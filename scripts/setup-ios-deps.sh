#!/usr/bin/env bash

# Downloads and prepares SherpaOnnxKit binary XCFramework dependencies used by
# the local Swift package.

set -euo pipefail

SHERPA_VERSION="${SHERPA_VERSION:-1.12.23}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PKG_DIR="$REPO_DIR/LocalPackages/SherpaOnnxKit"

if [ ! -d "$PKG_DIR" ]; then
  echo "SherpaOnnxKit directory not found: $PKG_DIR" >&2
  exit 1
fi

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

ARCHIVE="$WORK_DIR/sherpa-onnx-v${SHERPA_VERSION}-ios-no-tts.tar.bz2"
URL="https://github.com/k2-fsa/sherpa-onnx/releases/download/v${SHERPA_VERSION}/sherpa-onnx-v${SHERPA_VERSION}-ios-no-tts.tar.bz2"

echo "Downloading sherpa-onnx iOS package v${SHERPA_VERSION}..."
curl -L --fail -o "$ARCHIVE" "$URL"
tar -xjf "$ARCHIVE" -C "$WORK_DIR"

SRC_ROOT="$WORK_DIR/build-ios-no-tts"
SHERPA_SRC="$SRC_ROOT/sherpa-onnx.xcframework"
ONNX_SRC="$(find "$SRC_ROOT/ios-onnxruntime" -maxdepth 3 -type d -name onnxruntime.xcframework | head -n 1)"

if [ ! -d "$SHERPA_SRC" ]; then
  echo "sherpa-onnx.xcframework was not found in archive" >&2
  exit 1
fi

if [ -z "$ONNX_SRC" ] || [ ! -d "$ONNX_SRC" ]; then
  echo "onnxruntime.xcframework was not found in archive" >&2
  exit 1
fi

rm -rf "$PKG_DIR/sherpa-onnx.xcframework" "$PKG_DIR/onnxruntime.xcframework"
cp -R "$SHERPA_SRC" "$PKG_DIR/"
cp -R "$ONNX_SRC" "$PKG_DIR/"

SHERPA_XC="$PKG_DIR/sherpa-onnx.xcframework"
ONNX_XC="$PKG_DIR/onnxruntime.xcframework"

# The upstream archive does not include module maps/headers in the per-arch
# folders expected by this package, so patch them in.
for arch in ios-arm64 ios-arm64_x86_64-simulator; do
  mkdir -p "$SHERPA_XC/$arch/Headers"
  cp "$SHERPA_XC/Headers/sherpa-onnx/c-api/c-api.h" "$SHERPA_XC/$arch/Headers/c-api.h"
  cp "$SHERPA_XC/Headers/cargs.h" "$SHERPA_XC/$arch/Headers/cargs.h"
  cat > "$SHERPA_XC/$arch/Headers/module.modulemap" <<'EOF'
module sherpa_onnx {
    header "c-api.h"
    export *
}
EOF

  mkdir -p "$ONNX_XC/$arch/Headers"
  cat > "$ONNX_XC/$arch/Headers/module.modulemap" <<'EOF'
module onnxruntime {
    export *
}
EOF
done

PLIST="$SHERPA_XC/Info.plist"
for index in 0 1; do
  /usr/libexec/PlistBuddy -c "Add :AvailableLibraries:${index}:HeadersPath string Headers" "$PLIST" 2>/dev/null || \
    /usr/libexec/PlistBuddy -c "Set :AvailableLibraries:${index}:HeadersPath Headers" "$PLIST"
done

echo "SherpaOnnxKit iOS dependencies prepared."
