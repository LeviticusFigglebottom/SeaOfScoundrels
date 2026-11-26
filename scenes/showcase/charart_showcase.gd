extends Node3D
## Character art & procedural animation showcase.
##
## Usage:
##   tools/capture.sh res://scenes/showcase/charart_showcase.tscn char_lineup 2 5 -- shot=lineup
##
## User args (after `--`):
##   shot=lineup   all 9 archetypes (4 pirates + 4 drowned + tidecaller) in a curved dock lineup
##   shot=pirates  close hero view of Captain, Helmsman, Lookout, Carpenter
##   shot=enemies  moody dusk showcase of Drowned variants & Tidecaller with glowing details
##   shot=poses    live procedural animation gallery (locomotion, stations, carrying, combat & charm)
##   dur=<sec>     camera sweep duration (default 3.0)
##   orbit=<0|1>   slowly orbit camera around subject (default 0 for lineup/poses, 1 for pirates/enemies)
##
## Interactive keys: 1=lineup  2=pirates  3=enemies  4=poses

const PIRATE_ARCHS: Array[StringName] = [&"captain", &"helmsman", &"lookout", &"carpenter"]
const ENEMY_ARCHS: Array[StringName] = [&"drowned_cutlass", &"drowned_shield", &"drowned_powder", &"drowned_captain", &"tidecaller"]
const ALL_ARCHS: Array[StringName] = [
	&"captain", &"helmsman", &"lookout", &"carpenter",
	&"drowned_cutlass", &"drowned_shield", &"drowned_powder", &"drowned_captain", &"tidecaller",
]

var shot: String = "lineup"
var dur: float = 3.0
var orbit: bool = false
var _t: float = 0.0
var _opts: Dictionary = {}

var _stage: Node3D
var _cast_root: Node3D
var _cam: Camera3D
var _sun: DirectionalLight3D
var _fill: DirectionalLight3D
var _env: WorldEnvironment
var _pose_entries: Array[Dictionary] = []


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=")
		if kv.size() == 2:
			_opts[kv[0]] = kv[1]
	shot = String(_opts.get("shot", "lineup"))
	dur = maxf(float(_opts.get("dur", "3.0")), 0.1)
	var default_orbit := "1" if (shot == "pirates" or shot == "enemies") else "0"
	orbit = String(_opts.get("orbit", default_orbit)) == "1"

	_setup_env()
	_build_stage()

	_cast_root = Node3D.new()
	_cast_root.name = "Cast"
	add_child(_cast_root)

	_cam = Camera3D.new()
	_cam.fov = 44.0
	_cam.near = 0.08
	_cam.far = 2000.0
	add_child(_cam)
	_cam.make_current()

	_rebuild_shot()
	_update_camera(0.0)


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var ke := event as InputEventKey
	if not ke.pressed or ke.echo:
		return
	match ke.physical_keycode:
		KEY_1:
			shot = "lineup"
			orbit = false
			_rebuild_shot()
		KEY_2:
			shot = "pirates"
			orbit = true
			_rebuild_shot()
		KEY_3:
			shot = "enemies"
			orbit = true
			_rebuild_shot()
		KEY_4:
			shot = "poses"
			orbit = false
			_rebuild_shot()


func _process(delta: float) -> void:
	_t += delta
	_tick_poses()
	_update_camera(_t)


# ------------------------------------------------------------------ environment & stage

func _setup_env() -> void:
	_env = WorldEnvironment.new()
	_env.name = "WorldEnvironment"
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	sky.sky_material = ProceduralSkyMaterial.new()
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.85
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_white = 4.5
	env.glow_enabled = true
	env.glow_intensity = 0.55
	env.glow_bloom = 0.22
	env.glow_hdr_threshold = 1.05
	_env.environment = env
	add_child(_env)

	_sun = DirectionalLight3D.new()
	_sun.name = "Sun"
	_sun.shadow_enabled = true
	_sun.directional_shadow_max_distance = 45.0
	_sun.shadow_bias = 0.03
	add_child(_sun)

	_fill = DirectionalLight3D.new()
	_fill.name = "RimFill"
	_fill.shadow_enabled = false
	add_child(_fill)


func _apply_lighting(moody: bool) -> void:
	var sm := _env.environment.sky.sky_material as ProceduralSkyMaterial
	if moody:
		# Dusk storm-edge: readable rich indigo/teal sky so glowing eyes, runes & keg pop!
		sm.sky_top_color = Color(0.08, 0.16, 0.28)
		sm.sky_horizon_color = Color(0.30, 0.44, 0.52)
		sm.ground_bottom_color = Color(0.04, 0.10, 0.16)
		sm.ground_horizon_color = Color(0.16, 0.28, 0.34)
		_env.environment.ambient_light_energy = 0.72
		_sun.rotation_degrees = Vector3(-26.0, 146.0, 0.0)
		_sun.light_color = Color(1.0, 0.84, 0.66)
		_sun.light_energy = 1.45
		_fill.rotation_degrees = Vector3(-18.0, -28.0, 0.0)
		_fill.light_color = Color(0.32, 0.78, 0.84)
		_fill.light_energy = 0.75
	else:
		# Crisp golden Caribbean maritime sunlight matching Sea of Scoundrels palette.
		sm.sky_top_color = Color(0.16, 0.44, 0.80)
		sm.sky_horizon_color = Color(0.64, 0.84, 0.96)
		sm.ground_bottom_color = Color(0.05, 0.22, 0.34)
		sm.ground_horizon_color = Color(0.38, 0.68, 0.78)
		_env.environment.ambient_light_energy = 0.92
		_sun.rotation_degrees = Vector3(-36.0, 148.0, 0.0)
		_sun.light_color = Color(1.0, 0.95, 0.85)
		_sun.light_energy = 1.85
		_fill.rotation_degrees = Vector3(-22.0, -32.0, 0.0)
		_fill.light_color = Color(0.55, 0.80, 1.0)
		_fill.light_energy = 0.55


func _build_stage() -> void:
	_stage = Node3D.new()
	_stage.name = "Stage"
	add_child(_stage)

	# Stylized wooden dock planks planted right at y = 0.0 so boots ground crisply.
	var mat_deck := StandardMaterial3D.new()
	mat_deck.albedo_color = Color(0.36, 0.25, 0.16)
	mat_deck.roughness = 0.86

	var mat_beam := StandardMaterial3D.new()
	mat_beam.albedo_color = Color(0.24, 0.16, 0.10)
	mat_beam.roughness = 0.90

	var deck_mesh := BoxMesh.new()
	deck_mesh.size = Vector3(14.5, 0.26, 6.2)
	var deck := MeshInstance3D.new()
	deck.mesh = deck_mesh
	deck.position = Vector3(0.0, -0.13, 0.0)
	deck.material_override = mat_deck
	_stage.add_child(deck)

	# Plank groove accent strips for clear scale & visual texture on deck.
	for i in range(-12, 13):
		var strip := MeshInstance3D.new()
		var sm := BoxMesh.new()
		sm.size = Vector3(14.5, 0.015, 0.025)
		strip.mesh = sm
		strip.position = Vector3(0.0, -0.002, float(i) * 0.25)
		strip.material_override = mat_beam
		_stage.add_child(strip)

	# Low dock curb timber & corner mooring bollards for maritime charm & scale.
	var curb_mesh := BoxMesh.new()
	curb_mesh.size = Vector3(14.6, 0.16, 0.24)
	var curb := MeshInstance3D.new()
	curb.mesh = curb_mesh
	curb.position = Vector3(0.0, 0.08, 3.0)
	curb.material_override = mat_beam
	_stage.add_child(curb)

	for bx in [-6.8, -2.8, 2.8, 6.8]:
		var post := MeshInstance3D.new()
		var pm := CylinderMesh.new()
		pm.top_radius = 0.14
		pm.bottom_radius = 0.16
		pm.height = 0.95
		pm.radial_segments = 10
		post.mesh = pm
		post.position = Vector3(bx, 0.36, 2.95)
		post.material_override = mat_beam
		_stage.add_child(post)

	# Stylized turquoise sea plane below the dock.
	var sea_mesh := PlaneMesh.new()
	sea_mesh.size = Vector2(360.0, 360.0)
	var mat_sea := StandardMaterial3D.new()
	mat_sea.albedo_color = Color(0.06, 0.34, 0.44)
	mat_sea.roughness = 0.28
	var sea := MeshInstance3D.new()
	sea.mesh = sea_mesh
	sea.position = Vector3(0.0, -0.78, 0.0)
	sea.material_override = mat_sea
	_stage.add_child(sea)


# ------------------------------------------------------------------ cast spawning

func _clear_cast() -> void:
	_pose_entries.clear()
	for c in _cast_root.get_children():
		_cast_root.remove_child(c)
		c.queue_free()


func _spawn_character(arch: StringName, pos: Vector3, yaw_deg: float) -> Dictionary:
	var vis := CharacterVisual.new()
	vis.name = "Char_" + String(arch)
	vis.position = pos
	vis.rotation_degrees = Vector3(0.0, yaw_deg, 0.0)
	_cast_root.add_child(vis)
	vis.set_archetype(arch)

	var drv := AnimationDriver.new()
	drv.name = "AnimationDriver"
	drv.manual_mode = true
	vis.add_child(drv)
	drv.bind(vis, null)
	drv.update_pose(0.0, true)

	return {"visual": vis, "driver": drv, "arch": arch}


func _attach_prop_cutlass(vis: CharacterVisual) -> void:
	if vis.hand_right == null:
		return
	var sword := ToolMeshes.build_tool(&"cutlass")
	sword.name = "PropCutlass"
	# Natural forward-down swashbuckler grip aligned along Hand_R palm.
	sword.position = Vector3(0.0, 0.085, -0.02)
	sword.rotation_degrees = Vector3(-18.0, 12.0, -18.0)
	sword.scale = Vector3.ONE * 0.92
	vis.hand_right.add_child(sword)


func _attach_prop_pistol(vis: CharacterVisual) -> void:
	if vis.hand_right == null:
		return
	var pistol := ToolMeshes.build_tool(&"pistol")
	pistol.name = "PropPistol"
	pistol.position = Vector3(0.0, 0.085, -0.025)
	pistol.rotation_degrees = Vector3(-82.0, 0.0, 0.0)
	pistol.scale = Vector3.ONE * 0.95
	vis.hand_right.add_child(pistol)


func _attach_prop_tankard(vis: CharacterVisual) -> void:
	if vis.hand_right == null:
		return
	var mug := ToolMeshes.build_tool(&"tankard")
	mug.name = "PropTankard"
	mug.position = Vector3(0.0, 0.085, -0.02)
	mug.rotation_degrees = Vector3(-15.0, 0.0, 0.0)
	mug.scale = Vector3.ONE * 0.95
	vis.hand_right.add_child(mug)


func _attach_prop_crate(vis: CharacterVisual) -> void:
	if vis.carry_anchor == null:
		return
	var chest_scene: PackedScene = load("res://assets/generated/props/chest_treasure.glb") as PackedScene
	if chest_scene != null:
		var chest := chest_scene.instantiate() as Node3D
		chest.name = "PropChest"
		chest.position = Vector3(0.0, -0.14, 0.02)
		chest.scale = Vector3.ONE * 0.62
		vis.carry_anchor.add_child(chest)
		return
	var crate := MeshInstance3D.new()
	crate.name = "PropCrate"
	var bm := BoxMesh.new()
	bm.size = Vector3(0.42, 0.30, 0.32)
	crate.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.56, 0.36, 0.18)
	mat.roughness = 0.78
	crate.material_override = mat
	vis.carry_anchor.add_child(crate)


func _rebuild_shot() -> void:
	_clear_cast()
	_t = 0.0
	_apply_lighting(shot == "enemies")

	match shot:
		"pirates":
			_build_pirates()
		"enemies":
			_build_enemies()
		"poses":
			_build_poses()
		_:
			_build_lineup()


func _build_lineup() -> void:
	var n := ALL_ARCHS.size()
	var spacing := 1.18
	for i in n:
		var arch := ALL_ARCHS[i]
		var offset := float(i) - float(n - 1) * 0.5
		var x := offset * spacing
		var z := -absf(offset) * 0.16 # gentle theatrical arc facing -Z toward camera!
		var yaw := offset * 5.0
		var entry := _spawn_character(arch, Vector3(x, 0.0, z), yaw)
		var vis: CharacterVisual = entry["visual"]
		var drv: AnimationDriver = entry["driver"]
		if arch == &"captain" or arch == &"drowned_cutlass" or arch == &"drowned_captain" or arch == &"drowned_shield":
			_attach_prop_cutlass(vis)
		if arch == &"captain":
			drv.demo_look_pitch = 0.06
		elif arch == &"drowned_shield":
			drv.hold_action(&"block", 0.35)
		drv.update_pose(0.0, true)
		_pose_entries.append(entry)


func _build_pirates() -> void:
	var n := PIRATE_ARCHS.size()
	var spacing := 1.25
	for i in n:
		var arch := PIRATE_ARCHS[i]
		var offset := float(i) - float(n - 1) * 0.5
		var x := offset * spacing
		var z := -absf(offset) * 0.20
		var yaw := offset * 12.0
		var entry := _spawn_character(arch, Vector3(x, 0.0, z), yaw)
		var vis: CharacterVisual = entry["visual"]
		var drv: AnimationDriver = entry["driver"]
		if arch == &"captain":
			_attach_prop_cutlass(vis)
		elif arch == &"lookout":
			_attach_prop_pistol(vis)
			drv.hold_action(&"aim_pistol", 0.5)
		elif arch == &"carpenter":
			drv.demo_carrying = true
			_attach_prop_crate(vis)
		drv.update_pose(0.0, true)
		_pose_entries.append(entry)


func _build_enemies() -> void:
	var n := ENEMY_ARCHS.size()
	var spacing := 1.28
	for i in n:
		var arch := ENEMY_ARCHS[i]
		var offset := float(i) - float(n - 1) * 0.5
		var x := offset * spacing
		var z := -absf(offset) * 0.22
		var yaw := offset * 10.0
		var entry := _spawn_character(arch, Vector3(x, 0.0, z), yaw)
		var vis: CharacterVisual = entry["visual"]
		var drv: AnimationDriver = entry["driver"]
		if arch == &"drowned_cutlass" or arch == &"drowned_captain" or arch == &"drowned_shield":
			_attach_prop_cutlass(vis)
		if arch == &"drowned_shield":
			drv.hold_action(&"block", 0.45)
		elif arch == &"drowned_captain":
			drv.hold_action(&"shout", 0.48)
		drv.update_pose(0.0, true)
		_pose_entries.append(entry)


func _build_poses() -> void:
	# 8 expressive live poses staggered into clear visual windows (zero back-row occlusion!).
	var specs := [
		{"arch": &"captain", "pos": Vector3(-3.3, 0.0, -0.35), "yaw": -18.0, "kind": "action", "action": &"slash_1", "cutlass": true},
		{"arch": &"lookout", "pos": Vector3(-1.95, 0.0, 0.25), "yaw": -12.0, "kind": "action", "action": &"aim_pistol", "pistol": true},
		{"arch": &"helmsman", "pos": Vector3(-0.65, 0.0, -0.35), "yaw": -4.0, "kind": "station", "station": &"helm"},
		{"arch": &"carpenter", "pos": Vector3(0.65, 0.0, 0.25), "yaw": 6.0, "kind": "carry", "crate": true},
		{"arch": &"captain", "pos": Vector3(1.95, 0.0, -0.35), "yaw": 15.0, "kind": "sprint"},
		{"arch": &"drowned_captain", "pos": Vector3(3.3, 0.0, 0.25), "yaw": 20.0, "kind": "action", "action": &"heavy", "cutlass": true},
		{"arch": &"lookout", "pos": Vector3(-1.3, 0.0, 1.55), "yaw": -8.0, "kind": "action", "action": &"shout"},
		{"arch": &"helmsman", "pos": Vector3(1.3, 0.0, 1.55), "yaw": 10.0, "kind": "action", "action": &"drink", "tankard": true},
	]
	for sp: Dictionary in specs:
		var entry := _spawn_character(sp["arch"] as StringName, sp["pos"] as Vector3, float(sp["yaw"]))
		var vis: CharacterVisual = entry["visual"]
		var drv: AnimationDriver = entry["driver"]
		if sp.get("cutlass", false):
			_attach_prop_cutlass(vis)
		if sp.get("pistol", false):
			_attach_prop_pistol(vis)
		if sp.get("tankard", false):
			_attach_prop_tankard(vis)
		if sp.get("crate", false):
			_attach_prop_crate(vis)
		entry["spec"] = sp
		_configure_pose_entry(entry, 0.5)
		drv.update_pose(0.0, true)
		_pose_entries.append(entry)


func _configure_pose_entry(entry: Dictionary, cycle_u: float) -> void:
	var drv: AnimationDriver = entry["driver"]
	var sp: Dictionary = entry.get("spec", {})
	var kind: String = String(sp.get("kind", "idle"))
	match kind:
		"action":
			var act: StringName = sp["action"]
			drv.hold_action(act, clampf(cycle_u, 0.12, 0.78))
		"station":
			drv.demo_mode = Pawn.Mode.STATION
			drv.demo_station_kind = sp["station"] as StringName
		"carry":
			drv.demo_mode = Pawn.Mode.WALK
			drv.demo_carrying = true
			drv.demo_velocity = Vector3(0.0, 0.0, -2.4)
		"sprint":
			drv.demo_mode = Pawn.Mode.WALK
			drv.demo_sprint = true
			drv.demo_velocity = Vector3(0.0, 0.0, -5.6)


func _tick_poses() -> void:
	if shot != "poses":
		return
	var u := 0.25 + 0.52 * (0.5 + 0.5 * sin(_t * 2.2))
	for i in _pose_entries.size():
		var entry := _pose_entries[i]
		var sp: Dictionary = entry.get("spec", {})
		if String(sp.get("kind", "")) == "action":
			var phase := fmod(_t * 0.85 + float(i) * 0.17, 1.0)
			var act: StringName = sp["action"]
			var drv: AnimationDriver = entry["driver"]
			if act == &"aim_pistol" or act == &"shout" or act == &"drink":
				drv.hold_action(act, u)
			else:
				drv.hold_action(act, 0.14 + phase * 0.62)


# ------------------------------------------------------------------ scripted cameras

func _update_camera(time_s: float) -> void:
	var u := clampf(time_s / dur, 0.0, 1.0)
	var eye := Vector3(0.0, 1.65, -7.8)
	var look := Vector3(0.0, 1.02, 0.0)

	match shot:
		"lineup":
			var x_sweep := lerpf(-1.6, 1.6, u)
			eye = Vector3(x_sweep, 1.72, -9.2)
			look = Vector3(x_sweep * 0.35, 1.02, -0.2)
		"pirates":
			var ang := lerpf(-0.42, 0.42, u) if orbit else -0.14
			var rad := 4.45
			eye = Vector3(sin(ang) * rad, 1.56, -cos(ang) * rad)
			look = Vector3(0.0, 1.06, -0.1)
		"enemies":
			var ang := lerpf(-0.46, 0.46, u) if orbit else 0.12
			var rad := 5.45
			eye = Vector3(sin(ang) * rad, 1.62, -cos(ang) * rad)
			look = Vector3(0.0, 1.06, -0.15)
		"poses":
			var x_sweep := lerpf(-1.2, 1.2, u)
			eye = Vector3(x_sweep, 2.05, -6.9)
			look = Vector3(x_sweep * 0.3, 0.98, 0.35)

	_cam.global_position = eye
	_cam.look_at(look, Vector3.UP)
