extends Node

signal matrix_initialized(pentagon_id, frequency)

var origin_pentagon_id: int = -1
var base_frequency: float = 0.0
var is_initialized: bool = false

# Données du MULTIPASS (identité NOSTR/UPlanet)
var user_email: String = ""
var user_npub: String = ""
var user_nsec: String = ""
var user_g1pub: String = ""
var user_hex: String = ""
var user_ipns: String = ""
var user_salt: String = ""
var user_pepper: String = ""
# HEX NOSTR du NODE home station — parsé depuis le champ home_station du kind 0.
# Format : "IPFSNODEID:NODE_NOSTR_HEX" → on extrait la partie après ":"
# Utilisé par Nostr_Identity.send_udrive_dm() pour router les uploads en roaming.
var home_node_hex: String = ""

# Profil ATOM4LOVE — Données biométriques et spatio-temporelles (Module 1)
var birth_unix: int = 0           # Timestamp de naissance (Unix seconds)
var conception_unix: int = 0      # Timestamp de conception (0 = non défini)
var birth_lat: float = 0.0        # Latitude du lieu de naissance
var birth_lon: float = 0.0        # Longitude du lieu de naissance
var conception_lat: float = 0.0   # Latitude du lieu de conception (0 = identique à naissance)
var conception_lon: float = 0.0   # Longitude du lieu de conception
var parents_verified: bool = false # +10% IPV : données validées avec les géniteurs
# Polarité : 0 = Garçon (Onde Φ/Lumière/Expansion), 1 = Fille (Onde Octave/Son/Gravité)
var biological_sex: int = 0
var height_cm: float = 170.0      # Taille (cm) — calibrage cavité de résonance
var weight_kg: float = 70.0       # Poids (kg) — calibrage ω_bio
# Fuseau horaire UTC au moment de la naissance (ex: -4.0 pour Martinique, +2.0 pour Paris été)
# Permet de corriger birth_unix (heure locale saisie) en heure solaire vraie pour φ_i
var birth_utc_offset_h: float = 0.0
# Fuseau UTC au moment de la conception (mère potentiellement dans un autre pays)
# Utilise le même principe de correction heure locale → heure solaire pour le Pentagone d'Origine
var conception_utc_offset_h: float = 0.0
# true si l'utilisateur a explicitement saisi la date de conception (override du calcul auto)
var conception_datetime_user_set: bool = false
# true si l'utilisateur a explicitement saisi sa taille et son poids (même valeurs standard)
var morpho_user_set: bool = false

# Résultats calculés — mis à jour à chaque appel de _compute_atom4love_profile()
var personal_phase: float = 0.0   # φ_i — phase personnelle
var omega_bio: float = 0.0        # ω_bio — fréquence biologique

const SAVE_PATH = "user://multipass_identity.json"

func _ready():
	load_multipass()

func init_from_multipass(data: Dictionary):
	user_email  = data.get("email", "")
	user_npub   = data.get("npub", "")
	user_nsec   = data.get("nsec", "")
	user_hex    = data.get("hex", "")
	user_g1pub  = data.get("g1pub", "")
	user_ipns   = data.get("nostrns", "")
	user_salt       = data.get("salt", "")
	user_pepper     = data.get("pepper", "")
	home_node_hex   = data.get("home_node_hex", "")

	## NAISSANCE
	if data.has("birth_unix"): birth_unix = data["birth_unix"]
	if data.has("birth_utc_offset_h"): birth_utc_offset_h = data["birth_utc_offset_h"]
	if data.has("birth_lat"): birth_lat = data["birth_lat"]
	if data.has("birth_lon"): birth_lon = data["birth_lon"]
	if data.has("biological_sex"): biological_sex = data["biological_sex"]
	if data.has("weight_kg"): weight_kg = data["weight_kg"]
	if data.has("height_cm"): height_cm = data["height_cm"]

	## CONCEPTION
	if data.has("parents_verified"): parents_verified = data["parents_verified"]
	if data.has("conception_datetime_user_set"): conception_datetime_user_set = data["conception_datetime_user_set"]
	if data.has("morpho_user_set"): morpho_user_set = data["morpho_user_set"]
	if data.has("conception_unix"): conception_unix = data["conception_unix"]
	if data.has("conception_utc_offset_h"): conception_utc_offset_h = data["conception_utc_offset_h"]
	if data.has("conception_lat"): conception_lat = data["conception_lat"]
	if data.has("conception_lon"): conception_lon = data["conception_lon"]

	_compute_atom4love_profile()

	is_initialized = true
	save_multipass()
	emit_signal("matrix_initialized", origin_pentagon_id, base_frequency)

func set_birth_profile(p_birth_unix: int, p_birth_lat: float, p_birth_lon: float,
		p_sex: int, p_height: float, p_weight: float, p_conception_unix: int = 0,
		p_conception_lat: float = 0.0, p_conception_lon: float = 0.0,
		p_morpho_set: bool = false, p_utc_offset_h: float = 0.0):
	birth_unix         = p_birth_unix
	conception_unix    = p_conception_unix
	birth_lat          = p_birth_lat
	birth_lon          = p_birth_lon
	biological_sex     = p_sex
	height_cm          = p_height
	weight_kg          = p_weight
	conception_lat     = p_conception_lat
	conception_lon     = p_conception_lon
	morpho_user_set    = p_morpho_set
	birth_utc_offset_h = p_utc_offset_h
	_compute_atom4love_profile()
	save_multipass()

func _compute_atom4love_profile():
	if birth_unix > 0:
		# Phase cristallisée à la naissance (lieu du premier souffle)
		# birth_utc_offset_h corrige l'heure locale saisie → heure solaire vraie pour θ_daily
		personal_phase = Phi2X_Math.compute_personal_phase(birth_unix, birth_lat, birth_lon, birth_utc_offset_h)
		omega_bio = Phi2X_Math.compute_omega_bio(height_cm, weight_kg, biological_sex)
		if conception_unix == 0:
			conception_unix = Phi2X_Math.compute_conception_unix(birth_unix, weight_kg)
			# Persister immédiatement pour stabilité entre redémarrages
			if is_initialized: save_multipass()

	# Pentagon d'ancrage : lieu de CONCEPTION si renseigné, sinon lieu de naissance
	# (correction Étirement Spatio-Temporel — voyage mère entre T0 et premier souffle)
	var c_lat := conception_lat if (conception_lat != 0.0 or conception_lon != 0.0) else birth_lat
	var c_lon := conception_lon if (conception_lat != 0.0 or conception_lon != 0.0) else birth_lon

	if birth_unix > 0 and (c_lat != 0.0 or c_lon != 0.0):
		var origin_data = Phi2X_Math.get_nearest_pentagon(c_lat, c_lon, float(conception_unix))
		origin_pentagon_id = origin_data["idx"]
		base_frequency = 1.0 + (1.0 / (origin_data["distance_km"] + 1.0)) * Phi2X_Math.PHI
	elif user_hex != "":
		var hash_val = user_hex.hash()
		origin_pentagon_id = abs(hash_val) % 12
		base_frequency = 1.0 + (float(abs(hash_val % 1000)) / 1000.0) * Phi2X_Math.PHI

func reset():
	is_initialized = false
	user_email = ""; user_npub = ""; user_nsec = ""
	user_hex = ""; user_g1pub = ""; user_ipns = ""
	user_salt = ""; user_pepper = ""
	origin_pentagon_id = -1; base_frequency = 0.0
	birth_unix = 0; conception_unix = 0
	birth_lat = 0.0; birth_lon = 0.0
	conception_lat = 0.0; conception_lon = 0.0
	parents_verified = false
	biological_sex = 0; height_cm = 170.0; weight_kg = 70.0
	birth_utc_offset_h = 0.0; conception_utc_offset_h = 0.0
	conception_datetime_user_set = false; morpho_user_set = false
	personal_phase = 0.0; omega_bio = 0.0
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)

func has_atom4love_profile() -> bool:
	return birth_unix > 0

func calculate_vibrational_precision() -> int:
	if birth_unix <= 0: return 0
	var score := 40
	var dt := Time.get_datetime_dict_from_unix_time(birth_unix)
	# +15 si l'heure de naissance a été saisie (pas à midi par défaut)
	if dt.hour != 12 or dt.minute != 0:
		score += 15
	# +20 si le lieu de naissance est renseigné
	if abs(birth_lat) > 0.1 and abs(birth_lon) > 0.1:
		score += 20
	# +15 si l'utilisateur a EXPLICITEMENT saisi sa morphologie (même 70kg/170cm)
	# Correctif : on vérifie le flag, pas la valeur — un utilisateur de 70kg/170cm
	# ne doit pas être pénalisé pour avoir fourni ses données réelles.
	if morpho_user_set:
		score += 15
	if parents_verified:
		score += 10
	return clamp(score, 0, 100)

func get_polarity_label() -> String:
	return "Onde Φ (Lumière)" if biological_sex == 0 else "Onde Octave (Son)"

# URL complète du uDRIVE sur la home station IPFS.
# Format : https://ipfs.domain.tld/ipns/KEY/email/APP/uDRIVE
# user_ipns est de la forme "/ipns/k51qzi5uqu5dg..." ou "/ipns/Qm..."
func get_udrive_url(ipfs_gateway: String = "https://ipfs.copylaradio.com") -> String:
	if user_ipns.is_empty() or user_email.is_empty():
		return ""
	var key := user_ipns.strip_edges()
	if not key.begins_with("/"):
		key = "/" + key
	return ipfs_gateway.rstrip("/") + key + "/" + user_email + "/APP/uDRIVE"

func save_multipass():
	var save_data = {
		"email": user_email, "npub": user_npub, "nsec": user_nsec,
		"hex": user_hex, "g1pub": user_g1pub, "nostrns": user_ipns,
		"salt": user_salt, "pepper": user_pepper,
		"home_node_hex": home_node_hex,
		"birth_unix": birth_unix, "conception_unix": conception_unix,
		"birth_lat": birth_lat, "birth_lon": birth_lon,
		"conception_lat": conception_lat, "conception_lon": conception_lon,
		"parents_verified": parents_verified,
		"biological_sex": biological_sex, "height_cm": height_cm, "weight_kg": weight_kg,
		"birth_utc_offset_h": birth_utc_offset_h,
		"conception_utc_offset_h": conception_utc_offset_h,
		"conception_datetime_user_set": conception_datetime_user_set,
		"morpho_user_set": morpho_user_set
	}
	var file = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if not file:
		push_error("Player_Origin: impossible d'écrire %s (erreur %d)" % [SAVE_PATH, FileAccess.get_open_error()])
		return
	file.store_string(JSON.stringify(save_data))

func load_multipass():
	if FileAccess.file_exists(SAVE_PATH):
		var file = FileAccess.open(SAVE_PATH, FileAccess.READ)
		if not file:
			push_error("Player_Origin: impossible de lire %s (erreur %d)" % [SAVE_PATH, FileAccess.get_open_error()])
			return
		var data = JSON.parse_string(file.get_as_text())
		if data != null:
			init_from_multipass(data)
			print("✅ MULTIPASS chargé depuis la mémoire du téléphone.")
