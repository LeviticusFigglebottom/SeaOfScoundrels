class_name FishingLine
extends Node3D
## Low-stakes sailing downtime: cast a sculpted cork-and-crimson bobber into the real `Sea`
## with a bending bamboo-and-brass fishing rod, dynamic 14-segment catenary line, churning
## hooked-fish splashes, and a celebratory species-tinted leaping fish catch arc.

signal cast_started(bobber_pos: Vector3)
signal fish_hooked(species: Dictionary)
signal fish_caught(species: Dictionary)
signal line_snapped(species: Dictionary)

enum State { IDLE, WAITING, HOOKED }

const SPECIES: Array[Dictionary] = [
	{"id": &"azure_snapper", "name": "Azure Snapper", "gold": 45, "heal": 30.0, "fight": 0.45, "storm_only": false, "night_only": false},
	{"id": &"gilded_mackerel", "name": "Gilded Mackerel", "gold": 65, "heal": 35.0, "fight": 0.55, "storm_only": false, "night_only": false},
	{"id": &"reef_grouper", "name": "Reef Grouper", "gold": 95, "heal": 45.0, "fight": 0.65, "storm_only": false, "night_only": false},
	{"id": &"lantern_fin", "name": "Moonlit Lantern-Fin", "gold": 150, "heal": 55.0, "fight": 0.72, "storm_only": false, "night_only": true},
	{"id": &"storm_eel", "name": "Tempest Ribbon-Eel", "gold": 210, "heal": 65.0, "fight": 0.85, "storm_only": true, "night_only": false},
]

const LINE_SEGMENTS := 14
const SPLASH_INTERVAL := 0.28
const LEAP_DURATION := 0.85
const BOBBER_SWIVEL_Y := 0.252
const ROD_BUTT_LEN := 0.95
const ROD_MID_LEN := 0.85
const ROD_TIP_LEN := 0.75
const RIPPLE_WAIT_PERIOD := 1.6
const RIPPLE_FIGHT_SPEED_MULT := 2.6
const RIPPLE_WAIT_SCALE_MIN := 0.45
const RIPPLE_WAIT_SCALE_MAX := 1.35
const RIPPLE_FIGHT_SCALE_MIN := 0.55
const RIPPLE_FIGHT_SCALE_MAX := 2.15
const RIPPLE_WATER_OFFSET := 0.035

# Painterly pirate palette for bobber, bamboo rod, catenary line, and leaping fish.
const COL_CORK_BASE := Color(0.88, 0.78, 0.56)
const COL_CORK_SHADE := Color(0.75, 0.64, 0.43)
const COL_CRIMSON := Color(0.86, 0.18, 0.14)
const COL_CRIMSON_HI := Color(0.93, 0.25, 0.19)
const COL_CRIMSON_SHADE := Color(0.68, 0.13, 0.10)
const COL_BRASS := Color(0.85, 0.65, 0.24)
const COL_BRASS_DARK := Color(0.55, 0.39, 0.14)
const COL_IVORY := Color(0.94, 0.89, 0.74)
const COL_IVORY_HI := Color(0.98, 0.95, 0.84)
const COL_IRON := Color(0.22, 0.24, 0.28)
const COL_IRON_DARK := Color(0.14, 0.16, 0.19)

const COL_BAMBOO := Color(0.76, 0.58, 0.27)
const COL_BAMBOO_HI := Color(0.85, 0.69, 0.35)
const COL_BAMBOO_NODE := Color(0.48, 0.33, 0.14)
const COL_LASHING := Color(0.17, 0.12, 0.09)
const COL_CORK_GRIP := Color(0.74, 0.56, 0.35)
const COL_CORK_GRIP_DARK := Color(0.60, 0.43, 0.25)
const COL_SPOOL_TWINE := Color(0.90, 0.86, 0.74)
const COL_KNOB_OAK := Color(0.32, 0.19, 0.11)

const COL_LINE_RELAXED := Color(0.92, 0.89, 0.80)
const COL_LINE_TAUT := Color(0.98, 0.78, 0.30)
const COL_LINE_WARN := Color(1.22, 0.50, 0.14)

var state: State = State.IDLE
var bobber_pos: Vector3 = Vector3.ZERO
var distance_out: float = 0.0
var line_tension: float = 0.0
var fish_fighting: bool = false
var hooked_species: Dictionary = {}
var caught_fish: Array[Dictionary] = []

var _bite_timer: float = 0.0
var _fight_timer: float = 0.0
var _splash_timer: float = 0.0
var _anim_clock: float = 0.0
var _last_caster_pos: Vector3 = Vector3.ZERO
var _cast_forward: Vector3 = Vector3.FORWARD

var _bobber_mesh: MeshInstance3D = null
var _bobber_mat: StandardMaterial3D = null

var _ripple_mesh: MeshInstance3D = null
var _ripple_mat: StandardMaterial3D = null
var _ripple_phase: float = 0.0
var _ripple_scale: float = 0.0

var _night_lure_halo: MeshInstance3D = null
var _night_lure_mat: StandardMaterial3D = null
var _night_lure_intensity: float = 0.0

var _rod_root: Node3D = null
var _rod_butt_mesh: MeshInstance3D = null
var _rod_mid_pivot: Node3D = null
var _rod_mid_mesh: MeshInstance3D = null
var _rod_tip_pivot: Node3D = null
var _rod_tip_mesh: MeshInstance3D = null
var _rod_tip_marker: Node3D = null
var _rod_mat: StandardMaterial3D = null

var _line_mesh_inst: MeshInstance3D = null
var _line_mesh: ImmediateMesh = null
var _line_mat: StandardMaterial3D = null

var _splash_particles: GPUParticles3D = null
var _splash_tex: ImageTexture = null
var _splash_mat: StandardMaterial3D = null

var _leaping_fish: MeshInstance3D = null
var _fish_body_mat: StandardMaterial3D = null
var _fish_eye_mat: StandardMaterial3D = null
var _leap_active: bool = false
var _leap_elapsed: float = 0.0
var _leap_start: Vector3 = Vector3.ZERO
var _leap_end: Vector3 = Vector3.ZERO
var _leap_base_scale: Vector3 = Vector3.ONE
var _leap_stepped_externally: bool = false

var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	_build_bobber()
	_build_bobber_ripples()
	_build_fishing_rod()
	_build_line_ribbon()
	_build_splash_particles()


func _physics_process(delta: float) -> void:
	if _leap_stepped_externally:
		_leap_stepped_externally = false
		return
	if _leap_active:
		_tick_leaping_fish(delta)


func _exit_tree() -> void:
	_clear_leaping_fish()
	if _splash_particles != null and is_instance_valid(_splash_particles):
		_splash_particles.emitting = false
		_splash_particles.visible = false
		_splash_particles.draw_pass_1 = null
		_splash_particles.process_material = null
	if _line_mesh != null:
		_line_mesh.clear_surfaces()
	if _line_mesh_inst != null and is_instance_valid(_line_mesh_inst):
		_line_mesh_inst.mesh = null
		_line_mesh_inst.material_override = null
	if _night_lure_halo != null and is_instance_valid(_night_lure_halo):
		_night_lure_halo.visible = false
		_night_lure_halo.mesh = null
		_night_lure_halo.material_override = null
	if _ripple_mesh != null and is_instance_valid(_ripple_mesh):
		_ripple_mesh.visible = false
		_ripple_mesh.mesh = null
		_ripple_mesh.material_override = null
	if _bobber_mesh != null and is_instance_valid(_bobber_mesh):
		_bobber_mesh.mesh = null
		_bobber_mesh.material_override = null
	for seg: MeshInstance3D in [_rod_butt_mesh, _rod_mid_mesh, _rod_tip_mesh]:
		if seg != null and is_instance_valid(seg):
			seg.mesh = null
			seg.material_override = null
	if _splash_mat != null:
		_splash_mat.albedo_texture = null
	_line_mesh = null
	_line_mat = null
	_bobber_mesh = null
	_bobber_mat = null
	_ripple_mesh = null
	_ripple_mat = null
	_ripple_phase = 0.0
	_ripple_scale = 0.0
	_night_lure_halo = null
	_night_lure_mat = null
	_night_lure_intensity = 0.0
	_rod_mat = null
	_splash_tex = null
	_splash_mat = null
	_fish_body_mat = null
	_fish_eye_mat = null


## Return the concentric water-ripple MeshInstance3D floating beneath the bobber.
func get_bobber_ripples_node() -> MeshInstance3D:
	return _ripple_mesh


## Return the additive billboard nocturnal NightLureHalo MeshInstance3D attached to the bobber.
func get_night_lure_halo_node() -> MeshInstance3D:
	return _night_lure_halo


## Return the current brightness intensity of the nocturnal moonlit lure halo.
func get_night_lure_intensity() -> float:
	return _night_lure_intensity


## Return the current horizontal expansion scale of the concentric water ripple rings.
func get_ripple_scale() -> float:
	return _ripple_scale


## Return the world-space position of the flexing bamboo fishing rod's tip eyelet.
func get_rod_tip_world_pos() -> Vector3:
	if _rod_tip_marker != null and is_instance_valid(_rod_tip_marker):
		return _rod_tip_marker.global_position
	return global_position + Vector3(0.0, 1.6, 0.0)


## Cast the line forward from `origin` along `forward` into the sea.
func cast_line(origin: Vector3, forward: Vector3, cast_dist: float = 11.0) -> bool:
	if state != State.IDLE:
		return false
	_clear_leaping_fish()
	var flat := Vector3(forward.x, 0.0, forward.z).normalized()
	if flat.length_squared() < 0.01:
		flat = Vector3.FORWARD
	_last_caster_pos = origin
	_cast_forward = flat
	bobber_pos = origin + flat * cast_dist
	bobber_pos.y = Sea.height(bobber_pos.x, bobber_pos.z)
	distance_out = cast_dist
	line_tension = 0.0
	fish_fighting = false
	hooked_species = {}
	state = State.WAITING
	_bite_timer = _rng.randf_range(3.0, 7.5)
	_splash_timer = 0.0
	_ripple_phase = 0.0
	_ripple_scale = RIPPLE_WAIT_SCALE_MIN

	_set_stowed_prop_visible(false)
	if _bobber_mesh != null:
		_bobber_mesh.visible = true
	if _ripple_mesh != null:
		_ripple_mesh.visible = true
	if _rod_root != null:
		_rod_root.visible = true
	if _line_mesh_inst != null:
		_line_mesh_inst.visible = true

	_update_bobber_transform()
	_update_bobber_ripples(0.0)
	_update_night_lure_halo()
	_update_rod_transform(origin)
	_update_line_ribbon()

	Audio.play_sfx(&"splash_small", bobber_pos)
	if Ocean.current != null:
		Ocean.current.add_foam(bobber_pos, 0.65, 0.45)
	_trigger_splash_burst(bobber_pos)
	cast_started.emit(bobber_pos)
	return true


func cancel_cast() -> void:
	state = State.IDLE
	line_tension = 0.0
	fish_fighting = false
	hooked_species = {}
	_splash_timer = 0.0
	_ripple_phase = 0.0
	_ripple_scale = 0.0
	_night_lure_intensity = 0.0
	if _bobber_mesh != null:
		_bobber_mesh.visible = false
	if _ripple_mesh != null:
		_ripple_mesh.visible = false
	if _night_lure_halo != null:
		_night_lure_halo.visible = false
	if _rod_root != null:
		_rod_root.visible = false
	if _line_mesh_inst != null:
		_line_mesh_inst.visible = false
	if _line_mesh != null:
		_line_mesh.clear_surfaces()
	if _splash_particles != null and is_instance_valid(_splash_particles):
		_splash_particles.emitting = false
	_set_stowed_prop_visible(true)


## Advance fishing simulation. Call each physics tick while holding a rod (`reeling = primary`).
func step(delta: float, caster_pos: Vector3, reeling: bool) -> void:
	if _leap_active:
		_tick_leaping_fish(delta)
		_leap_stepped_externally = true

	if state == State.IDLE:
		return

	_anim_clock += delta
	_last_caster_pos = caster_pos
	var surf := Sea.height(bobber_pos.x, bobber_pos.z)
	bobber_pos.y = surf - (0.035 + 0.030 * sin(_anim_clock * 19.0) if fish_fighting else 0.0)

	if state == State.WAITING:
		_bite_timer -= delta
		if _bite_timer <= 0.0:
			hooked_species = _pick_species()
			state = State.HOOKED
			fish_fighting = true
			_fight_timer = _rng.randf_range(1.2, 2.2)
			_splash_timer = SPLASH_INTERVAL
			_ripple_phase = 0.0
			bobber_pos.y = surf - 0.045
			Audio.play_sfx(&"splash_small", bobber_pos, 2.0)
			if Ocean.current != null:
				Ocean.current.add_foam(bobber_pos, 1.1, 0.75)
			_trigger_splash_burst(bobber_pos)
			_update_bobber_transform()
			_update_bobber_ripples(0.0)
			_update_night_lure_halo()
			_update_rod_transform(caster_pos)
			_update_line_ribbon()
			fish_hooked.emit(hooked_species)
			return
		_update_bobber_transform()
		_update_bobber_ripples(delta)
		_update_night_lure_halo()
		_update_rod_transform(caster_pos)
		_update_line_ribbon()
		return

	# State.HOOKED: toggle between fighting bursts and tired lulls!
	_fight_timer -= delta
	if _fight_timer <= 0.0:
		fish_fighting = not fish_fighting
		_fight_timer = _rng.randf_range(1.1, 2.1) if fish_fighting else _rng.randf_range(1.8, 3.0)
		if fish_fighting:
			_splash_timer = minf(_splash_timer, 0.05)

	var fight_pow := float(hooked_species.get("fight", 0.5))
	if reeling:
		if fish_fighting:
			line_tension += (0.55 + fight_pow * 0.65) * delta
			distance_out -= 0.7 * delta
		else:
			line_tension = maxf(0.0, line_tension - 0.18 * delta)
			distance_out -= 3.8 * delta
	else:
		line_tension = maxf(0.0, line_tension - 0.85 * delta)
		if fish_fighting:
			distance_out += 0.9 * fight_pow * delta

	# Pull bobber smoothly toward caster as distance_out shrinks.
	var to_bob := Vector3(bobber_pos.x - caster_pos.x, 0.0, bobber_pos.z - caster_pos.z)
	if to_bob.length_squared() > 0.01:
		var dir := to_bob.normalized()
		bobber_pos.x = caster_pos.x + dir.x * maxf(distance_out, 0.5)
		bobber_pos.z = caster_pos.z + dir.z * maxf(distance_out, 0.5)

	surf = Sea.height(bobber_pos.x, bobber_pos.z)
	bobber_pos.y = surf - (0.035 + 0.030 * sin(_anim_clock * 19.0) if fish_fighting else 0.0)

	# Churning foam rings & water-droplet splash bursts while the hooked fish fights.
	if fish_fighting:
		_splash_timer -= delta
		if _splash_timer <= 0.0:
			_splash_timer = SPLASH_INTERVAL
			if Ocean.current != null:
				Ocean.current.add_foam(bobber_pos, 0.95, 0.65)
			_trigger_splash_burst(bobber_pos)

	if line_tension >= 1.0:
		var lost := hooked_species
		cancel_cast()
		line_snapped.emit(lost)
	elif distance_out <= 1.2:
		var caught := hooked_species.duplicate()
		caught["cooked_state"] = &"raw"
		caught_fish.append(caught)
		var leap_origin := Vector3(bobber_pos.x, surf, bobber_pos.z)
		cancel_cast()
		_spawn_leaping_fish(caught, leap_origin, caster_pos + Vector3(0.0, 1.15, 0.0))
		if Ocean.current != null:
			Ocean.current.add_foam(leap_origin, 1.05, 0.75)
		_trigger_splash_burst(leap_origin)
		Audio.play_sfx(&"splash_small", caster_pos)
		Game.post_notice("Caught a %s!" % String(caught["name"]))
		fish_caught.emit(caught)
	else:
		_update_bobber_transform()
		_update_bobber_ripples(delta)
		_update_night_lure_halo()
		_update_rod_transform(caster_pos)
		_update_line_ribbon()


func _pick_species() -> Dictionary:
	var is_storm := Weather.storminess > 0.55
	var is_night := Weather.is_night()
	var pool: Array[Dictionary] = []
	for sp in SPECIES:
		if bool(sp["storm_only"]) and not is_storm:
			continue
		if bool(sp["night_only"]) and not is_night:
			continue
		pool.append(sp)
	if pool.is_empty():
		return SPECIES[0]
	return pool[_rng.randi_range(0, pool.size() - 1)]


func _set_stowed_prop_visible(show_prop: bool) -> void:
	var prop := get_node_or_null(^"FishingRodProp") as Node3D
	if prop != null:
		prop.visible = show_prop


# ==============================================================================
# 1. Sculpted Two-Tone Painted Wooden Cork-and-Crimson Bobber
# ==============================================================================

func _build_bobber() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Lathed wooden pirate fishing float: dark iron bottom swivel weight, warm varnished
	# cork/cream lower belly, proud brass belly ring, bold sailor-crimson painted dome,
	# and slender bamboo/ivory quill antenna (+0.14 m above the dome).
	var rings: Array[Array] = [
		[-0.172, 0.000, COL_IRON_DARK],
		[-0.152, 0.022, COL_IRON],
		[-0.126, 0.029, COL_IRON],
		[-0.106, 0.015, COL_IRON_DARK],
		[-0.096, 0.024, COL_BRASS_DARK],
		[-0.092, 0.044, COL_CORK_SHADE],
		[-0.070, 0.084, COL_CORK_BASE],
		[-0.042, 0.108, COL_CORK_BASE],
		[-0.016, 0.113, COL_CORK_BASE],
		[-0.014, 0.119, COL_BRASS_DARK],
		[0.000, 0.123, COL_BRASS],
		[0.014, 0.119, COL_BRASS_DARK],
		[0.016, 0.113, COL_CRIMSON_SHADE],
		[0.044, 0.105, COL_CRIMSON],
		[0.074, 0.080, COL_CRIMSON_HI],
		[0.093, 0.042, COL_CRIMSON],
		[0.099, 0.025, COL_BRASS],
		[0.104, 0.015, COL_IVORY],
		[0.152, 0.013, COL_IVORY],
		[0.172, 0.012, COL_CRIMSON],
		[0.194, 0.011, COL_CRIMSON_HI],
		[0.200, 0.010, COL_IVORY_HI],
		[0.232, 0.016, COL_IVORY_HI],
		[0.244, 0.000, COL_BRASS],
	]
	_append_lathe_y(st, rings, 12)
	# Top brass line swivel eyelet right at the quill tip and bottom iron sinker loop.
	_append_torus_ring(st, Vector3(0.0, 0.248, 0.0), Vector3.RIGHT, 0.009, 0.0026, 8, 5, COL_BRASS)
	_append_torus_ring(st, Vector3(0.0, -0.175, 0.0), Vector3.RIGHT, 0.008, 0.0025, 8, 5, COL_IRON)
	st.generate_normals()

	_bobber_mat = StandardMaterial3D.new()
	_bobber_mat.vertex_color_use_as_albedo = true
	_bobber_mat.vertex_color_is_srgb = true
	_bobber_mat.roughness = 0.34
	_bobber_mat.metallic = 0.10
	_bobber_mat.clearcoat_enabled = true
	_bobber_mat.clearcoat = 0.42
	_bobber_mat.clearcoat_roughness = 0.22

	_bobber_mesh = MeshInstance3D.new()
	_bobber_mesh.name = "Bobber"
	_bobber_mesh.mesh = st.commit()
	_bobber_mesh.material_override = _bobber_mat
	_bobber_mesh.visible = false
	_bobber_mesh.top_level = true
	add_child(_bobber_mesh)

	# Nocturnal bioluminescent moonlit lure halo riding at the bobber quill swivel tip.
	_night_lure_mat = StandardMaterial3D.new()
	_night_lure_mat.vertex_color_use_as_albedo = true
	_night_lure_mat.vertex_color_is_srgb = true
	_night_lure_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_night_lure_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_night_lure_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_night_lure_mat.billboard_keep_scale = true
	_night_lure_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	_night_lure_mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	_night_lure_halo = MeshInstance3D.new()
	_night_lure_halo.name = "NightLureHalo"
	_night_lure_halo.position = Vector3(0.0, BOBBER_SWIVEL_Y, 0.0)
	_night_lure_halo.mesh = _build_night_lure_halo_mesh()
	_night_lure_halo.material_override = _night_lure_mat
	_night_lure_halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_night_lure_halo.visible = false
	_bobber_mesh.add_child(_night_lure_halo)


func _build_bobber_ripples() -> void:
	_ripple_mat = StandardMaterial3D.new()
	_ripple_mat.vertex_color_use_as_albedo = true
	_ripple_mat.vertex_color_is_srgb = true
	_ripple_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ripple_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ripple_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	_ripple_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_ripple_mat.albedo_color = Color(0.84, 0.96, 1.00, 0.65)

	_ripple_mesh = MeshInstance3D.new()
	_ripple_mesh.name = "BobberRippleRings"
	_ripple_mesh.mesh = _build_ripple_rings_mesh()
	_ripple_mesh.material_override = _ripple_mat
	_ripple_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ripple_mesh.visible = false
	_ripple_mesh.top_level = true
	add_child(_ripple_mesh)


static func _build_ripple_rings_mesh() -> ArrayMesh:
	# Sculpted concentric 2-ring horizontal water-ripple mesh (feathered bevel profile, finite upward unit normals).
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	const SEGS := 24
	var norm := Vector3(0.0, 1.0, 0.0)
	# Each ring spec: [r_in, r_mid, r_out, y_crest, peak_alpha]
	var ring_specs: Array[Array] = [
		[0.19, 0.25, 0.31, 0.008, 0.92],
		[0.42, 0.48, 0.54, 0.006, 0.72],
	]
	for spec in ring_specs:
		var r_in := float(spec[0])
		var r_mid := float(spec[1])
		var r_out := float(spec[2])
		var y_crest := float(spec[3])
		var peak_a := float(spec[4])
		var col_in := Color(0.84, 0.96, 1.00, 0.0)
		var col_peak := Color(0.98, 1.00, 1.00, peak_a)
		var col_out := Color(0.80, 0.95, 1.00, 0.0)
		for i in SEGS:
			var a0 := float(i) / float(SEGS) * TAU
			var a1 := float(i + 1) / float(SEGS) * TAU
			var c0 := cos(a0)
			var s0 := sin(a0)
			var c1 := cos(a1)
			var s1 := sin(a1)
			var p_in0 := Vector3(c0 * r_in, 0.0, s0 * r_in)
			var p_in1 := Vector3(c1 * r_in, 0.0, s1 * r_in)
			var p_mid0 := Vector3(c0 * r_mid, y_crest, s0 * r_mid)
			var p_mid1 := Vector3(c1 * r_mid, y_crest, s1 * r_mid)
			var p_out0 := Vector3(c0 * r_out, 0.0, s0 * r_out)
			var p_out1 := Vector3(c1 * r_out, 0.0, s1 * r_out)

			# Inner bevel slope: r_in -> r_mid (CW from +Y so (c - a).cross(b - a) points +Y).
			st.set_normal(norm); st.set_color(col_in); st.add_vertex(p_in0)
			st.set_normal(norm); st.set_color(col_peak); st.add_vertex(p_mid0)
			st.set_normal(norm); st.set_color(col_peak); st.add_vertex(p_mid1)

			st.set_normal(norm); st.set_color(col_in); st.add_vertex(p_in0)
			st.set_normal(norm); st.set_color(col_peak); st.add_vertex(p_mid1)
			st.set_normal(norm); st.set_color(col_in); st.add_vertex(p_in1)

			# Outer bevel slope: r_mid -> r_out.
			st.set_normal(norm); st.set_color(col_peak); st.add_vertex(p_mid0)
			st.set_normal(norm); st.set_color(col_out); st.add_vertex(p_out0)
			st.set_normal(norm); st.set_color(col_out); st.add_vertex(p_out1)

			st.set_normal(norm); st.set_color(col_peak); st.add_vertex(p_mid0)
			st.set_normal(norm); st.set_color(col_out); st.add_vertex(p_out1)
			st.set_normal(norm); st.set_color(col_peak); st.add_vertex(p_mid1)
	return st.commit()


static func _build_night_lure_halo_mesh() -> ArrayMesh:
	# Sculpted 16-wedge radial-gradient additive billboard halo disc (moonlit cyan-gold core -> black rim).
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	const WEDGES := 16
	const OUTER_R := 0.36
	const MID_R := 0.16
	var col_core := Color(0.86, 0.99, 0.88, 1.0)
	var col_mid := Color(0.28, 0.84, 0.80, 1.0)
	var col_rim := Color(0.0, 0.0, 0.0, 1.0)
	var center := Vector3.ZERO
	var norm := Vector3(0.0, 0.0, 1.0)
	for i in WEDGES:
		var a0 := float(i) / float(WEDGES) * TAU
		var a1 := float(i + 1) / float(WEDGES) * TAU
		var m0 := Vector3(cos(a0) * MID_R, sin(a0) * MID_R, 0.0)
		var m1 := Vector3(cos(a1) * MID_R, sin(a1) * MID_R, 0.0)
		var o0 := Vector3(cos(a0) * OUTER_R, sin(a0) * OUTER_R, 0.0)
		var o1 := Vector3(cos(a1) * OUTER_R, sin(a1) * OUTER_R, 0.0)
		st.set_normal(norm); st.set_color(col_core); st.add_vertex(center)
		st.set_normal(norm); st.set_color(col_mid); st.add_vertex(m1)
		st.set_normal(norm); st.set_color(col_mid); st.add_vertex(m0)

		st.set_normal(norm); st.set_color(col_mid); st.add_vertex(m0)
		st.set_normal(norm); st.set_color(col_mid); st.add_vertex(m1)
		st.set_normal(norm); st.set_color(col_rim); st.add_vertex(o1)

		st.set_normal(norm); st.set_color(col_mid); st.add_vertex(m0)
		st.set_normal(norm); st.set_color(col_rim); st.add_vertex(o1)
		st.set_normal(norm); st.set_color(col_rim); st.add_vertex(o0)
	return st.commit()


func _update_bobber_ripples(delta: float) -> void:
	if _ripple_mesh == null or not is_instance_valid(_ripple_mesh) or _ripple_mat == null:
		return
	if state == State.IDLE:
		_ripple_mesh.visible = false
		_ripple_scale = 0.0
		return

	_ripple_mesh.visible = true
	var speed_mult := 1.0
	var s_min := RIPPLE_WAIT_SCALE_MIN
	var s_max := RIPPLE_WAIT_SCALE_MAX
	var base_col := Color(0.82, 0.96, 1.00, 1.0)
	var peak_alpha := 0.68

	if state == State.HOOKED:
		if fish_fighting:
			speed_mult = RIPPLE_FIGHT_SPEED_MULT
			s_min = RIPPLE_FIGHT_SCALE_MIN
			s_max = RIPPLE_FIGHT_SCALE_MAX
			base_col = Color(0.96, 1.00, 1.00, 1.0)
			peak_alpha = 0.94
		else:
			speed_mult = 1.45
			s_min = 0.50
			s_max = 1.68
			base_col = Color(0.88, 0.98, 1.00, 1.0)
			peak_alpha = 0.78

	_ripple_phase = fposmod(_ripple_phase + (delta * speed_mult) / RIPPLE_WAIT_PERIOD, 1.0)
	var u := _ripple_phase
	var ease_u := lerpf(u, 1.0 - (1.0 - u) * (1.0 - u), 0.30)
	_ripple_scale = lerpf(s_min, s_max, ease_u)

	var fade_in := lerpf(0.45, 1.0, smoothstep(0.0, 0.12, u))
	var fade_out := pow(clampf(1.0 - u, 0.0, 1.0), 1.30)
	var alpha := fade_in * fade_out * peak_alpha
	_ripple_mat.albedo_color = Color(base_col.r, base_col.g, base_col.b, alpha)

	var y_surf := Sea.height(bobber_pos.x, bobber_pos.z)
	var pos := Vector3(bobber_pos.x, y_surf + RIPPLE_WATER_OFFSET, bobber_pos.z)
	var sea_n := Sea.normal(bobber_pos.x, bobber_pos.z)
	var up := sea_n.lerp(Vector3.UP, 0.50).normalized()
	var ref := Vector3.FORWARD if absf(up.dot(Vector3.FORWARD)) < 0.95 else Vector3.RIGHT
	var right := up.cross(ref).normalized()
	var fwd := right.cross(up).normalized()
	var wave_basis := Basis(right, up, fwd) * Basis(Vector3.UP, _anim_clock * 0.22)
	_ripple_mesh.global_transform = Transform3D(
		wave_basis.scaled(Vector3(_ripple_scale, 1.0, _ripple_scale)),
		pos
	)


func _update_night_lure_halo() -> void:
	if _night_lure_halo == null or not is_instance_valid(_night_lure_halo) or _night_lure_mat == null:
		return
	if state == State.IDLE:
		_night_lure_halo.visible = false
		_night_lure_intensity = 0.0
		return

	var dl := clampf(Weather.daylight(), 0.0, 1.0) if Weather != null else 1.0
	var darkness := clampf(1.0 - dl, 0.0, 1.0)
	var breathe := 0.90 + 0.10 * sin(_anim_clock * 3.6)
	var bite_surge := 0.0
	if state == State.HOOKED:
		var strike_pulse := 0.84 + 0.16 * sin(_anim_clock * 14.5)
		bite_surge = (0.55 if fish_fighting else 0.30) * strike_pulse
	var base_glow := lerpf(0.05, 1.15, darkness)
	_night_lure_intensity = (base_glow + bite_surge) * breathe

	# Moonlit cyan-gold nocturnal glow that flares warmer gold when a fish strikes!
	var hooked_warm := 0.45 if state == State.HOOKED else 0.0
	var tint := Color(0.68, 0.98, 0.92, 1.0).lerp(Color(1.00, 0.90, 0.62, 1.0), hooked_warm)
	_night_lure_mat.albedo_color = Color(
		tint.r * _night_lure_intensity,
		tint.g * _night_lure_intensity,
		tint.b * _night_lure_intensity,
		1.0
	)
	var h_scale := lerpf(0.58, 1.32, clampf(_night_lure_intensity / 1.5, 0.0, 1.0))
	_night_lure_halo.scale = Vector3(h_scale, h_scale, h_scale)
	_night_lure_halo.visible = true


func _update_bobber_transform() -> void:
	if _bobber_mesh == null or not is_instance_valid(_bobber_mesh):
		return
	var sea_n := Sea.normal(bobber_pos.x, bobber_pos.z)
	# Bottom iron weight keeps the float slightly self-righting while still tilting with swells.
	var up := sea_n.lerp(Vector3.UP, 0.24).normalized()
	var fwd := Vector3(bobber_pos.x - _last_caster_pos.x, 0.0, bobber_pos.z - _last_caster_pos.z)
	if fwd.length_squared() < 0.0001:
		fwd = _cast_forward
	fwd = (fwd - up * fwd.dot(up))
	if fwd.length_squared() < 0.0001:
		fwd = Vector3.FORWARD
	else:
		fwd = fwd.normalized()
	var right := up.cross(fwd)
	if right.length_squared() < 0.0001:
		right = Vector3.RIGHT
	else:
		right = right.normalized()
	fwd = right.cross(up).normalized()
	var wave_basis := Basis(right, up, fwd)

	var wobble := Basis.IDENTITY
	var visual_pos := bobber_pos
	if fish_fighting:
		var wx := sin(_anim_clock * 23.0) * 0.42
		var wz := cos(_anim_clock * 19.0) * 0.36
		var wy := sin(_anim_clock * 11.0) * 0.65
		wobble = Basis.from_euler(Vector3(wx, wy, wz))
		visual_pos += right * (sin(_anim_clock * 15.0) * 0.06)
	else:
		var gentle_x := sin(_anim_clock * 2.7) * 0.08
		var gentle_z := cos(_anim_clock * 2.2) * 0.07
		wobble = Basis.from_euler(Vector3(gentle_x, sin(_anim_clock * 0.8) * 0.22, gentle_z))
		visual_pos.y += sin(_anim_clock * 3.1) * 0.018

	_bobber_mesh.global_transform = Transform3D(wave_basis * wobble, visual_pos)


func _get_bobber_swivel_world_pos() -> Vector3:
	if _bobber_mesh != null and is_instance_valid(_bobber_mesh):
		return _bobber_mesh.global_transform * Vector3(0.0, BOBBER_SWIVEL_Y, 0.0)
	return bobber_pos + Vector3(0.0, BOBBER_SWIVEL_Y, 0.0)


# ==============================================================================
# 2. Visible Bending Bamboo-and-Brass Fishing Rod
# ==============================================================================

func _build_fishing_rod() -> void:
	_rod_mat = StandardMaterial3D.new()
	_rod_mat.vertex_color_use_as_albedo = true
	_rod_mat.vertex_color_is_srgb = true
	_rod_mat.roughness = 0.40
	_rod_mat.metallic = 0.16

	_rod_root = Node3D.new()
	_rod_root.name = "FishingRod"
	_rod_root.visible = false
	_rod_root.top_level = true
	add_child(_rod_root)

	# Section 1: Cork handle grip, brass butt cap, brass reel housing & spool, lower bamboo + guide #1.
	_rod_butt_mesh = MeshInstance3D.new()
	_rod_butt_mesh.name = "RodButtSection"
	_rod_butt_mesh.mesh = _build_rod_butt_mesh()
	_rod_butt_mesh.material_override = _rod_mat
	_rod_root.add_child(_rod_butt_mesh)

	# Section 2: Middle flexing bamboo segment + bamboo joint nodes + guides #2 and #3.
	_rod_mid_pivot = Node3D.new()
	_rod_mid_pivot.name = "RodMidPivot"
	_rod_mid_pivot.position = Vector3(0.0, 0.0, -ROD_BUTT_LEN)
	_rod_root.add_child(_rod_mid_pivot)

	_rod_mid_mesh = MeshInstance3D.new()
	_rod_mid_mesh.name = "RodMidSection"
	_rod_mid_mesh.mesh = _build_rod_mid_mesh()
	_rod_mid_mesh.material_override = _rod_mat
	_rod_mid_pivot.add_child(_rod_mid_mesh)

	# Section 3: Slender bamboo tip + guide #4 + tip-top brass eyelet.
	_rod_tip_pivot = Node3D.new()
	_rod_tip_pivot.name = "RodTipPivot"
	_rod_tip_pivot.position = Vector3(0.0, 0.0, -ROD_MID_LEN)
	_rod_mid_pivot.add_child(_rod_tip_pivot)

	_rod_tip_mesh = MeshInstance3D.new()
	_rod_tip_mesh.name = "RodTipSection"
	_rod_tip_mesh.mesh = _build_rod_tip_mesh()
	_rod_tip_mesh.material_override = _rod_mat
	_rod_tip_pivot.add_child(_rod_tip_mesh)

	_rod_tip_marker = Node3D.new()
	_rod_tip_marker.name = "RodTipMarker"
	_rod_tip_marker.position = Vector3(0.0, 0.0, -ROD_TIP_LEN)
	_rod_tip_pivot.add_child(_rod_tip_marker)


func _build_rod_butt_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Handle & lower bamboo shaft along -Z (distance increases from -0.08 behind hand to +0.95).
	var rings: Array[Array] = [
		[-0.085, 0.000, COL_BRASS_DARK],
		[-0.075, 0.028, COL_BRASS],
		[-0.055, 0.030, COL_BRASS_DARK],
		[-0.050, 0.028, COL_CORK_GRIP_DARK],
		[0.050, 0.032, COL_CORK_GRIP],
		[0.160, 0.030, COL_CORK_GRIP],
		[0.240, 0.027, COL_CORK_GRIP_DARK],
		[0.250, 0.029, COL_BRASS],
		[0.285, 0.027, COL_BRASS_DARK],
		[0.295, 0.023, COL_LASHING],
		[0.330, 0.023, COL_LASHING],
		[0.338, 0.022, COL_BAMBOO],
		[0.545, 0.020, COL_BAMBOO_HI],
		[0.560, 0.023, COL_BAMBOO_NODE],
		[0.576, 0.020, COL_BAMBOO],
		[0.745, 0.0185, COL_BAMBOO_HI],
		[0.752, 0.020, COL_LASHING],
		[0.805, 0.0195, COL_LASHING],
		[0.812, 0.018, COL_BAMBOO],
		[0.920, 0.0175, COL_BAMBOO],
		[0.926, 0.0195, COL_BRASS_DARK],
		[ROD_BUTT_LEN, 0.0185, COL_BRASS],
		[ROD_BUTT_LEN, 0.000, COL_BRASS_DARK],
	]
	_append_lathe_neg_z(st, rings, 8)

	# Underside brass reel seat foot + turned brass reel housing, wound spool, and starboard crank!
	var reel_c := Vector3(0.0, -0.062, -0.22)
	_append_cylinder_between(st, Vector3(0.0, -0.022, -0.22), reel_c + Vector3(0.0, 0.024, 0.0), 0.012, 0.014, 6, COL_BRASS_DARK, COL_BRASS)
	# Left & right brass side plates along X axis.
	_append_cylinder_between(st, reel_c + Vector3(-0.034, 0.0, 0.0), reel_c + Vector3(-0.024, 0.0, 0.0), 0.048, 0.050, 10, COL_BRASS_DARK, COL_BRASS)
	_append_cylinder_between(st, reel_c + Vector3(0.024, 0.0, 0.0), reel_c + Vector3(0.034, 0.0, 0.0), 0.050, 0.048, 10, COL_BRASS, COL_BRASS_DARK)
	# Wound waxed-linen fishing line spool between the brass plates.
	_append_cylinder_between(st, reel_c + Vector3(-0.024, 0.0, 0.0), reel_c + Vector3(0.024, 0.0, 0.0), 0.038, 0.038, 10, COL_SPOOL_TWINE, COL_SPOOL_TWINE)
	# Brass axle boss, crank arm, and dark oak handle knob on +X (starboard).
	_append_cylinder_between(st, reel_c + Vector3(0.034, 0.0, 0.0), reel_c + Vector3(0.052, 0.0, 0.0), 0.014, 0.010, 6, COL_BRASS, COL_BRASS_DARK)
	var crank_end := reel_c + Vector3(0.052, 0.032, -0.024)
	_append_cylinder_between(st, reel_c + Vector3(0.048, 0.0, 0.0), crank_end, 0.007, 0.006, 6, COL_BRASS, COL_BRASS)
	_append_cylinder_between(st, crank_end, crank_end + Vector3(0.024, 0.0, 0.0), 0.011, 0.009, 6, COL_KNOB_OAK, COL_IVORY)

	# Guide ring #1 mounted under dark lashing at z = -0.78.
	_append_line_guide(st, Vector3(0.0, -0.036, -0.78), 0.021, 0.0042, 0.018)

	st.generate_normals()
	return st.commit()


func _build_rod_mid_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var rings: Array[Array] = [
		[0.000, 0.000, COL_BRASS_DARK],
		[0.000, 0.0185, COL_BRASS],
		[0.025, 0.018, COL_BRASS_DARK],
		[0.032, 0.0175, COL_LASHING],
		[0.055, 0.017, COL_LASHING],
		[0.062, 0.0165, COL_BAMBOO],
		[0.275, 0.0155, COL_BAMBOO_HI],
		[0.282, 0.017, COL_LASHING],
		[0.325, 0.0165, COL_LASHING],
		[0.332, 0.015, COL_BAMBOO],
		[0.495, 0.014, COL_BAMBOO_HI],
		[0.510, 0.0165, COL_BAMBOO_NODE],
		[0.525, 0.0138, COL_BAMBOO],
		[0.710, 0.0128, COL_BAMBOO_HI],
		[0.718, 0.0142, COL_LASHING],
		[0.760, 0.0138, COL_LASHING],
		[0.768, 0.0124, COL_BAMBOO],
		[0.828, 0.0122, COL_BAMBOO],
		[0.834, 0.0140, COL_BRASS_DARK],
		[ROD_MID_LEN, 0.0132, COL_BRASS],
		[ROD_MID_LEN, 0.000, COL_BRASS_DARK],
	]
	_append_lathe_neg_z(st, rings, 8)

	# Guide rings #2 and #3 under dark lashings.
	_append_line_guide(st, Vector3(0.0, -0.030, -0.304), 0.017, 0.0038, 0.015)
	_append_line_guide(st, Vector3(0.0, -0.026, -0.739), 0.015, 0.0035, 0.013)

	st.generate_normals()
	return st.commit()


func _build_rod_tip_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var rings: Array[Array] = [
		[0.000, 0.000, COL_BRASS_DARK],
		[0.000, 0.0132, COL_BRASS],
		[0.022, 0.0128, COL_BRASS_DARK],
		[0.030, 0.0122, COL_LASHING],
		[0.050, 0.0118, COL_LASHING],
		[0.058, 0.0114, COL_BAMBOO],
		[0.335, 0.0102, COL_BAMBOO_HI],
		[0.342, 0.0116, COL_LASHING],
		[0.382, 0.0112, COL_LASHING],
		[0.390, 0.0098, COL_BAMBOO],
		[0.575, 0.0086, COL_BAMBOO_HI],
		[0.588, 0.0104, COL_BAMBOO_NODE],
		[0.600, 0.0084, COL_BAMBOO],
		[0.722, 0.0078, COL_BAMBOO],
		[0.728, 0.0094, COL_BRASS],
		[ROD_TIP_LEN, 0.0076, COL_BRASS],
		[ROD_TIP_LEN + 0.004, 0.000, COL_BRASS_DARK],
	]
	_append_lathe_neg_z(st, rings, 8)

	# Guide ring #4 plus gleaming tip-top brass eyelet right at the end of the pole.
	_append_line_guide(st, Vector3(0.0, -0.022, -0.362), 0.013, 0.0032, 0.011)
	_append_torus_ring(st, Vector3(0.0, -0.012, -ROD_TIP_LEN), Vector3(0.0, 0.0, -1.0), 0.011, 0.0030, 8, 5, COL_BRASS)

	st.generate_normals()
	return st.commit()


func _append_line_guide(st: SurfaceTool, ring_center: Vector3, ring_r: float, wire_r: float, shaft_r: float) -> void:
	# Brass eyelet ring aligned along -Z so line passes cleanly through it.
	_append_torus_ring(st, ring_center, Vector3(0.0, 0.0, -1.0), ring_r, wire_r, 8, 5, COL_BRASS)
	# Fore & aft brass standoff legs clasping the dark lashing on the underside of the rod.
	var top_pt := ring_center + Vector3(0.0, ring_r, 0.0)
	var foot_a := Vector3(0.0, -shaft_r * 0.72, ring_center.z + 0.020)
	var foot_b := Vector3(0.0, -shaft_r * 0.72, ring_center.z - 0.020)
	_append_cylinder_between(st, foot_a, top_pt, wire_r * 0.95, wire_r * 0.85, 5, COL_BRASS_DARK, COL_BRASS)
	_append_cylinder_between(st, foot_b, top_pt, wire_r * 0.95, wire_r * 0.85, 5, COL_BRASS_DARK, COL_BRASS)


func _update_rod_transform(caster_pos: Vector3) -> void:
	if _rod_root == null or not is_instance_valid(_rod_root):
		return
	var to_bob := Vector3(bobber_pos.x - caster_pos.x, 0.0, bobber_pos.z - caster_pos.z)
	var forward := to_bob.normalized() if to_bob.length_squared() > 0.0001 else _cast_forward
	if forward.length_squared() < 0.0001:
		forward = Vector3.FORWARD
	var up := Vector3.UP
	var right := forward.cross(up)
	if right.length_squared() < 0.0001:
		right = Vector3.RIGHT
	else:
		right = right.normalized()

	var hold_pos := caster_pos + forward * 0.55 + right * 0.28 + up * 1.15
	var base_basis := Basis(right, up, -forward)

	# Smooth continuous monotonic bamboo cane arch across butt (0.18), mid (0.28), and tip (0.36).
	var tension := clampf(line_tension, 0.0, 1.0)
	var hook_load := 0.14 if state == State.HOOKED else 0.0
	var bend_load := clampf(tension + hook_load * (1.0 - tension * 0.45), 0.0, 1.15)
	var tremor := sin(_anim_clock * 34.0) * (0.035 + tension * 0.045) if fish_fighting else 0.0
	var side_tremor := cos(_anim_clock * 27.0) * (0.025 + tension * 0.035) if fish_fighting else 0.0

	var root_pitch := 0.40 - bend_load * 0.18 + tremor * 0.30
	_rod_root.global_transform = Transform3D(
		base_basis * Basis.from_euler(Vector3(root_pitch, side_tremor * 0.35, 0.0)),
		hold_pos
	)
	if _rod_mid_pivot != null:
		_rod_mid_pivot.rotation = Vector3(-0.04 - bend_load * 0.28 - absf(tremor) * 0.28, side_tremor * 0.5, 0.0)
	if _rod_tip_pivot != null:
		_rod_tip_pivot.rotation = Vector3(-0.06 - bend_load * 0.36 + tremor * 0.60, side_tremor, 0.0)


# ==============================================================================
# 3. Dynamic 14-Segment Catenary Fishing Line Ribbon (`ImmediateMesh`)
# ==============================================================================

func _build_line_ribbon() -> void:
	_line_mesh = ImmediateMesh.new()
	_line_mat = StandardMaterial3D.new()
	_line_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_line_mat.vertex_color_use_as_albedo = true
	_line_mat.vertex_color_is_srgb = true
	_line_mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	_line_mesh_inst = MeshInstance3D.new()
	_line_mesh_inst.name = "FishingLineRibbon"
	_line_mesh_inst.mesh = _line_mesh
	_line_mesh_inst.material_override = _line_mat
	_line_mesh_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_line_mesh_inst.visible = false
	_line_mesh_inst.top_level = true
	add_child(_line_mesh_inst)


func _update_line_ribbon() -> void:
	if _line_mesh == null or _line_mesh_inst == null or not is_instance_valid(_line_mesh_inst):
		return
	_line_mesh_inst.global_transform = Transform3D.IDENTITY
	_line_mesh.clear_surfaces()

	var p_start := get_rod_tip_world_pos()
	var p_end := _get_bobber_swivel_world_pos()
	var span := p_end - p_start
	if span.length_squared() < 1e-6:
		return

	var tension := clampf(line_tension, 0.0, 1.0)
	var sag := lerpf(0.85, 0.04, clampf(tension * 1.4, 0.0, 1.0))
	var warn := clampf((tension - 0.72) / 0.28, 0.0, 1.0)

	# Diegetic tension color: waxed-hemp cream -> taut golden -> glowing warm-amber warning!
	var line_col := COL_LINE_RELAXED.lerp(COL_LINE_TAUT, clampf(tension * 1.25, 0.0, 1.0))
	if warn > 0.0:
		var pulse := 0.5 + 0.5 * sin(_anim_clock * 28.0)
		line_col = line_col.lerp(COL_LINE_WARN, clampf(warn * (0.72 + 0.28 * pulse), 0.0, 1.0))

	var span_dir := span.normalized()
	var hum_axis := span_dir.cross(Vector3.UP)
	if hum_axis.length_squared() < 1e-5:
		hum_axis = Vector3.RIGHT
	else:
		hum_axis = hum_axis.normalized()

	var pts: Array[Vector3] = []
	pts.resize(LINE_SEGMENTS + 1)
	var cosh_k := cosh(1.35)
	var cosh_denom := maxf(cosh_k - 1.0, 0.001)
	for i in LINE_SEGMENTS + 1:
		var u := float(i) / float(LINE_SEGMENTS)
		var pt := p_start.lerp(p_end, u)
		var cx := (u - 0.5) * 2.0
		var cat_w := (cosh_k - cosh(1.35 * cx)) / cosh_denom
		pt.y -= sag * cat_w
		if warn > 0.0:
			var hum_amp := warn * 0.018 * sin(u * PI)
			pt += hum_axis * (sin(_anim_clock * 54.0 + u * 9.5) * hum_amp)
		pts[i] = pt

	var cam: Camera3D = null
	var vp := get_viewport()
	if vp != null:
		cam = vp.get_camera_3d()
	var half_w := lerpf(0.0085, 0.013, warn)

	_line_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i in LINE_SEGMENTS + 1:
		var tang: Vector3
		if i == 0:
			tang = (pts[1] - pts[0]).normalized()
		elif i == LINE_SEGMENTS:
			tang = (pts[i] - pts[i - 1]).normalized()
		else:
			tang = (pts[i + 1] - pts[i - 1]).normalized()
		if tang.length_squared() < 1e-6:
			tang = span_dir

		var view_dir := (cam.global_position - pts[i]).normalized() if cam != null else Vector3.UP
		var side := tang.cross(view_dir)
		if side.length_squared() < 1e-5:
			side = tang.cross(Vector3.UP)
		if side.length_squared() < 1e-5:
			side = Vector3.RIGHT
		side = side.normalized() * half_w

		_line_mesh.surface_set_color(line_col)
		_line_mesh.surface_add_vertex(pts[i] - side)
		_line_mesh.surface_set_color(line_col)
		_line_mesh.surface_add_vertex(pts[i] + side)
	_line_mesh.surface_end()


# ==============================================================================
# 4. Hooked-Fish Churning Splash Particles & Leaping Caught Fish Arc
# ==============================================================================

func _build_splash_particles() -> void:
	_splash_tex = _make_droplet_texture()
	_splash_mat = StandardMaterial3D.new()
	_splash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_splash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_splash_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	_splash_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_splash_mat.vertex_color_use_as_albedo = true
	_splash_mat.albedo_texture = _splash_tex

	var proc := ParticleProcessMaterial.new()
	proc.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	proc.emission_ring_axis = Vector3.UP
	proc.emission_ring_radius = 0.18
	proc.emission_ring_inner_radius = 0.04
	proc.emission_ring_height = 0.06
	proc.direction = Vector3.UP
	proc.spread = 46.0
	proc.initial_velocity_min = 2.0
	proc.initial_velocity_max = 4.2
	proc.damping_min = 0.4
	proc.damping_max = 1.0
	proc.gravity = Vector3(0.0, -11.5, 0.0)
	proc.scale_min = 0.55
	proc.scale_max = 1.15

	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.16, 0.65, 1.0])
	grad.colors = PackedColorArray([
		Color(0.95, 0.99, 1.0, 0.0),
		Color(0.94, 0.99, 1.0, 0.88),
		Color(0.78, 0.95, 0.99, 0.52),
		Color(0.70, 0.90, 0.96, 0.0),
	])
	var ramp := GradientTexture1D.new()
	ramp.width = 24
	ramp.gradient = grad
	proc.color_ramp = ramp

	var quad := QuadMesh.new()
	quad.size = Vector2(0.20, 0.30)
	quad.material = _splash_mat

	_splash_particles = GPUParticles3D.new()
	_splash_particles.name = "FishingSplashParticles"
	_splash_particles.one_shot = true
	_splash_particles.explosiveness = 0.86
	_splash_particles.amount = 10
	_splash_particles.lifetime = 0.52
	_splash_particles.local_coords = false
	_splash_particles.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY
	_splash_particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_splash_particles.visibility_aabb = AABB(Vector3(-3.0, -1.5, -3.0), Vector3(6.0, 5.0, 6.0))
	_splash_particles.process_material = proc
	_splash_particles.draw_pass_1 = quad
	_splash_particles.emitting = false
	_splash_particles.top_level = true
	add_child(_splash_particles)


func _trigger_splash_burst(world_pos: Vector3) -> void:
	if _splash_particles == null or not is_instance_valid(_splash_particles) or not is_inside_tree():
		return
	var y_surf := Sea.height(world_pos.x, world_pos.z)
	_splash_particles.global_position = Vector3(world_pos.x, y_surf + 0.05, world_pos.z)
	_splash_particles.restart()
	_splash_particles.emitting = true


static func _make_droplet_texture() -> ImageTexture:
	var sz := 32
	var img := Image.create(sz, sz, false, Image.FORMAT_RGBA8)
	var half := float(sz - 1) * 0.5
	for y in sz:
		for x in sz:
			var nx := (float(x) - half) / half
			var ny := (float(y) - half) / half
			# Feathered teardrop splash puff (slightly elongated along Y).
			var r := sqrt(nx * nx * 1.35 + ny * ny * 0.92)
			var alpha := pow(clampf(1.0 - r, 0.0, 1.0), 1.55)
			var bright := lerpf(0.88, 1.0, alpha)
			img.set_pixel(x, y, Color(bright, bright, 1.0, alpha))
	return ImageTexture.create_from_image(img)


func _spawn_leaping_fish(species: Dictionary, start_pos: Vector3, target_pos: Vector3) -> void:
	_clear_leaping_fish()
	var species_id: StringName = StringName(species.get("id", &"azure_snapper"))
	var pal := _get_species_palette(species_id)

	_fish_body_mat = StandardMaterial3D.new()
	_fish_body_mat.vertex_color_use_as_albedo = true
	_fish_body_mat.vertex_color_is_srgb = true
	_fish_body_mat.roughness = 0.22
	_fish_body_mat.metallic = 0.14
	_fish_body_mat.clearcoat_enabled = true
	_fish_body_mat.clearcoat = 0.75
	_fish_body_mat.clearcoat_roughness = 0.16
	var em_col: Color = pal["emission"]
	if em_col.r > 0.01 or em_col.g > 0.01 or em_col.b > 0.01:
		_fish_body_mat.emission_enabled = true
		_fish_body_mat.emission = em_col
		_fish_body_mat.emission_energy_multiplier = float(pal["emission_energy"])

	_fish_eye_mat = StandardMaterial3D.new()
	_fish_eye_mat.vertex_color_use_as_albedo = true
	_fish_eye_mat.vertex_color_is_srgb = true
	_fish_eye_mat.roughness = 0.06
	_fish_eye_mat.metallic = 0.18
	_fish_eye_mat.clearcoat_enabled = true
	_fish_eye_mat.clearcoat = 1.0
	_fish_eye_mat.clearcoat_roughness = 0.05

	var fish_mesh := _build_fish_mesh(pal)
	_leaping_fish = MeshInstance3D.new()
	_leaping_fish.name = "LeapingCatchFish"
	_leaping_fish.mesh = fish_mesh
	_leaping_fish.set_surface_override_material(0, _fish_body_mat)
	if fish_mesh.get_surface_count() > 1:
		_leaping_fish.set_surface_override_material(1, _fish_eye_mat)
	_leaping_fish.top_level = true
	add_child(_leaping_fish)

	_leap_start = start_pos
	_leap_end = target_pos
	_leap_base_scale = pal["scale"]
	_leap_elapsed = 0.0
	_leap_active = true
	_update_leaping_fish_pose(0.0)


func _tick_leaping_fish(delta: float) -> void:
	if not _leap_active:
		return
	_leap_elapsed += delta
	if _leap_elapsed >= LEAP_DURATION:
		_clear_leaping_fish()
		return
	_update_leaping_fish_pose(clampf(_leap_elapsed / LEAP_DURATION, 0.0, 1.0))


func _update_leaping_fish_pose(u: float) -> void:
	if _leaping_fish == null or not is_instance_valid(_leaping_fish):
		return
	var arc_h := 2.15
	var pos := _leap_start.lerp(_leap_end, u)
	pos.y += sin(u * PI) * arc_h

	# Compute flight tangent so the sculpted fish leaps nose-first along the parabola.
	var vel := (_leap_end - _leap_start)
	vel.y += cos(u * PI) * PI * arc_h
	var fwd := vel.normalized() if vel.length_squared() > 0.0001 else Vector3.UP
	var ref_up := Vector3.UP if absf(fwd.dot(Vector3.UP)) < 0.92 else Vector3.RIGHT
	var right := fwd.cross(ref_up).normalized()
	var up := right.cross(fwd).normalized()
	var arc_basis := Basis(right, up, -fwd)

	# Joyful mid-air tail flop and barrel shimmer.
	var wiggle := Basis.from_euler(Vector3(0.0, sin(_leap_elapsed * 28.0) * 0.34, sin(_leap_elapsed * 16.0) * 0.24))
	var pop := smoothstep(0.0, 0.10, u) * (1.0 - smoothstep(0.86, 1.0, u))
	var s := _leap_base_scale * maxf(pop, 0.12)
	_leaping_fish.global_transform = Transform3D((arc_basis * wiggle).scaled(s), pos)


func _clear_leaping_fish() -> void:
	_leap_active = false
	_leap_elapsed = 0.0
	if _leaping_fish != null and is_instance_valid(_leaping_fish):
		if _leaping_fish.mesh != null:
			for surf_i in _leaping_fish.mesh.get_surface_count():
				_leaping_fish.set_surface_override_material(surf_i, null)
		_leaping_fish.mesh = null
		_leaping_fish.material_override = null
		if _leaping_fish.get_parent() == self:
			remove_child(_leaping_fish)
		_leaping_fish.queue_free()
	_leaping_fish = null
	_fish_body_mat = null
	_fish_eye_mat = null


static func _get_species_palette(species_id: StringName) -> Dictionary:
	match species_id:
		&"gilded_mackerel":
			return {
				"dorsal": Color(0.92, 0.64, 0.14),
				"flank": Color(1.00, 0.82, 0.28),
				"belly": Color(0.98, 0.93, 0.76),
				"fin": Color(0.95, 0.56, 0.12),
				"emission": Color.BLACK,
				"emission_energy": 0.0,
				"scale": Vector3(0.94, 0.92, 1.12),
			}
		&"reef_grouper":
			return {
				"dorsal": Color(0.86, 0.20, 0.18),
				"flank": Color(0.96, 0.42, 0.26),
				"belly": Color(0.98, 0.82, 0.72),
				"fin": Color(0.76, 0.16, 0.18),
				"emission": Color.BLACK,
				"emission_energy": 0.0,
				"scale": Vector3(1.18, 1.16, 1.06),
			}
		&"lantern_fin":
			return {
				"dorsal": Color(0.08, 0.72, 0.82),
				"flank": Color(0.26, 0.98, 0.94),
				"belly": Color(0.74, 0.98, 0.96),
				"fin": Color(0.34, 1.00, 0.95),
				"emission": Color(0.16, 0.88, 0.86),
				"emission_energy": 1.15,
				"scale": Vector3(1.02, 1.04, 1.04),
			}
		&"storm_eel":
			return {
				"dorsal": Color(0.32, 0.16, 0.82),
				"flank": Color(0.56, 0.34, 0.98),
				"belly": Color(0.78, 0.72, 0.98),
				"fin": Color(0.46, 0.68, 1.00),
				"emission": Color(0.42, 0.24, 0.96),
				"emission_energy": 0.95,
				"scale": Vector3(0.78, 0.82, 1.46),
			}
		_:
			# Default: azure_snapper.
			return {
				"dorsal": Color(0.10, 0.48, 0.88),
				"flank": Color(0.24, 0.74, 0.94),
				"belly": Color(0.88, 0.94, 0.96),
				"fin": Color(0.18, 0.62, 0.96),
				"emission": Color.BLACK,
				"emission_energy": 0.0,
				"scale": Vector3(1.0, 1.0, 1.0),
			}


static func _build_fish_mesh(pal: Dictionary) -> ArrayMesh:
	var c_dorsal: Color = pal["dorsal"]
	var c_flank: Color = pal["flank"]
	var c_belly: Color = pal["belly"]
	var c_fin: Color = pal["fin"]

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Streamlined curved fusiform body (-Z nose -> +Z tail peduncle).
	# Each station: [z, rx, ry, y_center, x_curve]
	var stations: Array[Array] = [
		[-0.26, 0.000, 0.000, 0.004, 0.012],
		[-0.21, 0.032, 0.044, 0.002, 0.018],
		[-0.14, 0.054, 0.078, 0.000, 0.014],
		[-0.05, 0.064, 0.096, 0.000, 0.002],
		[0.04, 0.056, 0.084, 0.000, -0.012],
		[0.12, 0.036, 0.054, 0.000, -0.018],
		[0.18, 0.016, 0.026, 0.000, -0.014],
		[0.21, 0.008, 0.015, 0.000, -0.008],
	]
	var rad_segs := 10
	for j in range(stations.size() - 1):
		var s0: Array = stations[j]
		var s1: Array = stations[j + 1]
		var z0 := float(s0[0])
		var rx0 := float(s0[1])
		var ry0 := float(s0[2])
		var yc0 := float(s0[3])
		var xc0 := float(s0[4])
		var z1 := float(s1[0])
		var rx1 := float(s1[1])
		var ry1 := float(s1[2])
		var yc1 := float(s1[3])
		var xc1 := float(s1[4])
		var c_ref := Vector3((xc0 + xc1) * 0.5, (yc0 + yc1) * 0.5, (z0 + z1) * 0.5)

		for k in rad_segs:
			var a0 := float(k) / float(rad_segs) * TAU
			var a1 := float(k + 1) / float(rad_segs) * TAU
			var p00 := Vector3(xc0 + cos(a0) * rx0, yc0 + sin(a0) * ry0, z0)
			var p01 := Vector3(xc0 + cos(a1) * rx0, yc0 + sin(a1) * ry0, z0)
			var p10 := Vector3(xc1 + cos(a0) * rx1, yc1 + sin(a0) * ry1, z1)
			var p11 := Vector3(xc1 + cos(a1) * rx1, yc1 + sin(a1) * ry1, z1)
			var col0 := _fish_ring_color(sin(a0), c_dorsal, c_flank, c_belly)
			var col1 := _fish_ring_color(sin(a1), c_dorsal, c_flank, c_belly)
			if rx0 <= 1e-5:
				_emit_outward_tri(st, p00, col0, p10, col0, p11, col1, c_ref)
			elif rx1 <= 1e-5:
				_emit_outward_tri(st, p00, col0, p01, col1, p10, col0, c_ref)
			else:
				_emit_outward_tri(st, p00, col0, p10, col0, p11, col1, c_ref)
				_emit_outward_tri(st, p00, col0, p11, col1, p01, col1, c_ref)

	# Swept dorsal fin along the spine.
	_append_fin_blade(
		st,
		Vector3(0.008, 0.080, -0.10),
		Vector3(-0.012, 0.056, 0.11),
		Vector3(-0.016, 0.145, 0.14),
		Vector3(0.002, 0.158, -0.02),
		0.008,
		c_dorsal,
		c_fin
	)

	# Sculpted forked tail fin (upper & lower swept lobes meeting at a central V-notch).
	var tail_x := -0.008
	var tail_root_top := Vector3(tail_x, 0.016, 0.19)
	var tail_root_mid := Vector3(tail_x, 0.000, 0.20)
	var tail_root_bot := Vector3(tail_x, -0.016, 0.19)
	var tail_notch := Vector3(tail_x + 0.008, 0.000, 0.265)
	var tail_upper := Vector3(tail_x + 0.014, 0.112, 0.345)
	var tail_lower := Vector3(tail_x + 0.014, -0.104, 0.335)
	_append_fin_blade(st, tail_root_top, tail_root_mid, tail_notch, tail_upper, 0.007, c_dorsal, c_fin)
	_append_fin_blade(st, tail_root_mid, tail_root_bot, tail_lower, tail_notch, 0.007, c_flank, c_fin)

	# Flared left & right pectoral fins.
	for sg: float in [-1.0, 1.0]:
		var root_a := Vector3(0.008 + sg * 0.048, -0.024, -0.11)
		var root_b := Vector3(0.004 + sg * 0.050, -0.042, -0.04)
		var tip_a := Vector3(0.008 + sg * 0.122, -0.055, -0.02)
		var tip_b := Vector3(0.004 + sg * 0.105, -0.072, 0.04)
		_append_fin_blade(st, root_a, root_b, tip_b, tip_a, 0.005, c_flank, c_fin)

	st.generate_normals()
	var mesh := st.commit()

	# Surface 1: bright glossy stylized eyes (warm ivory-gold sclera + jet-black glossy pupil).
	var eye_st := SurfaceTool.new()
	eye_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var eye_iris_col := Color(0.98, 0.90, 0.56)
	var eye_pupil_col := Color(0.04, 0.05, 0.07)
	for sg: float in [-1.0, 1.0]:
		var ec := Vector3(0.016 + sg * 0.036, 0.026, -0.168)
		var out_dir := Vector3(sg * 0.88, 0.18, -0.44).normalized()
		_append_eye_dome(eye_st, ec, out_dir, 0.017, 0.010, eye_iris_col, eye_pupil_col)
	eye_st.generate_normals()
	eye_st.commit(mesh)
	return mesh


static func _fish_ring_color(sin_a: float, dorsal: Color, flank: Color, belly: Color) -> Color:
	if sin_a >= 0.0:
		return flank.lerp(dorsal, clampf(sin_a * 1.25, 0.0, 1.0))
	return flank.lerp(belly, clampf(-sin_a * 1.35, 0.0, 1.0))


static func _append_fin_blade(st: SurfaceTool, r0: Vector3, r1: Vector3, t1: Vector3, t0: Vector3,
		half_thick: float, root_col: Color, tip_col: Color) -> void:
	var n := (t0 - r0).cross(r1 - r0)
	if n.length_squared() < 1e-8:
		n = Vector3.RIGHT
	else:
		n = n.normalized()
	var off := n * half_thick
	var tip_off := n * (half_thick * 0.25)
	var center := (r0 + r1 + t0 + t1) * 0.25

	var r0p := r0 + off
	var r1p := r1 + off
	var t1p := t1 + tip_off
	var t0p := t0 + tip_off
	var r0n := r0 - off
	var r1n := r1 - off
	var t1n := t1 - tip_off
	var t0n := t0 - tip_off

	# Both flanks + outer fin rim.
	_emit_outward_tri(st, r0p, root_col, r1p, root_col, t1p, tip_col, center)
	_emit_outward_tri(st, r0p, root_col, t1p, tip_col, t0p, tip_col, center)
	_emit_outward_tri(st, r0n, root_col, r1n, root_col, t1n, tip_col, center)
	_emit_outward_tri(st, r0n, root_col, t1n, tip_col, t0n, tip_col, center)
	_emit_outward_tri(st, t0p, tip_col, t1p, tip_col, t1n, tip_col, center)
	_emit_outward_tri(st, t0p, tip_col, t1n, tip_col, t0n, tip_col, center)
	_emit_outward_tri(st, r0p, root_col, t0p, tip_col, t0n, tip_col, center)
	_emit_outward_tri(st, r0p, root_col, t0n, tip_col, r0n, root_col, center)


static func _append_eye_dome(st: SurfaceTool, center: Vector3, out_dir: Vector3,
		iris_r: float, pupil_r: float, iris_col: Color, pupil_col: Color) -> void:
	var n := out_dir.normalized()
	var ref := Vector3.UP if absf(n.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT
	var bx := n.cross(ref).normalized()
	var by := n.cross(bx).normalized()
	var segs := 8
	var iris_apex := center + n * (iris_r * 0.55)
	var pupil_apex := center + n * (iris_r * 0.78)
	var ref_in := center - n * 0.02

	for k in segs:
		var a0 := float(k) / float(segs) * TAU
		var a1 := float(k + 1) / float(segs) * TAU
		var d0 := bx * cos(a0) + by * sin(a0)
		var d1 := bx * cos(a1) + by * sin(a1)
		var ir0 := center + d0 * iris_r
		var ir1 := center + d1 * iris_r
		var pr0 := iris_apex + d0 * pupil_r
		var pr1 := iris_apex + d1 * pupil_r
		_emit_outward_tri(st, ir0, iris_col, ir1, iris_col, pr1, iris_col, ref_in)
		_emit_outward_tri(st, ir0, iris_col, pr1, iris_col, pr0, iris_col, ref_in)
		_emit_outward_tri(st, pr0, pupil_col, pr1, pupil_col, pupil_apex, pupil_col, ref_in)


# ==============================================================================
# Procedural Faceted `SurfaceTool` Geometry Helpers (`set_smooth_group(-1)`)
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


static func _append_lathe_y(st: SurfaceTool, rings: Array[Array], segs: int,
		offset: Vector3 = Vector3.ZERO) -> void:
	for j in range(rings.size() - 1):
		var y0 := float(rings[j][0])
		var r0 := float(rings[j][1])
		var c0: Color = rings[j][2]
		var y1 := float(rings[j + 1][0])
		var r1 := float(rings[j + 1][1])
		var c1: Color = rings[j + 1][2]
		for k in segs:
			var a0 := float(k) / float(segs) * TAU
			var a1 := float(k + 1) / float(segs) * TAU
			var p00 := offset + Vector3(cos(a0) * r0, y0, sin(a0) * r0)
			var p01 := offset + Vector3(cos(a1) * r0, y0, sin(a1) * r0)
			var p10 := offset + Vector3(cos(a0) * r1, y1, sin(a0) * r1)
			var p11 := offset + Vector3(cos(a1) * r1, y1, sin(a1) * r1)
			if r0 > 1e-5 and r1 > 1e-5:
				_emit_flat_tri(st, p00, c0, p11, c1, p10, c1)
				_emit_flat_tri(st, p00, c0, p01, c0, p11, c1)
			elif r1 > 1e-5:
				_emit_flat_tri(st, p00, c0, p11, c1, p10, c1)
			elif r0 > 1e-5:
				_emit_flat_tri(st, p00, c0, p01, c0, p11, c1)


static func _append_lathe_neg_z(st: SurfaceTool, rings: Array[Array], segs: int,
		offset: Vector3 = Vector3.ZERO) -> void:
	for j in range(rings.size() - 1):
		var d0 := float(rings[j][0])
		var r0 := float(rings[j][1])
		var c0: Color = rings[j][2]
		var d1 := float(rings[j + 1][0])
		var r1 := float(rings[j + 1][1])
		var c1: Color = rings[j + 1][2]
		for k in segs:
			var a0 := float(k) / float(segs) * TAU
			var a1 := float(k + 1) / float(segs) * TAU
			var p00 := offset + Vector3(cos(a0) * r0, sin(a0) * r0, -d0)
			var p01 := offset + Vector3(cos(a1) * r0, sin(a1) * r0, -d0)
			var p10 := offset + Vector3(cos(a0) * r1, sin(a0) * r1, -d1)
			var p11 := offset + Vector3(cos(a1) * r1, sin(a1) * r1, -d1)
			if r0 > 1e-5 and r1 > 1e-5:
				_emit_flat_tri(st, p00, c0, p11, c1, p10, c1)
				_emit_flat_tri(st, p00, c0, p01, c0, p11, c1)
			elif r1 > 1e-5:
				_emit_flat_tri(st, p00, c0, p11, c1, p10, c1)
			elif r0 > 1e-5:
				_emit_flat_tri(st, p00, c0, p01, c0, p11, c1)


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


static func _append_torus_ring(st: SurfaceTool, center: Vector3, normal_axis: Vector3,
		major_r: float, minor_r: float, major_segs: int, minor_segs: int, col: Color) -> void:
	var n := normal_axis.normalized()
	var ref := Vector3.UP if absf(n.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT
	var bx := n.cross(ref).normalized()
	var by := n.cross(bx).normalized()
	for i in major_segs:
		var u0 := float(i) / float(major_segs) * TAU
		var u1 := float(i + 1) / float(major_segs) * TAU
		var r_u0 := bx * cos(u0) + by * sin(u0)
		var r_u1 := bx * cos(u1) + by * sin(u1)
		var tc0 := center + r_u0 * major_r
		var tc1 := center + r_u1 * major_r
		var tube_mid := (tc0 + tc1) * 0.5
		for j in minor_segs:
			var v0 := float(j) / float(minor_segs) * TAU
			var v1 := float(j + 1) / float(minor_segs) * TAU
			var p00 := tc0 + (r_u0 * cos(v0) + n * sin(v0)) * minor_r
			var p01 := tc0 + (r_u0 * cos(v1) + n * sin(v1)) * minor_r
			var p10 := tc1 + (r_u1 * cos(v0) + n * sin(v0)) * minor_r
			var p11 := tc1 + (r_u1 * cos(v1) + n * sin(v1)) * minor_r
			_emit_outward_tri(st, p00, col, p10, col, p11, col, tube_mid)
			_emit_outward_tri(st, p00, col, p11, col, p01, col, tube_mid)

