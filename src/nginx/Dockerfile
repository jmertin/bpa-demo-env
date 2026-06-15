# ════════════════════════════════════════════════════════════════════════════
# NGINX – Hardened build with BPA WebServer Plugin injection
# Base: ubuntu:22.04 (Jammy LTS)
#
# Pessimistic hardening approach (per Phase 3.3 requirements):
#   • All distro default virtual hosts and module configs are removed.
#   • Only packages strictly required at runtime are installed.
#   • No build tools, no man pages, no documentation in the final image.
#   • nginx.conf is replaced entirely with the project-supplied version.
#
# NGINX version: 1.18 (ubuntu:22.04 default; within BPA Plugin ceiling ≤1.29.x)
# HTTP port    : 8080 (non-privileged)
#
# BPA Plugin injection:
#   At container startup, entrypoint.sh checks APMIA_HOME for the BPA shared
#   module (ngx_http_ca_plugin_filter_module.so).  When found, a load_module
#   directive is written to /etc/nginx/modules-enabled/bpa.conf and picked up
#   by the top-level include directive in nginx.conf.  When absent, NGINX
#   starts without instrumentation – no reconfiguration needed.
# ════════════════════════════════════════════════════════════════════════════

FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

# Install nginx and the minimum viable set of runtime dependencies.
# --no-install-recommends prevents pulling in unnecessary meta-packages.
# cron executes the daily security-update job.
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        nginx \
        cron \
        ca-certificates && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# ── Pessimistic cleanup ──────────────────────────────────────────────────────
# Remove all distro-supplied default configurations, sites, and snippets.
# Only the project-supplied configs (copied below) will be active.
RUN rm -f  /etc/nginx/sites-enabled/default \
           /etc/nginx/sites-available/default && \
    rm -rf /etc/nginx/conf.d/* \
           /etc/nginx/snippets/* && \
    # Remove optional modules that could be loaded automatically and expand
    # the attack surface without providing any benefit to this application.
    rm -rf /etc/nginx/modules-enabled/* && \
    # Create the modules-enabled directory; the BPA entrypoint writes here.
    mkdir -p /etc/nginx/modules-enabled

# ── Temp path setup ─────────────────────────────────────────────────────────
# nginx worker processes run as www-data (non-root).  Temp directories must
# be writable by www-data since /var/lib/nginx is owned by root.
RUN mkdir -p /tmp/nginx-client /tmp/nginx-proxy /tmp/nginx-fastcgi && \
    chown -R www-data:www-data \
        /tmp/nginx-client /tmp/nginx-proxy /tmp/nginx-fastcgi

# ── Configuration ────────────────────────────────────────────────────────────
COPY config/nginx.conf   /etc/nginx/nginx.conf
COPY config/default.conf /etc/nginx/conf.d/default.conf
# The compose-specific vhost (phpfpm:9000 upstream) is volume-mounted at
# runtime via docker-compose.yml and is NOT baked into this image.

COPY entrypoint.sh /entrypoint.sh
RUN chmod 0755 /entrypoint.sh

# Security-update cron job (daily at 03:30 UTC, offset from php-fpm).
COPY config/security-updates /etc/cron.d/security-updates
RUN chmod 0644 /etc/cron.d/security-updates

# BPA plugin injection uses the APMIA volume shared with the dx-o2-agents
# container.  Must match the value set in the other containers.
ENV APMIA_HOME=/opt/apmia

# Non-privileged HTTP port.
EXPOSE 8080

ENTRYPOINT ["/entrypoint.sh"]
