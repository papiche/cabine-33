class_name TabProfil
extends VBoxContainer
# Onglet ⚛ PROFIL — auto-contenu, signaux vers Main_UI pour les actions transverses.
# class_name permet l'instanciation directe : TabProfil.new()

signal log_requested(msg: String)
signal toast_requested(msg: String)
signal share_resonance_requested
signal cosmic_card_requested
signal preview_instrument_requested  # déclenche un ping solo dans l'orchestre
signal reset_requested               # demande de remise à zéro de l'app

# Données biométriques transmises par HookScreen — lues lors de la forge
var hook_birth_unix:      int   = 0
var hook_birth_sex:       int   = 0
var hook_birth_lat:       float = 0.0
var hook_birth_lon:       float = 0.0
var hook_birth_weight:    float = 3.5
var hook_birth_height:    float = 170.0
var hook_conception_unix: int   = 0
var hook_conception_lat:  float = 0.0
var hook_conception_lon:  float = 0.0

# ─────────────────────────────────────────────────────────────
# POINT D'ENTRÉE
# ─────────────────────────────────────────────────────────────

func _exit_tree():
	# Déconnecte proprement les signaux d'Autoloads pour éviter les callbacks orphelins
	_disconnect_autoload_signals()

func _disconnect_autoload_signals():
	if Nostr_Identity.relay_list_updated.is_connected(_on_relay_list_updated):
		Nostr_Identity.relay_list_updated.disconnect(_on_relay_list_updated)

func build():
	_disconnect_autoload_signals()
	for child in get_children(): child.queue_free()
	_lbl_title(self, "⚛  ATOM4LOVE", 28, UI_Theme.accent_color())

	if not Player_Origin.is_initialized:
		var welcome := _make_panel_box()
		_lbl_title(welcome, "Trouvez vos âmes sœurs cosmiques", 18, UI_Theme.accent_color())
		_lbl(welcome, "ATOM4LOVE détecte en temps réel les personnes proches dont la fréquence de naissance résonne avec la vôtre — sans données personnelles en ligne.", 14, UI_Theme.text_secondary())
		_lbl(welcome, "Votre identité (MULTIPASS) est calculée uniquement depuis votre date, heure, lieu et poids de naissance. Elle n'est stockée nulle part — elle est dans les étoiles.", 13, UI_Theme.text_hint())
		add_child(HSeparator.new())
		_build_multipass_section()
	else:
		_build_metrics_header()  # Header permanent : KIN + φ_i + pureté
		add_child(HSeparator.new())
		_build_identity_card()
		add_child(HSeparator.new())
		_build_birth_locked()    # Données de naissance verrouillées (SALT)
		add_child(HSeparator.new())
		_build_conception_editable()  # Données de conception éditables (PEPPER)
		add_child(HSeparator.new())
		_lbl_section(self, "📡 MULTIPASS")
		_build_nostr_section()
		add_child(HSeparator.new())

func refresh():
	build()

func prefill_from_hook(data: Dictionary):
	hook_birth_unix      = data.get("birth_unix", 0)
	hook_birth_sex       = data.get("sex", 0)
	hook_birth_lat       = data.get("birth_lat", 0.0)
	hook_birth_lon       = data.get("birth_lon", 0.0)
	hook_birth_weight    = data.get("birth_weight", 3.5)
	hook_birth_height    = data.get("height_cm", 170.0)
	hook_conception_unix = data.get("conception_unix", 0)
	hook_conception_lat  = data.get("conception_lat", 0.0)
	hook_conception_lon  = data.get("conception_lon", 0.0)

# ─────────────────────────────────────────────────────────────
# CARTE IDENTITÉ
# ─────────────────────────────────────────────────────────────

func _build_metrics_header():
	# Header compact toujours en haut — KIN Maya + métriques clés + pureté vibratoire
	var h := _make_panel_box()
	var precision := Player_Origin.calculate_vibrational_precision()

	# Ligne 1 : KIN + couleur + sceau
	if Player_Origin.birth_unix > 0:
		var kd: Dictionary = Kin_Maya.calc_kin_unix(Player_Origin.birth_unix)
		if not kd.is_empty():
			var ki: int = kd.get("kin", 0)
			var tc := UI_Theme.text_positive() if precision >= 90 else (UI_Theme.text_warm() if precision >= 60 else Color(1.0, 0.4, 0.4))
			_lbl_title(h, "⚛ KIN %d — %s %s" % [ki, kd.get("color_fr",""), kd.get("glyph_fr","")], 17, tc)
			_lbl(h, "Tonalité %d %s" % [kd.get("ti",0)+1, kd.get("tone_fr","")], 12, UI_Theme.text_secondary())

	# Ligne 2 : φ_i + ω_bio côte à côte
	if Player_Origin.has_atom4love_profile():
		var metrics_hb := _hbox(16)
		var lm1 := Label.new(); lm1.text = "φ_i = %.5f" % Player_Origin.personal_phase
		lm1.add_theme_font_size_override("font_size", UI_Theme._get_scaled_size(13))
		lm1.modulate = UI_Theme.text_positive(); metrics_hb.add_child(lm1)
		var lm2 := Label.new(); lm2.text = "ω = %.1f Hz" % Player_Origin.omega_bio
		lm2.add_theme_font_size_override("font_size", UI_Theme._get_scaled_size(13))
		lm2.modulate = UI_Theme.accent_color(); metrics_hb.add_child(lm2)

	# Pureté Vibratoire — barre + % + indication d'amélioration possible
	var prec_color := UI_Theme.text_positive() if precision >= 90 else (UI_Theme.text_warm() if precision >= 60 else Color(1.0, 0.4, 0.4))
	_lbl_title(h, "📊 Pureté Vibratoire : %d%%" % precision, 15, prec_color)
	var prec_bar := ProgressBar.new()
	prec_bar.max_value = 100; prec_bar.value = precision
	prec_bar.custom_minimum_size = Vector2(0, 14); h.add_child(prec_bar)
	if precision < 100:
		_lbl(h, "💡 Précisez la date et le lieu de conception pour améliorer ce score", 11, UI_Theme.text_hint())

func _build_identity_card():
	# Identité décentralisée — uniquement npub/email/portail (métriques sont dans header)
	var id_panel := _make_panel_box()
	_lbl(id_panel, "📡 " + Player_Origin.user_npub.substr(0, 16) + "…" + Player_Origin.user_npub.right(4), 13, UI_Theme.bar_color(false))
	_lbl(id_panel, "📧 " + Player_Origin.user_email, 13)

	# Portail Goldberg (seule info non dupliquée)
	if Player_Origin.origin_pentagon_id >= 0:
		var pnames := ["Pôle Nord","Pôle Sud","Orion","Aldébaran","Sirius","Véga",
			"Antarès","Fomalhaut","Achernar","Rigel","Capella","Deneb"]
		var pn: String = pnames[Player_Origin.origin_pentagon_id] if Player_Origin.origin_pentagon_id < pnames.size() else "P%d" % Player_Origin.origin_pentagon_id
		# GPS 0,0 = Atlantique équatorial — afficher "Éther" plutôt qu'un portail géographique trompeur
		var birth_no_gps := Player_Origin.birth_lat == 0.0 and Player_Origin.birth_lon == 0.0
		var portal_txt := "⬡ Portail d'Origine : Éther (non ancré)" if birth_no_gps else "⬡ Portail d'Origine : %s" % pn
		_lbl(id_panel, portal_txt, 12, UI_Theme.text_warm() if not birth_no_gps else UI_Theme.text_hint())

	# Note de pureté (hint uniquement, pas de barre = déjà dans header)
	var precision := Player_Origin.calculate_vibrational_precision()
	if precision < 100:
		_lbl(id_panel, "💡 Précision %d%% — affinez les données de conception pour progresser" % precision, 11, UI_Theme.text_hint())

	# Voyageur cosmique
	var cl := Player_Origin.conception_lat; var cL := Player_Origin.conception_lon
	var bl := Player_Origin.birth_lat;     var bL := Player_Origin.birth_lon
	if (cl != 0.0 or cL != 0.0) and (bl != 0.0 or bL != 0.0):
		var dist := Phi2X_Math.haversine_distance(cl, cL, bl, bL)
		if dist > 100.0:
			_lbl(id_panel, "☄️ VOYAGEUR COSMIQUE — %d km entre conception et naissance" % int(dist), 12, Color(0.8, 0.4, 1.0))

	# ── Actions compactes (une seule ligne chacune) ───────────────────────────
	var act_hb := _hbox(8)
	var btn_share := Button.new(); btn_share.text = "🔗 Partager"
	btn_share.custom_minimum_size = Vector2(0, 44)
	btn_share.size_flags_horizontal = SIZE_EXPAND_FILL
	btn_share.connect("pressed", Callable(self, "_on_share")); act_hb.add_child(btn_share)
	var btn_card := Button.new(); btn_card.text = "📸 Carte"
	btn_card.custom_minimum_size = Vector2(0, 44)
	btn_card.size_flags_horizontal = SIZE_EXPAND_FILL
	btn_card.connect("pressed", Callable(self, "_on_export_card")); act_hb.add_child(btn_card)
	var btn_nostr := Button.new(); btn_nostr.text = "🌌 NOSTR"
	btn_nostr.custom_minimum_size = Vector2(0, 44)
	btn_nostr.size_flags_horizontal = SIZE_EXPAND_FILL
	btn_nostr.connect("pressed", Callable(self, "_on_tease_nostr")); act_hb.add_child(btn_nostr)

	# ── Instrument cosmique compact ───────────────────────────────────────────
	add_child(HSeparator.new())
	var mic_hb := _hbox(10)
	var mic_info := Label.new()
	mic_info.name = "InstLbl"
	var inst_txt := "🎙️ Voix samplée" if Voice_Sampler.inst_id == Voice_Sampler.INST_VOICE else "🎵 Synthé pur"
	mic_info.text = "%s  ω=%.0f Hz" % [inst_txt, Player_Origin.omega_bio]
	mic_info.add_theme_font_size_override("font_size", UI_Theme._get_scaled_size(13))
	mic_info.size_flags_horizontal = SIZE_EXPAND_FILL; mic_hb.add_child(mic_info)
	var btn_mic := Button.new(); btn_mic.name = "MicBtn"
	btn_mic.text = "🔴 Enregistrer"
	btn_mic.custom_minimum_size = Vector2(0, 44)
	btn_mic.connect("pressed", Callable(self, "_on_record_voice")); mic_hb.add_child(btn_mic)

func _on_share():    emit_signal("share_resonance_requested")
func _on_export_card(): emit_signal("cosmic_card_requested")

func _on_reset_multipass():
	emit_signal("reset_requested")

var _mic_pending_after_permission: bool = false

func _on_record_voice():
	var btn := find_child("MicBtn", true, false) as Button
	if OS.has_feature("android") and \
			not OS.get_granted_permissions().has("android.permission.RECORD_AUDIO"):
		_mic_pending_after_permission = true
		if btn: btn.text = "📲 Autorisation micro..."; btn.disabled = true
		emit_signal("log_requested", "📲 Autorisez le micro dans la popup Android.")
		# Connexion explicite au signal MainLoop (Godot 4 — non automatique sur les nodes non-root)
		var ml := Engine.get_main_loop()
		if ml and not ml.is_connected("on_request_permissions_result",
				Callable(self, "_on_request_permissions_result")):
			ml.connect("on_request_permissions_result",
				Callable(self, "_on_request_permissions_result"), CONNECT_ONE_SHOT)
		OS.request_permission("android.permission.RECORD_AUDIO")
		return
	_start_recording_now()

func _on_request_permissions_result(permission: String, granted: bool):
	if permission != "android.permission.RECORD_AUDIO": return
	var btn := find_child("MicBtn", true, false) as Button
	if granted and _mic_pending_after_permission:
		_mic_pending_after_permission = false
		emit_signal("log_requested", "✅ Micro autorisé — démarrage…")
		_start_recording_now()
	elif not granted:
		_mic_pending_after_permission = false
		if btn: btn.text = "🔴 Enregistrer"; btn.disabled = false
		emit_signal("log_requested", "❌ Permission micro refusée — activez-la dans Paramètres > Applications > ATOM4LOVE.")

func _start_recording_now():
	var btn := find_child("MicBtn", true, false) as Button
	if btn: btn.text = "⏳ Enregistrement..."; btn.disabled = true
	emit_signal("log_requested", "🎤 Chantez «Aaaa» ou «Ommm» pendant 1 seconde…")
	# Déconnecter d'abord — protège contre le double-clic rapide qui cause
	# "Signal already connected" si le précédent ONE_SHOT n'a pas encore tiré
	if Voice_Sampler.wavetable_ready.is_connected(_on_wavetable_ready):
		Voice_Sampler.wavetable_ready.disconnect(_on_wavetable_ready)
	if Voice_Sampler.recording_failed.is_connected(_on_recording_failed):
		Voice_Sampler.recording_failed.disconnect(_on_recording_failed)
	Voice_Sampler.wavetable_ready.connect(_on_wavetable_ready, CONNECT_ONE_SHOT)
	Voice_Sampler.recording_failed.connect(_on_recording_failed, CONNECT_ONE_SHOT)
	Voice_Sampler.start_recording()

func _on_wavetable_ready(_wt: PackedFloat32Array):
	var btn := find_child("MicBtn", true, false) as Button
	if btn: btn.text = "✅ Voix samplée ! (Recommencer)"; btn.disabled = false
	emit_signal("log_requested", "🎵 Votre timbre cosmique est capturé — il résonnera dans la Chorale Galactique !")
	# Bouton ÉCOUTER — aperçu immédiat de la voix quantique
	var mic_panel := find_child("MicBtn", true, false)
	if is_instance_valid(mic_panel) and is_instance_valid(mic_panel.get_parent()):
		var btn_listen := Button.new()
		btn_listen.name = "ListenBtn"
		btn_listen.text = "▶ ÉCOUTER MA VOIX QUANTIQUE"
		btn_listen.custom_minimum_size.y = UI_Theme.scale_px(48)
		btn_listen.pressed.connect(func(): emit_signal("preview_instrument_requested"))
		# Remplacer un éventuel ancien bouton ÉCOUTER
		var old := mic_panel.get_parent().find_child("ListenBtn", false, false)
		if old: old.queue_free()
		mic_panel.get_parent().add_child(btn_listen)
	# Republier le certificat ATOM4LOVE avec inst_id=1 (voix)
	if Player_Origin.is_initialized:
		Nostr_Identity.publish_atom4love_cert()
	# Rafraîchir le label d'instrument
	var inst_lbl := find_child("InstLbl", true, false) as Label
	if inst_lbl:
		inst_lbl.text = "🎙️ Voix samplée — ω_bio %.2f Hz" % Player_Origin.omega_bio

func _on_recording_failed(reason: String):
	var btn := find_child("MicBtn", true, false) as Button
	if btn: btn.text = "❌ Erreur — Réessayer"; btn.disabled = false
	emit_signal("log_requested", "⚠ Enregistrement échoué : " + reason)

func _on_join_cooperative():
	OS.shell_open("https://opencollective.com/monnaie-libre/contribute")
	emit_signal("log_requested", "🌍 Ouverture de opencollective.com/monnaie-libre — G1FabLab")

func _on_tease_nostr():
	if not Player_Origin.is_initialized:
		emit_signal("log_requested", "⚠ MULTIPASS requis pour publier sur NOSTR.")
		return
	Nostr_Identity.publish_tease()
	emit_signal("toast_requested", "🌌 Note de résonance publiée sur les relays publics !")
func _on_family_quest_pressed():
	emit_signal("log_requested", "🧬 Fonctionnalité Quête des Origines à venir.")

# ─────────────────────────────────────────────────────────────
# SECTION MULTIPASS (premier lancement)
# ─────────────────────────────────────────────────────────────

var _is_polling_gps: bool = false  # Verrou anti-spam du polling GPS

func _build_multipass_section():
	_lbl_section(self, "✅ CRÉER MON MULTIPASS")

	# Récapitulatif des données saisies — confirmation avant création
	if hook_birth_unix > 0:
		var summary := _make_panel_box()
		_lbl(summary, "Vérifiez vos informations avant de créer votre identifiant :", 13, UI_Theme.text_secondary())
		summary.add_child(HSeparator.new())

		var dt := Time.get_datetime_dict_from_unix_time(hook_birth_unix)
		_lbl(summary, "📅 Naissance : %02d/%02d/%04d  à  %02dh%02d" % [dt.day, dt.month, dt.year, dt.hour, dt.minute], 14, UI_Theme.text_color())
		if hook_birth_lat != 0.0 or hook_birth_lon != 0.0:
			_lbl(summary, "📍 Lieu : %.4f°N, %.4f°E" % [hook_birth_lat, hook_birth_lon], 13, UI_Theme.text_color())
		else:
			_lbl(summary, "📍 Lieu de naissance : non renseigné", 13, UI_Theme.text_hint())
		_lbl(summary, "⚖ Poids : %.1f kg   ·   %s" % [hook_birth_weight, "Homme" if hook_birth_sex == 0 else "Femme"], 13, UI_Theme.text_color())

		if hook_birth_unix > 0:
			var kd: Dictionary = Kin_Maya.calc_kin_unix(hook_birth_unix)
			if not kd.is_empty():
				_lbl(summary, "🔢 KIN %d — %s %s" % [kd.get("kin",0), kd.get("color_fr",""), kd.get("glyph_fr","")], 15, UI_Theme.text_warm())

		if hook_conception_unix > 0:
			var cd := Time.get_datetime_dict_from_unix_time(hook_conception_unix)
			_lbl(summary, "🌱 Conception estimée : %02d/%02d/%04d" % [cd.day, cd.month, cd.year], 12, UI_Theme.text_hint())

		summary.add_child(HSeparator.new())
		var precision := _compute_multipass_precision()
		var prec_color := UI_Theme.text_positive() if precision >= 90 else (UI_Theme.text_warm() if precision >= 60 else Color(1.0, 0.4, 0.4))
		_lbl(summary, "Fiabilité du profil : %d%%" % precision, 13, prec_color)
		var prec_bar := ProgressBar.new()
		prec_bar.max_value = 100; prec_bar.value = precision
		prec_bar.custom_minimum_size = Vector2(0, 10); summary.add_child(prec_bar)

	add_child(HSeparator.new())
	_lbl(self, "📧 Email — votre identifiant sur le réseau", 15)
	_lbl(self, "Vous recevrez vos correspondances KIN par email chaque semaine.", 12, UI_Theme.text_hint())
	UI_Theme.add_input(self, "MultipassEmail", "votre@email.com", 66, LineEdit.KEYBOARD_TYPE_EMAIL_ADDRESS)
	add_child(HSeparator.new())

	var btn_edit := Button.new()
	btn_edit.text = "◀ Modifier mes données de naissance"
	btn_edit.custom_minimum_size = Vector2(0, 48)
	btn_edit.add_theme_font_size_override("font_size", UI_Theme._get_scaled_size(14))
	btn_edit.connect("pressed", Callable(self, "_on_reset_multipass"))
	add_child(btn_edit)
	add_child(HSeparator.new())

	var status_lbl := Label.new(); status_lbl.name = "MultipassStatus"
	status_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_lbl.add_theme_font_size_override("font_size", UI_Theme._get_scaled_size(14))
	status_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	add_child(status_lbl)

	var btn_forge := UI_Theme.add_styled_button(self, "✅ CRÉER MON MULTIPASS",
		Callable(self, "_on_forge_pressed"), false)
	btn_forge.name = "ForgeBtn"
	btn_forge.custom_minimum_size = Vector2(0, 76)
	btn_forge.add_theme_font_size_override("font_size", UI_Theme._get_scaled_size(20))

func _compute_multipass_precision() -> int:
	if hook_birth_unix <= 0: return 0
	var score := 40
	var dt := Time.get_datetime_dict_from_unix_time(hook_birth_unix)
	if dt.hour != 12 or dt.minute != 0: score += 15
	if abs(hook_birth_lat) > 0.1 or abs(hook_birth_lon) > 0.1: score += 20
	if hook_birth_weight != 3.5: score += 15
	if abs(hook_conception_lat) > 0.1 or abs(hook_conception_lon) > 0.1: score += 10
	return clamp(score, 0, 100)

# ─────────────────────────────────────────────────────────────
# FORGE MULTIPASS
# ─────────────────────────────────────────────────────────────

func _on_forge_pressed():
	var email_inp := find_child("MultipassEmail", true, false) as LineEdit
	var status    := find_child("MultipassStatus", true, false) as Label
	if not email_inp or email_inp.text.strip_edges() == "":
		if status: status.text = "⚠ L'email est requis."; status.modulate = Color(1, 0.3, 0.3)
		return
	if hook_birth_unix <= 0:
		if status: status.text = "⚠ Données de naissance manquantes."; status.modulate = Color(1, 0.3, 0.3)
		return

	var dt := Time.get_datetime_dict_from_unix_time(hook_birth_unix)
	var sy_v: int = dt.year; var sm_v: int = dt.month; var sd_v: int = dt.day
	var hour: int = dt.hour; var min_v: int = dt.minute
	var blat := hook_birth_lat; var blon := hook_birth_lon
	var weight := hook_birth_weight; var sex := hook_birth_sex
	var height := hook_birth_height if hook_birth_height > 50.0 else 170.0

	# Conception — depuis HookScreen ou calculée
	var conception_unix := hook_conception_unix if hook_conception_unix > 0 else Phi2X_Math.compute_conception_unix(hook_birth_unix, weight)
	var clat := hook_conception_lat if hook_conception_lat != 0.0 else blat
	var clon := hook_conception_lon if hook_conception_lon != 0.0 else blon

	# UTC dérivé depuis la longitude
	Player_Origin.conception_utc_offset_h = roundf(clon / 15.0) if clon != 0.0 else 0.0
	Player_Origin.birth_utc_offset_h = roundf(blon / 15.0) if blon != 0.0 else 0.0

	# Dérivation SALT / PEPPER
	Player_Origin.height_cm = height  # propagé avant save_multipass via set_birth_profile
	Player_Origin.user_salt   = Phi2X_Math.derive_multipass_salt(sy_v, sm_v, sd_v, hour, min_v, blat, blon, sex, weight, 50, int(height))
	Player_Origin.user_pepper = Phi2X_Math.derive_multipass_pepper(conception_unix, clat, clon, weight, 50)

	# GPS actuel (ancrage réseau UMAP)
	var gps := SpaceTime_Manager.current_gps
	var lat := snappedf(gps.x, 0.01); var lon := snappedf(gps.y, 0.01)

	var birth_dt    := "%04d-%02d-%02dT%02d:%02d" % [sy_v, sm_v, sd_v, hour, min_v]
	var birth_place := "%.4f, %.4f" % [blat, blon] if (blat != 0.0 or blon != 0.0) else ""
	var cd := Time.get_datetime_dict_from_unix_time(conception_unix)
	var conception_dt    := "%04d-%02d-%02dT%02d:%02d" % [cd.year, cd.month, cd.day, cd.hour, cd.minute]
	var conception_place := "%.4f, %.4f" % [clat, clon] if (clat != 0.0 or clon != 0.0) else birth_place

	UI_Theme.vibrate(50)
	if status: status.text = "⏳ Connexion à Astroport…"; status.modulate = Color(0.8, 0.8, 0.8)
	var fb := find_child("ForgeBtn", true, false) as Button
	if fb: fb.disabled = true
	UPlanet_API.forge_multipass(email_inp.text.strip_edges(), Player_Origin.user_salt,
		Player_Origin.user_pepper, lat, lon, OS.get_locale().substr(0, 2).to_lower(),
		birth_dt, birth_place, str(weight) if weight > 0 else "", conception_dt, conception_place)

# ─────────────────────────────────────────────────────────────
# SECTION NAISSANCE & ATOM4LOVE
# ─────────────────────────────────────────────────────────────

func _build_birth_locked():
	# Données de naissance — VERROUILLÉES après création du MULTIPASS
	# Elles définissent le SALT cryptographique : les modifier changerait l'identité
	_lbl_section(self, "🔒 DONNÉES DE NAISSANCE — Identité fixée")
	var p := _make_panel_box()
	_lbl(p, "Ces données définissent votre SALT cryptographique. Elles ne peuvent plus être modifiées sans recréer un nouveau MULTIPASS.", 11, UI_Theme.text_hint())
	p.add_child(HSeparator.new())

	# Date et heure
	if Player_Origin.birth_unix > 0:
		var dt := Time.get_datetime_dict_from_unix_time(Player_Origin.birth_unix)
		_lbl(p, "📅 Date  %02d/%02d/%04d  %02d:%02d" % [dt.day, dt.month, dt.year, dt.hour, dt.minute], 14, UI_Theme.text_color())
	else:
		_lbl(p, "📅 Date de naissance — non renseignée", 14, UI_Theme.text_secondary())

	# Lieu
	if Player_Origin.birth_lat != 0.0 or Player_Origin.birth_lon != 0.0:
		_lbl(p, "📍 Lieu  %.4f°N  %.4f°E" % [Player_Origin.birth_lat, Player_Origin.birth_lon], 14, UI_Theme.text_color())
	else:
		_lbl(p, "📍 Lieu de naissance — non renseigné", 14, UI_Theme.text_secondary())

	# Poids + polarité
	var morph_line := ""
	if Player_Origin.weight_kg > 0.5:
		morph_line += "⚖ %.1f kg" % Player_Origin.weight_kg
	morph_line += "  |  " + Player_Origin.get_polarity_label()
	_lbl(p, morph_line, 13, UI_Theme.text_secondary())

func _build_conception_editable():
	# Données de conception — éditables à tout moment (améliorent la Pureté Vibratoire)
	_lbl_section(self, "✏️ DONNÉES DE CONCEPTION — Affiner la Pureté")
	_lbl(self, "Ces données définissent votre PEPPER cryptographique. Précisez-les pour augmenter votre score de Pureté Vibratoire sans toucher à votre identité.", 11, UI_Theme.text_hint())

	# Portail d'Origine dans le Polyèdre de Goldberg
	if Player_Origin.origin_pentagon_id >= 0:
		var pnames := ["Pôle Nord","Pôle Sud","Orion","Aldébaran","Sirius","Véga",
			"Antarès","Fomalhaut","Achernar","Rigel","Capella","Deneb"]
		var pname: String = pnames[Player_Origin.origin_pentagon_id] if Player_Origin.origin_pentagon_id < pnames.size() else "Portail %d" % Player_Origin.origin_pentagon_id
		var no_gps := Player_Origin.birth_lat == 0.0 and Player_Origin.birth_lon == 0.0
		var portal_txt2 := "⬡ Portail d'Origine : Éther — renseignez votre lieu de naissance pour l'ancrer" if no_gps else "⬡ Portail d'Origine : %s (P%d)" % [pname, Player_Origin.origin_pentagon_id]
		_lbl(self, portal_txt2, 13, UI_Theme.text_hint() if no_gps else UI_Theme.text_warm())

	# Date de conception
	_lbl(self, "📅 Date de conception", 14, UI_Theme.text_secondary())
	_lbl(self, "Pré-rempli automatiquement (naissance − 280 j.). Corrigez si connu.", 11, UI_Theme.text_hint())
	var conc_cb := Callable(self, "_on_conception_date_changed")
	var conc_date_hb := _hbox(6)
	_build_date_fields(conc_date_hb, [["ConceptionYear","Année",4], ["ConceptionMonth","Mois",2], ["ConceptionDay","Jour",2]], conc_cb)
	_lbl(self, "⏰ Heure locale de conception", 13, UI_Theme.text_secondary())
	var conc_time_hb := _hbox(6)
	_build_date_fields(conc_time_hb, [["ConceptionHour","Heure",2,"0"], ["ConceptionMin","Minute",2,"00"]], conc_cb)
	if Player_Origin.conception_unix > 0:
		var cd := Time.get_datetime_dict_from_unix_time(Player_Origin.conception_unix)
		for pair in [["ConceptionYear",cd.year],["ConceptionMonth",cd.month],["ConceptionDay",cd.day],
					 ["ConceptionHour",cd.hour],["ConceptionMin",cd.minute]]:
			var le := find_child(pair[0], true, false) as LineEdit
			if le: le.text = str(pair[1])

	# Fuseau UTC de conception
	_lbl(self, "🌐 Fuseau UTC à la conception", 12, UI_Theme.text_hint())
	var cutc_row := _hbox(10)
	var cutc_prefix := Label.new(); cutc_prefix.text = "UTC"
	cutc_prefix.add_theme_font_size_override("font_size", UI_Theme._get_scaled_size(15))
	cutc_prefix.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cutc_row.add_child(cutc_prefix)
	var cutc_inp := UI_Theme.add_input(cutc_row, "ConceptionUTCOffset", "+2 ou −4", 58, LineEdit.KEYBOARD_TYPE_NUMBER_DECIMAL)
	cutc_inp.size_flags_horizontal = 0; cutc_inp.custom_minimum_size.x = UI_Theme.scale_px(130)
	if Player_Origin.conception_utc_offset_h != 0.0:
		cutc_inp.text = "%.1f" % Player_Origin.conception_utc_offset_h
	elif Player_Origin.conception_lon != 0.0:
		cutc_inp.text = "%.0f" % roundf(Player_Origin.conception_lon / 15.0)

	# Lieu de conception
	_lbl(self, "📍 Lieu de conception  (défaut = lieu de naissance)", 14, UI_Theme.text_secondary())
	var conc_city_hb := _hbox(8)
	UI_Theme.add_input(conc_city_hb, "ConceptionCityInput", "Ex: Paris, Fort-de-France…", 48)
	var conc_btn := Button.new(); conc_btn.text = "🔍"
	conc_btn.custom_minimum_size = Vector2(UI_Theme.scale_px(48), UI_Theme.scale_px(48))
	conc_btn.connect("pressed", Callable(self, "_on_conception_city_search")); conc_city_hb.add_child(conc_btn)
	var conc_loc_lbl := Label.new(); conc_loc_lbl.name = "ConceptionLocLabel"
	conc_loc_lbl.add_theme_font_size_override("font_size", UI_Theme._get_scaled_size(12))
	conc_loc_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	conc_loc_lbl.modulate = UI_Theme.text_hint(); conc_loc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	add_child(conc_loc_lbl)
	var conc_hb := _hbox(6)
	var clat_i := UI_Theme.add_input(conc_hb, "ConceptionLat", "Latitude", 44, LineEdit.KEYBOARD_TYPE_NUMBER_DECIMAL)
	var clon_i := UI_Theme.add_input(conc_hb, "ConceptionLon", "Longitude", 44, LineEdit.KEYBOARD_TYPE_NUMBER_DECIMAL)
	var clat_d := Player_Origin.conception_lat if (Player_Origin.conception_lat != 0.0 or Player_Origin.conception_lon != 0.0) else Player_Origin.birth_lat
	var clon_d := Player_Origin.conception_lon if (Player_Origin.conception_lat != 0.0 or Player_Origin.conception_lon != 0.0) else Player_Origin.birth_lon
	if clat_d != 0.0 or clon_d != 0.0:
		clat_i.text = "%.4f" % clat_d; clon_i.text = "%.4f" % clon_d
		conc_loc_lbl.text = "📌 %.4f, %.4f" % [clat_d, clon_d]

	# Bouton de mise à jour (recalcul sans toucher au MULTIPASS)
	var btn_upd := UI_Theme.add_styled_button(self,
		"🔄 RECALCULER MA RÉSONANCE  (sans changer mon MULTIPASS)",
		Callable(self, "_on_birth_save"), false)
	btn_upd.custom_minimum_size.y = UI_Theme.scale_px(56)
	var result_lbl := Label.new(); result_lbl.name = "BirthResultLabel"
	result_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_lbl.add_theme_font_size_override("font_size", UI_Theme._get_scaled_size(13))
	result_lbl.modulate = UI_Theme.text_positive(); result_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	if Player_Origin.has_atom4love_profile():
		result_lbl.text = "✅ φ_i = %.5f  |  ω_bio = %.2f Hz" % [Player_Origin.personal_phase, Player_Origin.omega_bio]
	add_child(result_lbl)

func _on_birth_date_changed(_v: String):
	_refresh_birth_info()
	# Quand la date de naissance change, pré-remplir la date de conception auto-calculée
	# (seulement si l'utilisateur n'a pas saisi une date manuelle)
	var b := _get_birth_unix()
	if b > 0 and not Player_Origin.conception_datetime_user_set:
		var c := Phi2X_Math.compute_conception_unix(b)
		var cd := Time.get_datetime_dict_from_unix_time(c)
		for pair in [["ConceptionYear",cd.year],["ConceptionMonth",cd.month],["ConceptionDay",cd.day],
					 ["ConceptionHour",cd.hour],["ConceptionMin",cd.minute]]:
			var le := find_child(pair[0], true, false) as LineEdit
			if le and not le.has_focus(): le.text = str(pair[1])

func _on_conception_date_changed(_v: String):
	# Marque que l'utilisateur a explicitement modifié la date de conception
	Player_Origin.conception_datetime_user_set = true

func _refresh_birth_info():
	var conc_lbl := find_child("ConceptionLabel", true, false) as Label
	var kin_lbl  := find_child("KinMayaLabel",   true, false) as Label
	var b := _get_birth_unix()
	if b > 0:
		if conc_lbl:
			var c := Phi2X_Math.compute_conception_unix(b)
			var cd := Time.get_datetime_dict_from_unix_time(c)
			conc_lbl.text = "🌱 Conception ≈ %04d-%02d-%02d  (−280 j.)" % [cd.year, cd.month, cd.day]
		if kin_lbl:
			var sy := find_child("BirthYear",  true, false) as LineEdit
			var sm := find_child("BirthMonth", true, false) as LineEdit
			var sd := find_child("BirthDay",   true, false) as LineEdit
			if sy and sm and sd and sy.text.is_valid_int() and sm.text.is_valid_int() and sd.text.is_valid_int():
				var k: Dictionary = Kin_Maya.calc_kin(int(sy.text), int(sm.text), int(sd.text))
				kin_lbl.text = "🌀 " + Kin_Maya.format_kin_short(k)
	else:
		if conc_lbl: conc_lbl.text = "🌱 Conception : saisissez la date"

func _get_birth_unix() -> int:
	# Identité verrouillée après MULTIPASS : ne pas relire les champs (ils n'existent plus)
	if Player_Origin.is_initialized and Player_Origin.birth_unix > 0:
		return Player_Origin.birth_unix
	var sy := find_child("BirthYear",  true, false) as LineEdit
	var sm := find_child("BirthMonth", true, false) as LineEdit
	var sd := find_child("BirthDay",   true, false) as LineEdit
	var sh := find_child("BirthHour",  true, false) as LineEdit
	var sn := find_child("BirthMin",   true, false) as LineEdit
	if not (sy and sm and sd): return -1
	var y: int  = int(sy.text) if sy.text.is_valid_int() else 0
	# Correction saisie courte : "05"→2005, "85"→1985, "00"→2000
	if y > 0 and y < 100: y += (2000 if y < 30 else 1900)
	var mo: int = int(sm.text) if sm.text.is_valid_int() else 1
	var d: int  = int(sd.text) if sd.text.is_valid_int() else 1
	var hh: int = int(sh.text) if sh and sh.text.is_valid_int() else 12
	var mi: int = int(sn.text) if sn and sn.text.is_valid_int() else 0
	return Phi2X_Math.validate_date(y, mo, d, hh, mi)

func _set_birth_fields(y: int, mo: int, d: int, h: int, mi: int):
	for pair in [["BirthYear",y],["BirthMonth",mo],["BirthDay",d],["BirthHour",h],["BirthMin",mi]]:
		var le := find_child(pair[0], true, false) as LineEdit
		if le: le.text = str(pair[1])

func _on_birth_save():
	var bx  := find_child("BtnBoy",          true, false) as Button
	var hi  := find_child("HeightInput",     true, false) as LineEdit
	var wi  := find_child("WeightInput",     true, false) as LineEdit
	var rl  := find_child("BirthResultLabel", true, false) as Label
	var li  := find_child("ManualLat",       true, false) as LineEdit
	var lo  := find_child("ManualLon",       true, false) as LineEdit
	var cli := find_child("ConceptionLat",   true, false) as LineEdit
	var clo := find_child("ConceptionLon",   true, false) as LineEdit
	var b_unix := _get_birth_unix()
	if b_unix <= 0:
		if rl: rl.text = "❌ Date invalide."; rl.modulate = Color(1, 0.3, 0.3); return
	# Fallbacks vitaux : si le champ UI est verrouillé (absent), on garde la donnée d'origine
	var blat: float = clamp(float(li.text.replace(",",".").strip_edges()), -90.0, 90.0) if (li and li.text != "") else Player_Origin.birth_lat
	var blon: float = clamp(float(lo.text.replace(",",".").strip_edges()), -180.0, 180.0) if (lo and lo.text != "") else Player_Origin.birth_lon
	var clat: float = clamp(float(cli.text.replace(",",".").strip_edges()), -90.0, 90.0) if (cli and cli.text != "") else 0.0
	var clon: float = clamp(float(clo.text.replace(",",".").strip_edges()), -180.0, 180.0) if (clo and clo.text != "") else 0.0
	var sex: int  = (0 if bx.button_pressed else 1) if bx else Player_Origin.biological_sex
	var h_filled := hi != null and hi.text.strip_edges() != ""
	var w_filled := wi != null and wi.text.strip_edges() != ""
	var h: float  = clamp(float(hi.text.replace(",",".")) if h_filled else Player_Origin.height_cm, 50.0, 280.0)
	var w: float  = clamp(float(wi.text.replace(",",".")) if w_filled else Player_Origin.weight_kg, 20.0, 300.0)
	# Fuseau horaire UTC — estimé depuis birth_lon si champ vide
	var utc_inp := find_child("BirthUTCOffset", true, false) as LineEdit
	var utc_offset: float = 0.0
	if utc_inp and utc_inp.text.strip_edges() != "":
		utc_offset = float(utc_inp.text.replace(",", ".").strip_edges())
	elif blon != 0.0:
		utc_offset = roundf(blon / 15.0)  # estimation solaire si fuseau non saisi
	var pv   := find_child("ParentsVerifiedCheck", true, false) as CheckBox
	Player_Origin.parents_verified = pv.button_pressed if pv else false

	# ── Date/heure/UTC de conception ─────────────────────────────────────────
	# Ces données sont distinctes du MULTIPASS — elles n'affectent que le
	# Pentagone d'Origine dans le Polyèdre de Goldberg (algo ATOM4LOVE uniquement).
	var c_unix := 0
	var cy := find_child("ConceptionYear",  true, false) as LineEdit
	var cm := find_child("ConceptionMonth", true, false) as LineEdit
	var cd := find_child("ConceptionDay",   true, false) as LineEdit
	var ch := find_child("ConceptionHour",  true, false) as LineEdit
	var cn := find_child("ConceptionMin",   true, false) as LineEdit
	if cy and cm and cd and cy.text.is_valid_int():
		var cy_v := int(cy.text); var cm_v := int(cm.text) if cm.text.is_valid_int() else 1
		var cd_v := int(cd.text) if cd.text.is_valid_int() else 1
		var ch_v := int(ch.text) if ch and ch.text.is_valid_int() else 0
		var cn_v := int(cn.text) if cn and cn.text.is_valid_int() else 0
		c_unix = Phi2X_Math.validate_date(cy_v, cm_v, cd_v, ch_v, cn_v)

	var cutc_inp := find_child("ConceptionUTCOffset", true, false) as LineEdit
	var c_utc: float = 0.0
	if cutc_inp and cutc_inp.text.strip_edges() != "":
		c_utc = float(cutc_inp.text.replace(",", ".").strip_edges())
	elif clon != 0.0:
		c_utc = roundf(clon / 15.0)
	Player_Origin.conception_utc_offset_h = c_utc

	Player_Origin.set_birth_profile(b_unix, blat, blon, sex, h, w,
		c_unix if c_unix > 0 else 0, clat, clon, h_filled or w_filled, utc_offset)
	# Persister immédiatement — sinon les données sont perdues au redémarrage
	if Player_Origin.is_initialized:
		Player_Origin.save_multipass()
	if rl:
		rl.modulate = UI_Theme.text_positive()
		rl.text = "✅ φ_i = %.5f  |  ω_bio = %.2f Hz  |  %s" % [
			Player_Origin.personal_phase, Player_Origin.omega_bio, Player_Origin.get_polarity_label()]
	if Player_Origin.is_initialized: Nostr_Identity.publish_atom4love_cert()
	var ka := Kin_Maya.calc_kin_unix(b_unix)
	var anim := get_parent()
	while anim and not anim.has_method("set_kin"): anim = anim.get_parent()
	if anim: anim.call("set_kin", ka, {})  # AtomAnimation si trouvé dans l'arbre
	emit_signal("log_requested", "⚛ Profil ATOM4LOVE calculé. φ_i = %.5f" % Player_Origin.personal_phase)

# ─────────────────────────────────────────────────────────────
# RECHERCHE VILLE (Nominatim)
# ─────────────────────────────────────────────────────────────

func _on_onboard_birth_city_search():
	# Recherche ville pendant l'onboarding (step 1) → remplit BirthActualLat/Lon
	_search_city("OnboardBirthCityInput", "BirthActualLat", "BirthActualLon", "OnboardBirthLocLabel")
	# Pré-remplir aussi la conception avec le même lieu (par défaut = naissance)
	await get_tree().process_frame
	var blat_i := find_child("BirthActualLat", true, false) as LineEdit
	var blon_i := find_child("BirthActualLon", true, false) as LineEdit
	if blat_i and blon_i and blat_i.text != "":
		var clat_f := find_child("ForgeConLat", true, false) as LineEdit
		var clon_f := find_child("ForgeConLon", true, false) as LineEdit
		if clat_f and clat_f.text == "": clat_f.text = blat_i.text
		if clon_f and clon_f.text == "": clon_f.text = blon_i.text

func _on_city_search():
	_search_city("CityInput", "ManualLat", "ManualLon", "BirthLatLonLabel")

func _on_conception_city_search():
	# Si le champ ville conception est vide, utiliser le lieu de naissance comme point de départ
	var city_inp := find_child("ConceptionCityInput", true, false) as LineEdit
	if city_inp and city_inp.text.strip_edges() == "":
		var birth_city := find_child("CityInput", true, false) as LineEdit
		if birth_city and birth_city.text.strip_edges() != "":
			city_inp.text = birth_city.text  # copie la ville de naissance comme suggestion
	_search_city("ConceptionCityInput", "ConceptionLat", "ConceptionLon", "ConceptionLocLabel")

func _search_city(city_field: String, lat_field: String, lon_field: String, lbl_field: String):
	var city_inp := find_child(city_field, true, false) as LineEdit
	var loc_lbl  := find_child(lbl_field,  true, false) as Label
	if not city_inp or city_inp.text.strip_edges() == "": return

	# Désactiver le bouton pendant la recherche (anti double-clic)
	var btn := city_inp.get_parent().find_child("", true, false) as Button
	if not btn:
		for sib in city_inp.get_parent().get_children():
			if sib is Button: btn = sib; break
	if btn: btn.disabled = true

	if loc_lbl: loc_lbl.text = "⏳ Recherche en cours…"

	var http := HTTPRequest.new()
	http.name = "NominatimHTTP_" + city_field
	http.timeout = 8.0  # timeout explicite — Nominatim peut être lent (2-5s normalement)
	add_child(http)

	var url := "https://nominatim.openstreetmap.org/search?q=%s&format=json&limit=1&addressdetails=0" % \
		city_inp.text.strip_edges().uri_encode()
	# User-Agent requis par les ToS Nominatim — sans lui les requêtes sont ralenties/bloquées
	var headers := ["User-Agent: ATOM4LOVE/1.0 (atom4love@copylaradio.com)"]

	http.request_completed.connect(
		Callable(self, "_on_nominatim_result").bind(http, lat_field, lon_field, lbl_field, btn),
		CONNECT_ONE_SHOT)
	if http.request(url, headers) != OK:
		if loc_lbl: loc_lbl.text = "❌ Erreur réseau. Saisissez les coordonnées manuellement."
		if btn: btn.disabled = false
		http.queue_free()

func _on_nominatim_result(result: int, code: int, _h: PackedStringArray, body: PackedByteArray,
		http: HTTPRequest, lat_field: String, lon_field: String, lbl_field: String,
		search_btn):
	if is_instance_valid(http): http.queue_free()
	if search_btn is Button: search_btn.disabled = false
	var loc_lbl := find_child(lbl_field, true, false) as Label
	var lat_inp := find_child(lat_field, true, false) as LineEdit
	var lon_inp := find_child(lon_field, true, false) as LineEdit
	if result == HTTPRequest.RESULT_TIMEOUT:
		if loc_lbl: loc_lbl.text = "⏱ Délai dépassé — réessayez ou saisissez les coordonnées manuellement."; return
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		if loc_lbl: loc_lbl.text = "❌ Introuvable. Saisissez lat/lon manuellement."; return
	var json := JSON.new()
	if json.parse(body.get_string_from_utf8()) != OK:
		if loc_lbl: loc_lbl.text = "❌ Réponse invalide (JSON)."; return
	var data = json.get_data()
	if not (data is Array) or data.is_empty():
		if loc_lbl: loc_lbl.text = "❌ Ville inconnue — essayez en anglais (ex: Paris, Fort-de-France)."; return
	var entry = data[0]
	var blat: float = float(str(entry.get("lat", "0")))
	var blon: float = float(str(entry.get("lon", "0")))
	if lat_inp: lat_inp.text = "%.4f" % blat
	if lon_inp: lon_inp.text = "%.4f" % blon
	# Afficher seulement la première partie du display_name (ville, pays)
	var display: String = str(entry.get("display_name", "?"))
	var short_name: String = display.split(",")[0].strip_edges()
	if loc_lbl: loc_lbl.text = "📌 %s  →  %.4f, %.4f" % [short_name, blat, blon]

# ─────────────────────────────────────────────────────────────
# GÉOLOCALISATION
# ─────────────────────────────────────────────────────────────

const _PORTAIL_NOMS := ["Pôle Nord","Pôle Sud","Orion","Aldébaran","Sirius","Véga",
	"Antarès","Fomalhaut","Achernar","Rigel","Capella","Deneb"]

func _refresh_umap_gps():
	# Met à jour GPS (précision 0.01°) + coordonnée Goldberg (hexagone + portail)
	# 0.00, 0.00 = convention UPlanet pour les utilisateurs sans GeoLoc
	var gps := SpaceTime_Manager.current_gps
	var gps_lbl      := find_child("OnboardGpsLabel",      true, false) as Label
	var goldberg_lbl  := find_child("OnboardGoldbergLabel", true, false) as Label
	var lat_inp := find_child("OnboardLat", true, false) as LineEdit
	var lon_inp := find_child("OnboardLon", true, false) as LineEdit
	var has_gps := gps.x != 0.0 or gps.y != 0.0
	# Coordonnées effectives — 0.00/0.00 si GPS indisponible
	var eff_lat := snappedf(gps.x, 0.01)
	var eff_lon := snappedf(gps.y, 0.01)
	if gps_lbl:
		gps_lbl.text = "📍 %.2f, %.2f%s" % [eff_lat, eff_lon,
			"" if has_gps else "  (sans GeoLoc — UPlanet 0.00,0.00)"]
		gps_lbl.modulate = UI_Theme.text_positive() if has_gps else UI_Theme.text_secondary()
	if goldberg_lbl:
		var ts := float(Time.get_unix_time_from_system())
		var geo := Phi2X_Math.geo_tags(eff_lat, eff_lon, ts)
		var hex_tag: String = geo[1][1]
		var pent_id: int    = Phi2X_Math.decode_geo_tag(hex_tag).get("pentagon_id", 0)
		var portail: String = _PORTAIL_NOMS[pent_id] if pent_id < _PORTAIL_NOMS.size() else "P%02d" % pent_id
		goldberg_lbl.text = "⬡ %s  ·  %s" % [portail, hex_tag]
	# Toujours remplir les champs cachés (0.00/0.00 si pas de GPS)
	if lat_inp: lat_inp.text = "%.2f" % eff_lat
	if lon_inp: lon_inp.text = "%.2f" % eff_lon

func _on_geolocate_pressed():
	if _is_polling_gps: return
	_is_polling_gps = true
	var gps_lbl := find_child("OnboardGpsLabel", true, false) as Label
	if gps_lbl: gps_lbl.text = "⏳ Recherche GPS en cours…"; gps_lbl.modulate = Color(0.8, 0.8, 0.8)
	if OS.has_feature("web"):
		JavaScriptBridge.eval("""
			window._godotGps = null;
			navigator.geolocation.getCurrentPosition(
				function(pos){ window._godotGps=[pos.coords.latitude,pos.coords.longitude]; },
				function(err){ window._godotGps='ERROR'; },
				{enableHighAccuracy:true,timeout:10000}
			);
		""")
		_poll_web_gps(20); return
	if OS.has_feature("android"): OS.request_permission("ACCESS_FINE_LOCATION")
	await get_tree().create_timer(0.6).timeout
	_apply_gps(SpaceTime_Manager.current_gps)
	_is_polling_gps = false

func _poll_web_gps(attempts: int):
	if not is_instance_valid(self) or attempts <= 0:
		_is_polling_gps = false
		var l := find_child("OnboardGpsLabel", true, false) as Label
		if l: l.text = "⚠ GPS non disponible — saisissez manuellement."; l.modulate = Color(1.0, 0.6, 0.2)
		return
	await get_tree().create_timer(0.5).timeout
	var raw := str(JavaScriptBridge.eval("JSON.stringify(window._godotGps)"))
	if raw == "null" or raw == "" or raw == "undefined":
		_poll_web_gps(attempts - 1); return
	if raw == '"ERROR"':
		var l := find_child("OnboardGpsLabel", true, false) as Label
		if l: l.text = "⚠ Permission GPS refusée."; l.modulate = Color(1.0, 0.6, 0.2); return
	var j := JSON.new()
	if j.parse(raw) == OK and j.data is Array and (j.data as Array).size() == 2:
		var lat: float = float((j.data as Array)[0]); var lon: float = float((j.data as Array)[1])
		SpaceTime_Manager.update_gps_location(lat, lon); _apply_gps(Vector2(lat, lon))
	_is_polling_gps = false

func _apply_gps(gps: Vector2):
	if gps.x == 0.0 and gps.y == 0.0:
		var gps_lbl := find_child("OnboardGpsLabel", true, false) as Label
		if gps_lbl: gps_lbl.text = "⚠ GPS pas encore disponible — réessayez."; gps_lbl.modulate = Color(1.0, 0.6, 0.2)
		return
	SpaceTime_Manager.update_gps_location(gps.x, gps.y)
	_refresh_umap_gps()

# ─────────────────────────────────────────────────────────────
# SECTION MULTIPASS (Kind 0)
# ─────────────────────────────────────────────────────────────

func _build_nostr_section():
	for f in [["name","Nom affiché"], ["about","À propos"], ["picture","Avatar (URL)"], ["nip05","NIP-05 (user@domain)"]]:
		_lbl(self, f[1], 13)
		var inp := UI_Theme.add_input(self, "NField_" + f[0], f[1], 48)
		inp.text = Nostr_Identity.get_profile_field(f[0])
	UI_Theme.add_styled_button(self, "📤 PUBLIER MON PROFIL (Kind 0)",
		Callable(self, "_on_nostr_publish"), false)

	var relay_lbl := RichTextLabel.new(); relay_lbl.name = "RelayList"
	relay_lbl.bbcode_enabled = true; relay_lbl.fit_content = true
	relay_lbl.custom_minimum_size = Vector2(0, 60)
	_update_relay_label(relay_lbl); add_child(relay_lbl)
	# Déconnexion préalable pour éviter le doublon en cas de rebuild
	if Nostr_Identity.relay_list_updated.is_connected(_on_relay_list_updated):
		Nostr_Identity.relay_list_updated.disconnect(_on_relay_list_updated)
	Nostr_Identity.relay_list_updated.connect(_on_relay_list_updated)

	var relay_inp := UI_Theme.add_input(self, "RelayInput", "wss://relay.example.com", 46)
	var rel_hb := _hbox(8)
	var btn_add := Button.new(); btn_add.text = "+ AJOUTER RELAIS"
	btn_add.size_flags_horizontal = SIZE_EXPAND_FILL
	btn_add.connect("pressed", Callable(self, "_on_add_relay")); rel_hb.add_child(btn_add)
	var btn_disc := Button.new(); btn_disc.text = "🔍 DÉCOUVRIR"
	btn_disc.size_flags_horizontal = SIZE_EXPAND_FILL
	btn_disc.connect("pressed", Callable(UPlanet_API, "discover_relays")); rel_hb.add_child(btn_disc)

func _on_nostr_publish():
	for f in ["name", "about", "picture", "nip05", "website"]:
		var inp := find_child("NField_" + f, true, false) as LineEdit
		if inp: Nostr_Identity.set_profile_field(f, inp.text)
	Nostr_Identity.publish_kind0()
	emit_signal("toast_requested", "📤 Profil publié !")

func _on_add_relay():
	var ri := find_child("RelayInput", true, false) as LineEdit
	if ri and ri.text.begins_with("wss://"):
		Nostr_Identity.add_relay(ri.text.strip_edges()); ri.text = ""

func _on_relay_list_updated(_relays: Array):
	var rl := find_child("RelayList", true, false) as RichTextLabel
	if rl: _update_relay_label(rl)

func _update_relay_label(lbl: RichTextLabel):
	var relays := Nostr_Identity.relay_list if Nostr_Identity.relay_list.size() > 0 else Nostr_Identity.PUBLIC_RELAYS
	var t := ""
	for r in relays: t += "[color=cyan]• %s[/color]\n" % r
	lbl.text = t if t != "" else "[color=gray]Aucun relais[/color]"

# ─────────────────────────────────────────────────────────────
# HELPERS UI LOCAUX
# ─────────────────────────────────────────────────────────────

func _lbl(parent: Node, text: String, size: int = 14, col: Color = Color.TRANSPARENT) -> Label:
	return UI_Theme.add_label(parent, text, size, col)

func _lbl_title(parent: Node, text: String, size: int, col: Color = Color.TRANSPARENT) -> Label:
	var l := UI_Theme.add_label(parent, text, size, col)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; return l

func _lbl_section(parent: Node, text: String):
	UI_Theme.add_section_title(parent, text)

func _make_panel_box() -> VBoxContainer:
	return UI_Theme.add_panel_vbox(self)

func _hbox(sep: int = 8) -> HBoxContainer:
	var h := HBoxContainer.new(); h.add_theme_constant_override("separation", sep)
	add_child(h); return h

func _build_sex_toggle(name_a: String, text_a: String, name_b: String, text_b: String, a_pressed: bool = true):
	var sex_hb := _hbox(14)
	sex_hb.alignment = BoxContainer.ALIGNMENT_CENTER
	var btn_a := Button.new(); btn_a.name = name_a; btn_a.text = text_a
	btn_a.toggle_mode = true; btn_a.button_pressed = a_pressed
	btn_a.custom_minimum_size = Vector2(160, 58); sex_hb.add_child(btn_a)
	var btn_b := Button.new(); btn_b.name = name_b; btn_b.text = text_b
	btn_b.toggle_mode = true; btn_b.button_pressed = not a_pressed
	btn_b.custom_minimum_size = Vector2(160, 58); sex_hb.add_child(btn_b)
	btn_a.connect("pressed", Callable(self, "_on_sex_toggle").bind(btn_a, btn_b))
	btn_b.connect("pressed", Callable(self, "_on_sex_toggle").bind(btn_b, btn_a))

func _on_sex_toggle(active: Button, other: Button):
	active.button_pressed = true; other.button_pressed = false

func _on_field_advance(text: String, next: LineEdit, max_len: int):
	if text.length() >= max_len and is_instance_valid(next): next.grab_focus()

func _build_date_fields(hb: HBoxContainer, fields: Array, on_change: Callable = Callable()) -> Array[LineEdit]:
	var out: Array[LineEdit] = []
	for info in fields:
		var col := VBoxContainer.new(); col.size_flags_horizontal = SIZE_EXPAND_FILL; hb.add_child(col)
		_lbl(col, info[1], 11, UI_Theme.text_secondary())
		var le := UI_Theme.add_input(col, info[0], info[1], 64, LineEdit.KEYBOARD_TYPE_NUMBER)
		le.max_length = info[2]
		if info.size() > 3: le.text = info[3]
		if on_change.is_valid(): le.text_changed.connect(on_change)
		le.focus_entered.connect(func(): le.call_deferred("select_all"))
		out.append(le)
	# Auto-advance : focus sur le champ suivant quand max_length est atteint
	for i in range(out.size() - 1):
		var cur: LineEdit = out[i]; var nxt: LineEdit = out[i + 1]
		var ml: int = cur.max_length
		cur.text_changed.connect(func(t: String): if t.length() >= ml: nxt.grab_focus())
	return out
