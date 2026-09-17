#!/usr/bin/env bash
# Installs the 1password-commit-signing dev container Feature.
#
# This runs once, at image build time. Everything that has to happen on
# every container start lives in post-start.sh, installed here and run
# through postStartCommand.
set -euo pipefail

FEATURE=1password-commit-signing

# Print a multi-line error message from stdin and stop the build.
fail() {
    cat >&2
    exit 1
}

# Can ssh-keygen produce SSH signatures? Try it rather than checking a
# version: distros backport features, and crypto policies can remove them.
supports_ssh_signing() {
    command -v ssh-keygen >/dev/null || return 1

    local workdir ok=1
    workdir="$(mktemp -d)"
    printf 'probe' > "$workdir/payload"
    if ssh-keygen -q -t ed25519 -N '' -f "$workdir/key" >/dev/null 2>&1 &&
        ssh-keygen -Y sign -n git -f "$workdir/key" "$workdir/payload" >/dev/null 2>&1; then
        ok=0
    fi
    rm -rf "$workdir"
    return "$ok"
}

if ! supports_ssh_signing; then
    if ! command -v apt-get >/dev/null; then
        fail <<EOF
$FEATURE: this image cannot sign commits with SSH, and openssh-client cannot be installed automatically.
  What happened: 'ssh-keygen -Y sign' is unavailable, and this Feature only knows how to install
  openssh-client with apt-get, which this image does not have.
  Next steps:
  - Install an OpenSSH client that supports 'ssh-keygen -Y sign' in your Dockerfile before this
    Feature runs.
  - Or switch to a Debian or Ubuntu based image, such as mcr.microsoft.com/devcontainers/base:ubuntu.
EOF
    fi
    apt-get update -y
    apt-get install -y --no-install-recommends openssh-client
    rm -rf /var/lib/apt/lists/*
fi

if ! supports_ssh_signing; then
    fail <<EOF
$FEATURE: openssh-client is installed but 'ssh-keygen -Y sign' does not work, so git cannot sign commits.
  What happened: this Feature generated a scratch ed25519 key and tried to sign a file with it,
  and ssh-keygen failed. Usually the OpenSSH client is too old to have 'ssh-keygen -Y sign';
  a system crypto policy that disables ed25519 fails the same way.
  Next steps:
  - Use a newer base image, such as mcr.microsoft.com/devcontainers/base:ubuntu.
  - Or install a newer openssh-client in your Dockerfile before this Feature runs.
  - Or check the image's crypto policy allows ed25519 keys.
EOF
fi

install -D -m 755 "$(dirname "$0")/post-start.sh" /usr/local/share/$FEATURE/post-start.sh

echo "Done!"
