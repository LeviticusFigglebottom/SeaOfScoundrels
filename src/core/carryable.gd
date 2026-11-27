class_name Carryable
extends RigidBody3D
## Base for anything hauled by hand: chests, cannonballs, crates, planks.
##
## A rigid body on collision layer 6. A pawn picks it up through the built-in
## `Interactable`; while held it is frozen, has no collision and is placed in
## front of the holder by the pawn every physics tick. It floats, using `Sea`.
## It can be dropped (`Pawn.drop_carried`) or handed to a container
## (`hand_to(container)`; the container implements
## `accept_carryable(item) -> bool`).
##
## State changes run on the host only.

signal picked_up(pawn: Node)
signal dropped(pawn: Node)
signal stored(container: Node)

const LAYER := 1 << 5
const MASK := 1 | 2 | (1 << 5)

@export var item_name: String = "Crate"
## Buoyant force over weight when fully submerged. Above 1 floats, below sinks.
@export var buoyancy: float = 1.7
## Half height used for the submersion estimate, metres.
@export var float_radius: float = 0.25
## Multiplier on the holder's sprint speed.
@export var carry_speed_factor: float = 0.72
## Hold position relative to the holder's feet, in the holder's facing frame.
@export var hold_offset: Vector3 = Vector3(0.0, 1.0, -0.62)
## Enable distant Sea-of-Thieves style color-coded treasure glint star.
@export var glint_enabled: bool = false
## Color hue applied to the additive TreasureGlintStar sparkle.
@export var glint_color: Color = Color(1.0, 0.86, 0.34)
## Vertical offset (m) where TreasureGlintStar mounts above the carryable origin.
@export var glint_height: float = 0.42

var holder: Node3D = null
var stored_in: Node = null
var interactable: Interactable = null

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
var _glint_mi: MeshInstance3D = null
var _glint_mat: StandardMaterial3D = null
var _glint_clock: float = 0.0
var _glint_phase: float = 0.0
var _glint_strength: float = 0.0
var _foam_timer: float = 0.0

## WeakRef-cached sculpted 4-point diamond star + radial glow ArrayMesh (0 strong static leaks).
static var _glint_mesh_ref: WeakRef = null

func _ready() -> void:
	collision_layer = LAYER
	collision_mask = MASK
	for c in get_children():
		if c is Interactable:
			interactable = c
	if interactable == null:
		interactable = Interactable.create("Pick up " + item_name, 0.55)
		add_child(interactable)
	interactable.interacted.connect(_on_interacted)
	if glint_enabled and _glint_mi == null:
		enable_treasure_glint(glint_color, glint_height)

func _exit_tree() -> void:
	_release_glint_resources()

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		_release_glint_resources()

func _release_glint_resources() -> void:
	if _glint_mi != null and is_instance_valid(_glint_mi):
		_glint_mi.material_override = null
		_glint_mi.mesh = null
	_glint_mi = null
	_glint_mat = null
	_glint_strength = 0.0

## Clear the WeakRef holder for the shared TreasureGlintStar mesh on teardown.
static func clear_shared_glint_cache() -> void:
	_glint_mesh_ref = null

func _on_interacted(pawn: Node) -> void:
	if pawn != null and pawn.has_method("pick_up"):
		pawn.pick_up(self)

func is_held() -> bool:
	return holder != null

## Mount and configure the distance-gated color-coded TreasureGlintStar billboard.
func enable_treasure_glint(color: Color, height_offset: float = 0.42) -> void:
	glint_enabled = true
	glint_color = color
	glint_height = height_offset
	var phase_seed := float(item_name.hash() & 0xFFFF) * 0.0137 + position.x * 0.71 + position.z * 0.53
	_glint_phase = fposmod(phase_seed, TAU)

	if _glint_mat == null:
		var mat := StandardMaterial3D.new()
		mat.vertex_color_use_as_albedo = true
		mat.vertex_color_is_srgb = true
		mat.albedo_color = color
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		mat.billboard_keep_scale = true
		mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_glint_mat = mat
	else:
		_glint_mat.albedo_color = color

	if _glint_mi == null or not is_instance_valid(_glint_mi):
		var mi := MeshInstance3D.new()
		mi.name = "TreasureGlintStar"
		mi.mesh = _get_shared_glint_mesh()
		mi.material_override = _glint_mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visibility_range_end = 175.0
		mi.visible = false
		add_child(mi)
		_glint_mi = mi
	else:
		_glint_mi.material_override = _glint_mat
	_glint_mi.position = Vector3(0.0, height_offset, 0.0)
	_glint_strength = 0.0

## Return the mounted TreasureGlintStar MeshInstance3D, or null if not enabled.
func get_glint_node() -> MeshInstance3D:
	return _glint_mi

## Return the latest computed glint brightness strength (0.0 when hidden/culled).
func get_glint_strength() -> float:
	return _glint_strength

func _hide_glint() -> void:
	_glint_strength = 0.0
	if _glint_mi != null and is_instance_valid(_glint_mi):
		_glint_mi.visible = false

## Update distance-gated Sea-of-Thieves glint visibility, pulse, and scale.
## Pass `cam_dist_override >= 0.0` in headless tests to evaluate deterministically without a Camera3D.
func tick_glint(delta: float, cam_dist_override: float = -1.0) -> void:
	if not glint_enabled or _glint_mi == null or not is_instance_valid(_glint_mi) or _glint_mat == null:
		return
	if is_held() or stored_in != null or not visible:
		_glint_mi.visible = false
		_glint_strength = 0.0
		return

	var d := cam_dist_override
	if d < 0.0:
		var vp := get_viewport() if is_inside_tree() else null
		var cam := vp.get_camera_3d() if vp != null else null
		if cam == null:
			_glint_mi.visible = false
			_glint_strength = 0.0
			return
		var origin := global_position if is_inside_tree() else position
		d = cam.global_position.distance_to(origin)

	if d < 5.0 or d > 165.0:
		_glint_mi.visible = false
		_glint_strength = 0.0
		return

	_glint_clock += maxf(0.0, delta)
	var dist_in := smoothstep(5.0, 9.5, d)
	var dist_out := 1.0 - smoothstep(138.0, 165.0, d)
	var dist_alpha := clampf(dist_in * dist_out, 0.0, 1.0)
	var wave := 0.5 + 0.5 * sin(_glint_clock * 2.35 + _glint_phase)
	var sparkle := 0.22 + 0.92 * pow(wave, 4.5)
	var scale_f := clampf(lerpf(0.32, 1.05, smoothstep(8.0, 75.0, d)) * sparkle, 0.14, 1.35)
	var intensity := clampf(dist_alpha * (0.45 + 0.95 * pow(wave, 3.0)), 0.0, 1.6)
	_glint_strength = intensity
	_glint_mi.visible = intensity > 0.001
	_glint_mi.scale = Vector3.ONE * scale_f
	_glint_mat.albedo_color = Color(
		glint_color.r * intensity,
		glint_color.g * intensity,
		glint_color.b * intensity,
		1.0
	)

func _process(delta: float) -> void:
	if glint_enabled:
		tick_glint(delta)

## Called by the holder (host only). Use `Pawn.pick_up(item)` from game code.
func attach_to(pawn: Node3D) -> void:
	if not Net.is_host():
		return
	holder = pawn
	stored_in = null
	_hide_glint()
	visible = true
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	freeze = true
	collision_layer = 0
	collision_mask = 0
	interactable.enabled = false
	picked_up.emit(pawn)

## Called by the holder (host only). Use `Pawn.drop_carried()` from game code.
func detach(world_velocity: Vector3 = Vector3.ZERO) -> void:
	if not Net.is_host():
		return
	var was := holder
	holder = null
	_restore_body()
	linear_velocity = world_velocity
	angular_velocity = Vector3.ZERO
	dropped.emit(was)

## Give the item to a container (barrel, hold rack, merchant). Returns false if
## the container refuses. On success the item is hidden and inert until
## `take_out()`; the container owns what happens next.
func hand_to(container: Node) -> bool:
	if not Net.is_host() or container == null or not container.has_method("accept_carryable"):
		return false
	if not container.accept_carryable(self):
		return false
	var was := holder
	holder = null
	if was != null and was.has_method("release_carried"):
		was.release_carried(self)
	stored_in = container
	_hide_glint()
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	freeze = true
	collision_layer = 0
	collision_mask = 0
	interactable.enabled = false
	visible = false
	stored.emit(container)
	return true

## Put a stored item back into the world.
func take_out(world_position: Vector3) -> void:
	if not Net.is_host():
		return
	stored_in = null
	visible = true
	global_position = world_position
	_restore_body()
	linear_velocity = Vector3.ZERO

func _restore_body() -> void:
	freeze = false
	collision_layer = LAYER
	collision_mask = MASK
	interactable.enabled = true

func _physics_process(delta: float) -> void:
	if freeze or not Net.is_host():
		return
	var bottom_depth := Sea.depth(global_position) + float_radius
	if bottom_depth <= 0.0:
		return
	var frac := clampf(bottom_depth / (2.0 * float_radius), 0.0, 1.0)
	apply_central_force(Vector3.UP * mass * _gravity * buoyancy * frac)
	apply_central_force(-linear_velocity * mass * 2.5 * frac)
	angular_velocity *= maxf(0.0, 1.0 - 2.0 * delta * frac)
	if bottom_depth > 0.05 and not is_held() and stored_in == null:
		_foam_timer -= delta
		if _foam_timer <= 0.0:
			_foam_timer = 1.45
			if Ocean.current != null and is_instance_valid(Ocean.current) and Ocean.current.has_method(&"add_foam"):
				Ocean.current.add_foam(global_position, float_radius * 2.4, 0.34)

static func _get_shared_glint_mesh() -> ArrayMesh:
	if _glint_mesh_ref != null:
		var existing: Variant = _glint_mesh_ref.get_ref()
		if existing is ArrayMesh:
			return existing as ArrayMesh
	var mesh := _build_glint_star_mesh()
	_glint_mesh_ref = weakref(mesh)
	return mesh

static func _emit_glint_tri(st: SurfaceTool, a: Vector3, ca: Color,
		b: Vector3, cb: Color, c: Vector3, cc: Color) -> void:
	const FRONT_NORMAL := Vector3(0.0, 0.0, 1.0)
	st.set_normal(FRONT_NORMAL)
	st.set_color(ca)
	st.add_vertex(a)
	st.set_normal(FRONT_NORMAL)
	st.set_color(cb)
	st.add_vertex(b)
	st.set_normal(FRONT_NORMAL)
	st.set_color(cc)
	st.add_vertex(c)

## Build a sculpted 32-tri 4-point diamond star + 2-ring soft radial glow ArrayMesh.
## Center is pure white-gold fading smoothly to Color(0, 0, 0, 1) at needle tips & halo rim
## so additive blending renders cleanly with zero hard edges and zero raw PrimitiveMeshes.
static func _build_glint_star_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var c_core := Color(1.0, 0.99, 0.92, 1.0)
	var c_mid := Color(0.42, 0.39, 0.32, 1.0)
	var c_zero := Color(0.0, 0.0, 0.0, 1.0)
	var center := Vector3.ZERO

	const HALO_SEGS := 8
	const R_MID := 0.12
	const R_OUT := 0.28
	var mid_ring: Array[Vector3] = []
	var out_ring: Array[Vector3] = []
	for k in HALO_SEGS:
		var ang := float(k) / float(HALO_SEGS) * TAU
		var sx := sin(ang)
		var cy := cos(ang)
		mid_ring.append(Vector3(sx * R_MID, cy * R_MID, 0.0))
		out_ring.append(Vector3(sx * R_OUT, cy * R_OUT, 0.0))
	for k in HALO_SEGS:
		var nk := (k + 1) % HALO_SEGS
		_emit_glint_tri(st, center, c_core, mid_ring[k], c_mid, mid_ring[nk], c_mid)
		_emit_glint_tri(st, mid_ring[k], c_mid, out_ring[k], c_zero, out_ring[nk], c_zero)
		_emit_glint_tri(st, mid_ring[k], c_mid, out_ring[nk], c_zero, mid_ring[nk], c_mid)

	const TIP_Y := 0.62
	const TIP_X := 0.56
	const VALLEY := 0.085
	var star_ring: Array[Vector3] = [
		Vector3(0.0, TIP_Y, 0.0),
		Vector3(VALLEY, VALLEY, 0.0),
		Vector3(TIP_X, 0.0, 0.0),
		Vector3(VALLEY, -VALLEY, 0.0),
		Vector3(0.0, -TIP_Y, 0.0),
		Vector3(-VALLEY, -VALLEY, 0.0),
		Vector3(-TIP_X, 0.0, 0.0),
		Vector3(-VALLEY, VALLEY, 0.0),
	]
	for k in star_ring.size():
		var nk := (k + 1) % star_ring.size()
		_emit_glint_tri(st, center, c_core, star_ring[k], c_zero, star_ring[nk], c_zero)

	var mesh := ArrayMesh.new()
	st.commit(mesh)
	return mesh

