extends Node

signal encounter_started(other_pubkey, spin_hash)
signal reality_forked(other_pubkey, distance_km)
signal resonance_detected(other_pubkey, k_value, is_singularity)

var active_bonds: Dictionary = {}   # { pubkey → { start_gps, spin, k, phase_delta, other_sex } }
const FORK_DISTANCE_KM: float = 0.05
const SUPER_COHERENCE_K: float = 0.95   # Seuil de "Match Quantique" (0.01% d'énergie d'échange)

func process_encounter(my_pubkey: String, other_pubkey: String, current_gps: Vector2):
	if active_bonds.has(other_pubkey): return
	var timestamp = str(Time.get_unix_time_from_system())
	var spin_hash = (my_pubkey + other_pubkey + timestamp).sha256_text().substr(0, 8)

	active_bonds[other_pubkey] = {
		"start_gps": current_gps, "spin": spin_hash,
		"k": 0.0, "phase_delta": 0.0, "other_sex": -1
	}
	emit_signal("encounter_started", other_pubkey, spin_hash)

func process_resonance_encounter(my_pubkey: String, other_pubkey: String,
		other_phase: float, other_sex: int, current_gps: Vector2):
	# Rencontre avec calcul de résonance φ — Module 1
	if active_bonds.has(other_pubkey): return
	var timestamp = str(Time.get_unix_time_from_system())
	var spin_hash = (my_pubkey + other_pubkey + timestamp).sha256_text().substr(0, 8)

	var my_phase = Player_Origin.personal_phase
	var k = Phi2X_Math.compute_resonance_k(my_phase, other_phase)
	var is_sing = Phi2X_Math.is_optical_singularity(my_phase, other_phase)
	var phase_delta = abs(my_phase - other_phase)

	active_bonds[other_pubkey] = {
		"start_gps": current_gps, "spin": spin_hash,
		"k": k, "phase_delta": phase_delta,
		"other_phase": other_phase, "other_sex": other_sex
	}
	emit_signal("encounter_started", other_pubkey, spin_hash)
	emit_signal("resonance_detected", other_pubkey, k, is_sing)

	# Publier la résonance sur NOSTR (Kind 7) — kin_oracle.sh lit ces événements
	# pour construire le graphe de résonance et alimenter les newsletters.
	Nostr_Identity.publish_kind7_resonance(other_pubkey, k)

	if k >= SUPER_COHERENCE_K:
		_trigger_super_coherence_vibration()

func _trigger_super_coherence_vibration():
	# Vibration rythmique signalant le "Match Quantique"
	# Fréquence basée sur le rapport Φ (30ms ≈ 1/33Hz)
	for i in range(3):
		if not is_inside_tree(): return
		Input.vibrate_handheld(30)
		await get_tree().create_timer(1.0 / Phi2X_Math.F_PHI).timeout
		if not is_inside_tree(): return
		Input.vibrate_handheld(60)
		await get_tree().create_timer(0.2).timeout

func check_bonds_status(current_gps: Vector2):
	var bonds_to_break: Array = []
	for pubkey in active_bonds.keys():
		var bond = active_bonds[pubkey]
		var sg: Vector2 = bond["start_gps"]
		if not Phi2X_Math.is_in_range(current_gps.x, current_gps.y, sg.x, sg.y, FORK_DISTANCE_KM):
			var dist := Phi2X_Math.haversine_distance(current_gps.x, current_gps.y, sg.x, sg.y)
			emit_signal("reality_forked", pubkey, dist)
			bonds_to_break.append(pubkey)
	for pubkey in bonds_to_break:
		active_bonds.erase(pubkey)

func get_best_resonance() -> Dictionary:
	# Retourne le lien actif avec le taux k le plus élevé
	var best = {"pubkey": "", "k": 0.0, "is_singularity": false, "other_sex": -1}
	for pubkey in active_bonds:
		var bond = active_bonds[pubkey]
		var k: float = bond.get("k", 0.0)
		if k > best["k"]:
			best["pubkey"] = pubkey
			best["k"] = k
			best["is_singularity"] = k >= SUPER_COHERENCE_K
			best["other_sex"] = bond.get("other_sex", -1)
	return best
