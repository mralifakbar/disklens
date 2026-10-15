# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/).

## [Unreleased]

## [0.1.0] - 2026-10-15

First public release.

### Added

- Whole-disk treemap of the APFS Data volume, plus the sealed system, Preboot,
  Recovery and VM volumes as tiles, with Category and Cleanup views.
- Parallel `fts(3)` scanner that counts allocated blocks and loads deeper folders
  on demand.
- Root helper started through the standard macOS admin prompt, with a fallback to
  scanning as the current user.
- Report of folders that couldn't be read, with a shortcut to Full Disk Access.
- Cleanup recommendations for package manager caches, build output, SDKs,
  simulators, AI models, Docker, idle `node_modules`, Claude Code worktrees, old
  downloads and the Trash.
- Copy a reviewed cleanup script, or move selected items to the Trash.
- `--demo` mode with sample data, and `--scan` for a summary in the terminal.

[Unreleased]: https://github.com/mralifakbar/disklens/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/mralifakbar/disklens/releases/tag/v0.1.0
