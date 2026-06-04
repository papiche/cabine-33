class_name TabScan
extends VBoxContainer

signal log_requested(msg: String)
signal toast_requested(msg: String)
signal scan_toggle_requested      # Main_UI gère _synth_player au démarrage du scan
signal haptic_requested(k: float) # Main_UI gère vibration + audio

# Widgets publics référencés depuis Main_UI pour les mises à jour temps-réel
var resonance_bar: ProgressBar       = null
var nearby_list: RichTextLabel       = null
var scan_btn: Button                 = null
var ssid_lbl: Label                  = null
var hotcold_indicator: ColorRect     = null
var hotcold_arrow_lbl: Label         = null
var hotcold_k_lbl: Label             = null
var hotcold_target_npub: String      = ""
var _hotcold_prev_k: float           = 0.0

func build():
	for child in get_children(): child.queue_free()
	resonance_bar = null; nearby_list = null; scan_btn = null; ssid_lbl = null
	hotcold_indicator = null; hotcold_arrow_lbl = null; hotcold_k_lbl = null
	_hotcold_prev_k = 0.0  # reset à chaque rebuild pour éviter la flèche stale

	# ── LOCA scanner ────────────────────────────────────────────────────────────
	UI_Theme.add_section_title(self, "📡 SCANNER LOCA")
	var hint := Label.new()
	hint.text = "Détecte les personnes proches partageant ATOM4LOVE. Activez le scan et approchez-vous."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD
	hint.add_theme_font_size_override("font_size", UI_Theme._get_scaled_size(13))
	hint.modulate = UI_Theme.text_hint(); add_child(hint)

	UI_Theme.add_label(self, "Taux de Résonance k :", 14)
	resonance_bar = ProgressBar.new(); resonance_bar.max_value = 1.0
	resonance_bar.custom_minimum_size = Vector2(0, 26)
	var rb_sb := StyleBoxFlat.new(); rb_sb.bg_color = Color(0.2, 0.9, 0.5); rb_sb.set_corner_radius_all(4)
	resonance_bar.add_theme_stylebox_override("fill", rb_sb); add_child(resonance_bar)

	# ── Bouton SCANNER (pleine largeur) ─────────────────────────────────────────
	scan_btn = Button.new(); scan_btn.text = "▶ SCANNER"
	scan_btn.custom_minimum_size = Vector2(0, 60)
	scan_btn.size_flags_horizontal = SIZE_EXPAND_FILL
	scan_btn.add_theme_font_size_override("font_size", UI_Theme._get_scaled_size(18))
	scan_btn.connect("pressed", func(): emit_signal("scan_toggle_requested")); add_child(scan_btn)

	# ── Bouton PARTAGER APK (ligne séparée, bien visible) ────────────────────────
	add_child(HSeparator.new())
	var apk_lbl := Label.new()
	apk_lbl.text = "📲 Partagez le nom WiFi ci-dessous et l'APK — vos amis vous détecteront automatiquement."
	apk_lbl.add_theme_font_size_override("font_size", UI_Theme._get_scaled_size(12))
	apk_lbl.modulate = UI_Theme.text_hint(); apk_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD; add_child(apk_lbl)
	var btn_share := Button.new(); btn_share.name = "ShareApkBtn"
	btn_share.custom_minimum_size = Vector2(0, 56)
	btn_share.size_flags_horizontal = SIZE_EXPAND_FILL
	btn_share.add_theme_font_size_override("font_size", UI_Theme._get_scaled_size(15))
	if not OS.has_feature("web"):
		# État initial : serveur déjà actif ou non
		btn_share.text = "⏹ ARRÊTER PARTAGE" if Loca_Scanner._apk_server_active else "📲 PARTAGER ATOM4LOVE"
		btn_share.connect("pressed", func():
			if Loca_Scanner._apk_server_active:
				Loca_Scanner.stop_apk_server()
				var b := find_child("ShareApkBtn", true, false) as Button
				if b: b.text = "📲 PARTAGER ATOM4LOVE"
			else:
				Loca_Scanner.start_apk_server()
				var b := find_child("ShareApkBtn", true, false) as Button
				if b: b.text = "⏹ ARRÊTER PARTAGE")
	else:
		btn_share.text = "📲 Partager le lien (Web)"
		btn_share.connect("pressed", func():
			if OS.has_feature("web"):
				JavaScriptBridge.eval("navigator.share ? navigator.share({title:'ATOM4LOVE',url:'https://u.copylaradio.com/apk/atom4love.apk'}) : navigator.clipboard.writeText('https://u.copylaradio.com/apk/atom4love.apk')")
			emit_signal("toast_requested", "🔗 Lien copié : u.copylaradio.com/apk/atom4love.apk"))
	add_child(btn_share)
	add_child(HSeparator.new())

	ssid_lbl = Label.new()
	# Afficher immédiatement le SSID si le scan est déjà actif (rebuild après navigation)
	ssid_lbl.text = ("SSID : " + Loca_Scanner.build_broadcast_ssid()) if Loca_Scanner.is_scanning else "SSID : —"
	ssid_lbl.add_theme_font_size_override("font_size", UI_Theme._get_scaled_size(13))
	ssid_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ssid_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD; add_child(ssid_lbl)

	var ssid_pc := PanelContainer.new()
	ssid_pc.add_theme_stylebox_override("panel", UI_Theme.make_panel_style(0.18)); add_child(ssid_pc)
	var ssid_hv := VBoxContainer.new(); ssid_hv.add_theme_constant_override("separation", 6); ssid_pc.add_child(ssid_hv)
	var ssid_hint := Label.new()
	ssid_hint.text = "💡 Renommage manuel du partage WiFi si l'OS bloque la modif automatique :"
	ssid_hint.autowrap_mode = TextServer.AUTOWRAP_WORD
	ssid_hint.add_theme_font_size_override("font_size", UI_Theme._get_scaled_size(13))
	ssid_hint.modulate = UI_Theme.text_secondary(); ssid_hv.add_child(ssid_hint)
	var ssid_fmt := Label.new(); ssid_fmt.name = "SSIDFormatLabel"
	ssid_fmt.add_theme_font_size_override("font_size", UI_Theme._get_scaled_size(13))
	ssid_fmt.modulate = UI_Theme.accent_color(); ssid_fmt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# Afficher le SSID dès qu'on a un MULTIPASS (pas besoin du profil atom4love complet)
	ssid_fmt.text = Loca_Scanner.build_broadcast_ssid() if Player_Origin.is_initialized else "Créez votre MULTIPASS d'abord"
	ssid_hv.add_child(ssid_fmt)
	var btn_copy := Button.new(); btn_copy.text = "📋 Copier ce nom de réseau"
	btn_copy.custom_minimum_size = Vector2(0, 40)
	btn_copy.connect("pressed", func():
		var t := ssid_fmt.text
		if t == "" or "Configurez" in t: return
		DisplayServer.clipboard_set(t); emit_signal("toast_requested", "📋 SSID copié !"))
	ssid_hv.add_child(btn_copy)

	UI_Theme.add_label(self, "Atomes détectés :", 15)
	nearby_list = RichTextLabel.new(); nearby_list.bbcode_enabled = true; nearby_list.fit_content = true
	nearby_list.custom_minimum_size = Vector2(0, 110)
	nearby_list.text = "[color=#888888]En attente de scan…[/color]"; add_child(nearby_list)

	add_child(HSeparator.new())

	# ── HOT/COLD ─────────────────────────────────────────────────────────────────
	UI_Theme.add_section_title(self, "🌡  HOT / COLD — Radar")
	var hint_h := Label.new()
	hint_h.text = "Sélectionnez une cible. Déplacez-vous — les vibrations vous guident par résonance."
	hint_h.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint_h.add_theme_font_size_override("font_size", UI_Theme._get_scaled_size(13))
	hint_h.modulate = UI_Theme.text_hint(); add_child(hint_h)

	var tgt_hb := HBoxContainer.new(); tgt_hb.add_theme_constant_override("separation", 8); add_child(tgt_hb)
	var tgt_lbl := Label.new(); tgt_lbl.name = "HotColdTargetLabel"
	tgt_lbl.size_flags_horizontal = SIZE_EXPAND_FILL
	tgt_lbl.add_theme_font_size_override("font_size", UI_Theme._get_scaled_size(14))
	tgt_lbl.text = "— aucune cible —"; tgt_hb.add_child(tgt_lbl)
	var btn_pick := Button.new(); btn_pick.name = "HotColdScanBtn"; btn_pick.text = "CHOISIR"
	btn_pick.custom_minimum_size = Vector2(0, 52)
	btn_pick.connect("pressed", Callable(self, "_on_hotcold_pick")); tgt_hb.add_child(btn_pick)

	var ind_pc := PanelContainer.new()
	ind_pc.add_theme_stylebox_override("panel", UI_Theme.make_panel_style(0.3)); add_child(ind_pc)
	hotcold_indicator = ColorRect.new(); hotcold_indicator.name = "HotColdIndicator"
	hotcold_indicator.custom_minimum_size = Vector2(0, 160)
	hotcold_indicator.size_flags_horizontal = SIZE_EXPAND_FILL
	hotcold_indicator.color = Color(0.1, 0.1, 0.3); ind_pc.add_child(hotcold_indicator)

	hotcold_arrow_lbl = Label.new(); hotcold_arrow_lbl.name = "HotColdArrow"
	hotcold_arrow_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hotcold_arrow_lbl.add_theme_font_size_override("font_size", UI_Theme._get_scaled_size(52))
	hotcold_arrow_lbl.text = "—"; add_child(hotcold_arrow_lbl)

	hotcold_k_lbl = Label.new(); hotcold_k_lbl.name = "HotColdKLabel"
	hotcold_k_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hotcold_k_lbl.add_theme_font_size_override("font_size", UI_Theme._get_scaled_size(36))
	hotcold_k_lbl.text = "k = —"; add_child(hotcold_k_lbl)

	var hc_kbar := ProgressBar.new(); hc_kbar.name = "HotColdKBar"
	hc_kbar.max_value = 1.0; hc_kbar.custom_minimum_size = Vector2(0, 18); add_child(hc_kbar)

	var btn_hc := Button.new(); btn_hc.name = "HotColdActivateBtn"
	btn_hc.text = "▶ ACTIVER DÉCOUVERTE"; btn_hc.custom_minimum_size = Vector2(0, 56)
	btn_hc.add_theme_font_size_override("font_size", UI_Theme._get_scaled_size(18))
	btn_hc.connect("pressed", func(): emit_signal("scan_toggle_requested")); add_child(btn_hc)

	if OS.is_debug_build():
		add_child(HSeparator.new())
		UI_Theme.add_label(self, "🧪 GPS simulé (debug)", 13, UI_Theme.text_hint())
		var gps_hb := HBoxContainer.new(); gps_hb.alignment = BoxContainer.ALIGNMENT_CENTER
		gps_hb.add_theme_constant_override("separation", 8); add_child(gps_hb)
		for dir: Array in [["↑ N", 0.001, 0.0], ["↓ S", -0.001, 0.0], ["← O", 0.0, -0.001], ["→ E", 0.0, 0.001]]:
			var gb := Button.new(); gb.text = dir[0]
			gb.custom_minimum_size = Vector2(64, 48)
			var dlat: float = dir[1]; var dlon: float = dir[2]
			gb.connect("pressed", func():
				var cur := SpaceTime_Manager.current_gps
				SpaceTime_Manager.update_gps_location(cur.x + dlat, cur.y + dlon))
			gps_hb.add_child(gb)

func refresh(): build()

# ── Mise à jour temps-réel (appelées depuis Main_UI) ──────────────────────────
func update_scan_state(is_scanning: bool):
	if is_instance_valid(scan_btn):
		scan_btn.text = "⏹ ARRÊTER" if is_scanning else "▶ SCANNER"
	if is_instance_valid(ssid_lbl):
		ssid_lbl.text = ("SSID : " + Loca_Scanner.build_broadcast_ssid()) if is_scanning else "SSID : —"
	# Mettre à jour aussi ssid_fmt dans le panel de copie
	var ssid_fmt := find_child("SSIDFormatLabel", true, false) as Label
	if is_instance_valid(ssid_fmt) and Player_Origin.is_initialized:
		ssid_fmt.text = Loca_Scanner.build_broadcast_ssid()

func update_atom_list(atoms: Dictionary):
	if not is_instance_valid(nearby_list): return
	if atoms.is_empty():
		nearby_list.text = "[color=#888888]Aucun atome détecté.[/color]"; return
	var sorted := []
	for k in atoms: sorted.append(atoms[k] | {"npub": k})
	sorted.sort_custom(func(a, b): return a.get("k", 0.0) > b.get("k", 0.0))
	var text := ""
	for atom in sorted.slice(0, 10):
		var icon := "☀" if atom.get("sex", 0) == 0 else "🌙"
		var col := "[color=#00ffcc]" if atom.get("k", 0.0) >= 0.95 else ("[color=#ffcc00]" if atom.get("k", 0.0) >= 0.7 else "[color=#888888]")
		var sex_txt := "♂" if atom.get("sex", 0) == 0 else "♀"
		text += "%s%s %s  [b]k=%.3f[/b][/color]
" % [col, sex_txt, atom.get("npub","").substr(0,12), atom.get("k",0.0)]
	nearby_list.text = text

func update_hotcold(k: float):
	if not is_instance_valid(hotcold_indicator): return
	var cold := Color(0.05, 0.15, 0.8)
	var gold := Color(1.0, 0.80, 0.1)
	var hot  := Color(1.0, 0.15, 0.05)
	var base_col: Color = cold.lerp(hot, k) if k < 0.85 else hot.lerp(gold, (k - 0.85) / 0.15)
	if k > 0.9:
		var p := (sin(Time.get_ticks_msec() / 1000.0 * TAU * 4.0) * 0.5 + 0.5)
		base_col = base_col.lerp(gold, p * (k - 0.9) * 10.0)
	hotcold_indicator.color = base_col
	if is_instance_valid(hotcold_k_lbl):
		hotcold_k_lbl.text = "k = %.4f" % k; hotcold_k_lbl.modulate = base_col
	if is_instance_valid(hotcold_arrow_lbl):
		if k > _hotcold_prev_k + 0.005: hotcold_arrow_lbl.text = "🔥 ▲"; hotcold_arrow_lbl.modulate = hot
		elif k < _hotcold_prev_k - 0.005: hotcold_arrow_lbl.text = "❄ ▼"; hotcold_arrow_lbl.modulate = cold
		else: hotcold_arrow_lbl.text = "— ="; hotcold_arrow_lbl.modulate = Color(0.7, 0.7, 0.7)
	var kb := find_child("HotColdKBar", true, false) as ProgressBar
	if kb:
		kb.value = k
		var bs := StyleBoxFlat.new(); bs.bg_color = base_col; bs.set_corner_radius_all(4)
		kb.add_theme_stylebox_override("fill", bs)
	_hotcold_prev_k = k
	emit_signal("haptic_requested", k)

# ── Hot/Cold target picking ────────────────────────────────────────────────────
func _on_hotcold_pick():
	var atoms := Loca_Scanner.get_sorted_by_resonance()
	var popup := PanelContainer.new(); popup.set_anchors_preset(PRESET_FULL_RECT)
	popup.add_theme_stylebox_override("panel", UI_Theme.make_panel_style(0.97))
	get_tree().root.add_child(popup); popup.move_to_front()
	# `hidden` ferme la popup si l'onglet est masqué (changement de tab sans destruction)
	# `tree_exiting` ne se déclenche pas dans cette architecture car le tab reste en arbre
	self.hidden.connect(func(): if is_instance_valid(popup): popup.queue_free(), CONNECT_ONE_SHOT)
	var m := MarginContainer.new()
	for side in ["margin_left","margin_right","margin_top","margin_bottom"]:
		m.add_theme_constant_override(side, 20)
	popup.add_child(m)
	var pv := VBoxContainer.new(); pv.add_theme_constant_override("separation", 10); m.add_child(pv)
	UI_Theme.add_label(pv, "Choisir la cible :", 20)
	if atoms.is_empty():
		UI_Theme.add_label(pv, "Aucun atome détecté. Activez le scan LOCA.", 14)
	else:
		for atom in atoms:
			var btn := Button.new()
			var si := "☀" if atom.get("sex", 0) == 0 else "🌙"
			btn.text = "%s %s  k=%.3f" % [si, atom["npub"].substr(0, 12), atom["k"]]
			var npub_cap: String = atom["npub"]
			btn.connect("pressed", func(): _set_target(npub_cap, popup)); pv.add_child(btn)
	for hex in Nostr_Identity.follows:
		var btn := Button.new(); btn.text = "👥 " + hex.substr(0, 12) + "…"
		var hex_cap: String = hex
		btn.connect("pressed", func(): _set_target(hex_cap, popup)); pv.add_child(btn)
	var bc := Button.new(); bc.text = "ANNULER"; bc.connect("pressed", Callable(popup, "queue_free")); pv.add_child(bc)

func _set_target(npub: String, popup: Node):
	hotcold_target_npub = npub; _hotcold_prev_k = 0.0
	var tl := find_child("HotColdTargetLabel", true, false) as Label
	if tl: tl.text = npub.substr(0, 20) + "…"
	if is_instance_valid(hotcold_arrow_lbl): hotcold_arrow_lbl.text = "— ="; hotcold_arrow_lbl.modulate = Color(0.7, 0.7, 0.7)
	if is_instance_valid(popup): popup.queue_free()
	emit_signal("log_requested", "🎯 Cible Hot/Cold : " + npub.substr(0, 16))
