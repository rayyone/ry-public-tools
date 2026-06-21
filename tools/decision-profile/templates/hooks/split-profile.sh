#!/usr/bin/env bash
# decision-profile — split-profile.sh  (ONE-TIME MIGRATION)
#
# Migrates a legacy monolithic profile into the two-file layout that keeps the
# profile from ballooning:
#
#   ~/.claude/user-decisions-table.md            HOT FILE — injected on every armed
#                                                 question. Holds ONLY: front-matter,
#                                                 ## Decision Principles, ## Decision Style,
#                                                 and the ## Domain Index marker block.
#   ~/.claude/decision-profile/domains/<slug>.md  SHARD — one role/topic domain table each.
#                                                 Read on demand, only when a question hits
#                                                 that domain.
#   ~/.claude/decision-profile/domains/INDEX.md   INDEX — one line per shard (slug | rows | hint).
#
# THIS IS A MIGRATION, NOT A SYNC. It runs once to carve a fat profile apart.
# After the split, domain rules live in the shards and are edited there directly
# (by `/decision-profile update`/`review`). Re-running this is a SAFE NO-OP: it
# detects the already-split marker and exits without touching the shards. To
# refresh the index after editing shards, use sync-index.sh instead.
#
# Usage:
#   split-profile.sh                 migrate the default profile
#   split-profile.sh <profile.md>    migrate a specific profile file
#
# Hot (never sharded): "Decision Principles" (prose), "Decision Style" (sets Conf
# globally). Everything else shards out.
set -euo pipefail

PROFILE="${1:-${HOME}/.claude/user-decisions-table.md}"
case "$PROFILE" in
  "${HOME}/.claude/user-decisions-table.md")
    DOMAINS_DIR="${HOME}/.claude/decision-profile/domains" ;;
  *)
    DOMAINS_DIR="$(dirname "$PROFILE")/domains" ;;
esac

[ -f "$PROFILE" ] || { echo "split-profile: no profile at $PROFILE"; exit 0; }

# Already split? The hot file carries the "## Domain Index" marker once migrated.
# Bail out so we never re-shard (and never wipe) existing shards.
if grep -q '^## Domain Index' "$PROFILE" 2>/dev/null; then
  echo "split-profile: already split (## Domain Index present) — no-op. Use sync-index.sh to refresh the index."
  exit 0
fi

mkdir -p "$DOMAINS_DIR"

PROFILE="$PROFILE" DOMAINS_DIR="$DOMAINS_DIR" python3 << 'PY'
import os, re, sys

profile = os.environ["PROFILE"]
ddir    = os.environ["DOMAINS_DIR"]

# Hot (never sharded). "decision principles" is the prose fallback block, placed
# explicitly below; "decision style" sets Conf for every domain so it stays hot.
HOT_DOMAINS  = {"decision style"}
SKIP_DOMAINS = {"decision principles"}   # placed explicitly, neither hot-list nor shard

src = open(profile, encoding="utf-8").read()

# Front-matter = everything before the first "## " section (comment, mode:,
# last_update:, role:, title, intro). Stays hot verbatim.
first_section = re.search(r"(?m)^## ", src)
if not first_section:
    sys.exit(0)

front = src[:first_section.start()]
body  = src[first_section.start():]

blocks = [b for b in re.split(r"(?m)^(?=## )", body) if b.strip()]

def domain_name(block):
    m = re.match(r"## (.+)", block)
    return m.group(1).strip() if m else ""

def slugify(name):
    return re.sub(r"[^a-z0-9]+", "-", name.lower()).strip("-") or "domain"

def count_rows(block):
    rows = 0
    for ln in block.splitlines():
        s = ln.strip()
        if not s.startswith("|"):
            continue
        cells = [c.strip() for c in s.strip("|").split("|")]
        if all(set(c) <= set("-: ") for c in cells):   # |---|---| separator
            continue
        if cells and cells[0].lower() == "when":         # header row
            continue
        if any(cells):
            rows += 1
    return rows

principles  = ""
hot_tables  = []                 # blocks kept inline in the hot file (Decision Style)
shard_specs = []                 # (name, slug, rows, block)

for b in blocks:
    name = domain_name(b)
    if not name:
        continue
    low = name.lower()
    if low == "decision principles":
        principles = b.rstrip() + "\n"
    elif low in SKIP_DOMAINS:
        continue
    elif low in HOT_DOMAINS:
        hot_tables.append(b.rstrip() + "\n")
    else:
        shard_specs.append((name, slugify(name), count_rows(b), b.rstrip() + "\n"))

# Write shards. (No deletion here — migration only adds.)
index_lines = []
for name, slug, rows, block in shard_specs:
    open(os.path.join(ddir, f"{slug}.md"), "w", encoding="utf-8").write(block)
    index_lines.append(f"- `{slug}` ({rows} rows) — {name}")

index_listing = "\n".join(sorted(index_lines)) if index_lines else "_No domain shards yet._"

# INDEX.md
open(os.path.join(ddir, "INDEX.md"), "w", encoding="utf-8").write(
    "<!-- Auto-generated. One line per domain shard. Refresh with sync-index.sh.\n"
    "     To consult a domain's rules at runtime, Read decision-profile/domains/<slug>.md. -->\n\n"
    "# Domain Index\n\n" + index_listing + "\n"
)

# Rebuild hot file.
index_marker = (
    "## Domain Index\n\n"
    "<!-- domain-index: full rules for these domains live in\n"
    "     ~/.claude/decision-profile/domains/<slug>.md — Read the matching shard\n"
    "     only when a question needs that domain's specific rows. -->\n\n"
    + index_listing + "\n"
)

parts = [front.rstrip() + "\n"]
if principles:
    parts.append(principles)
parts.extend(hot_tables)
parts.append(index_marker)

hot = "\n".join(p.rstrip("\n") for p in parts) + "\n"
hot = re.sub(r"\n{3,}", "\n\n", hot)
open(profile, "w", encoding="utf-8").write(hot)

print(f"split-profile: migrated — hot file + {len(shard_specs)} domain shard(s).")
PY
