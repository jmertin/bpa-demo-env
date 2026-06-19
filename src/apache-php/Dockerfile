# ════════════════════════════════════════════════════════════════════════════
# Apache 2.4 + mod_php 8.1 – Single hardened application container
# Base: ubuntu:22.04 (Jammy LTS)
#
# Replaces the previous nginx + php-fpm two-container setup.  Both the DX O2
# PHP probe and the BPA WebServer Plugin for Apache are injected at container
# startup from the shared APMIA volume (populated by dxo2-init).  The
# container starts cleanly when the agent volume is absent.
#
# Stage 1 (app-builder): Extracts the application archive.
# Stage 2 (runtime)    : Apache 2.4 + mod_php 8.1; no build tools present.
#
# PHP version  : 8.1 (ubuntu:22.04; within DX O2 PHP Agent ceiling ≤8.4)
# HTTP port    : 8080 (non-privileged)
# ════════════════════════════════════════════════════════════════════════════

# ── Stage 1: Extract application archive ────────────────────────────────────
FROM ubuntu:22.04 AS app-builder

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && \
    apt-get install -y --no-install-recommends tar ca-certificates && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

COPY app.tar.gz /tmp/app.tar.gz
RUN mkdir -p /app && \
    tar -xzf /tmp/app.tar.gz -C /app && \
    rm /tmp/app.tar.gz

# ── Stage 2: Runtime image ───────────────────────────────────────────────────
FROM ubuntu:22.04 AS runtime

ENV DEBIAN_FRONTEND=noninteractive

# Apache 2.4 + PHP 8.1 as an Apache module (mod_php).
# libapache2-mod-php8.1 pulls in php8.1-common; php8.1-cli is added so the
# entrypoint can call `php8.1 -r 'echo ini_get("extension_dir");'` to locate
# the correct path for the APMIA probe .so at runtime.
# cron: daily security-update job.
# Troubleshooting tools: curl, dnsutils (dig/nslookup/host), iputils-ping,
#   less, net-tools (netstat/ifconfig/route), procps (ps/top/free/kill).
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        apache2 \
        libapache2-mod-php8.1 \
        php8.1-cli \
        php8.1-mysql \
        php8.1-mbstring \
        cron \
        ca-certificates \
        curl \
        dnsutils \
        iputils-ping \
        less \
        net-tools \
        procps && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Enable required Apache modules; disable the distro default site.
RUN a2enmod rewrite headers php8.1 && \
    a2dissite 000-default

# Suppress "Could not reliably determine the server's FQDN" at every startup.
RUN echo "ServerName localhost" > /etc/apache2/conf-available/servername.conf && \
    a2enconf servername

# Listen on non-privileged port 8080 (the default of 80 requires root).
RUN sed -i 's/Listen 80$/Listen 8080/' /etc/apache2/ports.conf

# Project VirtualHost – baked in for Compose; overridden via ConfigMap subPath
# mount in Kubernetes (the sites-enabled/ symlink follows the mounted file).
COPY config/vhost.conf /etc/apache2/sites-available/bpa-demo.conf
RUN a2ensite bpa-demo

# Security-update cron job.
COPY config/security-updates /etc/cron.d/security-updates
RUN chmod 0644 /etc/cron.d/security-updates

# Application files from the builder stage.
COPY --from=app-builder /app /var/www/html
RUN chown -R www-data:www-data /var/www/html

# PHP probe log directory.  Created here so it exists even when the APMIA
# volume is absent.  www-data owns it because the probe runs inside the Apache
# process, which drops privileges to www-data before handling requests.
RUN mkdir -p /var/log/php-probe && \
    chown www-data:www-data /var/log/php-probe && \
    chmod 0755 /var/log/php-probe

ENV APMIA_HOME=/opt/apmia

COPY entrypoint.sh /entrypoint.sh
RUN chmod 0755 /entrypoint.sh

EXPOSE 8080
ENTRYPOINT ["/entrypoint.sh"]
