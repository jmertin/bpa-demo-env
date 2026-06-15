<?php
require_once __DIR__ . '/../lib/usecase.php';

auth_require_admin();

$user      = auth_user();
$usecase   = $_SESSION['usecase'] ?? '';
$flash     = '';
$flashType = 'success';

// ── Handle POST actions ────────────────────────────────────────────────────────
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
  csrf_verify();
  $action       = validate_string($_POST['action']       ?? '', 1, 30)  ?? '';
  $targetUserId = validate_int($_POST['target_user_id']  ?? null, 1)    ?? 0;
  $usecaseName  = validate_string($_POST['usecase_name'] ?? '', 0, 100) ?? '';

  if ($targetUserId > 0) {
    if ($action === 'assign' && $usecaseName !== '') {
      usecase_assign($targetUserId, $usecaseName, (int) $user['id']);
      $flash = 'Use case assigned.';
    }
    elseif ($action === 'unassign') {
      usecase_unassign($targetUserId);
      $flash = 'Use case removed.';
    }
  }
  header('Location: ?page=admin');
  exit;
}

// ── Load data ──────────────────────────────────────────────────────────────────
$flash = $_GET['flash'] ?? '';

$users = db()->query("
  SELECT u.id, u.username, u.full_name, u.email, u.role, u.created_at,
         uu.usecase_name
  FROM users u
  LEFT JOIN user_usecases uu ON uu.user_id = u.id
  ORDER BY u.id
")->fetchAll();

$availableUsecases = usecase_available();

$stats = [
  'products' => (int) db()->query('SELECT COUNT(*) FROM products')->fetchColumn(),
  'orders'   => (int) db()->query('SELECT COUNT(*) FROM orders')->fetchColumn(),
  'users'    => (int) db()->query('SELECT COUNT(*) FROM users')->fetchColumn(),
];

set_monitoring_headers(
  'ADMIN', 'PANEL', 'DASHBOARD',
  'admin',
  basket_total(),
  '',
  $usecase
);

$pageTitle = APP_NAME . ' – Admin';
require __DIR__ . '/../templates/layout.php';
?>

<div class="section-title" style="margin-bottom:1.2rem">⚙ Admin Panel</div>

<!-- Stats -->
<div style="display:flex;gap:1rem;flex-wrap:wrap;margin-bottom:1.5rem">
  <?php foreach (['products' => '📦', 'orders' => '🛍', 'users' => '👤'] as $key => $icon): ?>
  <div class="card" style="flex:1;min-width:140px;text-align:center;margin-bottom:0;padding:1rem">
    <div style="font-size:1.8rem"><?= $icon ?></div>
    <div style="font-size:1.4rem;font-weight:700"><?= $stats[$key] ?></div>
    <div style="font-size:.8rem;color:#607d8b;text-transform:capitalize"><?= $key ?></div>
  </div>
  <?php endforeach ?>
</div>

<?php if ($flash): ?>
  <div class="alert alert-success"><?= htmlspecialchars($flash) ?></div>
<?php endif ?>

<!-- User / use-case management -->
<div class="card">
  <h2>Users &amp; Use-case assignments</h2>
  <table class="admin-table">
    <thead>
      <tr>
        <th>ID</th>
        <th>Username</th>
        <th>Full name</th>
        <th>Email</th>
        <th>Role</th>
        <th>Use case</th>
        <th>Actions</th>
      </tr>
    </thead>
    <tbody>
      <?php foreach ($users as $u): ?>
      <tr>
        <td><?= (int) $u['id'] ?></td>
        <td><strong><?= htmlspecialchars($u['username']) ?></strong></td>
        <td><?= htmlspecialchars($u['full_name'] ?? '') ?></td>
        <td style="font-size:.8rem;color:#607d8b"><?= htmlspecialchars($u['email'] ?? '') ?></td>
        <td>
          <span class="role-badge <?= $u['role'] === 'admin' ? 'role-admin' : 'role-user' ?>">
            <?= htmlspecialchars($u['role']) ?>
          </span>
        </td>
        <td>
          <?php if ($u['usecase_name']): ?>
            <span class="cap-pill" style="background:#7c83ff"><?= htmlspecialchars($u['usecase_name']) ?></span>
          <?php else: ?>
            <span style="color:#b0bec5;font-size:.8rem">none</span>
          <?php endif ?>
        </td>
        <td style="white-space:nowrap">
          <!-- Assign form -->
          <form method="post" style="display:inline-flex;gap:.3rem">
            <input type="hidden" name="csrf_token"      value="<?= csrf_token() ?>">
            <input type="hidden" name="action"          value="assign">
            <input type="hidden" name="target_user_id"  value="<?= (int) $u['id'] ?>">
            <select name="usecase_name" style="font-size:.8rem;padding:.2rem .4rem;border:1px solid #cfd8dc;border-radius:4px">
              <option value="">— assign —</option>
              <?php foreach ($availableUsecases as $uc): ?>
                <option value="<?= htmlspecialchars($uc) ?>" <?= $u['usecase_name'] === $uc ? 'selected' : '' ?>>
                  <?= htmlspecialchars($uc) ?>
                </option>
              <?php endforeach ?>
            </select>
            <button type="submit" class="btn btn-primary btn-sm">Set</button>
          </form>
          <?php if ($u['usecase_name']): ?>
          <!-- Unassign form -->
          <form method="post" style="display:inline-flex;margin-left:.3rem">
            <input type="hidden" name="csrf_token"     value="<?= csrf_token() ?>">
            <input type="hidden" name="action"         value="unassign">
            <input type="hidden" name="target_user_id" value="<?= (int) $u['id'] ?>">
            <button type="submit" class="btn btn-danger btn-sm">✕</button>
          </form>
          <?php endif ?>
        </td>
      </tr>
      <?php endforeach ?>
    </tbody>
  </table>
</div>

<?php require __DIR__ . '/../templates/footer.php' ?>
