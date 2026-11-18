#!/bin/zsh
# Publishes a GitHub release with a prebuilt, universal M650Switch.zip.
#
# Bump CFBundleShortVersionString / CFBundleVersion in Resources/Info.plist first.
# Always release from the same machine: users' Bluetooth and Accessibility grants
# are tied to the signing certificate, so a different certificate resets them.
set -euo pipefail
cd "${0:A:h}"

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)
TAG="v$VERSION"

if [[ -n "$(git status --porcelain)" ]]; then
  echo "Commit your changes first." >&2
  exit 1
fi

./build.sh --release
ditto -c -k --keepParent build/M650Switch.app build/M650Switch.zip

gh release create "$TAG" build/M650Switch.zip \
  --title "M650Switch $VERSION" \
  --generate-notes
