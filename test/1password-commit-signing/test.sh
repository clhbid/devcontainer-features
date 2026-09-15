#!/bin/bash

# This test file will be executed against an auto-generated devcontainer.json that
# includes the 1password-commit-signing Feature with no options.
#
# CI has no 1Password socket, so these tests only cover the container-side
# behaviour: openssh-client is present, the postStartCommand script is
# installed and idempotent, and the socket-absent path is a no-op that
# never points SSH_AUTH_SOCK at a non-socket.

set -e

# Import test library bundled with the devcontainer CLI
source dev-container-features-test-lib

POST_START=/usr/local/share/1password-commit-signing/post-start.sh

check "openssh-client is installed" bash -c 'command -v ssh-keygen'

check "post-start.sh was installed and is executable" bash -c "test -x $POST_START"

check "SSH_AUTH_SOCK env probe script was installed" bash -c 'test -f /etc/profile.d/1password-commit-signing.sh'

check "no 1Password socket in CI: /ssh-agent.sock is absent or not a socket" bash -c '[ ! -S /ssh-agent.sock ]'

check "postStartCommand runs cleanly with no socket present" bash -c "$POST_START"

check "postStartCommand is idempotent when run twice" bash -c "$POST_START && $POST_START"

check "SSH_AUTH_SOCK is not exported when there is no socket" bash -c '. /etc/profile.d/1password-commit-signing.sh; [ -z "${SSH_AUTH_SOCK:-}" ]'

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

# Report result
reportResults
