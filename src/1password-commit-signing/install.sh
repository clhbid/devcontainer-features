#!/usr/bin/env bash
# Installs the 1password-commit-signing Feature at image build time.
# Per-start work lives in post-start.sh, installed here as postStartCommand.
set -euo pipefail

FEATURE=1password-commit-signing

# Print a multi-line error message from stdin and stop the build.
fail() {
    cat >&2
    exit 1
}

# Can ssh-keygen sign with a key held only by an agent? Try it rather than
# checking a version: distros backport features, and crypto policies can remove them.
supports_agent_ssh_signing() {
    command -v ssh-keygen >/dev/null || return 1

    local workdir ok=1
    workdir="$(mktemp -d)"
    printf 'probe' > "$workdir/payload"
    if ssh-keygen -q -t ed25519 -N '' -f "$workdir/key" >/dev/null 2>&1 &&
        ssh-agent sh -c '
            ssh-add "$1/key" >/dev/null 2>&1 &&
                rm "$1/key" &&
                ssh-keygen -Y sign -n git -f "$1/key.pub" "$1/payload"
        ' sh "$workdir" >/dev/null 2>&1; then
        ok=0
    fi
    rm -rf "$workdir"
    return "$ok"
}

if ! supports_agent_ssh_signing; then
    if ! command -v apt-get >/dev/null; then
        fail <<EOF
$FEATURE: this image cannot sign commits with an agent-held SSH key, and openssh-client cannot be installed automatically.
  What happened: ssh-keygen could not sign with a key held only by ssh-agent, and this Feature
  only knows how to install openssh-client with apt-get, which this image does not have.
  Next steps:
  - Install an OpenSSH client that supports signing with an agent-held key in your Dockerfile
    before this Feature runs.
  - Or switch to a Debian or Ubuntu based image, such as mcr.microsoft.com/devcontainers/base:ubuntu.
EOF
    fi
    apt-get update -y
    apt-get install -y --no-install-recommends openssh-client
    rm -rf /var/lib/apt/lists/*
fi

if ! supports_agent_ssh_signing; then
    fail <<EOF
$FEATURE: openssh-client is installed but cannot sign with an agent-held SSH key.
  What happened: this Feature loaded a scratch ed25519 key into ssh-agent, removed the private-key
  file, and ssh-keygen could not sign with the remaining public key. Usually the OpenSSH client
  lacks agent-backed SSH signing; a system crypto policy that disables ed25519 fails the same way.
  Next steps:
  - Use a newer base image, such as mcr.microsoft.com/devcontainers/base:ubuntu.
  - Or install a newer openssh-client in your Dockerfile before this Feature runs.
  - Or check the image's crypto policy allows ed25519 keys.
EOF
fi

install -D -m 755 "$(dirname "$0")/post-start.sh" /usr/local/share/$FEATURE/post-start.sh

echo "Done!"
