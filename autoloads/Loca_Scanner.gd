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
const SUPER_COHERENCE_THRESHOLD: float = 0.95
const APK_SERVER_PORT: int = 8080

var is_scanning: bool = false
# { npub_short → { k, phase, sex, last_seen_unix } }
var discovered_atoms: Dictionary = {}

var _scan_timer: Timer
var _apk_server: TCPServer = null
var _apk_server_active: bool = false
var _apk_server_url: String = ""

func _ready():
	_scan_timer = Timer.new()
	_scan_timer.wait_time = SCAN_INTERVAL_S
	_scan_timer.connect("timeout", Callable(self, "_on_scan_tick"))
	add_child(_scan_timer)
	set_process(false)

# --- GESTION DU SCAN LOCA ---

func start_scan():
	if is_scanning: return
	is_scanning = true
	discovered_atoms.clear()
	_scan_timer.start()
	emit_signal("scan_state_changed", true)
	print("📡 LOCA: Scan ATOM démarré (intervalle %.1fs)..." % SCAN_INTERVAL_S)

func stop_scan():
	if not is_scanning: return
	is_scanning = false
	_scan_timer.stop()
	emit_signal("scan_state_changed", false)
	print("📡 LOCA: Scan ATOM arrêté.")

func _on_scan_tick():
	# Production : appel plugin BLE Godot Android/iOS
	# Fallback : parseur de SSID WiFi de la forme "A4L_<npub8>_<sex>_<phase>"
	# Simulation : génère des atomes aléatoires pour les tests en éditeur
	_simulate_loca_detection()

func _simulate_loca_detection():
	if randf() < 0.35:
		var mock_npub = "npub1_" + str(randi() % 10000).pad_zeros(4)
		var mock_sex = randi() % 2
		var mock_phase = randf() * Phi2X_Math.PHASE_MODULUS
		_process_detected_atom(mock_npub, mock_sex, mock_phase)

func process_wifi_ssid(ssid: String):
	# Format SSID : "A4L-<npub8>-<sex>-<phase>"
	# split("-") donne ["A4L", npub, sex, phase] → 4 champs minimum
	if not ssid.begins_with(BLE_PACKET_PREFIX): return
	var parts = ssid.split("-")
	if parts.size() < 4: return
	var npub_short: String = parts[1]
	var sex: int = int(parts[2])
	var phase: float = float(parts[3])
	if npub_short.length() < 4 or sex < 0 or sex > 1: return  # Validation minimale
	_process_detected_atom(npub_short, sex, phase)

func _process_detected_atom(npub_short: String, sex: int, remote_phase: float):
	var my_phase = Player_Origin.personal_phase
	var k = Phi2X_Math.compute_resonance_k(my_phase, remote_phase)

	discovered_atoms[npub_short] = {
		"k": k, "phase": remote_phase, "sex": sex,
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
	return "A4L-%s-%d-%.4f" % [npub_short, Player_Origin.biological_sex, Player_Origin.personal_phase]

func get_sorted_by_resonance() -> Array:
	# Retourne la liste triée par taux k décroissant
	var entries = []
	for npub in discovered_atoms:
		var atom = discovered_atoms[npub].duplicate()
		atom["npub"] = npub
		entries.append(atom)
	entries.sort_custom(func(a, b): return a["k"] > b["k"])
	return entries

# --- SERVEUR P2P POUR DISTRIBUTION APK (Module 2 - Viralité) ---

func start_apk_server():
    if OS.has_feature("web"):
        push_error("Le serveur TCP n'est pas supporté sur navigateur.")
        emit_signal("apk_server_stopped") # ou un signal d'erreur UI
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

func _serve_http_response(peer: StreamPeerTCP):
	var ssid = build_broadcast_ssid()
	var html = """<!DOCTYPE html>
<html lang="fr">
<head><meta charset="UTF-8"><title>ATOM4LOVE</title>
<style>body{background:#050d1a;color:#00c8ff;font-family:monospace;text-align:center;padding:40px}
a{color:#ffd700;font-size:1.3em}</style></head>
<body>
<h1>⚛ ATOM4LOVE</h1>
<p>Interféromètre cosmique et social</p>
<p><a href="atom4love.apk">📥 Télécharger ATOM4LOVE.apk</a></p>
<hr>
<p style="font-size:0.8em">SSID Émetteur : %s</p>
</body></html>""" % ssid

	var html_bytes = html.to_utf8_buffer()
	var response = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\n"
	response += "Content-Length: %d\r\n\r\n" % html_bytes.size()
	peer.put_data(response.to_utf8_buffer())
	peer.put_data(html_bytes)
	peer.disconnect_from_host()
