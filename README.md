# diskman

A small macOS app that frees disk space without deleting anything behind your back.

It does two things:

- **Uninstalls apps completely.** Pick an app and diskman lists everything it keeps on disk: the
  bundle, its containers, preferences, caches, logs, launch agents, plug-ins and installer receipts.
- **Cleans caches and logs.** Build caches, package manager downloads, browser caches and logs are
  found by a list of declarative rules, sized, and shown before anything is touched.

## How it stays safe

A tool that removes files should be boring about it:

- **Everything goes to the Trash.** There is one code path for removal and it only moves items to
  the Trash. Nothing is deleted permanently; space is freed when you empty the Trash yourself.
- **You see it first.** The uninstaller lists every item with its path and size. The cleanup screen
  shows each rule with its total size; expand a rule to see its largest items.
- **Unsure means unchecked.** Leftovers that may belong to another product (a bundle ID with an
  unknown suffix, a same-vendor ID, dot folders in your home folder) and cleanup rules that are not
  fully regenerable are shown but never preselected.
- **The app goes first.** If an app bundle cannot be moved to the Trash, its data is left alone.
- **Running apps are left alone.** An app cannot be removed while it is running, and a cleanup rule
  tied to specific apps is blocked until they quit. Catch-all cache rules cannot know which apps are
  running, so they are opt-in.
- **Rules stay inside their folder.** A cleanup rule cannot match anything outside the path it
  names, and a symlink it finds there is neither followed nor removed.

## Requirements

- A Mac with Apple silicon. Intel Macs are not supported.
- macOS 26 or later
- Xcode 27.2 or later to build

## Install

Download the latest disk image from [Releases](https://github.com/baken667/diskman/releases/latest),
open it and drag diskman to Applications. Releases are signed with a Developer ID and notarized by
Apple.

### Updates

When it opens, diskman asks GitHub for the number of the latest release and shows a note in the
sidebar if a newer one is out. That request is the only time the app uses the network, and it
carries nothing about you or your disk. Nothing is downloaded or installed for you: the note links
to the release page. Turn the check off in Settings.

## Build

```sh
git clone https://github.com/baken667/diskman.git
cd diskman
open diskman.xcodeproj
```

Select the `diskman` scheme and run. Signing is set to automatic, so choose your own team in
*Signing & Capabilities* first.

### Full Disk Access

macOS hides other apps' containers and a few Library folders from every app by default. Without
Full Disk Access diskman still works, but it finds fewer leftovers. The app shows a banner with a
button that opens the right pane in System Settings; nothing is blocked if you decline.

macOS ties the permission to the app's code signature, so a build signed without a team may ask
for it again after you rebuild.

## Project layout

| Path | What it is |
| --- | --- |
| `DiskmanCore/` | Swift package with all disk logic and no UI: finding leftovers, expanding cleanup rules, sizing, moving to the Trash. |
| `DiskmanCore/Sources/DiskmanCore/Resources/cleanup-rules.json` | The built-in cleanup rules. |
| `diskman/` | The SwiftUI app, a thin layer over the package. |

Run the tests of the core package:

```sh
cd DiskmanCore
swift test
```

The tests never write outside temporary folders and never move anything to the Trash.

## Adding a cleanup rule

Rules live in [`cleanup-rules.json`](DiskmanCore/Sources/DiskmanCore/Resources/cleanup-rules.json).
A rule is one JSON object:

```json
{"id": "firefox.cache", "group": "Browsers", "kind": "caches", "isSafe": true,
 "name": "Firefox Cache",
 "description": "Web pages, scripts and graphics Firefox stored to load sites faster (history, passwords and logins are kept); sites load a bit slower until it fills again.",
 "paths": ["~/Library/Caches/Firefox/*"], "appBundleIDs": ["org.mozilla.firefox"]}
```

| Field | Meaning |
| --- | --- |
| `id` | Unique, stable identifier. |
| `group` | Section the rule is listed under. |
| `kind` | What the items are, for example `caches` or `logs`. |
| `isSafe` | `true` only if everything the rule matches is rebuilt automatically with no loss. Safe rules are checked by default; the rest are opt-in. |
| `name`, `description` | Shown to the user. The description must say what happens after removal. |
| `paths` | Patterns starting with `~/`. Any path component may be a glob (`*`, `*.log`). A pattern must contain at least one glob, and only items inside its literal prefix are matched. |
| `appBundleIDs` | Apps that must be quit before the rule can run. May be empty. |

Guidelines:

- Order matters. A path belongs to the first rule that claims it, so put specific rules above
  catch-all ones.
- Check the path on a real machine, and check what the tool does after its cache is gone.
- When in doubt, set `isSafe` to `false`.

## Releasing

Pushing a tag builds, signs, notarizes and publishes that version:

```sh
git tag v1.1
git push origin v1.1
```

The version number comes from the tag. The [release workflow](.github/workflows/release.yml) needs
these repository secrets:

| Secret | What it is |
| --- | --- |
| `DEVELOPER_ID_P12` | The "Developer ID Application" certificate with its private key, exported as `.p12` and base64-encoded. |
| `DEVELOPER_ID_P12_PASSWORD` | The password chosen when exporting it. |
| `ASC_KEY_P8` | An App Store Connect API key (the contents of the `.p8` file), used for notarization. |
| `ASC_KEY_ID` | That key's ID. |
| `ASC_ISSUER_ID` | The issuer ID shown above the key list in App Store Connect. |

## License

[MIT](LICENSE)
