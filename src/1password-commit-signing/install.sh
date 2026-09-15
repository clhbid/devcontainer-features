#!/usr/bin/env bash
# Installs the 1password-commit-signing dev container Feature.
#
# This script only runs once, at image build time. Everything that has to
# happen on every container start (fixing the forwarded socket's
# permissions, neutralising a copied host gitconfig) lives in
# post-start.sh, invoked via postStartCommand in devcontainer-feature.json.
set -euo pipefail

# Probe the actual ssh-keygen -Y sign capability instead of parsing version
# strings: distros can backport the feature independently of the reported
# OpenSSH version, so exercise a scratch signing flow directly.
supports_ssh_signing() {
    if ! command -v ssh-keygen >/dev/null 2>&1; then
        return 1
    fi

    workdir="$(mktemp -d)"
    printf 'probe' > "$workdir/payload"

    if ssh-keygen -q -t ed25519 -N '' -f "$workdir/probe" >/dev/null 2>&1 &&
        ssh-keygen -Y sign -n git -f "$workdir/probe" "$workdir/payload" >/dev/null 2>&1; then
        rm -rf "$workdir"
        return 0
    fi

    rm -rf "$workdir"
    return 1
}

if ! supports_ssh_signing; then
    if command -v apt-get >/dev/null 2>&1; then
        apt-get update -y
        apt-get install -y --no-install-recommends openssh-client
        rm -rf /var/lib/apt/lists/*
    else
        echo "1password-commit-signing: ssh-keygen -Y sign is unavailable and no apt-get is present to install openssh-client" >&2
        exit 1
    fi
fi

if ! supports_ssh_signing; then
    echo "1password-commit-signing: ssh-keygen -Y sign is still unavailable after attempting to install openssh-client" >&2
    exit 1
fi

install_dir="/usr/local/share/1password-commit-signing"
mkdir -p "$install_dir"
cp -f "$(dirname "$0")/post-start.sh" "$install_dir/post-start.sh"
chmod 755 "$install_dir/post-start.sh"

# Only export SSH_AUTH_SOCK when the forwarded path is an actual socket.
# On supported macOS hosts without the 1Password agent running, Docker
# Desktop's bind mount of a missing source creates an empty *directory* at
# /ssh-agent.sock instead;
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
