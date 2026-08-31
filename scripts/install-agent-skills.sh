#!/usr/bin/env bash
# Installs the shared agent skills globally (user-level), for this repo's agent workflow.
#
# Usage: ./scripts/install-agent-skills.sh [agent]
#   agent  which agent to install to (default: claude-code; '*' installs to all)
set -euo pipefail

AGENT="${1:-claude-code}"

# --agent avoids an agent-selection prompt that ignores --yes and crashes on
# non-TTY stdin (such as CI).
for package in clhbid/agent-context mattpocock/skills; do
  echo "Installing $package for $AGENT..."
  npx -y skills add "$package" --global --yes --agent "$AGENT"
done
