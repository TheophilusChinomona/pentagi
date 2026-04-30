# Pentest Toolkit — Athena

AI-powered autonomous penetration testing with a Hermes-based gateway that orchestrates isolated, per-engagement tool containers.

## Architecture

Three repos working together:
- **hermes-agent** (Athena): AI agent runtime, tools, memory, orchestration
- **athena-pentest** (this repo): Docker stack, gateway extensions, pentest tools, engagement scripts
- **pentagi**: reference pentesting methodology

```
┌──────────────────────────────────────────────────────────┐
│  PENTEST SERVER (isolated IP/network)                    │
│                                                          │
│  ┌─────────────────────────────────────────────────┐     │
│  │  docker compose up -d                            │     │
│  │                                                  │     │
│  │  ┌──────────────────┐  ┌──────────────┐         │     │
│  │  │ Athena Gateway   │  │ PostgreSQL   │         │     │
│  │  │ (Hermes runtime) │  │ + pgvector   │         │     │
│  │  └────────┬─────────┘  └──────────────┘         │     │
│  │           │                                      │     │
│  │           │ Docker socket                        │     │
│  │           ▼                                      │     │
│  │      ┌─────────┴────────┬────────┐              │     │
│  │      ▼         ▼        ▼        ▼              │     │
│  │  ┌──────┐ ┌──────┐ ┌──────┐ ┌──────┐          │     │
│  │  │Client│ │Client│ │Client│ │Client│          │     │
│  │  │ A    │ │ B    │ │ C    │ │ D    │          │     │
│  │  └──────┘ └──────┘ └──────┘ └──────┘          │     │
│  │   isolated containers per engagement           │     │
│  └─────────────────────────────────────────────────┘     │
└──────────────────────────────────────────────────────────┘
```

## Why Orchestrator + Tool Containers

- **Per-client isolation** — each engagement gets its own container + network
- **No cross-contamination** — Client A's traffic never touches Client B's scope
- **Clean teardown** — kill container, evidence preserved in volumes
- **Reproducible** — same image every time, same tool versions
- **Scalable** — run 5+ engagements simultaneously
- **Audit trail** — every container, command, and result is logged

## Quick Start (Self-Contained)

The stack pulls images from `registry.gitlab.com/chinomonatinotenda19/{athena,athena-pentest/*}`
and pulls secrets from Infisical at runtime — there is no `.env` file on disk.

### Prerequisites on the host

- Docker + Docker Compose plugin
- [Infisical CLI](https://infisical.com/docs/cli/overview) logged in (`infisical login`)
- An Infisical project containing the secrets listed in `.env.example` (one
  `dev` / `staging` / `prod` env at minimum)

### Deploy
```bash
git clone https://gitlab.com/chinomonatinotenda19/athena-pentest.git /opt/athena-pentest
cd /opt/athena-pentest

# Link this checkout to your Infisical project (one-time, writes .infisical.json)
infisical init

# Run setup against the env you want — defaults to "dev"
./setup.sh --env prod

# Load pentest skills into Athena
./load-skills.sh
```

### Day-to-day
Every `docker compose` call needs the same Infisical wrapper so secrets are
injected:
```bash
infisical run --env=prod -- docker compose ps
infisical run --env=prod -- docker compose logs -f
infisical run --env=prod -- docker compose down
```

### Gateway image (Hermes super-agent extension)

The compose builds a local gateway image (`docker/gateway.Dockerfile`) that:
- starts from the upstream Athena/Hermes runtime image
- installs `docker-ce-cli` so Hermes can launch tool containers
- bundles Athena scripts and skills
- exposes wrapper commands for Hermes tool usage:
  - `athena-engage`
  - `athena-teardown`
  - `athena-code-audit`

Athena's `tools/environments/docker.py` shells out to the `docker` CLI binary,
which the upstream `athena` image does not include. Rather than fork the athena
repo, this stack pulls a thin extension image:

- **Base**: `registry.gitlab.com/chinomonatinotenda19/athena:${IMAGE_TAG}`
- **Extension**: `registry.gitlab.com/chinomonatinotenda19/athena-pentest/gateway:${IMAGE_TAG}` (this stack uses the extension)
- **Diff**: just installs `docker-ce-cli` from Docker's official apt repo

Build & push the extension image (optional, if you want registry-hosted deploys):

```bash
# From a host that has Docker installed and is logged into the registry:
docker login registry.gitlab.com   # use a deploy token or PAT with write_registry

docker build \
  --build-arg IMAGE_TAG=stable \
  -t registry.gitlab.com/chinomonatinotenda19/athena-pentest/gateway:stable \
  -f docker/gateway.Dockerfile docker/

docker push registry.gitlab.com/chinomonatinotenda19/athena-pentest/gateway:stable
```

Local `docker compose up` will build this image directly in this repo.

### Image tags / registry CI prereq
The compose references `${IMAGE_TAG:-stable}` against three images:
- `registry.gitlab.com/chinomonatinotenda19/athena:<tag>` (gateway)
- `registry.gitlab.com/chinomonatinotenda19/athena-pentest/pentest-tools:<tag>`
- `registry.gitlab.com/chinomonatinotenda19/athena-pentest/code-tools:<tag>`

Each repo's `.gitlab-ci.yml` must publish the tag you select. If `IMAGE_TAG=stable`
and the athena repo's CI hasn't pushed `:stable` yet, `docker compose pull` will
404. Override per-env in Infisical (e.g. set `IMAGE_TAG=latest` in dev to use the
main-branch build).

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
├── setup.sh                        ← ONE COMMAND TO RULE THEM ALL
├── load-skills.sh                  ← Load skills into Athena
├── docker-compose.yml              Main stack definition (pulls from registry)
├── .env.example                    Reference list of Infisical secrets (not loaded)
├── docker/
│   └── pentest-tools.Dockerfile    Full tool stack image
├── skills/                         ← Bundled pentest skills
│   ├── pentest-recon/
│   ├── pentest-web/
│   ├── pentest-network/
│   ├── pentest-report/
│   └── pentest-orchestrator/
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
2. **Athena:** runs `athena-engage`, creates engagement container, runs recon
3. **Athena:** "Found 15 subdomains, 8 live hosts. Proceed to scanning?"
4. **You:** "yes"
5. **Athena:** Runs nuclei, sqlmap, web testing
6. **Athena:** "Found 2 critical, 5 high vulnerabilities. Proceed to exploitation?"
7. **You:** "yes"
8. **Athena:** Validates findings, collects evidence
9. **Athena:** Generates report, sends PDF on Discord
10. **Athena:** runs `athena-teardown`, archives evidence

## Hermes command surface

Inside `athena-gateway`, Hermes can run these engagement commands:

```bash
athena-engage target.com client-abc-2026
athena-code-audit https://github.com/org/repo.git
athena-teardown client-abc-2026
```

These wrappers map to:
- `scripts/run-engagement.sh`
- `scripts/run-code-audit.sh`
- `scripts/teardown-engagement.sh`

## Safety

- **Confirmation gates** before active exploitation
- **Per-engagement network isolation** — no cross-client traffic
- **All commands logged** with timestamps
- **Evidence preserved** after container teardown
- **Scope validation** before any scanning
- **Rate limiting** on all scans

## Cost

Per-engagement with DeepSeek V3 via OpenRouter: **~$0.25-1.00**
