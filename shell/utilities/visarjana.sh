#!/usr/bin/env bash
# visarjana — send off what agent sessions summoned: shux sessions and daemons, the Orca terminals following
# them, agent-browser sessions, and the headless Chromes they orphan. After a pūjā, the deities invoked with āvāhana are dismissed with visarjana.
#
# Safety, in order of how much each matters:
#   - It shows a ledger first and acts only on what the ledger names. Without -y it asks; with no terminal to ask
#     on, it refuses (exit 2). Other agents on this machine may be using shux right now.
#   - A daemon that gained sessions after the ledger was taken is spared, not killed.
#   - Every pid is re-checked against its command line just before it is signalled (pids get reused).
#   - A daemon is reached only on the socket it is seen holding (lsof), re-checked before every call: a shux client
#     pointed at a socket nobody serves would start a fresh daemon there.
#   - Sessions are killed by id, never by name (a name can start with "-" or match another id's prefix).
#   - When run from inside a shux pane, that pane's daemon is spared whole: killing it would kill this run.
#   - An Orca terminal is closed only when a `shux session attach` running in it (found by the
#     ORCA_TERMINAL_HANDLE in its own environment) follows a daemon this run stops outright. Never by title or
#     screen text, never a terminal running an agent, never the one running this, never a whole tab.
#   - One run at a time (a lock in $TMPDIR).
set -uo pipefail

PROG=visarjana
VERSION=1.1.1

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
${HD}$PROG${Z} ${MU}$VERSION${Z} — dismiss shux, Orca and agent-browser leftovers, on any repo on this machine.

${HD}Usage:${Z} ${FL}$PROG${Z} ${AR}[options]${Z}

${HD}Shows what is running, asks, then dismisses it:${Z}
  ${AR}shux${Z}           every session on every running daemon (running \`lens run\` jobs included),
                 then each daemon emptied by that. A daemon whose socket it cannot confirm
                 (file deleted, say) is reported and left alone, never guessed at.
  ${AR}orca${Z}           each Orca terminal pane whose \`shux session attach\` follows a daemon
                 stopped outright above (a daemon that keeps a session keeps its terminals)
  ${AR}agent-browser${Z}  every open session (its daemon exits with it), and headless Chromes
                 orphaned by a crashed daemon (parent pid 1, under ~/.agent-browser/browsers)
It ${B}never${Z} touches the agent-browser dashboard, your own Chrome, kind clusters, git, or files,
nor an Orca terminal running an agent or this command.

${HD}Options:${Z}
  ${FL}-n, --dry-run${Z}         show the ledger and stop                       ${MU}[VISARJANA_DRY_RUN=1]${Z}
  ${FL}-y, --yes${Z}             do not ask (needed when there is no terminal)  ${MU}[VISARJANA_YES=1]${Z}
  ${FL}-k, --keep${Z} ${AR}NAME${Z}       spare a session by name, or a shux session by id or short id;
                        a NAME that matches nothing stops the run; repeatable
                                                                       ${MU}[VISARJANA_KEEP=a,b]${Z}
  ${FL}-s, --socket${Z} ${AR}PATH${Z}     only shux daemons on this socket; repeatable   ${MU}[VISARJANA_SOCKET=p1,p2]${Z}
  ${FL}-o, --only${Z} ${AR}WHAT${Z}       shux | browser (shux includes its Orca terminals)  ${MU}[VISARJANA_ONLY]${Z}
      ${FL}--no-orca${Z}         leave Orca terminals open                      ${MU}[VISARJANA_ORCA=0]${Z}
  ${FL}-g, --grace${Z} ${AR}SECONDS${Z}   seconds to wait for an exit (default 5)       ${MU}[VISARJANA_GRACE]${Z}
  ${FL}-f, --force${Z}           SIGKILL whatever outlives the grace period     ${MU}[VISARJANA_FORCE=1]${Z}
      ${FL}--json${Z}            one JSON object per line, no colour; needs jq and -y or -n
  ${FL}-h, --help${Z}            this help
  ${FL}-V, --version${Z}         print the version

${HD}Needs:${Z} jq and lsof (macOS ships lsof; brew install jq). Orca terminals need Orca's CLI:
       \$ORCA_CLI_COMMAND, else \`orca\` on macOS, else \`orca-ide\` (never a bare \`orca\` on Linux).

${HD}Exit:${Z} ${OK}0${Z} everything named was dismissed, nothing to do, or a clean --dry-run
      ${WN}1${Z} something survived, a daemon could not be reached, a command failed,
        or you answered no (a --dry-run that finds such a problem also exits 1)
      ${FA}2${Z} usage error, a --keep that matches nothing, an unknown --socket,
        or asked to act with no terminal and no -y

${HD}Examples:${Z}
  ${FL}$PROG -n${Z}                         ${MU}# what would go?${Z}
  ${FL}$PROG${Z}                            ${MU}# show, ask, dismiss${Z}
  ${FL}$PROG -y --keep my-session${Z}       ${MU}# everything but one shux session${Z}
  ${FL}$PROG -y --only browser${Z}          ${MU}# just browsers and orphaned Chromes${Z}
  ${FL}$PROG -y -s /tmp/x/shux.sock${Z}     ${MU}# only the daemon on that socket${Z}
EOF
}

# ------------------------------------------------------------------ options ---
truthy() { case "${1:-}" in 1 | true | yes | on) return 0 ;; *) return 1 ;; esac; }
die_usage() { printf '%s%s:%s %s\n' "$EFA" "$PROG" "$EZ" "$1" >&2; printf "Try '%s --help'.\n" "$PROG" >&2; exit 2; }

DRY=0; YES=0; FORCE=0; JSON=0; WANT_ORCA=1
truthy "${VISARJANA_DRY_RUN:-}" && DRY=1
truthy "${VISARJANA_YES:-}" && YES=1
truthy "${VISARJANA_FORCE:-}" && FORCE=1
case "${VISARJANA_ORCA:-}" in 0 | false | no | off) WANT_ORCA=0 ;; esac
ONLY=${VISARJANA_ONLY:-}
GRACE=${VISARJANA_GRACE:-5}
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
for k in ${KEEP[@]+"${KEEP[@]}"}; do [ -n "$k" ] || die_usage "--keep needs a non-empty name"; done
# Daemons report absolute socket paths; make a relative --socket comparable.
for i in ${SOCKETS[@]+"${!SOCKETS[@]}"}; do
    case "${SOCKETS[$i]}" in /*) ;; '') die_usage "--socket needs a path" ;; *) SOCKETS[i]="$PWD/${SOCKETS[$i]}" ;; esac
done
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
        plan) tag="$AR  ·   $Z" ;; keep) tag="$KP keep $Z" ;; *) tag="$MU  ··  $Z" ;;
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
sx() { local s=$1; shift; shux --socket "$s" "$@"; }
# sessions SOCK → id \t name \t scratch \t created_at; scratch sessions (a running `lens run`) included
sessions() { sx "$1" session list --format json --include-scratch | jq -r '.sessions[] | [.id, .name, (.scratch|tostring), (.created_at|tostring)] | @tsv'; }
ago() {
    local s=$(( $(date +%s) - $1 ))
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

# ----------------------------------------------------------------- ledger ---
# Rows are tab-separated so names with spaces survive.
D_ROWS=()   # daemon:  pid \t socket \t args
S_ROWS=()   # session: pid \t socket \t id \t name \t daemon args
A_ROWS=()   # agent-browser session names
O_ROWS=()   # orphan chrome: pid \t age \t args
T_ROWS=()   # orca terminal: handle \t attach pid \t attach args \t daemon socket \t title
D_STOPPED=()   # sockets of daemons this run successfully stopped
T_CLOSED=()    # handles actually closed; spared terminals are not verification failures
MATCHED_SOCKS=()
KEPT_SOCKS=()   # sockets of daemons that stay for a kept session
ERRORS=0
HOST=$(host_daemon || true)

if [ "$WANT_SHUX" = 1 ]; then
    section "shux"
    if ! command -v shux >/dev/null; then
        [ ${#SOCKETS[@]} = 0 ] || die_usage "--socket needs shux on PATH"
        ev info absent "shux is not installed; nothing to do"
    else
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
                    ev error socket "daemon ${AR}$pid${Z} (${MU}$dargs${Z}): cannot tell which socket it serves (its socket file may be gone); left alone — if it is truly stale: kill $pid" pid="$pid"
                    ERRORS=$((ERRORS + 1)); found=$((found + 1))
                fi
                continue
            fi
            if [ ${#SOCKETS[@]} -gt 0 ]; then
                match=0; for s in "${SOCKETS[@]}"; do [ "$(canon "$s")" = "$(canon "$sock")" ] && match=1; done
                [ "$match" = 1 ] || continue
            fi
            MATCHED_SOCKS+=("$(canon "$sock")")
            found=$((found + 1))
            if ! list=$(sessions "$sock" 2>&1); then
                ev error list "cannot list sessions on daemon $pid ($sock): $list" pid="$pid" socket="$sock"
                ERRORS=$((ERRORS + 1)); continue
            fi
            if [ "$pid" = "$HOST" ]; then
                while IFS=$'\t' read -r id name _; do [ -n "$id" ] && keep_hit "$name" "$id"; done <<<"$list"
                ev warn spared "daemon ${AR}$pid${Z} (${MU}$sock${Z}) is the one running $PROG; spared with its sessions — run from a plain terminal to dismiss it" pid="$pid" socket="$sock"
                continue
            fi
            D_ROWS+=("$pid"$'\t'"$sock"$'\t'"$dargs")
            ev plan daemon "daemon ${AR}$pid${Z}  ${MU}${sock}${Z}" pid="$pid" socket="$sock"
            n=0
            while IFS=$'\t' read -r id name scratch created; do
                [ -n "$id" ] || continue
                n=$((n + 1))
                kind=session; [ "$scratch" = true ] && kind="scratch (a lens run)"
                if keep_hit "$name" "$id"; then
                    KEPT_SOCKS+=("$sock")
                    ev keep keep "  ${B}$name${Z}  ${MU}(${id:0:8})${Z}" session="$name" id="$id" socket="$sock"; continue
                fi
                S_ROWS+=("$pid"$'\t'"$sock"$'\t'"$id"$'\t'"$name"$'\t'"$dargs")
                ev plan session "  $kind  ${B}$name${Z}  ${MU}(${id:0:8}, created $(ago "$created") ago)${Z}" session="$name" id="$id" scratch="$scratch" socket="$sock"
            done <<<"$list"
            [ "$n" = 0 ] && ev plan session "  ${MU}no sessions; the daemon idles${Z}" pid="$pid"
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
if [ "$WANT_SHUX" = 1 ] && [ "$WANT_ORCA" = 1 ] && [ ${#D_ROWS[@]} -gt 0 ] && ORCA=$(orca_cli) && [ -n "$ORCA" ]; then
    section "orca"
    if ! live=$(orca_live "$ORCA") || [ -z "$live" ]; then
        ev warn list "cannot list Orca terminals (is Orca running?); none touched"; ORCA=""
    else
        # An attach client: `shux ... session attach`, or a bare `shux` (which attaches).
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
            kept=0; for k in ${KEPT_SOCKS[@]+"${KEPT_SOCKS[@]}"}; do [ "$(canon "$k")" = "$(canon "$dsock")" ] && kept=1; done
            if [ "$kept" = 1 ]; then
                ev keep keep "terminal ${AR}$handle${Z} ${MU}($title)${Z}: its daemon stays for a kept session" handle="$handle"; continue
            fi
            if [ "$agent" != - ]; then
                ev warn spared "terminal ${AR}$handle${Z} ${MU}($title)${Z} runs $agent; left open" handle="$handle"; continue
            fi
            T_ROWS+=("$handle"$'\t'"$cpid"$'\t'"$cargs"$'\t'"$dsock"$'\t'"$title")
            ev plan terminal "terminal ${AR}$handle${Z} ${MU}($title)${Z} follows ${MU}$dsock${Z}" handle="$handle" pid="$cpid" socket="$dsock"
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
            if is_kept "$name"; then note_kept "$name"; ev keep keep "${B}$name${Z}" session="$name"; continue; fi
            A_ROWS+=("$name")
            ev plan session "session  ${B}$name${Z}" session="$name"
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
        ev plan orphan "orphaned Chrome  ${AR}$pid${Z}  ${MU}(up $etime, no agent-browser daemon)${Z}" pid="$pid" age="$etime"
    done < <(ps -axo pid=,ppid=,etime=,args=)
    [ ${#A_ROWS[@]} = 0 ] && [ ${#O_ROWS[@]} = 0 ] && ev info none "no agent-browser sessions or orphaned Chromes"
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

total=$(( ${#D_ROWS[@]} + ${#S_ROWS[@]} + ${#T_ROWS[@]} + ${#A_ROWS[@]} + ${#O_ROWS[@]} ))
section "Plan"
if [ "$total" = 0 ]; then
    ev ok nothing "nothing to dismiss"
    [ "$ERRORS" = 0 ] || exit 1
    exit 0
fi
ev info plan "${B}${#S_ROWS[@]}${Z} shux session(s), up to ${B}${#D_ROWS[@]}${Z} shux daemon(s), ${B}${#T_ROWS[@]}${Z} Orca terminal(s), ${B}${#A_ROWS[@]}${Z} browser session(s), ${B}${#O_ROWS[@]}${Z} orphaned Chrome(s)" \
    shux_sessions="${#S_ROWS[@]}" shux_daemons="${#D_ROWS[@]}" orca_terminals="${#T_ROWS[@]}" browser_sessions="${#A_ROWS[@]}" orphans="${#O_ROWS[@]}"
if [ "$DRY" = 1 ]; then ev info dry-run "dry run: nothing touched"; [ "$ERRORS" = 0 ] || exit 1; exit 0; fi
if [ "$YES" != 1 ]; then
    if [ ! -t 0 ]; then
        printf '%s%s:%s no terminal to confirm on; rerun with -y to act or -n to only look\n' "$EFA" "$PROG" "$EZ" >&2; exit 2
    fi
    printf '\n%s%sDismiss all of the above?%s %s[y/N]%s ' "$B" "$WN" "$Z" "$MU" "$Z"
    read -r answer || answer=
    case "$answer" in y | Y | yes | YES) ;; *) ev warn declined "nothing touched"; exit 1 ;; esac
fi

# -------------------------------------------------------------------- act ---
section "Dismissing"
for row in ${S_ROWS[@]+"${S_ROWS[@]}"}; do
    IFS=$'\t' read -r pid sock id name dargs <<<"$row"
    if ! still "$pid" "$dargs"; then ev ok gone "session ${B}$name${Z}: its daemon is already gone" session="$name"; continue; fi
    if ! owns "$pid" "$sock"; then
        ev error socket "session ${B}$name${Z}: daemon ${AR}$pid${Z} no longer serves ${MU}$sock${Z}; left alone" session="$name"; ERRORS=$((ERRORS + 1)); continue
    fi
    # by id, never by name: a name can start with "-" or match another session's id prefix
    if out=$(sx "$sock" session kill "$id" 2>&1); then
        ev ok killed "shux session ${B}$name${Z} killed" session="$name" id="$id" socket="$sock"
    elif ! sessions "$sock" 2>/dev/null | cut -f1 | grep -qxF -- "$id"; then
        ev ok gone "shux session ${B}$name${Z} already gone" session="$name"
    else
        ev error kill "shux session ${B}$name${Z}: $out" session="$name"; ERRORS=$((ERRORS + 1))
    fi
done
for row in ${D_ROWS[@]+"${D_ROWS[@]}"}; do
    IFS=$'\t' read -r pid sock dargs <<<"$row"
    if ! still "$pid" "$dargs"; then ev ok gone "daemon ${AR}$pid${Z} already gone" pid="$pid"; continue; fi
    if ! owns "$pid" "$sock"; then
        ev error socket "daemon ${AR}$pid${Z} no longer serves ${MU}$sock${Z}; left alone" pid="$pid"; ERRORS=$((ERRORS + 1)); continue
    fi
    if ! left=$(sessions "$sock" 2>&1); then
        ev error list "daemon ${AR}$pid${Z}: cannot re-list sessions, so it is left running: $left" pid="$pid"; ERRORS=$((ERRORS + 1)); continue
    fi
    unknown=0
    while IFS=$'\t' read -r id name _; do [ -n "$id" ] && { keep_hit "$name" "$id" || unknown=1; }; done <<<"$left"
    left=$(cut -f2 <<<"$left" | sed '/^$/d')
    if [ -n "$left" ]; then
        if [ "$unknown" = 1 ]; then
            ev warn spared "daemon ${AR}$pid${Z} gained sessions after the ledger ($(paste -sd" " - <<<"$left")); spared" pid="$pid"
            ERRORS=$((ERRORS + 1))
        else
            ev keep keep "daemon ${AR}$pid${Z} stays for its kept session(s): $(paste -sd" " - <<<"$left")" pid="$pid"
        fi
        continue
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
for name in ${A_ROWS[@]+"${A_ROWS[@]}"}; do
    if out=$(agent-browser --session "$name" close 2>&1); then
        ev ok closed "agent-browser session ${B}$name${Z} closed" session="$name"
    else
        ev error close "agent-browser session ${B}$name${Z}: $out" session="$name"; ERRORS=$((ERRORS + 1))
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
if [ ${#A_ROWS[@]} -gt 0 ] && command -v agent-browser >/dev/null; then
    sleep 1
    if remaining=$(agent-browser session list --json 2>/dev/null | browser_names 2>/dev/null); then
        for name in "${A_ROWS[@]}"; do
            if grep -qxF -- "$name" <<<"$remaining"; then ev error survived "agent-browser session ${B}$name${Z} is still open" session="$name"; ERRORS=$((ERRORS + 1)); fi
        done
    else
        ev error verify "cannot verify agent-browser sessions"; ERRORS=$((ERRORS + 1))
    fi
fi
if [ "$ERRORS" = 0 ]; then
    ev ok finished "everything named was dismissed" errors=0
    exit 0
fi
ev error finished "$ERRORS item(s) were not dismissed; see above" errors="$ERRORS"
exit 1
