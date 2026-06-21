#!/usr/bin/env bash
#
# decision-profile.sh — pure-bash installer for the decision-profile Claude Code skill.
#
# Installs two sibling Claude Code skills (decision-profile + auto-answer), their
# event hooks, and scaffolds your data files — then wires the hooks into
# ~/.claude/settings.json idempotently. No Node, no clone, no npx.
#
# Usage (via the router):
#   curl -fsSL .../install.sh | bash -s -- decision-profile [install|uninstall|status]
#
# Usage (direct):
#   curl -fsSL .../tools/decision-profile.sh | bash -s -- install
#   ./decision-profile.sh install      # when run from a local checkout
#
# Templates are taken from a sibling templates/ dir when present (local checkout),
# otherwise downloaded from REPO_RAW (the curl|bash path).
#
set -euo pipefail

REPO_RAW="${REPO_RAW:-https://raw.githubusercontent.com/rayyone/ry-public-tools/main}"
TOOL_RAW="$REPO_RAW/tools/decision-profile"

# ---------------------------------------------------------------------------
# Paths (mirror cli.js)
# ---------------------------------------------------------------------------
HOME_DIR="$HOME"
CLAUDE_DIR="$HOME_DIR/.claude"
SKILLS_DIR="$CLAUDE_DIR/skills/decision-profile"
AUTO_ANSWER_SKILLS_DIR="$CLAUDE_DIR/skills/auto-answer"
HOOKS_DIR="$CLAUDE_DIR/hooks/decision-profile"
SETTINGS="$CLAUDE_DIR/settings.json"
ARMED_DIR="$CLAUDE_DIR/auto-answer/armed"

PROFILE="$CLAUDE_DIR/user-decisions-table.md"
STATE_DIR="$CLAUDE_DIR/decision-profile"
DOMAINS_DIR="$STATE_DIR/domains"
STATE_FILES=(user-manual-decided-log.md interviewed-questions-log.md low-confident-answers-log.md)

# Daily-backup (launchd) paths. Backups live outside ~/.claude so they survive
# an uninstall and are never near any git repo.
BACKUP_DIR="$HOME_DIR/.ry-decision-profile-backup"
LAUNCH_AGENTS_DIR="$HOME_DIR/Library/LaunchAgents"
PLIST_NAME="com.rayyone.decision-profile-backup"
PLIST_DEST="$LAUNCH_AGENTS_DIR/$PLIST_NAME.plist"

# Template files this installer needs (paths relative to templates/).
SKILL_FILES=(SKILL.md auto-answer/SKILL.md)
HOOK_FILES=(gate.sh session-check.sh post-ask.sh split-profile.sh sync-index.sh)
SCAFFOLD_FILES=(user-decisions-table.md "${STATE_FILES[@]}")
# Backup scripts (installed into STATE_DIR) + the launchd plist.
BACKUP_FILES=(sync-decisions.sh daily-backup.sh "$PLIST_NAME.plist")

# ---------------------------------------------------------------------------
# Output helpers
# ---------------------------------------------------------------------------
BOLD=$'\033[1m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; RED=$'\033[31m'; CYAN=$'\033[36m'; RESET=$'\033[0m'
log()  { printf "%s\n" "$*"; }
ok()   { printf "  %s✓%s %s\n" "$GREEN" "$RESET" "$*"; }
skip() { printf "  %s·%s %s\n" "$YELLOW" "$RESET" "$*"; }
fail() { printf "  %s✗%s %s\n" "$RED" "$RESET" "$*" >&2; }
have() { command -v "$1" >/dev/null 2>&1; }

# ---------------------------------------------------------------------------
# Template source: local sibling templates/ dir, or download to a tmp dir.
# Sets TPL to a directory containing the templates/ subtree.
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || true)"
TPL=""
TMP_TPL=""

resolve_templates() {
  if [[ -n "$SCRIPT_DIR" && -d "$SCRIPT_DIR/decision-profile/templates" ]]; then
    TPL="$SCRIPT_DIR/decision-profile/templates"   # router checkout: tools/decision-profile/templates
    return
  fi
  if [[ -n "$SCRIPT_DIR" && -d "$SCRIPT_DIR/templates" ]]; then
    TPL="$SCRIPT_DIR/templates"                     # run from inside tools/decision-profile/
    return
  fi
  # Piped install: fetch the templates we need into a temp dir.
  have curl || { fail "curl is required"; exit 1; }
  TMP_TPL="$(mktemp -d)"
  TPL="$TMP_TPL/templates"
  log "${BOLD}==>${RESET} Downloading templates from $TOOL_RAW/templates"
  local rel
  for rel in "${SKILL_FILES[@]}" "${HOOK_FILES[@]/#/hooks/}" "${SCAFFOLD_FILES[@]}" "${BACKUP_FILES[@]}"; do
    mkdir -p "$TPL/$(dirname "$rel")"
    if ! curl -fsSL "$TOOL_RAW/templates/$rel" -o "$TPL/$rel"; then
      fail "Failed to download templates/$rel"
      exit 1
    fi
  done
}

cleanup() { [[ -n "$TMP_TPL" && -d "$TMP_TPL" ]] && rm -rf "$TMP_TPL"; return 0; }
trap cleanup EXIT

# ---------------------------------------------------------------------------
# File helpers
# ---------------------------------------------------------------------------
copy_force()  { mkdir -p "$(dirname "$2")"; cp "$TPL/$1" "$2"; }            # overwrite (we own these)
copy_absent() { [[ -e "$2" ]] && return 1; mkdir -p "$(dirname "$2")"; cp "$TPL/$1" "$2"; }  # never clobber user data

# ---------------------------------------------------------------------------
# settings.json hook wiring — done in Python (ships on macOS) for safe JSON edits.
# Idempotent: adds each hook only if a matching command isn't already present,
# and drops the retired load-profile.sh wiring. Mode passed as argv: wire | unwire.
# ---------------------------------------------------------------------------
edit_settings() {
  local mode="$1"
  PY_SETTINGS="$SETTINGS" PY_HOOKS_DIR="$HOOKS_DIR" PY_MODE="$mode" python3 - <<'PY'
import json, os, sys

settings = os.environ["PY_SETTINGS"]
hooks_dir = os.environ["PY_HOOKS_DIR"]
mode = os.environ["PY_MODE"]

gate    = f'bash "{hooks_dir}/gate.sh"'
postask = f'bash "{hooks_dir}/post-ask.sh"'
session = f'bash "{hooks_dir}/session-check.sh"'

data = {}
if os.path.exists(settings):
    try:
        with open(settings) as f:
            data = json.load(f)
    except Exception as e:
        print(f"  \033[31m✗\033[0m Could not parse {settings}: {e}", file=sys.stderr)
        sys.exit(1)

hooks = data.setdefault("hooks", {})

def groups(evt):
    return hooks.setdefault(evt, [])

def has_cmd(evt, needle):
    return any(needle in (h.get("command","")) for g in hooks.get(evt,[]) for h in g.get("hooks",[]))

def drop_cmd(evt, needle):
    before = hooks.get(evt, [])
    kept = [g for g in before if not any(needle in (h.get("command","")) for h in g.get("hooks",[]))]
    removed = len(before) - len(kept)
    if evt in hooks:
        hooks[evt] = kept
    return removed

msgs = []

if mode == "wire":
    # Drop retired always-on load-profile.sh wiring first.
    if drop_cmd("PreToolUse", "decision-profile/load-profile.sh"):
        msgs.append("removed retired PreToolUse load-profile.sh wiring")

    if has_cmd("PreToolUse", "decision-profile/gate.sh"):
        msgs.append("· PreToolUse(AskUserQuestion) gate already wired")
    else:
        groups("PreToolUse").append({"matcher":"AskUserQuestion","hooks":[{"type":"command","command":gate,"timeout":5}]})
        msgs.append("✓ wired PreToolUse(AskUserQuestion) → gate.sh")

    if has_cmd("PostToolUse", "decision-profile/post-ask.sh"):
        msgs.append("· PostToolUse(AskUserQuestion) already wired")
    else:
        groups("PostToolUse").append({"matcher":"AskUserQuestion","hooks":[{"type":"command","command":postask,"timeout":10}]})
        msgs.append("✓ wired PostToolUse(AskUserQuestion) → post-ask.sh")

    if has_cmd("SessionStart", "decision-profile/session-check.sh"):
        msgs.append("· SessionStart already wired")
    else:
        groups("SessionStart").append({"hooks":[{"type":"command","command":session,"timeout":5}]})
        msgs.append("✓ wired SessionStart → session-check.sh")

elif mode == "unwire":
    for evt in ("PreToolUse","PostToolUse","SessionStart"):
        if drop_cmd(evt, "decision-profile/"):
            msgs.append(f"✓ removed {evt} hook")

os.makedirs(os.path.dirname(settings), exist_ok=True)
with open(settings, "w") as f:
    f.write(json.dumps(data, indent=2) + "\n")

for m in msgs:
    print("  " + m)
PY
}

# ---------------------------------------------------------------------------
# Daily-backup (launchd) — macOS only. Installs the backup scripts into STATE_DIR
# and a launchd agent that runs `sync-decisions.sh backup` daily at 03:00, silently
# (output appended to $BACKUP_DIR/sync.log). Idempotent: re-bootstraps each run.
# ---------------------------------------------------------------------------
install_daily_backup() {
  if [[ "$(uname -s)" != "Darwin" ]]; then
    skip "daily backup uses launchd (macOS only) — skipped on $(uname -s)"
    return
  fi

  # Backup scripts live alongside the profile data.
  copy_force "sync-decisions.sh" "$STATE_DIR/sync-decisions.sh"
  copy_force "daily-backup.sh"   "$STATE_DIR/daily-backup.sh"
  chmod 755 "$STATE_DIR/sync-decisions.sh" "$STATE_DIR/daily-backup.sh"
  ok "backup scripts → $STATE_DIR/"

  mkdir -p "$BACKUP_DIR" "$LAUNCH_AGENTS_DIR"

  # launchd does not expand ~ or env vars — bake the real $HOME into the plist.
  sed "s#HOME_PLACEHOLDER#$HOME_DIR#g" "$TPL/$PLIST_NAME.plist" > "$PLIST_DEST"

  # (Re)load the agent. bootout clears any stale copy; bootstrap (re)loads.
  if have launchctl; then
    local domain="gui/$(id -u)"
    launchctl bootout "$domain/$PLIST_NAME" >/dev/null 2>&1 || true
    if launchctl bootstrap "$domain" "$PLIST_DEST" >/dev/null 2>&1; then
      ok "daily backup scheduled (launchd, 03:00) → $PLIST_DEST"
    else
      fail "could not load launchd agent — load it manually: launchctl bootstrap $domain \"$PLIST_DEST\""
    fi
  else
    skip "launchctl not found — plist written to $PLIST_DEST but not loaded"
  fi
}

remove_daily_backup() {
  [[ "$(uname -s)" == "Darwin" ]] || return 0
  if have launchctl; then
    launchctl bootout "gui/$(id -u)/$PLIST_NAME" >/dev/null 2>&1 || true
  fi
  [[ -f "$PLIST_DEST" ]] && { rm -f "$PLIST_DEST"; ok "removed launchd agent → $PLIST_DEST"; }
  rm -f "$STATE_DIR/sync-decisions.sh" "$STATE_DIR/daily-backup.sh"
}

# ---------------------------------------------------------------------------
# Commands
# ---------------------------------------------------------------------------
install() {
  have python3 || { fail "python3 is required (ships with macOS Command Line Tools)"; exit 1; }
  log ""
  log "${BOLD}decision-profile — install${RESET}"
  log ""
  resolve_templates

  # 1. Skill bodies (overwrite).
  copy_force "SKILL.md" "$SKILLS_DIR/SKILL.md"
  ok "skill → $SKILLS_DIR/SKILL.md"
  copy_force "auto-answer/SKILL.md" "$AUTO_ANSWER_SKILLS_DIR/SKILL.md"
  ok "skill → $AUTO_ANSWER_SKILLS_DIR/SKILL.md"

  # 2. Hook scripts (overwrite + chmod).
  for h in "${HOOK_FILES[@]}"; do
    copy_force "hooks/$h" "$HOOKS_DIR/$h"
    chmod 755 "$HOOKS_DIR/$h"
  done
  ok "hooks → $HOOKS_DIR/"

  # 2b. Drop retired load-profile.sh script + its debug log if present.
  if [[ -f "$HOOKS_DIR/load-profile.sh" ]]; then
    rm -f "$HOOKS_DIR/load-profile.sh"
    ok "removed retired load-profile.sh (replaced by gate.sh)"
  fi
  if [[ -f "$STATE_DIR/load-profile-debug.log" ]]; then
    rm -f "$STATE_DIR/load-profile-debug.log"
    ok "removed retired load-profile-debug.log"
  fi

  # 2c. Armed-flag dir for auto-answer.
  mkdir -p "$ARMED_DIR"

  # 3. Scaffold user data files — NEVER overwrite.
  mkdir -p "$STATE_DIR" "$DOMAINS_DIR"
  if copy_absent "user-decisions-table.md" "$PROFILE"; then ok "scaffold → $PROFILE"; else skip "profile exists, kept → $PROFILE"; fi
  for f in "${STATE_FILES[@]}"; do
    if copy_absent "$f" "$STATE_DIR/$f"; then ok "scaffold → $STATE_DIR/$f"; else skip "exists, kept → $STATE_DIR/$f"; fi
  done

  # 3b. One-time profile split (lean hot file + per-domain shards). Safe no-op
  #     on an already-split or empty profile.
  if [[ -f "$PROFILE" && -f "$HOOKS_DIR/split-profile.sh" ]]; then
    out="$(bash "$HOOKS_DIR/split-profile.sh" 2>/dev/null | tail -n1 || true)"
    [[ -n "$out" ]] && ok "$out"
  fi

  # 4. Wire hooks into settings.json (idempotent).
  edit_settings wire

  # 5. Daily backup via launchd (macOS only).
  install_daily_backup

  log ""
  log "Installed."
  if [[ -f "$PROFILE" ]] && grep -q "No rules yet" "$PROFILE" 2>/dev/null; then
    log ""
    log "${BOLD}Next:${RESET} no profile yet — run ${CYAN}/decision-profile interview${RESET} in Claude Code to build one."
  else
    log ""
    log "Your existing profile was preserved."
  fi
  log ""
}

uninstall() {
  have python3 || { fail "python3 is required"; exit 1; }
  log ""
  log "${BOLD}decision-profile — uninstall${RESET} (hooks only; your data files are kept)"
  log ""
  edit_settings unwire
  remove_daily_backup
  [[ -d "$HOOKS_DIR" ]] && { rm -rf "$HOOKS_DIR"; ok "removed $HOOKS_DIR/"; }
  [[ -d "$SKILLS_DIR" ]] && { rm -rf "$SKILLS_DIR"; ok "removed $SKILLS_DIR/"; }
  [[ -d "$AUTO_ANSWER_SKILLS_DIR" ]] && { rm -rf "$AUTO_ANSWER_SKILLS_DIR"; ok "removed $AUTO_ANSWER_SKILLS_DIR/"; }
  log ""
  log "Kept your data: $PROFILE, $STATE_DIR/, and backups in $BACKUP_DIR/ (delete manually for a clean slate)."
  log ""
}

status_line() { # $1 label, $2 present(yes/no)
  if [[ "$2" == "yes" ]]; then printf "  %s✓%s %s\n" "$GREEN" "$RESET" "$1"
  else printf "  %s✗%s %s\n" "$RED" "$RESET" "$1"; fi
}
settings_has() { [[ -f "$SETTINGS" ]] && grep -q "$1" "$SETTINGS"; }

status() {
  log ""
  log "${BOLD}decision-profile — status${RESET}"
  log ""
  [[ -f "$SKILLS_DIR/SKILL.md" ]] && status_line "decision-profile skill installed" yes || status_line "decision-profile skill installed" no
  [[ -f "$AUTO_ANSWER_SKILLS_DIR/SKILL.md" ]] && status_line "auto-answer skill installed" yes || status_line "auto-answer skill installed" no
  settings_has "decision-profile/gate.sh"         && status_line "PreToolUse gate → gate.sh" yes        || status_line "PreToolUse gate → gate.sh" no
  settings_has "decision-profile/post-ask.sh"     && status_line "PostToolUse → post-ask.sh" yes        || status_line "PostToolUse → post-ask.sh" no
  settings_has "decision-profile/session-check.sh" && status_line "SessionStart → session-check.sh" yes || status_line "SessionStart → session-check.sh" no
  [[ -f "$PROFILE" ]] && status_line "profile file" yes || status_line "profile file" no
  if [[ "$(uname -s)" == "Darwin" ]]; then
    # Capture to a var first: `launchctl list | grep -q` lets grep close the pipe
    # early, killing launchctl with SIGPIPE → trips `set -o pipefail` → false ✗.
    local agents=""
    have launchctl && agents="$(launchctl list 2>/dev/null || true)"
    if [[ "$agents" == *"$PLIST_NAME"* ]]; then
      status_line "daily backup (launchd) loaded" yes
    else
      status_line "daily backup (launchd) loaded" no
    fi
  fi
  log ""
}

main() {
  local cmd="${1:-install}"
  case "$cmd" in
    install)   install ;;
    uninstall) uninstall ;;
    status)    status ;;
    *) log "Usage: decision-profile <install|uninstall|status>"; exit 1 ;;
  esac
}

main "$@"
