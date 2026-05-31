extends Node
# Bibliothèque NOSTR interne — ATOM4LOVE
# WebSocket multi-relais, Kind 0/3, ID SHA256, dérivation nsec1→nsec2

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
var follows: Array = []    # hex pubkeys suivis
var mutes: Array = []      # hex pubkeys silencés
var relay_list: Array = [] # wss:// URLs actifs

# Relais publics par défaut (population initiale)
const PUBLIC_RELAYS: Array = [
	"wss://relay.damus.io",
	"wss://nostr.wine",
	"wss://relay.snort.social",
	"wss://nos.lol",
	"wss://relay.copylaradio.com"
]

const SAVE_PROFILE = "user://nostr_profile.json"
const SAVE_SOCIAL  = "user://nostr_social.json"

# --- CONNEXIONS WEBSOCKET ---
# { relay_url → WebSocketPeer }
var _ws: Dictionary = {}
# Événements en attente d'une connexion ouverte
var _queue: Array = []
# { sub_id → filter_dict }
var _subs: Dictionary = {}
# Relais déjà initialisés (subs envoyés)
var _initialized_relays: Dictionary = {}

func _ready():
	set_process(false)
	_load_profile()
	_load_social()
	# Pré-remplir g1pub depuis MULTIPASS si dispo
	if Player_Origin.is_initialized and profile["g1pub"].is_empty():
		profile["g1pub"] = Player_Origin.user_g1pub

# ───────────────────────────────────────────────
# GESTION DES RELAIS
# ───────────────────────────────────────────────

func connect_relay(url: String):
	if _ws.has(url): return
	var ws = WebSocketPeer.new()
	var err = ws.connect_to_url(url)
	if err != OK:
		push_error("NOSTR: connect_to_url(%s) failed → %d" % [url, err])
		return
	_ws[url] = ws
	set_process(true)
	print("📡 NOSTR: Connexion à %s…" % url)

func connect_relay_list():
	var targets = relay_list if relay_list.size() > 0 else PUBLIC_RELAYS
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

func _process(_delta):
	var dead: Array = []
	for url in _ws.keys():
		var ws := _ws[url] as WebSocketPeer
		ws.poll()
		match ws.get_ready_state():
			WebSocketPeer.STATE_OPEN:
				if not _initialized_relays.get(url, false):
					_initialized_relays[url] = true
					# Rejouer les subs actifs + queue pour ce nouveau relais
					for sub_id in _subs:
						ws.send_text(JSON.stringify(["REQ", sub_id, _subs[sub_id]]))
					for msg in _queue: ws.send_text(msg)
					_queue.clear()
				while ws.get_available_packet_count() > 0:
					var pkt = ws.get_packet()
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
	if _ws.is_empty(): set_process(false)

func _parse_message(url: String, text: String):
	var msg = JSON.parse_string(text)
	if msg == null: return
	if not (msg is Array) or msg.size() < 2: return
	match str(msg[0]):
		"EVENT":
			if msg.size() >= 3 and msg[2] is Dictionary:
				emit_signal("event_received", msg[2])
		"EOSE":
			pass
		"NOTICE":
			print("NOSTR NOTICE [%s]: %s" % [url, msg[1]])
		"OK":
			# ["OK", event_id, true/false, message]
			if msg.size() >= 3 and str(msg[2]) == "true":
				pass  # Publication confirmée
		_:
			pass

# ───────────────────────────────────────────────
# PROTOCOLE NOSTR (REQ / EVENT / CLOSE)
# ───────────────────────────────────────────────

func subscribe(filter: Dictionary) -> String:
	var sub_id = "a4l_" + str(Time.get_unix_time_from_system()).sha256_text().substr(0, 8)
	_subs[sub_id] = filter
	_broadcast(JSON.stringify(["REQ", sub_id, filter]))
	return sub_id

func unsubscribe(sub_id: String):
	_subs.erase(sub_id)
	_broadcast(JSON.stringify(["CLOSE", sub_id]))

func publish_raw(event: Dictionary):
	_broadcast(JSON.stringify(["EVENT", event]))

func _broadcast(text: String):
	var sent := false
	for url in _ws.keys():
		var ws := _ws[url] as WebSocketPeer
		if ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
			ws.send_text(text)
			sent = true
	if not sent:
		_queue.append(text)

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
		"sig": ""   # Rempli par sign_and_send()
	}

func compute_event_id(ev: Dictionary) -> String:
	# Sérialisation canonique NIP-01
	var serialized := JSON.stringify([
		0,
		ev["pubkey"],
		ev["created_at"],
		ev["kind"],
		ev["tags"],
		ev["content"]
	])
	var buf := serialized.to_utf8_buffer()
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(buf)
	return ctx.finish().hex_encode()

func sign_and_send(ev: Dictionary):
	ev["id"] = compute_event_id(ev)
	if OS.get_name() == "Web" and Player_Origin.user_nsec.begins_with("nsec1"):
		_sign_via_js(ev)
	else:
		UPlanet_API.sign_and_publish(ev, Player_Origin.user_nsec)

func _sign_via_js(ev: Dictionary):
	# Appelle NostrTools.finishEvent() via JavaScriptBridge (export Web uniquement)
	# nostr.bundle.js doit être présent dans le template d'export HTML5
	# IMPORTANT : concaténation (pas %) — ev_json peut contenir des '%' dans les URLs
	var ev_json = JSON.stringify(ev)
	var nsec = Player_Origin.user_nsec
	var js = (
		"(function() {"
		+ "var lib=window.NostrTools;"
		+ "if(!lib||!lib.nip19||!lib.finishEvent)return null;"
		+ "try{"
		+ "var ev=" + ev_json + ";"
		+ "var dec=lib.nip19.decode('" + nsec + "');"
		+ "if(!dec||dec.type!=='nsec')return null;"
		+ "var signed=lib.finishEvent(ev,dec.data);"
		+ "return JSON.stringify(signed);"
		+ "}catch(e){return null;}"
		+ "})()"
	)
	var result = JavaScriptBridge.eval(js)
	if result != null and str(result) != "null" and str(result) != "":
		var j = JSON.new()
		if j.parse(str(result)) == OK and j.data is Dictionary:
			publish_raw(j.data)
			return
	# Fallback : proxy UPassport
	UPlanet_API.sign_and_publish(ev, Player_Origin.user_nsec)

# ───────────────────────────────────────────────
# KIND 0 — PROFIL MÉTADONNÉES
# ───────────────────────────────────────────────

func build_kind0() -> Dictionary:
	var content_dict := {
		"name":    profile.get("name", ""),
		"about":   profile.get("about", ""),
		"picture": profile.get("picture", ""),
		"nip05":   profile.get("nip05", ""),
		"website": profile.get("website", ""),
		"g1pub":   profile.get("g1pub", Player_Origin.user_g1pub),
		"banner":  profile.get("banner", "")
	}
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
	var n := _ws.size()
	emit_signal("profile_published", n)

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
# DÉRIVATION nsec1 → nsec2 (MULTIPASS)
# Coupe nsec1 en 2 moitiés égales : salt = 1ère moitié, pepper = 2ème moitié
# POST /g1nostr(email, salt, pepper) → reçoit nsec2, npub2, hex2, g1pub2
# ───────────────────────────────────────────────

func derive_nsec2_from_nsec1(nsec1_bech32: String, email: String):
	if not nsec1_bech32.begins_with("nsec1"):
		push_error("Nostr_Identity: format nsec1 invalide (doit commencer par 'nsec1')")
		return
	var key_mat := nsec1_bech32.substr(5)  # retire préfixe "nsec1"
	if key_mat.length() < 10:
		push_error("Nostr_Identity: nsec1 trop court")
		return
	var mid := key_mat.length() / 2
	var salt   := key_mat.substr(0, mid)
	var pepper := key_mat.substr(mid)
	print("🔑 MULTIPASS: dérivation nsec2 depuis nsec1 (salt=%d chars, pepper=%d chars)" % [salt.length(), pepper.length()])
	UPlanet_API.forge_multipass_with_salt(email, salt, pepper,
		SpaceTime_Manager.current_gps.x, SpaceTime_Manager.current_gps.y)

# ───────────────────────────────────────────────
# MISE À JOUR PROFIL (sans publier)
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

func _save_profile():
	var file := FileAccess.open(SAVE_PROFILE, FileAccess.WRITE)
	if not file:
		push_error("Nostr_Identity: écriture profil impossible")
		return
	file.store_string(JSON.stringify(profile))

func _load_profile():
	if not FileAccess.file_exists(SAVE_PROFILE): return
	var file := FileAccess.open(SAVE_PROFILE, FileAccess.READ)
	if not file: return
	var j := JSON.new()
	if j.parse(file.get_as_text()) == OK and j.data is Dictionary:
		for k in j.data: profile[k] = j.data[k]

func _save_social():
	var file := FileAccess.open(SAVE_SOCIAL, FileAccess.WRITE)
	if not file: return
	file.store_string(JSON.stringify({
		"follows": follows, "mutes": mutes, "relays": relay_list
	}))

func _load_social():
	if not FileAccess.file_exists(SAVE_SOCIAL): return
	var file := FileAccess.open(SAVE_SOCIAL, FileAccess.READ)
	if not file: return
	var j := JSON.new()
	if j.parse(file.get_as_text()) == OK and j.data is Dictionary:
		follows    = j.data.get("follows", [])
		mutes      = j.data.get("mutes", [])
		relay_list = j.data.get("relays", [])
