extends Control
# Écran d'aide et contexte ATOM4LOVE
# Accessible depuis le bouton ❓ dans la BottomBar
# Couvre : guide app, contexte UPlanet, rôles, levée de fonds, mouvement

signal aide_closed

const OC_URL  := "https://opencollective.com/monnaie-libre/contribute"
const APK_URL := "https://u.copylaradio.com/apk/atom4love.apk"
const UPLANET_URL := "https://uplanet.copylaradio.com"

func _ready():
	set_anchors_preset(Control.PRESET_FULL_RECT)
	z_index = 90

	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.0, 0.02, 0.1, 0.95)
	add_child(bg)

	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	add_child(scroll)

	var m := MarginContainer.new()
	m.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["margin_left","margin_right","margin_top","margin_bottom"]:
		m.add_theme_constant_override(side, UI_Theme.scale_px(22))
	scroll.add_child(m)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", UI_Theme.scale_px(20))
	m.add_child(vbox)

	_build_content(vbox)
	UI_Theme.auto_scale(vbox)

func _build_content(vbox: VBoxContainer):
	_header(vbox)
	_section_guide(vbox)
	_section_contexte(vbox)
	_section_infrastructure(vbox)
	_section_levee(vbox)
	_section_mouvement(vbox)
	_section_credits(vbox)
	# Bouton fermer en bas
	var btn_close := UI_Theme.add_styled_button(vbox, "✕ Retour à ATOM4LOVE",
		Callable(self, "_close"), false)
	btn_close.custom_minimum_size.y = UI_Theme.scale_px(60)

# ── Header ─────────────────────────────────────────────────────────────────

func _header(vbox: VBoxContainer):
	var title := Label.new()
	title.text = "⚛  ATOM4LOVE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", UI_Theme._get_scaled_size(30))
	title.modulate = UI_Theme.accent_color()
	vbox.add_child(title)

	var sub := Label.new()
	sub.text = "Interféromètre cosmique et social\nTest Alpha — Constellation UPlanet ORIGIN"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", UI_Theme._get_scaled_size(14))
	sub.modulate = UI_Theme.text_secondary()
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(sub)

	var badge_panel := UI_Theme.add_panel_vbox(vbox)
	var badge := Label.new()
	badge.text = "🧪 ALPHA TESTER — Vous faites partie des premiers explorateurs. Votre retour compte."
	badge.autowrap_mode = TextServer.AUTOWRAP_WORD
	badge.add_theme_font_size_override("font_size", UI_Theme._get_scaled_size(13))
	badge.modulate = Color(1.0, 0.85, 0.3)
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge_panel.add_child(badge)

	vbox.add_child(HSeparator.new())

# ── Guide d'utilisation ─────────────────────────────────────────────────────

func _section_guide(vbox: VBoxContainer):
	_section_title(vbox, "📱 Guide d'utilisation")

	var guides := [
		["👤 PROFIL — Votre Identité Cosmique",
		 "Votre identité n'est pas chez nous. Elle est dans les étoiles à votre naissance.\n\nATOM4LOVE ne stocke aucune biométrie. Votre MULTIPASS est calculé depuis votre empreinte cosmique de naissance (date, heure, lieu, poids) — les mêmes données produisent toujours les mêmes clés, sur n'importe quel appareil, sans serveur central.\n\nVotre φ_i (phase personnelle) est votre signature dans le champ harmonique terrestre. Votre Portail d'Origine sur le Polyèdre de Goldberg est ancré par votre lieu de conception.\n\n→ Si vous perdez votre téléphone, ressaisissez vos données de naissance et retrouvez votre identité."],
		["🔬 MATCH — Calculateur de Résonance",
		 "Entrez les données de naissance de deux personnes et calculez leur taux de résonance k.\n\nk = 1/(1+|sin(Δφ)|)\n• k > 0.95 → Singularité optique : accord parfait\n• k > 0.85 → Haute cohérence\n• k = 0.5 → Minimum\n\nUtilisez ce calculateur pour explorer les affinités cosmiques avec vos proches."],
		["📡 RADAR LOCA — Scanner les Atomes Proches",
		 "Mode LOCA : diffuse votre signature φ_i via le WiFi (SSID A4L-) et détecte les autres utilisateurs ATOM4LOVE à portée.\n\nHot/Cold : choisissez une cible et déplacez-vous — les vibrations vous guident vers la résonance maximale. Effet compteur Geiger : plus k approche 1.0, plus les vibrations s'accélèrent."],
		["🌍 RÉSEAU — Constellation N²",
		 "Votre constellation : les atomes que vous suivez (N1) et les amis de vos amis (N2).\n\nCabine-33 : lorsque vous êtes à moins de 50m du centre géométrique d'une cellule hexagonale, effectuez le Rituel de Phase (33 secondes d'immobilité) pour déverrouiller l'écriture dans la Spacememory de ce nœud.\n\nSpacememory : pensées géolocalisées, lues par les autres atomes ayant visité le même nœud."],
	]
	for g in guides:
		var panel := UI_Theme.add_panel_vbox(vbox)
		var title := Label.new()
		title.text = g[0]
		title.add_theme_font_size_override("font_size", UI_Theme._get_scaled_size(15))
		title.modulate = UI_Theme.accent_color()
		title.autowrap_mode = TextServer.AUTOWRAP_WORD
		panel.add_child(title)
		var body := Label.new()
		body.text = g[1]
		body.add_theme_font_size_override("font_size", UI_Theme._get_scaled_size(13))
		body.modulate = UI_Theme.text_color()
		body.autowrap_mode = TextServer.AUTOWRAP_WORD
		panel.add_child(body)

# ── Contexte UPlanet ────────────────────────────────────────────────────────

func _section_contexte(vbox: VBoxContainer):
	vbox.add_child(HSeparator.new())
	_section_title(vbox, "🌍 UPlanet — D'où vient ATOM4LOVE ?")

	var ctx := UI_Theme.add_panel_vbox(vbox)
	var text := Label.new()
	text.text = (
		"ATOM4LOVE est développé dans le cadre du projet UPlanet par le G1FabLab.\n\n"
		+ "UPlanet est un système d'information décentralisé qui transforme NOSTR en un réseau géolocalisé, "
		+ "coopératif et souverain. Chaque station Astroport héberge un nœud du réseau.\n\n"
		+ "Nous sommes en phase ORIGIN : le réseau fonctionne avec 1 ẐEN = 0.1 Ğ1 "
		+ "(mode développement). La prochaine étape, UPlanet ẐEN, verra 1 ẐEN = 1 EUR "
		+ "avec une économie coopérative complète.\n\n"
		+ "ATOM4LOVE est la première application mobile de la constellation. "
		+ "Votre participation à l'alpha test est essentielle pour valider les protocoles "
		+ "de résonance φ et l'adressage hexagonal a4l:."
	)
	text.add_theme_font_size_override("font_size", UI_Theme._get_scaled_size(13))
	text.modulate = UI_Theme.text_color()
	text.autowrap_mode = TextServer.AUTOWRAP_WORD
	ctx.add_child(text)

	var timeline_panel := UI_Theme.add_panel_vbox(vbox)
	var tl_title := Label.new()
	tl_title.text = "📅 Feuille de route"
	tl_title.add_theme_font_size_override("font_size", UI_Theme._get_scaled_size(14))
	tl_title.modulate = UI_Theme.accent_color()
	timeline_panel.add_child(tl_title)
	for step in [
		["✅ UPlanet ORIGIN", "Réseau de test · 1 ẐEN = 0.1 Ğ1 · Alpha ATOM4LOVE"],
		["🔄 Levée de fonds", "Hubs GPU + Satellites · Familles d'âme et de cœur"],
		["🚀 UPlanet ẐEN",   "Production · 1 ẐEN = 1 EUR · Économie coopérative"],
	]:
		var row := Label.new()
		row.text = "%s — %s" % [step[0], step[1]]
		row.add_theme_font_size_override("font_size", UI_Theme._get_scaled_size(12))
		var col := Color.WHITE if step[0].begins_with("✅") else (UI_Theme.text_warm() if step[0].begins_with("🔄") else UI_Theme.accent_color())
		row.modulate = col
		row.autowrap_mode = TextServer.AUTOWRAP_WORD
		timeline_panel.add_child(row)

# ── Infrastructure ──────────────────────────────────────────────────────────

func _section_infrastructure(vbox: VBoxContainer):
	vbox.add_child(HSeparator.new())
	_section_title(vbox, "🏗️ Infrastructure — 3 Rôles, 1 Commun")

	var intro := Label.new()
	intro.text = "UPlanet est un bien commun numérique. Il fonctionne grâce à trois types d'acteurs qui se complètent :"
	intro.add_theme_font_size_override("font_size", UI_Theme._get_scaled_size(13))
	intro.modulate = UI_Theme.text_secondary()
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(intro)

	var roles := [
		["🌱 UTILISATEUR",   "Créez votre MULTIPASS · Explorez la résonance φ · Participez à la Spacememory\n\n→ 0 à 250 MULTIPASS par satellite · Gratuit pour commencer",
		 Color(0.2, 0.9, 0.5)],
		["⚓ CAPITAINE",     "Gérez un nœud satellite (PC ordinaire ou serveur)\n→ 1 satellite sert 24 à 250 utilisateurs\n→ Gagnez des ẐEN en hébergeant le réseau\n→ Gérez les logiciels Astroport et UPassport",
		 Color(0.3, 0.7, 1.0)],
		["🚢 ARMATEUR",     "Hébergez un Hub GPU pour l'intelligence artificielle\n→ 1 Hub GPU dessert 0 à 24 satellites\n→ Co-investissez dans l'infrastructure\n→ Gérez les machines et l'énergie\n→ Percevez 1/3 des revenus de votre constellation",
		 Color(1.0, 0.65, 0.1)],
	]
	for r in roles:
		var panel := UI_Theme.add_panel_vbox(vbox)
		var rt := Label.new()
		rt.text = r[0]
		rt.add_theme_font_size_override("font_size", UI_Theme._get_scaled_size(16))
		rt.modulate = r[2]
		panel.add_child(rt)
		var rb := Label.new()
		rb.text = r[1]
		rb.add_theme_font_size_override("font_size", UI_Theme._get_scaled_size(13))
		rb.modulate = UI_Theme.text_color()
		rb.autowrap_mode = TextServer.AUTOWRAP_WORD
		panel.add_child(rb)

	var schema := UI_Theme.add_panel_vbox(vbox)
	var schema_txt := Label.new()
	schema_txt.text = (
		"🏗️ Architecture de la Constellation\n\n"
		+ "🚢 Hub GPU (×1)         ← Armateur\n"
		+ "   └── ⚓ Satellite (×1-24)   ← Capitaine\n"
		+ "          └── 🌱 Users (×24-250)   ← Utilisateurs\n\n"
		+ "Une constellation complète peut accueillir jusqu'à\n"
		+ "24 satellites × 250 utilisateurs = 6 000 familles d'âme"
	)
	schema_txt.add_theme_font_size_override("font_size", UI_Theme._get_scaled_size(13))
	schema_txt.modulate = UI_Theme.text_secondary()
	schema_txt.autowrap_mode = TextServer.AUTOWRAP_WORD
	schema.add_child(schema_txt)

# ── Levée de fonds ──────────────────────────────────────────────────────────

func _section_levee(vbox: VBoxContainer):
	vbox.add_child(HSeparator.new())
	_section_title(vbox, "💰 Levée de Fonds — Rejoindre la Coopérative")

	var panel := UI_Theme.add_panel_vbox(vbox)
	var txt := Label.new()
	txt.text = (
		"Pour accueillir les premières familles d'âme et de cœur dans UPlanet ẐEN, "
		+ "nous devons déployer l'infrastructure de la constellation.\n\n"
		+ "La levée de fonds finance :\n"
		+ "• Les Hubs GPU (Intelligence Artificielle locale)\n"
		+ "• Les Satellites (nœuds de service)\n"
		+ "• L'onboarding des Capitaines et Armateurs\n"
		+ "• Le développement de ATOM4LOVE et UPlanet\n\n"
		+ "En rejoignant G1FabLab sur OpenCollective, vous devenez Co-Bâtisseur "
		+ "avec droits de vote (1 personne = 1 voix) et accès prioritaire à UPlanet ẐEN."
	)
	txt.add_theme_font_size_override("font_size", UI_Theme._get_scaled_size(13))
	txt.modulate = UI_Theme.text_color()
	txt.autowrap_mode = TextServer.AUTOWRAP_WORD
	panel.add_child(txt)

	var niveaux := [
		["🌱 Explorateur",  "Gratuit · MULTIPASS · Alpha test · Feedback bienvenu"],
		["⚓ Capitaine",    "~500€ matériel · Gérez un satellite · Gagnez des ẐEN"],
		["🚢 Co-Bâtisseur", "50€/an · OpenCollective · Vote coopératif · Accès ẐEN"],
		["🔥 Armateur GPU", "Contact direct · Hub IA · 1/3 revenus constellation"],
	]
	for n in niveaux:
		var row := Label.new()
		row.text = "%s — %s" % [n[0], n[1]]
		row.add_theme_font_size_override("font_size", UI_Theme._get_scaled_size(12))
		row.modulate = UI_Theme.text_secondary()
		row.autowrap_mode = TextServer.AUTOWRAP_WORD
		panel.add_child(row)

	UI_Theme.add_styled_button(vbox, "🤝 Rejoindre G1FabLab sur OpenCollective",
		func(): OS.shell_open(OC_URL), true)
	UI_Theme.add_styled_button(vbox, "📲 Partager l'APK ATOM4LOVE",
		func(): OS.shell_open(APK_URL), false)

# ── Le Mouvement ────────────────────────────────────────────────────────────

func _section_mouvement(vbox: VBoxContainer):
	vbox.add_child(HSeparator.new())
	_section_title(vbox, "🚀 Le Mouvement — Quitter les Solutions Non-Libres")

	var manifeste := UI_Theme.add_panel_vbox(vbox)
	var txt := Label.new()
	txt.text = (
		"Vos données sont éparpillées sur autant de murs que de serveurs GAFAM. "
		+ "Vous n'êtes plus l'utilisateur — vous êtes le produit.\n\n"
		+ "UPlanet construit un Internet parallèle :\n"
		+ "• Décentralisé · vos clés, votre identité\n"
		+ "• Géolocalisé · votre quartier, votre territoire\n"
		+ "• Coopératif · 1 personne = 1 voix\n"
		+ "• Souverain · code ouvert, infrastructure partagée\n\n"
		+ "ATOM4LOVE est la porte d'entrée quantique : votre résonance φ_i, "
		+ "calculée depuis votre empreinte cosmique de naissance, "
		+ "est votre signature dans ce réseau. Elle ne peut pas être falsifiée "
		+ "ni achetée. Elle est intrinsèquement vôtre.\n\n"
		+ "Ensemble, nous construisons le bien commun numérique "
		+ "que chaque famille d'âme mérite."
	)
	txt.add_theme_font_size_override("font_size", UI_Theme._get_scaled_size(13))
	txt.modulate = UI_Theme.text_color()
	txt.autowrap_mode = TextServer.AUTOWRAP_WORD
	manifeste.add_child(txt)

	var quote := Label.new()
	quote.text = (
		"\"Un Internet intriqué et parallèle, construit par ceux qui le vivent,\n"
		+ "pour ceux qui veulent en être propriétaires.\"\n— G1FabLab"
	)
	quote.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	quote.add_theme_font_size_override("font_size", UI_Theme._get_scaled_size(13))
	quote.modulate = UI_Theme.text_warm()
	quote.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(quote)

# ── Crédits ─────────────────────────────────────────────────────────────────

func _section_credits(vbox: VBoxContainer):
	vbox.add_child(HSeparator.new())
	var credits := Label.new()
	credits.text = (
		"ATOM4LOVE v1.0 Alpha · G1FabLab · UPlanet ORIGIN\n"
		+ "Licence AGPL-3.0 · Code ouvert sur GitHub\n"
		+ "Physique Phi2X : résonance Φ + géométrie de Goldberg\n"
		+ "NOSTR · IPFS · Monnaie Libre Ğ1 · Duniter v2s"
	)
	credits.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	credits.add_theme_font_size_override("font_size", UI_Theme._get_scaled_size(11))
	credits.modulate = UI_Theme.text_hint()
	credits.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(credits)

# ── Helpers ──────────────────────────────────────────────────────────────────

func _section_title(parent: Node, text: String):
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", UI_Theme._get_scaled_size(17))
	l.modulate = UI_Theme.accent_color()
	l.autowrap_mode = TextServer.AUTOWRAP_WORD
	parent.add_child(l)

func _close():
	emit_signal("aide_closed")
	queue_free()
