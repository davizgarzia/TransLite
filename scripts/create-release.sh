#!/bin/bash

# Script para crear un release de TransLite con Sparkle
# Uso: ./scripts/create-release.sh 1.1.0

set -e

VERSION=$1

if [ -z "$VERSION" ]; then
    echo "Uso: $0 <version>"
    echo "Ejemplo: $0 1.1.0"
    exit 1
fi

echo "=== Creando release TransLite v$VERSION ==="

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

# 1. Compilar
echo "1. Compilando..."
cd "$BUILD_DIR"
xcodebuild -project TransLite.xcodeproj -scheme TransLite -configuration Release clean build 2>&1 | grep -E "(BUILD|error:)" || true

# 2. Copiar app a releases
echo "2. Copiando app..."
mkdir -p "$RELEASE_DIR"
APP_PATH=~/Library/Developer/Xcode/DerivedData/TransLite-*/Build/Products/Release/TransLite.app
cp -R $APP_PATH "$RELEASE_DIR/TransLite-$VERSION.app"

# 3. Crear ZIP
echo "3. Creando ZIP..."
cd "$RELEASE_DIR"
rm -f "TransLite-$VERSION.zip"
ditto -c -k --keepParent "TransLite-$VERSION.app" "TransLite-$VERSION.zip"

# 4. Firmar
echo "4. Firmando..."
SIGNATURE=$("$SPARKLE_BIN" "TransLite-$VERSION.zip" 2>&1)

# 5. Obtener tamaño
SIZE=$(stat -f%z "TransLite-$VERSION.zip")

echo ""
echo "=== RELEASE LISTO ==="
echo ""
echo "Archivo: $RELEASE_DIR/TransLite-$VERSION.zip"
echo "Tamaño: $SIZE bytes"
echo ""
echo "Añade esto al appcast.xml:"
echo ""
echo "        <item>"
echo "            <title>Version $VERSION</title>"
echo "            <pubDate>$(date -R)</pubDate>"
echo "            <sparkle:version>BUILD_NUMBER</sparkle:version>"
echo "            <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>"
echo "            <sparkle:minimumSystemVersion>13.0</sparkle:minimumSystemVersion>"
echo "            <description><![CDATA["
echo "                <h2>TransLite $VERSION</h2>"
echo "                <ul>"
echo "                    <li>Cambios aquí</li>"
echo "                </ul>"
echo "            ]]></description>"
echo "            <enclosure"
echo "                url=\"https://github.com/davizgarzia/TransLite/releases/download/v$VERSION/TransLite-$VERSION.zip\""
echo "                $SIGNATURE"
echo "                length=\"$SIZE\""
echo "                type=\"application/octet-stream\" />"
echo "        </item>"
echo ""
echo "Siguiente paso: sube TransLite-$VERSION.zip a GitHub Releases como v$VERSION"
