#!/usr/bin/env bash
# daily-backup.sh — wrapper that runs sync-decisions.sh backup once, quietly.
#
# Invoked by the launchd agent
# (~/Library/LaunchAgents/com.rayyone.decision-profile-backup.plist) on a daily
# schedule. All output is appended to the backup dir's sync.log with a timestamp
# so the run is silent on the console but still auditable.
set -uo pipefail

STATE_DIR="$HOME/.claude/decision-profile"
BACKUP_DIR="$HOME/.ry-decision-profile-backup"
LOG="$BACKUP_DIR/sync.log"

mkdir -p "$BACKUP_DIR"

ts() { date '+%Y-%m-%dT%H:%M:%S%z'; }

{
  echo "=== $(ts) daily backup start ==="
  bash "$STATE_DIR/sync-decisions.sh" backup
  echo "=== $(ts) daily backup done (exit $?) ==="
} >> "$LOG" 2>&1
