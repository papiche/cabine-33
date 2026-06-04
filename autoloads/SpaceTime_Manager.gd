extends Node

signal cycle_changed(new_state)
signal gps_updated(lat, lon)

enum TimeState { STATE_DAY_ACTION, STATE_NIGHT_DREAM }
var current_state: TimeState = TimeState.STATE_DAY_ACTION
var current_gps: Vector2 = Vector2(48.8566, 2.3522)
var _suspend_unix: int = 0  # Horodatage de mise en veille

func _ready():
	var timer = Timer.new()
	timer.wait_time = 60.0
	timer.autostart = true
	timer.connect("timeout", Callable(self, "_check_time_cycle"))
	add_child(timer)
	# call_deferred garantit que Main_UI est dans l'arbre avant _trigger_night_sync
	call_deferred("_check_time_cycle")

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

func update_gps_location(lat: float, lon: float):
	current_gps = Vector2(lat, lon)
	emit_signal("gps_updated", lat, lon)

func _notification(what: int):
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_suspend_unix = int(Time.get_unix_time_from_system())
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		if _suspend_unix > 0:
			var elapsed := int(Time.get_unix_time_from_system()) - _suspend_unix
			# >10 min de veille : sync (jamais purge directe)
			if elapsed > 600:
				_trigger_night_sync()
		_suspend_unix = 0
		_check_time_cycle()

func _trigger_night_sync():
	print("🌙 SYNCHRONISATION DU VIDE QUANTIQUE...")
	# Ne pas purger ici : déléguer à Main_UI._on_sync_pressed() qui vérifie
	# la connectivité NOSTR avant toute suppression des données locales
	var main_ui := get_tree().root.find_child("Main_UI", true, false)
	if is_instance_valid(main_ui) and main_ui.has_method("_on_sync_pressed"):
		main_ui._on_sync_pressed()
	else:
		push_error("SpaceTime_Manager: Main_UI introuvable — pensées conservées en local")
