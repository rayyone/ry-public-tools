#!/usr/bin/env bash
# auto-answer gate — PreToolUse hook (matcher: AskUserQuestion).
#
# This REPLACES auto-decide's always-on load-profile.sh. The decision profile
# is no longer injected on every question. Instead it is injected ONLY when the
# current Claude Code session has been explicitly ARMED by the user via the
# `auto-answer` skill (which writes a per-session flag file).
#
#   Unarmed session  -> exit 0, silent. AskUserQuestion fires normally. The user
#                       answers it themselves. (Default — non-intrusive.)
#   Armed session     -> behave exactly like the old load-profile.sh: deny the
#                       pending question and feed the profile back so the model
#                       auto-decides (emit ⚡) or genuinely re-asks.
#
# Arm scope is the Claude Code session: the flag is keyed by session_id, so it
# auto-clears when a new session starts. Re-arm each session you want it in.
#
# No-op (silent, exit 0) if: profile absent, no session armed, or stdin lacks a
# session_id.
set -euo pipefail

PROFILE="${HOME}/.claude/user-decisions-table.md"
ARM_DIR="${HOME}/.claude/auto-answer/armed"

[ -f "$PROFILE" ] || exit 0

# Read the hook payload from stdin to learn which session we're in.
INPUT="$(cat)"
[ -n "$INPUT" ] || exit 0

# Extract session_id without a jq dependency.
SESSION_ID="$(SID_INPUT="$INPUT" python3 -c '
import json, os, sys
try:
    p = json.loads(os.environ["SID_INPUT"])
except Exception:
    sys.exit(0)
sid = p.get("session_id") or ""
print(sid)
' 2>/dev/null || true)"

[ -n "$SESSION_ID" ] || exit 0

# Armed only if this session has a flag file. Not armed -> passthrough.
[ -f "${ARM_DIR}/${SESSION_ID}" ] || exit 0

# ---- ARMED: inject the profile and deny, same payload as the old hook. ----

# Hot payload: the profile is split into a lean hot file (this PROFILE) + per-domain
# shard files under decision-profile/domains/. The hot file holds only the always-hot
# sections — ## Decision Principles, ## Decision Style, and the ## Domain Index — so we
# inject ALL of their content (rows included). For any OTHER section that may still be
# inline (a profile not yet migrated by split-profile.sh), strip its table rows and keep
# just the header, exactly like the legacy behavior, so the payload stays lean either way.
TRIMMED="$(awk '
  /^## / {
    print
    keep_rows = ($0 == "## Decision Principles" || $0 == "## Decision Style" || $0 == "## Domain Index")
    next
  }
  keep_rows { print; next }
  $0 !~ /^\|/ { print }
' "$PROFILE")"

MODE="$(awk -F': ' '/^mode:/ {print $2; exit}' "$PROFILE")"
MODE="${MODE:-normal}"

REASON="$(cat <<EOF
STOP — auto-answer is ARMED for this session and a decision profile is loaded (mode: ${MODE}). Do NOT ask yet. For EACH question below, match it against this profile first.

${TRIMMED}

The ## Domain Index above lists every domain shard (slug + topic). Full per-domain rules live in ~/.claude/decision-profile/domains/<slug>.md — Read ONLY the one shard whose topic matches a question that needs a specific row. Do not read the whole profile or multiple shards; one targeted shard Read at most, and only when Principles + Decision Style above don't already resolve the question.

Decision rule per question:
- Matches a HIGH-conf row OR a clear principle, AND is NOT under the safety floor (irreversible / destructive / security / architecture fork / data-model change / breaking-API) → do NOT re-call AskUserQuestion for it. Emit the ⚡⚡⚡⚡⚡ auto-decision block and proceed. The block is EXACTLY 2 lines between the ⚡ fences: Line 1 = the verbatim question text (MANDATORY — never omit it; emit one full block per question, never collapse multiple into one decision line), Line 2 = "[CONF] → decision". Emitting only the decision line is a bug.
- mode is "${MODE}": if never-ask, MEDIUM/LOW questions also decide silently (log LOW to low-confident-answers-log.md) unless the safety floor applies.
- ONLY re-call AskUserQuestion for questions that genuinely hit the safety floor or have no usable row/principle match.

If you re-call AskUserQuestion, include ONLY the still-unresolved questions, not the ones you just auto-decided.
EOF
)"

REASON="$REASON" python3 -c '
import json, os
print(json.dumps({
    "hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "deny",
        "permissionDecisionReason": os.environ["REASON"],
    }
}))
'
exit 0
