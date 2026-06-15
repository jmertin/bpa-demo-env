FROM ubuntu:26.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        nginx \
        cron \
        ca-certificates && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Security-update cron job (daily at 03:30, offset from php-fpm)
COPY config/security-updates /etc/cron.d/security-updates
RUN chmod 0644 /etc/cron.d/security-updates

# Remove distro default virtual host; we supply our own.
RUN rm -f /etc/nginx/sites-enabled/default \
          /etc/nginx/sites-available/default

# Nginx needs writable temp paths when the worker runs as a non-root user.
RUN mkdir -p /tmp/nginx-client /tmp/nginx-proxy /tmp/nginx-fastcgi && \
    chown -R www-data:www-data /tmp/nginx-client /tmp/nginx-proxy /tmp/nginx-fastcgi

COPY config/nginx.conf      /etc/nginx/nginx.conf
COPY config/default.conf    /etc/nginx/conf.d/default.conf

COPY entrypoint.sh /entrypoint.sh
RUN chmod 0755 /entrypoint.sh

# Non-privileged HTTP port (8080)
EXPOSE 8080

ENTRYPOINT ["/entrypoint.sh"]
