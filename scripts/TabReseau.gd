class_name TabReseau
extends VBoxContainer

signal log_requested(msg: String)
signal toast_requested(msg: String)
signal open_profil_requested
signal reset_requested

# État injecté depuis Main_UI
var wot_authorized: bool  = false
var cabine_dist_km: float = 999.0
const CABINE_UNLOCK_KM: float = 0.05

func build():
	for child in get_children(): child.queue_free()

	UI_Theme.add_section_title(self, "🌍 RÉSEAU N²")
	if not Player_Origin.is_initialized or Player_Origin.user_npub == "npub1_anonyme":
		_build_locked(); return

	_build_qr_section()
	add_child(HSeparator.new())
	_build_follows_section()
	add_child(HSeparator.new())
	_build_cabine_section()
	add_child(HSeparator.new())
	_build_udrive_section()
	add_child(HSeparator.new())
	_build_log_section()
	add_child(HSeparator.new())
	# RESET déplacé vers le ProfileTab — bouton résiduel ici pour historique
	var btn_reset := Button.new(); btn_reset.text = "🔄 Déconnexion — Oublier ce MULTIPASS"
	btn_reset.custom_minimum_size = Vector2(0, 44)
	var rst_sb := StyleBoxFlat.new()
	rst_sb.bg_color = Color(0.45, 0.15, 0.1); rst_sb.set_corner_radius_all(10)
	btn_reset.add_theme_stylebox_override("normal", rst_sb)
	btn_reset.connect("pressed", func(): emit_signal("reset_requested")); add_child(btn_reset)

func refresh(): build()

func set_cabine_distance(dist_km: float):
	cabine_dist_km = dist_km
	var lbl := find_child("Cabine33DistLabel", true, false) as Label
	if not is_instance_valid(lbl): return
	# Toujours afficher en mètres pour distance < 1 km (plus lisible pour l'utilisateur)
	var dist_m := dist_km * 1000.0
	var dval := ("%.0fm" % dist_m) if dist_m < 1000.0 else ("%.2f km" % dist_km)
	lbl.text = ("✅ Nœud PHI accessible (%s)" % dval) if dist_km <= CABINE_UNLOCK_KM \
		else ("🔒 %s du centre hex (< %.0fm requis)" % [dval, CABINE_UNLOCK_KM * 1000.0])
	lbl.modulate = Color(0.2, 0.9, 0.5) if dist_km <= CABINE_UNLOCK_KM else Color(0.7, 0.7, 0.7)

func update_log(text: String):
	var lbl := find_child("InlineLog", true, false) as RichTextLabel
	if is_instance_valid(lbl): lbl.text = text

# ── Sections ──────────────────────────────────────────────────────────────────
func _build_locked():
	UI_Theme.add_label(self, "🔒 Réseau verrouillé", 20, Color(1.0, 0.5, 0.3))
	var hl := Label.new()
	hl.text = "Forgez votre MULTIPASS pour rejoindre le réseau, publier sur NOSTR et créer votre constellation."
	hl.autowrap_mode = TextServer.AUTOWRAP_WORD; hl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hl.add_theme_font_size_override("font_size", UI_Theme._get_scaled_size(15)); add_child(hl)
	var btn := Button.new(); btn.text = "⚡ FORGER MON MULTIPASS"
	btn.custom_minimum_size = Vector2(0, 62)
	btn.add_theme_font_size_override("font_size", UI_Theme._get_scaled_size(18))
	var sb := StyleBoxFlat.new(); sb.bg_color = Color(0.0, 0.45, 0.25); sb.set_corner_radius_all(14)
	btn.add_theme_stylebox_override("normal", sb)
	btn.connect("pressed", func(): emit_signal("open_profil_requested")); add_child(btn)

func _build_qr_section():
	UI_Theme.add_section_title(self, "🔑 MA CLÉ PUBLIQUE")
	var npub := Player_Origin.user_npub
	var qr_lbl := Label.new(); qr_lbl.text = npub.substr(0,20) + "…" + npub.right(4)
	qr_lbl.add_theme_font_size_override("font_size", UI_Theme._get_scaled_size(13))
	qr_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	qr_lbl.modulate = UI_Theme.accent_color()
	qr_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; add_child(qr_lbl)
	var btn_copy := Button.new(); btn_copy.text = "📋 Copier ma clé publique"
	btn_copy.custom_minimum_size = Vector2(0, 44)
	btn_copy.connect("pressed", func():
		DisplayServer.clipboard_set(npub)
		emit_signal("toast_requested", "📋 Clé publique copiée !"))
	add_child(btn_copy)

func _build_follows_section():
	UI_Theme.add_section_title(self, "⭐ CONSTELLATION")
	if Nostr_Identity.follows.is_empty():
		var el := Label.new(); el.text = "Aucune étoile. Scannez des atomes ou ajoutez manuellement."
		el.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		el.add_theme_font_size_override("font_size", UI_Theme._get_scaled_size(14)); add_child(el)
	else:
		for hex in Nostr_Identity.follows:
			var row := HBoxContainer.new(); add_child(row)
			var hl := Label.new(); hl.text = hex.substr(0, 12) + "…" + hex.right(4)
			hl.size_flags_horizontal = SIZE_EXPAND_FILL; row.add_child(hl)
			var btn_u := Button.new(); btn_u.text = "✖"
			var hex_cap: String = hex
			btn_u.connect("pressed", func(): Nostr_Identity.unfollow(hex_cap); refresh())
			row.add_child(btn_u)
	var hex_inp := LineEdit.new(); hex_inp.name = "HexFollowInput"
	hex_inp.placeholder_text = "Pubkey hex (64 chars) ou npub1…"
	hex_inp.custom_minimum_size = Vector2(0, 46); add_child(hex_inp)
	var fhb := HBoxContainer.new(); fhb.add_theme_constant_override("separation", 8); add_child(fhb)
	var btn_follow := Button.new(); btn_follow.text = "+ SUIVRE"
	btn_follow.size_flags_horizontal = SIZE_EXPAND_FILL
	btn_follow.connect("pressed", func():
		var inp := find_child("HexFollowInput", true, false) as LineEdit
		if not inp: return
		var t := inp.text.strip_edges()
		if t.begins_with("npub1"):
			t = NostrCrypto.npub_to_hex(t)
		if t.length() == 64: Nostr_Identity.follow(t); inp.text = ""; refresh()
		else: emit_signal("log_requested", "⚠ Pubkey hex invalide (64 chars requis)."))
	fhb.add_child(btn_follow)
	var btn_k3 := Button.new(); btn_k3.text = "📤 Publier Kind 3"
	btn_k3.size_flags_horizontal = SIZE_EXPAND_FILL
	btn_k3.connect("pressed", Callable(Nostr_Identity, "publish_kind3")); fhb.add_child(btn_k3)

func _build_cabine_section():
	UI_Theme.add_section_title(self, "🔮 CABINE-33")
	var dist_lbl := Label.new(); dist_lbl.name = "Cabine33DistLabel"
	dist_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dist_lbl.add_theme_font_size_override("font_size", UI_Theme._get_scaled_size(16))
	add_child(dist_lbl); set_cabine_distance(cabine_dist_km)  # initialise le label

	if cabine_dist_km <= CABINE_UNLOCK_KM and wot_authorized:
		var thought := TextEdit.new(); thought.name = "InlineThoughtInput"
		thought.placeholder_text = "Déposez une pensée dans le vide quantique…"
		thought.custom_minimum_size = Vector2(0, 120)
		thought.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY; add_child(thought)
		var btn_send := Button.new(); btn_send.name = "SendThoughtBtn"
		btn_send.text = "📡 TRANSMETTRE"
		btn_send.custom_minimum_size = Vector2(0, 54)
		btn_send.add_theme_font_size_override("font_size", UI_Theme._get_scaled_size(16))
		btn_send.connect("pressed", func():
			var t_inp := find_child("InlineThoughtInput", true, false) as TextEdit
			var btn := find_child("SendThoughtBtn", true, false) as Button
			if not t_inp: return
			var content := t_inp.text.strip_edges()
			if content.is_empty():
				emit_signal("toast_requested", "✏️ Écrivez une pensée avant d'envoyer.")
				return
			if btn: btn.disabled = true; btn.text = "⏳ Envoi…"
			var gps := SpaceTime_Manager.current_gps
			Thought_Cache.capture_thought(content, {"lat": gps.x, "lon": gps.y})
			if Player_Origin.is_initialized and Nostr_Identity.relay_list.size() > 0:
				var ts := float(Time.get_unix_time_from_system())
				var geo := Phi2X_Math.geo_tags(gps.x, gps.y, ts)
				var ev_tags: Array = geo.duplicate()
				ev_tags.append(["t","atom4love"]); ev_tags.append(["t","cabine33"])
				var ev := Nostr_Identity.make_event(1, content, ev_tags)
				Nostr_Identity.sign_and_send(ev)
				emit_signal("toast_requested", "💭 Pensée transmise au Vide Quantique !")
				emit_signal("log_requested", "💭 Spacememory — " + geo[1][1])
			else:
				emit_signal("toast_requested", "💾 Pensée conservée localement (hors réseau).")
			t_inp.text = ""
			if btn: btn.disabled = false; btn.text = "📡 TRANSMETTRE")
		add_child(btn_send)

func _build_udrive_section():
	UI_Theme.add_section_title(self, "☁️ MON uDRIVE")
	var udrive_url := Player_Origin.get_udrive_url() if Player_Origin.has_method("get_udrive_url") else ""
	if not udrive_url.is_empty():
		var udrive_link := LinkButton.new()
		udrive_link.text = "🌐 Voir mon uDRIVE sur ma station"
		udrive_link.add_theme_font_size_override("font_size", UI_Theme._get_scaled_size(13))
		udrive_link.connect("pressed", func(): OS.shell_open(udrive_url)); add_child(udrive_link)
	var nc := Thought_Cache.local_thoughts.size() if Thought_Cache.has_method("local_thoughts") else 0
	var cache_lbl := Label.new(); cache_lbl.name = "CacheCountLabel"
	cache_lbl.text = ("💭 %d pensée(s) en attente de sync" % nc) if nc > 0 else "💭 Cache vide"
	cache_lbl.add_theme_font_size_override("font_size", UI_Theme._get_scaled_size(14)); add_child(cache_lbl)
	var udrive_hb := HBoxContainer.new(); udrive_hb.add_theme_constant_override("separation", 8); add_child(udrive_hb)
	var btn_sync := Button.new(); btn_sync.text = "📤 Sync pensées"
	btn_sync.size_flags_horizontal = SIZE_EXPAND_FILL; btn_sync.custom_minimum_size = Vector2(0, 52)
	btn_sync.connect("pressed", func():
		emit_signal("log_requested", "📤 Synchronisation pensées…")
		Thought_Cache.sync_to_udrive() if Thought_Cache.has_method("sync_to_udrive") else null)
	udrive_hb.add_child(btn_sync)
	var btn_pick := Button.new(); btn_pick.text = "📎 Bibliothèque"
	btn_pick.size_flags_horizontal = SIZE_EXPAND_FILL; btn_pick.custom_minimum_size = Vector2(0, 52)
	btn_pick.connect("pressed", func():
		var fd := FileDialog.new(); fd.file_mode = FileDialog.FILE_MODE_OPEN_FILE
		fd.access = FileDialog.ACCESS_FILESYSTEM; fd.use_native_dialog = true
		# Libérer après usage — sans ça chaque clic crée un FileDialog orphelin en RAM
		fd.connect("file_selected", func(path: String): _on_file_for_udrive(path); fd.queue_free())
		fd.connect("canceled", func(): fd.queue_free())
		fd.connect("close_requested", func(): fd.queue_free())
		get_tree().root.add_child(fd); fd.popup_centered_ratio(0.92))
	udrive_hb.add_child(btn_pick)
	var status := Label.new(); status.name = "UDriveStatus"
	status.text = "— aucune sync en attente —"
	status.add_theme_font_size_override("font_size", UI_Theme._get_scaled_size(13))
	status.modulate = UI_Theme.text_hint()
	status.autowrap_mode = TextServer.AUTOWRAP_WORD; add_child(status)

func _on_file_for_udrive(path: String):
	var f := FileAccess.open(path, FileAccess.READ)
	if not f: emit_signal("log_requested", "❌ Impossible d'ouvrir le fichier."); return
	var data := f.get_buffer(f.get_length()); f.close()
	var filename := path.get_file()
	UPlanet_API.upload_to_udrive(data, filename)
	emit_signal("log_requested", "📤 Upload en cours : " + filename)

func _build_log_section():
	UI_Theme.add_section_title(self, "📋 JOURNAL")
	var log_display := RichTextLabel.new(); log_display.name = "InlineLog"
	log_display.bbcode_enabled = true; log_display.fit_content = true
	log_display.custom_minimum_size = Vector2(0, 180)
	log_display.scroll_following = true; add_child(log_display)
