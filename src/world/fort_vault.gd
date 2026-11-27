class_name FortVault
extends Node3D
## Sculpted Ironwatch Fort Treasury Vault Gate: a flat-faceted coral-limestone
## arched stone lintel frame fitted with hinged wrought-iron barred double gates,
## riveted cross-straps, spearhead finials, an ornate brass lockplate & padlock,
## a warm golden treasury OmniLight3D spilling through the bars, and a solid
## StaticBody3D blocker that disables cleanly as the gates swing open ±108°.

signal vault_opened(vault: FortVault, opener: Node)

const GROUP := &"fort_vaults"
const OPEN_DURATION := 1.35
const OPEN_ANGLE_RAD := deg_to_rad(108.0)
const GATE_HALF_SPAN := 1.52

const HALO_POS := Vector3(0.0, 1.55, -0.75)
const HALO_ENERGY_LOCKED := 0.65
const HALO_ENERGY_OPEN := 1.35
const HALO_SCALE_LOCKED := 1.0
const HALO_SCALE_OPEN := 1.42
const HALO_VISIBILITY_RANGE := 95.0

const GOLD_MOTE_COUNT := 16
const MOTE_Y_MIN := 0.25
const MOTE_Y_MAX := 2.85
const MOTE_ACTIVE_DIST := 55.0
const MOTE_VISIBILITY_RANGE := 70.0

# Warm buff coral-limestone, dark soot-black wrought iron, and gleaming pirate-brass palette (sRGB).
const COL_STONE_LIGHT := Color(0.80, 0.70, 0.52)
const COL_STONE_MID := Color(0.66, 0.56, 0.40)
const COL_STONE_SHADOW := Color(0.43, 0.36, 0.26)
const COL_STONE_MOSS := Color(0.40, 0.44, 0.26)

const COL_IRON_HI := Color(0.20, 0.19, 0.21)
const COL_IRON_MID := Color(0.11, 0.11, 0.13)
const COL_IRON_DARK := Color(0.065, 0.062, 0.072)
const COL_RIVET := Color(0.22, 0.21, 0.23)

const COL_BRASS_HI := Color(0.98, 0.78, 0.26)
const COL_BRASS_MID := Color(0.82, 0.60, 0.16)
const COL_BRASS_DARK := Color(0.50, 0.34, 0.09)

const COL_HALO_CORE := Color(1.0, 0.88, 0.36, 1.0)
const COL_HALO_MID := Color(0.62, 0.40, 0.08, 1.0)
const COL_HALO_RIM := Color(0.0, 0.0, 0.0, 1.0)

const COL_MOTE_TOP := Color(1.0, 0.96, 0.72, 1.0)
const COL_MOTE_MID := Color(1.0, 0.80, 0.24, 1.0)
const COL_MOTE_BOT := Color(0.86, 0.56, 0.10, 1.0)

static var _active_vaults: int = 0
static var _frame_mesh: ArrayMesh = null
static var _gate_left_mesh: ArrayMesh = null
static var _gate_right_mesh: ArrayMesh = null
static var _halo_mesh: ArrayMesh = null
static var _gold_mote_mesh: ArrayMesh = null
static var _stone_mat: StandardMaterial3D = null
static var _iron_mat: StandardMaterial3D = null
static var _brass_mat: StandardMaterial3D = null
static var _mote_mat: StandardMaterial3D = null

var is_open: bool = false
var is_locked: bool = true
var interactable: Interactable = null

var left_gate_pivot: Node3D = null
var right_gate_pivot: Node3D = null
var treasury_light: OmniLight3D = null

var _frame_mi: MeshInstance3D = null
var _left_gate_mi: MeshInstance3D = null
var _right_gate_mi: MeshInstance3D = null
var _halo_mi: MeshInstance3D = null
var _halo_mat: StandardMaterial3D = null
var _gold_motes_mmi: MultiMeshInstance3D = null
var _blocker_body: StaticBody3D = null
var _blocker_shape: CollisionShape3D = null

var _open_elapsed: float = 0.0
var _open_anim_active: bool = false
var _glow_clock: float = 0.0
var _treasury_halo_energy: float = HALO_ENERGY_LOCKED

# Pre-allocated fixed-size buffers for VaultGoldMotes (zero steady-state heap allocations).
var _mote_age: PackedFloat32Array = PackedFloat32Array()
var _mote_speed: PackedFloat32Array = PackedFloat32Array()
var _mote_base_x: PackedFloat32Array = PackedFloat32Array()
var _mote_base_z: PackedFloat32Array = PackedFloat32Array()
var _mote_phase: PackedFloat32Array = PackedFloat32Array()
var _mote_swirl_r: PackedFloat32Array = PackedFloat32Array()
var _mote_scale: PackedFloat32Array = PackedFloat32Array()
var _mote_positions: PackedVector3Array = PackedVector3Array()


static func clear_shared_cache() -> void:
	_frame_mesh = null
	_gate_left_mesh = null
	_gate_right_mesh = null
	_halo_mesh = null
	_gold_mote_mesh = null
	_stone_mat = null
	_iron_mat = null
	_brass_mat = null
	_mote_mat = null


func _enter_tree() -> void:
	_active_vaults += 1
	add_to_group(GROUP)


func _exit_tree() -> void:
	for mi: MeshInstance3D in [_frame_mi, _left_gate_mi, _right_gate_mi, _halo_mi]:
		if mi != null and is_instance_valid(mi):
			if mi.mesh != null:
				for si in mi.mesh.get_surface_count():
					mi.set_surface_override_material(si, null)
			mi.mesh = null
			mi.material_override = null
	_frame_mi = null
	_left_gate_mi = null
	_right_gate_mi = null
	_halo_mi = null
	_halo_mat = null
	if _gold_motes_mmi != null and is_instance_valid(_gold_motes_mmi):
		_gold_motes_mmi.visible = false
		_gold_motes_mmi.material_override = null
		_gold_motes_mmi.multimesh = null
	_gold_motes_mmi = null
	_active_vaults = maxi(0, _active_vaults - 1)
	if _active_vaults == 0:
		clear_shared_cache()


func _ready() -> void:
	_ensure_shared_assets()
	_build_structure()
	_build_treasury_vfx()
	_build_blocker()
	_build_interactable()
	_apply_gate_angles(0.0)
	_update_treasury_vfx(0.0)


# ==============================================================================
# Public API
# ==============================================================================

## Unlock or re-lock the vault interactable prompt when fort batteries are cleared.
func set_siege_cleared(cleared: bool) -> void:
	if is_open:
		return
	is_locked = not cleared
	if interactable != null:
		interactable.prompt = "Open Ironwatch Fort Vault" if cleared else "Unlock Ironwatch Fort Vault"


## Host-authoritative unlock & smooth 1.35 s inward double-gate swing (±108°).
func open_vault(opener: Node = null) -> bool:
	if not Net.is_host() or is_open:
		return false
	is_locked = false
	is_open = true
	_open_elapsed = 0.0
	_open_anim_active = true
	_set_blocker_enabled(false)
	if interactable != null:
		interactable.enabled = false
		interactable.prompt = "Ironwatch Fort Vault Open"
	Audio.play_sfx(&"chest_thump", global_position, 2.0)
	Audio.play_stinger(&"discovery")
	Game.post_notice("Ironwatch Fort Vault unlocked! Claim the Sovereign hoard!")
	vault_opened.emit(self, opener)
	return true


## Returns normalized gate open progress in 0..1.
func get_open_progress() -> float:
	if not is_open:
		return 0.0
	return clampf(_open_elapsed / OPEN_DURATION, 0.0, 1.0)


## True while the solid vault StaticBody3D collision blocker prevents passage.
func is_blocking() -> bool:
	if _blocker_shape == null or _blocker_body == null:
		return false
	return (not _blocker_shape.disabled) and _blocker_body.collision_layer != 0


## Return the sculpted additive VaultTreasuryHalo MeshInstance3D inside the vault chamber.
func get_treasury_halo_node() -> MeshInstance3D:
	return _halo_mi


## Return the sculpted VaultGoldMotes MultiMeshInstance3D drifting inside the vault chamber.
func get_gold_motes_node() -> MultiMeshInstance3D:
	return _gold_motes_mmi


## Return the latest computed additive brightness energy for VaultTreasuryHalo.
func get_treasury_halo_energy() -> float:
	return _treasury_halo_energy


## Return the preallocated local-space positions of all 16 rising VaultGoldMotes.
func get_gold_mote_positions() -> PackedVector3Array:
	return _mote_positions


func step_animation(delta: float) -> void:
	_glow_clock += delta
	if _open_anim_active:
		_open_elapsed += delta
		var u := clampf(_open_elapsed / OPEN_DURATION, 0.0, 1.0)
		var eased := u * u * (3.0 - 2.0 * u)
		_apply_gate_angles(eased)
		if u >= 1.0:
			_open_anim_active = false
	if treasury_light != null and is_instance_valid(treasury_light):
		var base_e := 2.35 if is_open else 1.75
		var pulse := sin(_glow_clock * 3.6) * 0.14 + sin(_glow_clock * 8.1 + 0.9) * 0.07
		treasury_light.light_energy = base_e + pulse
	_update_treasury_vfx(delta)


func _physics_process(delta: float) -> void:
	step_animation(delta)


func _on_interacted(pawn: Node) -> void:
	if is_open:
		return
	if is_locked:
		Audio.play_sfx(&"parry_ring", global_position, -4.0)
		Game.post_notice("Vault sealed! Silence Ironwatch Fort's coastal batteries to open the gate!")
		return
	open_vault(pawn)


func _apply_gate_angles(eased_t: float) -> void:
	var ang := eased_t * OPEN_ANGLE_RAD
	# LeftGatePivot sits at -X (leaf extends +X): negative Y yaw swings leaf inward toward +Z.
	# RightGatePivot sits at +X (leaf extends -X): positive Y yaw swings leaf inward toward +Z.
	if left_gate_pivot != null:
		left_gate_pivot.rotation.y = -ang
	if right_gate_pivot != null:
		right_gate_pivot.rotation.y = ang


func _set_blocker_enabled(enabled: bool) -> void:
	if _blocker_shape != null:
		_blocker_shape.disabled = not enabled
	if _blocker_body != null:
		_blocker_body.collision_layer = 1 if enabled else 0


# ==============================================================================
# Scene Hierarchy Construction
# ==============================================================================

func _build_structure() -> void:
	_frame_mi = MeshInstance3D.new()
	_frame_mi.name = "VaultArchFrame"
	_frame_mi.mesh = _frame_mesh
	_frame_mi.set_surface_override_material(0, _stone_mat)
	if _frame_mesh.get_surface_count() > 1:
		_frame_mi.set_surface_override_material(1, _iron_mat)
	add_child(_frame_mi)

	left_gate_pivot = Node3D.new()
	left_gate_pivot.name = "LeftGatePivot"
	left_gate_pivot.position = Vector3(-GATE_HALF_SPAN, 0.0, 0.0)
	add_child(left_gate_pivot)

	_left_gate_mi = MeshInstance3D.new()
	_left_gate_mi.name = "LeftGateMesh"
	_left_gate_mi.mesh = _gate_left_mesh
	_left_gate_mi.set_surface_override_material(0, _iron_mat)
	if _gate_left_mesh.get_surface_count() > 1:
		_left_gate_mi.set_surface_override_material(1, _brass_mat)
	left_gate_pivot.add_child(_left_gate_mi)

	right_gate_pivot = Node3D.new()
	right_gate_pivot.name = "RightGatePivot"
	right_gate_pivot.position = Vector3(GATE_HALF_SPAN, 0.0, 0.0)
	add_child(right_gate_pivot)

	_right_gate_mi = MeshInstance3D.new()
	_right_gate_mi.name = "RightGateMesh"
	_right_gate_mi.mesh = _gate_right_mesh
	_right_gate_mi.set_surface_override_material(0, _iron_mat)
	if _gate_right_mesh.get_surface_count() > 1:
		_right_gate_mi.set_surface_override_material(1, _brass_mat)
	right_gate_pivot.add_child(_right_gate_mi)

	# Warm amber-gold treasury radiance spilling outward from behind the wrought-iron bars!
	treasury_light = OmniLight3D.new()
	treasury_light.name = "VaultTreasuryGlow"
	treasury_light.position = Vector3(0.0, 1.55, 1.45)
	treasury_light.light_color = Color(1.0, 0.76, 0.28)
	treasury_light.light_energy = 1.75
	treasury_light.omni_range = 10.0
	treasury_light.omni_attenuation = 1.3
	treasury_light.shadow_enabled = false
	add_child(treasury_light)


func _build_treasury_vfx() -> void:
	# 1. Sculpted 48-tri 16-wedge radial-gradient additive golden treasury halo inside the chamber.
	_halo_mat = StandardMaterial3D.new()
	_halo_mat.vertex_color_use_as_albedo = true
	_halo_mat.vertex_color_is_srgb = true
	_halo_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_halo_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_halo_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_halo_mat.billboard_keep_scale = true
	_halo_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	_halo_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_halo_mat.albedo_color = Color(HALO_ENERGY_LOCKED, HALO_ENERGY_LOCKED, HALO_ENERGY_LOCKED, 1.0)

	_halo_mi = MeshInstance3D.new()
	_halo_mi.name = "VaultTreasuryHalo"
	_halo_mi.position = HALO_POS
	_halo_mi.mesh = _halo_mesh
	_halo_mi.material_override = _halo_mat
	_halo_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_halo_mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	_halo_mi.visibility_range_end = HALO_VISIBILITY_RANGE
	_halo_mi.extra_cull_margin = 2.0
	add_child(_halo_mi)

	# 2. Preallocate deterministic buffers for 16 rising faceted Sovereign gold motes (zero runtime allocations).
	_mote_age.resize(GOLD_MOTE_COUNT)
	_mote_speed.resize(GOLD_MOTE_COUNT)
	_mote_base_x.resize(GOLD_MOTE_COUNT)
	_mote_base_z.resize(GOLD_MOTE_COUNT)
	_mote_phase.resize(GOLD_MOTE_COUNT)
	_mote_swirl_r.resize(GOLD_MOTE_COUNT)
	_mote_scale.resize(GOLD_MOTE_COUNT)
	_mote_positions.resize(GOLD_MOTE_COUNT)

	for i in GOLD_MOTE_COUNT:
		var fi := float(i)
		_mote_age[i] = lerpf(0.04, 0.68, fi / float(GOLD_MOTE_COUNT))
		_mote_speed[i] = lerpf(0.16, 0.25, fposmod(fi * 0.618034, 1.0))
		_mote_base_x[i] = lerpf(-1.18, 1.18, fposmod(fi * 0.381966 + 0.13, 1.0))
		_mote_base_z[i] = lerpf(-1.45, -0.08, fposmod(fi * 0.754877 + 0.27, 1.0))
		_mote_phase[i] = fi / float(GOLD_MOTE_COUNT) * TAU
		_mote_swirl_r[i] = lerpf(0.05, 0.15, fposmod(fi * 0.414213, 1.0))
		_mote_scale[i] = lerpf(0.75, 1.32, fposmod(fi * 0.543689, 1.0))
		_mote_positions[i] = Vector3(_mote_base_x[i], lerpf(MOTE_Y_MIN, MOTE_Y_MAX, _mote_age[i]), _mote_base_z[i])

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = false
	mm.mesh = _gold_mote_mesh
	mm.instance_count = GOLD_MOTE_COUNT
	for i in GOLD_MOTE_COUNT:
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, _mote_positions[i]))
		mm.set_instance_color(i, Color(1.0, 0.90, 0.45, 1.0))

	_gold_motes_mmi = MultiMeshInstance3D.new()
	_gold_motes_mmi.name = "VaultGoldMotes"
	_gold_motes_mmi.multimesh = mm
	_gold_motes_mmi.material_override = _mote_mat
	_gold_motes_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_gold_motes_mmi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	_gold_motes_mmi.visibility_range_end = MOTE_VISIBILITY_RANGE
	_gold_motes_mmi.extra_cull_margin = 3.0
	add_child(_gold_motes_mmi)


func _update_treasury_vfx(delta: float) -> void:
	var open_t := get_open_progress()
	var open_eased := open_t * open_t * (3.0 - 2.0 * open_t)
	var halo_pulse := sin(_glow_clock * 2.8) * 0.045 + sin(_glow_clock * 6.1 + 0.7) * 0.020
	_treasury_halo_energy = lerpf(HALO_ENERGY_LOCKED, HALO_ENERGY_OPEN, open_eased) + halo_pulse

	if _halo_mat != null:
		_halo_mat.albedo_color = Color(_treasury_halo_energy, _treasury_halo_energy, _treasury_halo_energy, 1.0)
	if _halo_mi != null and is_instance_valid(_halo_mi):
		var halo_scale := lerpf(HALO_SCALE_LOCKED, HALO_SCALE_OPEN, open_eased) * (1.0 + sin(_glow_clock * 2.8) * 0.015)
		_halo_mi.scale = Vector3(halo_scale, halo_scale, halo_scale)

	if _gold_motes_mmi == null or not is_instance_valid(_gold_motes_mmi):
		return
	var mm := _gold_motes_mmi.multimesh
	if mm == null:
		return

	# Distance-gate mote updates cleanly to <= 55 m in live gameplay when a Camera3D exists;
	# headless deterministic step_animation(delta) (no active Camera3D) always animates.
	if delta > 0.0 and is_inside_tree():
		var vp := get_viewport()
		var cam := vp.get_camera_3d() if vp != null else null
		if cam != null and cam.global_position.distance_to(global_position) > MOTE_ACTIVE_DIST:
			return

	var speed_mul := lerpf(1.0, 1.28, open_eased)
	var glow_mul := lerpf(0.82, 1.38, open_eased)
	for i in GOLD_MOTE_COUNT:
		var age := _mote_age[i]
		if delta > 0.0:
			age = fposmod(age + _mote_speed[i] * speed_mul * delta, 1.0)
			_mote_age[i] = age
		var y := lerpf(MOTE_Y_MIN, MOTE_Y_MAX, age)
		var ang := _mote_phase[i] + _glow_clock * 1.35 + age * TAU * 0.65
		var sr := _mote_swirl_r[i]
		var pos := Vector3(
			_mote_base_x[i] + cos(ang) * sr,
			y,
			_mote_base_z[i] + sin(ang) * sr
		)
		_mote_positions[i] = pos
		var env := smoothstep(0.0, 0.12, age) * (1.0 - smoothstep(0.82, 1.0, age))
		var s := maxf(0.24, _mote_scale[i] * lerpf(0.55, 1.15, env) * lerpf(1.0, 1.18, open_eased))
		var rot_b := Basis(Vector3.UP, ang * 1.4) * Basis(Vector3.RIGHT, _glow_clock * 1.9 + float(i) * 0.6)
		mm.set_instance_transform(i, Transform3D(rot_b.scaled(Vector3(s, s, s)), pos))
		var lum := clampf(env * glow_mul, 0.0, 1.8)
		mm.set_instance_color(i, Color(lum, lum * 0.94, lum * 0.72, 1.0))


func _build_blocker() -> void:
	_blocker_body = StaticBody3D.new()
	_blocker_body.name = "VaultBlocker"
	_blocker_body.collision_layer = 1
	_blocker_body.collision_mask = 0
	_blocker_shape = CollisionShape3D.new()
	_blocker_shape.name = "VaultBlockerShape"
	var bx := BoxShape3D.new()
	bx.size = Vector3(3.14, 2.95, 0.46)
	_blocker_shape.shape = bx
	_blocker_shape.position = Vector3(0.0, 1.48, 0.0)
	_blocker_body.add_child(_blocker_shape)
	add_child(_blocker_body)
	_set_blocker_enabled(not is_open)


func _build_interactable() -> void:
	interactable = Interactable.create("Unlock Ironwatch Fort Vault", 1.35)
	interactable.name = "VaultInteractable"
	interactable.position = Vector3(0.0, 1.45, -0.35)
	interactable.reach = 3.6
	interactable.interacted.connect(_on_interacted)
	add_child(interactable)


# ==============================================================================
# Shared Sculpted Flat-Faceted Procedural Meshes (Zero Raw Primitives)
# ==============================================================================

static func _ensure_shared_assets() -> void:
	if _stone_mat == null:
		_stone_mat = StandardMaterial3D.new()
		_stone_mat.vertex_color_use_as_albedo = true
		_stone_mat.vertex_color_is_srgb = true
		_stone_mat.roughness = 0.90
		_stone_mat.metallic = 0.02
	if _iron_mat == null:
		_iron_mat = StandardMaterial3D.new()
		_iron_mat.vertex_color_use_as_albedo = true
		_iron_mat.vertex_color_is_srgb = true
		_iron_mat.roughness = 0.46
		_iron_mat.metallic = 0.64
	if _brass_mat == null:
		_brass_mat = StandardMaterial3D.new()
		_brass_mat.vertex_color_use_as_albedo = true
		_brass_mat.vertex_color_is_srgb = true
		_brass_mat.roughness = 0.26
		_brass_mat.metallic = 0.78
	if _mote_mat == null:
		_mote_mat = StandardMaterial3D.new()
		_mote_mat.vertex_color_use_as_albedo = true
		_mote_mat.vertex_color_is_srgb = true
		_mote_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_mote_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_mote_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	if _frame_mesh == null:
		_frame_mesh = _build_stone_arch_frame_mesh()
	if _gate_left_mesh == null:
		_gate_left_mesh = _build_gate_leaf_mesh(true)
	if _gate_right_mesh == null:
		_gate_right_mesh = _build_gate_leaf_mesh(false)
	if _halo_mesh == null:
		_halo_mesh = _build_treasury_halo_mesh()
	if _gold_mote_mesh == null:
		_gold_mote_mesh = _build_gold_mote_mesh()


static func _build_treasury_halo_mesh() -> ArrayMesh:
	# Sculpted 48-tri 16-wedge radial-gradient Sovereign gold halo disc with finite (0, 0, 1) unit normals.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	const WEDGES := 16
	const INNER_R := 0.56
	const OUTER_R := 1.45
	const FRONT_NORMAL := Vector3(0.0, 0.0, 1.0)
	var ctr := Vector3.ZERO
	for i in WEDGES:
		var a0 := TAU * float(i) / float(WEDGES)
		var a1 := TAU * float(i + 1) / float(WEDGES)
		var m0 := Vector3(cos(a0) * INNER_R, sin(a0) * INNER_R, 0.0)
		var m1 := Vector3(cos(a1) * INNER_R, sin(a1) * INNER_R, 0.0)
		var o0 := Vector3(cos(a0) * OUTER_R, sin(a0) * OUTER_R, 0.0)
		var o1 := Vector3(cos(a1) * OUTER_R, sin(a1) * OUTER_R, 0.0)
		# Inner core wedge (16 tris)
		st.set_normal(FRONT_NORMAL)
		st.set_color(COL_HALO_CORE)
		st.add_vertex(ctr)
		st.set_normal(FRONT_NORMAL)
		st.set_color(COL_HALO_MID)
		st.add_vertex(m1)
		st.set_normal(FRONT_NORMAL)
		st.set_color(COL_HALO_MID)
		st.add_vertex(m0)
		# Outer feathered skirt quad fading smoothly to Color(0, 0, 0, 1) (32 tris)
		st.set_normal(FRONT_NORMAL)
		st.set_color(COL_HALO_MID)
		st.add_vertex(m0)
		st.set_normal(FRONT_NORMAL)
		st.set_color(COL_HALO_MID)
		st.add_vertex(m1)
		st.set_normal(FRONT_NORMAL)
		st.set_color(COL_HALO_RIM)
		st.add_vertex(o1)
		st.set_normal(FRONT_NORMAL)
		st.set_color(COL_HALO_MID)
		st.add_vertex(m0)
		st.set_normal(FRONT_NORMAL)
		st.set_color(COL_HALO_RIM)
		st.add_vertex(o1)
		st.set_normal(FRONT_NORMAL)
		st.set_color(COL_HALO_RIM)
		st.add_vertex(o0)
	return st.commit()


static func _build_gold_mote_mesh() -> ArrayMesh:
	# Exact 8-tri faceted golden diamond bipyramid mote (finite outward unit normals).
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var top := Vector3(0.0, 0.068, 0.0)
	var bot := Vector3(0.0, -0.056, 0.0)
	const R := 0.036
	var ring: Array[Vector3] = [
		Vector3(R, 0.0, 0.0),
		Vector3(0.0, 0.0, R),
		Vector3(-R, 0.0, 0.0),
		Vector3(0.0, 0.0, -R),
	]
	for k in 4:
		var k1 := (k + 1) % 4
		_emit_outward_tri(st, top, COL_MOTE_TOP, ring[k], COL_MOTE_MID, ring[k1], COL_MOTE_MID, Vector3.ZERO)
		_emit_outward_tri(st, bot, COL_MOTE_BOT, ring[k1], COL_MOTE_MID, ring[k], COL_MOTE_MID, Vector3.ZERO)
	st.generate_normals()
	return st.commit()


static func _build_stone_arch_frame_mesh() -> ArrayMesh:
	var stone_st := SurfaceTool.new()
	stone_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var iron_st := SurfaceTool.new()
	iron_st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Stepped stone sill threshold flush at y = 0.0 spanning 3.9 m across the gateway.
	_append_beveled_box(
		stone_st, Vector3(0.0, 0.055, 0.0), Vector3(4.10, 0.11, 0.88), 0.025,
		COL_STONE_LIGHT, COL_STONE_MID, COL_STONE_MOSS
	)

	# Massive coral-limestone left & right ashlar jamb piers (3.8 m outer span, 3.04 m inner opening).
	for sgn: float in [-1.0, 1.0]:
		var jx := sgn * 1.84
		# Moss-stained battered base plinth resting on courtyard pavement.
		_append_beveled_box(
			stone_st, Vector3(jx, 0.24, 0.0), Vector3(0.72, 0.48, 0.84), 0.04,
			COL_STONE_MID, COL_STONE_MOSS, COL_STONE_SHADOW
		)
		# Stacked faceted ashlar masonry courses up to the arch springline (y = 2.48 m).
		var courses: Array[Array] = [
			[0.72, 0.48, 0.62, 0.74, COL_STONE_LIGHT, COL_STONE_MID],
			[1.20, 0.48, 0.65, 0.76, COL_STONE_MID, COL_STONE_SHADOW],
			[1.68, 0.48, 0.61, 0.73, COL_STONE_LIGHT, COL_STONE_MID],
			[2.16, 0.48, 0.64, 0.76, COL_STONE_LIGHT, COL_STONE_MID],
		]
		for course in courses:
			_append_beveled_box(
				stone_st, Vector3(jx, float(course[0]), 0.0),
				Vector3(float(course[2]), float(course[1]), float(course[3])), 0.032,
				course[4] as Color, course[5] as Color, COL_STONE_SHADOW
			)
		# Protruding beveled impost capital block where the stone arch springs.
		_append_beveled_box(
			stone_st, Vector3(jx, 2.49, 0.0), Vector3(0.76, 0.22, 0.84), 0.035,
			COL_STONE_LIGHT, COL_STONE_LIGHT, COL_STONE_SHADOW
		)

		# Heavy forged iron hinge pintles anchored into the inner jamb face (y = 0.56 & y = 2.04).
		for hy: float in [0.56, 2.04]:
			var inner_x := sgn * 1.54
			_append_beveled_box(
				iron_st, Vector3(inner_x + sgn * 0.04, hy, 0.0), Vector3(0.14, 0.11, 0.14), 0.015,
				COL_IRON_HI, COL_IRON_MID, COL_IRON_DARK
			)
			_append_cylinder_between(
				iron_st, Vector3(sgn * GATE_HALF_SPAN, hy - 0.08, 0.0), Vector3(sgn * GATE_HALF_SPAN, hy + 0.10, 0.0),
				0.032, 0.028, 6, COL_IRON_DARK, COL_IRON_HI
			)

	# 7-voussoir coral-limestone segmental arch lintel spanning cleanly to y = 3.22 m!
	var voussoirs: Array[Array] = [
		[-1.44, 2.66, 0.34, Vector3(0.56, 0.48, 0.76)],
		[-0.96, 2.84, 0.22, Vector3(0.54, 0.50, 0.76)],
		[-0.48, 2.95, 0.11, Vector3(0.54, 0.52, 0.76)],
		[0.00, 3.00, 0.00, Vector3(0.56, 0.64, 0.88)],
		[0.48, 2.95, -0.11, Vector3(0.54, 0.52, 0.76)],
		[0.96, 2.84, -0.22, Vector3(0.54, 0.50, 0.76)],
		[1.44, 2.66, -0.34, Vector3(0.56, 0.48, 0.76)],
	]
	for vi in voussoirs.size():
		var v: Array = voussoirs[vi]
		var vx: float = float(v[0])
		var vy: float = float(v[1])
		var roll: float = float(v[2])
		var vsz: Vector3 = v[3] as Vector3
		var is_keystone := (vi == 3)
		var rot := Basis(Vector3.BACK, roll)
		_append_oriented_beveled_box(
			stone_st, Vector3(vx, vy, 0.0), rot, vsz, 0.035,
			COL_STONE_LIGHT, COL_STONE_LIGHT if is_keystone else COL_STONE_MID, COL_STONE_SHADOW
		)

	# Heavy beveled crowning stone lintel cornice capping the gate frame at y = 3.22 m.
	_append_beveled_box(
		stone_st, Vector3(0.0, 3.16, 0.0), Vector3(4.12, 0.18, 0.90), 0.035,
		COL_STONE_LIGHT, COL_STONE_MID, COL_STONE_SHADOW
	)
	# Forged iron drop-bolt stop plate embedded in center threshold sill.
	_append_beveled_box(
		iron_st, Vector3(0.0, 0.115, 0.0), Vector3(0.24, 0.035, 0.18), 0.006,
		COL_IRON_HI, COL_IRON_MID, COL_IRON_DARK
	)

	stone_st.generate_normals()
	var mesh := stone_st.commit()
	iron_st.generate_normals()
	iron_st.commit(mesh)
	return mesh


static func _build_gate_leaf_mesh(is_left: bool) -> ArrayMesh:
	var iron_st := SurfaceTool.new()
	iron_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var brass_st := SurfaceTool.new()
	brass_st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Leaf extends along local +X (if left) or -X (if right) from hinge x = 0 to center seam x = dir * 1.50.
	var dir := 1.0 if is_left else -1.0
	var leaf_w := 1.50
	var outer_x := dir * leaf_w
	var mid_x := dir * (leaf_w * 0.5)

	# 1. Outer forged iron vertical stiles (hinge stile & center meeting stile).
	_append_beveled_box(
		iron_st, Vector3(dir * 0.045, 1.24, 0.0), Vector3(0.09, 2.26, 0.095), 0.012,
		COL_IRON_HI, COL_IRON_MID, COL_IRON_DARK
	)
	_append_beveled_box(
		iron_st, Vector3(outer_x - dir * 0.042, 1.38, 0.0), Vector3(0.085, 2.54, 0.095), 0.012,
		COL_IRON_HI, COL_IRON_MID, COL_IRON_DARK
	)

	# 2. Heavy bottom kick rail, riveted middle cross-strap & upper cross-strap.
	_append_beveled_box(
		iron_st, Vector3(mid_x, 0.22, 0.0), Vector3(leaf_w - 0.04, 0.18, 0.085), 0.012,
		COL_IRON_HI, COL_IRON_MID, COL_IRON_DARK
	)
	for strap_y: float in [0.64, 1.26, 2.02]:
		var sh := 0.125 if strap_y == 1.26 else 0.095
		_append_beveled_box(
			iron_st, Vector3(mid_x, strap_y, 0.0), Vector3(leaf_w - 0.03, sh, 0.105), 0.010,
			COL_IRON_HI, COL_IRON_MID, COL_IRON_DARK
		)

	# 3. Curved segmental upper arch rail following the stone lintel curve.
	var arch_segs := 5
	for i in arch_segs:
		var u0 := float(i) / float(arch_segs)
		var u1 := float(i + 1) / float(arch_segs)
		var p0 := Vector3(dir * (0.04 + u0 * (leaf_w - 0.08)), _gate_top_y(u0), 0.0)
		var p1 := Vector3(dir * (0.04 + u1 * (leaf_w - 0.08)), _gate_top_y(u1), 0.0)
		_append_cylinder_between(iron_st, p0, p1, 0.042, 0.042, 6, COL_IRON_DARK, COL_IRON_HI)

	# 4. 6 forged vertical wrought-iron bars with rivets & chunky faceted spearhead finials!
	var bar_count := 6
	for bi in bar_count:
		var u := (float(bi) + 0.5) / float(bar_count)
		var bx := dir * (0.09 + u * (leaf_w - 0.18))
		var top_y := _gate_top_y(u)
		_append_cylinder_between(
			iron_st, Vector3(bx, 0.20, 0.0), Vector3(bx, top_y + 0.08, 0.0),
			0.026, 0.024, 6, COL_IRON_DARK, COL_IRON_HI
		)
		# Spearhead collar ring & faceted diamond spear tip above the upper arch rail.
		_append_beveled_box(
			iron_st, Vector3(bx, top_y + 0.07, 0.0), Vector3(0.068, 0.035, 0.068), 0.008,
			COL_IRON_HI, COL_IRON_MID, COL_IRON_DARK
		)
		_append_spear_finial(iron_st, Vector3(bx, top_y + 0.085, 0.0), 0.056, 0.21, COL_IRON_HI, COL_IRON_DARK)

		# Rivet studs at every bar-to-cross-strap intersection (front -Z & back +Z faces).
		for strap_y: float in [0.64, 1.26, 2.02]:
			for fz: float in [-1.0, 1.0]:
				_append_rivet_dome(iron_st, Vector3(bx, strap_y, fz * 0.053), Vector3(0.0, 0.0, fz), 0.017, 0.011, COL_RIVET)

	# 5. Forged iron strap-hinge collars clasping the stone jamb pintles (y = 0.56 & y = 2.04).
	for hy: float in [0.56, 2.04]:
		_append_cylinder_between(
			iron_st, Vector3(0.0, hy - 0.075, 0.0), Vector3(0.0, hy + 0.075, 0.0),
			0.052, 0.052, 8, COL_IRON_DARK, COL_IRON_HI
		)
		_append_beveled_box(
			iron_st, Vector3(dir * 0.16, hy, 0.0), Vector3(0.32, 0.095, 0.115), 0.010,
			COL_IRON_HI, COL_IRON_MID, COL_IRON_DARK
		)
		_append_rivet_dome(brass_st, Vector3(dir * 0.22, hy, -0.058), Vector3(0.0, 0.0, -1.0), 0.020, 0.012, COL_BRASS_HI)

	# 6. Ornate gleaming brass lockplate, keyhole escutcheon & heavy pirate padlock at the center seam!
	if not is_left:
		var lx := outer_x - dir * 0.06
		var ly := 1.26
		# Ornate beveled brass lockplate backplate spanning both sides of the meeting stile.
		_append_beveled_box(
			brass_st, Vector3(lx, ly, -0.064), Vector3(0.24, 0.34, 0.036), 0.010,
			COL_BRASS_HI, COL_BRASS_MID, COL_BRASS_DARK
		)
		_append_beveled_box(
			brass_st, Vector3(lx, ly, 0.064), Vector3(0.22, 0.30, 0.032), 0.010,
			COL_BRASS_HI, COL_BRASS_MID, COL_BRASS_DARK
		)
		# Corner brass lockplate studs.
		for rx: float in [-0.085, 0.085]:
			for ry: float in [-0.125, 0.125]:
				_append_rivet_dome(brass_st, Vector3(lx + rx, ly + ry, -0.082), Vector3(0.0, 0.0, -1.0), 0.014, 0.010, COL_BRASS_HI)
		# Dark recessed iron keyhole & heavy brass latch bar reaching across the center seam.
		_append_beveled_box(
			iron_st, Vector3(lx, ly + 0.04, -0.084), Vector3(0.032, 0.072, 0.012), 0.004,
			COL_IRON_DARK, COL_IRON_DARK, COL_IRON_DARK
		)
		_append_beveled_box(
			brass_st, Vector3(outer_x, ly, -0.076), Vector3(0.24, 0.062, 0.032), 0.008,
			COL_BRASS_HI, COL_BRASS_MID, COL_BRASS_DARK
		)
		# Heavy sculpted brass vault padlock hanging from the center seam hasp!
		var pad_c := Vector3(outer_x, ly - 0.19, -0.102)
		# Iron-and-brass padlock shackle arch looping up through the hasp.
		var sh_pts: Array[Vector3] = [
			pad_c + Vector3(-0.046, 0.07, 0.0),
			pad_c + Vector3(-0.046, 0.145, 0.0),
			pad_c + Vector3(0.0, 0.180, 0.0),
			pad_c + Vector3(0.046, 0.145, 0.0),
			pad_c + Vector3(0.046, 0.07, 0.0),
		]
		for si in range(sh_pts.size() - 1):
			_append_cylinder_between(iron_st, sh_pts[si], sh_pts[si + 1], 0.016, 0.016, 6, COL_IRON_DARK, COL_IRON_HI)
		# Chunky beveled hexagonal brass padlock body + front keyhole boss.
		_append_beveled_box(
			brass_st, pad_c, Vector3(0.16, 0.17, 0.072), 0.022,
			COL_BRASS_HI, COL_BRASS_MID, COL_BRASS_DARK
		)
		_append_beveled_box(
			iron_st, pad_c + Vector3(0.0, -0.01, -0.038), Vector3(0.024, 0.056, 0.010), 0.004,
			COL_IRON_DARK, COL_IRON_DARK, COL_IRON_DARK
		)
	else:
		# Matching brass catch plate & decorative boss on the left leaf meeting stile.
		var lx := outer_x - dir * 0.06
		_append_beveled_box(
			brass_st, Vector3(lx, 1.26, -0.062), Vector3(0.18, 0.28, 0.030), 0.009,
			COL_BRASS_HI, COL_BRASS_MID, COL_BRASS_DARK
		)
		_append_rivet_dome(brass_st, Vector3(lx, 1.35, -0.077), Vector3(0.0, 0.0, -1.0), 0.015, 0.010, COL_BRASS_HI)
		_append_rivet_dome(brass_st, Vector3(lx, 1.17, -0.077), Vector3(0.0, 0.0, -1.0), 0.015, 0.010, COL_BRASS_HI)

	iron_st.generate_normals()
	var mesh := iron_st.commit()
	brass_st.generate_normals()
	brass_st.commit(mesh)
	return mesh


static func _gate_top_y(u: float) -> float:
	# Graceful rising fortress arch profile from hinge (u = 0 -> 2.34 m) to center (u = 1 -> 2.66 m).
	return 2.34 + sin(clampf(u, 0.0, 1.0) * PI * 0.5) * 0.32


# ==============================================================================
# Flat-Faceted `SurfaceTool` Helpers (`set_smooth_group(-1)`)
# ==============================================================================

static func _emit_flat_tri(st: SurfaceTool, a: Vector3, ca: Color,
		b: Vector3, cb: Color, c: Vector3, cc: Color) -> void:
	if (c - a).cross(b - a).length_squared() < 1e-12:
		return
	st.set_smooth_group(-1)
	st.set_color(ca)
	st.add_vertex(a)
	st.set_smooth_group(-1)
	st.set_color(cb)
	st.add_vertex(b)
	st.set_smooth_group(-1)
	st.set_color(cc)
	st.add_vertex(c)


static func _emit_dir_tri(st: SurfaceTool, a: Vector3, ca: Color,
		b: Vector3, cb: Color, c: Vector3, cc: Color, expected_normal: Vector3) -> void:
	var n := (c - a).cross(b - a)
	if n.length_squared() < 1e-12:
		return
	if n.dot(expected_normal) < 0.0:
		_emit_flat_tri(st, a, ca, c, cc, b, cb)
	else:
		_emit_flat_tri(st, a, ca, b, cb, c, cc)


static func _emit_outward_tri(st: SurfaceTool, a: Vector3, ca: Color,
		b: Vector3, cb: Color, c: Vector3, cc: Color, ref_center: Vector3) -> void:
	var centroid := (a + b + c) / 3.0
	_emit_dir_tri(st, a, ca, b, cb, c, cc, centroid - ref_center)


static func _append_beveled_box(st: SurfaceTool, center: Vector3, size: Vector3, bevel: float,
		col_top: Color, col_mid: Color, col_bot: Color) -> void:
	_append_oriented_beveled_box(st, center, Basis.IDENTITY, size, bevel, col_top, col_mid, col_bot)


static func _append_oriented_beveled_box(st: SurfaceTool, center: Vector3, rot: Basis,
		size: Vector3, bevel: float, col_top: Color, col_mid: Color, col_bot: Color) -> void:
	var hx := size.x * 0.5
	var hy := size.y * 0.5
	var hz := size.z * 0.5
	var bv := minf(bevel, minf(hx, minf(hy, hz)) * 0.45)
	var ix := hx - bv
	var iy := hy - bv
	var iz := hz - bv

	var ys: Array[float] = [-hy, -iy, iy, hy]
	var xzs: Array[Vector2] = [Vector2(ix, iz), Vector2(hx, hz), Vector2(hx, hz), Vector2(ix, iz)]
	var cols: Array[Color] = [col_bot, col_bot.lerp(col_mid, 0.5), col_mid.lerp(col_top, 0.5), col_top]

	var rings: Array[Array] = []
	for li in 4:
		var ry := ys[li]
		var rx := xzs[li].x
		var rz := xzs[li].y
		var cx := maxf(rx - bv * 0.5, 0.001)
		var cz := maxf(rz - bv * 0.5, 0.001)
		var raw_pts: Array[Vector3] = [
			Vector3(-cx, ry, -rz),
			Vector3(cx, ry, -rz),
			Vector3(rx, ry, -cz),
			Vector3(rx, ry, cz),
			Vector3(cx, ry, rz),
			Vector3(-cx, ry, rz),
			Vector3(-rx, ry, cz),
			Vector3(-rx, ry, -cz),
		]
		var ring: Array[Vector3] = []
		for rp in raw_pts:
			ring.append(center + rot * rp)
		rings.append(ring)

	for li in 3:
		var r0: Array = rings[li]
		var r1: Array = rings[li + 1]
		var c0 := cols[li]
		var c1 := cols[li + 1]
		for k in 8:
			var nk := (k + 1) % 8
			_emit_outward_tri(st, r0[k], c0, r1[k], c1, r1[nk], c1, center)
			_emit_outward_tri(st, r0[k], c0, r1[nk], c1, r0[nk], c0, center)

	var top_c := center + rot * Vector3(0.0, hy, 0.0)
	var bot_c := center + rot * Vector3(0.0, -hy, 0.0)
	var top_n := rot * Vector3.UP
	var bot_n := rot * Vector3.DOWN
	var top_r: Array = rings[3]
	var bot_r: Array = rings[0]
	for k in 8:
		var nk := (k + 1) % 8
		_emit_dir_tri(st, top_c, col_top, top_r[k], col_top, top_r[nk], col_top, top_n)
		_emit_dir_tri(st, bot_c, col_bot, bot_r[nk], col_bot, bot_r[k], col_bot, bot_n)


static func _append_cylinder_between(st: SurfaceTool, p0: Vector3, p1: Vector3,
		r0: float, r1: float, segs: int, c0: Color, c1: Color) -> void:
	var axis := p1 - p0
	if axis.length_squared() < 1e-10:
		return
	var an := axis.normalized()
	var ref := Vector3.UP if absf(an.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT
	var bx := an.cross(ref).normalized()
	var by := an.cross(bx).normalized()
	var mid := (p0 + p1) * 0.5
	for k in segs:
		var a0 := float(k) / float(segs) * TAU
		var a1 := float(k + 1) / float(segs) * TAU
		var d0 := bx * cos(a0) + by * sin(a0)
		var d1 := bx * cos(a1) + by * sin(a1)
		var v00 := p0 + d0 * r0
		var v01 := p0 + d1 * r0
		var v10 := p1 + d0 * r1
		var v11 := p1 + d1 * r1
		_emit_outward_tri(st, v00, c0, v10, c1, v11, c1, mid)
		_emit_outward_tri(st, v00, c0, v11, c1, v01, c0, mid)
		_emit_outward_tri(st, p0, c0, v00, c0, v01, c0, mid)
		_emit_outward_tri(st, p1, c1, v11, c1, v10, c1, mid)


static func _append_spear_finial(st: SurfaceTool, base: Vector3, half_w: float, height: float,
		col_hi: Color, col_lo: Color) -> void:
	# Faceted 4-sided diamond spearhead finial with crisp forged spine ridges.
	var mid_y := base.y + height * 0.34
	var tip := Vector3(base.x, base.y + height, base.z)
	var b_pts: Array[Vector3] = [
		Vector3(base.x - half_w * 0.45, base.y, base.z),
		Vector3(base.x, base.y, base.z - half_w * 0.38),
		Vector3(base.x + half_w * 0.45, base.y, base.z),
		Vector3(base.x, base.y, base.z + half_w * 0.38),
	]
	var m_pts: Array[Vector3] = [
		Vector3(base.x - half_w, mid_y, base.z),
		Vector3(base.x, mid_y, base.z - half_w * 0.56),
		Vector3(base.x + half_w, mid_y, base.z),
		Vector3(base.x, mid_y, base.z + half_w * 0.56),
	]
	var ctr := Vector3(base.x, base.y + height * 0.42, base.z)
	for i in 4:
		var ni := (i + 1) % 4
		_emit_outward_tri(st, b_pts[i], col_lo, m_pts[i], col_hi, m_pts[ni], col_hi, ctr)
		_emit_outward_tri(st, b_pts[i], col_lo, m_pts[ni], col_hi, b_pts[ni], col_lo, ctr)
		_emit_outward_tri(st, m_pts[i], col_hi, tip, col_hi, m_pts[ni], col_hi, ctr)


static func _append_rivet_dome(st: SurfaceTool, base: Vector3, out_dir: Vector3,
		radius: float, height: float, col: Color) -> void:
	var n := out_dir.normalized()
	var ref := Vector3.UP if absf(n.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT
	var bx := n.cross(ref).normalized()
	var by := n.cross(bx).normalized()
	var segs := 6
	var apex := base + n * height
	var col_rim := col.darkened(0.22)
	for k in segs:
		var a0 := float(k) / float(segs) * TAU
		var a1 := float(k + 1) / float(segs) * TAU
		var p0 := base + (bx * cos(a0) + by * sin(a0)) * radius
		var p1 := base + (bx * cos(a1) + by * sin(a1)) * radius
		_emit_dir_tri(st, p0, col_rim, p1, col_rim, apex, col, n)
