#!/bin/bash
# Build APK Android pour ATOM4LOVE (cabine-33)
# Prérequis : Godot 4.x headless + Android SDK + template d'export Android

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_FILE="$PROJECT_DIR/project.godot"
BUILD_DIR="$PROJECT_DIR/build/android"
APK_NAME="atom4love"

# Détection automatique de Godot headless
GODOT_BIN=""
for candidate in \
    "$HOME/.local/bin/godot" \
    "/usr/local/bin/godot" \
    "/usr/bin/godot" \
    "$(which godot 2>/dev/null || true)"; do
    if [ -x "$candidate" ]; then
        GODOT_BIN="$candidate"
        break
    fi
done

if [ -z "$GODOT_BIN" ]; then
    echo "❌ Godot introuvable. Installez Godot 4.x et ajoutez-le au PATH."
    echo "   Téléchargement : https://godotengine.org/download"
    exit 1
fi

echo "✅ Godot détecté : $GODOT_BIN"

# ── Vérification concordance de version ────────────────────────────────────────
_proj_ver=$(grep 'config/version' "$PROJECT_DIR/project.godot" 2>/dev/null | grep -oP '"[^"]+"' | tr -d '"' | head -1 || true)
_preset_ver=$(grep 'version/name=' "$PROJECT_DIR/export_presets.cfg" 2>/dev/null | grep -oP '"[^"]+"' | tr -d '"' | head -1 || true)
if [[ -n "$_proj_ver" && -n "$_preset_ver" && "$_proj_ver" != "$_preset_ver" ]]; then
    echo ""
    echo "⚠️  VERSION MISMATCH !"
    echo "   project.godot config/version = \"$_proj_ver\""
    echo "   export_presets.cfg version/name = \"$_preset_ver\""
    echo "   Corrigez avant de publier (pour éviter de shipper une v1.2 étiquetée v1.1)."
    echo ""
fi

# Récupérer la version exacte
GODOT_VERSION=$("$GODOT_BIN" --headless --version 2>/dev/null | grep -oP '\d+\.\d+\.\d+\.\w+' | head -1)
if [ -z "$GODOT_VERSION" ]; then
    GODOT_VERSION="4.6.3.stable"
fi
echo "   Version : $GODOT_VERSION"
GODOT_RELEASE="${GODOT_VERSION%.*}-${GODOT_VERSION##*.}"

# ── Vérifier Java JDK ─────────────────────────────────────────────────────────
if ! command -v java &>/dev/null; then
    echo ""
    echo "❌ Java JDK introuvable."
    echo "   Installation : sudo apt install default-jdk"
    exit 1
fi
JAVA_VER=$(java -version 2>&1 | head -1)
echo "✅ Java : $JAVA_VER"

# ── Vérifier Android SDK ──────────────────────────────────────────────────────
ANDROID_SDK="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Android/Sdk}}"
if [ ! -d "$ANDROID_SDK" ]; then
    echo ""
    echo "❌ Android SDK introuvable. Vérifiez ANDROID_HOME ou ANDROID_SDK_ROOT."
    echo ""
    echo "   Installation rapide via command-line tools :"
    echo "   https://developer.android.com/tools#command-line-tools-only"
    echo ""
    echo "   Ou via Android Studio :"
    echo "   https://developer.android.com/studio"
    echo ""
    echo "   Puis configurez dans Godot :"
    echo "   Éditeur → Paramètres de l'éditeur → Export → Android → SDK Path"
    exit 1
fi
echo "✅ Android SDK : $ANDROID_SDK"

# ── Vérifier les templates Android ───────────────────────────────────────────
TEMPLATES_DIR="$HOME/.local/share/godot/export_templates/$GODOT_VERSION"
ANDROID_TEMPLATE_DEBUG="$TEMPLATES_DIR/android_debug.apk"
ANDROID_TEMPLATE_RELEASE="$TEMPLATES_DIR/android_release.apk"

if [ ! -f "$ANDROID_TEMPLATE_DEBUG" ]; then
    echo ""
    echo "⚠️  Templates Android manquants : $TEMPLATES_DIR"
    echo ""
    # Mode non-interactif : cron ou variable d'environnement
    if [[ ! -t 0 || "${ATOM4LOVE_AUTO_DOWNLOAD:-}" == "1" ]]; then
        REPLY="y"
        echo "   Mode non-interactif : téléchargement automatique..."
    else
        echo "   Option 1 — Téléchargement automatique (≈1.1 Go) :"
        echo "   Voulez-vous télécharger les templates maintenant ? [o/N]"
        read -r REPLY
    fi
    if [[ "$REPLY" =~ ^[oOyY]$ ]]; then
        TPZ_URL="https://github.com/godotengine/godot/releases/download/${GODOT_RELEASE}/Godot_v${GODOT_RELEASE}_export_templates.tpz"
        TPZ_FILE="/tmp/godot_templates_${GODOT_RELEASE}.tpz"
        echo "⬇  Téléchargement de $TPZ_URL ..."
        wget -q --show-progress -O "$TPZ_FILE" "$TPZ_URL" || \
            curl -L --progress-bar -o "$TPZ_FILE" "$TPZ_URL"
        echo "📦 Installation des templates..."
        mkdir -p "$TEMPLATES_DIR"
        unzip -q "$TPZ_FILE" -d /tmp/godot_tpz_extract/
        cp /tmp/godot_tpz_extract/templates/* "$TEMPLATES_DIR/"
        rm -rf /tmp/godot_tpz_extract/ "$TPZ_FILE"
        echo "✅ Templates installés dans $TEMPLATES_DIR"
    else
        echo ""
        echo "   Option 2 — Via l'éditeur Godot (recommandé) :"
        echo "     Ouvrez l'éditeur → Menu Éditeur → Gérer les modèles d'exportation"
        echo "     → Télécharger pour la version $GODOT_VERSION"
        exit 1
    fi
fi

# ── Vérifier / créer le debug.keystore ───────────────────────────────────────
KEYSTORE_DIR="$HOME/.android"
KEYSTORE="$KEYSTORE_DIR/debug.keystore"
if [ ! -f "$KEYSTORE" ]; then
    echo "🔑 Création du debug.keystore..."
    mkdir -p "$KEYSTORE_DIR"
    keytool -genkey -v \
        -keystore "$KEYSTORE" \
        -storepass android \
        -alias androiddebugkey \
        -keypass android \
        -keyalg RSA \
        -keysize 2048 \
        -validity 10000 \
        -dname "CN=Android Debug,O=Android,C=US" 2>/dev/null
    echo "✅ debug.keystore créé : $KEYSTORE"
fi

# ── Configurer SDK Android + JDK dans les paramètres éditeur Godot ────────────
EDITOR_SETTINGS=$(ls "$HOME/.config/godot/editor_settings-4"*.tres 2>/dev/null | sort -V | tail -1)
if [ -n "$EDITOR_SETTINGS" ] && [ -f "$EDITOR_SETTINGS" ]; then
    JAVA_HOME_DETECTED=$(dirname "$(dirname "$(readlink -f "$(which java)")")")
    if grep -q 'export/android/java_sdk_path = ""' "$EDITOR_SETTINGS"; then
        sed -i "s|export/android/java_sdk_path = \"\"|export/android/java_sdk_path = \"$JAVA_HOME_DETECTED\"|" "$EDITOR_SETTINGS"
        echo "✅ java_sdk_path → $JAVA_HOME_DETECTED"
    fi
    if ! grep -q "export/android/android_sdk_path" "$EDITOR_SETTINGS"; then
        echo "export/android/android_sdk_path = \"$ANDROID_SDK\"" >> "$EDITOR_SETTINGS"
        echo "✅ android_sdk_path → $ANDROID_SDK"
    fi
else
    echo "⚠️  editor_settings Godot introuvable — paramètres Android non injectés"
fi

echo ""
echo "📦 Construction APK Android..."
mkdir -p "$BUILD_DIR"

# ── Injection du keystore debug dans export_presets.cfg ──────────────────────
# export_presets.cfg est versionné avec des champs vides (portable / F-Droid / CI).
# On injecte le chemin local avant l'export, puis on restaure après.
# Godot 4 requiert : soit les 3 champs (debug/user/password) configurés, soit les 3 vides.
PRESETS_CFG="$PROJECT_DIR/export_presets.cfg"
PRESETS_BACKUP="$PROJECT_DIR/export_presets.cfg.bak"

cp "$PRESETS_CFG" "$PRESETS_BACKUP"
python3 - <<EOF
import re, sys
cfg = open("$PRESETS_CFG").read()
cfg = re.sub(r'keystore/debug="[^"]*"',          'keystore/debug="$KEYSTORE"',          cfg)
cfg = re.sub(r'keystore/debug_user="[^"]*"',     'keystore/debug_user="androiddebugkey"', cfg)
cfg = re.sub(r'keystore/debug_password="[^"]*"', 'keystore/debug_password="android"',    cfg)
open("$PRESETS_CFG", "w").write(cfg)
EOF
echo "✅ Keystore debug injecté : $KEYSTORE"

# Restaurer export_presets.cfg à sa version vide après chaque build (trap)
_restore_presets() { cp "$PRESETS_BACKUP" "$PRESETS_CFG" && rm -f "$PRESETS_BACKUP"; }
trap _restore_presets EXIT

# Export debug APK
"$GODOT_BIN" --headless \
    --path "$PROJECT_DIR" \
    --export-debug "Android" \
    "$BUILD_DIR/${APK_NAME}_debug.apk"

echo ""
echo "✅ APK debug : $BUILD_DIR/${APK_NAME}_debug.apk"

# Export release APK (nécessite keystore configuré dans les presets d'export)
if "$GODOT_BIN" --headless \
    --path "$PROJECT_DIR" \
    --export-release "Android" \
    "$BUILD_DIR/${APK_NAME}.apk" 2>/dev/null; then
    echo "✅ APK release : $BUILD_DIR/${APK_NAME}.apk"
else
    echo "⚠️  APK release ignoré (keystore release non configuré — éditer export_presets.cfg)"
fi

echo ""
echo "📂 Fichiers dans $BUILD_DIR :"
ls -lh "$BUILD_DIR/"
echo ""
echo "📲 Installation sur appareil connecté (adb) :"
echo "   adb install -r --no-incremental $BUILD_DIR/${APK_NAME}_debug.apk"

echo "Logs Android — commandes utiles"
echo ""
echo "adb logcat -s Godot                          # tout ce que Godot affiche"
echo "adb logcat -s Godot | grep "ATOM\|NOSTR\|φ"  # filtré"
echo "adb logcat -v time -s Godot                  # avec horodatage"
