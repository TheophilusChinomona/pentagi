# PentAGI Fork — Pentest Toolkit

This is a fork of [vxcontrol/pentagi](https://github.com/vxcontrol/pentagi) — a fully autonomous AI-driven penetration testing system.

## What's Different from Upstream

- **Custom pentest tools image** built from `Dockerfile.pentest` (Ubuntu 24.04 + 40+ tools including ProjectDiscovery suite, Metasploit, wordlists, SAST/SCA scanners)
- Standalone, agent-agnostic — works with PentAGI UI/API, Hermes, Claude Code, Codex, or any AI agent with Docker access
- No Hermes-specific or Athena-specific deployment scripts

## Architecture

The stack runs as a group of Docker Compose services:

| Service | Purpose |
|---------|---------|
| `pentagi` | Go backend + AI agents + REST/GraphQL API |
| `pgvector` | PostgreSQL + pgvector for memory/semantic search |
| `pgexporter` | Prometheus metrics for PostgreSQL |
| `scraper` | Headless browser for web intelligence |
| `pentest-tools` | **Custom** tool image (build target, built on demand) |

Optional stacks (separate compose files):
- `docker-compose-langfuse.yml` — LLM analytics
- `docker-compose-observability.yml` — Grafana/Prometheus/Jaeger/Loki monitoring
- `docker-compose-graphiti.yml` — Neo4j knowledge graph

The `pentagi` service uses `DOCKER_DEFAULT_IMAGE_FOR_PENTEST=pentest-tools:latest` (set in `.env.example`) to spawn isolated tool containers for pentest operations.

## Quick Start

```bash
# 1. Build the custom pentest tools image
docker compose build pentest-tools

# 2. Copy .env and configure (at minimum an LLM API key)
cp .env.example .env
# Edit .env — set OPEN_AI_KEY or ANTHROPIC_API_KEY or GEMINI_API_KEY, etc.

# 3. Start the full stack
docker compose up -d

# 4. Open the UI
open https://localhost:8443
# Default login: admin@pentagi.com / admin

# 5. (Optional) Start optional stacks
docker compose -f docker-compose-langfuse.yml up -d
docker compose -f docker-compose-observability.yml up -d
```

## Common Commands

```bash
docker compose build pentest-tools  # Build custom tool image
docker compose up -d                 # Start main stack
docker compose down                  # Stop everything
docker compose logs -f pentagi       # Watch agent logs

# Optional stacks
docker compose -f docker-compose-langfuse.yml up -d
docker compose -f docker-compose-observability.yml up -d
```

## Building the Custom Tool Image

`Dockerfile.pentest` extends Ubuntu 24.04 with:

- **Go tools**: nuclei, subfinder, httpx, dnsx, naabu, katana, ffuf, gobuster, amass, waybackurls, trufflehog, gitleaks, osv-scanner
- **Python tools**: semgrep, bandit, checkov, pip-audit, impacket, bloodhound, commix, jwt_tool, NetExec, Responder, enum4linux-ng
- **APT packages**: nmap, sqlmap, nikto, hydra, masscan, john, hashcat
- **Other**: Metasploit, searchsploit, trivy, grype, kubescape, kube-bench
- **Wordlists**: SecLists, XSS payloads, API endpoints, common passwords

To test the tools are available:
```bash
docker compose --profile build run pentest-tools bash
# Then inside: nmap --version, nuclei -version, etc.
```

## Using Without the Full Stack (Agent-Only)

Any AI agent can use the pentest-tools image directly without the PentAGI backend:

```bash
# Hermes
hermes config set terminal.backend docker
hermes config set terminal.docker_image pentest-tools:latest

# Docker exec directly
docker run --rm pentest-tools:latest nmap -sV scanme.nmap.org

# Claude Code / Codex
# Configure your tool to use pentest-tools:latest as the terminal image
```

## Key Files

| File | Purpose |
|------|---------|
| `Dockerfile.pentest` | Custom pentest tools image |
| `Dockerfile` | PentAGI main app build (multi-stage: Go backend + React frontend) |
| `docker-compose.yml` | Main stack with custom tool image wired in |
| `.env.example` | All configuration variables with our custom defaults |
| `backend/` | Go backend source (REST + GraphQL APIs, agent system) |
| `frontend/` | React/TypeScript UI source |
| `scripts/aggregate-results.sh` | Utility to parse tool outputs into findings JSON |

## Agent Skills

Three skill files in `skills/` describe how agents interact with the stack:

| Skill | What It Describes |
|-------|-------------------|
| `pentagi-stack` | Stack discovery, API URL, quick-start workflows |
| `pentagi-api` | REST/GraphQL API endpoints, auth, flow lifecycle, Python client |
| `pentest-tools` | Full tool reference by category with Docker exec examples |

To load into Hermes: `make load-skills`

## Upstream Sync

This repo tracks `vxcontrol/pentagi`. To sync upstream changes:

```bash
git remote add upstream https://github.com/vxcontrol/pentagi.git
git fetch upstream
git checkout pentagi-fork
git merge upstream/main
# Resolve conflicts on Dockerfile.pentest, .env.example, docker-compose.yml, .gitignore
```

## What Not to Do

- Don't commit `.env` — secrets live in environment variables or Docker secrets
- Don't mix old Hermes/Athena deployment scripts with the PentAGI stack
- Don't edit the Go backend or React frontend without understanding the full PentAGI architecture
