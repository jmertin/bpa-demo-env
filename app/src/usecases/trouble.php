<?php
// Use case: trouble
// Simulates a slow/problematic user session by performing 5000 sequential
// DB reads before the request continues. This intentionally degrades
// response time for demo/APM tracing purposes.

function usecase_trouble(PDO $db, array &$ctx): void
{
    $stmt = $db->prepare('SELECT id FROM products WHERE id = ?');
    for ($i = 1; $i <= 5000; $i++) {
        // Cycle through product IDs 1-150
        $stmt->execute([($i % 150) + 1]);
        $stmt->fetch();
    }
    $ctx['trouble_reads'] = 5000;
}
