# How work gets done in this repo

This file is read automatically at the start of a Claude Code session here.
It exists because "vibe coding" — describing what you want and accepting
whatever the model produces without a plan, tests, or review — is fine for a
throwaway script but wrong for anything that runs unattended, touches other
systems, or outlives the session that wrote it. Everything in this repo
(cron jobs, a queue runner, tool allowlists gating what an unattended agent
can touch) falls in the second category. So: **act like a senior engineer
pairing with another senior engineer, not like an intern taking dictation.**
Plan, prep, write, test, iterate — in that order — before anything ships.

## The workflow

For anything beyond a one-line fix:

1. **Plan.** State the problem in one paragraph. List the files it touches.
   Name the risk (data loss, a race, a cost, a security boundary) if there
   is one. If the change is user-facing or behavior-changing, write it as
   Gherkin first (see below) — it forces "done" to be a fact, not a feeling.
2. **Prep.** Check for prior art in this repo before writing new code —
   `bin/` and `claude-tasks/_adhoc.tools` already encode patterns (locking,
   least-privilege tool grants, non-clobbering output) worth reusing rather
   than reinventing. If the change pulls in a new dependency, vet it first
   (see **Dependency and supply-chain checks** below) — do this *before*
   writing code against it, not after.
3. **Write.** Small, single-purpose changes. Prefer extending an existing
   script's pattern over adding a new abstraction (YAGNI, below).
4. **Test.** Prove the change works and prove it fails safely. For shell
   scripts that means running them against a scratch `$TASKS`/`$VAULT`, not
   just reading the diff. For anything with a race or a lock, test the
   concurrent case, not just the happy path.
5. **Iterate.** Re-read the diff adversarially before calling it done: what
   input breaks this? What happens if it's killed mid-write? What happens
   the second time it runs?
6. **Ship.** Commit with a message that says why, not what. Only then is
   the task actually finished — a working diff sitting uncommitted, or a
   plan without a test, is not "done."

Skipping straight to step 3 is vibe coding. It's fine for a five-minute
throwaway; it is not fine for anything that runs on a cron job while you're
asleep or holds credentials to Gmail, Calendar, or Drive.

## Definition of ready / definition of done

**Ready to start writing code:**
- The behavior is written down (a sentence, a Gherkin scenario, or both) —
  not just implied by a chat message.
- Any new dependency has been checked against **Dependency and
  supply-chain checks** below.
- You know what "this broke" looks like before you start, so you'll
  recognize it.

**Ready to ship:**
- Tests (or a manual run, for scripts with no test harness) demonstrate the
  behavior, including at least one failure/edge case.
- No new capability was granted (a tool, a scope, a credential) beyond what
  the task actually needs — check `claude-tasks/_adhoc.tools` stays
  read-only-by-default if you touch it.
- The diff is the smallest thing that solves the stated problem.

## Writing behavior down: Gherkin / BDD

Before implementing a feature or fixing a bug, write the acceptance
criteria as Given/When/Then. This is cheap and catches "wait, what should
actually happen here?" before code gets written to the wrong spec:

```gherkin
Feature: queue-runner skips overlapping runs
  Scenario: a run is already in progress
    Given queue-runner.sh already holds the lock file
    When cron invokes queue-runner.sh --now
    Then the new invocation exits 0 immediately
    And it logs that another run holds the lock
    And it does not touch any file in the queue
```

You don't need a test framework that parses Gherkin — the value is in
forcing the scenario into words before code, and it doubles as the PR
description.

## Domain-Driven Design, scaled to this repo

Full DDD (bounded contexts, aggregates, repositories) is overkill for a
handful of shell scripts. What still applies:

- **Ubiquitous language.** Use the same words in code, filenames, logs, and
  conversation. This repo already does this well — `queue`, `done`,
  `failed`, `priority`, `now`/`drain` mean the same thing everywhere. Don't
  introduce a new script that calls the same concept by a different name.
- **Keep the model explicit.** A task file's frontmatter *is* the schema.
  If you add a field, document it in the same comment block where the
  others live (see `bin/ct`'s header comment), not just in the code that
  reads it.

## SOLID and YAGNI, for scripts and services alike

- **Single responsibility.** `ct` queues; `queue-runner.sh` drains. Don't
  merge them because it's convenient once — the split is what makes each
  one testable and reasoned-about in isolation.
- **Open/closed in spirit:** prefer adding a new task type or a new
  frontmatter key over branching deep inside an existing function.
- **YAGNI.** Don't add a config flag, a plugin point, or a generic
  abstraction for a second use case that doesn't exist yet. Three similar
  lines of shell beat a premature helper function. This repo's own
  `_adhoc.tools` comment models this: it grants exactly what's needed and
  says explicitly what to add "only when you mean it."

## Concurrency, races, and idempotency

These matter here specifically because a cron-driven, unattended agent
cannot be asked "did you mean to do that?" — bugs in this space fail
silently or fail expensively (a doubled session cost, a lost task, a
clobbered file). When touching anything that runs on a schedule or reads a
shared directory:

- **TOCTOU (time-of-check to time-of-use).** A check (`[[ -e "$out" ]]`)
  followed by an act (writing to `$out`) is a race if anything else can run
  between the two. `queue-runner.sh`'s `flock` on `$LOCK` is exactly this
  guard applied to "don't let two drains run at once" — reuse that pattern
  (a lock file + `flock -n`, or an atomic `mkdir`/`ln` as a mutex) rather
  than a bare existence check whenever more than one process could touch
  the same path.
- **Prefer atomic operations over check-then-write.** A `mv` within the
  same filesystem is atomic; a `cp` then `rm` is not. Moving a task from
  `queue/` to `done/` or `failed/` is the safe primitive already in use —
  keep using it instead of, say, deleting-then-rewriting a file in place.
- **Idempotency.** A task that gets processed twice (retried after a crash,
  re-queued by hand) should not double-send an email, double-post a
  message, or silently overwrite a prior result. The existing "never clobber
  an earlier result" loop in `queue-runner.sh` is the pattern: derive a
  stable, collision-checked output name rather than assuming you'll only
  ever be called once.
- **Pull over push, where you have the choice.** This repo's queue is pull
  based — cron wakes the runner, the runner drains what's waiting — rather
  than push based (something reaching in to trigger a run live). Pull is
  easier to reason about (no incoming trigger to authenticate or rate-limit),
  easier to test (drive it manually), and fails safe (nothing runs if
  nothing polls). Default to pull for anything new unless push is a real
  requirement (genuine low-latency need), not just a convenience.

## Dependency and supply-chain checks

AI coding assistants — this one included — occasionally suggest a package
that doesn't exist, or exists but isn't the one you meant ("slopsquatting":
attackers watch for names LLMs hallucinate and publish malicious packages
under exactly those names, betting someone will `pip install`/`npm install`
it without checking). Treat any package name a model suggests, including
ones suggested in this session, as **unverified until checked**:

1. **Confirm the package actually exists and is the one you think it is.**
   Look it up on the real registry (PyPI, npm, crates.io, etc.) yourself —
   don't trust the name alone. Check: does it have a plausible history (not
   "published yesterday, zero downloads before now")? Does its listed
   repository link to a real, maintained GitHub project? Does the
   maintainer/org match who you'd expect to publish it?
2. **Check download counts and age are consistent with how well-known the
   package is supposed to be.** A package an AI describes as "the standard
   library for X" that has a handful of weekly downloads and was published
   last month is a red flag, not a coincidence.
3. **Pin and lock.** Use a lockfile (`package-lock.json`, `poetry.lock`,
   `Pipfile.lock`, etc.) with integrity hashes, and commit it. Don't let a
   floating version range silently pick up a compromised release.
4. **Run a vulnerability/supply-chain scanner before shipping** when the
   ecosystem has one — `npm audit`, `pip-audit`, `osv-scanner`, `cargo
   audit`. This catches known-bad packages even when the name was typed by
   a human, not just a hallucinated one.
5. **Never pipe an installer straight from a URL a model suggested**
   (`curl … | sh`, an unpinned `go install …@latest`) without reading what
   it fetches first.
6. **When in doubt, ask before adding the dependency at all** — an extra
   external package is a bigger, harder-to-reverse decision than an extra
   function, and warrants the same "check before proceeding" treatment as
   any other hard-to-reverse action.

This applies to Claude Code itself, too: MCP servers and plugins are
dependencies. Don't add one on a name alone.

## Repo-specific notes

- Tool allowlists in `claude-tasks/_adhoc.tools` are read-only by design —
  see the file's own header comment. Widen them per-task with `ct -t`, and
  only when the task genuinely needs it, not as a standing default.
- `docs/INSTALL.md` Step 0 (off-LAN Tailscale) is a documented
  prerequisite the rest of the setup depends on — don't skip re-verifying
  it when touching install/cron docs.
