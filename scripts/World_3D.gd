extends Node3D

@onready var world_root:    Node3D         = $WorldRoot
@onready var player_avatar: MeshInstance3D = $PlayerAvatar
@onready var camera:        Camera3D       = $Camera3D
@onready var ground_mesh:   MeshInstance3D = $InfiniteGround
@onready var world_env:     WorldEnvironment = $WorldEnvironment

const FLOATING_ORIGIN_THRESHOLD: float = 5000.0

var last_gps_lat:    float  = 0.0
var last_gps_lon:    float  = 0.0
var target_world_pos: Vector3 = Vector3.ZERO
var default_cam_transform: Transform3D
var _shader_world_offset: Vector3 = Vector3.ZERO

# ── Mode AR ────────────────────────────────────────────────────
var is_ar_mode: bool = false
var _ar_target_basis: Basis = Basis.IDENTITY

const AR_CAM_POS  := Vector3(0.0, 1.6, 0.0)  # hauteur yeux
const AR_GYRO_LERP := 12.0                    # douceur du suivi gyroscope

# ── Souvenirs photo — pulse radar ──────────────────────────────
var _memory_pivots: Array[Node3D] = []
const MEM_PULSE_RADIUS: float = 150.0  # ~150m : zone de pulsation
var _memory_pulse_acc: float = 0.0     # accumulateur pour throttle à 10 Hz

# ── Spacememory sociale — bulles de pensées ──────────────────────
var _thought_bubbles: Array[Node3D] = []
const THOUGHT_BUBBLE_COUNT: int = 33   # max bulles simultanées
const THOUGHT_FONT_SIZE: int = 32

func _ready():
	default_cam_transform = camera.transform
	SpaceTime_Manager.connect("gps_updated",      Callable(self, "_on_gps_updated"))
	Player_Origin.connect("matrix_initialized",   Callable(self, "_on_matrix_init"))
	Spacememory_Vision.connect("snapshot_taken",  Callable(self, "_on_snapshot_taken"))
	Spacememory_Vision.connect("memory_deleted",  Callable(self, "_on_memory_deleted"))

	var ui := get_node_or_null("../CanvasLayer/Main_UI")
	if ui:
		ui.connect("recenter_requested", Callable(self, "_on_recenter"))
		if ui.has_signal("ritual_progress"):
			ui.connect("ritual_progress", Callable(self, "_on_ritual_progress"))
		if ui.has_signal("ar_toggled"):
			ui.connect("ar_toggled", Callable(self, "toggle_ar_mode"))
		if ui.has_signal("spacememory_received"):
			ui.connect("spacememory_received", Callable(self, "_on_spacememory_events"))

	last_gps_lat = SpaceTime_Manager.current_gps.x
	last_gps_lon = SpaceTime_Manager.current_gps.y
	_update_shader_offset()
	_update_planck_field()

	# Charger les souvenirs photo persistés
	call_deferred("_load_saved_memories")

func _process(delta):
	world_root.position = world_root.position.lerp(target_world_pos, delta * 4.0)

	if world_root.position.length() > FLOATING_ORIGIN_THRESHOLD:
		_apply_floating_origin()

	ground_mesh.position.x = camera.position.x
	ground_mesh.position.z = camera.position.z
	_update_shader_offset()

	if Player_Origin.origin_pentagon_id != -1:
		var pulse := 1.0 + sin(Time.get_ticks_msec() / 1000.0 * Player_Origin.base_frequency) * 0.1
		player_avatar.scale = Vector3(pulse, pulse, pulse)

	# Gyroscope FPS en mode AR
	if is_ar_mode:
		_update_ar_gyro(delta)
		_update_ar_horizon()

	# Memory pulse throttlé à 10 Hz (100ms) pour éviter le bottleneck CPU
	# si l'index Spacememory contient des centaines de photos
	# Bobbing animé à 60Hz (mouvement fluide en AR)
	_update_memory_bobbing()
	# Culling / alpha / scale calculés à 10Hz seulement (coûteux sur 500 photos)
	_memory_pulse_acc += delta
	if _memory_pulse_acc >= 0.1:
		_memory_pulse_acc = fmod(_memory_pulse_acc, 0.1) # Conserve le delta résiduel
		_update_memory_culling()

# ── Bobbing 60Hz — mouvement vertical fluide (pas de culling ici) ──────────
func _update_memory_bobbing():
	var t := Time.get_ticks_msec() / 1000.0
	for pivot in _memory_pivots:
		if not is_instance_valid(pivot): continue
		var base_y: float = pivot.get_meta("base_y", 1.8)
		var phase:  float = pivot.get_meta("phase",  0.0)
		pivot.position.y = base_y + sin(t * 0.7 + phase) * 0.18
		# Scale pulsé à 60Hz pour éviter les saccades (le culling 10Hz ne s'en occupe plus)
		var sprite := pivot.get_child(0) as Node3D
		if is_instance_valid(sprite) and sprite.visible:
			var dist := (world_root.position + pivot.position - camera.position).length()
			var prox := maxf(0.0, 1.0 - (dist / MEM_PULSE_RADIUS))
			var ts := 1.0 + sin(t * 2.2 + phase) * 0.12 * prox
			sprite.scale = Vector3(ts, ts, ts)

# ── Culling / alpha / scale 10Hz — coûteux, pas besoin à 60fps ─────────────
func _update_memory_culling():
	var t := Time.get_ticks_msec() / 1000.0
	for pivot in _memory_pivots:
		if not is_instance_valid(pivot): continue
		var dist := (world_root.position + pivot.position - camera.position).length()
		var sprite := pivot.get_child(0) as Node3D
		if not is_instance_valid(sprite): continue
		var phase: float     = pivot.get_meta("phase",     0.0)
		var is_loaded: bool  = pivot.get_meta("is_loaded", false)
		if dist < MEM_PULSE_RADIUS:
			sprite.visible = true
			var prox := 1.0 - (dist / MEM_PULSE_RADIUS)
			var alpha := lerpf(0.35, 0.92, prox * prox)
			if sprite is Sprite3D: (sprite as Sprite3D).modulate.a = alpha
			# Lazy Load asynchrone : chargement image dans worker thread, création texture sur main thread
			if not is_loaded:
				var path: String = pivot.get_meta("thumb_path", "")
				pivot.set_meta("is_loaded", true)  # pré-marquer pour éviter double déclenchement
				if path != "" and FileAccess.file_exists(path):
					var pivot_ref := pivot
					var sprite_ref := sprite
					WorkerThreadPool.add_task(func():
						var img := Image.new()
						if img.load(path) == OK:
							# is_loaded reste true même si le sprite est devenu invisible entre-temps
							call_deferred("_apply_memory_texture", sprite_ref, img)
						# Si load échoue, remettre is_loaded=false pour permettre une nouvelle tentative
						else:
							(func(): if is_instance_valid(pivot_ref): pivot_ref.set_meta("is_loaded", false)).call_deferred()
					)
		else:
			sprite.visible = false  # retire le draw call GPU — alpha=0 dessinait quand même
			# Lazy Unload : libérer la VRAM quand on s'éloigne
			if is_loaded:
				if sprite is Sprite3D:
					(sprite as Sprite3D).texture = preload("res://icon.svg")
				pivot.set_meta("is_loaded", false)

func _apply_memory_texture(sprite: Node3D, img: Image):
	if is_instance_valid(sprite) and sprite is Sprite3D and sprite.visible:
		(sprite as Sprite3D).texture = ImageTexture.create_from_image(img)

# ── Mode AR ────────────────────────────────────────────────────

func toggle_ar_mode(active: bool):
	is_ar_mode = active
	var env := world_env.environment

	if active:
		# Activer le flux caméra comme fond 3D (Android natif uniquement)
		var feed_tex := Spacememory_Vision.get_feed_texture()
		if feed_tex != null and Spacememory_Vision.camera_feed != null:
			env.background_mode = Environment.BG_CAMERA_FEED
			env.camera_feed_id  = Spacememory_Vision.camera_feed.get_id()
		else:
			# Pas de caméra — fondu vers fond noir (Vision Quantique mode)
			env.background_mode  = Environment.BG_COLOR
			env.background_color = Color(0.0056, 0.0056, 0.0056, 1.0)
			var tw_bg := create_tween()
			tw_bg.tween_method(func(c: Color): env.background_color = c,
				Color(0.0056, 0.0056, 0.0056, 1.0), Color(0.0, 0.0, 0.02, 1.0), 0.6)

		# Caméra FPS à hauteur des yeux
		var tw := create_tween().set_trans(Tween.TRANS_SINE)
		tw.tween_property(camera, "position", AR_CAM_POS, 0.4)
		tw.parallel().tween_property(camera, "rotation_degrees", Vector3.ZERO, 0.4)
		_ar_target_basis = Basis.IDENTITY
		# Sol hexagonal horizontal — le shader blend_add le superpose au flux caméra (ou au fond noir si pas de caméra)
		# Si pas de caméra : fond noir + grille fil de fer pleine intensité (mode "vision quantique" sans caméra)
		var has_camera: bool = (Spacememory_Vision.camera_feed != null)
		var mat_ar: Material = ground_mesh.get_active_material(0)
		if mat_ar:
			mat_ar.set_shader_parameter("planck_intensity", 0.55 if has_camera else 0.80)
			mat_ar.set_shader_parameter("fade_far", 90.0 if has_camera else 150.0)
		for piv in _memory_pivots:
			if is_instance_valid(piv):
				piv.set_meta("base_y", 1.6)
	else:
		if Spacememory_Vision.camera_feed:
			Spacememory_Vision.camera_feed.set_active(false)
		env.background_mode  = Environment.BG_COLOR
		env.background_color = Color(0.0056, 0.0056, 0.0056, 1.0)
		var tw := create_tween().set_trans(Tween.TRANS_SINE)
		tw.tween_property(camera, "transform", default_cam_transform, 0.4)
		var mat_iso: Material = ground_mesh.get_active_material(0)
		if mat_iso: mat_iso.set_shader_parameter("planck_intensity", 0.40)
		for piv in _memory_pivots:
			if is_instance_valid(piv):
				piv.set_meta("base_y", 1.8)

func _update_ar_gyro(delta: float):
	# Orientation physique du smartphone → rotation caméra 3D
	# Godot Input.get_gravity() sur Android portrait :
	#   gravité au repos ≈ (0, -9.8, 0)  → téléphone à plat face en haut
	#   gravité debout   ≈ (0,  0, -9.8) → écran face à l'utilisateur
	# On calcule le pitch (inclinaison haut/bas) et l'azimut (compas) directement
	# depuis les capteurs inertiels sans passer par _get_orientation (qui peut dériver).

	var grav := Input.get_gravity()
	var mag  := Input.get_magnetometer()

	if grav.length() > 0.5 and mag.length() > 0.5:
		# Vecteurs normalisés
		var g := grav.normalized()
		var m := mag.normalized()
		# Repère local : Est = g × m, Nord = Est × g
		var east  := g.cross(m)
		if east.length() < 0.001:
			east = Vector3(0, 1, 0) if abs(g.x) > 0.9 else Vector3(1, 0, 0)
		east = east.normalized()
		var north := east.cross(g).normalized()
		# Azimut : angle du Nord projeté sur le plan horizontal
		var azimut := fmod(rad_to_deg(atan2(north.x, north.z)) + 360.0, 360.0)
		# Pitch : inclinaison de l'écran par rapport au sol
		# Portrait debout = pitch 0°, couché plat = pitch 90°, orienté vers le haut = -90°
		var pitch := rad_to_deg(asin(clamp(-g.z, -1.0, 1.0)))
		# Correction pour caméra arrière en portrait : l'écran regarde l'utilisateur,
		# la caméra regarde dans le sens opposé (−Z de la caméra = avant du monde)
		var target_basis := Basis.from_euler(Vector3(
			deg_to_rad(-pitch),     # tilt haut/bas (négatif car axe Y Godot inversé)
			deg_to_rad(-azimut),    # rotation boussole
			0.0                     # pas de roll
		))
		_ar_target_basis = _ar_target_basis.slerp(target_basis, delta * AR_GYRO_LERP)
		camera.basis = _ar_target_basis

	elif OS.has_feature("web"):
		# Web : DeviceOrientationEvent (alpha = compas, beta = pitch avant/arrière)
		var orient := Spacememory_Vision._get_orientation()
		if orient[0] == 0.0 and orient[1] == 0.0: return
		var target_basis := Basis.from_euler(Vector3(
			deg_to_rad(-orient[1]),  # beta (pitch)
			deg_to_rad(-orient[0]),  # alpha (azimut/compas)
			0.0
		))
		_ar_target_basis = _ar_target_basis.slerp(target_basis, delta * AR_GYRO_LERP)
		camera.basis = _ar_target_basis

func _update_ar_horizon():
	# Adapte le rayon visible de la grille hexagonale selon l'inclinaison caméra :
	# Regarder vers le sol (pitch ≈ -90°) → grille dense et proche
	# Regarder à l'horizon (pitch ≈ 0°)   → grille qui s'étend très loin
	# Regarder vers le ciel (pitch > 0°)  → grille presque invisible
	var pitch_deg: float = camera.rotation_degrees.x  # -90 = vers le sol, 0 = horizon, +90 = ciel
	# Mapping : pitch -90° → fade_far 20m  |  pitch 0° → 120m  |  pitch +30° → 8m (disparaît)
	var t: float = clampf((-pitch_deg + 90.0) / 90.0, 0.0, 1.0)
	var dynamic_fade_far: float = lerpf(8.0, 140.0, t * t)
	var mat: Material = ground_mesh.get_active_material(0)
	if mat: mat.set_shader_parameter("fade_far", dynamic_fade_far)

# ── Souvenirs persistés ────────────────────────────────────────

func _load_saved_memories():
	var memories := Spacememory_Vision.load_memories()
	for mem in memories:
		_place_memory_node(mem)

func _place_memory_node(mem: Dictionary):
	var m_lat: float = mem.get("lat", last_gps_lat)
	var m_lon: float = mem.get("lon", last_gps_lon)
	var offset := _gps_to_world_offset(last_gps_lat, last_gps_lon, m_lat, m_lon)
	# Base height + random offset pour éviter les superpositions
	var base_y := 1.8 + randf_range(-0.3, 0.3)
	var pos := Vector3(offset.x, base_y, offset.z) - target_world_pos

	var pivot := Node3D.new()
	pivot.name = "MemoryPivot"
	pivot.set_meta("base_y", base_y)
	pivot.set_meta("phase",  randf_range(0.0, TAU))
	pivot.set_meta("ts",     mem.get("ts", 0))   # timestamp = identifiant unique pour delete_memory
	pivot.position = pos

	var sprite := Sprite3D.new()
	var fov: float = mem.get("fov", 70.0)
	sprite.pixel_size    = 0.012 * (70.0 / fov)
	sprite.double_sided  = true
	sprite.billboard     = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.alpha_cut     = SpriteBase3D.ALPHA_CUT_DISABLED
	sprite.modulate      = Color(1.0, 1.0, 1.0, 0.90)
	# Lazy loading : on ne charge PAS la texture ici pour éviter la saturation VRAM
	# (200 textures PNG au démarrage = crash sur mobile bas de gamme)
	# Le chargement se fait dans _update_memory_culling() quand on s'approche
	sprite.texture = preload("res://icon.svg")  # placeholder neutre
	var thumb_path: String = mem.get("thumb", mem.get("path", ""))
	pivot.set_meta("thumb_path", thumb_path)
	pivot.set_meta("is_loaded",  false)

	world_root.add_child(pivot)
	pivot.add_child(sprite)
	_memory_pivots.append(pivot)

# ── Snapshot temps-réel ────────────────────────────────────────

func _on_snapshot_taken(tex: Texture2D, lat: float, lon: float,
		_azimut: float, _pitch: float, fov: float):
	var offset := _gps_to_world_offset(last_gps_lat, last_gps_lon, lat, lon)
	var base_y := 2.0
	var pos := Vector3(offset.x, base_y, offset.z) - target_world_pos

	var pivot := Node3D.new()
	pivot.name = "MemoryPivot"
	pivot.set_meta("base_y", base_y)
	pivot.set_meta("phase",  randf_range(0.0, TAU))
	pivot.position = pos

	# Récupérer le thumb_path depuis le dernier memory persisté
	# (save_web_snapshot ou take_real_snapshot ont déjà appelé _persist_memory avant ce signal)
	var memories := Spacememory_Vision.load_memories()
	var thumb := ""
	if memories.size() > 0:
		var last: Dictionary = memories[memories.size() - 1]
		thumb = last.get("thumb", "")
	var mem_ts: int = (memories[memories.size()-1].get("ts", 0) as int) if memories.size() > 0 else int(Time.get_unix_time_from_system())
	pivot.set_meta("ts",         mem_ts)
	pivot.set_meta("thumb_path", thumb)
	pivot.set_meta("is_loaded",  true)  # texture fournie directement, pas de lazy load initial

	var sprite := Sprite3D.new()
	sprite.texture       = tex
	sprite.pixel_size    = 0.012 * (70.0 / fov)
	sprite.double_sided  = true
	sprite.billboard     = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.modulate      = Color(1.0, 1.0, 1.0, 0.90)

	world_root.add_child(pivot)
	pivot.add_child(sprite)
	_memory_pivots.append(pivot)

func _on_memory_deleted(ts: int):
	# Détruit le pivot 3D correspondant au timestamp supprimé
	for i in range(_memory_pivots.size() - 1, -1, -1):
		var pivot := _memory_pivots[i]
		if is_instance_valid(pivot) and pivot.get_meta("ts", -1) == ts:
			pivot.queue_free()
			_memory_pivots.remove_at(i)

# ── Helpers internes ───────────────────────────────────────────

func _gps_to_world_offset(from_lat: float, from_lon: float, to_lat: float, to_lon: float) -> Vector3:
	# Projection polaire exacte : haversine distance + cap géodésique
	# Pas d'approximation plane — précis aux pôles et à grande distance (> 50km)
	var dist_m := Phi2X_Math.haversine_distance(from_lat, from_lon, to_lat, to_lon) * 1000.0
	var bearing_r := deg_to_rad(Phi2X_Math.compute_bearing(from_lat, from_lon, to_lat, to_lon))
	return Vector3(sin(bearing_r) * dist_m, 0.0, -cos(bearing_r) * dist_m)

func _apply_floating_origin():
	var offset := world_root.position
	# Compenser le décalage du monde dans la position locale de chaque enfant
	# pour que leur position GLOBALE reste identique
	for child in world_root.get_children():
		child.position += offset
	world_root.position = Vector3.ZERO
	target_world_pos -= offset
	_shader_world_offset += offset
	# Modulo sur la période de la grille pour garder l'offset GPU < 1 hexagone (évite la perte float32)
	const HEX_SIZE: float = 4.0  # doit correspondre au paramètre hex_size du shader
	# fposmod garantit un offset toujours positif — fmod renvoie négatif si l'offset
	# est négatif (marche vers le sud-ouest), causant un "snap" visible de la grille hex
	_shader_world_offset.x = fposmod(_shader_world_offset.x, HEX_SIZE)
	_shader_world_offset.z = fposmod(_shader_world_offset.z, 1.7320508 * HEX_SIZE)

func _update_shader_offset():
	if not is_instance_valid(ground_mesh):
		push_warning("⚠️ InfiniteGround introuvable !")
		return
	var mat: Material = ground_mesh.get_active_material(0)
	if mat:
		mat.set_shader_parameter("world_offset", _shader_world_offset + world_root.position)
		mat.set_shader_parameter("pulse_speed",  Player_Origin.base_frequency)
		mat.set_shader_parameter("camera_pos",   camera.global_position)

func _update_planck_field():
	if not is_instance_valid(ground_mesh): return
	var mat: Material = ground_mesh.get_active_material(0)
	if not mat: return
	var lat := SpaceTime_Manager.current_gps.x
	var lon := SpaceTime_Manager.current_gps.y
	var ts  := float(Time.get_unix_time_from_system())
	var pentagons := Phi2X_Math.get_dynamic_pentagons(ts)

	var dists: Array = []
	for i in range(pentagons.size()):
		var p: Vector2 = pentagons[i]
		dists.append({"d": Phi2X_Math.haversine_distance(lat, lon, p.x, p.y), "pos": p})
	dists.sort_custom(func(a, b): return a["d"] < b["d"])

	for slot in range(2):
		if slot >= dists.size(): break
		var p: Vector2 = dists[slot]["pos"]
		var bearing_r := deg_to_rad(Phi2X_Math.compute_bearing(lat, lon, p.x, p.y))
		var dir := Vector3(sin(bearing_r), 0.0, -cos(bearing_r))
		mat.set_shader_parameter("pentagon_near" + str(slot + 1), world_root.position + dir * 100000.0)

func _on_gps_updated(lat: float, lon: float):
	var offset := _gps_to_world_offset(last_gps_lat, last_gps_lon, lat, lon)
	# Soustraction : le monde recule quand le joueur avance → illusion de déplacement vers les objets
	target_world_pos.x -= offset.x
	target_world_pos.z -= offset.z
	last_gps_lat = lat
	last_gps_lon = lon
	_update_planck_field()

func _on_recenter():
	is_ar_mode = false
	toggle_ar_mode(false)
	var tw := create_tween()
	tw.tween_property(camera, "transform", default_cam_transform, 0.5).set_trans(Tween.TRANS_SINE)

func _on_matrix_init(pent_id: int, _freq: float):
	var col := Color.from_hsv(pent_id / 12.0, 0.8, 1.0)
	# Réutilise le material existant si possible, évite une fuite à chaque réinitialisation
	var mat := player_avatar.material_override as StandardMaterial3D
	if mat == null:
		mat = StandardMaterial3D.new()
		player_avatar.material_override = mat
	mat.albedo_color = col; mat.emission_enabled = true
	mat.emission = col; mat.emission_energy_multiplier = 8.0
	var ground_mat := ground_mesh.get_active_material(0)
	if ground_mat: ground_mat.set_shader_parameter("grid_color", col)

const RITUAL_BASE_FOV: float = 75.0

func _on_spacememory_events(events: Array):
	for ev in events:
		_spawn_thought_bubble(ev)

func _spawn_thought_bubble(ev: Dictionary):
	var content: String = str(ev.get("content", "")).strip_edges()
	if content.is_empty(): return
	# Limiter le nombre de bulles simultanées
	if _thought_bubbles.size() >= THOUGHT_BUBBLE_COUNT:
		var oldest := _thought_bubbles.pop_front() as Node3D
		if is_instance_valid(oldest): oldest.queue_free()

	var lbl := Label3D.new()
	# Tronquer à 120 caractères, retour à la ligne automatique
	lbl.text = content.substr(0, 120)
	lbl.font_size = THOUGHT_FONT_SIZE
	lbl.pixel_size = 0.006
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.no_depth_test = true
	lbl.outline_size = 8
	lbl.modulate = Color(0.85, 1.0, 0.95, 0.0)        # commence invisible
	lbl.outline_modulate = Color(0.0, 0.05, 0.1, 0.9)
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.width = 3.0  # largeur de la bulle en unités monde (~3m)

	# Position orbitale aléatoire autour du joueur
	var angle := randf() * TAU
	var radius := randf_range(4.0, 10.0)
	var height := randf_range(1.2, 3.5)
	lbl.position = Vector3(sin(angle) * radius, height, -cos(angle) * radius)

	world_root.add_child(lbl)
	_thought_bubbles.append(lbl)

	# Animation : apparition + montée lente + disparition
	var lifetime := randf_range(20.0, 40.0)
	var tw := create_tween().bind_node(lbl)
	tw.tween_property(lbl, "modulate:a", 0.88, 2.0).set_ease(Tween.EASE_OUT)  # fondu entrant
	tw.tween_interval(lifetime - 4.0)
	tw.tween_property(lbl, "modulate:a", 0.0, 4.0).set_ease(Tween.EASE_IN)   # fondu sortant
	tw.tween_callback(func():
		_thought_bubbles.erase(lbl)
		if is_instance_valid(lbl): lbl.queue_free())
	# Dérive verticale lente (Monte de 1.5m sur toute la durée)
	create_tween().bind_node(lbl).tween_property(
		lbl, "position:y", height + 1.5, lifetime).set_ease(Tween.EASE_IN_OUT)

func _on_ritual_progress(pct: float):
	if not is_instance_valid(ground_mesh): return
	var mat: Material = ground_mesh.get_active_material(0)
	if mat: mat.set_shader_parameter("glow_intensity", pct * 5.0)
	# Zoom progressif : FOV 75° → 55° au fur et à mesure de la synchronisation
	camera.fov = lerpf(RITUAL_BASE_FOV, 55.0, pct)
	# Micro-tremblement à partir de 80% (le nœud "sent" l'impulsion hexagonale)
	if pct > 0.8:
		var shake: float = (pct - 0.8) * 0.4  # amplitude max 0.08 à pct=1.0
		camera.h_offset = randf_range(-shake, shake)
		camera.v_offset = randf_range(-shake * 0.5, shake * 0.5)
	else:
		camera.h_offset = 0.0
		camera.v_offset = 0.0
	if pct >= 1.0 or pct <= 0.0:
		camera.fov = RITUAL_BASE_FOV; camera.h_offset = 0.0; camera.v_offset = 0.0
