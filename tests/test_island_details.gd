extends TestCase
## Headless contract tests for sculpted 3D island landmarks (62 BC7 PBR GLB assets)
## and batched MultiMesh `IslandDetails` ground foliage, highland cliff-ledge scrub,
## coastal details, living shore fauna, twilight lantern halos & steep-slope cliff buttresses across all 14 island archetypes.

const IslandDetailsCls := preload("res://src/world/island_details.gd")
const FOLIAGE_SHADER: Shader = preload("res://src/world/foliage_wind.gdshader")
const LANDMARK_DIR := "res://assets/generated/landmarks/"
const SHARED_LANDMARK_TEX_PREFIX := "res://assets/generated/landmarks/shared/"

const GEOLOGY_LANDMARKS: Array[String] = [
	"cliff_buttress_tall.glb",
	"cliff_buttress_wide.glb",
	"cliff_overhang_ledge.glb",
	"coastal_sea_arch.glb",
	"volcanic_basalt_spire.glb",
	"mossy_cliff_boulder_cluster.glb",
]

const SETPIECE_LANDMARKS: Array[String] = [
	"skull_cliff_carving.glb",
	"ancient_temple_stairway.glb",
	"cliff_catwalk_pier.glb",
	"impaled_shipwreck_bow.glb",
	"trail_lantern_post.glb",
	"stone_cairn_marker.glb",
]

const STORYTELLING_LANDMARKS: Array[String] = [
	"ancient_sea_god_idol.glb",
	"volcanic_obsidian_arch.glb",
	"leviathan_ribcage_bones.glb",
	"beached_rowboat_wreck.glb",
	"pirate_warning_gibbet.glb",
	"coastal_signal_brazier.glb",
]

const SKYLINE_LANDMARKS: Array[String] = [
	"cliff_summit_crag_spire.glb",
	"cliff_ruin_aqueduct_arch.glb",
	"cliffside_pirate_watchpost.glb",
	"upper_cliff_strata_rib.glb",
]

const COASTAL_LANDMARKS: Array[String] = [
	"pirate_camp_canopy.glb",
	"sunken_galleon_stern.glb",
	"giant_tidal_coral_arch.glb",
	"obsidian_lava_cauldron_shrine.glb",
]

const HARBOUR_RUINS_LANDMARKS: Array[String] = [
	"harbour_cargo_crane_dock.glb",
	"overgrown_jungle_idol_altar.glb",
	"cliffside_waterfall_shrine.glb",
	"smuggler_contraband_hoard.glb",
]

const MARITIME_RELICS_LANDMARKS: Array[String] = [
	"fort_coastal_watchtower_ruin.glb",
	"shipwreck_bell_buoy_beacon.glb",
	"ancient_compass_monolith_ring.glb",
	"volcanic_chain_bridge_anchor.glb",
]

const WORLD_CRAFT_LANDMARKS: Array[String] = [
	"careening_ship_drydock.glb",
	"cursed_skeleton_throne_shrine.glb",
	"tropical_fishing_stilts_hut.glb",
	"ancient_astronomer_orrery_ruin.glb",
]

const ONFOOT_CRAFT_LANDMARKS: Array[String] = [
	"wooden_trail_footbridge.glb",
	"coastal_smuggler_jetty.glb",
	"ancient_ruined_obelisk_gate.glb",
	"pirate_lookout_bell_frame.glb",
]

const STORY_CRAFT_LANDMARKS: Array[String] = [
	"pirate_tavern_supply_cart.glb",
	"sunken_anchor_memorial.glb",
	"ancient_sun_dial_plaza.glb",
	"volcanic_obsidian_fissure_vent.glb",
]

const FORT_VAULT_LANDMARKS: Array[String] = [
	"stone_well_courtyard.glb",
	"ruined_sea_fort_cannon_bastion.glb",
	"pirate_treasure_vault_door.glb",
	"wooden_shipwreck_crow_nest_mast.glb",
]

const ISLAND_LORE_LANDMARKS: Array[String] = [
	"pirate_rum_distillery_shack.glb",
	"ancient_jade_serpent_totem.glb",
	"coastal_driftwood_arch_camp.glb",
	"volcanic_obsidian_bridge_ruin.glb",
]

const NAUTICAL_CRAFT_LANDMARKS: Array[String] = [
	"coastal_rope_ferry_pulley.glb",
	"ancient_sunken_bell_shrine.glb",
	"pirate_map_planning_table_tent.glb",
	"volcanic_basalt_obelisk_brazier.glb",
]

const SEA_LORE_LANDMARKS: Array[String] = [
	"pirate_shipwright_timber_rack.glb",
	"ancient_tidal_obelisk_mirror.glb",
	"smuggler_rope_cargo_hoist.glb",
	"volcanic_obsidian_forge_anvil.glb",
]

const EXPECTED_MIN_COLLIDERS: Dictionary = {
	"cliff_buttress_tall.glb": 1,
	"cliff_buttress_wide.glb": 1,
	"cliff_overhang_ledge.glb": 2,
	"coastal_sea_arch.glb": 3,
	"volcanic_basalt_spire.glb": 1,
	"mossy_cliff_boulder_cluster.glb": 1,
	"skull_cliff_carving.glb": 2,
	"ancient_temple_stairway.glb": 4,
	"cliff_catwalk_pier.glb": 2,
	"impaled_shipwreck_bow.glb": 2,
	"trail_lantern_post.glb": 1,
	"stone_cairn_marker.glb": 1,
	"ancient_sea_god_idol.glb": 2,
	"volcanic_obsidian_arch.glb": 3,
	"leviathan_ribcage_bones.glb": 2,
	"beached_rowboat_wreck.glb": 1,
	"pirate_warning_gibbet.glb": 1,
	"coastal_signal_brazier.glb": 1,
	"cliff_summit_crag_spire.glb": 2,
	"cliff_ruin_aqueduct_arch.glb": 4,
	"cliffside_pirate_watchpost.glb": 2,
	"upper_cliff_strata_rib.glb": 1,
	"pirate_camp_canopy.glb": 2,
	"sunken_galleon_stern.glb": 2,
	"giant_tidal_coral_arch.glb": 2,
	"obsidian_lava_cauldron_shrine.glb": 1,
	"harbour_cargo_crane_dock.glb": 1,
	"overgrown_jungle_idol_altar.glb": 1,
	"cliffside_waterfall_shrine.glb": 1,
	"smuggler_contraband_hoard.glb": 1,
	"fort_coastal_watchtower_ruin.glb": 1,
	"shipwreck_bell_buoy_beacon.glb": 1,
	"ancient_compass_monolith_ring.glb": 1,
	"volcanic_chain_bridge_anchor.glb": 1,
	"careening_ship_drydock.glb": 1,
	"cursed_skeleton_throne_shrine.glb": 1,
	"tropical_fishing_stilts_hut.glb": 1,
	"ancient_astronomer_orrery_ruin.glb": 1,
	"wooden_trail_footbridge.glb": 1,
	"coastal_smuggler_jetty.glb": 1,
	"ancient_ruined_obelisk_gate.glb": 1,
	"pirate_lookout_bell_frame.glb": 1,
	"pirate_tavern_supply_cart.glb": 1,
	"sunken_anchor_memorial.glb": 1,
	"ancient_sun_dial_plaza.glb": 1,
	"volcanic_obsidian_fissure_vent.glb": 1,
	"stone_well_courtyard.glb": 1,
	"ruined_sea_fort_cannon_bastion.glb": 1,
	"pirate_treasure_vault_door.glb": 1,
	"wooden_shipwreck_crow_nest_mast.glb": 1,
	"pirate_rum_distillery_shack.glb": 1,
	"ancient_jade_serpent_totem.glb": 1,
	"coastal_driftwood_arch_camp.glb": 1,
	"volcanic_obsidian_bridge_ruin.glb": 1,
	"coastal_rope_ferry_pulley.glb": 1,
	"ancient_sunken_bell_shrine.glb": 1,
	"pirate_map_planning_table_tent.glb": 1,
	"volcanic_basalt_obelisk_brazier.glb": 1,
	"pirate_shipwright_timber_rack.glb": 1,
	"ancient_tidal_obelisk_mirror.glb": 1,
	"smuggler_rope_cargo_hoist.glb": 1,
	"volcanic_obsidian_forge_anvil.glb": 1,
}

const EXPECTED_LANTERN_EMPTIES: Dictionary = {
	"skull_cliff_carving.glb": ["Lantern_SkullEyeL", "Lantern_SkullEyeR"],
	"cliff_catwalk_pier.glb": ["Lantern_Catwalk"],
	"impaled_shipwreck_bow.glb": ["Lantern_WreckBow"],
	"trail_lantern_post.glb": ["Lantern_Trail"],
	"ancient_sea_god_idol.glb": ["Lantern_IdolEyeL", "Lantern_IdolEyeR"],
	"volcanic_obsidian_arch.glb": ["Lantern_MagmaArch"],
	"beached_rowboat_wreck.glb": ["Lantern_Rowboat"],
	"pirate_warning_gibbet.glb": ["Lantern_Gallows"],
	"coastal_signal_brazier.glb": ["Lantern_Brazier"],
	"cliffside_pirate_watchpost.glb": ["Lantern_Watchpost"],
	"pirate_camp_canopy.glb": ["Lantern_Camp"],
	"sunken_galleon_stern.glb": ["Lantern_Stern"],
	"obsidian_lava_cauldron_shrine.glb": ["Lantern_CalderaShrine"],
	"harbour_cargo_crane_dock.glb": ["Lantern_Crane*"],
	"overgrown_jungle_idol_altar.glb": ["Lantern_Altar*"],
	"cliffside_waterfall_shrine.glb": ["Lantern_WaterfallShrine*"],
	"smuggler_contraband_hoard.glb": ["Lantern_Hoard*"],
	"fort_coastal_watchtower_ruin.glb": ["Lantern_Watchtower*"],
	"shipwreck_bell_buoy_beacon.glb": ["Lantern_ReefBeacon*"],
	"ancient_compass_monolith_ring.glb": ["Lantern_Monolith*"],
	"volcanic_chain_bridge_anchor.glb": ["Lantern_ChainPylon*"],
	"careening_ship_drydock.glb": ["Lantern_Drydock*"],
	"cursed_skeleton_throne_shrine.glb": ["Lantern_Throne*"],
	"tropical_fishing_stilts_hut.glb": ["Lantern_FishHut*"],
	"ancient_astronomer_orrery_ruin.glb": ["Lantern_Orrery*"],
	"wooden_trail_footbridge.glb": ["Lantern_Footbridge*"],
	"coastal_smuggler_jetty.glb": ["Lantern_Jetty*"],
	"ancient_ruined_obelisk_gate.glb": ["Lantern_ObeliskGate*"],
	"pirate_lookout_bell_frame.glb": ["Lantern_BellFrame*"],
	"pirate_tavern_supply_cart.glb": ["Lantern_Cart*"],
	"sunken_anchor_memorial.glb": ["Lantern_Anchor*"],
	"ancient_sun_dial_plaza.glb": ["Lantern_Sundial*"],
	"volcanic_obsidian_fissure_vent.glb": ["Lantern_MagmaVent*"],
	"stone_well_courtyard.glb": ["Lantern_Well*"],
	"ruined_sea_fort_cannon_bastion.glb": ["Lantern_Bastion*"],
	"pirate_treasure_vault_door.glb": ["Lantern_Vault*"],
	"wooden_shipwreck_crow_nest_mast.glb": ["Lantern_CrowNest*"],
	"pirate_rum_distillery_shack.glb": ["Lantern_Still*"],
	"ancient_jade_serpent_totem.glb": ["Lantern_Serpent*"],
	"coastal_driftwood_arch_camp.glb": ["Lantern_Bivouac*"],
	"volcanic_obsidian_bridge_ruin.glb": ["Lantern_VolcBridge*"],
	"coastal_rope_ferry_pulley.glb": ["Lantern_FerryWinch*"],
	"ancient_sunken_bell_shrine.glb": ["Lantern_BellShrine*"],
	"pirate_map_planning_table_tent.glb": ["Lantern_MapTent*"],
	"volcanic_basalt_obelisk_brazier.glb": ["Lantern_BasaltBrazier*"],
	"pirate_shipwright_timber_rack.glb": ["Lantern_Shipyard*"],
	"ancient_tidal_obelisk_mirror.glb": ["Lantern_MirrorShrine*"],
	"smuggler_rope_cargo_hoist.glb": ["Lantern_SmugglerHoist*"],
	"volcanic_obsidian_forge_anvil.glb": ["Lantern_VolcForge*"],
}

const GROUNDING_AUDIT_PREFIXES: Array[String] = [
	"SkullCliffCarving",
	"TempleStairway_",
	"CliffCatwalk",
	"ImpaledShipwreck",
	"SeaGodIdol_",
	"VolcanicObsidianArch_",
	"LeviathanRibcage_",
	"BeachedRowboat_",
	"PirateGibbet_",
	"SignalBrazier_",
	"SummitCrag_",
	"RuinAqueduct_",
	"PirateWatchpost_",
	"UpperStrataRib_",
	"PirateCamp_",
	"SunkenStern_",
	"LavaCauldronShrine_",
	"HarbourCrane_",
	"JungleAltar_",
	"CascadeShrine_",
	"SmugglerHoard_",
	"FortWatchtower_",
	"CompassMonolith_",
	"VolcanicChainPylon_",
	"ShipDrydock_",
	"SkeletonThrone_",
	"FishingHut_",
	"AstronomerOrrery_",
	"ObeliskGate_",
	"TrailFootbridge_",
	"LookoutBell_",
	"SupplyCart_",
	"AnchorMemorial_",
	"SundialPlaza_",
	"ObsidianVent_",
	"StoneWell_",
	"CannonBastion_",
	"TreasureVault_",
	"CrowNestMast_",
	"RumDistillery_",
	"SerpentTotem_",
	"DriftwoodCamp_",
	"VolcanicBridgeRuin_",
	"FerryWinch_",
	"BellShrine_",
	"MapTent_",
	"BasaltBrazier_",
	"ShipyardRack_",
	"MirrorShrine_",
	"SmugglerHoist_",
	"VolcForge_",
]

const GROUND_COVER_LAYERS: Array[String] = [
	"GrassClumps",
	"JungleFerns",
	"HibiscusShrubs",
	"CoastalDriftwood",
	"ShorePebblesShells",
	"TidalOutcrops",
	"TrailSteppingStones",
	"IslandButterflies",
	"ShoreCrabs",
	"LandmarkLanternHalos",
]

const FOLIAGE_WIND_LAYERS: Array[String] = [
	"GrassClumps",
	"JungleFerns",
	"HibiscusShrubs",
]


func _init_host() -> void:
	Net.start_single_player()
	Sea.amp_scale = 0.0
	Sea.time = 0.0


func _count_mesh_tris(mesh: Mesh) -> int:
	if mesh == null:
		return 0
	var total := 0
	for si in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(si)
		if arrays.is_empty():
			continue
		var idx_var: Variant = arrays[Mesh.ARRAY_INDEX]
		if idx_var is PackedInt32Array and not (idx_var as PackedInt32Array).is_empty():
			total += int(float((idx_var as PackedInt32Array).size()) / 3.0)
		else:
			var verts_var: Variant = arrays[Mesh.ARRAY_VERTEX]
			if verts_var is PackedVector3Array:
				total += int(float((verts_var as PackedVector3Array).size()) / 3.0)
	return total


func _count_bad_normals(mesh: Mesh) -> int:
	if mesh == null:
		return 1
	var bad := 0
	for si in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(si)
		if arrays.is_empty():
			bad += 1
			continue
		var norms_var: Variant = arrays[Mesh.ARRAY_NORMAL]
		if not (norms_var is PackedVector3Array):
			bad += 1
			continue
		var norms: PackedVector3Array = norms_var
		if norms.is_empty():
			bad += 1
			continue
		for nv in norms:
			if not nv.is_finite() or nv.length_squared() < 0.5 or nv.length_squared() > 1.5:
				bad += 1
	return bad


func _record_shared_landmark_tex(tex: Texture2D, filename: String, mesh_name: String,
		slot_name: String, unique_pbr_paths: Dictionary, non_shared_errors: Array[String]) -> void:
	if tex == null:
		return
	var rp := tex.resource_path
	var key := rp if not rp.is_empty() else "<embedded:%s:%s:%s>" % [filename, mesh_name, slot_name]
	unique_pbr_paths[key] = true
	if not rp.begins_with(SHARED_LANDMARK_TEX_PREFIX):
		non_shared_errors.append("%s (%s:%s -> %s)" % [
			filename, mesh_name, slot_name, rp if not rp.is_empty() else "<embedded>",
		])


func _relative_transform(node: Node3D, ancestor: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var cur: Node = node
	while cur != null and cur != ancestor:
		if cur is Node3D:
			xf = (cur as Node3D).transform * xf
		cur = cur.get_parent()
	return xf


func _compute_landmark_visual_aabb(landmark: Node3D, isl: Node3D) -> Dictionary:
	var has_box := false
	var combined := AABB()
	var meshes: Array[Node] = landmark.find_children("*", "MeshInstance3D", true, false)
	if landmark is MeshInstance3D:
		meshes.append(landmark)
	for n in meshes:
		var mi := n as MeshInstance3D
		if mi == null or not mi.visible or mi.mesh == null or String(mi.name).begins_with("col_"):
			continue
		var local_box := mi.mesh.get_aabb()
		var rel_xf := _relative_transform(mi, isl)
		for ci in 8:
			var pt := rel_xf * local_box.get_endpoint(ci)
			if not has_box:
				combined = AABB(pt, Vector3.ZERO)
				has_box = true
			else:
				combined = combined.expand(pt)
	return {"valid": has_box, "aabb": combined}


func _is_grounding_audit_landmark(node_name: String) -> bool:
	if node_name.begins_with("CoastalSeaArch_") or node_name.begins_with("TidalCoralArch_") \
			or node_name.begins_with("ReefBeacon_") or node_name.begins_with("SmugglerJetty_"):
		return false
	for prefix in GROUNDING_AUDIT_PREFIXES:
		if node_name.begins_with(prefix):
			return true
	return false


func test_all_12_landmark_glbs_load_pbr_tangents_and_colliders() -> void:
	var all_landmarks: Array[String] = []
	all_landmarks.append_array(GEOLOGY_LANDMARKS)
	all_landmarks.append_array(SETPIECE_LANDMARKS)
	all_landmarks.append_array(STORYTELLING_LANDMARKS)
	all_landmarks.append_array(SKYLINE_LANDMARKS)
	all_landmarks.append_array(COASTAL_LANDMARKS)
	all_landmarks.append_array(HARBOUR_RUINS_LANDMARKS)
	all_landmarks.append_array(MARITIME_RELICS_LANDMARKS)
	all_landmarks.append_array(WORLD_CRAFT_LANDMARKS)
	all_landmarks.append_array(ONFOOT_CRAFT_LANDMARKS)
	all_landmarks.append_array(STORY_CRAFT_LANDMARKS)
	all_landmarks.append_array(FORT_VAULT_LANDMARKS)
	all_landmarks.append_array(ISLAND_LORE_LANDMARKS)
	all_landmarks.append_array(NAUTICAL_CRAFT_LANDMARKS)
	all_landmarks.append_array(SEA_LORE_LANDMARKS)
	check_eq(all_landmarks.size(), 62, "expected 62 sculpted landmark GLBs")

	var unique_pbr_paths := {}
	var non_shared_tex_errors: Array[String] = []

	for filename in all_landmarks:
		var path := LANDMARK_DIR + filename
		check(ResourceLoader.exists(path), "missing landmark GLB: " + path)
		var packed := load(path) as PackedScene
		check(packed != null, "failed to load landmark PackedScene: " + path)
		if packed == null:
			continue

		var inst := packed.instantiate()
		check(inst is Node3D, "landmark root must be Node3D: " + filename)
		var all_meshes := inst.find_children("*", "MeshInstance3D", true, false)

		var visual_meshes: Array[MeshInstance3D] = []
		var col_meshes: Array[MeshInstance3D] = []
		var raw_prims := 0
		for n in all_meshes:
			var mi := n as MeshInstance3D
			if mi == null:
				continue
			if mi.mesh is PrimitiveMesh:
				raw_prims += 1
			if mi.name.begins_with("col_"):
				col_meshes.append(mi)
			else:
				visual_meshes.append(mi)

		check(visual_meshes.size() >= 1, "landmark has no visual MeshInstance3D: " + filename)
		check_eq(raw_prims, 0, "landmark contains raw PrimitiveMesh: " + filename)

		var total_tris := 0
		var bad_normals := 0
		var pbr_surfaces := 0
		var missing_tangents := 0
		var bad_tangents := 0

		for vmi in visual_meshes:
			var mesh := vmi.mesh
			check(mesh != null, "visual MeshInstance3D has null mesh in %s (%s)" % [filename, vmi.name])
			if mesh == null:
				continue
			total_tris += _count_mesh_tris(mesh)
			bad_normals += _count_bad_normals(mesh)

			for si in mesh.get_surface_count():
				var mat: Material = vmi.get_active_material(si)
				if mat == null:
					mat = mesh.surface_get_material(si)
				if mat is StandardMaterial3D:
					var std := mat as StandardMaterial3D
					var has_albedo := std.albedo_texture != null
					var has_normal := std.normal_texture != null
					if has_albedo and has_normal:
						pbr_surfaces += 1
					_record_shared_landmark_tex(std.albedo_texture, filename, String(vmi.name),
						"albedo", unique_pbr_paths, non_shared_tex_errors)
					_record_shared_landmark_tex(std.normal_texture, filename, String(vmi.name),
						"normal", unique_pbr_paths, non_shared_tex_errors)
					_record_shared_landmark_tex(std.roughness_texture, filename, String(vmi.name),
						"roughness", unique_pbr_paths, non_shared_tex_errors)
					if has_albedo or has_normal:
						var arrays := mesh.surface_get_arrays(si)
						var tang_var: Variant = arrays[Mesh.ARRAY_TANGENT] if not arrays.is_empty() else null
						if not (tang_var is PackedFloat32Array) or (tang_var as PackedFloat32Array).is_empty():
							missing_tangents += 1
						else:
							var tangs: PackedFloat32Array = tang_var
							for tv in tangs:
								if not is_finite(tv):
									bad_tangents += 1
									break

		var min_tris := 500
		print("    landmark %-32s %5d tris  (%d vis, %d col_, %d PBR)" % [
			filename, total_tris, visual_meshes.size(), col_meshes.size(), pbr_surfaces])
		check(total_tris >= min_tris,
			"landmark %s has too few visual tris (%d < %d)" % [filename, total_tris, min_tris])
		check_eq(bad_normals, 0, "landmark %s has non-finite or non-unit normals (%d)" % [filename, bad_normals])
		check(pbr_surfaces >= 1,
			"landmark %s must have >= 1 PBR StandardMaterial3D with albedo_texture & normal_texture" % filename)
		check_eq(missing_tangents, 0,
			"landmark %s has textured surface(s) missing ARRAY_TANGENT (%d)" % [filename, missing_tangents])
		check_eq(bad_tangents, 0,
			"landmark %s has non-finite ARRAY_TANGENT values (%d)" % [filename, bad_tangents])

		var min_cols := int(EXPECTED_MIN_COLLIDERS.get(filename, 1))
		check(col_meshes.size() >= min_cols,
			"landmark %s has too few col_* meshes (%d < %d)" % [filename, col_meshes.size(), min_cols])
		for cmi in col_meshes:
			check(cmi.mesh != null and cmi.mesh.get_faces().size() >= 3,
				"collider %s in %s has degenerate mesh" % [cmi.name, filename])

		if EXPECTED_LANTERN_EMPTIES.has(filename):
			var empty_names: Array = EXPECTED_LANTERN_EMPTIES[filename]
			for empty_name_var in empty_names:
				var empty_name := String(empty_name_var)
				var found_empty := inst.find_child(empty_name, true, false)
				check(found_empty != null and found_empty is Node3D,
					"missing Node3D lantern empty %s in %s" % [empty_name, filename])

		inst.free()

	# Shared Landmark PBR Texture Deduplication contract across all 62 GLBs.
	print("    shared landmark PBR textures: %d unique path(s) across %d GLBs (non-shared: %d)" % [
		unique_pbr_paths.size(), all_landmarks.size(), non_shared_tex_errors.size()])
	check(non_shared_tex_errors.is_empty(),
		"every landmark textured material must resolve from %s (offenders: %s)" % [
			SHARED_LANDMARK_TEX_PREFIX, ", ".join(non_shared_tex_errors.slice(0, 6))])
	check_eq(unique_pbr_paths.size(), 30,
		"expected strictly 30 unique shared landmark PBR texture paths across all 62 GLBs (got %d)" % unique_pbr_paths.size())


func _collect_leaked_detail_caches() -> Array[String]:
	var leaked_fields: Array[String] = []
	if IslandDetailsCls._grass_mesh != null:
		leaked_fields.append("_grass_mesh")
	if IslandDetailsCls._fern_mesh != null:
		leaked_fields.append("_fern_mesh")
	if IslandDetailsCls._hibiscus_mesh != null:
		leaked_fields.append("_hibiscus_mesh")
	if IslandDetailsCls._driftwood_mesh != null:
		leaked_fields.append("_driftwood_mesh")
	if IslandDetailsCls._pebbles_mesh != null:
		leaked_fields.append("_pebbles_mesh")
	if IslandDetailsCls._tidal_rock_mesh != null:
		leaked_fields.append("_tidal_rock_mesh")
	if IslandDetailsCls._fallback_buttress_mesh != null:
		leaked_fields.append("_fallback_buttress_mesh")
	if IslandDetailsCls._fallback_buttress_wide_mesh != null:
		leaked_fields.append("_fallback_buttress_wide_mesh")
	if IslandDetailsCls._stepping_stone_mesh != null:
		leaked_fields.append("_stepping_stone_mesh")
	if IslandDetailsCls._butterfly_mesh != null:
		leaked_fields.append("_butterfly_mesh")
	if IslandDetailsCls._crab_mesh != null:
		leaked_fields.append("_crab_mesh")
	if IslandDetailsCls._lantern_halo_mesh != null:
		leaked_fields.append("_lantern_halo_mesh")
	if IslandDetailsCls._foliage_material != null:
		leaked_fields.append("_foliage_material")
	if IslandDetailsCls._wood_stone_material != null:
		leaked_fields.append("_wood_stone_material")
	if IslandDetailsCls._pebble_material != null:
		leaked_fields.append("_pebble_material")
	if IslandDetailsCls._tidal_rock_material != null:
		leaked_fields.append("_tidal_rock_material")
	if IslandDetailsCls._buttress_fallback_material != null:
		leaked_fields.append("_buttress_fallback_material")
	if IslandDetailsCls._stepping_stone_mat != null:
		leaked_fields.append("_stepping_stone_mat")
	if IslandDetailsCls._butterfly_mat != null:
		leaked_fields.append("_butterfly_mat")
	if IslandDetailsCls._crab_mat != null:
		leaked_fields.append("_crab_mat")
	if IslandDetailsCls._lantern_halo_mat != null:
		leaked_fields.append("_lantern_halo_mat")
	if not IslandDetailsCls._glb_mesh_cache.is_empty():
		leaked_fields.append("_glb_mesh_cache(%d)" % IslandDetailsCls._glb_mesh_cache.size())
	return leaked_fields


func test_island_details_all_14_archetypes_batched_grounded_and_deterministic() -> void:
	_init_host()
	check_eq(IslandGenerator.ARCHETYPES.size(), 14, "expected 14 island archetypes")

	for idx in IslandGenerator.ARCHETYPES.size():
		var arch := IslandGenerator.ARCHETYPES[idx]
		var spec := {
			"id": "test_det_" + String(arch),
			"name": "Test Details " + String(arch),
			"archetype": arch,
			"seed": 700 + idx,
		}
		var isl := IslandGenerator.build_island(spec)
		add_child(isl)

		# IslandGenerator.build_island() natively attaches exactly one IslandDetails child.
		var detail_nodes := isl.find_children("*", "IslandDetails", false, false)
		check_eq(detail_nodes.size(), 1,
			"build_island attaches exactly 1 IslandDetails child on " + String(arch))
		var details := isl.get_node_or_null(^"IslandDetails") as IslandDetails
		check(details != null, "build_island attached null IslandDetails for " + String(arch))
		if details == null:
			isl.queue_free()
			continue

		check(details.is_in_group(&"island_details"),
			"IslandDetails registers in island_details group on " + String(arch))

		var mm_count := details.get_multimesh_count()
		check(mm_count >= 5 and mm_count <= 12,
			"archetype %s MultiMesh draw-call count must be 5..12 (got %d)" % [arch, mm_count])

		# Ensure ZERO unstripped col_* helper geometry or collider nodes inside IslandDetails.
		var leaked_cols := details.find_children("col_*", "", true, false)
		check(leaked_cols.is_empty(),
			"archetype %s IslandDetails contains unstripped col_* node(s): %d" % [arch, leaked_cols.size()])
		var leaked_shapes := details.find_children("*", "CollisionShape3D", true, false)
		check(leaked_shapes.is_empty(),
			"archetype %s IslandDetails contains unexpected CollisionShape3D node(s)" % arch)

		var mmis := details.find_children("*", "MultiMeshInstance3D", true, false)
		check_eq(mmis.size(), mm_count,
			"archetype %s get_multimesh_count() matches MultiMeshInstance3D child count" % arch)

		var raw_prims := 0
		var bad_normals := 0
		for n in mmis:
			var mmi := n as MultiMeshInstance3D
			if mmi == null:
				continue
			check(not mmi.name.begins_with("col_"),
				"archetype %s MultiMesh has col_* name: %s" % [arch, mmi.name])
			check(mmi.multimesh != null and mmi.multimesh.mesh != null,
				"archetype %s MultiMesh '%s' has null mesh" % [arch, mmi.name])
			if mmi.multimesh == null or mmi.multimesh.mesh == null:
				continue
			var mesh := mmi.multimesh.mesh
			if mesh is PrimitiveMesh:
				raw_prims += 1
			check(not mesh.resource_name.begins_with("col_"),
				"archetype %s MultiMesh '%s' carries col_* mesh resource" % [arch, mmi.name])
			bad_normals += _count_bad_normals(mesh)

			if GROUND_COVER_LAYERS.has(mmi.name):
				check_eq(mmi.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
					"archetype %s ground-cover layer '%s' must disable shadow casting" % [arch, mmi.name])

			if FOLIAGE_WIND_LAYERS.has(mmi.name):
				var fmat := mmi.material_override as ShaderMaterial
				if fmat == null and mesh.get_surface_count() > 0:
					fmat = mesh.surface_get_material(0) as ShaderMaterial
				check(fmat != null and fmat.shader == FOLIAGE_SHADER,
					"archetype %s foliage layer '%s' must bind foliage_wind.gdshader" % [arch, mmi.name])

			if mmi.material_override is StandardMaterial3D:
				var std_override := mmi.material_override as StandardMaterial3D
				check(std_override.vertex_color_is_srgb,
					"archetype %s procedural StandardMaterial3D on '%s' must enable vertex_color_is_srgb" % [
						arch, mmi.name])

		for extra_mi_node in details.find_children("*", "MeshInstance3D", true, false):
			var extra_mi := extra_mi_node as MeshInstance3D
			if extra_mi != null and extra_mi.mesh is PrimitiveMesh:
				raw_prims += 1

		check_eq(raw_prims, 0, "archetype %s IslandDetails contains zero PrimitiveMeshes" % arch)
		check_eq(bad_normals, 0, "archetype %s IslandDetails mesh normals are all finite unit vectors" % arch)

		# Verify density targets per island tier & biome.
		var grass_n := details.get_grass_count()
		var fern_n := details.get_fern_count()
		var hibiscus_n := details.get_hibiscus_count()
		var coastal_n := details.get_coastal_detail_count()
		var buttress_n := details.get_cliff_buttress_count()
		var stone_n := details.get_stepping_stone_count()
		var butterfly_n := details.get_butterfly_count()
		var crab_n := details.get_shore_crab_count()
		var halo_n: int = details.get_lantern_halo_count()
		var total_n := details.get_total_instance_count()

		print("    details %-16s r=%5.1fm  DC=%d  total=%4d  grass=%3d  fern=%3d  hib=%3d  coast=%3d  butt=%2d  stone=%2d  bf=%2d  crab=%2d  halo=%2d" % [
			String(arch), isl.island_radius, mm_count, total_n, grass_n, fern_n, hibiscus_n, coastal_n, buttress_n, stone_n, butterfly_n, crab_n, halo_n])

		if arch != &"volcano_crag" and arch != &"sea_stack" and isl.island_radius >= 50.0:
			check(grass_n >= 180 and grass_n <= 720,
				"archetype %s grass count out of 180..720 (got %d)" % [arch, grass_n])
			check(fern_n + hibiscus_n >= 80 and fern_n + hibiscus_n <= 380,
				"archetype %s fern+hibiscus count out of 80..380 (got %d)" % [arch, fern_n + hibiscus_n])
			check(coastal_n >= 40,
				"archetype %s coastal detail count < 40 (got %d)" % [arch, coastal_n])
			check(buttress_n >= 8,
				"archetype %s cliff buttress count < 8 (got %d)" % [arch, buttress_n])
		elif arch == &"volcano_crag" or arch == &"sea_stack":
			check(grass_n >= 110 and grass_n <= 720,
				"archetype %s grass count out of 110..720 (got %d)" % [arch, grass_n])
			check(fern_n + hibiscus_n >= 40 and fern_n + hibiscus_n <= 380,
				"archetype %s fern+hibiscus count out of 40..380 (got %d)" % [arch, fern_n + hibiscus_n])
			check(buttress_n >= 8,
				"archetype %s cliff buttress count < 8 (got %d)" % [arch, buttress_n])
			check(total_n >= 100,
				"archetype %s total detail count < 100 (got %d)" % [arch, total_n])
		else:
			check(grass_n >= 110 and grass_n <= 720,
				"archetype %s compact grass count out of 110..720 (got %d)" % [arch, grass_n])
			check(fern_n + hibiscus_n >= 40 and fern_n + hibiscus_n <= 380,
				"archetype %s compact fern+hibiscus count out of 40..380 (got %d)" % [arch, fern_n + hibiscus_n])
			check(total_n >= 80,
				"archetype %s compact island total detail count < 80 (got %d)" % [arch, total_n])

		# Verify EVERY placed cliff buttress sits strictly on a steep cliff slope (ny < 0.725).
		var buttress_nys := details.get_placed_buttress_normals_y()
		check_eq(buttress_nys.size(), buttress_n,
			"archetype %s buttress normal sample count matches get_cliff_buttress_count()" % arch)
		var bad_slope_count := 0
		var max_ny := -1.0
		for ny_var in buttress_nys:
			var ny := float(ny_var)
			max_ny = maxf(max_ny, ny)
			if ny >= 0.725:
				bad_slope_count += 1
		check_eq(bad_slope_count, 0,
			"archetype %s placed %d buttress(es) on shallow slope (max ny=%.3f >= 0.725)" % [
				arch, bad_slope_count, max_ny])

		# Verify determinism: building a second island with identical spec produces exact same counts.
		var isl_b := IslandGenerator.build_island(spec)
		add_child(isl_b)
		var details_b := isl_b.get_node_or_null(^"IslandDetails") as IslandDetails
		check(details_b != null, "second build_island attached null IslandDetails for " + String(arch))
		if details_b != null:
			check_eq(details_b.get_multimesh_count(), mm_count,
				"archetype %s deterministic multimesh count" % arch)
			check_eq(details_b.get_total_instance_count(), total_n,
				"archetype %s deterministic total instance count" % arch)
			check_eq(details_b.get_grass_count(), grass_n,
				"archetype %s deterministic grass count" % arch)
			check_eq(details_b.get_fern_count(), fern_n,
				"archetype %s deterministic fern count" % arch)
			check_eq(details_b.get_hibiscus_count(), hibiscus_n,
				"archetype %s deterministic hibiscus count" % arch)
			check_eq(details_b.get_coastal_detail_count(), coastal_n,
				"archetype %s deterministic coastal detail count" % arch)
			check_eq(details_b.get_cliff_buttress_count(), buttress_n,
				"archetype %s deterministic cliff buttress count" % arch)
			check_eq(details_b.get_stepping_stone_count(), stone_n,
				"archetype %s deterministic stepping stone count" % arch)
			check_eq(details_b.get_butterfly_count(), butterfly_n,
				"archetype %s deterministic butterfly count" % arch)
			check_eq(details_b.get_shore_crab_count(), crab_n,
				"archetype %s deterministic shore crab count" % arch)
			check_eq(details_b.get_lantern_halo_count(), halo_n,
				"archetype %s deterministic lantern halo count" % arch)

		isl.queue_free()
		isl_b.queue_free()

	await physics_frames(3)


func test_island_details_outpost_keepouts_wind_and_zero_leaks() -> void:
	_init_host()

	var outpost := IslandGenerator.build_island(Archipelago.ISLAND_SPECS[0]) as Outpost
	var cutlass := IslandGenerator.build_island(Archipelago.ISLAND_SPECS[1])
	check(outpost != null, "Port Scoundrel built as Outpost")
	check(cutlass != null, "Cutlass Cay built as Island")
	add_child(outpost)
	add_child(cutlass)
	await physics_frames(1)

	# Read the auto-attached IslandDetails children created by IslandGenerator.build_island().
	var op_details := outpost.get_node_or_null(^"IslandDetails") as IslandDetails
	var cc_details := cutlass.get_node_or_null(^"IslandDetails") as IslandDetails

	check(op_details != null and cc_details != null,
		"IslandDetails auto-populated cleanly on Port Scoundrel and Cutlass Cay")
	check_eq(outpost.find_children("*", "IslandDetails", false, false).size(), 1,
		"Port Scoundrel owns exactly one IslandDetails node")
	check_eq(cutlass.find_children("*", "IslandDetails", false, false).size(), 1,
		"Cutlass Cay owns exactly one IslandDetails node")
	check(IslandDetailsCls._active_details >= 2,
		"active IslandDetails counter tracks live instances (got %d)" % IslandDetailsCls._active_details)

	# 1. Verify Outpost pier planks & mooring keepouts on placed grass positions.
	var op_grass := op_details.get_placed_grass_positions()
	check_eq(op_grass.size(), op_details.get_grass_count(),
		"get_placed_grass_positions() size matches get_grass_count() on Port Scoundrel")
	check(op_grass.size() >= 180,
		"Port Scoundrel places lush coastal grass (>= 180, got %d)" % op_grass.size())

	var mooring_xz := Vector2(outpost.mooring_transform.origin.x, outpost.mooring_transform.origin.z)
	var dock_inv := outpost.dock_local_transform.affine_inverse()
	var mooring_violations := 0
	var pier_violations := 0
	var submerged_grass := 0
	var min_mooring_dist := INF
	for gp_var in op_grass:
		var gp: Vector3 = gp_var
		var d_moor := Vector2(gp.x, gp.z).distance_to(mooring_xz)
		min_mooring_dist = minf(min_mooring_dist, d_moor)
		if d_moor < 7.5:
			mooring_violations += 1
		var p_dock := dock_inv * gp
		if absf(p_dock.x) < Outpost.PIER_HALF_WIDTH + 0.35 \
				and p_dock.z <= 0.6 and p_dock.z >= -(Outpost.PIER_LENGTH + 0.5):
			pier_violations += 1
		if gp.y <= 0.0:
			submerged_grass += 1

	check_eq(mooring_violations, 0,
		"Port Scoundrel grass must stay >= 7.5 m from mooring_transform (min=%.2f m, %d violations)" % [
			min_mooring_dist, mooring_violations])
	check_eq(pier_violations, 0,
		"Port Scoundrel grass must stay off dock pier planks (%d violations)" % pier_violations)
	check_eq(submerged_grass, 0,
		"Port Scoundrel grass must stay above sea level (%d submerged)" % submerged_grass)

	# 2. Verify IslandDetails wind shader material registers with Island._foliage_materials!
	var wind_mat: ShaderMaterial = IslandDetailsCls._foliage_material
	check(wind_mat != null and wind_mat.shader == FOLIAGE_SHADER,
		"IslandDetails._foliage_material binds foliage_wind.gdshader")
	check(outpost._foliage_materials.has(wind_mat),
		"Port Scoundrel _foliage_materials contains IslandDetails wind shader material")
	check(cutlass._foliage_materials.has(wind_mat),
		"Cutlass Cay _foliage_materials contains IslandDetails wind shader material")

	# 2b. Wave I-11 Botanical Craft, Wave I-12 Coastal Micro-Craft, Wave I-14 Fauna & Halo Craft,
	#     Wave I-15 Trail Masonry & Gaussian Halo Craft & Trail Pebble Hygiene assertions.
	if cc_details != null:
		var cc_grass_mmi := cc_details.get_node_or_null(^"GrassClumps") as MultiMeshInstance3D
		var cc_fern_mmi := cc_details.get_node_or_null(^"JungleFerns") as MultiMeshInstance3D
		var cc_hib_mmi := cc_details.get_node_or_null(^"HibiscusShrubs") as MultiMeshInstance3D
		check(cc_grass_mmi != null and cc_grass_mmi.multimesh != null and cc_grass_mmi.multimesh.mesh != null,
			"Cutlass Cay mounts GrassClumps MultiMesh with procedural mesh")
		check(cc_fern_mmi != null and cc_fern_mmi.multimesh != null and cc_fern_mmi.multimesh.mesh != null,
			"Cutlass Cay mounts JungleFerns MultiMesh with procedural mesh")
		check(cc_hib_mmi != null and cc_hib_mmi.multimesh != null and cc_hib_mmi.multimesh.mesh != null,
			"Cutlass Cay mounts HibiscusShrubs MultiMesh with procedural mesh")
		var grass_tris := _count_mesh_tris(cc_grass_mmi.multimesh.mesh) if (cc_grass_mmi != null and cc_grass_mmi.multimesh != null) else 0
		var fern_tris := _count_mesh_tris(cc_fern_mmi.multimesh.mesh) if (cc_fern_mmi != null and cc_fern_mmi.multimesh != null) else 0
		var hib_tris := _count_mesh_tris(cc_hib_mmi.multimesh.mesh) if (cc_hib_mmi != null and cc_hib_mmi.multimesh != null) else 0
		print("    wave_i11 botanical craft tris: grass=%d fern=%d hibiscus=%d" % [grass_tris, fern_tris, hib_tris])
		check(grass_tris >= 140,
			"Wave I-11 GrassClumps mesh must have >= 140 tris (slender 28-blade + seed-stalk tuft, got %d)" % grass_tris)
		check(fern_tris >= 200,
			"Wave I-11 JungleFerns mesh must have >= 200 tris (true pinnate serrated fern fronds, got %d)" % fern_tris)
		check(hib_tris >= 180,
			"Wave I-11 HibiscusShrubs mesh must have >= 180 tris (16-leaf layered shrub + 6 cupped blossoms, got %d)" % hib_tris)

		var cc_peb_mmi := cc_details.get_node_or_null(^"ShorePebblesShells") as MultiMeshInstance3D
		var cc_drift_mmi := cc_details.get_node_or_null(^"CoastalDriftwood") as MultiMeshInstance3D
		var cc_tidal_mmi := cc_details.get_node_or_null(^"TidalOutcrops") as MultiMeshInstance3D
		check(cc_peb_mmi != null and cc_peb_mmi.multimesh != null and cc_peb_mmi.multimesh.mesh != null,
			"Cutlass Cay mounts ShorePebblesShells MultiMesh with procedural mesh")
		check(cc_drift_mmi != null and cc_drift_mmi.multimesh != null and cc_drift_mmi.multimesh.mesh != null,
			"Cutlass Cay mounts CoastalDriftwood MultiMesh with procedural mesh")
		check(cc_tidal_mmi != null and cc_tidal_mmi.multimesh != null and cc_tidal_mmi.multimesh.mesh != null,
			"Cutlass Cay mounts TidalOutcrops MultiMesh with procedural mesh")
		var peb_tris := _count_mesh_tris(cc_peb_mmi.multimesh.mesh) if (cc_peb_mmi != null and cc_peb_mmi.multimesh != null) else 0
		var drift_tris := _count_mesh_tris(cc_drift_mmi.multimesh.mesh) if (cc_drift_mmi != null and cc_drift_mmi.multimesh != null) else 0
		var tidal_tris := _count_mesh_tris(cc_tidal_mmi.multimesh.mesh) if (cc_tidal_mmi != null and cc_tidal_mmi.multimesh != null) else 0
		print("    wave_i12 coastal micro-craft tris: pebbles_shells=%d driftwood=%d tidal_outcrops=%d" % [
			peb_tris, drift_tris, tidal_tris])
		check(peb_tris >= 180,
			"Wave I-12 ShorePebblesShells mesh must have >= 180 tris (cobbles + conch shell + 5-arm sea star, got %d)" % peb_tris)
		check(drift_tris >= 150,
			"Wave I-12 CoastalDriftwood mesh must have >= 150 tris (gnarled roots + kelp/barnacles, got %d)" % drift_tris)
		check(tidal_tris >= 150,
			"Wave I-12 TidalOutcrops mesh must have >= 150 tris (got %d)" % tidal_tris)

		var cc_bf_mmi := cc_details.get_node_or_null(^"IslandButterflies") as MultiMeshInstance3D
		var cc_crab_mmi := cc_details.get_node_or_null(^"ShoreCrabs") as MultiMeshInstance3D
		check(cc_bf_mmi != null and cc_bf_mmi.multimesh != null and cc_bf_mmi.multimesh.mesh != null,
			"Cutlass Cay mounts IslandButterflies MultiMesh with procedural mesh")
		check(cc_crab_mmi != null and cc_crab_mmi.multimesh != null and cc_crab_mmi.multimesh.mesh != null,
			"Cutlass Cay mounts ShoreCrabs MultiMesh with procedural mesh")
		var bf_tris := _count_mesh_tris(cc_bf_mmi.multimesh.mesh) if (cc_bf_mmi != null and cc_bf_mmi.multimesh != null) else 0
		var crab_tris := _count_mesh_tris(cc_crab_mmi.multimesh.mesh) if (cc_crab_mmi != null and cc_crab_mmi.multimesh != null) else 0
		var op_halo_mmi := op_details.get_node_or_null(^"LandmarkLanternHalos") as MultiMeshInstance3D if op_details != null else null
		var halo_tris := _count_mesh_tris(op_halo_mmi.multimesh.mesh) if (op_halo_mmi != null and op_halo_mmi.multimesh != null) else 0
		print("    wave_i14 fauna & halo craft tris: butterflies=%d crabs=%d lantern_halos=%d" % [
			bf_tris, crab_tris, halo_tris])
		check(bf_tris >= 44,
			"Wave I-14 IslandButterflies mesh must have >= 44 tris (sculpted swallowtail + thorax/abdomen/antennae, got %d)" % bf_tris)
		check(crab_tris >= 60,
			"Wave I-14 ShoreCrabs mesh must have >= 60 tris (beveled carapace + hinged pincers + walking legs + eyestalks, got %d)" % crab_tris)
		check(op_halo_mmi != null and op_halo_mmi.multimesh != null and op_halo_mmi.multimesh.mesh != null
			and not (op_halo_mmi.multimesh.mesh is PrimitiveMesh) and halo_tris >= 4,
			"Wave I-14 Port Scoundrel mounts LandmarkLanternHalos MultiMesh with sculpted non-PrimitiveMesh (tris=%d)" % halo_tris)

		var cc_stone_mmi := cc_details.get_node_or_null(^"TrailSteppingStones") as MultiMeshInstance3D
		check(cc_stone_mmi != null and cc_stone_mmi.multimesh != null and cc_stone_mmi.multimesh.mesh != null
			and not (cc_stone_mmi.multimesh.mesh is PrimitiveMesh),
			"Cutlass Cay mounts TrailSteppingStones MultiMesh with sculpted non-PrimitiveMesh")
		var stone_tris := _count_mesh_tris(cc_stone_mmi.multimesh.mesh) if (cc_stone_mmi != null and cc_stone_mmi.multimesh != null) else 0
		print("    wave_i15 trail masonry tris: stepping_stones=%d" % stone_tris)
		check(stone_tris >= 80,
			"Wave I-15 TrailSteppingStones mesh must have >= 80 tris (hand-chiseled flagstone + companion cobbles cluster, got %d)" % stone_tris)
		check(halo_tris >= 60,
			"Wave I-15 LandmarkLanternHalos mesh must have >= 60 tris (80-tri 16-gon 3-ring Gaussian billboard, got %d)" % halo_tris)

		var cc_pebbles := cc_details.get_placed_pebble_positions()
		var cc_trail_ctx := IslandDetailsCls._collect_trail_context(cutlass)
		check(bool(cc_trail_ctx.get("active", false)),
			"Cutlass Cay trail context must be active for shore pebble hygiene audit")
		var trail_pebble_violations := 0
		for pp_var in cc_pebbles:
			var pp: Vector3 = pp_var
			if IslandDetailsCls._is_on_trail(Vector2(pp.x, pp.z), cc_trail_ctx):
				trail_pebble_violations += 1
		print("    wave_i11 trail pebble hygiene (Cutlass Cay): %d pebble clusters checked, %d on-trail" % [
			cc_pebbles.size(), trail_pebble_violations])
		check(cc_pebbles.size() >= 1,
			"Cutlass Cay places >= 1 coastal shore pebble cluster (got %d)" % cc_pebbles.size())
		check_eq(trail_pebble_violations, 0,
			"Cutlass Cay shore pebbles must stay strictly outside walkable trail corridors (%d violations)" % trail_pebble_violations)

	if op_details != null:
		var op_halo_n: int = op_details.get_lantern_halo_count()
		check(op_halo_n >= 4,
			"Wave I-14 Port Scoundrel must batch >= 4 LandmarkLanternHalos (got %d)" % op_halo_n)
		var op_halo_node := op_details.get_node_or_null(^"LandmarkLanternHalos") as MultiMeshInstance3D
		check(op_halo_node != null, "Port Scoundrel mounts LandmarkLanternHalos MultiMesh")
		if op_halo_node != null:
			var prev_tod := Weather.time_of_day
			Weather.time_of_day = 11.0
			op_details._process(0.016)
			check(not op_halo_node.visible,
				"LandmarkLanternHalos must stay hidden during bright midday (tod=11.0)")
			Weather.time_of_day = 20.2
			op_details._process(0.016)
			check(op_halo_node.visible,
				"LandmarkLanternHalos must illuminate cleanly at dusk/night (tod=20.2)")
			Weather.time_of_day = prev_tod
			op_details._process(0.016)

	# 3. Zero-leak teardown: free all islands & details, await 2 physics frames, confirm all caches cleared!
	outpost.queue_free()
	cutlass.queue_free()
	await physics_frames(2)

	check_eq(IslandDetailsCls._active_details, 0,
		"all IslandDetails exited cleanly (_active_details == 0)")
	var leaked_fields := _collect_leaked_detail_caches()
	check(leaked_fields.is_empty(),
		"IslandDetails releases all static caches cleanly on teardown (leaked: %s)" % ", ".join(leaked_fields))


func test_wave_i2_full_14_island_archipelago_trails_landmarks_pbr_and_zero_leaks() -> void:
	_init_host()

	var archipelago := Archipelago.new()
	add_child(archipelago)
	await physics_frames(1)

	var all_islands := archipelago.get_islands()
	check_eq(all_islands.size(), 14, "full Archipelago builds all 14 islands")
	check_eq(IslandDetailsCls._active_details, 14,
		"all 14 Archipelago islands register live IslandDetails (_active_details=%d)" % IslandDetailsCls._active_details)

	var total_trail_markers := 0
	var total_trail_verts := 0
	var total_stepping_stones := 0
	var total_butterflies := 0
	var total_shore_crabs := 0
	var total_lantern_halos := 0
	var total_overhang_ledges := 0

	# 1. Verify EVERY island across all 14 carries batched IslandDetails, painted trails, stepping stones,
	#    tropical butterflies on lush islands, shore crabs on non-volcanic islands, twilight lantern halos,
	#    zero visible col_*, and zero flat CliffOverhangLedge shelves.
	for isl in all_islands:
		var details := isl.get_node_or_null(^"IslandDetails") as IslandDetails
		check(details != null, "island %s missing native IslandDetails child" % isl.island_id)
		var stone_n := 0
		var bf_n := 0
		var crab_n := 0
		var halo_n := 0
		if details != null:
			var dc := details.get_multimesh_count()
			var inst_n := details.get_total_instance_count()
			check(dc >= 5 and dc <= 12,
				"island %s IslandDetails draw calls must be 5..12 (got %d)" % [isl.island_id, dc])
			check(inst_n >= 200,
				"island %s IslandDetails total instance count must be >= 200 (got %d)" % [isl.island_id, inst_n])

			var prim_count := 0
			for n in details.find_children("*", "MultiMeshInstance3D", true, false):
				var mmi := n as MultiMeshInstance3D
				if mmi != null and mmi.multimesh != null and mmi.multimesh.mesh is PrimitiveMesh:
					prim_count += 1
			for n in details.find_children("*", "MeshInstance3D", true, false):
				var mi := n as MeshInstance3D
				if mi != null and mi.mesh is PrimitiveMesh:
					prim_count += 1
			check_eq(prim_count, 0, "island %s IslandDetails has zero PrimitiveMeshes" % isl.island_id)

			stone_n = details.get_stepping_stone_count()
			bf_n = details.get_butterfly_count()
			crab_n = details.get_shore_crab_count()
			halo_n = details.get_lantern_halo_count()
			total_stepping_stones += stone_n
			total_butterflies += bf_n
			total_shore_crabs += crab_n
			total_lantern_halos += halo_n
			var min_stones := 4 if isl.archetype == &"sea_stack" else 10
			check(stone_n >= min_stones,
				"island %s TrailSteppingStones count must be >= %d (got %d)" % [isl.island_id, min_stones, stone_n])
			var stone_mmi := details.get_node_or_null(^"TrailSteppingStones") as MultiMeshInstance3D
			check(stone_mmi != null and stone_mmi.multimesh != null and stone_mmi.multimesh.mesh != null
				and not (stone_mmi.multimesh.mesh is PrimitiveMesh),
				"island %s TrailSteppingStones MultiMesh uses sculpted non-PrimitiveMesh" % isl.island_id)

			if isl.archetype != &"volcano_crag" and isl.archetype != &"sea_stack":
				check(bf_n >= 12,
					"lush island %s IslandButterflies count must be >= 12 (got %d)" % [isl.island_id, bf_n])
				var bf_mmi := details.get_node_or_null(^"IslandButterflies") as MultiMeshInstance3D
				check(bf_mmi != null and bf_mmi.multimesh != null and bf_mmi.multimesh.mesh != null
					and not (bf_mmi.multimesh.mesh is PrimitiveMesh),
					"lush island %s IslandButterflies MultiMesh uses sculpted non-PrimitiveMesh" % isl.island_id)

			if isl.archetype != &"volcano_crag":
				check(crab_n >= 8,
					"non-volcanic island %s ShoreCrabs count must be >= 8 (got %d)" % [isl.island_id, crab_n])
				var crab_mmi := details.get_node_or_null(^"ShoreCrabs") as MultiMeshInstance3D
				check(crab_mmi != null and crab_mmi.multimesh != null and crab_mmi.multimesh.mesh != null
					and not (crab_mmi.multimesh.mesh is PrimitiveMesh),
					"non-volcanic island %s ShoreCrabs MultiMesh uses sculpted non-PrimitiveMesh" % isl.island_id)

			if halo_n > 0:
				var halo_mmi := details.get_node_or_null(^"LandmarkLanternHalos") as MultiMeshInstance3D
				check(halo_mmi != null and halo_mmi.multimesh != null and halo_mmi.multimesh.mesh != null
					and not (halo_mmi.multimesh.mesh is PrimitiveMesh),
					"island %s LandmarkLanternHalos MultiMesh uses sculpted non-PrimitiveMesh" % isl.island_id)

		# Verify painted walkable trail vertices in TerrainMesh ARRAY_COLOR (1.0 - COLOR.a).
		var terrain_mi := isl.get_node_or_null(^"TerrainMesh") as MeshInstance3D
		check(terrain_mi != null and terrain_mi.mesh != null,
			"island %s missing TerrainMesh" % isl.island_id)
		var trail_vert_count := 0
		if terrain_mi != null and terrain_mi.mesh != null and terrain_mi.mesh.get_surface_count() > 0:
			var surf_arrays := terrain_mi.mesh.surface_get_arrays(0)
			var cols_var: Variant = surf_arrays[Mesh.ARRAY_COLOR] if not surf_arrays.is_empty() else null
			if cols_var is PackedColorArray:
				for c: Color in cols_var as PackedColorArray:
					if c.a < 0.75:
						trail_vert_count += 1
		total_trail_verts += trail_vert_count
		check(trail_vert_count >= 18,
			"island %s TerrainMesh must have >= 18 painted trail vertices (c.a < 0.75, got %d)" % [
				isl.island_id, trail_vert_count])

		# Verify ZERO visible col_* collider meshes anywhere on the island.
		var visible_cols := 0
		for c_node in isl.find_children("col_*", "MeshInstance3D", true, false):
			var c_mi := c_node as MeshInstance3D
			if c_mi != null and c_mi.visible:
				visible_cols += 1
		check_eq(visible_cols, 0,
			"island %s has %d visible col_* collider mesh(es)" % [isl.island_id, visible_cols])

		var overhang_n := isl.find_children("CliffOverhangLedge*", "Node3D", true, false).size()
		total_overhang_ledges += overhang_n

		var lanterns := isl.find_children("TrailLantern*", "Node3D", true, false).size()
		var cairns := isl.find_children("StoneCairn*", "Node3D", true, false).size()
		total_trail_markers += lanterns + cairns

		print("    arch14  %-20s r=%5.1fm  trail_v=%4d  markers=%2d (L=%d C=%d)  stone=%2d  bf=%2d  crab=%2d  halo=%2d  det=%4d" % [
			isl.island_id, isl.island_radius, trail_vert_count, lanterns + cairns, lanterns, cairns,
			stone_n, bf_n, crab_n, halo_n, details.get_total_instance_count() if details != null else 0])

	check(total_trail_markers >= 20,
		"archipelago must place >= 20 trail storytelling markers (TrailLantern*/StoneCairn*, got %d)" % total_trail_markers)
	check(total_trail_verts >= 1000,
		"Wave I-8 wider trails: total painted trail vertices across 14 islands must be >= 1000 (got %d)" % total_trail_verts)
	check(total_stepping_stones >= 400,
		"Wave I-8 stepping stones: total sculpted stepping stones across 14 islands must be >= 400 (got %d)" % total_stepping_stones)
	check(total_shore_crabs >= 160,
		"Wave I-9 shore crabs: total sculpted ShoreCrabs across 14 islands must be >= 160 (got %d)" % total_shore_crabs)
	check_eq(total_overhang_ledges, 0,
		"Wave I-8 full overhang sweep: zero CliffOverhangLedge* flat shelves across all 14 live islands (got %d)" % total_overhang_ledges)

	# Verify Wave I-8 living tropical butterflies day/night hiding, Wave I-9 shore crabs storm-hiding
	# & Wave I-14 LandmarkLanternHalos midday-hiding / twilight-illumination contract.
	var port_isl := archipelago.get_island_by_id("port_scoundrel")
	check(port_isl != null, "Port Scoundrel exists in Archipelago")
	if port_isl != null:
		var port_details := port_isl.get_node_or_null(^"IslandDetails") as IslandDetails
		var port_bf_mmi := port_details.get_node_or_null(^"IslandButterflies") as MultiMeshInstance3D if port_details != null else null
		check(port_details != null and port_bf_mmi != null,
			"Port Scoundrel mounts IslandButterflies MultiMesh for day/night cycle contract")
		if port_details != null and port_bf_mmi != null:
			var prev_storm := Weather.storminess
			Weather.time_of_day = 11.0
			Weather.storminess = 0.0
			port_details._process(0.25)
			check(port_bf_mmi.visible,
				"IslandButterflies must be visible during calm daytime (tod=11.0, storm=0.0)")
			Weather.time_of_day = 0.5
			port_details._process(0.25)
			check(not port_bf_mmi.visible,
				"IslandButterflies must hide cleanly to sleep at night (tod=0.5)")
			Weather.time_of_day = 11.0
			Weather.storminess = prev_storm
			port_details._process(0.25)

		var port_crab_mmi := port_details.get_node_or_null(^"ShoreCrabs") as MultiMeshInstance3D if port_details != null else null
		check(port_details != null and port_crab_mmi != null,
			"Port Scoundrel mounts ShoreCrabs MultiMesh for storm-hiding contract")
		if port_details != null and port_crab_mmi != null:
			var prev_storm_c := Weather.storminess
			Weather.storminess = 0.85
			port_details._process(0.25)
			check(not port_crab_mmi.visible,
				"ShoreCrabs must hide cleanly during heavy storms (storm=0.85)")
			Weather.storminess = 0.0
			port_details._process(0.25)
			check(port_crab_mmi.visible,
				"ShoreCrabs must re-emerge cleanly once storm clears (storm=0.0)")
			Weather.storminess = prev_storm_c
			port_details._process(0.25)

		var port_halo_mmi := port_details.get_node_or_null(^"LandmarkLanternHalos") as MultiMeshInstance3D if port_details != null else null
		check(port_details != null and port_halo_mmi != null,
			"Port Scoundrel mounts LandmarkLanternHalos MultiMesh for twilight visibility contract")
		if port_details != null and port_halo_mmi != null:
			check(port_details.get_lantern_halo_count() >= 4,
				"Port Scoundrel batches >= 4 LandmarkLanternHalos (got %d)" % port_details.get_lantern_halo_count())
			var prev_tod_h := Weather.time_of_day
			Weather.time_of_day = 11.0
			port_details._process(0.016)
			check(not port_halo_mmi.visible,
				"LandmarkLanternHalos must stay hidden during bright midday (tod=11.0)")
			Weather.time_of_day = 20.2
			port_details._process(0.016)
			check(port_halo_mmi.visible,
				"LandmarkLanternHalos must illuminate cleanly at dusk/night (tod=20.2)")
			Weather.time_of_day = prev_tod_h
			port_details._process(0.016)

	print("    wave_i8 pass_iq1: trail_verts=%d stepping_stones=%d butterflies=%d overhang_shelves=%d" % [
		total_trail_verts, total_stepping_stones, total_butterflies, total_overhang_ledges])

	# 2. Verify bespoke Wave I-2 signature 3D landmarks spawned on their assigned islands!
	var skull_isl := archipelago.get_island_by_id("skull_bluff")
	check(skull_isl != null, "Skull Bluff exists in Archipelago")
	if skull_isl != null:
		var skull_carving := skull_isl.find_child("SkullCliffCarving*", true, false) as Node3D
		check(skull_carving != null, "Skull Bluff spawns SkullCliffCarving landmark")
		if skull_carving != null:
			var eye_lights := skull_carving.find_children("*", "OmniLight3D", true, false)
			check(eye_lights.size() >= 2,
				"SkullCliffCarving mounts >= 2 glowing eye OmniLight3Ds (got %d)" % eye_lights.size())

	var emerald_isl := archipelago.get_island_by_id("emerald_spire")
	check(emerald_isl != null, "Emerald Spire exists in Archipelago")
	if emerald_isl != null:
		var stairs_e := emerald_isl.find_children("TempleStairway*", "Node3D", true, false)
		check(stairs_e.size() >= 1,
			"Emerald Spire spawns >= 1 TempleStairway* landmark (got %d)" % stairs_e.size())

	var sov_isl := archipelago.get_island_by_id("sovereigns_bastion")
	check(sov_isl != null, "Sovereign's Bastion exists in Archipelago")
	if sov_isl != null:
		var stairs_s := sov_isl.find_children("TempleStairway*", "Node3D", true, false)
		check(stairs_s.size() >= 2,
			"Sovereign's Bastion spawns >= 2 TempleStairway* landmarks (got %d)" % stairs_s.size())

	var gal_isl := archipelago.get_island_by_id("galleons_reach")
	check(gal_isl != null, "Galleon's Reach exists in Archipelago")
	if gal_isl != null:
		var catwalks_g := gal_isl.find_children("CliffCatwalk*", "Node3D", true, false)
		var stairs_g := gal_isl.find_children("TempleStairway*", "Node3D", true, false)
		check(catwalks_g.size() >= 2,
			"Galleon's Reach spawns >= 2 CliffCatwalk* landmarks (got %d)" % catwalks_g.size())
		check(stairs_g.size() >= 1,
			"Galleon's Reach spawns >= 1 TempleStairway* landmark (got %d)" % stairs_g.size())

	var smug_isl := archipelago.get_island_by_id("smugglers_cove")
	check(smug_isl != null, "Smuggler's Cove exists in Archipelago")
	if smug_isl != null:
		var catwalks_sm := smug_isl.find_children("CliffCatwalk*", "Node3D", true, false)
		check(catwalks_sm.size() >= 1,
			"Smuggler's Cove spawns >= 1 CliffCatwalk* landmark (got %d)" % catwalks_sm.size())

	var barn_isl := archipelago.get_island_by_id("barnacle_haven")
	check(barn_isl != null, "Barnacle Haven exists in Archipelago")
	if barn_isl != null:
		var arches_b := barn_isl.find_children("CoastalSeaArch*", "Node3D", true, false)
		var catwalks_b := barn_isl.find_children("CliffCatwalk*", "Node3D", true, false)
		check(arches_b.size() >= 1,
			"Barnacle Haven spawns >= 1 CoastalSeaArch* landmark (got %d)" % arches_b.size())
		check(catwalks_b.size() >= 1,
			"Barnacle Haven spawns >= 1 CliffCatwalk* landmark (got %d)" % catwalks_b.size())

	var gulls_isl := archipelago.get_island_by_id("gulls_arch")
	check(gulls_isl != null, "Gull's Arch exists in Archipelago")
	if gulls_isl != null:
		var arches_gu := gulls_isl.find_children("CoastalSeaArch*", "Node3D", true, false)
		check(arches_gu.size() >= 1,
			"Gull's Arch spawns >= 1 CoastalSeaArch* landmark (got %d)" % arches_gu.size())
		check(gulls_isl.find_child("SeaArch_Main", true, false) == null,
			"Gull's Arch skips legacy SeaArch_Main when PBR coastal_sea_arch.glb exists")

	for wreck_id: String in ["wreckers_shoal", "sirens_tooth", "crescent_atoll"]:
		var w_isl := archipelago.get_island_by_id(wreck_id)
		check(w_isl != null, "%s exists in Archipelago" % wreck_id)
		if w_isl != null:
			var wrecks := w_isl.find_children("ImpaledShipwreck*", "Node3D", true, false)
			check(wrecks.size() >= 1,
				"%s spawns >= 1 ImpaledShipwreck* landmark (got %d)" % [wreck_id, wrecks.size()])

	var cinder_isl := archipelago.get_island_by_id("cinder_crag")
	check(cinder_isl != null, "Cinder Crag exists in Archipelago")
	if cinder_isl != null:
		var spires_c := cinder_isl.find_children("VolcanicBasaltSpire*", "Node3D", true, false)
		check(spires_c.size() >= 4,
			"Cinder Crag spawns >= 4 VolcanicBasaltSpire* landmarks (got %d)" % spires_c.size())
		var varch_c := cinder_isl.find_children("VolcanicObsidianArch*", "Node3D", true, false)
		check(varch_c.size() >= 1,
			"Cinder Crag spawns >= 1 VolcanicObsidianArch* portal landmark (got %d)" % varch_c.size())

	# 2b. Verify Wave I-3 storytelling landmarks across the 14-island archipelago + triplanar PBR vaults!
	var idol_total := 0
	var ribcage_total := 0
	var rowboat_total := 0
	var gibbet_total := 0
	var brazier_total := 0
	for isl_i3 in all_islands:
		idol_total += isl_i3.find_children("SeaGodIdol*", "Node3D", true, false).size()
		ribcage_total += isl_i3.find_children("LeviathanRibcage*", "Node3D", true, false).size()
		rowboat_total += isl_i3.find_children("BeachedRowboat*", "Node3D", true, false).size()
		gibbet_total += isl_i3.find_children("PirateGibbet*", "Node3D", true, false).size()
		brazier_total += isl_i3.find_children("SignalBrazier*", "Node3D", true, false).size()
	print("    wave_i3 storytelling landmarks: idols=%d ribcages=%d rowboats=%d gibbets=%d braziers=%d" % [
		idol_total, ribcage_total, rowboat_total, gibbet_total, brazier_total])
	check(idol_total >= 3, "Wave I-3 spawns >= 3 SeaGodIdol* landmarks (got %d)" % idol_total)
	check(ribcage_total >= 3, "Wave I-3 spawns >= 3 LeviathanRibcage* landmarks (got %d)" % ribcage_total)
	check(rowboat_total >= 4, "Wave I-3 spawns >= 4 BeachedRowboat* landmarks (got %d)" % rowboat_total)
	check(gibbet_total >= 3, "Wave I-3 spawns >= 3 PirateGibbet* landmarks (got %d)" % gibbet_total)
	check(brazier_total >= 5, "Wave I-3 spawns >= 5 SignalBrazier* landmarks (got %d)" % brazier_total)

	# 2c. Verify Wave I-4 upper-mountain skyline landmarks across Tier 2-4 islands!
	var crag_total := 0
	var aqueduct_total := 0
	var watchpost_total := 0
	var strata_total := 0
	for isl_i4 in all_islands:
		crag_total += isl_i4.find_children("SummitCrag*", "Node3D", true, false).size()
		aqueduct_total += isl_i4.find_children("RuinAqueduct*", "Node3D", true, false).size()
		watchpost_total += isl_i4.find_children("PirateWatchpost*", "Node3D", true, false).size()
		strata_total += isl_i4.find_children("UpperStrataRib*", "Node3D", true, false).size()
	print("    wave_i4 skyline landmarks: crags=%d aqueducts=%d watchposts=%d strata_ribs=%d" % [
		crag_total, aqueduct_total, watchpost_total, strata_total])
	check(crag_total >= 8, "Wave I-4 spawns >= 8 SummitCrag* landmarks (got %d)" % crag_total)
	check(aqueduct_total >= 4, "Wave I-4 spawns >= 4 RuinAqueduct* landmarks (got %d)" % aqueduct_total)
	check(watchpost_total >= 6, "Wave I-4 spawns >= 6 PirateWatchpost* landmarks (got %d)" % watchpost_total)
	check(strata_total >= 14, "Wave I-4 spawns >= 14 UpperStrataRib* landmarks (got %d)" % strata_total)

	# 2d. Verify Wave I-5 coastal, reef & volcanic caldera landmarks across the 14-island archipelago!
	var camp_total := 0
	var stern_total := 0
	var coral_arch_total := 0
	var lava_shrine_total := 0
	for isl_i5 in all_islands:
		camp_total += isl_i5.find_children("PirateCamp_*", "Node3D", true, false).size()
		stern_total += isl_i5.find_children("SunkenStern_*", "Node3D", true, false).size()
		coral_arch_total += isl_i5.find_children("TidalCoralArch_*", "Node3D", true, false).size()
		lava_shrine_total += isl_i5.find_children("LavaCauldronShrine_*", "Node3D", true, false).size()
	var cinder_shrines := 0
	if cinder_isl != null:
		cinder_shrines = cinder_isl.find_children("LavaCauldronShrine_*", "Node3D", true, false).size()
	print("    wave_i5 coastal/reef landmarks: camps=%d sterns=%d coral_arches=%d lava_shrines=%d" % [
		camp_total, stern_total, coral_arch_total, lava_shrine_total])
	check(camp_total >= 4, "Wave I-5 spawns >= 4 PirateCamp_* landmarks (got %d)" % camp_total)
	check(stern_total >= 3, "Wave I-5 spawns >= 3 SunkenStern_* landmarks (got %d)" % stern_total)
	check(coral_arch_total >= 4, "Wave I-5 spawns >= 4 TidalCoralArch_* landmarks (got %d)" % coral_arch_total)
	check(cinder_shrines >= 2, "Cinder Crag spawns >= 2 LavaCauldronShrine_* landmarks (got %d)" % cinder_shrines)

	# 2e. Verify Wave I-6 harbour, jungle ruin, waterfall shrine & smuggler hoard landmarks!
	var crane_total := 0
	var altar_total := 0
	var wf_shrine_total := 0
	var hoard_total := 0
	for isl_i6 in all_islands:
		crane_total += isl_i6.find_children("HarbourCrane_*", "Node3D", true, false).size()
		altar_total += isl_i6.find_children("JungleAltar_*", "Node3D", true, false).size()
		wf_shrine_total += isl_i6.find_children("CascadeShrine_*", "Node3D", true, false).size()
		hoard_total += isl_i6.find_children("SmugglerHoard_*", "Node3D", true, false).size()
	print("    wave_i6 harbour/ruins landmarks: cranes=%d altars=%d cascade_shrines=%d hoards=%d" % [
		crane_total, altar_total, wf_shrine_total, hoard_total])
	check(crane_total >= 3, "Wave I-6 spawns >= 3 HarbourCrane_* landmarks (got %d)" % crane_total)
	check(altar_total >= 3, "Wave I-6 spawns >= 3 JungleAltar_* landmarks (got %d)" % altar_total)
	check(wf_shrine_total >= 3, "Wave I-6 spawns >= 3 CascadeShrine_* landmarks (got %d)" % wf_shrine_total)
	check(hoard_total >= 4, "Wave I-6 spawns >= 4 SmugglerHoard_* landmarks (got %d)" % hoard_total)
	if emerald_isl != null:
		var wf_match := emerald_isl.find_child("*Waterfall*", true, false)
		check(wf_match is IslandWaterfall,
			"Emerald Spire find_child('*Waterfall*') resolves to IslandWaterfall (got %s)" % (
				String(wf_match.name) if wf_match != null else "null"))

	# 2f. Verify Wave I-7 maritime watchtower, reef beacon, compass monolith & volcanic chain pylon landmarks!
	var watchtower_total := 0
	var reef_beacon_total := 0
	var monolith_total := 0
	var chain_pylon_total := 0
	for isl_i7 in all_islands:
		watchtower_total += isl_i7.find_children("FortWatchtower_*", "Node3D", true, false).size()
		reef_beacon_total += isl_i7.find_children("ReefBeacon_*", "Node3D", true, false).size()
		monolith_total += isl_i7.find_children("CompassMonolith_*", "Node3D", true, false).size()
		chain_pylon_total += isl_i7.find_children("VolcanicChainPylon_*", "Node3D", true, false).size()
	print("    wave_i7 maritime/relic landmarks: watchtowers=%d reef_beacons=%d monoliths=%d chain_pylons=%d" % [
		watchtower_total, reef_beacon_total, monolith_total, chain_pylon_total])
	check(watchtower_total >= 3, "Wave I-7 spawns >= 3 FortWatchtower_* landmarks (got %d)" % watchtower_total)
	check(reef_beacon_total >= 4, "Wave I-7 spawns >= 4 ReefBeacon_* landmarks (got %d)" % reef_beacon_total)
	check(monolith_total >= 3, "Wave I-7 spawns >= 3 CompassMonolith_* landmarks (got %d)" % monolith_total)
	check(chain_pylon_total >= 3, "Wave I-7 spawns >= 3 VolcanicChainPylon_* landmarks (got %d)" % chain_pylon_total)

	# 2g. Verify Wave I-9 world-craft landmarks (careening ship drydock, skeleton throne shrine,
	#     tropical fishing stilts hut & ancient astronomer orrery) + living shore crabs!
	var drydock_total := 0
	var throne_total := 0
	var fish_hut_total := 0
	var orrery_total := 0
	for isl_i9 in all_islands:
		drydock_total += isl_i9.find_children("ShipDrydock_*", "Node3D", true, false).size()
		throne_total += isl_i9.find_children("SkeletonThrone_*", "Node3D", true, false).size()
		fish_hut_total += isl_i9.find_children("FishingHut_*", "Node3D", true, false).size()
		orrery_total += isl_i9.find_children("AstronomerOrrery_*", "Node3D", true, false).size()
	print("    wave_i9 world_craft landmarks: drydocks=%d thrones=%d fish_huts=%d orreries=%d shore_crabs=%d" % [
		drydock_total, throne_total, fish_hut_total, orrery_total, total_shore_crabs])
	check(drydock_total >= 3, "Wave I-9 spawns >= 3 ShipDrydock_* landmarks (got %d)" % drydock_total)
	check(throne_total >= 3, "Wave I-9 spawns >= 3 SkeletonThrone_* landmarks (got %d)" % throne_total)
	check(fish_hut_total >= 4, "Wave I-9 spawns >= 4 FishingHut_* landmarks (got %d)" % fish_hut_total)
	check(orrery_total >= 3, "Wave I-9 spawns >= 3 AstronomerOrrery_* landmarks (got %d)" % orrery_total)

	# 2h. Verify Wave I-10 on-foot craft landmarks (coastal smuggler jetty, ancient ruined obelisk gate,
	#     wooden trail footbridge & pirate lookout bell frame)!
	var jetty_total := 0
	var obelisk_gate_total := 0
	var footbridge_total := 0
	var lookout_bell_total := 0
	for isl_i10 in all_islands:
		jetty_total += isl_i10.find_children("SmugglerJetty_*", "Node3D", true, false).size()
		obelisk_gate_total += isl_i10.find_children("ObeliskGate_*", "Node3D", true, false).size()
		footbridge_total += isl_i10.find_children("TrailFootbridge_*", "Node3D", true, false).size()
		lookout_bell_total += isl_i10.find_children("LookoutBell_*", "Node3D", true, false).size()
	print("    wave_i10 onfoot_craft landmarks: jetties=%d obelisk_gates=%d footbridges=%d lookout_bells=%d" % [
		jetty_total, obelisk_gate_total, footbridge_total, lookout_bell_total])
	check(jetty_total >= 4, "Wave I-10 spawns >= 4 SmugglerJetty_* landmarks (got %d)" % jetty_total)
	check(obelisk_gate_total >= 3, "Wave I-10 spawns >= 3 ObeliskGate_* landmarks (got %d)" % obelisk_gate_total)
	check(footbridge_total >= 3, "Wave I-10 spawns >= 3 TrailFootbridge_* landmarks (got %d)" % footbridge_total)
	check(lookout_bell_total >= 4, "Wave I-10 spawns >= 4 LookoutBell_* landmarks (got %d)" % lookout_bell_total)

	# 2h-2. Verify Wave I-11 story-craft landmarks (pirate tavern supply cart, sunken anchor memorial,
	#       ancient sun-dial plaza & volcanic obsidian fissure vent) + MID_RANGE_FILES LOD cap!
	var supply_cart_total := 0
	var anchor_memorial_total := 0
	var sundial_plaza_total := 0
	var obsidian_vent_total := 0
	for isl_i11 in all_islands:
		supply_cart_total += isl_i11.find_children("SupplyCart_*", "Node3D", true, false).size()
		anchor_memorial_total += isl_i11.find_children("AnchorMemorial_*", "Node3D", true, false).size()
		sundial_plaza_total += isl_i11.find_children("SundialPlaza_*", "Node3D", true, false).size()
		obsidian_vent_total += isl_i11.find_children("ObsidianVent_*", "Node3D", true, false).size()
	print("    wave_i11 story_craft landmarks: carts=%d anchors=%d sundials=%d vents=%d" % [
		supply_cart_total, anchor_memorial_total, sundial_plaza_total, obsidian_vent_total])
	check(supply_cart_total >= 4, "Wave I-11 spawns >= 4 SupplyCart_* landmarks (got %d)" % supply_cart_total)
	check(anchor_memorial_total >= 4, "Wave I-11 spawns >= 4 AnchorMemorial_* landmarks (got %d)" % anchor_memorial_total)
	check(sundial_plaza_total >= 3, "Wave I-11 spawns >= 3 SundialPlaza_* landmarks (got %d)" % sundial_plaza_total)
	check(obsidian_vent_total >= 3, "Wave I-11 spawns >= 3 ObsidianVent_* landmarks (got %d)" % obsidian_vent_total)
	for sc_glb in STORY_CRAFT_LANDMARKS:
		check(IslandLandmarks.MID_RANGE_FILES.has(sc_glb),
			"Wave I-11 landmark %s must be registered in IslandLandmarks.MID_RANGE_FILES (< 0.45 ms offshore GPU cap)" % sc_glb)

	# 2h-3. Verify Wave I-12 (50-Landmark Milestone) fort/vault landmarks (stone well courtyard,
	#       ruined sea-fort cannon bastion, pirate treasure vault door & shipwreck crow's-nest mast)
	#       + MID_RANGE_FILES & VIS_RANGE_MID <= 400 m offshore LOD cap!
	var stone_well_total := 0
	var cannon_bastion_total := 0
	var treasure_vault_total := 0
	var crow_nest_mast_total := 0
	for isl_i12 in all_islands:
		stone_well_total += isl_i12.find_children("StoneWell_*", "Node3D", true, false).size()
		cannon_bastion_total += isl_i12.find_children("CannonBastion_*", "Node3D", true, false).size()
		treasure_vault_total += isl_i12.find_children("TreasureVault_*", "Node3D", true, false).size()
		crow_nest_mast_total += isl_i12.find_children("CrowNestMast_*", "Node3D", true, false).size()
	print("    wave_i12 fort_vault landmarks: wells=%d bastions=%d vaults=%d crow_nests=%d" % [
		stone_well_total, cannon_bastion_total, treasure_vault_total, crow_nest_mast_total])
	check(stone_well_total >= 4, "Wave I-12 spawns >= 4 StoneWell_* landmarks (got %d)" % stone_well_total)
	check(cannon_bastion_total >= 4, "Wave I-12 spawns >= 4 CannonBastion_* landmarks (got %d)" % cannon_bastion_total)
	check(treasure_vault_total >= 3, "Wave I-12 spawns >= 3 TreasureVault_* landmarks (got %d)" % treasure_vault_total)
	check(crow_nest_mast_total >= 4, "Wave I-12 spawns >= 4 CrowNestMast_* landmarks (got %d)" % crow_nest_mast_total)
	check(IslandLandmarks.VIS_RANGE_MID <= 400.0,
		"IslandLandmarks.VIS_RANGE_MID must be <= 400.0 m (got %.1f m)" % IslandLandmarks.VIS_RANGE_MID)
	for fv_glb in FORT_VAULT_LANDMARKS:
		check(IslandLandmarks.MID_RANGE_FILES.has(fv_glb),
			"Wave I-12 landmark %s must be registered in IslandLandmarks.MID_RANGE_FILES (<= 400 m offshore LOD cap)" % fv_glb)

	# 2h-4. Verify Wave I-13 (54-Landmark Island-Lore Milestone) landmarks (pirate rum distillery shack,
	#       ancient jade serpent totem, coastal driftwood arch camp & volcanic obsidian bridge ruin)
	#       + MID_RANGE_FILES offshore LOD cap!
	var rum_distillery_total := 0
	var serpent_totem_total := 0
	var driftwood_camp_total := 0
	var volcanic_bridge_total := 0
	for isl_i13 in all_islands:
		rum_distillery_total += isl_i13.find_children("RumDistillery_*", "Node3D", true, false).size()
		serpent_totem_total += isl_i13.find_children("SerpentTotem_*", "Node3D", true, false).size()
		driftwood_camp_total += isl_i13.find_children("DriftwoodCamp_*", "Node3D", true, false).size()
		volcanic_bridge_total += isl_i13.find_children("VolcanicBridgeRuin_*", "Node3D", true, false).size()
	print("    wave_i13 island_lore landmarks: distilleries=%d serptotems=%d driftwood_camps=%d volc_bridges=%d" % [
		rum_distillery_total, serpent_totem_total, driftwood_camp_total, volcanic_bridge_total])
	check(rum_distillery_total >= 4, "Wave I-13 spawns >= 4 RumDistillery_* landmarks (got %d)" % rum_distillery_total)
	check(serpent_totem_total >= 4, "Wave I-13 spawns >= 4 SerpentTotem_* landmarks (got %d)" % serpent_totem_total)
	check(driftwood_camp_total >= 4, "Wave I-13 spawns >= 4 DriftwoodCamp_* landmarks (got %d)" % driftwood_camp_total)
	check(volcanic_bridge_total >= 3, "Wave I-13 spawns >= 3 VolcanicBridgeRuin_* landmarks (got %d)" % volcanic_bridge_total)
	for il_glb in ISLAND_LORE_LANDMARKS:
		check(IslandLandmarks.MID_RANGE_FILES.has(il_glb),
			"Wave I-13 landmark %s must be registered in IslandLandmarks.MID_RANGE_FILES (<= 400 m offshore LOD cap)" % il_glb)

	# 2h-5. Verify Wave I-14 (58-Landmark Nautical-Craft & Twilight Lantern Halo Milestone) landmarks
	#       (coastal rope ferry pulley, ancient sunken bell shrine, pirate map planning table tent &
	#       volcanic basalt obelisk brazier) + MID_RANGE_FILES (VIS_RANGE_MID <= 300 m) & batched LandmarkLanternHalos!
	var ferry_winch_total := 0
	var bell_shrine_total := 0
	var map_tent_total := 0
	var basalt_brazier_total := 0
	for isl_i14 in all_islands:
		ferry_winch_total += isl_i14.find_children("FerryWinch_*", "Node3D", true, false).size()
		bell_shrine_total += isl_i14.find_children("BellShrine_*", "Node3D", true, false).size()
		map_tent_total += isl_i14.find_children("MapTent_*", "Node3D", true, false).size()
		basalt_brazier_total += isl_i14.find_children("BasaltBrazier_*", "Node3D", true, false).size()
	print("    wave_i14 nautical_craft landmarks: ferry_winches=%d bell_shrines=%d map_tents=%d basalt_braziers=%d lantern_halos=%d" % [
		ferry_winch_total, bell_shrine_total, map_tent_total, basalt_brazier_total, total_lantern_halos])
	check(ferry_winch_total >= 4, "Wave I-14 spawns >= 4 FerryWinch_* landmarks (got %d)" % ferry_winch_total)
	check(bell_shrine_total >= 4, "Wave I-14 spawns >= 4 BellShrine_* landmarks (got %d)" % bell_shrine_total)
	check(map_tent_total >= 4, "Wave I-14 spawns >= 4 MapTent_* landmarks (got %d)" % map_tent_total)
	check(basalt_brazier_total >= 3, "Wave I-14 spawns >= 3 BasaltBrazier_* landmarks (got %d)" % basalt_brazier_total)
	check(total_lantern_halos >= 120,
		"Wave I-14 archipelago must batch >= 120 twilight LandmarkLanternHalos across 14 islands (got %d)" % total_lantern_halos)
	check(IslandLandmarks.VIS_RANGE_MID <= 300.0,
		"IslandLandmarks.VIS_RANGE_MID must be <= 300.0 m (got %.1f m)" % IslandLandmarks.VIS_RANGE_MID)
	for nc_glb in NAUTICAL_CRAFT_LANDMARKS:
		check(IslandLandmarks.MID_RANGE_FILES.has(nc_glb),
			"Wave I-14 landmark %s must be registered in IslandLandmarks.MID_RANGE_FILES (<= 300 m offshore LOD cap)" % nc_glb)

	# 2h-6. Verify Wave I-15 (62-Landmark Sea-Lore Milestone) landmarks (pirate shipwright timber rack,
	#       ancient tidal obelisk mirror, smuggler rope cargo hoist & volcanic obsidian forge anvil)
	#       + MID_RANGE_FILES (VIS_RANGE_MID <= 300 m) & expanded twilight LandmarkLanternHalos!
	var shipyard_rack_total := 0
	var mirror_shrine_total := 0
	var smuggler_hoist_total := 0
	var volc_forge_total := 0
	for isl_i15 in all_islands:
		shipyard_rack_total += isl_i15.find_children("ShipyardRack_*", "Node3D", true, false).size()
		mirror_shrine_total += isl_i15.find_children("MirrorShrine_*", "Node3D", true, false).size()
		smuggler_hoist_total += isl_i15.find_children("SmugglerHoist_*", "Node3D", true, false).size()
		volc_forge_total += isl_i15.find_children("VolcForge_*", "Node3D", true, false).size()
	print("    wave_i15 sea_lore landmarks: shipyard_racks=%d mirror_shrines=%d smuggler_hoists=%d volc_forges=%d lantern_halos=%d" % [
		shipyard_rack_total, mirror_shrine_total, smuggler_hoist_total, volc_forge_total, total_lantern_halos])
	check(shipyard_rack_total >= 4, "Wave I-15 spawns >= 4 ShipyardRack_* landmarks (got %d)" % shipyard_rack_total)
	check(mirror_shrine_total >= 4, "Wave I-15 spawns >= 4 MirrorShrine_* landmarks (got %d)" % mirror_shrine_total)
	check(smuggler_hoist_total >= 4, "Wave I-15 spawns >= 4 SmugglerHoist_* landmarks (got %d)" % smuggler_hoist_total)
	check(volc_forge_total >= 3, "Wave I-15 spawns >= 3 VolcForge_* landmarks (got %d)" % volc_forge_total)
	check(total_lantern_halos >= 140,
		"Wave I-15 archipelago must batch >= 140 twilight LandmarkLanternHalos across 14 islands (got %d)" % total_lantern_halos)
	check(IslandLandmarks.VIS_RANGE_MID <= 300.0,
		"IslandLandmarks.VIS_RANGE_MID must be <= 300.0 m (got %.1f m)" % IslandLandmarks.VIS_RANGE_MID)
	for sl_glb in SEA_LORE_LANDMARKS:
		check(IslandLandmarks.MID_RANGE_FILES.has(sl_glb),
			"Wave I-15 landmark %s must be registered in IslandLandmarks.MID_RANGE_FILES (<= 300 m offshore LOD cap)" % sl_glb)

	# 2i. Automated 14-island landmark anti-float grounding audit!
	var grounded_checked := 0
	var floating_count := 0
	var worst_clearance := -INF
	var floating_offenders: Array[String] = []
	for isl_g in all_islands:
		var props_root := isl_g.get_node_or_null(^"Props") as Node3D
		if props_root == null:
			props_root = isl_g.get_node_or_null(^"PropsRoot") as Node3D
		if props_root == null:
			continue
		for child in props_root.get_children():
			var lm := child as Node3D
			if lm == null:
				continue
			var lm_name := String(lm.name)
			if not _is_grounding_audit_landmark(lm_name):
				continue
			var aabb_res := _compute_landmark_visual_aabb(lm, isl_g)
			if not bool(aabb_res.get("valid", false)):
				continue
			var bb: AABB = aabb_res["aabb"]
			var lm_origin := _relative_transform(lm, isl_g).origin
			var lx := lm_origin.x
			var lz := lm_origin.z
			var dx := bb.size.x * 0.28
			var dz := bb.size.z * 0.28
			var max_ground_y: float = isl_g.surface_height(lx, lz)
			max_ground_y = maxf(max_ground_y, isl_g.surface_height(lx + dx, lz + dz))
			max_ground_y = maxf(max_ground_y, isl_g.surface_height(lx - dx, lz + dz))
			max_ground_y = maxf(max_ground_y, isl_g.surface_height(lx + dx, lz - dz))
			max_ground_y = maxf(max_ground_y, isl_g.surface_height(lx - dx, lz - dz))
			var clearance := bb.position.y - max_ground_y
			grounded_checked += 1
			if clearance > worst_clearance:
				worst_clearance = clearance
			if clearance > 0.60:
				floating_count += 1
				floating_offenders.append("%s/%s (min_y=%.2f > max_g=%.2f + 0.60, clr=%+.2fm)" % [
					isl_g.island_id, lm_name, bb.position.y, max_ground_y, clearance])
	if grounded_checked == 0:
		worst_clearance = 0.0
	print("    wave_i15 grounding audit: %d landmarks checked, %d floating, worst_clearance=%+.2fm" % [
		grounded_checked, floating_count, worst_clearance])
	check(grounded_checked >= 230,
		"grounding audit must inspect >= 230 land landmarks across 14 islands (got %d)" % grounded_checked)
	check_eq(floating_count, 0,
		"all land landmarks must sit seated on/below terrain (aabb_min_y <= max_ground_y + 0.60; offenders: %s)" % [
			", ".join(floating_offenders.slice(0, 6))])

	# Verify zero-VRAM triplanar cliff PBR wired onto FortBastion & SmugglersGrotto stone meshes.
	var fort_isl := archipelago.get_island_by_id("ironwatch_fort")
	if fort_isl != null:
		var bst_mi := fort_isl.find_child("BastionStonework", true, false) as MeshInstance3D
		check(bst_mi != null and bst_mi.material_override is StandardMaterial3D,
			"Ironwatch Fort BastionStonework uses StandardMaterial3D")
		if bst_mi != null and bst_mi.material_override is StandardMaterial3D:
			var sm := bst_mi.material_override as StandardMaterial3D
			check(sm.uv1_triplanar and sm.albedo_texture != null and sm.normal_texture != null,
				"FortBastion stonework binds triplanar cliff albedo & normal PBR")
	if smug_isl != null:
		var grt_mi := smug_isl.find_child("GrottoVaultMesh", true, false) as MeshInstance3D
		check(grt_mi != null and grt_mi.material_override is StandardMaterial3D,
			"Smuggler's Cove GrottoVaultMesh uses StandardMaterial3D")
		if grt_mi != null and grt_mi.material_override is StandardMaterial3D:
			var gm := grt_mi.material_override as StandardMaterial3D
			check(gm.uv1_triplanar and gm.albedo_texture != null and gm.normal_texture != null,
				"SmugglersGrotto vault binds triplanar cliff albedo & normal PBR")

	# 3. Verify ALL 10 Wave 25B 1024x1024 PBR terrain textures exist on disk and load cleanly.
	var pbr_paths := IslandGenerator.get_terrain_pbr_texture_paths()
	check_eq(pbr_paths.size(), 10, "IslandGenerator exposes all 10 Wave 25B PBR terrain texture paths")
	for param_key in pbr_paths:
		var tex_path := String(pbr_paths[param_key])
		check(ResourceLoader.exists(tex_path), "missing Wave 25B PBR terrain texture: " + tex_path)
		var tex := load(tex_path) as Texture2D
		check(tex != null, "failed to load Wave 25B PBR terrain texture as Texture2D: " + tex_path)
		if tex != null:
			check_eq(tex.get_width(), 1024, "PBR terrain texture %s width == 1024" % tex_path)
			check_eq(tex.get_height(), 1024, "PBR terrain texture %s height == 1024" % tex_path)

	# 4. Full teardown & ZERO-leak verification!
	archipelago.queue_free()
	await physics_frames(2)

	check_eq(IslandDetailsCls._active_details, 0,
		"full 14-island Archipelago tears down IslandDetails cleanly (_active_details == 0)")
	var leaked_fields := _collect_leaked_detail_caches()
	check(leaked_fields.is_empty(),
		"full 14-island Archipelago releases all IslandDetails static caches (leaked: %s)" % ", ".join(leaked_fields))

