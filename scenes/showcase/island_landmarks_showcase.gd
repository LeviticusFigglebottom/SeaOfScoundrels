extends Node3D
## Visual verification showcase for Wave I-2..I-9 sculpted 3D island landmarks (38 BC7 PBR GLBs),
## winding walkable terrain trails, and native batched MultiMesh `IslandDetails` ground foliage,
## highland cliff-ledge scrub, coastal dressing, living shore fauna & steep-slope cliff buttresses across all 14 islands.
##
## Usage:
##   tools/capture.sh res://scenes/showcase/island_landmarks_showcase.tscn cutlass_overhaul 2 5 -- shot=cutlass_overhaul
##
## User args (after `--`), all optional:
##   shot=<name>       22 visual audit shots (8 galleries + all 14 archipelago islands):
##                     gallery_geology|gallery_setpieces|gallery_storytelling|gallery_skyline|gallery_coastal|gallery_harbour_ruins|gallery_maritime_relics|gallery_world_craft|
##                     cutlass_overhaul|skull_bluff|emerald_temple|galleons_catwalk|cinder_basalt|gulls_arch|
##                     sovereigns_bastion|ironwatch_fort|crescent_atoll|barnacle_haven|
##                     wreckers_shoal|sirens_tooth|smugglers_cove|port_scoundrel
##   time=<hour>       hour of day (auto per-shot sunlit / golden-hour default)
##   storm=<0..1>      storminess (default 0.0)
##   cloud=<0..1>      cloudiness (default 0.30)
##   quality=low|medium|high   Ocean & sky cloud quality (default medium sky / high ocean)
##   scale=<0.25..1>   3D render scale
##   clock=<seconds>   starting pan clock
##   t=<seconds>       initial Sea.time (default 36.0)
##
## Interactive keys:
##   1=gallery_geology     2=gallery_setpieces   3=cutlass_overhaul   4=skull_bluff
##   5=emerald_temple      6=galleons_catwalk    7=cinder_basalt      8=gulls_arch
##   9=gallery_storytelling 0=sovereigns_bastion Q=ironwatch_fort     W=crescent_atoll
##   E=barnacle_haven      R=wreckers_shoal      T=sirens_tooth       Y=smugglers_cove
##   U=port_scoundrel      I=gallery_skyline     O=gallery_coastal    P=gallery_harbour_ruins
##   L=gallery_maritime_relics K=gallery_world_craft

const LANDMARK_DIR := "res://assets/generated/landmarks/"

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

const STORYTELLING_BACK_GLBS: Array[String] = [
	"ancient_sea_god_idol.glb",
	"volcanic_obsidian_arch.glb",
	"leviathan_ribcage_bones.glb",
]

const STORYTELLING_FRONT_GLBS: Array[String] = [
	"beached_rowboat_wreck.glb",
	"pirate_warning_gibbet.glb",
	"coastal_signal_brazier.glb",
]

const SKYLINE_GLBS: Array[String] = [
	"cliff_summit_crag_spire.glb",
	"cliff_ruin_aqueduct_arch.glb",
	"cliffside_pirate_watchpost.glb",
	"upper_cliff_strata_rib.glb",
]

const COASTAL_GLBS: Array[String] = [
	"pirate_camp_canopy.glb",
	"sunken_galleon_stern.glb",
	"giant_tidal_coral_arch.glb",
	"obsidian_lava_cauldron_shrine.glb",
]

const HARBOUR_RUINS_GLBS: Array[String] = [
	"harbour_cargo_crane_dock.glb",
	"overgrown_jungle_idol_altar.glb",
	"cliffside_waterfall_shrine.glb",
	"smuggler_contraband_hoard.glb",
]

const MARITIME_RELICS_GLBS: Array[String] = [
	"fort_coastal_watchtower_ruin.glb",
	"shipwreck_bell_buoy_beacon.glb",
	"ancient_compass_monolith_ring.glb",
	"volcanic_chain_bridge_anchor.glb",
]

const WORLD_CRAFT_GLBS: Array[String] = [
	"careening_ship_drydock.glb",
	"cursed_skeleton_throne_shrine.glb",
	"tropical_fishing_stilts_hut.glb",
	"ancient_astronomer_orrery_ruin.glb",
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
var _emerald_spire: Island = null
var _galleons_reach: Island = null
var _cinder_crag: Island = null
var _gulls_arch: Island = null
var _sovereigns_bastion: Island = null
var _ironwatch_fort: Island = null
var _crescent_atoll: Island = null
var _barnacle_haven: Island = null
var _wreckers_shoal: Island = null
var _sirens_tooth: Island = null
var _smugglers_cove: Island = null
var _port_scoundrel: Island = null

var _gallery_root: Node3D = null
var _gallery_stage_mi: MeshInstance3D = null
var _gallery_stage_mesh: ArrayMesh = null
var _gallery_stage_mat: StandardMaterial3D = null
var _gallery_bounds: AABB = AABB(Vector3(-25.0, 0.0, -10.0), Vector3(50.0, 18.0, 20.0))

var _landmark_scenes: Dictionary = {}  # filename -> PackedScene
var _flicker_lights: Array[Dictionary] = []

var _skull_hero_aim: Vector3 = Vector3.ZERO
var _emerald_hero_aim: Vector3 = Vector3.ZERO
var _galleons_hero_aim: Vector3 = Vector3.ZERO
var _gulls_arch_aim: Vector3 = Vector3.ZERO
var _sovereigns_hero_aim: Vector3 = Vector3.ZERO
var _ironwatch_hero_aim: Vector3 = Vector3.ZERO
var _crescent_hero_aim: Vector3 = Vector3.ZERO
var _barnacle_hero_aim: Vector3 = Vector3.ZERO
var _wreckers_hero_aim: Vector3 = Vector3.ZERO
var _sirens_hero_aim: Vector3 = Vector3.ZERO
var _smugglers_hero_aim: Vector3 = Vector3.ZERO
var _port_scoundrel_hero_aim: Vector3 = Vector3.ZERO


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
		sky_rig.set(&"shadow_distance", 360.0)

	var ocean := get_node_or_null(^"Ocean") as Ocean
	if ocean != null:
		var oq_str := String(_args.get("quality", "high"))
		ocean.quality = {"low": Ocean.Quality.LOW, "medium": Ocean.Quality.MEDIUM}.get(oq_str, Ocean.Quality.HIGH)

	# Build real 14-island deterministic archipelago (natively includes IslandDetails,
	# winding COLOR.a terrain trails, and bespoke Wave I-2 signature 3D landmarks).
	_archipelago = Archipelago.new()
	_archipelago.name = "Archipelago"
	add_child(_archipelago)

	_cutlass = _archipelago.get_island_by_id("cutlass_cay")
	_skull_bluff = _archipelago.get_island_by_id("skull_bluff")
	_emerald_spire = _archipelago.get_island_by_id("emerald_spire")
	_galleons_reach = _archipelago.get_island_by_id("galleons_reach")
	_cinder_crag = _archipelago.get_island_by_id("cinder_crag")
	_gulls_arch = _archipelago.get_island_by_id("gulls_arch")
	_sovereigns_bastion = _archipelago.get_island_by_id("sovereigns_bastion")
	_ironwatch_fort = _archipelago.get_island_by_id("ironwatch_fort")
	_crescent_atoll = _archipelago.get_island_by_id("crescent_atoll")
	_barnacle_haven = _archipelago.get_island_by_id("barnacle_haven")
	_wreckers_shoal = _archipelago.get_island_by_id("wreckers_shoal")
	_sirens_tooth = _archipelago.get_island_by_id("sirens_tooth")
	_smugglers_cove = _archipelago.get_island_by_id("smugglers_cove")
	_port_scoundrel = _archipelago.get_island_by_id("port_scoundrel")

	_resolve_native_landmark_aims()

	# Stage sunlit open-water gallery sandbar for asset lineup shots.
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
	_emerald_spire = null
	_galleons_reach = null
	_cinder_crag = null
	_gulls_arch = null
	_sovereigns_bastion = null
	_ironwatch_fort = null
	_crescent_atoll = null
	_barnacle_haven = null
	_wreckers_shoal = null
	_sirens_tooth = null
	_smugglers_cove = null
	_port_scoundrel = null
	_cam = null
	TreasureCatalog.clear_mesh_cache()
	IslandDetails.clear_shared_cache()


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
		KEY_5:
			next_shot = "emerald_temple"
		KEY_6:
			next_shot = "galleons_catwalk"
		KEY_7:
			next_shot = "cinder_basalt"
		KEY_8:
			next_shot = "gulls_arch"
		KEY_9:
			next_shot = "gallery_storytelling"
		KEY_0:
			next_shot = "sovereigns_bastion"
		KEY_Q:
			next_shot = "ironwatch_fort"
		KEY_W:
			next_shot = "crescent_atoll"
		KEY_E:
			next_shot = "barnacle_haven"
		KEY_R:
			next_shot = "wreckers_shoal"
		KEY_T:
			next_shot = "sirens_tooth"
		KEY_Y:
			next_shot = "smugglers_cove"
		KEY_U:
			next_shot = "port_scoundrel"
		KEY_I:
			next_shot = "gallery_skyline"
		KEY_O:
			next_shot = "gallery_coastal"
		KEY_P:
			next_shot = "gallery_harbour_ruins"
		KEY_L:
			next_shot = "gallery_maritime_relics"
		KEY_K:
			next_shot = "gallery_world_craft"
	if next_shot != "" and next_shot != _shot:
		_shot = next_shot
		_clock = 0.0
		_apply_shot_weather()
		_rebuild_gallery_for_shot()
		_update_camera()
		if _cam != null:
			Weather.set_focus(_cam.global_position)


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
		"gallery_storytelling":
			default_time = 15.8
		"gallery_skyline":
			default_time = 15.4
		"gallery_coastal":
			default_time = 15.2
		"gallery_harbour_ruins":
			default_time = 15.6
		"gallery_maritime_relics":
			default_time = 16.1
		"gallery_world_craft":
			default_time = 15.8
		"cutlass_overhaul":
			default_time = 10.4
		"skull_bluff":
			default_time = 16.3
		"emerald_temple":
			default_time = 10.8
		"galleons_catwalk":
			default_time = 16.1
		"cinder_basalt":
			default_time = 17.1
		"gulls_arch":
			default_time = 10.2
		"sovereigns_bastion":
			default_time = 15.9
		"ironwatch_fort":
			default_time = 10.1
		"crescent_atoll":
			default_time = 15.2
		"barnacle_haven":
			default_time = 10.0
		"wreckers_shoal":
			default_time = 15.8
		"sirens_tooth":
			default_time = 9.9
		"smugglers_cove":
			default_time = 16.0
		"port_scoundrel":
			default_time = 10.3
	var default_cloud := 0.30 if _shot.begins_with("gallery_") else 0.34
	if _shot == "cinder_basalt":
		default_cloud = 0.44
	elif _shot == "crescent_atoll":
		default_cloud = 0.28
	elif _shot == "port_scoundrel":
		default_cloud = 0.30
	elif _shot == "barnacle_haven":
		default_cloud = 0.32
	elif _shot == "wreckers_shoal":
		default_cloud = 0.36
	Weather.time_of_day = float(_args.get("time", str(default_time)))
	var storm := float(_args.get("storm", "0.0"))
	var cloud := float(_args.get("cloud", str(default_cloud)))
	Weather.set_weather(storm, 8.2, deg_to_rad(30.0), 0.0, cloud)
	Weather.cloud_offset = Vector2(240.0, 120.0)

	Sea.amp_scale = lerpf(Sea.AMP_CALM, Sea.AMP_STORM, storm)
	if _shot.begins_with("gallery_"):
		Sea.amp_scale = 0.28
	elif _shot == "cutlass_overhaul" or _shot == "gulls_arch":
		Sea.amp_scale = 0.46
	elif _shot == "galleons_catwalk" or _shot == "emerald_temple":
		Sea.amp_scale = 0.42
	elif _shot == "cinder_basalt":
		Sea.amp_scale = 0.62
	elif _shot == "sovereigns_bastion" or _shot == "ironwatch_fort":
		Sea.amp_scale = 0.48
	elif _shot == "crescent_atoll":
		Sea.amp_scale = 0.34
	elif _shot == "smugglers_cove":
		Sea.amp_scale = 0.36
	elif _shot == "port_scoundrel":
		Sea.amp_scale = 0.38
	elif _shot == "barnacle_haven":
		Sea.amp_scale = 0.40
	elif _shot == "wreckers_shoal":
		Sea.amp_scale = 0.50
	elif _shot == "sirens_tooth":
		Sea.amp_scale = 0.52
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
		var m_name := String(marker.name)
		var light := OmniLight3D.new()
		light.name = "Glow_" + m_name
		light.shadow_enabled = false
		var amp := 0.18
		if m_name.begins_with("Lantern_SkullEye"):
			light.light_color = Color(0.18, 0.96, 0.80)
			light.light_energy = 4.6
			light.omni_range = 18.0
			light.omni_attenuation = 1.25
			amp = 0.12
		elif m_name.begins_with("Lantern_IdolEye"):
			light.light_color = Color(0.16, 0.98, 0.78)
			light.light_energy = 4.8
			light.omni_range = 18.0
			light.omni_attenuation = 1.25
			amp = 0.16
		elif m_name.begins_with("Lantern_CalderaShrine"):
			light.light_color = Color(1.0, 0.38, 0.08)
			light.light_energy = 5.8
			light.omni_range = 22.0
			light.omni_attenuation = 1.25
			amp = 0.22
		elif m_name.begins_with("Lantern_MagmaArch") or m_name.begins_with("Lantern_Magma"):
			light.light_color = Color(1.0, 0.42, 0.10)
			light.light_energy = 5.4
			light.omni_range = 20.0
			light.omni_attenuation = 1.25
			amp = 0.20
		elif m_name.begins_with("Lantern_Camp"):
			light.light_color = Color(1.0, 0.70, 0.28)
			light.light_energy = 4.0
			light.omni_range = 16.0
			light.omni_attenuation = 1.30
			amp = 0.18
		elif m_name.begins_with("Lantern_Stern"):
			light.light_color = Color(1.0, 0.76, 0.34)
			light.light_energy = 3.8
			light.omni_range = 16.0
			light.omni_attenuation = 1.30
			amp = 0.16
		elif m_name.begins_with("Lantern_Crane"):
			light.light_color = Color(1.0, 0.74, 0.30)
			light.light_energy = 4.2
			light.omni_range = 18.0
			light.omni_attenuation = 1.28
			amp = 0.16
		elif m_name.begins_with("Lantern_Altar"):
			light.light_color = Color(0.20, 0.96, 0.72)
			light.light_energy = 4.6
			light.omni_range = 18.0
			light.omni_attenuation = 1.25
			amp = 0.18
		elif m_name.begins_with("Lantern_WaterfallShrine"):
			light.light_color = Color(0.26, 0.94, 0.88)
			light.light_energy = 4.4
			light.omni_range = 18.0
			light.omni_attenuation = 1.25
			amp = 0.14
		elif m_name.begins_with("Lantern_Hoard"):
			light.light_color = Color(1.0, 0.64, 0.22)
			light.light_energy = 3.6
			light.omni_range = 15.0
			light.omni_attenuation = 1.32
			amp = 0.20
		elif m_name.begins_with("Lantern_Watchtower"):
			light.light_color = Color(1.0, 0.72, 0.28)
			light.light_energy = 4.6
			light.omni_range = 20.0
			light.omni_attenuation = 1.28
			amp = 0.18
		elif m_name.begins_with("Lantern_ReefBeacon"):
			light.light_color = Color(1.0, 0.78, 0.34)
			light.light_energy = 4.4
			light.omni_range = 19.0
			light.omni_attenuation = 1.26
			amp = 0.16
		elif m_name.begins_with("Lantern_Monolith"):
			light.light_color = Color(0.18, 0.96, 0.80)
			light.light_energy = 4.8
			light.omni_range = 19.0
			light.omni_attenuation = 1.25
			amp = 0.15
		elif m_name.begins_with("Lantern_ChainPylon"):
			light.light_color = Color(1.0, 0.42, 0.10)
			light.light_energy = 5.4
			light.omni_range = 20.0
			light.omni_attenuation = 1.25
			amp = 0.22
		elif m_name.begins_with("Lantern_Drydock"):
			light.light_color = Color(1.0, 0.72, 0.30)
			light.light_energy = 4.4
			light.omni_range = 19.0
			light.omni_attenuation = 1.28
			amp = 0.18
		elif m_name.begins_with("Lantern_Throne"):
			light.light_color = Color(0.18, 0.98, 0.72)
			light.light_energy = 4.8
			light.omni_range = 20.0
			light.omni_attenuation = 1.25
			amp = 0.20
		elif m_name.begins_with("Lantern_FishHut"):
			light.light_color = Color(1.0, 0.74, 0.34)
			light.light_energy = 3.8
			light.omni_range = 16.0
			light.omni_attenuation = 1.30
			amp = 0.16
		elif m_name.begins_with("Lantern_Orrery"):
			light.light_color = Color(0.24, 0.92, 1.0)
			light.light_energy = 4.8
			light.omni_range = 20.0
			light.omni_attenuation = 1.25
			amp = 0.14
		elif m_name.begins_with("Lantern_Rowboat") or m_name.begins_with("Lantern_Gallows") \
				or m_name.begins_with("Lantern_Brazier") or m_name.begins_with("Lantern_Watchpost"):
			light.light_color = Color(1.0, 0.72, 0.30)
			light.light_energy = 4.2 if (m_name.begins_with("Lantern_Brazier") or m_name.begins_with("Lantern_Watchpost")) else 3.4
			light.omni_range = 20.0 if m_name.begins_with("Lantern_Watchpost") else (17.0 if m_name.begins_with("Lantern_Brazier") else 14.0)
			light.omni_attenuation = 1.30
			amp = 0.18
		else:
			light.light_color = Color(1.0, 0.66, 0.24)
			light.light_energy = 3.4
			light.omni_range = 14.0
			light.omni_attenuation = 1.35
		marker.add_child(light)
		var phase := float(idx) * 1.7 + float(m_name.hash() % 64) * 0.1
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
	var is_gallery := _shot == "gallery_geology" or _shot == "gallery_setpieces" \
			or _shot == "gallery_storytelling" or _shot == "gallery_skyline" \
			or _shot == "gallery_coastal" or _shot == "gallery_harbour_ruins" \
			or _shot == "gallery_maritime_relics" or _shot == "gallery_world_craft"
	_gallery_root.visible = is_gallery
	if not is_gallery:
		return

	_ensure_gallery_sandbar()

	if _shot == "gallery_geology":
		_layout_geology_gallery()
	elif _shot == "gallery_storytelling":
		_layout_storytelling_gallery()
	elif _shot == "gallery_skyline":
		_layout_skyline_gallery()
	elif _shot == "gallery_coastal":
		_layout_coastal_gallery()
	elif _shot == "gallery_harbour_ruins":
		_layout_harbour_ruins_gallery()
	elif _shot == "gallery_maritime_relics":
		_layout_maritime_relics_gallery()
	elif _shot == "gallery_world_craft":
		_layout_world_craft_gallery()
	else:
		_layout_setpieces_gallery()


func _layout_world_craft_gallery() -> void:
	# Stage Wave I-9 careening ship drydock, skeleton throne shrine, fishing stilts hut & astronomer orrery on the sunlit sandbar.
	var items: Array[Dictionary] = []
	var total_span := 0.0
	var gap := 4.6
	for i in WORLD_CRAFT_GLBS.size():
		var fn := WORLD_CRAFT_GLBS[i]
		var inst := _spawn_landmark(fn, _gallery_root, "WorldCraft_%02d" % i, Transform3D.IDENTITY, null, true)
		if inst == null:
			continue
		var bb := _compute_visual_aabb(inst)
		var footprint_w := clampf(maxf(bb.size.x, bb.size.z * 0.78), 6.0, 24.0)
		items.append({"node": inst, "aabb": bb, "width": footprint_w, "file": fn})
		total_span += footprint_w
	if items.is_empty():
		_gallery_bounds = AABB(Vector3(-24.0, 0.0, -10.0), Vector3(48.0, 14.0, 20.0))
		return
	total_span += gap * float(maxi(0, items.size() - 1))

	var cursor_x := -total_span * 0.5
	var bounds := AABB()
	var has_bounds := false
	for i in items.size():
		var entry: Dictionary = items[i]
		var inst := entry["node"] as Node3D
		var bb: AABB = entry["aabb"]
		var w := float(entry["width"])
		var fn := String(entry["file"])
		var cx := cursor_x + w * 0.5
		cursor_x += w + gap

		var t_norm := cx / maxf(total_span * 0.5, 1.0)
		var cz := -4.4 + t_norm * t_norm * 4.4
		if fn == "tropical_fishing_stilts_hut.glb":
			cz += 1.8
		elif fn == "cursed_skeleton_throne_shrine.glb":
			cz += 1.2
		var ground_y := _sandbar_y(cx, cz) - 0.12
		var yaw := PI - t_norm * 0.24
		if fn == "careening_ship_drydock.glb":
			yaw += 0.28
		elif fn == "tropical_fishing_stilts_hut.glb":
			yaw -= 0.22
		elif fn == "ancient_astronomer_orrery_ruin.glb":
			yaw -= 0.18
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

	if has_bounds:
		_gallery_bounds = bounds


func _layout_maritime_relics_gallery() -> void:
	# Stage Wave I-7 maritime watchtower, bell buoy beacon, compass monolith & volcanic chain pylon on the sunlit sandbar.
	var items: Array[Dictionary] = []
	var total_span := 0.0
	var gap := 4.6
	for i in MARITIME_RELICS_GLBS.size():
		var fn := MARITIME_RELICS_GLBS[i]
		var inst := _spawn_landmark(fn, _gallery_root, "MaritimeRelics_%02d" % i, Transform3D.IDENTITY, null, true)
		if inst == null:
			continue
		var bb := _compute_visual_aabb(inst)
		var footprint_w := clampf(maxf(bb.size.x, bb.size.z * 0.78), 6.0, 24.0)
		items.append({"node": inst, "aabb": bb, "width": footprint_w, "file": fn})
		total_span += footprint_w
	if items.is_empty():
		_gallery_bounds = AABB(Vector3(-24.0, 0.0, -10.0), Vector3(48.0, 14.0, 20.0))
		return
	total_span += gap * float(maxi(0, items.size() - 1))

	var cursor_x := -total_span * 0.5
	var bounds := AABB()
	var has_bounds := false
	for i in items.size():
		var entry: Dictionary = items[i]
		var inst := entry["node"] as Node3D
		var bb: AABB = entry["aabb"]
		var w := float(entry["width"])
		var fn := String(entry["file"])
		var cx := cursor_x + w * 0.5
		cursor_x += w + gap

		var t_norm := cx / maxf(total_span * 0.5, 1.0)
		var cz := -4.4 + t_norm * t_norm * 4.4
		if fn == "shipwreck_bell_buoy_beacon.glb":
			cz += 2.0
		elif fn == "volcanic_chain_bridge_anchor.glb":
			cz += 1.2
		var ground_y := _sandbar_y(cx, cz) - 0.12
		var yaw := PI - t_norm * 0.24
		if fn == "fort_coastal_watchtower_ruin.glb":
			yaw += 0.24
		elif fn == "shipwreck_bell_buoy_beacon.glb":
			yaw -= 0.18
		elif fn == "volcanic_chain_bridge_anchor.glb":
			yaw -= 0.26
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

	if has_bounds:
		_gallery_bounds = bounds


func _layout_harbour_ruins_gallery() -> void:
	# Stage Wave I-6 harbour, jungle ruin, waterfall shrine & smuggler hoard landmarks on the sunlit sandbar.
	var items: Array[Dictionary] = []
	var total_span := 0.0
	var gap := 4.6
	for i in HARBOUR_RUINS_GLBS.size():
		var fn := HARBOUR_RUINS_GLBS[i]
		var inst := _spawn_landmark(fn, _gallery_root, "HarbourRuins_%02d" % i, Transform3D.IDENTITY, null, true)
		if inst == null:
			continue
		var bb := _compute_visual_aabb(inst)
		var footprint_w := clampf(maxf(bb.size.x, bb.size.z * 0.78), 6.0, 24.0)
		items.append({"node": inst, "aabb": bb, "width": footprint_w, "file": fn})
		total_span += footprint_w
	if items.is_empty():
		_gallery_bounds = AABB(Vector3(-24.0, 0.0, -10.0), Vector3(48.0, 14.0, 20.0))
		return
	total_span += gap * float(maxi(0, items.size() - 1))

	var cursor_x := -total_span * 0.5
	var bounds := AABB()
	var has_bounds := false
	for i in items.size():
		var entry: Dictionary = items[i]
		var inst := entry["node"] as Node3D
		var bb: AABB = entry["aabb"]
		var w := float(entry["width"])
		var fn := String(entry["file"])
		var cx := cursor_x + w * 0.5
		cursor_x += w + gap

		var t_norm := cx / maxf(total_span * 0.5, 1.0)
		var cz := -4.4 + t_norm * t_norm * 4.4
		if fn == "smuggler_contraband_hoard.glb":
			cz += 2.2
		elif fn == "harbour_cargo_crane_dock.glb":
			cz += 1.4
		var ground_y := _sandbar_y(cx, cz) - 0.12
		var yaw := PI - t_norm * 0.24
		if fn == "harbour_cargo_crane_dock.glb":
			yaw += 0.28
		elif fn == "smuggler_contraband_hoard.glb":
			yaw -= 0.22
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

	if has_bounds:
		_gallery_bounds = bounds


func _layout_coastal_gallery() -> void:
	# Stage Wave I-5 coastal, reef & volcanic caldera landmarks cleanly on the sunlit sandbar.
	var items: Array[Dictionary] = []
	var total_span := 0.0
	var gap := 4.6
	for i in COASTAL_GLBS.size():
		var fn := COASTAL_GLBS[i]
		var inst := _spawn_landmark(fn, _gallery_root, "Coastal_%02d" % i, Transform3D.IDENTITY, null, true)
		if inst == null:
			continue
		var bb := _compute_visual_aabb(inst)
		var footprint_w := clampf(maxf(bb.size.x, bb.size.z * 0.78), 6.0, 24.0)
		items.append({"node": inst, "aabb": bb, "width": footprint_w, "file": fn})
		total_span += footprint_w
	if items.is_empty():
		_gallery_bounds = AABB(Vector3(-24.0, 0.0, -10.0), Vector3(48.0, 14.0, 20.0))
		return
	total_span += gap * float(maxi(0, items.size() - 1))

	var cursor_x := -total_span * 0.5
	var bounds := AABB()
	var has_bounds := false
	for i in items.size():
		var entry: Dictionary = items[i]
		var inst := entry["node"] as Node3D
		var bb: AABB = entry["aabb"]
		var w := float(entry["width"])
		var fn := String(entry["file"])
		var cx := cursor_x + w * 0.5
		cursor_x += w + gap

		var t_norm := cx / maxf(total_span * 0.5, 1.0)
		var cz := -4.4 + t_norm * t_norm * 4.4
		if fn == "giant_tidal_coral_arch.glb":
			cz += 1.6
		elif fn == "pirate_camp_canopy.glb":
			cz += 2.0
		var ground_y := _sandbar_y(cx, cz) - 0.12
		var yaw := PI - t_norm * 0.24
		if fn == "sunken_galleon_stern.glb":
			yaw += 0.34
		elif fn == "pirate_camp_canopy.glb":
			yaw -= 0.20
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

	if has_bounds:
		_gallery_bounds = bounds


func _layout_skyline_gallery() -> void:
	var items: Array[Dictionary] = []
	var total_span := 0.0
	var gap := 4.4
	for i in SKYLINE_GLBS.size():
		var fn := SKYLINE_GLBS[i]
		var inst := _spawn_landmark(fn, _gallery_root, "Skyline_%02d" % i, Transform3D.IDENTITY, null, true)
		if inst == null:
			continue
		var bb := _compute_visual_aabb(inst)
		var footprint_w := clampf(maxf(bb.size.x, bb.size.z * 0.78), 6.0, 23.0)
		items.append({"node": inst, "aabb": bb, "width": footprint_w, "file": fn})
		total_span += footprint_w
	if items.is_empty():
		return
	total_span += gap * float(maxi(0, items.size() - 1))

	var cursor_x := -total_span * 0.5
	var bounds := AABB()
	var has_bounds := false
	for i in items.size():
		var entry: Dictionary = items[i]
		var inst := entry["node"] as Node3D
		var bb: AABB = entry["aabb"]
		var w := float(entry["width"])
		var fn := String(entry["file"])
		var cx := cursor_x + w * 0.5
		cursor_x += w + gap

		var t_norm := cx / maxf(total_span * 0.5, 1.0)
		var cz := -4.8 + t_norm * t_norm * 4.5
		var ground_y := _sandbar_y(cx, cz) - 0.12
		var yaw := PI - t_norm * 0.24
		if fn == "upper_cliff_strata_rib.glb":
			yaw += 0.42
		elif fn == "cliffside_pirate_watchpost.glb":
			yaw -= 0.28
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

	if has_bounds:
		_gallery_bounds = bounds


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


func _layout_storytelling_gallery() -> void:
	# Stage Wave I-3 storytelling PBR landmarks on the sunlit sandbar; missing GLBs skip cleanly.
	var back_items: Array[Dictionary] = []
	var total_span := 0.0
	var gap := 4.8
	for i in STORYTELLING_BACK_GLBS.size():
		var fn := STORYTELLING_BACK_GLBS[i]
		var inst := _spawn_landmark(fn, _gallery_root, "StoryBack_%02d" % i, Transform3D.IDENTITY, null, true)
		if inst == null:
			continue
		var bb := _compute_visual_aabb(inst)
		var footprint_w := clampf(maxf(bb.size.x, bb.size.z * 0.78), 5.5, 24.0)
		back_items.append({"node": inst, "aabb": bb, "width": footprint_w, "file": fn})
		total_span += footprint_w
	total_span += gap * float(maxi(0, back_items.size() - 1))

	var bounds := AABB()
	var has_bounds := false
	var cursor_x := -total_span * 0.5
	for i in back_items.size():
		var entry: Dictionary = back_items[i]
		var inst := entry["node"] as Node3D
		var bb: AABB = entry["aabb"]
		var w := float(entry["width"])
		var fn := String(entry["file"])
		var cx := cursor_x + w * 0.5
		cursor_x += w + gap

		var t_norm := cx / maxf(total_span * 0.5, 1.0)
		var cz := -5.8 + t_norm * t_norm * 4.2
		var ground_y := _sandbar_y(cx, cz) - 0.12
		var yaw := PI - t_norm * 0.24
		if fn == "leviathan_ribcage_bones.glb":
			yaw += 0.28
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

	# Front arc: compact storytelling props spaced across the sunlit foreground sandbar.
	var front_items: Array[Dictionary] = []
	var front_span := 0.0
	var front_gap := 6.0
	for j in STORYTELLING_FRONT_GLBS.size():
		var fn := STORYTELLING_FRONT_GLBS[j]
		var inst := _spawn_landmark(fn, _gallery_root, "StoryFront_%02d" % j, Transform3D.IDENTITY, null, true)
		if inst == null:
			continue
		var bb := _compute_visual_aabb(inst)
		var footprint_w := clampf(maxf(bb.size.x, bb.size.z * 0.78), 3.6, 10.0)
		front_items.append({"node": inst, "aabb": bb, "width": footprint_w, "file": fn})
		front_span += footprint_w
	front_span += front_gap * float(maxi(0, front_items.size() - 1))
	var min_front_span := clampf(total_span * 0.54, 18.0, 32.0) if front_items.size() > 1 else 0.0
	if front_items.size() > 1 and front_span < min_front_span:
		front_gap += (min_front_span - front_span) / float(front_items.size() - 1)
		front_span = min_front_span

	var f_cursor_x := -front_span * 0.5
	for j in front_items.size():
		var entry: Dictionary = front_items[j]
		var inst := entry["node"] as Node3D
		var bb: AABB = entry["aabb"]
		var w := float(entry["width"])
		var fn := String(entry["file"])
		var cx := f_cursor_x + w * 0.5
		f_cursor_x += w + front_gap

		var t_norm := cx / maxf(front_span * 0.5, 1.0)
		var cz := 7.6 + (1.0 - t_norm * t_norm) * 1.4
		var ground_y := _sandbar_y(cx, cz) - 0.06
		var yaw := PI - t_norm * 0.28
		if fn == "beached_rowboat_wreck.glb":
			yaw += 0.36
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
	else:
		_gallery_bounds = AABB(Vector3(-24.0, 0.0, -10.0), Vector3(48.0, 14.0, 20.0))


# ------------------------------------------------------------------ native Wave I-2 & I-3 landmark targeting

func _island_landing_yaw(isl: Island, fallback_yaw: float) -> float:
	if isl != null and isl.has_meta(&"landing_yaw"):
		return float(isl.get_meta(&"landing_yaw"))
	return fallback_yaw


func _find_native_landmark_aim(isl: Island, pattern: String, fallback_world: Vector3) -> Vector3:
	if isl == null:
		return fallback_world
	var node := isl.find_child(pattern, true, false) as Node3D
	if node == null:
		return fallback_world
	var bb := _compute_visual_aabb(node)
	return node.global_transform * bb.get_center()


func _resolve_native_landmark_aims() -> void:
	if _skull_bluff != null:
		var sb_basis := Basis(Vector3.UP, _island_landing_yaw(_skull_bluff, 2.35))
		var sb_fallback := _skull_bluff.global_position + sb_basis * Vector3(0.0, 26.0, -26.0)
		_skull_hero_aim = _find_native_landmark_aim(_skull_bluff, "SkullCliffCarving*", sb_fallback)

	if _emerald_spire != null:
		var es_basis := Basis(Vector3.UP, _island_landing_yaw(_emerald_spire, -1.42))
		var es_fallback := _emerald_spire.global_position + es_basis * Vector3(0.0, 14.0, 8.0)
		var stair_aim := _find_native_landmark_aim(_emerald_spire, "TempleStairway*", es_fallback)
		var wf_node := _emerald_spire.find_child("EmeraldCanyonWaterfall*", true, false) as Node3D
		if wf_node != null:
			var wf_aim := wf_node.global_position - Vector3(0.0, 6.0, 0.0)
			_emerald_hero_aim = stair_aim.lerp(wf_aim, 0.35)
		else:
			_emerald_hero_aim = stair_aim

	if _galleons_reach != null:
		var gr_basis := Basis(Vector3.UP, _island_landing_yaw(_galleons_reach, 0.12))
		var gr_fallback := _galleons_reach.global_position + gr_basis * Vector3(-16.0, 10.0, -34.0)
		var catwalk_aim := _find_native_landmark_aim(_galleons_reach, "CliffCatwalk*", gr_fallback)
		var harbor_hub := _galleons_reach.global_position + gr_basis * Vector3(-4.0, 9.0, -24.0)
		_galleons_hero_aim = catwalk_aim.lerp(harbor_hub, 0.35)

	if _gulls_arch != null:
		var ga_basis := Basis(Vector3.UP, _island_landing_yaw(_gulls_arch, -2.15))
		var ga_fallback := _gulls_arch.global_position + ga_basis * Vector3(0.0, 9.0, -28.0)
		_gulls_arch_aim = _find_native_landmark_aim(_gulls_arch, "CoastalSeaArch_Main*",
			_find_native_landmark_aim(_gulls_arch, "CoastalSeaArch*", ga_fallback))

	if _sovereigns_bastion != null:
		var sv_basis := Basis(Vector3.UP, _island_landing_yaw(_sovereigns_bastion, 1.72))
		var sv_fallback := _sovereigns_bastion.global_position + sv_basis * Vector3(0.0, 26.0, 18.0)
		var bastion_aim := _find_native_landmark_aim(_sovereigns_bastion, "FortBastion*", sv_fallback)
		var wf_node := _sovereigns_bastion.find_child("CitadelWaterfall*", true, false) as Node3D
		if wf_node != null:
			var wf_aim := wf_node.global_position - Vector3(0.0, 8.0, 0.0)
			_sovereigns_hero_aim = bastion_aim.lerp(wf_aim, 0.18)
		else:
			_sovereigns_hero_aim = bastion_aim
		_sovereigns_hero_aim.y = maxf(_sovereigns_hero_aim.y, 24.0)

	if _ironwatch_fort != null:
		var iw_basis := Basis(Vector3.UP, _island_landing_yaw(_ironwatch_fort, -2.35))
		var iw_fallback := _ironwatch_fort.global_position + iw_basis * Vector3(0.0, 21.0, 3.0)
		var iw_bastion := _find_native_landmark_aim(_ironwatch_fort, "FortBastion*", iw_fallback)
		var iw_ramp := _ironwatch_fort.global_position + iw_basis * Vector3(0.0, 9.5, -28.0)
		_ironwatch_hero_aim = iw_bastion.lerp(iw_ramp, 0.18)

	if _crescent_atoll != null:
		var ca_basis := Basis(Vector3.UP, _island_landing_yaw(_crescent_atoll, 0.72))
		var ca_pos := _crescent_atoll.global_position
		var arch_fb := ca_pos + ca_basis * Vector3(0.0, 6.0, -78.0)
		var wreck_fb := ca_pos + ca_basis * Vector3(83.0, 6.0, -46.0)
		var arch_aim := _find_native_landmark_aim(_crescent_atoll, "CoastalSeaArch_Lagoon*",
			_find_native_landmark_aim(_crescent_atoll, "CoastalSeaArch*", arch_fb))
		var wreck_aim := _find_native_landmark_aim(_crescent_atoll, "ImpaledShipwreckBow_Reef*",
			_find_native_landmark_aim(_crescent_atoll, "ImpaledShipwreckBow*", wreck_fb))
		var lagoon_heart := ca_pos + ca_basis * Vector3(6.0, 5.5, -18.0)
		_crescent_hero_aim = arch_aim * 0.42 + wreck_aim * 0.28 + lagoon_heart * 0.30

	if _barnacle_haven != null:
		var bh_basis := Basis(Vector3.UP, _island_landing_yaw(_barnacle_haven, -0.78))
		var bh_pos := _barnacle_haven.global_position
		var bh_arch_fb := bh_pos + bh_basis * Vector3(42.0, 5.5, -34.0)
		var bh_cat_fb := bh_pos + bh_basis * Vector3(-38.0, 6.5, -18.0)
		var bh_arch := _find_native_landmark_aim(_barnacle_haven, "CoastalSeaArch_Harbour*", bh_arch_fb)
		var bh_cat := _find_native_landmark_aim(_barnacle_haven, "CliffCatwalkPier_Bluff*", bh_cat_fb)
		var bh_hub := bh_pos + bh_basis * Vector3(0.0, 6.0, -18.0)
		_barnacle_hero_aim = bh_hub * 0.56 + bh_arch * 0.22 + bh_cat * 0.22

	if _wreckers_shoal != null:
		var ws_basis := Basis(Vector3.UP, _island_landing_yaw(_wreckers_shoal, 0.05))
		var ws_pos := _wreckers_shoal.global_position
		var ws_fb := ws_pos + ws_basis * Vector3(4.6, 11.5, -3.1)
		var ws_bow := _find_native_landmark_aim(_wreckers_shoal, "ImpaledShipwreckBow_Main*",
			_find_native_landmark_aim(_wreckers_shoal, "ImpaledShipwreckBow*", ws_fb))
		var ws_center := ws_pos + ws_basis * Vector3(0.0, 9.5, 0.0)
		_wreckers_hero_aim = ws_bow.lerp(ws_center, 0.18)

	if _sirens_tooth != null:
		var st_basis := Basis(Vector3.UP, _island_landing_yaw(_sirens_tooth, -0.62))
		var st_pos := _sirens_tooth.global_position
		var st_bow_fb := st_pos + st_basis * Vector3(-7.6, 10.0, -8.9)
		var st_arch_fb := st_pos + st_basis * Vector3(17.7, 5.0, -11.4)
		var st_bow := _find_native_landmark_aim(_sirens_tooth, "ImpaledShipwreckBow_Fang*", st_bow_fb)
		var st_arch := _find_native_landmark_aim(_sirens_tooth, "CoastalSeaArch_Tooth*", st_arch_fb)
		var st_fang := st_pos + st_basis * Vector3(0.0, 22.0, 2.0)
		_sirens_hero_aim = st_fang * 0.52 + st_bow * 0.24 + st_arch * 0.24
		_sirens_hero_aim.y = maxf(_sirens_hero_aim.y, 17.0)

	if _smugglers_cove != null:
		var sc_basis := Basis(Vector3.UP, _island_landing_yaw(_smugglers_cove, 1.35))
		var sc_pos := _smugglers_cove.global_position
		var grotto_mouth := sc_pos + sc_basis * Vector3(0.0, 5.8, 9.6)
		var grotto_node := _smugglers_cove.find_child("SmugglersGrotto*", true, false) as Node3D
		if grotto_node != null:
			grotto_mouth = grotto_node.global_position + Vector3(0.0, 4.2, 0.0)
		var sc_cat_fb := sc_pos + sc_basis * Vector3(36.0, 7.5, -18.0)
		var sc_cat := _find_native_landmark_aim(_smugglers_cove, "CliffCatwalkPier_Cove*", sc_cat_fb)
		_smugglers_hero_aim = grotto_mouth.lerp(sc_cat, 0.38)

	if _port_scoundrel != null:
		var ps_basis := Basis(Vector3.UP, _island_landing_yaw(_port_scoundrel, -0.37))
		var ps_pos := _port_scoundrel.global_position
		var ps_bluff_fb := ps_pos + ps_basis * Vector3(-34.0, 11.0, 3.0)
		var ps_bcn_fb := ps_pos + ps_basis * Vector3(24.0, 16.0, -6.5)
		var ps_bluff := _find_native_landmark_aim(_port_scoundrel, "CliffOverhangLedge_TavernBluff*",
			_find_native_landmark_aim(_port_scoundrel, "CliffOverhangLedge*", ps_bluff_fb))
		var ps_bcn := _find_native_landmark_aim(_port_scoundrel, "BeaconTower*", ps_bcn_fb)
		var ps_hub := ps_pos + ps_basis * Vector3(-2.0, 6.5, -14.0)
		_port_scoundrel_hero_aim = ps_hub * 0.54 + ps_bcn * 0.24 + ps_bluff * 0.22


# ------------------------------------------------------------------ camera choreography

func _safe_camera_eye(isl: Island, eye: Vector3) -> Vector3:
	var min_y := 3.5
	if isl != null:
		var ground_y := isl.world_surface_height(eye)
		ground_y = maxf(ground_y, isl.world_surface_height(eye + Vector3(3.0, 0.0, 0.0)))
		ground_y = maxf(ground_y, isl.world_surface_height(eye + Vector3(-3.0, 0.0, 0.0)))
		ground_y = maxf(ground_y, isl.world_surface_height(eye + Vector3(0.0, 0.0, 3.0)))
		ground_y = maxf(ground_y, isl.world_surface_height(eye + Vector3(0.0, 0.0, -3.0)))
		min_y = maxf(min_y, ground_y + 3.5)
	if eye.y < min_y:
		eye.y = min_y
	return eye


func _update_camera() -> void:
	if _cam == null:
		return

	match _shot:
		"gallery_geology", "gallery_setpieces", "gallery_storytelling", "gallery_skyline", "gallery_coastal", "gallery_harbour_ruins", "gallery_maritime_relics", "gallery_world_craft":
			var ctr := GALLERY_ORIGIN + _gallery_bounds.get_center()
			var span_x := maxf(_gallery_bounds.size.x, 30.0)
			var span_y := maxf(_gallery_bounds.size.y, 10.0)
			var dist := clampf(maxf(span_x * 0.72, span_y * 1.95), 24.0, 72.0)
			var pan := sin(_clock * 0.35) * (span_x * 0.08)
			var eye_x := ctr.x + pan
			var eye_z := ctr.z + dist
			var min_eye_y := maxf(4.8, _sandbar_y(eye_x - GALLERY_ORIGIN.x, eye_z - GALLERY_ORIGIN.z) + 3.5)
			var eye := Vector3(eye_x, maxf(min_eye_y, ctr.y + span_y * 0.18), eye_z)
			var aim := Vector3(ctr.x, maxf(2.2, ctr.y - span_y * 0.04), ctr.z)
			_cam.fov = 50.0
			_cam.look_at_from_position(eye, aim)

		"cutlass_overhaul":
			if _cutlass == null:
				return
			var cc_pos := _cutlass.global_position
			var cc_basis := Basis(Vector3.UP, _island_landing_yaw(_cutlass, 2.77))
			var sweep := clampf(_clock * 0.22, 0.0, 1.0)
			var pan := sin(_clock * 0.42) * 5.0
			var eye := _safe_camera_eye(_cutlass,
				cc_pos + cc_basis * Vector3(-16.0 + pan, lerpf(12.0, 5.6, sweep), lerpf(-60.0, -39.0, sweep)))
			var aim := cc_pos + cc_basis * Vector3(1.5, lerpf(10.5, 5.8, sweep), lerpf(3.0, -9.0, sweep))
			_cam.fov = 58.0
			_cam.look_at_from_position(eye, aim)

		"skull_bluff":
			if _skull_bluff == null:
				return
			var sb_pos := _skull_bluff.global_position
			var sb_basis := Basis(Vector3.UP, _island_landing_yaw(_skull_bluff, 2.35))
			var sweep := clampf(_clock * 0.20, 0.0, 1.0)
			var pan := sin(_clock * 0.32) * 7.5
			var eye := _safe_camera_eye(_skull_bluff,
				sb_pos + sb_basis * Vector3(-26.0 + pan, lerpf(21.0, 17.5, sweep), lerpf(-142.0, -124.0, sweep)))
			var aim := _skull_hero_aim - Vector3(0.0, 2.0, 0.0)
			_cam.fov = 54.0
			_cam.look_at_from_position(eye, aim)

		"emerald_temple":
			if _emerald_spire == null:
				return
			var es_pos := _emerald_spire.global_position
			var es_basis := Basis(Vector3.UP, _island_landing_yaw(_emerald_spire, -1.42))
			var sweep := clampf(_clock * 0.22, 0.0, 1.0)
			var pan := sin(_clock * 0.36) * 6.0
			var eye := _safe_camera_eye(_emerald_spire,
				es_pos + es_basis * Vector3(-14.0 + pan, lerpf(17.5, 11.8, sweep), lerpf(-94.0, -66.0, sweep)))
			var aim := _emerald_hero_aim
			_cam.fov = 56.0
			_cam.look_at_from_position(eye, aim)

		"galleons_catwalk":
			if _galleons_reach == null:
				return
			var gr_pos := _galleons_reach.global_position
			var gr_basis := Basis(Vector3.UP, _island_landing_yaw(_galleons_reach, 0.12))
			var sweep := clampf(_clock * 0.20, 0.0, 1.0)
			var pan := sin(_clock * 0.34) * 8.0
			var eye := _safe_camera_eye(_galleons_reach,
				gr_pos + gr_basis * Vector3(-34.0 + pan, lerpf(23.0, 15.0, sweep), lerpf(-114.0, -80.0, sweep)))
			var aim := _galleons_hero_aim
			_cam.fov = 56.0
			_cam.look_at_from_position(eye, aim)

		"cinder_basalt":
			if _cinder_crag == null:
				return
			var cr_pos := _cinder_crag.global_position
			var cr_basis := Basis(Vector3.UP, _island_landing_yaw(_cinder_crag, 2.90))
			var sweep := clampf(_clock * 0.18, 0.0, 1.0)
			var pan := sin(_clock * 0.28) * 14.0
			var eye := _safe_camera_eye(_cinder_crag,
				cr_pos + cr_basis * Vector3(-52.0 + pan, lerpf(56.0, 44.0, sweep), lerpf(-236.0, -196.0, sweep)))
			var aim := cr_pos + cr_basis * Vector3(0.0, 50.0, -10.0)
			_cam.fov = 54.0
			_cam.look_at_from_position(eye, aim)

		"gulls_arch":
			if _gulls_arch == null:
				return
			var ga_pos := _gulls_arch.global_position
			var ga_basis := Basis(Vector3.UP, _island_landing_yaw(_gulls_arch, -2.15))
			var sweep := clampf(_clock * 0.22, 0.0, 1.0)
			var pan := sin(_clock * 0.36) * 6.5
			var eye := _safe_camera_eye(_gulls_arch,
				ga_pos + ga_basis * Vector3(-22.0 + pan, lerpf(15.5, 9.2, sweep), lerpf(-96.0, -68.0, sweep)))
			var aim := _gulls_arch_aim
			_cam.fov = 56.0
			_cam.look_at_from_position(eye, aim)

		"sovereigns_bastion":
			if _sovereigns_bastion == null:
				return
			var sv_pos := _sovereigns_bastion.global_position
			var sv_basis := Basis(Vector3.UP, _island_landing_yaw(_sovereigns_bastion, 1.72))
			var sweep := clampf(_clock * 0.18, 0.0, 1.0)
			var pan := sin(_clock * 0.30) * 12.0
			var eye := _safe_camera_eye(_sovereigns_bastion,
				sv_pos + sv_basis * Vector3(34.0 + pan, lerpf(42.0, 31.0, sweep), lerpf(-228.0, -186.0, sweep)))
			var aim := _sovereigns_hero_aim
			_cam.fov = 54.0
			_cam.look_at_from_position(eye, aim)

		"ironwatch_fort":
			if _ironwatch_fort == null:
				return
			var iw_pos := _ironwatch_fort.global_position
			var iw_basis := Basis(Vector3.UP, _island_landing_yaw(_ironwatch_fort, -2.35))
			var sweep := clampf(_clock * 0.20, 0.0, 1.0)
			var pan := sin(_clock * 0.34) * 7.5
			var eye := _safe_camera_eye(_ironwatch_fort,
				iw_pos + iw_basis * Vector3(-34.0 + pan, lerpf(28.0, 20.5, sweep), lerpf(-136.0, -108.0, sweep)))
			var aim := _ironwatch_hero_aim
			_cam.fov = 54.0
			_cam.look_at_from_position(eye, aim)

		"crescent_atoll":
			if _crescent_atoll == null:
				return
			var ca_pos := _crescent_atoll.global_position
			var ca_basis := Basis(Vector3.UP, _island_landing_yaw(_crescent_atoll, 0.72))
			var sweep := clampf(_clock * 0.20, 0.0, 1.0)
			var pan := sin(_clock * 0.32) * 10.0
			var eye := _safe_camera_eye(_crescent_atoll,
				ca_pos + ca_basis * Vector3(32.0 + pan, lerpf(32.0, 23.0, sweep), lerpf(-186.0, -152.0, sweep)))
			var aim := _crescent_hero_aim
			_cam.fov = 56.0
			_cam.look_at_from_position(eye, aim)

		"barnacle_haven":
			if _barnacle_haven == null:
				return
			var bh_pos := _barnacle_haven.global_position
			var bh_basis := Basis(Vector3.UP, _island_landing_yaw(_barnacle_haven, -0.78))
			var sweep := clampf(_clock * 0.22, 0.0, 1.0)
			var pan := sin(_clock * 0.36) * 6.5
			var eye := _safe_camera_eye(_barnacle_haven,
				bh_pos + bh_basis * Vector3(-10.0 + pan, lerpf(22.0, 14.5, sweep), lerpf(-118.0, -88.0, sweep)))
			var aim := _barnacle_hero_aim
			_cam.fov = 56.0
			_cam.look_at_from_position(eye, aim)

		"wreckers_shoal":
			if _wreckers_shoal == null:
				return
			var ws_pos := _wreckers_shoal.global_position
			var ws_basis := Basis(Vector3.UP, _island_landing_yaw(_wreckers_shoal, 0.05))
			var sweep := clampf(_clock * 0.22, 0.0, 1.0)
			var pan := sin(_clock * 0.38) * 5.0
			var eye := _safe_camera_eye(_wreckers_shoal,
				ws_pos + ws_basis * Vector3(-22.0 + pan, lerpf(16.0, 10.5, sweep), lerpf(-78.0, -56.0, sweep)))
			var aim := _wreckers_hero_aim
			_cam.fov = 54.0
			_cam.look_at_from_position(eye, aim)

		"sirens_tooth":
			if _sirens_tooth == null:
				return
			var st_pos := _sirens_tooth.global_position
			var st_basis := Basis(Vector3.UP, _island_landing_yaw(_sirens_tooth, -0.62))
			var sweep := clampf(_clock * 0.22, 0.0, 1.0)
			var pan := sin(_clock * 0.38) * 5.5
			var eye := _safe_camera_eye(_sirens_tooth,
				st_pos + st_basis * Vector3(14.0 + pan, lerpf(20.0, 14.5, sweep), lerpf(-92.0, -70.0, sweep)))
			var aim := _sirens_hero_aim
			_cam.fov = 56.0
			_cam.look_at_from_position(eye, aim)

		"smugglers_cove":
			if _smugglers_cove == null:
				return
			var sc_pos := _smugglers_cove.global_position
			var sc_basis := Basis(Vector3.UP, _island_landing_yaw(_smugglers_cove, 1.35))
			var sweep := clampf(_clock * 0.20, 0.0, 1.0)
			var pan := sin(_clock * 0.34) * 5.0
			var eye := _safe_camera_eye(_smugglers_cove,
				sc_pos + sc_basis * Vector3(-10.0 + pan, lerpf(21.0, 12.0, sweep), lerpf(-118.0, -76.0, sweep)))
			var aim := _smugglers_hero_aim
			_cam.fov = 56.0
			_cam.look_at_from_position(eye, aim)

		"port_scoundrel":
			if _port_scoundrel == null:
				return
			var ps_pos := _port_scoundrel.global_position
			var ps_basis := Basis(Vector3.UP, _island_landing_yaw(_port_scoundrel, -0.37))
			var sweep := clampf(_clock * 0.22, 0.0, 1.0)
			var pan := sin(_clock * 0.36) * 6.5
			var eye := _safe_camera_eye(_port_scoundrel,
				ps_pos + ps_basis * Vector3(14.0 + pan, lerpf(22.0, 14.0, sweep), lerpf(-114.0, -82.0, sweep)))
			var aim := _port_scoundrel_hero_aim
			_cam.fov = 56.0
			_cam.look_at_from_position(eye, aim)

		_:
			if _cutlass != null:
				var cc_pos := _cutlass.global_position
				var cc_basis := Basis(Vector3.UP, _island_landing_yaw(_cutlass, 2.77))
				var eye := _safe_camera_eye(_cutlass, cc_pos + cc_basis * Vector3(-16.0, 12.0, -60.0))
				_cam.look_at_from_position(eye, cc_pos + cc_basis * Vector3(1.5, 10.5, 3.0))

