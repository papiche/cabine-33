extends Node

signal cache_purged(thought_count)
signal thought_added(thought_text)

const CACHE_PATH := "user://thought_cache.json"

var local_thoughts: Array = []

func _ready():
	_load_from_disk()

func capture_thought(text: String, gps_location: Dictionary):
	if text.strip_edges() == "": return
	var lat: float = gps_location.get("lat", 0.0)
	var lon: float = gps_location.get("lon", 0.0)
	var thought := {
		"timestamp": Time.get_unix_time_from_system(),
		"location": gps_location,
		"text": text,
		"resonance": Phi2X_Math.get_nearest_phi_node(lat, lon).get("resonance_strength", 0.0)
	}
	local_thoughts.append(thought)
	_save_to_disk()
	emit_signal("thought_added", text)

func _save_to_disk():
	var f := FileAccess.open(CACHE_PATH, FileAccess.WRITE)
	if f: f.store_string(JSON.stringify(local_thoughts))

func _load_from_disk():
	if not FileAccess.file_exists(CACHE_PATH): return
	var f := FileAccess.open(CACHE_PATH, FileAccess.READ)
	if not f: return
	var j := JSON.new()
	if j.parse(f.get_as_text()) == OK and j.data is Array:
		local_thoughts = j.data
		print("💭 Thought_Cache: %d pensées restaurées depuis le disque." % local_thoughts.size())

# Purge locale (sans upload — utilisée par SpaceTime_Manager la nuit si hors ligne)
func purge_to_spacememory() -> Array:
	var count := local_thoughts.size()
	var archived_thoughts := local_thoughts.duplicate()
	local_thoughts.clear()
	if FileAccess.file_exists(CACHE_PATH):
		DirAccess.remove_absolute(CACHE_PATH)
	emit_signal("cache_purged", count)
	return archived_thoughts

# Retourne les pensées empaquetées en JSON prêt à uploader
func to_json_bytes() -> PackedByteArray:
	var payload := {
		"type":     "spacememory",
		"date":     Time.get_date_string_from_system(),
		"count":    local_thoughts.size(),
		"thoughts": local_thoughts
	}
	return JSON.stringify(payload, "  ").to_utf8_buffer()

# Upload vers uDRIVE à la demande (n'efface le cache qu'en cas de succès).
# Connecter UPlanet_API.udrive_uploaded → clear_cache() depuis Main_UI.
func sync_to_udrive() -> void:
	if local_thoughts.is_empty(): return
	var filename := "spacememory_%s.json" % Time.get_date_string_from_system()
	UPlanet_API.upload_to_udrive(to_json_bytes(), filename, "application/json")

func clear_cache() -> void:
	local_thoughts.clear()
	if FileAccess.file_exists(CACHE_PATH):
		DirAccess.remove_absolute(CACHE_PATH)
	emit_signal("cache_purged", 0)
