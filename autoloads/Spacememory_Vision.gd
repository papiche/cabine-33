extends Node

signal snapshot_taken(texture, lat, lon, azimut, pitch, fov)

var camera_feed: CameraFeed
var cam_texture: CameraTexture
var current_feed_idx: int = 0

func _ready():
	Input.set_use_accumulated_input(false)

# Démarre le flux vidéo et retourne la texture (pour l'afficher sur l'UI)
func get_feed_texture() -> CameraTexture:
	if not cam_texture:
		cam_texture = CameraTexture.new()
		
	var feeds = CameraServer.feeds()
	if feeds.size() > 0:
		camera_feed = feeds[current_feed_idx]
		cam_texture.camera_feed_id = camera_feed.get_id()
		camera_feed.set_active(true)
		print("📷 Caméra activée : ", camera_feed.get_name())
	return cam_texture

# Bascule entre la caméra frontale et arrière
func switch_camera():
	var feeds = CameraServer.feeds()
	if feeds.size() > 1:
		if camera_feed:
			camera_feed.set_active(false)
		current_feed_idx = (current_feed_idx + 1) % feeds.size()
		camera_feed = feeds[current_feed_idx]
		cam_texture.camera_feed_id = camera_feed.get_id()
		camera_feed.set_active(true)

# Capture le moment et fige l'image
func take_real_snapshot():
	SpaceTime_Manager.consume_energy(10.0)
	var lat = SpaceTime_Manager.current_gps.x
	var lon = SpaceTime_Manager.current_gps.y
	
	# Simulation des capteurs magnétiques et gyroscopiques du téléphone
	# (En production, Input.get_magnetometer() sera utilisé)
	var azimut = randf_range(0.0, 360.0)
	var pitch = randf_range(-15.0, 15.0)
	var fov = 70.0 # Paramètre optique standard d'un smartphone
	
	var final_texture = null
	
	# Fige l'image de la caméra dans une ImageTexture (Indépendante du flux vidéo)
	if cam_texture and cam_texture.get_image():
		var img = cam_texture.get_image()
		final_texture = ImageTexture.create_from_image(img)
	else:
		final_texture = preload("res://icon.svg")
		
	emit_signal("snapshot_taken", final_texture, lat, lon, azimut, pitch, fov)
	
	# Coupe la caméra pour économiser la batterie
	if camera_feed:
		camera_feed.set_active(false)

func fetch_memories_for_hex(_hex_index: Vector3) -> Array:
	return [] # Vidé pour l'instant, on se concentre sur vos propres photos
