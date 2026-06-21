---
name: auto-answer
version: 2.0.0
description: "Apply your decision profile to live AskUserQuestion prompts. Opt-in per session: arm THIS session, then routine questions are auto-answered (⚡) from the profile; unarmed = questions reach you normally. Params: on (bare = on) | off | never-ask on|off | enable|disable | status. Profile is BUILT by the decision-profile skill."
allowed-tools:
  - Bash
  - Read
triggers:
  - auto-answer
  - auto answer
  - decide for yourself
  - decide for me
  - answer for me
  - use my decision profile
  - never-ask mode
  - stop asking me this session
---

# auto-answer

**This skill APPLIES the decision profile. It does not build it.** The profile (`~/.claude/user-decisions-table.md`) is authored by the sibling **`decision-profile`** skill (`interview`, `update`, `review`, `summary`). This skill is the runtime side: it decides *whether* and *how* a live `AskUserQuestion` is auto-answered from that profile.

**Opt-in per session.** By default every question reaches you normally — nothing is intercepted. Run `/auto-answer` (or "decide for yourself") to **arm the current session**; from then until the session ends or you disarm, routine questions are auto-answered (⚡) from the profile. The safety floor always asks regardless.

## Mechanism

- Arm flag: `~/.claude/auto-answer/armed/<session_id>` (marker file holding the arm timestamp).
- `session_id` = the `CLAUDE_CODE_SESSION_ID` env var (available to this skill's Bash), which equals the `session_id` the gate hook reads from its stdin payload. Same key on both sides.
- PreToolUse:AskUserQuestion gate hook `~/.claude/hooks/decision-profile/gate.sh`: armed → inject the profile + deny the pending call so the model re-decides (this Runtime section). Unarmed → exit 0, the question fires normally.
- Session-scoped by construction: a new session has a new `session_id`, so no stale flag carries over. Re-arm each session you want it.

## Commands

Invoked as `/auto-answer [on|off|never-ask on|off|enable|disable|status]`. Bare = `on` (arm this session).

### `/auto-answer on`  (also: bare `/auto-answer`, "decide for yourself", "answer for me")

Arm this session. Routine `AskUserQuestion` prompts are now auto-answered from the profile until the session ends or you run `off`.

Run exactly this (one Bash call):

```bash
SID="${CLAUDE_CODE_SESSION_ID:-}"
if [ -z "$SID" ]; then echo "no CLAUDE_CODE_SESSION_ID — cannot arm this session"; exit 1; fi
if [ ! -f "$HOME/.claude/user-decisions-table.md" ]; then
  echo "no decision profile yet — run /decision-profile interview first"; exit 1
fi
mkdir -p "$HOME/.claude/auto-answer/armed"
date -u +%Y-%m-%dT%H:%M:%SZ > "$HOME/.claude/auto-answer/armed/$SID"
echo "auto-answer ARMED for session $SID"
```

Then tell the user: auto-answer is on for this session; routine questions are auto-answered from the profile, safety-floor questions still asked; `/auto-answer off` to stop.

### `/auto-answer off`  (also: "stop auto-answering", "let me decide")

Disarm this session. Questions reach you normally again.

```bash
SID="${CLAUDE_CODE_SESSION_ID:-}"
if [ -z "$SID" ]; then echo "no CLAUDE_CODE_SESSION_ID"; exit 1; fi
rm -f "$HOME/.claude/auto-answer/armed/$SID"
echo "auto-answer DISARMED for session $SID"
```

Then tell the user auto-answer is off; they'll be asked normally again.

### `/auto-answer never-ask on|off`

Toggle never-ask mode. Stored as `mode: never-ask` / `mode: normal` in the profile header (`~/.claude/user-decisions-table.md`). Affects only **armed** sessions; the safety floor always holds.

- **on** — in an armed session, LOW-confidence routine questions are decided silently (and logged to `low-confident-answers-log.md`) instead of interrupting.
- **off** — LOW-confidence questions are asked normally again.

Edit the header line in place (Bash, no Edit/Write diff noise):

```bash
PROFILE="$HOME/.claude/user-decisions-table.md"
VAL="$1"   # on|off
MODE=$([ "$VAL" = on ] && echo never-ask || echo normal)
if grep -q '^mode:' "$PROFILE"; then
  sed -i '' "s/^mode:.*/mode: $MODE/" "$PROFILE" 2>/dev/null || sed -i "s/^mode:.*/mode: $MODE/" "$PROFILE"
else
  printf 'mode: %s\n' "$MODE" >> "$PROFILE"
fi
echo "never-ask: $MODE"
```

### `/auto-answer enable` / `/auto-answer disable`  (master switch)

Toggle the profile master switch. Stored as `auto_decide: on` / `auto_decide: off` in the profile header.

- **disable** — even when a session is armed, never auto-answer: every `AskUserQuestion` fires normally as if no profile existed. Overrides arming and never-ask. The profile is preserved, just never consulted.
- **enable** — restore normal armed behavior. (Default; an omitted header line = enabled.)

```bash
PROFILE="$HOME/.claude/user-decisions-table.md"
VAL="$1"   # enable|disable
FLAG=$([ "$VAL" = disable ] && echo off || echo on)
if grep -q '^auto_decide:' "$PROFILE"; then
  sed -i '' "s/^auto_decide:.*/auto_decide: $FLAG/" "$PROFILE" 2>/dev/null || sed -i "s/^auto_decide:.*/auto_decide: $FLAG/" "$PROFILE"
else
  printf 'auto_decide: %s\n' "$FLAG" >> "$PROFILE"
fi
echo "auto_decide: $FLAG"
```

### `/auto-answer status`

Report the full runtime state: armed-or-not for this session, never-ask mode, master switch.

```bash
SID="${CLAUDE_CODE_SESSION_ID:-}"
PROFILE="$HOME/.claude/user-decisions-table.md"
MODE=$(grep -m1 '^mode:' "$PROFILE" 2>/dev/null | sed 's/^mode:[[:space:]]*//'); MODE=${MODE:-normal}
SW=$(grep -m1 '^auto_decide:' "$PROFILE" 2>/dev/null | sed 's/^auto_decide:[[:space:]]*//'); SW=${SW:-on}
if [ -f "$HOME/.claude/auto-answer/armed/$SID" ]; then
  echo "session: ARMED (since $(cat "$HOME/.claude/auto-answer/armed/$SID"))"
else
  echo "session: not armed — questions reach you normally"
fi
echo "never-ask mode: $MODE"
echo "master switch (auto_decide): $SW"
```

Report plainly. (Build-side coverage — rule counts per domain — is `/decision-profile` bare, not here.)

## Runtime behavior — how to apply the profile when a question arises (ARMED sessions only)

The gate hook injects the hot file (`## Decision Principles` + `## Decision Style` + the `## Domain Index`) and denies the pending `AskUserQuestion` only when this session is armed. So this whole section runs **only in an armed session**. **If the profile header contains `auto_decide: off`, skip all matching below and call `AskUserQuestion` directly** (master switch off). Otherwise, match the situation: first against the injected Principles + Decision Style, then — only if a question needs a domain-specific row — against that domain's shard. Match on the `When` trigger, read the `Lens` to apply the rule correctly (a `means-ends` rule's `Decide` is an *objective* — honor the objective even if the surface choice differs; an `engagement` rule in `## Decision Style` tells you *whether* to auto-decide at all). The matched row's `Conf` drives the behavior.

The profile is **split**: the hot file holds only Principles + Decision Style + the Domain Index; each domain's full table is a shard at `~/.claude/decision-profile/domains/<slug>.md`. When (and only when) Principles + Decision Style don't resolve a question, look at the injected `## Domain Index`, pick the one matching shard by topic, and `Read` it. **Read at most one shard per question** — never load the whole profile or multiple shards. If the hot file alone resolves it, read no shard.

**Never output internal match-reasoning.** Do not narrate which row matched, which domain, or what confidence. Skip straight to the ⚡ output block (auto-answered) or the `AskUserQuestion` call (genuine re-ask). The user only needs the outcome.

- **HIGH confidence match** → auto-answer silently. Do **not** call AskUserQuestion. Emit ⚡ output (format below).
- **MEDIUM confidence match** → in normal mode: suggest the predicted answer and ask a short confirm, emitting the suggestion as ⚡ output. In never-ask mode: decide silently, emit ⚡ output, log to `low-confident-answers-log.md`.
- **No matching row** → fall back to `## Decision Principles`. If a principle clearly resolves the question and it is **not** under the safety floor, auto-answer and emit ⚡ output. If the principles only lean (don't decide cleanly), treat as MEDIUM and confirm. If neither row nor principle applies, or it's high-stakes → ask normally.
- **LOW confidence / high-stakes** → in normal mode: ask normally. In never-ask mode: decide silently, emit ⚡ output, log to `low-confident-answers-log.md`.

Precedence, in order: **`auto_decide: off` (skip all, always ask) → safety floor (always ask) → matched table row (by its Conf) → Decision Principles → ask.** A row always beats a principle; a principle beats asking only when it resolves the question and the safety floor is clear.

### Safety floor (overrides never-ask, overrides arming)

These categories **always** ask the user, even armed, even in never-ask mode, even at HIGH confidence:
- Irreversible actions (data deletion, `rm -rf`, dropping tables, history rewrites/force-push).
- Destructive or wide-blast-radius changes.
- Security-relevant decisions (auth, secrets, permissions, exposure).
- Architecture forks, data-model changes, breaking API changes.

### never-ask mode (`mode: never-ask`)

When on AND armed AND the situation is **not** under the safety floor: HIGH, MEDIUM, and LOW-confidence questions are all decided silently. Pick the most-likely answer (prefer what `## Decision Principles` implies), proceed, emit ⚡ output, and append to `low-confident-answers-log.md` using a **Bash append** (never Edit/Write — avoids diff output in UI):

```bash
LOG="$HOME/.claude/decision-profile/low-confident-answers-log.md"
printf -- '- [<date-time>] [<domain>] Q:"<question>" -> DECIDED:"<answer>" | conf:<HIGH|MEDIUM|LOW> | reason:"<why>" | review: [ ]\n' >> "$LOG"
```

Substitute the actual values before running. Use `date -u +%Y-%m-%dT%H:%M:%SZ` for the timestamp. (`/decision-profile review` later walks this log so you can correct silent calls.)

### Auto-decision output format

Used for all auto-answers (HIGH always; MEDIUM/LOW in never-ask mode; principle-based). Emit exactly 2 lines wrapped with 5 ⚡ symbols on each side:
- Line 1 (**MANDATORY — never omit**): the verbatim question text that was about to be asked. Without it the user has no idea what was decided. If multiple questions were auto-answered, emit one full ⚡-wrapped 2-line block **per question** — never collapse them into a single decision line.
- Line 2: `[CONF_LEVEL] → <decision>`

Both lines are required. Emitting only Line 2 (the decision) is a bug — the question line is the whole point of the block. Nothing else beyond these 2 lines — no log mention, no match reasoning, no extra explanation.

Example:
⚡⚡⚡⚡⚡
Real-time notification service: WebSockets vs SSE, no codebase precedent
[LOW] → Recommend WebSockets for bidirectional needs; present 2-option brief
⚡⚡⚡⚡⚡

## Relationship to decision-profile

| Concern | Owner |
|---|---|
| Building / refining the profile + principles (interview/update/review/summary) | **`decision-profile`** |
| Logging answered questions (feeds `update`), the SessionStart update digest | `decision-profile` hooks (`post-ask.sh`, `session-check.sh`) |
| **Whether & how the profile is applied to a live question** (arm, never-ask, master switch, runtime match, ⚡ output, safety floor) | **`auto-answer` (this skill) + `gate.sh`** |

One artifact, two skills: `decision-profile` writes `user-decisions-table.md`; `auto-answer` reads it (only when armed). The `mode:` and `auto_decide:` header fields physically live in that file but are *this* skill's switches — `decision-profile` only preserves them.

## Notes

- If no profile exists, `on` refuses and points to `/decision-profile interview`.
- Stale flags from crashed sessions are harmless (that `session_id` never recurs) but accumulate as tiny files; `gate.sh` and the installer don't depend on cleanup. Safe to `rm -rf ~/.claude/auto-answer/armed` anytime.
