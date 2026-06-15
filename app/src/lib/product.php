<?php
// Product and catalogue helpers.

require_once __DIR__ . '/../config/database.php';

/**
 * Returns all brands for the navigation sidebar.
 *
 * @return array
 *   Indexed array of brand rows (id, name, slug, color, description), ordered
 *   by name.
 */
function product_get_brands(): array {
  return db()->query(
    'SELECT id, name, slug, color, description FROM brands ORDER BY name'
  )->fetchAll();
}

/**
 * Returns all capabilities for the filter panel.
 *
 * @return array
 *   Indexed array of capability rows (id, name, slug, color), ordered by name.
 */
function product_get_capabilities(): array {
  return db()->query(
    'SELECT id, name, slug, color FROM capabilities ORDER BY name'
  )->fetchAll();
}

/**
 * Returns paginated products with optional filters.
 *
 * Accepted keys in $filters (all optional):
 *   brand_id  int    – filter by brand.
 *   cap_id    int    – filter by capability.
 *   search    string – full-text search on name + description.
 *   min_price float  – lower price bound.
 *   max_price float  – upper price bound.
 *   page      int    – 1-based page number (default 1).
 *   per_page  int    – items per page (default 24).
 *
 * @param array $filters
 *   Associative filter array (see above).
 *
 * @return array
 *   Associative array with keys: products (array), total (int), pages (int),
 *   page (int), per_page (int).
 */
function product_list(array $filters = []): array {
  $page     = max(1, (int) ($filters['page']     ?? 1));
  $per_page = max(1, (int) ($filters['per_page'] ?? 24));
  $offset   = ($page - 1) * $per_page;

  [$where, $params] = _product_where($filters);

  $countSql  = "
    SELECT COUNT(DISTINCT p.id)
    FROM products p
    JOIN brands b ON b.id = p.brand_id
    {$where}
  ";
  $countStmt = db()->prepare($countSql);
  $countStmt->execute($params);
  $total = (int) $countStmt->fetchColumn();

  $sql = "
    SELECT p.id, p.name, p.slug, p.description, p.price, p.stock, p.image_url,
           b.id AS brand_id, b.name AS brand_name, b.slug AS brand_slug, b.color AS brand_color,
           GROUP_CONCAT(c.name  ORDER BY c.name SEPARATOR ',') AS caps,
           GROUP_CONCAT(c.slug  ORDER BY c.name SEPARATOR ',') AS cap_slugs,
           GROUP_CONCAT(c.color ORDER BY c.name SEPARATOR ',') AS cap_colors
    FROM products p
    JOIN brands b ON b.id = p.brand_id
    LEFT JOIN product_capabilities pc ON pc.product_id = p.id
    LEFT JOIN capabilities c ON c.id = pc.capability_id
    {$where}
    GROUP BY p.id
    ORDER BY p.brand_id, p.id
    LIMIT ? OFFSET ?
  ";
  $stmt = db()->prepare($sql);
  $stmt->execute(array_merge($params, [$per_page, $offset]));
  $rows = $stmt->fetchAll();

  return [
    'products' => array_map('_product_decode_caps', $rows),
    'total'    => $total,
    'pages'    => max(1, (int) ceil($total / $per_page)),
    'page'     => $page,
    'per_page' => $per_page,
  ];
}

/**
 * Returns a single product by slug, including capability list.
 *
 * @param string $slug
 *   URL slug of the product.
 *
 * @return array|null
 *   Product row decorated with a 'capabilities' key, or NULL when not found.
 */
function product_get_by_slug(string $slug): ?array {
  $stmt = db()->prepare("
    SELECT p.id, p.name, p.slug, p.description, p.price, p.stock, p.image_url,
           b.id AS brand_id, b.name AS brand_name, b.slug AS brand_slug, b.color AS brand_color,
           GROUP_CONCAT(c.name  ORDER BY c.name SEPARATOR ',') AS caps,
           GROUP_CONCAT(c.slug  ORDER BY c.name SEPARATOR ',') AS cap_slugs,
           GROUP_CONCAT(c.color ORDER BY c.name SEPARATOR ',') AS cap_colors
    FROM products p
    JOIN brands b ON b.id = p.brand_id
    LEFT JOIN product_capabilities pc ON pc.product_id = p.id
    LEFT JOIN capabilities c ON c.id = pc.capability_id
    WHERE p.slug = ?
    GROUP BY p.id
  ");
  $stmt->execute([$slug]);
  $row = $stmt->fetch();
  return $row ? _product_decode_caps($row) : null;
}

/**
 * Returns a single product by ID.
 *
 * @param int $id
 *   Primary key of the product.
 *
 * @return array|null
 *   Product row decorated with a 'capabilities' key, or NULL when not found.
 */
function product_get_by_id(int $id): ?array {
  $stmt = db()->prepare("
    SELECT p.id, p.name, p.slug, p.description, p.price, p.stock, p.image_url,
           b.id AS brand_id, b.name AS brand_name, b.slug AS brand_slug, b.color AS brand_color,
           GROUP_CONCAT(c.name  ORDER BY c.name SEPARATOR ',') AS caps,
           GROUP_CONCAT(c.slug  ORDER BY c.name SEPARATOR ',') AS cap_slugs,
           GROUP_CONCAT(c.color ORDER BY c.name SEPARATOR ',') AS cap_colors
    FROM products p
    JOIN brands b ON b.id = p.brand_id
    LEFT JOIN product_capabilities pc ON pc.product_id = p.id
    LEFT JOIN capabilities c ON c.id = pc.capability_id
    WHERE p.id = ?
    GROUP BY p.id
  ");
  $stmt->execute([$id]);
  $row = $stmt->fetch();
  return $row ? _product_decode_caps($row) : null;
}

// ── Internal helpers ─────────────────────────────────────────────────────────

/**
 * Builds the WHERE clause and parameter array for product queries.
 *
 * @param array $filters
 *   Same filter keys accepted by product_list().
 *
 * @return array
 *   Two-element array: [where_string, params_array].
 */
function _product_where(array $filters): array {
  $clauses = [];
  $params  = [];

  if (!empty($filters['brand_id'])) {
    $clauses[] = 'p.brand_id = ?';
    $params[]  = (int) $filters['brand_id'];
  }
  if (!empty($filters['cap_id'])) {
    $clauses[] = 'EXISTS (
      SELECT 1 FROM product_capabilities pc2
      WHERE pc2.product_id = p.id AND pc2.capability_id = ?
    )';
    $params[] = (int) $filters['cap_id'];
  }
  if (!empty($filters['search'])) {
    $clauses[] = '(p.name LIKE ? OR p.description LIKE ?)';
    $like      = '%' . addcslashes($filters['search'], '%_\\') . '%';
    $params[]  = $like;
    $params[]  = $like;
  }
  if (isset($filters['min_price'])) {
    $clauses[] = 'p.price >= ?';
    $params[]  = (float) $filters['min_price'];
  }
  if (isset($filters['max_price'])) {
    $clauses[] = 'p.price <= ?';
    $params[]  = (float) $filters['max_price'];
  }

  $where = $clauses ? 'WHERE ' . implode(' AND ', $clauses) : '';
  return [$where, $params];
}

/**
 * Converts comma-separated capability columns in a product row to a structured
 * 'capabilities' array, removing the raw columns.
 *
 * @param array $row
 *   Raw product row from PDO containing caps, cap_slugs, cap_colors columns.
 *
 * @return array
 *   Product row with caps/cap_slugs/cap_colors replaced by a 'capabilities'
 *   array of ['name', 'slug', 'color'] maps.
 */
function _product_decode_caps(array $row): array {
  $names  = $row['caps']       ? explode(',', $row['caps'])       : [];
  $slugs  = $row['cap_slugs']  ? explode(',', $row['cap_slugs'])  : [];
  $colors = $row['cap_colors'] ? explode(',', $row['cap_colors']) : [];

  $caps = [];
  foreach ($names as $i => $name) {
    $caps[] = [
      'name'  => $name,
      'slug'  => $slugs[$i]  ?? '',
      'color' => $colors[$i] ?? '888888',
    ];
  }

  unset($row['caps'], $row['cap_slugs'], $row['cap_colors']);
  $row['capabilities'] = $caps;
  return $row;
}
