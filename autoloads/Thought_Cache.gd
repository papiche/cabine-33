extends Node

signal cache_purged(thought_count)
signal thought_added(thought_text)

var local_thoughts: Array = []

func capture_thought(text: String, gps_location: Vector2):
	if text.strip_edges() == "": return
	
	var thought = {
		"timestamp": Time.get_unix_time_from_system(),
		"location": gps_location,
		"text": text,
		"resonance": Phi2X_Math.get_nearest_phi_node(gps_location.x, gps_location.y)["resonance_strength"]
	}
	local_thoughts.append(thought)
	SpaceTime_Manager.consume_energy(5.0) # Écrire coûte de l'énergie (1/3)
	emit_signal("thought_added", text)

# Appelé par SpaceTime_Manager la nuit
func purge_to_spacememory() -> Array:
	var count = local_thoughts.size()
	var archived_thoughts = local_thoughts.duplicate()
	local_thoughts.clear()
	emit_signal("cache_purged", count)
	return archived_thoughts
