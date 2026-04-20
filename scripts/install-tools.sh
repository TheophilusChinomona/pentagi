#!/usr/bin/env bash
# ============================================================================
# Pentest Toolkit — Full Stack Installation Script
# Built by Athena for Theophilus
# Run on: Ubuntu 24.04 pentest server (isolated)
# Usage: chmod +x install-tools.sh && sudo ./install-tools.sh
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

# Must run as root
if [[ $EUID -ne 0 ]]; then
    err "Run as root: sudo ./install-tools.sh"
    exit 1
fi

INSTALL_DIR="/opt/pentest-tools"
BIN_DIR="/usr/local/bin"
mkdir -p "$INSTALL_DIR"

# ============================================================================
# TIER 1 — Essential Tools
# ============================================================================

step "Tier 1: Essential Tools"

log "Updating package lists..."
apt-get update -qq

log "Installing apt packages..."
apt-get install -y -qq \
    nmap \
    sqlmap \
    nikto \
    whois \
    dnsutils \
    traceroute \
    curl \
    wget \
    git \
    python3 \
    python3-pip \
    python3-venv \
    unzip \
    jq \
    build-essential \
    libpcap-dev

# --- nuclei (ProjectDiscovery) ---
log "Installing nuclei..."
if ! command -v nuclei &>/dev/null; then
    go_version=$(curl -s https://go.dev/dl/?mode=json | jq -r '.[0].version' 2>/dev/null || echo "go1.24.1")
    
    # Install Go if not present
    if ! command -v go &>/dev/null; then
        log "Installing Go ($go_version)..."
        wget -q "https://go.dev/dl/${go_version}.linux-amd64.tar.gz" -O /tmp/go.tar.gz
        rm -rf /usr/local/go && tar -C /usr/local -xzf /tmp/go.tar.gz
        echo 'export PATH=$PATH:/usr/local/go/bin:$HOME/go/bin' >> /etc/profile.d/go.sh
        source /etc/profile.d/go.sh
        rm /tmp/go.tar.gz
    fi
    
    export PATH=$PATH:/usr/local/go/bin:$HOME/go/bin
    go install -v github.com/projectdiscovery/nuclei/v3/cmd/nuclei@latest
    cp ~/go/bin/nuclei "$BIN_DIR/"
    log "Updating nuclei templates..."
    nuclei -update-templates -silent || true
fi

# --- subfinder ---
log "Installing subfinder..."
if ! command -v subfinder &>/dev/null; then
    go install -v github.com/projectdiscovery/subfinder/v2/cmd/subfinder@latest
    cp ~/go/bin/subfinder "$BIN_DIR/"
fi

# --- httpx ---
log "Installing httpx..."
if ! command -v httpx &>/dev/null; then
    go install -v github.com/projectdiscovery/httpx/cmd/httpx@latest
    cp ~/go/bin/httpx "$BIN_DIR/"
fi

# --- ffuf ---
log "Installing ffuf..."
if ! command -v ffuf &>/dev/null; then
    go install -v github.com/ffuf/ffuf/v2@latest
    cp ~/go/bin/ffuf "$BIN_DIR/"
fi

# ============================================================================
# TIER 2 — Standard Tools
# ============================================================================

step "Tier 2: Standard Tools"

log "Installing hydra..."
apt-get install -y -qq hydra

log "Installing wfuzz..."
apt-get install -y -qq wfuzz

log "Installing gobuster..."
if ! command -v gobuster &>/dev/null; then
    go install -v github.com/OJ/gobuster/v3@latest
    cp ~/go/bin/gobuster "$BIN_DIR/"
fi

log "Installing commix..."
if ! command -v commix &>/dev/null; then
    pip3 install commix --break-system-packages 2>/dev/null || \
    git clone https://github.com/commixproject/commix.git "$INSTALL_DIR/commix"
    ln -sf "$INSTALL_DIR/commix/commix.py" "$BIN_DIR/commix"
fi

log "Installing whatweb..."
apt-get install -y -qq whatweb

log "Installing wapiti..."
apt-get install -y -qq wapiti

log "Installing exploitdb (searchsploit)..."
if ! command -v searchsploit &>/dev/null; then
    git clone --depth 1 https://gitlab.com/exploit-database/exploitdb.git "$INSTALL_DIR/exploitdb"
    ln -sf "$INSTALL_DIR/exploitdb/searchsploit" "$BIN_DIR/searchsploit"
    cp -r "$INSTALL_DIR/exploitdb/"* "$BIN_DIR/" 2>/dev/null || true
fi

# ============================================================================
# TIER 3 — Full Arsenal
# ============================================================================

step "Tier 3: Full Arsenal"

log "Installing Metasploit Framework..."
if ! command -v msfconsole &>/dev/null; then
    curl -s https://raw.githubusercontent.com/rapid7/metasploit-omnibus/master/config/templates/metasploit-framework-wrappers/msfupdate.erb > /tmp/msfinstall
    chmod 755 /tmp/msfinstall
    /tmp/msfinstall || warn "Metasploit install had issues — try running msfupdate manually"
    rm -f /tmp/msfinstall
fi

log "Installing John the Ripper..."
apt-get install -y -qq john

log "Installing hashcat..."
apt-get install -y -qq hashcat

log "Installing Responder..."
if ! command -v responder &>/dev/null; then
    git clone https://github.com/lgandx/Responder.git "$INSTALL_DIR/responder"
    pip3 install -r "$INSTALL_DIR/responder/requirements.txt" --break-system-packages 2>/dev/null || true
    ln -sf "$INSTALL_DIR/responder/Responder.py" "$BIN_DIR/responder"
fi

log "Installing Impacket..."
pip3 install impacket --break-system-packages 2>/dev/null || \
pip3 install git+https://github.com/fortra/impacket.git --break-system-packages 2>/dev/null || \
warn "Impacket install had issues"

log "Installing CrackMapExec (NetExec)..."
if ! command -v netexec &>/dev/null; then
    pip3 install netexec --break-system-packages 2>/dev/null || \
    pip3 install crackmapexec --break-system-packages 2>/dev/null || \
    warn "CrackMapExec/NetExec install had issues"
fi

log "Installing enum4linux-ng..."
if ! command -v enum4linux-ng &>/dev/null; then
    pip3 install enum4linux-ng --break-system-packages 2>/dev/null || \
    git clone https://github.com/cddmp/enum4linux-ng.git "$INSTALL_DIR/enum4linux-ng"
    ln -sf "$INSTALL_DIR/enum4linux-ng/enum4linux-ng.py" "$BIN_DIR/enum4linux-ng"
fi

# ============================================================================
# Additional Useful Tools
# ============================================================================

step "Additional Tools"

log "Installing masscan..."
apt-get install -y -qq masscan

log "Installing amass..."
if ! command -v amass &>/dev/null; then
    go install -v github.com/owasp-amass/amass/v4/...@master
    cp ~/go/bin/amass "$BIN_DIR/" 2>/dev/null || true
fi

log "Installing dnsx..."
if ! command -v dnsx &>/dev/null; then
    go install -v github.com/projectdiscovery/dnsx/cmd/dnsx@latest
    cp ~/go/bin/dnsx "$BIN_DIR/"
fi

log "Installing naabu (port scanner)..."
if ! command -v naabu &>/dev/null; then
    go install -v github.com/projectdiscovery/naabu/v2/cmd/naabu@latest
    cp ~/go/bin/naabu "$BIN_DIR/"
fi

log "Installing katana (crawler)..."
if ! command -v katana &>/dev/null; then
    go install -v github.com/projectdiscovery/katana/cmd/katana@latest
    cp ~/go/bin/katana "$BIN_DIR/"
fi

log "Installing interactsh (OOB testing)..."
if ! command -v interactsh-client &>/dev/null; then
    go install -v github.com/projectdiscovery/interactsh/cmd/interactsh-client@latest
    cp ~/go/bin/interactsh-client "$BIN_DIR/"
fi

# ============================================================================
# Wordlists
# ============================================================================

step "Wordlists"

WORDLIST_DIR="/usr/share/wordlists"
mkdir -p "$WORDLIST_DIR"

log "Downloading SecLists..."
if [[ ! -d "$WORDLIST_DIR/SecLists" ]]; then
    git clone --depth 1 https://github.com/danielmiessler/SecLists.git "$WORDLIST_DIR/SecLists"
fi

log "Downloading fuzzing payloads..."
if [[ ! -f "$WORDLIST_DIR/xss-payloads.txt" ]]; then
    wget -q "https://raw.githubusercontent.com/payloadbox/xss-payload-list/master/Intruder/xss-payload-list.txt" \
        -O "$WORDLIST_DIR/xss-payloads.txt"
fi

# ============================================================================
# Verification
# ============================================================================

step "Verification"

TOOLS=(nmap nuclei subfinder httpx ffuf sqlmap nikto hydra gobuster wfuzz
       whatweb wapiti searchsploit john hashcat masscan)

INSTALLED=0
MISSING=0

for tool in "${TOOLS[@]}"; do
    if command -v "$tool" &>/dev/null; then
        log "✓ $tool"
        ((INSTALLED++))
    else
        warn "✗ $tool — not found"
        ((MISSING++))
    fi
done

echo ""
echo -e "${GREEN}Installed: $INSTALLED${NC} | ${RED}Missing: $MISSING${NC}"
echo ""

# ============================================================================
# Summary
# ============================================================================

step "Installation Complete"

cat << 'EOF'
Tools installed at /opt/pentest-tools/
Binaries in /usr/local/bin/
Wordlists at /usr/share/wordlists/

Next steps:
1. Run 'nuclei -update-templates' to get latest vulnerability templates
2. Configure any API keys (Shodan, Censys, etc.) in ~/.config/
3. Deploy Athena pentest skills from the build server

Quick test:
  nmap --version
  nuclei -version
  subfinder -version
  httpx -version

Full stack includes:
  Recon:       nmap, subfinder, httpx, amass, masscan, dnsx, naabu
  Web:         nuclei, nikto, sqlmap, ffuf, gobuster, wfuzz, wapiti, whatweb, katana
  Network:     hydra, responder, netexec, enum4linux-ng, impacket
  Cracking:    john, hashcat
  Exploitation: metasploit, searchsploit, commix
  OOB:         interactsh
  Wordlists:   SecLists, XSS payloads
EOF
