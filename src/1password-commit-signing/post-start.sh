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
set -uo pipefail

SOCKET=/ssh-agent.sock

if [ -S "$SOCKET" ]; then
    target_group="vscode"
    if ! getent group "$target_group" >/dev/null 2>&1; then
        target_group="$(id -gn 2>/dev/null || echo root)"
    fi
    sudo chown "root:${target_group}" "$SOCKET" 2>/dev/null || true
    sudo chmod 660 "$SOCKET" 2>/dev/null || true
fi

program="$(git config --global --get gpg.ssh.program 2>/dev/null || true)"
if [ -n "$program" ] && ! command -v "$program" >/dev/null 2>&1 && [ ! -x "$program" ]; then
    git config --global --unset gpg.ssh.program || true
fi

exit 0
