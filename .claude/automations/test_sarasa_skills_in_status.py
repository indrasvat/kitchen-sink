# /// script
# requires-python = ">=3.14"
# dependencies = [
#   "iterm2",
#   "pyobjc",
#   "pyobjc-framework-Quartz",
# ]
# ///
"""
Visual test: verify 'skills' manager appears in `sarasa status` and `sarasa run --dry-run`.

After adding 'skills' to DefaultConfig().Managers, this test confirms:
    1. `sarasa status` output includes a SKILLS section header
    2. `sarasa run --dry-run` output includes a SKILLS section header
    3. `sarasa --help` long description mentions 'skills'

Verification Strategy:
    - Build sarasa from local source on the fix branch
    - Run each command in a dedicated iTerm2 window
    - Read screen contents and assert SKILLS header is present
    - Capture screenshots of each output for visual inspection

Screenshots:
    - sarasa_status_skills_01_status.png: `sarasa status` output with SKILLS section
    - sarasa_status_skills_02_run_dryrun.png: `sarasa run --dry-run` with SKILLS section
    - sarasa_status_skills_03_help.png: `sarasa --help` mentioning skills

Screenshot Inspection Checklist:
    - SKILLS section header visible with correct icon/color
    - All 5 default managers shown (brew, volta, pipx, bun, skills)
    - No errors or panics in output

Key Bindings:
    - q: quit TUI (if accidentally entered)
    - Ctrl+C: interrupt

Usage:
    uv run .claude/automations/test_sarasa_skills_in_status.py
"""

import asyncio
import os
import subprocess
import sys
import time
from datetime import datetime
from pathlib import Path

import iterm2

try:
    import Quartz
except ImportError:
    Quartz = None

# ============================================================
# CONFIGURATION
# ============================================================

PROJECT_ROOT = Path(__file__).parent.parent.parent
SARASA_DIR = PROJECT_ROOT / "go" / "sarasa"
SCREENSHOT_DIR = PROJECT_ROOT / ".claude" / "automations" / "screenshots"
TIMEOUT_SECONDS = 10.0

# ============================================================
# RESULT TRACKING
# ============================================================

results = {
    "passed": 0,
    "failed": 0,
    "tests": [],
    "screenshots": [],
    "start_time": None,
}


def log_result(test_name, status, details="", screenshot=None):
    results["tests"].append({"name": test_name, "status": status, "details": details})
    if screenshot:
        results["screenshots"].append(screenshot)
    symbol = "+" if status == "PASS" else "x"
    results["passed" if status == "PASS" else "failed"] += 1
    print(f"  [{symbol}] {status}: {test_name}")
    if details:
        print(f"      {details}")
    if screenshot:
        print(f"      Screenshot: {screenshot}")


def print_summary():
    total = results["passed"] + results["failed"]
    duration = (datetime.now() - results["start_time"]).total_seconds() if results["start_time"] else 0
    print(f"\n{'=' * 60}")
    print("TEST SUMMARY")
    print(f"{'=' * 60}")
    print(f"Duration:    {duration:.1f}s")
    print(f"Total:       {total}")
    print(f"Passed:      {results['passed']}")
    print(f"Failed:      {results['failed']}")
    if results["screenshots"]:
        print(f"Screenshots: {len(results['screenshots'])}")
    print("=" * 60)
    if results["failed"] > 0:
        print("\nFailed tests:")
        for t in results["tests"]:
            if t["status"] == "FAIL":
                print(f"  - {t['name']}: {t['details']}")
        print("\nOVERALL: FAILED")
        return 1
    print("\nOVERALL: PASSED")
    return 0


# ============================================================
# QUARTZ SCREENSHOT
# ============================================================


def find_quartz_window_id(target_x, target_w, target_h, tolerance=30):
    if not Quartz:
        return None
    window_list = Quartz.CGWindowListCopyWindowInfo(
        Quartz.kCGWindowListOptionOnScreenOnly | Quartz.kCGWindowListExcludeDesktopElements,
        Quartz.kCGNullWindowID,
    )
    best_id, best_score = None, float("inf")
    for w in window_list:
        if "iTerm" not in w.get("kCGWindowOwnerName", ""):
            continue
        b = w.get("kCGWindowBounds", {})
        score = (
            abs(float(b.get("X", 0)) - target_x) * 2
            + abs(float(b.get("Width", 0)) - target_w)
            + abs(float(b.get("Height", 0)) - target_h)
        )
        if score < best_score:
            best_score, best_id = score, w.get("kCGWindowNumber")
    return best_id if best_score < tolerance else None


async def capture_screenshot(window, name):
    SCREENSHOT_DIR.mkdir(parents=True, exist_ok=True)
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    filepath = SCREENSHOT_DIR / f"sarasa_status_skills_{name}_{timestamp}.png"

    frame = await window.async_get_frame()
    qid = find_quartz_window_id(frame.origin.x, frame.size.width, frame.size.height)

    if qid:
        subprocess.run(["screencapture", "-x", "-l", str(qid), str(filepath)], check=True)
    else:
        subprocess.run(["screencapture", "-x", str(filepath)], check=True)

    print(f"  SCREENSHOT: {filepath.name}")
    return str(filepath)


# ============================================================
# WINDOW CREATION
# ============================================================


async def create_test_window(connection, name="test", x_pos=100, width=800, height=600):
    window = await iterm2.Window.async_create(connection)
    if window is None:
        raise RuntimeError("Window.async_create() returned None")

    await asyncio.sleep(0.5)

    app = await iterm2.async_get_app(connection)
    if window.current_tab is None:
        for w in app.terminal_windows:
            if w.window_id == window.window_id:
                window = w
                break

    for _ in range(20):
        if window.current_tab and window.current_tab.current_session:
            break
        await asyncio.sleep(0.2)

    if not window.current_tab or not window.current_tab.current_session:
        raise RuntimeError("Window tab/session not ready after timeout")

    session = window.current_tab.current_session
    await session.async_set_name(name)

    frame = await window.async_get_frame()
    await window.async_set_frame(
        iterm2.Frame(
            iterm2.Point(x_pos, frame.origin.y),
            iterm2.Size(width, height),
        )
    )
    await asyncio.sleep(0.3)
    return window, session


# ============================================================
# VERIFICATION HELPERS
# ============================================================


async def get_all_screen_text(session):
    screen = await session.async_get_screen_contents()
    lines = []
    for i in range(screen.number_of_lines):
        lines.append(screen.line(i).string)
    return lines


async def wait_for_text(session, target, timeout=None):
    timeout = timeout or TIMEOUT_SECONDS
    start = time.monotonic()
    while (time.monotonic() - start) < timeout:
        lines = await get_all_screen_text(session)
        for line in lines:
            if target in line:
                return True
        await asyncio.sleep(0.3)
    return False


async def dump_screen(session, label):
    lines = await get_all_screen_text(session)
    print(f"\n{'=' * 60}")
    print(f"SCREEN DUMP: {label}")
    print(f"{'=' * 60}")
    for i, line in enumerate(lines):
        if line.strip():
            print(f"{i:03d}: {line}")
    print(f"{'=' * 60}\n")


async def cleanup_session(session):
    try:
        await session.async_send_text("\x03")
        await asyncio.sleep(0.1)
        await session.async_send_text("exit\n")
        await asyncio.sleep(0.2)
        await session.async_close()
    except Exception:
        pass


# ============================================================
# MAIN
# ============================================================


async def main(connection):
    results["start_time"] = datetime.now()

    print("\n" + "#" * 60)
    print("# TEST: skills manager in sarasa status/run/help")
    print("#" * 60)

    # Build sarasa from source
    print("\nBuilding sarasa from local source...")
    build = subprocess.run(
        ["go", "build", "-o", "/tmp/sarasa-test", "."],
        cwd=str(SARASA_DIR),
        capture_output=True,
        text=True,
    )
    if build.returncode != 0:
        print(f"BUILD FAILED:\n{build.stderr}")
        log_result("Build", "FAIL", build.stderr)
        return print_summary()
    print("  Build OK")

    sarasa = "/tmp/sarasa-test"
    window, session = await create_test_window(connection, "sarasa-skills-test", x_pos=150)
    created_sessions = [session]

    try:
        # ============================================================
        # TEST 1: sarasa status shows SKILLS section
        # ============================================================
        print(f"\n{'=' * 60}")
        print("TEST 1: sarasa status shows SKILLS section")
        print(f"{'=' * 60}")

        # Run in non-TUI mode (pipe through cat to force styled/plain)
        await session.async_send_text(f"clear && {sarasa} status 2>&1 | cat\n")
        await asyncio.sleep(8)  # status checks can take a few seconds

        found = await wait_for_text(session, "SKILLS", timeout=5)
        screenshot = await capture_screenshot(window, "01_status")

        if found:
            log_result("sarasa status shows SKILLS", "PASS", screenshot=screenshot)
        else:
            await dump_screen(session, "status output")
            log_result("sarasa status shows SKILLS", "FAIL",
                       "SKILLS header not found in status output", screenshot=screenshot)

        # ============================================================
        # TEST 2: sarasa run --dry-run shows SKILLS section
        # ============================================================
        print(f"\n{'=' * 60}")
        print("TEST 2: sarasa run --dry-run shows SKILLS section")
        print(f"{'=' * 60}")

        await session.async_send_text(f"clear && {sarasa} run --dry-run 2>&1 | cat\n")
        await asyncio.sleep(8)

        found = await wait_for_text(session, "SKILLS", timeout=5)
        screenshot = await capture_screenshot(window, "02_run_dryrun")

        if found:
            log_result("sarasa run --dry-run shows SKILLS", "PASS", screenshot=screenshot)
        else:
            await dump_screen(session, "run --dry-run output")
            log_result("sarasa run --dry-run shows SKILLS", "FAIL",
                       "SKILLS header not found in run output", screenshot=screenshot)

        # ============================================================
        # TEST 3: sarasa --help mentions skills
        # ============================================================
        print(f"\n{'=' * 60}")
        print("TEST 3: sarasa --help mentions skills")
        print(f"{'=' * 60}")

        await session.async_send_text(f"clear && {sarasa} --help 2>&1\n")
        await asyncio.sleep(2)

        found = await wait_for_text(session, "skills", timeout=3)
        screenshot = await capture_screenshot(window, "03_help")

        if found:
            log_result("sarasa --help mentions skills", "PASS", screenshot=screenshot)
        else:
            await dump_screen(session, "help output")
            log_result("sarasa --help mentions skills", "FAIL",
                       "'skills' not found in help output", screenshot=screenshot)

        # ============================================================
        # TEST 4: sarasa status --json includes skills manager
        # ============================================================
        print(f"\n{'=' * 60}")
        print("TEST 4: sarasa status --json includes skills manager")
        print(f"{'=' * 60}")

        json_out = subprocess.run(
            [sarasa, "status", "--json"],
            capture_output=True, text=True, timeout=30,
        )
        if '"skills"' in json_out.stdout or '"name":"skills"' in json_out.stdout.replace(" ", ""):
            log_result("sarasa status --json includes skills", "PASS",
                       "Found skills manager in JSON output")
        else:
            log_result("sarasa status --json includes skills", "FAIL",
                       f"skills not in JSON: {json_out.stdout[:200]}")

    except Exception as e:
        print(f"\nERROR: {e}")
        log_result("Test Execution", "FAIL", str(e))
        try:
            await dump_screen(session, "error_state")
        except Exception:
            pass

    finally:
        for s in created_sessions:
            await cleanup_session(s)

    return print_summary()


if __name__ == "__main__":
    exit_code = iterm2.run_until_complete(main)
    sys.exit(exit_code or 0)
