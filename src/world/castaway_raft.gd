class_name CastawayRaft
extends Node3D
## Stylized lashed-driftwood castaway raft with bamboo signal mast, tattered
## crimson-orange distress pennant, real hanging lit oil lantern, corner supply
## barrel, animated waving castaway CharacterVisual, and rescue Interactable.
##
## Replaces primitive box/sphere placeholders with sculpted vertex-colored
## SurfaceTool timber, rope bindings, and distance-gated character animation.

signal rescued(raft: CastawayRaft, rescuer: Node)

const BARREL_PROP_SCENE: PackedScene = preload("res://assets/generated/props/barrel_prop.glb")

const LOG_COUNT := 7
const ANIM_DISTANCE := 90.0
const ANIM_DISTANCE_SQ := ANIM_DISTANCE * ANIM_DISTANCE
const RESCUE_REACH := 4.5

const CASTAWAY_TINT_PRIMARY := Color(0.20, 0.46, 0.48)
const CASTAWAY_TINT_SECONDARY := Color(0.84, 0.74, 0.52)
const COL_ROPE := Color(0.68, 0.56, 0.36)
const COL_PENNANT_HOIST := Color(0.84, 0.19, 0.10)
const COL_PENNANT_FLY := Color(0.95, 0.46, 0.16)

## Deterministic seed controlling organic driftwood lengths, radii & knots.
@export var raft_seed: int = 1715
## When true, rides Sea.height() & Sea.normal() automatically in _process().
@export var auto_buoyancy: bool = true

var deck_logs_mesh: MeshInstance3D = null
var cross_spars_mesh: MeshInstance3D = null
var lashings_mesh: MeshInstance3D = null
var mast_mesh: MeshInstance3D = null
var pennant_mesh: MeshInstance3D = null
var oar_mesh: MeshInstance3D = null
var lantern_node: Node3D = null
var supply_prop: Node3D = null
var castaway_visual: CharacterVisual = null
var castaway_driver: AnimationDriver = null
var rescue_interactable: Interactable = null
var is_rescued: bool = false

var _pennant_pivot: Node3D = null
var _lantern_pivot: Node3D = null
var _castaway_holder: Node3D = null
var _lantern_light: OmniLight3D = null
var _lantern_flame: Node3D = null
var _rng := RandomNumberGenerator.new()
var _clock: float = 0.0
var _wave_timer: float = 0.8
var _driver_bound: bool = false
var _built: bool = false


func _ready() -> void:
	if name == &"":
		name = "CastawayRaft"
	add_to_group(&"castaway_rafts")
	if not _built:
		_build_raft()


func _exit_tree() -> void:
	if rescue_interactable != null and is_instance_valid(rescue_interactable):
		if rescue_interactable.interacted.is_connected(_on_rescue_interacted):
			rescue_interactable.interacted.disconnect(_on_rescue_interacted)
	if castaway_driver != null and is_instance_valid(castaway_driver):
		castaway_driver.bind(null, null)
	_driver_bound = false
	_lantern_light = null
	_lantern_flame = null


func _process(delta: float) -> void:
	_clock += delta
	_tick_buoyancy(delta)
	_tick_pennant_and_lantern()
	_tick_castaway_animation(delta)


## Return the active rescue Interactable for HUD/world wiring & tests.
func get_rescue_interactable() -> Interactable:
	return rescue_interactable


# ==============================================================================
# Construction
# ==============================================================================

func _build_raft() -> void:
	_built = true
	_rng.seed = raft_seed ^ 0x5A71C

	var log_specs := _build_deck_logs()
	_build_cross_spars_and_planks()
	_build_signal_mast_and_yard()
	_build_lashings(log_specs)
	_build_distress_pennant()
	_build_hanging_lantern()
	_build_supply_props()
	_build_castaway_npc()
	_build_rescue_interactable()


func _build_deck_logs() -> Array[Dictionary]:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var log_specs: Array[Dictionary] = []
	var base_colors: Array[Color] = [
		Color(0.44, 0.31, 0.19),
		Color(0.37, 0.27, 0.18),
		Color(0.49, 0.36, 0.23),
		Color(0.41, 0.30, 0.20),
		Color(0.47, 0.34, 0.22),
		Color(0.36, 0.26, 0.17),
		Color(0.45, 0.33, 0.21),
	]
	var spacing := 0.37
	var half_span := float(LOG_COUNT - 1) * 0.5 * spacing

	for i in LOG_COUNT:
		var t_center := absf(float(i) - float(LOG_COUNT - 1) * 0.5) / (float(LOG_COUNT - 1) * 0.5)
		var x := -half_span + float(i) * spacing + _rng.randf_range(-0.014, 0.014)
		# Center logs run slightly longer to suggest a hand-lashed prow & stern.
		var half_len := lerpf(1.58, 1.32, t_center) + _rng.randf_range(-0.09, 0.10)
		var z_shift := _rng.randf_range(-0.08, 0.08)
		var r_fore := _rng.randf_range(0.155, 0.182)
		var r_aft := _rng.randf_range(0.162, 0.190)
		var yaw_off := _rng.randf_range(-0.028, 0.028)
		var y_center := _rng.randf_range(-0.012, 0.012)

		var p_fore := Vector3(x + sin(yaw_off) * half_len, y_center, z_shift - half_len)
		var p_aft := Vector3(x - sin(yaw_off) * half_len, y_center, z_shift + half_len)
		var crook := Vector3(_rng.randf_range(-0.025, 0.025), _rng.randf_range(-0.014, 0.018), 0.0)
		var bark_col: Color = base_colors[i % base_colors.size()]
		var heart_col := bark_col.lightened(0.24)
		_append_tapered_log(
			st, p_fore, p_aft, r_fore, r_aft, 9, 6, crook, bark_col, heart_col, true, _rng.randf() * TAU
		)
		log_specs.append({
			"x": x,
			"y": y_center,
			"r_avg": (r_fore + r_aft) * 0.5,
		})

	st.generate_normals()
	deck_logs_mesh = _make_mesh_node("DeckLogs", st.commit(), _make_vcol_mat(0.88, 0.02))
	add_child(deck_logs_mesh)
	return log_specs


func _build_cross_spars_and_planks() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Forward and aft transverse timber cross-spars lashing the 7 logs together.
	var spar_bark := Color(0.48, 0.34, 0.21)
	var spar_end := Color(0.62, 0.49, 0.32)
	_append_tapered_log(
		st, Vector3(-1.38, 0.23, -0.92), Vector3(1.38, 0.23, -0.90),
		0.082, 0.088, 8, 5, Vector3(0.0, 0.012, -0.015), spar_bark, spar_end, false, 0.4
	)
	_append_tapered_log(
		st, Vector3(-1.36, 0.23, 0.90), Vector3(1.38, 0.23, 0.92),
		0.086, 0.080, 8, 5, Vector3(0.0, 0.010, 0.014), spar_bark.darkened(0.06), spar_end, false, 1.9
	)

	# Three salvaged deck footing planks spanning between the cross-spars for the castaway.
	var plank_cols: Array[Color] = [
		Color(0.55, 0.41, 0.25),
		Color(0.49, 0.36, 0.22),
		Color(0.53, 0.39, 0.24),
	]
	for pi in 3:
		var px := -0.58 + float(pi) * 0.34
		var py := 0.205
		var xf := Transform3D(Basis(Vector3.UP, _rng.randf_range(-0.03, 0.03)), Vector3(px, py, 0.02))
		_append_beveled_box_vcol(st, Vector3(0.28, 0.042, 1.64), 0.009, xf, plank_cols[pi])

	st.generate_normals()
	cross_spars_mesh = _make_mesh_node("CrossSpars", st.commit(), _make_vcol_mat(0.84, 0.02))
	add_child(cross_spars_mesh)


func _build_signal_mast_and_yard() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var bamboo_light := Color(0.68, 0.58, 0.35)
	var bamboo_node := Color(0.46, 0.36, 0.20)

	# Main lashed bamboo/driftwood signal mast rising from starboard-fore deck.
	var mast_base := Vector3(0.66, 0.12, -0.58)
	var mast_top := Vector3(0.76, 3.12, -0.66)
	_append_bamboo_pole(st, mast_base, mast_top, 0.068, 0.042, 9, 6, Vector3(0.03, 0.0, -0.02), bamboo_light, bamboo_node)

	# Two diagonal driftwood strut braces propping the mast firmly onto deck & spar.
	_append_tapered_log(
		st, Vector3(0.24, 0.22, -0.91), Vector3(0.69, 1.02, -0.60),
		0.042, 0.034, 7, 3, Vector3.ZERO, Color(0.46, 0.33, 0.20), bamboo_light, false, 0.7
	)
	_append_tapered_log(
		st, Vector3(1.08, 0.20, -0.18), Vector3(0.70, 0.96, -0.60),
		0.042, 0.034, 7, 3, Vector3.ZERO, Color(0.43, 0.31, 0.19), bamboo_light, false, 2.2
	)

	# Transverse cross-yard lashed near masthead overhanging starboard to hang the signal lantern.
	var yard_port := Vector3(0.16, 2.64, -0.62)
	var yard_stbd := Vector3(1.48, 2.70, -0.65)
	_append_bamboo_pole(st, yard_port, yard_stbd, 0.034, 0.026, 8, 4, Vector3(0.0, 0.022, 0.0), bamboo_light, bamboo_node)

	st.generate_normals()
	mast_mesh = _make_mesh_node("SignalMast", st.commit(), _make_vcol_mat(0.82, 0.03))
	add_child(mast_mesh)


func _build_lashings(log_specs: Array[Dictionary]) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Diagonal hemp X-lashings tying every driftwood log to both transverse cross-spars.
	for spar_z: float in [-0.91, 0.91]:
		for spec in log_specs:
			var lx: float = float(spec["x"])
			var r_log: float = float(spec["r_avg"])
			var y_top := 0.315
			var y_bot := maxf(-r_log * 0.72, -0.12)
			for diag: float in [-1.0, 1.0]:
				var loop_pts: Array[Vector3] = []
				for k in 11:
					var a := float(k) / 10.0 * TAU
					var ca := cos(a)
					var sa := sin(a)
					var px := lx + ca * (r_log + 0.018)
					var py := lerpf(y_bot, y_top, (sa + 1.0) * 0.5)
					var pz := spar_z + diag * ca * 0.085
					loop_pts.append(Vector3(px, py, pz))
				_append_tube(st, loop_pts, 0.015, 5, false)

	# Thick hemp rope lashing collar binding the cross-yard to the signal mast.
	var yard_joint := Vector3(0.74, 2.66, -0.64)
	for diag: float in [-1.0, 1.0]:
		var yloop: Array[Vector3] = []
		for k in 11:
			var a := float(k) / 10.0 * TAU
			yloop.append(yard_joint + Vector3(cos(a) * 0.085, sin(a) * 0.085, diag * cos(a) * 0.068))
		_append_tube(st, yloop, 0.014, 5, false)

	# Mast-brace lashing collars around the mast waist & foot.
	for cy: float in [0.24, 0.98]:
		var frac := (cy - 0.12) / 3.0
		var mc := Vector3(0.66, 0.12, -0.58).lerp(Vector3(0.76, 3.12, -0.66), frac)
		for turn in 2:
			var collar: Array[Vector3] = []
			for k in 11:
				var a := float(k) / 10.0 * TAU
				collar.append(mc + Vector3(cos(a) * 0.082, float(turn) * 0.028, sin(a) * 0.082))
			_append_tube(st, collar, 0.014, 5, false)

	# Hemp securing rope tying the corner supply barrel to the aft cross-spar.
	var barrel_tie: Array[Vector3] = []
	for k in 13:
		var a := float(k) / 12.0 * TAU
		barrel_tie.append(Vector3(0.76 + cos(a) * 0.30, 0.44 + sin(a * 2.0) * 0.025, 0.58 + sin(a) * 0.30))
	_append_tube(st, barrel_tie, 0.015, 5, false)
	_append_tube(st, [
		Vector3(0.76, 0.44, 0.86),
		Vector3(0.76, 0.32, 0.92),
		Vector3(0.76, 0.18, 0.94),
	], 0.015, 5, true)

	st.generate_normals()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = COL_ROPE
	mat.roughness = 0.92
	mat.metallic = 0.0
	lashings_mesh = _make_mesh_node("RopeLashings", st.commit(), mat)
	add_child(lashings_mesh)


func _build_distress_pennant() -> void:
	_pennant_pivot = Node3D.new()
	_pennant_pivot.name = "PennantPivot"
	_pennant_pivot.position = Vector3(0.75, 2.98, -0.65)
	add_child(_pennant_pivot)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Tattered swallowtail distress pennant streaming along +X in pivot-local space.
	var cols := 10
	var rows := 4
	var length := 1.32
	var hoist := 0.42
	for c in cols:
		var u0 := float(c) / float(cols)
		var u1 := float(c + 1) / float(cols)
		for r in rows:
			var v0 := float(r) / float(rows)
			var v1 := float(r + 1) / float(rows)
			# Carve a classic swallowtail V-notch & ragged trailing tatters near fly tip.
			var v_mid := (v0 + v1) * 0.5
			if u0 >= 0.78 and absf(v_mid - 0.5) < 0.24 * ((u0 - 0.65) / 0.35):
				continue
			if c == cols - 1 and r == 2:
				continue
			var p00 := _pennant_vertex(u0, v0, length, hoist)
			var p10 := _pennant_vertex(u1, v0, length, hoist)
			var p11 := _pennant_vertex(u1, v1, length, hoist)
			var p01 := _pennant_vertex(u0, v1, length, hoist)
			var c0 := COL_PENNANT_HOIST.lerp(COL_PENNANT_FLY, u0)
			var c1 := COL_PENNANT_HOIST.lerp(COL_PENNANT_FLY, u1)
			# Slight sun-bleached edge highlight along top/bottom hem.
			var hem0 := 1.0 + 0.08 * absf(v0 - 0.5) * 2.0
			var hem1 := 1.0 + 0.08 * absf(v1 - 0.5) * 2.0
			var col00 := Color(minf(c0.r * hem0, 1.0), minf(c0.g * hem0, 1.0), minf(c0.b * hem0, 1.0))
			var col10 := Color(minf(c1.r * hem0, 1.0), minf(c1.g * hem0, 1.0), minf(c1.b * hem0, 1.0))
			var col11 := Color(minf(c1.r * hem1, 1.0), minf(c1.g * hem1, 1.0), minf(c1.b * hem1, 1.0))
			var col01 := Color(minf(c0.r * hem1, 1.0), minf(c0.g * hem1, 1.0), minf(c0.b * hem1, 1.0))
			_add_quad_vcol(st, p00, p10, p11, p01, col00, col10, col11, col01)

	st.generate_normals()
	var mat := _make_vcol_mat(0.86, 0.0)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	pennant_mesh = _make_mesh_node("DistressPennant", st.commit(), mat)
	_pennant_pivot.add_child(pennant_mesh)


static func _pennant_vertex(u: float, v: float, length: float, hoist: float) -> Vector3:
	var x := u * length
	var taper := lerpf(1.0, 0.42, pow(u, 0.85))
	var jag := -0.025 * sin(u * 19.0) * u if v > 0.7 else 0.0
	var y := (0.5 - v) * hoist * taper - 0.07 * u * u + jag
	var z := sin(u * PI * 2.15) * 0.075 * u
	return Vector3(x, y, z)


func _build_hanging_lantern() -> void:
	_lantern_pivot = Node3D.new()
	_lantern_pivot.name = "LanternPivot"
	_lantern_pivot.position = Vector3(1.32, 2.68, -0.64)
	add_child(_lantern_pivot)

	# Short sculpted hemp suspension tether dropping from the cross-yard to the lantern bail.
	var st_rope := SurfaceTool.new()
	st_rope.begin(Mesh.PRIMITIVE_TRIANGLES)
	_append_tube(st_rope, [Vector3(0.0, 0.03, 0.0), Vector3(0.0, -0.22, 0.0)], 0.011, 6, true)
	st_rope.generate_normals()
	var rmat := StandardMaterial3D.new()
	rmat.albedo_color = COL_ROPE
	rmat.roughness = 0.92
	_lantern_pivot.add_child(_make_mesh_node("LanternTether", st_rope.commit(), rmat))

	# Real ToolMeshes oil lantern, lit & tuned for sea-horizon distress beacon readability.
	lantern_node = ToolMeshes.build_tool(&"lantern")
	lantern_node.name = "SignalLantern"
	lantern_node.position = Vector3(0.0, -0.22, 0.0)
	lantern_node.scale = Vector3.ONE * 1.18
	ToolMeshes.set_lantern_lit(lantern_node, true)
	_lantern_pivot.add_child(lantern_node)

	_lantern_light = lantern_node.get_node_or_null(^"LanternLight") as OmniLight3D
	if _lantern_light != null:
		_lantern_light.omni_range = 18.0
		_lantern_light.light_energy = 2.8
	_lantern_flame = lantern_node.get_node_or_null(^"Flame") as Node3D


func _build_supply_props() -> void:
	# Corner wooden supply barrel tied neatly behind the signal mast.
	var barrel := BARREL_PROP_SCENE.instantiate() as Node3D
	barrel.name = "SupplyBarrel"
	barrel.position = Vector3(0.76, 0.18, 0.58)
	barrel.rotation = Vector3(0.04, 0.65, -0.05)
	barrel.scale = Vector3.ONE * 0.72
	for node in barrel.find_children("col_*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi != null:
			mi.visible = false
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(barrel)
	supply_prop = barrel

	# Sculpted salvaged driftwood oar resting diagonally across the aft deck.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var oar_col := Color(0.56, 0.42, 0.25)
	var oar_end := Color(0.66, 0.53, 0.34)
	_append_tapered_log(
		st, Vector3(-1.12, 0.27, 0.78), Vector3(0.32, 0.28, 1.14),
		0.026, 0.022, 7, 4, Vector3.ZERO, oar_col, oar_end, false, 0.3
	)
	var blade_xf := Transform3D(Basis(Vector3.UP, -0.24), Vector3(-1.26, 0.27, 0.74))
	_append_beveled_box_vcol(st, Vector3(0.54, 0.026, 0.16), 0.007, blade_xf, oar_col.lightened(0.08))
	st.generate_normals()
	oar_mesh = _make_mesh_node("DriftwoodOar", st.commit(), _make_vcol_mat(0.84, 0.02))
	add_child(oar_mesh)


func _build_castaway_npc() -> void:
	_castaway_holder = Node3D.new()
	_castaway_holder.name = "CastawayHolder"
	_castaway_holder.position = Vector3(-0.28, 0.21, 0.04)
	_castaway_holder.rotation.y = 0.28
	add_child(_castaway_holder)

	castaway_visual = CharacterVisual.new()
	castaway_visual.name = "CastawayVisual"
	castaway_visual.archetype = &"carpenter"
	_castaway_holder.add_child(castaway_visual)
	castaway_visual.set_tint(CASTAWAY_TINT_PRIMARY, CASTAWAY_TINT_SECONDARY)

	castaway_driver = AnimationDriver.new()
	castaway_driver.name = "CastawayAnimationDriver"
	castaway_driver.manual_mode = true
	castaway_driver.set_process(false)
	_castaway_holder.add_child(castaway_driver)


func _build_rescue_interactable() -> void:
	rescue_interactable = Interactable.create("Rescue Castaway", 1.55)
	rescue_interactable.name = "RescueInteractable"
	rescue_interactable.position = Vector3(0.0, 1.15, 0.0)
	rescue_interactable.reach = RESCUE_REACH
	rescue_interactable.target = self
	rescue_interactable.interacted.connect(_on_rescue_interacted)
	add_child(rescue_interactable)


func _on_rescue_interacted(rescuer: Node) -> void:
	if not Net.is_host() or is_rescued:
		return
	is_rescued = true
	if rescue_interactable != null and is_instance_valid(rescue_interactable):
		rescue_interactable.enabled = false
		rescue_interactable.prompt = "Castaway Rescued"
	rescued.emit(self, rescuer)


# ==============================================================================
# Live wave bobbing, wind pennant, lantern sway & distance-gated castaway wave
# ==============================================================================

func _tick_buoyancy(delta: float) -> void:
	if not auto_buoyancy or not is_inside_tree():
		return
	var wx := global_position.x
	var wz := global_position.z
	var wave_y := Sea.height(wx, wz)
	var n := Sea.normal(wx, wz)
	global_position.y = wave_y + 0.02
	var pitch := clampf(atan2(n.z, maxf(n.y, 0.25)) * 0.65, -0.26, 0.26)
	var roll := clampf(atan2(-n.x, maxf(n.y, 0.25)) * 0.65, -0.26, 0.26)
	var gentle_bob := sin(_clock * 1.45) * 0.035
	var alpha := clampf(delta * 5.5, 0.0, 1.0)
	rotation.x = lerpf(rotation.x, pitch + gentle_bob, alpha)
	rotation.z = lerpf(rotation.z, roll + cos(_clock * 1.18) * 0.032, alpha)


func _tick_pennant_and_lantern() -> void:
	if _pennant_pivot != null and is_instance_valid(_pennant_pivot):
		var wv := Weather.wind_vector()
		var wlen := Vector2(wv.x, wv.z).length()
		var wind_yaw := atan2(-wv.z, wv.x) if wlen > 0.1 else 0.0
		var gust := clampf(wlen / 12.0, 0.35, 1.45)
		var flutter := sin(_clock * (5.2 + gust * 2.2)) * 0.14 * gust
		var snap := sin(_clock * 11.4) * 0.05 * gust
		_pennant_pivot.rotation = Vector3(snap, wind_yaw - global_rotation.y + flutter, flutter * 0.35)

	if _lantern_pivot != null and is_instance_valid(_lantern_pivot):
		var sway_x := -rotation.x * 0.72 + sin(_clock * 2.2) * 0.07
		var sway_z := -rotation.z * 0.72 + cos(_clock * 1.85) * 0.07
		_lantern_pivot.rotation = Vector3(sway_x, 0.0, sway_z)

	var flick := 0.92 + 0.08 * sin(_clock * 10.6) * cos(_clock * 6.9)
	if _lantern_light != null and is_instance_valid(_lantern_light):
		_lantern_light.light_energy = 2.8 * flick
	if _lantern_flame != null and is_instance_valid(_lantern_flame):
		_lantern_flame.scale = Vector3(1.0, 0.90 + 0.16 * sin(_clock * 14.2), 1.0)


func _tick_castaway_animation(delta: float) -> void:
	if castaway_driver == null or not is_instance_valid(castaway_driver):
		return
	if castaway_visual == null or not is_instance_valid(castaway_visual):
		return

	var cam := get_viewport().get_camera_3d() if get_viewport() != null else null
	if cam != null and global_position.distance_squared_to(cam.global_position) > ANIM_DISTANCE_SQ:
		return

	if not _driver_bound:
		if castaway_visual.skeleton == null:
			return
		castaway_driver.bind(castaway_visual)
		castaway_visual.set_tint(CASTAWAY_TINT_PRIMARY, CASTAWAY_TINT_SECONDARY)
		_driver_bound = true

	# Gently orient castaway toward approaching player camera while keeping natural footing.
	if cam != null and _castaway_holder != null and is_instance_valid(_castaway_holder):
		var to_cam := global_transform.affine_inverse() * cam.global_position
		var dist_xz := Vector2(to_cam.x, to_cam.z).length()
		if dist_xz > 1.5 and dist_xz < 48.0:
			var want_yaw := atan2(-to_cam.x, -to_cam.z)
			_castaway_holder.rotation.y = lerp_angle(_castaway_holder.rotation.y, want_yaw, clampf(delta * 2.2, 0.0, 1.0))

	_wave_timer -= delta
	if _wave_timer <= 0.0 and not castaway_driver.is_playing_action():
		castaway_driver.play_action(&"shout", 1.25)
		_wave_timer = _rng.randf_range(2.4, 3.8)

	castaway_driver.demo_grounded = true
	castaway_driver.demo_velocity = Vector3.ZERO
	castaway_driver.demo_look_pitch = 0.06 + sin(_clock * 1.15) * 0.10
	castaway_driver.update_pose(delta)


# ==============================================================================
# Sculpted SurfaceTool geometry helpers (zero primitive placeholder meshes)
# ==============================================================================

static func _make_vcol_mat(roughness: float, metallic: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color.WHITE
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.roughness = roughness
	m.metallic = metallic
	return m


static func _make_mesh_node(node_name: String, mesh: Mesh, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	mi.material_override = mat
	return mi


static func _add_quad_vcol(st: SurfaceTool, top_l: Vector3, top_r: Vector3, bot_r: Vector3, bot_l: Vector3,
		ctl: Color, ctr: Color, cbr: Color, cbl: Color) -> void:
	st.set_color(ctl); st.add_vertex(top_l)
	st.set_color(ctr); st.add_vertex(top_r)
	st.set_color(cbr); st.add_vertex(bot_r)
	st.set_color(ctl); st.add_vertex(top_l)
	st.set_color(cbr); st.add_vertex(bot_r)
	st.set_color(cbl); st.add_vertex(bot_l)


static func _append_tapered_log(
	st: SurfaceTool,
	p_start: Vector3,
	p_end: Vector3,
	r_start: float,
	r_end: float,
	segs: int,
	axial_steps: int,
	crook: Vector3,
	bark_color: Color,
	end_color: Color,
	wet_underside: bool,
	grain_phase: float
) -> void:
	var tang := (p_end - p_start).normalized()
	if tang.length_squared() < 0.0001:
		return
	var ref := Vector3.RIGHT if absf(tang.dot(Vector3.RIGHT)) < 0.85 else Vector3.UP
	var right := tang.cross(ref).normalized()
	var up := right.cross(tang).normalized()

	var rings: Array = []
	var ring_cols: Array = []
	var steps := maxi(axial_steps, 2)
	# Include slightly chamfered bevel rings at both ends for chunky stylized timber silhouette.
	var u_stops: Array[float] = [0.0, 0.035]
	for s in range(1, steps):
		u_stops.append(lerpf(0.04, 0.96, float(s) / float(steps)))
	u_stops.append(0.965)
	u_stops.append(1.0)

	for ui in u_stops.size():
		var u: float = u_stops[ui]
		var center := p_start.lerp(p_end, u) + crook * sin(u * PI)
		var base_r := lerpf(r_start, r_end, u)
		if ui == 0 or ui == u_stops.size() - 1:
			base_r *= 0.82
		var ring: Array = []
		var cols: Array = []
		for k in segs:
			var a := float(k) / float(segs) * TAU
			var organic := 1.0 + 0.055 * sin(u * PI * 3.0 + a * 2.0 + grain_phase)
			var r := base_r * organic
			var pt := center + (right * cos(a) + up * sin(a)) * r
			ring.append(pt)
			var stripe := 0.90 + 0.14 * sin(a * 3.0 + u * 5.0 + grain_phase)
			var c := Color(
				clampf(bark_color.r * stripe, 0.0, 1.0),
				clampf(bark_color.g * stripe, 0.0, 1.0),
				clampf(bark_color.b * stripe, 0.0, 1.0)
			)
			if wet_underside and pt.y < 0.03:
				var wet := clampf((0.03 - pt.y) / 0.16, 0.0, 1.0)
				c = c.darkened(0.32 * wet)
			cols.append(c)
		rings.append(ring)
		ring_cols.append(cols)

	_append_vcol_loft(st, rings, ring_cols, end_color)


static func _append_bamboo_pole(
	st: SurfaceTool,
	p_start: Vector3,
	p_end: Vector3,
	r_start: float,
	r_end: float,
	segs: int,
	knuckles: int,
	crook: Vector3,
	base_color: Color,
	node_color: Color
) -> void:
	var tang := (p_end - p_start).normalized()
	if tang.length_squared() < 0.0001:
		return
	var ref := Vector3.RIGHT if absf(tang.dot(Vector3.RIGHT)) < 0.85 else Vector3.UP
	var right := tang.cross(ref).normalized()
	var up := right.cross(tang).normalized()

	var u_samples: Array[float] = [0.0]
	var r_mults: Array[float] = [0.92]
	var c_blends: Array[float] = [0.35]
	var n_kn := maxi(knuckles, 2)
	for i in range(1, n_kn):
		var uc := float(i) / float(n_kn)
		u_samples.append(maxf(0.02, uc - 0.028))
		r_mults.append(1.0)
		c_blends.append(0.0)
		u_samples.append(uc)
		r_mults.append(1.22)
		c_blends.append(0.85)
		u_samples.append(minf(0.98, uc + 0.028))
		r_mults.append(1.0)
		c_blends.append(0.0)
	u_samples.append(1.0)
	r_mults.append(0.90)
	c_blends.append(0.35)

	var rings: Array = []
	var ring_cols: Array = []
	for idx in u_samples.size():
		var u: float = u_samples[idx]
		var center := p_start.lerp(p_end, u) + crook * sin(u * PI)
		var r := lerpf(r_start, r_end, u) * r_mults[idx]
		var col := base_color.lerp(node_color, c_blends[idx])
		var ring: Array = []
		var cols: Array = []
		for k in segs:
			var a := float(k) / float(segs) * TAU
			ring.append(center + (right * cos(a) + up * sin(a)) * r)
			cols.append(col)
		rings.append(ring)
		ring_cols.append(cols)

	_append_vcol_loft(st, rings, ring_cols, base_color.lightened(0.15))


static func _append_vcol_loft(st: SurfaceTool, rings: Array, ring_cols: Array, cap_color: Color) -> void:
	if rings.size() < 2:
		return
	var ring_len := (rings[0] as Array).size()
	if ring_len < 3:
		return
	for j in range(rings.size() - 1):
		var r0: Array = rings[j]
		var r1: Array = rings[j + 1]
		var c0: Array = ring_cols[j]
		var c1: Array = ring_cols[j + 1]
		for i in ring_len:
			var ni := (i + 1) % ring_len
			_add_quad_vcol(st, r1[ni], r1[i], r0[i], r0[ni], c1[ni], c1[i], c0[i], c0[ni])

	# Saw-cut end caps (outward-wound matching ToolMeshes._append_loft).
	var first: Array = rings[0]
	var fc := Vector3.ZERO
	for p: Vector3 in first:
		fc += p
	fc /= float(ring_len)
	for i in ring_len:
		var ni := (i + 1) % ring_len
		st.set_color(cap_color); st.add_vertex(fc)
		st.set_color(cap_color.darkened(0.08)); st.add_vertex(first[ni])
		st.set_color(cap_color.darkened(0.08)); st.add_vertex(first[i])

	var last: Array = rings[rings.size() - 1]
	var lc := Vector3.ZERO
	for p: Vector3 in last:
		lc += p
	lc /= float(ring_len)
	for i in ring_len:
		var ni := (i + 1) % ring_len
		st.set_color(cap_color); st.add_vertex(lc)
		st.set_color(cap_color.darkened(0.08)); st.add_vertex(last[i])
		st.set_color(cap_color.darkened(0.08)); st.add_vertex(last[ni])


static func _append_beveled_box_vcol(st: SurfaceTool, size: Vector3, bevel: float,
		xform: Transform3D, color: Color) -> void:
	var hx := size.x * 0.5
	var hy := size.y * 0.5
	var hz := size.z * 0.5
	var b := minf(bevel, minf(hx, minf(hy, hz)) * 0.42)
	var ix := maxf(hx - b, 0.0001)
	var iy := maxf(hy - b, 0.0001)
	var iz := maxf(hz - b, 0.0001)
	var ys: PackedFloat32Array = PackedFloat32Array([-hy, -iy, iy, hy])
	var xs: PackedFloat32Array = PackedFloat32Array([ix, hx, hx, ix])
	var zs: PackedFloat32Array = PackedFloat32Array([iz, hz, hz, iz])
	var rings: Array = []
	var ring_cols: Array = []
	for k in 4:
		var y: float = ys[k]
		var rx: float = xs[k]
		var rz: float = zs[k]
		var bx: float = maxf(rx - b * 0.55, rx * 0.72) if (k == 1 or k == 2) else maxf(rx - b * 0.35, rx * 0.80)
		var bz: float = maxf(rz - b * 0.55, rz * 0.72) if (k == 1 or k == 2) else maxf(rz - b * 0.35, rz * 0.80)
		rings.append([
			xform * Vector3(bx, y, -rz),
			xform * Vector3(rx, y, -bz),
			xform * Vector3(rx, y, bz),
			xform * Vector3(bx, y, rz),
			xform * Vector3(-bx, y, rz),
			xform * Vector3(-rx, y, bz),
			xform * Vector3(-rx, y, -bz),
			xform * Vector3(-bx, y, -rz),
		])
		var row_c := color.darkened(0.14) if k == 0 else color
		ring_cols.append([row_c, row_c, row_c, row_c, row_c, row_c, row_c, row_c])
	_append_vcol_loft(st, rings, ring_cols, color)


static func _append_tube(st: SurfaceTool, points: Array[Vector3], radius: float,
		segs: int = 6, close_caps: bool = true) -> void:
	if points.size() < 2:
		return
	var rings: Array = []
	for i in points.size():
		var p := points[i]
		var tang: Vector3
		if i == 0:
			tang = (points[1] - p).normalized()
		elif i == points.size() - 1:
			tang = (p - points[i - 1]).normalized()
		else:
			tang = (points[i + 1] - points[i - 1]).normalized()
		if tang.length_squared() < 0.0001:
			tang = Vector3.UP
		var ref := Vector3.RIGHT if absf(tang.dot(Vector3.RIGHT)) < 0.85 else Vector3.UP
		var right := tang.cross(ref).normalized()
		var up := right.cross(tang).normalized()
		var ring: Array = []
		for k in segs:
			var a := float(k) / float(segs) * TAU
			ring.append(p + (right * cos(a) + up * sin(a)) * radius)
		rings.append(ring)

	var ring_len := (rings[0] as Array).size()
	for j in range(rings.size() - 1):
		var r0: Array = rings[j]
		var r1: Array = rings[j + 1]
		for i in ring_len:
			var ni := (i + 1) % ring_len
			st.add_vertex(r1[ni]); st.add_vertex(r1[i]); st.add_vertex(r0[i])
			st.add_vertex(r1[ni]); st.add_vertex(r0[i]); st.add_vertex(r0[ni])
	if close_caps:
		var first: Array = rings[0]
		var c0 := Vector3.ZERO
		for p: Vector3 in first:
			c0 += p
		c0 /= float(ring_len)
		for i in ring_len:
			var ni := (i + 1) % ring_len
			st.add_vertex(c0); st.add_vertex(first[ni]); st.add_vertex(first[i])
		var last: Array = rings[rings.size() - 1]
		var c1 := Vector3.ZERO
		for p: Vector3 in last:
			c1 += p
		c1 /= float(ring_len)
		for i in ring_len:
			var ni := (i + 1) % ring_len
			st.add_vertex(c1); st.add_vertex(last[i]); st.add_vertex(last[ni])
