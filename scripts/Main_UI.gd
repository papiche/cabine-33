extends Control

signal recenter_requested

@onready var state_label = $MarginContainer/VBoxContainer/HeaderPanel/VBoxContainer/StateLabel
@onready var energy_bar = $MarginContainer/VBoxContainer/HeaderPanel/VBoxContainer/EnergyProgressBar
@onready var compass_label = $MarginContainer/VBoxContainer/CompassPanel/CompassLabel
@onready var distance_label = $MarginContainer/VBoxContainer/CompassPanel/DistanceLabel
@onready var module_tabs = $MarginContainer/VBoxContainer/ModuleTabs
@onready var log_text = $MarginContainer/VBoxContainer/ModuleTabs/Historique

@onready var photo_btn = $MarginContainer/VBoxContainer/QuickActions/PhotoBtn
@onready var sync_btn = $MarginContainer/VBoxContainer/QuickActions/SyncBtn

var my_pubkey = "npub1_alpha_000"
var wot_authorized = false
const CABINE_UNLOCK_DISTANCE_KM = 0.05
var setup_panel: PanelContainer

# Interface Caméra
var viewfinder: TextureRect

var email_input: LineEdit
var pass_input: LineEdit
var status_lbl: Label

func _ready():
	self.modulate = Color(1, 1, 1, 0.9)
	
	SpaceTime_Manager.connect("cycle_changed", Callable(self, "_on_cycle_changed"))
	SpaceTime_Manager.connect("energy_updated", Callable(self, "_on_energy_updated"))
	SpaceTime_Manager.connect("gps_updated", Callable(self, "_on_gps_updated"))
	Atom4Peace.connect("encounter_started", Callable(self, "_on_encounter_started"))
	Atom4Peace.connect("reality_forked", Callable(self, "_on_reality_forked"))
	
	UPlanet_API.connect("multipass_created", Callable(self, "_on_multipass_success"))
	UPlanet_API.connect("api_error", Callable(self, "_on_multipass_error"))
	UPlanet_API.connect("network_n2_analyzed", Callable(self, "_on_n2_analyzed"))
	UPlanet_API.connect("sync_completed", Callable(self, "_on_sync_completed"))
	
	var encounter_btn = $MarginContainer/VBoxContainer/ModuleTabs/Radars/EncounterButton
	encounter_btn.connect("pressed", Callable(self, "_simulate_bluetooth_encounter"))
	
	photo_btn.connect("pressed", Callable(self, "_on_photo_pressed"))
	sync_btn.connect("pressed", Callable(self, "_on_sync_pressed"))

	# Ajout dynamique du bouton RECENTRER
	var quick_actions = $MarginContainer/VBoxContainer/QuickActions
	var btn_recenter = Button.new()
	btn_recenter.text = "📍 RECENTRER"
	btn_recenter.custom_minimum_size = Vector2(140, 50)
	btn_recenter.add_theme_font_size_override("font_size", 18)
	btn_recenter.connect("pressed", Callable(self, "_on_recenter_pressed"))
	quick_actions.add_child(btn_recenter)

	_apply_cyber_style()
	_build_camera_viewfinder()
	
	if module_tabs.has_node("Cabine_33"):
		var send_btn = module_tabs.get_node("Cabine_33/SendButton")
		send_btn.connect("pressed", Callable(self, "_on_send_thought_pressed"))
		Thought_Cache.connect("cache_purged", Callable(self, "_on_cache_purged"))
		module_tabs.set_tab_disabled(2, true)
		module_tabs.set_tab_title(2, "[VERROUILLÉ]")
	
	energy_bar.max_value = SpaceTime_Manager.MAX_TOTAL_ENERGY / 3.0
	_on_energy_updated(SpaceTime_Manager.available_matter_energy)
	_on_cycle_changed(SpaceTime_Manager.current_state)
	
	if not Player_Origin.is_initialized:
		_show_multipass_sas()
	else:
		_build_profile_tab()
		_check_authorization()

func _process(_delta):
	if Atom4Peace.active_bonds.size() > 0:
		Atom4Peace.check_bonds_status(SpaceTime_Manager.current_gps)

func _apply_cyber_style():
	# Style translucide "Glassmorphism"
	var glass_style = StyleBoxFlat.new()
	glass_style.bg_color = Color(0, 0.08, 0.15, 0.7) # Bleu profond transparent
	glass_style.border_width_left = 2
	glass_style.border_color = Color(0.1, 0.8, 1.0, 0.6) # Cyan néon
	glass_style.corner_radius_top_right = 30
	glass_style.corner_radius_bottom_left = 30
	glass_style.set_content_margin_all(15)
	glass_style.set_corner_radius_all(30)
	
	# Appliquer aux panneaux principaux
	$MarginContainer/VBoxContainer/HeaderPanel.add_theme_stylebox_override("panel", glass_style)
	
	# Customisation de la barre d'énergie
	var sb_fg = StyleBoxFlat.new()
	sb_fg.bg_color = Color(1.0, 0.7, 0.0, 0.9) # Or
	sb_fg.set_corner_radius_all(5)
	energy_bar.add_theme_stylebox_override("fill", sb_fg)
	
	# Animation de pulsation sur l'interface
	var tween = create_tween().set_loops()
	tween.tween_property(distance_label, "modulate:a", 0.6, 1.2)
	tween.tween_property(distance_label, "modulate:a", 1.0, 1.2)

# --- CREATION DU VISEUR PHOTO ---
func _build_camera_viewfinder():
	viewfinder = TextureRect.new()
	viewfinder.set_anchors_preset(PRESET_FULL_RECT)
	viewfinder.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	viewfinder.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	viewfinder.hide()
	add_child(viewfinder)
	
	var overlay = VBoxContainer.new()
	overlay.set_anchors_preset(PRESET_FULL_RECT)
	overlay.alignment = BoxContainer.ALIGNMENT_END
	viewfinder.add_child(overlay)
	
	var hbox = HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.custom_minimum_size = Vector2(0, 120)
	hbox.add_theme_constant_override("separation", 20)
	overlay.add_child(hbox)
	
	var btn_switch = Button.new()
	btn_switch.text = "🔄 CAM"
	btn_switch.custom_minimum_size = Vector2(80, 60)
	btn_switch.connect("pressed", Callable(Spacememory_Vision, "switch_camera"))
	hbox.add_child(btn_switch)
	
	var btn_take = Button.new()
	btn_take.text = "🔴 CAPTURER"
	btn_take.custom_minimum_size = Vector2(120, 80)
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.8, 0.1, 0.1)
	style.set_corner_radius_all(40)
	btn_take.add_theme_stylebox_override("normal", style)
	btn_take.connect("pressed", Callable(self, "_do_capture"))
	hbox.add_child(btn_take)
	
	var btn_close = Button.new()
	btn_close.text = "❌"
	btn_close.custom_minimum_size = Vector2(80, 60)
	btn_close.connect("pressed", Callable(self, "_close_camera"))
	hbox.add_child(btn_close)

# --- BOUTONS ACTIONS RAPIDES ---
func _on_photo_pressed():
	# Lance la caméra et affiche le viseur par dessus le jeu
	viewfinder.texture = Spacememory_Vision.get_feed_texture()
	viewfinder.show()

func _do_capture():
	Spacememory_Vision.take_real_snapshot()
	_close_camera()
	add_log("📸 Empreinte spatio-temporelle fixée !")

func _close_camera():
	viewfinder.hide()
	if Spacememory_Vision.camera_feed:
		Spacememory_Vision.camera_feed.set_active(false)

func _on_sync_pressed():
	add_log("🔄 Demande de synchronisation au relais...")
	sync_btn.disabled = true
	Thought_Cache.purge_to_spacememory()
	UPlanet_API.sync_with_relay(Player_Origin.user_npub)

func _on_sync_completed(msg):
	add_log("✅ " + msg)
	sync_btn.disabled = false

func _on_recenter_pressed():
	emit_signal("recenter_requested")

# --- VERIFICATION WEB OF TRUST ---
func _check_authorization():
	if Player_Origin.user_email == "anonyme_playground":
		wot_authorized = false
		add_log("👁️ Mode Explorateur (Anonyme). Écriture désactivée.")
	else:
		add_log("🕸️ Interrogation de la Toile de Confiance...")
		UPlanet_API.check_wot_authorization(Player_Origin.user_hex)

func _on_n2_analyzed(is_authorized, total_nodes):
	wot_authorized = is_authorized
	if is_authorized:
		add_log("✅ Accès Cabine-33 Autorisé ! (" + str(total_nodes) + " atomes N2)")
	else:
		add_log("⚠️ Accès Écriture Refusé (Non connecté au réseau N2).")

# --- ONGLET PROFIL ---
func _build_profile_tab():
	if module_tabs.has_node("MULTIPASS"):
		module_tabs.get_node("MULTIPASS").queue_free()
		
	var tab = VBoxContainer.new()
	tab.name = "MULTIPASS"
	tab.alignment = BoxContainer.ALIGNMENT_CENTER
	
	var id_lbl = Label.new()
	id_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	
	if Player_Origin.is_initialized:
		# AJOUT DE L'EMAIL ICI
		var info_text = "📧 Email : " + Player_Origin.user_email + "\n"
		info_text += "🆔 Nostr : " + Player_Origin.user_npub.substr(0, 12) + "..." + Player_Origin.user_npub.substr(-4) + "\n"
		info_text += "💰 G1 Pub : " + Player_Origin.user_g1pub.substr(0, 12) + "..."
		id_lbl.text = info_text
	else:
		id_lbl.text = "Aucun MULTIPASS."
		
	tab.add_child(id_lbl)
	module_tabs.add_child(tab)

# --- SAS DE CONNEXION ---
func _show_multipass_sas():
	if is_instance_valid(setup_panel): setup_panel.queue_free()
	setup_panel = PanelContainer.new()
	setup_panel.set_anchors_preset(PRESET_FULL_RECT)
	
	var bg_style = StyleBoxFlat.new()
	bg_style.bg_color = Color(0.05, 0.08, 0.12, 0.98)
	bg_style.border_width_left = 5; bg_style.border_width_right = 5
	setup_panel.add_theme_stylebox_override("panel", bg_style)
	
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 30)
	margin.add_theme_constant_override("margin_right", 30)
	setup_panel.add_child(margin)
	
	var vbox = VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 15)
	margin.add_child(vbox)
	
	var title = Label.new()
	title.text = "FORGEZ VOTRE MULTIPASS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	vbox.add_child(title)
	
	email_input = LineEdit.new()
	email_input.placeholder_text = "Email (Salt)"
	vbox.add_child(email_input)
	
	pass_input = LineEdit.new()
	pass_input.placeholder_text = "Mot de passe (Pepper)"
	pass_input.secret = true
	vbox.add_child(pass_input)
	
	status_lbl = Label.new()
	status_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(status_lbl)
	
	var btn_forge = Button.new()
	btn_forge.text = "S'INCARNER"
	btn_forge.custom_minimum_size = Vector2(0, 50)
	btn_forge.connect("pressed", Callable(self, "_on_forge_pressed"))
	vbox.add_child(btn_forge)

	if not Player_Origin.is_initialized or Player_Origin.user_email != "anonyme_playground":
		vbox.add_child(HSeparator.new())
		var btn_anon = Button.new()
		btn_anon.text = "MODE ANONYME"
		btn_anon.custom_minimum_size = Vector2(0, 40)
		btn_anon.connect("pressed", Callable(self, "_on_anonymous_pressed"))
		vbox.add_child(btn_anon)
	
	var btn_cancel = Button.new()
	btn_cancel.text = "FERMER"
	btn_cancel.connect("pressed", Callable(setup_panel, "queue_free"))
	vbox.add_child(btn_cancel)
	
	add_child(setup_panel)

func _on_forge_pressed():
	if email_input.text == "":
		status_lbl.text = "L'email est requis."
		return
	status_lbl.text = "Communication Astroport..."
	UPlanet_API.forge_multipass(email_input.text, pass_input.text, SpaceTime_Manager.current_gps.x, SpaceTime_Manager.current_gps.y)

func _on_anonymous_pressed():
	var random_hex = ""
	for i in range(64): random_hex += "0123456789abcdef"[randi() % 16]
	var mock_data = {
		"email": "anonyme_playground", "npub": "npub1_anonyme", "nsec": "nsec1_anonyme",
		"hex": random_hex, "g1pub": "G1_ANONYME_READONLY", "nostrns": "ipns_anonyme"
	}
	Player_Origin.init_from_multipass(mock_data)
	my_pubkey = "npub1_anonyme"
	setup_panel.queue_free()
	_build_profile_tab()
	_check_authorization()

func _on_multipass_success(data):
	status_lbl.text = "MULTIPASS généré !"
	Player_Origin.init_from_multipass(data)
	my_pubkey = Player_Origin.user_npub
	setup_panel.queue_free()
	_build_profile_tab()
	_check_authorization()

func _on_multipass_error(msg):
	status_lbl.text = "Erreur: " + msg

func _on_cycle_changed(state):
	if state == SpaceTime_Manager.TimeState.STATE_DAY_ACTION:
		state_label.text = "ÉTAT: JOUR (MATIÈRE)"
		state_label.modulate = Color(1.0, 0.8, 0.2)
	else:
		state_label.text = "ÉTAT: NUIT (RÊVE)"
		state_label.modulate = Color(0.4, 0.4, 1.0)

func _on_energy_updated(energy):
	energy_bar.value = energy

func _on_gps_updated(lat, lon):
	var phi_node = Phi2X_Math.get_nearest_phi_node(lat, lon)
	var hex_pos = Phi2X_Math.gps_to_hex_index(lat, lon)
	compass_label.text = "NOEUD PHI [HEX: %s, %s, %s]" % [round(hex_pos.x), round(hex_pos.y), round(hex_pos.z)]
	var dist = phi_node["distance_km"]
	distance_label.text = "Distance: %.3f km" % dist
	
	if module_tabs.has_node("Cabine_33"):
		if dist <= CABINE_UNLOCK_DISTANCE_KM and module_tabs.is_tab_disabled(2):
			module_tabs.set_tab_disabled(2, false)
			module_tabs.set_tab_title(2, "CABINE 33")
			distance_label.modulate = Color(0.2, 1.0, 0.2)
		elif dist > CABINE_UNLOCK_DISTANCE_KM and not module_tabs.is_tab_disabled(2):
			module_tabs.set_tab_disabled(2, true)
			module_tabs.set_tab_title(2, "[VERROUILLÉ]")
			distance_label.modulate = Color(1.0, 1.0, 1.0)

func _on_send_thought_pressed():
	if not wot_authorized:
		add_log("⚠️ Écriture refusée (Non certifié N2).")
		return
	var thought_input = module_tabs.get_node("Cabine_33/ThoughtInput")
	Thought_Cache.capture_thought(thought_input.text, SpaceTime_Manager.current_gps)
	thought_input.text = "" 

func _on_cache_purged(count):
	add_log("Purge : %s événements NOSTR mis en attente." % count)

func _on_encounter_started(pubkey, spin_hash):
	add_log("Rencontre Atome [%s] - SPIN: %s" % [pubkey.substr(0,4), spin_hash])

func _on_reality_forked(pubkey, _dist):
	add_log("FRACTURE! Séparation avec [%s]" % [pubkey.substr(0,4)])

func _simulate_bluetooth_encounter():
	var random_pubkey = "npub1_" + str(randi() % 1000).pad_zeros(4)
	Atom4Peace.process_encounter(my_pubkey, random_pubkey, SpaceTime_Manager.current_gps)

func add_log(msg: String):
	log_text.text += "\n[%s] %s" % [Time.get_time_string_from_system(), msg]
