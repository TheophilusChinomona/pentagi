#!/usr/bin/env bash
# ============================================================================
# Toolchain Verification Script
# Tests every tool in the pentest stack to ensure it's working
# Run this after setup to verify everything is functional
#
# Usage: ./verify-toolchain.sh
# ============================================================================

set -uo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

PASS=0
FAIL=0
WARN=0
RESULTS=()

pass() { echo -e "  ${GREEN}✓${NC} $1"; ((PASS++)); RESULTS+=("PASS: $1"); }
fail() { echo -e "  ${RED}✗${NC} $1 — $2"; ((FAIL++)); RESULTS+=("FAIL: $1 — $2"); }
warn() { echo -e "  ${YELLOW}⚠${NC} $1 — $2"; ((WARN++)); RESULTS+=("WARN: $1 — $2"); }

echo -e "${CYAN}"
echo "╔══════════════════════════════════════════════════════╗"
echo "║  Athena Pentest — Toolchain Verification            ║"
echo "╚══════════════════════════════════════════════════════╝"
echo -e "${NC}"

# ============================================================================
# Tier 1 — Essential Tools
# ============================================================================

echo -e "${CYAN}Tier 1: Essential Tools${NC}"

# nmap
if command -v nmap &>/dev/null; then
    VERSION=$(nmap --version 2>/dev/null | head -1)
    pass "nmap — $VERSION"
else
    fail "nmap" "not found"
fi

# nuclei
if command -v nuclei &>/dev/null; then
    VERSION=$(nuclei -version 2>/dev/null | head -1)
    # Check templates exist
    if [[ -d "${HOME}/nuclei-templates" ]] || [[ -d "/root/nuclei-templates" ]]; then
        TEMPLATE_COUNT=$(find "${HOME}/nuclei-templates" -name "*.yaml" 2>/dev/null | wc -l)
        pass "nuclei — $VERSION ($TEMPLATE_COUNT templates)"
    else
        warn "nuclei" "templates not found, run: nuclei -update-templates"
    fi
else
    fail "nuclei" "not found"
fi

# subfinder
if command -v subfinder &>/dev/null; then
    pass "subfinder — $(subfinder -version 2>/dev/null | head -1)"
else
    fail "subfinder" "not found"
fi

# httpx
if command -v httpx &>/dev/null; then
    pass "httpx — $(httpx -version 2>/dev/null | head -1)"
else
    fail "httpx" "not found"
fi

# ffuf
if command -v ffuf &>/dev/null; then
    pass "ffuf — $(ffuf -V 2>/dev/null)"
else
    fail "ffuf" "not found"
fi

# sqlmap
if command -v sqlmap &>/dev/null; then
    pass "sqlmap — $(sqlmap --version 2>/dev/null)"
else
    fail "sqlmap" "not found"
fi

# nikto
if command -v nikto &>/dev/null; then
    pass "nikto — $(nikto -Version 2>&1 | head -1)"
else
    fail "nikto" "not found"
fi

# ============================================================================
# Tier 2 — Standard Tools
# ============================================================================

echo ""
echo -e "${CYAN}Tier 2: Standard Tools${NC}"

# hydra
if command -v hydra &>/dev/null; then
    pass "hydra — $(hydra -h 2>&1 | head -1)"
else
    fail "hydra" "not found"
fi

# gobuster
if command -v gobuster &>/dev/null; then
    pass "gobuster — $(gobuster version 2>/dev/null)"
else
    fail "gobuster" "not found"
fi

# wfuzz
if command -v wfuzz &>/dev/null; then
    pass "wfuzz — $(wfuzz --version 2>/dev/null | head -1)"
else
    fail "wfuzz" "not found"
fi

# whatweb
if command -v whatweb &>/dev/null; then
    pass "whatweb — $(whatweb --version 2>/dev/null)"
else
    fail "whatweb" "not found"
fi

# wapiti
if command -v wapiti &>/dev/null; then
    pass "wapiti — $(wapiti --version 2>/dev/null | head -1)"
else
    fail "wapiti" "not found"
fi

# searchsploit
if command -v searchsploit &>/dev/null; then
    pass "searchsploit — available"
else
    fail "searchsploit" "not found"
fi

# commix
if command -v commix &>/dev/null; then
    pass "commix — available"
else
    fail "commix" "not found"
fi

# ============================================================================
# Tier 3 — Full Arsenal
# ============================================================================

echo ""
echo -e "${CYAN}Tier 3: Full Arsenal${NC}"

# metasploit
if command -v msfconsole &>/dev/null; then
    pass "metasploit — $(msfconsole -v 2>/dev/null | head -1)"
else
    warn "metasploit" "not found (optional for basic pentesting)"
fi

# john
if command -v john &>/dev/null; then
    pass "john — $(john --list=build-info 2>/dev/null | head -1)"
else
    fail "john" "not found"
fi

# hashcat
if command -v hashcat &>/dev/null; then
    pass "hashcat — $(hashcat --version 2>/dev/null)"
else
    fail "hashcat" "not found"
fi

# responder
if command -v responder &>/dev/null || [[ -f /opt/responder/Responder.py ]]; then
    pass "responder — available"
else
    warn "responder" "not found (internal pentest only)"
fi

# netexec
if command -v netexec &>/dev/null || command -v crackmapexec &>/dev/null; then
    pass "netexec/crackmapexec — available"
else
    warn "netexec" "not found (AD testing only)"
fi

# ============================================================================
# Additional Tools
# ============================================================================

echo ""
echo -e "${CYAN}Additional Tools${NC}"

# masscan
if command -v masscan &>/dev/null; then
    pass "masscan — $(masscan --version 2>&1 | head -1)"
else
    warn "masscan" "not found (optional, nmap covers most cases)"
fi

# amass
if command -v amass &>/dev/null; then
    pass "amass — available"
else
    warn "amass" "not found (subfinder covers most cases)"
fi

# dnsx
if command -v dnsx &>/dev/null; then
    pass "dnsx — available"
else
    warn "dnsx" "not found"
fi

# naabu
if command -v naabu &>/dev/null; then
    pass "naabu — available"
else
    warn "naabu" "not found"
fi

# katana
if command -v katana &>/dev/null; then
    pass "katana — available"
else
    warn "katana" "not found"
fi

# interactsh
if command -v interactsh-client &>/dev/null; then
    pass "interactsh — available"
else
    warn "interactsh" "not found (OOB testing only)"
fi

# ============================================================================
# Wordlists
# ============================================================================

echo ""
echo -e "${CYAN}Wordlists${NC}"

if [[ -d /usr/share/wordlists/SecLists ]]; then
    COUNT=$(find /usr/share/wordlists/SecLists -type f | wc -l)
    pass "SecLists — $COUNT files"
else
    fail "SecLists" "not found at /usr/share/wordlists/SecLists"
fi

if [[ -f /usr/share/wordlists/xss-payloads.txt ]]; then
    pass "XSS payloads — available"
else
    warn "xss-payloads" "not found"
fi

# ============================================================================
# Functional Tests
# ============================================================================

echo ""
echo -e "${CYAN}Functional Tests${NC}"

# DNS resolution
if dig example.com A +short | head -1 | grep -qP '\d+\.\d+\.\d+\.\d+'; then
    pass "DNS resolution — working"
else
    fail "DNS resolution" "dig not working"
fi

# HTTP connectivity
if curl -s -o /dev/null -w "%{http_code}" https://example.com | grep -q "200"; then
    pass "HTTP connectivity — working"
else
    fail "HTTP connectivity" "cannot reach external sites"
fi

# nmap quick scan
if timeout 10 nmap -sn 127.0.0.1 &>/dev/null; then
    pass "nmap scan — working"
else
    fail "nmap scan" "failed on localhost"
fi

# nuclei version check
if timeout 10 nuclei -version &>/dev/null; then
    pass "nuclei execution — working"
else
    fail "nuclei execution" "failed to run"
fi

# ============================================================================
# Results Directory
# ============================================================================

echo ""
echo -e "${CYAN}Storage${NC}"

if [[ -d /pentest/results ]]; then
    pass "Results directory — /pentest/results exists"
elif [[ -d /opt/pentest-results ]]; then
    pass "Results directory — /opt/pentest-results exists"
else
    warn "Results directory" "not found at /pentest/results or /opt/pentest-results"
fi

# Disk space
DISK_FREE=$(df -h / 2>/dev/null | awk 'NR==2 {print $4}')
DISK_FREE_GB=$(df -BG / 2>/dev/null | awk 'NR==2 {print $4}' | tr -d 'G')
if [[ "${DISK_FREE_GB:-0}" -ge 10 ]]; then
    pass "Disk space — ${DISK_FREE} free"
else
    warn "Disk space" "only ${DISK_FREE} free (recommend 10GB+)"
fi

# ============================================================================
# Summary
# ============================================================================

echo ""
echo -e "${CYAN}══════════════════════════════════════════════════════${NC}"
echo ""
echo -e "  ${GREEN}Passed:${NC}  $PASS"
echo -e "  ${RED}Failed:${NC}  $FAIL"
echo -e "  ${YELLOW}Warning:${NC} $WARN"
echo ""

if [[ $FAIL -eq 0 ]]; then
    echo -e "  ${GREEN}✓ All critical tools operational${NC}"
    echo ""
    if [[ $WARN -gt 0 ]]; then
        echo -e "  ${YELLOW}Some optional tools missing — basic pentesting ready${NC}"
    fi
    EXIT_CODE=0
else
    echo -e "  ${RED}✗ $FAIL critical tools missing${NC}"
    echo ""
    echo "  Failed tools:"
    for result in "${RESULTS[@]}"; do
        [[ "$result" == FAIL* ]] && echo "    $result"
    done
    echo ""
    echo "  Run setup.sh to install missing tools"
    EXIT_CODE=1
fi

echo ""
echo -e "${CYAN}══════════════════════════════════════════════════════${NC}"

# Save results
VERIFICATION_LOG="/tmp/pentest/verification-$(date +%Y%m%d-%H%M%S).log"
mkdir -p /tmp/pentest
{
    echo "Athena Pentest — Toolchain Verification"
    echo "Date: $(date -Iseconds)"
    echo "Passed: $PASS | Failed: $FAIL | Warning: $WARN"
    echo ""
    for result in "${RESULTS[@]}"; do
        echo "$result"
    done
} > "$VERIFICATION_LOG"
echo ""
echo "Results saved to: $VERIFICATION_LOG"

exit $EXIT_CODE
