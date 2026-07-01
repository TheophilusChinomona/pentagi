# PentAGI Fork — Agent Integration Guide

This fork ships two things your agents can use:

1. **A standalone pentest tool image** — any agent with Docker access can use it
2. **A full PentAGI backend** — exposes REST/GraphQL APIs for programmatic access

---

## Mode 1: Just the Tool Image (Simplest)

Build the image once, then any agent runs tools via `docker exec`:

```bash
# Build
docker compose build pentest-tools

# Test
docker run --rm pentest-tools:latest nmap --version
docker run --rm pentest-tools:latest nuclei -version
```

### Agent Configuration

**Hermes:**
```bash
hermes config set terminal.backend docker
hermes config set terminal.docker_image pentest-tools:latest
```

**Claude Code / Codex:**
Set your agent's Docker image to `pentest-tools:latest` via its config or CLI flag.

**Any agent (generic):**
```bash
docker run --rm -v /path/to/results:/pentest/results pentest-tools:latest nmap -sV target.com
docker run --rm pentest-tools:443 nuclei -u https://target.com -o /pentest/results/nuclei.json
```

**Interactive session:**
```bash
docker run --rm -it pentest-tools:latest bash
# Now you have nmap, nuclei, sqlmap, metasploit, hydra, etc.
```

---

## Mode 2: Full PentAGI Backend (REST/GraphQL API)

Run the complete PentAGI stack with the custom tool image:

```bash
# 1. Build the custom tool image
docker compose build pentest-tools

# 2. Configure
cp .env.example .env
# Edit .env — you MUST set at least one LLM API key:
#   OPEN_AI_KEY=sk-...
#   or ANTHROPIC_API_KEY=sk-ant-...
#   or GEMINI_API_KEY=...
#   or any supported provider

# 3. Start the stack
docker compose up -d

# 4. Open the UI
open https://localhost:8443
# Default login: admin@pentagi.com / admin
```

### Connecting Agents via API

**REST API:**
```bash
# Generate an API token in the UI (Settings → API Tokens)
# Then use it:
curl https://your-host:8443/api/v1/flows \
  -H "Authorization: Bearer YOUR_API_TOKEN"

# Create a new flow (pentest engagement):
curl -X POST https://your-host:8443/api/v1/graphql \
  -H "Authorization: Bearer YOUR_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "query": "mutation { createFlow(modelProvider: \"auto\", input: \"Scan example.com\") { id title status } }"
  }'
```

**Python client:**
```python
import requests

class PentAGIClient:
    def __init__(self, base_url, api_token):
        self.base_url = base_url
        self.headers = {
            "Authorization": f"Bearer {api_token}",
            "Content-Type": "application/json"
        }

    def create_flow(self, target):
        query = """
        mutation CreateFlow($input: String!) {
          createFlow(modelProvider: "auto", input: $input) {
            id title status
          }
        }"""
        r = requests.post(
            f"{self.base_url}/api/v1/graphql",
            json={"query": query, "variables": {"input": target}},
            headers=self.headers
        )
        return r.json()

    def list_flows(self):
        r = requests.get(f"{self.base_url}/api/v1/flows", headers=self.headers)
        return r.json()

client = PentAGIClient("https://localhost:8443", "YOUR_API_TOKEN")
print(client.create_flow("nmap -sV scanme.nmap.org"))
```

**n8n / no-code:** Use the HTTP Request node with Bearer token auth against the REST API. The OpenAPI spec is at `https://your-host:8443/api/v1/swagger/doc.json`.

---

## How It Works

```
┌─────────────────────────────────────────────────────┐
│                   Your AI Agent                       │
│  (Hermes, Claude Code, Codex, custom agent, etc.)    │
└────────┬──────────────────────────────────┬───────────┘
         │ via REST/GraphQL API            │ via docker exec
         ▼                                 ▼
┌─────────────────┐            ┌─────────────────────────┐
│  PentAGI Backend │            │ pentest-tools:latest    │
│  (Go + Agents)   │  spawns ──► (nmap, nuclei, sqlmap,   │
│  postgres/scraper│  containers │ metasploit, 40+ tools)  │
└─────────────────┘            └─────────────────────────┘
```

The `pentest-tools:latest` image is used by PentAGI's backend whenever it needs to execute a pentest command. The backend spawns an isolated container per operation, collects results, and stores them in the database.

---

## What's in the Tool Image

| Category | Tools |
|----------|-------|
| **Network scanning** | nmap, masscan, naabu, dnsx, subfinder, amass |
| **Vulnerability scanning** | nuclei (with templates), nikto, wapiti |
| **Web app testing** | sqlmap, ffuf, gobuster, katana, whatweb, wfuzz, smuggler |
| **API testing** | jwt_tool, websocat, waybackurls |
| **Exploitation** | Metasploit, hydra, john, hashcat, searchsploit |
| **AD/Windows** | impacket, bloodhound, NetExec, Responder, enum4linux-ng |
| **SAST/Code** | semgrep, bandit, trufflehog, gitleaks, osv-scanner, pip-audit |
| **Container/IaC** | trivy, grype, checkov, kube-bench, kubescape |
| **Wordlists** | SecLists, XSS payloads, API endpoints, common passwords |
| **Utilities** | jq, curl, git, python3, pipx, go, node, ruby, perl |

---

## Environment Variables (`.env`)

At minimum, set ONE LLM provider:
```
OPEN_AI_KEY=sk-...
# or
ANTHROPIC_API_KEY=sk-ant-...
# or
GEMINI_API_KEY=...
```

For AI gateways (OpenRouter, DeepInfra, etc.), use the custom provider config:
```
LLM_SERVER_URL=https://openrouter.ai/api/v1
LLM_SERVER_KEY=sk-or-...
LLM_SERVER_MODEL=anthropic/claude-sonnet-4
```

The pentest image defaults are already pre-configured:
```
DOCKER_DEFAULT_IMAGE_FOR_PENTEST=pentest-tools:latest
```

No need to change these unless you want to use a different tool image.
