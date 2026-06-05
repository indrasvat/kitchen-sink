#!/bin/bash
# Confirm the auto-heal works without a forgeable backdoor:
#   1) daemon is loaded
#   2) the detection predicate is valid AND matches real failures in the log
#   3) the bounce ACTION works end-to-end via the root-only --bounce-once path
# Uses sudo for the root-only action test (step 3).
set -uo pipefail

LABEL=com.indrasvat.airdrop-autoheal
LOG=/var/log/airdrop-autoheal.log
BIN="/Library/Application Support/airdrop-autoheal/airdrop-autoheal.sh"
PRED='processImagePath == "/usr/libexec/sharingd" AND eventMessage CONTAINS "quic_migration_path_unavailable" AND eventMessage CONTAINS "awdl0"'

echo "=== airdrop-autoheal self-test ==="

# 1) loaded & running?
if ! launchctl print "system/${LABEL}" >/dev/null 2>&1; then
  echo "1) daemon: NOT loaded — run: sudo bash install.sh"
  exit 1
fi
echo "1) daemon: loaded"
launchctl print "system/${LABEL}" 2>/dev/null | awk '/state = |pid = /{gsub(/^[ \t]+/,""); print "     "$0}'

# 2) predicate: valid syntax + how many real failures it caught recently
echo "2) detection predicate vs. real logs (scanning last 12h — this takes a moment)…"
if out=$(log show --last 12h --predicate "$PRED" --style compact 2>/dev/null); then
  hits=$(printf '%s\n' "$out" | grep -c quic_migration_path_unavailable || true)
  echo "     predicate VALID; matched ${hits} real awdl0-failure event(s) in last 12h"
  echo "     (0 just means no failures happened recently — the predicate still parses & arms.)"
else
  echo "     predicate REJECTED by log(1) — syntax error, fix before trusting it"
  exit 1
fi

# 3) action path: root-only one-shot bounce — the exact code the daemon runs
echo "3) exercising the bounce action via 'sudo --bounce-once'…"
before=$(/sbin/ifconfig awdl0 2>/dev/null | awk '/status:/{print $2}')
sudo "$BIN" --bounce-once
sleep 1
after=$(/sbin/ifconfig awdl0 2>/dev/null | awk '/status:/{print $2}')
if sudo tail -n 5 "$LOG" 2>/dev/null | grep -q "BOUNCED awdl0"; then
  echo "     PASS — bounce executed + logged (awdl0 ${before:-?} -> ${after:-?})"
else
  echo "     FAIL — no BOUNCED line in audit log"
  exit 1
fi

echo
echo "RESULT: predicate validated against real logs + bounce action verified end-to-end."
