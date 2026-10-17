# Shared iOS development routine in KotatsuCore

Adopted from [qtmleap/devcontainers](https://github.com/qtmleap/devcontainers/tree/0ffa75dec05570817c499452ac6faf1c3413006c)
at `0ffa75dec05570817c499452ac6faf1c3413006c`. The four files under `.agents/skills/ios-development/` are copied
without modification. Future refreshes compare that directory and merge the
marked `development-orchestration` block in root `AGENTS.md`, preserving local
rules. Adoption does not install tools or grant additional release authority.

## Repository scope

SwiftPM library supporting iOS, tvOS and macOS, defined by `Package.swift`. Use package conventions and affected consumer contracts; do not create an Xcode project to follow an app example.

There are no checked-in GitHub Actions workflows at the adoption base. Do not delegate required tests to nonexistent CI. Discover suitable Apple tooling/destinations for affected SwiftPM tests and consumer integration.

Package changes follow library versioning and consumer compatibility rules. TestFlight, screenshots and App Review apply only when working on an authorized consuming app release, not an ordinary library PR.

## Applying the routine

- Root `AGENTS.md` holds the common parallel-work, review/session, Tailscale,
  UI and ASC policy. `CLAUDE.md` imports it for Claude Code.
- Use [the native skill](../../.agents/skills/ios-development/SKILL.md) for its
  applicable native app scope; read its testing and release references when
  relevant. The repository scope above takes precedence over generic app
  examples. Apply checks to supported targets rather than inventing platforms.
- Keep the repository's existing mandatory gates and release route. The common
  internal-feature/external-RC timing defaults apply only where no stricter
  project policy exists.
- For documentation-only PRs, verify content, links, copied-file hashes and
  mandatory Git hooks. Native app binaries and simulator state are unchanged;
  this is no claim of native test success or release readiness. Let required CI
  run on the PR source rather than duplicating its unchanged full suites locally.
- Follow the library release process above when changing versions or publishing
  packages. This rollout opens a documentation PR; package publication and
  consuming-app release timing remain with their respective release processes.
- An App Review monitor is established by a future authorized submission flow
  according to the copied follow-up reference. No monitor is installed merely
  by adopting these instructions.

## UI screenshots and OS coverage

Apply the [visual testing policy](../../.agents/skills/ios-development/references/testing-policy.md)
for retained captures, matching references and baseline review on every selected
UI-test run.

Pure library logic tests need no screenshots. When affected consumer UI is tested, use that app's actual platform/minimum OS; do not lower this library's declared iOS 26 minimum to manufacture an 18 cell.

## Remote screenshot sharing

When a demo or consuming app UI is captured remotely, follow the
[sharing workflow](../../.agents/skills/ios-development/references/testing-policy.md#sharing-remote-screenshots).
Return actual tailnet image/viewer links, including baseline/current/diff when
comparing, and report client reachability and viewer expiry separately from
visual-test outcomes. Existing platform, release and access-control rules remain
in force. This adoption starts no viewer and claims no live URL.
