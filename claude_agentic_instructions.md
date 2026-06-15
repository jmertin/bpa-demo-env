# Claude Agentic Execution Instructions: Project Hardening & Broadcom DX O2 Integration[cite: 1]

You are tasked with taking the existing prototype of the PHP-FPM + NGINX + MariaDB application and refactoring it into a production-grade, hardened, monitored deployment.[cite: 1]

Execute the following tasks sequentially.[cite: 1] For every action taken, you must log modifications to the project `CHANGELOG` using the format: `YYYY-MM-DD @ HH:MM - [Task Name]: [Description of change]`.[cite: 1] Commit changes frequently to the local git repository.[cite: 1]

---

## Phase 1: Compatibility Analysis & Repository Setup[cite: 1]
**Objective:** Establish version baseline and safety boundaries before altering code.[cite: 1]

1. **Git Initialization:** If not already present, initialize a local git repository in the workspace root.[cite: 1]
2. **Version Compatibility Matrix:**[cite: 1]
   * Analyze the existing prototype's PHP and NGINX versions.[cite: 1]
   * Cross-reference them with Broadcom DX O2 requirements.[cite: 1] Verify compatibility with the **PHP Agent (supports up to PHP 8.4)** and the **BPA WebServer Plugin (supports up to NGINX 1.29.x)**.[cite: 1]
   * Select a target older Ubuntu LTS base image (e.g., Ubuntu 20.04 or 22.04) that fulfills the system dependency requirements of the Broadcom binary agents.[cite: 1]
3. **Directory Structuring:** Create a clean, segregated project directory layout:[cite: 1]
```text
   ├── .config (Git-ignored)
   ├── CHANGELOG
   ├── README.md
   ├── build-scripts/
   ├── helm/
   │   └── php-app-chart/
   └── src/
       ├── php-fpm/
       ├── nginx/
       └── dx-o2-agents/
   ```[cite: 1]

---

## Phase 2: PHP Application Standardization[cite: 1]
**Objective:** Refactor the prototype source code to meet enterprise standards.[cite: 1]

1. **Coding Standards:** Refactor all existing PHP code inside `src/` to strictly comply with the [Backdrop CMS PHP coding standards](https://docs.backdropcms.org/php-standards).[cite: 1]
2. **Inline Function Documentation:** Rewrite or append headers to **every** PHP function.[cite: 1] Headers must strictly follow the [Backdrop CMS documentation standards](https://docs.backdropcms.org/doc-standards), outlining parameters, return types, and purpose.[cite: 1]

---

## Phase 3: Hardened Containerization & Agent Integration[cite: 1]
**Objective:** Build multi-stage, non-privileged container images hosting the application and Broadcom agents.[cite: 1]

### Task 3.1: The Combined DX O2 Monitoring Image[cite: 1]
* Create a dedicated Dockerfile under `src/dx-o2-agents/`.[cite: 1]
* Base this image on official, cryptographically signed packages.[cite: 1]
* Configure this single container to run **both** the **Broadcom Infrastructure Agent** and the **Business Transaction Listener (BTL)**.[cite: 1]
* Ensure the package directory containing the PHP probe installation script is exposed via a volume mount or accessible multi-stage pathway.[cite: 1]

### Task 3.2: PHP-FPM Hardening & Injection[cite: 1]
* Rebase the PHP-FPM container onto the chosen older Ubuntu LTS official image.[cite: 1]
* Implement a **multi-stage build**: execute compilation steps in a build container, then copy only runtime binaries over to a clean, minimal runtime layer.[cite: 1] Do not leave development environments/packages in the final image.[cite: 1]
* Configure the container to run on a **non-privileged port**.[cite: 1]
* Write an entrypoint script to inject and configure the Broadcom PHP probe (`wily_php_agent.ini`) at container startup using the installer binaries passed from the Infrastructure Agent volume.[cite: 1]

### Task 3.3: NGINX Hardening & BPA Plugin Injection[cite: 1]
* Rebase the NGINX container onto the older Ubuntu LTS official image.[cite: 1]
* Configure the service to listen exclusively on **non-privileged ports**.[cite: 1]
* Write an entrypoint mechanism to inject the Business Payload Analyzer (BPA) WebServer Plugin (`ngx_http_ca_plugin_filter_module.so`) into the NGINX configuration at startup.[cite: 1]
* Apply a pessimistic approach: remove all default configurations, unused modules, and utilities.[cite: 1]

---

## Phase 4: Build System Automation[cite: 1]
**Objective:** Script the image lifecycle using secure configuration management.[cite: 1]

1. **Configuration Isolation (`.config`):**[cite: 1]
   * Use and if required update the `.config` file in the root directory formatted as standard shell variables.[cite: 1]
   * Store all environment configurations, image tags, repository URLs, and registry credentials here.[cite: 1]
   * **CRITICAL:** Ensure `.config` is added to `.gitignore`.[cite: 1] It must never be tracked in git or hardcoded into scripts.[cite: 1]
2. **Build & Push Scripting:**[cite: 1]
   * Write modular Bash scripts inside `build-scripts/` to build the Docker images and conditionally push them to the pre-defined container registry.[cite: 1]
   * Strictly adhere to the [OpenWaterFoundation Shell Best Practices](https://learn.openwaterfoundation.org/owf-learn-linux-shell/best-practices/best-practices/).[cite: 1]
   * Build operations must assume an external compilation runtime (the scripts will not run inside the Kubernetes cluster).[cite: 1]

---

## Phase 5: Kubernetes Orchestration (Helm)[cite: 1]
**Objective:** Deliver a production-ready Helm chart targeting secure K8s clusters.[cite: 1]

1. **Chart Construction:** Create a Helm chart inside `helm/php-app-chart/` to deploy the application stack (PHP-FPM, NGINX, MariaDB, and the combined DX O2 Agent container).[cite: 1]
2. **Registry Authentication:** Configure a `ServiceAccount` and `imagePullSecrets` block within the Helm chart to handle secure cluster access to your private container registry.[cite: 1]
3. **Security Contexts:** Ensure all workloads are explicitly configured with restrictive pod security contexts (e.g., `runAsNonRoot: true`, `allowPrivilegeEscalation: false`).[cite: 1]
4. **Certificate Integration:** Assume the target Kubernetes cluster has active ingress controllers and certificate managers; expose proper TLS ingress definitions in the values configuration.[cite: 1]

---

## Phase 6: Documentation & Validation[cite: 1]
**Objective:** Finalize user hand-off assets.[cite: 1]

1. **Project README.md:** Populate the root `README.md` with:[cite: 1]
   * A high-level architecture overview of the application and agent injection flow.[cite: 1]
   * Step-by-step setup and local execution steps using the automation scripts.[cite: 1]
   * Helm deployment configuration guides detailing variables found within `.config`.[cite: 1]
2. **Changelog Validation:** Audit the `CHANGELOG` file to guarantee every code iteration has been mapped chronologically with timestamped entries.[cite: 1]
