#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT_DIR="${ROOT}/.shux/out/run-tui-real-brew"
BIN_DIR="${OUT_DIR}/bin"
BINARY="${BIN_DIR}/sarasa-real"
FAKE_BREW="${BIN_DIR}/brew"
CONFIG="${OUT_DIR}/config.toml"
STATE="${OUT_DIR}/brew-state.txt"
LOG="${OUT_DIR}/brew-commands.log"
SESSION="sarasa-run-tui-real-brew"

mkdir -p "${BIN_DIR}"
rm -rf "${OUT_DIR:?}/"*
mkdir -p "${BIN_DIR}" "${OUT_DIR}/logs"

cleanup() {
    shux session kill "${SESSION}" >/dev/null 2>&1 || true
}
trap cleanup EXIT

(cd "${ROOT}" && go build -o "${BINARY}" .)

cat > "${CONFIG}" <<EOF_CONFIG
managers = ["brew"]

[skip]
brew = []
volta = []
pipx = []
bun = []
skills = []
custom = []

[logging]
dir = "${OUT_DIR}/logs"
retention_days = 1
level = "debug"

[brew]
greedy = false

[npm]
skip_major = false

[volta]
skip_major = false
EOF_CONFIG

cat > "${FAKE_BREW}" <<'EOF_BREW'
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "$*" >> "${SARASA_REAL_BREW_LOG}"

version="1.0.0"
if [[ -f "${SARASA_REAL_BREW_STATE}" ]]; then
    version="$(cat "${SARASA_REAL_BREW_STATE}")"
fi

case "${1:-}" in
    update)
        exit 0
        ;;
    outdated)
        cat <<JSON
{"formulae":[{"name":"real-brew-demo","installed_versions":["${version}"],"current_version":"1.1.0"}],"casks":[]}
JSON
        exit 0
        ;;
    upgrade)
        if [[ "${2:-}" == "--formula" && "${3:-}" == "real-brew-demo" ]]; then
            printf '1.1.0' > "${SARASA_REAL_BREW_STATE}"
            exit 0
        fi
        echo "unexpected brew upgrade args: $*" >&2
        exit 2
        ;;
    info)
        if [[ "${2:-}" == "--json=v2" && "${3:-}" == "--formula" && "${4:-}" == "real-brew-demo" ]]; then
            cat <<JSON
{"formulae":[{"name":"real-brew-demo","installed":[{"version":"${version}"}]}],"casks":[]}
JSON
            exit 0
        fi
        echo "unexpected brew info args: $*" >&2
        exit 2
        ;;
    --cache)
        printf '%s\n' "${TMPDIR:-/tmp}/sarasa-fake-brew-cache"
        exit 0
        ;;
    cleanup|autoremove)
        exit 0
        ;;
esac

echo "unexpected brew args: $*" >&2
exit 2
EOF_BREW
chmod +x "${FAKE_BREW}"

cleanup
shux --format json session create "${SESSION}" -d -- \
    env -u NO_COLOR -u CI \
        PATH="${BIN_DIR}:${PATH}" \
        TERM=xterm-256color \
        COLORTERM=truecolor \
        SARASA_REAL_BREW_LOG="${LOG}" \
        SARASA_REAL_BREW_STATE="${STATE}" \
        "${BINARY}" --config "${CONFIG}" run --skip-cleanup >/dev/null

shux pane set-size -s "${SESSION}" --cols 100 --rows 32 >/dev/null
shux pane wait-for -s "${SESSION}" --text "real-brew-demo" --timeout-ms 15000 >/dev/null
shux pane wait-for -s "${SESSION}" --text "1 upgraded" --timeout-ms 15000 >/dev/null
shux pane wait-for -s "${SESSION}" --text "q quit" --timeout-ms 15000 >/dev/null

shux pane capture -s "${SESSION}" > "${OUT_DIR}/capture.txt"
shux --format json pane snapshot -s "${SESSION}" \
    | jq -r .png_base64 \
    | base64 -d > "${OUT_DIR}/snapshot.png"

python3 - "${OUT_DIR}/capture.txt" "${OUT_DIR}/snapshot.png" "${STATE}" "${LOG}" <<'PY'
import struct
import sys
from pathlib import Path

capture = Path(sys.argv[1]).read_text()
png = Path(sys.argv[2]).read_bytes()
state = Path(sys.argv[3]).read_text()
log = Path(sys.argv[4]).read_text()

for text in ["SARASA UPGRADE", "BREW", "real-brew-demo", "1.0.0", "1.1.0", "1 upgraded", "q quit"]:
    if text not in capture:
        raise SystemExit(f"missing expected TUI text: {text!r}")

if state != "1.1.0":
    raise SystemExit(f"fake brew state = {state!r}, want '1.1.0'")

for text in ["update", "outdated --json=v2", "upgrade --formula real-brew-demo", "info --json=v2 --formula real-brew-demo"]:
    if text not in log:
        raise SystemExit(f"missing expected brew command: {text!r}\n{log}")

if png[:8] != b"\x89PNG\r\n\x1a\n":
    raise SystemExit("snapshot is not a PNG")
width, height = struct.unpack(">II", png[16:24])
if width <= 0 or height <= 0:
    raise SystemExit(f"invalid PNG dimensions: {width}x{height}")

print(f"PASS shux real Brew TUI validation: png={width}x{height}, state={state}")
PY
