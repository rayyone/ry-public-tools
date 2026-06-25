#!/usr/bin/env bash
# decision-profile PostToolUse hook (matcher: AskUserQuestion).
# Reads the tool result from stdin (Claude Code injects JSON), extracts the
# user's answer, and appends it to decision-log.md for later digest.
#
# Claude Code PostToolUse stdin format:
#   { "tool_name": "AskUserQuestion", "tool_input": { ... }, "tool_response": { ... } }
set -euo pipefail

LOG="${HOME}/.claude/decision-profile/user-manual-decided-log.md"

[ -f "$LOG" ] || exit 0

# Read stdin into variable first, then pass to node via env.
INPUT=$(cat)
[ -z "$INPUT" ] && exit 0

HOOK_INPUT="$INPUT" node << 'NODE_EOF'
const fs  = require('fs');
const log = process.env.HOME + '/.claude/decision-profile/user-manual-decided-log.md';

const raw = process.env.HOOK_INPUT || '';
if (!raw.trim()) process.exit(0);

let payload;
try { payload = JSON.parse(raw); } catch { process.exit(0); }

const input    = payload.tool_input    || {};
const response = payload.tool_response || {};

const questions = input.questions || [];

// Skip dismissed/unanswered prompts. When the user closes the prompt without
// picking, Claude Code returns the string "The user did not answer the
// questions." (and no answers object). Logging those produced junk rows with
// empty/null answers in user-manual-decided-log.md.
const noAnswer =
  typeof response === 'string'
    ? /did not answer/i.test(response)
    : (typeof response.content === 'string' && /did not answer/i.test(response.content));

const answers = (response && typeof response === 'object' && response.answers) || {};

if (!questions.length) process.exit(0);
if (noAnswer || !Object.keys(answers).length) process.exit(0);

const ts = new Date().toISOString().replace(/\.\d+Z$/, 'Z');

const lines = questions
  .map((q) => {
    const text = q.question || '';
    const ans  = answers[text] !== undefined ? answers[text] : (Object.values(answers)[0] || '');
    return `- [${ts}] [unknown] Q:"${text.replace(/"/g, "'")}" -> A:"${String(ans).replace(/"/g, "'")}"`;
  })
  .filter(Boolean);

if (!lines.length) process.exit(0);

let existing = '';
try { existing = fs.readFileSync(log, 'utf8'); } catch { existing = ''; }

// Preserve header comment block, append new entries, trim to 200.
const headerMatch = existing.match(/^((?:<!--[\s\S]*?-->)\s*)/);
const header  = headerMatch ? headerMatch[1] : '';
const entries = (existing.match(/^- \[.*$/gm) || []);
const combined = [...entries, ...lines];
const trimmed  = combined.slice(-200);

fs.writeFileSync(log, header + trimmed.join('\n') + '\n');
NODE_EOF
