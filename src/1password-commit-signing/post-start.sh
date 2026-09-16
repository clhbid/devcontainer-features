#!/usr/bin/env bash
# Runs on every container start (postStartCommand). Idempotent.
#
# 1. The consumer's devcontainer.json mounts the 1Password agent socket at
#    /ssh-agent.sock and points SSH_AUTH_SOCK at it through remoteEnv, so
#    that has to be a usable socket. Docker Desktop re-mounts it root:root
#    0660 on every start, which the non-root container user can't open.
#    Fix that up. If there is no socket there at all -- the mount is
#    missing, the 1Password agent is off, or this is a Linux/Windows host
#    where Docker turned the missing macOS path into an empty directory --
#    say so and fail: git cannot sign, and remoteEnv has displaced whatever
#    agent forwarding VS Code would otherwise have provided.
# 2. VS Code copies the host ~/.gitconfig into the container
#    (dev.containers.copyGitConfig). On macOS machines with the 1Password
#    SSH agent, that gitconfig sets gpg.ssh.program to the 1Password app's
#    op-ssh-sign binary, which does not exist in the container. It lands
#    in the container user's *global* gitconfig, so a --system value
#    would not override it (local > global > system). Unset it here so
#    git falls back to ssh-keygen, but leave a working program alone.
#
# Anything the Feature needs in order to sign commits is treated as
# required: if it cannot be done, this script explains what went wrong and
# what to do about it, and exits non-zero rather than leaving a container
# where every commit fails with an opaque git error.
set -uo pipefail

FEATURE="1password-commit-signing"
# The tests point this at a scratch path to exercise the missing-socket
# branches below; nothing else should set it.
SOCKET="${ONEPASSWORD_COMMIT_SIGNING_SOCKET:-/ssh-agent.sock}"
HOST_SOCKET='~/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock'

fail() {
    printf '%s: %s\n' "$FEATURE" "$1" >&2
    shift
    for line in "$@"; do
        printf '  %s\n' "$line" >&2
    done
    exit 1
}

# Run a command as root, without ever blocking on a sudo password prompt.
run_privileged() {
    if [ "$(id -u)" -eq 0 ]; then
        "$@"
    elif command -v sudo >/dev/null 2>&1; then
        sudo -n "$@"
    else
        return 1
    fi
}

socket_usable() {
    [ -r "$SOCKET" ] && [ -w "$SOCKET" ]
}

if command -v git >/dev/null 2>&1; then
    program="$(git config --global --get gpg.ssh.program 2>/dev/null || true)"
    if [ -n "$program" ] && ! command -v "$program" >/dev/null 2>&1; then
        if ! git config --global --unset gpg.ssh.program >/dev/null 2>&1; then
            fail "gpg.ssh.program is set to '$program', which does not exist in this container, and it could not be unset." \
                "What happened: VS Code copied your host ~/.gitconfig into the container, including the macOS 1Password signing helper. Git will fail every signed commit while it points at a missing program." \
                "Next steps:" \
                "- Run 'git config --global --unset gpg.ssh.program' in the container so git falls back to ssh-keygen." \
                "- If that fails, check that the global gitconfig (\${HOME}/.gitconfig) is writable by $(id -un)."
        fi
    fi
fi

if [ -d "$SOCKET" ]; then
    fail "$SOCKET is an empty directory, not the 1Password SSH agent socket, so git cannot sign commits." \
        "What happened: Docker bind-mounted the macOS socket path ($HOST_SOCKET) but nothing was there, so it created a directory instead. Either the 1Password SSH agent is not running on this Mac, or this is a Linux or Windows host, which this Feature does not support." \
        "Next steps:" \
        "- On macOS: open 1Password > Settings > Developer, turn on 'Use the SSH agent', then rebuild the container." \
        "- On Linux or Windows: remove this Feature, the $SOCKET mount and the SSH_AUTH_SOCK remoteEnv entry from devcontainer.json; they only displace the SSH agent VS Code forwards for you."
elif [ ! -e "$SOCKET" ]; then
    fail "$SOCKET does not exist, so git cannot sign commits." \
        "What happened: this Feature expects devcontainer.json to bind-mount the 1Password SSH agent socket ($HOST_SOCKET) at $SOCKET, and nothing is mounted there." \
        "Next steps:" \
        "- Add the mount and the remoteEnv entry to devcontainer.json (see the Feature's README for the Compose and image-based forms) and rebuild the container."
elif [ ! -S "$SOCKET" ]; then
    fail "$SOCKET exists but is not a socket, so git cannot sign commits." \
        "What happened: something other than the 1Password SSH agent socket ($HOST_SOCKET) is mounted at $SOCKET." \
        "Next steps:" \
        "- Check the $SOCKET mount in devcontainer.json points at the 1Password agent socket, then rebuild the container."
fi

if ! socket_usable; then
    target_group="vscode"
    if ! getent group "$target_group" >/dev/null 2>&1; then
        target_group="$(id -gn)"
    fi

    run_privileged chown "root:${target_group}" "$SOCKET" >/dev/null 2>&1
    run_privileged chmod 660 "$SOCKET" >/dev/null 2>&1

    if ! socket_usable; then
        fail "the forwarded 1Password SSH agent socket ($SOCKET) is not readable and writable by $(id -un), so git cannot sign commits." \
            "What happened: Docker re-mounts the socket owned by root on every container start, and this script could not change its ownership. That needs either root or passwordless sudo inside the container." \
            "Next steps:" \
            "- Check the socket with 'ls -l $SOCKET' and, if you have sudo, run 'sudo chown root:${target_group} $SOCKET && sudo chmod 660 $SOCKET'." \
            "- If the container user has no sudo access, set \"remoteUser\": \"root\" in devcontainer.json or use a base image that grants the user sudo, then rebuild the container."
    fi
fi

exit 0
