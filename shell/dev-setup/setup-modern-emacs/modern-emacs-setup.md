# Modern Emacs on macOS (December 2025)

Goal: install, setup, and configure a **modern, user-friendly, batteries-included, aesthetically pleasing, forgiving, and reliable** Emacs on a Mac — suitable for a **principal backend engineer** — without leaving the machine in a broken state.

This repo provides:
- `setup-modern-emacs.sh`: an end-to-end installer with safety nets and automatic backups.
- `emacs.d/`: a curated Emacs configuration (Emacs 30.x era) focused on stability and “modern defaults”.

---

## Clarifying questions (you can answer later)

The installer defaults are sane, but your answers can refine the setup:
1. **Keybindings**: do you want **pure Emacs keys**, **Vim (Evil)**, or **hybrid**?
2. **Primary languages**: Go / Java / Kotlin / Python / Rust / TS / Terraform / SQL / … ?
3. **AI provider**: OpenAI / Anthropic / local (Ollama) / GitHub Copilot?
4. **How you launch Emacs**: mostly **terminal** (`emacs -nw`) or **GUI + daemon** (`emacsclient -c`)?

This guide proceeds with defaults: **Emacs keybindings**, **GUI+terminal friendly**, **Eglot (built-in LSP)**, **tree-sitter**, and **gptel** for AI chat.

---

## TL;DR (recommended)

From this repo:

```bash
./setup-modern-emacs.sh
```

What it does (safe defaults):
- Installs **Homebrew Emacs** (stable) and a small set of reliable CLI tools.
- Installs fonts for a great look (JetBrains Mono Nerd Font + Inter).
- Installs common language servers (optional; enabled by default).
- Installs this repo’s Emacs config into `~/.emacs.d`, with timestamped backups.
- Bootstraps Emacs packages and installs common tree-sitter grammars.

If you want “no prompts”:

```bash
./setup-modern-emacs.sh --yes
```

If you want the fast-start daemon workflow:

```bash
./setup-modern-emacs.sh --yes --daemon
```

---

## Why this setup (design choices, Dec 2025)

### 1) Emacs version & distribution
**Recommendation**: Homebrew `emacs` (core formula), which is **Emacs 30.2** as of **2025-12-16**.

Why:
- Stable, widely used on macOS.
- Includes modern features (tree-sitter integration, improved scrolling, native compilation support depending on build).
- Easy updates via `brew upgrade`.

### 2) “Modern” completion & navigation stack
This config uses the widely adopted modern Emacs UX stack:
- **Vertico**: minibuffer completion UI
- **Orderless**: flexible matching
- **Marginalia**: rich annotations
- **Consult**: powerful search/navigation commands (ripgrep integration, buffer switching, etc.)
- **Embark**: context actions everywhere
- **Corfu + Cape**: in-buffer completions via `completion-at-point` (CAPF)

Why:
- Very popular in 2023–2025 Emacs communities.
- Minimal “framework magic”; excellent discoverability and ergonomics.
- Reliable and fast, with strong upstream maintenance.

### 3) LSP choice: Eglot (built-in)
**Eglot** is built into Emacs and is the most conservative/reliable way to use LSP in Emacs.

Why:
- Lower moving parts than `lsp-mode`.
- Excellent for backend engineer workflows (jump-to-def, rename, diagnostics, formatting).
- Works great with Corfu/Cape and Emacs’ built-in xref, eldoc, etc.

### 4) Tree-sitter
Tree-sitter provides modern parsing-based highlighting and structural editing capabilities for many languages.

This setup:
- Installs a curated set of grammars during bootstrap (optional).
- Remaps classic modes → `*-ts-mode` when grammars are available (safe conditional remaps).

### 5) Spellchecking: Jinx
**Jinx** (GNU ELPA) is a modern spell-checker that uses **Enchant**. It’s fast and pleasant compared to older ispell/hunspell workflows.

### 6) Terminal inside Emacs: EAT
**EAT** is reliable and avoids native module compilation issues common with vterm on macOS.

### 7) AI: gptel
**gptel** (NonGNU ELPA) is currently one of the most reliable and actively maintained Emacs LLM clients.

This config:
- Enables `gptel` commands.
- Reads API keys from environment variables (no secrets stored in config).
- Supports OpenAI by default; switches to Anthropic backend when only `ANTHROPIC_API_KEY` is present.

---

## Popular “flavors” of Emacs (and when to choose them)

These are still the dominant “packaged” experiences as of late 2025:

### Doom Emacs
- Pros: fast, polished, reproducible package management, great defaults, huge community.
- Cons: opinionated, macros/framework, commonly assumes/encourages Evil (Vim) workflow.
- Choose if: you want a “distribution” and don’t mind adopting Doom conventions.

### Spacemacs
- Pros: very beginner-friendly for Vim users; strong documentation; “layers” abstraction.
- Cons: heavier; slower than Doom; more framework to learn.
- Choose if: you want the classic “Emacs as a platform” distribution feel.

### Purcell’s “reasonable Emacs config”
- Pros: pragmatic, long-lived, moderate customization; good for developers.
- Cons: still a “personal config” (you’ll adopt someone’s opinions).
- Choose if: you want a mature, non-framework baseline that’s been battle-tested for years.

### Crafted Emacs / System Crafters ecosystem
- Pros: educational, modular, closer to vanilla; great learning path.
- Cons: intentionally not “kitchen sink”; you add what you need.
- Choose if: you want a guided “build your own” approach.

This repo’s approach is: **vanilla Emacs + modern packages + conservative defaults**, with automation and safety nets.

---

## Prerequisites

- macOS (Darwin)
- Network access (to fetch Homebrew, Emacs packages, and optional tree-sitter grammars)
- **Xcode Command Line Tools** (required for Homebrew; also needed to compile tree-sitter grammars):
  ```bash
  xcode-select -p
  ```
  If missing:
  ```bash
  xcode-select --install
  ```

---

## What the installer changes (safety-first)

The script is designed to be “idiot-proof”:
- **Never deletes** your existing Emacs config.
- If `~/.emacs.d` or `~/.emacs` exists, it moves them to:
  - `~/.modern-emacs-backups/<timestamp>/…`
- Installs a fresh config into `~/.emacs.d`.
- If the script fails after replacing your config, it attempts to **restore** the previous config automatically.
- Does **not** change system defaults (no `EDITOR`, no shell rc rewriting beyond Homebrew’s own installer).

---

## Running the installer

### Basic
```bash
./setup-modern-emacs.sh
```

### Recommended non-interactive run
```bash
./setup-modern-emacs.sh --yes
```

### Skip language servers/tooling
```bash
./setup-modern-emacs.sh --skip-lsps
```

### Skip fonts
```bash
./setup-modern-emacs.sh --skip-fonts
```

### Skip tree-sitter grammar installs
```bash
./setup-modern-emacs.sh --no-treesit
```

### Don’t install optional extras (icons, terraform-mode)
```bash
./setup-modern-emacs.sh --no-optional
```

### Dry-run (no changes)
```bash
./setup-modern-emacs.sh --dry-run
```

---

## Manual install (if you don’t want the script)

1) Install Homebrew (official):
```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

2) Install Emacs + core tooling:
```bash
brew install emacs ripgrep fd enchant gnupg
```

3) (Optional) Install language servers:
```bash
brew install gopls pyright rust-analyzer bash-language-server yaml-language-server \
  dockerfile-language-server terraform-ls typescript-language-server \
  vscode-langservers-extracted sql-language-server shellcheck shfmt
```

4) (Optional) Install fonts:
```bash
brew tap homebrew/cask-fonts
brew install --cask font-jetbrains-mono-nerd-font font-inter
```

5) Install the config:
```bash
mkdir -p ~/.emacs.d
rsync -a ./emacs.d/ ~/.emacs.d/
```

6) Bootstrap packages:
```bash
emacs --batch -Q -l ~/.emacs.d/bootstrap.el
```

---

## What gets installed (Homebrew packages)

Core:
- `emacs` (GNU Emacs)
- `ripgrep` (fast searching; used by Consult)
- `fd` (fast file finding; used by many Emacs tools)
- `enchant` (required for Jinx spellchecking)
- `gnupg` (reliable package signature verification)

Optional but installed by default (language servers & tooling):
- `gopls`, `pyright`, `rust-analyzer`
- `bash-language-server`, `yaml-language-server`
- `dockerfile-language-server`, `terraform-ls`
- `typescript-language-server`, `vscode-langservers-extracted`
- `sql-language-server`
- `shellcheck`, `shfmt`

Fonts (optional; installed by default):
- `font-jetbrains-mono-nerd-font`
- `font-inter`

---

## First launch workflows (GUI and terminal)

### Direct launch
- GUI: `emacs`
- Terminal: `emacs -nw`

### Recommended: daemon + emacsclient
If you enabled `--daemon`, Emacs runs in the background for instant startup:
- GUI frame: `emacsclient -c`
- Terminal client: `emacsclient -t`

Manage via Homebrew:
```bash
brew services list
brew services restart emacs
brew services stop emacs
```

---

## Emacs onboarding (first 15 minutes)

If you’re new (or rusty) and want the quickest ramp:
- Tutorial: `C-h t`
- Describe key: `C-h k` then press keys
- Describe function/variable: `C-h f` / `C-h v`
- Run a command: `M-x` (Alt/Option-x, or Esc then x)
- Cancel prompts: `C-g`

This setup helps you learn faster:
- Which-key shows possible continuations as you type key sequences.
- Vertico/Consult make `M-x` and navigation feel “modern IDE-like”.

---

## Config layout and how to customize

Installed to: `~/.emacs.d/`

Key files:
- `~/.emacs.d/early-init.el`: startup/performance and early UI toggles.
- `~/.emacs.d/init.el`: main configuration.
- `~/.emacs.d/bootstrap.el`: installs packages + tree-sitter grammars (batch-safe).
- `~/.emacs.d/custom.el`: created by Emacs Customize UI (loaded automatically).
- `~/.emacs.d/init-local.el`: **your personal overrides** (optional; loaded last).

Recommended customization workflow:
1. Put personal tweaks in `~/.emacs.d/init-local.el`
2. Keep `~/.emacs.d/init.el` mostly unchanged so you can update this repo’s config easily

---

## Keybindings (high value)

General:
- `C-s`: `consult-line` (search in buffer)
- `C-x b`: `consult-buffer` (smart buffer switch)
- `C-c r`: `consult-ripgrep` (project search)
- `C-.`: `embark-act` (do-what-I-mean actions)
- `M-j`: `avy-goto-char-timer` (fast jump)
- `C-=`: expand region
- Multiple cursors: `C->`, `C-<`, `C-c C-<`

Projects (prefix: `C-c p`):
- `C-c p p`: switch project
- `C-c p f`: find file in project
- `C-c p g`: ripgrep in project
- `C-c p b`: project buffers
- `C-c p s`: project shell

Git:
- `C-x g`: Magit status

Terminal:
- `C-c t`: open EAT terminal

Notes:
- `C-c a`: Org agenda
- `C-c c`: Org capture

AI:
- `C-c G`: open a gptel chat
- `C-c A`: gptel menu

---

## Backend engineer features (what’s included)

### LSP via Eglot
Eglot starts automatically in common modes when servers are available:
- Go → `gopls`
- Python → `pyright-langserver`
- Rust → `rust-analyzer`
- JS/TS → `typescript-language-server`
- Bash → `bash-language-server`
- YAML → `yaml-language-server`
- Dockerfile → `docker-langserver` (from dockerfile-language-server)
- Terraform → `terraform-ls` (mode support depends on major mode availability)

Formatting:
- `C-c f` in an Eglot buffer runs formatting (uses `eglot-format-buffer` when available).

### Tree-sitter
The bootstrap installs grammars for common backend languages (Go, Python, Rust, TS/JS, JSON, YAML, TOML, HCL, etc.) and remaps to `*-ts-mode` when ready.

### Git-centric workflow
Magit + diff highlights (`diff-hl`) for a great day-to-day Git experience.

### Search & navigation at scale
Consult + ripgrep is a strong “IDE-grade” navigation story in big monorepos.

### Snippets & completion
Yasnippet + Corfu/Cape provide modern in-buffer completion.

---

## AI setup (secure, reliable defaults)

### gptel with OpenAI
Set your key in your shell profile:
```bash
export OPENAI_API_KEY="..."
```

### gptel with Anthropic
```bash
export ANTHROPIC_API_KEY="..."
```

Security tips:
- Prefer environment variables set by your shell / a secrets manager.
- Consider Emacs `auth-source` (`~/.authinfo` / `~/.authinfo.gpg`) for keys if you want them out of shell history.
- Avoid committing keys into `init-local.el` or dotfiles.

Optional (not enabled by default here, but worth considering):
- **GitHub Copilot** (`copilot.el`) for inline code completions (requires Node).
- **Ollama** for local models + gptel backend (privacy-friendly).
- MCP integrations (gptel supports MCP via `mcp.el`) if you want tools/agents inside Emacs.

---

## Aesthetics (terminal and GUI)

Defaults in this config:
- Theme: built-in **Modus Vivendi** (high-quality, accessible).
- Fonts (GUI): JetBrains Mono Nerd Font (code) + Inter (UI/notes) when installed.

Terminal tips:
- Set your terminal font to a Nerd Font (JetBrainsMono Nerd Font works well).
- Enable truecolor in your terminal (Warp/Ghostty/iTerm2 all support it).
- Ligatures: GUI Emacs can render ligatures when built with HarfBuzz and using a ligature font; terminal Emacs depends on your terminal and is more limited.

Optional icons:
- If you want icons in completions and dired, keep optional packages enabled and ensure Nerd Fonts are installed.

---

## Best practices (reliability + sanity)

- Use the **daemon + emacsclient** workflow if you want “instant startup”.
- Keep your personal tweaks in `init-local.el` so upgrades are easy.
- Prefer GNU ELPA/NonGNU ELPA packages for stability; treat MELPA as optional.
- Debug startup issues with:
  - `emacs --debug-init`
  - temporarily moving `~/.emacs.d/init-local.el` out of the way
- Keep backups: this script already creates timestamped backups under `~/.modern-emacs-backups/`.

---

## Troubleshooting

### “Failed verifying signature” / GPG issues
- Ensure `gnupg` is installed (`brew install gnupg`).
- Re-run bootstrap:
  ```bash
  emacs --batch -Q -l ~/.emacs.d/bootstrap.el
  ```

### Tree-sitter grammar installation fails
- Ensure Xcode Command Line Tools are installed:
  ```bash
  xcode-select -p
  ```
- Re-run bootstrap with tree-sitter enabled:
  ```bash
  emacs --batch -Q -l ~/.emacs.d/bootstrap.el
  ```

### Eglot says it can’t find a language server
- Install the server (via Homebrew or your toolchain).
- Confirm it’s on PATH inside Emacs:
  - `M-x getenv RET PATH` (GUI builds need exec-path-from-shell)
  - `M-: (executable-find "gopls")`

### gptel fails to authenticate
- Confirm your key is present in Emacs:
  - `M-: (getenv "OPENAI_API_KEY")`
  - `M-: (getenv "ANTHROPIC_API_KEY")`

---

## Updating

### Update Emacs and system tools
```bash
brew update
brew upgrade
```

### Update Emacs packages
Inside Emacs:
- `M-x list-packages` → mark upgrades → execute

Or re-run bootstrap (safe):
```bash
emacs --batch -Q -l ~/.emacs.d/bootstrap.el
```

Tree-sitter grammars may need occasional re-install after upstream updates.

---

## Rollback / uninstall

### Restore your previous Emacs config
Backups live in:
- `~/.modern-emacs-backups/<timestamp>/`

To restore manually (example):
```bash
mv ~/.emacs.d ~/.emacs.d.current
mv ~/.modern-emacs-backups/<timestamp>/.emacs.d ~/.emacs.d
```

### Remove Homebrew packages (optional)
If you want to remove what the script installed:
```bash
brew uninstall emacs ripgrep fd enchant gnupg
```
(and any language servers/fonts you no longer want)

---

## Next enhancements (optional)

If you answer the clarifying questions, common upgrades include:
- Evil (Vim) keybindings, or a hybrid approach.
- Docker/Kubernetes packages (`docker.el`, kubernetes clients).
- Better `.env`/direnv integration (`envrc` / `direnv.el`).
- Debugging (DAP, `dape`, etc.) depending on your languages.
- Org-roam / knowledge management if you want a “second brain” workflow.

---

## References

Core docs:
- GNU Emacs manual: https://www.gnu.org/software/emacs/manual/
- Emacs NEWS (Emacs 30): https://www.gnu.org/software/emacs/news/

Key packages:
- Vertico/Consult/Embark ecosystem (Minad): https://github.com/minad/
- Corfu/Cape: https://github.com/minad/corfu , https://github.com/minad/cape
- Magit: https://magit.vc/
- gptel: https://elpa.nongnu.org/nongnu/gptel.html

Popular distributions:
- Doom Emacs: https://github.com/doomemacs/doomemacs
- Spacemacs: https://github.com/syl20bnr/spacemacs
- Purcell’s emacs.d: https://github.com/purcell/emacs.d
- Crafted Emacs: https://github.com/SystemCrafters/crafted-emacs
