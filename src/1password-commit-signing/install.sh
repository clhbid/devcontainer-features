#!/usr/bin/env bash
# Installs the 1password-commit-signing dev container Feature.
#
# This script only runs once, at image build time. Everything that has to
# happen on every container start (fixing the forwarded socket's
# permissions, neutralising a copied host gitconfig) lives in
# post-start.sh, invoked via postStartCommand in devcontainer-feature.json.
set -euo pipefail

# ssh-keygen -Y sign/verify (used to sign commits with an agent-held SSH
# key) needs OpenSSH >= 8.9. Don't assume the base image already has it.
if ! command -v ssh-keygen >/dev/null 2>&1; then
    if command -v apt-get >/dev/null 2>&1; then
        apt-get update -y
        apt-get install -y --no-install-recommends openssh-client
        rm -rf /var/lib/apt/lists/*
    else
        echo "1password-commit-signing: no apt-get available and ssh-keygen is missing; skipping openssh-client install" >&2
    fi
fi

install_dir="/usr/local/share/1password-commit-signing"
mkdir -p "$install_dir"
cp -f "$(dirname "$0")/post-start.sh" "$install_dir/post-start.sh"
chmod 755 "$install_dir/post-start.sh"

# Only export SSH_AUTH_SOCK when the forwarded path is an actual socket.
# On hosts without the 1Password agent, Docker Desktop's bind mount of a
# missing source creates an empty *directory* at /ssh-agent.sock instead;
# pointing SSH_AUTH_SOCK at that would break whatever agent forwarding VS
# Code already set up. /etc/profile.d runs through the default
# userEnvProbe (loginInteractiveShell), so this reaches the VS Code server
# and its terminals without ever being set unconditionally.
cat > /etc/profile.d/1password-commit-signing.sh <<'EOF'
if [ -S /ssh-agent.sock ]; then
    export SSH_AUTH_SOCK=/ssh-agent.sock
fi
EOF
chmod 644 /etc/profile.d/1password-commit-signing.sh

echo "Done!"
