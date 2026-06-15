<?php
// Session-based shopping basket.
// Basket lives in $_SESSION['basket'] as ['product_id' => quantity, ...].

require_once __DIR__ . '/../config/database.php';
require_once __DIR__ . '/product.php';

/**
 * Adds a quantity of a product to the basket, capped at 99 per line.
 *
 * @param int $productId
 *   ID of the product to add.
 * @param int $qty
 *   Number of units to add. Defaults to 1.
 *
 * @return void
 */
function basket_add(int $productId, int $qty = 1): void {
  if (!isset($_SESSION['basket'])) {
    $_SESSION['basket'] = [];
  }
  $current = (int) ($_SESSION['basket'][$productId] ?? 0);
  $_SESSION['basket'][$productId] = min(99, $current + $qty);
}

/**
 * Removes a product line from the basket entirely.
 *
 * @param int $productId
 *   ID of the product to remove.
 *
 * @return void
 */
function basket_remove(int $productId): void {
  unset($_SESSION['basket'][$productId]);
}

/**
 * Sets the quantity of a basket line, removing the line when qty reaches zero.
 *
 * @param int $productId
 *   ID of the product to update.
 * @param int $qty
 *   New quantity. Values <= 0 remove the line.
 *
 * @return void
 */
function basket_set_qty(int $productId, int $qty): void {
  if ($qty <= 0) {
    basket_remove($productId);
  }
  else {
    $_SESSION['basket'][$productId] = min(99, $qty);
  }
}

/**
 * Empties the basket by removing all lines from the session.
 *
 * @return void
 */
function basket_clear(): void {
  $_SESSION['basket'] = [];
}

/**
 * Returns the hydrated basket contents with subtotals.
 *
 * Fetches product data for all basket lines in a single query and decorates
 * each line with the computed subtotal.
 *
 * @return array
 *   Indexed array of line arrays, each with keys: product (array), qty (int),
 *   subtotal (float). Empty array when basket is empty.
 */
function basket_items(): array {
  $raw = $_SESSION['basket'] ?? [];
  if (empty($raw)) {
    return [];
  }

  $ids          = array_keys($raw);
  $placeholders = implode(',', array_fill(0, count($ids), '?'));
  $stmt         = db()->prepare("
    SELECT p.id, p.name, p.slug, p.price, p.stock,
           b.name AS brand_name, b.color AS brand_color
    FROM products p
    JOIN brands b ON b.id = p.brand_id
    WHERE p.id IN ({$placeholders})
    ORDER BY p.brand_id, p.name
  ");
  $stmt->execute($ids);
  $products = [];
  foreach ($stmt->fetchAll() as $p) {
    $products[(int) $p['id']] = $p;
  }

  $items = [];
  foreach ($raw as $pid => $qty) {
    $pid = (int) $pid;
    if (!isset($products[$pid])) {
      continue;
    }
    $p       = $products[$pid];
    $sub     = round((float) $p['price'] * $qty, 2);
    $items[] = [
      'product'  => $p,
      'qty'      => $qty,
      'subtotal' => $sub,
    ];
  }
  return $items;
}

/**
 * Returns the basket total in EUR.
 *
 * Returns 0.00 unconditionally when the active use case is 'empty_basket'.
 *
 * @return float
 *   Total price rounded to two decimal places.
 */
function basket_total(): float {
  if (!empty($_SESSION['usecase']) && $_SESSION['usecase'] === 'empty_basket') {
    return 0.00;
  }
  $total = 0.0;
  foreach (basket_items() as $item) {
    $total += $item['subtotal'];
  }
  return round($total, 2);
}

/**
 * Returns the total number of units across all basket lines.
 *
 * @return int
 *   Sum of all quantities in the basket.
 */
function basket_count(): int {
  return array_sum($_SESSION['basket'] ?? []);
}
