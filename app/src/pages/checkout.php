<?php
require_once __DIR__ . '/../lib/order.php';

$user    = auth_user();
$usecase = $_SESSION['usecase'] ?? '';
$items   = basket_items();
$total   = basket_total();

if (empty($items)) {
    header('Location: ?page=basket');
    exit;
}

$errors = [];
$values = [];

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    csrf_verify();

    $values['billing_name']  = validate_string($_POST['billing_name']  ?? '', 2, 200);
    $values['billing_email'] = validate_email($_POST['billing_email']  ?? '');
    $values['cc_number']     = validate_cc_number($_POST['cc_number']  ?? '');
    $values['cc_expiry']     = validate_cc_expiry($_POST['cc_expiry']  ?? '');
    $values['cc_cvv']        = validate_cvv($_POST['cc_cvv']           ?? '');

    if ($values['billing_name']  === null) $errors['billing_name']  = 'Enter a valid name (2-200 chars).';
    if ($values['billing_email'] === null) $errors['billing_email'] = 'Enter a valid email address.';
    if ($values['cc_number']     === null) $errors['cc_number']     = 'Enter a valid card number (Luhn check failed).';
    if ($values['cc_expiry']     === null) $errors['cc_expiry']     = 'Enter a valid expiry (MM/YY, not in the past).';
    if ($values['cc_cvv']        === null) $errors['cc_cvv']        = 'Enter a valid CVV (3-4 digits).';

    if (empty($errors)) {
        $ccLast4  = substr(preg_replace('/\s+/', '', $values['cc_number']), -4);
        $userId   = $user ? (int)$user['id'] : null;
        $orderId  = order_create(
            $userId,
            $values['billing_name'],
            $values['billing_email'],
            $ccLast4
        );
        header("Location: ?page=order&id={$orderId}");
        exit;
    }
}

set_monitoring_headers(
    'CHECKOUT', 'FORM', 'PAYMENT',
    $user ? $user['role'] : 'anonymous',
    $total,
    empty($errors) ? '' : 'VALIDATION_ERRORS',
    $usecase
);

$pageTitle = APP_NAME . ' – Checkout';
require __DIR__ . '/../templates/layout.php';
?>

<div class="section-title" style="margin-bottom:1.2rem">💳 Checkout</div>

<?php if (!empty($errors)): ?>
  <div class="alert alert-error">Please correct the errors below.</div>
<?php endif ?>

<div class="checkout-grid">

  <!-- Billing + Payment form -->
  <form method="post">
    <input type="hidden" name="csrf_token" value="<?= csrf_token() ?>">

    <div class="card">
      <h2>Billing details</h2>
      <div class="form-group">
        <label>Full name *</label>
        <input type="text" name="billing_name"
               value="<?= htmlspecialchars($values['billing_name'] ?? ($user['full_name'] ?? '')) ?>"
               placeholder="Jane Smith">
        <?php if (isset($errors['billing_name'])): ?>
          <span class="form-error"><?= htmlspecialchars($errors['billing_name']) ?></span>
        <?php endif ?>
      </div>
      <div class="form-group">
        <label>Email address *</label>
        <input type="email" name="billing_email"
               value="<?= htmlspecialchars($values['billing_email'] ?? '') ?>"
               placeholder="jane@example.com">
        <?php if (isset($errors['billing_email'])): ?>
          <span class="form-error"><?= htmlspecialchars($errors['billing_email']) ?></span>
        <?php endif ?>
      </div>
    </div>

    <div class="card">
      <h2>Payment — credit card</h2>
      <div class="form-group">
        <label>Card number *</label>
        <input type="text" name="cc_number"
               value="<?= htmlspecialchars($values['cc_number'] ?? '') ?>"
               placeholder="4111 1111 1111 1111" maxlength="19">
        <?php if (isset($errors['cc_number'])): ?>
          <span class="form-error"><?= htmlspecialchars($errors['cc_number']) ?></span>
        <?php endif ?>
      </div>
      <div class="cc-row">
        <div class="form-group">
          <label>Expiry (MM/YY) *</label>
          <input type="text" name="cc_expiry"
                 value="<?= htmlspecialchars($values['cc_expiry'] ?? '') ?>"
                 placeholder="12/28" maxlength="5">
          <?php if (isset($errors['cc_expiry'])): ?>
            <span class="form-error"><?= htmlspecialchars($errors['cc_expiry']) ?></span>
          <?php endif ?>
        </div>
        <div class="form-group">
          <label>CVV *</label>
          <input type="text" name="cc_cvv"
                 value="" placeholder="123" maxlength="4" autocomplete="off">
          <?php if (isset($errors['cc_cvv'])): ?>
            <span class="form-error"><?= htmlspecialchars($errors['cc_cvv']) ?></span>
          <?php endif ?>
        </div>
      </div>
      <p style="font-size:.75rem;color:#90a4ae;margin-top:.5rem">
        ⚠ This is a demo application. No real payment is processed. Use any valid-format card number.
      </p>
    </div>

    <button type="submit" class="btn btn-success" style="width:100%;padding:.8rem">
      Place order &amp; pay €<?= number_format($total, 2) ?>
    </button>
  </form>

  <!-- Order summary -->
  <div>
    <div class="card">
      <h2>Order summary</h2>
      <div class="order-summary">
        <?php foreach ($items as $item): ?>
        <div class="order-summary-row">
          <span><?= htmlspecialchars($item['product']['name']) ?> ×<?= (int)$item['qty'] ?></span>
          <span>€<?= number_format($item['subtotal'], 2) ?></span>
        </div>
        <?php endforeach ?>
        <div class="order-summary-row" style="margin-top:.4rem">
          <span>Total</span>
          <span>€<?= number_format($total, 2) ?></span>
        </div>
      </div>
    </div>
    <a href="?page=basket" class="btn btn-secondary btn-sm">&larr; Edit basket</a>
  </div>

</div>

<?php require __DIR__ . '/../templates/footer.php' ?>
