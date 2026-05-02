#!/usr/bin/env bash
set -euo pipefail

# Creates a persistent self-signed code-signing identity in the user's login
# keychain so that LocalWhisperFlow keeps the same code signature across
# rebuilds. macOS TCC keys Accessibility / Microphone / Input Monitoring on
# the signing identity (when present) instead of the cdhash, so granting
# permission once stays valid across recompiles.
#
# Run this script ONCE per machine. It is safe to run repeatedly: it only
# creates the cert if it does not already exist.

IDENTITY_NAME="LocalWhisperFlow Dev"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -p codesigning -v "$KEYCHAIN" | grep -q "$IDENTITY_NAME"; then
  echo "Signing identity '$IDENTITY_NAME' already exists. Nothing to do."
  exit 0
fi

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

cat > "$WORK_DIR/req.cnf" <<EOF
[req]
distinguished_name = req_dn
req_extensions     = v3_req
prompt             = no

[req_dn]
CN = $IDENTITY_NAME

[v3_req]
basicConstraints       = critical, CA:false
keyUsage               = critical, digitalSignature
extendedKeyUsage       = critical, codeSigning
EOF

openssl req -x509 \
  -newkey rsa:2048 \
  -keyout "$WORK_DIR/key.pem" \
  -out "$WORK_DIR/cert.pem" \
  -days 3650 \
  -nodes \
  -config "$WORK_DIR/req.cnf" \
  -extensions v3_req

openssl pkcs12 -export \
  -out "$WORK_DIR/cert.p12" \
  -inkey "$WORK_DIR/key.pem" \
  -in "$WORK_DIR/cert.pem" \
  -password pass:

echo "Importing identity into login keychain. macOS may prompt for keychain password."
security import "$WORK_DIR/cert.p12" -k "$KEYCHAIN" -T /usr/bin/codesign -P ""
security set-key-partition-list -S apple-tool:,apple:,codesign: -k "" "$KEYCHAIN" >/dev/null 2>&1 || true

# Trust the cert so codesign accepts it without prompts.
security add-trusted-cert -d -r trustRoot -p codeSign -k "$KEYCHAIN" "$WORK_DIR/cert.pem" >/dev/null 2>&1 || true

echo "Signing identity '$IDENTITY_NAME' installed. You can now run ./script/build_and_run.sh."
