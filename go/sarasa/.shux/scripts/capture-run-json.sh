#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SESSION="${SESSION:-sarasa-run-json}"
OUT_DIR="${ROOT}/.shux/out/run-json"
BINARY="${BINARY:-${ROOT}/sarasa}"
CONFIG="${OUT_DIR}/run-json-demo-config.toml"

mkdir -p "${OUT_DIR}"

if [[ ! -x "${BINARY}" ]]; then
    (cd "${ROOT}" && go build -o sarasa .)
fi

cat > "${CONFIG}" <<'TOML'
managers = ["custom"]

[custom]
state_dir = "~/.local/state/sarasa/run-json-demo"
default_timeout = "30s"

[[custom.tools]]
name = "json-demo"
current = { argv = ["sh", "-c", "printf 'json-demo v1.0.0'"], regex = "v?[0-9]+\\.[0-9]+\\.[0-9]+" }
latest = { value = "v1.1.0" }
upgrade = { shell = "printf 'installing ${name} ${current} -> ${latest}'" }
verify = { argv = ["sh", "-c", "printf 'json-demo v1.1.0'"], regex = "v?[0-9]+\\.[0-9]+\\.[0-9]+" }
TOML

shux session kill "${SESSION}" >/dev/null 2>&1 || true
shux --format json session create "${SESSION}" -d -- \
    env -u NO_COLOR TERM=xterm-256color COLORTERM=truecolor "${BINARY}" --config "${CONFIG}" run --dry-run --json >/dev/null

shux pane set-size -s "${SESSION}" --cols 120 --rows 34 >/dev/null
shux pane wait-for -s "${SESSION}" --text '"dry_run": true' --timeout-ms 10000 >/dev/null
shux pane wait-for -s "${SESSION}" --text '"would_upgrade"' --timeout-ms 10000 >/dev/null
sleep "${SETTLE_SECONDS:-1}"

shux pane capture -s "${SESSION}" > "${OUT_DIR}/sarasa-run-json.txt"
shux --format json pane snapshot -s "${SESSION}" \
    | jq -r .png_base64 \
    | base64 -d > "${OUT_DIR}/sarasa-run-json.png"

grep -q '"success": true' "${OUT_DIR}/sarasa-run-json.txt"
grep -q '"name": "json-demo"' "${OUT_DIR}/sarasa-run-json.txt"

shux session kill "${SESSION}" >/dev/null

printf '%s\n' "${OUT_DIR}/sarasa-run-json.png"
