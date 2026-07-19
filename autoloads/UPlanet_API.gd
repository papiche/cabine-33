extends Node

signal multipass_created(data)
signal multipass_needs_pass(email: String)   # 409 need_pass — compte existant, code PASS requis
signal multipass_pass_invalid(email: String) # 401 — code PASS incorrect, réessayer
signal network_n2_analyzed(is_authorized, total_nodes)
signal sync_completed(message)
signal api_error(message)
signal udrive_uploaded(filename: String, cid: String)    # upload uDRIVE réussi
signal udrive_roaming()                                  # station ≠ home → roaming détecté
signal feedback_sent(result: Dictionary)                 # /api/feedback OK — {ok, stored, issue_url, ...}
signal feedback_error(message: String)

var http_request: HTTPRequest
var http_sign: HTTPRequest      # requête dédiée à la signature Schnorr
var http_discover: HTTPRequest  # requête dédiée à la découverte de relais
var http_auth: HTTPRequest      # requête dédiée à check_wot_authorization (évite collision avec forge)
var http_upload: HTTPRequest    # requête dédiée à l'upload uDRIVE
var http_feedback: HTTPRequest  # requête dédiée à /api/feedback
var base_url: String = "https://u.copylaradio.com"
var relay_url: String = "wss://relay.copylaradio.com"

# Derniers paramètres envoyés à forge_multipass — permet de rejouer la même
# requête avec un pass_code une fois que le serveur l'a demandé (409 need_pass),
# sans que l'appelant (TabProfil.gd) ait à tout ressaisir.
var _last_forge_params: Dictionary = {}

func _ready():
	http_request = HTTPRequest.new()
	http_request.timeout = 120.0  # forge Multipass : g1.sh + tx blockchain peut prendre >60s
	add_child(http_request)
	http_sign = HTTPRequest.new()
	http_sign.timeout = 30.0      # signature + publication NOSTR
	add_child(http_sign)
	http_discover = HTTPRequest.new()
	http_discover.timeout = 15.0
	add_child(http_discover)
	http_auth = HTTPRequest.new()
	http_auth.timeout = 15.0
	add_child(http_auth)
	http_upload = HTTPRequest.new()
	http_upload.timeout = 60.0    # upload fichier vers uDRIVE
	add_child(http_upload)
	http_feedback = HTTPRequest.new()
	http_feedback.timeout = 20.0
	add_child(http_feedback)

# ── Upload vers uDRIVE (/api/fileupload) ──────────────────────────────────────
# Authentification implicite via npub — UPassport vérifie que le joueur est local.
# Réponse 401/403 = station ≠ home station (roaming) → signal udrive_roaming.
# Réponse 200 = fichier stocké dans APP/uDRIVE/{type}/filename.
func upload_to_udrive(file_bytes: PackedByteArray, filename: String,
		mime_type: String = "application/octet-stream") -> void:
	if not Player_Origin.is_initialized or Player_Origin.user_npub.is_empty():
		emit_signal("api_error", "Aucun MULTIPASS connecté — impossible de synchroniser.")
		return

	var boundary := "A4LUpload" + str(int(Time.get_unix_time_from_system()))
	var body := PackedByteArray()

	# Part : fichier
	var fhdr := (
		"--" + boundary + "\r\n"
		+ "Content-Disposition: form-data; name=\"file\"; filename=\"" + filename + "\"\r\n"
		+ "Content-Type: " + mime_type + "\r\n\r\n"
	)
	body.append_array(fhdr.to_utf8_buffer())
	body.append_array(file_bytes)
	body.append_array("\r\n".to_utf8_buffer())

	# Part : npub (auth implicite côté UPassport)
	var nhdr := (
		"--" + boundary + "\r\n"
		+ "Content-Disposition: form-data; name=\"npub\"\r\n\r\n"
		+ Player_Origin.user_npub + "\r\n"
	)
	body.append_array(nhdr.to_utf8_buffer())
	body.append_array(("--" + boundary + "--\r\n").to_utf8_buffer())

	var headers := ["Content-Type: multipart/form-data; boundary=" + boundary]
	var err := http_upload.request_raw(base_url + "/api/fileupload", headers,
		HTTPClient.METHOD_POST, body)
	if err != OK:
		emit_signal("api_error", "Erreur réseau upload (code %d)" % err)
		return

	var result: Array = await http_upload.request_completed
	var code: int = result[1]
	var resp_body := (result[3] as PackedByteArray).get_string_from_utf8()

	match code:
		200, 201:
			var j := JSON.new()
			var cid := ""
			if j.parse(resp_body) == OK and j.data is Dictionary:
				cid = j.data.get("cid", j.data.get("ipfs_cid", ""))
			if cid.is_empty():
				# CID absent = upload accepté mais non archivé → ne pas purger le cache
				emit_signal("api_error", "⚠ uDRIVE: CID manquant dans la réponse — données conservées localement")
			else:
				emit_signal("udrive_uploaded", filename, cid)
				emit_signal("sync_completed", "✅ %s synchronisé dans votre uDRIVE" % filename)
		401, 403:
			emit_signal("udrive_roaming")
			# Roaming détecté → route via DM NIP-44 inter-node vers la home station.
			# La home station exécute bro_dm_daemon.sh qui gère channel "udrive".
			_route_udrive_via_constellation(file_bytes, filename, mime_type)
		413:
			emit_signal("api_error", "❌ Fichier trop volumineux pour votre uDRIVE.")
		_:
			emit_signal("api_error", "Erreur serveur upload (%d) — réessayez." % code)

func forge_multipass(email: String, salt: String, pepper: String, lat: float, lon: float,
		lang: String = "fr",
		birth_datetime: String = "", birth_place: String = "", birth_weight: String = "",
		conception_datetime: String = "", conception_place: String = "",
		pass_code: String = ""):
	_last_forge_params = {
		"email": email, "salt": salt, "pepper": pepper, "lat": lat, "lon": lon, "lang": lang,
		"birth_datetime": birth_datetime, "birth_place": birth_place, "birth_weight": birth_weight,
		"conception_datetime": conception_datetime, "conception_place": conception_place,
	}
	var params := PackedStringArray([
		"email=" + email.uri_encode(),
		"lang=" + lang, "lat=" + str(lat), "lon=" + str(lon),
		"salt=" + salt.uri_encode(), "pepper=" + pepper.uri_encode(),
		"pre_stretched=false",  # Cabine-33 envoie les chaînes brutes : le serveur applique PBKDF2
		"format=json"
	])
	if birth_datetime != "":      params.append("birth_datetime="      + birth_datetime.uri_encode())
	if birth_place != "":         params.append("birth_place="         + birth_place.uri_encode())
	if birth_weight != "":        params.append("birth_weight="        + birth_weight.uri_encode())
	if conception_datetime != "": params.append("conception_datetime=" + conception_datetime.uri_encode())
	if conception_place != "":    params.append("conception_place="    + conception_place.uri_encode())
	if pass_code != "":           params.append("pass_code="           + pass_code.uri_encode())
	var headers := ["Content-Type: application/x-www-form-urlencoded"]
	var err := http_request.request(base_url + "/g1nostr", headers,
		HTTPClient.METHOD_POST, "&".join(params))
	if err != OK:
		emit_signal("api_error", "Erreur réseau lors de la forge (code %d)" % err); return
	var result: Array = await http_request.request_completed
	var http_result: int = result[0]; var response_code: int = result[1]
	var body: PackedByteArray = result[3]
	if http_result != HTTPRequest.RESULT_SUCCESS:
		var reason := "Astroport injoignable"
		match http_result:
			HTTPRequest.RESULT_TIMEOUT:           reason = "Timeout — le nœud est lent (>120s). Réessayez."
			HTTPRequest.RESULT_CONNECTION_ERROR:  reason = "Connexion refusée — vérifiez votre réseau."
			HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR: reason = "Erreur TLS — certificat invalide."
			HTTPRequest.RESULT_CANT_CONNECT:      reason = "Impossible de joindre le nœud Astroport."
		emit_signal("api_error", reason)
		return
	if response_code == 200:
		var json := JSON.new()
		if json.parse(body.get_string_from_utf8()) == OK:
			emit_signal("multipass_created", json.data)
		else: emit_signal("api_error", "Réponse du nœud illisible.")
		return

	# Réponses d'erreur structurées — voir UPassport/routers/identity.py::_scan_qr_impl
	var err_json := JSON.new()
	var err_data: Dictionary = {}
	if err_json.parse(body.get_string_from_utf8()) == OK and err_json.data is Dictionary:
		err_data = err_json.data
	match response_code:
		409:
			if err_data.get("need_pass", false):
				emit_signal("multipass_needs_pass", email)
			elif err_data.get("error", "") == "IDENTITY_CONFLICT":
				emit_signal("api_error", "Conflit d'identité : ces données correspondent déjà à un autre compte.")
			else:
				emit_signal("api_error", "Le nœud a refusé (Code 409)")
		401:
			emit_signal("multipass_pass_invalid", email)
		503:
			emit_signal("api_error", "Code PASS indisponible sur ce nœud. Contactez le support.")
		_:
			emit_signal("api_error", "Le nœud a refusé (Code %d)" % response_code)

# Rejoue la dernière tentative forge_multipass() avec un pass_code — utilisé
# après un signal multipass_needs_pass ou multipass_pass_invalid, quand
# l'utilisateur saisit son code PASS dans TabProfil.gd.
func retry_forge_multipass_with_pass(pass_code: String) -> void:
	if _last_forge_params.is_empty():
		emit_signal("api_error", "Aucune tentative de forge en attente — recommencez.")
		return
	var p := _last_forge_params
	forge_multipass(p["email"], p["salt"], p["pepper"], p["lat"], p["lon"], p["lang"],
		p["birth_datetime"], p["birth_place"], p["birth_weight"],
		p["conception_datetime"], p["conception_place"], pass_code)

# sign_and_publish() supprimée — la clé privée ne doit jamais quitter l'appareil.
# Toute signature passe par NostrCrypto.sign_event_local() (Android/Desktop)
# ou window.NostrTools.finalizeEvent() (Web). Voir Nostr_Identity._sign_local_and_publish().

func discover_relays():
	# GET / — JSON station UPlanet. Champ "myRELAY" = relay de la station.
	# "SWARM" = tableau des nœuds de la constellation, chacun avec son "myRELAY".
	# On collecte tous les relays WSS publics (pas ws://127.x ou ws://localhost).
	var err := http_discover.request(base_url + "/")
	if err != OK: return
	var result: Array = await http_discover.request_completed
	if result[1] != 200: return
	var j := JSON.new()
	if j.parse((result[3] as PackedByteArray).get_string_from_utf8()) != OK: return
	var data = j.data

	var seen: Dictionary = {}
	var relays: Array = []

	# Relay principal de la station (champ "myRELAY")
	var main_relay: String = data.get("myRELAY", "")
	if main_relay != "" and main_relay.begins_with("wss://") and not seen.has(main_relay):
		seen[main_relay] = true
		relays.append(main_relay)

	# Relays publics du SWARM (évite les adresses locales 127.x)
	if data.has("SWARM") and data["SWARM"] is Array:
		for node in data["SWARM"]:
			if not (node is Dictionary): continue
			var nr: String = node.get("myRELAY", "")
			if nr.begins_with("wss://") and not seen.has(nr):
				seen[nr] = true
				relays.append(nr)

	# Fallback si aucun relay public trouvé
	if relays.is_empty():
		var fb := relay_url if relay_url.begins_with("wss://") else "wss://relay.copylaradio.com"
		relays = [fb]
		push_warning("UPlanet_API: aucun myRELAY public dans le JSON station — fallback : " + fb)

	print("📡 UPlanet_API: %d relay(s) découvert(s) : %s" % [relays.size(), str(relays)])
	Nostr_Identity.set_relay_list_from_discovery(relays)

func fetch_follows(hex_pubkey: String):
	check_wot_authorization(hex_pubkey)

func check_wot_authorization(hex_pubkey: String):
	if http_auth.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		http_auth.cancel_request()
	var url := base_url + "/api/getN2?hex=" + hex_pubkey + "&range=default&output=json"
	var err := http_auth.request(url)
	if err != OK:
		emit_signal("network_n2_analyzed", false, 0); return
	var result: Array = await http_auth.request_completed
	if result[1] != 200:
		emit_signal("network_n2_analyzed", false, 0); return
	var json := JSON.new()
	if json.parse((result[3] as PackedByteArray).get_string_from_utf8()) != OK:
		emit_signal("network_n2_analyzed", false, 0); return
	var data = json.data
	var total: int = data.get("total_n1", 0) + data.get("total_n2", 0)
	emit_signal("network_n2_analyzed", total > 0, total)

# Synchronisation manuelle NOSTR — délègue à Nostr_Identity (WebSocket déjà géré)
func sync_with_relay(_npub: String):
	Nostr_Identity.connect_relay_list()
	emit_signal("sync_completed", "Connexion relais lancée vers " + relay_url)

# ── Routage uDRIVE via constellation (roaming) ────────────────────────────────
# 1. Upload le fichier sur IPFS via /upload2ipfs de la station courante → CID
# 2. Envoie un DM NIP-44 kind 4 au home NODE hex avec le payload udrive
# bro_dm_daemon.sh sur la home station récupère le CID et place le fichier dans uDRIVE.
func _route_udrive_via_constellation(file_bytes: PackedByteArray, filename: String,
		mime_type: String) -> void:
	var home_hex := Player_Origin.home_node_hex
	if home_hex.is_empty():
		emit_signal("api_error",
			"⚠️ Station d'origine inconnue — impossible de synchroniser en roaming.\n"
			+ "Reconnectez-vous à votre station personnelle.")
		return

	emit_signal("sync_completed", "📡 Roaming détecté — envoi via la constellation…")

	# Étape 1 : upload IPFS (pas d'auth requise pour ipfs add)
	var boundary := "A4LIPFS" + str(int(Time.get_unix_time_from_system()))
	var body := PackedByteArray()
	var fhdr := (
		"--" + boundary + "\r\n"
		+ "Content-Disposition: form-data; name=\"file\"; filename=\"" + filename + "\"\r\n"
		+ "Content-Type: " + mime_type + "\r\n\r\n"
	)
	body.append_array(fhdr.to_utf8_buffer())
	body.append_array(file_bytes)
	body.append_array(("\r\n--" + boundary + "--\r\n").to_utf8_buffer())

	var http_ipfs := HTTPRequest.new(); http_ipfs.timeout = 30.0; add_child(http_ipfs)
	var err := http_ipfs.request_raw(base_url + "/upload2ipfs",
		["Content-Type: multipart/form-data; boundary=" + boundary],
		HTTPClient.METHOD_POST, body)

	if err != OK:
		http_ipfs.queue_free()
		emit_signal("api_error", "❌ Upload IPFS échoué (réseau)")
		return

	var result: Array = await http_ipfs.request_completed
	http_ipfs.queue_free()

	if result[1] not in [200, 201]:
		emit_signal("api_error", "❌ Upload IPFS échoué (HTTP %d)" % result[1])
		return

	var j := JSON.new()
	var cid := ""
	if j.parse((result[3] as PackedByteArray).get_string_from_utf8()) == OK:
		cid = j.data.get("cid", j.data.get("Hash", ""))
	if cid.is_empty():
		emit_signal("api_error", "❌ CID IPFS introuvable dans la réponse")
		return

	# Étape 2 : DM NIP-44 → home station → bro_dm_daemon.sh → _handle_udrive()
	var ext := filename.get_extension().to_lower()
	var filetype := "json" if ext == "json" else ("image" if ext in ["jpg","jpeg","png"] else "file")
	var dm_payload := {
		"channel": "udrive",
		"payload": {
			"email":    Player_Origin.user_email,
			"cid":      cid,
			"filename": filename,
			"filetype": filetype
		}
	}
	Nostr_Identity.send_udrive_dm(home_hex, dm_payload)
	emit_signal("sync_completed",
		"📨 En transit via constellation → home station\nLe fichier sera disponible dans votre uDRIVE sous peu.")

# DM NIP-44 chiffré localement — nsec ne quitte JAMAIS l'appareil
# Le ciphertext est publié directement via Nostr_Identity (kind 4)
func send_secure_dm_proxy(recipient_hex: String, plaintext: String) -> void:
	if Player_Origin.user_nsec.is_empty() or Player_Origin.user_hex.is_empty():
		push_error("UPlanet_API: send_secure_dm_proxy — MULTIPASS non initialisé"); return
	if recipient_hex.length() != 64:
		push_error("UPlanet_API: send_secure_dm_proxy — recipient_hex invalide"); return

	# Chiffrement NIP-44 local : nsec reste sur l'appareil
	var ciphertext := NostrCrypto.encrypt_nip44(Player_Origin.user_nsec, recipient_hex, plaintext)
	if ciphertext.is_empty():
		push_error("UPlanet_API: send_secure_dm_proxy — chiffrement NIP-44 échoué"); return

	# Publier kind 4 (DM chiffré) via la file NOSTR existante
	var ev := Nostr_Identity.make_event(4, ciphertext, [["p", recipient_hex]])
	Nostr_Identity.sign_and_send(ev)
	print("📨 DM NIP-44 chiffré localement → %s…" % recipient_hex.substr(0, 12))

# ── Feedback / rapport de bug ─────────────────────────────────────────────────
# POST /api/feedback — même endpoint que UPlanet/earth (feedback.js) et Zelkova
# (FeedbackService) : crée une issue Git (repo "{GIT_OWNER}/cabine-33") ou,
# à défaut, envoie un email au capitaine. Voir UPassport/routers/feedback.py.
func send_feedback(title: String, description: String, category: String = "bug",
		pubkey: String = "") -> void:
	var fields := PackedStringArray([
		"title=" + title.uri_encode(),
		"description=" + description.uri_encode(),
		"category=" + category.uri_encode(),
		"source=cabine-33",
		"platform=" + OS.get_name().uri_encode(),
	])
	if pubkey != "": fields.append("pubkey=" + pubkey.uri_encode())
	var headers := ["Content-Type: application/x-www-form-urlencoded"]
	var err := http_feedback.request(base_url + "/api/feedback", headers,
		HTTPClient.METHOD_POST, "&".join(fields))
	if err != OK:
		emit_signal("feedback_error", "Erreur réseau (code %d)" % err); return
	var result: Array = await http_feedback.request_completed
	var http_result: int = result[0]; var response_code: int = result[1]
	var body: PackedByteArray = result[3]
	if http_result != HTTPRequest.RESULT_SUCCESS:
		emit_signal("feedback_error", "Astroport injoignable — vérifiez votre connexion.")
		return
	if response_code != 200:
		emit_signal("feedback_error", "Le nœud a refusé (Code %d)" % response_code)
		return
	var json := JSON.new()
	if json.parse(body.get_string_from_utf8()) == OK and json.data is Dictionary:
		emit_signal("feedback_sent", json.data as Dictionary)
	else:
		emit_signal("feedback_error", "Réponse du nœud illisible.")
