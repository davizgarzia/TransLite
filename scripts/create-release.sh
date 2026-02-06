#!/bin/bash

# Script para crear un release de TransLite con firma, DMG y notarización
# Uso: ./scripts/create-release.sh 1.1.0

set -e

VERSION=$1
DEVELOPER_ID="0FCEEAA4861A3809015D60D8BD083B396BD79016"
NOTARY_PROFILE="TransLite"

if [ -z "$VERSION" ]; then
    echo "Uso: $0 <version>"
    echo "Ejemplo: $0 1.1.0"
    exit 1
fi

echo "=== Creando release TransLite v$VERSION ==="
echo ""

# Rutas
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/TransLite"
RELEASE_DIR="$PROJECT_DIR/releases"
SPARKLE_BIN=$(find ~/Library/Developer/Xcode/DerivedData -name "sign_update" -path "*/artifacts/*" 2>/dev/null | head -1)

if [ -z "$SPARKLE_BIN" ]; then
    echo "Error: No se encontró sign_update de Sparkle"
    echo "Asegúrate de haber compilado el proyecto al menos una vez"
    exit 1
fi

# 1. Regenerar proyecto
echo "1/8. Regenerando proyecto..."
cd "$BUILD_DIR"
xcodegen generate 2>&1 | grep -E "(Created|error)" || true

# 2. Compilar
echo "2/8. Compilando..."
xcodebuild -project TransLite.xcodeproj -scheme TransLite -configuration Release clean build 2>&1 | grep -E "(BUILD|error:)" || true

# 3. Copiar app
echo "3/8. Preparando app..."
mkdir -p "$RELEASE_DIR"
APP_PATH=$(find ~/Library/Developer/Xcode/DerivedData/TransLite-*/Build/Products/Release -name "TransLite.app" -type d 2>/dev/null | head -1)

if [ -z "$APP_PATH" ]; then
    echo "Error: No se encontró la app compilada"
    exit 1
fi

rm -rf "$RELEASE_DIR/TransLite-$VERSION.app"
cp -R "$APP_PATH" "$RELEASE_DIR/TransLite-$VERSION.app"

# 4. Firmar la app (deep signing para frameworks incluidos)
echo "4/8. Firmando app con Developer ID..."
codesign --deep --force --options runtime --sign "$DEVELOPER_ID" "$RELEASE_DIR/TransLite-$VERSION.app"
codesign --verify --verbose "$RELEASE_DIR/TransLite-$VERSION.app"

# 5. Crear DMG
echo "5/8. Creando DMG..."
DMG_PATH="$RELEASE_DIR/TransLite-$VERSION.dmg"
rm -f "$DMG_PATH"

# Crear DMG temporal
hdiutil create -volname "TransLite $VERSION" -srcfolder "$RELEASE_DIR/TransLite-$VERSION.app" -ov -format UDZO "$DMG_PATH"

# 6. Firmar DMG
echo "6/8. Firmando DMG..."
codesign --force --sign "$DEVELOPER_ID" "$DMG_PATH"

# 7. Notarizar
echo "7/8. Notarizando con Apple (esto puede tardar 2-5 minutos)..."
xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait

# Staple el ticket
echo "    Aplicando staple..."
xcrun stapler staple "$DMG_PATH"

# 8. Firmar para Sparkle
echo "8/8. Generando firma para Sparkle..."
SIGNATURE=$("$SPARKLE_BIN" "$DMG_PATH" 2>&1)
SIZE=$(stat -f%z "$DMG_PATH")

echo ""
echo "=========================================="
echo "   RELEASE v$VERSION LISTO"
echo "=========================================="
echo ""
echo "Archivo: $DMG_PATH"
echo "Tamaño: $SIZE bytes"
echo ""
echo "Añade esto al appcast.xml (encima del item anterior):"
echo ""
echo "        <item>"
echo "            <title>Version $VERSION</title>"
echo "            <pubDate>$(date -R)</pubDate>"
echo "            <sparkle:version>BUILD_NUMBER_AQUI</sparkle:version>"
echo "            <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>"
echo "            <sparkle:minimumSystemVersion>13.0</sparkle:minimumSystemVersion>"
echo "            <description><![CDATA["
echo "                <h2>TransLite $VERSION</h2>"
echo "                <ul>"
echo "                    <li>Cambios aquí</li>"
echo "                </ul>"
echo "            ]]></description>"
echo "            <enclosure"
echo "                url=\"https://github.com/davizgarzia/TransLite/releases/download/v$VERSION/TransLite-$VERSION.dmg\""
echo "                $SIGNATURE"
echo "                length=\"$SIZE\""
echo "                type=\"application/octet-stream\" />"
echo "        </item>"
echo ""
echo "Siguientes pasos:"
echo "1. gh release create v$VERSION $DMG_PATH --title \"TransLite $VERSION\" --notes \"Cambios...\""
echo "2. Actualizar appcast.xml con el XML de arriba"
echo "3. git add appcast.xml && git commit -m \"Release v$VERSION\" && git push"
