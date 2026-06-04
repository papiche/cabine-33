extends Control
# Onboarding 2 écrans — collecte toutes les données biométriques avant forge.
# Émet hook_completed(data) avec data = {
#   "action": "forge",
#   "birth_unix": int, "sex": int,
#   "birth_lat": float, "birth_lon": float,
#   "birth_weight": float,
#   "conception_unix": int, "conception_lat": float, "conception_lon": float
# }
# Émet resonance_ping_requested(k).

signal hook_completed(data: Dictionary)
signal resonance_ping_requested(k: float)

var _screen1: VBoxContainer = null
var _screen2: VBoxContainer = null
var _scroll: ScrollContainer = null

var _hook_birth_lat:    float = 0.0
var _hook_birth_lon:    float = 0.0
var _hook_con_lat:      float = 0.0
var _hook_con_lon:      float = 0.0
var _user_edited_conception: bool = false  # true si l'utilisateur a modifié la date manuellement

func _ready():
	set_anchors_preset(Control.PRESET_FULL_RECT)
	z_index = 100

	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.0, 0.02, 0.08, 0.97)
	add_child(bg)

	_scroll = ScrollContainer.new()
	_scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	add_child(_scroll)

	var m := MarginContainer.new()
	m.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		m.add_theme_constant_override(side, 28)
	_scroll.add_child(m)

	var outer := VBoxContainer.new()
	outer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer.add_theme_constant_override("separation", 0)
	m.add_child(outer)

	_build_screen1(outer)
	_build_screen2(outer)

# ── Écran 1 — Profil de naissance ───────────────────────────────────────────

func _build_screen1(parent: VBoxContainer):
	_screen1 = VBoxContainer.new()
	_screen1.name = "HookScreen1"
	_screen1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_screen1.add_theme_constant_override("separation", 20)
	parent.add_child(_screen1)

	_lbl_title(_screen1, "⚛ VOTRE PROFIL DE NAISSANCE", 24, UI_Theme.accent_color())

	var sub := Label.new()
	sub.text = "Ces données calculent votre KIN Maya — un identifiant basé sur votre date et lieu de naissance. Ainsi vous rencontrerez les membres du réseau qui vous correspondent."
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD
	sub.add_theme_font_size_override("font_size", UI_Theme._get_scaled_size(13))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.modulate = UI_Theme.text_secondary()
	_screen1.add_child(sub)

	_screen1.add_child(HSeparator.new())

	# Date de naissance — défaut exemple : 21/03/1972
	_lbl(_screen1, "📅 Date de naissance", 16, UI_Theme.text_secondary())
	var date_hb := HBoxContainer.new()
	date_hb.add_theme_constant_override("separation", 8)
	_screen1.add_child(date_hb)
	for info: Array in [["HookDay","Jour",2,"1"], ["HookMonth","Mois",2,"1"], ["HookYear","Année",4,"1970"]]:
		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		date_hb.add_child(col)
		_lbl(col, info[1], 12, UI_Theme.text_secondary())
		var le := UI_Theme.add_input(col, info[0], info[1], 66, LineEdit.KEYBOARD_TYPE_NUMBER)
		le.max_length = info[2]; le.text = info[3]
		le.focus_entered.connect(func(): le.call_deferred("select_all"))

	# Heure locale de naissance — défaut exemple : 20:12
	_lbl(_screen1, "⏰ Heure locale de naissance", 16, UI_Theme.text_secondary())
	var time_hb := HBoxContainer.new()
	time_hb.add_theme_constant_override("separation", 8)
	_screen1.add_child(time_hb)
	for info: Array in [["HookHour","Heure",2,"20"], ["HookMin","Min",2,"12"]]:
		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		time_hb.add_child(col)
		_lbl(col, info[1], 12, UI_Theme.text_secondary())
		var le := UI_Theme.add_input(col, info[0], info[1], 66, LineEdit.KEYBOARD_TYPE_NUMBER)
		le.max_length = info[2]; le.text = info[3]
		le.focus_entered.connect(func(): le.call_deferred("select_all"))

	# Lieu de naissance — requis pour passer à l'écran suivant
	_screen1.add_child(HSeparator.new())
	_lbl(_screen1, "📍 Lieu de naissance  (࿐ ࿔*:･゚)", 16, UI_Theme.text_secondary())
	_lbl(_screen1, "Permet de calculer votre position dans la grille hexagonale UPlanet.", 12, UI_Theme.text_hint())
	var city_hb := HBoxContainer.new()
	city_hb.add_theme_constant_override("separation", 8)
	_screen1.add_child(city_hb)
	var city_inp := LineEdit.new()
	city_inp.name = "HookCityInput"
	city_inp.placeholder_text = "Paris, Fort-de-France, Montréal…"
	city_inp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	city_inp.custom_minimum_size = Vector2(0, 62)
	city_hb.add_child(city_inp)
	var city_btn := Button.new()
	city_btn.text = "🔍"; city_btn.custom_minimum_size = Vector2(62, 62)
	city_btn.connect("pressed", Callable(self, "_on_birth_city_search"))
	city_hb.add_child(city_btn)
	var loc_lbl := Label.new()
	loc_lbl.name = "HookLocLabel"
	loc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	loc_lbl.add_theme_font_size_override("font_size", UI_Theme._get_scaled_size(12))
	loc_lbl.modulate = Color(0.9, 0.6, 0.2)
	loc_lbl.text = "Recherchez votre ville ou saisissez les coordonnées ci-dessous"
	_screen1.add_child(loc_lbl)

	# Champs de saisie manuelle — toujours visibles (fallback si Nominatim indisponible)
	var manual_lbl := Label.new()
	manual_lbl.text = "📍 Coordonnées manuelles (optionnel si la ville introuvable)"
	manual_lbl.add_theme_font_size_override("font_size", UI_Theme._get_scaled_size(11))
	manual_lbl.modulate = UI_Theme.text_hint(); _screen1.add_child(manual_lbl)
	var manual_hb := HBoxContainer.new(); manual_hb.add_theme_constant_override("separation", 8); _screen1.add_child(manual_hb)
	var lat_inp := UI_Theme.add_input(manual_hb, "HookManualLat", "Lat ex: 48.8566", 48, LineEdit.KEYBOARD_TYPE_NUMBER_DECIMAL)
	lat_inp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var lon_inp := UI_Theme.add_input(manual_hb, "HookManualLon", "Lon ex: 2.3522", 48, LineEdit.KEYBOARD_TYPE_NUMBER_DECIMAL)
	lon_inp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Saisie manuelle → active SUIVANT immédiatement
	var _manual_cb := func(_v: String):
		var lat_s := lat_inp.text.strip_edges(); var lon_s := lon_inp.text.strip_edges()
		if lat_s.is_valid_float() and lon_s.is_valid_float():
			_hook_birth_lat = float(lat_s); _hook_birth_lon = float(lon_s)
			loc_lbl.text = "📍 %.4f, %.4f (manuel)" % [_hook_birth_lat, _hook_birth_lon]
			loc_lbl.modulate = UI_Theme.text_positive()
			var bn := _screen1.find_child("HookBtnNext", true, false) as Button
			if bn: bn.disabled = false
			_update_precision()
	lat_inp.text_changed.connect(_manual_cb); lon_inp.text_changed.connect(_manual_cb)

	# KIN calculé — confirmation visuelle des données saisies
	var kin_preview := Label.new(); kin_preview.name = "HookKinPreview"
	kin_preview.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	kin_preview.add_theme_font_size_override("font_size", UI_Theme._get_scaled_size(16))
	kin_preview.modulate = UI_Theme.text_warm()
	kin_preview.autowrap_mode = TextServer.AUTOWRAP_WORD
	_screen1.add_child(kin_preview)

	for le_name: String in ["HookYear", "HookMonth", "HookDay"]:
		var le_node := _screen1.find_child(le_name, true, false) as LineEdit
		if le_node: le_node.text_changed.connect(func(_v: String): _refresh_kin())
	_refresh_kin()

	# Bouton SUIVANT — désactivé jusqu'à la saisie du lieu
	var btn_next := Button.new()
	btn_next.name = "HookBtnNext"
	btn_next.text = "SUIVANT →"
	btn_next.custom_minimum_size = Vector2(0, 72)
	btn_next.add_theme_font_size_override("font_size", UI_Theme._get_scaled_size(18))
	btn_next.disabled = true
	var sb_next := StyleBoxFlat.new()
	sb_next.bg_color = Color(0.0, 0.35, 0.55); sb_next.set_corner_radius_all(14)
	btn_next.add_theme_stylebox_override("normal", sb_next)
	btn_next.connect("pressed", Callable(self, "_on_next_screen"))
	_screen1.add_child(btn_next)

	UI_Theme.auto_scale(_screen1)

# ── Écran 2 — Complément biométrique & confirmation ──────────────────────────

func _build_screen2(parent: VBoxContainer):
	_screen2 = VBoxContainer.new()
	_screen2.name = "HookScreen2"
	_screen2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_screen2.add_theme_constant_override("separation", 20)
	_screen2.visible = false
	parent.add_child(_screen2)

	_lbl_title(_screen2, "⚖ DONNÉES COMPLÉMENTAIRES", 22, UI_Theme.accent_color())

	var sub := Label.new()
	sub.text = "Ces informations affinent votre clé cryptographique MULTIPASS. Plus les données sont précises, plus votre profil de correspondance est fiable."
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD
	sub.add_theme_font_size_override("font_size", UI_Theme._get_scaled_size(13))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.modulate = UI_Theme.text_secondary()
	_screen2.add_child(sub)

	_screen2.add_child(HSeparator.new())

	# Morphologie — poids de naissance + taille adulte
	var morph_hb := HBoxContainer.new(); morph_hb.add_theme_constant_override("separation", 12); _screen2.add_child(morph_hb)
	var w_col := VBoxContainer.new(); w_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL; morph_hb.add_child(w_col)
	_lbl(w_col, "⚖ Poids de naissance (kg)", 14, UI_Theme.text_secondary())
	var w_inp := UI_Theme.add_input(w_col, "HookWeight", "ex: 3.2", 58, LineEdit.KEYBOARD_TYPE_NUMBER_DECIMAL)
	w_inp.text = "3.5"
	w_inp.text_changed.connect(func(_v: String): _recalc_conception())
	var h_col := VBoxContainer.new(); h_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL; morph_hb.add_child(h_col)
	_lbl(h_col, "📏 Taille adulte (cm)", 14, UI_Theme.text_secondary())
	var h_inp := UI_Theme.add_input(h_col, "HookHeight", "ex: 170", 58, LineEdit.KEYBOARD_TYPE_NUMBER)
	h_inp.text = "170"
	_lbl(_screen2, "Poids de naissance : vérifiez dans votre carnet de santé. Taille : calibre la résonance de cavité ω_bio.", 11, UI_Theme.text_hint())

	_screen2.add_child(HSeparator.new())

	# Sexe biologique — radio buttons via ButtonGroup
	_lbl(_screen2, "⚧ Sexe biologique", 16, UI_Theme.text_secondary())
	_lbl(_screen2, "Détermine la fréquence de base (φ ou ♪) utilisée dans le calcul de résonance.", 12, UI_Theme.text_hint())
	var sex_group := ButtonGroup.new()
	var sex_hb := HBoxContainer.new()
	sex_hb.add_theme_constant_override("separation", 12)
	_screen2.add_child(sex_hb)
	var btn_phi := Button.new(); btn_phi.name = "HookBtnPhi"
	btn_phi.text = "♂  Homme"; btn_phi.toggle_mode = true
	btn_phi.button_pressed = true; btn_phi.button_group = sex_group
	btn_phi.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_phi.custom_minimum_size = Vector2(0, 64)
	btn_phi.add_theme_font_size_override("font_size", UI_Theme._get_scaled_size(16))
	sex_hb.add_child(btn_phi)
	var btn_oct := Button.new(); btn_oct.name = "HookBtnOct"
	btn_oct.text = "♀  Femme"; btn_oct.toggle_mode = true
	btn_oct.button_group = sex_group
	btn_oct.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_oct.custom_minimum_size = Vector2(0, 64)
	btn_oct.add_theme_font_size_override("font_size", UI_Theme._get_scaled_size(16))
	sex_hb.add_child(btn_oct)

	_screen2.add_child(HSeparator.new())

	# Date de conception — calculée, éditable si connue
	var conc_panel := PanelContainer.new()
	var conc_sb := StyleBoxFlat.new()
	conc_sb.bg_color = Color(0.05, 0.08, 0.15, 0.8); conc_sb.set_corner_radius_all(10)
	conc_panel.add_theme_stylebox_override("panel", conc_sb)
	_screen2.add_child(conc_panel)
	var conc_vbox := VBoxContainer.new()
	conc_vbox.add_theme_constant_override("separation", 10)
	var conc_margin := MarginContainer.new()
	for s in ["margin_left","margin_right","margin_top","margin_bottom"]: conc_margin.add_theme_constant_override(s, 14)
	conc_margin.add_child(conc_vbox); conc_panel.add_child(conc_margin)

	_lbl(conc_vbox, "📅 Date de conception", 14, UI_Theme.text_secondary())
	_lbl(conc_vbox, "Corrigez avec la date exacte — améliore la précision et renforce la sécurité de votre clé.", 11, UI_Theme.text_hint())
	var cd_hb := HBoxContainer.new(); cd_hb.add_theme_constant_override("separation", 8); conc_vbox.add_child(cd_hb)
	for info: Array in [["HookConDay","Jour",2,"jj"], ["HookConMonth","Mois",2,"mm"], ["HookConYear","Année",4,"aaaa"]]:
		var col := VBoxContainer.new(); col.size_flags_horizontal = Control.SIZE_EXPAND_FILL; cd_hb.add_child(col)
		_lbl(col, info[1], 11, UI_Theme.text_secondary())
		var le := UI_Theme.add_input(col, info[0], info[3], 58, LineEdit.KEYBOARD_TYPE_NUMBER)
		le.max_length = info[2]; le.text = info[3]
		le.text_changed.connect(func(_v: String): _user_edited_conception = true)

	_lbl(conc_vbox, "📍 Lieu de conception (༄˖°.🪐.ೃ࿔*:･)", 13, UI_Theme.text_secondary())
	var con_city_hb := HBoxContainer.new(); con_city_hb.add_theme_constant_override("separation", 8); conc_vbox.add_child(con_city_hb)
	var con_inp := LineEdit.new()
	con_inp.name = "HookConCityInput"
	con_inp.placeholder_text = "Laisser vide si identique au lieu de votre naissance"
	con_inp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	con_inp.custom_minimum_size = Vector2(0, 52)
	con_city_hb.add_child(con_inp)
	var con_btn := Button.new(); con_btn.text = "🔍"; con_btn.custom_minimum_size = Vector2(52, 52)
	con_btn.connect("pressed", Callable(self, "_on_con_city_search"))
	con_city_hb.add_child(con_btn)
	var con_loc_lbl := Label.new(); con_loc_lbl.name = "HookConLocLabel"
	con_loc_lbl.add_theme_font_size_override("font_size", UI_Theme._get_scaled_size(12))
	con_loc_lbl.modulate = UI_Theme.text_hint()
	_screen2.add_child(con_loc_lbl)

	_screen2.add_child(HSeparator.new())

	# Précision du profil
	var prec_lbl := Label.new(); prec_lbl.name = "HookPrecisionLabel"
	prec_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prec_lbl.add_theme_font_size_override("font_size", UI_Theme._get_scaled_size(14))
	_screen2.add_child(prec_lbl)
	var prec_bar := ProgressBar.new(); prec_bar.name = "HookPrecisionBar"
	prec_bar.max_value = 100; prec_bar.value = 0
	prec_bar.custom_minimum_size = Vector2(0, 14)
	_screen2.add_child(prec_bar)
	var prec_hint := Label.new(); prec_hint.name = "HookPrecisionHint"
	prec_hint.add_theme_font_size_override("font_size", UI_Theme._get_scaled_size(11))
	prec_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prec_hint.autowrap_mode = TextServer.AUTOWRAP_WORD
	prec_hint.modulate = UI_Theme.text_hint()
	_screen2.add_child(prec_hint)

	_screen2.add_child(HSeparator.new())

	# Boutons action
	var btn_forge := Button.new()
	btn_forge.text = "✅ CRÉER MON IDENTITÉ"
	btn_forge.custom_minimum_size = Vector2(0, 76)
	btn_forge.add_theme_font_size_override("font_size", UI_Theme._get_scaled_size(20))
	var sb_forge := StyleBoxFlat.new()
	sb_forge.bg_color = Color(0.0, 0.45, 0.25); sb_forge.set_corner_radius_all(14)
	btn_forge.add_theme_stylebox_override("normal", sb_forge)
	btn_forge.connect("pressed", Callable(self, "_on_forge"))
	_screen2.add_child(btn_forge)

	var btn_back := Button.new()
	btn_back.text = "◀ RETOUR"
	btn_back.custom_minimum_size = Vector2(0, 52)
	btn_back.connect("pressed", Callable(self, "_on_back_screen"))
	_screen2.add_child(btn_back)

	# Invitation coopérative
	_screen2.add_child(HSeparator.new())
	var coop_lbl := Label.new()
	coop_lbl.text = "ATOM4LOVE est développé par G1FabLab — réseau coopératif NOSTR + IPFS + Monnaie Libre."
	coop_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	coop_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	coop_lbl.add_theme_font_size_override("font_size", UI_Theme._get_scaled_size(12))
	coop_lbl.modulate = UI_Theme.text_hint()
	_screen2.add_child(coop_lbl)
	var btn_oc := Button.new()
	btn_oc.text = "🤝 Soutenir sur OpenCollective"
	btn_oc.custom_minimum_size = Vector2(0, 48)
	btn_oc.add_theme_font_size_override("font_size", UI_Theme._get_scaled_size(13))
	btn_oc.connect("pressed", func(): OS.shell_open("https://opencollective.com/monnaie-libre/contribute"))
	_screen2.add_child(btn_oc)

	UI_Theme.auto_scale(_screen2)

# ── Navigation entre écrans ───────────────────────────────────────────────────

func _on_next_screen():
	if not _validate_screen1(): return
	_screen1.visible = false
	_screen2.visible = true
	_recalc_conception()
	if _scroll: _scroll.scroll_vertical = 0
	UI_Theme.vibrate(80)

func _on_back_screen():
	_screen2.visible = false
	_screen1.visible = true
	_user_edited_conception = false  # l'utilisateur retourne corriger la date → le recalcul doit se refaire
	if _scroll: _scroll.scroll_vertical = 0

func _validate_screen1() -> bool:
	var sy := _screen1.find_child("HookYear",  true, false) as LineEdit
	var sm := _screen1.find_child("HookMonth", true, false) as LineEdit
	var sd := _screen1.find_child("HookDay",   true, false) as LineEdit
	if not (sy and sm and sd): return false
	if not (sy.text.is_valid_int() and sm.text.is_valid_int() and sd.text.is_valid_int()): return false
	var sh := _screen1.find_child("HookHour", true, false) as LineEdit
	var sn := _screen1.find_child("HookMin",  true, false) as LineEdit
	var b := Phi2X_Math.validate_date(int(sy.text), int(sm.text), int(sd.text),
		int(sh.text) if sh and sh.text.is_valid_int() else 12,
		int(sn.text) if sn and sn.text.is_valid_int() else 0)
	return b > 0

func _get_birth_unix() -> int:
	var sy := _screen1.find_child("HookYear",  true, false) as LineEdit
	var sm := _screen1.find_child("HookMonth", true, false) as LineEdit
	var sd := _screen1.find_child("HookDay",   true, false) as LineEdit
	var sh := _screen1.find_child("HookHour",  true, false) as LineEdit
	var sn := _screen1.find_child("HookMin",   true, false) as LineEdit
	if not (sy and sm and sd and sy.text.is_valid_int()): return -1
	var y := int(sy.text)
	if y > 0 and y < 100: y += (2000 if y < 30 else 1900)  # "85"→1985, "05"→2005
	return Phi2X_Math.validate_date(
		y,
		int(sm.text) if sm.text.is_valid_int() else 1,
		int(sd.text) if sd.text.is_valid_int() else 1,
		int(sh.text) if sh and sh.text.is_valid_int() else 12,
		int(sn.text) if sn and sn.text.is_valid_int() else 0)

func _get_weight() -> float:
	var wi := _screen2.find_child("HookWeight", true, false) as LineEdit
	if not wi or not wi.text.replace(",",".").is_valid_float(): return 3.5
	return float(wi.text.replace(",","."))

# ── Pré-calcul des données de conception ─────────────────────────────────────

func _recalc_conception():
	if _user_edited_conception: return  # ne pas écraser si l'utilisateur a corrigé manuellement
	var b_unix := _get_birth_unix()
	if b_unix <= 0: return
	var w := _get_weight()
	var c_unix := Phi2X_Math.compute_conception_unix(b_unix, w)
	var cd := Time.get_datetime_dict_from_unix_time(c_unix)
	for pair: Array in [["HookConDay",cd.day],["HookConMonth",cd.month],["HookConYear",cd.year]]:
		var le := _screen2.find_child(pair[0], true, false) as LineEdit
		if le: le.text = str(pair[1])
	# Heure de conception reste à 0h00 sauf si déjà modifié manuellement
	_update_precision()

func _update_precision():
	var prec_lbl  := _screen2.find_child("HookPrecisionLabel", true, false) as Label
	var prec_bar  := _screen2.find_child("HookPrecisionBar",   true, false) as ProgressBar
	var prec_hint := _screen2.find_child("HookPrecisionHint",  true, false) as Label
	if not prec_lbl or not prec_bar: return
	var score := _compute_precision()
	prec_bar.value = score
	var color := UI_Theme.text_positive() if score >= 90 else (UI_Theme.text_warm() if score >= 60 else Color(1.0, 0.4, 0.4))
	prec_lbl.modulate = color
	prec_lbl.text = "Précision du profil : %d%%" % score
	if prec_hint:
		if score >= 90:
			prec_hint.text = "✅ Profil complet — votre identité cosmique est prête."
		elif score >= 60:
			var missing: Array = []
			if _hook_birth_lat == 0.0 and _hook_birth_lon == 0.0: missing.append("lieu de naissance")
			var wi := _screen2.find_child("HookWeight", true, false) as LineEdit
			if not wi or wi.text == "3.5": missing.append("poids de naissance")
			if missing.is_empty():
				prec_hint.text = "✅ Profil complet — votre identité cosmique est prête."
			else:
				prec_hint.text = "💡 Pour améliorer : ajoutez " + ", ".join(missing) + "."
		else:
			prec_hint.text = "📍 Renseignez votre lieu de naissance pour améliorer la précision."

func _compute_precision() -> int:
	var score := 0
	var b_unix := _get_birth_unix()
	if b_unix <= 0: return 0
	score += 40  # date de naissance
	var sh := _screen1.find_child("HookHour", true, false) as LineEdit
	var sn := _screen1.find_child("HookMin",  true, false) as LineEdit
	var h := int(sh.text) if sh and sh.text.is_valid_int() else 12
	var mn := int(sn.text) if sn and sn.text.is_valid_int() else 0
	if h != 12 or mn != 0: score += 15  # heure non-défaut
	if _hook_birth_lat != 0.0 or _hook_birth_lon != 0.0: score += 20  # lieu naissance
	var w := _get_weight()
	if w != 3.5: score += 15  # poids personnalisé
	if _hook_con_lat != 0.0 or _hook_con_lon != 0.0: score += 10  # lieu conception distinct
	return clamp(score, 0, 100)

# ── Toggle polarité ───────────────────────────────────────────────────────────

func _toggle_sex(selected: Button, other: Button):
	selected.button_pressed = true
	other.button_pressed = false
	var ac := UI_Theme.accent_color()
	var sel_sb := StyleBoxFlat.new()
	sel_sb.bg_color = Color(ac.r, ac.g, ac.b, 0.25); sel_sb.set_corner_radius_all(8)
	selected.add_theme_stylebox_override("normal", sel_sb)
	other.remove_theme_stylebox_override("normal")

# ── KIN preview (écran 1) ─────────────────────────────────────────────────────

func _refresh_kin():
	var kin_lbl := _screen1.find_child("HookKinPreview", true, false) as Label
	if not kin_lbl: return
	var sy := _screen1.find_child("HookYear",  true, false) as LineEdit
	var sm := _screen1.find_child("HookMonth", true, false) as LineEdit
	var sd := _screen1.find_child("HookDay",   true, false) as LineEdit
	if not (sy and sm and sd): return
	if not (sy.text.is_valid_int() and sm.text.is_valid_int() and sd.text.is_valid_int()): return
	var k := Kin_Maya.calc_kin(int(sy.text), int(sm.text), int(sd.text))
	kin_lbl.text = "KIN %d · %s" % [k.get("kin", 0), Kin_Maya.format_kin_short(k)]

# ── Forge ─────────────────────────────────────────────────────────────────────

func _on_forge():
	var b_unix := _get_birth_unix()
	if b_unix <= 0: return
	var btn_phi := _screen2.find_child("HookBtnPhi", true, false) as Button
	var sex := 0 if (btn_phi and btn_phi.button_pressed) else 1
	var w := _get_weight()
	var h_inp2 := _screen2.find_child("HookHeight", true, false) as LineEdit
	var h := clamp(float(h_inp2.text.replace(",",".")) if (h_inp2 and h_inp2.text.strip_edges() != "" and h_inp2.text.is_valid_float()) else 170.0, 50.0, 280.0)

	# Date de conception (éventuellement corrigée par l'utilisateur)
	var cdy := _screen2.find_child("HookConYear",  true, false) as LineEdit
	var cdm := _screen2.find_child("HookConMonth", true, false) as LineEdit
	var cdd := _screen2.find_child("HookConDay",   true, false) as LineEdit
	var cdh := _screen2.find_child("HookConHour",  true, false) as LineEdit
	var cdn := _screen2.find_child("HookConMin",   true, false) as LineEdit
	var c_unix := 0
	if cdy and cdy.text.is_valid_int() and cdm and cdm.text.is_valid_int() and cdd and cdd.text.is_valid_int():
		c_unix = Phi2X_Math.validate_date(
			int(cdy.text), int(cdm.text), int(cdd.text),
			int(cdh.text) if cdh and cdh.text.is_valid_int() else 0,
			int(cdn.text) if cdn and cdn.text.is_valid_int() else 0)
	if c_unix <= 0:
		c_unix = Phi2X_Math.compute_conception_unix(b_unix, w)

	var con_lat := _hook_con_lat if _hook_con_lat != 0.0 else _hook_birth_lat
	var con_lon := _hook_con_lon if _hook_con_lon != 0.0 else _hook_birth_lon

	UI_Theme.vibrate(50)  # clic de confirmation bref ; l'Orchestre Quantique gère l'envolée haptique
	emit_signal("resonance_ping_requested", 0.92)
	emit_signal("hook_completed", {
		"action": "forge",
		"birth_unix": b_unix, "sex": sex,
		"birth_lat": _hook_birth_lat, "birth_lon": _hook_birth_lon,
		"birth_weight": w, "height_cm": h,
		"conception_unix": c_unix,
		"conception_lat": con_lat, "conception_lon": con_lon
	})

# ── Recherche ville de naissance (Nominatim) ──────────────────────────────────

func _on_birth_city_search():
	var city_inp := _screen1.find_child("HookCityInput", true, false) as LineEdit
	var loc_lbl  := _screen1.find_child("HookLocLabel",  true, false) as Label
	if not city_inp or city_inp.text.strip_edges() == "": return
	if loc_lbl: loc_lbl.text = "⏳ Recherche…"
	var http := HTTPRequest.new(); http.name = "HookNominatim"; add_child(http)
	http.request_completed.connect(_on_birth_nominatim.bind(http), CONNECT_ONE_SHOT)
	var url := "https://nominatim.openstreetmap.org/search?q=%s&format=json&limit=1" % \
		city_inp.text.strip_edges().uri_encode()
	if http.request(url) != OK:
		if loc_lbl: loc_lbl.text = "❌ Réseau indisponible — utilisez les champs Lat/Lon ci-dessous."
		http.queue_free()
		http.queue_free()

func _on_birth_nominatim(result: int, code: int, _h: PackedStringArray,
		body: PackedByteArray, http: HTTPRequest):
	if is_instance_valid(http): http.queue_free()
	var loc_lbl := _screen1.find_child("HookLocLabel", true, false) as Label
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		if loc_lbl: loc_lbl.text = "❌ Introuvable."; return
	var json := JSON.new()
	if json.parse(body.get_string_from_utf8()) != OK or not (json.get_data() is Array) or (json.get_data() as Array).is_empty():
		if loc_lbl: loc_lbl.text = "❌ Ville inconnue."; return
	var entry = (json.get_data() as Array)[0]
	_hook_birth_lat = float(entry.get("lat", "0"))
	_hook_birth_lon = float(entry.get("lon", "0"))
	var city_name: String = (entry.get("display_name", "") as String).split(",")[0]
	if loc_lbl:
		loc_lbl.text = "✅ %.4f, %.4f — %s" % [_hook_birth_lat, _hook_birth_lon, city_name]
		loc_lbl.modulate = UI_Theme.text_positive()
	var btn_next := _screen1.find_child("HookBtnNext", true, false) as Button
	if btn_next: btn_next.disabled = false
	_update_precision()

# ── Recherche ville de conception (Nominatim) ─────────────────────────────────

func _on_con_city_search():
	var city_inp := _screen2.find_child("HookConCityInput", true, false) as LineEdit
	var loc_lbl  := _screen2.find_child("HookConLocLabel",  true, false) as Label
	if not city_inp or city_inp.text.strip_edges() == "": return
	if loc_lbl: loc_lbl.text = "⏳ Recherche…"
	var http := HTTPRequest.new(); http.name = "HookConNominatim"; add_child(http)
	http.request_completed.connect(_on_con_nominatim.bind(http), CONNECT_ONE_SHOT)
	var url := "https://nominatim.openstreetmap.org/search?q=%s&format=json&limit=1" % \
		city_inp.text.strip_edges().uri_encode()
	if http.request(url) != OK:
		if loc_lbl: loc_lbl.text = "❌ Réseau indisponible — utilisez les champs Lat/Lon ci-dessous."
		http.queue_free()
		http.queue_free()

func _on_con_nominatim(result: int, code: int, _h: PackedStringArray,
		body: PackedByteArray, http: HTTPRequest):
	if is_instance_valid(http): http.queue_free()
	var loc_lbl := _screen2.find_child("HookConLocLabel", true, false) as Label
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		if loc_lbl: loc_lbl.text = "❌ Introuvable."; return
	var json := JSON.new()
	if json.parse(body.get_string_from_utf8()) != OK or not (json.get_data() is Array) or (json.get_data() as Array).is_empty():
		if loc_lbl: loc_lbl.text = "❌ Ville inconnue."; return
	var entry = (json.get_data() as Array)[0]
	_hook_con_lat = float(entry.get("lat", "0"))
	_hook_con_lon = float(entry.get("lon", "0"))
	var city_name: String = (entry.get("display_name", "") as String).split(",")[0]
	if loc_lbl: loc_lbl.text = "📍 %.4f, %.4f — %s" % [_hook_con_lat, _hook_con_lon, city_name]
	_update_precision()

# ── Helpers UI ────────────────────────────────────────────────────────────────

func _lbl(parent: Node, text: String, size: int, color: Color = Color.TRANSPARENT) -> Label:
	return UI_Theme.add_label(parent, text, size, color)

func _lbl_title(parent: Node, text: String, size: int, color: Color = Color.TRANSPARENT) -> Label:
	var l := UI_Theme.add_label(parent, text, size, color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l
