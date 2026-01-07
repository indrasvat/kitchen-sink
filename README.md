# kitchen-sink

A curated collection of useful scripts for macOS automation, development setup, and utilities.

## Structure

```
.
├── shell/
│   ├── screenshot-tools/    # Terminal screenshot automation
│   ├── dev-setup/           # Development environment setup scripts
│   └── utilities/           # General-purpose utilities
├── python/
│   ├── automation/          # Task automation scripts
│   ├── dev-tools/           # Developer productivity tools
│   └── games/               # Fun stuff
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
| [`gameboy-dev-setup-macos.sh`](shell/dev-setup/gameboy-dev-setup-macos.sh) | Complete Game Boy development environment (GBDK-2020, RGBDS, emulators) |
| [`setup-modern-emacs/`](shell/dev-setup/setup-modern-emacs/) | Modern Emacs setup with Homebrew, LSP, tree-sitter |

```bash
# Set up Game Boy dev environment
./gameboy-dev-setup-macos.sh

# Set up Emacs with modern defaults
./setup-modern-emacs/setup-modern-emacs.sh --yes
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

## Guides

| Guide | Description |
|-------|-------------|
| [`remote-claude-access/`](guides/remote-claude-access/) | Access Claude Code CLI from iPhone via Tailscale + Termius/Blink Shell |

## Requirements

- **macOS** (most scripts are macOS-specific)
- **uv** for Python scripts: `curl -LsSf https://astral.sh/uv/install.sh | sh`
- **Homebrew** for shell scripts: `/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"`

## License

MIT - Use freely, no attribution required.
