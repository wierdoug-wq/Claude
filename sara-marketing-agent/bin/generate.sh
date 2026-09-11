#!/usr/bin/env bash
#
# generate.sh — draft one piece of marketing content for Calm and Connected
# (Sara's practice, ccbehavior.org) using a template + brand brief.
#
# Drafts only. Nothing here posts, schedules, or sends anything — it writes
# a markdown file to drafts/ for a human to review and publish by hand.
#
#   generate.sh instagram "morning routine meltdowns"
#   generate.sh facebook "back to school transitions" -l
#   generate.sh email "why 'just try harder' doesn't work" -n "keep it under 250 words"
#   generate.sh blog "sensory overload at birthday parties"
#   generate.sh -l                     # list drafts

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BRAND="$HERE/brand/brief.md"
TEMPLATES="$HERE/templates"
DRAFTS="$HERE/drafts"
CLAUDE_BIN="${CLAUDE_BIN:-claude}"

usage() {
  sed -n '2,13p' "$0" | sed 's/^# \?//'
  echo
  echo "types: instagram, facebook, email, blog"
}

notes=""
list_only=false

while getopts ':n:lh' opt; do
  case "$opt" in
    n) notes="$OPTARG" ;;
    l) list_only=true ;;
    h) usage; exit 0 ;;
    *) echo "generate.sh: bad flag; try -h" >&2; exit 2 ;;
  esac
done
shift $((OPTIND - 1))

mkdir -p "$DRAFTS"

if $list_only; then
  echo "drafts:"
  ls -1t "$DRAFTS" 2>/dev/null | sed 's/^/  /' || true
  exit 0
fi

type="${1:-}"
topic="${2:-}"

case "$type" in
  instagram) template="$TEMPLATES/instagram-post.md" ;;
  facebook)  template="$TEMPLATES/facebook-post.md" ;;
  email)     template="$TEMPLATES/email-newsletter.md" ;;
  blog)      template="$TEMPLATES/blog-idea.md" ;;
  ""|-h|--help) usage; exit 0 ;;
  *) echo "generate.sh: unknown type '$type'; try -h" >&2; exit 2 ;;
esac

[[ -n "$topic" ]] || { echo "generate.sh: missing topic; try -h" >&2; exit 2; }

prompt_body="$(sed "s/{{TOPIC}}/$(printf '%s' "$topic" | sed 's/[&/\]/\\&/g')/" "$template")"

prompt="$(cat "$BRAND")

---

$prompt_body"

if [[ -n "$notes" ]]; then
  prompt="$prompt

Additional notes from Sara for this piece: $notes"
fi

slug="$(printf '%s' "$topic" | tr '[:upper:]' '[:lower:]' \
        | tr -cs 'a-z0-9' '-' | cut -c1-40 | sed 's/^-*//; s/-*$//')"
[[ -n "$slug" ]] || slug=draft
out="$DRAFTS/$(date +%Y%m%d-%H%M%S)-${type}-${slug}.md"

prompt="$prompt

Output only the requested content as plain text in your reply. Do not use
any tools, do not attempt to read or write any files — just write the
content directly in your response."

echo "generating $type draft on: $topic" >&2
result="$("$CLAUDE_BIN" -p --disallowedTools 'Write,Edit,Bash,Read,Glob,Grep' -- "$prompt")"

{
  echo "---"
  echo "type: $type"
  echo "topic: $topic"
  echo "generated: $(date -Iseconds)"
  echo "status: draft-needs-review"
  echo "---"
  echo
  echo "$result"
} >"$out"

echo "draft written: $out"
