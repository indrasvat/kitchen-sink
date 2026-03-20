#!/bin/bash
# ╭──────────────────────────────────────────────────────────────╮
# │  Sarasa Installer                                            │
# │  One-command install for automated package manager upgrades  │
# │  Safe · No sudo required · Cleans up after itself            │
# ╰──────────────────────────────────────────────────────────────╯
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/indrasvat/kitchen-sink/main/go/sarasa/install.sh | bash
#   bash install.sh                     # local install
#   bash install.sh --prefix ~/bin      # custom install dir
#   bash install.sh --no-init           # skip interactive setup
#   bash install.sh --check             # check prerequisites only
#
# Prerequisites: git, go (1.22+)
# Installs to: ~/.local/bin/sarasa (no sudo needed)

set -uo pipefail

# ── Colors ──────────────────────────────────────────────────────
if [ -t 1 ]; then
    RST=$'\033[0m'
    DIM=$'\033[2m'
    BOLD=$'\033[1m'
    RED=$'\033[31m'
    # shellcheck disable=SC2034
    GRN=$'\033[32m'
    # shellcheck disable=SC2034
    YEL=$'\033[33m'
    CYN=$'\033[36m'
    BGRN=$'\033[92m'
    BCYN=$'\033[96m'
    BYEL=$'\033[93m'
else
    RST="" DIM="" BOLD="" RED="" CYN=""
    # shellcheck disable=SC2034
    GRN=""
    # shellcheck disable=SC2034
    YEL=""
    BGRN="" BCYN="" BYEL=""
fi

# ── Box-drawing ─────────────────────────────────────────────────
# Inner width between the two │ chars (including the leading space).
# All box content is auto-padded to exactly this width.
BW=54

# _box_rule LEFT_CORNER RIGHT_CORNER
_box_rule() {
    local left="$1" right="$2" fill=""
    local i
    for ((i = 0; i < BW; i++)); do fill="${fill}─"; done
    printf "  %s%s%s%s%s\n" "$CYN" "$left" "$fill" "$right" "$RST"
}

# _box_line [STYLED_CONTENT]
#   Auto-measures display width by stripping ANSI escapes.
#   IMPORTANT: Do NOT put emojis or wide Unicode inside box lines — their
#   display width is unpredictable across terminals and ${#} undercounts.
_box_line() {
    local content="$*"
    # Strip ANSI escape sequences to get plain text for width measurement
    local plain
    plain="$(printf '%s' "$content" | sed $'s/\033\[[0-9;]*m//g')"
    local dw=${#plain}
    local pad=$((BW - 1 - dw))
    if [ "$pad" -lt 0 ]; then pad=0; fi
    local spaces=""
    local i
    for ((i = 0; i < pad; i++)); do spaces="${spaces} "; done
    printf "  %s│%s %s%s%s│%s\n" "$CYN" "$RST" "$content" "$spaces" "$CYN" "$RST"
}

# ── Logging ─────────────────────────────────────────────────────
_info()  { printf "  %s│%s  %s▸%s %s\n" "${DIM}${CYN}" "$RST" "$CYN" "$RST" "$*"; }
_done()  { printf "  %s│%s  %s✔%s %s\n" "${DIM}${CYN}" "$RST" "$BGRN" "$RST" "$*"; }
_warn()  { printf "  %s│%s  %s⚠  %s%s\n" "${DIM}${CYN}" "$RST" "$BYEL" "$*" "$RST"; }
_fail()  { printf "  %s│%s  %s✘%s %s\n" "${DIM}${CYN}" "$RST" "$RED" "$RST" "$*"; }
_step()  { printf "  %s│%s  %s▶%s %s\n" "${DIM}${CYN}" "$RST" "$BCYN" "$RST" "$*"; }

# ── Configuration ───────────────────────────────────────────────
REPO_URL="https://github.com/indrasvat/kitchen-sink.git"
REPO_SUBDIR="go/sarasa"
INSTALL_PREFIX="${HOME}/.local/bin"
RUN_INIT="true"
CHECK_ONLY="false"
CLEANUP_DIR=""

# ── Cleanup trap ────────────────────────────────────────────────
cleanup() {
    if [ -n "$CLEANUP_DIR" ] && [ -d "$CLEANUP_DIR" ]; then
        rm -rf "$CLEANUP_DIR"
    fi
}
trap cleanup EXIT INT TERM

# ── Argument parsing ────────────────────────────────────────────
while [ $# -gt 0 ]; do
    case "$1" in
        --prefix)
            shift
            INSTALL_PREFIX="${1:?--prefix requires a path}"
            ;;
        --no-init)
            RUN_INIT="false"
            ;;
        --check)
            CHECK_ONLY="true"
            ;;
        --help|-h)
            printf "Usage: %s [--prefix DIR] [--no-init] [--check]\n" "$0"
            printf "\n  --prefix DIR   Install directory (default: ~/.local/bin)\n"
            printf "  --no-init      Skip interactive sarasa init after install\n"
            printf "  --check        Check prerequisites only, don't install\n"
            exit 0
            ;;
        *)
            printf "%sUnknown option: %s%s\n" "$RED" "$1" "$RST" >&2
            exit 2
            ;;
    esac
    shift
done

# ── Banner ──────────────────────────────────────────────────────
# No emojis inside box — only plain ASCII + ANSI styles.
show_banner() {
    printf "\n"
    _box_rule "╭" "╮"
    _box_line ""
    _box_line "${BOLD}SARASA INSTALLER${RST}"
    _box_line ""
    _box_line "Automated global package upgrades for macOS"
    _box_line "${DIM}brew  ·  volta  ·  npm  ·  pipx  ·  bun${RST}"
    _box_line ""
    _box_rule "╰" "╯"
    printf "\n"
}

# ── Prerequisite checks ────────────────────────────────────────
check_prereqs() {
    local ok="true"

    _step "Checking prerequisites..."
    printf "\n"

    # Git
    if command -v git >/dev/null 2>&1; then
        local git_ver
        git_ver="$(git --version 2>&1 | head -1)"
        _done "git: ${DIM}${git_ver}${RST}"
    else
        _fail "git: not found"
        _warn "  Install: https://git-scm.com/downloads"
        ok="false"
    fi

    # Go
    if command -v go >/dev/null 2>&1; then
        local go_ver
        go_ver="$(go version 2>&1 | head -1)"
        _done "go:  ${DIM}${go_ver}${RST}"

        # Check minimum version (1.22+)
        local minor
        minor="$(go version | sed -E 's/.*go1\.([0-9]+).*/\1/')"
        if [ "$minor" -lt 22 ] 2>/dev/null; then
            _warn "Go 1.22+ recommended (found 1.${minor})"
        fi
    else
        _fail "go:  not found"
        _warn "  Install: https://go.dev/dl"
        ok="false"
    fi

    # Install directory
    if [ -f "$INSTALL_PREFIX" ] && [ ! -d "$INSTALL_PREFIX" ]; then
        _fail "dir: ${INSTALL_PREFIX} exists as a file, not a directory"
        _warn "  Remove it or choose a different --prefix"
        ok="false"
    elif [ -d "$INSTALL_PREFIX" ]; then
        if [ -w "$INSTALL_PREFIX" ]; then
            _done "dir: ${DIM}${INSTALL_PREFIX} (writable)${RST}"
        else
            _fail "dir: ${INSTALL_PREFIX} (not writable)"
            _warn "  Choose a writable prefix with --prefix"
            ok="false"
        fi
    else
        _info "dir: ${DIM}${INSTALL_PREFIX} (will create)${RST}"
    fi

    # PATH check
    if echo "$PATH" | tr ':' '\n' | grep -qx "$INSTALL_PREFIX"; then
        _done "PATH: ${DIM}includes ${INSTALL_PREFIX}${RST}"
    else
        _warn "PATH: ${INSTALL_PREFIX} is not in \$PATH"
        _info "  Add to your shell profile:"
        _info "  ${BOLD}export PATH=\"${INSTALL_PREFIX}:\$PATH\"${RST}"
    fi

    printf "\n"

    if [ "$ok" = "false" ]; then
        _fail "Prerequisites not met. Fix the above and retry."
        return 1
    fi
    return 0
}

# ── Clone & Build ───────────────────────────────────────────────
clone_and_build() {
    local tmpdir
    tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/sarasa-install.XXXXXX")"
    CLEANUP_DIR="$tmpdir"

    _step "Cloning repository (sparse checkout)..."

    # Use sparse checkout to only fetch go/sarasa/
    git clone --depth 1 --filter=blob:none --sparse \
        "$REPO_URL" "$tmpdir/repo" 2>&1 | while IFS= read -r line; do
        printf "  %s│%s  %s%s%s\n" "${DIM}${CYN}" "$RST" "$DIM" "$line" "$RST"
    done

    (
        cd "$tmpdir/repo" || exit 1
        git sparse-checkout set "$REPO_SUBDIR" 2>/dev/null
    )

    if [ ! -f "$tmpdir/repo/${REPO_SUBDIR}/main.go" ]; then
        _fail "Clone failed: main.go not found"
        return 1
    fi
    _done "Source fetched"

    _step "Building sarasa..."

    local build_dir="$tmpdir/repo/${REPO_SUBDIR}"
    local commit_sha
    commit_sha="$(git -C "$tmpdir/repo" rev-parse --short HEAD 2>/dev/null || echo "unknown")"
    local build_date
    build_date="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

    (
        cd "$build_dir" || exit 1
        go build \
            -ldflags "-s -w -X github.com/indrasvat/sarasa/cmd.Version=${commit_sha} -X github.com/indrasvat/sarasa/cmd.Commit=${commit_sha} -X github.com/indrasvat/sarasa/cmd.BuildDate=${build_date}" \
            -o "$tmpdir/sarasa" . 2>&1
    )

    if [ ! -f "$tmpdir/sarasa" ]; then
        _fail "Build failed"
        return 1
    fi

    local size
    if stat --version >/dev/null 2>&1; then
        size="$(stat -c %s "$tmpdir/sarasa" 2>/dev/null)"
    else
        size="$(stat -f %z "$tmpdir/sarasa" 2>/dev/null)"
    fi
    local size_mb
    size_mb="$(awk "BEGIN { printf \"%.1f\", ${size:-0} / 1048576 }")"

    _done "Built sarasa ${DIM}(${size_mb} MB, ${commit_sha})${RST}"

    # Verify binary works
    if ! "$tmpdir/sarasa" version >/dev/null 2>&1; then
        _fail "Binary verification failed"
        return 1
    fi
    _done "Binary verified"
}

# ── Install ─────────────────────────────────────────────────────
install_binary() {
    local src="$CLEANUP_DIR/sarasa"

    # Refuse if prefix path is a regular file
    if [ -f "$INSTALL_PREFIX" ] && [ ! -d "$INSTALL_PREFIX" ]; then
        _fail "${INSTALL_PREFIX} is a file, not a directory"
        _warn "Remove it first, or use --prefix <dir>"
        return 1
    fi

    # Create install directory if needed
    if [ ! -d "$INSTALL_PREFIX" ]; then
        mkdir -p "$INSTALL_PREFIX" || {
            _fail "Cannot create ${INSTALL_PREFIX}"
            _warn "Try: --prefix ~/bin  (or another writable directory)"
            return 1
        }
        _done "Created ${INSTALL_PREFIX}"
    fi

    # Check for existing installation
    if [ -f "${INSTALL_PREFIX}/sarasa" ]; then
        local existing_ver
        existing_ver="$("${INSTALL_PREFIX}/sarasa" version 2>/dev/null | head -1 || echo "unknown")"
        _info "Replacing existing: ${DIM}${existing_ver}${RST}"
    fi

    cp "$src" "${INSTALL_PREFIX}/sarasa" || {
        _fail "Cannot copy to ${INSTALL_PREFIX}/sarasa"
        return 1
    }
    chmod +x "${INSTALL_PREFIX}/sarasa" || true

    _done "Installed to ${BOLD}${INSTALL_PREFIX}/sarasa${RST}"
}

# ── Post-install ────────────────────────────────────────────────
post_install() {
    printf "\n"
    _box_rule "╭" "╮"
    _box_line ""
    _box_line "${BGRN}OK${RST} ${BOLD}Installation complete!${RST}"
    _box_line ""

    if [ "$RUN_INIT" = "true" ] && [ -t 0 ] && [ -t 1 ]; then
        _box_line "Running ${BOLD}sarasa init${RST} to configure..."
        _box_line ""
        _box_rule "╰" "╯"
        printf "\n"
        "${INSTALL_PREFIX}/sarasa" init
    else
        _box_line "Next steps:"
        _box_line "  ${BOLD}sarasa init${RST}     -- interactive setup"
        _box_line "  ${BOLD}sarasa status${RST}   -- check outdated packages"
        _box_line "  ${BOLD}sarasa run${RST}      -- upgrade everything"
        _box_line ""
        _box_rule "╰" "╯"
        printf "\n"
    fi
}

# ── Main ────────────────────────────────────────────────────────
main() {
    show_banner

    if ! check_prereqs; then
        exit 1
    fi

    if [ "$CHECK_ONLY" = "true" ]; then
        _done "All prerequisites met!"
        exit 0
    fi

    clone_and_build || exit 1
    printf "\n"

    install_binary || exit 1

    post_install
}

main
