#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NATIVE_DIR="$ROOT_DIR/native"
APP_NAME="BeatDropper"
EXECUTABLE_NAME="BeatDropperNative"
BUILD_CONFIGURATION="${BUILD_CONFIGURATION:-release}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
NOTARIZE="${NOTARIZE:-0}"
NOTARY_KEYCHAIN_PROFILE="${NOTARY_KEYCHAIN_PROFILE:-}"
APPLE_ID="${APPLE_ID:-}"
APPLE_TEAM_ID="${APPLE_TEAM_ID:-}"
APPLE_PASSWORD="${APPLE_PASSWORD:-}"
BUILD_DIR="$NATIVE_DIR/.build"
DIST_DIR="$NATIVE_DIR/dist"
APP_DIR="$DIST_DIR/$APP_NAME.app"
ZIP_PATH="$DIST_DIR/$APP_NAME.zip"
DMG_PATH="$DIST_DIR/$APP_NAME.dmg"
DMG_STAGING_DIR="$DIST_DIR/dmg-staging"
NOTARY_LOG_DIR="$DIST_DIR/notary-logs"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
SCRIPT_RESOURCES_DIR="$RESOURCES_DIR/Scripts"
RUNTIME_RESOURCES_DIR="$RESOURCES_DIR/Runtime"
THIRD_PARTY_RESOURCES_DIR="$RESOURCES_DIR/ThirdParty"
INFO_PLIST="$NATIVE_DIR/Packaging/Info.plist"
ENTITLEMENTS="$NATIVE_DIR/Packaging/BeatDropper.entitlements"
ICON_SOURCE="$ROOT_DIR/public/icons/dropper-icon.png"
PLANNER_SCRIPT="$ROOT_DIR/scripts/codex-mix-planner.cjs"
NODE_BINARY="${NODE_BINARY:-$(command -v node || true)}"
ICONSET_DIR="$DIST_DIR/$APP_NAME.iconset"
ICNS_PATH="$RESOURCES_DIR/$APP_NAME.icns"

if [[ ! -f "$INFO_PLIST" ]]; then
  echo "Missing Info.plist: $INFO_PLIST" >&2
  exit 1
fi

if [[ ! -f "$ICON_SOURCE" ]]; then
  echo "Missing icon source: $ICON_SOURCE" >&2
  exit 1
fi

if [[ ! -f "$PLANNER_SCRIPT" ]]; then
  echo "Missing planner script: $PLANNER_SCRIPT" >&2
  exit 1
fi

if [[ -z "$NODE_BINARY" || ! -x "$NODE_BINARY" ]]; then
  echo "Missing executable Node runtime. Set NODE_BINARY to the node executable used by the planner bridge." >&2
  exit 1
fi

NODE_ROOT="$(cd "$(dirname "$NODE_BINARY")/.." && pwd)"
NODE_LICENSE_FILE="${NODE_LICENSE_FILE:-$NODE_ROOT/LICENSE}"
NODE_VERSION="$("$NODE_BINARY" --version)"

if [[ ! -f "$NODE_LICENSE_FILE" ]]; then
  echo "Missing Node license file. Set NODE_LICENSE_FILE to the LICENSE file for $NODE_BINARY." >&2
  exit 1
fi

PACKAGE_VERSION="$(
  node -e "const fs = require('node:fs'); const pkg = JSON.parse(fs.readFileSync(process.argv[1], 'utf8')); process.stdout.write(String(pkg.version || ''));" "$ROOT_DIR/package.json"
)"
BUNDLE_VERSION="${BUNDLE_VERSION:-$PACKAGE_VERSION}"

if [[ ! "$PACKAGE_VERSION" =~ ^[0-9]+([.][0-9]+){0,2}$ ]]; then
  echo "package.json version must be a numeric macOS bundle short version: $PACKAGE_VERSION" >&2
  exit 1
fi

if [[ ! "$BUNDLE_VERSION" =~ ^[0-9]+([.][0-9]+){0,2}$ ]]; then
  echo "BUNDLE_VERSION must be numeric for CFBundleVersion: $BUNDLE_VERSION" >&2
  exit 1
fi

notary_submit() {
  local artifact_path="$1"
  local artifact_label="$2"
  local submit_json="$NOTARY_LOG_DIR/$artifact_label-submit.json"
  local log_json="$NOTARY_LOG_DIR/$artifact_label-log.json"
  local submit_args=(notarytool submit)
  local log_args=(notarytool log)

  mkdir -p "$NOTARY_LOG_DIR"

  if [[ -n "$NOTARY_KEYCHAIN_PROFILE" ]]; then
    submit_args+=(--keychain-profile "$NOTARY_KEYCHAIN_PROFILE")
    log_args+=(--keychain-profile "$NOTARY_KEYCHAIN_PROFILE")
  elif [[ -n "$APPLE_ID" && -n "$APPLE_TEAM_ID" && -n "$APPLE_PASSWORD" ]]; then
    submit_args+=(
      --apple-id "$APPLE_ID"
      --team-id "$APPLE_TEAM_ID"
      --password "$APPLE_PASSWORD"
    )
    log_args+=(
      --apple-id "$APPLE_ID"
      --team-id "$APPLE_TEAM_ID"
      --password "$APPLE_PASSWORD"
    )
  else
    echo "NOTARIZE=1 requires NOTARY_KEYCHAIN_PROFILE or APPLE_ID, APPLE_TEAM_ID, and APPLE_PASSWORD." >&2
    exit 1
  fi

  submit_args+=(--wait --output-format json "$artifact_path")
  xcrun "${submit_args[@]}" | tee "$submit_json"

  local submission_id
  submission_id="$(
    node -e "const fs = require('node:fs'); const data = JSON.parse(fs.readFileSync(process.argv[1], 'utf8')); process.stdout.write(data.id || data.submissionId || '');" "$submit_json"
  )"
  if [[ -z "$submission_id" ]]; then
    echo "Could not parse notary submission id from $submit_json" >&2
    exit 1
  fi

  log_args+=("$submission_id" "$log_json")
  xcrun "${log_args[@]}"
  echo "Notary evidence written: $submit_json"
  echo "Notary log written: $log_json"
}

codesign_app() {
  local target="$1"
  local sign_args=(
    --force
    --deep
    --options runtime
    --sign "$SIGN_IDENTITY"
    --entitlements "$ENTITLEMENTS"
  )

  if [[ "$SIGN_IDENTITY" == "-" ]]; then
    sign_args+=(--timestamp=none)
  else
    sign_args+=(--timestamp)
  fi

  codesign "${sign_args[@]}" "$target" >/dev/null
}

if [[ "$NOTARIZE" == "1" && "$SIGN_IDENTITY" == "-" ]]; then
  echo "NOTARIZE=1 requires SIGN_IDENTITY to be a Developer ID Application identity." >&2
  exit 1
fi

if [[ "$SIGN_IDENTITY" != "-" ]]; then
  if ! security find-identity -v -p codesigning | grep -F "$SIGN_IDENTITY" >/dev/null; then
    echo "SIGN_IDENTITY does not match an installed valid code signing identity: $SIGN_IDENTITY" >&2
    echo "Run: npm run native:release:check" >&2
    exit 1
  fi
fi

if [[ "$NOTARIZE" == "1" && -z "$NOTARY_KEYCHAIN_PROFILE" && ( -z "$APPLE_ID" || -z "$APPLE_TEAM_ID" || -z "$APPLE_PASSWORD" ) ]]; then
  echo "NOTARIZE=1 requires NOTARY_KEYCHAIN_PROFILE or APPLE_ID, APPLE_TEAM_ID, and APPLE_PASSWORD." >&2
  echo "Run: npm run native:release:check" >&2
  exit 1
fi

swift build \
  --package-path "$NATIVE_DIR" \
  -c "$BUILD_CONFIGURATION" \
  --product "$EXECUTABLE_NAME"

BUILT_EXECUTABLE="$BUILD_DIR/$BUILD_CONFIGURATION/$EXECUTABLE_NAME"
if [[ ! -x "$BUILT_EXECUTABLE" ]]; then
  echo "Missing built executable: $BUILT_EXECUTABLE" >&2
  exit 1
fi

rm -rf "$APP_DIR" "$ICONSET_DIR" "$DMG_STAGING_DIR" "$ZIP_PATH" "$DMG_PATH" "$NOTARY_LOG_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$SCRIPT_RESOURCES_DIR" "$RUNTIME_RESOURCES_DIR" "$THIRD_PARTY_RESOURCES_DIR" "$ICONSET_DIR"

cp "$BUILT_EXECUTABLE" "$MACOS_DIR/$EXECUTABLE_NAME"
chmod 755 "$MACOS_DIR/$EXECUTABLE_NAME"
cp "$INFO_PLIST" "$CONTENTS_DIR/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $PACKAGE_VERSION" "$CONTENTS_DIR/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUNDLE_VERSION" "$CONTENTS_DIR/Info.plist"
cp "$PLANNER_SCRIPT" "$SCRIPT_RESOURCES_DIR/codex-mix-planner.cjs"
cp "$NODE_BINARY" "$RUNTIME_RESOURCES_DIR/node"
chmod 755 "$RUNTIME_RESOURCES_DIR/node"
cp "$NODE_LICENSE_FILE" "$THIRD_PARTY_RESOURCES_DIR/Node-LICENSE.txt"
{
  printf 'BeatDropper Third-Party Notices\n'
  printf '\n'
  printf 'Node.js runtime\n'
  printf 'Version: %s\n' "$NODE_VERSION"
  printf 'Bundled executable: Contents/Resources/Runtime/node\n'
  printf 'License file: Contents/Resources/ThirdParty/Node-LICENSE.txt\n'
} > "$THIRD_PARTY_RESOURCES_DIR/THIRD-PARTY-NOTICES.txt"
printf 'APPL????' > "$CONTENTS_DIR/PkgInfo"

for size in 16 32 128 256 512; do
  sips -z "$size" "$size" "$ICON_SOURCE" \
    --out "$ICONSET_DIR/icon_${size}x${size}.png" >/dev/null
  double_size=$((size * 2))
  sips -z "$double_size" "$double_size" "$ICON_SOURCE" \
    --out "$ICONSET_DIR/icon_${size}x${size}@2x.png" >/dev/null
done

iconutil -c icns "$ICONSET_DIR" -o "$ICNS_PATH"
rm -rf "$ICONSET_DIR"

plutil -lint "$CONTENTS_DIR/Info.plist" >/dev/null
codesign_app "$APP_DIR"
codesign --verify --deep --strict "$APP_DIR"

ditto -c -k --keepParent "$APP_DIR" "$ZIP_PATH"

if [[ "$NOTARIZE" == "1" ]]; then
  notary_submit "$ZIP_PATH" "zip"
  xcrun stapler staple "$APP_DIR"
  spctl --assess --type execute --verbose "$APP_DIR"
  ditto -c -k --keepParent "$APP_DIR" "$ZIP_PATH"
fi

mkdir -p "$DMG_STAGING_DIR"
cp -R "$APP_DIR" "$DMG_STAGING_DIR/$APP_NAME.app"
ln -s /Applications "$DMG_STAGING_DIR/Applications"
hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$DMG_STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH" >/dev/null
rm -rf "$DMG_STAGING_DIR"

if [[ "$SIGN_IDENTITY" != "-" ]]; then
  codesign --force --sign "$SIGN_IDENTITY" --timestamp "$DMG_PATH" >/dev/null
fi

if [[ "$NOTARIZE" == "1" ]]; then
  notary_submit "$DMG_PATH" "dmg"
  xcrun stapler staple "$DMG_PATH"
  spctl --assess --type open --context context:primary-signature --verbose "$DMG_PATH"
fi

node "$ROOT_DIR/scripts/write-native-release-manifest.cjs"

printf '%s\n' "$APP_DIR" "$ZIP_PATH" "$DMG_PATH" "$DIST_DIR/release-manifest.json"
