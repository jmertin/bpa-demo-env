<?php
// Returns a singleton PDO connection to MariaDB.
// Credentials are read from environment variables injected by Kubernetes.

function db(): PDO
{
    static $pdo = null;
    if ($pdo !== null) {
        return $pdo;
    }

    $host   = getenv('MARIADB_HOST')     ?: '127.0.0.1';
    $port   = getenv('MARIADB_PORT')     ?: '3306';
    $dbname = getenv('MARIADB_DATABASE') ?: 'phpapp';
    $user   = getenv('MARIADB_USER')     ?: 'phpuser';
    $pass   = getenv('MARIADB_PASSWORD') ?: '';

    $dsn = "mysql:host={$host};port={$port};dbname={$dbname};charset=utf8mb4";
    $pdo = new PDO($dsn, $user, $pass, [
        PDO::ATTR_ERRMODE            => PDO::ERRMODE_EXCEPTION,
        PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
        PDO::ATTR_EMULATE_PREPARES   => false,
    ]);
    return $pdo;
}
