extends TestCase
## Art contract for the generated sloop: names, pivots, station markers, and collision that leaves the ship walkable.

const SLOOP := "res://assets/generated/ship/sloop.glb"
const STATIONS := {
	"Station_Helm": Vector3(0, 2.0, 5.2), "Station_SailLength": Vector3(-1.9, 1.1, 0.5), "Station_SailAngle": Vector3(1.9, 1.1, 0.5),
	"Station_Anchor": Vector3(0, 1.1, -4.6), "Station_CannonPort": Vector3(-2.0, 1.1, -1.5), "Station_CannonStarboard": Vector3(2.0, 1.1, -1.5),
	"Station_MapTable": Vector3(0, -0.6, 2.5), "Station_Ladder_Port": Vector3(-2.3, 0, 2.0), "Station_Ladder_Starboard": Vector3(2.3, 0, 2.0),
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

func test_collision_leaves_ship_walkable() -> void:
	var s := _load()
	var body := StaticBody3D.new()
	add_child(body)
	var count := 0
	for mi in s.find_children("col_*", "MeshInstance3D", true, false):
		var cs := CollisionShape3D.new()
		var shape := ConvexPolygonShape3D.new()
		shape.points = (mi as MeshInstance3D).mesh.get_faces()
		cs.shape = shape
		cs.transform = (mi as MeshInstance3D).global_transform
		body.add_child(cs)
		count += 1
	check(count > 40, "expected many col_ pieces, got %d" % count)
	await physics_frames(2)
	var space := get_viewport().world_3d.direct_space_state
	# [feet position, expected floor y, body height]
	var spots := [
		[Vector3(0.9, 1.1, -2.6), 1.1, 1.8], [Vector3(-1.3, 1.1, 0.4), 1.1, 1.8], [Vector3(1.3, 1.1, 0.4), 1.1, 1.8], [Vector3(0, 1.1, -3.4), 1.1, 1.8],
		[Vector3(0, 1.1, 1.65), 1.1, 1.8], [Vector3(-1.6, 1.1, 2.0), 1.1, 1.8], [Vector3(1.6, 1.1, 2.0), 1.1, 1.8], [Vector3(1.2, 1.1, -1.5), 1.1, 1.8],
		[Vector3(0, 1.58, 2.47), 1.58, 1.8], [Vector3(0, 2.0, 3.6), 2.0, 1.8], [Vector3(0, 2.0, 6.0), 2.0, 1.8], [Vector3(1.2, 2.0, 4.5), 2.0, 1.8],
		[Vector3(0, 0.25, 0.4), 0.25, 1.8], [Vector3(-1.0, -0.6, 0.3), -0.6, 1.5], [Vector3(0.75, -0.6, 3.5), -0.6, 1.8], [Vector3(0, -0.6, 4.2), -0.6, 1.8],
		[Vector3(0.6, -0.6, -2.9), -0.6, 1.5], [Vector3(-0.9, -0.6, 2.5), -0.6, 1.5],
	]
	for sp in spots:
		var p: Vector3 = sp[0]
		var ray := PhysicsRayQueryParameters3D.create(p + Vector3(0, 0.6, 0), p + Vector3(0, -1.0, 0))
		var hit := space.intersect_ray(ray)
		check(not hit.is_empty() and absf(hit.position.y - float(sp[1])) < 0.06, "floor under %s: %s" % [p, hit.get("position", "none")])
		var cap := CapsuleShape3D.new()
		cap.radius = 0.25
		cap.height = float(sp[2]) - 0.1
		var q := PhysicsShapeQueryParameters3D.new()
		q.shape = cap
		q.transform = Transform3D(Basis(), p + Vector3(0, float(sp[2]) * 0.5 + 0.08, 0))
		check(space.intersect_shape(q, 1).is_empty(), "a %.1f m body does not fit at %s" % [sp[2], p])
	# the hull must still be solid: rays from outside hit the side, from above the hatch hit the stairs not the keel
	var side := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(6, 0.4, 0), Vector3(0, 0.4, 0)))
	check(not side.is_empty() and side.position.x > 1.9, "hull side solid")
	var bottom := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(0.3, -3, 0), Vector3(0.3, 0, 0)))
	check(not bottom.is_empty() and bottom.position.y < -0.9, "hull bottom solid")
	body.queue_free()
	s.queue_free()
