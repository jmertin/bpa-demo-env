FROM ubuntu:26.04

ENV DEBIAN_FRONTEND=noninteractive

# Install PHP-FPM and minimal runtime dependencies.
# php-mysql is required for PDO/MySQLi connectivity to MariaDB.
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        php-fpm \
        php-mysql \
        php-mbstring \
        cron \
        ca-certificates && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Discover installed PHP version once and create stable symlinks so
# subsequent layers and the entrypoint do not need to re-discover it.
RUN PHP_VER=$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;') && \
    ln -sf "/etc/php/${PHP_VER}/fpm/php-fpm.conf"  /etc/php-fpm-main.conf && \
    ln -sf "/etc/php/${PHP_VER}/fpm/pool.d"         /etc/php-fpm-pool.d  && \
    ln -sf "$(command -v php-fpm${PHP_VER})"         /usr/local/bin/php-fpm-run && \
    # Remove distro default pool; we ship our own
    rm -f "/etc/php/${PHP_VER}/fpm/pool.d/www.conf"

# Security-update cron job (daily at 03:15)
COPY config/security-updates /etc/cron.d/security-updates
RUN chmod 0644 /etc/cron.d/security-updates

# PHP-FPM global config and worker pool
COPY config/php-fpm.conf /etc/php-fpm-main.conf
COPY config/www.conf     /etc/php-fpm-pool.d/www.conf

# Application: deployed as a tar archive per project requirements.
# The archive is extracted to /var/www/html and then removed.
COPY app.tar.gz /tmp/app.tar.gz
RUN mkdir -p /var/www/html && \
    tar -xzf /tmp/app.tar.gz -C /var/www/html && \
    chown -R www-data:www-data /var/www/html && \
    rm /tmp/app.tar.gz

COPY entrypoint.sh /entrypoint.sh
RUN chmod 0755 /entrypoint.sh

# PHP-FPM listens on a non-privileged port (TCP 9000)
EXPOSE 9000

ENTRYPOINT ["/entrypoint.sh"]
