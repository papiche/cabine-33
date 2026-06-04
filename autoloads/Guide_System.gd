extends Node
# Système d'onboarding ATOM4LOVE — 7 étapes

signal step_changed(step_index, title, text)
signal guide_completed

const STEPS: Array = [
	{
		"title": "🌌 Bienvenue dans ATOM4LOVE",
		"text": "ATOM4LOVE est un interféromètre cosmique et social.\n\nChaque être humain rayonne une fréquence unique dérivée de sa date et lieu de naissance. Cette app te permet de détecter les résonances Φ avec d'autres atomes proches ou dans le réseau N² mondial.\n\nTouche SUIVANT pour commencer."
	},
	{
		"title": "🔑 Forge ton MULTIPASS",
		"text": "Ton identité dans l'écosystème UPlanet repose sur une paire de clés NOSTR (nsec2 / npub2) dérivée de tes identifiants.\n\nTu peux soit :\n• Créer un nouveau MULTIPASS avec email + mot de passe\n• Importer une clé nsec1 existante → elle sera coupée en sel + poivre pour forger ton nsec2\n\nTon identité est stockée localement. L'email ne sert qu'au dérivation de la clé."
	},
	{
		"title": "⚛ Configure ton Profil ATOM4LOVE",
		"text": "Renseigne tes données de naissance pour activer le moteur de résonance Φ :\n\n• Date et heure de naissance\n• Lieu de naissance (latitude / longitude)\n• Sexe biologique (Onde Φ ou Onde Octave)\n• Taille et poids (calibrage de ω_bio)\n\nCes données restent sur ton appareil. Seule ta phase φ_i peut être diffusée localement via WiFi (mode LOCA)."
	},
	{
		"title": "📡 Connecte tes relais NOSTR",
		"text": "ATOM4LOVE utilise le protocole NOSTR pour diffuser ton profil et détecter les atomes dans le réseau N².\n\nDes relais publics sont pré-configurés. Tu peux en ajouter depuis l'onglet NOSTR PROFIL.\n\nUn relais de ta constellation locale (relay.copylaradio.com) est inclus par défaut pour la découverte P2P."
	},
	{
		"title": "📶 Mode LOCA — Détecte les Atomes proches",
		"text": "En mode LOCA, ton appareil diffuse ta phase φ_i et ton sexe biologique via le nom WiFi (SSID).\n\nLes autres utilisateurs ATOM4LOVE à portée WiFi détectent automatiquement ta présence et calculent la résonance k entre vous.\n\nSi k ≥ 0.95 (Singularité Optique), une vibration rythmique Φ signale le Match Quantique.\n\nTu peux aussi partager l'APK directement via WiFi local (bouton PARTAGER)."
	},
	{
		"title": "🌍 Mode GLOBAL — Réseau N²",
		"text": "En mode GLOBAL, tu accèdes au réseau N² (amis d'amis) via les relais NOSTR.\n\nTu peux :\n• Suivre d'autres atomes (kind 3)\n• Calculer les résonances Φ avec tout le réseau\n• Accéder à la Cabine-33 (création participative) si tu es certifié N²\n\nLa Cabine-33 se déverrouille quand tu es à moins de 50m du nœud Phi le plus proche."
	},
	{
		"title": "🏁 Prêt·e à interférer !",
		"text": "Tu maîtrises maintenant les bases d'ATOM4LOVE.\n\n• ⚛ PROFIL — Configure ton identité et tes données de naissance\n• 📡 NOSTR — Gère ton profil kind 0 et tes relais\n• 📶 LOCA — Détecte les atomes locaux\n• 🌍 GLOBAL — Explore le réseau N²\n• 🏛 CABINE 33 — Crée avec d'autres atomes\n\nBonne interférence cosmique ! 🌌"
	}
]

var current_step: int = -1
var _panel: PanelContainer = null

func show_guide(from_step: int = 0):
	current_step = from_step
	_show_current_step()

func next_step():
	if current_step < STEPS.size() - 1:
		current_step += 1
		_show_current_step()
	else:
		_close_guide()
		emit_signal("guide_completed")

func prev_step():
	if current_step > 0:
		current_step -= 1
		_show_current_step()

func _show_current_step():
	var step = STEPS[current_step]
	emit_signal("step_changed", current_step, step["title"], step["text"])
	_rebuild_panel(step["title"], step["text"])

func _close_guide():
	if is_instance_valid(_panel):
		# Détruire aussi le CanvasLayer parent créé dans _rebuild_panel
		var parent := _panel.get_parent()
		if is_instance_valid(parent) and parent is CanvasLayer and parent.name == "GuideCanvasLayer":
			parent.queue_free()
		else:
			_panel.queue_free()
		_panel = null

func _rebuild_panel(title: String, text: String):
	_close_guide()

	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel.z_index = 100

	var bg = StyleBoxFlat.new()
	bg.bg_color = Color(0.03, 0.06, 0.12, 0.97)
	bg.border_width_left = 3; bg.border_width_right = 3
	bg.border_color = Color(0.1, 0.8, 1.0, 0.7)
	bg.set_corner_radius_all(20)
	_panel.add_theme_stylebox_override("panel", bg)

	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 30)
	margin.add_theme_constant_override("margin_right", 30)
	margin.add_theme_constant_override("margin_top", 40)
	margin.add_theme_constant_override("margin_bottom", 30)
	_panel.add_child(margin)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 20)
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(vbox)

	# Indicateur d'étape
	var step_lbl = Label.new()
	step_lbl.text = "Étape %d / %d" % [current_step + 1, STEPS.size()]
	step_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	step_lbl.add_theme_font_size_override("font_size", 14)
	step_lbl.modulate = Color(0.5, 0.8, 1.0)
	vbox.add_child(step_lbl)

	# Titre
	var title_lbl = Label.new()
	title_lbl.text = title
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.add_theme_font_size_override("font_size", 22)
	title_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(title_lbl)

	vbox.add_child(HSeparator.new())

	# Contenu
	var content_lbl = Label.new()
	content_lbl.text = text
	content_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content_lbl.add_theme_font_size_override("font_size", 16)
	content_lbl.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	content_lbl.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(content_lbl)

	vbox.add_child(HSeparator.new())

	# Boutons navigation
	var hbox = HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 20)
	vbox.add_child(hbox)

	if current_step > 0:
		var btn_prev = Button.new()
		btn_prev.text = "◀ PRÉCÉDENT"
		btn_prev.custom_minimum_size = Vector2(140, 50)
		btn_prev.connect("pressed", Callable(self, "prev_step"))
		hbox.add_child(btn_prev)

	var btn_next = Button.new()
	if current_step < STEPS.size() - 1:
		btn_next.text = "SUIVANT ▶"
	else:
		btn_next.text = "✅ COMMENCER"
	btn_next.custom_minimum_size = Vector2(160, 55)
	btn_next.add_theme_font_size_override("font_size", 18)
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.6, 1.0, 0.9)
	style.set_corner_radius_all(12)
	btn_next.add_theme_stylebox_override("normal", style)
	btn_next.connect("pressed", Callable(self, "next_step"))
	hbox.add_child(btn_next)

	var btn_skip = Button.new()
	btn_skip.text = "✖ FERMER"
	btn_skip.custom_minimum_size = Vector2(100, 40)
	btn_skip.connect("pressed", Callable(self, "_close_guide"))
	vbox.add_child(btn_skip)

	# Encapsuler dans un CanvasLayer à haut z-index pour apparaître au-dessus de toute l'UI
	var tree = Engine.get_main_loop() as SceneTree
	if tree and is_instance_valid(tree.current_scene):
		var canvas := CanvasLayer.new()
		canvas.layer = 150   # au-dessus des menus (z≈0..100) et de l'aide (z=92)
		canvas.name  = "GuideCanvasLayer"
		canvas.add_child(_panel)
		tree.current_scene.add_child(canvas)
	else:
		push_error("Guide_System: scène courante invalide, panel non ajouté")
