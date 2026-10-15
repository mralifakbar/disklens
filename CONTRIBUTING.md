# Contributing to DiskLens

Thanks for helping out. This guide covers the setup, the layout of the code, and
what a good pull request looks like.

## Setup

You need macOS 14 or later and Xcode 15.3 or later (Swift 5.10).

```sh
git clone https://github.com/mralifakbar/disklens.git
cd disklens
swift test                          # run the tests
./build.sh && open build/DiskLens.app
```

You can open `Package.swift` in Xcode, but the app has to be launched from the
bundle `build.sh` makes: macOS needs the `Info.plist` for the admin prompt and the
folder-access descriptions.

## Layout

```
Sources/DiskLens/
  Core/   scanning, categories, recommendations, root helper, treemap layout
          (no SwiftUI here, so it's easy to test)
  UI/     SwiftUI views and colors
  App/    entry point, app state, demo data, development switches
Tests/DiskLensTests/   unit tests for Core
scripts/make-icon.swift  draws the app icon
build.sh               builds, signs (ad hoc) and packages the .app
```

## Development switches

| Switch | Effect |
|---|---|
| `DiskLens --demo` or `DISKLENS_DEMO=1` | Sample data. Nothing on your disk is read or touched. |
| `DISKLENS_NO_ADMIN=1` | Skip the password prompt and scan as yourself. |
| `DISKLENS_OPEN=~` (or a path) | Open that folder once the scan finishes. |
| `DISKLENS_MODE=cleanup` | Start in the Cleanup view. |
| `DISKLENS_SNAPSHOT=/tmp/shot.png` | Save the window to a PNG, then quit. |
| `DiskLens --scan` | Print a disk summary and the recommendations, no window. |

The README screenshots are made like this:

```sh
A=build/DiskLens.app/Contents/MacOS/DiskLens
DISKLENS_DEMO=1 DISKLENS_OPEN=~ DISKLENS_SNAPSHOT=$PWD/docs/screenshot-light.png $A -NSRequiresAquaSystemAppearance YES
DISKLENS_DEMO=1 DISKLENS_OPEN=~ DISKLENS_MODE=cleanup DISKLENS_SNAPSHOT=$PWD/docs/screenshot-cleanup-dark.png $A
DISKLENS_DEMO=1 DISKLENS_SNAPSHOT=$PWD/docs/screenshot-disk.png $A -NSRequiresAquaSystemAppearance YES
```

Use the environment variable rather than `--demo` when you pass AppKit flags such as
`-NSRequiresAquaSystemAppearance YES`. AppKit would read `--demo` as a key and treat
the stray `YES` as a file to open, and then no window appears.

Please don't commit screenshots of your own disk. File and folder names say a lot
about a person. The demo exists so you don't have to.

## Adding a cleanup rule

Most contributions will be new rules. They live in `Recommender.rules`
([`Core/Recommender.swift`](Sources/DiskLens/Core/Recommender.swift)):

```swift
Rule(title: "Deno cache", note: "Deno downloads modules again when it needs them.",
     safety: .safe, paths: ["Library/Caches/deno"]),
```

- `paths` are relative to the home folder. Missing paths are ignored.
- Use `.safe` only when deleting the folder never loses work: the tool rebuilds or
  downloads it again on its own. Anything with user data, or that costs a long
  download, is `.review`.
- If the right way to clean up is a command (`docker system prune`,
  `xcrun simctl delete`), set `command:`. The script then runs it instead of `rm`,
  and the app never moves those folders to the Trash.
- If your rule covers a folder in `~/Library/Caches`, add its name to
  `coveredCaches` so it isn't counted twice under "App caches".
- Add a category color in `Categorizer.explicitRelative` if the folder deserves one.
- Add a test in `RecommenderTests` (build a small tree and assert the
  recommendation). No real disk access is needed.

## Pull requests

- Keep each PR focused on one thing, and describe what changed and how you tested it.
- `swift test` must pass. CI runs it on every PR, along with a universal release build.
- Follow the style of the code around you: 4-space indent, small types, comments that
  explain *why*.
- For UI changes, include a before/after screenshot taken from `--demo`.
- Update `CHANGELOG.md` under **Unreleased**.

## Releasing (maintainers)

1. Move the **Unreleased** notes in `CHANGELOG.md` under a new version heading.
2. Tag and push: `git tag v0.2.0 && git push origin v0.2.0`.
3. The release workflow builds the universal app, zips it and publishes a GitHub
   release with the changelog section as notes.
