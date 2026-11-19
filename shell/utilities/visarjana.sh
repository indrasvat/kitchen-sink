#!/usr/bin/env bash
# visarjana — send off what agent sessions summoned and then forgot: shux daemons and sessions, and the headless
# Chromes agent-browser orphans. After a pūjā, the deities invoked with āvāhana are dismissed with visarjana.
# What counts as orphan, idle, in use or unknown, and what each run may dismiss: usage() below, and probe().
#
# Safety, in order of how much each matters:
#   - It shows the ledger first and acts only on what the ledger names. Without -y it asks; with no terminal to ask
#     on, it refuses (exit 2). Other agents on this machine may be using shux right now.
#   - Each daemon is classified again just before it is touched, and spared if it no longer qualifies or gained a
#     session after the ledger was taken.
#   - Every pid is re-checked against its command line just before it is signalled (pids get reused).
#   - A daemon is reached only on the socket it is seen holding (lsof), re-checked before every call: a shux client
#     pointed at a socket nobody serves would start a fresh daemon there.
#   - Sessions are killed by id, never by name (a name can start with "-" or match another id's prefix).
#   - When run from inside a shux pane, that pane's daemon is in use, always: killing it would kill this run.
#   - An Orca terminal is closed only when a `shux session attach` running in it (found by the
#     ORCA_TERMINAL_HANDLE in its own environment) follows a daemon this run stopped outright, which only --in-use
#     can do. Never by title or screen text, never a terminal running an agent, never the one running this.
#   - One run at a time (a lock in $TMPDIR).
set -uo pipefail

PROG=visarjana
VERSION=2.0.0

# Colour only for a person at a terminal: never under NO_COLOR, TERM=dumb, a pipe, or --json (cleared after parsing).
paint() { [ -t "$1" ] && [ -z "${NO_COLOR:-}" ] && [ "${TERM:-dumb}" != dumb ]; }
# One palette, by role:  HD heading · FL what you type · AR a value · MU muted detail ·
#                        OK success · WN warning/attention · FA failure · KP kept/spared · B bold · Z reset
if paint 1; then
    HD=$'\033[1;35m'; FL=$'\033[1;36m'; AR=$'\033[36m'; MU=$'\033[2m'
    OK=$'\033[32m'; WN=$'\033[33m'; FA=$'\033[31m'; KP=$'\033[34m'; B=$'\033[1m'; Z=$'\033[0m'
else HD=; FL=; AR=; MU=; OK=; WN=; FA=; KP=; B=; Z=; fi
if paint 2; then EFA=$'\033[1;31m'; EZ=$'\033[0m'; else EFA=; EZ=; fi

usage() {
    cat <<EOF
${HD}$PROG${Z} ${MU}$VERSION${Z} — dismiss forgotten shux daemons and orphaned agent-browser Chromes, on any repo on this machine.

${HD}Usage:${Z} ${FL}$PROG${Z} ${AR}[options]${Z}

${HD}Sorts what is running, shows it, asks, then dismisses only what is plainly abandoned:${Z}
  ${OK}orphan${Z}    a shux daemon with no sessions and no clients, up 10 minutes or more     ${B}dismissed${Z}
            a headless Chrome under ~/.agent-browser/browsers whose daemon is gone      ${B}dismissed${Z}
  ${WN}idle${Z}      a shux daemon whose sessions hold only shells at a prompt (or exited panes),
            with no clients, quiet for --idle-after                                   ${B}only with --idle${Z}
  ${KP}in use${Z}    attached or connected to, a command or program running in a pane, active
            within --idle-after, under 10 minutes old, or running this command         ${B}never in a sweep${Z}
  ${FA}unknown${Z}   its socket or sessions cannot be read                                     ${B}left alone${Z}
Open agent-browser sessions are listed, never closed: nothing tells an abandoned one from a busy one.
To tear down a unit you own, name its daemon: ${FL}$PROG -s SOCKET --in-use${Z} (also closes the Orca
terminal attached to it). It ${B}never${Z} touches your own Chrome, kind clusters, git, or files.

${HD}Options:${Z}
  ${FL}-n, --dry-run${Z}         show the ledger and stop                       ${MU}[VISARJANA_DRY_RUN=1]${Z}
  ${FL}-y, --yes${Z}             do not ask (needed when there is no terminal)  ${MU}[VISARJANA_YES=1]${Z}
      ${FL}--idle${Z}            also dismiss idle daemons and their sessions   ${MU}[VISARJANA_IDLE=1]${Z}
      ${FL}--idle-after${Z} ${AR}AGE${Z}  quiet this long counts as idle: 30m, 6h, 2d; at least 10m (default 6h)
                                                                       ${MU}[VISARJANA_IDLE_AFTER]${Z}
  ${FL}-s, --socket${Z} ${AR}PATH${Z}     only shux daemons on this socket; repeatable   ${MU}[VISARJANA_SOCKET=p1,p2]${Z}
      ${FL}--in-use${Z}          dismiss the daemons named with -s even when in use (needs -s; no env)
  ${FL}-k, --keep${Z} ${AR}NAME${Z}       spare the daemon holding this session (name, id or short id);
                        a NAME that matches nothing stops the run; repeatable
                                                                       ${MU}[VISARJANA_KEEP=a,b]${Z}
  ${FL}-o, --only${Z} ${AR}WHAT${Z}       shux | browser                                 ${MU}[VISARJANA_ONLY]${Z}
      ${FL}--no-orca${Z}         leave Orca terminals open                      ${MU}[VISARJANA_ORCA=0]${Z}
  ${FL}-g, --grace${Z} ${AR}SECONDS${Z}   seconds to wait for an exit (default 5)       ${MU}[VISARJANA_GRACE]${Z}
  ${FL}-f, --force${Z}           SIGKILL whatever outlives the grace period     ${MU}[VISARJANA_FORCE=1]${Z}
      ${FL}--json${Z}            one JSON object per line, no colour; needs jq and -y or -n
  ${FL}-h, --help${Z}            this help
  ${FL}-V, --version${Z}         print the version

${HD}Needs:${Z} jq and lsof (macOS ships lsof; brew install jq). Orca terminals need Orca's CLI:
       \$ORCA_CLI_COMMAND, else \`orca\` on macOS, else \`orca-ide\` (never a bare \`orca\` on Linux).

${HD}Exit:${Z} ${OK}0${Z} everything chosen was dismissed, nothing to do, or a clean --dry-run
      ${WN}1${Z} something chosen survived or changed under it, a daemon could not be read,
        a command failed, or you answered no (a --dry-run that finds such a problem also exits 1)
      ${FA}2${Z} usage error, a --keep that matches nothing, an unknown --socket,
        or asked to act with no terminal and no -y

${HD}Examples:${Z}
  ${FL}$PROG -n${Z}                              ${MU}# what is there, and what would go?${Z}
  ${FL}$PROG${Z}                                 ${MU}# show, ask, dismiss the orphans${Z}
  ${FL}$PROG --idle --idle-after 1d${Z}          ${MU}# also sessions nobody has touched for a day${Z}
  ${FL}$PROG -y -s /tmp/x/shux/shux.sock --in-use${Z}  ${MU}# tear down your own unit, tab and all${Z}
EOF
}

# ------------------------------------------------------------------ options ---
truthy() { case "${1:-}" in 1 | true | yes | on) return 0 ;; *) return 1 ;; esac; }
die_usage() { printf '%s%s:%s %s\n' "$EFA" "$PROG" "$EZ" "$1" >&2; printf "Try '%s --help'.\n" "$PROG" >&2; exit 2; }

DRY=0; YES=0; FORCE=0; JSON=0; WANT_ORCA=1; IDLE=0; IN_USE=0
truthy "${VISARJANA_DRY_RUN:-}" && DRY=1
truthy "${VISARJANA_YES:-}" && YES=1
truthy "${VISARJANA_FORCE:-}" && FORCE=1
truthy "${VISARJANA_IDLE:-}" && IDLE=1
case "${VISARJANA_ORCA:-}" in 0 | false | no | off) WANT_ORCA=0 ;; esac
ONLY=${VISARJANA_ONLY:-}
GRACE=${VISARJANA_GRACE:-5}
IDLE_AFTER=${VISARJANA_IDLE_AFTER:-6h}
KEEP=(); SOCKETS=()
if [ -n "${VISARJANA_KEEP:-}" ]; then IFS=, read -r -a KEEP <<<"$VISARJANA_KEEP"; fi
if [ -n "${VISARJANA_SOCKET:-}" ]; then IFS=, read -r -a SOCKETS <<<"$VISARJANA_SOCKET"; fi

need_val() { [ $# -ge 2 ] && [ -n "$2" ] && [ "${2#-}" = "$2" ] || die_usage "$1 needs a value"; }
while [ $# -gt 0 ]; do
    case "$1" in
        -n | --dry-run) DRY=1 ;;
        -y | --yes) YES=1 ;;
        -f | --force) FORCE=1 ;;
        --json) JSON=1 ;;
        --no-orca) WANT_ORCA=0 ;;
        --idle) IDLE=1 ;;
        --in-use) IN_USE=1 ;;
        --idle-after) need_val "$@"; IDLE_AFTER=$2; shift ;;
        --idle-after=*) IDLE_AFTER=${1#*=} ;;
        -k | --keep) need_val "$@"; KEEP+=("$2"); shift ;;
        --keep=*) KEEP+=("${1#*=}") ;;
        -s | --socket) need_val "$@"; SOCKETS+=("$2"); shift ;;
        --socket=*) SOCKETS+=("${1#*=}") ;;
        -o | --only) need_val "$@"; ONLY=$2; shift ;;
        --only=*) ONLY=${1#*=}; [ -n "$ONLY" ] || die_usage "--only= needs shux or browser" ;;
        -g | --grace) need_val "$@"; GRACE=$2; shift ;;
        --grace=*) GRACE=${1#*=} ;;
        -h | --help) usage; exit 0 ;;
        -V | --version) echo "${HD}$PROG${Z} ${MU}$VERSION${Z}"; exit 0 ;;
        --) shift; [ $# -eq 0 ] || die_usage "unexpected argument: $1"; break ;;
        -*) die_usage "unknown option: $1" ;;
        *) die_usage "unexpected argument: $1" ;;
    esac
    shift
done
case "$ONLY" in '' | shux | browser) ;; *) die_usage "--only takes shux or browser, not '$ONLY'" ;; esac
case "$GRACE" in '' | *[!0-9]*) die_usage "--grace takes whole seconds, not '$GRACE'" ;; esac
GRACE=${GRACE#"${GRACE%%[!0]*}"}; GRACE=${GRACE:-0}
[ "${#GRACE}" -le 3 ] || die_usage "--grace above 600 seconds is surely a mistake"
GRACE=$((10#$GRACE))   # 08 and 09 are not octal errors
[ "$GRACE" -le 600 ] || die_usage "--grace above 600 seconds is surely a mistake"
# AGE → seconds. Below 10 minutes a shell someone is reading would count as idle.
case "$IDLE_AFTER" in
    [1-9]m | [1-9][0-9]m | [1-9][0-9][0-9]m | [1-9][0-9][0-9][0-9]m) IDLE_AFTER=$(( 10#${IDLE_AFTER%m} * 60 )) ;;
    [1-9]h | [1-9][0-9]h | [1-9][0-9][0-9]h) IDLE_AFTER=$(( 10#${IDLE_AFTER%h} * 3600 )) ;;
    [1-9]d | [1-9][0-9]d) IDLE_AFTER=$(( 10#${IDLE_AFTER%d} * 86400 )) ;;
    *) die_usage "--idle-after takes minutes, hours or days, such as 30m, 6h or 2d; not '$IDLE_AFTER'" ;;
esac
[ "$IDLE_AFTER" -ge 600 ] || die_usage "--idle-after below 10m would count a shell someone is reading as idle"
for k in ${KEEP[@]+"${KEEP[@]}"}; do [ -n "$k" ] || die_usage "--keep needs a non-empty name"; done
# Daemons report absolute socket paths; make a relative --socket comparable.
for i in ${SOCKETS[@]+"${!SOCKETS[@]}"}; do
    case "${SOCKETS[$i]}" in /*) ;; '') die_usage "--socket needs a path" ;; *) SOCKETS[i]="$PWD/${SOCKETS[$i]}" ;; esac
done
[ "$IN_USE" = 0 ] || [ ${#SOCKETS[@]} -gt 0 ] || die_usage "--in-use dismisses daemons in use, so it needs each one named with -s"
if [ "$JSON" = 1 ]; then
    command -v jq >/dev/null || { printf '%s%s:%s --json needs jq on PATH\n' "$EFA" "$PROG" "$EZ" >&2; exit 1; }
    [ "$YES" = 1 ] || [ "$DRY" = 1 ] || die_usage "--json cannot prompt; add -y or -n"
fi
WANT_SHUX=1; WANT_BROWSER=1
[ "$ONLY" = browser ] && WANT_SHUX=0
[ "$ONLY" = shux ] && WANT_BROWSER=0
if [ ${#SOCKETS[@]} -gt 0 ]; then   # -s is about shux only
    [ "$ONLY" = browser ] && die_usage "--socket selects shux daemons; it cannot go with --only browser"
    WANT_BROWSER=0
fi
if { [ "$WANT_SHUX" = 1 ] && command -v shux >/dev/null; } || { [ "$WANT_BROWSER" = 1 ] && command -v agent-browser >/dev/null; }; then
    for t in jq lsof; do command -v "$t" >/dev/null || { printf '%s%s:%s needs %s on PATH\n' "$EFA" "$PROG" "$EZ" "$t" >&2; exit 1; }; done
fi

# ------------------------------------------------------------------ output ---
[ "$JSON" = 1 ] && { HD=; FL=; AR=; MU=; OK=; WN=; FA=; KP=; B=; Z=; EFA=; EZ=; }
# ev LEVEL EVENT MESSAGE [key=value ...] — text for people, one JSON object per line with --json
ev() {
    local lvl=$1 event=$2 msg=$3; shift 3
    if [ "$JSON" = 1 ]; then
        msg=${msg#"${msg%%[! ]*}"}
        local args=(--arg ts "$(date -u +%FT%TZ)" --arg level "$lvl" --arg event "$event" --arg msg "$msg") kv f="{ts:\$ts,level:\$level,event:\$event,msg:\$msg"
        local i=0
        for kv in "$@"; do
            # pids and counts are numbers; everything else (session names included) stays a string
            case "${kv%%=*}:${kv#*=}" in
                pid:[0-9]* | errors:[0-9]* | shux_*:[0-9]* | browser_sessions:[0-9]* | orphans:[0-9]* | orca_*:[0-9]*) args+=(--argjson "k$i" "${kv#*=}") ;;
                *) args+=(--arg "k$i" "${kv#*=}") ;;
            esac
            f+=",\"${kv%%=*}\":\$k$i"; i=$((i + 1))
        done
        jq -ncM "${args[@]}" "$f}"
        return
    fi
    local tag
    case "$lvl" in
        ok) tag="$OK  ok  $Z" ;; warn) tag="$WN warn $Z" ;; error) tag="$FA fail $Z" ;;
        plan) tag="$OK  go  $Z" ;; keep) tag="$KP stay $Z" ;; *) tag="$MU  ··  $Z" ;;
    esac
    printf '%s %s\n' "$tag" "$msg"
}
section() { [ "$JSON" = 1 ] || printf '\n%s%s%s\n' "$HD" "$1" "$Z"; }

# ------------------------------------------------------------------- lock ---
LOCK=${TMPDIR:-/tmp}; LOCK=${LOCK%/}/visarjana.lock
take_lock() {
    if mkdir "$LOCK" 2>/dev/null; then echo $$ >"$LOCK/pid"; return 0; fi
    local other; other=$(cat "$LOCK/pid" 2>/dev/null || true)
    if [ -n "$other" ] && kill -0 "$other" 2>/dev/null; then
        ev error lock "another $PROG run (pid $other) is in progress" pid="$other"; exit 1
    fi
    rm -rf "$LOCK" && mkdir "$LOCK" 2>/dev/null && echo $$ >"$LOCK/pid" && return 0
    ev error lock "cannot take the lock $LOCK" path="$LOCK"; exit 1
}
take_lock
trap 'rm -rf "$LOCK"' EXIT
trap 'ev warn interrupted "interrupted; anything not yet dismissed is still running"; exit 130' INT TERM

# ---------------------------------------------------------------- helpers ---
is_kept() { local k; for k in ${KEEP[@]+"${KEEP[@]}"}; do [ "$k" = "$1" ] && return 0; done; return 1; }
KEPT_HIT=()
note_kept() { KEPT_HIT+=("$1"); }
args_of() { ps -o args= -p "$1" 2>/dev/null; }
alive() { kill -0 "$1" 2>/dev/null; }
# still PID ARGS [ORPHAN]: the pid is alive with exactly the command line the ledger saw (so it was not reused by
# another daemon or browser), and with ORPHAN still parented to pid 1.
still() {
    local a; a=$(args_of "$1") || return 1
    [ "${a%"${a##*[! ]}"}" = "$2" ] || return 1
    [ -z "${3:-}" ] || [ "$(ps -o ppid= -p "$1" 2>/dev/null | tr -d ' ')" = 1 ]
}
# stop PID ARGS WHAT [ORPHAN]: SIGTERM, wait the grace period, SIGKILL only with --force. 0 when it is gone.
stop() {
    local pid=$1 needle=$2 what=$3 orphan=${4:-} waited=0
    if ! still "$pid" "$needle" "$orphan"; then ev ok gone "$what already gone" pid="$pid"; return 0; fi
    kill -TERM "$pid" 2>/dev/null
    while alive "$pid" && [ "$waited" -lt $((GRACE * 4)) ]; do sleep 0.25; waited=$((waited + 1)); done
    if alive "$pid" && [ "$FORCE" = 1 ] && still "$pid" "$needle" "$orphan"; then
        kill -KILL "$pid" 2>/dev/null; sleep 0.5
    fi
    if alive "$pid"; then
        ev error survived "$what (pid $pid) outlived SIGTERM after ${GRACE}s$([ "$FORCE" = 1 ] || echo '; rerun with --force')" pid="$pid"
        return 1
    fi
    ev ok stopped "$what stopped" pid="$pid"
}
# The shux daemon this process runs under, if any: walking up the parents.
host_daemon() {
    local p=$$ a
    while [ -n "$p" ] && [ "$p" -gt 1 ]; do
        a=$(args_of "$p") || return 1
        case "$a" in *"shux __daemon"*) echo "$p"; return 0 ;; esac
        p=$(ps -o ppid= -p "$p" 2>/dev/null | tr -d ' ')
    done
    return 1
}
# canon PATH: the path with its directory resolved, so /tmp/x and /private/tmp/x compare equal
canon() { local d; d=$(cd "$(dirname "$1")" 2>/dev/null && pwd -P) || { echo "$1"; return; }; echo "$d/$(basename "$1")"; }
# lsof_socks PID: the unix socket paths the process holds, attach side-channels left out
lsof_socks() { lsof -nP -a -p "$1" -U -Fn 2>/dev/null | sed -n 's/^n//p' | grep -v '/attach\.sock$' | sort -u; }
# sock_conns PID SOCK: connections the daemon has accepted on SOCK and its attach side-channel. lsof names each
# accepted connection after the socket it came in on, so every sighting past the listener's is a client. Fails
# when lsof does or does not show the listener: a count it could not read is never zero.
sock_conns() {
    local out; out=$(lsof -nP -a -p "$1" -U -Fn 2>/dev/null) || return 1
    sed -n 's/^n//p' <<<"$out" | awk -v s="$2" '
        $0 == s || /\/attach\.sock$/ {c[$0]++}
        END {if (!c[s]) exit 1; n = 0; for (k in c) n += c[k] - 1; print n}'
}
# daemon_socket PID ARGS: the socket the daemon serves, read from the process itself — never guessed from the
# default path or SHUX_SOCKET. Fails when it cannot be told, and the daemon is then left alone.
daemon_socket() {
    local pid=$1 want="" s cands=()
    case "$2" in *"--socket "*) want=${2#*--socket } ;; esac
    while IFS= read -r s; do [ -S "$s" ] && cands+=("$s"); done < <(lsof_socks "$pid")
    for s in ${cands[@]+"${cands[@]}"}; do [ "$s" = "$want" ] && { echo "$s"; return 0; }; done
    [ ${#cands[@]} = 1 ] && { echo "${cands[0]}"; return 0; }
    return 1
}
# owns PID SOCK: the socket file is there and this daemon still holds it. Checked before every call: a shux
# client pointed at a socket no daemon serves starts a new daemon there.
owns() { [ -S "$2" ] && lsof_socks "$1" | grep -qxF -- "$2"; }
# same_build SOCK: the daemon is this shux CLI's own build. Asked with `shux version`, the one call that never
# replaces a daemon: every other one SIGTERMs a daemon of another build and starts a fresh one, losing its sessions.
same_build() {
    local v; v=$(shux --socket "$1" --format json version 2>/dev/null) || return 1
    jq -e '.mismatch == false and .daemon.status == "running"' <<<"$v" >/dev/null 2>&1
}
sx() {
    local s=$1; shift
    if ! same_build "$s"; then echo "it is not this shux build, so any shux call would restart it" >&2; return 1; fi
    shux --socket "$s" "$@"
}
# sessions SOCK → id \t name \t scratch \t created_at; scratch sessions (a running `lens run`) included
sessions() {
    # Keep stderr outside the rows; validate the whole response before emitting any of them.
    sx "$1" session list --format json --include-scratch | jq -sr '
        def field: type == "string" and length > 0 and (test("[\u0000-\u001f\u007f]") | not);
        if length == 1 and (.[0] | type == "object" and (.sessions | type == "array") and
            all(.sessions[]; type == "object" and (.id | field) and (.name | field) and
                (.scratch | type == "boolean") and
                (.created_at | type == "number" and . >= 0 and . <= 9007199254740991 and floor == .)))
        then .[0].sessions[] | [.id, .name, (.scratch|tostring), (.created_at|floor|tostring)] | @tsv
        else error("invalid shux session list") end
    '
}
dur() {
    local s=$1
    if [ "$s" -lt 120 ]; then echo "${s}s"; elif [ "$s" -lt 7200 ]; then echo "$((s / 60))m"
    elif [ "$s" -lt 172800 ]; then echo "$((s / 3600))h"; else echo "$((s / 86400))d"; fi
}
# keep_hit NAME ID: a --keep names this session by name, full id, or the 8-character short id
keep_hit() {
    local k matched=1
    for k in ${KEEP[@]+"${KEEP[@]}"}; do
        if [ "$k" = "$1" ] || [ "$k" = "$2" ] || [ "$k" = "${2:0:8}" ]; then note_kept "$k"; matched=0; fi
    done
    return "$matched"
}

# proc_env PID VAR: VAR as the process's own environment has it; empty when it cannot be read. From ps the
# environment follows the arguments, so the last match is the environment's.
proc_env() {
    if [ -r "/proc/$1/environ" ]; then tr '\0' '\n' <"/proc/$1/environ" 2>/dev/null | sed -n "s/^$2=//p" | head -1
    else ps eww -o command= -p "$1" 2>/dev/null | tr ' ' '\n' | sed -n "s/^$2=//p" | tail -1; fi
}
# client_socket PID ARGS: the socket a shux client talks to, resolved as the shux CLI resolves it: --socket,
# then SHUX_SOCKET, then $XDG_RUNTIME_DIR/shux/shux.sock, then $TMPDIR/shux-$UID/shux.sock. Empty for a
# relative path (it is relative to the client's cwd), which then matches no daemon.
client_socket() {
    local s=""
    case "$2" in
        *" --socket="*) s=${2#* --socket=}; s=${s%% *} ;;
        *" --socket "*) s=${2#* --socket }; s=${s%% *} ;;
    esac
    [ -n "$s" ] || s=$(proc_env "$1" SHUX_SOCKET)
    if [ -z "$s" ]; then
        s=$(proc_env "$1" XDG_RUNTIME_DIR)
        if [ -n "$s" ]; then s="${s%/}/shux/shux.sock"
        else s=$(proc_env "$1" TMPDIR); s="${s:-/tmp}"; s="${s%/}/shux-$(id -u)/shux.sock"; fi
    fi
    case "$s" in /*) echo "$s" ;; esac
}
# orca_cli: Orca's CLI, chosen as Orca documents it. On Linux a bare `orca` outside Orca's own terminals is the
# GNOME screen reader, so there only orca-ide (or ORCA_CLI_COMMAND) is used.
orca_cli() {
    if [ -n "${ORCA_CLI_COMMAND:-}" ]; then command -v "$ORCA_CLI_COMMAND"
    elif [ "$(uname -s)" = Darwin ]; then command -v orca
    else command -v orca-ide; fi
}
# orca_live ORCA: handle \t agent \t title for every live Orca terminal. No field is ever empty ("-"): read
# collapses consecutive tabs, and an empty agent would shift the title into its place.
orca_live() {
    "$1" terminal list --json 2>/dev/null \
        | jq -r 'if (.result.terminals | type) == "array" then .result.terminals[] | [.handle, ((.agentIdentity // "") | if . == "" then "-" else . end), ((.title // "") | if . == "" then "-" else . end)] | @tsv else error("invalid Orca terminal list") end'
}
browser_names() {
    jq -r 'if (.data.sessions | type) == "array" and all(.data.sessions[]; type == "string" and length > 0 and (test("[\r\n]") | not)) then .data.sessions[] else error("invalid browser session list") end'
}

# --------------------------------------------------------------- classify ---
ORPHAN_AGE=600   # an empty daemon younger than this may be about to get its first session
SHELLS=" bash zsh sh fish dash ksh tcsh csh "
PS=""; CLIENTS=""; NOW=0
# shux client processes: a bare `shux` attaches, so only the daemon itself is left out
shux_clients() { ps -axo pid=,args= | awk '$2 ~ /(^|\/)shux$/ && $3 != "__daemon" {sub(/^ +/, ""); print}'; }
# snapshot: one view of the process table, and of which daemon socket each shux client talks to
# (canonical socket \t pid \t args), for probe to read.
snapshot() {
    local cpid cargs s
    NOW=$(date +%s)
    PS=$(ps -axo pid=,ppid=,tpgid=,stat=,etime=,tty=,args=) || return 1
    CLIENTS=$(shux_clients | while read -r cpid cargs; do
        s=$(client_socket "$cpid" "$cargs") || continue
        [ -z "$s" ] || printf '%s\t%s\t%s\n' "$(canon "$s")" "$cpid" "$cargs"
    done)
}
# up PID: seconds since the process started, from ps's [[dd-]hh:]mm:ss
up() {
    awk -v p="$1" '$1 == p {
        e = $5; d = 0; if (i = index(e, "-")) { d = substr(e, 1, i - 1); e = substr(e, i + 1) }
        n = split(e, a, ":"); s = 0; for (j = 1; j <= n; j++) s = s * 60 + a[j]; print d * 86400 + s; exit }' <<<"$PS"
}
# panes_of PID: busy \t tty \t command for each process the daemon runs (one per live pane). Idle means a shell
# at a prompt, as far as the process table can say: an interactive shell (no -c, no script) that holds its
# terminal's foreground, sleeps, and has no child. Anything else is running something.
panes_of() {
    awk -v d="$1" -v shells="$SHELLS" '
        { pid[NR] = $1; pp[NR] = $2; tp[NR] = $3; st[NR] = $4; tty[NR] = $6; cmd[NR] = $7; kids[$2]++
          bare[NR] = 1; for (j = 8; j <= NF; j++) if ($j !~ /^-(-login|-interactive|[il]+)$/) bare[NR] = 0 }
        END { for (i = 1; i <= NR; i++) if (pp[i] == d && st[i] !~ /^Z/) {   # a zombie is a pane already gone
            c = cmd[i]; sub(/^.*\//, "", c); sub(/^-/, "", c)
            busy = (index(shells, " " c " ") == 0 || !bare[i] || st[i] !~ /^S/ || tp[i] != pid[i] || kids[pid[i]] > 0)
            printf "%d\t%s\t%s\n", busy, tty[i], c } }' <<<"$PS"
}
# mtime FILE: last-modified time in epoch seconds (a terminal's is its last output); fails unless it is one number
if stat --version >/dev/null 2>&1; then STAT=(stat -c %Y); else STAT=(stat -f %m); fi   # GNU, or BSD/macOS
mtime() {
    local m; m=$("${STAT[@]}" "$1" 2>/dev/null) || return 1
    case "$m" in '' | *[!0-9]*) return 1 ;; esac
    echo "$m"
}
# probe PID SOCK LIST: classify one daemon from the latest snapshot. Sets CAT (orphan, idle, in-use, or unknown
# when the evidence cannot be read) and WHY.
probe() {
    local pid=$1 sock=$2 list=$3 n=0 born=0 age conns csock cpid cargs b tt c m busy="" ttys=0 seen=0 heard=0 quiet
    local why=() clients=0
    while IFS=$'\t' read -r _ _ _ c; do [ -n "$c" ] || continue; n=$((n + 1)); [ "$c" -gt "$born" ] && born=$c; done <<<"$list"
    if ! age=$(up "$pid") || [ -z "$age" ]; then CAT=unknown; WHY="cannot read its age"; return; fi
    if ! conns=$(sock_conns "$pid" "$sock"); then CAT=unknown; WHY="cannot read its client connections"; return; fi
    [ "$pid" = "$HOST" ] && why+=("runs this $PROG")
    while IFS=$'\t' read -r csock cpid cargs; do
        [ "$csock" = "$(canon "$sock")" ] || continue
        clients=$((clients + 1)); why+=("client pid $cpid: $cargs")
    done <<<"$CLIENTS"
    while IFS=$'\t' read -r b tt c; do
        [ -n "$b" ] || continue
        ttys=$((ttys + 1))
        [ "$b" = 1 ] && busy+="${busy:+, }$c"
        if [ "$tt" != "??" ] && [ "$tt" != "?" ] && m=$(mtime "/dev/$tt"); then
            seen=$((seen + 1)); [ "$m" -gt "$heard" ] && heard=$m
        fi
    done < <(panes_of "$pid")
    # A busy pane is reason enough to stay; an idle one whose last write cannot be read says nothing.
    if [ -z "$busy" ] && [ "$seen" -lt "$ttys" ]; then CAT=unknown; WHY="cannot tell when its panes last wrote"; return; fi

    [ "$clients" = 0 ] && [ "$conns" -gt 0 ] && why+=("$conns client connection(s)")
    [ -n "$busy" ] && why+=("running: $busy")
    if [ "$n" = 0 ]; then
        [ "$ttys" -gt 0 ] && why+=("runs $ttys process(es) but lists no session")
        [ "$age" -lt "$ORPHAN_AGE" ] && why+=("started $(dur "$age") ago")
        if [ ${#why[@]} = 0 ]; then CAT=orphan; WHY="no sessions, no clients, up $(dur "$age")"; return; fi
    else
        # Quiet since its panes last wrote; with no live pane, since its newest session was made.
        [ "$ttys" -gt 0 ] || heard=$born
        quiet=$((NOW - heard)); [ "$quiet" -ge 0 ] || quiet=0   # a pane may write after the clock was read
        [ "$quiet" -lt "$IDLE_AFTER" ] && why+=("active $(dur "$quiet") ago")
        if [ ${#why[@]} = 0 ]; then
            CAT=idle
            WHY="$n session(s), $([ "$ttys" -gt 0 ] && echo "$ttys shell(s) at a prompt" || echo 'no live panes'), quiet $(dur "$quiet"), no clients"
            return
        fi
    fi
    CAT=in-use; WHY=$(printf '%s; ' "${why[@]}"); WHY=${WHY%; }
}
# chosen CAT: this run dismisses a daemon of this kind
# --in-use, which only ever names daemons with -s, takes them whatever kind they are short of unknown.
chosen() { case "$1" in orphan) true ;; idle) [ "$IDLE" = 1 ] || [ "$IN_USE" = 1 ] ;; in-use) [ "$IN_USE" = 1 ] ;; *) false ;; esac; }
label() {
    case "$1" in
        orphan) echo "${OK}orphan${Z} " ;; idle) echo "${WN}idle${Z}   " ;; in-use) echo "${KP}in use${Z} " ;; *) echo "${FA}unknown${Z}" ;;
    esac
}

# ----------------------------------------------------------------- ledger ---
# Rows are tab-separated so names with spaces survive.
D_ROWS=()   # daemon to dismiss: pid \t socket \t args \t session ids (space-separated)
O_ROWS=()   # orphan chrome: pid \t age \t args
T_ROWS=()   # orca terminal: handle \t attach pid \t attach args \t daemon socket \t title
D_STOPPED=()   # sockets of daemons this run successfully stopped
T_CLOSED=()    # handles actually closed; spared terminals are not verification failures
MATCHED_SOCKS=()
N_ORPHAN=0; N_IDLE=0; N_INUSE=0; N_UNKNOWN=0; N_KEPT=0; N_SESS=0; N_BROWSER=0
ERRORS=0
HOST=$(host_daemon || true)

if [ "$WANT_SHUX" = 1 ]; then
    section "shux"
    if ! command -v shux >/dev/null; then
        [ ${#SOCKETS[@]} = 0 ] || die_usage "--socket needs shux on PATH"
        ev info absent "shux is not installed; nothing to do"
    else
        snapshot || { ev error ps "cannot read the process table"; exit 1; }
        found=0
        while IFS= read -r line; do
            [ -n "$line" ] || continue
            pid=${line%% *}; dargs=${line#* }
            if ! sock=$(daemon_socket "$pid" "$dargs"); then
                # Unreachable: its socket file is gone, or it holds several. Say so unless -s scoped it out.
                mention=1
                if [ ${#SOCKETS[@]} -gt 0 ]; then
                    mention=0; for s in "${SOCKETS[@]}"; do case "$dargs" in *"$s"*) mention=1 ;; esac; done
                fi
                if [ "$mention" = 1 ]; then
                    ev error socket "${FA}unknown${Z}  daemon ${AR}$pid${Z} (${MU}$dargs${Z}): cannot tell which socket it serves (its socket file may be gone); left alone — if it is truly stale: kill $pid" pid="$pid" category=unknown
                    N_UNKNOWN=$((N_UNKNOWN + 1)); ERRORS=$((ERRORS + 1)); found=$((found + 1))
                fi
                continue
            fi
            if [ ${#SOCKETS[@]} -gt 0 ]; then
                match=0; for s in "${SOCKETS[@]}"; do [ "$(canon "$s")" = "$(canon "$sock")" ] && match=1; done
                [ "$match" = 1 ] || continue
            fi
            MATCHED_SOCKS+=("$(canon "$sock")")
            found=$((found + 1))
            if ! same_build "$sock"; then
                N_UNKNOWN=$((N_UNKNOWN + 1)); ERRORS=$((ERRORS + 1))
                ev error build "${FA}unknown${Z}  daemon ${AR}$pid${Z}  ${MU}$sock${Z}  — not this shux build (see: shux --socket $sock version); any other shux call would restart it and lose its sessions, so it is left alone" pid="$pid" socket="$sock" category=unknown
                continue
            fi
            if ! list=$(sessions "$sock"); then
                ev error list "${FA}unknown${Z}  daemon ${AR}$pid${Z} (${MU}$sock${Z}): cannot list its sessions; left alone" pid="$pid" socket="$sock" category=unknown
                N_UNKNOWN=$((N_UNKNOWN + 1)); ERRORS=$((ERRORS + 1)); continue
            fi
            probe "$pid" "$sock" "$list"
            kept=0; ids=""
            while IFS=$'\t' read -r id name _; do
                [ -n "$id" ] || continue
                keep_hit "$name" "$id" && kept=1
                ids+="${ids:+ }$id"
            done <<<"$list"
            case "$CAT" in
                orphan) N_ORPHAN=$((N_ORPHAN + 1)) ;; idle) N_IDLE=$((N_IDLE + 1)) ;; in-use) N_INUSE=$((N_INUSE + 1)) ;;
                *) N_UNKNOWN=$((N_UNKNOWN + 1)); ERRORS=$((ERRORS + 1)) ;;
            esac
            lvl=keep; note=$WHY
            if [ "$kept" = 1 ]; then note="$WHY; kept by --keep"; N_KEPT=$((N_KEPT + 1))
            elif [ "$pid" != "$HOST" ] && chosen "$CAT"; then
                lvl=plan; D_ROWS+=("$pid"$'\t'"$sock"$'\t'"$dargs"$'\t'"$ids")
            fi
            ev "$lvl" daemon "$(label "$CAT") daemon ${AR}$pid${Z}  ${MU}$sock${Z}  — $note" pid="$pid" socket="$sock" category="$CAT" reason="$note"
            while IFS=$'\t' read -r id name scratch created; do
                [ -n "$id" ] || continue
                [ "$lvl" = plan ] && N_SESS=$((N_SESS + 1))
                kind=session; [ "$scratch" = true ] && kind="scratch (a lens run)"
                ev "$lvl" session "          $kind  ${B}$name${Z}  ${MU}(${id:0:8}, created $(dur $((NOW - created))) ago)${Z}" session="$name" id="$id" scratch="$scratch" socket="$sock"
            done <<<"$list"
        # ps, not pgrep: macOS pgrep leaves out its own ancestors, so from inside a pane it cannot see that pane's daemon.
        done < <(ps -axo pid=,args= | awk '$2 ~ /(^|\/)shux$/ && $3 == "__daemon" {sub(/^ +/, ""); print}')
        if [ "$found" = 0 ]; then
            if [ ${#SOCKETS[@]} -gt 0 ]; then
                running=$(ps -axo pid=,args= | awk '$2 ~ /(^|\/)shux$/ && $3 == "__daemon" {print $1}' \
                    | while IFS= read -r p; do daemon_socket "$p" "$(args_of "$p")"; done | paste -sd" " -)
                ev error absent "no running shux daemon on: ${SOCKETS[*]} (running: ${running:-none})" sockets="${SOCKETS[*]}"; exit 2
            fi
            ev info absent "no shux daemons running"
        fi
    fi
fi

for s in ${SOCKETS[@]+"${SOCKETS[@]}"}; do
    match=0
    for seen in ${MATCHED_SOCKS[@]+"${MATCHED_SOCKS[@]}"}; do [ "$(canon "$s")" = "$seen" ] && match=1; done
    [ "$match" = 1 ] || die_usage "no running shux daemon on: $s"
done

ORCA=""
# Only --in-use can stop a daemon that has an attach client, so only it can leave an Orca terminal to close.
if [ "$IN_USE" = 1 ] && [ "$WANT_ORCA" = 1 ] && [ ${#D_ROWS[@]} -gt 0 ] && ORCA=$(orca_cli) && [ -n "$ORCA" ]; then
    section "orca"
    if ! live=$(orca_live "$ORCA") || [ -z "$live" ]; then
        ev warn list "cannot list Orca terminals (is Orca running?); none touched"; ORCA=""
    else
        while read -r cpid cargs; do
            handle=$(proc_env "$cpid" ORCA_TERMINAL_HANDLE)
            [ -n "$handle" ] || continue
            [ "$handle" = "${ORCA_TERMINAL_HANDLE:-}" ] && continue   # the terminal running this
            csock=$(client_socket "$cpid" "$cargs"); [ -n "$csock" ] || continue
            csock=$(canon "$csock"); dsock=""
            for row in "${D_ROWS[@]}"; do
                IFS=$'\t' read -r _ ds _ <<<"$row"; [ "$(canon "$ds")" = "$csock" ] && dsock=$ds
            done
            [ -n "$dsock" ] || continue
            entry=$(awk -F'\t' -v h="$handle" '$1 == h' <<<"$live")
            [ -n "$entry" ] || continue   # not a live Orca terminal
            IFS=$'\t' read -r _ agent title <<<"$entry"
            if [ "$agent" != - ]; then
                ev warn spared "terminal ${AR}$handle${Z} ${MU}($title)${Z} runs $agent; left open" handle="$handle"; continue
            fi
            T_ROWS+=("$handle"$'\t'"$cpid"$'\t'"$cargs"$'\t'"$dsock"$'\t'"$title")
            ev plan terminal "terminal ${AR}$handle${Z} ${MU}($title)${Z} follows ${MU}$dsock${Z}" handle="$handle" pid="$cpid" socket="$dsock"
        # An attach client: `shux ... session attach`, or a bare `shux` (which attaches).
        done < <(ps -axo pid=,args= | awk '$2 ~ /(^|\/)shux$/ && (($3 == "session" && $4 == "attach") || / session attach / || NF == 2) {sub(/^ +/, ""); print}')
        [ ${#T_ROWS[@]} = 0 ] && ev info none "no Orca terminal follows these daemons"
    fi
fi

if [ "$WANT_BROWSER" = 1 ]; then
    section "agent-browser"
    if ! command -v agent-browser >/dev/null; then
        ev info absent "agent-browser is not installed; looking only for orphaned Chromes"
    elif ! list=$(agent-browser session list --json 2>&1) || ! names=$(browser_names <<<"$list" 2>/dev/null); then
        ev error list "cannot list agent-browser sessions: $list"; ERRORS=$((ERRORS + 1))
    else
        while IFS= read -r name; do
            [ -n "$name" ] || continue
            is_kept "$name" && note_kept "$name"
            N_BROWSER=$((N_BROWSER + 1))
            ev keep session "${KP}open${Z}    session  ${B}$name${Z}  ${MU}— never closed here; if it is yours: agent-browser --session '$name' close${Z}" session="$name" category=in-use
        done <<<"$names"
    fi
    root="$HOME/.agent-browser/browsers/"
    while read -r pid ppid etime args; do
        # The browser's main executable only: its helpers carry --type=, and its crashpad handlers are always
        # parented to pid 1, live browser or not, and exit with the browser.
        case "$args" in "$root"*"/Contents/MacOS/Google Chrome for Testing" | "$root"*"/Contents/MacOS/Google Chrome for Testing "*) ;; *) continue ;; esac
        case "$args" in *--type=*) continue ;; esac
        case " $args " in *" --headless "* | *" --headless="*) ;; *) continue ;; esac
        [ "$ppid" = 1 ] || continue
        O_ROWS+=("$pid"$'\t'"$etime"$'\t'"$args")
        ev plan orphan "${OK}orphan${Z}  Chrome  ${AR}$pid${Z}  ${MU}(up $etime, its agent-browser daemon is gone)${Z}" pid="$pid" age="$etime" category=orphan
    done < <(ps -axo pid=,ppid=,etime=,args=)
    [ "$N_BROWSER" = 0 ] && [ ${#O_ROWS[@]} = 0 ] && ev info none "no agent-browser sessions or orphaned Chromes"
fi

# A --keep that matches nothing is most likely a typo for a session that would then be dismissed: refuse to act.
unmatched=0
for k in ${KEEP[@]+"${KEEP[@]}"}; do
    hit=0; for h in ${KEPT_HIT[@]+"${KEPT_HIT[@]}"}; do [ "$h" = "$k" ] && hit=1; done
    [ "$hit" = 1 ] && continue
    ev warn keep-unmatched "--keep '$k' matches no session (a typo?)" name="$k"; unmatched=1
done
if [ "$unmatched" = 1 ]; then
    ev error keep-unmatched "refusing to act while a --keep matches nothing; fix or drop it. Nothing touched"; exit 2
fi

section "Plan"
total=$(( ${#D_ROWS[@]} + ${#T_ROWS[@]} + ${#O_ROWS[@]} ))
ev info plan "dismiss ${B}${#D_ROWS[@]}${Z} shux daemon(s) with ${B}${N_SESS}${Z} session(s), ${B}${#T_ROWS[@]}${Z} Orca terminal(s), ${B}${#O_ROWS[@]}${Z} orphaned Chrome(s). Seen: $N_ORPHAN orphan, $N_IDLE idle, $N_INUSE in use, $N_UNKNOWN unknown, $N_KEPT kept, $N_BROWSER browser session(s)" \
    shux_daemons="${#D_ROWS[@]}" shux_sessions="$N_SESS" orca_terminals="${#T_ROWS[@]}" orphans="${#O_ROWS[@]}" \
    shux_orphan="$N_ORPHAN" shux_idle="$N_IDLE" shux_in_use="$N_INUSE" shux_unknown="$N_UNKNOWN" shux_kept="$N_KEPT" browser_sessions="$N_BROWSER"
[ "$N_IDLE" -gt 0 ] && [ "$IDLE" = 0 ] && [ "$IN_USE" = 0 ] && ev info hint "idle daemons stay; add ${FL}--idle${Z} to dismiss them too"
[ "$N_INUSE" -gt 0 ] && [ "$IN_USE" = 0 ] && ev info hint "in-use daemons are never swept; to tear down one you own: ${FL}$PROG -s SOCKET --in-use${Z}"
if [ "$total" = 0 ]; then
    ev ok nothing "nothing to dismiss"
    [ "$ERRORS" = 0 ] || exit 1
    exit 0
fi
if [ "$DRY" = 1 ]; then ev info dry-run "dry run: nothing touched"; [ "$ERRORS" = 0 ] || exit 1; exit 0; fi
if [ "$YES" != 1 ]; then
    if [ ! -t 0 ]; then
        printf '%s%s:%s no terminal to confirm on; rerun with -y to act or -n to only look\n' "$EFA" "$PROG" "$EZ" >&2; exit 2
    fi
    printf '\n%s%sDismiss what is marked go?%s %s[y/N]%s ' "$B" "$WN" "$Z" "$MU" "$Z"
    read -r answer || answer=
    case "$answer" in y | Y | yes | YES) ;; *) ev warn declined "nothing touched"; exit 1 ;; esac
fi

# -------------------------------------------------------------------- act ---
section "Dismissing"
# qualifies PID SOCK ARGS IDS: look again, just before touching it. Succeeds only while the daemon is the same
# process, still serves SOCK, holds no session the ledger did not see, and is still a kind this run dismisses;
# says why otherwise. Sets LEFT to its sessions. Returns 2 when it is already gone.
qualifies() {
    local pid=$1 sock=$2 dargs=$3 ids=$4 id name newcomers=""
    if ! still "$pid" "$dargs"; then ev ok gone "daemon ${AR}$pid${Z} already gone" pid="$pid"; return 2; fi
    if ! owns "$pid" "$sock"; then
        ev error socket "daemon ${AR}$pid${Z} no longer serves ${MU}$sock${Z}; left alone" pid="$pid"; ERRORS=$((ERRORS + 1)); return 1
    fi
    if ! LEFT=$(sessions "$sock") || ! snapshot; then
        ev error list "daemon ${AR}$pid${Z}: cannot look at it again, so it is left running" pid="$pid"; ERRORS=$((ERRORS + 1)); return 1
    fi
    while IFS=$'\t' read -r id name _; do
        [ -n "$id" ] || continue
        case " $ids " in *" $id "*) ;; *) newcomers+="${newcomers:+ }$name" ;; esac
    done <<<"$LEFT"
    if [ -n "$newcomers" ]; then
        ev warn spared "daemon ${AR}$pid${Z} gained sessions after the ledger ($newcomers); spared" pid="$pid"; ERRORS=$((ERRORS + 1)); return 1
    fi
    probe "$pid" "$sock" "$LEFT"
    if ! chosen "$CAT"; then
        ev warn spared "daemon ${AR}$pid${Z} is now $CAT ($WHY); spared" pid="$pid" category="$CAT"; ERRORS=$((ERRORS + 1)); return 1
    fi
}
for row in ${D_ROWS[@]+"${D_ROWS[@]}"}; do
    IFS=$'\t' read -r pid sock dargs ids <<<"$row"
    qualifies "$pid" "$sock" "$dargs" "$ids" || continue
    failed=0
    while IFS=$'\t' read -r id name _; do
        [ -n "$id" ] || continue
        # Each kill gets its own look: someone may have attached while the previous one ran.
        qualifies "$pid" "$sock" "$dargs" "$ids" || { failed=1; break; }
        # by id, never by name: a name can start with "-" or match another session's id prefix
        if out=$(sx "$sock" session kill "$id" 2>&1); then
            ev ok killed "shux session ${B}$name${Z} killed" session="$name" id="$id" socket="$sock"
        elif ! sessions "$sock" 2>/dev/null | cut -f1 | grep -qxF -- "$id"; then
            ev ok gone "shux session ${B}$name${Z} already gone" session="$name"
        else
            ev error kill "shux session ${B}$name${Z}: $out" session="$name"; ERRORS=$((ERRORS + 1)); failed=1; break
        fi
    done <<<"$LEFT"
    [ "$failed" = 0 ] || continue
    # The killed sessions' shells take a moment to exit; until they have, they look like work.
    waited=0
    while snapshot && [ -n "$(panes_of "$pid")" ] && [ "$waited" -lt $((GRACE * 4)) ]; do sleep 0.25; waited=$((waited + 1)); done
    qualifies "$pid" "$sock" "$dargs" "$ids" || continue
    if [ -n "$LEFT" ]; then
        ev error kill "daemon ${AR}$pid${Z} still lists $(cut -f2 <<<"$LEFT" | paste -sd" " -) after their kill; left running" pid="$pid"
        ERRORS=$((ERRORS + 1)); continue
    fi
    # `shux daemon stop` finds a daemon by runtime dir, not socket, and misses some; SIGTERM is what it sends.
    if stop "$pid" "$dargs" "shux daemon ${AR}$pid${Z} (${MU}$sock${Z})"; then D_STOPPED+=("$sock")
    else ERRORS=$((ERRORS + 1)); fi
done
# The ledger tied each attach to a daemon; close only after that daemon actually stopped.
for row in ${T_ROWS[@]+"${T_ROWS[@]}"}; do
    IFS=$'\t' read -r handle cpid cargs sock title <<<"$row"
    stopped=0
    for s in ${D_STOPPED[@]+"${D_STOPPED[@]}"}; do [ "$s" = "$sock" ] && stopped=1; done
    [ "$stopped" = 1 ] || continue
    if alive "$cpid" && { ! still "$cpid" "$cargs" || [ "$(proc_env "$cpid" ORCA_TERMINAL_HANDLE)" != "$handle" ]; }; then
        ev warn spared "terminal ${AR}$handle${Z}: its attach identity changed; left open" handle="$handle"; continue
    fi
    if ! live=$(orca_live "$ORCA"); then
        ev error list "cannot recheck Orca terminal $handle; left open" handle="$handle"; ERRORS=$((ERRORS + 1)); continue
    fi
    entry=$(awk -F'\t' -v h="$handle" '$1 == h' <<<"$live")
    [ -n "$entry" ] || continue
    IFS=$'\t' read -r _ agent _ <<<"$entry"
    if [ "$agent" != - ] || [ "$handle" = "${ORCA_TERMINAL_HANDLE:-}" ]; then
        ev warn spared "terminal ${AR}$handle${Z} now runs an agent or this command; left open" handle="$handle"; continue
    fi
    # One pane, never --tab: a split sharing the tab may be something else entirely.
    if out=$("$ORCA" terminal close --terminal "$handle" --json 2>&1) && jq -e '.ok == true' <<<"$out" >/dev/null 2>&1; then
        T_CLOSED+=("$handle")
        ev ok closed "Orca terminal ${AR}$handle${Z} ${MU}($title)${Z} closed" handle="$handle"
    else
        ev error close "Orca terminal ${AR}$handle${Z}: $out" handle="$handle"; ERRORS=$((ERRORS + 1))
    fi
done
for row in ${O_ROWS[@]+"${O_ROWS[@]}"}; do
    IFS=$'\t' read -r pid _ oargs <<<"$row"
    stop "$pid" "$oargs" "orphaned Chrome ${AR}$pid${Z}" orphan || ERRORS=$((ERRORS + 1))
done

# ----------------------------------------------------------------- verify ---
section "Verify"
if [ ${#T_CLOSED[@]} -gt 0 ]; then
    for handle in "${T_CLOSED[@]}"; do
        waited=0
        while true; do
            if ! live=$(orca_live "$ORCA"); then
                ev error verify "cannot verify Orca terminal $handle" handle="$handle"; ERRORS=$((ERRORS + 1)); break
            fi
            if ! cut -f1 <<<"$live" | grep -qxF -- "$handle"; then break; fi
            if [ "$waited" -ge $((GRACE * 4)) ]; then
                ev error survived "Orca terminal ${AR}$handle${Z} is still open" handle="$handle"; ERRORS=$((ERRORS + 1)); break
            fi
            sleep 0.25; waited=$((waited + 1))
        done
    done
fi
if [ "$ERRORS" = 0 ]; then
    ev ok finished "everything chosen was dismissed" errors=0
    exit 0
fi
ev error finished "$ERRORS item(s) were not dismissed; see above" errors="$ERRORS"
exit 1
