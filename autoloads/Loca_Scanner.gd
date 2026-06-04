extends Node
# Mode LOCA — Découverte de résonances environnantes (BLE/WiFi + Partage APK P2P)
# Module 2 du cahier des charges ATOM4LOVE

signal atom_detected(npub_short, k_value, phase, sex)
signal super_coherence_match(npub_short, k_value)
signal scan_state_changed(is_scanning)
signal apk_server_started(local_url)
signal apk_server_stopped

const BLE_PACKET_PREFIX: String = "A4L-"  # Format: A4L-<npub8>-<sex>-<phase>
const SCAN_INTERVAL_S: float = 2.0
const SUPER_COHERENCE_THRESHOLD: float = Atom4Peace.SUPER_COHERENCE_K  # source unique dans Atom4Peace
const APK_SERVER_PORT: int = 8080

var is_scanning: bool = false
# { npub_short → { k, phase, sex, last_seen_unix } }
var discovered_atoms: Dictionary = {}

var _scan_timer: Timer
var _apk_server: TCPServer = null
var _apk_server_active: bool = false
var _apk_server_url: String = ""

var _was_scanning_before_pause: bool = false

func _ready():
	_scan_timer = Timer.new()
	_scan_timer.wait_time = SCAN_INTERVAL_S
	_scan_timer.connect("timeout", Callable(self, "_on_scan_tick"))
	add_child(_scan_timer)
	set_process(false)

func _notification(what: int):
	match what:
		NOTIFICATION_APPLICATION_FOCUS_OUT:
			# App en arrière-plan ou écran éteint → mémoriser si scan actif
			_was_scanning_before_pause = is_scanning
			# On maintient le scan actif grâce à WAKE_LOCK + screen_set_keep_on
			# Mais si l'OS suspend le process, le scan s'arrêtera quand même
		NOTIFICATION_APPLICATION_FOCUS_IN:
			# App revenue au premier plan → réactiver l'écran allumé si scan était actif
			if _was_scanning_before_pause and is_scanning:
				if OS.has_feature("android") or OS.has_feature("mobile"):
					DisplayServer.screen_set_keep_on(true)
			_was_scanning_before_pause = false

# --- GESTION DU SCAN LOCA ---

func start_scan():
	if is_scanning: return
	is_scanning = true
	discovered_atoms.clear()
	_scan_timer.start()
	emit_signal("scan_state_changed", true)
	# Garder l'écran allumé pendant le scan LOCA (Android)
	# Note : WAKE_LOCK permission requise dans export_presets.cfg
	# Une vraie implémentation ForegroundService nécessiterait un plugin Godot Android.
	# Pour l'alpha, on garde l'écran allumé — l'utilisateur est en mode actif (proximité).
	if OS.has_feature("android") or OS.has_feature("mobile"):
		DisplayServer.screen_set_keep_on(true)
	print("📡 LOCA: Scan ATOM démarré (intervalle %.1fs)..." % SCAN_INTERVAL_S)

func stop_scan():
	if not is_scanning: return
	is_scanning = false
	_scan_timer.stop()
	discovered_atoms.clear()
	emit_signal("scan_state_changed", false)
	# Rendre le contrôle de l'écran à l'OS
	if OS.has_feature("android") or OS.has_feature("mobile"):
		DisplayServer.screen_set_keep_on(false)
	print("📡 LOCA: Scan ATOM arrêté.")

func _on_scan_tick():
	# Production : appel plugin BLE Godot Android/iOS
	# Fallback : parseur de SSID WiFi de la forme "A4L_<npub8>_<sex>_<phase>"
	# Simulation : génère des atomes aléatoires pour les tests en éditeur
	evict_stale_atoms()
	_simulate_loca_detection()

func _simulate_loca_detection():
	if randf() < 0.35:
		var mock_npub = "npub1_" + str(randi() % 10000).pad_zeros(4)
		var mock_sex = randi() % 2
		var mock_phase = randf() * Phi2X_Math.PHASE_MODULUS
		_process_detected_atom(mock_npub, mock_sex, mock_phase)

func process_wifi_ssid(ssid: String):
	# Format SSID v3 : "A4L-<npub8>-<sex>-<phase>-<inst_id>-<kin_gi>"
	# split avec max_split=6 évite que un '-' dans npub casse le parsing
	if not ssid.begins_with(BLE_PACKET_PREFIX): return
	var parts := ssid.split("-", false, 6)  # max 6 champs, ignore les vides
	if parts.size() < 4: return
	var npub_short: String = parts[1]
	var sex: int    = parts[2].to_int()
	var phase: float = parts[3].to_float()
	var inst: int   = parts[4].to_int() if parts.size() >= 5 else 0
	var kin_gi: int = parts[5].to_int() if parts.size() >= 6 else 99  # 99=inconnu
	# Validation stricte : npub 8 chars alnum, sex binaire, phase physique
	if npub_short.length() < 4: return
	if not npub_short.is_valid_identifier() and not npub_short.is_valid_hex_number(): return
	if sex < 0 or sex > 1: return
	if phase < 0.0 or phase > TAU * 1.1: return  # hors plage physique → rejet
	_process_detected_atom(npub_short, sex, phase, inst, kin_gi)

func _process_detected_atom(npub_short: String, sex: int, remote_phase: float,
		inst: int = 0, kin_gi: int = 99):  # 99=inconnu (pas -1 qui produit "--1" dans le SSID)
	var my_phase = Player_Origin.personal_phase
	var k = Phi2X_Math.compute_resonance_k(my_phase, remote_phase)
	discovered_atoms[npub_short] = {
		"k": k, "phase": remote_phase, "sex": sex, "inst": inst,
		"kin_gi": kin_gi,  # Sceau Maya (0-19), -1=inconnu
		"last_seen_unix": Time.get_unix_time_from_system()
	}

	emit_signal("atom_detected", npub_short, k, remote_phase, sex)

	if k >= SUPER_COHERENCE_THRESHOLD:
		emit_signal("super_coherence_match", npub_short, k)
		Atom4Peace.process_resonance_encounter(
			Player_Origin.user_npub, npub_short,
			remote_phase, sex, SpaceTime_Manager.current_gps
		)

func build_broadcast_ssid() -> String:
	# Format : "A4L-<npub8>-<sex>-<phase>"
	# Nettoie "_" et "-" du npub (bech32 contient des underscores dans la version mock)
	var npub_raw := Player_Origin.user_npub
	var npub_clean := npub_raw.replace("_", "").replace("-", "")
	var npub_short := npub_clean.substr(0, 8) if npub_clean.length() >= 8 else "anon0000"
	var inst_id := Voice_Sampler.get_inst_id() if Engine.has_singleton("Voice_Sampler") or is_instance_valid(Voice_Sampler) else 0
	# 99 = "inconnu" (au lieu de -1 qui crée "--1" dans le SSID et casse le split("-"))
	var my_kin_gi := 99
	if Player_Origin.birth_unix > 0:
		var kd: Dictionary = Kin_Maya.calc_kin_unix(Player_Origin.birth_unix)
		my_kin_gi = kd.get("gi", 99)  # gi ∈ [0,19], 99 = non défini
	return "A4L-%s-%d-%.4f-%d-%d" % [npub_short, Player_Origin.biological_sex, Player_Origin.personal_phase, inst_id, my_kin_gi]

func get_sorted_by_resonance() -> Array:
	# Retourne la liste triée par taux k décroissant (tiebreaker : last_seen_unix)
	var entries = []
	for npub in discovered_atoms:
		var atom = discovered_atoms[npub].duplicate()
		atom["npub"] = npub
		entries.append(atom)
	entries.sort_custom(func(a, b):
		if absf(a["k"] - b["k"]) > 0.0001: return a["k"] > b["k"]
		return a.get("last_seen_unix", 0) > b.get("last_seen_unix", 0))
	return entries

func evict_stale_atoms(max_age_s: float = 30.0):
	var now := Time.get_unix_time_from_system()
	var stale: Array = []
	for npub in discovered_atoms:
		if now - discovered_atoms[npub].get("last_seen_unix", 0) > max_age_s:
			stale.append(npub)
	for npub in stale:
		discovered_atoms.erase(npub)

# --- SERVEUR P2P POUR DISTRIBUTION APK (Module 2 - Viralité) ---

func start_apk_server():
	if OS.has_feature("web"):
		push_error("Le serveur TCP n'est pas supporté sur navigateur.")
		emit_signal("apk_server_stopped")
		return
	if _apk_server_active: return
	_apk_server = TCPServer.new()
	if _apk_server.listen(APK_SERVER_PORT) != OK:
		push_error("LOCA: Impossible de démarrer le serveur APK sur le port %d" % APK_SERVER_PORT)
		return
	_apk_server_active = true
	set_process(true)

	var addresses = IP.get_local_addresses()
	var local_ip = "192.168.43.1"
	for addr in addresses:
		if addr.begins_with("192.168.") or addr.begins_with("10."):
			local_ip = addr
			break
	_apk_server_url = "http://%s:%d/" % [local_ip, APK_SERVER_PORT]
	emit_signal("apk_server_started", _apk_server_url)
	print("🌐 LOCA: Serveur APK actif → " + _apk_server_url)

func stop_apk_server():
	if _apk_server_active and _apk_server:
		_apk_server.stop()
	_apk_server_active = false
	set_process(false)
	emit_signal("apk_server_stopped")

func get_apk_server_url() -> String:
	return _apk_server_url

func _process(_delta):
	if not _apk_server_active or not _apk_server: return
	if _apk_server.is_connection_available():
		var peer = _apk_server.take_connection()
		_serve_http_response(peer)

func _serve_http_response(peer: StreamPeerTCP) -> void:
	var ssid = build_broadcast_ssid()
	# Portail de redirection : ne sert pas le .apk localement (impossible sur Android),
	# redirige vers l'URL officielle F-Droid / UPlanet
	var html = """<!DOCTYPE html>
<html lang="fr">
<head><meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>ATOM4LOVE</title>
<style>body{background:#050d1a;color:#00c8ff;font-family:monospace;text-align:center;padding:40px}
a.btn{display:inline-block;margin:10px;padding:16px 28px;background:#1a3a5c;color:#ffd700;
text-decoration:none;border-radius:12px;font-size:1.1em;border:1px solid #ffd70055}
</style></head>
<body>
<h1>⚛ ATOM4LOVE</h1>
<p>Interféromètre cosmique et social</p>
<a class="btn" href="https://u.copylaradio.com/apk/atom4love.apk">📥 Télécharger ATOM4LOVE.apk</a>
<a class="btn" href="https://atom4love.copylaradio.com">🌐 Version Web (PWA)</a>
<hr><p style="font-size:0.75em;opacity:0.6">Émetteur : %s</p>
</body></html>""" % ssid

	var html_bytes = html.to_utf8_buffer()
	var response = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\n"
	response += "Content-Length: %d\r\n\r\n" % html_bytes.size()
	peer.put_data(response.to_utf8_buffer())
	peer.put_data(html_bytes)
	# Attendre que l'OS flushe le buffer TCP sans bloquer le thread principal
	# OS.delay_msec() gèlerait toute l'app si plusieurs clients se connectent simultanément
	await get_tree().create_timer(0.15).timeout
	peer.disconnect_from_host()
