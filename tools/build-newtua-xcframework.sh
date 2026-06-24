#!/usr/bin/env bash
#
# Builds bindings/swift/Newtua.xcframework from the Rust newtua-ffi crate.
# Safe to call from an Xcode Run Script build phase — it short-circuits when
# the inputs haven't changed.
#
# The framework inside is named CNewtua (matching the `import CNewtua`
# module name); the top-level XCFramework keeps the SwiftPM product name
# "Newtua". The Rust crate already ships `crate-type = ["staticlib",
# "cdylib", "rlib"]` — see docs/reply-2026-06-24-newtua-ffi-cdylib.md. We
# do NOT modify it.
#
set -euo pipefail

# Xcode-launched contexts don't include cargo on PATH — add it explicitly.
export PATH="$HOME/.cargo/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"

REPO_ROOT="$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)"

RUST_TARGET="aarch64-apple-darwin"
FRAMEWORK_NAME="CNewtua"
FRAMEWORK_VERSION="A"
DYLIB_FILENAME="libnewtua_ffi.dylib"
HEADER_SRC="$REPO_ROOT/crates/newtua-ffi/include/newtua.h"
DYLIB_SRC="$REPO_ROOT/target/$RUST_TARGET/release/$DYLIB_FILENAME"
XCFRAMEWORK_PATH="$REPO_ROOT/bindings/swift/Newtua.xcframework"
EMBEDDED_BIN="$XCFRAMEWORK_PATH/macos-arm64/$FRAMEWORK_NAME.framework/Versions/$FRAMEWORK_VERSION/$FRAMEWORK_NAME"
INSTALL_NAME="@rpath/$FRAMEWORK_NAME.framework/Versions/$FRAMEWORK_VERSION/$FRAMEWORK_NAME"

if [[ ! -f "$HEADER_SRC" ]]; then
    echo "error: missing C header at $HEADER_SRC" >&2
    exit 1
fi

# MACOSX_DEPLOYMENT_TARGET via env keeps this concern out of Cargo.toml —
# the floor lives with the macOS app, not the cross-platform engine.
export MACOSX_DEPLOYMENT_TARGET=26.0
(cd "$REPO_ROOT" && cargo build -p newtua-ffi --release --target "$RUST_TARGET" --locked --quiet)

if [[ ! -f "$DYLIB_SRC" ]]; then
    echo "error: cargo did not produce $DYLIB_SRC" >&2
    exit 1
fi

# Short-circuit when nothing that affects the XCFramework has changed.
# `-nt` returns false on missing files, so the check naturally fires on
# first run too. We include this script itself so edits to the Info.plist
# or modulemap heredocs invalidate the cached artifact.
if [[ -f "$EMBEDDED_BIN" \
    && ! "$DYLIB_SRC"        -nt "$EMBEDDED_BIN" \
    && ! "$HEADER_SRC"       -nt "$EMBEDDED_BIN" \
    && ! "${BASH_SOURCE[0]}" -nt "$EMBEDDED_BIN" ]]; then
    echo "OK: $XCFRAMEWORK_PATH up to date"
    exit 0
fi

BUILD_DIR="$(mktemp -d)"
trap 'rm -rf "$BUILD_DIR"' EXIT

FRAMEWORK_DIR="$BUILD_DIR/$FRAMEWORK_NAME.framework"
VERSION_DIR="$FRAMEWORK_DIR/Versions/$FRAMEWORK_VERSION"
mkdir -p "$VERSION_DIR/Headers" "$VERSION_DIR/Modules" "$VERSION_DIR/Resources"

cp "$DYLIB_SRC" "$VERSION_DIR/$FRAMEWORK_NAME"
install_name_tool -id "$INSTALL_NAME" "$VERSION_DIR/$FRAMEWORK_NAME"
cp "$HEADER_SRC" "$VERSION_DIR/Headers/newtua.h"

cat > "$VERSION_DIR/Modules/module.modulemap" <<EOF
framework module $FRAMEWORK_NAME {
    umbrella header "newtua.h"
    export *
    module * { export * }
}
EOF

cat > "$VERSION_DIR/Resources/Info.plist" <<EOF
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
    <key>MinimumOSVersion</key>              <string>$MACOSX_DEPLOYMENT_TARGET</string>
</dict>
</plist>
EOF

# Symlink layout that xcodebuild -create-xcframework expects.
(cd "$FRAMEWORK_DIR/Versions" && ln -sfn "$FRAMEWORK_VERSION" Current)
(cd "$FRAMEWORK_DIR" \
    && ln -sfn "Versions/Current/$FRAMEWORK_NAME" "$FRAMEWORK_NAME" \
    && ln -sfn Versions/Current/Headers Headers \
    && ln -sfn Versions/Current/Modules Modules \
    && ln -sfn Versions/Current/Resources Resources)

rm -rf "$XCFRAMEWORK_PATH"
xcodebuild -create-xcframework \
    -framework "$FRAMEWORK_DIR" \
    -output "$XCFRAMEWORK_PATH" >/dev/null

if [[ ! -f "$EMBEDDED_BIN" ]]; then
    echo "error: xcodebuild did not produce $EMBEDDED_BIN" >&2
    exit 1
fi
ACTUAL_INSTALL_NAME=$(otool -D "$EMBEDDED_BIN" | tail -n 1 | tr -d '[:space:]')
if [[ "$ACTUAL_INSTALL_NAME" != "$INSTALL_NAME" ]]; then
    echo "error: install_name mismatch" >&2
    echo "  got:      $ACTUAL_INSTALL_NAME" >&2
    echo "  expected: $INSTALL_NAME" >&2
    exit 1
fi

DYLIB_SIZE=$(du -h "$EMBEDDED_BIN" | cut -f1)
echo "OK: $XCFRAMEWORK_PATH built ($DYLIB_SIZE, install_name $INSTALL_NAME)"
