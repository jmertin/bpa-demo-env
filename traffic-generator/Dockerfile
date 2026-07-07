# ════════════════════════════════════════════════════════════════════════════
# Traffic generator – synthetic user traffic for the BPA-Demo web shop
# Base: python:3.12-slim (Debian bookworm)
#
# Continuously cycles through the demo user roster (see CLAUDE.md's "Demo
# use cases" section), logging in as each one and performing a randomized
# sequence of shop actions, so the DX O2 agents have real, varied traffic
# to report on demand rather than only when a human is clicking through
# the app. generator.py uses only the Python standard library – there is
# nothing to fetch at build time and no dependency layer.
# ════════════════════════════════════════════════════════════════════════════

FROM python:3.12-slim

ENV PYTHONUNBUFFERED=1

RUN useradd --system --no-create-home --shell /usr/sbin/nologin traffic

WORKDIR /app

COPY generator.py .
RUN chown -R traffic:traffic /app

USER traffic

ENTRYPOINT ["python", "generator.py"]
