# ry-public-tools

Public install scripts for the team. Copy a snippet below, paste it into your
**Terminal**, press Enter. No setup, no cloning, no manual downloads.

## Quick start

See what's available, then run a tool by name:

```bash
# List all tools
curl -fsSL https://raw.githubusercontent.com/rayyone/ry-public-tools/main/install.sh | bash

# Run one
curl -fsSL https://raw.githubusercontent.com/rayyone/ry-public-tools/main/install.sh | bash -s -- <tool>
```

## Available tools

### `setup-mac` — bootstrap a new Mac

Installs the standard toolset (Homebrew, Claude Code, Ghostty, oh-my-zsh,
powerlevel10k, Zed, zoxide, yazi, and MCP servers). Safe to re-run — it skips
anything already installed.

```bash
curl -fsSL https://raw.githubusercontent.com/rayyone/ry-public-tools/main/install.sh | bash -s -- setup-mac
```

Install only specific pieces (e.g. just Ghostty + Zed):

```bash
curl -fsSL https://raw.githubusercontent.com/rayyone/ry-public-tools/main/install.sh | bash -s -- setup-mac ghostty zed
```

List what `setup-mac` can install:

```bash
curl -fsSL https://raw.githubusercontent.com/rayyone/ry-public-tools/main/tools/setup-mac.sh | bash -s -- --list
```

### `decision-profile` — fewer interruptions in Claude Code

Installs two Claude Code skills (`decision-profile` + `auto-answer`) plus their
hooks. They learn how you decide and auto-resolve routine `AskUserQuestion`
prompts, asking only when genuinely uncertain or high-stakes. Pure bash — needs
`python3` (ships with macOS) and `curl`, no Node. Re-running is safe; your
existing profile and logs are never overwritten.

```bash
curl -fsSL https://raw.githubusercontent.com/rayyone/ry-public-tools/main/install.sh | bash -s -- decision-profile install
```

Then, in Claude Code, run `/decision-profile interview` to build your profile.

Check what's installed, or remove the hooks (your data is kept):

```bash
curl -fsSL https://raw.githubusercontent.com/rayyone/ry-public-tools/main/install.sh | bash -s -- decision-profile status
curl -fsSL https://raw.githubusercontent.com/rayyone/ry-public-tools/main/install.sh | bash -s -- decision-profile uninstall
```

---

## For maintainers

### Layout

```
ry-public-tools/
├── README.md        # this file — share the snippets above
├── install.sh       # router: downloads + runs tools/<name>.sh
└── tools/
    └── setup-mac.sh  # one self-contained script per tool
```

### Add a new tool

1. Drop a self-contained `tools/<name>.sh` (a `#!/usr/bin/env bash` script that
   needs nothing from this repo to run).
2. Add a `"<name>:<one-line description>"` entry to the `TOOLS` array in
   `install.sh`.
3. Add a snippet section to this README.
4. Commit and push to `main`. The raw URLs are live immediately.

### Why curl | bash?

Non-technical teammates can't be expected to clone, `chmod +x`, or navigate
folders. A single copy-paste line is the lowest-friction path. Every script
here is public and readable — anyone can inspect a URL before running it.

> [!WARNING]
> Only put scripts here that are safe to be **fully public**. No secrets, no
> tokens, no internal hostnames. Anyone with the URL can read and run them.
