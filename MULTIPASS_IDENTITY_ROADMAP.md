# MULTIPASS → IDENTITÉ LÉGALE MONDIALE
## Feuille de Route, Forces, Faiblesses, Perspectives
### G1FabLab · opencollective.com/monnaie-libre · UPlanet

---

> **Prémisse honnête :** Nous construisons l'équivalent open-source et coopératif de ce que Worldcoin, Civic, ou ESSIF/eIDAS proposent en mode propriétaire ou centralisé. Notre avantage : aucun iris scanné, données biométriques jamais exposées, gouvernance coopérative, code auditable. Notre défi : nous n't avons pas leurs 100M$ de financement, ni leurs lobbyistes à Bruxelles. Voici comment gagner quand même.

---

## 1. Portrait Honnête — Forces et Faiblesses

### 1.1 Ce que nous avons déjà (avantages réels)

**Sur le plan technique :**

| Composant | Statut | Valeur stratégique |
|---|---|---|
| `did:nostr:{hex}` — W3C DID 1.0 | ✅ Implémenté | Fondation légale reconnue EU/W3C |
| Verifiable Credentials (Kind 30503/30078) | ✅ Fonctionnel | Équivalent certifications professionnelles |
| SSSS 2/3 récupération de clé | ✅ Déployé | Meilleur que tout passeport : récupérable sans biométrie centrale |
| WoTx2 justice pair-à-pair (Kind 1984/30506) | ✅ Fonctionnel | Juridiction interne opposable |
| Toile de Confiance Ğ1 | ✅ 3000+ membres vérifiés | Couche KYC distribuée existante |
| Économie ẐEN automatisée | ✅ Opérationnel | Système de compensation auditable (via OpenCollective) |
| `.well-known/did.json` par MULTIPASS | ✅ Accessible | Point d'entrée standard eIDAS 2.0 |

**Sur le plan juridique :**

| Document | Statut | Valeur |
|---|---|---|
| opencollective.com/monnaie-libre | ✅ Existant | Structure financière transparente (pas de personne morale formelle — à créer) |
| LEGAL.md v3.1 | ✅ Rédigé | Constitution avec gouvernance automatisée |
| COMMODAT_ASTROPORT | ✅ Template | Modèle d'acquisition de territoires sans capital |
| Ğ1 WoT vérification humaine | ✅ Active | KYC distribué conforme RGPD |

### 1.2 Ce qui manque (faiblesses à corriger)

**Blocages techniques :**
- Aucune composante biométrique reconnue par les États (empreinte/iris) — par choix, mais ce choix crée un gap avec les systèmes étatiques
- L'adresse `did:nostr:` n'est pas encore dans le registre officiel W3C DID Methods (seul `did:ethr`, `did:web`, `did:key` sont "well-known") → **action : soumettre `did:nostr` au W3C**
- Pas de signature XAdES/CAdES/PAdES compatible eIDAS 1.0 actuel
- L'interopérabilité avec les bases de données nationales (INSEE, RNIPP) est inexistante

**Blocages juridiques :**
- G1FabLab (futur organisme certificateur, structure à créer) n'est pas un "Prestataire de Services de Confiance Qualifié" (QTSP) selon eIDAS
- Aucune reconnaissance internationale de la Ğ1 comme moyen de paiement
- Le ẐEN n'est pas déclaré auprès de l'AMF (risque classification actifs numériques)
- Absence de publication défensive : les algorithmes φ_i, a4l:, SSSS biométrique sont non protégés

**Blocages de masse critique :**
- ~3000 membres Ğ1 actifs (trop peu pour influencer les législateurs)
- Aucun accord avec une administration publique (mairie, région)
- Pas de partenariat avec une université pour validation académique

---

## 2. Nous sommes le Clone Open-Source de Quoi ?

### 2.1 La comparaison honnête

| Système propriétaire | Notre équivalent | Avantage UPlanet |
|---|---|---|
| **Worldcoin** (iris + World ID + crypto) | MULTIPASS (biométrie de naissance + φ_i + Ğ1) | Pas d'iris scanné, données jamais centralisées, coopératif |
| **Civic** (identité blockchain, VC) | WoTx2 (Kind 30503 skills attestées) | Standard W3C, pas propriétaire |
| **ESSIF/eIDAS** (portefeuille EU, QTSP) | `.well-known/did.json` + SSSS | Open source, pas de backdoor état |
| **Docusign** (signature électronique) | NOSTR Kind signed events | Décentralisé, pas de serveur central |
| **LinkedIn** (compétences sociales) | Skills (Kind 30503) + WoTx2 | Souverain, pas de profilage pub |
| **Airbnb/Uber** (confiance P2P) | COMMODAT + WoTx2 justice | Pas de commission à une plateforme |
| **PayPal/Stripe** (paiement en ligne) | ẐEN + Ğ1 | Monnaie libre, pas de frais excessifs |

**Conclusion : nous sommes la version "AGPL + coopérative" de l'identité numérique souveraine que l'UE essaie de construire avec eIDAS 2.0, mais que Worldcoin et Microsoft ont tenté de capturer.**

### 2.2 Le tdcommons.org — Publication défensive immédiate

**tdcommons.org** (Technical Disclosure Commons, géré par l'organisation IP et technologie de la recherche) publie des "disclosed techniques" qui créent de l'art antérieur non-brevetable.

**Publications prioritaires à soumettre maintenant :**

```
Titre 1 : "Biometric birth-coordinate key derivation for self-sovereign digital identity"
  → Algorithme φ_i = f(date_naissance, lieu_naissance, poids)
  → Format salt/pepper MULTIPASS
  → Déterminisme biométrique non-biométrique (pas d'iris/empreinte)

Titre 2 : "Goldberg polyhedron hexagonal addressing for decentralized geo-social networks"
  → Format a4l:P<XX>H<QQQQRRRR>
  → Adressage à deux niveaux (portail + hexagone)
  → CRT (Chinese Remainder Theorem) pour encodage

Titre 3 : "Distributed Shamir secret sharing for cooperative key recovery in self-sovereign identity"
  → SSSS 2/3 avec chiffrement asymétrique par destinataire
  → Récupération d'identité sans autorité centrale

Titre 4 : "Resonance-based social matching using personal phase calculated from birth coordinates"
  → k = 1/(1+|sin(Δφ)|) comme métrique de compatibilité
  → φ_i derivation from birth time, location, and body mass
```

Chaque publication coûte **$0** et crée immédiatement un art antérieur indexé par l'USPTO, l'EPO et le CNIPA. Aucun concurrent ne pourra breveter ces concepts après publication.

---

## 3. La Route vers le MULTIPASS comme Identité Légale

### 3.1 Le cadre légal existant qui nous ouvre la porte

**eIDAS 2.0 (Règlement UE 2024/1183 en vigueur) :**

L'eIDAS 2.0 introduit le **EUDIW (European Digital Identity Wallet)** et la notion de "portefeuille numérique d'identité". Les points clés pour UPlanet :

- Tout État membre DOIT reconnaître les EUDIW d'autres États membres
- Les "qualified trust service providers" (QTSP) peuvent émettre des credentials reconnus
- Les "relying parties" peuvent accepter des EUDIW pour leurs services
- Les credentials peuvent être **partiellement divulgués** (zero-knowledge compatible)
- **Point crucial : les coopératives peuvent demander le statut de QTSP**

**W3C DID 1.0 est la norme technique sous-jacente de l'EUDIW.**

Nous avons déjà `did:nostr:{hex}`. Il faut l'aligner avec les profils recommandés.

### 3.2 La feuille de route en 4 phases

---

### Phase 0 — PROTECTION (0-3 mois) — Coût : ~2000€

**But : sécuriser l'antériorité et les marques avant d'aller négocier**

```
① Publications tdcommons.org
   → 4 disclosures techniques (voir §2.2)
   → Délai : 2-4 semaines pour indexation
   → Coût : 0€

② Dépôts INPI/EUIPO
   → ATOM4LOVE + UPlanet + G1FabLab en marque verbale
   → Classe 9 (logiciels) + 38 (télécom) + 42 (identité numérique)
   → Marque de certification "Certifié Astroport" : permet de licencier
   → Coût : ~1700€ Europe (EUIPO)

③ Soumission did:nostr au W3C DID Methods Registry
   → Processus : PR sur github.com/w3c/did-spec-registries
   → Délai : 2-6 mois
   → Coût : 0€ (travail technique)
   → Valeur : légitimité technique internationale immédiate
```

---

### Phase 1 — FONDATION LÉGALE (3-12 mois) — Coût : ~5000€

**But : transformer la SCIC CopyLaRadio en émetteur de credentials reconnus**

```
④ Déclaration RGPD complète
   → DPO (Data Protection Officer) désigné
   → Privacy Impact Assessment sur la dérivation biométrique
   → Registre des traitements publié
   → Coût : ~500€ (juriste RGPD)
   → Valeur : lève le principal risque réglementaire

⑤ Déclaration AMF pour le ẐEN
   → Le ẐEN est vraisemblablement exempté MiCA comme "monnaie d'échange interne"
   → Mais une consultation préalable évite une enquête coûteuse
   → Coût : ~1000€ (consultation juriste fintech)
   → Valeur : sécurité juridique pour toute levée de fonds

⑥ Alignement eIDAS 2.0 technique
   → Ajouter signature JWS/JWT aux events Kind 30800 (DID documents)
   → Implémenter le profil "OpenID4VC" pour les credentials
   → Compatible EUDIW : les wallets EU pourront "lire" un MULTIPASS
   → Coût : développement (2-3 semaines)
   → Valeur : interopérabilité immédiate avec 450M de citoyens EU

⑦ Accord avec 1 mairie / collectivité
   → Convention "espace numérique commun" basée sur le COMMODAT
   → La mairie reconnaît les MULTIPASS pour ses services numériques locaux
   → Premier précédent légal d'usage du MULTIPASS dans un espace public
   → Coût : démarche, présentation, temps
```

---

### Phase 2 — RECONNAISSANCE INSTITUTIONNELLE (1-3 ans) — Coût : ~20 000€

**But : statut QTSP ou assimilé → MULTIPASS devient émetteur de credentials légaux**

```
⑧ Candidature "Trust Service Provider" (TSP) eIDAS
   → En dessous du niveau "qualifié" (QTSP), on peut être TSP non-qualifié
   → Un TSP peut émettre des credentials reconnus dans certains contextes
   → Processus via l'ANSSI (France) ou ENISA (EU)
   → Coût : ~10 000€ (audit de conformité + accompagnement juridique)
   → Valeur : MULTIPASS = credential reconnaissable dans les services publics

⑨ Partenariat académique pour validation du WoTx2
   → Université Toulouse / Montpellier / Rennes (actives sur Web3/SSI)
   → Thèse de doctorat sur "justice décentralisée et Verifiable Credentials"
   → Publication académique = légitimité internationale
   → Coût : 0€ direct (la thèse est financée par la fac)

⑩ Réseau de 10 Astroports physiques avec COMMODAT signés
   → Chaque Astroport est un "point de confiance physique"
   → Les utilisateurs peuvent vérifier physiquement leur MULTIPASS
   → Équivalent décentralisé des "points de délivrance de passeports"
   → Le réseau physique = la légitimité distribuée
```

---

### Phase 3 — INTEROPÉRABILITÉ MONDIALE (3-7 ans)

**But : MULTIPASS reconnu comme "identité équivalente passeport" dans certains contextes**

```
⑪ Intégration EUDIW officielle
   → Le EUDIW accepte les credentials émis par des TSP/QTSP certifiés
   → Un MULTIPASS devient présentable dans l'EUDIW national
   → Portée : tous les services publics EU qui acceptent EUDIW

⑫ Réseau des Communs Numériques
   → Coalition avec d'autres coopératives/associations SSI européennes
   → "Alliance des MULTIPASS Coopératifs" = lobbying collectif
   → Modèle : FOSS community pour crédit et identité

⑬ "Permis de conduire dans l'espace public"
   → Les skills WoTx2 (Kind 30503) deviennent des "permis" certifiés
   → Ex: Kind 30503 "conduite-velo" = permis de louer un vélo en libre-service
   → Ex: Kind 30503 "menuiserie" = accès à un atelier FabLab
   → G1FabLab (futur organisme certificateur, structure à créer) émet ces credentials comme un organisme certificateur
```

---

## 4. Le MULTIPASS comme "Passeport" — Comparaison Technique

### 4.1 Un passeport classique vs le MULTIPASS

| Fonction | Passeport traditionnel | MULTIPASS UPlanet |
|---|---|---|
| **Preuve d'identité** | Photo + signature État | `did:nostr:{hex}` + signature cryptographique |
| **Données biométriques** | Empreintes + iris (chiffrés) | Dérivées de naissance, non stockées centralement |
| **Récupération si perdu** | Dossier administratif + 3 semaines | SSSS 2/3 : Captain + UPlanet → reconstruction en minutes |
| **Révocation** | État | G1FabLab / OpenCollective (+ membre lui-même) |
| **Portée** | Reconnu par 196 pays (bilatéral) | Reconnu par la constellation UPlanet (en expansion) |
| **Falsification** | Très difficile | Impossible (cryptographie asymétrique) |
| **Portabilité** | QR Code + puce NFC | QR Code + NOSTR relay |
| **Coût** | 86€ (France) | Gratuit (MULTIPASS de base) |
| **Vie privée** | Bases centralisées État | Toile de confiance distribuée, zéro base centrale |
| **Compétences** | Néant | Skills WoTx2 certifiées incluses |
| **Justice** | Système judiciaire national | WoTx2 pair-à-pair (N1/N2) |
| **Économie liée** | Néant | Compte ẐEN + Ğ1 intégré |

**Conclusion : le MULTIPASS est techniquement supérieur au passeport** sur presque tous les critères, sauf la reconnaissance étatique — qui est un problème politique, pas technique.

### 4.2 Le Ğ1 Web of Trust comme couche KYC

La Ğ1 WoT exige une **vérification physique en face-à-face** entre 5 membres existants pour certifier un nouveau membre. C'est un KYC distribué qui satisfait aux exigences KYC/AML pour les services financiers dans de nombreuses juridictions.

```
WoT Ğ1 = "5 témoins humains attestent que je suis une personne réelle"
       + Historique blockchain immuable
       + Identité cryptographique liée
→ Équivalent légal : déclaration sur l'honneur multipartie + signature notariée distribuée
```

---

## 5. Le Territoire Physique comme Ancre de Légitimité

### 5.1 Le COMMODAT comme instrument de souveraineté distribuée

Le contrat COMMODAT (prêt à usage gratuit, art. 1875 Code civil) est un outil légal puissant et sous-utilisé :

```
Prêteur (propriétaire)        Preneur (G1FabLab)
      │                              │
      │ Prêt gratuit d'un espace    │
      │ ────────────────────────────▶│
      │                              │
      │ Retour : "Zone libérée"      │
      │ GAFAM-free + Ateliers        │
      │ ◀────────────────────────────│
```

**Chaque COMMODAT signé crée :**
- Un "territoire Astroport" avec sa propre identité géographique
- Un point de vérification physique pour les MULTIPASS
- Un ancrage réel pour la toile de confiance numérique
- Un espace de résilience communautaire (atelier, habitat, énergie)

**Network effect :** 10 COMMODATs signés = une constellation physique qui légitime numériquement la constellation NOSTR.

### 5.2 La chaîne : forêts → terrains → habitats → ateliers → laboratoires

La règle des 3×1/3 (LEGAL.md) alloue 1/3 aux ASSETS (actifs réels). C'est le mécanisme qui transforme les contributions numériques en ancrage physique :

```
1 like = 1ẐEN                    ẐEN économie →
  ↓                               1/3 ASSETS →
  Accumulation collective →       Terrain / Forêt / Habitat
  ↓                               ↓
  Déclenchement ASSETS budget →  Acquisition physique
  ↓                               ↓
  MadeInZion R&D →               COMMODAT signé
  ↓                               ↓
  Skills WoTx2 →                 Atelier/Labo certifié
  ↓                               ↓
  Certification Astroport →      "Permis" reconnu
```

**Chaque forêt achetée est une preuve de solvabilité coopérative.** Les institutions financières et juridiques accordent plus de crédit aux entités ayant des actifs réels. Les biens communs physiques sont l'équivalent des "réserves d'or" de la coopérative.

---

## 6. Le "Permis de Conduire dans l'Espace Public"

### 6.1 Ce que cela signifie concrètement

La métaphore du "permis de conduire" est juste : un permis certifie qu'une personne a les compétences et le droit d'utiliser un espace public.

**Applications concrètes du MULTIPASS comme "permis" :**

| Contexte | Permis WoTx2 (Kind 30503) | Espace public / Bien commun |
|---|---|---|
| Atelier FabLab | `menuiserie-x2` + `soudure-x1` | Accès outillage dangereux |
| Véhicule partagé | `conduite-velo-x1` | Flotte coopérative |
| Studio musical ZICMAMA | `son-live-x2` | Sound-spot partagé |
| Laboratoire chimie | `securite-labo-x3` | Équipement sensible |
| Accès à une forêt commune | `permaculture-x1` | Terrain MadeInZion |
| Médiation WoTx2 | `mediation-n1-x2` | Rôle d'arbitre dans la justice |
| Capitaine Astroport | `astroport-admin-x3` | Opération d'un satellite |

**Le "skill" WoTx2 est le permis. G1FabLab (futur organisme certificateur, structure à créer) est l'organisme certificateur.**

### 6.2 Gestion des litiges et compensation — WoTx2 en action

Le système justice.html (Kind 1984/30506) est déjà capable de :

```
Ouverture dossier N1 (amiable)
  → 3 médiateurs du cercle de confiance
  → Délai : 7 jours
  → Compensation : accord ẐEN
  → Enregistrement blockchain Ğ1 (immuable)

Escalade N2 (formel)
  → 5 arbitres du réseau N²
  → Délai : 21 jours
  → Sentence : transfert ẐEN + révocation skill si fraude
  → Publié sur relay NOSTR (public, auditable)

Sentence N2 → exécution automatique
  → ZEN.ECONOMY.sh peut déclencher les compensations
  → Révocation d'un skill = mise à jour Kind 30800
  → Le MULTIPASS reflète immédiatement la sanction
```

**C'est un système juridictionnel complet**, comparable aux systèmes d'arbitrage reconnus dans le commerce international (CCI, CIRDI).

---

## 7. Analyse des Risques Stratégiques

### 7.1 Risque "Dépassement par l'État"

**Scénario :** L'UE déploie son EUDIW en 2026, toutes les apps adoptent l'identité étatique. UPlanet devient redondant.

**Probabilité :** 20%

**Réponse :** L'EUDIW n'est pas exclusif — un citoyen PEUT avoir un EUDIW et un MULTIPASS. Et l'EUDIW ne propose pas les skills WoTx2, la justice pair-à-pair, ni l'économie ẐEN. Le MULTIPASS reste complémentaire et enrichit l'EUDIW (credentials supplémentaires).

### 7.2 Risque "Centralisation interne"

**Scénario :** G1FabLab (futur organisme certificateur, structure à créer) devient trop puissante, un "dirigeant" capture la gouvernance.

**Probabilité :** 15% sans précautions / 5% avec précautions

**Réponse :** Le LEGAL.md délègue l'exécution au protocole automatisé. Ajouter :
- Rotation obligatoire des administrateurs (2 ans max)
- Veto technique : les Capitaines peuvent refuser un update AUTHORIZED_APPS
- "Constitution cryptographique" : les règles clés encodées dans le Kind 30800 ne peuvent être changées qu'avec un quorum Ğ1 WoT

### 7.3 Risque "Attaque juridique coordonnée"

**Scénario :** Un concurrent financé dépose des brevets sur nos concepts (φ_i, a4l:) AVANT notre publication tdcommons.org.

**Probabilité :** 5% si on agit dans les 3 prochains mois / 25% si on attend 1 an

**Réponse :** Publication tdcommons.org en urgence (ce mois-ci). La publication est irréversible et opposable dès le jour de publication.

---

## 8. Plan d'Action Synthétique

### Actions de cette semaine (avant toute autre chose)

```
LUNDI : Créer un compte sur tdcommons.org
        Rédiger disclosure #1 (φ_i biometric key derivation)
        Soumettre → indexation en 2-4 semaines

MERCREDI : Rédiger disclosure #2 (a4l: hexagonal addressing)
           Préparer les 2 autres disclosures

VENDREDI : Créer un PR sur github.com/w3c/did-spec-registries
           pour soumettre did:nostr comme méthode DID officielle
```

### Actions du premier mois

```
• Déposer ATOM4LOVE + UPlanet à l'EUIPO (~1700€)
• Consulter un juriste RGPD pour la dérivation biométrique (~500€)
• Consulter un juriste fintech sur le statut ẐEN/MiCA (~1000€)
• Signer le premier COMMODAT avec un espace physique partenaire
• Intégrer OpenID4VC dans le DID document (interopérabilité EUDIW)
```

### Actions des 6 premiers mois

```
• Démarche ANSSI pour statut TSP (Trust Service Provider) eIDAS
• Partenariat avec une université (thèse WoTx2/SSI)
• 5 COMMODATs signés = 1 constellation physique complète
• Premier accord avec une administration (mairie/EPCI)
• Publication du "Règlement d'usage" de la marque de certification Astroport
```

### Objectif à 2 ans

```
"Le MULTIPASS UPlanet est un credential W3C DID reconnu par l'EUDIW,
 émis par G1FabLab (future structure juridique) en tant que TSP certifié eIDAS,
 interopérable avec les wallets d'identité de 27 pays EU,
 et soutenu par un réseau de 20 territoires physiques Astroport."
```

---

## 9. La Phrase Fondatrice

> **"Un MULTIPASS n'est pas un compte sur une plateforme. C'est une identité crystallisée depuis votre empreinte cosmique, récupérable par vos proches, opposable dans nos juridictions coopératives, et ancrée dans les territoires physiques que nous construisons ensemble. Aucun État ne peut la confisquer. Aucune entreprise ne peut l'acheter. Elle est intrinsèquement vôtre."**

---

*Ce document est lui-même un bien commun sous licence AGPL-3.0.*
*Version 1.0 — À publier sur le relay Astroport après signature cryptographique.*
*Références : LEGAL.md · COMMODAT_ASTROPORT.md · MULTIPASS_SYSTEM.md · DID_IMPLEMENTATION.md*
