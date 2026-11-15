# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/).

## [Unreleased]

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
