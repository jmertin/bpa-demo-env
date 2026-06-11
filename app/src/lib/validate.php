<?php
// Input validation helpers.
// Every public-facing input must pass through one of these before use.

/**
 * Validates a string: strips leading/trailing whitespace, checks length.
 * Returns the cleaned string on success or null on failure.
 */
function validate_string(mixed $value, int $min = 0, int $max = 255): ?string
{
    if (!is_string($value) && !is_int($value)) {
        return null;
    }
    $s = trim((string)$value);
    $len = mb_strlen($s, 'UTF-8');
    if ($len < $min || $len > $max) {
        return null;
    }
    return $s;
}

/**
 * Validates a positive integer within an inclusive range.
 */
function validate_int(mixed $value, int $min = 1, int $max = PHP_INT_MAX): ?int
{
    if (is_string($value) && ctype_digit(ltrim($value, '-'))) {
        $value = (int)$value;
    }
    if (!is_int($value)) {
        return null;
    }
    if ($value < $min || $value > $max) {
        return null;
    }
    return $value;
}

/**
 * Validates an e-mail address using PHP's built-in filter.
 */
function validate_email(mixed $value): ?string
{
    $s = validate_string($value, 3, 255);
    if ($s === null) {
        return null;
    }
    $filtered = filter_var($s, FILTER_VALIDATE_EMAIL);
    return $filtered !== false ? $filtered : null;
}

/**
 * Validates a slug (only a-z, 0-9, hyphens).
 */
function validate_slug(mixed $value, int $max = 200): ?string
{
    $s = validate_string($value, 1, $max);
    if ($s === null) {
        return null;
    }
    return preg_match('/^[a-z0-9\-]+$/', $s) ? $s : null;
}

/**
 * Validates a decimal price string (e.g. "12.90").
 * Returns the value cast to float on success, null on failure.
 */
function validate_price(mixed $value): ?float
{
    $s = validate_string($value, 1, 20);
    if ($s === null) {
        return null;
    }
    if (!preg_match('/^\d{1,8}(\.\d{1,2})?$/', $s)) {
        return null;
    }
    return (float)$s;
}

/**
 * Validates a credit-card number: digits only, 13-19 chars, Luhn check.
 */
function validate_cc_number(mixed $value): ?string
{
    $s = validate_string($value, 13, 19);
    if ($s === null) {
        return null;
    }
    $digits = preg_replace('/\s+/', '', $s);
    if (!ctype_digit($digits)) {
        return null;
    }
    // Luhn algorithm
    $sum = 0;
    $alt = false;
    for ($i = strlen($digits) - 1; $i >= 0; $i--) {
        $n = (int)$digits[$i];
        if ($alt) {
            $n *= 2;
            if ($n > 9) {
                $n -= 9;
            }
        }
        $sum += $n;
        $alt = !$alt;
    }
    return ($sum % 10 === 0) ? $digits : null;
}

/**
 * Validates a MM/YY expiry date (must not be in the past).
 */
function validate_cc_expiry(mixed $value): ?string
{
    $s = validate_string($value, 5, 5);
    if ($s === null) {
        return null;
    }
    if (!preg_match('/^(\d{2})\/(\d{2})$/', $s, $m)) {
        return null;
    }
    $month = (int)$m[1];
    $year  = 2000 + (int)$m[2];
    if ($month < 1 || $month > 12) {
        return null;
    }
    $now = getdate();
    if ($year < $now['year'] || ($year === $now['year'] && $month < $now['mon'])) {
        return null;
    }
    return $s;
}

/**
 * Validates a 3-4 digit CVV.
 */
function validate_cvv(mixed $value): ?string
{
    $s = validate_string($value, 3, 4);
    if ($s === null) {
        return null;
    }
    return ctype_digit($s) ? $s : null;
}

/**
 * Validates a username: alphanumeric plus underscore/hyphen, 1-50 chars.
 */
function validate_username(mixed $value): ?string
{
    $s = validate_string($value, 1, 50);
    if ($s === null) {
        return null;
    }
    return preg_match('/^[a-zA-Z0-9_\-]+$/', $s) ? $s : null;
}

/**
 * Validates a password: minimum 6 characters.
 */
function validate_password(mixed $value): ?string
{
    return validate_string($value, 6, 255);
}

/**
 * Returns a sanitised integer from GET/POST, or null.
 */
function input_int(string $key, string $source = 'get', int $min = 1, int $max = PHP_INT_MAX): ?int
{
    $data = $source === 'post' ? $_POST : $_GET;
    return validate_int($data[$key] ?? null, $min, $max);
}

/**
 * Returns a sanitised string from GET/POST, or null.
 */
function input_string(string $key, string $source = 'get', int $min = 0, int $max = 255): ?string
{
    $data = $source === 'post' ? $_POST : $_GET;
    return validate_string($data[$key] ?? null, $min, $max);
}
