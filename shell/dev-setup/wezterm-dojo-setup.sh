#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════════════
#  WezTerm Dojo · setup   (kitchen-sink installer)
#  Reproduce the WezTerm setup on a fresh Mac. Config is NOT embedded — it is
#  owned by your dotfiles repo (indrasvat/dotfiles) and linked in with GNU stow.
#
#    1. install / update WezTerm nightly
#    2. install JetBrains Mono Nerd Font
#    3. clone / fast-forward your dotfiles repo
#    4. stow the `wezterm` package  →  ~/.config/wezterm
#    5. seed WezTerm plugins (runs the stowed seed-plugins.sh)
#    6. verify
#
#  • Idempotent  — safe to run repeatedly (re-stows, fast-forwards, re-seeds).
#  • Forgiving   — non-fatal steps warn and continue; clear final summary.
#  • No admin    — installs WezTerm to ~/Applications when it can't use sudo.
#
#  Usage:  bash wezterm-dojo-setup.sh [--dry-run] [--no-color] [--force]
#                  [--skip-app] [--skip-font] [--skip-dotfiles] [--skip-plugins]
#
#  Env (override the dotfiles source):
#    DOTFILES_REPO    default git@github.com:indrasvat/dotfiles.git
#    DOTFILES_DIR     default $HOME/code/github.com/indrasvat/dotfiles
#    DOTFILES_BRANCH  default main
#    STOW_PACKAGE     default wezterm
# ════════════════════════════════════════════════════════════════════════════
set -uo pipefail

VERSION="2.0.0"
DRY=false; FORCE=false; SKIP_APP=false; SKIP_FONT=false; SKIP_DOTFILES=false; SKIP_PLUGINS=false; WANT_COLOR=auto
CFG="$HOME/.config/wezterm"
DOTFILES_REPO="${DOTFILES_REPO:-git@github.com:indrasvat/dotfiles.git}"
DOTFILES_DIR="${DOTFILES_DIR:-$HOME/code/github.com/indrasvat/dotfiles}"
DOTFILES_BRANCH="${DOTFILES_BRANCH:-main}"
STOW_PACKAGE="${STOW_PACKAGE:-wezterm}"
OK_N=0; WARN_N=0; FAIL_N=0
TMPDIRS=""
# shellcheck disable=SC2329  # invoked indirectly via trap
cleanup(){ for d in $TMPDIRS; do [ -n "$d" ] && rm -rf "$d" 2>/dev/null; done; }
trap cleanup EXIT
mktmp(){ d="$(mktemp -d 2>/dev/null || mktemp -d -t wtdojo)"; TMPDIRS="$TMPDIRS $d"; printf '%s' "$d"; }

usage(){
  cat <<EOF
WezTerm Dojo setup ${VERSION}

  bash wezterm-dojo-setup.sh [options]

Options:
  --dry-run        Show what would happen; change nothing.
  --no-color       Disable colored output.
  --force          Reinstall WezTerm nightly even if a nightly is present.
  --skip-app       Don't install/upgrade the WezTerm binary.
  --skip-font      Don't install the Nerd Font.
  --skip-dotfiles  Don't clone/pull dotfiles or stow (use config already in place).
  --skip-plugins   Don't seed plugins.
  -h, --help       This help.

Env:
  DOTFILES_REPO=${DOTFILES_REPO}
  DOTFILES_DIR=${DOTFILES_DIR}
  DOTFILES_BRANCH=${DOTFILES_BRANCH}   STOW_PACKAGE=${STOW_PACKAGE}
  NO_COLOR=1       Disable color (same as --no-color).
EOF
}

# ── args ──────────────────────────────────────────────────────────────────────
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY=true ;;
    --no-color) WANT_COLOR=never ;;
    --force) FORCE=true ;;
    --skip-app) SKIP_APP=true ;;
    --skip-font) SKIP_FONT=true ;;
    --skip-dotfiles) SKIP_DOTFILES=true ;;
    --skip-plugins) SKIP_PLUGINS=true ;;
    -h|--help) usage; exit 0 ;;
    *) printf 'Unknown option: %s\n' "$1"; usage; exit 2 ;;
  esac
  shift
done

# ── colors (Rosé Pine, 24-bit) ────────────────────────────────────────────────
init_color(){
  local use=false
  case "$WANT_COLOR" in
    never) use=false ;;
    *) if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then use=true; fi ;;
  esac
  if $use; then
    ROSE=$'\033[38;2;235;188;186m'; GOLD=$'\033[38;2;246;193;119m'
    FOAM=$'\033[38;2;156;207;216m'; IRIS=$'\033[38;2;196;167;231m'
    PINE=$'\033[38;2;49;116;143m';  LOVE=$'\033[38;2;235;111;146m'
    TEXT=$'\033[38;2;224;222;244m'; MUTED=$'\033[38;2;144;140;170m'
    BOLD=$'\033[1m'; RST=$'\033[0m'
  else
    ROSE=""; GOLD=""; FOAM=""; IRIS=""; PINE=""; LOVE=""; TEXT=""; MUTED=""; BOLD=""; RST=""
  fi
}

# ── logging (no bleeds: every line ends in RST) ───────────────────────────────
note(){  printf '%s%s%s\n'        "$MUTED" "$*" "$RST"; }
info(){  printf '   %s•%s %s%s%s\n' "$PINE" "$RST" "$TEXT" "$*" "$RST"; }
ok(){    OK_N=$((OK_N+1));   printf '   %s✓%s %s%s%s\n' "$FOAM" "$RST" "$TEXT" "$*" "$RST"; }
warn(){  WARN_N=$((WARN_N+1)); printf '   %s⚠%s %s%s%s\n' "$GOLD" "$RST" "$TEXT" "$*" "$RST"; }
fail(){  FAIL_N=$((FAIL_N+1)); printf '   %s✗%s %s%s%s\n' "$LOVE" "$RST" "$TEXT" "$*" "$RST"; }
step(){  printf '\n%s%s▸ %s%s\n'  "$BOLD" "$IRIS" "$*" "$RST"; }

hbar(){ local s="" i=0; while [ "$i" -lt "$1" ]; do s="$s$2"; i=$((i+1)); done; printf '%s' "$s"; }
BW=58
bline(){ printf '%s│%s%-*s%s│%s\n' "$ROSE" "$RST" "$BW" "$1" "$ROSE" "$RST"; }
banner(){
  local bar; bar="$(hbar "$BW" '─')"
  printf '\n%s╭%s╮%s\n' "$ROSE" "$bar" "$RST"
  bline ""
  bline "  W E Z T E R M       |  D O J O"
  bline "  reproducible setup  |  v${VERSION}"
  bline ""
  printf '%s╰%s╯%s\n' "$ROSE" "$bar" "$RST"
}
sline(){
  local plain; plain="$(printf '%s' "$1" | sed 's/\x1b\[[0-9;]*m//g')"
  printf '%s│%s%s%-*s%s%s│%s\n' "$IRIS" "$RST" "$TEXT" "$BW" "$plain" "$RST" "$IRIS" "$RST"
}

have(){ command -v "$1" >/dev/null 2>&1; }
need(){ have "$1"; }

# ── environment ───────────────────────────────────────────────────────────────
OS="other"; case "$(uname -s)" in Darwin) OS="macos" ;; Linux) OS="linux" ;; esac
ARCH="$(uname -m 2>/dev/null || echo '?')"
plugins_dir(){
  case "$OS" in
    macos) printf '%s' "$HOME/Library/Application Support/wezterm/plugins" ;;
    *)     printf '%s' "${XDG_DATA_HOME:-$HOME/.local/share}/wezterm/plugins" ;;
  esac
}
wezterm_bin(){
  if have wezterm; then command -v wezterm; return; fi
  for p in /Applications/WezTerm.app/Contents/MacOS/wezterm "$HOME/Applications/WezTerm.app/Contents/MacOS/wezterm"; do
    [ -x "$p" ] && { printf '%s' "$p"; return; }
  done
}
wezterm_version(){ local b; b="$(wezterm_bin)"; [ -n "$b" ] && "$b" --version 2>/dev/null | awk '{print $2}'; }

preflight(){
  step "Preflight"
  info "os: ${OS} (${ARCH})   bash: ${BASH_VERSION:-?}"
  local tools="git curl unzip rsync stow wezterm brew fc-list" t line=""
  for t in $tools; do
    if have "$t"; then line="$line ${FOAM}✓${RST}${MUTED}${t}${RST}"; else line="$line ${LOVE}✗${RST}${MUTED}${t}${RST}"; fi
  done
  printf '   tools:%s\n' "$line"
  info "dotfiles: ${DOTFILES_DIR}  (${DOTFILES_BRANCH})"
}

# ── step 1: WezTerm nightly ───────────────────────────────────────────────────
ensure_cli(){
  local bin="$1/Contents/MacOS/wezterm" d brew_bin dirs seen
  have wezterm && return 0
  dirs="$HOME/.local/bin"
  if have brew; then
    brew_bin="$(brew --prefix 2>/dev/null)/bin"
    dirs="$dirs $brew_bin"
  fi
  seen=" "
  local old_ifs="$IFS"; IFS=:
  for d in $PATH; do
    IFS="$old_ifs"
    case "$d" in
      /*) dirs="$dirs $d" ;;
    esac
    IFS=:
  done
  IFS="$old_ifs"
  for d in $dirs; do
    case "$seen" in *" $d "*) continue ;; esac
    seen="$seen$d "
    if [ -d "$d" ] && [ -w "$d" ]; then ln -sf "$bin" "$d/wezterm"; info "linked wezterm → $d/wezterm"
      case ":$PATH:" in *":$d:"*) : ;; *) warn "$d is not on your PATH — add it" ;; esac
      return 0
    fi
  done
  mkdir -p "$HOME/.local/bin" && ln -sf "$bin" "$HOME/.local/bin/wezterm" && warn "linked wezterm → ~/.local/bin (add it to your PATH)"
}
install_app(){
  step "WezTerm nightly"
  $SKIP_APP && { info "skipped (--skip-app)"; return 0; }
  if [ "$OS" != "macos" ]; then
    warn "automatic binary install is macOS-only — install nightly per https://wezterm.org/install (then re-run with --skip-app)"; return 0
  fi
  local ver date
  ver="$(wezterm_version)"
  date="$(printf '%s' "${ver:-0}" | grep -oE '^[0-9]+' || echo 0)"
  if [ -n "$ver" ]; then info "found WezTerm $ver"; else info "WezTerm not installed"; fi
  if [ "${date:-0}" -gt 20240203 ] 2>/dev/null && ! $FORCE; then
    ok "already a nightly build ($ver) — up to date (use --force to reinstall latest)"; return 0
  fi
  need curl || { fail "curl missing — cannot download WezTerm"; return 1; }
  need unzip || { fail "unzip missing — cannot extract WezTerm"; return 1; }
  if $DRY; then ok "[dry-run] would download nightly and install to /Applications or ~/Applications"; return 0; fi
  local tmp; tmp="$(mktmp)"
  info "downloading nightly…"
  curl -fL --progress-bar -o "$tmp/wt.zip" "https://github.com/wezterm/wezterm/releases/download/nightly/WezTerm-macos-nightly.zip" \
    || { fail "download failed"; return 1; }
  unzip -q "$tmp/wt.zip" -d "$tmp/x" || { fail "unzip failed"; return 1; }
  local app; app="$(find "$tmp/x" -maxdepth 2 -name 'WezTerm.app' -type d 2>/dev/null | head -1)"
  [ -n "$app" ] || { fail "WezTerm.app not found in archive"; return 1; }
  local newver; newver="$("$app/Contents/MacOS/wezterm" --version 2>/dev/null | awk '{print $2}')"
  local me dest=""; me="$(id -un)"
  if [ -d /Applications/WezTerm.app ] \
     && [ -z "$(find /Applications/WezTerm.app ! -user "$me" 2>/dev/null | head -1)" ] \
     && [ -w /Applications/WezTerm.app/Contents ]; then
    dest=/Applications/WezTerm.app; info "updating /Applications/WezTerm.app in place (no admin needed)"
  elif [ -w /Applications ]; then
    dest=/Applications/WezTerm.app; info "installing to /Applications"
  else
    mkdir -p "$HOME/Applications"; dest="$HOME/Applications/WezTerm.app"
    info "no admin / /Applications not writable — installing to ~/Applications"
  fi
  mkdir -p "$dest"
  if have rsync; then rsync -a --delete "$app/" "$dest/"; else cp -R "$app/." "$dest/"; fi
  xattr -dr com.apple.quarantine "$dest" 2>/dev/null || true
  ensure_cli "$dest"; hash -r 2>/dev/null || true
  ok "installed WezTerm ${newver:-nightly} → $dest"
}

# ── step 2: Nerd Font ─────────────────────────────────────────────────────────
font_present(){
  if have fc-list; then fc-list 2>/dev/null | grep -qi "JetBrainsMono Nerd Font" && return 0; fi
  local d
  for d in "$HOME/Library/Fonts" /Library/Fonts "$HOME/.local/share/fonts"; do
    [ -d "$d" ] || continue
    [ -n "$(find "$d" -maxdepth 1 -iname 'JetBrainsMono*Nerd*' 2>/dev/null | head -1)" ] && return 0
  done
  return 1
}
install_font(){
  step "JetBrains Mono Nerd Font"
  $SKIP_FONT && { info "skipped (--skip-font)"; return 0; }
  if font_present; then ok "JetBrainsMono Nerd Font already installed"; return 0; fi
  need curl || { fail "curl missing — install the font manually"; return 1; }
  need unzip || { fail "unzip missing"; return 1; }
  local fdir; case "$OS" in macos) fdir="$HOME/Library/Fonts" ;; *) fdir="$HOME/.local/share/fonts" ;; esac
  if $DRY; then ok "[dry-run] would install JetBrainsMono Nerd Font → $fdir"; return 0; fi
  mkdir -p "$fdir"
  local tmp; tmp="$(mktmp)"
  info "downloading JetBrainsMono Nerd Font…"
  curl -fL --progress-bar -o "$tmp/jbm.zip" \
    "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip" \
    || { fail "font download failed"; return 1; }
  unzip -qo "$tmp/jbm.zip" -d "$tmp/f" || { fail "font unzip failed"; return 1; }
  local n=0 f
  while IFS= read -r f; do [ -n "$f" ] && cp "$f" "$fdir"/ && n=$((n+1)); done < <(find "$tmp/f" -name '*.ttf' 2>/dev/null)
  have fc-cache && fc-cache -f "$fdir" >/dev/null 2>&1
  ok "installed $n font files → $fdir"
}

# ── step 3: dotfiles (clone / fast-forward) ───────────────────────────────────
sync_dotfiles(){
  step "Dotfiles  (${DOTFILES_REPO})"
  $SKIP_DOTFILES && { info "skipped (--skip-dotfiles)"; return 0; }
  need git || { fail "git missing — cannot manage dotfiles"; return 1; }
  if $DRY; then
    if [ -d "$DOTFILES_DIR/.git" ]; then ok "[dry-run] would fetch + ff-only pull $DOTFILES_DIR ($DOTFILES_BRANCH)"
    else ok "[dry-run] would clone $DOTFILES_REPO → $DOTFILES_DIR"; fi
    return 0
  fi
  if [ -d "$DOTFILES_DIR/.git" ]; then
    info "updating $DOTFILES_DIR"
    if git -C "$DOTFILES_DIR" fetch --quiet origin "$DOTFILES_BRANCH" 2>/dev/null; then
      git -C "$DOTFILES_DIR" checkout --quiet "$DOTFILES_BRANCH" 2>/dev/null \
        || warn "couldn't checkout $DOTFILES_BRANCH (local changes?) — leaving current branch"
      if git -C "$DOTFILES_DIR" merge --ff-only --quiet "origin/$DOTFILES_BRANCH" 2>/dev/null; then
        ok "fast-forwarded to origin/$DOTFILES_BRANCH"
      else
        warn "not fast-forwarded (diverged / dirty / offline) — using working tree as-is"
      fi
    else
      warn "fetch failed (offline or no access) — using local checkout as-is"
    fi
  else
    info "cloning $DOTFILES_REPO"
    mkdir -p "$(dirname "$DOTFILES_DIR")"
    if git clone --quiet "$DOTFILES_REPO" "$DOTFILES_DIR" 2>/dev/null; then
      ok "cloned → $DOTFILES_DIR"
    else
      fail "clone failed — check SSH key / repo access (set DOTFILES_REPO to an https URL to use a token)"; return 1
    fi
  fi
}

# ── step 4: let dotfiles install/adopt the wezterm package ────────────────────
stow_wezterm(){
  step "Dotfiles install  (${STOW_PACKAGE} → ~/.config/wezterm)"
  $SKIP_DOTFILES && { info "skipped (--skip-dotfiles)"; return 0; }
  local pkg="$DOTFILES_DIR/$STOW_PACKAGE"
  [ -d "$pkg" ] || { fail "package '$STOW_PACKAGE' not found in $DOTFILES_DIR (clone failed?)"; return 1; }
  [ -f "$DOTFILES_DIR/install.sh" ] || { fail "dotfiles installer not found: $DOTFILES_DIR/install.sh"; return 1; }
  if $DRY; then
    if NO_COLOR=1 bash "$DOTFILES_DIR/install.sh" --dry-run --packages "$STOW_PACKAGE" --force >/dev/null; then
      ok "[dry-run] dotfiles installer can adopt $STOW_PACKAGE"
    else
      fail "[dry-run] dotfiles installer rejected $STOW_PACKAGE"
      return 1
    fi
    return 0
  fi
  if NO_COLOR=1 bash "$DOTFILES_DIR/install.sh" --packages "$STOW_PACKAGE" --force >/dev/null; then
    ok "installed $STOW_PACKAGE via dotfiles installer"
  else
    fail "dotfiles installer failed for $STOW_PACKAGE"
    warn "re-run directly for details: cd \"$DOTFILES_DIR\" && ./install.sh --packages \"$STOW_PACKAGE\""
    return 1
  fi
}

# ── step 5: plugins (runs the stowed seeder) ──────────────────────────────────
seed_plugins(){
  step "Plugins  (bar · workspace-switcher · resurrect · smart-splits)"
  $SKIP_PLUGINS && { info "skipped (--skip-plugins)"; return 0; }
  need git || { fail "git missing — cannot seed plugins"; return 1; }
  if $DRY; then ok "[dry-run] would run ~/.config/wezterm/seed-plugins.sh → clones plugins into $(plugins_dir)"; return 0; fi
  local seeder="$CFG/seed-plugins.sh"
  [ -f "$seeder" ] || { fail "seed-plugins.sh not found at $seeder (stow step failed?)"; return 1; }
  if bash "$seeder" >/dev/null 2>&1; then ok "plugins seeded → $(plugins_dir)"
  else warn "plugin seeding hit an issue — re-run manually: bash ~/.config/wezterm/seed-plugins.sh"; fi
}

# ── step 6: verify + summary ──────────────────────────────────────────────────
verify(){
  step "Verify"
  local v; v="$(wezterm_version)"
  if [ -n "$v" ]; then ok "wezterm: $v"; else warn "wezterm CLI not on PATH yet (relaunch terminal / add to PATH)"; fi
  if [ -L "$CFG" ]; then ok "config: ~/.config/wezterm → $(readlink "$CFG")"
  elif [ -d "$CFG" ]; then ok "config present: $CFG ($(find "$CFG" -name '*.lua' 2>/dev/null | wc -l | tr -d ' ') lua files)"
  else warn "config not in place"; fi
  local pd; pd="$(plugins_dir)"
  if [ -d "$pd" ]; then ok "plugins: $(find "$pd" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | wc -l | tr -d ' ') in $pd"
  else note "   (plugins not seeded)"; fi
}
summary(){
  local bar; bar="$(hbar "$BW" '─')"
  printf '\n%s╭%s╮%s\n' "$IRIS" "$bar" "$RST"
  sline "  Summary"
  sline "  ${OK_N} ok  |  ${WARN_N} warnings  |  ${FAIL_N} failed"
  sline ""
  if [ "$FAIL_N" -eq 0 ]; then
    sline "  Done. Relaunch WezTerm (Cmd-Q, reopen)."
    sline "  Leader = CTRL-Space  |  cheat-sheet: LEADER then k"
  else
    sline "  Finished with errors — see the ✗ lines above."
  fi
  printf '%s╰%s╯%s\n' "$IRIS" "$bar" "$RST"
  $DRY && note "(dry-run — nothing was changed)"
}

main(){
  init_color
  banner
  preflight
  install_app     || true
  install_font    || true
  sync_dotfiles   || true
  stow_wezterm    || true
  seed_plugins    || true   # after stow — the seeder ships in the dotfiles package
  verify          || true
  summary
  [ "$FAIL_N" -eq 0 ]
}
main "$@"
exit $?
