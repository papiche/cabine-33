extends Control
# TabProfil chargé via preload — évite la dépendance sur l'indexation du class_name
const _TAB_PROFIL_SCRIPT := preload("res://scripts/TabProfil.gd")

signal recenter_requested
signal ritual_progress(pct: float)
signal ar_toggled(active: bool)
signal spacememory_received(events: Array)  # pensées lues sur le nœud hexagonal courant

@onready var state_label    = $TopBar/StateLabel
@onready var compass_label  = $HUDCenter/CompassLabel
@onready var distance_label = $HUDCenter/DistanceLabel
@onready var log_text       = $LogNode
@onready var photo_btn      = $BottomBar/PhotoBtn
@onready var sync_btn       = $BottomBar/SyncBtn

const CABINE_UNLOCK_KM: float = 0.05
const COL_GREEN := Color(0.0, 1.0, 0.5)

# ── Polices responsives ──────────────────────────────────────────
func _vp_font(base: int) -> int:
	return UI_Theme._get_scaled_size(base)


var my_pubkey: String = "npub1_alpha_000"
var _tab_profil: Node = null  # Instance de TabProfil (res://scripts/TabProfil.gd)
var wot_authorized: bool = false
var _cabine_dist_km: float = 999.0
var _hex_center_gps: Vector2 = Vector2.ZERO
var _last_bearing: float = 0.0

# ── Rituel de Phase : 33 secondes d'immobilité GPS au centre de l'hexagone
var _phase_ritual_active: bool = false
var _phase_ritual_timer: float = 0.0
var _phase_ritual_start_gps: Vector2 = Vector2.ZERO
const PHASE_RITUAL_DURATION: float = 33.0
const PHASE_RITUAL_GPS_TOLERANCE_KM: float = 0.025  # 25m — absorbe le GPS Drift en intérieur/urbain
const RITUAL_MOVEMENT_KMH: float = 2.0              # ~55 cm/s : seuil marche réelle vs drift GPS
var _ritual_last_ping_s: int = -1                   # Dernière seconde écoulée avec micro-ping haptique
var _ritual_prev_gps: Vector2 = Vector2.ZERO        # GPS lissé au tick précédent (calcul vélocité)
var _ritual_prev_gps_ts: float = 0.0               # Timestamp du tick précédent
var _smoothed_gps: Vector2 = Vector2.ZERO
var _gps_window: Array[Vector2] = []               # Fenêtre glissante 5 positions
const GPS_WINDOW_SIZE: int = 5

# ── Offcanvas panel
var _panel: PanelContainer = null
var _panel_open: bool = false
var _swipe_start_x: float = -1.0
var _swipe_accum_x: float = 0.0
var _did_drag_3d: bool = false  # true si le touch courant a glissé → pas un tap
var _tab_btns: Array[Button] = []
var _tab_pages: Array[ScrollContainer] = []
var _tab_vboxes: Array[VBoxContainer] = []
var _current_tab: int = 0
const TAB_PROFIL = 0
const TAB_MATCH  = 1
const TAB_SCAN   = 2
const TAB_RESEAU = 3

const _TAB_MATCH_SCRIPT  := preload("res://scripts/TabMatch.gd")
const _TAB_SCAN_SCRIPT   := preload("res://scripts/TabScan.gd")
const _TAB_RESEAU_SCRIPT := preload("res://scripts/TabReseau.gd")

var _tab_match:  Node = null
var _tab_scan:   Node = null
var _tab_reseau: Node = null

# ── Overlays
var viewfinder: TextureRect
var interference_rect: ColorRect
var _interference_hide_id: int = 0
var _web_capture_tex: ImageTexture = null   # Photo chargée depuis le sélecteur de fichier Web
var _web_photo_cb: JavaScriptObject = null  # Callback JS→GDScript pour la caméra Web
var _ar_active: bool = false                # Mode Réalité Augmentée actif

# ── Tween guards (évite les tweens concurrents)
var _panel_tween: Tween = null
var _scan_pulse_tween: Tween = null
var _blink_tween: Tween = null
var _cycle_tween: Tween = null
var _coherence_tween: Tween = null

# ── Haptique & synthé
var _last_haptic_k: float = 0.0
var _haptic_cooldown: float = 0.0
const HAPTIC_COOLDOWN_S: float = 0.4
var _synth_player: AudioStreamPlayer = null
var _synth_gen: AudioStreamGenerator = null
var _synth_pb: AudioStreamGeneratorPlayback = null
var _synth_phase: float = 0.0
var _synth_phase_r: float = 0.0    # Phase du canal droit (binaural rituel)
var _synth_volume_db: float = -60.0
var _synth_muted: bool = true
var _binaural_mode: bool = false    # Actif pendant le Rituel de Phase
var _orchestra_active: bool = false # Orchestre ON quand le scanner LOCA est actif
var _ping_amp: float = 0.0          # Accent court sur ma voix lors d'un atom_detected
var _atom_phases: Dictionary = {}   # npub → phase persistante entre frames (orchestre)
var _lfo_phase: float = 0.0         # LFO global modulé par le tone Kin (pulsation)
var _cached_lfo_hz: float = 1.05        # Cache du tone Kin → mis à jour à chaque init profil
var _hotcold_delay_feedback: float = 0.35  # Feedback delay : 0.35 (loin) → 0.0 (singularité)
var _tune_cents: float = 0.0        # Détune personnel [-50, +50] cents (calibration)
var _atom_wavetables: Dictionary = {} # npub → PackedFloat32Array (voix téléchargée)
# ── Arrays DSP pré-alloués (évite les allocations dans la boucle audio = pas de GC stutter)
const _DSP_MAX_ATOMS := 5  # top 5 atomes, cohérent avec le filtre existant
var _a_incs := PackedFloat32Array()  # incrément de phase par sample
var _a_ks   := PackedFloat32Array()  # résonance k (cible)
var _a_amps := PackedFloat32Array()  # amplitude courante lissée (évite les pops)
var _a_gl   := PackedFloat32Array()  # gain panoramique gauche
var _a_gr   := PackedFloat32Array()  # gain panoramique droit
var _a_sex  := PackedInt32Array()    # polarité (0=Φ 1=Octave)
var _a_ph   := PackedFloat32Array()  # phase courante
# Concert : delay line stéréo (echo spatial) — taille = ~200ms à 22050Hz
const _DELAY_SAMPLES := 4410  # 200ms
var _delay_buf_l: PackedFloat32Array = PackedFloat32Array()
var _delay_buf_r: PackedFloat32Array = PackedFloat32Array()
var _delay_idx: int = 0

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
var _hotcold_kbar_stylebox: StyleBoxFlat = null  # caché — évite allocation GC à 10Hz

# ── Hook screen (onboarding inversé)
var _hook_overlay: Control = null
var _hook_birth_unix: int = 0
var _hook_birth_sex: int = 0
# ── Deep linking Web
var _deeplink_match_npub: String = ""
var _pending_deeplink_tab: int = -1
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
	_build_bottom_nav()
	_build_content_card()
	_apply_bg_color()
	_style_topbar()
	_precompile_shaders()

	QR_Generator._init_gf()  # tables Galois initialisées dans le thread principal (évite race condition)
	photo_btn.connect("pressed", Callable(self, "_on_photo_pressed"))
	sync_btn.connect("pressed", Callable(self, "_on_sync_pressed"))

	_on_cycle_changed(SpaceTime_Manager.current_state)

	if OS.has_feature("web"):
		_web_photo_cb = JavaScriptBridge.create_callback(_on_web_photo_received)
		JavaScriptBridge.get_interface("window")["_godotPhotoCb"] = _web_photo_cb
		_check_deeplink()

	if not Player_Origin.is_initialized:
		# Masquer l'UI principale pour un onboarding épuré (fond atomique visible seul)
		$TopBar.hide()
		$HUDCenter.hide()
		$BottomBar.hide()
		var _nav := find_child("BottomNavBar", true, false)
		if _nav: _nav.hide()
		var hook_scene := load("res://scenes/HookScreen.tscn") as PackedScene
		_hook_overlay = hook_scene.instantiate() as Control
		_hook_overlay.connect("hook_completed", Callable(self, "_on_hook_completed"))
		_hook_overlay.connect("resonance_ping_requested", Callable(self, "_play_resonance_ping"))
		add_child(_hook_overlay)
		_hook_overlay.move_to_front()
	else:
		# Les onglets sont déjà construits par _build_content_card() — ne pas reconstruire
		_check_authorization()
		Nostr_Identity.connect_relay_list()
		if not Player_Origin.has_atom4love_profile():
			add_log("⚛ Profil ATOM4LOVE incomplet. Touchez ☰ → ⚛ PROFIL.")

func _input(event: InputEvent):
	# _input (avant que les Controls ne consomment) — nécessaire pour les DRAGS :
	# un ScrollContainer dans le panel "avale" les InputEventScreenDrag, rendant le
	# swipe-to-close inopérant si on utilise _unhandled_input.
	# On ne consomme PAS l'événement (pas de set_input_as_handled) → les boutons
	# et ScrollContainers continuent à fonctionner normalement.
	if event is InputEventScreenTouch:
		if event.pressed:
			_swipe_start_x  = event.position.x
			_swipe_accum_x  = 0.0
			_did_drag_3d    = false
		else:
			_swipe_start_x = -1.0
	elif event is InputEventScreenDrag:
		_did_drag_3d = true
		# Swipe-to-close : glissement vertical vers le bas (poignée en haut du panel)
		if _panel_open and _swipe_start_x >= 0.0 and event.relative.y > abs(event.relative.x) * 1.5:
			_swipe_accum_x = maxf(0.0, _swipe_accum_x + event.relative.y)
			if _swipe_accum_x > 80.0:
				_close_panel()

func _unhandled_input(event: InputEvent):
	# _unhandled_input pour le TAP (touch release) — seulement si aucun Control n'a
	# consommé l'événement. Évite d'ouvrir le panel quand on clique sur un bouton.
	if event is InputEventScreenTouch and not event.pressed and not _panel_open:
		if _did_drag_3d: return  # glissement libéré → pas un tap, ne pas ouvrir le menu
		var vp := get_viewport().get_visible_rect()
		var nav_y := vp.size.y - 148.0
		var top_y := 62.0
		var px: float = event.position.y
		if px > top_y and px < nav_y:
			_open_panel(TAB_PROFIL)
		else:
			_swipe_start_x = -1.0

func _notification(what: int):
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		# Priorité de fermeture : caméra > aide > galerie > panel > quitter
		if is_instance_valid(viewfinder) and viewfinder.visible:
			_close_camera()
		elif find_child("AideScreenNode", true, false) != null:
			find_child("AideScreenNode", true, false).queue_free()
		elif find_child("GalleryPopup", true, false) != null:
			find_child("GalleryPopup", true, false).queue_free()
		elif find_child("ApkQrPopup", true, false) != null:
			find_child("ApkQrPopup", true, false).queue_free()
		elif _panel_open:
			_close_panel()
		elif _ar_active:
			# AR actif → désactiver AR plutôt que quitter
			var btn := $BottomBar.find_child("ARBtn", true, false) as Button
			if btn: btn.button_pressed = false
			_on_ar_toggled(false)
		else:
			get_tree().quit()

func _process(delta):
	if Atom4Peace.active_bonds.size() > 0:
		Atom4Peace.check_bonds_status(SpaceTime_Manager.current_gps)
	if _haptic_cooldown > 0.0:
		_haptic_cooldown -= delta
	if _synth_pb and (_orchestra_active or _binaural_mode or _ping_amp > 0.01):
		_fill_synth_buffer()
	# Rituel de Phase : compte les secondes d'immobilité
	if _phase_ritual_active:
		_phase_ritual_timer += delta
		var pct := _phase_ritual_timer / PHASE_RITUAL_DURATION
		# Micro-ping haptique à chaque seconde (l'utilisateur "sent" la synchronisation)
		var current_s := int(_phase_ritual_timer)
		if current_s != _ritual_last_ping_s:
			_ritual_last_ping_s = current_s
			UI_Theme.vibrate(8)
		var dist_lbl := _find_in_tab(TAB_RESEAU, "Cabine33DistLabel") as Label
		if dist_lbl:
			dist_lbl.text = "🔮 Synchronisation : %.0f / 33s  (%.0f%%)" % [_phase_ritual_timer, pct * 100.0]
		emit_signal("ritual_progress", pct)
		# Mise à jour de l'anneau radial
		var ring := find_child("RitualRing", true, false)
		if is_instance_valid(ring) and ring.material is ShaderMaterial:
			(ring.material as ShaderMaterial).set_shader_parameter("pct", pct)
		if _phase_ritual_timer >= PHASE_RITUAL_DURATION:
			_complete_phase_ritual()

func _connect_signals():
	SpaceTime_Manager.connect("cycle_changed",    Callable(self, "_on_cycle_changed"))
	SpaceTime_Manager.connect("gps_updated",      Callable(self, "_on_gps_updated"))
	Atom4Peace.connect("encounter_started",       Callable(self, "_on_encounter_started"))
	Atom4Peace.connect("reality_forked",          Callable(self, "_on_reality_forked"))
	Atom4Peace.connect("resonance_detected",      Callable(self, "_on_resonance_detected"))
	UPlanet_API.connect("multipass_created",      Callable(self, "_on_multipass_success"))
	UPlanet_API.connect("api_error",              Callable(self, "_on_multipass_error"))
	UPlanet_API.connect("network_n2_analyzed",    Callable(self, "_on_n2_analyzed"))
	UPlanet_API.connect("sync_completed",         Callable(self, "_on_sync_completed"))
	UPlanet_API.connect("udrive_uploaded",        Callable(self, "_on_udrive_uploaded"))
	UPlanet_API.connect("udrive_roaming",         Callable(self, "_on_udrive_roaming"))
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
	state_label.modulate = ac
	distance_label.modulate = UI_Theme.bar_color(false)
	if _blink_tween: _blink_tween.kill()
	_blink_tween = create_tween().set_loops()
	_blink_tween.tween_property(distance_label, "modulate:a", 0.45, 1.6)
	_blink_tween.tween_property(distance_label, "modulate:a", 1.0, 1.6)

func _precompile_shaders():
	if not is_instance_valid(interference_rect): return
	interference_rect.modulate.a = 0.01
	interference_rect.show()
	await get_tree().process_frame
	interference_rect.hide()
	interference_rect.modulate.a = 1.0

func _update_nav_btns():
	var ac := UI_Theme.accent_color()
	for i in range(_tab_btns.size()):
		var btn := _tab_btns[i]
		if not is_instance_valid(btn): continue
		var active := _panel_open and i == _current_tab
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(ac.r, ac.g, ac.b, 0.20) if active else Color(0, 0, 0, 0)
		sb.border_width_top = 3 if active else 0
		sb.border_color = ac
		sb.set_corner_radius_all(10)
		btn.add_theme_stylebox_override("normal", sb)
		btn.modulate = ac if active else UI_Theme.text_color()

func _update_menu_btn_style():
	_update_nav_btns()

# ─────────────────────────────────────────────────────────────
# BOUTONS EXTRA (☰ MENU + 📍 RECENTER) dans BottomBar
# ─────────────────────────────────────────────────────────────

func _build_bottom_nav():
	# ── Utilitaires compacts dans $BottomBar (📍 🔇)
	var btn_recenter = Button.new()
	btn_recenter.text = "📍"; btn_recenter.custom_minimum_size = Vector2(72, 64)
	btn_recenter.add_theme_font_size_override("font_size", UI_Theme._get_scaled_size(20))
	btn_recenter.connect("pressed", Callable(self, "_on_recenter_pressed"))
	$BottomBar.add_child(btn_recenter)

	var btn_sound = Button.new()
	btn_sound.name = "SoundBtn"; btn_sound.text = "🔇"
	btn_sound.custom_minimum_size = Vector2(72, 64)
	btn_sound.add_theme_font_size_override("font_size", UI_Theme._get_scaled_size(20))
	btn_sound.connect("pressed", Callable(self, "_on_sound_toggle"))
	$BottomBar.add_child(btn_sound)

	var btn_ar = Button.new()
	btn_ar.name = "ARBtn"; btn_ar.text = "👁"
	btn_ar.custom_minimum_size = Vector2(72, 64)
	btn_ar.add_theme_font_size_override("font_size", UI_Theme._get_scaled_size(20))
	btn_ar.toggle_mode = true
	btn_ar.connect("toggled", Callable(self, "_on_ar_toggled"))
	$BottomBar.add_child(btn_ar)

	var btn_gallery = Button.new()
	btn_gallery.name = "GalleryBtn"; btn_gallery.text = "🗂"
	btn_gallery.custom_minimum_size = Vector2(72, 64)
	btn_gallery.add_theme_font_size_override("font_size", UI_Theme._get_scaled_size(20))
	btn_gallery.connect("pressed", Callable(self, "_show_gallery_popup"))
	$BottomBar.add_child(btn_gallery)

	# ❓ overlay flottant coin haut-droite — PAS dans un HBoxContainer (anchors ignorés dedans)
	var btn_aide := Button.new()
	btn_aide.name = "AideBtn"; btn_aide.text = "❓"
	btn_aide.flat = true
	btn_aide.custom_minimum_size = Vector2(52, 52)
	btn_aide.add_theme_font_size_override("font_size", UI_Theme._get_scaled_size(22))
	btn_aide.anchor_left  = 1.0; btn_aide.anchor_right  = 1.0
	btn_aide.anchor_top   = 0.0; btn_aide.anchor_bottom = 0.0
	btn_aide.offset_left  = -60; btn_aide.offset_right  = -4
	btn_aide.offset_top   = 6;   btn_aide.offset_bottom  = 58
	btn_aide.z_index = 50
	btn_aide.mouse_filter = MOUSE_FILTER_STOP
	# Premier lancement sans MULTIPASS → Guide interactif (7 étapes)
	# Après création MULTIPASS → AideScreen statique (référence rapide)
	if not Player_Origin.is_initialized:
		btn_aide.connect("pressed", func(): Guide_System.show_guide(0))
	else:
		btn_aide.connect("pressed", Callable(self, "_show_aide"))
	add_child(btn_aide)  # enfant de Main_UI directement, pas du HBoxContainer TopBar

	# ── Barre de navigation principale (4 onglets flottants)
	var nav := PanelContainer.new()
	nav.name = "BottomNavBar"
	nav.anchor_left = 0.0; nav.anchor_right = 1.0
	nav.anchor_top = 1.0;  nav.anchor_bottom = 1.0
	nav.offset_top = -148.0; nav.offset_bottom = -76.0  # 72px, au-dessus de $BottomBar (~76px)

	var nav_sb := StyleBoxFlat.new()
	var bg := UI_Theme.current()["bg"] as Color
	nav_sb.bg_color = Color(bg.r * 0.85, bg.g * 0.85, bg.b * 0.9, 0.96)
	nav_sb.border_width_top = 1
	nav_sb.border_color = Color(UI_Theme.accent_color(), 0.22)
	nav_sb.corner_radius_top_left = 18; nav_sb.corner_radius_top_right = 18
	nav.add_theme_stylebox_override("panel", nav_sb)

	var nav_row := HBoxContainer.new()
	nav_row.set_anchors_preset(PRESET_FULL_RECT)
	nav_row.add_theme_constant_override("separation", 0)
	nav.add_child(nav_row)

	_tab_btns.clear()
	var tab_data := [["👤", "PROFIL"], ["🔬", "MATCH"], ["📡", "RADAR"], ["🌍", "RÉSEAU"]]
	for i in range(4):
		var btn := Button.new()
		btn.name = "NavBtn" + str(i)
		btn.text = tab_data[i][0] + "\n" + tab_data[i][1]
		btn.size_flags_horizontal = SIZE_EXPAND_FILL
		btn.custom_minimum_size = Vector2(0, 72)
		btn.add_theme_font_size_override("font_size", UI_Theme._get_scaled_size(22))
		btn.flat = true
		btn.connect("pressed", Callable(self, "_on_nav_pressed").bind(i))
		nav_row.add_child(btn)
		_tab_btns.append(btn)

	add_child(nav)
	_update_nav_btns()

# ─────────────────────────────────────────────────────────────
# CONTENT CARD (flotte par-dessus la 3D, bords arrondis)
# ─────────────────────────────────────────────────────────────

func _build_content_card():
	_panel = PanelContainer.new()
	_panel.name = "ContentCard"
	# Ancré : marges 3% gauche/droite, entre TopBar (~60px) et BottomNavBar+BottomBar (~148px)
	_panel.anchor_left = 0.03; _panel.anchor_right = 0.97
	_panel.anchor_top = 0.0;   _panel.anchor_bottom = 1.0
	_panel.offset_top = 62.0;  _panel.offset_bottom = -150.0

	var psb := StyleBoxFlat.new()
	var bg := UI_Theme.current()["bg"] as Color
	psb.bg_color = Color(bg.r, bg.g, bg.b, 0.93)
	psb.set_corner_radius_all(22)
	psb.set_content_margin_all(0)
	_panel.add_theme_stylebox_override("panel", psb)
	_panel.clip_contents = true  # empêche le contenu de déborder hors des bords arrondis
	_panel.modulate.a = 0.0
	_panel.hide()
	add_child(_panel)
	_panel.move_to_front()

	# ── Drag handle "replier" — ligne tactile en haut du panel ──────────────
	# Tap → ferme le panel et laisse voir l'animation 3D
	var handle := Button.new()
	handle.name = "PanelDragHandle"
	handle.anchor_left = 0.0; handle.anchor_right = 1.0
	handle.anchor_top  = 0.0; handle.anchor_bottom = 0.0
	handle.offset_top  = 0.0; handle.offset_bottom = 28.0
	handle.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	handle.flat = true
	var hstyle := StyleBoxFlat.new()
	hstyle.bg_color = Color(1,1,1,0.0)
	handle.add_theme_stylebox_override("normal", hstyle.duplicate())
	handle.add_theme_stylebox_override("hover",  hstyle.duplicate())
	handle.add_theme_stylebox_override("pressed",hstyle.duplicate())
	# Pill visuelle centrée
	var pill := ColorRect.new()
	pill.color = Color(0.5, 0.5, 0.5, 0.45)
	pill.custom_minimum_size = Vector2(48, 5)
	pill.set_anchors_preset(Control.PRESET_CENTER)
	pill.offset_left = -24; pill.offset_right = 24; pill.offset_top = -2; pill.offset_bottom = 3
	handle.add_child(pill)
	handle.connect("pressed", Callable(self, "_close_panel"))
	_panel.add_child(handle)

	# Zone de contenu — les onglets sont chargés depuis des .tscn (éditables dans Godot)
	# ou construits en code si la scène n'existe pas encore.
	var holder := Control.new()
	holder.set_anchors_preset(PRESET_FULL_RECT)
	holder.offset_top = 28.0  # descend sous le handle
	_panel.add_child(holder)

	_tab_pages.clear()
	_tab_vboxes.clear()
	for i in range(4):
		var scroll := ScrollContainer.new()
		var margin := MarginContainer.new()
		margin.name = "TabMargin"
		for side in ["margin_left","margin_right","margin_top","margin_bottom"]:
			margin.add_theme_constant_override(side, 22 if side != "margin_top" else 18)
		margin.size_flags_horizontal = SIZE_EXPAND_FILL
		scroll.add_child(margin)

		var inner: VBoxContainer
		if i == TAB_PROFIL:
			# TabProfil est un class_name auto-contenu — instanciation directe
			_tab_profil = _TAB_PROFIL_SCRIPT.new() as Node
			_tab_profil.name = "InnerVBox"
			_tab_profil.size_flags_horizontal = SIZE_EXPAND_FILL
			_tab_profil.add_theme_constant_override("separation", 20)
			_tab_profil.log_requested.connect(add_log)
			_tab_profil.toast_requested.connect(_show_toast)
			_tab_profil.share_resonance_requested.connect(_on_share_resonance_link)
			_tab_profil.cosmic_card_requested.connect(_export_cosmic_card)
			_tab_profil.preview_instrument_requested.connect(_on_preview_instrument)
			_tab_profil.reset_requested.connect(_on_reset_multipass)
			margin.add_child(_tab_profil)
			inner = _tab_profil
		elif i == TAB_MATCH:
			_tab_match = _TAB_MATCH_SCRIPT.new() as Node
			_tab_match.name = "InnerVBox"
			_tab_match.size_flags_horizontal = SIZE_EXPAND_FILL
			_tab_match.log_requested.connect(add_log)
			_tab_match.toast_requested.connect(_show_toast)
			_tab_match.share_resonance_requested.connect(_on_share_resonance_link)
			_tab_match.simulate_encounter_requested.connect(_simulate_bluetooth_encounter)
			margin.add_child(_tab_match); inner = _tab_match
		elif i == TAB_SCAN:
			_tab_scan = _TAB_SCAN_SCRIPT.new() as Node
			_tab_scan.name = "InnerVBox"
			_tab_scan.size_flags_horizontal = SIZE_EXPAND_FILL
			_tab_scan.log_requested.connect(add_log)
			_tab_scan.toast_requested.connect(_show_toast)
			_tab_scan.scan_toggle_requested.connect(_on_loca_toggle)
			_tab_scan.haptic_requested.connect(_update_hot_cold_feedback)
			# Exposer les refs de widget scanner vers Main_UI (pour _on_scan_state_changed etc.)
			margin.add_child(_tab_scan); inner = _tab_scan
		elif i == TAB_RESEAU:
			_tab_reseau = _TAB_RESEAU_SCRIPT.new() as Node
			_tab_reseau.name = "InnerVBox"
			_tab_reseau.size_flags_horizontal = SIZE_EXPAND_FILL
			_tab_reseau.log_requested.connect(add_log)
			_tab_reseau.toast_requested.connect(_show_toast)
			_tab_reseau.open_profil_requested.connect(func(): _open_panel(TAB_PROFIL))
			_tab_reseau.reset_requested.connect(_on_reset_multipass)
			margin.add_child(_tab_reseau); inner = _tab_reseau
		else:
			inner = VBoxContainer.new()
			inner.name = "InnerVBox"
			inner.size_flags_horizontal = SIZE_EXPAND_FILL
			inner.add_theme_constant_override("separation", 20)
			margin.add_child(inner)

		scroll.set_anchors_preset(PRESET_FULL_RECT)
		scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.modulate.a = 0.0; scroll.visible = false
		holder.add_child(scroll)
		_tab_pages.append(scroll)
		_tab_vboxes.append(inner)

	_tab_profil.build()
	if is_instance_valid(_tab_match):  (_tab_match as TabMatch).build()
	if is_instance_valid(_tab_scan):
		(_tab_scan as TabScan).build()
		# Exposer les widget refs pour les callbacks Main_UI (hotcold, atom_detected…)
		resonance_bar     = (_tab_scan as TabScan).resonance_bar
		nearby_list       = (_tab_scan as TabScan).nearby_list
		loca_scan_btn     = (_tab_scan as TabScan).scan_btn
		loca_ssid_lbl     = (_tab_scan as TabScan).ssid_lbl
		_hotcold_indicator  = (_tab_scan as TabScan).hotcold_indicator
		_hotcold_arrow_lbl  = (_tab_scan as TabScan).hotcold_arrow_lbl
		_hotcold_k_lbl      = (_tab_scan as TabScan).hotcold_k_lbl
	if is_instance_valid(_tab_reseau): (_tab_reseau as TabReseau).build()
	_set_tab(TAB_PROFIL)

func _get_vbox(tab: int) -> VBoxContainer:
	if tab < _tab_vboxes.size(): return _tab_vboxes[tab]
	return null

func _set_tab(idx: int):
	if idx != _current_tab: UI_Theme.vibrate(15)
	var prev_tab := _current_tab
	_current_tab = idx
	for i in range(_tab_pages.size()):
		var page := _tab_pages[i]
		if i == idx:
			page.modulate.a = 0.0
			page.visible = true
			var tw := create_tween()
			tw.tween_property(page, "modulate:a", 1.0, 0.20).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		elif i == prev_tab and page.visible:
			var p := page
			var tw := create_tween()
			tw.tween_property(p, "modulate:a", 0.0, 0.12).set_ease(Tween.EASE_IN)
			tw.tween_callback(func(): if is_instance_valid(p): p.visible = false; p.modulate.a = 0.0)
		else:
			page.visible = false
			page.modulate.a = 0.0
	_update_nav_btns()
	_sync_anim_to_tab(idx)

func _sync_anim_to_tab(idx: int):
	var anim := find_child("AtomAnimation", true, false) as Node2D
	if not is_instance_valid(anim) or not anim.has_method("set_mode"): return
	var ka: Dictionary = {}
	if Player_Origin.birth_unix > 0:
		ka = Kin_Maya.calc_kin_unix(Player_Origin.birth_unix)
	match idx:
		TAB_PROFIL:
			# Mode icosaèdre respirant — profil joueur seul
			anim.call("set_mode", 0)  # DrawMode.PROFIL
			anim.call("set_kin", ka, {})
			anim.call("set_resonance", Player_Origin.personal_phase, Player_Origin.personal_phase, 0.0)
		TAB_MATCH:
			# Mode deux icosaèdres entrelacés — résonance avec partenaire
			anim.call("set_mode", 1)  # DrawMode.MATCH
			anim.call("set_kin", ka, {})
			var k: float = clamp(Player_Origin.personal_phase * 0.5 + 0.3, 0.0, 1.0)
			anim.call("set_resonance", k, Player_Origin.personal_phase, 0.0)
		TAB_SCAN, TAB_RESEAU:
			# Mode Goldberg — géométrie universelle
			anim.call("set_mode", 2)  # DrawMode.THEORIE
			anim.call("set_kin", ka, {})
			anim.call("set_resonance", 0.5, Player_Origin.personal_phase, 0.0)

func _on_nav_pressed(idx: int):
	if _panel_open and _current_tab == idx:
		_close_panel()
	elif _panel_open:
		_set_tab(idx)
	else:
		_open_panel(idx)

func _update_cached_lfo_hz():
	if Player_Origin.birth_unix > 0:
		var kd: Dictionary = Kin_Maya.calc_kin_unix(Player_Origin.birth_unix)
		var ti: int = kd.get("ti", 6)
		_cached_lfo_hz = float(ti + 1) * 0.15

func _rebuild_tab(idx: int):
	match idx:
		TAB_PROFIL:
			if is_instance_valid(_tab_profil): _tab_profil.refresh()
			_update_cached_lfo_hz()
		TAB_MATCH:
			if is_instance_valid(_tab_match): (_tab_match as TabMatch).refresh()
		TAB_SCAN:
			if is_instance_valid(_tab_scan):
				(_tab_scan as TabScan).refresh()
				# Ré-exposer les widget refs après rebuild
				resonance_bar     = (_tab_scan as TabScan).resonance_bar
				nearby_list       = (_tab_scan as TabScan).nearby_list
				loca_scan_btn     = (_tab_scan as TabScan).scan_btn
				loca_ssid_lbl     = (_tab_scan as TabScan).ssid_lbl
				_hotcold_indicator  = (_tab_scan as TabScan).hotcold_indicator
				_hotcold_arrow_lbl  = (_tab_scan as TabScan).hotcold_arrow_lbl
				_hotcold_k_lbl      = (_tab_scan as TabScan).hotcold_k_lbl
		TAB_RESEAU:
			if is_instance_valid(_tab_reseau):
				(_tab_reseau as TabReseau).wot_authorized = wot_authorized
				(_tab_reseau as TabReseau).cabine_dist_km = _cabine_dist_km
				(_tab_reseau as TabReseau).refresh()

func _toggle_panel():
	if _panel_open: _close_panel()
	else: _open_panel(_current_tab)

func _open_panel(tab: int = TAB_PROFIL):
	if _panel == null: return
	_panel.show()
	if _panel_tween and _panel_tween.is_running(): _panel_tween.kill()
	_panel_tween = create_tween()
	_panel_tween.tween_property(_panel, "modulate:a", 1.0, 0.22).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_panel_open = true
	_set_tab(tab)
	_update_nav_btns()

func _close_panel():
	if not _panel_open or _panel == null: return
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window._godot_qr_stop = true;")
	if _panel_tween and _panel_tween.is_running(): _panel_tween.kill()
	_panel_tween = create_tween()
	_panel_tween.tween_property(_panel, "modulate:a", 0.0, 0.18).set_ease(Tween.EASE_IN)
	_panel_tween.tween_callback(func(): if is_instance_valid(_panel): _panel.hide())
	_panel_open = false
	_update_nav_btns()

# ─────────────────────────────────────────────────────────────
# [TabProfil.gd] — Onglet PROFIL géré par res://scripts/TabProfil.gd
# ─────────────────────────────────────────────────────────────


# ─────────────────────────────────────────────────────────────
# ONGLET 🔬 MATCH — Calculateur bi-profil
# ─────────────────────────────────────────────────────────────

func _lbl_title(parent: Node, text: String, size: int, col: Color = Color.TRANSPARENT) -> Label:
	var l := UI_Theme.add_label(parent, text, size, col)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l

func _lbl(parent: Node, text: String, size: int = 14, col: Color = Color.TRANSPARENT) -> Label:
	return UI_Theme.add_label(parent, text, size, col)

func _lbl_section(parent: Node, text: String):
	UI_Theme.add_section_title(parent, text)

func _on_sex_toggle(active_btn: Button, other_btn: Button, _sex: int):
	active_btn.button_pressed = true; other_btn.button_pressed = false

func _parse_datetime(s: String) -> int:
	return Phi2X_Math.parse_datetime_safe(s)

func _build_date_fields(hb: HBoxContainer, fields: Array, on_change: Callable = Callable()) -> Array[LineEdit]:
	var out: Array[LineEdit] = []
	for info in fields:
		var col := VBoxContainer.new(); col.size_flags_horizontal = SIZE_EXPAND_FILL; hb.add_child(col)
		_lbl(col, info[1], 11, UI_Theme.text_secondary())
		var le := LineEdit.new(); le.name = info[0]
		le.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER
		le.max_length = info[2]; le.placeholder_text = info[1]
		if info.size() > 3: le.text = info[3]
		le.custom_minimum_size = Vector2(0, 52); col.add_child(le)
		if on_change.is_valid(): le.text_changed.connect(on_change)
		var le_cap: LineEdit = le; le_cap.focus_entered.connect(func(): le_cap.select_all())
		out.append(le)
	return out

func _show_toast(msg: String):
	var lbl := Label.new(); lbl.text = msg
	lbl.add_theme_font_size_override("font_size", UI_Theme._get_scaled_size(15))
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.0, 0.0, 0.0, 0.88); sb.set_corner_radius_all(10); sb.set_content_margin_all(14)
	lbl.add_theme_stylebox_override("normal", sb)
	var canvas := CanvasLayer.new(); canvas.layer = 200; add_child(canvas)
	lbl.set_anchors_preset(PRESET_CENTER_BOTTOM)
	lbl.position.y -= 140; lbl.size_flags_horizontal = SIZE_SHRINK_CENTER
	canvas.add_child(lbl)
	var tw := create_tween()
	tw.tween_interval(2.0)
	tw.tween_property(lbl, "modulate:a", 0.0, 0.4).set_ease(Tween.EASE_IN)
	tw.tween_callback(canvas.queue_free)

func _on_field_advance(text: String, next_field: LineEdit, max_len: int):
	if text.length() >= max_len and is_instance_valid(next_field):
		next_field.grab_focus()

func _make_panel_box(parent: Node) -> VBoxContainer:
	return UI_Theme.add_panel_vbox(parent)


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
	interference_rect.z_index = 80  # au-dessus des menus (z_index panel ≈ 0)
	interference_rect.hide()
	var sm = ShaderMaterial.new()
	var sh = load("res://shaders/interference.gdshader")
	if sh: sm.shader = sh; interference_rect.material = sm
	add_child(interference_rect)

func _update_interference_shader(other_phase: float, other_sex: int, k: float):
	if not is_instance_valid(interference_rect): return
	var mat = interference_rect.material as ShaderMaterial
	if not mat: return
	mat.set_shader_parameter("phase_a",     Player_Origin.personal_phase)
	mat.set_shader_parameter("phase_b",     other_phase)
	mat.set_shader_parameter("polarity_a",  Player_Origin.biological_sex)
	mat.set_shader_parameter("polarity_b",  other_sex)
	mat.set_shader_parameter("resonance_k", k)
	interference_rect.show()
	
	# Le shader disparaîtra toujours de lui-même après 5 secondes
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
	_synth_gen.mix_rate = 22050.0
	# 0.25s de buffer (vs 0.12s) : +130ms de latence mais divise les underruns par 2 sur mobile
	# Sur haut de gamme : imperceptible. Sur entrée de gamme : élimine les craquements.
	_synth_gen.buffer_length = 0.25
	_synth_player = AudioStreamPlayer.new()
	_synth_player.name = "ResonanceSynth"; _synth_player.stream = _synth_gen
	_synth_player.volume_db = -60.0
	# NE PAS add_child ici : l'AudioContext web requiert un geste utilisateur
	_synth_pb = null
	# Initialiser le delay stéréo (200ms de reverb spatiale)
	_delay_buf_l.resize(_DELAY_SAMPLES); _delay_buf_l.fill(0.0)
	_delay_buf_r.resize(_DELAY_SAMPLES); _delay_buf_r.fill(0.0)
	_delay_idx = 0
	# Pré-allouer les arrays DSP (évite les allocations = GC stutter dans la boucle audio)
	_a_incs.resize(_DSP_MAX_ATOMS); _a_incs.fill(0.0)
	_a_ks.resize(_DSP_MAX_ATOMS);   _a_ks.fill(0.0)
	_a_amps.resize(_DSP_MAX_ATOMS); _a_amps.fill(0.0)
	_a_gl.resize(_DSP_MAX_ATOMS);   _a_gl.fill(0.0)
	_a_gr.resize(_DSP_MAX_ATOMS);   _a_gr.fill(0.0)
	_a_sex.resize(_DSP_MAX_ATOMS);  _a_sex.fill(0)
	_a_ph.resize(_DSP_MAX_ATOMS);   _a_ph.fill(0.0)

func _fill_synth_buffer():
	if _synth_pb == null: return  # guard: get_stream_playback() pas encore appelé
	var frames = _synth_pb.get_frames_available()
	if frames <= 0: return
	var sr: float = _synth_gen.mix_rate

	# ── MODE BINAURAL RITUEL (prioritaire) — amplitude lissée par sample ───────
	if _binaural_mode:
		if _synth_player: _synth_player.volume_db = 0.0  # gain géré manuellement
		var bi_amp: float = db_to_linear(_synth_volume_db)
		var bi_target: float = db_to_linear(-12.0)
		var inc_l := Phi2X_Math.F_WATER / sr * TAU
		var inc_r := (Phi2X_Math.F_WATER + Phi2X_Math.F_PHI) / sr * TAU
		for _i in range(frames):
			bi_amp = lerpf(bi_amp, bi_target, 0.0005)
			_synth_pb.push_frame(Vector2(sin(_synth_phase) * 0.18, sin(_synth_phase_r) * 0.18) * bi_amp)
			_synth_phase   += inc_l; if _synth_phase   >= TAU: _synth_phase   -= TAU
			_synth_phase_r += inc_r; if _synth_phase_r >= TAU: _synth_phase_r -= TAU
		_synth_volume_db = linear_to_db(maxf(bi_amp, 0.00001))
		return

	# ── ORCHESTRE QUANTIQUE — Concert Électro ────────────────────────────────
	var atoms: Dictionary = Loca_Scanner.discovered_atoms
	var n_voices := 1 + atoms.size()

	var target_db: float = -60.0 if (not _orchestra_active and _ping_amp < 0.01) \
		else lerpf(-16.0, -5.0, minf(float(n_voices - 1) / 5.0, 1.0))
	# Le volume est maintenant lissé par sample (plus bas) — ne plus toucher volume_db du player
	# pour éviter les "pops" en escalier 4×/s (1 buffer = 0.25s)
	var current_amp: float = db_to_linear(_synth_volume_db)
	var target_amp:  float = db_to_linear(target_db)
	if target_amp < 0.0001 and current_amp < 0.0001:
		for _i in range(frames): _synth_pb.push_frame(Vector2.ZERO)
		return
	# Stabiliser le player à volume neutre — le gain se fait par multiplication des samples
	if _synth_player: _synth_player.volume_db = 0.0

	# Fondamentales — détune personnel en cents (calibration)
	var tune_ratio: float = pow(2.0, _tune_cents / 1200.0)
	var my_freq_c: float = maxf(Player_Origin.omega_bio, 100.0) * tune_ratio  # canal centre
	var my_freq_l: float = my_freq_c * 0.9982   # -3 Hz détune gauche (chorus)
	var my_freq_r: float = my_freq_c * 1.0018   # +3 Hz détune droite (chorus)
	var my_sex: int      = Player_Origin.biological_sex

	# LFO rythmique — _cached_lfo_hz mis à jour une seule fois à chaque init profil
	# (plus de calc_kin_unix dans la boucle audio = plus de stuttering sur mobile)
	var lfo_hz: float = _cached_lfo_hz
	var lfo_inc: float = lfo_hz / sr * TAU

	# Harmonique basse (une octave en dessous, 25% — l'assise du concert)
	var sub_freq_c: float = my_freq_c * 0.5

	# Phase séparée pour le sub-harmonique et le canal droit chorus
	# On utilise _synth_phase_r comme phase du canal droit de ma voix
	var my_inc_l: float = my_freq_l / sr * TAU
	var my_inc_r: float = my_freq_r / sr * TAU
	var sub_inc:  float = sub_freq_c / sr * TAU

	# Top 5 atoms par k — limite CPU sur vieux smartphones Android.
	# V2 production : porter _fill_synth_buffer en GDExtension (C++) ou AudioEffect
	# natif pour éliminer le coût GDScript interprété et supprimer les buffer underruns.
	# _atom_wavetables[npub] : non peuplé en Alpha (beacon SSID trop petit pour audio).
	# V2 : télécharger via TCP Loca_Scanner ou requête NOSTR vers le relay de l'atome.
	# En attendant, le fallback sin()/Phi2X donne un timbre correct pour chaque polarité.
	var _all_npubs := atoms.keys()
	if _all_npubs.size() > 5:
		_all_npubs.sort_custom(func(a, b): return atoms[a].get("k", 0.0) > atoms[b].get("k", 0.0))
		_all_npubs = _all_npubs.slice(0, 5)

	# ── PRÉ-CALCUL hors boucle chaude (critique pour éviter les underruns GDScript) ──
	# Toutes les opérations coûteuses (dict.get, calcul de fréquence, trigonométrie de pan)
	# sont effectuées UNE SEULE FOIS avant la boucle frames → division CPU par ~5 sur mobile.

	# Phases atomes persistantes (sync + cleanup)
	for npub in atoms:
		if not _atom_phases.has(npub): _atom_phases[npub] = atoms[npub].get("phase", 0.0)
	for npub in _atom_phases.keys():
		if not atoms.has(npub): _atom_phases.erase(npub)

	# Pré-calcul des données de chaque atome — on réutilise les arrays de classe (zéro allocation GC)
	var n_atoms: int = _all_npubs.size()
	for ni in range(n_atoms):
		var npub: String   = _all_npubs[ni]
		var atom: Dictionary = atoms[npub]
		var atom_k: float  = atom.get("k", 0.5)
		var phase_ratio: float = atom.get("phase", 0.0) / TAU
		var atom_kin_gi: int  = atom.get("kin_gi", 99)  # 99=inconnu (cohérent avec SSID)
		var atom_freq: float
		if atom_k >= 0.95:
			var delta: float = abs(atom.get("phase", 0.0) - Player_Origin.personal_phase)
			atom_freq = my_freq_c * (2.0 if abs(delta - PI) < 0.2 else 1.0)
		elif atom_k > 0.85:
			var cf: int = atom_kin_gi % 4 if atom_kin_gi < 20 else (int(phase_ratio * 4.0) % 4)
			match cf:
				0: atom_freq = my_freq_c * (1.2 if phase_ratio > 0.5 else (6.0/5.0))
				1: atom_freq = my_freq_c * (5.0/4.0 if phase_ratio > 0.5 else (9.0/8.0))
				2: atom_freq = my_freq_c * (45.0/32.0 if phase_ratio > 0.5 else (4.0/3.0))
				3: atom_freq = my_freq_c * (3.0/2.0 if phase_ratio > 0.5 else (25.0/16.0))
				_: atom_freq = my_freq_c * (3.0/2.0 if phase_ratio > 0.5 else (4.0/3.0))
		else:
			atom_freq = my_freq_c * (1.0 + phase_ratio * 0.5)
		_a_incs[ni] = atom_freq / sr * TAU
		_a_ks[ni]   = atom_k
		_a_sex[ni]  = atom.get("sex", 0)
		_a_ph[ni]   = _atom_phases.get(npub, 0.0)
		# Si l'atome est nouveau (pas encore dans _atom_phases), initialiser l'amplitude
		# à 0 pour éviter le pop d'apparition → sera lissé en ~9ms par le slew rate
		if not _atom_phases.has(npub): _a_amps[ni] = 0.0
		var pan: float = phase_ratio
		var gl := cos(pan * PI * 0.5); var gr := sin(pan * PI * 0.5)
		if ni % 2 == 1: _a_gl[ni] = gr; _a_gr[ni] = gl  # swap alternance
		else:           _a_gl[ni] = gl; _a_gr[ni] = gr

	# n_atoms = voix RÉELLEMENT jouées (≤5 après le slice) — pas atoms.size() (peut être 30+)
	# Si on divise par atoms.size(), le volume devient inaudible dans une grande salle
	var attenuation: float = 1.0 / float(1 + n_atoms)
	var phi_f: float = Phi2X_Math.PHI

	# ── Accès wavetable sans division — index flottant avec wrap ────────────────
	# Remplace read_wt() (fmod + division) par un accumulateur d'index pur
	var wt: PackedFloat32Array = Voice_Sampler.my_wavetable
	var wt_size: float = float(wt.size()) if not wt.is_empty() else 0.0
	var i_wt_size: int = wt.size()  # pré-casté une fois — évite int(wt_size) par sample
	# Accumulateur d'index : incrément par sample pré-calculé, wrap par soustraction
	# Économise ~22 000 multiplications flottantes par seconde vs l'ancienne méthode phase*inv_TAU
	var wt_idx_l: float = (_synth_phase   / TAU) * wt_size if wt_size > 0.0 else 0.0
	var wt_idx_r: float = (_synth_phase_r / TAU) * wt_size if wt_size > 0.0 else 0.0
	var wt_step_l: float = my_freq_l / sr * wt_size if wt_size > 0.0 else 0.0
	var wt_step_r: float = my_freq_r / sr * wt_size if wt_size > 0.0 else 0.0
	# sub_idx supprimé — calculé depuis _synth_phase pour éviter le saut de phase

	# ── BOUCLE FRAMES — arithmétique pure sur variables locales ─────────────────
	for _i in range(frames):
		var lfo_mod := (0.85 + 0.15 * sin(_lfo_phase)) * (1.0 + _ping_amp)
		_ping_amp = lerpf(_ping_amp, 0.0, 5.0 / sr)  # ~0.2s fade-out (vs <1ms avec 0.08)

		var wl: float; var wr: float
		if wt_size > 0.0:
			# Accumulateur pur : lecture directe de l'index, clampi évite out-of-bounds
			var i1l := clampi(int(wt_idx_l), 0, i_wt_size - 1); var i2l := (i1l + 1) % i_wt_size
			var i1r := clampi(int(wt_idx_r), 0, i_wt_size - 1); var i2r := (i1r + 1) % i_wt_size
			var fl := wt_idx_l - float(i1l); var fr := wt_idx_r - float(i1r)
			if my_sex == 0:
				wl = (lerpf(wt[i1l], wt[i2l], fl) + 0.5 * sin(_synth_phase   * phi_f)) / 1.5
				wr = (lerpf(wt[i1r], wt[i2r], fr) + 0.5 * sin(_synth_phase_r * phi_f)) / 1.5
			else:
				wl = lerpf(wt[i1l], wt[i2l], fl)
				wr = lerpf(wt[i1r], wt[i2r], fr)
		else:
			wl = (sin(_synth_phase) + 0.5 * sin(_synth_phase * phi_f)) / 1.5
			wr = (sin(_synth_phase_r) + 0.5 * sin(_synth_phase_r * phi_f)) / 1.5
		wl *= lfo_mod; wr *= lfo_mod

		_synth_phase += my_inc_l;   if _synth_phase   >= TAU: _synth_phase   -= TAU
		_synth_phase_r += my_inc_r; if _synth_phase_r >= TAU: _synth_phase_r -= TAU
		wt_idx_l += wt_step_l; if wt_idx_l >= wt_size: wt_idx_l -= wt_size
		wt_idx_r += wt_step_r; if wt_idx_r >= wt_size: wt_idx_r -= wt_size

		# Sub-harmonique calculé depuis _synth_phase (pas de variable d'état = pas de saut de phase)
		var sub_phase := _synth_phase + PI; if sub_phase >= TAU: sub_phase -= TAU
		var sub_i := clampi(int((sub_phase / TAU) * wt_size), 0, i_wt_size - 1) if wt_size > 0.0 else 0
		var sub: float = (wt[sub_i] if wt_size > 0.0 else sin(sub_phase)) * 0.25

		var mix_l := wl + sub; var mix_r := wr + sub
		for ni in range(n_atoms):
			# Slew rate sur l'amplitude : lisse les entrées/sorties d'atomes (~20ms attack/release)
			# lerpf(..., 0.005) à 22050 Hz → τ ≈ 1/(0.005*22050) ≈ 9ms — inaudible comme click
			_a_amps[ni] = lerpf(_a_amps[ni], _a_ks[ni], 0.005)
			var ap: float = _a_ph[ni]
			var aw: float = (sin(ap) + 0.5 * sin(ap * phi_f)) / 1.5 if _a_sex[ni] == 0 else sin(ap)
			aw *= _a_amps[ni]  # amplitude lissée, pas k brut
			mix_l += aw * _a_gl[ni]; mix_r += aw * _a_gr[ni]
			ap += _a_incs[ni]; if ap >= TAU: ap -= TAU
			_a_ph[ni] = ap

		mix_l = tanh(mix_l * attenuation) * 0.38
		mix_r = tanh(mix_r * attenuation) * 0.38

		var dl: float = _delay_buf_l[_delay_idx] * _hotcold_delay_feedback
		var dr: float = _delay_buf_r[_delay_idx] * _hotcold_delay_feedback
		_delay_buf_l[_delay_idx] = mix_r + dr
		_delay_buf_r[_delay_idx] = mix_l + dl
		_delay_idx = (_delay_idx + 1) % _DELAY_SAMPLES
		mix_l += dl; mix_r += dr

		# Lissage amplitude par sample (~0.0005 par sample = fade ~2s à 22kHz) — zéro pop
		current_amp = lerpf(current_amp, target_amp, 0.0005)
		_synth_pb.push_frame(Vector2(mix_l, mix_r) * current_amp)
		_lfo_phase += lfo_inc; if _lfo_phase >= TAU: _lfo_phase -= TAU

	# Sauvegarder l'amplitude courante en dB pour la prochaine itération
	_synth_volume_db = linear_to_db(maxf(current_amp, 0.00001))

	# Écrire les phases atomes calculées en dehors de la boucle frames (évite dict.set par sample)
	for ni in range(n_atoms):
		_atom_phases[_all_npubs[ni]] = _a_ph[ni]

func _play_resonance_ping(k: float):
	# L'orchestre fournit le feedback audio continu — le ping est un accent bref sur ma voix.
	# Si l'orchestre n'est pas actif (ex: HookScreen avant scanner), on démarre le synth solo.
	_last_haptic_k = k
	if _synth_muted: return
	_ping_amp = k  # accent transitoire sur ma voix (décroît dans _fill_synth_buffer)
	if not _orchestra_active:
		# Feedback solo (HookScreen, preview) : démarrer le synth si pas encore actif
		if is_instance_valid(_synth_player) and not _synth_player.playing:
			if _synth_player.get_parent() == null: add_child(_synth_player)
			_synth_player.volume_db = -60.0; _synth_volume_db = -60.0
			_synth_player.play()
			_synth_pb = _synth_player.get_stream_playback()

func _stop_resonance_synth():
	_last_haptic_k = 0.0; _ping_amp = 0.0
	# Ne pas couper le player si l'orchestre est actif — laisser _fill_synth_buffer gérer le volume
	if not _orchestra_active and _synth_player:
		_synth_player.volume_db = -60.0

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
				_synth_player.volume_db = -60.0
				_synth_volume_db = -60.0
				_synth_player.play()
				_synth_pb = _synth_player.get_stream_playback()
		if btn: btn.text = "🔊"
		add_log("🔊 Son activé — appuyez à nouveau pour couper.")

# ─────────────────────────────────────────────────────────────
# CALLBACKS : CYCLE / ÉNERGIE / GPS
# ─────────────────────────────────────────────────────────────

func _on_cycle_changed(state):
	if _cycle_tween: _cycle_tween.kill()
	if state == SpaceTime_Manager.TimeState.STATE_DAY_ACTION:
		state_label.text = "☀ JOUR — ACTION"
		state_label.modulate = UI_Theme.accent_color()
		_cycle_tween = create_tween()
		_cycle_tween.tween_property(self, "modulate", Color(1.0, 1.0, 1.0, 0.92), 1.2)
		if is_instance_valid(resonance_bar):
			var sb = StyleBoxFlat.new(); sb.bg_color = COL_GREEN; sb.set_corner_radius_all(4)
			resonance_bar.add_theme_stylebox_override("fill", sb)
	else:
		state_label.text = "🌙 NUIT — SYNC"
		state_label.modulate = UI_Theme.bar_color(true)
		_cycle_tween = create_tween()
		_cycle_tween.tween_property(self, "modulate", Color(0.55, 0.55, 1.0, 0.88), 2.0)
		if is_instance_valid(resonance_bar):
			var sb = StyleBoxFlat.new(); sb.bg_color = Color(0.4, 0.2, 1.0); sb.set_corner_radius_all(4)
			resonance_bar.add_theme_stylebox_override("fill", sb)
		add_log("🌙 RÊVE — Purge Spacememory en cours…")

func _on_preview_instrument():
	# Prévisualisation solo de la voix quantique — booste le ping_amp pour 1s
	_ping_amp = 1.0
	if not _orchestra_active and not _binaural_mode and _synth_player:
		if not _synth_player.playing:
			if _synth_player.get_parent() == null: add_child(_synth_player)
			_synth_player.volume_db = -60.0; _synth_volume_db = -60.0
			_synth_player.play()
			_synth_pb = _synth_player.get_stream_playback()
		# Éteindre automatiquement après 2 secondes si scanner pas actif
		get_tree().create_timer(2.0).timeout.connect(
			func():
				if not _orchestra_active: _synth_player.stop()
		, CONNECT_ONE_SHOT)

const _PENTAGON_NAMES := [
	"Pôle Nord", "Pôle Sud",
	"Orion", "Aldébaran", "Sirius", "Véga", "Antarès",
	"Fomalhaut", "Achernar", "Rigel", "Capella", "Deneb"
]
func _pentagon_sector(lat: float, lon: float) -> String:
	var best := 0; var best_d := 9999.0
	# Utilise haversine (distance sphérique) — la distance euclidienne en degrés
	# est fausse aux hautes latitudes (erreur > 30% à Paris)
	for i in range(Phi2X_Math.PENTAGONS_GPS.size()):
		var p: Vector2 = Phi2X_Math.PENTAGONS_GPS[i]
		var d := Phi2X_Math.haversine_distance(lat, lon, p.x, p.y)
		if d < best_d: best_d = d; best = i
	return _PENTAGON_NAMES[best] if best < _PENTAGON_NAMES.size() else "Secteur %d" % best

func _on_gps_updated(lat: float, lon: float):
	# Moyenne glissante sur 5 positions — snap si saut > 50m (réveil, métro)
	var new_gps := Vector2(lat, lon)
	if _smoothed_gps == Vector2.ZERO or _smoothed_gps.distance_to(new_gps) > 0.0005:
		_gps_window.clear()
		_smoothed_gps = new_gps
	else:
		_gps_window.append(new_gps)
		if _gps_window.size() > GPS_WINDOW_SIZE:
			_gps_window.pop_front()
		var avg := Vector2.ZERO
		for p in _gps_window: avg += p
		_smoothed_gps = avg / maxf(float(_gps_window.size()), 1.0)
	var slat := _smoothed_gps.x; var slon := _smoothed_gps.y

	# Centre géométrique de l'hexagone courant = cible de la Cabine Téléphonique
	_hex_center_gps = Phi2X_Math.get_hex_center_gps(slat, slon)
	_cabine_dist_km = Phi2X_Math.haversine_distance(slat, slon, _hex_center_gps.x, _hex_center_gps.y)
	# Réarmer le rituel quand on sort de la zone — permet de le rejouer dans un autre hex
	if _cabine_dist_km > CABINE_UNLOCK_KM: _cabine_ritual_done = false
	# Propager la distance au TabReseau (sans rebuild complet)
	if is_instance_valid(_tab_reseau): (_tab_reseau as TabReseau).set_cabine_distance(_cabine_dist_km)

	# Cap vers le centre pour guider l'utilisateur (flèche directionnelle)
	_last_bearing = Phi2X_Math.compute_bearing(slat, slon, _hex_center_gps.x, _hex_center_gps.y)
	var sector := _pentagon_sector(slat, slon)
	compass_label.text = "%s  ⬡ %s" % [_bearing_arrow(_last_bearing), sector]
	distance_label.text = "%.0fm" % (_cabine_dist_km * 1000.0)

	# Rituel de phase : vérifier la stabilité GPS par VÉLOCITÉ (pas distance absolue)
	# La distance absolue cause des faux-reset dus au drift GPS (±15-20m en urbain).
	# La vitesse différencie drift (oscillation haute-freq, faible déplacement net)
	# d'une vraie marche (déplacement directionnel soutenu > 2 km/h).
	if _phase_ritual_active:
		if not Phi2X_Math.is_in_range(slat, slon, _hex_center_gps.x, _hex_center_gps.y, CABINE_UNLOCK_KM):
			_cancel_phase_ritual()
			return
		var now_ts: float = Time.get_unix_time_from_system()
		var dt_s: float = now_ts - _ritual_prev_gps_ts
		var speed_kmh := 0.0
		# dt_s > 1.0 : on ne juge la vitesse que sur des intervalles significatifs
		# → élimine les faux positifs dus au drift GPS (rebond élastique sur interval court)
		if dt_s > 1.0 and _ritual_prev_gps != Vector2.ZERO:
			var delta_km: float = Phi2X_Math.haversine_distance(
				_ritual_prev_gps.x, _ritual_prev_gps.y, slat, slon)
			if delta_km > 0.001:  # filtre < 1m (bruit de précision GPS)
				speed_kmh = delta_km / dt_s * 3600.0
		# Mise à jour uniquement toutes les 1s pour éviter dt_s trop petit
		if dt_s > 1.0 or _ritual_prev_gps == Vector2.ZERO:
			_ritual_prev_gps = Vector2(slat, slon)
			_ritual_prev_gps_ts = now_ts
		if speed_kmh > RITUAL_MOVEMENT_KMH:
			_phase_ritual_timer = 0.0
			_phase_ritual_start_gps = _smoothed_gps
			add_log("⚡ Déplacement détecté (%.1f km/h) — Resynchronisation…" % speed_kmh)
		return  # Pendant le rituel, ne pas redéclencher et ne pas mettre à jour le label

	# Mise à jour du label Cabine-33 dans l'onglet RÉSEAU
	var dist_lbl := _find_in_tab(TAB_RESEAU, "Cabine33DistLabel") as Label
	if dist_lbl:
		var dval := "%.0fm" % (_cabine_dist_km * 1000.0)
		dist_lbl.text = ("✅ Centre HEX (%s)" % dval) if _cabine_dist_km <= CABINE_UNLOCK_KM \
			else ("🔒 %s — %s (< %.0fm)" % [_bearing_arrow(_last_bearing), dval, CABINE_UNLOCK_KM * 1000])
		dist_lbl.modulate = COL_GREEN if _cabine_dist_km <= CABINE_UNLOCK_KM else Color(0.7, 0.7, 0.7)

	if _cabine_dist_km <= CABINE_UNLOCK_KM and wot_authorized and not _cabine_ritual_done:
		_start_phase_ritual(lat, lon)

# ─────────────────────────────────────────────────────────────
# RITUEL DE PHASE — CABINE TÉLÉPHONIQUE
# ─────────────────────────────────────────────────────────────

func _bearing_arrow(bearing: float) -> String:
	# Si gyroscope disponible, calcule l'angle RELATIF à l'orientation du téléphone
	# → la flèche tourne avec le téléphone comme une vraie boussole
	var phone_azimut := 0.0
	if OS.has_feature("android"):
		var grav := Input.get_gravity()
		var mag  := Input.get_magnetometer()
		if grav.length() > 0.5 and mag.length() > 0.5:
			var g := grav.normalized(); var m := mag.normalized()
			var east := g.cross(m); if east.length() > 0.001: east = east.normalized()
			var north := east.cross(g).normalized()
			phone_azimut = fmod(rad_to_deg(atan2(north.x, north.z)) + 360.0, 360.0)
	var relative := fmod(bearing - phone_azimut + 360.0, 360.0)
	var arrows := ["↑", "↗", "→", "↘", "↓", "↙", "←", "↖"]
	return arrows[int((relative + 22.5) / 45.0) % 8]

func _start_phase_ritual(lat: float, lon: float):
	_phase_ritual_active = true
	_phase_ritual_timer = 0.0
	_ritual_last_ping_s = -1
	_ritual_prev_gps = Vector2.ZERO
	_ritual_prev_gps_ts = 0.0
	_phase_ritual_start_gps = Vector2(lat, lon)
	UI_Theme.vibrate(200)
	add_log("🔮 RITUEL DE PHASE — Restez immobile 33s pour déverrouiller le journal géolocalisé de ce lieu.")
	add_log("📍 Position verrouillée : %.5f, %.5f" % [lat, lon])
	# Anneau de progression radial — s'affiche au centre de l'écran
	_spawn_ritual_ring()
	# Binaural Φ : F_WATER gauche, F_WATER+F_PHI droite → battement 33.17 Hz (état alpha)
	# Anti-click : volume forcé à -60dB avant play(), le lerpf dans _fill_synth_buffer monte ensuite.
	if not _synth_muted:
		_binaural_mode = true
		_synth_phase_r = 0.0
		if is_instance_valid(_synth_player) and not _synth_player.playing:
			if _synth_player.get_parent() == null: add_child(_synth_player)
			_synth_player.volume_db = -60.0  # volume silencieux AVANT play()
			_synth_volume_db = -60.0         # synchronise l'état interne
			_synth_player.play()
			_synth_pb = _synth_player.get_stream_playback()

func _spawn_ritual_ring():
	# Anneau radial centré sur l'écran — mis à jour via ritual_progress signal
	var existing := find_child("RitualRing", true, false)
	if existing: existing.queue_free()
	var ring := ColorRect.new()
	ring.name = "RitualRing"
	ring.set_anchors_preset(PRESET_CENTER)
	ring.custom_minimum_size = Vector2(180, 180)
	ring.offset_left = -90; ring.offset_right = 90
	ring.offset_top  = -90; ring.offset_bottom = 90
	ring.mouse_filter = MOUSE_FILTER_IGNORE
	ring.z_index = 75
	# Shader de cercle arc progressif (simple CanvasItem shader)
	var sh := load("res://shaders/ritual_ring.gdshader") if ResourceLoader.exists("res://shaders/ritual_ring.gdshader") else null
	if sh:
		var sm := ShaderMaterial.new(); sm.shader = sh
		ring.material = sm
	else:
		ring.color = Color(0.0, 0.8, 1.0, 0.0)  # fallback sans shader
	add_child(ring)

func _cancel_phase_ritual():
	_phase_ritual_active = false
	_binaural_mode = false
	_stop_resonance_synth()
	# Si le scanner était actif, l'orchestre reprend automatiquement via _fill_synth_buffer
	# (_orchestra_active = true → volume remonte, pas besoin de .play() car player tourne déjà)
	emit_signal("ritual_progress", 0.0)
	var _rr := find_child("RitualRing", true, false)
	if _rr: _rr.queue_free()
	add_log("❌ Rituel interrompu — vous vous êtes éloigné du Nœud PHI.")

func _complete_phase_ritual():
	_phase_ritual_active = false
	_binaural_mode = false
	_cabine_ritual_done = true
	UI_Theme.vibrate(500)
	emit_signal("ritual_progress", 1.0)
	# Anneau final : flash blanc → disparaît
	var ring := find_child("RitualRing", true, false)
	if is_instance_valid(ring):
		var tw := create_tween()
		tw.tween_property(ring, "modulate:a", 0.0, 0.6)
		tw.tween_callback(ring.queue_free)
	add_log("✨ CABINE DÉVERROUILLÉE — Phase synchronisée avec le nœud hexagonal !")
	_trigger_cabine_ritual()
	_subscribe_spacememory()

func _subscribe_spacememory():
	# Lecture de la Spacememory sociale — Kind 1 géotagués sur ce nœud hexagonal
	# Deux niveaux d'abonnement : hexagone exact + portail Goldberg (zone régionale)
	var gps := SpaceTime_Manager.current_gps
	var ts  := float(Time.get_unix_time_from_system())
	var tags := Phi2X_Math.geo_tags(gps.x, gps.y, ts)  # [pent_tag, hex_tag]
	var pent_tag_v: String = tags[0][1]   # "a4l:P02"
	var hex_tag_v:  String = tags[1][1]   # "a4l:P02H820B7F6C"
	# Abonnement hexagone exact (local ~1 km²)
	Nostr_Identity.subscribe({"kinds": [1], "#l": [hex_tag_v], "limit": 33})
	# Abonnement portail (zone Goldberg — pensées de la région)
	Nostr_Identity.subscribe({"kinds": [1], "#l": [pent_tag_v], "limit": 12, "since": int(ts) - 86400})
	add_log("📡 Spacememory — %s · %s" % [hex_tag_v, pent_tag_v])
	if not Nostr_Identity.event_received.is_connected(_on_spacememory_event):
		Nostr_Identity.event_received.connect(_on_spacememory_event)

var _spacememory_seen: Dictionary = {}        # event_id → true
var _spacememory_seen_queue: Array = []       # FIFO pour purge glissante sans clear brutal

func _on_spacememory_event(ev: Dictionary):
	if ev.get("kind", 0) != 1: return
	var eid: String = str(ev.get("id", ""))
	if eid != "" and _spacememory_seen.has(eid): return
	if eid != "":
		_spacememory_seen[eid] = true
		_spacememory_seen_queue.append(eid)
	# FIFO : supprimer les 200 plus anciens quand on dépasse 500 (jamais de clear total)
	if _spacememory_seen_queue.size() > 500:
		for _i in range(200):
			if _spacememory_seen_queue.is_empty(): break
			var old_id: String = _spacememory_seen_queue.pop_front()
			_spacememory_seen.erase(old_id)
	for tag in ev.get("tags", []):
		if tag is Array and tag.size() >= 2 and str(tag[0]) == "l" and str(tag[1]).begins_with("a4l:"):
			emit_signal("spacememory_received", [ev])
			var preview := str(ev.get("content", "")).strip_edges().substr(0, 40)
			add_log("💭 « %s… »  [%s]" % [preview, str(tag[1])])
			return

# ─────────────────────────────────────────────────────────────
# CALLBACKS : ATOM / RÉSONANCE
# ─────────────────────────────────────────────────────────────

func _on_resonance_detected(pubkey: String, k: float, is_singularity: bool):
	var bond = Atom4Peace.active_bonds.get(pubkey, {})
	_update_interference_shader(bond.get("other_phase", 0.0), bond.get("other_sex", 1), k)
	if is_instance_valid(resonance_bar): resonance_bar.value = k
	var label = "✨ SINGULARITÉ" if is_singularity else "Résonance"
	add_log("%s k=%.3f avec %s" % [label, k, pubkey.substr(0, 10)])

func _on_atom_detected(npub: String, k: float, _phase: float, _sex: int):
	# Déléguer l'affichage au TabScan (liste atomes + hotcold indicator)
	if is_instance_valid(_tab_scan):
		var ts := _tab_scan as TabScan
		ts.update_atom_list(Loca_Scanner.discovered_atoms)
		if ts.hotcold_target_npub != "" and npub == ts.hotcold_target_npub:
			ts.update_hotcold(k)
	# Fallback si refs directes encore disponibles
	if is_instance_valid(resonance_bar):
		var best := Loca_Scanner.get_sorted_by_resonance()
		if best.size() > 0: resonance_bar.value = best[0]["k"]
	_update_hot_cold_feedback(k)

func _on_super_coherence(npub: String, k: float):
	add_log("💫 MATCH QUANTIQUE ! k=%.3f avec %s" % [k, npub.substr(0, 10)])
	if not is_instance_valid(resonance_bar): return
	# Tuer le tween précédent — évite les tweens orphelins si k oscille sur 0.95
	if _coherence_tween and _coherence_tween.is_running(): _coherence_tween.kill()
	_coherence_tween = create_tween()
	for _i in range(4):
		_coherence_tween.tween_property(resonance_bar, "modulate", Color(1, 1, 1, 1), 0.15)
		_coherence_tween.tween_property(resonance_bar, "modulate", Color(0, 1, 0.5, 1), 0.15)

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
	var duration_ms: int; var cooldown_s: float
	if k > 0.9:
		# Zone Geiger : vibrations ultra-courtes, intervalle exponentiel (effet compteur)
		# k=0.90 → 20ms/0.20s | k=0.95 → 13ms/0.09s | k=1.0 → 5ms/0.05s
		var t := (k - 0.9) / 0.1         # [0..1] dans la zone critique
		duration_ms = int(lerpf(20.0, 5.0, t))
		cooldown_s  = lerpf(0.20, 0.05, t * t)  # quadratique = accélération perceptive
	else:
		# Zone sonar normale : k=0.2 → 88ms/0.42s | k=0.9 → 18ms/0.14s
		duration_ms = int((1.0 - k) * 100.0 + 8.0)
		cooldown_s  = (1.0 - k) * HAPTIC_COOLDOWN_S + 0.1
	UI_Theme.vibrate(duration_ms)
	# Sur Web, navigator.vibrate est throttlé par les navigateurs — cooldown minimum 150ms
	_haptic_cooldown = maxf(cooldown_s, 0.15) if OS.has_feature("web") else cooldown_s
	if not _synth_muted and k > 0.35:
		_play_resonance_ping(k)

func _update_hotcold_display(k: float):
	if not is_instance_valid(_hotcold_indicator): return
	var cold := Color(0.05, 0.15, 0.8)   # bleu électrique
	var gold := Color(1.0,  0.80, 0.1)   # or (Onde Φ, singularité)
	var hot  := Color(1.0,  0.15, 0.05)  # rouge (Onde Octave)

	# Couleur de base : froid→chaud, puis vire à l'or à l'approche de la singularité
	var base_col: Color = cold.lerp(hot, k) if k < 0.85 else hot.lerp(gold, (k - 0.85) / 0.15)

	# Pulsation couleur en zone critique (k > 0.9) — l'écran "vibre" visuellement
	if k > 0.9:
		var pulse_t := (sin(Time.get_ticks_msec() / 1000.0 * TAU * 4.0) * 0.5 + 0.5)
		base_col = base_col.lerp(gold, pulse_t * (k - 0.9) * 10.0)
	_hotcold_indicator.color = base_col

	if is_instance_valid(_hotcold_k_lbl):
		_hotcold_k_lbl.text = "k = %.4f" % k
		_hotcold_k_lbl.modulate = base_col
	if is_instance_valid(_hotcold_arrow_lbl):
		if k > _hotcold_prev_k + 0.005:
			_hotcold_arrow_lbl.text = "🔥 ▲"; _hotcold_arrow_lbl.modulate = hot
		elif k < _hotcold_prev_k - 0.005:
			_hotcold_arrow_lbl.text = "❄ ▼"; _hotcold_arrow_lbl.modulate = cold
		else:
			_hotcold_arrow_lbl.text = "— ="; _hotcold_arrow_lbl.modulate = Color(0.7, 0.7, 0.7)

	# Son cristallin : à l'approche de k=1, réduire le delay (son plus sec = plus proche)
	# fade_far du shader audio = 0 à k=1 (unisson pur, zéro réverb)
	if _orchestra_active and not _binaural_mode:
		var delay_feedback := lerpf(0.35, 0.0, clampf((k - 0.7) / 0.3, 0.0, 1.0))
		# Le delay_buf decay se réduit dynamiquement via le gain de feedback dans _fill_synth_buffer
		# Ici on stocke pour que la boucle audio le lise
		_hotcold_delay_feedback = delay_feedback

	var kb := _find_in_tab(TAB_SCAN, "HotColdKBar") as ProgressBar
	if kb:
		kb.value = k
		if _hotcold_kbar_stylebox == null:
			_hotcold_kbar_stylebox = StyleBoxFlat.new()
			_hotcold_kbar_stylebox.set_corner_radius_all(4)
			kb.add_theme_stylebox_override("fill", _hotcold_kbar_stylebox)
		_hotcold_kbar_stylebox.bg_color = base_col
	_hotcold_prev_k = k

# ─────────────────────────────────────────────────────────────
# CALLBACKS : LOCA SCANNER
# ─────────────────────────────────────────────────────────────

func _on_loca_toggle():
	# Pre-unlock AudioContext Web : add_child doit se faire depuis un geste utilisateur.
	# On l'injecte ici (clic scanner) pour que le rituel binaural auto-lancé par GPS fonctionne.
	if _synth_player and _synth_player.get_parent() == null:
		add_child(_synth_player)
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
	_orchestra_active = is_scanning
	if not _synth_muted and _synth_player:
		if is_scanning and not _binaural_mode:
			# Démarrer l'orchestre au clic scanner (AudioContext déjà déverrouillé dans _on_loca_toggle)
			if not _synth_player.playing:
				_synth_player.volume_db = -60.0; _synth_volume_db = -60.0
				_synth_player.play()
				_synth_pb = _synth_player.get_stream_playback()
		elif not is_scanning and not _binaural_mode:
			# Fade-out gracieux : _orchestra_active=false → lerpf volume vers -60dB
			# dans _fill_synth_buffer → quand silence atteint, on arrête le player.
			_atom_phases.clear()  # vide les phases → silence progressif (pas de clic)
			# Arrêt différé après le fondu (~1.5s pour lerpf 0.05 × 60fps)
			get_tree().create_timer(1.8).timeout.connect(
				func():
					if not _orchestra_active and not _binaural_mode and _synth_player:
						_synth_player.stop()
						_delay_buf_l.fill(0.0); _delay_buf_r.fill(0.0)  # vider le delay
			, CONNECT_ONE_SHOT)
	if is_instance_valid(loca_scan_btn):
		loca_scan_btn.text = "⏹ ARRÊTER" if is_scanning else "▶ SCANNER"
	# Propager au TabScan pour mettre à jour le SSID affiché
	if is_instance_valid(_tab_scan): (_tab_scan as TabScan).update_scan_state(is_scanning)
	if is_instance_valid(loca_ssid_lbl):
		loca_ssid_lbl.text = ("SSID : " + Loca_Scanner.build_broadcast_ssid()) if is_scanning else "SSID : —"
	var btn_hc = _find_in_tab(TAB_SCAN, "HotColdActivateBtn") as Button
	if btn_hc: btn_hc.text = "⏹ DÉSACTIVER" if is_scanning else "▶ ACTIVER DÉCOUVERTE"
	if is_instance_valid(resonance_bar):
		if _scan_pulse_tween and _scan_pulse_tween.is_running(): _scan_pulse_tween.kill()
		if is_scanning:
			_scan_pulse_tween = create_tween().set_loops()
			_scan_pulse_tween.tween_property(resonance_bar, "modulate:a", 0.35, 0.9)
			if is_instance_valid(nearby_list):
				_scan_pulse_tween.parallel().tween_property(nearby_list, "modulate:a", 0.35, 0.9)
			_scan_pulse_tween.tween_property(resonance_bar, "modulate:a", 1.0, 0.9)
			if is_instance_valid(nearby_list):
				_scan_pulse_tween.parallel().tween_property(nearby_list, "modulate:a", 1.0, 0.9)
		else:
			resonance_bar.modulate.a = 1.0
			if is_instance_valid(nearby_list): nearby_list.modulate.a = 1.0

func _on_apk_server_started(url: String):
	add_log("📲 Serveur APK : " + url)
	if is_instance_valid(loca_ssid_lbl): loca_ssid_lbl.text = "URL: " + url
	_show_apk_qr_popup(url)

func _on_reset_multipass(): _on_reset_pressed()  # alias depuis TabProfil

func _on_reset_pressed():
	var dlg = ConfirmationDialog.new()
	dlg.title = "🔄 Déconnexion — Oublier ce MULTIPASS"
	dlg.dialog_text = "Supprimer les données MULTIPASS locales ?\n\nVos clés NOSTR restent sur UPlanet. Vous pourrez créer un nouveau MULTIPASS ou en récupérer un existant."
	add_child(dlg)
	dlg.confirmed.connect(_do_reset)
	dlg.popup_centered()

func _do_reset():
	Player_Origin.reset()
	my_pubkey = ""
	wot_authorized = false
	_rebuild_tab(TAB_PROFIL)
	_rebuild_tab(TAB_RESEAU)
	add_log("🔄 MULTIPASS réinitialisé.")
	_close_panel()

	# Relancer l'onboarding propre (même chemin que le premier démarrage)
	if is_instance_valid(_hook_overlay): _hook_overlay.queue_free(); _hook_overlay = null
	var hook_scene := load("res://scenes/HookScreen.tscn") as PackedScene
	_hook_overlay = hook_scene.instantiate() as Control
	_hook_overlay.connect("hook_completed", Callable(self, "_on_hook_completed"))
	_hook_overlay.connect("resonance_ping_requested", Callable(self, "_play_resonance_ping"))
	add_child(_hook_overlay); _hook_overlay.move_to_front()
	$TopBar.hide(); $HUDCenter.hide(); $BottomBar.hide()
	var nav := find_child("BottomNavBar", true, false)
	if nav: nav.hide()

func _on_multipass_success(data):
	Player_Origin.init_from_multipass(data)
	my_pubkey = Player_Origin.user_npub
	# Propager les coordonnées de naissance collectées dans HookScreen
	if is_instance_valid(_tab_profil):
		if _tab_profil.hook_birth_lat != 0.0 or _tab_profil.hook_birth_lon != 0.0:
			Player_Origin.birth_lat = _tab_profil.hook_birth_lat
			Player_Origin.birth_lon = _tab_profil.hook_birth_lon
	_rebuild_tab(TAB_PROFIL); _rebuild_tab(TAB_RESEAU)
	_check_authorization(); Nostr_Identity.connect_relay_list()
	add_log("⚛ MULTIPASS créé ! Configurez votre profil ATOM4LOVE.")
	if Player_Origin.has_atom4love_profile():
		Nostr_Identity.publish_atom4love_cert()
	call_deferred("_show_cooperative_invite")

func _on_multipass_error(msg):
	var status = _find_in_tab(TAB_PROFIL, "MultipassStatus") as Label
	if status: status.text = "Erreur : " + msg; status.modulate = Color(1, 0.3, 0.3)
	var btn := _find_in_tab(TAB_PROFIL, "ForgeBtn") as Button
	if btn: btn.disabled = false

func _on_nostr_relay_connected(url: String):    add_log("📡 Relais connecté : " + url)
func _on_nostr_relay_disconnected(url: String): add_log("⚠ Relais déconnecté : " + url)
func _on_nostr_profile_published(n: int):       add_log("✅ Profil Kind 0 publié sur %d relais." % n)

func _on_nostr_follows_updated(_follows: Array):
	add_log("👥 Follows mis à jour : %d contacts." % Nostr_Identity.follows.size())
	_rebuild_tab(TAB_RESEAU)

# ─────────────────────────────────────────────────────────────
# CALLBACKS : RÉSEAU / FOLLOWS
# ─────────────────────────────────────────────────────────────

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


func _on_theme_changed(_id: String):
	# Fond d'écran (opaque si thème clair, transparent si sombre)
	_apply_bg_color()
	# Topbar, btn menu, onglets actifs
	_style_topbar()
	_update_menu_btn_style()
	_set_tab(_current_tab)
	# ContentCard — style carte flottante (nouvelle UI)
	if is_instance_valid(_panel):
		var t := UI_Theme.current()
		var t_bg := t["bg"] as Color
		var psb := StyleBoxFlat.new()
		psb.bg_color = Color(t_bg.r, t_bg.g, t_bg.b, 0.93)
		psb.set_corner_radius_all(22)
		psb.set_content_margin_all(0)
		_panel.add_theme_stylebox_override("panel", psb)
	# BottomNavBar — mettre à jour les couleurs selon le thème
	var nav := find_child("BottomNavBar", true, false) as PanelContainer
	if is_instance_valid(nav):
		var t2 := UI_Theme.current()
		var nav_bg := t2["bg"] as Color
		var nav_sb := StyleBoxFlat.new()
		nav_sb.bg_color = Color(nav_bg.r * 0.85, nav_bg.g * 0.85, nav_bg.b * 0.9, 0.96)
		nav_sb.border_width_top = 1
		nav_sb.border_color = Color(UI_Theme.accent_color(), 0.22)
		nav_sb.corner_radius_top_left = 18; nav_sb.corner_radius_top_right = 18
		nav.add_theme_stylebox_override("panel", nav_sb)
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
	if OS.has_feature("android"):
		var granted := OS.get_granted_permissions().has("android.permission.CAMERA")
		if not granted:
			OS.request_permission("android.permission.CAMERA")
			add_log("📷 Autorisez la caméra dans la popup, puis retappez 📷.")
			return
		# Permission accordée MAIS aucun feed (accordé en cours de session → restart requis)
		if CameraServer.feeds().size() == 0:
			add_log("📷 Redémarrez l'application pour activer la caméra (permission accordée).")
			_show_toast("🔄 Redémarrage requis pour la caméra")
			return
	_close_panel()
	if OS.has_feature("web"):
		# Caméra Web : sélecteur de fichier natif → FileReader → callback GDScript
		JavaScriptBridge.eval("""
(function() {
    var input = document.createElement('input');
    input.type = 'file';
    input.accept = 'image/*';
    input.capture = 'environment';
    input.onchange = function(e) {
        var file = e.target.files[0];
        if (!file) return;
        var reader = new FileReader();
        reader.onload = function(ev) {
            var img = new Image();
            img.onload = function() {
                var canvas = document.createElement('canvas');
                var max_size = 1080;
                var scale = Math.min(max_size / img.width, max_size / img.height, 1.0);
                canvas.width = Math.round(img.width * scale);
                canvas.height = Math.round(img.height * scale);
                canvas.getContext('2d').drawImage(img, 0, 0, canvas.width, canvas.height);
                var b64 = canvas.toDataURL('image/jpeg', 0.82).split(',')[1];
                if (window._godotPhotoCb) window._godotPhotoCb([b64]);
            };
            img.src = ev.target.result;
        };
        reader.readAsDataURL(file);
    };
    input.click();
})();
""")
		return
	var feed_tex := Spacememory_Vision.get_feed_texture()
	if feed_tex == null:
		# Pas de caméra native — on affiche un message mais le mode AR fil-de-fer se lance quand même
		add_log("📷 Pas de caméra — mode Vision Quantique (fil de fer + memories flottantes)")
		emit_signal("ar_toggled", true)  # lance le rendu 3D AR sans fond caméra
		return
	viewfinder.texture = feed_tex
	viewfinder.move_to_front()
	viewfinder.show()

func _on_web_photo_received(args: Array):
	if args.is_empty(): return
	var b64 := str(args[0])
	var raw := Marshalls.base64_to_raw(b64)
	var img := Image.new()
	if img.load_png_from_buffer(raw) != OK:
		if img.load_jpg_from_buffer(raw) != OK:
			add_log("❌ Format photo non reconnu (ni PNG ni JPEG)")
			return
	_web_capture_tex = ImageTexture.create_from_image(img)
	if _web_capture_tex == null: add_log("❌ Conversion image échouée"); return
	viewfinder.texture = _web_capture_tex
	viewfinder.show()
	add_log("📸 Photo chargée — appuyez sur 🔴 CAPTURER pour fixer l'empreinte.")

func _do_capture():
	if _web_capture_tex != null:
		var lat := SpaceTime_Manager.current_gps.x
		var lon := SpaceTime_Manager.current_gps.y
		# save_web_snapshot persiste le thumb sur disque AVANT d'émettre snapshot_taken
		# (le lazy loader de World_3D a besoin du thumb_path pour recharger après unload)
		Spacememory_Vision.save_web_snapshot(_web_capture_tex, lat, lon)
		_web_capture_tex = null
	else:
		Spacememory_Vision.take_real_snapshot()
	_close_camera()
	add_log("📸 Empreinte spatio-temporelle fixée !")

func _close_camera():
	viewfinder.hide()
	_web_capture_tex = null
	if Spacememory_Vision.camera_feed: Spacememory_Vision.camera_feed.set_active(false)

func _on_ar_toggled(pressed: bool):
	_ar_active = pressed
	if pressed:
		_close_panel()
		# Demander la permission gyroscope iOS depuis ce geste utilisateur direct
		# (Safari/Chrome refusent si appelé depuis _ready ou un timer)
		if Spacememory_Vision.has_method("request_web_permissions"):
			Spacememory_Vision.request_web_permissions()
	# En AR : masquer fond + TopBar + BottomNavBar pour une vue caméra immersive
	var bg_rect := find_child("ThemeBgRect", true, false) as ColorRect
	if bg_rect: bg_rect.visible = not pressed
	var nav_bar := find_child("BottomNavBar", true, false)
	var tw_ui := create_tween()
	for el in [$TopBar, nav_bar]:
		if is_instance_valid(el):
			tw_ui.parallel().tween_property(el, "modulate:a", 0.0 if pressed else 1.0, 0.3)
			(el as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE if pressed else Control.MOUSE_FILTER_STOP
	var btn := $BottomBar.find_child("ARBtn", true, false) as Button
	if btn:
		var sb := StyleBoxFlat.new()
		if pressed:
			sb.bg_color = Color(UI_Theme.accent_color(), 0.35); sb.set_corner_radius_all(8)
			btn.add_theme_stylebox_override("normal", sb)
		else:
			btn.remove_theme_stylebox_override("normal")
	emit_signal("ar_toggled", pressed)
	if pressed and CameraServer.feeds().size() == 0 and OS.has_feature("web"):
		_on_photo_pressed()

func _show_gallery_popup():
	var memories := Spacememory_Vision.load_memories()
	var popup := PanelContainer.new()
	popup.name = "GalleryPopup"
	popup.set_anchors_preset(PRESET_FULL_RECT)
	popup.add_theme_stylebox_override("panel", UI_Theme.make_panel_style(0.97))
	add_child(popup); popup.move_to_front()

	var m := MarginContainer.new()
	for side in ["margin_left","margin_right","margin_top","margin_bottom"]:
		m.add_theme_constant_override(side, 20)
	popup.add_child(m)

	var pv := VBoxContainer.new(); pv.add_theme_constant_override("separation", 12); m.add_child(pv)
	_lbl_title(pv, "🗂 SPACEMEMORY — GALERIE", 20, UI_Theme.accent_color())

	var scroll := ScrollContainer.new()
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.custom_minimum_size = Vector2(0, 400); scroll.size_flags_vertical = SIZE_EXPAND_FILL
	pv.add_child(scroll)
	var sv := VBoxContainer.new(); sv.add_theme_constant_override("separation", 10)
	sv.size_flags_horizontal = SIZE_EXPAND_FILL; scroll.add_child(sv)

	if memories.is_empty():
		_lbl(sv, "Aucune photo ancrée dans l'espace.\nCapturez un souvenir depuis le bouton 📷.", 14, UI_Theme.text_secondary())
	else:
		# Tri antichronologique
		memories.sort_custom(func(a, b): return a.get("ts", 0) > b.get("ts", 0))
		for mem in memories:
			var row := PanelContainer.new()
			row.add_theme_stylebox_override("panel", UI_Theme.make_panel_style(0.22))
			sv.add_child(row)
			var rhb := HBoxContainer.new(); rhb.add_theme_constant_override("separation", 12); row.add_child(rhb)

			# Vignette — charge la miniature pré-calculée (256px) pas la photo pleine résolution
			var thumb_path: String = mem.get("thumb", "")
			if thumb_path == "": thumb_path = mem.get("path", "")
			if thumb_path != "" and FileAccess.file_exists(thumb_path):
				var img := Image.new()
				if img.load(thumb_path) == OK:
					var tr := TextureRect.new()
					tr.texture = ImageTexture.create_from_image(img)
					tr.custom_minimum_size = Vector2(80, 60)
					tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
					rhb.add_child(tr)

			var meta_v := VBoxContainer.new(); meta_v.size_flags_horizontal = SIZE_EXPAND_FILL; rhb.add_child(meta_v)
			var ts: int = mem.get("ts", 0)
			var dt := Time.get_datetime_dict_from_unix_time(ts)
			_lbl(meta_v, "%04d-%02d-%02d %02d:%02d" % [dt.year,dt.month,dt.day,dt.hour,dt.minute], 13)
			_lbl(meta_v, "📍 %.4f, %.4f" % [mem.get("lat",0.0), mem.get("lon",0.0)], 12, UI_Theme.text_secondary())
			# Bouton suppression
			var btn_del := Button.new()
			btn_del.text = "🗑"
			btn_del.flat = true
			btn_del.custom_minimum_size = Vector2(44, 44)
			btn_del.add_theme_font_size_override("font_size", UI_Theme._get_scaled_size(20))
			btn_del.modulate = Color(1.0, 0.3, 0.3)
			var ts_capture := ts  # capture pour la closure
			btn_del.connect("pressed", func():
				Spacememory_Vision.delete_memory(ts_capture)
				row.queue_free()
				add_log("🗑 Empreinte supprimée."))
			rhb.add_child(btn_del)

	var btn_close := Button.new(); btn_close.text = "✕ FERMER"
	btn_close.custom_minimum_size = Vector2(0, 48); btn_close.add_theme_font_size_override("font_size", UI_Theme._get_scaled_size(16))
	btn_close.connect("pressed", Callable(popup, "queue_free"))
	pv.add_child(btn_close)

func _show_aide():
	# Toggle : si déjà ouvert → ferme
	var existing := find_child("AideScreenNode", true, false)
	if is_instance_valid(existing): existing.queue_free(); return

	# Popup plein écran identique à _show_gallery_popup() — pattern éprouvé
	var popup := PanelContainer.new()
	popup.name = "AideScreenNode"
	popup.set_anchors_preset(PRESET_FULL_RECT)
	popup.add_theme_stylebox_override("panel", UI_Theme.make_panel_style(0.97))
	popup.z_index = 92
	add_child(popup); popup.move_to_front()

	var m := MarginContainer.new()
	for side in ["margin_left","margin_right","margin_top","margin_bottom"]:
		m.add_theme_constant_override(side, 20)
	popup.add_child(m)

	var pv := VBoxContainer.new(); pv.add_theme_constant_override("separation", 14); m.add_child(pv)

	_lbl_title(pv, "⚛ ATOM4LOVE — Guide & Contexte", 20, UI_Theme.accent_color())

	var scroll := ScrollContainer.new()
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	pv.add_child(scroll)
	var sv := VBoxContainer.new(); sv.add_theme_constant_override("separation", 16)
	sv.size_flags_horizontal = SIZE_EXPAND_FILL; scroll.add_child(sv)

	# Instancier AideScreen.gd pour accéder à _build_content(vbox)
	var aide_script := load("res://scripts/AideScreen.gd")
	if aide_script:
		var aide_instance := (aide_script as GDScript).new()
		if aide_instance.has_method("_build_content"):
			aide_instance._build_content(sv)
		else:
			_aide_content_inline(sv)
	else:
		_aide_content_inline(sv)

	var btn_close := Button.new(); btn_close.text = "✕ FERMER"
	btn_close.custom_minimum_size = Vector2(0, 52)
	btn_close.add_theme_font_size_override("font_size", UI_Theme._get_scaled_size(16))
	btn_close.connect("pressed", Callable(popup, "queue_free"))
	pv.add_child(btn_close)

func _aide_content_inline(parent: VBoxContainer):
	var sections := [
		["🌟 Votre identité est dans les étoiles",
		 "ATOM4LOVE ne stocke aucune biométrie. Votre MULTIPASS est calculé depuis votre empreinte cosmique de naissance (date, heure, lieu, poids). Si vous perdez votre téléphone, ressaisissez vos données de naissance et retrouvez votre identité."],
		["👤 PROFIL — Créer son MULTIPASS",
		 "Entrez votre date, heure, lieu et poids de naissance. Vos clés cryptographiques sont dérivées de façon déterministe — reproductibles sur n'importe quel appareil.\n\nφ_i = votre phase personnelle dans le champ harmonique terrestre."],
		["🔬 MATCH — Calculateur de Résonance",
		 "k = 1/(1+|sin(Δφ)|) mesure l'alignement de phase.\n• k > 0.95 → Singularité optique (accord parfait)\n• k > 0.85 → Haute cohérence\n• k = 0.5 → Dissonance maximale"],
		["📡 RADAR LOCA — Scanner",
		 "Diffuse votre signature φ_i via WiFi (SSID A4L-*). Mode Hot/Cold : les vibrations vous guident vers la résonance maximale. Plus k approche 1.0, plus les vibrations s'accélèrent (effet compteur Geiger)."],
		["🔮 CABINE-33 — Rituel de Phase",
		 "Approchez-vous à moins de 50m du centre d'un hexagone et restez immobile 33 secondes. L'anneau de progression s'affiche. La grille hexagonale s'illumine progressivement. À la complétion, votre Spacememory locale se déverrouille."],
		["🌍 RÉSEAU & Spacememory",
		 "Vos pensées géolocalisées (Kind 1 NOSTR avec tag a4l:) sont lues par les autres atomes ayant visité le même nœud hexagonal. Chaque nœud est une mémoire collective locale."],
		["🎙️ Instrument Cosmique",
		 "Enregistrez 1 seconde de voix (\"Aaaa\" ou \"Ommm\"). Votre timbre sera accordé sur votre fréquence biologique ω_bio. En mode LOCA avec d'autres atomes, vos téléphones jouent une symphonie collective."],
		["🤝 G1FabLab & UPlanet",
		 "Projet coopératif · AGPL-3.0 · opencollective.com/monnaie-libre\nBudget transparent · Zéro investisseur · Infrastructure décentralisée IPFS + NOSTR + Ğ1"],
	]
	for sec in sections:
		var panel := UI_Theme.add_panel_vbox(parent)
		var title := Label.new()
		title.text = sec[0]
		title.add_theme_font_size_override("font_size", UI_Theme._get_scaled_size(15))
		title.modulate = UI_Theme.accent_color()
		title.autowrap_mode = TextServer.AUTOWRAP_WORD
		panel.add_child(title)
		var body := Label.new()
		body.text = sec[1]
		body.add_theme_font_size_override("font_size", UI_Theme._get_scaled_size(13))
		body.modulate = UI_Theme.text_color()
		body.autowrap_mode = TextServer.AUTOWRAP_WORD
		panel.add_child(body)

func _on_sync_pressed():
	add_log("🔄 Synchronisation avec le relais…"); sync_btn.disabled = true
	# Ne PAS purger avant la confirmation réseau — lecture seule du cache
	var thoughts_to_send := Thought_Cache.local_thoughts.duplicate()

	if thoughts_to_send.size() == 0:
		add_log("Le cache quantique est vide.")
		sync_btn.disabled = false
		return

	if Nostr_Identity._ws.is_empty():
		add_log("⚠ Aucun relais connecté — données conservées en local.")
		sync_btn.disabled = false
		return

	for thought in thoughts_to_send:
		var content = thought["text"] if thought.has("text") else ""
		if thought.has("media_path"):
			content += "\n[Média local en attente d'Astroport : %s]" % thought["media_path"]
		var loc = thought.get("location", {})
		var ev = Nostr_Identity.make_event(1, content, [
			["l", str(loc.get("lat", 0.0)) + "," + str(loc.get("lon", 0.0)), "GPS"]
		])
		Nostr_Identity.sign_and_send(ev)

	# Purge APRÈS envoi réussi (les événements sont dans la file NOSTR)
	Thought_Cache.purge_to_spacememory()
	UPlanet_API.sync_with_relay(Player_Origin.user_npub)

# ─────────────────────────────────────────────────────────────
# HELPERS
# ─────────────────────────────────────────────────────────────

func _find_in_tab(tab: int, node_name: String) -> Node:
	if tab >= _tab_pages.size(): return null
	return _tab_pages[tab].find_child(node_name, true, false)

# _k_col et _k_hex supprimés — utiliser UI_Theme.k_color(k) (source unique)

# ─────────────────────────────────────────────────────────────
# PARTAGE VIRAL — Web Share API
# ─────────────────────────────────────────────────────────────

func _on_share_resonance_link():
	if not Player_Origin.is_initialized:
		add_log("⚠ Créez votre MULTIPASS pour partager votre lien de résonance."); return
	var my_npub := Player_Origin.user_npub
	if my_npub.is_empty() or my_npub == "npub1_anonyme":
		add_log("⚠ Forgez un vrai MULTIPASS pour partager votre résonance cosmique."); return
	# Lien = téléchargement APK + npub en texte (page web atom4love?match= n'existe pas encore)
	var apk_link := "https://u.copylaradio.com/apk/atom4love.apk"
	var my_kin := 0
	if Player_Origin.birth_unix > 0:
		var kd: Dictionary = Kin_Maya.calc_kin_unix(Player_Origin.birth_unix)
		my_kin = kd.get("kin", 0)
	var text := "⚛ ATOM4LOVE — Testez notre résonance φ !\n"
	text += "Mon KIN Maya : %d | Mon NPUB : %s\n" % [my_kin, my_npub.substr(0, 20) + "…"]
	text += "Téléchargez l'app : " + apk_link
	if OS.has_feature("web"):
		var js := """
		(function() {
			var t = %s, u = '%s';
			if (navigator.share) {
				navigator.share({ title: 'ATOM4LOVE', text: t, url: u }).catch(function(e){ console.error(e); });
			} else {
				navigator.clipboard.writeText(t).then(function(){
					alert('Message copié dans le presse-papier !');
				}).catch(function(){ alert(t); });
			}
		})();
		""" % [JSON.stringify(text), apk_link]
		JavaScriptBridge.eval(js)
	elif OS.has_feature("android"):
		# Android : Intent de partage natif via OS.shell_open ne fonctionne pas pour partage texte
		# Utiliser le clipboard + toast
		DisplayServer.clipboard_set(text)
		_show_toast("🔗 Message copié — colle-le dans ton app préférée !")
		add_log("📋 Lien APK + KIN copié dans le presse-papier.")
	else:
		DisplayServer.clipboard_set(text)
		_show_toast("🔗 Copié !")


func _on_copy_ssid(lbl: Label):
	var ssid := lbl.text
	if ssid == "" or "Configurez" in ssid: return
	DisplayServer.clipboard_set(ssid)
	_show_toast("📋 SSID copié !")

# ─────────────────────────────────────────────────────────────
# CARTE COSMIQUE — Export screenshot
# ─────────────────────────────────────────────────────────────

func _export_cosmic_card():
	# Masquer l'UI pour un rendu propre (animation 3D + Kin en fond)
	var nav_bar := find_child("BottomNavBar", true, false)
	$TopBar.hide(); $BottomBar.hide(); $HUDCenter.hide()
	if is_instance_valid(nav_bar): nav_bar.hide()
	if is_instance_valid(_panel) and _panel_open: _panel.hide()
	await get_tree().process_frame
	await get_tree().process_frame

	var img := get_viewport().get_texture().get_image()

	$TopBar.show(); $BottomBar.show(); $HUDCenter.show()
	if is_instance_valid(nav_bar): nav_bar.show()
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
		_show_toast("📸 Carte sauvegardée !")

# ─────────────────────────────────────────────────────────────
# CABINE-33 — Rituel de la faille
# ─────────────────────────────────────────────────────────────

const OC_URL := "https://opencollective.com/monnaie-libre/contribute"

func _show_cooperative_invite():
	# Invitation à rejoindre la coopérative G1FabLab
	# Affiché après la création du MULTIPASS — engagement maximal
	var popup := PanelContainer.new()
	popup.set_anchors_preset(PRESET_CENTER)
	popup.offset_left = -300; popup.offset_right = 300
	popup.offset_top = -240; popup.offset_bottom = 240
	popup.add_theme_stylebox_override("panel", UI_Theme.make_panel_style(0.97))
	add_child(popup); popup.move_to_front()

	var m := MarginContainer.new()
	for side in ["margin_left","margin_right","margin_top","margin_bottom"]:
		m.add_theme_constant_override(side, UI_Theme.scale_px(24))
	popup.add_child(m)

	var vb := VBoxContainer.new(); vb.add_theme_constant_override("separation", UI_Theme.scale_px(16)); m.add_child(vb)

	var title := Label.new()
	title.text = "🤝 Rejoindre G1FabLab · UPlanet ẐEN"
	title.add_theme_font_size_override("font_size", UI_Theme._get_scaled_size(22))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.modulate = UI_Theme.accent_color(); vb.add_child(title)

	var body := Label.new()
	body.text = (
		"Votre MULTIPASS est forgé. Vous faites maintenant partie du réseau UPlanet.\n\n"
		+ "La Monnaie Libre Ğ1 est la monnaie coopérative qui alimente ce réseau. "
		+ "En rejoignant OpenCollective, vous participez aux décisions de la coopérative, "
		+ "soutenez le développement et accédez aux activités collectives.\n\n"
		+ "Votre MULTIPASS est votre clé — créé à partir de votre propre empreinte cosmique."
	)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD
	body.add_theme_font_size_override("font_size", UI_Theme._get_scaled_size(14))
	body.modulate = UI_Theme.text_color(); vb.add_child(body)

	var url_lbl := Label.new()
	url_lbl.text = OC_URL
	url_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	url_lbl.add_theme_font_size_override("font_size", UI_Theme._get_scaled_size(13))
	url_lbl.modulate = UI_Theme.bar_color(false); vb.add_child(url_lbl)

	var btn_join := UI_Theme.add_styled_button(vb, "🌍 REJOINDRE G1FabLab · UPlanet ẐEN",
		func(): OS.shell_open(OC_URL); popup.queue_free(), true)
	btn_join.custom_minimum_size.y = UI_Theme.scale_px(68)

	UI_Theme.add_styled_button(vb, "Plus tard", Callable(popup, "queue_free"), false)

func _trigger_cabine_ritual():
	add_log("🔮 Nœud PHI atteint — La faille s'ouvre…")
	UI_Theme.vibrate(800)
	# Glitch de l'écran via le shader d'interférence
	# Incrémenter l'ID pour annuler tout timer d'interférence précédent (rencontre ou rituel)
	_interference_hide_id += 1
	var my_id := _interference_hide_id
	if is_instance_valid(interference_rect):
		interference_rect.show()
	get_tree().create_timer(5.0).timeout.connect(func():
		if is_instance_valid(interference_rect) and my_id == _interference_hide_id:
			interference_rect.hide()
	, CONNECT_ONE_SHOT)
	# Tween : flash rougeoyant + disparition progressive
	var glitch_rect = ColorRect.new()
	glitch_rect.set_anchors_preset(PRESET_FULL_RECT)
	glitch_rect.color = Color(0.8, 0.0, 0.3, 0.0)
	glitch_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glitch_rect.z_index = 90
	add_child(glitch_rect); glitch_rect.move_to_front()
	var gtw := create_tween().bind_node(glitch_rect)
	gtw.tween_property(glitch_rect, "color:a", 0.45, 0.18)
	gtw.tween_property(glitch_rect, "color:a", 0.0, 0.18)
	gtw.tween_property(glitch_rect, "color:a", 0.35, 0.12)
	gtw.tween_property(glitch_rect, "color:a", 0.0, 0.8)
	gtw.tween_callback(glitch_rect.queue_free)
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
	lbl.add_theme_font_size_override("font_size", UI_Theme._get_scaled_size(26))
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
	if "family=" in qs:
		var parts := qs.split("family=")
		if parts.size() >= 2:
			var child_npub := parts[1].split("&")[0].strip_edges()
			add_log("🧬 Bienvenue ! Un atome de votre descendance (%s…) a besoin de vos mémoires." % child_npub.substr(0, 10))
			if not Player_Origin.is_initialized:
				_pending_deeplink_tab = TAB_PROFIL
			else:
				await get_tree().process_frame
				_open_panel(TAB_PROFIL)
	elif "match=" in qs:
		var parts := qs.split("match=")
		if parts.size() >= 2:
			_deeplink_match_npub = parts[1].split("&")[0].strip_edges()
			add_log("🔗 Invitation reçue : " + _deeplink_match_npub.substr(0, 20) + "…")
			if not Player_Origin.is_initialized:
				_pending_deeplink_tab = TAB_MATCH
			else:
				await get_tree().process_frame
				_open_panel(TAB_MATCH)

# ─────────────────────────────────────────────────────────────
# HOOK SCREEN — Signal reçu depuis HookScreen.tscn
# ─────────────────────────────────────────────────────────────

func _on_hook_completed(data: Dictionary):
	var b_unix: int = data.get("birth_unix", 0)
	var sex: int    = data.get("sex", 0)
	var blat: float = data.get("birth_lat", 0.0)
	var blon: float = data.get("birth_lon", 0.0)
	if blat != 0.0 or blon != 0.0:
		Player_Origin.birth_lat = blat
		Player_Origin.birth_lon = blon
	Player_Origin.biological_sex = sex  # propagé immédiatement pour omega_bio correct avant MULTIPASS
	# Restaurer l'UI principale masquée pendant l'onboarding
	$TopBar.show()
	$HUDCenter.show()
	$BottomBar.show()
	var _nav := find_child("BottomNavBar", true, false)
	if _nav: _nav.show()
	if data.get("action", "") == "forge":
		if is_instance_valid(_tab_profil): 
			_tab_profil.prefill_from_hook(data)
			_rebuild_tab(TAB_PROFIL)
		if is_instance_valid(_hook_overlay): 
			_hook_overlay.queue_free(); 
			_hook_overlay = null
		var _ka := Kin_Maya.calc_kin_unix(b_unix)
		var _anim := find_child("AtomAnimation", true, false) as Node2D
		if _anim and _anim.has_method("set_kin"): _anim.set_kin(_ka, {})
		_update_cached_lfo_hz()
		if _pending_deeplink_tab != -1:
			_open_panel(_pending_deeplink_tab); _pending_deeplink_tab = -1
		else:
			_open_panel(TAB_PROFIL)

# ─────────────────────────────────────────────────────────────
# QR APK P2P — Partage sans Internet
# ─────────────────────────────────────────────────────────────

func _show_apk_qr_popup(url: String):
	var popup = PanelContainer.new()
	popup.name = "ApkQrPopup"
	popup.set_anchors_preset(PRESET_FULL_RECT)
	popup.add_theme_stylebox_override("panel", UI_Theme.make_panel_style(0.97))
	add_child(popup); popup.move_to_front()
	var m = MarginContainer.new()
	for side in ["margin_left","margin_right","margin_top","margin_bottom"]:
		m.add_theme_constant_override(side, 24)
	popup.add_child(m)
	var pv = VBoxContainer.new(); pv.add_theme_constant_override("separation", 14); m.add_child(pv)
	_lbl_title(pv, "📲 INVITER UN AMI SUR ATOM4LOVE", 20, UI_Theme.accent_color())

	# Étapes explicites — l'utilisateur sait exactement quoi faire
	var ssid_now := Loca_Scanner.build_broadcast_ssid()
	var steps_lbl := Label.new()
	steps_lbl.text = (
		"1️⃣  Activez le Partage WiFi (hotspot) sur votre téléphone.\n"
		+ "2️⃣  Donnez ce nom de réseau à votre ami :\n"
		+ "         " + ssid_now + "\n"
		+ "3️⃣  Votre ami se connecte à ce WiFi, puis flashe le QR ci-dessous.\n"
		+ "4️⃣  Il télécharge l'APK et rejoint ATOM4LOVE !"
	)
	steps_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	steps_lbl.add_theme_font_size_override("font_size", UI_Theme._get_scaled_size(13))
	steps_lbl.modulate = UI_Theme.text_color()
	pv.add_child(steps_lbl)
	var img_rect = TextureRect.new()
	img_rect.name = "ApkQRRect"
	img_rect.custom_minimum_size = Vector2(320, 320)
	img_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	img_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pv.add_child(img_rect)
	var gen_lbl = Label.new(); gen_lbl.text = "⏳ Génération QR…"
	gen_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; pv.add_child(gen_lbl)
	# Bouton copier le SSID pour faciliter la saisie chez l'ami
	var ssid_copy_row := HBoxContainer.new(); ssid_copy_row.add_theme_constant_override("separation", 8)
	pv.add_child(ssid_copy_row)
	var ssid_lbl_copy := Label.new()
	ssid_lbl_copy.text = url; ssid_lbl_copy.add_theme_font_size_override("font_size", UI_Theme._get_scaled_size(11))
	ssid_lbl_copy.modulate = UI_Theme.bar_color(false); ssid_lbl_copy.size_flags_horizontal = SIZE_EXPAND_FILL
	ssid_lbl_copy.autowrap_mode = TextServer.AUTOWRAP_WORD; ssid_copy_row.add_child(ssid_lbl_copy)
	var btn_copy_url := Button.new(); btn_copy_url.text = "📋"
	btn_copy_url.custom_minimum_size = Vector2(44, 44)
	btn_copy_url.connect("pressed", func():
		DisplayServer.clipboard_set(url)
		add_log("📋 URL copiée : " + url))
	ssid_copy_row.add_child(btn_copy_url)

	var btn_c = Button.new(); btn_c.text = "✕ FERMER  (serveur actif tant que nécessaire)"
	btn_c.custom_minimum_size = Vector2(0, 52)
	btn_c.add_theme_font_size_override("font_size", UI_Theme._get_scaled_size(14))
	# Fermer le QR ne stoppe PAS le serveur — le téléchargement de l'ami est en cours
	# L'utilisateur arrête le serveur via "⏹ ARRÊTER PARTAGE" dans l'onglet SCAN
	btn_c.connect("pressed", Callable(popup, "queue_free"))
	pv.add_child(btn_c)
	# Génération QR en thread pour éviter le freeze (100-300ms sur mobile)
	var url_cap: String = url
	var ir_cap: TextureRect = img_rect
	var gl_cap: Label = gen_lbl
	WorkerThreadPool.add_task(func():
		var img := QR_Generator.generate(url_cap, 8)
		call_deferred("_on_apk_qr_ready", img, ir_cap, gl_cap)
	)

func _on_apk_qr_ready(img: Image, img_rect: TextureRect, gen_lbl: Label):
	var tex := ImageTexture.create_from_image(img)
	if is_instance_valid(img_rect): img_rect.texture = tex
	if is_instance_valid(gen_lbl): gen_lbl.queue_free()

# ─────────────────────────────────────────────────────────────
# uDRIVE — Callbacks signaux UPlanet_API (upload géré par TabReseau)
# ─────────────────────────────────────────────────────────────

func _on_udrive_uploaded(filename: String, _cid: String) -> void:
	# Succès : vider le cache pensées si c'était un sync
	if filename.begins_with("spacememory_"):
		Thought_Cache.clear_cache()
		var lbl := _find_in_tab(TAB_RESEAU, "CacheCountLabel") as Label
		if lbl: lbl.text = "💭 Cache vidé — synchronisation réussie"
		var btn := _find_in_tab(TAB_RESEAU, "SyncThoughtsBtn") as Button
		if btn: btn.disabled = true
	_udrive_status("✅ %s dans votre uDRIVE" % filename)

func _on_udrive_roaming() -> void:
	_udrive_status("⚠️ Vous êtes en roaming.\nConnectez-vous à votre station d'origine pour synchroniser.")

func _udrive_status(msg: String) -> void:
	var lbl := _find_in_tab(TAB_RESEAU, "UDriveStatus") as Label
	if lbl: lbl.text = msg
	add_log(msg)

func _udrive_mime(fname: String) -> String:
	match fname.get_extension().to_lower():
		"jpg", "jpeg": return "image/jpeg"
		"png":         return "image/png"
		"mp4", "mov":  return "video/mp4"
		"mp3":         return "audio/mpeg"
		"pdf":         return "application/pdf"
		"json":        return "application/json"
		"txt":         return "text/plain"
		_:             return "application/octet-stream"

# ─────────────────────────────────────────────────────────────
# Power Score — fetch indicatif depuis la station (12345 JSON)
# ─────────────────────────────────────────────────────────────

func _fetch_station_power_score() -> void:
	var lbl := _find_in_tab(TAB_RESEAU, "PowerScoreLabel") as Label
	if not lbl: return
	# L'endpoint 12345 expose capacities.power_score
	var station_url := UPlanet_API.base_url.replace(":54321", ":12345").replace("/api", "")
	var http := HTTPRequest.new(); http.timeout = 8.0; add_child(http)
	var err := http.request(station_url + "/", [], HTTPClient.METHOD_GET, "")
	if err != OK: lbl.text = "Station inaccessible"; http.queue_free(); return
	var result: Array = await http.request_completed
	http.queue_free()
	if result[1] != 200: lbl.text = "Station inaccessible"; return
	var j := JSON.new()
	if j.parse((result[3] as PackedByteArray).get_string_from_utf8()) != OK:
		lbl.text = "Données station illisibles"; return
	var caps: Dictionary = (j.data as Dictionary).get("capacities", {})
	var score: float = caps.get("power_score", 0.0)
	var tier := "🌿 Light" if score < 11 else ("⚡ Standard" if score < 41 else "🔥 Brain")
	var ai_ready: bool = caps.get("provider_ready", false)
	lbl.text = "Power Score : %.0f  %s%s" % [score, tier, "  · IA disponible" if ai_ready else ""]
	lbl.modulate = Color(0.4, 1.0, 0.6) if score >= 41 else Color(0.8, 0.8, 0.8)

# ─────────────────────────────────────────────────────────────

func add_log(msg: String):
	log_text.text += "\n[%s] %s" % [Time.get_time_string_from_system(), msg]
	var il = _find_in_tab(TAB_RESEAU, "InlineLog") as RichTextLabel
	if il: il.text = log_text.text
