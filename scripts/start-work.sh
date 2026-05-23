#!/bin/bash
# start-work.sh — launch the orchestrator tmux session.
#
# Creates (or attaches to) a tmux session named "work" with an orchestrator
# Claude running in the repo root under the claude-revive respawn wrapper.
# The repo root is resolved from this script's own location, so the repo can
# live anywhere on disk — it does not have to be at ~/claude-orchestrator.
#
# Exports CLAUDE_ORCHESTRATOR_HOME into the tmux server environment so child
# windows spawned by the orchestrator can reference $CLAUDE_ORCHESTRATOR_HOME
# instead of hardcoded paths.
#
# Flags:
#   --no-attach    Create the session if missing, then exit without attaching.
#                  Used by the LaunchAgent (no terminal available at login).

set -u

NO_ATTACH=0
for arg in "$@"; do
  case "$arg" in
    --no-attach) NO_ATTACH=1 ;;
    -h|--help)
      sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      printf 'unknown argument: %s\n' "$arg" >&2
      exit 2
      ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/.." && pwd)"
REVIVE="$REPO/bin/claude-revive"

maybe_attach() {
  [[ "$NO_ATTACH" -eq 1 ]] && return 0
  tmux attach -t work
}

# Auto-restore tracked project sessions that aren't currently in tmux. Runs
# in both the "session already up" and "session just created" paths so the
# user doesn't have to confirm respawns after a tmux kill-server. The dir
# check skips state entries whose project directory has been removed; those
# get surfaced by the orchestrator's own claude-state missing check instead.
restore_missing() {
  local name path
  while IFS=$'\t' read -r name path; do
    [[ -z "$name" ]] && continue
    if [[ ! -d "$path" ]]; then
      printf '[start-work] WARN %s -> %s: dir missing, skipping\n' "$name" "$path" >&2
      continue
    fi
    printf '[start-work] restoring %s -> %s\n' "$name" "$path"
    tmux new-window -t work -c "$path" -n "$name"
    tmux send-keys -t "work:$name" "$REVIVE" Enter
  done < <("$REPO/bin/claude-state" missing)
}

if tmux has-session -t work 2>/dev/null; then
  # Refresh the global env in case the repo moved since the server started.
  tmux set-environment -g CLAUDE_ORCHESTRATOR_HOME "$REPO"
else
  # Seed the tmux server env before spawning any windows so every child shell
  # inherits CLAUDE_ORCHESTRATOR_HOME.
  tmux set-environment -g CLAUDE_ORCHESTRATOR_HOME "$REPO"
  tmux new-session -d -s work -c "$REPO" -n orchestrator
  tmux send-keys -t work:orchestrator "$REVIVE" Enter
fi

restore_missing

maybe_attach
