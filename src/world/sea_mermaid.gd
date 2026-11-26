class_name SeaMermaid
extends Node3D
## Sculpted Sea-Merfolk Stranded-Swimmer Return Beacon.
##
## Rises gracefully from the open sea ahead of a stranded swimmer (for example
## after a Wave 33A cannon self-launch or failed enemy boarding) bearing a
## driftwood-and-coral beacon staff crowned with a blazing sea-glass conch orb
## and a towering 26 m curling emerald-turquoise smoke ribbon visible from 400 m
## across storm swells. Interacting (`[F] Return to ship`) drops any carried
## cargo into the sea and warps the swimmer cleanly back onto their ship's main
## deck, triggering sea foam, audio, and warm AI crew callouts.
##
## 100% sculpted flat-faceted `SurfaceTool` `ArrayMesh` geometry (zero
## `PrimitiveMesh`es, zero extra texture VRAM, ref-counted static cache with
## zero-leak teardown).

signal pawn_returned_to_ship(mermaid: SeaMermaid, pawn: Pawn, ship: Node3D)

const GROUP := &"sea_mermaids"
const STRANDED_DISTANCE := 55.0
const RECALL_DISTANCE := 38.0
const SPAWN_AHEAD_DISTANCE := 12.0
const INTERACT_REACH := 4.5
const SMOKE_HEIGHT := 26.0

const RISE_START_Y := -2.4
const SUBMERGE_END_Y := -2.8
const RISE_SPEED := 2.2
const SUBMERGE_SPEED := 2.4
const CONCH_ORB_LOCAL := Vector3(0.55, 1.98, -0.14)

# Painterly sea-merfolk, kelp mantle, coral braid & glowing conch palette (sRGB).
const COL_SCALE_TEAL := Color(0.11, 0.56, 0.54)
const COL_SCALE_EMERALD := Color(0.14, 0.72, 0.52)
const COL_SCALE_BRIGHT := Color(0.26, 0.86, 0.72)
const COL_SCALE_DEEP := Color(0.06, 0.28, 0.34)
const COL_BELLY_PEARL := Color(0.58, 0.84, 0.78)
const COL_FIN_BASE := Color(0.08, 0.44, 0.48)
const COL_FIN_TIP := Color(0.32, 0.92, 0.80)

const COL_SKIN_HI := Color(0.56, 0.78, 0.72)
const COL_SKIN_MID := Color(0.38, 0.62, 0.58)
const COL_SKIN_SHADE := Color(0.22, 0.42, 0.43)

const COL_KELP_DARK := Color(0.06, 0.22, 0.16)
const COL_KELP_MID := Color(0.11, 0.38, 0.25)
const COL_KELP_EDGE := Color(0.22, 0.56, 0.36)

const COL_SHELL_CREAM := Color(0.92, 0.86, 0.74)
const COL_SHELL_ROSE := Color(0.84, 0.64, 0.58)
const COL_GOLD_CORD := Color(0.82, 0.66, 0.28)

const COL_HAIR_DEEP := Color(0.08, 0.26, 0.28)
const COL_HAIR_TEAL := Color(0.16, 0.50, 0.46)
const COL_CORAL_ROSE := Color(0.90, 0.42, 0.34)
const COL_CORAL_WARM := Color(0.96, 0.62, 0.44)

const COL_DRIFTWOOD_HI := Color(0.54, 0.45, 0.34)
const COL_DRIFTWOOD_LO := Color(0.30, 0.23, 0.17)

const COL_ORB_CORE := Color(0.68, 1.00, 0.94)
const COL_ORB_EDGE := Color(0.18, 0.94, 0.80)
const COL_EYE_GLOW := Color(0.54, 1.00, 0.95)
const COL_PEARL_GLOW := Color(0.76, 1.00, 0.92)

const COL_SMOKE_CORE := Color(0.44, 1.00, 0.92, 0.92)
const COL_SMOKE_MID := Color(0.14, 0.90, 0.72, 0.76)
const COL_SMOKE_HIGH := Color(0.09, 0.72, 0.58, 0.42)
const COL_SMOKE_TIP := Color(0.24, 0.88, 0.78, 0.02)

# Ref-counted static cache shared across all live SeaMermaids (0 extra VRAM).
static var _active_mermaids: int = 0
static var _figure_mesh: ArrayMesh = null
static var _smoke_mesh: ArrayMesh = null
static var _mote_mesh: ArrayMesh = null
static var _body_mat: StandardMaterial3D = null
static var _glow_mat: StandardMaterial3D = null
static var _smoke_mat: StandardMaterial3D = null

@export var auto_recall: bool = true

var target_ship: Node3D = null
var tracked_pawn: Pawn = null
var interactable: Interactable = null

var base_x: float = 0.0
var base_z: float = 0.0
var rise_offset: float = RISE_START_Y
var dismissed: bool = false

var _figure_pivot: Node3D = null
var _figure_mi: MeshInstance3D = null
var _smoke_plume: Node3D = null
var _smoke_mi: MeshInstance3D = null
var _conch_light: OmniLight3D = null
var _mist_particles: CPUParticles3D = null
var _clock: float = 0.0
var _base_yaw: float = 0.0


# ==============================================================================
# Static Helpers & Factories
# ==============================================================================

## True when `pawn` is a live unboarded swimmer at least `STRANDED_DISTANCE` m
## horizontally away from their non-sinking `ship`.
static func should_spawn_for_pawn(pawn: Pawn, ship: Node3D) -> bool:
	if pawn == null or not is_instance_valid(pawn) or pawn.dead:
		return false
	if pawn.platform != null or not pawn.is_swimming():
		return false
	if ship == null or not is_instance_valid(ship):
		return false
	if ship.get(&"is_sinking") == true:
		return false
	var dx := pawn.global_position.x - ship.global_position.x
	var dz := pawn.global_position.z - ship.global_position.z
	return Vector2(dx, dz).length() >= STRANDED_DISTANCE


## Spawn a SeaMermaid rising ~12 m ahead of a stranded swimming `pawn` in open water.
static func spawn_near_swimmer(parent: Node, pawn: Pawn, ship: Node3D) -> SeaMermaid:
	if pawn == null or not is_instance_valid(pawn):
		return null
	var fwd := pawn.facing()
	fwd.y = 0.0
	if fwd.length_squared() < 0.0001:
		fwd = Vector3.FORWARD
	else:
		fwd = fwd.normalized()
	var spawn_xz := pawn.global_position + fwd * SPAWN_AHEAD_DISTANCE
	var sy := Sea.height(spawn_xz.x, spawn_xz.z) if Sea != null else 0.0
	var world_pos := Vector3(spawn_xz.x, sy, spawn_xz.z)
	var mermaid := SeaMermaid.new()
	mermaid.name = "SeaMermaid"
	mermaid.target_ship = ship
	mermaid.tracked_pawn = pawn
	mermaid.base_x = world_pos.x
	mermaid.base_z = world_pos.z
	mermaid.position = world_pos
	if parent != null:
		parent.add_child(mermaid)
		if mermaid.is_inside_tree():
			mermaid.global_position = world_pos
	if Ocean.current != null:
		Ocean.current.add_foam(world_pos, 3.0, 0.78)
	Audio.play_sfx(&"splash_small", world_pos, -3.5)
	return mermaid


## Spawn a SeaMermaid directly at `world_pos` (ideal for showcases & tests).
static func spawn_at(parent: Node, world_pos: Vector3, ship: Node3D = null) -> SeaMermaid:
	var mermaid := SeaMermaid.new()
	mermaid.name = "SeaMermaid"
	mermaid.target_ship = ship
	mermaid.tracked_pawn = null
	mermaid.base_x = world_pos.x
	mermaid.base_z = world_pos.z
	var sy := Sea.height(world_pos.x, world_pos.z) if Sea != null else world_pos.y
	var placed := Vector3(world_pos.x, sy, world_pos.z)
	mermaid.position = placed
	if parent != null:
		parent.add_child(mermaid)
		if mermaid.is_inside_tree():
			mermaid.global_position = placed
	return mermaid


## Release all statically cached sculpted meshes and materials cleanly.
static func clear_shared_cache() -> void:
	_figure_mesh = null
	_smoke_mesh = null
	_mote_mesh = null
	_body_mat = null
	_glow_mat = null
	_smoke_mat = null


# ==============================================================================
# Lifecycle
# ==============================================================================

func _enter_tree() -> void:
	_active_mermaids += 1
	add_to_group(GROUP)


func _ready() -> void:
	if base_x == 0.0 and base_z == 0.0:
		base_x = global_position.x
		base_z = global_position.z
	if tracked_pawn != null and is_instance_valid(tracked_pawn):
		var to_p := tracked_pawn.global_position - Vector3(base_x, 0.0, base_z)
		if Vector2(to_p.x, to_p.z).length_squared() > 0.01:
			_base_yaw = atan2(-to_p.x, -to_p.z)
	else:
		_base_yaw = rotation.y

	_ensure_shared_assets()
	_build_visuals()
	_build_interactable()
	step_mermaid(0.0)


func _exit_tree() -> void:
	_release_local_refs()
	_active_mermaids = maxi(0, _active_mermaids - 1)
	if _active_mermaids == 0:
		clear_shared_cache()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		_release_local_refs()


func _physics_process(delta: float) -> void:
	step_mermaid(delta)


func _release_local_refs() -> void:
	if _figure_mi != null and is_instance_valid(_figure_mi):
		if _figure_mi.mesh != null:
			for si in _figure_mi.mesh.get_surface_count():
				_figure_mi.set_surface_override_material(si, null)
		_figure_mi.mesh = null
		_figure_mi.material_override = null
	if _smoke_mi != null and is_instance_valid(_smoke_mi):
		_smoke_mi.mesh = null
		_smoke_mi.material_override = null
	if _mist_particles != null and is_instance_valid(_mist_particles):
		_mist_particles.emitting = false
		_mist_particles.visible = false
		_mist_particles.material_override = null
	_figure_pivot = null
	_figure_mi = null
	_smoke_plume = null
	_smoke_mi = null
	_conch_light = null
	_mist_particles = null


# ==============================================================================
# Public Interaction, Warp & Simulation API
# ==============================================================================

## Host-authoritative warp returning `pawn` cleanly onto their ship's main deck.
func return_pawn_to_ship(pawn: Pawn) -> bool:
	if not Net.is_host() or dismissed:
		return false
	if pawn == null or not is_instance_valid(pawn) or pawn.dead:
		return false
	var ship := _resolve_return_ship(pawn)
	if ship == null or not is_instance_valid(ship) or not (ship is PhysicsBody3D):
		return false

	var deck_local := Vector3(0.0, 1.25, -1.5)
	if ship.has_method(&"ship_point"):
		deck_local = ship.call(&"ship_point", deck_local) as Vector3

	var dropped_cargo := false
	if pawn.carried != null:
		pawn.drop_carried(0.4)
		dropped_cargo = true
	if pawn.station != null:
		pawn.leave_station()

	var depart_pos := global_position if is_inside_tree() else position
	pawn.board(ship as PhysicsBody3D, deck_local)

	if dropped_cargo:
		Game.post_notice("Returned aboard your ship via Sea Mermaid! (Carried cargo left behind in the sea.)")
	else:
		Game.post_notice("Returned aboard your ship via Sea Mermaid!")

	if Ocean.current != null:
		Ocean.current.add_foam(depart_pos, 4.2, 0.95)
	Audio.play_sfx(&"splash_small", depart_pos, -1.0)
	Audio.play_stinger(&"discovery", -3.0)

	_notify_crew_return(ship, pawn)
	pawn_returned_to_ship.emit(self, pawn, ship)
	dismiss()
	return true


## Gently submerge and despawn this SeaMermaid beacon.
func dismiss() -> void:
	if dismissed:
		return
	dismissed = true
	if interactable != null and is_instance_valid(interactable):
		interactable.enabled = false
	if _mist_particles != null and is_instance_valid(_mist_particles):
		_mist_particles.emitting = false


## Advance wave buoyancy, graceful rise/submerge, emerald smoke rotation & recall check.
func step_mermaid(delta: float) -> void:
	var dt := maxf(delta, 0.0)
	_clock += dt

	if dismissed:
		rise_offset = move_toward(rise_offset, SUBMERGE_END_Y, SUBMERGE_SPEED * dt)
	else:
		rise_offset = move_toward(rise_offset, 0.0, RISE_SPEED * dt)

	var sea_y := Sea.height(base_x, base_z) if Sea != null else 0.0
	var sx0 := Sea.height(base_x - 1.2, base_z) if Sea != null else sea_y
	var sx1 := Sea.height(base_x + 1.2, base_z) if Sea != null else sea_y
	var sz0 := Sea.height(base_x, base_z - 1.2) if Sea != null else sea_y
	var sz1 := Sea.height(base_x, base_z + 1.2) if Sea != null else sea_y

	# Track tracked_pawn gently with yaw so the welcoming merfolk always faces the swimmer.
	if not dismissed and tracked_pawn != null and is_instance_valid(tracked_pawn):
		var to_p := tracked_pawn.global_position - Vector3(base_x, sea_y, base_z)
		if Vector2(to_p.x, to_p.z).length_squared() > 0.25:
			var want_yaw := atan2(-to_p.x, -to_p.z)
			_base_yaw = lerp_angle(_base_yaw, want_yaw, clampf(dt * 2.2, 0.0, 1.0))

	var target_pos := Vector3(base_x, sea_y, base_z)
	if is_inside_tree():
		global_position = target_pos
	else:
		position = target_pos
	# Keep root strictly upright (zero X/Z tilt) so SmokePlume always rises vertically!
	rotation = Vector3(0.0, _base_yaw, 0.0)

	var emerge := clampf((rise_offset - RISE_START_Y) / absf(RISE_START_Y), 0.0, 1.0)
	var bob_y := sin(_clock * 1.85) * 0.055 * emerge
	var sway_x := clampf(-(sz1 - sz0) / 5.5 + sin(_clock * 1.35) * 0.035, -0.14, 0.14)
	var sway_z := clampf((sx1 - sx0) / 5.5 + cos(_clock * 1.12) * 0.035, -0.14, 0.14)

	if _figure_pivot != null and is_instance_valid(_figure_pivot):
		_figure_pivot.position = Vector3(0.0, rise_offset + bob_y, 0.0)
		_figure_pivot.rotation = Vector3(sway_x, sin(_clock * 0.65) * 0.04, sway_z)

	if _smoke_plume != null and is_instance_valid(_smoke_plume):
		var plume_y := CONCH_ORB_LOCAL.y - 0.04 + rise_offset * 0.65 + sin(_clock * 1.4) * 0.08
		_smoke_plume.position = Vector3(CONCH_ORB_LOCAL.x, plume_y, CONCH_ORB_LOCAL.z)
		_smoke_plume.rotation = Vector3(0.0, _clock * 0.55, 0.0)
		var plume_s := lerpf(0.22, 1.0, emerge) if not dismissed else maxf(0.02, emerge)
		_smoke_plume.scale = Vector3(plume_s, plume_s, plume_s)
		_smoke_plume.visible = (not dismissed) or emerge > 0.04

	if _conch_light != null and is_instance_valid(_conch_light):
		var pulse := 2.45 + sin(_clock * 3.1) * 0.35 + cos(_clock * 5.7) * 0.14
		var light_scale := lerpf(0.35, 1.0, emerge) if not dismissed else emerge
		_conch_light.light_energy = maxf(0.0, pulse * light_scale)
		_conch_light.visible = (not dismissed) or emerge > 0.04

	if auto_recall and not dismissed and Net.is_host() and tracked_pawn != null:
		if not is_instance_valid(tracked_pawn) or tracked_pawn.dead or tracked_pawn.platform != null:
			dismiss()
		elif target_ship != null and is_instance_valid(target_ship):
			var d_xz := Vector2(
				tracked_pawn.global_position.x - target_ship.global_position.x,
				tracked_pawn.global_position.z - target_ship.global_position.z
			).length()
			if d_xz < RECALL_DISTANCE:
				dismiss()

	if dismissed and rise_offset <= SUBMERGE_END_Y + 0.02 and is_inside_tree():
		queue_free()


## Snap immediately to full waist-high emergence (ideal for deterministic showcases & tests).
func force_emerged() -> void:
	dismissed = false
	rise_offset = 0.0
	if interactable != null and is_instance_valid(interactable):
		interactable.enabled = true
	if _mist_particles != null and is_instance_valid(_mist_particles):
		_mist_particles.emitting = true
	step_mermaid(0.0)


## Orient the merfolk figure cleanly around the vertical Y axis.
func set_facing_yaw(yaw: float) -> void:
	_base_yaw = yaw
	rotation = Vector3(0.0, _base_yaw, 0.0)


## Total sculpted triangle count across the merfolk figure and emerald smoke beacon.
func get_triangle_count() -> int:
	_ensure_shared_assets()
	return _count_mesh_tris(_figure_mesh) + _count_mesh_tris(_smoke_mesh)


func get_figure_triangle_count() -> int:
	_ensure_shared_assets()
	return _count_mesh_tris(_figure_mesh)


func get_smoke_triangle_count() -> int:
	_ensure_shared_assets()
	return _count_mesh_tris(_smoke_mesh)


func get_mote_triangle_count() -> int:
	_ensure_shared_assets()
	return _count_mesh_tris(_mote_mesh)


func get_figure_mesh_instance() -> MeshInstance3D:
	return _figure_mi


func get_smoke_mesh_instance() -> MeshInstance3D:
	return _smoke_mi


func get_smoke_plume() -> Node3D:
	return _smoke_plume


func get_conch_light() -> OmniLight3D:
	return _conch_light


func get_mist_particles() -> CPUParticles3D:
	return _mist_particles


# ==============================================================================
# Internal Helpers
# ==============================================================================

func _on_interacted(actor: Node) -> void:
	if actor is Pawn:
		return_pawn_to_ship(actor as Pawn)


func _resolve_return_ship(pawn: Pawn) -> Node3D:
	if target_ship != null and is_instance_valid(target_ship) and target_ship.get(&"is_sinking") != true:
		return target_ship
	var tree := get_tree()
	if tree == null:
		return null
	var want_faction := &"player"
	var cc := pawn.get_node_or_null(^"CombatComponent")
	if cc != null and cc.get(&"faction") != null:
		want_faction = StringName(cc.get(&"faction"))
	var fallback: Node3D = null
	for node in tree.get_nodes_in_group(&"ship"):
		if not (node is Node3D) or not is_instance_valid(node):
			continue
		var s := node as Node3D
		if s.get(&"is_sinking") == true:
			continue
		var f: Variant = s.get(&"faction")
		if f != null and StringName(f) == want_faction:
			return s
		if fallback == null:
			fallback = s
	return fallback


func _notify_crew_return(ship: Node3D, pawn: Pawn) -> void:
	var tree := get_tree()
	if tree == null:
		return
	var nearest: CrewBrain = null
	var best_d := INF
	for node in tree.get_nodes_in_group(&"crew_brains"):
		var cb := node as CrewBrain
		if cb == null or not is_instance_valid(cb) or cb.pawn == null or cb.pawn.dead:
			continue
		var same_ship := (cb.ship == ship) or (cb.pawn.platform == ship)
		var dist := cb.pawn.global_position.distance_to(pawn.global_position)
		if not same_ship and dist > 28.0:
			continue
		if dist < best_d:
			best_d = dist
			nearest = cb
	if nearest != null:
		nearest.notify_mermaid_return()


func _build_visuals() -> void:
	_figure_pivot = Node3D.new()
	_figure_pivot.name = "FigurePivot"
	_figure_pivot.position = Vector3(0.0, rise_offset, 0.0)
	add_child(_figure_pivot)

	_figure_mi = MeshInstance3D.new()
	_figure_mi.name = "MerfolkFigure"
	_figure_mi.mesh = _figure_mesh
	_figure_mi.set_surface_override_material(0, _body_mat)
	if _figure_mesh.get_surface_count() > 1:
		_figure_mi.set_surface_override_material(1, _glow_mat)
	_figure_mi.visibility_range_end = 280.0
	_figure_pivot.add_child(_figure_mi)

	_conch_light = OmniLight3D.new()
	_conch_light.name = "ConchLight"
	_conch_light.position = CONCH_ORB_LOCAL
	_conch_light.light_color = Color(0.24, 0.96, 0.84)
	_conch_light.light_energy = 2.45
	_conch_light.omni_range = 10.5
	_conch_light.omni_attenuation = 1.35
	_conch_light.shadow_enabled = false
	_figure_pivot.add_child(_conch_light)

	_mist_particles = CPUParticles3D.new()
	_mist_particles.name = "SeaMistSparkles"
	_mist_particles.position = CONCH_ORB_LOCAL + Vector3(0.0, -0.10, 0.0)
	_mist_particles.emitting = true
	_mist_particles.amount = 20
	_mist_particles.lifetime = 2.2
	_mist_particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	_mist_particles.emission_sphere_radius = 0.55
	_mist_particles.direction = Vector3(0.0, 1.0, 0.0)
	_mist_particles.spread = 28.0
	_mist_particles.initial_velocity_min = 0.55
	_mist_particles.initial_velocity_max = 1.35
	_mist_particles.gravity = Vector3(0.0, 0.40, 0.0)
	_mist_particles.scale_amount_min = 0.65
	_mist_particles.scale_amount_max = 1.30
	_mist_particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mist_particles.mesh = _mote_mesh
	_mist_particles.material_override = _glow_mat
	_figure_pivot.add_child(_mist_particles)

	_smoke_plume = Node3D.new()
	_smoke_plume.name = "SmokePlume"
	_smoke_plume.position = CONCH_ORB_LOCAL + Vector3(0.0, 0.08, 0.0)
	add_child(_smoke_plume)

	_smoke_mi = MeshInstance3D.new()
	_smoke_mi.name = "SmokeBeaconMesh"
	_smoke_mi.mesh = _smoke_mesh
	_smoke_mi.material_override = _smoke_mat
	_smoke_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_smoke_mi.visibility_range_end = 560.0
	_smoke_plume.add_child(_smoke_mi)


func _build_interactable() -> void:
	interactable = Interactable.create("Return to ship", 1.55)
	interactable.name = "MermaidInteractable"
	interactable.position = Vector3(0.0, 1.15, 0.0)
	interactable.reach = INTERACT_REACH
	interactable.interacted.connect(_on_interacted)
	add_child(interactable)


static func _count_mesh_tris(m: ArrayMesh) -> int:
	if m == null:
		return 0
	var total := 0
	for si in m.get_surface_count():
		var arr := m.surface_get_arrays(si)
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		total += floori(float(verts.size()) / 3.0)
	return total


# ==============================================================================
# Shared Sculpted Assets & Materials (Zero PrimitiveMeshes, Zero Extra VRAM)
# ==============================================================================

static func _ensure_shared_assets() -> void:
	if _body_mat == null:
		_body_mat = StandardMaterial3D.new()
		_body_mat.albedo_color = Color.WHITE
		_body_mat.vertex_color_use_as_albedo = true
		_body_mat.vertex_color_is_srgb = true
		_body_mat.roughness = 0.44
		_body_mat.metallic = 0.14
		_body_mat.clearcoat = 0.36
		_body_mat.clearcoat_roughness = 0.24
	if _glow_mat == null:
		_glow_mat = StandardMaterial3D.new()
		_glow_mat.albedo_color = Color.WHITE
		_glow_mat.vertex_color_use_as_albedo = true
		_glow_mat.vertex_color_is_srgb = true
		_glow_mat.roughness = 0.18
		_glow_mat.metallic = 0.08
		_glow_mat.emission_enabled = true
		_glow_mat.emission = Color(0.22, 0.96, 0.84)
		_glow_mat.emission_energy_multiplier = 2.35
	if _smoke_mat == null:
		_smoke_mat = StandardMaterial3D.new()
		_smoke_mat.albedo_color = Color(0.95, 1.0, 0.98, 0.44)
		_smoke_mat.vertex_color_use_as_albedo = true
		_smoke_mat.vertex_color_is_srgb = true
		_smoke_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_smoke_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_smoke_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		_smoke_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_smoke_mat.render_priority = 2
	if _figure_mesh == null:
		_figure_mesh = _build_merfolk_figure_mesh()
	if _smoke_mesh == null:
		_smoke_mesh = _build_emerald_smoke_beacon_mesh()
	if _mote_mesh == null:
		_mote_mesh = _build_diamond_mote_mesh()


static func _build_merfolk_figure_mesh() -> ArrayMesh:
	var body_st := SurfaceTool.new()
	body_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var glow_st := SurfaceTool.new()
	glow_st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# 1. Coiled iridescent teal-and-emerald scaled merfolk tail & twin crescent flukes
	#    sweeping underwater (-1.58 m) and arching gracefully out beside the waterline.
	_sculpt_merfolk_tail(body_st)

	# 2. Broad heroic torso, collarbones, sculpted neck & scalloped waist fin skirts.
	_sculpt_merfolk_torso_and_waist_fins(body_st)

	# 3. Draped dark-jade sea-kelp shoulder mantle & carved pearl-and-shell medallion.
	_sculpt_kelp_mantle_and_medallion(body_st, glow_st)

	# 4. Sculpted serene head, aquatic fin-ears, coral brow circlet, glowing aquamarine
	#    eyes, and flowing braided sea-coral hair over both shoulders.
	_sculpt_head_face_and_braided_hair(body_st, glow_st)

	# 5. Raised right arm gripping the carved driftwood-and-coral beacon staff crowned
	#    with a blazing faceted sea-glass conch orb, plus welcoming outstretched left arm!
	_sculpt_arms_and_conch_staff(body_st, glow_st)

	var mesh := body_st.commit()
	glow_st.commit(mesh)
	return mesh


static func _sculpt_merfolk_tail(st: SurfaceTool) -> void:
	# 15-station curving spine from waist (y=0.22) plunging to y=-1.52 then sweeping
	# gracefully leftward and upward so the crescent tail flukes crest out of the waves!
	var centers: Array[Vector3] = [
		Vector3(0.00, 0.22, 0.00),
		Vector3(-0.02, 0.00, 0.06),
		Vector3(-0.05, -0.26, 0.16),
		Vector3(-0.08, -0.56, 0.26),
		Vector3(-0.14, -0.88, 0.34),
		Vector3(-0.24, -1.18, 0.36),
		Vector3(-0.38, -1.42, 0.30),
		Vector3(-0.56, -1.54, 0.16),
		Vector3(-0.74, -1.46, -0.02),
		Vector3(-0.88, -1.24, -0.18),
		Vector3(-0.98, -0.94, -0.30),
		Vector3(-1.02, -0.62, -0.36),
		Vector3(-0.98, -0.32, -0.36),
		Vector3(-0.90, -0.08, -0.32),
		Vector3(-0.82, 0.10, -0.26),
	]
	var radii: Array[Vector2] = [
		Vector2(0.24, 0.18),
		Vector2(0.28, 0.22),
		Vector2(0.29, 0.24),
		Vector2(0.27, 0.23),
		Vector2(0.25, 0.21),
		Vector2(0.23, 0.19),
		Vector2(0.20, 0.17),
		Vector2(0.18, 0.15),
		Vector2(0.16, 0.14),
		Vector2(0.145, 0.125),
		Vector2(0.130, 0.112),
		Vector2(0.112, 0.098),
		Vector2(0.096, 0.084),
		Vector2(0.082, 0.072),
		Vector2(0.068, 0.060),
	]
	var colors: Array[Color] = []
	for i in centers.size():
		var t := float(i) / float(centers.size() - 1)
		var band := 0.5 + 0.5 * sin(float(i) * 1.45)
		var c := COL_SCALE_TEAL.lerp(COL_SCALE_EMERALD, band)
		c = c.lerp(COL_SCALE_DEEP, clampf(sin(t * PI) * 0.45, 0.0, 0.45))
		if i >= centers.size() - 4:
			c = c.lerp(COL_SCALE_BRIGHT, 0.45)
		colors.append(c)

	_append_curved_loft(st, centers, radii, colors, 12, true, true, COL_BELLY_PEARL)

	# Dorsal ridge fin blades tracing the outer curve of the merfolk tail.
	var fin_indices: Array[int] = [2, 4, 6, 8, 10, 12]
	for idx in fin_indices:
		var p0 := centers[idx]
		var p1 := centers[idx + 1]
		var tangent := (p1 - p0).normalized()
		var out_dir := Vector3(0.0, -0.35, 0.92).normalized()
		if idx >= 8:
			out_dir = Vector3(-0.88, -0.25, -0.40).normalized()
		var base_a := p0 + out_dir * (radii[idx].y * 0.85)
		var base_b := p1 + out_dir * (radii[idx + 1].y * 0.85)
		var tip := base_a.lerp(base_b, 0.65) + out_dir * 0.24 - tangent * 0.08
		var side_n := tangent.cross(out_dir).normalized()
		var thick := side_n * 0.022
		var ref := base_a.lerp(base_b, 0.5)
		_emit_outward_tri(st, base_a + thick, base_b + thick, tip, ref, COL_FIN_BASE, COL_FIN_BASE, COL_FIN_TIP)
		_emit_outward_tri(st, base_b - thick, base_a - thick, tip, ref, COL_FIN_BASE, COL_FIN_BASE, COL_FIN_TIP)
		_emit_outward_tri(st, base_a - thick, base_a + thick, tip, ref, COL_FIN_BASE, COL_FIN_BASE, COL_FIN_TIP)
		_emit_outward_tri(st, base_b + thick, base_b - thick, tip, ref, COL_FIN_BASE, COL_FIN_BASE, COL_FIN_TIP)

	# Twin sweeping crescent tail flukes rising proudly above the waves at the tail tip.
	var peduncle := centers[centers.size() - 1]
	var ped_dir := (centers[centers.size() - 1] - centers[centers.size() - 2]).normalized()
	var fluke_side := ped_dir.cross(Vector3(0.0, 0.0, 1.0))
	if fluke_side.length_squared() < 0.01:
		fluke_side = Vector3.RIGHT
	else:
		fluke_side = fluke_side.normalized()
	var fluke_norm := ped_dir.cross(fluke_side).normalized()

	for sign_v: float in [-1.0, 1.0]:
		var lobe_pts: Array[Vector3] = []
		var lobe_radii: Array[Vector2] = []
		var lobe_cols: Array[Color] = []
		var segs := 6
		for s in segs + 1:
			var u := float(s) / float(segs)
			# Sweeping crescent arc curving outward and trailing cleanly to a tapered point.
			var spread := sin(u * PI * 0.88) * 0.62 * sign_v
			var reach := u * 0.62 - pow(u, 2.2) * 0.22
			var arch := sin(u * PI) * 0.14
			var pt := peduncle + ped_dir * reach + fluke_side * spread + fluke_norm * arch
			var rx := lerpf(0.075, 0.016, pow(u, 1.25))
			var ry := lerpf(0.115, 0.020, pow(u, 1.1))
			lobe_pts.append(pt)
			lobe_radii.append(Vector2(rx, ry))
			lobe_cols.append(COL_FIN_BASE.lerp(COL_FIN_TIP, pow(u, 0.78)))
		_append_curved_loft(st, lobe_pts, lobe_radii, lobe_cols, 8, true, true, COL_SCALE_BRIGHT)


static func _sculpt_merfolk_torso_and_waist_fins(st: SurfaceTool) -> void:
	# Heroic waist-to-neck loft with anatomical taper, broad ribcage, pectoral crest & neck.
	var rings: Array[Array] = [
		[0.18, 0.23, 0.17, 0.00, COL_SCALE_TEAL],
		[0.32, 0.21, 0.15, -0.01, COL_SKIN_SHADE.lerp(COL_SCALE_TEAL, 0.45)],
		[0.48, 0.24, 0.16, -0.02, COL_SKIN_SHADE],
		[0.66, 0.29, 0.18, -0.02, COL_SKIN_MID],
		[0.84, 0.34, 0.19, -0.02, COL_SKIN_HI],
		[0.98, 0.35, 0.17, -0.01, COL_SKIN_HI],
		[1.06, 0.22, 0.13, 0.00, COL_SKIN_MID],
		[1.14, 0.11, 0.10, -0.01, COL_SKIN_MID],
		[1.24, 0.095, 0.095, -0.01, COL_SKIN_HI],
	]
	_append_vertical_profile_loft(st, rings, 12, true, true)

	# Scalloped waist/hip fin skirts fanning around the scale-to-skin transition (y=0.22).
	var fin_angles: Array[float] = [-2.4, -1.6, -0.8, 0.8, 1.6, 2.4]
	for ang in fin_angles:
		var dir := Vector3(sin(ang), -0.32, cos(ang)).normalized()
		var tan_v := Vector3(cos(ang), 0.0, -sin(ang)).normalized()
		var root := Vector3(sin(ang) * 0.21, 0.24, cos(ang) * 0.16)
		var p_l := root - tan_v * 0.11 + Vector3(0.0, -0.06, 0.0)
		var p_r := root + tan_v * 0.11 + Vector3(0.0, -0.06, 0.0)
		var tip := root + dir * 0.32
		var n_out := Vector3(sin(ang), 0.35, cos(ang)).normalized()
		var off := n_out * 0.018
		var ref := root + Vector3(0.0, -0.08, 0.0)
		_emit_outward_tri(st, p_l + off, p_r + off, tip, ref, COL_FIN_BASE, COL_FIN_BASE, COL_FIN_TIP)
		_emit_outward_tri(st, p_r - off, p_l - off, tip, ref, COL_FIN_BASE, COL_FIN_BASE, COL_FIN_TIP)
		_emit_outward_tri(st, root + off, p_l + off, tip, ref, COL_SCALE_BRIGHT, COL_FIN_BASE, COL_FIN_TIP)
		_emit_outward_tri(st, p_r + off, root + off, tip, ref, COL_FIN_BASE, COL_SCALE_BRIGHT, COL_FIN_TIP)


static func _sculpt_kelp_mantle_and_medallion(body_st: SurfaceTool, glow_st: SurfaceTool) -> void:
	# Draped dark-jade sea-kelp shoulder mantle pauldrons + 6 layered cascading kelp fronds.
	for sx: float in [-1.0, 1.0]:
		var pauldron_pts: Array[Vector3] = [
			Vector3(sx * 0.12, 1.06, 0.04),
			Vector3(sx * 0.26, 1.04, 0.01),
			Vector3(sx * 0.37, 0.96, -0.01),
			Vector3(sx * 0.42, 0.84, 0.02),
		]
		var pauldron_r: Array[Vector2] = [
			Vector2(0.11, 0.10),
			Vector2(0.14, 0.13),
			Vector2(0.13, 0.12),
			Vector2(0.06, 0.08),
		]
		var pauldron_c: Array[Color] = [COL_KELP_MID, COL_KELP_EDGE, COL_KELP_MID, COL_KELP_DARK]
		_append_curved_loft(body_st, pauldron_pts, pauldron_r, pauldron_c, 8, true, true, COL_KELP_DARK)

	# Six overlapping sculpted sea-kelp mantle fronds cascading across back, chest & flanks.
	var frond_specs: Array[Array] = [
		# [start_x, start_z, mid_x, mid_z, tip_x, tip_y, tip_z, width]
		[-0.32, 0.04, -0.38, 0.14, -0.34, 0.34, 0.18, 0.095],
		[-0.14, 0.14, -0.18, 0.24, -0.16, 0.26, 0.26, 0.115],
		[0.00, 0.16, 0.02, 0.26, 0.04, 0.22, 0.28, 0.120],
		[0.16, 0.14, 0.20, 0.23, 0.18, 0.28, 0.25, 0.110],
		[0.32, 0.04, 0.38, 0.13, 0.34, 0.36, 0.16, 0.092],
		[-0.22, -0.12, -0.20, -0.21, -0.14, 0.56, -0.20, 0.082],
	]
	for fr in frond_specs:
		var p0 := Vector3(float(fr[0]), 0.99, float(fr[1]))
		var p1 := Vector3(float(fr[2]), 0.72, float(fr[3]))
		var p2 := Vector3(float(fr[4]), float(fr[5]), float(fr[6]))
		var w := float(fr[7])
		var pts: Array[Vector3] = [p0, p0.lerp(p1, 0.55), p1, p1.lerp(p2, 0.55), p2]
		var rads: Array[Vector2] = [
			Vector2(w * 0.72, 0.028),
			Vector2(w * 1.00, 0.032),
			Vector2(w * 0.95, 0.028),
			Vector2(w * 0.65, 0.022),
			Vector2(0.018, 0.014),
		]
		var cols: Array[Color] = [COL_KELP_MID, COL_KELP_EDGE, COL_KELP_MID, COL_KELP_DARK, COL_KELP_EDGE]
		_append_curved_loft(body_st, pts, rads, cols, 6, true, true, COL_KELP_DARK)

	# Carved Pearl-and-Shell Breastplate Medallion on chest + woven gold neck cord.
	var med_c := Vector3(0.0, 0.80, -0.195)
	for ri in 7:
		var frac := (float(ri) / 6.0) * 2.0 - 1.0
		var a := frac * 1.12
		var dir := Vector3(sin(a), -cos(a) * 0.85, -0.14).normalized()
		var rib_end := med_c + dir * (0.145 - absf(frac) * 0.028)
		var col_r := COL_SHELL_CREAM.lerp(COL_SHELL_ROSE, absf(frac) * 0.55)
		_append_tapered_tube(body_st, med_c, rib_end, 0.024, 0.014, 5, COL_SHELL_CREAM, col_r)

	# Woven gold-and-coral collar necklace suspending the medallion.
	var cord_pts: Array[Vector3] = [
		Vector3(-0.18, 1.02, -0.05),
		Vector3(-0.14, 0.92, -0.16),
		Vector3(0.00, 0.84, -0.205),
		Vector3(0.14, 0.92, -0.16),
		Vector3(0.18, 1.02, -0.05),
	]
	var cord_r: Array[Vector2] = [
		Vector2(0.018, 0.018),
		Vector2(0.020, 0.020),
		Vector2(0.024, 0.024),
		Vector2(0.020, 0.020),
		Vector2(0.018, 0.018),
	]
	var cord_c: Array[Color] = [COL_GOLD_CORD, COL_GOLD_CORD, COL_CORAL_WARM, COL_GOLD_CORD, COL_GOLD_CORD]
	_append_curved_loft(body_st, cord_pts, cord_r, cord_c, 6, true, true, COL_GOLD_CORD)

	# Central luminous sea-pearl cabochon on Surface 1 (_glow_mat).
	_append_faceted_bipyramid(glow_st, med_c + Vector3(0.0, 0.01, -0.032), 0.048, 0.054, 8, COL_PEARL_GLOW, COL_ORB_EDGE)


static func _sculpt_head_face_and_braided_hair(body_st: SurfaceTool, glow_st: SurfaceTool) -> void:
	# Sculpted serene head with tapered jaw, cheekbones, brow & crown (y = 1.22 .. 1.60).
	var head_rings: Array[Array] = [
		[1.22, 0.068, 0.078, -0.020, COL_SKIN_SHADE],
		[1.28, 0.105, 0.115, -0.018, COL_SKIN_MID],
		[1.36, 0.128, 0.138, -0.012, COL_SKIN_HI],
		[1.44, 0.132, 0.145, -0.005, COL_SKIN_HI],
		[1.52, 0.118, 0.132, 0.002, COL_SKIN_MID],
		[1.58, 0.075, 0.088, 0.006, COL_HAIR_TEAL],
	]
	_append_vertical_profile_loft(body_st, head_rings, 12, true, true)

	# Sculpted nose bridge & brow ridge.
	_append_tapered_tube(body_st, Vector3(0.0, 1.41, -0.136), Vector3(0.0, 1.335, -0.158),
		0.016, 0.012, 5, COL_SKIN_HI, COL_SKIN_MID)

	# Serene glowing aquamarine eyes set beneath the brow on Surface 1 (_glow_mat).
	for sx: float in [-1.0, 1.0]:
		var eye_c := Vector3(sx * 0.050, 1.388, -0.132)
		_append_faceted_bipyramid(glow_st, eye_c, 0.022, 0.012, 6, COL_EYE_GLOW, COL_ORB_EDGE)

	# Twin swept aquatic fin-ears flaring gracefully from temples.
	for sx: float in [-1.0, 1.0]:
		var ear_a := Vector3(sx * 0.122, 1.36, -0.01)
		var ear_b := Vector3(sx * 0.122, 1.44, 0.01)
		var ear_tip := Vector3(sx * 0.235, 1.49, 0.08)
		var ref := Vector3(0.0, 1.40, 0.0)
		var thick := Vector3(0.0, 0.0, 0.014)
		_emit_outward_tri(body_st, ear_a + thick, ear_b + thick, ear_tip, ref, COL_FIN_BASE, COL_FIN_BASE, COL_FIN_TIP)
		_emit_outward_tri(body_st, ear_b - thick, ear_a - thick, ear_tip, ref, COL_FIN_BASE, COL_FIN_BASE, COL_FIN_TIP)
		_emit_outward_tri(body_st, ear_a - thick, ear_a + thick, ear_tip, ref, COL_SKIN_MID, COL_SKIN_MID, COL_FIN_TIP)
		_emit_outward_tri(body_st, ear_b + thick, ear_b - thick, ear_tip, ref, COL_SKIN_MID, COL_SKIN_MID, COL_FIN_TIP)

	# Carved coral-and-shell brow circlet tiara across the forehead.
	var tiara_pts: Array[Vector3] = [
		Vector3(-0.125, 1.46, 0.02),
		Vector3(-0.095, 1.47, -0.10),
		Vector3(0.000, 1.495, -0.145),
		Vector3(0.095, 1.47, -0.10),
		Vector3(0.125, 1.46, 0.02),
	]
	var tiara_r: Array[Vector2] = [
		Vector2(0.015, 0.015),
		Vector2(0.018, 0.020),
		Vector2(0.024, 0.028),
		Vector2(0.018, 0.020),
		Vector2(0.015, 0.015),
	]
	var tiara_c: Array[Color] = [COL_CORAL_ROSE, COL_CORAL_WARM, COL_SHELL_CREAM, COL_CORAL_WARM, COL_CORAL_ROSE]
	_append_curved_loft(body_st, tiara_pts, tiara_r, tiara_c, 6, true, true, COL_CORAL_ROSE)

	# Flowing braided sea-coral hair locks cascading over shoulders & back (7 curved strands).
	var strands: Array[Array] = [
		# Left shoulder front braid
		[
			Vector3(-0.10, 1.54, -0.02),
			Vector3(-0.18, 1.38, -0.03),
			Vector3(-0.24, 1.15, -0.09),
			Vector3(-0.22, 0.90, -0.15),
			Vector3(-0.17, 0.68, -0.17),
		],
		# Right shoulder front braid
		[
			Vector3(0.10, 1.54, -0.02),
			Vector3(0.18, 1.38, -0.03),
			Vector3(0.24, 1.15, -0.09),
			Vector3(0.22, 0.90, -0.14),
			Vector3(0.18, 0.68, -0.15),
		],
		# Flowing outer-left back wave
		[
			Vector3(-0.09, 1.56, 0.05),
			Vector3(-0.19, 1.36, 0.14),
			Vector3(-0.26, 1.06, 0.21),
			Vector3(-0.28, 0.72, 0.24),
			Vector3(-0.24, 0.44, 0.28),
		],
		# Flowing center-left back lock
		[
			Vector3(-0.04, 1.59, 0.06),
			Vector3(-0.10, 1.36, 0.18),
			Vector3(-0.13, 1.04, 0.26),
			Vector3(-0.14, 0.68, 0.30),
			Vector3(-0.10, 0.38, 0.34),
		],
		# Central flowing back crest
		[
			Vector3(0.00, 1.60, 0.07),
			Vector3(0.00, 1.36, 0.20),
			Vector3(0.00, 1.02, 0.29),
			Vector3(0.02, 0.64, 0.33),
			Vector3(0.04, 0.34, 0.38),
		],
		# Flowing center-right back lock
		[
			Vector3(0.05, 1.59, 0.06),
			Vector3(0.11, 1.36, 0.18),
			Vector3(0.15, 1.04, 0.26),
			Vector3(0.16, 0.68, 0.29),
			Vector3(0.14, 0.40, 0.33),
		],
		# Flowing outer-right back wave
		[
			Vector3(0.10, 1.55, 0.05),
			Vector3(0.20, 1.35, 0.14),
			Vector3(0.27, 1.06, 0.20),
			Vector3(0.28, 0.74, 0.23),
			Vector3(0.25, 0.46, 0.26),
		],
	]
	for si in strands.size():
		var pts: Array[Vector3] = []
		for v in strands[si]:
			pts.append(v as Vector3)
		var is_braid := si < 2
		var r_base := 0.052 if is_braid else 0.066
		var rads: Array[Vector2] = [
			Vector2(r_base, r_base * 0.9),
			Vector2(r_base * 1.05, r_base * 0.92),
			Vector2(r_base * 0.92, r_base * 0.85),
			Vector2(r_base * 0.68, r_base * 0.65),
			Vector2(0.022, 0.020),
		]
		var cols: Array[Color] = [
			COL_HAIR_DEEP,
			COL_HAIR_TEAL,
			COL_CORAL_ROSE.lerp(COL_HAIR_TEAL, 0.45) if is_braid else COL_HAIR_TEAL,
			COL_HAIR_DEEP.lerp(COL_CORAL_ROSE, 0.35),
			COL_CORAL_WARM if is_braid else COL_FIN_TIP,
		]
		_append_curved_loft(body_st, pts, rads, cols, 6, true, true, COL_HAIR_DEEP)
		if is_braid:
			# Coral beads woven along the front shoulder braids.
			for bi: int in [2, 3]:
				_append_faceted_bipyramid(body_st, pts[bi], 0.036, 0.028, 6, COL_CORAL_WARM, COL_CORAL_ROSE)


static func _sculpt_arms_and_conch_staff(body_st: SurfaceTool, glow_st: SurfaceTool) -> void:
	# 1. Raised right arm gripping the beacon staff firmly aloft!
	var r_arm_pts: Array[Vector3] = [
		Vector3(0.32, 0.96, -0.02),
		Vector3(0.42, 1.01, -0.05),
		Vector3(0.50, 1.12, -0.09),
		Vector3(0.53, 1.28, -0.12),
		Vector3(0.55, 1.44, -0.14),
	]
	var r_arm_r: Array[Vector2] = [
		Vector2(0.088, 0.082),
		Vector2(0.078, 0.074),
		Vector2(0.068, 0.066),
		Vector2(0.062, 0.060),
		Vector2(0.058, 0.058),
	]
	var r_arm_c: Array[Color] = [COL_SKIN_HI, COL_SKIN_MID, COL_SKIN_MID, COL_CORAL_ROSE, COL_SKIN_HI]
	_append_curved_loft(body_st, r_arm_pts, r_arm_r, r_arm_c, 8, true, true, COL_SKIN_SHADE)
	# Clasped right hand wrapped around the staff shaft.
	_append_faceted_bipyramid(body_st, Vector3(0.55, 1.45, -0.14), 0.072, 0.064, 6, COL_SKIN_HI, COL_SKIN_MID)

	# 2. Welcoming outstretched left arm & open beckoning hand reaching toward the swimmer!
	var l_arm_pts: Array[Vector3] = [
		Vector3(-0.32, 0.96, -0.02),
		Vector3(-0.42, 0.89, -0.11),
		Vector3(-0.46, 0.82, -0.23),
		Vector3(-0.40, 0.85, -0.37),
		Vector3(-0.34, 0.90, -0.50),
	]
	var l_arm_r: Array[Vector2] = [
		Vector2(0.088, 0.082),
		Vector2(0.078, 0.074),
		Vector2(0.068, 0.066),
		Vector2(0.060, 0.058),
		Vector2(0.052, 0.036),
	]
	var l_arm_c: Array[Color] = [COL_SKIN_HI, COL_SKIN_MID, COL_SKIN_MID, COL_CORAL_ROSE, COL_SKIN_HI]
	_append_curved_loft(body_st, l_arm_pts, l_arm_r, l_arm_c, 8, true, true, COL_SKIN_SHADE)
	# Welcoming open palm & outstretched beckoning fingers.
	var palm := Vector3(-0.33, 0.91, -0.53)
	_append_faceted_bipyramid(body_st, palm, 0.058, 0.034, 6, COL_SKIN_HI, COL_SKIN_MID)
	_append_tapered_tube(body_st, palm, palm + Vector3(0.04, 0.05, -0.10), 0.024, 0.012, 5, COL_SKIN_HI, COL_SKIN_MID)
	_append_tapered_tube(body_st, palm, palm + Vector3(-0.04, 0.04, -0.08), 0.018, 0.010, 5, COL_SKIN_HI, COL_SKIN_MID)

	# 3. Carved driftwood-and-coral beacon staff passing through the raised right hand.
	var staff_pts: Array[Vector3] = [
		Vector3(0.51, -0.45, -0.10),
		Vector3(0.53, 0.12, -0.12),
		Vector3(0.56, 0.72, -0.15),
		Vector3(0.54, 1.24, -0.13),
		Vector3(0.55, 1.54, -0.14),
		Vector3(0.55, 1.78, -0.14),
	]
	var staff_r: Array[Vector2] = [
		Vector2(0.036, 0.036),
		Vector2(0.040, 0.040),
		Vector2(0.042, 0.042),
		Vector2(0.040, 0.040),
		Vector2(0.046, 0.046),
		Vector2(0.068, 0.068),
	]
	var staff_c: Array[Color] = [
		COL_DRIFTWOOD_LO,
		COL_DRIFTWOOD_HI,
		COL_DRIFTWOOD_LO,
		COL_DRIFTWOOD_HI,
		COL_CORAL_ROSE,
		COL_CORAL_WARM,
	]
	_append_curved_loft(body_st, staff_pts, staff_r, staff_c, 8, true, true, COL_DRIFTWOOD_LO)

	# 4. Four curling sea-coral cradle prongs embracing the blazing sea-glass conch orb.
	var crown_base := Vector3(0.55, 1.78, -0.14)
	for pi in 4:
		var ang := float(pi) * (TAU * 0.25) + 0.4
		var rad_dir := Vector3(cos(ang), 0.0, sin(ang))
		var tan_dir := Vector3(-sin(ang), 0.0, cos(ang))
		var prong_pts: Array[Vector3] = [
			crown_base + rad_dir * 0.04,
			crown_base + rad_dir * 0.15 + tan_dir * 0.04 + Vector3(0.0, 0.10, 0.0),
			crown_base + rad_dir * 0.18 + tan_dir * 0.07 + Vector3(0.0, 0.24, 0.0),
			crown_base + rad_dir * 0.10 + tan_dir * 0.05 + Vector3(0.0, 0.34, 0.0),
		]
		var prong_r: Array[Vector2] = [
			Vector2(0.028, 0.028),
			Vector2(0.024, 0.024),
			Vector2(0.018, 0.018),
			Vector2(0.010, 0.010),
		]
		var prong_c: Array[Color] = [COL_DRIFTWOOD_HI, COL_CORAL_ROSE, COL_CORAL_WARM, COL_SHELL_CREAM]
		_append_curved_loft(body_st, prong_pts, prong_r, prong_c, 5, true, true, COL_CORAL_ROSE)

	# 5. Blazing faceted Sea-Glass Conch Orb atop the beacon staff (Surface 1 _glow_mat!).
	var orb_rings: Array[Array] = [
		[CONCH_ORB_LOCAL.y - 0.15, 0.055, 0.055, 0.0, COL_ORB_EDGE],
		[CONCH_ORB_LOCAL.y - 0.07, 0.125, 0.125, 0.0, COL_ORB_CORE],
		[CONCH_ORB_LOCAL.y + 0.02, 0.140, 0.140, 0.0, COL_ORB_CORE],
		[CONCH_ORB_LOCAL.y + 0.10, 0.108, 0.108, 0.0, COL_ORB_EDGE],
		[CONCH_ORB_LOCAL.y + 0.18, 0.048, 0.048, 0.0, COL_ORB_CORE],
		[CONCH_ORB_LOCAL.y + 0.25, 0.014, 0.014, 0.0, COL_PEARL_GLOW],
	]
	_append_offset_profile_loft(glow_st, Vector3(CONCH_ORB_LOCAL.x, 0.0, CONCH_ORB_LOCAL.z), orb_rings, 10, true, true)

	# Spiral conch-shell whorl flare hugging the glowing sea-glass orb.
	var whorl_pts: Array[Vector3] = []
	var whorl_r: Array[Vector2] = []
	var whorl_c: Array[Color] = []
	for wi in 7:
		var u := float(wi) / 6.0
		var wa := u * TAU * 1.15
		var wr := lerpf(0.155, 0.055, u)
		var wy := CONCH_ORB_LOCAL.y - 0.06 + u * 0.26
		whorl_pts.append(Vector3(CONCH_ORB_LOCAL.x + cos(wa) * wr, wy, CONCH_ORB_LOCAL.z + sin(wa) * wr))
		whorl_r.append(Vector2(lerpf(0.030, 0.012, u), lerpf(0.024, 0.010, u)))
		whorl_c.append(COL_SHELL_CREAM.lerp(COL_CORAL_WARM, u))
	_append_curved_loft(body_st, whorl_pts, whorl_r, whorl_c, 5, true, true, COL_SHELL_ROSE)


static func _build_emerald_smoke_beacon_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# 1. Three intertwined rising helical emerald-turquoise smoke ribbon wisps
	#    stretching SMOKE_HEIGHT (26.0 m) straight above the conch orb!
	var ribbon_segs := 24
	for ri in 3:
		var phase := float(ri) * (TAU / 3.0)
		var pts: Array[Vector3] = []
		var rads: Array[Vector2] = []
		var cols: Array[Color] = []
		for s in ribbon_segs + 1:
			var t := float(s) / float(ribbon_segs)
			var y := t * SMOKE_HEIGHT
			var swirl_ang := phase + t * TAU * 2.55
			var orbit_r := lerpf(0.14, 1.12, pow(t, 0.72)) * (1.0 - 0.25 * pow(t, 2.2))
			var x := cos(swirl_ang) * orbit_r
			var z := sin(swirl_ang) * orbit_r
			pts.append(Vector3(x, y, z))
			var w_profile := sin(clampf(t, 0.03, 0.97) * PI)
			var rx := lerpf(0.12, 0.44, w_profile) * lerpf(0.75, 1.15, t)
			var ry := rx * 0.48
			rads.append(Vector2(maxf(rx, 0.045), maxf(ry, 0.032)))
			cols.append(_smoke_color_at(t))
		_append_curved_loft(st, pts, rads, cols, 3, false, false, COL_SMOKE_CORE)

	# 2. Central luminous twisting turquoise inner core spine rising 22 m!
	var core_segs := 20
	var core_pts: Array[Vector3] = []
	var core_r: Array[Vector2] = []
	var core_c: Array[Color] = []
	for s in core_segs + 1:
		var t := float(s) / float(core_segs)
		var y := t * (SMOKE_HEIGHT * 0.88)
		var ang := -t * TAU * 1.8
		var r_off := lerpf(0.03, 0.30, sin(t * PI))
		core_pts.append(Vector3(cos(ang) * r_off, y, sin(ang) * r_off))
		var cr := lerpf(0.16, 0.28, sin(t * PI)) * (1.0 - t * 0.65)
		core_r.append(Vector2(maxf(cr, 0.035), maxf(cr, 0.035)))
		var cc := COL_SMOKE_CORE.lerp(COL_SMOKE_TIP, pow(t, 0.85))
		core_c.append(cc)
	_append_curved_loft(st, core_pts, core_r, core_c, 4, false, false, COL_SMOKE_CORE)

	# 3. Four flared curling side-wisp tendrils drifting outward along the rising column.
	var wisp_heights: Array[float] = [4.8, 10.4, 16.0, 21.2]
	for wi in wisp_heights.size():
		var h0 := wisp_heights[wi]
		var base_ang := float(wi) * 1.65 + 0.5
		var w_pts: Array[Vector3] = []
		var w_r: Array[Vector2] = []
		var w_c: Array[Color] = []
		for s in 7:
			var u := float(s) / 6.0
			var a := base_ang + u * 2.1
			var rad := lerpf(0.55, 1.85, u)
			var y := h0 + u * 3.8
			w_pts.append(Vector3(cos(a) * rad, y, sin(a) * rad))
			var wr := lerpf(0.24, 0.06, u)
			w_r.append(Vector2(wr, wr * 0.55))
			var t_glob := clampf(y / SMOKE_HEIGHT, 0.0, 1.0)
			var col := _smoke_color_at(t_glob)
			col.a *= (1.0 - u * 0.85)
			w_c.append(col)
		_append_curved_loft(st, w_pts, w_r, w_c, 3, false, false, COL_SMOKE_MID)

	return st.commit()


static func _smoke_color_at(t: float) -> Color:
	var u := clampf(t, 0.0, 1.0)
	if u < 0.28:
		return COL_SMOKE_CORE.lerp(COL_SMOKE_MID, u / 0.28)
	if u < 0.72:
		return COL_SMOKE_MID.lerp(COL_SMOKE_HIGH, (u - 0.28) / 0.44)
	return COL_SMOKE_HIGH.lerp(COL_SMOKE_TIP, (u - 0.72) / 0.28)


## Sculpted 16-tri faceted diamond crystal mote for rising sea-mist sparkles (0 primitives).
static func _build_diamond_mote_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_append_faceted_bipyramid(st, Vector3.ZERO, 0.036, 0.064, 8, COL_ORB_CORE, COL_ORB_EDGE)
	return st.commit()


# ==============================================================================
# Low-Level Sculpting Geometry Helpers (Guaranteed Finite Outward Unit Normals)
# ==============================================================================

static func _append_vertical_profile_loft(st: SurfaceTool, rings: Array[Array], sides: int,
		cap_bottom: bool, cap_top: bool) -> void:
	_append_offset_profile_loft(st, Vector3.ZERO, rings, sides, cap_bottom, cap_top)


static func _append_offset_profile_loft(st: SurfaceTool, offset: Vector3, rings: Array[Array], sides: int,
		cap_bottom: bool, cap_top: bool) -> void:
	if rings.size() < 2 or sides < 3:
		return
	var ring_verts: Array[Array] = []
	var ring_centers: Array[Vector3] = []
	var ring_cols: Array[Color] = []

	for r in rings:
		var ry := float(r[0])
		var rx := float(r[1])
		var rz := float(r[2])
		var z_shift := float(r[3])
		var col: Color = r[4] as Color
		var ctr := offset + Vector3(0.0, ry, z_shift)
		ring_centers.append(ctr)
		ring_cols.append(col)
		var pts: Array[Vector3] = []
		for k in sides:
			var a := TAU * float(k) / float(sides)
			pts.append(ctr + Vector3(cos(a) * rx, 0.0, sin(a) * rz))
		ring_verts.append(pts)

	for i in rings.size() - 1:
		var r0: Array = ring_verts[i]
		var r1: Array = ring_verts[i + 1]
		var c0 := ring_cols[i]
		var c1 := ring_cols[i + 1]
		var mid := (ring_centers[i] + ring_centers[i + 1]) * 0.5
		for k in sides:
			var nk := (k + 1) % sides
			_emit_outward_quad(st, r0[k] as Vector3, r0[nk] as Vector3, r1[nk] as Vector3, r1[k] as Vector3,
				mid, c0, c0, c1, c1)

	if cap_bottom:
		var c_bot := ring_centers[0]
		var col_bot := ring_cols[0]
		var r_bot: Array = ring_verts[0]
		for k in sides:
			var nk := (k + 1) % sides
			_emit_directed_tri(st, c_bot, r_bot[nk] as Vector3, r_bot[k] as Vector3, Vector3.DOWN,
				col_bot, col_bot, col_bot)

	if cap_top:
		var last := rings.size() - 1
		var c_top := ring_centers[last]
		var col_top := ring_cols[last]
		var r_top: Array = ring_verts[last]
		for k in sides:
			var nk := (k + 1) % sides
			_emit_directed_tri(st, c_top, r_top[k] as Vector3, r_top[nk] as Vector3, Vector3.UP,
				col_top, col_top, col_top)


static func _append_curved_loft(st: SurfaceTool, centers: Array[Vector3], radii: Array[Vector2],
		colors: Array[Color], sides: int, cap_start: bool, cap_end: bool, belly_col: Color) -> void:
	var n := centers.size()
	if n < 2 or sides < 3:
		return
	var ring_verts: Array[Array] = []
	var ring_vcols: Array[Array] = []
	var prev_u := Vector3.RIGHT

	for i in n:
		var tang: Vector3
		if i == 0:
			tang = (centers[1] - centers[0]).normalized()
		elif i == n - 1:
			tang = (centers[n - 1] - centers[n - 2]).normalized()
		else:
			tang = (centers[i + 1] - centers[i - 1]).normalized()
		if tang.length_squared() < 0.0001:
			tang = Vector3.UP

		# Parallel-transport orthonormal frame so curved lofts never twist or pinch!
		var u := prev_u - tang * prev_u.dot(tang)
		if u.length_squared() < 0.001:
			var ref := Vector3.UP if absf(tang.y) < 0.9 else Vector3.FORWARD
			u = tang.cross(ref).normalized()
		else:
			u = u.normalized()
		var v := tang.cross(u).normalized()
		prev_u = u

		var rx := radii[i].x
		var ry := radii[i].y
		var base_c := colors[i]
		var pts: Array[Vector3] = []
		var vcs: Array[Color] = []
		for k in sides:
			var a := TAU * float(k) / float(sides)
			var dir := u * cos(a) + v * sin(a)
			pts.append(centers[i] + u * (cos(a) * rx) + v * (sin(a) * ry))
			var front_fac := clampf(-dir.z * 0.5 + 0.5, 0.0, 1.0)
			var vc := base_c.lerp(belly_col, front_fac * 0.22)
			vc.a = base_c.a
			vcs.append(vc)
		ring_verts.append(pts)
		ring_vcols.append(vcs)

	for i in n - 1:
		var r0: Array = ring_verts[i]
		var r1: Array = ring_verts[i + 1]
		var c0: Array = ring_vcols[i]
		var c1: Array = ring_vcols[i + 1]
		var mid := (centers[i] + centers[i + 1]) * 0.5
		for k in sides:
			var nk := (k + 1) % sides
			_emit_outward_quad(st, r0[k] as Vector3, r0[nk] as Vector3, r1[nk] as Vector3, r1[k] as Vector3,
				mid, c0[k] as Color, c0[nk] as Color, c1[nk] as Color, c1[k] as Color)

	if cap_start:
		var dir_start := (centers[0] - centers[1]).normalized()
		var r_s: Array = ring_verts[0]
		var c_s: Array = ring_vcols[0]
		for k in sides:
			var nk := (k + 1) % sides
			_emit_directed_tri(st, centers[0], r_s[nk] as Vector3, r_s[k] as Vector3, dir_start,
				colors[0], c_s[nk] as Color, c_s[k] as Color)

	if cap_end:
		var last := n - 1
		var dir_end := (centers[last] - centers[last - 1]).normalized()
		var r_e: Array = ring_verts[last]
		var c_e: Array = ring_vcols[last]
		for k in sides:
			var nk := (k + 1) % sides
			_emit_directed_tri(st, centers[last], r_e[k] as Vector3, r_e[nk] as Vector3, dir_end,
				colors[last], c_e[k] as Color, c_e[nk] as Color)


static func _append_tapered_tube(st: SurfaceTool, p0: Vector3, p1: Vector3,
		r0: float, r1: float, segs: int, c0: Color, c1: Color) -> void:
	var axis := p1 - p0
	if axis.length_squared() < 1e-10:
		return
	var dir := axis.normalized()
	var ref := Vector3.UP if absf(dir.y) < 0.92 else Vector3.RIGHT
	var u := dir.cross(ref).normalized()
	var v := dir.cross(u).normalized()
	var mid := (p0 + p1) * 0.5
	for k in segs:
		var a0 := TAU * float(k) / float(segs)
		var a1 := TAU * float(k + 1) / float(segs)
		var d0 := u * cos(a0) + v * sin(a0)
		var d1 := u * cos(a1) + v * sin(a1)
		var v00 := p0 + d0 * r0
		var v01 := p0 + d1 * r0
		var v10 := p1 + d0 * r1
		var v11 := p1 + d1 * r1
		_emit_outward_quad(st, v00, v01, v11, v10, mid, c0, c0, c1, c1)
		_emit_directed_tri(st, p0, v01, v00, -dir, c0, c0, c0)
		_emit_directed_tri(st, p1, v10, v11, dir, c1, c1, c1)


static func _append_faceted_bipyramid(st: SurfaceTool, center: Vector3, radius: float,
		half_height: float, sides: int, col_tip: Color, col_mid: Color) -> void:
	var top := center + Vector3(0.0, half_height, 0.0)
	var bot := center - Vector3(0.0, half_height, 0.0)
	for k in sides:
		var a0 := TAU * float(k) / float(sides)
		var a1 := TAU * float(k + 1) / float(sides)
		var p0 := center + Vector3(cos(a0) * radius, 0.0, sin(a0) * radius)
		var p1 := center + Vector3(cos(a1) * radius, 0.0, sin(a1) * radius)
		_emit_outward_tri(st, top, p0, p1, center, col_tip, col_mid, col_mid)
		_emit_outward_tri(st, bot, p1, p0, center, col_tip, col_mid, col_mid)


static func _emit_outward_quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3,
		ref_center: Vector3, ca: Color, cb: Color, cc: Color, cd: Color) -> void:
	_emit_outward_tri(st, a, b, c, ref_center, ca, cb, cc)
	_emit_outward_tri(st, a, c, d, ref_center, ca, cc, cd)


static func _emit_outward_tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3,
		ref_center: Vector3, ca: Color, cb: Color, cc: Color) -> void:
	var centroid := (a + b + c) / 3.0
	_emit_directed_tri(st, a, b, c, centroid - ref_center, ca, cb, cc)


static func _emit_directed_tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3,
		outward_dir: Vector3, ca: Color, cb: Color, cc: Color) -> void:
	var n := (c - a).cross(b - a)
	if n.length_squared() < 1e-12:
		return
	if n.dot(outward_dir) < 0.0:
		var tv := b
		b = c
		c = tv
		var tc := cb
		cb = cc
		cc = tc
		n = -n
	n = n.normalized()
	st.set_normal(n)
	st.set_color(ca)
	st.set_uv(Vector2(0.0, 0.0))
	st.add_vertex(a)
	st.set_normal(n)
	st.set_color(cb)
	st.set_uv(Vector2(1.0, 0.0))
	st.add_vertex(b)
	st.set_normal(n)
	st.set_color(cc)
	st.set_uv(Vector2(0.5, 1.0))
	st.add_vertex(c)
