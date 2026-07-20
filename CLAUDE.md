# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Présentation

**Cabine 33** est une application Godot 4.6 mobile-first (portrait 720×1280) implémentant un réseau social décentralisé via NOSTR et une physique quantique gamifiée (résonance Phi, géométrie de Goldberg). Déploiement Android APK et Web PWA.

## Build

Prérequis : Godot 4.x headless (`~/.local/bin/godot` ou `/usr/local/bin/godot`), Java JDK + Android SDK (APK uniquement), `rsvg-convert` ou Inkscape (icône PWA).

```bash
./create_apk.sh          # Compile debug + release APK (arm64)
./create_web.sh          # Compile Web HTML5 + injecte PWA (manifest, SW, icône)
./cpcode.sh godot sh gd uid md tscn json ./   # Copie sources (ignore .godot/)
```

Les scripts téléchargent automatiquement les templates Godot si absents (~1.1 Go). Les sorties sont dans `build/android/` et `build/web/`.

`create_web.sh` copie `nostr.bundle.js` depuis `../UPlanet/earth/` pour la signature Schnorr côté web — cette dépendance externe est requise pour la publication NOSTR sur la plateforme web.

## Architecture

### Couche 1 — Autoloads (12 singletons)

Tous initialisés au boot dans `project.godot`. Pas de couplage fort entre eux — ils communiquent via signaux Godot.

| Autoload | Rôle |
|----------|------|
| `Player_Origin.gd` | Profil joueur : Multipass (identité NOSTR aléatoire générée par le serveur, `user_nsec`/`user_npub`/`user_hex`), profil biométrique naissance/conception (`birth_unix`, `conception_unix`, etc.) utilisé côté serveur pour dériver la clé LOVE/ATOM4LOVE dédiée, phase personnelle, pentagon ID, polarity (Φ/Octave) |
| `Phi2X_Math.gd` | Moteur physique : résonance k, phase GPS→hex, singularité optique, géométrie Goldberg |
| `Nostr_Identity.gd` | WebSocket multi-relais NOSTR, kinds 0/1/3/7, SHA256 signatures |
| `UPlanet_API.gd` | HTTPRequest vers `u.copylaradio.com`, forge Multipass, Schnorr signature via JS bridge |
| `Loca_Scanner.gd` | Scan BLE/WiFi (SSID `A4L-*`), détection atomes locaux, serveur P2P TCP port 8080 |
| `Atom4Peace.gd` | Liaisons covalentes, super-cohérence (k ≥ 0.95), fork de réalité |
| `SpaceTime_Manager.gd` | Horloge jour/nuit (6h–20h), purge nocturne vers Spacememory |
| `Guide_System.gd` | Tutoriels progressifs (Noyau→Radar→Cabine), unlock mécanique |
| `UI_Theme.gd` | Palette dynamique jour/nuit, couleurs Φ (or) vs Octave (bleu) |
| `Spacememory_Vision.gd` | Caméra AR, empreinte spatio-temporelle (stub Android/Web) |
| `Thought_Cache.gd` | Cache mémoire pensées nocturnes (Dictionary en RAM) |
| `Kin_Maya.gd` | Variables de session temporaires |

### Couche 2 — UI & Animation

**`scripts/Main_UI.gd`** (2393 lignes) — Monolithe UI responsable de toute l'interface :
- TopBar (état ATOM4LOVE, barre énergie), HUDCenter (boussole, distance Cabine), BottomBar (actions)
- Panel offcanvas avec 5 onglets : PROFIL / MATCH / SCAN / RESEAU / THEORIE
- L'onglet PROFIL expose le Multipass (nsec/npub) et les relais NOSTR

**`scripts/AtomAnimation.gd`** (317 lignes) — Rendu `_draw()` pur en 3 modes :
- `PROFIL` : icosaèdre respirant (couleur polarity)
- `MATCH` : 2 icosaèdres entrelacés + ondes d'interférence
- `THEORIE` : polyèdre Goldberg, 12 pentagones, singularités
- Auto-calibration perf (LOW/MED/HIGH) après 120 frames

**`scripts/QR_Generator.gd`** — Génération QR codes pour partage Multipass

### Couche 3 — Monde 3D

**`scripts/World_3D.gd`** — Caméra isométrique, environnement (glow), sol infini, avatar sphère dorée émissive positionnée par GPS réel.

**`shaders/hex_grid.gdshader`** — Grille hexagonale universelle (SDF), paramètre `hex_size` ajustable.

**`shaders/interference.gdshader`** — Superposition onde Φ (or) + onde Octave (bleu), vortex singularité quand k→1.

### Scènes

- `scenes/Main_3D.tscn` — Scène root : World 3D + UI superposée
- `scenes/Main_UI.tscn` — Hiérarchie UI : TopBar, HUD, BottomBar, Panel offcanvas

## Flux de données clé

```
GPS → Phi2X_Math.gps_to_hex_index() → coordonnées HEX
    → Player_Origin.personal_phase (fsec)
    → Loca_Scanner.start_scan() → atomes locaux
    → Phi2X_Math.compute_resonance_k() → k ∈ [0, 1]
    → k ≥ 0.95 → Atom4Peace.process_resonance_encounter()
    → Nostr_Identity.publish_kind7() → validation pair
    → Atom4Peace.check_bonds_status() → fork réalité
```

## Configuration

- `project.godot` — Mapping autoloads, viewport 720×1280, renderer GL Compatibility
- `export_presets.cfg` — Android (`com.atom4love.cabine33`, arm64, permissions GPS/BLE/Camera/Internet), Web (GL Compat)

## Intégrations externes

- **UPlanet API** : `https://u.copylaradio.com` — forge Multipass, Web of Trust N²
- **NOSTR** : relais WebSocket, kinds 0 (profil), 1 (note), 3 (contacts), 7 (réaction)
- **Schnorr** : `nostr.bundle.js` chargé dynamiquement depuis `https://u.copylaradio.com/earth/nostr.bundle.js` via `JavaScriptBridge` (Web). Fallback UPassport si non disponible. Voir `Nostr_Identity._inject_nostr_bundle()`.
- **BLE** : scan `A4L-*` (simulation sur Web, natif sur Android via permissions)

## APIs ajoutées (Phi2X_Math.gd)

| Fonction | Rôle |
|----------|------|
| `get_hex_center_gps(lat, lon) → Vector2` | Centre géométrique parfait de l'hexagone courant (cible Cabine) |
| `compute_bearing(from_lat, from_lon, to_lat, to_lon) → float` | Cap géodésique [0-360°] |
| `get_dynamic_pentagons(unix_ts) → Array[Vector2]` | 12 pentagones avec dérive de précession des équinoxes |
| `get_nearest_pentagon(lat, lon, unix_ts) → Dict` | Pentagon le plus proche (dynamique ou statique) |

## Certification ATOM4LOVE (Kind 30078)

### Principe

Au premier lancement avec un Multipass valide (`Nostr_Identity.is_initialized` + `Player_Origin.has_atom4love_profile()`), l'app publie un événement Kind 30078 `d=atom4love` (signé avec `Player_Origin.user_hex`, le pubkey MULTIPASS — cf. `_compute_a4l_proof(Player_Origin.user_hex)`) sur tous les relais NOSTR. Cet événement sert de **certificat d'entrée** dans le relay strfry Astroport : il prouve que le pubkey MULTIPASS vient bien de l'app ATOM4LOVE et que les données biométriques transmises (`personal_phase`, `omega_bio`) sont dans les plages attendues.

Note : ce certificat d'entrée (signé MULTIPASS) est distinct de la clé LOVE/ATOM4LOVE (`.secret.love`) que le serveur Astroport dérive ensuite de façon déterministe à partir des données de naissance/conception (`Astroport.ONE/tools/atom4love_publish.py`) — la clé LOVE republie son propre événement Kind 30078 (`d=atom4love`) signé par elle-même, dédié au canal de résonance, jamais à l'identité principale ni aux paiements ẐEN. Le MULTIPASS lui-même reste toujours une identité aléatoire générée côté serveur (`Astroport.ONE/tools/make_NOSTRCARD.sh`), indépendante des données de naissance.

### Constante et proof tag

```gdscript
# Dans autoloads/Nostr_Identity.gd
const A4L_PROOF_SALT := "ATOM4LOVE_v1"

func _compute_a4l_proof(hex_pubkey: String) -> String:
    var ctx := HashingContext.new()
    ctx.start(HashingContext.HASH_SHA256)
    ctx.update((hex_pubkey + ":" + A4L_PROOF_SALT).to_utf8_buffer())
    return ctx.finish().hex_encode()
```

Le tag `a4l_proof` dans l'événement vaut `SHA256(pubkey_hex + ":" + A4L_PROOF_SALT)`. C'est déterministe, public et lié à la constante de la version.

### Événement publié

```json
{
  "kind": 30078,
  "tags": [
    ["d", "atom4love"],
    ["app", "atom4love"],
    ["a4l_proof", "<sha256(pubkey:ATOM4LOVE_v1)>"]
  ],
  "content": "{\"personal_phase\": <0-6.99>, \"omega_bio\": <0.1-49.9>}"
}
```

### Publier le certificat

```gdscript
# Déclenché automatiquement après Multipass + profil ATOM4LOVE valides
Nostr_Identity.publish_atom4love_cert()
```

### Mettre à jour la version de l'app

1. Changer `A4L_PROOF_SALT` dans `Nostr_Identity.gd` (ex. `"ATOM4LOVE_v2"`)
2. Ajouter le nouveau salt côté relay :
   ```bash
   source ~/.zen/Astroport.ONE/tools/cooperative_config.sh
   coop_app_add "ATOM4LOVE_v2"
   ```
3. L'ancien salt reste actif jusqu'à la migration complète des utilisateurs.
4. Quand tous les clients ont migré : `coop_app_remove "ATOM4LOVE_v1"`

### Ajouter une nouvelle app certifiée

Toute app mobile souhaitant accéder au relay Astroport doit :
1. Choisir un salt unique (`NOMAPP_v1`)
2. Calculer `a4l_proof = SHA256(pubkey + ":" + "NOMAPP_v1")` côté client
3. Publier un Kind 30078 `d=atom4love` avec ce tag
4. L'opérateur coopératif enregistre le salt : `coop_app_add "NOMAPP_v1"`

Le relay `filter/30078.sh` vérifie automatiquement la liste `AUTHORIZED_APPS` propagée dans la config coopérative (Kind 30800). Les nouvelles apps sont reconnues sur **tous les relays constellation** sans redémarrage.

## Mécanique Cabine Téléphonique

1. Atteindre le centre géométrique d'un hexagone (distance < `CABINE_UNLOCK_KM` = 50m)
2. **Rituel de Phase** : rester immobile 33 secondes (tolérance GPS : 5m)
3. Déverrouillage NOSTR géolocalisé + vibration 500ms + log

La flèche directionnelle dans `compass_label` (`_bearing_arrow()`) guide vers le centre hex. Les **Lignes de Planck** dans `hex_grid.gdshader` s'orientent vers les 2 pentagones les plus proches (injectés depuis `World_3D._update_planck_field()`).
