#!/usr/bin/env bash
set -euo pipefail

HERMES_HOME="${HERMES_HOME:-/opt/data}"

mkdir -p "${HERMES_HOME}" "${HERMES_HOME}/skills" "/pentest/results"

# Seed Athena pentest skills into runtime home if absent.
if [ -d "/opt/athena/skills" ]; then
  for skill_path in /opt/athena/skills/*; do
    skill_name="$(basename "$skill_path")"
    if [ ! -e "${HERMES_HOME}/skills/${skill_name}" ]; then
      cp -R "$skill_path" "${HERMES_HOME}/skills/${skill_name}"
    fi
  done
fi

exec /opt/hermes/docker/entrypoint.sh "$@"
