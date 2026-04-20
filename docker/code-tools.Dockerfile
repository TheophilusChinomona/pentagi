FROM ubuntu:24.04 AS code-tools

LABEL maintainer="Theophilus / Athena"
LABEL description="Code security testing tools — SAST, SCA, secret detection, container scanning"

ENV DEBIAN_FRONTEND=noninteractive
ENV GOPATH=/root/go
ENV PATH=$PATH:/usr/local/go/bin:$GOPATH/bin:/root/.local/bin

# ============================================================================
# Base System
# ============================================================================

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    wget \
    git \
    jq \
    unzip \
    python3 \
    python3-pip \
    python3-venv \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

# ============================================================================
# Go (for Go-based tools)
# ============================================================================

RUN wget -q https://go.dev/dl/go1.24.1.linux-amd64.tar.gz -O /tmp/go.tar.gz \
    && rm -rf /usr/local/go \
    && tar -C /usr/local -xzf /tmp/go.tar.gz \
    && rm /tmp/go.tar.gz

# ============================================================================
# Secret Detection
# ============================================================================

# trufflehog — deep secret scanning (git history, filesystem, S3, etc.)
RUN curl -sSfL https://raw.githubusercontent.com/trufflesecurity/trufflehog/main/scripts/install.sh | sh -s -- -b /usr/local/bin

# gitleaks — fast git secret scanning
RUN go install github.com/gitleaks/gitleaks/v8@latest

# ============================================================================
# SAST — Static Analysis
# ============================================================================

# semgrep — lightweight static analysis
RUN pip3 install semgrep --break-system-packages --no-cache-dir

# ============================================================================
# SCA — Dependency Scanning
# ============================================================================

# grype — vulnerability scanner for containers and filesystems
RUN curl -sSfL https://raw.githubusercontent.com/anchore/grype/main/install.sh | sh -s -- -b /usr/local/bin

# osv-scanner — Google's open source vulnerability scanner
RUN go install github.com/google/osv-scanner/cmd/osv-scanner@latest

# npm audit (included with Node.js)
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/*

# pip-audit — Python dependency auditing
RUN pip3 install pip-audit --break-system-packages --no-cache-dir

# ============================================================================
# Container / IaC Scanning
# ============================================================================

# trivy — comprehensive security scanner (containers, IaC, code, dependencies)
RUN curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh | sh -s -- -b /usr/local/bin

# checkov — IaC security scanner (Terraform, Docker, K8s, CloudFormation)
RUN pip3 install checkov --break-system-packages --no-cache-dir

# ============================================================================
# License Compliance
# ============================================================================

# license-checker for npm
RUN npm install -g license-checker

# pip-licenses for Python
RUN pip3 install pip-licenses --break-system-packages --no-cache-dir

# ============================================================================
# Additional Tools
# ============================================================================

# bandit — Python-specific SAST
RUN pip3 install bandit --break-system-packages --no-cache-dir

# eslint security plugin (for JS/TS)
RUN npm install -g eslint @eslint/js eslint-plugin-security

# ============================================================================
# Workspace
# ============================================================================

RUN mkdir -p /scan/results /scan/targets

WORKDIR /scan

HEALTHCHECK --interval=60s --timeout=10s \
    CMD semgrep --version > /dev/null 2>&1 && trivy --version > /dev/null 2>&1

CMD ["/bin/bash"]
