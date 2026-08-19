<?php
// Consume any flash error set by usecase_locked (before auth_user() redirect).
$error = '';
$usecase = '';
if (!empty($_SESSION['login_error'])) {
  $error = $_SESSION['login_error'];
  unset($_SESSION['login_error']);
  if ($error === 'Locked by admin. Please contact site admin') {
    $usecase = 'locked';
  }
}

// Redirect if already logged in.
if (auth_user()) {
  header('Location: /index.php?page=shop');
  exit;
}

$values = [];

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
  csrf_verify();

  $username = validate_username($_POST['username'] ?? '');
  $password = validate_password($_POST['password'] ?? '');
  $values['username'] = $username ?? '';

  if ($username === null || $password === null) {
    $error = 'Invalid username or password format.';
  }
  elseif (!auth_login($username, $password)) {
    $error = 'Invalid username or password.';
  }
  elseif (($_SESSION['usecase'] ?? '') === 'locked') {
    // Credential was valid but the account is locked — revoke immediately.
    foreach (['user_id', 'username', 'role', 'full_name', 'usecase', 'csrf_token'] as $key) {
      unset($_SESSION[$key]);
    }
    // The form below is about to re-render on this same request and needs a
    // token for the retry submission — regenerate one now that the old
    // token was wiped, otherwise csrf_token() reads an unset array key and
    // its `: string` return type turns that into an uncaught TypeError
    // (HTTP 500) instead of the 403 below.
    $_SESSION['csrf_token'] = bin2hex(random_bytes(32));
    $error = 'Locked by admin. Please contact site admin';
    $usecase = 'locked';
  }
  else {
    $redirect = validate_slug($_GET['from'] ?? 'shop') ?? 'shop';
    header("Location: /index.php?page={$redirect}");
    exit;
  }
}

if ($usecase === 'locked') {
  http_response_code(403);
}

set_monitoring_headers(
  'AUTH', 'LOGIN', 'FORM', 'anonymous', 0,
  $usecase === 'locked' ? 'LOGIN_LOCKED' : ($error ? 'LOGIN_FAILED' : ''),
  $usecase
);

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
