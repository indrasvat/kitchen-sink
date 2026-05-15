#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SESSION="${SESSION:-sarasa-custom-dry-run}"
OUT_DIR="${ROOT}/.shux/out"
BINARY="${BINARY:-${ROOT}/sarasa}"
CONFIG="${OUT_DIR}/custom-demo-config.toml"

mkdir -p "${OUT_DIR}"

if [[ ! -x "${BINARY}" ]]; then
    (cd "${ROOT}" && go build -o sarasa .)
fi

cat > "${CONFIG}" <<'TOML'
managers = ["custom"]

[custom]
state_dir = "~/.local/state/sarasa/custom-demo"
default_timeout = "30s"

[[custom.tools]]
name = "demo-installer"
current = { argv = ["sh", "-c", "printf 'demo-installer v1.0.0'"], regex = "v?[0-9]+\\.[0-9]+\\.[0-9]+" }
latest = { value = "v1.1.0" }
upgrade = { shell = "printf 'installing ${name} ${current} -> ${latest}'" }
verify = { argv = ["sh", "-c", "printf 'demo-installer v1.1.0'"], regex = "v?[0-9]+\\.[0-9]+\\.[0-9]+" }

[[custom.tools]]
name = "demo-self-updater"
allow_unchanged = true
current = { argv = ["sh", "-c", "printf '2.0.0'"], regex = "[0-9]+\\.[0-9]+\\.[0-9]+" }
latest = { mode = "self" }
outdated = { mode = "always" }
upgrade = { argv = ["sh", "-c", "printf already-current"] }
verify = { argv = ["sh", "-c", "printf '2.0.0'"], regex = "[0-9]+\\.[0-9]+\\.[0-9]+" }
TOML

shux session kill "${SESSION}" >/dev/null 2>&1 || true
shux --format json session create "${SESSION}" -d -- \
    env -u NO_COLOR TERM=xterm-256color "${BINARY}" --config "${CONFIG}" run --dry-run >/dev/null

shux pane set-size -s "${SESSION}" --cols 110 --rows 30 >/dev/null
shux pane wait-for -s "${SESSION}" --text "CUSTOM" --timeout-ms 10000 >/dev/null
sleep "${SETTLE_SECONDS:-2}"

shux pane capture -s "${SESSION}" > "${OUT_DIR}/sarasa-custom-dry-run.txt"
shux --format json pane snapshot -s "${SESSION}" \
    | jq -r .png_base64 \
    | base64 -d > "${OUT_DIR}/sarasa-custom-dry-run.png"

shux session kill "${SESSION}" >/dev/null

printf '%s\n' "${OUT_DIR}/sarasa-custom-dry-run.png"
