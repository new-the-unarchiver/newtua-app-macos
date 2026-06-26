#!/usr/bin/env bash
#
# Installs the NewTheUnarchiver pre-alpha (un-notarized) into /Applications and
# registers it with Launch Services + Quick Look, so that:
#   - Finder's "Open With" / double-click route archives to the app, and
#   - Quick Look (Space) previews them via the bundled extension.
#
# This is a one-shot manual step for pre-alpha test builds — there is no DMG and
# no notarization yet. Re-run it after every new Release build.
#
# Why these exact steps (learned on real hardware, see decisions.md
# 2026-06-24 "Регистрация QL extension" and 2026-06-27 "Поддержка LZ4"):
#   * `lsregister -f` registers the app's UTIs / document types, but it does
#     NOT reliably register the Quick Look .appex — Spotlight rejects the scan
#     (errors -10811 / -10814). So we register the extension DIRECTLY with
#     `pluginkit -a`, which talks to pkd over XPC and bypasses indexing.
#   * Stale DerivedData / ./build copies "win" the bundle-id in pluginkit even
#     when outdated, so we unregister them first (their scan errors are benign
#     and ignored).
#
# Usage:
#   tools/install-prealpha.sh              # build Release, then install + register
#   tools/install-prealpha.sh --no-build   # reuse an existing Release .app
#
# Override the install destination with DEST=/some/Applications (default
# /Applications).
#
set -euo pipefail

# Xcode/cargo aren't on PATH in every shell — add the usual locations.
export PATH="$HOME/.cargo/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"

REPO_ROOT="$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)"
SRCROOT="$REPO_ROOT/apps/macos/NewTheUnarchiver"
PROJECT="$SRCROOT/NewTheUnarchiver.xcodeproj"
SCHEME="NewTheUnarchiver"
APP_NAME="NewTheUnarchiver.app"
BUILD_DIR="$SRCROOT/build"
RELEASE_APP="$BUILD_DIR/Build/Products/Release/$APP_NAME"
DEST="${DEST:-/Applications}"
INSTALLED_APP="$DEST/$APP_NAME"

LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister

DO_BUILD=1
[[ "${1:-}" == "--no-build" ]] && DO_BUILD=0

# ---------------------------------------------------------------------------
# 1. Build the Release bundle (unless --no-build).
# ---------------------------------------------------------------------------
if [[ "$DO_BUILD" == 1 ]]; then
    echo "==> Building Release ($SCHEME)..."
    xcodebuild build \
        -project "$PROJECT" \
        -scheme "$SCHEME" \
        -configuration Release \
        -destination 'platform=macOS' \
        -derivedDataPath "$BUILD_DIR" \
        -quiet
fi

if [[ ! -d "$RELEASE_APP" ]]; then
    echo "error: Release bundle not found at $RELEASE_APP" >&2
    echo "       run without --no-build, or build it in Xcode first." >&2
    exit 1
fi

APPEX="$INSTALLED_APP/Contents/PlugIns/NewTheUnarchiverQuickLook.appex"

# ---------------------------------------------------------------------------
# 2. Install into $DEST.
# ---------------------------------------------------------------------------
echo "==> Installing to $INSTALLED_APP..."
rm -rf "$INSTALLED_APP"
if ! cp -R "$RELEASE_APP" "$INSTALLED_APP" 2>/dev/null; then
    echo "error: could not copy into $DEST (try: sudo DEST=$DEST $0 --no-build)" >&2
    exit 1
fi

# Read the extension's bundle id straight from the installed bundle so this
# script never drifts from the project's signing settings.
QL_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' \
    "$APPEX/Contents/Info.plist" 2>/dev/null || true)"
if [[ -z "$QL_ID" ]]; then
    echo "error: could not read Quick Look extension bundle id from $APPEX" >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# 3. Drop stale registrations (DerivedData + ./build). Scan errors are benign.
# ---------------------------------------------------------------------------
echo "==> Unregistering stale copies..."
for p in \
    "$HOME"/Library/Developer/Xcode/DerivedData/NewTheUnarchiver-*/Build/Products/Debug/"$APP_NAME" \
    "$HOME"/Library/Developer/Xcode/DerivedData/NewTheUnarchiver-*/Build/Products/Release/"$APP_NAME" \
    "$RELEASE_APP"; do
    [[ -e "$p" ]] && "$LSREGISTER" -u "$p" >/dev/null 2>&1 || true
done

# ---------------------------------------------------------------------------
# 4. Register the installed app (UTIs / document types) and the QL extension.
# ---------------------------------------------------------------------------
echo "==> Registering app with Launch Services..."
"$LSREGISTER" -f "$INSTALLED_APP" >/dev/null 2>&1 || true

echo "==> Registering Quick Look extension ($QL_ID)..."
pluginkit -a "$APPEX"
pluginkit -e use -i "$QL_ID"

# ---------------------------------------------------------------------------
# 5. Restart the Quick Look daemon and Finder so changes take effect now.
# ---------------------------------------------------------------------------
echo "==> Restarting Quick Look daemon + Finder..."
qlmanage -r        >/dev/null 2>&1 || true
qlmanage -r cache  >/dev/null 2>&1 || true
killall quicklookd  2>/dev/null || true
killall Finder      2>/dev/null || true
sleep 2

# ---------------------------------------------------------------------------
# 6. Verify.
# ---------------------------------------------------------------------------
echo "==> Verifying..."
status=0

# 6a. The extension must be enabled ("+") and point at the installed bundle.
pk_line="$(pluginkit -mvv -i "$QL_ID" 2>/dev/null | head -1 || true)"
if [[ "$pk_line" == +* ]] && pluginkit -mvv -i "$QL_ID" 2>/dev/null | grep -q "$INSTALLED_APP"; then
    echo "    OK  Quick Look extension enabled at $INSTALLED_APP"
else
    echo "    !!  Quick Look extension not enabled as expected:" >&2
    pluginkit -mvv -i "$QL_ID" 2>&1 | head -3 >&2
    status=1
fi

# 6b. A .lz4 file must resolve to the system UTI public.lz4-archive (newest
#     format this build adds). Non-fatal: Spotlight may lag right after a
#     restart, so a miss is a warning, not a hard failure.
probe="$(mktemp -d)/sample.lz4"
: > "$probe"
ct="$(mdls -name kMDItemContentType -raw "$probe" 2>/dev/null || true)"
rm -rf "$(dirname "$probe")"
if [[ "$ct" == "public.lz4-archive" ]]; then
    echo "    OK  .lz4 resolves to public.lz4-archive"
else
    echo "    ?   .lz4 currently resolves to '${ct:-<none>}' (may settle shortly)"
fi

if [[ "$status" == 0 ]]; then
    echo "Done. $APP_NAME installed and registered. Try Space-preview on a .lz4 / .zip / .7z file."
else
    echo "Done with warnings — see messages above." >&2
fi
exit "$status"
