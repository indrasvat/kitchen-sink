#!/bin/bash
# ╭──────────────────────────────────────────────────────────────╮
# │  सामग्री (Sāmagrī) — macOS Dev Environment Setup            │
# │  Reads a Yantragaṇanā inventory JSON and rebuilds the env   │
# │  Safe · Idempotent · Resumable · Interactive                 │
# ╰──────────────────────────────────────────────────────────────╯
#
# Usage:
#   ./saamagri.sh                              # interactive, personal profile
#   ./saamagri.sh --yes                        # non-interactive, accept all defaults
#   ./saamagri.sh --profile work               # work Mac (skip personal-only tools)
#   ./saamagri.sh --phase 5                    # resume from phase 5
#   ./saamagri.sh --dry-run                    # show what would be done
#   ./saamagri.sh --inventory path/to/inv.json # use specific inventory
#
# NOTE: This script is intentionally bash 3.2 compatible (no associative arrays,
# no readarray, no ${var,,}) because a fresh Mac only has /bin/bash 3.2.
# After Phase 4 installs brew bash 5.x, subsequent runs benefit automatically.

set -uo pipefail
# NOTE: we do NOT use set -e — each phase handles its own errors for resilience.

readonly SMGR_VERSION="1.0.0"

# ── Paths & Defaults ─────────────────────────────────────────────
readonly STATE_DIR="$HOME/.saamagri"
BACKUP_DIR="$STATE_DIR/backups/$(date +%Y%m%d-%H%M%S)"
readonly BACKUP_DIR
readonly LOG_DIR="$STATE_DIR/logs"
readonly COMPLETED_FILE="$STATE_DIR/completed_phases"

# Runtime config (mutable — set during arg parsing)
INVENTORY_FILE=""
AUTO_YES="false"
DRY_RUN="false"
START_PHASE=1
PROFILE="personal"
LOG_FILE=""
export CURRENT_PHASE=0
TOTAL_PHASES=17

# Work profile config (set via --work-* flags or interactive prompts)
WORK_EMAIL=""
WORK_ORG=""
WORK_DIR=""
WORK_SSH_HOST=""

# ── Colors (works on bash 3.2) ───────────────────────────────────
RST=$'\033[0m'
DIM=$'\033[2m'
BOLD=$'\033[1m'
UL=$'\033[4m'
RED=$'\033[31m'
# shellcheck disable=SC2034
GRN=$'\033[32m'
YEL=$'\033[33m'
CYN=$'\033[36m'
BGRN=$'\033[92m'
BWHT=$'\033[97m'
BYEL=$'\033[93m'

# ── Layout ───────────────────────────────────────────────────────
LINE_W=62
RULE='───────────────────────────────────────────────────────────'
BW=42

# ── Logging ──────────────────────────────────────────────────────
_info()  { _wal INFO  "$*"; printf "  ${DIM}${CYN}│${RST}  ${CYN}▸${RST} %s\n" "$*" >&2; }
_done()  { _wal OK    "$*"; printf "  ${DIM}${CYN}│${RST}  ${BGRN}✔${RST} %s\n" "$*" >&2; }
_warn()  { _wal WARN  "$*"; printf "  ${DIM}${CYN}│${RST}  ${BYEL}⚠${RST}  ${YEL}%s${RST}\n" "$*" >&2; }
_skip()  { _wal SKIP  "$*"; printf "  ${DIM}${CYN}│${RST}  ${DIM}○ %s${RST}\n" "$*" >&2; }
_err()   { _wal ERROR "$*"; printf "  ${DIM}${CYN}│${RST}  ${RED}✘${RST} %s\n" "$*" >&2; }
_act()   { _wal ACT   "$*"; printf "  ${DIM}${CYN}│${RST}  ${BWHT}▶${RST} %s\n" "$*" >&2; }

_phase() {
    _wal PHASE "=== $1 ==="
    local label="$1"
    local used=$(( 2 + 5 + ${#label} + 1 ))
    local pad_len=$(( LINE_W - used ))
    if [ "$pad_len" -lt 1 ]; then pad_len=1; fi
    local pad=""
    local i=0; while [ "$i" -lt "$pad_len" ]; do pad="${pad}─"; i=$((i + 1)); done
    printf "\n  ${BOLD}${CYN}┌─── %s ${DIM}%s${RST}\n" "$label" "$pad" >&2
}

_phase_end() {
    printf "  ${DIM}${CYN}└%s${RST}\n" "$RULE" >&2
}

_box_rule() {
    local color="$1" top="$2" bottom="$3"
    local dashes="" i=0; while [ "$i" -lt "$BW" ]; do dashes="${dashes}─"; i=$((i + 1)); done
    printf "  ${BOLD}%s%s%s%s${RST}\n" "$color" "$top" "$dashes" "$bottom" >&2
}

_box_line() {
    local color="$1" plain_len="$2" content="$3"
    local pad_len=$(( BW - plain_len ))
    if [ "$pad_len" -lt 0 ]; then pad_len=0; fi
    local pad=""
    local i=0; while [ "$i" -lt "$pad_len" ]; do pad="${pad} "; i=$((i + 1)); done
    printf "  ${BOLD}%s│${RST}%s%s${BOLD}%s│${RST}\n" "$color" "$content" "$pad" "$color" >&2
}

# ── WAL Logging ──────────────────────────────────────────────────
_wal() {
    [ -z "$LOG_FILE" ] && return 0
    local level="$1"; shift
    printf '%s [%-5s] %s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$level" "$*" \
        | sed $'s/\033\\[[0-9;]*[mGKHJ]//g' >> "$LOG_FILE"
}

# ── PATH Bootstrap ──────────────────────────────────────────────
# Rehydrate PATH for tools installed in prior phases (critical for --phase N resume)
_bootstrap_path() {
    # Homebrew
    if [ -f /opt/homebrew/bin/brew ]; then
        eval "$(/opt/homebrew/bin/brew shellenv 2>/dev/null)" || true
    elif [ -f /usr/local/bin/brew ]; then
        eval "$(/usr/local/bin/brew shellenv 2>/dev/null)" || true
    fi
    # Cargo/Rust
    if [ -f "$HOME/.cargo/env" ]; then
        # shellcheck source=/dev/null
        . "$HOME/.cargo/env" 2>/dev/null || true
    fi
    # Volta
    if [ -d "$HOME/.volta" ]; then
        export VOLTA_HOME="$HOME/.volta"
        export PATH="$VOLTA_HOME/bin:$PATH"
    fi
    # Bun
    if [ -d "$HOME/.bun" ]; then
        export BUN_INSTALL="$HOME/.bun"
        export PATH="$BUN_INSTALL/bin:$PATH"
    fi
}

# ── Helpers ──────────────────────────────────────────────────────
cmd_exists() { command -v "$1" >/dev/null 2>&1; }

# Safe command execution with dry-run support and logging
run_cmd() {
    if [ "$DRY_RUN" = "true" ]; then
        _info "${DIM}[dry-run]${RST} $*"
        _wal "DRY" "$*"
        return 0
    fi
    _wal "EXEC" "$*"
    "$@" >> "$LOG_FILE" 2>&1
    local rc=$?
    _wal "EXIT" "rc=$rc cmd=$*"
    if [ $rc -ne 0 ]; then
        _err "Command failed (rc=$rc): $*"
    fi
    return $rc
}

# Read from inventory JSON — uses jq if available, python3 as fallback
inv_get() {
    if cmd_exists jq; then
        jq -r "$1" "$INVENTORY_FILE" 2>/dev/null
    elif cmd_exists python3; then
        python3 -c "
import json, sys, re
try:
    data = json.load(open('$INVENTORY_FILE'))
    path = '''$1'''.strip('.')
    tokens = re.findall(r'\[[^\]]*\]|[^.\[\]]+', path)
    for tok in tokens:
        if tok == '[]':
            # Iterate current array
            for item in (data if isinstance(data, list) else []):
                print(item if isinstance(item, str) else json.dumps(item))
            sys.exit(0)
        elif tok.endswith('[]'):
            data = data[tok[:-2]]
            for item in (data if isinstance(data, list) else []):
                print(item if isinstance(item, str) else json.dumps(item))
            sys.exit(0)
        elif tok.startswith('[') and tok.endswith(']'):
            data = data[int(tok[1:-1])]
        else:
            data = data[tok]
    if data is None:
        print('')
    elif isinstance(data, str):
        print(data)
    elif isinstance(data, bool):
        print(str(data).lower())
    else:
        print(json.dumps(data))
except Exception:
    print('')
" 2>/dev/null
    else
        echo ""
    fi
}

# Read raw JSON content from a path (for writing config files)
inv_content() {
    if cmd_exists jq; then
        jq -r "$1 // empty" "$INVENTORY_FILE" 2>/dev/null
    elif cmd_exists python3; then
        python3 -c "
import json, re
data = json.load(open('$INVENTORY_FILE'))
path = '''$1'''.strip('.')
tokens = re.findall(r'\[[^\]]*\]|[^.\[\]]+', path)
for tok in tokens:
    if data is None: break
    if tok.startswith('[') and tok.endswith(']'):
        idx = int(tok[1:-1])
        data = data[idx] if isinstance(data, list) and idx < len(data) else None
    elif isinstance(data, dict):
        data = data.get(tok)
    else:
        data = None
if data is None:
    pass  # print nothing, matching jq's '// empty'
elif isinstance(data, str):
    print(data)
else:
    print(json.dumps(data))
" 2>/dev/null
    else
        echo ""
    fi
}

# State management — simple text file, no jq needed
phase_completed() {
    [ -f "$COMPLETED_FILE" ] && grep -qx "$1" "$COMPLETED_FILE" 2>/dev/null
}

mark_phase_complete() {
    mkdir -p "$STATE_DIR"
    if ! phase_completed "$1"; then
        echo "$1" >> "$COMPLETED_FILE"
    fi
    _wal "DONE" "Phase $1 marked complete"
}

# Backup a file before overwriting
backup_file() {
    local f="$1"
    if [ -f "$f" ]; then
        mkdir -p "$BACKUP_DIR"
        cp "$f" "$BACKUP_DIR/$(basename "$f")"
        _info "Backed up $(basename "$f")"
    fi
}

# Write inventory content to a file (with backup)
write_config() {
    local json_path="$1" target_path="$2"
    local content
    content=$(inv_content "$json_path")
    if [ -z "$content" ]; then
        _skip "No content for $target_path in inventory"
        return 0
    fi
    # Check if identical
    if [ -f "$target_path" ]; then
        local existing
        existing=$(cat "$target_path" 2>/dev/null)
        if [ "$existing" = "$content" ]; then
            _skip "$(basename "$target_path") already up to date"
            return 0
        fi
    fi
    backup_file "$target_path"
    local dir
    dir=$(dirname "$target_path")
    mkdir -p "$dir"
    if [ "$DRY_RUN" = "true" ]; then
        _info "${DIM}[dry-run]${RST} Would write $target_path"
        return 0
    fi
    printf '%s' "$content" > "$target_path"
    _done "Wrote $(basename "$target_path")"
}

# Interactive confirmation
confirm_phase() {
    local phase_num="$1" phase_name="$2"
    if [ "$AUTO_YES" = "true" ]; then return 0; fi
    printf "\n  ${BOLD}${BWHT}▶ Phase %s — %s${RST} ${DIM}[Y/n/s(kip)/q(uit)]${RST} " "$phase_num" "$phase_name" >&2
    local reply
    read -r reply
    case "$reply" in
        [Nn]*|[Ss]*)  _skip "Skipped by user"; return 1 ;;
        [Qq]*)  _warn "Aborted at Phase $phase_num. Resume with: saamagri.sh --phase $phase_num"
                exit 0 ;;
        *)      return 0 ;;
    esac
}

# Count items in a jq array
inv_count() {
    if cmd_exists jq; then
        jq -r "$1 | length" "$INVENTORY_FILE" 2>/dev/null
    else
        echo "?"
    fi
}

# Prompt for a value if not already set. Usage: prompt_if_empty VAR "prompt text" "default"
prompt_if_empty() {
    local varname="$1" prompt_text="$2" default="${3:-}"
    local current_val=""
    eval "current_val=\"\$$varname\""
    if [ -n "$current_val" ]; then return 0; fi
    if [ "$AUTO_YES" = "true" ] && [ -n "$default" ]; then
        eval "$varname=\"$default\""
        return 0
    fi
    local suffix=""
    [ -n "$default" ] && suffix=" ${DIM}[$default]${RST}"
    printf "  ${BOLD}${BWHT}%s${RST}%s: " "$prompt_text" "$suffix" >&2
    local reply
    read -r reply
    if [ -z "$reply" ] && [ -n "$default" ]; then reply="$default"; fi
    eval "$varname=\"\$reply\""
}

# Collect work profile config interactively if not set via flags
collect_work_config() {
    if [ "$PROFILE" != "work" ]; then return 0; fi

    # Apply defaults for optional flags before checking completeness
    [ -z "$WORK_SSH_HOST" ] && WORK_SSH_HOST="github.com-work"
    [ -z "$WORK_DIR" ] && WORK_DIR="$HOME/work/src"

    # Only prompt if required work flags are missing
    if [ -n "$WORK_EMAIL" ] && [ -n "$WORK_ORG" ]; then
        return 0
    fi

    _phase "Work Profile Setup"
    _info "Configure your work identity (personal identity comes from inventory)"

    prompt_if_empty WORK_EMAIL "Work email" ""
    prompt_if_empty WORK_ORG "GitHub org (e.g. spectrocloud)" ""
    prompt_if_empty WORK_DIR "Work repo directory" "$HOME/work/src"
    prompt_if_empty WORK_SSH_HOST "SSH host alias for work GitHub" "github.com-work"

    if [ -z "$WORK_EMAIL" ]; then
        _warn "No work email provided — skipping work identity setup"
        _phase_end
        return 1
    fi

    _done "Work email: $WORK_EMAIL"
    [ -n "$WORK_ORG" ] && _done "Work org: $WORK_ORG"
    _done "Work dir: $WORK_DIR"
    _done "SSH host: $WORK_SSH_HOST"
    _phase_end
}

# ══════════════════════════════════════════════════════════════════
# PHASE IMPLEMENTATIONS
# ══════════════════════════════════════════════════════════════════

# ── Phase 1: Xcode Command Line Tools ────────────────────────────
phase_01_xcode_clt() {
    CURRENT_PHASE=1
    if phase_completed 1; then _skip "Phase 1 already completed"; return 0; fi
    _phase "Phase 1 — Xcode Command Line Tools"

    if xcode-select -p >/dev/null 2>&1; then
        _done "Already installed at $(xcode-select -p 2>/dev/null)"
        mark_phase_complete 1
        _phase_end; return 0
    fi

    if ! confirm_phase 1 "Xcode Command Line Tools"; then _phase_end; return 0; fi

    _act "Installing Xcode CLT (a dialog will appear)..."
    if [ "$DRY_RUN" = "true" ]; then
        _info "${DIM}[dry-run]${RST} Would run: xcode-select --install"
    else
        xcode-select --install 2>/dev/null || true
        _warn "Please complete the Xcode CLT dialog, then press Enter to continue"
        read -r
        if ! xcode-select -p >/dev/null 2>&1; then
            _err "Xcode CLT not detected. Re-run this script after installation."
            _phase_end; return 1
        fi
    fi
    _done "Xcode CLT installed"
    mark_phase_complete 1
    _phase_end
}

# ── Phase 2: Homebrew ────────────────────────────────────────────
phase_02_homebrew() {
    CURRENT_PHASE=2
    if phase_completed 2; then _skip "Phase 2 already completed"; return 0; fi
    _phase "Phase 2 — Homebrew"

    if cmd_exists brew; then
        _done "Already installed: $(brew --version 2>/dev/null | head -1)"
        # Ensure brew is in PATH for this session
        eval "$(brew shellenv 2>/dev/null)" || true
        mark_phase_complete 2
        _phase_end; return 0
    fi

    if ! confirm_phase 2 "Homebrew"; then _phase_end; return 0; fi

    _act "Installing Homebrew..."
    if [ "$DRY_RUN" = "true" ]; then
        _info "${DIM}[dry-run]${RST} Would install Homebrew"
    else
        NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" >> "$LOG_FILE" 2>&1
        # Set up PATH for current session
        if [ -f /opt/homebrew/bin/brew ]; then
            eval "$(/opt/homebrew/bin/brew shellenv)"
        elif [ -f /usr/local/bin/brew ]; then
            eval "$(/usr/local/bin/brew shellenv)"
        fi
    fi

    if cmd_exists brew; then
        _done "Homebrew installed: $(brew --version 2>/dev/null | head -1)"
    else
        _err "Homebrew installation failed — check $LOG_FILE"
        _phase_end; return 1
    fi
    mark_phase_complete 2
    _phase_end
}

# ── Phase 3: Core Formulae ───────────────────────────────────────
phase_03_core_formulae() {
    CURRENT_PHASE=3
    if phase_completed 3; then _skip "Phase 3 already completed"; return 0; fi
    _phase "Phase 3 — Core Formulae"

    # These are needed before anything else
    local core_formulae="git jq bash coreutils bash-completion@2"
    local to_install="" installed=0 pending=0

    for f in $core_formulae; do
        if brew list --formula 2>/dev/null | grep -qx "$f"; then
            installed=$((installed + 1))
        else
            to_install="$to_install $f"
            pending=$((pending + 1))
        fi
    done

    if [ $pending -eq 0 ]; then
        _done "All core formulae already installed ($installed/$installed)"
        mark_phase_complete 3
        _phase_end; return 0
    fi

    _info "$installed already installed, $pending to install:$to_install"
    if ! confirm_phase 3 "Core Formulae"; then _phase_end; return 0; fi

    local any_failed="false"
    for f in $to_install; do
        _act "Installing $f..."
        if run_cmd brew install "$f"; then
            _done "$f"
        else
            _err "Failed to install $f"
            any_failed="true"
        fi
    done
    if [ "$any_failed" = "true" ]; then
        _err "Some core formulae failed — not marking phase complete"
        _phase_end; return 1
    fi
    mark_phase_complete 3
    _phase_end
}

# ── Phase 4: Set Bash as Default Shell ───────────────────────────
phase_04_default_shell() {
    CURRENT_PHASE=4
    if phase_completed 4; then _skip "Phase 4 already completed"; return 0; fi
    _phase "Phase 4 — Set Bash as Default Shell"

    local brew_bash=""
    if [ -f /opt/homebrew/bin/bash ]; then
        brew_bash="/opt/homebrew/bin/bash"
    elif [ -f /usr/local/bin/bash ]; then
        brew_bash="/usr/local/bin/bash"
    fi

    if [ -z "$brew_bash" ]; then
        _err "Brew bash not found. Was Phase 3 completed?"
        _phase_end; return 1
    fi

    local current_shell
    current_shell=$(dscl . -read "/Users/$USER" UserShell 2>/dev/null | awk '{print $2}')
    if [ "$current_shell" = "$brew_bash" ]; then
        _done "Already default: $brew_bash"
        mark_phase_complete 4
        _phase_end; return 0
    fi

    _info "Current default: $current_shell"
    _info "Target: $brew_bash"
    if ! confirm_phase 4 "Set $brew_bash as default shell"; then _phase_end; return 0; fi

    if [ "$DRY_RUN" = "true" ]; then
        _info "${DIM}[dry-run]${RST} Would add $brew_bash to /etc/shells and chsh"
    else
        # Add to /etc/shells if missing
        if ! grep -qx "$brew_bash" /etc/shells 2>/dev/null; then
            _act "Adding $brew_bash to /etc/shells (requires sudo)..."
            echo "$brew_bash" | sudo tee -a /etc/shells >/dev/null
        fi
        _act "Changing default shell (requires password)..."
        chsh -s "$brew_bash"
    fi
    _done "Default shell set to $brew_bash"
    _warn "Open a new terminal for the change to take effect"
    mark_phase_complete 4
    _phase_end
}

# ── Phase 5: Remaining Brew Packages ─────────────────────────────
phase_05_brew_packages() {
    CURRENT_PHASE=5
    if phase_completed 5; then _skip "Phase 5 already completed"; return 0; fi
    _phase "Phase 5 — Brew Formulae, Casks & Taps"

    # Taps
    local tap_count
    tap_count=$(inv_count '.homebrew.taps')
    _info "$tap_count taps to configure"
    if cmd_exists jq; then
        local tap
        for tap in $(jq -r '.homebrew.taps[]' "$INVENTORY_FILE" 2>/dev/null); do
            if brew tap 2>/dev/null | grep -qx "$tap"; then
                continue
            fi
            _act "Tapping $tap..."
            run_cmd brew tap "$tap" || _warn "Failed to tap $tap"
        done
    fi

    # Formulae (skip the core ones from Phase 3)
    local formula_count
    formula_count=$(inv_count '.homebrew.formulae')
    _info "$formula_count formulae from inventory"

    if ! confirm_phase 5 "Brew Packages ($formula_count formulae, $(inv_count '.homebrew.casks') casks)"; then
        _phase_end; return 0
    fi

    if cmd_exists jq; then
        local installed_formulae
        installed_formulae=$(brew list --formula 2>/dev/null)
        local to_install="" pending=0

        local name
        for name in $(jq -r '.homebrew.formulae[].name' "$INVENTORY_FILE" 2>/dev/null); do
            if echo "$installed_formulae" | grep -qx "$name"; then
                continue
            fi
            to_install="$to_install $name"
            pending=$((pending + 1))
        done

        if [ $pending -gt 0 ]; then
            _act "Installing $pending formulae..."
            local failed=0
            for name in $to_install; do
                if ! run_cmd brew install "$name" 2>/dev/null; then
                    failed=$((failed + 1))
                fi
            done
            _done "$((pending - failed)) formulae installed ($failed failed)"
        else
            _done "All formulae already installed"
        fi

        # Casks
        local installed_casks
        installed_casks=$(brew list --cask 2>/dev/null)
        local cask_to_install="" cask_pending=0

        for name in $(jq -r '.homebrew.casks[].name' "$INVENTORY_FILE" 2>/dev/null); do
            # Profile filtering
            if [ "$PROFILE" = "work" ]; then
                case "$name" in codex) continue ;; esac
            fi
            if echo "$installed_casks" | grep -qx "$name"; then
                continue
            fi
            cask_to_install="$cask_to_install $name"
            cask_pending=$((cask_pending + 1))
        done

        if [ $cask_pending -gt 0 ]; then
            _act "Installing $cask_pending casks..."
            local cfailed=0
            for name in $cask_to_install; do
                _info "Installing cask: $name"
                if ! run_cmd brew install --cask "$name" 2>/dev/null; then
                    cfailed=$((cfailed + 1))
                fi
            done
            _done "$((cask_pending - cfailed)) casks installed ($cfailed failed)"
        else
            _done "All casks already installed"
        fi
        # Check for any failures
        local total_failed=$((failed + cfailed))
        if [ "$total_failed" -gt 0 ]; then
            _err "$total_failed package(s) failed — not marking phase complete"
            _phase_end; return 1
        fi
    else
        _warn "jq not available — cannot parse inventory. Install jq and re-run from --phase 5"
        _phase_end; return 1
    fi
    mark_phase_complete 5
    _phase_end
}

# ── Phase 6: Language Runtimes ───────────────────────────────────
phase_06_language_runtimes() {
    CURRENT_PHASE=6
    if phase_completed 6; then _skip "Phase 6 already completed"; return 0; fi
    _phase "Phase 6 — Language Runtimes"

    if ! confirm_phase 6 "Language Runtimes (Rust, Volta/Node, Bun, SDKMAN)"; then
        _phase_end; return 0
    fi

    # 6a: Rust via rustup (Go, Python/uv, Deno come via brew)
    if ! cmd_exists rustup; then
        _act "Installing Rust via rustup..."
        if [ "$DRY_RUN" = "true" ]; then
            _info "${DIM}[dry-run]${RST} Would install rustup"
        else
            curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y >> "$LOG_FILE" 2>&1
            # Source cargo env for current session
            # shellcheck source=/dev/null
            [ -f "$HOME/.cargo/env" ] && . "$HOME/.cargo/env"
        fi
        if cmd_exists rustc; then
            _done "Rust $(rustc --version 2>/dev/null | awk '{print $2}')"
        else
            _err "Rust installation failed"
        fi
    else
        _done "Rust already installed: $(rustc --version 2>/dev/null | awk '{print $2}')"
    fi

    # Rust toolchains
    if cmd_exists jq && cmd_exists rustup; then
        local tc
        for tc in $(jq -r '.rust.toolchains[]' "$INVENTORY_FILE" 2>/dev/null); do
            # Remove " (default)" suffix
            tc="${tc% (default)}"
            if rustup toolchain list 2>/dev/null | grep -q "$tc"; then continue; fi
            _act "Installing toolchain: $tc"
            run_cmd rustup toolchain install "$tc" || true
        done
    fi

    # 6b: Volta
    if ! cmd_exists volta; then
        _act "Installing Volta..."
        if [ "$DRY_RUN" = "true" ]; then
            _info "${DIM}[dry-run]${RST} Would install Volta"
        else
            curl https://get.volta.sh 2>/dev/null | bash -s -- --skip-setup >> "$LOG_FILE" 2>&1
            export VOLTA_HOME="$HOME/.volta"
            export PATH="$VOLTA_HOME/bin:$PATH"
        fi
        if cmd_exists volta; then
            _done "Volta $(volta --version 2>/dev/null)"
        else
            _err "Volta installation failed"
        fi
    else
        _done "Volta already installed: $(volta --version 2>/dev/null)"
    fi

    # Install default node + npm via the detected version manager
    if cmd_exists jq; then
        local version_manager node_ver
        version_manager=$(jq -r '.node_ecosystem.version_manager' "$INVENTORY_FILE" 2>/dev/null)
        node_ver=$(jq -r '.node_ecosystem.node_version' "$INVENTORY_FILE" 2>/dev/null | sed 's/^v//')

        if [ "$version_manager" = "volta" ] && cmd_exists volta; then
            local volta_node
            volta_node=$(jq -r '[.node_ecosystem.volta_tools[] | select(.kind=="runtime" and .default==true)] | .[0].version' "$INVENTORY_FILE" 2>/dev/null)
            if [ -n "$volta_node" ] && [ "$volta_node" != "null" ]; then
                _act "Installing Node $volta_node via Volta..."
                run_cmd volta install "node@$volta_node" || true
            fi
        elif [ -n "$node_ver" ] && [ "$node_ver" != "null" ] && [ "$node_ver" != "not installed" ]; then
            if ! cmd_exists node; then
                _info "Node $node_ver needed but no version manager detected"
                _info "Install via: brew install node (or install volta/fnm/nvm first)"
            fi
        fi
    fi

    # 6c: Bun
    if ! cmd_exists bun; then
        _act "Installing Bun..."
        if [ "$DRY_RUN" != "true" ]; then
            curl -fsSL https://bun.sh/install 2>/dev/null | bash >> "$LOG_FILE" 2>&1 || true
            export BUN_INSTALL="$HOME/.bun"
            export PATH="$BUN_INSTALL/bin:$PATH"
        fi
        if cmd_exists bun; then _done "Bun $(bun --version 2>/dev/null)"; else _warn "Bun not installed"; fi
    else
        _done "Bun already installed: $(bun --version 2>/dev/null)"
    fi

    # 6d: SDKMAN
    local sdkman_status
    sdkman_status=$(inv_get '.other_runtimes.sdkman')
    if [ "$sdkman_status" = "installed" ] && [ ! -f "$HOME/.sdkman/bin/sdkman-init.sh" ]; then
        _act "Installing SDKMAN..."
        if [ "$DRY_RUN" != "true" ]; then
            curl -s "https://get.sdkman.io" 2>/dev/null | bash >> "$LOG_FILE" 2>&1 || true
        fi
    else
        [ -f "$HOME/.sdkman/bin/sdkman-init.sh" ] && _done "SDKMAN already installed"
    fi

    mark_phase_complete 6
    _phase_end
}

# ── Phase 7: Language-Specific Tools ─────────────────────────────
phase_07_language_tools() {
    CURRENT_PHASE=7
    if phase_completed 7; then _skip "Phase 7 already completed"; return 0; fi
    _phase "Phase 7 — Language Tools"

    if ! confirm_phase 7 "Language Tools (cargo, volta, uv installs)"; then
        _phase_end; return 0
    fi

    if ! cmd_exists jq; then
        _warn "jq required for this phase"; _phase_end; return 0
    fi

    # 7a: Cargo binaries
    if cmd_exists cargo; then
        local cbin
        for cbin in $(jq -r '.rust.cargo_binaries[].name' "$INVENTORY_FILE" 2>/dev/null); do
            if cmd_exists "$cbin"; then _skip "$cbin already installed"; continue; fi
            _act "cargo install $cbin"
            run_cmd cargo install "$cbin" || _warn "Failed: cargo install $cbin"
        done
    fi

    # 7b: Volta packages
    if cmd_exists volta; then
        local pkg_name pkg_ver
        while IFS=$'\t' read -r pkg_name pkg_ver; do
            [ -z "$pkg_name" ] && continue
            # Profile filtering
            if [ "$PROFILE" = "work" ]; then
                case "$pkg_name" in
                    "@google/gemini-cli"|"@google/jules") continue ;;
                esac
            fi
            _act "volta install $pkg_name@$pkg_ver"
            run_cmd volta install "$pkg_name@$pkg_ver" || _warn "Failed: $pkg_name"
        done < <(jq -r '.node_ecosystem.volta_tools[] | select(.kind=="package") | [.name, .version] | @tsv' "$INVENTORY_FILE" 2>/dev/null)
    fi

    # 7c: uv tools
    if cmd_exists uv; then
        local utool
        for utool in $(jq -r '.python_ecosystem.uv_tools[].name' "$INVENTORY_FILE" 2>/dev/null); do
            _act "uv tool install $utool"
            run_cmd uv tool install "$utool" || _warn "Failed: $utool"
        done
    fi

    _done "Language tools installed"
    mark_phase_complete 7
    _phase_end
}

# ── Phase 8: Shell Configurations ────────────────────────────────
phase_08_shell_configs() {
    CURRENT_PHASE=8
    if phase_completed 8; then _skip "Phase 8 already completed"; return 0; fi
    _phase "Phase 8 — Shell Configurations"

    local config_count
    config_count=$(inv_count '.shell_configs.configs')
    _info "$config_count config files to write"
    if ! confirm_phase 8 "Shell Configs ($config_count files)"; then _phase_end; return 0; fi

    if ! cmd_exists jq; then _warn "jq required"; _phase_end; return 0; fi

    local i=0
    while [ "$i" -lt "$config_count" ]; do
        local path content
        path=$(jq -r ".shell_configs.configs[$i].path" "$INVENTORY_FILE" 2>/dev/null)
        [ -z "$path" ] || [ "$path" = "null" ] && { i=$((i + 1)); continue; }
        # Rewrite paths from the inventory's $HOME to the current $HOME
        # (inventory may have been captured on a machine with a different username)
        local inv_home
        inv_home=$(echo "$path" | sed -E 's|^(/Users/[^/]+).*|\1|')
        if [ "$inv_home" != "$HOME" ] && [ -n "$inv_home" ]; then
            path="${path/$inv_home/$HOME}"
        fi
        write_config ".shell_configs.configs[$i].content" "$path"
        i=$((i + 1))
    done

    # Starship themes
    local theme
    for theme in $(jq -r '.shell_configs.starship_themes[]' "$INVENTORY_FILE" 2>/dev/null); do
        [ "$theme" = "starship.toml" ] && continue  # symlink, handled above
        _info "Starship theme: $theme (copy from backup or inventory)"
    done

    mark_phase_complete 8
    _phase_end
}

# ── Phase 9: Git Configuration ───────────────────────────────────
phase_09_git_config() {
    CURRENT_PHASE=9
    if phase_completed 9; then _skip "Phase 9 already completed"; return 0; fi
    _phase "Phase 9 — Git Configuration"

    local git_user git_email
    git_user=$(inv_get '.git_config.user')
    git_email=$(inv_get '.git_config.email')
    _info "Git user: $git_user <$git_email>"

    if ! confirm_phase 9 "Git Configuration"; then _phase_end; return 0; fi

    write_config '.git_config.gitconfig' "$HOME/.gitconfig"

    # Global gitignore
    local gitignore_path
    gitignore_path=$(inv_get '.git_config.global_gitignore_path')
    [ -n "$gitignore_path" ] && [ "$gitignore_path" != "null" ] && \
        write_config '.git_config.global_gitignore' "$gitignore_path"

    # Work profile: add includeIf and write ~/.gitconfig-work
    if [ "$PROFILE" = "work" ] && [ -n "$WORK_EMAIL" ] && [ -n "$WORK_DIR" ]; then
        local work_dir_pattern="$WORK_DIR"
        # Ensure trailing slash for gitdir matching
        case "$work_dir_pattern" in
            */) ;; *) work_dir_pattern="${work_dir_pattern}/" ;;
        esac

        # Add includeIf to .gitconfig if not already present
        if [ -f "$HOME/.gitconfig" ] && ! grep -q "gitdir:${work_dir_pattern}" "$HOME/.gitconfig" 2>/dev/null; then
            if [ "$DRY_RUN" = "true" ]; then
                _info "${DIM}[dry-run]${RST} Would add includeIf to .gitconfig"
            else
                printf '\n[includeIf "gitdir:%s"]\n\tpath = ~/.gitconfig-work\n' "$work_dir_pattern" >> "$HOME/.gitconfig"
                _done "Added includeIf for $work_dir_pattern"
            fi
        else
            _skip "includeIf already present in .gitconfig"
        fi

        # Write ~/.gitconfig-work (update if contents changed)
        local work_gitconfig="[user]\n\temail = ${WORK_EMAIL}"
        if [ -n "$WORK_ORG" ] && [ -n "$WORK_SSH_HOST" ]; then
            work_gitconfig="${work_gitconfig}\n[url \"git@${WORK_SSH_HOST}:${WORK_ORG}/\"]\n\tinsteadOf = https://github.com/${WORK_ORG}/"
        fi
        local desired
        desired=$(printf '%b\n' "$work_gitconfig")
        if [ -f "$HOME/.gitconfig-work" ]; then
            local existing
            existing=$(cat "$HOME/.gitconfig-work" 2>/dev/null)
            if [ "$existing" = "$desired" ]; then
                _skip ".gitconfig-work already up to date"
            else
                backup_file "$HOME/.gitconfig-work"
                if [ "$DRY_RUN" = "true" ]; then
                    _info "${DIM}[dry-run]${RST} Would update .gitconfig-work"
                else
                    printf '%s\n' "$desired" > "$HOME/.gitconfig-work"
                    _done "Updated .gitconfig-work (email=$WORK_EMAIL)"
                fi
            fi
        elif [ "$DRY_RUN" = "true" ]; then
            _info "${DIM}[dry-run]${RST} Would write .gitconfig-work"
        else
            printf '%s\n' "$desired" > "$HOME/.gitconfig-work"
            _done "Wrote .gitconfig-work (email=$WORK_EMAIL)"
        fi

        # Create work directory
        if [ ! -d "$WORK_DIR" ]; then
            if [ "$DRY_RUN" = "true" ]; then
                _info "${DIM}[dry-run]${RST} Would create $WORK_DIR"
            else
                mkdir -p "$WORK_DIR"
                _done "Created $WORK_DIR"
            fi
        else
            _skip "$WORK_DIR already exists"
        fi
    fi

    mark_phase_complete 9
    _phase_end
}

# ── Phase 10: SSH Keys ───────────────────────────────────────────
phase_10_ssh_keys() {
    CURRENT_PHASE=10
    if phase_completed 10; then _skip "Phase 10 already completed"; return 0; fi
    _phase "Phase 10 — SSH Keys"

    local ssh_dir="$HOME/.ssh"
    mkdir -p "$ssh_dir"
    chmod 700 "$ssh_dir"

    if [ -f "$ssh_dir/id_ed25519" ]; then
        _done "SSH key already exists (ed25519)"
        # Write SSH config if missing
        if [ ! -f "$ssh_dir/config" ]; then
            write_config '.ssh.config' "$ssh_dir/config"
        fi
        mark_phase_complete 10
        _phase_end; return 0
    fi

    _warn "No SSH key found"
    local reply="n"
    if [ "$AUTO_YES" = "true" ]; then
        _skip "SSH key generation skipped in non-interactive mode"
    else
        printf '  %sGenerate a new ed25519 SSH key (personal)?%s %s[y/N]%s ' "${BOLD}${BWHT}" "$RST" "$DIM" "$RST" >&2
        read -r reply
    fi
    if [ "$reply" = "y" ] || [ "$reply" = "Y" ]; then
        local email
        email=$(inv_get '.git_config.email')
        _act "Generating personal ed25519 key..."
        if [ "$DRY_RUN" != "true" ]; then
            ssh-keygen -t ed25519 -C "${email:-$USER@$(hostname)}" -f "$ssh_dir/id_ed25519" -N ""
            _done "Personal SSH key generated"
            _warn "Add to GitHub: cat ~/.ssh/id_ed25519.pub | pbcopy"
        fi
    else
        _skip "Personal SSH key generation skipped"
    fi

    # Work profile: generate a second SSH key
    if [ "$PROFILE" = "work" ] && [ -n "$WORK_EMAIL" ] && [ -n "$WORK_SSH_HOST" ]; then
        local work_key_name="id_ed25519_work"
        if [ -f "$ssh_dir/$work_key_name" ]; then
            _done "Work SSH key already exists ($work_key_name)"
        else
            local work_reply="n"
            if [ "$AUTO_YES" = "true" ]; then
                _skip "Work SSH key generation skipped in non-interactive mode"
            else
                printf '  %sGenerate a work ed25519 SSH key?%s %s[y/N]%s ' "${BOLD}${BWHT}" "$RST" "$DIM" "$RST" >&2
                read -r work_reply
            fi
            if [ "$work_reply" = "y" ] || [ "$work_reply" = "Y" ]; then
                _act "Generating work ed25519 key..."
                if [ "$DRY_RUN" != "true" ]; then
                    ssh-keygen -t ed25519 -C "$WORK_EMAIL" -f "$ssh_dir/$work_key_name" -N ""
                    _done "Work SSH key generated ($work_key_name)"
                    _warn "Add work key to GitHub: cat ~/.ssh/${work_key_name}.pub | pbcopy"
                fi
            else
                _skip "Work SSH key generation skipped"
            fi
        fi
    fi

    # Write SSH config — use multi-host config if work profile is active
    if [ "$PROFILE" = "work" ] && [ -n "$WORK_SSH_HOST" ]; then
        if [ -f "$ssh_dir/config" ]; then
            if grep -q "$WORK_SSH_HOST" "$ssh_dir/config" 2>/dev/null; then
                _skip "SSH config already has $WORK_SSH_HOST entry"
            else
                # Append work host to existing config
                backup_file "$ssh_dir/config"
                if [ "$DRY_RUN" = "true" ]; then
                    _info "${DIM}[dry-run]${RST} Would append work host to SSH config"
                else
                    local work_key_file="id_ed25519_work"
                    printf '\n# Work GitHub (%s)\nHost %s\n    HostName github.com\n    User git\n    IdentityFile ~/.ssh/%s\n    IdentitiesOnly yes\n' \
                        "${WORK_ORG:-work}" "$WORK_SSH_HOST" "$work_key_file" >> "$ssh_dir/config"
                    _done "Appended $WORK_SSH_HOST to SSH config"
                fi
            fi
        else
            # Write fresh SSH config with both hosts
            if [ "$DRY_RUN" = "true" ]; then
                _info "${DIM}[dry-run]${RST} Would write SSH config with personal + work hosts"
            else
                local work_key_file="id_ed25519_work"
                cat > "$ssh_dir/config" <<SSHEOF
# Personal GitHub
Host github.com
    HostName github.com
    User git
    IdentityFile ~/.ssh/id_ed25519
    IdentitiesOnly yes

# Work GitHub (${WORK_ORG:-work})
Host $WORK_SSH_HOST
    HostName github.com
    User git
    IdentityFile ~/.ssh/$work_key_file
    IdentitiesOnly yes
SSHEOF
                chmod 600 "$ssh_dir/config"
                _done "Wrote SSH config (personal + work hosts)"
            fi
        fi
    else
        write_config '.ssh.config' "$ssh_dir/config"
    fi
    mark_phase_complete 10
    _phase_end
}

# ── Phase 11: Terminal Configs (tmux, zellij) ────────────────────
phase_11_terminal_configs() {
    CURRENT_PHASE=11
    if phase_completed 11; then _skip "Phase 11 already completed"; return 0; fi
    _phase "Phase 11 — Terminal Configs"

    if ! confirm_phase 11 "Terminal Configs (tmux, zellij)"; then _phase_end; return 0; fi

    # tmux plugin manager (TPM)
    if cmd_exists tmux; then
        local tpm_dir="$HOME/.config/tmux/plugins/tpm"
        if [ ! -d "$tpm_dir" ]; then
            _act "Installing TPM (tmux plugin manager)..."
            if [ "$DRY_RUN" != "true" ]; then
                mkdir -p "$(dirname "$tpm_dir")"
                git clone https://github.com/tmux-plugins/tpm "$tpm_dir" >> "$LOG_FILE" 2>&1 || true
            fi
            _done "TPM installed"
        else
            _done "TPM already installed"
        fi

        # Install tmux plugins
        if [ -x "$tpm_dir/bin/install_plugins" ]; then
            _act "Installing tmux plugins..."
            if [ "$DRY_RUN" != "true" ]; then
                "$tpm_dir/bin/install_plugins" >> "$LOG_FILE" 2>&1 || true
            fi
            local plugin_count
            plugin_count=$(inv_count '.shell_configs.tmux_plugins')
            _done "$plugin_count tmux plugins"
        fi
    fi

    # Zellij config is written in Phase 8 with other shell configs
    cmd_exists zellij && _done "Zellij config written in Phase 8"

    mark_phase_complete 11
    _phase_end
}

# ── Phase 12: VS Code / Cursor Extensions ────────────────────────
phase_12_vscode_extensions() {
    CURRENT_PHASE=12
    if phase_completed 12; then _skip "Phase 12 already completed"; return 0; fi
    _phase "Phase 12 — Editor Extensions"

    local editor_cmd=""
    if cmd_exists code; then
        editor_cmd="code"
        _info "VS Code detected"
    elif cmd_exists cursor; then
        editor_cmd="cursor"
        _info "Cursor detected"
    else
        _skip "No VS Code or Cursor CLI found"
        mark_phase_complete 12
        _phase_end; return 0
    fi

    local ext_count
    ext_count=$(inv_count '.vscode.extensions')
    _info "$ext_count extensions from inventory"
    if ! confirm_phase 12 "Editor Extensions ($ext_count)"; then _phase_end; return 0; fi

    if cmd_exists jq; then
        local installed_exts
        installed_exts=$($editor_cmd --list-extensions 2>/dev/null)
        local ext pending=0 failed=0
        for ext in $(jq -r '.vscode.extensions[]' "$INVENTORY_FILE" 2>/dev/null); do
            if echo "$installed_exts" | grep -qix "$ext"; then continue; fi
            pending=$((pending + 1))
            if run_cmd $editor_cmd --install-extension "$ext" --force 2>/dev/null; then
                _done "$ext"
            else
                failed=$((failed + 1))
            fi
        done
        _done "$((pending - failed)) extensions installed ($failed failed)"
    fi
    mark_phase_complete 12
    _phase_end
}

# ── Phase 13: Fonts ──────────────────────────────────────────────
phase_13_fonts() {
    CURRENT_PHASE=13
    if phase_completed 13; then _skip "Phase 13 already completed"; return 0; fi
    _phase "Phase 13 — Developer Fonts"

    # Font casks are already installed in Phase 5.
    # Verify they're present
    local font_count
    font_count=$(inv_count '.developer_fonts.fonts')
    if [ "$font_count" -gt 0 ] 2>/dev/null; then
        _done "$font_count developer fonts available (installed via brew casks)"
    else
        _skip "No developer fonts in inventory"
    fi
    mark_phase_complete 13
    _phase_end
}

# ── Phase 14: AI Coding Agents ───────────────────────────────────
phase_14_ai_agents() {
    CURRENT_PHASE=14
    if phase_completed 14; then _skip "Phase 14 already completed"; return 0; fi
    _phase "Phase 14 — AI Coding Agents"

    if ! confirm_phase 14 "AI Agents (Claude, Codex, Gemini)"; then _phase_end; return 0; fi

    # Claude Code
    if cmd_exists claude; then
        _done "Claude Code already installed"
    else
        _act "Installing Claude Code..."
        if cmd_exists npm; then
            run_cmd npm install -g @anthropic-ai/claude-code || _warn "Claude install failed"
        fi
    fi
    # Claude settings
    if cmd_exists jq; then
        local claude_settings
        claude_settings=$(inv_content '.claude_code.settings')
        if [ -n "$claude_settings" ] && [ "$claude_settings" != "null" ]; then
            write_config '.claude_code.settings' "$HOME/.claude/settings.json"
        fi
    fi

    # Codex (personal profile only)
    if [ "$PROFILE" = "personal" ]; then
        if cmd_exists codex; then
            _done "Codex already installed"
        else
            _info "Install Codex via: brew install --cask codex"
        fi
        if cmd_exists jq; then
            local codex_config
            codex_config=$(inv_content '.codex.config')
            if [ -n "$codex_config" ] && [ "$codex_config" != "null" ]; then
                write_config '.codex.config' "$HOME/.codex/config.toml"
            fi
            write_config '.codex.agents_md' "$HOME/.codex/AGENTS.md"
        fi
    fi

    # Gemini CLI (personal profile only)
    if [ "$PROFILE" = "personal" ]; then
        if cmd_exists gemini; then
            _done "Gemini CLI already installed"
        else
            _info "Gemini CLI is installed via Volta (Phase 7)"
        fi
        if cmd_exists jq; then
            write_config '.gemini.settings' "$HOME/.gemini/settings.json"
            write_config '.gemini.gemini_md' "$HOME/.gemini/GEMINI.md"
        fi
    fi

    mark_phase_complete 14
    _phase_end
}

# ── Phase 15: Docker Configuration ───────────────────────────────
phase_15_docker_config() {
    CURRENT_PHASE=15
    if phase_completed 15; then _skip "Phase 15 already completed"; return 0; fi
    _phase "Phase 15 — Docker Configuration"

    if ! cmd_exists docker; then
        _skip "Docker not installed — install Docker Desktop from brew cask"
        mark_phase_complete 15
        _phase_end; return 0
    fi

    if ! confirm_phase 15 "Docker Config"; then _phase_end; return 0; fi

    write_config '.docker.daemon_config' "$HOME/.docker/daemon.json"
    _done "Docker daemon config written"
    mark_phase_complete 15
    _phase_end
}

# ── Phase 16: LaunchAgents ───────────────────────────────────────
phase_16_launch_agents() {
    CURRENT_PHASE=16
    if phase_completed 16; then _skip "Phase 16 already completed"; return 0; fi
    _phase "Phase 16 — LaunchAgents"

    local agent_count
    agent_count=$(inv_count '.launch_agents.agents')
    _info "$agent_count LaunchAgents in inventory"

    if cmd_exists jq; then
        local agent
        while IFS= read -r agent; do
            [ -z "$agent" ] && continue
            if [ -f "$HOME/Library/LaunchAgents/$agent.plist" ]; then
                _done "$agent (present)"
            else
                _warn "$agent (missing — may need manual setup)"
            fi
        done < <(jq -r '.launch_agents.agents[]' "$INVENTORY_FILE" 2>/dev/null)
    fi
    _info "LaunchAgents are app-specific; they'll be recreated when apps are opened"
    mark_phase_complete 16
    _phase_end
}

# ── Phase 17: macOS Defaults ─────────────────────────────────────
phase_17_macos_defaults() {
    CURRENT_PHASE=17
    if phase_completed 17; then _skip "Phase 17 already completed"; return 0; fi
    _phase "Phase 17 — macOS Defaults"

    if ! confirm_phase 17 "macOS Defaults (Dock, Keyboard, Finder)"; then _phase_end; return 0; fi

    if cmd_exists jq; then
        local dock_hide dock_size
        dock_hide=$(jq -r '.macos_defaults.dock.autohide' "$INVENTORY_FILE" 2>/dev/null)
        dock_size=$(jq -r '.macos_defaults.dock.tilesize' "$INVENTORY_FILE" 2>/dev/null)

        if [ -n "$dock_hide" ] && [ "$dock_hide" != "null" ]; then
            local current_hide
            current_hide=$(defaults read com.apple.dock autohide 2>/dev/null || echo "")
            if [ "$current_hide" != "$dock_hide" ]; then
                _act "Setting Dock autohide=$dock_hide"
                run_cmd defaults write com.apple.dock autohide -bool "$dock_hide"
            fi
        fi

        if [ -n "$dock_size" ] && [ "$dock_size" != "null" ]; then
            _act "Setting Dock tilesize=$dock_size"
            run_cmd defaults write com.apple.dock tilesize -int "$dock_size"
        fi

        # Keyboard
        local key_repeat
        key_repeat=$(jq -r '.macos_defaults.keyboard.key_repeat' "$INVENTORY_FILE" 2>/dev/null)
        if [ -n "$key_repeat" ] && [ "$key_repeat" != "null" ] && [ "$key_repeat" != "default" ]; then
            _act "Setting KeyRepeat=$key_repeat"
            run_cmd defaults write NSGlobalDomain KeyRepeat -int "$key_repeat"
        fi

        local initial_repeat
        initial_repeat=$(jq -r '.macos_defaults.keyboard.initial_key_repeat' "$INVENTORY_FILE" 2>/dev/null)
        if [ -n "$initial_repeat" ] && [ "$initial_repeat" != "null" ] && [ "$initial_repeat" != "default" ]; then
            _act "Setting InitialKeyRepeat=$initial_repeat"
            run_cmd defaults write NSGlobalDomain InitialKeyRepeat -int "$initial_repeat"
        fi

        # Finder
        local show_ext
        show_ext=$(jq -r '.macos_defaults.finder.show_extensions' "$INVENTORY_FILE" 2>/dev/null)
        if [ -n "$show_ext" ] && [ "$show_ext" != "null" ] && [ "$show_ext" != "default" ]; then
            _act "Setting AppleShowAllExtensions=$show_ext"
            run_cmd defaults write NSGlobalDomain AppleShowAllExtensions -bool "$show_ext"
        fi

        _act "Restarting Dock and Finder to apply..."
        if [ "$DRY_RUN" != "true" ]; then
            killall Dock 2>/dev/null || true
            killall Finder 2>/dev/null || true
        fi
    fi

    _done "macOS defaults applied"
    mark_phase_complete 17
    _phase_end
}

# ══════════════════════════════════════════════════════════════════
# MAIN
# ══════════════════════════════════════════════════════════════════

show_help() {
    cat >&2 <<HELP
${BOLD}प्रतिष्ठापना (Pratisthāpana)${RST} v${SMGR_VERSION} — macOS Dev Environment Setup

${BOLD}USAGE:${RST}
  $(basename "$0") [OPTIONS]

${BOLD}OPTIONS:${RST}
  --yes, -y               Non-interactive (auto-confirm all phases)
  --dry-run, -n           Show what would be done, change nothing
  --inventory PATH        Path to inventory JSON (default: auto-detect)
  --phase N               Start from phase N (resume after failure)
  --profile personal|work Tool profile (default: personal)
  --work-email EMAIL      Work Git email (prompted if --profile work)
  --work-org ORG          Work GitHub org for SSH/URL routing
  --work-dir DIR          Work repo directory (default: ~/work/src)
  --work-ssh-host HOST    SSH host alias (default: github.com-work)
  --reset                 Clear state, re-run all phases
  --help, -h              Show this help
  --version               Show version

${BOLD}PHASES:${RST}
   1  Xcode Command Line Tools
   2  Homebrew
   3  Core formulae (git, jq, bash)
   4  Set brew bash as default shell
   5  Brew formulae + casks + taps
   6  Language runtimes (Rust, Volta/Node, Bun, SDKMAN)
   7  Language tools (cargo, volta, uv installs)
   8  Shell configs (bashrc, starship, atuin, zoxide)
   9  Git configuration
  10  SSH key generation
  11  Terminal configs (tmux + plugins, zellij)
  12  VS Code / Cursor extensions
  13  Fonts
  14  AI coding agents (Claude, Codex, Gemini)
  15  Docker configuration
  16  LaunchAgents
  17  macOS defaults

${BOLD}EXAMPLES:${RST}
  $(basename "$0")                                          # interactive personal setup
  $(basename "$0") --profile work --work-email me@co.com    # work Mac (prompts for org/dir)
  $(basename "$0") --profile work --work-email me@co.com \\
    --work-org acme --work-dir ~/work/src                    # work Mac, fully specified
  $(basename "$0") --phase 8                                 # resume from shell configs
  $(basename "$0") --dry-run                                 # preview all changes
HELP
}

show_banner() {
    local t1_plain="  macOS Dev Environment Setup  v${SMGR_VERSION}"
    local t1_styled="  ${BOLD}${BWHT}macOS Dev Environment Setup${RST}  ${BOLD}v${SMGR_VERSION}${RST}"

    printf '\n' >&2
    _box_rule "$CYN" '╭' '╮'
    _box_line "$CYN" "${#t1_plain}" "$t1_styled"
    _box_rule "$CYN" '╰' '╯'
    printf '\n' >&2

    _info "Profile:   ${BOLD}$PROFILE${RST}"
    _info "Inventory: ${UL}$INVENTORY_FILE${RST}"
    _info "Mode:      $([ "$AUTO_YES" = "true" ] && echo "non-interactive" || echo "interactive")\
$([ "$DRY_RUN" = "true" ] && echo " ${BYEL}(dry-run)${RST}" || echo "")"
    _info "Log:       ${DIM}$LOG_FILE${RST}"
    _info "State:     ${DIM}$STATE_DIR${RST}"
    if [ "$PROFILE" = "work" ] && [ -n "$WORK_EMAIL" ]; then
        _info "Work:      ${BOLD}$WORK_EMAIL${RST} → ${DIM}${WORK_DIR:-~/work/src}${RST}"
    fi

    # Phase progress
    local completed=0
    if [ -f "$COMPLETED_FILE" ]; then
        completed=$(wc -l < "$COMPLETED_FILE" | tr -d ' ')
    fi
    if [ "$completed" -gt 0 ]; then
        _info "Progress:  ${BGRN}$completed/$TOTAL_PHASES phases completed${RST}"
    fi
    printf '\n' >&2
}

show_completion() {
    local s1_plain="  ✔  Setup complete!"
    local s1_styled="  ${BGRN}✔${RST}  ${BOLD}Setup complete!${RST}"
    local s2_plain="     Open a new terminal to begin"
    local s2_styled="     Open a new terminal to begin"

    printf '\n' >&2
    _box_rule "$BGRN" '╭' '╮'
    _box_line "$BGRN" "${#s1_plain}" "$s1_styled"
    _box_line "$BGRN" "${#s2_plain}" "$s2_styled"
    _box_rule "$BGRN" '╰' '╯'
    printf '\n' >&2

    _wal OK "=== Setup complete ==="

    # Log path uses ANSI styling — print directly to avoid logging escapes
    printf "  ${DIM}${CYN}│${RST}  ${CYN}▸${RST} Log: ${UL}%s${RST}\n" "$LOG_FILE" >&2
    printf "  ${DIM}${CYN}│${RST}  ${CYN}▸${RST} Backups: ${UL}%s${RST}\n" "$BACKUP_DIR" >&2
    _info "Re-run any phase: $(basename "$0") --phase N"
    printf '\n' >&2
}

run_phases() {
    # Collect work profile config before starting phases
    collect_work_config

    local phase_funcs="
        phase_01_xcode_clt
        phase_02_homebrew
        phase_03_core_formulae
        phase_04_default_shell
        phase_05_brew_packages
        phase_06_language_runtimes
        phase_07_language_tools
        phase_08_shell_configs
        phase_09_git_config
        phase_10_ssh_keys
        phase_11_terminal_configs
        phase_12_vscode_extensions
        phase_13_fonts
        phase_14_ai_agents
        phase_15_docker_config
        phase_16_launch_agents
        phase_17_macos_defaults
    "

    local phase_num=0
    local critical_failure="false"
    for func in $phase_funcs; do
        phase_num=$((phase_num + 1))
        if [ "$phase_num" -lt "$START_PHASE" ]; then continue; fi
        if ! $func; then
            # Phases 1-5 are critical prerequisites — abort on failure
            # (Phase 5 installs all brew packages that later phases depend on)
            if [ "$phase_num" -le 5 ]; then
                _err "Critical phase $phase_num failed. Fix the issue and resume with: saamagri.sh --phase $phase_num"
                critical_failure="true"
                break
            else
                _warn "Phase $phase_num had errors. Continuing with remaining phases."
            fi
        fi
    done

    if [ "$critical_failure" = "true" ]; then
        printf '\n' >&2
        local f1_plain="  ✘  Setup incomplete (failed at phase $phase_num)"
        local f1_styled="  ${RED}✘${RST}  ${BOLD}Setup incomplete (failed at phase $phase_num)${RST}"
        local f2_plain="     Resume: saamagri.sh --phase $phase_num"
        local f2_styled="     ${DIM}Resume: saamagri.sh --phase $phase_num${RST}"
        _box_rule "$RED" '╭' '╮'
        _box_line "$RED" "${#f1_plain}" "$f1_styled"
        _box_line "$RED" "${#f2_plain}" "$f2_styled"
        _box_rule "$RED" '╰' '╯'
        printf '\n' >&2
        return 1
    fi

    show_completion
}

main() {
    # Parse arguments (bash 3.2 compatible — no associative arrays)
    local next_is=""
    for arg in "$@"; do
        if [ -n "$next_is" ]; then
            case "$next_is" in
                inventory)      INVENTORY_FILE="$arg" ;;
                phase)          START_PHASE="$arg" ;;
                profile)        PROFILE="$arg" ;;
                work-email)     WORK_EMAIL="$arg" ;;
                work-org)       WORK_ORG="$arg" ;;
                work-dir)       WORK_DIR="$arg" ;;
                work-ssh-host)  WORK_SSH_HOST="$arg" ;;
            esac
            next_is=""
            continue
        fi
        case "$arg" in
            --yes|-y)        AUTO_YES="true" ;;
            --dry-run|-n)    DRY_RUN="true" ;;
            --inventory)     next_is="inventory" ;;
            --inventory=*)   INVENTORY_FILE="${arg#*=}" ;;
            --phase)         next_is="phase" ;;
            --phase=*)       START_PHASE="${arg#*=}" ;;
            --profile)       next_is="profile" ;;
            --profile=*)     PROFILE="${arg#*=}" ;;
            --work-email)    next_is="work-email" ;;
            --work-email=*)  WORK_EMAIL="${arg#*=}" ;;
            --work-org)      next_is="work-org" ;;
            --work-org=*)    WORK_ORG="${arg#*=}" ;;
            --work-dir)      next_is="work-dir" ;;
            --work-dir=*)    WORK_DIR="${arg#*=}" ;;
            --work-ssh-host) next_is="work-ssh-host" ;;
            --work-ssh-host=*) WORK_SSH_HOST="${arg#*=}" ;;
            --reset)
                rm -f "$COMPLETED_FILE"
                echo "State reset — all phases will re-run." >&2
                exit 0 ;;
            --help|-h)       show_help; exit 0 ;;
            --version)       echo "saamagri v$SMGR_VERSION"; exit 0 ;;
            *)               echo "Unknown option: $arg" >&2; show_help; exit 2 ;;
        esac
    done

    # Environment variable overrides
    [ "${SAAMAGRI_YES:-}" = "true" ] && AUTO_YES="true"
    [ "${SAAMAGRI_DRY_RUN:-}" = "true" ] && DRY_RUN="true"
    [ -n "${SAAMAGRI_PROFILE:-}" ] && PROFILE="$SAAMAGRI_PROFILE"

    # Bootstrap PATH for tools installed in prior phases (critical for --phase N resume)
    _bootstrap_path

    # Auto-detect inventory file — prefer v2+ (has git_config, ssh, etc.)
    if [ -z "$INVENTORY_FILE" ]; then
        local candidate=""
        local candidates=""
        # Collect all possible inventory files (newest first)
        candidates=$(ls -t "$HOME"/tool-inventory-*.json /tmp/inventory-v2.json "$HOME/tool-inventory-latest.json" 2>/dev/null || true)
        for candidate in $candidates; do
            [ -f "$candidate" ] || continue
            # Check for v2+ schema: must have git_config section
            if cmd_exists jq; then
                if jq -e '.git_config' "$candidate" >/dev/null 2>&1; then
                    INVENTORY_FILE="$candidate"
                    break
                fi
            elif cmd_exists python3; then
                if python3 -c "import json; d=json.load(open('$candidate')); assert 'git_config' in d" 2>/dev/null; then
                    INVENTORY_FILE="$candidate"
                    break
                fi
            else
                # No jq or python3 — just take the newest
                INVENTORY_FILE="$candidate"
                break
            fi
        done
        # Fallback: take whatever is available even if v1
        if [ -z "$INVENTORY_FILE" ]; then
            for candidate in $candidates; do
                [ -f "$candidate" ] || continue
                INVENTORY_FILE="$candidate"
                break
            done
        fi
        if [ -z "$INVENTORY_FILE" ]; then
            echo "Error: No inventory JSON found." >&2
            echo "Run mac-inventory.sh first, or pass --inventory path/to/file.json" >&2
            exit 1
        fi
    fi

    if [ ! -f "$INVENTORY_FILE" ]; then
        echo "Error: Inventory file not found: $INVENTORY_FILE" >&2
        exit 1
    fi

    # Validate profile
    case "$PROFILE" in
        personal|work) ;;
        *) echo "Error: Unknown profile '$PROFILE'. Use 'personal' or 'work'." >&2; exit 2 ;;
    esac

    # Initialize logging
    mkdir -p "$LOG_DIR" "$STATE_DIR"
    LOG_FILE="$LOG_DIR/saamagri-$(date +%Y%m%d-%H%M%S).log"
    touch "$LOG_FILE"
    _wal "START" "v$SMGR_VERSION profile=$PROFILE inventory=$INVENTORY_FILE dry_run=$DRY_RUN"

    show_banner
    run_phases
}

main "$@"
