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

## Gaps against the video's model

- **No hybrid layer.** The video's own recommendation, after making the case
  for structural navigation, is *not* "abandon similarity search" — it's
  "use similarity search to find the right document, then navigate its
  structure." This system has no equivalent first pass: every task
  glob/greps the whole vault cold. That's fine at current size; the README
  itself flags `00_Inbox/Agent_Results/` as "grows without bound" with no
  cleanup story. Once the vault is large enough that a blind grep is slow
  or burns context, there's no cheaper first-pass index (a generated
  `INDEX.md`, or frontmatter-tag search) to narrow scope before reading —
  worth building before it's needed, not after a task times out.
- **No outline-first navigation.** Docling gives the agent a table of
  contents before it opens anything, so the agent can reason "which section"
  before spending a read. Here the agent's first move on a cold task is
  necessarily a blind `Glob`/`Grep` — there's no cheap "here's the vault's
  shape" step it's handed up front. A standing outline (folder structure +
  frontmatter tag index) would let tasks skip straight to the relevant
  section the way the video's agent does with Docling's tree, instead of
  discovering structure by searching for it every time.
- **Table/structure handling is untested by this repo.** The read-only
  allowlist includes `mcp__claude_ai_Google_Drive__read_file_content`,
  which can return exported Docs/Sheets. Unlike Docling, there's no
  explicit guarantee here that a spreadsheet's table structure survives
  being flattened to text for the agent — it depends entirely on what that
  MCP tool hands back. If Drive documents with real tables start showing
  up in ad-hoc tasks, that's the one place this system could hit exactly
  the failure mode the video describes (structure lost before the agent
  ever sees it), and it's worth a quick check rather than an assumption.

## Bottom line

The design already lands closer to the video's endpoint (agentic structural
navigation) than to the RAG pipeline it argues against — mostly because the
vault's native format (Markdown) sidesteps the problem Docling exists to
solve for PDFs. The gap isn't structure preservation, it's scale: no
first-pass index or standing outline means every task pays a full cold
search, which is the exact cost the video's hybrid recommendation is
designed to avoid. That only becomes a real problem as
`00_Inbox/Agent_Results/` keeps growing unbounded, so it's worth addressing
before it's a timeout on the 15-minute budget rather than after.
