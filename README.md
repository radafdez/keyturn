# Supabase Switch

**Switch the account the Supabase CLI is logged in as — one click in the menu bar, no browser.**

[Español](README.es.md)

<img src="docs/menu-light.png" width="340" alt="The menu with three accounts, one of them in use"> <img src="docs/settings-agents.png" width="420" alt="Settings: letting AI agents switch the account, and connecting Claude Code and Codex">

The `supabase` CLI keeps a single login. If your projects live in several
Supabase accounts — one per client, personal and work, a shared org — every
change means `supabase logout`, `supabase login`, a browser tab and a code.
Supabase Switch keeps one access token per account in the macOS Keychain and
hands the right one to the CLI when you click.

- **One click** in the menu bar, or `sbswitch use acme` in a terminal.
- **Your AI agent switches for you**: Claude Code, Codex, Cursor and any other
  MCP client can call `use_project` before running `supabase`. Every switch is
  recorded with who asked for it, and you can turn it off. See
  [AI agents](#ai-agents-mcp).
- **Projects at hand**: each account lists its projects; copy a `ref` for
  `--project-ref` or `supabase link` without opening the dashboard.
- **Your names**: rename accounts, and give projects local aliases
  (`acme-production` → “Acme prod”). Supabase never sees them.
- **Activity and statistics**: every switch with who made it (you in the
  menu, a terminal, or which agent), and counts per account, per source and
  per agent. Kept on your Mac only.
- **One-off commands as another account** without switching:
  `sbswitch run globex -- supabase migration list`.
- **Notices logins made elsewhere**: a `supabase login` typed in a terminal
  shows up in the menu within 30 seconds.
- **Settings window** (⌘, from the menu): accounts, agents, activity,
  statistics, language and about.
- **Updates itself**: new versions install with one click, and only if they
  carry the project's signature. See [Updates](#updates).
- English and Spanish, following the system language or your choice.

## Requirements

- macOS 13 Ventura or later, on Apple Silicon or Intel.
- The [Supabase CLI](https://supabase.com/docs/guides/local-development/cli/getting-started)
  installed with Homebrew (`/opt/homebrew/bin` or `/usr/local/bin`) or anywhere
  on your login shell's `PATH`. Tested with CLI 2.114.
- To build: Swift 5.9 or later — the Xcode Command Line Tools are enough
  (`xcode-select --install`); Xcode works too.

## Install

### From source (recommended)

```bash
git clone https://github.com/radafdez/supabase-switch.git
cd supabase-switch
./scripts/build-app.sh --install
```

That builds the app, copies it to `/Applications`, links `sbswitch` next to
the Supabase CLI and opens it. A bolt appears in the menu bar.

### With Homebrew

```bash
brew install --cask radafdez/tap/supabase-switch
```

That installs the app in `/Applications` and links `sbswitch`. Naming the
tap in full trusts only this cask, not the rest of the tap. The app is **not
notarized**, so the first launch is blocked as with the zip below: open it
once and click **Open Anyway** in **System Settings → Privacy & Security**.
After that it updates itself, and `brew upgrade` leaves it alone. To remove
it, `brew uninstall --cask supabase-switch`; add `--zap` to delete your
accounts list and settings as well (the tokens stay in the Keychain).

### From a release

Download `Supabase-Switch-<version>.zip` from
[Releases](https://github.com/radafdez/supabase-switch/releases), unzip it and
move the app to `/Applications`. Release builds are **not notarized** by
Apple, so the first launch is blocked: open it once, then go to
**System Settings → Privacy & Security** and click **Open Anyway**. If you
would rather not do that, build from source — it takes about a minute.

That is only the first time: from 1.3.0 on, the app updates itself (below).

### Updates

Copies downloaded from Releases update through [Sparkle](https://sparkle-project.org).
On the second launch the app asks once whether to check on its own; you can
change that, or check by hand, in **Settings → General** and **About**. A
check that finds a version while you work does not open a window: the menu
shows “Version … is ready to install”.

Every update is signed with the project's EdDSA key, and so is the feed that
announces it. The app holds the public half and refuses a feed or a zip that
does not match, before unpacking anything. That signature, not an Apple
notarization, is what proves an update comes from this repository. An update
Sparkle installs is not quarantined, so **Open Anyway** is not needed again.

A copy installed with Homebrew updates the same way. A copy built from source
does not update itself: pull and build again.

## First steps

1. With the CLI logged in to one account, open the menu and choose
   **Capture the CLI's current login**. macOS asks for permission to read the
   CLI's Keychain entry: **Allow** is enough, “Always Allow” is not needed.
2. For each other account, either:
   - choose **Add account with its token…** and paste an access token created
     at <https://supabase.com/dashboard/account/tokens> while signed in to
     that account, or
   - run `supabase login` with that account one last time, then capture again.
3. From then on, click an account to switch.

Right-click an account to rename it, read its projects again or remove it. The
pencil next to a project gives it a local name.

## AI agents (MCP)

`sbswitch mcp` is a [Model Context Protocol](https://modelcontextprotocol.io)
server over stdio. An agent working on a feature can ask which account the CLI
is on and switch it to the one that owns the project, without you leaving the
conversation.

| Tool | What it does |
|------|--------------|
| `list_accounts` | Accounts and their projects (ref, name, alias, region), and which one the CLI is on. Read-only. |
| `current_account` | The account the CLI is logged in as now. Read-only. |
| `use_project` | Puts the CLI on the account that owns a project (ref, name or alias). Does nothing if it is already there. |
| `switch_account` | Switches to an account by name. |

**Connect it** from **Settings → AI agents**: one button for Claude Code and
one for Codex (they run `claude mcp add` / `codex mcp add` for you). Or by
hand:

```bash
claude mcp add --scope user supabase-switch -- "/Applications/Supabase Switch.app/Contents/MacOS/sbswitch" mcp
```

```bash
codex mcp add supabase-switch -- "/Applications/Supabase Switch.app/Contents/MacOS/sbswitch" mcp
```

For Claude Desktop, Cursor, Windsurf and other tools configured with JSON, the
same pane gives you the block to paste:

```json
{
  "mcpServers": {
    "supabase-switch": {
      "command": "/Applications/Supabase Switch.app/Contents/MacOS/sbswitch",
      "args": ["mcp"]
    }
  }
}
```

What agents can and cannot do:

- They **never see a token**: the server returns names, refs and regions only.
- Every switch they make is recorded with the agent's name (as its MCP client
  calls itself) and shows up in **Activity**, with a macOS notification if you
  want one.
- **Settings → AI agents → Let AI agents switch the account** turns switching
  off. They can still read which account is in use, and they get an error
  telling them to ask you.
- The server only switches the CLI's login. It does not run `supabase`
  commands, read your projects' data or touch your database.

<img src="docs/settings-activity.png" width="420" alt="Activity: each switch with who asked for it"> <img src="docs/settings-about.png" width="420" alt="About: version, updates, links and license">

## `sbswitch`

```text
sbswitch                          list the accounts and mark the one in use
sbswitch use <account>            switch the CLI to that account
sbswitch current                  say which account the CLI is on now
sbswitch capture [name]           register the account the CLI is logged in as
sbswitch add [name]               register an account from its access token
sbswitch refresh [account]        read the projects again
sbswitch rename <account> <new name>
sbswitch alias <project> [alias]  give a project a local name (none = back to Supabase's)
sbswitch remove <account>
sbswitch stats                    switches and runs per account
sbswitch run <account> -- <cmd>   run one command as that account without switching
sbswitch mcp                      MCP server over stdio, for AI agents
sbswitch version
```

`<account>` is its name, the start of its name, or the ref, name or alias of
one of its projects. `sbswitch add` reads the token without echo, or from
standard input — never from the arguments, where other processes could see it:

```bash
pbpaste | sbswitch add "Globex"
```

## How it works

- **Switching** pipes the stored token into `supabase login`: the CLI's own
  login path, minus the browser. The token is tried on its own first, so a
  revoked one never replaces a login that works; afterwards the CLI is asked
  who it is, and only then is the switch reported as done.
- **Telling accounts apart**: an account is the set of organizations it can see
  (`supabase orgs list`). The app never calls the Supabase API itself — every
  request goes through the CLI.
- **Knowing who is logged in, cheaply**: the app reads only the modification
  date of the CLI's Keychain entry (no prompt) and asks the CLI only when that
  date changes.
- `supabase logout` wipes everything under the Keychain service “Supabase CLI”,
  so this app keeps its tokens under its own service, “Supabase Switch”, and
  they survive a logout.

```text
Sources/SwitchCore       logic without UI: accounts, Keychain, CLI, usage, MCP server
Sources/SupabaseSwitch   the menu bar app (SwiftUI)
Sources/sbswitch         the same logic from a terminal
Tests/SwitchCoreTests    tests with a fake Keychain and a fake CLI
```

## Security and privacy

- Access tokens live **only in the macOS login Keychain**. They are never
  written to a file and never passed as process arguments (stdin or the
  environment only).
- `~/Library/Application Support/SupabaseSwitch/accounts.json` holds account
  names, project refs, regions, your aliases and the usage history (account,
  kind and time — never the command). Nothing secret. Mode `0600`.
- **No telemetry.** Nothing leaves your Mac except what the Supabase CLI itself
  sends to Supabase. Checking for updates (only if you allow it, or press the
  button) asks GitHub for `appcast.xml`, the list of versions; it sends no
  profile of your Mac.
- Worth knowing:
  - Each registered account means one long-lived access token in the Keychain.
    Any process running as your user can read entries created through
    `/usr/bin/security` without a prompt — the same exposure the CLI's own
    login has.
  - `sbswitch run` puts the token in the environment of the command it runs.
  - An agent with the MCP connected can switch the CLI to any registered
    account. Turn that off in Settings if you would rather do it yourself.
  - If you revoke a token in the dashboard, that account stops switching: add
    it again.
- Not handled: the CLI's fallback token file `~/.supabase/access-token`, used
  when no Keychain is available.

See [SECURITY.md](SECURITY.md) to report a vulnerability.

## Development

```bash
./scripts/test.sh          # unit tests
./scripts/build-app.sh     # dist/Supabase Switch.app and dist/sbswitch
open "dist/Supabase Switch.app"
```

Two quirks of building with only the Command Line Tools are handled in the code:

- **Tests** use Swift Testing, whose macro plugin the compiler does not find on
  its own there; `scripts/test.sh` passes its path. With Xcode, plain
  `swift test` works too.
- **`@State` and `@FocusState`** are macros in the macOS 27 SDK and their plugin
  ships only with Xcode. Views use the aliases `@ViewState` and `@ViewFocus`
  from `Sources/SupabaseSwitch/ViewState.swift` instead.

`libSwiftScan` and `search path … not found` warnings are harmless.

User-facing text goes through `tr("English", "Español")` (in
`Sources/SwitchCore/Localization.swift`). `SUPABASE_SWITCH_LANG=en|es` forces a
language.

`scripts/try-update.sh` runs a real Sparkle update on your Mac, start to
finish, with a throwaway key and a feed on `127.0.0.1`, and checks that an
edited feed and a swapped zip are refused. It does not touch your accounts,
your settings or the real feed.

`SUPABASE_SWITCH_DEMO=1` opens the app with three made-up accounts kept in
memory — no file, Keychain or CLI is touched — and
`SUPABASE_SWITCH_SNAPSHOTS=<folder>` draws the menu and every settings pane
into PNGs and quits; that is how the screenshots here are made:

```bash
SUPABASE_SWITCH_SNAPSHOTS=/tmp/shots "dist/Supabase Switch.app/Contents/MacOS/SupabaseSwitch"
```

Contributions are welcome — see [CONTRIBUTING.md](CONTRIBUTING.md).

## License

[MIT](LICENSE). The app includes [Sparkle](https://github.com/sparkle-project/Sparkle),
© its authors, under the MIT License; its notice ships inside the app as
`Contents/Resources/Sparkle-LICENSE.txt`.

---

Supabase Switch is an independent project, not affiliated with or endorsed by
Supabase Inc. Supabase is a trademark of Supabase Inc. The app does not use the
Supabase logo.
