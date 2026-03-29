# /// script
# requires-python = ">=3.13"
# dependencies = [
#   "iterm2",
#   "pyobjc",
# ]
# ///
"""
Quick test for sarasa --help styled output.
Run with: uv run .claude/automations/test_sarasa_help.py
"""
import iterm2
import asyncio
import subprocess
from datetime import datetime
from pathlib import Path
import Quartz

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
    """Take screenshot of iTerm2 window only."""
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


async def main(connection):
    app = await iterm2.async_get_app(connection)
    window = app.current_terminal_window

    if not window:
        print("ERROR: No active iTerm2 window")
        return

    tab = await window.async_create_tab()
    session = tab.current_session
    await session.async_set_name("sarasa-help-test")

    try:
        print("\n" + "=" * 60)
        print(" TEST: sarasa --help styled output")
        print("=" * 60)

        # Build sarasa
        print("\nBuilding sarasa...")
        await session.async_send_text(f"cd {SARASA_DIR} && go build -o sarasa . 2>&1\n")
        await asyncio.sleep(2)

        # Clear screen and run help
        print("Running ./sarasa --help...")
        await session.async_send_text("clear && ./sarasa --help\n")
        await asyncio.sleep(1)

        await take_screenshot("help_styled")

        # Dump screen for verification
        print("\n--- SCREEN OUTPUT ---")
        screen = await session.async_get_screen_contents()
        for i in range(min(35, screen.number_of_lines)):
            line = screen.line(i).string
            if line.strip():
                print(f"  {i:02d}: {line}")
        print("---\n")

        print("SUCCESS: Help output captured")

    except Exception as e:
        print(f"\nERROR: {e}")
        import traceback
        traceback.print_exc()

    finally:
        # Cleanup
        print("\nCleaning up...")
        try:
            await session.async_send_text("exit\n")
            await asyncio.sleep(0.3)
        except Exception:
            pass
        for s in tab.sessions:
            try:
                await s.async_close()
            except Exception:
                pass
        print("Done.")


if __name__ == "__main__":
    iterm2.run_until_complete(main)
