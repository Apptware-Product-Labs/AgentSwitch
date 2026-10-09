#!/usr/bin/env bash
# One-time: creates a self-signed code-signing certificate "AgentSwitch Dev" in your
# login keychain. Signing with a stable identity (instead of ad-hoc) means macOS keeps
# the Accessibility grant across rebuilds. Run this yourself; it touches your keychain.
set -euo pipefail
NAME="AgentSwitch Dev"

if security find-identity -v -p codesigning 2>/dev/null | grep -q "$NAME"; then
  echo "Identity \"$NAME\" already exists."; exit 0
fi

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/cert.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
basicConstraints = critical, CA:false
EOF
openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$TMP/cert.cnf" \
  -keyout "$TMP/key.pem" -out "$TMP/cert.pem" >/dev/null 2>&1
# macOS can't read OpenSSL 3's default PKCS12 encryption; use the older algorithms.
openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" -out "$TMP/cert.p12" \
  -passout pass:agentswitch -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1

KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
security import "$TMP/cert.p12" -k "$KEYCHAIN" -P agentswitch -T /usr/bin/codesign >/dev/null
# Trust it for code signing (you'll be asked for your login password).
security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$TMP/cert.pem"

echo "Created \"$NAME\". scripts/build_app.sh will use it automatically."
echo "If macOS still shows a stale AgentSwitch entry under Accessibility, remove it and re-add /Applications/AgentSwitch.app."
