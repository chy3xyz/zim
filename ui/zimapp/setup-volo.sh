#!/bin/bash
#
# Setup script for connecting OpenIM Flutter to Volo-OpenIM backend
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$SCRIPT_DIR/openim_common/lib/src"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[✓]${NC} $1"; }
log_error() { echo -e "${RED}[✗]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[!]${NC} $1"; }
log_section() { echo -e "${CYAN}════════════════════════════════════════════════════════════${NC}"; }

# Get local IP
get_local_ip() {
    local ip=""
    if [[ "$OSTYPE" == "darwin"* ]]; then
        ip=$(ifconfig | grep "inet " | grep -v 127.0.0.1 | awk '{print $2}' | head -1)
    elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
        ip=$(hostname -I | awk '{print $1}')
    fi
    echo "$ip"
}

# Show current status
show_status() {
    log_section
    log_info "Current Configuration Status"
    log_section
    
    if [[ -f "$CONFIG_DIR/config.dart.backup" ]]; then
        log_warn "Original config backed up"
    fi
    
    if [[ -f "$CONFIG_DIR/config.dart" ]]; then
        local current_host=$(grep "_defaultHost" "$CONFIG_DIR/config.dart" | grep "return" | head -1)
        log_info "Current config host: $current_host"
    fi
}

# Setup for Android Emulator
setup_android() {
    log_section
    log_info "Setting up for Android Emulator"
    log_section
    
    # Backup original if not already backed up
    if [[ ! -f "$CONFIG_DIR/config.dart.backup" ]]; then
        cp "$CONFIG_DIR/config.dart" "$CONFIG_DIR/config.dart.backup"
        log_success "Original config backed up"
    fi
    
    # Copy volo config
    cp "$CONFIG_DIR/config_volo.dart" "$CONFIG_DIR/config.dart"
    
    # Update for Android (10.0.2.2)
    sed -i.bak 's/return "localhost";/return "10.0.2.2";/g' "$CONFIG_DIR/config.dart" 2>/dev/null || \
        sed -i '' 's/return "localhost";/return "10.0.2.2";/g' "$CONFIG_DIR/config.dart"
    
    log_success "Configuration updated for Android Emulator"
    log_info "API URL: http://10.0.2.2:10002"
    log_info "WebSocket: ws://10.0.2.2:10001"
}

# Setup for iOS Simulator
setup_ios_simulator() {
    log_section
    log_info "Setting up for iOS Simulator"
    log_section
    
    if [[ ! -f "$CONFIG_DIR/config.dart.backup" ]]; then
        cp "$CONFIG_DIR/config.dart" "$CONFIG_DIR/config.dart.backup"
        log_success "Original config backed up"
    fi
    
    cp "$CONFIG_DIR/config_volo.dart" "$CONFIG_DIR/config.dart"
    
    # localhost is fine for iOS Simulator
    log_success "Configuration updated for iOS Simulator"
    log_info "API URL: http://localhost:10002"
    log_info "WebSocket: ws://localhost:10001"
}

# Setup for real device
setup_real_device() {
    local ip=$(get_local_ip)
    
    log_section
    log_info "Setting up for Real Device"
    log_section
    
    if [[ -z "$ip" ]]; then
        log_error "Could not determine local IP address"
        exit 1
    fi
    
    log_info "Local IP detected: $ip"
    
    if [[ ! -f "$CONFIG_DIR/config.dart.backup" ]]; then
        cp "$CONFIG_DIR/config.dart" "$CONFIG_DIR/config.dart.backup"
        log_success "Original config backed up"
    fi
    
    cp "$CONFIG_DIR/config_volo.dart" "$CONFIG_DIR/config.dart"
    
    # Update IP for real device
    sed -i.bak "s/return 'localhost';/return '$ip';/g" "$CONFIG_DIR/config.dart" 2>/dev/null || \
        sed -i '' "s/return 'localhost';/return '$ip';/g" "$CONFIG_DIR/config.dart"
    
    log_success "Configuration updated for Real Device"
    log_info "API URL: http://$ip:10002"
    log_info "WebSocket: ws://$ip:10001"
    log_warn "Make sure your phone and computer are on the same WiFi"
}

# Restore original config
restore_original() {
    log_section
    log_info "Restoring original configuration"
    log_section
    
    if [[ -f "$CONFIG_DIR/config.dart.backup" ]]; then
        cp "$CONFIG_DIR/config.dart.backup" "$CONFIG_DIR/config.dart"
        log_success "Original configuration restored"
    else
        log_error "No backup found"
    fi
}

# Run Flutter app
run_flutter() {
    log_section
    log_info "Running Flutter App"
    log_section
    
    cd "$SCRIPT_DIR"
    
    # Check if dependencies are installed
    if [[ ! -d "openim_common/.dart_tool" ]]; then
        log_info "Installing dependencies..."
        flutter pub get
    fi
    
    log_info "Starting Flutter app..."
    flutter run
}

# Show help
show_help() {
    cat << EOF
OpenIM Flutter - Volo Backend Setup Script

Usage: $0 [command]

Commands:
    android     Configure for Android Emulator (10.0.2.2)
    ios         Configure for iOS Simulator (localhost)
    device      Configure for Real Device (auto-detect IP)
    restore     Restore original configuration
    run         Run Flutter app after configuration
    status      Show current configuration status
    help        Show this help

Examples:
    $0 android      # Setup for Android Emulator
    $0 ios          # Setup for iOS Simulator
    $0 device       # Setup for real device
    $0 run          # Run the app

Quick Start:
    1. Start volo-openim backend:
       cd volo-openim/apps/openim-main && cargo run --release
    
    2. Configure Flutter:
       $0 android     # For Android Emulator
       $0 ios         # For iOS Simulator
       $0 device      # For real device
    
    3. Run Flutter app:
       $0 run

Note:
    - For Android Emulator: uses 10.0.2.2 to access host
    - For iOS Simulator: uses localhost
    - For Real Device: uses your computer's IP (must be same WiFi)

EOF
}

# Main
main() {
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║     OpenIM Flutter + Volo-OpenIM Setup                     ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""
    
    case "${1:-}" in
        android)
            setup_android
            ;;
        ios|simulator)
            setup_ios_simulator
            ;;
        device|real)
            setup_real_device
            ;;
        restore)
            restore_original
            ;;
        run)
            run_flutter
            ;;
        status)
            show_status
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            show_help
            exit 1
            ;;
    esac
}

main "$@"
