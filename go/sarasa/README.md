# Sarasa

Sarasa automates global tool upgrades on macOS. It handles standard package
managers and user-defined tools that are installed outside package managers.

## Managers

| Manager | Purpose |
| --- | --- |
| `brew` | Homebrew formulae and casks |
| `volta` | Volta-managed global npm tools |
| `npm` | Global npm tools when npm is not managed by Volta |
| `pipx` | pipx applications |
| `bun` | Bun global packages |
| `skills` | Global agent skills through `npx skills` |
| `custom` | Config-defined tools, direct installers, local repos, and self-updaters |

## Commands

```bash
sarasa init
sarasa status
sarasa run --dry-run
sarasa run
sarasa logs
sarasa schedule install
```

## Configuration

Default path:

```text
~/.config/sarasa/config.toml
```

Minimal example:

```toml
managers = ["brew", "volta", "pipx", "bun", "skills", "custom"]

[skip]
brew = ["postgresql@14"]
custom = ["experimental-tool"]

[schedule]
times = ["08:00", "14:00", "22:00"]
```

## Custom Tools

Custom tools are recipes. Sarasa runs them through the same status, dry-run,
upgrade, logging, and TUI paths as built-in managers.

Each recipe follows this flow:

```text
detect installed -> current version -> latest version -> compare -> upgrade -> verify
```

### GitHub Release Installer

Use this for projects that publish GitHub Releases and expose a shell installer.

```toml
managers = ["custom"]

[custom]
state_dir = "~/.local/state/sarasa/custom"
default_timeout = "10m"

[[custom.tools]]
name = "nidhi"
binary = "nidhi"
missing = "install"
current = { argv = ["nidhi", "--version"], regex = "v?[0-9]+\\.[0-9]+\\.[0-9]+" }
latest = { github_release = "indrasvat/nidhi" }
upgrade = { shell = "curl -sSfL https://raw.githubusercontent.com/indrasvat/nidhi/main/install.sh | bash -s -- --version ${latest} --dir ~/.local/bin" }
verify = { argv = ["nidhi", "--version"], regex = "v?[0-9]+\\.[0-9]+\\.[0-9]+" }
```

The `custom` panel shows the recipe method beside each row:

```text
🛠 CUSTOM
╭────────────────────────────────────────────────────────────────────────────╮
│ (1.2s)                                                                     │
│   ▸ nidhi  v0.1.0 → v0.2.0 · github-release / shell                        │
╰────────────────────────────────────────────────────────────────────────────╯
```

### Self-Updater

Use `outdated.mode = "always"` for tools that decide update availability inside
their own upgrade command. Set `allow_unchanged = true` when a successful no-op
is valid.

```toml
[[custom.tools]]
name = "claude"
binary = "claude"
allow_unchanged = true
current = { argv = ["claude", "--version"], regex = "[0-9]+\\.[0-9]+\\.[0-9]+" }
latest = { mode = "self" }
outdated = { mode = "always" }
upgrade = { argv = ["claude", "upgrade"] }
verify = { argv = ["claude", "--version"], regex = "[0-9]+\\.[0-9]+\\.[0-9]+" }
```

### Missing Tool Policy

By default, a custom recipe with `binary = "tool"` is skipped when the binary is
not present in `PATH`. Use `missing = "install"` for installer recipes that
should bootstrap the tool when it is absent:

```toml
[[custom.tools]]
name = "shux"
binary = "shux"
missing = "install"
current = { argv = ["shux", "--version"], regex = "v?[0-9]+\\.[0-9]+\\.[0-9]+" }
latest = { github_release = "indrasvat/shux" }
upgrade = { shell = "curl -sSfL https://raw.githubusercontent.com/indrasvat/shux/main/install.sh | sh -s -- --version ${latest} --dir ~/.local/bin", timeout = "15m" }
verify = { argv = ["shux", "--version"], regex = "v?[0-9]+\\.[0-9]+\\.[0-9]+" }
```

Supported values:

| Policy | Behavior |
| --- | --- |
| unset / `skip` | Skip the recipe when `binary` is absent |
| `install` | Report `not installed → latest` and run `upgrade` |
| `fail` | Fail the custom manager when `binary` is absent |

### Local Repo Installer

Use this for tools you build and install from an active checkout.

```toml
[[custom.tools]]
name = "local-tool"
binary = "local-tool"
current = { argv = ["local-tool", "--version"], regex = "v?[0-9]+\\.[0-9]+\\.[0-9]+" }
latest = { argv = ["git", "describe", "--tags", "--abbrev=0"], cwd = "~/code/github.com/indrasvat-local-tool" }
upgrade = { argv = ["make", "install"], cwd = "~/code/github.com/indrasvat-local-tool", timeout = "15m" }
verify = { argv = ["local-tool", "--version"], regex = "v?[0-9]+\\.[0-9]+\\.[0-9]+" }
```

## Recipe Fields

| Field | Description |
| --- | --- |
| `name` | Display name and skip-list key |
| `binary` | Optional executable used to decide whether the tool is installed |
| `missing` | Missing-binary policy: `skip`, `install`, or `fail` |
| `current` | Command probe for the installed version |
| `latest` | Latest version provider |
| `outdated` | Optional policy override |
| `upgrade` | Command or shell action to run |
| `verify` | Optional post-upgrade version probe |
| `cleanup` | Optional post-run cleanup action |
| `timeout` | Per-tool timeout fallback |
| `allow_unchanged` | Treat successful same-version verification as success |

Command-bearing fields support:

| Key | Description |
| --- | --- |
| `argv` | Preferred command form, for example `["make", "install"]` |
| `shell` | Shell command form for pipes and installer snippets |
| `cwd` | Working directory, with `~` expansion |
| `env` | Extra environment variables |
| `timeout` | Per-command timeout |
| `regex` | Version extraction regex for `current`, `latest`, and `verify` probes |

`upgrade` commands may reference:

```text
${name}
${current}
${latest}
```

Latest providers:

| Provider | Example |
| --- | --- |
| `value` | `latest = { value = "v1.2.3" }` |
| `github_release` | `latest = { github_release = "owner/repo" }` |
| command probe | `latest = { argv = ["tool", "latest"], regex = "..." }` |
| self-managed | `latest = { mode = "self" }` |

For `github_release`, sarasa calls the GitHub Releases API. It uses
`GITHUB_TOKEN` or `GH_TOKEN` when either is set, and falls back to authenticated
`gh api` on GitHub 401/403 responses when the GitHub CLI is available. This
keeps public release checks working after unauthenticated API rate limits.

Outdated modes:

| Mode | Behavior |
| --- | --- |
| unset / `compare` / `semver` | Compare latest and current versions |
| `always` | Always run during `sarasa run` |
| `never` | Never report outdated |
| `command` | Run an exit-code probe; exit 0 means outdated |

## Verification

Local checks:

```bash
make test
make lint
```

Visual checks use shux so TUI rendering is verified in a real PTY:

```bash
.shux/scripts/capture-run-dry-run.sh
.shux/scripts/capture-custom-dry-run.sh
```
