#!/usr/bin/env bash
set -euo pipefail

SCRIPT_NAME="$(basename "$0")"

# Defaults
NONINTERACTIVE=0
ACTION=""           # "install" or "uninstall"
DO_GBDK=0
DO_RGBDS=0
DO_EMULATORS=0
ALL_COMPONENTS=0
GBDK_VERSION="4.4.0"   # Latest stable as of 2025-05-19
GBDK_REPO="gbdk-2020/gbdk-2020"
GBDK_INSTALL_DIR_DEFAULT="/opt/gbdk-2020"
GBDK_INSTALL_DIR="$GBDK_INSTALL_DIR_DEFAULT"
MODIFY_SHELL_RC=0

# Emoji helpers
EMOJI_INFO="ℹ️"
EMOJI_OK="✅"
EMOJI_WARN="⚠️"
EMOJI_ERR="❌"
EMOJI_STEP="👉"

log_info()  { printf "%s %s\n" "$EMOJI_INFO" "$*"; }
log_ok()    { printf "%s %s\n" "$EMOJI_OK" "$*"; }
log_warn()  { printf "%s %s\n" "$EMOJI_WARN" "$*"; }
log_err()   { printf "%s %s\n" "$EMOJI_ERR" "$*" >&2; }

usage() {
  cat <<EOF
Game Boy dev setup for macOS

Usage:
  $SCRIPT_NAME [--install|--uninstall] [options]

Actions:
  --install             Install selected components
  --uninstall           Uninstall selected components

Components (default with --install is: --gbdk --rgbds --emulators):
  --gbdk                Manage GBDK-2020 (C toolchain)
  --rgbds               Manage RGBDS (assembly toolchain, via Homebrew)
  --emulators           Manage SameBoy + mGBA (via Homebrew)

General options:
  --all                 Apply action to all components
  --gbdk-dir DIR        Install GBDK into DIR (default: $GBDK_INSTALL_DIR_DEFAULT)
  --modify-shell-rc     Automatically add PATH config for GBDK to your shell rc
  --non-interactive     No prompts; assume "yes" for requested actions
  -h, --help            Show this help

Examples:
  $SCRIPT_NAME --install --all
  $SCRIPT_NAME --install --gbdk --rgbds --non-interactive
  $SCRIPT_NAME --uninstall --all --non-interactive

EOF
}

confirm() {
  local msg="$1"
  if (( NONINTERACTIVE )); then
    # Called only when user explicitly requested an action.
    return 0
  fi
  printf "%s %s [y/N]: " "$EMOJI_STEP" "$msg"
  read -r answer || return 1
  case "$answer" in
    [Yy]*) return 0 ;;
    *)     return 1 ;;
  esac
}

require_macos() {
  if [[ "$(uname -s)" != "Darwin" ]]; then
    log_err "This script is intended for macOS."
    exit 1
  fi
}

detect_brew() {
  if command -v brew >/dev/null 2>&1; then
    return 0
  fi
  # Try common Homebrew locations
  if [[ -x "/opt/homebrew/bin/brew" ]]; then
    export PATH="/opt/homebrew/bin:$PATH"
    return 0
  elif [[ -x "/usr/local/bin/brew" ]]; then
    export PATH="/usr/local/bin:$PATH"
    return 0
  fi
  return 1
}

ensure_brew() {
  if detect_brew; then
    return 0
  fi
  log_warn "Homebrew not found. It is required for RGBDS and emulator installs."
  if ! confirm "Install Homebrew now from https://brew.sh ?"; then
    log_err "Homebrew is required. Aborting."
    exit 1
  fi
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  if ! detect_brew; then
    log_err "Homebrew installation seems to have failed or is not on PATH."
    exit 1
  fi
  log_ok "Homebrew installed."
}

# --- GBDK helpers -----------------------------------------------------------

get_gbdk_asset_url() {
  local arch="$1"
  local tag="$GBDK_VERSION"
  local api="https://api.github.com/repos/${GBDK_REPO}/releases/tags/${tag}"

  log_info "Fetching GBDK-2020 $tag release metadata ..."
  local json
  if ! json="$(curl -fsSL "$api")"; then
    log_err "Unable to fetch GBDK-2020 release data from GitHub."
    return 1
  fi

  local pattern
  case "$arch" in
    arm64)   pattern="MacOS.*ARM" ;;
    x86_64)  pattern="MacOS.*Intel" ;;
    *)       log_err "Unsupported architecture for GBDK: $arch"; return 1 ;;
  esac

  # Match each asset: pair "name" with its following "browser_download_url"
  local url
  url="$(
    printf '%s\n' "$json" | awk -v pat="$pattern" '
      /"name":/ {
        name=$2
        gsub(/[",]/, "", name)
      }
      /"browser_download_url":/ {
        url=$2
        gsub(/[",]/, "", url)
        if (name ~ pat) {
          print url
          exit
        }
      }
    '
  )"

  if [[ -z "${url:-}" ]]; then
    log_err "Could not find a macOS GBDK-2020 $tag asset (pattern: $pattern)."
    return 1
  fi

  printf '%s\n' "$url"
}

install_gbdk() {
  require_macos

  local arch
  arch="$(uname -m)"

  log_info "Preparing to install GBDK-2020 ${GBDK_VERSION} for $arch into: $GBDK_INSTALL_DIR"

  local url
  if ! url="$(get_gbdk_asset_url "$arch")"; then
    log_err "Failed to determine correct GBDK download URL."
    return 1
  fi

  local parent_dir
  parent_dir="$(dirname "$GBDK_INSTALL_DIR")"
  local sudo_cmd=""
  if [[ ! -d "$parent_dir" || ! -w "$parent_dir" ]]; then
    sudo_cmd="sudo"
  fi

  $sudo_cmd mkdir -p "$GBDK_INSTALL_DIR"

  local tmpfile
  tmpfile="$(mktemp "/tmp/gbdk-XXXXXX.tar.gz")"

  log_info "Downloading GBDK-2020 from: $url"
  if ! curl -fsSL -o "$tmpfile" "$url"; then
    log_err "Failed to download GBDK-2020 archive."
    rm -f "$tmpfile"
    return 1
  fi

  log_info "Extracting into $GBDK_INSTALL_DIR ..."
  if ! $sudo_cmd tar -xzf "$tmpfile" -C "$GBDK_INSTALL_DIR" --strip-components=1; then
    log_err "Extraction failed."
    rm -f "$tmpfile"
    return 1
  fi

  rm -f "$tmpfile"
  log_ok "GBDK-2020 installed at $GBDK_INSTALL_DIR"

  if (( MODIFY_SHELL_RC )); then
    configure_shell_rc_for_gbdk
  else
    log_info "Add this to your shell config (~/.zshrc or ~/.bashrc):"
    printf '  export GBDK_HOME="%s"\n' "$GBDK_INSTALL_DIR"
    # shellcheck disable=SC2016 # Intentional: $GBDK_HOME should appear literally
    printf '  export PATH="$GBDK_HOME/bin:$PATH"\n'
  fi
}

configure_shell_rc_for_gbdk() {
  local line1="export GBDK_HOME=\"$GBDK_INSTALL_DIR\""
  # shellcheck disable=SC2016 # Intentional: $GBDK_HOME should appear literally
  local line2='export PATH="$GBDK_HOME/bin:$PATH"'

  local shell_rc=""
  if [[ -n "${ZDOTDIR-}" && -w "$ZDOTDIR/.zshrc" ]]; then
    shell_rc="$ZDOTDIR/.zshrc"
  elif [[ -w "$HOME/.zshrc" ]]; then
    shell_rc="$HOME/.zshrc"
  elif [[ -w "$HOME/.bashrc" ]]; then
    shell_rc="$HOME/.bashrc"
  elif [[ -w "$HOME/.bash_profile" ]]; then
    shell_rc="$HOME/.bash_profile"
  fi

  if [[ -z "$shell_rc" ]]; then
    log_warn "Could not find a writable shell rc file; skipping auto PATH config."
    return
  fi

  if ! grep -q 'GBDK_HOME' "$shell_rc"; then
    {
      printf '\n# Game Boy dev (GBDK-2020)\n'
      printf '%s\n' "$line1"
      printf '%s\n' "$line2"
    } >> "$shell_rc"
    log_ok "Updated $shell_rc with GBDK PATH configuration."
  else
    log_info "GBDK PATH config already present in $shell_rc, skipping."
  fi
}

uninstall_gbdk() {
  if [[ ! -d "$GBDK_INSTALL_DIR" ]]; then
    log_info "GBDK-2020 not found at $GBDK_INSTALL_DIR, nothing to remove."
    return 0
  fi
  if ! confirm "Remove GBDK-2020 directory at $GBDK_INSTALL_DIR ?"; then
    log_info "Skipping GBDK removal."
    return 0
  fi
  local sudo_cmd=""
  local parent_dir
  parent_dir="$(dirname "$GBDK_INSTALL_DIR")"
  if [[ ! -w "$GBDK_INSTALL_DIR" || ! -w "$parent_dir" ]]; then
    sudo_cmd="sudo"
  fi
  $sudo_cmd rm -rf "$GBDK_INSTALL_DIR"
  log_ok "Removed GBDK-2020 from $GBDK_INSTALL_DIR (you may want to clean PATH entries manually)."
}

# --- RGBDS helpers ----------------------------------------------------------

install_rgbds() {
  require_macos
  ensure_brew

  if brew list rgbds >/dev/null 2>&1; then
    log_info "RGBDS already installed. Upgrading to latest if needed ..."
    brew upgrade rgbds || log_warn "brew upgrade rgbds failed or was not needed."
  else
    log_info "Installing RGBDS via Homebrew ..."
    brew install rgbds
  fi
  log_ok "RGBDS installed."
}

uninstall_rgbds() {
  if ! detect_brew || ! brew list rgbds >/dev/null 2>&1; then
    log_info "RGBDS is not installed via Homebrew; nothing to remove."
    return 0
  fi
  if ! confirm "Uninstall RGBDS (brew uninstall rgbds)?"; then
    log_info "Skipping RGBDS removal."
    return 0
  fi
  brew uninstall rgbds
  log_ok "RGBDS uninstalled."
}

# --- Emulator helpers -------------------------------------------------------

install_emulators() {
  require_macos
  ensure_brew

  # SameBoy (debug-friendly emulator)
  if brew list --cask sameboy >/dev/null 2>&1; then
    log_info "SameBoy already installed (cask)."
  else
    log_info "Installing SameBoy via Homebrew cask ..."
    brew install --cask sameboy
  fi

  # mGBA (multi-system emulator; good GB/GBC implementation)
  if brew list mgba >/dev/null 2>&1 || brew list --cask mgba-app >/dev/null 2>&1; then
    log_info "mGBA already installed."
  else
    if brew info --cask mgba-app >/dev/null 2>&1; then
      log_info "Installing mGBA (app) via Homebrew cask ..."
      brew install --cask mgba-app
    else
      log_info "Installing mGBA via Homebrew formula ..."
      brew install mgba
    fi
  fi

  log_ok "Emulators installed (SameBoy + mGBA)."
}

uninstall_emulators() {
  if detect_brew; then
    local any=0
    if brew list --cask sameboy >/dev/null 2>&1 || brew list sameboy >/dev/null 2>&1; then
      any=1
    fi
    if brew list mgba >/dev/null 2>&1 || brew list --cask mgba-app >/dev/null 2>&1; then
      any=1
    fi
    if (( any == 0 )); then
      log_info "No managed emulators (SameBoy/mGBA) found; nothing to remove."
      return 0
    fi
    if ! confirm "Uninstall SameBoy and mGBA installed via Homebrew?"; then
      log_info "Skipping emulator removal."
      return 0
    fi
    brew uninstall --cask sameboy  >/dev/null 2>&1 || true
    brew uninstall sameboy         >/dev/null 2>&1 || true
    brew uninstall --cask mgba-app >/dev/null 2>&1 || true
    brew uninstall mgba            >/dev/null 2>&1 || true
    log_ok "Requested emulators have been removed (where present)."
  else
    log_info "Homebrew not found; assuming emulators not managed by this script."
  fi
}

# --- Argument parsing -------------------------------------------------------

parse_args() {
  if [[ "$#" -eq 0 ]]; then
    usage
    exit 1
  fi

  while [[ "$#" -gt 0 ]]; do
    case "$1" in
      --install)
        ACTION="install"
        ;;
      --uninstall)
        ACTION="uninstall"
        ;;
      --gbdk)
        DO_GBDK=1
        ;;
      --rgbds)
        DO_RGBDS=1
        ;;
      --emulators)
        DO_EMULATORS=1
        ;;
      --all)
        ALL_COMPONENTS=1
        ;;
      --gbdk-dir)
        shift
        if [[ "$#" -eq 0 ]]; then
          log_err "--gbdk-dir requires a value"
          exit 1
        fi
        GBDK_INSTALL_DIR="$1"
        ;;
      --modify-shell-rc)
        MODIFY_SHELL_RC=1
        ;;
      --non-interactive)
        NONINTERACTIVE=1
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        log_err "Unknown argument: $1"
        usage
        exit 1
        ;;
    esac
    shift
  done

  if [[ -z "$ACTION" ]]; then
    log_err "You must specify --install or --uninstall."
    usage
    exit 1
  fi

  if (( ALL_COMPONENTS )); then
    DO_GBDK=1
    DO_RGBDS=1
    DO_EMULATORS=1
  fi

  if (( !DO_GBDK && !DO_RGBDS && !DO_EMULATORS )); then
    if [[ "$ACTION" == "install" ]]; then
      DO_GBDK=1
      DO_RGBDS=1
      DO_EMULATORS=1
      log_info "No components specified; defaulting to --gbdk --rgbds --emulators."
    else
      log_err "For --uninstall you must specify components (e.g. --gbdk, --rgbds, --emulators, or --all)."
      usage
      exit 1
    fi
  fi
}

main() {
  parse_args "$@"
  require_macos

  log_info "Starting Game Boy dev $ACTION ..."
  if [[ "$ACTION" == "install" ]]; then
    (( DO_GBDK ))      && install_gbdk
    (( DO_RGBDS ))     && install_rgbds
    (( DO_EMULATORS )) && install_emulators
    log_ok "Install completed."
  else
    (( DO_GBDK ))      && uninstall_gbdk
    (( DO_RGBDS ))     && uninstall_rgbds
    (( DO_EMULATORS )) && uninstall_emulators
    log_ok "Uninstall completed."
  fi
}

main "$@"