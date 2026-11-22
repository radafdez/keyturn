# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Fixed
- A new login made with `supabase login`, of an account not registered yet,
  could be thrown away by an agent's `use_project` before you captured it.
  Keyturn now never switches over such a login: agents and `keyturn use` get
  an error asking you to capture it first, and choosing an account in the menu
  captures it before switching. If nothing can be saved, nothing changes.

### Added
- A notification when the CLI is on a login waiting to be captured, so the
  warning no longer lives only in the menu.
- If a login waiting to be captured is replaced anyway (say, another
  `supabase login` in a terminal), Keyturn says so: a notification, a banner in
  the menu, a line in `keyturn list` / `keyturn current`, and a note in the
  agents' `current_account`, telling you to log in with it again and capture it.

## [1.5.0] - 2026-11-21

### Added
- **Running CLIs**, a feature apart from the accounts: Keyturn watches which
  command-line tools run on this Mac — Supabase, Claude Code, Codex, Gemini,
  Vercel, GitHub, Stripe, Firebase, Wrangler and more, plus commands you add —
  and for how long. The menu lists what runs now; Settings → Running CLIs adds
  the time per tool (today, 7 or 30 days) and the latest sessions, each with
  the app it ran in and the tool that launched it. It reads the process table
  every 5 seconds, never touches the tools, and keeps only the tool, the app
  and the times, on this Mac. On by default; it turns off in the same pane.
- `keyturn clis [--json]`: what runs now, and today's time per tool.

## [1.4.0] - 2026-11-16

### Changed
- A new name: **Keyturn**. The command is now `keyturn`, the cask
  `radafdez/tap/keyturn`, and the repository `radafdez/keyturn`. It is a clean
  break: accounts live under the new name in the Keychain and in a new data
  folder, so add them again, and reconnect the AI agents from Settings.
- A new icon: two arrows going round a bolt, on a charcoal tile. The menu bar
  shows the same symbol in place of the plain bolt, black or white to match the
  bar.

### Added
- `brand/`: the symbol as SVG (logos, app icons, favicons, one-colour
  versions), for anyone writing about the app.

### Fixed
- `scripts/try-update.sh` turned the signed-feed checks off in its test copies,
  so its "edited feed" step proved nothing. It now keeps them on and checks
  they are on. The released app always had them on.

## [1.3.2] - 2026-11-16

### Fixed

- 1.3.1 said a copy installed with Homebrew lifts the quarantine from its own
  files once opened. It cannot: macOS does not let a quarantined app remove the
  mark, so `keyturn` and the MCP server stayed blocked. Now Settings → AI
  Agents says so and gives the Terminal command that removes it, and the
  README and the cask explain it after `brew install`.

## [1.3.1] - 2026-11-16

### Added

- Install with Homebrew: `brew install --cask radafdez/tap/keyturn`.
  It also links `keyturn`.

### Changed

- Copies installed with Homebrew update themselves too, like the ones from the
  zip. `brew upgrade` leaves them alone, so macOS does not block the app again
  after every upgrade.
- Once you have opened it, a copy installed with Homebrew lifts the quarantine
  from its own files. Without that, macOS would stop `keyturn` and the MCP
  server without asking, even after you approved the app.

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

- `keyturn mcp`: a Model Context Protocol server, so AI agents (Claude Code,
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
- `KEYTURN_DEMO=1` (made-up accounts in memory) and
  `KEYTURN_SNAPSHOTS=<folder>` (draws the screenshots).

### Changed

- The menu footer has a settings button in place of the version number.
- Counts read “1 run” instead of “1 runs”.
- The copyright holder is Radames Fernandez (LICENSE, the app and About).

## [1.1.1] - 2026-11-15

### Fixed

- The app and `keyturn` are universal binaries: they now run on Intel Macs
  too (1.1.0 was Apple Silicon only).
- `scripts/test.sh` runs the tests on Macs with Xcode installed.

## [1.1.0] - 2026-11-15

First public release.

### Added

- Rename an account right in its row, or from its right-click menu.
- Local aliases for projects, kept when the projects are read again;
  `keyturn alias`. Accounts can be found by a project's alias.
- Basic statistics: switches and `keyturn run` commands per account, this
  week, and last use; in the menu and with `keyturn stats`.
- English interface, chosen from the system language (Spanish stays available).
- `keyturn version`.

### Changed

- The copy-ref button is an icon, so the whole ref stays visible.
- Dates in the state file are stored as ISO 8601 text.

## [1.0.0] - 2026-11-15

- Menu bar app and `keyturn`: register accounts by capturing the CLI's login or
  from an access token, switch with one click, copy project refs, run one
  command as another account.
