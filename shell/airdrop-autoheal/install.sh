#!/bin/bash
# ╭──────────────────────────────────────────────────────────────╮
# │  AirDrop Auto-Heal Installer                                 │
# │  Self-healing LaunchDaemon for the macOS awdl0 AirDrop flake  │
# │  Seamless · auto-elevates with sudo · verifies with doctor    │
# ╰──────────────────────────────────────────────────────────────╯
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/indrasvat/kitchen-sink/main/shell/airdrop-autoheal/install.sh | sudo bash
#   sudo bash install.sh                 # local install (from a clone)
#   bash  install.sh                     # auto re-execs itself with sudo
#   sudo bash install.sh --uninstall     # remove the daemon
#   bash  install.sh --check             # prerequisites only (no sudo)
#
# Installs (root):
#   /Library/Application Support/airdrop-autoheal/airdrop-autoheal.sh   (watcher)
#   /Library/Application Support/airdrop-autoheal/doctor.sh             (health)
#   /Library/LaunchDaemons/com.indrasvat.airdrop-autoheal.plist
#   /var/log/airdrop-autoheal.{log,err}   + newsyslog rotation
set -uo pipefail

# ── Configuration ───────────────────────────────────────────────
LABEL="com.indrasvat.airdrop-autoheal"
APPDIR="/Library/Application Support/airdrop-autoheal"
PLIST="/Library/LaunchDaemons/${LABEL}.plist"
NEWSYSLOG="/etc/newsyslog.d/airdrop-autoheal.conf"
LOGF="/var/log/airdrop-autoheal.log"
ERRF="/var/log/airdrop-autoheal.err"
REPO_SUBDIR="shell/airdrop-autoheal"
# Artifact source. Defaults to main; override to install from a branch/tag with
# NO code change (handy for testing a PR branch):
#   curl -fsSL <…>/<ref>/install.sh | sudo AIRDROP_AUTOHEAL_REF=<ref> bash
# or point at a fully custom base with AIRDROP_AUTOHEAL_RAW_BASE.
REPO_REF="${AIRDROP_AUTOHEAL_REF:-main}"
RAW_BASE="${AIRDROP_AUTOHEAL_RAW_BASE:-https://raw.githubusercontent.com/indrasvat/kitchen-sink/${REPO_REF}/${REPO_SUBDIR}}"

ACTION="install"
SRC_DIR=""
CLEANUP_DIR=""
ORIG_ARGS=("$@")

# ── Colors ──────────────────────────────────────────────────────
want_color=0
[ -t 1 ] && want_color=1
[ -n "${FORCE_COLOR:-}" ] && want_color=1
[ -n "${NO_COLOR:-}" ] && want_color=0
for a in ${ORIG_ARGS[@]+"${ORIG_ARGS[@]}"}; do [ "$a" = "--no-color" ] && want_color=0; done
if [ "$want_color" = 1 ]; then
    RST=$'\033[0m'; DIM=$'\033[2m'; BOLD=$'\033[1m'
    RED=$'\033[31m'; CYN=$'\033[36m'
    BGRN=$'\033[92m'; BCYN=$'\033[96m'; BYEL=$'\033[93m'
else
    RST=""; DIM=""; BOLD=""; RED=""; CYN=""; BGRN=""; BCYN=""; BYEL=""
fi

# ── Box-drawing (BW = inner width; content auto-padded) ─────────
BW=56
_box_rule() {
    local left="$1" right="$2" fill="" i
    for ((i = 0; i < BW; i++)); do fill="${fill}─"; done
    printf "  %s%s%s%s%s\n" "$CYN" "$left" "$fill" "$right" "$RST"
}
# Measure display width on the ANSI-stripped string (never ${#styled}).
_box_line() {
    local content="$*" plain pad spaces="" i
    plain="$(printf '%s' "$content" | sed $'s/\033\[[0-9;]*m//g')"
    pad=$((BW - 1 - ${#plain}))
    [ "$pad" -lt 0 ] && pad=0
    for ((i = 0; i < pad; i++)); do spaces="${spaces} "; done
    printf "  %s│%s %s%s%s│%s\n" "$CYN" "$RST" "$content" "$spaces" "$CYN" "$RST"
}
_info() { printf "  %s│%s  %s▸%s %s\n" "${DIM}${CYN}" "$RST" "$CYN" "$RST" "$*"; }
_done() { printf "  %s│%s  %s✔%s %s\n" "${DIM}${CYN}" "$RST" "$BGRN" "$RST" "$*"; }
_warn() { printf "  %s│%s  %s⚠  %s%s\n" "${DIM}${CYN}" "$RST" "$BYEL" "$*" "$RST"; }
_fail() { printf "  %s│%s  %s✘%s %s\n" "${DIM}${CYN}" "$RST" "$RED" "$RST" "$*"; }
_step() { printf "  %s│%s  %s▶%s %s\n" "${DIM}${CYN}" "$RST" "$BCYN" "$RST" "$*"; }
# Run a command that MUST succeed; abort (no half-installed state). The script
# can't use `set -e` — its many `[ cond ] && action` lines would abort spuriously.
_must() { "$@" || { _fail "failed: $*"; exit 1; }; }

cleanup() { [ -n "$CLEANUP_DIR" ] && [ -d "$CLEANUP_DIR" ] && rm -rf "$CLEANUP_DIR"; }
trap cleanup EXIT INT TERM

# ── Argument parsing ────────────────────────────────────────────
while [ $# -gt 0 ]; do
    case "$1" in
        --uninstall) ACTION="uninstall" ;;
        --check)     ACTION="check" ;;
        --no-color)  : ;;
        --help | -h)
            printf "Usage: [sudo] bash %s [--uninstall] [--check] [--no-color]\n" "$0"
            printf "\n  (no flags)    install + load the auto-heal LaunchDaemon (needs root)\n"
            printf "  --uninstall   unload + remove it (needs root)\n"
            printf "  --check       check prerequisites only (no root)\n"
            printf "  --no-color    plain output\n"
            exit 0
            ;;
        *) printf "%sUnknown option: %s%s\n" "$RED" "$1" "$RST" >&2; exit 2 ;;
    esac
    shift
done

show_banner() {
    printf "\n"
    _box_rule "╭" "╮"; _box_line ""
    _box_line "${BOLD}AIRDROP AUTO-HEAL${RST}"
    _box_line ""
    _box_line "Self-heals the macOS awdl0 AirDrop transfer flake"
    _box_line "${DIM}watch sharingd / re-prime awdl0 / zero-touch${RST}"
    _box_line ""; _box_rule "╰" "╯"; printf "\n"
}

# ── Root handling: auto-elevate for install/uninstall ───────────
ensure_root() {
    [ "$(id -u)" -eq 0 ] && return 0
    local self="${BASH_SOURCE[0]:-}"
    if [ -n "$self" ] && [ -f "$self" ]; then
        _warn "Root needed (LaunchDaemon + awdl0 control) — re-running with sudo…"
        printf "\n"
        exec sudo -- /bin/bash "$self" ${ORIG_ARGS[@]+"${ORIG_ARGS[@]}"}
    fi
    _fail "Root required, and I can't re-exec from a pipe. Re-run with sudo:"
    _info "  curl -fsSL <…>/install.sh | ${BOLD}sudo${RST} bash"
    exit 1
}

# ── Prerequisites ───────────────────────────────────────────────
check_prereqs() {
    local ok="true"
    _step "Checking prerequisites…"; printf "\n"

    if [ "$(uname -s)" = "Darwin" ]; then _done "macOS ${DIM}($(sw_vers -productVersion 2>/dev/null || echo '?'))${RST}"
    else _fail "macOS only (uname=$(uname -s))"; ok="false"; fi

    if [ -x /usr/libexec/sharingd ]; then _done "AirDrop daemon ${DIM}(/usr/libexec/sharingd)${RST}"
    else _fail "/usr/libexec/sharingd not found — is this macOS?"; ok="false"; fi

    if command -v launchctl >/dev/null 2>&1; then _done "launchctl present"; else _fail "launchctl not found"; ok="false"; fi
    if [ -x /sbin/ifconfig ]; then _done "ifconfig present"; else _fail "/sbin/ifconfig not found"; ok="false"; fi

    if /sbin/ifconfig awdl0 >/dev/null 2>&1; then _done "awdl0 interface present"
    else _warn "awdl0 not present right now (created on demand by AirDrop) — continuing"; fi

    printf "\n"
    [ "$ok" = "true" ] || { _fail "Prerequisites not met."; return 1; }
    return 0
}

# ── Locate artifacts: local clone, else sparse-fetch ────────────
locate_artifacts() {
    local self="${BASH_SOURCE[0]:-}" dir=""
    [ -n "$self" ] && [ -f "$self" ] && dir="$(cd "$(dirname "$self")" && pwd)"
    if [ -n "$dir" ] && [ -f "$dir/airdrop-autoheal.sh" ] && [ -f "$dir/doctor.sh" ] && [ -f "$dir/${LABEL}.plist" ]; then
        SRC_DIR="$dir"
        _done "Using local artifacts ${DIM}(${dir})${RST}"
        return 0
    fi
    command -v curl >/dev/null 2>&1 || { _fail "curl required to fetch artifacts"; exit 1; }
    local tmp; tmp="$(mktemp -d "${TMPDIR:-/tmp}/airdrop-autoheal-install.XXXXXX")" || { _fail "mktemp failed"; exit 1; }
    CLEANUP_DIR="$tmp"
    _step "Fetching artifacts…"
    # Plain HTTPS downloads — NOT git — so a user's url.insteadOf SSH rewrite or
    # a missing root known_hosts can't break the curl|sudo bash install path.
    local f
    for f in airdrop-autoheal.sh doctor.sh "${LABEL}.plist"; do
        if ! curl -fsSL "${RAW_BASE}/${f}" -o "${tmp}/${f}"; then
            _fail "download failed: ${f}"; exit 1
        fi
    done
    if ! head -1 "${tmp}/airdrop-autoheal.sh" 2>/dev/null | grep -q '^#!/bin/bash'; then
        _fail "fetched airdrop-autoheal.sh looks wrong (truncated/HTML?)"; exit 1
    fi
    SRC_DIR="$tmp"
    _done "Artifacts fetched"
}

# ── Install ─────────────────────────────────────────────────────
do_install() {
    _step "Installing files (root-owned)…"
    # Root-only dir (NOT /usr/local/bin — admin-writable script run by root = LPE).
    _must install -d -m 0755 -o root -g wheel "$APPDIR"
    _must install -m 0755 -o root -g wheel "$SRC_DIR/airdrop-autoheal.sh" "$APPDIR/airdrop-autoheal.sh"
    _must install -m 0755 -o root -g wheel "$SRC_DIR/doctor.sh"           "$APPDIR/doctor.sh"
    _must install -m 0644 -o root -g wheel "$SRC_DIR/${LABEL}.plist"      "$PLIST"

    # Private (non-world-readable) audit logs.
    local f
    for f in "$LOGF" "$ERRF"; do
        if [ ! -e "$f" ]; then : >"$f" || { _fail "cannot create $f"; exit 1; }; fi
        _must chown root:admin "$f"
        _must chmod 0640 "$f"
    done

    # Bound growth via newsyslog (rotate ~1MB, keep 7, bzip2).
    if ! cat >"$NEWSYSLOG" <<'NSL'
# logfilename                     [owner:group]  mode  count  size  when  flags
/var/log/airdrop-autoheal.log     root:admin     640   7      1024  *     J
/var/log/airdrop-autoheal.err     root:admin     640   7      1024  *     J
NSL
    then
        _fail "cannot write $NEWSYSLOG"; exit 1
    fi
    _must chmod 0644 "$NEWSYSLOG"
    _done "Files installed"

    _step "Loading LaunchDaemon…"
    # bootout is ASYNC — wait for full unload before bootstrap, else EIO (error 5).
    launchctl bootout "system/${LABEL}" 2>/dev/null || true
    local i
    for i in $(seq 1 20); do launchctl print "system/${LABEL}" >/dev/null 2>&1 || break; sleep 0.5; done
    launchctl enable "system/${LABEL}" 2>/dev/null || true
    # Capture stderr in a variable — no predictable /tmp file for a root process
    # to be tricked (symlink/TOCTOU) into clobbering.
    local bs_ok=0 bs_err=""
    for i in 1 2 3 4 5; do
        if bs_err="$(launchctl bootstrap system "$PLIST" 2>&1)"; then bs_ok=1; break; fi
        launchctl bootout "system/${LABEL}" 2>/dev/null || true; sleep 1
    done
    if [ "$bs_ok" -ne 1 ]; then
        _fail "bootstrap failed:"; printf '%s\n' "$bs_err" | sed 's/^/        /'
        exit 1
    fi
    launchctl kickstart -k "system/${LABEL}" 2>/dev/null || true
    _done "Daemon loaded"
}

# ── Uninstall ───────────────────────────────────────────────────
do_uninstall() {
    _step "Removing LaunchDaemon…"
    launchctl bootout "system/${LABEL}" 2>/dev/null || true
    rm -f "$PLIST" "$NEWSYSLOG"
    rm -rf "$APPDIR"
    /sbin/ifconfig awdl0 up >/dev/null 2>&1 || true   # never leave awdl0 down
    _done "Removed (logs kept at /var/log/airdrop-autoheal.{log,err})"
}

# ── Verify (run the installed doctor) ───────────────────────────
verify() {
    _step "Verifying with doctor…"; printf "\n"
    sleep 3   # let the daemon write its start line + spawn the log child
    if [ -x "$APPDIR/doctor.sh" ]; then
        /bin/bash "$APPDIR/doctor.sh"   # exits with the number of FAILs (0 = healthy)
        return $?
    fi
    _warn "doctor.sh missing — skipping verification"
    return 0
}

# ── Post-action boxes ───────────────────────────────────────────
post_install() {
    printf "\n"; _box_rule "╭" "╮"; _box_line ""
    _box_line "${BGRN}OK${RST}  ${BOLD}Installed - auto-heal is live${RST}"
    _box_line ""; _box_rule "╰" "╯"; printf "\n"
    # Long absolute paths live OUTSIDE the box (no right border to align to).
    _info "Health  ${BOLD}bash \"${APPDIR}/doctor.sh\"${RST}"
    _info "Logs    ${BOLD}sudo tail -f ${LOGF}${RST}"
    _info "Reset   ${BOLD}sudo \"${APPDIR}/airdrop-autoheal.sh\" --bounce-once${RST}"
    _info "Remove  ${BOLD}sudo bash install.sh --uninstall${RST}"
    printf "\n"
}
post_uninstall() {
    printf "\n"; _box_rule "╭" "╮"; _box_line ""
    _box_line "${BGRN}OK${RST} ${BOLD}Uninstalled${RST}"
    _box_line ""; _box_rule "╰" "╯"; printf "\n"
}

# ── Main ────────────────────────────────────────────────────────
main() {
    show_banner
    if [ "$ACTION" = "check" ]; then check_prereqs && _done "All prerequisites met!"; exit $?; fi
    ensure_root
    if [ "$ACTION" = "uninstall" ]; then do_uninstall; post_uninstall; exit 0; fi
    check_prereqs || exit 1
    locate_artifacts
    do_install
    # Gate the success box on doctor: a flapping daemon must NOT report success.
    if verify; then
        post_install
    else
        rc=$?
        printf "\n"
        _fail "doctor reported ${rc} problem(s) — the daemon did not come up healthy."
        _info "Inspect: ${BOLD}sudo tail -50 ${LOGF}${RST}"
        printf "\n"
        exit "$rc"
    fi
}

# Run main only when executed/piped directly (not when sourced by tests).
script_source="${BASH_SOURCE[0]:-}"
if [[ "$script_source" == "${0}" ]] || [[ -z "$script_source" ]]; then
    main
fi
