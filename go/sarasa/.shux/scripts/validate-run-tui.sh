#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT_DIR="${ROOT}/.shux/out/run-tui-final"
BIN_DIR="${ROOT}/.shux/out/bin"
BINARY="${BIN_DIR}/sarasa-fake"
CONFIG="${ROOT}/.shux/fixtures/tui-run.toml"

mkdir -p "${OUT_DIR}" "${BIN_DIR}"
rm -rf "${OUT_DIR:?}/"*

cleanup_session() {
    local session="$1"
    shux session kill "${session}" >/dev/null 2>&1 || true
}

(cd "${ROOT}" && go build -o "${BINARY}" ./internal/shuxtest/sarasa-fake)

validate_viewport() {
    local cols="$1"
    local rows="$2"
    local viewport="${cols}x${rows}"
    local session="sarasa-run-tui-${viewport}"
    local viewport_dir="${OUT_DIR}/${viewport}"
    local events="${viewport_dir}/events.ndjson"

    mkdir -p "${viewport_dir}"
    rm -f "${events}"
    cleanup_session "${session}"

    shux --format json session create "${session}" -d -- \
        env -u NO_COLOR -u CI \
            TERM=xterm-256color \
            COLORTERM=truecolor \
            SARASA_SHUX_EXPECTED_MANAGERS=3 \
            SARASA_SHUX_EVENTS="${events}" \
            "${BINARY}" --config "${CONFIG}" run --skip-cleanup >/dev/null

    trap 'cleanup_session "${session}"' RETURN

    shux pane set-size -s "${session}" --cols "${cols}" --rows "${rows}" >/dev/null

    shux pane wait-for -s "${session}" --text "BREW" --timeout-ms 10000 >/dev/null
    shux pane wait-for -s "${session}" --text "VOLTA" --timeout-ms 10000 >/dev/null
    shux pane wait-for -s "${session}" --text "PIPX" --timeout-ms 10000 >/dev/null
    shux pane wait-for -s "${session}" --text "1 upgraded" --timeout-ms 10000 >/dev/null
    shux pane wait-for -s "${session}" --text "1 failed" --timeout-ms 10000 >/dev/null
    shux pane wait-for -s "${session}" --text "1 skipped" --timeout-ms 10000 >/dev/null
    shux pane wait-for -s "${session}" --text "q quit" --timeout-ms 10000 >/dev/null

    shux pane capture -s "${session}" > "${viewport_dir}/capture.txt"
    shux --format json pane snapshot -s "${session}" \
        | jq -r .png_base64 \
        | base64 -d > "${viewport_dir}/snapshot.png"

    python3 - "${viewport_dir}/capture.txt" "${viewport_dir}/snapshot.png" "${events}" "${viewport}" <<'PY'
import json
import struct
import sys
from pathlib import Path

capture = Path(sys.argv[1]).read_text()
png = Path(sys.argv[2]).read_bytes()
events_path = Path(sys.argv[3])
viewport = sys.argv[4]

required = [
    "BREW",
    "VOLTA",
    "PIPX",
    "brew-upgraded",
    "skip-me",
    "volta-failed",
    "1 upgraded",
    "1 failed",
    "1 skipped",
    "q quit",
]
if viewport != "80x24":
    required.append("SARASA UPGRADE")
missing = [text for text in required if text not in capture]
if missing:
    raise SystemExit(f"missing expected TUI text: {missing}")

for forbidden in ["waiting..."]:
    if forbidden in capture:
        raise SystemExit(f"unexpected non-final TUI text: {forbidden}")

if png[:8] != b"\x89PNG\r\n\x1a\n":
    raise SystemExit("snapshot is not a PNG")
width, height = struct.unpack(">II", png[16:24])
if width <= 0 or height <= 0:
    raise SystemExit(f"invalid PNG dimensions: {width}x{height}")

events = [json.loads(line) for line in events_path.read_text().splitlines() if line.strip()]
starts = [event for event in events if event["event"] == "start"]
dones = [event for event in events if event["event"] == "done"]
if len(starts) != 3 or len(dones) != 3:
    raise SystemExit(f"unexpected event counts: starts={len(starts)} dones={len(dones)}")
first_done = next((i for i, event in enumerate(events) if event["event"] == "done"), None)
last_start = max(i for i, event in enumerate(events) if event["event"] == "start")
if first_done is None or first_done < last_start:
    raise SystemExit(f"managers did not all start before first completion: {events}")

print(f"PASS shux TUI validation {viewport}: png={width}x{height}, events={len(events)}")
PY
    cleanup_session "${session}"
    trap - RETURN
}

validate_viewport 80 24
validate_viewport 120 40
