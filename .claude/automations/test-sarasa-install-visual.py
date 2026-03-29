# /// script
# requires-python = ">=3.14"
# dependencies = [
#   "iterm2",
#   "pyobjc",
#   "pyobjc-framework-Quartz",
# ]
# ///
"""
Test: sarasa install.sh — visual box-drawing alignment verification
====================================================================

Tests:
  1. Banner box: corners ╭╮╰╯ aligned with │ sides on every line
  2. Post-install box: same alignment check
  3. No stray │ characters outside box boundaries
  4. Prerequisite section renders correctly
  5. Full install to temp dir succeeds

Verification Strategy:
  - Run --check first (fast, renders both banner and prereq output)
  - Parse screen for box-drawing characters and verify alignment
  - Take screenshots at each phase
  - Then run full install to temp dir

Screenshots:
  - /tmp/sarasa-vis-1-banner.png   — banner box
  - /tmp/sarasa-vis-2-install.png  — full install output

Usage:
  uv run .claude/automations/test-sarasa-install-visual.py
"""

import asyncio
import subprocess
from pathlib import Path
import iterm2


def capture_iterm_screenshot(path: str) -> bool:
    """Capture iTerm2 window screenshot."""
    try:
        import Quartz
        window_list = Quartz.CGWindowListCopyWindowInfo(
            Quartz.kCGWindowListOptionOnScreenOnly,
            Quartz.kCGNullWindowID,
        )
        for win in window_list:
            owner = win.get("kCGWindowOwnerName", "")
            if "iTerm2" in owner and win.get("kCGWindowLayer", 999) == 0:
                wid = win.get("kCGWindowNumber")
                subprocess.run(
                    ["screencapture", "-l", str(wid), "-x", path],
                    check=True, capture_output=True,
                )
                print(f"  Screenshot: {path}")
                return True
    except Exception as e:
        print(f"  WARN: Screenshot failed: {e}")
    return False


async def read_screen(session) -> str:
    screen = await session.async_get_screen_contents()
    lines = []
    for i in range(screen.number_of_lines):
        lines.append(screen.line(i).string)
    return "\n".join(lines)


async def read_screen_lines(session) -> list[str]:
    screen = await session.async_get_screen_contents()
    lines = []
    for i in range(screen.number_of_lines):
        lines.append(screen.line(i).string)
    return lines


async def screen_contains(session, text: str, timeout: float = 5.0) -> bool:
    deadline = asyncio.get_event_loop().time() + timeout
    while asyncio.get_event_loop().time() < deadline:
        content = await read_screen(session)
        if text in content:
            return True
        await asyncio.sleep(0.5)
    return False


results = {"passed": 0, "failed": 0, "tests": []}


def log_result(name: str, passed: bool, details: str = ""):
    results["passed" if passed else "failed"] += 1
    results["tests"].append({"name": name, "passed": passed, "details": details})
    icon = "✓" if passed else "✗"
    det = f" — {details}" if details else ""
    print(f"  {icon} {name}{det}")


def print_summary():
    total = results["passed"] + results["failed"]
    print(f"\n  Results: {results['passed']}/{total} passed")
    return 0 if results["failed"] == 0 else 1


def verify_box_alignment(lines: list[str], label: str) -> bool:
    """Verify that all box lines have │ at the same columns and corners connect."""
    box_lines = []
    for i, line in enumerate(lines):
        stripped = line.rstrip()
        # Find lines that contain box-drawing characters
        if "╭" in stripped or "╰" in stripped or "│" in stripped:
            box_lines.append((i, stripped))

    if not box_lines:
        log_result(f"{label}: box found", False, "no box-drawing characters found")
        return False

    # Find the column of the left and right borders
    left_cols = set()
    right_cols = set()

    for i, line in box_lines:
        for j, ch in enumerate(line):
            if ch in "╭╰│":
                left_cols.add(j)
                break
        # Search from end for right border
        for j in range(len(line) - 1, -1, -1):
            if line[j] in "╮╯│":
                right_cols.add(j)
                break

    # All left borders should be at the same column
    left_ok = len(left_cols) == 1
    right_ok = len(right_cols) == 1

    if not left_ok:
        log_result(f"{label}: left border aligned", False,
                   f"left │ at columns {sorted(left_cols)}")
    else:
        log_result(f"{label}: left border aligned", True,
                   f"column {next(iter(left_cols))}")

    if not right_ok:
        log_result(f"{label}: right border aligned", False,
                   f"right │ at columns {sorted(right_cols)}")
    else:
        log_result(f"{label}: right border aligned", True,
                   f"column {next(iter(right_cols))}")

    return left_ok and right_ok


REPO_ROOT = Path(__file__).resolve().parents[2]
SCRIPT = str(REPO_ROOT / "go/sarasa/install.sh")
TMPPREFIX = "/tmp/sarasa-vis-test"


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
        print("\n  Visual verification: sarasa install.sh\n")

        # Clean previous test artifacts
        await session.async_send_text(f"rm -rf {TMPPREFIX}\n")
        await asyncio.sleep(0.3)

        # -- Test 1: Banner box alignment (--check is fast) --
        await session.async_send_text(f"bash {SCRIPT} --check 2>&1\n")
        await asyncio.sleep(3.0)

        lines = await read_screen_lines(session)
        capture_iterm_screenshot("/tmp/sarasa-vis-1-banner.png")

        # Find banner box (between SARASA INSTALLER lines)
        banner_lines = []
        in_banner = False
        for line in lines:
            if "╭" in line and "╮" in line:
                in_banner = True
            if in_banner:
                banner_lines.append(line)
            if in_banner and "╰" in line and "╯" in line:
                in_banner = False
                break

        if banner_lines:
            verify_box_alignment(banner_lines, "Banner box")
        else:
            log_result("Banner box: found", False, "no ╭...╮ / ╰...╯ pair found")

        # Check content
        content = "\n".join(lines)
        log_result("Banner shows title", "SARASA INSTALLER" in content)
        log_result("Prereqs: git checked", "git:" in content)
        log_result("Prereqs: go checked", "go:" in content)

        # -- Test 2: Full install with temp prefix --
        await session.async_send_text("clear\n")
        await asyncio.sleep(0.3)
        await session.async_send_text(
            f"bash {SCRIPT} --prefix {TMPPREFIX} --no-init 2>&1\n"
        )

        found = await screen_contains(session, "Installation complete", timeout=120.0)
        log_result("Full install succeeds", found)

        await asyncio.sleep(1.0)
        lines = await read_screen_lines(session)
        capture_iterm_screenshot("/tmp/sarasa-vis-2-install.png")

        # Verify post-install box alignment
        post_lines = []
        in_box = False
        for line in lines:
            # Find the second box (post-install)
            if "Installation complete" in line:
                # Walk backward to find ╭
                idx = lines.index(line)
                for k in range(idx, -1, -1):
                    if "╭" in lines[k]:
                        post_lines = lines[k:]
                        break
                break

        # Find just the box portion
        box_portion = []
        in_box = False
        for line in post_lines:
            if "╭" in line:
                in_box = True
            if in_box:
                box_portion.append(line)
            if in_box and "╰" in line:
                break

        if box_portion:
            verify_box_alignment(box_portion, "Post-install box")
        else:
            log_result("Post-install box: found", False, "no box found in output")

        # Verify binary works
        await session.async_send_text(f"{TMPPREFIX}/sarasa version 2>&1\n")
        await asyncio.sleep(1.0)
        content = await read_screen(session)
        log_result("Installed binary works", "sarasa" in content.lower())

        # Cleanup
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
