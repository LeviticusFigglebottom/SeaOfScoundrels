class_name Leviathan
extends Node3D
## World-event sea monster: an abyssal multi-tentacle Leviathan that encircles a ship
## in deep water, whips foaming wave rings, slams the hull unless driven off by cannon
## or weapon fire, and drops Sunken Archive salvage when defeated.

signal tentacle_defeated(index: int, remaining: int)
signal leviathan_defeated(pos: Vector3, salvage: Array)

const TENTACLE_COUNT := 4
const TENTACLE_HP := 95.0
const SLAM_INTERVAL := 7.5

var target_ship: Ship = null
var active: bool = true
var _tentacles: Array[Dictionary] = []
var _clock: float = 0.0
var _center: Vector3 = Vector3.ZERO
var _defeated: bool = false


func _ready() -> void:
	name = "Leviathan"
	add_to_group(&"world_events")
	_center = global_position
	_build_tentacles()
	Audio.play_stinger(&"danger")
	Game.post_notice("Dark waters! The Abyssal Leviathan rises around the hull!")


func _build_tentacles() -> void:
	var skin_mat := StandardMaterial3D.new()
	skin_mat.albedo_color = Color(0.11, 0.22, 0.28)
	skin_mat.roughness = 0.55
	var glow_mat := StandardMaterial3D.new()
	glow_mat.albedo_color = Color(0.22, 0.94, 0.84)
	glow_mat.emission_enabled = true
	glow_mat.emission = Color(0.18, 0.92, 0.82)
	glow_mat.emission_energy_multiplier = 1.4

	for i in TENTACLE_COUNT:
		var root := Node3D.new()
		root.name = "Tentacle_%d" % i
		add_child(root)

		var segs: Array[Node3D] = []
		var parent_node: Node3D = root
		for s in 5:
			var pivot := Node3D.new()
			pivot.position = Vector3(0.0, 2.1 if s > 0 else 0.0, 0.0)
			parent_node.add_child(pivot)
			var mesh_inst := MeshInstance3D.new()
			var cyl := CylinderMesh.new()
			var r_bot := lerpf(0.72, 0.18, float(s) / 5.0)
			var r_top := lerpf(0.56, 0.08, float(s) / 5.0)
			cyl.bottom_radius = r_bot
			cyl.top_radius = r_top
			cyl.height = 2.25
			cyl.radial_segments = 8
			mesh_inst.mesh = cyl
			mesh_inst.position = Vector3(0.0, 1.05, 0.0)
			mesh_inst.material_override = skin_mat
			pivot.add_child(mesh_inst)

			# Glowing abyssal sucker ridge facing inward toward the ship.
			var pip := MeshInstance3D.new()
			var sp := SphereMesh.new()
			sp.radius = r_top * 0.42
			sp.height = r_top * 0.84
			sp.radial_segments = 6
			sp.rings = 3
			pip.mesh = sp
			pip.position = Vector3(0.0, 1.05, -r_bot * 0.72)
			pip.material_override = glow_mat
			pivot.add_child(pip)

			segs.append(pivot)
			parent_node = pivot

		# Hittable collider body so cannonballs & pistol shots can strike each tentacle!
		var body := StaticBody3D.new()
		body.name = "TentacleHitbox_%d" % i
		body.collision_layer = Pawn.LAYER_PAWN
		body.collision_mask = 0
		body.set_meta("leviathan", self)
		body.set_meta("tentacle_index", i)
		var cs := CollisionShape3D.new()
		var cap := CapsuleShape3D.new()
		cap.radius = 0.85
		cap.height = 8.5
		cs.shape = cap
		cs.position = Vector3(0.0, 4.2, 0.0)
		body.add_child(cs)
		root.add_child(body)

		_tentacles.append({
			"index": i,
			"root": root,
			"segs": segs,
			"hp": TENTACLE_HP,
			"alive": true,
			"angle": float(i) * TAU / float(TENTACLE_COUNT) + 0.4,
			"slam_cd": 3.5 + float(i) * 1.9,
			"slam_anim": 0.0,
		})


## Apply damage to a specific tentacle (or the nearest living tentacle if index < 0).
func damage_tentacle(index: int, amount: float) -> bool:
	if not Net.is_host() or _defeated:
		return false
	var t_dict: Dictionary = {}
	if index >= 0 and index < _tentacles.size() and bool(_tentacles[index]["alive"]):
		t_dict = _tentacles[index]
	else:
		for entry in _tentacles:
			if bool(entry["alive"]):
				t_dict = entry
				break
	if t_dict.is_empty():
		return false
	t_dict["hp"] = float(t_dict["hp"]) - amount
	var root: Node3D = t_dict["root"]
	Audio.play_sfx(&"hit_flesh", root.global_position, 2.0)
	if float(t_dict["hp"]) <= 0.0:
		t_dict["alive"] = false
		root.visible = false
		Audio.play_sfx(&"splash_large", root.global_position, 2.0)
		if Ocean.current != null:
			Ocean.current.add_foam(root.global_position, 4.0, 1.0)
		var rem := living_tentacles()
		tentacle_defeated.emit(int(t_dict["index"]), rem)
		if rem == 0:
			_on_defeated()
	return true


func living_tentacles() -> int:
	var n := 0
	for t in _tentacles:
		if bool(t["alive"]):
			n += 1
	return n


func _physics_process(delta: float) -> void:
	if _defeated:
		return
	_clock += delta
	if target_ship != null and is_instance_valid(target_ship) and not target_ship.is_sinking:
		_center = _center.lerp(target_ship.global_position, clampf(delta * 1.8, 0.0, 1.0))
		global_position = Vector3(_center.x, 0.0, _center.z)
		# Heavy ink-water drag while gripped by the Leviathan!
		if Net.is_host() and living_tentacles() > 0:
			target_ship.apply_central_force(-target_ship.linear_velocity * 3200.0)

	for t in _tentacles:
		if not bool(t["alive"]):
			continue
		var idx: int = t["index"]
		var root: Node3D = t["root"]
		var ang: float = float(t["angle"]) + _clock * 0.14
		var radius := 12.5 + sin(_clock * 0.9 + float(idx)) * 1.6
		var wx := _center.x + cos(ang) * radius
		var wz := _center.z + sin(ang) * radius
		var surf := Sea.height(wx, wz)
		root.global_position = Vector3(wx, surf - 1.2, wz)
		# Face inward toward ship centre.
		root.look_at(Vector3(_center.x, surf, _center.z), Vector3.UP)

		var slam_anim: float = maxf(0.0, float(t["slam_anim"]) - delta * 1.6)
		t["slam_anim"] = slam_anim
		var segs: Array = t["segs"]
		for s in segs.size():
			var piv: Node3D = segs[s]
			var sway := sin(_clock * 2.4 + float(idx) * 1.7 + float(s) * 0.65) * 0.22
			var curl := -0.18 - slam_anim * 0.45
			piv.rotation = Vector3(curl, 0.0, sway)

		if Ocean.current != null:
			Ocean.current.add_foam(Vector3(wx, surf, wz), 2.4, 0.35)

		if Net.is_host() and target_ship != null and is_instance_valid(target_ship) and not target_ship.is_sinking:
			t["slam_cd"] = float(t["slam_cd"]) - delta
			if float(t["slam_cd"]) <= 0.0:
				t["slam_cd"] = SLAM_INTERVAL
				t["slam_anim"] = 1.0
				# Slam strikes the nearest hull side of the ship!
				var slam_pt := target_ship.global_position + (root.global_position - target_ship.global_position).normalized() * 2.2
				slam_pt.y = target_ship.global_position.y - 0.35
				target_ship.apply_hull_damage(slam_pt, 0.42)
				Audio.play_sfx(&"hull_impact", slam_pt, 1.0)


func _on_defeated() -> void:
	_defeated = true
	active = false
	var salvage: Array = []
	var parent := get_parent()
	if parent != null:
		var surf := Sea.height(_center.x, _center.z)
		var loot_ids: Array[StringName] = [&"archive_chalice", &"sovereign_chest"]
		for i in loot_ids.size():
			var pos := Vector3(_center.x + (float(i) - 0.5) * 4.0, surf + 0.35, _center.z)
			var item := TreasureCatalog.create_treasure_carryable(loot_ids[i], pos)
			parent.add_child(item)
			item.global_position = pos
			salvage.append(item)
	Audio.play_stinger(&"victory")
	Game.post_notice("The Abyssal Leviathan retreats to the deep! Treasure rises to the surface!")
	leviathan_defeated.emit(_center, salvage)
	queue_free()
