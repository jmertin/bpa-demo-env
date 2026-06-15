#!/usr/bin/env bash
set -euo pipefail

service cron start

# Validate configuration before starting.
nginx -t

# Forward nginx logs to stdout/stderr (picked up by the container runtime).
ln -sf /proc/self/fd/1 /var/log/nginx/access.log
ln -sf /proc/self/fd/2 /var/log/nginx/error.log

exec nginx -g 'daemon off;'
