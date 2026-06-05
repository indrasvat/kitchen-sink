#!/bin/bash
# airdrop-autoheal — watch the unified log for the AirDrop awdl0 path-migration
# failure fingerprint and re-prime awdl0. Runs as a root LaunchDaemon.
#   (no args)      run as the daemon
#   --bounce-once  one manual reset (root)   — also your hotkey-able reset
# Health/diagnostics: run  doctor.sh  (installed alongside).
#
# Robustness (each verified by test):
#  - log stream is a DIRECTLY-backgrounded child with a known PID, read via a
#    FIFO in the ROOT-ONLY install dir (not world-writable /tmp). The trap kills
#    exactly that PID — guarded against PID reuse — so NO orphan is ever left.
#  - predicate pins the real Apple binary (processImagePath) — unspoofable.
#  - signals exit explicitly (never resume mid-bounce); EXIT trap forces awdl0 UP
#    with retries (never wedged down).
#  - heartbeat distinguishes idle-timeout from stream-death via `kill -0`, so it
#    is correct on /bin/bash 3.2 (where `read -t` timeout returns 1, like EOF).
#  - circuit breaker caps bounces/window; pinned PATH + absolute binaries.
set -euo pipefail
export PATH=/usr/bin:/bin:/usr/sbin:/sbin

IFCONFIG=/sbin/ifconfig
LOGBIN=/usr/bin/log
AWK=/usr/bin/awk
DATE=/bin/date

LOG=/var/log/airdrop-autoheal.log
APPDIR="/Library/Application Support/airdrop-autoheal"   # root-only (0755 root:wheel)
IFACE=awdl0
COOLDOWN=30                 # min seconds between bounces
BREAKER_MAX=6               # at most this many bounces ...
BREAKER_WINDOW=600          # ... per this many seconds, else pause (circuit breaker)
HEARTBEAT=3600              # log a liveness line every N idle seconds
PRED='processImagePath == "/usr/libexec/sharingd" AND eventMessage CONTAINS "quic_migration_path_unavailable" AND eventMessage CONTAINS "awdl0"'

last_bounce=0
breaker_start=0
breaker_count=0
STREAM_PID=""
FIFO=""

ts()   { "$DATE" '+%Y-%m-%d %H:%M:%S'; }
note() { printf '%s  %s\n' "$(ts)" "$*" >>"$LOG" 2>/dev/null || true; }

# Bring awdl0 up, with retries. Shared by bounce() and cleanup().
force_up() {
  "$IFCONFIG" "$IFACE" up >/dev/null 2>&1 && return 0
  for _ in 1 2 3; do
    sleep 1
    "$IFCONFIG" "$IFACE" up >/dev/null 2>&1 && return 0
  done
  return 1
}

# Kill ONLY our own stream child (guarded against PID reuse), then leave awdl0 up.
# shellcheck disable=SC2329  # invoked via trap
cleanup() {
  if [ -n "${STREAM_PID:-}" ] && kill -0 "$STREAM_PID" 2>/dev/null; then
    if [ "$(ps -p "$STREAM_PID" -o ppid= 2>/dev/null | tr -d ' ')" = "$$" ]; then
      kill "$STREAM_PID" 2>/dev/null || true
      wait "$STREAM_PID" 2>/dev/null || true
    fi
  fi
  [ -n "${FIFO:-}" ] && rm -f "$FIFO" 2>/dev/null || true
  force_up || true
}

# single quotes intentional: $2 is an awk field, not a shell variable.
# shellcheck disable=SC2016
status() { "$IFCONFIG" "$IFACE" 2>/dev/null | "$AWK" '/^[[:space:]]*status:/{print $2; exit}' || true; }

bounce() {
  local before after
  before=$(status)
  if ! "$IFCONFIG" "$IFACE" down 2>>"$LOG"; then
    note "ERROR: '$IFACE down' failed — leaving interface as-is"
    return 1
  fi
  sleep 1
  if ! force_up; then
    note "FATAL: $IFACE may be left DOWN after retries — exiting for launchd to recover"
    exit 1
  fi
  sleep 1
  after=$(status)
  note "BOUNCED $IFACE  (status ${before:-?} -> ${after:-?})"
  return 0
}

# ---- one-shot manual reset (root): minimal trap (just ensure awdl0 up) ----
if [ "${1:-}" = "--bounce-once" ]; then
  if [ "$(id -u)" -ne 0 ]; then echo "must be root: sudo $0 --bounce-once" >&2; exit 1; fi
  trap 'force_up || true' EXIT
  trap 'exit 143' INT TERM HUP
  note "manual --bounce-once invoked"
  bounce          # propagate status so a hotkey/script sees a reset that failed
  exit $?         # (the EXIT trap still forces awdl0 back up regardless)
fi

# ---- daemon ----
# cleanup runs once on EXIT; signals trigger an explicit exit (which fires the
# EXIT trap), so a TERM/HUP during startup or a bounce never RESUMES the script.
trap cleanup EXIT
trap 'exit 143' INT TERM HUP

# FIFO in the root-only install dir + unique name: an unprivileged user cannot
# pre-create it (no /tmp DoS), and the unique name avoids any multi-instance race.
FIFO="$(mktemp -u "${APPDIR}/stream.XXXXXX")" || { note "FATAL: mktemp failed"; exit 1; }
if ! mkfifo -m 0600 "$FIFO" 2>>"$LOG"; then note "FATAL: mkfifo $FIFO failed"; exit 1; fi
"$LOGBIN" stream --style compact --predicate "$PRED" >"$FIFO" 2>>"$LOG" &
STREAM_PID=$!
exec 3<"$FIFO"

note "=== airdrop-autoheal started (pid $$, stream $STREAM_PID, cooldown ${COOLDOWN}s, breaker ${BREAKER_MAX}/${BREAKER_WINDOW}s) ==="

while :; do
  if IFS= read -r -t "$HEARTBEAT" line <&3; then
    :   # got a line — fall through to process it
  else
    # read failed: idle-timeout (stream alive) vs stream death. Distinguish by
    # the stream's process STATE — NOT `kill -0`, which is fooled by an unreaped
    # zombie (a dead child still "exists"), spinning this loop and spamming the
    # log. State "Z" (zombie) or empty (reaped/gone) both mean the stream died.
    sstate="$(ps -p "$STREAM_PID" -o state= 2>/dev/null | cut -c1)"
    if [ -n "$sstate" ] && [ "$sstate" != "Z" ]; then
      note "heartbeat — watching (awdl0 $(status), bounces this window ${breaker_count})"
      continue
    fi
    break   # stream dead/zombie → exit non-zero for launchd to relaunch
  fi

  case "$line" in
    *quic_migration_path_unavailable*) : ;;
    *) continue ;;
  esac

  now=$("$DATE" +%s)
  if [ "$((now - last_bounce))" -lt "$COOLDOWN" ]; then
    note "failure seen (within ${COOLDOWN}s cooldown) — skipping"
    continue
  fi
  if [ "$((now - breaker_start))" -ge "$BREAKER_WINDOW" ]; then
    breaker_start=$now
    breaker_count=0
  fi
  if [ "$breaker_count" -ge "$BREAKER_MAX" ]; then
    note "CIRCUIT BREAKER tripped (>=${BREAKER_MAX} bounces / ${BREAKER_WINDOW}s) — NOT bouncing; investigate"
    continue
  fi
  last_bounce=$now
  breaker_count=$((breaker_count + 1))
  note "DETECTED AirDrop awdl0 path-migration failure (#${breaker_count} this window)"
  bounce || note "bounce returned non-zero"
done

note "=== log stream ended (stream $STREAM_PID gone) — exiting non-zero for launchd relaunch ==="
exit 1
