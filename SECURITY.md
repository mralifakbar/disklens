# Security

DiskLens runs part of itself as root, so its security matters more than usual for a
disk utility. This page explains what runs with privileges and how to report a
problem.

## Reporting a vulnerability

Please **don't open a public issue**. Report it privately through
[GitHub's vulnerability reporting](https://github.com/mralifakbar/disklens/security/advisories/new)
with steps to reproduce. You'll get a reply within a week, and a fix or a plan
soon after that.

Only the latest release gets security fixes.

## What runs as root

When you approve the macOS admin prompt, DiskLens starts **its own binary**
(`DiskLens.app/Contents/MacOS/DiskLens --helper`) as root through
`osascript … with administrator privileges`.

The helper:

- **only reads metadata.** It walks folders with `fts(3)` and reports names and
  allocated sizes. It never opens file contents, and never deletes, moves or writes
  anything on your disk.
- **only talks to the app.** Requests arrive on a FIFO the app created with mode
  `0600` inside its own `0700` temporary folder. Both FIFOs are unlinked as soon as
  the two sides have connected, so nothing else can open them after that.
- **dies with the app.** It exits when the app closes its end of the pipe, which
  also happens when the app crashes or is killed.
- **makes no network connections.**

Every cleanup (Trash, scripts) runs as **you**, never as root.

## Known limits

- **Install to `/Applications`.** The admin prompt starts whatever binary is inside
  the app bundle. If the app lives in a folder other users or processes can write
  to, they could replace that binary before you approve the prompt.
- **Processes running as you.** A process already running as your user could, in a
  narrow window during startup, open the request FIFO before the app does. It would
  then get folder names and sizes, never file contents. Anything running as your
  user can do a lot worse already, so this isn't treated as a boundary.
- **Release builds are ad-hoc signed and not notarized.** Check the SHA-256 on the
  release page, or build from source.
