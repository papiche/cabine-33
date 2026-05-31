extends Node3D

@onready var world_root = $WorldRoot
@onready var player_avatar = $PlayerAvatar
@onready var camera = $Camera3D
@onready var ground_mesh = $InfiniteGround # Nouveau

# float = 64 bits en GDScript 4 (Vector2 = 32 bits → jitter sur petits deltas GPS)
var last_gps_lat: float = 0.0
var last_gps_lon: float = 0.0
var target_world_pos: Vector3 = Vector3.ZERO
var default_cam_pos: Vector3

func _ready():
	default_cam_pos = camera.position
	SpaceTime_Manager.connect("gps_updated", Callable(self, "_on_gps_updated"))
	Player_Origin.connect("matrix_initialized", Callable(self, "_on_matrix_init"))
	Spacememory_Vision.connect("snapshot_taken", Callable(self, "_on_snapshot_taken"))
	
	var ui = get_node_or_null("../CanvasLayer/Main_UI")
	if ui: ui.connect("recenter_requested", Callable(self, "_on_recenter"))
	
	last_gps_lat = SpaceTime_Manager.current_gps.x
	last_gps_lon = SpaceTime_Manager.current_gps.y
	
	# Initialisation du shader
	_update_shader_offset()

func _process(delta):
	# Le monde (les objets déposés) bouge fluidement
	world_root.position = world_root.position.lerp(target_world_pos, delta * 4.0)
	
	# TRUC CRUCIAL : Le sol infini suit la caméra en X et Z
	# Mais la grille reste fixe grâce au world_offset injecté dans le shader
	ground_mesh.position.x = camera.position.x
	ground_mesh.position.z = camera.position.z
	
	_update_shader_offset()
	
	# Pulsation fréquence du joueur
	if Player_Origin.origin_pentagon_id != -1:
		var scale_pulse = 1.0 + (sin(Time.get_ticks_msec() / 1000.0 * Player_Origin.base_frequency) * 0.1)
		player_avatar.scale = Vector3(scale_pulse, scale_pulse, scale_pulse)

func _update_shader_offset():
	# On vérifie si ground_mesh n'est pas "null" avant d'appeler ses fonctions
	if is_instance_valid(ground_mesh):
		var mat = ground_mesh.get_active_material(0)
		if mat:
			mat.set_shader_parameter("world_offset", world_root.position)
			mat.set_shader_parameter("pulse_speed", Player_Origin.base_frequency)
	else:
		print("⚠️ Attention: InfiniteGround est introuvable dans la scène !")

func _on_gps_updated(lat, lon):
	# lat et lon arrivent en float 64-bit depuis le signal
	# On travaille directement en float pour préserver la précision sub-métrique
	var delta_lat: float = (lat - last_gps_lat) * 111320.0
	var delta_lon: float = (lon - last_gps_lon) * 111320.0 * cos(deg_to_rad(last_gps_lat))
	target_world_pos.x -= delta_lon
	target_world_pos.z += delta_lat
	last_gps_lat = lat
	last_gps_lon = lon

func _on_recenter():
	var tween = create_tween()
	tween.tween_property(camera, "position", default_cam_pos, 0.5).set_trans(Tween.TRANS_SINE)

func _on_matrix_init(pent_id, _freq):
	var mat = StandardMaterial3D.new()
	var col = Color.from_hsv((pent_id / 12.0), 0.8, 1.0)
	mat.albedo_color = col
	mat.emission_enabled = true
	mat.emission = col
	mat.emission_energy_multiplier = 8.0 # Augmenté de 3 à 8 pour l'effet néon
	player_avatar.material_override = mat
	
	# On change aussi la couleur de la grille pour matcher l'origine du joueur
	var ground_mat = ground_mesh.get_active_material(0)
	if ground_mat:
		ground_mat.set_shader_parameter("grid_color", col)

# (Gardez la fonction _on_snapshot_taken identique à la précédente)
func _on_snapshot_taken(tex, _lat, _lon, azimut, pitch, fov):
	var pivot = Node3D.new()
	pivot.position = Vector3(0, 1.5, 0)
	pivot.rotation_degrees = Vector3(pitch, azimut, 0)
	var sprite = Sprite3D.new()
	sprite.texture = tex
	sprite.pixel_size = 0.015 * (70.0 / fov) 
	sprite.double_sided = true
	world_root.add_child(pivot)
	pivot.add_child(sprite)
	sprite.position = Vector3(0, 0, -4.0)
