# Broadcom DX O2 Agent Setup Guide

This guide covers every step required to obtain, install, build, and verify the
four Broadcom monitoring components used in BPA-Demo:

| Component | Binary / file | Injected into |
|---|---|---|
| Infrastructure Agent (APMIA) | `bin/APMIAgent` | `dx-o2-agents` sidecar container |
| Business Transaction Listener (BTL) | `bin/btl` | `dx-o2-agents` sidecar container |
| PHP Probe | `extensions/PHPAgent/wily_php_agent.so` + `.ini` | `php-fpm` container (at startup) |
| BPA WebServer Plugin | `extensions/WebServerPlugin/ngx_http_ca_plugin_filter_module.so` | `nginx` container (at startup) |

All four components ship in a **single installer archive** — one download covers
everything.

---

## 1. Compatibility matrix

Verify that the APMIA version you download is compatible with the project's
runtime stack before placing the archive in the build tree.

| Runtime | Project version | APMIA requirement | Status |
|---|---|---|---|
| PHP | 8.1 (ubuntu:22.04) | PHP Probe ≤ 8.4 | ✓ within ceiling |
| NGINX | 1.18 (ubuntu:22.04) | BPA WebServer Plugin ≤ 1.29.x | ✓ within ceiling |
| glibc | 2.35 (ubuntu:22.04 Jammy) | Infrastructure Agent ≥ 2.17 | ✓ satisfied |
| JRE | openjdk-11-jre-headless | BTL requires JRE 11+ | ✓ installed in image |
| OS architecture | linux/amd64 | x86_64 Linux | ✓ matches `BUILD_PLATFORM` |

If you are targeting `linux/arm64` (Apple Silicon, AWS Graviton), download the
`aarch64` variant of the installer and update `BUILD_PLATFORM=linux/arm64` in
`.config`.

---

## 2. Obtaining the installer

### 2.1 Access the Broadcom Support Portal

1. Go to **https://support.broadcom.com/**
2. Log in with your Broadcom Support account (requires an active DX APM licence).
3. Navigate to:
   **My Downloads → DX Application Performance Management → DX APM Agents**

### 2.2 Select the correct download

Look for a download matching all of the following criteria:

| Field | Value to select |
|---|---|
| Product | **DX Application Performance Management** (DX APM) |
| Release | Latest available (or the release your EM is running) |
| Platform | **Linux** |
| Package type | **Infrastructure Agent** |
| File pattern | `apmia-<version>-linux.tar.gz` or `IntroscopeAgent-<version>-linux.tar.gz` |

> The exact package name depends on the APMIA release generation.  Packages
> from the 23.x and 24.x families are named `apmia-*.tar.gz`.  Older packages
> (≤ 11.x) may be named `IntroscopeAgent-*.tar.gz`.  Either format works with
> the build script as long as the file matches the glob `apmia-*.tar.gz` or you
> rename it accordingly.

### 2.3 Verify the checksum

Broadcom publishes an SHA-256 or MD5 hash alongside each download.  Verify
before placing the file in the build tree:

```bash
# Replace <published-hash> with the value from the portal
sha256sum apmia-<version>-linux.tar.gz
# output must match <published-hash> exactly
```

---

## 3. Placing the installer

```bash
# From the project root
cp ~/Downloads/apmia-<version>-linux.tar.gz \
   src/dx-o2-agents/installers/

# Verify placement
ls -lh src/dx-o2-agents/installers/
# should show exactly one .tar.gz file
```

The `installers/` directory is gitignored — the archive will never be committed:

```
src/dx-o2-agents/installers/*
!src/dx-o2-agents/installers/.gitkeep
```

Only one archive may be present at a time.  The Dockerfile build step picks the
first match of `apmia-*.tar.gz` with `ls … | head -1`.  Remove any older
archives before adding a new version.

---

## 4. What the installer creates

When `build.sh` runs, the Dockerfile executes:

```bash
install.sh -i silent -DUSER_INSTALL_DIR=/opt/apmia
```

This produces the following tree inside the container image:

```
/opt/apmia/
│
├── bin/
│   ├── APMIAgent              ← Infrastructure Agent main process (Java wrapper)
│   ├── btl                    ← Business Transaction Listener (may be absent in
│   │                              some releases; BTL is then embedded in the agent)
│   └── apmia-watchdog         ← optional watchdog / auto-restart helper
│
├── config/
│   ├── IntroscopeAgent.profile.template   ← our runtime-rendered copy (overrides
│   │                                           the installer default at pod start)
│   ├── IntroscopeAgent.profile            ← rendered from template by entrypoint.sh
│   └── ...
│
├── extensions/
│   │
│   ├── PHPAgent/                          ← PHP Probe package
│   │   ├── wily_php_agent.so              ← PHP extension shared library (PHP 8.1 / amd64)
│   │   ├── wily_php_agent.ini             ← PHP INI snippet (extension=wily_php_agent.so)
│   │   └── install.sh                     ← optional probe self-installer helper
│   │
│   └── WebServerPlugin/                   ← BPA WebServer Plugin package
│       ├── ngx_http_ca_plugin_filter_module.so   ← NGINX dynamic module (1.18 / amd64)
│       ├── webserver_plugin.ini           ← BPA plugin configuration file
│       └── ...
│
├── logs/
│   └── IntroscopeAgent.log                ← populated at runtime; size-capped 50 MB
│
└── ...
```

> **Exact sub-paths vary by APMIA release generation.**  The injection scripts
> in `src/php-fpm/entrypoint.sh` and `src/nginx/entrypoint.sh` check for the
> expected files with `-f` guards and log clearly when they are absent, so a
> structural change in a new release produces a visible warning rather than a
> silent failure.

---

## 5. Building the dx-o2-agents image

Once the installer is in place, run the standard build script:

```bash
build-scripts/build.sh
```

`build.sh` Step 4 detects the installer automatically and builds the
`dx-o2-agents` image.  You will see output similar to:

```
[build] Building dx-o2-agents: registry.example.com/php-demo/dx-o2-agents:1.0.0b3
...
 => Installing from: /tmp/installers/apmia-24.x.x-linux.tar.gz
 => Infrastructure Agent installed at: /opt/apmia
[build] dx-o2-agents built successfully.
```

If the installer is absent, Step 4 is skipped with an informative message and
the `php-fpm` / `nginx` builds complete normally — the application stack runs
without APM instrumentation.

### Build once, share always

The `dx-o2-agents` image only needs to be rebuilt when:

- A new APMIA version is being adopted.
- The EM hostname or agent configuration template changes.

The `php-fpm` and `nginx` images **do not need to be rebuilt** when the agent
version changes — they receive probe files at container startup via the shared
emptyDir volume.

---

## 6. Runtime injection — how each component is loaded

### 6.1 Infrastructure Agent + BTL (`dx-o2-agent` sidecar)

`src/dx-o2-agents/entrypoint.sh` runs inside the sidecar container:

```
1. Validates APMIA_EM_HOST is set (fatal error if missing).
2. Renders /opt/apmia/config/IntroscopeAgent.profile from template
   using envsubst (replaces ${APMIA_EM_HOST}, ${APMIA_EM_PORT}, etc.).
3. Starts ${APMIA_HOME}/bin/APMIAgent in the background.
4. Starts ${APMIA_HOME}/bin/btl in the background (if the binary exists).
5. Sets SIGTERM/SIGINT trap → graceful shutdown of both processes.
6. wait $AGENT_PID — keeps the container alive for the pod's lifetime.
```

### 6.2 PHP Probe (`php-fpm` container startup)

`src/php-fpm/entrypoint.sh` runs at php-fpm container startup.  The emptyDir
volume mounted at `/opt/apmia` (populated by `dxo2-init`) is the source:

```
Check: /opt/apmia/extensions/PHPAgent/wily_php_agent.ini exists?
  YES →
    Copy wily_php_agent.so  →  $(php8.1 -r 'echo ini_get("extension_dir");')/
    Copy wily_php_agent.ini  →  /etc/php/8.1/mods-available/
    Symlink                  →  /etc/php/8.1/fpm/conf.d/99-wily_php_agent.ini
    Run install.sh --silent  (if present)
    → PHP probe active; php-fpm workers carry APM instrumentation.
  NO  →
    Log "DX O2 agent volume not mounted" and continue without probe.
    → php-fpm starts cleanly; no APM instrumentation.
```

### 6.3 BPA WebServer Plugin (`nginx` container startup)

`src/nginx/entrypoint.sh` runs at nginx container startup.  Same emptyDir
volume is the source:

```
Check: /opt/apmia/extensions/WebServerPlugin/
         ngx_http_ca_plugin_filter_module.so exists?
  YES →
    Write:  /etc/nginx/modules-enabled/bpa.conf
            → load_module /opt/apmia/extensions/WebServerPlugin/
                          ngx_http_ca_plugin_filter_module.so;
    Copy:   webserver_plugin.ini → /etc/nginx/bpa_plugin.ini
    → nginx -t validates the load_module directive.
    → NGINX starts with BPA module loaded.
  NO  →
    Remove stale /etc/nginx/modules-enabled/bpa.conf (if any).
    Log "BPA module not found" and continue.
    → NGINX starts cleanly; no BPA instrumentation.
```

The `load_module` directive works because `nginx.conf` (both in the image and in
the Kubernetes ConfigMap) includes the `modules-enabled/` directory at the
**top-level scope before `events {}`**:

```nginx
# Required for dynamic module loading — must precede events {}
include /etc/nginx/modules-enabled/*.conf;

worker_processes auto;
...
events { ... }
```

Removing this include breaks BPA injection silently.

### 6.4 Kubernetes init-container flow (complete sequence)

```
Pod startup
  │
  ├─ initContainer: dxo2-init
  │    Image: dx-o2-agents
  │    Command: cp -a /opt/apmia/. /apmia-share/
  │    VolumeMount: apmia-share → /apmia-share  (readWrite)
  │    → Exits 0; emptyDir now contains full agent tree.
  │
  ├─ initContainer: mariadb-lock-cleanup  (independent; removes stale DB locks)
  │
  └─ Containers start (in parallel after all initContainers exit 0):
       │
       ├─ dx-o2-agent sidecar
       │    VolumeMount: (none – uses image-baked /opt/apmia)
       │    Runs: APMIAgent + btl → connects to EM
       │
       ├─ nginx
       │    VolumeMount: apmia-share → /opt/apmia  (readOnly)
       │    Entrypoint: detects BPA .so → loads module → starts nginx
       │
       ├─ php-fpm
       │    VolumeMount: apmia-share → /opt/apmia  (readOnly)
       │    Entrypoint: detects PHP probe → copies .so + .ini → starts php-fpm
       │
       └─ mariadb  (no agent involvement)
```

---

## 7. Configuring the agent connection

All agent configuration flows from `.config` into `values.local.yaml` via
`deploy.sh`.  There are no credentials or hostnames in any tracked file.

Edit `.config`:

```bash
# Minimum required
APMIA_EM_HOST="em.example.internal"  # EM hostname or IP

# Optional (shown with defaults)
APMIA_EM_PORT="5001"                 # 5001 plain-text; 5443 for TLS
APMIA_AGENT_NAME="bpa-demo-agent"   # shown in EM agent tree
APMIA_APP_NAME="BPA-Demo"           # application grouping in EM console
APMIA_LOG_LEVEL="INFO"              # DEBUG | INFO | WARN | ERROR
```

`deploy.sh` sets `dxo2.enabled: true` in the generated `values.local.yaml`
automatically when `APMIA_EM_HOST` is non-empty.

### Agent profile rendering

The file `src/dx-o2-agents/config/IntroscopeAgent.profile.template` is copied
into the image at build time.  At container startup `entrypoint.sh` renders it
with `envsubst`:

```
${APMIA_EM_HOST}    → introscope.agent.enterprisemanager.transport.tcp.host.DEFAULT
${APMIA_EM_PORT}    → introscope.agent.enterprisemanager.transport.tcp.port.DEFAULT
${APMIA_AGENT_NAME} → introscope.agent.agentName
${APMIA_APP_NAME}   → introscope.agent.applicationName
${APMIA_LOG_LEVEL}  → log4j.logger.IntroscopeAgent
```

To change the EM endpoint after deployment, update `.config` and re-run
`deploy.sh` — the pod restarts with the new rendered profile.

### TLS Enterprise Manager (port 5443)

If your EM uses TLS, update the profile template before building the image.
Change the socket factory line in
`src/dx-o2-agents/config/IntroscopeAgent.profile.template`:

```properties
# Replace DefaultSocketFactory with the TLS factory:
introscope.agent.enterprisemanager.transport.tcp.socketfactory.DEFAULT=\
    com.wily.isengard.postofficehub.link.net.SSLSocketFactory

# Add keystore settings if using mutual TLS:
introscope.agent.enterprisemanager.transport.tcp.socketfactory.DEFAULT.keyStoreFile=\
    /opt/apmia/config/keystore.jks
introscope.agent.enterprisemanager.transport.tcp.socketfactory.DEFAULT.keyStorePassword=\
    changeme
```

Set `APMIA_EM_PORT="5443"` in `.config`.

---

## 8. Verifying agent activity

### 8.1 Check container logs

```bash
# dx-o2-agent sidecar — should show "Infrastructure Agent started"
kubectl logs -n php-demo <pod> -c dx-o2-agent

# php-fpm — should show "DX O2 PHP probe active"
kubectl logs -n php-demo <pod> -c php-fpm

# nginx — should show "BPA WebServer Plugin active"
kubectl logs -n php-demo <pod> -c nginx
```

Expected successful output:

```
# dx-o2-agent
[entrypoint] Rendering agent profile from template...
[entrypoint] Agent profile written to /opt/apmia/config/IntroscopeAgent.profile
[entrypoint] Starting Broadcom Infrastructure Agent...
[entrypoint]   EM host  : em.example.internal:5001
[entrypoint]   Agent    : bpa-demo-agent
[entrypoint]   App      : BPA-Demo
[entrypoint] Infrastructure Agent started (PID 12)
[entrypoint] Starting Business Transaction Listener...
[entrypoint] BTL started (PID 34)

# php-fpm
[entrypoint] Injecting DX O2 PHP probe from /opt/apmia/extensions/PHPAgent
[entrypoint]   Copied wily_php_agent.so → /usr/lib/php/20210902/
[entrypoint]   Probe INI installed at /etc/php/8.1/fpm/conf.d/99-wily_php_agent.ini
[entrypoint] DX O2 PHP probe active – APM instrumentation enabled.

# nginx
[entrypoint] Injecting BPA WebServer Plugin from /opt/apmia/extensions/WebServerPlugin/...
[entrypoint]   Wrote /etc/nginx/modules-enabled/bpa.conf
[entrypoint]   Copied BPA plugin config → /etc/nginx/bpa_plugin.ini
[entrypoint] BPA WebServer Plugin active – BPA instrumentation enabled.
```

### 8.2 Check monitoring HTTP response headers

Every PHP response carries APM context headers that confirm probe activity:

```bash
curl -si https://php-demo.example.com/?page=shop | grep -i "^x-"
```

Expected:
```
X-Page-ID: SHOP-LIST-ALL
X-User-Role: anonymous
X-Basket-Total: 0.00
```

The presence of `X-Page-ID` confirms the PHP probe is intercepting requests.

### 8.3 Check the PHP extension is loaded

```bash
kubectl exec -n php-demo <pod> -c php-fpm -- \
  php -r 'var_dump(extension_loaded("wily_php_agent"));'
# expected: bool(true)

kubectl exec -n php-demo <pod> -c php-fpm -- \
  php -m | grep wily
# expected: wily_php_agent
```

### 8.4 Check the NGINX module is loaded

```bash
kubectl exec -n php-demo <pod> -c nginx -- \
  nginx -T 2>/dev/null | grep load_module
# expected: load_module /opt/apmia/extensions/WebServerPlugin/ngx_http_ca_plugin_filter_module.so;

kubectl exec -n php-demo <pod> -c nginx -- \
  cat /etc/nginx/modules-enabled/bpa.conf
# expected: load_module /opt/apmia/.../ngx_http_ca_plugin_filter_module.so;
```

### 8.5 Confirm agent connects to the EM

```bash
kubectl exec -n php-demo <pod> -c dx-o2-agent -- \
  tail -20 /opt/apmia/logs/IntroscopeAgent.log
```

Look for lines containing `Connected to` or `Successfully connected` rather than
`Connection refused` or `UnknownHostException`.

---

## 9. Common problems and fixes

### Probe files not found after container start

**Symptom:** php-fpm or nginx logs `"agent volume not mounted"` even though
`dxo2.enabled=true` in the Helm values.

**Cause:** The `dxo2-init` initContainer failed or the `apmia-share` emptyDir
was not mounted.

**Fix:**
```bash
# Check whether dxo2-init completed successfully
kubectl describe pod -n php-demo <pod> | grep -A5 "dxo2-init"

# Check initContainer logs
kubectl logs -n php-demo <pod> -c dxo2-init
# should end with: "Done – N entries in /apmia-share"
```

If the initContainer failed, the most likely cause is that the dx-o2-agents
image was built without a valid installer (the archive was absent or corrupt).
Rebuild with a valid installer and redeploy.

### NGINX fails to start with "unknown directive load_module"

**Symptom:** nginx container crashes with:
```
nginx: [emerg] unknown directive "load_module" in /etc/nginx/modules-enabled/bpa.conf
```

**Cause:** The `include /etc/nginx/modules-enabled/*.conf;` directive is absent
from `nginx.conf` or is placed inside `http {}` / `events {}` instead of at the
top-level scope.

**Fix:** Verify `helm/php-demo/templates/configmap.yaml`:
```nginx
# This line MUST appear before worker_processes and events {}
include /etc/nginx/modules-enabled/*.conf;

worker_processes auto;
...
```

### NGINX fails with "module is not binary compatible"

**Symptom:**
```
nginx: [emerg] module ".../ngx_http_ca_plugin_filter_module.so" is not binary compatible
```

**Cause:** The NGINX version inside the container does not match the version the
BPA plugin `.so` was compiled against.

**Fix:** The project pins NGINX 1.18 from ubuntu:22.04 repos which is within the
BPA plugin's supported range (≤ 1.29.x).  This error indicates either:
- A different NGINX version snuck in (check `Dockerfile`).
- A mismatched APMIA version was downloaded.

Verify the NGINX version in the running container:
```bash
kubectl exec -n php-demo <pod> -c nginx -- nginx -v
# expected: nginx version: nginx/1.18.0 (Ubuntu)
```

### PHP probe loads but APM shows no data

**Cause:** The Infrastructure Agent (`dx-o2-agent` sidecar) is not connected to
the Enterprise Manager.

**Fix:** Check EM connectivity from inside the pod:
```bash
kubectl exec -n php-demo <pod> -c dx-o2-agent -- \
  curl -s --connect-timeout 3 telnet://${APMIA_EM_HOST}:${APMIA_EM_PORT} \
  && echo "reachable" || echo "unreachable"
```

Ensure `APMIA_EM_HOST` and `APMIA_EM_PORT` in `.config` are correct and that
the EM is network-reachable from the Kubernetes cluster.

### BTL binary not found

**Symptom:** Log line:
```
[entrypoint] BTL binary not found at /opt/apmia/bin/btl – BTL may be embedded in the Infrastructure Agent.
```

**Cause:** In some APMIA releases the BTL is compiled into the agent process
rather than shipped as a separate binary.  This is not an error.

**Fix:** No action required.  The agent automatically activates the BTL
subsystem internally.  Check the EM console to confirm BTL data is flowing.

### Docker Compose: agent volume

Docker Compose does not include a DX O2 agent container by default.  The
application runs without instrumentation, which is intentional for local
development.  If you need to test agent behaviour locally, add a volume
stanza to `docker-compose.yml`:

```yaml
services:
  dxo2:
    image: ${REGISTRY}/${IMAGE_PREFIX}/dx-o2-agents:${IMAGE_TAG}
    build:
      context: ./src/dx-o2-agents
    environment:
      APMIA_EM_HOST: ${APMIA_EM_HOST}
      APMIA_EM_PORT: ${APMIA_EM_PORT:-5001}
      APMIA_AGENT_NAME: ${APMIA_AGENT_NAME:-bpa-demo-local}
      APMIA_APP_NAME: ${APMIA_APP_NAME:-BPA-Demo}
      APMIA_LOG_LEVEL: ${APMIA_LOG_LEVEL:-DEBUG}
    volumes:
      - apmia_data:/opt/apmia

  phpfpm:
    ...
    volumes:
      - apmia_data:/opt/apmia:ro

  nginx:
    ...
    volumes:
      - apmia_data:/opt/apmia:ro

volumes:
  mariadb_data:
  apmia_data:      # ← add this
```

This `docker-compose.yml` change is intentionally not included by default because
it requires the installer to be present and an EM to be reachable.

---

## 10. Complete end-to-end build checklist

```
[ ] 1. Obtain apmia-<version>-linux.tar.gz from support.broadcom.com
[ ] 2. Verify sha256sum against the portal-published hash
[ ] 3. Place file in src/dx-o2-agents/installers/  (only one .tar.gz allowed)
[ ] 4. Set APMIA_EM_HOST in .config (and APMIA_EM_PORT if not 5001)
[ ] 5. Run: build-scripts/build.sh
       Confirm: "[build] dx-o2-agents built successfully."
[ ] 6. Run: build-scripts/push.sh
       (omit --skip-dxo2 so the dx-o2-agents image is pushed)
[ ] 7. Run: build-scripts/deploy.sh
       deploy.sh sets dxo2.enabled: true automatically when APMIA_EM_HOST is set
[ ] 8. Verify: kubectl get pods -n php-demo -w
       Wait for 3/3 or 4/4 containers Running
[ ] 9. Check: kubectl logs -n php-demo <pod> -c php-fpm | grep "probe active"
[  ] 10. Check: kubectl logs -n php-demo <pod> -c nginx | grep "BPA WebServer Plugin active"
[  ] 11. Check: kubectl logs -n php-demo <pod> -c dx-o2-agent | grep "Infrastructure Agent started"
[  ] 12. Verify in EM console: agent tree shows bpa-demo-agent under BPA-Demo
```
