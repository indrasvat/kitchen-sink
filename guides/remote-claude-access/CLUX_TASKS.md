# Clux Implementation Task List
## Day 1 Build Schedule - 14 Hours Total

### 🎯 Hour 1-2: Foundation Setup + UI Libraries
```bash
# Terminal 1: Project Setup
mkdir Clux && cd Clux
xcodebuild -create-project Clux -language Swift -type app

# Terminal 2: Git Setup  
git init
echo ".DS_Store\n*.xcuserdata\nbuild/" > .gitignore
git add . && git commit -m "Initial Clux project"
```

**Tasks:**
- [ ] 001. Create new Xcode project named "Clux" with SwiftUI App lifecycle
- [ ] 002. Set minimum deployment target to macOS 13.0
- [ ] 003. Enable "Menu Bar App" in project settings
- [ ] 004. Add app sandbox entitlements with network client permission
- [ ] 005. Add Swift Package Manager dependencies:
  - SwiftNIO SSH
  - KeyboardShortcuts
  - LaunchAtLogin
  - Highlightr (syntax highlighting)
  - Sparkle (auto-updates)
- [ ] 006. Create design system file (CluxDesign.swift) with colors and animations
- [ ] 007. Design app icon in Figma/Sketch (terminal + neon green dot)
- [ ] 008. Export icon assets in all required sizes to Assets.xcassets
- [ ] 009. Implement CluxApp.swift with MenuBarExtra and WindowGroup

### 🔧 Hour 3-4: Data Models & Design System
**Tasks:**
- [ ] 010. Create Models/ folder and TmuxSession.swift model
- [ ] 011. Create ConnectionProfile.swift with Codable support
- [ ] 012. Create AppSettings.swift with UserDefaults integration
- [ ] 013. Implement SessionManager.swift as ObservableObject
- [ ] 014. Add SessionState enum (active, inactive, error)
- [ ] 015. Create mock data for testing without SSH
- [ ] 016. Create UI/Components folder for reusable views
- [ ] 017. Implement GlassCard.swift with vibrancy effect
- [ ] 018. Create NeonStatusDot.swift with pulse animation
- [ ] 019. Build GradientButton.swift with hover effects
- [ ] 020. Add Sparkline.swift for activity visualization

### 🌐 Hour 5-7: SSH & tmux Integration
**Tasks:**
- [ ] 021. Create Controllers/SSHClient.swift with async/await
- [ ] 022. Implement SSH connection with timeout handling
- [ ] 023. Create TmuxController.swift with command builders
- [ ] 024. Implement listSessions() with output parsing
- [ ] 025. Implement createSession() and killSession()
- [ ] 026. Add captureOutput() for session monitoring
- [ ] 027. Create error handling for network failures
- [ ] 028. Add connection retry logic with exponential backoff
- [ ] 029. Implement Tailscale detection and auto-configuration
- [ ] 030. Create session health monitoring system

### 🎨 Hour 8-10: Premium UI Implementation
**Tasks:**
- [ ] 031. Create Views/ folder structure
- [ ] 032. Implement MenuBarView.swift with animated status icon
- [ ] 033. Create dropdown menu with glassmorphic background
- [ ] 034. Build MainWindow.swift with vibrancy and shadows
- [ ] 035. Implement SessionListView.swift with card-based layout
- [ ] 036. Add session cards with gradient progress bars
- [ ] 037. Create OutputViewer.swift with syntax highlighting (Highlightr)
- [ ] 038. Add CommandInputBar.swift with floating design
- [ ] 039. Implement smooth spring animations for all transitions
- [ ] 040. Add hover effects and micro-interactions
- [ ] 041. Create loading states with shimmer effects
- [ ] 042. Implement dark/light/auto theme switching
- [ ] 043. Add window blur and vibrancy effects
- [ ] 044. Create custom window controls (traffic lights style)

### 📋 Hour 11-12: Session Management & Polish
**Tasks:**
- [ ] 045. Add "New Session" sheet with animated modal
- [ ] 046. Implement session deletion with confirmation alert
- [ ] 047. Add send command functionality with history
- [ ] 048. Create Timer for automatic refresh with visual indicator
- [ ] 049. Implement connection status with animated pulse
- [ ] 050. Add error recovery with toast notifications
- [ ] 051. Create session activity sparklines
- [ ] 052. Add CPU/memory usage monitoring
- [ ] 053. Implement notification system with custom alerts
- [ ] 054. Add sound effects for actions (optional toggle)

### ⚙️ Hour 13: Preferences & Advanced Features
**Tasks:**
- [ ] 055. Create PreferencesView.swift with segmented control
- [ ] 056. Design General tab with custom sliders and toggles
- [ ] 057. Add Appearance tab with theme preview
- [ ] 058. Add Connection tab with profile management
- [ ] 059. Implement settings persistence to UserDefaults
- [ ] 060. Add keyboard shortcuts with KeyboardShortcuts library
- [ ] 061. Implement launch at login with LaunchAtLogin
- [ ] 062. Add Sparkle framework for auto-updates
- [ ] 063. Create about window with app info and credits
- [ ] 064. Add export/import settings functionality

### 🧪 Hour 14: Testing & Packaging
**Tasks:**
- [ ] 065. Test with local tmux sessions
- [ ] 066. Test with Tailscale remote connections
- [ ] 067. Test all animations and transitions
- [ ] 068. Verify syntax highlighting works correctly
- [ ] 069. Test error handling (no tmux, SSH failure)
- [ ] 070. Check memory usage with Instruments
- [ ] 071. Profile CPU usage during animations
- [ ] 072. Build Release configuration with optimizations
- [ ] 073. Code sign with Developer ID
- [ ] 074. Create DMG with custom background image
- [ ] 075. Test auto-update functionality
- [ ] 076. Write README.md with screenshots and GIFs

---

## 🚀 Quick Implementation Scripts

### Create Premium UI Components
```bash
#!/bin/bash
# create_ui_components.sh

mkdir -p Clux/UI/{Components,Effects,Animations}

# Create design system
cat > Clux/UI/CluxDesign.swift << 'EOF'
import SwiftUI

struct CluxDesign {
    // Neon Colors
    static let neonGreen = Color(hex: "00FF88")
    static let neonBlue = Color(hex: "00CCFF")
    static let neonAmber = Color(hex: "FFB800")
    static let neonRed = Color(hex: "FF3B30")
    
    // Background Colors
    static let bgPrimary = Color(hex: "1C1C1E")
    static let bgSecondary = Color(hex: "2C2C2E")
    static let bgTertiary = Color(hex: "3A3A3C")
    
    // Effects
    static let glassEffect = Material.ultraThin
    static let shadowRadius: CGFloat = 20
    static let cornerRadius: CGFloat = 12
    
    // Animations
    static let springAnimation = Animation.spring(response: 0.3, dampingFraction: 0.7)
    static let pulseAnimation = Animation.easeInOut(duration: 1.5).repeatForever()
}
EOF

# Create glass card component
cat > Clux/UI/Components/GlassCard.swift << 'EOF'
import SwiftUI

struct GlassCard<Content: View>: View {
    let content: () -> Content
    @State private var isHovered = false
    
    var body: some View {
        content()
            .padding()
            .background(.ultraThinMaterial)
            .cornerRadius(CluxDesign.cornerRadius)
            .shadow(
                color: .black.opacity(isHovered ? 0.3 : 0.2),
                radius: isHovered ? 15 : 10,
                y: isHovered ? 8 : 5
            )
            .scaleEffect(isHovered ? 1.02 : 1.0)
            .onHover { hovering in
                withAnimation(CluxDesign.springAnimation) {
                    isHovered = hovering
                }
            }
    }
}
EOF

# Create neon status dot
cat > Clux/UI/Components/NeonStatusDot.swift << 'EOF'
import SwiftUI

struct NeonStatusDot: View {
    let isActive: Bool
    @State private var isPulsing = false
    
    var body: some View {
        ZStack {
            Circle()
                .fill(isActive ? CluxDesign.neonGreen : Color.gray)
                .frame(width: 8, height: 8)
            
            if isActive {
                Circle()
                    .stroke(CluxDesign.neonGreen, lineWidth: 2)
                    .frame(width: 8, height: 8)
                    .scaleEffect(isPulsing ? 2.0 : 1.0)
                    .opacity(isPulsing ? 0 : 0.5)
                    .onAppear {
                        withAnimation(CluxDesign.pulseAnimation) {
                            isPulsing = true
                        }
                    }
            }
        }
        .shadow(color: isActive ? CluxDesign.neonGreen : .clear, radius: 3)
    }
}
EOF

echo "✅ Premium UI components created"
```

### Create All Files at Once
```bash
#!/bin/bash
# create_structure.sh

mkdir -p Clux/{Models,Views,Controllers,Utilities,Resources}

# Create model files
cat > Clux/Models/TmuxSession.swift << 'EOF'
import Foundation

struct TmuxSession: Identifiable, Codable {
    let id: String
    var created: Date
    var isAttached: Bool
    var runtime: TimeInterval
    var lastActivity: Date
    var outputBuffer: [String] = []
}
EOF

cat > Clux/Models/ConnectionProfile.swift << 'EOF'
import Foundation

struct ConnectionProfile: Codable {
    let id = UUID()
    var name: String
    var host: String
    var port: Int = 22
    var username: String
}
EOF

cat > Clux/Models/AppSettings.swift << 'EOF'
import Foundation

class AppSettings: ObservableObject {
    @Published var refreshInterval: TimeInterval = 5.0
    @Published var maxOutputLines: Int = 100
    @Published var launchAtLogin: Bool = false
}
EOF

echo "✅ File structure created"
```

### Test tmux Commands
```bash
#!/bin/bash
# test_tmux.sh

# Create test session
tmux new-session -d -s clux-test -n main "echo 'Clux Test Session'; bash"

# List sessions
echo "Sessions:"
tmux list-sessions -F "#{session_name}:#{session_created}:#{session_attached}"

# Capture output
echo "Output:"
tmux capture-pane -t clux-test -p

# Clean up
tmux kill-session -t clux-test
```

---

## 📝 Critical Implementation Notes

### Menu Bar Setup with Animations (CluxApp.swift)
```swift
import SwiftUI
import Sparkle

@main
struct CluxApp: App {
    @StateObject private var sessionManager = SessionManager()
    @State private var isMenuBarIconAnimating = false
    private let updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    
    var body: some Scene {
        MenuBarExtra {
            MenuBarView(sessionManager: sessionManager)
                .frame(width: 280)
                .background(.ultraThinMaterial)
                .cornerRadius(12)
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "terminal")
                    .symbolEffect(.pulse, value: isMenuBarIconAnimating)
                NeonStatusDot(isActive: sessionManager.hasActiveSessions)
            }
        }
        .menuBarExtraStyle(.window)
        
        Window("Clux", id: "main") {
            MainWindow(sessionManager: sessionManager)
                .preferredColorScheme(.dark)
                .background(CluxDesign.bgPrimary)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 450, height: 600)
        
        Settings {
            PreferencesView()
                .environmentObject(sessionManager)
        }
    }
}
```

### Premium Session Card Component
```swift
// SessionCard.swift - Glassmorphic session card
struct SessionCard: View {
    let session: TmuxSession
    @State private var isHovered = false
    
    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                // Header
                HStack {
                    NeonStatusDot(isActive: session.isRunning)
                    Text(session.name)
                        .font(.system(.body, design: .monospaced))
                        .fontWeight(.semibold)
                    Spacer()
                    Text(session.formattedRuntime)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                // CPU Progress Bar
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("CPU")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("\(Int(session.cpuUsage))%")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Rectangle()
                                .fill(Color.gray.opacity(0.2))
                                .frame(height: 4)
                            
                            Rectangle()
                                .fill(
                                    LinearGradient(
                                        colors: [CluxDesign.neonGreen, CluxDesign.neonBlue],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: geometry.size.width * (session.cpuUsage / 100), height: 4)
                                .animation(.spring(), value: session.cpuUsage)
                        }
                        .cornerRadius(2)
                    }
                    .frame(height: 4)
                }
                
                // Stats
                HStack(spacing: 12) {
                    Label("\(session.lineCount) lines", systemImage: "doc.text")
                    Label(session.lastActivityTime, systemImage: "clock")
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
            .padding()
        }
        .overlay(
            RoundedRectangle(cornerRadius: CluxDesign.cornerRadius)
                .stroke(
                    LinearGradient(
                        colors: isHovered ? [CluxDesign.neonGreen.opacity(0.5), CluxDesign.neonBlue.opacity(0.5)] : [Color.clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 2
                )
        )
        .onHover { hovering in
            withAnimation(.spring(response: 0.3)) {
                isHovered = hovering
            }
        }
    }
}
```

### SSH Connection Pattern
```swift
// Use Process instead of SwiftNIO for Day 1 simplicity
func executeSSHCommand(_ command: String) async throws -> String {
    let task = Process()
    task.launchPath = "/usr/bin/ssh"
    task.arguments = [host, command]
    
    let pipe = Pipe()
    task.standardOutput = pipe
    
    try task.run()
    task.waitUntilExit()
    
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    return String(data: data, encoding: .utf8) ?? ""
}
```

### tmux Command Examples
```swift
// Commands to implement
let commands = [
    "tmux list-sessions -F '#{session_name}|#{session_created}'",
    "tmux new-session -d -s \(name) 'claude code'",
    "tmux kill-session -t \(name)",
    "tmux send-keys -t \(session) '\(command)' Enter",
    "tmux capture-pane -t \(session) -p -S -100"
]
```

---

## ✅ Definition of Done

1. **Menu bar icon** animates with pulse effect and changes color based on session status
2. **Dropdown menu** shows glassmorphic session cards with live CPU usage
3. **HUD window** has vibrancy effects and smooth animations
4. **Session cards** display with gradient borders and hover effects
5. **Output viewer** has syntax highlighting for code
6. **Commands** can be sent with floating input bar
7. **Settings** persist with beautiful preferences UI
8. **Animations** are smooth and responsive (60fps)
9. **Auto-updates** work via Sparkle framework
10. **App runs** without crashes for 30 minutes
11. **DMG installer** has custom background and drag-to-install
12. **Screenshots** showcase the premium UI design

---

## 🎯 Success Metrics

- **Build Time:** ≤14 hours
- **App Size:** <15MB (with UI libraries)
- **Memory Usage:** <50MB idle, <80MB with animations
- **CPU Usage:** <2% idle, <5% during animations
- **Startup Time:** <2 seconds
- **Refresh Latency:** <500ms
- **Animation FPS:** 60fps minimum
- **UI Responsiveness:** <100ms for interactions

---

## 🎨 Visual Polish Checklist

- [ ] App icon with neon green accent
- [ ] Menu bar icon with animated pulse
- [ ] Glassmorphic cards with blur
- [ ] Gradient buttons and borders
- [ ] Smooth spring animations
- [ ] Hover effects on all interactive elements
- [ ] Loading shimmers for async operations
- [ ] Success/error toast notifications
- [ ] Syntax highlighting in output
- [ ] Dark mode optimized design

---

**Ready to Build!** An AI agent can use this enhanced task list to build a premium-looking Clux app with beautiful animations and modern UI design.