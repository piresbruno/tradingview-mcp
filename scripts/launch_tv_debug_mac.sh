#!/bin/bash
# Launch TradingView Desktop on macOS with Chrome DevTools Protocol enabled
# Usage: ./scripts/launch_tv_debug_mac.sh [port]

PORT="${1:-9222}"

# Auto-detect TradingView .app bundle
APP_BUNDLE=""
LOCATIONS=(
  "/Applications/TradingView.app"
  "$HOME/Applications/TradingView.app"
)

for loc in "${LOCATIONS[@]}"; do
  if [ -d "$loc" ]; then
    APP_BUNDLE="$loc"
    break
  fi
done

# Fallback: search with mdfind (Spotlight)
if [ -z "$APP_BUNDLE" ]; then
  APP_BUNDLE=$(mdfind "kMDItemCFBundleIdentifier == 'com.tradingview.tradingviewapp.desktop'" 2>/dev/null | head -1)
fi

# Fallback: find any TradingView.app
if [ -z "$APP_BUNDLE" ] || [ ! -d "$APP_BUNDLE" ]; then
  APP_BUNDLE=$(find /Applications "$HOME/Applications" -name "TradingView.app" -maxdepth 2 2>/dev/null | head -1)
fi

if [ -z "$APP_BUNDLE" ] || [ ! -d "$APP_BUNDLE" ]; then
  echo "Error: TradingView not found."
  echo "Checked: /Applications/TradingView.app, ~/Applications/TradingView.app"
  echo ""
  echo "If installed elsewhere, run manually:"
  echo "  open /path/to/TradingView.app --args --remote-debugging-port=$PORT"
  exit 1
fi

# Kill any existing TradingView
pkill -f "TradingView" 2>/dev/null
sleep 1

echo "Found TradingView at: $APP_BUNDLE"
echo "Launching with --remote-debugging-port=$PORT ..."
open -a "$APP_BUNDLE" --args --remote-debugging-port=$PORT
echo "Launched via macOS open command"

# Wait for CDP to be ready
echo "Waiting for CDP..."
for i in $(seq 1 30); do
  if curl -s "http://localhost:$PORT/json/version" > /dev/null 2>&1; then
    echo "CDP ready at http://localhost:$PORT"
    curl -s "http://localhost:$PORT/json/version" | python3 -m json.tool 2>/dev/null || curl -s "http://localhost:$PORT/json/version"
    exit 0
  fi
  sleep 1
done

echo "Warning: CDP not responding after 30s. TradingView may still be loading."
echo "Check manually: curl http://localhost:$PORT/json/version"
