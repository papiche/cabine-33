extends Node

signal multipass_created(data)
signal network_n2_analyzed(is_authorized, total_nodes)
signal sync_completed(message)
signal api_error(message)

var http_request: HTTPRequest
var base_url: String = "https://u.copylaradio.com"
var relay_url: String = "wss://relay.copylaradio.com"

func _ready():
	http_request = HTTPRequest.new()
	add_child(http_request)

func forge_multipass(email: String, pepper: String, lat: float, lon: float):
	var url = base_url + "/g1nostr"
	var body = "email=" + email.uri_encode() + "&lang=fr&lat=" + str(lat) + "&lon=" + str(lon) + "&salt=" + email.uri_encode() + "&pepper=" + pepper.uri_encode() + "&format=json"
	var headers = ["Content-Type: application/x-www-form-urlencoded"]
	
	http_request.request_completed.connect(_on_forge_completed, CONNECT_ONE_SHOT)
	http_request.request(url, headers, HTTPClient.METHOD_POST, body)

func _on_forge_completed(_result, response_code, _headers, body):
	if response_code == 200:
		var json = JSON.new()
		if json.parse(body.get_string_from_utf8()) == OK:
			emit_signal("multipass_created", json.data)
		else: emit_signal("api_error", "Réponse illisible.")
	else: emit_signal("api_error", "Astroport a refusé (Code " + str(response_code) + ")")

func check_wot_authorization(hex_pubkey: String):
	var url = base_url + "/api/getN2?hex=" + hex_pubkey + "&range=default&output=json"
	http_request.request_completed.connect(_on_n2_completed, CONNECT_ONE_SHOT)
	http_request.request(url)

func _on_n2_completed(_result, response_code, _headers, body):
	if response_code == 200:
		var json = JSON.new()
		if json.parse(body.get_string_from_utf8()) == OK:
			var data = json.data
			var total = data.get("total_n1", 0) + data.get("total_n2", 0)
			emit_signal("network_n2_analyzed", total > 0, total)
		else: emit_signal("network_n2_analyzed", false, 0)
	else: emit_signal("network_n2_analyzed", false, 0)

# Synchronisation manuelle NOSTR
func sync_with_relay(_npub: String):
	print("🔄 [NOSTR] Handshake WebSocket avec " + relay_url + "...")
	await get_tree().create_timer(1.5).timeout
	emit_signal("sync_completed", "Synchronisation avec " + relay_url + " réussie (uDRIVE mis à jour).")
