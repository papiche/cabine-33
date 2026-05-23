extends Node

signal matrix_initialized(pentagon_id, frequency)

var origin_pentagon_id: int = -1
var base_frequency: float = 0.0
var is_initialized: bool = false

# Données du MULTIPASS
var user_email: String = ""
var user_npub: String = ""
var user_nsec: String = ""
var user_g1pub: String = ""
var user_hex: String = ""
var user_ipns: String = ""

const SAVE_PATH = "user://multipass_identity.json"

const PENTAGONS_GPS = [
	Vector2(90, 0), Vector2(-90, 0),
	Vector2(26.56, 0), Vector2(26.56, 72), Vector2(26.56, 144), Vector2(26.56, -72), Vector2(26.56, -144),
	Vector2(-26.56, 36), Vector2(-26.56, 108), Vector2(-26.56, 180), Vector2(-26.56, -36), Vector2(-26.56, -108)
]

func _ready():
	load_multipass()

# Initialisation depuis les données de l'API UPlanet
func init_from_multipass(data: Dictionary):
	user_email = data.get("email", "")
	user_npub = data.get("npub", "")
	user_nsec = data.get("nsec", "")
	user_hex = data.get("hex", "")
	user_g1pub = data.get("g1pub", "")
	user_ipns = data.get("nostrns", "")
	
	# Hachage basé sur la vraie clé cryptographique NOSTR (Hex) plutôt que la date
	var hash_val = user_hex.hash()
	origin_pentagon_id = abs(hash_val) % 12
	base_frequency = 1.0 + (float(abs(hash_val % 1000)) / 1000.0) * Phi2X_Math.PHI
	
	is_initialized = true
	save_multipass()
	emit_signal("matrix_initialized", origin_pentagon_id, base_frequency)

func save_multipass():
	var save_data = {
		"email": user_email, "npub": user_npub, "nsec": user_nsec, 
		"hex": user_hex, "g1pub": user_g1pub, "nostrns": user_ipns
	}
	var file = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(save_data))

func load_multipass():
	if FileAccess.file_exists(SAVE_PATH):
		var file = FileAccess.open(SAVE_PATH, FileAccess.READ)
		var json = JSON.new()
		if json.parse(file.get_as_text()) == OK:
			init_from_multipass(json.data)
			print("✅ MULTIPASS chargé depuis la mémoire du téléphone.")
