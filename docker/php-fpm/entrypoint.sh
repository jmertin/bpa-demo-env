#!/usr/bin/env bash
set -euo pipefail

# Initialise the cron daemon so the security-update job can run.
# The service command handles the sysv init wrapper present in Ubuntu images.
service cron start

# Launch PHP-FPM in foreground.
# -F  keeps the master process in the foreground (required for container PID 1).
# -R  permits running as root; worker processes drop to www-data as configured
#     in /etc/php-fpm-pool.d/www.conf.
exec php-fpm-run -F -R
