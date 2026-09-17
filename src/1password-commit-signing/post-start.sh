#!/usr/bin/env bash
# Runs on every container start (postStartCommand). Safe to run repeatedly.
#
# The consumer's devcontainer.json mounts the 1Password agent socket at
# /ssh-agent.sock and points SSH_AUTH_SOCK at it with remoteEnv. This
# script then:
#
# 1. Unsets a gpg.ssh.program in the global gitconfig that does not exist in
#    the container. Tools that copy the host ~/.gitconfig bring across the
#    macOS 1Password signing helper, and git needs to fall back to ssh-keygen.
# 2. Makes the socket readable and writable by the container user. Docker
#    Desktop re-mounts it root:root 0660 on every start.
# 3. Checks SSH_AUTH_SOCK points at the socket. Lifecycle hooks run with
#    remoteEnv applied, and nothing else in the container sets the variable
#    to this path, so seeing it here means the consumer's remoteEnv is in
#    place -- and VS Code's terminals and Source Control will see it too.
#
# All three are required for signing to work, so when any cannot be done
# the script says what happened and what to do next, then exits non-zero.
# It does not use `set -e`: every failure it cares about is checked
# explicitly so that it can explain itself.
set -u

FEATURE=1password-commit-signing
HOST_SOCKET='~/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock'
README=https://github.com/clhbid/devcontainer-features/tree/main/src/$FEATURE
# The tests point this at scratch paths to exercise the failure branches.
SOCKET="${ONEPASSWORD_COMMIT_SIGNING_SOCKET:-/ssh-agent.sock}"

# Print a multi-line error message from stdin and exit non-zero.
fail() {
    cat >&2
    exit 1
}

# Run a command as root. `sudo -n` fails instead of prompting for a password.
as_root() {
    if [ "$(id -u)" -eq 0 ]; then "$@"; else sudo -n "$@"; fi
}

# --- 1. gitconfig

# --type=path expands a leading ~ the way git itself does when it runs the program.
program="$(git config --global --type=path --get gpg.ssh.program 2>/dev/null)"
if [ -n "$program" ] && ! command -v "$program" >/dev/null; then
    if ! git config --global --unset gpg.ssh.program; then
        fail <<EOF
$FEATURE: gpg.ssh.program is set to '$program', which does not exist in this container, and it could not be unset.
  What happened: your host ~/.gitconfig was copied into the container, including the macOS
  1Password signing helper. Git will fail every signed commit while it points at a missing program.
  Next steps:
  - Run 'git config --global --unset gpg.ssh.program' in the container so git falls back to ssh-keygen.
  - If that fails, check that ~/.gitconfig in the container is writable by $(id -un).
EOF
    fi
fi

# --- 2. socket

if [ -d "$SOCKET" ]; then
    fail <<EOF
$FEATURE: $SOCKET is an empty directory, not the 1Password SSH agent socket, so git cannot sign commits.
  What happened: Docker bind-mounted the macOS socket path ($HOST_SOCKET) but nothing was there,
  so it created a directory instead. Either the 1Password SSH agent is not running on this Mac,
  or this is a Linux or Windows host, which this Feature does not support.
  Next steps:
  - On macOS: open 1Password > Settings > Developer, turn on 'Use the SSH agent', then rebuild
    the container.
  - On Linux or Windows: remove this Feature, the $SOCKET mount and the SSH_AUTH_SOCK remoteEnv
    entry from devcontainer.json; they only displace the SSH agent VS Code forwards for you.
EOF
fi

if [ ! -S "$SOCKET" ]; then
    fail <<EOF
$FEATURE: there is no socket at $SOCKET, so git cannot sign commits.
  What happened: this Feature expects devcontainer.json to bind-mount the 1Password SSH agent
  socket ($HOST_SOCKET) at $SOCKET, and nothing is mounted there.
  Next steps:
  - Add the mount and the remoteEnv entry to devcontainer.json and rebuild the container.
    The Compose and image-based forms are in $README
EOF
fi

if [ ! -r "$SOCKET" ] || [ ! -w "$SOCKET" ]; then
    group="$(id -gn)"
    as_root chown "root:$group" "$SOCKET" 2>/dev/null
    as_root chmod 660 "$SOCKET" 2>/dev/null
fi

if [ ! -r "$SOCKET" ] || [ ! -w "$SOCKET" ]; then
    fail <<EOF
$FEATURE: the 1Password SSH agent socket ($SOCKET) is not readable and writable by $(id -un), so git cannot sign commits.
  What happened: Docker re-mounts the socket owned by root on every container start, and this
  script could not change its ownership. That needs root or passwordless sudo inside the container.
  Next steps:
  - Check the socket with 'ls -l $SOCKET' and, if you have sudo, run
    'sudo chown root:$(id -gn) $SOCKET && sudo chmod 660 $SOCKET'.
  - If the container user has no sudo access, set "remoteUser": "root" in devcontainer.json or
    use a base image that grants the user sudo, then rebuild the container.
EOF
fi

# --- 3. SSH_AUTH_SOCK

if [ "${SSH_AUTH_SOCK:-}" != "$SOCKET" ]; then
    fail <<EOF
$FEATURE: SSH_AUTH_SOCK is ${SSH_AUTH_SOCK:-unset}, not $SOCKET, so git will not find the 1Password agent.
  What happened: devcontainer.json does not set "remoteEnv": { "SSH_AUTH_SOCK": "$SOCKET" }.
  Without it VS Code points git at the SSH agent it forwards from the host, which does not hold
  your 1Password keys, and commits fail with "Couldn't find key in agent?".
  Next steps:
  - Add "remoteEnv": { "SSH_AUTH_SOCK": "$SOCKET" } to devcontainer.json and rebuild the container.
    See $README
EOF
fi
