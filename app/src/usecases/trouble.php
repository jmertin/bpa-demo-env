<?php
// Use case: trouble.
// Simulates a slow/problematic user session by performing 5000 sequential
// DB reads before the request continues. This intentionally degrades
// response time for demo/APM tracing purposes.

/**
 * Executes 5000 sequential DB reads to simulate a slow user session.
 *
 * Cycles through product IDs 1-300 repeatedly. Intended purely for APM
 * demonstration — do not assign this use case in production environments.
 *
 * @param \PDO $db
 *   Active database connection passed by the use-case runner.
 * @param array &$ctx
 *   Request context array; receives a 'trouble_reads' integer key on exit.
 *
 * @return void
 */
function usecase_trouble(PDO $db, array &$ctx): void {
  $stmt = $db->prepare('SELECT id FROM products WHERE id = ?');
  for ($i = 1; $i <= 5000; $i++) {
    // Cycle through product IDs 1-300.
    $stmt->execute([($i % 300) + 1]);
    $stmt->fetch();
  }
  $ctx['trouble_reads'] = 5000;
}
