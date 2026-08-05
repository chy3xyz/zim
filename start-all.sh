#!/bin/bash
set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ============================================
# Dependency checks
# ============================================
echo -e "${BLUE}Checking dependencies...${NC}"

if ! command -v zig &> /dev/null; then
    echo -e "${RED}Error: zig is not installed or not in PATH${NC}"
    exit 1
fi

if ! command -v pnpm &> /dev/null; then
    echo -e "${RED}Error: pnpm is not installed or not in PATH${NC}"
    exit 1
fi

if ! command -v node &> /dev/null; then
    echo -e "${RED}Error: node is not installed or not in PATH${NC}"
    exit 1
fi

echo -e "${GREEN}  zig: $(zig version)${NC}"
echo -e "${GREEN}  node: $(node --version)${NC}"
echo -e "${GREEN}  pnpm: $(pnpm --version)${NC}"

# ============================================
# Build zim backend if needed
# ============================================
echo -e "${BLUE}Building zim backend...${NC}"
cd "$SCRIPT_DIR/src"

if [ ! -f "zig-out/bin/zim" ] || [ "$(find modules -newer zig-out/bin/zim 2>/dev/null | wc -l)" -gt 0 ]; then
    echo -e "${YELLOW}  Binary missing or source changed, rebuilding...${NC}"
    rm -rf zig-out .zig-cache
    zig build
    echo -e "${GREEN}  Build complete${NC}"
else
    echo -e "${GREEN}  Binary up to date, skipping build${NC}"
fi

# ============================================
# Install admin UI dependencies if needed
# ============================================
cd "$SCRIPT_DIR/ui/admin"
if [ ! -d "node_modules" ]; then
    echo -e "${BLUE}Installing admin UI dependencies...${NC}"
    pnpm install --ignore-scripts
    echo -e "${GREEN}  Dependencies installed${NC}"
fi

# ============================================
# Start zim backend
# ============================================
echo -e "${BLUE}Starting zim backend...${NC}"
cd "$SCRIPT_DIR/src"

# Kill any existing zim process
pkill -f "zig-out/bin/zim" 2>/dev/null || true
sleep 1

./zig-out/bin/zim > "$SCRIPT_DIR/zim-server.log" 2>&1 &
ZIM_PID=$!
echo -e "${GREEN}  zim server started (PID: $ZIM_PID)${NC}"

# Wait for backend to be ready
echo -e "${YELLOW}  Waiting for backend to be ready...${NC}"
for i in {1..30}; do
    if curl -s http://localhost:10000/health > /dev/null 2>&1; then
        echo -e "${GREEN}  Backend ready!${NC}"
        break
    fi
    if ! kill -0 $ZIM_PID 2>/dev/null; then
        echo -e "${RED}  Backend failed to start. Check zim-server.log${NC}"
        cat "$SCRIPT_DIR/zim-server.log" | tail -20
        exit 1
    fi
    sleep 1
    echo -n "."
done

if ! curl -s http://localhost:10000/health > /dev/null 2>&1; then
    echo -e "${RED}  Backend failed to start within 30s. Check zim-server.log${NC}"
    cat "$SCRIPT_DIR/zim-server.log" | tail -20
    exit 1
fi

# ============================================
# Start admin UI
# ============================================
echo -e "${BLUE}Starting admin UI...${NC}"
cd "$SCRIPT_DIR/ui/admin"

echo -e "${YELLOW}  Admin UI will be available at http://localhost:8000${NC}"
echo -e "${YELLOW}  Admin login: account=admin, password=any${NC}"
echo -e "${YELLOW}  IM API: http://localhost:10000${NC}"
echo -e "${YELLOW}  WebSocket: ws://localhost:10001${NC}"
echo ""
echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}  All services started!${NC}"
echo -e "${GREEN}============================================${NC}"
echo ""
echo -e "${BLUE}Press Ctrl+C to stop all services${NC}"
echo ""

# Trap Ctrl+C to stop zim backend
cleanup() {
    echo ""
    echo -e "${YELLOW}Shutting down...${NC}"
    if kill -0 $ZIM_PID 2>/dev/null; then
        kill $ZIM_PID 2>/dev/null || true
        wait $ZIM_PID 2>/dev/null || true
        echo -e "${GREEN}  zim server stopped${NC}"
    fi
    exit 0
}
trap cleanup SIGINT SIGTERM

# Start admin UI in foreground (so Ctrl+C stops it)
pnpm dev

# If admin UI exits, also stop zim
cleanup
