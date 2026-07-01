<?php
// Use case: locked.
// Blocks access for the assigned user.  At login, login.php detects the
// use case before the session is confirmed and revokes it immediately.
// This file handles the edge case where the use case is assigned to an
// already-logged-in user: it evicts their auth session data and redirects
// them to the login page with a flash message.

/**
 * Forces an immediate logout when a locked user makes any request.
 *
 * Clears all authentication session keys (without destroying the session
 * so the flash message survives the redirect), regenerates the session ID,
 * stores the error message as a flash, then redirects to the login page.
 *
 * @param \PDO   $db
 *   Active database connection passed by the use-case runner (unused here).
 * @param array &$ctx
 *   Request context array (unused here; function exits before returning).
 *
 * @return void
 */
function usecase_locked(PDO $db, array &$ctx): void {
  foreach (['user_id', 'username', 'role', 'full_name', 'usecase', 'csrf_token'] as $key) {
    unset($_SESSION[$key]);
  }
  session_regenerate_id(true);
  $_SESSION['login_error'] = 'Your account is not allowed to log in. Please contact the web administrator.';
  header('Location: /login');
  exit;
}
