# Product Requirements Document: Clux
## Claude Session Monitor for macOS

**Version:** 1.0.0  
**Date:** 2025-01-26  
**Timeline:** 1 Day Build  
**Platform:** macOS 13.0+ (Ventura)  
**Language:** Swift 5.9+ with SwiftUI  

---

## 1. Executive Summary

Clux is a lightweight macOS menu bar application that monitors and manages tmux sessions running Claude Code CLI. It provides real-time session monitoring, quick command execution, and seamless integration with both local and remote (Tailscale) connections.

### Key Value Propositions
- **Instant Visibility**: Monitor all Claude sessions from the menu bar
- **Quick Control**: Manage sessions without opening terminal
- **Persistent Monitoring**: Runs in background with minimal resource usage
- **Remote Ready**: Works with Tailscale connections out of the box

---

## 2. Technical Specifications

### 2.1 Development Environment
```yaml
Platform: macOS 13.0+
IDE: Xcode 15.0+
Language: Swift 5.9
UI Framework: SwiftUI
Architecture: MVVM
Package Manager: Swift Package Manager
```

### 2.2 Dependencies
```swift
// Package.swift dependencies
.package(url: "https://github.com/apple/swift-nio-ssh.git", from: "0.8.0")
.package(url: "https://github.com/SwiftyJSON/SwiftyJSON.git", from: "5.0.0")
.package(url: "https://github.com/sindresorhus/KeyboardShortcuts.git", from: "1.0.0")
.package(url: "https://github.com/sindresorhus/LaunchAtLogin.git", from: "5.0.0")
.package(url: "https://github.com/gonzalezreal/swift-markdown-ui.git", from: "2.0.0")
.package(url: "https://github.com/raspu/Highlightr.git", from: "2.2.0")
.package(url: "https://github.com/sparkle-project/Sparkle.git", from: "2.0.0")
```

### 2.3 UI Enhancement Libraries
```swift
// Best-in-class UI components for premium look
- SwiftUI-Shimmer         // Loading animations
- Lottie-iOS              // Micro-animations
- ProgressHUD             // Beautiful progress indicators
- SwiftUIX                // Extended UI components
- Introspect              // UIKit bridge for advanced features
- PopoverKit              // Custom popovers
- SwiftUI-Blur            // Glassmorphism effects
```

### 2.4 System Requirements
- **Memory**: <50MB idle, <100MB active
- **CPU**: <2% idle, <10% during refresh
- **Storage**: ~10MB app size
- **Network**: SSH access to target machines

---

## 3. Core Features (MVP - Day 1)

### 3.1 Menu Bar Application
```swift
// Menu bar icon states
enum SessionStatus {
    case active     // Green dot overlay
    case inactive   // Gray icon
    case error      // Red dot overlay
    case warning    // Yellow dot overlay
}
```

### 3.2 Session Monitoring
```bash
# Commands to implement
tmux list-sessions -F "#{session_name}:#{session_created}:#{session_attached}"
tmux capture-pane -t session-name -p
tmux list-panes -t session-name -F "#{pane_pid}"
```

### 3.3 HUD Window
- **Size**: 450x600px (resizable)
- **Position**: Remember last position
- **Sections**: Session list, output viewer, command input

### 3.4 Basic Session Management
- List sessions
- Create new session
- Attach to session (opens Terminal.app)
- Kill session
- Send command to session

---

## 4. Data Models

### 4.1 Core Models
```swift
struct TmuxSession: Identifiable {
    let id: String          // session_name
    var created: Date
    var isAttached: Bool
    var runtime: TimeInterval
    var lastActivity: Date
    var outputBuffer: [String]
}

struct ConnectionProfile: Codable {
    let id: UUID
    var name: String
    var host: String        // "localhost" or Tailscale IP
    var port: Int = 22
    var username: String
    var useKeychain: Bool = true
}

struct AppSettings: Codable {
    var refreshInterval: TimeInterval = 5.0
    var maxOutputLines: Int = 100
    var showNotifications: Bool = true
    var launchAtLogin: Bool = false
    var globalHotkey: String = "cmd+shift+c"
}
```

---

## 5. User Interface Design

### 5.0 Visual Design System
```swift
// Design Tokens
struct CluxDesign {
    // Colors (SF Symbols + Custom)
    static let activeGreen = Color(hex: "00FF88")     // Neon green
    static let warningAmber = Color(hex: "FFB800")    // Amber
    static let errorRed = Color(hex: "FF3B30")        // System red
    static let bgPrimary = Color(hex: "1C1C1E")       // Near black
    static let bgSecondary = Color(hex: "2C2C2E")     // Dark gray
    static let bgTertiary = Color(hex: "3A3A3C")      // Medium gray
    
    // Typography
    static let fontMono = "SF Mono"
    static let fontUI = "SF Pro Display"
    
    // Effects
    static let glassBackground = Material.ultraThin
    static let shadowRadius: CGFloat = 20
    static let cornerRadius: CGFloat = 12
    static let animationSpring = Animation.spring(response: 0.3, dampingFraction: 0.7)
}
```

### 5.1 Menu Bar Item
```swift
// MenuBarView.swift structure
- Icon with status indicator
- Dropdown menu:
  - Session list (clickable)
  - Separator
  - "Open Clux" (opens HUD)
  - "New Session..."
  - Separator
  - "Preferences..." (⌘,)
  - "Quit" (⌘Q)
```

### 5.2 Main HUD Window
```swift
// MainWindow.swift structure
NavigationSplitView {
    // Sidebar: Session list
    SessionListView()
} detail: {
    // Main: Session details
    VStack {
        SessionInfoHeader()
        OutputViewer()
        CommandInputBar()
    }
}
```

### 5.3 Main HUD Window - Premium UI Mockup
```
┌─────────────────────────────────────────────────────┐
│ ⚫️🔴🟡  Clux                              🔍 ⚙️ ⬜ ✕ │  <- Traffic lights + frosted glass
├─────────────────────────────────────────────────────┤
│ 🟢 Connected to MacBook-Pro • Latency: 2ms         │  <- Animated pulse on 🟢
├─────────────────────────────────────────────────────┤
│                                                      │
│  SESSIONS                              [✨ New]     │  <- Gradient button
│ ┌────────────────────────────────────────────────┐ │
│ │ ╭─────────────────────────────────────────────╮ │ │
│ │ │ 💚 claude-main              ● Running  2:34h│ │ │  <- Glassmorphism cards
│ │ │ ░░░░░░░░░░░░░░░░░░░░░░░░░░░░ CPU 12% ░░░░░ │ │ │  <- Live progress bar
│ │ │ 📊 1,247 lines • Last active: 2s ago       │ │ │
│ │ ╰─────────────────────────────────────────────╯ │ │
│ │                                                  │ │
│ │ ╭─────────────────────────────────────────────╮ │ │
│ │ │ 💚 claude-project1          ● Running   45m │ │ │
│ │ │ ░░░░░░░░░░░░░░░░░░░░░░░░░░░░ CPU  3% ░░░░░ │ │ │
│ │ │ 📊 523 lines • Last active: 15s ago        │ │ │
│ │ ╰─────────────────────────────────────────────╯ │ │
│ │                                                  │ │
│ │ ╭─────────────────────────────────────────────╮ │ │
│ │ │ ⚫ claude-test              ○ Stopped    -- │ │ │
│ │ │ ░░░░░░░░░░░░░░░░░░░░░░░░░░░░ CPU  0% ░░░░░ │ │ │
│ │ │ 📊 0 lines • Last active: 1h ago           │ │ │
│ │ ╰─────────────────────────────────────────────╯ │ │
│ └────────────────────────────────────────────────┘ │
│                                                      │
│  OUTPUT                         [📋 Copy] [🗑 Clear] │  <- Icon buttons with hover
│ ┌────────────────────────────────────────────────┐ │
│ │ ╭────────────────────────────────────────────╮  │ │
│ │ │ $ Processing request...                    │  │ │  <- Syntax highlighted
│ │ │ ✓ Analysis complete                        │  │ │  <- With colors
│ │ │ → Generated 150 lines of code              │  │ │
│ │ │ ┃ def calculate_metrics():                 │  │ │
│ │ │ ┃     return {"success": True}             │  │ │
│ │ │ ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░ │  │ │  <- Fade out older lines
│ │ ╰────────────────────────────────────────────╯  │ │
│ └────────────────────────────────────────────────┘ │
│                                                      │
│ ╭──────────────────────────────────────────────╮   │
│ │ 💬 Send command...              [↩️ Send]    │   │  <- Floating input
│ ╰──────────────────────────────────────────────╯   │
└─────────────────────────────────────────────────────┘

Visual Effects:
- Frosted glass background (vibrancy)
- Smooth spring animations on all transitions
- Glow effects on active elements
- Subtle shadows with blur
- Gradient accents (green to teal)
- Micro-animations (pulsing status dots)
```

### 5.4 Menu Bar Dropdown - Premium Design
```
╭─────────────────────────────╮
│ Clux  🟢                    │  <- Animated status dot
├─────────────────────────────┤
│ Sessions                    │
│ ├─ 💚 claude-main    2h 34m │  <- With activity sparkline ▁▃▅▇▅▃▁
│ ├─ 💚 claude-project1   45m │
│ └─ ⚫ claude-test        -- │
├─────────────────────────────┤
│ ✨ New Session...           │
│ 🖥  Show Clux      ⌘⇧C     │
├─────────────────────────────┤
│ ⚙️  Preferences...  ⌘,      │
│ 🔄 Check for Updates...     │
│ ❌ Quit            ⌘Q       │
╰─────────────────────────────╯

Hover Effects:
- Row highlight with gradient
- Icon rotation/bounce
- Tooltip with session details
```

### 5.5 Preferences Window - Modern Settings UI
```
┌──────────────────────────────────────────────┐
│ Preferences                              ✕   │
├──────────────────────────────────────────────┤
│ [General] [Appearance] [Connection] [Advanced]│  <- Segmented control
├──────────────────────────────────────────────┤
│                                               │
│  General Settings                             │
│  ╭───────────────────────────────────────╮   │
│  │ Refresh Interval                      │   │
│  │ ●───────────────○ 5 seconds          │   │  <- Custom slider
│  │                                       │   │
│  │ ☑️ Launch at Login                    │   │  <- Toggle switches
│  │ ☑️ Show Notifications                 │   │
│  │ ☑️ Play Sound Effects                 │   │
│  ╰───────────────────────────────────────╯   │
│                                               │
│  Appearance                                   │
│  ╭───────────────────────────────────────╮   │
│  │ Theme                                 │   │
│  │ ◉ Auto  ○ Light  ○ Dark              │   │  <- Radio buttons
│  │                                       │   │
│  │ Window Opacity                        │   │
│  │ ●─────────────────○ 95%              │   │
│  │                                       │   │
│  │ ☑️ Use Vibrancy Effects               │   │
│  │ ☑️ Animate Transitions                │   │
│  ╰───────────────────────────────────────╯   │
│                                               │
│         [Cancel]  [Save Changes]              │  <- Gradient buttons
└──────────────────────────────────────────────┘
```

### 5.6 Visual Component Library
```swift
// Reusable UI Components

// 1. Glassmorphic Card
struct GlassCard<Content: View>: View {
    let content: Content
    var body: some View {
        content
            .background(.ultraThinMaterial)
            .cornerRadius(12)
            .shadow(color: .black.opacity(0.2), radius: 10, y: 5)
    }
}

// 2. Neon Status Indicator
struct NeonStatusDot: View {
    let isActive: Bool
    var body: some View {
        Circle()
            .fill(isActive ? Color.green : Color.gray)
            .frame(width: 8, height: 8)
            .overlay(
                Circle()
                    .stroke(isActive ? Color.green : Color.clear, lineWidth: 2)
                    .scaleEffect(isActive ? 1.5 : 1)
                    .opacity(isActive ? 0 : 1)
                    .animation(.easeInOut(duration: 1).repeatForever(autoreverses: false))
            )
            .shadow(color: isActive ? .green : .clear, radius: 3)
    }
}

// 3. Gradient Button
struct GradientButton: View {
    let title: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title)
                .foregroundColor(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(
                    LinearGradient(
                        colors: [Color(hex: "00FF88"), Color(hex: "00CCFF")],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
}

// 4. Activity Sparkline
struct Sparkline: View {
    let data: [Double]
    var body: some View {
        GeometryReader { geometry in
            Path { path in
                // Draw sparkline path
            }
            .stroke(
                LinearGradient(
                    colors: [.green, .blue],
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                lineWidth: 2
            )
        }
    }
}

// 5. Animated Progress Bar
struct LiveProgressBar: View {
    let value: Double
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [.green, .mint],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: geometry.size.width * value)
                    .animation(.spring())
            }
            .cornerRadius(4)
        }
        .frame(height: 4)
    }
}
```

### 5.7 Animation Specifications
```swift
// Micro-animations for premium feel
struct CluxAnimations {
    // Status dot pulse
    static let pulse = Animation
        .easeInOut(duration: 1.5)
        .repeatForever(autoreverses: false)
    
    // Card hover
    static let hover = Animation
        .spring(response: 0.3, dampingFraction: 0.7)
    
    // Window transitions
    static let windowSlide = Animation
        .spring(response: 0.4, dampingFraction: 0.8)
    
    // Loading shimmer
    static let shimmer = Animation
        .linear(duration: 1.5)
        .repeatForever(autoreverses: false)
    
    // Success checkmark
    static let success = Animation
        .spring(response: 0.5, dampingFraction: 0.6)
        .delay(0.1)
}
```

### 5.8 Preferences Window

---

## 6. Implementation Task Breakdown

### Phase 1: Foundation (2 hours)
```markdown
1. [ ] Create Xcode project "Clux" with SwiftUI lifecycle
2. [ ] Add menu bar application capability
3. [ ] Implement basic menu bar icon with dropdown
4. [ ] Create data models (TmuxSession, ConnectionProfile)
5. [ ] Set up UserDefaults for settings persistence
6. [ ] Add Swift Package dependencies
```

### Phase 2: SSH & tmux Integration (3 hours)
```markdown
7. [ ] Implement SSHClient class using SwiftNIO SSH
8. [ ] Create TmuxController for command execution
9. [ ] Implement session listing functionality
10. [ ] Add session creation/deletion methods
11. [ ] Implement output capture from sessions
12. [ ] Add error handling for SSH failures
```

### Phase 3: Core UI (3 hours)
```markdown
13. [ ] Build SessionListView with live updates
14. [ ] Create OutputViewer with auto-scroll
15. [ ] Implement CommandInputBar with history
16. [ ] Add SessionInfoHeader with metrics
17. [ ] Create floating HUD window
18. [ ] Implement window show/hide animations
```

### Phase 4: Session Management (2 hours)
```markdown
19. [ ] Add "New Session" dialog
20. [ ] Implement session kill confirmation
21. [ ] Add "Send Command" functionality
22. [ ] Create session refresh timer
23. [ ] Implement session state monitoring
24. [ ] Add connection status indicator
```

### Phase 5: Polish & Preferences (2 hours)
```markdown
25. [ ] Create Preferences window UI
26. [ ] Implement settings persistence
27. [ ] Add keyboard shortcuts
28. [ ] Implement launch at login
29. [ ] Add app icon and assets
30. [ ] Create about window
```

### Phase 6: Testing & Packaging (2 hours)
```markdown
31. [ ] Test with local tmux sessions
32. [ ] Test with Tailscale connections
33. [ ] Handle edge cases (no sessions, SSH timeout)
34. [ ] Memory leak testing
35. [ ] Create DMG installer
36. [ ] Write basic documentation
```

---

## 7. File Structure

```
Clux/
├── Clux.xcodeproj
├── Clux/
│   ├── CluxApp.swift                 # App entry point
│   ├── Info.plist
│   ├── Assets.xcassets/
│   │   └── AppIcon.appiconset/
│   ├── Models/
│   │   ├── TmuxSession.swift
│   │   ├── ConnectionProfile.swift
│   │   └── AppSettings.swift
│   ├── Views/
│   │   ├── MenuBarView.swift
│   │   ├── MainWindow.swift
│   │   ├── SessionListView.swift
│   │   ├── OutputViewer.swift
│   │   ├── CommandInputBar.swift
│   │   └── PreferencesView.swift
│   ├── Controllers/
│   │   ├── SSHClient.swift
│   │   ├── TmuxController.swift
│   │   └── SessionManager.swift
│   ├── Utilities/
│   │   ├── KeychainHelper.swift
│   │   └── NotificationManager.swift
│   └── Resources/
│       └── default_settings.json
└── README.md
```

---

## 8. Key Implementation Details

### 8.1 SSH Connection
```swift
// SSHClient.swift - Core connection logic
class SSHClient {
    func connect(to host: String, port: Int = 22, username: String) async throws
    func executeCommand(_ command: String) async throws -> String
    func disconnect()
}
```

### 8.2 tmux Command Execution
```swift
// TmuxController.swift - tmux specific commands
class TmuxController {
    func listSessions() async throws -> [TmuxSession]
    func createSession(name: String) async throws
    func killSession(name: String) async throws
    func sendCommand(to session: String, command: String) async throws
    func captureOutput(from session: String, lines: Int = 100) async throws -> String
}
```

### 8.3 Menu Bar Integration
```swift
// MenuBarView.swift - Menu bar UI
struct MenuBarView: View {
    @StateObject var sessionManager: SessionManager
    
    var body: some View {
        // Menu implementation
    }
}
```

---

## 9. Testing Checklist

### Functional Tests
- [ ] Create new tmux session
- [ ] List existing sessions
- [ ] Send command to session
- [ ] Kill session with confirmation
- [ ] Capture session output
- [ ] Connect via Tailscale
- [ ] Handle SSH timeout gracefully
- [ ] Persist settings across launches

### Performance Tests
- [ ] CPU usage <2% when idle
- [ ] Memory usage <50MB baseline
- [ ] Refresh cycle completes in <500ms
- [ ] No memory leaks over 1 hour

### UI Tests
- [ ] Menu bar icon updates correctly
- [ ] HUD window shows/hides properly
- [ ] Keyboard shortcuts work
- [ ] Preferences save correctly

---

## 10. Success Criteria

### Day 1 Deliverables
1. **Functional menu bar app** that shows session status
2. **Working SSH/tmux integration** for local and Tailscale
3. **Basic HUD** with session list and output viewer
4. **Core session management** (create, list, kill, send command)
5. **Preferences** for connection and refresh settings
6. **Packaged DMG** ready for distribution

### Performance Metrics
- Launch time: <2 seconds
- Session refresh: <500ms
- Memory footprint: <50MB idle
- CPU usage: <2% idle

---

## 11. Future Enhancements (Post-MVP)

- Session recording and playback
- Multiple host management
- Session templates and presets
- Output search and filtering
- Regex-based notifications
- CloudKit sync for settings
- iOS companion app
- Session sharing via secure links
- Metrics dashboard with graphs
- Plugin system for extensions

---

## 12. Development Commands

```bash
# Build and run
xcodebuild -scheme Clux build
open build/Release/Clux.app

# Create DMG
create-dmg \
  --volname "Clux Installer" \
  --window-size 500 300 \
  --icon "Clux.app" 100 100 \
  --app-drop-link 400 100 \
  "Clux-1.0.0.dmg" \
  "build/Release/"

# Test SSH connection
ssh localhost "tmux list-sessions"

# Test tmux commands
tmux new-session -d -s test-session
tmux send-keys -t test-session "echo 'Hello from Clux'" Enter
tmux capture-pane -t test-session -p
```

---

## 13. Resources & References

- [SwiftUI Menu Bar Apps](https://developer.apple.com/documentation/swiftui/menu-bar-apps)
- [SwiftNIO SSH](https://github.com/apple/swift-nio-ssh)
- [tmux Control Mode](https://github.com/tmux/tmux/wiki/Control-Mode)
- [Tailscale API](https://tailscale.com/api)
- [macOS Keychain Services](https://developer.apple.com/documentation/security/keychain_services)

---

**Document Status:** Ready for Implementation  
**Estimated Build Time:** 14 hours  
**Developer Requirements:** Swift/SwiftUI experience, familiarity with SSH/tmux