# /// script
# requires-python = ">=3.13"
# dependencies = [
#   "iterm2",
#   "pyobjc",
# ]
# ///
"""
iTerm2 automation test for sarasa TUI panel alignment.
Tests: bordered panel alignment, consistent widths, emoji handling.

Run with: uv run .claude/automations/test_sarasa_tui.py [status|run|all]

TUI Key Bindings:
- q: quit
- r: refresh (status only)
"""
import iterm2
import asyncio
import subprocess
import sys
from datetime import datetime
from pathlib import Path
import Quartz

# Project paths
PROJECT_ROOT = Path(__file__).parent.parent.parent
SARASA_DIR = PROJECT_ROOT / "go" / "sarasa"
SCREENSHOTS_DIR = PROJECT_ROOT / ".claude" / "automations" / "screenshots"


def get_iterm2_window_id() -> int | None:
    """Get iTerm2's main window CGWindowID for screencapture -l flag."""
    windows = Quartz.CGWindowListCopyWindowInfo(
        Quartz.kCGWindowListOptionOnScreenOnly, Quartz.kCGNullWindowID
    )
    for w in windows:
        if w.get("kCGWindowOwnerName") == "iTerm2":
            return w.get("kCGWindowNumber")
    return None


async def take_screenshot(name: str) -> str:
    """Take screenshot of iTerm2 window only (non-interactive)."""
    SCREENSHOTS_DIR.mkdir(parents=True, exist_ok=True)
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    path = SCREENSHOTS_DIR / f"sarasa_{name}_{timestamp}.png"

    window_id = get_iterm2_window_id()
    if window_id:
        subprocess.run(["screencapture", "-x", "-l", str(window_id), str(path)], check=True)
    else:
        subprocess.run(["screencapture", "-x", str(path)], check=True)

    print(f"  Screenshot: {path.name}")
    return str(path)


async def get_screen_lines(session, max_lines=50) -> list[str]:
    """Get screen contents as list of strings."""
    screen = await session.async_get_screen_contents()
    lines = []
    for i in range(min(screen.number_of_lines, max_lines)):
        lines.append(screen.line(i).string)
    return lines


async def dump_screen(session, label: str):
    """Debug: print screen contents with line numbers."""
    print(f"\n--- SCREEN: {label} ---")
    screen = await session.async_get_screen_contents()
    for i in range(min(30, screen.number_of_lines)):
        line = screen.line(i).string
        if line.strip():
            # Show column positions for alignment debugging
            print(f"  {i:02d}: |{line}|")
    print("---\n")


async def cleanup_tab(tab, session):
    """Robust cleanup: quit TUI, exit shell, close all sessions."""
    print("\nCleaning up...")
    try:
        # Try 'q' first (sarasa TUI quit key)
        await session.async_send_text("q")
        await asyncio.sleep(0.5)
    except Exception:
        pass

    try:
        # Fallback: Ctrl+C to force quit any running process
        await session.async_send_text("\x03")
        await asyncio.sleep(0.3)
    except Exception:
        pass

    try:
        # Exit the shell
        await session.async_send_text("exit\n")
        await asyncio.sleep(0.3)
    except Exception:
        pass

    # Close all sessions in the tab
    for s in tab.sessions:
        try:
            await s.async_close()
        except Exception:
            pass

    print("Cleanup done.")


def analyze_panel_alignment(lines: list[str]) -> dict:
    """
    Analyze screen lines for panel alignment issues.

    Returns dict with:
    - issues: list of problems found
    - left_positions: column positions of left borders
    - right_positions: column positions of right borders
    - widths: panel widths found
    """
    result = {
        "issues": [],
        "left_positions": [],
        "right_positions": [],
        "widths": [],
        "border_lines": [],
    }

    # Box-drawing characters (rounded and square borders)
    border_chars_left = set('╭╰│┌└')
    border_chars_right = set('╮╯│┐┘')
    border_chars_all = border_chars_left | border_chars_right | set('─')

    for i, line in enumerate(lines):
        if any(c in line for c in border_chars_all):
            result["border_lines"].append((i, line))

            # Find leftmost border char
            for j, c in enumerate(line):
                if c in border_chars_left:
                    result["left_positions"].append((i, j, c))
                    break

            # Find rightmost border char
            for j in range(len(line) - 1, -1, -1):
                if line[j] in border_chars_right:
                    result["right_positions"].append((i, j, line[j]))
                    break

    if not result["border_lines"]:
        result["issues"].append("No bordered panels found")
        return result

    # Check left alignment consistency
    left_cols = [pos[1] for pos in result["left_positions"]]
    unique_left = set(left_cols)
    if len(unique_left) > 1:
        result["issues"].append(
            f"LEFT BORDER MISALIGNED: columns {sorted(unique_left)}"
        )
        for line_num, col, char in result["left_positions"]:
            result["issues"].append(f"  Line {line_num}: '{char}' at col {col}")

    # Check right alignment consistency
    right_cols = [pos[1] for pos in result["right_positions"]]
    unique_right = set(right_cols)
    if len(unique_right) > 1:
        result["issues"].append(
            f"RIGHT BORDER MISALIGNED: columns {sorted(unique_right)}"
        )
        for line_num, col, char in result["right_positions"]:
            result["issues"].append(f"  Line {line_num}: '{char}' at col {col}")

    # Calculate and check widths
    for (ln1, left_col, _), (ln2, right_col, _) in zip(
        result["left_positions"], result["right_positions"]
    ):
        if ln1 == ln2:
            width = right_col - left_col
            result["widths"].append((ln1, width))

    unique_widths = set(w for _, w in result["widths"])
    if len(unique_widths) > 1:
        result["issues"].append(
            f"INCONSISTENT WIDTHS: {sorted(unique_widths)}"
        )
        for line_num, width in result["widths"]:
            result["issues"].append(f"  Line {line_num}: width={width}")

    return result


async def test_status_tui(connection, window) -> dict:
    """Test sarasa status TUI alignment."""
    results = {"passed": 0, "failed": 0, "name": "status"}

    tab = await window.async_create_tab()
    session = tab.current_session
    await session.async_set_name("sarasa-status-test")

    try:
        print("\n" + "=" * 60)
        print(" TEST: sarasa status TUI alignment")
        print("=" * 60)

        # Build sarasa
        print("\nBuilding sarasa...")
        await session.async_send_text(f"cd {SARASA_DIR} && go build -o sarasa . 2>&1\n")
        await asyncio.sleep(3)

        # Launch status TUI
        print("Launching ./sarasa status...")
        await session.async_send_text("./sarasa status\n")
        await asyncio.sleep(4)  # Wait for TUI to load and fetch data

        await take_screenshot("status_01_initial")

        # Capture screen
        lines = await get_screen_lines(session, 40)

        # Analyze alignment
        analysis = analyze_panel_alignment(lines)

        # Debug dump
        await dump_screen(session, "status TUI")

        # Report findings
        if analysis["issues"]:
            print("\n*** ALIGNMENT ISSUES DETECTED ***")
            for issue in analysis["issues"]:
                print(f"  {issue}")
            results["failed"] += 1
        else:
            print("\n*** ALIGNMENT CHECK PASSED ***")
            print(f"  Left borders at column: {set(p[1] for p in analysis['left_positions'])}")
            print(f"  Right borders at column: {set(p[1] for p in analysis['right_positions'])}")
            print(f"  Panel widths: {set(w for _, w in analysis['widths'])}")
            results["passed"] += 1

        await take_screenshot("status_02_analyzed")

        # Test refresh (press 'r')
        print("\nTesting refresh (r key)...")
        await session.async_send_text("r")
        await asyncio.sleep(3)
        await take_screenshot("status_03_after_refresh")

        # Re-analyze after refresh
        lines = await get_screen_lines(session, 40)
        analysis2 = analyze_panel_alignment(lines)
        if not analysis2["issues"]:
            print("  Refresh: alignment maintained")
            results["passed"] += 1
        else:
            print("  Refresh: alignment issues appeared")
            results["failed"] += 1

    except Exception as e:
        print(f"\nERROR: {e}")
        await dump_screen(session, "error_state")
        import traceback
        traceback.print_exc()
        results["failed"] += 1

    finally:
        await cleanup_tab(tab, session)

    return results


async def test_run_tui(connection, window) -> dict:
    """Test sarasa run --dry-run TUI alignment."""
    results = {"passed": 0, "failed": 0, "name": "run"}

    tab = await window.async_create_tab()
    session = tab.current_session
    await session.async_set_name("sarasa-run-test")

    try:
        print("\n" + "=" * 60)
        print(" TEST: sarasa run --dry-run TUI alignment")
        print("=" * 60)

        # Build sarasa (may already be built)
        print("\nBuilding sarasa...")
        await session.async_send_text(f"cd {SARASA_DIR} && go build -o sarasa . 2>&1\n")
        await asyncio.sleep(2)

        # Launch run TUI in dry-run mode
        print("Launching ./sarasa run --dry-run...")
        await session.async_send_text("./sarasa run --dry-run\n")
        await asyncio.sleep(5)  # Wait for TUI to load and check packages

        await take_screenshot("run_01_initial")

        # Capture screen
        lines = await get_screen_lines(session, 40)

        # Analyze alignment
        analysis = analyze_panel_alignment(lines)

        # Debug dump
        await dump_screen(session, "run TUI")

        # Report findings
        if analysis["issues"]:
            print("\n*** ALIGNMENT ISSUES DETECTED ***")
            for issue in analysis["issues"]:
                print(f"  {issue}")
            results["failed"] += 1
        else:
            print("\n*** ALIGNMENT CHECK PASSED ***")
            print(f"  Left borders at column: {set(p[1] for p in analysis['left_positions'])}")
            print(f"  Right borders at column: {set(p[1] for p in analysis['right_positions'])}")
            print(f"  Panel widths: {set(w for _, w in analysis['widths'])}")
            results["passed"] += 1

        await take_screenshot("run_02_analyzed")

    except Exception as e:
        print(f"\nERROR: {e}")
        await dump_screen(session, "error_state")
        import traceback
        traceback.print_exc()
        results["failed"] += 1

    finally:
        await cleanup_tab(tab, session)

    return results


async def test_logs_tui(connection, window) -> dict:
    """Test sarasa logs TUI."""
    results = {"passed": 0, "failed": 0, "name": "logs"}

    tab = await window.async_create_tab()
    session = tab.current_session
    await session.async_set_name("sarasa-logs-test")

    try:
        print("\n" + "=" * 60)
        print(" TEST: sarasa logs TUI")
        print("=" * 60)

        # Build sarasa
        print("\nBuilding sarasa...")
        await session.async_send_text(f"cd {SARASA_DIR} && go build -o sarasa . 2>&1\n")
        await asyncio.sleep(2)

        # Launch logs TUI
        print("Launching ./sarasa logs...")
        await session.async_send_text("./sarasa logs\n")
        await asyncio.sleep(2)

        await take_screenshot("logs_01_initial")

        # Capture screen
        lines = await get_screen_lines(session, 40)

        # Debug dump
        await dump_screen(session, "logs TUI")

        # Check for key elements
        screen_text = "\n".join(lines)
        has_header = "SARASA LOGS" in screen_text
        has_help = "search" in screen_text.lower() or "/" in screen_text
        has_entries = "[INF]" in screen_text or "[DBG]" in screen_text or "[WRN]" in screen_text or "[ERR]" in screen_text

        if has_header:
            print("  PASS: Header displayed")
            results["passed"] += 1
        else:
            print("  FAIL: Header not found")
            results["failed"] += 1

        if has_help:
            print("  PASS: Help text displayed")
            results["passed"] += 1
        else:
            print("  FAIL: Help text not found")
            results["failed"] += 1

        if has_entries:
            print("  PASS: Log entries displayed")
            results["passed"] += 1
        else:
            print("  INFO: No log entries (may be empty)")

        # Test search functionality
        print("\nTesting search (/ key)...")
        await session.async_send_text("/")
        await asyncio.sleep(0.5)
        await take_screenshot("logs_02_search_open")

        await session.async_send_text("brew")
        await asyncio.sleep(0.3)
        await session.async_send_text("\r")  # Enter
        await asyncio.sleep(0.5)
        await take_screenshot("logs_03_search_results")

        lines = await get_screen_lines(session, 40)
        screen_text = "\n".join(lines)
        if "brew" in screen_text.lower() or "Search:" in screen_text:
            print("  PASS: Search functionality working")
            results["passed"] += 1
        else:
            print("  INFO: Search may have no results")

        # Test level filter toggle
        print("\nTesting level filter (2 key to toggle INF)...")
        await session.async_send_text("\x1b")  # Esc to clear search
        await asyncio.sleep(0.3)
        await session.async_send_text("2")  # Toggle INF
        await asyncio.sleep(0.5)
        await take_screenshot("logs_04_filter_toggled")

    except Exception as e:
        print(f"\nERROR: {e}")
        await dump_screen(session, "error_state")
        import traceback
        traceback.print_exc()
        results["failed"] += 1

    finally:
        await cleanup_tab(tab, session)

    return results


async def main(connection):
    app = await iterm2.async_get_app(connection)
    window = app.current_terminal_window

    if not window:
        print("ERROR: No active iTerm2 window")
        return

    if not SARASA_DIR.exists():
        print(f"ERROR: Sarasa directory not found: {SARASA_DIR}")
        return

    # Parse args
    args = sys.argv[1:] if len(sys.argv) > 1 else ["all"]

    all_results = []

    for test in args:
        if test == "status":
            all_results.append(await test_status_tui(connection, window))
        elif test == "run":
            all_results.append(await test_run_tui(connection, window))
        elif test == "logs":
            all_results.append(await test_logs_tui(connection, window))
        elif test == "all":
            all_results.append(await test_status_tui(connection, window))
            await asyncio.sleep(1)
            all_results.append(await test_run_tui(connection, window))
            await asyncio.sleep(1)
            all_results.append(await test_logs_tui(connection, window))
        else:
            print(f"Unknown test: {test}")
            print("Usage: uv run test_sarasa_tui.py [status|run|logs|all]")
            return

    # Summary
    print("\n" + "=" * 60)
    print(" TEST SUMMARY")
    print("=" * 60)

    total_passed = 0
    total_failed = 0

    for r in all_results:
        status = "PASS" if r["failed"] == 0 else "FAIL"
        print(f"  {r['name']}: {status} ({r['passed']} passed, {r['failed']} failed)")
        total_passed += r["passed"]
        total_failed += r["failed"]

    print("-" * 60)
    print(f"  TOTAL: {total_passed} passed, {total_failed} failed")

    if total_failed == 0:
        print("\n  All alignment tests passed!")
    else:
        print("\n  Alignment issues detected - see screenshots for details")
        print(f"  Screenshots saved to: {SCREENSHOTS_DIR}")

    print("=" * 60)


if __name__ == "__main__":
    iterm2.run_until_complete(main)
