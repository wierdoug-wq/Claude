# sara-marketing-agent

A draft-only content generator for **Calm and Connected Behavior Consulting &
Parent Training** (Sara's practice, [ccbehavior.org](https://ccbehavior.org)).

Given a content type and a topic, it fills a brand-voice prompt and writes a
markdown draft to `drafts/`. It does not post, schedule, or send anything —
every draft needs a human read and a manual publish. That's deliberate: this
is the MVP of a larger idea (content + scheduling + research + analytics),
scoped down to "produce good drafts in Sara's voice" first.

## Contents

| Path | Purpose |
|---|---|
| `brand/brief.md` | Business facts, voice, audience, content pillars. Edit this first — it drives every draft. |
| `templates/` | One prompt template per content type. |
| `bin/generate.sh` | CLI: generate a draft, or list what's been generated. |
| `drafts/` | Output. Gitignored content aside from `.gitkeep` — review and delete/publish by hand. |

## Usage

```
bin/generate.sh instagram "morning routine meltdowns"
bin/generate.sh facebook "back to school transitions"
bin/generate.sh email "why 'just try harder' doesn't work"
bin/generate.sh blog "sensory overload at birthday parties"

bin/generate.sh -n "keep it under 100 words" instagram "screen time battles"
bin/generate.sh -l   # list drafts
```

Requires the `claude` CLI on `PATH` (or set `CLAUDE_BIN` to its path).

## Before using this for real

`brand/brief.md` has `[confirm]` markers on details pulled from public search
results, not supplied by Sara directly — her preferred bio wording, any
existing tagline/brand colors, and words she wants to avoid. Fill those in
before the drafts go out under her name; the brief is what keeps every draft
sounding like her instead of like generic parenting-coach content.

## Not built yet

- Live publishing/scheduling to Instagram, Facebook, or an email platform
  (needs API credentials + Sara's sign-off on which tools)
- Competitor research / content strategy
- Analytics/reporting on post performance

These were part of the original ask but are deliberately deferred until the
draft quality itself is validated with Sara.
