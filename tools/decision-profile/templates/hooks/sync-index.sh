#!/usr/bin/env bash
# decision-profile — sync-index.sh  (SAFE, RE-RUNNABLE)
#
# Rebuilds the domain index from whatever shard files currently exist:
#   - rewrites ~/.claude/decision-profile/domains/INDEX.md
#   - rewrites the "## Domain Index" block inside ~/.claude/user-decisions-table.md
#
# Run this after `/decision-profile update` or `review` edits the domain shards,
# so the hot file's index (slugs + row counts) stays accurate. It NEVER edits the
# Decision Principles / Decision Style blocks and NEVER deletes a shard — it only
# regenerates the listing. Reports any shard that exceeds the per-domain row cap
# so the digest step can prune it.
#
# Usage:
#   sync-index.sh                 default paths
#   sync-index.sh <profile.md>    specific profile file
#
# Two-tier per-domain row caps (rows are loaded one shard at a time, so the cap
# guards eviction aggression, not per-question cost):
#   soft (DP_DOMAIN_CAP, default 25)  — comfortable; ≤ soft = silent.
#   hard (DP_DOMAIN_HARD, default 40) — real bloat (usually near-dupes); must prune.
# Between soft and hard: warn so update/review prunes opportunistically (merge-first).
set -euo pipefail

PROFILE="${1:-${HOME}/.claude/user-decisions-table.md}"
CAP="${DP_DOMAIN_CAP:-25}"
HARD="${DP_DOMAIN_HARD:-40}"
case "$PROFILE" in
  "${HOME}/.claude/user-decisions-table.md")
    DOMAINS_DIR="${HOME}/.claude/decision-profile/domains" ;;
  *)
    DOMAINS_DIR="$(dirname "$PROFILE")/domains" ;;
esac

[ -f "$PROFILE" ] || { echo "sync-index: no profile at $PROFILE"; exit 0; }
[ -d "$DOMAINS_DIR" ] || { echo "sync-index: no domains dir at $DOMAINS_DIR (run split-profile.sh first)"; exit 0; }

PROFILE="$PROFILE" DOMAINS_DIR="$DOMAINS_DIR" CAP="$CAP" HARD="$HARD" python3 << 'PY'
import os, re, sys

profile = os.environ["PROFILE"]
ddir    = os.environ["DOMAINS_DIR"]
cap     = int(os.environ.get("CAP", "25"))
hard    = int(os.environ.get("HARD", "40"))

def domain_name(text):
    m = re.search(r"(?m)^## (.+)", text)
    return m.group(1).strip() if m else None

def count_rows(text):
    rows = 0
    for ln in text.splitlines():
        s = ln.strip()
        if not s.startswith("|"):
            continue
        cells = [c.strip() for c in s.strip("|").split("|")]
        if all(set(c) <= set("-: ") for c in cells):
            continue
        if cells and cells[0].lower() == "when":
            continue
        if any(cells):
            rows += 1
    return rows

index_lines = []
over_hard = []   # > hard: must prune this run
over_soft = []   # soft < rows <= hard: warn, prune opportunistically
for f in sorted(os.listdir(ddir)):
    if not f.endswith(".md") or f == "INDEX.md":
        continue
    text = open(os.path.join(ddir, f), encoding="utf-8").read()
    name = domain_name(text) or f[:-3]
    slug = f[:-3]
    rows = count_rows(text)
    if rows > hard:
        flag = " ⛔over-hard"
        over_hard.append((slug, rows))
    elif rows > cap:
        flag = " ⚠over-soft"
        over_soft.append((slug, rows))
    else:
        flag = ""
    index_lines.append(f"- `{slug}` ({rows} rows{flag}) — {name}")

listing = "\n".join(index_lines) if index_lines else "_No domain shards yet._"

# Rewrite INDEX.md
open(os.path.join(ddir, "INDEX.md"), "w", encoding="utf-8").write(
    "<!-- Auto-generated. One line per domain shard. Refresh with sync-index.sh.\n"
    "     To consult a domain's rules at runtime, Read decision-profile/domains/<slug>.md. -->\n\n"
    "# Domain Index\n\n" + listing + "\n"
)

# Rewrite the "## Domain Index" block in the hot file (replace from the marker to EOF
# or to the next "## " — the index is conventionally last, but handle either).
src = open(profile, encoding="utf-8").read()
marker = "## Domain Index"
new_block = (
    "## Domain Index\n\n"
    "<!-- domain-index: full rules for these domains live in\n"
    "     ~/.claude/decision-profile/domains/<slug>.md — Read the matching shard\n"
    "     only when a question needs that domain's specific rows. -->\n\n"
    + listing + "\n"
)

idx = src.find("\n" + marker)
if idx == -1 and src.startswith(marker):
    idx = 0
if idx == -1:
    # No marker yet (e.g. profile never split) — append it.
    out = src.rstrip("\n") + "\n\n" + new_block
else:
    head = src[:idx].rstrip("\n")
    # Find a following "## " after the marker, if any, to preserve trailing sections.
    after = src[idx + 1:]
    nxt = re.search(r"(?m)^## (?!Domain Index)", after[len(marker):])
    tail = ""
    if nxt:
        tail = after[len(marker) + nxt.start():]
    out = head + "\n\n" + new_block + (("\n" + tail) if tail.strip() else "")

out = re.sub(r"\n{3,}", "\n\n", out)
open(profile, "w", encoding="utf-8").write(out)

print(f"sync-index: {len(index_lines)} shard(s) indexed. caps: soft={cap} hard={hard}.")
if over_hard:
    print("sync-index: OVER HARD CAP — MUST prune this run (merge-first): " +
          ", ".join(f"{s}={r}>{hard}" for s, r in over_hard))
if over_soft:
    print("sync-index: over soft cap — prune opportunistically when redundant: " +
          ", ".join(f"{s}={r}>{cap}" for s, r in over_soft))
PY
