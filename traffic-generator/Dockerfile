FROM ghcr.io/browserless/chromium:latest

USER root

# Copy corporate CA certificate into the Debian trusted certificate
# directory If your security team requires SSL verification for
# package installation, copy your organization's root certificate into
# the image during the apt-get step If your company has a transparent
# application level firewall, copy the firewall's CA Certificate here
# and uncomment the below line
COPY cloud_services_root_CA.cer /usr/local/share/ca-certificates/corporate-ca.crt

# Install system dependencies and register the new CA certificate
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 \
    python3-pip \
    python3-venv \
    ca-certificates \
    netcat-openbsd \
    tini \
    && update-ca-certificates \
    && rm -rf /var/lib/apt-get/lists/*

WORKDIR /app

# Point Python SSL tools globally to the updated system certificate bundle
ENV SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt
ENV REQUESTS_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt

# Create virtual environment and install Playwright over verified TLS
RUN python3 -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

#RUN pip install --no-cache-dir playwright
# Replace the index URL with your company's Artifactory / Nexus PyPI mirror
RUN pip install --no-cache-dir \
    --index-url https://packages.vcfd.broadcom.net/artifactory/api/pypi/pypi-remote/simple \
    playwright


# Copy application files
COPY generator.py /app/generator.py
COPY entrypoint.sh /app/entrypoint.sh
RUN chmod +x /app/entrypoint.sh

# Target local Browserless service over WebSocket
ENV BROWSERLESS_URL="ws://localhost:3000"

ENTRYPOINT ["/usr/bin/tini", "--", "/app/entrypoint.sh"]
