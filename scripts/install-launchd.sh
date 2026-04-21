#!/bin/bash
# install-launchd.sh — install (or remove) the claude-orchestrator LaunchAgent.
#
# With no args: renders launchd/com.claude-orchestrator.plist.template with
# this repo's absolute path, drops it at ~/Library/LaunchAgents/, and
# bootstraps it via launchctl so the orchestrator tmux session comes up at
# every login.
#
# With --uninstall: booteds it out and removes the plist.
#
# Logs to /tmp/claude-orchestrator.log. Safe to re-run.

set -euo pipefail

LABEL="com.claude-orchestrator"
AGENT_DIR="$HOME/Library/LaunchAgents"
PLIST="$AGENT_DIR/$LABEL.plist"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/.." && pwd)"
TEMPLATE="$REPO/launchd/$LABEL.plist.template"

say() { printf '\033[1;36m[launchd]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[launchd]\033[0m %s\n' "$*" >&2; }

if [[ "$(uname)" != "Darwin" ]]; then
  warn "LaunchAgents are macOS-only. Skipping."
  exit 0
fi

bootout() {
  launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
}

bootstrap() {
  launchctl bootstrap "gui/$(id -u)" "$PLIST"
}

if [[ "${1:-}" == "--uninstall" ]]; then
  if [[ -f "$PLIST" ]]; then
    say "Unloading and removing $PLIST"
    bootout
    rm -f "$PLIST"
  else
    say "No plist at $PLIST — nothing to remove."
  fi
  exit 0
fi

if [[ ! -f "$TEMPLATE" ]]; then
  warn "Template missing: $TEMPLATE"
  exit 1
fi

mkdir -p "$AGENT_DIR"

say "Rendering plist with REPO=$REPO"
sed "s|__REPO__|$REPO|g" "$TEMPLATE" > "$PLIST"

say "Reloading LaunchAgent..."
bootout
bootstrap

say "Installed. It will run at every login, and is running now."
say "Logs: /tmp/claude-orchestrator.log"
say "Uninstall with: scripts/install-launchd.sh --uninstall"
