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

Bootstrap a fresh Mac with the standard toolset. One command, safe to re-run —
installed tools are skipped.

```bash
curl -fsSL https://raw.githubusercontent.com/rayyone/ry-public-tools/main/install.sh | bash -s -- setup-mac
```

After it finishes, restart your terminal (or `source ~/.zshrc`), then run
`p10k configure` to set up the prompt.

**What it installs**

| Tool | Notes |
|------|-------|
| Homebrew | Package manager (installed first; everything else depends on it) |
| Claude Code | via `npm` if present, else the official installer |
| Ghostty | Terminal (cask) |
| oh-my-zsh | Zsh framework (unattended install) |
| powerlevel10k | Zsh theme — run `p10k configure` after to set up the prompt |
| Zed | Editor (cask) |
| zoxide | Smarter `cd` — adds `eval "$(zoxide init zsh)"` to `.zshrc` |
| yazi | Terminal file manager + previewers (ffmpeg, poppler, imagemagick, nerd font, …) |
| GitHub MCP | Official remote MCP for Claude Code (auth on first use) |
| Gmail MCP | Self-hosted `google_workspace_mcp` via `uvx` (needs Google OAuth creds — see below) |

Install only specific pieces (e.g. just Ghostty + Zed):

```bash
curl -fsSL https://raw.githubusercontent.com/rayyone/ry-public-tools/main/install.sh | bash -s -- setup-mac ghostty zed
```

List every tool name it can install:

```bash
curl -fsSL https://raw.githubusercontent.com/rayyone/ry-public-tools/main/tools/setup-mac.sh | bash -s -- --list
```

**Gmail MCP (self-hosted)** — uses
[`taylorwilsdon/google_workspace_mcp`](https://github.com/taylorwilsdon/google_workspace_mcp)
run via `uvx workspace-mcp --tools gmail`. It needs a Google OAuth **client ID
and secret**. Export them *before* running so the installer picks them up:

```bash
export GOOGLE_OAUTH_CLIENT_ID=...
export GOOGLE_OAUTH_CLIENT_SECRET=...
curl -fsSL https://raw.githubusercontent.com/rayyone/ry-public-tools/main/install.sh | bash -s -- setup-mac
```

Create the creds in Google Cloud Console → OAuth 2.0 Client (Desktop app). The
first time you use a Gmail tool in Claude Code, complete the OAuth flow in the
browser. Without the creds, the Gmail MCP step warns and uses placeholders —
everything else still installs.

**Requirements** — macOS (Apple Silicon or Intel), internet access, admin
rights (Homebrew install may prompt for your password).

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

### Add / remove a tool inside `setup-mac.sh`

The script uses one function per tool, registered in the `TOOLS` array.

**Add:**
1. Write an `install_<name>()` function. Return early if already installed:
   ```bash
   install_fzf() {
     if have fzf; then skip "fzf"; return; fi
     info "Installing fzf"
     brew_install fzf
     ok "fzf"
   }
   ```
2. Add `<name>` to the `TOOLS` array (order = install order; put deps first).

**Remove:** delete the function and its entry in `TOOLS`.

Helpers available inside an installer: `have <cmd>`, `brew_install <formula>`,
`brew_install_cask <cask>`, `add_to_zshrc '<line>'`, and the output helpers
`info` / `ok` / `skip` / `warn` / `fail`.

> **Do not commit real OAuth secrets** into the script or this repo. The Gmail
> OAuth creds are placeholders supplied at runtime via env.

### Why curl | bash?

Non-technical teammates can't be expected to clone, `chmod +x`, or navigate
folders. A single copy-paste line is the lowest-friction path. Every script
here is public and readable — anyone can inspect a URL before running it.

> [!WARNING]
> Only put scripts here that are safe to be **fully public**. No secrets, no
> tokens, no internal hostnames. Anyone with the URL can read and run them.
