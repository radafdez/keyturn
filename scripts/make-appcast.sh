#!/bin/bash
# Writes appcast.xml for one release, the feed Sparkle reads, and signs both
# the zip and the feed with the project's EdDSA key.
#
#     SPARKLE_PRIVATE_KEY=… scripts/make-appcast.sh <zip> <notes.md> [download-url]
#
# The key comes from the environment and goes to sign_update through stdin,
# never as an argument, so it does not show up in the process list. The
# version and build are read from the app inside the zip, so the feed cannot
# announce a version the zip does not carry. The download URL defaults to the
# GitHub release of that version; a local test passes its own.
#
# Escribe appcast.xml de una versión, el feed que lee Sparkle, y firma el zip y
# el feed con la clave EdDSA del proyecto.
#
# La clave sale del entorno y llega a sign_update por stdin, nunca como
# argumento, para que no aparezca en la lista de procesos. La versión y el build
# se leen de la app que hay dentro del zip, así que el feed no puede anunciar
# una versión que el zip no lleva. La URL de descarga es, por defecto, la de la
# versión en GitHub; una prueba local pasa la suya.
set -euo pipefail
cd "$(dirname "$0")/.."

zip="${1:?Usage: scripts/make-appcast.sh <zip> <notes.md> [download-url]}"
notes="${2:?Usage: scripts/make-appcast.sh <zip> <notes.md> [download-url]}"
: "${SPARKLE_PRIVATE_KEY:?Set SPARKLE_PRIVATE_KEY to the private EdDSA key}"
sign_update=".build/artifacts/sparkle/Sparkle/bin/sign_update"
[ -x "$sign_update" ] || { echo "No $sign_update: run scripts/build-app.sh first" >&2; exit 1; }

scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
ditto -x -k "$zip" "$scratch"
plist="$scratch/Keyturn.app/Contents/Info.plist"
read_key() { /usr/libexec/PlistBuddy -c "Print $1" "$plist"; }
version="$(read_key CFBundleShortVersionString)"
build="$(read_key CFBundleVersion)"
minimum="$(read_key LSMinimumSystemVersion)"
public_key="$(read_key SUPublicEDKey 2>/dev/null)" || { echo "The app in $zip has no SUPublicEDKey: it could never check an update" >&2; exit 1; }

url="${3:-https://github.com/radafdez/keyturn/releases/download/v$version/$(basename "$zip")}"
release="https://github.com/radafdez/keyturn/releases/tag/v$version"
grep -q ']]>' "$notes" && { echo "$notes contains ]]>, which would end the CDATA block" >&2; exit 1; }

signature="$(printf '%s' "$SPARKLE_PRIVATE_KEY" | "$sign_update" --ed-key-file - "$zip")"
case "$signature" in
  *sparkle:edSignature=*) ;;
  *) echo "sign_update did not return a signature" >&2; exit 1 ;;
esac

edsignature="$(printf '%s' "$signature" | sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p')"
swift scripts/check-signature.swift "$public_key" "$zip" "$edsignature" 2>&1 | grep -v libSwiftScan

cat > appcast.xml <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Keyturn</title>
    <link>https://github.com/radafdez/keyturn</link>
    <item>
      <title>Keyturn $version</title>
      <pubDate>$(LC_ALL=C date -u "+%a, %d %b %Y %H:%M:%S +0000")</pubDate>
      <sparkle:version>$build</sparkle:version>
      <sparkle:shortVersionString>$version</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>$minimum</sparkle:minimumSystemVersion>
      <sparkle:fullReleaseNotesLink>$release</sparkle:fullReleaseNotesLink>
      <description sparkle:format="markdown"><![CDATA[
$(cat "$notes")
]]></description>
      <enclosure url="$url" type="application/octet-stream" $signature />
    </item>
  </channel>
</rss>
XML

# The feed carries its own signature: the app is built with SURequireSignedFeed.
# El feed lleva su propia firma: la app se construye con SURequireSignedFeed.
printf '%s' "$SPARKLE_PRIVATE_KEY" | "$sign_update" --ed-key-file - appcast.xml
echo "appcast.xml: $version ($build) → $url"
