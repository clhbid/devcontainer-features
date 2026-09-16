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

# Can ssh-keygen produce SSH signatures (OpenSSH 8.9 or newer)? Try it
# rather than parsing a version string, since distros backport features.
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
  What happened: 'ssh-keygen -Y sign' (OpenSSH 8.9 or newer) is unavailable, and this Feature only
  knows how to install openssh-client with apt-get, which this image does not have.
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
  What happened: the installed OpenSSH client is older than 8.9, the first release that supports
  SSH signatures.
  Next steps:
  - Use a newer base image, such as mcr.microsoft.com/devcontainers/base:ubuntu.
  - Or install a backported openssh-client (8.9 or newer) in your Dockerfile before this Feature runs.
EOF
fi

install -D -m 755 "$(dirname "$0")/post-start.sh" /usr/local/share/$FEATURE/post-start.sh

# VS Code gets SSH_AUTH_SOCK from the consumer's remoteEnv, the only setting
# it applies on top of its own SSH agent forwarding. This profile script
# covers everything else -- `devcontainer exec`, `docker exec` login shells,
# other editors -- and only sets the variable when the socket is really
# there, so a shell on a host without it keeps whatever agent it had.
cat > /etc/profile.d/$FEATURE.sh <<'EOF'
if [ -S /ssh-agent.sock ]; then
    export SSH_AUTH_SOCK=/ssh-agent.sock
fi
EOF

echo "Done!"
