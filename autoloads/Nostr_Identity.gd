extends Node
# Bibliothèque NOSTR interne — ATOM4LOVE
# WebSocket multi-relais, Kind 0/3, ID SHA256
# (derive_nsec2_from_nsec1 : obsolète/inutilisée, voir le bloc dédié plus bas)

signal relay_connected(relay_url)
signal relay_disconnected(relay_url)
signal event_received(event_dict)
signal profile_published(relay_count)
signal follows_updated(follows)
signal relay_list_updated(relays)
signal nsec2_derived(data)

# --- PROFIL KIND 0 ---
var profile: Dictionary = {
	"name": "", "about": "", "picture": "",
	"nip05": "", "website": "",
	"g1pub": "", "banner": ""
}

# --- RÉSEAU SOCIAL ---
var follows: Array = []
var mutes: Array = []
var relay_list: Array = []

# Relay de la constellation ATOM4LOVE — fallback si discover_relays() n'a pas encore tourné.
# Ces relays implémentent NIP-101 (filtres Kind 30078, certificat ATOM4LOVE).
const PUBLIC_RELAYS: Array = [
	"wss://relay.copylaradio.com"
]

# Relays NOSTR publics — ne comprennent PAS le protocole ATOM4LOVE (pas de NIP-101).
# Utilisés uniquement pour le "teasing" : diffuser un Kind 1 d'accroche pour la
# visibilité de l'app sur l'écosystème NOSTR grand public.
const TEASE_RELAYS: Array = [
	"wss://relay.damus.io",
	"wss://nostr.wine",
	"wss://relay.snort.social",
	"wss://nos.lol"
]

const SAVE_PROFILE = "user://nostr_profile.json"
const SAVE_SOCIAL  = "user://nostr_social.json"

# URL de la bibliothèque Schnorr/NOSTR hébergée sur UPlanet
const NOSTR_BUNDLE_URL: String = "https://u.copylaradio.com/earth/nostr.bundle.js"

# --- CONNEXIONS WEBSOCKET ---
var _ws: Dictionary = {}
var _queue: Dictionary = {}  # url → Array[String] : file par relais pour éviter la perte si connexion tardive
var _subs: Dictionary = {}
var _reconnect_timer: float = 0.0  # auto-reconnexion si relay perdu (changement 4G/WiFi)
var _initialized_relays: Dictionary = {}

# --- ÉTAT DU CHARGEMENT nostr.bundle.js ---
var _nostr_bundle_injected: bool = false
var _nostr_bundle_ready: bool = false
var _pending_sign_queue: Array = []  # Événements en attente de bundle JS

func _ready():
	set_process(false)
	_load_profile()
	_load_social()
	if Player_Origin.is_initialized and profile["g1pub"].is_empty():
		profile["g1pub"] = Player_Origin.user_g1pub
	if OS.get_name() == "Web":
		_inject_nostr_bundle()
	# Découverte automatique des relays de la constellation au démarrage
	# (n'attend pas que l'utilisateur appuie sur "Sync")
	call_deferred("_auto_discover_relays")

func _auto_discover_relays():
	await get_tree().create_timer(3.0).timeout  # Laisser le temps à UPlanet_API d'être prêt
	if relay_list.is_empty():
		UPlanet_API.discover_relays()

# ───────────────────────────────────────────────
# CHARGEMENT DYNAMIQUE nostr.bundle.js
# ───────────────────────────────────────────────

func _inject_nostr_bundle():
	if _nostr_bundle_injected: return
	_nostr_bundle_injected = true
	# Vérifier si déjà présent dans le template HTML5 (export statique)
	var already: String = str(JavaScriptBridge.eval(
		"typeof window.NostrTools !== 'undefined' ? 'yes' : 'no'"
	))
	if already == "yes":
		_nostr_bundle_ready = true
		print("📦 NostrTools: déjà présent dans le template HTML.")
		return
	# Injection dynamique depuis l'hébergeur UPlanet
	var js := (
		"(function(){"
		+ "var s=document.createElement('script');"
		+ "s.src='" + NOSTR_BUNDLE_URL + "';"
		+ "s.onload=function(){window._nostr_ready=true;"
		+ "console.log('[ATOM4LOVE] NostrTools chargé depuis " + NOSTR_BUNDLE_URL + "');};"
		+ "s.onerror=function(){window._nostr_ready=false;"
		+ "console.error('[ATOM4LOVE] Échec chargement NostrTools');};"
		+ "document.head.appendChild(s);"
		+ "})()"
	)
	JavaScriptBridge.eval(js)
	print("📦 NostrTools: injection depuis " + NOSTR_BUNDLE_URL)

func _check_nostr_ready() -> bool:
	if _nostr_bundle_ready: return true
	if OS.get_name() != "Web": return false
	var ready: String = str(JavaScriptBridge.eval(
		"(typeof window.NostrTools !== 'undefined'"
		+ " && (typeof window.NostrTools.finalizeEvent !== 'undefined'"
		+ "  || typeof window.NostrTools.finishEvent  !== 'undefined')) ? 'yes' : 'no'"
	))
	_nostr_bundle_ready = (ready == "yes")
	return _nostr_bundle_ready

# ───────────────────────────────────────────────
# GESTION DES RELAIS
# ───────────────────────────────────────────────

func connect_relay(url: String):
	if _ws.has(url): return
	var ws := WebSocketPeer.new()
	var err := ws.connect_to_url(url)
	if err != OK:
		push_error("NOSTR: connect_to_url(%s) failed → %d" % [url, err])
		return
	_ws[url] = ws
	set_process(true)
	print("📡 NOSTR: Connexion à %s…" % url)

func connect_relay_list():
	var targets := relay_list if relay_list.size() > 0 else PUBLIC_RELAYS
	for url in targets:
		connect_relay(url)

func disconnect_relay(url: String):
	if _ws.has(url):
		(_ws[url] as WebSocketPeer).close()
		_ws.erase(url)

func disconnect_all():
	for url in _ws.keys():
		(_ws[url] as WebSocketPeer).close()
	_ws.clear()
	set_process(false)

func add_relay(url: String):
	if not relay_list.has(url):
		relay_list.append(url)
		_save_social()
		emit_signal("relay_list_updated", relay_list)
	connect_relay(url)

func remove_relay(url: String):
	relay_list.erase(url)
	disconnect_relay(url)
	_save_social()
	emit_signal("relay_list_updated", relay_list)

func set_relay_list_from_discovery(relays: Array):
	relay_list = relays.duplicate()
	_save_social()
	emit_signal("relay_list_updated", relay_list)

# ───────────────────────────────────────────────
# BOUCLE DE POLLING WEBSOCKET (_process)
# ───────────────────────────────────────────────

var _process_delta: float = 0.0

func _process(delta: float):
	_process_delta = delta
	var dead: Array = []
	for url in _ws.keys():
		var ws := _ws[url] as WebSocketPeer
		ws.poll()
		match ws.get_ready_state():
			WebSocketPeer.STATE_OPEN:
				if not _initialized_relays.get(url, false):
					_initialized_relays[url] = true
					for sub_id in _subs:
						ws.send_text(JSON.stringify(["REQ", sub_id, _subs[sub_id]]))
					if _queue.has(url):
						for msg in _queue[url]: ws.send_text(msg)
						_queue.erase(url)
				while ws.get_available_packet_count() > 0:
					var pkt := ws.get_packet()
					_parse_message(url, pkt.get_string_from_utf8())
			WebSocketPeer.STATE_CONNECTING:
				pass
			WebSocketPeer.STATE_CLOSED:
				dead.append(url)
				_initialized_relays.erase(url)
				emit_signal("relay_disconnected", url)
			WebSocketPeer.STATE_CLOSING:
				pass
	for url in dead: _ws.erase(url)

	# Auto-reconnexion : toutes les 10s, tenter de ré-animer les relays perdus
	# (utile après un changement 4G→WiFi ou coupure réseau temporaire)
	_reconnect_timer += _process_delta
	if _reconnect_timer > 10.0:
		_reconnect_timer = 0.0
		var targets := relay_list if relay_list.size() > 0 else PUBLIC_RELAYS
		for url in targets:
			if not _ws.has(url): connect_relay(url)

	if _ws.is_empty(): set_process(false)

func _parse_message(url: String, text: String):
	var msg = JSON.parse_string(text)
	if msg == null: return
	if not (msg is Array) or msg.size() < 2: return
	match str(msg[0]):
		"EVENT":
			if msg.size() >= 3 and msg[2] is Dictionary:
				var ev: Dictionary = msg[2]
				emit_signal("event_received", ev)
				# Extraire home_station depuis le kind 0 de l'utilisateur lui-même
				if ev.get("kind") == 0 and ev.get("pubkey", "") == Player_Origin.user_hex:
					_parse_home_station_from_kind0(ev)
		"EOSE":
			pass
		"NOTICE":
			print("NOSTR NOTICE [%s]: %s" % [url, msg[1]])
		"OK":
			pass
		_:
			pass

# ───────────────────────────────────────────────
# PROTOCOLE NOSTR (REQ / EVENT / CLOSE)
# ───────────────────────────────────────────────

func subscribe(filter: Dictionary) -> String:
	var sub_id := "a4l_" + str(Time.get_unix_time_from_system()).sha256_text().substr(0, 8)
	_subs[sub_id] = filter
	_broadcast(JSON.stringify(["REQ", sub_id, filter]))
	return sub_id

func unsubscribe(sub_id: String):
	_subs.erase(sub_id)
	_broadcast(JSON.stringify(["CLOSE", sub_id]))

func publish_raw(event: Dictionary):
	_broadcast(JSON.stringify(["EVENT", event]))

func _broadcast(text: String):
	# Itérer sur relay_list (pas seulement _ws.keys()) : si la connexion est perdue
	# _ws est vidé mais les relais cibles sont connus → message mis en file pour la reconnexion
	var targets: Array = relay_list if relay_list.size() > 0 else PUBLIC_RELAYS
	for url in targets:
		if _ws.has(url) and (_ws[url] as WebSocketPeer).get_ready_state() == WebSocketPeer.STATE_OPEN:
			(_ws[url] as WebSocketPeer).send_text(text)
		else:
			if not _queue.has(url): _queue[url] = []
			(_queue[url] as Array).append(text)

# ───────────────────────────────────────────────
# CONSTRUCTION D'ÉVÉNEMENTS NOSTR
# ───────────────────────────────────────────────

func make_event(kind: int, content: String, tags: Array = []) -> Dictionary:
	return {
		"pubkey": Player_Origin.user_hex,
		"created_at": int(Time.get_unix_time_from_system()),
		"kind": kind,
		"tags": tags,
		"content": content,
		"sig": ""
	}

func compute_event_id(ev: Dictionary) -> String:
	var serialized := JSON.stringify([
		0, ev["pubkey"], ev["created_at"], ev["kind"], ev["tags"], ev["content"]
	])
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(serialized.to_utf8_buffer())
	return ctx.finish().hex_encode()

func sign_and_send(ev: Dictionary):
	ev["id"] = compute_event_id(ev)
	# Accepter nsec1... (bech32) ET hex brut 64 chars — nostr-tools gère les deux
	var nsec := Player_Origin.user_nsec
	var is_signable_web := nsec.begins_with("nsec1") or (nsec.length() == 64 and nsec.is_valid_hex_number())
	if OS.get_name() == "Web" and is_signable_web:
		if not _nostr_bundle_ready:
			_pending_sign_queue.append(ev)
			if not await _ensure_nostr_ready():
				push_error("NOSTR: NostrTools indisponible — signing local GDScript")
				_pending_sign_queue.erase(ev)
				_sign_local_and_publish(ev)
				return
			_flush_sign_queue()
			return
		_sign_via_js(ev)
	else:
		# Android/Desktop : signe LOCALEMENT (nsec ne quitte pas le téléphone)
		_sign_local_and_publish(ev)

func _sign_local_and_publish(ev: Dictionary):
	var nsec := Player_Origin.user_nsec
	if nsec.is_empty() or nsec == "ANON":
		push_error("NOSTR: pas de nsec — événement abandonné"); return
	var signed := NostrCrypto.sign_event_local(ev, nsec)
	if signed.get("sig", "").is_empty():
		push_error("NOSTR: signing local échoué — événement abandonné (la clé privée ne quitte pas l'appareil)")
		return
	publish_raw(signed)

func _ensure_nostr_ready() -> bool:
	if _nostr_bundle_ready: return true
	var timeout := 8.0
	while timeout > 0.0 and not _nostr_bundle_ready:
		await get_tree().create_timer(0.25).timeout
		timeout -= 0.25
		_check_nostr_ready()
	return _nostr_bundle_ready

func _flush_sign_queue():
	var queue := _pending_sign_queue.duplicate()
	_pending_sign_queue.clear()
	for queued_ev in queue:
		_sign_via_js(queued_ev)

func _sign_via_js(ev: Dictionary):
	if not _check_nostr_ready():
		push_error("NOSTR: NostrTools pas encore chargé — événement abandonné"); return

	# IMPORTANT: concaténation (pas %) — ev_json peut contenir des '%' dans les URLs
	var ev_json := JSON.stringify(ev)
	var nsec := Player_Origin.user_nsec
	# Compatibilité v1 (finishEvent) et v2 (finalizeEvent) + hex brut 64 chars
	# nostr-tools v2 finalizeEvent accepte Uint8Array directement (pas seulement nsec1)
	var js := (
		"(function(){"
		+ "var lib=window.NostrTools;"
		+ "if(!lib){"
		+ "console.warn('[ATOM4LOVE] NostrTools non disponible');"
		+ "return null;}"
		+ "try{"
		+ "var ev=" + ev_json + ";"
		+ "var privkey;"
		+ "if('" + nsec + "'.startsWith('nsec1')){"
		+ "  var dec=lib.nip19.decode('" + nsec + "');"
		+ "  if(!dec||dec.type!=='nsec')return null;"
		+ "  privkey=dec.data;"
		+ "}else{"
		+ "  var h='" + nsec + "';"
		+ "  privkey=new Uint8Array(h.match(/../g).map(function(x){return parseInt(x,16)}));"
		+ "}"
		+ "var signed=lib.finalizeEvent?lib.finalizeEvent(ev,privkey):lib.finishEvent(ev,privkey);"
		+ "return JSON.stringify(signed);"
		+ "}catch(e){console.error('[ATOM4LOVE] sign error:',e);return null;}"
		+ "})()"
	)
	var result: Variant = JavaScriptBridge.eval(js)
	if result != null and str(result) != "null" and str(result) != "":
		var j := JSON.new()
		if j.parse(str(result)) == OK and j.data is Dictionary:
			publish_raw(j.data)
			return
	push_error("NOSTR: signature JS échouée — événement abandonné (la clé privée ne quitte pas l'appareil)")

# ───────────────────────────────────────────────
# KIND 0 — PROFIL MÉTADONNÉES
# ───────────────────────────────────────────────

func build_kind0() -> Dictionary:
	# Partir du profil complet (duplicate) pour ne jamais perdre les champs techniques
	# comme home_station, lud16, zap_endpoint, etc. qui ne sont pas dans les LineEdits UI
	var content_dict := profile.duplicate()
	# Forcer les champs UI éditables par-dessus (sans toucher aux autres)
	content_dict["g1pub"]   = Player_Origin.user_g1pub
	content_dict.get_or_add("name",    "")
	content_dict.get_or_add("about",   "")
	content_dict.get_or_add("picture", "")
	content_dict.get_or_add("nip05",   "")
	content_dict.get_or_add("website", "")
	content_dict.get_or_add("banner",  "")
	var ev := make_event(0, JSON.stringify(content_dict))
	ev["id"] = compute_event_id(ev)
	return ev

func publish_kind0():
	if not Player_Origin.is_initialized:
		push_error("Nostr_Identity: MULTIPASS requis pour publier kind 0")
		return
	profile["g1pub"] = Player_Origin.user_g1pub
	var ev := build_kind0()
	sign_and_send(ev)
	_save_profile()
	emit_signal("profile_published", _ws.size())

# ───────────────────────────────────────────────
# KIND 30078 — CERTIFICAT D'INCARNATION ATOM4LOVE
# Publié une fois après la création du MULTIPASS.
# Le relay NIP-101 vérifie :
#   - personal_phase ∈ [0,7) et omega_bio ∈ (0.1,50)
#   - a4l_proof == SHA256(pubkey + ":ATOM4LOVE_v1") — marqueur d'app
# ───────────────────────────────────────────────

const A4L_PROOF_SALT := "ATOM4LOVE_v1"

func _compute_a4l_proof(hex_pubkey: String) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update((hex_pubkey + ":" + A4L_PROOF_SALT).to_utf8_buffer())
	return ctx.finish().hex_encode()

func publish_atom4love_cert():
	if not Player_Origin.is_initialized:
		return  # Silencieux : MULTIPASS pas encore créé, état normal avant onboarding
	if not Player_Origin.has_atom4love_profile():
		return  # Silencieux : profil de naissance pas encore saisi, état attendu
	var proof: String  = _compute_a4l_proof(Player_Origin.user_hex)
	var kin_dict: Dictionary = Kin_Maya.calc_kin_unix(Player_Origin.birth_unix)
	var kin_num: int   = kin_dict.get("kin", 0)
	# Contenu enrichi — synchronisé avec kin_oracle.sh._scan_a4l_phi()
	var content := JSON.stringify({
		"personal_phase":    Player_Origin.personal_phase,
		"omega_bio":         Player_Origin.omega_bio,
		"biological_sex":    Player_Origin.biological_sex,   # 0=Φ-wave 1=Octave
		"kin_num":           kin_num,                        # Kin Maya Tzolkin (1-260)
		"inst_id":           Voice_Sampler.get_inst_id(),    # 0=synth 1=voix enregistrée
		"app":               "atom4love",
		"version":           2                               # v2 : champs enrichis
	})
	var ev := make_event(30078, content, [
		["d",         "atom4love"],
		["app",       "atom4love"],
		["a4l_proof", proof],
		["k",         "%.6f" % Player_Origin.personal_phase],  # index rapide relay
		["kin",       str(kin_num)]                             # index rapide relay
	])
	sign_and_send(ev)
	print("⚛ ATOM4LOVE: certificat Kind 30078 publié (φ=%.4f ω=%.4f kin=%d proof=%s…)" % [
		Player_Origin.personal_phase, Player_Origin.omega_bio, kin_num, proof.substr(0, 8)])

# ───────────────────────────────────────────────
# KIND 7 — RÉSONANCE ATOM4LOVE
# Publie un événement de résonance mesuré avec un autre atome.
# Distinct des paiements ẐEN (Kind 7 content "+N") par le tag ["t","a4l-resonance"].
# Format content : "+k" où k ∈ [0.5, 1.0] — jamais ambigu avec un montant ẐEN > 1.
# ───────────────────────────────────────────────
func publish_kind7_resonance(target_hex: String, k: float):
	if not Player_Origin.is_initialized: return
	if target_hex.is_empty(): return
	var k_str := "+%.4f" % k
	var ev := make_event(7, k_str, [
		["p", target_hex],            # pubkey cible (NIP-01)
		["t", "atom4love"],           # tag app
		["t", "a4l-resonance"],       # distingue des paiements ẐEN
		["k", "%.4f" % k],            # tag indexable pour le relay
		["singularity", "1" if k >= 0.95 else "0"]
	])
	sign_and_send(ev)
	print("⚛ ATOM4LOVE: Kind 7 résonance → %s k=%.4f" % [target_hex.substr(0, 8), k])

# ───────────────────────────────────────────────
# KIND 1 — TEASING SUR RELAYS PUBLICS
# Diffuse une note d'accroche sur les relays NOSTR publics (damus, nostr.wine…)
# pour la visibilité de l'App. Ces relays ne comprennent pas le protocole
# ATOM4LOVE mais voient l'utilisateur et peuvent amener de nouveaux atomes.
# ───────────────────────────────────────────────

func publish_tease(custom_content: String = ""):
	if not Player_Origin.is_initialized:
		push_error("Nostr_Identity: MULTIPASS requis pour le teasing")
		return
	var content := custom_content if custom_content != "" else _default_tease_content()
	var ev := make_event(1, content, [
		["t", "atom4love"],
		["t", "nostr"],
		["t", "uplanet"],
		["t", "resonance"]
	])
	# Publier directement sur les TEASE_RELAYS (pas sur la constellation)
	_broadcast_to(ev, TEASE_RELAYS)
	print("✨ ATOM4LOVE: teasing publié sur %d relays publics" % TEASE_RELAYS.size())

func _default_tease_content() -> String:
	var phi := "%.5f" % Player_Origin.personal_phase if Player_Origin.has_atom4love_profile() else "?"
	return (
		"🌌 Je cartographie mon champ de résonance cosmique avec ATOM4LOVE.\n\n"
		+ "φ_i = %s — ma fréquence personnelle dans le polyèdre de Goldberg.\n\n" % phi
		+ "ATOM4LOVE est un interféromètre social décentralisé : il calcule le taux de résonance φ "
		+ "entre deux êtres depuis leur date et lieu de naissance.\n\n"
		+ "🌐 UPlanet / NOSTR / G1 — #atom4love #uplanet #resonance #phi"
	)

func _broadcast_to(ev: Dictionary, targets: Array):
	# Signature 100% locale puis diffusion WebSocket native — nsec ne quitte pas l'appareil
	var signed_ev: Dictionary
	if OS.get_name() == "Web" and Player_Origin.user_nsec.begins_with("nsec1"):
		if not await _ensure_nostr_ready():
			push_error("NOSTR: _broadcast_to — JS indisponible, événement abandonné"); return
		var ev_json := JSON.stringify(ev)
		var nsec := Player_Origin.user_nsec
		var js := (
			"(function(){try{"
			+ "var lib=window.NostrTools;"
			+ "var dec=lib.nip19.decode('" + nsec + "');"
			+ "var ev=" + ev_json + ";"
			+ "var s=lib.finalizeEvent?lib.finalizeEvent(ev,dec.data):lib.finishEvent(ev,dec.data);"
			+ "return JSON.stringify(s);"
			+ "}catch(e){return null;}})()"
		)
		var result: Variant = JavaScriptBridge.eval(js)
		if result != null and str(result) != "null":
			var j := JSON.new()
			if j.parse(str(result)) == OK and j.data is Dictionary:
				signed_ev = j.data
	else:
		# Android / Desktop : signature GDScript locale
		signed_ev = NostrCrypto.sign_event_local(ev, Player_Origin.user_nsec)

	if signed_ev.is_empty() or signed_ev.get("sig", "").is_empty():
		push_error("NOSTR: _broadcast_to — signature échouée, événement abandonné"); return

	# Diffusion via WebSocket native — envoi direct si relais déjà ouvert, file sinon
	var msg := JSON.stringify(["EVENT", signed_ev])
	for url in targets:
		if _ws.has(url) and (_ws[url] as WebSocketPeer).get_ready_state() == WebSocketPeer.STATE_OPEN:
			(_ws[url] as WebSocketPeer).send_text(msg)
		else:
			if not _ws.has(url): connect_relay(url)
			if not _queue.has(url): _queue[url] = []
			(_queue[url] as Array).append(msg)

# ───────────────────────────────────────────────
# KIND 3 — LISTE DE FOLLOWS (CONTACT LIST)
# ───────────────────────────────────────────────

func build_kind3() -> Dictionary:
	var tags := []
	var relay_hint: String = relay_list[0] if relay_list.size() > 0 else "wss://relay.copylaradio.com"
	for hex in follows:
		tags.append(["p", hex, relay_hint, ""])
	var ev := make_event(3, "", tags)
	ev["id"] = compute_event_id(ev)
	return ev

func follow(hex: String):
	if not follows.has(hex):
		follows.append(hex)
		mutes.erase(hex)
		_save_social()
		emit_signal("follows_updated", follows)

func unfollow(hex: String):
	follows.erase(hex)
	_save_social()
	emit_signal("follows_updated", follows)

func mute(hex: String):
	if not mutes.has(hex):
		mutes.append(hex)
		follows.erase(hex)
		_save_social()

func unmute(hex: String):
	mutes.erase(hex)
	_save_social()

func publish_kind3():
	if follows.is_empty(): return
	var ev := build_kind3()
	sign_and_send(ev)

func is_following(hex: String) -> bool: return follows.has(hex)
func is_muted(hex: String) -> bool:     return mutes.has(hex)

# ───────────────────────────────────────────────
# DÉRIVATION nsec1 → nsec2 (MULTIPASS) — INUTILISÉE / OBSOLÈTE
# ───────────────────────────────────────────────
# Aucun appelant dans le projet (signal nsec2_derived jamais émis ailleurs) —
# conservée pour référence historique uniquement. Le serveur (make_NOSTRCARD.sh)
# force désormais TOUJOURS un SALT/PEPPER aléatoire pour l'identité MULTIPASS
# (voir Phi2X_Math.gd, note en tête du bloc géométrie), donc UPlanet_API.forge_multipass()
# n'accepte plus de salt/pepper client — dériver nsec2 depuis nsec1 de cette façon
# n'a plus de sens et ne produirait plus une identité déterministe.

func derive_nsec2_from_nsec1(_nsec1_bech32: String, email: String):
	push_warning("Nostr_Identity: derive_nsec2_from_nsec1() est obsolète — "
		+ "forge_multipass() ne dérive plus jamais l'identité MULTIPASS d'un secret "
		+ "fourni par le client (voir make_NOSTRCARD.sh::_A4L_BIRTH_CONTEXT).")
	UPlanet_API.forge_multipass(email,
		SpaceTime_Manager.current_gps.x, SpaceTime_Manager.current_gps.y)

# ───────────────────────────────────────────────
# MISE À JOUR PROFIL
# ───────────────────────────────────────────────

func set_profile_field(field: String, value: String):
	profile[field] = value

func get_profile_field(field: String) -> String:
	return profile.get(field, "")

# ───────────────────────────────────────────────
# PERSISTENCE
# ───────────────────────────────────────────────

func save_all():
	_save_profile()
	_save_social()

func _save_json(path: String, data: Variant):
	var file := FileAccess.open(path, FileAccess.WRITE)
	if not file:
		push_error("Nostr_Identity: écriture impossible → %s (erreur %d)" % [path, FileAccess.get_open_error()])
		return
	file.store_string(JSON.stringify(data))

func _load_json(path: String) -> Variant:
	if not FileAccess.file_exists(path): return null
	var file := FileAccess.open(path, FileAccess.READ)
	if not file: return null
	var j := JSON.new()
	if j.parse(file.get_as_text()) == OK: return j.data
	return null

func _save_profile():
	_save_json(SAVE_PROFILE, profile)

func _load_profile():
	var data = _load_json(SAVE_PROFILE)
	if data is Dictionary:
		for k in data: profile[k] = data[k]

func _save_social():
	_save_json(SAVE_SOCIAL, {"follows": follows, "mutes": mutes, "relays": relay_list})

func _load_social():
	var data = _load_json(SAVE_SOCIAL)
	if data is Dictionary:
		follows    = data.get("follows", [])
		mutes      = data.get("mutes", [])
		relay_list = data.get("relays", [])

# ───────────────────────────────────────────────
# ROAMING — Home station & DM NIP-44 inter-node
# ───────────────────────────────────────────────

# Extrait NODE_NOSTR_HEX depuis le champ home_station du profil kind 0.
# Format attendu : "IPFSNODEID:NODE_NOSTR_HEX" (posé par nostr_setup_profile.py)
func _parse_home_station_from_kind0(ev: Dictionary) -> void:
	var j := JSON.new()
	if j.parse(ev.get("content", "{}")) != OK: return
	var meta: Dictionary = j.data if j.data is Dictionary else {}
	var hs: String = meta.get("home_station", "")
	if hs.contains(":"):
		var parts := hs.split(":", false, 1)
		if parts.size() == 2 and parts[1].length() == 64:
			Player_Origin.home_node_hex = parts[1]
			print("🏠 home_node_hex mis à jour : %s…" % parts[1].substr(0, 12))

# Envoie un DM NIP-44 inter-node pour relayer une action uDRIVE vers la home station.
# Appelé par UPlanet_API quand /api/fileupload retourne 401 (roaming détecté).
# payload_dict = {"channel":"udrive","payload":{"email","cid","filename","filetype"}}
func send_udrive_dm(recipient_hex: String, payload_dict: Dictionary) -> void:
	if Player_Origin.user_hex.is_empty() or Player_Origin.user_nsec.is_empty():
		push_error("NOSTR: send_udrive_dm — pas de MULTIPASS"); return
	if recipient_hex.length() != 64 or not recipient_hex.is_valid_hex_number():
		push_error("NOSTR: send_udrive_dm — recipient_hex invalide (attendu: 64 chars hex)"); return

	var plaintext := JSON.stringify(payload_dict)

	if OS.get_name() == "Web" and _check_nostr_ready():
		_send_dm_nip44_js(recipient_hex, plaintext)
	else:
		# Android / Desktop : proxy via UPassport (encryption côté serveur)
		# UPassport utilise nostr_send_secure_dm.py avec le nsec du joueur
		UPlanet_API.send_secure_dm_proxy(recipient_hex, plaintext)

func _send_dm_nip44_js(recipient_hex: String, plaintext: String) -> void:
	var nsec := Player_Origin.user_nsec
	# NIP-44 synchrone dans nostr-tools — pas d'await nécessaire
	# Fallback NIP-04 si nip44 absent de la version du bundle
	var js := (
		"(function(){"
		+ "try{"
		+ "var lib=window.NostrTools;"
		+ "if(!lib||!lib.nip19) return null;"
		+ "var priv=lib.nip19.decode('" + nsec + "').data;"
		+ "var pub='" + recipient_hex + "';"
		+ "var plain=" + JSON.stringify(plaintext) + ";"
		+ "var enc;"
		+ "if(lib.nip44&&lib.nip44.v2&&lib.nip44.v2.encrypt){"
		+ "  var ck=lib.nip44.v2.utils.getConversationKey(priv,pub);"
		+ "  enc=lib.nip44.v2.encrypt(plain,ck);"
		+ "} else if(lib.nip04){"
		+ "  enc=lib.nip04.encrypt(priv,pub,plain);" # sync dans certaines versions
		+ "} else { return null; }"
		+ "var ev={kind:4,pubkey:lib.getPublicKey(priv),"
		+ "created_at:Math.floor(Date.now()/1000),"
		+ "tags:[['p',pub]],content:enc};"
		+ "var signed=lib.finalizeEvent(ev,priv)||lib.finishEvent(ev,priv);"
		+ "return JSON.stringify(signed);"
		+ "}catch(e){console.error('[A4L] DM NIP-44 error:',e);return null;}"
		+ "})()"
	)
	var result: Variant = JavaScriptBridge.eval(js)
	if result != null and str(result) != "null" and str(result) != "":
		var j := JSON.new()
		if j.parse(str(result)) == OK and j.data is Dictionary:
			publish_raw(j.data)
			print("📨 DM NIP-44 envoyé vers home node %s…" % recipient_hex.substr(0, 12))
			return
	push_error("NOSTR: DM NIP-44 JS échoué — fallback proxy UPassport")
	UPlanet_API.send_secure_dm_proxy(recipient_hex, plaintext)
