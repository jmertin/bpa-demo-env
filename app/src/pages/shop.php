<?php
require_once __DIR__ . '/../lib/product.php';

// ── Resolve filters ────────────────────────────────────────────────────────────
$brandSlug = validate_slug($_GET['brand'] ?? '') ?? '';
$capSlug   = validate_slug($_GET['cap']   ?? '') ?? '';
$search    = validate_string($_GET['q']   ?? '', 0, 100) ?? '';
$minPrice  = validate_price($_GET['min_price'] ?? '') ?? null;
$maxPrice  = validate_price($_GET['max_price'] ?? '') ?? null;
$pageNum   = validate_int($_GET['p'] ?? 1, 1, 9999) ?? 1;

// Resolve brand_id from slug.
$brandId = null;
if ($brandSlug !== '') {
  foreach (product_get_brands() as $b) {
    if ($b['slug'] === $brandSlug) {
      $brandId = (int) $b['id'];
      break;
    }
  }
}

// Resolve cap_id from slug.
$capId = null;
if ($capSlug !== '') {
  foreach (product_get_capabilities() as $c) {
    if ($c['slug'] === $capSlug) {
      $capId = (int) $c['id'];
      break;
    }
  }
}

$result = product_list([
  'brand_id'  => $brandId,
  'cap_id'    => $capId,
  'search'    => $search,
  'min_price' => $minPrice,
  'max_price' => $maxPrice,
  'page'      => $pageNum,
  'per_page'  => 24,
]);

// ── Monitoring headers ─────────────────────────────────────────────────────────
$user    = auth_user();
$usecase = $_SESSION['usecase'] ?? '';
$target  = $brandSlug ?: ($capSlug ?: 'all');
set_monitoring_headers(
  'SHOP', 'LIST', $target,
  $user ? $user['role'] : 'anonymous',
  basket_total(),
  '',
  $usecase
);

// ── Build page title ───────────────────────────────────────────────────────────
$pageTitle = APP_NAME . ' – Shop';
if ($brandSlug) {
  $pageTitle = APP_NAME . ' – ' . ucfirst($brandSlug);
}
elseif ($capSlug) {
  $pageTitle = APP_NAME . ' – ' . ucfirst($capSlug) . ' devices';
}
elseif ($search) {
  $pageTitle = APP_NAME . ' – Search: ' . htmlspecialchars($search);
}

// ── Brand icon map ─────────────────────────────────────────────────────────────
$brandIcon = ['shelly' => '🔵', 'sonoff' => '🔴', 'tuya' => '🟠'];

require __DIR__ . '/../templates/layout.php';
?>

<div class="section-header">
  <span class="section-title">
    <?php if ($brandSlug): ?>
      <?= $brandIcon[$brandSlug] ?? '📦' ?> <?= htmlspecialchars(ucfirst($brandSlug)) ?> Products
    <?php elseif ($capSlug): ?>
      📡 <?= htmlspecialchars(ucfirst(str_replace('-', ' ', $capSlug))) ?> Devices
    <?php elseif ($search): ?>
      🔍 Results for "<?= htmlspecialchars($search) ?>"
    <?php else: ?>
      All Products
    <?php endif ?>
  </span>
  <span class="result-count"><?= $result['total'] ?> product<?= $result['total'] !== 1 ? 's' : '' ?></span>
</div>

<!-- Filter bar -->
<form method="get" action="/index.php" class="filter-bar">
  <input type="hidden" name="page" value="shop">
  <?php if ($brandSlug): ?><input type="hidden" name="brand" value="<?= htmlspecialchars($brandSlug) ?>"><?php endif ?>
  <?php if ($capSlug): ?><input type="hidden" name="cap"   value="<?= htmlspecialchars($capSlug) ?>"><?php endif ?>
  <div class="filter-group" style="flex:2;min-width:180px">
    <label>Search</label>
    <input type="text" name="q" value="<?= htmlspecialchars($search) ?>" placeholder="Product name…">
  </div>
  <div class="filter-group">
    <label>Min price €</label>
    <input type="text" name="min_price" value="<?= $minPrice !== null ? htmlspecialchars((string) $minPrice) : '' ?>" placeholder="0">
  </div>
  <div class="filter-group">
    <label>Max price €</label>
    <input type="text" name="max_price" value="<?= $maxPrice !== null ? htmlspecialchars((string) $maxPrice) : '' ?>" placeholder="999">
  </div>
  <button type="submit" class="btn btn-primary">Filter</button>
  <a href="/index.php?page=shop" class="btn btn-secondary">Reset</a>
</form>

<!-- Product grid -->
<?php if (empty($result['products'])): ?>
  <div class="alert alert-info">No products found matching your criteria.</div>
<?php else: ?>
<div class="product-grid">
  <?php foreach ($result['products'] as $p): ?>
  <div class="product-card">
    <div class="product-card-img" style="background:linear-gradient(135deg,#<?= $p['brand_color'] ?>22,#<?= $p['brand_color'] ?>44)">
      <?php if (!empty($p['image_url'])): ?>
        <img src="<?= htmlspecialchars($p['image_url']) ?>"
             alt="<?= htmlspecialchars($p['name']) ?>"
             style="width:100%;height:100%;object-fit:contain;padding:8px"
             loading="lazy"
             onerror="this.style.display='none';this.nextElementSibling.style.display='block'">
        <span style="display:none;font-size:2.5rem"><?= $brandIcon[$p['brand_slug']] ?? '📦' ?></span>
      <?php else: ?>
        <span style="font-size:2.5rem"><?= $brandIcon[$p['brand_slug']] ?? '📦' ?></span>
      <?php endif ?>
    </div>
    <div class="product-card-body">
      <div class="product-brand" style="color:#<?= htmlspecialchars($p['brand_color']) ?>">
        <?= htmlspecialchars($p['brand_name']) ?>
      </div>
      <div class="product-name">
        <a href="/index.php?page=product&slug=<?= htmlspecialchars($p['slug']) ?>">
          <?= htmlspecialchars($p['name']) ?>
        </a>
      </div>
      <div class="product-desc"><?= htmlspecialchars($p['description']) ?></div>
      <div class="product-caps">
        <?php foreach ($p['capabilities'] as $cap): ?>
          <span class="cap-pill" style="background:#<?= htmlspecialchars($cap['color']) ?>"><?= htmlspecialchars($cap['name']) ?></span>
        <?php endforeach ?>
      </div>
      <div class="product-price">€<?= number_format((float) $p['price'], 2) ?></div>
      <div class="product-stock">Stock: <?= (int) $p['stock'] ?></div>
    </div>
    <div class="product-card-footer">
      <a href="/index.php?page=product&slug=<?= htmlspecialchars($p['slug']) ?>" class="btn btn-secondary btn-sm" style="flex:1;text-align:center">Details</a>
      <form method="post" action="/index.php?page=basket" style="flex:1">
        <input type="hidden" name="csrf_token" value="<?= csrf_token() ?>">
        <input type="hidden" name="action"     value="add">
        <input type="hidden" name="product_id" value="<?= (int) $p['id'] ?>">
        <button type="submit" class="btn btn-primary btn-sm" style="width:100%">Add 🛒</button>
      </form>
    </div>
  </div>
  <?php endforeach ?>
</div>

<!-- Pagination -->
<?php if ($result['pages'] > 1): ?>
<div class="pagination">
  <?php for ($i = 1; $i <= $result['pages']; $i++): ?>
    <?php
    $params = array_filter([
      'page'      => 'shop',
      'brand'     => $brandSlug,
      'cap'       => $capSlug,
      'q'         => $search,
      'min_price' => $minPrice,
      'max_price' => $maxPrice,
      'p'         => $i,
    ], fn($v) => $v !== '' && $v !== null);
    ?>
    <a href="/index.php?<?= http_build_query($params) ?>"
       class="page-link <?= $i === $pageNum ? 'active' : '' ?>"><?= $i ?></a>
  <?php endfor ?>
</div>
<?php endif ?>
<?php endif ?>

<?php require __DIR__ . '/../templates/footer.php' ?>
