#!/usr/bin/env bash

set -o pipefail

# ============================================================================
# TOOL CONFIGURATION - Add new AI CLI tools here
# ============================================================================
# Format: ["command_name"]="package_manager:package_name"
# 
# Supported package managers: npm, bun, brew
# 
# To add a new tool:
# 1. Find the actual CLI command you run in the shell (may differ from the package name).
#    Verify it exists with `which command` and check its version output.
# 2. Find the package manager and package name from the tool's documentation.
# 3. Add a new line: ["command_name"]="package_manager:package_name"
# 4. If the tool prints a non-standard version string, add a custom case in get_version().
# 
# Examples:
#   ["newtool"]="npm:@company/newtool"       # npm package
#   ["anothertool"]="bun:anothertool"        # bun package  
#   ["brewtool"]="brew:brewtool"             # homebrew package
# ============================================================================

declare -A TOOLS=(
    ["claude"]="npm:@anthropic-ai/claude-code"
    ["codex"]="npm:@openai/codex"
    ["gemini"]="npm:@google/gemini-cli"
    ["amp"]="npm:@sourcegraph/amp"
    ["opencode"]="bun:opencode-ai"
    ["happy"]="npm:happy-coder"
    ["copilot"]="npm:@github/copilot"
    ["jules"]="npm:@google/jules"
)

# ============================================================================
# SCRIPT INTERNALS - Don't modify below this line unless you know what you're doing
# ============================================================================

# Global variables
VERBOSE=false

# Color definitions
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly PURPLE='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly BOLD='\033[1m'
readonly DIM='\033[2m'
readonly NC='\033[0m' # No Color

# Icons
readonly CHECK="✓"
readonly CROSS="✗"
readonly ARROW="→"
readonly SPARKLE="✨"
readonly WRENCH="🔧"

# Logging functions
log_verbose() {
    if [[ "$VERBOSE" == "true" ]]; then
        echo -e "${DIM}[VERBOSE]${NC} $*" >&2
    fi
}

log_debug() {
    if [[ "$VERBOSE" == "true" ]]; then
        echo -e "${DIM}[DEBUG]${NC} $*" >&2
    fi
}

print_header() {
    echo -e "${BOLD}${CYAN}  █████╗ ██╗ ${YELLOW}    //${NC}"
    echo -e "${BOLD}${CYAN} ██╔══██╗██║ ${YELLOW}   //${NC}"
    echo -e "${BOLD}${CYAN} ███████║██║ ${YELLOW}  //___${NC}"
    echo -e "${BOLD}${CYAN} ██╔══██║██║ ${YELLOW} /____/${NC}"
    echo -e "${BOLD}${CYAN} ██║  ██║██║ ${YELLOW}    //${NC}"
    echo -e "${BOLD}${CYAN} ╚═╝  ╚═╝╚═╝ ${YELLOW}   //${NC}"
    echo
    echo -e "${BOLD}${CYAN}${SPARKLE} AI CLI Tools Install & Upgrade Manager${NC}"
    echo -e "${DIM}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo
}

show_help() {
    print_header
    cat << 'EOF'
USAGE:
  upgrade-ai [OPTIONS]

DESCRIPTION:
  Automatically installs and upgrades all your AI CLI tools to their latest versions.
  If a tool is not installed, it will be installed automatically. If it's already 
  installed, it will be upgraded to the latest version. Shows current versions, 
  performs installations/upgrades, and displays results with beautiful colored output.

  Currently supported tools:
  • claude     (Claude Code - @anthropic-ai/claude-code)
  • codex      (OpenAI Codex - @openai/codex)
  • gemini     (Google Gemini CLI - @google/gemini-cli)
  • amp        (Sourcegraph Amp - @sourcegraph/amp)
  • opencode   (OpenCode AI - opencode-ai via bun)
  • happy      (Happy Coder CLI - happy-coder via npm)
  • copilot    (GitHub Copilot CLI - @github/copilot via npm)
  • jules      (Google Jules - @google/jules via npm)

OPTIONS:
  -h, --help       Show this help message and exit
  -v, --verbose    Enable verbose logging for debugging

EXAMPLES:
  upgrade-ai                # Install/upgrade all AI CLI tools
  upgrade-ai --help         # Show this help
  upgrade-ai --verbose      # Install/upgrade with detailed debug output

HOW TO ADD NEW TOOLS:
  
  1. Find the command name (what you type to run the tool)
  2. Find the package manager and package name from tool's docs
  3. Edit this script and add to the TOOLS array (around line 23-29):
     
     ["command_name"]="package_manager:package_name"
  
  Examples:
    ["cursor"]="npm:@cursor/cli"           # npm package
    ["aider"]="bun:aider-chat"             # bun package  
    ["continue"]="brew:continue-dev"       # homebrew package

SUPPORTED PACKAGE MANAGERS:
  • npm      Uses 'npm install -g <package>' or 'npm upgrade -g <package>'
  • bun      Uses 'bun install -g <package>' (works for both install and upgrade)
  • brew     Uses 'brew install <package>' or 'brew upgrade <package>'

TROUBLESHOOTING:
  • Tool not found? It will be installed automatically if configured
  • Version detection fails? Tool might use non-standard --version format
  • Install/upgrade fails? Check package name in the tool's documentation
  • Permission errors? You might need to run with appropriate permissions

SCRIPT LOCATION:
  ~/.local/bin/upgrade-ai -> ~/shell-scripts/upgrade-ai-cli.sh

For more details, see the comments at the end of the script file.
EOF
}

print_tool_header() {
    local tool="$1"
    echo -e "${BOLD}${BLUE}${WRENCH} $tool${NC}"
}

get_version() {
    local cmd="$1"
    local version=""
    
    log_debug "Checking if command '$cmd' is available"
    if ! command -v "$cmd" >/dev/null 2>&1; then
        log_debug "Command '$cmd' not found in PATH"
        echo ""
        return
    fi
    
    log_debug "Getting version for '$cmd'"
    
    case "$cmd" in
        "claude")
            # Output: "1.0.48 (Claude Code)"
            version=$($cmd --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
            ;;
        "codex")
            # Output: "codex-cli 0.7.0"
            version=$($cmd --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)*' | head -1)
            ;;
        "gemini")
            # Output: "0.1.12"
            version=$($cmd --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)*' | head -1)
            ;;
        "amp")
            # Output: "0.0.1752523513-gda9fd7 (released 2025-07-14T20:10:21.481Z)"
            version=$($cmd --version 2>/dev/null | grep -oE '^[0-9]+\.[0-9]+\.[0-9]+[^[:space:]]*' | head -1)
            ;;
        "opencode")
            # Output: "0.2.15"
            version=$($cmd --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
            ;;
        "happy")
            # Output: "happy version: 0.11.0" along with aggregated tool versions
            version=$($cmd --version 2>/dev/null | awk -F'version: ' '/^happy version:/ {print $2; exit}')
            version=${version%% *}
            if [[ -z "$version" ]]; then
                version=$($cmd version 2>/dev/null | awk -F'version: ' '/^happy version:/ {print $2; exit}')
                version=${version%% *}
            fi
            ;;
        "jules")
            # Output: "Version: v0.1.40"
            version=$($cmd version 2>/dev/null | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | head -1)
            version=${version#v}
            ;;
        "copilot")
            # Output: "0.0.327\nCommit: 0cbec74"
            version=$($cmd --version 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
            ;;
        *)
            # Fallback for unknown tools
            version=$($cmd --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)*' | head -1)
            ;;
    esac
    
    log_debug "Extracted version for '$cmd': '${version:-unknown}'"
    echo "${version:-unknown}"
}

print_version_info() {
    local tool="$1"
    local version="$2"
    local status="$3"
    
    case "$status" in
        "current")
            echo -e "  ${DIM}Current:${NC} ${GREEN}$version${NC}"
            ;;
        "old")
            echo -e "  ${DIM}Current:${NC} ${YELLOW}$version${NC}"
            ;;
        "not_found")
            echo -e "  ${DIM}Status:${NC} ${RED}Not installed${NC}"
            ;;
    esac
}

upgrade_npm_package() {
    local package="$1"
    local is_installed="$2"
    
    if [[ "$is_installed" == "false" ]]; then
        echo -e "  ${DIM}Installing via npm...${NC}"
        log_verbose "Running: npm install -g $package"
        local npm_output
        if npm_output=$(npm install -g "$package" 2>&1); then
            log_verbose "npm install successful for $package"
            log_debug "npm output: $npm_output"
            return 0
        else
            log_verbose "npm install failed for $package"
            echo -e "  ${RED}${CROSS} npm install failed${NC}" >&2
            echo -e "  ${DIM}Error: ${npm_output}${NC}" >&2
            return 1
        fi
    else
        echo -e "  ${DIM}Upgrading via npm...${NC}"
        log_verbose "Running: npm upgrade -g $package"
        local npm_output
        if npm_output=$(npm upgrade -g "$package" 2>&1); then
            log_verbose "npm upgrade successful for $package"
            log_debug "npm output: $npm_output"
            return 0
        else
            log_verbose "npm upgrade failed for $package"
            echo -e "  ${RED}${CROSS} npm upgrade failed${NC}" >&2
            echo -e "  ${DIM}Error: ${npm_output}${NC}" >&2
            return 1
        fi
    fi
}

upgrade_bun_package() {
    local package="$1"
    local is_installed="$2"
    
    # Note: bun install -g works for both install and upgrade
    if [[ "$is_installed" == "false" ]]; then
        echo -e "  ${DIM}Installing via bun...${NC}"
        log_verbose "Running: bun install -g $package"
    else
        echo -e "  ${DIM}Upgrading via bun...${NC}"
        log_verbose "Running: bun install -g $package (bun uses install for both install and upgrade)"
    fi
    
    local bun_output
    if bun_output=$(bun install -g "$package" 2>&1); then
        if [[ "$is_installed" == "false" ]]; then
            log_verbose "bun install successful for $package"
        else
            log_verbose "bun upgrade successful for $package"
        fi
        log_debug "bun output: $bun_output"
        return 0
    else
        if [[ "$is_installed" == "false" ]]; then
            log_verbose "bun install failed for $package"
            echo -e "  ${RED}${CROSS} bun install failed${NC}" >&2
        else
            log_verbose "bun upgrade failed for $package"
            echo -e "  ${RED}${CROSS} bun upgrade failed${NC}" >&2
        fi
        echo -e "  ${DIM}Error: ${bun_output}${NC}" >&2
        return 1
    fi
}

upgrade_brew_package() {
    local package="$1"
    local is_installed="$2"
    
    if [[ "$is_installed" == "false" ]]; then
        echo -e "  ${DIM}Installing via brew...${NC}"
        log_verbose "Running: brew install $package"
        local brew_output
        if brew_output=$(brew install "$package" 2>&1); then
            log_verbose "brew install successful for $package"
            log_debug "brew output: $brew_output"
            return 0
        else
            log_verbose "brew install failed for $package"
            echo -e "  ${RED}${CROSS} brew install failed${NC}" >&2
            echo -e "  ${DIM}Error: ${brew_output}${NC}" >&2
            return 1
        fi
    else
        echo -e "  ${DIM}Upgrading via brew...${NC}"
        log_verbose "Running: brew upgrade $package"
        local brew_output
        if brew_output=$(brew upgrade "$package" 2>&1); then
            log_verbose "brew upgrade successful for $package"
            log_debug "brew output: $brew_output"
            return 0
        else
            log_verbose "brew upgrade failed for $package"
            echo -e "  ${RED}${CROSS} brew upgrade failed${NC}" >&2
            echo -e "  ${DIM}Error: ${brew_output}${NC}" >&2
            return 1
        fi
    fi
}

upgrade_tool() {
    local tool="$1"
    local is_installed="$2"
    local manager_info="${TOOLS[$tool]}"
    local manager="${manager_info%%:*}"
    local package="${manager_info##*:}"
    
    log_debug "Upgrading $tool using $manager package manager (package: $package), installed: $is_installed"
    
    case "$manager" in
        "npm")
            upgrade_npm_package "$package" "$is_installed"
            ;;
        "bun")
            upgrade_bun_package "$package" "$is_installed"
            ;;
        "brew")
            upgrade_brew_package "$package" "$is_installed"
            ;;
        *)
            echo -e "  ${RED}${CROSS} Unknown package manager: $manager${NC}" >&2
            return 1
            ;;
    esac
}

print_result() {
    local tool="$1"
    local old_version="$2"
    local new_version="$3"
    local success="$4"
    
    if [[ "$success" == "true" ]]; then
        if [[ "$old_version" != "$new_version" && -n "$new_version" && "$new_version" != "unknown" ]]; then
            echo -e "  ${GREEN}${CHECK} Upgraded${NC} ${DIM}$old_version${NC} ${ARROW} ${GREEN}$new_version${NC}"
        else
            echo -e "  ${GREEN}${CHECK} Already up to date${NC} ${DIM}($old_version)${NC}"
        fi
    else
        echo -e "  ${RED}${CROSS} Upgrade failed${NC}"
    fi
    echo
}

main() {
    print_header
    
    local total_tools=${#TOOLS[@]}
    local upgraded_count=0
    local installed_count=0
    local failed_count=0
    local uptodate_count=0
    
    # Arrays to track results
    local -a upgraded_tools=()
    local -a installed_tools=()
    local -a failed_tools=()
    local -a uptodate_tools=()
    
    log_verbose "Starting install/upgrade process for $total_tools configured tools"
    log_debug "Configured tools: ${!TOOLS[*]}"
    
    for tool in "${!TOOLS[@]}"; do
        log_verbose "Processing tool: $tool"
        print_tool_header "$tool"
        
        # Check if tool is installed
        local is_installed="true"
        if ! command -v "$tool" >/dev/null 2>&1; then
            log_verbose "Tool '$tool' not found in PATH, will attempt to install"
            print_version_info "$tool" "" "not_found"
            is_installed="false"
        else
            # Get current version
            log_verbose "Getting current version for $tool"
            old_version=$(get_version "$tool")
            log_verbose "Current version of $tool: $old_version"
            print_version_info "$tool" "$old_version" "old"
        fi
        
        # Install or Upgrade
        if [[ "$is_installed" == "false" ]]; then
            log_verbose "Starting installation for $tool"
        else
            log_verbose "Starting upgrade for $tool"
        fi
        
        if upgrade_tool "$tool" "$is_installed"; then
            if [[ "$is_installed" == "false" ]]; then
                log_verbose "Installation completed for $tool, checking new version"
                # Get new version after installation
                sleep 1
                new_version=$(get_version "$tool")
                log_verbose "Installed version of $tool: $new_version"
                echo -e "  ${GREEN}${CHECK} Installed${NC} ${GREEN}$new_version${NC}"
                installed_tools+=("$tool ($new_version)")
                ((installed_count++))
            else
                log_verbose "Upgrade completed for $tool, checking new version"
                # Get new version (with a brief pause to ensure version updates)
                sleep 1
                new_version=$(get_version "$tool")
                log_verbose "New version of $tool: $new_version"
                print_result "$tool" "$old_version" "$new_version" "true"
                
                # Track if actually upgraded or already up to date
                if [[ "$old_version" != "$new_version" && -n "$new_version" && "$new_version" != "unknown" ]]; then
                    upgraded_tools+=("$tool ($old_version → $new_version)")
                    ((upgraded_count++))
                else
                    uptodate_tools+=("$tool ($old_version)")
                    ((uptodate_count++))
                fi
            fi
        else
            if [[ "$is_installed" == "false" ]]; then
                log_verbose "Installation failed for $tool"
                echo -e "  ${RED}${CROSS} Installation failed${NC}"
            else
                log_verbose "Upgrade failed for $tool"
                print_result "$tool" "$old_version" "" "false"
            fi
            failed_tools+=("$tool")
            ((failed_count++))
        fi
        echo
        log_verbose "Finished processing $tool"
    done
    
    # Detailed Summary Report
    echo -e "${BOLD}${CYAN}Summary Report${NC}"
    echo -e "${DIM}━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}Total tools configured: $total_tools${NC}"
    echo
    
    # Show newly installed tools
    if [[ $installed_count -gt 0 ]]; then
        echo -e "${BOLD}${GREEN}${CHECK} Newly installed ($installed_count):${NC}"
        for tool_info in "${installed_tools[@]}"; do
            echo -e "  ${GREEN}•${NC} $tool_info"
        done
        echo
    fi
    
    # Show upgraded tools
    if [[ $upgraded_count -gt 0 ]]; then
        echo -e "${BOLD}${GREEN}${CHECK} Upgraded ($upgraded_count):${NC}"
        for tool_info in "${upgraded_tools[@]}"; do
            echo -e "  ${GREEN}•${NC} $tool_info"
        done
        echo
    fi
    
    # Show up-to-date tools
    if [[ $uptodate_count -gt 0 ]]; then
        echo -e "${BOLD}${GREEN}${CHECK} Already up to date ($uptodate_count):${NC}"
        for tool_info in "${uptodate_tools[@]}"; do
            echo -e "  ${GREEN}•${NC} $tool_info"
        done
        echo
    fi
    
    # Show failed tools
    if [[ $failed_count -gt 0 ]]; then
        echo -e "${BOLD}${RED}${CROSS} Failed ($failed_count):${NC}"
        for tool in "${failed_tools[@]}"; do
            echo -e "  ${RED}•${NC} $tool"
        done
        echo
    fi
    
    # Final status
    if [[ $failed_count -gt 0 ]]; then
        echo -e "${RED}${CROSS} ${BOLD}Completed with errors${NC} - $failed_count tool(s) failed"
        log_verbose "Script completed with $failed_count failures"
        exit 1
    else
        echo -e "${SPARKLE} ${BOLD}All done successfully!${NC}"
        local success_message=""
        if [[ $installed_count -gt 0 && $upgraded_count -gt 0 ]]; then
            success_message="$installed_count tool(s) installed, $upgraded_count upgraded, $uptodate_count already up to date"
        elif [[ $installed_count -gt 0 ]]; then
            success_message="$installed_count tool(s) installed, $uptodate_count already up to date"
        elif [[ $upgraded_count -gt 0 ]]; then
            success_message="$upgraded_count tool(s) upgraded, $uptodate_count already up to date"
        else
            success_message="All $uptodate_count tool(s) were already up to date"
        fi
        echo -e "${DIM}$success_message${NC}"
        log_verbose "Script completed successfully"
        exit 0
    fi
}

# Handle script interruption gracefully
trap 'echo -e "\n${YELLOW}⚠ Install/upgrade interrupted${NC}"; exit 130' INT TERM

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -v|--verbose)
                VERBOSE=true
                echo -e "${DIM}[INFO] Verbose logging enabled${NC}" >&2
                ;;
            *)
                echo -e "${RED}${CROSS} Unknown option: $1${NC}" >&2
                echo -e "${DIM}Use 'upgrade-ai --help' for usage information.${NC}" >&2
                exit 1
                ;;
        esac
        shift
    done
}

# Parse arguments first
parse_args "$@"

# Run main function
main

# ============================================================================
# HOW TO ADD NEW TOOLS
# ============================================================================
#
# When you install a new AI CLI tool, follow these steps to add it to this script:
#
# 1. FIND THE COMMAND NAME
#    - What command do you type to run the tool? (e.g., "claude", "codex", "cursor")
#
# 2. FIND THE PACKAGE INFORMATION
#    - Check the tool's README/documentation for installation instructions
#    - Look for: npm install -g PACKAGE_NAME, bun install -g PACKAGE_NAME, or brew install PACKAGE_NAME
#
# 3. ADD TO THE TOOLS ARRAY (around line 23-29)
#    - Add a new line in the format: ["command_name"]="package_manager:package_name"
#
# EXAMPLES:
#
# For a tool installed via npm:
#   npm install -g @company/awesome-ai-tool
#   Command: awesome-ai
#   Add: ["awesome-ai"]="npm:@company/awesome-ai-tool"
#
# For a tool installed via bun:
#   bun install -g super-ai-cli
#   Command: super-ai
#   Add: ["super-ai"]="bun:super-ai-cli"
#
# For a tool installed via homebrew:
#   brew install amazing-ai
#   Command: amazing-ai
#   Add: ["amazing-ai"]="brew:amazing-ai"
#
# 4. TEST THE ADDITION
#    - Run: upgrade-ai
#    - Your new tool should appear in the list and be automatically installed if not present
#
# BEHAVIOR:
#
# - If a tool is NOT installed: The script will install it using the appropriate package manager
# - If a tool IS installed: The script will upgrade it to the latest version
# - The script shows clear status for each tool: Installed, Upgraded, Already up to date, or Failed
#
# TROUBLESHOOTING:
#
# - Tool not found and installation fails? Check that the package name is correct
# - If version detection fails, the tool might use a different --version format
#   The script will try common patterns automatically, but some tools might need
#   custom handling in the get_version() function
#
# - If installation/upgrade fails, check that the package name is correct in the tool's documentation
#   and that you have the necessary permissions
#
# - For npm: Make sure you have npm installed and configured properly
# - For bun: Make sure you have bun installed and configured properly  
# - For brew: Make sure you have Homebrew installed (macOS/Linux)
#
# ============================================================================
