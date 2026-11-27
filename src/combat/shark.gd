class_name Shark
extends Node3D
## Stylized ocean shark predator: circles swimmers with its curved dorsal fin and
## sweeping caudal lobe slicing the waves, telegraphs a high-speed lunge with wide
## snapping toothed jaws and an undulating 2-segment S-wave tail, and retreats briefly
## after biting or taking damage.

signal bit_target(target: Pawn, damage: float)

enum State { CIRCLE, CHARGE, RETREAT }

const GROUP_SHARKS := &"sharks"
const GROUP_BEASTS := &"beasts"

# Painterly Sea of Scoundrels countershaded pelagic shark palette (authored in sRGB).
const COL_DORSAL_RIDGE := Color(0.133, 0.227, 0.302)       # Deep crown ridge
const COL_DORSAL_MAIN := Color(0.176, 0.290, 0.369)        # Slate-blue dorsal (#2d4a5e)
const COL_FLANK_MID := Color(0.278, 0.412, 0.494)          # Cool steel-slate mid-flank
const COL_BELLY_CREAM := Color(0.863, 0.894, 0.902)        # Cream-ivory underbelly (#dce4e6)
const COL_BELLY_WARM := Color(0.914, 0.922, 0.898)         # Sunlit ventral belly keel
const COL_FIN_LEAD := Color(0.224, 0.353, 0.439)           # Sunlit slate leading edge
const COL_FIN_TIP := Color(0.102, 0.173, 0.231)            # Dark charcoal-slate fin tips
const COL_GILL_DARK := Color(0.063, 0.102, 0.141)          # Deep recessed gill slit
const COL_GILL_LIP := Color(0.149, 0.235, 0.302)           # Sculpted anterior gill fold
const COL_NOSTRIL_DARK := Color(0.071, 0.110, 0.145)       # Recessed snout nostril pit
const COL_EYE_SOCKET := Color(0.094, 0.153, 0.208)         # Brow-shadowed orbital socket
const COL_EYE_DARK := Color(0.031, 0.043, 0.063)           # Glossy wet obsidian predator eye
const COL_MOUTH_CRIMSON := Color(0.478, 0.106, 0.141)      # Dark crimson gums & tongue
const COL_MOUTH_DEEP := Color(0.247, 0.047, 0.071)         # Deep crimson throat interior
const COL_TOOTH_IVORY := Color(0.969, 0.957, 0.906)        # Jagged ivory-white shark teeth

# Articulation constants (negative X pitch opens the -Z lower mandible downward).
const JAW_OPEN_ANGLE := -0.46
const JAW_CLOSED_ANGLE := -0.04
const TAIL_PHASE_LAG := 0.85

# Fusiform torso longitudinal loft stations (-Z snout tip .. +Z tail socket).
# Row: [z, y_center, rx, ry_top, ry_bot, mouth_recess, brow_sculpt]
const BODY_STATIONS: Array[Array] = [
	[-1.44, 0.052, 0.048, 0.032, 0.022, 0.00, 0.00],  # 0: Hydrodynamic snout tip
	[-1.28, 0.062, 0.155, 0.088, 0.056, 0.00, 0.00],  # 1: Forward rostrum (nostrils)
	[-1.10, 0.064, 0.248, 0.148, 0.104, 0.90, 0.20],  # 2: Upper jaw front arcade
	[-0.92, 0.062, 0.308, 0.204, 0.128, 1.00, 1.00],  # 3: Recessed eyes & brow ridges
	[-0.76, 0.044, 0.348, 0.256, 0.176, 0.35, 0.20],  # 4: Jaw corner / hinge
	[-0.56, 0.024, 0.384, 0.308, 0.252, 0.00, 0.00],  # 5: Anterior gill slits (1-2)
	[-0.34, 0.014, 0.408, 0.348, 0.284, 0.00, 0.00],  # 6: Rear gills (3-5) & pectoral root
	[-0.10, 0.020, 0.398, 0.360, 0.286, 0.00, 0.00],  # 7: Peak dorsal shoulders
	[0.14, 0.024, 0.352, 0.326, 0.258, 0.00, 0.00],   # 8: Aft dorsal fin base
	[0.36, 0.024, 0.278, 0.262, 0.212, 0.00, 0.00],   # 9: Pelvic taper
	[0.56, 0.022, 0.206, 0.200, 0.166, 0.00, 0.00],   # 10: Mid-tail socket overlap
]

const BODY_RADIAL_SEGS := 16
const TAIL_MID_RADIAL_SEGS := 12
const SPLASH_DROPLET_COUNT := 16
const SPLASH_DURATION := 0.65
const SPLASH_GRAVITY := 10.5
const CHARGE_WAKE_INTERVAL := 0.56

# Statically cached procedural ArrayMeshes & materials shared across shark packs.
static var _active_sharks: int = 0
static var _spawn_serial: int = 0
static var _mesh_cache: Dictionary = {}
static var _skin_mat: StandardMaterial3D = null
static var _eye_mat: StandardMaterial3D = null
static var _splash_mesh: ArrayMesh = null
static var _splash_mat: StandardMaterial3D = null

@export var max_health: float = 80.0
@export var circle_radius: float = 8.5
@export var swim_speed: float = 5.2
@export var charge_speed: float = 9.4
@export var bite_damage: float = 28.0

var health: float = 80.0
var dead: bool = false
var faction: StringName = &"beast"
var target: Pawn = null
var state: State = State.CIRCLE

var _angle: float = 0.0
var _state_timer: float = 3.5
var _tail_phase: float = 0.0
var _visual_root: Node3D = null
var _tail_mid_node: Node3D = null
var _tail_node: Node3D = null
var _jaw_node: Node3D = null
var _splash_mmi: MultiMeshInstance3D = null
var _center: Vector3 = Vector3.ZERO
var _turn_bank: float = 0.0
var _pitch_tilt: float = 0.0
var _jaw_snap_timer: float = 0.0
var _prev_state: State = State.CIRCLE
var _splash_active: bool = false
var _splash_age: float = 0.0
var _splash_burst_serial: int = 0
var _charge_wake_timer: float = 0.0

# Preallocated ballistic fin-slice spray droplet buffers (zero per-frame heap allocations).
var _drop_px: PackedFloat32Array = PackedFloat32Array()
var _drop_py: PackedFloat32Array = PackedFloat32Array()
var _drop_pz: PackedFloat32Array = PackedFloat32Array()
var _drop_vx: PackedFloat32Array = PackedFloat32Array()
var _drop_vy: PackedFloat32Array = PackedFloat32Array()
var _drop_vz: PackedFloat32Array = PackedFloat32Array()
var _drop_scale: PackedFloat32Array = PackedFloat32Array()
var _drop_spin: PackedFloat32Array = PackedFloat32Array()
var _drop_r: PackedFloat32Array = PackedFloat32Array()
var _drop_g: PackedFloat32Array = PackedFloat32Array()
var _drop_b: PackedFloat32Array = PackedFloat32Array()


func _enter_tree() -> void:
	_active_sharks += 1


func _exit_tree() -> void:
	_release_refs()
	_active_sharks = maxi(0, _active_sharks - 1)
	if _active_sharks == 0:
		clear_shared_cache()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		_release_refs()


func _release_refs() -> void:
	if _splash_mmi != null and is_instance_valid(_splash_mmi):
		_splash_mmi.visible = false
		_splash_mmi.material_override = null
		_splash_mmi.multimesh = null
	_splash_mmi = null
	_splash_active = false


## Release statically cached shared procedural shark meshes & materials cleanly.
static func clear_shared_cache() -> void:
	_mesh_cache.clear()
	_skin_mat = null
	_eye_mat = null
	_splash_mesh = null
	_splash_mat = null


## Return the sculpted MultiMeshInstance3D used for ballistic lunge & fin-slice spray bursts.
func get_splash_spray_node() -> MultiMeshInstance3D:
	return _splash_mmi


## Return true while a ballistic lunge/fin-slice spray burst is actively animating.
func is_splash_active() -> bool:
	return _splash_active


## Return current local positions of all 16 ballistic spray droplets (useful for headless tests).
func get_splash_droplet_positions() -> PackedVector3Array:
	var out := PackedVector3Array()
	out.resize(_drop_px.size())
	for i in _drop_px.size():
		out[i] = Vector3(_drop_px[i], _drop_py[i], _drop_pz[i])
	return out


## Fire an energetic 16-droplet ballistic spray burst arcing upward & outward over 0.65 s.
func trigger_splash_burst(intensity: float = 1.0) -> void:
	if _splash_mmi == null or not is_instance_valid(_splash_mmi) or _splash_mmi.multimesh == null:
		return
	var clamped_i := clampf(intensity, 0.35, 1.8)
	_splash_age = 0.0
	_splash_active = true
	_splash_burst_serial += 1
	var phase_seed := float(_splash_burst_serial) * 2.39996
	var mm := _splash_mmi.multimesh
	for i in SPLASH_DROPLET_COUNT:
		var fi := float(i)
		var side := -1.0 if (i % 2 == 0) else 1.0
		var h1 := fposmod(sin(fi * 12.9898 + phase_seed) * 43758.5453, 1.0)
		var h2 := fposmod(sin(fi * 78.233 + phase_seed * 1.7) * 24634.6345, 1.0)
		var ox := side * lerpf(0.08, 0.28, h1)
		var oy := lerpf(0.28, 0.48, h2)
		var oz := lerpf(-0.95, 0.42, fi / float(SPLASH_DROPLET_COUNT - 1))
		_drop_px[i] = ox
		_drop_py[i] = oy
		_drop_pz[i] = oz
		_drop_vx[i] = side * lerpf(1.15, 2.85, h2) * clamped_i
		_drop_vy[i] = lerpf(2.85, 4.95, h1) * clamped_i
		_drop_vz[i] = lerpf(-0.45, 1.65, h2) * clamped_i
		_drop_scale[i] = lerpf(0.75, 1.50, h1) * lerpf(0.85, 1.15, clampf(clamped_i - 0.5, 0.0, 1.0))
		_drop_spin[i] = side * lerpf(3.5, 9.0, h2)
		var aqua_t := h2 * 0.65
		_drop_r[i] = lerpf(0.98, 0.72, aqua_t)
		_drop_g[i] = lerpf(1.00, 0.94, aqua_t)
		_drop_b[i] = 1.00
		var s := _drop_scale[i] * 0.85
		mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3(s, s * 1.25, s)), Vector3(ox, oy, oz)))
		mm.set_instance_color(i, Color(_drop_r[i], _drop_g[i], _drop_b[i], 0.92))
	_splash_mmi.visible = true


func _ready() -> void:
	health = max_health
	_center = global_position
	_prev_state = state
	_tail_phase = float(_spawn_serial % 16) * 1.65
	_spawn_serial += 1
	add_to_group(GROUP_SHARKS)
	add_to_group(GROUP_BEASTS)
	_init_splash_buffers()
	_build_mesh()
	_build_hitbox()
	_update_articulation(0.0, 0.0, 0.0)
	_update_eye_night_sheen()


func _init_splash_buffers() -> void:
	_drop_px.resize(SPLASH_DROPLET_COUNT)
	_drop_py.resize(SPLASH_DROPLET_COUNT)
	_drop_pz.resize(SPLASH_DROPLET_COUNT)
	_drop_vx.resize(SPLASH_DROPLET_COUNT)
	_drop_vy.resize(SPLASH_DROPLET_COUNT)
	_drop_vz.resize(SPLASH_DROPLET_COUNT)
	_drop_scale.resize(SPLASH_DROPLET_COUNT)
	_drop_spin.resize(SPLASH_DROPLET_COUNT)
	_drop_r.resize(SPLASH_DROPLET_COUNT)
	_drop_g.resize(SPLASH_DROPLET_COUNT)
	_drop_b.resize(SPLASH_DROPLET_COUNT)


func _build_hitbox() -> void:
	var body := StaticBody3D.new()
	body.name = "SharkHitbox"
	body.collision_layer = Pawn.LAYER_PAWN
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.55
	cap.height = 2.6
	cs.shape = cap
	cs.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	body.add_child(cs)
	add_child(body)


func _build_mesh() -> void:
	_ensure_shared_assets()

	_visual_root = Node3D.new()
	_visual_root.name = "VisualRoot"
	add_child(_visual_root)

	# 1. Sculpted countershaded torso, dorsal/pectoral/pelvic fins, gills, nostrils & upper jaw teeth.
	var body_mi := MeshInstance3D.new()
	body_mi.name = "BodyMesh"
	body_mi.mesh = _mesh_cache["body"] as ArrayMesh
	body_mi.material_override = _skin_mat
	_visual_root.add_child(body_mi)

	# 2. Glossy dark predator eyes recessed under sculpted brow ridges.
	var eyes_mi := MeshInstance3D.new()
	eyes_mi.name = "EyesMesh"
	eyes_mi.mesh = _mesh_cache["eyes"] as ArrayMesh
	eyes_mi.material_override = _eye_mat
	_visual_root.add_child(eyes_mi)

	# 3. Articulated hinged U-shaped lower jaw with ivory teeth & dark crimson mouth interior.
	_jaw_node = Node3D.new()
	_jaw_node.name = "JawPivot"
	_jaw_node.position = Vector3(0.0, -0.092, -0.77)
	_visual_root.add_child(_jaw_node)

	var jaw_mi := MeshInstance3D.new()
	jaw_mi.name = "JawMesh"
	jaw_mi.mesh = _mesh_cache["jaw"] as ArrayMesh
	jaw_mi.material_override = _skin_mat
	_jaw_node.add_child(jaw_mi)

	# 4. Segment 1 of 2-segment undulating tail: muscular caudal peduncle + 2nd dorsal & anal fins.
	_tail_mid_node = Node3D.new()
	_tail_mid_node.name = "TailMidPivot"
	_tail_mid_node.position = Vector3(0.0, 0.022, 0.52)
	_visual_root.add_child(_tail_mid_node)

	var tail_mid_mi := MeshInstance3D.new()
	tail_mid_mi.name = "TailMidMesh"
	tail_mid_mi.mesh = _mesh_cache["tail_mid"] as ArrayMesh
	tail_mid_mi.material_override = _skin_mat
	_tail_mid_node.add_child(tail_mid_mi)

	# 5. Segment 2 of 2-segment undulating tail: sweeping crescent heterocercal caudal fin.
	_tail_node = Node3D.new()
	_tail_node.name = "TailFinPivot"
	_tail_node.position = Vector3(0.0, 0.0, 0.54)
	_tail_mid_node.add_child(_tail_node)

	var tail_fin_mi := MeshInstance3D.new()
	tail_fin_mi.name = "TailFinMesh"
	tail_fin_mi.mesh = _mesh_cache["tail_fin"] as ArrayMesh
	tail_fin_mi.material_override = _skin_mat
	_tail_node.add_child(tail_fin_mi)

	# 6. Sculpted 16-droplet zero-primitive MultiMesh ballistic fin-slice & lunge spray bursts.
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = _splash_mesh
	mm.instance_count = SPLASH_DROPLET_COUNT
	for i in SPLASH_DROPLET_COUNT:
		mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3(0.001, 0.001, 0.001)), Vector3.ZERO))
		mm.set_instance_color(i, Color(1.0, 1.0, 1.0, 0.0))

	_splash_mmi = MultiMeshInstance3D.new()
	_splash_mmi.name = "SharkSplashSpray"
	_splash_mmi.multimesh = mm
	_splash_mmi.material_override = _splash_mat
	_splash_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_splash_mmi.visibility_range_end = 110.0
	_splash_mmi.visible = false
	add_child(_splash_mmi)


func apply_damage(amount: float, _from: Node = null) -> void:
	if not Net.is_host() or dead:
		return
	health -= amount
	Audio.play_sfx(&"hit_flesh", global_position)
	if health <= 0.0:
		dead = true
		queue_free()
		return
	# Taking a hit scares the shark into a brief retreat!
	state = State.RETREAT
	_state_timer = 3.2


func _physics_process(delta: float) -> void:
	if dead:
		return

	var yaw_delta := 0.0
	var vertical_vel := 0.0

	if Net.is_host():
		if target == null or not is_instance_valid(target) or target.dead or not target.is_swimming():
			target = _find_swimmer()

		var center := target.global_position if target != null else _center
		_state_timer -= delta

		var goal := global_position
		var spd := swim_speed
		match state:
			State.CIRCLE:
				_angle += (swim_speed / maxf(circle_radius, 2.0)) * delta
				goal = center + Vector3(cos(_angle) * circle_radius, 0.0, sin(_angle) * circle_radius)
				if target != null and _state_timer <= 0.0:
					state = State.CHARGE
					_state_timer = 2.8
					Audio.play_sfx(&"splash_small", global_position, 1.0)
			State.CHARGE:
				spd = charge_speed
				if target != null:
					goal = target.global_position
					if global_position.distance_to(target.global_position) < 1.65:
						target.apply_damage(bite_damage, self)
						Audio.play_sfx(&"splash_large", global_position, -2.0)
						bit_target.emit(target, bite_damage)
						trigger_splash_burst(1.35)
						_jaw_snap_timer = 0.18
						state = State.RETREAT
						_state_timer = 3.6
				if _state_timer <= 0.0:
					state = State.RETREAT
					_state_timer = 2.5
			State.RETREAT:
				var away := (global_position - center)
				away.y = 0.0
				var dir := away.normalized() if away.length_squared() > 0.01 else Vector3.RIGHT
				goal = center + dir * (circle_radius + 4.0)
				if _state_timer <= 0.0:
					state = State.CIRCLE
					_state_timer = 3.5

		var step := Vector3(goal.x - global_position.x, 0.0, goal.z - global_position.z)
		if step.length_squared() > 0.01:
			var fwd := step.normalized()
			global_position += fwd * spd * delta
			var target_yaw := atan2(-fwd.x, -fwd.z)
			var prev_yaw := rotation.y
			rotation.y = lerp_angle(rotation.y, target_yaw, clampf(delta * 5.0, 0.0, 1.0))
			yaw_delta = wrapf(rotation.y - prev_yaw, -PI, PI)

		# Ride just under the visible wave surface so the dorsal fin slices the water!
		var surf := Sea.height(global_position.x, global_position.z)
		var depth_off := -0.35 if state == State.CIRCLE else -0.22
		var prev_y := global_position.y
		global_position.y = lerpf(global_position.y, surf + depth_off, clampf(delta * 8.0, 0.0, 1.0))
		if delta > 0.0001:
			vertical_vel = (global_position.y - prev_y) / delta

		if Ocean.current != null:
			if state == State.CHARGE:
				Ocean.current.add_foam(global_position, 1.15, 0.42)
			else:
				Ocean.current.add_foam(global_position, 0.65, 0.14)

	if state == State.CHARGE and _prev_state == State.CIRCLE:
		trigger_splash_burst(1.1)
		_charge_wake_timer = CHARGE_WAKE_INTERVAL
	elif state == State.CHARGE:
		_charge_wake_timer -= delta
		if _charge_wake_timer <= 0.0:
			_charge_wake_timer = CHARGE_WAKE_INTERVAL
			trigger_splash_burst(0.78)
	_prev_state = state

	_step_splash_spray(delta)
	_update_eye_night_sheen()
	_update_articulation(delta, yaw_delta, vertical_vel)


func _step_splash_spray(delta: float) -> void:
	if not _splash_active or _splash_mmi == null or not is_instance_valid(_splash_mmi):
		return
	var mm := _splash_mmi.multimesh
	if mm == null:
		_splash_active = false
		_splash_mmi.visible = false
		return
	var dt := maxf(delta, 0.0)
	_splash_age += dt
	var t := _splash_age / SPLASH_DURATION
	if t >= 1.0:
		_splash_active = false
		_splash_age = 0.0
		_splash_mmi.visible = false
		return
	var alpha := clampf((1.0 - t) * (1.0 - t * 0.35), 0.0, 1.0) * 0.92
	var size_env := lerpf(0.85, 1.22, minf(t * 2.5, 1.0)) * lerpf(1.0, 0.42, t * t)
	var drag := maxf(0.0, 1.0 - dt * 1.45)
	for i in SPLASH_DROPLET_COUNT:
		var vx := _drop_vx[i] * drag
		var vy := _drop_vy[i] - SPLASH_GRAVITY * dt
		var vz := _drop_vz[i] * drag
		_drop_vx[i] = vx
		_drop_vy[i] = vy
		_drop_vz[i] = vz
		var px := _drop_px[i] + vx * dt
		var py := _drop_py[i] + vy * dt
		var pz := _drop_pz[i] + vz * dt
		_drop_px[i] = px
		_drop_py[i] = py
		_drop_pz[i] = pz
		var s := _drop_scale[i] * size_env
		var spin_ang := _drop_spin[i] * _splash_age
		var drop_basis := Basis(Vector3.UP, spin_ang).scaled(Vector3(s, s * 1.25, s))
		mm.set_instance_transform(i, Transform3D(drop_basis, Vector3(px, py, pz)))
		mm.set_instance_color(i, Color(_drop_r[i], _drop_g[i], _drop_b[i], alpha))


func _update_eye_night_sheen() -> void:
	if _eye_mat == null:
		return
	var dl := clampf(Weather.daylight(), 0.0, 1.0) if Weather != null else 1.0
	var night := 1.0 - dl
	_eye_mat.emission_energy_multiplier = lerpf(0.0, 0.52, night)
	_eye_mat.clearcoat = lerpf(0.85, 1.0, night)
	_eye_mat.rim = lerpf(0.18, 0.65, night)


func _update_articulation(delta: float, yaw_delta: float, vertical_vel: float) -> void:
	_jaw_snap_timer = maxf(0.0, _jaw_snap_timer - delta)

	var tail_freq := 5.8
	var mid_amp := 0.21
	var fin_amp := 0.32
	var sway_amp := 0.055
	var roll_amp := 0.050

	if state == State.CHARGE:
		tail_freq = 12.6
		mid_amp = 0.35
		fin_amp = 0.54
		sway_amp = 0.088
		roll_amp = 0.075
	elif state == State.RETREAT:
		tail_freq = 9.0
		mid_amp = 0.27
		fin_amp = 0.41
		sway_amp = 0.068
		roll_amp = 0.060

	_tail_phase += delta * tail_freq
	var wave_mid := sin(_tail_phase)
	var wave_fin := sin(_tail_phase - TAIL_PHASE_LAG)
	var wave_head := sin(_tail_phase + 0.45)

	if _tail_mid_node != null:
		_tail_mid_node.rotation.y = wave_mid * mid_amp
		_tail_mid_node.rotation.z = wave_mid * (roll_amp * 0.9)
	if _tail_node != null:
		_tail_node.rotation.y = wave_fin * fin_amp

	# Articulated toothed lower jaw snaps wide open downward during CHARGE and closes cleanly otherwise.
	if _jaw_node != null:
		var want_jaw := JAW_CLOSED_ANGLE
		if _jaw_snap_timer > 0.0:
			want_jaw = 0.0
		elif state == State.CHARGE:
			want_jaw = JAW_OPEN_ANGLE
		var jaw_lerp := clampf(delta * (18.0 if _jaw_snap_timer > 0.0 else 9.0), 0.0, 1.0)
		_jaw_node.rotation.x = lerpf(_jaw_node.rotation.x, want_jaw, jaw_lerp) if delta > 0.0 else want_jaw

	# Living counter-yaw, turn banking roll, and swell pitch on VisualRoot without disturbing steering yaw.
	if _visual_root != null:
		var turn_rate := yaw_delta / maxf(delta, 0.008) if delta > 0.0 else 0.0
		var want_bank := clampf(turn_rate * 0.28, -0.26, 0.26)
		var want_pitch := clampf(vertical_vel * 0.085, -0.18, 0.18)
		var smooth_k := clampf(delta * 6.0, 0.0, 1.0)
		_turn_bank = lerpf(_turn_bank, want_bank, smooth_k) if delta > 0.0 else 0.0
		_pitch_tilt = lerpf(_pitch_tilt, want_pitch, smooth_k) if delta > 0.0 else 0.0
		_visual_root.rotation = Vector3(
			_pitch_tilt,
			-wave_head * sway_amp,
			_turn_bank + wave_mid * roll_amp
		)


func _find_swimmer() -> Pawn:
	var best: Pawn = null
	var best_d := 65.0
	for node in get_tree().get_nodes_in_group(&"combatants"):
		var cc := node as CombatComponent
		if cc != null and cc.pawn != null and not cc.pawn.dead and cc.pawn.is_swimming():
			var d := global_position.distance_to(cc.pawn.global_position)
			if d < best_d:
				best_d = d
				best = cc.pawn
	return best


# ------------------------------------------------------------------ shared procedural assets

static func _ensure_shared_assets() -> void:
	if _skin_mat == null:
		_skin_mat = StandardMaterial3D.new()
		_skin_mat.vertex_color_use_as_albedo = true
		_skin_mat.vertex_color_is_srgb = true
		_skin_mat.roughness = 0.34
		_skin_mat.metallic = 0.04

	if _eye_mat == null:
		_eye_mat = StandardMaterial3D.new()
		_eye_mat.vertex_color_use_as_albedo = true
		_eye_mat.vertex_color_is_srgb = true
		_eye_mat.roughness = 0.08
		_eye_mat.metallic = 0.12
		_eye_mat.clearcoat_enabled = true
		_eye_mat.clearcoat = 0.85
		_eye_mat.clearcoat_roughness = 0.08
		_eye_mat.rim_enabled = true
		_eye_mat.rim = 0.18
		_eye_mat.rim_tint = 0.45
		_eye_mat.emission_enabled = true
		_eye_mat.emission = Color(0.56, 0.86, 0.96)
		_eye_mat.emission_energy_multiplier = 0.0

	if _splash_mat == null:
		_splash_mat = StandardMaterial3D.new()
		_splash_mat.vertex_color_use_as_albedo = true
		_splash_mat.vertex_color_is_srgb = true
		_splash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_splash_mat.roughness = 0.15
		_splash_mat.metallic = 0.0
		_splash_mat.rim_enabled = true
		_splash_mat.rim = 0.55
		_splash_mat.rim_tint = 0.35
		_splash_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED

	if _splash_mesh == null:
		_splash_mesh = _build_spray_droplet_mesh()

	if _mesh_cache.is_empty():
		_mesh_cache["body"] = _build_body_mesh()
		_mesh_cache["eyes"] = _build_eyes_mesh()
		_mesh_cache["jaw"] = _build_jaw_mesh()
		_mesh_cache["tail_mid"] = _build_tail_mid_mesh()
		_mesh_cache["tail_fin"] = _build_tail_fin_mesh()


static func _build_spray_droplet_mesh() -> ArrayMesh:
	# Sculpted exact 12-triangle faceted translucent white-aqua spray droplet (zero SphereMesh).
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	const SIDES := 6
	const R_EQ := 0.056
	const Y_TOP := 0.088
	const Y_EQ := -0.010
	const Y_BOT := -0.064
	var top := Vector3(0.0, Y_TOP, 0.0)
	var bot := Vector3(0.0, Y_BOT, 0.0)
	var ring: Array[Vector3] = []
	for s in SIDES:
		var ang := float(s) / float(SIDES) * TAU
		ring.append(Vector3(cos(ang) * R_EQ, Y_EQ, sin(ang) * R_EQ))
	var col_top := Color(0.98, 1.00, 1.00, 0.94)
	var col_eq := Color(0.82, 0.96, 1.00, 0.88)
	var col_bot := Color(0.56, 0.88, 0.96, 0.80)
	for s in SIDES:
		var ns := (s + 1) % SIDES
		_add_outward_tri(st, ring[s], top, ring[ns], Vector3.ZERO, col_eq, col_top, col_eq)
		_add_outward_tri(st, ring[ns], bot, ring[s], Vector3.ZERO, col_eq, col_bot, col_eq)
	st.generate_normals()
	return st.commit()


# ------------------------------------------------------------------ Mesh 1: Fusiform Torso & Fins

static func _build_body_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# 1. Multi-station fusiform countershaded shark body (-Z pointed snout .. +Z tail socket).
	_append_body_loft(st)

	# 2. Recessed dark crimson upper gum arcade & 9 jagged ivory-white triangular upper teeth.
	_append_upper_jaw_teeth(st)

	# 3. Paired sculpted nostril pits on the underside of the hydrodynamic snout.
	_append_nostril_pits(st)

	# 4. Five sculpted dark diagonal gill slits per flank flush against the curved hull.
	_append_gill_slits(st)

	# 5. Subtle sculpted dark orbital socket collars cradling each glossy eye under the brow.
	_append_eye_socket_collars(st)

	# 6. Iconic tall curved swept-back primary dorsal fin with trailing free-tip notch.
	_append_primary_dorsal_fin(st)

	# 7. Sweeping hydrofoil pectoral fins (dark slate top, cream-ivory underside with dark tips).
	for sg: float in [-1.0, 1.0]:
		_append_pectoral_fin(st, sg)

	# 8. Sculpted paired aft ventral pelvic fins.
	for sg: float in [-1.0, 1.0]:
		_append_pelvic_fin(st, sg)

	st.generate_normals()
	return st.commit()


static func _eval_body_ring_point(row: Array, k: int, segs: int) -> Vector3:
	var z: float = float(row[0])
	var yc: float = float(row[1])
	var rx: float = float(row[2])
	var ry_top: float = float(row[3])
	var ry_bot: float = float(row[4])
	var mouth_recess: float = float(row[5])
	var brow_sculpt: float = float(row[6])

	var ang := float(k) / float(segs) * TAU
	var nx := sin(ang)
	var ny := cos(ang)

	var x := nx * rx
	var y := yc
	if ny >= 0.0:
		# Subtle hydrodynamic dorsal spine ridge along top centerline.
		var keel_lift := 1.0 + 0.05 * pow(ny, 4.0)
		var top_pinch := 1.0 - 0.08 * pow(ny, 3.0)
		x *= top_pinch
		y += ny * ry_top * keel_lift
	else:
		# Slightly flattened broad ventral belly with clean lower-flank chine.
		var abs_ny := -ny
		var flat_y := abs_ny * (1.0 - 0.12 * pow(abs_ny, 2.5))
		var chine_w := 1.0 + 0.08 * sin(abs_ny * PI)
		x *= chine_w
		y -= flat_y * ry_bot

		# Carve underslung crimson upper mouth vault cleanly beneath the overhanging snout.
		if mouth_recess > 0.01 and abs_ny > 0.62:
			var vault_t := clampf((abs_ny - 0.62) / 0.38, 0.0, 1.0) * mouth_recess
			y += ry_bot * 0.24 * vault_t

	# Sculpt subtle overhanging predatory brow ridges & recessed eye sockets at eye station.
	if brow_sculpt > 0.01:
		var side_s := 1.0 if nx > 0.0 else (-1.0 if nx < 0.0 else 0.0)
		if ny > 0.58 and ny < 0.82 and absf(nx) > 0.55:
			# Overhanging brow ridge flare.
			x += side_s * 0.026 * brow_sculpt
			y += 0.018 * brow_sculpt
		elif ny > 0.22 and ny < 0.54 and absf(nx) > 0.80:
			# Recessed orbital socket tuck.
			x -= side_s * 0.022 * brow_sculpt

	return Vector3(x, y, z)


static func _eval_body_ring_color(row: Array, k: int, segs: int) -> Color:
	var z: float = float(row[0])
	var mouth_recess: float = float(row[5])
	var brow_sculpt: float = float(row[6])

	var ang := float(k) / float(segs) * TAU
	var ny := cos(ang)
	var nx := sin(ang)

	# Dark crimson underslung mouth cavity roof beneath snout.
	if mouth_recess > 0.55 and ny < -0.58:
		return COL_MOUTH_DEEP if ny < -0.84 else COL_MOUTH_CRIMSON

	# Subtle shadowed eye socket directly under the overhanging brow ridge.
	if brow_sculpt > 0.55 and ny > 0.22 and ny < 0.54 and absf(nx) > 0.80:
		return COL_EYE_SOCKET

	# Crisp countershading boundary running along the lateral flank midline.
	var wave_shift := sin(z * 3.8) * 0.04
	if ny >= 0.72:
		return COL_DORSAL_RIDGE.lerp(COL_DORSAL_MAIN, clampf((1.0 - ny) / 0.28, 0.0, 1.0))
	if ny >= 0.14 + wave_shift:
		return COL_DORSAL_MAIN
	if ny >= -0.14 + wave_shift:
		return COL_FLANK_MID
	if ny >= -0.68:
		return COL_BELLY_CREAM
	return COL_BELLY_CREAM.lerp(COL_BELLY_WARM, clampf((-ny - 0.68) / 0.32, 0.0, 1.0))


static func _sample_body_surface(z_query: float, ang: float) -> Vector3:
	var last_i := BODY_STATIONS.size() - 1
	var i0 := 0
	var i1 := 0
	var t := 0.0
	if z_query <= float(BODY_STATIONS[0][0]):
		i0 = 0
		i1 = 0
	elif z_query >= float(BODY_STATIONS[last_i][0]):
		i0 = last_i
		i1 = last_i
	else:
		for i in range(last_i):
			var za := float(BODY_STATIONS[i][0])
			var zb := float(BODY_STATIONS[i + 1][0])
			if z_query >= za and z_query <= zb:
				i0 = i
				i1 = i + 1
				t = (z_query - za) / maxf(zb - za, 0.0001)
				break

	var ra: Array = BODY_STATIONS[i0]
	var rb: Array = BODY_STATIONS[i1]
	var yc := lerpf(float(ra[1]), float(rb[1]), t)
	var rx := lerpf(float(ra[2]), float(rb[2]), t)
	var ry_top := lerpf(float(ra[3]), float(rb[3]), t)
	var ry_bot := lerpf(float(ra[4]), float(rb[4]), t)

	var nx := sin(ang)
	var ny := cos(ang)
	var x := nx * rx
	var y := yc
	if ny >= 0.0:
		x *= 1.0 - 0.08 * pow(ny, 3.0)
		y += ny * ry_top * (1.0 + 0.05 * pow(ny, 4.0))
	else:
		var abs_ny := -ny
		x *= 1.0 + 0.08 * sin(abs_ny * PI)
		y -= abs_ny * (1.0 - 0.12 * pow(abs_ny, 2.5)) * ry_bot
	return Vector3(x, y, z_query)


static func _append_body_loft(st: SurfaceTool) -> void:
	var rings: Array[Array] = []
	var ring_cols: Array[Array] = []
	var centers: Array[Vector3] = []

	for row in BODY_STATIONS:
		var pts: Array[Vector3] = []
		var cols: Array[Color] = []
		for k in BODY_RADIAL_SEGS:
			pts.append(_eval_body_ring_point(row, k, BODY_RADIAL_SEGS))
			cols.append(_eval_body_ring_color(row, k, BODY_RADIAL_SEGS))
		rings.append(pts)
		ring_cols.append(cols)
		# Keep reference center slightly dorsal inside mouth stations so vault normals face outward.
		var mouth_r: float = float(row[5])
		centers.append(Vector3(0.0, float(row[1]) + mouth_r * 0.04, float(row[0])))

	for j in range(rings.size() - 1):
		var r0: Array = rings[j]
		var r1: Array = rings[j + 1]
		var c0: Array = ring_cols[j]
		var c1: Array = ring_cols[j + 1]
		var ctr := (centers[j] + centers[j + 1]) * 0.5
		for k in BODY_RADIAL_SEGS:
			var nk := (k + 1) % BODY_RADIAL_SEGS
			_add_outward_quad(st, r0[k], r1[k], r1[nk], r0[nk], ctr,
				c0[k], c1[k], c1[nk], c0[nk])

	# Pointed beveled hydrodynamic snout nose cap (-Z).
	var first_r: Array = rings[0]
	var first_c: Array = ring_cols[0]
	var nose_tip := Vector3(0.0, 0.048, -1.505)
	var nose_ref := Vector3(0.0, 0.052, -1.36)
	for k in BODY_RADIAL_SEGS:
		var nk := (k + 1) % BODY_RADIAL_SEGS
		_add_outward_tri(st, nose_tip, first_r[k], first_r[nk], nose_ref,
			COL_DORSAL_MAIN, first_c[k], first_c[nk])

	# Aft socket cap seated cleanly inside the mid-tail peduncle overlap collar (+Z).
	var last_i := rings.size() - 1
	var last_r: Array = rings[last_i]
	var last_c: Array = ring_cols[last_i]
	var aft_tip := Vector3(0.0, 0.022, 0.60)
	var aft_ref := Vector3(0.0, 0.022, 0.46)
	for k in BODY_RADIAL_SEGS:
		var nk := (k + 1) % BODY_RADIAL_SEGS
		_add_outward_tri(st, aft_tip, last_r[nk], last_r[k], aft_ref,
			COL_FLANK_MID, last_c[nk], last_c[k])


static func _append_upper_jaw_teeth(st: SurfaceTool) -> void:
	# 1. Solid sculpted dark crimson upper gum ridge embedded inside the overhanging upper snout.
	const GUM_SEGS := 7
	var gum_pts: Array[Vector3] = []
	var gum_rings: Array[Array] = []
	for i in GUM_SEGS:
		var u := (float(i) / float(GUM_SEGS - 1)) * 2.0 - 1.0
		var ang := u * PI * 0.49
		var gx := 0.212 * sin(ang)
		var gz := -1.14 + (1.0 - cos(ang)) * 0.27
		var gy := lerpf(-0.008, -0.036, u * u)
		var pt := Vector3(gx, gy, gz)
		gum_pts.append(pt)
		var out_xz := Vector3(sin(ang), 0.0, -cos(ang)).normalized()
		# 4-point solid triangular-bevel gum ridge anchored upward inside the skull roof.
		gum_rings.append([
			pt + Vector3(0.0, 0.044, 0.0) + out_xz * 0.022,
			pt + Vector3(0.0, -0.014, 0.0) + out_xz * 0.016,
			pt + Vector3(0.0, -0.016, 0.0) - out_xz * 0.018,
			pt + Vector3(0.0, 0.044, 0.0) - out_xz * 0.022,
		])

	for i in range(GUM_SEGS - 1):
		var r0: Array = gum_rings[i]
		var r1: Array = gum_rings[i + 1]
		var seg_ctr := (gum_pts[i] + gum_pts[i + 1]) * 0.5 + Vector3(0.0, 0.014, 0.0)
		for k in 4:
			var nk := (k + 1) % 4
			var col := COL_MOUTH_DEEP if k >= 2 else COL_MOUTH_CRIMSON
			_add_outward_quad(st, r0[k], r1[k], r1[nk], r0[nk], seg_ctr, col, col, col, col)

	# 2. Nine broad jagged ivory-white triangular shark teeth rooted solidly inside the crimson gum!
	var tooth_count := 9
	for i in tooth_count:
		var u := (float(i) / float(tooth_count - 1)) * 2.0 - 1.0  # -1..+1 left to right
		var ang := u * PI * 0.46
		var arch_x := 0.206 * sin(ang)
		var arch_z := -1.135 + (1.0 - cos(ang)) * 0.265
		var arch_y := lerpf(-0.012, -0.040, u * u)
		var base := Vector3(arch_x, arch_y + 0.008, arch_z)

		# Tangent along the dental arch so each flattened tooth blade aligns with the jaw rim.
		var tang := Vector3(cos(ang), 0.0, sin(ang) * 0.85).normalized()
		var inward := Vector3(-sin(ang), 0.0, cos(ang)).normalized()
		var size_k := lerpf(1.0, 0.68, absf(u))
		var tip := base + Vector3(0.0, -0.060 * size_k, 0.0) + inward * (0.016 * size_k)
		_append_shark_tooth(st, base, tip, tang, inward, 0.021 * size_k, 0.008 * size_k)


static func _append_nostril_pits(st: SurfaceTool) -> void:
	# Sculpted oblique dark nostril recesses embedded cleanly on the snout bevel.
	for sg: float in [-1.0, 1.0]:
		var z_mid := -1.275
		var ang_mid := sg * 2.18  # Lower-outer snout bevel (~125 deg from dorsal spine)
		var surf := _sample_body_surface(z_mid, ang_mid)
		var outward := Vector3(surf.x, surf.y - 0.06, 0.0).normalized()
		var along := Vector3(sg * 0.22, -0.10, -0.96).normalized()
		var across := outward.cross(along).normalized()

		# Dark inner recess surrounded by a raised rim & embedded skin skirt (zero floating gap).
		var c_in := surf + outward * 0.005
		var c_rim := surf + outward * 0.013
		var c_embed := surf - outward * 0.012
		var rim: Array[Vector3] = [
			c_rim + along * 0.034,
			c_rim + across * 0.016,
			c_rim - along * 0.030,
			c_rim - across * 0.016,
		]
		var skirt: Array[Vector3] = [
			c_embed + along * 0.046,
			c_embed + across * 0.026,
			c_embed - along * 0.042,
			c_embed - across * 0.026,
		]
		var ref_in := surf - outward * 0.05
		for k in 4:
			var nk := (k + 1) % 4
			var rim_col := COL_GILL_LIP if k < 2 else COL_BELLY_CREAM
			_add_outward_tri(st, c_in, rim[k], rim[nk], ref_in, COL_NOSTRIL_DARK, COL_NOSTRIL_DARK, rim_col)
			_add_outward_quad(st, rim[k], skirt[k], skirt[nk], rim[nk], ref_in,
				rim_col, COL_FLANK_MID, COL_FLANK_MID, rim_col)


static func _append_gill_slits(st: SurfaceTool) -> void:
	# 5 crisp diagonal dark gill slits per flank conforming directly to the lofted skin curve.
	const GILL_COUNT := 5
	const GILL_VERTS := 4  # 3 vertical segments tracing flank curvature cleanly

	for sg: float in [-1.0, 1.0]:
		for g in GILL_COUNT:
			var g_frac := float(g) / float(GILL_COUNT - 1)
			var z_top := -0.66 + float(g) * 0.072
			var z_bot := z_top + 0.044  # Graceful predatory backward diagonal slant
			var ang_top := sg * lerpf(1.22, 1.32, g_frac)
			var ang_bot := sg * lerpf(2.04, 1.82, g_frac)  # Rear gills shorten above pectoral root

			var strip_front: Array[Vector3] = []
			var strip_crest: Array[Vector3] = []
			var strip_dark: Array[Vector3] = []
			var strip_back: Array[Vector3] = []
			var refs: Array[Vector3] = []

			for v in GILL_VERTS:
				var vt := float(v) / float(GILL_VERTS - 1)
				var z_v := lerpf(z_top, z_bot, vt)
				var a_v := lerpf(ang_top, ang_bot, vt)
				var s_pt := _sample_body_surface(z_v, a_v)
				var rad := Vector3(s_pt.x, (s_pt.y - 0.02) * 0.45, 0.0).normalized()
				# Embed outer margins inside the faceted loft skin; raise beveled anterior gill lip cleanly.
				var end_taper := sin(vt * PI)
				var lip_h := 0.005 + 0.013 * end_taper
				var groove_h := 0.004 + 0.003 * end_taper

				strip_front.append(s_pt + Vector3(0.0, 0.0, -0.020) - rad * 0.012)
				strip_crest.append(s_pt + Vector3(0.0, 0.0, -0.006) + rad * lip_h)
				strip_dark.append(s_pt + Vector3(0.0, 0.0, 0.011) + rad * groove_h)
				strip_back.append(s_pt + Vector3(0.0, 0.0, 0.021) - rad * 0.012)
				refs.append(s_pt - rad * 0.10)

			for v in range(GILL_VERTS - 1):
				var ref_c := (refs[v] + refs[v + 1]) * 0.5
				var col_lip := COL_DORSAL_MAIN if v == 0 else COL_GILL_LIP
				# Sun-catching anterior gill flap bevel.
				_add_outward_quad(st, strip_front[v], strip_crest[v], strip_crest[v + 1], strip_front[v + 1],
					ref_c, col_lip, COL_GILL_LIP, COL_GILL_LIP, col_lip)
				# Deep dark recessed diagonal gill slit.
				_add_outward_quad(st, strip_crest[v], strip_dark[v], strip_dark[v + 1], strip_crest[v + 1],
					ref_c, COL_GILL_DARK, COL_GILL_DARK, COL_GILL_DARK, COL_GILL_DARK)
				# Posterior margin closing solidly into the flank.
				_add_outward_quad(st, strip_dark[v], strip_back[v], strip_back[v + 1], strip_dark[v + 1],
					ref_c, COL_GILL_DARK, COL_FLANK_MID, COL_FLANK_MID, COL_GILL_DARK)


static func _append_eye_socket_collars(st: SurfaceTool) -> void:
	# Subtle beveled dark orbital rim cradling each glossy eye beneath its brow ridge.
	const SEGS := 8
	for sg: float in [-1.0, 1.0]:
		var center := Vector3(sg * 0.258, 0.142, -0.925)
		var out_dir := Vector3(sg * 0.94, 0.12, -0.32).normalized()
		var up_v := Vector3(0.0, 1.0, 0.0)
		var fwd_v := out_dir.cross(up_v).normalized()
		up_v = fwd_v.cross(out_dir).normalized()

		var inner_ring: Array[Vector3] = []
		var outer_ring: Array[Vector3] = []
		for k in SEGS:
			var a := float(k) / float(SEGS) * TAU
			var radial := fwd_v * (cos(a) * 0.056) + up_v * (sin(a) * 0.048)
			inner_ring.append(center + radial * 0.72 + out_dir * 0.014)
			outer_ring.append(center + radial * 1.24 - out_dir * 0.014)

		var ref_in := center - out_dir * 0.09
		for k in SEGS:
			var nk := (k + 1) % SEGS
			_add_outward_quad(st, outer_ring[k], inner_ring[k], inner_ring[nk], outer_ring[nk],
				ref_in, COL_DORSAL_MAIN, COL_EYE_SOCKET, COL_EYE_SOCKET, COL_DORSAL_MAIN)


static func _append_primary_dorsal_fin(st: SurfaceTool) -> void:
	# Iconic tall curved swept-back shark dorsal fin slicing cleanly above the waves!
	# Format: [y, z_lead, z_trail, half_thick, col_lead, col_mid, col_trail]
	var stations: Array[Array] = [
		[0.28, -0.28, 0.30, 0.095, COL_DORSAL_MAIN, COL_DORSAL_MAIN, COL_DORSAL_RIDGE],
		[0.44, -0.17, 0.26, 0.068, COL_FIN_LEAD, COL_DORSAL_MAIN, COL_DORSAL_RIDGE],
		[0.66, -0.01, 0.28, 0.046, COL_FIN_LEAD, COL_DORSAL_MAIN, COL_FIN_TIP],
		[0.88, 0.16, 0.37, 0.028, COL_DORSAL_MAIN, COL_DORSAL_RIDGE, COL_FIN_TIP],
		[1.03, 0.30, 0.44, 0.013, COL_DORSAL_RIDGE, COL_FIN_TIP, COL_FIN_TIP],
	]
	_append_vertical_fin(st, stations, Vector3(0.0, 1.085, 0.425), COL_FIN_TIP)

	# Classic shark trailing free-tip rear notch lobe at base of dorsal fin.
	var notch_stations: Array[Array] = [
		[0.28, 0.20, 0.36, 0.042, COL_DORSAL_MAIN, COL_DORSAL_RIDGE, COL_FIN_TIP],
		[0.34, 0.23, 0.41, 0.022, COL_DORSAL_RIDGE, COL_FIN_TIP, COL_FIN_TIP],
	]
	_append_vertical_fin(st, notch_stations, Vector3(0.0, 0.355, 0.455), COL_FIN_TIP)


static func _append_pectoral_fin(st: SurfaceTool, side_sign: float) -> void:
	# Long sweeping hydrofoil pectoral fin: dark slate dorsal surface, cream-ivory underside with dark tip.
	# Format: [x_abs, y_ctr, z_lead, z_trail, thick_up, thick_dn, col_top, col_bot]
	var stations: Array[Array] = [
		[0.28, -0.12, -0.46, -0.02, 0.056, 0.042, COL_DORSAL_MAIN, COL_BELLY_CREAM],
		[0.48, -0.15, -0.37, 0.02, 0.044, 0.030, COL_FIN_LEAD, COL_BELLY_CREAM],
		[0.76, -0.21, -0.17, 0.11, 0.032, 0.020, COL_DORSAL_MAIN, COL_BELLY_CREAM],
		[1.02, -0.28, 0.03, 0.22, 0.020, 0.012, COL_DORSAL_RIDGE, COL_FLANK_MID],
		[1.17, -0.33, 0.15, 0.29, 0.010, 0.007, COL_FIN_TIP, COL_FIN_TIP],
	]
	_append_lateral_fin(st, side_sign, stations, Vector3(side_sign * 1.25, -0.36, 0.31), COL_FIN_TIP)


static func _append_pelvic_fin(st: SurfaceTool, side_sign: float) -> void:
	# Smaller swept aft ventral pelvic fins.
	var stations: Array[Array] = [
		[0.16, -0.15, 0.20, 0.44, 0.028, 0.022, COL_FLANK_MID, COL_BELLY_CREAM],
		[0.32, -0.21, 0.30, 0.49, 0.020, 0.014, COL_DORSAL_MAIN, COL_BELLY_CREAM],
		[0.44, -0.26, 0.40, 0.53, 0.010, 0.007, COL_FIN_TIP, COL_FLANK_MID],
	]
	_append_lateral_fin(st, side_sign, stations, Vector3(side_sign * 0.49, -0.28, 0.55), COL_FIN_TIP)


# ------------------------------------------------------------------ Mesh 2: Glossy Dark Predator Eyes

static func _build_eyes_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Sculpted wet obsidian-navy almond-oval predator eyes nestled inside the brow sockets.
	for sg: float in [-1.0, 1.0]:
		var center := Vector3(sg * 0.260, 0.142, -0.925)
		_append_sculpted_eye_dome(st, center, Vector3(0.036, 0.042, 0.048))

	st.generate_normals()
	return st.commit()


static func _append_sculpted_eye_dome(st: SurfaceTool, center: Vector3, radii: Vector3) -> void:
	const LON_SEGS := 10
	const LAT_RINGS := 4
	var rings: Array[Array] = []
	for j in range(1, LAT_RINGS):
		var phi := (float(j) / float(LAT_RINGS)) * PI - PI * 0.5
		var cp := cos(phi)
		var sp := sin(phi)
		var ring: Array[Vector3] = []
		for k in LON_SEGS:
			var th := (float(k) / float(LON_SEGS)) * TAU
			ring.append(center + Vector3(cos(th) * cp * radii.x, sp * radii.y, sin(th) * cp * radii.z))
		rings.append(ring)

	var bot_pole := center + Vector3(0.0, -radii.y, 0.0)
	var top_pole := center + Vector3(0.0, radii.y, 0.0)
	var col_hi := COL_EYE_DARK.lightened(0.08)

	var first_r: Array = rings[0]
	for k in LON_SEGS:
		var nk := (k + 1) % LON_SEGS
		_add_outward_tri(st, bot_pole, first_r[k], first_r[nk], center, COL_EYE_DARK, COL_EYE_DARK, COL_EYE_DARK)

	for j in range(rings.size() - 1):
		var r0: Array = rings[j]
		var r1: Array = rings[j + 1]
		for k in LON_SEGS:
			var nk := (k + 1) % LON_SEGS
			var c_top := col_hi if j == rings.size() - 2 else COL_EYE_DARK
			_add_outward_quad(st, r0[k], r1[k], r1[nk], r0[nk], center,
				COL_EYE_DARK, c_top, c_top, COL_EYE_DARK)

	var last_r: Array = rings[rings.size() - 1]
	for k in LON_SEGS:
		var nk := (k + 1) % LON_SEGS
		_add_outward_tri(st, top_pole, last_r[nk], last_r[k], center, col_hi, col_hi, col_hi)


# ------------------------------------------------------------------ Mesh 3: Hinged Toothed Lower Jaw

static func _build_jaw_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# 7-station sculpted U-shaped horseshoe mandible arch (pivot origin = (0, -0.092, -0.77)).
	const ARCH_SEGS := 7
	var arch_pts: Array[Vector3] = []
	var arch_rings: Array[Array] = []
	var arch_cols: Array[Array] = []
	var inner_top_pts: Array[Vector3] = []
	var inner_bot_pts: Array[Vector3] = []

	for i in ARCH_SEGS:
		var u := (float(i) / float(ARCH_SEGS - 1)) * 2.0 - 1.0  # -1 left hinge .. 0 chin .. +1 right hinge
		var ang := u * PI * 0.52
		var ax := 0.198 * sin(ang)
		var az := -0.345 * cos(ang) + 0.055
		var ay := lerpf(0.018, -0.008, u * u)
		var pt := Vector3(ax, ay, az)
		arch_pts.append(pt)

		# Local outward normal in XZ pointing away from the center of the U-arch.
		var out_xz := Vector3(sin(ang), 0.0, -cos(ang)).normalized()
		var thick_out := lerpf(0.044, 0.052, u * u)
		var thick_in := lerpf(0.036, 0.042, u * u)
		var h_up := lerpf(0.042, 0.034, u * u)
		var h_dn := lerpf(0.052, 0.062, u * u)

		# 6-vertex mandibular bone cross-section: outer cream-ivory chin, inner dark crimson gums!
		var p_top_gum := pt + Vector3(0.0, h_up, 0.0) + out_xz * (thick_out * 0.18)
		var p_out_hi := pt + Vector3(0.0, h_up * 0.45, 0.0) + out_xz * thick_out
		var p_out_lo := pt + Vector3(0.0, -h_dn * 0.62, 0.0) + out_xz * (thick_out * 0.85)
		var p_chin_bot := pt + Vector3(0.0, -h_dn, 0.0) - out_xz * (thick_in * 0.15)
		var p_in_lo := pt + Vector3(0.0, -h_dn * 0.30, 0.0) - out_xz * thick_in
		var p_in_hi := pt + Vector3(0.0, h_up * 0.55, 0.0) - out_xz * (thick_in * 0.88)

		arch_rings.append([p_top_gum, p_out_hi, p_out_lo, p_chin_bot, p_in_lo, p_in_hi])
		var corner_col := COL_BELLY_CREAM.lerp(COL_FLANK_MID, clampf((absf(u) - 0.65) / 0.35, 0.0, 0.55))
		arch_cols.append([
			COL_MOUTH_CRIMSON,
			corner_col,
			COL_BELLY_CREAM,
			COL_BELLY_WARM,
			COL_MOUTH_DEEP,
			COL_MOUTH_CRIMSON,
		])
		inner_top_pts.append(p_in_hi)
		inner_bot_pts.append(p_chin_bot)

	for i in range(ARCH_SEGS - 1):
		var r0: Array = arch_rings[i]
		var r1: Array = arch_rings[i + 1]
		var c0: Array = arch_cols[i]
		var c1: Array = arch_cols[i + 1]
		var seg_ctr := (arch_pts[i] + arch_pts[i + 1]) * 0.5
		for k in 6:
			var nk := (k + 1) % 6
			_add_outward_quad(st, r0[k], r1[k], r1[nk], r0[nk], seg_ctr,
				c0[k], c1[k], c1[nk], c0[nk])

	# Cap left & right rear hinge ends cleanly inside the cheek/throat pocket.
	for end_idx: int in [0, ARCH_SEGS - 1]:
		var er: Array = arch_rings[end_idx]
		var ec: Array = arch_cols[end_idx]
		var cap_pt := arch_pts[end_idx] + Vector3(0.0, 0.0, 0.04)
		var cap_ref := arch_pts[end_idx] + Vector3(0.0, 0.0, -0.05)
		for k in 6:
			var nk := (k + 1) % 6
			_add_outward_tri(st, cap_pt, er[k], er[nk], cap_ref, COL_MOUTH_DEEP, ec[k], ec[nk])

	# Solid sculpted crimson oral floor + raised muscular tongue & solid cream underside chin floor!
	var tongue_tip := Vector3(0.0, 0.014, -0.22)
	var tongue_mid := Vector3(0.0, 0.022, -0.09)
	var throat_back := Vector3(0.0, 0.004, 0.07)
	var chin_mid_bot := Vector3(0.0, -0.068, -0.10)
	var throat_bot := Vector3(0.0, -0.064, 0.07)

	# Upper crimson mouth floor & tongue (faces upward into open mouth).
	var ref_below := Vector3(0.0, -0.22, -0.08)
	_add_outward_tri(st, inner_top_pts[3], inner_top_pts[2], tongue_tip, ref_below,
		COL_MOUTH_CRIMSON, COL_MOUTH_CRIMSON, COL_MOUTH_CRIMSON)
	_add_outward_tri(st, inner_top_pts[3], tongue_tip, inner_top_pts[4], ref_below,
		COL_MOUTH_CRIMSON, COL_MOUTH_CRIMSON, COL_MOUTH_CRIMSON)
	_add_outward_quad(st, inner_top_pts[2], inner_top_pts[1], tongue_mid, tongue_tip, ref_below,
		COL_MOUTH_CRIMSON, COL_MOUTH_DEEP, COL_MOUTH_CRIMSON, COL_MOUTH_CRIMSON)
	_add_outward_quad(st, tongue_tip, tongue_mid, inner_top_pts[5], inner_top_pts[4], ref_below,
		COL_MOUTH_CRIMSON, COL_MOUTH_CRIMSON, COL_MOUTH_DEEP, COL_MOUTH_CRIMSON)
	_add_outward_quad(st, inner_top_pts[1], inner_top_pts[0], throat_back, tongue_mid, ref_below,
		COL_MOUTH_DEEP, COL_MOUTH_DEEP, COL_MOUTH_DEEP, COL_MOUTH_CRIMSON)
	_add_outward_quad(st, tongue_mid, throat_back, inner_top_pts[6], inner_top_pts[5], ref_below,
		COL_MOUTH_CRIMSON, COL_MOUTH_DEEP, COL_MOUTH_DEEP, COL_MOUTH_DEEP)

	# Lower cream-ivory chin floor (faces downward when viewed from below/underwater).
	var ref_above := Vector3(0.0, 0.16, -0.08)
	_add_outward_tri(st, inner_bot_pts[3], inner_bot_pts[2], chin_mid_bot, ref_above,
		COL_BELLY_WARM, COL_BELLY_CREAM, COL_BELLY_WARM)
	_add_outward_tri(st, inner_bot_pts[3], chin_mid_bot, inner_bot_pts[4], ref_above,
		COL_BELLY_WARM, COL_BELLY_WARM, COL_BELLY_CREAM)
	_add_outward_quad(st, inner_bot_pts[2], inner_bot_pts[1], throat_bot, chin_mid_bot, ref_above,
		COL_BELLY_CREAM, COL_BELLY_CREAM, COL_BELLY_WARM, COL_BELLY_WARM)
	_add_outward_quad(st, chin_mid_bot, throat_bot, inner_bot_pts[5], inner_bot_pts[4], ref_above,
		COL_BELLY_WARM, COL_BELLY_WARM, COL_BELLY_CREAM, COL_BELLY_CREAM)
	_add_outward_tri(st, inner_bot_pts[1], inner_bot_pts[0], throat_bot, ref_above,
		COL_BELLY_CREAM, COL_BELLY_CREAM, COL_BELLY_WARM)
	_add_outward_tri(st, throat_bot, inner_bot_pts[6], inner_bot_pts[5], ref_above,
		COL_BELLY_WARM, COL_BELLY_CREAM, COL_BELLY_CREAM)
	# Rear throat bulkhead sealing hinge cavity solidly.
	var ref_front := Vector3(0.0, -0.02, -0.25)
	_add_outward_quad(st, inner_top_pts[0], throat_back, throat_bot, inner_bot_pts[0], ref_front,
		COL_MOUTH_DEEP, COL_MOUTH_DEEP, COL_BELLY_CREAM, COL_BELLY_CREAM)
	_add_outward_quad(st, throat_back, inner_top_pts[6], inner_bot_pts[6], throat_bot, ref_front,
		COL_MOUTH_DEEP, COL_MOUTH_DEEP, COL_BELLY_CREAM, COL_BELLY_CREAM)

	# 9 sharp jagged ivory-white triangular lower teeth rooted solidly inside the crimson lower gum!
	var tooth_count := 9
	for i in tooth_count:
		var u := (float(i) / float(tooth_count - 1)) * 2.0 - 1.0
		var ang := u * PI * 0.45
		var tx := 0.194 * sin(ang)
		var tz := -0.338 * cos(ang) + 0.055
		var ty := lerpf(0.050, 0.022, u * u)  # Rooted 10 mm inside top gum rim
		var base := Vector3(tx, ty, tz)

		var tang := Vector3(cos(ang), 0.0, sin(ang) * 0.85).normalized()
		var inward := Vector3(-sin(ang), 0.0, cos(ang)).normalized()
		var size_k := lerpf(0.96, 0.66, absf(u))
		var tip := base + Vector3(0.0, 0.056 * size_k, 0.0) + inward * (0.015 * size_k)
		_append_shark_tooth(st, base, tip, tang, inward, 0.019 * size_k, 0.0075 * size_k)

	st.generate_normals()
	return st.commit()


# ------------------------------------------------------------------ Mesh 4: Mid-Tail Peduncle Segment

static func _build_tail_mid_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Tapered muscular caudal peduncle with lateral hydrodynamic keels (local z = -0.10 .. +0.60).
	# Format: [z, yc, rx, ry_top, ry_bot, lateral_keel]
	var stations: Array[Array] = [
		[-0.10, 0.000, 0.210, 0.202, 0.168, 0.00],  # Overlap ball-socket collar nested in body
		[0.06, 0.002, 0.190, 0.186, 0.152, 0.00],   # Muscular anterior tail trunk
		[0.24, 0.002, 0.144, 0.148, 0.118, 0.010],  # Mid-peduncle
		[0.44, 0.000, 0.098, 0.108, 0.088, 0.028],  # Caudal keel flare
		[0.60, 0.000, 0.072, 0.084, 0.070, 0.016],  # Tail-fin pivot socket overlap
	]

	var rings: Array[Array] = []
	var ring_cols: Array[Array] = []
	var centers: Array[Vector3] = []

	for row in stations:
		var z: float = float(row[0])
		var yc: float = float(row[1])
		var rx: float = float(row[2])
		var ry_top: float = float(row[3])
		var ry_bot: float = float(row[4])
		var keel: float = float(row[5])

		var pts: Array[Vector3] = []
		var cols: Array[Color] = []
		for k in TAIL_MID_RADIAL_SEGS:
			var ang := float(k) / float(TAIL_MID_RADIAL_SEGS) * TAU
			var nx := sin(ang)
			var ny := cos(ang)
			var keel_flare := keel * pow(absf(nx), 4.0)
			var vx := nx * rx + (1.0 if nx > 0.0 else (-1.0 if nx < 0.0 else 0.0)) * keel_flare
			var vy := yc + ny * (ry_top if ny >= 0.0 else ry_bot)
			pts.append(Vector3(vx, vy, z))

			var col := COL_BELLY_CREAM
			if ny >= 0.72:
				col = COL_DORSAL_RIDGE
			elif ny >= 0.12:
				col = COL_DORSAL_MAIN
			elif ny >= -0.18:
				col = COL_FLANK_MID
			cols.append(col)
		rings.append(pts)
		ring_cols.append(cols)
		centers.append(Vector3(0.0, yc, z))

	for j in range(rings.size() - 1):
		var r0: Array = rings[j]
		var r1: Array = rings[j + 1]
		var c0: Array = ring_cols[j]
		var c1: Array = ring_cols[j + 1]
		var ctr := (centers[j] + centers[j + 1]) * 0.5
		for k in TAIL_MID_RADIAL_SEGS:
			var nk := (k + 1) % TAIL_MID_RADIAL_SEGS
			_add_outward_quad(st, r0[k], r1[k], r1[nk], r0[nk], ctr,
				c0[k], c1[k], c1[nk], c0[nk])

	# Rounded front & rear socket caps for seamless articulation at wide S-wave angles.
	var first_r: Array = rings[0]
	var first_c: Array = ring_cols[0]
	var f_tip := Vector3(0.0, 0.0, -0.16)
	var f_ref := Vector3(0.0, 0.0, -0.02)
	for k in TAIL_MID_RADIAL_SEGS:
		var nk := (k + 1) % TAIL_MID_RADIAL_SEGS
		_add_outward_tri(st, f_tip, first_r[k], first_r[nk], f_ref, COL_FLANK_MID, first_c[k], first_c[nk])

	var last_i := rings.size() - 1
	var last_r: Array = rings[last_i]
	var last_c: Array = ring_cols[last_i]
	var b_tip := Vector3(0.0, 0.0, 0.64)
	var b_ref := Vector3(0.0, 0.0, 0.50)
	for k in TAIL_MID_RADIAL_SEGS:
		var nk := (k + 1) % TAIL_MID_RADIAL_SEGS
		_add_outward_tri(st, b_tip, last_r[nk], last_r[k], b_ref, COL_FLANK_MID, last_c[nk], last_c[k])

	# Sculpted second dorsal fin riding atop the muscular peduncle.
	var second_dorsal: Array[Array] = [
		[0.10, 0.14, 0.40, 0.036, COL_DORSAL_MAIN, COL_DORSAL_MAIN, COL_DORSAL_RIDGE],
		[0.21, 0.24, 0.41, 0.022, COL_FIN_LEAD, COL_DORSAL_MAIN, COL_FIN_TIP],
		[0.31, 0.35, 0.46, 0.010, COL_DORSAL_RIDGE, COL_FIN_TIP, COL_FIN_TIP],
	]
	_append_vertical_fin(st, second_dorsal, Vector3(0.0, 0.345, 0.48), COL_FIN_TIP)

	# Sculpted ventral anal fin beneath the peduncle.
	var anal_fin: Array[Array] = [
		[-0.08, 0.20, 0.44, 0.030, COL_BELLY_CREAM, COL_FLANK_MID, COL_DORSAL_MAIN],
		[-0.17, 0.29, 0.45, 0.018, COL_FLANK_MID, COL_DORSAL_MAIN, COL_FIN_TIP],
		[-0.25, 0.38, 0.49, 0.009, COL_DORSAL_RIDGE, COL_FIN_TIP, COL_FIN_TIP],
	]
	_append_vertical_fin(st, anal_fin, Vector3(0.0, -0.28, 0.51), COL_FIN_TIP)

	st.generate_normals()
	return st.commit()


# ------------------------------------------------------------------ Mesh 5: Heterocercal Caudal Tail Fin

static func _build_tail_fin_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# 1. Rounded peduncle overlap hub seated seamlessly inside TailMidPivot's aft socket.
	const HUB_SEGS := 10
	var hub_stations: Array[Array] = [
		[-0.07, 0.000, 0.076, 0.088, 0.072],
		[0.03, 0.000, 0.064, 0.082, 0.068],
		[0.14, 0.000, 0.042, 0.095, 0.078],
	]
	var h_rings: Array[Array] = []
	var h_cols: Array[Array] = []
	var h_ctrs: Array[Vector3] = []
	for row in hub_stations:
		var z: float = float(row[0])
		var yc: float = float(row[1])
		var rx: float = float(row[2])
		var ry_top: float = float(row[3])
		var ry_bot: float = float(row[4])
		var pts: Array[Vector3] = []
		var cols: Array[Color] = []
		for k in HUB_SEGS:
			var a := float(k) / float(HUB_SEGS) * TAU
			var ny := cos(a)
			pts.append(Vector3(sin(a) * rx, yc + ny * (ry_top if ny >= 0.0 else ry_bot), z))
			cols.append(COL_DORSAL_MAIN if ny >= 0.0 else (COL_FLANK_MID if ny >= -0.35 else COL_BELLY_CREAM))
		h_rings.append(pts)
		h_cols.append(cols)
		h_ctrs.append(Vector3(0.0, yc, z))

	for j in range(h_rings.size() - 1):
		var r0: Array = h_rings[j]
		var r1: Array = h_rings[j + 1]
		var c0: Array = h_cols[j]
		var c1: Array = h_cols[j + 1]
		var ctr := (h_ctrs[j] + h_ctrs[j + 1]) * 0.5
		for k in HUB_SEGS:
			var nk := (k + 1) % HUB_SEGS
			_add_outward_quad(st, r0[k], r1[k], r1[nk], r0[nk], ctr,
				c0[k], c1[k], c1[nk], c0[nk])

	var h_first: Array = h_rings[0]
	var h_first_c: Array = h_cols[0]
	for k in HUB_SEGS:
		var nk := (k + 1) % HUB_SEGS
		_add_outward_tri(st, Vector3(0.0, 0.0, -0.11), h_first[k], h_first[nk],
			Vector3(0.0, 0.0, -0.02), COL_FLANK_MID, h_first_c[k], h_first_c[nk])

	var h_last: Array = h_rings[h_rings.size() - 1]
	var h_last_c: Array = h_cols[h_rings.size() - 1]
	for k in HUB_SEGS:
		var nk := (k + 1) % HUB_SEGS
		_add_outward_tri(st, Vector3(0.0, 0.0, 0.24), h_last[nk], h_last[k],
			Vector3(0.0, 0.0, 0.08), COL_DORSAL_MAIN, h_last_c[nk], h_last_c[k])

	# 2. Taller sweeping upper heterocercal caudal lobe (with classic subterminal notch!).
	var upper_lobe: Array[Array] = [
		[-0.01, 0.00, 0.28, 0.056, COL_DORSAL_MAIN, COL_DORSAL_MAIN, COL_DORSAL_RIDGE],
		[0.16, 0.14, 0.34, 0.044, COL_FIN_LEAD, COL_DORSAL_MAIN, COL_FIN_TIP],
		[0.34, 0.32, 0.46, 0.032, COL_FIN_LEAD, COL_DORSAL_MAIN, COL_FIN_TIP],
		[0.49, 0.49, 0.61, 0.023, COL_DORSAL_MAIN, COL_DORSAL_RIDGE, COL_FIN_TIP],
		[0.55, 0.57, 0.63, 0.017, COL_DORSAL_RIDGE, COL_FIN_TIP, COL_FIN_TIP],  # Subterminal notch
		[0.64, 0.70, 0.77, 0.011, COL_DORSAL_RIDGE, COL_FIN_TIP, COL_FIN_TIP],
	]
	_append_vertical_fin(st, upper_lobe, Vector3(0.0, 0.69, 0.81), COL_FIN_TIP)

	# 3. Shorter stout sweeping lower heterocercal caudal lobe.
	var lower_lobe: Array[Array] = [
		[0.01, 0.00, 0.28, 0.052, COL_BELLY_CREAM, COL_FLANK_MID, COL_DORSAL_MAIN],
		[-0.14, 0.12, 0.31, 0.038, COL_BELLY_CREAM, COL_DORSAL_MAIN, COL_FIN_TIP],
		[-0.28, 0.27, 0.40, 0.024, COL_FLANK_MID, COL_DORSAL_RIDGE, COL_FIN_TIP],
		[-0.39, 0.41, 0.49, 0.012, COL_DORSAL_RIDGE, COL_FIN_TIP, COL_FIN_TIP],
	]
	_append_vertical_fin(st, lower_lobe, Vector3(0.0, -0.44, 0.53), COL_FIN_TIP)

	st.generate_normals()
	return st.commit()


# ------------------------------------------------------------------ Reusable 3D Sculpture Primitives

static func _append_vertical_fin(st: SurfaceTool, stations: Array[Array],
		tip_apex: Vector3, tip_col: Color) -> void:
	# 6-point symmetric NACA hydrofoil cross-section lofted vertically along Y.
	var rings: Array[Array] = []
	var cols: Array[Array] = []
	var centers: Array[Vector3] = []

	for row in stations:
		var y: float = float(row[0])
		var z_lead: float = float(row[1])
		var z_trail: float = float(row[2])
		var w: float = float(row[3])
		var c_lead: Color = row[4]
		var c_mid: Color = row[5]
		var c_trail: Color = row[6]

		var z_max := lerpf(z_lead, z_trail, 0.28)
		var z_taper := lerpf(z_lead, z_trail, 0.66)
		var ring: Array[Vector3] = [
			Vector3(0.0, y, z_lead),
			Vector3(w, y, z_max),
			Vector3(w * 0.52, y, z_taper),
			Vector3(0.0, y, z_trail),
			Vector3(-w * 0.52, y, z_taper),
			Vector3(-w, y, z_max),
		]
		var rcol: Array[Color] = [c_lead, c_mid, c_mid.lerp(c_trail, 0.5), c_trail, c_mid.lerp(c_trail, 0.5), c_mid]
		rings.append(ring)
		cols.append(rcol)
		centers.append(Vector3(0.0, y, lerpf(z_lead, z_trail, 0.36)))

	for j in range(rings.size() - 1):
		var r0: Array = rings[j]
		var r1: Array = rings[j + 1]
		var c0: Array = cols[j]
		var c1: Array = cols[j + 1]
		var ctr := (centers[j] + centers[j + 1]) * 0.5
		for k in 6:
			var nk := (k + 1) % 6
			_add_outward_quad(st, r0[k], r1[k], r1[nk], r0[nk], ctr,
				c0[k], c1[k], c1[nk], c0[nk])

	# Clean sculpted tip cap.
	var last_i := rings.size() - 1
	var top_r: Array = rings[last_i]
	var top_c: Array = cols[last_i]
	var ref_in := centers[last_i] + (centers[last_i] - tip_apex).normalized() * 0.08
	for k in 6:
		var nk := (k + 1) % 6
		_add_outward_tri(st, tip_apex, top_r[k], top_r[nk], ref_in, tip_col, top_c[k], top_c[nk])


static func _append_lateral_fin(st: SurfaceTool, side_sign: float, stations: Array[Array],
		tip_apex: Vector3, tip_col: Color) -> void:
	# 6-point cambered hydrofoil cross-section lofted spanwise along ±X (pectorals & pelvics).
	var rings: Array[Array] = []
	var cols: Array[Array] = []
	var centers: Array[Vector3] = []

	for row in stations:
		var x: float = side_sign * float(row[0])
		var yc: float = float(row[1])
		var z_lead: float = float(row[2])
		var z_trail: float = float(row[3])
		var t_up: float = float(row[4])
		var t_dn: float = float(row[5])
		var c_top: Color = row[6]
		var c_bot: Color = row[7]

		var z_max := lerpf(z_lead, z_trail, 0.30)
		var z_taper := lerpf(z_lead, z_trail, 0.68)
		var ring: Array[Vector3] = [
			Vector3(x, yc, z_lead),
			Vector3(x, yc + t_up, z_max),
			Vector3(x, yc + t_up * 0.46, z_taper),
			Vector3(x, yc - t_dn * 0.14, z_trail),
			Vector3(x, yc - t_dn * 0.50, z_taper),
			Vector3(x, yc - t_dn, z_max),
		]
		var c_edge := c_top.lerp(c_bot, 0.35)
		var c_trail := c_top.lerp(COL_FIN_TIP, 0.55)
		var rcol: Array[Color] = [c_edge, c_top, c_top, c_trail, c_bot, c_bot]
		rings.append(ring)
		cols.append(rcol)
		centers.append(Vector3(x, yc, lerpf(z_lead, z_trail, 0.36)))

	for j in range(rings.size() - 1):
		var r0: Array = rings[j]
		var r1: Array = rings[j + 1]
		var c0: Array = cols[j]
		var c1: Array = cols[j + 1]
		var ctr := (centers[j] + centers[j + 1]) * 0.5
		for k in 6:
			var nk := (k + 1) % 6
			_add_outward_quad(st, r0[k], r1[k], r1[nk], r0[nk], ctr,
				c0[k], c1[k], c1[nk], c0[nk])

	var last_i := rings.size() - 1
	var end_r: Array = rings[last_i]
	var end_c: Array = cols[last_i]
	var ref_in := centers[last_i] + (centers[last_i] - tip_apex).normalized() * 0.08
	for k in 6:
		var nk := (k + 1) % 6
		_add_outward_tri(st, tip_apex, end_r[k], end_r[nk], ref_in, tip_col, end_c[k], end_c[nk])


static func _append_shark_tooth(st: SurfaceTool, base: Vector3, tip: Vector3,
		tang: Vector3, inward: Vector3, half_w: float, half_t: float) -> void:
	# Flattened jagged triangular shark tooth blade with gleaming ivory vertex color.
	var p0 := base + tang * half_w
	var p1 := base + inward * half_t
	var p2 := base - tang * half_w
	var p3 := base - inward * half_t
	var ctr := base.lerp(tip, 0.28)
	var col_base := COL_TOOTH_IVORY.darkened(0.06)
	_add_outward_tri(st, tip, p0, p1, ctr, COL_TOOTH_IVORY, col_base, col_base)
	_add_outward_tri(st, tip, p1, p2, ctr, COL_TOOTH_IVORY, col_base, col_base)
	_add_outward_tri(st, tip, p2, p3, ctr, COL_TOOTH_IVORY, col_base, col_base)
	_add_outward_tri(st, tip, p3, p0, ctr, COL_TOOTH_IVORY, col_base, col_base)


static func _add_outward_quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3,
		ref_center: Vector3, ca: Color, cb: Color, cc: Color, cd: Color) -> void:
	_add_outward_tri(st, a, b, c, ref_center, ca, cb, cc)
	_add_outward_tri(st, a, c, d, ref_center, ca, cc, cd)


static func _add_outward_tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3,
		ref_center: Vector3, ca: Color, cb: Color, cc: Color) -> void:
	# Godot front-face winding is CW -> outward normal is (c - a) x (b - a).
	var n := (c - a).cross(b - a)
	if n.length_squared() < 1e-10:
		return
	var centroid := (a + b + c) / 3.0
	if n.dot(centroid - ref_center) < 0.0:
		var tmp_v := b
		b = c
		c = tmp_v
		var tmp_c := cb
		cb = cc
		cc = tmp_c
	_add_flat_tri(st, a, b, c, ca, cb, cc)


static func _add_flat_tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3,
		ca: Color, cb: Color, cc: Color) -> void:
	if (c - a).cross(b - a).length_squared() < 1e-10:
		return
	st.set_smooth_group(-1)
	st.set_color(ca)
	st.set_uv(Vector2(0.0, 0.0))
	st.add_vertex(a)

	st.set_smooth_group(-1)
	st.set_color(cb)
	st.set_uv(Vector2(1.0, 0.0))
	st.add_vertex(b)

	st.set_smooth_group(-1)
	st.set_color(cc)
	st.set_uv(Vector2(0.5, 1.0))
	st.add_vertex(c)
