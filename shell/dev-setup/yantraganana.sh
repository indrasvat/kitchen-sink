#!/usr/bin/env bash
# ╭──────────────────────────────────────────────────────────────╮
# │  Yantragaṇanā — macOS Tool Inventory Report                 │
# │  Scans all package managers, configs & known paths → JSON    │
# │  Designed for AI coding agents to reconstruct a dev env      │
# ╰──────────────────────────────────────────────────────────────╯
# shellcheck disable=SC2016  # jq expressions use $var in single quotes intentionally
set -euo pipefail

readonly VERSION="3.0.0"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
readonly TIMESTAMP
HOSTNAME_SHORT=$(hostname -s)
readonly HOSTNAME_SHORT
readonly OUTPUT_FILE="${1:-$HOME/tool-inventory-$(date +%Y%m%d-%H%M%S).json}"

# ── Log file ───────────────────────────────────────────────────
readonly LOG_DIR="${HOME}/.local/state/yantraganana"
mkdir -p "$LOG_DIR"
LOG_FILE="${LOG_DIR}/yantraganana-$(date +%Y%m%d-%H%M%S).log"
readonly LOG_FILE

# ── Temp directory for JSON fragments ─────────────────────────
TMPDIR_FRAGS=$(mktemp -d)
readonly TMPDIR_FRAGS
cleanup_tmpdir() { rm -r "$TMPDIR_FRAGS"; }
trap cleanup_tmpdir EXIT

# ── Colors ───────────────────────────────────────────────────────
readonly RST=$'\033[0m'
readonly DIM=$'\033[2m'
readonly BOLD=$'\033[1m'
readonly UL=$'\033[4m'

readonly RED=$'\033[31m'
# shellcheck disable=SC2034
readonly GRN=$'\033[32m'
readonly YEL=$'\033[33m'
readonly CYN=$'\033[36m'

readonly BGRN=$'\033[92m'
readonly BWHT=$'\033[97m'
readonly BYEL=$'\033[93m'

# ── Layout constants ─────────────────────────────────────────────
readonly LINE_W=62
readonly RULE='───────────────────────────────────────────────────────────'
readonly BW=42  # inner width for framed boxes

# ── Logging ──────────────────────────────────────────────────────
_log() {
    local level="$1"; shift
    printf '%s [%-5s] %s\n' "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" "$level" "$*" >> "$LOG_FILE"
}

_info()  { _log INFO  "$*"; printf "  ${DIM}${CYN}│${RST}  ${CYN}▸${RST} %s\n" "$*" >&2; }
_done()  { _log OK    "$*"; printf "  ${DIM}${CYN}│${RST}  ${BGRN}✔${RST} %s\n" "$*" >&2; }
_warn()  { _log WARN  "$*"; printf "  ${DIM}${CYN}│${RST}  ${BYEL}⚠${RST}  ${YEL}%s${RST}\n" "$*" >&2; }
_skip()  { _log SKIP  "$*"; printf "  ${DIM}${CYN}│${RST}  ${DIM}○ %s${RST}\n" "$*" >&2; }
_error() { _log ERROR "$*"; printf "  ${DIM}${CYN}│${RST}  ${RED}✘${RST}  ${RED}%s${RST}\n" "$*" >&2; }

_phase() {
    _log PHASE "=== $1 ==="
    local label="$1"
    local used=$(( 2 + 5 + ${#label} + 1 ))
    local pad_len=$(( LINE_W - used ))
    (( pad_len < 1 )) && pad_len=1
    local pad
    pad=$(printf '%*s' "$pad_len" '' | tr ' ' '─')
    printf "\n  ${BOLD}${CYN}┌─── %s ${DIM}%s${RST}\n" "$label" "$pad" >&2
}

_phase_end() {
    printf "  ${DIM}${CYN}└%s${RST}\n" "$RULE" >&2
}

_box_rule() {
    local color="$1" top="$2" bottom="$3"
    local dashes
    dashes=$(printf '%*s' "$BW" '' | tr ' ' '─')
    printf "  ${BOLD}%s%s%s%s${RST}\n" "$color" "$top" "$dashes" "$bottom" >&2
}

_box_line() {
    local color="$1" plain_len="$2" content="$3"
    local pad_len=$(( BW - plain_len ))
    (( pad_len < 0 )) && pad_len=0
    local pad
    pad=$(printf '%*s' "$pad_len" '')
    printf "  ${BOLD}%s│${RST}%s%s${BOLD}%s│${RST}\n" "$color" "$content" "$pad" "$color" >&2
}

# ── Helpers ──────────────────────────────────────────────────────
cmd_exists() { command -v "$1" &>/dev/null; }
sgrep() { grep "$@" || true; }

get_version() {
    _timeout_run 10 "$@" 2>&1 | head -1 | sgrep -oE '[0-9]+\.[0-9]+[.0-9]*' | head -1
}

# Run a command with a timeout (seconds). Stdout captured; returns empty on timeout.
# Uses perl alarm() — always available on macOS, no GNU coreutils needed.
_timeout_run() {
    local secs="$1"; shift
    perl -e '
        use POSIX ":sys_wait_h";
        $SIG{ALRM} = sub { kill("TERM", $pid) if $pid; exit 1 };
        alarm('"$secs"');
        $pid = open(my $fh, "-|", @ARGV) or exit 1;
        while (<$fh>) { print }
        close $fh;
        alarm(0);
    ' -- "$@" || true
}

# Read a file as a JSON string (max 50KB), or null if missing
_jq_file() {
    if [[ -f "$1" ]]; then
        head -c 51200 "$1" 2>/dev/null | jq -Rs '.' 2>/dev/null || echo 'null'
    else
        echo 'null'
    fi
}

# Emit a fragment file. Usage: _emit 01-system <jq expression>
# Each collector calls this to write its JSON fragment.
_emit() {
    local name="$1"; shift
    "$@" > "$TMPDIR_FRAGS/${name}.json"
}

human_size() {
    local bytes=$1
    if (( bytes >= 1073741824 )); then
        awk "BEGIN { printf \"%.1f GiB\", $bytes/1073741824 }"
    elif (( bytes >= 1048576 )); then
        awk "BEGIN { printf \"%.1f MiB\", $bytes/1048576 }"
    elif (( bytes >= 1024 )); then
        awk "BEGIN { printf \"%.1f KiB\", $bytes/1024 }"
    else
        printf '%d B' "$bytes"
    fi
}

# ── System info ──────────────────────────────────────────────────
collect_system_info() {
    _phase "System Info"
    local product_name product_version build_version arch chip memory serial

    product_name=$(sw_vers -productName 2>/dev/null || echo "unknown")
    product_version=$(sw_vers -productVersion 2>/dev/null || echo "unknown")
    build_version=$(sw_vers -buildVersion 2>/dev/null || echo "unknown")
    arch=$(uname -m 2>/dev/null || echo "unknown")
    chip=$(sysctl -n machdep.cpu.brand_string 2>/dev/null || echo "unknown")
    memory=$(sysctl -n hw.memsize 2>/dev/null | awk '{printf "%.0f GB", $1/1073741824}' || echo "unknown")
    serial=$(system_profiler SPHardwareDataType 2>/dev/null | awk -F': ' '/Serial Number/{print $2}' || echo "unknown")

    _done "$product_name $product_version ($build_version) · $arch"
    _info "Chip: $chip · RAM: $memory"
    _phase_end

    _emit 01-system jq -n \
        --arg hostname "$HOSTNAME_SHORT" \
        --arg os "$product_name" \
        --arg version "$product_version" \
        --arg build "$build_version" \
        --arg arch "$arch" \
        --arg chip "$chip" \
        --arg memory "$memory" \
        --arg serial "$serial" \
        '{system: {hostname: $hostname, os: $os, version: $version,
                   build: $build, arch: $arch, chip: $chip,
                   memory: $memory, serial: $serial}}'
}

# ── Homebrew ─────────────────────────────────────────────────────
collect_brew() {
    _phase "Homebrew"
    if ! cmd_exists brew; then
        _skip "brew not found, skipping"
        _phase_end
        _emit 02-brew jq -n '{homebrew: {installed: false}}'
        return
    fi

    local brew_version brew_prefix
    brew_version=$(brew --version 2>/dev/null | head -1)
    brew_prefix=$(brew --prefix 2>/dev/null)
    _info "$brew_version at $brew_prefix"

    # Formulae — one pipeline, no per-item jq
    local formulae_json
    formulae_json=$(brew list --formula --versions 2>/dev/null \
        | awk '{print $1 "\t" $2}' \
        | jq -R 'split("\t") | {name: .[0], version: (.[1] // "unknown")}' \
        | jq -s '.')
    local formulae_count
    formulae_count=$(echo "$formulae_json" | jq 'length')
    _done "$formulae_count formulae"

    # Casks — read version dirs from Caskroom, exclude .metadata
    local caskroom
    caskroom="$(brew --prefix 2>/dev/null)/Caskroom"
    local casks_json
    casks_json=$(brew list --cask 2>/dev/null | while IFS= read -r cask_name; do
        [[ -z "$cask_name" ]] && continue
        local cask_ver="unknown"
        if [[ -d "$caskroom/$cask_name" ]]; then
            cask_ver=$(find "$caskroom/$cask_name" -maxdepth 1 -mindepth 1 -type d -not -name '.metadata' 2>/dev/null | head -1 | xargs basename 2>/dev/null)
            [[ -z "$cask_ver" ]] && cask_ver="unknown"
        fi
        printf '%s\t%s\n' "$cask_name" "$cask_ver"
    done | jq -R 'split("\t") | {name: .[0], version: (.[1] // "unknown")}' | jq -s '.')
    [[ -z "$casks_json" ]] && casks_json="[]"
    local cask_count
    cask_count=$(echo "$casks_json" | jq 'length')
    _done "$cask_count casks"

    # Taps
    local taps_json
    taps_json=$(brew tap 2>/dev/null | jq -R '.' | jq -s '.')
    local tap_count
    tap_count=$(echo "$taps_json" | jq 'length')
    _done "$tap_count taps"

    _phase_end

    _emit 02-brew jq -n \
        --arg version "$brew_version" \
        --arg prefix "$brew_prefix" \
        --argjson taps "$taps_json" \
        --argjson formulae "$formulae_json" \
        --argjson casks "$casks_json" \
        '{homebrew: {installed: true, version: $version, prefix: $prefix,
                     taps: $taps,
                     formulae_count: ($formulae | length), formulae: $formulae,
                     casks_count: ($casks | length), casks: $casks}}'
}

# ── Node.js / npm / Volta ────────────────────────────────────────
collect_node() {
    _phase "Node.js Ecosystem"

    local node_version="not installed" npm_version="not installed"
    local npx_version="not installed" volta_version="not installed"
    local pnpm_version="not installed" yarn_version="not installed"
    local bun_version="not installed" manager="none"

    cmd_exists volta && { volta_version=$(volta --version 2>/dev/null || echo "error"); manager="volta"; }
    cmd_exists node && node_version=$(node --version 2>/dev/null || echo "error")
    cmd_exists npm && npm_version=$(npm --version 2>/dev/null || echo "error")
    cmd_exists npx && npx_version=$(npx --version 2>/dev/null || echo "error")
    cmd_exists pnpm && pnpm_version=$(pnpm --version 2>/dev/null || echo "error")
    cmd_exists yarn && yarn_version=$(yarn --version 2>/dev/null || echo "error")
    cmd_exists bun && bun_version=$(bun --version 2>/dev/null || echo "error")

    [[ "$manager" == "none" ]] && cmd_exists fnm && manager="fnm"
    [[ "$manager" == "none" ]] && cmd_exists nvm && manager="nvm"
    [[ "$manager" == "none" ]] && [[ "$node_version" != "not installed" ]] && manager="system"

    _info "node=$node_version  npm=$npm_version  manager=$manager"

    # Global npm packages
    local npm_globals_json="[]"
    if cmd_exists npm; then
        npm_globals_json=$(npm list -g --depth=0 --parseable 2>/dev/null \
            | tail -n +2 | xargs -I{} basename {} | sort \
            | jq -R '{name: .}' | jq -s '.' 2>/dev/null) || npm_globals_json="[]"
        [[ -z "$npm_globals_json" || "$npm_globals_json" == "null" ]] && npm_globals_json="[]"
    fi
    local npm_global_count
    npm_global_count=$(echo "$npm_globals_json" | jq 'length')
    _done "$npm_global_count global npm packages"

    # Volta-managed tools
    local volta_tools_json="[]"
    if cmd_exists volta; then
        volta_tools_json=$(volta list all 2>/dev/null | while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            local kind name_ver name ver is_default
            kind=$(echo "$line" | awk '{print $1}')
            name_ver=$(echo "$line" | awk '{print $2}')
            ver="${name_ver##*@}"
            name="${name_ver%@*}"
            is_default="false"
            [[ "$line" == *"(default)"* ]] && is_default="true"
            printf '%s\t%s\t%s\t%s\n' "$kind" "$name" "$ver" "$is_default"
        done | jq -R 'split("\t") | {kind: .[0], name: .[1], version: .[2]} + (if .[3] == "true" then {"default": true} else {} end)' \
             | jq -s '.' 2>/dev/null) || volta_tools_json="[]"
        [[ -z "$volta_tools_json" || "$volta_tools_json" == "null" ]] && volta_tools_json="[]"
        local volta_tool_count
        volta_tool_count=$(echo "$volta_tools_json" | jq 'length')
        _done "$volta_tool_count volta-managed tools"
    fi

    _phase_end

    _emit 03-node jq -n \
        --arg manager "$manager" \
        --arg volta_version "$volta_version" \
        --arg node_version "$node_version" \
        --arg npm_version "$npm_version" \
        --arg npx_version "$npx_version" \
        --arg pnpm_version "$pnpm_version" \
        --arg yarn_version "$yarn_version" \
        --arg bun_version "$bun_version" \
        --argjson npm_globals "$npm_globals_json" \
        --argjson volta_tools "$volta_tools_json" \
        '{node_ecosystem: {
            version_manager: $manager,
            volta_version: $volta_version,
            node_version: $node_version,
            npm_version: $npm_version,
            npx_version: $npx_version,
            pnpm_version: $pnpm_version,
            yarn_version: $yarn_version,
            bun_version: $bun_version,
            npm_global_count: ($npm_globals | length),
            npm_globals: $npm_globals,
            volta_tool_count: ($volta_tools | length),
            volta_tools: $volta_tools}}'
}

# ── Go ───────────────────────────────────────────────────────────
collect_go() {
    _phase "Go"
    if ! cmd_exists go; then
        _skip "go not found, skipping"; _phase_end
        _emit 04-go jq -n '{go: {installed: false}}'
        return
    fi

    local go_version gopath gobin
    go_version=$(go version 2>/dev/null | awk '{print $3}')
    gopath=$(go env GOPATH 2>/dev/null || echo "$HOME/go")
    gobin="${GOBIN:-$gopath/bin}"
    _info "$go_version  GOPATH=$gopath"

    local bins_json="[]"
    if [[ -d "$gobin" ]]; then
        bins_json=$(find "$gobin" -maxdepth 1 -type f -perm +111 -exec basename {} \; 2>/dev/null \
            | sort | jq -R '{name: .}' | jq -s '.')
    fi
    local bin_count
    bin_count=$(echo "$bins_json" | jq 'length')
    _done "$bin_count binaries in GOBIN"
    _phase_end

    _emit 04-go jq -n \
        --arg version "$go_version" \
        --arg gopath "$gopath" \
        --arg gobin "$gobin" \
        --argjson binaries "$bins_json" \
        '{go: {installed: true, version: $version, gopath: $gopath,
               gobin: $gobin, binaries_count: ($binaries | length),
               binaries: $binaries}}'
}

# ── Rust / Cargo ─────────────────────────────────────────────────
collect_rust() {
    _phase "Rust / Cargo"
    if ! cmd_exists rustc; then
        _skip "rustc not found, skipping"; _phase_end
        _emit 05-rust jq -n '{rust: {installed: false}}'
        return
    fi

    local rust_version cargo_version rustup_version
    rust_version=$(rustc --version 2>/dev/null | awk '{print $2}')
    cargo_version=$(cargo --version 2>/dev/null | awk '{print $2}')
    rustup_version=$(rustup --version 2>/dev/null | head -1 | awk '{print $2}' || echo "not installed")
    _info "rustc=$rust_version  cargo=$cargo_version"

    local cargo_home="${CARGO_HOME:-$HOME/.cargo}"
    local skip_bins="rustc|cargo|rustup|rustfmt|rust-gdb|rust-lldb|clippy-driver|cargo-fmt|rust-gdbgui|rustdoc"
    local cargo_bins_json="[]"
    if [[ -d "$cargo_home/bin" ]]; then
        cargo_bins_json=$(find "$cargo_home/bin" -maxdepth 1 -type f -perm +111 -exec basename {} \; 2>/dev/null \
            | sort | sgrep -vE "^($skip_bins)$" \
            | jq -R '{name: .}' | jq -s '.')
    fi
    local cargo_bin_count
    cargo_bin_count=$(echo "$cargo_bins_json" | jq 'length')
    _done "$cargo_bin_count cargo-installed binaries"

    local toolchains_json="[]"
    if cmd_exists rustup; then
        toolchains_json=$(rustup toolchain list 2>/dev/null | jq -R '.' | jq -s '.')
        local tc_count
        tc_count=$(echo "$toolchains_json" | jq 'length')
        _done "$tc_count toolchains"
    fi
    _phase_end

    _emit 05-rust jq -n \
        --arg rustc_version "$rust_version" \
        --arg cargo_version "$cargo_version" \
        --arg rustup_version "$rustup_version" \
        --arg cargo_home "$cargo_home" \
        --argjson toolchains "$toolchains_json" \
        --argjson cargo_binaries "$cargo_bins_json" \
        '{rust: {installed: true, rustc_version: $rustc_version,
                 cargo_version: $cargo_version, rustup_version: $rustup_version,
                 cargo_home: $cargo_home, toolchains: $toolchains,
                 cargo_binaries_count: ($cargo_binaries | length),
                 cargo_binaries: $cargo_binaries}}'
}

# ── Python / pipx / uv ──────────────────────────────────────────
collect_python() {
    _phase "Python Ecosystem"
    local python_version="not installed" python3_path="not found"
    local pip_version="not installed" pipx_version="not installed"
    local uv_version="not installed" pyenv_version="not installed"
    local conda_version="not installed"

    cmd_exists python3 && { python_version=$(python3 --version 2>/dev/null | awk '{print $2}'); python3_path=$(which python3); }
    cmd_exists pip3 && pip_version=$(pip3 --version 2>/dev/null | awk '{print $2}')
    cmd_exists pipx && pipx_version=$(pipx --version 2>/dev/null)
    cmd_exists uv && uv_version=$(uv --version 2>/dev/null | awk '{print $2}')
    cmd_exists pyenv && pyenv_version=$(pyenv --version 2>/dev/null | awk '{print $2}')
    cmd_exists conda && conda_version=$(conda --version 2>/dev/null | awk '{print $2}')
    _info "python=$python_version  uv=$uv_version  pipx=$pipx_version"

    local pipx_json="[]"
    if cmd_exists pipx; then
        pipx_json=$(pipx list --short 2>/dev/null \
            | awk '{print $1}' \
            | while read -r pkg; do
                [[ -z "$pkg" || "$pkg" == "venvs" || "$pkg" == "package" ]] && continue
                printf '%s\n' "$pkg"
            done \
            | jq -R '{name: .}' | jq -s '.' 2>/dev/null) || pipx_json="[]"
        [[ -z "$pipx_json" || "$pipx_json" == "null" ]] && pipx_json="[]"
    fi
    local pipx_count
    pipx_count=$(echo "$pipx_json" | jq 'length')
    _done "$pipx_count pipx packages"

    local uv_tools_json="[]"
    if cmd_exists uv; then
        uv_tools_json=$(uv tool list 2>/dev/null \
            | while IFS= read -r line; do
                [[ -z "$line" || "$line" == *"No tools"* || "$line" == "- "* ]] && continue
                local tool ver
                tool=$(echo "$line" | awk '{print $1}')
                ver=$(echo "$line" | sgrep -oE 'v[0-9]+\.[0-9]+[.0-9]*' | head -1)
                [[ -z "$tool" ]] && continue
                printf '%s\t%s\n' "$tool" "${ver:-unknown}"
            done \
            | jq -R 'split("\t") | {name: .[0], version: (.[1] // "unknown")}' | jq -s '.' 2>/dev/null) || uv_tools_json="[]"
        [[ -z "$uv_tools_json" || "$uv_tools_json" == "null" ]] && uv_tools_json="[]"
    fi
    local uv_tool_count
    uv_tool_count=$(echo "$uv_tools_json" | jq 'length')
    _done "$uv_tool_count uv tools"

    local pyenv_versions_json="[]"
    if cmd_exists pyenv; then
        pyenv_versions_json=$(pyenv versions --bare 2>/dev/null \
            | sed 's/^[ *]*//' | awk '{print $1}' \
            | jq -R '.' | jq -s '.')
        local pyenv_ver_count
        pyenv_ver_count=$(echo "$pyenv_versions_json" | jq 'length')
        _done "$pyenv_ver_count pyenv versions"
    fi
    _phase_end

    _emit 06-python jq -n \
        --arg python_version "$python_version" \
        --arg python3_path "$python3_path" \
        --arg pip_version "$pip_version" \
        --arg uv_version "$uv_version" \
        --arg pipx_version "$pipx_version" \
        --arg pyenv_version "$pyenv_version" \
        --arg conda_version "$conda_version" \
        --argjson pyenv_versions "$pyenv_versions_json" \
        --argjson pipx_packages "$pipx_json" \
        --argjson uv_tools "$uv_tools_json" \
        '{python_ecosystem: {
            python_version: $python_version, python3_path: $python3_path,
            pip_version: $pip_version, uv_version: $uv_version,
            pipx_version: $pipx_version, pyenv_version: $pyenv_version,
            conda_version: $conda_version, pyenv_versions: $pyenv_versions,
            pipx_count: ($pipx_packages | length), pipx_packages: $pipx_packages,
            uv_tool_count: ($uv_tools | length), uv_tools: $uv_tools}}'
}

# ── /Applications ────────────────────────────────────────────────
collect_applications() {
    _phase "/Applications"

    local system_apps_json
    system_apps_json=$(find /Applications -maxdepth 2 -name "*.app" -type d 2>/dev/null | sort | while IFS= read -r app_path; do
        [[ -z "$app_path" ]] && continue
        local app_name version bundle_id
        app_name=$(basename "$app_path" .app)
        local plist="$app_path/Contents/Info.plist"
        if [[ -f "$plist" ]]; then
            version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$plist" 2>/dev/null || echo "unknown")
            bundle_id=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$plist" 2>/dev/null || echo "unknown")
        else
            version="unknown"; bundle_id="unknown"
        fi
        printf '%s\t%s\t%s\n' "$app_name" "$version" "$bundle_id"
    done | jq -R 'split("\t") | {name: .[0], version: (.[1] // "unknown"), bundle_id: (.[2] // "unknown")}' | jq -s '.')
    [[ -z "$system_apps_json" || "$system_apps_json" == "null" ]] && system_apps_json="[]"
    local app_count
    app_count=$(echo "$system_apps_json" | jq 'length')

    local user_apps_json="[]"
    if [[ -d "$HOME/Applications" ]]; then
        user_apps_json=$(find "$HOME/Applications" -maxdepth 2 -name "*.app" -type d 2>/dev/null | sort | while IFS= read -r app_path; do
            [[ -z "$app_path" ]] && continue
            local app_name version
            app_name=$(basename "$app_path" .app)
            local plist="$app_path/Contents/Info.plist"
            version=$([[ -f "$plist" ]] && /usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$plist" 2>/dev/null || echo "unknown")
            printf '%s\t%s\n' "$app_name" "$version"
        done | jq -R 'split("\t") | {name: .[0], version: (.[1] // "unknown")}' | jq -s '.')
        [[ -z "$user_apps_json" || "$user_apps_json" == "null" ]] && user_apps_json="[]"
    fi
    local user_app_count
    user_app_count=$(echo "$user_apps_json" | jq 'length')

    _done "$app_count system apps, $user_app_count user apps"
    _phase_end

    _emit 07-apps jq -n \
        --argjson system "$system_apps_json" \
        --argjson user "$user_apps_json" \
        '{applications: {
            system_count: ($system | length), system: $system,
            user_count: ($user | length), user: $user}}'
}

# ── Loose binaries ───────────────────────────────────────────────
collect_local_bins() {
    _phase "Loose Binaries"
    local search_dirs=("$HOME/.local/bin" "$HOME/bin" "/usr/local/bin")
    local all_dirs_json="[]"
    local total_count=0

    for dir in "${search_dirs[@]}"; do
        [[ ! -d "$dir" ]] && continue
        local dir_bins_json
        dir_bins_json=$(find "$dir" -maxdepth 1 -type f -perm +111 -exec basename {} \; 2>/dev/null \
            | sort | jq -R '{name: .}' | jq -s '.')
        [[ -z "$dir_bins_json" || "$dir_bins_json" == "null" ]] && continue
        local dir_count
        dir_count=$(echo "$dir_bins_json" | jq 'length')
        [[ "$dir_count" -eq 0 ]] && continue

        all_dirs_json=$(echo "$all_dirs_json" | jq --arg dir "$dir" --argjson bins "$dir_bins_json" \
            '. + [{directory: $dir, count: ($bins | length), binaries: $bins}]')
        total_count=$((total_count + dir_count))
        _done "$dir_count binaries in $dir"
    done
    _phase_end

    _emit 08-bins jq -n \
        --argjson directories "$all_dirs_json" \
        '{loose_binaries: {
            total_count: ([$directories[].count] | add // 0),
            directories: $directories}}'
}

# ── Shell environment ────────────────────────────────────────────
collect_shell() {
    _phase "Shell Environment"

    local current_shell="${SHELL:-unknown}"
    local zsh_version bash_version tmux_version zellij_version
    zsh_version=$(zsh --version 2>/dev/null | awk '{print $2}' || echo "not installed")
    bash_version=$(get_version bash --version)
    [[ -z "$bash_version" ]] && bash_version="not installed"
    cmd_exists tmux && tmux_version=$(tmux -V 2>/dev/null | awk '{print $2}') || tmux_version="not installed"
    cmd_exists zellij && zellij_version=$(zellij --version 2>/dev/null | awk '{print $2}') || zellij_version="not installed"

    local prompt_framework="none"
    cmd_exists starship && prompt_framework="starship"
    [[ -d "$HOME/.oh-my-zsh" ]] && prompt_framework="oh-my-zsh"
    [[ -f "$HOME/.p10k.zsh" ]] && prompt_framework="powerlevel10k"

    # CLI tools presence check
    local tools_to_check=(
        "git" "gh" "fzf" "ripgrep:rg" "fd" "bat" "eza" "delta" "jq" "yq"
        "htop" "btop" "neovim:nvim" "lazygit" "lazydocker" "atuin" "zoxide"
        "direnv" "stow" "wget" "curl" "httpie:http" "xh"
        "docker" "kubectl" "kubecolor" "helm" "k9s" "kubectx" "kustomize" "krew"
        "terraform" "colima" "lima" "podman"
        "tailscale" "mosh" "ssh"
        "ffmpeg" "imagemagick:magick" "pandoc"
        "claude:claude" "codex:codex" "gemini:gemini"
    )

    local cli_tools_json="[]"
    for entry in "${tools_to_check[@]}"; do
        local display_name cmd_name version_str cmd_path
        if [[ "$entry" == *":"* ]]; then
            display_name="${entry%%:*}"; cmd_name="${entry##*:}"
        else
            display_name="$entry"; cmd_name="$entry"
        fi
        if cmd_exists "$cmd_name"; then
            version_str=$(get_version "$cmd_name" --version)
            [[ -z "$version_str" ]] && version_str="installed"
            cmd_path=$(which "$cmd_name" 2>/dev/null)
            cli_tools_json=$(echo "$cli_tools_json" | jq \
                --arg name "$display_name" \
                --arg command "$cmd_name" \
                --arg version "$version_str" \
                --arg path "$cmd_path" \
                '. + [{name: $name, command: $command, version: $version, path: $path}]')
        fi
    done
    local cli_count
    cli_count=$(echo "$cli_tools_json" | jq 'length')
    _done "$cli_count CLI tools detected"
    _phase_end

    _emit 09-shell jq -n \
        --arg current_shell "$current_shell" \
        --arg zsh_version "$zsh_version" \
        --arg bash_version "$bash_version" \
        --arg tmux_version "$tmux_version" \
        --arg zellij_version "$zellij_version" \
        --arg prompt_framework "$prompt_framework" \
        --argjson cli_tools "$cli_tools_json" \
        '{shell: {current_shell: $current_shell, zsh_version: $zsh_version,
                  bash_version: $bash_version, tmux_version: $tmux_version,
                  zellij_version: $zellij_version, prompt_framework: $prompt_framework,
                  cli_tools_count: ($cli_tools | length), cli_tools: $cli_tools}}'
}

# ── Dev runtimes ─────────────────────────────────────────────────
collect_runtimes() {
    _phase "Other Runtimes & SDKs"

    local java_version="not installed" swift_version="not installed"
    local ruby_version="not installed" deno_version="not installed"
    local lua_version="not installed" luarocks_version="not installed"
    local zig_version="not installed"

    cmd_exists java && java_version=$(get_version java -version)
    [[ -z "$java_version" ]] && java_version="not installed"
    cmd_exists swift && swift_version=$(get_version swift --version)
    [[ -z "$swift_version" ]] && swift_version="not installed"
    cmd_exists ruby && ruby_version=$(_timeout_run 10 ruby --version 2>/dev/null | awk '{print $2}')
    [[ -z "$ruby_version" ]] && ruby_version="not installed"
    cmd_exists deno && deno_version=$(_timeout_run 10 deno --version 2>/dev/null | head -1 | awk '{print $2}')
    [[ -z "$deno_version" ]] && deno_version="not installed"
    cmd_exists lua && lua_version=$(get_version lua -v)
    [[ -z "$lua_version" ]] && lua_version="not installed"
    cmd_exists luarocks && luarocks_version=$(get_version luarocks --version)
    [[ -z "$luarocks_version" ]] && luarocks_version="not installed"
    cmd_exists zig && zig_version=$(_timeout_run 10 zig version 2>/dev/null)
    [[ -z "$zig_version" ]] && cmd_exists zig && zig_version="installed"

    local xcode_version="not installed" xcode_path="not installed"
    cmd_exists xcodebuild && xcode_version=$(_timeout_run 10 xcodebuild -version 2>/dev/null | head -1 | awk '{print $2}')
    [[ -z "$xcode_version" ]] && xcode_version="not installed"
    cmd_exists xcode-select && xcode_path=$(xcode-select -p 2>/dev/null || echo "not set")

    local sdkman_version="not installed"
    [[ -f "$HOME/.sdkman/bin/sdkman-init.sh" ]] && sdkman_version="installed"

    _done "Runtimes scanned"
    _phase_end

    _emit 10-runtimes jq -n \
        --arg java "$java_version" \
        --arg swift "$swift_version" \
        --arg ruby "$ruby_version" \
        --arg deno "$deno_version" \
        --arg lua "$lua_version" \
        --arg luarocks "$luarocks_version" \
        --arg zig "$zig_version" \
        --arg xcode_version "$xcode_version" \
        --arg xcode_path "$xcode_path" \
        --arg sdkman "$sdkman_version" \
        '{other_runtimes: {java: $java, swift: $swift, ruby: $ruby,
                           deno: $deno, lua: $lua, luarocks: $luarocks,
                           zig: $zig, xcode_version: $xcode_version,
                           xcode_path: $xcode_path, sdkman: $sdkman}}'
}

# ── Git config ───────────────────────────────────────────────────
collect_git_config() {
    _phase "Git Config"
    if ! cmd_exists git; then
        _skip "git not found"; _phase_end
        _emit 11-git jq -n '{git_config: {}}'
        return
    fi

    local git_user git_email
    git_user=$(git config --global user.name 2>/dev/null || echo "")
    git_email=$(git config --global user.email 2>/dev/null || echo "")
    _info "user=$git_user <$git_email>"

    local gitconfig_json gitignore_json
    gitconfig_json=$(_jq_file "$HOME/.gitconfig")
    local gitignore_path
    gitignore_path=$(git config --global core.excludesfile 2>/dev/null || echo "$HOME/.gitignore_global")
    gitignore_path="${gitignore_path/#\~/$HOME}"
    gitignore_json=$(_jq_file "$gitignore_path")

    _done "Git config captured"
    _phase_end

    _emit 11-git jq -n \
        --arg user "$git_user" \
        --arg email "$git_email" \
        --argjson gitconfig "$gitconfig_json" \
        --arg gitignore_path "$gitignore_path" \
        --argjson global_gitignore "$gitignore_json" \
        '{git_config: {user: $user, email: $email, gitconfig: $gitconfig,
                       global_gitignore_path: $gitignore_path,
                       global_gitignore: $global_gitignore}}'
}

# ── SSH ──────────────────────────────────────────────────────────
collect_ssh() {
    _phase "SSH"
    local ssh_dir="$HOME/.ssh"
    if [[ ! -d "$ssh_dir" ]]; then
        _skip "$HOME/.ssh not found"; _phase_end
        _emit 12-ssh jq -n '{ssh: {}}'
        return
    fi

    local keys_json="[]"
    for pub in "$ssh_dir"/*.pub; do
        [[ -f "$pub" ]] || continue
        local ktype kname
        ktype=$(awk '{print $1}' "$pub" 2>/dev/null)
        kname=$(basename "$pub" .pub)
        keys_json=$(echo "$keys_json" | jq --arg name "$kname" --arg type "$ktype" \
            '. + [{name: $name, type: $type}]')
    done
    local key_count
    key_count=$(echo "$keys_json" | jq 'length')
    _done "$key_count SSH key(s)"

    local ssh_config_json
    ssh_config_json=$(_jq_file "$ssh_dir/config")

    _phase_end

    _emit 12-ssh jq -n \
        --argjson keys "$keys_json" \
        --argjson config "$ssh_config_json" \
        '{ssh: {keys: $keys, config: $config}}'
}

# ── Shell config files ───────────────────────────────────────────
collect_shell_configs() {
    _phase "Shell Config Files"

    local files_to_check=(
        "$HOME/.bashrc"
        "$HOME/.bash_profile"
        "$HOME/.zshrc"
        "$HOME/.zshenv"
        "$HOME/.zprofile"
        "$HOME/.profile"
        "$HOME/.config/starship.toml"
        "$HOME/.config/atuin/config.toml"
        "$HOME/.config/zellij/config.kdl"
        "$HOME/.tmux.conf"
        "$HOME/.config/tmux/tmux.conf"
    )

    local configs_json="[]"
    local config_count=0
    for f in "${files_to_check[@]}"; do
        if [[ -f "$f" ]] || [[ -L "$f" ]]; then
            local size target=""
            size=$(wc -c < "$f" 2>/dev/null | tr -d ' ')
            [[ -L "$f" ]] && target=$(readlink "$f" 2>/dev/null || true)
            local content_json
            content_json=$(_jq_file "$f")

            if [[ -n "$target" ]]; then
                configs_json=$(echo "$configs_json" | jq \
                    --arg path "$f" --argjson size "$size" \
                    --arg symlink_target "$target" --argjson content "$content_json" \
                    '. + [{path: $path, size: $size, symlink_target: $symlink_target, content: $content}]')
            else
                configs_json=$(echo "$configs_json" | jq \
                    --arg path "$f" --argjson size "$size" \
                    --argjson content "$content_json" \
                    '. + [{path: $path, size: $size, content: $content}]')
            fi
            config_count=$((config_count + 1))
        fi
    done
    _done "$config_count shell config files"

    # Starship themes
    local starship_themes_json
    starship_themes_json=$(find "$HOME/.config" -maxdepth 1 -name 'starship*.toml' 2>/dev/null \
        | sort | xargs -I{} basename {} | jq -R '.' | jq -s '.' 2>/dev/null) || starship_themes_json="[]"
    [[ -z "$starship_themes_json" || "$starship_themes_json" == "null" ]] && starship_themes_json="[]"

    # tmux plugins
    local tmux_plugins_json="[]"
    local tmux_plugin_dirs=("$HOME/.tmux/plugins" "$HOME/.config/tmux/plugins")
    for tpd in "${tmux_plugin_dirs[@]}"; do
        [[ -d "$tpd" ]] || continue
        local dir_plugins
        dir_plugins=$(find "$tpd" -maxdepth 1 -mindepth 1 -type d -exec basename {} \; 2>/dev/null \
            | sort | jq -R '.' | jq -s '.')
        tmux_plugins_json=$(echo "$tmux_plugins_json" "$dir_plugins" | jq -s 'add')
    done
    local tmux_plugin_count
    tmux_plugin_count=$(echo "$tmux_plugins_json" | jq 'length')
    [[ "$tmux_plugin_count" -gt 0 ]] && _done "$tmux_plugin_count tmux plugins"

    # Dotfiles management
    local dotfiles_manager="none"
    [[ -d "$HOME/dotfiles/.git" || -d "$HOME/.dotfiles/.git" ]] && dotfiles_manager="git-repo"
    cmd_exists chezmoi && dotfiles_manager="chezmoi"
    cmd_exists yadm && dotfiles_manager="yadm"

    _phase_end

    _emit 13-shellconfigs jq -n \
        --argjson configs "$configs_json" \
        --argjson starship_themes "$starship_themes_json" \
        --argjson tmux_plugins "$tmux_plugins_json" \
        --arg dotfiles_manager "$dotfiles_manager" \
        '{shell_configs: {
            config_count: ($configs | length), configs: $configs,
            starship_themes: $starship_themes,
            tmux_plugins: $tmux_plugins,
            dotfiles_manager: $dotfiles_manager}}'
}

# ── VS Code extensions ───────────────────────────────────────────
collect_vscode() {
    _phase "Editor Extensions"

    local editor_cmd="" editor_name=""
    if cmd_exists code; then
        editor_cmd="code"; editor_name="VS Code"
    elif cmd_exists cursor; then
        editor_cmd="cursor"; editor_name="Cursor"
    else
        _skip "No VS Code or Cursor CLI found"; _phase_end
        _emit 14-vscode jq -n '{vscode: {installed: false}}'
        return
    fi

    _info "$editor_name detected"

    local ext_json
    ext_json=$($editor_cmd --list-extensions 2>/dev/null | jq -R '.' | jq -s '.')
    local ext_count
    ext_count=$(echo "$ext_json" | jq 'length')
    _done "$ext_count $editor_name extensions"
    _phase_end

    _emit 14-vscode jq -n \
        --arg editor "$editor_name" \
        --argjson extensions "$ext_json" \
        '{vscode: {installed: true, editor: $editor,
                   extension_count: ($extensions | length),
                   extensions: $extensions}}'
}

# ── Fonts ────────────────────────────────────────────────────────
collect_fonts() {
    _phase "Developer Fonts"

    local font_dirs=()
    [[ -d "$HOME/Library/Fonts" ]] && font_dirs+=("$HOME/Library/Fonts")
    [[ -d "/Library/Fonts" ]] && font_dirs+=("/Library/Fonts")

    local fonts_json="[]"
    if [[ ${#font_dirs[@]} -gt 0 ]]; then
        fonts_json=$(find "${font_dirs[@]}" -maxdepth 1 \
            \( -name "*.ttf" -o -name "*.otf" -o -name "*.ttc" \) -exec basename {} \; 2>/dev/null \
            | sort -u \
            | sgrep -iE 'nerd|mono|code|fira|jetbrains|hack|iosevka|cascadia|source.?code|inconsolata|menlo|sf.?mono' \
            | jq -R '.' | jq -s '.')
    fi
    [[ -z "$fonts_json" || "$fonts_json" == "null" ]] && fonts_json="[]"
    local font_count
    font_count=$(echo "$fonts_json" | jq 'length')
    _done "$font_count developer fonts"
    _phase_end

    _emit 15-fonts jq -n \
        --argjson fonts "$fonts_json" \
        '{developer_fonts: {count: ($fonts | length), fonts: $fonts}}'
}

# ── Environment variables & PATH ─────────────────────────────────
collect_env() {
    _phase "Environment & PATH"

    # PATH entries
    local path_json
    path_json=$(echo "$PATH" | tr ':' '\n' | jq -R '.' | jq -s '.')
    local path_count
    path_count=$(echo "$path_json" | jq 'length')
    _done "$path_count PATH entries"

    # Key env vars
    local vars_to_check=(
        "SHELL" "LANG" "LC_ALL"
        "GOPATH" "GOBIN"
        "VOLTA_HOME" "PNPM_HOME"
        "CARGO_HOME"
        "DENO_INSTALL" "BUN_INSTALL"
        "SDKMAN_DIR" "JAVA_HOME"
        "STARSHIP_CONFIG"
        "EDITOR" "VISUAL"
        "DOCKER_HOST"
    )

    local env_json="{}"
    local env_count=0
    for var in "${vars_to_check[@]}"; do
        local val="${!var:-}"
        [[ -z "$val" ]] && continue
        env_json=$(echo "$env_json" | jq --arg k "$var" --arg v "$val" '. + {($k): $v}')
        env_count=$((env_count + 1))
    done
    _done "$env_count environment variables"
    _phase_end

    _emit 16-env jq -n \
        --argjson path "$path_json" \
        --argjson variables "$env_json" \
        '{environment: {path_count: ($path | length), path: $path,
                        variables: $variables}}'
}

# ── LaunchAgents ─────────────────────────────────────────────────
collect_launch_agents() {
    _phase "LaunchAgents"
    local la_dir="$HOME/Library/LaunchAgents"
    local agents_json="[]"

    if [[ -d "$la_dir" ]]; then
        agents_json=$(find "$la_dir" -name "*.plist" 2>/dev/null \
            | sort | xargs -I{} basename {} .plist \
            | jq -R '.' | jq -s '.')
        [[ -z "$agents_json" || "$agents_json" == "null" ]] && agents_json="[]"
    fi
    local agent_count
    agent_count=$(echo "$agents_json" | jq 'length')
    _done "$agent_count user LaunchAgents"
    _phase_end

    _emit 17-launchagents jq -n \
        --argjson agents "$agents_json" \
        '{launch_agents: {count: ($agents | length), agents: $agents}}'
}

# ── Docker ───────────────────────────────────────────────────────
collect_docker() {
    _phase "Docker"
    if ! cmd_exists docker; then
        _skip "docker not found"; _phase_end
        _emit 18-docker jq -n '{docker: {installed: false}}'
        return
    fi

    local docker_version context
    docker_version=$(get_version docker --version)
    context=$(docker context show 2>/dev/null || echo "unknown")
    _info "Docker $docker_version  context=$context"

    local daemon_config_json
    daemon_config_json=$(_jq_file "$HOME/.docker/daemon.json")

    _phase_end

    _emit 18-docker jq -n \
        --arg version "$docker_version" \
        --arg context "$context" \
        --argjson daemon_config "$daemon_config_json" \
        '{docker: {installed: true, version: $version,
                   context: $context, daemon_config: $daemon_config}}'
}

# ── Claude Code config ───────────────────────────────────────────
collect_claude_config() {
    _phase "Claude Code"
    if ! cmd_exists claude; then
        _skip "claude not found"; _phase_end
        _emit 19-claude jq -n '{claude_code: {installed: false}}'
        return
    fi

    local claude_version
    claude_version=$(get_version claude --version)
    _info "Claude Code v$claude_version"

    local settings_json
    settings_json=$(_jq_file "$HOME/.claude/settings.json")

    # Installed plugins
    local plugins_json="[]"
    local plugins_file="$HOME/.claude/plugins/installed_plugins.json"
    if [[ -f "$plugins_file" ]]; then
        plugins_json=$(jq -r '.plugins | keys[]' "$plugins_file" 2>/dev/null | jq -R '.' | jq -s '.' 2>/dev/null) || plugins_json="[]"
        [[ -z "$plugins_json" || "$plugins_json" == "null" ]] && plugins_json="[]"
    fi
    local plugin_count
    plugin_count=$(echo "$plugins_json" | jq 'length')
    _done "$plugin_count plugins"

    # Custom agents
    local agents_json="[]"
    if [[ -d "$HOME/.claude/agents" ]]; then
        agents_json=$(find "$HOME/.claude/agents" -name "*.md" 2>/dev/null \
            | sort | xargs -I{} basename {} .md \
            | jq -R '.' | jq -s '.')
        [[ -z "$agents_json" || "$agents_json" == "null" ]] && agents_json="[]"
    fi
    local agent_count
    agent_count=$(echo "$agents_json" | jq 'length')
    [[ "$agent_count" -gt 0 ]] && _done "$agent_count custom agents"

    # Custom skills
    local skills_json="[]"
    if [[ -d "$HOME/.claude/skills" ]]; then
        skills_json=$(find "$HOME/.claude/skills" -maxdepth 1 -mindepth 1 -type d 2>/dev/null \
            | sort | xargs -I{} basename {} \
            | jq -R '.' | jq -s '.')
        [[ -z "$skills_json" || "$skills_json" == "null" ]] && skills_json="[]"
    fi
    local skill_count
    skill_count=$(echo "$skills_json" | jq 'length')
    [[ "$skill_count" -gt 0 ]] && _done "$skill_count custom skills"

    _phase_end

    _emit 19-claude jq -n \
        --arg version "$claude_version" \
        --argjson settings "$settings_json" \
        --argjson plugins "$plugins_json" \
        --argjson agents "$agents_json" \
        --argjson skills "$skills_json" \
        '{claude_code: {installed: true, version: $version,
                        settings: $settings, plugins: $plugins,
                        agents: $agents, skills: $skills}}'
}

# ── Codex (OpenAI) config ─────────────────────────────────────────
collect_codex_config() {
    _phase "Codex"
    if ! cmd_exists codex; then
        _skip "codex not found"; _phase_end
        _emit 20-codex jq -n '{codex: {installed: false}}'
        return
    fi

    local codex_version
    codex_version=$(get_version codex --version)
    _info "Codex v$codex_version"

    local config_json agents_md_json
    config_json=$(_jq_file "$HOME/.codex/config.toml")
    agents_md_json=$(_jq_file "$HOME/.codex/AGENTS.md")

    # Custom rules
    local rules_json="[]"
    if [[ -d "$HOME/.codex/rules" ]]; then
        rules_json=$(find "$HOME/.codex/rules" -type f 2>/dev/null \
            | sort | xargs -I{} basename {} \
            | jq -R '.' | jq -s '.')
        [[ -z "$rules_json" || "$rules_json" == "null" ]] && rules_json="[]"
    fi

    _done "Codex config captured"
    _phase_end

    _emit 20-codex jq -n \
        --arg version "$codex_version" \
        --argjson config "$config_json" \
        --argjson agents_md "$agents_md_json" \
        --argjson rules "$rules_json" \
        '{codex: {installed: true, version: $version,
                  config: $config, agents_md: $agents_md, rules: $rules}}'
}

# ── Gemini CLI config ────────────────────────────────────────────
collect_gemini_config() {
    _phase "Gemini CLI"
    if ! cmd_exists gemini; then
        _skip "gemini not found"; _phase_end
        _emit 21-gemini jq -n '{gemini: {installed: false}}'
        return
    fi

    local gemini_version
    gemini_version=$(get_version gemini --version)
    _info "Gemini CLI v$gemini_version"

    local settings_json gemini_md_json
    settings_json=$(_jq_file "$HOME/.gemini/settings.json")
    gemini_md_json=$(_jq_file "$HOME/.gemini/GEMINI.md")

    # Extensions
    local ext_json="[]"
    if [[ -d "$HOME/.gemini/extensions" ]]; then
        ext_json=$(find "$HOME/.gemini/extensions" -maxdepth 1 -mindepth 1 -type d 2>/dev/null \
            | sort | xargs -I{} basename {} \
            | jq -R '.' | jq -s '.')
        [[ -z "$ext_json" || "$ext_json" == "null" ]] && ext_json="[]"
    fi

    _done "Gemini config captured"
    _phase_end

    _emit 21-gemini jq -n \
        --arg version "$gemini_version" \
        --argjson settings "$settings_json" \
        --argjson gemini_md "$gemini_md_json" \
        --argjson extensions "$ext_json" \
        '{gemini: {installed: true, version: $version,
                   settings: $settings, gemini_md: $gemini_md,
                   extensions: $extensions}}'
}

# ── Agent skills (npx skills) ────────────────────────────────────
collect_agent_skills() {
    _phase "Agent Skills"

    local lock_file="$HOME/.agents/.skill-lock.json"
    if [[ ! -f "$lock_file" ]]; then
        _skip "No skill-lock.json found (npx skills not used)"
        _phase_end
        _emit 22-agent-skills jq -n '{agent_skills: {installed: false}}'
        return
    fi

    # Capture the full lock file — it has source, sourceType, skillPath for each skill
    local lock_json
    lock_json=$(jq '.skills' "$lock_file" 2>/dev/null)
    [[ -z "$lock_json" || "$lock_json" == "null" ]] && lock_json="{}"
    local skill_count
    skill_count=$(echo "$lock_json" | jq 'length')

    # Also capture which skill dirs exist under ~/.agents/skills/
    local dirs_json="[]"
    if [[ -d "$HOME/.agents/skills" ]]; then
        dirs_json=$(find "$HOME/.agents/skills" -maxdepth 1 -mindepth 1 -type d -exec basename {} \; 2>/dev/null \
            | sort | jq -R '.' | jq -s '.')
        [[ -z "$dirs_json" || "$dirs_json" == "null" ]] && dirs_json="[]"
    fi

    _done "$skill_count skills in lock file"
    _phase_end

    _emit 22-agent-skills jq -n \
        --argjson lock "$lock_json" \
        --argjson dirs "$dirs_json" \
        '{agent_skills: {installed: true,
                         skill_count: ($lock | length),
                         lock: $lock,
                         dirs: $dirs}}'
}

# ── macOS defaults (dev-relevant) ────────────────────────────────
collect_macos_defaults() {
    _phase "macOS Defaults"

    local dock_autohide dock_tilesize
    dock_autohide=$(defaults read com.apple.dock autohide 2>/dev/null || echo "0")
    dock_tilesize=$(defaults read com.apple.dock tilesize 2>/dev/null || echo "48")

    local key_repeat initial_repeat press_hold
    key_repeat=$(defaults read NSGlobalDomain KeyRepeat 2>/dev/null || echo "default")
    initial_repeat=$(defaults read NSGlobalDomain InitialKeyRepeat 2>/dev/null || echo "default")
    press_hold=$(defaults read NSGlobalDomain ApplePressAndHoldEnabled 2>/dev/null || echo "default")

    local show_all_files show_extensions show_path_bar
    show_all_files=$(defaults read com.apple.finder AppleShowAllFiles 2>/dev/null || echo "default")
    show_extensions=$(defaults read NSGlobalDomain AppleShowAllExtensions 2>/dev/null || echo "default")
    show_path_bar=$(defaults read com.apple.finder ShowPathbar 2>/dev/null || echo "default")

    _done "macOS defaults scanned"
    _phase_end

    _emit 22-macos jq -n \
        --arg dock_autohide "$dock_autohide" \
        --arg dock_tilesize "$dock_tilesize" \
        --arg key_repeat "$key_repeat" \
        --arg initial_repeat "$initial_repeat" \
        --arg press_hold "$press_hold" \
        --arg show_all_files "$show_all_files" \
        --arg show_extensions "$show_extensions" \
        --arg show_path_bar "$show_path_bar" \
        '{macos_defaults: {
            dock: {autohide: ($dock_autohide | tonumber? // $dock_autohide),
                   tilesize: ($dock_tilesize | tonumber? // $dock_tilesize)},
            keyboard: {key_repeat: $key_repeat, initial_key_repeat: $initial_repeat,
                       press_and_hold: $press_hold},
            finder: {show_all_files: $show_all_files, show_extensions: $show_extensions,
                     show_path_bar: $show_path_bar}}}'
}

# ── Main ─────────────────────────────────────────────────────────
main() {
    # Require jq — it's now essential, not optional
    if ! cmd_exists jq; then
        printf >&2 'ERROR: jq is required but not found. Install with: brew install jq\n'
        exit 1
    fi

    local title_plain="  macOS Tool Inventory  v${VERSION}"
    local title_styled="  ${BOLD}${BWHT}macOS Tool Inventory${RST}  ${BOLD}v${VERSION}${RST}"

    printf '\n' >&2
    _box_rule "$CYN" '╭' '╮'
    _box_line "$CYN" "${#title_plain}" "$title_styled"
    _box_rule "$CYN" '╰' '╯'
    printf '\n' >&2

    _log INFO "=== Yantraganana v${VERSION} started ==="
    _log INFO "Output: $OUTPUT_FILE"
    _log INFO "Log: $LOG_FILE"
    _log INFO "Hostname: $HOSTNAME_SHORT"

    printf "  ${DIM}${CYN}│${RST}  ${CYN}▸${RST} Output: ${UL}%s${RST}\n" "$OUTPUT_FILE" >&2
    printf "  ${DIM}${CYN}│${RST}  ${CYN}▸${RST} Log: ${UL}%s${RST}\n" "$LOG_FILE" >&2
    _info "Timestamp: $TIMESTAMP"

    local start_time; start_time=$(date +%s)

    # Run all collectors — each writes a JSON fragment to $TMPDIR_FRAGS
    collect_system_info
    collect_brew
    collect_node
    collect_go
    collect_rust
    collect_python
    collect_applications
    collect_local_bins
    collect_shell
    collect_runtimes
    collect_git_config
    collect_ssh
    collect_shell_configs
    collect_vscode
    collect_fonts
    collect_env
    collect_launch_agents
    collect_docker
    collect_claude_config
    collect_codex_config
    collect_gemini_config
    collect_agent_skills
    collect_macos_defaults

    # Merge all fragments into one JSON object
    jq -s 'add + {inventory_version: $v, generated_at: $ts}' \
        --arg v "$VERSION" --arg ts "$TIMESTAMP" \
        "$TMPDIR_FRAGS"/*.json > "$OUTPUT_FILE"

    local end_time elapsed
    end_time=$(date +%s)
    elapsed=$(( end_time - start_time ))

    # ── Summary box ─────────────────────────────
    printf '\n' >&2
    if jq empty "$OUTPUT_FILE" 2>/dev/null; then
        local total_size size_str
        total_size=$(wc -c < "$OUTPUT_FILE" | tr -d ' ')
        size_str=$(human_size "$total_size")

        local line1_plain="  ✔  Inventory complete  (${elapsed}s, ${size_str})"
        local line1_styled="  ${BGRN}✔${RST}  ${BOLD}Inventory complete${RST}  ${DIM}(${elapsed}s, ${size_str})${RST}"
        local line2_plain="     Valid JSON written successfully"
        local line2_styled="     Valid JSON written successfully"

        _log INFO "Inventory complete (${elapsed}s, ${size_str}), valid JSON"

        _box_rule "$BGRN" '╭' '╮'
        _box_line "$BGRN" "${#line1_plain}" "$line1_styled"
        _box_line "$BGRN" "${#line2_plain}" "$line2_styled"
        _box_rule "$BGRN" '╰' '╯'
        printf "  ${DIM}${UL}%s${RST}\n" "$OUTPUT_FILE" >&2
        printf "  ${DIM}Log: ${UL}%s${RST}\n\n" "$LOG_FILE" >&2
    else
        local f1_plain="  ✘  JSON validation failed"
        local f1_styled="  ${RED}✘${RST}  ${BOLD}JSON validation failed${RST}"
        local fname; fname=$(basename "$OUTPUT_FILE")
        local f2_plain="     Run: jq . '${fname}'"
        local f2_styled="     ${DIM}Run: jq . '${fname}'${RST}"

        _log ERROR "JSON validation failed for $OUTPUT_FILE"

        _box_rule "$RED" '╭' '╮'
        _box_line "$RED" "${#f1_plain}" "$f1_styled"
        _box_line "$RED" "${#f2_plain}" "$f2_styled"
        _box_rule "$RED" '╰' '╯'
        printf "  ${DIM}Log: ${UL}%s${RST}\n\n" "$LOG_FILE" >&2
    fi
}

main "$@"
