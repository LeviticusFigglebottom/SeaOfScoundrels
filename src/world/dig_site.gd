class_name DigSite
extends Node3D
## Buried treasure dig site on an island beach or clearing.
##
## Visuals pair `dig_mound.glb` with a rising buried `chest_treasure.glb` preview
## and sand-clod puff particles. Players may dig either via a Shovel tool calling
## `dig(world_pos, digger)` or directly through the attached `Interactable`.
## Three digs unearth a real `Carryable` chest via `TreasureCatalog`.

signal dug(dig_count: int, remaining: int, digger: Node)
signal unearthed(chest: Carryable)

const DIG_MOUND_SCENE: PackedScene = preload("res://assets/generated/props/dig_mound.glb")
const CHEST_PREVIEW_SCENE: PackedScene = preload("res://assets/generated/props/chest_treasure.glb")

const DIG_RADIUS := 2.4
const REQUIRED_DIGS := 3
const GROUP := &"dig_sites"

## Treasure catalogue ID spawned on unearthing (configurable by voyages).
@export var treasure_id: StringName = &"wayfarer_chest"

var dig_count: int = 0
var is_unearthed: bool = false
var spawned_chest: Carryable = null
var interactable: Interactable = null

static var _active_dig_sites: int = 0
static var _clod_mesh: ArrayMesh = null
static var _clod_mat: StandardMaterial3D = null
static var _sparkle_mesh: ArrayMesh = null
static var _sparkle_mat: StandardMaterial3D = null

var _mound_node: Node3D = null
var _chest_preview: Node3D = null
var _dirt_particles: CPUParticles3D = null
var _gold_particles: CPUParticles3D = null


## Release statically cached sculpted earth clod & gold sparkle particle assets cleanly.
static func clear_shared_cache() -> void:
	_clod_mesh = null
	_clod_mat = null
	_sparkle_mesh = null
	_sparkle_mat = null


func _enter_tree() -> void:
	add_to_group(GROUP)
	_active_dig_sites += 1


func _exit_tree() -> void:
	for p: CPUParticles3D in [_dirt_particles, _gold_particles]:
		if p != null and is_instance_valid(p):
			p.emitting = false
			p.mesh = null
			p.material_override = null
	_dirt_particles = null
	_gold_particles = null
	_active_dig_sites = maxi(0, _active_dig_sites - 1)
	if _active_dig_sites == 0:
		clear_shared_cache()


func _ready() -> void:
	_build_visuals()
	_build_particles()
	_build_interactable()


func _build_visuals() -> void:
	if _mound_node == null:
		_mound_node = DIG_MOUND_SCENE.instantiate() as Node3D
		_mound_node.name = "DigMound"
		add_child(_mound_node)

	if _chest_preview == null:
		_chest_preview = CHEST_PREVIEW_SCENE.instantiate() as Node3D
		_chest_preview.name = "BuriedChestPreview"
		_chest_preview.position = Vector3(0.0, -0.44, 0.0)
		_chest_preview.rotation = Vector3(0.08, 0.35, -0.06)
		_chest_preview.visible = false
		add_child(_chest_preview)


func _build_particles() -> void:
	if _dirt_particles != null:
		return
	_ensure_particle_assets()

	var p := CPUParticles3D.new()
	p.name = "DirtPuffParticles"
	p.emitting = false
	p.one_shot = true
	p.amount = 18
	p.lifetime = 0.65
	p.explosiveness = 0.85
	p.position = Vector3(0.0, 0.22, 0.0)
	p.direction = Vector3(0.0, 1.0, 0.0)
	p.spread = 52.0
	p.initial_velocity_min = 2.0
	p.initial_velocity_max = 4.6
	p.gravity = Vector3(0.0, -11.5, 0.0)
	p.scale_amount_min = 0.08
	p.scale_amount_max = 0.19
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.mesh = _clod_mesh
	p.material_override = _clod_mat
	add_child(p)
	_dirt_particles = p

	var g := CPUParticles3D.new()
	g.name = "TreasureGlintParticles"
	g.emitting = false
	g.one_shot = true
	g.amount = 16
	g.lifetime = 0.95
	g.explosiveness = 0.88
	g.position = Vector3(0.0, 0.38, 0.0)
	g.direction = Vector3(0.0, 1.0, 0.0)
	g.spread = 65.0
	g.initial_velocity_min = 1.6
	g.initial_velocity_max = 3.8
	g.gravity = Vector3(0.0, -3.5, 0.0)
	g.scale_amount_min = 0.05
	g.scale_amount_max = 0.12
	g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	g.mesh = _sparkle_mesh
	g.material_override = _sparkle_mat
	add_child(g)
	_gold_particles = g


static func _ensure_particle_assets() -> void:
	if _clod_mat == null:
		_clod_mat = StandardMaterial3D.new()
		_clod_mat.albedo_color = Color.WHITE
		_clod_mat.vertex_color_use_as_albedo = true
		_clod_mat.vertex_color_is_srgb = true
		_clod_mat.roughness = 0.92
		_clod_mat.metallic = 0.02

	if _sparkle_mat == null:
		_sparkle_mat = StandardMaterial3D.new()
		_sparkle_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_sparkle_mat.albedo_color = Color.WHITE
		_sparkle_mat.vertex_color_use_as_albedo = true
		_sparkle_mat.vertex_color_is_srgb = true
		_sparkle_mat.emission_enabled = true
		_sparkle_mat.emission = Color(1.0, 0.88, 0.35)
		_sparkle_mat.emission_energy_multiplier = 1.2

	if _clod_mesh == null:
		_clod_mesh = _build_earth_clod_mesh()
	if _sparkle_mesh == null:
		_sparkle_mesh = _build_gold_sparkle_mesh()


static func _build_earth_clod_mesh() -> ArrayMesh:
	## Sculpted irregular beveled multi-faceted earth & beach sand clod (zero BoxMesh).
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var col_sand := Color(0.86, 0.74, 0.46)
	var col_mid := Color(0.68, 0.54, 0.31)
	var col_loam := Color(0.42, 0.31, 0.18)

	var top_p := Vector3(0.05, 0.34, -0.04)
	var bot_p := Vector3(-0.04, -0.30, 0.05)
	var segs := 8
	var upper_ring: Array[Vector3] = []
	var lower_ring: Array[Vector3] = []
	for k in segs:
		var a := float(k) / float(segs) * TAU
		var w_u := 0.36 + 0.08 * sin(a * 3.0 + 0.5)
		var w_l := 0.44 + 0.09 * cos(a * 2.0 - 0.8)
		upper_ring.append(Vector3(cos(a) * w_u, 0.14 + 0.04 * sin(a * 2.0), sin(a) * w_u * 0.92))
		lower_ring.append(Vector3(cos(a + 0.22) * w_l, -0.10 + 0.04 * cos(a * 3.0), sin(a + 0.22) * w_l * 0.94))

	for k in segs:
		var nk := (k + 1) % segs
		_emit_outward_tri(st, top_p, col_sand, upper_ring[k], col_sand, upper_ring[nk], col_mid, Vector3.ZERO)
		_emit_outward_tri(st, upper_ring[k], col_sand, lower_ring[k], col_mid, lower_ring[nk], col_loam, Vector3.ZERO)
		_emit_outward_tri(st, upper_ring[k], col_sand, lower_ring[nk], col_loam, upper_ring[nk], col_mid, Vector3.ZERO)
		_emit_outward_tri(st, bot_p, col_loam, lower_ring[nk], col_loam, lower_ring[k], col_mid, Vector3.ZERO)

	st.generate_normals()
	return st.commit()


static func _build_gold_sparkle_mesh() -> ArrayMesh:
	## Sculpted 4-point faceted diamond gold sparkle gem glinting over unearthed treasure.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var col_core := Color(1.00, 0.98, 0.84)
	var col_gold := Color(1.00, 0.84, 0.26)
	var col_tip := Color(0.96, 0.66, 0.14)

	var top_p := Vector3(0.0, 0.42, 0.0)
	var bot_p := Vector3(0.0, -0.42, 0.0)
	var ring: Array[Vector3] = []
	var ring_cols: Array[Color] = []
	for k in 8:
		var a := float(k) / 8.0 * TAU
		var is_point := (k % 2 == 0)
		var r := 0.34 if is_point else 0.13
		ring.append(Vector3(cos(a) * r, 0.0, sin(a) * r))
		ring_cols.append(col_tip if is_point else col_gold)

	for k in 8:
		var nk := (k + 1) % 8
		_emit_outward_tri(st, top_p, col_core, ring[k], ring_cols[k], ring[nk], ring_cols[nk], Vector3.ZERO)
		_emit_outward_tri(st, bot_p, col_core, ring[nk], ring_cols[nk], ring[k], ring_cols[k], Vector3.ZERO)

	st.generate_normals()
	return st.commit()


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


func _build_interactable() -> void:
	if interactable != null:
		return
	interactable = Interactable.create("Dig for treasure", 1.05)
	interactable.name = "DigInteractable"
	interactable.position = Vector3(0.0, 0.35, 0.0)
	interactable.reach = 2.8
	interactable.target = self
	interactable.interacted.connect(_on_interacted)
	add_child(interactable)


func _on_interacted(pawn: Node) -> void:
	var pos := global_position
	if pawn is Node3D:
		var p_pos := (pawn as Node3D).global_position
		if Vector2(p_pos.x - global_position.x, p_pos.z - global_position.z).length() <= DIG_RADIUS:
			pos = p_pos
	dig(pos, pawn)


## Perform a dig strike at `world_pos` (host-authoritative).
## Returns `{hit, digs, remaining, unearthed, chest, reason}`.
func dig(world_pos: Vector3, digger: Node = null) -> Dictionary:
	if not Net.is_host():
		return {
			"hit": false,
			"reason": "not_host",
			"digs": dig_count,
			"remaining": maxi(0, REQUIRED_DIGS - dig_count),
			"unearthed": is_unearthed,
			"chest": spawned_chest,
		}
	if is_unearthed:
		return {
			"hit": false,
			"reason": "already_unearthed",
			"digs": dig_count,
			"remaining": 0,
			"unearthed": true,
			"chest": spawned_chest,
		}

	var dist_xz := Vector2(world_pos.x - global_position.x, world_pos.z - global_position.z).length()
	if dist_xz > DIG_RADIUS:
		return {
			"hit": false,
			"reason": "out_of_range",
			"distance": dist_xz,
			"digs": dig_count,
			"remaining": maxi(0, REQUIRED_DIGS - dig_count),
			"unearthed": false,
			"chest": null,
		}

	dig_count += 1
	var remaining := maxi(0, REQUIRED_DIGS - dig_count)
	Audio.play_sfx(&"dig_sand", global_position)
	_trigger_dirt_puff()
	_update_mound_progress()

	if dig_count < REQUIRED_DIGS:
		if dig_count == REQUIRED_DIGS - 1:
			Audio.play_sfx(&"chest_thump", global_position, -6.0)
		if interactable != null:
			interactable.prompt = "Unearth treasure (1 left)" if remaining == 1 else "Dig for treasure (%d left)" % remaining
		dug.emit(dig_count, remaining, digger)
		return {
			"hit": true,
			"reason": "",
			"digs": dig_count,
			"remaining": remaining,
			"unearthed": false,
			"chest": null,
		}

	# Final strike: unearth the physical Carryable chest.
	is_unearthed = true
	if _chest_preview != null:
		_chest_preview.visible = false
	if interactable != null:
		interactable.enabled = false
		interactable.prompt = "Dug up"

	var resolved_id := _resolve_treasure_id(treasure_id)
	var spawn_pos := global_position + Vector3(0.0, 0.42, 0.0)
	var chest := TreasureCatalog.create_treasure_carryable(resolved_id, Vector3.ZERO)
	var host_parent := get_parent() if get_parent() != null else self
	host_parent.add_child(chest)
	chest.global_position = spawn_pos
	chest.linear_velocity = Vector3(0.0, 2.0, 0.0)
	spawned_chest = chest

	Audio.play_sfx(&"chest_thump", global_position)
	Audio.play_stinger(&"treasure_found")
	if _gold_particles != null:
		_gold_particles.restart()
		_gold_particles.emitting = true
	dug.emit(dig_count, 0, digger)
	unearthed.emit(chest)

	return {
		"hit": true,
		"reason": "",
		"digs": dig_count,
		"remaining": 0,
		"unearthed": true,
		"chest": chest,
	}


func _trigger_dirt_puff() -> void:
	if _dirt_particles != null:
		_dirt_particles.restart()
		_dirt_particles.emitting = true


func _update_mound_progress() -> void:
	if _mound_node != null:
		match dig_count:
			1:
				_mound_node.scale = Vector3(1.04, 0.80, 1.04)
			2:
				_mound_node.scale = Vector3(1.10, 0.54, 1.10)
			_:
				_mound_node.scale = Vector3(1.16, 0.24, 1.16)
				_mound_node.position.y = -0.06
	if _chest_preview != null and not is_unearthed:
		_chest_preview.visible = true
		if dig_count == 1:
			_chest_preview.position.y = -0.26
		elif dig_count >= 2:
			_chest_preview.position.y = -0.07


static func _resolve_treasure_id(tid: StringName) -> StringName:
	if TreasureCatalog.has_treasure(tid):
		return tid
	if tid == &"seafarer_chest":
		return &"wayfarer_chest"
	return &"wayfarer_chest"
