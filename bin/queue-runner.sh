#!/usr/bin/env bash
#
# queue-runner.sh — drain the ad-hoc Claude task queue on lab01.
#
# Companion to run-claude-task.sh. That one runs *named, scheduled* tasks whose
# prompt and tool allowlist are fixed in advance. This one runs *ad-hoc* tasks
# dropped into a queue directory from anywhere on the tailnet — typically from
# a phone, over SSH, while away from the house.
#
# Usage:
#   queue-runner.sh --now      process only tasks marked `priority: now`
#   queue-runner.sh --drain    process everything still queued
#
# Cron calls --now every 10 minutes and --drain once in the 3-4am window, so a
# task runs immediately only when it says to, and otherwise waits for the
# overnight slot. That split exists because of a real failure already recorded
# in Home_Lab_Home.md: a sweep run during the day died on "You've hit your
# session limit" and cost the session that was actually wanted.

set -euo pipefail

VAULT="${VAULT:-$HOME/vault}"
TASKS="${TASKS:-$HOME/claude-tasks}"
QUEUE="$TASKS/queue"
DONE="$TASKS/done"
FAILED="$TASKS/failed"
LOG="${LOG:-$HOME/logs/queue-runner.log}"
LOCK="$HOME/.queue-runner.lock"
RESULTS="$VAULT/00_Inbox/Agent_Results"
RESULTS_ARCHIVE="$RESULTS/_archive"
RESULTS_RETENTION_DAYS="${RESULTS_RETENTION_DAYS:-14}"
DEFAULT_TOOLS="$TASKS/_adhoc.tools"
TIMEOUT="${TIMEOUT:-15m}"
CLAUDE_BIN="${CLAUDE_BIN:-/usr/bin/claude}"
INDEX_DIR="$VAULT/.vault-index"
INDEX_OUT="$INDEX_DIR/INDEX.md"
BUILD_INDEX="${BUILD_INDEX:-$(dirname "$0")/build-vault-index.sh}"

mkdir -p "$QUEUE" "$DONE" "$FAILED" "$RESULTS" "$(dirname "$LOG")"

log() { printf '%s  %s\n' "$(date -Iseconds)" "$*" >>"$LOG"; }

case "${1:-}" in
  --now)   MODE=now   ;;
  --drain) MODE=drain ;;
  *) echo "usage: $0 --now|--drain" >&2; exit 2 ;;
esac

# Never let two runs overlap. Each task is a full Claude session; two at once
# compete for the same quota. Non-blocking, so a slow run doesn't stack a queue
# of cron invocations behind it.
exec 9>"$LOCK"
if ! flock -n 9; then
  log "[$MODE] another run holds the lock; skipping"
  exit 0
fi

# Keep the vault index fresh so a task's first move can be reading it instead
# of a blind Glob/Grep sweep. Cheap: one `find -newer` check, no LLM call --
# safe to run on every --now tick even when the queue is empty.
if [[ -x "$BUILD_INDEX" ]]; then
  stale=1
  if [[ -f "$INDEX_OUT" ]]; then
    newer="$(find "$VAULT" -name '*.md' -newer "$INDEX_OUT" \
              -not -path "$INDEX_DIR/*" -not -path "$RESULTS/*" \
              -print -quit 2>/dev/null)"
    [[ -z "$newer" ]] && stale=0
  fi
  if (( stale )); then
    if "$BUILD_INDEX" "$VAULT" >>"$LOG" 2>&1; then
      log "[$MODE] vault index rebuilt"
    else
      log "[$MODE] vault index rebuild failed (rc=$?)"
    fi
  fi
fi

# Read one frontmatter key from a task file. Frontmatter is the block between
# the first two `---` lines; absent frontmatter yields an empty string.
fm() {
  sed -n '/^---[[:space:]]*$/,/^---[[:space:]]*$/p' "$2" 2>/dev/null \
    | sed -n "s/^$1:[[:space:]]*//p" | head -1 | tr -d '\r'
}

# Everything after the closing `---`. If there is no frontmatter, the whole file.
body() {
  if head -1 "$1" | grep -q '^---[[:space:]]*$'; then
    awk 'NR>1 && /^---[[:space:]]*$/ {found=1; next} found' "$1" \
      | sed '/./,$!d' 
  else
    cat "$1"
  fi
}

shopt -s nullglob
queued=("$QUEUE"/*.md)
(( ${#queued[@]} )) || log "[$MODE] queue empty"

for task in "${queued[@]}"; do
  name="$(basename "$task" .md)"
  priority="$(fm priority "$task")"; priority="${priority:-defer}"

  if [[ "$MODE" == now && "$priority" != now ]]; then
    continue
  fi

  # Tool allowlist: the shared read-only default, plus anything the task adds.
  # A wildcard is only legal after a literal mcp__<server>__ prefix — bare
  # 'mcp__*' is rejected outright — so every tool is named explicitly. A run
  # that needs a tool it was not granted stops on a permission prompt that
  # nobody is awake to answer.
  tools=""
  [[ -f "$DEFAULT_TOOLS" ]] && tools="$(grep -vE '^\s*(#|$)' "$DEFAULT_TOOLS" | paste -sd,)"
  extra="$(fm tools "$task")"
  [[ -n "$extra" ]] && tools="${tools:+$tools,}$extra"

  prompt="$(body "$task")"
  if [[ -z "${prompt//[[:space:]]/}" ]]; then
    log "[$MODE] $name: empty prompt, moving to failed/"
    mv "$task" "$FAILED/"
    continue
  fi

  # Point the agent at the standing index before it goes hunting. The raw
  # $prompt (not this) is what gets written into the result note's Request
  # section, so the note stays a clean record of what was actually asked.
  full_prompt="$prompt"
  if [[ -f "$INDEX_OUT" ]]; then
    full_prompt="Vault index: $INDEX_OUT -- a generated outline by folder, type,
and tags. Check it before a full Glob/Grep sweep of the vault. It can lag
same-minute edits, so fall back to Glob/Grep for anything time-sensitive.

$prompt"
  fi

  # `ct` already names tasks with a queue timestamp; don't stamp them twice.
  # Anything queued by hand without one gets a stamp so results stay ordered.
  if [[ "$name" =~ ^[0-9]{8}-[0-9]{6}- ]]; then
    out="$RESULTS/${name}.md"
  else
    out="$RESULTS/$(date +%Y%m%d-%H%M%S)-${name}.md"
  fi
  # Never clobber an earlier result for the same task name.
  n=2; while [[ -e "$out" ]]; do out="${out%.md}-$n.md"; ((n++)); done
  started="$(date -Iseconds)"
  log "[$MODE] $name: start (priority=$priority)"

  set +e
  result="$(timeout "$TIMEOUT" "$CLAUDE_BIN" -p "$full_prompt" --allowedTools "$tools" 2>&1)"
  rc=$?
  set -e

  # Write the result into the vault regardless of outcome. Syncthing carries it
  # to Beastly; a failure that leaves no note is a failure nobody sees.
  {
    echo '---'
    echo 'type: agent-result'
    echo "created: $(date +%Y-%m-%d)"
    echo "task: $name"
    echo "priority: $priority"
    echo "started: $started"
    echo "finished: $(date -Iseconds)"
    echo "exit_code: $rc"
    echo 'tags:'
    echo '  - agent/adhoc'
    echo '---'
    echo
    echo "# $name"
    echo
    echo '## Request'
    echo
    echo "$prompt"
    echo
    echo '## Result'
    echo
    if (( rc == 124 )); then
      echo "_Timed out after $TIMEOUT._"
      echo
    elif (( rc != 0 )); then
      echo "_Run exited $rc._"
      echo
    fi
    echo "$result"
  } >"$out"

  chmod 640 "$out"

  if (( rc == 0 )); then
    mv "$task" "$DONE/"
    log "[$MODE] $name: ok -> $out"
  else
    mv "$task" "$FAILED/"
    log "[$MODE] $name: exit $rc -> $out"
  fi
done

# Archive old results so Agent_Results doesn't grow without bound and a
# Glob/Grep sweep of it stays cheap. Drain-only: filesystem housekeeping,
# not something a 9am --now tick should pay for.
if [[ "$MODE" == drain ]]; then
  archived=0
  while IFS= read -r -d '' f; do
    month="$(date -r "$f" +%Y-%m)"
    mkdir -p "$RESULTS_ARCHIVE/$month"
    mv "$f" "$RESULTS_ARCHIVE/$month/"
    archived=$((archived + 1))
  done < <(find "$RESULTS" -maxdepth 1 -name '*.md' -mtime "+$RESULTS_RETENTION_DAYS" -print0)
  (( archived )) && log "[$MODE] archived $archived result note(s) older than ${RESULTS_RETENTION_DAYS}d"
fi

# Self-trim, matching run-claude-task.sh.
if [[ -f "$LOG" ]] && (( $(wc -l <"$LOG") > 2000 )); then
  tail -1000 "$LOG" >"$LOG.tmp" && mv "$LOG.tmp" "$LOG"
fi
