<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title><?= htmlspecialchars($pageTitle ?? APP_NAME) ?></title>
<link rel="stylesheet" href="/css/app.css">
</head>
<body>

<?php /* ── Top navigation bar ──────────────────────────────────────────────── */ ?>
<header class="topbar">
  <a href="/index.php?page=shop" class="topbar-brand">🏠 <?= APP_NAME ?></a>
  <div class="topbar-right">
    <?php if (auth_user()): ?>
      <span class="topbar-user">
        <?php if (auth_is_admin()): ?>
          <a href="/index.php?page=admin" style="color:#ffd54f">⚙ Admin</a> &nbsp;
        <?php endif ?>
        Hi, <strong><?= htmlspecialchars(auth_user()['full_name'] ?: auth_user()['username']) ?></strong>
        &nbsp;|&nbsp;
        <a href="/index.php?page=logout" style="color:#ef9a9a">Logout</a>
      </span>
    <?php else: ?>
      <a href="/index.php?page=login" style="color:#b0bec5">Login</a>
    <?php endif ?>
    <a href="/index.php?page=basket" class="basket-badge">
      🛒 Basket
      <span class="count"><?= basket_count() ?></span>
      &nbsp;€<?= number_format(basket_total(), 2) ?>
    </a>
  </div>
</header>

<div class="page-wrapper">

<?php /* ── Sidebar ─────────────────────────────────────────────────────────── */ ?>
<aside class="sidebar">
  <div class="sidebar-section">
    <h3>Brands</h3>
    <a href="/index.php?page=shop" class="<?= empty($_GET['brand']) ? 'active' : '' ?>">All brands</a>
    <?php foreach (product_get_brands() as $b): ?>
      <a href="/index.php?page=shop&brand=<?= $b['slug'] ?>"
         class="<?= (($_GET['brand'] ?? '') === $b['slug']) ? 'active' : '' ?>">
        <span class="brand-dot" style="background:#<?= htmlspecialchars($b['color']) ?>"></span>
        <?= htmlspecialchars($b['name']) ?>
      </a>
    <?php endforeach ?>
  </div>

  <div class="sidebar-section">
    <h3>Protocol</h3>
    <a href="/index.php?page=shop" class="<?= empty($_GET['cap']) ? 'active' : '' ?>">All protocols</a>
    <?php foreach (product_get_capabilities() as $c): ?>
      <a href="/index.php?page=shop&cap=<?= $c['slug'] ?>"
         class="<?= (($_GET['cap'] ?? '') === $c['slug']) ? 'active' : '' ?>">
        <span class="brand-dot" style="background:#<?= htmlspecialchars($c['color']) ?>"></span>
        <?= htmlspecialchars($c['name']) ?>
      </a>
    <?php endforeach ?>
  </div>

  <div class="sidebar-section">
    <h3>Shop</h3>
    <a href="/index.php?page=basket">🛒 My Basket</a>
    <?php if (auth_user()): ?>
      <a href="/index.php?page=order">📦 My Orders</a>
    <?php endif ?>
    <?php if (auth_is_admin()): ?>
      <a href="/index.php?page=admin" class="<?= ($page === 'admin') ? 'active' : '' ?>">⚙ Admin Panel</a>
    <?php endif ?>
  </div>

  <?php if (auth_is_admin()): ?>
  <div class="sidebar-section">
    <h3>Diagnostics</h3>
    <a href="/index.php?page=dxo2" class="<?= ($page === 'dxo2') ? 'active' : '' ?>">&#128202; DX O2 Status</a>
    <a href="/index.php?page=info" class="<?= ($page === 'info') ? 'active' : '' ?>">&#128196; PHP Info</a>
    <a href="/index.php?page=db"   class="<?= ($page === 'db')   ? 'active' : '' ?>">&#128421; Database</a>
  </div>
  <?php endif ?>
</aside>

<main class="main">
<?php // page content follows
