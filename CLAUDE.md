# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

A curated collection of macOS automation scripts, development setup tools, and utilities. Scripts are organized by language (shell/, python/) and purpose.

## Commands

```bash
# Install all scripts to ~/.local/bin
make install

# Uninstall
make uninstall

# Lint all code
make lint

# Lint only shell scripts (shellcheck)
make lint-shell

# Lint only Python scripts (ruff)
make lint-python

# List all available scripts
make list
```

## Running Python Scripts

All Python scripts use [uv](https://docs.astral.sh/uv/) with inline script metadata (PEP 723). Run directly with uv:

```bash
uv run python/dev-tools/process-lister.py --limit 20
uv run python/automation/ntp.py pool.ntp.org
```

## Code Style

- Shell scripts: 4-space indentation, checked with shellcheck
- Python: 4-space indentation, checked with ruff
- YAML: 2-space indentation
- Makefiles: tab indentation
- All files: LF line endings, UTF-8, final newline required

## Commit Convention

Use Conventional Commits: `type(scope): summary`

**Format:**
- Single line only: `type(scope): summary` (no body or bullet points)
- Imperative mood, lowercase, no period
- Types: feat, fix, docs, style, refactor, test, chore, perf, build
- Scopes: based on the logical components of the app

**Examples:**
```
feat(auth): add login rate limiting
fix(sarasa): resolve golangci-lint warnings
docs: update README installation steps
refactor(api): extract validation into separate module
```

**Granularity:**
- Keep commits *reasonably* atomic—one logical change per commit
- Don't be overly granular: related changes (e.g., a feature + its tests) belong together
- A single commit can touch multiple files if they're part of one coherent change
- Commit early, commit often, but group related work sensibly

## CI

GitHub Actions runs shellcheck on `shell/` and ruff on `python/` for PRs to main.
