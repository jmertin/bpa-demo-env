<?php
require_once __DIR__ . '/../lib/order.php';

$user    = auth_user();
$usecase = $_SESSION['usecase'] ?? '';

// If ?id is set, show single order confirmation.
$orderId = validate_int($_GET['id'] ?? null, 1) ?? 0;

if ($orderId > 0) {
  $order = order_get($orderId);
  if (!$order) {
    http_response_code(404);
    $pageTitle = APP_NAME . ' – Order Not Found';
    set_monitoring_headers('ORDER', 'VIEW', 'NOTFOUND', $user ? $user['role'] : 'anonymous', 0, '', $usecase);
    require __DIR__ . '/../templates/layout.php';
    echo '<div class="alert alert-error">Order not found.</div>';
    require __DIR__ . '/../templates/footer.php';
    exit;
  }

  // Target is a fixed string, not the order ID: BPA groups business
  // transactions by the full X-Page-ID, so a numeric target here would
  // create one distinct metric path per checkout instead of one shared
  // "ORDER-CONFIRM-SUCCESS" path for the whole order-confirmation page.
  set_monitoring_headers(
    'ORDER', 'CONFIRM', 'SUCCESS',
    $user ? $user['role'] : 'anonymous',
    0,
    '',
    $usecase
  );

  $pageTitle = APP_NAME . ' – Order #' . $orderId . ' Confirmed';
  require __DIR__ . '/../templates/layout.php';
  ?>

  <div class="order-confirm">
    <div class="order-confirm-icon">✅</div>
    <div style="font-size:1.2rem;font-weight:700;margin-bottom:.5rem">Thank you for your order!</div>
    <div class="order-confirm-num">Order #<?= $orderId ?></div>
    <p style="color:#607d8b;margin:.8rem 0">A confirmation would be sent to <strong><?= htmlspecialchars($order['billing_email']) ?></strong> in a real shop.</p>
  </div>

  <div class="card" style="max-width:600px;margin:0 auto">
    <h2>Order details</h2>
    <table class="basket-table">
      <thead>
        <tr><th>Product</th><th>Qty</th><th>Unit price</th><th>Subtotal</th></tr>
      </thead>
      <tbody>
        <?php foreach ($order['items'] as $item): ?>
        <tr>
          <td><?= htmlspecialchars($item['product_name']) ?></td>
          <td><?= (int) $item['quantity'] ?></td>
          <td>€<?= number_format((float) $item['unit_price'], 2) ?></td>
          <td>€<?= number_format((float) $item['unit_price'] * $item['quantity'], 2) ?></td>
        </tr>
        <?php endforeach ?>
      </tbody>
      <tfoot>
        <tr class="basket-total-row">
          <td colspan="3" style="text-align:right">Total paid</td>
          <td>€<?= number_format((float) $order['total'], 2) ?></td>
        </tr>
      </tfoot>
    </table>
    <p style="font-size:.8rem;color:#90a4ae;margin-top:.8rem">
      Billed to: <?= htmlspecialchars($order['billing_name']) ?> · Card ending ****<?= htmlspecialchars($order['cc_last4']) ?>
    </p>
  </div>

  <div style="text-align:center;margin-top:1.5rem">
    <a href="/index.php?page=shop" class="btn btn-primary">Continue shopping</a>
  </div>

  <?php
}
else {
  // List user's orders.
  if (!$user) {
    header('Location: /index.php?page=login');
    exit;
  }

  $orders = order_list_for_user((int) $user['id']);

  set_monitoring_headers(
    'ORDER', 'LIST', 'USER',
    $user['role'],
    basket_total(),
    '',
    $usecase
  );

  $pageTitle = APP_NAME . ' – My Orders';
  require __DIR__ . '/../templates/layout.php';
  ?>

  <div class="section-title" style="margin-bottom:1.2rem">📦 My Orders</div>

  <?php if (empty($orders)): ?>
    <div class="alert alert-info">You haven't placed any orders yet. <a href="/index.php?page=shop">Start shopping →</a></div>
  <?php else: ?>
  <table class="admin-table">
    <thead>
      <tr>
        <th>#</th><th>Date</th><th>Status</th><th>Total</th><th></th>
      </tr>
    </thead>
    <tbody>
      <?php foreach ($orders as $o): ?>
      <tr>
        <td><?= (int) $o['id'] ?></td>
        <td><?= htmlspecialchars($o['created_at']) ?></td>
        <td><?= htmlspecialchars($o['status']) ?></td>
        <td>€<?= number_format((float) $o['total'], 2) ?></td>
        <td><a href="/index.php?page=order&id=<?= (int) $o['id'] ?>" class="btn btn-secondary btn-sm">View</a></td>
      </tr>
      <?php endforeach ?>
    </tbody>
  </table>
  <?php endif ?>

<?php
}
require __DIR__ . '/../templates/footer.php';
