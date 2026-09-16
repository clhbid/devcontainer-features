#!/bin/bash

# Shared checks for every scenario in scenarios.json. Each scenario is the
# documented consumer config: a host-side ssh-agent socket mounted at
# /ssh-agent.sock with `-v` -- the form Docker Desktop for Mac accepts for
# sockets -- and remoteEnv pointing SSH_AUTH_SOCK at it, so the permission
# fix, the env plumbing and agent-backed signing run for real. Use
# scripts/test-features.sh to start that agent and run the scenarios.
#
# The socket-missing branches of post-start.sh are covered by pointing it at
# a scratch path through ONEPASSWORD_COMMIT_SIGNING_SOCKET.

set -e

# Import test library bundled with the devcontainer CLI
source dev-container-features-test-lib

POST_START=/usr/local/share/1password-commit-signing/post-start.sh
PROFILE=/etc/profile.d/1password-commit-signing.sh
SOCKET=/ssh-agent.sock

# Assert that post-start.sh exits non-zero and prints next steps.
fails_with_next_steps() {
    local output status
    output="$($POST_START 2>&1)" && status=0 || status=$?
    [ "$status" -ne 0 ] && printf '%s' "$output" | grep -q 'Next steps'
}
export -f fails_with_next_steps
export POST_START

# --- Build-time install

check "openssh-client is installed" bash -c 'command -v ssh-keygen'

check "ssh-keygen supports SSH signing" bash -c '
    workdir="$(mktemp -d)"
    trap "rm -rf \"$workdir\"" EXIT
    printf "probe" > "$workdir/payload"
    ssh-keygen -q -t ed25519 -N "" -f "$workdir/probe" >/dev/null 2>&1
    ssh-keygen -Y sign -n git -f "$workdir/probe" "$workdir/payload" >/dev/null 2>&1
    test -f "$workdir/payload.sig"
'

check "post-start.sh was installed and is executable" bash -c "test -x $POST_START"

check "SSH_AUTH_SOCK profile script was installed" bash -c "test -f $PROFILE"

# --- The forwarded socket (postStartCommand has already run once at start-up)

check "the scenario mounted a socket at $SOCKET" bash -c "[ -S $SOCKET ]"

check "postStartCommand made the socket usable by the container user" bash -c "[ -r $SOCKET ] && [ -w $SOCKET ]"

check "postStartCommand is idempotent when run twice" bash -c "$POST_START && $POST_START"

check "the consumer remoteEnv points SSH_AUTH_SOCK at the socket" bash -c "[ \"\${SSH_AUTH_SOCK:-}\" = $SOCKET ]"

check "profile script exports SSH_AUTH_SOCK when the socket is present" bash -c "unset SSH_AUTH_SOCK; . $PROFILE; [ \"\${SSH_AUTH_SOCK:-}\" = $SOCKET ]"

check "the forwarded agent answers and holds a key" bash -c "SSH_AUTH_SOCK=$SOCKET ssh-add -l"

check "an agent-held key signs through the forwarded socket" bash -c "
    workdir=\"\$(mktemp -d)\"
    trap 'rm -rf \"\$workdir\"' EXIT
    export SSH_AUTH_SOCK=$SOCKET
    ssh-add -L | head -1 > \"\$workdir/key.pub\"
    printf 'probe' > \"\$workdir/payload\"
    ssh-keygen -Y sign -n git -f \"\$workdir/key.pub\" \"\$workdir/payload\"
    test -f \"\$workdir/payload.sig\"
"

# --- No usable socket: SSH_AUTH_SOCK already points at it, so this must be loud

check "postStartCommand fails with next steps when the socket is missing" bash -c '
    export ONEPASSWORD_COMMIT_SIGNING_SOCKET="$(mktemp -d)/absent.sock"
    fails_with_next_steps
'

check "postStartCommand fails with next steps when the mount is an empty directory" bash -c '
    export ONEPASSWORD_COMMIT_SIGNING_SOCKET="$(mktemp -d)"
    fails_with_next_steps
'

check "profile script leaves SSH_AUTH_SOCK alone when there is no socket" bash -c "
    SSH_AUTH_SOCK=/tmp/existing.sock; export SSH_AUTH_SOCK
    sed 's#/ssh-agent.sock#/nonexistent.sock#g' $PROFILE > /tmp/profile-no-socket.sh
    . /tmp/profile-no-socket.sh
    [ \"\$SSH_AUTH_SOCK\" = /tmp/existing.sock ]
"

# --- gitconfig normalisation

check "a working gpg.ssh.program is left alone" bash -c "
    git config --global gpg.ssh.program /usr/bin/ssh-keygen
    $POST_START
    [ \"\$(git config --global --get gpg.ssh.program)\" = /usr/bin/ssh-keygen ]
"

check "a non-existent gpg.ssh.program is unset" bash -c "
    git config --global gpg.ssh.program /Applications/1Password.app/Contents/MacOS/op-ssh-sign
    $POST_START
    ! git config --global --get gpg.ssh.program
"

check "an un-unsettable gpg.ssh.program fails with an explanation and next steps" bash -c "
    if [ \"\$(id -u)\" -eq 0 ]; then
        echo 'skipped: running as root, which can always write the gitconfig'
        exit 0
    fi
    workdir=\"\$(mktemp -d)\"
    export GIT_CONFIG_GLOBAL=\"\$workdir/gitconfig\"
    git config --global gpg.ssh.program /nonexistent/op-ssh-sign
    chmod 500 \"\$workdir\"
    trap 'chmod 700 \"\$workdir\"' EXIT
    fails_with_next_steps
"

# Report result
reportResults
