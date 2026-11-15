# Security policy

Supabase Switch handles Supabase access tokens, which grant full access to
every project of an account. Reports are taken seriously.

## Reporting a vulnerability

Please **do not open a public issue**. Use GitHub's private reporting instead:
**Security → Report a vulnerability** on this repository. You will get an
answer within a week.

Include what you found, how to reproduce it, and which version
(`sbswitch version`) and macOS version you used. **Never include a real access
token** in a report.

## Supported versions

Only the latest release gets fixes.

## What the app promises

- Tokens are stored only in the macOS login Keychain, under the service
  “Supabase Switch” (the CLI's own login stays under “Supabase CLI”).
- Tokens are never written to a file and never passed as process arguments:
  only through standard input or the environment of the child process.
- The state file holds no secrets.
- The app sends nothing anywhere: every request to Supabase is made by the
  Supabase CLI.

A way to break any of these is a vulnerability.

## Known limits (by design)

- Entries are created through `/usr/bin/security`, so any process running as
  the same user can read them through that tool without a prompt. The app is
  signed ad hoc, so the Keychain cannot tie the entries to it instead.
- `sbswitch run` exposes the token to the command it runs, in
  `SUPABASE_ACCESS_TOKEN`.
- Release builds are not notarized.
