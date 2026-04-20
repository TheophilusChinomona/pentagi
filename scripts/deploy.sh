#!/usr/bin/env bash
# ============================================================================
# Pentest Server Deployment Playbook
# Built by Athena — deploys from build server to isolated pentest server
#
# Usage: ./deploy.sh <pentest-server-ip> [ssh-user]
# Example: ./deploy.sh 192.168.1.50 root
# ============================================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log()  { echo -e "${GREEN}[+]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
err()  { echo -e "${RED}[-]${NC} $1"; }
step() { echo -e "\n${BLUE}=== $1 ===${NC}\n"; }

# ============================================================================
# Configuration
# ============================================================================

PENTEST_SERVER="${1:?Usage: $0 <pentest-server-ip> [ssh-user]}"
SSH_USER="${2:-root}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILL_DIR="$HOME/.hermes/skills/software-development"
REMOTE_DIR="/opt/pentest-athena"

# ============================================================================
# Pre-flight Checks
# ============================================================================

step "Pre-flight Checks"

log "Testing SSH connectivity to $SSH_USER@$PENTEST_SERVER..."
if ! ssh -o ConnectTimeout=10 -o BatchMode=yes "$SSH_USER@$PENTEST_SERVER" "echo 'SSH OK'" 2>/dev/null; then
    err "Cannot SSH to $SSH_USER@$PENTEST_SERVER"
    err "Make sure SSH key auth is configured: ssh-copy-id $SSH_USER@$PENTEST_SERVER"
    exit 1
fi
log "SSH connection verified"

# ============================================================================
# Phase 1: Create Remote Directory Structure
# ============================================================================

step "Phase 1: Setting up remote directory structure"

ssh "$SSH_USER@$PENTEST_SERVER" bash <<EOF
    mkdir -p $REMOTE_DIR/{scripts,skills,configs,wordlists,results}
    mkdir -p /tmp/pentest
    echo "Remote directories created"
EOF

# ============================================================================
# Phase 2: Copy Installation Script
# ============================================================================

step "Phase 2: Copying tool installation script"

scp "$SCRIPT_DIR/scripts/install-tools.sh" "$SSH_USER@$PENTEST_SERVER:$REMOTE_DIR/scripts/"
log "Installation script copied"

# ============================================================================
# Phase 3: Copy Skills
# ============================================================================

step "Phase 3: Copying pentest skills"

for skill_dir in "$SKILL_DIR"/pentest-*; do
    if [[ -d "$skill_dir" ]]; then
        skill_name=$(basename "$skill_dir")
        log "Copying skill: $skill_name"
        scp -r "$skill_dir" "$SSH_USER@$PENTEST_SERVER:$REMOTE_DIR/skills/"
    fi
done

# ============================================================================
# Phase 4: Copy Configs
# ============================================================================

step "Phase 4: Copying configuration files"

# nuclei config template
cat > /tmp/nuclei-config.yaml <<'NUCLEI'
# Nuclei configuration for pentest server
# Adjust threads/rate based on target and authorization level

# Global vars
var:
  # Add custom variables here
  # USERNAME: admin
  # PASSWORD: admin

# Rate limiting
rate-limit: 150
bulk-size: 25
concurrency: 30

# Output
omit-raw: false
include-rr: true

# Templates to use
tags: ""

# Severity filter
severity: critical,high,medium
NUCLEI

scp /tmp/nuclei-config.yaml "$SSH_USER@$PENTEST_SERVER:$REMOTE_DIR/configs/"
rm /tmp/nuclei-config.yaml

log "Configuration files copied"

# ============================================================================
# Phase 5: Copy This Playbook
# ============================================================================

step "Phase 5: Copying deployment files"

scp "$SCRIPT_DIR/README.md" "$SSH_USER@$PENTEST_SERVER:$REMOTE_DIR/"
log "Documentation copied"

# ============================================================================
# Phase 6: Run Tool Installation (Optional)
# ============================================================================

step "Phase 6: Tool installation"

read -p "Run tool installation on pentest server now? (y/N) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    log "Running tool installation..."
    ssh "$SSH_USER@$PENTEST_SERVER" "cd $REMOTE_DIR/scripts && chmod +x install-tools.sh && sudo ./install-tools.sh"
    log "Tool installation complete"
else
    warn "Skipped tool installation. Run manually on pentest server:"
    warn "  ssh $SSH_USER@$PENTEST_SERVER"
    warn "  cd $REMOTE_DIR/scripts && sudo ./install-tools.sh"
fi

# ============================================================================
# Phase 7: Verify Deployment
# ============================================================================

step "Phase 7: Verification"

ssh "$SSH_USER@$PENTEST_SERVER" bash <<'VERIFY'
    echo "=== Deployed Files ==="
    find /opt/pentest-athena -type f | sort
    echo ""
    echo "=== Installed Tools ==="
    for tool in nmap nuclei subfinder httpx ffuf sqlmap nikto hydra gobuster wfuzz whatweb wapiti searchsploit john hashcat masscan; do
        if command -v $tool &>/dev/null; then
            echo "  ✓ $tool"
        else
            echo "  ✗ $tool (not installed)"
        fi
    done
VERIFY

# ============================================================================
# Summary
# ============================================================================

step "Deployment Complete"

cat <<EOF

Deployed to: $SSH_USER@$PENTEST_SERVER:$REMOTE_DIR/

Structure:
  $REMOTE_DIR/
  ├── scripts/          Tool installation script
  ├── skills/           Athena pentest skills
  ├── configs/          Tool configurations
  ├── wordlists/        (created by install script)
  └── results/          Engagement output

Next steps:
  1. SSH into pentest server: ssh $SSH_USER@$PENTEST_SERVER
  2. Run install if not done: cd $REMOTE_DIR/scripts && sudo ./install-tools.sh
  3. Verify tools: nmap --version && nuclei -version
  4. Install Hermes gateway on the pentest server
  5. Load pentest skills into the gateway
  6. Start testing: "pentest target.com"

Security notes:
  - Pentest server should have separate IP/egress
  - All traffic from this server will be scanning activity
  - Keep it isolated from your dev infrastructure
  - Consider VPN/proxy for client engagements
EOF
