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
[1Password SSH agent](https://developer.1password.com/docs/ssh/agent) enabled**. It forwards the
1Password agent socket from its macOS path
(`~/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock`) into the container.

Windows and Linux hosts are not supported. On Docker Engine, enabling this Feature without that
macOS path available on the host fails container creation before any in-container guard can run, so
only enable it on macOS hosts that provide the 1Password socket path. Pull requests adding Windows
and Linux support are welcome.

## Layout

Standard Features layout, so the `devcontainers/action` publisher can find everything:

```
src/<feature-id>/devcontainer-feature.json
src/<feature-id>/install.sh
test/<feature-id>/test.sh
```

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
