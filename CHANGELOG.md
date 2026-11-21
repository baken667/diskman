# Changelog

All notable changes to diskman are listed here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions are the release tags.

## [Unreleased]

### Added

- Apps installed by a package (owned by root) and their files in /Library can be removed: diskman
  asks Finder to move them to the Trash, and Finder asks for an administrator password.

## [1.1] - 2026-11-21

### Added

- Update and Restart: diskman downloads a new release, checks that it is signed by the same
  developer, replaces itself and reopens. The previous version is moved to the Trash. Releases now
  ship a zip for this next to the disk image.
- A changelog, and issue forms for bugs, feature requests and cleanup rules.

### Changed

- The app inside the disk image carries its own notarization ticket, so it opens offline no matter
  how it was copied.

## [1.0] - 2026-11-21

First public release.

### Added

- App uninstaller: lists everything an app keeps on disk (bundle, containers, preferences, caches,
  logs, launch agents, plug-ins, installer receipts) with sizes, before anything is removed.
- Cache and log cleanup driven by 34 declarative rules for developer tools, browsers and the system.
- Everything is moved to the Trash; nothing is deleted permanently.
- Running apps block removal of their own data; uncertain matches and review-first rules are never
  preselected.
- Full Disk Access prompt for finding leftovers in protected folders.
- A note in the sidebar when a newer release is out.
- Signed and notarized builds for Apple silicon.

[Unreleased]: https://github.com/baken667/diskman/compare/v1.1...HEAD
[1.1]: https://github.com/baken667/diskman/compare/v1.0...v1.1
[1.0]: https://github.com/baken667/diskman/releases/tag/v1.0
