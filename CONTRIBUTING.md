# Contributing

Thanks for helping. Bug reports, ideas and pull requests are all welcome.

## Before you start

- For anything bigger than a small fix, open an issue first so we can agree on
  the approach.
- Never paste a real access token in an issue, a test or a commit. Tests use
  fake tokens such as `"sbp_" + String(repeating: "a", count: 40)`.

## Building and testing

You need macOS 13+ and Swift 5.9+ (the Command Line Tools are enough).

```bash
./scripts/test.sh
./scripts/build-app.sh
open "dist/Keyturn.app"
```

Tests must pass without touching the real Keychain or the real CLI: use the
fakes in `Tests/SwitchCoreTests/Fakes.swift`. The one test that touches the
real Keychain (in its own service only) runs with `KEYTURN_LIVE_KEYCHAIN=1`.

**Never test `supabase login` with a fake token on your machine**: it replaces
your real CLI login.

## Guidelines

- Logic goes in `SwitchCore`, behind the `SecretStore`, `SupabaseCLI` and
  `StateStore` protocols, with a test. The app and `keyturn` stay thin.
- Every user-facing string goes through `tr("English", "Español")`. If you
  don't speak Spanish, write the English and leave the Spanish to review.
- In SwiftUI views use `@ViewState` / `@ViewFocus` instead of `@State` /
  `@FocusState` (see the README for why).
- Secrets travel through stdin or the environment, never through arguments.
- Old state files must keep opening: new fields are optional or decoded with a
  default.
- Add a line to `CHANGELOG.md` under “Unreleased”.

## Pull requests

Keep them focused, describe what changes for the user, and say how you tested
it — for UI changes, a screenshot helps. `KEYTURN_DEMO=1` runs the app
with made-up accounts, and `KEYTURN_SNAPSHOTS=<folder>` draws every
screen into PNGs (see the README); the pictures in `docs/` come from there, so
they never show real accounts.

Changes to `keyturn mcp` are tested in `Tests/SwitchCoreTests/MCPServerTests.swift`
by sending JSON-RPC lines to `MCPServer.handle(_:)`. A tool must never return a
token, and a switch must record its origin.

## Releases and the update key

A release is a tag (`v1.3.0`) that matches `switchVersion` and has a section
in `CHANGELOG.md`. The release workflow builds the app, signs the zip with the
EdDSA key in the `SPARKLE_PRIVATE_KEY` secret, writes and signs `appcast.xml`,
and refuses to publish if that signature does not match the public key in
`Resources/sparkle-public-key.txt`. The public key is in the repository; the
private one is only in the maintainer's Keychain and in that secret.

Changes to the updater are tested with `scripts/try-update.sh`, never against
the real feed.

By contributing you agree that your work is released under the
[MIT License](LICENSE), and to follow the [Code of Conduct](CODE_OF_CONDUCT.md).
