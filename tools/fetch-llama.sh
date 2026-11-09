#!/bin/sh
# Downloads the prebuilt llama.cpp xcframework used by the app into Vendor/ and checks its SHA-256.
# Run from the repo root: sh tools/fetch-llama.sh
set -eu

TAG="b12211"
SHA256="1f701c47b0e2f9410e1441960105e7d7ad1757f8a49e4063c6e792df31348a7a"
URL="https://github.com/ggml-org/llama.cpp/releases/download/${TAG}/llama-${TAG}-xcframework.zip"

mkdir -p Vendor
if [ -d Vendor/llama.xcframework ] && [ "$(cat Vendor/llama.version 2>/dev/null)" = "$TAG" ]; then
  echo "llama.xcframework ${TAG} already present"
  exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
echo "Downloading llama.cpp ${TAG} xcframework…"
curl -fsSL -o "$TMP/llama.zip" "$URL"
echo "${SHA256}  $TMP/llama.zip" | shasum -a 256 -c -
unzip -q "$TMP/llama.zip" -d "$TMP/unzipped"
FRAMEWORK="$(find "$TMP/unzipped" -maxdepth 3 -name 'llama.xcframework' -type d | head -1)"
[ -n "$FRAMEWORK" ] || { echo "llama.xcframework not found in the archive"; exit 1; }
rm -rf Vendor/llama.xcframework
mv "$FRAMEWORK" Vendor/llama.xcframework
echo "$TAG" > Vendor/llama.version
echo "Installed Vendor/llama.xcframework (${TAG})"
