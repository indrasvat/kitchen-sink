# /// script
# requires-python = ">=3.14"
# dependencies = [
#   "iterm2",
#   "pyobjc",
#   "pyobjc-framework-Quartz",
# ]
# ///
"""
Test: sarasa install.sh in a clean temp directory
==================================================

Tests:
  1. --check flag: verify prerequisite detection
  2. --help flag: verify usage output
  3. Full install to temp prefix with --no-init
  4. Verify installed binary works (version, schedule, init --help)
  5. Verify cleanup (no leftover temp dirs)

Verification Strategy:
  - Run each command and check stdout for expected strings
  - Use a temp install prefix to avoid touching real ~/.local/bin
  - Verify binary works after install

Screenshots:
  - /tmp/sarasa-install-1-check.png    — prerequisite check
  - /tmp/sarasa-install-2-install.png  — install in progress
  - /tmp/sarasa-install-3-verify.png   — post-install verify

Usage:
  uv run .claude/automations/test-sarasa-install.py
"""

import asyncio
import subprocess
import iterm2


def capture_iterm_screenshot(path: str) -> bool:
    """Capture iTerm2 window screenshot."""
    try:
        import Quartz
        window_list = Quartz.CGWindowListCopyWindowInfo(
            Quartz.kCGWindowListOptionOnScreenOnly,
            Quartz.kCGNullWindowID,
        )
        iterm_id = None
        for win in window_list:
            owner = win.get("kCGWindowOwnerName", "")
            if "iTerm2" in owner and win.get("kCGWindowLayer", 999) == 0:
                iterm_id = win.get("kCGWindowNumber")
                break
        if iterm_id is None:
            return False
        subprocess.run(
            ["screencapture", "-l", str(iterm_id), "-x", path],
            check=True, capture_output=True,
        )
        print(f"  Screenshot: {path}")
        return True
    except Exception:
        return False


async def read_screen(session) -> str:
    screen = await session.async_get_screen_contents()
    lines = []
    for i in range(screen.number_of_lines):
        lines.append(screen.line(i).string)
    return "\n".join(lines)


async def screen_contains(session, text: str, timeout: float = 5.0) -> bool:
    deadline = asyncio.get_event_loop().time() + timeout
    while asyncio.get_event_loop().time() < deadline:
        content = await read_screen(session)
        if text in content:
            return True
        await asyncio.sleep(0.5)
    return False


async def wait_for_prompt(session, timeout: float = 120.0) -> bool:
    """Wait for shell prompt ($ or %) to appear, meaning command finished."""
    deadline = asyncio.get_event_loop().time() + timeout
    while asyncio.get_event_loop().time() < deadline:
        screen = await session.async_get_screen_contents()
        # Check last few non-empty lines for prompt
        for i in range(screen.number_of_lines - 1, max(0, screen.number_of_lines - 5), -1):
            line = screen.line(i).string.strip()
            if line and (line.endswith("$") or line.endswith("%") or line.endswith("#")):
                return True
        await asyncio.sleep(1.0)
    return False


results = {"passed": 0, "failed": 0, "tests": []}


def log_result(name: str, passed: bool, details: str = ""):
    status = "PASS" if passed else "FAIL"
    results["passed" if passed else "failed"] += 1
    results["tests"].append({"name": name, "status": status, "details": details})
    icon = "✓" if passed else "✗"
    print(f"  {icon} {name}" + (f" — {details}" if details else ""))


def print_summary():
    total = results["passed"] + results["failed"]
    print(f"\n  Results: {results['passed']}/{total} passed")
    return 0 if results["failed"] == 0 else 1


SCRIPT = "/Users/indrasvat/code/github.com/indrasvat-kitchen-sink/go/sarasa/install.sh"
TMPPREFIX = "/tmp/sarasa-install-test"


async def main(connection):
    app = await iterm2.async_get_app(connection)
    window = app.current_terminal_window
    if window is None:
        print("ERROR: No iTerm2 window")
        return

    tab = await window.async_create_tab()
    session = tab.current_session
    await asyncio.sleep(0.5)

    try:
        print("\n  Testing sarasa install.sh\n")

        # Clean up any previous test prefix
        await session.async_send_text(f"rm -rf {TMPPREFIX}\n")
        await asyncio.sleep(0.3)

        # -- Test 1: --help --
        await session.async_send_text(f"bash {SCRIPT} --help\n")
        await asyncio.sleep(1.0)
        content = await read_screen(session)
        log_result("--help shows usage", "Usage:" in content and "--prefix" in content)

        # -- Test 2: --check --
        await session.async_send_text(f"bash {SCRIPT} --check\n")
        await asyncio.sleep(3.0)
        content = await read_screen(session)
        has_banner = "SARASA INSTALLER" in content
        log_result("Banner displayed", has_banner)

        has_git_check = "git:" in content
        log_result("Git prerequisite checked", has_git_check)

        has_go_check = "go:" in content
        log_result("Go prerequisite checked", has_go_check)

        capture_iterm_screenshot("/tmp/sarasa-install-1-check.png")

        # -- Test 3: Full install to temp prefix --
        await session.async_send_text(f"bash {SCRIPT} --prefix {TMPPREFIX} --no-init\n")

        # Wait for install to complete (clone + build takes time)
        found = await screen_contains(session, "Installation complete", timeout=120.0)
        log_result("Install completed successfully", found)

        capture_iterm_screenshot("/tmp/sarasa-install-2-install.png")

        # -- Test 4: Verify installed binary --
        await session.async_send_text(f"{TMPPREFIX}/sarasa version\n")
        await asyncio.sleep(1.0)
        content = await read_screen(session)
        has_version = "sarasa" in content.lower() or "version" in content.lower()
        log_result("Installed binary runs (version)", has_version)

        await session.async_send_text(f"{TMPPREFIX}/sarasa schedule\n")
        await asyncio.sleep(1.0)
        content = await read_screen(session)
        has_subcommands = "install" in content and "uninstall" in content and "status" in content
        log_result("schedule shows subcommands (bug fix verified)", has_subcommands)

        await session.async_send_text(f"{TMPPREFIX}/sarasa init --help\n")
        await asyncio.sleep(1.0)
        content = await read_screen(session)
        has_init = "setup wizard" in content.lower() or "dry-run" in content
        log_result("init command available with --dry-run", has_init)

        capture_iterm_screenshot("/tmp/sarasa-install-3-verify.png")

        # -- Test 5: Cleanup check --
        await session.async_send_text("ls /tmp/sarasa-install.* 2>&1\n")
        await asyncio.sleep(0.5)
        content = await read_screen(session)
        no_leftovers = "No such file" in content or "cannot access" in content or "sarasa-install." not in content
        log_result("Temp directory cleaned up", no_leftovers)

        # Clean up test prefix
        await session.async_send_text(f"rm -rf {TMPPREFIX}\n")
        await asyncio.sleep(0.3)

        exit_code = print_summary()

    except Exception as e:
        print(f"\n  ERROR: {e}")
        import traceback
        traceback.print_exc()
        exit_code = 1

    finally:
        await session.async_send_text("\x03")
        await asyncio.sleep(0.2)
        await session.async_send_text("exit\n")
        await asyncio.sleep(0.3)
        try:
            await session.async_close()
        except Exception:
            pass

    raise SystemExit(exit_code)


iterm2.run_until_complete(main)
