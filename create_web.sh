#!/bin/bash
# Build HTML5/Web pour ATOM4LOVE (cabine-33)
# Prérequis : Godot 4.x headless + template d'export Web
# Post-build : copie nostr.bundle.js dans le répertoire de sortie pour la signature JS

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$PROJECT_DIR/build/web"
NOSTR_BUNDLE_SRC="$(find "$PROJECT_DIR/../UPlanet/earth" -name "nostr.bundle.js" 2>/dev/null | head -1)"

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

# Récupérer la version exacte de Godot
GODOT_VERSION=$("$GODOT_BIN" --version 2>/dev/null | grep -oP '\d+\.\d+\.\d+\.\w+' | head -1)
if [ -z "$GODOT_VERSION" ]; then
    GODOT_VERSION="4.6.3.stable"
fi
echo "   Version : $GODOT_VERSION"

# Vérifier les templates Web
TEMPLATES_DIR="$HOME/.local/share/godot/export_templates/$GODOT_VERSION"
WEB_TEMPLATE_DEBUG="$TEMPLATES_DIR/web_nothreads_debug.zip"
WEB_TEMPLATE_RELEASE="$TEMPLATES_DIR/web_nothreads_release.zip"

if [ ! -f "$WEB_TEMPLATE_RELEASE" ]; then
    echo ""
    echo "⚠️  Templates Web manquants : $TEMPLATES_DIR"
    echo ""
    echo "   Option 1 — Téléchargement automatique (≈1.1 Go) :"
    echo "   Voulez-vous télécharger les templates maintenant ? [o/N]"
    read -r REPLY
    if [[ "$REPLY" =~ ^[oOyY]$ ]]; then
        GODOT_TAG="${GODOT_VERSION/stable/stable}"
        # Format : 4.6.3.stable → 4.6.3-stable
        GODOT_RELEASE="${GODOT_VERSION%.*}-${GODOT_VERSION##*.}"
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
        echo ""
        echo "   Option 3 — Manuellement :"
        echo "     GODOT_RELEASE=${GODOT_VERSION%.*}-${GODOT_VERSION##*.}"
        echo "     wget https://github.com/godotengine/godot/releases/download/\${GODOT_RELEASE}/Godot_v\${GODOT_RELEASE}_export_templates.tpz"
        echo "     mkdir -p $TEMPLATES_DIR"
        echo "     unzip Godot_v\${GODOT_RELEASE}_export_templates.tpz -d /tmp/tpz/"
        echo "     cp /tmp/tpz/templates/* $TEMPLATES_DIR/"
        exit 1
    fi
fi

echo ""
echo "🌐 Construction export Web..."
mkdir -p "$BUILD_DIR"

"$GODOT_BIN" --headless \
    --path "$PROJECT_DIR" \
    --export-release "Web" \
    "$BUILD_DIR/index.html"

echo "✅ Export Web généré dans $BUILD_DIR/"

# Copier nostr.bundle.js pour la signature Schnorr via JavaScriptBridge
if [ -n "$NOSTR_BUNDLE_SRC" ] && [ -f "$NOSTR_BUNDLE_SRC" ]; then
    cp "$NOSTR_BUNDLE_SRC" "$BUILD_DIR/nostr.bundle.js"
    echo "✅ nostr.bundle.js copié (signature Schnorr JS disponible)"
    if grep -q 'nostr.bundle.js' "$BUILD_DIR/index.html" 2>/dev/null; then
        echo "   nostr.bundle.js déjà référencé dans index.html"
    else
        sed -i 's|</head>|<script src="nostr.bundle.js"></script>\n</head>|' "$BUILD_DIR/index.html"
        echo "   nostr.bundle.js injecté dans index.html"
    fi
else
    echo "⚠️  nostr.bundle.js introuvable dans UPlanet/earth/"
    echo "   Tentative de téléchargement depuis u.copylaradio.com (self-hosted)..."
    BUNDLE_URL="https://u.copylaradio.com/earth/nostr.bundle.js"
    if wget -q --timeout=15 -O "$BUILD_DIR/nostr.bundle.js" "$BUNDLE_URL" 2>/dev/null || \
       curl -fsSL --max-time 15 -o "$BUILD_DIR/nostr.bundle.js" "$BUNDLE_URL" 2>/dev/null; then
        echo "✅ nostr.bundle.js téléchargé et servi localement (évite les blocages CORS)"
        if ! grep -q 'nostr.bundle.js' "$BUILD_DIR/index.html" 2>/dev/null; then
            sed -i 's|</head>|<script src="nostr.bundle.js"></script>\n</head>|' "$BUILD_DIR/index.html"
        fi
    else
        echo "⚠️  Impossible de télécharger nostr.bundle.js — fallback UPassport actif."
    fi
fi

# ── PWA : manifest.json + service-worker.js ──────────────────
echo ""
echo "📱 Injection PWA (Progressive Web App)..."

# manifest.json — permet l'installation sur écran d'accueil iOS/Android
cat > "$BUILD_DIR/manifest.json" << 'MANIFEST_EOF'
{
  "name": "ATOM4LOVE — Interféromètre Cosmique",
  "short_name": "ATOM4LOVE",
  "description": "Découvrez votre empreinte cosmique et testez votre résonance de phase avec d'autres atomes vivants.",
  "start_url": "./index.html",
  "display": "standalone",
  "orientation": "portrait",
  "background_color": "#000a14",
  "theme_color": "#f59e0b",
  "icons": [
    { "src": "icon.png", "sizes": "192x192", "type": "image/png", "purpose": "any maskable" },
    { "src": "icon.png", "sizes": "512x512", "type": "image/png", "purpose": "any maskable" }
  ],
  "categories": ["games", "lifestyle"],
  "lang": "fr",
  "scope": "./"
}
MANIFEST_EOF
echo "   ✅ manifest.json créé"

# Convertir icon.svg en icon.png si rsvg-convert ou Inkscape disponible
if [ -f "$PROJECT_DIR/icon.svg" ]; then
    if command -v rsvg-convert &>/dev/null; then
        rsvg-convert -w 512 -h 512 "$PROJECT_DIR/icon.svg" -o "$BUILD_DIR/icon.png" 2>/dev/null \
            && echo "   ✅ icon.png généré (512×512 via rsvg-convert)"
    elif command -v inkscape &>/dev/null; then
        inkscape --export-filename="$BUILD_DIR/icon.png" -w 512 -h 512 "$PROJECT_DIR/icon.svg" 2>/dev/null \
            && echo "   ✅ icon.png généré (512×512 via Inkscape)"
    else
        echo "   ⚠️  rsvg-convert/Inkscape absent — icon.png non généré (PWA icône manquante)"
    fi
fi

# Construire la liste des assets à mettre en cache
CACHED_JS='["./", "./index.html"'
for f in "$BUILD_DIR"/*.js "$BUILD_DIR"/*.wasm "$BUILD_DIR"/*.pck "$BUILD_DIR"/*.png "$BUILD_DIR"/*.json; do
    # Exclure service-worker.js (anti-pattern PWA : il ne doit pas se mettre en cache lui-même)
    if [ -f "$f" ] && [ "$(basename "$f")" != "service-worker.js" ]; then
        CACHED_JS="$CACHED_JS, \"./$(basename "$f")\""
    fi
done
CACHED_JS="$CACHED_JS]"

# Hash de build = timestamp pour invalider le cache à chaque publication
BUILD_HASH=$(date -u +%Y%m%d%H%M)
_app_ver=$(grep 'version/name=' "$PROJECT_DIR/export_presets.cfg" 2>/dev/null | grep -oP '"[^"]+"' | tr -d '"' | head -1 || echo "1.0")

# service-worker.js — cache offline-first + notification de mise à jour
cat > "$BUILD_DIR/service-worker.js" << SWEOF
// ATOM4LOVE PWA Service Worker — v${_app_ver} build ${BUILD_HASH}
const CACHE = 'atom4love-${_app_ver}-${BUILD_HASH}';
const ASSETS = ${CACHED_JS};

self.addEventListener('install', ev => {
  ev.waitUntil(
    caches.open(CACHE)
      .then(c => c.addAll(ASSETS))
      .then(() => self.skipWaiting())
  );
});

self.addEventListener('activate', ev => {
  ev.waitUntil(
    caches.keys()
      .then(ks => Promise.all(
        ks.filter(k => k !== CACHE).map(k => {
          console.log('[SW] Suppression ancien cache:', k);
          return caches.delete(k);
        })
      ))
      .then(() => {
        // Notifier tous les clients qu'une mise à jour est disponible
        self.clients.matchAll().then(clients =>
          clients.forEach(c => c.postMessage({ type: 'SW_UPDATED', version: '${_app_ver}' }))
        );
        return self.clients.claim();
      })
  );
});

self.addEventListener('fetch', ev => {
  ev.respondWith(
    caches.match(ev.request).then(cached => {
      if (cached) return cached;
      return fetch(ev.request).then(resp => {
        const clone = resp.clone();
        caches.open(CACHE).then(c => c.put(ev.request, clone));
        return resp;
      });
    })
  );
});
SWEOF
echo "   ✅ service-worker.js créé (cache offline-first)"

# Injecter manifest + SW dans index.html (idempotent)
if ! grep -q 'manifest.json' "$BUILD_DIR/index.html" 2>/dev/null; then
    sed -i 's|</head>|  <link rel="manifest" href="manifest.json">\n  <meta name="theme-color" content="#f59e0b">\n  <meta name="mobile-web-app-capable" content="yes">\n  <meta name="apple-mobile-web-app-capable" content="yes">\n  <meta name="apple-mobile-web-app-status-bar-style" content="black-translucent">\n  <meta name="apple-mobile-web-app-title" content="ATOM4LOVE">\n  <script>if("serviceWorker"in navigator){navigator.serviceWorker.register("./service-worker.js");navigator.serviceWorker.addEventListener("message",function(e){if(e.data\&\&e.data.type==="SW_UPDATED"){var b=document.createElement("div");b.style="position:fixed;top:0;left:0;right:0;z-index:9999;background:#059669;color:#fff;text-align:center;padding:10px;font-family:sans-serif;font-size:14px;cursor:pointer";b.textContent="⚛ Nouvelle version ATOM4LOVE disponible — Tapez pour recharger";b.onclick=function(){window.location.reload()};document.body.appendChild(b);}});}</script>\n</head>|' \
        "$BUILD_DIR/index.html"
    echo "   ✅ PWA injecté dans index.html (manifest + SW + apple-meta)"
else
    echo "   ℹ️  PWA déjà injecté dans index.html"
fi

echo ""
echo "📂 Fichiers dans $BUILD_DIR :"
ls -lh "$BUILD_DIR/"
echo ""
echo "🚀 Pour tester localement :"
echo "   cd $BUILD_DIR && python3 -m http.server 8080"
echo "   Puis ouvrir http://localhost:8080"
echo ""
echo "📱 PWA : visitez https://u.copylaradio.com/atom4love sur Chrome/Safari"
echo "         → bouton natif 'Ajouter à l'écran d'accueil' apparaîtra."
