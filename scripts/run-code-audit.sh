#!/usr/bin/env bash
# ============================================================================
# Code Security Audit Runner
# Runs a full code security audit on a target repository
#
# Usage: ./run-code-audit.sh <repo-path-or-url> [output-dir]
# Example: ./run-code-audit.sh /opt/repos/myapp /tmp/scan/myapp
# ============================================================================

set -uo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log()  { echo -e "${GREEN}[+]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
err()  { echo -e "${RED}[-]${NC} $1"; }
step() { echo -e "\n${CYAN}═══ $1 ═══${NC}\n"; }

TARGET="${1:?Usage: $0 <repo-path-or-url> [output-dir]}"
OUTPUT_DIR="${2:-/tmp/scan/$(basename "$TARGET" .git)-$(date +%Y%m%d-%H%M%S)}"

mkdir -p "$OUTPUT_DIR"

echo -e "${CYAN}"
echo "╔══════════════════════════════════════════════════════╗"
echo "║  Athena — Code Security Audit                       ║"
echo "╚══════════════════════════════════════════════════════╝"
echo -e "${NC}"
echo "Target: $TARGET"
echo "Output: $OUTPUT_DIR"
echo ""

# Clone if URL
REPO_PATH="$TARGET"
if [[ "$TARGET" =~ ^https?:// ]]; then
    REPO_PATH="/tmp/scan-repos/$(basename "$TARGET" .git)"
    if [[ ! -d "$REPO_PATH" ]]; then
        log "Cloning repository..."
        git clone --depth 1 "$TARGET" "$REPO_PATH" 2>/dev/null
    fi
fi

# ============================================================================
# Phase 1: Secret Detection
# ============================================================================

step "Phase 1: Secret Detection"

# trufflehog
if command -v trufflehog &>/dev/null; then
    log "Running trufflehog..."
    trufflehog filesystem "$REPO_PATH" --only-verified --json > "$OUTPUT_DIR/trufflehog.json" 2>/dev/null || true
    SECRETS=$(jq 'length' "$OUTPUT_DIR/trufflehog.json" 2>/dev/null || echo "0")
    log "trufflehog: $SECRETS verified secrets found"
else
    warn "trufflehog not installed"
fi

# gitleaks
if command -v gitleaks &>/dev/null; then
    log "Running gitleaks..."
    gitleaks detect --source "$REPO_PATH" --report-path "$OUTPUT_DIR/gitleaks.json" --report-format json 2>/dev/null || true
    LEAKS=$(jq 'length' "$OUTPUT_DIR/gitleaks.json" 2>/dev/null || echo "0")
    log "gitleaks: $LEAKS leaks found"
else
    warn "gitleaks not installed"
fi

# grep patterns
log "Scanning for hardcoded secrets patterns..."
grep -rn --include="*.{js,ts,py,go,yaml,yml,json,env,conf,cfg,ini,toml,rb,java,php,cs}" \
  -iE '(api[_-]?key|secret[_-]?key|password|token|aws[_-]?access|private[_-]?key)\s*[:=]\s*["\x27][^\s"'\'']{8,}' \
  "$REPO_PATH" 2>/dev/null | grep -v node_modules | grep -v ".git/" | grep -v vendor > "$OUTPUT_DIR/grep-secrets.txt" || true
GREP_HITS=$(wc -l < "$OUTPUT_DIR/grep-secrets.txt" 2>/dev/null || echo "0")
log "Pattern scan: $GREP_HITS potential secrets"

# ============================================================================
# Phase 2: SAST
# ============================================================================

step "Phase 2: Static Analysis (SAST)"

# semgrep
if command -v semgrep &>/dev/null; then
    log "Running semgrep (auto rules)..."
    semgrep scan "$REPO_PATH" --config auto --json -o "$OUTPUT_DIR/semgrep-auto.json" 2>/dev/null || true
    SEMGREP_HITS=$(jq '.results | length' "$OUTPUT_DIR/semgrep-auto.json" 2>/dev/null || echo "0")
    log "semgrep: $SEMGREP_HITS findings"

    log "Running semgrep (OWASP Top 10)..."
    semgrep scan "$REPO_PATH" --config "p/owasp-top-ten" --json -o "$OUTPUT_DIR/semgrep-owasp.json" 2>/dev/null || true
else
    warn "semgrep not installed"
fi

# bandit (Python)
if command -v bandit &>/dev/null && find "$REPO_PATH" -name "*.py" | head -1 | grep -q .; then
    log "Running bandit (Python)..."
    bandit -r "$REPO_PATH" -f json -o "$OUTPUT_DIR/bandit.json" --severity-level medium 2>/dev/null || true
else
    warn "bandit not installed or no Python files"
fi

# ============================================================================
# Phase 3: SCA — Dependency Scanning
# ============================================================================

step "Phase 3: Dependency Scanning (SCA)"

# grype
if command -v grype &>/dev/null; then
    log "Running grype..."
    grype dir:"$REPO_PATH" -o json > "$OUTPUT_DIR/grype.json" 2>/dev/null || true
    GRYPE_HITS=$(jq '.matches | length' "$OUTPUT_DIR/grype.json" 2>/dev/null || echo "0")
    log "grype: $GRYPE_HITS vulnerable dependencies"
else
    warn "grype not installed"
fi

# osv-scanner
if command -v osv-scanner &>/dev/null; then
    log "Running osv-scanner..."
    osv-scanner --format json -r "$REPO_PATH" > "$OUTPUT_DIR/osv.json" 2>/dev/null || true
else
    warn "osv-scanner not installed"
fi

# npm audit
if [[ -f "$REPO_PATH/package.json" ]]; then
    log "Running npm audit..."
    (cd "$REPO_PATH" && npm audit --json > "$OUTPUT_DIR/npm-audit.json" 2>/dev/null) || true
    NPM_VULNS=$(jq '.metadata.vulnerabilities | to_entries | map(select(.value > 0)) | length' "$OUTPUT_DIR/npm-audit.json" 2>/dev/null || echo "0")
    log "npm audit: $NPM_VULNS severity levels with vulnerabilities"
fi

# pip-audit
if [[ -f "$REPO_PATH/requirements.txt" ]]; then
    log "Running pip-audit..."
    pip-audit -r "$REPO_PATH/requirements.txt" -f json -o "$OUTPUT_DIR/pip-audit.json" 2>/dev/null || true
fi

# ============================================================================
# Phase 4: IaC Scanning
# ============================================================================

step "Phase 4: Infrastructure as Code (IaC)"

# Check for Docker files
if [[ -f "$REPO_PATH/Dockerfile" ]] || [[ -f "$REPO_PATH/docker-compose.yml" ]]; then
    if command -v checkov &>/dev/null; then
        log "Running checkov on Docker files..."
        [[ -f "$REPO_PATH/Dockerfile" ]] && checkov -f "$REPO_PATH/Dockerfile" --output json --output-file-path "$OUTPUT_DIR/checkov-dockerfile.json" 2>/dev/null || true
        [[ -f "$REPO_PATH/docker-compose.yml" ]] && checkov -f "$REPO_PATH/docker-compose.yml" --output json --output-file-path "$OUTPUT_DIR/checkov-docker.json" 2>/dev/null || true
    fi

    if command -v trivy &>/dev/null; then
        log "Running trivy config..."
        trivy config "$REPO_PATH" --format json -o "$OUTPUT_DIR/trivy-iac.json" 2>/dev/null || true
    fi
fi

# ============================================================================
# Phase 5: License Check
# ============================================================================

step "Phase 5: License Compliance"

if [[ -f "$REPO_PATH/package.json" ]] && command -v license-checker &>/dev/null; then
    log "Checking npm licenses..."
    (cd "$REPO_PATH" && license-checker --json --out "$OUTPUT_DIR/npm-licenses.json" 2>/dev/null) || true
fi

# ============================================================================
# Phase 6: Aggregate Results
# ============================================================================

step "Phase 6: Aggregating Results"

SEVERITY_CRITICAL=0
SEVERITY_HIGH=0
SEVERITY_MEDIUM=0
SEVERITY_LOW=0

# Count trufflehog secrets
SEVERITY_CRITICAL=$((SEVERITY_CRITICAL + ${SECRETS:-0}))

# Count semgrep findings by severity
if [[ -f "$OUTPUT_DIR/semgrep-auto.json" ]]; then
    SEMGREP_ERROR=$(jq '[.results[] | select(.extra.severity == "ERROR")] | length' "$OUTPUT_DIR/semgrep-auto.json" 2>/dev/null || echo "0")
    SEMGREP_WARNING=$(jq '[.results[] | select(.extra.severity == "WARNING")] | length' "$OUTPUT_DIR/semgrep-auto.json" 2>/dev/null || echo "0")
    SEVERITY_HIGH=$((SEVERITY_HIGH + SEMGREP_ERROR))
    SEVERITY_MEDIUM=$((SEVERITY_MEDIUM + SEMGREP_WARNING))
fi

# Count grype findings by severity
if [[ -f "$OUTPUT_DIR/grype.json" ]]; then
    GRYPE_CRITICAL=$(jq '[.matches[] | select(.vulnerability.severity == "Critical")] | length' "$OUTPUT_DIR/grype.json" 2>/dev/null || echo "0")
    GRYPE_HIGH=$(jq '[.matches[] | select(.vulnerability.severity == "High")] | length' "$OUTPUT_DIR/grype.json" 2>/dev/null || echo "0")
    GRYPE_MEDIUM=$(jq '[.matches[] | select(.vulnerability.severity == "Medium")] | length' "$OUTPUT_DIR/grype.json" 2>/dev/null || echo "0")
    SEVERITY_CRITICAL=$((SEVERITY_CRITICAL + GRYPE_CRITICAL))
    SEVERITY_HIGH=$((SEVERITY_HIGH + GRYPE_HIGH))
    SEVERITY_MEDIUM=$((SEVERITY_MEDIUM + GRYPE_MEDIUM))
fi

# Generate summary JSON
cat > "$OUTPUT_DIR/audit-summary.json" <<EOF
{
  "target": "$TARGET",
  "scanned_at": "$(date -Iseconds)",
  "severity": {
    "critical": $SEVERITY_CRITICAL,
    "high": $SEVERITY_HIGH,
    "medium": $SEVERITY_MEDIUM,
    "low": $SEVERITY_LOW
  },
  "tools_run": {
    "secrets": {"trufflehog": $(command -v trufflehog &>/dev/null && echo true || echo false), "gitleaks": $(command -v gitleaks &>/dev/null && echo true || echo false)},
    "sast": {"semgrep": $(command -v semgrep &>/dev/null && echo true || echo false), "bandit": $(command -v bandit &>/dev/null && echo true || echo false)},
    "sca": {"grype": $(command -v grype &>/dev/null && echo true || echo false), "osv-scanner": $(command -v osv-scanner &>/dev/null && echo true || echo false)},
    "iac": {"checkov": $(command -v checkov &>/dev/null && echo true || echo false), "trivy": $(command -v trivy &>/dev/null && echo true || echo false)}
  },
  "files_scanned": $(find "$REPO_PATH" -type f -not -path "*/.git/*" -not -path "*/node_modules/*" -not -path "*/vendor/*" | wc -l)
}
EOF

# ============================================================================
# Summary
# ============================================================================

step "Audit Complete"

echo -e "${CYAN}Results:${NC}"
echo "  Critical: $SEVERITY_CRITICAL"
echo "  High:     $SEVERITY_HIGH"
echo "  Medium:   $SEVERITY_MEDIUM"
echo "  Low:      $SEVERITY_LOW"
echo ""
echo "  Output: $OUTPUT_DIR/"
echo "  Summary: $OUTPUT_DIR/audit-summary.json"
echo ""

# List all result files
echo -e "${CYAN}Generated files:${NC}"
ls -la "$OUTPUT_DIR/" | grep -v "^total" | grep -v "^d"
