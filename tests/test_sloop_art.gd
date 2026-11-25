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
			"HatchCover_Starboard", "Lantern_Stern", "Lantern_Mast", "Lantern_Hold", "Hole_01", "Hole_10", "HolePatch_01", "HolePatch_10",
			"Sail/Clew_Port", "Sail/Clew_Starboard", "MapTable", "Figurehead"]:
		check(s.get_node_or_null(n) != null, "missing " + n)
	check((s.get_node("Sail") as Node3D).position.distance_to(Vector3(0, 9, -1)) < 0.002, "Sail origin on the mast at the yard")
	check((s.get_node("Yard") as Node3D).position.distance_to(Vector3(0, 9, -1)) < 0.002, "Yard origin on the mast")
	check(absf((s.get_node("Wheel") as Node3D).position.x) < 0.001 and absf((s.get_node("Wheel") as Node3D).position.z - 5.2) < 0.001, "Wheel hub at the helm")
	check((-(s.get_node("Cannon_Port") as Node3D).global_transform.basis.z).distance_to(Vector3.LEFT) < 0.01, "port cannon -Z is its muzzle")
	s.queue_free()

const FLOOR := -0.85

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
