#!/bin/bash
# install-launchd.sh — install (or remove) the claude-orchestrator LaunchAgents.
#
# Installs two agents:
#   * com.claude-orchestrator   — brings the "work" tmux session up at login.
#   * com.claude-rc-watchdog    — polls panes for Remote-Control relay drops
#                                 and SIGTERMs claude so claude-revive can
#                                 re-register.
#
# Both plists are rendered from launchd/<label>.plist.template with this
# repo's absolute path, dropped at ~/Library/LaunchAgents, and bootstrapped
# via launchctl. Logs land in /tmp/<label>.log. Safe to re-run.
#
# Flags:
#   --uninstall           Remove both agents.
#   --orchestrator-only   Install just the orchestrator (legacy behavior).

set -euo pipefail

LABELS=(com.claude-orchestrator com.claude-rc-watchdog)
AGENT_DIR="$HOME/Library/LaunchAgents"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/.." && pwd)"

say() { printf '\033[1;36m[launchd]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[launchd]\033[0m %s\n' "$*" >&2; }

if [[ "$(uname)" != "Darwin" ]]; then
  warn "LaunchAgents are macOS-only. Skipping."
  exit 0
fi

bootout_label() {
  launchctl bootout "gui/$(id -u)/$1" 2>/dev/null || true
}

install_label() {
  local label=$1
  local plist="$AGENT_DIR/$label.plist"
  local template="$REPO/launchd/$label.plist.template"

  if [[ ! -f "$template" ]]; then
    warn "Template missing: $template"
    return 1
  fi

  say "Rendering $label with REPO=$REPO"
  sed "s|__REPO__|$REPO|g" "$template" > "$plist"

  say "Reloading $label..."
  bootout_label "$label"
  launchctl bootstrap "gui/$(id -u)" "$plist"
}

uninstall_label() {
  local label=$1
  local plist="$AGENT_DIR/$label.plist"

  if [[ -f "$plist" ]]; then
    say "Unloading and removing $plist"
    bootout_label "$label"
    rm -f "$plist"
  else
    say "No plist at $plist — nothing to remove."
  fi
}

case "${1:-}" in
  --uninstall)
    for l in "${LABELS[@]}"; do uninstall_label "$l"; done
    exit 0
    ;;
  --orchestrator-only)
    LABELS=(com.claude-orchestrator)
    ;;
  "")
    : # default — install all
    ;;
  *)
    warn "Unknown flag: $1"
    warn "Usage: $0 [--uninstall | --orchestrator-only]"
    exit 2
    ;;
esac

mkdir -p "$AGENT_DIR"

for label in "${LABELS[@]}"; do
  install_label "$label"
done

say "Installed: ${LABELS[*]}"
say "Logs: /tmp/com.claude-orchestrator.log, /tmp/claude-rc-watchdog.log"
say "Uninstall with: scripts/install-launchd.sh --uninstall"
