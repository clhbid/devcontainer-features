#!/bin/bash

# This test file will be executed against an auto-generated devcontainer.json that
# includes the 1password-commit-signing Feature with no options.
#
# CI has no 1Password socket, so these tests only cover the container-side
# behaviour: ssh-keygen supports SSH signing, the postStartCommand script is
# installed and idempotent, and the socket-absent path never points
# SSH_AUTH_SOCK at a non-socket or overwrites an existing forwarded agent.

set -e

# Import test library bundled with the devcontainer CLI
source dev-container-features-test-lib

POST_START=/usr/local/share/1password-commit-signing/post-start.sh

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

check "SSH_AUTH_SOCK env probe script was installed" bash -c 'test -f /etc/profile.d/1password-commit-signing.sh'

check "no 1Password socket in CI: /ssh-agent.sock is absent or not a socket" bash -c '[ ! -S /ssh-agent.sock ]'

check "postStartCommand runs cleanly with no socket present" bash -c "$POST_START"

check "postStartCommand is idempotent when run twice" bash -c "$POST_START && $POST_START"

check "SSH_AUTH_SOCK stays unset when there is no socket" bash -c 'unset SSH_AUTH_SOCK; . /etc/profile.d/1password-commit-signing.sh; [ -z "${SSH_AUTH_SOCK:-}" ]'

check "existing SSH_AUTH_SOCK is preserved when there is no socket" bash -c 'SSH_AUTH_SOCK=/tmp/existing.sock; export SSH_AUTH_SOCK; . /etc/profile.d/1password-commit-signing.sh; [ "$SSH_AUTH_SOCK" = /tmp/existing.sock ]'

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
    output=\"\$($POST_START 2>&1)\"
    status=\$?
    chmod 700 \"\$workdir\"
    [ \"\$status\" -ne 0 ]
    printf '%s' \"\$output\" | grep -q 'Next steps'
"

# Report result
reportResults
