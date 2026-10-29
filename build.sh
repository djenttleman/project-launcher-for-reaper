#!/usr/bin/env bash
# Construye y firma (ad-hoc) ReaSet Selector.app en ~/Applications
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
APP="$HOME/Applications/Project Launcher.app"
BUILD="$HERE/.build"
BIN="$BUILD/ProjectLauncher"

rm -rf "$BUILD"; mkdir -p "$BUILD"

echo "== compilando =="
swiftc -O -parse-as-library \
  -target arm64-apple-macos13.0 \
  -o "$BIN" "$HERE/Selector.swift" \
  -framework Cocoa -framework WebKit

echo "== armando bundle =="
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/ProjectLauncher"
cp "$HERE/Resources/selector.html" "$HERE/Resources/selector.css" "$HERE/Resources/reaset-kit.css" "$APP/Contents/Resources/"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Project Launcher</string>
  <key>CFBundleDisplayName</key><string>Project Launcher</string>
  <key>CFBundleIdentifier</key><string>com.reaset.selector</string>
  <key>CFBundleExecutable</key><string>ProjectLauncher</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.2.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>LSApplicationCategoryType</key><string>public.app-category.music</string>
  <key>NSHumanReadableCopyright</key><string>ReaSet</string>
  <key>NSDocumentsFolderUsageDescription</key><string>Project Launcher lee tus archivos .rpp para mostrar regiones, pistas y copias de seguridad.</string>
  <key>NSDesktopFolderUsageDescription</key><string>Project Launcher lee tus archivos .rpp para mostrar regiones, pistas y copias de seguridad.</string>
  <key>NSDownloadsFolderUsageDescription</key><string>Project Launcher lee tus archivos .rpp para mostrar regiones, pistas y copias de seguridad.</string>
  <key>NSRemovableVolumesUsageDescription</key><string>Project Launcher lee proyectos .rpp guardados en discos externos.</string>
  <key>NSNetworkVolumesUsageDescription</key><string>Project Launcher lee proyectos .rpp guardados en volúmenes de red.</string>
</dict>
</plist>
PLIST

echo "== firmando ad-hoc =="
# Firma: si hay una identidad local "Auri Local Signing" se usa esa (el permiso
# de Accesibilidad sobrevive a las recompilaciones, porque la huella es del
# certificado y no del binario). Si no existe, ad-hoc como siempre.
if codesign --force --deep --sign "Auri Local Signing" "$APP" >/dev/null 2>&1; then
  echo "  firma: Auri Local Signing (local, permisos estables)"
else
  codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true
  echo "  firma: ad-hoc"
fi

echo "== listo =="
ls -la "$APP/Contents/MacOS" "$APP/Contents/Resources"
