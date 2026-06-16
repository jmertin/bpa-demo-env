# Broadcom DX O2 Agent Setup Guide

This guide covers every step required to obtain, build, and verify the
Broadcom DX O2 monitoring components used in BPA-Demo.

| Component | Installer package | Runtime location |
|---|---|---|
| Infrastructure Agent (APMIA) | `PHP_apmia_*.tar` | `/opt/apmia/` in `dx-o2-agents` image |
| Business Transaction Listener (BTL) | `Business_Transaction_Listener.zip` | `/opt/btlistener/` in `dx-o2-agents` image |
| PHP Probe | `PHP_apmia_*.tar` (bundled) | `/opt/apmia/extensions/PHPAgent/` |
| BPA WebServer Plugin | `Business_Payload_Analyzer_WebServer_Plugins.zip` | `/opt/apmia/extensions/WebServerPlugin/` |

The three packages are downloaded from the **DX O2 interface** (not from
support.broadcom.com).  The DX O2 download includes a pre-configured
`IntroscopeAgent.profile` with your tenant's EM URL and JWT credential already
embedded — the agent connects to your DX O2 backend automatically without any
manual configuration.

---

## 1. Compatibility matrix

Verify that the DX O2 package versions are compatible with the project's
runtime stack before placing them in the build tree.

| Runtime | Project version | APMIA requirement | Status |
|---|---|---|---|
| PHP | 8.1 (ubuntu:22.04) | PHP Probe ≤ 8.4 | ✓ within ceiling |
| NGINX | 1.18 (ubuntu:22.04) | BPA plugin ≤ 1.29.x (1.17.1 module ABI-compatible with 1.18) | ✓ within ceiling |
| glibc | 2.35 (ubuntu:22.04 Jammy) | Infrastructure Agent ≥ 2.17 | ✓ satisfied |
| JRE | Bundled in `PHP_apmia*.tar` | BTL requires JRE 11+ | ✓ bundled JRE used |
| OS architecture | linux/amd64 | x86_64 Linux | ✓ matches `BUILD_PLATFORM` |

If targeting `linux/arm64` (Apple Silicon, AWS Graviton), download the
`aarch64` variant and update `BUILD_PLATFORM=linux/arm64` in `.config`.

---

## 2. Obtaining the packages

### 2.1 Navigate to the DX O2 Agents download area

1. Log in to your **DX O2 interface** (the SaaS portal, e.g.
   `https://dx.dxi-eu1.saas.broadcom.com/` for the EU1 region).
2. Go to **Administration → Agents** (or the equivalent section in your tenant).
3. You will find separate download links for each component.

### 2.2 Download the three required packages

| Package | DX O2 navigation | File name pattern |
|---|---|---|
| Infrastructure Agent + PHP Probe | Agents → Infrastructure Agent → Linux | `PHP_apmia_<date>_v<n>.tar` |
| Business Transaction Listener | Agents → Business Transaction Listener | `Business_Transaction_Listener.zip` |
| BPA WebServer Plugin | Agents → Business Payload Analyzer WebServer Plugins | `Business_Payload_Analyzer_WebServer_Plugins.zip` |

> **Why these packages and not support.broadcom.com?**
> Packages downloaded from the DX O2 interface include a pre-configured
> `IntroscopeAgent.profile` with your tenant's WSS EM URL and JWT credential
> already baked in.  The agent connects without any manual EM host configuration.
> Packages from the Broadcom Support Portal require you to supply the EM URL and
> credentials separately and are not pre-configured.

### 2.3 Verify the downloads

Broadcom does not currently publish SHA-256 hashes alongside DX O2 downloads.
At minimum, verify the file sizes are non-zero and that the archives open
correctly:

```bash
# Should list many files ending in .jar, .sh, .so, etc.
tar -tf PHP_apmia_*.tar | head -20
unzip -l Business_Transaction_Listener.zip | tail -5
unzip -l Business_Payload_Analyzer_WebServer_Plugins.zip | tail -5
```

---

## 3. Placing the packages

```bash
# From the project root
cp ~/Downloads/PHP_apmia_*.tar \
   src/dx-o2-agents/installers/
cp ~/Downloads/Business_Transaction_Listener.zip \
   src/dx-o2-agents/installers/
cp ~/Downloads/Business_Payload_Analyzer_WebServer_Plugins.zip \
   src/dx-o2-agents/installers/

# Verify placement
ls -lh src/dx-o2-agents/installers/
# should show exactly three files: PHP_apmia*.tar, Business_Transaction_Listener.zip,
# Business_Payload_Analyzer_WebServer_Plugins.zip
```

The `installers/` directory is gitignored — the archives are never committed:

```
src/dx-o2-agents/installers/*
!src/dx-o2-agents/installers/.gitkeep
```

Only one copy of each archive may be present at a time.  The Dockerfile picks
the first match of each glob with `ls … | head -1`.  Remove older versions
before adding new ones.

---

## 4. What the Dockerfile extracts

`build.sh` builds the `dx-o2-agents` image.  The Dockerfile extracts the three
archives in sequence and produces the following layout:

### 4.1 `/opt/apmia/` (from `PHP_apmia*.tar`)

The `PHP_apmia*.tar` archive has a single top-level `apmia/` directory.
Extracting to `/opt` creates `/opt/apmia/`:

```
/opt/apmia/
│
├── bin/
│   └── APMIAgent.sh               ← IA start script (Java Service Wrapper)
│
├── APMIACtrl.sh                   ← Agent control script
│
├── jre/                           ← Bundled JRE (set as JAVA_HOME at runtime)
│
├── core/
│   └── config/
│       └── IntroscopeAgent.profile    ← Pre-configured: tenant EM URL (WSS) + JWT
│                                          NEVER overwrite — entrypoint patches only
│                                          agentName and application.name
│
├── probe/
│   ├── lib/
│   │   └── php81/
│   │       └── wily_php_agent.so      ← PHP 8.1 probe extension (original path)
│   └── wily_php_agent.ini             ← PHP INI snippet (original path)
│
├── extensions/
│   ├── PHPAgent/
│   │   ├── wily_php_agent.so          ← normalised copy (Dockerfile step)
│   │   └── wily_php_agent.ini         ← normalised copy (Dockerfile step)
│   └── WebServerPlugin/
│       └── ngx_http_ca_plugin_filter_module.so  ← nginx 1.17.1 module (from BPA zip)
│
└── logs/                          ← Runtime log directory
```

### 4.2 `/opt/btlistener/` (from `Business_Transaction_Listener.zip`)

```
/opt/btlistener/
├── bin/
│   └── BTListener.sh              ← BTL start script
├── conf/
│   └── custom/
│       └── application.properties ← Pre-configured: DXC URL, tenantId, port 8000
└── ...
```

### 4.3 PHP Probe normalisation step

The `php-fpm` entrypoint expects the probe files at
`/opt/apmia/extensions/PHPAgent/`.  Because the DX O2 installer places them at
`probe/lib/php81/`, the Dockerfile adds a normalisation step that copies them:

```dockerfile
RUN mkdir -p /opt/apmia/extensions/PHPAgent && \
    cp /opt/apmia/probe/lib/php81/wily_php_agent.so /opt/apmia/extensions/PHPAgent/ && \
    cp /opt/apmia/probe/wily_php_agent.ini          /opt/apmia/extensions/PHPAgent/
```

This keeps the entrypoint path logic consistent regardless of APMIA release layout.

---

## 5. Building the dx-o2-agents image

Once the three archives are in place, run the standard build script:

```bash
build-scripts/build.sh
```

`build.sh` detects the `PHP_apmia*.tar` archive and builds the `dx-o2-agents`
image.  Expected build output:

```
[build] Building dx-o2-agents: registry.example.com/php-demo/dx-o2-agents:1.0.0b3
...
 => Extracting APMIA from: PHP_apmia_20250301_v5.tar
 => Infrastructure Agent extracted to /opt/apmia
 => PHP probe files installed to /opt/apmia/extensions/PHPAgent/
 => Extracting BTL from: Business_Transaction_Listener.zip
 => BTL extracted to /opt/btlistener
 => Extracting BPA plugin from: Business_Payload_Analyzer_WebServer_Plugins.zip
 => BPA WebServer Plugin installed to /opt/apmia/extensions/WebServerPlugin/
[build] dx-o2-agents built successfully.
```

If any archive is absent, the Dockerfile build fails with a clear error message
identifying which package is missing.

> The `php-fpm` and `nginx` images **do not need to be rebuilt** when the
> DX O2 package version changes — they receive probe files at container startup
> via the shared emptyDir volume.

---

## 6. Runtime injection — how each component is loaded

### 6.1 Infrastructure Agent + BTL (`dx-o2-agent` sidecar)

`src/dx-o2-agents/entrypoint.sh` runs inside the sidecar:

```
1. Sets JAVA_HOME to the bundled JRE (/opt/apmia/jre/).
2. Verifies pre-configured profile exists at
   /opt/apmia/core/config/IntroscopeAgent.profile
   (fatal error if missing — wrong installer format).
3. Patches only two fields in the profile:
     introscope.agent.agentName    ← from APMIA_AGENT_NAME env var
     introscope.agent.application.name ← from APMIA_APP_NAME env var
   All agentManager.* lines (EM URL, credential, transport) are left intact.
4. Starts APMIAgent.sh in 'console' mode (foreground) via Java Service Wrapper.
5. Starts BTListener.sh in the background (if the script is present).
6. Sets SIGTERM/SIGINT trap → graceful shutdown of both processes.
7. wait $AGENT_PID — keeps the container alive for the pod's lifetime.
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
    Patch wily_php_agent.ini:
      wily_php_agent.collectorHost = ${APMIA_PHP_COLLECTOR_HOST} (default 127.0.0.1)
      wily_php_agent.collectorPort = ${APMIA_PHP_COLLECTOR_PORT} (default 5005)
      wily_php_agent.application.name = ${APMIA_APP_NAME}
      wily_php_agent.logdir = "/tmp"
    → PHP probe active; php-fpm workers carry APM instrumentation.
  NO  →
    Log "DX O2 agent volume not mounted" and continue without probe.
    → php-fpm starts cleanly; no APM instrumentation.
```

**IPC note:** PHP probe → IA collector communication uses port 5005 on
`127.0.0.1` (Kubernetes pod loopback, all containers share the same network
namespace).

### 6.3 BPA WebServer Plugin (`nginx` container startup)

`src/nginx/entrypoint.sh` runs at nginx container startup:

```
Check: /opt/apmia/extensions/WebServerPlugin/
         ngx_http_ca_plugin_filter_module.so exists?
  YES →
    Write:  /etc/nginx/modules-enabled/bpa.conf
            → load_module /opt/apmia/extensions/WebServerPlugin/
                          ngx_http_ca_plugin_filter_module.so;
    Log BTL address (${APMIA_BTL_HOST}:${APMIA_BTL_PORT}).
    → nginx -t validates the load_module directive.
    → NGINX starts with BPA module loaded.
  NO  →
    Remove stale /etc/nginx/modules-enabled/bpa.conf (if any).
    Log "BPA module not found" and continue.
    → NGINX starts cleanly; no BPA instrumentation.
```

> The DX O2 BPA package ships only the `.so` file; there is no separate
> `webserver_plugin.ini` in the current package version.

The `load_module` directive works because `nginx.conf` (both in the image and
in the Kubernetes ConfigMap) includes the `modules-enabled/` directory at the
**top-level scope before `events {}`**:

```nginx
# Required for dynamic module loading — must precede events {}
include /etc/nginx/modules-enabled/*.conf;

worker_processes auto;
...
events { ... }
```

### 6.4 Kubernetes init-container flow (complete sequence)

```
Pod startup
  │
  ├─ initContainer: dxo2-init
  │    Image: dx-o2-agents
  │    Command: cp -a /opt/apmia/. /apmia-share/
  │    VolumeMount: apmia-share → /apmia-share  (readWrite)
  │    → Exits 0; emptyDir now contains full agent tree including probe and BPA .so.
  │
  ├─ initContainer: mariadb-lock-cleanup  (removes stale DB lock files)
  │
  └─ Containers start (in parallel after all initContainers exit 0):
       │
       ├─ dx-o2-agent sidecar
       │    Image-baked /opt/apmia (VOLUME)
       │    JAVA_HOME=/opt/apmia/jre
       │    Runs: APMIAgent.sh console → connects to pre-configured EM (WSS)
       │    Runs: BTListener.sh → listens on 127.0.0.1:8000 for BPA plugin
       │    Named ports: php-collector:5005, btl:8000
       │
       ├─ nginx
       │    VolumeMount: apmia-share → /opt/apmia  (readOnly)
       │    Entrypoint: detects BPA .so → writes load_module → starts nginx
       │    Env: APMIA_BTL_HOST=127.0.0.1, APMIA_BTL_PORT=8000
       │
       ├─ php-fpm
       │    VolumeMount: apmia-share → /opt/apmia  (readOnly)
       │    Entrypoint: detects PHP probe → copies .so + patches .ini → starts php-fpm
       │    Env: APMIA_PHP_COLLECTOR_HOST=127.0.0.1, APMIA_PHP_COLLECTOR_PORT=5005
       │
       └─ mariadb  (no agent involvement)
```

---

## 7. Configuring the deployment

### 7.1 DX O2 interface download (pre-configured — minimal setup)

When using packages downloaded from the DX O2 interface, the EM URL and
credential are already embedded in `IntroscopeAgent.profile`.  Only set the
agent identity fields in `.config`:

```bash
# Agent identity – displayed in the DX O2 console
APMIA_AGENT_NAME="bpa-demo-agent"
APMIA_APP_NAME="BPA-Demo"
APMIA_LOG_LEVEL="INFO"     # DEBUG | INFO | WARN | ERROR

# Leave APMIA_EM_HOST empty — EM connection is pre-configured in the profile.
APMIA_EM_HOST=""
```

`deploy.sh` sets `dxo2.enabled: true` automatically when `APMIA_EM_HOST` is
non-empty.  When using the pre-configured package, you must set it to a
non-empty placeholder to enable the agent stack, or set `dxo2.enabled: true`
directly in `values.local.yaml`.

> **Tip:** Set `APMIA_EM_HOST` to a single space `" "` or the actual EM
> hostname shown in the DX O2 interface (it is informational only — the agent
> uses the profile's pre-configured URL).

### 7.2 Same-pod IPC addresses

All four containers in the BPA-Demo pod share `127.0.0.1` (Kubernetes pod
network namespace).  The defaults match the DX O2 installer:

| Variable | Default | Purpose |
|---|---|---|
| `APMIA_PHP_COLLECTOR_HOST` | `127.0.0.1` | PHP probe → IA collector |
| `APMIA_PHP_COLLECTOR_PORT` | `5005` | IA PHP collector port (from `wily_php_agent.ini`) |
| `APMIA_BTL_HOST` | `127.0.0.1` | BPA plugin → BTL |
| `APMIA_BTL_PORT` | `8000` | BTL listener port (from BTL `application.properties`) |

Override these only if you run the `dx-o2-agent` sidecar in a separate pod or
service.

---

## 8. Verifying agent activity

### 8.1 Check container logs

```bash
# dx-o2-agent sidecar — should show agent starting and connecting
kubectl logs -n php-demo <pod> -c dx-o2-agent

# php-fpm — should show "DX O2 PHP probe active"
kubectl logs -n php-demo <pod> -c php-fpm

# nginx — should show "BPA WebServer Plugin active"
kubectl logs -n php-demo <pod> -c nginx
```

Expected successful output:

```
# dx-o2-agent
[entrypoint] Using pre-configured agent profile: /opt/apmia/core/config/IntroscopeAgent.profile
[entrypoint]   Patching agent name  : bpa-demo-agent
[entrypoint]   Patching app name    : BPA-Demo
[entrypoint] Agent profile ready.
[entrypoint] Starting Broadcom Infrastructure Agent (console mode)...
[entrypoint]   Agent : bpa-demo-agent
[entrypoint]   App   : BPA-Demo
[entrypoint] Infrastructure Agent started (PID 12)
[entrypoint] Starting Business Transaction Listener...
[entrypoint] BTL started (PID 34)

# php-fpm
[entrypoint] Injecting DX O2 PHP probe from /opt/apmia/extensions/PHPAgent
[entrypoint]   Copied wily_php_agent.so → /usr/lib/php/20210902/
[entrypoint]   Probe INI installed at /etc/php/8.1/fpm/conf.d/99-wily_php_agent.ini
[entrypoint]   PHP probe IPC: 127.0.0.1:5005
[entrypoint] DX O2 PHP probe active – APM instrumentation enabled.

# nginx
[entrypoint] Injecting BPA WebServer Plugin from /opt/apmia/extensions/WebServerPlugin/ngx_http_ca_plugin_filter_module.so
[entrypoint]   Wrote /etc/nginx/modules-enabled/bpa.conf
[entrypoint]   BPA → BTL: 127.0.0.1:8000
[entrypoint] BPA WebServer Plugin active – BPA instrumentation enabled.
```

### 8.2 Check the PHP extension is loaded

```bash
kubectl exec -n php-demo <pod> -c php-fpm -- \
  php -r 'var_dump(extension_loaded("wily_php_agent"));'
# expected: bool(true)

kubectl exec -n php-demo <pod> -c php-fpm -- \
  php -m | grep wily
# expected: wily_php_agent
```

### 8.3 Check the NGINX module is loaded

```bash
kubectl exec -n php-demo <pod> -c nginx -- \
  nginx -T 2>/dev/null | grep load_module
# expected: load_module /opt/apmia/extensions/WebServerPlugin/ngx_http_ca_plugin_filter_module.so;

kubectl exec -n php-demo <pod> -c nginx -- \
  cat /etc/nginx/modules-enabled/bpa.conf
# expected: load_module /opt/apmia/extensions/WebServerPlugin/ngx_http_ca_plugin_filter_module.so;
```

### 8.4 Confirm agent connects to DX O2

```bash
kubectl exec -n php-demo <pod> -c dx-o2-agent -- \
  tail -30 /opt/apmia/logs/IntroscopeAgent.log
```

Look for lines containing `Connected to` or `Successfully connected` rather than
`Connection refused` or `UnknownHostException`.  The pre-configured profile uses
WSS (`wss://apmgw.dxi-eu1.saas.broadcom.com:443`); ensure your cluster can reach
this endpoint.

---

## 9. Common problems and fixes

### Wrong installer format (support.broadcom.com download)

**Symptom:** Build fails with `APMIAgent.sh not found` or
`pre-configured profile not found`.

**Cause:** The archive was downloaded from support.broadcom.com (named
`apmia-*.tar.gz`) rather than from the DX O2 interface.  The support portal
archive uses a different layout and does not include a pre-configured profile.

**Fix:** Download the three packages from your DX O2 interface
(Agents → Infrastructure Agent → Linux, etc.).

### Probe files not found after container start

**Symptom:** php-fpm or nginx logs `"DX O2 agent volume not mounted"` even
though `dxo2.enabled=true`.

**Cause:** The `dxo2-init` initContainer failed, or the `apmia-share` emptyDir
was not mounted.

**Fix:**
```bash
kubectl describe pod -n php-demo <pod> | grep -A5 "dxo2-init"
kubectl logs -n php-demo <pod> -c dxo2-init
# should end with: "Done – N entries in /apmia-share"
```

If the initContainer failed, rebuild with valid packages and redeploy.

### NGINX fails to start with "unknown directive load_module"

**Symptom:** nginx container crashes:
```
nginx: [emerg] unknown directive "load_module" in /etc/nginx/modules-enabled/bpa.conf
```

**Cause:** The `include /etc/nginx/modules-enabled/*.conf;` directive is absent
from `nginx.conf` or placed inside `http {}` / `events {}` instead of the
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
nginx: [emerg] module "...ngx_http_ca_plugin_filter_module.so" is not binary compatible
```

**Cause:** The BPA plugin `.so` was built for nginx 1.17.1 and uses the same
`NGX_MODULE_VERSION` series as nginx 1.18.x.  This error indicates a version
mismatch — either a different nginx was installed in the image, or the wrong BPA
package was downloaded.

**Fix:** Confirm nginx version:
```bash
kubectl exec -n php-demo <pod> -c nginx -- nginx -v
# expected: nginx version: nginx/1.18.0 (Ubuntu)
```

### PHP probe loads but DX O2 shows no data

**Cause:** The Infrastructure Agent (`dx-o2-agent` sidecar) is not connected to
the DX O2 backend.

**Fix:** Check agent logs for connection errors:
```bash
kubectl logs -n php-demo <pod> -c dx-o2-agent | grep -i "error\|refused\|exception"
```

Ensure the cluster can reach the WSS endpoint in the pre-configured profile
(e.g. `apmgw.dxi-eu1.saas.broadcom.com:443`).  Check for firewall or proxy
restrictions on outbound WSS.

### Pre-configured profile not found (entrypoint error)

**Symptom:** dx-o2-agent container exits immediately:
```
[entrypoint] ERROR: Pre-configured agent profile not found:
             /opt/apmia/core/config/IntroscopeAgent.profile
```

**Cause:** The `PHP_apmia*.tar` archive was either extracted incorrectly or is
from the support portal (which uses a different layout).

**Fix:** Confirm the archive is the correct DX O2 download:
```bash
tar -tf PHP_apmia_*.tar | grep IntroscopeAgent.profile
# expected: apmia/core/config/IntroscopeAgent.profile
```

If the path shown is `apmia/config/IntroscopeAgent.profile` (no `core/`
subdirectory), the archive is from the support portal — obtain the correct
package from the DX O2 interface.

---

## 10. Complete end-to-end build checklist

```
[ ] 1. Log in to DX O2 interface (e.g. https://dx.dxi-eu1.saas.broadcom.com/)
[ ] 2. Download PHP_apmia_*.tar        (Agents → Infrastructure Agent → Linux)
[ ] 3. Download Business_Transaction_Listener.zip
[ ] 4. Download Business_Payload_Analyzer_WebServer_Plugins.zip
[ ] 5. Place all three archives in src/dx-o2-agents/installers/
[ ] 6. Verify archives are readable:
       tar -tf src/dx-o2-agents/installers/PHP_apmia*.tar | grep IntroscopeAgent.profile
       # must show: apmia/core/config/IntroscopeAgent.profile
[ ] 7. Set APMIA_AGENT_NAME, APMIA_APP_NAME in .config
[ ] 8. Set APMIA_EM_HOST to a non-empty value in .config (enables dxo2.enabled)
[ ] 9. Run: build-scripts/build.sh
       Confirm: "[build] dx-o2-agents built successfully."
[ ] 10. Run: build-scripts/push.sh
        (omit --skip-dxo2 so the dx-o2-agents image is pushed)
[ ] 11. Run: build-scripts/deploy.sh
        deploy.sh sets dxo2.enabled: true automatically when APMIA_EM_HOST is set
[ ] 12. Verify: kubectl get pods -n php-demo -w
        Wait for 4/4 containers Running (or 3/3 if dxo2 not yet enabled)
[ ] 13. Check: kubectl logs -n php-demo <pod> -c php-fpm | grep "probe active"
[ ] 14. Check: kubectl logs -n php-demo <pod> -c nginx | grep "BPA WebServer Plugin active"
[ ] 15. Check: kubectl logs -n php-demo <pod> -c dx-o2-agent | grep "Infrastructure Agent started"
[ ] 16. Verify in DX O2 console: agent tree shows bpa-demo-agent under BPA-Demo
```
