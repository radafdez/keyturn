#!/bin/bash
# Builds `dist/Supabase Switch.app` and `dist/sbswitch`.
# With `--install`, also copies the app to /Applications and links `sbswitch`
# next to the Supabase CLI.
#
# Construye `dist/Supabase Switch.app` y `dist/sbswitch`.
# Con `--install`, además copia la app a /Applications y enlaza `sbswitch`
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
name="Supabase Switch"
bundle="dist/$name.app"

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
  cp "$bin/SupabaseSwitch" "$bin/sbswitch" "$slices/$architecture/"
done

rm -rf "$bundle"
mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources"
cp Resources/AppIcon.icns "$bundle/Contents/Resources/AppIcon.icns"
# The build number counts commits, so two builds of one version can be told apart.
# El número de build cuenta commits, para distinguir dos builds de una versión.
build="$(git rev-list --count HEAD 2>/dev/null || echo 1)"
built="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
for product in SupabaseSwitch sbswitch; do
  lipo -create "$slices/arm64/$product" "$slices/x86_64/$product" \
    -output "$bundle/Contents/MacOS/$product"
done
cp "$bundle/Contents/MacOS/sbswitch" dist/sbswitch

cat > "$bundle/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>$name</string>
  <key>CFBundleDisplayName</key><string>$name</string>
  <key>CFBundleIdentifier</key><string>com.raisapp.supabase-switch</string>
  <key>CFBundleExecutable</key><string>SupabaseSwitch</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$version</string>
  <key>CFBundleVersion</key><string>$build</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>SupabaseSwitchBuildDate</key><string>$built</string>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleLocalizations</key><array><string>en</string><string>es</string></array>
  <key>NSHumanReadableCopyright</key><string>Copyright © 2026 RAIS LLC. MIT License.</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

# Ad-hoc signature: enough to run on this Mac. The tokens do not depend on it:
# they are stored through /usr/bin/security, so a rebuild keeps reading them.
# Firma ad hoc: basta para ejecutarla en este Mac. Los tokens no dependen de
# ella: se guardan a través de /usr/bin/security, así que una recompilación los
# sigue leyendo.
codesign --force --sign - "$bundle/Contents/MacOS/sbswitch"
codesign --force --sign - "$bundle"
codesign --force --sign - dist/sbswitch

echo "Built: $bundle ($version)"

if $install; then
  target="/Applications/$name.app"
  pkill -x SupabaseSwitch 2>/dev/null || true
  rm -rf "$target"
  cp -R "$bundle" "$target"
  echo "Installed: $target"

  for directory in /opt/homebrew/bin /usr/local/bin; do
    if [ -d "$directory" ] && [ -w "$directory" ]; then
      ln -sf "$target/Contents/MacOS/sbswitch" "$directory/sbswitch"
      echo "Linked: $directory/sbswitch"
      break
    fi
  done

  open "$target"
fi
