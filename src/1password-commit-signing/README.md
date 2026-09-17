# 1Password commit signing

Signs git commits inside a dev container with an SSH key held in 1Password on a **macOS host**.
The consumer's `devcontainer.json` mounts the 1Password agent socket and points `SSH_AUTH_SOCK`
at it; the Feature does everything inside the container.

## Usage

Add all three of: the Feature, `remoteEnv`, and the socket mount. Start-up fails naming
whichever is missing. The mount form depends on the kind of dev container.

Compose-based (`dockerComposeFile`):

```jsonc
{
  "mounts": [
    "source=${localEnv:HOME}/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock,target=/ssh-agent.sock,type=bind"
  ],
  "remoteEnv": { "SSH_AUTH_SOCK": "/ssh-agent.sock" },
  "features": { "ghcr.io/clhbid/devcontainer-features/1password-commit-signing:1": {} }
}
```

Image- or Dockerfile-based (`image` / `build`) — `runArgs`, **not** `mounts`:

```jsonc
{
  "runArgs": [
    "-v", "${localEnv:HOME}/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock:/ssh-agent.sock"
  ],
  "remoteEnv": { "SSH_AUTH_SOCK": "/ssh-agent.sock" },
  "features": { "ghcr.io/clhbid/devcontainer-features/1password-commit-signing:1": {} }
}
```

`user.signingkey`, `gpg.format` and `commit.gpgsign` come from the copied host gitconfig. A plain
`docker exec` shell does not get `remoteEnv`; set `SSH_AUTH_SOCK=/ssh-agent.sock` there yourself.

## What the Feature does

- **Build** (`install.sh`): installs `openssh-client` unless `ssh-keygen` can sign with a scratch
  key held only by `ssh-agent`. The capability is probed rather than inferred from the OpenSSH
  version. Fails the build with next steps if it still doesn't work.
- **Every start** (`post-start.sh`): unsets a copied `gpg.ssh.program` that doesn't exist in the
  container so git falls back to `ssh-keygen`; re-owns `/ssh-agent.sock` to the container user's
  group (Docker Desktop re-mounts it `root:root` each start); checks `SSH_AUTH_SOCK` is the
  socket. Any of those failing exits non-zero with what happened and next steps — a quiet no-op
  would leave every commit failing with an opaque git error.

## Why the consumer supplies the mount and `remoteEnv`

**The mount.** Docker Desktop for Mac only proxies host Unix sockets for the `-v` (`Binds`) form
of a bind mount; `--mount type=bind` (`Mounts`) of the same socket fails with
`bind source path does not exist: /socket_mnt/…`. The devcontainer CLI emits Feature `mounts`,
and `devcontainer.json` `mounts` in image-based containers, as `--mount`; Compose containers get
a volume entry instead, which becomes a Bind. So a Feature-owned mount would break every
image-based consumer, and `runArgs -v` is the working form there. Mounting the parent directory
is no workaround — `~/Library/Group Containers` is protected by macOS.

**`SSH_AUTH_SOCK`.** VS Code forwards the host's own SSH agent — Apple's, holding no keys; 1Password
is wired in via `IdentityAgent`, which VS Code doesn't see — and sets `SSH_AUTH_SOCK` for every
terminal and the Source Control view after `userEnvProbe`. That beats `profile.d`, the probed
env and a Feature `containerEnv`. Only `remoteEnv` is applied on top, and a Feature can't carry
`remoteEnv`. (Pointing the *host's* `SSH_AUTH_SOCK` at the 1Password socket with
`launchctl setenv` would let VS Code forward the right agent with no mount at all, but it is a
per-developer host step, which this Feature exists to avoid.)

## Platform support

macOS hosts with the [1Password SSH agent](https://developer.1password.com/docs/ssh/agent)
enabled. On Windows and Linux the mount yields an empty directory, `remoteEnv` points at it
regardless, and start-up fails telling the developer to remove the Feature, the mount and the
`remoteEnv` entry. It can't be a silent no-op: `remoteEnv` has already displaced VS Code's agent.

## Testing

`scripts/test-features.sh` starts a throwaway `ssh-agent` on the host and runs the scenarios in
`test/1password-commit-signing/scenarios.json` — the consumer config above with that agent's
socket — including signing with the agent-held key through it. `devcontainer features test`
alone can't run this Feature: with nothing mounted, start-up fails by design.
