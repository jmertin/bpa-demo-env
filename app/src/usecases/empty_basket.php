<?php
// Use case: empty_basket.
// Forces basket_total() to return 0.00 for this user.
// The actual logic lives in basket_total() which checks $_SESSION['usecase'].
// This file just needs to exist and be callable.

/**
 * Empty-basket use case — marks the context and lets basket_total() handle the
 * rest.
 *
 * basket_total() reads $_SESSION['usecase'] directly and returns 0.00 when it
 * equals 'empty_basket'. No additional work is required here; the context flag
 * is used by monitoring headers.
 *
 * @param \PDO $db
 *   Active database connection passed by the use-case runner (unused).
 * @param array &$ctx
 *   Request context array; receives an 'empty_basket' boolean key on exit.
 *
 * @return void
 */
function usecase_empty_basket(PDO $db, array &$ctx): void {
  $ctx['empty_basket'] = true;
}
