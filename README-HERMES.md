# Hermes + Pentest Tools — Setup Guide

This directory contains a Docker-based penetration testing toolkit that integrates with the **stock Hermes agent** (not the athena fork).

## What's Different from Athena

| Athena Fork | Stock Hermes |
|-------------|--------------|
| Custom gateway container with Hermes bundled | You already have Hermes installed |
| Spawns per-engagement tool containers automatically | Hermes uses its Docker backend directly |
| Custom wrapper scripts (`athena-engage`, etc.) | Skills run terminal commands directly |
| Infisical secret management | Use your existing Hermes `.env` |

**We only need:** a pentest-tools Docker image and Hermes configured to use it.

---

## Prerequisites

- Docker + Docker Compose plugin installed and running
- Hermes agent already installed and working (`hermes` command available)
- OpenRouter API key in `~/.hermes/.env` (or config)
- Sufficient disk space (~5 GB for the image)

---

## Step 1: Build the Pentest Tools Image

From this directory (`pentestAGI/athena-pentest`):

```bash
# Build the Docker image with all pentest tools
docker compose build pentest-tools

# Or without cache (fresh tools)
docker compose build --no-cache pentest-tools

# Verify tools are installed
docker run --rm pentest-tools:latest bash -c '\
  nmap --version && \
  nuclei -version && \
  subfinder -version && \
  sqlmap --version'
```

The image includes:
- **Recon:** nmap, masscan, subfinder, amass, dnsx, naabu, httpx, whatweb
- **Web:** nuclei, nikto, wapiti, ffuf, gobuster, sqlmap, commix, katana, interactsh
- **Network:** hydra, enum4linux-ng, netexec, impacket, responder
- **Cracking:** john, hashcat
- **Exploitation:** metasploit, searchsploit
- **Utilities:** jq, curl, wget, git, ruby, perl, python3

---

## Step 2: Configure Hermes to Use Docker Backend

Edit `~/.hermes/config.yaml`:

```yaml
terminal:
  backend: docker                    # Use Docker instead of local shell
  docker_image: pentest-tools:latest  # Our built pentest image
  docker_forward_env: []              # Optional: forward env vars into container
  container_cpu: 2                    # Resources per container (optional)
  container_memory: 8192              # Memory in MB
  container_disk: 51200              # Disk quota in MB
  persistent_shell: true             # Reuse container across commands

# Optional: Use external PostgreSQL for memory (better than file-based)
# Uncomment if you have a Postgres+pgvector instance:
# memory:
#   database_url: postgresql://user:pass@host:5432/hermes_memory
```

Or use CLI:
```bash
hermes config set terminal.backend docker
hermes config set terminal.docker_image pentest-tools:latest
hermes config set terminal.container_cpu 2
hermes config set terminal.container_memory 8192
```

---

## Step 3: Load Pentest Skills

The skill files in `skills/` are Hermes-compatible (just SKILL.md methodology docs). Load them:

```bash
# From this directory
make load-skills

# Or manually:
mkdir -p ~/.hermes/skills
cp -r skills/pentest-* ~/.hermes/skills/
```

Verify:
```bash
ls ~/.hermes/skills/pentest-*
# Should list: pentest-api pentest-network pentest-orchestrator pentest-report pentest-recon pentest-web
```

---

## Step 4: Test the Setup

Start Hermes:
```bash
hermes
```

Ask it to run a recon:
```
You: do a quick reconnaissance on scanme.nmap.org
```

Expected behavior:
1. Hermes reads `pentest-recon` skill
2. Spins up a `pentest-tools:latest` container (if not already running)
3. Runs `whois scanme.nmap.org`, `nmap -sV scanme.nmap.org`, etc. inside container
4. Returns results

Try another:
```
You: run a nuclei scan on scanme.nmap.org
```

---

## How It Works

- **Terminal backend:** When `terminal.backend=docker`, Hermes creates (or reuses) a long-lived Docker container from your configured image.
- **Every terminal command** (via `terminal` tool) runs inside that container via `docker exec`.
- **Skills** are just methodology documents (`SKILL.md`). Hermes reads them and plans steps using terminal commands.
- **No gateway container** needed — Hermes runs directly on your host.
- **Results** are stored in the container's filesystem (`/tmp/`). For persistence, you can mount volumes via `terminal.docker_volumes`.

Optional volume mount to keep results on host:
```yaml
terminal:
  docker_volumes:
    - /path/on/host/pentest-results:/tmp/pentest
```

---

## Cleaning Up

Stop the Hermes Docker container (persisted across Hermes restarts):
```bash
# Hermes reuses one container per session. To force fresh:
hermes /reset  # starts new conversation, same container
# Container stops when Hermes exits

# To manually kill the pentest container:
docker ps | grep pentest-tools  # find container ID
docker stop <container-id>
```

Remove the image:
```bash
docker rmi pentest-tools:latest
```

Unload skills:
```bash
rm -rf ~/.hermes/skills/pentest-*
```

---

## Troubleshooting

**Docker not found:**
```
Error: Docker backend selected but no docker executable was found
```
Install Docker Desktop or Docker Engine and ensure `docker version` works.

**Container fails to start:**
Check `docker logs <container-id>`. Common issues: insufficient memory, disk space.

**Tools missing:**
The Dockerfile is comprehensive but you can extend it. Edit `Dockerfile.pentest` and rebuild.

**Permission denied on Docker socket:**
Ensure your user is in the `docker` group:
```bash
sudo usermod -aG docker $USER
# Log out and back in
```

**Hermes still using local backend:**
Double-check `~/.hermes/config.yaml` syntax (YAML indentation matters). Restart Hermes after config changes.

---

## Advanced: Persistent Workspace

By default, Hermes uses a tmpfs workspace inside the container (ephemeral). To persist files across sessions:

```yaml
terminal:
  persistent_shell: true   # already default
  docker_volumes:
    - ~/.hermes/workspace:/workspace
```

Then inside the container, `/workspace` will survive container restarts.

---

## Cost Estimate

Using DeepSeek V3 via OpenRouter: **~$0.25–1.00 per full engagement** (recon → scan → report).

---

## Notes

- This setup intentionally avoids the athena gateway complexity. You get the same pentest capabilities with plain Hermes.
- The skills provided are methodology-focused; Hermes's reasoning model decides which exact commands to run based on the skill description and current context.
- You can extend skills by adding `scripts/` subdirectories with helper Python/bash scripts copied to `~/.hermes/skills/<skill>/scripts/`.
