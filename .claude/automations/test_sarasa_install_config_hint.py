# /// script
# requires-python = ">=3.14"
# dependencies = [
#   "iterm2",
#   "pyobjc",
#   "pyobjc-framework-Quartz",
# ]
# ///
"""
Visual test: install.sh config-upgrade detection and sarasa config suggest.

Tests the new installer behavior when upgrading sarasa with a stale config
that's missing newly available managers (e.g., skills).

Tests:
    1. config suggest --json with stale config: should report missing managers
    2. config suggest --json with current config: should report no missing
    3. config suggest styled (TTY) with stale config: shows hint text
    4. install.sh post-install hint box: simulated upgrade with stale config
    5. install.sh post-install no hint: simulated upgrade with current config

Verification Strategy:
    - Build sarasa from local source
    - Create temp config files to simulate stale/current configs
    - Run commands in iTerm2 to capture styled output
    - Verify screen text and capture screenshots

Screenshots:
    - config_hint_01_suggest_json_stale.png
    - config_hint_02_suggest_styled.png
    - config_hint_03_install_stale_config.png
    - config_hint_04_install_current_config.png

Screenshot Inspection Checklist:
    - Hint box: correct box drawing, colors, alignment
    - Manager names: displayed with correct icons/colors
    - "sarasa init --force" prompt visible
    - No hint shown when config is already current

Key Bindings:
    - n: decline reconfigure prompt
    - Ctrl+C: interrupt

Usage:
    uv run .claude/automations/test_sarasa_install_config_hint.py
"""

import asyncio
import os
import subprocess
import sys
import tempfile
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
TIMEOUT_SECONDS = 8.0

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
    duration = (
        (datetime.now() - results["start_time"]).total_seconds()
        if results["start_time"]
        else 0
    )
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
        Quartz.kCGWindowListOptionOnScreenOnly
        | Quartz.kCGWindowListExcludeDesktopElements,
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
    filepath = SCREENSHOT_DIR / f"config_hint_{name}_{timestamp}.png"

    frame = await window.async_get_frame()
    qid = find_quartz_window_id(frame.origin.x, frame.size.width, frame.size.height)

    if qid:
        subprocess.run(
            ["screencapture", "-x", "-l", str(qid), str(filepath)], check=True
        )
    else:
        subprocess.run(["screencapture", "-x", str(filepath)], check=True)

    print(f"  SCREENSHOT: {filepath.name}")
    return str(filepath)


# ============================================================
# WINDOW CREATION
# ============================================================


async def create_test_window(
    connection, name="test", x_pos=50, width=1200, height=900
):
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

    # Position window prominently for clear screenshots
    await window.async_set_frame(
        iterm2.Frame(
            iterm2.Point(x_pos, 50),
            iterm2.Size(width, height),
        )
    )
    await asyncio.sleep(0.5)

    # Set a larger font for screenshot readability
    profile = await session.async_get_profile()
    await profile.async_set_normal_font("MesloLGS-NF-Regular 16")
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


async def screen_contains(session, target):
    lines = await get_all_screen_text(session)
    return any(target in line for line in lines)


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
# TEST CONFIGS
# ============================================================

STALE_CONFIG = """\
managers = ["brew", "volta", "pipx", "bun"]

[skip]
brew = []

[schedule]
times = ["08:00", "14:00", "22:00"]

[logging]
retention_days = 30
level = "info"
"""

CURRENT_CONFIG = """\
managers = ["brew", "volta", "pipx", "bun", "skills"]

[skip]
brew = []

[schedule]
times = ["08:00", "14:00", "22:00"]

[logging]
retention_days = 30
level = "info"
"""

# Install.sh fragment that sources only the display/check functions
# and calls check_config_updates with a custom config path.
INSTALL_SH_HARNESS = """\
#!/bin/bash
set -uo pipefail

export HOME="{fake_home}"

# Source install.sh to get function definitions.
# The main guard prevents main() from running.
source "{install_sh}"

# Override variables that install.sh set during source
INSTALL_PREFIX="{install_prefix}"
RUN_INIT="false"

# Call just the config check function
check_config_updates || echo "(no config updates)"
"""


# ============================================================
# MAIN
# ============================================================


async def main(connection):
    results["start_time"] = datetime.now()

    print("\n" + "#" * 60)
    print("# TEST: install.sh config-upgrade detection")
    print("#" * 60)

    # Build sarasa
    print("\nBuilding sarasa from local source...")
    sarasa_bin = str(SARASA_DIR / "sarasa-test-binary")
    build = subprocess.run(
        ["go", "build", "-o", sarasa_bin, "."],
        cwd=str(SARASA_DIR),
        capture_output=True,
        text=True,
    )
    if build.returncode != 0:
        print(f"BUILD FAILED:\n{build.stderr}")
        log_result("Build", "FAIL", build.stderr)
        return print_summary()
    print("  Build OK")

    window, session = await create_test_window(
        connection, "config-hint-test", x_pos=150
    )
    created_sessions = [session]

    try:
        # ============================================================
        # TEST 1: config suggest --json with stale config
        # ============================================================
        print(f"\n{'=' * 60}")
        print("TEST 1: config suggest --json (stale config)")
        print(f"{'=' * 60}")

        with tempfile.NamedTemporaryFile(
            mode="w", suffix=".toml", delete=False
        ) as f:
            f.write(STALE_CONFIG)
            stale_path = f.name

        out = subprocess.run(
            [sarasa_bin, "--config", stale_path, "config", "suggest", "--json"],
            capture_output=True,
            text=True,
        )
        os.unlink(stale_path)

        if '"skills"' in out.stdout and '"missing"' in out.stdout:
            log_result(
                "config suggest --json (stale)",
                "PASS",
                f"Output: {out.stdout.strip()[:120]}",
            )
        else:
            log_result(
                "config suggest --json (stale)",
                "FAIL",
                f"Expected 'skills' in missing. Got: {out.stdout.strip()[:200]}",
            )

        # ============================================================
        # TEST 2: config suggest --json with current config
        # ============================================================
        print(f"\n{'=' * 60}")
        print("TEST 2: config suggest --json (current config)")
        print(f"{'=' * 60}")

        with tempfile.NamedTemporaryFile(
            mode="w", suffix=".toml", delete=False
        ) as f:
            f.write(CURRENT_CONFIG)
            current_path = f.name

        out = subprocess.run(
            [sarasa_bin, "--config", current_path, "config", "suggest", "--json"],
            capture_output=True,
            text=True,
        )
        os.unlink(current_path)

        if '"missing": null' in out.stdout or '"missing": []' in out.stdout:
            log_result(
                "config suggest --json (current)",
                "PASS",
                "No missing managers reported",
            )
        else:
            log_result(
                "config suggest --json (current)",
                "FAIL",
                f"Expected no missing. Got: {out.stdout.strip()[:200]}",
            )

        # ============================================================
        # TEST 3: config suggest styled output (stale config, in TTY)
        # ============================================================
        print(f"\n{'=' * 60}")
        print("TEST 3: config suggest styled (stale config, TTY)")
        print(f"{'=' * 60}")

        with tempfile.NamedTemporaryFile(
            mode="w", suffix=".toml", delete=False
        ) as f:
            f.write(STALE_CONFIG)
            stale_path = f.name

        await session.async_send_text(
            f"clear && {sarasa_bin} --config {stale_path} config suggest\n"
        )
        await asyncio.sleep(2)

        found_new = await screen_contains(session, "New managers available")
        found_skills = await screen_contains(session, "skills")
        found_init = await screen_contains(session, "sarasa init --force")
        screenshot = await capture_screenshot(window, "02_suggest_styled")

        # Clean up temp file
        await session.async_send_text(f"rm -f {stale_path}\n")
        await asyncio.sleep(0.3)

        if found_new and found_skills and found_init:
            log_result(
                "config suggest styled (TTY)",
                "PASS",
                "Hint text, skills name, and init command all visible",
                screenshot=screenshot,
            )
        else:
            await dump_screen(session, "suggest styled output")
            details = (
                f"new_managers={found_new}, skills={found_skills}, init={found_init}"
            )
            log_result(
                "config suggest styled (TTY)",
                "FAIL",
                details,
                screenshot=screenshot,
            )

        # ============================================================
        # TEST 4: install.sh post-install hint (stale config)
        # ============================================================
        print(f"\n{'=' * 60}")
        print("TEST 4: install.sh hint box (stale config)")
        print(f"{'=' * 60}")

        # Create a fake HOME with stale config
        fake_home = tempfile.mkdtemp(prefix="sarasa-test-home-")
        fake_config_dir = os.path.join(fake_home, ".config", "sarasa")
        os.makedirs(fake_config_dir)
        with open(os.path.join(fake_config_dir, "config.toml"), "w") as f:
            f.write(STALE_CONFIG)

        # Create the skills lock file so IsAvailable() returns true
        fake_agents_dir = os.path.join(fake_home, ".agents")
        os.makedirs(fake_agents_dir)
        with open(os.path.join(fake_agents_dir, ".skill-lock.json"), "w") as f:
            f.write("{}")

        # Also create a fake install prefix with the binary
        fake_prefix = os.path.join(fake_home, ".local", "bin")
        os.makedirs(fake_prefix)
        subprocess.run(["cp", sarasa_bin, os.path.join(fake_prefix, "sarasa")])

        # Write the harness script
        harness_path = os.path.join(fake_home, "test_install.sh")
        harness_content = INSTALL_SH_HARNESS.format(
            install_prefix=fake_prefix,
            fake_home=fake_home,
            install_sh=str(SARASA_DIR / "install.sh"),
        )
        with open(harness_path, "w") as f:
            f.write(harness_content)
        os.chmod(harness_path, 0o755)

        await session.async_send_text(f"clear && bash {harness_path}\n")
        await asyncio.sleep(3)

        found_hint = await screen_contains(session, "New managers available")
        found_skills = await screen_contains(session, "skills")
        found_box_top = await screen_contains(session, "╭")
        found_box_bot = await screen_contains(session, "╰")
        screenshot = await capture_screenshot(window, "03_install_stale_config")

        # Cleanup
        await session.async_send_text(f"rm -rf {fake_home}\n")
        await asyncio.sleep(0.3)

        if found_hint and found_skills and found_box_top and found_box_bot:
            log_result(
                "install.sh hint box (stale config)",
                "PASS",
                "Hint box with skills suggestion displayed",
                screenshot=screenshot,
            )
        else:
            await dump_screen(session, "install hint output")
            details = f"hint={found_hint}, skills={found_skills}, box_top={found_box_top}, box_bot={found_box_bot}"
            log_result(
                "install.sh hint box (stale config)",
                "FAIL",
                details,
                screenshot=screenshot,
            )

        # ============================================================
        # TEST 5: install.sh no hint (current config)
        # ============================================================
        print(f"\n{'=' * 60}")
        print("TEST 5: install.sh no hint (current config)")
        print(f"{'=' * 60}")

        # Create a fake HOME with current config
        fake_home2 = tempfile.mkdtemp(prefix="sarasa-test-home2-")
        fake_config_dir2 = os.path.join(fake_home2, ".config", "sarasa")
        os.makedirs(fake_config_dir2)
        with open(os.path.join(fake_config_dir2, "config.toml"), "w") as f:
            f.write(CURRENT_CONFIG)

        fake_prefix2 = os.path.join(fake_home2, ".local", "bin")
        os.makedirs(fake_prefix2)
        subprocess.run(["cp", sarasa_bin, os.path.join(fake_prefix2, "sarasa")])

        harness_path2 = os.path.join(fake_home2, "test_install.sh")
        harness_content2 = INSTALL_SH_HARNESS.format(
            install_prefix=fake_prefix2,
            fake_home=fake_home2,
            install_sh=str(SARASA_DIR / "install.sh"),
        )
        with open(harness_path2, "w") as f:
            f.write(harness_content2)
        os.chmod(harness_path2, 0o755)

        await session.async_send_text(f"clear && bash {harness_path2}\n")
        await asyncio.sleep(3)

        # Should NOT show the hint
        no_hint = not await screen_contains(session, "New managers available")
        has_no_updates = await screen_contains(session, "(no config updates)")
        screenshot = await capture_screenshot(window, "04_install_current_config")

        await session.async_send_text(f"rm -rf {fake_home2}\n")
        await asyncio.sleep(0.3)

        if no_hint and has_no_updates:
            log_result(
                "install.sh no hint (current config)",
                "PASS",
                "No hint shown — config is current",
                screenshot=screenshot,
            )
        else:
            await dump_screen(session, "install no-hint output")
            log_result(
                "install.sh no hint (current config)",
                "FAIL",
                f"no_hint={no_hint}, no_updates={has_no_updates}",
                screenshot=screenshot,
            )

    except Exception as e:
        print(f"\nERROR: {e}")
        import traceback

        traceback.print_exc()
        log_result("Test Execution", "FAIL", str(e))
        try:
            await dump_screen(session, "error_state")
        except Exception:
            pass

    finally:
        # Clean up built binary
        try:
            os.unlink(sarasa_bin)
        except Exception:
            pass

        for s in created_sessions:
            await cleanup_session(s)

    return print_summary()


if __name__ == "__main__":
    exit_code = iterm2.run_until_complete(main)
    sys.exit(exit_code or 0)
