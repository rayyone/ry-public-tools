#!/usr/bin/env bash
# sync-decisions.sh — backup or restore your decision-profile files.
#
# Backups live OUTSIDE any git repo, under your home dir, so personal decision
# data is never committed publicly:
#   ~/.ry-decision-profile-backup/
#
# Usage:
#   ./sync-decisions.sh backup    — copy live profile → backup dir
#   ./sync-decisions.sh restore   — copy backup dir → live profile
#
set -euo pipefail

CLAUDE_DIR="$HOME/.claude"
STATE_DIR="$CLAUDE_DIR/decision-profile"
BACKUP_DIR="$HOME/.ry-decision-profile-backup"

# Single files: "backup-name:live-path"
FILES=(
  "user-decisions-table.md:$CLAUDE_DIR/user-decisions-table.md"
  "interviewed-questions-log.md:$STATE_DIR/interviewed-questions-log.md"
)

# The profile is split: the hot file above + per-domain shards under domains/.
# Mirror the whole shards dir so backup/restore keeps the rules that moved out
# of the hot file. Without this, restore would bring back an empty/stale profile.
DOMAINS_LIVE="$STATE_DIR/domains"
DOMAINS_BACKUP="$BACKUP_DIR/domains"

usage() { echo "Usage: $0 <backup|restore>"; exit 1; }

[[ $# -eq 1 ]] || usage
CMD="$1"

case "$CMD" in
  backup)
    mkdir -p "$BACKUP_DIR"
    for entry in "${FILES[@]}"; do
      name="${entry%%:*}"
      src="${entry##*:}"
      if [[ -f "$src" ]]; then
        cp "$src" "$BACKUP_DIR/$name"
        echo "backed up: $src → $BACKUP_DIR/$name"
      else
        echo "skip (not found): $src"
      fi
    done
    # Domain shards (whole dir). Mirror exactly so deleted shards don't linger.
    if [[ -d "$DOMAINS_LIVE" ]]; then
      rm -rf "$DOMAINS_BACKUP"
      cp -R "$DOMAINS_LIVE" "$DOMAINS_BACKUP"
      echo "backed up: $DOMAINS_LIVE/ → $DOMAINS_BACKUP/ ($(ls "$DOMAINS_BACKUP"/*.md 2>/dev/null | grep -vc INDEX) shard(s))"
    else
      echo "skip (not found): $DOMAINS_LIVE/"
    fi
    ;;
  restore)
    mkdir -p "$STATE_DIR"
    for entry in "${FILES[@]}"; do
      name="${entry%%:*}"
      dest="${entry##*:}"
      src="$BACKUP_DIR/$name"
      if [[ -f "$src" ]]; then
        cp "$src" "$dest"
        echo "restored: $src → $dest"
      else
        echo "skip (not found): $src"
      fi
    done
    # Domain shards (whole dir). Mirror exactly.
    if [[ -d "$DOMAINS_BACKUP" ]]; then
      rm -rf "$DOMAINS_LIVE"
      cp -R "$DOMAINS_BACKUP" "$DOMAINS_LIVE"
      echo "restored: $DOMAINS_BACKUP/ → $DOMAINS_LIVE/ ($(ls "$DOMAINS_LIVE"/*.md 2>/dev/null | grep -vc INDEX) shard(s))"
    else
      echo "skip (not found): $DOMAINS_BACKUP/"
    fi
    ;;
  *)
    usage
    ;;
esac
