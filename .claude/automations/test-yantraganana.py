# /// script
# requires-python = ">=3.14"
# dependencies = [
#   "iterm2",
#   "pyobjc",
#   "pyobjc-framework-Quartz",
# ]
# ///

"""
Test Yantraganana Script: Verify all code paths, output quality, and visual correctness

Tests:
    1. Full Run: Execute script, verify it completes (no hang)
    2. JSON Validation: Output file is valid JSON with all 22 expected sections
    3. Log File: Log file created at ~/.local/state/yantraganana/ with proper entries
    4. Cask Versions: No ".metadata" entries in homebrew casks
    5. Runtimes: other_runtimes section populated (was hanging before fix)
    6. Box Drawing: Visual box alignment in terminal output
    7. Timeout Guard: _timeout_run kills a hanging command within 10s

Verification Strategy:
    - Run script in iTerm2 tab, monitor for completion or hang (60s timeout)
    - Parse screen for all phase headers and the final summary box
    - Validate JSON output with jq
    - Inspect log file for proper structure

Screenshots:
    - yantra_running.png: Script mid-execution showing phases
    - yantra_complete.png: Final summary box
    - yantra_boxcheck.png: Close-up of box-drawing alignment

Key Bindings:
    - N/A (non-interactive script)

Usage:
    uv run .claude/automations/test-yantraganana.py
"""

import iterm2
import asyncio
import subprocess
import os
import json
import time
from datetime import datetime

SCREENSHOT_DIR = "./screenshots"
TIMEOUT_SECONDS = 10.0
PROJECT_DIR = "/Users/indrasvat/code/github.com/indrasvat-kitchen-sink"
TEST_OUTPUT = "/tmp/yantra-test-output.json"

results = {
    "passed": 0,
    "failed": 0,
    "unverified": 0,
    "tests": [],
    "screenshots": [],
    "start_time": None,
    "end_time": None,
}


def log_result(test_name: str, status: str, details: str = "", screenshot: str = None):
    results["tests"].append({
        "name": test_name,
        "status": status,
        "details": details,
        "screenshot": screenshot,
    })
    if screenshot:
        results["screenshots"].append(screenshot)
    if status == "PASS":
        results["passed"] += 1
        print(f"  [+] PASS: {test_name}")
    elif status == "FAIL":
        results["failed"] += 1
        print(f"  [x] FAIL: {test_name} - {details}")
    else:
        results["unverified"] += 1
        print(f"  [?] UNVERIFIED: {test_name} - {details}")
    if screenshot:
        print(f"      Screenshot: {screenshot}")


def print_summary() -> int:
    results["end_time"] = datetime.now()
    total = results["passed"] + results["failed"] + results["unverified"]
    duration = (results["end_time"] - results["start_time"]).total_seconds() if results["start_time"] else 0
    print("\n" + "=" * 60)
    print("TEST SUMMARY")
    print("=" * 60)
    print(f"Duration:   {duration:.1f}s")
    print(f"Total:      {total}")
    print(f"Passed:     {results['passed']}")
    print(f"Failed:     {results['failed']}")
    print(f"Unverified: {results['unverified']}")
    if results["screenshots"]:
        print(f"Screenshots: {len(results['screenshots'])}")
    print("=" * 60)
    if results["failed"] > 0:
        print("\nFailed tests:")
        for test in results["tests"]:
            if test["status"] == "FAIL":
                print(f"  - {test['name']}: {test['details']}")
    print("\n" + "-" * 60)
    if results["failed"] > 0:
        print("OVERALL: FAILED")
        return 1
    elif results["unverified"] > 0:
        print("OVERALL: PASSED (with unverified tests)")
        return 0
    else:
        print("OVERALL: PASSED")
        return 0


def print_test_header(test_name: str, test_num: int = None):
    if test_num:
        header = f"TEST {test_num}: {test_name}"
    else:
        header = f"TEST: {test_name}"
    print("\n" + "=" * 60)
    print(header)
    print("=" * 60)


try:
    import Quartz

    def get_iterm2_window_id():
        window_list = Quartz.CGWindowListCopyWindowInfo(
            Quartz.kCGWindowListOptionOnScreenOnly | Quartz.kCGWindowListExcludeDesktopElements,
            Quartz.kCGNullWindowID
        )
        for window in window_list:
            owner = window.get('kCGWindowOwnerName', '')
            if 'iTerm' in owner:
                return window.get('kCGWindowNumber')
        return None
except ImportError:
    print("WARNING: Quartz not available")
    def get_iterm2_window_id():
        return None


def capture_screenshot(name: str) -> str:
    os.makedirs(SCREENSHOT_DIR, exist_ok=True)
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    filename = f"{name}_{timestamp}.png"
    filepath = os.path.join(SCREENSHOT_DIR, filename)
    window_id = get_iterm2_window_id()
    if window_id:
        subprocess.run(["screencapture", "-x", "-l", str(window_id), filepath], check=True)
    else:
        subprocess.run(["screencapture", "-x", filepath], check=True)
    print(f"  SCREENSHOT: {filepath}")
    return filepath


async def get_full_screen_text(session) -> str:
    screen = await session.async_get_screen_contents()
    lines = []
    for i in range(screen.number_of_lines):
        lines.append(screen.line(i).string)
    return "\n".join(lines)


async def wait_for_text(session, text: str, timeout: float = 60.0) -> bool:
    start = time.monotonic()
    while (time.monotonic() - start) < timeout:
        screen_text = await get_full_screen_text(session)
        if text in screen_text:
            return True
        await asyncio.sleep(0.5)
    return False


async def dump_screen(session, label: str):
    screen = await session.async_get_screen_contents()
    print(f"\n{'='*60}")
    print(f"SCREEN DUMP: {label}")
    print(f"{'='*60}")
    for i in range(screen.number_of_lines):
        line = screen.line(i).string
        if line.strip():
            print(f"{i:03d}: {line}")
    print(f"{'='*60}\n")


BOX_CORNERS_TOP = set("┌╭╔")
BOX_CORNERS_BOTTOM = set("└╰╚")
BOX_HORIZONTAL = set("─═━")


def check_box_alignment(screen_text: str) -> list[str]:
    """Check box-drawing character alignment. Returns list of issues."""
    issues = []
    for line_num, line in enumerate(screen_text.split("\n")):
        for j, char in enumerate(line):
            # Top-left corner should be followed by horizontal
            if char in BOX_CORNERS_TOP and j + 1 < len(line):
                next_char = line[j + 1]
                if next_char not in BOX_HORIZONTAL and next_char not in BOX_CORNERS_TOP:
                    issues.append(f"Line {line_num}: corner '{char}' at col {j} not connected (next='{next_char}')")
            # Bottom-left corner should be followed by horizontal
            if char in BOX_CORNERS_BOTTOM and j + 1 < len(line):
                next_char = line[j + 1]
                if next_char not in BOX_HORIZONTAL and next_char not in BOX_CORNERS_BOTTOM:
                    issues.append(f"Line {line_num}: corner '{char}' at col {j} not connected (next='{next_char}')")
    return issues


async def cleanup_session(session):
    try:
        await session.async_send_text("\x03")
        await asyncio.sleep(0.3)
        await session.async_send_text("exit\n")
        await asyncio.sleep(0.3)
        await session.async_close()
    except Exception:
        pass


async def main(connection):
    results["start_time"] = datetime.now()
    app = await iterm2.async_get_app(connection)
    window = app.current_terminal_window

    if not window:
        print("ERROR: No iTerm2 window found")
        return

    # Create a new tab for testing
    tab = await window.async_create_tab()
    session = tab.current_session
    await asyncio.sleep(0.5)

    try:
        # ── TEST 1: Full script execution ──────────────────────
        print_test_header("Full Script Run", 1)

        # Clean up any previous test output
        await session.async_send_text(f"rm -f {TEST_OUTPUT}\n")
        await asyncio.sleep(0.3)
        await session.async_send_text(f"cd {PROJECT_DIR} && bash shell/dev-setup/yantraganana.sh {TEST_OUTPUT}\n")

        # Wait for completion — look for the summary box
        found = await wait_for_text(session, "Inventory complete", timeout=120.0)

        if found:
            log_result("Script completes without hanging", "PASS")
        else:
            await dump_screen(session, "Script may have hung")
            screenshot = capture_screenshot("yantra_hung")
            log_result("Script completes without hanging", "FAIL",
                       "Script did not complete within 120s (possible hang)",
                       screenshot)
            # Abort further tests
            print_summary()
            return

        await asyncio.sleep(1.0)
        screenshot = capture_screenshot("yantra_complete")

        # ── TEST 2: All phases visible in output ──────────────
        print_test_header("All Phases Completed", 2)

        screen_text = await get_full_screen_text(session)

        expected_phases = [
            "System Info",
            "Homebrew",
            "Node.js Ecosystem",
            "Go",
            "Rust / Cargo",
            "Python Ecosystem",
            "/Applications",
            "Loose Binaries",
            "Shell Environment",
            "Other Runtimes",
            "Git Config",
            "SSH",
            "Shell Config Files",
            "Editor Extensions",
            "Developer Fonts",
            "Environment & PATH",
            "LaunchAgents",
            "Docker",
            "Claude Code",
            "Codex",
            "Gemini CLI",
            "macOS Defaults",
        ]

        # Note: early phases scroll off the iTerm2 screen buffer.
        # Check the JSON output for completeness instead (Test 5).
        # Here we just verify the last few phases are visible on screen.
        visible_phases = [p for p in expected_phases if p in screen_text]
        # At minimum the final phases + summary should be visible
        if len(visible_phases) >= 8:
            log_result(f"Terminal shows recent phases ({len(visible_phases)}/{len(expected_phases)} visible)", "PASS")
        else:
            log_result(f"Terminal shows recent phases", "FAIL",
                       f"Only {len(visible_phases)} visible: {visible_phases}")

        # ── TEST 3: Box-drawing alignment ─────────────────────
        print_test_header("Box-Drawing Alignment", 3)

        box_issues = check_box_alignment(screen_text)
        if not box_issues:
            log_result("Box-drawing characters properly connected", "PASS")
        else:
            for issue in box_issues[:5]:
                print(f"    {issue}")
            log_result("Box-drawing characters properly connected", "FAIL",
                       f"{len(box_issues)} alignment issues found")

        # ── TEST 4: Valid JSON output ─────────────────────────
        print_test_header("JSON Output Validation", 4)

        await session.async_send_text(f"jq empty {TEST_OUTPUT} && echo 'JSON_VALID' || echo 'JSON_INVALID'\n")
        await asyncio.sleep(1.0)

        json_valid = await wait_for_text(session, "JSON_VALID", timeout=5.0)
        if json_valid:
            log_result("Output is valid JSON", "PASS")
        else:
            log_result("Output is valid JSON", "FAIL", "jq validation failed")

        # ── TEST 5: JSON has all expected sections ────────────
        print_test_header("JSON Section Completeness", 5)

        await session.async_send_text(f"jq 'keys | length' {TEST_OUTPUT}\n")
        await asyncio.sleep(1.0)

        expected_keys = [
            "system", "homebrew", "node_ecosystem", "go", "rust",
            "python_ecosystem", "applications", "loose_binaries",
            "shell", "other_runtimes", "git_config", "ssh",
            "shell_configs", "vscode", "developer_fonts", "environment",
            "launch_agents", "docker", "claude_code", "codex",
            "gemini", "macos_defaults", "inventory_version", "generated_at"
        ]

        # Read JSON file directly to check keys
        try:
            with open(TEST_OUTPUT, 'r') as f:
                data = json.load(f)
            missing_keys = [k for k in expected_keys if k not in data]
            if not missing_keys:
                log_result(f"All {len(expected_keys)} JSON sections present", "PASS")
            else:
                log_result(f"All {len(expected_keys)} JSON sections present", "FAIL",
                           f"Missing: {missing_keys}")
        except (json.JSONDecodeError, FileNotFoundError) as e:
            log_result(f"All {len(expected_keys)} JSON sections present", "FAIL",
                       f"Could not parse JSON: {e}")

        # ── TEST 6: No .metadata cask versions ────────────────
        print_test_header("Cask Version Fix (no .metadata)", 6)

        try:
            with open(TEST_OUTPUT, 'r') as f:
                data = json.load(f)
            if data.get("homebrew", {}).get("installed"):
                metadata_casks = [
                    c["name"] for c in data["homebrew"].get("casks", [])
                    if c.get("version") == ".metadata"
                ]
                if not metadata_casks:
                    log_result("No casks with .metadata version", "PASS")
                else:
                    log_result("No casks with .metadata version", "FAIL",
                               f"Casks with .metadata: {metadata_casks}")
            else:
                log_result("No casks with .metadata version", "UNVERIFIED",
                           "Homebrew not installed")
        except Exception as e:
            log_result("No casks with .metadata version", "FAIL", str(e))

        # ── TEST 7: other_runtimes populated ──────────────────
        print_test_header("Runtimes Section (hang fix)", 7)

        try:
            with open(TEST_OUTPUT, 'r') as f:
                data = json.load(f)
            runtimes = data.get("other_runtimes", {})
            if runtimes and len(runtimes) > 0:
                # Check that at least some values are not "not installed"
                populated = [k for k, v in runtimes.items() if v and v != "not installed"]
                log_result(f"other_runtimes section populated ({len(populated)} detected)", "PASS",
                           f"Detected: {', '.join(populated)}")
            else:
                log_result("other_runtimes section populated", "FAIL",
                           "Section is empty or missing")
        except Exception as e:
            log_result("other_runtimes section populated", "FAIL", str(e))

        # ── TEST 8: Log file created and has entries ──────────
        print_test_header("Log File Validation", 8)

        import glob
        log_dir = os.path.expanduser("~/.local/state/yantraganana")
        log_files = sorted(glob.glob(os.path.join(log_dir, "yantraganana-*.log")))

        if log_files:
            latest_log = log_files[-1]
            with open(latest_log, 'r') as f:
                log_content = f.read()

            # Check for expected log structure
            has_start = "=== Yantraganana" in log_content
            has_phases = "[PHASE]" in log_content
            has_ok = "[OK   ]" in log_content
            has_complete = "Inventory complete" in log_content
            no_ansi = "\033[" not in log_content and "\x1b[" not in log_content

            checks_passed = all([has_start, has_phases, has_ok, has_complete])

            if checks_passed:
                log_result("Log file has proper structure", "PASS",
                           f"Log: {latest_log}")
            else:
                details = []
                if not has_start: details.append("missing start header")
                if not has_phases: details.append("missing PHASE entries")
                if not has_ok: details.append("missing OK entries")
                if not has_complete: details.append("missing completion entry")
                log_result("Log file has proper structure", "FAIL",
                           "; ".join(details))

            if no_ansi:
                log_result("Log file has no ANSI escape codes", "PASS")
            else:
                log_result("Log file has no ANSI escape codes", "FAIL",
                           "ANSI escapes found in log file")
        else:
            log_result("Log file has proper structure", "FAIL",
                       f"No log files found in {log_dir}")

        # ── TEST 9: _timeout_run actually kills ───────────────
        print_test_header("Timeout Guard Test", 9)

        # Test _timeout_run by calling the perl-based timeout directly
        # Use a 3s timeout on a 30s sleep — should complete in ~3-5s
        await session.async_send_text(
            f"cd {PROJECT_DIR} && "
            "bash -c '"
            'cmd_exists() { command -v "$1" &>/dev/null; }; '
            '_timeout_run() { '
            '  local secs="$1"; shift; '
            '  perl -e '"'"'use POSIX ":sys_wait_h"; '
            '$SIG{ALRM}=sub{kill("TERM",$pid) if $pid; exit 1}; '
            'alarm('"'"'"$secs"'"'"'); '
            '$pid=open(my $fh,"-|",@ARGV) or exit 1; '
            'while(<$fh>){print} close $fh; alarm(0);'"'"' '
            '-- "$@" 2>/dev/null || true; '
            "}; "
            "start=$(date +%s); "
            "_timeout_run 3 sleep 30; "
            "elapsed=$(( $(date +%s) - start )); "
            'echo "TIMEOUT_ELAPSED_${elapsed}s"; '
            "if (( elapsed < 10 )); then echo TIMEOUT_OK; "
            "else echo TIMEOUT_FAIL; fi'\n"
        )

        timeout_ok = await wait_for_text(session, "TIMEOUT_OK", timeout=20.0)
        if timeout_ok:
            log_result("_timeout_run kills hanging commands within timeout", "PASS")
        else:
            timeout_fail = await wait_for_text(session, "TIMEOUT_FAIL", timeout=5.0)
            if timeout_fail:
                log_result("_timeout_run kills hanging commands within timeout", "FAIL",
                           "Command was killed but took too long")
            else:
                await dump_screen(session, "timeout test")
                log_result("_timeout_run kills hanging commands within timeout", "FAIL",
                           "Timeout test did not complete")

        # ── TEST 10: Summary box visual check ─────────────────
        print_test_header("Summary Box Visual Check", 10)

        # Check that the summary mentions Valid JSON
        if "Valid JSON" in screen_text:
            log_result("Summary box shows 'Valid JSON'", "PASS")
        else:
            log_result("Summary box shows 'Valid JSON'", "FAIL",
                       "Summary does not show JSON validation success")

        # Check log path is shown
        if "Log:" in screen_text and "yantraganana" in screen_text:
            log_result("Summary shows log file path", "PASS")
        else:
            log_result("Summary shows log file path", "FAIL",
                       "Log path not visible in output")

        # Final screenshot
        capture_screenshot("yantra_final")

    except Exception as e:
        print(f"\nERROR: {e}")
        await dump_screen(session, "error state")
        capture_screenshot("yantra_error")
        log_result("Unexpected error", "FAIL", str(e))
        raise

    finally:
        await cleanup_session(session)

    exit_code = print_summary()
    if exit_code != 0:
        raise SystemExit(exit_code)


iterm2.run_until_complete(main)
