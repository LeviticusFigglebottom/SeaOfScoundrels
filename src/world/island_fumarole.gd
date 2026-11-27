class_name VolcanicFumarole
extends Node3D
## Dynamic active volcanic steam-vent chimney with sculpted dark basalt-obsidian
## crags, incandescent sulfur-orange inner vent throat, periodic pressurized
## steam/ash & glowing ember eruptions, shadowless flickering glow, and 190 m culling.

const CULL_DIST := 190.0
const ERUPTION_DURATION := 2.0

# Sculpted basalt-obsidian & molten volcanic sulfur palette (authored in sRGB).
const COL_BASALT_HI := Color(0.24, 0.22, 0.23)
const COL_BASALT_MID := Color(0.14, 0.13, 0.15)
const COL_BASALT_LO := Color(0.075, 0.070, 0.085)
const COL_SULFUR_CRUST := Color(0.68, 0.56, 0.16)
const COL_MAGMA_CORE := Color(1.00, 0.62, 0.14)
const COL_MAGMA_EDGE := Color(0.92, 0.28, 0.05)
const COL_HALO_CORE := Color(1.00, 0.68, 0.16, 1.0)
const COL_HALO_MID := Color(0.86, 0.30, 0.05, 1.0)
const COL_HALO_RIM := Color(0.0, 0.0, 0.0, 1.0)

# Statically cached procedural ArrayMeshes, materials & spray texture shared across fumaroles.
static var _active_fumaroles: int = 0
static var _chimney_mesh: ArrayMesh = null
static var _magma_halo_mesh: ArrayMesh = null
static var _rock_mat: StandardMaterial3D = null
static var _throat_mat: StandardMaterial3D = null
static var _steam_tex: ImageTexture = null
static var _steam_mat: StandardMaterial3D = null
static var _steam_card_mesh: ArrayMesh = null
static var _ember_diamond_mesh: ArrayMesh = null
static var _ember_mat: StandardMaterial3D = null

@export var vent_scale: float = 1.0
@export var phase_seed: float = 0.0
@export var enable_effects: bool = true

var chimney_mi: MeshInstance3D = null
var vent_magma_halo: MeshInstance3D = null
var steam_plume: GPUParticles3D = null
var ember_sparks: GPUParticles3D = null
var vent_light: OmniLight3D = null

var _magma_halo_mat: StandardMaterial3D = null
var _magma_halo_energy: float = 0.0
var _cycle_period: float = 6.8
var _cycle_clock: float = 0.0
var _eruption_remaining: float = 0.0
var _glow_clock: float = 0.0
var _distance_active: bool = true
var _tri_count: int = 0


## Create a configured volcanic fumarole with scale `p_vent_scale` and deterministic `p_phase_seed`.
static func create(p_vent_scale: float = 1.0, p_phase_seed: float = 0.0) -> VolcanicFumarole:
	var vf := VolcanicFumarole.new()
	vf.name = "VolcanicFumarole"
	vf.vent_scale = clampf(p_vent_scale, 0.45, 3.0)
	vf.phase_seed = p_phase_seed
	return vf


## Release all statically cached fumarole chimney, halo, steam & ember assets cleanly.
static func clear_shared_cache() -> void:
	if _steam_mat != null:
		_steam_mat.albedo_texture = null
	_chimney_mesh = null
	_magma_halo_mesh = null
	_rock_mat = null
	_throat_mat = null
	_steam_tex = null
	_steam_mat = null
	_steam_card_mesh = null
	_ember_diamond_mesh = null
	_ember_mat = null


func _enter_tree() -> void:
	_active_fumaroles += 1
	add_to_group(&"volcanic_fumaroles")


func _ready() -> void:
	_ensure_shared_assets()
	# Deterministic period in 5.5..8.5 s and staggered initial phase from phase_seed.
	var s_frac := fposmod(absf(phase_seed * 1.6180339), 1.0)
	_cycle_period = lerpf(5.5, 8.5, s_frac)
	_cycle_clock = fposmod(absf(phase_seed * 2.7182818), _cycle_period * 0.85)
	scale = Vector3.ONE * vent_scale

	chimney_mi = MeshInstance3D.new()
	chimney_mi.name = "FumaroleChimney"
	chimney_mi.mesh = _chimney_mesh
	chimney_mi.set_surface_override_material(0, _rock_mat)
	if _chimney_mesh.get_surface_count() > 1:
		chimney_mi.set_surface_override_material(1, _throat_mat)
	chimney_mi.visibility_range_end = CULL_DIST + 100.0
	add_child(chimney_mi)
	_tri_count = _count_mesh_tris(_chimney_mesh)

	vent_light = OmniLight3D.new()
	vent_light.name = "VentLight"
	vent_light.position = Vector3(0.0, 1.38, 0.0)
	vent_light.light_color = Color(1.0, 0.48, 0.12)
	vent_light.light_energy = 1.05
	vent_light.omni_range = 10.0
	vent_light.omni_attenuation = 1.35
	vent_light.shadow_enabled = false
	add_child(vent_light)

	# Additive 16-wedge radial-gradient billboard magma glow halo hovering right over the sulfur throat.
	_magma_halo_mat = StandardMaterial3D.new()
	_magma_halo_mat.vertex_color_use_as_albedo = true
	_magma_halo_mat.vertex_color_is_srgb = true
	_magma_halo_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_magma_halo_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_magma_halo_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_magma_halo_mat.billboard_keep_scale = true
	_magma_halo_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	_magma_halo_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_magma_halo_mat.albedo_color = Color(0.42, 0.42, 0.42, 1.0)

	vent_magma_halo = MeshInstance3D.new()
	vent_magma_halo.name = "VentMagmaHalo"
	vent_magma_halo.mesh = _magma_halo_mesh
	vent_magma_halo.material_override = _magma_halo_mat
	vent_magma_halo.position = Vector3(0.0, 1.32, 0.0)
	vent_magma_halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	vent_magma_halo.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	vent_magma_halo.visibility_range_end = CULL_DIST + 40.0
	add_child(vent_magma_halo)

	if enable_effects:
		steam_plume = _build_steam_plume()
		steam_plume.position = Vector3(0.0, 1.28, 0.0)
		add_child(steam_plume)

		ember_sparks = _build_ember_sparks()
		ember_sparks.position = Vector3(0.0, 1.24, 0.0)
		add_child(ember_sparks)

	_apply_vent_state()


func _exit_tree() -> void:
	if chimney_mi != null and is_instance_valid(chimney_mi):
		if chimney_mi.mesh != null:
			for si in chimney_mi.mesh.get_surface_count():
				chimney_mi.set_surface_override_material(si, null)
		chimney_mi.mesh = null
		chimney_mi.material_override = null
	if vent_magma_halo != null and is_instance_valid(vent_magma_halo):
		vent_magma_halo.material_override = null
		vent_magma_halo.mesh = null
	for gp: GPUParticles3D in [steam_plume, ember_sparks]:
		if gp != null and is_instance_valid(gp):
			gp.emitting = false
			gp.visible = false
			var pm := gp.process_material as ParticleProcessMaterial
			if pm != null:
				pm.color_ramp = null
			gp.material_override = null
			gp.draw_pass_1 = null
			gp.process_material = null
	chimney_mi = null
	vent_magma_halo = null
	_magma_halo_mat = null
	_magma_halo_energy = 0.0
	steam_plume = null
	ember_sparks = null
	vent_light = null
	_active_fumaroles = maxi(0, _active_fumaroles - 1)
	if _active_fumaroles == 0:
		clear_shared_cache()


func _process(delta: float) -> void:
	var vp := get_viewport()
	var cam := vp.get_camera_3d() if vp != null else null
	if cam != null:
		var in_range := cam.global_position.distance_squared_to(global_position) <= CULL_DIST * CULL_DIST
		if in_range != _distance_active:
			set_distance_active(in_range)
	if not _distance_active:
		return
	step_fumarole(delta)


## Advance the periodic volcanic geyser cycle by `delta` seconds (deterministic for tests & gameplay).
func step_fumarole(delta: float) -> void:
	var dt := maxf(0.0, delta)
	_glow_clock += dt
	if _eruption_remaining > 0.0:
		_eruption_remaining = maxf(0.0, _eruption_remaining - dt)
	_cycle_clock += dt
	if _cycle_clock >= _cycle_period:
		_cycle_clock = fposmod(_cycle_clock, _cycle_period)
		trigger_eruption_pulse()
	_apply_vent_state()


## Trigger a pressurized 2.0-second volcanic steam, ash, ember & vent-glow eruption burst.
func trigger_eruption_pulse() -> void:
	_eruption_remaining = ERUPTION_DURATION
	_apply_vent_state()


## True while the fumarole is actively surging through a pressurized eruption pulse.
func is_erupting() -> bool:
	return _eruption_remaining > 0.0


## Return sculpted triangle count of the fumarole chimney mesh.
func get_triangle_count() -> int:
	return _tri_count


## Return the sculpted additive billboard VentMagmaHalo MeshInstance3D.
func get_magma_halo_node() -> MeshInstance3D:
	return vent_magma_halo


## Return the active additive magma halo intensity (0.0 when distance-culled).
func get_magma_halo_energy() -> float:
	return _magma_halo_energy


## Toggle particle emitters, magma halo, and light cleanly for 190 m distance culling or tests.
func set_distance_active(active: bool) -> void:
	_distance_active = active
	_apply_vent_state()


func _apply_vent_state() -> void:
	var erupting := is_erupting()
	var active := _distance_active
	var surge := smoothstep(0.0, 0.35, _eruption_remaining) * smoothstep(ERUPTION_DURATION, ERUPTION_DURATION - 0.18, _eruption_remaining) if erupting else 0.0
	if erupting and _eruption_remaining >= ERUPTION_DURATION - 0.18:
		surge = 1.0
	var flicker := sin(_glow_clock * 7.4) * 0.14 + cos(_glow_clock * 15.2) * 0.08

	if vent_light != null and is_instance_valid(vent_light):
		vent_light.visible = active
		if active:
			var base_e := lerpf(1.05, 3.35, surge)
			vent_light.light_energy = maxf(0.4, base_e + flicker * (1.0 + surge * 1.4))

	if vent_magma_halo != null and is_instance_valid(vent_magma_halo):
		vent_magma_halo.visible = active
		if active:
			var night := clampf(1.0 - (Weather.daylight() if Weather != null else 1.0), 0.0, 1.0)
			var base_h := lerpf(0.42, 1.25, surge)
			var night_mul := lerpf(1.0, 1.48, night)
			var pulse_mul := 1.0 + flicker * (0.28 + surge * 0.25)
			_magma_halo_energy = maxf(0.18, base_h * night_mul * pulse_mul)
			var halo_s := lerpf(1.0, 1.48, surge) * lerpf(1.0, 1.16, night) * (1.0 + flicker * 0.14)
			vent_magma_halo.scale = Vector3(halo_s, halo_s, halo_s)
			if _magma_halo_mat != null:
				var warm := Color(1.0, 0.94, 0.86).lerp(Color(1.0, 0.82, 0.58), clampf(night * 0.75 + surge * 0.45, 0.0, 1.0))
				_magma_halo_mat.albedo_color = Color(
					warm.r * _magma_halo_energy,
					warm.g * _magma_halo_energy,
					warm.b * _magma_halo_energy,
					1.0
				)
		else:
			_magma_halo_energy = 0.0

	if steam_plume != null and is_instance_valid(steam_plume):
		steam_plume.visible = active and enable_effects
		steam_plume.emitting = active and enable_effects
		steam_plume.amount_ratio = 1.0 if erupting else 0.28
		var spm := steam_plume.process_material as ParticleProcessMaterial
		if spm != null:
			spm.initial_velocity_min = 4.2 if erupting else 1.2
			spm.initial_velocity_max = 7.6 if erupting else 2.4

	if ember_sparks != null and is_instance_valid(ember_sparks):
		var show_embers := active and enable_effects and erupting
		ember_sparks.visible = show_embers
		ember_sparks.emitting = show_embers


# ==============================================================================
# Particle Emitters & Sculpted Zero-Primitive Volcanic Chimney Builders
# ==============================================================================

func _build_steam_plume() -> GPUParticles3D:
	var proc := ParticleProcessMaterial.new()
	proc.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	proc.emission_sphere_radius = 0.28
	proc.direction = Vector3.UP
	proc.spread = 18.0
	proc.initial_velocity_min = 1.2
	proc.initial_velocity_max = 2.4
	proc.gravity = Vector3(0.0, 0.45, 0.0)
	proc.damping_min = 0.45
	proc.damping_max = 0.90
	proc.scale_min = 0.95
	proc.scale_max = 2.65

	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.18, 0.65, 1.0])
	grad.colors = PackedColorArray([
		Color(0.55, 0.44, 0.36, 0.0),
		Color(0.48, 0.42, 0.38, 0.56),
		Color(0.32, 0.30, 0.32, 0.32),
		Color(0.24, 0.24, 0.26, 0.0),
	])
	var ramp := GradientTexture1D.new()
	ramp.width = 16
	ramp.gradient = grad
	proc.color_ramp = ramp

	var gp := GPUParticles3D.new()
	gp.name = "SteamPlume"
	gp.amount = 22
	gp.lifetime = 2.35
	gp.local_coords = false
	gp.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD
	gp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	gp.visibility_aabb = AABB(Vector3(-5.0, -1.0, -5.0), Vector3(10.0, 14.0, 10.0))
	gp.process_material = proc
	gp.draw_pass_1 = _steam_card_mesh
	gp.material_override = _steam_mat
	gp.emitting = _distance_active
	gp.visible = _distance_active
	return gp


func _build_ember_sparks() -> GPUParticles3D:
	var proc := ParticleProcessMaterial.new()
	proc.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	proc.emission_sphere_radius = 0.22
	proc.direction = Vector3.UP
	proc.spread = 28.0
	proc.initial_velocity_min = 4.6
	proc.initial_velocity_max = 9.2
	proc.angular_velocity_min = -9.0
	proc.angular_velocity_max = 9.0
	proc.gravity = Vector3(0.0, -6.5, 0.0)
	proc.scale_min = 0.65
	proc.scale_max = 1.45

	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.20, 0.78, 1.0])
	grad.colors = PackedColorArray([
		Color(1.0, 0.92, 0.55, 1.0),
		Color(1.0, 0.58, 0.14, 1.0),
		Color(0.92, 0.22, 0.04, 0.85),
		Color(0.35, 0.06, 0.02, 0.0),
	])
	var ramp := GradientTexture1D.new()
	ramp.width = 16
	ramp.gradient = grad
	proc.color_ramp = ramp

	var gp := GPUParticles3D.new()
	gp.name = "EmberSparks"
	gp.amount = 18
	gp.lifetime = 1.45
	gp.local_coords = false
	gp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	gp.visibility_aabb = AABB(Vector3(-6.0, -1.0, -6.0), Vector3(12.0, 12.0, 12.0))
	gp.process_material = proc
	gp.draw_pass_1 = _ember_diamond_mesh
	gp.material_override = _ember_mat
	gp.emitting = false
	gp.visible = false
	return gp


static func _ensure_shared_assets() -> void:
	if _rock_mat == null:
		_rock_mat = StandardMaterial3D.new()
		_rock_mat.vertex_color_use_as_albedo = true
		_rock_mat.vertex_color_is_srgb = true
		_rock_mat.roughness = 0.90
		_rock_mat.metallic = 0.06

	if _throat_mat == null:
		_throat_mat = StandardMaterial3D.new()
		_throat_mat.vertex_color_use_as_albedo = true
		_throat_mat.vertex_color_is_srgb = true
		_throat_mat.roughness = 0.45
		_throat_mat.emission_enabled = true
		_throat_mat.emission = Color(1.0, 0.42, 0.08)
		_throat_mat.emission_energy_multiplier = 2.4

	if _steam_tex == null:
		_steam_tex = _make_soft_steam_texture()
	if _steam_mat == null:
		_steam_mat = StandardMaterial3D.new()
		_steam_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_steam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_steam_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		_steam_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_steam_mat.vertex_color_use_as_albedo = true
		_steam_mat.albedo_texture = _steam_tex
	if _steam_card_mesh == null:
		_steam_card_mesh = _build_billboard_card_mesh(1.0)

	if _ember_mat == null:
		_ember_mat = StandardMaterial3D.new()
		_ember_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_ember_mat.vertex_color_use_as_albedo = true
		_ember_mat.vertex_color_is_srgb = true
		_ember_mat.emission_enabled = true
		_ember_mat.emission = Color(1.0, 0.56, 0.14)
		_ember_mat.emission_energy_multiplier = 3.2
	if _ember_diamond_mesh == null:
		_ember_diamond_mesh = _build_ember_diamond_mesh()

	if _chimney_mesh == null:
		_chimney_mesh = _build_chimney_mesh()
	if _magma_halo_mesh == null:
		_magma_halo_mesh = _build_magma_halo_mesh()


static func _build_magma_halo_mesh() -> ArrayMesh:
	# Sculpted 48-tri 16-wedge radial-gradient billboard magma glow halo disc (zero primitives, unit +Z normals).
	# Incandescent sulfur-amber core -> molten orange mid-ring -> Color(0, 0, 0, 1) rim for seamless additive blend.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	const WEDGES := 16
	const INNER_R := 0.42
	const OUTER_R := 1.05
	var n := Vector3(0.0, 0.0, 1.0)
	var ctr := Vector3.ZERO
	for i in WEDGES:
		var a0 := TAU * float(i) / float(WEDGES)
		var a1 := TAU * float(i + 1) / float(WEDGES)
		var m0 := Vector3(cos(a0) * INNER_R, sin(a0) * INNER_R, 0.0)
		var m1 := Vector3(cos(a1) * INNER_R, sin(a1) * INNER_R, 0.0)
		var o0 := Vector3(cos(a0) * OUTER_R, sin(a0) * OUTER_R, 0.0)
		var o1 := Vector3(cos(a1) * OUTER_R, sin(a1) * OUTER_R, 0.0)

		st.set_normal(n)
		st.set_color(COL_HALO_CORE)
		st.add_vertex(ctr)
		st.set_normal(n)
		st.set_color(COL_HALO_MID)
		st.add_vertex(m1)
		st.set_normal(n)
		st.set_color(COL_HALO_MID)
		st.add_vertex(m0)

		st.set_normal(n)
		st.set_color(COL_HALO_MID)
		st.add_vertex(m0)
		st.set_normal(n)
		st.set_color(COL_HALO_MID)
		st.add_vertex(m1)
		st.set_normal(n)
		st.set_color(COL_HALO_RIM)
		st.add_vertex(o1)

		st.set_normal(n)
		st.set_color(COL_HALO_MID)
		st.add_vertex(m0)
		st.set_normal(n)
		st.set_color(COL_HALO_RIM)
		st.add_vertex(o1)
		st.set_normal(n)
		st.set_color(COL_HALO_RIM)
		st.add_vertex(o0)

	return st.commit()


static func _build_chimney_mesh() -> ArrayMesh:
	var rock_st := SurfaceTool.new()
	rock_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var throat_st := SurfaceTool.new()
	throat_st.begin(Mesh.PRIMITIVE_TRIANGLES)

	const SEGS := 12
	# 1. Outer jagged dark basalt-obsidian volcanic chimney cone + sulfur-crusted jagged caldera rim.
	# [y_base, r_base, jag_amp, col]
	var outer_specs: Array[Array] = [
		[-0.18, 1.18, 0.12, COL_BASALT_LO],
		[0.34, 0.94, 0.14, COL_BASALT_MID],
		[0.82, 0.72, 0.12, COL_BASALT_HI],
		[1.26, 0.54, 0.10, COL_BASALT_HI.lerp(COL_SULFUR_CRUST, 0.35)],
		[1.16, 0.36, 0.05, COL_SULFUR_CRUST],
	]
	var rings: Array[Array] = []
	var rcols: Array[Array] = []
	for ri in outer_specs.size():
		var spec: Array = outer_specs[ri]
		var y0 := float(spec[0])
		var rad := float(spec[1])
		var jag := float(spec[2])
		var base_c: Color = spec[3] as Color
		var ring: Array[Vector3] = []
		var cols: Array[Color] = []
		for k in SEGS:
			var a := float(k) / float(SEGS) * TAU
			var radial_n := 1.0 + jag * sin(a * 3.0 + float(ri) * 1.1) + (jag * 0.5) * cos(a * 5.0)
			var y_jag := (0.16 * sin(a * 3.0 + 0.5) + 0.08 * cos(a * 5.0)) if ri == 3 else 0.0
			ring.append(Vector3(cos(a) * rad * radial_n, y0 + y_jag, sin(a) * rad * radial_n))
			var sulfur_spot := ri >= 2 and (k % 3 == 0)
			cols.append(base_c.lerp(COL_SULFUR_CRUST, 0.45) if sulfur_spot else base_c)
		rings.append(ring)
		rcols.append(cols)

	for ri in range(rings.size() - 1):
		var r0: Array = rings[ri]
		var r1: Array = rings[ri + 1]
		var c0: Array = rcols[ri]
		var c1: Array = rcols[ri + 1]
		var ym := 0.5 * (float(outer_specs[ri][0]) + float(outer_specs[ri + 1][0]))
		var ref_ctr := Vector3(0.0, ym - 0.15, 0.0)
		for k in SEGS:
			var nk := (k + 1) % SEGS
			_emit_outward_quad(rock_st, r0[k] as Vector3, r1[k] as Vector3, r1[nk] as Vector3, r0[nk] as Vector3,
				ref_ctr, c0[k] as Color, c1[k] as Color, c1[nk] as Color, c0[nk] as Color)

	# 2. 6 protruding jagged obsidian crag buttress spires gripping the base of the vent!
	for si in 6:
		var ang := float(si) / 6.0 * TAU + 0.25
		var dir := Vector3(cos(ang), 0.0, sin(ang))
		var base_c := dir * 0.96 + Vector3(0.0, -0.10, 0.0)
		var peak_c := dir * 0.64 + Vector3(0.0, 0.62 + 0.22 * sin(float(si) * 2.3), 0.0)
		_append_crag_spire(rock_st, base_c, peak_c, 0.34, COL_BASALT_HI, COL_BASALT_LO)

	# 3. Incandescent molten orange-sulfur inner vent throat (Surface 1 — emissive magma glow!).
	var lip_ring: Array = rings[rings.size() - 1]
	var mid_throat: Array[Vector3] = []
	for k in SEGS:
		var a := float(k) / float(SEGS) * TAU
		mid_throat.append(Vector3(cos(a) * 0.29, 0.78, sin(a) * 0.29))
	var magma_floor := Vector3(0.0, 0.52, 0.0)
	for k in SEGS:
		var nk := (k + 1) % SEGS
		# Throat wall faces inward toward the central vent axis (0, 0.95, 0).
		_emit_inward_quad(throat_st, lip_ring[k] as Vector3, mid_throat[k], mid_throat[nk], lip_ring[nk] as Vector3,
			Vector3(0.0, 0.96, 0.0), COL_MAGMA_EDGE, COL_MAGMA_CORE, COL_MAGMA_CORE, COL_MAGMA_EDGE)
		_emit_outward_tri(throat_st, magma_floor, mid_throat[nk], mid_throat[k], Vector3(0.0, 0.10, 0.0),
			COL_MAGMA_CORE, COL_MAGMA_CORE, COL_MAGMA_CORE)

	rock_st.generate_normals()
	var mesh := rock_st.commit()
	throat_st.generate_normals()
	throat_st.commit(mesh)
	return mesh


static func _append_crag_spire(st: SurfaceTool, base_pos: Vector3, peak_pos: Vector3,
		base_r: float, col_hi: Color, col_lo: Color) -> void:
	const SIDES := 5
	var b_pts: Array[Vector3] = []
	for k in SIDES:
		var a := float(k) / float(SIDES) * TAU
		b_pts.append(base_pos + Vector3(cos(a) * base_r, 0.0, sin(a) * base_r))
	var ctr := (base_pos + peak_pos) * 0.5
	for k in SIDES:
		var nk := (k + 1) % SIDES
		_emit_outward_tri(st, peak_pos, b_pts[k], b_pts[nk], ctr, col_hi, col_lo, col_lo)


static func _build_ember_diamond_mesh() -> ArrayMesh:
	# Faceted 8-triangle glowing volcanic ember diamond shard (zero primitives!).
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var col_hot := Color(1.0, 0.92, 0.52)
	var col_mid := Color(1.0, 0.44, 0.08)
	var top := Vector3(0.0, 0.11, 0.0)
	var bot := Vector3(0.0, -0.11, 0.0)
	var ring: Array[Vector3] = [
		Vector3(0.055, 0.0, 0.0),
		Vector3(0.0, 0.0, 0.055),
		Vector3(-0.055, 0.0, 0.0),
		Vector3(0.0, 0.0, -0.055),
	]
	for k in 4:
		var nk := (k + 1) % 4
		_emit_outward_tri(st, top, ring[k], ring[nk], Vector3.ZERO, col_hot, col_mid, col_mid)
		_emit_outward_tri(st, bot, ring[nk], ring[k], Vector3.ZERO, col_mid, col_mid, col_mid)
	st.generate_normals()
	return st.commit()


static func _build_billboard_card_mesh(sz: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var h := sz * 0.5
	var p0 := Vector3(-h, h, 0.0)
	var p1 := Vector3(h, h, 0.0)
	var p2 := Vector3(h, -h, 0.0)
	var p3 := Vector3(-h, -h, 0.0)
	st.set_uv(Vector2(0.0, 0.0))
	st.add_vertex(p0)
	st.set_uv(Vector2(1.0, 0.0))
	st.add_vertex(p1)
	st.set_uv(Vector2(1.0, 1.0))
	st.add_vertex(p2)
	st.set_uv(Vector2(0.0, 0.0))
	st.add_vertex(p0)
	st.set_uv(Vector2(1.0, 1.0))
	st.add_vertex(p2)
	st.set_uv(Vector2(0.0, 1.0))
	st.add_vertex(p3)
	st.generate_normals()
	return st.commit()


static func _make_soft_steam_texture() -> ImageTexture:
	var sz := 48
	var img := Image.create(sz, sz, false, Image.FORMAT_RGBA8)
	var half := float(sz - 1) * 0.5
	for y in sz:
		for x in sz:
			var nx := (float(x) - half) / half
			var ny := (float(y) - half) / half
			var r := sqrt(nx * nx + ny * ny)
			var w := clampf(1.0 - r, 0.0, 1.0)
			var alpha := w * w * smoothstep(0.0, 0.45, w)
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha))
	return ImageTexture.create_from_image(img)


static func _emit_outward_quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3,
		ref_center: Vector3, ca: Color, cb: Color, cc: Color, cd: Color) -> void:
	_emit_outward_tri(st, a, b, c, ref_center, ca, cb, cc)
	_emit_outward_tri(st, a, c, d, ref_center, ca, cc, cd)


static func _emit_inward_quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3,
		axis_center: Vector3, ca: Color, cb: Color, cc: Color, cd: Color) -> void:
	_emit_dir_tri(st, a, b, c, axis_center - ((a + b + c) / 3.0), ca, cb, cc)
	_emit_dir_tri(st, a, c, d, axis_center - ((a + c + d) / 3.0), ca, cc, cd)


static func _emit_outward_tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3,
		ref_center: Vector3, ca: Color, cb: Color, cc: Color) -> void:
	var centroid := (a + b + c) / 3.0
	_emit_dir_tri(st, a, b, c, centroid - ref_center, ca, cb, cc)


static func _emit_dir_tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3,
		expected_normal: Vector3, ca: Color, cb: Color, cc: Color) -> void:
	var n := (c - a).cross(b - a)
	if n.length_squared() < 1e-12:
		return
	if n.dot(expected_normal) < 0.0:
		var tv := b
		b = c
		c = tv
		var tc := cb
		cb = cc
		cc = tc
	st.set_smooth_group(-1)
	st.set_color(ca)
	st.add_vertex(a)
	st.set_smooth_group(-1)
	st.set_color(cb)
	st.add_vertex(b)
	st.set_smooth_group(-1)
	st.set_color(cc)
	st.add_vertex(c)


static func _count_mesh_tris(mesh: ArrayMesh) -> int:
	if mesh == null:
		return 0
	var total := 0
	for si in mesh.get_surface_count():
		var arr := mesh.surface_get_arrays(si)
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		total += floori(float(verts.size()) / 3.0)
	return total
