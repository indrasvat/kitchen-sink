# AirDrop Auto-Heal

A root `LaunchDaemon` that self-heals the macOS **`awdl0` AirDrop path-migration
flake** — the intermittent failure where an AirDrop transfer is accepted, then
dies mid-flight because macOS migrates the connection **off** the `awdl0`
peer-to-peer link to a "better path" (common when a VPN like Tailscale is
running). The daemon watches `sharingd`'s log for the exact failure fingerprint
and re-primes `awdl0` within ~1s, so your re-send goes straight through.

It is **auto-recovery, not prevention**: it can't rescue the transfer that just
died, but it clears the wedge so the retry succeeds — with zero manual steps.

## Install

```bash
# One-liner (any Mac) — auto-elevates with sudo:
curl -fsSL https://raw.githubusercontent.com/indrasvat/kitchen-sink/main/shell/airdrop-autoheal/install.sh | sudo bash

# From a local clone:
sudo bash shell/airdrop-autoheal/install.sh

# Check prerequisites only (no sudo):
bash shell/airdrop-autoheal/install.sh --check

# Install from a branch/tag (e.g. testing a PR) — no code change:
curl -fsSL https://raw.githubusercontent.com/indrasvat/kitchen-sink/<ref>/shell/airdrop-autoheal/install.sh \
  | sudo AIRDROP_AUTOHEAL_REF=<ref> bash
```

The installer fetches its artifacts over plain HTTPS (no `git`, so a user's
`url.insteadOf` SSH rewrite can't break it). Source is `main` by default;
override with `AIRDROP_AUTOHEAL_REF` (branch/tag) or `AIRDROP_AUTOHEAL_RAW_BASE`
(full base URL).

The installer is idempotent, verifies itself with `doctor` at the end, and
needs root exactly **once** (to install a LaunchDaemon and because bouncing a
network interface is a privileged operation). After that it runs autonomously —
no further `sudo` prompts.

## Commands

| Command | Root? | What it does |
| --- | --- | --- |
| `bash "/Library/Application Support/airdrop-autoheal/doctor.sh"` | no | Darcula-themed health report (process tree, orphan scan, predicate, awdl0, logs) |
| `sudo "/Library/Application Support/airdrop-autoheal/airdrop-autoheal.sh" --bounce-once` | yes | Manual one-shot `awdl0` reset (hotkey-able) |
| `sudo tail -f /var/log/airdrop-autoheal.log` | no¹ | Watch every detection + bounce live |
| `sudo bash install.sh --uninstall` | yes | Unload + remove (keeps logs) |

¹ The audit log is `0640 root:admin` — readable without `sudo` if you're in the
`admin` group.

## How it works

- **Detection:** a backgrounded `log stream` watches for
  `processImagePath == "/usr/libexec/sharingd" AND eventMessage CONTAINS "quic_migration_path_unavailable" AND CONTAINS "awdl0"`.
  Pinning the real Apple binary by path (not the spoofable process *name*) means
  no unprivileged process can forge the trigger.
- **Heal:** `ifconfig awdl0 down/up` re-primes the AWDL link.
- **Safety (hardened across two adversarial reviews):**
  - log stream is a **directly-backgrounded** child read via a FIFO in the
    root-only install dir — the trap kills exactly its PID (guarded against PID
    reuse), so **no orphaned process or subshell** is ever left behind.
  - signals `exit` explicitly (never resume mid-bounce); the EXIT trap always
    forces `awdl0` back **up** (never wedged down), with retries.
  - **circuit breaker** caps bounces at 6 / 600s so it can never thrash the network.
  - pinned `PATH` + absolute binaries; logs `0640` + `newsyslog`-rotated;
    hourly heartbeat line so the log self-documents liveness.
- **Footprint:** ~0% CPU/mem at idle (a single narrow `log stream` subscriber).

## What it installs

```
/Library/Application Support/airdrop-autoheal/airdrop-autoheal.sh   # watcher daemon
/Library/Application Support/airdrop-autoheal/doctor.sh             # health report
/Library/LaunchDaemons/com.indrasvat.airdrop-autoheal.plist        # KeepAlive daemon
/etc/newsyslog.d/airdrop-autoheal.conf                             # log rotation
/var/log/airdrop-autoheal.{log,err}                                # audit logs (0640)
```

## What this does NOT fix

A separate, unrelated AirDrop-receive failure on **macOS Tahoe** throws
`NSPOSIXErrorDomain Code 2 "No such file or directory"` at finalization when the
incoming **filename contains non-ASCII characters** (e.g. `ā`, `·`). That's an
Apple OS bug in path handling — not a network issue — so this daemon correctly
does nothing for it. Workaround: rename to ASCII before sending; report via
Feedback Assistant.

## Requirements

- **macOS** (uses `launchctl` / `sharingd` / `awdl0`).
- Runs under system `/bin/bash` (3.2-compatible by design — no dependency on a
  newer shell).
- Root once for install; none thereafter.
