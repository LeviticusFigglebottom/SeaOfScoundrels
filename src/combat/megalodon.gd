class_name AncientMegalodon
extends Node3D
## Colossal 16-metre prehistoric scarred apex shark world boss.
##
## Prowls in a wide stalking ring around the target ship with a towering 2.8 m
## battle-notched dorsal fin slicing above the waves, telegraphs devastating hull
## bite charges by flaring bioluminescent turquoise-cyan battle scars and snapping
## triple-rowed serrated jaws wide open, can be staggered out of a charge by
## concentrated cannon/gunfire (>= 95 damage during WINDUP or CHARGE), and yields
## four high-tier floating treasures upon defeat.
##
## 100% sculpted SurfaceTool ArrayMesh geometry (>= 2,200 tris), zero PrimitiveMeshes,
## zero procedural ImageTexture VRAM allocations, and ref-counted leak-free cache teardown.

signal charge_telegraphed(mega: AncientMegalodon, target_ship: Node3D)
signal charge_interrupted(mega: AncientMegalodon, attacker: Node)
signal hull_bitten(mega: AncientMegalodon, ship: Node3D, breaches: int)
signal megalodon_defeated(mega: AncientMegalodon, pos: Vector3, salvage: Array)

enum State { EMERGE, CIRCLE, WINDUP, CHARGE, STAGGERED, RETREAT, DEFEATED }

const GROUP := &"megalodons"
const GROUP_WORLD_EVENTS := &"world_events"
const GROUP_BEASTS := &"beasts"

const MAX_HEALTH := 420.0
const CIRCLE_RADIUS := 34.0
const CHARGE_INTERVAL := 13.5
const CHARGE_WINDUP := 2.4
const CHARGE_INTERRUPT_DAMAGE := 95.0
const BITE_HULL_BREACHES := 2

const EMERGE_DURATION := 1.6
const STAGGER_DURATION := 3.2
const RETREAT_DURATION := 4.5
const CHARGE_TIMEOUT := 7.0
const SINK_DURATION := 3.8

const CIRCLE_SPEED := 10.5
const CHARGE_SPEED := 18.5
const RETREAT_SPEED := 13.5
const BITE_RANGE := 8.5
const BITE_HULL_IMPULSE := 26000.0

# Articulation constants (negative X pitch hinges the -Z lower mandible downward).
const JAW_OPEN_ANGLE := -0.62
const JAW_WINDUP_ANGLE := -0.50
const JAW_CLOSED_ANGLE := -0.05
const TAIL_PHASE_LAG := 0.88

# Painterly abyssal-prehistoric palette (authored in sRGB).
const COL_HIDE_ABYSSAL := Color(0.068, 0.098, 0.148)
const COL_HIDE_DORSAL := Color(0.112, 0.162, 0.226)
const COL_HIDE_FLANK := Color(0.172, 0.236, 0.302)
const COL_HIDE_STRIPE := Color(0.088, 0.125, 0.180)
const COL_BELLY_ASH := Color(0.685, 0.728, 0.742)
const COL_BELLY_PALE := Color(0.775, 0.802, 0.790)
const COL_FIN_LEAD := Color(0.158, 0.224, 0.296)
const COL_FIN_TIP := Color(0.058, 0.088, 0.132)
const COL_GILL_DARK := Color(0.036, 0.054, 0.082)
const COL_GILL_FLAP := Color(0.122, 0.174, 0.236)
const COL_NOSTRIL_DARK := Color(0.042, 0.062, 0.092)
const COL_EYE_SOCKET := Color(0.056, 0.084, 0.126)
const COL_EYE_AMBER := Color(1.0, 0.74, 0.16)
const COL_EYE_CORE := Color(1.0, 0.92, 0.48)
const COL_EYE_PUPIL := Color(0.14, 0.06, 0.02)
const COL_MOUTH_CRIMSON := Color(0.435, 0.078, 0.108)
const COL_MOUTH_DEEP := Color(0.205, 0.032, 0.052)
const COL_TOOTH_IVORY := Color(0.955, 0.938, 0.872)
const COL_TOOTH_ROOT := Color(0.845, 0.810, 0.720)
const COL_BONE_SPINE := Color(0.660, 0.652, 0.582)
const COL_BARNACLE_SHELL := Color(0.755, 0.745, 0.675)
const COL_BARNACLE_DARK := Color(0.245, 0.275, 0.260)
const COL_CORAL_PINK := Color(0.710, 0.345, 0.365)
const COL_SCAR_CORE := Color(0.32, 0.98, 0.95)
const COL_SCAR_EDGE := Color(0.07, 0.56, 0.68)
const COL_SCAR_IDLE := Color(0.14, 0.88, 0.92)
const COL_SCAR_CHARGE := Color(0.72, 1.0, 0.98)
const COL_SCAR_HIT := Color(1.0, 0.24, 0.50)

# Colossal 16 m torso longitudinal loft stations (-Z snout tip .. +Z tail socket).
# Row: [z, y_center, rx, ry_top, ry_bot, mouth_recess, brow_sculpt]
const BODY_STATIONS: Array[Array] = [
	[-7.35, 0.24, 0.24, 0.16, 0.12, 0.00, 0.00],  # 0: Blunted armored snout tip
	[-6.85, 0.28, 0.68, 0.40, 0.26, 0.00, 0.00],  # 1: Forward rostrum & nostrils
	[-6.15, 0.30, 1.16, 0.68, 0.48, 0.85, 0.15],  # 2: Forward upper dental arcade
	[-5.35, 0.28, 1.54, 0.96, 0.62, 1.00, 0.55],  # 3: Mid upper mouth vault
	[-4.65, 0.25, 1.72, 1.20, 0.72, 0.90, 1.00],  # 4: Overhanging brow ridges & eyes
	[-3.95, 0.18, 1.88, 1.44, 0.96, 0.35, 0.35],  # 5: Colossal jaw hinge socket
	[-3.15, 0.10, 2.02, 1.66, 1.28, 0.00, 0.00],  # 6: Anterior gill vault (gills 1-2)
	[-2.30, 0.06, 2.12, 1.84, 1.48, 0.00, 0.00],  # 7: Rear gills (3-5) & pectoral root
	[-1.35, 0.08, 2.14, 1.96, 1.56, 0.00, 0.00],  # 8: Peak armored dorsal shoulders
	[-0.35, 0.10, 2.02, 1.92, 1.52, 0.00, 0.00],  # 9: Primary dorsal fin core
	[0.55, 0.10, 1.82, 1.76, 1.38, 0.00, 0.00],   # 10: Aft dorsal fin base
	[1.35, 0.10, 1.54, 1.50, 1.18, 0.00, 0.00],   # 11: Pelvic fin taper
	[2.05, 0.09, 1.26, 1.24, 0.98, 0.00, 0.00],   # 12: Pre-peduncle trunk
	[2.65, 0.08, 1.02, 1.02, 0.82, 0.00, 0.00],   # 13: Mid-tail socket overlap
	[2.95, 0.08, 0.86, 0.86, 0.70, 0.00, 0.00],   # 14: Aft socket bevel
]

const BODY_RADIAL_SEGS := 24
const TAIL_MID_RADIAL_SEGS := 16

const SALVAGE_LOOT_IDS: Array[StringName] = [
	&"sovereign_chest",
	&"archive_chalice",
	&"captains_skull",
	&"blazing_rage_chest",
]

# Ref-counted static cache shared across all AncientMegalodon instances.
static var _active_megas: int = 0
static var _spawn_serial: int = 0
static var _mesh_cache: Dictionary = {}
static var _hide_mat: StandardMaterial3D = null
static var _scar_mat: StandardMaterial3D = null
static var _eye_mat: StandardMaterial3D = null
static var _splash_mat: StandardMaterial3D = null

@export var max_health: float = MAX_HEALTH
@export var enable_effects: bool = true

var health: float = MAX_HEALTH
var dead: bool = false
var faction: StringName = &"beast"
var target_ship: Node3D = null
var state: State = State.EMERGE

var _center: Vector3 = Vector3.ZERO
var _orbit_angle: float = 0.0
var _orbit_dir: float = 1.0
var _state_timer: float = EMERGE_DURATION
var _emerge_elapsed: float = 0.0
var _charge_damage_taken: float = 0.0
var _clock: float = 0.0
var _tail_phase: float = 0.0
var _hit_flash: float = 0.0
var _jaw_snap_timer: float = 0.0
var _turn_bank: float = 0.0
var _pitch_tilt: float = 0.0
var _stagger_roll: float = 0.0
var _stagger_dir: Vector3 = Vector3.BACK
var _sink_timer: float = 0.0
var _sink_start_y: float = 0.0
var _sinking: bool = false
var _showcase_forced: bool = false
var _showcase_jaw: float = 0.85
var _showcase_scar: float = 1.0
var _emerge_announced: bool = false

var _hitbox: StaticBody3D = null
var _hitbox_shape: CollisionShape3D = null
var _visual_root: Node3D = null
var _body_mi: MeshInstance3D = null
var _scar_mi: MeshInstance3D = null
var _eyes_mi: MeshInstance3D = null
var _jaw_pivot: Node3D = null
var _jaw_mi: MeshInstance3D = null
var _tail_mid_pivot: Node3D = null
var _tail_mid_mi: MeshInstance3D = null
var _tail_mid_scar_mi: MeshInstance3D = null
var _tail_fin_pivot: Node3D = null
var _tail_fin_mi: MeshInstance3D = null
var _inst_scar_mat: StandardMaterial3D = null
var _active_vfx: Array[Dictionary] = []


## Spawn an Ancient Megalodon near `ship` (at `spawn_pos` if finite, else at CIRCLE_RADIUS).
static func spawn_near_ship(parent: Node, ship: Node3D,
		spawn_pos: Vector3 = Vector3.INF) -> AncientMegalodon:
	var mega := AncientMegalodon.new()
	mega.name = "AncientMegalodon"
	mega.target_ship = ship

	var center := Vector3.ZERO
	var ship_fwd := Vector3(0.0, 0.0, -1.0)
	if ship != null and is_instance_valid(ship):
		center = Vector3(ship.global_position.x, 0.0, ship.global_position.z)
		var f := Vector3(-ship.global_basis.z.x, 0.0, -ship.global_basis.z.z)
		if f.length_squared() > 0.001:
			ship_fwd = f.normalized()

	var pos := spawn_pos
	if not pos.is_finite():
		var right := Vector3(-ship_fwd.z, 0.0, ship_fwd.x)
		var side := 1.0 if (_spawn_serial % 2 == 0) else -1.0
		var dir := (ship_fwd * 0.45 + right * (0.89 * side)).normalized()
		pos = center + dir * CIRCLE_RADIUS
	else:
		pos = Vector3(pos.x, 0.0, pos.z)
		if ship == null or not is_instance_valid(ship):
			center = pos

	var surf := Sea.height(pos.x, pos.z) if Sea != null else 0.0
	pos.y = surf - 8.0
	mega._center = center
	mega._orbit_angle = atan2(pos.z - center.z, pos.x - center.x)
	mega.position = pos

	if parent != null:
		parent.add_child(mega)
		if mega.is_inside_tree():
			mega.global_position = pos
	return mega


## Release all statically cached sculpted Megalodon meshes and materials cleanly.
static func clear_shared_cache() -> void:
	_mesh_cache.clear()
	_hide_mat = null
	_scar_mat = null
	_eye_mat = null
	_splash_mat = null


func _enter_tree() -> void:
	_active_megas += 1


func _ready() -> void:
	health = max_health
	_tail_phase = float(_spawn_serial % 16) * 1.45
	_spawn_serial += 1
	add_to_group(GROUP)
	add_to_group(GROUP_WORLD_EVENTS)
	add_to_group(GROUP_BEASTS)

	if _center == Vector3.ZERO:
		if target_ship != null and is_instance_valid(target_ship):
			_center = Vector3(target_ship.global_position.x, 0.0, target_ship.global_position.z)
		else:
			_center = Vector3(global_position.x, 0.0, global_position.z)
	var offset_xz := Vector2(global_position.x - _center.x, global_position.z - _center.z)
	if offset_xz.length_squared() > 0.25:
		_orbit_angle = atan2(offset_xz.y, offset_xz.x)

	_build_visuals()
	_build_hitbox()
	_update_articulation(0.0, 0.0, 0.0)
	_update_scar_material(0.0)


func _exit_tree() -> void:
	_cleanup_all_vfx()
	for mi: MeshInstance3D in [
		_body_mi, _scar_mi, _eyes_mi, _jaw_mi,
		_tail_mid_mi, _tail_mid_scar_mi, _tail_fin_mi,
	]:
		if mi != null and is_instance_valid(mi):
			mi.mesh = null
			mi.material_override = null
	_body_mi = null
	_scar_mi = null
	_eyes_mi = null
	_jaw_mi = null
	_tail_mid_mi = null
	_tail_mid_scar_mi = null
	_tail_fin_mi = null
	_jaw_pivot = null
	_tail_mid_pivot = null
	_tail_fin_pivot = null
	_visual_root = null
	_hitbox = null
	_hitbox_shape = null
	_inst_scar_mat = null
	_active_megas = maxi(0, _active_megas - 1)
	if _active_megas == 0:
		clear_shared_cache()


func _build_hitbox() -> void:
	_hitbox = StaticBody3D.new()
	_hitbox.name = "MegalodonHitbox"
	_hitbox.collision_layer = Pawn.LAYER_PAWN
	_hitbox.collision_mask = 0
	_hitbox.set_meta(&"megalodon", self)

	_hitbox_shape = CollisionShape3D.new()
	_hitbox_shape.name = "HitboxCapsule"
	var cap := CapsuleShape3D.new()
	cap.radius = 2.4
	cap.height = 13.0
	_hitbox_shape.shape = cap
	_hitbox_shape.position = Vector3(0.0, 0.20, -0.40)
	_hitbox_shape.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	_hitbox.add_child(_hitbox_shape)
	add_child(_hitbox)


func _build_visuals() -> void:
	_ensure_shared_assets()
	_inst_scar_mat = _scar_mat.duplicate() as StandardMaterial3D

	_visual_root = Node3D.new()
	_visual_root.name = "VisualRoot"
	add_child(_visual_root)

	# 1. Sculpted colossal prehistoric torso, ragged 2.8 m dorsal fin, pectorals, gills,
	#    osteoderm spines, barnacles & triple-row serrated upper teeth.
	_body_mi = MeshInstance3D.new()
	_body_mi.name = "BodyMesh"
	_body_mi.mesh = _mesh_cache["body"] as ArrayMesh
	_body_mi.material_override = _hide_mat
	_visual_root.add_child(_body_mi)

	# 2. Glowing bioluminescent turquoise-cyan battle scars & dorsal energy ridges.
	_scar_mi = MeshInstance3D.new()
	_scar_mi.name = "ScarGlow"
	_scar_mi.mesh = _mesh_cache["scars"] as ArrayMesh
	_scar_mi.material_override = _inst_scar_mat
	_visual_root.add_child(_scar_mi)

	# 3. Glowing amber-gold prehistoric eyes nestled beneath overhanging brow ridges.
	_eyes_mi = MeshInstance3D.new()
	_eyes_mi.name = "EyesMesh"
	_eyes_mi.mesh = _mesh_cache["eyes"] as ArrayMesh
	_eyes_mi.material_override = _eye_mat
	_visual_root.add_child(_eyes_mi)

	# 4. Hinged colossal lower mandible with triple rows of serrated ivory teeth & crimson gullet.
	_jaw_pivot = Node3D.new()
	_jaw_pivot.name = "JawPivot"
	_jaw_pivot.position = Vector3(0.0, -0.52, -3.95)
	_visual_root.add_child(_jaw_pivot)

	_jaw_mi = MeshInstance3D.new()
	_jaw_mi.name = "JawMesh"
	_jaw_mi.mesh = _mesh_cache["jaw"] as ArrayMesh
	_jaw_mi.material_override = _hide_mat
	_jaw_pivot.add_child(_jaw_mi)

	# 5. Segment 1 of S-wave tail: muscular caudal peduncle, keels, 2nd dorsal, anal fin & scars.
	_tail_mid_pivot = Node3D.new()
	_tail_mid_pivot.name = "TailMidPivot"
	_tail_mid_pivot.position = Vector3(0.0, 0.08, 2.55)
	_visual_root.add_child(_tail_mid_pivot)

	_tail_mid_mi = MeshInstance3D.new()
	_tail_mid_mi.name = "TailMidMesh"
	_tail_mid_mi.mesh = _mesh_cache["tail_mid"] as ArrayMesh
	_tail_mid_mi.material_override = _hide_mat
	_tail_mid_pivot.add_child(_tail_mid_mi)

	_tail_mid_scar_mi = MeshInstance3D.new()
	_tail_mid_scar_mi.name = "TailScarGlow"
	_tail_mid_scar_mi.mesh = _mesh_cache["tail_scars"] as ArrayMesh
	_tail_mid_scar_mi.material_override = _inst_scar_mat
	_tail_mid_pivot.add_child(_tail_mid_scar_mi)

	# 6. Segment 2 of S-wave tail: colossal crescent heterocercal caudal fluke.
	_tail_fin_pivot = Node3D.new()
	_tail_fin_pivot.name = "TailFinPivot"
	_tail_fin_pivot.position = Vector3(0.0, 0.0, 2.85)
	_tail_mid_pivot.add_child(_tail_fin_pivot)

	_tail_fin_mi = MeshInstance3D.new()
	_tail_fin_mi.name = "TailFinMesh"
	_tail_fin_mi.mesh = _mesh_cache["tail_fin"] as ArrayMesh
	_tail_fin_mi.material_override = _hide_mat
	_tail_fin_pivot.add_child(_tail_fin_mi)


# ------------------------------------------------------------------ Public API & Combat

## Host-authoritative damage intake. Accumulates interrupt damage during WINDUP/CHARGE
## and triggers STAGGERED when >= CHARGE_INTERRUPT_DAMAGE, or defeats the boss at <= 0 HP.
func apply_damage(amount: float, source: Node = null) -> bool:
	if not Net.is_host() or dead or amount <= 0.0:
		return false
	health = maxf(0.0, health - amount)
	_hit_flash = 1.0
	if Audio != null:
		Audio.play_sfx(&"hit_flesh", global_position, 2.0)

	if health <= 0.0:
		_defeat()
		return true

	if state == State.WINDUP or state == State.CHARGE:
		_charge_damage_taken += amount
		if _charge_damage_taken >= CHARGE_INTERRUPT_DAMAGE:
			_interrupt_charge(source)
	return true


## Pose the Ancient Megalodon cleanly for static/showcase camera captures.
func force_pose_for_showcase(jaw_open: float = 0.85, scar_glow: float = 1.0) -> void:
	_showcase_forced = true
	_showcase_jaw = clampf(jaw_open, 0.0, 1.0)
	_showcase_scar = clampf(scar_glow, 0.0, 1.5)
	state = State.CHARGE
	_hit_flash = 0.0
	if _jaw_pivot != null:
		_jaw_pivot.rotation.x = lerpf(JAW_CLOSED_ANGLE, JAW_OPEN_ANGLE, _showcase_jaw)
	if _tail_mid_pivot != null:
		_tail_mid_pivot.rotation = Vector3(0.0, 0.24, 0.06)
	if _tail_fin_pivot != null:
		_tail_fin_pivot.rotation = Vector3(0.0, -0.34, 0.0)
	if _visual_root != null:
		_visual_root.rotation = Vector3(0.16, -0.06, -0.10)
	if _inst_scar_mat != null:
		_inst_scar_mat.emission = COL_SCAR_IDLE.lerp(COL_SCAR_CHARGE, clampf(_showcase_scar * 0.75, 0.0, 1.0))
		_inst_scar_mat.emission_energy_multiplier = lerpf(1.4, 7.6, clampf(_showcase_scar, 0.0, 1.0))
	if Ocean.current != null:
		var surf := Sea.height(global_position.x, global_position.z)
		var ring_ctr := Vector3(global_position.x, surf, global_position.z)
		Ocean.current.add_foam(ring_ctr, 6.2, 0.95)
		for ki in 6:
			var a := float(ki) / 6.0 * TAU
			Ocean.current.add_foam(ring_ctr + Vector3(cos(a) * 4.5, 0.0, sin(a) * 4.5), 4.2, 0.85)


## Begin sinking the defeated carcass beneath the waves and free once submerged.
func sink_and_free() -> void:
	if _sinking:
		return
	_sinking = true
	_sink_timer = 0.0
	_sink_start_y = global_position.y


func is_defeated() -> bool:
	return dead or state == State.DEFEATED


func get_health_ratio() -> float:
	if dead or max_health <= 0.0:
		return 0.0
	return clampf(health / max_health, 0.0, 1.0)


func get_scar_emission_energy() -> float:
	return _inst_scar_mat.emission_energy_multiplier if _inst_scar_mat != null else 0.0


# ------------------------------------------------------------------ AI Simulation

func _physics_process(delta: float) -> void:
	if _showcase_forced:
		_tick_vfx(delta)
		return
	step_ai(delta)


## Host-authoritative encounter AI & animation step (safe for deterministic headless loops).
func step_ai(delta: float) -> void:
	if delta < 0.0:
		return
	_clock += delta
	_hit_flash = maxf(0.0, _hit_flash - delta * 3.4)
	_jaw_snap_timer = maxf(0.0, _jaw_snap_timer - delta)
	_tick_vfx(delta)

	if state == State.DEFEATED or dead:
		if not _sinking:
			sink_and_free()
		_step_sink(delta)
		_update_scar_material(delta)
		return

	var yaw_delta := 0.0
	var vertical_vel := 0.0

	if Net.is_host():
		var has_ship := _has_live_ship()
		if has_ship:
			var ship_xz := Vector3(target_ship.global_position.x, 0.0, target_ship.global_position.z)
			_center = _center.lerp(ship_xz, clampf(delta * 2.4, 0.0, 1.0))

		var surf := Sea.height(global_position.x, global_position.z) if Sea != null else 0.0
		var prev_y := global_position.y
		var prev_yaw := rotation.y
		var target_y := surf - 0.85

		match state:
			State.EMERGE:
				if not _emerge_announced:
					_emerge_announced = true
					_spawn_water_burst(Vector3(global_position.x, surf, global_position.z), 1.45)
					_apply_nearby_camera_trauma(global_position, 0.42, 60.0)
					if Audio != null:
						Audio.play_sfx(&"splash_large", global_position, 2.5)
						Audio.play_sfx(&"thunder_near", global_position, -2.0, 0.08)
						Audio.play_stinger(&"danger")
					if Game != null:
						Game.post_notice("Colossal dorsal fin breaches the swell -- Ancient Megalodon surfaces!")
				_emerge_elapsed += delta
				_state_timer -= delta
				var t_em := clampf(_emerge_elapsed / EMERGE_DURATION, 0.0, 1.0)
				var ease_em := 1.0 - pow(1.0 - t_em, 2.4)
				global_position.y = lerpf(surf - 8.0, surf - 0.85, ease_em)
				target_y = global_position.y
				# Face tangent along the stalking ring as it breaches upward.
				var tang := Vector3(-sin(_orbit_angle) * _orbit_dir, 0.0, cos(_orbit_angle) * _orbit_dir)
				if tang.length_squared() > 0.001:
					var want_yaw := atan2(-tang.x, -tang.z)
					rotation.y = lerp_angle(rotation.y, want_yaw, clampf(delta * 4.0, 0.0, 1.0))
				if Ocean.current != null:
					Ocean.current.add_foam(Vector3(global_position.x, surf, global_position.z), 4.6, 0.85)
				if _state_timer <= 0.0:
					state = State.CIRCLE
					_state_timer = CHARGE_INTERVAL

			State.CIRCLE:
				_orbit_angle += _orbit_dir * (CIRCLE_SPEED / maxf(CIRCLE_RADIUS, 6.0)) * delta
				var goal := _center + Vector3(cos(_orbit_angle) * CIRCLE_RADIUS, 0.0, sin(_orbit_angle) * CIRCLE_RADIUS)
				_steer_toward_xz(goal, CIRCLE_SPEED, delta, 4.2)
				target_y = surf - 0.85
				global_position.y = lerpf(global_position.y, target_y, clampf(delta * 5.0, 0.0, 1.0))
				if Ocean.current != null:
					Ocean.current.add_foam(Vector3(global_position.x, surf, global_position.z), 3.1, 0.42)
				_state_timer -= delta
				if _state_timer <= 0.0 and has_ship:
					_begin_windup()

			State.WINDUP:
				_state_timer -= delta
				if not has_ship:
					state = State.CIRCLE
					_state_timer = CHARGE_INTERVAL
				else:
					var ship_pos := target_ship.global_position
					var to_ship := Vector3(ship_pos.x - global_position.x, 0.0, ship_pos.z - global_position.z)
					if to_ship.length_squared() > 0.01:
						var fwd := to_ship.normalized()
						var want_yaw := atan2(-fwd.x, -fwd.z)
						rotation.y = lerp_angle(rotation.y, want_yaw, clampf(delta * 6.5, 0.0, 1.0))
						# Coil slightly outward on initial windup, then surge forward slightly near launch.
						var coil_spd := -1.8 if _state_timer > CHARGE_WINDUP * 0.45 else 2.2
						global_position += fwd * coil_spd * delta
					target_y = surf - 0.18
					global_position.y = lerpf(global_position.y, target_y, clampf(delta * 6.0, 0.0, 1.0))
					if Ocean.current != null:
						Ocean.current.add_foam(Vector3(global_position.x, surf, global_position.z), 4.4, 0.78)
					if _state_timer <= 0.0:
						state = State.CHARGE
						_state_timer = CHARGE_TIMEOUT
						_spawn_water_burst(Vector3(global_position.x, surf, global_position.z), 1.15)
						if Audio != null:
							Audio.play_sfx(&"splash_large", global_position, 2.0)

			State.CHARGE:
				_state_timer -= delta
				if not has_ship:
					state = State.RETREAT
					_state_timer = RETREAT_DURATION
				else:
					var ship_pos := target_ship.global_position
					var to_ship := Vector3(ship_pos.x - global_position.x, 0.0, ship_pos.z - global_position.z)
					var dist_xz := to_ship.length()
					if dist_xz > 0.01:
						var fwd := to_ship / dist_xz
						global_position += fwd * CHARGE_SPEED * delta
						var want_yaw := atan2(-fwd.x, -fwd.z)
						rotation.y = lerp_angle(rotation.y, want_yaw, clampf(delta * 8.5, 0.0, 1.0))
					target_y = surf - 0.10
					global_position.y = lerpf(global_position.y, target_y, clampf(delta * 7.5, 0.0, 1.0))
					if Ocean.current != null:
						Ocean.current.add_foam(Vector3(global_position.x, surf, global_position.z), 4.8, 0.96)
					var post_dist_xz := Vector2(ship_pos.x - global_position.x, ship_pos.z - global_position.z).length()
					if post_dist_xz <= BITE_RANGE:
						_execute_hull_bite()
					elif _state_timer <= 0.0:
						state = State.RETREAT
						_state_timer = RETREAT_DURATION

			State.STAGGERED:
				_state_timer -= delta
				var stag_frac := clampf(_state_timer / STAGGER_DURATION, 0.0, 1.0)
				global_position += _stagger_dir * (8.5 * stag_frac) * delta
				target_y = surf - 0.45 - (1.0 - stag_frac) * 0.55
				global_position.y = lerpf(global_position.y, target_y, clampf(delta * 5.0, 0.0, 1.0))
				if Ocean.current != null:
					Ocean.current.add_foam(Vector3(global_position.x, surf, global_position.z), 4.5, 0.72 * stag_frac + 0.20)
				if _state_timer <= 0.0:
					_orbit_dir = -_orbit_dir
					_orbit_angle = atan2(global_position.z - _center.z, global_position.x - _center.x)
					state = State.RETREAT
					_state_timer = RETREAT_DURATION * 0.75

			State.RETREAT:
				_state_timer -= delta
				var away := Vector3(global_position.x - _center.x, 0.0, global_position.z - _center.z)
				var rad_dir := away.normalized() if away.length_squared() > 0.01 else Vector3(cos(_orbit_angle), 0.0, sin(_orbit_angle))
				var goal := _center + rad_dir * (CIRCLE_RADIUS + 4.0)
				_steer_toward_xz(goal, RETREAT_SPEED, delta, 4.5)
				_orbit_angle = atan2(global_position.z - _center.z, global_position.x - _center.x)
				target_y = surf - 0.95
				global_position.y = lerpf(global_position.y, target_y, clampf(delta * 5.0, 0.0, 1.0))
				if Ocean.current != null:
					Ocean.current.add_foam(Vector3(global_position.x, surf, global_position.z), 3.4, 0.45)
				if _state_timer <= 0.0:
					state = State.CIRCLE
					_state_timer = CHARGE_INTERVAL

		yaw_delta = wrapf(rotation.y - prev_yaw, -PI, PI)
		if delta > 0.0001:
			vertical_vel = (global_position.y - prev_y) / delta

	_update_articulation(delta, yaw_delta, vertical_vel)
	_update_scar_material(delta)


func _has_live_ship() -> bool:
	if target_ship == null or not is_instance_valid(target_ship):
		return false
	var sinking_v: Variant = target_ship.get(&"is_sinking")
	if sinking_v is bool and bool(sinking_v):
		return false
	return true


func _steer_toward_xz(goal: Vector3, speed: float, delta: float, turn_rate: float) -> void:
	var step := Vector3(goal.x - global_position.x, 0.0, goal.z - global_position.z)
	if step.length_squared() > 0.01:
		var fwd := step.normalized()
		global_position += fwd * speed * delta
		var target_yaw := atan2(-fwd.x, -fwd.z)
		rotation.y = lerp_angle(rotation.y, target_yaw, clampf(delta * turn_rate, 0.0, 1.0))


func _begin_windup() -> void:
	state = State.WINDUP
	_state_timer = CHARGE_WINDUP
	_charge_damage_taken = 0.0
	var surf := Sea.height(global_position.x, global_position.z) if Sea != null else 0.0
	_spawn_water_burst(Vector3(global_position.x, surf, global_position.z), 1.0)
	if Audio != null:
		Audio.play_sfx(&"thunder_near", global_position, -1.0, 0.08)
		Audio.play_sfx(&"splash_large", global_position, 1.0)
	charge_telegraphed.emit(self, target_ship)


func _interrupt_charge(source: Node) -> void:
	state = State.STAGGERED
	_state_timer = STAGGER_DURATION
	_charge_damage_taken = 0.0
	var away := Vector3.BACK
	if target_ship != null and is_instance_valid(target_ship):
		away = Vector3(global_position.x - target_ship.global_position.x, 0.0,
			global_position.z - target_ship.global_position.z)
	if away.length_squared() < 0.01:
		away = global_basis.z
		away.y = 0.0
	_stagger_dir = away.normalized() if away.length_squared() > 0.001 else Vector3.BACK
	var surf := Sea.height(global_position.x, global_position.z) if Sea != null else 0.0
	var splash_pt := Vector3(global_position.x, surf, global_position.z)
	_spawn_water_burst(splash_pt, 1.65)
	if Ocean.current != null:
		Ocean.current.add_foam(splash_pt, 6.4, 1.0)
	_apply_nearby_camera_trauma(splash_pt, 0.52, 65.0)
	if Audio != null:
		Audio.play_sfx(&"splash_large", splash_pt, 3.0)
		Audio.play_sfx(&"thunder_near", splash_pt, -2.5, 0.08)
	if Game != null:
		Game.post_notice("Megalodon charge staggered by cannon fire!")
	charge_interrupted.emit(self, source)


func _execute_hull_bite() -> void:
	_jaw_snap_timer = 0.34
	var ship := target_ship
	var breaches := 0
	if ship != null and is_instance_valid(ship):
		var to_mega := Vector3(global_position.x - ship.global_position.x, 0.0,
			global_position.z - ship.global_position.z)
		var radial := to_mega.normalized() if to_mega.length_squared() > 0.001 else Vector3.RIGHT
		var along := Vector3(-radial.z, 0.0, radial.x)
		var bite_center := ship.global_position + radial * 2.2
		bite_center.y = ship.global_position.y - 0.25

		if ship.has_method(&"apply_hull_damage"):
			for bi in BITE_HULL_BREACHES:
				var off_along := (float(bi) - float(BITE_HULL_BREACHES - 1) * 0.5) * 3.4
				var hit_pt := bite_center + along * off_along
				var slot_idx: int = int(ship.call(&"apply_hull_damage", hit_pt, 0.52))
				if slot_idx >= 0:
					breaches += 1
		if breaches == 0:
			breaches = BITE_HULL_BREACHES

		if ship is RigidBody3D:
			var rb := ship as RigidBody3D
			var imp_dir := (-radial + Vector3(0.0, 0.12, 0.0)).normalized()
			var rel_pos := bite_center - rb.global_position
			rel_pos.y = clampf(rel_pos.y, -1.5, 1.5)
			rb.apply_impulse(imp_dir * BITE_HULL_IMPULSE, rel_pos)

		var surf := Sea.height(bite_center.x, bite_center.z) if Sea != null else 0.0
		var splash_pt := Vector3(bite_center.x, surf, bite_center.z)
		_spawn_water_burst(splash_pt, 1.85)
		if Ocean.current != null:
			Ocean.current.add_foam(splash_pt, 6.8, 1.0)
		_apply_nearby_camera_trauma(bite_center, 0.78, 55.0)
		if Audio != null:
			Audio.play_sfx(&"hull_impact", bite_center, 3.5)
			Audio.play_sfx(&"splash_large", splash_pt, 2.5)
			Audio.play_sfx(&"thunder_near", bite_center, -1.5, 0.06)
		hull_bitten.emit(self, ship, breaches)

	_orbit_dir = -_orbit_dir
	_orbit_angle = atan2(global_position.z - _center.z, global_position.x - _center.x)
	state = State.RETREAT
	_state_timer = RETREAT_DURATION


func _defeat() -> void:
	if dead:
		return
	dead = true
	state = State.DEFEATED
	health = 0.0

	if _hitbox != null and is_instance_valid(_hitbox):
		_hitbox.collision_layer = 0
	if _hitbox_shape != null and is_instance_valid(_hitbox_shape):
		_hitbox_shape.disabled = true

	var death_pos := Vector3(global_position.x,
		Sea.height(global_position.x, global_position.z) if Sea != null else 0.0,
		global_position.z)
	_spawn_water_burst(death_pos, 2.15)
	if Ocean.current != null:
		Ocean.current.add_foam(death_pos, 7.6, 1.0)
	_apply_nearby_camera_trauma(death_pos, 0.62, 75.0)

	var salvage: Array = []
	var parent_node := get_parent()
	if parent_node != null:
		for i in SALVAGE_LOOT_IDS.size():
			var ang := (float(i) / float(SALVAGE_LOOT_IDS.size())) * TAU + 0.4
			var rad := 4.4
			var lx := death_pos.x + cos(ang) * rad
			var lz := death_pos.z + sin(ang) * rad
			var ly := (Sea.height(lx, lz) if Sea != null else 0.0) + 0.35
			var lpos := Vector3(lx, ly, lz)
			var item := TreasureCatalog.create_treasure_carryable(SALVAGE_LOOT_IDS[i], lpos)
			parent_node.add_child(item)
			item.global_position = lpos
			salvage.append(item)

	if Game != null:
		if Game.profile != null:
			Game.profile.bump_stat("bosses_defeated", 1)
		Game.post_notice("Ancient Megalodon vanquished! Four chests of deep-sea plunder rise to the waves!")
	if Audio != null:
		Audio.play_sfx(&"splash_large", death_pos, 3.5)
		Audio.play_sfx(&"thunder_near", death_pos, -1.0, 0.06)
		Audio.play_stinger(&"victory")

	megalodon_defeated.emit(self, death_pos, salvage)
	sink_and_free()


func _step_sink(delta: float) -> void:
	_sink_timer += delta
	var t := clampf(_sink_timer / SINK_DURATION, 0.0, 1.0)
	var ease_t := t * t
	global_position.y = lerpf(_sink_start_y, _sink_start_y - 11.5, ease_t)
	if _visual_root != null:
		_visual_root.rotation.z = lerpf(_visual_root.rotation.z, PI * 0.82, clampf(delta * 1.4, 0.0, 1.0))
		_visual_root.rotation.x = lerpf(_visual_root.rotation.x, -0.28, clampf(delta * 1.2, 0.0, 1.0))
	if _jaw_pivot != null:
		_jaw_pivot.rotation.x = lerpf(_jaw_pivot.rotation.x, -0.25, clampf(delta * 2.0, 0.0, 1.0))
	if Ocean.current != null and t < 0.72:
		var surf := Sea.height(global_position.x, global_position.z) if Sea != null else 0.0
		Ocean.current.add_foam(Vector3(global_position.x, surf, global_position.z), 5.2, 0.65 * (1.0 - t))
	if t >= 1.0:
		queue_free()


func _update_articulation(delta: float, yaw_delta: float, vertical_vel: float) -> void:
	var tail_freq := 3.4
	var mid_amp := 0.20
	var fin_amp := 0.30
	var sway_amp := 0.045
	var roll_amp := 0.042

	match state:
		State.WINDUP:
			tail_freq = 7.4
			mid_amp = 0.28
			fin_amp = 0.42
			sway_amp = 0.068
			roll_amp = 0.055
		State.CHARGE:
			tail_freq = 10.6
			mid_amp = 0.36
			fin_amp = 0.54
			sway_amp = 0.082
			roll_amp = 0.072
		State.STAGGERED:
			tail_freq = 4.6
			mid_amp = 0.30
			fin_amp = 0.44
			sway_amp = 0.075
			roll_amp = 0.085
		State.RETREAT:
			tail_freq = 5.4
			mid_amp = 0.24
			fin_amp = 0.36
			sway_amp = 0.055
			roll_amp = 0.050

	_tail_phase += delta * tail_freq
	var wave_mid := sin(_tail_phase)
	var wave_fin := sin(_tail_phase - TAIL_PHASE_LAG)
	var wave_head := sin(_tail_phase + 0.45)

	if _tail_mid_pivot != null:
		_tail_mid_pivot.rotation.y = wave_mid * mid_amp
		_tail_mid_pivot.rotation.z = wave_mid * (roll_amp * 0.9)
	if _tail_fin_pivot != null:
		_tail_fin_pivot.rotation.y = wave_fin * fin_amp

	# Colossal triple-toothed lower jaw snaps wide open (-0.62 rad) on WINDUP/CHARGE.
	if _jaw_pivot != null:
		var want_jaw := JAW_CLOSED_ANGLE
		if _jaw_snap_timer > 0.0:
			want_jaw = -0.02
		elif state == State.CHARGE:
			want_jaw = JAW_OPEN_ANGLE
		elif state == State.WINDUP:
			var w_t := 1.0 - clampf(_state_timer / CHARGE_WINDUP, 0.0, 1.0)
			want_jaw = lerpf(JAW_CLOSED_ANGLE, JAW_WINDUP_ANGLE, smoothstep(0.0, 1.0, w_t))
		elif state == State.STAGGERED:
			want_jaw = -0.28
		var jaw_k := clampf(delta * (18.0 if _jaw_snap_timer > 0.0 else 7.5), 0.0, 1.0)
		_jaw_pivot.rotation.x = lerpf(_jaw_pivot.rotation.x, want_jaw, jaw_k) if delta > 0.0 else want_jaw

	if _visual_root != null:
		var turn_rate := yaw_delta / maxf(delta, 0.008) if delta > 0.0 else 0.0
		var want_bank := clampf(turn_rate * 0.26, -0.24, 0.24)
		var want_pitch := clampf(vertical_vel * 0.045, -0.22, 0.24)
		var want_stagger_roll := 0.58 * _orbit_dir if state == State.STAGGERED else 0.0
		if state == State.EMERGE:
			want_pitch = maxf(want_pitch, 0.26)
		elif state == State.WINDUP:
			want_pitch += 0.08
		var smooth_k := clampf(delta * 5.0, 0.0, 1.0)
		_turn_bank = lerpf(_turn_bank, want_bank, smooth_k) if delta > 0.0 else 0.0
		_pitch_tilt = lerpf(_pitch_tilt, want_pitch, smooth_k) if delta > 0.0 else 0.0
		_stagger_roll = lerpf(_stagger_roll, want_stagger_roll, clampf(delta * 4.5, 0.0, 1.0)) if delta > 0.0 else 0.0
		_visual_root.rotation = Vector3(
			_pitch_tilt,
			-wave_head * sway_amp,
			_turn_bank + _stagger_roll + wave_mid * roll_amp
		)


func _update_scar_material(_delta: float) -> void:
	if _inst_scar_mat == null:
		return
	var energy := 1.95 + sin(_clock * 2.8) * 0.42
	var col := COL_SCAR_IDLE

	match state:
		State.WINDUP:
			var w_t := 1.0 - clampf(_state_timer / CHARGE_WINDUP, 0.0, 1.0)
			var throb := 0.5 + 0.5 * sin(_clock * lerpf(9.0, 22.0, w_t))
			col = COL_SCAR_IDLE.lerp(COL_SCAR_CHARGE, clampf(w_t * 1.15, 0.0, 1.0))
			energy = lerpf(3.2, 7.8, w_t) + throb * 1.6
		State.CHARGE:
			col = COL_SCAR_CHARGE
			energy = 8.4 + sin(_clock * 18.0) * 0.85
		State.STAGGERED:
			col = COL_SCAR_IDLE.lerp(COL_SCAR_HIT, 0.25)
			energy = 1.1 + absf(sin(_clock * 11.0)) * 0.65
		State.DEFEATED:
			var fade := clampf(1.0 - _sink_timer / (SINK_DURATION * 0.7), 0.0, 1.0)
			energy = 1.6 * fade * fade
			col = COL_SCAR_IDLE

	if _hit_flash > 0.01:
		col = col.lerp(COL_SCAR_HIT, clampf(_hit_flash * 0.92, 0.0, 1.0))
		energy = maxf(energy, lerpf(2.2, 7.6, _hit_flash))

	_inst_scar_mat.emission = col
	_inst_scar_mat.emission_energy_multiplier = energy


# ------------------------------------------------------------------ Zero-Primitive VFX & Camera Trauma

func _spawn_water_burst(world_pos: Vector3, scale_mult: float = 1.0) -> void:
	if not enable_effects or not is_inside_tree():
		return
	_ensure_shared_assets()
	if _active_vfx.size() >= 10:
		var old: Dictionary = _active_vfx.pop_front()
		_free_vfx_entry(old)

	var host := Node3D.new()
	host.name = "MegalodonWaterBurst"
	host.top_level = true
	add_child(host)
	host.global_transform = Transform3D(Basis.IDENTITY, world_pos)

	# 1. Sculpted faceted sea-foam droplets (zero PrimitiveMeshes, zero textures).
	var drops := CPUParticles3D.new()
	drops.name = "SprayDrops"
	drops.one_shot = true
	drops.explosiveness = 0.92
	drops.amount = clampi(roundi(28.0 * scale_mult), 16, 48)
	drops.lifetime = 0.95
	drops.direction = Vector3.UP
	drops.spread = 64.0
	drops.initial_velocity_min = 6.0 * scale_mult
	drops.initial_velocity_max = 14.5 * scale_mult
	drops.gravity = Vector3(0.0, -16.0, 0.0)
	drops.scale_amount_min = 0.22 * scale_mult
	drops.scale_amount_max = 0.56 * scale_mult
	drops.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	drops.mesh = _mesh_cache["splash_drop"] as ArrayMesh
	drops.material_override = _splash_mat
	host.add_child(drops)
	drops.emitting = true

	# 2. Expanding sculpted splash-crown foam ring (zero PrimitiveMeshes).
	var ring_mat := _splash_mat.duplicate() as StandardMaterial3D
	ring_mat.albedo_color = Color(0.92, 0.99, 1.0, 0.82)
	var ring := MeshInstance3D.new()
	ring.name = "FoamCrown"
	ring.mesh = _mesh_cache["foam_ring"] as ArrayMesh
	ring.material_override = ring_mat
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.scale = Vector3(0.45 * scale_mult, 0.55 * scale_mult, 0.45 * scale_mult)
	host.add_child(ring)

	_active_vfx.append({
		"root": host,
		"drops": drops,
		"ring": ring,
		"ring_mat": ring_mat,
		"age": 0.0,
		"dur": 1.10,
		"scale": scale_mult,
	})


func _tick_vfx(delta: float) -> void:
	if _active_vfx.is_empty():
		return
	var i := 0
	while i < _active_vfx.size():
		var e: Dictionary = _active_vfx[i]
		var age: float = float(e["age"]) + delta
		var dur: float = float(e["dur"])
		e["age"] = age
		if age >= dur:
			_free_vfx_entry(e)
			_active_vfx.remove_at(i)
			continue
		var t := clampf(age / dur, 0.0, 1.0)
		var ring := e.get("ring") as MeshInstance3D
		var sc := float(e["scale"])
		if ring != null and is_instance_valid(ring):
			var xz := lerpf(0.45, 2.35, 1.0 - pow(1.0 - t, 2.0)) * sc
			var sy := lerpf(0.65, 0.14, t) * sc
			ring.scale = Vector3(xz, sy, xz)
		var rmat := e.get("ring_mat") as StandardMaterial3D
		if rmat != null:
			rmat.albedo_color.a = clampf(0.84 * (1.0 - t) * (1.0 - t), 0.0, 0.84)
		i += 1


func _free_vfx_entry(e: Dictionary) -> void:
	var drops := e.get("drops") as CPUParticles3D
	if drops != null and is_instance_valid(drops):
		drops.emitting = false
		drops.mesh = null
		drops.material_override = null
	var ring := e.get("ring") as MeshInstance3D
	if ring != null and is_instance_valid(ring):
		ring.mesh = null
		ring.material_override = null
	var root := e.get("root") as Node3D
	if root != null and is_instance_valid(root):
		if root.get_parent() == self:
			remove_child(root)
		root.queue_free()


func _cleanup_all_vfx() -> void:
	for e in _active_vfx:
		_free_vfx_entry(e)
	_active_vfx.clear()


func _apply_nearby_camera_trauma(origin: Vector3, max_trauma: float, max_dist: float) -> void:
	var tree := get_tree()
	if tree == null or tree.root == null:
		return
	var pcs: Array[PlayerController] = []
	_collect_player_controllers(tree.root, pcs)
	for pc: PlayerController in pcs:
		if not is_instance_valid(pc) or not pc.is_inside_tree():
			continue
		var ref_pos := pc.pawn.global_position if (pc.pawn != null and is_instance_valid(pc.pawn)) else pc.global_position
		var d := ref_pos.distance_to(origin)
		if d <= max_dist:
			var amt := clampf((1.0 - d / max_dist) * max_trauma, 0.14, max_trauma)
			pc.add_camera_trauma(amt)


static func _collect_player_controllers(node: Node, out: Array[PlayerController]) -> void:
	if node is PlayerController:
		out.append(node as PlayerController)
	for ch in node.get_children():
		_collect_player_controllers(ch, out)


# ------------------------------------------------------------------ Shared Procedural Assets

static func _ensure_shared_assets() -> void:
	if _hide_mat == null:
		_hide_mat = StandardMaterial3D.new()
		_hide_mat.vertex_color_use_as_albedo = true
		_hide_mat.vertex_color_is_srgb = true
		_hide_mat.roughness = 0.36
		_hide_mat.metallic = 0.06
		_hide_mat.clearcoat_enabled = true
		_hide_mat.clearcoat = 0.45
		_hide_mat.clearcoat_roughness = 0.26

	if _scar_mat == null:
		_scar_mat = StandardMaterial3D.new()
		_scar_mat.vertex_color_use_as_albedo = true
		_scar_mat.vertex_color_is_srgb = true
		_scar_mat.roughness = 0.24
		_scar_mat.metallic = 0.05
		_scar_mat.emission_enabled = true
		_scar_mat.emission = COL_SCAR_IDLE
		_scar_mat.emission_energy_multiplier = 2.0

	if _eye_mat == null:
		_eye_mat = StandardMaterial3D.new()
		_eye_mat.vertex_color_use_as_albedo = true
		_eye_mat.vertex_color_is_srgb = true
		_eye_mat.roughness = 0.08
		_eye_mat.metallic = 0.14
		_eye_mat.clearcoat_enabled = true
		_eye_mat.clearcoat = 0.90
		_eye_mat.clearcoat_roughness = 0.08
		_eye_mat.emission_enabled = true
		_eye_mat.emission = COL_EYE_AMBER
		_eye_mat.emission_energy_multiplier = 2.6

	if _splash_mat == null:
		_splash_mat = StandardMaterial3D.new()
		_splash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_splash_mat.vertex_color_use_as_albedo = true
		_splash_mat.vertex_color_is_srgb = true
		_splash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_splash_mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	if _mesh_cache.is_empty():
		_mesh_cache["body"] = _build_body_mesh()
		_mesh_cache["scars"] = _build_scar_mesh()
		_mesh_cache["eyes"] = _build_eyes_mesh()
		_mesh_cache["jaw"] = _build_jaw_mesh()
		_mesh_cache["tail_mid"] = _build_tail_mid_mesh()
		_mesh_cache["tail_scars"] = _build_tail_scar_mesh()
		_mesh_cache["tail_fin"] = _build_tail_fin_mesh()
		_mesh_cache["splash_drop"] = _build_splash_drop_mesh()
		_mesh_cache["foam_ring"] = _build_foam_ring_mesh()


# ------------------------------------------------------------------ Mesh 1: Colossal Armored Torso & Fins

static func _build_body_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# 1. Multi-station heavy prehistoric shark body (-Z snout .. +Z tail socket).
	_append_body_loft(st)

	# 2. Recessed crimson upper gum arcade & triple rows of massive serrated ivory teeth.
	_append_upper_jaw_teeth(st)

	# 3. Paired sculpted nostril pits beneath the heavy rostrum.
	_append_nostril_pits(st)

	# 4. Five deep-carved diagonal armored gill clefts per flank.
	_append_gill_slits(st)

	# 5. Menacing armored orbital socket collars beneath overhanging brow ridges.
	_append_eye_socket_collars(st)

	# 6. Towering ragged notched 2.8 m battle-scarred primary dorsal fin + trailing notch lobe.
	_append_primary_dorsal_fin(st)

	# 7. Bony prehistoric dorsal osteoderm spines fore and aft of the dorsal fin.
	_append_body_dorsal_spines(st)

	# 8. Heavy muscular swept battle-notched pectoral fins (~10.8 m wingspan).
	for sg: float in [-1.0, 1.0]:
		_append_pectoral_fin(st, sg)

	# 9. Ancient encrusted barnacle volcanoes & sea-coral clusters near fin roots & brow.
	_append_barnacle_coral_clusters(st)

	# 10. Sculpted paired aft ventral pelvic fins.
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
		# Muscular armored prehistoric dorsal ridge keel along top centerline.
		var keel_lift := 1.0 + 0.075 * pow(ny, 4.0)
		var top_pinch := 1.0 - 0.10 * pow(ny, 3.0)
		x *= top_pinch
		y += ny * ry_top * keel_lift
	else:
		# Broad reinforced underbelly with heavy lateral chine shelf.
		var abs_ny := -ny
		var flat_y := abs_ny * (1.0 - 0.14 * pow(abs_ny, 2.4))
		var chine_w := 1.0 + 0.09 * sin(abs_ny * PI)
		x *= chine_w
		y -= flat_y * ry_bot

		# Carve cavernous crimson upper mouth vault cleanly beneath overhanging snout.
		if mouth_recess > 0.01 and abs_ny > 0.58:
			var vault_t := clampf((abs_ny - 0.58) / 0.42, 0.0, 1.0) * mouth_recess
			y += ry_bot * 0.30 * vault_t

	# Sculpt menacing overhanging brow ridges & deep recessed orbital eye sockets.
	if brow_sculpt > 0.01:
		var side_s := 1.0 if nx > 0.0 else (-1.0 if nx < 0.0 else 0.0)
		if ny > 0.50 and ny < 0.84 and absf(nx) > 0.48:
			x += side_s * 0.16 * brow_sculpt
			y += 0.12 * brow_sculpt
		elif ny > 0.16 and ny < 0.50 and absf(nx) > 0.78:
			x -= side_s * 0.13 * brow_sculpt

	return Vector3(x, y, z)


static func _eval_body_ring_color(row: Array, k: int, segs: int) -> Color:
	var z: float = float(row[0])
	var mouth_recess: float = float(row[5])
	var brow_sculpt: float = float(row[6])

	var ang := float(k) / float(segs) * TAU
	var ny := cos(ang)
	var nx := sin(ang)

	if mouth_recess > 0.55 and ny < -0.56:
		return COL_MOUTH_DEEP if ny < -0.82 else COL_MOUTH_CRIMSON

	if brow_sculpt > 0.55 and ny > 0.16 and ny < 0.50 and absf(nx) > 0.78:
		return COL_EYE_SOCKET

	# Prehistoric countershading with weathered tiger-slate dorsal bars.
	var wave_shift := sin(z * 0.85) * 0.055
	var stripe_band := sin(z * 1.95 + absf(nx) * 1.4)
	if ny >= 0.72:
		return COL_HIDE_ABYSSAL.lerp(COL_HIDE_DORSAL, clampf((1.0 - ny) / 0.28, 0.0, 1.0))
	if ny >= 0.16 + wave_shift:
		return COL_HIDE_STRIPE if stripe_band > 0.42 else COL_HIDE_DORSAL
	if ny >= -0.14 + wave_shift:
		return COL_HIDE_FLANK
	if ny >= -0.66:
		return COL_BELLY_ASH
	return COL_BELLY_ASH.lerp(COL_BELLY_PALE, clampf((-ny - 0.66) / 0.34, 0.0, 1.0))


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
		x *= 1.0 - 0.10 * pow(ny, 3.0)
		y += ny * ry_top * (1.0 + 0.075 * pow(ny, 4.0))
	else:
		var abs_ny := -ny
		x *= 1.0 + 0.09 * sin(abs_ny * PI)
		y -= abs_ny * (1.0 - 0.14 * pow(abs_ny, 2.4)) * ry_bot
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
		var mouth_r: float = float(row[5])
		centers.append(Vector3(0.0, float(row[1]) + mouth_r * 0.22, float(row[0])))

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

	# Armored blunted rostrum nose cap (-Z).
	var first_r: Array = rings[0]
	var first_c: Array = ring_cols[0]
	var nose_tip := Vector3(0.0, 0.22, -7.65)
	var nose_ref := Vector3(0.0, 0.24, -6.90)
	for k in BODY_RADIAL_SEGS:
		var nk := (k + 1) % BODY_RADIAL_SEGS
		_add_outward_tri(st, nose_tip, first_r[k], first_r[nk], nose_ref,
			COL_HIDE_DORSAL, first_c[k], first_c[nk])

	# Aft socket cap nested cleanly inside TailMidPivot overlap collar (+Z).
	var last_i := rings.size() - 1
	var last_r: Array = rings[last_i]
	var last_c: Array = ring_cols[last_i]
	var aft_tip := Vector3(0.0, 0.08, 3.12)
	var aft_ref := Vector3(0.0, 0.08, 2.40)
	for k in BODY_RADIAL_SEGS:
		var nk := (k + 1) % BODY_RADIAL_SEGS
		_add_outward_tri(st, aft_tip, last_r[nk], last_r[k], aft_ref,
			COL_HIDE_FLANK, last_c[nk], last_c[k])


static func _append_upper_jaw_teeth(st: SurfaceTool) -> void:
	# 1. Sculpted dark crimson upper gum ridge embedded inside overhanging rostrum.
	const GUM_SEGS := 11
	var gum_pts: Array[Vector3] = []
	var gum_rings: Array[Array] = []
	for i in GUM_SEGS:
		var u := (float(i) / float(GUM_SEGS - 1)) * 2.0 - 1.0
		var ang := u * PI * 0.49
		var gx := 1.16 * sin(ang)
		var gz := -5.98 + (1.0 - cos(ang)) * 1.48
		var gy := lerpf(-0.04, -0.22, u * u)
		var pt := Vector3(gx, gy, gz)
		gum_pts.append(pt)
		var out_xz := Vector3(sin(ang), 0.0, -cos(ang)).normalized()
		gum_rings.append([
			pt + Vector3(0.0, 0.24, 0.0) + out_xz * 0.13,
			pt + Vector3(0.0, -0.08, 0.0) + out_xz * 0.10,
			pt + Vector3(0.0, -0.10, 0.0) - out_xz * 0.16,
			pt + Vector3(0.0, 0.24, 0.0) - out_xz * 0.18,
		])

	for i in range(GUM_SEGS - 1):
		var r0: Array = gum_rings[i]
		var r1: Array = gum_rings[i + 1]
		var seg_ctr := (gum_pts[i] + gum_pts[i + 1]) * 0.5 + Vector3(0.0, 0.08, 0.0)
		for k in 4:
			var nk := (k + 1) % 4
			var col := COL_MOUTH_DEEP if k >= 2 else COL_MOUTH_CRIMSON
			_add_outward_quad(st, r0[k], r1[k], r1[nk], r0[nk], seg_ctr, col, col, col, col)

	# 2. Triple rows of massive serrated triangular ivory upper megalodon teeth!
	var row_specs: Array[Array] = [
		[15, 1.13, -5.94, 1.45, -0.02, 0.38, 0.125, 0.046, true],   # Outer colossal serrated row
		[13, 1.01, -5.78, 1.38,  0.02, 0.29, 0.098, 0.036, false],  # Middle replacement row
		[11, 0.89, -5.62, 1.30,  0.05, 0.22, 0.078, 0.028, false],  # Inner recurved fang row
	]
	for spec in row_specs:
		var count: int = int(spec[0])
		var rad_x: float = float(spec[1])
		var z_front: float = float(spec[2])
		var z_sweep: float = float(spec[3])
		var y_off: float = float(spec[4])
		var t_len: float = float(spec[5])
		var t_w: float = float(spec[6])
		var t_t: float = float(spec[7])
		var serrated: bool = bool(spec[8])
		for i in count:
			var u := (float(i) / float(count - 1)) * 2.0 - 1.0
			var ang := u * PI * 0.46
			var ax := rad_x * sin(ang)
			var az := z_front + (1.0 - cos(ang)) * z_sweep
			var ay := lerpf(y_off, y_off - 0.18, u * u)
			var base := Vector3(ax, ay, az)
			var tang := Vector3(cos(ang), 0.0, sin(ang) * 0.85).normalized()
			var inward := Vector3(-sin(ang), 0.0, cos(ang)).normalized()
			var size_k := lerpf(1.0, 0.62, absf(u))
			var tip := base + Vector3(0.0, -t_len * size_k, 0.0) + inward * (t_len * 0.28 * size_k)
			if serrated:
				_append_serrated_tooth(st, base, tip, tang, inward, t_w * size_k, t_t * size_k)
			else:
				_append_blade_tooth(st, base, tip, tang, inward, t_w * size_k, t_t * size_k)


static func _append_nostril_pits(st: SurfaceTool) -> void:
	for sg: float in [-1.0, 1.0]:
		var z_mid := -6.68
		var ang_mid := sg * 2.15
		var surf := _sample_body_surface(z_mid, ang_mid)
		var outward := Vector3(surf.x, surf.y - 0.28, 0.0).normalized()
		var along := Vector3(sg * 0.22, -0.10, -0.96).normalized()
		var across := outward.cross(along).normalized()

		var c_in := surf + outward * 0.025
		var c_rim := surf + outward * 0.068
		var c_embed := surf - outward * 0.060
		var rim: Array[Vector3] = [
			c_rim + along * 0.18,
			c_rim + across * 0.085,
			c_rim - along * 0.16,
			c_rim - across * 0.085,
		]
		var skirt: Array[Vector3] = [
			c_embed + along * 0.24,
			c_embed + across * 0.14,
			c_embed - along * 0.22,
			c_embed - across * 0.14,
		]
		var ref_in := surf - outward * 0.24
		for k in 4:
			var nk := (k + 1) % 4
			var rim_col := COL_GILL_FLAP if k < 2 else COL_BELLY_ASH
			_add_outward_tri(st, c_in, rim[k], rim[nk], ref_in, COL_NOSTRIL_DARK, COL_NOSTRIL_DARK, rim_col)
			_add_outward_quad(st, rim[k], skirt[k], skirt[nk], rim[nk], ref_in,
				rim_col, COL_HIDE_FLANK, COL_HIDE_FLANK, rim_col)


static func _append_gill_slits(st: SurfaceTool) -> void:
	const GILL_COUNT := 5
	const GILL_VERTS := 5

	for sg: float in [-1.0, 1.0]:
		for g in GILL_COUNT:
			var g_frac := float(g) / float(GILL_COUNT - 1)
			var z_top := -3.55 + float(g) * 0.36
			var z_bot := z_top + 0.24
			var ang_top := sg * lerpf(1.18, 1.28, g_frac)
			var ang_bot := sg * lerpf(2.06, 1.82, g_frac)

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
				var rad := Vector3(s_pt.x, (s_pt.y - 0.10) * 0.45, 0.0).normalized()
				var end_taper := sin(vt * PI)
				var lip_h := 0.03 + 0.085 * end_taper
				var groove_h := 0.015 + 0.018 * end_taper

				strip_front.append(s_pt + Vector3(0.0, 0.0, -0.105) - rad * 0.06)
				strip_crest.append(s_pt + Vector3(0.0, 0.0, -0.032) + rad * lip_h)
				strip_dark.append(s_pt + Vector3(0.0, 0.0, 0.062) + rad * groove_h)
				strip_back.append(s_pt + Vector3(0.0, 0.0, 0.115) - rad * 0.06)
				refs.append(s_pt - rad * 0.45)

			for v in range(GILL_VERTS - 1):
				var ref_c := (refs[v] + refs[v + 1]) * 0.5
				var col_lip := COL_HIDE_DORSAL if v == 0 else COL_GILL_FLAP
				_add_outward_quad(st, strip_front[v], strip_crest[v], strip_crest[v + 1], strip_front[v + 1],
					ref_c, col_lip, COL_GILL_FLAP, COL_GILL_FLAP, col_lip)
				_add_outward_quad(st, strip_crest[v], strip_dark[v], strip_dark[v + 1], strip_crest[v + 1],
					ref_c, COL_GILL_DARK, COL_GILL_DARK, COL_GILL_DARK, COL_GILL_DARK)
				_add_outward_quad(st, strip_dark[v], strip_back[v], strip_back[v + 1], strip_dark[v + 1],
					ref_c, COL_GILL_DARK, COL_HIDE_FLANK, COL_HIDE_FLANK, COL_GILL_DARK)


static func _append_eye_socket_collars(st: SurfaceTool) -> void:
	const SEGS := 10
	for sg: float in [-1.0, 1.0]:
		var center := Vector3(sg * 1.46, 0.72, -4.68)
		var out_dir := Vector3(sg * 0.94, 0.12, -0.32).normalized()
		var up_v := Vector3(0.0, 1.0, 0.0)
		var fwd_v := out_dir.cross(up_v).normalized()
		up_v = fwd_v.cross(out_dir).normalized()

		var inner_ring: Array[Vector3] = []
		var outer_ring: Array[Vector3] = []
		for k in SEGS:
			var a := float(k) / float(SEGS) * TAU
			var radial := fwd_v * (cos(a) * 0.30) + up_v * (sin(a) * 0.25)
			inner_ring.append(center + radial * 0.72 + out_dir * 0.08)
			outer_ring.append(center + radial * 1.30 - out_dir * 0.08)

		var ref_in := center - out_dir * 0.42
		for k in SEGS:
			var nk := (k + 1) % SEGS
			_add_outward_quad(st, outer_ring[k], inner_ring[k], inner_ring[nk], outer_ring[nk],
				ref_in, COL_HIDE_DORSAL, COL_EYE_SOCKET, COL_EYE_SOCKET, COL_HIDE_DORSAL)


static func _append_primary_dorsal_fin(st: SurfaceTool) -> void:
	# Towering 2.8 m battle-scarred dorsal fin with TWO dramatic trailing battle notches!
	# Format: [y, z_lead, z_trail, half_thick, col_lead, col_mid, col_trail]
	var stations: Array[Array] = [
		[1.56, -1.55, 1.35, 0.46, COL_HIDE_DORSAL, COL_HIDE_DORSAL, COL_HIDE_ABYSSAL],
		[2.05, -1.18, 1.18, 0.36, COL_FIN_LEAD, COL_HIDE_DORSAL, COL_HIDE_ABYSSAL],
		[2.58, -0.70, 1.24, 0.27, COL_FIN_LEAD, COL_HIDE_DORSAL, COL_FIN_TIP],
		[2.90, -0.36, 0.92, 0.21, COL_FIN_LEAD, COL_HIDE_ABYSSAL, COL_FIN_TIP],      # Battle notch 1!
		[3.26, 0.02, 1.34, 0.18, COL_HIDE_DORSAL, COL_HIDE_ABYSSAL, COL_FIN_TIP],
		[3.72, 0.46, 1.54, 0.13, COL_HIDE_DORSAL, COL_FIN_TIP, COL_FIN_TIP],
		[4.02, 0.76, 1.30, 0.10, COL_HIDE_ABYSSAL, COL_FIN_TIP, COL_FIN_TIP],       # Battle notch 2!
		[4.38, 1.12, 1.66, 0.072, COL_HIDE_ABYSSAL, COL_FIN_TIP, COL_FIN_TIP],
		[4.66, 1.40, 1.82, 0.036, COL_FIN_TIP, COL_FIN_TIP, COL_FIN_TIP],
	]
	_append_vertical_fin(st, stations, Vector3(0.0, 4.86, 1.86), COL_FIN_TIP)

	# Trailing free-tip rear notch lobe at dorsal fin base.
	var notch_stations: Array[Array] = [
		[1.56, 0.88, 1.72, 0.18, COL_HIDE_DORSAL, COL_HIDE_ABYSSAL, COL_FIN_TIP],
		[1.86, 1.02, 1.98, 0.09, COL_HIDE_ABYSSAL, COL_FIN_TIP, COL_FIN_TIP],
	]
	_append_vertical_fin(st, notch_stations, Vector3(0.0, 1.96, 2.22), COL_FIN_TIP)


static func _append_body_dorsal_spines(st: SurfaceTool) -> void:
	# Bony prehistoric osteoderm spine plates along the dorsal ridge fore & aft of the dorsal fin.
	var spine_specs: Array[Array] = [
		[-3.45, 0.42, 0.14, 0.34],
		[-2.60, 0.56, 0.17, 0.44],
		[-1.80, 0.68, 0.19, 0.52],
		[1.22, 0.50, 0.15, 0.40],
		[1.76, 0.44, 0.14, 0.36],
		[2.28, 0.38, 0.12, 0.32],
	]
	for sp in spine_specs:
		var zc: float = float(sp[0])
		var h: float = float(sp[1])
		var hw: float = float(sp[2])
		var hl: float = float(sp[3])
		var surf := _sample_body_surface(zc, 0.0)
		_append_osteoderm_spine(st, surf - Vector3(0.0, 0.12, 0.0), h, hw, hl)


static func _append_pectoral_fin(st: SurfaceTool, side_sign: float) -> void:
	# Massive muscular swept hydrofoil pectoral fin (~5.5 m per side) with trailing battle notch.
	# Format: [x_abs, y_ctr, z_lead, z_trail, thick_up, thick_dn, col_top, col_bot]
	var stations: Array[Array] = [
		[1.38, -0.58, -2.55, -0.25, 0.28, 0.22, COL_HIDE_DORSAL, COL_BELLY_ASH],
		[2.22, -0.74, -2.02, 0.06, 0.22, 0.16, COL_FIN_LEAD, COL_BELLY_ASH],
		[3.12, -0.96, -1.24, 0.52, 0.16, 0.11, COL_HIDE_DORSAL, COL_BELLY_ASH],
		[3.82, -1.16, -0.56, 0.44, 0.12, 0.08, COL_HIDE_ABYSSAL, COL_HIDE_FLANK],  # Battle nick!
		[4.56, -1.40, 0.12, 1.08, 0.09, 0.055, COL_HIDE_ABYSSAL, COL_HIDE_FLANK],
		[5.22, -1.62, 0.72, 1.38, 0.048, 0.032, COL_FIN_TIP, COL_FIN_TIP],
	]
	_append_lateral_fin(st, side_sign, stations, Vector3(side_sign * 5.62, -1.78, 1.50), COL_FIN_TIP)


static func _append_barnacle_coral_clusters(st: SurfaceTool) -> void:
	# Ancient barnacle volcano clusters & branching reef-coral nubs encrusted into hide.
	# Format: [z, ang_rad, radius, height, is_coral]
	var specs: Array[Array] = [
		[-2.20, 1.72, 0.17, 0.14, false],
		[-1.92, 1.84, 0.13, 0.11, false],
		[-1.68, 1.66, 0.11, 0.10, true],
		[-2.35, -1.76, 0.18, 0.15, false],
		[-2.02, -1.88, 0.14, 0.12, true],
		[-1.75, -1.62, 0.12, 0.10, false],
		[-4.25, 0.76, 0.14, 0.11, false],
		[-4.45, -0.82, 0.13, 0.10, false],
		[-1.12, 0.42, 0.16, 0.13, false],
		[-0.86, 0.54, 0.12, 0.11, true],
		[-1.02, -0.48, 0.15, 0.12, false],
		[-0.64, -0.36, 0.11, 0.09, false],
		[0.45, 0.58, 0.13, 0.10, false],
		[0.62, -0.64, 0.14, 0.11, true],
	]
	for sp in specs:
		var zc: float = float(sp[0])
		var ang: float = float(sp[1])
		var rad: float = float(sp[2])
		var h: float = float(sp[3])
		var is_coral: bool = bool(sp[4])
		var surf := _sample_body_surface(zc, ang)
		var out_n := Vector3(sin(ang), cos(ang), 0.0).normalized()
		if is_coral:
			_append_coral_cluster(st, surf - out_n * 0.05, out_n, rad, h)
		else:
			_append_barnacle_cone(st, surf - out_n * 0.05, out_n, rad, h)


static func _append_pelvic_fin(st: SurfaceTool, side_sign: float) -> void:
	var stations: Array[Array] = [
		[0.82, -0.78, 0.90, 2.08, 0.14, 0.11, COL_HIDE_FLANK, COL_BELLY_ASH],
		[1.56, -1.06, 1.38, 2.34, 0.095, 0.072, COL_HIDE_DORSAL, COL_BELLY_ASH],
		[2.16, -1.30, 1.86, 2.54, 0.048, 0.034, COL_FIN_TIP, COL_HIDE_FLANK],
	]
	_append_lateral_fin(st, side_sign, stations, Vector3(side_sign * 2.42, -1.42, 2.66), COL_FIN_TIP)


# ------------------------------------------------------------------ Mesh 2: Bioluminescent Battle Scars

static func _build_scar_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Glowing turquoise-cyan battle-scar gashes conformed flush across flanks, brow & dorsal fin!
	# Flank scars: [z_start, ang_start, z_end, ang_end, half_width, segs]
	var flank_scars: Array[Array] = [
		# Starboard massive harpoon & kraken gouges
		[-4.35, 0.88, -2.65, 1.24, 0.095, 5],
		[-3.65, 0.62, -1.55, 1.08, 0.115, 6],
		[-1.85, 0.56, 0.45, 1.22, 0.125, 6],
		[-0.40, 1.08, 1.65, 1.48, 0.090, 5],
		# Port jagged predator & cannon scars
		[-5.10, -0.74, -3.55, -1.16, 0.088, 5],
		[-3.15, -0.68, -0.85, -1.26, 0.120, 6],
		[-1.45, -0.52, 0.85, -1.06, 0.115, 6],
		[0.20, -1.18, 2.15, -1.52, 0.085, 5],
		# Dorsal shoulder glowing battle ridges flanking the spine
		[-3.55, 0.24, -1.50, 0.22, 0.075, 5],
		[-3.55, -0.24, -1.50, -0.22, 0.075, 5],
	]
	for sc in flank_scars:
		_append_body_scar_ribbon(st, float(sc[0]), float(sc[1]), float(sc[2]), float(sc[3]),
			float(sc[4]), int(sc[5]))

	# Glowing battle-scar fissures slashing across BOTH faces of the 2.8 m primary dorsal fin!
	for sg: float in [-1.0, 1.0]:
		_append_fin_scar_gash(st,
			Vector3(sg * 0.28, 2.15, -0.65),
			Vector3(sg * 0.14, 3.05, 0.78),
			Vector3(sg, 0.0, 0.0), 0.075, 4)
		_append_fin_scar_gash(st,
			Vector3(sg * 0.16, 3.20, 0.25),
			Vector3(sg * 0.08, 4.05, 1.26),
			Vector3(sg, 0.0, 0.0), 0.062, 4)

	st.generate_normals()
	return st.commit()


static func _append_body_scar_ribbon(st: SurfaceTool, z0: float, a0: float, z1: float, a1: float,
		half_w: float, segs: int) -> void:
	var left_pts: Array[Vector3] = []
	var core_pts: Array[Vector3] = []
	var right_pts: Array[Vector3] = []
	var refs: Array[Vector3] = []

	for i in range(segs + 1):
		var t := float(i) / float(segs)
		var z := lerpf(z0, z1, t)
		var jag := sin(t * PI * 3.0) * 0.055 * sin(t * PI)
		var ang := lerpf(a0, a1, t) + jag
		var surf := _sample_body_surface(z, ang)
		var out_n := Vector3(sin(ang), cos(ang), 0.0).normalized()
		var tang_a := Vector3(cos(ang), -sin(ang), 0.0).normalized()
		var end_k := sin(t * PI)
		var w := half_w * (0.28 + 0.72 * end_k)
		var lift := 0.032 + 0.046 * end_k

		core_pts.append(surf + out_n * lift)
		left_pts.append(surf + tang_a * w - out_n * 0.035)
		right_pts.append(surf - tang_a * w - out_n * 0.035)
		refs.append(surf - out_n * 0.45)

	for i in segs:
		var ref_c := (refs[i] + refs[i + 1]) * 0.5
		_add_outward_quad(st, left_pts[i], core_pts[i], core_pts[i + 1], left_pts[i + 1],
			ref_c, COL_SCAR_EDGE, COL_SCAR_CORE, COL_SCAR_CORE, COL_SCAR_EDGE)
		_add_outward_quad(st, core_pts[i], right_pts[i], right_pts[i + 1], core_pts[i + 1],
			ref_c, COL_SCAR_CORE, COL_SCAR_EDGE, COL_SCAR_EDGE, COL_SCAR_CORE)


static func _append_fin_scar_gash(st: SurfaceTool, p0: Vector3, p1: Vector3, out_n: Vector3,
		half_w: float, segs: int) -> void:
	var along := (p1 - p0).normalized()
	var across := out_n.cross(along).normalized()
	var left_pts: Array[Vector3] = []
	var core_pts: Array[Vector3] = []
	var right_pts: Array[Vector3] = []
	var refs: Array[Vector3] = []

	for i in range(segs + 1):
		var t := float(i) / float(segs)
		var pt := p0.lerp(p1, t) + across * (sin(t * PI * 2.0) * 0.04)
		var end_k := sin(t * PI)
		var w := half_w * (0.30 + 0.70 * end_k)
		core_pts.append(pt + out_n * (0.042 * end_k + 0.018))
		left_pts.append(pt + across * w - out_n * 0.04)
		right_pts.append(pt - across * w - out_n * 0.04)
		refs.append(pt - out_n * 0.30)

	for i in segs:
		var ref_c := (refs[i] + refs[i + 1]) * 0.5
		_add_outward_quad(st, left_pts[i], core_pts[i], core_pts[i + 1], left_pts[i + 1],
			ref_c, COL_SCAR_EDGE, COL_SCAR_CORE, COL_SCAR_CORE, COL_SCAR_EDGE)
		_add_outward_quad(st, core_pts[i], right_pts[i], right_pts[i + 1], core_pts[i + 1],
			ref_c, COL_SCAR_CORE, COL_SCAR_EDGE, COL_SCAR_EDGE, COL_SCAR_CORE)


# ------------------------------------------------------------------ Mesh 3: Glowing Amber-Gold Predator Eyes

static func _build_eyes_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	for sg: float in [-1.0, 1.0]:
		var center := Vector3(sg * 1.48, 0.72, -4.68)
		_append_predator_eye_dome(st, center, Vector3(0.18, 0.21, 0.25), sg)

	st.generate_normals()
	return st.commit()


static func _append_predator_eye_dome(st: SurfaceTool, center: Vector3, radii: Vector3,
		side_sign: float) -> void:
	const LON_SEGS := 12
	const LAT_RINGS := 5
	var rings: Array[Array] = []
	var ring_cols: Array[Array] = []
	for j in range(1, LAT_RINGS):
		var phi := (float(j) / float(LAT_RINGS)) * PI - PI * 0.5
		var cp := cos(phi)
		var sp := sin(phi)
		var ring: Array[Vector3] = []
		var rcol: Array[Color] = []
		for k in LON_SEGS:
			var th := (float(k) / float(LON_SEGS)) * TAU
			var lx := cos(th) * cp
			var lz := sin(th) * cp
			ring.append(center + Vector3(lx * radii.x, sp * radii.y, lz * radii.z))
			# Bright amber-gold iris facing outward with dark vertical predator slit pupil.
			var out_face := lx * side_sign
			var col := COL_EYE_AMBER
			if out_face > 0.72 and absf(lz) < 0.28:
				col = COL_EYE_PUPIL
			elif out_face > 0.45:
				col = COL_EYE_CORE
			rcol.append(col)
		rings.append(ring)
		ring_cols.append(rcol)

	var bot_pole := center + Vector3(0.0, -radii.y, 0.0)
	var top_pole := center + Vector3(0.0, radii.y, 0.0)
	var first_r: Array = rings[0]
	var first_c: Array = ring_cols[0]
	for k in LON_SEGS:
		var nk := (k + 1) % LON_SEGS
		_add_outward_tri(st, bot_pole, first_r[k], first_r[nk], center,
			COL_EYE_AMBER, first_c[k], first_c[nk])

	for j in range(rings.size() - 1):
		var r0: Array = rings[j]
		var r1: Array = rings[j + 1]
		var c0: Array = ring_cols[j]
		var c1: Array = ring_cols[j + 1]
		for k in LON_SEGS:
			var nk := (k + 1) % LON_SEGS
			_add_outward_quad(st, r0[k], r1[k], r1[nk], r0[nk], center,
				c0[k], c1[k], c1[nk], c0[nk])

	var last_r: Array = rings[rings.size() - 1]
	var last_c: Array = ring_cols[rings.size() - 1]
	for k in LON_SEGS:
		var nk := (k + 1) % LON_SEGS
		_add_outward_tri(st, top_pole, last_r[nk], last_r[k], center,
			COL_EYE_AMBER, last_c[nk], last_c[k])


# ------------------------------------------------------------------ Mesh 4: Colossal Hinged Lower Jaw

static func _build_jaw_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# 11-station horseshoe lower mandible arch (pivot origin = (0, -0.52, -3.95)).
	const ARCH_SEGS := 11
	var arch_pts: Array[Vector3] = []
	var arch_rings: Array[Array] = []
	var arch_cols: Array[Array] = []
	var inner_top_pts: Array[Vector3] = []
	var inner_bot_pts: Array[Vector3] = []

	for i in ARCH_SEGS:
		var u := (float(i) / float(ARCH_SEGS - 1)) * 2.0 - 1.0
		var ang := u * PI * 0.52
		var ax := 1.12 * sin(ang)
		var az := -1.86 * cos(ang) + 0.30
		var ay := lerpf(0.09, -0.05, u * u)
		var pt := Vector3(ax, ay, az)
		arch_pts.append(pt)

		var out_xz := Vector3(sin(ang), 0.0, -cos(ang)).normalized()
		var thick_out := lerpf(0.24, 0.30, u * u)
		var thick_in := lerpf(0.20, 0.24, u * u)
		var h_up := lerpf(0.22, 0.18, u * u)
		var h_dn := lerpf(0.30, 0.36, u * u)

		# 8-vertex armored mandibular bone cross-section: pale bone chin outside, crimson gums inside.
		var p0 := pt + Vector3(0.0, h_up, 0.0) + out_xz * (thick_out * 0.20)
		var p1 := pt + Vector3(0.0, h_up * 0.65, 0.0) + out_xz * (thick_out * 0.85)
		var p2 := pt + Vector3(0.0, -h_dn * 0.12, 0.0) + out_xz * thick_out
		var p3 := pt + Vector3(0.0, -h_dn * 0.72, 0.0) + out_xz * (thick_out * 0.72)
		var p4 := pt + Vector3(0.0, -h_dn, 0.0) - out_xz * (thick_in * 0.15)
		var p5 := pt + Vector3(0.0, -h_dn * 0.55, 0.0) - out_xz * (thick_in * 0.82)
		var p6 := pt + Vector3(0.0, 0.0, 0.0) - out_xz * thick_in
		var p7 := pt + Vector3(0.0, h_up * 0.68, 0.0) - out_xz * (thick_in * 0.86)

		arch_rings.append([p0, p1, p2, p3, p4, p5, p6, p7])
		var corner_col := COL_BELLY_ASH.lerp(COL_HIDE_FLANK, clampf((absf(u) - 0.60) / 0.40, 0.0, 0.60))
		arch_cols.append([
			COL_MOUTH_CRIMSON,
			corner_col,
			COL_BELLY_ASH,
			COL_BELLY_ASH,
			COL_BELLY_PALE,
			COL_MOUTH_DEEP,
			COL_MOUTH_DEEP,
			COL_MOUTH_CRIMSON,
		])
		inner_top_pts.append(p7)
		inner_bot_pts.append(p4)

	for i in range(ARCH_SEGS - 1):
		var r0: Array = arch_rings[i]
		var r1: Array = arch_rings[i + 1]
		var c0: Array = arch_cols[i]
		var c1: Array = arch_cols[i + 1]
		var seg_ctr := (arch_pts[i] + arch_pts[i + 1]) * 0.5
		for k in 8:
			var nk := (k + 1) % 8
			_add_outward_quad(st, r0[k], r1[k], r1[nk], r0[nk], seg_ctr,
				c0[k], c1[k], c1[nk], c0[nk])

	# Cap left & right hinge ends cleanly inside cheek pocket.
	for end_idx: int in [0, ARCH_SEGS - 1]:
		var er: Array = arch_rings[end_idx]
		var ec: Array = arch_cols[end_idx]
		var cap_pt := arch_pts[end_idx] + Vector3(0.0, 0.0, 0.22)
		var cap_ref := arch_pts[end_idx] + Vector3(0.0, 0.0, -0.25)
		for k in 8:
			var nk := (k + 1) % 8
			_add_outward_tri(st, cap_pt, er[k], er[nk], cap_ref, COL_MOUTH_DEEP, ec[k], ec[nk])

	# Solid crimson oral gullet, muscular tongue & armored pale underside chin floor.
	var tongue_spine: Array[Vector3] = [
		Vector3(0.0, 0.06, -1.28),
		Vector3(0.0, 0.14, -0.78),
		Vector3(0.0, 0.12, -0.22),
		Vector3(0.0, 0.02, 0.36),
	]
	var chin_spine: Array[Vector3] = [
		Vector3(0.0, -0.34, -1.24),
		Vector3(0.0, -0.38, -0.74),
		Vector3(0.0, -0.36, -0.20),
		Vector3(0.0, -0.34, 0.36),
	]
	var ref_below := Vector3(0.0, -1.2, -0.45)
	var ref_above := Vector3(0.0, 1.0, -0.45)

	# Fan inner mandible vertices symmetrically to tongue spine (top) and chin spine (bottom).
	var mid_idx := 5
	_add_outward_tri(st, inner_top_pts[mid_idx], inner_top_pts[mid_idx - 1], tongue_spine[0], ref_below,
		COL_MOUTH_CRIMSON, COL_MOUTH_CRIMSON, COL_MOUTH_CRIMSON)
	_add_outward_tri(st, inner_top_pts[mid_idx], tongue_spine[0], inner_top_pts[mid_idx + 1], ref_below,
		COL_MOUTH_CRIMSON, COL_MOUTH_CRIMSON, COL_MOUTH_CRIMSON)
	_add_outward_tri(st, inner_bot_pts[mid_idx], inner_bot_pts[mid_idx - 1], chin_spine[0], ref_above,
		COL_BELLY_PALE, COL_BELLY_ASH, COL_BELLY_PALE)
	_add_outward_tri(st, inner_bot_pts[mid_idx], chin_spine[0], inner_bot_pts[mid_idx + 1], ref_above,
		COL_BELLY_PALE, COL_BELLY_PALE, COL_BELLY_ASH)

	var left_map: Array[int] = [4, 3, 1, 0]
	var right_map: Array[int] = [6, 7, 9, 10]
	for si in range(3):
		var c_in := COL_MOUTH_CRIMSON if si == 0 else COL_MOUTH_DEEP
		_add_outward_quad(st, inner_top_pts[left_map[si]], inner_top_pts[left_map[si + 1]],
			tongue_spine[si + 1], tongue_spine[si], ref_below, c_in, COL_MOUTH_DEEP, c_in, COL_MOUTH_CRIMSON)
		_add_outward_quad(st, tongue_spine[si], tongue_spine[si + 1],
			inner_top_pts[right_map[si + 1]], inner_top_pts[right_map[si]], ref_below,
			COL_MOUTH_CRIMSON, c_in, COL_MOUTH_DEEP, c_in)
		_add_outward_quad(st, inner_bot_pts[left_map[si]], inner_bot_pts[left_map[si + 1]],
			chin_spine[si + 1], chin_spine[si], ref_above,
			COL_BELLY_ASH, COL_BELLY_ASH, COL_BELLY_PALE, COL_BELLY_PALE)
		_add_outward_quad(st, chin_spine[si], chin_spine[si + 1],
			inner_bot_pts[right_map[si + 1]], inner_bot_pts[right_map[si]], ref_above,
			COL_BELLY_PALE, COL_BELLY_PALE, COL_BELLY_ASH, COL_BELLY_ASH)
	# Connect skipped indices 2 and 8 cleanly to avoid any edge crease.
	_add_outward_tri(st, inner_top_pts[3], inner_top_pts[2], inner_top_pts[1], ref_below,
		COL_MOUTH_DEEP, COL_MOUTH_DEEP, COL_MOUTH_DEEP)
	_add_outward_tri(st, inner_top_pts[7], inner_top_pts[8], inner_top_pts[9], ref_below,
		COL_MOUTH_DEEP, COL_MOUTH_DEEP, COL_MOUTH_DEEP)
	_add_outward_tri(st, inner_bot_pts[3], inner_bot_pts[2], inner_bot_pts[1], ref_above,
		COL_BELLY_ASH, COL_BELLY_ASH, COL_BELLY_ASH)
	_add_outward_tri(st, inner_bot_pts[7], inner_bot_pts[8], inner_bot_pts[9], ref_above,
		COL_BELLY_ASH, COL_BELLY_ASH, COL_BELLY_ASH)

	# Rear crimson gullet bulkhead closing the hinge throat solidly.
	var ref_front := Vector3(0.0, -0.10, -1.40)
	_add_outward_quad(st, inner_top_pts[0], tongue_spine[3], chin_spine[3], inner_bot_pts[0],
		ref_front, COL_MOUTH_DEEP, COL_MOUTH_DEEP, COL_BELLY_ASH, COL_BELLY_ASH)
	_add_outward_quad(st, tongue_spine[3], inner_top_pts[10], inner_bot_pts[10], chin_spine[3],
		ref_front, COL_MOUTH_DEEP, COL_MOUTH_DEEP, COL_BELLY_ASH, COL_BELLY_ASH)

	# Triple rows of massive serrated triangular ivory lower teeth!
	var row_specs: Array[Array] = [
		[13, 1.08, -1.82, 0.30, 0.25, 0.36, 0.115, 0.044, true],   # Outer colossal serrated row
		[11, 0.96, -1.66, 0.30, 0.22, 0.27, 0.090, 0.034, false],  # Middle replacement row
		[9,  0.84, -1.50, 0.30, 0.18, 0.20, 0.072, 0.026, false],  # Inner recurved fang row
	]
	for spec in row_specs:
		var count: int = int(spec[0])
		var rad_x: float = float(spec[1])
		var z_amp: float = float(spec[2])
		var z_off: float = float(spec[3])
		var y_base: float = float(spec[4])
		var t_len: float = float(spec[5])
		var t_w: float = float(spec[6])
		var t_t: float = float(spec[7])
		var serrated: bool = bool(spec[8])
		for i in count:
			var u := (float(i) / float(count - 1)) * 2.0 - 1.0
			var ang := u * PI * 0.45
			var tx := rad_x * sin(ang)
			var tz := z_amp * cos(ang) + z_off
			var ty := lerpf(y_base, y_base - 0.14, u * u)
			var base := Vector3(tx, ty, tz)
			var tang := Vector3(cos(ang), 0.0, sin(ang) * 0.85).normalized()
			var inward := Vector3(-sin(ang), 0.0, cos(ang)).normalized()
			var size_k := lerpf(0.96, 0.62, absf(u))
			var tip := base + Vector3(0.0, t_len * size_k, 0.0) + inward * (t_len * 0.26 * size_k)
			if serrated:
				_append_serrated_tooth(st, base, tip, tang, inward, t_w * size_k, t_t * size_k)
			else:
				_append_blade_tooth(st, base, tip, tang, inward, t_w * size_k, t_t * size_k)

	st.generate_normals()
	return st.commit()


# ------------------------------------------------------------------ Mesh 5: Mid-Tail Peduncle & Tail Scars

static func _build_tail_mid_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Format: [z, yc, rx, ry_top, ry_bot, lateral_keel]
	var stations: Array[Array] = [
		[-0.55, 0.00, 1.05, 1.04, 0.84, 0.00],
		[0.10, 0.01, 0.96, 0.95, 0.78, 0.00],
		[0.80, 0.01, 0.78, 0.80, 0.64, 0.06],
		[1.55, 0.00, 0.60, 0.66, 0.52, 0.16],
		[2.25, 0.00, 0.46, 0.54, 0.43, 0.22],
		[2.85, 0.00, 0.38, 0.46, 0.37, 0.14],
		[3.12, 0.00, 0.32, 0.39, 0.32, 0.08],
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

			var col := COL_BELLY_ASH
			if ny >= 0.70:
				col = COL_HIDE_ABYSSAL
			elif ny >= 0.12:
				col = COL_HIDE_DORSAL
			elif ny >= -0.18:
				col = COL_HIDE_FLANK
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

	# Front & rear socket caps for seamless wide-angle S-wave swimming.
	var first_r: Array = rings[0]
	var first_c: Array = ring_cols[0]
	for k in TAIL_MID_RADIAL_SEGS:
		var nk := (k + 1) % TAIL_MID_RADIAL_SEGS
		_add_outward_tri(st, Vector3(0.0, 0.0, -0.82), first_r[k], first_r[nk],
			Vector3(0.0, 0.0, -0.15), COL_HIDE_FLANK, first_c[k], first_c[nk])

	var last_r: Array = rings[rings.size() - 1]
	var last_c: Array = ring_cols[ring_cols.size() - 1]
	for k in TAIL_MID_RADIAL_SEGS:
		var nk := (k + 1) % TAIL_MID_RADIAL_SEGS
		_add_outward_tri(st, Vector3(0.0, 0.0, 3.34), last_r[nk], last_r[k],
			Vector3(0.0, 0.0, 2.65), COL_HIDE_FLANK, last_c[nk], last_c[k])

	# Sculpted second dorsal fin riding atop the muscular peduncle.
	var second_dorsal: Array[Array] = [
		[0.52, 0.72, 2.05, 0.18, COL_HIDE_DORSAL, COL_HIDE_DORSAL, COL_HIDE_ABYSSAL],
		[1.08, 1.24, 2.15, 0.11, COL_FIN_LEAD, COL_HIDE_DORSAL, COL_FIN_TIP],
		[1.56, 1.78, 2.40, 0.048, COL_HIDE_ABYSSAL, COL_FIN_TIP, COL_FIN_TIP],
	]
	_append_vertical_fin(st, second_dorsal, Vector3(0.0, 1.78, 2.52), COL_FIN_TIP)

	# Sculpted ventral anal fin beneath the peduncle.
	var anal_fin: Array[Array] = [
		[-0.42, 1.05, 2.24, 0.15, COL_BELLY_ASH, COL_HIDE_FLANK, COL_HIDE_DORSAL],
		[-0.90, 1.48, 2.32, 0.09, COL_HIDE_FLANK, COL_HIDE_DORSAL, COL_FIN_TIP],
		[-1.32, 1.96, 2.54, 0.044, COL_HIDE_ABYSSAL, COL_FIN_TIP, COL_FIN_TIP],
	]
	_append_vertical_fin(st, anal_fin, Vector3(0.0, -1.50, 2.66), COL_FIN_TIP)

	# Posterior osteoderm spines along the caudal ridge.
	_append_osteoderm_spine(st, Vector3(0.0, 0.84, 0.25), 0.34, 0.11, 0.28)
	_append_osteoderm_spine(st, Vector3(0.0, 0.48, 2.32), 0.26, 0.085, 0.22)

	st.generate_normals()
	return st.commit()


static func _build_tail_scar_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Diagonal bioluminescent battle-scar gashes along both sides of the caudal peduncle.
	for sg: float in [-1.0, 1.0]:
		var p0 := Vector3(sg * 0.88, 0.24, 0.20)
		var p1 := Vector3(sg * 0.56, -0.04, 1.95)
		_append_fin_scar_gash(st, p0, p1, Vector3(sg, 0.18, 0.0).normalized(), 0.075, 4)

	st.generate_normals()
	return st.commit()


# ------------------------------------------------------------------ Mesh 6: Colossal Crescent Caudal Fluke

static func _build_tail_fin_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# 1. Peduncle overlap hub seated cleanly inside TailMidPivot's aft socket.
	const HUB_SEGS := 12
	var hub_stations: Array[Array] = [
		[-0.38, 0.0, 0.40, 0.48, 0.39],
		[0.14, 0.0, 0.34, 0.45, 0.36],
		[0.72, 0.0, 0.22, 0.52, 0.42],
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
			cols.append(COL_HIDE_DORSAL if ny >= 0.0 else (COL_HIDE_FLANK if ny >= -0.35 else COL_BELLY_ASH))
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
		_add_outward_tri(st, Vector3(0.0, 0.0, -0.56), h_first[k], h_first[nk],
			Vector3(0.0, 0.0, -0.10), COL_HIDE_FLANK, h_first_c[k], h_first_c[nk])

	var h_last: Array = h_rings[h_rings.size() - 1]
	var h_last_c: Array = h_cols[h_rings.size() - 1]
	for k in HUB_SEGS:
		var nk := (k + 1) % HUB_SEGS
		_add_outward_tri(st, Vector3(0.0, 0.0, 1.24), h_last[nk], h_last[k],
			Vector3(0.0, 0.0, 0.42), COL_HIDE_DORSAL, h_last_c[nk], h_last_c[k])

	# 2. Colossal crescent upper heterocercal caudal lobe (with battle nick & subterminal notch!).
	var upper_lobe: Array[Array] = [
		[-0.06, 0.00, 1.42, 0.28, COL_HIDE_DORSAL, COL_HIDE_DORSAL, COL_HIDE_ABYSSAL],
		[0.72, 0.56, 1.66, 0.22, COL_FIN_LEAD, COL_HIDE_DORSAL, COL_FIN_TIP],
		[1.48, 1.28, 2.08, 0.16, COL_FIN_LEAD, COL_HIDE_DORSAL, COL_FIN_TIP],
		[1.92, 1.72, 2.02, 0.13, COL_HIDE_DORSAL, COL_HIDE_ABYSSAL, COL_FIN_TIP],  # Battle nick
		[2.45, 2.26, 2.86, 0.10, COL_HIDE_DORSAL, COL_HIDE_ABYSSAL, COL_FIN_TIP],
		[2.82, 2.66, 2.94, 0.075, COL_HIDE_ABYSSAL, COL_FIN_TIP, COL_FIN_TIP],    # Subterminal notch
		[3.28, 3.16, 3.48, 0.045, COL_HIDE_ABYSSAL, COL_FIN_TIP, COL_FIN_TIP],
	]
	_append_vertical_fin(st, upper_lobe, Vector3(0.0, 3.58, 3.65), COL_FIN_TIP)

	# 3. Powerful swept lower heterocercal caudal lobe.
	var lower_lobe: Array[Array] = [
		[0.06, 0.00, 1.42, 0.26, COL_BELLY_ASH, COL_HIDE_FLANK, COL_HIDE_DORSAL],
		[-0.64, 0.52, 1.54, 0.19, COL_BELLY_ASH, COL_HIDE_DORSAL, COL_FIN_TIP],
		[-1.32, 1.18, 1.88, 0.125, COL_HIDE_FLANK, COL_HIDE_ABYSSAL, COL_FIN_TIP],
		[-1.92, 1.78, 2.26, 0.072, COL_HIDE_ABYSSAL, COL_FIN_TIP, COL_FIN_TIP],
		[-2.24, 2.12, 2.46, 0.042, COL_FIN_TIP, COL_FIN_TIP, COL_FIN_TIP],
	]
	_append_vertical_fin(st, lower_lobe, Vector3(0.0, -2.48, 2.62), COL_FIN_TIP)

	st.generate_normals()
	return st.commit()


# ------------------------------------------------------------------ Zero-Primitive VFX Meshes

static func _build_splash_drop_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	const SEGS := 6
	var top := Vector3(0.0, 0.62, 0.0)
	var bot := Vector3(0.0, -0.48, 0.0)
	var ring: Array[Vector3] = []
	for i in SEGS:
		var a := float(i) / float(SEGS) * TAU
		var r := 0.44 + 0.08 * sin(float(i) * 2.1)
		ring.append(Vector3(cos(a) * r, sin(float(i) * 1.7) * 0.08, sin(a) * r))
	var col_top := Color(0.92, 0.99, 1.0, 0.92)
	var col_mid := Color(0.68, 0.94, 0.96, 0.84)
	var col_bot := Color(0.42, 0.82, 0.88, 0.72)
	for i in SEGS:
		var ni := (i + 1) % SEGS
		_add_outward_tri(st, top, ring[i], ring[ni], Vector3.ZERO, col_top, col_mid, col_mid)
		_add_outward_tri(st, bot, ring[ni], ring[i], Vector3.ZERO, col_bot, col_mid, col_mid)
	st.generate_normals()
	return st.commit()


static func _build_foam_ring_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	const SEGS := 16
	var inner_bot: Array[Vector3] = []
	var crest_ring: Array[Vector3] = []
	var outer_bot: Array[Vector3] = []
	for i in SEGS:
		var a := float(i) / float(SEGS) * TAU
		var jag := 1.0 + 0.24 * sin(float(i) * 3.0)
		var ca := cos(a)
		var sa := sin(a)
		inner_bot.append(Vector3(ca * 1.6, 0.0, sa * 1.6))
		crest_ring.append(Vector3(ca * (2.6 * jag), 1.85 * jag, sa * (2.6 * jag)))
		outer_bot.append(Vector3(ca * (3.8 * jag), 0.05, sa * (3.8 * jag)))
	var c_base := Color(0.76, 0.95, 0.98, 0.86)
	var c_crest := Color(0.96, 1.0, 1.0, 0.94)
	var c_outer := Color(0.64, 0.90, 0.94, 0.45)
	for i in SEGS:
		var ni := (i + 1) % SEGS
		var ref_in := Vector3(0.0, 0.2, 0.0)
		_add_outward_quad(st, inner_bot[i], crest_ring[i], crest_ring[ni], inner_bot[ni],
			ref_in, c_base, c_crest, c_crest, c_base)
		_add_outward_quad(st, crest_ring[i], outer_bot[i], outer_bot[ni], crest_ring[ni],
			ref_in, c_crest, c_outer, c_outer, c_crest)
	st.generate_normals()
	return st.commit()


# ------------------------------------------------------------------ Reusable 3D Sculpture Helpers

static func _append_vertical_fin(st: SurfaceTool, stations: Array[Array],
		tip_apex: Vector3, tip_col: Color) -> void:
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
		var rcol: Array[Color] = [
			c_lead, c_mid, c_mid.lerp(c_trail, 0.5),
			c_trail, c_mid.lerp(c_trail, 0.5), c_mid,
		]
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

	var last_i := rings.size() - 1
	var top_r: Array = rings[last_i]
	var top_c: Array = cols[last_i]
	var ref_in := centers[last_i] + (centers[last_i] - tip_apex).normalized() * 0.32
	for k in 6:
		var nk := (k + 1) % 6
		_add_outward_tri(st, tip_apex, top_r[k], top_r[nk], ref_in, tip_col, top_c[k], top_c[nk])


static func _append_lateral_fin(st: SurfaceTool, side_sign: float, stations: Array[Array],
		tip_apex: Vector3, tip_col: Color) -> void:
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
	var ref_in := centers[last_i] + (centers[last_i] - tip_apex).normalized() * 0.32
	for k in 6:
		var nk := (k + 1) % 6
		_add_outward_tri(st, tip_apex, end_r[k], end_r[nk], ref_in, tip_col, end_c[k], end_c[nk])


static func _append_serrated_tooth(st: SurfaceTool, base: Vector3, tip: Vector3,
		tang: Vector3, inward: Vector3, half_w: float, half_t: float) -> void:
	# Colossal 2-tier serrated triangular megalodon blade (12 tris per tooth).
	var mid := base.lerp(tip, 0.48)
	var b_ring: Array[Vector3] = [
		base + tang * half_w,
		base + inward * half_t,
		base - tang * half_w,
		base - inward * half_t,
	]
	var m_ring: Array[Vector3] = [
		mid + tang * (half_w * 0.58),
		mid + inward * (half_t * 0.62),
		mid - tang * (half_w * 0.58),
		mid - inward * (half_t * 0.62),
	]
	var ctr_lo := base.lerp(mid, 0.5)
	var ctr_hi := mid.lerp(tip, 0.32)
	for k in 4:
		var nk := (k + 1) % 4
		_add_outward_quad(st, b_ring[k], m_ring[k], m_ring[nk], b_ring[nk], ctr_lo,
			COL_TOOTH_ROOT, COL_TOOTH_IVORY, COL_TOOTH_IVORY, COL_TOOTH_ROOT)
		_add_outward_tri(st, tip, m_ring[k], m_ring[nk], ctr_hi,
			COL_TOOTH_IVORY, COL_TOOTH_IVORY, COL_TOOTH_IVORY)


static func _append_blade_tooth(st: SurfaceTool, base: Vector3, tip: Vector3,
		tang: Vector3, inward: Vector3, half_w: float, half_t: float) -> void:
	var p0 := base + tang * half_w
	var p1 := base + inward * half_t
	var p2 := base - tang * half_w
	var p3 := base - inward * half_t
	var ctr := base.lerp(tip, 0.28)
	_add_outward_tri(st, tip, p0, p1, ctr, COL_TOOTH_IVORY, COL_TOOTH_ROOT, COL_TOOTH_ROOT)
	_add_outward_tri(st, tip, p1, p2, ctr, COL_TOOTH_IVORY, COL_TOOTH_ROOT, COL_TOOTH_ROOT)
	_add_outward_tri(st, tip, p2, p3, ctr, COL_TOOTH_IVORY, COL_TOOTH_ROOT, COL_TOOTH_ROOT)
	_add_outward_tri(st, tip, p3, p0, ctr, COL_TOOTH_IVORY, COL_TOOTH_ROOT, COL_TOOTH_ROOT)


static func _append_osteoderm_spine(st: SurfaceTool, base: Vector3, height: float,
		half_w: float, half_len: float) -> void:
	# Swept-back bony dorsal ridge plate rooted into the spine (8 tris).
	var p_fwd := base + Vector3(0.0, 0.0, -half_len)
	var p_r := base + Vector3(half_w, 0.0, 0.0)
	var p_aft := base + Vector3(0.0, 0.0, half_len)
	var p_l := base + Vector3(-half_w, 0.0, 0.0)
	var tip := base + Vector3(0.0, height, half_len * 0.72)
	var ctr := base + Vector3(0.0, height * 0.28, half_len * 0.15)
	_add_outward_tri(st, tip, p_fwd, p_r, ctr, COL_BONE_SPINE, COL_HIDE_ABYSSAL, COL_HIDE_DORSAL)
	_add_outward_tri(st, tip, p_r, p_aft, ctr, COL_BONE_SPINE, COL_HIDE_DORSAL, COL_HIDE_ABYSSAL)
	_add_outward_tri(st, tip, p_aft, p_l, ctr, COL_BONE_SPINE, COL_HIDE_ABYSSAL, COL_HIDE_DORSAL)
	_add_outward_tri(st, tip, p_l, p_fwd, ctr, COL_BONE_SPINE, COL_HIDE_DORSAL, COL_HIDE_ABYSSAL)


static func _append_barnacle_cone(st: SurfaceTool, base: Vector3, out_n: Vector3,
		radius: float, height: float) -> void:
	# Sculpted 6-sided crusty barnacle volcano cone with dark recessed aperture (18 tris).
	var ref_u := Vector3.UP if absf(out_n.y) < 0.85 else Vector3.FORWARD
	var tang_a := out_n.cross(ref_u).normalized()
	var tang_b := out_n.cross(tang_a).normalized()
	const SEGS := 6
	var bot_r: Array[Vector3] = []
	var top_r: Array[Vector3] = []
	for k in SEGS:
		var a := float(k) / float(SEGS) * TAU
		var dir := tang_a * cos(a) + tang_b * sin(a)
		bot_r.append(base + dir * radius)
		top_r.append(base + out_n * height + dir * (radius * 0.44))
	var pit := base + out_n * (height * 0.72)
	var ctr := base + out_n * (height * 0.38)
	var pit_ref := base - out_n * 0.15
	for k in SEGS:
		var nk := (k + 1) % SEGS
		_add_outward_quad(st, bot_r[k], top_r[k], top_r[nk], bot_r[nk], ctr,
			COL_BARNACLE_DARK, COL_BARNACLE_SHELL, COL_BARNACLE_SHELL, COL_BARNACLE_DARK)
		_add_outward_tri(st, pit, top_r[k], top_r[nk], pit_ref,
			COL_BARNACLE_DARK, COL_BARNACLE_SHELL, COL_BARNACLE_SHELL)


static func _append_coral_cluster(st: SurfaceTool, base: Vector3, out_n: Vector3,
		radius: float, height: float) -> void:
	# Three-prong encrusted reef-coral nodule (12 tris).
	var ref_u := Vector3.UP if absf(out_n.y) < 0.85 else Vector3.FORWARD
	var tang_a := out_n.cross(ref_u).normalized()
	var tang_b := out_n.cross(tang_a).normalized()
	var prongs: Array[Vector3] = [
		(out_n + tang_a * 0.35).normalized() * (height * 1.35),
		(out_n - tang_a * 0.28 + tang_b * 0.32).normalized() * (height * 1.15),
		(out_n - tang_b * 0.36).normalized() * (height * 0.95),
	]
	for p_off: Vector3 in prongs:
		var tip := base + p_off
		var r := radius * 0.52
		var b0 := base + tang_a * r
		var b1 := base + tang_b * r
		var b2 := base - tang_a * r
		var b3 := base - tang_b * r
		var ctr := base + p_off * 0.30
		_add_outward_tri(st, tip, b0, b1, ctr, COL_CORAL_PINK, COL_BARNACLE_SHELL, COL_BARNACLE_SHELL)
		_add_outward_tri(st, tip, b1, b2, ctr, COL_CORAL_PINK, COL_BARNACLE_SHELL, COL_BARNACLE_SHELL)
		_add_outward_tri(st, tip, b2, b3, ctr, COL_CORAL_PINK, COL_BARNACLE_SHELL, COL_BARNACLE_SHELL)
		_add_outward_tri(st, tip, b3, b0, ctr, COL_CORAL_PINK, COL_BARNACLE_SHELL, COL_BARNACLE_SHELL)


static func _add_outward_quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3,
		ref_center: Vector3, ca: Color, cb: Color, cc: Color, cd: Color) -> void:
	_add_outward_tri(st, a, b, c, ref_center, ca, cb, cc)
	_add_outward_tri(st, a, c, d, ref_center, ca, cc, cd)


static func _add_outward_tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3,
		ref_center: Vector3, ca: Color, cb: Color, cc: Color) -> void:
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
