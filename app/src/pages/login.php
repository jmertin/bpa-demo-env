<?php
// Redirect if already logged in
if (auth_user()) {
    header('Location: ?page=shop');
    exit;
}

$error  = '';
$values = [];

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    csrf_verify();

    $username = validate_username($_POST['username'] ?? '');
    $password = validate_password($_POST['password'] ?? '');
    $values['username'] = $username ?? '';

    if ($username === null || $password === null) {
        $error = 'Invalid username or password format.';
    } elseif (!auth_login($username, $password)) {
        $error = 'Invalid username or password.';
    } else {
        $redirect = validate_slug($_GET['from'] ?? 'shop') ?? 'shop';
        header("Location: ?page={$redirect}");
        exit;
    }
}

set_monitoring_headers('AUTH', 'LOGIN', 'FORM', 'anonymous', 0, $error ? 'LOGIN_FAILED' : '');

$pageTitle = APP_NAME . ' – Login';
require __DIR__ . '/../templates/layout.php';
?>

<div class="login-wrap">
  <div class="login-title">🔐 Sign in</div>

  <?php if ($error): ?>
    <div class="alert alert-error"><?= htmlspecialchars($error) ?></div>
  <?php endif ?>

  <div class="card">
    <form method="post">
      <input type="hidden" name="csrf_token" value="<?= csrf_token() ?>">
      <div class="form-group">
        <label>Username</label>
        <input type="text" name="username" value="<?= htmlspecialchars($values['username'] ?? '') ?>"
               autofocus autocomplete="username" maxlength="50">
      </div>
      <div class="form-group">
        <label>Password</label>
        <input type="password" name="password" autocomplete="current-password">
      </div>
      <button type="submit" class="btn btn-primary" style="width:100%;padding:.6rem">Sign in</button>
    </form>
  </div>

  <p style="text-align:center;font-size:.8rem;color:#90a4ae;margin-top:1rem">
    Demo accounts: admin / alice / bob / charlie… &nbsp;|&nbsp; password: <code>demo123</code>
  </p>
</div>

<?php require __DIR__ . '/../templates/footer.php' ?>
