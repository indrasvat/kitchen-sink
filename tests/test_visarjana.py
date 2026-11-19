#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.14"
# dependencies = []
# ///
"""Run the real script against private CLI fixtures and disposable processes."""

import json
import os
import shutil
import socket
import subprocess
import sys
import tempfile
import threading
import time
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / "shell/utilities/visarjana.sh"
BASH = shutil.which("bash")
DAY = 86400

MOCK = r"""
import json
import os
from pathlib import Path
import sys

state_file = Path(os.environ["VISARJANA_TEST_STATE"])
state = json.loads(state_file.read_text())
tool = Path(sys.argv[0]).name
args = sys.argv[1:]

def save():
    state_file.write_text(json.dumps(state))

def fail(message):
    print(message, file=sys.stderr)
    save()
    sys.exit(1)

def process(pid):
    return next((p for p in state["processes"] if str(p["pid"]) == pid), None)

DEFAULTS = {"ppid": 1, "stat": "Ss", "etime": "10-00:00:00", "tty": "??"}

def field(p, name):
    if name == "tpgid":
        return p.get("tpgid", p["pid"])
    return p.get(name, DEFAULTS.get(name))

if tool == "ps":
    if args[0] == "-axo":
        names = [f.rstrip("=") for f in args[1].split(",")]
        for p in state["processes"]:
            print(*(field(p, name) for name in names))
    else:
        p = process(args[args.index("-p") + 1])
        field = args[args.index("-o") + 1]
        if field == "ppid=":
            print(p.get("ppid", 1) if p else state.get("host_pid", 1))
        elif not p:
            if state.get("host_pid"):
                print("bash")
            else:
                sys.exit(1)
        elif field == "command=":
            print(p["args"], *(f"{k}={v}" for k, v in p.get("env", {}).items()))
        else:
            print(p["args"])
elif tool == "lsof":
    p = process(args[args.index("-p") + 1])
    if p:
        p["lsofs"] = p.get("lsofs", 0) + 1
        if p["lsofs"] in p.get("lsof_fail", []):
            fail("lsof: fixture failure")
    if p and not p.get("socket_lost"):
        for _ in range(1 + p.get("connections", 0)):  # the listener, then each accepted client
            print("n" + p["socket"])
    save()
elif tool == "stat":
    mtime = state.get("mtimes", {}).get(args[-1])
    if mtime is None:
        sys.exit(1)
    print(mtime)
elif tool == "shux":
    sock = args[args.index("--socket") + 1]
    p = next(p for p in state["processes"] if p.get("socket") == sock)
    if "version" in args:  # the one call that never replaces a daemon
        print(json.dumps({"mismatch": p.get("mismatch", False), "daemon": {"status": "running"}}))
        sys.exit(0)
    if p.get("mismatch"):  # what shux really does to a daemon of another build
        state["actions"].append(["shux-restarted-daemon", p["pid"]])
        save()
        sys.exit(0)
    if "list" in args:
        p["lists"] = p.get("lists", 0) + 1
        if p["lists"] in p.get("fail_lists", []):
            fail("cannot list fixture sessions")
        if p.get("list_warning"):
            print(p["list_warning"], file=sys.stderr)
        responses = p.get("list_responses", {})
        print(responses.get(str(p["lists"]), json.dumps({"sessions": p["sessions"]})))
        if p["lists"] in p.get("fail_after_output", []):
            fail("fixture list failed after valid JSON")
        if p.get("lose_socket_after_list"):
            p["socket_lost"] = True
        if p.get("reuse_after_list"):
            p["args"] = "unrelated-process"
        # Someone attaches, types or runs something between the ledger and the act-time look.
        for pid, changes in p.get("after_list", {}).get(str(p["lists"]), []):
            next(q for q in state["processes"] if q["pid"] == pid).update(changes)
    else:
        sid = args[-1]
        state["actions"].append(["shux-kill", sid])
        if p.get("kill_failure"):
            fail("fixture kill failed")
        p["sessions"] = [s for s in p["sessions"] if s["id"] != sid]
        if not p["sessions"]:  # its panes end with its last session
            state["processes"] = [q for q in state["processes"] if q.get("ppid") != p["pid"]]
        if p.get("new_session"):
            p["sessions"].append(p.pop("new_session"))
    save()
elif tool in ("orca", "orca-ide"):
    if "list" in args:
        state["orca_lists"] = state.get("orca_lists", 0) + 1
        if state.get("orca_list_failure") or state["orca_lists"] in state.get("orca_fail_lists", []):
            fail("fixture Orca unavailable")
        print(json.dumps({"result": {"terminals": state["terminals"]}}))
        if state.get("orca_new_agent"):
            for t in state["terminals"]:
                t["agentIdentity"] = "codex"
        save()
    else:
        handle = args[args.index("--terminal") + 1]
        state["actions"].append(["orca-close", handle])
        state["terminals"] = [t for t in state["terminals"] if t["handle"] != handle]
        print(json.dumps({"ok": True}))
        save()
elif tool == "agent-browser":
    if "list" in args:
        if state.get("browser_list_failure"):
            fail("fixture browser unavailable")
        print(json.dumps(state.get("browser_response", {"data": {"sessions": state["browsers"]}})))
    else:  # visarjana never closes one; recorded so a test catches it if it ever does
        state["actions"].append(["browser-close", args[args.index("--session") + 1]])
        save()
elif tool == "sleep":
    pass
"""


class VisarjanaTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory(prefix="visarjana-test-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.state_file = self.root / "state.json"
        self.state: dict = {
            "processes": [],
            "sessions": [],
            "browsers": [],
            "terminals": [],
            "actions": [],
        }
        for tool in (
            "ps",
            "lsof",
            "stat",
            "shux",
            "orca",
            "orca-ide",
            "agent-browser",
            "sleep",
        ):
            path = self.bin / tool
            path.write_text(f"#!{sys.executable}\n{MOCK}")
            path.chmod(0o755)
        self.env = {
            k: v
            for k, v in os.environ.items()
            if not k.startswith(("VISARJANA_", "ORCA_", "SHUX_"))
        }
        self.env.update(
            HOME=str(self.root),
            TMPDIR=str(self.root),
            PATH=f"{self.bin}:{os.environ['PATH']}",
            VISARJANA_TEST_STATE=str(self.state_file),
            ORCA_CLI_COMMAND=str(self.bin / "orca"),
            NO_COLOR="1",
        )

    def child(self, *, ignore_term: bool = False, **env: str) -> subprocess.Popen:
        code = "import time; print('ready', flush=True); time.sleep(60)"
        if ignore_term:
            code = (
                "import signal; signal.signal(signal.SIGTERM, signal.SIG_IGN); " + code
            )
        proc = subprocess.Popen(
            [sys.executable, "-c", code],
            env=self.env | env,
            stdout=subprocess.PIPE,
            text=True,
        )
        self.assertEqual(proc.stdout.readline(), "ready\n")
        proc.stdout.close()
        threading.Thread(target=proc.wait, daemon=True).start()
        self.addCleanup(self.reap, proc)
        return proc

    @staticmethod
    def reap(proc: subprocess.Popen) -> None:
        if proc.poll() is None:
            proc.kill()
        proc.wait(timeout=5)

    def daemon(self, names: tuple[str, ...] = ("fixture",), **options: object) -> dict:
        proc = self.child()
        sock_path = self.root / f"{proc.pid}.sock"
        sock = socket.socket(socket.AF_UNIX)
        sock.bind(str(sock_path))
        self.addCleanup(sock.close)
        row = {
            "pid": proc.pid,
            "args": f"shux __daemon --socket {sock_path}",
            "socket": str(sock_path),
            "sessions": [
                {
                    "id": f"{proc.pid:08x}-{i:04d}-0000-0000-000000000001",
                    "name": name,
                    "scratch": False,
                    "created_at": int(time.time()) - 2 * DAY,
                }
                for i, name in enumerate(names)
            ],
            **options,
        }
        self.state["processes"].append(row)
        row["proc"] = proc
        return row

    def pane(
        self,
        row: dict,
        args: str = "bash -l",
        *,
        quiet: int = 2 * DAY,
        foreground: bool = True,
        child: bool = False,
    ) -> dict:
        """A process the daemon runs for one pane; its tty last wrote `quiet` seconds ago.

        Never signalled, so its pid only has to be unique in the fixture table."""
        n = len(self.state["processes"])
        pid, tty = 4_000_000 + n, f"ttys9{n:02d}"
        pane = {"pid": pid, "ppid": row["pid"], "tty": tty, "args": args}
        if not foreground:  # a command the shell started holds the terminal
            pane["tpgid"] = pid + 1
        self.state["processes"].append(pane)
        if child:
            self.state["processes"].append(
                {"pid": pid + 1, "ppid": pid, "args": "sleep 600"}
            )
        self.state.setdefault("mtimes", {})[f"/dev/{tty}"] = int(time.time()) - quiet
        return pane

    def client(self, row: dict, args: str = "shux pane wait-for -s fixture") -> None:
        """A shux CLI process talking to the daemon, between connections."""
        proc = self.child(SHUX_SOCKET=row["socket"])
        self.state["processes"].append(
            {"pid": proc.pid, "args": args, "env": {"SHUX_SOCKET": row["socket"]}}
        )

    def events(self, result: subprocess.CompletedProcess) -> list[dict]:
        return [json.loads(line) for line in result.stdout.splitlines()]

    def category(self, row: dict, *args: str, **env: str) -> str:
        """How a dry run classifies the daemon."""
        result = self.run_script("-n", "--json", *args, **env)
        (daemon,) = [
            e
            for e in self.events(result)
            if e["event"] == "daemon" and e["pid"] == row["pid"]
        ]
        return daemon["category"]

    def write_state(self) -> None:
        self.state_file.write_text(json.dumps(self.state, default=lambda _: None))

    def run_script(
        self, *args: str, expected: int = 0, **env: str
    ) -> subprocess.CompletedProcess:
        self.write_state()
        result = subprocess.run(
            [BASH, str(SCRIPT), *args],
            check=False,
            env=self.env | env,
            input="",
            text=True,
            capture_output=True,
            timeout=15,
        )
        self.assertEqual(result.returncode, expected, result.stdout + result.stderr)
        self.state = json.loads(self.state_file.read_text())
        self.assertFalse((self.root / "visarjana.lock").exists())
        return result

    def test_help_and_version(self) -> None:
        self.assertIn("--keep", self.run_script("--help").stdout)
        self.assertIn("visarjana 2.0.0", self.run_script("--version").stdout)

    def test_invalid_options(self) -> None:
        for args in (
            ("--unknown",),
            ("--grace", "-1"),
            ("--grace=601",),
            ("--only=bad",),
            ("--keep=",),
            ("--socket=",),
            ("--only=",),
            ("--only", "browser", "--socket", "/unknown"),
            ("--json",),
            ("--", "extra"),
            ("--grace",),
            ("--grace", "9223372036854775808"),
            ("--grace", "18446744073709551616"),
            ("--in-use",),  # never without naming the daemons
            ("--in-use", "-y"),
            ("--idle-after", "9m"),  # a shell someone is reading
            ("--idle-after", "6"),
            ("--idle-after=1w",),
            ("--idle-after=0h",),
            ("--idle-after=08h",),
        ):
            with self.subTest(args=args):
                self.run_script(*args, expected=2)

    def test_empty_machine(self) -> None:
        self.assertIn("nothing to dismiss", self.run_script("-y").stdout)

    def test_host_daemon_is_spared(self) -> None:
        row = self.daemon()
        proc = row["proc"]
        self.state["host_pid"] = row["pid"]
        self.run_script("-y")
        self.assertEqual(self.state["actions"], [])
        self.assertIsNone(proc.poll())

    def test_orphan_daemon_is_the_only_thing_swept(self) -> None:
        orphan = self.daemon(())
        idle = self.daemon()
        self.pane(idle)
        self.run_script("-y", "--grace", "1")
        self.assertEqual(orphan["proc"].wait(timeout=5), -15)
        self.assertIsNone(idle["proc"].poll())
        self.assertEqual(self.state["actions"], [])

    def test_idle_daemon_needs_idle(self) -> None:
        row = self.daemon()
        self.pane(row)
        self.assertEqual(self.category(row), "idle")
        self.run_script("-y", "--idle", "--grace", "1")
        self.assertEqual(row["proc"].wait(timeout=5), -15)
        self.assertEqual(
            self.state["actions"], [["shux-kill", row["sessions"][0]["id"]]]
        )

    def test_scratch_sessions_are_cleaned_up(self) -> None:
        row = self.daemon()
        row["sessions"][0]["scratch"] = True
        self.run_script("-y", "--idle", "--grace", "1")
        self.assertEqual(row["proc"].wait(timeout=5), -15)

    def test_what_makes_a_daemon_in_use(self) -> None:
        cases = {
            "young empty daemon": lambda row: row.update(etime="09:59"),
            "accepted connection": lambda row: row.update(connections=1),
            "client process": self.client,
            "command running": lambda row: self.pane(row, foreground=False),
            "background job": lambda row: self.pane(row, child=True),
            "program, not a shell": lambda row: self.pane(row, "lazygit"),
            "recent output": lambda row: self.pane(row, quiet=5 * 3600),
        }
        for case, make in cases.items():
            with self.subTest(case=case):
                self.state["processes"] = []
                row = self.daemon(() if case == "young empty daemon" else ("fixture",))
                make(row)
                self.assertEqual(self.category(row, "--idle"), "in-use")

    def test_idle_after_sets_the_quiet_threshold(self) -> None:
        row = self.daemon()
        self.pane(row, quiet=2 * 3600)
        self.assertEqual(self.category(row), "in-use")
        self.assertEqual(self.category(row, "--idle-after", "1h"), "idle")
        self.assertEqual(self.category(row, VISARJANA_IDLE_AFTER="90m"), "idle")

    def test_session_without_panes_is_idle_only_when_old(self) -> None:
        row = self.daemon()
        self.assertEqual(self.category(row), "idle")
        row["sessions"][0]["created_at"] = int(time.time()) - 60
        self.state["processes"] = [row]  # run_script reloaded the state; put the change back in
        self.assertEqual(self.category(row), "in-use")

    def test_daemon_that_comes_into_use_is_spared(self) -> None:
        """The ledger said orphan or idle; by the act-time look it was attached or busy."""
        for case in ("orphan gains a connection", "idle pane starts a command"):
            with self.subTest(case=case):
                self.state["processes"] = []
                if case.startswith("orphan"):
                    row = self.daemon(())
                    change = [row["pid"], {"connections": 1}]
                else:
                    row = self.daemon()
                    change = [self.pane(row)["pid"], {"tpgid": 1}]
                row["after_list"] = {"2": [change]}  # list 1 is the ledger's, 2 the act-time look
                result = self.run_script("-y", "--idle", "--json", expected=1)
                self.assertIn("now in-use", result.stdout)
                self.assertIsNone(row["proc"].poll())
                self.assertEqual(self.state["actions"], [])

    def test_in_use_teardown_needs_its_socket_named(self) -> None:
        row = self.daemon()
        self.pane(row, "make test", quiet=0)
        other = self.daemon()
        self.pane(other, "make test", quiet=0)
        self.run_script("-y", "-s", row["socket"], "--in-use", "--grace", "1")
        self.assertEqual(row["proc"].wait(timeout=5), -15)
        self.assertIsNone(other["proc"].poll())

    def test_daemon_of_another_build_is_never_called(self) -> None:
        """Any shux call but `version` restarts a daemon of another build, losing its sessions."""
        row = self.daemon(mismatch=True)
        for args in (("-n",), ("-y", "--idle"), ("-y", "-s", row["socket"], "--in-use")):
            with self.subTest(args=args):
                result = self.run_script(*args, "--json", expected=1)
                self.assertEqual(self.state["actions"], [])
                self.assertIn('"category":"unknown"', result.stdout)
                self.assertIsNone(row["proc"].poll())

    def test_shell_that_is_not_at_a_prompt_is_in_use(self) -> None:
        for case, args, stat in (
            ("bash -c loop", "bash -c while :; do :; done", "Ss"),
            ("script", "bash ./deploy.sh", "Ss"),
            ("builtin loop at the prompt", "bash -l", "Rs+"),
        ):
            with self.subTest(case=case):
                self.state["processes"] = []
                row = self.daemon()
                self.pane(row, args)["stat"] = stat
                self.assertEqual(self.category(row, "--idle"), "in-use")

    def test_login_and_interactive_shells_are_idle(self) -> None:
        for args in ("-bash", "bash -l", "/bin/zsh -il", "fish --login"):
            with self.subTest(args=args):
                self.state["processes"] = []
                row = self.daemon()
                self.pane(row, args)
                self.assertEqual(self.category(row), "idle")

    def test_unreadable_evidence_is_unknown_never_removable(self) -> None:
        cases = {
            # lsof call 1 finds the socket; call 2 counts its connections
            "connections": lambda row: row.update(lsof_fail=[2]),
            "activity": lambda row: self.state["mtimes"].update(
                {f"/dev/{self.pane(row)['tty']}": "File: garbage\n1700000000"}
            ),
        }
        for case, make in cases.items():
            with self.subTest(case=case):
                self.state.update(processes=[], mtimes={})
                row = self.daemon()
                make(row)
                result = self.run_script("-y", "--idle", "--json", expected=1)
                self.assertIn('"category":"unknown"', result.stdout)
                self.assertIsNone(row["proc"].poll())

    def test_idle_daemon_with_several_sessions_is_dismissed_whole(self) -> None:
        row = self.daemon(("one", "two"))
        self.run_script("-y", "--idle", "--grace", "1")
        self.assertEqual(
            self.state["actions"],
            [["shux-kill", s["id"]] for s in row["sessions"]],
        )
        self.assertEqual(row["proc"].wait(timeout=5), -15)

    def test_attach_between_session_kills_stops_the_teardown(self) -> None:
        row = self.daemon(("one", "two"))
        # lists: 1 ledger, 2 first look, 3 look before kill one, 4 look before kill two.
        # A change keyed to a list is seen by that same look, so this client arrives after kill one.
        row["after_list"] = {"4": [[row["pid"], {"connections": 1}]]}
        self.run_script("-y", "--idle", "--grace", "1", expected=1)
        self.assertEqual(self.state["actions"], [["shux-kill", row["sessions"][0]["id"]]])
        self.assertIsNone(row["proc"].poll())

    def test_in_use_teardown_also_takes_an_idle_unit(self) -> None:
        row = self.daemon()
        self.assertEqual(self.category(row), "idle")
        self.run_script("-y", "-s", row["socket"], "--in-use", "--grace", "1")
        self.assertEqual(row["proc"].wait(timeout=5), -15)

    def test_keep_spares_the_whole_daemon(self) -> None:
        row = self.daemon(("keep", "other"))
        self.run_script("-y", "--idle", "--keep", "keep")
        self.assertIsNone(row["proc"].poll())
        self.assertEqual(self.state["actions"], [])

    def orphan(
        self, *, ignore_term: bool = False, ppid: int = 1, suffix: str = ""
    ) -> subprocess.Popen:
        proc = self.child(ignore_term=ignore_term)
        self.state["processes"].append(
            {
                "pid": proc.pid,
                "ppid": ppid,
                "args": f"{self.root}/.agent-browser/browsers/chrome/Contents/MacOS/"
                f"Google Chrome for Testing --headless{suffix}",
            }
        )
        return proc

    def test_orphan_cleanup_preserves_owned_browsers_and_helpers(self) -> None:
        orphan = self.orphan()
        owned = self.orphan(ppid=os.getpid())
        helper = self.orphan(suffix=" --type=renderer")
        self.run_script("-y", "--only", "browser", "--grace", "1")
        self.assertEqual(orphan.wait(timeout=5), -15)
        self.assertIsNone(owned.poll())
        self.assertIsNone(helper.poll())

    def test_force_is_required_for_sigkill(self) -> None:
        proc = self.orphan(ignore_term=True)
        self.run_script("-y", "--only", "browser", "--grace", "0", expected=1)
        self.assertIsNone(proc.poll())
        self.run_script("-y", "--only", "browser", "--grace", "0", "--force")
        self.assertEqual(proc.wait(timeout=5), -9)

    def test_headed_chrome_is_preserved(self) -> None:
        proc = self.orphan()
        self.state["processes"][-1]["args"] = self.state["processes"][-1][
            "args"
        ].replace(" --headless", "")
        self.run_script("-y", "--only", "browser", "--grace", "1")
        self.assertIsNone(proc.poll())

    def test_dry_run_preserves_everything(self) -> None:
        row = self.daemon()
        proc = row["proc"]
        self.state["browsers"] = ["fixture browser"]
        self.run_script("-n")
        self.assertEqual(self.state["actions"], [])
        self.assertIsNone(proc.poll())

    def test_nonterminal_requires_confirmation(self) -> None:
        row = self.daemon(())
        self.run_script(expected=2)
        self.assertIsNone(row["proc"].poll())

    def test_browser_sessions_are_listed_never_closed(self) -> None:
        self.state["browsers"] = ["fixture browser", "--leading-dash"]
        orphan = self.orphan()
        result = self.run_script("-y", "--only", "browser", "--grace", "1", "--json")
        records = self.events(result)
        listed = [e["session"] for e in records if e["event"] == "session"]
        self.assertEqual(listed, ["fixture browser", "--leading-dash"])
        self.assertEqual(records[-1]["event"], "finished")
        self.assertEqual(records[-1]["errors"], 0)
        self.assertEqual(self.state["actions"], [])
        self.assertEqual(orphan.wait(timeout=5), -15)
        self.assertNotIn("\033", result.stdout)

    def test_keep_browser_by_env_is_not_a_typo(self) -> None:
        self.state["browsers"] = ["keep"]
        self.run_script(VISARJANA_YES="1", VISARJANA_ONLY="browser", VISARJANA_KEEP="keep")
        self.assertEqual(self.state["actions"], [])

    def test_unmatched_keep_prevents_actions(self) -> None:
        row = self.daemon(())
        self.run_script("-y", "--keep", "typo", expected=2)
        self.assertIsNone(row["proc"].poll())

    def test_browser_list_failure(self) -> None:
        self.state["browser_list_failure"] = True
        self.run_script("-n", expected=1)

    def test_socket_filter_and_session_id(self) -> None:
        row = self.daemon(("--hostile name",))
        other = self.daemon(("unrelated",))
        self.run_script("-y", "--idle", "-s", row["socket"], "--grace", "1")
        self.assertEqual(
            self.state["actions"], [["shux-kill", row["sessions"][0]["id"]]]
        )
        self.assertEqual(row["proc"].wait(timeout=5), -15)
        self.assertIsNone(other["proc"].poll())

    def test_keep_full_and_short_id(self) -> None:
        row = self.daemon()
        for sid in (row["sessions"][0]["id"], row["sessions"][0]["id"][:8]):
            self.run_script("-y", "--idle", "--keep", sid)
            self.assertEqual(self.state["actions"], [])

    def test_multiple_keep_aliases_match(self) -> None:
        row = self.daemon()
        sid = row["sessions"][0]["id"]
        self.run_script("-y", "--idle", "-k", "fixture", "-k", sid, "-k", sid[:8])
        self.assertEqual(self.state["actions"], [])

    def test_unmatched_keep_dry_run_is_usage_error(self) -> None:
        self.run_script("-n", "--keep", "typo", expected=2)
        self.state["browsers"] = ["fixture"]
        self.run_script("-n", "--keep", "typo", expected=2)

    def test_unknown_socket_among_valid_filters_prevents_actions(self) -> None:
        row = self.daemon()
        self.run_script("-y", "-s", row["socket"], "-s", "/nonexistent", expected=2)
        self.assertEqual(self.state["actions"], [])

    def test_invalid_browser_response_is_failure(self) -> None:
        for response in (
            {"success": False},
            {"data": {"sessions": "bad"}},
            {"data": {"sessions": ["two\nlines"]}},
        ):
            with self.subTest(response=response):
                self.state["browser_response"] = response
                self.run_script("-n", expected=1)

    def test_unknown_socket(self) -> None:
        self.run_script("-n", "-s", "/nonexistent", expected=2)

    def test_explicit_socket_requires_shux(self) -> None:
        (self.bin / "shux").unlink()
        self.run_script(
            "-n", "-s", "/nonexistent", expected=2, PATH=f"{self.bin}:/usr/bin:/bin"
        )

    def test_unreachable_daemon_is_spared(self) -> None:
        row = self.daemon(socket_lost=True)
        proc = row["proc"]
        self.run_script("-y", expected=1)
        self.assertIsNone(proc.poll())

    def test_list_failure_is_spared(self) -> None:
        row = self.daemon(fail_lists=[1])
        proc = row["proc"]
        self.run_script("-y", expected=1)
        self.assertIsNone(proc.poll())

    def test_list_warnings_do_not_become_sessions(self) -> None:
        row = self.daemon(
            list_warning="WARN Daemon version mismatch — restarting daemon"
        )
        result = self.run_script("-n", "--json")
        events = [json.loads(line) for line in result.stdout.splitlines()]
        sessions = [e for e in events if e["event"] == "session" and "id" in e]
        self.assertEqual([e["id"] for e in sessions], [row["sessions"][0]["id"]])
        self.assertIn("WARN Daemon version mismatch", result.stderr)
        self.assertNotIn("arithmetic", result.stderr)
        self.assertEqual(self.state["actions"], [])

    def test_list_warnings_allow_empty_daemon_cleanup(self) -> None:
        row = self.daemon((), list_warning="WARN harmless diagnostic")
        self.run_script("-y", "--grace", "1")
        self.assertEqual(row["proc"].wait(timeout=5), -15)
        self.assertEqual(self.state["actions"], [])

    def test_list_warnings_do_not_affect_cleanup_or_relist(self) -> None:
        row = self.daemon(list_warning="WARN harmless diagnostic")
        result = self.run_script("-y", "--idle", "--grace", "1")
        self.assertEqual(
            self.state["actions"], [["shux-kill", row["sessions"][0]["id"]]]
        )
        self.assertEqual(row["proc"].wait(timeout=5), -15)
        self.assertNotIn("arithmetic", result.stderr)

    def test_integral_timestamp_notation_is_normalized(self) -> None:
        row = self.daemon()
        for timestamp in ("1.0", "1e3", "-0", "9007199254740991"):
            with self.subTest(timestamp=timestamp):
                session = {**row["sessions"][0], "created_at": "TIMESTAMP"}
                response = json.dumps({"sessions": [session]}).replace(
                    '"TIMESTAMP"', timestamp
                )
                row["lists"] = 0
                row["list_responses"] = {"1": response}
                self.state["processes"] = [row]
                result = self.run_script("-n", "--json")
                self.assertEqual(result.stderr, "")
                self.assertEqual(self.state["actions"], [])

    def test_invalid_session_list_is_spared(self) -> None:
        row = self.daemon()
        valid = row["sessions"][0]
        invalid_rows = (
            [{**valid, "id": value} for value in (None, "", 7, "bad\tid", "bad\nid")]
            + [
                {**valid, "name": value}
                for value in (None, "", 7, "bad\tname", "bad\nname")
            ]
            + [{**valid, "scratch": value} for value in (None, "false", 0)]
            + [
                {**valid, "created_at": value}
                for value in (None, "", "0", -1, 1.5, 1e100)
            ]
        )
        responses = [
            "",
            "not json",
            "null",
            "{}",
            '{"sessions":null}',
            '{"sessions":{}}',
            '{"sessions":[]}\n{"sessions":[]}',
        ]
        responses += [
            json.dumps({"sessions": [valid, invalid]}) for invalid in invalid_rows
        ]
        for response in responses:
            with self.subTest(response=response):
                row["lists"] = 0
                row["list_responses"] = {"1": response}
                self.state["processes"] = [row]
                result = self.run_script("-y", "--json", expected=1)
                events = [json.loads(line) for line in result.stdout.splitlines()]
                self.assertTrue(
                    any(e["event"] == "list" and e["level"] == "error" for e in events)
                )
                self.assertFalse(
                    any(e["event"] == "session" and "id" in e for e in events)
                )
                self.assertEqual(self.state["actions"], [])
                self.assertIsNone(row["proc"].poll())

    def test_unescaped_nul_response_is_rejected(self) -> None:
        row = self.daemon((), list_responses={"1": '{"sessions":[]}\x00'})
        self.run_script("-n", "--json", expected=1)
        self.assertEqual(self.state["actions"], [])
        self.assertIsNone(row["proc"].poll())

    def test_failed_list_with_valid_json_preserves_daemon(self) -> None:
        row = self.daemon((), fail_after_output=[1])
        result = self.run_script("-n", "--json", expected=1)
        self.assertIn("fixture list failed after valid JSON", result.stderr)
        self.assertEqual(self.state["actions"], [])
        self.assertIsNone(row["proc"].poll())

    def test_failed_relist_with_valid_json_preserves_daemon(self) -> None:
        row = self.daemon((), fail_after_output=[2])
        self.run_script("-y", expected=1)
        self.assertEqual(self.state["actions"], [])
        self.assertIsNone(row["proc"].poll())

    def test_invalid_relist_preserves_daemon(self) -> None:
        row = self.daemon((), list_responses={"2": '{"sessions":[{}]}'})
        self.run_script("-y", expected=1)
        self.assertIsNone(row["proc"].poll())
        self.assertEqual(self.state["actions"], [])

    def test_reused_pid_is_spared(self) -> None:
        row = self.daemon(reuse_after_list=True)
        proc = row["proc"]
        self.run_script("-y", "--idle")
        self.assertEqual(self.state["actions"], [])
        self.assertIsNone(proc.poll())

    def test_lost_socket_is_spared(self) -> None:
        row = self.daemon(lose_socket_after_list=True)
        proc = row["proc"]
        self.run_script("-y", "--idle", expected=1)
        self.assertEqual(self.state["actions"], [])
        self.assertIsNone(proc.poll())

    def test_new_sessions_spare_daemon(self) -> None:
        row = self.daemon(
            new_session={
                "id": "new-session",
                "name": "newcomer",
                "scratch": False,
                "created_at": int(time.time()),
            }
        )
        proc = row["proc"]
        result = self.run_script("-y", "--idle", expected=1)
        self.assertIn("gained sessions", result.stdout)
        self.assertIsNone(proc.poll())

    def test_session_made_after_the_ledger_spares_daemon(self) -> None:
        row = self.daemon(())
        newcomer = {"id": "late", "name": "late", "scratch": False, "created_at": 1}
        row["list_responses"] = {"2": json.dumps({"sessions": [newcomer]})}
        result = self.run_script("-y", expected=1)
        self.assertIn("gained sessions after the ledger (late)", result.stdout)
        self.assertEqual(self.state["actions"], [])
        self.assertIsNone(row["proc"].poll())

    def test_failed_kill_reports_error(self) -> None:
        row = self.daemon(kill_failure=True)
        proc = row["proc"]
        self.run_script("-y", "--idle", expected=1)
        self.assertIsNone(proc.poll())

    def test_failed_relist_spares_daemon(self) -> None:
        row = self.daemon(fail_lists=[2])
        proc = row["proc"]
        self.run_script("-y", "--idle", expected=1)
        self.assertIsNone(proc.poll())

    def orca_terminals(self, row: dict) -> None:
        for handle, agent in (("term_plain", ""), ("term_agent", "codex")):
            proc = self.child(ORCA_TERMINAL_HANDLE=handle, SHUX_SOCKET=row["socket"])
            self.state["processes"].append(
                {
                    "pid": proc.pid,
                    "args": "shux session attach fixture",
                    "env": {
                        "ORCA_TERMINAL_HANDLE": handle,
                        "SHUX_SOCKET": row["socket"],
                    },
                }
            )
            self.state["terminals"].append(
                {"handle": handle, "agentIdentity": agent, "title": "fixture"}
            )

    def teardown(self, row: dict, expected: int = 0) -> subprocess.CompletedProcess:
        return self.run_script(
            "-y", "-s", row["socket"], "--in-use", "--grace", "1", expected=expected
        )

    def test_client_with_relative_socket_does_not_break_the_snapshot(self) -> None:
        row = self.daemon(())
        self.client(row, "shux --socket rel.sock session list")  # listed last by ps
        self.run_script("-y")
        self.assertIsNotNone(row["proc"].wait(timeout=5))

    def test_attached_daemon_and_its_terminal_survive_a_sweep(self) -> None:
        row = self.daemon()
        self.orca_terminals(row)
        self.assertEqual(self.category(row, "--idle"), "in-use")
        self.run_script("-y", "--idle", "--grace", "1")
        self.assertEqual(self.state["actions"], [])
        self.assertIsNone(row["proc"].poll())

    def test_orca_association_and_agent_guard(self) -> None:
        row = self.daemon()
        self.orca_terminals(row)
        self.teardown(row)
        self.assertIn(["orca-close", "term_plain"], self.state["actions"])
        self.assertNotIn(["orca-close", "term_agent"], self.state["actions"])

    def test_orca_preserved_when_daemon_cannot_stop(self) -> None:
        row = self.daemon(fail_lists=[2])
        self.orca_terminals(row)
        self.teardown(row, expected=1)
        self.assertNotIn(["orca-close", "term_plain"], self.state["actions"])

    def test_orca_preserved_when_daemon_gains_sessions(self) -> None:
        row = self.daemon(
            new_session={
                "id": "new-session",
                "name": "newcomer",
                "scratch": False,
                "created_at": int(time.time()),
            }
        )
        self.orca_terminals(row)
        self.teardown(row, expected=1)
        self.assertNotIn(["orca-close", "term_plain"], self.state["actions"])

    def test_new_orca_agent_is_spared(self) -> None:
        row = self.daemon()
        self.orca_terminals(row)
        self.state["orca_new_agent"] = True
        self.teardown(row)
        self.assertNotIn(["orca-close", "term_plain"], self.state["actions"])

    def test_orca_verification_failure_is_failure(self) -> None:
        row = self.daemon()
        self.orca_terminals(row)
        self.state["orca_fail_lists"] = [3]
        self.teardown(row, expected=1)

    def test_no_orca_and_kept_daemon_leave_terminals(self) -> None:
        row = self.daemon()
        proc = self.child(
            ORCA_TERMINAL_HANDLE="term_fixture", SHUX_SOCKET=row["socket"]
        )
        self.state["processes"].append(
            {
                "pid": proc.pid,
                "args": "shux session attach fixture",
                "env": {
                    "ORCA_TERMINAL_HANDLE": "term_fixture",
                    "SHUX_SOCKET": row["socket"],
                },
            }
        )
        self.state["terminals"] = [
            {"handle": "term_fixture", "agentIdentity": "", "title": ""}
        ]
        self.run_script("-y", "-s", row["socket"], "--in-use", "--keep", "fixture")
        self.assertEqual(self.state["actions"], [])
        self.run_script("-n", "--no-orca")
        self.assertEqual(self.state["actions"], [])

    def test_live_lock_is_preserved(self) -> None:
        lock = self.root / "visarjana.lock"
        lock.mkdir()
        (lock / "pid").write_text(str(os.getpid()))
        self.write_state()
        result = subprocess.run(
            [BASH, str(SCRIPT), "-n"],
            check=False,
            env=self.env,
            text=True,
            capture_output=True,
            timeout=5,
        )
        self.assertEqual(result.returncode, 1)
        self.assertTrue(lock.exists())

    def test_stale_lock_is_reclaimed(self) -> None:
        lock = self.root / "visarjana.lock"
        lock.mkdir()
        (lock / "pid").write_text("2147483647")
        self.run_script("-n")


def main() -> None:
    unittest.main(verbosity=2)


if __name__ == "__main__":
    main()
