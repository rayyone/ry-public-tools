#!/usr/bin/env bash
#
# install.sh — one-line installer/router for ry-public-tools.
#
# Usage (paste into a terminal):
#   curl -fsSL https://raw.githubusercontent.com/rayyone/ry-public-tools/main/install.sh | bash -s -- setup-mac
#
# What it does:
#   - Downloads tools/<name>.sh from this repo and runs it.
#   - With no argument (or --list), prints the available tools.
#
# This file is intentionally tiny and dependency-free so the curl|bash
# snippet stays trustworthy and easy to read.
#
set -euo pipefail

# Where the raw tool scripts live. Override REPO_RAW to point at a fork/branch.
REPO_RAW="${REPO_RAW:-https://raw.githubusercontent.com/rayyone/ry-public-tools/main}"

# Registry: tool name -> short description. Keep in sync with tools/.
TOOLS=(
  "setup-mac:Bootstrap a new macOS machine with the standard toolset"
  "decision-profile:Install the decision-profile + auto-answer Claude Code skills"
)

BOLD=$'\033[1m'; GREEN=$'\033[32m'; RED=$'\033[31m'; RESET=$'\033[0m'
info() { printf "%s==>%s %s\n" "$BOLD" "$RESET" "$*"; }
fail() { printf "  %s✗%s %s\n" "$RED" "$RESET" "$*" >&2; }

list_tools() {
  printf "%sAvailable tools:%s\n" "$BOLD" "$RESET"
  for entry in "${TOOLS[@]}"; do
    printf "  %s%-12s%s %s\n" "$GREEN" "${entry%%:*}" "$RESET" "${entry#*:}"
  done
  printf "\nRun one with:\n  curl -fsSL %s/install.sh | bash -s -- <tool>\n" "$REPO_RAW"
}

known_tool() {
  local name="$1"
  for entry in "${TOOLS[@]}"; do
    [[ "${entry%%:*}" == "$name" ]] && return 0
  done
  return 1
}

main() {
  local tool="${1:-}"

  if [[ -z "$tool" || "$tool" == "--list" || "$tool" == "-l" ]]; then
    list_tools
    exit 0
  fi

  if ! known_tool "$tool"; then
    fail "Unknown tool: $tool"
    list_tools
    exit 1
  fi

  info "Fetching and running: $tool"
  # Pass any remaining args through to the tool script.
  shift || true
  local url="$REPO_RAW/tools/$tool.sh"
  curl -fsSL "$url" | bash -s -- "$@"
}

main "$@"
