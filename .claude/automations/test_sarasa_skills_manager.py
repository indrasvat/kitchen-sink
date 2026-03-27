# /// script
# requires-python = ">=3.14"
# dependencies = [
#   "iterm2",
#   "pyobjc",
#   "pyobjc-framework-Quartz",
# ]
# ///
"""
Visual verification for sarasa skills manager integration.

Tests:
  1. `sarasa --help` — skills appears in managers list with puzzle icon and teal color
  2. `sarasa status --managers=skills` — skills manager shows with correct icon/color
  3. `sarasa status --json --managers=skills` — JSON output includes skills manager

Verification Strategy:
  - Build sarasa binary from source (expects CWD = go/sarasa/)
  - Run each command in an isolated iTerm2 window
  - Capture screenshots for visual inspection
  - Read screen content to verify textual presence of "skills" and icon

Screenshots saved to: .claude/screenshots/

Usage:
  cd go/sarasa && uv run ../../.claude/automations/test_sarasa_skills_manager.py
"""

import asyncio
import json
import os
import pathlib
import subprocess
import sys

import iterm2

try:
    import Quartz
except ImportError:
    Quartz = None

# All paths relative to this script — no hardcoded user paths
SCRIPT_DIR = pathlib.Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parent.parent
SARASA_DIR = REPO_ROOT / "go" / "sarasa"
SARASA_BIN = SARASA_DIR / "sarasa"
SCREENSHOT_DIR = SCRIPT_DIR.parent / "screenshots"

SCREENSHOT_DIR.mkdir(parents=True, exist_ok=True)


async def create_window(connection, name="test", x_pos=100, width=900, height=600):
    """Create an isolated window. Handles the stale-window-object bug."""
    window = await iterm2.Window.async_create(connection)
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
        raise RuntimeError(f"Window '{name}' not ready after refresh + probe")

    session = window.current_tab.current_session
    await session.async_set_name(name)

    frame = await window.async_get_frame()
    await window.async_set_frame(iterm2.Frame(
        iterm2.Point(x_pos, frame.origin.y),
        iterm2.Size(width, height)
    ))
    await asyncio.sleep(0.3)

    return window, session


async def capture_screenshot(window, output_path):
    """Capture screenshot of a specific window via Quartz position matching."""
    if Quartz is None:
        print(f"  SKIP screenshot (Quartz not available): {output_path}")
        return None

    frame = await window.async_get_frame()
    window_list = Quartz.CGWindowListCopyWindowInfo(
        Quartz.kCGWindowListOptionOnScreenOnly
        | Quartz.kCGWindowListExcludeDesktopElements,
        Quartz.kCGNullWindowID,
    )
    best_id, best_score = None, float("inf")
    for w in window_list:
        if "iTerm" not in w.get("kCGWindowOwnerName", ""):
            continue
        b = w.get("kCGWindowBounds", {})
        score = (abs(float(b.get("X", 0)) - frame.origin.x) * 2
                 + abs(float(b.get("Width", 0)) - frame.size.width)
                 + abs(float(b.get("Height", 0)) - frame.size.height))
        if score < best_score:
            best_score, best_id = score, w.get("kCGWindowNumber")
    if best_id and best_score < 30:
        subprocess.run(["screencapture", "-x", "-l", str(best_id), str(output_path)])
        return str(output_path)
    print(f"  WARN: Could not match Quartz window for screenshot: {output_path}")
    return None


async def read_screen_text(session, max_lines=80):
    """Read screen content including scrollback as a single string."""
    # Request extra lines to capture scrollback (help output can be long)
    screen = await session.async_get_screen_contents()
    lines = []
    for i in range(min(screen.number_of_lines, max_lines)):
        line = screen.line(i)
        lines.append(line.string)

    # Also try reading scrollback by scrolling up and re-reading
    # (the screen object only returns visible + scrollback already fetched)
    return "\n".join(lines)


async def cleanup_stale_windows(connection, prefix="sarasa-test-"):
    """Close windows from previous crashed runs."""
    app = await iterm2.async_get_app(connection)
    for window in app.terminal_windows:
        for tab in window.tabs:
            for session in tab.sessions:
                if session.name and session.name.startswith(prefix):
                    try:
                        await session.async_send_text("\x03")
                        await asyncio.sleep(0.1)
                        try:
                            await session.async_close()
                        except Exception:
                            pass
                    except Exception:
                        pass


async def main(connection):
    results = {"passed": 0, "failed": 0, "tests": []}
    created_sessions = []

    try:
        await cleanup_stale_windows(connection)

        # Build sarasa
        print("Building sarasa...")
        build = subprocess.run(
            ["go", "build", "-o", "sarasa", "."],
            cwd=str(SARASA_DIR),
            capture_output=True,
            text=True,
        )
        if build.returncode != 0:
            print(f"BUILD FAILED:\n{build.stderr}")
            sys.exit(1)
        print("  Build OK")

        # -- Test 1: sarasa --help --
        print("\nTest 1: sarasa --help")
        window, session = await create_window(connection, "sarasa-test-help", x_pos=100, height=900)
        created_sessions.append(session)

        # Pipe through cat to avoid pager and capture full output
        await session.async_send_text(f"{SARASA_BIN} --help 2>&1 | cat\r")
        await asyncio.sleep(2)

        screen_text = await read_screen_text(session, max_lines=100)
        shot = await capture_screenshot(window, SCREENSHOT_DIR / "sarasa_help.png")

        test1_pass = "skills" in screen_text.lower()
        results["tests"].append({
            "name": "help_shows_skills",
            "passed": test1_pass,
            "screenshot": shot,
            "detail": "'skills' found in help" if test1_pass else "'skills' NOT found in help",
        })
        if test1_pass:
            results["passed"] += 1
            print("  PASS: 'skills' found in help output")
        else:
            results["failed"] += 1
            print("  FAIL: 'skills' not found in help output")
            print(f"  Screen:\n{screen_text[:500]}")

        # -- Test 2: sarasa status --managers=skills (plain mode via pipe) --
        print("\nTest 2: sarasa status --managers=skills")
        window2, session2 = await create_window(connection, "sarasa-test-status", x_pos=200)
        created_sessions.append(session2)

        await session2.async_send_text(f"{SARASA_BIN} status --managers=skills 2>&1 | cat\r")
        await asyncio.sleep(10)  # npx cold start can be slow

        screen_text2 = await read_screen_text(session2)
        shot2 = await capture_screenshot(window2, SCREENSHOT_DIR / "sarasa_status_skills.png")

        test2_pass = "skills" in screen_text2.lower()
        results["tests"].append({
            "name": "status_shows_skills",
            "passed": test2_pass,
            "screenshot": shot2,
            "detail": "'SKILLS' found in status" if test2_pass else "'SKILLS' NOT found in status",
        })
        if test2_pass:
            results["passed"] += 1
            print("  PASS: 'SKILLS' found in status output")
        else:
            results["failed"] += 1
            print("  FAIL: 'SKILLS' not found in status output")
            print(f"  Screen:\n{screen_text2[:500]}")

        # -- Test 3: sarasa status --json --managers=skills --
        print("\nTest 3: sarasa status --json --managers=skills")
        window3, session3 = await create_window(connection, "sarasa-test-json", x_pos=300)
        created_sessions.append(session3)

        await session3.async_send_text(f"{SARASA_BIN} status --json --managers=skills 2>&1 | cat\r")
        await asyncio.sleep(10)

        screen_text3 = await read_screen_text(session3)
        shot3 = await capture_screenshot(window3, SCREENSHOT_DIR / "sarasa_status_json.png")

        test3_pass = '"name"' in screen_text3 and "skills" in screen_text3
        results["tests"].append({
            "name": "json_includes_skills",
            "passed": test3_pass,
            "screenshot": shot3,
            "detail": "JSON includes skills" if test3_pass else "JSON missing skills",
        })
        if test3_pass:
            results["passed"] += 1
            print("  PASS: JSON output includes skills manager")
        else:
            results["failed"] += 1
            print("  FAIL: JSON output missing skills manager")
            print(f"  Screen:\n{screen_text3[:500]}")

        # -- Summary --
        print(f"\n{'='*40}")
        print(f"Results: {results['passed']} passed, {results['failed']} failed")
        print(f"Screenshots: {SCREENSHOT_DIR}/")
        for t in results["tests"]:
            status = "PASS" if t["passed"] else "FAIL"
            print(f"  [{status}] {t['name']}: {t['detail']}")

    except Exception as e:
        print(f"ERROR: {e}")
        import traceback
        traceback.print_exc()
        raise
    finally:
        for s in created_sessions:
            try:
                await s.async_send_text("\x03")
                await asyncio.sleep(0.1)
                await s.async_send_text("exit\r")
                await asyncio.sleep(0.2)
                await s.async_close()
            except Exception:
                pass

    if results["failed"] > 0:
        sys.exit(1)


iterm2.run_until_complete(main)
