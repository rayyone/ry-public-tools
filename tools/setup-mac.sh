#!/usr/bin/env bash
#
# setup-mac.sh — bootstrap a new macOS machine with my standard toolset.
#
# Usage:
#   ./setup-mac.sh            # install everything (skips what's already present)
#   ./setup-mac.sh ghostty    # install only the named tool(s)
#   ./setup-mac.sh --list     # list all available tools
#
# Adding/removing a tool:
#   1. Write an install_<name>() function below (return early if already installed).
#   2. Add "<name>" to the TOOLS array.
#   3. Done. Removing = delete the function and its entry in TOOLS.
#
set -uo pipefail

# ---------------------------------------------------------------------------
# Registry: order matters (deps first). Each name must have an install_<name>().
# ---------------------------------------------------------------------------
TOOLS=(
  homebrew
  claude_code
  ghostty
  oh_my_zsh
  p10k
  zed
  zoxide
  yazi
  mcp_github
  mcp_gmail
)

# ---------------------------------------------------------------------------
# Output helpers
# ---------------------------------------------------------------------------
BOLD=$'\033[1m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; RED=$'\033[31m'; RESET=$'\033[0m'
info()  { printf "%s==>%s %s\n" "$BOLD" "$RESET" "$*"; }
ok()    { printf "  %s✓%s %s\n" "$GREEN" "$RESET" "$*"; }
skip()  { printf "  %s•%s %s (already installed)\n" "$YELLOW" "$RESET" "$*"; }
warn()  { printf "  %s!%s %s\n" "$YELLOW" "$RESET" "$*"; }
fail()  { printf "  %s✗%s %s\n" "$RED" "$RESET" "$*"; }
have()  { command -v "$1" >/dev/null 2>&1; }

# Brew install with idempotency baked in (brew is already idempotent, but quiet).
brew_install()      { brew list --formula "$1" >/dev/null 2>&1 || brew install "$1"; }
brew_install_cask() { brew list --cask "$1"    >/dev/null 2>&1 || brew install --cask "$1"; }

# ---------------------------------------------------------------------------
# Tool installers — one per tool. Each returns early if already present.
# ---------------------------------------------------------------------------

install_homebrew() {
  if have brew; then skip "Homebrew"; return; fi
  info "Installing Homebrew"
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  # Make brew available in this script run (Apple Silicon path).
  [ -x /opt/homebrew/bin/brew ] && eval "$(/opt/homebrew/bin/brew shellenv)"
  [ -x /usr/local/bin/brew ]    && eval "$(/usr/local/bin/brew shellenv)"
  ok "Homebrew"
}

install_claude_code() {
  if have claude; then skip "Claude Code"; return; fi
  info "Installing Claude Code"
  if have npm; then
    npm install -g @anthropic-ai/claude-code
  else
    curl -fsSL https://claude.ai/install.sh | bash
  fi
  ok "Claude Code"
}

install_ghostty() {
  if have ghostty || [ -d "/Applications/Ghostty.app" ]; then skip "Ghostty"; return; fi
  info "Installing Ghostty"
  brew_install_cask ghostty
  ok "Ghostty"
}

install_oh_my_zsh() {
  if [ -d "$HOME/.oh-my-zsh" ]; then skip "oh-my-zsh"; return; fi
  info "Installing oh-my-zsh"
  # --unattended: don't change shell or launch zsh mid-script.
  sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
  ok "oh-my-zsh"
}

install_p10k() {
  local dir="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k"
  if [ -d "$dir" ]; then skip "powerlevel10k"; return; fi
  info "Installing powerlevel10k"
  git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$dir"
  # Point .zshrc at the theme (only if oh-my-zsh's ZSH_THEME line exists).
  if grep -q '^ZSH_THEME=' "$HOME/.zshrc" 2>/dev/null; then
    sed -i '' 's|^ZSH_THEME=.*|ZSH_THEME="powerlevel10k/powerlevel10k"|' "$HOME/.zshrc"
  fi
  ok "powerlevel10k (run 'p10k configure' to set up the prompt)"
}

install_zed() {
  if have zed || [ -d "/Applications/Zed.app" ]; then skip "Zed"; return; fi
  info "Installing Zed"
  brew_install_cask zed
  ok "Zed"
}

install_zoxide() {
  if have zoxide; then skip "zoxide"; return; fi
  info "Installing zoxide"
  brew_install zoxide
  add_to_zshrc 'eval "$(zoxide init zsh)"'
  ok "zoxide"
}

install_yazi() {
  if have yazi; then skip "yazi"; return; fi
  info "Installing yazi (+ previewers/deps)"
  brew install yazi ffmpeg-full sevenzip jq poppler fd ripgrep fzf zoxide \
    resvg imagemagick-full font-symbols-only-nerd-font
  brew link ffmpeg-full imagemagick-full -f --overwrite
  ok "yazi"
}

install_mcp_github() {
  if ! have claude; then warn "Claude Code missing — skipping GitHub MCP"; return; fi
  if claude mcp get github >/dev/null 2>&1; then skip "GitHub MCP"; return; fi
  info "Adding GitHub MCP (official remote)"
  claude mcp add --transport http github https://api.githubcopilot.com/mcp/
  ok "GitHub MCP (authenticate on first use)"
}

install_mcp_gmail() {
  if ! have claude; then warn "Claude Code missing — skipping Gmail MCP"; return; fi
  if claude mcp get gmail >/dev/null 2>&1; then skip "Gmail MCP"; return; fi

  # Self-hosted: taylorwilsdon/google_workspace_mcp, run via uvx.
  # Requires Google OAuth client creds — set these before running, or edit here.
  : "${GOOGLE_OAUTH_CLIENT_ID:=YOUR_GOOGLE_OAUTH_CLIENT_ID}"
  : "${GOOGLE_OAUTH_CLIENT_SECRET:=YOUR_GOOGLE_OAUTH_CLIENT_SECRET}"

  if ! have uvx; then
    info "Installing uv (for uvx)"
    brew_install uv
  fi

  info "Adding Gmail MCP (google_workspace_mcp, self-hosted)"
  claude mcp add gmail \
    -e GOOGLE_OAUTH_CLIENT_ID="$GOOGLE_OAUTH_CLIENT_ID" \
    -e GOOGLE_OAUTH_CLIENT_SECRET="$GOOGLE_OAUTH_CLIENT_SECRET" \
    -- uvx workspace-mcp --tools gmail
  if [[ "$GOOGLE_OAUTH_CLIENT_ID" == YOUR_* ]]; then
    warn "Set GOOGLE_OAUTH_CLIENT_ID / GOOGLE_OAUTH_CLIENT_SECRET — placeholder used"
  fi
  ok "Gmail MCP"
}

# ---------------------------------------------------------------------------
# Shared helper: append a line to .zshrc only if not already there.
# ---------------------------------------------------------------------------
add_to_zshrc() {
  local line="$1" rc="$HOME/.zshrc"
  touch "$rc"
  grep -qF "$line" "$rc" || printf '\n%s\n' "$line" >>"$rc"
}

# ---------------------------------------------------------------------------
# Driver
# ---------------------------------------------------------------------------
run_tool() {
  local name="$1"
  if ! declare -f "install_$name" >/dev/null; then
    fail "Unknown tool: $name"; return 1
  fi
  "install_$name"
}

main() {
  if [[ "${1:-}" == "--list" ]]; then
    printf '%s\n' "${TOOLS[@]}"; exit 0
  fi

  [[ "$(uname)" == "Darwin" ]] || { fail "macOS only"; exit 1; }

  local targets=("$@")
  [ ${#targets[@]} -eq 0 ] && targets=("${TOOLS[@]}")

  info "Setting up: ${targets[*]}"
  for t in "${targets[@]}"; do run_tool "$t"; done
  info "Done. Restart your terminal (or 'source ~/.zshrc') to pick up changes."
}

main "$@"
