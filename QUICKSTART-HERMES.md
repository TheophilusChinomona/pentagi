# Quick Start — Hermes Pentest Toolkit

## TL;DR

```bash
# 1. Build the pentest tools Docker image
docker compose build pentest-tools

# 2. Configure Hermes to use Docker backend
hermes config set terminal.backend docker
hermes config set terminal.docker_image pentest-tools:latest

# 3. Load pentest skills
make load-skills   # or: cp -r skills/pentest-* ~/.hermes/skills/

# 4. Start Hermes and run a pentest
hermes
> pentest scanme.nmap.org
```

---

## What I Created

| File | Purpose |
|------|---------|
| `Dockerfile.pentest` | Standalone pentest tools image (Ubuntu 24.04 + 30+ security tools) |
| `docker-compose.yml` | Builds the image; optional PostgreSQL for memory |
| `Makefile` | `make build`, `make load-skills`, `make shell`, `make test-tools` |
| `README-HERMES.md` | Full setup & troubleshooting guide |
| `skills/pentest-orchestrator/SKILL.md` | Master skill — full pipeline with confirm gates |
| `skills/pentest-recon/SKILL.md` | Passive/active reconnaissance |
| `skills/pentest-web/SKILL.md` | Web app testing (XSS, SQLi, SSRF, etc.) |
| `skills/pentest-network/SKILL.md` | Network testing (nmap, SMB, AD, credentials) |
| `skills/pentest-api/SKILL.md` | API security (REST, GraphQL, BOLA/IDOR) |
| `skills/pentest-report/SKILL.md` | Professional report generation |

All skills are **Hermes-native** — just `SKILL.md` methodology documents that Hermes reads and executes using the `terminal` tool.

---

## What Was Removed / Ignored

Athena-specific files you no longer need:
- `docker/gateway.Dockerfile` — not used (Hermes is your gateway)
- `docker/entrypoint-super-agent.sh` — not used
- `scripts/run-engagement.sh`, `scripts/teardown-engagement.sh` — Hermes manages containers automatically
- `scripts/install-tools.sh` — tools are in Docker image now
- `setup.sh`, `load-skills.sh` — replaced by `make load-skills` + Hermes config
- `.infisical.json` — not needed; use `~/.hermes/.env` for secrets

You can delete or ignore these. They belong to the athena fork.

---

## Configuration Details

### Hermes Config (`~/.hermes/config.yaml`)

```yaml
terminal:
  backend: docker
  docker_image: pentest-tools:latest
  container_cpu: 2            # optional: limit CPU
  container_memory: 8192      # optional: limit RAM (MB)
  container_disk: 51200       # optional: disk quota (MB)
  persistent_shell: true      # reuse container across commands (default)
  docker_volumes: []          # optional: mount host dirs, e.g. ["/host/results:/tmp/pentest"]

# Optional: external Postgres for better memory (instead of file-based)
# memory:
#   database_url: postgresql://user:pass@host:5432/hermes_memory
```

### Environment Variables

Set in `~/.hermes/.env` (if not already):
```
OPENROUTER_API_KEY=your-key-here
# HERMES_MEMORY_DATABASE_URL=postgresql://...  (optional)
```

---

## How It Works

1. **Docker backend**: When `terminal.backend=docker`, Hermes creates (or reuses) a container from `pentest-tools:latest`.
2. **Commands**: Every `terminal` tool call runs inside that container via `docker exec`.
3. **Skills**: `SKILL.md` files in `~/.hermes/skills/` are read by Hermes; it plans steps and executes them with `terminal` calls.
4. **No extra gateway**: Your existing Hermes installation handles everything.

---

## Verification

```bash
# Check Hermes sees Docker
hermes config get terminal.backend
# Should output: docker

# Verify image exists
docker image ls pentest-tools:latest

# Test a tool
docker run --rm pentest-tools:latest nmap --version

# Start Hermes and ask for recon
hermes
> run reconnaissance on scanme.nmap.org
```

Expected output: Hermes runs `whois`, `nmap`, `subfinder`, etc. inside the container and returns a summary.

---

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| `Docker executable not found` | Install Docker, add user to `docker` group |
| `Cannot connect to the Docker daemon` | Start Docker: `sudo systemctl start docker` |
| `Image pentest-tools:latest not found` | Run `docker compose build pentest-tools` |
| Tools missing from container | Edit `Dockerfile.pentest`, rebuild |
| Hermes still using `local` backend | Restart Hermes after config change; check YAML syntax |
| Permission denied on `/tmp` inside container | Normal — container runs as non-root but has write access to /tmp |

For more, see `README-HERMES.md`.

---

## Extending

**Add more tools?** Edit `Dockerfile.pentest` and rebuild.

**Persist results on host?** Add volume mount:
```yaml
terminal:
  docker_volumes:
    - /home/user/pentest-results:/tmp/pentest
```

**Switch to local shell temporarily:**
```bash
hermes config set terminal.backend local
# ... do local work ...
hermes config set terminal.backend docker  # switch back
```

---

## Files Modified / Created

All changes are within `pentestAGI/athena-pentest/`:

- **New:** `Dockerfile.pentest`, `docker-compose.yml`, `Makefile`, `README-HERMES.md`
- **Updated:** All `skills/pentest-*/SKILL.md` to remove athena-specific references
- **Unchanged (legacy):** `docker/gateway.Dockerfile`, `scripts/run-engagement.sh`, `setup.sh`, etc. — these are athena-specific and can be ignored/deleted.

---

Next step: **run `make build`** to build the pentest-tools Docker image.
