<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title><?= htmlspecialchars($pageTitle ?? APP_NAME) ?></title>
<style>
/* ── Reset & base ──────────────────────────────────────────────────────────── */
*,*::before,*::after{box-sizing:border-box;margin:0;padding:0}
html{font-size:16px;height:100%}
body{font-family:'Segoe UI',system-ui,sans-serif;background:#f0f2f5;color:#1a1a2e;min-height:100%;display:flex;flex-direction:column}
a{color:inherit;text-decoration:none}
a:hover{text-decoration:underline}
img{max-width:100%;display:block}

/* ── Top bar ────────────────────────────────────────────────────────────────── */
.topbar{
  background:#1a1a2e;color:#e8eaf6;
  display:flex;align-items:center;justify-content:space-between;
  padding:.6rem 1.5rem;position:sticky;top:0;z-index:100;
  box-shadow:0 2px 8px rgba(0,0,0,.4);
}
.topbar-brand{font-size:1.2rem;font-weight:700;letter-spacing:.03em;color:#7c83ff}
.topbar-right{display:flex;align-items:center;gap:1rem;font-size:.875rem}
.topbar-user{color:#b0bec5}
.topbar-user strong{color:#e8eaf6}
.basket-badge{
  display:inline-flex;align-items:center;gap:.35rem;
  background:#7c83ff;color:#fff;padding:.3rem .75rem;border-radius:20px;
  font-size:.8rem;font-weight:600;cursor:pointer;
}
.basket-badge:hover{background:#5c6bc0;text-decoration:none}
.basket-badge .count{background:#fff;color:#1a1a2e;border-radius:50%;
  width:18px;height:18px;display:inline-flex;align-items:center;justify-content:center;font-size:.7rem}

/* ── Layout ─────────────────────────────────────────────────────────────────── */
.page-wrapper{display:flex;flex:1;max-width:1400px;width:100%;margin:0 auto;padding:1.5rem;gap:1.5rem}

/* ── Sidebar ────────────────────────────────────────────────────────────────── */
.sidebar{
  width:220px;flex-shrink:0;
  background:#1a1a2e;border-radius:10px;padding:1.2rem;
  height:fit-content;position:sticky;top:56px;
  box-shadow:0 4px 16px rgba(0,0,0,.25);
}
.sidebar h3{font-size:.7rem;text-transform:uppercase;letter-spacing:.12em;color:#7986cb;margin-bottom:.8rem;padding-bottom:.4rem;border-bottom:1px solid #283593}
.sidebar-section{margin-bottom:1.4rem}
.sidebar a{
  display:block;color:#b0bec5;padding:.4rem .6rem;border-radius:6px;
  font-size:.875rem;transition:background .15s,color .15s;
}
.sidebar a:hover,.sidebar a.active{background:#283593;color:#e8eaf6;text-decoration:none}
.brand-dot{display:inline-block;width:8px;height:8px;border-radius:50%;margin-right:.5rem;vertical-align:middle}
.cap-pill{
  display:inline-block;font-size:.72rem;padding:.1rem .45rem;border-radius:10px;
  color:#fff;margin:.15rem .1rem;
}

/* ── Main content ────────────────────────────────────────────────────────────── */
.main{flex:1;min-width:0}

/* ── Section header ─────────────────────────────────────────────────────────── */
.section-header{display:flex;align-items:center;justify-content:space-between;margin-bottom:1.2rem;gap:1rem;flex-wrap:wrap}
.section-title{font-size:1.25rem;font-weight:700;color:#1a1a2e}
.result-count{font-size:.85rem;color:#607d8b}

/* ── Filter bar ─────────────────────────────────────────────────────────────── */
.filter-bar{
  background:#fff;border-radius:10px;padding:.9rem 1.2rem;
  margin-bottom:1.2rem;display:flex;gap:.8rem;flex-wrap:wrap;align-items:flex-end;
  box-shadow:0 2px 8px rgba(0,0,0,.07);
}
.filter-group{display:flex;flex-direction:column;gap:.25rem;min-width:120px}
.filter-group label{font-size:.7rem;color:#607d8b;text-transform:uppercase;letter-spacing:.08em}
.filter-group select,.filter-group input{
  border:1px solid #cfd8dc;border-radius:6px;padding:.35rem .6rem;font-size:.875rem;
  background:#f5f7fa;color:#1a1a2e;outline:none;
}
.filter-group select:focus,.filter-group input:focus{border-color:#7c83ff}
.btn{
  display:inline-flex;align-items:center;gap:.4rem;
  padding:.4rem .9rem;border-radius:6px;font-size:.875rem;font-weight:600;
  border:none;cursor:pointer;transition:background .15s,transform .1s;
}
.btn:active{transform:scale(.97)}
.btn-primary{background:#7c83ff;color:#fff}
.btn-primary:hover{background:#5c6bc0}
.btn-secondary{background:#e8eaf6;color:#3949ab}
.btn-secondary:hover{background:#c5cae9}
.btn-danger{background:#ef5350;color:#fff}
.btn-danger:hover{background:#c62828}
.btn-success{background:#43a047;color:#fff}
.btn-success:hover{background:#2e7d32}
.btn-sm{padding:.25rem .6rem;font-size:.8rem}

/* ── Product grid ────────────────────────────────────────────────────────────── */
.product-grid{
  display:grid;
  grid-template-columns:repeat(auto-fill,minmax(220px,1fr));
  gap:1.2rem;
}
.product-card{
  background:#fff;border-radius:10px;overflow:hidden;
  box-shadow:0 2px 8px rgba(0,0,0,.07);
  transition:box-shadow .2s,transform .2s;
  display:flex;flex-direction:column;
}
.product-card:hover{box-shadow:0 8px 24px rgba(0,0,0,.14);transform:translateY(-3px)}
.product-card-img{
  height:160px;display:flex;align-items:center;justify-content:center;
  overflow:hidden;background:linear-gradient(135deg,#e8eaf6,#c5cae9);
  position:relative;
}
.product-card-img img{width:100%;height:100%;object-fit:contain;padding:8px}
.product-card-img span{font-size:3rem}
.product-card-body{padding:.9rem;flex:1;display:flex;flex-direction:column;gap:.4rem}
.product-brand{font-size:.72rem;font-weight:700;text-transform:uppercase;letter-spacing:.08em}
.product-name{font-size:.9rem;font-weight:600;color:#1a1a2e;line-height:1.3}
.product-desc{font-size:.8rem;color:#607d8b;line-height:1.4;flex:1}
.product-caps{display:flex;flex-wrap:wrap;gap:.2rem;margin:.2rem 0}
.product-price{font-size:1.1rem;font-weight:700;color:#1a1a2e}
.product-stock{font-size:.75rem;color:#78909c}
.product-card-footer{padding:.7rem .9rem;border-top:1px solid #f0f2f5;display:flex;gap:.5rem}

/* ── Product detail ─────────────────────────────────────────────────────────── */
.product-detail{background:#fff;border-radius:10px;padding:1.8rem;box-shadow:0 2px 8px rgba(0,0,0,.07)}
.product-detail-header{display:flex;gap:1.5rem;margin-bottom:1.5rem;flex-wrap:wrap}
.product-detail-img{
  width:200px;height:200px;border-radius:10px;flex-shrink:0;
  display:flex;align-items:center;justify-content:center;
  font-size:5rem;background:linear-gradient(135deg,#e8eaf6,#c5cae9);
}
.product-detail-meta{flex:1}
.product-detail-brand{font-size:.8rem;font-weight:700;text-transform:uppercase;letter-spacing:.1em;margin-bottom:.3rem}
.product-detail-name{font-size:1.5rem;font-weight:700;margin-bottom:.6rem}
.product-detail-desc{color:#455a64;line-height:1.6;margin-bottom:1rem}
.product-detail-price{font-size:1.8rem;font-weight:700;color:#1a1a2e}

/* ── Basket table ────────────────────────────────────────────────────────────── */
.basket-table{width:100%;border-collapse:collapse;background:#fff;border-radius:10px;overflow:hidden;box-shadow:0 2px 8px rgba(0,0,0,.07)}
.basket-table th{background:#e8eaf6;color:#3949ab;font-size:.8rem;text-transform:uppercase;padding:.7rem 1rem;text-align:left}
.basket-table td{padding:.8rem 1rem;border-bottom:1px solid #f0f2f5;font-size:.9rem;vertical-align:middle}
.basket-table tr:last-child td{border-bottom:none}
.qty-input{width:60px;padding:.3rem .5rem;border:1px solid #cfd8dc;border-radius:6px;text-align:center;font-size:.875rem}
.basket-total-row td{font-weight:700;font-size:1rem;color:#1a1a2e;border-top:2px solid #e8eaf6}

/* ── Checkout / forms ────────────────────────────────────────────────────────── */
.checkout-grid{display:grid;grid-template-columns:1fr 1fr;gap:1.5rem;align-items:start}
@media(max-width:700px){.checkout-grid{grid-template-columns:1fr}}
.card{background:#fff;border-radius:10px;padding:1.5rem;box-shadow:0 2px 8px rgba(0,0,0,.07);margin-bottom:1.5rem}
.card h2{font-size:1rem;font-weight:700;color:#1a1a2e;margin-bottom:1rem;padding-bottom:.5rem;border-bottom:2px solid #e8eaf6}
.form-group{display:flex;flex-direction:column;gap:.3rem;margin-bottom:.9rem}
.form-group label{font-size:.75rem;color:#607d8b;text-transform:uppercase;letter-spacing:.07em}
.form-group input,.form-group select,.form-group textarea{
  border:1px solid #cfd8dc;border-radius:6px;padding:.5rem .7rem;font-size:.9rem;
  background:#f8f9fc;color:#1a1a2e;outline:none;width:100%;
}
.form-group input:focus,.form-group select:focus{border-color:#7c83ff;background:#fff}
.form-error{color:#e53935;font-size:.8rem;margin-top:-.4rem;margin-bottom:.4rem}
.cc-row{display:flex;gap:.8rem}
.cc-row .form-group{flex:1}
.order-summary{background:#f8f9fc;border-radius:8px;padding:1rem;font-size:.875rem}
.order-summary-row{display:flex;justify-content:space-between;padding:.3rem 0;border-bottom:1px solid #e8eaf6}
.order-summary-row:last-child{border-bottom:none;font-weight:700;font-size:1rem}

/* ── Alert / flash messages ─────────────────────────────────────────────────── */
.alert{padding:.8rem 1.2rem;border-radius:8px;margin-bottom:1rem;font-size:.9rem}
.alert-success{background:#e8f5e9;color:#2e7d32;border:1px solid #a5d6a7}
.alert-error{background:#ffebee;color:#c62828;border:1px solid #ef9a9a}
.alert-info{background:#e3f2fd;color:#1565c0;border:1px solid #90caf9}

/* ── Login page ─────────────────────────────────────────────────────────────── */
.login-wrap{max-width:400px;margin:3rem auto}
.login-title{text-align:center;font-size:1.5rem;font-weight:700;color:#1a1a2e;margin-bottom:1.5rem}

/* ── Admin table ────────────────────────────────────────────────────────────── */
.admin-table{width:100%;border-collapse:collapse;background:#fff;border-radius:10px;overflow:hidden;box-shadow:0 2px 8px rgba(0,0,0,.07)}
.admin-table th{background:#e8eaf6;color:#3949ab;font-size:.8rem;text-transform:uppercase;padding:.7rem 1rem;text-align:left}
.admin-table td{padding:.7rem 1rem;border-bottom:1px solid #f0f2f5;font-size:.875rem;vertical-align:middle}
.admin-table tr:last-child td{border-bottom:none}
.admin-table tr:hover td{background:#f8f9fc}
.role-badge{display:inline-block;padding:.15rem .5rem;border-radius:10px;font-size:.72rem;font-weight:700;text-transform:uppercase;letter-spacing:.06em}
.role-admin{background:#7c83ff;color:#fff}
.role-user{background:#e8eaf6;color:#3949ab}

/* ── Pagination ─────────────────────────────────────────────────────────────── */
.pagination{display:flex;gap:.4rem;justify-content:center;margin-top:1.5rem;flex-wrap:wrap}
.page-link{
  display:inline-flex;align-items:center;justify-content:center;
  width:34px;height:34px;border-radius:6px;font-size:.875rem;
  background:#fff;color:#3949ab;box-shadow:0 1px 4px rgba(0,0,0,.1);
  transition:background .15s;
}
.page-link:hover{background:#e8eaf6;text-decoration:none}
.page-link.active{background:#7c83ff;color:#fff}

/* ── Order confirmation ─────────────────────────────────────────────────────── */
.order-confirm{text-align:center;padding:2rem}
.order-confirm-icon{font-size:4rem;margin-bottom:1rem}
.order-confirm-num{font-size:1.5rem;font-weight:700;color:#7c83ff}

/* ── Footer ─────────────────────────────────────────────────────────────────── */
footer{background:#1a1a2e;color:#607d8b;text-align:center;padding:.9rem;font-size:.8rem;margin-top:auto}
footer span{color:#7c83ff}

/* ── Responsive ─────────────────────────────────────────────────────────────── */
@media(max-width:900px){
  .page-wrapper{flex-direction:column}
  .sidebar{width:100%;position:static;display:flex;flex-wrap:wrap;gap:1rem}
  .sidebar-section{margin-bottom:0;min-width:140px}
}
@media(max-width:600px){
  .product-grid{grid-template-columns:1fr 1fr}
  .topbar{padding:.5rem 1rem}
}
</style>
</head>
<body>

<?php /* ── Top navigation bar ──────────────────────────────────────────────── */ ?>
<header class="topbar">
  <a href="?" class="topbar-brand">🏠 <?= APP_NAME ?></a>
  <div class="topbar-right">
    <?php if (auth_user()): ?>
      <span class="topbar-user">
        <?php if (auth_is_admin()): ?>
          <a href="?page=admin" style="color:#ffd54f">⚙ Admin</a> &nbsp;
        <?php endif ?>
        Hi, <strong><?= htmlspecialchars(auth_user()['full_name'] ?: auth_user()['username']) ?></strong>
        &nbsp;|&nbsp;
        <a href="?page=logout" style="color:#ef9a9a">Logout</a>
      </span>
    <?php else: ?>
      <a href="?page=login" style="color:#b0bec5">Login</a>
    <?php endif ?>
    <a href="?page=basket" class="basket-badge">
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
    <a href="?" class="<?= empty($_GET['brand']) ? 'active' : '' ?>">All brands</a>
    <?php foreach (product_get_brands() as $b): ?>
      <a href="?brand=<?= $b['slug'] ?>"
         class="<?= (($_GET['brand'] ?? '') === $b['slug']) ? 'active' : '' ?>">
        <span class="brand-dot" style="background:#<?= htmlspecialchars($b['color']) ?>"></span>
        <?= htmlspecialchars($b['name']) ?>
      </a>
    <?php endforeach ?>
  </div>

  <div class="sidebar-section">
    <h3>Protocol</h3>
    <a href="?" class="<?= empty($_GET['cap']) ? 'active' : '' ?>">All protocols</a>
    <?php foreach (product_get_capabilities() as $c): ?>
      <a href="?cap=<?= $c['slug'] ?>"
         class="<?= (($_GET['cap'] ?? '') === $c['slug']) ? 'active' : '' ?>">
        <span class="brand-dot" style="background:#<?= htmlspecialchars($c['color']) ?>"></span>
        <?= htmlspecialchars($c['name']) ?>
      </a>
    <?php endforeach ?>
  </div>

  <div class="sidebar-section">
    <h3>Shop</h3>
    <a href="?page=basket">🛒 My Basket</a>
    <?php if (auth_user()): ?>
      <a href="?page=order">📦 My Orders</a>
    <?php endif ?>
    <?php if (auth_is_admin()): ?>
      <a href="?page=admin" class="<?= ($page === 'admin') ? 'active' : '' ?>">⚙ Admin Panel</a>
    <?php endif ?>
  </div>

  <?php if (auth_is_admin()): ?>
  <div class="sidebar-section">
    <h3>Diagnostics</h3>
    <a href="?page=dxo2" class="<?= ($page === 'dxo2') ? 'active' : '' ?>">&#128202; DX O2 Status</a>
    <a href="?page=info" class="<?= ($page === 'info') ? 'active' : '' ?>">&#128196; PHP Info</a>
    <a href="?page=db"   class="<?= ($page === 'db')   ? 'active' : '' ?>">&#128421; Database</a>
  </div>
  <?php endif ?>
</aside>

<main class="main">
<?php // page content follows
