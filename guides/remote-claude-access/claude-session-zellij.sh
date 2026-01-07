#!/usr/bin/env bash
set -euo pipefail

# Claude Code Zellij Session Manager
# Port of your tmux manager, adapted to Zellij primitives.

CLAUDE_SESSION_PREFIX="${CLAUDE_SESSION_PREFIX:-claude}"
CLAUDE_CMD="${CLAUDE_CMD:-claude}"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'
CYAN='\033[0;36m'; BOLD='\033[1m'; DIM='\033[2m'; NC='\033[0m'

sanitize() { echo "$1" | sed 's/[^a-zA-Z0-9_-]/-/g; s/--*/-/g; s/^-//; s/-$//' | sed 's/^$/main/'; }

git_repo_name() {
  if git rev-parse --is-inside-work-tree &>/dev/null; then
    if origin="$(git remote get-url origin 2>/dev/null)"; then
      basename "${origin%.git}"
    else
      basename "$(git rev-parse --show-toplevel)"
    fi
  else
    return 1
  fi
}

contextual_name() {
  if repo="$(git_repo_name 2>/dev/null)"; then
    sanitize "$repo"
  else
    d="$(basename "$(pwd)")"
    [ -z "$d" ] && d="main"
    sanitize "$d"
  fi
}

full_session() { echo "${CLAUDE_SESSION_PREFIX}-$(sanitize "$1")"; }

list_sessions() { zellij list-sessions 2>/dev/null || true; }

session_exists() {
  local name="$1"; local target; target="$(full_session "$name")"
  list_sessions | awk '{print $1}' | grep -Fxq "$target"
}

attach_create() { zellij attach -c "$(full_session "$1")"; }

delete_session() { zellij delete-session "$(full_session "$1")" --force; }

start_with_layout() {
  local name="$1" cmd="$2"
  local session; session="$(full_session "$name")"

  # Start a new named session using the user's normal config,
  # but set the default shell to Claude so it launches immediately.
  # This attaches synchronously and avoids ENODEV / layout overrides.
  # See: zellij User Guide → Command Line Configuration Options
  #   --session-name, --default-shell, --attach-to-session
  zellij options \
    --session-name "$session" \
    --default-shell "$cmd" \
    --attach-to-session true
}

# ----- actions -----

list_cmd() {
  local interactive="${1:-false}"
  local out; out="$(list_sessions)"
  if [ -z "$out" ]; then
    echo -e "${DIM}No Zellij sessions.${NC}"; return 1
  fi
  echo "$out"
  if [[ "$interactive" =~ ^(true|i|interactive)$ ]]; then
    if command -v fzf >/dev/null 2>&1; then
      sel="$(list_sessions | fzf --ansi --border --reverse --height=40% --prompt='Sessions > ' --color='header:blue,prompt:cyan,pointer:green,marker:magenta' | awk '{print $1}')"
      [ -n "$sel" ] && zellij attach "$sel"
    else
      echo -e "${YELLOW}Install fzf for interactive mode (brew install fzf)${NC}"
    fi
  fi
}

new_cmd() {
  local name="${1:-}"; local n
  n="${name:-$(contextual_name)}"
  if session_exists "$n"; then
    echo -e "${YELLOW}Session exists; attaching: $(full_session "$n")${NC}"
    attach_create "$n"
  else
    echo -e "${GREEN}Creating: $(full_session "$n") with \`${CLAUDE_CMD}\`${NC}"
    start_with_layout "$n" "$CLAUDE_CMD"
  fi
}

attach_cmd() {
  local name="${1:-}"; local n; n="${name:-$(contextual_name)}"
  attach_create "$n"
}

kill_cmd() {
  local name="${1:-}"
  if [ -z "$name" ]; then
    if command -v fzf >/dev/null 2>&1; then
      sel="$(list_sessions | fzf --ansi --border --reverse --height=40% --prompt='Sessions > ' --color='header:blue,prompt:cyan,pointer:green,marker:magenta' | awk '{print $1}')"
      [ -z "$sel" ] && return 1
      zellij delete-session "$sel" --force
      echo -e "${GREEN}Killed $sel${NC}"
    else
      echo -e "${YELLOW}Provide a name or install fzf.${NC}"; return 2
    fi
  else
    zellij delete-session "$(full_session "$name")" --force
    echo -e "${GREEN}Killed $(full_session "$name")${NC}"
  fi
}

send_cmd() {
  local name="${1:-}"; local text="${2:-}"; local no_enter="${3:-0}"
  if [ -z "$text" ]; then echo -e "${RED}No text provided${NC}"; return 2; fi
  local n; n="${name:-$(contextual_name)}"; local sess; sess="$(full_session "$n")"
  zellij --session "$sess" action write-chars "$text" >/dev/null || {
    echo -e "${RED}Failed to send (session running?)${NC}"; return 1; }
  if [ "$no_enter" != "1" ]; then
    zellij --session "$sess" action write 13 >/dev/null || true
  fi
  echo -e "${GREEN}Sent to ${sess}${NC}"
}

capture_cmd() {
  local name="${1:-}"; local file="${2:-}"; local full="${3:-1}"
  local n; n="${name:-$(contextual_name)}"; local sess; sess="$(full_session "$n")"
  local out="${file:-claude-output-$(sanitize "$n").txt}"
  if [ "$full" = "1" ]; then
    zellij --session "$sess" action dump-screen --full "$out" >/dev/null 2>&1 || \
    zellij --session "$sess" action dump-screen "$out" >/dev/null 2>&1
  else
    zellij --session "$sess" action dump-screen "$out" >/dev/null 2>&1
  fi
  if [ -f "$out" ]; then
    echo -e "${GREEN}Saved → $out${NC}"
  else
    echo -e "${RED}Capture failed${NC}"; return 1
  fi
}

monitor_cmd() {
  local name="${1:-}"; local interval="${2:-5}"; local tail="${3:-20}"
  local n; n="${name:-$(contextual_name)}"; local sess; sess="$(full_session "$n")"
  local tmp; tmp="$(mktemp)"; trap 'rm -f "$tmp"' EXIT
  while true; do
    if ! zellij --session "$sess" action dump-screen --full "$tmp" >/dev/null 2>&1; then
      zellij --session "$sess" action dump-screen "$tmp" >/dev/null 2>&1 || true
    fi
    clear
    echo "Session: $sess"
    printf '%0.s─' {1..60}; echo
    if [ -s "$tmp" ]; then tail -n "$tail" "$tmp"; else echo "(no output)"; fi
    echo; echo "Ctrl-C to stop"
    sleep "$interval"
  done
}

quickstart_cmd() {
  local n; n="$(contextual_name)"
  if session_exists "$n"; then
    attach_create "$n"
  else
    start_with_layout "$n" "$CLAUDE_CMD"
  fi
}

usage() {
  cat <<'USAGE'
Claude Code Zellij Session Manager

Usage:
  claude-session-zellij.sh list [interactive]
  claude-session-zellij.sh new [name]
  claude-session-zellij.sh attach [name]
  claude-session-zellij.sh kill [name]
  claude-session-zellij.sh send [name] "text" [no_enter:0|1]
  claude-session-zellij.sh capture [name] [file] [full:1|0]
  claude-session-zellij.sh monitor [name] [interval] [tail]
  claude-session-zellij.sh quickstart

Env:
  CLAUDE_SESSION_PREFIX (default: claude)
  CLAUDE_CMD            (default: claude)
USAGE
}

cmd="${1:-}"; shift || true
case "$cmd" in
  list|ls)        list_cmd "${1:-false}" ;;
  new|create)     new_cmd "${1:-}" ;;
  attach|a)       attach_cmd "${1:-}" ;;
  kill|stop)      kill_cmd "${1:-}" ;;
  send)           send_cmd "${1:-}" "${2:-}" "${3:-0}" ;;
  capture)        capture_cmd "${1:-}" "${2:-}" "${3:-1}" ;;
  monitor|watch)  monitor_cmd "${1:-}" "${2:-5}" "${3:-20}" ;;
  quickstart|qs)  quickstart_cmd ;;
  ""|-h|--help)   usage ;;
  *) echo "Unknown: $cmd"; usage; exit 2 ;;
esac