# 📱 Complete Termius Setup Guide for Claude Code CLI Access

## 🎯 What We're Building
You'll be able to open Termius on your iPhone, tap once, and instantly access Claude Code CLI running on your MacBook. Sessions will stay alive even when you switch between WiFi and cellular or close the app.

## 📋 Pre-Setup Checklist
✅ Termius installed on iPhone  
✅ Tailscale installed and logged in on both MacBook and iPhone  
✅ tmux installed on MacBook  
✅ mosh installed on MacBook  

## 🔍 Understanding the Components

Before we start, here's what each tool does in simple terms:

- **Termius**: The app on your iPhone that acts like a remote control for your MacBook
- **Tailscale**: Creates a private, secure tunnel between your devices (like a VPN but easier)
- **tmux**: Keeps your Claude sessions running even when you disconnect
- **mosh**: Makes connections super stable on mobile networks (better than regular SSH)
- **SSH Keys**: Like a digital ID card that proves it's really you connecting

---

## 📍 Step 1: Find Your MacBook's Tailscale Address

On your MacBook, open Terminal and run:

```bash
tailscale ip -4
```

You'll see something like: `100.101.102.103`

**Write this number down** - you'll need it soon! This is your MacBook's private address on the Tailscale network.

Also get your MacBook's Tailscale name:
```bash
tailscale status | grep $(hostname)
```

You'll see something like: `my-macbook` or `johns-mbp`

**Write this name down too** - it's easier to remember than numbers!

---

## 🔐 Step 2: Create SSH Keys in Termius (iPhone)

SSH keys are like creating a special password that only your phone and MacBook know. Here's how:

### On Your iPhone (in Termius):

1. Open **Termius**
2. Tap the **Settings** (gear icon) at bottom right
3. Tap **Keychain**
4. Tap the **+** button (top right)
5. Select **Generate New Key**
6. Fill in:
   - **Label**: `Claude MacBook Key` (or any name you like)
   - **Type**: Select `ED25519` (it's the most secure)
   - **Passphrase**: Leave empty for convenience (or add one for extra security)
7. Tap **Save**

### Now Export the Public Key:

1. Stay in Keychain, tap on the key you just created
2. You'll see "Public Key" section
3. Tap the **Export** or **Share** button
4. Choose **Copy** 
5. Now email this to yourself or save it in Notes - you'll need it on your MacBook!

The public key looks something like this (but much longer):
```
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI... 
```

---

## 🖥️ Step 3: Add Your iPhone's Key to MacBook

Now we need to tell your MacBook to trust your iPhone. On your MacBook:

1. Open Terminal
2. Create the SSH folder if it doesn't exist:
   ```bash
   mkdir -p ~/.ssh
   chmod 700 ~/.ssh
   ```

3. Add your iPhone's public key (replace with your actual key):
   ```bash
   echo "YOUR_PUBLIC_KEY_HERE" >> ~/.ssh/authorized_keys
   ```
   
   Example:
   ```bash
   echo "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILfGqM... Termius" >> ~/.ssh/authorized_keys
   ```

4. Set the correct permissions (very important!):
   ```bash
   chmod 600 ~/.ssh/authorized_keys
   ```

5. Enable SSH on your MacBook:
   ```bash
   sudo systemsetup -setremotelogin on
   ```
   Enter your MacBook password when prompted.

---

## 📱 Step 4: Configure Termius Host (iPhone)

Now let's set up the connection in Termius:

### Create New Host:

1. Open **Termius** on iPhone
2. Tap **Hosts** (bottom navigation)
3. Tap **+** button (top right)
4. Tap **New Host**

### Fill in Basic Settings:

**Connection**
- **Label**: `Claude Code` (or whatever you want to call it)
- **Address**: Your Tailscale IP (like `100.101.102.103`) or name (like `my-macbook`)
- **Port**: `22` (already filled)

**Credentials**
- **Username**: Your Mac username (run `whoami` on Mac to check)
  - Example: `johnsmith` (NOT your full name, just the username)
- **Password**: Leave empty (we're using keys!)
- **Key**: Select `Claude MacBook Key` (the one you created)

### Advanced Settings (scroll down):

Tap **Advanced** and configure:

**Terminal**
- **Terminal Type**: `xterm-256color`
- **Font Size**: Set to your preference (14 is good for iPhone)

**SSH**
- **SSH Keepalive Interval**: `60` (keeps connection alive)
- **Compression**: Toggle ON (faster on slow networks)

### Save the Host:
- Tap **Save** (top right)

---

## 🚀 Step 5: Enable Mosh for Better Mobile Experience

Mosh makes your connection survive network changes. Here's how to enable it:

### In Termius (on the host you just created):

1. Tap on your `Claude Code` host to see details
2. Scroll down to find **Mosh** section
3. Toggle **Use Mosh** to ON
4. **Mosh Port Range**: Leave as `Auto` or set to `60000-61000`
5. **Mosh Server Path**: `/usr/local/bin/mosh-server`
6. Tap **Save**

### Test Mosh is Working on MacBook:

On your MacBook, run:
```bash
which mosh-server
```

Should show: `/usr/local/bin/mosh-server`

If not found, install it:
```bash
brew install mosh
```

---

## 🎯 Step 6: Set Up Claude Session Management

Let's create a command that automatically connects you to Claude Code:

### On Your MacBook:

1. Create the startup script:
   ```bash
   cat > ~/start-claude.sh << 'EOF'
   #!/bin/bash
   # Automatically start or connect to Claude Code session
   
   SESSION_NAME="claude-main"
   
   # Check if tmux session exists
   tmux has-session -t $SESSION_NAME 2>/dev/null
   
   if [ $? != 0 ]; then
       # Create new session with Claude Code
       tmux new-session -d -s $SESSION_NAME "claude code"
       echo "Created new Claude session"
   fi
   
   # Attach to the session
   tmux attach-session -t $SESSION_NAME
   EOF
   ```

2. Make it executable:
   ```bash
   chmod +x ~/start-claude.sh
   ```

3. Test it works:
   ```bash
   ~/start-claude.sh
   ```
   
   You should see Claude Code start. Press `Ctrl-A` then `D` to detach (leave it running).

---

## 📲 Step 7: Create Quick Connect in Termius

Let's make it one-tap to connect:

### Method 1: Startup Command

1. In Termius, edit your `Claude Code` host
2. Find **Startup Command** or **Run Command**
3. Enter: `/Users/YOUR_USERNAME/start-claude.sh`
   - Replace YOUR_USERNAME with your actual Mac username
4. Save

### Method 2: Quick Actions (Termius Premium)

If you have Termius Premium:
1. Go to **Settings** → **Quick Actions**
2. Create new action:
   - **Name**: `Start Claude`
   - **Command**: `~/start-claude.sh`
3. Assign to your host

---

## ✅ Step 8: Test Your Connection!

1. Open **Termius** on iPhone
2. Tap your **Claude Code** host
3. You should connect immediately and see Claude Code!

### If Connection Works:
Congratulations! 🎉 Try these commands:
- Type `help` to see Claude commands
- Type a question to Claude
- Press `Ctrl-A` then `D` to disconnect (session keeps running)
- Reconnect and you'll be right where you left off!

### If Connection Fails:
See Troubleshooting below.

---

## 🔧 Step 9: Optimize for Daily Use

### Create iOS Home Screen Shortcut:

1. In Termius, connect to your host once
2. On iOS home screen, open **Shortcuts** app
3. Create new shortcut:
   - Add action: **Open App** → Select **Termius**
   - Add action: **Open URL** → Enter: `termius://connect/[host-id]`
4. Add to Home Screen with name "Claude Code"

### Set Up Touch/Face ID:

1. In Termius **Settings** → **Security**
2. Enable **Touch ID** / **Face ID**
3. Set **Auto-lock** to your preference

### Configure Gestures:

In Termius **Settings** → **Terminal**:
- **Two finger tap**: Send Escape
- **Three finger tap**: Toggle keyboard
- **Swipe from edge**: Show/hide toolbar

---

## 🆘 Troubleshooting Guide

### "Connection Refused" Error

1. Check Tailscale is connected on both devices:
   ```bash
   # On MacBook
   tailscale status
   ```
   Should show "Active" and list your iPhone

2. Test basic connection:
   ```bash
   # On MacBook
   tailscale ping YOUR_IPHONE_NAME
   ```

3. Verify SSH is enabled:
   ```bash
   sudo systemsetup -getremotelogin
   ```
   Should say "Remote Login: On"

### "Permission Denied (publickey)" Error

1. Check your key is in authorized_keys:
   ```bash
   cat ~/.ssh/authorized_keys
   ```
   Should show your Termius key

2. Fix permissions:
   ```bash
   chmod 700 ~/.ssh
   chmod 600 ~/.ssh/authorized_keys
   ```

3. Check SSH logs:
   ```bash
   sudo log show --predicate 'process == "sshd"' --last 5m
   ```

### "Host Key Verification Failed"

This happens first time connecting. In Termius:
1. You'll see a popup about "Unknown Host"
2. Tap **Accept** or **Trust**
3. This adds your MacBook's fingerprint - only happens once

### Mosh Not Working

1. Test mosh directly in Termius terminal:
   ```
   mosh YOUR_MACBOOK_IP
   ```

2. Check firewall:
   ```bash
   # On MacBook
   sudo /usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate
   ```

3. If firewall is on, allow mosh:
   ```bash
   sudo /usr/libexec/ApplicationFirewall/socketfilterfw --add /usr/local/bin/mosh-server
   ```

### Session Disappeared

Your Claude session is probably still running! Just reconnect:
```bash
# See all sessions
tmux ls

# Reconnect to Claude
tmux attach -t claude-main
```

---

## 📚 Essential Commands Cheat Sheet

### tmux Commands (After Connecting)
```bash
Ctrl-A C        # Create new window
Ctrl-A N        # Next window
Ctrl-A P        # Previous window
Ctrl-A D        # Detach (disconnect but keep running)
Ctrl-A [        # Scroll mode (use arrows, Q to exit)
Ctrl-A ?        # Show all commands
```

### Claude Code Commands
```bash
help           # Show Claude commands
clear          # Clear screen
exit           # Exit Claude (stays in tmux)
Ctrl-C         # Cancel current operation
```

### Emergency Commands
```bash
# Kill stuck session (on MacBook)
tmux kill-session -t claude-main

# Restart everything
tmux kill-server
tmux new -s claude-main "claude code"

# Check what's running
ps aux | grep -E "(tmux|claude)"
```

---

## 🎨 Customization Tips

### Make Text Easier to Read:
In Termius **Settings** → **Terminal**:
- **Font**: SF Mono or Menlo
- **Font Size**: 14-16 for iPhone
- **Line Spacing**: 1.1
- **Cursor**: Block + Blinking

### Color Schemes:
- **Dark Mode**: Dracula or Tomorrow Night
- **Light Mode**: Solarized Light or Github

### Better Keyboard:
- Consider external keyboard for long sessions
- Or use iPhone in landscape mode
- Enable **Keyboard Clicks** for feedback

---

## 🔒 Security Best Practices

1. **Always use Tailscale** - Never expose SSH to the internet
2. **Use Face/Touch ID** in Termius
3. **Rotate SSH keys** every few months:
   ```bash
   # Generate new key in Termius
   # Add to MacBook
   # Remove old key from ~/.ssh/authorized_keys
   ```
4. **Monitor access**:
   ```bash
   # See who's connected
   who
   
   # Check recent connections
   last -10
   ```

---

## 🎯 Quick Daily Workflow

1. **Morning**: Open Termius → Tap "Claude Code" → You're in!
2. **During Day**: Just switch apps - session stays active
3. **Network Changes**: Mosh handles it automatically
4. **End of Day**: Just close Termius - session keeps running
5. **Next Day**: Reconnect and continue where you left off

---

## 💡 Pro Tips

1. **Create Multiple Sessions** for different projects:
   ```bash
   tmux new -s claude-project1
   tmux new -s claude-project2
   ```

2. **See All Sessions**:
   ```bash
   tmux ls
   ```

3. **Quick Switch** between sessions:
   ```bash
   tmux switch -t claude-project2
   ```

4. **Save Session Output**:
   ```bash
   # In tmux, press Ctrl-A then :
   capture-pane -S -3000
   save-buffer ~/claude-output.txt
   ```

5. **Battery Saving**: 
   - Use black background (OLED screens)
   - Reduce keepalive interval if on cellular

---

## 🚨 If Everything Breaks

Don't panic! Run this reset on your MacBook:

```bash
# Kill everything
tmux kill-server
pkill mosh-server

# Restart Tailscale
tailscale down
tailscale up

# Create fresh session
tmux new -s claude-main "claude code"

# Test connection
ssh localhost echo "SSH works!"
```

Then try connecting from Termius again.

---

## ✅ Success Checklist

After setup, you should be able to:
- [ ] Connect to Claude Code in <5 seconds
- [ ] See your Claude session
- [ ] Type commands and get responses
- [ ] Disconnect and reconnect without losing work
- [ ] Switch from WiFi to cellular without disconnection (with Mosh)
- [ ] Access from anywhere via Tailscale

---

## 📞 Getting More Help

1. **Termius Support**: support@termius.com
2. **Tailscale Help**: https://tailscale.com/kb
3. **tmux Manual**: Run `man tmux` on MacBook
4. **Claude Code Issues**: https://github.com/anthropics/claude-code/issues

Remember: You're creating a private, secure tunnel between your devices. Nobody else can access this - it's like having a private road between your iPhone and MacBook!

Good luck, and enjoy coding with Claude from anywhere! 🚀