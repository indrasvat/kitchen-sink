#!/bin/bash
# Make all scripts executable and set up the environment

echo "🔧 Setting up Remote Claude Code Access..."

# Make all shell scripts executable
chmod +x setup-tailscale.sh
chmod +x setup-gotty.sh
chmod +x claude-session.sh
chmod +x gotty-start.sh 2>/dev/null
chmod +x gotty-stop.sh 2>/dev/null
chmod +x make-executable.sh

# Copy tmux config to home directory
cp .tmux.conf ~/.tmux.conf

echo "✅ All scripts are now executable!"
echo ""
echo "📋 Next Steps:"
echo "1. Run: ./setup-tailscale.sh"
echo "2. Install Tailscale on your iPhone"
echo "3. Either:"
echo "   a) Set up Blink Shell (see BLINK_SHELL_SETUP.md)"
echo "   b) Run: ./setup-gotty.sh for web access"
echo "4. Test connection: ./claude-session.sh quickstart"
echo ""
echo "📚 Documentation:"
echo "- README.md: Complete overview and quick start"
echo "- BLINK_SHELL_SETUP.md: iOS app configuration"
echo "- SECURITY.md: Security hardening guide"
echo "- TROUBLESHOOTING.md: Common issues and fixes"