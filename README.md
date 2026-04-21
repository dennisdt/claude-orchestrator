# claude-orchestrator

A tmux-based harness for running multiple persistent Claude Code sessions from one "orchestrator" Claude. You talk to the orchestrator in natural language; it spawns, lists, and kills Claude Code windows in a shared tmux session.

## What's in here

- `CLAUDE.md` — the orchestrator's system prompt. Loaded automatically when you run `claude` from this directory.
- `bin/claude-revive` — a bash respawn loop around `claude --dangerously-skip-permissions --remote-control`. On any exit it restarts with `--continue` so history is preserved. If the cwd already has prior Claude history on disk, it resumes from the very first launch (not just on respawn). Ctrl+C during the 5-second grace window stops the loop.
- `bin/claude-send` — sends text or a slash command to a named orchestrator window. For cron/CI/external-tool triggers, e.g. `claude-send example-api /compact`. Inside the orchestrator you'd just ask it in English — this helper exists for non-Claude callers.
- `bin/claude-state` — TSV-based session tracker at `~/.claude-orchestrator/sessions.txt`. The orchestrator calls `claude-state add` after spawning, `claude-state remove` after killing, and `claude-state missing` on startup to detect sessions that should be restored after a reboot.
- `scripts/start-work.sh` — creates (or attaches to) a tmux session named `work`, with an orchestrator Claude running in this directory under `claude-revive`. Accepts `--no-attach` for headless use (the LaunchAgent calls it this way).
- `scripts/install.sh` — one-shot macOS setup for the tmux-Keychain bridge.
- `scripts/install-launchd.sh` — installs (or removes with `--uninstall`) the LaunchAgent that brings the orchestrator up at every login.
- `launchd/com.claude-orchestrator.plist.template` — the plist the installer renders with your repo's absolute path.
- `.claude/settings.json` — project-scoped Claude Code permission allowlist for the tmux commands the orchestrator needs.
- `tmux.conf.example` — the one-line `~/.tmux.conf` snippet the installer adds.

## Prerequisites

- macOS (the Keychain fix is macOS-specific; the rest works anywhere)
- [Homebrew](https://brew.sh)
- [tmux](https://github.com/tmux/tmux) (`brew install tmux`)
- [Claude Code](https://docs.claude.com/en/docs/claude-code) logged in (`claude` on PATH)

## Install

Clone the repo anywhere — the scripts resolve the repo root from their own location, and `scripts/start-work.sh` exports `CLAUDE_ORCHESTRATOR_HOME` into the tmux server environment so child windows can find `bin/claude-revive` regardless of where you put the repo.

```bash
git clone https://github.com/dennisdt/claude-orchestrator.git
cd claude-orchestrator
scripts/install.sh
```

The installer will:

1. `brew install reattach-to-user-namespace`
2. Append `set-option -g default-command "reattach-to-user-namespace -l ${SHELL}"` to `~/.tmux.conf` (skipped if already present).
3. Warn you to run `tmux kill-server` if a tmux server is already running — the config only reloads on a fresh server.

After the kill-server, any tmux-hosted `claude` can reach the login Keychain normally. This is the fix for [the `/login` credential prompt loop inside tmux](https://www.junyi.dev/en/posts/tmux-keychain/); the short version is that the long-lived tmux daemon inherits a stale macOS security session, so child processes can't see your Keychain.

## Usage

Start the orchestrator from inside the repo (or via its absolute path):

```bash
./scripts/start-work.sh
```

This creates a tmux session named `work` with a single window — `orchestrator` — running Claude in this directory under `claude-revive`. Claude loads `CLAUDE.md` from the cwd, so it boots straight into orchestrator mode.

Then just talk to it:

> "Start a session for my example-api repo"
> "Kill the example-ui window"
> "List the running sessions"

Under the hood, the orchestrator runs standard tmux commands:

```bash
# Spawn
tmux new-window -t work -c <directory> -n <short-name>
tmux send-keys -t work:<short-name> '$CLAUDE_ORCHESTRATOR_HOME/bin/claude-revive' Enter
$CLAUDE_ORCHESTRATOR_HOME/bin/claude-state add <short-name> <directory>

# List
tmux list-windows -t work

# Kill
tmux kill-window -t work:<short-name>
$CLAUDE_ORCHESTRATOR_HOME/bin/claude-state remove <short-name>
```

Each spawned window runs Claude under `claude-revive`, so if remote control drops (macOS tmux + Anthropic remote-control servers do drop idle connections) or Claude crashes, the wrapper respawns with `--continue`.

## Auto-start at login (optional)

If you want the orchestrator + any sessions it manages to come up automatically every time you log in, install the LaunchAgent:

```bash
scripts/install-launchd.sh
```

This renders `launchd/com.claude-orchestrator.plist.template` with your repo's absolute path, drops it at `~/Library/LaunchAgents/com.claude-orchestrator.plist`, and bootstraps it via `launchctl`. At login it runs `scripts/start-work.sh --no-attach` — the tmux session is created in the background; open your terminal and run `start-work.sh` (or `tmux attach -t work`) to connect.

Logs go to `/tmp/claude-orchestrator.log`. Uninstall with:

```bash
scripts/install-launchd.sh --uninstall
```

## Restoring sessions after a reboot

Claude Code writes every conversation to `~/.claude/projects/<encoded-cwd>/*.jsonl` on every turn, so per-project histories survive any reboot, crash, or `tmux kill-server`. What doesn't survive is the tmux windows themselves — they need to be respawned.

`claude-orchestrator` tracks spawned windows in `~/.claude-orchestrator/sessions.txt` (TSV: `<name>\t<path>`). After a reboot, `scripts/start-work.sh` (or the LaunchAgent) recreates only the orchestrator window. On your first message, the orchestrator runs `claude-state missing`, sees which project sessions aren't back yet, and asks whether to respawn them. Say yes and each comes back with `--continue` and its full prior history; say no and the entries are dropped from state.

## Known limitation

If `--continue` lands in a very large context, Claude shows a "Resume from summary / Resume full" prompt. The wrapper can't click through that — you have to do it manually the next time you attach.

## Layout

```
claude-orchestrator/
├── CLAUDE.md                 # orchestrator system prompt
├── README.md
├── tmux.conf.example         # the one-line Keychain bridge
├── .claude/
│   └── settings.json         # project-scoped tmux permission allowlist
├── bin/
│   ├── claude-revive         # respawn loop
│   ├── claude-send           # external trigger helper
│   └── claude-state          # session state tracker (for restore-on-reboot)
├── launchd/
│   └── com.claude-orchestrator.plist.template
└── scripts/
    ├── install.sh            # brew + tmux.conf setup
    ├── install-launchd.sh    # login auto-start (optional)
    └── start-work.sh         # create/attach the "work" tmux session
```
