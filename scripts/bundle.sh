#!/usr/bin/env bash
# Builds build/MacWorkspaces.app (release, ad-hoc signed).
# Usage: scripts/bundle.sh [--install]   (--install copies the app to /Applications)
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release --product MacWorkspaces
BIN="$(swift build -c release --show-bin-path)/MacWorkspaces"

APP="build/MacWorkspaces.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/MacWorkspaces"
cp Resources/Info.plist "$APP/Contents/Info.plist"

# Ad-hoc signature: enough to run locally and for TCC to attribute permissions to the
# bundle. Developer ID signing + notarization is a later distribution decision.
codesign --force --sign - --timestamp=none "$APP"
codesign --verify --verbose=2 "$APP"
echo "Built $APP"

if [[ "${1:-}" == "--install" ]]; then
  LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
  rm -rf /Applications/MacWorkspaces.app
  cp -R "$APP" /Applications/
  # Only the installed copy may handle macworkspaces:// — otherwise LaunchServices can keep
  # routing ⌘Return to a stale build/ copy with the same bundle id.
  "$LSREGISTER" -u "$PWD/$APP" 2>/dev/null || true
  rm -rf "$APP"
  "$LSREGISTER" -f /Applications/MacWorkspaces.app
  echo "Installed /Applications/MacWorkspaces.app"
fi
