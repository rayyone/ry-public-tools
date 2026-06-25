---
name: decision-profile
version: 1.4.0
description: "Build and refine your decision profile — model HOW you decide so the auto-answer skill can apply it. Params: interview [batch=N] [domain=<name>] | update | review | summary | (bare = coverage status). Applying the profile at runtime lives in the auto-answer skill, not here."
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - Glob
  - Grep
  - AskUserQuestion
triggers:
  - decision-profile
  - build my decision profile
  - interview my preferences
  - refine my decision profile
---

# decision-profile

**This skill BUILDS the profile. It does not apply it.** Authoring/refinement only — `interview`, `update`, `review`, `summary`. *Applying* the profile to live `AskUserQuestion` prompts (arming a session, never-ask, the runtime match logic, ⚡ output, the on/off master switch) lives in the sibling **`auto-answer`** skill. The two share one artifact: `~/.claude/user-decisions-table.md` — this skill writes it, auto-answer reads it.

Cut interruptions. Learn how the user decides, then apply it automatically when an `AskUserQuestion` would otherwise fire.

## File map (all under `~/.claude/`)

The profile is **split** to stay cheap: the hot file holds only the always-needed sections; each domain's table lives in its own shard, read on demand.

| File | Read at runtime? | Purpose |
|---|---|---|
| `~/.claude/user-decisions-table.md` | **YES** (hook injects it) | **Hot file.** ONLY: header (mode/role/last_update) + `## Decision Principles` + `## Decision Style` + a `## Domain Index` listing the shards. No other domain tables. Injected before every armed question — keep it lean. |
| `~/.claude/decision-profile/domains/<slug>.md` | On demand | **Domain shard.** One `## <Domain>` table per file. Read by the runtime ONLY when a question hits that domain. This is where role/topic rules live and where `update`/`review`/`interview` write them. |
| `~/.claude/decision-profile/domains/INDEX.md` | No (mirror) | Generated list of shards (slug · row count · domain name). Mirrored into the hot file's `## Domain Index`. Refresh with `sync-index.sh`. |
| `~/.claude/decision-profile/user-manual-decided-log.md` | No | Ring buffer of answered questions (max 200). Staging for `update`. Digested entries are removed. |
| `~/.claude/decision-profile/interviewed-questions-log.md` | No | Ledger of interview questions already asked, so the next batch is fresh. Written only by `interview` — `update` and `review` must not touch it. |
| `~/.claude/decision-profile/low-confident-answers-log.md` | No | LOW-confidence decisions forced silently in never-ask mode. For your later `review`. |

**Never** put logs into `user-decisions-table.md` or the shards. **Never** add a domain table back into the hot file — domain rules belong in `domains/<slug>.md`. The hot file holds only Principles + Decision Style + the index.

### The two helper scripts (under `~/.claude/hooks/decision-profile/`)

- **`split-profile.sh`** — one-time migration that carves a legacy monolithic profile into the hot file + shards. Safe no-op once split. You normally never run this by hand; the installer runs it.
- **`sync-index.sh`** — safe, re-runnable. Rebuilds `INDEX.md` + the hot file's `## Domain Index` from whatever shards exist, and **prints any shard over the per-domain row cap**. Run it at the end of every `interview`/`update`/`review` after you edit shards, via Bash: `bash ~/.claude/hooks/decision-profile/sync-index.sh`.

## Where to write a rule (hot file vs. shard)

Every rule lands in exactly one place:

- **`## Decision Style`** rule (engagement-style / stopping-rule — sets `Conf` globally) → write into the **hot file** `## Decision Style` table.
- **Any other domain** rule → write into that domain's **shard** `~/.claude/decision-profile/domains/<slug>.md`. If the shard doesn't exist yet, create it: a file whose only content is the `## <Domain>` header + the table schema + your row. Slug = domain name lowercased, non-alphanumerics → `-`.
- **`## Decision Principles`** (prose posture) → the **hot file** Principles block.

After writing any shard, run `sync-index.sh` so the hot file's `## Domain Index` and row counts stay accurate.

## Decision concepts — the lenses (read before interview / update / review)

This skill does not collect preferences; it models **how the user decides**. Every question you write, every answer you synthesize, and every rule you add or revise (interview *and* `update` *and* `review`) works through the same six lenses, drawn from decision-science research. They are the shared vocabulary of the whole skill — a rule is only good if it captures the user's behavior on one of these lenses.

| Lens | Source | What it captures | The probe it implies | How it becomes a rule |
|---|---|---|---|---|
| **Trade-off axis** | MAUT / preference elicitation | Where the user lands when two goods conflict (speed↔safety, breadth↔depth, cost↔correctness, velocity↔polish) | Force a pick between two genuinely-good options under a concrete trigger | `Decide` = which side wins, `When` = the trigger that forces the trade-off |
| **Means→ends** | Keeney, Value-Focused Thinking | The *fundamental objective* behind a surface choice — ask "why does that matter?" until it bottoms out | "Why is that important to you?" laddered up from a concrete choice | `Decide` encodes the **end**, not the surface pick, so it generalizes to new surfaces |
| **Engagement style** | Scott & Bruce, GDMS | How the user wants to be involved: decide-for-me / want-a-say / follow-convention / always-ask | "When X happens, do you want me to just do it, or be asked?" | Sets the rule's **Conf** directly (decide-for-me→HIGH, want-a-say→MEDIUM, always-ask→LOW; MEDIUM asks in normal mode) |
| **Stopping rule** | Maximizer vs. satisficer (Schwartz) | Optimal-or-bust vs. good-enough; how much search before committing | "Good-enough-and-ship, or keep optimizing until best?" | Calibrates auto-decide aggressiveness; recorded as a rule and as profile-wide default |
| **Threshold / trigger** | Value-Focused Thinking (objectives → measurable attributes) | The concrete, recognizable condition that flips the decision | "At what point does this stop being fine?" (>10 files, CVE with no patch, p95 > 200ms) | Becomes a sharp, testable `When` cell instead of a vague situation |
| **Stakeholder view** | Keeney device | Whose interest the user optimizes for when they conflict (user / team / future-maintainer / customer) | "When these parties pull apart, whose call wins?" | `Decide` names the winning stakeholder; `Why` records the others |

**Question-generation devices (Keeney) — use to *find* situations worth asking about, so questions aren't flat preference polls:** status-quo pain ("what about the current default annoys you?"), good/bad past choices ("recall a call you'd redo"), wish-list ("if no constraints, what would you always do?"), stakeholder perspectives. Each device surfaces a moment; then pick the lens that turns that moment into a rule.

## Two layers: precision (tables) + recall (principles)

The profile decides through **two layers**, read in order:

1. **`## Decision Principles`** — a short prose block (6–10 bullets) at the top of `user-decisions-table.md`, right after the header and before the first domain table. It encodes the user's *general decision posture* in one sentence each (bias-to-action, what outranks what, stopping rule, scope discipline). It is the **fallback / recall layer**: when a question matches **no** table row, decide from these instead of asking. This is what gives the profile coverage over the long tail of unseen questions without a row for every one.
2. **Domain tables** (`| When | Decide | Conf | Lens | Why |`) — the **precision layer**: sharp `When` triggers with explicit `Conf`. A matched row always wins over a principle.

Principles are distilled from the tables, not a substitute for them: they are the cross-cutting pattern that recurs across many rows (e.g. "customer-facing & data-integrity outrank internal/velocity"). `interview`, `update`, and `review` all keep them in sync — when several new rows express the same posture, lift it into a principle; when a principle is contradicted, fix it.

The block ends with the precedence line: **safety floor → matched table row → principles → ask.** Keep it under ~10 bullets so it stays cheap to inject on every question.

## Size discipline — caps + merge-first eviction

The profile is digested daily by `update`, so without a ceiling it balloons. But shards load **one at a time, on demand** — so a shard's row count is NOT a per-question token cost. The cap's real job is to bound **eviction aggression**: too low and the daily digest drops a still-valid sharp rule just to fit. So the cap is **two-tier and soft-biased** — prune on real redundancy, not on a number tripping. Enforce on **every** `interview`/`update`/`review`:

- **Per-domain soft cap: ~25 rows (`DP_DOMAIN_CAP`).** ≤25 = comfortable, do nothing. A domain where the user genuinely makes many distinct decisions (e.g. 23 rows) is signal, not bloat — don't prune it just for size.
- **Per-domain hard cap: ~40 rows (`DP_DOMAIN_HARD`).** >40 = real bloat, almost always near-duplicates. **Must** prune this run down toward soft.
- **Between soft and hard (26–40): prune opportunistically** — only fold rows that are genuinely redundant; otherwise leave them.
- **The bloat signal is near-duplicate rows, not row count.** Always prefer merge over evict:
  1. **Merge first.** Find the closest existing row (same `Lens` + overlapping `When`/`Decide`). Fold the new signal in — widen its `When`, sharpen its `Decide`, bump `Conf` if the new evidence agrees. No net row added.
  2. **Evict last.** Only over hard cap with nothing mergeable: drop the single **lowest-leverage** row — oldest, most generic (vague `When`), lowest-`Conf`, never corrected.
- **`## Decision Principles`: ≤10 bullets.** Distinct postures only. Merge or drop the weakest before exceeding.
- **`## Decision Style`: ≤12 rows.** Same merge-first rule.
- **Prefer generalization over accumulation.** Two rows expressing the same underlying objective on different surfaces → collapse into one means→ends row whose `Decide` names the end. This is the main lever that keeps the profile small without losing coverage.

`sync-index.sh` reports both tiers: `⛔over-hard` (must prune now) and `⚠over-soft` (prune if redundant). On `⛔over-hard`, prune that shard the same run via merge-first and re-run.

## Table schema (every domain)

```
## <Domain Name>
| When | Decide | Conf | Lens | Why |
|---|---|---|---|---|
```

- **When** — the trigger condition (Threshold lens makes this sharp).
- **Decide** — the rule-shaped action/choice (for Means→ends, write the *end*).
- **Conf** — HIGH = auto-decide silently · MEDIUM = ask (auto-decided only in never-ask mode) · LOW = ask. Engagement-style + Stopping-rule answers set this. (Runtime: in normal mode only HIGH auto-answers; MEDIUM and LOW both ask. never-ask mode auto-decides all three below the safety floor.)
- **Lens** — which lens(es) this rule encodes (e.g. `trade-off`, `means-ends`, `engagement`, `stopping`, `threshold`, `stakeholder`). Makes the technique persist into the table so `update`/`review`/dedup can reason on it.
- **Why** — the fundamental objective or reason; for trade-offs, what was traded away.

## Commands

Invoked as `/decision-profile [mode] [args]`. Bare = status.

### `/decision-profile interview [batch=N] [domain=<name>]`

Run (or re-run) the interview to enrich the profile.

#### First run only — role elicitation and domain bootstrap

Check `user-decisions-table.md` for the `role:` header line. If it is empty:

1. Ask the user (one `AskUserQuestion`): "What is your current job title / role? (e.g. Fullstack Engineer, Product Manager, Tech Lead, Data Scientist, Solo Founder…)". Free-text via Other is fine.
2. Write the answer into the `role: <value>` header in `user-decisions-table.md`.
3. Based on the role, generate **5–10 tailored decision domains** that are most relevant to that role. Think about the kinds of choices that person makes daily. Examples by role (not exhaustive — use judgment):
   - *Fullstack / Backend Engineer*: Code quality & patterns, Architecture & design, Testing strategy, Dependency & tooling, Deployment & ops, Cross-team communication
   - *Product Manager*: Scope & prioritization, Stakeholder management, Data & metrics, Release decisions, UX tradeoffs, Process & rituals
   - *Tech Lead*: Technical direction, Team process, Code review standards, Risk & velocity, Cross-team coordination, Hiring bar
   - *Data Scientist*: Modeling decisions, Data quality, Experiment design, Tooling & infra, Communication of results
   - *Solo Founder*: Build vs buy, Scope ruthlessness, Customer communication, Hiring & delegation, Risk appetite
4. Create each domain in the **split layout** (see **Where to write a rule**), using the **Table schema** below (`| When | Decide | Conf | Lens | Why |`):
   - **`## Decision Style`** lives in the **hot file** `user-decisions-table.md` (cross-cutting — holds Engagement-style + Stopping-rule rules, calibrates auto-decide everywhere). Seed it first, as an empty table under the existing `## Decision Style` header.
   - **Every role-specific domain + `general`** is a **shard file** `~/.claude/decision-profile/domains/<slug>.md`, each containing just its `## <Domain>` header + the empty table schema. Create the 5–10 role domains + a `general` shard (catch-all — always present).
   - Keep the hot-file `## Decision Principles` block at the top. If the template's generic starter principles are present, leave them — they'll be tailored from real answers once the first batches land. Don't delete the block.
   - Then **run `bash ~/.claude/hooks/decision-profile/sync-index.sh`** to populate the `## Domain Index`.
5. Report the domains created. Then proceed with the first question batch (steps below). For the **first** batch, weight it toward `## Decision Style` — establishing how the user wants to be engaged and when they stop searching makes every later rule's `Conf` more accurate.

If `role:` is already set, skip this bootstrap and go directly to the batch.

#### Every run — question batch

1. Read `interviewed-questions-log.md`. Collect every question already asked. Dedup is **semantic, not literal**: a candidate is a duplicate if it would elicit the same rule as a past question — same lens × same decision point × same trigger condition — even if worded differently. Reject "Do you prefer X or Y?" if any prior question already pins down where the user lands on that lens/axis. Only ask what is still genuinely unknown.
2. Read `domains/INDEX.md` for the domain list, then read the shard(s) for the domain(s) you're about to enrich (and the hot file for `## Decision Style`). Each existing rule is also a "known answer" — do not re-ask anything a current rule (its `When` + `Lens`) already encodes. Don't load every shard — only the ones in scope for this batch.
3. Choose the next batch:
   - Default batch size **12-16**. Override with `batch=N`.
   - **Each domain needs ≥10 rules before it is "covered."** Rotate across the user's domains; always prioritize the domain furthest below 10. Don't move on from a domain while it is under 10 rules unless every remaining unknown there fails the quality bar.
   - If `domain=<name>` given: ask only in that domain. If `<name>` doesn't exist yet, create a new shard `domains/<slug>.md` first, then ask.
   - No fixed grand total — keep enriching until every domain is ≥10 and the high-leverage unknowns are exhausted. Each run still asks one batch, then stops.
4. **Design each question through a lens (see Decision concepts above), then ask the batch with one `AskUserQuestion` call** (multiple questions in the array). 2–4 options each + the auto "Other".

   **A question is only worth asking if its answer becomes a table rule that improves a runtime auto-decision.** Before writing each one: (a) pick the **lens** it targets; (b) name the real, recurring decision the answer will let you make without interrupting the user, and what goes wrong today if you guess. If you can't name a lens *and* that failure mode, discard it. Then enforce:

   - **Pick a lens, not a topic.** Every question targets exactly one of the six lenses (trade-off / means-ends / engagement / stopping / threshold / stakeholder). Use a Keeney device (status-quo pain, good/bad past choice, wish-list, stakeholder view) to surface a concrete situation first, then the lens to shape it.
   - **Target a real decision, not a preference.** Anchor on a moment where the user must choose and guessing wrong costs them. "When a migration drops a column, require a backup step first?" beats "Do you care about data safety?" — first sets a rule, second sets a vibe.
   - **Capture the concept, not the surface.** For trade-off/means-ends lenses, aim at the underlying axis or fundamental objective. One question on the right axis generalizes to many future situations.
   - **Make it discriminating.** Options must split *this* user from a plausibly-different user. If almost everyone in the role answers the same, it teaches nothing — drop it.
   - **Make it trigger-bound.** Phrase the situation so the answer maps to a sharp `When` cell (threshold lens): a recognizable condition (">10 files", "dep has a CVE, no patch"), not "how do you usually…".
   - **Options mutually exclusive and rule-shaped.** Each option writable near-verbatim into a `Decide` cell. No "it depends" / "case by case" — those produce no rule.
   - **Highest-leverage unknown first.** Ask the question whose answer resolves the most future ambiguity. Engagement-style and stopping-rule questions are highest leverage early — they set `Conf` for everything.

   Sanity check the batch before sending: no two questions share the same lens × axis; none is already answered by `interviewed-questions-log.md` or an existing rule; each plausibly raises a real auto-decision from LOW → MEDIUM/HIGH.
5. **Synthesize** answers into rules — this is the core step, not the question. Each answer becomes a table row written to the right place (**Where to write a rule**): Engagement/Stopping answers → hot-file `## Decision Style`; everything else → its `domains/<slug>.md` shard.
   `| When | Decide | Conf | Lens | Why |`
   - **When** ← the trigger from the question (sharpen it via the threshold lens).
   - **Decide** ← the rule-shaped action. For **means→ends** questions, write the *fundamental objective* the answer revealed (the "why"), not the surface option — so it generalizes.
   - **Lens** ← the lens the question targeted (carry it through verbatim).
   - **Conf** ← set from the **engagement-style / stopping-rule** signal: decide-for-me / optimal-is-not-required → HIGH; want-a-say / conditional-involvement → MEDIUM; always-ask / conditional → LOW. Absent that signal, HIGH when unambiguous + broadly applicable, MEDIUM when conditional. (Reminder: MEDIUM asks in normal mode — reserve HIGH for rules safe to auto-answer unattended.)
   - **Why** ← fundamental objective, or what was traded away.
   - **Honor the per-domain caps (soft ~25 / hard ~40): merge-first, evict only over hard** (see **Size discipline**). If a domain doesn't clearly fit, write to the `general` shard.
   - **Refresh `## Decision Principles`** (hot file). After adding the batch's rows, scan for a posture that now recurs across ≥3 rows in different domains (same trade-off side, same stakeholder winning, same stopping rule). If it isn't already a principle, lift it into a one-sentence bullet. If a new high-Conf rule contradicts an existing principle, fix the principle. Keep the block ≤10 bullets — merge or drop the weakest before exceeding.
6. Append the asked questions to `interviewed-questions-log.md` (one line each: `- [date] [domain] (lens: <lens> | axis: <decision concept>) <question>`). The `lens` + `axis` tags are what the next run's semantic dedup (step 1) matches on — so it dedups by concept, not wording.
7. **Run `bash ~/.claude/hooks/decision-profile/sync-index.sh`** to refresh the index + row counts; prune any `⛔over-hard` shard (merge-first) and re-run.
8. Report: rules added per domain, which domains are now ≥10 vs. still under, lenses exercised, suggest re-running to finish under-covered domains.

Re-runnable. Each run enriches. Add a brand-new domain anytime via `domain=`.

### `/decision-profile update`

Digest the decision log into refined rules. Auto-fires via SessionStart hook (see below); can also be run manually.

**Do NOT write to `interviewed-questions-log.md`.** That file is owned exclusively by `interview`. `update` reads `user-manual-decided-log.md` and writes to the hot file `user-decisions-table.md` (Principles + Decision Style only), the relevant `domains/<slug>.md` shards, and `user-manual-decided-log.md`.

1. Read `user-manual-decided-log.md`.
2. Read `domains/INDEX.md` (or the hot file's `## Domain Index`) to see which domains exist. **Read only the shard(s)** whose domain a log entry plausibly belongs to — never load every shard. Read the hot file for Principles + Decision Style.
3. Analyze entries through the **same six lenses** (see Decision concepts). Look for: a repeated trade-off resolution (the user keeps picking one side of an axis), a recurring trigger/threshold, an engagement-style signal (they keep overriding your auto-decision → they want to be asked; they keep accepting it → raise Conf), a means→ends pattern (different surface choices, same underlying objective), contradictions with existing rules.
4. For each clear pattern: add or **modify** a row, writing it to the right place (see **Where to write a rule**) — Decision Style → hot file; any other domain → its `domains/<slug>.md` shard. Tag the `Lens`. **Honor the per-domain caps (soft ~25 / hard ~40): merge-first, evict only over hard** (see **Size discipline**) — prefer folding the new signal into an existing row over adding one.
   - Express means→ends patterns as the **fundamental objective** in `Decide`, not the surface choices.
   - Adjust `Conf` from the engagement signal: consistent acceptance → raise; repeated override → lower (or flip to always-ask).
   - Resolve contradictions in favor of the newer, more frequent choice.
   - If the rule doesn't fit any existing domain: infer a concise domain name and **create a new shard** `domains/<slug>.md` (header + table schema + the row). Report the new domain. (Engagement/stopping patterns → hot-file `## Decision Style`.)
   - If genuinely domain-ambiguous: add to the `general` shard.
5. **Refresh `## Decision Principles`** (hot file) from the digested patterns: a posture the user repeats across multiple domains becomes (or strengthens) a bullet; a principle the log repeatedly contradicts gets fixed or dropped. Keep ≤10 bullets and keep the precedence line last.
6. **Remove the digested entries** from `user-manual-decided-log.md`. Keep too-ambiguous-to-digest entries for next time.
7. Stamp `last_update: <ISO date-time>` in the hot-file header.
8. **Run `bash ~/.claude/hooks/decision-profile/sync-index.sh`** to refresh the index + row counts. If it prints `⛔over-hard`, prune those shards now (merge-first) and re-run it; `⚠over-soft` only if redundant.
9. Report rules changed, lenses touched, principles changed, new/pruned domains, and any shards still over cap.

### `/decision-profile review`

Walk the never-ask log so you can correct silent low-confidence calls.

**Do NOT write to `interviewed-questions-log.md`.** That file is owned exclusively by `interview`. `review` reads `low-confident-answers-log.md` and writes to the hot file (Principles + Decision Style only), the relevant `domains/<slug>.md` shards, and `low-confident-answers-log.md`.

1. Read `low-confident-answers-log.md`. For each **unreviewed** entry, show the user: question, the decision you made, your reason.
2. Read `domains/INDEX.md` to know which domains exist; read only the shard(s) a correction touches. Read the hot file for Principles + Decision Style.
3. Collect the user's comment per case ("good" / "should have been X" / "always do Y in this situation"). A correction is an **engagement-style signal**: "good" → the auto-decide was right, safe to raise `Conf`; "should have been X" → wrong rule, fix the `Decide`; "always ask me here" → set this case to LOW/always-ask.
4. Apply through the lenses: add or modify the matching row, written to the right place (**Where to write a rule**) — Decision Style → hot file; other domains → `domains/<slug>.md`. Honor the cap (merge-first, evict-last).
   - Tag the `Lens`. If the user revealed an underlying objective ("X because I always protect Y"), write the **end** (means→ends), not just the surface fix.
   - Set `Conf` from the correction per step 3.
   - If the rule doesn't fit any existing domain: infer a concise domain name and create a new shard `domains/<slug>.md`. Report the new domain. (Engagement/stopping corrections → hot-file `## Decision Style`.)
   - If genuinely domain-ambiguous: add to the `general` shard.
   - If a correction reveals a wrong *general posture* (the bad silent call came from a principle, not a row), fix the offending hot-file `## Decision Principles` bullet — not just the row.
5. **Remove reviewed entries** from `low-confident-answers-log.md`.
6. **Run `bash ~/.claude/hooks/decision-profile/sync-index.sh`**; prune any `⛔over-hard` shard (merge-first) and re-run.
7. Report what changed, lenses touched, principles changed, new/pruned domains.

### `/decision-profile summary`

Mirror the profile back to the user in plain language so they can sanity-check that it reflects how they actually decide — then correct it if it doesn't.

**Read-only until the user asks for a change.** This command reads `user-decisions-table.md`. It writes to it **only** after the user identifies something to fix. It must **not** touch `interviewed-questions-log.md`, `user-manual-decided-log.md`, or `low-confident-answers-log.md`.

1. Read the hot file `user-decisions-table.md` (header + `## Decision Principles` + `## Decision Style` + `## Domain Index`) and **every shard** under `decision-profile/domains/` (summary is the one command that legitimately reads them all — it's an explicit, user-invoked audit, not a per-question path).
2. **Distill, don't dump.** Synthesize the dense rules into a concise prose portrait of *how this user decides* — not a row-by-row reprint. Organize through the six lenses (trade-off axis / means-ends / engagement style / stopping rule / thresholds / stakeholder view): where they consistently land on the recurring trade-offs, whose interest tends to win, how much they want to be involved (decide-for-me vs. confirm vs. always-ask), how aggressively they ship vs. optimize, and the sharp triggers that flip their decisions. Group across domains — surface the cross-cutting posture, collapse near-duplicate rules into one statement. Aim for a tight, readable digest (roughly 8–15 bullets / a few short paragraphs), not the full table.
   - Lead with the `## Decision Principles` (the user's general posture), then the strongest per-domain patterns under it.
   - Call out anything that looks **inconsistent or thin** explicitly: contradictory rules, a domain with almost no coverage, a HIGH-confidence rule that seems aggressive. These are the things most worth the user's correction.
3. Present the portrait, then ask (one `AskUserQuestion`): does this accurately reflect how you make decisions, or is something off?
   - Options shaped like: "Accurate — leave as is" / "Something's off — let me correct it" (+ auto Other for free-text).
   - If **accurate / leave as is**: change nothing. Report that the profile was left untouched. Done.
4. If the user flags something off, collect their correction in free text ("I actually always ask before X", "drop the rule that says Y", "I lean the other way on speed-vs-safety"). Treat each correction through the lenses, exactly like `review` does:
   - **"I lean the other way" / "should be X"** → fix the offending `Decide` cell (or the `## Decision Principles` bullet if the bad posture is a principle, not a row).
   - **"always ask me here"** → set that rule's `Conf` to LOW.
   - **"I'm fine auto-deciding that"** → raise `Conf`.
   - **"that rule is wrong / remove it"** → delete the row.
   - **a missing pattern** → add a new row (or principle) in the right domain.
   - If a correction reveals an underlying objective ("X because I always protect Y"), write the **end** (means→ends), not just the surface fix. Tag the `Lens` on any row you add or change.
5. Apply the edits to `user-decisions-table.md`. Re-summarize **only the parts that changed** and confirm with the user. Loop steps 3–5 until the user says it's accurate.
6. If any edits were made, stamp `last_update: <ISO date-time>` in the header. Report what changed (rules/principles edited, added, removed; lenses touched). If nothing changed, say so.

This is a read-and-reflect command, not an enrichment one — it does not generate new interview questions or digest logs. Its job is to let the user audit the profile against their own self-image and fix drift.

### `/decision-profile` (bare)

Coverage status only (build-side). Read `domains/INDEX.md` (it already carries the per-domain row counts) + the hot file's `## Decision Style`. Print: rule count per domain **with a ≥10 coverage flag** (covered vs. under) **and an over-cap flag (soft ~25 / hard ~40)**, total rules, last interview date, pending decision-log count, undigested-since-update count, `last_update`. (Runtime state — armed sessions, never-ask mode, the on/off master switch — is reported by `/auto-answer status`, not here.)

## Runtime is owned by `auto-answer`

This skill does **not** decide questions. When a session is armed (`/auto-answer on`), the `auto-answer` skill + its `gate.sh` hook read the profile this skill produced and do the matching, the never-ask handling, the safety floor, and the ⚡ output. See the `auto-answer` skill for all of that. Everything below here is build-side only.

The two things this skill still owns at runtime-adjacent moments:

- **Auto-logging answered questions** (feeds `update`). This is done by the `post-ask.sh` PostToolUse hook automatically — every answered `AskUserQuestion` is appended to `user-manual-decided-log.md` (max 200, ring buffer). You don't do this by hand.
- **Auto-update digest** (below).

## Auto-update (SessionStart)

The SessionStart hook checks: if `now - last_update > 8h` **and** pending decision-log entries `>= 10`, it injects a directive telling you to run `/decision-profile update` at the start of the session.

When the directive is present, **spawn a background subagent** to run the update — do NOT run it inline in the main session. This keeps the user's actual request uninterrupted.

Exact steps:

1. Spawn an Agent call with `run_in_background: true`, `model: "sonnet"`, and a self-contained prompt that instructs the subagent to:
   - Read `~/.claude/decision-profile/user-manual-decided-log.md`, the hot file `~/.claude/user-decisions-table.md`, and `~/.claude/decision-profile/domains/INDEX.md` — then only the shard(s) each log entry touches
   - Perform the full `/decision-profile update` digest (synthesize rules into the correct shard / hot-file section, honor the per-domain cap with merge-first eviction, refresh Decision Principles, remove digested entries, stamp `last_update`)
   - Run `bash ~/.claude/hooks/decision-profile/sync-index.sh` and prune any `⛔over-hard` shard (merge-first)
   - Return a one-line summary of what changed

2. Print exactly one line to the user **before** handling their prompt:
   `[decision-profile] Updating decision profile in background (N entries pending) — continuing with your request.`

3. Immediately proceed with the user's actual request without waiting for the subagent.

The subagent result arrives asynchronously and is not shown to the user unless they ask. If the directive is absent, do nothing.

## Install-once / non-override

- If `~/.claude/user-decisions-table.md` is **absent**, prompt the user once: "No decision profile yet — run `/decision-profile interview` to build one."
- If profile files already exist, **never overwrite** them. Only append/modify per the commands above.

## Format rules

- **Hot file `user-decisions-table.md` stays ~120 lines max.** It holds ONLY: header + `## Decision Principles` + `## Decision Style` + `## Domain Index`. No other domain tables, no log content. This is the file injected on every armed question — its size is the per-question token cost, so guard it hard.
- **Each domain shard `domains/<slug>.md`: soft cap ~25 rows, hard cap ~40** (`DP_DOMAIN_CAP` / `DP_DOMAIN_HARD`). One `## <Domain>` table per file. Merge-first always; evict only over hard (see **Size discipline**). `sync-index.sh` flags both tiers.
- `## Decision Principles` lives at the top of the hot file (after header, before `## Decision Style`): ≤10 one-sentence bullets + the precedence line. Keep it terse — `auto-answer` injects the whole hot file on every question in an armed session.
- `## Decision Style` ≤12 rows. `## Domain Index` is generated — never hand-edit it; run `sync-index.sh`.
- `user-manual-decided-log.md`: max 200 entries, ring buffer.
- All dates absolute (ISO), never relative.
- Profile header fields: `role:`, `last_update:` (owned by this skill) and `mode:` (`normal` | `never-ask`), `auto_decide:` (`on` | `off`, default on) (the runtime switches — set by `/auto-answer never-ask|on|off`, read by `auto-answer` at runtime; they live in this same header file but this skill only preserves them, it doesn't toggle them).
