# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/).

## [Unreleased]

## [1.3.0] - 2026-11-16

### Added

- The app updates itself through Sparkle: “Check for Updates…” in About,
  “Check Now” and “Check for updates automatically” in Settings → General.
  Sparkle asks once, on the second launch, whether to check on its own.
- A version found in the background waits in the menu (“Version … is ready to
  install”) instead of opening a window.
- Updates and the feed are signed with the project's EdDSA key; the app
  refuses a feed or a zip that does not match before unpacking it.
- `scripts/try-update.sh`: a real update on your Mac with a throwaway key, plus
  an edited feed and a swapped zip that must be refused.

### Changed

- Copies installed with Homebrew leave updates to Homebrew, and copies built
  from source point to the releases page.

## [1.2.0] - 2026-11-15

### Added

- `sbswitch mcp`: a Model Context Protocol server, so AI agents (Claude Code,
  Codex, Cursor, Claude Desktop…) can list the accounts and put the CLI on the
  one that owns a project. Four tools: `list_accounts`, `current_account`,
  `use_project` and `switch_account`. Agents never see a token.
- Every switch records who asked for it: the menu, a terminal, or an agent and
  its name.
- A settings window (⌘, from the menu) with a sidebar: General (language, open
  at login, the state file), Accounts, AI agents (allow or block agent
  switches, notifications, one-click setup for Claude Code and Codex, JSON for
  the rest), Activity, Statistics (per account, per source, per agent) and
  About (version, build, updates, links, license).
- A macOS notification when an agent switches the account (can be turned off).
- Switches made from a terminal or an agent show up in the app at once.
- Choose the language in Settings instead of following the system.
- An app icon.
- `SUPABASE_SWITCH_DEMO=1` (made-up accounts in memory) and
  `SUPABASE_SWITCH_SNAPSHOTS=<folder>` (draws the screenshots).

### Changed

- The menu footer has a settings button in place of the version number.
- Counts read “1 run” instead of “1 runs”.
- The copyright holder is Radames Fernandez (LICENSE, the app and About).

## [1.1.1] - 2026-11-15

### Fixed

- The app and `sbswitch` are universal binaries: they now run on Intel Macs
  too (1.1.0 was Apple Silicon only).
- `scripts/test.sh` runs the tests on Macs with Xcode installed.

## [1.1.0] - 2026-11-15

First public release.

### Added

- Rename an account right in its row, or from its right-click menu.
- Local aliases for projects, kept when the projects are read again;
  `sbswitch alias`. Accounts can be found by a project's alias.
- Basic statistics: switches and `sbswitch run` commands per account, this
  week, and last use; in the menu and with `sbswitch stats`.
- English interface, chosen from the system language (Spanish stays available).
- `sbswitch version`.

### Changed

- The copy-ref button is an icon, so the whole ref stays visible.
- Dates in the state file are stored as ISO 8601 text.

## [1.0.0] - 2026-11-15

- Menu bar app and `sbswitch`: register accounts by capturing the CLI's login or
  from an access token, switch with one click, copy project refs, run one
  command as another account.
