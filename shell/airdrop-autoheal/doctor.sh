#!/bin/bash
# airdrop-autoheal doctor — one-shot health + diagnostics report (Darcula-themed).
# Run:  sudo bash doctor.sh        (root gives full detail; runs without too)
#   --no-color / NO_COLOR=1        force plain output
# Exit code = number of FAILs (0 = healthy).
set -uo pipefail
export PATH=/usr/bin:/bin:/usr/sbin:/sbin

LABEL=com.indrasvat.airdrop-autoheal
LOG=/var/log/airdrop-autoheal.log
ERR=/var/log/airdrop-autoheal.err
APPDIR="/Library/Application Support/airdrop-autoheal"
BIN="$APPDIR/airdrop-autoheal.sh"
PLIST="/Library/LaunchDaemons/${LABEL}.plist"
NEWSYSLOG="/etc/newsyslog.d/airdrop-autoheal.conf"
PRED='processImagePath == "/usr/libexec/sharingd" AND eventMessage CONTAINS "quic_migration_path_unavailable" AND eventMessage CONTAINS "awdl0"'
BW=60   # rule width (single source of truth)

# ---- Darcula palette (24-bit truecolor); auto-off when not a TTY / NO_COLOR ----
# Precedence: NO_COLOR / --no-color always win; FORCE_COLOR enables off a TTY;
# otherwise auto-detect (color only when stdout is a terminal).
want_color=0
[ -t 1 ] && want_color=1
[ -n "${FORCE_COLOR:-}" ] && want_color=1
[ -n "${NO_COLOR:-}" ] && want_color=0
[ "${1:-}" = "--no-color" ] && want_color=0
if [ "$want_color" = 1 ]; then
  R=$'\033[0m'; B=$'\033[1m'; DIM=$'\033[2m'
  FG=$'\033[38;2;169;183;198m'    # #A9B7C6 foreground
  GRY=$'\033[38;2;128;128;128m'   # #808080 comment gray
  ORG=$'\033[38;2;204;120;50m'    # #CC7832 keyword orange
  YEL=$'\033[38;2;255;198;109m'   # #FFC66D function yellow
  GRN=$'\033[38;2;152;195;121m'   # bright green
  BLU=$'\033[38;2;104;151;187m'   # #6897BB number blue
  RED=$'\033[38;2;255;107;104m'   # #FF6B68 error red
  CYN=$'\033[38;2;88;157;175m'    # teal accent
  WHT=$'\033[38;2;240;240;240m'
  INK=$'\033[38;2;30;30;30m'      # dark ink for filled badges
  BG_GRN=$'\033[48;2;106;135;89m'; BG_YEL=$'\033[48;2;204;120;50m'; BG_RED=$'\033[48;2;188;63;60m'
else
  R=''; B=''; DIM=''; FG=''; GRY=''; ORG=''; YEL=''; GRN=''; BLU=''; RED=''; CYN=''; WHT=''; INK=''
  BG_GRN=''; BG_YEL=''; BG_RED=''
fi

pass=0; warn=0; fail=0

rule()    { local i s=""; for ((i=0; i<BW; i++)); do s="${s}${1:-━}"; done; printf '%b%s%b\n' "$CYN" "$s" "$R"; }
section() { printf '\n  %b❯%b %b%b%s%b\n' "$ORG" "$R" "$B" "$FG" "$1" "$R"; }
ok()   { printf '    %b%b OK   %b %b%s%b\n' "$B$BG_GRN" "$INK" "$R" "$FG"  "$*" "$R"; pass=$((pass + 1)); }
wn()   { printf '    %b%b WARN %b %b%s%b\n' "$B$BG_YEL" "$INK" "$R" "$YEL" "$*" "$R"; warn=$((warn + 1)); }
bad()  { printf '    %b%b FAIL %b %b%s%b\n' "$B$BG_RED" "$WHT" "$R" "$RED" "$*" "$R"; fail=$((fail + 1)); }
dimblk(){ printf '%b' "$GRY"; sed 's/^/         /'; printf '%b' "$R"; }   # dim a stdin block

# ---- header ----
echo
rule "━"
printf '   %b%bairdrop-autoheal%b %b·%b %b%bdoctor%b\n' "$ORG" "$B" "$R" "$GRY" "$R" "$CYN" "$B" "$R"
rule "━"
if [ "$(id -u)" -eq 0 ]; then modes="${GRN}root${R}"; else modes="${DIM}non-root — sudo for full detail${R}"; fi
printf '   %btime%b %b%s%b  %b·%b  %buser%b %b%s%b  %b·%b  %b\n' \
  "$GRY" "$R" "$BLU" "$(date '+%Y-%m-%d %H:%M:%S')" "$R" "$GRY" "$R" \
  "$GRY" "$R" "$FG" "$(id -un)" "$R" "$GRY" "$R" "$modes"

# ---- install ----
section "install"
if [ -f "$BIN" ]; then ok "watcher present"; else bad "watcher MISSING: $BIN"; fi
if [ -f "$PLIST" ]; then ok "plist present"; else bad "plist MISSING: $PLIST"; fi
if [ -f "$NEWSYSLOG" ]; then ok "log rotation configured"; else wn "no newsyslog config — logs may grow unbounded"; fi

# ---- launchd job ----
section "launchd job"
if info=$(launchctl print "system/${LABEL}" 2>/dev/null); then
  st=$(printf '%s\n'   "$info" | awk -F'= ' '/[ \t]state = /{print $2; exit}')
  jpid=$(printf '%s\n' "$info" | awk -F'= ' '/[ \t]pid = /{print $2; exit}')
  runs=$(printf '%s\n' "$info" | awk -F'= ' '/[ \t]runs = /{print $2; exit}')
  if [ "$st" = "running" ]; then ok "job running (pid ${jpid:-?}, runs ${runs:-?})"; else wn "job state: ${st:-unknown} (pid ${jpid:-none})"; fi
  case "${runs:-}" in ''|*[!0-9]*) : ;; *) [ "$runs" -gt 20 ] && wn "high restart count (runs=${runs}) — possible flapping";; esac
else
  wn "cannot query launchd job (need sudo) — checking processes directly"
fi

# ---- process tree ----
section "process tree"
# note: `ps -o comm=` may print a full path (e.g. /usr/bin/log) on macOS, so
# normalize with basename before comparing.
mainpid=""
for p in $(pgrep -f "airdrop-autoheal/airdrop-autoheal.sh" 2>/dev/null); do
  cb=$(basename "$(ps -p "$p" -o comm= 2>/dev/null)" 2>/dev/null)
  pp=$(ps -p "$p" -o ppid= 2>/dev/null | tr -d ' ')
  [ "$cb" = "bash" ] && [ "$pp" = "1" ] && mainpid="$p"
done
if [ -n "$mainpid" ]; then
  ok "daemon main loop alive (pid $mainpid)"
  logchild=""
  for c in $(pgrep -P "$mainpid" 2>/dev/null); do
    [ "$(basename "$(ps -p "$c" -o comm= 2>/dev/null)" 2>/dev/null)" = "log" ] && logchild="$c"
  done
  if [ -n "$logchild" ]; then ok "log stream child alive (pid $logchild) — actively watching"; else bad "no log stream child — daemon may be wedged / not watching"; fi
else
  bad "daemon main loop NOT running"
fi

# ---- orphan scan ----
section "orphan scan (must be empty)"
# shellcheck disable=SC2009  # need ppid + full command line together; pgrep can't filter on both
orphans=$(ps -axo pid,ppid,comm,command 2>/dev/null \
  | grep "processImagePath" | grep -v grep \
  | grep -viE "skycomputer|codex|doctor|SharedSupport|claude" \
  | awk -v m="${mainpid:-0}" '$3 ~ /(^|\/)log$/ && $2!=m {print $1}')
if [ -z "$orphans" ]; then ok "no orphaned log-stream processes"; else for o in $orphans; do bad "ORPHAN log stream pid=$o (parent != daemon)"; done; fi

# ---- predicate ----
section "detection predicate"
if log show --last 1m --predicate "$PRED" >/dev/null 2>&1; then ok "predicate parses & is accepted by log(1)"; else bad "predicate REJECTED by log(1)"; fi

# ---- awdl0 ----
section "awdl0"
aw=$(ifconfig awdl0 2>/dev/null | awk '/status:/{print $2}')
if [ "$aw" = "active" ]; then ok "awdl0 status: active"; else wn "awdl0 status: ${aw:-MISSING}"; fi

# ---- audit log ----
section "audit log"
if [ -r "$LOG" ]; then
  sz=$(stat -f '%z' "$LOG" 2>/dev/null)
  nb=$(grep -c "BOUNCED awdl0" "$LOG" 2>/dev/null || true); nb=${nb:-0}
  ok "log readable (${sz} bytes, ${nb} total bounces)"
  lh=$(grep "heartbeat" "$LOG" 2>/dev/null | tail -1); [ -n "$lh" ] && printf '%b         last heartbeat: %s%b\n' "$GRY" "$lh" "$R"
  printf '         %blast 6 events:%b\n' "$DIM" "$R"
  tail -n 6 "$LOG" 2>/dev/null | dimblk
else
  wn "audit log not readable here (try: sudo bash doctor.sh): $LOG"
fi
if [ -r "$ERR" ]; then
  es=$(stat -f '%z' "$ERR" 2>/dev/null)
  case "${es:-0}" in 0) ok "stderr clean (0 bytes)";; *) wn "stderr non-empty (${es}B) — inspect $ERR"; tail -n 3 "$ERR" 2>/dev/null | dimblk;; esac
fi

# ---- resource use ----
section "resource use"
[ -n "$mainpid" ] && ps -p "$mainpid" -o pid,pcpu,pmem,etime,comm 2>/dev/null | dimblk

# ---- summary ----
echo
rule "━"
if [ "$fail" -eq 0 ]; then vbg="$BG_GRN"; vink="$INK"; verdict="HEALTHY"; else vbg="$BG_RED"; vink="$WHT"; verdict="NEEDS ATTENTION"; fi
printf '  %b%b %s %b   %b%d OK%b   %b%d WARN%b   %b%d FAIL%b\n' \
  "$B$vbg" "$vink" "$verdict" "$R" "$GRN" "$pass" "$R" "$YEL" "$warn" "$R" "$RED" "$fail" "$R"
echo
exit "$fail"
