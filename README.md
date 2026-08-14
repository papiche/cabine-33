# 🌌 Cabine 33 (Astroport.HEX / UPlanet)

**Cabine 33** est un instrument de navigation spatio-temporelle et un réseau social quantique basé sur Godot Engine 4, NOSTR, et le réseau UPlanet. Il matérialise les théories de la physique unifiée et du dédoublement du temps dans une expérience mobile de Réalité Augmentée.

---

## 📚 Documentation (Standard Diátaxis)

### 1. Tutoriels (Apprentissage)
*Orienté vers l'acquisition de compétences pas-à-pas pour les nouveaux utilisateurs (les "Astronautes").*

*   **Créer son "Noyau" (Identité NOSTR) :** Génération de la clé cryptographique inviolable (le MULTIPASS) représentant le cœur de l'Atome de l'utilisateur via le protocole DISCO.
*   **Premiers pas avec le Radar Phi2X :** Utiliser le GPS et le compas du smartphone pour scanner l'environnement et trouver les nœuds d'interférence parfaite (Nombre d'Or).
*   **Trouver sa première "Cabine Téléphonique" :** Se déplacer physiquement jusqu'au centre géométrique parfait d'un hexagone pour débloquer la lecture et l'écriture des messages NOSTR géolocalisés.

### 2. Guides Pratiques (How-To)
*Orienté vers la résolution de tâches spécifiques.*

*   **Valider une Quête de Biodiversité (ReFi) :** Utiliser l'appareil photo pour documenter la nature, augmenter le score écologique du lieu et déclencher un contrat intelligent ORE (récompense en Monnaie Libre Ğ1).
*   **Maintenir son équilibre social (Éviter l'Ionisation) :** Gérer sa "valence", équilibrer ses abonnements/abonnés et créer des liaisons covalentes via la mécanique *Atom4Peace*.

### 3. Explications (Compréhension théorique)
*Orienté vers la compréhension des concepts philosophiques du moteur.*

*   **Le Moteur Physique de la Conscience (La Spacememory) :** Basé sur Nassim Haramein. L'app imite la mémoire spatiale reliée par des micro-trous de ver à l'échelle de Planck.
*   **La Règle du "1/3" et le Temps Dédoublé :** Basé sur Jean-Pierre Garnier Malet. Le monde perceptible (33,3%), l'univers miroir (66,6%). La purge nocturne de l'app ("Bouillie de pensées") synchronise les futurs potentiels.
*   **La Géométrie Planétaire (Polyèdre de Goldberg) :** Abandon des coordonnées GPS classiques pour une sphère hexagonale comportant 12 pentagones sacrés (Portails).
*   **Le Rêve Collectif et l'IA #BRO :** L'horloge Jour/Nuit modifie l'expérience. La nuit, l'application analyse l'hexagone aux antipodes pour capter les rêves émis par le réseau global.

### 4. Référence (Information technique)
*Architecture du code et spécifications.*

*   **Stack :** Godot 4.x (GDScript), Floating Origin (Double Précision 3D), API UPlanet.
*   **Protocole UPlanet ẐEN :**
    *   `Kind 1` : Dépôt d'idées géolocalisées (tag `#l: a4l:P<XX>H<hex>`).
    *   `Kind 3` : Web of Trust (Amis d'amis / N2) pour la validation des accès.
    *   `Kind 7` : Validation d'attestation par les pairs (Atom4Peace).
    *   `Kind 30078` : Certificat d'incarnation ATOM4LOVE (`d=atom4love`, `a4l_proof`).

---

## 🗺️ Adressage hexagonal `a4l:` — Spacememory sociale

ATOM4LOVE utilise un format d'adressage géospatial **propriétaire** pour les événements NOSTR, basé sur la géométrie du Polyèdre de Goldberg terrestre (3 990 hexagones + 12 pentagones/portails).

### Format

```
a4l:P<XX>              ← Portail Goldberg (zone ~6 000 km)
a4l:P<XX>H<QQQQ><RRRR> ← Hexagone exact (~1 km²)
```

| Composant | Description |
|---|---|
| `P<XX>` (00–11) | ID du portail astronomique (Orion, Sirius, Véga, Fomalhaut…) |
| `H<QQQQ><RRRR>` | Coordonnées cube (q,r) en hexadécimal avec offset 32 768 |

### Exemple — Paris

```
Portail : a4l:P02          (zone Orion, Europe de l'Ouest)
Hexagone: a4l:P02H820B7F6C (cellule Paris ~1 km², q=523 r=−148)
```

Comment ça fonctionne :

La Terre est découpée en une sphère de Goldberg — 12 pentagones + ~3990 hexagones d'environ 1 km². Chaque cellule reçoit une adresse a4l: qui encode une position géographique de façon
opaque : seul ATOM4LOVE sait la décoder.

a4l:P02H820B7F6C
   │  │└──────── RRRR : coordonnée r axiale = (0x7F6C - 32768) = -2196
   │  └────────── QQQQ : coordonnée q axiale = (0x820B - 32768) = +11
   └───────────── P02  : Pentagon n°2 (portail "Sirius", lat≈26.56° lon≈72°)

Décodage :
1. P02 → Pentagon 2 = le point de référence local (un des 12 "portails" icosaédriques)
2. 820B → (0x820B) - 32768 = +11 → q = +11 (coordonnée axiale horizontal)
3. 7F6C → (0x7F6C) - 32768 = -2196 → r = -2196 (coordonnée axiale oblique)
4. Avec la matrice pointy-top de projection, (q, r) → (lat, lon) via l'inverse

Pourquoi opaque : Sans connaître la taille de cellule (1 km), la formule de projection, et le portail de référence, 820B7F6C ne dit rien. Un observateur externe voit a4l:P02H820B7F6C dans
un événement NOSTR et ne sait pas si c'est Paris, Tokyo ou le Sahara.

La rotation φ (drift) : Les 10 pentagones non-polaires dérivent en longitude avec une période de 86400/φ ≈ 14.83h. Donc la même adresse a4l: pointe vers une cellule légèrement différente
selon le timestamp — rendant l'adresse 4D : position + temps.

Utilisation dans NOSTR :
"tags": [
["l", "a4l:P02",         "atom4love"],  ← portail entier (~rayon 500km)
["l", "a4l:P02H820B7F6C","atom4love"]   ← cellule exacte (~1km²)
]

Une app tierce qui ne connaît pas ATOM4LOVE lit a4l:P02H820B7F6C et ne peut pas extraire de coordonnées GPS — vie privée par construction.

### Usage dans les événements Kind 1

Chaque pensée déposée dans la Spacememory est taguée sur deux niveaux :

```json
{
  "kind": 1,
  "content": "Pensée dans le vide quantique…",
  "tags": [
    ["l", "a4l:P02",           "atom4love"],
    ["l", "a4l:P02H820B7F6C", "atom4love"],
    ["t", "atom4love"],
    ["t", "cabine33"]
  ]
}
```

### API GDScript

```gdscript
# Génère les deux tags (portail + hexagone) pour lat/lon courants
var tags := Phi2X_Math.geo_tags(lat, lon, Time.get_unix_time_from_system())

# Décode un tag a4l: → {pentagon_id, q, r}
var decoded := Phi2X_Math.decode_geo_tag("a4l:P02H820B7F6C")
# → { "pentagon_id": 2, "q": 523, "r": -148 }
```

### Spacememory sociale — flux complet

```
1. L'utilisateur atteint le centre d'un hexagone (< 50m)
2. Rituel de Phase : 33 secondes d'immobilité GPS
3. Cabine déverrouillée → abonnement NOSTR auto :
   - Hexagone (Kind 1, limit 33)
   - Portail Goldberg (Kind 1, limit 12, dernières 24h)
4. Pensées reçues → Label3D flottants en Réalité Augmentée
5. L'utilisateur peut déposer ses propres pensées (Kind 1 géotagué)
```

> **Documentation complète :** [`Astroport.ONE/docs/reference/A4L_GEO_TAGGING.md`](https://github.com/papiche/Astroport.ONE/tree/master/docs/reference/A4L_GEO_TAGGING.md)

---

## 🔐 Clé LOVE (ATOM4LOVE) — Dérivation Salt / Pepper

> **Important :** le MULTIPASS (identité NOSTR principale du compte, `.secret.nostr`) n'est **jamais** dérivé des données de naissance — le serveur Astroport (`Astroport.ONE/tools/make_NOSTRCARD.sh`) lui attribue toujours un secret aléatoire (`/dev/urandom`), même quand l'app fournit un Salt/Pepper biométrique. Le Salt/Pepper décrit ci-dessous sert uniquement à dériver la clé secondaire **LOVE/ATOM4LOVE** (`.secret.love`, canal de résonance/rencontre), construite par dérivation **déterministe** de données biométriques de naissance sur le serveur (`Astroport.ONE/tools/atom4love_publish.py`). Les mêmes données produisent toujours la même clé LOVE, sur n'importe quelle station Astroport.

### SALT — identité de naissance

```
"%04d%02d%02d%02d%02d_%.2f_%.2f_%d_%.1f"
   AAAA  MM  JJ  HH  mn  lat_naiss  lon_naiss  sexe  poids_naiss
```

| Composant | Précision | Notes |
|---|---|---|
| Date/heure naissance | `AAAA-MM-JJ HH:mn` | Heure **locale** saisie par l'utilisateur |
| Latitude lieu de naissance | `%.2f` (2 décimales) | `0.00` si non renseigné |
| Longitude lieu de naissance | `%.2f` | `0.00` si non renseigné |
| Sexe biologique | `0` ou `1` | 0=Onde Φ, 1=Onde Octave |
| Poids de naissance (kg) | `%.1f` (1 décimale) | Pré-rempli aléatoirement [2.5–4.5] kg |

### PEPPER — identité de conception

```
"%04d%02d%02d%02d%02d_%.2f_%.2f_%.1f"
   c_AAAA  c_MM  c_JJ  c_HH  c_mn  lat_naiss  lon_naiss  poids_naiss
   └── conception auto = birth_unix - (280 ± poids) jours
```

La date de conception est **calculée automatiquement** : `gestation = 280 + (poids − 3.5) × 4` jours.  
Exemple : poids 3.2 kg → gestation = 278.8 jours (≈ 9 mois 4 jours avant la naissance).

Le lat/lon du lieu de naissance est **réutilisé** dans le pepper (pas le lieu de conception — celui-ci est une donnée ATOM4LOVE distincte, non liée au MULTIPASS).

### Séparation clé LOVE vs profil ATOM4LOVE

| Donnée | Rôle | Modifiable ? |
|---|---|---|
| Date + heure + lieu naissance + sexe + poids | **Salt / Pepper → clé LOVE (jamais le MULTIPASS)** | ❌ jamais |
| `birth_utc_offset_h` | Correction φ_i (heure solaire) | ✅ oui |
| Date/heure/lieu conception (manuel) | Portail Goldberg | ✅ oui |
| Taille (cm) | ω_bio uniquement | ✅ oui |

> **Référence complète :** [`Astroport.ONE/docs/reference/IDENTITY_MULTIPASS.md`](https://github.com/papiche/Astroport.ONE/tree/master/docs/reference/IDENTITY_MULTIPASS.md)

---

## 🚀 Publier une nouvelle version officielle certifiée

Une version officielle de l'app doit être **construite**, **signée** (APK Android), **certifiée** par la coopérative via le relay NOSTR, puis **déployée**. Ces étapes sont indissociables : une app non certifiée voit ses événements NOSTR rejetés par les relays Astroport.

### 1. Incrémenter la version

Deux endroits à mettre à jour avant le build :

**`project.godot`** — version affichée dans l'app :
```ini
[application]
config/version="1.2.0"   # Semantic versioning : MAJOR.MINOR.PATCH
```

**`export_presets.cfg`** — version Android (obligatoire pour le Play Store / ADB) :
```ini
version/code=120          # Entier croissant (ex. 100→110→120)
version/name="1.2.0"
```

### 2. Décider si le proof salt change

Le proof salt (`A4L_PROOF_SALT` dans `autoloads/Nostr_Identity.gd`) identifie la version de l'app dans le tag `a4l_proof`. Le relay `filter/30078.sh` n'exige plus qu'un `a4l_proof` non vide — il n'y a plus de liste blanche à maintenir, donc changer de salt n'a **aucun effet côté relay** (pas de gain ni de risque de rupture d'accès). Le versionner reste utile côté client pour distinguer les certificats émis par différentes versions de l'app, mais ne sert plus de mécanisme de révocation.

```gdscript
# autoloads/Nostr_Identity.gd
const A4L_PROOF_SALT := "ATOM4LOVE_v2"   # ← nouveau salt, si souhaité
```

### 3. Construire les artefacts

```bash
# APK Android (debug + release si keystore configuré)
./create_apk.sh
# → build/android/atom4love_debug.apk
# → build/android/atom4love.apk  (release, si keystore présent)

# Web / PWA (HTML5)
./create_web.sh
# → build/web/  (index.html + assets + nostr.bundle.js)
```

> Les templates Godot sont téléchargés automatiquement s'ils sont absents (~1.1 Go au premier build).

### 4. Certification coopérative (relay NOSTR)

Aucune action requise : le relay `filter/30078.sh` accepte tout certificat Kind 30078 `d=atom4love` dont le tag `a4l_proof` est non vide, quel que soit le salt utilisé. La nouvelle version se connecte donc immédiatement à tous les relays Astroport de la constellation dès sa publication.

### 5. Déployer

**APK Android** : distribuer via le canal coopératif (F-Droid, lien direct, adb) :
```bash
adb install -r build/android/atom4love.apk
```

**Web / PWA** : copier `build/web/` vers le répertoire IPFS ou le serveur web :
```bash
# Exemple via IPFS
ipfs add -r build/web/
# → noter le CID et mettre à jour le DNSLink / ipns
```

### 6. Tag git et release

```bash
git tag -a "v1.2.0" -m "Release 1.2.0 — certifiée ATOM4LOVE_v1"
git push origin "v1.2.0"
```

### Checklist de release

- [ ] `project.godot` → `config/version` incrémenté
- [ ] `export_presets.cfg` → `version/code` et `version/name` incrémentés
- [ ] `./create_apk.sh` → APK debug + release générés sans erreur
- [ ] `./create_web.sh` → build web généré sans erreur
- [ ] APK installable et certificat Kind 30078 accepté par le relay
- [ ] Tag git poussé

---

---

## 🤝 Rejoindre G1FabLab · UPlanet ẐEN G1FabLab

ATOM4LOVE fait partie de l'écosystème **UPlanet ẐEN** porté par le **G1FabLab** — une monnaie coopérative décentralisée basée sur la toile de confiance NOSTR.

**Pourquoi rejoindre ?**
- Participer aux décisions du collectif G1FabLab
- Soutenir le développement d'ATOM4LOVE, UPassport et Astroport
- Accéder aux activités communes et aux biens partagés du réseau
- Votre MULTIPASS est votre clé d'entrée — forgé depuis votre empreinte cosmique unique

**→ [G1FabLab/monnaie-libre](https://opencollective.com/monnaie-libre/contribute)** (dons & soutien G1FabLab)

L'invitation est intégrée dans l'app à trois moments :
1. **HookScreen** — après la révélation de l'empreinte Kin Maya
2. **_on_multipass_success** — immédiatement après la création du MULTIPASS
3. **Profil** — bouton permanent dans la carte identité

---

## 🔑 Clé biométrique sociale

La méthode de dérivation salt/pepper n'est pas seulement cryptographique — elle est **socialement mémorable**. Les personnes qui connaissent bien l'utilisateur (parents, proches) peuvent reconstituer les données de naissance :

> *"Né le 17 avril 1985 à 15h30, à Paris, 3.2 kg"*

Ces données sont à la fois :
- **Personnelles** (entropie suffisante pour la sécurité)
- **Transmissibles** (backup vivant par les proches)
- **Vérifiables** (les parents connaissent le poids et l'heure)

C'est une forme de **cryptographie sociale** : vos proches sont votre phrase de récupération.

---

## 🔗 Écosystème & Ressources

*   **Astroport.ONE :** [github.com/papiche/Astroport.ONE](https://github.com/papiche/Astroport.ONE)
*   **Projet Phi2X :** [github.com/papiche/Phi2X](https://github.com/papiche/Phi2X)
*   **UPlanet / MineLife :** [github.com/papiche/UPlanet](https://github.com/papiche/UPlanet)
*   **G1FabLab :** [opencollective.com/monnaie-libre](https://opencollective.com/monnaie-libre/contribute)
