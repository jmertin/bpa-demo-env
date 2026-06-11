<?php
require_once __DIR__ . '/../lib/product.php';

$slug = validate_slug($_GET['slug'] ?? '') ?? '';
if ($slug === '') {
    header('Location: ?page=shop');
    exit;
}

$product = product_get_by_slug($slug);
if (!$product) {
    http_response_code(404);
    $pageTitle = APP_NAME . ' – Not Found';
    require __DIR__ . '/../templates/layout.php';
    echo '<div class="alert alert-error">Product not found.</div>';
    require __DIR__ . '/../templates/footer.php';
    exit;
}

$user    = auth_user();
$usecase = $_SESSION['usecase'] ?? '';
set_monitoring_headers(
    'PRODUCT', 'VIEW', strtoupper(preg_replace('/[^a-z0-9]/i', '', $product['brand_slug'])),
    $user ? $user['role'] : 'anonymous',
    basket_total(),
    '',
    $usecase
);

$pageTitle = APP_NAME . ' – ' . $product['name'];
$brandIcon = ['shelly' => '🔵', 'sonoff' => '🔴', 'tuya' => '🟠'];

require __DIR__ . '/../templates/layout.php';
?>

<nav style="font-size:.85rem;color:#607d8b;margin-bottom:1rem">
  <a href="?page=shop">Shop</a> &rsaquo;
  <a href="?page=shop&brand=<?= htmlspecialchars($product['brand_slug']) ?>"><?= htmlspecialchars($product['brand_name']) ?></a> &rsaquo;
  <?= htmlspecialchars($product['name']) ?>
</nav>

<div class="product-detail">
  <div class="product-detail-header">
    <div class="product-detail-img" style="background:linear-gradient(135deg,#<?= $product['brand_color'] ?>22,#<?= $product['brand_color'] ?>44)">
      <?= $brandIcon[$product['brand_slug']] ?? '📦' ?>
    </div>
    <div class="product-detail-meta">
      <div class="product-detail-brand" style="color:#<?= htmlspecialchars($product['brand_color']) ?>">
        <?= htmlspecialchars($product['brand_name']) ?>
      </div>
      <div class="product-detail-name"><?= htmlspecialchars($product['name']) ?></div>
      <div class="product-detail-desc"><?= htmlspecialchars($product['description']) ?></div>

      <div class="product-caps" style="margin:.6rem 0">
        <?php foreach ($product['capabilities'] as $cap): ?>
          <span class="cap-pill" style="background:#<?= htmlspecialchars($cap['color']) ?>"><?= htmlspecialchars($cap['name']) ?></span>
        <?php endforeach ?>
      </div>

      <div class="product-detail-price">€<?= number_format((float)$product['price'], 2) ?></div>
      <div class="product-stock" style="margin:.4rem 0">In stock: <?= (int)$product['stock'] ?> units</div>

      <form method="post" action="?page=basket" style="display:flex;gap:.7rem;align-items:center;margin-top:1rem">
        <input type="hidden" name="csrf_token" value="<?= csrf_token() ?>">
        <input type="hidden" name="action"     value="add">
        <input type="hidden" name="product_id" value="<?= (int)$product['id'] ?>">
        <input type="number" name="qty" value="1" min="1" max="99" style="width:60px;padding:.4rem;border:1px solid #cfd8dc;border-radius:6px;text-align:center">
        <button type="submit" class="btn btn-primary">Add to Basket 🛒</button>
      </form>
    </div>
  </div>
</div>

<div style="margin-top:1rem">
  <a href="?page=shop&brand=<?= htmlspecialchars($product['brand_slug']) ?>" class="btn btn-secondary">&larr; Back to <?= htmlspecialchars($product['brand_name']) ?></a>
</div>

<?php require __DIR__ . '/../templates/footer.php' ?>
