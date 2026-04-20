#!/usr/bin/env bash
# ============================================================================
# Agent Bootstrap — Load pentest skills into Athena
# Run after setup.sh completes
#
# Usage: ./load-skills.sh [skills-dir]
# ============================================================================

set -euo pipefail

SKILLS_DIR="${1:-$(dirname "$0")/skills}"
HERMES_SKILLS_DIR="${HOME}/.hermes/skills/software-development"

log() { echo -e "\033[0;32m[+]\033[0m $1"; }
err() { echo -e "\033[0;31m[-]\033[0m $1"; }

mkdir -p "$HERMES_SKILLS_DIR"

LOADED=0
FAILED=0

for skill_dir in "$SKILLS_DIR"/pentest-*; do
    if [[ -d "$skill_dir" ]]; then
        skill_name=$(basename "$skill_dir")
        dest="$HERMES_SKILLS_DIR/$skill_name"

        if [[ -f "$skill_dir/SKILL.md" ]]; then
            cp -r "$skill_dir" "$dest"
            log "Loaded: $skill_name"
            ((LOADED++))
        else
            err "Missing SKILL.md in $skill_name"
            ((FAILED++))
        fi
    fi
done

echo ""
echo "Skills loaded: $LOADED"
[[ $FAILED -gt 0 ]] && echo "Failed: $FAILED"
echo ""
echo "Available skills:"
for skill in "$HERMES_SKILLS_DIR"/pentest-*; do
    if [[ -d "$skill" ]]; then
        echo "  • $(basename "$skill")"
    fi
done
