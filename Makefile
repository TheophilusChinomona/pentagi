# ============================================================================
# Athena Pentest Tools — Setup for Original Hermes
# ============================================================================
# This directory provides a Docker-based pentest tools image that integrates
# with the stock Hermes agent (not the athena fork).
#
# Quick summary:
#   1. Build the pentest-tools image:   docker compose build pentest-tools
#   2. Configure Hermes:                terminal.backend = docker
#                                        terminal.docker_image = pentest-tools:latest
#   3. Load skills:                     cp -r skills/* ~/.hermes/skills/
#   4. Start testing:                  hermes (then "pentest example.com")
# ============================================================================

.PHONY: help build clean load-skills test-shell

help:
	@echo "Athena Pentest Tools — Hermes Integration"
	@echo ""
	@echo "Targets:"
	@echo "  build         Build the pentest-tools Docker image"
	@echo "  build-no-cache  Build without cache (fresh tools)"
	@echo "  shell         Open a shell inside the pentest-tools container"
	@echo "  test-tools    Verify all tools are installed"
	@echo "  load-skills   Copy skill files to ~/.hermes/skills/"
	@echo "  clean         Remove built image and containers"
	@echo ""
	@echo "After setup, configure Hermes:"
	@echo "  hermes config set terminal.backend docker"
	@echo "  hermes config set terminal.docker_image pentest-tools:latest"
	@echo ""
	@echo "Then start Hermes and say:"
	@echo "  \"pentest example.com\""

# Build the pentest tools image
build:
	docker compose build pentest-tools

build-no-cache:
	docker compose build --no-cache pentest-tools

# Quick sanity check — verify tools inside the container
test-tools:
	@echo "Testing pentest-tools image availability..."
	@docker run --rm pentest-tools:latest bash -c '\
	  echo \"--- Tool versions ---\" && \
	  nmap --version | head -1 && \
	  nuclei -version | head -1 && \
	  subfinder -version | head -1 && \
	  httpx -version | head -1 && \
	  sqlmap --version | head -1 && \
	  nikto -Version | head -1 && \
	  echo \"--- OK ---\"'

# Open an interactive shell in the tools container
shell:
	docker run --rm -it pentest-tools:latest bash

# Install skills into Hermes
load-skills:
	@echo "Loading pentest skills into ~/.hermes/skills/"
	@mkdir -p ~/.hermes/skills
	@for skill in pentest-*; do \
	  if [ -d "$$skill" ] && [ -f "$$skill/SKILL.md" ]; then \
	    echo "  $$skill"; \
	    rm -rf "~/.hermes/skills/$$skill"; \
	    cp -r "$$skill" ~/.hermes/skills/; \
	  fi; \
	done
	@echo "Done. Skills available:"
	@ls -1 ~/.hermes/skills/pentest-* 2>/dev/null || true

# Remove built image and any stopped containers
clean:
	docker compose down
	docker rmi pentest-tools:latest 2>/dev/null || true
