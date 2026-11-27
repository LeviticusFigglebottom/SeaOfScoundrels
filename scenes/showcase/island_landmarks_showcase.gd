extends Node3D
## Visual verification showcase for Wave I-2..I-23 sculpted 3D island landmarks (94 BC7 PBR GLBs),
## winding walkable terrain trails, and native batched MultiMesh `IslandDetails` ground foliage,
## highland cliff-ledge scrub, coastal dressing, living shore fauna, twilight lantern halos & steep-slope cliff buttresses across all 14 islands.
##
## Usage:
##   tools/capture.sh res://scenes/showcase/island_landmarks_showcase.tscn cutlass_overhaul 2 5 -- shot=cutlass_overhaul
##
## User args (after `--`), all optional:
##   shot=<name>       79 visual audit shots (22 galleries + all 14 archipelago islands + 14 2.2 m daytime on-foot walk-up shots + 14 twilight/dusk on-foot atmospheric lantern-halo audits + 15 golden-hour sunset, storm squall, storm-flood waterfall, moonlit waterfall, dawn terrace, coastal/crab macro & trail flagstone close-up showcase shots - 100% 14-of-14 island coverage in both daylight & twilight):
##                     gallery_geology|gallery_setpieces|gallery_storytelling|gallery_skyline|gallery_coastal|gallery_harbour_ruins|gallery_maritime_relics|gallery_world_craft|gallery_onfoot_craft|gallery_story_craft|gallery_fort_vault|gallery_island_lore|gallery_nautical_craft|gallery_sea_lore|gallery_corsair_relics|gallery_expedition_craft|gallery_haven_relics|gallery_frontier_craft|gallery_armada_relics|gallery_privateer_craft|gallery_sovereign_craft|gallery_buccaneer_craft|
##                     cutlass_overhaul|skull_bluff|emerald_temple|galleons_catwalk|cinder_basalt|gulls_arch|
##                     sovereigns_bastion|ironwatch_fort|crescent_atoll|barnacle_haven|
##                     wreckers_shoal|sirens_tooth|smugglers_cove|port_scoundrel|
##                     onfoot_cutlass_trail|onfoot_port_harbour|onfoot_emerald_canyon|onfoot_smugglers_cove|onfoot_crescent_lagoon|onfoot_cinder_caldera|onfoot_skull_bluff|onfoot_galleons_reach|onfoot_sovereigns_bastion|onfoot_ironwatch_fort|onfoot_barnacle_haven|onfoot_gulls_arch|onfoot_wreckers_shoal|onfoot_sirens_tooth|
##                     onfoot_port_dusk|onfoot_skull_dusk|onfoot_cinder_dusk|onfoot_emerald_dusk|onfoot_galleons_dusk|onfoot_sovereigns_dusk|onfoot_ironwatch_dusk|onfoot_smugglers_dusk|onfoot_crescent_dusk|onfoot_cutlass_dusk|onfoot_barnacle_dusk|onfoot_gulls_dusk|onfoot_wreckers_dusk|onfoot_sirens_dusk|
##                     onfoot_emerald_sunset|onfoot_port_sunset|onfoot_cutlass_shells|onfoot_sovereigns_waterfall_sunset|onfoot_cinder_sunset|onfoot_gulls_tidepool|onfoot_emerald_moonlit|onfoot_sovereigns_dawn|onfoot_crescent_driftwood|onfoot_cinder_storm|onfoot_port_storm|onfoot_cutlass_flagstones|onfoot_emerald_storm|onfoot_sovereigns_waterfall_storm|onfoot_cutlass_crab
##   time=<hour>       hour of day (auto per-shot sunlit / golden-hour / twilight default)
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
##   L=gallery_maritime_relics K=gallery_world_craft J=gallery_onfoot_craft H=gallery_story_craft
##   G=gallery_fort_vault  F=gallery_island_lore D=gallery_nautical_craft S=gallery_sea_lore
##   A=gallery_corsair_relics Z=gallery_expedition_craft X=gallery_haven_relics C=gallery_frontier_craft
##   V=gallery_armada_relics B=gallery_privateer_craft N=gallery_sovereign_craft M=gallery_buccaneer_craft

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

const ONFOOT_CRAFT_GLBS: Array[String] = [
	"wooden_trail_footbridge.glb",
	"coastal_smuggler_jetty.glb",
	"ancient_ruined_obelisk_gate.glb",
	"pirate_lookout_bell_frame.glb",
]

const STORY_CRAFT_GLBS: Array[String] = [
	"pirate_tavern_supply_cart.glb",
	"sunken_anchor_memorial.glb",
	"ancient_sun_dial_plaza.glb",
	"volcanic_obsidian_fissure_vent.glb",
]

const FORT_VAULT_GLBS: Array[String] = [
	"stone_well_courtyard.glb",
	"ruined_sea_fort_cannon_bastion.glb",
	"pirate_treasure_vault_door.glb",
	"wooden_shipwreck_crow_nest_mast.glb",
]

const ISLAND_LORE_GLBS: Array[String] = [
	"pirate_rum_distillery_shack.glb",
	"ancient_jade_serpent_totem.glb",
	"coastal_driftwood_arch_camp.glb",
	"volcanic_obsidian_bridge_ruin.glb",
]

const NAUTICAL_CRAFT_GLBS: Array[String] = [
	"coastal_rope_ferry_pulley.glb",
	"ancient_sunken_bell_shrine.glb",
	"pirate_map_planning_table_tent.glb",
	"volcanic_basalt_obelisk_brazier.glb",
]

const SEA_LORE_GLBS: Array[String] = [
	"pirate_shipwright_timber_rack.glb",
	"ancient_tidal_obelisk_mirror.glb",
	"smuggler_rope_cargo_hoist.glb",
	"volcanic_obsidian_forge_anvil.glb",
]

const CORSAIR_RELICS_GLBS: Array[String] = [
	"pirate_bounty_gallows_post.glb",
	"ancient_kraken_stone_fountain.glb",
	"coastal_salted_fish_drying_rack.glb",
	"volcanic_obsidian_dragon_maw.glb",
]

const EXPEDITION_CRAFT_GLBS: Array[String] = [
	"pirate_chart_navigator_gazebo.glb",
	"ancient_sun_serpent_archway.glb",
	"coastal_shipwreck_barricade_camp.glb",
	"volcanic_obsidian_lava_gate.glb",
]

const HAVEN_RELICS_GLBS: Array[String] = [
	"pirate_harbour_clock_belltower.glb",
	"ancient_celestial_moon_dial.glb",
	"coastal_buccaneer_grog_stall.glb",
	"volcanic_obsidian_anchor_monolith.glb",
]

const FRONTIER_CRAFT_GLBS: Array[String] = [
	"pirate_powder_magazine_bunker.glb",
	"ancient_coral_leviathan_altar.glb",
	"coastal_boatbuilder_slipway_winch.glb",
	"volcanic_obsidian_ember_totem.glb",
]

const ARMADA_RELICS_GLBS: Array[String] = [
	"pirate_ropewalk_cordage_loom.glb",
	"ancient_tidal_compass_sanctum.glb",
	"coastal_buccaneer_careening_cradle.glb",
	"volcanic_obsidian_kraken_altar.glb",
]

const PRIVATEER_CRAFT_GLBS: Array[String] = [
	"pirate_sailmaker_rigging_loft.glb",
	"ancient_serpent_tide_portal.glb",
	"coastal_castaway_raft_shelter.glb",
	"volcanic_obsidian_phoenix_brazier.glb",
]

const SOVEREIGN_CRAFT_GLBS: Array[String] = [
	"pirate_cooperage_barrel_workshop.glb",
	"ancient_astral_tide_obelisk.glb",
	"coastal_buccaneer_net_mending_pier.glb",
	"volcanic_obsidian_leviathan_spire.glb",
]

const BUCCANEER_CRAFT_GLBS: Array[String] = [
	"pirate_blacksmith_anchor_forge.glb",
	"ancient_abyssal_nautilus_shrine.glb",
	"coastal_smuggler_signal_tripod.glb",
	"volcanic_obsidian_wyrm_arch.glb",
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
var _emerald_wf_top_world: Vector3 = Vector3.ZERO
var _emerald_wf_pool_world: Vector3 = Vector3.ZERO
var _has_emerald_waterfall: bool = false
var _cutlass_shell_local: Vector3 = Vector3.ZERO
var _has_cutlass_shell: bool = false
var _cutlass_flagstone_local: Vector3 = Vector3.ZERO
var _cutlass_flagstone_look_dir: Vector3 = Vector3.FORWARD
var _cutlass_flagstone_scale_y: float = 0.85
var _has_cutlass_flagstone: bool = false
var _cutlass_crab_idx: int = -1
var _cutlass_crab_local: Vector3 = Vector3.ZERO
var _cutlass_crab_cam_dir: Vector3 = Vector3.FORWARD
var _has_cutlass_crab: bool = false
var _galleons_hero_aim: Vector3 = Vector3.ZERO
var _gulls_arch_aim: Vector3 = Vector3.ZERO
var _gulls_tidepool_local: Vector3 = Vector3.ZERO
var _gulls_tidepool_cam_dir: Vector3 = Vector3.FORWARD
var _gulls_tidepool_scale_y: float = 1.0
var _has_gulls_tidepool: bool = false
var _sovereigns_hero_aim: Vector3 = Vector3.ZERO
var _sovereigns_wf_top_world: Vector3 = Vector3.ZERO
var _sovereigns_wf_pool_world: Vector3 = Vector3.ZERO
var _sovereigns_wf_out_dir: Vector3 = Vector3.FORWARD
var _has_sovereigns_waterfall: bool = false
var _ironwatch_hero_aim: Vector3 = Vector3.ZERO
var _crescent_hero_aim: Vector3 = Vector3.ZERO
var _crescent_driftwood_local: Vector3 = Vector3.ZERO
var _crescent_driftwood_cam_dir: Vector3 = Vector3.FORWARD
var _crescent_driftwood_scale_y: float = 1.0
var _has_crescent_driftwood: bool = false
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

	if OS.has_feature("movie") and Audio != null:
		Audio.ambience_enabled = false

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
	if Audio != null:
		Audio.ambience_enabled = false
		Audio.set_process(false)
		for child in Audio.find_children("*", "", true, false):
			if child is AudioStreamPlayer:
				var ap := child as AudioStreamPlayer
				ap.stop()
				ap.stream = null
			elif child is AudioStreamPlayer3D:
				var ap3 := child as AudioStreamPlayer3D
				ap3.stop()
				ap3.stream = null
	TreasureCatalog.clear_mesh_cache()
	IslandDetails.clear_shared_cache()
	Outpost.clear_shared_cache()
	IslandWaterfall.clear_shared_cache()
	VolcanicFumarole.clear_shared_cache()
	FortVault.clear_shared_cache()
	FortBattery.clear_shared_cache()
	MerchantStall.clear_shared_cache()
	DigSite.clear_shared_cache()
	MessageBottle.clear_shared_cache()
	SupplyBarrel.clear_shared_cache()
	CoralReef.clear_shared_cache()
	ReefFishSchool.clear_shared_cache()
	MantaRay.clear_shared_cache()
	IslandWildlife.clear_shared_cache()


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
		KEY_J:
			next_shot = "gallery_onfoot_craft"
		KEY_H:
			next_shot = "gallery_story_craft"
		KEY_G:
			next_shot = "gallery_fort_vault"
		KEY_F:
			next_shot = "gallery_island_lore"
		KEY_D:
			next_shot = "gallery_nautical_craft"
		KEY_S:
			next_shot = "gallery_sea_lore"
		KEY_A:
			next_shot = "gallery_corsair_relics"
		KEY_Z:
			next_shot = "gallery_expedition_craft"
		KEY_X:
			next_shot = "gallery_haven_relics"
		KEY_C:
			next_shot = "gallery_frontier_craft"
		KEY_V:
			next_shot = "gallery_armada_relics"
		KEY_B:
			next_shot = "gallery_privateer_craft"
		KEY_N:
			next_shot = "gallery_sovereign_craft"
		KEY_M:
			next_shot = "gallery_buccaneer_craft"
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
		"gallery_onfoot_craft":
			default_time = 15.4
		"gallery_story_craft":
			default_time = 15.6
		"gallery_fort_vault":
			default_time = 15.6
		"gallery_island_lore":
			default_time = 15.6
		"gallery_nautical_craft":
			default_time = 15.6
		"gallery_sea_lore":
			default_time = 15.6
		"gallery_corsair_relics":
			default_time = 15.6
		"gallery_expedition_craft":
			default_time = 15.6
		"gallery_haven_relics":
			default_time = 15.6
		"gallery_frontier_craft":
			default_time = 15.6
		"gallery_armada_relics":
			default_time = 15.6
		"gallery_privateer_craft":
			default_time = 15.6
		"gallery_sovereign_craft":
			default_time = 15.6
		"gallery_buccaneer_craft":
			default_time = 15.6
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
		"onfoot_cutlass_trail":
			default_time = 10.6
		"onfoot_port_harbour":
			default_time = 10.2
		"onfoot_emerald_canyon":
			default_time = 10.6
		"onfoot_smugglers_cove":
			default_time = 15.8
		"onfoot_crescent_lagoon":
			default_time = 15.2
		"onfoot_cinder_caldera":
			default_time = 17.0
		"onfoot_skull_bluff":
			default_time = 16.2
		"onfoot_galleons_reach":
			default_time = 15.8
		"onfoot_sovereigns_bastion":
			default_time = 15.6
		"onfoot_ironwatch_fort":
			default_time = 10.4
		"onfoot_barnacle_haven":
			default_time = 10.2
		"onfoot_gulls_arch":
			default_time = 10.4
		"onfoot_wreckers_shoal":
			default_time = 15.8
		"onfoot_sirens_tooth":
			default_time = 10.1
		"onfoot_port_dusk":
			default_time = 19.6
		"onfoot_skull_dusk":
			default_time = 20.4
		"onfoot_cinder_dusk":
			default_time = 19.8
		"onfoot_emerald_dusk":
			default_time = 20.0
		"onfoot_galleons_dusk":
			default_time = 19.7
		"onfoot_sovereigns_dusk":
			default_time = 19.9
		"onfoot_ironwatch_dusk":
			default_time = 19.8
		"onfoot_smugglers_dusk":
			default_time = 20.1
		"onfoot_crescent_dusk":
			default_time = 20.2
		"onfoot_cutlass_dusk":
			default_time = 19.9
		"onfoot_barnacle_dusk":
			default_time = 19.7
		"onfoot_gulls_dusk":
			default_time = 20.0
		"onfoot_wreckers_dusk":
			default_time = 20.1
		"onfoot_sirens_dusk":
			default_time = 20.2
		"onfoot_emerald_sunset":
			default_time = 17.4
		"onfoot_port_sunset":
			default_time = 17.4
		"onfoot_cutlass_shells":
			default_time = 13.8
		"onfoot_sovereigns_waterfall_sunset":
			default_time = 17.4
		"onfoot_cinder_sunset":
			default_time = 17.3
		"onfoot_gulls_tidepool":
			default_time = 13.6
		"onfoot_emerald_moonlit":
			default_time = 22.8
		"onfoot_sovereigns_dawn":
			default_time = 6.2
		"onfoot_crescent_driftwood":
			default_time = 13.8
		"onfoot_cinder_storm":
			default_time = 15.2
		"onfoot_port_storm":
			default_time = 20.4
		"onfoot_cutlass_flagstones":
			default_time = 13.8
		"onfoot_emerald_storm":
			default_time = 15.0
		"onfoot_sovereigns_waterfall_storm":
			default_time = 15.0
		"onfoot_cutlass_crab":
			default_time = 13.8
	var default_storm := 0.0
	if _shot == "onfoot_cinder_storm" or _shot == "onfoot_emerald_storm" \
			or _shot == "onfoot_sovereigns_waterfall_storm":
		default_storm = 0.92
	elif _shot == "onfoot_port_storm":
		default_storm = 0.90
	var default_cloud := 0.30 if _shot.begins_with("gallery_") else 0.34
	if _shot == "onfoot_cinder_storm" or _shot == "onfoot_emerald_storm" \
			or _shot == "onfoot_sovereigns_waterfall_storm":
		default_cloud = 0.95
	elif _shot == "onfoot_port_storm":
		default_cloud = 0.94
	elif _shot == "cinder_basalt":
		default_cloud = 0.44
	elif _shot == "onfoot_cinder_caldera":
		default_cloud = 0.42
	elif _shot == "onfoot_cinder_dusk":
		default_cloud = 0.40
	elif _shot == "onfoot_emerald_moonlit":
		default_cloud = 0.18
	elif _shot == "onfoot_gulls_tidepool" or _shot == "onfoot_crescent_driftwood" \
			or _shot == "onfoot_cutlass_crab":
		default_cloud = 0.22
	elif _shot == "onfoot_cutlass_shells" or _shot == "onfoot_cutlass_flagstones":
		default_cloud = 0.24
	elif _shot == "onfoot_emerald_sunset" or _shot == "onfoot_sovereigns_waterfall_sunset":
		default_cloud = 0.26
	elif _shot == "crescent_atoll" or _shot == "onfoot_crescent_lagoon" or _shot == "onfoot_port_dusk" \
			or _shot == "onfoot_crescent_dusk" or _shot == "onfoot_port_sunset" \
			or _shot == "onfoot_sovereigns_dawn":
		default_cloud = 0.28
	elif _shot == "port_scoundrel" or _shot == "onfoot_cutlass_trail" or _shot == "onfoot_cutlass_dusk" \
			or _shot == "onfoot_port_harbour" or _shot == "onfoot_emerald_canyon" \
			or _shot == "onfoot_barnacle_haven" or _shot == "onfoot_barnacle_dusk" \
			or _shot == "onfoot_gulls_arch" or _shot == "onfoot_gulls_dusk" \
			or _shot == "onfoot_skull_dusk" or _shot == "onfoot_emerald_dusk" or _shot == "onfoot_galleons_dusk" \
			or _shot == "onfoot_sovereigns_dusk":
		default_cloud = 0.30
	elif _shot == "barnacle_haven" or _shot == "onfoot_smugglers_cove" or _shot == "onfoot_smugglers_dusk" \
			or _shot == "onfoot_galleons_reach" or _shot == "onfoot_sovereigns_bastion" \
			or _shot == "onfoot_ironwatch_fort" or _shot == "onfoot_ironwatch_dusk" \
			or _shot == "onfoot_sirens_tooth" or _shot == "onfoot_sirens_dusk" \
			or _shot == "onfoot_cinder_sunset":
		default_cloud = 0.32
	elif _shot == "wreckers_shoal":
		default_cloud = 0.36
	Weather.time_of_day = float(_args.get("time", str(default_time)))
	var storm := float(_args.get("storm", str(default_storm)))
	var cloud := float(_args.get("cloud", str(default_cloud)))
	var wind_spd := lerpf(8.2, 20.0, clampf(storm, 0.0, 1.0))
	Weather.set_weather(storm, wind_spd, deg_to_rad(30.0), 0.0, cloud)
	Weather.cloud_offset = Vector2(240.0, 120.0)

	Sea.amp_scale = lerpf(Sea.AMP_CALM, Sea.AMP_STORM, storm)
	if _shot.begins_with("gallery_"):
		Sea.amp_scale = 0.28
	elif _shot == "onfoot_cinder_storm" or _shot == "onfoot_port_storm" \
			or _shot == "onfoot_emerald_storm" or _shot == "onfoot_sovereigns_waterfall_storm":
		# Keep full storm sea_amp_scale (>= 2.25) so Local-GPU M59 rain-wetness/puddles & M61 storm-flood waterfalls shine live!
		Sea.amp_scale = maxf(Sea.amp_scale, 2.28)
		RenderingServer.global_shader_parameter_set(&"sea_amp_scale", Sea.amp_scale)
	elif _shot == "onfoot_crescent_driftwood" or _shot == "onfoot_cutlass_crab":
		Sea.amp_scale = 0.30
	elif _shot == "onfoot_gulls_tidepool" or _shot == "onfoot_cutlass_flagstones":
		Sea.amp_scale = 0.32
	elif _shot == "cutlass_overhaul" or _shot == "gulls_arch" or _shot == "onfoot_gulls_arch" \
			or _shot == "onfoot_gulls_dusk":
		Sea.amp_scale = 0.46
	elif _shot == "onfoot_cutlass_trail" or _shot == "onfoot_cutlass_dusk" \
			or _shot == "onfoot_sovereigns_bastion" or _shot == "onfoot_sovereigns_dusk" \
			or _shot == "onfoot_ironwatch_fort" or _shot == "onfoot_ironwatch_dusk":
		Sea.amp_scale = 0.44
	elif _shot == "galleons_catwalk" or _shot == "emerald_temple" or _shot == "onfoot_emerald_canyon" \
			or _shot == "onfoot_emerald_dusk" or _shot == "onfoot_emerald_sunset" \
			or _shot == "onfoot_sovereigns_waterfall_sunset" \
			or _shot == "onfoot_skull_bluff" or _shot == "onfoot_skull_dusk":
		Sea.amp_scale = 0.42
	elif _shot == "cinder_basalt":
		Sea.amp_scale = 0.62
	elif _shot == "onfoot_cinder_caldera" or _shot == "onfoot_cinder_dusk" \
			or _shot == "onfoot_cinder_sunset":
		Sea.amp_scale = 0.60
	elif _shot == "sovereigns_bastion" or _shot == "ironwatch_fort" or _shot == "onfoot_sovereigns_dawn":
		Sea.amp_scale = 0.48
	elif _shot == "crescent_atoll" or _shot == "onfoot_crescent_lagoon" or _shot == "onfoot_crescent_dusk" \
			or _shot == "onfoot_cutlass_shells":
		Sea.amp_scale = 0.34
	elif _shot == "smugglers_cove" or _shot == "onfoot_port_harbour" or _shot == "onfoot_port_dusk" \
			or _shot == "onfoot_port_sunset" or _shot == "onfoot_smugglers_cove" or _shot == "onfoot_smugglers_dusk" \
			or _shot == "onfoot_emerald_moonlit":
		Sea.amp_scale = 0.36
	elif _shot == "port_scoundrel":
		Sea.amp_scale = 0.38
	elif _shot == "barnacle_haven" or _shot == "onfoot_galleons_reach" or _shot == "onfoot_galleons_dusk" \
			or _shot == "onfoot_barnacle_haven" or _shot == "onfoot_barnacle_dusk":
		Sea.amp_scale = 0.40
	elif _shot == "wreckers_shoal" or _shot == "onfoot_wreckers_shoal" or _shot == "onfoot_wreckers_dusk":
		Sea.amp_scale = 0.50
	elif _shot == "sirens_tooth" or _shot == "onfoot_sirens_tooth" or _shot == "onfoot_sirens_dusk":
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
		elif m_name.begins_with("Lantern_MagmaVent"):
			light.light_color = Color(1.0, 0.36, 0.08)
			light.light_energy = 5.6
			light.omni_range = 21.0
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
		elif m_name.begins_with("Lantern_Footbridge"):
			light.light_color = Color(1.0, 0.74, 0.34)
			light.light_energy = 3.6
			light.omni_range = 15.0
			light.omni_attenuation = 1.30
			amp = 0.16
		elif m_name.begins_with("Lantern_Jetty"):
			light.light_color = Color(1.0, 0.70, 0.28)
			light.light_energy = 4.0
			light.omni_range = 17.0
			light.omni_attenuation = 1.28
			amp = 0.18
		elif m_name.begins_with("Lantern_ObeliskGate"):
			light.light_color = Color(0.20, 0.96, 0.82)
			light.light_energy = 4.6
			light.omni_range = 19.0
			light.omni_attenuation = 1.25
			amp = 0.15
		elif m_name.begins_with("Lantern_BellFrame"):
			light.light_color = Color(1.0, 0.76, 0.32)
			light.light_energy = 4.2
			light.omni_range = 18.0
			light.omni_attenuation = 1.28
			amp = 0.17
		elif m_name.begins_with("Lantern_Cart"):
			light.light_color = Color(1.0, 0.74, 0.32)
			light.light_energy = 3.8
			light.omni_range = 16.0
			light.omni_attenuation = 1.30
			amp = 0.17
		elif m_name.begins_with("Lantern_AnchorForge"):
			light.light_color = Color(1.00, 0.64, 0.24)
			light.light_energy = 4.6
			light.omni_range = 18.0
			light.omni_attenuation = 1.28
			amp = 0.20
		elif m_name.begins_with("Lantern_Anchor"):
			light.light_color = Color(1.0, 0.70, 0.28)
			light.light_energy = 4.0
			light.omni_range = 17.0
			light.omni_attenuation = 1.28
			amp = 0.18
		elif m_name.begins_with("Lantern_Sundial"):
			light.light_color = Color(0.24, 0.94, 0.88)
			light.light_energy = 4.8
			light.omni_range = 20.0
			light.omni_attenuation = 1.25
			amp = 0.15
		elif m_name.begins_with("Lantern_Well"):
			light.light_color = Color(1.0, 0.74, 0.36)
			light.light_energy = 3.8
			light.omni_range = 16.0
			light.omni_attenuation = 1.30
			amp = 0.16
		elif m_name.begins_with("Lantern_Bastion"):
			light.light_color = Color(1.0, 0.56, 0.18)
			light.light_energy = 4.4
			light.omni_range = 19.0
			light.omni_attenuation = 1.28
			amp = 0.19
		elif m_name.begins_with("Lantern_Vault"):
			light.light_color = Color(0.26, 0.96, 0.78)
			light.light_energy = 4.8
			light.omni_range = 20.0
			light.omni_attenuation = 1.25
			amp = 0.17
		elif m_name.begins_with("Lantern_CrowNest"):
			light.light_color = Color(1.0, 0.70, 0.28)
			light.light_energy = 4.2
			light.omni_range = 18.0
			light.omni_attenuation = 1.28
			amp = 0.17
		elif m_name.begins_with("Lantern_Still"):
			light.light_color = Color(1.0, 0.72, 0.28)
			light.light_energy = 4.0
			light.omni_range = 17.0
			light.omni_attenuation = 1.28
			amp = 0.18
		elif m_name.begins_with("Lantern_SerpentPortal"):
			light.light_color = Color(0.28, 0.96, 0.92)
			light.light_energy = 5.0
			light.omni_range = 20.0
			light.omni_attenuation = 1.25
			amp = 0.18
		elif m_name.begins_with("Lantern_Serpent"):
			light.light_color = Color(0.20, 0.98, 0.72)
			light.light_energy = 4.8
			light.omni_range = 20.0
			light.omni_attenuation = 1.25
			amp = 0.16
		elif m_name.begins_with("Lantern_Bivouac"):
			light.light_color = Color(1.0, 0.64, 0.22)
			light.light_energy = 4.2
			light.omni_range = 17.0
			light.omni_attenuation = 1.30
			amp = 0.20
		elif m_name.begins_with("Lantern_VolcBridge"):
			light.light_color = Color(1.0, 0.38, 0.08)
			light.light_energy = 5.4
			light.omni_range = 21.0
			light.omni_attenuation = 1.25
			amp = 0.22
		elif m_name.begins_with("Lantern_FerryWinch"):
			light.light_color = Color(1.0, 0.72, 0.30)
			light.light_energy = 4.0
			light.omni_range = 17.0
			light.omni_attenuation = 1.28
			amp = 0.18
		elif m_name.begins_with("Lantern_BellShrine"):
			light.light_color = Color(0.22, 0.96, 0.84)
			light.light_energy = 4.8
			light.omni_range = 20.0
			light.omni_attenuation = 1.25
			amp = 0.15
		elif m_name.begins_with("Lantern_MapTent"):
			light.light_color = Color(1.0, 0.68, 0.26)
			light.light_energy = 4.2
			light.omni_range = 17.0
			light.omni_attenuation = 1.30
			amp = 0.18
		elif m_name.begins_with("Lantern_BasaltBrazier"):
			light.light_color = Color(1.0, 0.40, 0.08)
			light.light_energy = 5.4
			light.omni_range = 21.0
			light.omni_attenuation = 1.25
			amp = 0.22
		elif m_name.begins_with("Lantern_Shipyard"):
			light.light_color = Color(1.0, 0.72, 0.30)
			light.light_energy = 4.2
			light.omni_range = 18.0
			light.omni_attenuation = 1.28
			amp = 0.18
		elif m_name.begins_with("Lantern_MirrorShrine"):
			light.light_color = Color(0.24, 0.96, 0.90)
			light.light_energy = 4.8
			light.omni_range = 20.0
			light.omni_attenuation = 1.25
			amp = 0.14
		elif m_name.begins_with("Lantern_SmugglerHoist"):
			light.light_color = Color(1.0, 0.66, 0.24)
			light.light_energy = 4.0
			light.omni_range = 17.0
			light.omni_attenuation = 1.30
			amp = 0.18
		elif m_name.begins_with("Lantern_VolcForge"):
			light.light_color = Color(1.0, 0.38, 0.08)
			light.light_energy = 5.6
			light.omni_range = 21.0
			light.omni_attenuation = 1.25
			amp = 0.22
		elif m_name.begins_with("Lantern_BountyPost"):
			light.light_color = Color(1.0, 0.70, 0.28)
			light.light_energy = 4.2
			light.omni_range = 18.0
			light.omni_attenuation = 1.28
			amp = 0.18
		elif m_name.begins_with("Lantern_KrakenShrine"):
			light.light_color = Color(0.20, 0.96, 0.86)
			light.light_energy = 4.8
			light.omni_range = 20.0
			light.omni_attenuation = 1.25
			amp = 0.15
		elif m_name.begins_with("Lantern_FishRack"):
			light.light_color = Color(1.0, 0.74, 0.32)
			light.light_energy = 4.0
			light.omni_range = 17.0
			light.omni_attenuation = 1.30
			amp = 0.17
		elif m_name.begins_with("Lantern_DragonMaw"):
			light.light_color = Color(1.0, 0.36, 0.08)
			light.light_energy = 5.6
			light.omni_range = 21.0
			light.omni_attenuation = 1.25
			amp = 0.22
		elif m_name.begins_with("Lantern_NavGazebo"):
			light.light_color = Color(1.0, 0.74, 0.30)
			light.light_energy = 4.2
			light.omni_range = 18.0
			light.omni_attenuation = 1.28
			amp = 0.17
		elif m_name.begins_with("Lantern_SunSerpent"):
			light.light_color = Color(0.22, 0.98, 0.76)
			light.light_energy = 4.8
			light.omni_range = 20.0
			light.omni_attenuation = 1.25
			amp = 0.15
		elif m_name.begins_with("Lantern_BarricadeCamp"):
			light.light_color = Color(1.0, 0.66, 0.24)
			light.light_energy = 4.2
			light.omni_range = 18.0
			light.omni_attenuation = 1.30
			amp = 0.19
		elif m_name.begins_with("Lantern_LavaGate"):
			light.light_color = Color(1.0, 0.36, 0.08)
			light.light_energy = 5.6
			light.omni_range = 21.0
			light.omni_attenuation = 1.25
			amp = 0.22
		elif m_name.begins_with("Lantern_TideClock"):
			light.light_color = Color(1.0, 0.74, 0.32)
			light.light_energy = 4.4
			light.omni_range = 19.0
			light.omni_attenuation = 1.28
			amp = 0.16
		elif m_name.begins_with("Lantern_MoonDial"):
			light.light_color = Color(0.28, 0.92, 1.0)
			light.light_energy = 4.8
			light.omni_range = 20.0
			light.omni_attenuation = 1.25
			amp = 0.14
		elif m_name.begins_with("Lantern_GrogStall"):
			light.light_color = Color(1.0, 0.68, 0.26)
			light.light_energy = 4.2
			light.omni_range = 18.0
			light.omni_attenuation = 1.30
			amp = 0.18
		elif m_name.begins_with("Lantern_VolcAnchor"):
			light.light_color = Color(1.0, 0.36, 0.08)
			light.light_energy = 5.6
			light.omni_range = 21.0
			light.omni_attenuation = 1.25
			amp = 0.22
		elif m_name.begins_with("Lantern_PowderBunker"):
			light.light_color = Color(1.00, 0.72, 0.34)
			light.light_energy = 4.2
			light.omni_range = 18.0
			light.omni_attenuation = 1.28
			amp = 0.16
		elif m_name.begins_with("Lantern_CoralAltar"):
			light.light_color = Color(0.32, 0.96, 0.90)
			light.light_energy = 4.8
			light.omni_range = 20.0
			light.omni_attenuation = 1.25
			amp = 0.18
		elif m_name.begins_with("Lantern_BoatSlipway"):
			light.light_color = Color(1.00, 0.78, 0.42)
			light.light_energy = 4.0
			light.omni_range = 18.0
			light.omni_attenuation = 1.28
			amp = 0.16
		elif m_name.begins_with("Lantern_EmberTotem"):
			light.light_color = Color(1.00, 0.40, 0.14)
			light.light_energy = 5.6
			light.omni_range = 21.0
			light.omni_attenuation = 1.25
			amp = 0.24
		elif m_name.begins_with("Lantern_Ropewalk"):
			light.light_color = Color(1.00, 0.76, 0.38)
			light.light_energy = 4.2
			light.omni_range = 18.0
			light.omni_attenuation = 1.28
			amp = 0.16
		elif m_name.begins_with("Lantern_TidalCompass"):
			light.light_color = Color(0.30, 0.96, 0.90)
			light.light_energy = 4.8
			light.omni_range = 20.0
			light.omni_attenuation = 1.25
			amp = 0.18
		elif m_name.begins_with("Lantern_Careening"):
			light.light_color = Color(1.00, 0.72, 0.34)
			light.light_energy = 4.2
			light.omni_range = 18.0
			light.omni_attenuation = 1.28
			amp = 0.16
		elif m_name.begins_with("Lantern_VolcKraken"):
			light.light_color = Color(1.00, 0.38, 0.14)
			light.light_energy = 5.6
			light.omni_range = 21.0
			light.omni_attenuation = 1.25
			amp = 0.24
		# Wave I-21 Privateer Craft lanterns (Lantern_SerpentPortal matched above Lantern_Serpent).
		elif m_name.begins_with("Lantern_Sailmaker"):
			light.light_color = Color(1.00, 0.78, 0.42)
			light.light_energy = 4.2
			light.omni_range = 18.0
			light.omni_attenuation = 1.28
			amp = 0.16
		elif m_name.begins_with("Lantern_CastawayCamp"):
			light.light_color = Color(1.00, 0.66, 0.28)
			light.light_energy = 4.4
			light.omni_range = 18.0
			light.omni_attenuation = 1.30
			amp = 0.20
		elif m_name.begins_with("Lantern_PhoenixBrazier"):
			light.light_color = Color(1.00, 0.42, 0.14)
			light.light_energy = 5.6
			light.omni_range = 21.0
			light.omni_attenuation = 1.25
			amp = 0.24
		# Wave I-22 Sovereign Craft lanterns.
		elif m_name.begins_with("Lantern_Cooperage"):
			light.light_color = Color(1.00, 0.74, 0.34)
			light.light_energy = 4.4
			light.omni_range = 18.0
			light.omni_attenuation = 1.28
			amp = 0.18
		elif m_name.begins_with("Lantern_AstralObelisk"):
			light.light_color = Color(0.28, 0.96, 0.92)
			light.light_energy = 5.0
			light.omni_range = 20.0
			light.omni_attenuation = 1.25
			amp = 0.18
		elif m_name.begins_with("Lantern_NetPier"):
			light.light_color = Color(1.00, 0.78, 0.42)
			light.light_energy = 4.0
			light.omni_range = 18.0
			light.omni_attenuation = 1.28
			amp = 0.16
		elif m_name.begins_with("Lantern_VolcSpire"):
			light.light_color = Color(1.00, 0.40, 0.14)
			light.light_energy = 5.6
			light.omni_range = 21.0
			light.omni_attenuation = 1.25
			amp = 0.24
		# Wave I-23 Buccaneer Craft lanterns (Lantern_AnchorForge matched above Lantern_Anchor).
		elif m_name.begins_with("Lantern_NautilusShrine"):
			light.light_color = Color(0.28, 0.96, 0.92)
			light.light_energy = 5.0
			light.omni_range = 20.0
			light.omni_attenuation = 1.25
			amp = 0.18
		elif m_name.begins_with("Lantern_SignalTripod"):
			light.light_color = Color(1.00, 0.70, 0.30)
			light.light_energy = 4.4
			light.omni_range = 18.0
			light.omni_attenuation = 1.28
			amp = 0.20
		elif m_name.begins_with("Lantern_WyrmArch"):
			light.light_color = Color(1.00, 0.38, 0.14)
			light.light_energy = 5.6
			light.omni_range = 21.0
			light.omni_attenuation = 1.25
			amp = 0.24
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
			or _shot == "gallery_maritime_relics" or _shot == "gallery_world_craft" \
			or _shot == "gallery_onfoot_craft" or _shot == "gallery_story_craft" \
			or _shot == "gallery_fort_vault" or _shot == "gallery_island_lore" \
			or _shot == "gallery_nautical_craft" or _shot == "gallery_sea_lore" \
			or _shot == "gallery_corsair_relics" or _shot == "gallery_expedition_craft" \
			or _shot == "gallery_haven_relics" or _shot == "gallery_frontier_craft" \
			or _shot == "gallery_armada_relics" or _shot == "gallery_privateer_craft" \
			or _shot == "gallery_sovereign_craft" or _shot == "gallery_buccaneer_craft"
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
	elif _shot == "gallery_onfoot_craft":
		_layout_onfoot_craft_gallery()
	elif _shot == "gallery_story_craft":
		_layout_story_craft_gallery()
	elif _shot == "gallery_fort_vault":
		_layout_fort_vault_gallery()
	elif _shot == "gallery_island_lore":
		_layout_island_lore_gallery()
	elif _shot == "gallery_nautical_craft":
		_layout_nautical_craft_gallery()
	elif _shot == "gallery_sea_lore":
		_layout_sea_lore_gallery()
	elif _shot == "gallery_corsair_relics":
		_layout_corsair_relics_gallery()
	elif _shot == "gallery_expedition_craft":
		_layout_expedition_craft_gallery()
	elif _shot == "gallery_haven_relics":
		_layout_haven_relics_gallery()
	elif _shot == "gallery_frontier_craft":
		_layout_frontier_craft_gallery()
	elif _shot == "gallery_armada_relics":
		_layout_armada_relics_gallery()
	elif _shot == "gallery_privateer_craft":
		_layout_privateer_craft_gallery()
	elif _shot == "gallery_sovereign_craft":
		_layout_sovereign_craft_gallery()
	elif _shot == "gallery_buccaneer_craft":
		_layout_buccaneer_craft_gallery()
	else:
		_layout_setpieces_gallery()


func _layout_buccaneer_craft_gallery() -> void:
	# Stage Wave I-23 pirate blacksmith anchor forge, ancient abyssal nautilus shrine, coastal smuggler signal tripod & volcanic obsidian wyrm arch on the sunlit sandbar.
	var items: Array[Dictionary] = []
	var total_span := 0.0
	var gap := 4.6
	for i in BUCCANEER_CRAFT_GLBS.size():
		var fn := BUCCANEER_CRAFT_GLBS[i]
		var inst := _spawn_landmark(fn, _gallery_root, "BuccaneerCraft_%02d" % i, Transform3D.IDENTITY, null, true)
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
		if fn == "pirate_blacksmith_anchor_forge.glb":
			cz += 1.4
		elif fn == "coastal_smuggler_signal_tripod.glb":
			cz += 1.6
		elif fn == "volcanic_obsidian_wyrm_arch.glb":
			cz += 0.8
		var ground_y := _sandbar_y(cx, cz) - 0.12
		var yaw := PI - t_norm * 0.24
		if fn == "pirate_blacksmith_anchor_forge.glb":
			yaw += 0.28
		elif fn == "ancient_abyssal_nautilus_shrine.glb":
			yaw += 0.18
		elif fn == "coastal_smuggler_signal_tripod.glb":
			yaw -= 0.22
		elif fn == "volcanic_obsidian_wyrm_arch.glb":
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


func _layout_sovereign_craft_gallery() -> void:
	# Stage Wave I-22 pirate cooperage barrel workshop, ancient astral tide obelisk, coastal buccaneer net-mending pier & volcanic obsidian leviathan spire on the sunlit sandbar.
	var items: Array[Dictionary] = []
	var total_span := 0.0
	var gap := 4.6
	for i in SOVEREIGN_CRAFT_GLBS.size():
		var fn := SOVEREIGN_CRAFT_GLBS[i]
		var inst := _spawn_landmark(fn, _gallery_root, "SovereignCraft_%02d" % i, Transform3D.IDENTITY, null, true)
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
		if fn == "pirate_cooperage_barrel_workshop.glb":
			cz += 1.4
		elif fn == "coastal_buccaneer_net_mending_pier.glb":
			cz += 1.6
		elif fn == "volcanic_obsidian_leviathan_spire.glb":
			cz += 0.8
		var ground_y := _sandbar_y(cx, cz) - 0.12
		var yaw := PI - t_norm * 0.24
		if fn == "pirate_cooperage_barrel_workshop.glb":
			yaw += 0.28
		elif fn == "ancient_astral_tide_obelisk.glb":
			yaw += 0.18
		elif fn == "coastal_buccaneer_net_mending_pier.glb":
			yaw -= 0.22
		elif fn == "volcanic_obsidian_leviathan_spire.glb":
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


func _layout_privateer_craft_gallery() -> void:
	# Stage Wave I-21 pirate sailmaker rigging loft, ancient serpent tide portal, coastal castaway raft shelter & volcanic obsidian phoenix brazier on the sunlit sandbar.
	var items: Array[Dictionary] = []
	var total_span := 0.0
	var gap := 4.6
	for i in PRIVATEER_CRAFT_GLBS.size():
		var fn := PRIVATEER_CRAFT_GLBS[i]
		var inst := _spawn_landmark(fn, _gallery_root, "PrivateerCraft_%02d" % i, Transform3D.IDENTITY, null, true)
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
		if fn == "pirate_sailmaker_rigging_loft.glb":
			cz += 1.4
		elif fn == "coastal_castaway_raft_shelter.glb":
			cz += 1.6
		elif fn == "volcanic_obsidian_phoenix_brazier.glb":
			cz += 0.8
		var ground_y := _sandbar_y(cx, cz) - 0.12
		var yaw := PI - t_norm * 0.24
		if fn == "pirate_sailmaker_rigging_loft.glb":
			yaw += 0.28
		elif fn == "ancient_serpent_tide_portal.glb":
			yaw += 0.18
		elif fn == "coastal_castaway_raft_shelter.glb":
			yaw -= 0.22
		elif fn == "volcanic_obsidian_phoenix_brazier.glb":
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


func _layout_armada_relics_gallery() -> void:
	# Stage Wave I-20 pirate ropewalk cordage loom, ancient tidal compass sanctum, coastal buccaneer careening cradle & volcanic obsidian kraken altar on the sunlit sandbar.
	var items: Array[Dictionary] = []
	var total_span := 0.0
	var gap := 4.6
	for i in ARMADA_RELICS_GLBS.size():
		var fn := ARMADA_RELICS_GLBS[i]
		var inst := _spawn_landmark(fn, _gallery_root, "ArmadaRelics_%02d" % i, Transform3D.IDENTITY, null, true)
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
		if fn == "pirate_ropewalk_cordage_loom.glb":
			cz += 1.4
		elif fn == "coastal_buccaneer_careening_cradle.glb":
			cz += 1.6
		elif fn == "volcanic_obsidian_kraken_altar.glb":
			cz += 0.8
		var ground_y := _sandbar_y(cx, cz) - 0.12
		var yaw := PI - t_norm * 0.24
		if fn == "pirate_ropewalk_cordage_loom.glb":
			yaw += 0.28
		elif fn == "ancient_tidal_compass_sanctum.glb":
			yaw += 0.18
		elif fn == "coastal_buccaneer_careening_cradle.glb":
			yaw -= 0.22
		elif fn == "volcanic_obsidian_kraken_altar.glb":
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


func _layout_frontier_craft_gallery() -> void:
	# Stage Wave I-19 pirate powder magazine bunker, ancient coral leviathan altar, coastal boatbuilder slipway winch & volcanic obsidian ember totem on the sunlit sandbar.
	var items: Array[Dictionary] = []
	var total_span := 0.0
	var gap := 4.6
	for i in FRONTIER_CRAFT_GLBS.size():
		var fn := FRONTIER_CRAFT_GLBS[i]
		var inst := _spawn_landmark(fn, _gallery_root, "FrontierCraft_%02d" % i, Transform3D.IDENTITY, null, true)
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
		if fn == "pirate_powder_magazine_bunker.glb":
			cz += 1.4
		elif fn == "coastal_boatbuilder_slipway_winch.glb":
			cz += 1.6
		elif fn == "volcanic_obsidian_ember_totem.glb":
			cz += 0.8
		var ground_y := _sandbar_y(cx, cz) - 0.12
		var yaw := PI - t_norm * 0.24
		if fn == "pirate_powder_magazine_bunker.glb":
			yaw += 0.28
		elif fn == "ancient_coral_leviathan_altar.glb":
			yaw += 0.18
		elif fn == "coastal_boatbuilder_slipway_winch.glb":
			yaw -= 0.22
		elif fn == "volcanic_obsidian_ember_totem.glb":
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


func _layout_haven_relics_gallery() -> void:
	# Stage Wave I-18 pirate harbour clock belltower, ancient celestial moon dial, coastal buccaneer grog stall & volcanic obsidian anchor monolith on the sunlit sandbar.
	var items: Array[Dictionary] = []
	var total_span := 0.0
	var gap := 4.6
	for i in HAVEN_RELICS_GLBS.size():
		var fn := HAVEN_RELICS_GLBS[i]
		var inst := _spawn_landmark(fn, _gallery_root, "HavenRelics_%02d" % i, Transform3D.IDENTITY, null, true)
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
		if fn == "pirate_harbour_clock_belltower.glb":
			cz += 1.4
		elif fn == "coastal_buccaneer_grog_stall.glb":
			cz += 1.6
		elif fn == "volcanic_obsidian_anchor_monolith.glb":
			cz += 0.8
		var ground_y := _sandbar_y(cx, cz) - 0.12
		var yaw := PI - t_norm * 0.24
		if fn == "pirate_harbour_clock_belltower.glb":
			yaw += 0.28
		elif fn == "ancient_celestial_moon_dial.glb":
			yaw += 0.18
		elif fn == "coastal_buccaneer_grog_stall.glb":
			yaw -= 0.22
		elif fn == "volcanic_obsidian_anchor_monolith.glb":
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


func _layout_expedition_craft_gallery() -> void:
	# Stage Wave I-17 pirate chart navigator gazebo, ancient sun serpent archway, coastal shipwreck barricade camp & volcanic obsidian lava gate on the sunlit sandbar.
	var items: Array[Dictionary] = []
	var total_span := 0.0
	var gap := 4.6
	for i in EXPEDITION_CRAFT_GLBS.size():
		var fn := EXPEDITION_CRAFT_GLBS[i]
		var inst := _spawn_landmark(fn, _gallery_root, "ExpeditionCraft_%02d" % i, Transform3D.IDENTITY, null, true)
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
		if fn == "pirate_chart_navigator_gazebo.glb":
			cz += 1.4
		elif fn == "coastal_shipwreck_barricade_camp.glb":
			cz += 1.6
		elif fn == "volcanic_obsidian_lava_gate.glb":
			cz += 0.8
		var ground_y := _sandbar_y(cx, cz) - 0.12
		var yaw := PI - t_norm * 0.24
		if fn == "pirate_chart_navigator_gazebo.glb":
			yaw += 0.28
		elif fn == "ancient_sun_serpent_archway.glb":
			yaw += 0.18
		elif fn == "coastal_shipwreck_barricade_camp.glb":
			yaw -= 0.22
		elif fn == "volcanic_obsidian_lava_gate.glb":
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


func _layout_corsair_relics_gallery() -> void:
	# Stage Wave I-16 pirate bounty gallows post, ancient kraken stone fountain, coastal salted fish drying rack & volcanic obsidian dragon maw on the sunlit sandbar.
	var items: Array[Dictionary] = []
	var total_span := 0.0
	var gap := 4.6
	for i in CORSAIR_RELICS_GLBS.size():
		var fn := CORSAIR_RELICS_GLBS[i]
		var inst := _spawn_landmark(fn, _gallery_root, "CorsairRelics_%02d" % i, Transform3D.IDENTITY, null, true)
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
		if fn == "pirate_bounty_gallows_post.glb":
			cz += 1.4
		elif fn == "coastal_salted_fish_drying_rack.glb":
			cz += 1.6
		elif fn == "volcanic_obsidian_dragon_maw.glb":
			cz += 0.8
		var ground_y := _sandbar_y(cx, cz) - 0.12
		var yaw := PI - t_norm * 0.24
		if fn == "pirate_bounty_gallows_post.glb":
			yaw += 0.28
		elif fn == "ancient_kraken_stone_fountain.glb":
			yaw += 0.18
		elif fn == "coastal_salted_fish_drying_rack.glb":
			yaw -= 0.22
		elif fn == "volcanic_obsidian_dragon_maw.glb":
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


func _layout_sea_lore_gallery() -> void:
	# Stage Wave I-15 pirate shipwright timber rack, ancient tidal obelisk mirror, smuggler rope cargo hoist & volcanic obsidian forge anvil on the sunlit sandbar.
	var items: Array[Dictionary] = []
	var total_span := 0.0
	var gap := 4.6
	for i in SEA_LORE_GLBS.size():
		var fn := SEA_LORE_GLBS[i]
		var inst := _spawn_landmark(fn, _gallery_root, "SeaLore_%02d" % i, Transform3D.IDENTITY, null, true)
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
		if fn == "pirate_shipwright_timber_rack.glb":
			cz += 1.4
		elif fn == "smuggler_rope_cargo_hoist.glb":
			cz += 1.6
		elif fn == "volcanic_obsidian_forge_anvil.glb":
			cz += 0.8
		var ground_y := _sandbar_y(cx, cz) - 0.12
		var yaw := PI - t_norm * 0.24
		if fn == "pirate_shipwright_timber_rack.glb":
			yaw += 0.28
		elif fn == "ancient_tidal_obelisk_mirror.glb":
			yaw += 0.18
		elif fn == "smuggler_rope_cargo_hoist.glb":
			yaw -= 0.22
		elif fn == "volcanic_obsidian_forge_anvil.glb":
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


func _layout_nautical_craft_gallery() -> void:
	# Stage Wave I-14 coastal rope ferry pulley, ancient sunken bell shrine, pirate map planning table tent & volcanic basalt obelisk brazier on the sunlit sandbar.
	var items: Array[Dictionary] = []
	var total_span := 0.0
	var gap := 4.6
	for i in NAUTICAL_CRAFT_GLBS.size():
		var fn := NAUTICAL_CRAFT_GLBS[i]
		var inst := _spawn_landmark(fn, _gallery_root, "NauticalCraft_%02d" % i, Transform3D.IDENTITY, null, true)
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
		if fn == "coastal_rope_ferry_pulley.glb":
			cz += 1.4
		elif fn == "pirate_map_planning_table_tent.glb":
			cz += 1.6
		elif fn == "volcanic_basalt_obelisk_brazier.glb":
			cz += 0.8
		var ground_y := _sandbar_y(cx, cz) - 0.12
		var yaw := PI - t_norm * 0.24
		if fn == "coastal_rope_ferry_pulley.glb":
			yaw += 0.28
		elif fn == "ancient_sunken_bell_shrine.glb":
			yaw += 0.18
		elif fn == "pirate_map_planning_table_tent.glb":
			yaw -= 0.22
		elif fn == "volcanic_basalt_obelisk_brazier.glb":
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


func _layout_island_lore_gallery() -> void:
	# Stage Wave I-13 pirate rum distillery shack, ancient jade serpent totem, coastal driftwood arch camp & volcanic obsidian bridge ruin on the sunlit sandbar.
	var items: Array[Dictionary] = []
	var total_span := 0.0
	var gap := 4.6
	for i in ISLAND_LORE_GLBS.size():
		var fn := ISLAND_LORE_GLBS[i]
		var inst := _spawn_landmark(fn, _gallery_root, "IslandLore_%02d" % i, Transform3D.IDENTITY, null, true)
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
		if fn == "pirate_rum_distillery_shack.glb":
			cz += 1.4
		elif fn == "coastal_driftwood_arch_camp.glb":
			cz += 1.6
		elif fn == "volcanic_obsidian_bridge_ruin.glb":
			cz += 0.8
		var ground_y := _sandbar_y(cx, cz) - 0.12
		var yaw := PI - t_norm * 0.24
		if fn == "pirate_rum_distillery_shack.glb":
			yaw += 0.28
		elif fn == "ancient_jade_serpent_totem.glb":
			yaw += 0.18
		elif fn == "coastal_driftwood_arch_camp.glb":
			yaw -= 0.22
		elif fn == "volcanic_obsidian_bridge_ruin.glb":
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


func _layout_fort_vault_gallery() -> void:
	# Stage Wave I-12 stone well courtyard, ruined sea-fort cannon bastion, pirate treasure vault door & shipwreck crow's-nest mast on the sunlit sandbar.
	var items: Array[Dictionary] = []
	var total_span := 0.0
	var gap := 4.6
	for i in FORT_VAULT_GLBS.size():
		var fn := FORT_VAULT_GLBS[i]
		var inst := _spawn_landmark(fn, _gallery_root, "FortVault_%02d" % i, Transform3D.IDENTITY, null, true)
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
		if fn == "stone_well_courtyard.glb":
			cz += 1.6
		elif fn == "ruined_sea_fort_cannon_bastion.glb":
			cz += 0.8
		elif fn == "wooden_shipwreck_crow_nest_mast.glb":
			cz += 1.2
		var ground_y := _sandbar_y(cx, cz) - 0.12
		var yaw := PI - t_norm * 0.24
		if fn == "stone_well_courtyard.glb":
			yaw += 0.30
		elif fn == "ruined_sea_fort_cannon_bastion.glb":
			yaw += 0.22
		elif fn == "pirate_treasure_vault_door.glb":
			yaw -= 0.16
		elif fn == "wooden_shipwreck_crow_nest_mast.glb":
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


func _layout_story_craft_gallery() -> void:
	# Stage Wave I-11 pirate tavern supply cart, sunken anchor memorial, ancient sun-dial plaza & volcanic obsidian fissure vent on the sunlit sandbar.
	var items: Array[Dictionary] = []
	var total_span := 0.0
	var gap := 4.6
	for i in STORY_CRAFT_GLBS.size():
		var fn := STORY_CRAFT_GLBS[i]
		var inst := _spawn_landmark(fn, _gallery_root, "StoryCraft_%02d" % i, Transform3D.IDENTITY, null, true)
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
		if fn == "pirate_tavern_supply_cart.glb":
			cz += 1.6
		elif fn == "sunken_anchor_memorial.glb":
			cz += 1.0
		elif fn == "volcanic_obsidian_fissure_vent.glb":
			cz += 1.2
		var ground_y := _sandbar_y(cx, cz) - 0.12
		var yaw := PI - t_norm * 0.24
		if fn == "pirate_tavern_supply_cart.glb":
			yaw += 0.34
		elif fn == "sunken_anchor_memorial.glb":
			yaw += 0.22
		elif fn == "ancient_sun_dial_plaza.glb":
			yaw -= 0.18
		elif fn == "volcanic_obsidian_fissure_vent.glb":
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


func _layout_onfoot_craft_gallery() -> void:
	# Stage Wave I-10 wooden trail footbridge, coastal smuggler jetty, ruined obelisk gate & lookout bell frame on the sunlit sandbar.
	var items: Array[Dictionary] = []
	var total_span := 0.0
	var gap := 4.6
	for i in ONFOOT_CRAFT_GLBS.size():
		var fn := ONFOOT_CRAFT_GLBS[i]
		var inst := _spawn_landmark(fn, _gallery_root, "OnFootCraft_%02d" % i, Transform3D.IDENTITY, null, true)
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
		if fn == "wooden_trail_footbridge.glb":
			cz += 1.6
		elif fn == "pirate_lookout_bell_frame.glb":
			cz += 1.4
		var ground_y := _sandbar_y(cx, cz) - 0.12
		var yaw := PI - t_norm * 0.24
		if fn == "wooden_trail_footbridge.glb":
			yaw += 0.32
		elif fn == "coastal_smuggler_jetty.glb":
			yaw += 0.36
		elif fn == "ancient_ruined_obelisk_gate.glb":
			yaw -= 0.16
		elif fn == "pirate_lookout_bell_frame.glb":
			yaw -= 0.24
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
			_has_emerald_waterfall = true
			_emerald_wf_top_world = wf_node.global_position
			var rb_node := wf_node.get_node_or_null(^"WaterfallMistRainbow") as Node3D
			var foam_node := wf_node.get_node_or_null(^"PlungePoolFoam") as Node3D
			if rb_node != null:
				_emerald_wf_pool_world = rb_node.global_position
			elif foam_node != null:
				_emerald_wf_pool_world = foam_node.global_position + Vector3(0.0, 0.6, 0.0)
			else:
				var out_d := -wf_node.global_basis.z
				out_d.y = 0.0
				out_d = out_d.normalized() if out_d.length_squared() > 0.001 else (-es_basis.z)
				_emerald_wf_pool_world = wf_node.global_position + out_d * 16.0 - Vector3(0.0, 26.0, 0.0)
		else:
			_emerald_hero_aim = stair_aim
			_has_emerald_waterfall = false

	if _cutlass != null:
		_has_cutlass_shell = false
		var cc_basis := Basis(Vector3.UP, _island_landing_yaw(_cutlass, 2.77))
		var cc_inv := cc_basis.inverse()
		var cc_details := _cutlass.get_node_or_null(^"IslandDetails") as IslandDetails
		if cc_details != null:
			var obstacle_pts := PackedVector3Array()
			for obs_name: String in ["CoastalDriftwood", "TidalOutcrops"]:
				var obs_mmi := cc_details.get_node_or_null(obs_name) as MultiMeshInstance3D
				if obs_mmi != null and obs_mmi.multimesh != null:
					var mm := obs_mmi.multimesh
					for oi in mm.instance_count:
						var ox := mm.get_instance_transform(oi).origin
						if ox.length_squared() > 0.01:
							obstacle_pts.append(ox)
			var pebbles := cc_details.get_placed_pebble_positions()
			var best_score := INF
			var best_fallback_score := INF
			var best_fallback := Vector3.ZERO
			var has_fallback := false
			var cove_ref := Vector2(0.0, -48.0)
			for p in pebbles:
				var uv := cc_inv * p
				var surf_h := _cutlass.surface_height(p.x, p.z)
				var ny := _cutlass.surface_normal(p.x, p.z).y
				var dist_cove := Vector2(uv.x, uv.z).distance_to(cove_ref)
				var blocked := false
				for ox in obstacle_pts:
					var dx := p.x - ox.x
					var dz := p.z - ox.z
					if dx * dx + dz * dz < 3.4 * 3.4:
						blocked = true
						break
				if surf_h >= 0.24 and not blocked and dist_cove < best_fallback_score:
					best_fallback_score = dist_cove
					best_fallback = Vector3(p.x, surf_h, p.z)
					has_fallback = true
				# Prefer crisp dry/wet-sand transition clusters near the landing cove strictly above lapping waves & clear of driftwood/outcrops.
				if not blocked and uv.z < -30.0 and absf(uv.x) < 34.0 and surf_h >= 0.34 and surf_h <= 1.25 and ny >= 0.90:
					var score := dist_cove + absf(surf_h - 0.56) * 14.0
					if score < best_score:
						best_score = score
						_cutlass_shell_local = Vector3(p.x, surf_h, p.z)
						_has_cutlass_shell = true
			if not _has_cutlass_shell and has_fallback:
				_cutlass_shell_local = best_fallback
				_has_cutlass_shell = true

			var cc_prop_pts := PackedVector3Array()
			var cc_props := _cutlass.get_node_or_null(^"Props")
			if cc_props != null:
				var cc_origin := _cutlass.global_position
				for pch in cc_props.get_children():
					var p3 := pch as Node3D
					if p3 != null:
						var rel_p := p3.global_position - cc_origin
						if rel_p.length_squared() > 1.0:
							cc_prop_pts.append(rel_p)

			# Resolve a sunlit inland TrailSteppingStones corridor on Cutlass Cay directly from MultiMesh transforms.
			_has_cutlass_flagstone = false
			var stone_mmi := cc_details.get_node_or_null(^"TrailSteppingStones") as MultiMeshInstance3D
			if stone_mmi != null and stone_mmi.multimesh != null:
				var smm := stone_mmi.multimesh
				var stone_entries: Array[Dictionary] = []
				for si in smm.instance_count:
					var sxf := smm.get_instance_transform(si)
					var sp := sxf.origin
					if sp.length_squared() < 0.01:
						continue
					var sy := clampf(sxf.basis.y.length(), 0.55, 2.50)
					stone_entries.append({
						"pos": sp,
						"sy": sy,
						"is_curb": sy >= 1.28,
					})
				var hib_pts := PackedVector3Array()
				var hib_mmi := cc_details.get_node_or_null(^"HibiscusShrubs") as MultiMeshInstance3D
				if hib_mmi != null and hib_mmi.multimesh != null:
					var hmm := hib_mmi.multimesh
					for hi in hmm.instance_count:
						var hp := hmm.get_instance_transform(hi).origin
						if hp.length_squared() > 0.01:
							hib_pts.append(hp)
				var gr_pts := PackedVector3Array()
				var gr_mmi := cc_details.get_node_or_null(^"GrassClumps") as MultiMeshInstance3D
				if gr_mmi != null and gr_mmi.multimesh != null:
					var gmm := gr_mmi.multimesh
					for gi in gmm.instance_count:
						var gp := gmm.get_instance_transform(gi).origin
						if gp.length_squared() > 0.01:
							gr_pts.append(gp)
				var sun_ang_f := (13.8 - 6.0) / 24.0 * TAU
				var sun_h_f := Vector3(cos(sun_ang_f), 0.0, 0.35).normalized()
				var best_f_score := -INF
				var best_f_fb_score := -INF
				var fb_f_local := Vector3.ZERO
				var fb_f_look := cc_basis.z
				var fb_f_sy := 0.85
				var has_f_fb := false
				for si in stone_entries.size():
					var se: Dictionary = stone_entries[si]
					if bool(se["is_curb"]):
						continue
					var sp: Vector3 = se["pos"]
					var surf_h := _cutlass.surface_height(sp.x, sp.z)
					if surf_h < 2.0 or surf_h > 9.0:
						continue
					var surf_ny := _cutlass.surface_normal(sp.x, sp.z).y
					if surf_ny < 0.88:
						continue
					var sy := float(se["sy"])
					for sj in stone_entries.size():
						if si == sj:
							continue
						var oe: Dictionary = stone_entries[sj]
						if bool(oe["is_curb"]):
							continue
						var op: Vector3 = oe["pos"]
						var dvec := Vector3(op.x - sp.x, 0.0, op.z - sp.z)
						var dist_pair := dvec.length()
						if dist_pair < 1.2 or dist_pair > 5.2:
							continue
						var look_dir := dvec / dist_pair
						var cam_dir := -look_dir
						var cor_path := 0
						var cor_curb := 0
						for sk in stone_entries.size():
							if sk == si:
								continue
							var qe: Dictionary = stone_entries[sk]
							var qp: Vector3 = qe["pos"]
							var qv := Vector3(qp.x - sp.x, 0.0, qp.z - sp.z)
							var along := qv.dot(look_dir)
							var lat := absf(qv.cross(look_dir).y)
							if along > 0.8 and along < 15.0 and lat < 2.8:
								if bool(qe["is_curb"]):
									cor_curb += 1
								else:
									cor_path += 1
						var hib_c := 0
						for hp in hib_pts:
							var qv := Vector3(hp.x - sp.x, 0.0, hp.z - sp.z)
							var al := qv.dot(look_dir)
							var lt := absf(qv.cross(look_dir).y)
							if al > -0.5 and al < 10.0 and lt > 0.6 and lt < 5.0:
								hib_c += 1
						var gr_c := 0
						for gp in gr_pts:
							var qv := Vector3(gp.x - sp.x, 0.0, gp.z - sp.z)
							var al := qv.dot(look_dir)
							var lt := absf(qv.cross(look_dir).y)
							if al > -0.5 and al < 10.0 and lt > 0.5 and lt < 5.0:
								gr_c += 1
						var close_bonus := 1.6 if dist_pair <= 2.8 else 0.0
						var f_score := float(cor_path) * 2.4 + float(cor_curb) * 1.1 \
								+ float(mini(hib_c, 3)) * 1.8 + float(mini(gr_c, 12)) * 0.28 \
								+ cam_dir.dot(sun_h_f) * 2.2 + surf_ny * 1.5 + close_bonus \
								- absf(surf_h - 3.8) * 0.25
						if f_score > best_f_fb_score:
							best_f_fb_score = f_score
							fb_f_local = sp
							fb_f_look = look_dir
							fb_f_sy = sy
							has_f_fb = true
						var eye_test := sp + cam_dir * 2.10
						var f_blocked := false
						for pr in cc_prop_pts:
							if Vector2(pr.x - eye_test.x, pr.z - eye_test.z).length_squared() < 2.5 * 2.5:
								f_blocked = true
								break
							var qv := Vector3(pr.x - sp.x, 0.0, pr.z - sp.z)
							var al := qv.dot(look_dir)
							var lt := absf(qv.cross(look_dir).y)
							if al > -2.5 and al < 7.0 and lt < 1.8:
								f_blocked = true
								break
						if not f_blocked and cor_path >= 2 and f_score > best_f_score:
							best_f_score = f_score
							_cutlass_flagstone_local = sp
							_cutlass_flagstone_look_dir = look_dir
							_cutlass_flagstone_scale_y = sy
							_has_cutlass_flagstone = true
				if not _has_cutlass_flagstone and has_f_fb:
					_cutlass_flagstone_local = fb_f_local
					_cutlass_flagstone_look_dir = fb_f_look
					_cutlass_flagstone_scale_y = fb_f_sy
					_has_cutlass_flagstone = true

			# Resolve a sunlit sandy beach ShoreCrabs specimen on Cutlass Cay directly from MultiMesh transforms.
			_cutlass_crab_idx = -1
			_has_cutlass_crab = false
			var crab_mmi := cc_details.get_node_or_null(^"ShoreCrabs") as MultiMeshInstance3D
			if crab_mmi != null and crab_mmi.multimesh != null:
				var cmm := crab_mmi.multimesh
				var sun_ang_c := (13.8 - 6.0) / 24.0 * TAU
				var sun_h_c := Vector3(cos(sun_ang_c), 0.0, 0.35).normalized()
				var best_c_score := -INF
				var best_c_fb_score := -INF
				var fb_c_idx := -1
				var fb_c_local := Vector3.ZERO
				var fb_c_cam_dir := cc_basis.z
				var has_c_fb := false
				for ci in cmm.instance_count:
					var cxf := cmm.get_instance_transform(ci)
					var cp := cxf.origin
					if cp.length_squared() < 0.01:
						continue
					var surf_h := _cutlass.surface_height(cp.x, cp.z)
					if surf_h < 0.22 or surf_h > 1.35:
						continue
					var surf_n := _cutlass.surface_normal(cp.x, cp.z)
					if surf_n.y < 0.88:
						continue
					var uphill := Vector3(-surf_n.x, 0.0, -surf_n.z)
					if uphill.length_squared() < 0.0004:
						uphill = Vector3(-cp.x, 0.0, -cp.z)
					uphill = uphill.normalized() if uphill.length_squared() > 0.0004 else cc_basis.z
					var face_dir := Vector3(-cxf.basis.z.x, 0.0, -cxf.basis.z.z)
					if face_dir.length_squared() < 0.0004:
						continue
					face_dir = face_dir.normalized()
					var right_f := face_dir.cross(Vector3.UP).normalized()
					var side_sgn := 1.0 if right_f.dot(sun_h_c * 0.60 + uphill * 0.40) >= 0.0 else -1.0
					var front34 := (face_dir * 0.84 + right_f * (0.54 * side_sgn)).normalized()
					var cam_raw := front34 * 0.76 + uphill * 0.16 + sun_h_c * 0.14
					var cam_dir := cam_raw.normalized() if cam_raw.length_squared() > 0.0004 else front34
					if cam_dir.dot(face_dir) < 0.52:
						cam_dir = front34
					var c_col := cmm.get_instance_color(ci)
					var coral_pop := clampf(c_col.r - c_col.g, 0.0, 1.0)
					var sc_y := clampf(cxf.basis.y.length(), 0.70, 1.30)
					var eye_test := cp + cam_dir * 0.95
					var eye_ground := _cutlass.surface_height(eye_test.x, eye_test.z)
					var bg3 := _cutlass.surface_height(cp.x - cam_dir.x * 3.5, cp.z - cam_dir.z * 3.5)
					var bg7 := _cutlass.surface_height(cp.x - cam_dir.x * 7.5, cp.z - cam_dir.z * 7.5)
					var bg14 := _cutlass.surface_height(cp.x - cam_dir.x * 14.0, cp.z - cam_dir.z * 14.0)
					var c_score := coral_pop * 6.5 + face_dir.dot(uphill) * 4.5 + cam_dir.dot(sun_h_c) * 2.8 \
							+ cam_dir.dot(uphill) * 3.6 + surf_n.y * 1.8 \
							+ (3.0 if bg3 < 0.05 else 0.0) + (3.2 if bg7 < -0.20 else 0.0) \
							+ (1.8 if bg14 < -0.60 else 0.0) + (1.2 if eye_ground >= 0.20 else -2.5) \
							+ sc_y * 2.2 - absf(surf_h - 0.38) * 2.8
					if c_score > best_c_fb_score:
						best_c_fb_score = c_score
						fb_c_idx = ci
						fb_c_local = cp
						fb_c_cam_dir = cam_dir
						has_c_fb = true
					var c_blocked := false
					var view_dir := -cam_dir
					for ox in obstacle_pts:
						if Vector2(cp.x - ox.x, cp.z - ox.z).length_squared() < 2.2 * 2.2 \
								or Vector2(eye_test.x - ox.x, eye_test.z - ox.z).length_squared() < 2.0 * 2.0:
							c_blocked = true
							break
						var qv := Vector3(ox.x - cp.x, 0.0, ox.z - cp.z)
						var al := qv.dot(view_dir)
						var lt := absf(qv.cross(view_dir).y)
						if al > -1.2 and al < 4.5 and lt < 1.4:
							c_blocked = true
							break
					if not c_blocked:
						for pr in cc_prop_pts:
							if Vector2(cp.x - pr.x, cp.z - pr.z).length_squared() < 4.0 * 4.0 \
									or Vector2(eye_test.x - pr.x, eye_test.z - pr.z).length_squared() < 3.5 * 3.5:
								c_blocked = true
								break
					if not c_blocked and c_score > best_c_score:
						best_c_score = c_score
						_cutlass_crab_idx = ci
						_cutlass_crab_local = cp
						_cutlass_crab_cam_dir = cam_dir
						_has_cutlass_crab = true
				if not _has_cutlass_crab and has_c_fb:
					_cutlass_crab_idx = fb_c_idx
					_cutlass_crab_local = fb_c_local
					_cutlass_crab_cam_dir = fb_c_cam_dir
					_has_cutlass_crab = true

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
		_has_gulls_tidepool = false
		var ga_details := _gulls_arch.get_node_or_null(^"IslandDetails") as IslandDetails
		if ga_details != null:
			var tidal_mmi := ga_details.get_node_or_null(^"TidalOutcrops") as MultiMeshInstance3D
			if tidal_mmi != null and tidal_mmi.multimesh != null:
				var mm := tidal_mmi.multimesh
				var tidal_pts := PackedVector3Array()
				for ti in mm.instance_count:
					var tp := mm.get_instance_transform(ti).origin
					if tp.length_squared() > 0.01:
						tidal_pts.append(tp)
				var dw_pts := PackedVector3Array()
				var dw_mmi := ga_details.get_node_or_null(^"CoastalDriftwood") as MultiMeshInstance3D
				if dw_mmi != null and dw_mmi.multimesh != null:
					var dmm := dw_mmi.multimesh
					for di in dmm.instance_count:
						var dp := dmm.get_instance_transform(di).origin
						if dp.length_squared() > 0.01:
							dw_pts.append(dp)
				var sun_ang := (13.6 - 6.0) / 24.0 * TAU
				var sun_h := Vector3(cos(sun_ang), 0.0, 0.35).normalized()
				var best_score := -INF
				var best_fb_score := -INF
				var fb_local := Vector3.ZERO
				var fb_cam_dir := ga_basis.z
				var fb_scale_y := 1.0
				var has_fb := false
				for ti in mm.instance_count:
					var xf := mm.get_instance_transform(ti)
					var p := xf.origin
					if p.length_squared() < 0.01:
						continue
					var surf_h := _gulls_arch.surface_height(p.x, p.z)
					if surf_h < -0.15 or surf_h > 0.95:
						continue
					var ny := _gulls_arch.surface_normal(p.x, p.z).y
					var inland := Vector3(-p.x, 0.0, -p.z)
					inland = inland.normalized() if inland.length_squared() > 0.01 else ga_basis.z
					var hero_dir := xf.basis * Vector3(-0.12, 0.0, 1.0)
					hero_dir.y = 0.0
					hero_dir = hero_dir.normalized() if hero_dir.length_squared() > 0.001 else inland
					var cam_raw := hero_dir * 0.65 + inland * 0.45 + sun_h * 0.25
					var cam_dir := cam_raw.normalized() if cam_raw.length_squared() > 0.001 else inland
					var sc_y := clampf(xf.basis.y.length(), 0.70, 1.80)
					var detail_y := p.y + 0.27 * sc_y
					var bg_pt := p - cam_dir * 10.0
					var bg_h := _gulls_arch.surface_height(bg_pt.x, bg_pt.z)
					var score := hero_dir.dot(sun_h) * 3.0 + hero_dir.dot(inland) * 2.6 \
							+ clampf(detail_y, 0.0, 1.0) * 1.4 - absf(surf_h - 0.52) * 1.8 \
							+ (1.2 if bg_h < 0.0 else 0.0)
					if score > best_fb_score:
						best_fb_score = score
						fb_local = p
						fb_cam_dir = cam_dir
						fb_scale_y = sc_y
						has_fb = true
					if ny < 0.85:
						continue
					var eye_test := p + cam_dir * 2.4
					var blocked := false
					for op in tidal_pts:
						if op.distance_squared_to(p) < 0.04:
							continue
						var odx := eye_test.x - op.x
						var odz := eye_test.z - op.z
						if odx * odx + odz * odz < 1.8 * 1.8:
							blocked = true
							break
					if not blocked:
						for dp in dw_pts:
							var ddx := p.x - dp.x
							var ddz := p.z - dp.z
							if ddx * ddx + ddz * ddz < 2.2 * 2.2:
								blocked = true
								break
					if not blocked and score > best_score:
						best_score = score
						_gulls_tidepool_local = p
						_gulls_tidepool_cam_dir = cam_dir
						_gulls_tidepool_scale_y = sc_y
						_has_gulls_tidepool = true
				if not _has_gulls_tidepool and has_fb:
					_gulls_tidepool_local = fb_local
					_gulls_tidepool_cam_dir = fb_cam_dir
					_gulls_tidepool_scale_y = fb_scale_y
					_has_gulls_tidepool = true

	if _sovereigns_bastion != null:
		var sv_basis := Basis(Vector3.UP, _island_landing_yaw(_sovereigns_bastion, 1.72))
		var sv_fallback := _sovereigns_bastion.global_position + sv_basis * Vector3(0.0, 26.0, 18.0)
		var bastion_aim := _find_native_landmark_aim(_sovereigns_bastion, "FortBastion*", sv_fallback)
		var wf_node := _sovereigns_bastion.find_child("CitadelWaterfall*", true, false) as Node3D
		if wf_node != null:
			var wf_aim := wf_node.global_position - Vector3(0.0, 8.0, 0.0)
			_sovereigns_hero_aim = bastion_aim.lerp(wf_aim, 0.18)
			_has_sovereigns_waterfall = true
			_sovereigns_wf_top_world = wf_node.global_position
			var out_d := -wf_node.global_basis.z
			out_d.y = 0.0
			_sovereigns_wf_out_dir = out_d.normalized() if out_d.length_squared() > 0.001 else (-sv_basis.z)
			var foam_node := wf_node.get_node_or_null(^"PlungePoolFoam") as Node3D
			var rb_node := wf_node.get_node_or_null(^"WaterfallMistRainbow") as Node3D
			if foam_node != null:
				_sovereigns_wf_pool_world = foam_node.global_position
			elif rb_node != null:
				_sovereigns_wf_pool_world = rb_node.global_position
			else:
				_sovereigns_wf_pool_world = wf_node.global_position + _sovereigns_wf_out_dir * 18.0 - Vector3(0.0, 25.0, 0.0)
		else:
			_sovereigns_hero_aim = bastion_aim
			_has_sovereigns_waterfall = false
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
		_has_crescent_driftwood = false
		var ca_details := _crescent_atoll.get_node_or_null(^"IslandDetails") as IslandDetails
		if ca_details != null:
			var dw_mmi := ca_details.get_node_or_null(^"CoastalDriftwood") as MultiMeshInstance3D
			if dw_mmi != null and dw_mmi.multimesh != null:
				var dmm := dw_mmi.multimesh
				var dw_pts := PackedVector3Array()
				for di in dmm.instance_count:
					var dp := dmm.get_instance_transform(di).origin
					if dp.length_squared() > 0.01:
						dw_pts.append(dp)
				var td_pts := PackedVector3Array()
				var td_mmi := ca_details.get_node_or_null(^"TidalOutcrops") as MultiMeshInstance3D
				if td_mmi != null and td_mmi.multimesh != null:
					var tmm := td_mmi.multimesh
					for ti in tmm.instance_count:
						var tp := tmm.get_instance_transform(ti).origin
						if tp.length_squared() > 0.01:
							td_pts.append(tp)
				var prop_pts := PackedVector3Array()
				var ca_props := _crescent_atoll.get_node_or_null(^"Props")
				if ca_props != null:
					for p_child in ca_props.get_children():
						var p3 := p_child as Node3D
						if p3 != null:
							var rel_p := p3.global_position - ca_pos
							if rel_p.length_squared() > 1.0:
								prop_pts.append(rel_p)
				var sun_ang := (13.8 - 6.0) / 24.0 * TAU
				var sun_h := Vector3(cos(sun_ang), 0.0, 0.35).normalized()
				var best_score := -INF
				var best_fb_score := -INF
				var fb_local := Vector3.ZERO
				var fb_cam_dir := ca_basis.z
				var fb_scale_y := 1.0
				var has_fb := false
				for di in dmm.instance_count:
					var xf := dmm.get_instance_transform(di)
					var p := xf.origin
					if p.length_squared() < 0.01:
						continue
					var surf_h := _crescent_atoll.surface_height(p.x, p.z)
					if surf_h < 0.25 or surf_h > 1.25:
						continue
					var surf_n := _crescent_atoll.surface_normal(p.x, p.z)
					if surf_n.y < 0.88:
						continue
					var uphill := Vector3(-surf_n.x, 0.0, -surf_n.z)
					if uphill.length_squared() < 0.0004:
						uphill = Vector3(p.x, 0.0, p.z)
					uphill = uphill.normalized() if uphill.length_squared() > 0.0004 else ca_basis.z
					var z_axis := Vector3(xf.basis.z.x, 0.0, xf.basis.z.z)
					if z_axis.length_squared() < 0.001:
						continue
					z_axis = z_axis.normalized()
					# Broadside inland flank (+Z or -Z) so the camera stands upslope looking seaward across the log.
					var cam_dir := z_axis if z_axis.dot(uphill) >= 0.0 else -z_axis
					var hero_pos_z := cam_dir.dot(z_axis) > 0.0
					var sc_x := clampf(xf.basis.x.length(), 0.65, 1.50)
					var sc_y := clampf(xf.basis.y.length(), 0.65, 1.50)
					var bg8 := _crescent_atoll.surface_height(p.x - cam_dir.x * 8.0, p.z - cam_dir.z * 8.0)
					var bg18 := _crescent_atoll.surface_height(p.x - cam_dir.x * 18.0, p.z - cam_dir.z * 18.0)
					var score := cam_dir.dot(sun_h) * 3.2 + (1.6 if hero_pos_z else 0.0) \
							+ surf_n.y * 2.0 + (1.4 if bg8 < -0.15 else 0.0) + (1.4 if bg18 < -0.8 else 0.0) \
							- absf(surf_h - 0.45) * 1.4 - absf(sc_x - 0.90) * 1.8
					if score > best_fb_score:
						best_fb_score = score
						fb_local = p
						fb_cam_dir = cam_dir
						fb_scale_y = sc_y
						has_fb = true
					var eye_test := p + cam_dir * 2.15
					var blocked := false
					for tp in td_pts:
						if Vector2(p.x - tp.x, p.z - tp.z).length_squared() < 2.6 * 2.6 \
								or Vector2(eye_test.x - tp.x, eye_test.z - tp.z).length_squared() < 2.4 * 2.4:
							blocked = true
							break
					if not blocked:
						for op in dw_pts:
							if op.distance_squared_to(p) < 0.04:
								continue
							if Vector2(eye_test.x - op.x, eye_test.z - op.z).length_squared() < 2.2 * 2.2:
								blocked = true
								break
					if not blocked:
						for lp in prop_pts:
							if Vector2(p.x - lp.x, p.z - lp.z).length_squared() < 4.5 * 4.5 \
									or Vector2(eye_test.x - lp.x, eye_test.z - lp.z).length_squared() < 4.0 * 4.0:
								blocked = true
								break
					if not blocked and score > best_score:
						best_score = score
						_crescent_driftwood_local = p
						_crescent_driftwood_cam_dir = cam_dir
						_crescent_driftwood_scale_y = sc_y
						_has_crescent_driftwood = true
				if not _has_crescent_driftwood and has_fb:
					_crescent_driftwood_local = fb_local
					_crescent_driftwood_cam_dir = fb_cam_dir
					_crescent_driftwood_scale_y = fb_scale_y
					_has_crescent_driftwood = true

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
		"gallery_geology", "gallery_setpieces", "gallery_storytelling", "gallery_skyline", "gallery_coastal", "gallery_harbour_ruins", "gallery_maritime_relics", "gallery_world_craft", "gallery_onfoot_craft", "gallery_story_craft", "gallery_fort_vault", "gallery_island_lore", "gallery_nautical_craft", "gallery_sea_lore", "gallery_corsair_relics", "gallery_expedition_craft", "gallery_haven_relics", "gallery_frontier_craft", "gallery_armada_relics", "gallery_privateer_craft", "gallery_sovereign_craft", "gallery_buccaneer_craft":
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

		"onfoot_cutlass_trail", "onfoot_cutlass_dusk":
			if _cutlass == null:
				return
			var cc_pos := _cutlass.global_position
			var cc_basis := Basis(Vector3.UP, _island_landing_yaw(_cutlass, 2.77))
			var walk := clampf(_clock * 0.14, 0.0, 1.0)
			var pan := sin(_clock * 0.42) * 1.4
			var eye_local := cc_basis * Vector3(2.0 + pan * 0.25, 0.0, lerpf(-40.0, -35.5, walk))
			var ground_y := _cutlass.surface_height(eye_local.x, eye_local.z)
			var eye_h := maxf(ground_y, 0.6) + 2.2
			var eye := cc_pos + Vector3(eye_local.x, eye_h, eye_local.z)
			var aim_local := cc_basis * Vector3(-3.5 + pan, 0.0, lerpf(-12.0, -6.0, walk))
			var aim_ground := _cutlass.surface_height(aim_local.x, aim_local.z)
			var aim_h := clampf(aim_ground + 1.8, eye_h + 2.2, eye_h + 5.5)
			var aim := cc_pos + Vector3(aim_local.x, aim_h, aim_local.z)
			_cam.fov = 62.0
			_cam.look_at_from_position(eye, aim)

		"onfoot_port_harbour", "onfoot_port_dusk":
			if _port_scoundrel == null:
				return
			var ps_pos := _port_scoundrel.global_position
			var ps_basis := Basis(Vector3.UP, _island_landing_yaw(_port_scoundrel, -0.37))
			var walk := clampf(_clock * 0.14, 0.0, 1.0)
			var pan := sin(_clock * 0.40) * 1.6
			var eye_v := lerpf(-28.0, -23.5, walk)
			var eye_local := ps_basis * Vector3(pan * 0.20, 0.0, eye_v)
			var dock_deck_y := lerpf(1.35, 0.34, clampf((eye_v + 28.0) / 2.25, 0.0, 1.0))
			var floor_y := maxf(_port_scoundrel.surface_height(eye_local.x, eye_local.z), dock_deck_y)
			var eye_h := floor_y + 2.4
			var eye := ps_pos + Vector3(eye_local.x, eye_h, eye_local.z)
			var aim_local := ps_basis * Vector3(-1.8 + pan, 0.0, lerpf(4.0, 10.0, walk))
			var aim_ground := _port_scoundrel.surface_height(aim_local.x, aim_local.z)
			var aim_h := clampf(aim_ground + 2.0, eye_h + 1.8, eye_h + 4.8)
			var aim := ps_pos + Vector3(aim_local.x, aim_h, aim_local.z)
			_cam.fov = 64.0
			_cam.look_at_from_position(eye, aim)

		"onfoot_emerald_canyon", "onfoot_emerald_dusk":
			if _emerald_spire == null:
				return
			var es_pos := _emerald_spire.global_position
			var es_basis := Basis(Vector3.UP, _island_landing_yaw(_emerald_spire, -1.42))
			var walk := clampf(_clock * 0.14, 0.0, 1.0)
			var pan := sin(_clock * 0.40) * 1.2
			var eye_local := es_basis * Vector3(lerpf(5.0, 5.6, walk) + pan * 0.20, 0.0, lerpf(-114.5, -110.0, walk))
			var ground_y := _emerald_spire.surface_height(eye_local.x, eye_local.z)
			var eye_h := maxf(ground_y, 0.6) + 2.2
			var eye := es_pos + Vector3(eye_local.x, eye_h, eye_local.z)
			var aim_local := es_basis * Vector3(lerpf(1.5, 1.2, walk) + pan, 0.0, lerpf(-20.0, -14.0, walk))
			var aim_ground := _emerald_spire.surface_height(aim_local.x, aim_local.z)
			var aim_h := clampf(aim_ground + 2.0, eye_h + 2.5, eye_h + 8.0)
			var aim := es_pos + Vector3(aim_local.x, aim_h, aim_local.z)
			_cam.fov = 62.0
			_cam.look_at_from_position(eye, aim)

		"onfoot_smugglers_cove", "onfoot_smugglers_dusk":
			if _smugglers_cove == null:
				return
			var sc_pos := _smugglers_cove.global_position
			var sc_basis := Basis(Vector3.UP, _island_landing_yaw(_smugglers_cove, 1.35))
			var walk := clampf(_clock * 0.14, 0.0, 1.0)
			var pan := sin(_clock * 0.38) * 1.2
			var eye_local := sc_basis * Vector3(lerpf(-13.6, -13.0, walk) + pan * 0.18, 0.0, lerpf(-45.2, -43.2, walk))
			var ground_y := _smugglers_cove.surface_height(eye_local.x, eye_local.z)
			var eye_h := maxf(ground_y, 0.6) + 2.2
			var eye := sc_pos + Vector3(eye_local.x, eye_h, eye_local.z)
			var aim_local := sc_basis * Vector3(lerpf(4.5, 4.0, walk) + pan, 0.0, lerpf(-16.0, -12.0, walk))
			var aim_ground := _smugglers_cove.surface_height(aim_local.x, aim_local.z)
			var aim_h := clampf(aim_ground + 2.8, eye_h + 1.8, eye_h + 6.2)
			var aim := sc_pos + Vector3(aim_local.x, aim_h, aim_local.z)
			_cam.fov = 64.0
			_cam.look_at_from_position(eye, aim)

		"onfoot_crescent_lagoon", "onfoot_crescent_dusk":
			if _crescent_atoll == null:
				return
			var ca_pos := _crescent_atoll.global_position
			var ca_basis := Basis(Vector3.UP, _island_landing_yaw(_crescent_atoll, 0.72))
			var walk := clampf(_clock * 0.14, 0.0, 1.0)
			var pan := sin(_clock * 0.38) * 1.4
			var eye_local := ca_basis * Vector3(lerpf(-44.8, -42.5, walk) + pan * 0.20, 0.0, lerpf(-102.5, -96.5, walk))
			var ground_y := _crescent_atoll.surface_height(eye_local.x, eye_local.z)
			var eye_h := maxf(ground_y, 0.6) + 2.2
			var eye := ca_pos + Vector3(eye_local.x, eye_h, eye_local.z)
			var aim_local := ca_basis * Vector3(lerpf(12.5, 15.5, walk) + pan, 0.0, lerpf(-70.0, -65.0, walk))
			var aim_ground := _crescent_atoll.surface_height(aim_local.x, aim_local.z)
			var aim_h := clampf(aim_ground + 1.8, eye_h - 1.6, eye_h + 2.5)
			var aim := ca_pos + Vector3(aim_local.x, aim_h, aim_local.z)
			_cam.fov = 64.0
			_cam.look_at_from_position(eye, aim)

		"onfoot_cinder_caldera", "onfoot_cinder_dusk":
			if _cinder_crag == null:
				return
			var cr_pos := _cinder_crag.global_position
			var cr_basis := Basis(Vector3.UP, _island_landing_yaw(_cinder_crag, 2.90))
			var walk := clampf(_clock * 0.14, 0.0, 1.0)
			var pan := sin(_clock * 0.36) * 1.4
			var eye_local := cr_basis * Vector3(lerpf(-1.6, -2.8, walk) + pan * 0.20, 0.0, lerpf(-158.0, -151.0, walk))
			var ground_y := _cinder_crag.surface_height(eye_local.x, eye_local.z)
			var eye_h := maxf(ground_y, 0.6) + 2.2
			var eye := cr_pos + Vector3(eye_local.x, eye_h, eye_local.z)
			var aim_local := cr_basis * Vector3(lerpf(-2.0, -2.5, walk) + pan, 0.0, lerpf(-98.0, -92.0, walk))
			var aim_ground := _cinder_crag.surface_height(aim_local.x, aim_local.z)
			var aim_h := clampf(aim_ground + 3.5, eye_h + 3.0, eye_h + 9.5)
			var aim := cr_pos + Vector3(aim_local.x, aim_h, aim_local.z)
			_cam.fov = 66.0
			_cam.look_at_from_position(eye, aim)

		"onfoot_skull_bluff", "onfoot_skull_dusk":
			if _skull_bluff == null:
				return
			var sb_pos := _skull_bluff.global_position
			var sb_basis := Basis(Vector3.UP, _island_landing_yaw(_skull_bluff, 2.35))
			var walk := clampf(_clock * 0.14, 0.0, 1.0)
			var pan := sin(_clock * 0.38) * 1.2
			var eye_local := sb_basis * Vector3(lerpf(-1.2, -2.0, walk) + pan * 0.18, 0.0, lerpf(-116.5, -111.5, walk))
			var ground_y := _skull_bluff.surface_height(eye_local.x, eye_local.z)
			var eye_h := maxf(ground_y, 0.6) + 2.2
			var eye := sb_pos + Vector3(eye_local.x, eye_h, eye_local.z)
			var aim_local := sb_basis * Vector3(lerpf(-4.2, -3.8, walk) + pan, 0.0, lerpf(-38.0, -34.0, walk))
			var aim_ground := _skull_bluff.surface_height(aim_local.x, aim_local.z)
			var aim_h := clampf(aim_ground + 4.5, eye_h + 7.5, eye_h + 13.5)
			var aim := sb_pos + Vector3(aim_local.x, aim_h, aim_local.z)
			_cam.fov = 66.0
			_cam.look_at_from_position(eye, aim)

		"onfoot_galleons_reach", "onfoot_galleons_dusk":
			if _galleons_reach == null:
				return
			var gr_pos := _galleons_reach.global_position
			var gr_basis := Basis(Vector3.UP, _island_landing_yaw(_galleons_reach, 0.12))
			var walk := clampf(_clock * 0.14, 0.0, 1.0)
			var pan := sin(_clock * 0.38) * 1.2
			var eye_local := gr_basis * Vector3(lerpf(56.2, 54.6, walk) + pan * 0.18, 0.0, lerpf(-83.0, -79.2, walk))
			var ground_y := _galleons_reach.surface_height(eye_local.x, eye_local.z)
			var eye_h := maxf(ground_y, 0.6) + 2.2
			var eye := gr_pos + Vector3(eye_local.x, eye_h, eye_local.z)
			var aim_local := gr_basis * Vector3(lerpf(-4.0, -3.0, walk) + pan, 0.0, lerpf(-24.0, -20.0, walk))
			var aim_ground := _galleons_reach.surface_height(aim_local.x, aim_local.z)
			var aim_h := clampf(aim_ground + 5.0, eye_h + 4.5, eye_h + 11.5)
			var aim := gr_pos + Vector3(aim_local.x, aim_h, aim_local.z)
			_cam.fov = 66.0
			_cam.look_at_from_position(eye, aim)

		"onfoot_sovereigns_bastion", "onfoot_sovereigns_dusk":
			if _sovereigns_bastion == null:
				return
			var sv_pos := _sovereigns_bastion.global_position
			var sv_basis := Basis(Vector3.UP, _island_landing_yaw(_sovereigns_bastion, 1.72))
			var walk := clampf(_clock * 0.14, 0.0, 1.0)
			var pan := sin(_clock * 0.36) * 1.2
			var eye_local := sv_basis * Vector3(lerpf(0.0, -0.3, walk) + pan * 0.18, 0.0, lerpf(-111.5, -106.0, walk))
			var ground_y := _sovereigns_bastion.surface_height(eye_local.x, eye_local.z)
			var eye_h := maxf(ground_y, 0.6) + 2.2
			var eye := sv_pos + Vector3(eye_local.x, eye_h, eye_local.z)
			var aim_local := sv_basis * Vector3(pan, 0.0, lerpf(14.0, 20.0, walk))
			var aim_ground := _sovereigns_bastion.surface_height(aim_local.x, aim_local.z)
			var aim_h := clampf(aim_ground + 4.5, eye_h + 9.0, eye_h + 18.0)
			var aim := sv_pos + Vector3(aim_local.x, aim_h, aim_local.z)
			_cam.fov = 66.0
			_cam.look_at_from_position(eye, aim)

		"onfoot_ironwatch_fort", "onfoot_ironwatch_dusk":
			if _ironwatch_fort == null:
				return
			var iw_pos := _ironwatch_fort.global_position
			var iw_basis := Basis(Vector3.UP, _island_landing_yaw(_ironwatch_fort, -2.35))
			var walk := clampf(_clock * 0.14, 0.0, 1.0)
			var pan := sin(_clock * 0.38) * 1.2
			var eye_local := iw_basis * Vector3(lerpf(-1.5, -0.5, walk) + pan * 0.18, 0.0, lerpf(-70.2, -65.2, walk))
			var ground_y := _ironwatch_fort.surface_height(eye_local.x, eye_local.z)
			var eye_h := maxf(ground_y, 0.6) + 2.2
			var eye := iw_pos + Vector3(eye_local.x, eye_h, eye_local.z)
			var aim_local := iw_basis * Vector3(lerpf(5.8, 5.2, walk) + pan, 0.0, lerpf(-2.0, 2.0, walk))
			var aim_ground := _ironwatch_fort.surface_height(aim_local.x, aim_local.z)
			var aim_h := clampf(aim_ground + 4.0, eye_h + 7.5, eye_h + 16.0)
			var aim := iw_pos + Vector3(aim_local.x, aim_h, aim_local.z)
			_cam.fov = 68.0
			_cam.look_at_from_position(eye, aim)

		"onfoot_barnacle_haven", "onfoot_barnacle_dusk":
			if _barnacle_haven == null:
				return
			var bh_pos := _barnacle_haven.global_position
			var bh_basis := Basis(Vector3.UP, _island_landing_yaw(_barnacle_haven, -0.78))
			var walk := clampf(_clock * 0.14, 0.0, 1.0)
			var pan := sin(_clock * 0.38) * 1.2
			var eye_local := bh_basis * Vector3(lerpf(-21.2, -19.8, walk) + pan * 0.16, 0.0, lerpf(-50.5, -48.5, walk))
			var ground_y := _barnacle_haven.surface_height(eye_local.x, eye_local.z)
			var eye_h := maxf(ground_y, 0.6) + 2.2
			var eye := bh_pos + Vector3(eye_local.x, eye_h, eye_local.z)
			var aim_local := bh_basis * Vector3(lerpf(9.5, 10.5, walk) + pan, 0.0, lerpf(-22.5, -21.5, walk))
			var aim_ground := _barnacle_haven.surface_height(aim_local.x, aim_local.z)
			var aim_h := clampf(aim_ground + 4.8, eye_h + 3.2, eye_h + 5.8)
			var aim := bh_pos + Vector3(aim_local.x, aim_h, aim_local.z)
			_cam.fov = 66.0
			_cam.look_at_from_position(eye, aim)

		"onfoot_gulls_arch", "onfoot_gulls_dusk":
			if _gulls_arch == null:
				return
			var ga_pos := _gulls_arch.global_position
			var ga_basis := Basis(Vector3.UP, _island_landing_yaw(_gulls_arch, -2.15))
			var walk := clampf(_clock * 0.14, 0.0, 1.0)
			var pan := sin(_clock * 0.38) * 1.2
			var eye_local := ga_basis * Vector3(lerpf(35.2, 32.5, walk) + pan * 0.18, 0.0, lerpf(-53.8, -50.8, walk))
			var ground_y := _gulls_arch.surface_height(eye_local.x, eye_local.z)
			var eye_h := maxf(ground_y, 0.6) + 2.2
			var eye := ga_pos + Vector3(eye_local.x, eye_h, eye_local.z)
			var aim_local := ga_basis * Vector3(lerpf(-10.0, -11.0, walk) + pan, 0.0, lerpf(-58.0, -57.5, walk))
			var aim_ground := _gulls_arch.surface_height(aim_local.x, aim_local.z)
			var aim_h := clampf(aim_ground + 5.2, eye_h + 1.4, eye_h + 3.4)
			var aim := ga_pos + Vector3(aim_local.x, aim_h, aim_local.z)
			_cam.fov = 66.0
			_cam.look_at_from_position(eye, aim)

		"onfoot_wreckers_shoal", "onfoot_wreckers_dusk":
			if _wreckers_shoal == null:
				return
			var ws_pos := _wreckers_shoal.global_position
			var ws_basis := Basis(Vector3.UP, _island_landing_yaw(_wreckers_shoal, 0.05))
			var walk := clampf(_clock * 0.14, 0.0, 1.0)
			var pan := sin(_clock * 0.38) * 1.2
			var eye_local := ws_basis * Vector3(lerpf(-35.2, -33.6, walk) + pan * 0.16, 0.0, lerpf(-33.0, -31.8, walk))
			var ground_y := _wreckers_shoal.surface_height(eye_local.x, eye_local.z)
			var eye_h := maxf(ground_y, 0.6) + 2.2
			var eye := ws_pos + Vector3(eye_local.x, eye_h, eye_local.z)
			var aim_local := ws_basis * Vector3(lerpf(5.5, 6.2, walk) + pan, 0.0, lerpf(-4.2, -3.8, walk))
			var aim_ground := _wreckers_shoal.surface_height(aim_local.x, aim_local.z)
			var aim_h := clampf(aim_ground + 2.5, eye_h + 5.5, eye_h + 8.0)
			var aim := ws_pos + Vector3(aim_local.x, aim_h, aim_local.z)
			_cam.fov = 68.0
			_cam.look_at_from_position(eye, aim)

		"onfoot_sirens_tooth", "onfoot_sirens_dusk":
			if _sirens_tooth == null:
				return
			var st_pos := _sirens_tooth.global_position
			var st_basis := Basis(Vector3.UP, _island_landing_yaw(_sirens_tooth, -0.62))
			var walk := clampf(_clock * 0.14, 0.0, 1.0)
			var pan := sin(_clock * 0.36) * 1.1
			var eye_local := st_basis * Vector3(lerpf(15.2, 16.2, walk) + pan * 0.16, 0.0, lerpf(-27.2, -25.4, walk))
			var ground_y := _sirens_tooth.surface_height(eye_local.x, eye_local.z)
			var eye_h := maxf(ground_y, 0.6) + 2.2
			var eye := st_pos + Vector3(eye_local.x, eye_h, eye_local.z)
			var aim_local := st_basis * Vector3(lerpf(-4.2, -3.8, walk) + pan, 0.0, lerpf(-4.0, -3.5, walk))
			var aim_ground := _sirens_tooth.surface_height(aim_local.x, aim_local.z)
			var aim_h := clampf(aim_ground + 2.0, eye_h + 8.5, eye_h + 11.5)
			var aim := st_pos + Vector3(aim_local.x, aim_h, aim_local.z)
			_cam.fov = 68.0
			_cam.look_at_from_position(eye, aim)

		"onfoot_emerald_sunset", "onfoot_emerald_moonlit", "onfoot_emerald_storm":
			# Golden-hour sunset (time=17.4), starry moonlit midnight (time=22.8, M48 silver-foam shader),
			# & pouring tropical storm (time=15.0, storm=0.92, M61 storm-flood waterfall runoff + M59 rain puddles)
			# eye-height (2.4 m) canyon floor vista looking straight up Emerald Spire's walkable valley
			# toward the carved palm-free EmeraldCanyonWaterfall (+5.06 m clearance, lip to pool) + fireflies & glowing lanterns!
			if _emerald_spire == null:
				return
			var es_pos := _emerald_spire.global_position
			var es_basis := Basis(Vector3.UP, _island_landing_yaw(_emerald_spire, -1.42))
			var s_r := _emerald_spire.island_radius / 60.0
			var walk := clampf(_clock * 0.14, 0.0, 1.0)
			var pan := sin(_clock * 0.36) * 0.65
			var eye_local := es_basis * Vector3(lerpf(3.3, 3.5, walk) * s_r + pan * 0.16, 0.0, lerpf(5.6, 6.2, walk) * s_r)
			var ground_y := _emerald_spire.surface_height(eye_local.x, eye_local.z)
			ground_y = maxf(ground_y, _emerald_spire.surface_height(eye_local.x + 1.2, eye_local.z))
			ground_y = maxf(ground_y, _emerald_spire.surface_height(eye_local.x - 1.2, eye_local.z))
			ground_y = maxf(ground_y, _emerald_spire.surface_height(eye_local.x, eye_local.z + 1.2))
			ground_y = maxf(ground_y, _emerald_spire.surface_height(eye_local.x, eye_local.z - 1.2))
			var eye_h := maxf(ground_y, 0.6) + 2.4
			var eye := es_pos + Vector3(eye_local.x, eye_h, eye_local.z)
			var aim := es_pos + es_basis * Vector3(pan * 0.50, 26.5, 16.0 * s_r)
			if _has_emerald_waterfall:
				aim = _emerald_wf_pool_world.lerp(_emerald_wf_top_world, 0.34) + es_basis * Vector3(pan * 0.45, 0.0, 0.0)
			_cam.fov = 68.0
			_cam.look_at_from_position(eye, aim)

		"onfoot_port_sunset", "onfoot_port_storm":
			# Golden-hour sunset (time=17.4) & pouring twilight squall (time=20.4, storm=0.90) eye-height (2.2 m)
			# harbour overlook on Port Scoundrel framing ferns, sea-oat grass, wildflowers, storm-hardened
			# LandmarkLanternHalos & IslandFireflies, glowing tavern windows & harbour swells!
			if _port_scoundrel == null:
				return
			var ps_pos := _port_scoundrel.global_position
			var ps_basis := Basis(Vector3.UP, _island_landing_yaw(_port_scoundrel, -0.37))
			var walk := clampf(_clock * 0.14, 0.0, 1.0)
			var pan := sin(_clock * 0.36) * 0.95
			var eye_local := ps_basis * Vector3(lerpf(26.1, 24.7, walk) + pan * 0.15, 0.0, lerpf(-18.8, -18.2, walk))
			var ground_y := _port_scoundrel.surface_height(eye_local.x, eye_local.z)
			var eye_h := maxf(ground_y, 0.6) + 2.2
			var eye := ps_pos + Vector3(eye_local.x, eye_h, eye_local.z)
			var aim_local := ps_basis * Vector3(lerpf(-12.0, -14.0, walk) + pan, 0.0, lerpf(-24.0, -25.0, walk))
			var aim_h := eye_h - 1.3
			var aim := ps_pos + Vector3(aim_local.x, aim_h, aim_local.z)
			_cam.fov = 64.0
			_cam.look_at_from_position(eye, aim)

		"onfoot_cutlass_shells":
			# Low shoreline close-up (1.15 m eye height, 44 deg FOV) hero-framing a live 367-tri Cutlass Cay
			# ShorePebblesShells beach cluster (5 cobbles, fluted scallop, coral sea star, 4-whorl spiral conch & sand dollar)
			# beside gleaming wet sand & lapping afternoon turquoise waves!
			if _cutlass == null:
				return
			var cc_pos := _cutlass.global_position
			var cc_basis := Basis(Vector3.UP, _island_landing_yaw(_cutlass, 2.77))
			var cluster_local := _cutlass_shell_local
			if not _has_cutlass_shell:
				var fb_xz := cc_basis * Vector3(6.0, 0.0, -50.0)
				cluster_local = Vector3(fb_xz.x, _cutlass.surface_height(fb_xz.x, fb_xz.z), fb_xz.z)
			var cluster_world := cc_pos + Vector3(cluster_local.x, cluster_local.y + 0.05, cluster_local.z)
			var pan := sin(_clock * 0.35) * 0.22
			# Stand ~1.7 m inland (radially upslope away from the shoreline) & +1.05 m up looking seaward-downward
			# so gleaming wet sand & turquoise lapping waves frame the hero beach shell cluster!
			var inland_dir := Vector3(-cluster_local.x, 0.0, -cluster_local.z)
			inland_dir = inland_dir.normalized() if inland_dir.length_squared() > 0.01 else cc_basis.z
			var right_dir := inland_dir.cross(Vector3.UP).normalized()
			var back_vec := (inland_dir * 0.96 + right_dir * 0.28).normalized() * 1.70 + right_dir * pan
			var eye_xz := cluster_world + back_vec
			var local_ground := _cutlass.world_surface_height(eye_xz)
			var eye_y := maxf(cluster_world.y + 1.05, local_ground + 0.95)
			var eye := Vector3(eye_xz.x, eye_y, eye_xz.z)
			_cam.fov = 44.0
			_cam.look_at_from_position(eye, cluster_world)

		"onfoot_sovereigns_waterfall_sunset", "onfoot_sovereigns_waterfall_storm":
			# Golden-hour sunset (time=17.4) & dramatic tropical squall (time=15.0, storm=0.92, M61 storm-flood
			# waterfall + M59 rain-drenched citadel cliffs) clear cove/terrace vantage (66 deg FOV) facing
			# Sovereign's Bastion's 25 m free-falling CitadelWaterfall curtain (+4.45 m clearance) +
			# WaterfallMistRainbow + CascadeShrine, CannonBastion & AstronomerOrrery!
			if _sovereigns_bastion == null:
				return
			var sv_pos := _sovereigns_bastion.global_position
			var sv_basis := Basis(Vector3.UP, _island_landing_yaw(_sovereigns_bastion, 1.72))
			var walk := clampf(_clock * 0.14, 0.0, 1.0)
			var pan := sin(_clock * 0.36) * 0.65
			if _has_sovereigns_waterfall:
				var out_dir := _sovereigns_wf_out_dir
				var right_dir := out_dir.cross(Vector3.UP).normalized()
				var step_fwd := lerpf(28.5, 26.5, walk)
				var lat_off := -4.8 + pan * 0.35
				var eye_xz := _sovereigns_wf_pool_world + out_dir * step_fwd + right_dir * lat_off
				var ground_y := _sovereigns_bastion.world_surface_height(eye_xz)
				ground_y = maxf(ground_y, _sovereigns_bastion.world_surface_height(eye_xz + Vector3(1.4, 0.0, 0.0)))
				ground_y = maxf(ground_y, _sovereigns_bastion.world_surface_height(eye_xz + Vector3(-1.4, 0.0, 0.0)))
				ground_y = maxf(ground_y, _sovereigns_bastion.world_surface_height(eye_xz + Vector3(0.0, 0.0, 1.4)))
				ground_y = maxf(ground_y, _sovereigns_bastion.world_surface_height(eye_xz + Vector3(0.0, 0.0, -1.4)))
				var eye_y := maxf(maxf(ground_y, 0.0) + 2.4, 2.2)
				var eye := Vector3(eye_xz.x, eye_y, eye_xz.z)
				var aim := _sovereigns_wf_pool_world.lerp(_sovereigns_wf_top_world, 0.38) + right_dir * (pan * 0.45)
				_cam.fov = 66.0
				_cam.look_at_from_position(eye, aim)
			else:
				var fb_local := sv_basis * Vector3(52.0 + pan * 0.35, 0.0, lerpf(-58.0, -54.0, walk))
				var ground_y := _sovereigns_bastion.surface_height(fb_local.x, fb_local.z)
				var eye_y := maxf(maxf(ground_y, 0.0) + 2.4, 2.2)
				var eye := sv_pos + Vector3(fb_local.x, eye_y, fb_local.z)
				var aim := sv_pos + sv_basis * Vector3(58.0 + pan * 0.45, 14.0, -18.0)
				_cam.fov = 66.0
				_cam.look_at_from_position(eye, aim)

		"onfoot_cinder_sunset", "onfoot_cinder_storm":
			# Dramatic fiery sunset (time=17.3) & heavy tropical storm (time=15.2, storm=0.92) eye-height (2.4 m)
			# coastal obsidian trail vista on Cinder Crag framing smoky basalt-ash beach/scrub foreground, glowing
			# molten magma rivers, VolcanicFumarole, storm-hardened VolcanoEmberPlume & LandmarkLanternHalos,
			# basalt spires, VolcanicObsidianArch & LavaGate!
			if _cinder_crag == null:
				return
			var cr_pos := _cinder_crag.global_position
			var cr_basis := Basis(Vector3.UP, _island_landing_yaw(_cinder_crag, 2.90))
			var walk := clampf(_clock * 0.14, 0.0, 1.0)
			var pan := sin(_clock * 0.36) * 1.1
			var eye_local := cr_basis * Vector3(lerpf(-62.5, -59.5, walk) + pan * 0.18, 0.0, lerpf(-168.5, -165.0, walk))
			var ground_y := _cinder_crag.surface_height(eye_local.x, eye_local.z)
			ground_y = maxf(ground_y, _cinder_crag.surface_height(eye_local.x + 1.4, eye_local.z))
			ground_y = maxf(ground_y, _cinder_crag.surface_height(eye_local.x - 1.4, eye_local.z))
			ground_y = maxf(ground_y, _cinder_crag.surface_height(eye_local.x, eye_local.z + 1.4))
			ground_y = maxf(ground_y, _cinder_crag.surface_height(eye_local.x, eye_local.z - 1.4))
			var eye_h := maxf(ground_y, 0.6) + 2.4
			var eye := cr_pos + Vector3(eye_local.x, eye_h, eye_local.z)
			var aim_local := cr_basis * Vector3(lerpf(-4.5, -3.5, walk) + pan, 0.0, lerpf(-84.0, -80.0, walk))
			var aim_y := 31.0 if _shot == "onfoot_cinder_storm" else 33.0
			var aim := cr_pos + Vector3(aim_local.x, aim_y, aim_local.z)
			_cam.fov = 64.0
			_cam.look_at_from_position(eye, aim)

		"onfoot_gulls_tidepool":
			# Low shoreline close-up (time=13.6, 44 deg FOV) on Gull's Arch framing an upgraded TidalOutcrops
			# cluster (stratified wet boulders + barnacles + limpets + glossy blue-black Sea-Mussels + vivid
			# crimson-coral Sea Anemone crown rosettes) beside gleaming shallow turquoise surf!
			if _gulls_arch == null:
				return
			var ga_pos := _gulls_arch.global_position
			var outcrop_local := _gulls_tidepool_local
			var cam_dir := _gulls_tidepool_cam_dir
			var sc_y := _gulls_tidepool_scale_y
			if not _has_gulls_tidepool:
				var fb_h := _gulls_arch.surface_height(-12.0, -74.4)
				outcrop_local = Vector3(-12.0, fb_h - 0.24, -74.4)
				var sun_ang := (13.6 - 6.0) / 24.0 * TAU
				var sun_h := Vector3(cos(sun_ang), 0.0, 0.35).normalized()
				var fb_in := Vector3(12.0, 0.0, 74.4).normalized()
				cam_dir = (fb_in * 0.72 + sun_h * 0.28).normalized()
				sc_y = 1.08
			var outcrop_base_world := ga_pos + outcrop_local
			var aim_world := outcrop_base_world + Vector3(0.0, 0.36 * sc_y, 0.0)
			var pan := sin(_clock * 0.35) * 0.20
			var right_dir := cam_dir.cross(Vector3.UP).normalized()
			var eye_xz := outcrop_base_world + cam_dir * 2.40 + right_dir * pan
			var local_ground := _gulls_arch.world_surface_height(eye_xz)
			var eye_y := maxf(maxf(outcrop_base_world.y + 1.15, local_ground + 0.95), 1.25)
			var eye := Vector3(eye_xz.x, eye_y, eye_xz.z)
			_cam.fov = 44.0
			_cam.look_at_from_position(eye, aim_world)

		"onfoot_sovereigns_dawn":
			# Rose-peach dawn sunrise (time=6.2, cloud=0.28, Sea.amp_scale=0.48, 64 deg FOV) eye-height (2.4 m)
			# buttress-free coastal terrace overlook on Sovereign's Bastion looking seaward over sunlit temple
			# ruins (TidalCompass_Terrace & NavGazebo_Terrace), fading dawn lantern halos, foreground 570-tri
			# ferns & hibiscus wildflowers, and deep indigo-teal dawn ocean swells catching rose-peach sunrise light!
			if _sovereigns_bastion == null:
				return
			var sv_pos := _sovereigns_bastion.global_position
			var sv_basis := Basis(Vector3.UP, _island_landing_yaw(_sovereigns_bastion, 1.72))
			var walk := clampf(_clock * 0.14, 0.0, 1.0)
			var pan := sin(_clock * 0.36) * 0.85
			var eye_local := sv_basis * Vector3(lerpf(-110.0, -111.5, walk) + pan * 0.14, 0.0, lerpf(-53.0, -53.2, walk))
			var ground_y := _sovereigns_bastion.surface_height(eye_local.x, eye_local.z)
			ground_y = maxf(ground_y, _sovereigns_bastion.surface_height(eye_local.x + 1.4, eye_local.z))
			ground_y = maxf(ground_y, _sovereigns_bastion.surface_height(eye_local.x - 1.4, eye_local.z))
			ground_y = maxf(ground_y, _sovereigns_bastion.surface_height(eye_local.x, eye_local.z + 1.4))
			ground_y = maxf(ground_y, _sovereigns_bastion.surface_height(eye_local.x, eye_local.z - 1.4))
			var eye_h := maxf(ground_y, 0.6) + 2.4
			var eye := sv_pos + Vector3(eye_local.x, eye_h, eye_local.z)
			var look_dir := (sv_basis * Vector3(-0.998, 0.0, -0.05)).normalized()
			var right_dir := look_dir.cross(Vector3.UP).normalized()
			var aim := eye + look_dir * 65.0 + right_dir * (pan * 1.1) - Vector3(0.0, 2.8, 0.0)
			_cam.fov = 64.0
			_cam.look_at_from_position(eye, aim)

		"onfoot_crescent_driftwood":
			# Low shoreline close-up (time=13.8, ~1.20 m eye height, 44 deg FOV) on Crescent Atoll hero-framing
			# an upgraded 440+-tri CoastalDriftwood log (gnarled bleached trunk + 3-turn braided hemp rope lash +
			# scalloped bracket-fungus shelves + coral sea star + barnacles + draped sea-kelp ribbons) beside
			# gleaming turquoise lagoon shallows!
			if _crescent_atoll == null:
				return
			var ca_pos := _crescent_atoll.global_position
			var ca_basis := Basis(Vector3.UP, _island_landing_yaw(_crescent_atoll, 0.72))
			var log_local := _crescent_driftwood_local
			var cam_dir := _crescent_driftwood_cam_dir
			var sc_y := _crescent_driftwood_scale_y
			if not _has_crescent_driftwood:
				var fb_xz := ca_basis * Vector3(108.1, 0.0, 79.4)
				var fb_h := _crescent_atoll.surface_height(fb_xz.x, fb_xz.z)
				log_local = Vector3(fb_xz.x, fb_h - 0.06, fb_xz.z)
				var fb_n := _crescent_atoll.surface_normal(fb_xz.x, fb_xz.z)
				var fb_up := Vector3(-fb_n.x, 0.0, -fb_n.z)
				cam_dir = fb_up.normalized() if fb_up.length_squared() > 0.0004 else (-ca_basis.x)
				sc_y = 0.84
			var log_base_world := ca_pos + log_local
			var aim_world := log_base_world + Vector3(0.0, 0.19 * sc_y, 0.0)
			var pan := sin(_clock * 0.35) * 0.18
			var right_dir := cam_dir.cross(Vector3.UP).normalized()
			var view_dir := (cam_dir - right_dir * 0.20).normalized()
			var eye_xz := log_base_world + view_dir * 2.15 + right_dir * pan
			var local_ground := _crescent_atoll.world_surface_height(eye_xz)
			var eye_y := maxf(maxf(log_base_world.y + 1.05, local_ground + 0.72), 1.20)
			var eye := Vector3(eye_xz.x, eye_y, eye_xz.z)
			_cam.fov = 44.0
			_cam.look_at_from_position(eye, aim_world)

		"onfoot_cutlass_flagstones":
			# Low trail-level close-up (time=13.8, ~1.25 m eye height, 46 deg FOV) on Cutlass Cay hero-framing
			# upgraded 224-tri moss-joint & 4-companion-cobble TrailSteppingStones winding along the sunlit
			# footpath beside 392-tri hibiscus wildflowers & 286-tri sea-oat grass!
			if _cutlass == null:
				return
			var cc_pos := _cutlass.global_position
			var stone_local := _cutlass_flagstone_local
			var look_dir := _cutlass_flagstone_look_dir
			var sc_y := _cutlass_flagstone_scale_y
			if not _has_cutlass_flagstone:
				var fb_h := _cutlass.surface_height(-10.6, 24.4)
				stone_local = Vector3(-10.6, fb_h - 0.04, 24.4)
				look_dir = Vector3(0.21, 0.0, -0.98).normalized()
				sc_y = 0.85
			var stone_base_world := cc_pos + stone_local
			var right_dir := look_dir.cross(Vector3.UP).normalized()
			var pan := sin(_clock * 0.35) * 0.16
			var eye_xz := stone_base_world - look_dir * 2.10 + right_dir * (0.24 + pan)
			var local_ground := _cutlass.world_surface_height(eye_xz)
			var eye_y := maxf(maxf(stone_base_world.y + 1.15, local_ground + 1.15), 1.25)
			var eye := Vector3(eye_xz.x, eye_y, eye_xz.z)
			var aim_world := stone_base_world + look_dir * 1.55 + Vector3(0.0, 0.14 * sc_y, 0.0)
			_cam.fov = 46.0
			_cam.look_at_from_position(eye, aim_world)

		"onfoot_cutlass_crab":
			# Low shoreline macro close-up (time=13.8, ~0.55 m eye height, 42 deg FOV) on Cutlass Cay hero-framing
			# an upgraded 3D volumetric ShoreCrabs specimen (10-sided scalloped carapace, twin serrated pincer claws,
			# 8 volumetric jointed walking legs, stalked glossy-black eyes & antennae) on sunlit golden beach sand
			# beside sparkling turquoise surf!
			if _cutlass == null:
				return
			var cc_pos := _cutlass.global_position
			var cc_basis := Basis(Vector3.UP, _island_landing_yaw(_cutlass, 2.77))
			var crab_local := _cutlass_crab_local
			var cam_dir := _cutlass_crab_cam_dir
			if _has_cutlass_crab and _cutlass_crab_idx >= 0:
				var cc_det := _cutlass.get_node_or_null(^"IslandDetails") as IslandDetails
				if cc_det != null:
					var cmmi := cc_det.get_node_or_null(^"ShoreCrabs") as MultiMeshInstance3D
					if cmmi != null and cmmi.multimesh != null and _cutlass_crab_idx < cmmi.multimesh.instance_count:
						var live_xf := cmmi.multimesh.get_instance_transform(_cutlass_crab_idx)
						if live_xf.origin.length_squared() > 0.01:
							crab_local = live_xf.origin
			if not _has_cutlass_crab:
				var fb_xz := cc_basis * Vector3(5.0, 0.0, -49.0)
				var fb_h := _cutlass.surface_height(fb_xz.x, fb_xz.z)
				crab_local = Vector3(fb_xz.x, fb_h, fb_xz.z)
				var fb_n := _cutlass.surface_normal(fb_xz.x, fb_xz.z)
				var fb_up := Vector3(-fb_n.x, 0.0, -fb_n.z)
				var sun_ang := (13.8 - 6.0) / 24.0 * TAU
				var sun_h := Vector3(cos(sun_ang), 0.0, 0.35).normalized()
				var up_n := fb_up.normalized() if fb_up.length_squared() > 0.0004 else cc_basis.z
				cam_dir = (up_n * 0.80 + sun_h * 0.25).normalized()
			var sand_y := _cutlass.surface_height(crab_local.x, crab_local.z)
			var crab_world := cc_pos + Vector3(crab_local.x, maxf(crab_local.y, sand_y), crab_local.z)
			var aim_world := crab_world + Vector3(0.0, 0.08, 0.0)
			var pan := sin(_clock * 0.35) * 0.08
			var right_dir := cam_dir.cross(Vector3.UP).normalized()
			var eye_xz := crab_world + cam_dir * 0.95 + right_dir * pan
			var local_ground := _cutlass.world_surface_height(eye_xz)
			var eye_y := maxf(maxf(cc_pos.y + sand_y + 0.48, local_ground + 0.24), 0.55)
			var eye := Vector3(eye_xz.x, eye_y, eye_xz.z)
			_cam.fov = 42.0
			_cam.look_at_from_position(eye, aim_world)

		_:
			if _cutlass != null:
				var cc_pos := _cutlass.global_position
				var cc_basis := Basis(Vector3.UP, _island_landing_yaw(_cutlass, 2.77))
				var eye := _safe_camera_eye(_cutlass, cc_pos + cc_basis * Vector3(-16.0, 12.0, -60.0))
				_cam.look_at_from_position(eye, cc_pos + cc_basis * Vector3(1.5, 10.5, 3.0))






