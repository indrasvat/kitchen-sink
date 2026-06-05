#!/bin/bash
# Convenience wrapper — uninstall the AirDrop auto-heal LaunchDaemon.
# Delegates to install.sh (single source of truth). Auto-elevates with sudo.
#   bash uninstall.sh        (or)   sudo bash uninstall.sh
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
exec /bin/bash "$here/install.sh" --uninstall "$@"
