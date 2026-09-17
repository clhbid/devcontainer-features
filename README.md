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
`devcontainer.json` mounts the agent socket and sets `remoteEnv`; the
[Feature's README](src/1password-commit-signing/README.md) has the lines and the reasons.

Windows and Linux hosts are not supported: the Feature's start-up script fails there with an
explanation rather than silently displacing VS Code's own agent forwarding. Pull requests adding
support are welcome.

## Layout

Standard Features layout, so the `devcontainers/action` publisher can find everything:

```
src/<feature-id>/devcontainer-feature.json
src/<feature-id>/install.sh
test/<feature-id>/scenarios.json
test/<feature-id>/<scenario>.sh      # one per scenario; may share a checks.sh
```

`./scripts/test-features.sh [scenario-filter]` runs the tests locally and in CI; it wraps
`devcontainer features test` with the host-side SSH agent the scenarios need.

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
