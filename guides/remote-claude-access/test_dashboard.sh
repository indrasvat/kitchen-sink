#!/usr/bin/env bash
# Test dashboard functionality
cd /tmp
echo "Testing dashboard from /tmp directory..."

# Test that dashboard command is recognized
claude-session-git d <<< "q" 2>&1 | head -25

echo ""
echo "Dashboard test completed!"
