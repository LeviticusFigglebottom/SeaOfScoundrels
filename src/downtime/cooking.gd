class_name CookingStove
extends Node3D
## Stylized Cast-Iron Naval Galley Hearth Stove & sizzling cooking pan.
## Builds a self-contained flat-faceted cast-iron hearth (splayed cabriole legs,
## beveled riveted stove box, recessed panels, brass damper knob, arched -X firebox
## with iron grate bars, flickering glowing coal bed + warm hold OmniLight3D,
## tapered rear stovepipe chimney flue with brass collar bands, and a heavy
## copper-rimmed cast-iron frying skillet), plus sculpted fish/crab food meshes
## and feathered radial-gradient billboard GPUParticles3D steam/smoke.

signal food_placed(item: Dictionary)
signal food_state_changed(cook_state: StringName, item: Dictionary)
signal food_taken(item: Dictionary, pawn: Node)

const COOK_TIME := 10.0
const BURN_TIME := 18.0
const COOK_READY_PULSE_DURATION := 0.85

const SKILLET_CENTER := Vector3(-0.055, 0.678, -0.040)
const FOOD_BASE_POS := Vector3(-0.055, 0.695, -0.040)
const STEAM_POS := Vector3(-0.055, 0.748, -0.040)
const TRIPOD_SKILLET_CENTER := Vector3(0.0, 0.560, 0.0)
const TRIPOD_FOOD_BASE_POS := Vector3(0.0, 0.576, 0.0)
const TRIPOD_STEAM_POS := Vector3(0.0, 0.630, 0.0)
const FLUE_CENTER := Vector2(0.205, 0.185)

# Painterly soot-black wrought cast-iron, hammered copper, brass, coal & food palettes (sRGB).
const COL_IRON_HI := Color(0.16, 0.145, 0.135)
const COL_IRON_MID := Color(0.08, 0.075, 0.08)
const COL_IRON_DARK := Color(0.055, 0.050, 0.052)
const COL_IRON_PANEL := Color(0.068, 0.062, 0.064)
const COL_IRON_SOOT := Color(0.032, 0.028, 0.030)
const COL_IRON_OILED := Color(0.065, 0.060, 0.062)
const COL_RIVET := Color(0.20, 0.185, 0.17)

const COL_BRASS_HI := Color(0.96, 0.78, 0.30)
const COL_BRASS_MID := Color(0.82, 0.60, 0.19)
const COL_BRASS_DARK := Color(0.54, 0.37, 0.11)

const COL_COPPER_HI := Color(0.96, 0.58, 0.30)
const COL_COPPER_MID := Color(0.84, 0.42, 0.18)
const COL_COPPER_DARK := Color(0.56, 0.25, 0.10)

const COL_COAL_CORE := Color(1.00, 0.76, 0.22)
const COL_COAL_HOT := Color(1.00, 0.38, 0.07)
const COL_COAL_DEEP := Color(0.74, 0.14, 0.03)
const COL_COAL_ASH := Color(0.22, 0.08, 0.04)

const HEARTH_HALO_POS := Vector3(-0.30, 0.30, 0.0)
const SIZZLE_MOTE_COUNT := 14
const COL_SIZZLE_EMPTY := Color(0.0, 0.0, 0.0, 0.0)
const COL_SIZZLE_RAW := Color(0.98, 0.94, 0.82, 0.86)
const COL_SIZZLE_COOKED := Color(1.00, 0.80, 0.24, 0.94)
const COL_SIZZLE_BURNT := Color(1.00, 0.28, 0.05, 0.98)

# Neutral-warm value mask colors for sculpted food (multiplied by _food_mat.albedo_color).
const COL_FISH_FLANK := Color(0.96, 0.94, 0.92)
const COL_FISH_DORSAL := Color(0.76, 0.77, 0.80)
const COL_FISH_BELLY := Color(1.00, 0.99, 0.96)
const COL_FISH_FIN := Color(0.84, 0.80, 0.76)
const COL_FISH_SEAR := Color(0.44, 0.32, 0.24)
const COL_FISH_EYE := Color(0.18, 0.18, 0.20)

const COL_CRAB_SHELL := Color(0.96, 0.90, 0.86)
const COL_CRAB_RIDGE := Color(0.76, 0.64, 0.58)
const COL_CRAB_CLAW := Color(1.00, 0.95, 0.88)
const COL_CRAB_MEAT := Color(1.00, 0.99, 0.95)
const COL_CRAB_TIP := Color(0.86, 0.82, 0.74)

@export var build_hearth: bool = true
@export var build_campfire_tripod: bool = false

var cooking_item: Dictionary = {}
var elapsed: float = 0.0
var cook_state: StringName = &"empty"  # &"empty", &"raw", &"cooked", &"burnt"
var interactable: Interactable = null

var _hearth_mesh: MeshInstance3D = null
var _tripod_mesh: MeshInstance3D = null
var _coal_mesh: MeshInstance3D = null
var _hearth_light: OmniLight3D = null
var _hearth_halo_mesh: MeshInstance3D = null
var _skillet_mesh: MeshInstance3D = null
var _food_mesh: MeshInstance3D = null
var _steam_particles: GPUParticles3D = null
var _sizzle_motes: MultiMeshInstance3D = null

var _iron_mat: StandardMaterial3D = null
var _brass_mat: StandardMaterial3D = null
var _skillet_iron_mat: StandardMaterial3D = null
var _copper_mat: StandardMaterial3D = null
var _coal_mat: StandardMaterial3D = null
var _hearth_halo_mat: StandardMaterial3D = null
var _food_mat: StandardMaterial3D = null

var _fish_mesh: ArrayMesh = null
var _crab_mesh: ArrayMesh = null

var _sizzle_mm: MultiMesh = null
var _sizzle_mesh: ArrayMesh = null
var _sizzle_mat: StandardMaterial3D = null
var _sizzle_mode_color: Color = COL_SIZZLE_EMPTY
var _sizzle_phase_off: PackedFloat32Array = PackedFloat32Array()
var _sizzle_angle_off: PackedFloat32Array = PackedFloat32Array()
var _sizzle_rad_frac: PackedFloat32Array = PackedFloat32Array()
var _sizzle_spin_rate: PackedFloat32Array = PackedFloat32Array()
var _sizzle_positions: PackedVector3Array = PackedVector3Array()

var _steam_tex: ImageTexture = null
var _steam_mat: StandardMaterial3D = null
var _steam_proc: ParticleProcessMaterial = null
var _steam_quad: ArrayMesh = null
var _steam_ramp: GradientTexture1D = null
var _steam_scale_tex: CurveTexture = null

var _anim_time: float = 0.0
var _cook_ready_pulse: float = 0.0
var _cook_ready_rise: float = 0.0
var _food_base_yaw: float = 0.32
var _in_physics_step: bool = false


func _ready() -> void:
	interactable = Interactable.create("Cook fish or crab on pan", 0.7)
	interactable.position = Vector3(0.0, 0.62, 0.0) if (build_campfire_tripod and not build_hearth) else Vector3(0.0, 0.4, 0.0)
	interactable.interacted.connect(_on_interacted)
	add_child(interactable)
	if build_hearth:
		_build_hearth_visual()
	elif build_campfire_tripod:
		_build_campfire_tripod_visual()
	_build_food_visual()


func _exit_tree() -> void:
	_cook_ready_pulse = 0.0
	_cook_ready_rise = 0.0
	if _steam_particles != null and is_instance_valid(_steam_particles):
		_steam_particles.emitting = false
		_steam_particles.visible = false
		_steam_particles.draw_pass_1 = null
		_steam_particles.process_material = null
	if _steam_quad != null and _steam_quad.get_surface_count() > 0:
		_steam_quad.surface_set_material(0, null)
	if _steam_mat != null:
		_steam_mat.albedo_texture = null
	if _steam_proc != null:
		_steam_proc.color_ramp = null
		_steam_proc.scale_curve = null
	if _sizzle_motes != null and is_instance_valid(_sizzle_motes):
		_sizzle_motes.visible = false
		_sizzle_motes.material_override = null
		_sizzle_motes.multimesh = null
	for mi: MeshInstance3D in [_hearth_mesh, _tripod_mesh, _coal_mesh, _hearth_halo_mesh, _skillet_mesh, _food_mesh]:
		if mi != null and is_instance_valid(mi):
			if mi.mesh != null:
				for surf_i in mi.mesh.get_surface_count():
					mi.set_surface_override_material(surf_i, null)
			mi.mesh = null
			mi.material_override = null
	_hearth_mesh = null
	_tripod_mesh = null
	_coal_mesh = null
	_hearth_light = null
	_hearth_halo_mesh = null
	_skillet_mesh = null
	_food_mesh = null
	_sizzle_motes = null
	_sizzle_mm = null
	_sizzle_mesh = null
	_sizzle_mat = null
	_sizzle_mode_color = COL_SIZZLE_EMPTY
	_sizzle_positions.clear()
	_steam_tex = null
	_steam_mat = null
	_steam_proc = null
	_steam_quad = null
	_steam_ramp = null
	_steam_scale_tex = null
	_iron_mat = null
	_brass_mat = null
	_skillet_iron_mat = null
	_copper_mat = null
	_coal_mat = null
	_hearth_halo_mat = null
	_food_mat = null
	_fish_mesh = null
	_crab_mesh = null


## Return the additive billboard HearthFireHalo MeshInstance3D (null when build_hearth == false).
func get_hearth_halo_node() -> MeshInstance3D:
	return _hearth_halo_mesh


## Return the MultiMeshInstance3D rendering the 14 rising faceted skillet sizzle/aroma/ember motes.
func get_sizzle_motes_node() -> MultiMeshInstance3D:
	return _sizzle_motes


## Return the active skillet sizzle mote palette tint for the current cook_state.
func get_sizzle_mode_color() -> Color:
	return _sizzle_mode_color


## Return the latest local-space positions of the 14 rising skillet sizzle/aroma/ember motes.
func get_sizzle_mote_positions() -> PackedVector3Array:
	return _sizzle_positions


## Return the current 0..1 sear-ready golden flourish pulse intensity.
func get_cook_ready_pulse() -> float:
	return _cook_ready_pulse


func _food_base_pos() -> Vector3:
	return TRIPOD_FOOD_BASE_POS if (build_campfire_tripod and not build_hearth) else FOOD_BASE_POS


func _steam_base_pos() -> Vector3:
	return TRIPOD_STEAM_POS if (build_campfire_tripod and not build_hearth) else STEAM_POS


# ==============================================================================
# 1. Sculpted Cast-Iron Naval Galley Hearth, Campfire Tripod & Copper Skillet
# ==============================================================================

func _ensure_hardware_materials() -> void:
	if _iron_mat == null:
		_iron_mat = StandardMaterial3D.new()
		_iron_mat.vertex_color_use_as_albedo = true
		_iron_mat.vertex_color_is_srgb = true
		_iron_mat.metallic = 0.62
		_iron_mat.roughness = 0.48

	if _brass_mat == null:
		_brass_mat = StandardMaterial3D.new()
		_brass_mat.vertex_color_use_as_albedo = true
		_brass_mat.vertex_color_is_srgb = true
		_brass_mat.metallic = 0.84
		_brass_mat.roughness = 0.28

	if _skillet_iron_mat == null:
		_skillet_iron_mat = StandardMaterial3D.new()
		_skillet_iron_mat.vertex_color_use_as_albedo = true
		_skillet_iron_mat.vertex_color_is_srgb = true
		_skillet_iron_mat.metallic = 0.62
		_skillet_iron_mat.roughness = 0.36
		_skillet_iron_mat.clearcoat_enabled = true
		_skillet_iron_mat.clearcoat = 0.26
		_skillet_iron_mat.clearcoat_roughness = 0.24

	if _copper_mat == null:
		_copper_mat = StandardMaterial3D.new()
		_copper_mat.vertex_color_use_as_albedo = true
		_copper_mat.vertex_color_is_srgb = true
		_copper_mat.metallic = 0.86
		_copper_mat.roughness = 0.26


func _build_hearth_visual() -> void:
	_ensure_hardware_materials()

	_coal_mat = StandardMaterial3D.new()
	_coal_mat.vertex_color_use_as_albedo = true
	_coal_mat.vertex_color_is_srgb = true
	_coal_mat.roughness = 0.84
	_coal_mat.metallic = 0.04
	_coal_mat.emission_enabled = true
	_coal_mat.emission = Color(1.0, 0.40, 0.09)
	_coal_mat.emission_energy_multiplier = 2.4

	# 1a. Cast-iron galley stove body, bowed legs, arched firebox + grate, chimney flue.
	var hearth_array := _build_galley_hearth_mesh()
	_hearth_mesh = MeshInstance3D.new()
	_hearth_mesh.name = "GalleyHearth"
	_hearth_mesh.mesh = hearth_array
	_hearth_mesh.set_surface_override_material(0, _iron_mat)
	if hearth_array.get_surface_count() > 1:
		_hearth_mesh.set_surface_override_material(1, _brass_mat)
	add_child(_hearth_mesh)

	# 1b. Glowing red-orange coal bed behind the -X arched firebox grate bars.
	_coal_mesh = MeshInstance3D.new()
	_coal_mesh.name = "CoalBed"
	_coal_mesh.mesh = _build_coal_bed_mesh()
	_coal_mesh.material_override = _coal_mat
	_coal_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_coal_mesh)

	# 1c. Subtle warm hold hearth light positioned just outside the -X firebox grate.
	_hearth_light = OmniLight3D.new()
	_hearth_light.name = "HearthLight"
	_hearth_light.position = Vector3(-0.34, 0.31, 0.0)
	_hearth_light.light_color = Color(1.0, 0.56, 0.22)
	_hearth_light.light_energy = 0.45
	_hearth_light.omni_range = 2.8
	_hearth_light.omni_attenuation = 1.5
	_hearth_light.shadow_enabled = false
	add_child(_hearth_light)

	# 1d. Atmospheric 16-wedge additive billboard firebox glow halo hugging the -X grate.
	_hearth_halo_mat = StandardMaterial3D.new()
	_hearth_halo_mat.vertex_color_use_as_albedo = true
	_hearth_halo_mat.vertex_color_is_srgb = true
	_hearth_halo_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_hearth_halo_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_hearth_halo_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_hearth_halo_mat.billboard_keep_scale = true
	_hearth_halo_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	_hearth_halo_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_hearth_halo_mat.albedo_color = Color(0.86, 0.80, 0.72, 1.0)

	_hearth_halo_mesh = MeshInstance3D.new()
	_hearth_halo_mesh.name = "HearthFireHalo"
	_hearth_halo_mesh.position = HEARTH_HALO_POS
	_hearth_halo_mesh.mesh = _build_hearth_halo_mesh()
	_hearth_halo_mesh.material_override = _hearth_halo_mat
	_hearth_halo_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_hearth_halo_mesh)

	# 1e. Heavy copper-rimmed cast-iron frying skillet resting on cooktop.
	_mount_skillet_mesh(SKILLET_CENTER)


func _build_campfire_tripod_visual() -> void:
	_ensure_hardware_materials()

	# Sculpted 3-leg forged-iron campfire cooking tripod + link chain + 3-point bridle.
	var tripod_array := _build_campfire_tripod_mesh()
	_tripod_mesh = MeshInstance3D.new()
	_tripod_mesh.name = "CampfireTripod"
	_tripod_mesh.mesh = tripod_array
	_tripod_mesh.set_surface_override_material(0, _iron_mat)
	if tripod_array.get_surface_count() > 1:
		_tripod_mesh.set_surface_override_material(1, _brass_mat)
	add_child(_tripod_mesh)

	# Hanging copper-rimmed cast-iron skillet suspended cleanly at y = 0.56 m over the embers!
	_mount_skillet_mesh(TRIPOD_SKILLET_CENTER)


func _mount_skillet_mesh(local_pos: Vector3) -> void:
	var skillet_array := _build_skillet_mesh()
	_skillet_mesh = MeshInstance3D.new()
	_skillet_mesh.name = "FryingSkillet"
	_skillet_mesh.position = local_pos
	_skillet_mesh.mesh = skillet_array
	_skillet_mesh.set_surface_override_material(0, _skillet_iron_mat)
	if skillet_array.get_surface_count() > 1:
		_skillet_mesh.set_surface_override_material(1, _copper_mat)
	add_child(_skillet_mesh)


static func _build_campfire_tripod_mesh() -> ArrayMesh:
	var iron_st := SurfaceTool.new()
	iron_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var brass_st := SurfaceTool.new()
	brass_st.begin(Mesh.PRIMITIVE_TRIANGLES)

	const LEG_FOOT_R := 0.68
	const APEX_Y := 1.46
	const PAN_RIM_Y := TRIPOD_SKILLET_CENTER.y + 0.046
	const PAN_RIM_R := 0.198
	const BRIDLE_Y := 0.85

	# 1. Three splayed forged-iron tripod legs planted firmly at y = 0.0 (r = 0.68 m straddling fire ring).
	for li in 3:
		var ang := deg_to_rad(30.0 + float(li) * 120.0)
		var rdir := Vector3(cos(ang), 0.0, sin(ang))
		var foot := rdir * LEG_FOOT_R
		# Beveled octagonal forged iron foot pad resting flush at y = 0.0 (+ shallow sand spike).
		var foot_rings: Array[Array] = [
			[-0.060, 0.000, COL_IRON_SOOT],
			[-0.060, 0.012, COL_IRON_SOOT],
			[0.000, 0.044, COL_IRON_DARK],
			[0.022, 0.040, COL_IRON_MID],
			[0.036, 0.024, COL_IRON_HI],
		]
		_append_lathe_y(iron_st, foot_rings, 6, foot)

		# Slightly arched forged iron tripod shaft converging to apex + decorative crossed finial!
		var p_bot := foot + Vector3(0.0, 0.024, 0.0)
		var p_mid := rdir * (LEG_FOOT_R * 0.52) + Vector3(0.0, APEX_Y * 0.52, 0.0)
		var p_apex := rdir * 0.028 + Vector3(0.0, APEX_Y, 0.0)
		var p_tip := -rdir * 0.068 + Vector3(0.0, APEX_Y + 0.135, 0.0)
		_append_tube_chain(
			iron_st,
			[p_bot, p_mid, p_apex, p_tip],
			[0.022, 0.020, 0.018, 0.011],
			[COL_IRON_DARK, COL_IRON_MID, COL_IRON_HI, COL_IRON_HI],
			6
		)
		# Decorative forged spear-tip finial capping each crossed iron leg.
		_append_cone_spike(iron_st, p_tip, p_tip + (-rdir * 0.018 + Vector3(0.0, 0.036, 0.0)),
			0.013, COL_IRON_HI, COL_RIVET)

		# Small forged reinforcement sleeve & brass stud midway up each leg.
		_append_cylinder_between(
			iron_st,
			p_mid - Vector3(0.0, 0.03, 0.0),
			p_mid + Vector3(0.0, 0.03, 0.0),
			0.025, 0.025, 6, COL_IRON_DARK, COL_IRON_HI
		)
		_append_rivet_dome(brass_st, p_mid + rdir * 0.024, rdir, 0.009, 0.006, COL_BRASS_HI)

	# 2. Forged iron apex binding crown collar + gleaming brass hinge ring & suspension hook.
	var crown_rings: Array[Array] = [
		[APEX_Y - 0.052, 0.056, COL_IRON_DARK],
		[APEX_Y - 0.036, 0.068, COL_IRON_HI],
		[APEX_Y + 0.022, 0.068, COL_IRON_HI],
		[APEX_Y + 0.038, 0.054, COL_IRON_DARK],
	]
	_append_lathe_y(iron_st, crown_rings, 8)
	var brass_band: Array[Array] = [
		[APEX_Y - 0.022, 0.069, COL_BRASS_DARK],
		[APEX_Y - 0.008, 0.074, COL_BRASS_HI],
		[APEX_Y + 0.008, 0.074, COL_BRASS_HI],
		[APEX_Y + 0.022, 0.069, COL_BRASS_DARK],
	]
	_append_lathe_y(brass_st, brass_band, 8)

	# Apex suspension pin & hook directly beneath the binding crown.
	_append_cylinder_between(iron_st, Vector3(0.0, APEX_Y - 0.03, 0.0), Vector3(0.0, APEX_Y - 0.11, 0.0),
		0.016, 0.012, 6, COL_IRON_MID, COL_IRON_HI)

	# 3. Sculpted 7-link forged iron suspension chain descending from apex hook to bridle ring.
	var chain_top_y := APEX_Y - 0.105
	var chain_links := 7
	var link_step := (chain_top_y - BRIDLE_Y) / float(chain_links)
	for ci in chain_links:
		var cy := chain_top_y - (float(ci) + 0.5) * link_step
		var link_h := link_step * 0.62
		var link_w := 0.022
		var dir_x := Vector3.RIGHT if (ci % 2 == 0) else Vector3.FORWARD
		var p_t := Vector3(0.0, cy + link_h, 0.0)
		var p_b := Vector3(0.0, cy - link_h, 0.0)
		var p_tl := Vector3(0.0, cy + link_h * 0.55, 0.0) - dir_x * link_w
		var p_tr := Vector3(0.0, cy + link_h * 0.55, 0.0) + dir_x * link_w
		var p_bl := Vector3(0.0, cy - link_h * 0.55, 0.0) - dir_x * link_w
		var p_br := Vector3(0.0, cy - link_h * 0.55, 0.0) + dir_x * link_w
		_append_cylinder_between(iron_st, p_t, p_tl, 0.0075, 0.0075, 5, COL_IRON_HI, COL_IRON_MID)
		_append_cylinder_between(iron_st, p_t, p_tr, 0.0075, 0.0075, 5, COL_IRON_HI, COL_IRON_MID)
		_append_cylinder_between(iron_st, p_tl, p_bl, 0.0075, 0.0075, 5, COL_IRON_MID, COL_IRON_DARK)
		_append_cylinder_between(iron_st, p_tr, p_br, 0.0075, 0.0075, 5, COL_IRON_MID, COL_IRON_DARK)
		_append_cylinder_between(iron_st, p_bl, p_b, 0.0075, 0.0075, 5, COL_IRON_DARK, COL_IRON_HI)
		_append_cylinder_between(iron_st, p_br, p_b, 0.0075, 0.0075, 5, COL_IRON_DARK, COL_IRON_HI)

	# Forged iron + brass swivel bridle collector ring at y = BRIDLE_Y.
	var bridle_rings: Array[Array] = [
		[BRIDLE_Y - 0.020, 0.020, COL_BRASS_DARK],
		[BRIDLE_Y - 0.008, 0.032, COL_BRASS_HI],
		[BRIDLE_Y + 0.008, 0.032, COL_BRASS_HI],
		[BRIDLE_Y + 0.020, 0.020, COL_BRASS_DARK],
	]
	_append_lathe_y(brass_st, bridle_rings, 8)

	# 4. Three forged-iron bail chains & riveted rim lug brackets cradling the hanging cast-iron skillet!
	for bi in 3:
		# Offset 60 deg from handle direction so all 3 bail chains clear the skillet handle cleanly!
		var bang := deg_to_rad(25.0 + float(bi) * 120.0)
		var bdir := Vector3(cos(bang), 0.0, sin(bang))
		var top_pt := bdir * 0.026 + Vector3(0.0, BRIDLE_Y - 0.012, 0.0)
		var rim_pt := bdir * PAN_RIM_R + Vector3(0.0, PAN_RIM_Y, 0.0)
		_append_cylinder_between(iron_st, top_pt, rim_pt, 0.007, 0.007, 5, COL_IRON_HI, COL_IRON_MID)
		# Small forged iron lug ear & brass rivet gripping the skillet rim.
		_append_beveled_box(
			iron_st, rim_pt + bdir * 0.008 - Vector3(0.0, 0.010, 0.0),
			Vector3(0.024, 0.026, 0.024), 0.005, COL_IRON_HI, COL_IRON_MID, COL_IRON_DARK
		)
		_append_rivet_dome(brass_st, rim_pt + bdir * 0.020 - Vector3(0.0, 0.010, 0.0), bdir, 0.006, 0.004, COL_BRASS_HI)

	iron_st.generate_normals()
	var mesh := iron_st.commit()
	brass_st.generate_normals()
	brass_st.commit(mesh)
	return mesh


static func _build_galley_hearth_mesh() -> ArrayMesh:
	var iron_st := SurfaceTool.new()
	iron_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var brass_st := SurfaceTool.new()
	brass_st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# --- 4 bowed cast-iron splayed cabriole legs resting firmly at y = 0.0 ---
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			var foot_c := Vector3(sx * 0.275, 0.0, sz * 0.255)
			var pad_rings: Array[Array] = [
				[0.000, 0.000, COL_IRON_DARK],
				[0.000, 0.044, COL_IRON_DARK],
				[0.018, 0.042, COL_IRON_MID],
				[0.028, 0.030, COL_IRON_HI],
			]
			_append_lathe_y(iron_st, pad_rings, 6, foot_c)

			var leg_pts: Array[Vector3] = [
				Vector3(sx * 0.275, 0.022, sz * 0.255),
				Vector3(sx * 0.288, 0.068, sz * 0.266),
				Vector3(sx * 0.266, 0.112, sz * 0.244),
				Vector3(sx * 0.232, 0.152, sz * 0.212),
			]
			var leg_rads: Array[float] = [0.029, 0.036, 0.038, 0.044]
			var leg_cols: Array[Color] = [COL_IRON_DARK, COL_IRON_HI, COL_IRON_MID, COL_IRON_DARK]
			_append_tube_chain(iron_st, leg_pts, leg_rads, leg_cols, 6)

			# Forged under-plinth corner gusset brace.
			_append_cylinder_between(
				iron_st,
				Vector3(sx * 0.248, 0.118, sz * 0.228),
				Vector3(sx * 0.185, 0.155, sz * 0.170),
				0.020, 0.024, 5, COL_IRON_DARK, COL_IRON_MID
			)

	# --- Stepped beveled hearth base plinth + projecting -X ash-catch lip ---
	_append_beveled_box(
		iron_st, Vector3(0.0, 0.168, 0.0), Vector3(0.57, 0.056, 0.53), 0.014,
		COL_IRON_HI, COL_IRON_MID, COL_IRON_DARK
	)
	_append_beveled_box(
		iron_st, Vector3(-0.312, 0.162, 0.0), Vector3(0.11, 0.034, 0.36), 0.008,
		COL_IRON_HI, COL_IRON_MID, COL_IRON_DARK
	)
	# Small raised front ash lip bead along -X edge of ash tray.
	_append_beveled_box(
		iron_st, Vector3(-0.358, 0.184, 0.0), Vector3(0.018, 0.018, 0.35), 0.004,
		COL_IRON_HI, COL_IRON_MID, COL_IRON_DARK
	)

	# --- Stove firebox shell: solid rear/sides with recessed cast-iron panels ---
	# Rear +X bulk wall (leaves x in [-0.26, -0.02] open for recessed firebox cavity).
	_append_beveled_box(
		iron_st, Vector3(0.12, 0.410, 0.0), Vector3(0.28, 0.432, 0.48), 0.010,
		COL_IRON_HI, COL_IRON_MID, COL_IRON_DARK
	)
	# Recessed decorative back-wall cast panel on +X.
	_append_recessed_panel_x(iron_st, 0.260, 1.0, 0.25, 0.57, -0.18, 0.18, 0.016)

	# Side cheeks flanking the firebox cavity (-Z and +Z walls, flush with +/-0.135 arch edges).
	_append_beveled_box(
		iron_st, Vector3(-0.14, 0.410, -0.188), Vector3(0.24, 0.432, 0.104), 0.008,
		COL_IRON_HI, COL_IRON_MID, COL_IRON_DARK
	)
	_append_beveled_box(
		iron_st, Vector3(-0.14, 0.410, 0.188), Vector3(0.24, 0.432, 0.104), 0.008,
		COL_IRON_HI, COL_IRON_MID, COL_IRON_DARK
	)
	# Recessed cast-iron side panels: -Z houses the brass draft damper; +Z has an embossed lozenge.
	_append_recessed_panel_z(iron_st, -0.240, -1.0, -0.19, 0.19, 0.25, 0.57, false)
	_append_recessed_panel_z(iron_st, 0.240, 1.0, -0.19, 0.19, 0.25, 0.57, true)

	# Firebox bottom hearth floor & dark soot vault ceiling sealing the cavity.
	_append_beveled_box(
		iron_st, Vector3(-0.14, 0.205, 0.0), Vector3(0.24, 0.022, 0.30), 0.004,
		COL_IRON_SOOT, COL_IRON_SOOT, COL_IRON_DARK
	)
	_append_beveled_box(
		iron_st, Vector3(-0.14, 0.555, 0.0), Vector3(0.24, 0.142, 0.30), 0.006,
		COL_IRON_HI, COL_IRON_MID, COL_IRON_SOOT
	)

	# --- Arched firebox spandrel header, beveled arch surround & iron grate bars (-X face) ---
	var arch_segs := 8
	var arch_r := 0.135
	var spring_y := 0.345
	var top_y := 0.624
	var front_x := -0.260
	var inner_x := -0.215
	for i in arch_segs:
		var a0 := PI * float(i) / float(arch_segs)
		var a1 := PI * float(i + 1) / float(arch_segs)
		var z0 := -cos(a0) * arch_r
		var y0 := spring_y + sin(a0) * arch_r
		var z1 := -cos(a1) * arch_r
		var y1 := spring_y + sin(a1) * arch_r

		# Front arch spandrel face (-X outward).
		var f_b0 := Vector3(front_x, y0, z0)
		var f_b1 := Vector3(front_x, y1, z1)
		var f_t0 := Vector3(front_x, top_y, z0)
		var f_t1 := Vector3(front_x, top_y, z1)
		_emit_dir_quad(iron_st, f_b0, f_b1, f_t1, f_t0, COL_IRON_MID, COL_IRON_MID, COL_IRON_HI, COL_IRON_HI, Vector3(-1.0, 0.0, 0.0))

		# Underside arch intrados curving into the firebox cavity.
		var i_b0 := Vector3(inner_x, y0, z0)
		var i_b1 := Vector3(inner_x, y1, z1)
		var mid_a := (a0 + a1) * 0.5
		var in_n := Vector3(0.0, -sin(mid_a), cos(mid_a))
		_emit_dir_quad(iron_st, f_b0, i_b0, i_b1, f_b1, COL_IRON_DARK, COL_IRON_SOOT, COL_IRON_SOOT, COL_IRON_DARK, in_n)

		# Proud beveled cast-iron arch surround rib framing the firebox opening.
		var r_out := arch_r + 0.026
		var mid_p0 := Vector3(front_x - 0.016, spring_y + sin(a0) * (arch_r + 0.012), -cos(a0) * (arch_r + 0.012))
		var mid_p1 := Vector3(front_x - 0.016, spring_y + sin(a1) * (arch_r + 0.012), -cos(a1) * (arch_r + 0.012))
		_append_cylinder_between(iron_st, mid_p0, mid_p1, 0.016, 0.016, 5, COL_IRON_HI, COL_IRON_HI)
		if i == 0 or i == arch_segs - 1:
			var end_z := -r_out + 0.014 if i == 0 else r_out - 0.014
			_append_cylinder_between(
				iron_st,
				Vector3(front_x - 0.014, 0.210, end_z),
				Vector3(front_x - 0.014, spring_y + 0.005, end_z),
				0.016, 0.016, 5, COL_IRON_DARK, COL_IRON_HI
			)

	# Bold cast-iron arch keystone boss & flanking brass rivets on the -X face.
	_append_beveled_box(
		iron_st, Vector3(front_x - 0.018, spring_y + arch_r + 0.020, 0.0),
		Vector3(0.032, 0.056, 0.058), 0.008, COL_IRON_HI, COL_IRON_MID, COL_IRON_DARK
	)
	for sg: float in [-1.0, 1.0]:
		_append_rivet_dome(brass_st, Vector3(front_x - 0.014, spring_y, sg * (arch_r + 0.028)), Vector3(-1.0, 0.0, 0.0), 0.011, 0.007, COL_BRASS_HI)

	# 5 forged vertical cast-iron grate bars + horizontal retaining bar across the firebox mouth.
	for gz: float in [-0.10, -0.05, 0.0, 0.05, 0.10]:
		var arch_h := sqrt(maxf(0.0, arch_r * arch_r - gz * gz))
		var bar_top := spring_y + arch_h + 0.008
		_append_cylinder_between(
			iron_st,
			Vector3(-0.252, 0.212, gz),
			Vector3(-0.252, bar_top, gz),
			0.0085, 0.0085, 6, COL_IRON_DARK, COL_IRON_HI
		)
	_append_cylinder_between(
		iron_st,
		Vector3(-0.258, 0.268, -0.145),
		Vector3(-0.258, 0.268, 0.145),
		0.010, 0.010, 6, COL_IRON_HI, COL_IRON_MID
	)

	# --- 4 chamfered corner pilasters + vertical iron rivets ---
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			_append_beveled_box(
				iron_st, Vector3(sx * 0.248, 0.410, sz * 0.228),
				Vector3(0.056, 0.436, 0.056), 0.012, COL_IRON_HI, COL_IRON_MID, COL_IRON_DARK
			)
			for r_i in 4:
				var ry := 0.245 + float(r_i) * 0.110
				_append_rivet_dome(iron_st, Vector3(sx * 0.276, ry, sz * 0.228), Vector3(sx, 0.0, 0.0), 0.009, 0.005, COL_RIVET)
				_append_rivet_dome(iron_st, Vector3(sx * 0.248, ry, sz * 0.256), Vector3(0.0, 0.0, sz), 0.009, 0.005, COL_RIVET)

	# --- Brass draft damper dial & knob centered inside the -Z recessed panel + brass firebox pull ---
	var damp_c := Vector3(0.0, 0.425, -0.243)
	_append_cylinder_between(brass_st, damp_c + Vector3(0.0, 0.0, 0.004), damp_c + Vector3(0.0, 0.0, -0.012), 0.056, 0.048, 10, COL_BRASS_DARK, COL_BRASS_MID)
	_append_cylinder_between(brass_st, damp_c + Vector3(0.0, 0.0, -0.012), damp_c + Vector3(0.0, 0.0, -0.036), 0.013, 0.011, 8, COL_BRASS_DARK, COL_BRASS_MID)
	_append_cylinder_between(brass_st, damp_c + Vector3(0.0, 0.0, -0.034), damp_c + Vector3(0.0, 0.0, -0.052), 0.023, 0.018, 8, COL_BRASS_MID, COL_BRASS_HI)
	# Small dark draft vent slit right below the brass dial inside the recessed panel.
	_append_beveled_box(iron_st, Vector3(0.0, 0.325, -0.247), Vector3(0.105, 0.022, 0.010), 0.003, COL_IRON_SOOT, COL_IRON_SOOT, COL_IRON_SOOT)

	# Brass firebox latch pull on the -X left pier.
	var latch_c := Vector3(-0.264, 0.355, -0.195)
	_append_cylinder_between(brass_st, latch_c + Vector3(0.006, 0.0, 0.0), latch_c + Vector3(-0.028, 0.0, 0.0), 0.010, 0.014, 6, COL_BRASS_DARK, COL_BRASS_HI)
	_append_rivet_dome(brass_st, latch_c + Vector3(-0.028, 0.0, 0.0), Vector3(-1.0, 0.0, 0.0), 0.016, 0.010, COL_BRASS_HI)

	# --- Protruding beveled cast-iron stove top lip rim & cooktop burner ring ---
	_append_beveled_box(
		iron_st, Vector3(0.0, 0.648, 0.0), Vector3(0.62, 0.054, 0.58), 0.013,
		COL_IRON_HI, COL_IRON_MID, COL_IRON_DARK
	)
	# Subtle stepped cast-iron burner eye plate beneath the skillet.
	var burner_rings: Array[Array] = [
		[0.674, 0.192, COL_IRON_DARK],
		[0.680, 0.184, COL_IRON_HI],
		[0.680, 0.158, COL_IRON_DARK],
		[0.677, 0.152, COL_IRON_SOOT],
		[0.677, 0.000, COL_IRON_SOOT],
	]
	_append_lathe_y(iron_st, burner_rings, 12, Vector3(SKILLET_CENTER.x, 0.0, SKILLET_CENTER.z))

	# --- Tapered rear cast-iron stovepipe chimney flue (y = 0.674 .. 1.45 m) ---
	var flue_off := Vector3(FLUE_CENTER.x, 0.0, FLUE_CENTER.y)
	var flue_iron_rings: Array[Array] = [
		[0.674, 0.094, COL_IRON_DARK],
		[0.692, 0.092, COL_IRON_HI],
		[0.708, 0.075, COL_IRON_MID],
		[0.880, 0.068, COL_IRON_MID],
		[0.950, 0.066, COL_IRON_MID],
		[1.260, 0.059, COL_IRON_MID],
		[1.296, 0.058, COL_IRON_MID],
		[1.410, 0.056, COL_IRON_MID],
		[1.442, 0.067, COL_IRON_HI],
		[1.452, 0.064, COL_IRON_HI],
		[1.452, 0.050, COL_IRON_DARK],
		[1.365, 0.047, COL_IRON_SOOT],
		[1.365, 0.000, COL_IRON_SOOT],
	]
	_append_lathe_y(iron_st, flue_iron_rings, 10, flue_off)

	# Gleaming brass collar bands & rivets around the stovepipe chimney flue!
	var collar_lower: Array[Array] = [
		[0.876, 0.068, COL_BRASS_DARK],
		[0.884, 0.078, COL_BRASS_MID],
		[0.914, 0.080, COL_BRASS_HI],
		[0.944, 0.077, COL_BRASS_MID],
		[0.952, 0.066, COL_BRASS_DARK],
	]
	_append_lathe_y(brass_st, collar_lower, 10, flue_off)
	var collar_upper: Array[Array] = [
		[1.256, 0.059, COL_BRASS_DARK],
		[1.264, 0.066, COL_BRASS_HI],
		[1.290, 0.065, COL_BRASS_MID],
		[1.298, 0.058, COL_BRASS_DARK],
	]
	_append_lathe_y(brass_st, collar_upper, 10, flue_off)

	# 6 tiny brass studs around the primary flue collar band + small flue damper handle!
	for r_i in 6:
		var ang := TAU * float(r_i) / 6.0
		var rdir := Vector3(cos(ang), 0.0, sin(ang))
		_append_rivet_dome(brass_st, flue_off + Vector3(0.0, 0.914, 0.0) + rdir * 0.079, rdir, 0.008, 0.005, COL_BRASS_HI)
	# Flue damper pin sticking out toward -X so the cook can twist the draft.
	_append_cylinder_between(
		brass_st,
		flue_off + Vector3(-0.066, 0.914, 0.0),
		flue_off + Vector3(-0.118, 0.914, 0.0),
		0.006, 0.006, 6, COL_BRASS_DARK, COL_BRASS_MID
	)
	_append_cylinder_between(
		brass_st,
		flue_off + Vector3(-0.118, 0.892, 0.0),
		flue_off + Vector3(-0.118, 0.936, 0.0),
		0.007, 0.007, 6, COL_BRASS_MID, COL_BRASS_HI
	)

	iron_st.generate_normals()
	var mesh := iron_st.commit()
	brass_st.generate_normals()
	brass_st.commit(mesh)
	return mesh


static func _build_coal_bed_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Glowing ember bed mound tucked cleanly inside the -X firebox cavity behind the grate bars (x = -0.252).
	var mound_rings: Array[Array] = [
		[0.214, 0.112, COL_COAL_DEEP],
		[0.244, 0.100, COL_COAL_HOT],
		[0.272, 0.076, COL_COAL_CORE],
		[0.292, 0.040, COL_COAL_HOT],
		[0.300, 0.000, COL_COAL_DEEP],
	]
	_append_lathe_y(st, mound_rings, 8, Vector3(-0.130, 0.0, 0.0))

	# 14 sculpted irregular faceted coal chunks with incandescent core -> charred tip gradient.
	var rng := RandomNumberGenerator.new()
	rng.seed = 0xC0A15EA
	var coal_specs: Array[Array] = [
		[Vector3(-0.186, 0.244, -0.076), Vector3(0.034, 0.026, 0.032), COL_COAL_HOT],
		[Vector3(-0.190, 0.252, -0.022), Vector3(0.038, 0.032, 0.036), COL_COAL_CORE],
		[Vector3(-0.188, 0.248, 0.034), Vector3(0.036, 0.030, 0.034), COL_COAL_CORE],
		[Vector3(-0.182, 0.240, 0.080), Vector3(0.032, 0.025, 0.030), COL_COAL_HOT],
		[Vector3(-0.154, 0.280, -0.056), Vector3(0.040, 0.032, 0.038), COL_COAL_CORE],
		[Vector3(-0.148, 0.298, 0.002), Vector3(0.044, 0.038, 0.042), COL_COAL_CORE],
		[Vector3(-0.154, 0.278, 0.058), Vector3(0.038, 0.030, 0.036), COL_COAL_HOT],
		[Vector3(-0.172, 0.274, -0.010), Vector3(0.034, 0.028, 0.032), COL_COAL_HOT],
		[Vector3(-0.118, 0.285, -0.072), Vector3(0.042, 0.034, 0.038), COL_COAL_DEEP],
		[Vector3(-0.112, 0.308, -0.018), Vector3(0.046, 0.038, 0.042), COL_COAL_HOT],
		[Vector3(-0.116, 0.298, 0.046), Vector3(0.042, 0.034, 0.040), COL_COAL_DEEP],
		[Vector3(-0.140, 0.320, 0.018), Vector3(0.034, 0.028, 0.034), COL_COAL_ASH],
		[Vector3(-0.168, 0.296, 0.036), Vector3(0.030, 0.024, 0.030), COL_COAL_ASH],
		[Vector3(-0.164, 0.294, -0.038), Vector3(0.030, 0.024, 0.030), COL_COAL_ASH],
	]
	for spec in coal_specs:
		var pos: Vector3 = spec[0]
		var sz: Vector3 = spec[1]
		var col: Color = spec[2]
		var rot := Basis.from_euler(Vector3(
			rng.randf_range(-0.45, 0.45),
			rng.randf_range(0.0, TAU),
			rng.randf_range(-0.45, 0.45)
		))
		_append_faceted_lump(st, pos, sz, rot, col.lerp(COL_COAL_CORE, 0.28), col, col.lerp(COL_COAL_ASH, 0.55))

	st.generate_normals()
	return st.commit()


static func _build_skillet_mesh() -> ArrayMesh:
	var iron_st := SurfaceTool.new()
	iron_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var copper_st := SurfaceTool.new()
	copper_st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# --- Heavy cast-iron frying skillet body with sloped flared walls & recessed oiled floor ---
	var pan_iron_rings: Array[Array] = [
		[0.000, 0.000, COL_IRON_DARK],
		[0.000, 0.152, COL_IRON_DARK],
		[0.006, 0.160, COL_IRON_MID],
		[0.028, 0.186, COL_IRON_MID],
	]
	_append_lathe_y(iron_st, pan_iron_rings, 14)

	# Inner sloped pan wall & recessed oiled cast-iron cooking floor (y = 0.015).
	var pan_inner_rings: Array[Array] = [
		[0.048, 0.194, COL_IRON_HI],
		[0.022, 0.164, COL_IRON_OILED],
		[0.015, 0.148, COL_IRON_OILED],
		[0.015, 0.000, COL_IRON_OILED],
	]
	_append_lathe_y(iron_st, pan_inner_rings, 14)

	# --- Hammered gleaming copper outer rim band & rolled lip (Surface 1) ---
	var copper_rim_rings: Array[Array] = [
		[0.027, 0.185, COL_COPPER_DARK],
		[0.032, 0.192, COL_COPPER_MID],
		[0.047, 0.205, COL_COPPER_HI],
		[0.052, 0.201, COL_COPPER_HI],
		[0.048, 0.193, COL_COPPER_MID],
	]
	_append_lathe_y(copper_st, copper_rim_rings, 14)

	# --- Long forged iron skillet handle jutting off toward cabin-front (-X, -Z) ---
	var h_dir := Vector3(-0.62, 0.0, -0.785).normalized()
	var h_side := Vector3(-h_dir.z, 0.0, h_dir.x)
	var h_up := Vector3.UP

	# Forged riveted mounting bracket pad clasping outer wall + 2 gleaming copper rivets!
	var pad_c := h_dir * 0.196 + Vector3(0.0, 0.036, 0.0)
	_append_oriented_box(iron_st, pad_c, h_dir, h_up, h_side, Vector3(0.028, 0.024, 0.058), COL_IRON_HI, COL_IRON_DARK)
	for rs: float in [-0.017, 0.017]:
		var rpos := pad_c + h_side * rs + h_dir * 0.014
		_append_rivet_dome(copper_st, rpos, h_dir, 0.007, 0.005, COL_COPPER_HI)

	# Sweeping forged iron handle strap angling gently upward (+16 deg) from skillet wall.
	var strap_pts: Array[Vector3] = [
		h_dir * 0.202 + Vector3(0.0, 0.038, 0.0),
		h_dir * 0.268 + Vector3(0.0, 0.062, 0.0),
		h_dir * 0.342 + Vector3(0.0, 0.084, 0.0),
		h_dir * 0.398 + Vector3(0.0, 0.098, 0.0),
	]
	var strap_ws: Array[float] = [0.036, 0.028, 0.024, 0.028]
	var strap_ts: Array[float] = [0.012, 0.011, 0.010, 0.010]
	for si in range(strap_pts.size() - 1):
		var a := strap_pts[si]
		var b := strap_pts[si + 1]
		var seg_d := (b - a).normalized()
		var seg_u := h_side.cross(seg_d).normalized()
		_append_tapered_strap(
			iron_st, a, b, h_side, seg_u,
			strap_ws[si] * 0.5, strap_ts[si] * 0.5,
			strap_ws[si + 1] * 0.5, strap_ts[si + 1] * 0.5,
			COL_IRON_HI, COL_IRON_DARK
		)

	# Forged hanging-eyelet paddle loop at the end of the handle (left & right forged arms + tip).
	var loop_base := strap_pts[strap_pts.size() - 1]
	var loop_l := loop_base + h_dir * 0.028 + Vector3(0.0, 0.008, 0.0) - h_side * 0.018
	var loop_r := loop_base + h_dir * 0.028 + Vector3(0.0, 0.008, 0.0) + h_side * 0.018
	var loop_tip := loop_base + h_dir * 0.056 + Vector3(0.0, 0.015, 0.0)
	_append_cylinder_between(iron_st, loop_base - h_side * 0.008, loop_l, 0.0065, 0.0060, 5, COL_IRON_HI, COL_IRON_MID)
	_append_cylinder_between(iron_st, loop_base + h_side * 0.008, loop_r, 0.0065, 0.0060, 5, COL_IRON_HI, COL_IRON_MID)
	_append_cylinder_between(iron_st, loop_l, loop_tip, 0.0060, 0.0065, 5, COL_IRON_MID, COL_IRON_HI)
	_append_cylinder_between(iron_st, loop_r, loop_tip, 0.0060, 0.0065, 5, COL_IRON_MID, COL_IRON_HI)

	iron_st.generate_normals()
	var mesh := iron_st.commit()
	copper_st.generate_normals()
	copper_st.commit(mesh)
	return mesh


# ==============================================================================
# 2. Sculpted Sizzling Fish Fillet / Spiced Crab Claw & Feathered Steam VFX
# ==============================================================================

func _build_food_visual() -> void:
	_fish_mesh = _build_pan_fish_mesh()
	_crab_mesh = _build_pan_crab_mesh()

	_food_mat = StandardMaterial3D.new()
	_food_mat.vertex_color_use_as_albedo = true
	_food_mat.vertex_color_is_srgb = true
	_food_mat.albedo_color = Color(0.95, 0.66, 0.58)
	_food_mat.roughness = 0.34
	_food_mat.metallic = 0.06
	_food_mat.clearcoat_enabled = true
	_food_mat.clearcoat = 0.38
	_food_mat.clearcoat_roughness = 0.24

	_food_mesh = MeshInstance3D.new()
	_food_mesh.name = "SizzlingFood"
	_food_mesh.mesh = _fish_mesh
	_food_mesh.position = _food_base_pos()
	_food_mesh.rotation = Vector3(0.0, _food_base_yaw, 0.0)
	_food_mesh.material_override = _food_mat
	_food_mesh.visible = false
	add_child(_food_mesh)

	_build_steam_particles()
	_build_sizzle_motes()


func _build_sizzle_motes() -> void:
	_sizzle_mesh = _build_sizzle_diamond_mesh()

	_sizzle_mat = StandardMaterial3D.new()
	_sizzle_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_sizzle_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_sizzle_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_sizzle_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	_sizzle_mat.vertex_color_use_as_albedo = true
	_sizzle_mat.vertex_color_is_srgb = true
	_sizzle_mat.cull_mode = BaseMaterial3D.CULL_BACK

	var rng := RandomNumberGenerator.new()
	rng.seed = 0x51221E14
	_sizzle_phase_off.resize(SIZZLE_MOTE_COUNT)
	_sizzle_angle_off.resize(SIZZLE_MOTE_COUNT)
	_sizzle_rad_frac.resize(SIZZLE_MOTE_COUNT)
	_sizzle_spin_rate.resize(SIZZLE_MOTE_COUNT)
	_sizzle_positions.resize(SIZZLE_MOTE_COUNT)
	for i in SIZZLE_MOTE_COUNT:
		_sizzle_phase_off[i] = rng.randf_range(-0.03, 0.03)
		_sizzle_angle_off[i] = rng.randf_range(0.0, TAU)
		_sizzle_rad_frac[i] = rng.randf_range(0.28, 1.0)
		_sizzle_spin_rate[i] = rng.randf_range(-2.6, 2.6)
		_sizzle_positions[i] = Vector3.ZERO

	_sizzle_mm = MultiMesh.new()
	_sizzle_mm.transform_format = MultiMesh.TRANSFORM_3D
	_sizzle_mm.use_colors = true
	_sizzle_mm.use_custom_data = false
	_sizzle_mm.mesh = _sizzle_mesh
	_sizzle_mm.instance_count = SIZZLE_MOTE_COUNT
	for i in SIZZLE_MOTE_COUNT:
		_sizzle_mm.set_instance_transform(i, Transform3D.IDENTITY)
		_sizzle_mm.set_instance_color(i, COL_SIZZLE_EMPTY)

	_sizzle_motes = MultiMeshInstance3D.new()
	_sizzle_motes.name = "SkilletSizzleMotes"
	_sizzle_motes.position = _steam_base_pos()
	_sizzle_motes.multimesh = _sizzle_mm
	_sizzle_motes.material_override = _sizzle_mat
	_sizzle_motes.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_sizzle_motes.extra_cull_margin = 0.85
	_sizzle_motes.visible = false
	add_child(_sizzle_motes)


static func _build_hearth_halo_mesh() -> ArrayMesh:
	# Sculpted 16-wedge radial-gradient additive billboard halo disc (bright fiery amber core -> black rim).
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	const WEDGES := 16
	const OUTER_R := 0.26
	const MID_R := 0.115
	var col_core := Color(1.00, 0.72, 0.24, 1.0)
	var col_mid := Color(0.86, 0.34, 0.06, 1.0)
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


static func _build_sizzle_diamond_mesh() -> ArrayMesh:
	# Sculpted 8-triangle faceted diamond crystal mote (4 upper + 4 lower faces, zero raw primitives).
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var col_hi := Color(1.00, 1.00, 1.00, 1.0)
	var col_mid := Color(0.92, 0.90, 0.88, 1.0)
	var col_lo := Color(0.76, 0.74, 0.72, 1.0)
	var top := Vector3(0.0, 0.018, 0.0)
	var bot := Vector3(0.0, -0.014, 0.0)
	var ring: Array[Vector3] = [
		Vector3(0.010, 0.0, 0.0),
		Vector3(0.0, 0.0, 0.010),
		Vector3(-0.010, 0.0, 0.0),
		Vector3(0.0, 0.0, -0.010),
	]
	for k in 4:
		var nk := (k + 1) % 4
		_emit_outward_tri(st, top, col_hi, ring[k], col_mid, ring[nk], col_mid, Vector3.ZERO)
		_emit_outward_tri(st, bot, col_lo, ring[nk], col_mid, ring[k], col_mid, Vector3.ZERO)
	st.generate_normals()
	return st.commit()


func _build_steam_particles() -> void:
	_steam_tex = _make_steam_puff_texture()

	_steam_mat = StandardMaterial3D.new()
	_steam_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_steam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_steam_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	_steam_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_steam_mat.vertex_color_use_as_albedo = true
	_steam_mat.albedo_texture = _steam_tex

	_steam_quad = _build_quad_card_mesh(Vector2(0.32, 0.32), _steam_mat)

	var scale_curve := Curve.new()
	scale_curve.add_point(Vector2(0.0, 0.48))
	scale_curve.add_point(Vector2(0.35, 1.12))
	scale_curve.add_point(Vector2(1.0, 1.82))
	_steam_scale_tex = CurveTexture.new()
	_steam_scale_tex.curve = scale_curve

	_steam_ramp = _make_color_ramp(
		PackedFloat32Array([0.0, 0.20, 0.68, 1.0]),
		PackedColorArray([
			Color(0.98, 0.96, 0.91, 0.0),
			Color(0.98, 0.96, 0.91, 0.42),
			Color(0.95, 0.92, 0.87, 0.24),
			Color(0.92, 0.90, 0.86, 0.0),
		])
	)

	_steam_proc = ParticleProcessMaterial.new()
	_steam_proc.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	_steam_proc.emission_ring_axis = Vector3.UP
	_steam_proc.emission_ring_radius = 0.115
	_steam_proc.emission_ring_inner_radius = 0.018
	_steam_proc.emission_ring_height = 0.02
	_steam_proc.direction = Vector3.UP
	_steam_proc.spread = 22.0
	_steam_proc.initial_velocity_min = 0.20
	_steam_proc.initial_velocity_max = 0.36
	_steam_proc.gravity = Vector3(0.0, 0.16, 0.0)
	_steam_proc.damping_min = 0.22
	_steam_proc.damping_max = 0.42
	_steam_proc.angle_min = 0.0
	_steam_proc.angle_max = 360.0
	_steam_proc.angular_velocity_min = -26.0
	_steam_proc.angular_velocity_max = 26.0
	_steam_proc.scale_min = 0.84
	_steam_proc.scale_max = 1.38
	_steam_proc.scale_curve = _steam_scale_tex
	_steam_proc.color_ramp = _steam_ramp

	_steam_particles = GPUParticles3D.new()
	_steam_particles.name = "CookingSteam"
	_steam_particles.position = _steam_base_pos()
	_steam_particles.amount = 18
	_steam_particles.lifetime = 1.80
	_steam_particles.local_coords = true
	_steam_particles.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD
	_steam_particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_steam_particles.visibility_aabb = AABB(Vector3(-0.7, -0.1, -0.7), Vector3(1.4, 1.6, 1.4))
	_steam_particles.process_material = _steam_proc
	_steam_particles.draw_pass_1 = _steam_quad
	_steam_particles.emitting = false
	_steam_particles.visible = false
	add_child(_steam_particles)


## Zero-primitive 2-tri billboard quad card spanning [-w/2..w/2] x [-h/2..h/2] at z = 0.
static func _build_quad_card_mesh(size: Vector2, mat: Material = null) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hw := size.x * 0.5
	var hh := size.y * 0.5
	var nrm := Vector3(0.0, 0.0, 1.0)
	var p_tl := Vector3(-hw, hh, 0.0)
	var p_tr := Vector3(hw, hh, 0.0)
	var p_br := Vector3(hw, -hh, 0.0)
	var p_bl := Vector3(-hw, -hh, 0.0)
	var uv_tl := Vector2(0.0, 0.0)
	var uv_tr := Vector2(1.0, 0.0)
	var uv_br := Vector2(1.0, 1.0)
	var uv_bl := Vector2(0.0, 1.0)

	st.set_normal(nrm); st.set_uv(uv_tl); st.add_vertex(p_tl)
	st.set_normal(nrm); st.set_uv(uv_tr); st.add_vertex(p_tr)
	st.set_normal(nrm); st.set_uv(uv_br); st.add_vertex(p_br)

	st.set_normal(nrm); st.set_uv(uv_tl); st.add_vertex(p_tl)
	st.set_normal(nrm); st.set_uv(uv_br); st.add_vertex(p_br)
	st.set_normal(nrm); st.set_uv(uv_bl); st.add_vertex(p_bl)
	var mesh := st.commit()
	if mat != null and mesh.get_surface_count() > 0:
		mesh.surface_set_material(0, mat)
	return mesh


static func _build_pan_fish_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Whole pan-seared fish fillet resting on its side in XZ (-X snout -> +X forked tail).
	# Each station: [x, half_width_z, height_y, z_curve]
	var stations: Array[Array] = [
		[-0.132, 0.000, 0.008, 0.012],
		[-0.104, 0.028, 0.028, 0.016],
		[-0.064, 0.048, 0.042, 0.014],
		[-0.016, 0.054, 0.046, 0.004],
		[0.032, 0.044, 0.038, -0.008],
		[0.070, 0.026, 0.024, -0.014],
		[0.094, 0.012, 0.014, -0.012],
	]
	var rad_segs := 8
	for j in range(stations.size() - 1):
		var s0: Array = stations[j]
		var s1: Array = stations[j + 1]
		var x0 := float(s0[0])
		var rz0 := float(s0[1])
		var hy0 := float(s0[2])
		var zc0 := float(s0[3])
		var x1 := float(s1[0])
		var rz1 := float(s1[1])
		var hy1 := float(s1[2])
		var zc1 := float(s1[3])
		var c_ref := Vector3((x0 + x1) * 0.5, (hy0 + hy1) * 0.25, (zc0 + zc1) * 0.5)

		for k in rad_segs:
			var a0 := float(k) / float(rad_segs) * TAU
			var a1 := float(k + 1) / float(rad_segs) * TAU
			var p00 := _fish_station_pt(x0, zc0, rz0, hy0, a0)
			var p01 := _fish_station_pt(x0, zc0, rz0, hy0, a1)
			var p10 := _fish_station_pt(x1, zc1, rz1, hy1, a0)
			var p11 := _fish_station_pt(x1, zc1, rz1, hy1, a1)
			var col0 := _fish_profile_color(a0)
			var col1 := _fish_profile_color(a1)
			if rz0 <= 1e-5:
				_emit_outward_tri(st, p00, col0, p10, col0, p11, col1, c_ref)
			elif rz1 <= 1e-5:
				_emit_outward_tri(st, p00, col0, p01, col1, p10, col0, c_ref)
			else:
				_emit_outward_tri(st, p00, col0, p10, col0, p11, col1, c_ref)
				_emit_outward_tri(st, p00, col0, p11, col1, p01, col1, c_ref)

	# Cap tail peduncle cleanly.
	var ped_c := Vector3(0.094, 0.007, -0.012)
	for k in rad_segs:
		var a0 := float(k) / float(rad_segs) * TAU
		var a1 := float(k + 1) / float(rad_segs) * TAU
		_emit_dir_tri(
			st,
			ped_c, COL_FISH_FLANK,
			_fish_station_pt(0.094, -0.012, 0.012, 0.014, a0), COL_FISH_FLANK,
			_fish_station_pt(0.094, -0.012, 0.012, 0.014, a1), COL_FISH_FLANK,
			Vector3.RIGHT
		)

	# Sculpted notched forked tail fin (+X end) resting neatly inside the skillet!
	var ty := 0.008
	var tc_z := -0.012
	var t_r0 := Vector3(0.088, ty, tc_z - 0.012)
	var t_rm := Vector3(0.094, ty, tc_z)
	var t_r1 := Vector3(0.088, ty, tc_z + 0.012)
	var t_notch := Vector3(0.118, ty + 0.002, tc_z + 0.004)
	var t_lobe_a := Vector3(0.140, ty + 0.008, tc_z - 0.044)
	var t_lobe_b := Vector3(0.138, ty + 0.007, tc_z + 0.046)
	_append_fin_blade(st, t_r0, t_rm, t_notch, t_lobe_a, 0.0045, COL_FISH_DORSAL, COL_FISH_FIN)
	_append_fin_blade(st, t_rm, t_r1, t_lobe_b, t_notch, 0.0045, COL_FISH_FLANK, COL_FISH_FIN)

	# Swept dorsal fin along the curved back (-Z edge).
	_append_fin_blade(
		st,
		Vector3(-0.056, 0.014, -0.030),
		Vector3(0.046, 0.012, -0.044),
		Vector3(0.062, 0.016, -0.070),
		Vector3(-0.026, 0.017, -0.068),
		0.004, COL_FISH_DORSAL, COL_FISH_FIN
	)

	# Flared pectoral fin resting atop the upper pan-seared flank (+Y side).
	_append_fin_blade(
		st,
		Vector3(-0.052, 0.036, 0.018),
		Vector3(-0.028, 0.038, 0.030),
		Vector3(0.004, 0.030, 0.054),
		Vector3(-0.020, 0.026, 0.058),
		0.0035, COL_FISH_FLANK, COL_FISH_FIN
	)

	# 4 crisp diagonal grill sear marks scored across the upper flank!
	var sear_xs: Array[float] = [-0.052, -0.020, 0.012, 0.042]
	var sear_widths: Array[float] = [0.062, 0.078, 0.072, 0.050]
	var sear_hs: Array[float] = [0.041, 0.046, 0.041, 0.031]
	var sear_zcs: Array[float] = [0.011, 0.005, -0.003, -0.010]
	for si in sear_xs.size():
		var sx := sear_xs[si]
		var sw := sear_widths[si]
		var sy := sear_hs[si]
		var szc := sear_zcs[si]
		var p_a := Vector3(sx - 0.010, sy - 0.004, szc - sw * 0.44)
		var p_m := Vector3(sx, sy + 0.0035, szc)
		var p_b := Vector3(sx + 0.010, sy - 0.004, szc + sw * 0.44)
		_append_cylinder_between(st, p_a, p_m, 0.0036, 0.0042, 5, COL_FISH_SEAR, COL_FISH_SEAR)
		_append_cylinder_between(st, p_m, p_b, 0.0042, 0.0036, 5, COL_FISH_SEAR, COL_FISH_SEAR)

	# Stylized dark eye bead on the upward-facing cheek.
	_append_rivet_dome(st, Vector3(-0.088, 0.029, 0.006), Vector3(0.0, 1.0, 0.0), 0.0085, 0.0045, COL_FISH_EYE)

	st.generate_normals()
	return st.commit()


static func _fish_station_pt(x: float, zc: float, rz: float, hy: float, ang: float) -> Vector3:
	# Flattened bottom resting solidly on the hot skillet, plump domed upper flank.
	var cz := cos(ang) * rz
	var sy := sin(ang)
	var py := (0.34 + 0.66 * sy) * hy if sy >= 0.0 else (0.34 + 0.34 * sy) * hy
	return Vector3(x, maxf(py, 0.0), zc + cz)


static func _fish_profile_color(ang: float) -> Color:
	var c := cos(ang)
	if c < -0.25:
		return COL_FISH_FLANK.lerp(COL_FISH_DORSAL, clampf((-c - 0.25) * 1.35, 0.0, 1.0))
	if c > 0.25:
		return COL_FISH_FLANK.lerp(COL_FISH_BELLY, clampf((c - 0.25) * 1.35, 0.0, 1.0))
	return COL_FISH_FLANK


static func _build_pan_crab_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# --- 1. Domed faceted crab carapace half resting on the left-aft side of the skillet ---
	var shell_c := Vector3(-0.044, 0.0, 0.022)
	var segs := 8
	var layers: Array[Array] = [
		[0.002, 0.062, 0.052, COL_CRAB_MEAT],
		[0.018, 0.076, 0.064, COL_CRAB_SHELL],
		[0.042, 0.058, 0.048, COL_CRAB_SHELL],
		[0.056, 0.028, 0.024, COL_CRAB_RIDGE],
	]
	var rings: Array[Array] = []
	var rcols: Array[Color] = []
	for layer in layers:
		var ly := float(layer[0])
		var rx := float(layer[1])
		var rz := float(layer[2])
		var col: Color = layer[3]
		var ring: Array[Vector3] = []
		for i in segs:
			var a := float(i) / float(segs) * TAU
			var ridge := 1.0 + 0.05 * cos(a * 4.0)
			ring.append(shell_c + Vector3(cos(a) * rx * ridge, ly, sin(a) * rz * ridge))
		rings.append(ring)
		rcols.append(col)

	var sc_ref := shell_c + Vector3(0.0, 0.024, 0.0)
	for j in range(rings.size() - 1):
		var r0: Array = rings[j]
		var r1: Array = rings[j + 1]
		var c0: Color = rcols[j]
		var c1: Color = rcols[j + 1]
		for i in segs:
			var ni := (i + 1) % segs
			var dark_c := c0.lerp(COL_CRAB_RIDGE, 0.35 if (i % 2 == 0 and j == 1) else 0.0)
			_emit_outward_tri(st, r0[i], dark_c, r1[i], c1, r1[ni], c1, sc_ref)
			_emit_outward_tri(st, r0[i], dark_c, r1[ni], c1, r0[ni], dark_c, sc_ref)

	var top_pt := shell_c + Vector3(0.0, 0.062, 0.0)
	var bot_pt := shell_c + Vector3(0.0, 0.001, 0.0)
	var top_r: Array = rings[rings.size() - 1]
	var bot_r: Array = rings[0]
	for i in segs:
		var ni := (i + 1) % segs
		_emit_outward_tri(st, top_pt, COL_CRAB_SHELL, top_r[i], COL_CRAB_RIDGE, top_r[ni], COL_CRAB_RIDGE, sc_ref)
		_emit_outward_tri(st, bot_pt, COL_CRAB_MEAT, bot_r[ni], COL_CRAB_MEAT, bot_r[i], COL_CRAB_MEAT, sc_ref)

	# Serrated shell margin spikes & two stubby roasted leg segments tucked beneath carapace.
	for sp_ang: float in [-0.7, -0.2, 0.35, 0.85]:
		var sbase := shell_c + Vector3(-cos(sp_ang) * 0.068, 0.020, sin(sp_ang) * 0.056)
		var stip := shell_c + Vector3(-cos(sp_ang) * 0.090, 0.024, sin(sp_ang) * 0.072)
		_append_cone_spike(st, sbase, stip, 0.011, COL_CRAB_SHELL, COL_CRAB_TIP)

	for l_i in 2:
		var lz := 0.034 + float(l_i) * 0.026
		var lp0 := shell_c + Vector3(-0.034, 0.014, lz * 0.55)
		var lp1 := shell_c + Vector3(-0.066, 0.022, lz)
		var lp2 := shell_c + Vector3(-0.046, 0.008, lz + 0.024)
		_append_cylinder_between(st, lp0, lp1, 0.011, 0.009, 6, COL_CRAB_RIDGE, COL_CRAB_SHELL)
		_append_cone_spike(st, lp1, lp2, 0.009, COL_CRAB_SHELL, COL_CRAB_TIP)

	# --- 2. Chunky curved segmented crusher pincer claw curling beside the carapace ---
	# Exposed creamy crab meat knuckle base -> segmented forearm -> swollen crusher palm.
	var k0 := Vector3(0.015, 0.016, 0.088)
	var k1 := Vector3(0.052, 0.020, 0.058)
	var k2 := Vector3(0.082, 0.026, 0.012)
	_append_cylinder_between(st, k0 - Vector3(0.014, 0.0, 0.012), k0, 0.014, 0.016, 6, COL_CRAB_MEAT, COL_CRAB_MEAT)
	_append_cylinder_between(st, k0, k1, 0.018, 0.022, 6, COL_CRAB_RIDGE, COL_CRAB_SHELL)
	_append_cylinder_between(st, k1, k2, 0.022, 0.029, 6, COL_CRAB_SHELL, COL_CRAB_CLAW)

	# Swollen faceted crusher palm (propodus) with roasted ridge.
	var palm_c := Vector3(0.074, 0.030, -0.028)
	var palm_rot := Basis.from_euler(Vector3(0.08, 0.42, -0.14))
	_append_faceted_lump(st, palm_c, Vector3(0.042, 0.030, 0.054), palm_rot, COL_CRAB_CLAW, COL_CRAB_SHELL, COL_CRAB_RIDGE)

	# Curved upper fixed pincer prong sweeping inward around the pan.
	var up0 := Vector3(0.064, 0.034, -0.062)
	var up1 := Vector3(0.034, 0.032, -0.098)
	var up2 := Vector3(-0.012, 0.022, -0.106)
	_append_cylinder_between(st, up0, up1, 0.020, 0.014, 6, COL_CRAB_CLAW, COL_CRAB_TIP)
	_append_cone_spike(st, up1, up2, 0.014, COL_CRAB_TIP, COL_CRAB_MEAT)

	# Angled lower pincer thumb (dactylus) forming unmistakable V-pincer silhouette!
	var lo0 := Vector3(0.044, 0.022, -0.042)
	var lo1 := Vector3(0.006, 0.018, -0.066)
	var lo2 := Vector3(-0.026, 0.016, -0.082)
	_append_cylinder_between(st, lo0, lo1, 0.016, 0.012, 6, COL_CRAB_SHELL, COL_CRAB_TIP)
	_append_cone_spike(st, lo1, lo2, 0.012, COL_CRAB_TIP, COL_CRAB_MEAT)

	# Two tiny pale serrated crusher teeth inside the pincer gap.
	_append_cone_spike(st, Vector3(0.038, 0.027, -0.078), Vector3(0.024, 0.024, -0.066), 0.0065, COL_CRAB_MEAT, COL_CRAB_TIP)
	_append_cone_spike(st, Vector3(0.016, 0.025, -0.090), Vector3(0.008, 0.021, -0.076), 0.0060, COL_CRAB_MEAT, COL_CRAB_TIP)

	st.generate_normals()
	return st.commit()


static func _make_steam_puff_texture() -> ImageTexture:
	var sz := 64
	var img := Image.create(sz, sz, false, Image.FORMAT_RGBA8)
	var half := float(sz - 1) * 0.5
	# Soft multi-lobe radial gradient cloud puff -- zero hard billboard edges.
	var lobes: Array[Vector3] = [
		Vector3(0.0, 0.0, 0.86),
		Vector3(-0.22, -0.08, 0.54),
		Vector3(0.24, -0.05, 0.52),
		Vector3(0.03, 0.22, 0.50),
		Vector3(-0.12, 0.18, 0.42),
	]
	for y in sz:
		for x in sz:
			var nx := (float(x) - half) / half
			var ny := (float(y) - half) / half
			var density := 0.0
			for lobe in lobes:
				var dx := nx - lobe.x
				var dy := ny - lobe.y
				var r := sqrt(dx * dx + dy * dy) / lobe.z
				if r < 1.0:
					var w := 1.0 - r * r
					density = maxf(density, w * w)
			var edge := clampf(1.0 - sqrt(nx * nx + ny * ny), 0.0, 1.0)
			var alpha := clampf(density * smoothstep(0.0, 0.48, edge), 0.0, 1.0)
			var shade := lerpf(0.86, 1.0, density)
			img.set_pixel(x, y, Color(shade, shade, shade, alpha))
	return ImageTexture.create_from_image(img)


static func _make_color_ramp(offsets: PackedFloat32Array, colors: PackedColorArray) -> GradientTexture1D:
	var grad := Gradient.new()
	grad.offsets = offsets
	grad.colors = colors
	var tex := GradientTexture1D.new()
	tex.width = 24
	tex.gradient = grad
	return tex


func _update_food_visual() -> void:
	if _food_mesh == null or _food_mat == null:
		return
	var active := not cooking_item.is_empty()
	_food_mesh.visible = active
	if _steam_particles != null and is_instance_valid(_steam_particles):
		_steam_particles.visible = active
		_steam_particles.emitting = active
	if not active:
		_food_mesh.position = _food_base_pos()
		_food_mesh.rotation = Vector3(0.0, _food_base_yaw, 0.0)
		_food_mat.emission_enabled = false
		_food_mat.emission_energy_multiplier = 0.0
		_update_sizzle_motes()
		return

	var is_crab := String(cooking_item.get("id", "")).contains("crab")
	_food_mesh.mesh = _crab_mesh if is_crab else _fish_mesh
	_update_food_tint()
	_update_steam_profile()
	_update_sizzle_motes()


func _update_food_tint() -> void:
	if _food_mat == null or cooking_item.is_empty():
		return
	var is_crab := String(cooking_item.get("id", "")).contains("crab")
	var raw_col := Color(0.94, 0.36, 0.25) if is_crab else Color(0.95, 0.64, 0.56)
	var cooked_col := Color(0.98, 0.52, 0.16) if is_crab else Color(0.90, 0.58, 0.22)
	var burnt_col := Color(0.14, 0.11, 0.10)

	if cook_state == &"raw":
		var u := clampf(elapsed / COOK_TIME, 0.0, 1.0)
		var sear_blend := u * u * 0.42
		_food_mat.albedo_color = raw_col.lerp(cooked_col, sear_blend)
		_food_mat.roughness = lerpf(0.34, 0.38, sear_blend)
		_food_mat.clearcoat_enabled = true
		_food_mat.clearcoat = lerpf(0.36, 0.46, sear_blend)
		_food_mat.clearcoat_roughness = 0.22
		_food_mat.emission_enabled = false
		_food_mat.emission_energy_multiplier = 0.0
	elif cook_state == &"cooked":
		var burn_u := clampf((elapsed - COOK_TIME) / maxf(BURN_TIME - COOK_TIME, 0.1), 0.0, 1.0)
		var dark_warn := clampf((burn_u - 0.65) / 0.35, 0.0, 1.0) * 0.32
		var sheen_pulse := 0.5 + 0.5 * sin(_anim_time * 4.4)
		_food_mat.albedo_color = cooked_col.lerp(burnt_col, dark_warn)
		_food_mat.roughness = lerpf(0.38, 0.54, dark_warn)
		_food_mat.clearcoat_enabled = true
		_food_mat.clearcoat = lerpf(0.56, 0.25, dark_warn) + 0.10 * sheen_pulse * (1.0 - dark_warn)
		_food_mat.clearcoat_roughness = 0.20
		# Subtle savory warm golden sheen pulse so any pirate immediately sees a perfectly seared meal!
		_food_mat.emission_enabled = true
		_food_mat.emission = Color(1.00, 0.70, 0.20)
		_food_mat.emission_energy_multiplier = (0.24 + 0.18 * sheen_pulse) * (1.0 - dark_warn * 0.8)
	else:
		_food_mat.albedo_color = burnt_col
		_food_mat.roughness = 0.94
		_food_mat.clearcoat_enabled = false
		_food_mat.clearcoat = 0.0
		_food_mat.emission_enabled = false
		_food_mat.emission_energy_multiplier = 0.0


func _update_steam_profile() -> void:
	if _steam_proc == null:
		return
	if cook_state == &"raw":
		_steam_proc.initial_velocity_min = 0.20
		_steam_proc.initial_velocity_max = 0.34
		_steam_proc.scale_min = 0.84
		_steam_proc.scale_max = 1.36
		_steam_ramp = _make_color_ramp(
			PackedFloat32Array([0.0, 0.20, 0.68, 1.0]),
			PackedColorArray([
				Color(0.98, 0.96, 0.91, 0.0),
				Color(0.98, 0.96, 0.91, 0.42),
				Color(0.95, 0.92, 0.87, 0.24),
				Color(0.92, 0.90, 0.86, 0.0),
			])
		)
	elif cook_state == &"cooked":
		_steam_proc.initial_velocity_min = 0.24
		_steam_proc.initial_velocity_max = 0.42
		_steam_proc.scale_min = 1.02
		_steam_proc.scale_max = 1.56
		_steam_ramp = _make_color_ramp(
			PackedFloat32Array([0.0, 0.18, 0.66, 1.0]),
			PackedColorArray([
				Color(1.00, 0.95, 0.85, 0.0),
				Color(1.00, 0.95, 0.85, 0.42),
				Color(0.96, 0.90, 0.78, 0.25),
				Color(0.92, 0.88, 0.80, 0.0),
			])
		)
	else:
		_steam_proc.initial_velocity_min = 0.30
		_steam_proc.initial_velocity_max = 0.50
		_steam_proc.scale_min = 1.20
		_steam_proc.scale_max = 1.84
		_steam_ramp = _make_color_ramp(
			PackedFloat32Array([0.0, 0.18, 0.62, 1.0]),
			PackedColorArray([
				Color(0.14, 0.13, 0.13, 0.0),
				Color(0.14, 0.13, 0.13, 0.58),
				Color(0.20, 0.19, 0.19, 0.36),
				Color(0.24, 0.23, 0.23, 0.0),
			])
		)
	_steam_proc.color_ramp = _steam_ramp


# ==============================================================================
# 3. Cooking Simulation & Diegetic Hearth / Sizzle Animation
# ==============================================================================

func place_food(item: Dictionary) -> bool:
	if not Net.is_host() or not cooking_item.is_empty():
		return false
	cooking_item = item.duplicate()
	elapsed = 0.0
	cook_state = &"raw"
	_cook_ready_pulse = 0.0
	_cook_ready_rise = 0.0
	cooking_item["cooked_state"] = cook_state
	if interactable != null:
		interactable.prompt = "Take %s (cooking...)" % String(cooking_item.get("name", "Fish"))
	_update_food_visual()
	food_placed.emit(cooking_item)
	return true


func take_food(pawn: Node = null) -> Dictionary:
	if not Net.is_host() or cooking_item.is_empty():
		return {}
	var out := cooking_item.duplicate()
	out["cooked_state"] = cook_state
	cooking_item = {}
	elapsed = 0.0
	cook_state = &"empty"
	_cook_ready_pulse = 0.0
	_cook_ready_rise = 0.0
	if interactable != null:
		interactable.prompt = "Cook fish or crab on pan"
	_update_food_visual()
	_update_hearth_flicker()
	if pawn is Pawn:
		var heal_amt := float(out.get("heal", 35.0))
		if out["cooked_state"] == &"cooked":
			heal_amt *= 1.85
		elif out["cooked_state"] == &"burnt":
			heal_amt *= 0.25
		(pawn as Pawn).heal(heal_amt)
		Audio.play_sfx(&"grog_gulp", (pawn as Pawn).eye_position(), -2.0)
	food_taken.emit(out, pawn)
	return out


func _physics_process(delta: float) -> void:
	_in_physics_step = true
	step(delta)
	_in_physics_step = false
	_anim_time += delta

	_update_hearth_flicker()
	_update_sizzle_motes()
	if cook_state == &"cooked":
		_update_food_tint()

	# Subtle lively sizzling pan-jiggle & rock while cooking!
	if _food_mesh != null and _food_mesh.visible:
		var vig := 1.0 if cook_state == &"cooked" else (0.72 if cook_state == &"raw" else 0.25)
		var hop := absf(sin(_anim_time * 19.0)) * 0.0024 * vig
		var shim_x := sin(_anim_time * 23.0) * 0.0016 * vig
		var shim_z := cos(_anim_time * 17.0) * 0.0016 * vig
		_food_mesh.position = _food_base_pos() + Vector3(shim_x, hop, shim_z)
		_food_mesh.rotation = Vector3(
			sin(_anim_time * 14.5) * 0.036 * vig,
			_food_base_yaw + cos(_anim_time * 11.0) * 0.026 * vig,
			cos(_anim_time * 16.2) * 0.034 * vig
		)


func _update_hearth_flicker() -> void:
	# Gentle dual-frequency firebox coal, warm hearth OmniLight3D, and additive HearthFireHalo flicker.
	var active_cook := not cooking_item.is_empty()
	var flick := sin(_anim_time * 5.7) * 0.55 + sin(_anim_time * 13.1 + 1.3) * 0.30 + cos(_anim_time * 2.9) * 0.15
	var ready_swell := 0.25 * _cook_ready_pulse
	if _coal_mat != null:
		var base_em := 2.65 if active_cook else 2.25
		_coal_mat.emission_energy_multiplier = base_em + flick * 0.38 + ready_swell * 1.4
	if _hearth_light != null and is_instance_valid(_hearth_light):
		var base_e := 0.50 if active_cook else 0.44
		_hearth_light.light_energy = base_e + flick * 0.065 + ready_swell
	if _hearth_halo_mat != null and _hearth_halo_mesh != null and is_instance_valid(_hearth_halo_mesh):
		var base_g := 0.96 if active_cook else 0.78
		var glow := clampf(base_g + flick * 0.16 + ready_swell, 0.45, 1.50)
		var g_green := lerpf(0.93, 0.96, _cook_ready_pulse)
		var g_blue := lerpf(0.82, 0.76, _cook_ready_pulse)
		_hearth_halo_mat.albedo_color = Color(glow, glow * g_green, glow * g_blue, 1.0)
		var hs := (1.06 if active_cook else 0.96) + flick * 0.07 + ready_swell * 0.5
		_hearth_halo_mesh.scale = Vector3(hs, hs, hs)


func _update_sizzle_motes() -> void:
	if _sizzle_motes == null or not is_instance_valid(_sizzle_motes) or _sizzle_mm == null:
		return
	if cook_state == &"empty" or cooking_item.is_empty():
		_sizzle_motes.visible = false
		_sizzle_mode_color = COL_SIZZLE_EMPTY
		return

	_sizzle_motes.visible = true
	var y_min := 0.02
	var y_max := 0.24
	var rise_speed := 0.62
	var rad_max := 0.13
	var scale_lo := 0.46
	var scale_hi := 0.74
	var wiggle_amp := 0.015
	var wiggle_freq := 4.2

	if cook_state == &"raw":
		_sizzle_mode_color = COL_SIZZLE_RAW
	elif cook_state == &"cooked":
		_sizzle_mode_color = COL_SIZZLE_COOKED
		var ready_burst := 1.0 + 0.55 * _cook_ready_pulse
		y_min = 0.04
		y_max = 0.52
		rise_speed = 0.48
		rad_max = 0.165
		scale_lo = 0.70 * ready_burst
		scale_hi = 1.08 * ready_burst
		wiggle_amp = 0.026
		wiggle_freq = 3.1
	else:
		_sizzle_mode_color = COL_SIZZLE_BURNT
		y_min = 0.06
		y_max = 0.68
		rise_speed = 1.18
		rad_max = 0.195
		scale_lo = 0.78
		scale_hi = 1.26
		wiggle_amp = 0.036
		wiggle_freq = 8.4

	var rise_extra := _cook_ready_rise if cook_state == &"cooked" else 0.0
	for i in SIZZLE_MOTE_COUNT:
		var u := fposmod(float(i) / float(SIZZLE_MOTE_COUNT) + _sizzle_phase_off[i] + _anim_time * rise_speed + rise_extra, 1.0)
		var y := lerpf(y_min, y_max, u)
		var ang := _sizzle_angle_off[i] + _anim_time * _sizzle_spin_rate[i] + u * 2.4
		var r := _sizzle_rad_frac[i] * rad_max * (0.45 + 0.55 * u)
		var x := cos(ang) * r + sin(_anim_time * wiggle_freq + float(i) * 1.7) * wiggle_amp * u
		var z := sin(ang) * r + cos(_anim_time * wiggle_freq * 0.85 + float(i) * 2.3) * wiggle_amp * u
		var env := smoothstep(0.0, 0.14, u) * (1.0 - smoothstep(0.76, 1.0, u))
		var sc := lerpf(scale_lo, scale_hi, _sizzle_rad_frac[i]) * maxf(env, 0.18)
		var rot := Basis.from_euler(Vector3(_anim_time * 2.4 + float(i), ang, _anim_time * 1.8 - float(i) * 0.7))
		var pos := Vector3(x, y, z)
		_sizzle_positions[i] = pos
		_sizzle_mm.set_instance_transform(i, Transform3D(rot.scaled(Vector3(sc, sc * 1.15, sc)), pos))

		var col := _sizzle_mode_color
		if cook_state == &"burnt":
			var flare := 0.5 + 0.5 * sin(_anim_time * 18.0 + float(i) * 2.1)
			col = col.lerp(Color(1.0, 0.64, 0.12, col.a), 0.35 * flare)
		elif cook_state == &"cooked":
			var shimmer := 0.5 + 0.5 * sin(_anim_time * 5.2 + float(i) * 1.3)
			var gold_mix := clampf(0.28 * shimmer + 0.55 * _cook_ready_pulse, 0.0, 1.0)
			col = col.lerp(Color(1.0, 0.94, 0.58, col.a), gold_mix)
		col.a *= clampf(0.25 + 0.75 * env, 0.0, 1.0)
		_sizzle_mm.set_instance_color(i, col)


func step(delta: float) -> void:
	var dt := maxf(delta, 0.0)
	if _cook_ready_pulse > 0.0:
		if cook_state == &"cooked":
			_cook_ready_rise += dt * 0.48 * 0.55 * _cook_ready_pulse
		_cook_ready_pulse = maxf(0.0, _cook_ready_pulse - dt / COOK_READY_PULSE_DURATION)
	if not _in_physics_step:
		_anim_time += delta
	if not Net.is_host() or cooking_item.is_empty():
		if not _in_physics_step:
			_update_hearth_flicker()
		return
	elapsed += delta
	var next_state := &"raw"
	if elapsed >= BURN_TIME:
		next_state = &"burnt"
	elif elapsed >= COOK_TIME:
		next_state = &"cooked"
	if next_state != cook_state:
		var prev_state := cook_state
		cook_state = next_state
		cooking_item["cooked_state"] = cook_state
		var nm := String(cooking_item.get("name", "Fish"))
		if interactable != null:
			interactable.prompt = "Take %s %s" % [String(cook_state), nm]
		if cook_state == &"cooked":
			Game.post_notice("%s is golden and cooked!" % nm)
			if prev_state == &"raw":
				_cook_ready_pulse = 1.0
				_cook_ready_rise = 0.0
				var cue_pos := global_transform * _food_base_pos() if is_inside_tree() else global_position
				Audio.play_sfx(&"lantern_click", cue_pos, -1.5, 0.04)
		elif cook_state == &"burnt":
			_cook_ready_pulse = 0.0
			_cook_ready_rise = 0.0
			Game.post_notice("%s has burnt on the stove!" % nm)
		_update_food_visual()
		if not _in_physics_step:
			_update_hearth_flicker()
		food_state_changed.emit(cook_state, cooking_item)
	else:
		_update_food_tint()
		if not _in_physics_step:
			_update_hearth_flicker()
			_update_sizzle_motes()


func _on_interacted(pawn: Node) -> void:
	if not cooking_item.is_empty():
		take_food(pawn)
	else:
		place_food({"id": &"azure_snapper", "name": "Azure Snapper", "heal": 35.0, "gold": 45})


# ==============================================================================
# 4. Procedural Flat-Faceted `SurfaceTool` Helpers (`set_smooth_group(-1)`)
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


static func _emit_dir_quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3,
		ca: Color, cb: Color, cc: Color, cd: Color, expected_normal: Vector3) -> void:
	_emit_dir_tri(st, a, ca, b, cb, c, cc, expected_normal)
	_emit_dir_tri(st, a, ca, c, cc, d, cd, expected_normal)


static func _emit_outward_tri(st: SurfaceTool, a: Vector3, ca: Color,
		b: Vector3, cb: Color, c: Vector3, cc: Color, ref_center: Vector3) -> void:
	var centroid := (a + b + c) / 3.0
	_emit_dir_tri(st, a, ca, b, cb, c, cc, centroid - ref_center)


static func _append_lathe_y(st: SurfaceTool, rings: Array[Array], segs: int,
		offset: Vector3 = Vector3.ZERO) -> void:
	for j in range(rings.size() - 1):
		var y0 := float(rings[j][0])
		var r0 := float(rings[j][1])
		var c0: Color = rings[j][2]
		var y1 := float(rings[j + 1][0])
		var r1 := float(rings[j + 1][1])
		var c1: Color = rings[j + 1][2]
		var dr := r1 - r0
		var dy := y1 - y0
		for k in segs:
			var a0 := float(k) / float(segs) * TAU
			var a1 := float(k + 1) / float(segs) * TAU
			var am := (a0 + a1) * 0.5
			var rad_dir := Vector3(cos(am), 0.0, sin(am))
			var exp_n := rad_dir * dy - Vector3.UP * dr
			if exp_n.length_squared() < 1e-12:
				exp_n = rad_dir
			var p00 := offset + Vector3(cos(a0) * r0, y0, sin(a0) * r0)
			var p01 := offset + Vector3(cos(a1) * r0, y0, sin(a1) * r0)
			var p10 := offset + Vector3(cos(a0) * r1, y1, sin(a0) * r1)
			var p11 := offset + Vector3(cos(a1) * r1, y1, sin(a1) * r1)
			if r0 > 1e-5 and r1 > 1e-5:
				_emit_dir_tri(st, p00, c0, p11, c1, p10, c1, exp_n)
				_emit_dir_tri(st, p00, c0, p01, c0, p11, c1, exp_n)
			elif r1 > 1e-5:
				_emit_dir_tri(st, p00, c0, p11, c1, p10, c1, exp_n)
			elif r0 > 1e-5:
				_emit_dir_tri(st, p00, c0, p01, c0, p11, c1, exp_n)


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


static func _append_tube_chain(st: SurfaceTool, pts: Array[Vector3], rads: Array[float],
		cols: Array[Color], segs: int) -> void:
	if pts.size() < 2:
		return
	var rings: Array[Array] = []
	for i in pts.size():
		var tang: Vector3
		if i == 0:
			tang = (pts[1] - pts[0]).normalized()
		elif i == pts.size() - 1:
			tang = (pts[i] - pts[i - 1]).normalized()
		else:
			tang = (pts[i + 1] - pts[i - 1]).normalized()
		if tang.length_squared() < 1e-6:
			tang = Vector3.UP
		var ref := Vector3.RIGHT if absf(tang.dot(Vector3.RIGHT)) < 0.85 else Vector3.FORWARD
		var bx := tang.cross(ref).normalized()
		var by := tang.cross(bx).normalized()
		var r := rads[i]
		var ring: Array[Vector3] = []
		for k in segs:
			var a := float(k) / float(segs) * TAU
			ring.append(pts[i] + (bx * cos(a) + by * sin(a)) * r)
		rings.append(ring)

	for i in range(pts.size() - 1):
		var r0: Array = rings[i]
		var r1: Array = rings[i + 1]
		var c0 := cols[i]
		var c1 := cols[i + 1]
		var mid := (pts[i] + pts[i + 1]) * 0.5
		for k in segs:
			var nk := (k + 1) % segs
			_emit_outward_tri(st, r0[k], c0, r1[k], c1, r1[nk], c1, mid)
			_emit_outward_tri(st, r0[k], c0, r1[nk], c1, r0[nk], c0, mid)


static func _append_cone_spike(st: SurfaceTool, base: Vector3, tip: Vector3,
		radius: float, base_col: Color, tip_col: Color) -> void:
	var axis := tip - base
	if axis.length_squared() < 1e-10:
		return
	var an := axis.normalized()
	var ref := Vector3.UP if absf(an.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT
	var bx := an.cross(ref).normalized()
	var by := an.cross(bx).normalized()
	var segs := 6
	var mid := base.lerp(tip, 0.35)
	for k in segs:
		var a0 := float(k) / float(segs) * TAU
		var a1 := float(k + 1) / float(segs) * TAU
		var v0 := base + (bx * cos(a0) + by * sin(a0)) * radius
		var v1 := base + (bx * cos(a1) + by * sin(a1)) * radius
		_emit_outward_tri(st, v0, base_col, v1, base_col, tip, tip_col, mid)
		_emit_outward_tri(st, base, base_col, v1, base_col, v0, base_col, mid)


static func _append_beveled_box(st: SurfaceTool, center: Vector3, size: Vector3, bevel: float,
		col_top: Color, col_mid: Color, col_bot: Color) -> void:
	var hx := size.x * 0.5
	var hy := size.y * 0.5
	var hz := size.z * 0.5
	var bv := minf(bevel, minf(hx, minf(hy, hz)) * 0.45)
	var ix := hx - bv
	var iy := hy - bv
	var iz := hz - bv

	# Octagonal beveled cuboid built as 3 stacked chamfered layers (bot, mid-bot, mid-top, top).
	var ys: Array[float] = [-hy, -iy, iy, hy]
	var xzs: Array[Vector2] = [Vector2(ix, iz), Vector2(hx, hz), Vector2(hx, hz), Vector2(ix, iz)]
	var cols: Array[Color] = [col_bot, col_bot.lerp(col_mid, 0.5), col_mid.lerp(col_top, 0.5), col_top]

	var rings: Array[Array] = []
	for li in 4:
		var ry := center.y + ys[li]
		var rx := xzs[li].x
		var rz := xzs[li].y
		var cx := maxf(rx - bv * 0.5, 0.001)
		var cz := maxf(rz - bv * 0.5, 0.001)
		var ring: Array[Vector3] = [
			Vector3(center.x - cx, ry, center.z - rz),
			Vector3(center.x + cx, ry, center.z - rz),
			Vector3(center.x + rx, ry, center.z - cz),
			Vector3(center.x + rx, ry, center.z + cz),
			Vector3(center.x + cx, ry, center.z + rz),
			Vector3(center.x - cx, ry, center.z + rz),
			Vector3(center.x - rx, ry, center.z + cz),
			Vector3(center.x - rx, ry, center.z - cz),
		]
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

	var top_c := center + Vector3(0.0, hy, 0.0)
	var bot_c := center - Vector3(0.0, hy, 0.0)
	var top_r: Array = rings[3]
	var bot_r: Array = rings[0]
	for k in 8:
		var nk := (k + 1) % 8
		_emit_dir_tri(st, top_c, col_top, top_r[k], col_top, top_r[nk], col_top, Vector3.UP)
		_emit_dir_tri(st, bot_c, col_bot, bot_r[nk], col_bot, bot_r[k], col_bot, Vector3.DOWN)


static func _append_oriented_box(st: SurfaceTool, center: Vector3, ax: Vector3, ay: Vector3, az: Vector3,
		size: Vector3, col_hi: Color, col_lo: Color) -> void:
	var hx := ax * (size.x * 0.5)
	var hy := ay * (size.y * 0.5)
	var hz := az * (size.z * 0.5)
	var c000 := center - hx - hy - hz
	var c100 := center + hx - hy - hz
	var c110 := center + hx + hy - hz
	var c010 := center - hx + hy - hz
	var c001 := center - hx - hy + hz
	var c101 := center + hx - hy + hz
	var c111 := center + hx + hy + hz
	var c011 := center - hx + hy + hz
	_emit_dir_quad(st, c010, c110, c111, c011, col_hi, col_hi, col_hi, col_hi, ay)
	_emit_dir_quad(st, c001, c101, c100, c000, col_lo, col_lo, col_lo, col_lo, -ay)
	_emit_dir_quad(st, c100, c101, c111, c110, col_lo, col_lo, col_hi, col_hi, ax)
	_emit_dir_quad(st, c001, c000, c010, c011, col_lo, col_lo, col_hi, col_hi, -ax)
	_emit_dir_quad(st, c001, c011, c111, c101, col_lo, col_hi, col_hi, col_lo, az)
	_emit_dir_quad(st, c100, c110, c010, c000, col_lo, col_hi, col_hi, col_lo, -az)


static func _append_tapered_strap(st: SurfaceTool, a: Vector3, b: Vector3, side: Vector3, up: Vector3,
		hw0: float, ht0: float, hw1: float, ht1: float, col_hi: Color, col_lo: Color) -> void:
	var mid := (a + b) * 0.5
	var a_tl := a - side * hw0 + up * ht0
	var a_tr := a + side * hw0 + up * ht0
	var a_br := a + side * hw0 - up * ht0
	var a_bl := a - side * hw0 - up * ht0
	var b_tl := b - side * hw1 + up * ht1
	var b_tr := b + side * hw1 + up * ht1
	var b_br := b + side * hw1 - up * ht1
	var b_bl := b - side * hw1 - up * ht1
	var ring_a: Array[Vector3] = [a_tl, a_tr, a_br, a_bl]
	var ring_b: Array[Vector3] = [b_tl, b_tr, b_br, b_bl]
	var cols: Array[Color] = [col_hi, col_hi, col_lo, col_lo]
	for i in 4:
		var ni := (i + 1) % 4
		_emit_outward_tri(st, ring_a[i], cols[i], ring_b[i], cols[i], ring_b[ni], cols[ni], mid)
		_emit_outward_tri(st, ring_a[i], cols[i], ring_b[ni], cols[ni], ring_a[ni], cols[ni], mid)


static func _append_recessed_panel_z(st: SurfaceTool, face_z: float, z_sign: float,
		x0: float, x1: float, y0: float, y1: float, with_medallion: bool) -> void:
	var n := Vector3(0.0, 0.0, z_sign)
	var out_z := face_z + z_sign * 0.018
	var in_z := face_z + z_sign * 0.003
	var b := 0.028
	var o00 := Vector3(x0, y0, out_z)
	var o10 := Vector3(x1, y0, out_z)
	var o11 := Vector3(x1, y1, out_z)
	var o01 := Vector3(x0, y1, out_z)
	var i00 := Vector3(x0 + b, y0 + b, in_z)
	var i10 := Vector3(x1 - b, y0 + b, in_z)
	var i11 := Vector3(x1 - b, y1 - b, in_z)
	var i01 := Vector3(x0 + b, y1 - b, in_z)

	# Outer raised cast-iron frame molding cheeks + recessed dark cast-iron center panel.
	_emit_dir_quad(st, o00, o10, i10, i00, COL_IRON_HI, COL_IRON_HI, COL_IRON_DARK, COL_IRON_DARK, Vector3(0.0, 1.0, z_sign))
	_emit_dir_quad(st, o10, o11, i11, i10, COL_IRON_MID, COL_IRON_MID, COL_IRON_DARK, COL_IRON_DARK, Vector3(-1.0, 0.0, z_sign))
	_emit_dir_quad(st, o11, o01, i01, i11, COL_IRON_HI, COL_IRON_HI, COL_IRON_DARK, COL_IRON_DARK, Vector3(0.0, -1.0, z_sign))
	_emit_dir_quad(st, o01, o00, i00, i01, COL_IRON_MID, COL_IRON_MID, COL_IRON_DARK, COL_IRON_DARK, Vector3(1.0, 0.0, z_sign))
	_emit_dir_quad(st, i00, i10, i11, i01, COL_IRON_PANEL, COL_IRON_PANEL, COL_IRON_PANEL, COL_IRON_PANEL, n)

	# Outer rim perimeter closing frame cleanly onto the backing stove wall.
	var w00 := Vector3(x0, y0, face_z)
	var w10 := Vector3(x1, y0, face_z)
	var w11 := Vector3(x1, y1, face_z)
	var w01 := Vector3(x0, y1, face_z)
	_emit_dir_quad(st, w00, w10, o10, o00, COL_IRON_DARK, COL_IRON_DARK, COL_IRON_MID, COL_IRON_MID, Vector3.DOWN)
	_emit_dir_quad(st, w10, w11, o11, o10, COL_IRON_DARK, COL_IRON_DARK, COL_IRON_MID, COL_IRON_MID, Vector3.RIGHT)
	_emit_dir_quad(st, w11, w01, o01, o11, COL_IRON_DARK, COL_IRON_DARK, COL_IRON_HI, COL_IRON_HI, Vector3.UP)
	_emit_dir_quad(st, w01, w00, o00, o01, COL_IRON_DARK, COL_IRON_DARK, COL_IRON_MID, COL_IRON_MID, Vector3.LEFT)

	if with_medallion:
		var cx := (x0 + x1) * 0.5
		var cy := (y0 + y1) * 0.5
		var dx := (x1 - x0) * 0.24
		var dy := (y1 - y0) * 0.24
		var apex := Vector3(cx, cy, out_z + z_sign * 0.004)
		var dm0 := Vector3(cx, cy - dy, in_z)
		var dm1 := Vector3(cx + dx, cy, in_z)
		var dm2 := Vector3(cx, cy + dy, in_z)
		var dm3 := Vector3(cx - dx, cy, in_z)
		_emit_dir_tri(st, apex, COL_IRON_HI, dm0, COL_IRON_MID, dm1, COL_IRON_MID, n)
		_emit_dir_tri(st, apex, COL_IRON_HI, dm1, COL_IRON_MID, dm2, COL_IRON_MID, n)
		_emit_dir_tri(st, apex, COL_IRON_HI, dm2, COL_IRON_MID, dm3, COL_IRON_MID, n)
		_emit_dir_tri(st, apex, COL_IRON_HI, dm3, COL_IRON_MID, dm0, COL_IRON_MID, n)


static func _append_recessed_panel_x(st: SurfaceTool, face_x: float, x_sign: float,
		y0: float, y1: float, z0: float, z1: float, _depth: float) -> void:
	var n := Vector3(x_sign, 0.0, 0.0)
	var out_x := face_x + x_sign * 0.018
	var in_x := face_x + x_sign * 0.003
	var b := 0.028
	var o00 := Vector3(out_x, y0, z0)
	var o10 := Vector3(out_x, y0, z1)
	var o11 := Vector3(out_x, y1, z1)
	var o01 := Vector3(out_x, y1, z0)
	var i00 := Vector3(in_x, y0 + b, z0 + b)
	var i10 := Vector3(in_x, y0 + b, z1 - b)
	var i11 := Vector3(in_x, y1 - b, z1 - b)
	var i01 := Vector3(in_x, y1 - b, z0 + b)
	_emit_dir_quad(st, o00, o10, i10, i00, COL_IRON_HI, COL_IRON_HI, COL_IRON_DARK, COL_IRON_DARK, Vector3(x_sign, 1.0, 0.0))
	_emit_dir_quad(st, o10, o11, i11, i10, COL_IRON_MID, COL_IRON_MID, COL_IRON_DARK, COL_IRON_DARK, Vector3(x_sign, 0.0, -1.0))
	_emit_dir_quad(st, o11, o01, i01, i11, COL_IRON_HI, COL_IRON_HI, COL_IRON_DARK, COL_IRON_DARK, Vector3(x_sign, -1.0, 0.0))
	_emit_dir_quad(st, o01, o00, i00, i01, COL_IRON_MID, COL_IRON_MID, COL_IRON_DARK, COL_IRON_DARK, Vector3(x_sign, 0.0, 1.0))
	_emit_dir_quad(st, i00, i10, i11, i01, COL_IRON_PANEL, COL_IRON_PANEL, COL_IRON_PANEL, COL_IRON_PANEL, n)
	var w00 := Vector3(face_x, y0, z0)
	var w10 := Vector3(face_x, y0, z1)
	var w11 := Vector3(face_x, y1, z1)
	var w01 := Vector3(face_x, y1, z0)
	_emit_dir_quad(st, w00, w10, o10, o00, COL_IRON_DARK, COL_IRON_DARK, COL_IRON_MID, COL_IRON_MID, Vector3.DOWN)
	_emit_dir_quad(st, w10, w11, o11, o10, COL_IRON_DARK, COL_IRON_DARK, COL_IRON_MID, COL_IRON_MID, Vector3.BACK)
	_emit_dir_quad(st, w11, w01, o01, o11, COL_IRON_DARK, COL_IRON_DARK, COL_IRON_HI, COL_IRON_HI, Vector3.UP)
	_emit_dir_quad(st, w01, w00, o00, o01, COL_IRON_DARK, COL_IRON_DARK, COL_IRON_MID, COL_IRON_MID, Vector3.FORWARD)


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


static func _append_faceted_lump(st: SurfaceTool, center: Vector3, half_ext: Vector3,
		rot: Basis, col_bot: Color, col_mid: Color, col_top: Color) -> void:
	# 6-sided double-frustum crystalline lump (12 side + 12 cap tris) for coal chunks & crab palm.
	var segs := 6
	var bot_pt := center + rot * Vector3(0.0, -half_ext.y, 0.0)
	var top_pt := center + rot * Vector3(0.0, half_ext.y, 0.0)
	var ring_lo: Array[Vector3] = []
	var ring_hi: Array[Vector3] = []
	for k in segs:
		var a := float(k) / float(segs) * TAU
		var wobble := 0.88 + 0.22 * float((k * 3 + 1) % 4) / 3.0
		var v_lo := Vector3(cos(a) * half_ext.x * wobble, -half_ext.y * 0.35, sin(a) * half_ext.z * wobble)
		var v_hi := Vector3(cos(a + 0.28) * half_ext.x * 0.82 * wobble, half_ext.y * 0.42, sin(a + 0.28) * half_ext.z * 0.82 * wobble)
		ring_lo.append(center + rot * v_lo)
		ring_hi.append(center + rot * v_hi)

	for k in segs:
		var nk := (k + 1) % segs
		_emit_outward_tri(st, bot_pt, col_bot, ring_lo[nk], col_bot, ring_lo[k], col_bot, center)
		_emit_outward_tri(st, ring_lo[k], col_mid, ring_hi[k], col_mid, ring_hi[nk], col_mid, center)
		_emit_outward_tri(st, ring_lo[k], col_mid, ring_hi[nk], col_mid, ring_lo[nk], col_mid, center)
		_emit_outward_tri(st, top_pt, col_top, ring_hi[k], col_top, ring_hi[nk], col_top, center)


static func _append_fin_blade(st: SurfaceTool, r0: Vector3, r1: Vector3, t1: Vector3, t0: Vector3,
		half_thick: float, root_col: Color, tip_col: Color) -> void:
	var n := (t0 - r0).cross(r1 - r0)
	if n.length_squared() < 1e-8:
		n = Vector3.UP
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

	_emit_outward_tri(st, r0p, root_col, r1p, root_col, t1p, tip_col, center)
	_emit_outward_tri(st, r0p, root_col, t1p, tip_col, t0p, tip_col, center)
	_emit_outward_tri(st, r0n, root_col, r1n, root_col, t1n, tip_col, center)
	_emit_outward_tri(st, r0n, root_col, t1n, tip_col, t0n, tip_col, center)
	_emit_outward_tri(st, t0p, tip_col, t1p, tip_col, t1n, tip_col, center)
	_emit_outward_tri(st, t0p, tip_col, t1n, tip_col, t0n, tip_col, center)
	_emit_outward_tri(st, r0p, root_col, t0p, tip_col, t0n, tip_col, center)
	_emit_outward_tri(st, r0p, root_col, t0n, tip_col, r0n, root_col, center)
