<?php
// Order creation and retrieval.

require_once __DIR__ . '/../config/database.php';
require_once __DIR__ . '/basket.php';

/**
 * Creates an order from the current basket contents.
 * Returns the new order ID, or null if the basket is empty.
 */
function order_create(
    ?int   $userId,
    string $billingName,
    string $billingEmail,
    string $ccLast4
): ?int {
    $items = basket_items();
    if (empty($items)) {
        return null;
    }

    $subtotal = basket_total();
    $total    = $subtotal; // no tax calculation for demo

    $pdo = db();
    $pdo->beginTransaction();
    try {
        $pdo->prepare("
            INSERT INTO orders (user_id, session_id, status, subtotal, total,
                                billing_name, billing_email, cc_last4)
            VALUES (?, ?, 'paid', ?, ?, ?, ?, ?)
        ")->execute([
            $userId,
            session_id(),
            $subtotal,
            $total,
            $billingName,
            $billingEmail,
            $ccLast4,
        ]);
        $orderId = (int)$pdo->lastInsertId();

        $itemStmt = $pdo->prepare("
            INSERT INTO order_items (order_id, product_id, product_name, quantity, unit_price)
            VALUES (?, ?, ?, ?, ?)
        ");
        foreach ($items as $item) {
            $itemStmt->execute([
                $orderId,
                (int)$item['product']['id'],
                $item['product']['name'],
                $item['qty'],
                $item['product']['price'],
            ]);
        }
        $pdo->commit();
    } catch (Throwable $e) {
        $pdo->rollBack();
        throw $e;
    }

    basket_clear();
    return $orderId;
}

/**
 * Returns a single order with its items for the confirmation page.
 */
function order_get(int $orderId): ?array
{
    $stmt = db()->prepare('SELECT * FROM orders WHERE id = ?');
    $stmt->execute([$orderId]);
    $order = $stmt->fetch();
    if (!$order) {
        return null;
    }

    $items = db()->prepare(
        'SELECT * FROM order_items WHERE order_id = ? ORDER BY id'
    );
    $items->execute([$orderId]);
    $order['items'] = $items->fetchAll();
    return $order;
}

/**
 * Returns all orders for a user (most recent first).
 */
function order_list_for_user(int $userId): array
{
    $stmt = db()->prepare(
        'SELECT * FROM orders WHERE user_id = ? ORDER BY created_at DESC LIMIT 50'
    );
    $stmt->execute([$userId]);
    return $stmt->fetchAll();
}
