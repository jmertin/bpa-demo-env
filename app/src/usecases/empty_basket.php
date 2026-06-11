<?php
// Use case: empty_basket
// Forces basket_total() to return 0.00 for this user.
// The actual logic lives in basket_total() which checks $_SESSION['usecase'].
// This file just needs to exist and be callable.

function usecase_empty_basket(PDO $db, array &$ctx): void
{
    // basket_total() already reads $_SESSION['usecase'] directly.
    // Nothing additional to do here; the context flag is for monitoring.
    $ctx['empty_basket'] = true;
}
