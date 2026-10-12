#!/bin/bash
# Builds the eqMac app and audio driver from source (Release, ad-hoc signed).
# See LOCAL-BUILD-NOTES.md for why each step is needed.
#
#   ./build.sh                     build UI, app and driver
#   ./build.sh --skip-ui           reuse native/app/Embedded/ui.zip
#   ./build.sh --install-driver    also install the driver (asks for your password)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
PRODUCTS="$ROOT/build/Build/Products/Release"
LOG_DIR="$ROOT/build/logs"
SKIP_UI=0
INSTALL_DRIVER=0

for arg in "$@"; do
  case "$arg" in
    --skip-ui) SKIP_UI=1 ;;
    --install-driver) INSTALL_DRIVER=1 ;;
    -h|--help) sed -n '2,7p' "$0"; exit 0 ;;
    *) echo "Unknown option: $arg" >&2; exit 1 ;;
  esac
done

step () { printf '\n==> %s\n' "$1"; }

# xcode-select may point at the Command Line Tools, which can't build the app
if ! xcodebuild -version >/dev/null 2>&1; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
XCODE_VERSION="$(xcodebuild -version)"
echo "${XCODE_VERSION%%$'\n'*}"
mkdir -p "$LOG_DIR"

# 1. UI (Angular) -> native/app/Embedded/ui.zip
if [ "$SKIP_UI" = 0 ]; then
  step "Building UI"
  (cd "$ROOT" && yarn install --ignore-engines --frozen-lockfile >"$LOG_DIR/yarn.log" 2>&1) || {
    echo "yarn install failed, see $LOG_DIR/yarn.log" >&2; exit 1; }
  mkdir -p "$ROOT/native/app/Embedded"
  # Angular 12's webpack needs the legacy OpenSSL provider on Node 17+
  (cd "$ROOT/ui" && NODE_OPTIONS=--openssl-legacy-provider yarn build >"$LOG_DIR/ui.log" 2>&1) || {
    echo "UI build failed, see $LOG_DIR/ui.log" >&2; exit 1; }
fi
[ -f "$ROOT/native/app/Embedded/ui.zip" ] || { echo "native/app/Embedded/ui.zip is missing, run without --skip-ui" >&2; exit 1; }

# 2. CocoaPods, only when the installed pods don't match Podfile.lock
cd "$ROOT/native"
if ! cmp -s Podfile.lock Pods/Manifest.lock 2>/dev/null; then
  step "Installing pods"
  pod install
fi

# 3. App and driver
XCODE_ARGS=(
  -workspace eqMac.xcworkspace
  -configuration Release
  -derivedDataPath "$ROOT/build"
  CODE_SIGN_IDENTITY=-
  CODE_SIGNING_REQUIRED=NO
  DEVELOPMENT_TEAM=
  MACOSX_DEPLOYMENT_TARGET=12.0
  EQMAC_SKIP_DRIVER_INSTALL=YES
)
for scheme in "eqMac" "Driver - Release"; do
  step "Building $scheme"
  log="$LOG_DIR/xcodebuild-${scheme// /-}.log"
  if ! xcodebuild "${XCODE_ARGS[@]}" -scheme "$scheme" build >"$log" 2>&1; then
    grep -E "error:" "$log" | sort -u | head -20 >&2 || true
    echo "$scheme build failed, see $log" >&2
    exit 1
  fi
done

# 4. The Xcode project doesn't bundle ui.zip (upstream adds it in their release pipeline),
#    and the app crashes at launch without it.
step "Bundling UI and signing"
mkdir -p "$PRODUCTS/eqMac.app/Contents/Resources/Embedded"
cp "$ROOT/native/app/Embedded/ui.zip" "$PRODUCTS/eqMac.app/Contents/Resources/Embedded/ui.zip"
# macOS won't load an unsigned driver on Apple Silicon, so sign both bundles ad hoc
for bundle in eqMac.driver eqMac.app; do
  codesign --force --deep -s - "$PRODUCTS/$bundle" 2>/dev/null
  codesign --verify --deep --strict "$PRODUCTS/$bundle"
done

# 5. Optional driver install
if [ "$INSTALL_DRIVER" = 1 ]; then
  step "Installing driver (password required)"
  pkill -x eqMac 2>/dev/null || true
  sudo rm -rf /Library/Audio/Plug-Ins/HAL/eqMac.driver
  sudo cp -R "$PRODUCTS/eqMac.driver" /Library/Audio/Plug-Ins/HAL/
  # launchctl kickstart is blocked while SIP is on; launchd restarts coreaudiod by itself
  sudo killall coreaudiod
fi

step "Done"
echo "App:    $PRODUCTS/eqMac.app"
echo "Driver: $PRODUCTS/eqMac.driver"
[ "$INSTALL_DRIVER" = 1 ] || echo "Install the driver with: ./build.sh --skip-ui --install-driver"
