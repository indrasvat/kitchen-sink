# /// script
# requires-python = ">=3.14"
# dependencies = [
#   "iterm2",
#   "pyobjc",
#   "pyobjc-framework-Quartz",
# ]
# ///
"""
Test: sarasa init --force TUI wizard
=====================================

Tests:
  1. Launch sarasa init --force — verify manager selection screen renders
  2. Verify available managers are pre-selected (checked)
  3. Press Enter to confirm managers → verify schedule screen renders
  4. Navigate down to "Every hour" and press Enter
  5. Verify config written and launchd agent installed messages

Verification Strategy:
  - Read screen contents after each step
  - Check for expected strings (SARASA INIT, Package managers, schedule, etc.)
  - Screenshot at each phase for visual review

Screenshots:
  - /tmp/sarasa-init-1-managers.png   — manager selection screen
  - /tmp/sarasa-init-2-schedule.png   — schedule selection screen
  - /tmp/sarasa-init-3-result.png     — final result output

Key Bindings:
  - Space: toggle manager selection
  - j/k: navigate up/down
  - Enter: confirm selection
  - q/Ctrl+C: cancel

Usage:
  uv run .claude/automations/test-sarasa-init.py
"""

import asyncio
import subprocess
from pathlib import Path
import iterm2


# -- Screenshot helper --
def capture_iterm_screenshot(path: str) -> bool:
    """Capture iTerm2 window screenshot using screencapture."""
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
            print(f"  WARN: iTerm2 window not found for screenshot {path}")
            return False
        subprocess.run(
            ["screencapture", "-l", str(iterm_id), "-x", path],
            check=True, capture_output=True,
        )
        print(f"  Screenshot saved: {path}")
        return True
    except Exception as e:
        print(f"  WARN: Screenshot failed: {e}")
        return False


# -- Screen reading helper --
async def read_screen(session) -> str:
    """Read all visible lines from session."""
    screen = await session.async_get_screen_contents()
    lines = []
    for i in range(screen.number_of_lines):
        lines.append(screen.line(i).string)
    return "\n".join(lines)


async def screen_contains(session, text: str, timeout: float = 3.0) -> bool:
    """Wait for screen to contain text, with timeout."""
    deadline = asyncio.get_event_loop().time() + timeout
    while asyncio.get_event_loop().time() < deadline:
        content = await read_screen(session)
        if text in content:
            return True
        await asyncio.sleep(0.3)
    return False


# -- Test tracking --
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


REPO_ROOT = Path(__file__).resolve().parents[2]
SARASA_DIR = REPO_ROOT / "go" / "sarasa"
SARASA_BIN = "/tmp/sarasa-test"


async def main(connection):
    app = await iterm2.async_get_app(connection)
    window = app.current_terminal_window
    if window is None:
        print("ERROR: No iTerm2 window found")
        return

    # Build sarasa binary
    print("  Building sarasa...")
    build = subprocess.run(
        ["go", "build", "-o", SARASA_BIN, "."],
        cwd=str(SARASA_DIR),
        capture_output=True, text=True,
    )
    if build.returncode != 0:
        print(f"  BUILD FAILED:\n{build.stderr}")
        return
    print("  Build OK")

    # Create a new tab for testing
    tab = await window.async_create_tab()
    session = tab.current_session
    await asyncio.sleep(0.5)

    try:
        # Ensure we're in the right directory
        await session.async_send_text(
            f"cd {SARASA_DIR}\n"
        )
        await asyncio.sleep(0.3)

        # -- Test 1: Launch init wizard --
        print("\n  Testing sarasa init --force TUI wizard\n")
        await session.async_send_text(f"{SARASA_BIN} init --force\n")
        await asyncio.sleep(1.0)

        found = await screen_contains(session, "SARASA INIT")
        log_result("Init wizard launches", found)

        found_mgr = await screen_contains(session, "Package managers")
        log_result("Manager selection screen shown", found_mgr)

        # Check that available managers are pre-selected
        content = await read_screen(session)
        has_check = "✓" in content
        log_result("Available managers pre-selected", has_check)

        # Screenshot phase 1
        capture_iterm_screenshot("/tmp/sarasa-init-1-managers.png")

        # -- Test 2: Confirm managers, go to schedule --
        await session.async_send_text("\r")  # Enter
        await asyncio.sleep(0.8)

        found_sched = await screen_contains(session, "Upgrade schedule")
        log_result("Schedule selection screen shown", found_sched)

        content = await read_screen(session)
        has_hourly = "Every hour" in content
        log_result("Schedule options displayed", has_hourly)

        # Screenshot phase 2
        capture_iterm_screenshot("/tmp/sarasa-init-2-schedule.png")

        # -- Test 3: Select "Every hour" (first option) --
        # Navigate up to ensure we're at "Every hour"
        await session.async_send_text("\x1b[A")  # Up arrow
        await asyncio.sleep(0.2)
        await session.async_send_text("\x1b[A")  # Up arrow again
        await asyncio.sleep(0.2)
        await session.async_send_text("\x1b[A")  # One more
        await asyncio.sleep(0.2)
        await session.async_send_text("\x1b[A")  # One more to be safe
        await asyncio.sleep(0.2)

        await session.async_send_text("\r")  # Enter to select
        await asyncio.sleep(1.5)

        content = await read_screen(session)
        config_written = "Config written" in content or "✓" in content
        log_result("Config written confirmation", config_written)

        has_schedule_msg = "Schedule" in content or "Every hour" in content or "Launchd" in content
        log_result("Schedule confirmation shown", has_schedule_msg)

        has_launchd = "Launchd" in content or "launchd" in content
        log_result("Launchd agent installed", has_launchd)

        # Screenshot phase 3
        capture_iterm_screenshot("/tmp/sarasa-init-3-result.png")

        # -- Test 4: Verify config file was written --
        await session.async_send_text("cat ~/.config/sarasa/config.toml\n")
        await asyncio.sleep(0.5)

        content = await read_screen(session)
        has_times = "01:00" in content or "times" in content
        log_result("Config file contains schedule times", has_times)

        exit_code = print_summary()

    except Exception as e:
        print(f"\n  ERROR: {e}")
        import traceback
        traceback.print_exc()
        exit_code = 1

    finally:
        # Cleanup
        await session.async_send_text("\x03")  # Ctrl+C in case TUI is stuck
        await asyncio.sleep(0.3)
        await session.async_send_text("exit\n")
        await asyncio.sleep(0.3)
        await session.async_close()

    raise SystemExit(exit_code)


iterm2.run_until_complete(main)
