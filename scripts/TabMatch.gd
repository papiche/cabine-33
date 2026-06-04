class_name TabMatch
extends VBoxContainer

signal log_requested(msg: String)
signal toast_requested(msg: String)
signal share_resonance_requested
signal simulate_encounter_requested

func build():
	for child in get_children(): child.queue_free()
	_lbl_title(self, "🔬 TEST DE RÉSONANCE", 22, UI_Theme.accent_color())
	var hint := Label.new()
	hint.text = "Comparez deux empreintes cosmiques. Format date : AAAA-MM-JJ HH:MM  |  Lieu : lat, lon"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", UI_Theme._get_scaled_size(14))
	hint.modulate = UI_Theme.text_hint(); add_child(hint)

	if Player_Origin.is_initialized and Player_Origin.user_npub != "npub1_anonyme":
		var btn_load := Button.new(); btn_load.text = "📥 Charger mon profil dans Atome A"
		btn_load.custom_minimum_size = Vector2(0, 46)
		btn_load.connect("pressed", Callable(self, "_on_load_self")); add_child(btn_load)
	add_child(HSeparator.new())

	var profiles_hb := HBoxContainer.new()
	profiles_hb.add_theme_constant_override("separation", 10)
	profiles_hb.size_flags_horizontal = SIZE_EXPAND_FILL; add_child(profiles_hb)

	for i in range(2):
		var col := VBoxContainer.new()
		col.size_flags_horizontal = SIZE_EXPAND_FILL
		col.add_theme_constant_override("separation", 8); profiles_hb.add_child(col)
		var sf := "A" if i == 0 else "B"
		var col_col := UI_Theme.accent_color() if i == 0 else Color(1.0, 0.4, 0.4)
		_lbl_title(col, "🔵 Atome A" if i == 0 else "🔴 Atome B", 15, col_col)
		_lbl(col, "Naissance", 13)
		var di := LineEdit.new(); di.name = "TestDate" + sf
		di.placeholder_text = "AAAA-MM-JJ HH:MM"; di.custom_minimum_size = Vector2(0, 44)
		if i == 0 and Player_Origin.birth_unix > 0:
			var dt := Time.get_datetime_dict_from_unix_time(Player_Origin.birth_unix)
			di.text = "%04d-%02d-%02d %02d:%02d" % [dt.year, dt.month, dt.day, dt.hour, dt.minute]
		di.connect("text_changed", Callable(self, "_on_field_changed")); col.add_child(di)
		_lbl(col, "Lieu (lat,lon)", 13)
		var li := LineEdit.new(); li.name = "TestLoc" + sf
		li.placeholder_text = "lat, lon"; li.custom_minimum_size = Vector2(0, 44)
		li.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER_DECIMAL
		if i == 0 and Player_Origin.birth_lat != 0.0:
			li.text = "%.4f, %.4f" % [Player_Origin.birth_lat, Player_Origin.birth_lon]
		li.connect("text_changed", Callable(self, "_on_field_changed")); col.add_child(li)
		var shb := HBoxContainer.new(); shb.alignment = BoxContainer.ALIGNMENT_CENTER; col.add_child(shb)
		var bp := Button.new(); bp.name = "TestSex" + sf + "_0"; bp.text = "☀ Φ"
		bp.toggle_mode = true; bp.custom_minimum_size = Vector2(60, 42)
		bp.button_pressed = (i == 0 and Player_Origin.biological_sex == 0) or (i == 1); shb.add_child(bp)
		var bo := Button.new(); bo.name = "TestSex" + sf + "_1"; bo.text = "🌙 ♪"
		bo.toggle_mode = true; bo.custom_minimum_size = Vector2(60, 42)
		bo.button_pressed = (i == 0 and Player_Origin.biological_sex == 1); shb.add_child(bo)
		bp.connect("pressed", func(): bp.button_pressed = true; bo.button_pressed = false; _refresh())
		bo.connect("pressed", func(): bo.button_pressed = true; bp.button_pressed = false; _refresh())
		var ph_lbl := Label.new(); ph_lbl.name = "TestPhase" + sf
		ph_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ph_lbl.add_theme_font_size_override("font_size", UI_Theme._get_scaled_size(13))
		ph_lbl.modulate = UI_Theme.accent_color(); ph_lbl.text = "φ = —"; col.add_child(ph_lbl)
		var om_lbl := Label.new(); om_lbl.name = "TestOmega" + sf
		om_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		om_lbl.add_theme_font_size_override("font_size", UI_Theme._get_scaled_size(13))
		om_lbl.modulate = UI_Theme.text_hint(); om_lbl.text = "ω = —"; col.add_child(om_lbl)

	add_child(HSeparator.new())
	var result_panel := PanelContainer.new()
	result_panel.add_theme_stylebox_override("panel", UI_Theme.make_panel_style()); add_child(result_panel)
	var rv := VBoxContainer.new(); rv.add_theme_constant_override("separation", 8); result_panel.add_child(rv)
	var kl := Label.new(); kl.name = "TestKLabel"; kl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	kl.add_theme_font_size_override("font_size", UI_Theme._get_scaled_size(32)); kl.text = "k = —"; rv.add_child(kl)
	var kb := ProgressBar.new(); kb.name = "TestKBar"; kb.max_value = 1.0
	kb.custom_minimum_size = Vector2(0, 22); rv.add_child(kb)
	var dl := Label.new(); dl.name = "TestDetailLabel"; dl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dl.add_theme_font_size_override("font_size", UI_Theme._get_scaled_size(14)); dl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dl.text = "Remplissez les deux colonnes pour voir la synchronisation."; rv.add_child(dl)
	var legend := Label.new(); legend.add_theme_font_size_override("font_size", UI_Theme._get_scaled_size(12))
	legend.modulate = UI_Theme.text_hint(); legend.autowrap_mode = TextServer.AUTOWRAP_WORD
	legend.text = "φ = phase cosmique liée à votre naissance.  ω = fréquence bio en Hz.  k ∈ [0.5, 1.0]"
	rv.add_child(legend)

	add_child(HSeparator.new())
	var btn_sim := Button.new(); btn_sim.text = "🎲 SIMULER UNE RENCONTRE (ATOM4PEACE)"
	btn_sim.custom_minimum_size = Vector2(0, 54)
	btn_sim.add_theme_font_size_override("font_size", UI_Theme._get_scaled_size(15))
	btn_sim.connect("pressed", func(): emit_signal("simulate_encounter_requested")); add_child(btn_sim)

	if Player_Origin.is_initialized:
		add_child(HSeparator.new())
		var btn_inv := Button.new(); btn_inv.text = "✨ INVITER UN AMI — Tester notre résonance"
		btn_inv.custom_minimum_size = Vector2(0, 56)
		btn_inv.add_theme_font_size_override("font_size", UI_Theme._get_scaled_size(17))
		var inv_sb := StyleBoxFlat.new()
		inv_sb.bg_color = Color(0.28, 0.0, 0.52, 0.9); inv_sb.set_corner_radius_all(12)
		btn_inv.add_theme_stylebox_override("normal", inv_sb)
		btn_inv.connect("pressed", func(): emit_signal("share_resonance_requested")); add_child(btn_inv)

func refresh(): build()

func _on_load_self():
	if not Player_Origin.is_initialized: return
	var di := find_child("TestDateA", true, false) as LineEdit
	var li := find_child("TestLocA",  true, false) as LineEdit
	if Player_Origin.birth_unix > 0:
		var dt := Time.get_datetime_dict_from_unix_time(Player_Origin.birth_unix)
		if di: di.text = "%04d-%02d-%02d %02d:%02d" % [dt.year, dt.month, dt.day, dt.hour, dt.minute]
	if Player_Origin.birth_lat != 0.0 and li:
		li.text = "%.4f, %.4f" % [Player_Origin.birth_lat, Player_Origin.birth_lon]
	_refresh()

func _on_field_changed(_v: String): _refresh()

func _refresh():
	var results: Array = []
	for sf in ["A", "B"]:
		var di := find_child("TestDate" + sf, true, false) as LineEdit
		var li := find_child("TestLoc"  + sf, true, false) as LineEdit
		var sb := find_child("TestSex"  + sf + "_0", true, false) as Button
		var pl := find_child("TestPhase"+ sf, true, false) as Label
		var ol := find_child("TestOmega"+ sf, true, false) as Label
		if not (di and li and sb): results.append(null); continue
		var b_unix := _parse_datetime(di.text.strip_edges())
		if b_unix <= 0:
			if pl: pl.text = "φ = date invalide"; results.append(null); continue
		var lp := li.text.strip_edges().split(",")
		var blat := float(lp[0].strip_edges()) if lp.size() >= 2 else 0.0
		var blon := float(lp[1].strip_edges()) if lp.size() >= 2 else 0.0
		var sex  := 0 if sb.button_pressed else 1
		var phi  := Phi2X_Math.compute_personal_phase(b_unix, blat, blon)
		var h := Player_Origin.height_cm if sf == "A" else 170.0
		var w := Player_Origin.weight_kg if sf == "A" else 70.0
		var omega := Phi2X_Math.compute_omega_bio(h, w, sex)
		if pl: pl.text = "φ = %.5f" % phi
		if ol: ol.text = "ω = %.2f Hz" % omega
		results.append({"phi": phi, "sex": sex, "omega": omega})
	var kl := find_child("TestKLabel",     true, false) as Label
	var kb := find_child("TestKBar",       true, false) as ProgressBar
	var dl := find_child("TestDetailLabel",true, false) as Label
	if results.size() < 2 or results[0] == null or results[1] == null:
		if kl: kl.text = "k = —"; kl.modulate = UI_Theme.text_color()
		if kb: kb.value = 0.0
		return
	var pa: float = results[0]["phi"]; var pb: float = results[1]["phi"]
	var k := Phi2X_Math.compute_resonance_k(pa, pb)
	var is_sing := Phi2X_Math.is_optical_singularity(pa, pb)
	var col := UI_Theme.k_color(k)
	if kl: kl.text = "k = %.4f" % k; kl.modulate = col
	if kb:
		kb.value = k
		var bs := StyleBoxFlat.new(); bs.bg_color = col; bs.set_corner_radius_all(4)
		kb.add_theme_stylebox_override("fill", bs)
	if dl:
		var st := "  ✨ SINGULARITÉ !" if is_sing else ""
		dl.text = "Δφ = %.5f%s" % [abs(pa - pb), st]

func _parse_datetime(s: String) -> int:
	return Phi2X_Math.parse_datetime_safe(s)

# _k_col supprimé — utiliser UI_Theme.k_color(k) (source unique)

func _lbl_title(parent: Node, text: String, size: int, col: Color = Color.TRANSPARENT) -> Label:
	return UI_Theme.add_label(parent, text, size, col)

func _lbl(parent: Node, text: String, size: int = 14, col: Color = Color.TRANSPARENT) -> Label:
	return UI_Theme.add_label(parent, text, size, col)
