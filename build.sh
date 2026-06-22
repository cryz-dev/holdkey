#!/usr/bin/env bash
set -euo pipefail

APP_NAME="HoldKey"
BUNDLE="${APP_NAME}.app"
BIN_DIR=".build/release"

SIGN_ID="HoldKey Local Signing"
KC_NAME="holdkey-signing"
KC="${HOME}/Library/Keychains/${KC_NAME}.keychain-db"
KC_PASS="holdkey-local"          # password for the DEDICATED keychain (not your login pw)
P12_PASS="holdkey"

# ──────────────────────────────────────────────────────────────
# 1. Stable, fully non-interactive code-signing identity.
#
#    Ad-hoc signing changes the binary's cdhash on every rebuild,
#    invalidating the macOS Accessibility (TCC) grant each time.
#    We use a persistent self-signed cert kept in a DEDICATED keychain
#    whose password we control, with the key's partition list opened to
#    codesign — so signing never shows a keychain password dialog and the
#    code's designated requirement stays constant across rebuilds.
# ──────────────────────────────────────────────────────────────
if [ ! -f "${KC}" ]; then
    echo "🔐 Creating dedicated signing keychain..."
    security create-keychain -p "${KC_PASS}" "${KC_NAME}.keychain-db"
    security set-keychain-settings "${KC_NAME}.keychain-db"   # no auto-lock timeout
fi
security unlock-keychain -p "${KC_PASS}" "${KC_NAME}.keychain-db"

# Add the dedicated keychain to the search list (append, keep existing ones)
CURRENT_KC="$(security list-keychains -d user | sed 's/[" ]//g' | tr '\n' ' ')"
if [[ "${CURRENT_KC}" != *"${KC_NAME}"* ]]; then
    # shellcheck disable=SC2086
    security list-keychains -d user -s ${CURRENT_KC} "${KC}"
fi

if ! security find-identity -p codesigning "${KC}" | grep -q "${SIGN_ID}"; then
    echo "🔐 Generating self-signed identity '${SIGN_ID}'..."
    TMP="$(mktemp -d)"
    cat > "${TMP}/openssl.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = v3
prompt = no
[dn]
CN = ${SIGN_ID}
[v3]
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
basicConstraints = critical, CA:false
EOF
    openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
        -keyout "${TMP}/key.pem" -out "${TMP}/cert.pem" \
        -config "${TMP}/openssl.cnf" >/dev/null 2>&1
    # -legacy + password: OpenSSL 3.x's default PKCS12 MAC is rejected by Apple.
    openssl pkcs12 -export -legacy -inkey "${TMP}/key.pem" -in "${TMP}/cert.pem" \
        -out "${TMP}/id.p12" -passout "pass:${P12_PASS}" -name "${SIGN_ID}" >/dev/null 2>&1
    security import "${TMP}/id.p12" -k "${KC}" -P "${P12_PASS}" \
        -A -T /usr/bin/codesign >/dev/null 2>&1
    # THE key step: allow codesign to use the private key WITHOUT prompting.
    security set-key-partition-list -S apple-tool:,apple:,codesign: \
        -s -k "${KC_PASS}" "${KC}" >/dev/null 2>&1
    rm -rf "${TMP}"
    echo "   ✓ Identity ready (non-interactive)."
fi

# ──────────────────────────────────────────────────────────────
# 2. Build
# ──────────────────────────────────────────────────────────────
echo "🔨 Building ${APP_NAME}..."
swift build -c release

# ──────────────────────────────────────────────────────────────
# 3. Assemble .app bundle
# ──────────────────────────────────────────────────────────────
echo "📦 Creating .app bundle..."
rm -rf "${BUNDLE}"
mkdir -p "${BUNDLE}/Contents/MacOS"
mkdir -p "${BUNDLE}/Contents/Resources"
cp "${BIN_DIR}/${APP_NAME}" "${BUNDLE}/Contents/MacOS/${APP_NAME}"
cp "Info.plist"             "${BUNDLE}/Contents/Info.plist"

# App icon (regenerate if missing, then bundle it)
if [ ! -f "AppIcon.icns" ] && [ -f "tools/make_icon.swift" ]; then
    echo "🎨 Generating app icon..."
    swift tools/make_icon.swift >/dev/null 2>&1 && iconutil -c icns AppIcon.iconset -o AppIcon.icns
fi
if [ -f "AppIcon.icns" ]; then
    cp "AppIcon.icns" "${BUNDLE}/Contents/Resources/AppIcon.icns"
fi

# ──────────────────────────────────────────────────────────────
# 4. Sign (non-interactive, stable identity)
# ──────────────────────────────────────────────────────────────
echo "✍️  Signing..."
codesign --force --keychain "${KC}" --sign "${SIGN_ID}" "${BUNDLE}"
codesign -v "${BUNDLE}" && echo "   ✓ Signature valid."

echo ""
echo "✅ Done!  Stable designated requirement:"
codesign -d -r- "${BUNDLE}" 2>&1 | grep designated | sed 's/^/   /'
