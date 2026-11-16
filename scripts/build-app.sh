#!/bin/bash
# Builds `dist/Keyturn.app` and `dist/keyturn`.
# With `--install`, also copies the app to /Applications and links `keyturn`
# next to the Supabase CLI.
#
# Construye `dist/Keyturn.app` y `dist/keyturn`.
# Con `--install`, además copia la app a /Applications y enlaza `keyturn`
# junto al CLI de Supabase.
set -euo pipefail
cd "$(dirname "$0")/.."

install=false
for argument in "$@"; do
  case "$argument" in
    --install) install=true ;;
    *) echo "Usage: scripts/build-app.sh [--install]" >&2; exit 2 ;;
  esac
done

version="$(sed -n 's/.*switchVersion = "\(.*\)".*/\1/p' Sources/SwitchCore/Version.swift)"
[ -n "$version" ] || { echo "No version in Sources/SwitchCore/Version.swift" >&2; exit 1; }
name="Keyturn"
bundle="dist/$name.app"

# Updates: the feed is the appcast.xml of the latest GitHub release, and the
# public half of the project's EdDSA key checks it. Without the key file the
# app is built without Sparkle's settings and points to the releases page.
# Actualizaciones: el feed es el appcast.xml de la última versión de GitHub, y
# la mitad pública de la clave EdDSA del proyecto lo comprueba. Sin el fichero
# de la clave, la app se construye sin los ajustes de Sparkle y remite a la
# página de versiones.
feed="https://github.com/radafdez/keyturn/releases/latest/download/appcast.xml"
public_key="$(tr -d '[:space:]' < Resources/sparkle-public-key.txt 2>/dev/null || true)"
sparkle_keys=""
if [ -n "$public_key" ]; then
  sparkle_keys="  <key>SUFeedURL</key><string>$feed</string>
  <key>SUPublicEDKey</key><string>$public_key</string>
  <key>SURequireSignedFeed</key><true/>
  <key>SUVerifyUpdateBeforeExtraction</key><true/>
  <key>SUEnableSystemProfiling</key><false/>"
else
  echo "warning: no Resources/sparkle-public-key.txt, building without updates" >&2
fi

# Universal binary (Apple Silicon and Intel): one build per architecture,
# joined with lipo. Both `--arch` in one build need Xcode on older Swift, and
# newer Swift puts every architecture in the same folder, so each result is
# copied out before the next build.
# Binario universal (Apple Silicon e Intel): una compilación por arquitectura,
# unidas con lipo. Con Swift antiguo, las dos `--arch` a la vez necesitan Xcode,
# y el Swift nuevo deja todas las arquitecturas en la misma carpeta: por eso se
# copia cada resultado antes de la siguiente.
slices=".build/slices"
rm -rf "$slices"
for architecture in arm64 x86_64; do
  swift build -c release --arch "$architecture"
  bin="$(swift build -c release --arch "$architecture" --show-bin-path)"
  mkdir -p "$slices/$architecture"
  cp "$bin/KeyturnApp" "$bin/keyturn" "$slices/$architecture/"
done

rm -rf "$bundle"
mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources" "$bundle/Contents/Frameworks"
# The framework is already universal; ditto keeps its symlinks and signature.
# El framework ya es universal; ditto conserva sus enlaces y su firma.
ditto "$(swift build -c release --arch arm64 --show-bin-path)/Sparkle.framework" "$bundle/Contents/Frameworks/Sparkle.framework"
# Sparkle is MIT too: its notice travels with every copy of the app.
# Sparkle también es MIT: su aviso viaja con cada copia de la app.
cp .build/artifacts/sparkle/Sparkle/LICENSE "$bundle/Contents/Resources/Sparkle-LICENSE.txt"
cp Resources/AppIcon.icns "$bundle/Contents/Resources/AppIcon.icns"
cp Resources/MenuBarIcon.png Resources/MenuBarIcon@2x.png "$bundle/Contents/Resources/"
# The build number counts commits, so two builds of one version can be told apart.
# El número de build cuenta commits, para distinguir dos builds de una versión.
build="$(git rev-list --count HEAD 2>/dev/null || echo 1)"
built="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
for product in KeyturnApp keyturn; do
  lipo -create "$slices/arm64/$product" "$slices/x86_64/$product" \
    -output "$bundle/Contents/MacOS/$product"
done
cp "$bundle/Contents/MacOS/keyturn" dist/keyturn
# SwiftPM only looks next to the executable; the framework lives in Frameworks.
# SwiftPM solo busca junto al ejecutable; el framework vive en Frameworks.
install_name_tool -add_rpath "@executable_path/../Frameworks" "$bundle/Contents/MacOS/KeyturnApp"

cat > "$bundle/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>$name</string>
  <key>CFBundleDisplayName</key><string>$name</string>
  <key>CFBundleIdentifier</key><string>com.raisapp.keyturn</string>
  <key>CFBundleExecutable</key><string>KeyturnApp</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$version</string>
  <key>CFBundleVersion</key><string>$build</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>KeyturnBuildDate</key><string>$built</string>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleLocalizations</key><array><string>en</string><string>es</string></array>
  <key>NSHumanReadableCopyright</key><string>Copyright © 2026 Radames Fernandez. MIT License.</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
$sparkle_keys
</dict>
</plist>
PLIST

# Ad-hoc signature: enough to run on this Mac. The tokens do not depend on it:
# they are stored through /usr/bin/security, so a rebuild keeps reading them.
# Firma ad hoc: basta para ejecutarla en este Mac. Los tokens no dependen de
# ella: se guardan a través de /usr/bin/security, así que una recompilación los
# sigue leyendo.
codesign --force --sign - "$bundle/Contents/MacOS/keyturn"
codesign --force --sign - "$bundle"
codesign --verify --deep --strict "$bundle"
codesign --force --sign - dist/keyturn

echo "Built: $bundle ($version)"

if $install; then
  target="/Applications/$name.app"
  pkill -x KeyturnApp 2>/dev/null || true
  rm -rf "$target"
  cp -R "$bundle" "$target"
  echo "Installed: $target"

  for directory in /opt/homebrew/bin /usr/local/bin; do
    if [ -d "$directory" ] && [ -w "$directory" ]; then
      ln -sf "$target/Contents/MacOS/keyturn" "$directory/keyturn"
      echo "Linked: $directory/keyturn"
      break
    fi
  done

  open "$target"
fi
