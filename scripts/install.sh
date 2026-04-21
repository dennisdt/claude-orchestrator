#!/bin/bash
# install.sh — one-shot setup for claude-orchestrator.
#
# Installs the macOS tmux-keychain fix so Claude Code inside tmux can reach
# the login Keychain (avoids the "/login" credential prompt loop). Safe to
# re-run — each step is idempotent.
#
# What it does:
#   1. brew install reattach-to-user-namespace (if missing)
#   2. Appends the default-command line to ~/.tmux.conf (if missing)
#   3. Prompts to kill the tmux server so the change takes effect
#
# Reference: https://www.junyi.dev/en/posts/tmux-keychain/

set -euo pipefail

TMUX_LINE='set-option -g default-command "reattach-to-user-namespace -l ${SHELL}"'
TMUX_CONF="$HOME/.tmux.conf"

say() { printf '\033[1;36m[install]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[install]\033[0m %s\n' "$*" >&2; }

if [[ "$(uname)" != "Darwin" ]]; then
  warn "Non-macOS host detected. The Keychain fix is macOS-only; skipping."
  exit 0
fi

if ! command -v brew >/dev/null 2>&1; then
  warn "Homebrew not found. Install from https://brew.sh first, then re-run."
  exit 1
fi

if brew list --formula reattach-to-user-namespace >/dev/null 2>&1; then
  say "reattach-to-user-namespace already installed."
else
  say "Installing reattach-to-user-namespace via Homebrew..."
  brew install reattach-to-user-namespace
fi

touch "$TMUX_CONF"
if grep -Fq 'reattach-to-user-namespace' "$TMUX_CONF"; then
  say "~/.tmux.conf already references reattach-to-user-namespace."
else
  say "Appending default-command to ~/.tmux.conf..."
  {
    printf '\n# claude-orchestrator: macOS Keychain bridge for tmux (see scripts/install.sh)\n'
    printf '%s\n' "$TMUX_LINE"
  } >> "$TMUX_CONF"
fi

say "Done."
echo
if tmux list-sessions >/dev/null 2>&1; then
  warn "A tmux server is already running. Changes take effect on a fresh server."
  warn "When you're ready, stop all tmux work and run: tmux kill-server"
else
  say "Start a new tmux session with: scripts/start-work.sh"
fi
