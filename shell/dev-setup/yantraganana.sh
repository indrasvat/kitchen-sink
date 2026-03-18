#!/usr/bin/env bash
# ╭──────────────────────────────────────────────────────────────╮
# │  Yantragaṇanā — macOS Tool Inventory Report                 │
# │  Scans all package managers, configs & known paths → JSON    │
# │  Designed for AI coding agents to reconstruct a dev env      │
# ╰──────────────────────────────────────────────────────────────╯
set -euo pipefail

readonly VERSION="2.0.0"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
readonly TIMESTAMP
HOSTNAME=$(hostname -s)
readonly HOSTNAME
readonly OUTPUT_FILE="${1:-$HOME/tool-inventory-$(date +%Y%m%d-%H%M%S).json}"

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
_info()  { printf "  ${DIM}${CYN}│${RST}  ${CYN}▸${RST} %s\n" "$*" >&2; }
_done()  { printf "  ${DIM}${CYN}│${RST}  ${BGRN}✔${RST} %s\n" "$*" >&2; }
_warn()  { printf "  ${DIM}${CYN}│${RST}  ${BYEL}⚠${RST}  ${YEL}%s${RST}\n" "$*" >&2; }
_skip()  { printf "  ${DIM}${CYN}│${RST}  ${DIM}○ %s${RST}\n" "$*" >&2; }

_phase() {
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
inc() { eval "$1=\$(( $1 + 1 ))"; }
sgrep() { grep "$@" || true; }

get_version() {
    ( "$@" 2>&1 || true ) | head -1 | sgrep -oE '[0-9]+\.[0-9]+[.0-9]*' | head -1
}

json_escape() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//$'\n'/\\n}"
    s="${s//$'\t'/\\t}"
    printf '%s' "$s"
}

# Emit a JSON array of strings from lines of input
json_string_array() {
    local json="" count=0
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        [[ $count -gt 0 ]] && json+=","
        json+=" \"$(json_escape "$line")\""
        inc count
    done
    printf '[%s ]' "$json"
}

# Read a file and emit its content as a JSON-escaped string (max 50KB)
json_file_content() {
    local f="$1"
    if [[ -f "$f" ]]; then
        local content
        content=$(head -c 51200 "$f" 2>/dev/null || true)
        printf '"%s"' "$(json_escape "$content")"
    else
        printf 'null'
    fi
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

    cat <<EOF
  "system": {
    "hostname": "$(json_escape "$HOSTNAME")",
    "os": "$(json_escape "$product_name")",
    "version": "$(json_escape "$product_version")",
    "build": "$(json_escape "$build_version")",
    "arch": "$(json_escape "$arch")",
    "chip": "$(json_escape "$chip")",
    "memory": "$(json_escape "$memory")",
    "serial": "$(json_escape "$serial")"
  }
EOF
}

# ── Homebrew ─────────────────────────────────────────────────────
collect_brew() {
    _phase "Homebrew"
    if ! cmd_exists brew; then
        _skip "brew not found, skipping"
        _phase_end
        echo '  "homebrew": { "installed": false }'
        return
    fi

    local brew_version brew_prefix
    brew_version=$(brew --version 2>/dev/null | head -1)
    brew_prefix=$(brew --prefix 2>/dev/null)
    _info "$brew_version at $brew_prefix"

    # Formulae
    local formulae_json=""
    local count=0
    while IFS=$'\t' read -r name version; do
        [[ -z "$name" ]] && continue
        [[ $count -gt 0 ]] && formulae_json+=","
        formulae_json+=$'\n'"      { \"name\": \"$(json_escape "$name")\", \"version\": \"$(json_escape "$version")\" }"
        inc count
    done < <(brew list --formula --versions 2>/dev/null | awk '{print $1 "\t" $2}')
    _done "$count formulae"

    # Casks — brew list --cask --versions returns empty on some Homebrew versions,
    # so fall back to reading version dirs from Caskroom
    local casks_json=""
    local cask_count=0
    local caskroom
    caskroom="$(brew --prefix 2>/dev/null)/Caskroom"
    while IFS= read -r cask_name; do
        [[ -z "$cask_name" ]] && continue
        local cask_ver="unknown"
        # Get the installed version from the Caskroom directory
        if [[ -d "$caskroom/$cask_name" ]]; then
            cask_ver=$(find "$caskroom/$cask_name" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | head -1 | xargs basename 2>/dev/null)
            [[ -z "$cask_ver" ]] && cask_ver="unknown"
        fi
        [[ $cask_count -gt 0 ]] && casks_json+=","
        casks_json+=$'\n'"      { \"name\": \"$(json_escape "$cask_name")\", \"version\": \"$(json_escape "$cask_ver")\" }"
        inc cask_count
    done < <(brew list --cask 2>/dev/null)
    _done "$cask_count casks"

    # Taps
    local taps_json=""
    local tap_count=0
    while IFS= read -r tap; do
        [[ -z "$tap" ]] && continue
        [[ $tap_count -gt 0 ]] && taps_json+=","
        taps_json+=" \"$(json_escape "$tap")\""
        inc tap_count
    done < <(brew tap 2>/dev/null)
    _done "$tap_count taps"

    _phase_end

    cat <<EOF
  "homebrew": {
    "installed": true,
    "version": "$(json_escape "$brew_version")",
    "prefix": "$(json_escape "$brew_prefix")",
    "taps": [${taps_json} ],
    "formulae_count": $count,
    "formulae": [${formulae_json}
    ],
    "casks_count": $cask_count,
    "casks": [${casks_json}
    ]
  }
EOF
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
    local npm_globals_json=""
    local npm_global_count=0
    if cmd_exists npm; then
        while IFS='@' read -r pkg ver; do
            [[ -z "$pkg" || "$pkg" == *"("* ]] && continue
            [[ $npm_global_count -gt 0 ]] && npm_globals_json+=","
            npm_globals_json+=$'\n'"        { \"name\": \"$(json_escape "$pkg")\", \"version\": \"$(json_escape "$ver")\" }"
            inc npm_global_count
        done < <(npm list -g --depth=0 --parseable 2>/dev/null | tail -n +2 | xargs -I{} basename {} | sort)
        if [[ $npm_global_count -eq 0 ]]; then
            while read -r line; do
                local pkg ver
                pkg=$(echo "$line" | sed -E 's/.*── ([^@]+)@.*/\1/' 2>/dev/null)
                ver=$(echo "$line" | sed -E 's/.*@([^ ]+).*/\1/' 2>/dev/null)
                [[ -z "$pkg" || "$pkg" == "$line" ]] && continue
                [[ $npm_global_count -gt 0 ]] && npm_globals_json+=","
                npm_globals_json+=$'\n'"        { \"name\": \"$(json_escape "$pkg")\", \"version\": \"$(json_escape "$ver")\" }"
                inc npm_global_count
            done < <(npm list -g --depth=0 2>/dev/null | sgrep -E '── ')
        fi
    fi
    _done "$npm_global_count global npm packages"

    # Volta-managed tools — use `volta list all` for accurate names
    local volta_tools_json=""
    local volta_tool_count=0
    if cmd_exists volta; then
        while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            local kind name_ver name ver
            kind=$(echo "$line" | awk '{print $1}')
            name_ver=$(echo "$line" | awk '{print $2}')
            # Handle scoped packages like @google/clasp@3.3.0
            # Split on the LAST @ to separate name from version
            ver="${name_ver##*@}"
            name="${name_ver%@*}"
            local is_default=""
            [[ "$line" == *"(default)"* ]] && is_default=", \"default\": true"
            [[ $volta_tool_count -gt 0 ]] && volta_tools_json+=","
            volta_tools_json+=$'\n'"        { \"kind\": \"$(json_escape "$kind")\", \"name\": \"$(json_escape "$name")\", \"version\": \"$(json_escape "$ver")\"${is_default} }"
            inc volta_tool_count
        done < <(volta list all 2>/dev/null || true)
        _done "$volta_tool_count volta-managed tools"
    fi

    _phase_end

    cat <<EOF
  "node_ecosystem": {
    "version_manager": "$(json_escape "$manager")",
    "volta_version": "$(json_escape "$volta_version")",
    "node_version": "$(json_escape "$node_version")",
    "npm_version": "$(json_escape "$npm_version")",
    "npx_version": "$(json_escape "$npx_version")",
    "pnpm_version": "$(json_escape "$pnpm_version")",
    "yarn_version": "$(json_escape "$yarn_version")",
    "bun_version": "$(json_escape "$bun_version")",
    "npm_global_count": $npm_global_count,
    "npm_globals": [${npm_globals_json}
    ],
    "volta_tool_count": $volta_tool_count,
    "volta_tools": [${volta_tools_json}
    ]
  }
EOF
}

# ── Go ───────────────────────────────────────────────────────────
collect_go() {
    _phase "Go"
    if ! cmd_exists go; then
        _skip "go not found, skipping"; _phase_end
        echo '  "go": { "installed": false }'; return
    fi

    local go_version gopath gobin
    go_version=$(go version 2>/dev/null | awk '{print $3}')
    gopath=$(go env GOPATH 2>/dev/null || echo "$HOME/go")
    gobin="${GOBIN:-$gopath/bin}"
    _info "$go_version  GOPATH=$gopath"

    local bins_json="" bin_count=0
    if [[ -d "$gobin" ]]; then
        while IFS= read -r binary; do
            [[ -z "$binary" ]] && continue
            local bname; bname=$(basename "$binary")
            [[ $bin_count -gt 0 ]] && bins_json+=","
            bins_json+=$'\n'"      { \"name\": \"$(json_escape "$bname")\" }"
            inc bin_count
        done < <(find "$gobin" -maxdepth 1 -type f -perm +111 2>/dev/null | sort)
    fi
    _done "$bin_count binaries in GOBIN"
    _phase_end

    cat <<EOF
  "go": {
    "installed": true,
    "version": "$(json_escape "$go_version")",
    "gopath": "$(json_escape "$gopath")",
    "gobin": "$(json_escape "$gobin")",
    "binaries_count": $bin_count,
    "binaries": [${bins_json}
    ]
  }
EOF
}

# ── Rust / Cargo ─────────────────────────────────────────────────
collect_rust() {
    _phase "Rust / Cargo"
    if ! cmd_exists rustc; then
        _skip "rustc not found, skipping"; _phase_end
        echo '  "rust": { "installed": false }'; return
    fi

    local rust_version cargo_version rustup_version
    rust_version=$(rustc --version 2>/dev/null | awk '{print $2}')
    cargo_version=$(cargo --version 2>/dev/null | awk '{print $2}')
    rustup_version=$(rustup --version 2>/dev/null | head -1 | awk '{print $2}' || echo "not installed")
    _info "rustc=$rust_version  cargo=$cargo_version"

    local cargo_bins_json="" cargo_bin_count=0
    local cargo_home="${CARGO_HOME:-$HOME/.cargo}"
    if [[ -d "$cargo_home/bin" ]]; then
        while IFS= read -r binary; do
            [[ -z "$binary" ]] && continue
            local bname; bname=$(basename "$binary")
            [[ "$bname" == "rustc" || "$bname" == "cargo" || "$bname" == "rustup" || \
               "$bname" == "rustfmt" || "$bname" == "rust-gdb" || "$bname" == "rust-lldb" || \
               "$bname" == "clippy-driver" || "$bname" == "cargo-fmt" || \
               "$bname" == "rust-gdbgui" || "$bname" == "rustdoc" ]] && continue
            [[ $cargo_bin_count -gt 0 ]] && cargo_bins_json+=","
            cargo_bins_json+=$'\n'"      { \"name\": \"$(json_escape "$bname")\" }"
            inc cargo_bin_count
        done < <(find "$cargo_home/bin" -maxdepth 1 -type f -perm +111 2>/dev/null | sort)
    fi
    _done "$cargo_bin_count cargo-installed binaries"

    local toolchains_json="" tc_count=0
    if cmd_exists rustup; then
        while IFS= read -r tc; do
            [[ -z "$tc" ]] && continue
            [[ $tc_count -gt 0 ]] && toolchains_json+=","
            toolchains_json+=" \"$(json_escape "$tc")\""
            inc tc_count
        done < <(rustup toolchain list 2>/dev/null)
        _done "$tc_count toolchains"
    fi
    _phase_end

    cat <<EOF
  "rust": {
    "installed": true,
    "rustc_version": "$(json_escape "$rust_version")",
    "cargo_version": "$(json_escape "$cargo_version")",
    "rustup_version": "$(json_escape "$rustup_version")",
    "cargo_home": "$(json_escape "$cargo_home")",
    "toolchains": [${toolchains_json} ],
    "cargo_binaries_count": $cargo_bin_count,
    "cargo_binaries": [${cargo_bins_json}
    ]
  }
EOF
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

    local pipx_json="" pipx_count=0
    if cmd_exists pipx; then
        while read -r line; do
            local pkg ver
            pkg=$(echo "$line" | awk '{print $1}')
            ver=$(echo "$line" | sgrep -oE '[0-9]+\.[0-9]+[.0-9]*' | head -1)
            [[ -z "$pkg" || "$pkg" == "venvs" || "$pkg" == "package" ]] && continue
            [[ $pipx_count -gt 0 ]] && pipx_json+=","
            pipx_json+=$'\n'"      { \"name\": \"$(json_escape "$pkg")\", \"version\": \"$(json_escape "${ver:-unknown}")\" }"
            inc pipx_count
        done < <(pipx list --short 2>/dev/null)
    fi
    _done "$pipx_count pipx packages"

    local uv_tools_json="" uv_tool_count=0
    if cmd_exists uv; then
        while read -r line; do
            [[ -z "$line" || "$line" == *"No tools"* || "$line" == "- "* ]] && continue
            local tool ver
            tool=$(echo "$line" | awk '{print $1}')
            ver=$(echo "$line" | sgrep -oE 'v[0-9]+\.[0-9]+[.0-9]*' | head -1)
            [[ -z "$tool" ]] && continue
            [[ $uv_tool_count -gt 0 ]] && uv_tools_json+=","
            uv_tools_json+=$'\n'"      { \"name\": \"$(json_escape "$tool")\", \"version\": \"$(json_escape "${ver:-unknown}")\" }"
            inc uv_tool_count
        done < <(uv tool list 2>/dev/null)
    fi
    _done "$uv_tool_count uv tools"

    local pyenv_versions_json="" pyenv_ver_count=0
    if cmd_exists pyenv; then
        while IFS= read -r ver; do
            [[ -z "$ver" ]] && continue
            ver=$(echo "$ver" | sed 's/^[ *]*//' | awk '{print $1}')
            [[ $pyenv_ver_count -gt 0 ]] && pyenv_versions_json+=","
            pyenv_versions_json+=" \"$(json_escape "$ver")\""
            inc pyenv_ver_count
        done < <(pyenv versions --bare 2>/dev/null)
        _done "$pyenv_ver_count pyenv versions"
    fi
    _phase_end

    cat <<EOF
  "python_ecosystem": {
    "python_version": "$(json_escape "$python_version")",
    "python3_path": "$(json_escape "$python3_path")",
    "pip_version": "$(json_escape "$pip_version")",
    "uv_version": "$(json_escape "$uv_version")",
    "pipx_version": "$(json_escape "$pipx_version")",
    "pyenv_version": "$(json_escape "$pyenv_version")",
    "conda_version": "$(json_escape "$conda_version")",
    "pyenv_versions": [${pyenv_versions_json} ],
    "pipx_count": $pipx_count,
    "pipx_packages": [${pipx_json}
    ],
    "uv_tool_count": $uv_tool_count,
    "uv_tools": [${uv_tools_json}
    ]
  }
EOF
}

# ── /Applications ────────────────────────────────────────────────
collect_applications() {
    _phase "/Applications"
    local apps_json="" app_count=0

    while IFS= read -r app_path; do
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
        [[ $app_count -gt 0 ]] && apps_json+=","
        apps_json+=$'\n'"    { \"name\": \"$(json_escape "$app_name")\", \"version\": \"$(json_escape "$version")\", \"bundle_id\": \"$(json_escape "$bundle_id")\" }"
        inc app_count
    done < <(find /Applications -maxdepth 2 -name "*.app" -type d 2>/dev/null | sort)

    local user_apps_json="" user_app_count=0
    if [[ -d "$HOME/Applications" ]]; then
        while IFS= read -r app_path; do
            [[ -z "$app_path" ]] && continue
            local app_name version
            app_name=$(basename "$app_path" .app)
            local plist="$app_path/Contents/Info.plist"
            version=$([[ -f "$plist" ]] && /usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$plist" 2>/dev/null || echo "unknown")
            [[ $user_app_count -gt 0 ]] && user_apps_json+=","
            user_apps_json+=$'\n'"    { \"name\": \"$(json_escape "$app_name")\", \"version\": \"$(json_escape "$version")\" }"
            inc user_app_count
        done < <(find "$HOME/Applications" -maxdepth 2 -name "*.app" -type d 2>/dev/null | sort)
    fi
    _done "$app_count system apps, $user_app_count user apps"
    _phase_end

    cat <<EOF
  "applications": {
    "system_count": $app_count,
    "system": [${apps_json}
    ],
    "user_count": $user_app_count,
    "user": [${user_apps_json}
    ]
  }
EOF
}

# ── Loose binaries ───────────────────────────────────────────────
collect_local_bins() {
    _phase "Loose Binaries"
    local search_dirs=("$HOME/.local/bin" "$HOME/bin" "/usr/local/bin")
    local all_bins_json="" total_count=0

    for dir in "${search_dirs[@]}"; do
        [[ ! -d "$dir" ]] && continue
        local dir_bins="" dir_count=0
        while IFS= read -r binary; do
            [[ -z "$binary" ]] && continue
            local bname; bname=$(basename "$binary")
            [[ $dir_count -gt 0 ]] && dir_bins+=","
            dir_bins+=$'\n'"        { \"name\": \"$(json_escape "$bname")\" }"
            inc dir_count
        done < <(find "$dir" -maxdepth 1 -type f -perm +111 2>/dev/null | sort)

        [[ $dir_count -eq 0 ]] && continue
        [[ $total_count -gt 0 ]] && all_bins_json+=","
        all_bins_json+=$'\n'"    { \"directory\": \"$(json_escape "$dir")\", \"count\": $dir_count, \"binaries\": [${dir_bins}
      ] }"
        total_count=$((total_count + dir_count))
        _done "$dir_count binaries in $dir"
    done
    _phase_end

    cat <<EOF
  "loose_binaries": {
    "total_count": $total_count,
    "directories": [${all_bins_json}
    ]
  }
EOF
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
    local cli_tools_json="" cli_count=0
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

    for entry in "${tools_to_check[@]}"; do
        local display_name cmd_name version_str
        if [[ "$entry" == *":"* ]]; then
            display_name="${entry%%:*}"; cmd_name="${entry##*:}"
        else
            display_name="$entry"; cmd_name="$entry"
        fi
        if cmd_exists "$cmd_name"; then
            version_str=$(get_version "$cmd_name" --version)
            [[ -z "$version_str" ]] && version_str="installed"
            [[ $cli_count -gt 0 ]] && cli_tools_json+=","
            cli_tools_json+=$'\n'"    { \"name\": \"$(json_escape "$display_name")\", \"command\": \"$(json_escape "$cmd_name")\", \"version\": \"$(json_escape "$version_str")\", \"path\": \"$(which "$cmd_name" 2>/dev/null)\" }"
            inc cli_count
        fi
    done
    _done "$cli_count CLI tools detected"
    _phase_end

    cat <<EOF
  "shell": {
    "current_shell": "$(json_escape "$current_shell")",
    "zsh_version": "$(json_escape "$zsh_version")",
    "bash_version": "$(json_escape "$bash_version")",
    "tmux_version": "$(json_escape "$tmux_version")",
    "zellij_version": "$(json_escape "$zellij_version")",
    "prompt_framework": "$(json_escape "$prompt_framework")",
    "cli_tools_count": $cli_count,
    "cli_tools": [${cli_tools_json}
    ]
  }
EOF
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
    cmd_exists ruby && ruby_version=$(ruby --version 2>/dev/null | awk '{print $2}' || echo "installed")
    cmd_exists deno && deno_version=$(deno --version 2>/dev/null | head -1 | awk '{print $2}' || echo "installed")
    cmd_exists lua && lua_version=$(get_version lua -v)
    [[ -z "$lua_version" ]] && lua_version="not installed"
    cmd_exists luarocks && luarocks_version=$(get_version luarocks --version)
    [[ -z "$luarocks_version" ]] && luarocks_version="not installed"
    cmd_exists zig && zig_version=$(zig version 2>/dev/null || echo "installed")

    local xcode_version="not installed" xcode_path="not installed"
    cmd_exists xcodebuild && xcode_version=$(xcodebuild -version 2>/dev/null | head -1 | awk '{print $2}')
    cmd_exists xcode-select && xcode_path=$(xcode-select -p 2>/dev/null || echo "not set")

    # SDKMAN
    local sdkman_version="not installed"
    [[ -f "$HOME/.sdkman/bin/sdkman-init.sh" ]] && sdkman_version="installed"

    _done "Runtimes scanned"
    _phase_end

    cat <<EOF
  "other_runtimes": {
    "java": "$(json_escape "$java_version")",
    "swift": "$(json_escape "$swift_version")",
    "ruby": "$(json_escape "$ruby_version")",
    "deno": "$(json_escape "$deno_version")",
    "lua": "$(json_escape "$lua_version")",
    "luarocks": "$(json_escape "$luarocks_version")",
    "zig": "$(json_escape "$zig_version")",
    "xcode_version": "$(json_escape "$xcode_version")",
    "xcode_path": "$(json_escape "$xcode_path")",
    "sdkman": "$(json_escape "$sdkman_version")"
  }
EOF
}

# ── Git config ───────────────────────────────────────────────────
collect_git_config() {
    _phase "Git Config"
    if ! cmd_exists git; then
        _skip "git not found"; _phase_end
        echo '  "git_config": {}'; return
    fi

    local git_user git_email
    git_user=$(git config --global user.name 2>/dev/null || echo "")
    git_email=$(git config --global user.email 2>/dev/null || echo "")
    _info "user=$git_user <$git_email>"

    # Capture full gitconfig, global gitignore
    local gitconfig_content gitignore_content
    gitconfig_content=$(json_file_content "$HOME/.gitconfig")
    local gitignore_path
    gitignore_path=$(git config --global core.excludesfile 2>/dev/null || echo "$HOME/.gitignore_global")
    # Expand ~ if present
    gitignore_path="${gitignore_path/#\~/$HOME}"
    gitignore_content=$(json_file_content "$gitignore_path")

    _done "Git config captured"
    _phase_end

    cat <<EOF
  "git_config": {
    "user": "$(json_escape "$git_user")",
    "email": "$(json_escape "$git_email")",
    "gitconfig": $gitconfig_content,
    "global_gitignore_path": "$(json_escape "$gitignore_path")",
    "global_gitignore": $gitignore_content
  }
EOF
}

# ── SSH ──────────────────────────────────────────────────────────
collect_ssh() {
    _phase "SSH"
    local ssh_dir="$HOME/.ssh"
    if [[ ! -d "$ssh_dir" ]]; then
        _skip "$HOME/.ssh not found"; _phase_end
        echo '  "ssh": {}'; return
    fi

    # Key types (never contents)
    local keys_json="" key_count=0
    for pub in "$ssh_dir"/*.pub; do
        [[ -f "$pub" ]] || continue
        local ktype
        ktype=$(awk '{print $1}' "$pub" 2>/dev/null)
        local kname; kname=$(basename "$pub" .pub)
        [[ $key_count -gt 0 ]] && keys_json+=","
        keys_json+=" { \"name\": \"$(json_escape "$kname")\", \"type\": \"$(json_escape "$ktype")\" }"
        inc key_count
    done
    _done "$key_count SSH key(s)"

    local ssh_config_content
    ssh_config_content=$(json_file_content "$ssh_dir/config")

    _phase_end

    cat <<EOF
  "ssh": {
    "keys": [${keys_json} ],
    "config": $ssh_config_content
  }
EOF
}

# ── Shell config files ───────────────────────────────────────────
collect_shell_configs() {
    _phase "Shell Config Files"

    local configs_json=""
    local config_count=0
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

    for f in "${files_to_check[@]}"; do
        if [[ -f "$f" ]] || [[ -L "$f" ]]; then
            local size target=""
            size=$(wc -c < "$f" 2>/dev/null | tr -d ' ')
            [[ -L "$f" ]] && target=$(readlink "$f" 2>/dev/null || true)
            local content
            content=$(json_file_content "$f")
            [[ $config_count -gt 0 ]] && configs_json+=","
            configs_json+=$'\n'"    { \"path\": \"$(json_escape "$f")\", \"size\": $size"
            [[ -n "$target" ]] && configs_json+=", \"symlink_target\": \"$(json_escape "$target")\""
            configs_json+=", \"content\": $content }"
            inc config_count
        fi
    done
    _done "$config_count shell config files"

    # Starship themes
    local starship_themes_json=""
    local theme_count=0
    for t in "$HOME/.config"/starship*.toml; do
        [[ -f "$t" ]] || continue
        local tname; tname=$(basename "$t")
        [[ $theme_count -gt 0 ]] && starship_themes_json+=","
        starship_themes_json+=" \"$(json_escape "$tname")\""
        inc theme_count
    done

    # tmux plugins
    local tmux_plugins_json=""
    local tmux_plugin_count=0
    local tmux_plugin_dirs=("$HOME/.tmux/plugins" "$HOME/.config/tmux/plugins")
    for tpd in "${tmux_plugin_dirs[@]}"; do
        [[ -d "$tpd" ]] || continue
        while IFS= read -r pdir; do
            [[ -z "$pdir" ]] && continue
            local pname; pname=$(basename "$pdir")
            [[ $tmux_plugin_count -gt 0 ]] && tmux_plugins_json+=","
            tmux_plugins_json+=" \"$(json_escape "$pname")\""
            inc tmux_plugin_count
        done < <(find "$tpd" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | sort)
    done
    [[ $tmux_plugin_count -gt 0 ]] && _done "$tmux_plugin_count tmux plugins"

    # Dotfiles management
    local dotfiles_manager="none"
    [[ -d "$HOME/dotfiles/.git" || -d "$HOME/.dotfiles/.git" ]] && dotfiles_manager="git-repo"
    cmd_exists chezmoi && dotfiles_manager="chezmoi"
    cmd_exists yadm && dotfiles_manager="yadm"

    _phase_end

    cat <<EOF
  "shell_configs": {
    "config_count": $config_count,
    "configs": [${configs_json}
    ],
    "starship_themes": [${starship_themes_json} ],
    "tmux_plugins": [${tmux_plugins_json} ],
    "dotfiles_manager": "$(json_escape "$dotfiles_manager")"
  }
EOF
}

# ── VS Code extensions ───────────────────────────────────────────
collect_vscode() {
    _phase "VS Code"
    if ! cmd_exists code; then
        _skip "VS Code CLI not found"; _phase_end
        echo '  "vscode": { "installed": false }'; return
    fi

    local ext_json="" ext_count=0
    while IFS= read -r ext; do
        [[ -z "$ext" ]] && continue
        [[ $ext_count -gt 0 ]] && ext_json+=","
        ext_json+=" \"$(json_escape "$ext")\""
        inc ext_count
    done < <(code --list-extensions 2>/dev/null)
    _done "$ext_count VS Code extensions"
    _phase_end

    cat <<EOF
  "vscode": {
    "installed": true,
    "extension_count": $ext_count,
    "extensions": [${ext_json} ]
  }
EOF
}

# ── Fonts ────────────────────────────────────────────────────────
collect_fonts() {
    _phase "Developer Fonts"

    local fonts_json="" font_count=0
    local font_dirs=("$HOME/Library/Fonts" "/Library/Fonts")

    for dir in "${font_dirs[@]}"; do
        [[ -d "$dir" ]] || continue
        while IFS= read -r font; do
            [[ -z "$font" ]] && continue
            [[ $font_count -gt 0 ]] && fonts_json+=","
            fonts_json+=" \"$(json_escape "$font")\""
            inc font_count
        done < <(find "$dir" -maxdepth 1 \( -name "*.ttf" -o -name "*.otf" -o -name "*.ttc" \) -exec basename {} \; 2>/dev/null \
                 | sort -u | sgrep -iE 'nerd|mono|code|fira|jetbrains|hack|iosevka|cascadia|source.?code|inconsolata|menlo|sf.?mono')
    done
    _done "$font_count developer fonts"
    _phase_end

    cat <<EOF
  "developer_fonts": {
    "count": $font_count,
    "fonts": [${fonts_json} ]
  }
EOF
}

# ── Environment variables & PATH ─────────────────────────────────
collect_env() {
    _phase "Environment & PATH"

    # Capture PATH entries in order
    local path_json=""
    local path_count=0
    local IFS=':'
    for p in $PATH; do
        [[ $path_count -gt 0 ]] && path_json+=","
        path_json+=$'\n'"    \"$(json_escape "$p")\""
        inc path_count
    done
    unset IFS
    _done "$path_count PATH entries"

    # Key env vars an agent would need
    local env_json=""
    local env_count=0
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

    for var in "${vars_to_check[@]}"; do
        local val="${!var:-}"
        [[ -z "$val" ]] && continue
        [[ $env_count -gt 0 ]] && env_json+=","
        env_json+=$'\n'"    \"$(json_escape "$var")\": \"$(json_escape "$val")\""
        inc env_count
    done
    _done "$env_count environment variables"
    _phase_end

    cat <<EOF
  "environment": {
    "path_count": $path_count,
    "path": [${path_json}
    ],
    "variables": {${env_json}
    }
  }
EOF
}

# ── LaunchAgents ─────────────────────────────────────────────────
collect_launch_agents() {
    _phase "LaunchAgents"
    local agents_json="" agent_count=0
    local la_dir="$HOME/Library/LaunchAgents"

    if [[ -d "$la_dir" ]]; then
        while IFS= read -r plist; do
            [[ -z "$plist" ]] && continue
            local pname; pname=$(basename "$plist" .plist)
            [[ $agent_count -gt 0 ]] && agents_json+=","
            agents_json+=" \"$(json_escape "$pname")\""
            inc agent_count
        done < <(find "$la_dir" -name "*.plist" 2>/dev/null | sort)
    fi
    _done "$agent_count user LaunchAgents"
    _phase_end

    printf '  "launch_agents": {\n'
    printf '    "count": %d,\n' "$agent_count"
    printf '    "agents": [%s ]\n' "$agents_json"
    printf '  }'
}

# ── Docker ───────────────────────────────────────────────────────
collect_docker() {
    _phase "Docker"
    if ! cmd_exists docker; then
        _skip "docker not found"; _phase_end
        echo '  "docker": { "installed": false }'; return
    fi

    local docker_version context
    docker_version=$(get_version docker --version)
    context=$(docker context show 2>/dev/null || echo "unknown")
    _info "Docker $docker_version  context=$context"

    local daemon_config
    daemon_config=$(json_file_content "$HOME/.docker/daemon.json")

    _phase_end

    cat <<EOF
  "docker": {
    "installed": true,
    "version": "$(json_escape "$docker_version")",
    "context": "$(json_escape "$context")",
    "daemon_config": $daemon_config
  }
EOF
}

# ── Claude Code config ───────────────────────────────────────────
collect_claude_config() {
    _phase "Claude Code"
    if ! cmd_exists claude; then
        _skip "claude not found"; _phase_end
        echo '  "claude_code": { "installed": false }'; return
    fi

    local claude_version
    claude_version=$(get_version claude --version)
    _info "Claude Code v$claude_version"

    # Settings (hooks, plugins, permissions, env)
    local settings_content
    settings_content=$(json_file_content "$HOME/.claude/settings.json")

    # Installed plugins — parse from installed_plugins.json
    local plugins_json="" plugin_count=0
    local plugins_file="$HOME/.claude/plugins/installed_plugins.json"
    if [[ -f "$plugins_file" ]] && cmd_exists jq; then
        while IFS= read -r pname; do
            [[ -z "$pname" ]] && continue
            [[ $plugin_count -gt 0 ]] && plugins_json+=","
            plugins_json+=" \"$(json_escape "$pname")\""
            inc plugin_count
        done < <(jq -r '.plugins | keys[]' "$plugins_file" 2>/dev/null)
    fi
    _done "$plugin_count plugins"

    # Custom agents
    local agents_json="" agent_count=0
    if [[ -d "$HOME/.claude/agents" ]]; then
        while IFS= read -r afile; do
            [[ -z "$afile" ]] && continue
            local aname; aname=$(basename "$afile" .md)
            [[ $agent_count -gt 0 ]] && agents_json+=","
            agents_json+=" \"$(json_escape "$aname")\""
            inc agent_count
        done < <(find "$HOME/.claude/agents" -name "*.md" 2>/dev/null | sort)
    fi
    [[ $agent_count -gt 0 ]] && _done "$agent_count custom agents"

    # Custom skills
    local skills_json="" skill_count=0
    if [[ -d "$HOME/.claude/skills" ]]; then
        while IFS= read -r sdir; do
            [[ -z "$sdir" ]] && continue
            local sname; sname=$(basename "$sdir")
            [[ $skill_count -gt 0 ]] && skills_json+=","
            skills_json+=" \"$(json_escape "$sname")\""
            inc skill_count
        done < <(find "$HOME/.claude/skills" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | sort)
    fi
    [[ $skill_count -gt 0 ]] && _done "$skill_count custom skills"

    _phase_end

    cat <<EOF
  "claude_code": {
    "installed": true,
    "version": "$(json_escape "$claude_version")",
    "settings": $settings_content,
    "plugins": [${plugins_json} ],
    "agents": [${agents_json} ],
    "skills": [${skills_json} ]
  }
EOF
}

# ── Codex (OpenAI) config ─────────────────────────────────────────
collect_codex_config() {
    _phase "Codex"
    if ! cmd_exists codex; then
        _skip "codex not found"; _phase_end
        echo '  "codex": { "installed": false }'; return
    fi

    local codex_version
    codex_version=$(get_version codex --version)
    _info "Codex v$codex_version"

    local config_content agents_content
    config_content=$(json_file_content "$HOME/.codex/config.toml")
    agents_content=$(json_file_content "$HOME/.codex/AGENTS.md")

    # Custom rules
    local rules_json="" rule_count=0
    if [[ -d "$HOME/.codex/rules" ]]; then
        while IFS= read -r rfile; do
            [[ -z "$rfile" ]] && continue
            local rname; rname=$(basename "$rfile")
            [[ $rule_count -gt 0 ]] && rules_json+=","
            rules_json+=" \"$(json_escape "$rname")\""
            inc rule_count
        done < <(find "$HOME/.codex/rules" -type f 2>/dev/null | sort)
    fi

    _done "Codex config captured"
    _phase_end

    cat <<EOF
  "codex": {
    "installed": true,
    "version": "$(json_escape "$codex_version")",
    "config": $config_content,
    "agents_md": $agents_content,
    "rules": [${rules_json} ]
  }
EOF
}

# ── Gemini CLI config ────────────────────────────────────────────
collect_gemini_config() {
    _phase "Gemini CLI"
    if ! cmd_exists gemini; then
        _skip "gemini not found"; _phase_end
        echo '  "gemini": { "installed": false }'; return
    fi

    local gemini_version
    gemini_version=$(get_version gemini --version)
    _info "Gemini CLI v$gemini_version"

    local settings_content gemini_md_content
    settings_content=$(json_file_content "$HOME/.gemini/settings.json")
    gemini_md_content=$(json_file_content "$HOME/.gemini/GEMINI.md")

    # Extensions
    local ext_json="" ext_count=0
    if [[ -d "$HOME/.gemini/extensions" ]]; then
        while IFS= read -r edir; do
            [[ -z "$edir" ]] && continue
            local ename; ename=$(basename "$edir")
            [[ $ext_count -gt 0 ]] && ext_json+=","
            ext_json+=" \"$(json_escape "$ename")\""
            inc ext_count
        done < <(find "$HOME/.gemini/extensions" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | sort)
    fi

    _done "Gemini config captured"
    _phase_end

    cat <<EOF
  "gemini": {
    "installed": true,
    "version": "$(json_escape "$gemini_version")",
    "settings": $settings_content,
    "gemini_md": $gemini_md_content,
    "extensions": [${ext_json} ]
  }
EOF
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

    cat <<EOF
  "macos_defaults": {
    "dock": { "autohide": $dock_autohide, "tilesize": $dock_tilesize },
    "keyboard": { "key_repeat": "$key_repeat", "initial_key_repeat": "$initial_repeat", "press_and_hold": "$press_hold" },
    "finder": { "show_all_files": "$show_all_files", "show_extensions": "$show_extensions", "show_path_bar": "$show_path_bar" }
  }
EOF
}

# ── Main ─────────────────────────────────────────────────────────
main() {
    local title_plain="  macOS Tool Inventory  v${VERSION}"
    local title_styled="  ${BOLD}${BWHT}macOS Tool Inventory${RST}  ${BOLD}v${VERSION}${RST}"

    printf '\n' >&2
    _box_rule "$CYN" '╭' '╮'
    _box_line "$CYN" "${#title_plain}" "$title_styled"
    _box_rule "$CYN" '╰' '╯'
    printf '\n' >&2

    _info "Output: ${UL}${OUTPUT_FILE}${RST}"
    _info "Timestamp: $TIMESTAMP"

    local start_time; start_time=$(date +%s)

    {
        echo "{"
        printf '  "inventory_version": "%s",\n' "$VERSION"
        printf '  "generated_at": "%s",\n' "$TIMESTAMP"

        collect_system_info;      echo ","
        collect_brew;             echo ","
        collect_node;             echo ","
        collect_go;               echo ","
        collect_rust;             echo ","
        collect_python;           echo ","
        collect_applications;     echo ","
        collect_local_bins;       echo ","
        collect_shell;            echo ","
        collect_runtimes;         echo ","
        collect_git_config;       echo ","
        collect_ssh;              echo ","
        collect_shell_configs;    echo ","
        collect_vscode;           echo ","
        collect_fonts;            echo ","
        collect_env;              echo ","
        collect_launch_agents;    echo ","
        collect_docker;           echo ","
        collect_claude_config;    echo ","
        collect_codex_config;     echo ","
        collect_gemini_config;    echo ","
        collect_macos_defaults

        echo ""
        echo "}"
    } > "$OUTPUT_FILE"

    local end_time elapsed
    end_time=$(date +%s)
    elapsed=$(( end_time - start_time ))

    # ── Summary box ─────────────────────────────
    printf '\n' >&2
    if cmd_exists jq; then
        if jq empty "$OUTPUT_FILE" 2>/dev/null; then
            local total_size size_str
            total_size=$(wc -c < "$OUTPUT_FILE" | tr -d ' ')
            size_str=$(human_size "$total_size")

            local line1_plain="  ✔  Inventory complete  (${elapsed}s, ${size_str})"
            local line1_styled="  ${BGRN}✔${RST}  ${BOLD}Inventory complete${RST}  ${DIM}(${elapsed}s, ${size_str})${RST}"
            local line2_plain="     Valid JSON written successfully"
            local line2_styled="     Valid JSON written successfully"

            _box_rule "$BGRN" '╭' '╮'
            _box_line "$BGRN" "${#line1_plain}" "$line1_styled"
            _box_line "$BGRN" "${#line2_plain}" "$line2_styled"
            _box_rule "$BGRN" '╰' '╯'
            printf "  ${DIM}${UL}%s${RST}\n\n" "$OUTPUT_FILE" >&2
        else
            local f1_plain="  ✘  JSON validation failed"
            local f1_styled="  ${RED}✘${RST}  ${BOLD}JSON validation failed${RST}"
            local fname; fname=$(basename "$OUTPUT_FILE")
            local f2_plain="     Run: jq . '${fname}'"
            local f2_styled="     ${DIM}Run: jq . '${fname}'${RST}"

            _box_rule "$RED" '╭' '╮'
            _box_line "$RED" "${#f1_plain}" "$f1_styled"
            _box_line "$RED" "${#f2_plain}" "$f2_styled"
            _box_rule "$RED" '╰' '╯'
        fi
    else
        local n1_plain="  ✔  Inventory complete  (${elapsed}s)"
        local n1_styled="  ${BGRN}✔${RST}  ${BOLD}Inventory complete${RST}  ${DIM}(${elapsed}s)${RST}"
        local n2_plain="     Install jq for JSON validation"
        local n2_styled="     ${DIM}Install jq for JSON validation${RST}"

        _box_rule "$BGRN" '╭' '╮'
        _box_line "$BGRN" "${#n1_plain}" "$n1_styled"
        _box_line "$BGRN" "${#n2_plain}" "$n2_styled"
        _box_rule "$BGRN" '╰' '╯'
        printf "  ${DIM}${UL}%s${RST}\n\n" "$OUTPUT_FILE" >&2
    fi
}

main "$@"
