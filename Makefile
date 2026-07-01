# ============================================================================
# PentAGI Fork — Pentest Toolkit
# ============================================================================
# Quick reference:
#   make build-tools     Build custom pentest-tools image (Dockerfile.pentest)
#   make up              Start the main stack (pentagi + pgvector + scraper)
#   make down            Stop the main stack
#   make load-skills     Copy skill files to ~/.hermes/skills/ (for Hermes agents)
#   make test-tools      Smoke-test tools inside the pentest-tools image
#   make shell           Interactive bash inside pentest-tools image
#   make logs            Follow pentagi backend logs
# ============================================================================

.PHONY: help build-tools up down logs shell test-tools load-skills clean

help:
	@echo "PentAGI Fork — Pentest Toolkit"
	@echo ""
	@echo "Targets:"
	@echo "  build-tools   Build the custom pentest-tools image (Dockerfile.pentest)"
	@echo "  up            Start the main stack (with bundled pgvector)"
	@echo "  up-external   Start stack with external DB (set DATABASE_URL in .env)"
	@echo "  down          Stop the main stack"
	@echo "  logs          Follow pentagi backend logs"
	@echo "  shell         Interactive bash inside pentest-tools:latest"
	@echo "  load-skills   Copy skill files to ~/.hermes/skills/ (for Hermes agents)"
	@echo "  test-tools    Smoke-test tools inside pentest-tools:latest"
	@echo "  clean         Remove built image"
	@echo ""
	@echo "Optional stacks:"
	@echo "  docker compose -f docker-compose-langfuse.yml up -d"
	@echo "  docker compose -f docker-compose-observability.yml up -d"
	@echo "  docker compose -f docker-compose-graphiti.yml up -d"
	@echo ""

# Build the custom pentest tools image
build-tools:
	docker compose build pentest-tools

# Start main stack (with bundled pgvector)
up:
	docker compose --profile internal-db up -d

# Start stack with external database (set DATABASE_URL in .env)
# No local pgvector needed — connects to your existing ParadeDB/PostgreSQL
up-external:
	docker compose up -d

# Stop main stack
down:
	docker compose down

# Follow backend logs
logs:
	docker compose logs -f pentagi

# Interactive shell inside the tools container
shell:
	docker run --rm -it pentest-tools:latest bash

# Quick smoke test — verify tools inside the image
test-tools:
	@echo "Testing pentest-tools image..."
	@docker run --rm pentest-tools:latest bash -c '\
	  echo "=== Network pentesting ===" && \
	  nmap --version | head -1 && \
	  nuclei -version | head -1 && \
	  subfinder -version 2>&1 | head -1 && \
	  httpx -version 2>&1 | head -1 && \
	  naabu -version 2>&1 | head -1 && \
	  dnsx -version 2>&1 | head -1 && \
	  masscan --version 2>&1 | head -1 && \
	  hydra -h 2>&1 | head -1 && \
	  sqlmap --version | head -1 && \
	  nikto -Version | head -1 && \
	  echo "=== Web/API pentesting ===" && \
	  katana --version 2>&1 | head -1 && \
	  ffuf --help 2>&1 | head -1 && \
	  gobuster version 2>&1 | head -1 && \
	  whatweb --version 2>&1 | head -1 && \
	  wapiti --version 2>&1 | head -1 && \
	  commix --version 2>&1 | head -1 && \
	  waybackurls -h 2>&1 | head -1 && \
	  websocat --version 2>&1 | head -1 && \
	  jwt_tool 2>&1 | head -1 && \
	  echo "=== Code audit ===" && \
	  semgrep --version 2>&1 | head -1 && \
	  bandit --version 2>&1 | head -1 && \
	  trivy --version 2>&1 | head -1 && \
	  grype version 2>&1 | head -1 && \
	  checkov --version 2>&1 | head -1 && \
	  gitleaks version 2>&1 | head -1 && \
	  trufflehog --version 2>&1 | head -1 && \
	  echo "=== Post-exploit / AD ===" && \
	  john --help 2>&1 | head -1 && \
	  hashcat --version 2>&1 | head -1 && \
	  searchsploit -h 2>&1 | head -1 && \
	  echo "=== OK ---"'

# Copy skill files to ~/.hermes/skills/ for Hermes agents
# Skills describe how agents use the PentAGI API and pentest-tools image
load-skills:
	@echo "Loading skills into ~/.hermes/skills/"
	@mkdir -p ~/.hermes/skills
	@for skill in pentagi-stack pentagi-api pentest-tools; do \
	  if [ -d "skills/$$skill" ] && [ -f "skills/$$skill/SKILL.md" ]; then \
	    echo "  $$skill"; \
	    rm -rf ~/.hermes/skills/$$skill; \
	    cp -r skills/$$skill ~/.hermes/skills/; \
	  fi; \
	done
	@echo "Done. Skills loaded: pentagi-stack, pentagi-api, pentest-tools"

# Remove built image and stopped containers
clean:
	docker compose down
	docker rmi pentest-tools:latest 2>/dev/null || true
