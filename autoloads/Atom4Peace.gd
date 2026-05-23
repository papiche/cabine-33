extends Node

signal encounter_started(other_pubkey, spin_hash)
signal reality_forked(other_pubkey, distance_km)

var active_bonds: Dictionary = {}
const FORK_DISTANCE_KM: float = 0.05

func process_encounter(my_pubkey: String, other_pubkey: String, current_gps: Vector2):
	if active_bonds.has(other_pubkey): return
	var timestamp = str(Time.get_unix_time_from_system())
	var raw_spin = my_pubkey + other_pubkey + timestamp
	var spin_hash = raw_spin.sha256_text().substr(0, 8)
	
	active_bonds[other_pubkey] = { "start_gps": current_gps, "spin": spin_hash }
	SpaceTime_Manager.consume_energy(1.0)
	emit_signal("encounter_started", other_pubkey, spin_hash)

func check_bonds_status(current_gps: Vector2):
	var bonds_to_break = []
	for pubkey in active_bonds.keys():
		var bond = active_bonds[pubkey]
		var dist = Phi2X_Math.haversine_distance(current_gps.x, current_gps.y, bond["start_gps"].x, bond["start_gps"].y)
		if dist > FORK_DISTANCE_KM:
			emit_signal("reality_forked", pubkey, dist)
			bonds_to_break.append(pubkey)
	for pubkey in bonds_to_break: active_bonds.erase(pubkey)
