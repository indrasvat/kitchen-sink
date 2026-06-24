# kitchen-sink

A curated collection of useful scripts for macOS automation, development setup, and utilities.

## Structure

```
.
├── shell/
│   ├── airdrop-autoheal/    # Self-healing LaunchDaemon for the awdl0 AirDrop flake
│   ├── screenshot-tools/    # Terminal screenshot automation
│   ├── dev-setup/           # Development environment setup scripts
│   └── utilities/           # General-purpose utilities
├── python/
│   ├── automation/          # Task automation scripts
│   ├── dev-tools/           # Developer productivity tools
│   └── games/               # Fun stuff
├── go/
│   └── sarasa/              # Automated global package manager upgrades
├── guides/
│   └── remote-claude-access/ # Remote Claude Code CLI from iPhone
└── applescript/             # macOS automation scripts
```

## Shell Scripts

### Screenshot Tools

Automated CLI/TUI screenshot tools for documentation, demos, and testing.

| Script | Description |
|--------|-------------|
| [`iterm2-screenshot.sh`](shell/screenshot-tools/iterm2-screenshot.sh) | Direct iTerm2 screenshot capture with imgcat image preservation |
| [`tmux-screenshot.sh`](shell/screenshot-tools/tmux-screenshot.sh) | tmux-based screenshot tool for reproducible terminal captures |
| [`zellij-screenshot.sh`](shell/screenshot-tools/zellij-screenshot.sh) | Zellij-based tool with Sixel graphics protocol support |

**Common features:**
- Configurable terminal dimensions (`-w`, `-h`)
- Pre-command execution (`-e`)
- Delay control (`-d`)
- Working directory (`-D`)
- Window maximization (`-M`)

```bash
# Example: Capture a CLI app screenshot
./tmux-screenshot.sh -D ~/project -o demo.png -M -d 2 -- ./my-app --help
```

### Dev Setup

One-command development environment setup scripts.

| Script | Description |
|--------|-------------|
| [`yantraganana.sh`](shell/dev-setup/yantraganana.sh) | Capture full macOS dev environment inventory as JSON |
| [`saamagri.sh`](shell/dev-setup/saamagri.sh) | Replay an inventory JSON to set up a fresh Mac |
| [`gameboy-dev-setup-macos.sh`](shell/dev-setup/gameboy-dev-setup-macos.sh) | Complete Game Boy development environment (GBDK-2020, RGBDS, emulators) |
| [`wezterm-dojo-setup.sh`](shell/dev-setup/wezterm-dojo-setup.sh) | Reproduce the WezTerm setup: nightly app, Nerd Font, dotfiles stow package, plugins |
| [`setup-modern-emacs/`](shell/dev-setup/setup-modern-emacs/) | Modern Emacs setup with Homebrew, LSP, tree-sitter |

#### सामग्री (Sāmagrī)

Two-script workflow for cloning your dev environment across Macs.

**Step 1 — Capture** with यन्त्रगणना (Yantragaṇanā): scans all package managers, configs, and tools into a single JSON file.

**Step 2 — Replay** with सामग्री (Sāmagrī): reads that JSON on a fresh Mac and installs everything in the right order.

**17 phases** in dependency order: Xcode CLT → Homebrew → bash → brew packages → language runtimes → tools → shell configs → git → SSH → tmux → VS Code → fonts → AI agents → Docker → LaunchAgents → macOS defaults.

```bash
# On your current Mac — capture everything
./yantraganana.sh ~/tool-inventory.json

# On the new Mac — replay interactively
./saamagri.sh --inventory ~/tool-inventory.json

# Unattended setup for a work Mac
./saamagri.sh --yes --profile work

# Preview what would change
./saamagri.sh --dry-run

# Resume from a specific phase after a failure
./saamagri.sh --phase 8
```

### Utilities

| Script | Description |
|--------|-------------|
| [`upgrade-ai-cli.sh`](shell/utilities/upgrade-ai-cli.sh) | Install/upgrade AI CLI tools (Claude Code, Gemini CLI, Codex, etc.) |
| [`watch-and-notify.sh`](shell/utilities/watch-and-notify.sh) | Play sound notification on command output changes |

```bash
# Upgrade all AI CLI tools
./upgrade-ai-cli.sh

# Watch kubectl and notify on changes
./watch-and-notify.sh kubectl get po --watch --no-headers
```

### AirDrop Auto-Heal

[`airdrop-autoheal/`](shell/airdrop-autoheal/) is a root `LaunchDaemon` that self-heals the macOS **`awdl0` AirDrop path-migration flake** — the intermittent failure where a transfer is accepted, then dies mid-flight because macOS migrates the connection off the `awdl0` peer-to-peer link (common with a VPN like Tailscale running). It watches `sharingd`'s log and re-primes `awdl0` within ~1s so your re-send succeeds.

```bash
# Install (auto-elevates with sudo, verifies with doctor):
curl -fsSL https://raw.githubusercontent.com/indrasvat/kitchen-sink/main/shell/airdrop-autoheal/install.sh | sudo bash

# Health report (no sudo) + manual reset
bash "/Library/Application Support/airdrop-autoheal/doctor.sh"
sudo "/Library/Application Support/airdrop-autoheal/airdrop-autoheal.sh" --bounce-once
```

Hardened across two adversarial reviews (no orphaned processes, PID-reuse guard, circuit breaker, never leaves `awdl0` down). See [`shell/airdrop-autoheal/README.md`](shell/airdrop-autoheal/README.md) for the safety design.

## Python Scripts

All Python scripts use [uv](https://docs.astral.sh/uv/) with inline script metadata (PEP 723) for zero-setup execution.

### Automation

| Script | Description |
|--------|-------------|
| [`chatgpt-receipt-automation/`](python/automation/chatgpt-receipt-automation/) | Automated ChatGPT Plus receipt download via browser-use |
| [`ntp.py`](python/automation/ntp.py) | Simple NTP time query utility |

```bash
# Query NTP time
uv run python/automation/ntp.py pool.ntp.org

# ChatGPT receipt automation (see its own README)
cd python/automation/chatgpt-receipt-automation
make install
```

### Dev Tools

| Script | Description |
|--------|-------------|
| [`pyproject-dependencies-graph.py`](python/dev-tools/pyproject-dependencies-graph.py) | Visualize pyproject.toml dependencies as a graph |
| [`github-issue-importer.py`](python/dev-tools/github-issue-importer.py) | Bulk import GitHub issues from JSON |
| [`process-lister.py`](python/dev-tools/process-lister.py) | Activity Monitor-style process listing (RSS memory) |
| [`generate-synthetic-rust-code.py`](python/dev-tools/generate-synthetic-rust-code.py) | Generate synthetic Rust code for testing tools |

```bash
# Visualize dependencies
uv run python/dev-tools/pyproject-dependencies-graph.py

# List top 20 processes by memory
uv run python/dev-tools/process-lister.py --limit 20

# Generate 10k lines of synthetic Rust
uv run python/dev-tools/generate-synthetic-rust-code.py --lines 10000 -o test.rs
```

### Games

| Script | Description |
|--------|-------------|
| [`space-war.py`](python/games/space-war.py) | Retro arcade space shooter (pygame) |

```bash
uv run python/games/space-war.py
```

## Go Tools

### Sarasa

[`sarasa`](go/sarasa/) is a CLI tool for automated global package manager upgrades with scheduled background execution via launchd.

**Supported managers:** 🍺 brew · ⚡ volta · 📦 npm · 🐍 pipx · 🥟 bun · 🧩 skills · 🛠 custom tools

| Command | Description |
|---------|-------------|
| `sarasa init` | Interactive setup wizard (managers, schedule) |
| `sarasa status` | Check for outdated packages (press `u` to upgrade) |
| `sarasa run` | Upgrade all outdated packages |
| `sarasa run --dry-run` | Preview upgrades without applying |
| `sarasa logs` | Interactive log viewer with search and filtering |
| `sarasa schedule install` | Install launchd agent for scheduled upgrades |
| `sarasa schedule status` | Check if scheduled upgrades are active |

**Features:**
- Interactive TUI with colored output and progress indicators
- One-command install on new machines (no sudo required)
- Per-manager skip lists and major version upgrade control
- Config-driven custom tool recipes for direct installers, local repos, and self-updaters
- Structured JSON logging with 30-day retention
- Graceful degradation to plain text when piped

**Quick install** (no repo clone needed):

```bash
curl -fsSL https://raw.githubusercontent.com/indrasvat/kitchen-sink/main/go/sarasa/install.sh | bash
```

Or from a local clone:

```bash
cd go/sarasa && make install
sarasa init     # interactive setup (managers + schedule)
```

```bash
# Check what needs upgrading
sarasa status

# Preview upgrades (dry run)
sarasa run --dry-run

# Upgrade everything
sarasa run

# View upgrade history
sarasa logs
```

**Configuration:** `~/.config/sarasa/config.toml`

```toml
managers = ["brew", "volta", "npm", "pipx", "bun", "skills", "custom"]

[skip]
brew = ["postgresql@14"]  # Packages to skip
npm = []
custom = ["experimental-tool"]

[schedule]
times = ["08:00", "14:00", "22:00"]

[custom]
state_dir = "~/.local/state/sarasa/custom"
default_timeout = "10m"

[[custom.tools]]
name = "nidhi"
binary = "nidhi"
missing = "install"  # bootstrap if absent; default is "skip"
current = { argv = ["nidhi", "--version"], regex = "v?[0-9]+\\.[0-9]+\\.[0-9]+" }
latest = { github_release = "indrasvat/nidhi" }
upgrade = { shell = "curl -sSfL https://raw.githubusercontent.com/indrasvat/nidhi/main/install.sh | bash -s -- --version ${latest} --dir ~/.local/bin" }
verify = { argv = ["nidhi", "--version"], regex = "v?[0-9]+\\.[0-9]+\\.[0-9]+" }
```

`latest.github_release` uses `GITHUB_TOKEN`/`GH_TOKEN` when set and falls back
to authenticated `gh api` after GitHub 401/403 responses. See
[`go/sarasa/README.md`](go/sarasa/README.md) for custom recipe patterns,
self-updater examples, and verification notes.

## Guides

| Guide | Description |
|-------|-------------|
| [`remote-claude-access/`](guides/remote-claude-access/) | Access Claude Code CLI from iPhone via Tailscale + Termius/Blink Shell |

## Development

```bash
# Install all development tools (macOS)
make tools

# Install git hooks (runs lints before push)
make hooks

# Run all lints and tests
make ci

# Run individual linters
make lint-shell    # shellcheck
make lint-python   # ruff
make lint-go       # golangci-lint
```

The repo uses [lefthook](https://github.com/evilmartians/lefthook) for git hooks. The pre-push hook runs `make ci` to ensure all lints and tests pass before pushing.

## Requirements

- **macOS** (most scripts are macOS-specific)
- **uv** for Python scripts: `curl -LsSf https://astral.sh/uv/install.sh | sh`
- **Homebrew** for shell scripts: `/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"`
- **Go 1.23+** for Go tools: `brew install go`

## License

MIT - Use freely, no attribution required.
