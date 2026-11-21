# Changelog

All notable changes to diskman are listed here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions are the release tags.

## [Unreleased]

### Added

- Each leftover says why it is listed: named after the app's ID, named after the app, same developer,
  a background job that starts the app, or a folder with the app's name.
- The app's bundle ID, Team ID and whether it came from the App Store are shown above its leftovers.
- A cleanup rule's items have their own checkboxes, so one project or one model can be kept.
- Rules that only report: simulator devices, Colima virtual machines and device backups are measured
  and explained, with the owning tool's command to copy where there is one. They are never removed.
- New rules: Expo Go downloads, Gradle daemon logs, the Zig cache and iPhone/iPad software updates.
- A Quit button next to "Quit … first", for cleanup rules and for uninstalling.
- After a move, a bar says how much went to the Trash and offers to open it.
- *Help › What diskman Reads*: the folders and rules the app looks at, generated from the code.
- A Shortcuts and Spotlight action that measures what can be cleaned, without removing anything.
- With Full Disk Access, apps in Downloads and on the Desktop are listed too.
- When another copy of the app you are removing exists, its data is left unticked.
- Copy Path in the context menu, and the full path when hovering over a row.

### Changed

- The sidebar search also matches bundle IDs.
- "Continue Without" on the Full Disk Access banner is remembered.
- "Show all N items" replaces the "+ N more" line that could not be expanded.

### Fixed

- The Hugging Face rule missed the `xet` chunk cache.

## [1.2] - 2026-11-21

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

[Unreleased]: https://github.com/baken667/diskman/compare/v1.2...HEAD
[1.2]: https://github.com/baken667/diskman/compare/v1.1...v1.2
[1.1]: https://github.com/baken667/diskman/compare/v1.0...v1.1
[1.0]: https://github.com/baken667/diskman/releases/tag/v1.0
