#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# Modern Emacs setup for macOS (safe + forgiving).
# - Installs Homebrew (optional), Emacs 30.x, and useful CLI tools
# - Installs this repo's Emacs config into ~/.emacs.d with backups
# - Bootstraps packages (and optional tree-sitter grammars) in batch
# - Never deletes your old config; it is moved to a timestamped backup

SCRIPT_NAME="$(basename "$0")"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

YES=0
DRY_RUN=0
SKIP_BREW=0
SKIP_FONTS=0
SKIP_LSPS=0
SETUP_DAEMON="ask"   # ask|yes|no
NO_TREESIT=0
NO_OPTIONAL=0
TARGET_DIR="${HOME}/.emacs.d"

log()  { printf '%s\n' "$*"; }
warn() { printf 'WARN: %s\n' "$*" >&2; }
die()  { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<EOF
Usage: ${SCRIPT_NAME} [options]

Installs/sets up a modern, reliable Emacs on macOS using Homebrew, and
installs this repo's config into:
  ${TARGET_DIR}

Options:
  -y, --yes              Non-interactive; assume "yes" to prompts
  --dry-run              Print what would happen, but change nothing
  --skip-brew            Don't install Homebrew or brew packages
  --skip-fonts           Don't install fonts (JetBrainsMono Nerd Font, Inter)
  --skip-lsps            Don't install language servers/tooling
  --daemon               Set up Emacs as a background daemon (brew services)
  --no-daemon            Do not set up daemon
  --no-treesit           Don't install tree-sitter grammars during bootstrap
  --no-optional          Don't install optional packages (icons, terraform-mode)
  --target DIR           Install config into DIR (default: ~/.emacs.d)
  -h, --help             Show this help

Examples:
  ./${SCRIPT_NAME}
  ./${SCRIPT_NAME} --yes --daemon
  ./${SCRIPT_NAME} --skip-fonts --skip-lsps
EOF
}

run() {
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    printf '+'
    printf ' %q' "$@"
    printf '\n'
    return 0
  fi
  "$@"
}

prompt_yn() {
  local prompt="$1"
  local default="${2:-y}" # y|n

  if [[ "${YES}" -eq 1 ]]; then
    return 0
  fi
  if [[ ! -t 0 ]]; then
    [[ "${default}" == "y" ]] && return 0 || return 1
  fi

  local hint="[y/N]"
  [[ "${default}" == "y" ]] && hint="[Y/n]"

  while true; do
    read -r -p "${prompt} ${hint} " reply || return 1
    reply="${reply:-$default}"
    case "${reply}" in
      y|Y|yes|YES) return 0 ;;
      n|N|no|NO)   return 1 ;;
      *)          echo "Please answer y or n." ;;
    esac
  done
}

require_macos() {
  [[ "$(uname -s)" == "Darwin" ]] || die "This script is for macOS (Darwin) only."
  [[ -n "${HOME:-}" ]] || die "\$HOME is not set."
  [[ "$(id -u)" -ne 0 ]] || die "Do not run as root."
}

require_xcode_clt() {
  if xcode-select -p >/dev/null 2>&1; then
    return 0
  fi
  warn "Xcode Command Line Tools are required (for Homebrew and tree-sitter grammars)."
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    log "+ xcode-select --install"
    return 0
  fi
  if prompt_yn "Open the installer now (xcode-select --install)?" "y"; then
    run xcode-select --install || true
    die "Install Xcode Command Line Tools, then re-run: ./${SCRIPT_NAME}"
  fi
  die "Install Xcode Command Line Tools, then re-run: ./${SCRIPT_NAME}"
}

BREW=""
ensure_brew() {
  if [[ "${SKIP_BREW}" -eq 1 ]]; then
    return 0
  fi

  if command -v brew >/dev/null 2>&1; then
    BREW="$(command -v brew)"
  elif [[ -x /opt/homebrew/bin/brew ]]; then
    BREW="/opt/homebrew/bin/brew"
  elif [[ -x /usr/local/bin/brew ]]; then
    BREW="/usr/local/bin/brew"
  else
    log "Homebrew is not installed."
    if ! prompt_yn "Install Homebrew (recommended)?" "y"; then
      die "Homebrew not installed. Re-run with --skip-brew if you want to manage installs yourself."
    fi
    local install_url="https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh"
    if [[ "${DRY_RUN}" -eq 1 ]]; then
      log "+ /bin/bash -c \"\\$(curl -fsSL ${install_url})\""
      # Guess a reasonable brew path for subsequent dry-run output.
      if [[ "$(uname -m)" == "arm64" ]]; then
        BREW="/opt/homebrew/bin/brew"
      else
        BREW="/usr/local/bin/brew"
      fi
    else
      /bin/bash -c "$(curl -fsSL "${install_url}")"
      if [[ -x /opt/homebrew/bin/brew ]]; then
        BREW="/opt/homebrew/bin/brew"
      elif [[ -x /usr/local/bin/brew ]]; then
        BREW="/usr/local/bin/brew"
      else
        die "Homebrew installation completed but brew was not found on PATH."
      fi
    fi
  fi

  # Ensure brew is on PATH for the remainder of this script.
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    log "+ eval \"\$(${BREW} shellenv)\""
  else
    eval "$("${BREW}" shellenv)"
  fi
}

brew_install() {
  [[ "${SKIP_BREW}" -eq 1 ]] && return 0
  [[ -n "${BREW}" ]] || die "Internal error: brew not initialized."

  run "${BREW}" update

  local -a core_formulae=(
    emacs
    ripgrep
    fd
    enchant
    gnupg
  )

  log "Installing core packages (may take a bit)…"
  run "${BREW}" install "${core_formulae[@]}"

  if [[ "${SKIP_LSPS}" -eq 0 ]]; then
    local -a lsp_formulae=(
      gopls
      pyright
      rust-analyzer
      bash-language-server
      yaml-language-server
      dockerfile-language-server
      terraform-ls
      typescript-language-server
      vscode-langservers-extracted
      sql-language-server
      shellcheck
      shfmt
    )
    log "Installing language servers & tooling…"
    run "${BREW}" install "${lsp_formulae[@]}"
  fi

  if [[ "${SKIP_FONTS}" -eq 0 ]]; then
    log "Installing fonts (JetBrainsMono Nerd Font, Inter)…"
    run "${BREW}" tap homebrew/cask-fonts
    run "${BREW}" install --cask font-jetbrains-mono-nerd-font font-inter
  fi
}

BACKUP_DIR=""
RESTORE_NEEDED=0
cleanup_on_error() {
  local exit_code=$?
  if [[ $exit_code -ne 0 && "${RESTORE_NEEDED}" -eq 1 ]]; then
    warn "An error occurred; attempting to restore your previous Emacs config from:"
    warn "  ${BACKUP_DIR}"

    if [[ -e "${BACKUP_DIR}/.emacs.d" ]]; then
      if [[ -e "${TARGET_DIR}" ]]; then
        run mv "${TARGET_DIR}" "${TARGET_DIR}.failed-$(date +%Y%m%d-%H%M%S)" || true
      fi
      run mv "${BACKUP_DIR}/.emacs.d" "${TARGET_DIR}" || true
    fi
    if [[ -e "${BACKUP_DIR}/.emacs" ]]; then
      run mv "${BACKUP_DIR}/.emacs" "${HOME}/.emacs" || true
    fi
    if [[ -e "${BACKUP_DIR}/.emacs.el" ]]; then
      run mv "${BACKUP_DIR}/.emacs.el" "${HOME}/.emacs.el" || true
    fi
  fi
  exit $exit_code
}
trap cleanup_on_error EXIT

copy_tree() {
  local src="$1"
  local dest="$2"
  if command -v rsync >/dev/null 2>&1; then
    run rsync -a "${src}/" "${dest}/"
  else
    warn "rsync not found; falling back to cp -R."
    run cp -R "${src}/." "${dest}/"
  fi
}

install_config() {
  local src="${SCRIPT_DIR}/emacs.d"
  [[ -d "${src}" ]] || die "Missing config directory: ${src}"

  local stamp
  stamp="$(date +%Y%m%d-%H%M%S)"
  BACKUP_DIR="${HOME}/.modern-emacs-backups/${stamp}"

  if [[ -e "${TARGET_DIR}" || -e "${HOME}/.emacs" || -e "${HOME}/.emacs.el" ]]; then
    log "Existing Emacs config detected."
    log "A backup will be created at:"
    log "  ${BACKUP_DIR}"
    if ! prompt_yn "Proceed and replace your active Emacs config (safe backup will be kept)?" "y"; then
      die "Aborted by user."
    fi
    run mkdir -p "${BACKUP_DIR}"

    # From this point on, if anything fails, restore what we moved.
    RESTORE_NEEDED=1

    if [[ -e "${TARGET_DIR}" ]]; then
      run mv "${TARGET_DIR}" "${BACKUP_DIR}/.emacs.d"
    fi
    if [[ -e "${HOME}/.emacs" ]]; then
      run mv "${HOME}/.emacs" "${BACKUP_DIR}/.emacs"
    fi
    if [[ -e "${HOME}/.emacs.el" ]]; then
      run mv "${HOME}/.emacs.el" "${BACKUP_DIR}/.emacs.el"
    fi
  fi

  # Stage and install atomically-ish.
  local tmp
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    tmp="<tmpdir>"
  else
    tmp="$(mktemp -d)"
  fi

  local parent
  parent="$(dirname "${TARGET_DIR}")"

  if [[ "${DRY_RUN}" -eq 1 ]]; then
    log "+ mkdir -p \"${parent}\""
    log "+ mkdir -p \"${tmp}/.emacs.d\""
    log "+ rsync -a \"${src}/\" \"${tmp}/.emacs.d/\"   # or cp -R if rsync missing"
    log "+ mv \"${tmp}/.emacs.d\" \"${TARGET_DIR}\""
  else
    mkdir -p "${parent}"
    mkdir -p "${tmp}/.emacs.d"
    copy_tree "${src}" "${tmp}/.emacs.d"
    mv "${tmp}/.emacs.d" "${TARGET_DIR}"
    rmdir "${tmp}" 2>/dev/null || true
  fi

  if [[ "${DRY_RUN}" -eq 1 ]]; then
    log "Config would be installed to: ${TARGET_DIR}"
  else
    log "Config installed to: ${TARGET_DIR}"
  fi
  if [[ "${RESTORE_NEEDED}" -eq 1 ]]; then
    if [[ "${DRY_RUN}" -eq 1 ]]; then
      log "Backup would be saved at: ${BACKUP_DIR}"
    else
      log "Backup saved at:          ${BACKUP_DIR}"
    fi
  fi
}

bootstrap_emacs() {
  local emacs_bin="emacs"
  if ! command -v "${emacs_bin}" >/dev/null 2>&1; then
    if [[ "${SKIP_BREW}" -eq 0 && -n "${BREW}" ]]; then
      local prefix
      prefix="$("${BREW}" --prefix emacs 2>/dev/null || true)"
      if [[ -n "${prefix}" && -x "${prefix}/bin/emacs" ]]; then
        emacs_bin="${prefix}/bin/emacs"
      fi
    fi
  fi

  if [[ "${DRY_RUN}" -ne 1 ]]; then
    command -v "${emacs_bin}" >/dev/null 2>&1 || die "Emacs not found. Install it, or re-run without --skip-brew."
  fi

  local -a envcmd=()
  if [[ "${NO_TREESIT}" -eq 1 ]]; then
    envcmd+=(MODERN_EMACS_BOOTSTRAP_NO_TREESIT=1)
  fi
  if [[ "${NO_OPTIONAL}" -eq 1 ]]; then
    envcmd+=(MODERN_EMACS_BOOTSTRAP_NO_OPTIONAL=1)
  fi

  log "Bootstrapping Emacs packages (this may take a few minutes on first run)…"
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    run env "${envcmd[@]}" "${emacs_bin}" --batch -Q -l "${TARGET_DIR}/bootstrap.el"
  else
    env "${envcmd[@]}" "${emacs_bin}" --batch -Q -l "${TARGET_DIR}/bootstrap.el"
  fi
}

setup_daemon() {
  [[ "${SKIP_BREW}" -eq 1 ]] && return 0
  [[ -n "${BREW}" ]] || return 0

  local do_it=0
  case "${SETUP_DAEMON}" in
    yes) do_it=1 ;;
    no)  do_it=0 ;;
    ask)
      if prompt_yn "Set up Emacs daemon via 'brew services' (fast emacsclient launches)?" "n"; then
        do_it=1
      fi
      ;;
    *) die "Internal error: invalid SETUP_DAEMON value" ;;
  esac

  [[ $do_it -eq 1 ]] || return 0
  log "Enabling Emacs daemon (brew services)…"
  run "${BREW}" services restart emacs || run "${BREW}" services start emacs
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    log "Daemon would be enabled. Use 'emacsclient -c' for GUI frames, or 'emacsclient -t' in terminal."
  else
    log "Daemon enabled. Use 'emacsclient -c' for GUI frames, or 'emacsclient -t' in terminal."
  fi
}

main() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -y|--yes) YES=1; shift ;;
      --dry-run) DRY_RUN=1; shift ;;
      --skip-brew) SKIP_BREW=1; shift ;;
      --skip-fonts) SKIP_FONTS=1; shift ;;
      --skip-lsps) SKIP_LSPS=1; shift ;;
      --daemon) SETUP_DAEMON="yes"; shift ;;
      --no-daemon) SETUP_DAEMON="no"; shift ;;
      --no-treesit) NO_TREESIT=1; shift ;;
      --no-optional) NO_OPTIONAL=1; shift ;;
      --target) TARGET_DIR="${2:-}"; [[ -n "${TARGET_DIR}" ]] || die "--target requires a directory"; shift 2 ;;
      -h|--help) usage; exit 0 ;;
      *) die "Unknown option: $1 (use --help)" ;;
    esac
  done

  require_macos
  require_xcode_clt

  ensure_brew
  brew_install

  install_config
  bootstrap_emacs
  setup_daemon

  log ""
  log "Done."
  log "Next:"
  log "  - Launch Emacs: emacs"
  log "  - Or (recommended) start a frame from the daemon: emacsclient -c"
  log "  - If you want to restore your previous config, see the backup directory printed above."
}

main "$@"
