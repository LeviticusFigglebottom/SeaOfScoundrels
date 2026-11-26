class_name IslandWildlife
extends Node3D
## Living sculpted tropical island fauna ecosystem populating every island across
## the archipelago with reactive, zero-primitive procedural `SurfaceTool` wildlife:
##
## 1. Tropical Macaw Parrots (Scarlet Macaw & Emerald Amazon variants, >= 380 tris):
##    Perch around palms, campsites, and coastal rocks; startle with a guarded
##    tropical chirp when the player approaches within 9.5 m, burst into banked
##    soaring circular flight (11 Hz wingbeats, 6..9 s), and glide back to perch.
## 2. Giant Tropical Sea Turtles (>= 440 tris):
##    Crawl along gentle sandy shore arcs (0.25..2.4 m, slope < 0.24) aligned to
##    local terrain normals with alternating paddle-flipper strokes, sun-basking
##    pauses, breathing head nods, and shy head-tucking when player < 3.5 m.
## 3. Scurrying Coral Sand-Crabs (>= 280 tris):
##    Populate sandy coves & shoreline trails (0.20..3.6 m, slope < 0.30),
##    alternating pincer-waving pauses with snappy sideways scuttles and darting
##    sideways away from approaching players (< 5.5 m).
## 4. Tropical Butterflies (Day, >= 48 tris) & Meadow Fireflies (Dusk/Night):
##    Iridescent Morpho-Blue & Golden-Monarch butterflies flutter in figure-8
##    paths at 10..14 Hz across lush glades (6.5 <= Weather.time_of_day <= 18.5),
##    swapping seamlessly at dusk/night to warm glowing golden diamond fireflies.
##
## Zero primitive meshes, zero extra VRAM textures, distance-culled beyond
## `island_radius + 180.0 m`, and 100% ref-counted static cache teardown.

const GROUP := &"island_wildlife"
const CULL_MARGIN := 180.0

const PARROT_STARTLE_DIST := 9.5
const TURTLE_SHY_DIST := 3.5
const CRAB_FLEE_DIST := 5.5

const DAY_START_HOUR := 6.5
const DAY_END_HOUR := 18.5

const PARROT_PERCHED := 0
const PARROT_FLYING := 1
const PARROT_RETURNING := 2

# --- Painterly Tropical Fauna Palettes (authored in sRGB) ---------------------

# Scarlet Macaw
const COL_SCARLET_MAIN := Color(0.88, 0.13, 0.12)
const COL_SCARLET_DEEP := Color(0.64, 0.08, 0.09)
const COL_SCARLET_GOLD := Color(0.96, 0.78, 0.12)
const COL_SCARLET_COBALT := Color(0.11, 0.38, 0.84)
const COL_SCARLET_CHEEK := Color(0.96, 0.94, 0.88)

# Emerald Amazon Parrot
const COL_EMERALD_MAIN := Color(0.14, 0.66, 0.28)
const COL_EMERALD_DEEP := Color(0.08, 0.44, 0.20)
const COL_EMERALD_LIME := Color(0.56, 0.84, 0.22)
const COL_EMERALD_TEAL := Color(0.10, 0.56, 0.68)
const COL_EMERALD_CROWN := Color(0.95, 0.80, 0.18)

const COL_BEAK_IVORY := Color(0.92, 0.86, 0.72)
const COL_BEAK_DARK := Color(0.14, 0.14, 0.16)
const COL_TALON_SLATE := Color(0.32, 0.30, 0.28)
const COL_EYE_DARK := Color(0.05, 0.06, 0.08)
const COL_EYE_RING := Color(0.95, 0.92, 0.84)

# Giant Tropical Sea Turtle
const COL_SHELL_OLIVE := Color(0.24, 0.38, 0.22)
const COL_SHELL_AMBER := Color(0.62, 0.44, 0.18)
const COL_SHELL_DARK := Color(0.17, 0.24, 0.14)
const COL_SHELL_RIM := Color(0.76, 0.62, 0.32)
const COL_PLASTRON_SAND := Color(0.86, 0.78, 0.58)
const COL_TURTLE_SKIN := Color(0.36, 0.46, 0.28)
const COL_TURTLE_SCALE := Color(0.22, 0.31, 0.19)
const COL_TURTLE_EDGE := Color(0.70, 0.60, 0.38)

# Scurrying Coral Sand-Crab
const COL_CRAB_CORAL := Color(0.92, 0.30, 0.20)
const COL_CRAB_VERMILION := Color(0.78, 0.18, 0.13)
const COL_CRAB_MOTTLE := Color(0.96, 0.52, 0.28)
const COL_CRAB_BELLY := Color(0.94, 0.85, 0.72)
const COL_CRAB_CLAW_TIP := Color(0.96, 0.91, 0.80)
const COL_CRAB_LEG := Color(0.84, 0.34, 0.22)

# Tropical Butterflies & Meadow Fireflies
const COL_MORPHO_INNER := Color(0.12, 0.68, 0.98)
const COL_MORPHO_MID := Color(0.08, 0.44, 0.90)
const COL_MORPHO_RIM := Color(0.08, 0.11, 0.22)
const COL_MORPHO_DOT := Color(0.92, 0.96, 1.00)

const COL_MONARCH_INNER := Color(0.98, 0.58, 0.08)
const COL_MONARCH_MID := Color(0.96, 0.76, 0.16)
const COL_MONARCH_RIM := Color(0.10, 0.08, 0.07)
const COL_MONARCH_DOT := Color(0.98, 0.95, 0.84)

const COL_BUTTERFLY_BODY := Color(0.12, 0.11, 0.13)
const COL_FIREFLY_CORE := Color(1.00, 0.88, 0.34)
const COL_FIREFLY_GLOW := Color(1.00, 0.74, 0.18)

# --- Statically Cached Shared Meshes & Materials (Zero Extra VRAM) ------------

static var _active_instances: int = 0

static var _feather_mat: StandardMaterial3D = null
static var _shell_mat: StandardMaterial3D = null
static var _butterfly_mat: StandardMaterial3D = null
static var _firefly_mat: StandardMaterial3D = null

static var _parrot_scarlet_body: ArrayMesh = null
static var _parrot_scarlet_wing_l: ArrayMesh = null
static var _parrot_scarlet_wing_r: ArrayMesh = null
static var _parrot_emerald_body: ArrayMesh = null
static var _parrot_emerald_wing_l: ArrayMesh = null
static var _parrot_emerald_wing_r: ArrayMesh = null

static var _turtle_body_mesh: ArrayMesh = null
static var _turtle_head_mesh: ArrayMesh = null
static var _turtle_flipper_l_mesh: ArrayMesh = null
static var _turtle_flipper_r_mesh: ArrayMesh = null

static var _crab_body_mesh: ArrayMesh = null
static var _crab_claw_l_mesh: ArrayMesh = null
static var _crab_claw_r_mesh: ArrayMesh = null

static var _butterfly_body_mesh: ArrayMesh = null
static var _butterfly_morpho_wing_l: ArrayMesh = null
static var _butterfly_morpho_wing_r: ArrayMesh = null
static var _butterfly_monarch_wing_l: ArrayMesh = null
static var _butterfly_monarch_wing_r: ArrayMesh = null
static var _firefly_mesh: ArrayMesh = null

# --- Per-Island Instance State ------------------------------------------------

var player_pawn: Node3D = null
var distance_culled: bool = false

var _island: Island = null
var _rng := RandomNumberGenerator.new()
var _clock: float = 0.0
var _built: bool = false

var _parrots: Array[Dictionary] = []
var _turtles: Array[Dictionary] = []
var _crabs: Array[Dictionary] = []
var _insects: Array[Dictionary] = []
var _owned_meshes: Array[MeshInstance3D] = []


# ==============================================================================
# Public Static API
# ==============================================================================

## Release all statically cached IslandWildlife meshes and materials cleanly.
static func clear_shared_cache() -> void:
	_feather_mat = null
	_shell_mat = null
	_butterfly_mat = null
	_firefly_mat = null
	_parrot_scarlet_body = null
	_parrot_scarlet_wing_l = null
	_parrot_scarlet_wing_r = null
	_parrot_emerald_body = null
	_parrot_emerald_wing_l = null
	_parrot_emerald_wing_r = null
	_turtle_body_mesh = null
	_turtle_head_mesh = null
	_turtle_flipper_l_mesh = null
	_turtle_flipper_r_mesh = null
	_crab_body_mesh = null
	_crab_claw_l_mesh = null
	_crab_claw_r_mesh = null
	_butterfly_body_mesh = null
	_butterfly_morpho_wing_l = null
	_butterfly_morpho_wing_r = null
	_butterfly_monarch_wing_l = null
	_butterfly_monarch_wing_r = null
	_firefly_mesh = null


## Populate every island in `archipelago` with a living `IslandWildlife` ecosystem.
## Each wildlife node mounts directly as child `"IslandWildlife"` of its `Island`.
static func populate_archipelago(_parent: Node, archipelago: Archipelago,
		p_player_pawn: Node3D = null) -> Array[IslandWildlife]:
	var created: Array[IslandWildlife] = []
	if archipelago == null:
		return created
	var all_islands: Array[Island] = archipelago.get_islands()
	for isl in all_islands:
		if isl == null or not is_instance_valid(isl):
			continue
		var w := populate_island(isl, p_player_pawn)
		if w != null:
			created.append(w)
	return created


## Populate a single `island` with deterministic, biome-scaled wildlife attached
## as child `"IslandWildlife"` so local coordinates & transforms track cleanly.
static func populate_island(island: Island, p_player_pawn: Node3D = null) -> IslandWildlife:
	if island == null:
		return null
	var existing := island.get_node_or_null(^"IslandWildlife") as IslandWildlife
	if existing != null and is_instance_valid(existing):
		if p_player_pawn != null:
			existing.player_pawn = p_player_pawn
		return existing
	var wildlife := IslandWildlife.new()
	wildlife.name = "IslandWildlife"
	wildlife._island = island
	wildlife.player_pawn = p_player_pawn
	island.add_child(wildlife)
	return wildlife


# ==============================================================================
# Lifecycle
# ==============================================================================

func _enter_tree() -> void:
	_active_instances += 1
	add_to_group(GROUP)


func _ready() -> void:
	if _island == null and get_parent() is Island:
		_island = get_parent() as Island
	_ensure_built()


func _exit_tree() -> void:
	for mi in _owned_meshes:
		if mi != null and is_instance_valid(mi):
			if mi.mesh != null:
				for si in mi.mesh.get_surface_count():
					mi.set_surface_override_material(si, null)
			mi.material_override = null
			mi.mesh = null
	_owned_meshes.clear()
	_parrots.clear()
	_turtles.clear()
	_crabs.clear()
	_insects.clear()
	player_pawn = null
	_island = null
	_built = false
	_active_instances = maxi(0, _active_instances - 1)
	if _active_instances == 0:
		clear_shared_cache()


func _process(delta: float) -> void:
	if not _built or _island == null or not is_instance_valid(_island):
		return
	var cull_dist := _island.island_radius + CULL_MARGIN
	var viewer_dist_sq := _nearest_viewer_dist_sq()
	if viewer_dist_sq > cull_dist * cull_dist:
		distance_culled = true
		return
	distance_culled = false
	step_wildlife(delta)


## Advance all island fauna animations, AI behaviors, reactivity, and day/night swaps.
func step_wildlife(delta: float) -> void:
	if not _built or _island == null or not is_instance_valid(_island):
		return
	var dt := clampf(delta, 0.0, 0.12)
	_clock += dt

	var has_player := player_pawn != null and is_instance_valid(player_pawn)
	var player_local := Vector3.ZERO
	if has_player:
		var isl_xf := _island.global_transform if _island.is_inside_tree() else _island.transform
		var p_world := player_pawn.global_position if player_pawn.is_inside_tree() else player_pawn.position
		player_local = isl_xf.affine_inverse() * p_world

	_step_parrots(dt, has_player, player_local)
	_step_turtles(dt, has_player, player_local)
	_step_crabs(dt, has_player, player_local)
	_step_insects(dt)


# ==============================================================================
# Inspection Accessors (for tests & tooling)
# ==============================================================================

func get_parrots() -> Array[Node3D]:
	return _collect_roots(_parrots)


func get_turtles() -> Array[Node3D]:
	return _collect_roots(_turtles)


func get_crabs() -> Array[Node3D]:
	return _collect_roots(_crabs)


func get_insects() -> Array[Node3D]:
	return _collect_roots(_insects)


func is_parrot_flying(index: int) -> bool:
	if index < 0 or index >= _parrots.size():
		return false
	return int(_parrots[index]["state"]) != PARROT_PERCHED


func is_daytime_mode() -> bool:
	var tod := Weather.time_of_day if Weather != null else 12.0
	return tod >= DAY_START_HOUR and tod <= DAY_END_HOUR


static func _collect_roots(entries: Array[Dictionary]) -> Array[Node3D]:
	var out: Array[Node3D] = []
	for e in entries:
		var n := e.get("root") as Node3D
		if n != null and is_instance_valid(n):
			out.append(n)
	return out


func _nearest_viewer_dist_sq() -> float:
	var isl_pos := _island.global_position if _island.is_inside_tree() else _island.position
	var best := INF
	var found := false
	if is_inside_tree() and get_viewport() != null:
		var cam := get_viewport().get_camera_3d()
		if cam != null and is_instance_valid(cam):
			best = minf(best, isl_pos.distance_squared_to(cam.global_position))
			found = true
	if player_pawn != null and is_instance_valid(player_pawn):
		var p_pos := player_pawn.global_position if player_pawn.is_inside_tree() else player_pawn.position
		best = minf(best, isl_pos.distance_squared_to(p_pos))
		found = true
	return best if found else 0.0


# ==============================================================================
# Island Population & Biome-Aware Deterministic Placement
# ==============================================================================

func _ensure_built() -> void:
	if _built or _island == null:
		return
	_built = true
	_ensure_shared_assets()

	_rng.seed = _compute_island_seed(_island)

	var arch: StringName = _island.archetype
	var is_volcano := arch == &"volcano_crag"
	var is_showcase := _island.island_id == "cutlass_cay" or _island.island_id == "port_scoundrel"
	var size_t := clampf((_island.island_radius - 40.0) / 130.0, 0.0, 1.0)

	var target_parrots := 2 if is_volcano else clampi(int(roundf(lerpf(2.0, 4.0, size_t))), 2, 4)
	var target_turtles := 0 if is_volcano else clampi(int(roundf(lerpf(1.0, 3.0, size_t))), 1, 3)
	var target_crabs := 3 if is_volcano else clampi(int(roundf(lerpf(3.0, 6.0, size_t))), 3, 6)
	var target_insects := 0 if is_volcano else clampi(int(roundf(lerpf(4.0, 8.0, size_t))), 4, 8)
	if is_showcase:
		target_parrots = maxi(target_parrots, 3)
		target_turtles = maxi(target_turtles, 2)
		target_crabs = maxi(target_crabs, 4)
		target_insects = maxi(target_insects, 5)

	var landing_yaw := _get_landing_yaw(_island)
	var landing_basis := Basis(Vector3.UP, landing_yaw)

	_spawn_sea_turtles(target_turtles, landing_basis, is_showcase)
	_spawn_coral_crabs(target_crabs, landing_basis, is_showcase)
	_spawn_macaw_parrots(target_parrots, landing_basis, is_showcase, is_volcano)
	_spawn_butterflies_and_fireflies(target_insects, landing_basis, is_showcase)

	step_wildlife(0.0)


static func _compute_island_seed(island: Island) -> int:
	# Deterministic FNV-1a mix of island_id + radius so placement never shifts across runs.
	var h: int = 2166136261
	var bytes := island.island_id.to_utf8_buffer()
	for b in bytes:
		h = int((h ^ int(b)) * 16777619) & 0x7FFFFFFF
	h = int((h ^ int(roundf(island.island_radius * 10.0))) * 16777619) & 0x7FFFFFFF
	return h if h != 0 else 0x51A11D7


static func _get_landing_yaw(island: Island) -> float:
	if island is Outpost:
		return (island as Outpost).dock_yaw
	if island.has_meta(&"landing_yaw"):
		return float(island.get_meta(&"landing_yaw", 0.0))
	var m := island.mooring_transform.origin
	if Vector2(m.x, m.z).length_squared() > 0.25:
		return atan2(-m.x, -m.z)
	return 0.0


func _surface_slope(lx: float, lz: float) -> float:
	var n := _island.surface_normal(lx, lz)
	return Vector2(n.x, n.z).length() / maxf(n.y, 0.001)


func _is_clear_of_structures(lx: float, lz: float, margin: float = 0.0) -> bool:
	var pt := Vector2(lx, lz)
	# Keep off Outpost pier, tavern, stall & beacon footprints.
	if _island is Outpost:
		var op := _island as Outpost
		var pier_a := Vector2(op.dock_local_transform.origin.x, op.dock_local_transform.origin.z)
		var pier_b := Vector2(op.dock_pier_end_local.x, op.dock_pier_end_local.z)
		# Extend landward 4 m past pier root to keep creatures off the timber landing ramp.
		var pier_dir := (pier_b - pier_a).normalized() if pier_a.distance_squared_to(pier_b) > 0.01 else Vector2(0.0, -1.0)
		var seg_a := pier_a - pier_dir * 4.5
		var seg := pier_b - seg_a
		var seg_l2 := seg.length_squared()
		var proj := clampf((pt - seg_a).dot(seg) / seg_l2, 0.0, 1.0) if seg_l2 > 0.001 else 0.0
		if pt.distance_to(seg_a + seg * proj) < (6.2 + margin):
			return false
		if op.tavern_node != null and is_instance_valid(op.tavern_node):
			var tv := Vector2(op.tavern_node.position.x, op.tavern_node.position.z)
			if pt.distance_to(tv) < (7.5 + margin):
				return false
		if op.merchant_stall != null and is_instance_valid(op.merchant_stall):
			var ms := Vector2(op.merchant_stall.position.x, op.merchant_stall.position.z)
			if pt.distance_to(ms) < (4.4 + margin):
				return false
		if op.beacon_node != null and is_instance_valid(op.beacon_node):
			var bc := Vector2(op.beacon_node.position.x, op.beacon_node.position.z)
			if pt.distance_to(bc) < (5.0 + margin):
				return false
	for dp in _island.dig_points:
		if pt.distance_squared_to(Vector2(dp.x, dp.z)) < (2.6 + margin) * (2.6 + margin):
			return false
	return true


func _collect_beach_spots(min_h: float, max_h: float, max_slope: float,
		landing_basis: Basis, margin: float) -> Array[Vector3]:
	var spots: Array[Vector3] = []
	var r_max := _island.island_radius * 1.05
	var r_min := maxf(4.0, _island.island_radius * 0.18)
	var rings := 14
	var slices := 44
	for ri in rings:
		var r := lerpf(r_min, r_max, float(ri) / float(rings - 1))
		for si in slices:
			var ang := float(si) / float(slices) * TAU
			var lp := landing_basis * Vector3(cos(ang) * r, 0.0, sin(ang) * r)
			var h := _island.surface_height(lp.x, lp.z)
			if h < min_h or h > max_h:
				continue
			if _surface_slope(lp.x, lp.z) >= max_slope:
				continue
			if not _is_clear_of_structures(lp.x, lp.z, margin):
				continue
			spots.append(Vector3(lp.x, h, lp.z))
	return spots


func _sort_cove_first(spots: Array[Vector3], landing_basis: Basis) -> void:
	var inv_b := landing_basis.inverse()
	var is_outpost := _island is Outpost
	spots.sort_custom(func(a: Vector3, b: Vector3) -> bool:
		var la := inv_b * a
		var lb := inv_b * b
		var sa: float
		var sb: float
		if is_outpost:
			# Prioritize the sunlit harbour beaches flanking the dock pier (v < -10, |u| ~ 12..24).
			sa = la.z + absf(absf(la.x) - 16.0) * 0.85
			sb = lb.z + absf(absf(lb.x) - 16.0) * 0.85
		else:
			# Prioritize the primary seaward landing cove (-Z side of landing_basis).
			sa = la.z + absf(la.x) * 0.55
			sb = lb.z + absf(lb.x) * 0.55
		return sa < sb
	)


static func _far_from_xz(pt: Vector3, existing: Array[Vector3], min_dist: float) -> bool:
	var d2 := min_dist * min_dist
	for e in existing:
		var dx := pt.x - e.x
		var dz := pt.z - e.z
		if dx * dx + dz * dz < d2:
			return false
	return true


# ==============================================================================
# Species Spawners
# ==============================================================================

func _spawn_sea_turtles(count: int, landing_basis: Basis, is_showcase: bool) -> void:
	if count <= 0:
		return
	var candidates := _collect_beach_spots(0.28, 2.35, 0.238, landing_basis, 1.2)
	if candidates.is_empty():
		return
	_sort_cove_first(candidates, landing_basis)

	var placed: Array[Vector3] = []
	var selected: Array[Vector3] = []

	# Showcase beach turtle right in the main sandy landing cove (clear of dig sites & pier).
	if is_showcase:
		for c in candidates:
			if c.y >= 0.42 and c.y <= 1.85:
				selected.append(c)
				placed.append(c)
				break

	# Fill remaining turtles spaced comfortably across gentle sandy beaches.
	var stride := maxi(1, floori(float(candidates.size()) / float(maxi(count * 3, 1))))
	var offset := _rng.randi_range(0, maxi(0, candidates.size() - 1))
	for step_i in candidates.size():
		if selected.size() >= count:
			break
		var idx := (offset + step_i * stride) % candidates.size()
		var c := candidates[idx]
		if _far_from_xz(c, placed, 14.0):
			selected.append(c)
			placed.append(c)

	for i in selected.size():
		var spot := selected[i]
		var root := Node3D.new()
		root.name = "SeaTurtle_%d" % i
		var sc := _rng.randf_range(0.92, 1.16)
		root.scale = Vector3.ONE * sc
		add_child(root)

		var body_mi := _make_mesh_inst("BodyMesh", _turtle_body_mesh, _shell_mat, 195.0)
		root.add_child(body_mi)

		var head_pivot := Node3D.new()
		head_pivot.name = "HeadPivot"
		head_pivot.position = Vector3(0.0, 0.145, -0.50)
		root.add_child(head_pivot)
		var head_mi := _make_mesh_inst("HeadMesh", _turtle_head_mesh, _shell_mat, 195.0)
		head_pivot.add_child(head_mi)

		var fl_pivot := Node3D.new()
		fl_pivot.name = "FrontLeftFlipper"
		fl_pivot.position = Vector3(-0.34, 0.11, -0.28)
		root.add_child(fl_pivot)
		fl_pivot.add_child(_make_mesh_inst("FrontLeftFlipperMesh", _turtle_flipper_l_mesh, _shell_mat, 195.0))

		var fr_pivot := Node3D.new()
		fr_pivot.name = "FrontRightFlipper"
		fr_pivot.position = Vector3(0.34, 0.11, -0.28)
		root.add_child(fr_pivot)
		fr_pivot.add_child(_make_mesh_inst("FrontRightFlipperMesh", _turtle_flipper_r_mesh, _shell_mat, 195.0))

		# Orient initially tangent to the shoreline contour so turtles crawl gracefully along the beach!
		var radial := Vector2(spot.x, spot.z)
		var tang := Vector2(-radial.y, radial.x).normalized() if radial.length_squared() > 0.01 else Vector2(1.0, 0.0)
		var arc_dir := 1.0 if (i % 2 == 0) else -1.0
		tang *= arc_dir
		var init_heading := Vector3(tang.x, 0.0, tang.y).normalized()

		var entry := {
			"root": root,
			"head_pivot": head_pivot,
			"fl_pivot": fl_pivot,
			"fr_pivot": fr_pivot,
			"scale_val": sc,
			"lx": spot.x,
			"lz": spot.z,
			"heading": init_heading,
			"arc_dir": arc_dir,
			"speed": _rng.randf_range(0.22, 0.38),
			"crawling": true,
			"state_timer": _rng.randf_range(4.2, 7.5),
			"stroke_phase": _rng.randf() * TAU,
			"breath_phase": _rng.randf() * TAU,
			"shy_blend": 0.0,
		}
		_turtles.append(entry)


func _spawn_coral_crabs(count: int, landing_basis: Basis, is_showcase: bool) -> void:
	if count <= 0:
		return
	var candidates := _collect_beach_spots(0.24, 3.55, 0.295, landing_basis, 0.6)
	if candidates.is_empty():
		return
	_sort_cove_first(candidates, landing_basis)

	var placed: Array[Vector3] = []
	var selected: Array[Vector3] = []

	if is_showcase:
		# Place 2 lively coral crabs visibly in the main sandy landing cove!
		for c in candidates:
			if selected.size() >= mini(2, count):
				break
			if c.y >= 0.32 and c.y <= 2.65 and _far_from_xz(c, placed, 3.8):
				selected.append(c)
				placed.append(c)

	var stride := maxi(1, floori(float(candidates.size()) / float(maxi(count * 4, 1))))
	var offset := _rng.randi_range(0, maxi(0, candidates.size() - 1))
	for step_i in candidates.size():
		if selected.size() >= count:
			break
		var idx := (offset + step_i * stride) % candidates.size()
		var c := candidates[idx]
		if _far_from_xz(c, placed, 7.5):
			selected.append(c)
			placed.append(c)

	for i in selected.size():
		var spot := selected[i]
		var root := Node3D.new()
		root.name = "CoralCrab_%d" % i
		var sc := _rng.randf_range(0.92, 1.22)
		root.scale = Vector3.ONE * sc
		add_child(root)

		var body_pivot := Node3D.new()
		body_pivot.name = "BodyPivot"
		root.add_child(body_pivot)
		body_pivot.add_child(_make_mesh_inst("BodyMesh", _crab_body_mesh, _shell_mat, 130.0))

		var lc_pivot := Node3D.new()
		lc_pivot.name = "LeftClawPivot"
		lc_pivot.position = Vector3(-0.115, 0.088, -0.088)
		body_pivot.add_child(lc_pivot)
		lc_pivot.add_child(_make_mesh_inst("LeftClawMesh", _crab_claw_l_mesh, _shell_mat, 130.0))

		var rc_pivot := Node3D.new()
		rc_pivot.name = "RightClawPivot"
		rc_pivot.position = Vector3(0.115, 0.088, -0.088)
		body_pivot.add_child(rc_pivot)
		rc_pivot.add_child(_make_mesh_inst("RightClawMesh", _crab_claw_r_mesh, _shell_mat, 130.0))

		# Face roughly seaward so sideways scuttle runs naturally along the beach!
		var face := Vector3(spot.x, 0.0, spot.z)
		face = face.normalized() if face.length_squared() > 0.01 else Vector3(0.0, 0.0, -1.0)
		var entry := {
			"root": root,
			"body_pivot": body_pivot,
			"lc_pivot": lc_pivot,
			"rc_pivot": rc_pivot,
			"scale_val": sc,
			"lx": spot.x,
			"lz": spot.z,
			"facing": face,
			"scuttle_sign": 1.0 if (i % 2 == 0) else -1.0,
			"scuttling": (i % 2 == 0),
			"state_timer": _rng.randf_range(1.1, 2.4),
			"speed": _rng.randf_range(1.15, 1.88),
			"anim_phase": _rng.randf() * TAU,
		}
		_crabs.append(entry)


func _spawn_macaw_parrots(count: int, landing_basis: Basis, is_showcase: bool,
		is_volcano: bool) -> void:
	if count <= 0:
		return
	var perches: Array[Dictionary] = []  # {pos: Vector3, yaw: float, score: float}
	var inv_b := landing_basis.inverse()

	# 1. Gather natural tree canopy, rock, and campsite perches from generated island Props!
	var props_root := _island.get_node_or_null(^"Props")
	if props_root != null:
		for child in props_root.get_children():
			var n3 := child as Node3D
			if n3 == null:
				continue
			var cname := n3.name
			var p := n3.position
			var gh := _island.surface_height(p.x, p.z)
			if gh < 0.8 or (is_volcano and gh > 14.0):
				continue
			var lp := inv_b * p
			var cove_score := lp.z + absf(lp.x) * 0.45
			if cname.begins_with("Palm_") or cname.begins_with("Banyan_"):
				var off_ang := _rng.randf() * TAU
				var px := p.x + cos(off_ang) * 0.72
				var pz := p.z + sin(off_ang) * 0.72
				var ph := _island.surface_height(px, pz) + _rng.randf_range(2.2, 4.4)
				perches.append({
					"pos": Vector3(px, ph, pz),
					"yaw": atan2(px, pz),
					"score": cove_score,
				})
			elif cname.begins_with("Boulder_") or cname == "BeachCampfire":
				var px := p.x + (1.1 if cname == "BeachCampfire" else 0.0)
				var pz := p.z + (0.9 if cname == "BeachCampfire" else 0.0)
				var ph := _island.surface_height(px, pz) + (0.15 if cname == "BeachCampfire" else 1.25)
				perches.append({
					"pos": Vector3(px, ph, pz),
					"yaw": atan2(px, pz),
					"score": cove_score - 4.0,
				})

	# 2. Add low coastal beach/rock perches in landing cove so showcase islands always have a
	#    vivid, immediately visible Scarlet Macaw near the sandy shore!
	var coastal := _collect_beach_spots(0.95, 4.8, 0.32, landing_basis, 1.0)
	_sort_cove_first(coastal, landing_basis)
	for ci in mini(coastal.size(), 8):
		var c := coastal[ci]
		var lp := inv_b * c
		perches.append({
			"pos": Vector3(c.x, c.y + 0.15, c.z),
			"yaw": atan2(c.x, c.z),
			"score": lp.z + absf(lp.x) * 0.50 - (14.0 if ci == 0 and is_showcase else 0.0),
		})

	if perches.is_empty():
		return

	perches.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["score"]) < float(b["score"])
	)

	var chosen: Array[Dictionary] = []
	var chosen_pts: Array[Vector3] = []
	for p_info in perches:
		if chosen.size() >= count:
			break
		var pos: Vector3 = p_info["pos"] as Vector3
		var min_sep := 6.5 if chosen.size() < 2 else 11.0
		if _far_from_xz(pos, chosen_pts, min_sep):
			chosen.append(p_info)
			chosen_pts.append(pos)

	for i in chosen.size():
		var p_info: Dictionary = chosen[i]
		var perch_pos: Vector3 = p_info["pos"] as Vector3
		var perch_yaw: float = float(p_info["yaw"])
		# Parrot 0 is always a vibrant Scarlet Macaw; alternate Scarlet & Emerald Amazon across others.
		var is_scarlet := (i == 0) or ((i % 2) == 0)

		var root := Node3D.new()
		root.name = ("ScarletMacaw_%d" if is_scarlet else "EmeraldParrot_%d") % i
		root.position = perch_pos
		var sc := _rng.randf_range(1.02, 1.18)
		root.scale = Vector3.ONE * sc
		add_child(root)

		var tilt_pivot := Node3D.new()
		tilt_pivot.name = "TiltPivot"
		tilt_pivot.position = Vector3(0.0, 0.24, 0.0)
		root.add_child(tilt_pivot)

		var body_mesh := _parrot_scarlet_body if is_scarlet else _parrot_emerald_body
		var wl_mesh := _parrot_scarlet_wing_l if is_scarlet else _parrot_emerald_wing_l
		var wr_mesh := _parrot_scarlet_wing_r if is_scarlet else _parrot_emerald_wing_r
		tilt_pivot.add_child(_make_mesh_inst("BodyMesh", body_mesh, _feather_mat, 195.0))

		var wl_pivot := Node3D.new()
		wl_pivot.name = "LeftWing"
		wl_pivot.position = Vector3(-0.112, 0.085, -0.045)
		tilt_pivot.add_child(wl_pivot)
		wl_pivot.add_child(_make_mesh_inst("LeftWingMesh", wl_mesh, _feather_mat, 195.0))

		var wr_pivot := Node3D.new()
		wr_pivot.name = "RightWing"
		wr_pivot.position = Vector3(0.112, 0.085, -0.045)
		tilt_pivot.add_child(wr_pivot)
		wr_pivot.add_child(_make_mesh_inst("RightWingMesh", wr_mesh, _feather_mat, 195.0))

		var orbit_r := _rng.randf_range(10.5, 17.5)
		var out_xz := Vector2(perch_pos.x, perch_pos.z)
		var out_dir := out_xz.normalized() if out_xz.length_squared() > 0.01 else Vector2(0.0, -1.0)
		var orbit_center := Vector3(
			perch_pos.x + out_dir.x * (orbit_r * 0.45),
			maxf(perch_pos.y + 5.2, 7.5),
			perch_pos.z + out_dir.y * (orbit_r * 0.45)
		)

		var entry := {
			"root": root,
			"tilt_pivot": tilt_pivot,
			"wl_pivot": wl_pivot,
			"wr_pivot": wr_pivot,
			"is_scarlet": is_scarlet,
			"perch_pos": perch_pos,
			"perch_yaw": perch_yaw,
			"state": PARROT_PERCHED,
			"state_time": 0.0,
			"flight_duration": _rng.randf_range(6.2, 8.8),
			"orbit_center": orbit_center,
			"orbit_radius": orbit_r,
			"orbit_angle": atan2(perch_pos.z - orbit_center.z, perch_pos.x - orbit_center.x),
			"orbit_dir": 1.0 if (i % 2 == 0) else -1.0,
			"return_start": perch_pos,
			"return_yaw": perch_yaw,
			"bob_phase": _rng.randf() * TAU,
			"flap_phase": _rng.randf() * TAU,
			"fold_blend": 1.0,
			"bank": 0.0,
			"yaw": perch_yaw,
			"cooldown": 0.0,
		}
		_parrots.append(entry)


func _spawn_butterflies_and_fireflies(count: int, landing_basis: Basis, is_showcase: bool) -> void:
	if count <= 0:
		return
	var glades := _collect_beach_spots(1.25, 15.5, 0.36, landing_basis, 0.5)
	if glades.is_empty():
		glades = _collect_beach_spots(0.75, 18.0, 0.42, landing_basis, 0.3)
	if glades.is_empty():
		return
	_sort_cove_first(glades, landing_basis)

	var placed: Array[Vector3] = []
	var selected: Array[Vector3] = []

	# Guarantee 2 colorful butterflies fluttering near Cutlass Cay / Port Scoundrel landing cove!
	if is_showcase:
		for g in glades:
			if selected.size() >= mini(2, count):
				break
			if g.y >= 1.25 and g.y <= 5.5 and _far_from_xz(g, placed, 3.6):
				selected.append(g)
				placed.append(g)

	var stride := maxi(1, floori(float(glades.size()) / float(maxi(count * 3, 1))))
	var offset := _rng.randi_range(0, maxi(0, glades.size() - 1))
	for step_i in glades.size():
		if selected.size() >= count:
			break
		var idx := (offset + step_i * stride) % glades.size()
		var g := glades[idx]
		if _far_from_xz(g, placed, 6.2):
			selected.append(g)
			placed.append(g)

	for i in selected.size():
		var spot := selected[i]
		var is_morpho := (i % 2) == 0

		var root := Node3D.new()
		root.name = ("ButterflyMorpho_%d" if is_morpho else "ButterflyMonarch_%d") % i
		add_child(root)

		var bf_group := Node3D.new()
		bf_group.name = "ButterflyVisual"
		var b_sc := _rng.randf_range(0.95, 1.22)
		bf_group.scale = Vector3.ONE * b_sc
		root.add_child(bf_group)

		bf_group.add_child(_make_mesh_inst("BodyMesh", _butterfly_body_mesh, _butterfly_mat, 130.0))

		var wl_pivot := Node3D.new()
		wl_pivot.name = "LeftWing"
		wl_pivot.position = Vector3(-0.010, 0.008, -0.004)
		bf_group.add_child(wl_pivot)
		var wl_mesh := _butterfly_morpho_wing_l if is_morpho else _butterfly_monarch_wing_l
		wl_pivot.add_child(_make_mesh_inst("LeftWingMesh", wl_mesh, _butterfly_mat, 130.0))

		var wr_pivot := Node3D.new()
		wr_pivot.name = "RightWing"
		wr_pivot.position = Vector3(0.010, 0.008, -0.004)
		bf_group.add_child(wr_pivot)
		var wr_mesh := _butterfly_morpho_wing_r if is_morpho else _butterfly_monarch_wing_r
		wr_pivot.add_child(_make_mesh_inst("RightWingMesh", wr_mesh, _butterfly_mat, 130.0))

		var ff_group := Node3D.new()
		ff_group.name = "FireflyVisual"
		ff_group.visible = false
		root.add_child(ff_group)
		ff_group.add_child(_make_mesh_inst("FireflyMesh", _firefly_mesh, _firefly_mat, 145.0))

		var entry := {
			"root": root,
			"bf_group": bf_group,
			"ff_group": ff_group,
			"wl_pivot": wl_pivot,
			"wr_pivot": wr_pivot,
			"anchor_x": spot.x,
			"anchor_z": spot.z,
			"hover_h": _rng.randf_range(0.85, 1.85),
			"rx": _rng.randf_range(1.6, 3.2),
			"rz": _rng.randf_range(1.1, 2.4),
			"rot_ang": _rng.randf() * TAU,
			"path_speed": _rng.randf_range(0.55, 0.92),
			"phase": _rng.randf() * TAU,
			"flap_freq": _rng.randf_range(10.2, 13.8),
			"flap_phase": _rng.randf() * TAU,
			"glow_phase": _rng.randf() * TAU,
		}
		_insects.append(entry)


func _make_mesh_inst(node_name: String, mesh: ArrayMesh, mat: StandardMaterial3D,
		vis_end: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visibility_range_end = vis_end
	mi.visibility_range_end_margin = 18.0
	mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	_owned_meshes.append(mi)
	return mi


# ==============================================================================
# Per-Frame Living Fauna Simulation
# ==============================================================================

func _step_parrots(dt: float, has_player: bool, player_local: Vector3) -> void:
	for p in _parrots:
		var root := p["root"] as Node3D
		var tilt := p["tilt_pivot"] as Node3D
		var wl := p["wl_pivot"] as Node3D
		var wr := p["wr_pivot"] as Node3D
		if root == null or not is_instance_valid(root):
			continue

		var state: int = int(p["state"])
		var cooldown: float = maxf(0.0, float(p["cooldown"]) - dt)
		p["cooldown"] = cooldown
		var perch_pos: Vector3 = p["perch_pos"] as Vector3
		var perch_yaw: float = float(p["perch_yaw"])

		# Check player startle proximity while perched (< 9.5 m).
		if state == PARROT_PERCHED and has_player and cooldown <= 0.0:
			if root.position.distance_to(player_local) < PARROT_STARTLE_DIST:
				state = PARROT_FLYING
				p["state"] = state
				p["state_time"] = 0.0
				p["flight_duration"] = _rng.randf_range(6.2, 8.8)
				var oc: Vector3 = p["orbit_center"] as Vector3
				p["orbit_angle"] = atan2(perch_pos.z - oc.z, perch_pos.x - oc.x)
				_play_parrot_chirp(root.global_position if root.is_inside_tree() else perch_pos)

		if state == PARROT_PERCHED:
			var bp: float = float(p["bob_phase"]) + dt * 2.6
			p["bob_phase"] = bp
			var head_bob := sin(bp) * 0.08 + sin(bp * 2.3) * 0.03
			var look_twist := sin(bp * 0.42) * 0.34
			var tail_flick := maxf(0.0, sin(bp * 1.45) - 0.72) * 0.45
			root.position = perch_pos
			root.rotation = Vector3(0.0, perch_yaw + look_twist, 0.0)
			tilt.rotation = Vector3(head_bob - tail_flick, 0.0, sin(bp * 0.65) * 0.06)

			var fb: float = move_toward(float(p["fold_blend"]), 1.0, dt * 4.5)
			p["fold_blend"] = fb
			_apply_parrot_wings(wl, wr, fb, 0.0, 0.0)

		elif state == PARROT_FLYING:
			var st_time: float = float(p["state_time"]) + dt
			p["state_time"] = st_time
			var duration: float = float(p["flight_duration"])
			var oc: Vector3 = p["orbit_center"] as Vector3
			var rad: float = float(p["orbit_radius"])
			var odir: float = float(p["orbit_dir"])
			var ang_spd := 7.6 / maxf(rad, 8.0)
			var ang: float = wrapf(float(p["orbit_angle"]) + odir * ang_spd * dt, 0.0, TAU)
			p["orbit_angle"] = ang

			var ox := oc.x + cos(ang) * rad
			var oz := oc.z + sin(ang) * rad
			var min_clear_y := _island.surface_height(ox, oz) + 3.6
			var oy := maxf(oc.y + sin(ang * 2.0) * 1.15, min_clear_y)
			var orbit_pt := Vector3(ox, oy, oz)

			# Smooth takeoff curve over first 1.05 s from perch onto orbit path.
			var climb_t := clampf(st_time / 1.05, 0.0, 1.0)
			var ease_t := climb_t * climb_t * (3.0 - 2.0 * climb_t)
			var cur_pos := perch_pos.lerp(orbit_pt, ease_t)
			if climb_t < 1.0:
				cur_pos.y += sin(climb_t * PI) * 1.4

			# Analytic tangent direction for smooth yaw, climb pitch & turn bank.
			var next_ang := ang + odir * ang_spd * 0.06
			var nx := oc.x + cos(next_ang) * rad
			var nz := oc.z + sin(next_ang) * rad
			var ny := maxf(oc.y + sin(next_ang * 2.0) * 1.15, _island.surface_height(nx, nz) + 3.6)
			var next_pt := Vector3(nx, ny, nz)
			var vel := (next_pt - orbit_pt) if climb_t >= 1.0 else (orbit_pt - perch_pos + (next_pt - orbit_pt) * 2.5)
			var h_len := Vector2(vel.x, vel.z).length()
			var target_yaw := atan2(-vel.x, -vel.z) if h_len > 0.01 else float(p["yaw"])
			var yaw := lerp_angle(float(p["yaw"]), target_yaw, clampf(dt * 8.0, 0.0, 1.0)) if dt > 0.0 else target_yaw
			p["yaw"] = yaw
			var pitch := clampf(atan2(vel.y, maxf(h_len, 0.5)), -0.35, 0.42)
			var target_bank := clampf(-odir * 0.52, -0.58, 0.58)
			var bank := lerpf(float(p["bank"]), target_bank, clampf(dt * 5.0, 0.0, 1.0))
			p["bank"] = bank

			root.position = cur_pos
			root.rotation = Vector3(0.0, yaw, 0.0)
			tilt.rotation = Vector3(pitch, 0.0, bank)

			var fb: float = move_toward(float(p["fold_blend"]), 0.0, dt * 6.5)
			p["fold_blend"] = fb
			var flap_ph: float = float(p["flap_phase"]) + dt * 11.0 * TAU
			p["flap_phase"] = flap_ph
			# Vigorous 11 Hz wingbeats during climb and rhythmic flight bursts with short banked glides.
			var glide_pulse := 1.0 if (climb_t < 1.0 or sin(st_time * 1.9) > -0.45) else 0.18
			var flap_ang := sin(flap_ph) * 0.72 * glide_pulse + 0.12 * (1.0 - glide_pulse)
			var flap_pitch := cos(flap_ph) * 0.16 * glide_pulse
			_apply_parrot_wings(wl, wr, fb, flap_ang, flap_pitch)

			if st_time >= duration:
				p["state"] = PARROT_RETURNING
				p["state_time"] = 0.0
				p["return_start"] = cur_pos
				p["return_yaw"] = yaw

		else:  # PARROT_RETURNING
			var st_time: float = float(p["state_time"]) + dt
			p["state_time"] = st_time
			var ret_dur := 1.45
			var u := clampf(st_time / ret_dur, 0.0, 1.0)
			var eu := u * u * (3.0 - 2.0 * u)
			var r_start: Vector3 = p["return_start"] as Vector3
			var pos := r_start.lerp(perch_pos, eu)
			pos.y += sin(u * PI) * 1.25
			var to_p := perch_pos - r_start
			var approach_yaw := atan2(-to_p.x, -to_p.z) if Vector2(to_p.x, to_p.z).length_squared() > 0.04 else perch_yaw
			var yaw := lerp_angle(approach_yaw, perch_yaw, clampf((u - 0.55) / 0.45, 0.0, 1.0))
			p["yaw"] = yaw

			root.position = pos
			root.rotation = Vector3(0.0, yaw, 0.0)
			# Flare gently upward just before alighting on perch.
			var flare_pitch := sin(u * PI) * 0.24
			tilt.rotation = Vector3(flare_pitch, 0.0, lerpf(float(p["bank"]), 0.0, eu))

			var fb := clampf((u - 0.65) / 0.35, 0.0, 1.0)
			p["fold_blend"] = fb
			var flap_ph: float = float(p["flap_phase"]) + dt * 11.0 * TAU
			p["flap_phase"] = flap_ph
			var flap_ang := sin(flap_ph) * 0.58 * (1.0 - fb)
			_apply_parrot_wings(wl, wr, fb, flap_ang, cos(flap_ph) * 0.12 * (1.0 - fb))

			if u >= 1.0:
				p["state"] = PARROT_PERCHED
				p["state_time"] = 0.0
				p["cooldown"] = 1.6
				p["bank"] = 0.0


static func _apply_parrot_wings(wl: Node3D, wr: Node3D, fold_blend: float,
		flap_angle: float, flap_pitch: float) -> void:
	# Perched folded pose tucks wings cleanly backward & downward against flanks.
	var fold_x := -0.14
	var fold_y := 1.18
	var fold_z := 0.88
	var lx := lerpf(flap_pitch, fold_x, fold_blend)
	var ly := lerpf(0.0, fold_y, fold_blend)
	var lz := lerpf(-flap_angle, fold_z, fold_blend)
	var rz := lerpf(flap_angle, -fold_z, fold_blend)
	if wl != null:
		wl.rotation = Vector3(lx, ly, lz)
	if wr != null:
		wr.rotation = Vector3(lx, -ly, rz)


func _step_turtles(dt: float, has_player: bool, player_local: Vector3) -> void:
	for t in _turtles:
		var root := t["root"] as Node3D
		var head := t["head_pivot"] as Node3D
		var fl := t["fl_pivot"] as Node3D
		var fr := t["fr_pivot"] as Node3D
		if root == null or not is_instance_valid(root):
			continue

		var lx: float = float(t["lx"])
		var lz: float = float(t["lz"])
		var heading: Vector3 = t["heading"] as Vector3
		var arc_dir: float = float(t["arc_dir"])

		var h_now := _island.surface_height(lx, lz)
		var pos_now := Vector3(lx, h_now, lz)
		var player_close := has_player and pos_now.distance_to(player_local) < TURTLE_SHY_DIST
		var shy_blend := move_toward(float(t["shy_blend"]), 1.0 if player_close else 0.0, dt * 3.2)
		t["shy_blend"] = shy_blend

		var st_timer: float = float(t["state_timer"]) - dt
		var crawling: bool = bool(t["crawling"])
		if st_timer <= 0.0:
			crawling = not crawling
			t["crawling"] = crawling
			st_timer = _rng.randf_range(4.4, 7.8) if crawling else _rng.randf_range(2.8, 5.4)
		t["state_timer"] = st_timer

		var actively_crawling := crawling and not player_close
		if actively_crawling and dt > 0.0:
			var speed: float = float(t["speed"])
			# Steer gently along the island shoreline arc while staying within 0.25..2.4 m & slope < 0.24.
			var radial := Vector3(lx, 0.0, lz)
			if radial.length_squared() > 0.25:
				var tangent := Vector3(-radial.z, 0.0, radial.x).normalized() * arc_dir
				heading = heading.lerp(tangent, clampf(dt * 0.45, 0.0, 1.0)).normalized()
			var step_dist := speed * dt
			var nx := lx + heading.x * step_dist
			var nz := lz + heading.z * step_dist
			var nh := _island.surface_height(nx, nz)
			var nslope := _surface_slope(nx, nz)
			if nh >= 0.25 and nh <= 2.40 and nslope < 0.24 and _is_clear_of_structures(nx, nz, 0.8):
				lx = nx
				lz = nz
				h_now = nh
			else:
				# Smoothly turn back toward safe mid-beach contour / flip arc direction.
				arc_dir = -arc_dir
				t["arc_dir"] = arc_dir
				var turned := Vector3(-heading.x, 0.0, -heading.z).rotated(Vector3.UP, _rng.randf_range(-0.45, 0.45))
				heading = turned.normalized()
			t["lx"] = lx
			t["lz"] = lz
			t["heading"] = heading

		# Strict flush terrain grounding + local surface-normal alignment!
		var ground_y := maxf(0.16, _island.surface_height(lx, lz))
		var normal := _island.surface_normal(lx, lz)
		root.position = Vector3(lx, ground_y, lz)
		root.basis = _surface_aligned_basis(heading, normal) * Basis.from_scale(Vector3.ONE * float(t["scale_val"]))

		# Alternating sweeping front paddle-flipper strokes when crawling, resting cleanly when basking.
		var sp: float = float(t["stroke_phase"])
		if actively_crawling:
			sp += dt * 3.4
			t["stroke_phase"] = sp
			var l_sweep := sin(sp) * 0.46
			var l_lift := maxf(0.0, cos(sp)) * 0.22
			var r_sweep := sin(sp + PI) * 0.46
			var r_lift := maxf(0.0, cos(sp + PI)) * 0.22
			fl.rotation = Vector3(0.04, l_sweep, -l_lift)
			fr.rotation = Vector3(0.04, -r_sweep, r_lift)
		else:
			fl.rotation = fl.rotation.lerp(Vector3(0.0, -0.14, 0.0), clampf(dt * 4.0, 0.0, 1.0))
			fr.rotation = fr.rotation.lerp(Vector3(0.0, 0.14, 0.0), clampf(dt * 4.0, 0.0, 1.0))

		# Gentle breathing head nods + shy inward retraction when player approaches < 3.5 m.
		var bp: float = float(t["breath_phase"]) + dt * 1.85
		t["breath_phase"] = bp
		var nod := sin(bp) * 0.09 * (1.0 - shy_blend)
		head.position = Vector3(0.0, 0.145 - shy_blend * 0.025, -0.50 + shy_blend * 0.14)
		head.rotation = Vector3(nod - shy_blend * 0.12, sin(bp * 0.5) * 0.08 * (1.0 - shy_blend), 0.0)


func _step_crabs(dt: float, has_player: bool, player_local: Vector3) -> void:
	for c in _crabs:
		var root := c["root"] as Node3D
		var body := c["body_pivot"] as Node3D
		var lc := c["lc_pivot"] as Node3D
		var rc := c["rc_pivot"] as Node3D
		if root == null or not is_instance_valid(root):
			continue

		var lx: float = float(c["lx"])
		var lz: float = float(c["lz"])
		var facing: Vector3 = c["facing"] as Vector3
		var scuttle_sign: float = float(c["scuttle_sign"])

		var ground_y := _island.surface_height(lx, lz)
		var pos_now := Vector3(lx, ground_y, lz)
		var fleeing := false
		var move_dir := Vector3.ZERO

		if has_player:
			var from_player := pos_now - player_local
			from_player.y = 0.0
			var pdist := from_player.length()
			if pdist < CRAB_FLEE_DIST:
				fleeing = true
				var away := from_player.normalized() if pdist > 0.01 else Vector3(1.0, 0.0, 0.0)
				# Orient crab roughly perpendicular to flee vector so it darts briskly SIDEWAYS away!
				facing = Vector3(-away.z, 0.0, away.x).normalized()
				scuttle_sign = 1.0
				move_dir = away

		var scuttling: bool = bool(c["scuttling"])
		if not fleeing:
			var st_timer: float = float(c["state_timer"]) - dt
			if st_timer <= 0.0:
				scuttling = not scuttling
				c["scuttling"] = scuttling
				if scuttling and _rng.randf() < 0.45:
					scuttle_sign = -scuttle_sign
					c["scuttle_sign"] = scuttle_sign
				st_timer = _rng.randf_range(0.85, 2.15) if scuttling else _rng.randf_range(1.25, 2.95)
			c["state_timer"] = st_timer
			if scuttling:
				# Snappy sideways scuttle along crab's local +/-X axis!
				var side := Vector3(facing.z, 0.0, -facing.x).normalized() * scuttle_sign
				move_dir = side

		var moving := (fleeing or scuttling) and move_dir.length_squared() > 0.01
		if moving and dt > 0.0:
			var spd := (float(c["speed"]) * 1.25) if fleeing else float(c["speed"])
			var nx := lx + move_dir.x * spd * dt
			var nz := lz + move_dir.z * spd * dt
			var nh := _island.surface_height(nx, nz)
			var nslope := _surface_slope(nx, nz)
			if nh >= 0.20 and nh <= 3.60 and nslope < 0.30 and _is_clear_of_structures(nx, nz, 0.4):
				lx = nx
				lz = nz
				ground_y = nh
			else:
				scuttle_sign = -scuttle_sign
				c["scuttle_sign"] = scuttle_sign
				facing = facing.rotated(Vector3.UP, _rng.randf_range(0.6, 1.4)).normalized()
			c["lx"] = lx
			c["lz"] = lz
			c["facing"] = facing

		ground_y = maxf(0.16, _island.surface_height(lx, lz))
		var normal := _island.surface_normal(lx, lz)
		root.position = Vector3(lx, ground_y, lz)
		root.basis = _surface_aligned_basis(facing, normal) * Basis.from_scale(Vector3.ONE * float(c["scale_val"]))

		var ap: float = float(c["anim_phase"]) + dt * (18.0 if moving else 5.2)
		c["anim_phase"] = ap
		if moving:
			# Brisk sideways leg-patter wobble + raised defensive pincers when fleeing.
			body.position = Vector3(0.0, absf(sin(ap)) * 0.016, 0.0)
			body.rotation = Vector3(0.0, 0.0, sin(ap) * 0.11)
			var raise := 0.55 if fleeing else 0.22
			lc.rotation = Vector3(raise + sin(ap * 0.5) * 0.10, 0.15, 0.12)
			rc.rotation = Vector3(raise - sin(ap * 0.5) * 0.10, -0.15, -0.12)
		else:
			# Paused: playfully raise and wave snapping front pincer claws!
			body.position = Vector3.ZERO
			body.rotation = Vector3.ZERO
			var wave_l := 0.38 + sin(ap) * 0.34
			var wave_r := 0.38 + sin(ap + 1.4) * 0.34
			lc.rotation = Vector3(wave_l, 0.18 + cos(ap) * 0.14, 0.14)
			rc.rotation = Vector3(wave_r, -0.18 - cos(ap + 1.4) * 0.14, -0.14)


func _step_insects(dt: float) -> void:
	var day_mode := is_daytime_mode()
	for ins in _insects:
		var root := ins["root"] as Node3D
		var bf := ins["bf_group"] as Node3D
		var ff := ins["ff_group"] as Node3D
		var wl := ins["wl_pivot"] as Node3D
		var wr := ins["wr_pivot"] as Node3D
		if root == null or not is_instance_valid(root):
			continue

		bf.visible = day_mode
		ff.visible = not day_mode

		var speed_scale := 1.0 if day_mode else 0.42
		var ph: float = float(ins["phase"]) + dt * float(ins["path_speed"]) * speed_scale
		ins["phase"] = ph

		var ax: float = float(ins["anchor_x"])
		var az: float = float(ins["anchor_z"])
		var rx: float = float(ins["rx"])
		var rz: float = float(ins["rz"])
		var rot: float = float(ins["rot_ang"])
		var cr := cos(rot)
		var sr := sin(rot)

		# Organic figure-8 Lissajous path above glade terrain.
		var fx := sin(ph) * rx
		var fz := sin(ph * 2.0) * rz * 0.5
		var lx := ax + fx * cr - fz * sr
		var lz := az + fx * sr + fz * cr

		var ph_next := ph + 0.05
		var nfx := sin(ph_next) * rx
		var nfz := sin(ph_next * 2.0) * rz * 0.5
		var nlx := ax + nfx * cr - nfz * sr
		var nlz := az + nfx * sr + nfz * cr

		var ground_y := maxf(0.25, _island.surface_height(lx, lz))
		var hover_h: float = float(ins["hover_h"])
		var bob := sin(ph * 2.7 + float(ins["glow_phase"])) * (0.34 if day_mode else 0.24)
		var ly := ground_y + clampf(hover_h + bob, 0.55, 2.20)
		root.position = Vector3(lx, ly, lz)

		var dx := nlx - lx
		var dz := nlz - lz
		if dx * dx + dz * dz > 1e-6:
			var yaw := atan2(-dx, -dz)
			var bank := clampf(cos(ph * 2.0) * 0.34, -0.40, 0.40) if day_mode else 0.0
			root.rotation = Vector3(0.08 if day_mode else 0.0, yaw, bank)

		if day_mode:
			var fp: float = float(ins["flap_phase"]) + dt * float(ins["flap_freq"]) * TAU
			ins["flap_phase"] = fp
			var wing_ang := sin(fp) * 0.92 + 0.14
			wl.rotation = Vector3(0.0, 0.0, -wing_ang)
			wr.rotation = Vector3(0.0, 0.0, wing_ang)
		else:
			var gp: float = float(ins["glow_phase"]) + dt * 3.1
			ins["glow_phase"] = gp
			var pulse := 0.80 + 0.32 * (0.5 + 0.5 * sin(gp))
			ff.scale = Vector3.ONE * pulse


static func _surface_aligned_basis(forward_hint: Vector3, normal: Vector3) -> Basis:
	var up := normal.normalized() if normal.length_squared() > 0.001 else Vector3.UP
	var fwd := forward_hint - up * forward_hint.dot(up)
	if fwd.length_squared() < 1e-5:
		fwd = Vector3.FORWARD - up * Vector3.FORWARD.dot(up)
	if fwd.length_squared() < 1e-5:
		fwd = Vector3.RIGHT
	fwd = fwd.normalized()
	var z_axis := -fwd
	var x_axis := up.cross(z_axis)
	if x_axis.length_squared() < 1e-5:
		x_axis = Vector3.RIGHT
	x_axis = x_axis.normalized()
	z_axis = x_axis.cross(up).normalized()
	return Basis(x_axis, up, z_axis)


static func _play_parrot_chirp(world_pos: Vector3) -> void:
	if Audio == null:
		return
	var sfx_section: Variant = Audio.catalogue.get("sfx", null)
	if not (sfx_section is Dictionary):
		return
	var sfx_dict := sfx_section as Dictionary
	var chosen := &""
	var pitch_override := 1.0
	if sfx_dict.has("parrot_chirp") and Audio.has_sound(&"parrot_chirp"):
		chosen = &"parrot_chirp"
	elif sfx_dict.has("parrot") and Audio.has_sound(&"parrot"):
		chosen = &"parrot"
	elif sfx_dict.has("seagull") and Audio.has_sound(&"seagull"):
		chosen = &"seagull"
		pitch_override = 1.46
	if chosen == &"":
		return
	var player := Audio.play_sfx(chosen, world_pos, -5.0, 0.08)
	if player is AudioStreamPlayer3D and pitch_override != 1.0:
		(player as AudioStreamPlayer3D).pitch_scale *= pitch_override


# ==============================================================================
# Shared Procedural Sculpted Meshes (`SurfaceTool`, ZERO PrimitiveMeshes!)
# ==============================================================================

static func _ensure_shared_assets() -> void:
	if _feather_mat == null:
		_feather_mat = StandardMaterial3D.new()
		_feather_mat.albedo_color = Color.WHITE
		_feather_mat.vertex_color_use_as_albedo = true
		_feather_mat.vertex_color_is_srgb = true
		_feather_mat.uv1_world_triplanar = false
		_feather_mat.roughness = 0.76
		_feather_mat.metallic = 0.02

	if _shell_mat == null:
		_shell_mat = StandardMaterial3D.new()
		_shell_mat.albedo_color = Color.WHITE
		_shell_mat.vertex_color_use_as_albedo = true
		_shell_mat.vertex_color_is_srgb = true
		_shell_mat.uv1_world_triplanar = false
		_shell_mat.roughness = 0.46
		_shell_mat.metallic = 0.04
		_shell_mat.clearcoat_enabled = true
		_shell_mat.clearcoat = 0.28
		_shell_mat.clearcoat_roughness = 0.34

	if _butterfly_mat == null:
		_butterfly_mat = StandardMaterial3D.new()
		_butterfly_mat.albedo_color = Color.WHITE
		_butterfly_mat.vertex_color_use_as_albedo = true
		_butterfly_mat.vertex_color_is_srgb = true
		_butterfly_mat.uv1_world_triplanar = false
		_butterfly_mat.roughness = 0.36
		_butterfly_mat.metallic = 0.14

	if _firefly_mat == null:
		_firefly_mat = StandardMaterial3D.new()
		_firefly_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_firefly_mat.albedo_color = Color(1.42, 1.24, 0.72)
		_firefly_mat.vertex_color_use_as_albedo = true
		_firefly_mat.vertex_color_is_srgb = true
		_firefly_mat.uv1_world_triplanar = false

	if _parrot_scarlet_body == null:
		var scarlet_pal := {
			"main": COL_SCARLET_MAIN,
			"deep": COL_SCARLET_DEEP,
			"accent": COL_SCARLET_GOLD,
			"tip": COL_SCARLET_COBALT,
			"cheek": COL_SCARLET_CHEEK,
			"crown": COL_SCARLET_MAIN,
		}
		_parrot_scarlet_body = _build_parrot_body_mesh(scarlet_pal)
		_parrot_scarlet_wing_l = _build_parrot_wing_mesh(-1.0, scarlet_pal)
		_parrot_scarlet_wing_r = _build_parrot_wing_mesh(1.0, scarlet_pal)

	if _parrot_emerald_body == null:
		var emerald_pal := {
			"main": COL_EMERALD_MAIN,
			"deep": COL_EMERALD_DEEP,
			"accent": COL_EMERALD_LIME,
			"tip": COL_EMERALD_TEAL,
			"cheek": COL_EMERALD_LIME,
			"crown": COL_EMERALD_CROWN,
		}
		_parrot_emerald_body = _build_parrot_body_mesh(emerald_pal)
		_parrot_emerald_wing_l = _build_parrot_wing_mesh(-1.0, emerald_pal)
		_parrot_emerald_wing_r = _build_parrot_wing_mesh(1.0, emerald_pal)

	if _turtle_body_mesh == null:
		_turtle_body_mesh = _build_turtle_body_mesh()
		_turtle_head_mesh = _build_turtle_head_mesh()
		_turtle_flipper_l_mesh = _build_turtle_flipper_mesh(-1.0)
		_turtle_flipper_r_mesh = _build_turtle_flipper_mesh(1.0)

	if _crab_body_mesh == null:
		_crab_body_mesh = _build_crab_body_mesh()
		_crab_claw_l_mesh = _build_crab_claw_mesh(-1.0)
		_crab_claw_r_mesh = _build_crab_claw_mesh(1.0)

	if _butterfly_body_mesh == null:
		_butterfly_body_mesh = _build_butterfly_body_mesh()
		_butterfly_morpho_wing_l = _build_butterfly_wing_mesh(-1.0, COL_MORPHO_INNER, COL_MORPHO_MID, COL_MORPHO_RIM, COL_MORPHO_DOT)
		_butterfly_morpho_wing_r = _build_butterfly_wing_mesh(1.0, COL_MORPHO_INNER, COL_MORPHO_MID, COL_MORPHO_RIM, COL_MORPHO_DOT)
		_butterfly_monarch_wing_l = _build_butterfly_wing_mesh(-1.0, COL_MONARCH_INNER, COL_MONARCH_MID, COL_MONARCH_RIM, COL_MONARCH_DOT)
		_butterfly_monarch_wing_r = _build_butterfly_wing_mesh(1.0, COL_MONARCH_INNER, COL_MONARCH_MID, COL_MONARCH_RIM, COL_MONARCH_DOT)
		_firefly_mesh = _build_firefly_mesh()


# ------------------------------------------------------------------------------
# Species 1 Mesh Builders: Tropical Macaw Parrot (>= 380 tris total)
# ------------------------------------------------------------------------------

static func _build_parrot_body_mesh(pal: Dictionary) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var c_main: Color = pal["main"] as Color
	var c_deep: Color = pal["deep"] as Color
	var c_acc: Color = pal["accent"] as Color
	var c_tip: Color = pal["tip"] as Color
	var c_cheek: Color = pal["cheek"] as Color
	var c_crown: Color = pal["crown"] as Color

	# 1. Contoured torso, proud chest, neck & rounded crown (10 stations x 10 segs = 200 tris).
	var body_stations: Array[Array] = [
		[Vector3(0.0, -0.055, 0.240), 0.044, 0.040, 0.036, c_tip, c_deep, c_deep],
		[Vector3(0.0, -0.025, 0.155), 0.088, 0.082, 0.074, c_main, c_main, c_deep],
		[Vector3(0.0, 0.015, 0.055), 0.118, 0.114, 0.106, c_main, c_main, c_deep],
		[Vector3(0.0, 0.068, -0.045), 0.126, 0.122, 0.118, c_main, c_main, c_main],
		[Vector3(0.0, 0.135, -0.105), 0.108, 0.102, 0.098, c_main, c_main, c_main],
		[Vector3(0.0, 0.205, -0.135), 0.082, 0.078, 0.074, c_main, c_main, c_main],
		[Vector3(0.0, 0.265, -0.150), 0.085, 0.080, 0.072, c_crown, c_cheek, c_main],
		[Vector3(0.0, 0.312, -0.158), 0.080, 0.074, 0.068, c_crown, c_cheek, c_cheek],
		[Vector3(0.0, 0.352, -0.148), 0.058, 0.048, 0.042, c_crown, c_crown, c_cheek],
		[Vector3(0.0, 0.372, -0.128), 0.024, 0.018, 0.018, c_crown, c_crown, c_crown],
	]
	_append_curved_tube(st, body_stations, 10, true, true)

	# 2. Sculpted curved raptor-like hooked upper beak (5 stations x 6 segs = 54 tris).
	var upper_beak: Array[Array] = [
		[Vector3(0.0, 0.302, -0.212), 0.040, 0.038, 0.022, COL_BEAK_IVORY, COL_BEAK_IVORY, COL_BEAK_DARK],
		[Vector3(0.0, 0.296, -0.258), 0.032, 0.032, 0.018, COL_BEAK_IVORY, COL_BEAK_IVORY, COL_BEAK_DARK],
		[Vector3(0.0, 0.278, -0.296), 0.022, 0.022, 0.014, COL_BEAK_IVORY, COL_BEAK_IVORY, COL_BEAK_DARK],
		[Vector3(0.0, 0.246, -0.318), 0.013, 0.014, 0.010, COL_BEAK_DARK, COL_BEAK_DARK, COL_BEAK_DARK],
		[Vector3(0.0, 0.208, -0.314), 0.005, 0.006, 0.005, COL_BEAK_DARK, COL_BEAK_DARK, COL_BEAK_DARK],
	]
	_append_curved_tube(st, upper_beak, 6, false, true)

	# Lower hooked charcoal mandible (3 stations x 6 segs = 30 tris).
	var lower_beak: Array[Array] = [
		[Vector3(0.0, 0.258, -0.208), 0.030, 0.018, 0.024, COL_BEAK_DARK, COL_BEAK_DARK, COL_BEAK_DARK],
		[Vector3(0.0, 0.250, -0.246), 0.022, 0.014, 0.018, COL_BEAK_DARK, COL_BEAK_DARK, COL_BEAK_DARK],
		[Vector3(0.0, 0.252, -0.272), 0.010, 0.008, 0.009, COL_BEAK_DARK, COL_BEAK_DARK, COL_BEAK_DARK],
	]
	_append_curved_tube(st, lower_beak, 6, false, true)

	# 3. Expressive arched head crest plumes (3 sculpted feather blades = 24 tris).
	var crest_specs: Array[Array] = [
		[Vector3(0.0, 0.362, -0.155), Vector3(0.0, 0.420, -0.125), Vector3(0.0, 0.445, -0.075), 0.020, 0.010],
		[Vector3(-0.020, 0.354, -0.145), Vector3(-0.032, 0.405, -0.105), Vector3(-0.040, 0.418, -0.052), 0.016, 0.008],
		[Vector3(0.020, 0.354, -0.145), Vector3(0.032, 0.405, -0.105), Vector3(0.040, 0.418, -0.052), 0.016, 0.008],
	]
	for cs in crest_specs:
		_append_feather_blade(st, cs[0] as Vector3, cs[1] as Vector3, cs[2] as Vector3,
			Vector3.RIGHT, float(cs[3]), float(cs[4]), c_crown, c_acc, c_main)

	# 4. Expressive eyes on cheek patches (2 x 12 = 24 tris).
	for sgn: float in [-1.0, 1.0]:
		_append_eye_dome(st, Vector3(sgn * 0.074, 0.308, -0.186),
			Vector3(sgn * 0.92, 0.10, -0.36).normalized(), 0.022, COL_EYE_RING, COL_EYE_DARK)

	# 5. Long tapered scarlet-gold-cobalt tail feathers (3 overlapping plumes = 108 tris).
	var tail_plumes: Array[Array] = [
		[0.0, 0.0, 0.78, -0.20, 0.036],
		[-0.044, 0.012, 0.65, -0.16, 0.028],
		[0.044, 0.012, 0.65, -0.16, 0.028],
	]
	for tp in tail_plumes:
		var tx: float = float(tp[0])
		var ty_off: float = float(tp[1])
		var tlen: float = float(tp[2])
		var tdrop: float = float(tp[3])
		var tw: float = float(tp[4])
		var tail_st: Array[Array] = [
			[Vector3(tx * 0.35, -0.050 + ty_off, 0.22), tw * 0.90, 0.012, 0.010, c_main, c_main, c_deep],
			[Vector3(tx * 0.70, -0.088 + ty_off, 0.22 + (tlen - 0.22) * 0.33), tw, 0.010, 0.008, c_main, c_acc, c_deep],
			[Vector3(tx * 0.92, -0.130 + ty_off, 0.22 + (tlen - 0.22) * 0.66), tw * 0.78, 0.008, 0.006, c_acc, c_tip, c_tip],
			[Vector3(tx, tdrop + ty_off, tlen), tw * 0.24, 0.005, 0.004, c_tip, c_tip, c_tip],
		]
		_append_curved_tube(st, tail_st, 4, false, true)

	# 6. Perched talon feet descending cleanly to y = -0.24 (2 legs + 6 gripping toes = 120 tris).
	for sgn: float in [-1.0, 1.0]:
		var lx := sgn * 0.056
		var leg_st: Array[Array] = [
			[Vector3(lx, -0.075, 0.025), 0.028, 0.026, 0.026, c_deep, c_deep, c_deep],
			[Vector3(lx, -0.155, 0.015), 0.016, 0.016, 0.016, COL_TALON_SLATE, COL_TALON_SLATE, COL_TALON_SLATE],
			[Vector3(lx, -0.228, 0.008), 0.013, 0.013, 0.013, COL_TALON_SLATE, COL_TALON_SLATE, COL_TALON_SLATE],
		]
		_append_curved_tube(st, leg_st, 6, false, true)
		var toe_dirs: Array[Vector3] = [
			Vector3(sgn * 0.022, -0.014, -0.068),
			Vector3(-sgn * 0.016, -0.014, -0.064),
			Vector3(0.0, -0.012, 0.056),
		]
		for td in toe_dirs:
			var t0 := Vector3(lx, -0.224, 0.008)
			var t1 := t0 + td * 0.55 + Vector3(0.0, 0.004, 0.0)
			var t2 := t0 + td
			var toe_st: Array[Array] = [
				[t0, 0.008, 0.008, 0.007, COL_TALON_SLATE, COL_TALON_SLATE, COL_TALON_SLATE],
				[t1, 0.007, 0.007, 0.006, COL_TALON_SLATE, COL_TALON_SLATE, COL_TALON_SLATE],
				[t2, 0.003, 0.003, 0.003, COL_BEAK_DARK, COL_BEAK_DARK, COL_BEAK_DARK],
			]
			_append_curved_tube(st, toe_st, 4, false, true)

	st.generate_normals()
	return st.commit()


static func _build_parrot_wing_mesh(side_sgn: float, pal: Dictionary) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var c_main: Color = pal["main"] as Color
	var c_deep: Color = pal["deep"] as Color
	var c_acc: Color = pal["accent"] as Color
	var c_tip: Color = pal["tip"] as Color

	# Cambered tropical macaw wing: [span_x, z_lead, z_trail, thick_top, thick_bot, y_arc, col_lead, col_trail]
	var sections: Array[Array] = [
		[0.00, -0.14, 0.17, 0.044, 0.026, 0.000, c_main, c_deep],
		[0.12, -0.15, 0.18, 0.040, 0.022, 0.024, c_main, c_acc],
		[0.25, -0.14, 0.17, 0.032, 0.017, 0.036, c_acc, c_acc],
		[0.39, -0.11, 0.15, 0.022, 0.012, 0.032, c_acc, c_tip],
		[0.50, -0.07, 0.12, 0.013, 0.008, 0.020, c_tip, c_tip],
		[0.58, -0.02, 0.09, 0.006, 0.005, 0.008, c_tip, c_tip],
	]

	var rings: Array[Array] = []
	var cols: Array[Array] = []
	for s_row in sections:
		var sx: float = side_sgn * float(s_row[0])
		var zl: float = float(s_row[1])
		var zt: float = float(s_row[2])
		var tt: float = float(s_row[3])
		var tb: float = float(s_row[4])
		var dy: float = float(s_row[5])
		var cl: Color = s_row[6] as Color
		var ct: Color = s_row[7] as Color
		var chord := zt - zl
		var pts: Array[Vector3] = [
			Vector3(sx, dy, zl),
			Vector3(sx, dy + tt, zl + chord * 0.34),
			Vector3(sx, dy + tt * 0.58, zl + chord * 0.72),
			Vector3(sx, dy, zt),
			Vector3(sx, dy - tb * 0.55, zl + chord * 0.68),
			Vector3(sx, dy - tb, zl + chord * 0.30),
		]
		var rcols: Array[Color] = [cl, cl, ct, ct, c_deep, c_main]
		rings.append(pts)
		cols.append(rcols)

	for si in range(sections.size() - 1):
		var r0: Array = rings[si]
		var r1: Array = rings[si + 1]
		var c0: Array = cols[si]
		var c1: Array = cols[si + 1]
		var mid := Vector3(
			side_sgn * (float(sections[si][0]) + float(sections[si + 1][0])) * 0.5,
			(float(sections[si][5]) + float(sections[si + 1][5])) * 0.5,
			(float(sections[si][1]) + float(sections[si][2])) * 0.5
		)
		for k in 6:
			var nk := (k + 1) % 6
			_emit_outward_quad(st,
				r0[k] as Vector3, c0[k] as Color,
				r1[k] as Vector3, c1[k] as Color,
				r1[nk] as Vector3, c1[nk] as Color,
				r0[nk] as Vector3, c0[nk] as Color, mid)

	# Cap root and wingtip cleanly.
	var root_c := Vector3(0.0, 0.0, 0.015)
	var tip_i := rings.size() - 1
	var tip_c := Vector3(side_sgn * 0.60, 0.006, 0.035)
	for k in 6:
		var nk := (k + 1) % 6
		_emit_outward_tri(st, root_c, c_deep,
			rings[0][nk] as Vector3, cols[0][nk] as Color,
			rings[0][k] as Vector3, cols[0][k] as Color,
			Vector3(side_sgn * 0.18, 0.0, 0.015))
		_emit_outward_tri(st, tip_c, c_tip,
			rings[tip_i][k] as Vector3, cols[tip_i][k] as Color,
			rings[tip_i][nk] as Vector3, cols[tip_i][nk] as Color,
			Vector3(side_sgn * 0.44, 0.01, 0.035))

	# 4 splayed primary wingtip flight feathers (4 x 8 = 32 tris).
	for fi in 4:
		var fu := float(fi) / 3.0
		var base := Vector3(side_sgn * lerpf(0.45, 0.56, fu), 0.016 - fu * 0.008, lerpf(0.08, -0.02, fu))
		var mid_f := base + Vector3(side_sgn * 0.09, -0.004, lerpf(0.05, -0.02, fu))
		var tip_f := base + Vector3(side_sgn * 0.17, -0.010, lerpf(0.09, -0.03, fu))
		_append_feather_blade(st, base, mid_f, tip_f, Vector3(0.0, 0.0, 1.0), 0.020, 0.005, c_acc, c_tip, c_tip)

	st.generate_normals()
	return st.commit()


# ------------------------------------------------------------------------------
# Species 2 Mesh Builders: Giant Tropical Sea Turtle (>= 440 tris total)
# ------------------------------------------------------------------------------

static func _build_turtle_body_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# 1. Domed hexagonal-faceted olive/amber carapace + beveled marginal rim + sandy plastron.
	# Rings from bottom plastron up around beveled rim over domed scutes to crown:
	# [rx_scale, rz_scale, y, scute_bump, col_a, col_b]
	var ax := 0.46
	var bz := 0.58
	var segs := 12
	var shell_rows: Array[Array] = [
		[0.34, 0.36, 0.024, 0.000, COL_PLASTRON_SAND, COL_PLASTRON_SAND],
		[0.72, 0.74, 0.032, 0.000, COL_PLASTRON_SAND, COL_TURTLE_EDGE],
		[0.98, 0.98, 0.062, 0.000, COL_TURTLE_EDGE, COL_SHELL_RIM],
		[1.07, 1.06, 0.108, 0.004, COL_SHELL_RIM, COL_SHELL_AMBER],
		[1.00, 1.00, 0.150, 0.006, COL_SHELL_DARK, COL_SHELL_OLIVE],
		[0.86, 0.86, 0.255, 0.014, COL_SHELL_OLIVE, COL_SHELL_AMBER],
		[0.64, 0.64, 0.345, 0.016, COL_SHELL_AMBER, COL_SHELL_OLIVE],
		[0.38, 0.38, 0.405, 0.014, COL_SHELL_OLIVE, COL_SHELL_DARK],
		[0.14, 0.14, 0.434, 0.008, COL_SHELL_AMBER, COL_SHELL_OLIVE],
	]

	var rings: Array[Array] = []
	var rcols: Array[Array] = []
	for ri in shell_rows.size():
		var row: Array = shell_rows[ri]
		var rsx: float = float(row[0]) * ax
		var rsz: float = float(row[1]) * bz
		var ry: float = float(row[2])
		var bump: float = float(row[3])
		var ca: Color = row[4] as Color
		var cb: Color = row[5] as Color
		var pts: Array[Vector3] = []
		var cls: Array[Color] = []
		for k in segs:
			var ang := float(k) / float(segs) * TAU
			var hex_ridge := bump * (1.0 if ((k + ri) % 2 == 0) else -0.45)
			# Slight oval taper at rear of shell (+Z) for authentic hawksbill/green silhouette.
			var sz := sin(ang)
			var rear_taper := 1.0 - maxf(0.0, sz) * 0.08
			var px := cos(ang) * rsx * rear_taper
			var pz := sz * rsz
			pts.append(Vector3(px, ry + hex_ridge, pz))
			cls.append(ca if ((k + ri) % 2 == 0) else cb)
		rings.append(pts)
		rcols.append(cls)

	var shell_center := Vector3(0.0, 0.18, 0.0)
	for ri in range(rings.size() - 1):
		var r0: Array = rings[ri]
		var r1: Array = rings[ri + 1]
		var c0: Array = rcols[ri]
		var c1: Array = rcols[ri + 1]
		for k in segs:
			var nk := (k + 1) % segs
			_emit_outward_quad(st,
				r0[k] as Vector3, c0[k] as Color,
				r1[k] as Vector3, c1[k] as Color,
				r1[nk] as Vector3, c1[nk] as Color,
				r0[nk] as Vector3, c0[nk] as Color, shell_center)

	# Close plastron bottom center and carapace dorsal crown scute.
	var bot_c := Vector3(0.0, 0.020, 0.0)
	var top_i := rings.size() - 1
	var top_c := Vector3(0.0, 0.442, -0.02)
	for k in segs:
		var nk := (k + 1) % segs
		_emit_outward_tri(st, bot_c, COL_PLASTRON_SAND,
			rings[0][nk] as Vector3, rcols[0][nk] as Color,
			rings[0][k] as Vector3, rcols[0][k] as Color, shell_center)
		_emit_outward_tri(st, top_c, COL_SHELL_AMBER,
			rings[top_i][k] as Vector3, rcols[top_i][k] as Color,
			rings[top_i][nk] as Vector3, rcols[top_i][nk] as Color, shell_center)

	# 2. Broad sculpted rear paddle flippers (2 x 60 = 120 tris).
	for sgn: float in [-1.0, 1.0]:
		var rear_st: Array[Array] = [
			[Vector3(sgn * 0.22, 0.075, 0.42), 0.075, 0.042, 0.032, COL_TURTLE_SCALE, COL_TURTLE_SKIN, COL_PLASTRON_SAND],
			[Vector3(sgn * 0.30, 0.062, 0.52), 0.092, 0.032, 0.024, COL_TURTLE_SCALE, COL_TURTLE_EDGE, COL_PLASTRON_SAND],
			[Vector3(sgn * 0.38, 0.048, 0.62), 0.098, 0.022, 0.018, COL_TURTLE_SKIN, COL_TURTLE_EDGE, COL_PLASTRON_SAND],
			[Vector3(sgn * 0.43, 0.038, 0.71), 0.068, 0.014, 0.012, COL_TURTLE_SCALE, COL_TURTLE_EDGE, COL_TURTLE_EDGE],
			[Vector3(sgn * 0.44, 0.032, 0.77), 0.026, 0.008, 0.007, COL_TURTLE_SCALE, COL_TURTLE_SCALE, COL_TURTLE_EDGE],
		]
		_append_curved_tube(st, rear_st, 6, false, true)

	# 3. Stubby sculpted tail (30 tris).
	var tail_st: Array[Array] = [
		[Vector3(0.0, 0.076, 0.54), 0.044, 0.034, 0.028, COL_TURTLE_SCALE, COL_TURTLE_SKIN, COL_PLASTRON_SAND],
		[Vector3(0.0, 0.064, 0.63), 0.028, 0.022, 0.018, COL_TURTLE_SCALE, COL_TURTLE_SKIN, COL_TURTLE_EDGE],
		[Vector3(0.0, 0.052, 0.72), 0.010, 0.009, 0.008, COL_TURTLE_SCALE, COL_TURTLE_SCALE, COL_TURTLE_SCALE],
	]
	_append_curved_tube(st, tail_st, 6, false, true)

	st.generate_normals()
	return st.commit()


static func _build_turtle_head_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Plated arched neck & sculpted skull (7 stations x 8 segs = 104 tris + 24 eye tris = 128 tris).
	var head_st: Array[Array] = [
		[Vector3(0.0, -0.010, 0.14), 0.092, 0.078, 0.066, COL_TURTLE_SCALE, COL_TURTLE_SKIN, COL_PLASTRON_SAND],
		[Vector3(0.0, 0.006, 0.03), 0.084, 0.072, 0.060, COL_TURTLE_SKIN, COL_TURTLE_SKIN, COL_PLASTRON_SAND],
		[Vector3(0.0, 0.032, -0.08), 0.088, 0.076, 0.062, COL_TURTLE_SCALE, COL_TURTLE_EDGE, COL_PLASTRON_SAND],
		[Vector3(0.0, 0.052, -0.17), 0.098, 0.088, 0.070, COL_TURTLE_SCALE, COL_TURTLE_SKIN, COL_TURTLE_EDGE],
		[Vector3(0.0, 0.044, -0.25), 0.084, 0.074, 0.058, COL_TURTLE_SKIN, COL_TURTLE_EDGE, COL_PLASTRON_SAND],
		[Vector3(0.0, 0.024, -0.31), 0.056, 0.048, 0.038, COL_TURTLE_EDGE, COL_TURTLE_SKIN, COL_PLASTRON_SAND],
		[Vector3(0.0, 0.008, -0.35), 0.022, 0.022, 0.018, COL_TURTLE_EDGE, COL_TURTLE_EDGE, COL_TURTLE_EDGE],
	]
	_append_curved_tube(st, head_st, 8, false, true)

	for sgn: float in [-1.0, 1.0]:
		_append_eye_dome(st, Vector3(sgn * 0.076, 0.064, -0.220),
			Vector3(sgn * 0.85, 0.25, -0.45).normalized(), 0.022, COL_TURTLE_EDGE, COL_EYE_DARK)

	st.generate_normals()
	return st.commit()


static func _build_turtle_flipper_mesh(side_sgn: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Broad sculpted sea-turtle front paddle flipper:
	# [span_x, z_lead, z_trail, thick_top, thick_bot, y_off]
	var sections: Array[Array] = [
		[0.00, -0.10, 0.10, 0.052, 0.038, 0.000],
		[0.14, -0.13, 0.11, 0.042, 0.028, -0.018],
		[0.29, -0.12, 0.12, 0.030, 0.020, -0.042],
		[0.43, -0.06, 0.15, 0.020, 0.014, -0.062],
		[0.54, 0.02, 0.17, 0.012, 0.009, -0.074],
		[0.61, 0.09, 0.18, 0.006, 0.005, -0.080],
	]

	var rings: Array[Array] = []
	var cols: Array[Array] = []
	for s_row in sections:
		var sx: float = side_sgn * float(s_row[0])
		var zl: float = float(s_row[1])
		var zt: float = float(s_row[2])
		var tt: float = float(s_row[3])
		var tb: float = float(s_row[4])
		var dy: float = float(s_row[5])
		var chord := zt - zl
		var pts: Array[Vector3] = [
			Vector3(sx, dy, zl),
			Vector3(sx, dy + tt, zl + chord * 0.32),
			Vector3(sx, dy + tt * 0.65, zl + chord * 0.72),
			Vector3(sx, dy, zt),
			Vector3(sx, dy - tb * 0.60, zl + chord * 0.70),
			Vector3(sx, dy - tb, zl + chord * 0.30),
		]
		var rcols: Array[Color] = [
			COL_TURTLE_EDGE, COL_TURTLE_SCALE, COL_TURTLE_SKIN,
			COL_TURTLE_EDGE, COL_PLASTRON_SAND, COL_PLASTRON_SAND,
		]
		rings.append(pts)
		cols.append(rcols)

	for si in range(sections.size() - 1):
		var r0: Array = rings[si]
		var r1: Array = rings[si + 1]
		var c0: Array = cols[si]
		var c1: Array = cols[si + 1]
		var mid := Vector3(
			side_sgn * (float(sections[si][0]) + float(sections[si + 1][0])) * 0.5,
			(float(sections[si][5]) + float(sections[si + 1][5])) * 0.5,
			(float(sections[si][1]) + float(sections[si][2])) * 0.5
		)
		for k in 6:
			var nk := (k + 1) % 6
			_emit_outward_quad(st,
				r0[k] as Vector3, c0[k] as Color,
				r1[k] as Vector3, c1[k] as Color,
				r1[nk] as Vector3, c1[nk] as Color,
				r0[nk] as Vector3, c0[nk] as Color, mid)

	var root_c := Vector3(0.0, 0.0, 0.0)
	var tip_i := rings.size() - 1
	var tip_c := Vector3(side_sgn * 0.63, -0.082, 0.135)
	for k in 6:
		var nk := (k + 1) % 6
		_emit_outward_tri(st, root_c, COL_TURTLE_SKIN,
			rings[0][nk] as Vector3, cols[0][nk] as Color,
			rings[0][k] as Vector3, cols[0][k] as Color,
			Vector3(side_sgn * 0.20, -0.02, 0.0))
		_emit_outward_tri(st, tip_c, COL_TURTLE_EDGE,
			rings[tip_i][k] as Vector3, cols[tip_i][k] as Color,
			rings[tip_i][nk] as Vector3, cols[tip_i][nk] as Color,
			Vector3(side_sgn * 0.45, -0.06, 0.11))

	# Two raised scaly flipper leading-edge plates (16 tris).
	for pi in 2:
		var u := 0.25 + float(pi) * 0.34
		var p0 := Vector3(side_sgn * (u * 0.55), -0.015 - u * 0.06, -0.12 + u * 0.06)
		var p1 := p0 + Vector3(side_sgn * 0.07, -0.012, 0.025)
		var p2 := p0 + Vector3(side_sgn * 0.13, -0.020, 0.055)
		_append_feather_blade(st, p0, p1, p2, Vector3(0.0, 0.0, 1.0), 0.024, 0.012,
			COL_TURTLE_EDGE, COL_TURTLE_SCALE, COL_TURTLE_EDGE)

	st.generate_normals()
	return st.commit()


# ------------------------------------------------------------------------------
# Species 3 Mesh Builders: Scurrying Coral Sand-Crab (>= 280 tris total)
# ------------------------------------------------------------------------------

static func _build_crab_body_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# 1. Mottled vermilion-coral trapezoid-oval carapace (4 rings x 12 segs + caps = 96 tris).
	var segs := 12
	var shell_rows: Array[Array] = [
		[0.105, 0.082, 0.056, COL_CRAB_BELLY, COL_CRAB_BELLY],
		[0.162, 0.122, 0.088, COL_CRAB_VERMILION, COL_CRAB_CORAL],
		[0.142, 0.106, 0.130, COL_CRAB_CORAL, COL_CRAB_MOTTLE],
		[0.072, 0.054, 0.150, COL_CRAB_MOTTLE, COL_CRAB_CORAL],
	]
	var rings: Array[Array] = []
	var rcols: Array[Array] = []
	for ri in shell_rows.size():
		var row: Array = shell_rows[ri]
		var rx: float = float(row[0])
		var rz: float = float(row[1])
		var ry: float = float(row[2])
		var ca: Color = row[3] as Color
		var cb: Color = row[4] as Color
		var pts: Array[Vector3] = []
		var cls: Array[Color] = []
		for k in segs:
			var ang := float(k) / float(segs) * TAU
			var sz := sin(ang)
			# Broader across front brow (-Z), slightly narrower rear (+Z).
			var brow := 1.06 if sz < 0.0 else 0.88
			var scallop := 1.0 + (0.045 if (ri == 1 and k % 2 == 0) else 0.0)
			pts.append(Vector3(cos(ang) * rx * brow * scallop, ry, sz * rz * scallop))
			cls.append(ca if ((k + ri) % 2 == 0) else cb)
		rings.append(pts)
		rcols.append(cls)

	var body_c := Vector3(0.0, 0.095, 0.0)
	for ri in range(rings.size() - 1):
		for k in segs:
			var nk := (k + 1) % segs
			_emit_outward_quad(st,
				rings[ri][k] as Vector3, rcols[ri][k] as Color,
				rings[ri + 1][k] as Vector3, rcols[ri + 1][k] as Color,
				rings[ri + 1][nk] as Vector3, rcols[ri + 1][nk] as Color,
				rings[ri][nk] as Vector3, rcols[ri][nk] as Color, body_c)

	var bot_c := Vector3(0.0, 0.048, 0.0)
	var top_i := rings.size() - 1
	var top_c := Vector3(0.0, 0.155, -0.01)
	for k in segs:
		var nk := (k + 1) % segs
		_emit_outward_tri(st, bot_c, COL_CRAB_BELLY,
			rings[0][nk] as Vector3, rcols[0][nk] as Color,
			rings[0][k] as Vector3, rcols[0][k] as Color, body_c)
		_emit_outward_tri(st, top_c, COL_CRAB_MOTTLE,
			rings[top_i][k] as Vector3, rcols[top_i][k] as Color,
			rings[top_i][nk] as Vector3, rcols[top_i][nk] as Color, body_c)

	# 2. Twin raised black-tipped eye-stalks (2 x 36 = 72 tris).
	for sgn: float in [-1.0, 1.0]:
		var stalk_st: Array[Array] = [
			[Vector3(sgn * 0.052, 0.125, -0.096), 0.012, 0.012, 0.012, COL_CRAB_CORAL, COL_CRAB_MOTTLE, COL_CRAB_CORAL],
			[Vector3(sgn * 0.062, 0.172, -0.108), 0.010, 0.010, 0.010, COL_CRAB_MOTTLE, COL_CRAB_CLAW_TIP, COL_CRAB_MOTTLE],
			[Vector3(sgn * 0.068, 0.210, -0.114), 0.012, 0.012, 0.012, COL_EYE_DARK, COL_EYE_DARK, COL_EYE_DARK],
		]
		_append_curved_tube(st, stalk_st, 6, false, true)
		_append_eye_dome(st, Vector3(sgn * 0.069, 0.214, -0.118),
			Vector3(sgn * 0.22, 0.35, -0.91).normalized(), 0.016, COL_EYE_DARK, COL_EYE_DARK)

	# 3. 6 splayed jointed walking legs touching sand at y = 0.00 (6 x 28 = 168 tris).
	var leg_z_offs: Array[float] = [-0.036, 0.022, 0.076]
	for sgn: float in [-1.0, 1.0]:
		for li in 3:
			var lz: float = leg_z_offs[li]
			var sweep_z := (float(li) - 1.0) * 0.075
			var reach := 0.245 if li == 1 else 0.225
			var leg_st: Array[Array] = [
				[Vector3(sgn * 0.125, 0.076, lz), 0.018, 0.016, 0.016, COL_CRAB_VERMILION, COL_CRAB_LEG, COL_CRAB_BELLY],
				[Vector3(sgn * (0.125 + reach * 0.42), 0.132, lz + sweep_z * 0.45), 0.015, 0.015, 0.014, COL_CRAB_CORAL, COL_CRAB_MOTTLE, COL_CRAB_LEG],
				[Vector3(sgn * (0.125 + reach * 0.80), 0.066, lz + sweep_z * 0.80), 0.011, 0.011, 0.010, COL_CRAB_LEG, COL_CRAB_MOTTLE, COL_CRAB_BELLY],
				[Vector3(sgn * (0.125 + reach), 0.002, lz + sweep_z), 0.005, 0.005, 0.005, COL_CRAB_CLAW_TIP, COL_CRAB_CLAW_TIP, COL_CRAB_CLAW_TIP],
			]
			_append_curved_tube(st, leg_st, 4, false, true)

	st.generate_normals()
	return st.commit()


static func _build_crab_claw_mesh(side_sgn: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Bent arm + bulbous coral palm + upper & lower curved snapping pincer fingers (70 tris).
	var arm_st: Array[Array] = [
		[Vector3(0.0, 0.0, 0.0), 0.018, 0.018, 0.018, COL_CRAB_VERMILION, COL_CRAB_LEG, COL_CRAB_BELLY],
		[Vector3(side_sgn * 0.062, 0.018, -0.048), 0.022, 0.020, 0.018, COL_CRAB_CORAL, COL_CRAB_MOTTLE, COL_CRAB_BELLY],
		[Vector3(side_sgn * 0.078, 0.046, -0.098), 0.026, 0.026, 0.024, COL_CRAB_CORAL, COL_CRAB_CORAL, COL_CRAB_BELLY],
	]
	_append_curved_tube(st, arm_st, 4, false, true)

	# Bulbous chela palm.
	var palm_st: Array[Array] = [
		[Vector3(side_sgn * 0.078, 0.046, -0.098), 0.028, 0.030, 0.026, COL_CRAB_VERMILION, COL_CRAB_CORAL, COL_CRAB_BELLY],
		[Vector3(side_sgn * 0.066, 0.068, -0.150), 0.036, 0.040, 0.034, COL_CRAB_CORAL, COL_CRAB_MOTTLE, COL_CRAB_BELLY],
		[Vector3(side_sgn * 0.042, 0.072, -0.188), 0.028, 0.030, 0.026, COL_CRAB_MOTTLE, COL_CRAB_CORAL, COL_CRAB_CLAW_TIP],
	]
	_append_curved_tube(st, palm_st, 6, false, true)

	# Upper snapping pincer finger (dactyl) + lower fixed finger (propodus).
	var upper_f: Array[Array] = [
		[Vector3(side_sgn * 0.040, 0.090, -0.184), 0.015, 0.016, 0.014, COL_CRAB_CORAL, COL_CRAB_CLAW_TIP, COL_CRAB_CLAW_TIP],
		[Vector3(side_sgn * 0.014, 0.106, -0.228), 0.011, 0.012, 0.010, COL_CRAB_CLAW_TIP, COL_CRAB_CLAW_TIP, COL_CRAB_CLAW_TIP],
		[Vector3(-side_sgn * 0.012, 0.094, -0.252), 0.005, 0.006, 0.005, COL_CRAB_CLAW_TIP, COL_CRAB_CLAW_TIP, COL_CRAB_CLAW_TIP],
	]
	_append_curved_tube(st, upper_f, 4, false, true)

	var lower_f: Array[Array] = [
		[Vector3(side_sgn * 0.040, 0.056, -0.184), 0.014, 0.014, 0.014, COL_CRAB_CLAW_TIP, COL_CRAB_MOTTLE, COL_CRAB_BELLY],
		[Vector3(side_sgn * 0.014, 0.052, -0.224), 0.010, 0.010, 0.010, COL_CRAB_CLAW_TIP, COL_CRAB_CLAW_TIP, COL_CRAB_CLAW_TIP],
		[Vector3(-side_sgn * 0.010, 0.066, -0.246), 0.005, 0.005, 0.005, COL_CRAB_CLAW_TIP, COL_CRAB_CLAW_TIP, COL_CRAB_CLAW_TIP],
	]
	_append_curved_tube(st, lower_f, 4, false, true)

	st.generate_normals()
	return st.commit()


# ------------------------------------------------------------------------------
# Species 4 Mesh Builders: Tropical Butterflies (>= 48 tris) & Meadow Fireflies
# ------------------------------------------------------------------------------

static func _build_butterfly_body_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Head, plump thorax & tapered abdomen (5 stations x 4 segs + caps = 36 tris + 8 antennae = 44 tris).
	var body_st: Array[Array] = [
		[Vector3(0.0, 0.004, -0.054), 0.010, 0.010, 0.009, COL_BUTTERFLY_BODY, COL_BUTTERFLY_BODY, COL_BUTTERFLY_BODY],
		[Vector3(0.0, 0.008, -0.022), 0.014, 0.015, 0.012, COL_BUTTERFLY_BODY, COL_BUTTERFLY_BODY, COL_BUTTERFLY_BODY],
		[Vector3(0.0, 0.004, 0.014), 0.012, 0.012, 0.010, COL_BUTTERFLY_BODY, COL_BUTTERFLY_BODY, COL_BUTTERFLY_BODY],
		[Vector3(0.0, -0.002, 0.054), 0.009, 0.009, 0.008, COL_BUTTERFLY_BODY, COL_BUTTERFLY_BODY, COL_BUTTERFLY_BODY],
		[Vector3(0.0, -0.005, 0.082), 0.004, 0.004, 0.004, COL_BUTTERFLY_BODY, COL_BUTTERFLY_BODY, COL_BUTTERFLY_BODY],
	]
	_append_curved_tube(st, body_st, 4, true, true)

	for sgn: float in [-1.0, 1.0]:
		var a0 := Vector3(sgn * 0.006, 0.010, -0.052)
		var a1 := Vector3(sgn * 0.026, 0.024, -0.088)
		var a2 := Vector3(sgn * 0.042, 0.030, -0.106)
		_append_feather_blade(st, a0, a1, a2, Vector3.UP, 0.003, 0.002,
			COL_BUTTERFLY_BODY, COL_BUTTERFLY_BODY, COL_BUTTERFLY_BODY)

	st.generate_normals()
	return st.commit()


static func _build_butterfly_wing_mesh(side_sgn: float, c_inner: Color, c_mid: Color,
		c_rim: Color, c_dot: Color) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Sculpted cambered tropical forewing (top + bottom surfaces = 16 tris).
	var f_root := Vector3(0.0, 0.0, -0.018)
	var f_lead := Vector3(side_sgn * 0.145, 0.022, -0.115)
	var f_apex := Vector3(side_sgn * 0.195, 0.018, -0.048)
	var f_mid_out := Vector3(side_sgn * 0.155, 0.008, 0.022)
	var f_inner := Vector3(side_sgn * 0.068, 0.005, 0.015)
	var f_center_t := Vector3(side_sgn * 0.092, 0.019, -0.036)
	var f_center_b := Vector3(side_sgn * 0.092, 0.009, -0.036)
	var f_ref_t := f_center_b - Vector3(0.0, 0.06, 0.0)
	var f_ref_b := f_center_t + Vector3(0.0, 0.06, 0.0)

	var f_loop: Array[Vector3] = [f_root, f_lead, f_apex, f_mid_out, f_inner]
	var f_cols: Array[Color] = [c_inner, c_rim, c_dot, c_rim, c_mid]
	for k in f_loop.size():
		var nk := (k + 1) % f_loop.size()
		_emit_outward_tri(st, f_center_t, c_inner, f_loop[k], f_cols[k], f_loop[nk], f_cols[nk], f_ref_t)
		_emit_outward_tri(st, f_center_b, c_mid, f_loop[nk], f_cols[nk], f_loop[k], f_cols[k], f_ref_b)

	# Sculpted swallowtail hindwing (top + bottom surfaces = 12 tris).
	var h_root := Vector3(0.0, -0.002, 0.012)
	var h_out := Vector3(side_sgn * 0.135, 0.006, 0.036)
	var h_tail := Vector3(side_sgn * 0.105, -0.006, 0.132)
	var h_inner := Vector3(side_sgn * 0.028, -0.004, 0.095)
	var h_center_t := Vector3(side_sgn * 0.066, 0.008, 0.062)
	var h_center_b := Vector3(side_sgn * 0.066, -0.002, 0.062)
	var h_ref_t := h_center_b - Vector3(0.0, 0.05, 0.0)
	var h_ref_b := h_center_t + Vector3(0.0, 0.05, 0.0)

	var h_loop: Array[Vector3] = [h_root, h_out, h_tail, h_inner]
	var h_cols: Array[Color] = [c_inner, c_rim, c_dot, c_rim]
	for k in h_loop.size():
		var nk := (k + 1) % h_loop.size()
		_emit_outward_tri(st, h_center_t, c_mid, h_loop[k], h_cols[k], h_loop[nk], h_cols[nk], h_ref_t)
		_emit_outward_tri(st, h_center_b, c_mid, h_loop[nk], h_cols[nk], h_loop[k], h_cols[k], h_ref_b)

	st.generate_normals()
	return st.commit()


static func _build_firefly_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Sculpted glowing golden elongated diamond firefly (24 tris).
	var ff_st: Array[Array] = [
		[Vector3(0.0, 0.0, -0.072), 0.010, 0.010, 0.010, COL_FIREFLY_GLOW, COL_FIREFLY_GLOW, COL_FIREFLY_GLOW],
		[Vector3(0.0, 0.0, -0.012), 0.052, 0.052, 0.052, COL_FIREFLY_CORE, COL_FIREFLY_GLOW, COL_FIREFLY_GLOW],
		[Vector3(0.0, 0.0, 0.048), 0.042, 0.042, 0.042, COL_FIREFLY_CORE, COL_FIREFLY_CORE, COL_FIREFLY_GLOW],
		[Vector3(0.0, 0.0, 0.095), 0.008, 0.008, 0.008, COL_FIREFLY_GLOW, COL_FIREFLY_GLOW, COL_FIREFLY_GLOW],
	]
	_append_curved_tube(st, ff_st, 4, true, true)

	st.generate_normals()
	return st.commit()


# ==============================================================================
# Low-Level Flat-Faceted SurfaceTool Sculpting Helpers
# ==============================================================================

## Loft a closed curved tube through `[center, rx, ry_top, ry_bot, c_top, c_side, c_bot]` stations.
static func _append_curved_tube(st: SurfaceTool, stations: Array[Array], segs: int,
		cap_start: bool, cap_end: bool) -> void:
	if stations.size() < 2:
		return
	var rings: Array[Array] = []
	var ring_cols: Array[Array] = []
	var centers: Array[Vector3] = []

	for si in stations.size():
		var c: Vector3 = stations[si][0] as Vector3
		centers.append(c)
		var prev_c: Vector3 = stations[maxi(0, si - 1)][0] as Vector3
		var next_c: Vector3 = stations[mini(stations.size() - 1, si + 1)][0] as Vector3
		var tang := next_c - prev_c
		tang = tang.normalized() if tang.length_squared() > 1e-8 else Vector3.FORWARD

		var ref_up := Vector3.UP
		if absf(tang.dot(ref_up)) > 0.94:
			ref_up = Vector3.FORWARD
		var right := tang.cross(ref_up).normalized()
		var up := right.cross(tang).normalized()

		var rx: float = float(stations[si][1])
		var ry_t: float = float(stations[si][2])
		var ry_b: float = float(stations[si][3])
		var c_top: Color = stations[si][4] as Color
		var c_side: Color = stations[si][5] as Color
		var c_bot: Color = stations[si][6] as Color

		var pts: Array[Vector3] = []
		var cols: Array[Color] = []
		for k in segs:
			var a := float(k) / float(segs) * TAU
			var ca := cos(a)
			var sa := sin(a)
			var offset := right * (ca * rx) + up * (sa * (ry_t if sa >= 0.0 else ry_b))
			pts.append(c + offset)
			var col := c_side.lerp(c_top, sa) if sa >= 0.0 else c_side.lerp(c_bot, -sa)
			cols.append(col)
		rings.append(pts)
		ring_cols.append(cols)

	for si in range(stations.size() - 1):
		var mid := (centers[si] + centers[si + 1]) * 0.5
		for k in segs:
			var nk := (k + 1) % segs
			_emit_outward_quad(st,
				rings[si][k] as Vector3, ring_cols[si][k] as Color,
				rings[si + 1][k] as Vector3, ring_cols[si + 1][k] as Color,
				rings[si + 1][nk] as Vector3, ring_cols[si + 1][nk] as Color,
				rings[si][nk] as Vector3, ring_cols[si][nk] as Color, mid)

	if cap_start:
		var dir0 := (centers[0] - centers[1]).normalized()
		var tip0 := centers[0] + dir0 * maxf(float(stations[0][1]) * 0.45, 0.005)
		var col0: Color = stations[0][4] as Color
		for k in segs:
			var nk := (k + 1) % segs
			_emit_outward_tri(st, tip0, col0,
				rings[0][k] as Vector3, ring_cols[0][k] as Color,
				rings[0][nk] as Vector3, ring_cols[0][nk] as Color, centers[1])

	if cap_end:
		var li := stations.size() - 1
		var dir_e := (centers[li] - centers[li - 1]).normalized()
		var tip_e := centers[li] + dir_e * maxf(float(stations[li][1]) * 0.45, 0.005)
		var col_e: Color = stations[li][4] as Color
		for k in segs:
			var nk := (k + 1) % segs
			_emit_outward_tri(st, tip_e, col_e,
				rings[li][nk] as Vector3, ring_cols[li][nk] as Color,
				rings[li][k] as Vector3, ring_cols[li][k] as Color, centers[li - 1])


## Sculpted 8-triangle solid faceted feather/crest/scale blade.
static func _append_feather_blade(st: SurfaceTool, p_base: Vector3, p_mid: Vector3,
		p_tip: Vector3, width_hint: Vector3, half_w: float, thick: float,
		c_base: Color, c_mid: Color, c_tip: Color) -> void:
	var axis := (p_tip - p_base).normalized()
	var w_dir := width_hint - axis * width_hint.dot(axis)
	if w_dir.length_squared() < 1e-6:
		w_dir = Vector3.RIGHT
	w_dir = w_dir.normalized()
	var n_dir := axis.cross(w_dir).normalized()

	var ml := p_mid - w_dir * half_w
	var mr := p_mid + w_dir * half_w
	var mt := p_mid + n_dir * thick
	var mb := p_mid - n_dir * thick
	var mid_ring: Array[Vector3] = [ml, mt, mr, mb]
	var mid_cols: Array[Color] = [c_mid, c_mid, c_mid, c_base]

	for k in 4:
		var nk := (k + 1) % 4
		_emit_outward_tri(st, p_base, c_base, mid_ring[k], mid_cols[k], mid_ring[nk], mid_cols[nk], p_mid)
		_emit_outward_tri(st, p_tip, c_tip, mid_ring[nk], mid_cols[nk], mid_ring[k], mid_cols[k], p_mid)


## Sculpted 12-triangle faceted expressive eye dome with outer ring & glossy dark pupil.
static func _append_eye_dome(st: SurfaceTool, center: Vector3, out_dir: Vector3,
		radius: float, ring_col: Color, pupil_col: Color) -> void:
	var ref_u := Vector3.UP if absf(out_dir.dot(Vector3.UP)) < 0.92 else Vector3.FORWARD
	var right := out_dir.cross(ref_u).normalized()
	var up := right.cross(out_dir).normalized()
	var segs := 6
	var outer: Array[Vector3] = []
	var inner: Array[Vector3] = []
	for k in segs:
		var a := float(k) / float(segs) * TAU
		var radial := right * cos(a) + up * sin(a)
		outer.append(center + radial * radius)
		inner.append(center + radial * (radius * 0.58) + out_dir * (radius * 0.45))
	var apex := center + out_dir * (radius * 0.72)
	var ref_in := center - out_dir * (radius * 2.0)
	for k in segs:
		var nk := (k + 1) % segs
		_emit_outward_tri(st, outer[k], ring_col, inner[k], pupil_col, outer[nk], ring_col, ref_in)
		_emit_outward_tri(st, apex, pupil_col, inner[k], pupil_col, inner[nk], pupil_col, ref_in)


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


static func _emit_outward_tri(st: SurfaceTool, a: Vector3, ca: Color,
		b: Vector3, cb: Color, c: Vector3, cc: Color, ref_center: Vector3) -> void:
	var n := (c - a).cross(b - a)
	if n.length_squared() < 1e-12:
		return
	var centroid := (a + b + c) / 3.0
	if n.dot(centroid - ref_center) < 0.0:
		_emit_flat_tri(st, a, ca, c, cc, b, cb)
	else:
		_emit_flat_tri(st, a, ca, b, cb, c, cc)


static func _emit_outward_quad(st: SurfaceTool, a: Vector3, ca: Color,
		b: Vector3, cb: Color, c: Vector3, cc: Color, d: Vector3, cd: Color,
		ref_center: Vector3) -> void:
	_emit_outward_tri(st, a, ca, b, cb, c, cc, ref_center)
	_emit_outward_tri(st, a, ca, c, cc, d, cd, ref_center)
