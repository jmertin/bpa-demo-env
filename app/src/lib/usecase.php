<?php
// Use-case system.
// Use cases are PHP files in app/src/usecases/<name>.php
// Each defines a function  usecase_<name>(PDO $db, array &$ctx): void
// The context array lets the use case inject data into the request lifecycle.

require_once __DIR__ . '/../config/database.php';

/**
 * Runs the use case assigned to the current session user (if any).
 * Mutates $ctx in place so callers can inspect injected values.
 */
function usecase_run(array &$ctx): void
{
    $name = $_SESSION['usecase'] ?? '';
    if ($name === '') {
        return;
    }

    $file = __DIR__ . "/../usecases/{$name}.php";
    if (!is_file($file)) {
        return;
    }

    require_once $file;
    $fn = 'usecase_' . $name;
    if (is_callable($fn)) {
        $fn(db(), $ctx);
    }
}

/**
 * Admin: assigns a use case to a user.
 */
function usecase_assign(int $targetUserId, string $usecaseName, int $assignedBy): void
{
    db()->prepare("
        INSERT INTO user_usecases (user_id, usecase_name, assigned_by)
        VALUES (?, ?, ?)
        ON DUPLICATE KEY UPDATE usecase_name = VALUES(usecase_name),
                                 assigned_by  = VALUES(assigned_by),
                                 assigned_at  = CURRENT_TIMESTAMP
    ")->execute([$targetUserId, $usecaseName, $assignedBy]);
}

/**
 * Admin: removes a use case assignment.
 */
function usecase_unassign(int $targetUserId): void
{
    db()->prepare('DELETE FROM user_usecases WHERE user_id = ?')
        ->execute([$targetUserId]);
}

/**
 * Returns list of available use-case names by scanning the usecases/ directory.
 */
function usecase_available(): array
{
    $dir   = __DIR__ . '/../usecases/';
    $names = [];
    foreach (glob($dir . '*.php') as $file) {
        $names[] = basename($file, '.php');
    }
    sort($names);
    return $names;
}

/**
 * Returns the use case assigned to a user, or empty string.
 */
function usecase_get_for_user(int $userId): string
{
    $stmt = db()->prepare('SELECT usecase_name FROM user_usecases WHERE user_id = ?');
    $stmt->execute([$userId]);
    $row = $stmt->fetch();
    return $row ? $row['usecase_name'] : '';
}
