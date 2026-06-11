<?php
// Authentication helpers.
// Passwords in the DB may be stored as:
//   $SETUP$<plain>  – first-login seed format; verified plain, then upgraded to bcrypt.
//   $2y$…           – standard bcrypt hash.

require_once __DIR__ . '/../config/database.php';

function auth_login(string $username, string $password): bool
{
    $stmt = db()->prepare(
        'SELECT id, username, password_hash, role, full_name FROM users WHERE username = ?'
    );
    $stmt->execute([$username]);
    $user = $stmt->fetch();

    if (!$user) {
        return false;
    }

    $hash = $user['password_hash'];

    if (str_starts_with($hash, '$SETUP$')) {
        // First-login seed: compare plain text
        $plain = substr($hash, 7);
        if (!hash_equals($plain, $password)) {
            return false;
        }
        // Upgrade to bcrypt
        $newHash = password_hash($password, PASSWORD_BCRYPT);
        db()->prepare('UPDATE users SET password_hash = ? WHERE id = ?')
            ->execute([$newHash, $user['id']]);
    } else {
        if (!password_verify($password, $hash)) {
            return false;
        }
    }

    // Regenerate session to prevent session-fixation attacks
    session_regenerate_id(true);
    $_SESSION['csrf_token'] = bin2hex(random_bytes(32));

    $_SESSION['user_id']   = (int)$user['id'];
    $_SESSION['username']  = $user['username'];
    $_SESSION['role']      = $user['role'];
    $_SESSION['full_name'] = $user['full_name'];

    // Load assigned use case (if any)
    $uc = db()->prepare('SELECT usecase_name FROM user_usecases WHERE user_id = ?');
    $uc->execute([$user['id']]);
    $ucRow = $uc->fetch();
    $_SESSION['usecase'] = $ucRow ? $ucRow['usecase_name'] : '';

    return true;
}

function auth_logout(): void
{
    $_SESSION = [];
    session_destroy();
}

function auth_user(): ?array
{
    if (empty($_SESSION['user_id'])) {
        return null;
    }
    return [
        'id'       => $_SESSION['user_id'],
        'username' => $_SESSION['username'],
        'role'     => $_SESSION['role'],
        'full_name'=> $_SESSION['full_name'],
        'usecase'  => $_SESSION['usecase'] ?? '',
    ];
}

function auth_require_login(): void
{
    if (empty($_SESSION['user_id'])) {
        header('Location: ?page=login');
        exit;
    }
}

function auth_require_admin(): void
{
    auth_require_login();
    if ($_SESSION['role'] !== 'admin') {
        http_response_code(403);
        exit('Access denied.');
    }
}

function auth_is_admin(): bool
{
    return ($_SESSION['role'] ?? '') === 'admin';
}
