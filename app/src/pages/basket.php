<?php
// Handle POST actions first (before any output)
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    csrf_verify();
    $action    = validate_string($_POST['action'] ?? '', 1, 20) ?? '';
    $productId = validate_int($_POST['product_id'] ?? null, 1) ?? 0;

    if ($productId > 0) {
        switch ($action) {
            case 'add':
                $qty = validate_int($_POST['qty'] ?? 1, 1, 99) ?? 1;
                basket_add($productId, $qty);
                break;
            case 'remove':
                basket_remove($productId);
                break;
            case 'update':
                $qty = validate_int($_POST['qty'] ?? 1, 0, 99) ?? 0;
                basket_set_qty($productId, $qty);
                break;
        }
    }
    if ($action === 'clear') {
        basket_clear();
    }

    // POST–Redirect–GET to prevent double-submit
    header('Location: ?page=basket');
    exit;
}

// ── GET: display basket ───────────────────────────────────────────────────────
$user    = auth_user();
$usecase = $_SESSION['usecase'] ?? '';
$total   = basket_total();

set_monitoring_headers(
    'BASKET', 'VIEW', 'CART',
    $user ? $user['role'] : 'anonymous',
    $total,
    '',
    $usecase
);

$pageTitle = APP_NAME . ' – Basket';
$items = basket_items();

require __DIR__ . '/../templates/layout.php';
?>

<div class="section-header">
  <span class="section-title">🛒 Shopping Basket</span>
  <?php if (!empty($items)): ?>
    <form method="post">
      <input type="hidden" name="csrf_token" value="<?= csrf_token() ?>">
      <input type="hidden" name="action" value="clear">
      <button type="submit" class="btn btn-danger btn-sm">Clear basket</button>
    </form>
  <?php endif ?>
</div>

<?php if (!empty($usecase) && $usecase === 'empty_basket'): ?>
  <div class="alert alert-info">ℹ Promotional pricing active: total shown as €0.00</div>
<?php endif ?>

<?php if (empty($items)): ?>
  <div class="alert alert-info">Your basket is empty. <a href="?page=shop">Continue shopping →</a></div>
<?php else: ?>

<table class="basket-table">
  <thead>
    <tr>
      <th>Product</th>
      <th>Brand</th>
      <th>Unit price</th>
      <th>Qty</th>
      <th>Subtotal</th>
      <th></th>
    </tr>
  </thead>
  <tbody>
    <?php foreach ($items as $item): ?>
    <tr>
      <td>
        <a href="?page=product&slug=<?= htmlspecialchars($item['product']['slug']) ?>">
          <?= htmlspecialchars($item['product']['name']) ?>
        </a>
      </td>
      <td><span class="product-brand" style="color:#<?= htmlspecialchars($item['product']['brand_color']) ?>"><?= htmlspecialchars($item['product']['brand_name']) ?></span></td>
      <td>€<?= number_format((float)$item['product']['price'], 2) ?></td>
      <td>
        <form method="post" style="display:flex;gap:.3rem">
          <input type="hidden" name="csrf_token"  value="<?= csrf_token() ?>">
          <input type="hidden" name="action"      value="update">
          <input type="hidden" name="product_id"  value="<?= (int)$item['product']['id'] ?>">
          <input type="number" name="qty" value="<?= (int)$item['qty'] ?>" min="0" max="99" class="qty-input">
          <button type="submit" class="btn btn-secondary btn-sm">↻</button>
        </form>
      </td>
      <td>€<?= number_format($item['subtotal'], 2) ?></td>
      <td>
        <form method="post">
          <input type="hidden" name="csrf_token"  value="<?= csrf_token() ?>">
          <input type="hidden" name="action"      value="remove">
          <input type="hidden" name="product_id"  value="<?= (int)$item['product']['id'] ?>">
          <button type="submit" class="btn btn-danger btn-sm">✕</button>
        </form>
      </td>
    </tr>
    <?php endforeach ?>
  </tbody>
  <tfoot>
    <tr class="basket-total-row">
      <td colspan="4" style="text-align:right">Total</td>
      <td>€<?= number_format($total, 2) ?></td>
      <td></td>
    </tr>
  </tfoot>
</table>

<div style="margin-top:1.2rem;display:flex;gap:.8rem;justify-content:flex-end">
  <a href="?page=shop" class="btn btn-secondary">&larr; Continue shopping</a>
  <a href="?page=checkout" class="btn btn-primary">Proceed to checkout →</a>
</div>
<?php endif ?>

<?php require __DIR__ . '/../templates/footer.php' ?>
