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
open "dist/Supabase Switch.app"
```

Tests must pass without touching the real Keychain or the real CLI: use the
fakes in `Tests/SwitchCoreTests/Fakes.swift`. The one test that touches the
real Keychain (in its own service only) runs with `SBSWITCH_LIVE_KEYCHAIN=1`.

**Never test `supabase login` with a fake token on your machine**: it replaces
your real CLI login.

## Guidelines

- Logic goes in `SwitchCore`, behind the `SecretStore`, `SupabaseCLI` and
  `StateStore` protocols, with a test. The app and `sbswitch` stay thin.
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
it — for UI changes, a screenshot helps.

By contributing you agree that your work is released under the
[MIT License](LICENSE), and to follow the [Code of Conduct](CODE_OF_CONDUCT.md).
