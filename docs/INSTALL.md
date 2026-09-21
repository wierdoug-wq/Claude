# Ad-hoc task queue for lab01

Lets you hand Claude a task from your phone while away from the house, and
have the answer waiting in the vault. Extends the existing
`run-claude-task.sh` framework rather than replacing it: that one runs named,
scheduled tasks with a fixed prompt; this one runs one-off tasks you queue as
you think of them.

## Why it is shaped this way

- **The worker is lab01's own Claude Code, not a cloud session.** Cloud
  sessions cannot reach the tailnet, and bridging one would mean exposing
  lab01 to the public internet -- a bad trade for a box holding
  `confidential` and `highly-confidential` notes.
- **Results are delivered through the vault**, the same mechanism the daily
  brief already uses. lab01 writes into `00_Inbox/Agent_Results/`, Syncthing
  carries it to Beastly. No notification plumbing.
- **Do not route this through Google Drive.** The chain is
  lab01 -> Syncthing -> Beastly -> Drive. Beastly is the laptop that gets
  closed, so anything arriving via Drive only lands when the laptop is open --
  reintroducing the exact problem lab01 exists to solve.

## Step 0 -- verify off-LAN Tailscale first

`Home_Lab_Home.md` records this as **not yet verified**: every Tailscale test
so far ran with all three nodes on the same network, so the DERP relay path
has never been exercised. "Out and about" *is* that path.

Turn WiFi off on the phone, then over cellular:

    tailscale ping lab01
    ssh doug@100.82.2.47

If that fails, nothing below matters. Fix it first.

## Step 1 -- install

On lab01:

    git clone <this repo> ~/src/lab01-queue
    install -m 755 ~/src/lab01-queue/bin/queue-runner.sh      ~/bin/queue-runner.sh
    install -m 755 ~/src/lab01-queue/bin/ct                   ~/bin/ct
    install -m 755 ~/src/lab01-queue/bin/build-vault-index.sh ~/bin/build-vault-index.sh
    install -m 644 ~/src/lab01-queue/claude-tasks/_adhoc.tools ~/claude-tasks/_adhoc.tools
    mkdir -p ~/claude-tasks/{queue,done,failed}

No sudo needed -- everything lives under `$HOME`, which matters because
`sudo -n` fails on lab01 and cannot be driven over SSH.

Then `crontab -e` and append `docs/crontab.snippet` below the existing
`CRON_TZ` line.

## Step 2 -- confirm the tool prefixes

The allowlist in `_adhoc.tools` assumes lab01's human-readable MCP prefixes
(`mcp__claude_ai_Gmail__`, not the desktop app's UUIDs). Confirm before
trusting an unattended run:

    claude -p 'list your available tools' 2>&1 | grep -o 'mcp__[a-z_]*__' | sort -u

A run that needs a tool it was not granted stops on a permission prompt
nobody is awake to answer. Wildcards are only legal after a literal
`mcp__<server>__` prefix -- bare `mcp__*` is rejected.

## Step 3 -- use it

From an SSH session on the phone:

    ct "summarise this week's calendar and flag any conflicts"
    ct -n "what did the choir group post today"
    ct -t 'mcp__playwright__browser_navigate' "check the LTISD calendar page"
    ct -l

Without `-n`, a task waits for the 4:44am drain. That default is deliberate:
a task fired at 9am can burn the session you wanted at 9am, which has already
happened once.

## Safety model

`_adhoc.tools` is **read-only by construction** -- no send, no shell, no file
writes. The runner writes Claude's output into the vault itself, so no task
needs `Write` just to produce a note. Grant more per task with `ct -t`, and
only when you mean it.

## Vault index and result retention

Every run checks whether any note under `$VAULT` has changed since the last
build and, if so, regenerates `$VAULT/.vault-index/INDEX.md` -- a manifest
grouped by folder with each note's title, `type`, and `tags`. It costs one
`find -newer` check per run (no LLM call), and every queued task's prompt
gets a pointer to it prepended, so a task's first move can be reading the
index instead of a blind `Glob`/`Grep` sweep of the whole vault. Override the
script location with `BUILD_INDEX` if it isn't installed next to
`queue-runner.sh`.

`--drain` also archives result notes older than `RESULTS_RETENTION_DAYS`
(default 14) into `00_Inbox/Agent_Results/_archive/YYYY-MM/`, so the inbox
folder and the index build both stay cheap as results pile up.

## Not addressed here

- **A nicer phone UI.** `tailscale serve` could put a small submit form on
  `https://lab01.<tailnet>.ts.net/` reachable only inside the tailnet. Use
  `serve`, never `funnel` -- funnel is public.
- **Long-running tasks.** The 15-minute timeout matches `run-claude-task.sh`.
