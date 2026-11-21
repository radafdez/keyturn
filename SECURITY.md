# Security policy

Keyturn handles Supabase access tokens, which grant full access to
every project of an account. Reports are taken seriously.

## Reporting a vulnerability

Please **do not open a public issue**. Use GitHub's private reporting instead:
**Security → Report a vulnerability** on this repository. You will get an
answer within a week.

Include what you found, how to reproduce it, and which version
(`keyturn version`) and macOS version you used. **Never include a real access
token** in a report.

## Supported versions

Only the latest release gets fixes.

## What the app promises

- Tokens are stored only in the macOS login Keychain, under the service
  “Keyturn” (the CLI's own login stays under “Supabase CLI”).
- Tokens are never written to a file and never passed as process arguments:
  only through standard input or the environment of the child process.
- The state file holds no secrets.
- The app sends nothing anywhere: every request to Supabase is made by the
  Supabase CLI.
- The CLI scanner (Settings → Running CLIs) only reads the process table. It
  never runs, signals or attaches to another process, and it never writes a
  command line, a folder or any output to disk: `CLIs/activity.json` holds
  only the tool, the app, the process id and the times.

A way to break any of these is a vulnerability.

## Known limits (by design)

- Entries are created through `/usr/bin/security`, so any process running as
  the same user can read them through that tool without a prompt. The app is
  signed ad hoc, so the Keychain cannot tie the entries to it instead.
- `keyturn run` exposes the token to the command it runs, in
  `SUPABASE_ACCESS_TOKEN`.
- Release builds are not notarized.
- To tell which tool a `node` or `python` process runs, the scanner reads its
  arguments in memory, the same ones `ps` shows to your user. A secret passed
  as an argument to such a tool is readable this way by any process of your
  user anyway; Keyturn discards the arguments after matching.
