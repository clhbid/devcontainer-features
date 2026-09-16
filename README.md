# CLHbid dev container Features

Shared [dev container Features](https://containers.dev/implementors/features/) used by CLHbid.com
repositories, published to GitHub Container Registry.

The repositories that consume these Features are `clhbid/CLHbid-LiveAuction`,
`clhbid/infrastructure` and `clhbid/clhbid.com`.

## Features

| Feature                    | ID                                                                | Status      |
| -------------------------- | ----------------------------------------------------------------- | ----------- |
| `1password-commit-signing` | `ghcr.io/clhbid/devcontainer-features/1password-commit-signing:1` | Built, awaiting first publish to GHCR |

## Platform support

`1password-commit-signing` works only on **macOS hosts with the
[1Password SSH agent](https://developer.1password.com/docs/ssh/agent) enabled**. The consuming
`devcontainer.json` mounts the 1Password agent socket
(`~/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock`) at `/ssh-agent.sock` and
points `SSH_AUTH_SOCK` at it with `remoteEnv`; the Feature does the rest. The exact lines — and
why the Feature can't carry them itself — are in the
[Feature's README](src/1password-commit-signing/README.md).

Windows and Linux hosts are not supported. That `remoteEnv` entry is unconditional — it is the only
setting VS Code applies on top of its own agent forwarding — so on a host without the 1Password
socket the container's SSH agent is a dead path, and the Feature's start-up script fails with an
explanation and next steps rather than leaving that silent. Pull requests adding Windows and Linux
support are welcome.

## Layout

Standard Features layout, so the `devcontainers/action` publisher can find everything:

```
src/<feature-id>/devcontainer-feature.json
src/<feature-id>/install.sh
test/<feature-id>/scenarios.json
test/<feature-id>/<scenario>.sh
```

Run the tests with `./scripts/test-features.sh` (optionally `./scripts/test-features.sh ubuntu` to
filter by scenario name). It wraps `devcontainer features test` and starts the throwaway SSH agent
the scenarios mount in place of the 1Password socket; the CI workflow runs the same script.

`src/` is the source of truth for the published OCI artifacts. A push to `main` that changes a
Feature's `version` publishes a new release; the version must be bumped in the same pull request
that changes the Feature.

## Why this repository is public

The Features are published to GHCR as public packages so that `devcontainer.json` in any of the
consuming repositories resolves them without a registry login on developer machines or in CI.
Nothing here is secret — the Features carry host socket paths and permission fixes, not credentials.

## Contributing

Issues are tracked in this repository's GitHub Issues, using the same triage labels as
`clhbid/clhbid.com` (`needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`).
