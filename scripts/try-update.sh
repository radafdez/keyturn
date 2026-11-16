#!/bin/bash
# Runs a real Sparkle update on this Mac, start to finish, without touching
# your accounts, your settings or the real feed:
#
#     scripts/try-update.sh
#
# It builds two copies of the app (9.0.0 and 9.0.1) with their own bundle id,
# in demo mode, signed with a throwaway key that never goes to the Keychain.
# It serves a signed feed on 127.0.0.1, opens 9.0.0, waits for Sparkle to
# fetch 9.0.1, quits it so the update installs, and checks the result. Then it
# offers a feed edited after signing, and a zip swapped behind a valid feed:
# both must be refused.
#
# Hace una actualización real de Sparkle en este Mac, de principio a fin, sin
# tocar tus cuentas, tus ajustes ni el feed real. Construye dos copias de la
# app (9.0.0 y 9.0.1) con su propio bundle id, en modo demo, firmadas con una
# clave de usar y tirar que nunca va al Llavero. Sirve un feed firmado en
# 127.0.0.1, abre la 9.0.0, espera a que Sparkle traiga la 9.0.1, la cierra
# para que se instale y comprueba el resultado. Después ofrece un feed tocado
# tras firmarlo y un zip cambiado tras un feed válido: los dos deben rechazarse.
set -euo pipefail
cd "$(dirname "$0")/.."

id="com.raisapp.keyturn.updatetest"
port="${PORT:-8765}"
work="$(mktemp -d)"
server=""
cleanup() {
  osascript -e "quit app id \"$id\"" 2>/dev/null || true
  [ -n "$server" ] && { kill "$server" 2>/dev/null; wait "$server" 2>/dev/null; } || true
  defaults delete "$id" 2>/dev/null || true
  rm -rf "$work" ~/Library/Caches/"$id" ~/Library/HTTPStorages/"$id"* ~/Library/Preferences/"$id".plist
}
trap cleanup EXIT
quiet() { grep -v libSwiftScan || true; }

[ -d "dist/Keyturn.app" ] || ./scripts/build-app.sh

# A throwaway key pair, in files. / Un par de claves de usar y tirar, en ficheros.
cat > "$work/keys.swift" <<'SWIFT'
import CryptoKit
import Foundation
let key = Curve25519.Signing.PrivateKey()
print(key.rawRepresentation.base64EncodedString())
print(key.publicKey.rawRepresentation.base64EncodedString())
SWIFT
keys="$(swift "$work/keys.swift" 2> /dev/null)"
private_key="$(sed -n 1p <<< "$keys")"
public_key="$(sed -n 2p <<< "$keys")"

copy() { # <folder> <version> <build>
  local app="$1/Keyturn.app" plist="$1/Keyturn.app/Contents/Info.plist"
  rm -rf "$1"; mkdir -p "$1"
  ditto "dist/Keyturn.app" "$app"
  for command in "Set :CFBundleShortVersionString $2" "Set :CFBundleVersion $3" "Set :CFBundleIdentifier $id"; do
    /usr/libexec/PlistBuddy -c "$command" "$plist"
  done
  # Delete, then add: `Set :Key bool true` would store false, quietly turning
  # the protections under test off. / Borrar y añadir: `Set :Clave bool true`
  # guardaría false y apagaría sin avisar las protecciones que se prueban.
  local entry
  for entry in "KeyturnDemo bool true" "SUFeedURL string http://127.0.0.1:$port/appcast.xml" \
               "SUPublicEDKey string $public_key" "SURequireSignedFeed bool true" \
               "SUVerifyUpdateBeforeExtraction bool true" "SUEnableAutomaticChecks bool true" \
               "SUAutomaticallyUpdate bool true"; do
    /usr/libexec/PlistBuddy -c "Delete :${entry%% *}" "$plist" 2> /dev/null || true
    /usr/libexec/PlistBuddy -c "Add :$entry" "$plist"
  done
  for entry in SURequireSignedFeed SUVerifyUpdateBeforeExtraction; do
    [ "$(/usr/libexec/PlistBuddy -c "Print :$entry" "$plist")" = true ] || { echo "   FAIL: $entry is off in the copy"; exit 1; }
  done
  codesign --force --sign - "$app" 2> /dev/null
}
installed() { /usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$work/installed/Keyturn.app/Contents/Info.plist"; }
round() { # Opens the installed copy, lets Sparkle check, quits it so an update installs.
  defaults delete "$id" SULastCheckTime 2> /dev/null || true
  open "$work/installed/Keyturn.app"
  sleep 40
  osascript -e "quit app id \"$id\"" 2> /dev/null || true
  sleep 15
}
publish() { # <zip> → a signed appcast.xml in the served folder
  SPARKLE_PRIVATE_KEY="$private_key" ./scripts/make-appcast.sh "$1" "$work/notes.md" \
    "http://127.0.0.1:$port/$(basename "$1")" | quiet
  mv appcast.xml "$work/served/appcast.xml"
}

mkdir -p "$work/served"
printf '### Added\n\n- A test update.\n' > "$work/notes.md"
copy "$work/installed" 9.0.0 1000
copy "$work/new" 9.0.1 1001
(cd "$work/new" && ditto -c -k --keepParent "Keyturn.app" "$work/served/Keyturn-9.0.1.zip")
publish "$work/served/Keyturn-9.0.1.zip"
(cd "$work/served" && exec python3 -m http.server "$port" --bind 127.0.0.1 > /dev/null 2>&1) &
server=$!
sleep 1

echo "1. A genuine update, 9.0.0 → 9.0.1"
round
[ "$(installed)" = 9.0.1 ] || { echo "   FAIL: still $(installed)"; exit 1; }
xattr -lr "$work/installed/Keyturn.app" | grep -q quarantine && { echo "   FAIL: the update is quarantined"; exit 1; }
codesign --verify --deep --strict "$work/installed/Keyturn.app"
echo "   ok: 9.0.1 installed, signature valid, nothing quarantined"

echo "2. A feed edited after it was signed"
copy "$work/new" 9.0.2 1002
rm -f "$work/served/Keyturn-9.0.2.zip"
(cd "$work/new" && ditto -c -k --keepParent "Keyturn.app" "$work/served/Keyturn-9.0.2.zip")
publish "$work/served/Keyturn-9.0.2.zip"
cp "$work/served/appcast.xml" "$work/appcast-good.xml"
sed -i '' 's/Keyturn 9.0.2</Keyturn 9.0.2 (edited)</' "$work/served/appcast.xml"
round
[ "$(installed)" = 9.0.1 ] || { echo "   FAIL: the edited feed installed $(installed)"; exit 1; }
echo "   ok: refused"

echo "3. A valid feed, but the zip was swapped"
cp "$work/appcast-good.xml" "$work/served/appcast.xml"
echo swapped > "$work/new/Keyturn.app/Contents/Resources/swapped.txt"
codesign --force --sign - "$work/new/Keyturn.app" 2> /dev/null
rm -f "$work/served/Keyturn-9.0.2.zip"
(cd "$work/new" && ditto -c -k --keepParent "Keyturn.app" "$work/served/Keyturn-9.0.2.zip")
round
[ "$(installed)" = 9.0.1 ] || { echo "   FAIL: the swapped zip installed $(installed)"; exit 1; }
echo "   ok: refused"

echo "Updates work, and only signed ones get in."
