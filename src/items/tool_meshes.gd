class_name ToolMeshes
extends RefCounted
## Procedural chunky stylized 3D mesh builders for all 11 pirate tools and weapons.
##
## Every mesh is built from scratch with beveled surfaces, turned brass lathes,
## lofted curved blades/stocks, and rich warm painterly materials (warm brass,
## dark oak, gleaming steel, stitched leather, glowing lantern glass, parchment).
## Grip origin sits at (0, 0, 0) in tool-local space so both first-person
## viewmodels and third-person CharacterVisual.hand_right sockets mount cleanly.

const ALL_TOOLS: Array[StringName] = [
	&"cutlass",
	&"pistol",
	&"compass",
	&"spyglass",
	&"lantern",
	&"map",
	&"shovel",
	&"bucket",
	&"planks",
	&"tankard",
	&"instrument",
]

const DISPLAY_NAMES := {
	&"cutlass": "Cutlass",
	&"boarding_axe": "Boarding Axe",
	&"pistol": "Flintlock Pistol",
	&"blunderbuss": "Blunderbuss",
	&"compass": "Brass Compass",
	&"spyglass": "Spyglass",
	&"lantern": "Oil Lantern",
	&"map": "Treasure Map",
	&"shovel": "Iron Shovel",
	&"bucket": "Bilge Bucket",
	&"planks": "Oak Planks",
	&"tankard": "Grog Tankard",
	&"instrument": "Concertina",
	&"hurdy_gurdy": "Hurdy-Gurdy",
	&"whistle": "Bosun's Whistle",
	&"speaking_trumpet": "Speaking Trumpet",
}

# Curated warm painterly pirate palette (matching sloop.glb & concept art).
const COL_BRASS := Color(0.82, 0.62, 0.24)
const COL_BRONZE := Color(0.49, 0.35, 0.16)
const COL_STEEL := Color(0.79, 0.84, 0.89)
const COL_STEEL_EDGE := Color(0.92, 0.95, 0.98)
const COL_IRON := Color(0.24, 0.26, 0.30)
const COL_OAK_DARK := Color(0.31, 0.19, 0.11)
const COL_OAK_WARM := Color(0.47, 0.30, 0.16)
const COL_OAK_LIGHT := Color(0.60, 0.42, 0.23)
const COL_WALNUT := Color(0.38, 0.19, 0.10)
const COL_LEATHER := Color(0.42, 0.22, 0.12)
const COL_CRIMSON := Color(0.76, 0.13, 0.11)
const COL_GOLD_BRIGHT := Color(0.95, 0.78, 0.28)
const COL_IVORY := Color(0.93, 0.87, 0.72)
const COL_PARCHMENT_BACK := Color(0.76, 0.66, 0.48)
const COL_ROPE := Color(0.68, 0.57, 0.38)
const COL_PEWTER := Color(0.56, 0.59, 0.62)
const COL_FOAM := Color(0.96, 0.92, 0.82)
const COL_GROG := Color(0.42, 0.22, 0.06)
const COL_WATER := Color(0.16, 0.58, 0.56, 0.86)
const COL_LENS := Color(0.14, 0.26, 0.38, 0.84)
const COL_CRYSTAL := Color(0.84, 0.92, 0.96, 0.30)
const COL_GLASS_LIT := Color(1.0, 0.78, 0.38, 0.76)
const COL_GLASS_UNLIT := Color(0.68, 0.72, 0.74, 0.36)
const COL_FLAME := Color(1.0, 0.90, 0.46)
const COL_BELLOWS_RED := Color(0.68, 0.20, 0.16)
const COL_BELLOWS_CREAM := Color(0.88, 0.80, 0.62)

# Zero-extra-VRAM ship PBR normal & roughness maps already resident in VRAM.
const _PBR_FAMILY_SPECS := {
	&"oak": {
		"normal": "res://assets/generated/textures/ship_oak_normal.png",
		"rough": "res://assets/generated/textures/ship_oak_rough.png",
		"scale": Vector3(2.4, 2.4, 2.4),
		"normal_scale": 0.52,
	},
	&"brass": {
		"normal": "res://assets/generated/textures/ship_brass_normal.png",
		"rough": "res://assets/generated/textures/ship_brass_rough.png",
		"scale": Vector3(3.0, 3.0, 3.0),
		"normal_scale": 0.50,
	},
	&"iron": {
		"normal": "res://assets/generated/textures/ship_iron_normal.png",
		"rough": "res://assets/generated/textures/ship_iron_rough.png",
		"scale": Vector3(3.0, 3.0, 3.0),
		"normal_scale": 0.56,
	},
	&"rope": {
		"normal": "res://assets/generated/textures/ship_rope_normal.png",
		"rough": "res://assets/generated/textures/ship_rope_rough.png",
		"scale": Vector3(3.0, 3.0, 3.0),
		"normal_scale": 0.58,
	},
	&"cloth": {
		"normal": "res://assets/generated/textures/ship_cloth_normal.png",
		"rough": "",
		"scale": Vector3(3.0, 3.0, 3.0),
		"normal_scale": 0.48,
	},
	&"leather": {
		"normal": "res://assets/generated/textures/ship_oak_normal.png",
		"rough": "res://assets/generated/textures/ship_oak_rough.png",
		"scale": Vector3(3.4, 3.4, 3.4),
		"normal_scale": 0.44,
	},
}

## Lazy WeakRef cache of shared ship PBR Texture2D references (zero shutdown leaks).
static var _pbr_tex_cache: Dictionary = {}


## Clear cached shared PBR texture references cleanly on scene teardown.
static func clear_shared_cache() -> void:
	_pbr_tex_cache.clear()


static func _load_pbr_tex(path: String) -> Texture2D:
	if path == "":
		return null
	if _pbr_tex_cache.has(path):
		var wr: Variant = _pbr_tex_cache[path]
		if wr is WeakRef:
			var obj: Variant = (wr as WeakRef).get_ref()
			if obj is Texture2D:
				return obj as Texture2D
	if not ResourceLoader.exists(path):
		return null
	var loaded: Variant = ResourceLoader.load(path)
	if loaded is Texture2D:
		var tex := loaded as Texture2D
		_pbr_tex_cache[path] = weakref(tex)
		return tex
	return null


## Return ordered list of all 11 supported held tool IDs.
static func get_tool_ids() -> Array[StringName]:
	return ALL_TOOLS.duplicate()


## Return human-readable display name for a tool ID.
static func get_display_name(tool_id: StringName) -> String:
	return String(DISPLAY_NAMES.get(tool_id, String(tool_id).capitalize()))


## Build a complete stylized 3D Node3D hierarchy for `tool_id`.
static func build_tool(tool_id: StringName) -> Node3D:
	match tool_id:
		&"cutlass":
			return _build_cutlass()
		&"boarding_axe":
			return _build_boarding_axe()
		&"pistol":
			return _build_pistol()
		&"blunderbuss":
			return _build_blunderbuss()
		&"compass":
			return _build_compass()
		&"spyglass":
			return _build_spyglass()
		&"lantern":
			return _build_lantern()
		&"map":
			return _build_map()
		&"shovel":
			return _build_shovel()
		&"bucket":
			return _build_bucket()
		&"planks":
			return _build_planks()
		&"tankard":
			return _build_tankard()
		&"instrument":
			return _build_instrument()
		&"hurdy_gurdy":
			return _build_hurdy_gurdy()
		&"whistle":
			return _build_whistle()
		&"speaking_trumpet":
			return _build_speaking_trumpet()
		_:
			push_warning("ToolMeshes: unknown tool '%s', falling back to cutlass." % String(tool_id))
			return _build_cutlass()


## Update the texture displayed on a held Treasure Map node built by `build_tool(&"map")`.
static func apply_map_texture(map_node: Node3D, tex: Texture2D) -> void:
	if map_node == null or tex == null:
		return
	var surf := map_node.get_node_or_null(^"MapSurface") as MeshInstance3D
	if surf == null:
		return
	var mat := surf.material_override as StandardMaterial3D
	if mat == null:
		mat = _make_mat(Color.WHITE, 0.78, 0.0, Color.BLACK, 0.0, false, &"none")
		surf.material_override = mat
	mat.albedo_texture = tex


## Toggle a Lantern node's flame mesh, glowing amber glass emission, and OmniLight3D.
static func set_lantern_lit(lantern_node: Node3D, lit: bool) -> void:
	if lantern_node == null:
		return
	var light := lantern_node.get_node_or_null(^"LanternLight") as OmniLight3D
	if light != null:
		light.visible = lit
		light.light_energy = 2.4 if lit else 0.0
	var flame := lantern_node.get_node_or_null(^"Flame") as Node3D
	if flame != null:
		flame.visible = lit
	var glass := lantern_node.get_node_or_null(^"GlassCore") as MeshInstance3D
	if glass != null and glass.material_override is StandardMaterial3D:
		var mat := glass.material_override as StandardMaterial3D
		if lit:
			mat.albedo_color = COL_GLASS_LIT
			mat.emission_enabled = true
			mat.emission = Color(1.0, 0.64, 0.20)
			mat.emission_energy_multiplier = 2.2
		else:
			mat.albedo_color = COL_GLASS_UNLIT
			mat.emission_enabled = false
			mat.emission_energy_multiplier = 0.0


## Toggle the visible bilge water disc inside a Bucket node.
static func set_bucket_full(bucket_node: Node3D, full: bool) -> void:
	if bucket_node == null:
		return
	var wf := bucket_node.get_node_or_null(^"WaterFill") as Node3D
	if wf != null:
		wf.visible = full


## Expand or squeeze a Concertina node's bellows (`stretch_01` in 0..1, 0.5 = rest).
static func set_concertina_stretch(inst_node: Node3D, stretch_01: float) -> void:
	if inst_node == null:
		return
	var s := clampf(stretch_01, 0.0, 1.0)
	var scale_x := lerpf(0.68, 1.48, s)
	var bellows := inst_node.get_node_or_null(^"Bellows") as Node3D
	var left_end := inst_node.get_node_or_null(^"LeftEnd") as Node3D
	var right_end := inst_node.get_node_or_null(^"RightEnd") as Node3D
	if bellows != null:
		bellows.scale.x = scale_x
	var half_span := 0.085 * scale_x
	if left_end != null:
		left_end.position.x = -half_span
	if right_end != null:
		right_end.position.x = half_span


## Rotate a Hurdy-Gurdy node's `"CrankHandle"` around its drive axle (`angle_rad`).
static func set_hurdy_gurdy_crank(inst_node: Node3D, angle_rad: float) -> void:
	if inst_node == null:
		return
	var crank := inst_node.get_node_or_null(^"CrankHandle") as Node3D
	if crank != null:
		crank.rotation.x = angle_rad


## Extend or retract a Spyglass node's telescoping draw tubes (`ext_01` in 0..1).
static func set_spyglass_extension(spy_node: Node3D, ext_01: float) -> void:
	if spy_node == null:
		return
	var tubes := spy_node.get_node_or_null(^"DrawTubes") as Node3D
	if tubes != null:
		tubes.position.z = -clampf(ext_01, 0.0, 1.0) * 0.16


## Apply visible 3D first-person/third-person styling for Economy `tool_variant` sidegrades
## (`tool_far_spyglass`/`tool_gilded_spyglass`, `tool_relic_shovel`/`tool_master_shovel`,
## `tool_heavy_bailer`/`tool_cooper_bucket`), or reset cleanly to standard visuals when `variant_id == &""`.
static func apply_tool_variant_visual(item_id: StringName, node: Node3D, variant_id: StringName) -> void:
	if node == null or not is_instance_valid(node):
		return
	var is_far_spyglass := variant_id == &"tool_far_spyglass" or variant_id == &"tool_gilded_spyglass"
	var is_relic_shovel := variant_id == &"tool_relic_shovel" or variant_id == &"tool_master_shovel"
	var is_heavy_bailer := variant_id == &"tool_heavy_bailer" or variant_id == &"tool_cooper_bucket"
	var applied := &""

	match item_id:
		&"spyglass":
			var tubes := node.get_node_or_null(^"DrawTubes") as Node3D
			var eyepiece := node.get_node_or_null(^"BrassEyepiece") as MeshInstance3D
			var brass_tubes := tubes.get_node_or_null(^"TelescopingBrass") as MeshInstance3D if tubes != null else null
			var lens := tubes.get_node_or_null(^"ObjectiveLens") as MeshInstance3D if tubes != null else null
			var accent_ring := tubes.get_node_or_null(^"VariantAccentRing") as MeshInstance3D if tubes != null else null
			if is_far_spyglass:
				applied = variant_id
				if tubes != null:
					tubes.scale = Vector3(1.0, 1.0, 1.22)
				if eyepiece != null:
					eyepiece.material_override = _make_mat(COL_GOLD_BRIGHT, 0.18, 0.94)
				if brass_tubes != null:
					brass_tubes.material_override = _make_mat(COL_GOLD_BRIGHT, 0.16, 0.95)
				if lens != null:
					lens.material_override = _make_mat(Color(0.18, 0.56, 0.96, 0.80), 0.06, 0.25, Color(0.14, 0.54, 0.98), 0.65, true)
				if tubes != null:
					if accent_ring == null:
						var rot_z := Basis(Vector3.RIGHT, -PI * 0.5)
						var ring_mesh := _lathe_mesh([
							Vector2(0.036, 0.432),
							Vector2(0.046, 0.436),
							Vector2(0.046, 0.456),
							Vector2(0.038, 0.458),
						], 16, Transform3D(rot_z, Vector3.ZERO))
						accent_ring = _make_mesh_node("VariantAccentRing", ring_mesh,
							_make_mat(Color(0.16, 0.54, 0.95), 0.14, 0.82, Color(0.12, 0.48, 0.92), 0.55))
						tubes.add_child(accent_ring)
					accent_ring.visible = true
			else:
				if tubes != null:
					tubes.scale = Vector3.ONE
				if eyepiece != null:
					eyepiece.material_override = _make_mat(COL_BRASS, 0.24, 0.88)
				if brass_tubes != null:
					brass_tubes.material_override = _make_mat(COL_BRASS, 0.22, 0.90)
				if lens != null:
					lens.material_override = _make_mat(COL_LENS, 0.08, 0.25, Color(0.12, 0.26, 0.40), 0.25, true)
				if accent_ring != null:
					accent_ring.visible = false

		&"shovel":
			var blade := node.get_node_or_null(^"SpadeBlade") as MeshInstance3D
			var runic_band := node.get_node_or_null(^"VariantRunicBand") as MeshInstance3D
			if is_relic_shovel:
				applied = variant_id
				if blade != null:
					blade.material_override = _make_mat(Color(0.84, 0.64, 0.24), 0.26, 0.88)
				if runic_band == null:
					var band_mesh := _lathe_mesh([
						Vector2(0.025, 0.305),
						Vector2(0.032, 0.312),
						Vector2(0.032, 0.376),
						Vector2(0.025, 0.384),
					], 12)
					runic_band = _make_mesh_node("VariantRunicBand", band_mesh,
						_make_mat(Color(0.14, 0.88, 0.72), 0.20, 0.35, Color(0.14, 0.92, 0.76), 1.45))
					node.add_child(runic_band)
				runic_band.visible = true
			else:
				if blade != null:
					blade.material_override = _make_mat(COL_IRON, 0.44, 0.76)
				if runic_band != null:
					runic_band.visible = false

		&"bucket":
			var staves := node.get_node_or_null(^"OakStaves") as Node3D
			var bands := node.get_node_or_null(^"IronBands") as MeshInstance3D
			var water := node.get_node_or_null(^"WaterFill") as Node3D
			var target_scale := Vector3(1.16, 1.06, 1.16) if is_heavy_bailer else Vector3.ONE
			if is_heavy_bailer:
				applied = variant_id
			for child_n: Node3D in [staves, bands, water]:
				if child_n != null:
					child_n.scale = target_scale
			if bands != null:
				if is_heavy_bailer:
					bands.material_override = _make_mat(Color(0.32, 0.34, 0.39), 0.20, 0.92)
				else:
					bands.material_override = _make_mat(COL_IRON, 0.46, 0.74)

	node.set_meta(&"tool_variant_id", applied)


# ==============================================================================
# Individual tool builders
# ==============================================================================

## 1. Cutlass: curved gleaming pirate sabre with ornate brass basket/D-guard hilt.
static func _build_cutlass() -> Node3D:
	var root := Node3D.new()
	root.name = "Tool_Cutlass"

	# Curved broad cutlass blade lofted along +Y with forward sweep (-Z) and clipped point.
	var blade_rings: Array = []
	var blade_steps := 12
	for i in range(blade_steps + 1):
		var t := float(i) / float(blade_steps)
		var y := 0.105 + t * 0.64
		# Classic pirate cutlass curve: convex forward cutting edge (-Z) sweeping gracefully back toward tip (+Z).
		var sweep_z := 0.072 * pow(t, 1.95) - 0.012 * sin(t * PI)
		var width := 0.056 * (1.0 + 0.24 * sin(t * PI * 0.82)) * (1.0 - 0.88 * pow(t, 4.2))
		if i == blade_steps:
			width = 0.003
		var spine_half_x := lerpf(0.0085, 0.0025, t)
		var edge_z := sweep_z - width * 0.62
		var spine_z := sweep_z + width * 0.38
		var mid_z := lerpf(edge_z, spine_z, 0.56)
		blade_rings.append([
			Vector3(0.0, y, edge_z),                  # sharp front edge
			Vector3(spine_half_x * 1.05, y, mid_z),   # right fuller bevel
			Vector3(spine_half_x * 0.72, y, spine_z), # right spine
			Vector3(-spine_half_x * 0.72, y, spine_z),# left spine
			Vector3(-spine_half_x * 1.05, y, mid_z),  # left fuller bevel
		])
	var blade_mi := _make_mesh_node("Blade", _loft_mesh(blade_rings, true), _make_mat(COL_STEEL, 0.22, 0.90))
	root.add_child(blade_mi)

	# Ribbed dark stitched-leather grip centered at origin.
	var grip_prof: Array[Vector2] = [
		Vector2(0.017, -0.082),
		Vector2(0.021, -0.055),
		Vector2(0.018, -0.028),
		Vector2(0.022, 0.0),
		Vector2(0.019, 0.028),
		Vector2(0.022, 0.055),
		Vector2(0.019, 0.082),
	]
	root.add_child(_make_mesh_node("Grip", _lathe_mesh(grip_prof, 10), _make_mat(COL_LEATHER, 0.76, 0.05)))

	# Ornate brass cup-guard, pommel, and sweeping D-guard knuckle bow.
	var st_brass := SurfaceTool.new()
	st_brass.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Flared protective hand-guard shell at top of grip.
	_append_lathe(st_brass, [
		Vector2(0.022, 0.075),
		Vector2(0.048, 0.086),
		Vector2(0.068, 0.104),
		Vector2(0.060, 0.114),
		Vector2(0.024, 0.106),
	], 12)
	# Turned pommel cap at bottom of grip.
	_append_lathe(st_brass, [
		Vector2(0.0, -0.125),
		Vector2(0.024, -0.116),
		Vector2(0.030, -0.098),
		Vector2(0.021, -0.080),
	], 10)
	# Sweeping D-guard knuckle bow curving forward (-Z) from guard to pommel.
	var bow_pts: Array[Vector3] = []
	for i in 11:
		var u := float(i) / 10.0
		var ang := lerpf(0.0, PI, u)
		var bz := -0.022 - sin(ang) * 0.072
		var by := lerpf(0.098, -0.096, u)
		bow_pts.append(Vector3(0.0, by, bz))
	_append_tube(st_brass, bow_pts, 0.0095, 8, true)
	# Side basket rib for bold silhouette inspired by concept art.
	var rib_pts: Array[Vector3] = []
	for i in 9:
		var u := float(i) / 8.0
		var ang := lerpf(0.0, PI, u)
		rib_pts.append(Vector3(sin(ang) * 0.044, lerpf(0.098, -0.088, u), -0.015 - sin(ang) * 0.050))
	_append_tube(st_brass, rib_pts, 0.0065, 6, true)
	st_brass.generate_normals()
	root.add_child(_make_mesh_node("BrassHilt", st_brass.commit(), _make_mat(COL_BRASS, 0.28, 0.86)))
	return root


## 2. Flintlock Pistol: chunky brass-trimmed barrel & carved walnut stock (-Z aim).
static func _build_pistol() -> Node3D:
	var root := Node3D.new()
	root.name = "Tool_Pistol"

	# Carved curved walnut pistol stock + forearm bed.
	var stock_rings: Array = []
	var stock_path: Array = [
		[Vector3(0.0, -0.115, 0.078), 0.022, 0.024],
		[Vector3(0.0, -0.062, 0.046), 0.019, 0.021],
		[Vector3(0.0, -0.006, 0.016), 0.018, 0.022],
		[Vector3(0.0, 0.036, -0.022), 0.020, 0.025],
		[Vector3(0.0, 0.040, -0.135), 0.018, 0.022],
		[Vector3(0.0, 0.042, -0.245), 0.014, 0.016],
	]
	for s in stock_path:
		var c: Vector3 = s[0]
		var rx: float = s[1]
		var ry: float = s[2]
		# Ring wound so dT (-Z) x dU points strictly outward on all side walls & end caps.
		stock_rings.append([
			c + Vector3(0.0, ry, 0.0),
			c + Vector3(-rx, ry * 0.45, 0.0),
			c + Vector3(-rx * 0.9, -ry * 0.55, 0.0),
			c + Vector3(0.0, -ry, 0.0),
			c + Vector3(rx * 0.9, -ry * 0.55, 0.0),
			c + Vector3(rx, ry * 0.45, 0.0),
		])
	root.add_child(_make_mesh_node("Stock", _loft_mesh(stock_rings, true), _make_mat(COL_WALNUT, 0.62, 0.04)))

	# Octagonal forged-iron barrel with flared blunder-style pirate muzzle (-Z).
	var barrel_xf := Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(0.0, 0.062, -0.035))
	var barrel_prof: Array[Vector2] = [
		Vector2(0.0, 0.0),
		Vector2(0.022, 0.002),
		Vector2(0.020, 0.14),
		Vector2(0.018, 0.25),
		Vector2(0.026, 0.285),
		Vector2(0.023, 0.292),
		Vector2(0.014, 0.282),
		Vector2(0.0, 0.265),
	]
	var st_iron := SurfaceTool.new()
	st_iron.begin(Mesh.PRIMITIVE_TRIANGLES)
	_append_lathe(st_iron, barrel_prof, 8, barrel_xf)
	# Curved flintlock hammer/cock on starboard lockplate + steel frizzen.
	_append_tube(st_iron, [
		Vector3(0.024, 0.048, -0.038),
		Vector3(0.028, 0.088, -0.032),
		Vector3(0.024, 0.098, -0.056),
	], 0.0065, 6, true)
	_append_beveled_box(st_iron, Vector3(0.010, 0.032, 0.016), 0.002, Transform3D(Basis.IDENTITY, Vector3(0.024, 0.072, -0.084)))
	st_iron.generate_normals()
	root.add_child(_make_mesh_node("BarrelAndLock", st_iron.commit(), _make_mat(COL_IRON, 0.40, 0.78)))

	# Brass trim: barrel bands, butt pommel cap, lockplate, trigger guard & trigger.
	var st_brass := SurfaceTool.new()
	st_brass.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Barrel collar bands.
	_append_lathe(st_brass, [Vector2(0.0225, 0.09), Vector2(0.0245, 0.095), Vector2(0.0245, 0.115), Vector2(0.0225, 0.12)], 10, barrel_xf)
	_append_lathe(st_brass, [Vector2(0.021, 0.205), Vector2(0.0235, 0.210), Vector2(0.0235, 0.232), Vector2(0.021, 0.237)], 10, barrel_xf)
	# Heavy brass pommel butt cap.
	var pom_xf := Transform3D(Basis(Vector3.RIGHT, 0.55), Vector3(0.0, -0.122, 0.082))
	_append_lathe(st_brass, [Vector2(0.0, -0.016), Vector2(0.026, -0.006), Vector2(0.026, 0.016), Vector2(0.018, 0.022)], 10, pom_xf)
	# Starboard brass lockplate.
	_append_beveled_box(st_brass, Vector3(0.008, 0.030, 0.078), 0.0025, Transform3D(Basis.IDENTITY, Vector3(0.020, 0.044, -0.056)))
	# Trigger guard bow & trigger.
	_append_tube(st_brass, [
		Vector3(0.0, 0.020, -0.012),
		Vector3(0.0, -0.014, -0.036),
		Vector3(0.0, -0.012, -0.078),
		Vector3(0.0, 0.022, -0.094),
	], 0.0045, 6, true)
	_append_beveled_box(st_brass, Vector3(0.005, 0.024, 0.007), 0.001, Transform3D(Basis(Vector3.RIGHT, -0.3), Vector3(0.0, 0.006, -0.048)))
	st_brass.generate_normals()
	root.add_child(_make_mesh_node("BrassTrim", st_brass.commit(), _make_mat(COL_BRASS, 0.26, 0.86)))
	return root


## 2b. Boarding Axe: chunky crescent forged-steel chopping blade with riveted iron collar,
## rear armor-piercing boarding spike, long wrapped oak haft with leather bands, & brass pommel.
static func _build_boarding_axe() -> Node3D:
	var root := Node3D.new()
	root.name = "Tool_BoardingAxe"

	# Long turned oak haft passing through grip origin (0, 0, 0) up into the axe eye finial.
	var haft_prof: Array[Vector2] = [
		Vector2(0.0, -0.215),
		Vector2(0.018, -0.208),
		Vector2(0.022, -0.155),
		Vector2(0.019, -0.070),
		Vector2(0.020, 0.040),
		Vector2(0.019, 0.190),
		Vector2(0.022, 0.365),
		Vector2(0.024, 0.560),
		Vector2(0.018, 0.602),
		Vector2(0.0, 0.615),
	]
	root.add_child(_make_mesh_node("TimberHaft", _lathe_mesh(haft_prof, 10), _make_mat(COL_OAK_WARM, 0.78, 0.03)))

	# Stitched dark leather grip wrap centered at origin plus upper choking-grip band.
	var st_leather := SurfaceTool.new()
	st_leather.begin(Mesh.PRIMITIVE_TRIANGLES)
	_append_lathe(st_leather, [
		Vector2(0.019, -0.116),
		Vector2(0.0235, -0.106),
		Vector2(0.0215, -0.072),
		Vector2(0.0245, -0.038),
		Vector2(0.0215, 0.0),
		Vector2(0.0245, 0.038),
		Vector2(0.0215, 0.072),
		Vector2(0.0235, 0.102),
		Vector2(0.019, 0.112),
	], 10)
	_append_lathe(st_leather, [
		Vector2(0.0195, 0.215),
		Vector2(0.0240, 0.224),
		Vector2(0.0222, 0.252),
		Vector2(0.0245, 0.280),
		Vector2(0.0205, 0.292),
	], 10)
	st_leather.generate_normals()
	root.add_child(_make_mesh_node("LeatherWrap", st_leather.commit(), _make_mat(COL_LEATHER, 0.74, 0.05)))

	# Turned brass pommel cap, lanyard loop, and bolster ferrule bands.
	var st_brass := SurfaceTool.new()
	st_brass.begin(Mesh.PRIMITIVE_TRIANGLES)
	_append_lathe(st_brass, [
		Vector2(0.0, -0.268),
		Vector2(0.026, -0.258),
		Vector2(0.032, -0.236),
		Vector2(0.027, -0.212),
		Vector2(0.020, -0.202),
	], 10)
	var ring_pts: Array[Vector3] = []
	for i in 11:
		var a := float(i) / 10.0 * TAU
		ring_pts.append(Vector3(cos(a) * 0.014, -0.278 + sin(a) * 0.014, 0.0))
	_append_tube(st_brass, ring_pts, 0.0038, 6, false)
	# Bolster rings framing leather grip and seated beneath the iron collar.
	_append_lathe(st_brass, [
		Vector2(0.020, -0.130), Vector2(0.025, -0.126), Vector2(0.025, -0.114), Vector2(0.020, -0.110),
	], 10)
	_append_lathe(st_brass, [
		Vector2(0.020, 0.106), Vector2(0.025, 0.110), Vector2(0.025, 0.122), Vector2(0.020, 0.126),
	], 10)
	_append_lathe(st_brass, [
		Vector2(0.022, 0.376), Vector2(0.028, 0.382), Vector2(0.028, 0.402), Vector2(0.023, 0.408),
	], 10)
	st_brass.generate_normals()
	root.add_child(_make_mesh_node("BrassFittings", st_brass.commit(), _make_mat(COL_BRASS, 0.28, 0.86)))

	# Riveted forged-iron eye collar, cheek plates, reinforcement langets, and proud domed rivets.
	var st_iron := SurfaceTool.new()
	st_iron.begin(Mesh.PRIMITIVE_TRIANGLES)
	_append_beveled_box(st_iron, Vector3(0.056, 0.148, 0.078), 0.009,
		Transform3D(Basis.IDENTITY, Vector3(0.0, 0.485, 0.0)))
	_append_beveled_box(st_iron, Vector3(0.050, 0.022, 0.070), 0.005,
		Transform3D(Basis.IDENTITY, Vector3(0.0, 0.566, 0.0)))
	# Front & rear langet straps bolted down the oak haft.
	_append_beveled_box(st_iron, Vector3(0.022, 0.155, 0.012), 0.003,
		Transform3D(Basis.IDENTITY, Vector3(0.0, 0.345, -0.024)))
	_append_beveled_box(st_iron, Vector3(0.022, 0.155, 0.012), 0.003,
		Transform3D(Basis.IDENTITY, Vector3(0.0, 0.345, 0.024)))
	var rivet_prof: Array[Vector2] = [
		Vector2(0.007, 0.0),
		Vector2(0.007, 0.004),
		Vector2(0.0045, 0.007),
		Vector2(0.0, 0.008),
	]
	for sx: float in [-1.0, 1.0]:
		var cheek_rot := Basis(Vector3.BACK, -sx * PI * 0.5)
		for ry: float in [0.445, 0.525]:
			for rz: float in [-0.018, 0.018]:
				_append_lathe(st_iron, rivet_prof, 6, Transform3D(cheek_rot, Vector3(sx * 0.026, ry, rz)))
	for sz: float in [-1.0, 1.0]:
		var lang_rot := Basis(Vector3.RIGHT, sz * PI * 0.5)
		for ry: float in [0.295, 0.355]:
			_append_lathe(st_iron, rivet_prof, 6, Transform3D(lang_rot, Vector3(0.0, ry, sz * 0.028)))
	st_iron.generate_normals()
	root.add_child(_make_mesh_node("IronCollar", st_iron.commit(), _make_mat(COL_IRON, 0.40, 0.80)))

	# Chunky crescent forged-steel chopping blade (-Z) + rear armor-piercing boarding spike (+Z).
	var st_steel := SurfaceTool.new()
	st_steel.begin(Mesh.PRIMITIVE_TRIANGLES)
	var blade_rings: Array = []
	var blade_steps := 12
	for i in range(blade_steps + 1):
		var t := float(i) / float(blade_steps)
		var y := lerpf(0.335, 0.635, t)
		var u_mid := (t - 0.50) * 2.0
		var abs_u := absf(u_mid)
		# Concave bearded neck & dramatic convex crescent cutting edge facing -Z.
		var back_z := -0.026 - 0.105 * pow(abs_u, 1.85)
		var front_z := -0.242 + 0.072 * (u_mid * u_mid)
		var bevel_z := lerpf(front_z, back_z, 0.26)
		var cheek_x := lerpf(0.018, 0.0085, abs_u)
		var bevel_x := cheek_x * 0.66
		# CW from +Y so dT (+Y) x dU points strictly outward on every face & end cap.
		blade_rings.append([
			Vector3(0.0, y, front_z),
			Vector3(bevel_x, y, bevel_z),
			Vector3(cheek_x, y, back_z),
			Vector3(-cheek_x, y, back_z),
			Vector3(-bevel_x, y, bevel_z),
		])
	_append_loft(st_steel, blade_rings, true)

	# Rear curved diamond-section armor-piercing boarding spike extending along +Z.
	var spike_rings: Array = []
	var spike_steps := 7
	for i in range(spike_steps + 1):
		var t := float(i) / float(spike_steps)
		var z := lerpf(0.030, 0.202, t)
		var yc := 0.502 - 0.052 * pow(t, 1.75)
		var rx := lerpf(0.017, 0.0022, pow(t, 0.85))
		var ry := lerpf(0.024, 0.0025, pow(t, 0.85))
		# Wound top -> right -> bottom -> left so dT (+Z) x dU points strictly outward.
		spike_rings.append([
			Vector3(0.0, yc + ry, z),
			Vector3(rx, yc, z),
			Vector3(0.0, yc - ry, z),
			Vector3(-rx, yc, z),
		])
	_append_loft(st_steel, spike_rings, true)
	st_steel.generate_normals()
	root.add_child(_make_mesh_node("AxeBlade", st_steel.commit(), _make_mat(COL_STEEL, 0.24, 0.90)))
	return root


## 2c. Blunderbuss: iconic flared bell-mouth brass barrel with octagonal breech,
## carved walnut stock, brass trigger guard, and starboard flintlock hammer & lockplate (-Z aim).
static func _build_blunderbuss() -> Node3D:
	var root := Node3D.new()
	root.name = "Tool_Blunderbuss"

	# Carved walnut shoulder buttstock, slender wrist at origin, and chunky forearm bed (-Z).
	var st_wood := SurfaceTool.new()
	st_wood.begin(Mesh.PRIMITIVE_TRIANGLES)
	var stock_rings: Array = []
	var stock_path: Array = [
		[Vector3(0.0, -0.090, 0.220), 0.024, 0.058],
		[Vector3(0.0, -0.068, 0.145), 0.022, 0.044],
		[Vector3(0.0, -0.028, 0.068), 0.020, 0.028],
		[Vector3(0.0, -0.004, 0.008), 0.019, 0.023],
		[Vector3(0.0, 0.036, -0.048), 0.025, 0.030],
		[Vector3(0.0, 0.038, -0.185), 0.024, 0.024],
		[Vector3(0.0, 0.040, -0.295), 0.020, 0.019],
	]
	for s in stock_path:
		var c: Vector3 = s[0]
		var rx: float = s[1]
		var ry: float = s[2]
		# Ring wound so dT (-Z) x dU points strictly outward on all side walls & end caps.
		stock_rings.append([
			c + Vector3(0.0, ry, 0.0),
			c + Vector3(-rx, ry * 0.45, 0.0),
			c + Vector3(-rx * 0.9, -ry * 0.55, 0.0),
			c + Vector3(0.0, -ry, 0.0),
			c + Vector3(rx * 0.9, -ry * 0.55, 0.0),
			c + Vector3(rx, ry * 0.45, 0.0),
		])
	_append_loft(st_wood, stock_rings, true)
	# Under-barrel wooden ramrod tucked cleanly beneath the forearm.
	var ram_xf := Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(0.0, 0.020, -0.175))
	_append_lathe(st_wood, [
		Vector2(0.0, 0.0),
		Vector2(0.0065, 0.002),
		Vector2(0.0065, 0.205),
		Vector2(0.0, 0.208),
	], 8, ram_xf)
	st_wood.generate_normals()
	root.add_child(_make_mesh_node("Stock", st_wood.commit(), _make_mat(COL_WALNUT, 0.60, 0.04)))

	# Iconic octagonal-breech flared bell-mouth brass barrel, clamping bands, buttplate,
	# starboard lockplate, and sweeping brass trigger guard.
	var barrel_xf := Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(0.0, 0.070, -0.035))
	var st_brass := SurfaceTool.new()
	st_brass.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Octagonal heavy breech section (8 segments).
	_append_lathe(st_brass, [
		Vector2(0.0, 0.0),
		Vector2(0.031, 0.002),
		Vector2(0.030, 0.155),
		Vector2(0.027, 0.168),
	], 8, barrel_xf)
	# Turned stepped collar moulding & dramatic flared trumpet bell-mouth muzzle (16 segments).
	_append_lathe(st_brass, [
		Vector2(0.0265, 0.160),
		Vector2(0.0315, 0.168),
		Vector2(0.0315, 0.184),
		Vector2(0.0260, 0.192),
		Vector2(0.0245, 0.265),
		Vector2(0.0310, 0.315),
		Vector2(0.0425, 0.365),
		Vector2(0.0560, 0.402),
		Vector2(0.0640, 0.418),
		Vector2(0.0600, 0.428),
		Vector2(0.0500, 0.424),
		Vector2(0.0460, 0.414),
	], 16, barrel_xf)
	# Decorative brass barrel clamping bands & ramrod tip cap.
	_append_lathe(st_brass, [
		Vector2(0.030, 0.108), Vector2(0.0335, 0.112), Vector2(0.0335, 0.132), Vector2(0.030, 0.136),
	], 10, barrel_xf)
	_append_lathe(st_brass, [
		Vector2(0.0255, 0.232), Vector2(0.0295, 0.236), Vector2(0.0295, 0.258), Vector2(0.0255, 0.262),
	], 12, barrel_xf)
	_append_lathe(st_brass, [
		Vector2(0.007, 0.195), Vector2(0.009, 0.200), Vector2(0.009, 0.218), Vector2(0.0, 0.220),
	], 8, ram_xf)
	# Heavy brass shoulder buttplate.
	_append_beveled_box(st_brass, Vector3(0.050, 0.120, 0.015), 0.004,
		Transform3D(Basis(Vector3.RIGHT, 0.16), Vector3(0.0, -0.090, 0.226)))
	# Starboard brass flintlock lockplate.
	_append_beveled_box(st_brass, Vector3(0.009, 0.034, 0.092), 0.0025,
		Transform3D(Basis.IDENTITY, Vector3(0.026, 0.044, -0.065)))
	# Sweeping brass trigger guard bow beneath wrist/breech.
	_append_tube(st_brass, [
		Vector3(0.0, 0.014, 0.004),
		Vector3(0.0, -0.022, -0.028),
		Vector3(0.0, -0.020, -0.086),
		Vector3(0.0, 0.018, -0.114),
	], 0.0052, 6, true)
	st_brass.generate_normals()
	root.add_child(_make_mesh_node("BrassBarrel", st_brass.commit(), _make_mat(COL_BRASS, 0.25, 0.88)))

	# Deep soot-darkened inner bell funnel bore (wound downward along -Y so normals face out the muzzle).
	var bore_mesh := _lathe_mesh([
		Vector2(0.049, 0.422),
		Vector2(0.033, 0.386),
		Vector2(0.020, 0.340),
		Vector2(0.0, 0.330),
	], 14, barrel_xf)
	root.add_child(_make_mesh_node("BarrelBore", bore_mesh, _make_mat(Color(0.06, 0.06, 0.07), 0.92, 0.15, Color.BLACK, 0.0, false, &"none")))

	# Forged-iron flintlock hammer/cock, flint clamp, flash pan, upright steel frizzen & trigger.
	var st_iron := SurfaceTool.new()
	st_iron.begin(Mesh.PRIMITIVE_TRIANGLES)
	_append_tube(st_iron, [
		Vector3(0.031, 0.050, -0.044),
		Vector3(0.036, 0.094, -0.038),
		Vector3(0.031, 0.108, -0.064),
	], 0.0072, 6, true)
	_append_beveled_box(st_iron, Vector3(0.012, 0.014, 0.018), 0.002,
		Transform3D(Basis(Vector3.RIGHT, 0.35), Vector3(0.031, 0.104, -0.072)))
	# Flash pan & upright steel frizzen ahead of the hammer.
	_append_beveled_box(st_iron, Vector3(0.014, 0.012, 0.022), 0.002,
		Transform3D(Basis.IDENTITY, Vector3(0.030, 0.055, -0.088)))
	_append_beveled_box(st_iron, Vector3(0.011, 0.036, 0.016), 0.002,
		Transform3D(Basis(Vector3.RIGHT, -0.15), Vector3(0.031, 0.076, -0.098)))
	# Forged-iron trigger blade inside the brass guard.
	_append_beveled_box(st_iron, Vector3(0.006, 0.028, 0.008), 0.001,
		Transform3D(Basis(Vector3.RIGHT, -0.32), Vector3(0.0, 0.002, -0.056)))
	# Iron breech tang strip atop wrist.
	_append_beveled_box(st_iron, Vector3(0.016, 0.008, 0.052), 0.002,
		Transform3D(Basis(Vector3.RIGHT, 0.22), Vector3(0.0, 0.068, -0.012)))
	st_iron.generate_normals()
	root.add_child(_make_mesh_node("FlintlockMechanism", st_iron.commit(), _make_mat(COL_IRON, 0.38, 0.80)))
	return root


## 3. Compass: ornate brass case, ivory rose dial, hinged lid & live-rotating `Needle`.
static func _build_compass() -> Node3D:
	var root := Node3D.new()
	root.name = "Tool_Compass"

	# Turned brass pocket-compass body, scalloped rim, open hinged lid & lanyard ring.
	var st_brass := SurfaceTool.new()
	st_brass.begin(Mesh.PRIMITIVE_TRIANGLES)
	_append_lathe(st_brass, [
		Vector2(0.0, -0.024),
		Vector2(0.058, -0.024),
		Vector2(0.072, -0.012),
		Vector2(0.075, 0.006),
		Vector2(0.068, 0.018),
		Vector2(0.059, 0.018),
		Vector2(0.057, 0.004),
		Vector2(0.0, 0.004),
	], 18)
	# Hinged brass lid opened back toward -Z (north rim).
	var lid_xf := Transform3D(Basis(Vector3.RIGHT, -1.78), Vector3(0.0, 0.016, -0.072))
	_append_lathe(st_brass, [
		Vector2(0.0, 0.0),
		Vector2(0.068, 0.0),
		Vector2(0.072, 0.010),
		Vector2(0.058, 0.016),
		Vector2(0.0, 0.018),
	], 16, lid_xf * Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, 0.072)))
	# Brass lanyard ring at +Z (bottom near thumb).
	var ring_pts: Array[Vector3] = []
	for i in 13:
		var a := float(i) / 12.0 * TAU
		ring_pts.append(Vector3(cos(a) * 0.018, -0.004, 0.090 + sin(a) * 0.018))
	_append_tube(st_brass, ring_pts, 0.004, 6, false)
	st_brass.generate_normals()
	root.add_child(_make_mesh_node("BrassCase", st_brass.commit(), _make_mat(COL_BRASS, 0.36, 0.82)))

	# Warm antique parchment dial face with high roughness (0.88) to eliminate white specular glare.
	var dial_mesh := _lathe_mesh([
		Vector2(0.0, 0.004),
		Vector2(0.058, 0.004),
		Vector2(0.058, 0.008),
		Vector2(0.0, 0.008),
	], 18)
	root.add_child(_make_mesh_node("DialFace", dial_mesh, _make_mat(Color(0.76, 0.67, 0.49), 0.88, 0.0, Color.BLACK, 0.0, false, &"none")))

	# High-contrast dark navy-ink dial rings, cardinal/intercardinal ticks & wind-rose lines.
	var st_ticks := SurfaceTool.new()
	st_ticks.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Outer graduated bezel ink ring & inner rose ring.
	_append_lathe(st_ticks, [
		Vector2(0.0525, 0.0082),
		Vector2(0.0565, 0.0082),
		Vector2(0.0565, 0.0095),
		Vector2(0.0525, 0.0095),
	], 24)
	_append_lathe(st_ticks, [
		Vector2(0.024, 0.0082),
		Vector2(0.0265, 0.0082),
		Vector2(0.0265, 0.0092),
		Vector2(0.024, 0.0092),
	], 18)
	# E/S/W major ticks, NE/SE/SW/NW minor ticks, and delicate inner rose cross-bars.
	for i in range(1, 8):
		var a := float(i) * PI * 0.25
		var is_cardinal := (i % 2 == 0)
		var len_t := 0.0145 if is_cardinal else 0.0095
		var wid_t := 0.0048 if is_cardinal else 0.0030
		var rad := 0.0465
		var xf := Transform3D(Basis(Vector3.UP, a), Vector3(sin(a) * rad, 0.0094, -cos(a) * rad))
		_append_beveled_box(st_ticks, Vector3(wid_t, 0.0022, len_t), 0.0004, xf)
	for i in 4:
		var a := float(i) * PI * 0.5
		var xf := Transform3D(Basis(Vector3.UP, a), Vector3(0.0, 0.0089, 0.0))
		_append_beveled_box(st_ticks, Vector3(0.0022, 0.0014, 0.050), 0.0003, xf)
	st_ticks.generate_normals()
	root.add_child(_make_mesh_node("DialTicks", st_ticks.commit(), _make_mat(Color(0.11, 0.14, 0.22), 0.78, 0.08, Color.BLACK, 0.0, false, &"none")))

	# Bold deep-crimson North cardinal wedge & flanking chevron at -Z rim.
	var st_north := SurfaceTool.new()
	st_north.begin(Mesh.PRIMITIVE_TRIANGLES)
	_append_beveled_box(st_north, Vector3(0.0072, 0.0026, 0.0165), 0.0005,
		Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0096, -0.0455)))
	_append_beveled_box(st_north, Vector3(0.0135, 0.0022, 0.0042), 0.0004,
		Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0094, -0.0510)))
	st_north.generate_normals()
	root.add_child(_make_mesh_node("NorthMarker", st_north.commit(), _make_mat(Color(0.72, 0.10, 0.09), 0.72, 0.05, Color.BLACK, 0.0, false, &"none")))

	# Live rotating `Needle` node (local -Z is the crimson North arrow!).
	var needle := Node3D.new()
	needle.name = "Needle"
	needle.position = Vector3(0.0, 0.013, 0.0)
	root.add_child(needle)

	# North crimson diamond half (-Z) with rich saturated paint contrast.
	var n_st := SurfaceTool.new()
	n_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_append_diamond_needle(n_st, -0.048, 0.0, 0.0095, 0.004)
	n_st.generate_normals()
	needle.add_child(_make_mesh_node("NorthTip", n_st.commit(),
		_make_mat(Color(0.74, 0.08, 0.07), 0.42, 0.16, Color(0.55, 0.06, 0.05), 0.14)))

	# South blued-steel counterweight tail (+Z) for unmistakable contrast against parchment dial.
	var s_st := SurfaceTool.new()
	s_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_append_diamond_needle(s_st, 0.042, 0.0, 0.0085, 0.0038)
	s_st.generate_normals()
	needle.add_child(_make_mesh_node("SouthTail", s_st.commit(), _make_mat(Color(0.16, 0.21, 0.30), 0.34, 0.72)))

	# Gleaming brass center pivot cap.
	var pin_mesh := _lathe_mesh([
		Vector2(0.0, -0.002),
		Vector2(0.0075, -0.002),
		Vector2(0.0075, 0.004),
		Vector2(0.0, 0.0055),
	], 10)
	needle.add_child(_make_mesh_node("CenterPin", pin_mesh, _make_mat(COL_GOLD_BRIGHT, 0.28, 0.86)))

	# Ultra-clear subtle curved watch crystal (low alpha & specular so dial never washes out).
	var glass_mesh := _lathe_mesh([
		Vector2(0.058, 0.016),
		Vector2(0.044, 0.022),
		Vector2(0.022, 0.025),
		Vector2(0.0, 0.026),
	], 16)
	var crystal_mat := _make_mat(Color(0.88, 0.93, 0.96, 0.08), 0.22, 0.04, Color.BLACK, 0.0, true)
	crystal_mat.metallic_specular = 0.22
	root.add_child(_make_mesh_node("CrystalDome", glass_mesh, crystal_mat))
	return root


## 4. Spyglass: 3-stage telescoping brass & stitched-leather telescope (-Z axis).
static func _build_spyglass() -> Node3D:
	var root := Node3D.new()
	root.name = "Tool_Spyglass"
	var rot_z := Basis(Vector3.RIGHT, -PI * 0.5)  # maps lathe +Y to -Z forward

	# Stage 0: leather-wrapped main barrel grip.
	var leather_mesh := _lathe_mesh([
		Vector2(0.026, -0.08),
		Vector2(0.030, -0.075),
		Vector2(0.034, 0.115),
		Vector2(0.030, 0.120),
	], 14, Transform3D(rot_z, Vector3.ZERO))
	root.add_child(_make_mesh_node("LeatherGrip", leather_mesh, _make_mat(COL_LEATHER, 0.72, 0.06)))

	# Stage 0 brass eyepiece & front collar ring.
	var st_b0 := SurfaceTool.new()
	st_b0.begin(Mesh.PRIMITIVE_TRIANGLES)
	_append_lathe(st_b0, [
		Vector2(0.0, -0.118),
		Vector2(0.024, -0.118),
		Vector2(0.028, -0.106),
		Vector2(0.024, -0.092),
		Vector2(0.032, -0.082),
		Vector2(0.032, -0.068),
		Vector2(0.028, -0.068),
	], 14, Transform3D(rot_z, Vector3.ZERO))
	_append_lathe(st_b0, [
		Vector2(0.031, 0.105),
		Vector2(0.038, 0.110),
		Vector2(0.038, 0.132),
		Vector2(0.031, 0.135),
	], 14, Transform3D(rot_z, Vector3.ZERO))
	st_b0.generate_normals()
	root.add_child(_make_mesh_node("BrassEyepiece", st_b0.commit(), _make_mat(COL_BRASS, 0.24, 0.88)))

	# Telescoping Stages 1 & 2 inside `DrawTubes` child.
	var draw_tubes := Node3D.new()
	draw_tubes.name = "DrawTubes"
	root.add_child(draw_tubes)

	var st_tubes := SurfaceTool.new()
	st_tubes.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Stage 1 mid draw tube (starts at y = -0.06 inside Stage 0 so full extension has zero gap).
	_append_lathe(st_tubes, [
		Vector2(0.025, -0.06),
		Vector2(0.027, 0.115),
		Vector2(0.028, 0.255),
		Vector2(0.033, 0.260),
		Vector2(0.033, 0.278),
		Vector2(0.026, 0.280),
	], 14, Transform3D(rot_z, Vector3.ZERO))
	# Stage 2 front draw tube & flared brass objective sun-hood.
	_append_lathe(st_tubes, [
		Vector2(0.022, 0.268),
		Vector2(0.024, 0.375),
		Vector2(0.040, 0.398),
		Vector2(0.042, 0.445),
		Vector2(0.036, 0.445),
		Vector2(0.034, 0.415),
		Vector2(0.0, 0.415),
	], 14, Transform3D(rot_z, Vector3.ZERO))
	st_tubes.generate_normals()
	draw_tubes.add_child(_make_mesh_node("TelescopingBrass", st_tubes.commit(), _make_mat(COL_BRASS, 0.22, 0.90)))

	# Deep sea-blue objective glass lens.
	var lens_mesh := _lathe_mesh([
		Vector2(0.0, 0.422),
		Vector2(0.034, 0.418),
		Vector2(0.034, 0.412),
		Vector2(0.0, 0.412),
	], 14, Transform3D(rot_z, Vector3.ZERO))
	draw_tubes.add_child(_make_mesh_node("ObjectiveLens", lens_mesh, _make_mat(COL_LENS, 0.08, 0.25, Color(0.12, 0.26, 0.40), 0.25, true)))
	return root


## 5. Lantern: brass-caged maritime oil lantern with glowing glass flame & real OmniLight3D.
static func _build_lantern() -> Node3D:
	var root := Node3D.new()
	root.name = "Tool_Lantern"

	# Grip sits at top carry handle; lantern body hangs below (-Y).
	var st_brass := SurfaceTool.new()
	st_brass.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Heavy base oil reservoir.
	_append_lathe(st_brass, [
		Vector2(0.0, -0.345),
		Vector2(0.084, -0.345),
		Vector2(0.092, -0.325),
		Vector2(0.076, -0.292),
		Vector2(0.068, -0.280),
		Vector2(0.0, -0.280),
	], 12)
	# Tiered chimney hood above glass cage.
	_append_lathe(st_brass, [
		Vector2(0.0, -0.105),
		Vector2(0.086, -0.105),
		Vector2(0.090, -0.092),
		Vector2(0.056, -0.055),
		Vector2(0.044, -0.030),
		Vector2(0.052, -0.022),
		Vector2(0.0, -0.015),
	], 12)
	# Four protective cage ribs + mid guard ring.
	for i in 4:
		var a := float(i) * PI * 0.5 + PI * 0.25
		var p_bot := Vector3(cos(a) * 0.078, -0.290, sin(a) * 0.078)
		var p_mid := Vector3(cos(a) * 0.086, -0.195, sin(a) * 0.086)
		var p_top := Vector3(cos(a) * 0.080, -0.100, sin(a) * 0.080)
		_append_tube(st_brass, [p_bot, p_mid, p_top], 0.006, 6, true)
	var mid_ring: Array[Vector3] = []
	for i in 13:
		var a := float(i) / 12.0 * TAU
		mid_ring.append(Vector3(cos(a) * 0.085, -0.195, sin(a) * 0.085))
	_append_tube(st_brass, mid_ring, 0.005, 6, false)
	# Curved top carry bail handle passing through origin grip.
	var bail_pts: Array[Vector3] = []
	for i in 11:
		var u := float(i) / 10.0
		var a := lerpf(-PI * 0.5, PI * 0.5, u)
		bail_pts.append(Vector3(sin(a) * 0.055, -0.038 + cos(a) * 0.052, 0.0))
	_append_tube(st_brass, bail_pts, 0.007, 6, true)
	st_brass.generate_normals()
	root.add_child(_make_mesh_node("BrassCage", st_brass.commit(), _make_mat(COL_BRASS, 0.30, 0.84)))

	# Glowing faceted amber glass cylinder (`GlassCore` with unique material).
	var glass_mesh := _lathe_mesh([
		Vector2(0.056, -0.280),
		Vector2(0.068, -0.235),
		Vector2(0.070, -0.155),
		Vector2(0.058, -0.105),
	], 8)
	var glass_mat := _make_mat(COL_GLASS_LIT, 0.16, 0.05, Color(1.0, 0.64, 0.20), 2.2, true)
	root.add_child(_make_mesh_node("GlassCore", glass_mesh, glass_mat))

	# Bright sculpted teardrop flame inside.
	var flame_mesh := _lathe_mesh([
		Vector2(0.0, -0.242),
		Vector2(0.022, -0.228),
		Vector2(0.018, -0.196),
		Vector2(0.007, -0.166),
		Vector2(0.0, -0.152),
	], 8)
	var flame_mat := _make_mat(COL_FLAME, 0.2, 0.0, Color(1.0, 0.82, 0.30), 4.5)
	flame_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	root.add_child(_make_mesh_node("Flame", flame_mesh, flame_mat))

	# Real warm OmniLight3D illuminating dark holds, caves, and nights!
	var light := OmniLight3D.new()
	light.name = "LanternLight"
	light.position = Vector3(0.0, -0.195, 0.0)
	light.light_color = Color(1.0, 0.72, 0.34)
	light.light_energy = 2.4
	light.omni_range = 10.5
	light.omni_attenuation = 1.35
	light.shadow_enabled = false
	root.add_child(light)
	return root


## 6. Held Treasure Map: wooden-roller parchment scroll with live ImageTexture.
static func _build_map() -> Node3D:
	var root := Node3D.new()
	root.name = "Tool_Map"

	# Top and bottom turned oak scroll rollers with brass finials.
	var st_wood := SurfaceTool.new()
	st_wood.begin(Mesh.PRIMITIVE_TRIANGLES)
	var st_brass := SurfaceTool.new()
	st_brass.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rot_x := Basis(Vector3.BACK, PI * 0.5)  # maps lathe +Y to +X
	for ry in [-0.155, 0.155]:
		_append_lathe(st_wood, [
			Vector2(0.0, -0.195),
			Vector2(0.014, -0.192),
			Vector2(0.015, 0.192),
			Vector2(0.0, 0.195),
		], 10, Transform3D(rot_x, Vector3(0.0, ry, -0.006)))
		for sx: float in [-1.0, 1.0]:
			var fx: float = sx * 0.202
			_append_lathe(st_brass, [
				Vector2(0.0, -0.016),
				Vector2(0.018, -0.010),
				Vector2(0.020, 0.006),
				Vector2(0.011, 0.018),
				Vector2(0.0, 0.022),
			], 10, Transform3D(Basis(Vector3.BACK, -sx * PI * 0.5), Vector3(fx, ry, -0.006)))
	st_wood.generate_normals()
	st_brass.generate_normals()
	root.add_child(_make_mesh_node("ScrollRollers", st_wood.commit(), _make_mat(COL_OAK_DARK, 0.74, 0.04)))
	root.add_child(_make_mesh_node("RollerFinials", st_brass.commit(), _make_mat(COL_BRASS, 0.28, 0.85)))

	# Gently bowed front parchment sheet (`MapSurface`) facing +Z with clean [0..1] UVs.
	var front_mesh := _build_parchment_sheet_mesh(0.35, 0.30, 0.016, false)
	var default_tex := MapPainter.render_treasure_map("Cutlass Cay", PackedVector2Array(), Vector2(26.0, -18.0), 120.0)
	var front_mat := _make_mat(Color.WHITE, 0.78, 0.0, Color.BLACK, 0.0, false, &"none")
	front_mat.albedo_texture = default_tex
	root.add_child(_make_mesh_node("MapSurface", front_mesh, front_mat))

	# Plain aged parchment backing facing -Z so third-person onlookers see a real scroll!
	var back_mesh := _build_parchment_sheet_mesh(0.35, 0.30, 0.016, true)
	root.add_child(_make_mesh_node("MapBack", back_mesh, _make_mat(COL_PARCHMENT_BACK, 0.85, 0.0, Color.BLACK, 0.0, false, &"none")))
	return root


## 7. Shovel: heavy timber-handled iron spade with beveled curved blade.
static func _build_shovel() -> Node3D:
	var root := Node3D.new()
	root.name = "Tool_Shovel"

	# Timber shaft + chunky D-grip handle at top (+Y), iron blade down (-Y) or up (+Y).
	# Held upright with spade blade extending upward/forward (+Y) for iconic first-person silhouette!
	var st_wood := SurfaceTool.new()
	st_wood.begin(Mesh.PRIMITIVE_TRIANGLES)
	_append_lathe(st_wood, [
		Vector2(0.0, -0.30),
		Vector2(0.018, -0.295),
		Vector2(0.021, 0.0),
		Vector2(0.019, 0.38),
		Vector2(0.0, 0.39),
	], 10)
	# D-grip pommel crossbar at lower end (-Y).
	_append_beveled_box(st_wood, Vector3(0.115, 0.024, 0.026), 0.005, Transform3D(Basis.IDENTITY, Vector3(0.0, -0.375, 0.0)))
	_append_beveled_box(st_wood, Vector3(0.020, 0.090, 0.022), 0.004, Transform3D(Basis.IDENTITY, Vector3(-0.048, -0.335, 0.0)))
	_append_beveled_box(st_wood, Vector3(0.020, 0.090, 0.022), 0.004, Transform3D(Basis.IDENTITY, Vector3(0.048, -0.335, 0.0)))
	st_wood.generate_normals()
	root.add_child(_make_mesh_node("TimberHandle", st_wood.commit(), _make_mat(COL_OAK_WARM, 0.80, 0.03)))

	# Riveted iron socket ferrule + curved beveled iron spade blade.
	var st_iron := SurfaceTool.new()
	st_iron.begin(Mesh.PRIMITIVE_TRIANGLES)
	_append_lathe(st_iron, [
		Vector2(0.020, 0.28),
		Vector2(0.026, 0.29),
		Vector2(0.028, 0.42),
		Vector2(0.022, 0.44),
	], 10)
	# Slightly cupped curved iron spade blade lofted from shoulder (y=0.41) to pointed tip (y=0.72).
	var spade_rings: Array = []
	var steps := 7
	for i in range(steps + 1):
		var t := float(i) / float(steps)
		var y := lerpf(0.41, 0.73, t)
		var hw := lerpf(0.115, 0.012, pow(t, 1.75))
		var thick := lerpf(0.012, 0.004, t)
		var cup := 0.020 * (1.0 - t * 0.6)
		var z_off := -0.014 * sin(t * PI * 0.7)
		spade_rings.append([
			Vector3(-hw, y, z_off - cup),
			Vector3(0.0, y, z_off + thick * 0.6),
			Vector3(hw, y, z_off - cup),
			Vector3(hw * 0.92, y, z_off - cup + thick),
			Vector3(0.0, y, z_off + thick * 1.6),
			Vector3(-hw * 0.92, y, z_off - cup + thick),
		])
	_append_loft(st_iron, spade_rings, true)
	st_iron.generate_normals()
	root.add_child(_make_mesh_node("SpadeBlade", st_iron.commit(), _make_mat(COL_IRON, 0.44, 0.76)))
	return root


## 8. Bucket: iron-banded oak-stave bucket with toggleable `WaterFill` disc.
static func _build_bucket() -> Node3D:
	var root := Node3D.new()
	root.name = "Tool_Bucket"

	# Grip sits at the curved bail handle (0,0,0); bucket hangs directly below (-Y).
	var st_wood := SurfaceTool.new()
	st_wood.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Outer & inner wooden stave shell (thick visible rim!).
	_append_lathe(st_wood, [
		Vector2(0.0, -0.355),
		Vector2(0.095, -0.355),
		Vector2(0.102, -0.340),
		Vector2(0.136, -0.115),
		Vector2(0.120, -0.115),
		Vector2(0.088, -0.335),
		Vector2(0.0, -0.335),
	], 12)
	# Wooden handle grip sleeve centered around origin.
	_append_lathe(st_wood, [
		Vector2(0.0, -0.044),
		Vector2(0.014, -0.040),
		Vector2(0.016, 0.0),
		Vector2(0.014, 0.040),
		Vector2(0.0, 0.044),
	], 8, Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3.ZERO))
	st_wood.generate_normals()
	root.add_child(_make_mesh_node("OakStaves", st_wood.commit(), _make_mat(COL_OAK_WARM, 0.82, 0.03)))

	# Two forged iron barrel hoops + curved iron bail wire.
	var st_iron := SurfaceTool.new()
	st_iron.begin(Mesh.PRIMITIVE_TRIANGLES)
	_append_lathe(st_iron, [
		Vector2(0.103, -0.318),
		Vector2(0.110, -0.315),
		Vector2(0.114, -0.285),
		Vector2(0.108, -0.282),
	], 12)
	_append_lathe(st_iron, [
		Vector2(0.127, -0.175),
		Vector2(0.136, -0.172),
		Vector2(0.140, -0.140),
		Vector2(0.133, -0.137),
	], 12)
	# Curved bail arch from rim lugs up through origin grip.
	var bail_pts: Array[Vector3] = []
	for i in 13:
		var u := float(i) / 12.0
		var a := lerpf(-PI * 0.5, PI * 0.5, u)
		bail_pts.append(Vector3(sin(a) * 0.138, -0.128 + cos(a) * 0.128, 0.0))
	_append_tube(st_iron, bail_pts, 0.0055, 6, true)
	st_iron.generate_normals()
	root.add_child(_make_mesh_node("IronBands", st_iron.commit(), _make_mat(COL_IRON, 0.46, 0.74)))

	# Toggleable `WaterFill` disc inside bucket near top rim (hidden when empty).
	var water_mesh := _lathe_mesh([
		Vector2(0.0, -0.148),
		Vector2(0.118, -0.148),
		Vector2(0.118, -0.142),
		Vector2(0.0, -0.140),
	], 12)
	var water_mi := _make_mesh_node("WaterFill", water_mesh, _make_mat(COL_WATER, 0.12, 0.08, Color(0.06, 0.24, 0.24), 0.35, true))
	water_mi.visible = false
	root.add_child(water_mi)
	return root


## 9. Planks: thick weathered oak repair planks with forged iron nails & rope lashing.
static func _build_planks() -> Node3D:
	var root := Node3D.new()
	root.name = "Tool_Planks"

	var st_wood := SurfaceTool.new()
	st_wood.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Two staggered chunky beveled oak planks.
	_append_beveled_box(st_wood, Vector3(0.155, 0.54, 0.030), 0.006, Transform3D(Basis(Vector3.UP, 0.04), Vector3(0.0, 0.10, 0.0)))
	_append_beveled_box(st_wood, Vector3(0.142, 0.48, 0.028), 0.006, Transform3D(Basis(Vector3.UP, -0.06) * Basis(Vector3.BACK, 0.04), Vector3(0.012, 0.08, -0.032)))
	st_wood.generate_normals()
	root.add_child(_make_mesh_node("OakPlanks", st_wood.commit(), _make_mat(COL_OAK_LIGHT, 0.84, 0.02)))

	# Iron nail heads & protruding nail shanks along ends of the front plank.
	var st_iron := SurfaceTool.new()
	st_iron.begin(Mesh.PRIMITIVE_TRIANGLES)
	var nail_coords := [
		Vector3(-0.045, 0.31, 0.016),
		Vector3(0.042, 0.32, 0.016),
		Vector3(-0.042, -0.11, 0.016),
		Vector3(0.044, -0.10, 0.016),
	]
	for np: Vector3 in nail_coords:
		_append_lathe(st_iron, [
			Vector2(0.0, -0.004),
			Vector2(0.0045, -0.004),
			Vector2(0.0045, 0.010),
			Vector2(0.010, 0.012),
			Vector2(0.010, 0.016),
			Vector2(0.0, 0.017),
		], 6, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), np))
	st_iron.generate_normals()
	root.add_child(_make_mesh_node("IronNails", st_iron.commit(), _make_mat(COL_IRON, 0.42, 0.78)))

	# Hemp rope lashing band wrapping around the grip center.
	var st_rope := SurfaceTool.new()
	st_rope.begin(Mesh.PRIMITIVE_TRIANGLES)
	for ry in [-0.014, 0.0, 0.014]:
		_append_beveled_box(st_rope, Vector3(0.172, 0.011, 0.072), 0.004, Transform3D(Basis.IDENTITY, Vector3(0.005, ry, -0.015)))
	st_rope.generate_normals()
	root.add_child(_make_mesh_node("RopeLashing", st_rope.commit(), _make_mat(COL_ROPE, 0.90, 0.0, Color.BLACK, 0.0, false, &"rope")))
	return root


## 10. Tankard: banded pewter/oak grog mug with chunky handle and frothy foam top.
static func _build_tankard() -> Node3D:
	var root := Node3D.new()
	root.name = "Tool_Tankard"

	# Tapered staved oak barrel mug centered cleanly in front of handle grip.
	var mug_xform := Transform3D(Basis.IDENTITY, Vector3(0.0, -0.02, -0.095))
	var mug_mesh := _lathe_mesh([
		Vector2(0.0, -0.088),
		Vector2(0.074, -0.088),
		Vector2(0.080, -0.060),
		Vector2(0.070, 0.088),
		Vector2(0.056, 0.088),
		Vector2(0.058, 0.055),
		Vector2(0.0, 0.055),
	], 12, mug_xform)
	root.add_child(_make_mesh_node("OakMug", mug_mesh, _make_mat(COL_OAK_DARK, 0.74, 0.05)))

	# Banded pewter/brass hoops and curved sturdy grip handle centered at origin.
	var st_metal := SurfaceTool.new()
	st_metal.begin(Mesh.PRIMITIVE_TRIANGLES)
	_append_lathe(st_metal, [
		Vector2(0.076, -0.072),
		Vector2(0.084, -0.068),
		Vector2(0.084, -0.044),
		Vector2(0.077, -0.040),
	], 12, mug_xform)
	_append_lathe(st_metal, [
		Vector2(0.070, 0.052),
		Vector2(0.077, 0.056),
		Vector2(0.076, 0.082),
		Vector2(0.068, 0.086),
	], 12, mug_xform)
	_append_tube(st_metal, [
		Vector3(0.0, 0.048, -0.032),
		Vector3(0.0, 0.052, 0.008),
		Vector3(0.0, 0.000, 0.018),
		Vector3(0.0, -0.052, 0.006),
		Vector3(0.0, -0.052, -0.028),
	], 0.011, 8, true)
	st_metal.generate_normals()
	root.add_child(_make_mesh_node("PewterBands", st_metal.commit(), _make_mat(COL_PEWTER, 0.34, 0.78)))

	# Dark amber grog pool + overflowing frothy cream foam head (`FoamTop`).
	var grog_mesh := _lathe_mesh([Vector2(0.0, 0.060), Vector2(0.058, 0.060), Vector2(0.058, 0.064), Vector2(0.0, 0.064)], 10, mug_xform)
	root.add_child(_make_mesh_node("GrogLiquid", grog_mesh, _make_mat(COL_GROG, 0.16, 0.05)))

	var st_foam := SurfaceTool.new()
	st_foam.begin(Mesh.PRIMITIVE_TRIANGLES)
	var puffs := [
		[Vector3(0.0, 0.078, -0.095), 0.052, 0.030],
		[Vector3(-0.034, 0.072, -0.105), 0.034, 0.024],
		[Vector3(0.032, 0.074, -0.085), 0.032, 0.024],
		[Vector3(0.008, 0.086, -0.112), 0.030, 0.022],
		[Vector3(-0.044, 0.048, -0.062), 0.018, 0.036],  # frothy drip down the rim!
	]
	for pf in puffs:
		var c: Vector3 = pf[0]
		var r: float = pf[1]
		var h: float = pf[2]
		_append_lathe(st_foam, [
			Vector2(0.0, -h * 0.5),
			Vector2(r * 0.85, -h * 0.25),
			Vector2(r, 0.05 * h),
			Vector2(r * 0.72, h * 0.55),
			Vector2(0.0, h * 0.85),
		], 8, Transform3D(Basis.IDENTITY, c))
	st_foam.generate_normals()
	root.add_child(_make_mesh_node("FoamTop", st_foam.commit(), _make_mat(COL_FOAM, 0.86, 0.0, Color.BLACK, 0.0, false, &"none")))
	return root


## 11. Instrument: hexagonal mahogany & brass pirate concertina accordion!
static func _build_instrument() -> Node3D:
	var root := Node3D.new()
	root.name = "Tool_Instrument"

	# Pleated zig-zag hexagonal bellows centered at origin, expanding along X.
	var rot_x := Basis(Vector3.BACK, PI * 0.5)
	var b_prof: Array[Vector2] = []
	var pleats := 5
	for i in range(pleats * 2 + 1):
		var u := float(i) / float(pleats * 2)
		var x_pos := lerpf(-0.085, 0.085, u)
		var r := 0.088 if (i % 2 == 1) else 0.068
		b_prof.append(Vector2(r, x_pos))
	var bellows_mesh := _lathe_mesh(b_prof, 6, Transform3D(rot_x, Vector3.ZERO))
	root.add_child(_make_mesh_node("Bellows", bellows_mesh, _make_mat(COL_BELLOWS_RED, 0.74, 0.04, Color.BLACK, 0.0, false, &"cloth")))

	# Left & Right hexagonal walnut endplates with brass grill bezels & ivory buttons.
	for side_pair in [["LeftEnd", -1.0], ["RightEnd", 1.0]]:
		var end_name: String = side_pair[0]
		var sx: float = side_pair[1]
		var end_node := Node3D.new()
		end_node.name = end_name
		end_node.position = Vector3(sx * 0.085, 0.0, 0.0)
		root.add_child(end_node)

		var end_rot := Basis(Vector3.BACK, -sx * PI * 0.5)
		var wood_plate := _lathe_mesh([
			Vector2(0.0, 0.0),
			Vector2(0.098, 0.0),
			Vector2(0.104, 0.014),
			Vector2(0.096, 0.028),
			Vector2(0.0, 0.028),
		], 6, Transform3D(end_rot, Vector3.ZERO))
		end_node.add_child(_make_mesh_node("WoodPlate", wood_plate, _make_mat(COL_WALNUT, 0.58, 0.05)))

		# Ornate brass sound-plate trim & leather strap bracket.
		var brass_trim := _lathe_mesh([
			Vector2(0.040, 0.027),
			Vector2(0.082, 0.027),
			Vector2(0.082, 0.032),
			Vector2(0.040, 0.032),
		], 6, Transform3D(end_rot, Vector3.ZERO))
		end_node.add_child(_make_mesh_node("BrassInlay", brass_trim, _make_mat(COL_BRASS, 0.25, 0.86)))

		# Cluster of pearl-ivory concertina buttons.
		var st_btn := SurfaceTool.new()
		st_btn.begin(Mesh.PRIMITIVE_TRIANGLES)
		for bi in 6:
			var a := float(bi) / 6.0 * TAU
			var pos := Vector3(sx * 0.031, cos(a) * 0.042, sin(a) * 0.042)
			_append_lathe(st_btn, [
				Vector2(0.0, 0.0),
				Vector2(0.008, 0.0),
				Vector2(0.008, 0.010),
				Vector2(0.0, 0.012),
			], 6, Transform3D(end_rot, pos))
		st_btn.generate_normals()
		end_node.add_child(_make_mesh_node("Buttons", st_btn.commit(), _make_mat(COL_IVORY, 0.45, 0.05)))
	return root


## 12. Hurdy-Gurdy: chunky wooden lute-waisted soundbox, varnished belly, brass wheel cover,
## pegged headstock, ivory keybox buttons, and rotating `"CrankHandle"` (for Barnaby).
static func _build_hurdy_gurdy() -> Node3D:
	var root := Node3D.new()
	root.name = "Tool_HurdyGurdy"

	# Figure-8 hurdy-gurdy soundbox ribs (darker oak), chamfered top & bottom + carved pegbox headstock.
	var st_ribs := SurfaceTool.new()
	st_ribs.begin(Mesh.PRIMITIVE_TRIANGLES)
	var body_segs := 24
	var rib_levels := [
		[-0.064, 0.90],
		[-0.052, 1.00],
		[0.044, 1.00],
		[0.056, 0.93],
	]
	var body_rings: Array = []
	for lv in rib_levels:
		var y: float = float(lv[0])
		var sc: float = float(lv[1])
		var ring: Array = []
		for k in body_segs:
			var a := float(k) / float(body_segs) * TAU
			var cx := cos(a)
			var sz := sin(a)
			var u := (cx + 1.0) * 0.5
			var waist := 1.0 - 0.24 * exp(-pow((u - 0.46) / 0.18, 2.0))
			var half_z := lerpf(0.098, 0.130, u) * waist * sc
			var x := lerpf(-0.175, 0.165, u) * sc
			ring.append(Vector3(x, y, sz * half_z))
		body_rings.append(ring)
	_append_loft(st_ribs, body_rings, true)

	# Carved oak neck block, angled pegbox cheeks & decorative spiral scroll tip along -X.
	_append_beveled_box(st_ribs, Vector3(0.055, 0.062, 0.068), 0.009,
		Transform3D(Basis.IDENTITY, Vector3(-0.188, 0.012, 0.0)))
	_append_beveled_box(st_ribs, Vector3(0.092, 0.048, 0.016), 0.004,
		Transform3D(Basis(Vector3.BACK, -0.14), Vector3(-0.244, 0.018, -0.022)))
	_append_beveled_box(st_ribs, Vector3(0.092, 0.048, 0.016), 0.004,
		Transform3D(Basis(Vector3.BACK, -0.14), Vector3(-0.244, 0.018, 0.022)))
	_append_beveled_box(st_ribs, Vector3(0.090, 0.016, 0.056), 0.004,
		Transform3D(Basis(Vector3.BACK, -0.14), Vector3(-0.244, -0.002, 0.0)))
	var scroll_rot := Basis(Vector3.RIGHT, PI * 0.5)
	_append_lathe(st_ribs, [
		Vector2(0.0, -0.028),
		Vector2(0.024, -0.024),
		Vector2(0.028, 0.0),
		Vector2(0.024, 0.024),
		Vector2(0.0, 0.028),
	], 10, Transform3D(scroll_rot, Vector3(-0.294, 0.024, 0.0)))
	st_ribs.generate_normals()
	root.add_child(_make_mesh_node("SoundboxRibs", st_ribs.commit(), _make_mat(COL_OAK_DARK, 0.72, 0.04)))

	# Warm varnished spruce/maple belly plate inset slightly inside the dark oak binding rim.
	var belly_rings: Array = []
	for lv in [[0.052, 0.89], [0.062, 0.86]]:
		var y: float = float(lv[0])
		var sc: float = float(lv[1])
		var ring: Array = []
		for k in body_segs:
			var a := float(k) / float(body_segs) * TAU
			var cx := cos(a)
			var sz := sin(a)
			var u := (cx + 1.0) * 0.5
			var waist := 1.0 - 0.24 * exp(-pow((u - 0.46) / 0.18, 2.0))
			var half_z := lerpf(0.098, 0.130, u) * waist * sc
			var x := lerpf(-0.175, 0.165, u) * sc
			ring.append(Vector3(x, y, sz * half_z))
		belly_rings.append(ring)
	root.add_child(_make_mesh_node("SoundboardBelly", _loft_mesh(belly_rings, true), _make_mat(COL_OAK_LIGHT, 0.50, 0.03)))

	# Carved dark acoustic soundholes on the varnished belly.
	var st_holes := SurfaceTool.new()
	st_holes.begin(Mesh.PRIMITIVE_TRIANGLES)
	for sz_sign: float in [-1.0, 1.0]:
		_append_lathe(st_holes, [
			Vector2(0.0, 0.060),
			Vector2(0.021, 0.060),
			Vector2(0.021, 0.0645),
			Vector2(0.0, 0.0645),
		], 10, Transform3D(Basis.IDENTITY, Vector3(0.068, 0.0, sz_sign * 0.068)))
	st_holes.generate_normals()
	root.add_child(_make_mesh_node("Soundholes", st_holes.commit(), _make_mat(Color(0.08, 0.05, 0.03), 0.94, 0.02, Color.BLACK, 0.0, false, &"none")))

	# Walnut keybox housing, carved bridge, and tailpiece block.
	var st_keybox := SurfaceTool.new()
	st_keybox.begin(Mesh.PRIMITIVE_TRIANGLES)
	_append_beveled_box(st_keybox, Vector3(0.182, 0.038, 0.066), 0.006,
		Transform3D(Basis.IDENTITY, Vector3(-0.095, 0.078, 0.0)))
	_append_beveled_box(st_keybox, Vector3(0.186, 0.012, 0.072), 0.003,
		Transform3D(Basis.IDENTITY, Vector3(-0.095, 0.099, 0.0)))
	# Carved bridge & tailpiece behind the wheel.
	_append_beveled_box(st_keybox, Vector3(0.016, 0.024, 0.064), 0.003,
		Transform3D(Basis.IDENTITY, Vector3(0.106, 0.072, 0.0)))
	_append_beveled_box(st_keybox, Vector3(0.034, 0.016, 0.058), 0.003,
		Transform3D(Basis.IDENTITY, Vector3(0.138, 0.068, 0.0)))
	st_keybox.generate_normals()
	root.add_child(_make_mesh_node("KeyboxAndBridge", st_keybox.commit(), _make_mat(COL_WALNUT, 0.56, 0.04)))

	# Ivory tangent keybox buttons, rosined wheel rim, and turned tuning-peg handles.
	var st_ivory := SurfaceTool.new()
	st_ivory.begin(Mesh.PRIMITIVE_TRIANGLES)
	for ki in 7:
		var kx := lerpf(-0.168, -0.022, float(ki) / 6.0)
		_append_beveled_box(st_ivory, Vector3(0.014, 0.012, 0.026), 0.0025,
			Transform3D(Basis.IDENTITY, Vector3(kx, 0.070, 0.042)))
	for ki in 4:
		var kx := lerpf(-0.154, -0.046, float(ki) / 3.0)
		_append_beveled_box(st_ivory, Vector3(0.012, 0.011, 0.020), 0.002,
			Transform3D(Basis.IDENTITY, Vector3(kx, 0.084, 0.039)))
	# Cream rosined maple friction wheel visible inside the brass wheel cover.
	var rot_x := Basis(Vector3.BACK, PI * 0.5)
	_append_lathe(st_ivory, [
		Vector2(0.0, -0.014),
		Vector2(0.046, -0.014),
		Vector2(0.048, 0.0),
		Vector2(0.046, 0.014),
		Vector2(0.0, 0.014),
	], 14, Transform3D(rot_x, Vector3(0.052, 0.058, 0.0)))
	# Four pegbox tuning keys jutting cleanly from both sides of the headstock.
	for pi in 4:
		var side := 1.0 if (pi % 2 == 0) else -1.0
		var px := -0.214 - float(pi) * 0.018
		var pz := side * 0.038
		var peg_xf := Transform3D(Basis(Vector3.RIGHT, side * PI * 0.5), Vector3(px, 0.020, pz))
		_append_lathe(st_ivory, [
			Vector2(0.0045, -0.020),
			Vector2(0.0055, 0.006),
			Vector2(0.011, 0.014),
			Vector2(0.010, 0.022),
			Vector2(0.0, 0.024),
		], 8, peg_xf)
	st_ivory.generate_normals()
	root.add_child(_make_mesh_node("KeysAndWheel", st_ivory.commit(), _make_mat(COL_IVORY, 0.44, 0.05)))

	# Ornate brass rosined wheel housing arch, rim trim, and headstock peg ferrules.
	var st_brass := SurfaceTool.new()
	st_brass.begin(Mesh.PRIMITIVE_TRIANGLES)
	for arch_x: float in [0.022, 0.052, 0.082]:
		var arch_pts: Array[Vector3] = []
		for i in 11:
			var a := lerpf(-PI * 0.48, PI * 0.48, float(i) / 10.0)
			arch_pts.append(Vector3(arch_x, 0.060 + cos(a) * 0.058, sin(a) * 0.056))
		_append_tube(st_brass, arch_pts, 0.0068, 6, true)
	# Longitudinal brass spine bars linking the wheel-housing arches.
	for angle_deg: float in [-52.0, 0.0, 52.0]:
		var rad := deg_to_rad(angle_deg)
		var by := 0.060 + cos(rad) * 0.058
		var bz := sin(rad) * 0.056
		_append_tube(st_brass, [Vector3(0.018, by, bz), Vector3(0.086, by, bz)], 0.0062, 6, true)
	# Brass axle boss & rear decorative strap collar.
	_append_lathe(st_brass, [
		Vector2(0.0, -0.012),
		Vector2(0.018, -0.010),
		Vector2(0.020, 0.008),
		Vector2(0.013, 0.016),
		Vector2(0.0, 0.018),
	], 10, Transform3D(rot_x, Vector3(0.162, 0.004, 0.0)))
	# Brass collars around headstock pegs.
	for pi in 4:
		var side := 1.0 if (pi % 2 == 0) else -1.0
		var px := -0.214 - float(pi) * 0.018
		var collar_xf := Transform3D(Basis(Vector3.RIGHT, side * PI * 0.5), Vector3(px, 0.020, side * 0.026))
		_append_lathe(st_brass, [
			Vector2(0.007, 0.0), Vector2(0.009, 0.002), Vector2(0.009, 0.008), Vector2(0.006, 0.010),
		], 8, collar_xf)
	st_brass.generate_normals()
	root.add_child(_make_mesh_node("BrassWheelHousing", st_brass.commit(), _make_mat(COL_BRASS, 0.25, 0.88)))

	# Four taut steel melody & drone strings spanning tailpiece -> wheel -> keybox -> pegbox.
	var st_strings := SurfaceTool.new()
	st_strings.begin(Mesh.PRIMITIVE_TRIANGLES)
	for sz_off: float in [-0.018, -0.006, 0.006, 0.018]:
		_append_tube(st_strings, [
			Vector3(0.145, 0.078, sz_off),
			Vector3(0.052, 0.098, sz_off),
			Vector3(-0.095, 0.096, sz_off),
			Vector3(-0.245, 0.032, sz_off * 0.65),
		], 0.0018, 4, true)
	st_strings.generate_normals()
	root.add_child(_make_mesh_node("Strings", st_strings.commit(), _make_mat(COL_STEEL, 0.26, 0.90)))

	# Rotating `"CrankHandle"` pivot at rear tailpiece axle (+X).
	var crank := Node3D.new()
	crank.name = "CrankHandle"
	crank.position = Vector3(0.168, 0.004, 0.0)
	root.add_child(crank)

	var st_crank_brass := SurfaceTool.new()
	st_crank_brass.begin(Mesh.PRIMITIVE_TRIANGLES)
	_append_tube(st_crank_brass, [
		Vector3(0.0, 0.0, 0.0),
		Vector3(0.020, 0.004, 0.0),
		Vector3(0.032, 0.044, 0.0),
		Vector3(0.042, 0.082, 0.0),
	], 0.0072, 8, true)
	_append_lathe(st_crank_brass, [
		Vector2(0.0, 0.0),
		Vector2(0.014, 0.002),
		Vector2(0.014, 0.012),
		Vector2(0.0, 0.015),
	], 8, Transform3D(rot_x, Vector3(0.094, 0.082, 0.0)))
	st_crank_brass.generate_normals()
	crank.add_child(_make_mesh_node("CrankArm", st_crank_brass.commit(), _make_mat(COL_BRASS, 0.26, 0.88)))

	var knob_mesh := _lathe_mesh([
		Vector2(0.0, 0.0),
		Vector2(0.012, 0.004),
		Vector2(0.018, 0.024),
		Vector2(0.016, 0.048),
		Vector2(0.010, 0.058),
		Vector2(0.0, 0.060),
	], 10, Transform3D(rot_x, Vector3(0.038, 0.082, 0.0)))
	crank.add_child(_make_mesh_node("CrankKnob", knob_mesh, _make_mat(COL_WALNUT, 0.56, 0.05)))
	return root


## 13. Bosun's Whistle: curved brass-and-oak sailor's pipe/whistle with tapered fipple mouthpiece,
## finger holes, brass ferrule rings, nautical buoy & keel, and braided lanyard loop (for Maren).
static func _build_whistle() -> Node3D:
	var root := Node3D.new()
	root.name = "Tool_Whistle"

	# Helper centerline curve running from mouthpiece (+Z) to buoy (-Z) with graceful nautical droop.
	var curve_pt := func(t: float) -> Vector3:
		var z := lerpf(0.145, -0.185, t)
		var y := -0.030 * pow(t, 1.85) + 0.007 * sin(t * PI)
		return Vector3(0.0, y, z)

	# Curved oak sailor's whistle barrel (t in 0.14..0.88).
	var barrel_rings: Array = []
	var barrel_steps := 10
	var barrel_segs := 12
	for i in range(barrel_steps + 1):
		var u := float(i) / float(barrel_steps)
		var t := lerpf(0.14, 0.88, u)
		var c: Vector3 = curve_pt.call(t)
		var r := lerpf(0.0155, 0.0200, u)
		var ring: Array = []
		for k in barrel_segs:
			var a := float(k) / float(barrel_segs) * TAU
			# Wound CW looking along -Z (dT = -Z) so normals face strictly outward.
			ring.append(c + Vector3(-sin(a) * r, cos(a) * r, 0.0))
		barrel_rings.append(ring)
	root.add_child(_make_mesh_node("OakBarrel", _loft_mesh(barrel_rings, true), _make_mat(COL_OAK_WARM, 0.58, 0.04)))

	# Brass mouthpiece beak, ferrule collar rings, resonator buoy, keel fin & lanyard shackle.
	var st_brass := SurfaceTool.new()
	st_brass.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Tapered fipple mouthpiece beak from t = -0.10 (lip tip) to t = 0.16 (barrel collar).
	var mouth_rings: Array = []
	var mouth_specs := [
		[0.178, 0.004, 0.012, 0.0055],
		[0.162, 0.005, 0.014, 0.0085],
		[0.136, 0.006, 0.016, 0.0140],
		[0.102, 0.005, 0.018, 0.0175],
	]
	for ms in mouth_specs:
		var z: float = float(ms[0])
		var yc: float = float(ms[1])
		var rx: float = float(ms[2])
		var ry: float = float(ms[3])
		var ring: Array = []
		for k in 10:
			var a := float(k) / 10.0 * TAU
			ring.append(Vector3(-sin(a) * rx, yc + cos(a) * ry, z))
		mouth_rings.append(ring)
	_append_loft(st_brass, mouth_rings, true)

	# Three turned brass ferrule collar rings wrapping the curved oak barrel.
	for ft: float in [0.16, 0.50, 0.86]:
		var c0: Vector3 = curve_pt.call(ft - 0.026)
		var c1: Vector3 = curve_pt.call(ft + 0.026)
		var cm: Vector3 = (c0 + c1) * 0.5
		var r_base := lerpf(0.0155, 0.0200, (ft - 0.14) / 0.74)
		var r_ring := r_base + 0.0042
		var f_rings: Array = []
		for fstep in [[c0, r_base], [c0.lerp(cm, 0.45), r_ring], [c1.lerp(cm, 0.45), r_ring], [c1, r_base]]:
			var fc: Vector3 = fstep[0]
			var fr: float = float(fstep[1])
			var ring: Array = []
			for k in 12:
				var a := float(k) / 12.0 * TAU
				ring.append(fc + Vector3(-sin(a) * fr, cos(a) * fr, 0.0))
			f_rings.append(ring)
		_append_loft(st_brass, f_rings, false)

	# Classic bosun's-pipe flared brass resonator buoy/bell at the front end (-Z).
	var buoy_center: Vector3 = curve_pt.call(1.0) + Vector3(0.0, -0.004, -0.012)
	_append_lathe(st_brass, [
		Vector2(0.0, -0.028),
		Vector2(0.018, -0.024),
		Vector2(0.030, -0.008),
		Vector2(0.032, 0.010),
		Vector2(0.022, 0.024),
		Vector2(0.012, 0.028),
		Vector2(0.0, 0.028),
	], 14, Transform3D(Basis.IDENTITY, buoy_center))

	# Nautical flat brass keel plate beneath the front barrel & buoy + suspension shackle ring.
	_append_beveled_box(st_brass, Vector3(0.008, 0.044, 0.105), 0.0025,
		Transform3D(Basis(Vector3.RIGHT, 0.16), Vector3(0.0, -0.044, -0.142)))
	var eye_pts: Array[Vector3] = []
	for i in 11:
		var a := float(i) / 10.0 * TAU
		eye_pts.append(Vector3(0.0, -0.072 + sin(a) * 0.012, -0.138 + cos(a) * 0.012))
	_append_tube(st_brass, eye_pts, 0.0032, 6, false)

	# Tiny brass inlay rings framing each of the 6 finger holes on top of the barrel.
	var hole_ts: Array[float] = [0.24, 0.33, 0.42, 0.58, 0.67, 0.76]
	for ht: float in hole_ts:
		var hc: Vector3 = curve_pt.call(ht)
		var r_b := lerpf(0.0155, 0.0200, (ht - 0.14) / 0.74)
		_append_lathe(st_brass, [
			Vector2(0.0042, 0.0),
			Vector2(0.0068, 0.0),
			Vector2(0.0068, 0.0026),
			Vector2(0.0042, 0.0026),
		], 8, Transform3D(Basis.IDENTITY, hc + Vector3(0.0, r_b - 0.0008, 0.0)))
	st_brass.generate_normals()
	root.add_child(_make_mesh_node("BrassFittings", st_brass.commit(), _make_mat(COL_BRASS, 0.24, 0.88)))

	# Dark recessed finger holes & fipple labium windway notch along top ridge.
	var st_holes := SurfaceTool.new()
	st_holes.begin(Mesh.PRIMITIVE_TRIANGLES)
	for ht: float in hole_ts:
		var hc: Vector3 = curve_pt.call(ht)
		var r_b := lerpf(0.0155, 0.0200, (ht - 0.14) / 0.74)
		_append_lathe(st_holes, [
			Vector2(0.0, 0.0),
			Vector2(0.0044, 0.0),
			Vector2(0.0044, 0.0028),
			Vector2(0.0, 0.0028),
		], 8, Transform3D(Basis.IDENTITY, hc + Vector3(0.0, r_b - 0.0006, 0.0)))
	# Fipple windway labium cutout near mouthpiece.
	_append_beveled_box(st_holes, Vector3(0.011, 0.005, 0.016), 0.001,
		Transform3D(Basis.IDENTITY, Vector3(0.0, 0.020, 0.118)))
	st_holes.generate_normals()
	root.add_child(_make_mesh_node("FingerHoles", st_holes.commit(), _make_mat(Color(0.07, 0.04, 0.03), 0.95, 0.02, Color.BLACK, 0.0, false, &"none")))

	# Decorative twin-strand braided sailor's lanyard loop hanging from the keel eyelet.
	var st_rope := SurfaceTool.new()
	st_rope.begin(Mesh.PRIMITIVE_TRIANGLES)
	for strand: float in [-1.0, 1.0]:
		var loop_pts: Array[Vector3] = []
		for i in 17:
			var u := float(i) / 16.0
			var a := u * TAU
			var twist := sin(u * TAU * 4.0) * 0.0038 * strand
			var lx := twist + sin(a) * 0.010 * strand
			var ly := -0.078 - (1.0 - cos(a)) * 0.072
			var lz := -0.138 + sin(a) * 0.044
			loop_pts.append(Vector3(lx, ly, lz))
		_append_tube(st_rope, loop_pts, 0.0036, 6, false)
	st_rope.generate_normals()
	root.add_child(_make_mesh_node("BraidedLanyard", st_rope.commit(), _make_mat(COL_ROPE, 0.88, 0.0, Color.BLACK, 0.0, false, &"rope")))

	# Crimson sailor's Turks-head whipping knot collar securing the lanyard below the shackle.
	var knot_mesh := _lathe_mesh([
		Vector2(0.006, -0.010),
		Vector2(0.011, -0.005),
		Vector2(0.011, 0.005),
		Vector2(0.006, 0.010),
	], 10, Transform3D(Basis.IDENTITY, Vector3(0.0, -0.088, -0.138)))
	root.add_child(_make_mesh_node("LanyardKnot", knot_mesh, _make_mat(COL_CRIMSON, 0.78, 0.04)))
	return root


## 14. Speaking Trumpet: sculpted maritime brass megaphone with 16-sided flared bell,
## rolled gold lip ring, 3 turned reinforcement collars with square rivets, tapered
## mouthpiece rim, riveted dark-leather carry handle loop, and braided hemp wrist strap.
static func _build_speaking_trumpet() -> Node3D:
	var root := Node3D.new()
	root.name = "Tool_SpeakingTrumpet"

	# Lathe +Y axis projects straight forward (-Z) from mouthpiece (+0.088) to flared bell (-0.380).
	var horn_xf := Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(0.0, 0.054, 0.088))

	# 1. Main flared conical brass horn, 3 turned reinforcement collars with square rivets,
	#    carry-handle mounting brackets, and rear lanyard eyelet ring.
	var st_brass := SurfaceTool.new()
	st_brass.begin(Mesh.PRIMITIVE_TRIANGLES)
	var horn_profile: Array[Vector2] = [
		Vector2(0.020, 0.014),
		Vector2(0.022, 0.048),
		Vector2(0.026, 0.105),
		Vector2(0.034, 0.175),
		Vector2(0.044, 0.245),
		Vector2(0.056, 0.312),
		Vector2(0.074, 0.368),
		Vector2(0.098, 0.414),
		Vector2(0.122, 0.448),
		Vector2(0.132, 0.462),
	]
	_append_lathe(st_brass, horn_profile, 16, horn_xf)

	# Three turned brass reinforcement collars seated along the conical horn with square rivets.
	var collar_specs := [
		[0.105, 0.0265, 0.0315, 0.018, 6],
		[0.238, 0.0435, 0.0495, 0.022, 8],
		[0.358, 0.0705, 0.0775, 0.024, 8],
	]
	for spec: Array in collar_specs:
		var cy: float = float(spec[0])
		var r_base: float = float(spec[1])
		var r_out: float = float(spec[2])
		var half_len: float = float(spec[3]) * 0.5
		var rivet_count: int = int(spec[4])
		_append_lathe(st_brass, [
			Vector2(r_base, cy - half_len - 0.003),
			Vector2(r_out, cy - half_len),
			Vector2(r_out + 0.002, cy),
			Vector2(r_out, cy + half_len),
			Vector2(r_base, cy + half_len + 0.003),
		], 16, horn_xf)
		for ri in rivet_count:
			var ang := (float(ri) + 0.5) / float(rivet_count) * TAU
			var radial := Vector3(cos(ang), 0.0, sin(ang))
			var tang := Vector3(-sin(ang), 0.0, cos(ang))
			var r_basis := Basis(tang, radial, Vector3.UP)
			var r_local := Transform3D(r_basis, Vector3(radial.x * (r_out + 0.0012), cy, radial.z * (r_out + 0.0012)))
			_append_square_rivet(st_brass, 0.0046, 0.0032, horn_xf * r_local)

	# Riveted brass carry-handle mounting lugs anchoring the dark-leather handle beneath the horn.
	_append_beveled_box(st_brass, Vector3(0.024, 0.020, 0.026), 0.003,
		Transform3D(Basis.IDENTITY, Vector3(0.0, 0.022, 0.046)))
	_append_beveled_box(st_brass, Vector3(0.024, 0.022, 0.028), 0.003,
		Transform3D(Basis.IDENTITY, Vector3(0.0, 0.018, -0.072)))

	# Rear brass lanyard eyelet shackle ring under the rear collar.
	var eye_pts: Array[Vector3] = []
	for i in 11:
		var a := float(i) / 10.0 * TAU
		eye_pts.append(Vector3(0.0, 0.010 + sin(a) * 0.011, 0.068 + cos(a) * 0.011))
	_append_tube(st_brass, eye_pts, 0.0032, 6, false)
	st_brass.generate_normals()
	var mat_brass := _make_mat(COL_BRASS, 0.24, 0.88, Color.BLACK, 0.0, false, &"brass")
	mat_brass.vertex_color_is_srgb = true
	mat_brass.uv1_world_triplanar = false
	root.add_child(_make_mesh_node("BrassHorn", st_brass.commit(), mat_brass))

	# 2. Rolled gilded bell lip ring & tapered comfort mouthpiece rim.
	var st_gold := SurfaceTool.new()
	st_gold.begin(Mesh.PRIMITIVE_TRIANGLES)
	_append_lathe(st_gold, [
		Vector2(0.129, 0.456),
		Vector2(0.139, 0.464),
		Vector2(0.143, 0.473),
		Vector2(0.138, 0.481),
		Vector2(0.128, 0.482),
		Vector2(0.121, 0.475),
		Vector2(0.123, 0.466),
	], 16, horn_xf)
	_append_lathe(st_gold, [
		Vector2(0.014, -0.014),
		Vector2(0.025, -0.018),
		Vector2(0.032, -0.012),
		Vector2(0.031, -0.003),
		Vector2(0.023, 0.008),
		Vector2(0.021, 0.020),
	], 14, horn_xf)
	st_gold.generate_normals()
	var mat_gold := _make_mat(COL_GOLD_BRIGHT, 0.18, 0.94, Color.BLACK, 0.0, false, &"brass")
	mat_gold.vertex_color_is_srgb = true
	mat_gold.uv1_world_triplanar = false
	root.add_child(_make_mesh_node("GoldTrim", st_gold.commit(), mat_gold))

	# 3. Dark patinated inner bell funnel bore (wound downward along -Y so normals face out the bell).
	var st_bore := SurfaceTool.new()
	st_bore.begin(Mesh.PRIMITIVE_TRIANGLES)
	_append_lathe(st_bore, [
		Vector2(0.122, 0.472),
		Vector2(0.094, 0.415),
		Vector2(0.064, 0.345),
		Vector2(0.042, 0.255),
		Vector2(0.024, 0.140),
		Vector2(0.014, 0.045),
		Vector2(0.0, 0.032),
	], 16, horn_xf)
	st_bore.generate_normals()
	var mat_bore := _make_mat(Color(0.15, 0.10, 0.05), 0.56, 0.68, Color.BLACK, 0.0, false, &"brass")
	mat_bore.vertex_color_is_srgb = true
	mat_bore.uv1_world_triplanar = false
	root.add_child(_make_mesh_node("InnerBellBore", st_bore.commit(), mat_bore))

	# 4. Curved riveted dark-leather side/lower carry handle loop seated cleanly at grip origin (0, 0, 0).
	var st_leather := SurfaceTool.new()
	st_leather.begin(Mesh.PRIMITIVE_TRIANGLES)
	var handle_pts: Array[Vector3] = [
		Vector3(0.0, 0.022, 0.046),
		Vector3(0.0, 0.004, 0.052),
		Vector3(0.0, -0.014, 0.038),
		Vector3(0.0, -0.019, 0.012),
		Vector3(0.0, -0.019, -0.018),
		Vector3(0.0, -0.014, -0.048),
		Vector3(0.0, 0.000, -0.068),
		Vector3(0.0, 0.018, -0.072),
	]
	_append_tube(st_leather, handle_pts, 0.014, 10, true)
	# Ribbed stitched leather grip collars along the palm bar.
	var grip_rot := Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(0.0, -0.019, 0.026))
	_append_lathe(st_leather, [
		Vector2(0.014, 0.000),
		Vector2(0.0175, 0.008),
		Vector2(0.0155, 0.018),
		Vector2(0.0180, 0.028),
		Vector2(0.0155, 0.038),
		Vector2(0.0175, 0.048),
		Vector2(0.014, 0.056),
	], 10, grip_rot)
	st_leather.generate_normals()
	var mat_leather := _make_mat(COL_LEATHER, 0.72, 0.06, Color.BLACK, 0.0, false, &"leather")
	mat_leather.vertex_color_is_srgb = true
	mat_leather.uv1_world_triplanar = false
	root.add_child(_make_mesh_node("LeatherHandle", st_leather.commit(), mat_leather))

	# 5. Subtle twin-strand braided hemp lanyard wrist strap + crimson whipping knot.
	var st_rope := SurfaceTool.new()
	st_rope.begin(Mesh.PRIMITIVE_TRIANGLES)
	for strand: float in [-1.0, 1.0]:
		var strap_pts: Array[Vector3] = []
		for i in 15:
			var u := float(i) / 14.0
			var a := u * TAU
			var twist := sin(u * TAU * 3.5) * 0.0032 * strand
			var lx := twist + sin(a) * 0.012 * strand
			var ly := 0.002 - (1.0 - cos(a)) * 0.052
			var lz := 0.074 + sin(a) * 0.036
			strap_pts.append(Vector3(lx, ly, lz))
		_append_tube(st_rope, strap_pts, 0.0034, 6, false)
	st_rope.generate_normals()
	var mat_rope := _make_mat(COL_ROPE, 0.86, 0.0, Color.BLACK, 0.0, false, &"rope")
	mat_rope.vertex_color_is_srgb = true
	mat_rope.uv1_world_triplanar = false
	root.add_child(_make_mesh_node("BraidedLanyard", st_rope.commit(), mat_rope))

	var knot_mesh := _lathe_mesh([
		Vector2(0.0055, -0.008),
		Vector2(0.0095, -0.004),
		Vector2(0.0095, 0.004),
		Vector2(0.0055, 0.008),
	], 8, Transform3D(Basis.IDENTITY, Vector3(0.0, -0.008, 0.072)))
	var mat_knot := _make_mat(COL_CRIMSON, 0.78, 0.04, Color.BLACK, 0.0, false, &"cloth")
	mat_knot.vertex_color_is_srgb = true
	mat_knot.uv1_world_triplanar = false
	root.add_child(_make_mesh_node("LanyardKnot", knot_mesh, mat_knot))
	return root


static func _append_square_rivet(st: SurfaceTool, width: float, height: float, xform: Transform3D) -> void:
	var hw := width * 0.5
	var tw := hw * 0.62
	var b0 := xform * Vector3(-hw, 0.0, -hw)
	var b1 := xform * Vector3(hw, 0.0, -hw)
	var b2 := xform * Vector3(hw, 0.0, hw)
	var b3 := xform * Vector3(-hw, 0.0, hw)
	var t0 := xform * Vector3(-tw, height, -tw)
	var t1 := xform * Vector3(tw, height, -tw)
	var t2 := xform * Vector3(tw, height, tw)
	var t3 := xform * Vector3(-tw, height, tw)
	_add_quad(st, t1, t0, b0, b1)
	_add_quad(st, t2, t1, b1, b2)
	_add_quad(st, t3, t2, b2, b3)
	_add_quad(st, t0, t3, b3, b0)
	_add_quad(st, t0, t1, t2, t3)


# ==============================================================================
# Reusable SurfaceTool geometry builders
# ==============================================================================

static func _infer_pbr_family(
	color: Color,
	roughness: float,
	metallic: float,
	emission_energy: float,
	transparent: bool
) -> StringName:
	if transparent or color.a < 0.995 or emission_energy > 0.001:
		return &"none"
	if metallic >= 0.65:
		return &"brass" if color.r > color.b + 0.14 else &"iron"
	if metallic < 0.25 and roughness >= 0.50:
		# Skip very bright/pale dial, parchment, ivory, and foam surfaces.
		if color.r > 0.72 and color.g > 0.65 and color.b > 0.46:
			return &"none"
		# Warm hemp/manila rope tan.
		if color.r >= 0.62 and color.g >= 0.50 and color.b >= 0.32 and color.r > color.b + 0.20:
			return &"rope"
		# Saturated red/crimson bellows cloth.
		if color.r > color.g + 0.32 and color.r > color.b + 0.32:
			return &"cloth"
		return &"oak"
	return &"none"


static func _make_mat(
	color: Color,
	roughness: float = 0.6,
	metallic: float = 0.0,
	emission: Color = Color.BLACK,
	emission_energy: float = 0.0,
	transparent: bool = false,
	pbr_family: StringName = &""
) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	m.metallic = metallic
	if emission_energy > 0.001:
		m.emission_enabled = true
		m.emission = emission
		m.emission_energy_multiplier = emission_energy
	if transparent or color.a < 0.995:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	var resolved_family := pbr_family
	if resolved_family == &"":
		resolved_family = _infer_pbr_family(color, roughness, metallic, emission_energy, transparent)
	if resolved_family != &"none" and _PBR_FAMILY_SPECS.has(resolved_family):
		var spec: Dictionary = _PBR_FAMILY_SPECS[resolved_family]
		var norm_tex := _load_pbr_tex(String(spec["normal"]))
		var rough_tex := _load_pbr_tex(String(spec["rough"]))
		if norm_tex != null:
			# Object-space triplanar mapping prevents texture swimming on held first-person tools!
			m.uv1_triplanar = true
			m.uv1_world_triplanar = false
			m.uv1_scale = spec["scale"] as Vector3
			m.normal_enabled = true
			m.normal_scale = float(spec["normal_scale"])
			m.normal_texture = norm_tex
			if rough_tex != null:
				m.roughness_texture = rough_tex
	return m


static func _make_mesh_node(node_name: String, mesh: Mesh, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	mi.material_override = mat
	return mi


static func _add_quad(st: SurfaceTool, top_l: Vector3, top_r: Vector3, bot_r: Vector3, bot_l: Vector3,
		uv_tl: Vector2 = Vector2(0, 0), uv_tr: Vector2 = Vector2(1, 0),
		uv_br: Vector2 = Vector2(1, 1), uv_bl: Vector2 = Vector2(0, 1)) -> void:
	# Clockwise winding when viewed from front so Godot generates outward normals.
	st.set_uv(uv_tl); st.add_vertex(top_l)
	st.set_uv(uv_tr); st.add_vertex(top_r)
	st.set_uv(uv_br); st.add_vertex(bot_r)
	st.set_uv(uv_tl); st.add_vertex(top_l)
	st.set_uv(uv_br); st.add_vertex(bot_r)
	st.set_uv(uv_bl); st.add_vertex(bot_l)


static func _lathe_mesh(profile: Array[Vector2], segments: int, xform: Transform3D = Transform3D.IDENTITY) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_append_lathe(st, profile, segments, xform)
	st.generate_normals()
	return st.commit()


static func _append_lathe(st: SurfaceTool, profile: Array[Vector2], segments: int, xform: Transform3D = Transform3D.IDENTITY) -> void:
	var segs := maxi(segments, 4)
	var rows := profile.size()
	if rows < 2:
		return
	for j in range(rows - 1):
		var r0 := profile[j].x
		var y0 := profile[j].y
		var r1 := profile[j + 1].x
		var y1 := profile[j + 1].y
		var v0 := float(j) / float(rows - 1)
		var v1 := float(j + 1) / float(rows - 1)
		for i in segs:
			var a0 := float(i) / float(segs) * TAU
			var a1 := float(i + 1) / float(segs) * TAU
			var p00 := xform * Vector3(cos(a0) * r0, y0, sin(a0) * r0)
			var p01 := xform * Vector3(cos(a1) * r0, y0, sin(a1) * r0)
			var p10 := xform * Vector3(cos(a0) * r1, y1, sin(a0) * r1)
			var p11 := xform * Vector3(cos(a1) * r1, y1, sin(a1) * r1)
			var u0 := float(i) / float(segs)
			var u1 := float(i + 1) / float(segs)
			if r0 <= 0.0001 and r1 <= 0.0001:
				continue
			if r0 <= 0.0001:
				st.set_uv(Vector2(u1, v1)); st.add_vertex(p11)
				st.set_uv(Vector2(u0, v1)); st.add_vertex(p10)
				st.set_uv(Vector2(u0, v0)); st.add_vertex(p00)
			elif r1 <= 0.0001:
				st.set_uv(Vector2(u0, v1)); st.add_vertex(p10)
				st.set_uv(Vector2(u0, v0)); st.add_vertex(p00)
				st.set_uv(Vector2(u1, v0)); st.add_vertex(p01)
			else:
				_add_quad(st, p11, p10, p00, p01,
					Vector2(u1, v1), Vector2(u0, v1), Vector2(u0, v0), Vector2(u1, v0))


static func _loft_mesh(rings: Array, close_caps: bool = true) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_append_loft(st, rings, close_caps)
	st.generate_normals()
	return st.commit()


static func _append_loft(st: SurfaceTool, rings: Array, close_caps: bool = true) -> void:
	if rings.size() < 2:
		return
	var ring_len := (rings[0] as Array).size()
	if ring_len < 3:
		return
	for j in range(rings.size() - 1):
		var r0: Array = rings[j]
		var r1: Array = rings[j + 1]
		var v0 := float(j) / float(rings.size() - 1)
		var v1 := float(j + 1) / float(rings.size() - 1)
		for i in ring_len:
			var ni := (i + 1) % ring_len
			var u0 := float(i) / float(ring_len)
			var u1 := float(i + 1) / float(ring_len)
			_add_quad(st, r1[ni], r1[i], r0[i], r0[ni],
				Vector2(u1, v1), Vector2(u0, v1), Vector2(u0, v0), Vector2(u1, v0))
	if close_caps:
		# Bottom cap outward normal = -dT; top cap outward normal = +dT (CW from outside).
		var first: Array = rings[0]
		var c0 := Vector3.ZERO
		for p: Vector3 in first:
			c0 += p
		c0 /= float(ring_len)
		for i in ring_len:
			var ni := (i + 1) % ring_len
			st.set_uv(Vector2(0.5, 0.5)); st.add_vertex(c0)
			st.set_uv(Vector2(1.0, 0.0)); st.add_vertex(first[ni])
			st.set_uv(Vector2(0.0, 0.0)); st.add_vertex(first[i])
		var last: Array = rings[rings.size() - 1]
		var c1 := Vector3.ZERO
		for p: Vector3 in last:
			c1 += p
		c1 /= float(ring_len)
		for i in ring_len:
			var ni := (i + 1) % ring_len
			st.set_uv(Vector2(0.5, 0.5)); st.add_vertex(c1)
			st.set_uv(Vector2(0.0, 1.0)); st.add_vertex(last[i])
			st.set_uv(Vector2(1.0, 1.0)); st.add_vertex(last[ni])


static func _append_tube(st: SurfaceTool, points: Array[Vector3], radius: float, segs: int = 8, close_caps: bool = true) -> void:
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
	_append_loft(st, rings, close_caps)


static func _append_beveled_box(st: SurfaceTool, size: Vector3, bevel: float, xform: Transform3D = Transform3D.IDENTITY) -> void:
	var hx := size.x * 0.5
	var hy := size.y * 0.5
	var hz := size.z * 0.5
	var b := minf(bevel, minf(hx, minf(hy, hz)) * 0.42)
	var ix := maxf(hx - b, 0.0001)
	var iy := maxf(hy - b, 0.0001)
	var iz := maxf(hz - b, 0.0001)
	# 4-ring chamfered loft along Y (bottom cap, lower bevel, upper bevel, top cap).
	var ys: PackedFloat32Array = PackedFloat32Array([-hy, -iy, iy, hy])
	var xs: PackedFloat32Array = PackedFloat32Array([ix, hx, hx, ix])
	var zs: PackedFloat32Array = PackedFloat32Array([iz, hz, hz, iz])
	var rings: Array = []
	for k in 4:
		var y: float = ys[k]
		var rx: float = xs[k]
		var rz: float = zs[k]
		var bx: float = maxf(rx - b * 0.55, rx * 0.72) if (k == 1 or k == 2) else maxf(rx - b * 0.35, rx * 0.80)
		var bz: float = maxf(rz - b * 0.55, rz * 0.72) if (k == 1 or k == 2) else maxf(rz - b * 0.35, rz * 0.80)
		var ring: Array = [
			xform * Vector3(bx, y, -rz),
			xform * Vector3(rx, y, -bz),
			xform * Vector3(rx, y, bz),
			xform * Vector3(bx, y, rz),
			xform * Vector3(-bx, y, rz),
			xform * Vector3(-rx, y, bz),
			xform * Vector3(-rx, y, -bz),
			xform * Vector3(-bx, y, -rz),
		]
		rings.append(ring)
	_append_loft(st, rings, true)


static func _append_diamond_needle(st: SurfaceTool, tip_z: float, base_z: float, half_w: float, half_h: float) -> void:
	var tip := Vector3(0.0, 0.0, tip_z)
	var top := Vector3(0.0, half_h, base_z)
	var bot := Vector3(0.0, -half_h, base_z)
	var right := Vector3(half_w, 0.0, base_z)
	var left := Vector3(-half_w, 0.0, base_z)
	var uv := Vector2(0.5, 0.5)
	if tip_z < base_z:
		# Pointing along -Z: CW from outside.
		st.set_uv(uv); st.add_vertex(tip); st.set_uv(uv); st.add_vertex(right); st.set_uv(uv); st.add_vertex(top)
		st.set_uv(uv); st.add_vertex(tip); st.set_uv(uv); st.add_vertex(top); st.set_uv(uv); st.add_vertex(left)
		st.set_uv(uv); st.add_vertex(tip); st.set_uv(uv); st.add_vertex(left); st.set_uv(uv); st.add_vertex(bot)
		st.set_uv(uv); st.add_vertex(tip); st.set_uv(uv); st.add_vertex(bot); st.set_uv(uv); st.add_vertex(right)
		st.set_uv(uv); st.add_vertex(top); st.set_uv(uv); st.add_vertex(right); st.set_uv(uv); st.add_vertex(bot)
		st.set_uv(uv); st.add_vertex(top); st.set_uv(uv); st.add_vertex(bot); st.set_uv(uv); st.add_vertex(left)
	else:
		# Pointing along +Z.
		st.set_uv(uv); st.add_vertex(tip); st.set_uv(uv); st.add_vertex(top); st.set_uv(uv); st.add_vertex(right)
		st.set_uv(uv); st.add_vertex(tip); st.set_uv(uv); st.add_vertex(left); st.set_uv(uv); st.add_vertex(top)
		st.set_uv(uv); st.add_vertex(tip); st.set_uv(uv); st.add_vertex(bot); st.set_uv(uv); st.add_vertex(left)
		st.set_uv(uv); st.add_vertex(tip); st.set_uv(uv); st.add_vertex(right); st.set_uv(uv); st.add_vertex(bot)
		st.set_uv(uv); st.add_vertex(top); st.set_uv(uv); st.add_vertex(bot); st.set_uv(uv); st.add_vertex(right)
		st.set_uv(uv); st.add_vertex(top); st.set_uv(uv); st.add_vertex(left); st.set_uv(uv); st.add_vertex(bot)


static func _build_parchment_sheet_mesh(width: float, height: float, bow: float, back_face: bool) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cols := 8
	var rows := 6
	var z_bias := -0.002 if back_face else 0.002
	for r in rows:
		var v0 := float(r) / float(rows)
		var v1 := float(r + 1) / float(rows)
		var y0 := lerpf(height * 0.5, -height * 0.5, v0)
		var y1 := lerpf(height * 0.5, -height * 0.5, v1)
		var z_y0 := sin(v0 * PI) * bow * 0.55
		var z_y1 := sin(v1 * PI) * bow * 0.55
		for c in cols:
			var u0 := float(c) / float(cols)
			var u1 := float(c + 1) / float(cols)
			var x0 := lerpf(-width * 0.5, width * 0.5, u0)
			var x1 := lerpf(-width * 0.5, width * 0.5, u1)
			var z_x0 := cos((u0 - 0.5) * PI) * bow * 0.45
			var z_x1 := cos((u1 - 0.5) * PI) * bow * 0.45
			var top_l := Vector3(x0, y0, z_y0 + z_x0 + z_bias)
			var top_r := Vector3(x1, y0, z_y0 + z_x1 + z_bias)
			var bot_r := Vector3(x1, y1, z_y1 + z_x1 + z_bias)
			var bot_l := Vector3(x0, y1, z_y1 + z_x0 + z_bias)
			if back_face:
				_add_quad(st, top_r, top_l, bot_l, bot_r,
					Vector2(u1, v0), Vector2(u0, v0), Vector2(u0, v1), Vector2(u1, v1))
			else:
				_add_quad(st, top_l, top_r, bot_r, bot_l,
					Vector2(u0, v0), Vector2(u1, v0), Vector2(u1, v1), Vector2(u0, v1))
	st.generate_normals()
	return st.commit()
