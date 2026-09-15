#!/usr/bin/env bash
# Runs on every container start (postStartCommand). Idempotent.
#
# 1. Docker Desktop's file-sharing layer re-mounts the forwarded 1Password
#    agent socket root:root 0660 on every start, which the non-root
#    container user can't open. Fix that up, but only if the socket was
#    actually forwarded -- on hosts without 1Password, the bind mount
#    target is an empty directory instead of a socket.
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
SOCKET=/ssh-agent.sock

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

if [ -S "$SOCKET" ]; then
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
fi

if command -v git >/dev/null 2>&1; then
    program="$(git config --global --get gpg.ssh.program 2>/dev/null || true)"
    if [ -n "$program" ] && ! command -v "$program" >/dev/null 2>&1 && [ ! -x "$program" ]; then
        if ! git config --global --unset gpg.ssh.program >/dev/null 2>&1; then
            fail "gpg.ssh.program is set to '$program', which does not exist in this container, and it could not be unset." \
                "What happened: VS Code copied your host ~/.gitconfig into the container, including the macOS 1Password signing helper. Git will fail every signed commit while it points at a missing program." \
                "Next steps:" \
                "- Run 'git config --global --unset gpg.ssh.program' in the container so git falls back to ssh-keygen." \
                "- If that fails, check that the global gitconfig (\${HOME}/.gitconfig) is writable by $(id -un)."
        fi
    fi
fi

exit 0
