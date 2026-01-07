# 📱 Termius Quick Reference Card

## 🚀 Connection Info
```
Host: [Your Tailscale IP or hostname]
Port: 22
Username: [Your Mac username]
Key: [Your Termius key name]
Mosh: ON (for better mobile experience)
```

## ⚡ Quick Connect Steps
1. Open Termius
2. Tap your "Claude Code" host
3. You're in! Claude is ready

## ⌨️ Essential Shortcuts

### While Connected:
- **Ctrl-A D** → Disconnect (keeps running)
- **Ctrl-A C** → New window
- **Ctrl-A N** → Next window
- **Ctrl-A [** → Scroll mode (Q to exit)
- **Ctrl-C** → Cancel current Claude operation

### In Termius App:
- **Swipe right** → Show hosts
- **Two finger tap** → Send ESC
- **Pinch** → Zoom in/out
- **Long press** → Copy/paste

## 🔧 Common Fixes

### Can't Connect?
```bash
# On Mac Terminal:
tailscale status         # Check Tailscale
sudo systemsetup -setremotelogin on  # Enable SSH
```

### Lost Session?
```bash
# After reconnecting:
tmux ls                  # List sessions
tmux attach -t claude-main  # Reattach
```

### Everything Broken?
```bash
# On Mac Terminal:
tmux kill-server
tailscale down && tailscale up
tmux new -s claude-main "claude code"
```

## 📝 Daily Workflow
1. **Morning**: Tap host → Claude ready
2. **Switch networks**: Automatic (mosh)
3. **Close app**: Session keeps running
4. **Return**: Tap host → Continue working

## 🆘 Emergency
- Mac Terminal: `tmux kill-server`
- iPhone: Force quit Termius, reopen
- Nuclear option: Restart Mac's SSH

## 💡 Pro Tips
- Use landscape mode for coding
- Enable Face ID in Termius
- Dark theme saves battery
- Create widget for instant access

---
*Save this to Notes app for quick access!*