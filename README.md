# Pentest Toolkit — Athena

AI-powered autonomous penetration testing. Docker-in-Docker architecture for isolated, per-client engagements.

## Architecture

```
┌──────────────────────────────────────────────────────────┐
│  PENTEST SERVER (isolated IP/network)                    │
│                                                          │
│  ┌─────────────────────────────────────────────────┐     │
│  │  docker compose up -d                            │     │
│  │                                                  │     │
│  │  ┌──────────────┐  ┌──────────────┐             │     │
│  │  │ Athena       │  │ PostgreSQL   │             │     │
│  │  │ Gateway      │  │ + pgvector   │             │     │
│  │  │ (Hermes)     │  │              │             │     │
│  │  └──────┬───────┘  └──────────────┘             │     │
│  │         │                                        │     │
│  │         │ Docker API                             │     │
│  │         ▼                                        │     │
│  │  ┌──────────────┐                                │     │
│  │  │ Docker-in-   │                                │     │
│  │  │ Docker       │                                │     │
│  │  └──────┬───────┘                                │     │
│  │         │                                        │     │
│  │    ┌────┴────┬────────┬────────┐                │     │
│  │    ▼         ▼        ▼        ▼                │     │
│  │ ┌──────┐ ┌──────┐ ┌──────┐ ┌──────┐            │     │
│  │ │Client│ │Client│ │Client│ │Client│            │     │
│  │ │ A    │ │ B    │ │ C    │ │ D    │            │     │
│  │ └──────┘ └──────┘ └──────┘ └──────┘            │     │
│  │  isolated containers per engagement             │     │
│  └─────────────────────────────────────────────────┘     │
└──────────────────────────────────────────────────────────┘
```

## Why Docker-in-Docker

- **Per-client isolation** — each engagement gets its own container + network
- **No cross-contamination** — Client A's traffic never touches Client B's scope
- **Clean teardown** — kill container, evidence preserved in volumes
- **Reproducible** — same image every time, same tool versions
- **Scalable** — run 5+ engagements simultaneously
- **Audit trail** — every container, command, and result is logged

## Quick Start

### 1. Provision Pentest Server
```bash
# Any Ubuntu 24.04 server with Docker installed
# Separate IP from your dev infrastructure
# Minimum: 2 vCPU, 4GB RAM, 20GB disk
```

### 2. Deploy the Stack
```bash
git clone <this-repo> /opt/pentest-athena
cd /opt/pentest-athena
cp .env.example .env
# Edit .env with your OpenRouter key and passwords
docker compose up -d
```

### 3. Verify
```bash
# Check all services are running
docker compose ps

# Verify tools image was built
docker images | grep athena/pentest-tools

# Test tools container
docker run --rm athena/pentest-tools:latest nmap --version
```

### 4. Run an Engagement
```bash
# Launch isolated engagement container
./scripts/run-engagement.sh target.com client-xyz-2026

# Or let Athena handle it — just message on Discord:
# "pentest target.com"
```

## Container Lifecycle

```
run-engagement.sh ──▶ Docker container ──▶ Athena orchestrates ──▶ teardown-engagement.sh
     │                      │                        │                       │
     │                      │                        │                       │
  Creates:              Contains:               Runs:                  Preserves:
  - Container           - 20+ tools             - recon                - Evidence
  - Network             - Wordlists             - scanning             - Logs
  - Volume mount        - /pentest/results      - exploitation         - Reports
                                                - reporting            - Metadata
```

## Files

```
pentest/
├── docker-compose.yml              Main stack definition
├── .env.example                    Environment template
├── docker/
│   └── pentest-tools.Dockerfile    Full tool stack image
├── scripts/
│   ├── run-engagement.sh           Launch per-client container
│   ├── teardown-engagement.sh      Stop & archive engagement
│   ├── install-tools.sh            Standalone installer (non-Docker)
│   └── deploy.sh                   Deploy to remote server
└── README.md
```

## Skills (in Athena)

| Skill | Description |
|-------|-------------|
| `pentest-recon` | Subdomain enum, port scanning, OSINT, fingerprinting |
| `pentest-web` | XSS, SQLi, CSRF, SSRF, path traversal, file upload |
| `pentest-network` | Service enum, vuln scanning, credential auditing, AD |
| `pentest-report` | Professional vulnerability report generation |
| `pentest-orchestrator` | Full pipeline with confirmation gates |

## Engagement Workflow

1. **You (Discord):** "pentest acme-corp.com — web application focus"
2. **Athena:** Creates engagement container, runs recon
3. **Athena:** "Found 15 subdomains, 8 live hosts. Proceed to scanning?"
4. **You:** "yes"
5. **Athena:** Runs nuclei, sqlmap, web testing
6. **Athena:** "Found 2 critical, 5 high vulnerabilities. Proceed to exploitation?"
7. **You:** "yes"
8. **Athena:** Validates findings, collects evidence
9. **Athena:** Generates report, sends PDF on Discord
10. **Athena:** Tears down container, archives evidence

## Safety

- **Confirmation gates** before active exploitation
- **Per-engagement network isolation** — no cross-client traffic
- **All commands logged** with timestamps
- **Evidence preserved** after container teardown
- **Scope validation** before any scanning
- **Rate limiting** on all scans

## Cost

Per-engagement with DeepSeek V3 via OpenRouter: **~$0.25-1.00**
