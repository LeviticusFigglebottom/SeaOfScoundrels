extends TestCase
## Art contract for the generated sloop: names, pivots, station markers, and collision that leaves the ship walkable.

const SLOOP := "res://assets/generated/ship/sloop.glb"
const STATIONS := {
	"Station_Helm": Vector3(0, 2.0, 5.2), "Station_SailLength": Vector3(-1.9, 1.1, 0.5), "Station_SailAngle": Vector3(1.9, 1.1, 0.5),
	"Station_Anchor": Vector3(0, 1.1, -4.6), "Station_CannonPort": Vector3(-2.0, 1.1, -1.5), "Station_CannonStarboard": Vector3(2.0, 1.1, -1.5),
	"Station_MapTable": Vector3(0, -0.85, 2.5), "Station_Ladder_Port": Vector3(-2.3, 0, 2.0), "Station_Ladder_Starboard": Vector3(2.3, 0, 2.0),
}

func _load() -> Node3D:
	var s: Node3D = (load(SLOOP) as PackedScene).instantiate()
	add_child(s)
	return s

func test_names_and_stations() -> void:
	var s := _load()
	for n in STATIONS:
		var node := s.get_node_or_null(n) as Node3D
		check(node != null, "missing " + n)
		if node:
			check(node.global_position.distance_to(STATIONS[n]) < 0.002, "%s at %s" % [n, node.global_position])
	check((-(s.get_node("Station_CannonPort") as Node3D).global_transform.basis.z).distance_to(Vector3.LEFT) < 0.01, "port cannon station faces -X")
	check((-(s.get_node("Station_CannonStarboard") as Node3D).global_transform.basis.z).distance_to(Vector3.RIGHT) < 0.01, "starboard cannon station faces +X")
	for n in ["Hull", "Sail", "Sail_Furled", "Yard", "Flag", "Wheel", "Rudder", "Capstan", "Anchor", "Cannon_Port", "Cannon_Starboard",
			"Cannon_Port/Cannon_Port_Barrel", "Cannon_Starboard/Cannon_Starboard_Barrel", "Bell", "Bucket", "PlankStack", "HatchCover_Port",
			"HatchCover_Starboard", "Lantern_Stern", "Lantern_Mast", "Lantern_Hold", "Hole_01", "Hole_10", "HolePatch_01", "HolePatch_10", "HullPanel_01", "HullPanel_10",
			"Sail/Clew_Port", "Sail/Clew_Starboard", "MapTable", "Figurehead", "Yard/Yardarm_Port", "Yard/Yardarm_Starboard", "SheetPoint_Port",
			"SheetPoint_Starboard", "BracePoint_Port", "BracePoint_Starboard", "Rope_Sheet_Port", "Rope_Sheet_Starboard", "Rope_Brace_Port",
			"Rope_Brace_Starboard", "Lantern_Helm", "Bucket_Deck", "Station_Bilge"]:
		check(s.get_node_or_null(n) != null, "missing " + n)
	check((s.get_node("Sail") as Node3D).position.distance_to(Vector3(0, 9, -1)) < 0.002, "Sail origin on the mast at the yard")
	check((s.get_node("Yard") as Node3D).position.distance_to(Vector3(0, 9, -1)) < 0.002, "Yard origin on the mast")
	var wheel := s.get_node("Wheel") as MeshInstance3D
	check(wheel != null and absf(wheel.position.x) < 0.001 and absf(wheel.position.z - 5.2) < 0.001, "Wheel hub at the helm")
	if wheel != null:
		check_near(wheel.position.y, 2.68, 0.01, "Wheel hub lowered to waist height (QDECK_Y + 0.68)")
		var wbb := wheel.mesh.get_aabb()
		var king_top_y := wbb.position.y + wbb.size.y
		var reg_bot_y := absf(wbb.position.y)
		var scaled_top_above_qdeck := (wheel.position.y - 2.0 + king_top_y) * Ship.DEFAULT_HULL_SCALE
		check(king_top_y > reg_bot_y + 0.05, "12-o'clock King Spoke (+Y=%.3f) stands taller than regular spokes (%.3f)" % [king_top_y, reg_bot_y])
		check(scaled_top_above_qdeck < 1.56, "Wheel top spoke sits below Captain 1.60 m eye line at 1.24x scale (%.3f m)" % scaled_top_above_qdeck)
	var helm_lantern := s.get_node("Lantern_Helm") as Node3D
	check(helm_lantern != null and helm_lantern.position.x <= -0.40 and helm_lantern.position.y <= 2.95,
		"Lantern_Helm shifted outboard & lowered clear of forward sightline (%s)" % (helm_lantern.position if helm_lantern else Vector3.ZERO))
	check((-(s.get_node("Cannon_Port") as Node3D).global_transform.basis.z).distance_to(Vector3.LEFT) < 0.01, "port cannon -Z is its muzzle")
	s.queue_free()

const FLOOR := -0.85

func test_materials_and_wind_weights() -> void:
	var s := _load()
	var names := {}
	for n in s.find_children("*", "MeshInstance3D", true, false):
		var m: Mesh = (n as MeshInstance3D).mesh
		for i in m.get_surface_count():
			names[m.surface_get_material(i).resource_name] = m.surface_get_material(i)
	for want in ["mat_wood", "mat_paint", "mat_rope", "mat_iron", "mat_brass", "mat_lantern_glass", "mat_window_glass", "mat_canvas", "mat_canvas_back", "mat_cloth", "mat_flag"]:
		check(names.has(want), "material " + want)
	if names.has("mat_window_glass"):
		check((names["mat_window_glass"] as BaseMaterial3D).transparency != BaseMaterial3D.TRANSPARENCY_DISABLED, "stern glazing is see-through")
	for nm in ["Sail", "Flag"]:
		var arr := (s.get_node(nm) as MeshInstance3D).mesh.surface_get_arrays(0)
		check(arr[Mesh.ARRAY_TEX_UV2] != null, nm + " has wind weights in UV2")
		if arr[Mesh.ARRAY_TEX_UV2] != null:
			var lo := 1.0
			var hi := 0.0
			for v: Vector2 in arr[Mesh.ARRAY_TEX_UV2]:
				lo = minf(lo, v.x)
				hi = maxf(hi, v.x)
			check(lo < 0.02 and hi > 0.9, "%s weights span 0..1 (%f..%f)" % [nm, lo, hi])
	# a unit rope: local z from 0 to 1
	var rope := s.get_node("Rope_Sheet_Port") as MeshInstance3D
	var bb := rope.mesh.get_aabb()
	check(absf(bb.position.z) < 0.01 and absf(bb.size.z - 1.0) < 0.01 and bb.size.x < 0.06, "rope is a unit cylinder along +Z: %s" % bb)
	check(rope.global_position.distance_to((s.get_node("SheetPoint_Port") as Node3D).global_position) < 0.01, "sheet starts at its sheet point")
	var tip := rope.global_transform * Vector3(0, 0, 1)
	check(tip.distance_to((s.get_node("Sail/Clew_Port") as Node3D).global_position) < 0.02, "sheet ends at the clew")
	s.queue_free()

func _static_ship(s: Node3D, lift: float) -> StaticBody3D:
	var body := StaticBody3D.new()
	add_child(body)
	body.position.y = lift
	for mi in s.find_children("col_*", "MeshInstance3D", true, false):
		var cs := CollisionShape3D.new()
		var shape := ConvexPolygonShape3D.new()
		shape.points = (mi as MeshInstance3D).mesh.get_faces()
		cs.shape = shape
		cs.transform = (mi as MeshInstance3D).transform
		body.add_child(cs)
	return body

func test_collision_leaves_ship_walkable() -> void:
	var s := _load()
	var body := _static_ship(s, 0.0)
	check(body.get_child_count() > 40, "expected many col_ pieces, got %d" % body.get_child_count())
	await physics_frames(2)
	var space := get_viewport().world_3d.direct_space_state
	# [feet position, expected floor y]; a full 1.75 m body must fit at every one of them
	var spots := [
		[Vector3(0.9, 1.1, -2.6), 1.1], [Vector3(-1.3, 1.1, 0.4), 1.1], [Vector3(1.3, 1.1, 0.4), 1.1], [Vector3(0, 1.1, -3.4), 1.1],
		[Vector3(0, 1.1, 2.62), 1.1], [Vector3(-1.6, 1.1, 2.0), 1.1], [Vector3(1.6, 1.1, 2.0), 1.1], [Vector3(1.2, 1.1, -1.5), 1.1],
		[Vector3(1.4, 1.55, 3.25), 1.55], [Vector3(-1.4, 1.55, 3.25), 1.55], [Vector3(0, 2.0, 3.6), 2.0], [Vector3(0, 2.0, 6.0), 2.0], [Vector3(1.3, 2.0, 4.5), 2.0],
		[Vector3(0, 0.305, 1.2), 0.305],
		[Vector3(-0.82, FLOOR, 0.3), FLOOR], [Vector3(0.82, FLOOR, 1.5), FLOOR], [Vector3(0.5, FLOOR, 3.5), FLOOR], [Vector3(0, FLOOR, 4.2), FLOOR],
		[Vector3(0.6, FLOOR, -2.9), FLOOR], [Vector3(-0.6, FLOOR, 2.5), FLOOR], [Vector3(0.2, FLOOR, -2.6), FLOOR], [Vector3(-0.9, FLOOR, -1.5), FLOOR],
		[Vector3(0.85, FLOOR, 2.5), FLOOR], [Vector3(-0.5, FLOOR, 3.6), FLOOR],
	]
	for sp in spots:
		var p: Vector3 = sp[0]
		var ray := PhysicsRayQueryParameters3D.create(p + Vector3(0, 0.6, 0), p + Vector3(0, -1.0, 0))
		var hit := space.intersect_ray(ray)
		check(not hit.is_empty() and absf(hit.position.y - float(sp[1])) < 0.04, "floor under %s: %s" % [p, hit.get("position", "none")])
		var cap := CapsuleShape3D.new()
		cap.radius = 0.3
		cap.height = 1.75
		var q := PhysicsShapeQueryParameters3D.new()
		q.shape = cap
		# a capsule on a ramp rests on the side of its bottom sphere, so its feet point floats a little above the ramp
		var on_flat: bool = absf(p.y - 1.1) < 0.01 or absf(p.y - 2.0) < 0.01 or absf(p.y - FLOOR) < 0.01
		var lift_y := 0.04 if on_flat else 0.1
		q.transform = Transform3D(Basis(), p + Vector3(0, 0.875 + lift_y, 0))
		check(space.intersect_shape(q, 1).is_empty(), "a 1.75 m body does not fit at %s" % p)
	# the hull must still be solid: rays from outside hit the side, from below hit the keel
	var side := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(6, 0.4, 0), Vector3(0, 0.4, 0)))
	check(not side.is_empty() and side.position.x > 1.9, "hull side solid")
	var bottom := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(0.3, -3, 0), Vector3(0.3, 0, 0)))
	check(not bottom.is_empty() and bottom.position.y < -0.9, "hull bottom solid")
	# the main-deck bulwark is a real barrier about a metre high
	var rail := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(0.5, 1.1 + 0.9, 0.9), Vector3(4, 1.1 + 0.9, 0.9)))
	check(not rail.is_empty(), "bulwark at least 0.9 m high")
	body.queue_free()
	s.queue_free()

## A real Pawn walks quarterdeck -> starboard stairs -> main deck -> hold stairs -> the length of the hold -> back up -> port stairs,
## standing upright all the way (no auto-crouch). The ship is lifted clear of the sea so only the collision is under test.
const WALK := [
	Vector3(0, 2.0, 4.6), Vector3(1.4, 2.0, 4.3), Vector3(1.4, 1.1, 2.2), Vector3(0, 1.1, 2.62), Vector3(0, 0.6, 1.57), Vector3(0, -0.8, -0.3),
	Vector3(0.82, FLOOR, -0.3), Vector3(0.82, FLOOR, 2.6), Vector3(0.45, FLOOR, 3.5), Vector3(0, FLOOR, 4.6), Vector3(-0.45, FLOOR, 3.5),
	Vector3(-0.82, FLOOR, 2.6), Vector3(-0.82, FLOOR, -0.4), Vector3(-0.75, FLOOR, -1.6), Vector3(0.3, FLOOR, -3.0), Vector3(0.8, FLOOR, -1.6),
	Vector3(0.78, FLOOR, -0.4), Vector3(0, -0.8, -0.3), Vector3(0, -0.5, 0.2), Vector3(0, 1.1, 2.62), Vector3(-1.4, 1.1, 2.2), Vector3(-1.4, 2.0, 4.3), Vector3(0, 2.0, 5.6),
]

func test_pawn_walks_whole_ship_upright() -> void:
	var s := _load()
	var lift := 60.0
	s.position.y = lift
	var body := _static_ship(s, lift)
	var pawn: Pawn = (load("res://src/characters/pawn.tscn") as PackedScene).instantiate()
	add_child(pawn)
	pawn.global_position = Vector3(0, 2.05 + lift, 5.6)
	await physics_frames(20)
	var crouched_at := ""
	for i in WALK.size():
		var target: Vector3 = WALK[i] + Vector3(0, lift, 0)
		var ticks := 0
		while ticks < 600:
			var d := target - pawn.global_position
			d.y = 0.0
			if d.length() < 0.22:
				break
			pawn.wish_dir = d.normalized()
			await get_tree().physics_frame
			ticks += 1
			if pawn.crouched and crouched_at == "":
				crouched_at = str(pawn.global_position - Vector3(0, lift, 0))
		check(ticks < 600, "pawn stuck before waypoint %d %s at %s" % [i, WALK[i], pawn.global_position - Vector3(0, lift, 0)])
		check(absf(pawn.global_position.y - target.y) < 0.45, "pawn at wrong height at waypoint %d: %s" % [i, pawn.global_position - Vector3(0, lift, 0)])
		if ticks >= 600:
			break
	check(crouched_at == "", "pawn had to crouch at " + crouched_at)
	pawn.queue_free()
	body.queue_free()
	s.queue_free()

func test_world_and_ship_pbr_texture_quality() -> void:
	const TEX_ROOT := "res://assets/generated/textures/"
	# [filename, min_lum, max_lum, min_std]
	const ALBEDO_SPECS := [
		["terrain_grass_albedo.png", 0.30, 0.46, 0.055],
		["terrain_dirt_albedo.png", 0.32, 0.48, 0.050],
		["terrain_sand_albedo.png", 0.64, 0.80, 0.055],
		["terrain_cliff_albedo.png", 0.50, 0.68, 0.080],
		["terrain_volcanic_albedo.png", 0.13, 0.25, 0.050],
		["ship_oak_albedo.png", 0.80, 0.89, 0.100],
		["ship_paint_albedo.png", 0.84, 0.93, 0.025],
		["ship_iron_albedo.png", 0.77, 0.86, 0.024],
		["ship_brass_albedo.png", 0.85, 0.94, 0.024],
		["ship_rope_albedo.png", 0.81, 0.90, 0.110],
		["ship_cloth_albedo.png", 0.88, 0.97, 0.035],
	]
	const NORMAL_FILES := [
		"terrain_grass_normal.png", "terrain_dirt_normal.png", "terrain_sand_normal.png",
		"terrain_cliff_normal.png", "terrain_volcanic_normal.png", "ship_oak_normal.png",
		"ship_paint_normal.png", "ship_iron_normal.png", "ship_brass_normal.png",
		"ship_rope_normal.png", "ship_cloth_normal.png",
	]
	const ROUGH_FILES := [
		"ship_oak_rough.png", "ship_paint_rough.png", "ship_iron_rough.png",
		"ship_brass_rough.png", "ship_rope_rough.png",
	]

	for spec: Array in ALBEDO_SPECS:
		var fname: String = String(spec[0])
		var path: String = TEX_ROOT + fname
		check(ResourceLoader.exists(path), "missing PBR albedo: " + path)
		var tex := load(path) as Texture2D
		check(tex != null and tex.get_width() == 1024 and tex.get_height() == 1024,
			"%s imported size is 1024x1024 (got %s)" % [fname, Vector2i(tex.get_width(), tex.get_height()) if tex else Vector2i.ZERO])
		var img := Image.load_from_file(ProjectSettings.globalize_path(path))
		check(img != null and img.get_width() == 1024 and img.get_height() == 1024, "%s source PNG loads 1024x1024" % fname)
		if img == null:
			continue
		var sum_l := 0.0
		var sum_l2 := 0.0
		var n := 0
		for py in range(3, 1024, 13):
			for px in range(3, 1024, 13):
				var c := img.get_pixel(px, py)
				var lum := 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
				sum_l += lum
				sum_l2 += lum * lum
				n += 1
		var mean_l := sum_l / float(n)
		var std_l := sqrt(maxf(0.0, sum_l2 / float(n) - mean_l * mean_l))
		check(mean_l >= float(spec[1]) and mean_l <= float(spec[2]),
			"%s mean lum %.3f in [%.2f, %.2f]" % [fname, mean_l, float(spec[1]), float(spec[2])])
		check(std_l >= float(spec[3]), "%s contrast std %.3f >= %.3f" % [fname, std_l, float(spec[3])])

		var lr_diff := 0.0
		var tb_diff := 0.0
		var b_cnt := 0
		for i in range(0, 1024, 4):
			var cl := img.get_pixel(0, i)
			var cr := img.get_pixel(1023, i)
			lr_diff += (absf(cl.r - cr.r) + absf(cl.g - cr.g) + absf(cl.b - cr.b)) / 3.0
			var ct := img.get_pixel(i, 0)
			var cb := img.get_pixel(i, 1023)
			tb_diff += (absf(ct.r - cb.r) + absf(ct.g - cb.g) + absf(ct.b - cb.b)) / 3.0
			b_cnt += 1
		lr_diff /= float(b_cnt)
		tb_diff /= float(b_cnt)
		check(lr_diff < 0.04 and tb_diff < 0.04,
			"%s seamless borders LR=%.4f TB=%.4f (< 0.04)" % [fname, lr_diff, tb_diff])

	for fname: String in NORMAL_FILES:
		var path: String = TEX_ROOT + fname
		check(ResourceLoader.exists(path), "missing PBR normal: " + path)
		var tex := load(path) as Texture2D
		check(tex != null and tex.get_width() == 1024 and tex.get_height() == 1024,
			"%s imported size is 1024x1024" % fname)
		var img := Image.load_from_file(ProjectSettings.globalize_path(path))
		if img == null:
			continue
		var sum_r := 0.0
		var sum_g := 0.0
		var sum_b := 0.0
		var sum_r2 := 0.0
		var sum_g2 := 0.0
		var n := 0
		for py in range(3, 1024, 13):
			for px in range(3, 1024, 13):
				var c := img.get_pixel(px, py)
				sum_r += c.r
				sum_g += c.g
				sum_b += c.b
				sum_r2 += c.r * c.r
				sum_g2 += c.g * c.g
				n += 1
		var mr := sum_r / float(n)
		var mg := sum_g / float(n)
		var mb := sum_b / float(n)
		var sr := sqrt(maxf(0.0, sum_r2 / float(n) - mr * mr))
		var sg := sqrt(maxf(0.0, sum_g2 / float(n) - mg * mg))
		check(mr > 0.45 and mr < 0.55 and mg > 0.45 and mg < 0.55 and mb > 0.85,
			"%s tangent-space normal mean (%.3f, %.3f, %.3f)" % [fname, mr, mg, mb])
		check(maxf(sr, sg) >= 0.03, "%s crisp relief normal std (%.3f, %.3f >= 0.03)" % [fname, sr, sg])

	for fname: String in ROUGH_FILES:
		var path: String = TEX_ROOT + fname
		check(ResourceLoader.exists(path), "missing PBR roughness: " + path)
		var tex := load(path) as Texture2D
		check(tex != null and tex.get_width() == 1024 and tex.get_height() == 1024,
			"%s imported size is 1024x1024" % fname)

