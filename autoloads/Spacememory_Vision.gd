extends Node

signal snapshot_taken(texture, lat, lon, azimut, pitch, fov)
signal memory_deleted(ts: int)  # notifie World_3D pour détruire le pivot 3D

var camera_feed: CameraFeed
var cam_texture: CameraTexture
var current_feed_idx: int = 0

# Web DeviceOrientationEvent — maintenu par le callback JS
var _web_orient_alpha: float = 0.0   # azimut (compas)
var _web_orient_beta:  float = 0.0   # pitch
var _web_orient_cb: JavaScriptObject = null

const MEMORIES_DIR  := "user://memories"
const MEMORIES_IDX  := "user://memories/index.json"

var _memories_cache: Array = []
var _cache_loaded: bool = false

func _ready():
	Input.set_use_accumulated_input(false)
	DirAccess.make_dir_recursive_absolute(MEMORIES_DIR)
	_memories_cache = _load_index()
	_cache_loaded = true
	# Activer le monitoring CameraServer — requis avant tout appel à feeds()
	# Sans ça : "CameraServer is not actively monitoring feeds" en erreur console
	if not OS.has_feature("web"):
		CameraServer.set_monitoring_feeds(true)
	# Ne pas appeler _setup_web_orientation() ici !
	# iOS Safari (et Chrome mobile) exigent que DeviceOrientationEvent.requestPermission()
	# soit déclenché depuis un geste utilisateur direct — sinon la permission est refusée.
	# Appeler request_web_permissions() depuis le bouton AR 👁 dans Main_UI.gd.

func request_web_permissions():
	# Appelé depuis Main_UI._on_ar_toggled(true) — contexte de geste utilisateur garanti
	if OS.get_name() == "Web" and _web_orient_cb == null:
		_setup_web_orientation()

# ── Caméra ─────────────────────────────────────────────────────

func get_feed_texture() -> CameraTexture:
	var feeds := CameraServer.feeds()
	if feeds.size() == 0:
		# Aucune caméra disponible — retourner null pour éviter le moiré rose
		# Le code appelant doit tester la nullité avant d'afficher
		push_warning("Spacememory_Vision: aucun CameraFeed disponible (utiliser getUserMedia sur Web)")
		return null
	if not cam_texture:
		cam_texture = CameraTexture.new()
	camera_feed = feeds[current_feed_idx % feeds.size()]
	cam_texture.camera_feed_id = camera_feed.get_id()
	camera_feed.set_active(true)
	print("📷 Caméra activée : ", camera_feed.get_name())
	return cam_texture

func switch_camera():
	var feeds := CameraServer.feeds()
	if feeds.size() > 1:
		if camera_feed: camera_feed.set_active(false)
		current_feed_idx = (current_feed_idx + 1) % feeds.size()
		camera_feed = feeds[current_feed_idx]
		cam_texture.camera_feed_id = camera_feed.get_id()
		camera_feed.set_active(true)

# ── Orientation réelle ──────────────────────────────────────────

func _get_orientation() -> Array:
	# Web : utilise les données DeviceOrientationEvent collectées par JS
	if OS.get_name() == "Web":
		return [_web_orient_alpha, _web_orient_beta]

	# Android/iOS : gyroscope natif Godot 4
	var grav := Input.get_gravity()
	var mag  := Input.get_magnetometer()
	if grav.length() < 0.5 or mag.length() < 0.5:
		return [0.0, 0.0]  # capteur indisponible — valeur neutre

	var g := grav.normalized()
	var m := mag.normalized()
	var east  := g.cross(m).normalized()
	var north := east.cross(g).normalized()

	var pitch   := rad_to_deg(asin(clamp(-g.y, -1.0, 1.0)))
	var azimut  := fmod(rad_to_deg(atan2(north.x, north.z)) + 360.0, 360.0)
	return [azimut, pitch]

func _setup_web_orientation():
	_web_orient_cb = JavaScriptBridge.create_callback(_on_web_orientation)
	JavaScriptBridge.get_interface("window")["_godotOrientCb"] = _web_orient_cb
	JavaScriptBridge.eval("""
		(function() {
			function handler(e) {
				if (window._godotOrientCb)
					window._godotOrientCb([e.alpha||0, e.beta||0, e.gamma||0]);
			}
			if (typeof DeviceOrientationEvent !== 'undefined'
					&& typeof DeviceOrientationEvent.requestPermission === 'function') {
				DeviceOrientationEvent.requestPermission().then(function(s) {
					if (s === 'granted') window.addEventListener('deviceorientationabsolute', handler, true);
				}).catch(function(){});
			} else {
				window.addEventListener('deviceorientationabsolute', handler, true);
			}
		})();
	""")

func _on_web_orientation(args: Array):
	if args.size() < 2: return
	_web_orient_alpha = float(args[0])  # azimut compas [0-360]
	_web_orient_beta  = float(args[1])  # pitch [-180, 180]

# ── Capture ────────────────────────────────────────────────────

func take_real_snapshot():
	var lat    := SpaceTime_Manager.current_gps.x
	var lon    := SpaceTime_Manager.current_gps.y
	var orient := _get_orientation()
	var azimut: float = orient[0]
	var pitch:  float = orient[1]
	var fov:    float = 70.0

	var final_texture: Texture2D
	var img: Image = null
	if cam_texture:
		var raw_img := cam_texture.get_image()
		# Sur Android, la CameraTexture met quelques frames avant de recevoir l'image réelle
		# raw_img peut être vide si le capteur n'a pas encore fourni de frame
		if raw_img and not raw_img.is_empty():
			img = raw_img
			final_texture = ImageTexture.create_from_image(img)
		else:
			push_error("Spacememory: image capteur vide — snapshot ignoré")
			return  # Ne pas sauvegarder l'icône Godot comme souvenir
	else:
		final_texture = preload("res://icon.svg")

	emit_signal("snapshot_taken", final_texture, lat, lon, azimut, pitch, fov)
	_persist_memory(img, lat, lon, azimut, pitch, fov)

	if camera_feed: camera_feed.set_active(false)

# ── Persistance ────────────────────────────────────────────────

const THUMB_SIZE: int = 256  # px — taille max de la miniature galerie

func _persist_memory(img: Image, lat: float, lon: float,
		azimut: float, pitch: float, fov: float):
	var ts     := int(Time.get_unix_time_from_system())
	var path   := MEMORIES_DIR + "/photo_%d.png" % ts
	var thumb  := ""

	if img:
		img.save_png(path)
		# Sauvegarder une miniature distincte — seule celle-ci est chargée dans la galerie
		var th := img.duplicate()
		var tw: int = THUMB_SIZE
		var th_h: int = int(float(th.get_height()) / float(th.get_width()) * float(tw)) if th.get_width() > 0 else THUMB_SIZE
		th.resize(tw, th_h, Image.INTERPOLATE_BILINEAR)
		thumb = MEMORIES_DIR + "/thumb_%d.png" % ts
		th.save_png(thumb)
	else:
		path = ""

	var meta := {
		"path": path, "thumb": thumb, "ts": ts,
		"lat": lat, "lon": lon,
		"azimut": azimut, "pitch": pitch, "fov": fov,
		"hex_id": Phi2X_Math.gps_to_hex_index(lat, lon)
	}
	_memories_cache.append(meta)
	_save_index(_memories_cache)

func save_web_snapshot(tex: Texture2D, lat: float, lon: float):
	# Persistance avant émission : le thumb_path doit exister sur disque pour le lazy loading 3D
	var img := tex.get_image()
	_persist_memory(img, lat, lon, 0.0, 0.0, 70.0)
	emit_signal("snapshot_taken", tex, lat, lon, 0.0, 0.0, 70.0)

func load_memories() -> Array:
	return _memories_cache

func delete_memory(ts: int):
	# Supprime le memory par timestamp (identifiant unique)
	var idx := -1
	for i in range(_memories_cache.size()):
		if _memories_cache[i].get("ts", -1) == ts:
			idx = i; break
	if idx < 0: return
	var mem: Dictionary = _memories_cache[idx]
	# Supprimer fichiers disque (photo + miniature)
	for key in ["path", "thumb"]:
		var p: String = mem.get(key, "")
		if p != "" and FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)
	_memories_cache.remove_at(idx)
	_save_index(_memories_cache)
	emit_signal("memory_deleted", ts)  # World_3D peut nettoyer le pivot 3D

func _load_index() -> Array:
	if not FileAccess.file_exists(MEMORIES_IDX): return []
	var f := FileAccess.open(MEMORIES_IDX, FileAccess.READ)
	if not f: return []
	var j := JSON.new()
	if j.parse(f.get_as_text()) == OK and j.data is Array:
		return j.data as Array
	return []

func _save_index(data: Array):
	var f := FileAccess.open(MEMORIES_IDX, FileAccess.WRITE)
	if f: f.store_string(JSON.stringify(data))

func fetch_memories_for_hex(_hex_index: Vector3) -> Array:
	var hex := Phi2X_Math.gps_to_hex_index(
		SpaceTime_Manager.current_gps.x,
		SpaceTime_Manager.current_gps.y)
	var result: Array = []
	for m in _memories_cache:
		if m.get("hex_id") == hex: result.append(m)
	return result
