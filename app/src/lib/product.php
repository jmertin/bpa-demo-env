<?php
// Product and catalogue helpers.

require_once __DIR__ . '/../config/database.php';

/**
 * Returns all brands for the navigation sidebar.
 */
function product_get_brands(): array
{
    return db()->query(
        'SELECT id, name, slug, color, description FROM brands ORDER BY name'
    )->fetchAll();
}

/**
 * Returns all capabilities for the filter panel.
 */
function product_get_capabilities(): array
{
    return db()->query(
        'SELECT id, name, slug, color FROM capabilities ORDER BY name'
    )->fetchAll();
}

/**
 * Returns paginated products with optional filters.
 *
 * Filters array keys (all optional):
 *   brand_id    int
 *   cap_id      int
 *   search      string (searches name + description)
 *   min_price   float
 *   max_price   float
 *   page        int (1-based, default 1)
 *   per_page    int (default 24)
 *
 * Returns: ['products' => [...], 'total' => int, 'pages' => int]
 */
function product_list(array $filters = []): array
{
    $page     = max(1, (int)($filters['page']     ?? 1));
    $per_page = max(1, (int)($filters['per_page'] ?? 24));
    $offset   = ($page - 1) * $per_page;

    [$where, $params] = _product_where($filters);

    $countSql = "
        SELECT COUNT(DISTINCT p.id)
        FROM products p
        JOIN brands b ON b.id = p.brand_id
        {$where}
    ";
    $total = (int)db()->prepare($countSql)->execute($params) ? 0 : 0;
    $countStmt = db()->prepare($countSql);
    $countStmt->execute($params);
    $total = (int)$countStmt->fetchColumn();

    $sql = "
        SELECT p.id, p.name, p.slug, p.description, p.price, p.stock,
               b.id AS brand_id, b.name AS brand_name, b.slug AS brand_slug, b.color AS brand_color,
               GROUP_CONCAT(c.name ORDER BY c.name SEPARATOR ',') AS caps,
               GROUP_CONCAT(c.slug ORDER BY c.name SEPARATOR ',') AS cap_slugs,
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
        'pages'    => max(1, (int)ceil($total / $per_page)),
        'page'     => $page,
        'per_page' => $per_page,
    ];
}

/**
 * Returns a single product by slug, including capability list.
 */
function product_get_by_slug(string $slug): ?array
{
    $stmt = db()->prepare("
        SELECT p.id, p.name, p.slug, p.description, p.price, p.stock,
               b.id AS brand_id, b.name AS brand_name, b.slug AS brand_slug, b.color AS brand_color,
               GROUP_CONCAT(c.name ORDER BY c.name SEPARATOR ',') AS caps,
               GROUP_CONCAT(c.slug ORDER BY c.name SEPARATOR ',') AS cap_slugs,
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
 */
function product_get_by_id(int $id): ?array
{
    $stmt = db()->prepare("
        SELECT p.id, p.name, p.slug, p.description, p.price, p.stock,
               b.id AS brand_id, b.name AS brand_name, b.slug AS brand_slug, b.color AS brand_color,
               GROUP_CONCAT(c.name ORDER BY c.name SEPARATOR ',') AS caps,
               GROUP_CONCAT(c.slug ORDER BY c.name SEPARATOR ',') AS cap_slugs,
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

function _product_where(array $filters): array
{
    $clauses = [];
    $params  = [];

    if (!empty($filters['brand_id'])) {
        $clauses[] = 'p.brand_id = ?';
        $params[]  = (int)$filters['brand_id'];
    }
    if (!empty($filters['cap_id'])) {
        $clauses[] = 'EXISTS (
            SELECT 1 FROM product_capabilities pc2
            WHERE pc2.product_id = p.id AND pc2.capability_id = ?
        )';
        $params[] = (int)$filters['cap_id'];
    }
    if (!empty($filters['search'])) {
        $clauses[] = '(p.name LIKE ? OR p.description LIKE ?)';
        $like = '%' . addcslashes($filters['search'], '%_\\') . '%';
        $params[]  = $like;
        $params[]  = $like;
    }
    if (isset($filters['min_price'])) {
        $clauses[] = 'p.price >= ?';
        $params[]  = (float)$filters['min_price'];
    }
    if (isset($filters['max_price'])) {
        $clauses[] = 'p.price <= ?';
        $params[]  = (float)$filters['max_price'];
    }

    $where = $clauses ? 'WHERE ' . implode(' AND ', $clauses) : '';
    return [$where, $params];
}

function _product_decode_caps(array $row): array
{
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
