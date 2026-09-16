#!/bin/bash
# Shared checks for every scenario in scenarios.json. Each scenario is the
# documented consumer config -- a host ssh-agent socket mounted at
# /ssh-agent.sock with `-v`, and remoteEnv pointing SSH_AUTH_SOCK at it --
# so the permission fix, the env plumbing and agent-backed signing all run
# for real. scripts/test-features.sh starts that agent and runs the scenarios.
set -e

# Import test library bundled with the devcontainer CLI
source dev-container-features-test-lib

POST_START=/usr/local/share/1password-commit-signing/post-start.sh
PROFILE=/etc/profile.d/1password-commit-signing.sh
SOCKET=/ssh-agent.sock

# `check "label" command...` runs the command in this shell and records the
# result. The checks below are functions with ( subshell ) bodies, so
# anything they set, export or cd into is discarded when they return.

ssh_keygen_can_sign() (
    cd "$(mktemp -d)"
    printf 'probe' > payload
    ssh-keygen -q -t ed25519 -N '' -f key
    ssh-keygen -Y sign -n git -f key payload
    test -f payload.sig
)

agent_key_signs_through_socket() (
    export SSH_AUTH_SOCK=$SOCKET
    cd "$(mktemp -d)"
    ssh-add -L > key.pub
    printf 'probe' > payload
    ssh-keygen -Y sign -n git -f key.pub payload
    test -f payload.sig
)

profile_sets_ssh_auth_sock() (
    unset SSH_AUTH_SOCK
    . $PROFILE
    test "${SSH_AUTH_SOCK:-}" = $SOCKET
)

# The socket is really there in this container, so run a copy of the
# profile script that looks for it somewhere it isn't.
profile_keeps_existing_ssh_auth_sock_without_socket() (
    export SSH_AUTH_SOCK=/tmp/existing.sock
    sed "s#$SOCKET#/nonexistent.sock#" $PROFILE > /tmp/profile-without-socket.sh
    . /tmp/profile-without-socket.sh
    test "$SSH_AUTH_SOCK" = /tmp/existing.sock
)

# post-start.sh must exit non-zero and tell the user what to do.
post_start_fails_with_next_steps() (
    if output="$($POST_START 2>&1)"; then
        echo "post-start.sh succeeded but should have failed"
        return 1
    fi
    grep -q 'Next steps' <<< "$output"
)

post_start_fails_without_socket() (
    export ONEPASSWORD_COMMIT_SIGNING_SOCKET="$(mktemp -d)/absent.sock"
    post_start_fails_with_next_steps
)

post_start_fails_when_mount_is_a_directory() (
    export ONEPASSWORD_COMMIT_SIGNING_SOCKET="$(mktemp -d)"
    post_start_fails_with_next_steps
)

working_gpg_program_is_kept() (
    git config --global gpg.ssh.program /usr/bin/ssh-keygen
    $POST_START
    test "$(git config --global --get gpg.ssh.program)" = /usr/bin/ssh-keygen
)

missing_gpg_program_is_unset() (
    git config --global gpg.ssh.program /Applications/1Password.app/Contents/MacOS/op-ssh-sign
    $POST_START
    ! git config --global --get gpg.ssh.program
)

unwritable_gitconfig_fails_with_next_steps() (
    if [ "$(id -u)" -eq 0 ]; then
        echo "skipped: root can always write the gitconfig"
        return 0
    fi
    dir="$(mktemp -d)"
    export GIT_CONFIG_GLOBAL="$dir/gitconfig"
    git config --global gpg.ssh.program /nonexistent/op-ssh-sign
    chmod 500 "$dir"   # git writes a new file next to the old one, so it needs the directory
    post_start_fails_with_next_steps
)

# --- Build-time install
check "openssh-client is installed"                                   command -v ssh-keygen
check "ssh-keygen can produce SSH signatures"                         ssh_keygen_can_sign
check "post-start.sh is installed and executable"                     test -x $POST_START
check "the profile script is installed"                               test -f $PROFILE

# --- The forwarded socket (postStartCommand has already run once at start-up)
check "the scenario mounted a socket at $SOCKET"                      test -S $SOCKET
check "postStartCommand made the socket usable by the container user" test -r $SOCKET -a -w $SOCKET
check "post-start.sh can run again"                                   $POST_START
check "remoteEnv points SSH_AUTH_SOCK at the socket"                  test "${SSH_AUTH_SOCK:-}" = $SOCKET
check "the profile script sets SSH_AUTH_SOCK"                         profile_sets_ssh_auth_sock
check "the forwarded agent answers and holds a key"                   env SSH_AUTH_SOCK=$SOCKET ssh-add -l
check "an agent-held key signs through the forwarded socket"          agent_key_signs_through_socket

# --- No usable socket: SSH_AUTH_SOCK already points at it, so this must be loud
check "post-start.sh fails with next steps without a socket"          post_start_fails_without_socket
check "post-start.sh fails with next steps when the mount is a directory" post_start_fails_when_mount_is_a_directory
check "the profile script keeps an existing SSH_AUTH_SOCK without a socket" profile_keeps_existing_ssh_auth_sock_without_socket

# --- gitconfig
check "a working gpg.ssh.program is kept"                             working_gpg_program_is_kept
check "a missing gpg.ssh.program is unset"                            missing_gpg_program_is_unset
check "an unwritable gitconfig fails with next steps"                 unwritable_gitconfig_fails_with_next_steps

# Report result
reportResults
