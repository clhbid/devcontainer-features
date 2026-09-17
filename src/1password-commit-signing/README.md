# 1Password commit signing

Signs git commits inside a dev container with an SSH key held in 1Password on a **macOS host**.

The Feature does the container-side work; the consuming `devcontainer.json` supplies the socket
mount and the `SSH_AUTH_SOCK` entry. Both halves of that split are forced — see
[Why the consumer mounts the socket](#why-the-consumer-mounts-the-socket) and
[Why the consumer sets `remoteEnv`](#why-the-consumer-sets-remoteenv).

## What the Feature does

At build time (`install.sh`):

- Installs `openssh-client` if `ssh-keygen -Y sign` does not already work, and fails the build
  with next steps if it still doesn't. It probes by signing a scratch file rather than checking
  a version number, since distros backport features and crypto policies can remove them.
- Installs `post-start.sh`.

On every container start (`postStartCommand`):

- Unsets `gpg.ssh.program` in the container user's global gitconfig when it points at a program
  that doesn't exist in the container, so git falls back to `ssh-keygen`. A working program is
  left alone. (VS Code strips this key when it copies the host `~/.gitconfig`; other tools that
  copy the file don't, and on these machines it names
  `/Applications/1Password.app/Contents/MacOS/op-ssh-sign`.)
- Re-owns `/ssh-agent.sock` to `root:<container user's group> 660` — Docker Desktop re-mounts it
  `root:root` each start.
- Checks `SSH_AUTH_SOCK` is `/ssh-agent.sock`. Lifecycle hooks run with `remoteEnv` applied and
  nothing else in the container sets that value, so this is how the script knows the consumer's
  `remoteEnv` entry is in place.
- **Fails, with what happened and next steps**, if `/ssh-agent.sock` is missing, is an empty
  directory (the 1Password agent is off, or this is a Linux/Windows host), can't be made readable
  and writable, or `SSH_AUTH_SOCK` doesn't point at it. A quiet no-op would leave git failing
  with `Couldn't get agent socket?` or `Couldn't find key in agent?` and nothing to explain why.

`user.signingkey`, `gpg.format` and `commit.gpgsign` come from the copied host gitconfig; the
Feature does not set them.

VS Code and the devcontainer CLI both apply `remoteEnv` to terminals and `exec`. A plain
`docker exec` shell does not get it — set `SSH_AUTH_SOCK=/ssh-agent.sock` yourself there.

## Usage

Three additions to `devcontainer.json`, **all required**: the Feature, `remoteEnv`, and the
socket mount. Without the mount or `remoteEnv` the container's start-up fails with a message
saying which one is missing — see [Platform support](#platform-support) for why it isn't a
quiet no-op. **How you mount it depends on the kind of dev container.**

### Compose-based (`dockerComposeFile`)

```jsonc
{
  "dockerComposeFile": "docker-compose.yml",
  "service": "app",
  "mounts": [
    "source=${localEnv:HOME}/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock,target=/ssh-agent.sock,type=bind"
  ],
  "remoteEnv": {
    "SSH_AUTH_SOCK": "/ssh-agent.sock"
  },
  "features": {
    "ghcr.io/clhbid/devcontainer-features/1password-commit-signing:1": {}
  }
}
```

### Image- or Dockerfile-based (`image` / `build`)

```jsonc
{
  "image": "mcr.microsoft.com/devcontainers/base:bookworm",
  "runArgs": [
    "-v",
    "${localEnv:HOME}/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock:/ssh-agent.sock"
  ],
  "remoteEnv": {
    "SSH_AUTH_SOCK": "/ssh-agent.sock"
  },
  "features": {
    "ghcr.io/clhbid/devcontainer-features/1password-commit-signing:1": {}
  }
}
```

Do **not** use `mounts` for the socket in an image-based dev container — see below.

## Why the consumer mounts the socket

Docker Desktop for Mac forwards a host Unix socket into the VM through a socket proxy, and that
proxy is only wired up for the `-v` / `HostConfig.Binds` form of a bind mount. The `--mount
type=bind` / `HostConfig.Mounts` form of the *same* path fails at container creation:

```
invalid mount config for type "bind": bind source path does not exist:
/socket_mnt/Users/<you>/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock
```

The devcontainer CLI turns Feature `mounts` — and `devcontainer.json` `mounts` in an image-based
container — into `docker run --mount`, so a Feature cannot forward the socket itself without
breaking every image-based consumer on macOS. In a Compose-based container the CLI writes the
same mount into a Compose override as a short-syntax volume, which Compose sends as a Bind, so
`mounts` works there. `runArgs: ["-v", …]` is the equivalent for image-based containers.

Bind-mounting the socket's parent directory is not a workaround: `~/Library/Group Containers` is
protected by macOS and Docker Desktop cannot read it.

## Why the consumer sets `remoteEnv`

VS Code forwards the host's *own* SSH agent — whatever `SSH_AUTH_SOCK` is in the environment VS
Code was launched with — into every dev container as `/tmp/vscode-ssh-auth-<id>.sock`, and sets
`SSH_AUTH_SOCK` to that path for the Source Control view and every terminal. On a Mac that host
agent is Apple's launchd agent, which holds no keys: 1Password wires itself in through
`IdentityAgent` in `~/.ssh/config`, which VS Code doesn't see.

That override beats everything a Feature can do. The integrated terminal is an interactive
non-login shell, so an `/etc/profile.d` export never runs there; the override is applied after
`userEnvProbe`, so a probed export loses; and a Feature `containerEnv` is inherited by the VS Code
server and then overridden per terminal all the same. `git commit` fails with
`Couldn't find key in agent?` in each case. (An earlier version of this Feature shipped a guarded
`profile.d` export for non-VS Code shells. It went: the user-env probe fed it into lifecycle
hooks too, which made a missing `remoteEnv` undetectable from `post-start.sh`.) The one setting VS Code layers *on top of* its own
forwarding is `remoteEnv` — which the Feature spec doesn't allow a Feature to carry (the CLI keeps
only lifecycle hooks, `mounts`, `containerEnv`, `customizations` and a few container flags from
Feature metadata). So it lives in the consumer's `devcontainer.json`, and it can't be conditional.

The alternative is to make the *host's* `SSH_AUTH_SOCK` the 1Password socket (e.g.
`launchctl setenv SSH_AUTH_SOCK "$HOME/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"`
before launching VS Code). Then VS Code forwards the 1Password agent itself and no mount or
`remoteEnv` is needed at all — but it is a per-developer host setup step, which is what this
Feature exists to avoid.

## Platform support

macOS hosts with the [1Password SSH agent](https://developer.1password.com/docs/ssh/agent)
enabled. Windows and Linux hosts are not supported: the consumer's mount turns the missing macOS
path into an empty directory (both `-v` and Compose do this), the consumer's `remoteEnv` points
`SSH_AUTH_SOCK` at it regardless, and the start-up script fails with an explanation telling the
developer to remove the Feature, the mount and the `remoteEnv` entry. It cannot be a silent
no-op, because the `remoteEnv` entry would still have displaced the agent VS Code forwards.

## Testing

`../../scripts/test-features.sh` starts a throwaway `ssh-agent` on the host and runs the
scenarios in `../../test/1password-commit-signing/scenarios.json`, each of which is the consumer
config above with that agent's socket in place of the 1Password one. The checks include signing
with the agent-held key through the forwarded socket.

`devcontainer features test` on its own can't run this Feature: with no socket mounted, the
start-up script fails the container before any test runs, by design.
