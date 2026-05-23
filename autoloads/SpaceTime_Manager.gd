extends Node

signal cycle_changed(new_state)
signal energy_updated(new_energy)
signal gps_updated(lat, lon)

enum TimeState { STATE_DAY_ACTION, STATE_NIGHT_DREAM }
var current_state: TimeState = TimeState.STATE_DAY_ACTION
var current_gps: Vector2 = Vector2(48.8566, 2.3522)

const MAX_TOTAL_ENERGY: float = 100.0
var available_matter_energy: float = MAX_TOTAL_ENERGY / 3.0

func _ready():
	var timer = Timer.new()
	timer.wait_time = 10.0 # Accéléré pour le test (normalement 60.0)
	timer.autostart = true
	timer.connect("timeout", Callable(self, "_check_time_cycle"))
	add_child(timer)
	_check_time_cycle()

func _check_time_cycle():
	var time = Time.get_time_dict_from_system()
	var hour = time["hour"]
	var old_state = current_state
	
	if hour >= 6 and hour < 20: current_state = TimeState.STATE_DAY_ACTION
	else: current_state = TimeState.STATE_NIGHT_DREAM
		
	if old_state != current_state:
		emit_signal("cycle_changed", current_state)
		if current_state == TimeState.STATE_NIGHT_DREAM:
			_trigger_night_sync()

func consume_energy(amount: float):
	if current_state == TimeState.STATE_NIGHT_DREAM: return
	available_matter_energy = max(available_matter_energy - amount, 0.0)
	emit_signal("energy_updated", available_matter_energy)
	Thought_Cache.purge_to_spacememory()

func update_gps_location(lat: float, lon: float):
	current_gps = Vector2(lat, lon)
	emit_signal("gps_updated", lat, lon)

func _trigger_night_sync():
	print("SYNCHRONISATION DU VIDE QUANTIQUE...")
	available_matter_energy = MAX_TOTAL_ENERGY / 3.0
	emit_signal("energy_updated", available_matter_energy)
	Thought_Cache.purge_to_spacememory()
