#!/usr/bin/env bash
#
# Builds bindings/swift/Newtua.xcframework from the Rust newtua-ffi crate.
#
# Output: a release-optimized aarch64-apple-darwin dynamic library wrapped in
# a CNewtua.framework bundle, packaged into Newtua.xcframework. The framework
# is named CNewtua (matching the Swift `import CNewtua` module name); the
# top-level XCFramework keeps the SwiftPM product name "Newtua".
#
# The script is idempotent — every run regenerates the XCFramework from
# scratch (cheap, the Rust artifact is cached by cargo). Safe to call from an
# Xcode Run Script build phase.
#
# Boundary note: the Rust crate (`crates/newtua-ffi/Cargo.toml`) already ships
# `crate-type = ["staticlib", "cdylib", "rlib"]` — see
# `docs/reply-2026-06-24-newtua-ffi-cdylib.md`. We do NOT modify it.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

# Xcode-launched contexts don't include cargo on PATH — add it explicitly.
export PATH="$HOME/.cargo/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"

RUST_TARGET="aarch64-apple-darwin"
FRAMEWORK_NAME="CNewtua"
DYLIB_FILENAME="libnewtua_ffi.dylib"
HEADER_SRC="$REPO_ROOT/crates/newtua-ffi/include/newtua.h"
PKG_DIR="$REPO_ROOT/bindings/swift"
XCFRAMEWORK_PATH="$PKG_DIR/Newtua.xcframework"

if [[ ! -f "$HEADER_SRC" ]]; then
    echo "error: missing C header at $HEADER_SRC" >&2
    exit 1
fi

# 1. Build the release dylib. The minimum deployment target is set via env so
#    we don't have to touch Cargo.toml (this is a macOS-side compositional
#    decision; see decisions.md 2026-06-24, Stage 10).
export MACOSX_DEPLOYMENT_TARGET=26.0
(cd "$REPO_ROOT" && cargo build -p newtua-ffi --release --target "$RUST_TARGET")

DYLIB_SRC="$REPO_ROOT/target/$RUST_TARGET/release/$DYLIB_FILENAME"
if [[ ! -f "$DYLIB_SRC" ]]; then
    echo "error: cargo did not produce $DYLIB_SRC" >&2
    exit 1
fi

# 2. Stage CNewtua.framework in a fresh temp dir.
BUILD_DIR="$(mktemp -d)"
trap 'rm -rf "$BUILD_DIR"' EXIT

FRAMEWORK_DIR="$BUILD_DIR/$FRAMEWORK_NAME.framework"
VERSIONS_A="$FRAMEWORK_DIR/Versions/A"
mkdir -p "$VERSIONS_A/Headers" "$VERSIONS_A/Modules" "$VERSIONS_A/Resources"

# 2a. The framework binary is the dylib renamed (no `.dylib` suffix inside).
cp "$DYLIB_SRC" "$VERSIONS_A/$FRAMEWORK_NAME"
chmod 0755 "$VERSIONS_A/$FRAMEWORK_NAME"

# 2b. install_name lives on the macOS side: pin it to the framework's runtime
#     location relative to whoever loads it (the .app's Frameworks dir).
install_name_tool -id \
    "@rpath/$FRAMEWORK_NAME.framework/Versions/A/$FRAMEWORK_NAME" \
    "$VERSIONS_A/$FRAMEWORK_NAME"

# 2c. Public header from the cbindgen-generated copy in the Rust crate.
cp "$HEADER_SRC" "$VERSIONS_A/Headers/newtua.h"

# 2d. Modulemap so Swift sees this as `import CNewtua` (matches the existing
#     `bindings/swift/Sources/CNewtua/module.modulemap`).
cat > "$VERSIONS_A/Modules/module.modulemap" <<EOF
framework module $FRAMEWORK_NAME {
    umbrella header "newtua.h"
    export *
    module * { export * }
}
EOF

# 2e. Minimal Info.plist — required by xcodebuild -create-xcframework.
cat > "$VERSIONS_A/Resources/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>     <string>en</string>
    <key>CFBundleExecutable</key>            <string>$FRAMEWORK_NAME</string>
    <key>CFBundleIdentifier</key>            <string>org.newtua.$FRAMEWORK_NAME</string>
    <key>CFBundleInfoDictionaryVersion</key> <string>6.0</string>
    <key>CFBundleName</key>                  <string>$FRAMEWORK_NAME</string>
    <key>CFBundlePackageType</key>           <string>FMWK</string>
    <key>CFBundleShortVersionString</key>    <string>1.0</string>
    <key>CFBundleVersion</key>               <string>1</string>
    <key>MinimumOSVersion</key>              <string>26.0</string>
</dict>
</plist>
EOF

# 2f. Versioned framework symlinks (the layout xcodebuild expects).
(cd "$FRAMEWORK_DIR/Versions" && ln -sfn A Current)
(cd "$FRAMEWORK_DIR" \
    && ln -sfn "Versions/Current/$FRAMEWORK_NAME" "$FRAMEWORK_NAME" \
    && ln -sfn Versions/Current/Headers Headers \
    && ln -sfn Versions/Current/Modules Modules \
    && ln -sfn Versions/Current/Resources Resources)

# 3. Pack into XCFramework — replaces any previous artifact in place.
rm -rf "$XCFRAMEWORK_PATH"
xcodebuild -create-xcframework \
    -framework "$FRAMEWORK_DIR" \
    -output "$XCFRAMEWORK_PATH" >/dev/null

# 4. Smoke check: install_name must match what `@rpath` will resolve to.
EMBEDDED_BIN="$XCFRAMEWORK_PATH/macos-arm64/$FRAMEWORK_NAME.framework/Versions/A/$FRAMEWORK_NAME"
if [[ ! -f "$EMBEDDED_BIN" ]]; then
    echo "error: xcodebuild did not produce $EMBEDDED_BIN" >&2
    exit 1
fi
INSTALL_NAME=$(otool -D "$EMBEDDED_BIN" | tail -n 1 | tr -d '[:space:]')
EXPECTED="@rpath/$FRAMEWORK_NAME.framework/Versions/A/$FRAMEWORK_NAME"
if [[ "$INSTALL_NAME" != "$EXPECTED" ]]; then
    echo "error: install_name mismatch" >&2
    echo "  got:      $INSTALL_NAME" >&2
    echo "  expected: $EXPECTED" >&2
    exit 1
fi

DYLIB_SIZE=$(du -h "$EMBEDDED_BIN" | cut -f1)
echo "OK: $XCFRAMEWORK_PATH built ($DYLIB_SIZE, install_name $INSTALL_NAME)"
