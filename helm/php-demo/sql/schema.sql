-- BPA-Demo Database Schema
-- Smart home device web shop
SET NAMES utf8mb4;

CREATE TABLE IF NOT EXISTS brands (
    id   TINYINT UNSIGNED NOT NULL AUTO_INCREMENT,
    name VARCHAR(50)      NOT NULL,
    slug VARCHAR(50)      NOT NULL,
    color CHAR(6)         NOT NULL DEFAULT '888888',
    description VARCHAR(255),
    PRIMARY KEY (id),
    UNIQUE KEY uq_brands_slug (slug)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS capabilities (
    id    TINYINT UNSIGNED NOT NULL AUTO_INCREMENT,
    name  VARCHAR(50)      NOT NULL,
    slug  VARCHAR(50)      NOT NULL,
    color CHAR(6)          NOT NULL DEFAULT '888888',
    PRIMARY KEY (id),
    UNIQUE KEY uq_cap_slug (slug)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS products (
    id          SMALLINT UNSIGNED NOT NULL AUTO_INCREMENT,
    brand_id    TINYINT UNSIGNED  NOT NULL,
    name        VARCHAR(200)      NOT NULL,
    slug        VARCHAR(200)      NOT NULL,
    description VARCHAR(500),
    price       DECIMAL(8,2)      NOT NULL,
    stock       SMALLINT UNSIGNED NOT NULL DEFAULT 50,
    PRIMARY KEY (id),
    UNIQUE KEY uq_products_slug (slug),
    KEY idx_products_brand (brand_id),
    CONSTRAINT fk_products_brand FOREIGN KEY (brand_id) REFERENCES brands (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS product_capabilities (
    product_id    SMALLINT UNSIGNED NOT NULL,
    capability_id TINYINT UNSIGNED  NOT NULL,
    PRIMARY KEY (product_id, capability_id),
    CONSTRAINT fk_pc_product FOREIGN KEY (product_id)    REFERENCES products     (id),
    CONSTRAINT fk_pc_cap     FOREIGN KEY (capability_id) REFERENCES capabilities (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS users (
    id            SMALLINT UNSIGNED NOT NULL AUTO_INCREMENT,
    username      VARCHAR(50)       NOT NULL,
    password_hash VARCHAR(255)      NOT NULL,
    email         VARCHAR(255),
    role          ENUM('admin','user') NOT NULL DEFAULT 'user',
    full_name     VARCHAR(100),
    created_at    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    UNIQUE KEY uq_users_username (username)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Admin-assignable per-user behaviour overrides
CREATE TABLE IF NOT EXISTS user_usecases (
    user_id      SMALLINT UNSIGNED NOT NULL,
    usecase_name VARCHAR(100)      NOT NULL,
    assigned_by  SMALLINT UNSIGNED,
    assigned_at  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (user_id),
    CONSTRAINT fk_uu_user     FOREIGN KEY (user_id)     REFERENCES users (id),
    CONSTRAINT fk_uu_assigned FOREIGN KEY (assigned_by) REFERENCES users (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS orders (
    id            INT UNSIGNED      NOT NULL AUTO_INCREMENT,
    user_id       SMALLINT UNSIGNED,
    session_id    VARCHAR(128),
    status        ENUM('pending','paid','cancelled') NOT NULL DEFAULT 'pending',
    subtotal      DECIMAL(8,2) NOT NULL DEFAULT 0.00,
    total         DECIMAL(8,2) NOT NULL DEFAULT 0.00,
    billing_name  VARCHAR(200),
    billing_email VARCHAR(255),
    cc_last4      CHAR(4),
    created_at    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    KEY idx_orders_user (user_id),
    CONSTRAINT fk_orders_user FOREIGN KEY (user_id) REFERENCES users (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS order_items (
    id           INT UNSIGNED      NOT NULL AUTO_INCREMENT,
    order_id     INT UNSIGNED      NOT NULL,
    product_id   SMALLINT UNSIGNED NOT NULL,
    product_name VARCHAR(200)      NOT NULL,
    quantity     TINYINT UNSIGNED  NOT NULL DEFAULT 1,
    unit_price   DECIMAL(8,2)      NOT NULL,
    PRIMARY KEY (id),
    KEY idx_oi_order (order_id),
    CONSTRAINT fk_oi_order   FOREIGN KEY (order_id)   REFERENCES orders   (id),
    CONSTRAINT fk_oi_product FOREIGN KEY (product_id) REFERENCES products (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
