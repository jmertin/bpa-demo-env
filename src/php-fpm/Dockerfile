# ════════════════════════════════════════════════════════════════════════════
# PHP-FPM – Multi-stage hardened build
# Base: ubuntu:22.04 (Jammy LTS)
#
# Stage 1 (app-builder): Extracts and validates the application archive.
#   Contains only tar and ca-certificates; no PHP, no web server.
#
# Stage 2 (runtime): Clean Ubuntu 22.04 layer with PHP 8.1 runtime only.
#   No build tools, no compilers, no package cache in the final image.
#   PHP probe injection is performed at container startup by entrypoint.sh
#   using the APMIA volume shared with the dx-o2-agents container.
#
# PHP version: 8.1 (ubuntu:22.04 default; within DX O2 PHP Agent ceiling ≤8.4)
# FPM port   : 9000 (non-privileged, bound on all interfaces)
# ════════════════════════════════════════════════════════════════════════════

# ── Stage 1: Extract application archive ────────────────────────────────────
FROM ubuntu:22.04 AS app-builder

ENV DEBIAN_FRONTEND=noninteractive

# Minimal tooling to extract and verify the application archive.
# No PHP, no web server, no unnecessary packages.
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        tar \
        ca-certificates && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

COPY app.tar.gz /tmp/app.tar.gz
RUN mkdir -p /app && \
    tar -xzf /tmp/app.tar.gz -C /app && \
    rm /tmp/app.tar.gz

# ── Stage 2: Runtime image ───────────────────────────────────────────────────
FROM ubuntu:22.04 AS runtime

ENV DEBIAN_FRONTEND=noninteractive

# Install PHP 8.1 runtime packages only – no dev headers, no compilers.
# php8.1-mysql  : PDO_MySQL driver for MariaDB connectivity.
# php8.1-mbstring: required by mb_strlen() in lib/validate.php.
# cron          : runs the daily security-update job.
# ca-certificates: required for TLS (future extension installs, etc.).
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        php8.1-fpm \
        php8.1-mysql \
        php8.1-mbstring \
        cron \
        ca-certificates && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Create stable, version-agnostic symlinks so the entrypoint and process
# supervision tools do not need to hard-code /etc/php/8.1/... paths.
RUN ln -sf /etc/php/8.1/fpm/php-fpm.conf /etc/php-fpm-main.conf && \
    ln -sf /etc/php/8.1/fpm/pool.d        /etc/php-fpm-pool.d   && \
    ln -sf /usr/sbin/php-fpm8.1           /usr/local/bin/php-fpm-run && \
    # Remove the distro default pool; the project ships its own www.conf.
    rm -f /etc/php/8.1/fpm/pool.d/www.conf

# Security-update cron job (daily at 03:15 UTC).
COPY config/security-updates /etc/cron.d/security-updates
RUN chmod 0644 /etc/cron.d/security-updates

# PHP-FPM global config and worker pool definition.
COPY config/php-fpm.conf /etc/php-fpm-main.conf
COPY config/www.conf     /etc/php-fpm-pool.d/www.conf

# Copy extracted application from builder stage (no tar binary in runtime).
COPY --from=app-builder /app /var/www/html
RUN chown -R www-data:www-data /var/www/html

# Broadcom DX O2 PHP probe injection:
# At container startup, entrypoint.sh checks APMIA_HOME for the PHP probe
# shared library and INI file.  If found (i.e. the agent volume is mounted)
# the probe is copied into the PHP FPM conf.d directory and loaded.
# When the volume is absent the container starts cleanly without instrumentation.
ENV APMIA_HOME=/opt/apmia

COPY entrypoint.sh /entrypoint.sh
RUN chmod 0755 /entrypoint.sh

# PHP-FPM listens on a non-privileged port (TCP 9000).
EXPOSE 9000

ENTRYPOINT ["/entrypoint.sh"]
