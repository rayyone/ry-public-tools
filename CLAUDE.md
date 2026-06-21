# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A collection of **public, `curl | bash`-installable** shell scripts for the team. The
distribution model is the architecture: a non-technical teammate copies one line from the
README into a terminal and runs a tool — no clone, no `chmod`, no manual download. The raw
GitHub URLs (`https://raw.githubusercontent.com/rayyone/ry-public-tools/main/...`) are the
public API and go live the moment you push to `main`.

> **Hard constraint:** everything here is fully public. No secrets, tokens, internal
> hostnames, or private logic. Anyone with a URL can read and run these scripts. The Gmail
> OAuth creds in `setup-mac.sh` are intentionally placeholders supplied at runtime via env.

## Architecture

Two layers:

1. **`install.sh` — the router.** Tiny, dependency-free. Holds a `TOOLS` registry
   (`name:description`), lists tools with no args, and for `<tool>` downloads
   `tools/<tool>.sh` from `REPO_RAW` and pipes it to `bash`, forwarding remaining args
   (`bash -s -- "$@"`). Kept deliberately small so the `curl | bash` snippet stays
   trustworthy to read.

2. **`tools/<name>.sh` — self-contained tools.** Each script must run standalone with
   nothing from this repo (because it's fetched and piped in isolation). Two flavors exist:
   - **Single-file tool** (`setup-mac.sh`): everything in one script.
   - **Tool with templates** (`decision-profile.sh` + `tools/decision-profile/templates/`):
     the script installs *other* files. It resolves templates from a sibling
     `templates/` dir when run from a local checkout, **or downloads each template file
     from `REPO_RAW` when piped** (`resolve_templates`). When adding template files, you
     must list them in the relevant `*_FILES` arrays or the piped install won't fetch them.

### Conventions shared across scripts

- `set -euo pipefail` (router, decision-profile) or `set -uo pipefail` (setup-mac, which
  must keep going past a failed individual installer).
- An internal **registry array** drives a dispatch loop. `setup-mac.sh` maps each `TOOLS`
  entry to an `install_<name>()` function; `--list` prints the registry. Adding a tool =
  write the function + add the name to the array.
- **Idempotency is mandatory.** Every installer checks for presence and returns early
  (`skip "..."`). Re-running any script is always safe.
- **Never clobber user data.** `decision-profile.sh` distinguishes `copy_force` (files we
  own — skills, hooks) from `copy_absent` (user data — profile, logs — never overwritten).
- Colored `info/ok/skip/warn/fail` output helpers are duplicated per-script on purpose
  (self-containment beats DRY here).
- JSON edits to `~/.claude/settings.json` are done in an inline **Python heredoc**
  (`python3` ships with macOS), not `sed`/`jq`, and are idempotent (`has_cmd` before add,
  `drop_cmd` to remove). Mode is passed as argv: `wire` / `unwire`.

## Adding a new tool

1. Drop a self-contained `tools/<name>.sh` (`#!/usr/bin/env bash`, needs nothing from this repo).
2. Add `"<name>:<one-line description>"` to the `TOOLS` array in `install.sh`.
3. Add a snippet section to `README.md`.
4. Commit and push to `main` — raw URLs are live immediately.

## Testing changes locally

There is no build, lint, or test suite. Scripts are the deliverable. To exercise a change
without going through GitHub, point `REPO_RAW` at a fork/branch (both `install.sh` and
`decision-profile.sh` honor it), or run a tool script directly from the checkout:

```bash
# Run the router locally (downloads tools from REPO_RAW)
REPO_RAW="file://$PWD" bash install.sh setup-mac --list   # router still pulls over the URL scheme

# Run a tool script straight from the checkout (uses local templates/ when present)
bash tools/setup-mac.sh --list
bash tools/setup-mac.sh ghostty zed          # install only named pieces
bash tools/decision-profile.sh status        # install | uninstall | status
```

`setup-mac.sh` is macOS-only (guards on `uname == Darwin`) and mutates the real machine —
test individual `install_<name>` targets, not a full run, unless you mean it.

## The `decision-profile` tool

The most involved tool. It installs two Claude Code skills (`decision-profile` +
`auto-answer`), five event hooks, and scaffolds user data, then wires the hooks into
`~/.claude/settings.json`. Layout under `tools/decision-profile/templates/`:

- `SKILL.md`, `auto-answer/SKILL.md` — the two skill bodies (overwritten on install).
- `hooks/` — `gate.sh` (PreToolUse on `AskUserQuestion`), `post-ask.sh` (PostToolUse),
  `session-check.sh` (SessionStart), plus `split-profile.sh` / `sync-index.sh` helpers.
- `user-decisions-table.md` + `*-log.md` — user data scaffolds, never overwritten.
- `sync-decisions.sh` + `daily-backup.sh` + `com.rayyone.decision-profile-backup.plist`
  — the **daily backup** feature (listed in `BACKUP_FILES`). On macOS, install copies
  the two scripts into `~/.claude/decision-profile/`, bakes the real `$HOME` into the
  plist (launchd doesn't expand `~`), drops it in `~/Library/LaunchAgents/`, and
  `launchctl bootstrap`s it to run `sync-decisions.sh backup` daily at 03:00. Backups
  go to `~/.ry-decision-profile-backup/` (outside `~/.claude`, outside any git repo).
  Non-Darwin: skipped. Note: probe launchd state with `agents="$(launchctl list)"`
  then a `[[ ]]` glob — piping `launchctl list | grep -q` lets grep close the pipe
  early, SIGPIPEs launchctl, and trips `set -o pipefail` into a false negative.

`uninstall` removes hooks, skills, **and the launchd backup agent + its scripts**, but
**keeps user data** (`user-decisions-table.md`, `decision-profile/`) and **existing
backups** in `~/.ry-decision-profile-backup/`. Editing this tool means keeping
`decision-profile.sh`'s `*_FILES` arrays (including `BACKUP_FILES`), the
install/uninstall/status commands, and the `edit_settings` Python in sync.
