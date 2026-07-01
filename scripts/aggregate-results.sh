#!/usr/bin/env bash
# ============================================================================
# Result Aggregator
# Parses pentest tool outputs into structured findings JSON
# Called by the orchestrator after each scan phase
#
# Usage: ./aggregate-results.sh <target> [engagement-id]
# ============================================================================

set -uo pipefail

TARGET="${1:?Usage: $0 <target> [engagement-id]}"
ENGAGEMENT_ID="${2:-default}"
RESULTS_DIR="/tmp/pentest/${TARGET}"
FINDINGS_FILE="${RESULTS_DIR}/findings.json"

mkdir -p "$RESULTS_DIR"

# Initialize findings file if not exists
if [[ ! -f "$FINDINGS_FILE" ]]; then
    echo '{"engagement":"'"$ENGAGEMENT_ID"'","target":"'"$TARGET"'","generated_at":"'"$(date -Iseconds)"'","phases":{},"findings":[]}' | jq '.' > "$FINDINGS_FILE"
fi

log() { echo -e "\033[0;32m[+]\033[0m Aggregating: $1"; }

# ============================================================================
# Parse Nmap Results
# ============================================================================

parse_nmap() {
    local nmap_file="${RESULTS_DIR}/nmap-top.nmap"
    [[ ! -f "$nmap_file" ]] && return

    log "nmap results"

    local open_ports=$(grep -c "^[0-9].*open" "$nmap_file" 2>/dev/null || echo "0")
    local services=$(grep "^[0-9].*open" "$nmap_file" | awk '{print $3}' | sort -u | tr '\n' ',' | sed 's/,$//')
    local hosts=$(grep "Nmap scan report for" "$nmap_file" | wc -l)

    # Extract host details
    local hosts_json=$(grep "^[0-9].*open" "$nmap_file" | while read line; do
        PORT=$(echo "$line" | awk -F'/' '{print $1}')
        PROTO=$(echo "$line" | awk -F'/' '{print $2}')
        STATE=$(echo "$line" | awk '{print $2}')
        SERVICE=$(echo "$line" | awk '{print $3}')
        VERSION=$(echo "$line" | cut -d' ' -f4-)
        echo "{\"port\":\"${PORT}\",\"protocol\":\"${PROTO}\",\"state\":\"${STATE}\",\"service\":\"${SERVICE}\",\"version\":\"${VERSION}\"}"
    done | jq -s '.')

    # Update findings
    jq --argjson ports "$open_ports" \
       --arg services "$services" \
       --argjson hosts "$hosts" \
       --argjson host_details "$hosts_json" \
       '.phases.recon = {"open_ports":$ports,"services":$services,"hosts_scanned":$hosts,"port_details":$host_details}' \
       "$FINDINGS_FILE" > "${FINDINGS_FILE}.tmp" && mv "${FINDINGS_FILE}.tmp" "$FINDINGS_FILE"
}

# ============================================================================
# Parse Nuclei Results
# ============================================================================

parse_nuclei() {
    local nuclei_file="${RESULTS_DIR}/nuclei-results.txt"
    [[ ! -f "$nuclei_file" ]] && return

    log "nuclei results"

    local critical=$(grep -ci "critical" "$nuclei_file" 2>/dev/null || echo "0")
    local high=$(grep -ci "high" "$nuclei_file" 2>/dev/null || echo "0")
    local medium=$(grep -ci "medium" "$nuclei_file" 2>/dev/null || echo "0")
    local low=$(grep -ci "low" "$nuclei_file" 2>/dev/null || echo "0")
    local info=$(grep -ci "info" "$nuclei_file" 2>/dev/null || echo "0")

    # Extract findings
    local findings_json=$(while IFS= read -r line; do
        SEVERITY=$(echo "$line" | grep -oiE '(critical|high|medium|low|info)' | head -1 | tr '[:upper:]' '[:lower:]')
        TEMPLATE=$(echo "$line" | grep -oP '\[[^\]]+\]' | head -1 | tr -d '[]')
        HOST=$(echo "$line" | grep -oP 'https?://[^\s]+' | head -1)
        NAME=$(echo "$line" | sed 's/\[[^]]*\]//g' | sed 's/https?:\/\/[^ ]*//g' | xargs)
        [[ -n "$SEVERITY" ]] && echo "{\"severity\":\"${SEVERITY}\",\"template\":\"${TEMPLATE}\",\"host\":\"${HOST}\",\"name\":\"${NAME}\",\"source\":\"nuclei\"}"
    done < "$nuclei_file" | jq -s '.')

    # Merge into findings
    jq --argjson critical "$critical" \
       --argjson high "$high" \
       --argjson medium "$medium" \
       --argjson low "$low" \
       --argjson info "$info" \
       --argjson vulns "$findings_json" \
       '.phases.vuln_scan = {"critical":$critical,"high":$high,"medium":$medium,"low":$low,"info":$info} |
        .findings = (.findings + $vulns)' \
       "$FINDINGS_FILE" > "${FINDINGS_FILE}.tmp" && mv "${FINDINGS_FILE}.tmp" "$FINDINGS_FILE"
}

# ============================================================================
# Parse SQLMap Results
# ============================================================================

parse_sqlmap() {
    local sqlmap_dir="${RESULTS_DIR}/sqlmap"
    [[ ! -d "$sqlmap_dir" ]] && return

    log "sqlmap results"

    local vuln_hosts=$(find "$sqlmap_dir" -name "log" -exec grep -l "is vulnerable" {} \; 2>/dev/null | wc -l)
    local injection_types=$(find "$sqlmap_dir" -name "log" -exec grep "Type:" {} \; 2>/dev/null | awk -F': ' '{print $2}' | sort -u | tr '\n' ',' | sed 's/,$//')

    [[ "$vuln_hosts" -gt 0 ]] && {
        local sqli_findings=$(find "$sqlmap_dir" -name "log" -exec grep -l "is vulnerable" {} \; 2>/dev/null | while read logfile; do
            HOST=$(basename "$(dirname "$logfile")")
            TYPE=$(grep "Type:" "$logfile" | head -1 | awk -F': ' '{print $2}')
            DB=$(grep "back-end DBMS:" "$logfile" | head -1 | awk -F': ' '{print $2}')
            echo "{\"severity\":\"critical\",\"name\":\"SQL Injection\",\"host\":\"${HOST}\",\"type\":\"${TYPE}\",\"dbms\":\"${DB}\",\"source\":\"sqlmap\"}"
        done | jq -s '.')

        jq --argjson vulns "$sqli_findings" \
           '.findings = (.findings + $vulns) |
            .phases.exploitation = (.phases.exploitation // {}) + {"sql_injection":true,"injection_count":'\"$vulns_hosts\"'}' \
           "$FINDINGS_FILE" > "${FINDINGS_FILE}.tmp" && mv "${FINDINGS_FILE}.tmp" "$FINDINGS_FILE"
    }
}

# ============================================================================
# Parse FFUF Results
# ============================================================================

parse_ffuf() {
    local ffuf_file="${RESULTS_DIR}/ffuf-dirs.json"
    [[ ! -f "$ffuf_file" ]] && return

    log "ffuf directory results"

    local interesting=$(jq '[.results[] | select(.status == 200 or .status == 301 or .status == 302 or .status == 403)] | length' "$ffuf_file" 2>/dev/null || echo "0")
    local total=$(jq '.results | length' "$ffuf_file" 2>/dev/null || echo "0")

    jq --argjson total "$total" \
       --argjson interesting "$interesting" \
       '.phases.discovery = (.phases.discovery // {}) + {"directory_total":$total,"directory_interesting":$interesting}' \
       "$FINDINGS_FILE" > "${FINDINGS_FILE}.tmp" && mv "${FINDINGS_FILE}.tmp" "$FINDINGS_FILE"
}

# ============================================================================
# Parse Nikto Results
# ============================================================================

parse_nikto() {
    local nikto_file="${RESULTS_DIR}/nikto.txt"
    [[ ! -f "$nikto_file" ]] && return

    log "nikto results"

    local finding_count=$(grep -c "^+" "$nikto_file" 2>/dev/null || echo "0")

    jq --argjson count "$finding_count" \
       '.phases.discovery = (.phases.discovery // {}) + {"nikto_findings":$count}' \
       "$FINDINGS_FILE" > "${FINDINGS_FILE}.tmp" && mv "${FINDINGS_FILE}.tmp" "$FINDINGS_FILE"
}

# ============================================================================
# Parse Semgrep Results (SAST)
# ============================================================================

parse_semgrep() {
    local semgrep_file="${RESULTS_DIR}/semgrep-auto.json"
    [[ ! -f "$semgrep_file" ]] && return

    log "semgrep SAST results"

    local total=$(jq '.results | length' "$semgrep_file" 2>/dev/null || echo "0")
    local critical=$(jq '[.results[] | select(.extra.severity == "ERROR")] | length' "$semgrep_file" 2>/dev/null || echo "0")
    local high=$(jq '[.results[] | select(.extra.severity == "WARNING")] | length' "$semgrep_file" 2>/dev/null || echo "0")

    local findings_json=$(jq -r '.results[] | {
      severity: (if .extra.severity == "ERROR" then "critical" elif .extra.severity == "WARNING" then "high" else "medium" end),
      name: .check_id,
      file: .path,
      line: .start.line,
      description: .extra.message,
      source: "semgrep"
    }' "$semgrep_file" 2>/dev/null | jq -s '.')

    jq --argjson total "$total" \
       --argjson critical "$critical" \
       --argjson high "$high" \
       --argjson vulns "$findings_json" \
       '.phases.sast = {"total":$total,"critical":$critical,"high":$high} |
        .findings = (.findings + $vulns)' \
       "$FINDINGS_FILE" > "${FINDINGS_FILE}.tmp" && mv "${FINDINGS_FILE}.tmp" "$FINDINGS_FILE"
}

# ============================================================================
# Parse Trivy Results (Container/IaC)
# ============================================================================

parse_trivy() {
    local trivy_file="${RESULTS_DIR}/trivy-iac.json"
    [[ ! -f "$trivy_file" ]] && return

    log "trivy results"

    local critical=$(jq '[.Results[]?.Vulnerabilities[]? | select(.Severity == "CRITICAL")] | length' "$trivy_file" 2>/dev/null || echo "0")
    local high=$(jq '[.Results[]?.Vulnerabilities[]? | select(.Severity == "HIGH")] | length' "$trivy_file" 2>/dev/null || echo "0")

    jq --argjson critical "$critical" \
       --argjson high "$high" \
       '.phases.container_scan = {"critical":$critical,"high":$high,"scanner":"trivy"}' \
       "$FINDINGS_FILE" > "${FINDINGS_FILE}.tmp" && mv "${FINDINGS_FILE}.tmp" "$FINDINGS_FILE"
}

# ============================================================================
# Parse Grype Results (SCA)
# ============================================================================

parse_grype() {
    local grype_file="${RESULTS_DIR}/grype.json"
    [[ ! -f "$grype_file" ]] && return

    log "grype SCA results"

    local critical=$(jq '[.matches[] | select(.vulnerability.severity == "Critical")] | length' "$grype_file" 2>/dev/null || echo "0")
    local high=$(jq '[.matches[] | select(.vulnerability.severity == "High")] | length' "$grype_file" 2>/dev/null || echo "0")

    jq --argjson critical "$critical" \
       --argjson high "$high" \
       '.phases.sca = {"critical":$critical,"high":$high,"scanner":"grype"}' \
       "$FINDINGS_FILE" > "${FINDINGS_FILE}.tmp" && mv "${FINDINGS_FILE}.tmp" "$FINDINGS_FILE"
}

# ============================================================================
# Parse Checkov Results (IaC)
# ============================================================================

parse_checkov() {
    local checkov_file="${RESULTS_DIR}/checkov.json"
    [[ ! -f "$checkov_file" ]] && return

    log "checkov IaC results"

    local failed=$(jq '.results.failed_checks | length' "$checkov_file" 2>/dev/null || echo "0")

    jq --argjson failed "$failed" \
       '.phases.iac_scan = {"failed_checks":$failed,"scanner":"checkov"}' \
       "$FINDINGS_FILE" > "${FINDINGS_FILE}.tmp" && mv "${FINDINGS_FILE}.tmp" "$FINDINGS_FILE"
}

# ============================================================================
# Parse Secret Detection Results (TruffleHog / Gitleaks)
# ============================================================================

parse_secrets() {
    local trufflehog_file="${RESULTS_DIR}/trufflehog.json"
    local gitleaks_file="${RESULTS_DIR}/gitleaks.json"

    [[ ! -f "$trufflehog_file" && ! -f "$gitleaks_file" ]] && return

    log "secret detection results"

    local trufflehog_count=0
    local gitleaks_count=0

    if [[ -f "$trufflehog_file" ]]; then
        trufflehog_count=$(jq length "$trufflehog_file" 2>/dev/null || echo "0")
    fi

    if [[ -f "$gitleaks_file" ]]; then
        gitleaks_count=$(jq '. | length' "$gitleaks_file" 2>/dev/null || echo "0")
    fi

    local total_secrets=$((trufflehog_count + gitleaks_count))

    [[ "$total_secrets" -gt 0 ]] && {
        local secret_findings="[]"

        if [[ -f "$trufflehog_file" ]]; then
            secret_findings=$(jq -s '.[0] + (
                (if .[1] then .[1] else [] end)
            )' <(echo "$secret_findings") "$trufflehog_file" 2>/dev/null || echo "$secret_findings")
        fi

        jq --argjson total "$total_secrets" \
           --argjson trufflehog "$trufflehog_count" \
           --argjson gitleaks "$gitleaks_count" \
           --argjson secrets "$secret_findings" \
           '.phases.secrets = {"total":$total,"trufflehog":$trufflehog,"gitleaks":$gitleaks} |
            .findings += ($secrets | map(. + {"severity": "critical", "source": "secret_detection"}))' \
           "$FINDINGS_FILE" > "${FINDINGS_FILE}.tmp" && mv "${FINDINGS_FILE}.tmp" "$FINDINGS_FILE"
    }
}

# ============================================================================
# Parse Wayback URLs (Recon enrichment)
# ============================================================================

parse_wayback() {
    local wayback_file="${RESULTS_DIR}/wayback-urls.txt"
    [[ ! -f "$wayback_file" ]] && return

    log "wayback URLs"

    local url_count=$(wc -l < "$wayback_file" 2>/dev/null || echo "0")

    jq --argjson urls "$url_count" \
       '.phases.recon = (.phases.recon // {}) + {"wayback_urls":$urls}' \
       "$FINDINGS_FILE" > "${FINDINGS_FILE}.tmp" && mv "${FINDINGS_FILE}.tmp" "$FINDINGS_FILE"
}

# ============================================================================
# Generate Summary
# ============================================================================

generate_summary() {
    log "summary"

    local total_findings=$(jq '.findings | length' "$FINDINGS_FILE")
    local critical=$(jq '[.findings[] | select(.severity == "critical")] | length' "$FINDINGS_FILE")
    local high=$(jq '[.findings[] | select(.severity == "high")] | length' "$FINDINGS_FILE")
    local medium=$(jq '[.findings[] | select(.severity == "medium")] | length' "$FINDINGS_FILE")

    jq --argjson total "$total_findings" \
       --argjson critical "$critical" \
       --argjson high "$high" \
       --argjson medium "$medium" \
       '.summary = {"total_findings":$total,"critical":$critical,"high":$high,"medium":$medium,"generated_at":"'$(date -Iseconds)"'}' \
       "$FINDINGS_FILE" > "${FINDINGS_FILE}.tmp" && mv "${FINDINGS_FILE}.tmp" "$FINDINGS_FILE"
}

# ============================================================================
# Main
# ============================================================================

echo "═══════════════════════════════════════════════════"
echo "  Result Aggregator — $TARGET"
echo "═══════════════════════════════════════════════════"
echo ""

parse_nmap
parse_nuclei
parse_sqlmap
parse_ffuf
parse_nikto
parse_semgrep
parse_trivy
parse_grype
parse_checkov
parse_secrets
parse_wayback
generate_summary

echo ""
echo "Findings saved to: $FINDINGS_FILE"
echo ""

# Print summary
jq -r '
  "Summary:",
  "  Total findings: \(.summary.total_findings // 0)",
  "  Critical: \(.summary.critical // 0)",
  "  High: \(.summary.high // 0)",
  "  Medium: \(.summary.medium // 0)",
  "",
  "Phases completed:",
  (.phases | to_entries[] | "  \(.key): \(.value | to_entries | map("\(.key)=\(.value)") | join(", "))")
' "$FINDINGS_FILE"
