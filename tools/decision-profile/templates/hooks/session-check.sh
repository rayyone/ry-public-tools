#!/usr/bin/env bash
# decision-profile SessionStart hook.
# Emits a directive telling Claude to spawn a background subagent for `/decision-profile update` when:
#   (now - last_update) > 8h  AND  pending decision-log entries >= 10.
# Bash cannot call Claude, so it only signals; Claude spawns the subagent and announces it.
# Silent no-op otherwise.
set -euo pipefail

PROFILE="${HOME}/.claude/user-decisions-table.md"
LOG="${HOME}/.claude/decision-profile/user-manual-decided-log.md"

[ -f "$PROFILE" ] || exit 0
[ -f "$LOG" ] || exit 0

# Count pending log entries (lines starting with "- ["). grep exits non-zero on
# no-match, which under `set -e -o pipefail` would abort; guard with `|| true`.
PENDING=$( { grep -c '^- \[' "$LOG" 2>/dev/null || true; } | head -1 )
PENDING=${PENDING:-0}
[ "$PENDING" -ge 10 ] || exit 0

# Read last_update stamp from header. Empty stamp => due.
LAST=$(grep -m1 '^last_update:' "$PROFILE" 2>/dev/null | sed 's/^last_update:[[:space:]]*//' || echo "")

DUE=0
if [ -z "$LAST" ]; then
  DUE=1
else
  # Parse ISO-ish timestamp to epoch (try GNU then BSD date).
  LAST_EPOCH=$(date -d "$LAST" +%s 2>/dev/null || date -j -f "%Y-%m-%dT%H:%M:%S" "${LAST%%+*}" +%s 2>/dev/null || echo 0)
  NOW_EPOCH=$(date +%s)
  if [ "$LAST_EPOCH" -eq 0 ] || [ $((NOW_EPOCH - LAST_EPOCH)) -gt 28800 ]; then
    DUE=1
  fi
fi

[ "$DUE" -eq 1 ] || exit 0

printf '%s\n' "<decision-profile-due> ${PENDING} decision-log entries pending and >8h since last digest. Spawn a background subagent (model: sonnet, run_in_background: true) to run the /decision-profile update digest (refine rules, clear digested entries, stamp last_update). Before handling the user's request, print exactly one line: '[decision-profile] Updating decision profile in background (${PENDING} entries pending) — continuing with your request.' Then immediately handle the user's request without waiting for the subagent. </decision-profile-due>"
