#!/usr/bin/env bash
# Creates the self-signed "OmniIsland Signing" code-signing certificate once,
# and stores it where builds can use it:
#   * GitHub Actions secrets MACOS_CERT_P12 / MACOS_CERT_PASSWORD
#     (set automatically when the GitHub CLI `gh` is installed and logged in)
#   * your login keychain, so local `scripts/bundle.sh` builds match CI builds
#
# Because every build is then signed by the same certificate, macOS keeps the
# Accessibility permission across updates. Run this on your Mac, once.
#
# Usage: scripts/create-signing-cert.sh [owner/repo]
set -euo pipefail

REPO="${1:-jadewisemann/dynamic-island}"
NAME="OmniIsland Signing"
OUT="${OMNI_ISLAND_CERT_DIR:-$HOME/.omni-island-signing}"

if security find-identity -p codesigning 2>/dev/null | grep -q "\"$NAME\""; then
  echo "A '$NAME' certificate is already in your keychain."
  echo "Delete it in Keychain Access first if you really want a new one"
  echo "(a new certificate makes macOS ask for permissions once more)."
  exit 1
fi

mkdir -p "$OUT"
chmod 700 "$OUT"
cd "$OUT"

PASSWORD="$(openssl rand -base64 24)"

cat > cert.cnf <<CNF
[ req ]
distinguished_name = dn
x509_extensions = ext
prompt = no
[ dn ]
CN = $NAME
[ ext ]
basicConstraints = critical, CA:FALSE
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
subjectKeyIdentifier = hash
CNF

openssl req -x509 -newkey rsa:2048 -nodes -days 7300 \
  -keyout key.pem -out cert.pem -config cert.cnf

# OpenSSL 3 needs -legacy so that macOS `security import` can read the file.
LEGACY=()
if openssl version | grep -q '^OpenSSL 3'; then LEGACY=(-legacy); fi
openssl pkcs12 -export ${LEGACY[@]+"${LEGACY[@]}"} \
  -inkey key.pem -in cert.pem -name "$NAME" \
  -out OmniIsland-signing.p12 -passout "pass:$PASSWORD"
rm -f key.pem cert.cnf
chmod 600 OmniIsland-signing.p12

# Local builds.
security import OmniIsland-signing.p12 -k "$HOME/Library/Keychains/login.keychain-db" \
  -P "$PASSWORD" -T /usr/bin/codesign
echo "Imported '$NAME' into your login keychain."

# CI builds.
if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
  base64 -i OmniIsland-signing.p12 | gh secret set MACOS_CERT_P12 --repo "$REPO"
  printf '%s' "$PASSWORD" | gh secret set MACOS_CERT_PASSWORD --repo "$REPO"
  echo "Saved MACOS_CERT_P12 and MACOS_CERT_PASSWORD to $REPO's Actions secrets."
else
  echo
  echo "GitHub CLI not available. Add two secrets by hand at"
  echo "  https://github.com/$REPO/settings/secrets/actions"
  echo "MACOS_CERT_P12      = the output of: base64 -i '$OUT/OmniIsland-signing.p12'"
  echo "MACOS_CERT_PASSWORD = $PASSWORD"
fi

printf '%s\n' "$PASSWORD" > password.txt
chmod 600 password.txt
echo
echo "Backup kept in $OUT (keep it private; you need it only to set up CI again)."
