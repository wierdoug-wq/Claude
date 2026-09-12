# lab01 ad-hoc task queue

Hand Claude a task from your phone while out of the house; read the answer in
Obsidian when you get back.

The worker is lab01's own Claude Code. Tasks are queued into
`~/claude-tasks/queue/`, run by cron, and the results land in the vault at
`00_Inbox/Agent_Results/` — where Syncthing carries them to Beastly like any
other note.

A task can opt into running on lab01's local Ollama model instead, for
simple text-in/text-out work that doesn't need Claude's tools or token
budget — see `bin/ct -h`.

| Path | Purpose |
|---|---|
| `bin/ct` | Queue a task. Built to be typed on a phone over SSH. |
| `bin/queue-runner.sh` | Drains the queue. `--now` for urgent, `--drain` overnight. |
| `claude-tasks/_adhoc.tools` | Default tool allowlist. Read-only by construction. |
| `docs/crontab.snippet` | Cron lines to append below the existing `CRON_TZ`. |
| `docs/INSTALL.md` | Setup, including the off-LAN Tailscale check to do first. |

Start with **`docs/INSTALL.md` Step 0** — off-LAN Tailscale is recorded as
unverified in `Home_Lab_Home.md`, and it is the one thing this all depends on.
