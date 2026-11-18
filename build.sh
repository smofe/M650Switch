#!/bin/zsh
# Builds M650Switch.app and installs it to ~/Applications.
#   ./build.sh            native build, installed to ~/Applications
#   ./build.sh --release  universal build in ./build, not installed
#
# The app is signed with a self-signed certificate that is created once in your
# login keychain. A stable signature lets macOS keep the Bluetooth and
# Accessibility permissions across rebuilds (ad-hoc signatures change every build).
set -euo pipefail
cd "${0:A:h}"

APP=build/M650Switch.app
IDENTITY="M650Switch Local Signing"

create_signing_identity() {
  echo "Creating code-signing certificate '$IDENTITY' in your login keychain…"
  local tmp; tmp=$(mktemp -d)
  trap "rm -rf '$tmp'" EXIT
  cat > "$tmp/cert.cnf" <<EOF
[req]
distinguished_name = dn
prompt = no
x509_extensions = ext
[dn]
CN = $IDENTITY
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
EOF
  openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$tmp/cert.cnf" \
    -keyout "$tmp/key.pem" -out "$tmp/cert.pem" 2>/dev/null
  # The PKCS#12 password only protects this temporary file.
  openssl pkcs12 -export -legacy -inkey "$tmp/key.pem" -in "$tmp/cert.pem" \
    -out "$tmp/identity.p12" -passout pass:temp 2>/dev/null \
    || openssl pkcs12 -export -inkey "$tmp/key.pem" -in "$tmp/cert.pem" \
         -out "$tmp/identity.p12" -passout pass:temp
  security import "$tmp/identity.p12" -k ~/Library/Keychains/login.keychain-db \
    -P temp -T /usr/bin/codesign >/dev/null
}

echo "Compiling…"
rm -rf build
mkdir -p "$APP/Contents/MacOS"
if [[ "${1:-}" == "--release" ]]; then
  # Universal binary (Apple silicon + Intel) for distribution.
  for arch in arm64 x86_64; do
    swiftc -O -parse-as-library -target "$arch-apple-macos14.0" -o "build/M650Switch-$arch" Sources/*.swift
  done
  lipo -create build/M650Switch-arm64 build/M650Switch-x86_64 -output "$APP/Contents/MacOS/M650Switch"
else
  swiftc -O -parse-as-library -o "$APP/Contents/MacOS/M650Switch" Sources/*.swift
fi
cp Resources/Info.plist "$APP/Contents/Info.plist"

security find-certificate -c "$IDENTITY" >/dev/null 2>&1 || create_signing_identity
HASH=$(security find-certificate -c "$IDENTITY" -Z | awk '/SHA-1/ { print $3 }')
codesign --force --sign "$HASH" "$APP"

if [[ "${1:-}" == "--release" ]]; then
  echo "Built $APP (not installed)"
  exit 0
fi

echo "Installing to ~/Applications…"
pkill -x M650Switch 2>/dev/null && sleep 1 || true
mkdir -p ~/Applications
rm -rf ~/Applications/M650Switch.app
cp -R "$APP" ~/Applications/
echo "Done. Start it with: open ~/Applications/M650Switch.app"
