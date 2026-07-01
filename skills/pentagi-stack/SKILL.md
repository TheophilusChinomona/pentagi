---
name: pentagi-stack
description: PentAGI autonomous pentest platform — full stack overview, how agents discover and connect to the API and tool image
triggers:
  - "pentest"
  - "security assessment"
  - "scan target"
  - "connect to pentagi"
---

# PentAGI Stack — Agent Integration Guide

This repo deploys a full PentAGI autonomous pentesting platform. It provides two
ways for AI agents to run security operations:

1. **PentAGI API** (REST + GraphQL) — full orchestration, memory, knowledge graph
2. **pentest-tools image** — direct Docker exec for ad-hoc tool usage

## Discovery

When deployed, the stack is reachable at:

```
PentAGI API:    https://<server>:8443/api/v1/
PentAGI UI:     https://<server>:8443
Scraper (browser): https://<server>:9443
Pgvector:        <server>:5432
```

Default credentials: `admin@pentagi.com` / `admin` (change on first login).

## API Token

Generate an API token in the UI under Settings → API Tokens, or use the admin
credentials for initial setup. All API calls use Bearer auth:

```bash
curl -H "Authorization: Bearer <token>" https://<server>:8443/api/v1/flows
```

## Quick Start — Run a Pentest

### Via PentAGI API (orchestrated)

```bash
# 1. Create a flow (specifies target + LLM provider)
curl -X POST https://<server>:8443/api/v1/flows \
  -H "Authorization: Bearer <token>" \
  -H "Content-Type: application/json" \
  -d '{"input": "recon and vulnerability scan example.com", "provider": "openai"}'

# Response includes flow ID — poll for completion

# 2. Check status
curl https://<server>:8443/api/v1/flows/<flow-id> \
  -H "Authorization: Bearer <token>"

# 3. Get results
curl https://<server>:8443/api/v1/flows/<flow-id>/results \
  -H "Authorization: Bearer <token>"
```

### Via Direct Tool Image (ad-hoc)

If you have Docker access to the server:

```bash
docker exec <container> nmap -sV scanme.nmap.org
docker run --rm pentest-tools:latest nuclei -u https://example.com
```

See `pentest-tools` skill for the full tool reference.

## Workflow

1. **Recon** — subfinder, amass, httpx, nmap, whatweb
2. **Vulnerability Scanning** — nuclei, nikto, wapiti
3. **Web Testing** — ffuf, gobuster, katana, sqlmap, commix
4. **Network Testing** — masscan, hydra, enum4linux-ng, impacket
5. **Code Audit** — semgrep, trufflehog, gitleaks, trivy, grype
6. **Exploitation** — Metasploit, searchsploit, john, hashcat
7. **Reporting** — results aggregated via aggregate-results script
