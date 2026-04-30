# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repo purpose

Docker-based penetration-testing toolkit + skill library for an LLM agent (Hermes/Athena). This repo contains **no application source** — only Dockerfiles, shell wrappers, and `SKILL.md` methodology documents that the agent reads at runtime.

## Two parallel deployment tracks

This is the most important thing to understand before editing. The repo currently supports two mutually exclusive setups; do not mix them.

### Track A — Athena gateway (legacy, registry-pulled)
- Entrypoint: `setup.sh` → `docker-compose.yml` (the *committed but locally modified* version, see `git diff`).
- Pulls `registry.gitlab.com/chinomonatinotenda19/athena*` images and reads secrets from Infisical at runtime (`.env.example` documents the secrets, no `.env` on disk).
- Builds `docker/gateway.Dockerfile` — extends the upstream Athena image with `docker-ce-cli`, bundles `scripts/` and `skills/`, and exposes `athena-engage` / `athena-teardown` / `athena-code-audit` CLI wrappers (symlinks created in the Dockerfile).
- The gateway spawns **per-engagement tool containers** via `scripts/run-engagement.sh` — each gets its own isolated Docker network (`pentest-<engagement-id>`), `/pentest/results/<engagement-id>` volume, audit log, and `engagement-state.json`. `scripts/teardown-engagement.sh` archives evidence to a tarball before removing the container/network.
- README.md describes this track.

### Track B — Hermes-native (`Dockerfile.pentest` + `Makefile`, current direction)
- Entrypoint: `make build` → builds `pentest-tools:latest` from `Dockerfile.pentest` (Ubuntu 24.04 + ProjectDiscovery suite + msf + seclists). The user configures stock Hermes to `terminal.backend=docker, terminal.docker_image=pentest-tools:latest`; Hermes itself manages container lifecycle via its Docker backend, so the `scripts/run-engagement.sh` wrappers are not used here.
- Skills are loaded into the *host's* `~/.hermes/skills/` via `make load-skills` (NOT `load-skills.sh`, which targets the Athena layout `~/.hermes/skills/software-development/`).
- README-HERMES.md and QUICKSTART-HERMES.md describe this track. They explicitly say `docker/gateway.Dockerfile`, the engagement scripts, `setup.sh`, and `load-skills.sh` are unused in this mode.

The committed `docker-compose.yml` (HEAD) is Track A's full stack. The working tree has it reduced to a single `pentest-tools` build service for Track B — meaning `git diff docker-compose.yml` is large and intentional. Before editing compose, confirm which track the user is on.

## Common commands

Track B (most likely, given current working-tree state):
```bash
make build              # build pentest-tools:latest
make build-no-cache     # rebuild from scratch
make test-tools         # smoke-test that nmap/nuclei/subfinder/etc. exist in image
make shell              # interactive bash inside the tools container
make load-skills        # cp -r skills/pentest-* ~/.hermes/skills/
make clean              # docker compose down + rmi pentest-tools:latest
```

Track A:
```bash
infisical login
infisical init                                       # writes .infisical.json
./setup.sh --env <dev|staging|prod>                  # full deploy
./load-skills.sh                                     # load skills into ~/.hermes/skills/software-development/
infisical run --env=<env> -- docker compose <cmd>    # every compose call needs this wrapper
./scripts/run-engagement.sh <target> <engagement-id>
./scripts/teardown-engagement.sh <engagement-id>
```

There is no test suite, linter, or build system beyond Docker. `make test-tools` is the closest thing to a CI check.

## Skill files — gotchas

Skills are markdown files with YAML frontmatter (`name`, `description`, optional `triggers`) under `skills/pentest-*/SKILL.md`. They contain the methodology the agent follows, not executable code.

- **Naming is inconsistent across skills**: `pentest-orchestrator` and `pentest-code` use hyphens in the `name:` field; `pentest_api`, `pentest_recon`, `pentest_web`, `pentest_network`, `pentest_report` use underscores. If you add or rename a skill, match the surrounding file's convention rather than assuming one is canonical.
- The directory name (always hyphenated, e.g. `pentest-api/`) is what `make load-skills` and `load-skills.sh` copy. Hermes/Athena resolves skills by frontmatter `name`, not directory.
- Track A's `load-skills.sh` installs into `~/.hermes/skills/software-development/<skill>` (a sub-namespace); Track B's `make load-skills` installs flat into `~/.hermes/skills/<skill>`. They are not interchangeable.

## Engagement data layout (Track A)

When `run-engagement.sh` creates an engagement, the results directory is the source of truth:
```
${PENTEST_RESULTS_ROOT:-/pentest/results}/<engagement-id>/
├── audit.log               append-only timestamped events
├── engagement-state.json   phase tracking, findings counts, container/network IDs
├── recon/ web/ network/ api/ evidence/ reports/
└── <engagement-id>-evidence-<date>.tar.gz   created on teardown
```
`scripts/aggregate-results.sh` parses raw tool output (nmap, nuclei, etc.) into `findings.json`. Skills reference these paths; if you change the layout, update the orchestrator skill and both engagement scripts together.

## Image registry / IMAGE_TAG (Track A)

Compose references `${IMAGE_TAG:-stable}` against three GitLab registry images (`athena`, `athena-pentest/pentest-tools`, `athena-pentest/code-tools`). Each is built by a separate repo's CI; if the tag isn't published there, `docker compose pull` 404s. Override per-env in Infisical.

## What not to commit

`.gitignore` already blocks `.env`, `.credentials.json`, `.setup-complete`, and `results/`. The repo intentionally has no `.env` — secrets live in Infisical. Don't introduce a `.env` file to "make local dev easier."
