extends Control

signal recenter_requested

@onready var state_label    = $TopBar/StateLabel
@onready var energy_bar     = $TopBar/EnergyProgressBar
@onready var compass_label  = $HUDCenter/CompassLabel
@onready var distance_label = $HUDCenter/DistanceLabel
@onready var log_text       = $LogNode
@onready var photo_btn      = $BottomBar/PhotoBtn
@onready var sync_btn       = $BottomBar/SyncBtn

const CABINE_UNLOCK_KM: float = 0.05
const COL_GREEN := Color(0.0, 1.0, 0.5)

# ── Polices responsives ──────────────────────────────────────────
func _vp_font(base: int) -> int:
	var scale := clampf(get_viewport_rect().size.y / 640.0, 1.0, 2.4)
	return maxi(base, int(base * scale))

func _scale_node_fonts(node: Node):
	var scale := clampf(get_viewport_rect().size.y / 640.0, 1.0, 2.4)
	if scale < 1.06: return
	if node is Control:
		var ctrl := node as Control
		if ctrl.has_theme_font_size_override("font_size"):
			var fs := ctrl.get_theme_font_size("font_size")
			ctrl.add_theme_font_size_override("font_size", maxi(fs, int(fs * scale)))
	for child in node.get_children(): _scale_node_fonts(child)

var my_pubkey: String = "npub1_alpha_000"
var wot_authorized: bool = false
var _cabine_dist_km: float = 999.0

# ── Offcanvas panel
var _panel: PanelContainer = null
var _panel_open: bool = false
var _tab_btns: Array[Button] = []
var _tab_pages: Array[ScrollContainer] = []
var _tab_vboxes: Array[VBoxContainer] = []
var _current_tab: int = 0
const TAB_PROFIL = 0
const TAB_MATCH  = 1
const TAB_SCAN   = 2
const TAB_RESEAU = 3

# ── Overlays
var viewfinder: TextureRect
var interference_rect: ColorRect
var _interference_hide_id: int = 0

# ── Tween guards (évite les tweens concurrents)
var _panel_tween: Tween = null
var _scan_pulse_tween: Tween = null

# ── Haptique & synthé
var _last_haptic_k: float = 0.0
var _haptic_cooldown: float = 0.0
const HAPTIC_COOLDOWN_S: float = 0.4
var _synth_player: AudioStreamPlayer = null
var _synth_gen: AudioStreamGenerator = null
var _synth_pb: AudioStreamGeneratorPlayback = null
var _synth_phase: float = 0.0
var _synth_target_hz: float = 0.0
var _synth_volume_db: float = -60.0
var _synth_active: bool = false
var _synth_muted: bool = true

# ── Refs widgets onglet SCAN (assignées dans _build_scan_tab)
var resonance_bar: ProgressBar = null
var nearby_list: RichTextLabel = null
var loca_scan_btn: Button = null
var loca_ssid_lbl: Label = null
var _hotcold_target_npub: String = ""
var _hotcold_prev_k: float = 0.0
var _hotcold_indicator: ColorRect = null
var _hotcold_arrow_lbl: Label = null
var _hotcold_k_lbl: Label = null

# ── Hook screen (onboarding inversé)
var _hook_overlay: Control = null
var _hook_birth_unix: int = 0
var _hook_birth_sex: int = 0
# ── Deep linking Web
var _deeplink_match_npub: String = ""
# ── Cabine-33 rituel (déclenché une seule fois par session)
var _cabine_ritual_done: bool = false

# ─────────────────────────────────────────────────────────────
# INIT
# ─────────────────────────────────────────────────────────────

func _apply_bg_color():
	var bg_rect := find_child("ThemeBgRect", true, false) as ColorRect
	if bg_rect == null:
		bg_rect = ColorRect.new()
		bg_rect.name = "ThemeBgRect"
		bg_rect.set_anchors_preset(PRESET_FULL_RECT)
		bg_rect.mouse_filter = MOUSE_FILTER_IGNORE
		add_child(bg_rect)
		move_child(bg_rect, 0)
	var bg := UI_Theme.current()["bg"] as Color
	var is_light := bg.get_luminance() >= 0.4
	bg_rect.color = Color(bg.r, bg.g, bg.b, 1.0 if is_light else 0.0)

func _ready():
	self.modulate = Color(1, 1, 1, 0.9)
	_connect_signals()
	_init_resonance_synth()
	_build_camera_viewfinder()
	_build_interference_overlay()
	_build_bottom_extras()
	_build_offcanvas_panel()
	_apply_bg_color()
	_style_topbar()
	_precompile_shaders()

	photo_btn.connect("pressed", Callable(self, "_on_photo_pressed"))
	sync_btn.connect("pressed", Callable(self, "_on_sync_pressed"))

	energy_bar.max_value = SpaceTime_Manager.MAX_TOTAL_ENERGY / 3.0
	_on_energy_updated(SpaceTime_Manager.available_matter_energy)
	_on_cycle_changed(SpaceTime_Manager.current_state)

	if OS.has_feature("web"):
		_check_deeplink()

	if not Player_Origin.is_initialized:
		_build_hook_screen()
	else:
		_rebuild_tab(TAB_PROFIL)
		_check_authorization()
		Nostr_Identity.connect_relay_list()
		if not Player_Origin.has_atom4love_profile():
			add_log("⚛ Profil ATOM4LOVE incomplet. Touchez ☰ → ⚛ PROFIL.")

func _process(delta):
	if Atom4Peace.active_bonds.size() > 0:
		Atom4Peace.check_bonds_status(SpaceTime_Manager.current_gps)
	if _haptic_cooldown > 0.0:
		_haptic_cooldown -= delta
	if _synth_active and _synth_pb:
		_fill_synth_buffer()

func _connect_signals():
	SpaceTime_Manager.connect("cycle_changed",    Callable(self, "_on_cycle_changed"))
	SpaceTime_Manager.connect("energy_updated",   Callable(self, "_on_energy_updated"))
	SpaceTime_Manager.connect("gps_updated",      Callable(self, "_on_gps_updated"))
	Atom4Peace.connect("encounter_started",       Callable(self, "_on_encounter_started"))
	Atom4Peace.connect("reality_forked",          Callable(self, "_on_reality_forked"))
	Atom4Peace.connect("resonance_detected",      Callable(self, "_on_resonance_detected"))
	UPlanet_API.connect("multipass_created",      Callable(self, "_on_multipass_success"))
	UPlanet_API.connect("api_error",              Callable(self, "_on_multipass_error"))
	UPlanet_API.connect("network_n2_analyzed",    Callable(self, "_on_n2_analyzed"))
	UPlanet_API.connect("sync_completed",         Callable(self, "_on_sync_completed"))
	Loca_Scanner.connect("atom_detected",         Callable(self, "_on_atom_detected"))
	Loca_Scanner.connect("super_coherence_match", Callable(self, "_on_super_coherence"))
	Loca_Scanner.connect("scan_state_changed",    Callable(self, "_on_scan_state_changed"))
	Loca_Scanner.connect("apk_server_started",    Callable(self, "_on_apk_server_started"))
	Nostr_Identity.connect("relay_connected",     Callable(self, "_on_nostr_relay_connected"))
	Nostr_Identity.connect("relay_disconnected",  Callable(self, "_on_nostr_relay_disconnected"))
	Nostr_Identity.connect("profile_published",   Callable(self, "_on_nostr_profile_published"))
	Nostr_Identity.connect("follows_updated",     Callable(self, "_on_nostr_follows_updated"))
	Guide_System.connect("step_changed",          Callable(self, "_on_guide_step_changed"))
	Guide_System.connect("guide_completed",       Callable(self, "_on_guide_completed"))
	UI_Theme.connect("theme_changed",             Callable(self, "_on_theme_changed"))
	Thought_Cache.connect("cache_purged",         Callable(self, "_on_cache_purged"))

# ─────────────────────────────────────────────────────────────
# BARRE SUPÉRIEURE
# ─────────────────────────────────────────────────────────────

func _style_topbar():
	var ac := UI_Theme.accent_color()
	var sb_fg = StyleBoxFlat.new()
	sb_fg.bg_color = ac
	sb_fg.set_corner_radius_all(4)
	energy_bar.add_theme_stylebox_override("fill", sb_fg)
	state_label.modulate = ac
	distance_label.modulate = UI_Theme.bar_color(false)
	var tw = create_tween().set_loops()
	tw.tween_property(distance_label, "modulate:a", 0.45, 1.6)
	tw.tween_property(distance_label, "modulate:a", 1.0, 1.6)

func _precompile_shaders():
	if not is_instance_valid(interference_rect): return
	interference_rect.modulate.a = 0.01
	interference_rect.show()
	await get_tree().process_frame
	interference_rect.hide()
	interference_rect.modulate.a = 1.0

func _update_menu_btn_style():
	var btn := $BottomBar.find_child("MenuBtn", true, false) as Button
	if btn == null: return
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(UI_Theme.accent_color(), 0.72)
	sb.set_corner_radius_all(14)
	btn.add_theme_stylebox_override("normal", sb)

# ─────────────────────────────────────────────────────────────
# BOUTONS EXTRA (☰ MENU + 📍 RECENTER) dans BottomBar
# ─────────────────────────────────────────────────────────────

func _build_bottom_extras():
	var btn_recenter = Button.new()
	btn_recenter.text = "📍"
	btn_recenter.custom_minimum_size = Vector2(80, 64)
	btn_recenter.add_theme_font_size_override("font_size", 22)
	btn_recenter.connect("pressed", Callable(self, "_on_recenter_pressed"))
	$BottomBar.add_child(btn_recenter)

	var btn_sound = Button.new()
	btn_sound.name = "SoundBtn"
	btn_sound.text = "🔇"
	btn_sound.custom_minimum_size = Vector2(80, 64)
	btn_sound.add_theme_font_size_override("font_size", 22)
	btn_sound.connect("pressed", Callable(self, "_on_sound_toggle"))
	$BottomBar.add_child(btn_sound)

	var btn_menu = Button.new()
	btn_menu.name = "MenuBtn"
	btn_menu.text = "☰"
	btn_menu.custom_minimum_size = Vector2(80, 64)
	btn_menu.add_theme_font_size_override("font_size", 30)
	btn_menu.connect("pressed", Callable(self, "_toggle_panel"))
	$BottomBar.add_child(btn_menu)
	_update_menu_btn_style()

# ─────────────────────────────────────────────────────────────
# OFFCANVAS PANEL
# ─────────────────────────────────────────────────────────────

func _build_offcanvas_panel():
	_panel = PanelContainer.new()
	_panel.name = "OffcanvasPanel"
	_panel.layout_mode = 0
	var psb = UI_Theme.make_panel_style()
	psb.border_width_left = 3
	psb.border_width_right = 0
	psb.border_width_top = 0
	psb.border_width_bottom = 0
	psb.corner_radius_top_left = 16
	psb.corner_radius_bottom_left = 16
	_panel.add_theme_stylebox_override("panel", psb)
	_panel.hide()
	add_child(_panel)
	_panel.move_to_front()

	var root = VBoxContainer.new()
	root.set_anchors_preset(PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 0)
	_panel.add_child(root)

	# ── En-tête du panel
	var hdr = HBoxContainer.new()
	hdr.custom_minimum_size = Vector2(0, 62)
	hdr.add_theme_constant_override("separation", 10)
	var hdr_sb = StyleBoxFlat.new()
	var hdr_bg := UI_Theme.current()["bg"] as Color
	hdr_sb.bg_color = Color(hdr_bg.r * 0.8, hdr_bg.g * 0.8, hdr_bg.b * 0.8, 0.85)
	hdr_sb.border_width_bottom = 1
	hdr_sb.border_color = Color(UI_Theme.accent_color(), 0.3)
	hdr_sb.set_content_margin_all(10)
	hdr.add_theme_stylebox_override("panel", hdr_sb)
	root.add_child(hdr)

	var app_lbl = Label.new()
	app_lbl.text = "⚛  ATOM4LOVE"
	app_lbl.size_flags_horizontal = SIZE_EXPAND_FILL
	app_lbl.add_theme_font_size_override("font_size", 20)
	app_lbl.modulate = UI_Theme.accent_color()
	app_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hdr.add_child(app_lbl)

	var btn_close = Button.new()
	btn_close.text = "✕"
	btn_close.custom_minimum_size = Vector2(52, 52)
	btn_close.add_theme_font_size_override("font_size", 22)
	btn_close.connect("pressed", Callable(self, "_close_panel"))
	hdr.add_child(btn_close)

	# ── Barre d'onglets
	var tab_bar = HBoxContainer.new()
	tab_bar.custom_minimum_size = Vector2(0, 54)
	tab_bar.add_theme_constant_override("separation", 2)
	root.add_child(tab_bar)

	var tab_labels = ["⚛ PROFIL", "🔬 MATCH", "📡 SCAN", "🌍 RÉSEAU"]
	_tab_btns.clear()
	for i in range(4):
		var btn = Button.new()
		btn.text = tab_labels[i]
		btn.size_flags_horizontal = SIZE_EXPAND_FILL
		btn.custom_minimum_size = Vector2(0, 52)
		btn.add_theme_font_size_override("font_size", 13)
		btn.connect("pressed", Callable(self, "_set_tab").bind(i))
		tab_bar.add_child(btn)
		_tab_btns.append(btn)

	# ── Zone de contenu
	var holder = Control.new()
	holder.size_flags_horizontal = SIZE_EXPAND_FILL
	holder.size_flags_vertical = SIZE_EXPAND_FILL
	root.add_child(holder)

	_tab_pages.clear()
	_tab_vboxes.clear()
	for i in range(4):
		var scroll = ScrollContainer.new()
		scroll.set_anchors_preset(PRESET_FULL_RECT)
		scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.visible = false
		var margin = MarginContainer.new()
		margin.name = "TabMargin"
		margin.add_theme_constant_override("margin_left", 18)
		margin.add_theme_constant_override("margin_right", 18)
		margin.add_theme_constant_override("margin_top", 14)
		margin.add_theme_constant_override("margin_bottom", 14)
		margin.size_flags_horizontal = SIZE_EXPAND_FILL
		scroll.add_child(margin)
		var vbox = VBoxContainer.new()
		vbox.name = "InnerVBox"
		vbox.size_flags_horizontal = SIZE_EXPAND_FILL
		vbox.add_theme_constant_override("separation", 14)
		margin.add_child(vbox)
		holder.add_child(scroll)
		_tab_pages.append(scroll)
		_tab_vboxes.append(vbox)

	# Peupler tous les onglets
	_build_profil_tab(_tab_vboxes[TAB_PROFIL])
	_build_match_tab(_tab_vboxes[TAB_MATCH])
	_build_scan_tab(_tab_vboxes[TAB_SCAN])
	_build_reseau_tab(_tab_vboxes[TAB_RESEAU])

	# Polices responsives
	_scale_node_fonts(_panel)

	_set_tab(TAB_PROFIL)

func _get_vbox(tab: int) -> VBoxContainer:
	if tab < _tab_vboxes.size(): return _tab_vboxes[tab]
	return null

func _set_tab(idx: int):
	_current_tab = idx
	var ac := UI_Theme.accent_color()
	var bg := UI_Theme.current()["bg"] as Color
	for i in range(_tab_pages.size()):
		_tab_pages[i].visible = (i == idx)
	for i in range(_tab_btns.size()):
		var btn = _tab_btns[i]
		var active_sb = StyleBoxFlat.new()
		active_sb.bg_color = Color(ac.r, ac.g, ac.b, 0.22) if i == idx else Color(bg.r, bg.g, bg.b, 0.0)
		active_sb.border_width_bottom = 3 if i == idx else 0
		active_sb.border_color = ac
		btn.add_theme_stylebox_override("normal", active_sb)

func _rebuild_tab(idx: int):
	if idx >= _tab_vboxes.size(): return
	var vbox = _tab_vboxes[idx]
	if not is_instance_valid(vbox): return
	for child in vbox.get_children():
		child.queue_free()
	match idx:
		TAB_PROFIL: _build_profil_tab(vbox)
		TAB_MATCH:  _build_match_tab(vbox)
		TAB_SCAN:   _build_scan_tab(vbox)
		TAB_RESEAU: _build_reseau_tab(vbox)
	_scale_node_fonts(vbox)

func _toggle_panel():
	if _panel_open: _close_panel()
	else: _open_panel(_current_tab)

func _open_panel(tab: int = TAB_PROFIL):
	if _panel == null: return
	var vp = get_viewport_rect().size
	_panel.size = Vector2(vp.x * 0.92, vp.y)
	_panel.position = Vector2(vp.x, 0)
	_panel.show()
	if _panel_tween and _panel_tween.is_running(): _panel_tween.kill()
	_panel_tween = create_tween()
	_panel_tween.tween_property(_panel, "position:x", vp.x * 0.08, 0.22).set_ease(Tween.EASE_OUT)
	_panel_open = true
	_set_tab(tab)

func _close_panel():
	if not _panel_open or _panel == null: return
	var vp = get_viewport_rect().size
	if _panel_tween and _panel_tween.is_running(): _panel_tween.kill()
	_panel_tween = create_tween()
	_panel_tween.tween_property(_panel, "position:x", vp.x, 0.18).set_ease(Tween.EASE_IN)
	_panel_tween.connect("finished", Callable(self, "_on_panel_close_done"))
	_panel_open = false

func _on_panel_close_done():
	if is_instance_valid(_panel): _panel.hide()

# ─────────────────────────────────────────────────────────────
# ONGLET ⚛ PROFIL
# ─────────────────────────────────────────────────────────────

func _build_profil_tab(vbox: VBoxContainer):
	_lbl_title(vbox, "⚛  ATOM4LOVE", 28, UI_Theme.accent_color())

	if not Player_Origin.is_initialized:
		# ── Accueil premier lancement
		var welcome = Label.new()
		welcome.text = "Bienvenue !\n\nATOM4LOVE est un interféromètre cosmique. Il mesure votre résonance de phase avec d'autres atomes vivants proches de vous.\n\nCommencez par créer votre MULTIPASS — votre identité décentralisée sur le réseau UPlanet."
		welcome.autowrap_mode = TextServer.AUTOWRAP_WORD
		welcome.add_theme_font_size_override("font_size", 15)
		welcome.modulate = UI_Theme.text_secondary()
		vbox.add_child(welcome)
		vbox.add_child(HSeparator.new())
		_build_multipass_section(vbox)
	else:
		# ── Carte identité
		var id_panel = _make_panel_box(vbox)
		_lbl(id_panel, "📡 " + Player_Origin.user_npub.substr(0, 14) + "…" + Player_Origin.user_npub.right(4), 14, UI_Theme.bar_color(false))
		_lbl(id_panel, "📧 " + Player_Origin.user_email, 13)
		if Player_Origin.has_atom4love_profile():
			_lbl(id_panel, "⚛ φ_i = %.5f  |  ω_bio = %.2f Hz  |  %s" % [
				Player_Origin.personal_phase, Player_Origin.omega_bio,
				Player_Origin.get_polarity_label()], 13, COL_GREEN).autowrap_mode = TextServer.AUTOWRAP_WORD
		# ── Boutons viraux
		var btn_invite = Button.new()
		btn_invite.text = "✨ INVITER UN AMI — Tester notre résonance"
		btn_invite.custom_minimum_size = Vector2(0, 56)
		btn_invite.add_theme_font_size_override("font_size", 17)
		var invite_sb = StyleBoxFlat.new()
		invite_sb.bg_color = Color(0.28, 0.0, 0.52, 0.9); invite_sb.set_corner_radius_all(12)
		btn_invite.add_theme_stylebox_override("normal", invite_sb)
		btn_invite.connect("pressed", Callable(self, "_on_share_resonance_link"))
		vbox.add_child(btn_invite)

		var btn_card = Button.new()
		btn_card.text = "📸 EXPORTER CARTE COSMIQUE"
		btn_card.custom_minimum_size = Vector2(0, 46)
		btn_card.add_theme_font_size_override("font_size", 15)
		btn_card.connect("pressed", Callable(self, "_export_cosmic_card"))
		vbox.add_child(btn_card)

		vbox.add_child(HSeparator.new())

		# ── Profil de naissance + ATOM4LOVE
		_lbl_section(vbox, "📅 PROFIL DE NAISSANCE")
		_build_birth_section(vbox)
		vbox.add_child(HSeparator.new())

		# ── Profil NOSTR (Kind 0)
		_lbl_section(vbox, "📡 PROFIL NOSTR")
		_build_nostr_section(vbox)
		vbox.add_child(HSeparator.new())

	# ── Thème (toujours visible)
	_lbl_section(vbox, "🎨 THÈME DE L'INTERFACE")
	_build_theme_section(vbox)

# ── Sous-section : MULTIPASS
func _build_multipass_section(vbox: VBoxContainer):
	_lbl_section(vbox, "🌐 CRÉER MON MULTIPASS")

	var email_inp = LineEdit.new()
	email_inp.name = "MultipassEmail"
	email_inp.placeholder_text = "Email (identifiant)"
	email_inp.custom_minimum_size = Vector2(0, 52)
	email_inp.add_theme_font_size_override("font_size", 16)
	vbox.add_child(email_inp)

	var pass_inp = LineEdit.new()
	pass_inp.name = "MultipassPass"
	pass_inp.placeholder_text = "Mot de passe"
	pass_inp.secret = true
	pass_inp.custom_minimum_size = Vector2(0, 52)
	pass_inp.add_theme_font_size_override("font_size", 16)
	vbox.add_child(pass_inp)

	var status_lbl = Label.new()
	status_lbl.name = "MultipassStatus"
	status_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_lbl.add_theme_font_size_override("font_size", 14)
	status_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(status_lbl)

	var btn_forge = Button.new()
	btn_forge.text = "⚡ S'INCARNER"
	btn_forge.custom_minimum_size = Vector2(0, 58)
	btn_forge.add_theme_font_size_override("font_size", 20)
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0.0, 0.45, 0.25)
	sb.set_corner_radius_all(12)
	btn_forge.add_theme_stylebox_override("normal", sb)
	btn_forge.connect("pressed", Callable(self, "_on_forge_pressed").bind(vbox))
	vbox.add_child(btn_forge)

	vbox.add_child(HSeparator.new())

	var btn_anon = Button.new()
	btn_anon.text = "👁  MODE EXPLORATEUR (Anonyme)"
	btn_anon.custom_minimum_size = Vector2(0, 48)
	btn_anon.add_theme_font_size_override("font_size", 16)
	btn_anon.connect("pressed", Callable(self, "_on_anonymous_pressed"))
	vbox.add_child(btn_anon)

# ── Sous-section : naissance + φ_i (date structurée + recherche ville)
func _build_birth_section(vbox: VBoxContainer):
	_lbl(vbox, "📅 Date de naissance", 14, UI_Theme.text_secondary())

	# Ligne Année / Mois / Jour
	var date_hb = HBoxContainer.new()
	date_hb.add_theme_constant_override("separation", 6); vbox.add_child(date_hb)
	for info in [["BirthYear","Année",1900,2100,4], ["BirthMonth","Mois",1,12,2], ["BirthDay","Jour",1,31,2]]:
		var col = VBoxContainer.new(); col.size_flags_horizontal = SIZE_EXPAND_FILL; date_hb.add_child(col)
		_lbl(col, info[1], 11, UI_Theme.text_secondary())
		var sp = SpinBox.new(); sp.name = info[0]
		sp.min_value = info[2]; sp.max_value = info[3]; sp.step = 1
		sp.custom_minimum_size = Vector2(0, 48); col.add_child(sp)
		sp.connect("value_changed", Callable(self, "_on_birth_spinbox_changed").bind(vbox))

	# Ligne Heure / Minute
	var time_hb = HBoxContainer.new()
	time_hb.add_theme_constant_override("separation", 6); vbox.add_child(time_hb)
	for info in [["BirthHour","Heure",0,23,2], ["BirthMin","Minute",0,59,2]]:
		var col = VBoxContainer.new(); col.size_flags_horizontal = SIZE_EXPAND_FILL; time_hb.add_child(col)
		_lbl(col, info[1], 11, UI_Theme.text_secondary())
		var sp = SpinBox.new(); sp.name = info[0]
		sp.min_value = info[2]; sp.max_value = info[3]; sp.step = 1
		sp.custom_minimum_size = Vector2(0, 48); col.add_child(sp)
		sp.connect("value_changed", Callable(self, "_on_birth_spinbox_changed").bind(vbox))

	# Pré-remplir si profil existant
	if Player_Origin.birth_unix > 0:
		var dt = Time.get_datetime_dict_from_unix_time(Player_Origin.birth_unix)
		_set_birth_spinboxes(vbox, dt.year, dt.month, dt.day, dt.hour, dt.minute)

	# Conception auto-calculée
	var conc_lbl = Label.new(); conc_lbl.name = "ConceptionLabel"
	conc_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	conc_lbl.add_theme_font_size_override("font_size", 13); conc_lbl.modulate = UI_Theme.text_positive()
	conc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(conc_lbl)
	_refresh_birth_conception(vbox)

	# Kin Maya
	var kin_lbl = Label.new(); kin_lbl.name = "KinMayaLabel"
	kin_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	kin_lbl.add_theme_font_size_override("font_size", 13); kin_lbl.modulate = UI_Theme.text_warm()
	kin_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(kin_lbl)
	_refresh_kin_label(vbox)

	vbox.add_child(HSeparator.new())

	# ── Lieu de naissance : recherche par nom de ville
	_lbl(vbox, "📍 Lieu de naissance", 14, UI_Theme.text_secondary())
	var city_hb = HBoxContainer.new(); city_hb.add_theme_constant_override("separation", 8); vbox.add_child(city_hb)
	var city_inp = LineEdit.new(); city_inp.name = "CityInput"
	city_inp.placeholder_text = "Ex: Paris, Lyon, Montréal…"
	city_inp.custom_minimum_size = Vector2(0, 48); city_inp.size_flags_horizontal = SIZE_EXPAND_FILL
	city_hb.add_child(city_inp)
	var btn_search = Button.new(); btn_search.text = "🔍"
	btn_search.custom_minimum_size = Vector2(48, 48)
	btn_search.connect("pressed", Callable(self, "_on_city_search").bind(vbox))
	city_hb.add_child(btn_search)

	var loc_lbl = Label.new(); loc_lbl.name = "BirthLatLonLabel"
	loc_lbl.add_theme_font_size_override("font_size", 13); loc_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	loc_lbl.modulate = UI_Theme.text_hint()
	if Player_Origin.birth_lat != 0.0:
		loc_lbl.text = "📌 %.4f, %.4f" % [Player_Origin.birth_lat, Player_Origin.birth_lon]
		city_inp.text = "%.4f, %.4f" % [Player_Origin.birth_lat, Player_Origin.birth_lon]
	else:
		loc_lbl.text = "Entrez une ville ou cherchez manuellement"
	vbox.add_child(loc_lbl)

	# Fallback coordonnées manuelles
	var manual_hb = HBoxContainer.new(); manual_hb.add_theme_constant_override("separation", 6); vbox.add_child(manual_hb)
	var lat_inp = LineEdit.new(); lat_inp.name = "ManualLat"
	lat_inp.placeholder_text = "Latitude (ex: 48.8566)"; lat_inp.custom_minimum_size = Vector2(0, 44)
	lat_inp.size_flags_horizontal = SIZE_EXPAND_FILL; manual_hb.add_child(lat_inp)
	var lon_inp = LineEdit.new(); lon_inp.name = "ManualLon"
	lon_inp.placeholder_text = "Longitude (ex: 2.3522)"; lon_inp.custom_minimum_size = Vector2(0, 44)
	lon_inp.size_flags_horizontal = SIZE_EXPAND_FILL; manual_hb.add_child(lon_inp)
	if Player_Origin.birth_lat != 0.0:
		lat_inp.text = "%.4f" % Player_Origin.birth_lat
		lon_inp.text = "%.4f" % Player_Origin.birth_lon

	# Polarité
	_lbl(vbox, "⚡ Polarité", 15)
	var sex_hb = HBoxContainer.new()
	sex_hb.alignment = BoxContainer.ALIGNMENT_CENTER
	sex_hb.add_theme_constant_override("separation", 14)
	vbox.add_child(sex_hb)
	var btn_phi = Button.new(); btn_phi.name = "BtnBoy"
	btn_phi.text = "☀  Onde Φ  (♂)"; btn_phi.toggle_mode = true
	btn_phi.button_pressed = (Player_Origin.biological_sex == 0)
	btn_phi.custom_minimum_size = Vector2(160, 56)
	sex_hb.add_child(btn_phi)
	var btn_oct = Button.new(); btn_oct.name = "BtnGirl"
	btn_oct.text = "🌙 Onde ♪  (♀)"; btn_oct.toggle_mode = true
	btn_oct.button_pressed = (Player_Origin.biological_sex == 1)
	btn_oct.custom_minimum_size = Vector2(160, 56)
	sex_hb.add_child(btn_oct)
	btn_phi.connect("pressed", Callable(self, "_on_sex_toggle").bind(btn_phi, btn_oct, 0))
	btn_oct.connect("pressed", Callable(self, "_on_sex_toggle").bind(btn_oct, btn_phi, 1))

	# Morphologie
	var morph_hb = HBoxContainer.new()
	morph_hb.add_theme_constant_override("separation", 12)
	vbox.add_child(morph_hb)
	var hv = VBoxContainer.new(); hv.size_flags_horizontal = SIZE_EXPAND_FILL; morph_hb.add_child(hv)
	_lbl(hv, "📏 Taille (cm)", 13)
	var h_inp = LineEdit.new(); h_inp.name = "HeightInput"; h_inp.placeholder_text = "Ex: 175"
	h_inp.custom_minimum_size = Vector2(0, 48)
	if Player_Origin.height_cm > 0: h_inp.text = str(int(Player_Origin.height_cm))
	hv.add_child(h_inp)
	var wv = VBoxContainer.new(); wv.size_flags_horizontal = SIZE_EXPAND_FILL; morph_hb.add_child(wv)
	_lbl(wv, "⚖ Poids (kg)", 13)
	var w_inp = LineEdit.new(); w_inp.name = "WeightInput"; w_inp.placeholder_text = "Ex: 70"
	w_inp.custom_minimum_size = Vector2(0, 48)
	if Player_Origin.weight_kg > 0: w_inp.text = str(int(Player_Origin.weight_kg))
	wv.add_child(w_inp)

	var result_lbl = Label.new()
	result_lbl.name = "BirthResultLabel"
	result_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_lbl.add_theme_font_size_override("font_size", 14)
	result_lbl.modulate = COL_GREEN
	result_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	if Player_Origin.has_atom4love_profile():
		result_lbl.text = "✅ φ_i = %.5f  |  ω_bio = %.2f Hz  |  %s" % [
			Player_Origin.personal_phase, Player_Origin.omega_bio, Player_Origin.get_polarity_label()]
	vbox.add_child(result_lbl)

	var btn_save = Button.new()
	btn_save.text = "💾 CALCULER MON ÂME"
	btn_save.custom_minimum_size = Vector2(0, 56)
	btn_save.add_theme_font_size_override("font_size", 18)
	btn_save.add_theme_stylebox_override("normal", UI_Theme.make_button_style())
	btn_save.connect("pressed", Callable(self, "_on_birth_save").bind(vbox))
	vbox.add_child(btn_save)

# ── Sous-section : profil NOSTR (Kind 0)
func _build_nostr_section(vbox: VBoxContainer):
	var fields = [["name", "Nom affiché"], ["about", "À propos"],
		["picture", "Avatar (URL)"], ["nip05", "NIP-05 (user@domain)"]]
	for f in fields:
		var lbl = Label.new(); lbl.text = f[1]; lbl.add_theme_font_size_override("font_size", 13)
		vbox.add_child(lbl)
		var inp = LineEdit.new()
		inp.name = "NField_" + f[0]; inp.placeholder_text = f[1]
		inp.text = Nostr_Identity.get_profile_field(f[0])
		inp.custom_minimum_size = Vector2(0, 48)
		inp.size_flags_horizontal = SIZE_EXPAND_FILL
		vbox.add_child(inp)

	var btn_pub = Button.new()
	btn_pub.text = "📤 PUBLIER MON PROFIL (Kind 0)"
	btn_pub.custom_minimum_size = Vector2(0, 52)
	btn_pub.add_theme_font_size_override("font_size", 16)
	btn_pub.connect("pressed", Callable(self, "_on_nostr_profile_publish").bind(vbox))
	vbox.add_child(btn_pub)

	var relay_lbl = RichTextLabel.new()
	relay_lbl.name = "RelayList"
	relay_lbl.bbcode_enabled = true
	relay_lbl.fit_content = true
	relay_lbl.custom_minimum_size = Vector2(0, 60)
	_update_relay_label(relay_lbl)
	vbox.add_child(relay_lbl)

	var relay_inp = LineEdit.new()
	relay_inp.name = "RelayInput"
	relay_inp.placeholder_text = "wss://relay.example.com"
	relay_inp.custom_minimum_size = Vector2(0, 46)
	vbox.add_child(relay_inp)

	var rel_hb = HBoxContainer.new()
	rel_hb.add_theme_constant_override("separation", 8)
	vbox.add_child(rel_hb)
	var btn_add_r = Button.new(); btn_add_r.text = "+ AJOUTER RELAIS"
	btn_add_r.size_flags_horizontal = SIZE_EXPAND_FILL
	btn_add_r.connect("pressed", Callable(self, "_on_add_relay").bind(vbox))
	rel_hb.add_child(btn_add_r)
	var btn_disc = Button.new(); btn_disc.text = "🔍 DÉCOUVRIR"
	btn_disc.size_flags_horizontal = SIZE_EXPAND_FILL
	btn_disc.connect("pressed", Callable(UPlanet_API, "discover_relays"))
	rel_hb.add_child(btn_disc)

# ── Sous-section : sélecteur de thème
func _build_theme_section(vbox: VBoxContainer):
	var hint = Label.new()
	hint.text = "Les développeurs peuvent ajouter leurs propres thèmes via UI_Theme.register_theme()."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD
	hint.add_theme_font_size_override("font_size", 12)
	hint.modulate = UI_Theme.text_hint()
	vbox.add_child(hint)

	for tid in UI_Theme.get_theme_ids():
		var btn = Button.new()
		btn.text = UI_Theme.get_theme_label(tid) + ("  ✓" if tid == UI_Theme.current_theme_id else "")
		btn.custom_minimum_size = Vector2(0, 52)
		btn.add_theme_font_size_override("font_size", 16)
		btn.connect("pressed", Callable(self, "_on_theme_chosen").bind(tid))
		vbox.add_child(btn)

# ─────────────────────────────────────────────────────────────
# ONGLET 🔬 MATCH — Calculateur bi-profil
# ─────────────────────────────────────────────────────────────

func _build_match_tab(vbox: VBoxContainer):
	_lbl_title(vbox, "🔬 TEST DE RÉSONANCE", 22, UI_Theme.accent_color())
	var hint = Label.new()
	hint.text = "Comparez deux empreintes cosmiques. Format date : AAAA-MM-JJ HH:MM  |  Lieu : lat, lon"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", 14)
	hint.modulate = UI_Theme.text_hint()
	vbox.add_child(hint)
	if Player_Origin.is_initialized and Player_Origin.user_npub != "npub1_anonyme":
		var btn_load = Button.new()
		btn_load.text = "📥 Charger mon profil dans Atome A"
		btn_load.custom_minimum_size = Vector2(0, 46)
		btn_load.connect("pressed", Callable(self, "_on_match_load_self").bind(vbox))
		vbox.add_child(btn_load)
	vbox.add_child(HSeparator.new())

	var profiles_hb = HBoxContainer.new()
	profiles_hb.add_theme_constant_override("separation", 10)
	profiles_hb.size_flags_horizontal = SIZE_EXPAND_FILL
	vbox.add_child(profiles_hb)

	for i in range(2):
		var col = VBoxContainer.new()
		col.size_flags_horizontal = SIZE_EXPAND_FILL
		col.add_theme_constant_override("separation", 8)
		profiles_hb.add_child(col)
		var sf = ("A" if i == 0 else "B")
		var col_col = UI_Theme.accent_color() if i == 0 else Color(1.0, 0.4, 0.4)
		_lbl_title(col, ("🔵 Atome A" if i == 0 else "🔴 Atome B"), 15, col_col)

		_lbl(col, "Naissance", 13)
		var di = LineEdit.new(); di.name = "TestDate" + sf
		di.placeholder_text = "AAAA-MM-JJ HH:MM"; di.custom_minimum_size = Vector2(0, 44)
		if i == 0 and Player_Origin.birth_unix > 0:
			var dt = Time.get_datetime_dict_from_unix_time(Player_Origin.birth_unix)
			di.text = "%04d-%02d-%02d %02d:%02d" % [dt.year, dt.month, dt.day, dt.hour, dt.minute]
		di.connect("text_changed", Callable(self, "_on_test_field_changed").bind(_tab_pages[TAB_MATCH]))
		col.add_child(di)

		_lbl(col, "Lieu (lat,lon)", 13)
		var li = LineEdit.new(); li.name = "TestLoc" + sf
		li.placeholder_text = "lat, lon"; li.custom_minimum_size = Vector2(0, 44)
		if i == 0 and Player_Origin.birth_lat != 0.0:
			li.text = "%.4f, %.4f" % [Player_Origin.birth_lat, Player_Origin.birth_lon]
		li.connect("text_changed", Callable(self, "_on_test_field_changed").bind(_tab_pages[TAB_MATCH]))
		col.add_child(li)

		var shb = HBoxContainer.new(); shb.alignment = BoxContainer.ALIGNMENT_CENTER; col.add_child(shb)
		var bp = Button.new(); bp.name = "TestSex" + sf + "_0"; bp.text = "☀ Φ"
		bp.toggle_mode = true; bp.custom_minimum_size = Vector2(60, 42)
		bp.button_pressed = (i == 0 and Player_Origin.biological_sex == 0) or (i == 1)
		shb.add_child(bp)
		var bo = Button.new(); bo.name = "TestSex" + sf + "_1"; bo.text = "🌙 ♪"
		bo.toggle_mode = true; bo.custom_minimum_size = Vector2(60, 42)
		bo.button_pressed = (i == 0 and Player_Origin.biological_sex == 1)
		shb.add_child(bo)
		bp.connect("pressed", Callable(self, "_on_sex_toggle").bind(bp, bo, 0))
		bo.connect("pressed", Callable(self, "_on_sex_toggle").bind(bo, bp, 1))
		bp.connect("toggled", Callable(self, "_on_test_sex_toggled").bind(_tab_pages[TAB_MATCH]))
		bo.connect("toggled", Callable(self, "_on_test_sex_toggled").bind(_tab_pages[TAB_MATCH]))

		var ph_lbl = Label.new(); ph_lbl.name = "TestPhase" + sf
		ph_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ph_lbl.add_theme_font_size_override("font_size", 13)
		ph_lbl.modulate = UI_Theme.accent_color(); ph_lbl.text = "φ = —"; col.add_child(ph_lbl)
		var om_lbl = Label.new(); om_lbl.name = "TestOmega" + sf
		om_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		om_lbl.add_theme_font_size_override("font_size", 13)
		om_lbl.modulate = UI_Theme.text_hint(); om_lbl.text = "ω = —"; col.add_child(om_lbl)

	vbox.add_child(HSeparator.new())

	var result_panel = PanelContainer.new()
	result_panel.add_theme_stylebox_override("panel", UI_Theme.make_panel_style())
	vbox.add_child(result_panel)
	var rv = VBoxContainer.new(); rv.add_theme_constant_override("separation", 8); result_panel.add_child(rv)
	var kl = Label.new(); kl.name = "TestKLabel"; kl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	kl.add_theme_font_size_override("font_size", 32); kl.text = "k = —"; rv.add_child(kl)
	var kb = ProgressBar.new(); kb.name = "TestKBar"; kb.max_value = 1.0
	kb.custom_minimum_size = Vector2(0, 22); rv.add_child(kb)
	var dl = Label.new(); dl.name = "TestDetailLabel"; dl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dl.add_theme_font_size_override("font_size", 14); dl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dl.text = "Remplissez les deux colonnes pour voir la synchronisation."; rv.add_child(dl)
	var legend = Label.new(); legend.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	legend.add_theme_font_size_override("font_size", 12); legend.modulate = UI_Theme.text_hint()
	legend.autowrap_mode = TextServer.AUTOWRAP_WORD
	legend.text = "φ (phi) = phase personnelle, angle cosmique lié à votre date/lieu de naissance.\nω (omega) = fréquence bio en Hz, modulée par taille/masse/polarité.\nk = résonance [0→1] : similarité de vos ondes — 1.0 = synchronisation parfaite."
	rv.add_child(legend)

	vbox.add_child(HSeparator.new())
	var btn_sim = Button.new(); btn_sim.text = "🎲 SIMULER UNE RENCONTRE (ATOM4PEACE)"
	btn_sim.custom_minimum_size = Vector2(0, 54); btn_sim.add_theme_font_size_override("font_size", 15)
	btn_sim.connect("pressed", Callable(self, "_simulate_bluetooth_encounter"))
	vbox.add_child(btn_sim)

	if Player_Origin.is_initialized:
		vbox.add_child(HSeparator.new())
		var btn_inv = Button.new()
		btn_inv.text = "✨ INVITER UN AMI — Tester notre résonance"
		btn_inv.custom_minimum_size = Vector2(0, 56)
		btn_inv.add_theme_font_size_override("font_size", 17)
		var inv_sb = StyleBoxFlat.new()
		inv_sb.bg_color = Color(0.28, 0.0, 0.52, 0.9); inv_sb.set_corner_radius_all(12)
		btn_inv.add_theme_stylebox_override("normal", inv_sb)
		btn_inv.connect("pressed", Callable(self, "_on_share_resonance_link"))
		vbox.add_child(btn_inv)

# ─────────────────────────────────────────────────────────────
# ONGLET 📡 SCAN — LOCA + HOT/COLD
# ─────────────────────────────────────────────────────────────

func _build_scan_tab(vbox: VBoxContainer):
	# ── LOCA scanner
	_lbl_title(vbox, "📡 SCANNER LOCA", 22, UI_Theme.accent_color())
	var hint_l = Label.new()
	hint_l.text = "Détecte les atomes environnants via BLE/WiFi. SSID émis : format A4L-<npub8>-<sex>-<phase>."
	hint_l.autowrap_mode = TextServer.AUTOWRAP_WORD
	hint_l.add_theme_font_size_override("font_size", 13)
	hint_l.modulate = UI_Theme.text_hint()
	vbox.add_child(hint_l)

	_lbl(vbox, "Taux de Résonance k :", 14)
	resonance_bar = ProgressBar.new()
	resonance_bar.max_value = 1.0; resonance_bar.value = 0.0
	resonance_bar.custom_minimum_size = Vector2(0, 26)
	var rb_sb = StyleBoxFlat.new(); rb_sb.bg_color = COL_GREEN; rb_sb.set_corner_radius_all(4)
	resonance_bar.add_theme_stylebox_override("fill", rb_sb)
	vbox.add_child(resonance_bar)

	var scan_hb = HBoxContainer.new(); scan_hb.alignment = BoxContainer.ALIGNMENT_CENTER
	scan_hb.add_theme_constant_override("separation", 10); vbox.add_child(scan_hb)
	loca_scan_btn = Button.new(); loca_scan_btn.text = "▶ SCANNER"
	loca_scan_btn.custom_minimum_size = Vector2(160, 54); loca_scan_btn.add_theme_font_size_override("font_size", 16)
	loca_scan_btn.connect("pressed", Callable(self, "_on_loca_toggle"))
	scan_hb.add_child(loca_scan_btn)
	var btn_share = Button.new(); btn_share.text = "📡 PARTAGER APK"
	btn_share.custom_minimum_size = Vector2(160, 54); btn_share.add_theme_font_size_override("font_size", 16)
	btn_share.connect("pressed", Callable(Loca_Scanner, "start_apk_server"))
	scan_hb.add_child(btn_share)

	loca_ssid_lbl = Label.new(); loca_ssid_lbl.text = "SSID : —"
	loca_ssid_lbl.add_theme_font_size_override("font_size", 13)
	loca_ssid_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	loca_ssid_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD; vbox.add_child(loca_ssid_lbl)

	# ── Astuce SSID manuel (OS bloquant la modif programmatique)
	var ssid_pc = PanelContainer.new()
	ssid_pc.add_theme_stylebox_override("panel", UI_Theme.make_panel_style(0.18))
	vbox.add_child(ssid_pc)
	var ssid_hv = VBoxContainer.new(); ssid_hv.add_theme_constant_override("separation", 6); ssid_pc.add_child(ssid_hv)
	var ssid_hint_lbl = Label.new()
	ssid_hint_lbl.text = "💡 Si votre OS bloque le renommage automatique du WiFi, allez dans Réglages → Partage de connexion et utilisez ce nom :"
	ssid_hint_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	ssid_hint_lbl.add_theme_font_size_override("font_size", 12)
	ssid_hint_lbl.modulate = UI_Theme.text_secondary()
	ssid_hv.add_child(ssid_hint_lbl)
	var ssid_fmt_lbl = Label.new(); ssid_fmt_lbl.name = "SSIDFormatLabel"
	ssid_fmt_lbl.add_theme_font_size_override("font_size", 13)
	ssid_fmt_lbl.modulate = UI_Theme.accent_color()
	ssid_fmt_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if Player_Origin.has_atom4love_profile() and Loca_Scanner.has_method("build_broadcast_ssid"):
		ssid_fmt_lbl.text = Loca_Scanner.build_broadcast_ssid()
	else:
		ssid_fmt_lbl.text = "Configurez votre profil ATOM4LOVE d'abord"
	ssid_hv.add_child(ssid_fmt_lbl)
	var btn_copy_ssid = Button.new(); btn_copy_ssid.text = "📋 Copier ce nom de réseau"
	btn_copy_ssid.custom_minimum_size = Vector2(0, 40)
	btn_copy_ssid.add_theme_font_size_override("font_size", 14)
	btn_copy_ssid.connect("pressed", Callable(self, "_on_copy_ssid").bind(ssid_fmt_lbl))
	ssid_hv.add_child(btn_copy_ssid)

	_lbl(vbox, "Atomes détectés :", 15)
	nearby_list = RichTextLabel.new()
	nearby_list.bbcode_enabled = true; nearby_list.fit_content = true
	nearby_list.custom_minimum_size = Vector2(0, 110)
	nearby_list.text = "[color=#888888]En attente de scan…[/color]"; vbox.add_child(nearby_list)

	vbox.add_child(HSeparator.new())

	# ── HOT/COLD
	_lbl_title(vbox, "🌡  HOT / COLD — Radar", 20, UI_Theme.accent_color())
	var hint_h = Label.new()
	hint_h.text = "Sélectionnez une cible. Déplacez-vous — l'indicateur vous guide par résonance."
	hint_h.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint_h.add_theme_font_size_override("font_size", 13); hint_h.modulate = UI_Theme.text_hint()
	vbox.add_child(hint_h)

	var tgt_hb = HBoxContainer.new(); tgt_hb.add_theme_constant_override("separation", 8); vbox.add_child(tgt_hb)
	var tgt_lbl = Label.new(); tgt_lbl.name = "HotColdTargetLabel"
	tgt_lbl.size_flags_horizontal = SIZE_EXPAND_FILL; tgt_lbl.add_theme_font_size_override("font_size", 14)
	tgt_lbl.text = _hotcold_target_npub if _hotcold_target_npub != "" else "— aucune cible —"
	tgt_hb.add_child(tgt_lbl)
	var btn_pick = Button.new(); btn_pick.text = "CHOISIR"
	btn_pick.connect("pressed", Callable(self, "_on_hotcold_pick").bind(_tab_pages[TAB_SCAN]))
	tgt_hb.add_child(btn_pick)

	var ind_pc = PanelContainer.new()
	ind_pc.add_theme_stylebox_override("panel", UI_Theme.make_panel_style(0.3)); vbox.add_child(ind_pc)
	_hotcold_indicator = ColorRect.new(); _hotcold_indicator.name = "HotColdIndicator"
	_hotcold_indicator.custom_minimum_size = Vector2(0, 160)
	_hotcold_indicator.size_flags_horizontal = SIZE_EXPAND_FILL
	_hotcold_indicator.color = Color(0.1, 0.1, 0.3); ind_pc.add_child(_hotcold_indicator)

	_hotcold_arrow_lbl = Label.new(); _hotcold_arrow_lbl.name = "HotColdArrow"
	_hotcold_arrow_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hotcold_arrow_lbl.add_theme_font_size_override("font_size", 52); _hotcold_arrow_lbl.text = "—"
	vbox.add_child(_hotcold_arrow_lbl)

	_hotcold_k_lbl = Label.new(); _hotcold_k_lbl.name = "HotColdKLabel"
	_hotcold_k_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hotcold_k_lbl.add_theme_font_size_override("font_size", 36); _hotcold_k_lbl.text = "k = —"
	vbox.add_child(_hotcold_k_lbl)

	var hc_kbar = ProgressBar.new(); hc_kbar.name = "HotColdKBar"
	hc_kbar.max_value = 1.0; hc_kbar.custom_minimum_size = Vector2(0, 18); vbox.add_child(hc_kbar)

	var btn_hc = Button.new(); btn_hc.name = "HotColdScanBtn"
	btn_hc.text = "▶ ACTIVER DÉCOUVERTE"; btn_hc.custom_minimum_size = Vector2(0, 56)
	btn_hc.add_theme_font_size_override("font_size", 18)
	btn_hc.add_theme_stylebox_override("normal", UI_Theme.make_button_style())
	btn_hc.connect("pressed", Callable(self, "_on_hotcold_toggle")); vbox.add_child(btn_hc)

	# ── GPS Mock (debug uniquement)
	if OS.is_debug_build():
		vbox.add_child(HSeparator.new())
		_lbl(vbox, "🧪 GPS simulé (debug)", 13, UI_Theme.text_hint())
		var gps_hb = HBoxContainer.new(); gps_hb.alignment = BoxContainer.ALIGNMENT_CENTER
		gps_hb.add_theme_constant_override("separation", 8); vbox.add_child(gps_hb)
		for dir in [["↑ N", 0.001, 0.0], ["↓ S", -0.001, 0.0], ["← O", 0.0, -0.001], ["→ E", 0.0, 0.001]]:
			var gb = Button.new(); gb.text = dir[0]
			gb.custom_minimum_size = Vector2(64, 48); gb.add_theme_font_size_override("font_size", 16)
			gb.connect("pressed", Callable(self, "_mock_gps_move").bind(dir[1], dir[2]))
			gps_hb.add_child(gb)

# ─────────────────────────────────────────────────────────────
# ONGLET 🌍 RÉSEAU — Follows + Relais + Cabine-33
# ─────────────────────────────────────────────────────────────

func _build_reseau_tab(vbox: VBoxContainer):
	_lbl_title(vbox, "🌍 RÉSEAU N²", 22, UI_Theme.accent_color())
	if not Player_Origin.is_initialized or Player_Origin.user_npub == "npub1_anonyme":
		var g = VBoxContainer.new(); g.add_theme_constant_override("separation", 16); vbox.add_child(g)
		_lbl(g, "🔒 Réseau verrouillé", 20, Color(1.0, 0.5, 0.3))
		var hl = Label.new()
		hl.text = "Forgez votre MULTIPASS pour rejoindre le réseau de résonance, publier sur NOSTR et créer votre constellation d'atomes."
		hl.autowrap_mode = TextServer.AUTOWRAP_WORD; hl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hl.add_theme_font_size_override("font_size", 15); g.add_child(hl)
		var btn_mp = Button.new(); btn_mp.text = "⚡ FORGER MON MULTIPASS"
		btn_mp.custom_minimum_size = Vector2(0, 62); btn_mp.add_theme_font_size_override("font_size", 18)
		var sb = StyleBoxFlat.new(); sb.bg_color = Color(0.0, 0.45, 0.25); sb.set_corner_radius_all(14)
		btn_mp.add_theme_stylebox_override("normal", sb)
		btn_mp.connect("pressed", Callable(self, "_open_panel").bind(TAB_PROFIL))
		g.add_child(btn_mp)
		return

	# ── QR Code — partage de clef publique
	_lbl_section(vbox, "🔑 MA CLÉ PUBLIQUE (QR)")
	_build_qr_section(vbox)
	vbox.add_child(HSeparator.new())

	# ── Follows
	_lbl_section(vbox, "⭐ CONSTELLATION")
	if Nostr_Identity.follows.is_empty():
		var el = Label.new(); el.text = "Aucune étoile. Scannez des atomes ou ajoutez manuellement."
		el.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; el.add_theme_font_size_override("font_size", 14)
		vbox.add_child(el)
	else:
		for hex in Nostr_Identity.follows:
			var row = HBoxContainer.new(); vbox.add_child(row)
			var hl = Label.new(); hl.text = hex.substr(0, 12) + "…" + hex.right(4)
			hl.size_flags_horizontal = SIZE_EXPAND_FILL; row.add_child(hl)
			var btn_u = Button.new(); btn_u.text = "✖"
			btn_u.connect("pressed", Callable(self, "_on_unfollow").bind(hex)); row.add_child(btn_u)

	var hex_inp = LineEdit.new(); hex_inp.name = "HexFollowInput"
	hex_inp.placeholder_text = "Identifiant Cosmique (hex 64 chars ou npub1…)"; hex_inp.custom_minimum_size = Vector2(0, 46)
	vbox.add_child(hex_inp)
	var fhb = HBoxContainer.new(); fhb.add_theme_constant_override("separation", 8); vbox.add_child(fhb)
	var btn_follow = Button.new(); btn_follow.text = "+ SUIVRE"
	btn_follow.size_flags_horizontal = SIZE_EXPAND_FILL
	btn_follow.connect("pressed", Callable(self, "_on_follow").bind(vbox)); fhb.add_child(btn_follow)
	var btn_k3 = Button.new(); btn_k3.text = "📤 Publier Kind 3"
	btn_k3.size_flags_horizontal = SIZE_EXPAND_FILL
	btn_k3.connect("pressed", Callable(Nostr_Identity, "publish_kind3")); fhb.add_child(btn_k3)

	vbox.add_child(HSeparator.new())

	# ── Import nsec1
	_lbl_section(vbox, "🔑 IMPORTER nsec1 → nsec2")
	var nsec_inp = LineEdit.new(); nsec_inp.name = "Nsec1Input"; nsec_inp.secret = true
	nsec_inp.placeholder_text = "nsec1xxxxxxxxxxxxxx"; nsec_inp.custom_minimum_size = Vector2(0, 46)
	vbox.add_child(nsec_inp)
	var em_inp = LineEdit.new(); em_inp.name = "EmailNsecInput"
	em_inp.placeholder_text = "Email associé"; em_inp.custom_minimum_size = Vector2(0, 46)
	if Player_Origin.is_initialized: em_inp.text = Player_Origin.user_email
	vbox.add_child(em_inp)
	var btn_derive = Button.new(); btn_derive.text = "⚡ DÉRIVER nsec2"
	btn_derive.custom_minimum_size = Vector2(0, 50); btn_derive.add_theme_font_size_override("font_size", 16)
	btn_derive.connect("pressed", Callable(self, "_on_nsec1_import").bind(vbox)); vbox.add_child(btn_derive)

	vbox.add_child(HSeparator.new())

	# ── Cabine-33
	_lbl_section(vbox, "🔮 CABINE-33")
	var dist_lbl = Label.new(); dist_lbl.name = "Cabine33DistLabel"
	dist_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dist_lbl.add_theme_font_size_override("font_size", 16)
	var dval = "%.3f km" % _cabine_dist_km
	dist_lbl.text = ("✅ Nœud PHI accessible (%s)" % dval) if _cabine_dist_km <= CABINE_UNLOCK_KM else ("🔒 Distance : %s (< %.0fm requis)" % [dval, CABINE_UNLOCK_KM * 1000])
	dist_lbl.modulate = COL_GREEN if _cabine_dist_km <= CABINE_UNLOCK_KM else Color(0.7, 0.7, 0.7)
	vbox.add_child(dist_lbl)

	var thought_inp = $LegacyCabine/ThoughtInput
	var send_btn    = $LegacyCabine/SendButton
	if _cabine_dist_km <= CABINE_UNLOCK_KM and wot_authorized:
		var thought_inline = TextEdit.new(); thought_inline.name = "InlineThoughtInput"
		thought_inline.placeholder_text = "Déposez une pensée dans le vide quantique…"
		thought_inline.custom_minimum_size = Vector2(0, 120); thought_inline.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
		vbox.add_child(thought_inline)
		var btn_send = Button.new(); btn_send.text = "TRANSMETTRE (Coût: -5 Énergie)"
		btn_send.custom_minimum_size = Vector2(0, 54); btn_send.add_theme_font_size_override("font_size", 16)
		btn_send.connect("pressed", Callable(self, "_on_send_thought_inline").bind(thought_inline))
		vbox.add_child(btn_send)
	else:
		# Pass the thought_input and send_btn references for external usage
		thought_inp.visible = false
		send_btn.visible = false

	vbox.add_child(HSeparator.new())

	# ── Journal / Log
	_lbl_section(vbox, "📋 JOURNAL")
	var log_display = RichTextLabel.new(); log_display.name = "InlineLog"
	log_display.bbcode_enabled = true; log_display.fit_content = true
	log_display.custom_minimum_size = Vector2(0, 180)
	log_display.scroll_following = true
	log_display.text = log_text.text if is_instance_valid(log_text) else ""
	vbox.add_child(log_display)

# ─────────────────────────────────────────────────────────────
# QR CODE — Affichage npub + scanner
# ─────────────────────────────────────────────────────────────

func _build_qr_section(vbox: VBoxContainer):
	if not Player_Origin.is_initialized:
		_lbl(vbox, "Créez votre MULTIPASS pour afficher votre QR.", 13, Color(0.6,0.6,0.6)); return

	var npub := Player_Origin.user_npub
	_lbl(vbox, npub.substr(0,20) + "…" + npub.right(6), 12, UI_Theme.bar_color(false)).autowrap_mode = TextServer.AUTOWRAP_WORD

	var btn_copy = Button.new(); btn_copy.text = "📋 Copier npub"
	btn_copy.custom_minimum_size = Vector2(0, 48); btn_copy.add_theme_font_size_override("font_size", 15)
	btn_copy.connect("pressed", Callable(self, "_on_copy_npub")); vbox.add_child(btn_copy)

	var btn_qr = Button.new(); btn_qr.text = "🔲 Afficher QR Code"
	btn_qr.custom_minimum_size = Vector2(0, 48); btn_qr.add_theme_font_size_override("font_size", 15)
	btn_qr.connect("pressed", Callable(self, "_on_show_qr")); vbox.add_child(btn_qr)

	vbox.add_child(HSeparator.new())
	_lbl_section(vbox, "📷 AJOUTER UN CONTACT PAR QR")
	var hint = Label.new()
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD; hint.add_theme_font_size_override("font_size", 13)
	hint.modulate = UI_Theme.text_hint()
	hint.text = "Collez la clef hex (64 chars) ou npub1 d'un contact :"
	vbox.add_child(hint)
	var scan_inp = LineEdit.new(); scan_inp.name = "QRScanInput"
	scan_inp.placeholder_text = "npub1xxx… ou hex 64 chars"; scan_inp.custom_minimum_size = Vector2(0, 48)
	vbox.add_child(scan_inp)
	var btn_add = Button.new(); btn_add.text = "➕ AJOUTER AU FOLLOW"
	btn_add.custom_minimum_size = Vector2(0, 48); btn_add.add_theme_font_size_override("font_size", 15)
	btn_add.connect("pressed", Callable(self, "_on_qr_add_follow").bind(vbox))
	vbox.add_child(btn_add)

	if OS.has_feature("web"):
		var btn_cam = Button.new(); btn_cam.text = "📷 Scanner avec caméra (Web)"
		btn_cam.custom_minimum_size = Vector2(0, 48); btn_cam.add_theme_font_size_override("font_size", 14)
		btn_cam.connect("pressed", Callable(self, "_on_web_qr_scan").bind(vbox))
		vbox.add_child(btn_cam)

func _on_copy_npub():
	DisplayServer.clipboard_set(Player_Origin.user_npub)
	add_log("📋 npub copié dans le presse-papier.")

func _on_show_qr():
	if not Player_Origin.is_initialized: return
	var npub := Player_Origin.user_npub
	# Fenêtre popup avec QR code généré
	var popup = PanelContainer.new()
	popup.set_anchors_preset(PRESET_FULL_RECT)
	popup.add_theme_stylebox_override("panel", UI_Theme.make_panel_style(0.97))
	add_child(popup); popup.move_to_front()
	var m = MarginContainer.new()
	for side in ["margin_left","margin_right","margin_top","margin_bottom"]:
		m.add_theme_constant_override(side, 20)
	popup.add_child(m)
	var pv = VBoxContainer.new(); pv.add_theme_constant_override("separation", 12); m.add_child(pv)
	_lbl_title(pv, "🔑 MA CLÉ PUBLIQUE", 18, UI_Theme.accent_color())
	var img_rect = TextureRect.new(); img_rect.name = "QRRect"
	img_rect.custom_minimum_size = Vector2(264, 264)
	img_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	img_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pv.add_child(img_rect)
	# Génération asynchrone pour ne pas bloquer le rendu
	var gen_lbl = Label.new(); gen_lbl.text = "⏳ Génération QR…"
	gen_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; pv.add_child(gen_lbl)
	_lbl(pv, npub, 10, UI_Theme.bar_color(false)).autowrap_mode = TextServer.AUTOWRAP_WORD
	var btn_c = Button.new(); btn_c.text = "FERMER"
	btn_c.connect("pressed", Callable(popup, "queue_free")); pv.add_child(btn_c)
	# Générer le QR (peut être un peu lent sur mobile bas de gamme)
	await get_tree().process_frame
	var img := QR_Generator.generate(npub, 7)
	var tex := ImageTexture.create_from_image(img)
	if is_instance_valid(img_rect): img_rect.texture = tex
	if is_instance_valid(gen_lbl): gen_lbl.queue_free()

func _on_qr_add_follow(vbox: VBoxContainer):
	var inp = vbox.find_child("QRScanInput", true, false) as LineEdit
	if not inp or inp.text.strip_edges() == "": return
	var raw: String = inp.text.strip_edges()
	var hex: String = ""
	if raw.begins_with("npub1"):
		# Décoder npub1 → hex via Nostr_Identity si disponible
		hex = Nostr_Identity.npub_to_hex(raw) if Nostr_Identity.has_method("npub_to_hex") else ""
	elif raw.length() == 64:
		hex = raw
	if hex.length() == 64:
		Nostr_Identity.follow(hex)
		inp.text = ""; add_log("👥 Ajout follow : " + hex.substr(0, 12) + "…")
	else:
		add_log("⚠ Format invalide (attendu: npub1… ou hex 64 chars)")

func _on_web_qr_scan(vbox: VBoxContainer):
	if not OS.has_feature("web"):
		add_log("⚠ Scanner caméra disponible sur Web uniquement."); return
	var js := """
	(function() {
		if (!('BarcodeDetector' in window)) {
			window._godot_qr_result = 'UNSUPPORTED';
			return;
		}
		navigator.mediaDevices.getUserMedia({video:{facingMode:'environment'}})
		.then(function(stream) {
			const vid = document.createElement('video');
			vid.srcObject = stream; vid.play();
			const canvas = document.createElement('canvas');
			const ctx = canvas.getContext('2d');
			const detect = new BarcodeDetector({formats:['qr_code']});
			var attempt = 0;
			const scan = setInterval(function() {
				if (vid.readyState < 2 || ++attempt > 200) {
					clearInterval(scan); stream.getTracks().forEach(t=>t.stop()); return;
				}
				canvas.width = vid.videoWidth; canvas.height = vid.videoHeight;
				ctx.drawImage(vid,0,0);
				detect.detect(canvas).then(function(codes) {
					if (codes.length > 0) {
						clearInterval(scan); stream.getTracks().forEach(t=>t.stop());
						window._godot_qr_result = codes[0].rawValue;
					}
				}).catch(function(){});
			}, 300);
		}).catch(function(e) { window._godot_qr_result = 'ERROR:' + e.message; });
	})();
	"""
	JavaScriptBridge.eval(js)
	add_log("📷 Scanner QR Web activé — pointez vers un QR Code npub.")
	# Attendre et lire le résultat via polling léger
	_poll_web_qr_result(vbox, 60)

func _poll_web_qr_result(vbox: VBoxContainer, attempts: int):
	if attempts <= 0: add_log("⚠ Scanner QR : timeout."); return
	await get_tree().create_timer(0.5).timeout
	if not is_instance_valid(vbox): return
	var raw := str(JavaScriptBridge.eval("window._godot_qr_result || ''"))
	if raw == "" or raw == "null":
		_poll_web_qr_result(vbox, attempts - 1); return
	JavaScriptBridge.eval("window._godot_qr_result = '';")
	if raw.begins_with("ERROR:") or raw == "UNSUPPORTED":
		add_log("⚠ BarcodeDetector non disponible. Collez le npub manuellement."); return
	var inp = vbox.find_child("QRScanInput", true, false) as LineEdit
	if inp: inp.text = raw
	add_log("📷 QR scanné : " + raw.substr(0, 20) + "…")

# ─────────────────────────────────────────────────────────────
# HELPERS UI
# ─────────────────────────────────────────────────────────────

func _lbl_title(parent: Node, text: String, size: int, col: Color = Color.TRANSPARENT) -> Label:
	var l = Label.new(); l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.modulate = UI_Theme.accent_color() if col == Color.TRANSPARENT else col
	parent.add_child(l); return l

func _lbl(parent: Node, text: String, size: int = 14, col: Color = Color.TRANSPARENT) -> Label:
	var l = Label.new(); l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.modulate = UI_Theme.text_color() if col == Color.TRANSPARENT else col
	l.autowrap_mode = TextServer.AUTOWRAP_WORD
	parent.add_child(l); return l

func _lbl_section(parent: Node, text: String):
	var l = Label.new(); l.text = text
	l.add_theme_font_size_override("font_size", 16); l.modulate = UI_Theme.accent_color()
	parent.add_child(l)

func _make_panel_box(parent: Node) -> VBoxContainer:
	var pc = PanelContainer.new()
	pc.add_theme_stylebox_override("panel", UI_Theme.make_panel_style())
	parent.add_child(pc)
	var v = VBoxContainer.new(); v.add_theme_constant_override("separation", 6); pc.add_child(v)
	return v

func _update_relay_label(lbl: RichTextLabel):
	var relays = Nostr_Identity.relay_list if Nostr_Identity.relay_list.size() > 0 else Nostr_Identity.PUBLIC_RELAYS
	var t = ""
	for r in relays: t += "[color=cyan]• %s[/color]\n" % r
	lbl.text = t if t != "" else "[color=gray]Aucun relais[/color]"

# ─────────────────────────────────────────────────────────────
# CAMERA + SHADER
# ─────────────────────────────────────────────────────────────

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

	var hb = HBoxContainer.new(); hb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.custom_minimum_size = Vector2(0, 110); hb.add_theme_constant_override("separation", 20)
	overlay.add_child(hb)

	var bs = Button.new(); bs.text = "🔄 CAM"; bs.custom_minimum_size = Vector2(80, 60)
	bs.connect("pressed", Callable(Spacememory_Vision, "switch_camera")); hb.add_child(bs)

	var bt = Button.new(); bt.text = "🔴 CAPTURER"; bt.custom_minimum_size = Vector2(120, 80)
	var cs = StyleBoxFlat.new(); cs.bg_color = Color(0.8, 0.1, 0.1); cs.set_corner_radius_all(40)
	bt.add_theme_stylebox_override("normal", cs)
	bt.connect("pressed", Callable(self, "_do_capture")); hb.add_child(bt)

	var bc = Button.new(); bc.text = "❌"; bc.custom_minimum_size = Vector2(80, 60)
	bc.connect("pressed", Callable(self, "_close_camera")); hb.add_child(bc)

func _build_interference_overlay():
	interference_rect = ColorRect.new()
	interference_rect.set_anchors_preset(PRESET_FULL_RECT)
	interference_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	interference_rect.hide()
	var sm = ShaderMaterial.new()
	var sh = load("res://shaders/interference.gdshader")
	if sh: sm.shader = sh; interference_rect.material = sm
	add_child(interference_rect)

func _update_interference_shader(other_phase: float, other_sex: int, k: float):
	if not is_instance_valid(interference_rect): return
	var mat = interference_rect.material as ShaderMaterial
	if not mat: return
	mat.set_shader_parameter("phase_a", Player_Origin.personal_phase)
	mat.set_shader_parameter("phase_b", other_phase)
	mat.set_shader_parameter("sex_a",   Player_Origin.biological_sex)
	mat.set_shader_parameter("sex_b",   other_sex)
	mat.set_shader_parameter("resonance_k", k)
	interference_rect.show()
	if k < Atom4Peace.SUPER_COHERENCE_K:
		_interference_hide_id += 1
		var my_id := _interference_hide_id
		await get_tree().create_timer(5.0).timeout
		if is_instance_valid(interference_rect) and my_id == _interference_hide_id:
			interference_rect.hide()

# ─────────────────────────────────────────────────────────────
# SYNTHÉTISEUR BIO
# ─────────────────────────────────────────────────────────────

func _init_resonance_synth():
	_synth_gen = AudioStreamGenerator.new()
	_synth_gen.mix_rate = 22050.0; _synth_gen.buffer_length = 0.12
	_synth_player = AudioStreamPlayer.new()
	_synth_player.name = "ResonanceSynth"; _synth_player.stream = _synth_gen
	_synth_player.volume_db = -60.0
	# NE PAS add_child ici : l'AudioContext web requiert un geste utilisateur
	_synth_pb = null

func _fill_synth_buffer():
	var frames = _synth_pb.get_frames_available()
	if frames <= 0: return
	var target_db = lerpf(-24.0, -6.0, _last_haptic_k) if _last_haptic_k > 0.2 else -60.0
	_synth_volume_db = lerpf(_synth_volume_db, target_db, 0.05)
	if _synth_player: _synth_player.volume_db = _synth_volume_db
	var inc = _synth_target_hz / _synth_gen.mix_rate * TAU
	for _i in range(frames):
		var s = sin(_synth_phase) * 0.18
		_synth_pb.push_frame(Vector2(s, s))
		_synth_phase = fmod(_synth_phase + inc, TAU)

func _play_resonance_ping(k: float):
	if _synth_muted: return
	if _synth_player and not _synth_player.playing:
		_synth_player.play()
		_synth_pb = _synth_player.get_stream_playback()
	_synth_target_hz = lerpf(100.0, Phi2X_Math.F_WATER, k)
	_last_haptic_k = k; _synth_active = true

func _stop_resonance_synth():
	_synth_active = false; _synth_target_hz = 0.0; _last_haptic_k = 0.0
	if _synth_player: _synth_player.volume_db = -60.0

func _on_sound_toggle():
	_synth_muted = not _synth_muted
	var btn := $BottomBar.find_child("SoundBtn", true, false) as Button
	if _synth_muted:
		_stop_resonance_synth()
		if _synth_player and _synth_player.playing: _synth_player.stop()
		if btn: btn.text = "🔇"
	else:
		if _synth_player:
			if _synth_player.get_parent() == null: add_child(_synth_player)
			if not _synth_player.playing:
				_synth_player.play()
				_synth_pb = _synth_player.get_stream_playback()
		if btn: btn.text = "🔊"
		add_log("🔊 Son activé — appuyez à nouveau pour couper.")

# ─────────────────────────────────────────────────────────────
# CALLBACKS : CYCLE / ÉNERGIE / GPS
# ─────────────────────────────────────────────────────────────

func _on_cycle_changed(state):
	if state == SpaceTime_Manager.TimeState.STATE_DAY_ACTION:
		state_label.text = "☀ JOUR — ACTION"
		state_label.modulate = UI_Theme.accent_color()
		var tw = create_tween()
		tw.tween_property(self, "modulate", Color(1.0, 1.0, 1.0, 0.92), 1.2)
		if is_instance_valid(resonance_bar):
			var sb = StyleBoxFlat.new(); sb.bg_color = COL_GREEN; sb.set_corner_radius_all(4)
			resonance_bar.add_theme_stylebox_override("fill", sb)
	else:
		state_label.text = "🌙 NUIT — SYNC"
		state_label.modulate = UI_Theme.bar_color(true)
		var tw = create_tween()
		tw.tween_property(self, "modulate", Color(0.55, 0.55, 1.0, 0.88), 2.0)
		if is_instance_valid(resonance_bar):
			var sb = StyleBoxFlat.new(); sb.bg_color = Color(0.4, 0.2, 1.0); sb.set_corner_radius_all(4)
			resonance_bar.add_theme_stylebox_override("fill", sb)
		add_log("🌙 RÊVE — Purge Spacememory en cours…")

func _on_energy_updated(energy): energy_bar.value = energy

const _PENTAGON_NAMES := [
	"Pôle Nord", "Pôle Sud",
	"Orion", "Aldébaran", "Sirius", "Véga", "Antarès",
	"Fomalhaut", "Achernar", "Rigel", "Capella", "Deneb"
]
func _pentagon_sector(lat: float, lon: float) -> String:
	var best := 0; var best_d := 9999.0
	for i in range(Player_Origin.PENTAGONS_GPS.size()):
		var p := Player_Origin.PENTAGONS_GPS[i]
		var d := sqrt(pow(lat - p.x, 2) + pow(lon - p.y, 2))
		if d < best_d: best_d = d; best = i
	return _PENTAGON_NAMES[best] if best < _PENTAGON_NAMES.size() else "Secteur %d" % best

func _on_gps_updated(lat, lon):
	var phi_node = Phi2X_Math.get_nearest_phi_node(lat, lon)
	var hex_pos  = Phi2X_Math.gps_to_hex_index(lat, lon)
	var sector   := _pentagon_sector(lat, lon)
	compass_label.text = "⬡ %s" % sector
	_cabine_dist_km = phi_node["distance_km"]
	distance_label.text = "%.3f km" % _cabine_dist_km

	var dist_lbl = _find_in_tab(TAB_RESEAU, "Cabine33DistLabel") as Label
	if dist_lbl:
		var dval = "%.3f km" % _cabine_dist_km
		dist_lbl.text = ("✅ Nœud PHI (%s)" % dval) if _cabine_dist_km <= CABINE_UNLOCK_KM else ("🔒 %s (< %.0fm requis)" % [dval, CABINE_UNLOCK_KM * 1000])
		dist_lbl.modulate = COL_GREEN if _cabine_dist_km <= CABINE_UNLOCK_KM else Color(0.7, 0.7, 0.7)

	if _cabine_dist_km <= CABINE_UNLOCK_KM and wot_authorized and not _cabine_ritual_done:
		_cabine_ritual_done = true
		_trigger_cabine_ritual()

# ─────────────────────────────────────────────────────────────
# CALLBACKS : ATOM / RÉSONANCE
# ─────────────────────────────────────────────────────────────

func _on_resonance_detected(pubkey: String, k: float, is_singularity: bool):
	var bond = Atom4Peace.active_bonds.get(pubkey, {})
	_update_interference_shader(bond.get("other_phase", 0.0), bond.get("other_sex", 1), k)
	if is_instance_valid(resonance_bar): resonance_bar.value = k
	var label = "✨ SINGULARITÉ" if is_singularity else "Résonance"
	add_log("%s k=%.3f avec %s" % [label, k, pubkey.substr(0, 10)])

func _on_atom_detected(npub: String, k: float, phase: float, sex: int):
	if not is_instance_valid(nearby_list): return
	var icon = "☀" if sex == 0 else "🌙"
	var col = _k_hex(k)
	var line = "[color=%s]%s [b]k=%.3f[/b] %s φ=%.3f[/color]\n" % [col, icon, k, npub, phase]
	if nearby_list.text.contains("attente"): nearby_list.text = ""
	nearby_list.text += line
	if is_instance_valid(resonance_bar):
		var best = Loca_Scanner.get_sorted_by_resonance()
		if best.size() > 0: resonance_bar.value = best[0]["k"]
	_update_hot_cold_feedback(k)
	if _hotcold_target_npub != "" and npub == _hotcold_target_npub:
		_update_hotcold_display(k)

func _on_super_coherence(npub: String, k: float):
	add_log("💫 MATCH QUANTIQUE ! k=%.3f avec %s" % [k, npub.substr(0, 10)])
	if not is_instance_valid(resonance_bar): return
	var tw = create_tween()
	for _i in range(4):
		tw.tween_property(resonance_bar, "modulate", Color(1, 1, 1, 1), 0.15)
		tw.tween_property(resonance_bar, "modulate", Color(0, 1, 0.5, 1), 0.15)

func _on_encounter_started(pubkey, spin_hash):
	add_log("Rencontre [%s] — SPIN: %s" % [pubkey.substr(0, 6), spin_hash])

func _on_reality_forked(pubkey, _dist):
	add_log("FRACTURE avec [%s]" % pubkey.substr(0, 6))
	if is_instance_valid(interference_rect): interference_rect.hide()

func _simulate_bluetooth_encounter():
	var rpk  = "npub1_" + str(randi() % 1000).pad_zeros(4)
	var rph  = randf() * Phi2X_Math.PHASE_MODULUS
	var rsx  = randi() % 2
	Atom4Peace.process_resonance_encounter(my_pubkey, rpk, rph, rsx, SpaceTime_Manager.current_gps)

# ─────────────────────────────────────────────────────────────
# HOT / COLD feedback
# ─────────────────────────────────────────────────────────────

func _update_hot_cold_feedback(k: float):
	if k < 0.2 or _haptic_cooldown > 0.0: return
	_last_haptic_k = k
	Input.vibrate_handheld(int((1.0 - k) * 100.0 + 8.0))
	_haptic_cooldown = (1.0 - k) * HAPTIC_COOLDOWN_S + 0.1
	_play_resonance_ping(k)

func _update_hotcold_display(k: float):
	if not is_instance_valid(_hotcold_indicator): return
	var cold = Color(0.05, 0.15, 0.8); var hot = Color(1.0, 0.15, 0.05)
	_hotcold_indicator.color = cold.lerp(hot, k)
	if is_instance_valid(_hotcold_k_lbl):
		_hotcold_k_lbl.text = "k = %.4f" % k; _hotcold_k_lbl.modulate = _k_col(k)
	if is_instance_valid(_hotcold_arrow_lbl):
		if k > _hotcold_prev_k + 0.005:
			_hotcold_arrow_lbl.text = "🔥 ▲"; _hotcold_arrow_lbl.modulate = Color(1.0, 0.4, 0.0)
		elif k < _hotcold_prev_k - 0.005:
			_hotcold_arrow_lbl.text = "❄ ▼"; _hotcold_arrow_lbl.modulate = Color(0.3, 0.6, 1.0)
		else:
			_hotcold_arrow_lbl.text = "— ="; _hotcold_arrow_lbl.modulate = Color(0.7, 0.7, 0.7)
	var kb = _find_in_tab(TAB_SCAN, "HotColdKBar") as ProgressBar
	if kb:
		kb.value = k
		var bs = StyleBoxFlat.new(); bs.bg_color = cold.lerp(hot, k); bs.set_corner_radius_all(4)
		kb.add_theme_stylebox_override("fill", bs)
	_hotcold_prev_k = k

# ─────────────────────────────────────────────────────────────
# CALLBACKS : LOCA SCANNER
# ─────────────────────────────────────────────────────────────

func _on_loca_toggle():
	if Loca_Scanner.is_scanning:
		Loca_Scanner.stop_scan()
	else:
		if Player_Origin.has_atom4love_profile():
			if is_instance_valid(loca_ssid_lbl):
				loca_ssid_lbl.text = "SSID : " + Loca_Scanner.build_broadcast_ssid()
			Loca_Scanner.start_scan()
		else:
			add_log("⚛ Configurez votre profil ATOM4LOVE d'abord (onglet ⚛ PROFIL).")

func _on_scan_state_changed(is_scanning: bool):
	if is_instance_valid(loca_scan_btn):
		loca_scan_btn.text = "⏹ ARRÊTER" if is_scanning else "▶ SCANNER"
	var btn_hc = _find_in_tab(TAB_SCAN, "HotColdScanBtn") as Button
	if btn_hc: btn_hc.text = "⏹ DÉSACTIVER" if is_scanning else "▶ ACTIVER DÉCOUVERTE"
	if is_instance_valid(resonance_bar):
		if _scan_pulse_tween and _scan_pulse_tween.is_running(): _scan_pulse_tween.kill()
		if is_scanning:
			_scan_pulse_tween = create_tween().set_loops()
			_scan_pulse_tween.tween_property(resonance_bar, "modulate:a", 0.35, 0.9)
			_scan_pulse_tween.tween_property(resonance_bar, "modulate:a", 1.0, 0.9)
		else:
			resonance_bar.modulate.a = 1.0

func _on_apk_server_started(url: String):
	add_log("📲 Serveur APK : " + url)
	if is_instance_valid(loca_ssid_lbl): loca_ssid_lbl.text = "URL: " + url
	_show_apk_qr_popup(url)

func _on_hotcold_toggle():
	if Loca_Scanner.is_scanning: Loca_Scanner.stop_scan(); _stop_resonance_synth()
	else: Loca_Scanner.start_scan()

func _on_hotcold_pick(container: Node):
	var atoms = Loca_Scanner.get_sorted_by_resonance()
	var popup = PanelContainer.new()
	popup.set_anchors_preset(PRESET_FULL_RECT)
	popup.add_theme_stylebox_override("panel", UI_Theme.make_panel_style(0.97))
	add_child(popup); popup.move_to_front()
	var m = MarginContainer.new()
	m.add_theme_constant_override("margin_left", 20); m.add_theme_constant_override("margin_right", 20)
	m.add_theme_constant_override("margin_top", 30); popup.add_child(m)
	var pv = VBoxContainer.new(); pv.add_theme_constant_override("separation", 10); m.add_child(pv)
	_lbl_title(pv, "Choisir la cible :", 20)
	if atoms.is_empty():
		_lbl(pv, "Aucun atome détecté. Activez le scan LOCA.", 14)
	else:
		for atom in atoms:
			var btn = Button.new()
			var si = "☀" if atom.get("sex", 0) == 0 else "🌙"
			btn.text = "%s %s  k=%.3f" % [si, atom["npub"].substr(0, 12), atom["k"]]
			btn.connect("pressed", Callable(self, "_on_hotcold_chosen").bind(atom["npub"], container, popup))
			pv.add_child(btn)
	for hex in Nostr_Identity.follows:
		var btn = Button.new(); btn.text = "👥 " + hex.substr(0, 12) + "…"
		btn.connect("pressed", Callable(self, "_on_hotcold_chosen").bind(hex, container, popup))
		pv.add_child(btn)
	var bc = Button.new(); bc.text = "ANNULER"; bc.connect("pressed", Callable(popup, "queue_free")); pv.add_child(bc)

func _on_hotcold_chosen(npub: String, container: Node, popup: Node):
	_hotcold_target_npub = npub; _hotcold_prev_k = 0.0
	_stop_resonance_synth()
	var tl = container.find_child("HotColdTargetLabel", true, false) as Label
	if tl: tl.text = npub
	if is_instance_valid(popup): popup.queue_free()
	add_log("🎯 Cible Hot/Cold : " + npub.substr(0, 16))

# ─────────────────────────────────────────────────────────────
# CALLBACKS : MULTIPASS / FORGE
# ─────────────────────────────────────────────────────────────

func _on_forge_pressed(vbox: VBoxContainer):
	var email_inp = vbox.find_child("MultipassEmail", true, false) as LineEdit
	var pass_inp  = vbox.find_child("MultipassPass",  true, false) as LineEdit
	var status    = vbox.find_child("MultipassStatus", true, false) as Label
	if not email_inp or email_inp.text.strip_edges() == "":
		if status: status.text = "L'email est requis."; status.modulate = Color(1, 0.3, 0.3)
		return
	if status: status.text = "⏳ Connexion à Astroport…"; status.modulate = Color(0.8, 0.8, 0.8)
	UPlanet_API.forge_multipass(email_inp.text.strip_edges(), pass_inp.text,
		SpaceTime_Manager.current_gps.x, SpaceTime_Manager.current_gps.y)

func _on_anonymous_pressed():
	var rh = ""; for _i in range(64): rh += "0123456789abcdef"[randi() % 16]
	Player_Origin.init_from_multipass({
		"email": "anonyme_playground", "npub": "npub1_anonyme", "nsec": "nsec1_anonyme",
		"hex": rh, "g1pub": "G1_ANONYME_READONLY", "nostrns": "ipns_anonyme"
	})
	my_pubkey = "npub1_anonyme"
	_rebuild_tab(TAB_PROFIL); _rebuild_tab(TAB_RESEAU)
	_check_authorization(); Nostr_Identity.connect_relay_list()

func _on_multipass_success(data):
	Player_Origin.init_from_multipass(data)
	my_pubkey = Player_Origin.user_npub
	_rebuild_tab(TAB_PROFIL); _rebuild_tab(TAB_RESEAU)
	_check_authorization(); Nostr_Identity.connect_relay_list()
	add_log("⚛ MULTIPASS créé ! Configurez votre profil ATOM4LOVE.")
	if _hook_birth_unix > 0:
		var dt = Time.get_datetime_dict_from_unix_time(_hook_birth_unix)
		_set_birth_spinboxes(_tab_vboxes[TAB_PROFIL], dt.year, dt.month, dt.day, 12, 0)
		var bx := _tab_vboxes[TAB_PROFIL].find_child("BtnBoy",  true, false) as Button
		var bg := _tab_vboxes[TAB_PROFIL].find_child("BtnGirl", true, false) as Button
		if bx and bg: _on_sex_toggle(bx if _hook_birth_sex == 0 else bg, bg if _hook_birth_sex == 0 else bx, _hook_birth_sex)
		_hook_birth_unix = 0

func _on_multipass_error(msg):
	var status = _find_in_tab(TAB_PROFIL, "MultipassStatus") as Label
	if status: status.text = "Erreur : " + msg; status.modulate = Color(1, 0.3, 0.3)

# ─────────────────────────────────────────────────────────────
# CALLBACKS : PROFIL ATOM4LOVE (naissance)
# ─────────────────────────────────────────────────────────────

# ── Helpers naissance ────────────────────────────────────────────
func _set_birth_spinboxes(vbox: Node, y: int, mo: int, d: int, h: int, mi: int):
	for pair in [["BirthYear",y],["BirthMonth",mo],["BirthDay",d],["BirthHour",h],["BirthMin",mi]]:
		var sp = vbox.find_child(pair[0], true, false) as SpinBox
		if sp: sp.value = pair[1]

func _get_birth_unix_from_vbox(vbox: Node) -> int:
	var sy = vbox.find_child("BirthYear",  true, false) as SpinBox
	var sm = vbox.find_child("BirthMonth", true, false) as SpinBox
	var sd = vbox.find_child("BirthDay",   true, false) as SpinBox
	var sh = vbox.find_child("BirthHour",  true, false) as SpinBox
	var sn = vbox.find_child("BirthMin",   true, false) as SpinBox
	if not (sy and sm and sd): return -1
	return Time.get_unix_time_from_datetime_dict({
		"year": int(sy.value), "month": int(sm.value), "day": int(sd.value),
		"hour": int(sh.value if sh else 0), "minute": int(sn.value if sn else 0), "second": 0
	})

func _refresh_birth_conception(vbox: Node):
	var conc_lbl = vbox.find_child("ConceptionLabel", true, false) as Label
	if not conc_lbl: return
	var b = _get_birth_unix_from_vbox(vbox)
	if b > 0:
		var c = Phi2X_Math.compute_conception_unix(b)
		var cd = Time.get_datetime_dict_from_unix_time(c)
		conc_lbl.text = "🌱 Conception ≈ %04d-%02d-%02d  (−280 j.)" % [cd.year, cd.month, cd.day]
	else:
		conc_lbl.text = "🌱 Conception : saisissez la date"

func _refresh_kin_label(vbox: Node):
	var kin_lbl = vbox.find_child("KinMayaLabel", true, false) as Label
	if not kin_lbl: return
	var sy = vbox.find_child("BirthYear",  true, false) as SpinBox
	var sm = vbox.find_child("BirthMonth", true, false) as SpinBox
	var sd = vbox.find_child("BirthDay",   true, false) as SpinBox
	if not (sy and sm and sd): return
	var k = Kin_Maya.calc_kin(int(sy.value), int(sm.value), int(sd.value))
	kin_lbl.text = "🌀 " + Kin_Maya.format_kin_short(k)

func _on_birth_spinbox_changed(_value: float, vbox: Node):
	_refresh_birth_conception(vbox)
	_refresh_kin_label(vbox)

func _on_sex_toggle(active_btn: Button, other_btn: Button, _sex: int):
	active_btn.button_pressed = true; other_btn.button_pressed = false

func _on_match_load_self(vbox: VBoxContainer):
	if Player_Origin.birth_unix <= 0: add_log("⚠ Profil incomplet — date de naissance manquante."); return
	var dt = Time.get_datetime_dict_from_unix_time(Player_Origin.birth_unix)
	var da := vbox.find_child("TestDateA", true, false) as LineEdit
	var la := vbox.find_child("TestLocA",  true, false) as LineEdit
	if da: da.text = "%04d-%02d-%02d %02d:%02d" % [dt.year, dt.month, dt.day, dt.hour, dt.minute]
	if la and Player_Origin.birth_lat != 0.0:
		la.text = "%.4f, %.4f" % [Player_Origin.birth_lat, Player_Origin.birth_lon]
	var bp := vbox.find_child("TestSexA_0", true, false) as Button
	var bo := vbox.find_child("TestSexA_1", true, false) as Button
	if bp and bo: _on_sex_toggle(bp if Player_Origin.biological_sex == 0 else bo, bo if Player_Origin.biological_sex == 0 else bp, Player_Origin.biological_sex)
	_on_test_field_changed("", _tab_pages[TAB_MATCH])

# ── Recherche de ville via Nominatim ─────────────────────────────
func _on_city_search(vbox: VBoxContainer):
	var city_inp = vbox.find_child("CityInput", true, false) as LineEdit
	var loc_lbl  = vbox.find_child("BirthLatLonLabel", true, false) as Label
	if not city_inp or city_inp.text.strip_edges() == "": return
	if loc_lbl: loc_lbl.text = "⏳ Recherche…"
	var http = HTTPRequest.new(); http.name = "NominatimHTTP"; add_child(http)
	http.connect("request_completed", Callable(self, "_on_nominatim_response").bind(http, vbox))
	var url := "https://nominatim.openstreetmap.org/search?q=%s&format=json&limit=1" % \
		city_inp.text.strip_edges().uri_encode()
	if http.request(url) != OK:
		if loc_lbl: loc_lbl.text = "❌ Erreur réseau. Saisissez les coordonnées manuellement."
		http.queue_free()

func _on_nominatim_response(result: int, code: int, _headers: PackedStringArray,
		body: PackedByteArray, http: HTTPRequest, vbox: VBoxContainer):
	if is_instance_valid(http): http.queue_free()
	var loc_lbl = vbox.find_child("BirthLatLonLabel", true, false) as Label
	var lat_inp = vbox.find_child("ManualLat", true, false) as LineEdit
	var lon_inp = vbox.find_child("ManualLon", true, false) as LineEdit
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		if loc_lbl: loc_lbl.text = "❌ Introuvable. Saisissez lat/lon manuellement."
		return
	var json = JSON.new()
	if json.parse(body.get_string_from_utf8()) != OK: return
	var data = json.get_data()
	if not (data is Array) or data.is_empty():
		if loc_lbl: loc_lbl.text = "❌ Ville inconnue. Saisissez lat/lon manuellement."; return
	var entry = data[0]
	var blat := float(entry.get("lat", "0")); var blon := float(entry.get("lon", "0"))
	if lat_inp: lat_inp.text = "%.4f" % blat
	if lon_inp: lon_inp.text = "%.4f" % blon
	if loc_lbl: loc_lbl.text = "📌 %s  →  %.4f, %.4f" % [entry.get("display_name","?"), blat, blon]

func _on_birth_save(vbox: VBoxContainer):
	var bx = vbox.find_child("BtnBoy",         true, false) as Button
	var hi = vbox.find_child("HeightInput",    true, false) as LineEdit
	var wi = vbox.find_child("WeightInput",    true, false) as LineEdit
	var rl = vbox.find_child("BirthResultLabel", true, false) as Label
	var lat_inp = vbox.find_child("ManualLat", true, false) as LineEdit
	var lon_inp = vbox.find_child("ManualLon", true, false) as LineEdit
	var b_unix = _get_birth_unix_from_vbox(vbox)
	if b_unix <= 0:
		if rl: rl.text = "❌ Date invalide."; rl.modulate = Color(1, 0.3, 0.3); return
	var blat := float(lat_inp.text.strip_edges()) if (lat_inp and lat_inp.text != "") else 0.0
	var blon := float(lon_inp.text.strip_edges()) if (lon_inp and lon_inp.text != "") else 0.0
	var sex  := 0 if (bx and bx.button_pressed) else 1
	var h    := float(hi.text.strip_edges()) if (hi and hi.text != "") else 170.0
	var w    := float(wi.text.strip_edges()) if (wi and wi.text != "") else 70.0
	if h < 50 or h > 280: h = 170.0
	if w < 20 or w > 300: w = 70.0
	Player_Origin.set_birth_profile(b_unix, blat, blon, sex, h, w)
	if rl:
		rl.modulate = COL_GREEN
		rl.text = "✅ φ_i = %.5f  |  ω_bio = %.2f Hz  |  %s" % [
			Player_Origin.personal_phase, Player_Origin.omega_bio, Player_Origin.get_polarity_label()]
	if is_instance_valid(loca_ssid_lbl) and Player_Origin.has_atom4love_profile():
		loca_ssid_lbl.text = "SSID : " + Loca_Scanner.build_broadcast_ssid()
	# Mettre à jour animation Kin
	var ka = Kin_Maya.calc_kin_unix(b_unix)
	var anim := find_child("AtomAnimation", true, false) as Node2D
	if anim: anim.set_kin(ka, {})
	add_log("⚛ Profil ATOM4LOVE calculé. φ_i = %.5f" % Player_Origin.personal_phase)

func _parse_datetime(s: String) -> int:
	var parts = s.split(" ")
	if parts.size() == 0 or parts[0].length() < 10: return -1
	var dp = parts[0].split("-")
	if dp.size() < 3: return -1
	var hour = 0; var minute = 0
	if parts.size() >= 2:
		var tp = parts[1].split(":")
		if tp.size() >= 2: hour = int(tp[0]); minute = int(tp[1])
	return Time.get_unix_time_from_datetime_dict({
		"year": int(dp[0]), "month": int(dp[1]), "day": int(dp[2]),
		"hour": hour, "minute": minute, "second": 0
	})

# ─────────────────────────────────────────────────────────────
# CALLBACKS : PROFIL NOSTR (Kind 0)
# ─────────────────────────────────────────────────────────────

func _on_nostr_profile_publish(vbox: VBoxContainer):
	for f in ["name", "about", "picture", "nip05", "website"]:
		var inp = vbox.find_child("NField_" + f, true, false) as LineEdit
		if inp: Nostr_Identity.set_profile_field(f, inp.text)
	Nostr_Identity.publish_kind0()

func _on_add_relay(vbox: VBoxContainer):
	var ri = vbox.find_child("RelayInput", true, false) as LineEdit
	if ri and ri.text.begins_with("wss://"):
		Nostr_Identity.add_relay(ri.text.strip_edges()); ri.text = ""
		var rl = vbox.find_child("RelayList", true, false) as RichTextLabel
		if rl: _update_relay_label(rl)

func _on_nostr_relay_connected(url: String):    add_log("📡 Relais connecté : " + url)
func _on_nostr_relay_disconnected(url: String): add_log("⚠ Relais déconnecté : " + url)
func _on_nostr_profile_published(n: int):       add_log("✅ Profil Kind 0 publié sur %d relais." % n)

func _on_nostr_follows_updated(_follows: Array):
	add_log("👥 Follows mis à jour : %d contacts." % Nostr_Identity.follows.size())
	_rebuild_tab(TAB_RESEAU)

# ─────────────────────────────────────────────────────────────
# CALLBACKS : RÉSEAU / FOLLOWS
# ─────────────────────────────────────────────────────────────

func _on_follow(vbox: VBoxContainer):
	var inp = vbox.find_child("HexFollowInput", true, false) as LineEdit
	if inp and inp.text.length() == 64:
		Nostr_Identity.follow(inp.text.strip_edges()); inp.text = ""
	else:
		add_log("⚠ Pubkey hex invalide (64 chars requis).")

func _on_unfollow(hex: String): Nostr_Identity.unfollow(hex)

func _on_nsec1_import(vbox: VBoxContainer):
	var ni = vbox.find_child("Nsec1Input",    true, false) as LineEdit
	var ei = vbox.find_child("EmailNsecInput", true, false) as LineEdit
	if not ni or not ei: return
	var nsec1 = ni.text.strip_edges(); var email = ei.text.strip_edges()
	if nsec1 == "" or email == "":
		add_log("⚠ nsec1 et email requis pour la dérivation."); return
	add_log("🔑 Dérivation nsec2 en cours…")
	Nostr_Identity.derive_nsec2_from_nsec1(nsec1, email)

# ─────────────────────────────────────────────────────────────
# CABINE-33
# ─────────────────────────────────────────────────────────────

func _on_send_thought_inline(thought_inp: TextEdit):
	if not wot_authorized:
		add_log("⚠ Écriture refusée (Non certifié N2)."); return
	Thought_Cache.capture_thought(thought_inp.text, SpaceTime_Manager.current_gps)
	thought_inp.text = ""

func _on_cache_purged(count): add_log("Purge : %s événements NOSTR mis en attente." % count)

func _check_authorization():
	if Player_Origin.user_email == "anonyme_playground":
		wot_authorized = false
		add_log("👁 Mode Explorateur (Anonyme). Écriture désactivée.")
	else:
		add_log("🕸 Interrogation de la Toile de Confiance…")
		UPlanet_API.check_wot_authorization(Player_Origin.user_hex)

func _on_n2_analyzed(is_authorized, total_nodes):
	wot_authorized = is_authorized
	if is_authorized:
		add_log("✅ Accès Cabine-33 autorisé (%d atomes N²)" % total_nodes)
		if _panel_open and _current_tab == TAB_RESEAU: _rebuild_tab(TAB_RESEAU)
	else:
		add_log("⚠ Accès Écriture refusé (Non connecté au réseau N²).")

# ─────────────────────────────────────────────────────────────
# CALLBACKS : MATCH (test bi-profil)
# ─────────────────────────────────────────────────────────────

func _on_test_field_changed(_text: String, container: Node): _refresh_test_result(container)
func _on_test_sex_toggled(_pressed: bool, container: Node):   _refresh_test_result(container)

func _refresh_test_result(container: Node):
	var results: Array = []
	for sf in ["A", "B"]:
		var di = container.find_child("TestDate" + sf, true, false) as LineEdit
		var li = container.find_child("TestLoc"  + sf, true, false) as LineEdit
		var sb = container.find_child("TestSex"  + sf + "_0", true, false) as Button
		var pl = container.find_child("TestPhase" + sf, true, false) as Label
		var ol = container.find_child("TestOmega" + sf, true, false) as Label
		if not (di and li and sb): results.append(null); continue
		var b_unix = _parse_datetime(di.text.strip_edges())
		if b_unix <= 0:
			if pl: pl.text = "φ = date invalide"; results.append(null); continue
		var lp = li.text.strip_edges().split(",")
		var blat = float(lp[0].strip_edges()) if lp.size() >= 2 else 0.0
		var blon = float(lp[1].strip_edges()) if lp.size() >= 2 else 0.0
		var sex  = 0 if sb.button_pressed else 1
		var phi  = Phi2X_Math.compute_personal_phase(b_unix, blat, blon)
		var omega = Phi2X_Math.compute_omega_bio(170.0, 70.0, sex)
		if pl: pl.text = "φ = %.5f" % phi
		if ol: ol.text = "ω = %.2f Hz" % omega
		results.append({"phi": phi, "sex": sex, "omega": omega})
	var kl = container.find_child("TestKLabel",     true, false) as Label
	var kb = container.find_child("TestKBar",       true, false) as ProgressBar
	var dl = container.find_child("TestDetailLabel", true, false) as Label
	if results.size() < 2 or results[0] == null or results[1] == null:
		if kl: kl.text = "k = —"; return
	var pa = results[0]["phi"]; var pb = results[1]["phi"]
	var k  = Phi2X_Math.compute_resonance_k(pa, pb)
	var is_sing = Phi2X_Math.is_optical_singularity(pa, pb)
	if kl: kl.text = "k = %.4f" % k; kl.modulate = _k_col(k)
	if kb:
		kb.value = k
		var bs = StyleBoxFlat.new(); bs.bg_color = _k_col(k); bs.set_corner_radius_all(4)
		kb.add_theme_stylebox_override("fill", bs)
	if dl:
		var st = "  ✨ SINGULARITÉ !" if is_sing else ""
		dl.text = "Δφ = %.5f  |  Δω_bio = %.2f Hz%s" % [abs(pa - pb), abs(results[0]["omega"] - results[1]["omega"]), st]

# ─────────────────────────────────────────────────────────────
# CALLBACKS : THÈME / GUIDE / SYNC
# ─────────────────────────────────────────────────────────────

func _on_theme_chosen(theme_id: String): UI_Theme.apply_theme(theme_id)

func _on_theme_changed(_id: String):
	# Fond d'écran (opaque si thème clair, transparent si sombre)
	_apply_bg_color()
	# Topbar, btn menu, onglets actifs
	_style_topbar()
	_update_menu_btn_style()
	_set_tab(_current_tab)
	# Fond du panel
	if is_instance_valid(_panel):
		var t := UI_Theme.current()
		var t_bg := t["bg"] as Color; var t_bd := t["border"] as Color
		var t_alpha := float(t.get("panel_alpha", 0.88))
		var psb := StyleBoxFlat.new()
		psb.bg_color = Color(t_bg.r, t_bg.g, t_bg.b, t_alpha)
		psb.border_width_left = 3
		psb.border_color = Color(t_bd.r, t_bd.g, t_bd.b, 0.5)
		psb.corner_radius_top_left = 16; psb.corner_radius_bottom_left = 16
		_panel.add_theme_stylebox_override("panel", psb)
	# Reconstruire après fin de frame pour éviter conflits signal/queue_free
	call_deferred("_rebuild_tab", TAB_PROFIL)
	call_deferred("_rebuild_tab", TAB_MATCH)
	call_deferred("_rebuild_tab", TAB_SCAN)
	call_deferred("_rebuild_tab", TAB_RESEAU)

func _on_guide_step_changed(_step: int, title: String, _text: String): add_log("📖 Guide : " + title)
func _on_guide_completed(): add_log("✅ Guide terminé. Bonne interférence cosmique !")

func _on_sync_completed(msg): add_log("✅ " + msg); sync_btn.disabled = false
func _on_recenter_pressed():  emit_signal("recenter_requested")

func _mock_gps_move(dlat: float, dlon: float):
	var cur := SpaceTime_Manager.current_gps
	SpaceTime_Manager.update_gps_location(cur.x + dlat, cur.y + dlon)

# ─────────────────────────────────────────────────────────────
# ACTIONS RAPIDES (BOTTOM BAR)
# ─────────────────────────────────────────────────────────────

func _on_photo_pressed():
    if OS.has_feature("web") and CameraServer.feeds().size() == 0:
        # Fallback HTML natif pour prendre une photo depuis le navigateur web
        var js = """
        var input = document.createElement('input');
        input.type = 'file'; input.accept = 'image/*'; input.capture = 'environment';
        input.onchange = function(e) { 
            // Logique pour lire le fichier et le renvoyer à Godot via base64
            alert('Photo capturée via navigateur natif !'); 
        };
        input.click();
        """
        JavaScriptBridge.eval(js)
        return
        
    viewfinder.texture = Spacememory_Vision.get_feed_texture(); viewfinder.show()
	
func _do_capture():
	Spacememory_Vision.take_real_snapshot(); _close_camera()
	add_log("📸 Empreinte spatio-temporelle fixée !")

func _close_camera():
	viewfinder.hide()
	if Spacememory_Vision.camera_feed: Spacememory_Vision.camera_feed.set_active(false)

func _on_sync_pressed():
	add_log("🔄 Synchronisation avec le relais…"); sync_btn.disabled = true
	var archived_thoughts = Thought_Cache.purge_to_spacememory()
	
	if archived_thoughts.size() == 0:
		add_log("Le cache quantique est vide.")
		sync_btn.disabled = false
		return
		
	for thought in archived_thoughts:
		# Si c'est une image, il faudrait d'abord l'uploader sur IPFS via l'Astroport.
		# Pour l'instant, on publie au moins le texte/métadonnées sur NOSTR (Kind 1)
		var content = thought["text"]
		if thought.has("media_path"):
			content += "\n[Média local en attente d'Astroport : %s]" % thought["media_path"]
			
		var ev = Nostr_Identity.make_event(1, content, [
			["l", str(thought["location"].x) + "," + str(thought["location"].y), "GPS"]
		])
		Nostr_Identity.sign_and_send(ev)
		
	UPlanet_API.sync_with_relay(Player_Origin.user_npub)

# ─────────────────────────────────────────────────────────────
# HELPERS
# ─────────────────────────────────────────────────────────────

func _find_in_tab(tab: int, node_name: String) -> Node:
	if tab >= _tab_pages.size(): return null
	return _tab_pages[tab].find_child(node_name, true, false)

func _k_hex(k: float) -> String:
	if k >= 0.95: return "#ffd700"
	elif k >= 0.80: return "#00ff88"
	elif k >= 0.60: return "#00c8ff"
	else: return "#888888"

func _k_col(k: float) -> Color:
	if k >= 0.95: return Color(1.0, 0.85, 0.0)
	elif k >= 0.80: return Color(0.0, 1.0, 0.5)
	elif k >= 0.60: return Color(0.0, 0.78, 1.0)
	else: return Color(0.55, 0.55, 0.55)

# ─────────────────────────────────────────────────────────────
# PARTAGE VIRAL — Web Share API
# ─────────────────────────────────────────────────────────────

func _on_share_resonance_link():
	if not Player_Origin.is_initialized:
		add_log("⚠ Créez votre MULTIPASS pour partager votre lien de résonance."); return
	var my_npub := Player_Origin.user_npub
	if my_npub.is_empty() or my_npub == "npub1_anonyme":
		add_log("⚠ Forgez un vrai MULTIPASS pour partager votre résonance cosmique."); return
	var link := "https://u.copylaradio.com/atom4love?match=" + my_npub
	var text := "✨ Viens tester ta résonance cosmique avec moi sur ATOM4LOVE !"
	if OS.has_feature("web"):
		var js := """
		(function() {
			var t = '%s', u = '%s';
			if (navigator.share) {
				navigator.share({ title: 'ATOM4LOVE', text: t, url: u }).catch(function(e){ console.error(e); });
			} else {
				navigator.clipboard.writeText(t + ' ' + u).then(function(){
					alert('Lien copié dans le presse-papier !');
				}).catch(function(){ alert('Lien : ' + u); });
			}
		})();
		""" % [text, link]
		JavaScriptBridge.eval(js)
	else:
		DisplayServer.clipboard_set(text + " " + link)
		add_log("🔗 Lien copié ! Collez-le à un ami.\n" + link)

func _on_copy_ssid(lbl: Label):
	var ssid := lbl.text
	if ssid == "" or "Configurez" in ssid: return
	DisplayServer.clipboard_set(ssid)
	add_log("📋 Nom SSID copié : " + ssid)

# ─────────────────────────────────────────────────────────────
# CARTE COSMIQUE — Export screenshot
# ─────────────────────────────────────────────────────────────

func _export_cosmic_card():
	# Masquer l'UI pour un rendu propre (animation 3D + Kin en fond)
	$TopBar.hide(); $BottomBar.hide(); $HUDCenter.hide()
	if is_instance_valid(_panel) and _panel_open: _panel.hide()
	await get_tree().process_frame
	await get_tree().process_frame

	var img := get_viewport().get_texture().get_image()

	$TopBar.show(); $BottomBar.show(); $HUDCenter.show()
	if is_instance_valid(_panel) and _panel_open: _panel.show()

	if OS.has_feature("web"):
		var png_data := img.save_png_to_buffer()
		var b64 := Marshalls.raw_to_base64(png_data)
		var js := """
		(function() {
			var a = document.createElement('a');
			a.href = 'data:image/png;base64,%s';
			a.download = 'atom4love_empreinte.png';
			document.body.appendChild(a); a.click(); document.body.removeChild(a);
		})();
		""" % [b64]
		JavaScriptBridge.eval(js)
		add_log("📸 Carte Cosmique téléchargée.")
	else:
		var path := OS.get_user_data_dir() + "/atom4love_empreinte.png"
		img.save_png(path)
		DisplayServer.clipboard_set(path)
		add_log("📸 Carte Cosmique sauvegardée : " + path)

# ─────────────────────────────────────────────────────────────
# CABINE-33 — Rituel de la faille
# ─────────────────────────────────────────────────────────────

func _trigger_cabine_ritual():
	add_log("🔮 Nœud PHI atteint — La faille s'ouvre…")
	Input.vibrate_handheld(800)
	# Glitch de l'écran via le shader d'interférence
	if is_instance_valid(interference_rect):
		interference_rect.show()
	# Tween : flash rougeoyant + disparition progressive
	var glitch_rect = ColorRect.new()
	glitch_rect.set_anchors_preset(PRESET_FULL_RECT)
	glitch_rect.color = Color(0.8, 0.0, 0.3, 0.0)
	glitch_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glitch_rect.z_index = 90
	add_child(glitch_rect); glitch_rect.move_to_front()
	var gtw = create_tween()
	gtw.tween_property(glitch_rect, "color:a", 0.45, 0.18)
	gtw.tween_property(glitch_rect, "color:a", 0.0, 0.18)
	gtw.tween_property(glitch_rect, "color:a", 0.35, 0.12)
	gtw.tween_property(glitch_rect, "color:a", 0.0, 0.8)
	gtw.connect("finished", Callable(glitch_rect, "queue_free"))
	_show_cabine_invitation()

func _show_cabine_invitation():
	var overlay = Control.new()
	overlay.set_anchors_preset(PRESET_FULL_RECT)
	overlay.z_index = 60
	add_child(overlay); overlay.move_to_front()

	var bg = ColorRect.new()
	bg.set_anchors_preset(PRESET_FULL_RECT)
	bg.color = Color(0.0, 0.0, 0.0, 0.0)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(bg)

	var lbl = Label.new()
	lbl.text = "⚛  LA FAILLE EST OUVERTE\n\nDéposez votre pensée\ndans le vide quantique."
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.set_anchors_preset(PRESET_FULL_RECT)
	lbl.add_theme_font_size_override("font_size", 26)
	lbl.modulate = UI_Theme.accent_color()
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	overlay.add_child(lbl)

	# Apparition → maintien → disparition → ouvre RÉSEAU
	var tw = create_tween()
	tw.tween_property(bg, "color:a", 0.72, 0.6).set_ease(Tween.EASE_OUT)
	tw.tween_interval(2.8)
	tw.tween_property(overlay, "modulate:a", 0.0, 1.2).set_ease(Tween.EASE_IN)
	tw.connect("finished", Callable(overlay, "queue_free"))
	await get_tree().create_timer(5.0).timeout
	if is_instance_valid(interference_rect): interference_rect.hide()
	_open_panel(TAB_RESEAU)

# ─────────────────────────────────────────────────────────────
# DEEP LINKING WEB
# ─────────────────────────────────────────────────────────────

func _check_deeplink():
	var qs := str(JavaScriptBridge.eval("window.location.search || ''"))
	if "match=" in qs:
		var parts := qs.split("match=")
		if parts.size() >= 2:
			_deeplink_match_npub = parts[1].split("&")[0].strip_edges()
			add_log("🔗 Invitation reçue : " + _deeplink_match_npub.substr(0, 20) + "…")
			# Ouvrir le MATCH tab après construction du panel
			await get_tree().process_frame
			_open_panel(TAB_MATCH)

# ─────────────────────────────────────────────────────────────
# HOOK SCREEN — Onboarding Inversé
# ─────────────────────────────────────────────────────────────

func _build_hook_screen():
	_hook_overlay = Control.new()
	_hook_overlay.set_anchors_preset(PRESET_FULL_RECT)
	_hook_overlay.z_index = 100
	# Fond semi-transparent laissant voir le monde 3D
	var bg = ColorRect.new()
	bg.set_anchors_preset(PRESET_FULL_RECT)
	bg.color = Color(0.0, 0.02, 0.08, 0.82)
	_hook_overlay.add_child(bg)

	var scroll = ScrollContainer.new()
	scroll.set_anchors_preset(PRESET_FULL_RECT)
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_hook_overlay.add_child(scroll)

	var m = MarginContainer.new()
	m.size_flags_horizontal = SIZE_EXPAND_FILL
	for side in ["margin_left","margin_right","margin_top","margin_bottom"]:
		m.add_theme_constant_override(side, 28)
	scroll.add_child(m)

	var vbox = VBoxContainer.new()
	vbox.name = "HookVBox"
	vbox.size_flags_horizontal = SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 18)
	m.add_child(vbox)

	_lbl_title(vbox, "✨ QUELLE EST VOTRE\nEMPREINTE COSMIQUE ?", 26, UI_Theme.accent_color())

	var sub = Label.new()
	sub.text = "Chaque être porte une signature vibratoire unique — l'interférence de sa naissance avec le champ de la Terre."
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD
	sub.add_theme_font_size_override("font_size", 14)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.modulate = UI_Theme.text_secondary()
	vbox.add_child(sub)

	vbox.add_child(HSeparator.new())
	_lbl(vbox, "📅 Votre date de naissance", 16, UI_Theme.text_secondary())

	var date_hb = HBoxContainer.new()
	date_hb.add_theme_constant_override("separation", 8)
	vbox.add_child(date_hb)
	for info in [["HookYear","Année",1900,2100], ["HookMonth","Mois",1,12], ["HookDay","Jour",1,31]]:
		var col = VBoxContainer.new(); col.size_flags_horizontal = SIZE_EXPAND_FILL; date_hb.add_child(col)
		_lbl(col, info[1], 12, UI_Theme.text_secondary())
		var sp = SpinBox.new(); sp.name = info[0]
		sp.min_value = info[2]; sp.max_value = info[3]; sp.step = 1
		sp.custom_minimum_size = Vector2(0, 54)
		col.add_child(sp)
	var hook_sy := vbox.find_child("HookYear",  true, false) as SpinBox
	var hook_sm := vbox.find_child("HookMonth", true, false) as SpinBox
	var hook_sd := vbox.find_child("HookDay",   true, false) as SpinBox
	if hook_sy: hook_sy.value = 1990
	if hook_sm: hook_sm.value = 6
	if hook_sd: hook_sd.value = 21

	_lbl(vbox, "⚡ Votre polarité", 16)
	var sex_hb = HBoxContainer.new()
	sex_hb.alignment = BoxContainer.ALIGNMENT_CENTER
	sex_hb.add_theme_constant_override("separation", 16)
	vbox.add_child(sex_hb)
	var btn_phi_h = Button.new(); btn_phi_h.name = "HookBtnPhi"
	btn_phi_h.text = "☀  Onde Φ  (♂)"; btn_phi_h.toggle_mode = true; btn_phi_h.button_pressed = true
	btn_phi_h.custom_minimum_size = Vector2(160, 58)
	sex_hb.add_child(btn_phi_h)
	var btn_oct_h = Button.new(); btn_oct_h.name = "HookBtnOct"
	btn_oct_h.text = "🌙 Onde ♪  (♀)"; btn_oct_h.toggle_mode = true
	btn_oct_h.custom_minimum_size = Vector2(160, 58)
	sex_hb.add_child(btn_oct_h)
	btn_phi_h.connect("pressed", Callable(self, "_on_sex_toggle").bind(btn_phi_h, btn_oct_h, 0))
	btn_oct_h.connect("pressed", Callable(self, "_on_sex_toggle").bind(btn_oct_h, btn_phi_h, 1))

	var kin_preview = Label.new(); kin_preview.name = "HookKinPreview"
	kin_preview.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	kin_preview.add_theme_font_size_override("font_size", 17)
	kin_preview.modulate = UI_Theme.text_warm()
	kin_preview.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(kin_preview)

	for sp_name in ["HookYear", "HookMonth", "HookDay"]:
		var sp_node = vbox.find_child(sp_name, true, false) as SpinBox
		if sp_node: sp_node.connect("value_changed", Callable(self, "_on_hook_spinbox_changed").bind(vbox))
	_refresh_hook_kin(vbox)

	var btn_reveal = Button.new(); btn_reveal.name = "HookRevealBtn"
	btn_reveal.text = "✨ RÉVÉLER MON EMPREINTE"
	btn_reveal.custom_minimum_size = Vector2(0, 66)
	btn_reveal.add_theme_font_size_override("font_size", 20)
	var reveal_sb = StyleBoxFlat.new()
	reveal_sb.bg_color = Color(0.55, 0.15, 0.0); reveal_sb.set_corner_radius_all(16)
	btn_reveal.add_theme_stylebox_override("normal", reveal_sb)
	btn_reveal.connect("pressed", Callable(self, "_on_hook_reveal").bind(vbox))
	vbox.add_child(btn_reveal)

	# Section résultat, cachée jusqu'au clic "Révéler"
	var result_sec = VBoxContainer.new(); result_sec.name = "HookResultSection"
	result_sec.add_theme_constant_override("separation", 14)
	result_sec.visible = false; vbox.add_child(result_sec)

	add_child(_hook_overlay)
	_hook_overlay.move_to_front()
	_scale_node_fonts(_hook_overlay)

func _refresh_hook_kin(vbox: Node):
	var kin_lbl := vbox.find_child("HookKinPreview", true, false) as Label
	if not kin_lbl: return
	var sy := vbox.find_child("HookYear",  true, false) as SpinBox
	var sm := vbox.find_child("HookMonth", true, false) as SpinBox
	var sd := vbox.find_child("HookDay",   true, false) as SpinBox
	if not (sy and sm and sd): return
	var k = Kin_Maya.calc_kin(int(sy.value), int(sm.value), int(sd.value))
	kin_lbl.text = "🌀 " + Kin_Maya.format_kin_short(k)

func _on_hook_spinbox_changed(_value: float, vbox: Node):
	_refresh_hook_kin(vbox)

func _on_hook_reveal(vbox: VBoxContainer):
	var sy := vbox.find_child("HookYear",  true, false) as SpinBox
	var sm := vbox.find_child("HookMonth", true, false) as SpinBox
	var sd := vbox.find_child("HookDay",   true, false) as SpinBox
	var btn_phi := vbox.find_child("HookBtnPhi", true, false) as Button
	if not (sy and sm and sd): return

	var b_unix := Time.get_unix_time_from_datetime_dict({
		"year": int(sy.value), "month": int(sm.value), "day": int(sd.value),
		"hour": 12, "minute": 0, "second": 0
	})
	var sex := 0 if (btn_phi and btn_phi.button_pressed) else 1
	var ka  := Kin_Maya.calc_kin_unix(b_unix)
	var phi := Phi2X_Math.compute_personal_phase(b_unix, 0.0, 0.0)
	var omega := Phi2X_Math.compute_omega_bio(170.0, 70.0, sex)

	# Mettre à jour l'animation 3D (DrawMode: PROFIL=0, MATCH=1, THEORIE=2)
	var anim := find_child("AtomAnimation", true, false) as Node2D
	if anim and anim.has_method("set_mode"):
		anim.call("set_mode", 0)
		anim.set_kin(ka, {})
		anim.set_resonance(0.0, phi, 0.0)

	# Masquer le bouton Révéler
	var reveal_btn := vbox.find_child("HookRevealBtn", true, false) as Button
	if reveal_btn: reveal_btn.hide()

	# Remplir la section résultat
	var result_sec := vbox.find_child("HookResultSection", true, false) as VBoxContainer
	if not result_sec: return
	result_sec.visible = true

	var sep = HSeparator.new(); result_sec.add_child(sep)

	var kin_result = Label.new()
	kin_result.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	kin_result.add_theme_font_size_override("font_size", 24)
	kin_result.modulate = Kin_Maya.kin_color_rgb(ka["color"])
	kin_result.text = "🌀 " + Kin_Maya.format_kin_short(ka)
	result_sec.add_child(kin_result)

	var phi_lbl = Label.new()
	phi_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	phi_lbl.add_theme_font_size_override("font_size", 15)
	phi_lbl.modulate = UI_Theme.bar_color(false)
	phi_lbl.text = "φ_i = %.5f  |  ω_bio = %.2f Hz" % [phi, omega]
	result_sec.add_child(phi_lbl)

	var pol_lbl = Label.new()
	pol_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pol_lbl.add_theme_font_size_override("font_size", 15)
	pol_lbl.text = "Onde Φ — Solaire ☀" if sex == 0 else "Onde ♪ — Lunaire 🌙"
	pol_lbl.modulate = UI_Theme.text_warm() if sex == 0 else UI_Theme.bar_color(true)
	result_sec.add_child(pol_lbl)

	result_sec.add_child(HSeparator.new())

	var save_hint = Label.new()
	save_hint.text = "Votre empreinte est calculée ! Sauvegardez-la dans la Spacememory pour la retrouver sur tous vos appareils."
	save_hint.autowrap_mode = TextServer.AUTOWRAP_WORD
	save_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	save_hint.add_theme_font_size_override("font_size", 14)
	save_hint.modulate = UI_Theme.text_positive()
	result_sec.add_child(save_hint)

	var btn_forge = Button.new()
	btn_forge.text = "⚡ FORGER MON MULTIPASS"
	btn_forge.custom_minimum_size = Vector2(0, 64)
	btn_forge.add_theme_font_size_override("font_size", 20)
	var sb_forge = StyleBoxFlat.new()
	sb_forge.bg_color = Color(0.0, 0.45, 0.25); sb_forge.set_corner_radius_all(14)
	btn_forge.add_theme_stylebox_override("normal", sb_forge)
	btn_forge.connect("pressed", Callable(self, "_on_hook_forge").bind(b_unix, sex))
	result_sec.add_child(btn_forge)

	var btn_anon = Button.new()
	btn_anon.text = "👁  Explorer sans compte"
	btn_anon.custom_minimum_size = Vector2(0, 48)
	btn_anon.add_theme_font_size_override("font_size", 15)
	btn_anon.connect("pressed", Callable(self, "_on_hook_anonymous").bind(b_unix, sex))
	result_sec.add_child(btn_anon)

	_scale_node_fonts(result_sec)

	# ── Effet sensoriel "Aha!" ─────────────────────────────────
	Input.vibrate_handheld(400)
	_play_resonance_ping(0.92)
	var flash_rect = ColorRect.new()
	flash_rect.set_anchors_preset(PRESET_FULL_RECT)
	flash_rect.color = Color(1.0, 1.0, 1.0, 1.0)
	flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash_rect.z_index = 200
	add_child(flash_rect); flash_rect.move_to_front()
	var flash_tw = create_tween()
	flash_tw.tween_property(flash_rect, "color:a", 0.0, 1.4).set_ease(Tween.EASE_OUT)
	flash_tw.connect("finished", Callable(flash_rect, "queue_free"))

func _on_hook_forge(b_unix: int, sex: int):
	_hook_birth_unix = b_unix
	_hook_birth_sex  = sex
	if is_instance_valid(_hook_overlay): _hook_overlay.queue_free(); _hook_overlay = null
	_open_panel(TAB_PROFIL)

func _on_hook_anonymous(b_unix: int, sex: int):
	var rh = ""; for _i in range(64): rh += "0123456789abcdef"[randi() % 16]
	Player_Origin.init_from_multipass({
		"email": "anonyme_playground", "npub": "npub1_anonyme", "nsec": "nsec1_anonyme",
		"hex": rh, "g1pub": "G1_ANONYME_READONLY", "nostrns": "ipns_anonyme"
	})
	my_pubkey = "npub1_anonyme"
	Player_Origin.set_birth_profile(b_unix, 0.0, 0.0, sex, 170.0, 70.0)
	if is_instance_valid(_hook_overlay): _hook_overlay.queue_free(); _hook_overlay = null
	_rebuild_tab(TAB_PROFIL); _rebuild_tab(TAB_RESEAU)
	_check_authorization(); Nostr_Identity.connect_relay_list()
	var ka := Kin_Maya.calc_kin_unix(b_unix)
	var anim := find_child("AtomAnimation", true, false) as Node2D
	if anim and anim.has_method("set_kin"): anim.set_kin(ka, {})
	add_log("👁 Mode Explorateur. Empreinte cosmique active.")

# ─────────────────────────────────────────────────────────────
# QR APK P2P — Partage sans Internet
# ─────────────────────────────────────────────────────────────

func _show_apk_qr_popup(url: String):
	var popup = PanelContainer.new()
	popup.set_anchors_preset(PRESET_FULL_RECT)
	popup.add_theme_stylebox_override("panel", UI_Theme.make_panel_style(0.97))
	add_child(popup); popup.move_to_front()
	var m = MarginContainer.new()
	for side in ["margin_left","margin_right","margin_top","margin_bottom"]:
		m.add_theme_constant_override(side, 24)
	popup.add_child(m)
	var pv = VBoxContainer.new(); pv.add_theme_constant_override("separation", 14); m.add_child(pv)
	_lbl_title(pv, "📲 PARTAGE P2P SANS INTERNET", 20, UI_Theme.accent_color())
	var hint = Label.new()
	hint.text = "Votre ami flashe ce QR avec son téléphone pour télécharger l'APK directement depuis le vôtre."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD
	hint.add_theme_font_size_override("font_size", 14)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.modulate = UI_Theme.text_hint()
	pv.add_child(hint)
	var img_rect = TextureRect.new()
	img_rect.name = "ApkQRRect"
	img_rect.custom_minimum_size = Vector2(320, 320)
	img_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	img_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pv.add_child(img_rect)
	var gen_lbl = Label.new(); gen_lbl.text = "⏳ Génération QR…"
	gen_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; pv.add_child(gen_lbl)
	_lbl(pv, url, 11, UI_Theme.bar_color(false)).autowrap_mode = TextServer.AUTOWRAP_WORD
	var btn_c = Button.new(); btn_c.text = "FERMER"
	btn_c.custom_minimum_size = Vector2(0, 52)
	btn_c.connect("pressed", Callable(popup, "queue_free")); pv.add_child(btn_c)
	await get_tree().process_frame
	var img := QR_Generator.generate(url, 8)
	var tex := ImageTexture.create_from_image(img)
	if is_instance_valid(img_rect): img_rect.texture = tex
	if is_instance_valid(gen_lbl): gen_lbl.queue_free()

func add_log(msg: String):
	log_text.text += "\n[%s] %s" % [Time.get_time_string_from_system(), msg]
	var il = _find_in_tab(TAB_RESEAU, "InlineLog") as RichTextLabel
	if il: il.text = log_text.text
