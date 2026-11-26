extends Node3D
## Visual verification showcase for sculpted 3D island landmarks (12 PBR GLBs)
## and batched MultiMesh `IslandDetails` ground foliage, coastal details &
## steep-slope cliff buttresses using the real `SkyRig`, `Ocean` & `Archipelago`.
##
## Usage:
##   tools/capture.sh res://scenes/showcase/island_landmarks_showcase.tscn cutlass_overhaul 2 5 -- shot=cutlass_overhaul
##
## User args (after `--`), all optional:
##   shot=gallery_geology|gallery_setpieces|cutlass_overhaul|skull_bluff  (default cutlass_overhaul)
##   time=<hour>       hour of day (auto per-shot sunlit / golden-hour default)
##   storm=<0..1>      storminess (default 0.0)
##   cloud=<0..1>      cloudiness (default 0.30)
##   quality=low|medium|high   Ocean & sky cloud quality (default medium sky / high ocean)
##   scale=<0.25..1>   3D render scale
##   clock=<seconds>   starting pan clock
##   t=<seconds>       initial Sea.time (default 36.0)
##
## Interactive keys: 1=gallery_geology  2=gallery_setpieces  3=cutlass_overhaul  4=skull_bluff

const IslandDetailsCls := preload("res://src/world/island_details.gd")
const LANDMARK_DIR := "res://assets/generated/landmarks/"

const DETAIL_ISLAND_IDS: Array[String] = [
	"cutlass_cay",
	"skull_bluff",
	"emerald_spire",
	"cinder_crag",
	"port_scoundrel",
	"sovereigns_bastion",
	"galleons_reach",
]

const GEOLOGY_GLBS: Array[String] = [
	"cliff_buttress_tall.glb",
	"cliff_buttress_wide.glb",
	"cliff_overhang_ledge.glb",
	"coastal_sea_arch.glb",
	"volcanic_basalt_spire.glb",
	"mossy_cliff_boulder_cluster.glb",
]

const SETPIECE_BACK_GLBS: Array[String] = [
	"cliff_catwalk_pier.glb",
	"ancient_temple_stairway.glb",
	"skull_cliff_carving.glb",
	"impaled_shipwreck_bow.glb",
]

const SETPIECE_FRONT_GLBS: Array[String] = [
	"trail_lantern_post.glb",
	"stone_cairn_marker.glb",
]

## Open sunlit tropical water well clear of all 14 archipelago islands for gallery staging.
const GALLERY_ORIGIN := Vector3(380.0, 0.0, 260.0)

var _args: Dictionary = {}
var _shot: String = "cutlass_overhaul"
var _clock: float = 0.0
var _cam: Camera3D = null
var _archipelago: Archipelago = null
var _cutlass: Island = null
var _skull_bluff: Island = null

var _gallery_root: Node3D = null
var _gallery_stage_mi: MeshInstance3D = null
var _gallery_stage_mesh: ArrayMesh = null
var _gallery_stage_mat: StandardMaterial3D = null
var _gallery_bounds: AABB = AABB(Vector3(-25.0, 0.0, -10.0), Vector3(50.0, 18.0, 20.0))

var _landmark_scenes: Dictionary = {}  # filename -> PackedScene
var _flicker_lights: Array[Dictionary] = []

var _cutlass_hero_aim: Vector3 = Vector3.ZERO
var _skull_hero_aim: Vector3 = Vector3.ZERO
var _skull_wreck_world: Vector3 = Vector3.ZERO


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		if kv.size() == 2:
			_args[kv[0]] = kv[1]
	_shot = String(_args.get("shot", "cutlass_overhaul"))
	_clock = float(_args.get("clock", "0.0"))

	Net.start_single_player()
	Weather.day_length_seconds = 0.0
	Weather.lightning_enabled = false
	Weather.clear_storm_cell()

	_apply_shot_weather()

	var sky_rig := get_node_or_null(^"SkyRig")
	if sky_rig != null:
		var q_str := String(_args.get("quality", "medium"))
		sky_rig.set(&"cloud_quality", {"low": 0, "medium": 1, "high": 2}.get(q_str, 1))
		sky_rig.set(&"shadow_distance", 320.0)

	var ocean := get_node_or_null(^"Ocean") as Ocean
	if ocean != null:
		var oq_str := String(_args.get("quality", "high"))
		ocean.quality = {"low": Ocean.Quality.LOW, "medium": Ocean.Quality.MEDIUM}.get(oq_str, Ocean.Quality.HIGH)

	# Build real 14-island deterministic archipelago.
	_archipelago = Archipelago.new()
	_archipelago.name = "Archipelago"
	add_child(_archipelago)

	_cutlass = _archipelago.get_island_by_id("cutlass_cay")
	_skull_bluff = _archipelago.get_island_by_id("skull_bluff")

	# Populate live batched IslandDetails across flagship & hero showcase islands.
	for isl_id in DETAIL_ISLAND_IDS:
		var isl := _archipelago.get_island_by_id(isl_id)
		if isl == null:
			continue
		if isl.get_node_or_null(^"IslandDetails") == null:
			IslandDetailsCls.populate_for_island(isl, isl.archetype, isl.island_id.hash() ^ 0x51A7)

	# Stage Cutlass Cay & Skull Bluff hero landmarks onto real island terrain.
	_stage_cutlass_landmarks()
	_stage_skull_bluff_landmarks()

	# Stage sunlit open-water gallery sandbar for gallery shots.
	_gallery_root = Node3D.new()
	_gallery_root.name = "LandmarkGallery"
	_gallery_root.position = GALLERY_ORIGIN
	add_child(_gallery_root)
	_rebuild_gallery_for_shot()

	_cam = Camera3D.new()
	_cam.fov = 56.0
	_cam.near = 0.12
	_cam.far = 4500.0
	add_child(_cam)
	_cam.make_current()

	if _args.has("scale"):
		get_viewport().scaling_3d_scale = float(_args["scale"])

	_update_camera()
	Weather.set_focus(_cam.global_position)


func _exit_tree() -> void:
	_flicker_lights.clear()
	_landmark_scenes.clear()
	if _gallery_stage_mi != null and is_instance_valid(_gallery_stage_mi):
		_gallery_stage_mi.material_override = null
		_gallery_stage_mi.mesh = null
	_gallery_stage_mi = null
	_gallery_stage_mesh = null
	_gallery_stage_mat = null
	_gallery_root = null
	_archipelago = null
	_cutlass = null
	_skull_bluff = null
	_cam = null


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var ke := event as InputEventKey
	if not ke.pressed or ke.echo:
		return
	var next_shot := ""
	match ke.physical_keycode:
		KEY_1:
			next_shot = "gallery_geology"
		KEY_2:
			next_shot = "gallery_setpieces"
		KEY_3:
			next_shot = "cutlass_overhaul"
		KEY_4:
			next_shot = "skull_bluff"
	if next_shot != "" and next_shot != _shot:
		_shot = next_shot
		_clock = 0.0
		_apply_shot_weather()
		_rebuild_gallery_for_shot()
		_update_camera()


func _process(delta: float) -> void:
	_clock += delta
	for entry in _flicker_lights:
		var light := entry.get("light") as OmniLight3D
		if light == null or not is_instance_valid(light):
			continue
		var base_e := float(entry["base_energy"])
		var amp := float(entry["amp"])
		var phase := float(entry["phase"])
		var wave := sin(_clock * 5.2 + phase) * 0.6 + sin(_clock * 11.4 + phase * 1.7) * 0.4
		light.light_energy = maxf(0.2, base_e * (1.0 + wave * amp))
	_update_camera()


# ------------------------------------------------------------------ weather & shot setup

func _apply_shot_weather() -> void:
	var default_time := 10.4
	match _shot:
		"gallery_geology":
			default_time = 10.2
		"gallery_setpieces":
			default_time = 15.6
		"cutlass_overhaul":
			default_time = 10.4
		"skull_bluff":
			default_time = 16.0
	var default_cloud := 0.30 if _shot.begins_with("gallery_") else 0.34
	Weather.time_of_day = float(_args.get("time", str(default_time)))
	var storm := float(_args.get("storm", "0.0"))
	var cloud := float(_args.get("cloud", str(default_cloud)))
	Weather.set_weather(storm, 8.2, deg_to_rad(30.0), 0.0, cloud)
	Weather.cloud_offset = Vector2(240.0, 120.0)

	Sea.amp_scale = lerpf(Sea.AMP_CALM, Sea.AMP_STORM, storm)
	if _shot.begins_with("gallery_"):
		Sea.amp_scale = 0.28
	elif _shot == "cutlass_overhaul":
		Sea.amp_scale = 0.48
	Sea.time = float(_args.get("t", "36.0"))


# ------------------------------------------------------------------ landmark loading & stripping

func _load_landmark_scene(filename: String) -> PackedScene:
	if _landmark_scenes.has(filename):
		return _landmark_scenes[filename] as PackedScene
	var path := LANDMARK_DIR + filename
	if not ResourceLoader.exists(path):
		return null
	var packed := load(path) as PackedScene
	if packed != null:
		_landmark_scenes[filename] = packed
	return packed


func _spawn_landmark(filename: String, parent: Node3D, node_name: String,
		local_xform: Transform3D, register_island: Island = null,
		mount_lights: bool = true) -> Node3D:
	var packed := _load_landmark_scene(filename)
	if packed == null or parent == null:
		return null
	var inst := packed.instantiate() as Node3D
	if inst == null:
		return null
	inst.name = node_name
	inst.transform = local_xform
	parent.add_child(inst)

	# Strip all col_* collider visuals cleanly so zero debug boxes render.
	for c_node in inst.find_children("col_*", "MeshInstance3D", true, false):
		var cmi := c_node as MeshInstance3D
		if cmi != null:
			cmi.visible = false
			cmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var p := cmi.get_parent()
			if p != null:
				p.remove_child(cmi)
			cmi.free()

	if mount_lights:
		_mount_landmark_lanterns(inst, register_island)
	return inst


func _mount_landmark_lanterns(inst: Node3D, register_island: Island) -> void:
	var idx := 0
	for n in inst.find_children("Lantern_*", "Node3D", true, false):
		var marker := n as Node3D
		if marker == null:
			continue
		var is_skull_eye := marker.name.begins_with("Lantern_SkullEye")
		var light := OmniLight3D.new()
		light.name = "Glow_" + marker.name
		light.shadow_enabled = false
		if is_skull_eye:
			light.light_color = Color(0.18, 0.96, 0.80)
			light.light_energy = 4.6
			light.omni_range = 18.0
			light.omni_attenuation = 1.25
		else:
			light.light_color = Color(1.0, 0.66, 0.24)
			light.light_energy = 3.4
			light.omni_range = 14.0
			light.omni_attenuation = 1.35
		marker.add_child(light)
		var amp := 0.12 if is_skull_eye else 0.18
		var phase := float(idx) * 1.7 + float(marker.name.hash() % 64) * 0.1
		if register_island != null:
			register_island.register_flicker_light(light, light.light_energy, amp, phase)
		else:
			_flicker_lights.append({
				"light": light,
				"base_energy": light.light_energy,
				"amp": amp,
				"phase": phase,
			})
		idx += 1


func _relative_transform(node: Node3D, ancestor: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var cur: Node = node
	while cur != null and cur != ancestor:
		if cur is Node3D:
			xf = (cur as Node3D).transform * xf
		cur = cur.get_parent()
	return xf


func _compute_visual_aabb(root: Node3D) -> AABB:
	var has_box := false
	var combined := AABB()
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi == null or not mi.visible or mi.mesh == null or mi.name.begins_with("col_"):
			continue
		var local_box := mi.mesh.get_aabb()
		var rel_xf := _relative_transform(mi, root)
		for ci in 8:
			var pt := rel_xf * local_box.get_endpoint(ci)
			if not has_box:
				combined = AABB(pt, Vector3.ZERO)
				has_box = true
			else:
				combined = combined.expand(pt)
	if not has_box:
		return AABB(Vector3(-2.0, 0.0, -2.0), Vector3(4.0, 4.0, 4.0))
	return combined


# ------------------------------------------------------------------ sunlit gallery sandbar & lineups

func _clear_gallery() -> void:
	if _gallery_root == null:
		return
	_flicker_lights.clear()
	for child in _gallery_root.get_children():
		if child == _gallery_stage_mi:
			continue
		child.queue_free()


func _ensure_gallery_sandbar() -> void:
	if _gallery_stage_mi != null and is_instance_valid(_gallery_stage_mi):
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var half_x := 64.0
	var half_z := 28.0
	var seg_x := 44
	var seg_z := 22

	var col_dry := Color(0.91, 0.82, 0.61)
	var col_warm := Color(0.84, 0.72, 0.49)
	var col_wet := Color(0.62, 0.54, 0.37)
	var col_shallow := Color(0.24, 0.62, 0.58)

	var grid_pts: Array[Vector3] = []
	var grid_cols: Array[Color] = []
	var stride := seg_x + 1
	grid_pts.resize((seg_z + 1) * stride)
	grid_cols.resize((seg_z + 1) * stride)

	for iz in seg_z + 1:
		var vz := (float(iz) / float(seg_z)) * 2.0 - 1.0
		var z := vz * half_z
		for ix in seg_x + 1:
			var vx := (float(ix) / float(seg_x)) * 2.0 - 1.0
			var x := vx * half_x
			var ell := sqrt(vx * vx * 0.94 + vz * vz * 1.18)
			var ripple := sin(x * 0.19 + z * 0.14) * 0.12 + cos(x * 0.11 - z * 0.23) * 0.09
			var plateau := 1.0 - smoothstep(0.64, 1.04, ell)
			var y := lerpf(-4.6, 1.18 + ripple * 0.35, plateau)
			if ell < 0.72:
				y = maxf(y, 1.05 + ripple * 0.18)
			var col := col_dry
			if y > 0.75:
				col = col_warm.lerp(col_dry, clampf((y - 0.75) / 0.45, 0.0, 1.0))
			elif y > 0.0:
				col = col_wet.lerp(col_warm, clampf(y / 0.75, 0.0, 1.0))
			else:
				col = col_shallow.lerp(col_wet, clampf((y + 2.6) / 2.6, 0.0, 1.0))
			var k := iz * stride + ix
			grid_pts[k] = Vector3(x, y, z)
			grid_cols[k] = col

	for iz in seg_z:
		for ix in seg_x:
			var i00 := iz * stride + ix
			var i10 := i00 + 1
			var i01 := (iz + 1) * stride + ix
			var i11 := i01 + 1
			for tri_idx in [i00, i10, i11, i00, i11, i01]:
				st.set_color(grid_cols[tri_idx])
				st.add_vertex(grid_pts[tri_idx])

	st.generate_normals()
	_gallery_stage_mesh = st.commit()

	_gallery_stage_mat = StandardMaterial3D.new()
	_gallery_stage_mat.vertex_color_use_as_albedo = true
	_gallery_stage_mat.vertex_color_is_srgb = true
	_gallery_stage_mat.roughness = 0.90
	_gallery_stage_mat.metallic = 0.0

	_gallery_stage_mi = MeshInstance3D.new()
	_gallery_stage_mi.name = "GallerySandbar"
	_gallery_stage_mi.mesh = _gallery_stage_mesh
	_gallery_stage_mi.material_override = _gallery_stage_mat
	_gallery_stage_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_gallery_root.add_child(_gallery_stage_mi)


func _sandbar_y(lx: float, lz: float) -> float:
	var vx := lx / 64.0
	var vz := lz / 28.0
	var ell := sqrt(vx * vx * 0.94 + vz * vz * 1.18)
	var plateau := 1.0 - smoothstep(0.64, 1.04, ell)
	var y := lerpf(-4.6, 1.15, plateau)
	if ell < 0.72:
		y = maxf(y, 1.05)
	return y


func _rebuild_gallery_for_shot() -> void:
	_clear_gallery()
	if _gallery_root == null:
		return
	var is_gallery := _shot == "gallery_geology" or _shot == "gallery_setpieces"
	_gallery_root.visible = is_gallery
	if not is_gallery:
		return

	_ensure_gallery_sandbar()

	if _shot == "gallery_geology":
		_layout_geology_gallery()
	else:
		_layout_setpieces_gallery()


func _layout_geology_gallery() -> void:
	var items: Array[Dictionary] = []
	var total_span := 0.0
	var gap := 3.4
	for i in GEOLOGY_GLBS.size():
		var fn := GEOLOGY_GLBS[i]
		var inst := _spawn_landmark(fn, _gallery_root, "Geo_%02d" % i, Transform3D.IDENTITY, null, true)
		if inst == null:
			continue
		var bb := _compute_visual_aabb(inst)
		var footprint_w := maxf(bb.size.x, bb.size.z * 0.72)
		footprint_w = clampf(footprint_w, 4.0, 22.0)
		items.append({"node": inst, "aabb": bb, "width": footprint_w, "file": fn})
		total_span += footprint_w
	if items.is_empty():
		return
	total_span += gap * float(maxi(0, items.size() - 1))

	var cursor_x := -total_span * 0.5
	var bounds := AABB()
	var has_bounds := false
	for i in items.size():
		var entry := items[i]
		var inst := entry["node"] as Node3D
		var bb: AABB = entry["aabb"]
		var w := float(entry["width"])
		var fn := String(entry["file"])
		var cx := cursor_x + w * 0.5
		cursor_x += w + gap

		var t_norm := cx / maxf(total_span * 0.5, 1.0)
		var cz := -4.5 + t_norm * t_norm * 5.0
		if fn == "coastal_sea_arch.glb":
			cz += 2.5
		elif fn == "mossy_cliff_boulder_cluster.glb":
			cz += 5.5
		var ground_y := _sandbar_y(cx, cz) - 0.12
		var yaw := PI - t_norm * 0.22
		if fn == "cliff_overhang_ledge.glb":
			yaw += 0.34
		var center_off := Vector3(bb.get_center().x, 0.0, bb.get_center().z)
		var rot := Basis(Vector3.UP, yaw)
		# All landmarks author y = 0.0 as their ground/waterline datum with anchor skirts below y = 0.
		var pos := Vector3(cx, ground_y, cz) - rot * center_off
		inst.transform = Transform3D(rot, pos)

		var world_bb := _compute_visual_aabb(inst)
		for ci in 8:
			var pt := inst.transform * world_bb.get_endpoint(ci)
			pt.y = maxf(pt.y, 0.0)
			if not has_bounds:
				bounds = AABB(pt, Vector3.ZERO)
				has_bounds = true
			else:
				bounds = bounds.expand(pt)

	if has_bounds:
		_gallery_bounds = bounds


func _layout_setpieces_gallery() -> void:
	var back_items: Array[Dictionary] = []
	var total_span := 0.0
	var gap := 4.0
	for i in SETPIECE_BACK_GLBS.size():
		var fn := SETPIECE_BACK_GLBS[i]
		var inst := _spawn_landmark(fn, _gallery_root, "SetBack_%02d" % i, Transform3D.IDENTITY, null, true)
		if inst == null:
			continue
		var bb := _compute_visual_aabb(inst)
		var footprint_w := clampf(maxf(bb.size.x, bb.size.z * 0.72), 5.0, 22.0)
		back_items.append({"node": inst, "aabb": bb, "width": footprint_w, "file": fn})
		total_span += footprint_w
	total_span += gap * float(maxi(0, back_items.size() - 1))

	var bounds := AABB()
	var has_bounds := false
	var cursor_x := -total_span * 0.5
	for i in back_items.size():
		var entry := back_items[i]
		var inst := entry["node"] as Node3D
		var bb: AABB = entry["aabb"]
		var w := float(entry["width"])
		var fn := String(entry["file"])
		var cx := cursor_x + w * 0.5
		cursor_x += w + gap

		var t_norm := cx / maxf(total_span * 0.5, 1.0)
		var cz := -5.5 + t_norm * t_norm * 4.0
		if fn == "impaled_shipwreck_bow.glb":
			cz += 2.2
		var ground_y := _sandbar_y(cx, cz) - 0.12
		var yaw := PI - t_norm * 0.24
		if fn == "cliff_catwalk_pier.glb":
			yaw += 0.30
		var center_off := Vector3(bb.get_center().x, 0.0, bb.get_center().z)
		var rot := Basis(Vector3.UP, yaw)
		var pos := Vector3(cx, ground_y, cz) - rot * center_off
		inst.transform = Transform3D(rot, pos)

		var local_bb := _compute_visual_aabb(inst)
		for ci in 8:
			var pt := inst.transform * local_bb.get_endpoint(ci)
			pt.y = maxf(pt.y, 0.0)
			if not has_bounds:
				bounds = AABB(pt, Vector3.ZERO)
				has_bounds = true
			else:
				bounds = bounds.expand(pt)

	# Place compact trail props cleanly in sunlit foreground gaps so their PBR detail & lantern pop!
	var front_xs: Array[float] = [-maxf(total_span * 0.16, 6.5), maxf(total_span * 0.16, 6.5)]
	for j in SETPIECE_FRONT_GLBS.size():
		var fn := SETPIECE_FRONT_GLBS[j]
		var inst := _spawn_landmark(fn, _gallery_root, "SetFront_%02d" % j, Transform3D.IDENTITY, null, true)
		if inst == null:
			continue
		var bb := _compute_visual_aabb(inst)
		var cx := front_xs[j]
		var cz := 7.8
		var ground_y := _sandbar_y(cx, cz)
		var yaw := PI + (0.25 if j == 0 else -0.22)
		var rot := Basis(Vector3.UP, yaw)
		var center_off := Vector3(bb.get_center().x, 0.0, bb.get_center().z)
		var pos := Vector3(cx, ground_y, cz) - rot * center_off
		inst.transform = Transform3D(rot, pos)

		var local_bb := _compute_visual_aabb(inst)
		for ci in 8:
			var pt := inst.transform * local_bb.get_endpoint(ci)
			pt.y = maxf(pt.y, 0.0)
			if not has_bounds:
				bounds = AABB(pt, Vector3.ZERO)
				has_bounds = true
			else:
				bounds = bounds.expand(pt)

	if has_bounds:
		_gallery_bounds = bounds


# ------------------------------------------------------------------ hero island landmark staging

func _find_terrain_point(isl: Island, frame_basis: Basis, u_vals: Array[float],
		v_start: float, v_end: float, v_step: float,
		h_min: float, h_max: float, ny_min: float, ny_max: float) -> Dictionary:
	var best_pos := Vector3.ZERO
	var best_nrm := Vector3.UP
	var best_score := -INF
	var found := false

	for u in u_vals:
		var v := v_start
		while (v_step > 0.0 and v <= v_end) or (v_step < 0.0 and v >= v_end):
			var lp := frame_basis * Vector3(u, 0.0, v)
			var h := isl.surface_height(lp.x, lp.z)
			if h >= h_min and h <= h_max:
				var nrm := isl.surface_normal(lp.x, lp.z, 2.0)
				if nrm.y >= ny_min and nrm.y <= ny_max:
					var mid_h := (h_min + h_max) * 0.5
					var score := -absf(h - mid_h) * 0.4 - absf(u) * 0.08
					if score > best_score:
						best_score = score
						best_pos = Vector3(lp.x, h, lp.z)
						best_nrm = nrm
						found = true
			v += v_step
	return {"found": found, "pos": best_pos, "normal": best_nrm}


func _stage_cutlass_landmarks() -> void:
	if _cutlass == null:
		return
	var lm_root := Node3D.new()
	lm_root.name = "ShowcaseLandmarks"
	_cutlass.add_child(lm_root)

	var cc_yaw := 2.77
	var cc_basis := Basis(Vector3.UP, cc_yaw)
	_cutlass_hero_aim = _cutlass.global_position + cc_basis * Vector3(1.5, 9.5, 2.0)

	# 1. Coastal sea arch straddling the turquoise surf on Cutlass Cay's port cove flank.
	var arch_hit := _find_terrain_point(_cutlass, cc_basis,
		[-34.0, -30.0, -38.0, -26.0], -38.0, -8.0, 2.0, -1.2, 1.2, 0.65, 1.0)
	var arch_pos := arch_hit["pos"] as Vector3 if bool(arch_hit["found"]) else cc_basis * Vector3(-31.0, -0.3, -22.0)
	arch_pos.y = maxf(arch_pos.y, -0.9) - 0.55
	_spawn_landmark("coastal_sea_arch.glb", lm_root, "CutlassSeaArch",
		Transform3D(Basis(Vector3.UP, cc_yaw + 0.58), arch_pos), _cutlass, true)

	# 2. Cliff overhang ledge embedded into the steep limestone face overlooking the golden cove.
	var ledge_hit := _find_terrain_point(_cutlass, cc_basis,
		[6.0, 12.0, -4.0, 16.0, -10.0], -14.0, 22.0, 2.0, 10.5, 22.0, 0.15, 0.72)
	if bool(ledge_hit["found"]):
		var lp := ledge_hit["pos"] as Vector3
		var ln := ledge_hit["normal"] as Vector3
		var h_dir := Vector3(ln.x, 0.0, ln.z)
		if h_dir.length_squared() < 0.01:
			h_dir = cc_basis * Vector3(0.0, 0.0, -1.0)
		else:
			h_dir = h_dir.normalized()
		var ledge_yaw := atan2(-h_dir.x, -h_dir.z)
		var embed_pos := lp - h_dir * 1.8 - Vector3(0.0, 0.6, 0.0)
		_spawn_landmark("cliff_overhang_ledge.glb", lm_root, "CutlassOverhangLedge",
			Transform3D(Basis(Vector3.UP, ledge_yaw), embed_pos), _cutlass, true)

	# 3. Trail lantern post along the sunlit golden cove trail (with warm live lantern light).
	var lantern_hit := _find_terrain_point(_cutlass, cc_basis,
		[-6.0, -9.0, -3.0, -12.0], -34.0, -8.0, 1.5, 2.0, 4.0, 0.85, 1.0)
	var lantern_pos := lantern_hit["pos"] as Vector3 if bool(lantern_hit["found"]) else cc_basis * Vector3(-7.0, 2.5, -22.0)
	lantern_pos.y = _cutlass.surface_height(lantern_pos.x, lantern_pos.z) - 0.12
	_spawn_landmark("trail_lantern_post.glb", lm_root, "CutlassTrailLantern",
		Transform3D(Basis(Vector3.UP, cc_yaw - 0.35), lantern_pos), _cutlass, true)

	# 4. Stone cairn marker flanking the opposite side of the landing beach trail.
	var cairn_hit := _find_terrain_point(_cutlass, cc_basis,
		[7.0, 10.0, 4.0, 13.0], -34.0, -8.0, 1.5, 2.1, 4.2, 0.85, 1.0)
	var cairn_pos := cairn_hit["pos"] as Vector3 if bool(cairn_hit["found"]) else cc_basis * Vector3(8.0, 2.6, -21.0)
	cairn_pos.y = _cutlass.surface_height(cairn_pos.x, cairn_pos.z) - 0.10
	_spawn_landmark("stone_cairn_marker.glb", lm_root, "CutlassStoneCairn",
		Transform3D(Basis(Vector3.UP, cc_yaw + 0.42), cairn_pos), _cutlass, true)


func _stage_skull_bluff_landmarks() -> void:
	if _skull_bluff == null:
		return
	var lm_root := Node3D.new()
	lm_root.name = "ShowcaseLandmarks"
	_skull_bluff.add_child(lm_root)

	var sb_yaw := 2.35
	var sb_basis := Basis(Vector3.UP, sb_yaw)

	# 1. Colossal glowing-eyed skull carving embedded boldly into Skull Bluff's high seaward cliff face!
	var skull_hit := _find_terrain_point(_skull_bluff, sb_basis,
		[0.0, -5.0, 5.0, -10.0, 10.0], -78.0, 18.0, 2.5, 22.0, 44.0, 0.05, 0.78)
	var skull_pos := skull_hit["pos"] as Vector3 if bool(skull_hit["found"]) else sb_basis * Vector3(0.0, 28.0, -34.0)
	var sea_dir := (sb_basis * Vector3(0.0, 0.0, -1.0)).normalized()
	# Embed rear cranium snugly into the limestone cliff wall while face looks straight seaward.
	var skull_mount := skull_pos - sea_dir * 3.2 - Vector3(0.0, 2.5, 0.0)
	var skull_inst := _spawn_landmark("skull_cliff_carving.glb", lm_root, "SkullBluffCarving",
		Transform3D(Basis(Vector3.UP, sb_yaw).scaled(Vector3.ONE * 1.45), skull_mount), _skull_bluff, true)
	if skull_inst != null:
		var sbb := _compute_visual_aabb(skull_inst)
		_skull_hero_aim = _skull_bluff.global_position + skull_inst.transform * sbb.get_center()
	else:
		_skull_hero_aim = _skull_bluff.global_position + skull_pos

	# 2. Impaled shipwreck bow on the seaward fore-shoal with warm glowing wreck lantern!
	var wreck_hit := _find_terrain_point(_skull_bluff, sb_basis,
		[-24.0, -30.0, -18.0, 24.0, 30.0], -128.0, -52.0, 2.5, -0.7, 1.4, 0.72, 1.0)
	var wreck_pos := wreck_hit["pos"] as Vector3 if bool(wreck_hit["found"]) else sb_basis * Vector3(-24.0, 0.3, -96.0)
	wreck_pos.y = maxf(_skull_bluff.surface_height(wreck_pos.x, wreck_pos.z), -0.35) - 0.35
	_spawn_landmark("impaled_shipwreck_bow.glb", lm_root, "SkullForeShoalWreck",
		Transform3D(Basis(Vector3.UP, sb_yaw + 0.62), wreck_pos), _skull_bluff, true)
	_skull_wreck_world = _skull_bluff.global_position + wreck_pos


# ------------------------------------------------------------------ camera choreography

func _update_camera() -> void:
	if _cam == null:
		return

	match _shot:
		"gallery_geology", "gallery_setpieces":
			var ctr := GALLERY_ORIGIN + _gallery_bounds.get_center()
			var span_x := maxf(_gallery_bounds.size.x, 30.0)
			var span_y := maxf(_gallery_bounds.size.y, 10.0)
			var dist := clampf(maxf(span_x * 0.72, span_y * 1.95), 24.0, 72.0)
			var pan := sin(_clock * 0.35) * (span_x * 0.08)
			var eye := Vector3(ctr.x + pan, maxf(4.8, ctr.y + span_y * 0.18), ctr.z + dist)
			var aim := Vector3(ctr.x, maxf(2.2, ctr.y - span_y * 0.04), ctr.z)
			_cam.fov = 50.0
			_cam.look_at_from_position(eye, aim)

		"cutlass_overhaul":
			if _cutlass == null:
				return
			var cc_pos := _cutlass.global_position
			var cc_basis := Basis(Vector3.UP, 2.77)
			var sweep := clampf(_clock * 0.22, 0.0, 1.0)
			var pan := sin(_clock * 0.42) * 5.0
			var eye := cc_pos + cc_basis * Vector3(-16.0 + pan, lerpf(11.5, 5.2, sweep), lerpf(-58.0, -38.0, sweep))
			var aim := cc_pos + cc_basis * Vector3(1.5, lerpf(10.0, 5.6, sweep), lerpf(2.0, -10.0, sweep))
			_cam.fov = 58.0
			_cam.look_at_from_position(eye, aim)

		"skull_bluff":
			if _skull_bluff == null:
				return
			var sb_pos := _skull_bluff.global_position
			var sb_basis := Basis(Vector3.UP, 2.35)
			var pan := sin(_clock * 0.32) * 7.0
			var eye := sb_pos + sb_basis * Vector3(-26.0 + pan, 17.5, -138.0)
			var aim := _skull_hero_aim.lerp(_skull_wreck_world, 0.16)
			_cam.fov = 54.0
			_cam.look_at_from_position(eye, aim)

		_:
			if _cutlass != null:
				var cc_pos := _cutlass.global_position
				var cc_basis := Basis(Vector3.UP, 2.77)
				_cam.look_at_from_position(cc_pos + cc_basis * Vector3(-16.0, 11.5, -58.0),
					cc_pos + cc_basis * Vector3(1.5, 10.0, 2.0))
