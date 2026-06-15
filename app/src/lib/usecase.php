<?php
// Use-case system.
// Use cases are PHP files in app/src/usecases/<name>.php.
// Each defines a function  usecase_<name>(PDO $db, array &$ctx): void.
// The context array lets the use case inject data into the request lifecycle.

require_once __DIR__ . '/../config/database.php';

/**
 * Runs the use case assigned to the current session user (if any).
 *
 * Loads the use-case file from usecases/<name>.php and calls the corresponding
 * usecase_<name>() function, mutating $ctx so callers can inspect injected
 * values. Does nothing when no use case is assigned or the file does not exist.
 *
 * @param array &$ctx
 *   Request-lifecycle context array, mutated in place by the use-case function.
 *
 * @return void
 */
function usecase_run(array &$ctx): void {
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
 * Assigns a use case to a user (admin action).
 *
 * Uses INSERT … ON DUPLICATE KEY UPDATE so repeated assignments overwrite the
 * previous use case without violating the unique constraint.
 *
 * @param int $targetUserId
 *   ID of the user to assign the use case to.
 * @param string $usecaseName
 *   Name of the use case (must match a file in usecases/).
 * @param int $assignedBy
 *   ID of the admin user performing the assignment.
 *
 * @return void
 */
function usecase_assign(int $targetUserId, string $usecaseName, int $assignedBy): void {
  db()->prepare("
    INSERT INTO user_usecases (user_id, usecase_name, assigned_by)
    VALUES (?, ?, ?)
    ON DUPLICATE KEY UPDATE usecase_name = VALUES(usecase_name),
                             assigned_by  = VALUES(assigned_by),
                             assigned_at  = CURRENT_TIMESTAMP
  ")->execute([$targetUserId, $usecaseName, $assignedBy]);
}

/**
 * Removes a use case assignment from a user (admin action).
 *
 * @param int $targetUserId
 *   ID of the user whose use case assignment to remove.
 *
 * @return void
 */
function usecase_unassign(int $targetUserId): void {
  db()->prepare('DELETE FROM user_usecases WHERE user_id = ?')
    ->execute([$targetUserId]);
}

/**
 * Returns list of available use-case names by scanning the usecases/ directory.
 *
 * @return array
 *   Sorted indexed array of use-case name strings (without .php extension).
 */
function usecase_available(): array {
  $dir   = __DIR__ . '/../usecases/';
  $names = [];
  foreach (glob($dir . '*.php') as $file) {
    $names[] = basename($file, '.php');
  }
  sort($names);
  return $names;
}

/**
 * Returns the use case name assigned to a user, or an empty string.
 *
 * @param int $userId
 *   ID of the user to query.
 *
 * @return string
 *   Use case name, or empty string when no assignment exists.
 */
function usecase_get_for_user(int $userId): string {
  $stmt = db()->prepare('SELECT usecase_name FROM user_usecases WHERE user_id = ?');
  $stmt->execute([$userId]);
  $row = $stmt->fetch();
  return $row ? $row['usecase_name'] : '';
}
