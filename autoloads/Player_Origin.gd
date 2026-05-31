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

# Profil ATOM4LOVE — Données biométriques et spatio-temporelles (Module 1)
var birth_unix: int = 0           # Timestamp de naissance (Unix seconds)
var conception_unix: int = 0      # Timestamp de conception (0 = non défini)
var birth_lat: float = 0.0        # Latitude du lieu de naissance
var birth_lon: float = 0.0        # Longitude du lieu de naissance
# Polarité : 0 = Garçon (Onde Φ/Lumière/Expansion), 1 = Fille (Onde Octave/Son/Gravité)
var biological_sex: int = 0
var height_cm: float = 170.0      # Taille (cm) — calibrage cavité de résonance
var weight_kg: float = 70.0       # Poids (kg) — calibrage ω_bio

# Résultats calculés — mis à jour à chaque appel de _compute_atom4love_profile()
var personal_phase: float = 0.0   # φ_i — phase personnelle
var omega_bio: float = 0.0        # ω_bio — fréquence biologique

const SAVE_PATH = "user://multipass_identity.json"

const PENTAGONS_GPS = [
	Vector2(90, 0), Vector2(-90, 0),
	Vector2(26.56, 0), Vector2(26.56, 72), Vector2(26.56, 144), Vector2(26.56, -72), Vector2(26.56, -144),
	Vector2(-26.56, 36), Vector2(-26.56, 108), Vector2(-26.56, 180), Vector2(-26.56, -36), Vector2(-26.56, -108)
]

func _ready():
	load_multipass()

func init_from_multipass(data: Dictionary):
	user_email  = data.get("email", "")
	user_npub   = data.get("npub", "")
	user_nsec   = data.get("nsec", "")
	user_hex    = data.get("hex", "")
	user_g1pub  = data.get("g1pub", "")
	user_ipns   = data.get("nostrns", "")

	# Profil ATOM4LOVE (champs optionnels, présents si déjà sauvegardés)
	birth_unix       = data.get("birth_unix", 0)
	conception_unix  = data.get("conception_unix", 0)
	birth_lat        = data.get("birth_lat", 0.0)
	birth_lon        = data.get("birth_lon", 0.0)
	biological_sex   = data.get("biological_sex", 0)
	height_cm        = data.get("height_cm", 170.0)
	weight_kg        = data.get("weight_kg", 70.0)

	var hash_val = user_hex.hash()
	origin_pentagon_id = abs(hash_val) % 12
	base_frequency = 1.0 + (float(abs(hash_val % 1000)) / 1000.0) * Phi2X_Math.PHI

	_compute_atom4love_profile()

	is_initialized = true
	save_multipass()
	emit_signal("matrix_initialized", origin_pentagon_id, base_frequency)

func set_birth_profile(p_birth_unix: int, p_birth_lat: float, p_birth_lon: float,
		p_sex: int, p_height: float, p_weight: float, p_conception_unix: int = 0):
	birth_unix      = p_birth_unix
	conception_unix = p_conception_unix
	birth_lat       = p_birth_lat
	birth_lon       = p_birth_lon
	biological_sex  = p_sex
	height_cm       = p_height
	weight_kg       = p_weight
	_compute_atom4love_profile()
	save_multipass()

func _compute_atom4love_profile():
	if birth_unix > 0:
		personal_phase = Phi2X_Math.compute_personal_phase(birth_unix, birth_lat, birth_lon)
		omega_bio = Phi2X_Math.compute_omega_bio(height_cm, weight_kg, biological_sex)

func has_atom4love_profile() -> bool:
	return birth_unix > 0

func get_polarity_label() -> String:
	return "Onde Φ (Lumière)" if biological_sex == 0 else "Onde Octave (Son)"

func save_multipass():
	var save_data = {
		"email": user_email, "npub": user_npub, "nsec": user_nsec,
		"hex": user_hex, "g1pub": user_g1pub, "nostrns": user_ipns,
		"birth_unix": birth_unix, "conception_unix": conception_unix,
		"birth_lat": birth_lat, "birth_lon": birth_lon,
		"biological_sex": biological_sex, "height_cm": height_cm, "weight_kg": weight_kg
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
