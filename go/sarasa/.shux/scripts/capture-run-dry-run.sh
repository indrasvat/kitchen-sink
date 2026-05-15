#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SESSION="${SESSION:-sarasa-run-dry-run}"
OUT_DIR="${ROOT}/.shux/out"
BINARY="${BINARY:-${ROOT}/sarasa}"
CONFIG="${CONFIG:-}"

mkdir -p "${OUT_DIR}"

if [[ ! -x "${BINARY}" ]]; then
    (cd "${ROOT}" && go build -o sarasa .)
fi

shux session kill "${SESSION}" >/dev/null 2>&1 || true

args=("${BINARY}")
if [[ -n "${CONFIG}" ]]; then
    args+=(--config "${CONFIG}")
fi
args+=(run --dry-run)

shux --format json session create "${SESSION}" -d -- \
    env -u NO_COLOR TERM=xterm-256color "${args[@]}" >/dev/null

shux pane set-size -s "${SESSION}" --cols 100 --rows 34 >/dev/null
shux pane wait-for -s "${SESSION}" --text "SARASA DRY RUN" --timeout-ms 10000 >/dev/null
sleep "${SETTLE_SECONDS:-2}"

shux pane capture -s "${SESSION}" > "${OUT_DIR}/sarasa-run-dry-run.txt"
shux --format json pane snapshot -s "${SESSION}" \
    | jq -r .png_base64 \
    | base64 -d > "${OUT_DIR}/sarasa-run-dry-run.png"

shux session kill "${SESSION}" >/dev/null

printf '%s\n' "${OUT_DIR}/sarasa-run-dry-run.png"
