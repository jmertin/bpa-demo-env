# Version Compatibility Matrix – BPA-Demo / DX O2 Integration

Generated: 2026-06-15  
Purpose: Establish safe version boundaries before agent injection (Phase 3).

---

## 1. Current Prototype Baseline

| Component  | Current Base Image   | Default Package Version      |
|------------|----------------------|------------------------------|
| PHP-FPM    | ubuntu:26.04 (Noble+)| php-fpm – likely PHP 8.4–8.5 |
| NGINX      | ubuntu:26.04 (Noble+)| nginx   – likely 1.26–1.28   |

> **Ubuntu 26.04** ships the very latest APT packages and is not yet on
> Broadcom's validated OS list for Infrastructure Agent binary installers.

---

## 2. Broadcom DX O2 Agent Requirements

| Agent / Plugin                         | Max Supported Version | Notes                                      |
|----------------------------------------|-----------------------|--------------------------------------------|
| PHP Agent (`wily_php_agent`)           | PHP **8.4**           | Probes PHP-FPM workers via shared library  |
| BPA WebServer Plugin (`ngx_http_ca_*`) | NGINX **1.29.x**      | Dynamic `.so` module, version-ABI-sensitive|
| Infrastructure Agent (binary)          | Ubuntu 20.04 / 22.04  | glibc 2.31 / 2.35 ABI; 26.04 unverified   |
| Business Transaction Listener (BTL)    | Same OS as Infra Agent| Co-located with Infra Agent container      |

Sources: Broadcom DX APM Compatibility Guide (CA Technologies / Broadcom portal).

---

## 3. Target Base Image Decision

**Selected: `ubuntu:22.04` (Jammy Jellyfish, LTS until April 2027)**

Rationale:

| Criterion                           | ubuntu:22.04             | ubuntu:24.04              | ubuntu:26.04              |
|-------------------------------------|--------------------------|---------------------------|---------------------------|
| Infra Agent binary compatibility    | ✅ Confirmed              | ⚠️ Partial (recent builds) | ❌ Unverified              |
| Default PHP version                 | 8.1 (≤ 8.4 limit ✅)     | 8.3 (≤ 8.4 limit ✅)      | 8.4–8.5 (may exceed limit)|
| Default NGINX version               | 1.18 (≤ 1.29.x ✅)       | 1.24 (≤ 1.29.x ✅)        | 1.26+ (≤ 1.29.x ✅)       |
| glibc version                       | 2.35                     | 2.39                      | 2.41+                     |
| LTS support remaining               | Until Apr 2027           | Until Apr 2029            | Until Apr 2031            |

PHP 8.1 (ubuntu:22.04 default) satisfies the ≤ 8.4 ceiling.
NGINX 1.18 (ubuntu:22.04 default) is within the ≤ 1.29.x ceiling.
The Broadcom Infrastructure Agent `.deb` package has published Ubuntu 22.04 support.

Optional: install PHP 8.3 via the `ondrej/php` PPA if a newer minor is required.
Optional: install NGINX 1.27/1.28 via the official `nginx.org` APT repo.

---

## 4. Recommended Package Pinning (Phase 3 Dockerfiles)

```dockerfile
FROM ubuntu:22.04

# PHP-FPM (within DX O2 PHP Agent ceiling of PHP 8.4)
RUN apt-get install -y php8.1-fpm php8.1-mysql php8.1-mbstring

# NGINX (within BPA WebServer Plugin ceiling of NGINX 1.29.x)
# Default ubuntu:22.04 ships nginx 1.18 – acceptable.
# To use a newer minor, add the nginx.org focal repo before installing:
#   echo "deb https://nginx.org/packages/ubuntu jammy nginx" > /etc/apt/sources.list.d/nginx.list
RUN apt-get install -y nginx
```

---

## 5. Action Items for Phase 3

- [ ] Rebase `src/php-fpm/Dockerfile` from `ubuntu:26.04` to `ubuntu:22.04`
- [ ] Rebase `src/nginx/Dockerfile` from `ubuntu:26.04` to `ubuntu:22.04`
- [ ] Pin PHP to `php8.1-fpm` (or `php8.3-fpm` via PPA if justified)
- [ ] Pin NGINX to ubuntu:22.04 default (1.18) or add nginx.org repo for 1.27+
- [ ] Create `src/dx-o2-agents/Dockerfile` based on `ubuntu:22.04`
- [ ] Validate that all three container images resolve Broadcom agent `.deb` dependencies
