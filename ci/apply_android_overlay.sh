#!/usr/bin/env bash
# Copia overlays versionados em ci/ para o android/ gerado pelo flutter create.
# Deve rodar SEMPRE antes do flutter build apk (Codemagic e local).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_MAIN="$ROOT/android/app/src/main"
XML_DIR="$APP_MAIN/res/xml"

test -d "$APP_MAIN" || {
  echo "ERRO: $APP_MAIN nao existe. Rode flutter create --platforms=android . antes."
  exit 1
}

mkdir -p "$XML_DIR"
cp "$ROOT/ci/AndroidManifest.xml" "$APP_MAIN/AndroidManifest.xml"
cp "$ROOT/ci/file_paths.xml" "$XML_DIR/file_paths.xml"
cp "$ROOT/ci/backup_rules.xml" "$XML_DIR/backup_rules.xml"
cp "$ROOT/ci/data_extraction_rules.xml" "$XML_DIR/data_extraction_rules.xml"

# MainActivity customizada (FileProvider / WhatsApp / instalador de APK)
DEST="$(find "$ROOT/android" -name 'MainActivity.kt' | head -n 1 || true)"
if [ -z "$DEST" ]; then
  echo "ERRO: MainActivity.kt nao encontrado sob android/"
  exit 1
fi
PKG="$(dirname "$DEST" | sed -n 's|.*/kotlin/\(.*\)|\1|p' | tr '/' '.')"
cp "$ROOT/ci/MainActivity.kt" "$DEST"
if [ -n "$PKG" ]; then
  # macOS/BSD sed precisa de extensão em -i; Linux aceita -i sem arg — usar arquivo temp
  tmp="$(mktemp)"
  sed "1s/^package .*/package $PKG/" "$DEST" > "$tmp"
  mv "$tmp" "$DEST"
fi

echo "Overlay Android aplicado:"
echo "  - AndroidManifest.xml (allowBackup=false + regras de backup)"
echo "  - res/xml/file_paths.xml"
echo "  - res/xml/backup_rules.xml"
echo "  - res/xml/data_extraction_rules.xml"
echo "  - MainActivity.kt -> $DEST (package ${PKG:-?})"
