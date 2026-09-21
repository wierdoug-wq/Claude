# KB structure & retrieval, evaluated against "chunkless RAG"

Source video: IBM Technology, *"Unlock Better RAG & AI Agents with Docling"*
(youtu.be/anLahYrEFiQ). Its core argument, and the one worth testing this
repo against: traditional RAG chops documents into chunks, embeds them, and
retrieves by cosine similarity, which throws away headings, table structure,
and reading order. Docling instead parses a document into a structured tree
(sections, headings, tables, captions, with page/bbox provenance on every
node) and lets an agent *navigate* that tree the way a person would — read
the outline, reason about which section holds the answer, open it, follow
references. The video's own caveat: pure tree-walking costs more latency and
more model calls than a single embedding lookup, so the practical shape is
hybrid — similarity search to find the right document, structure-based
navigation to find the answer inside it.

This repo doesn't contain a KB itself — it's one piece (`bin/ct`,
`bin/queue-runner.sh`, `claude-tasks/_adhoc.tools`) that lets a phone queue
a task for lab01's own Claude Code, with results written into an Obsidian
vault (`~/vault`, outside this repo) at `00_Inbox/Agent_Results/`. The
"retrieval" that exists to evaluate is what that queued task is allowed to
do when it needs to find something: the tool allowlist in
`claude-tasks/_adhoc.tools`.

## What retrieval looks like here today

`_adhoc.tools` grants `Read`, `Glob`, `Grep`, `WebFetch`, `WebSearch`, plus
read-only Gmail/Calendar/Drive MCP tools. There is no embedding index, no
vector store, no chunking pipeline anywhere in this repo. Every ad-hoc task
finds what it needs by having the agent glob/grep the vault fresh and read
whatever files match — full agentic navigation, zero similarity search.

## Where this already matches the video's thesis

- **No chunk-and-embed step to throw structure away.** The video's complaint
  is that chunking destroys headings and table context before retrieval
  even happens. This system never chunks anything — it reads whole files,
  so nothing is lost that Docling would have to work to recover.
- **The vault is already the structured tree Docling produces.** Docling's
  whole job is turning PDFs/Word/scans into a hierarchical object because
  those formats don't carry structure natively. Obsidian notes are Markdown:
  headings, frontmatter, and links *are* the structure already, readable
  by `Grep`/`Read` with no parsing step. The problem the video solves mostly
  doesn't exist here, because the source format was never structure-hostile.
- **Provenance per result is already deliberate.** `queue-runner.sh` stamps
  every result note with `task`, `priority`, `started`/`finished`,
  `exit_code`, and the original prompt under `## Request`. That's coarser
  than Docling's per-node page/bbox, but it's the right granularity for a
  one-note-per-answer result — there's no sub-document region to cite.

## Gaps against the video's model, and what changed

- **No hybrid layer.** *Addressed.* The video's own recommendation, after
  making the case for structural navigation, is *not* "abandon similarity
  search" — it's "use similarity search to find the right document, then
  navigate its structure." This system had no equivalent first pass: every
  task glob/grepped the whole vault cold. `bin/build-vault-index.sh` now
  generates `$VAULT/.vault-index/INDEX.md`, a manifest grouped by folder
  with each note's title, `type`, and `tags`; `queue-runner.sh` rebuilds it
  only when something under the vault has actually changed (one
  `find -newer` check, no LLM call) and prepends a pointer to it on every
  task prompt. That's the cheap first pass the video argues for, without
  the embedding index it also argues isn't strictly necessary once
  structure is preserved.
- **No outline-first navigation.** *Addressed by the same change.* Docling
  gives the agent a table of contents before it opens anything, so it can
  reason "which section" before spending a read. Tasks now get that same
  move: the index is the outline, and the prompt tells the agent to check
  it before a full sweep, with an explicit fallback to `Glob`/`Grep` for
  anything time-sensitive the index might lag.
- **Result-note growth was undermining the fix.** Related but distinct
  from either gap above: `00_Inbox/Agent_Results/` was flagged as growing
  without bound, which would eventually make both the index and a blind
  grep expensive over the same pile of agent output. `queue-runner.sh
  --drain` now archives result notes older than `RESULTS_RETENTION_DAYS`
  (default 14 days) into `_archive/YYYY-MM/`, and the index generator
  excludes `Agent_Results` from its per-note listing entirely — it's agent
  output, not curated notes, so it doesn't belong in the outline.
- **Table/structure handling is still untested by this repo.** The
  read-only allowlist includes
  `mcp__claude_ai_Google_Drive__read_file_content`, which can return
  exported Docs/Sheets. Unlike Docling, there's no explicit guarantee here
  that a spreadsheet's table structure survives being flattened to text
  for the agent — it depends entirely on what that MCP tool hands back.
  Left open deliberately: it needs a real Drive document with tables to
  test against, not a guess.

## Bottom line

The design already landed closer to the video's endpoint (agentic
structural navigation) than to the RAG pipeline it argues against — mostly
because the vault's native format (Markdown) sidesteps the problem Docling
exists to solve for PDFs. The scale gap — no first-pass index, no retention
on the folder that would keep growing under it — is now closed: a cheap,
LLM-free index gives every task the outline-first move the video describes,
and drain-time archiving keeps both the index and a fallback grep affordable
as results accumulate. What's left (Drive table fidelity) is a genuine
unknown, not a design gap, and stays open until there's a real document to
test it against.
