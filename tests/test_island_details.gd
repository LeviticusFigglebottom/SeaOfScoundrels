extends TestCase
## Headless contract tests for sculpted 3D island landmarks (12 PBR GLB assets)
## and batched MultiMesh `IslandDetails` ground foliage, coastal details &
## steep-slope cliff buttresses across all 14 island archetypes.

const IslandDetailsCls := preload("res://src/world/island_details.gd")
const FOLIAGE_SHADER: Shader = preload("res://src/world/foliage_wind.gdshader")
const LANDMARK_DIR := "res://assets/generated/landmarks/"

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
}

const EXPECTED_LANTERN_EMPTIES: Dictionary = {
	"skull_cliff_carving.glb": ["Lantern_SkullEyeL", "Lantern_SkullEyeR"],
	"cliff_catwalk_pier.glb": ["Lantern_Catwalk"],
	"impaled_shipwreck_bow.glb": ["Lantern_WreckBow"],
	"trail_lantern_post.glb": ["Lantern_Trail"],
}

const COMPACT_LANDMARKS: Array[String] = [
	"trail_lantern_post.glb",
	"stone_cairn_marker.glb",
]

const GROUND_COVER_LAYERS: Array[String] = [
	"GrassClumps",
	"JungleFerns",
	"HibiscusShrubs",
	"CoastalDriftwood",
	"ShorePebblesShells",
	"TidalOutcrops",
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


func test_all_12_landmark_glbs_load_pbr_tangents_and_colliders() -> void:
	var all_landmarks: Array[String] = []
	all_landmarks.append_array(GEOLOGY_LANDMARKS)
	all_landmarks.append_array(SETPIECE_LANDMARKS)
	check_eq(all_landmarks.size(), 12, "expected 12 sculpted landmark GLBs")

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

		var min_tris := 80 if COMPACT_LANDMARKS.has(filename) else 150
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


func test_island_details_all_14_archetypes_batched_grounded_and_deterministic() -> void:
	_init_host()
	check_eq(IslandGenerator.ARCHETYPES.size(), 14, "expected 14 island archetypes")

	for idx in IslandGenerator.ARCHETYPES.size():
		var arch := IslandGenerator.ARCHETYPES[idx]
		var isl := IslandGenerator.build_island({
			"id": "test_det_" + String(arch),
			"name": "Test Details " + String(arch),
			"archetype": arch,
			"seed": 700 + idx,
		})
		add_child(isl)

		var seed_val := 9001 + idx
		var details := IslandDetailsCls.populate_for_island(isl, arch, seed_val)
		check(details != null, "populate_for_island returned null for " + String(arch))
		if details == null:
			isl.queue_free()
			continue

		check(details.is_in_group(&"island_details"),
			"IslandDetails registers in island_details group on " + String(arch))

		var mm_count := details.get_multimesh_count()
		check(mm_count >= 5 and mm_count <= 8,
			"archetype %s MultiMesh draw-call count must be 5..8 (got %d)" % [arch, mm_count])

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
		var total_n := details.get_total_instance_count()

		print("    details %-16s r=%5.1fm  DC=%d  total=%4d  grass=%3d  fern=%3d  hib=%3d  coast=%3d  butt=%2d" % [
			String(arch), isl.island_radius, mm_count, total_n, grass_n, fern_n, hibiscus_n, coastal_n, buttress_n])

		if arch != &"volcano_crag" and arch != &"sea_stack" and isl.island_radius >= 50.0:
			check(grass_n >= 180 and grass_n <= 550,
				"archetype %s grass count out of 180..550 (got %d)" % [arch, grass_n])
			check(fern_n + hibiscus_n >= 80 and fern_n + hibiscus_n <= 260,
				"archetype %s fern+hibiscus count out of 80..260 (got %d)" % [arch, fern_n + hibiscus_n])
			check(coastal_n >= 40,
				"archetype %s coastal detail count < 40 (got %d)" % [arch, coastal_n])
			check(buttress_n >= 8,
				"archetype %s cliff buttress count < 8 (got %d)" % [arch, buttress_n])
		elif arch == &"volcano_crag" or arch == &"sea_stack":
			check(buttress_n >= 8,
				"archetype %s cliff buttress count < 8 (got %d)" % [arch, buttress_n])
			check(total_n >= 100,
				"archetype %s total detail count < 100 (got %d)" % [arch, total_n])
		else:
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

		# Verify determinism: second pass with identical seed produces exact same layer counts.
		var details_b := IslandDetailsCls.populate_for_island(isl, arch, seed_val)
		check(details_b != null, "second populate_for_island returned null for " + String(arch))
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
			if details_b.get_parent() == null:
				details_b.free()

		isl.queue_free()

	await physics_frames(3)


func test_island_details_outpost_keepouts_wind_and_zero_leaks() -> void:
	_init_host()

	var outpost := IslandGenerator.build_island(Archipelago.ISLAND_SPECS[0]) as Outpost
	var cutlass := IslandGenerator.build_island(Archipelago.ISLAND_SPECS[1])
	check(outpost != null, "Port Scoundrel built as Outpost")
	check(cutlass != null, "Cutlass Cay built as Island")
	add_child(outpost)
	add_child(cutlass)

	var op_details := IslandDetailsCls.populate_for_island(outpost, outpost.archetype, 1101 + 313)
	var cc_details := IslandDetailsCls.populate_for_island(cutlass, cutlass.archetype, 2203 + 313)
	await physics_frames(1)

	check(op_details != null and cc_details != null,
		"IslandDetails populated cleanly on Port Scoundrel and Cutlass Cay")
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

	# 3. Zero-leak teardown: free all islands & details, await 2 physics frames, confirm all caches cleared!
	outpost.queue_free()
	cutlass.queue_free()
	await physics_frames(2)

	check_eq(IslandDetailsCls._active_details, 0,
		"all IslandDetails exited cleanly (_active_details == 0)")
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
	if not IslandDetailsCls._glb_mesh_cache.is_empty():
		leaked_fields.append("_glb_mesh_cache(%d)" % IslandDetailsCls._glb_mesh_cache.size())

	check(leaked_fields.is_empty(),
		"IslandDetails releases all static caches cleanly on teardown (leaked: %s)" % ", ".join(leaked_fields))
