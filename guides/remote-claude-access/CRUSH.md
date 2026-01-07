# CRUSH.md - Remote Claude Code CLI Access

## Build/Test/Lint Commands
```bash
# Test dashboard functionality
./test_dashboard.sh

# Setup and configuration
./setup-tailscale.sh          # Initial Tailscale setup
./setup-gotty.sh              # Web-based access setup
./verify-termius-setup.sh     # Verify Termius configuration

# Make scripts executable
chmod +x *.sh
./make-executable.sh          # Batch make all scripts executable
```

## Session Management Commands
```bash
# Quick start (most common)
./claude-session.sh quickstart

# Session operations
./claude-session.sh list                    # List active sessions
./claude-session.sh new [name]              # Create new session
./claude-session.sh attach [name]           # Attach to session
./claude-session.sh kill [name]             # Kill session
./claude-session.sh send [name] [command]   # Send command to session
./claude-session.sh monitor [name]          # Monitor session status
```

## Code Style Guidelines
- **Shell Scripts**: Use `#!/usr/bin/env bash` or `#!/bin/bash` shebang
- **Error Handling**: Always use `set -e` for strict error handling
- **Colors**: Use consistent color variables (RED, GREEN, YELLOW, BLUE, NC)
- **Functions**: Descriptive names with snake_case (e.g., `list_sessions`, `new_session`)
- **Variables**: Use UPPER_CASE for constants, lowercase for local vars
- **Validation**: Check command availability with `command -v` before use
- **User Feedback**: Provide clear status messages with emoji indicators
- **Documentation**: Include purpose comment at top of each script

## Security Requirements
- SSH key-only authentication (no passwords)
- Tailscale WireGuard encryption for all connections
- Regular security audits and monitoring
- Fail2ban intrusion prevention
- Comprehensive audit logging