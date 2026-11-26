class_name CharacterVisual
extends Node3D
## Stylized rigged character visual rig supporting pirates, Drowned skeletons, and Tidecallers.
##
## Loads the appropriate generated GLB rig for `archetype`, toggles modular clothing/gear meshes,
## creates `BoneAttachment3D` equipment sockets, and isolates per-instance cloth tint materials.

signal archetype_changed(archetype: StringName)
signal rig_changed(skeleton: Skeleton3D)

const RIG_SCENES := {
	&"pirate": preload("res://assets/generated/characters/pirate.glb"),
	&"drowned": preload("res://assets/generated/characters/drowned.glb"),
	&"tidecaller": preload("res://assets/generated/characters/tidecaller.glb"),
}

const EXPECTED_BONES: PackedStringArray = [
	"Hips", "Spine", "Chest", "Neck", "Head",
	"Shoulder_L", "UpperArm_L", "Forearm_L", "Hand_L",
	"Shoulder_R", "UpperArm_R", "Forearm_R", "Hand_R",
	"Thigh_L", "Shin_L", "Foot_L",
	"Thigh_R", "Shin_R", "Foot_R",
]

const ARCHETYPES := {
	&"captain": {
		"rig": &"pirate",
		"meshes": ["Body", "Hat_Tricorne", "Coat_Captain", "Belt_Sash"],
		"primary": Color(0.14, 0.25, 0.50),
		"secondary": Color(0.78, 0.16, 0.16),
	},
	&"helmsman": {
		"rig": &"pirate",
		"meshes": ["Body", "Hat_Cap", "Vest_Crew", "Beard_Full", "Belt_Sash"],
		"primary": Color(0.18, 0.42, 0.46),
		"secondary": Color(0.84, 0.58, 0.18),
	},
	&"lookout": {
		"rig": &"pirate",
		"meshes": ["Body", "Hat_Bandana", "Vest_Crew", "Eyepatch", "Belt_Sash"],
		"primary": Color(0.20, 0.42, 0.26),
		"secondary": Color(0.82, 0.18, 0.18),
	},
	&"carpenter": {
		"rig": &"pirate",
		"meshes": ["Body", "Hat_Cap", "Vest_Crew", "Belt_Sash"],
		"primary": Color(0.62, 0.30, 0.16),
		"secondary": Color(0.88, 0.66, 0.22),
	},
	&"drowned_cutlass": {
		"rig": &"drowned",
		"meshes": ["Drowned_Body", "Drowned_Bandana"],
		"primary": Color(0.20, 0.34, 0.34),
		"secondary": Color(0.56, 0.22, 0.20),
	},
	&"drowned_shield": {
		"rig": &"drowned",
		"meshes": ["Drowned_Body", "Drowned_Bandana", "Drowned_Shield"],
		"primary": Color(0.24, 0.28, 0.38),
		"secondary": Color(0.64, 0.48, 0.22),
	},
	&"drowned_powder": {
		"rig": &"drowned",
		"meshes": ["Drowned_Body", "Drowned_PowderKeg"],
		"primary": Color(0.24, 0.24, 0.26),
		"secondary": Color(1.0, 0.98, 0.96),
	},
	&"drowned_captain": {
		"rig": &"drowned",
		"meshes": ["Drowned_Body", "Drowned_CaptainHat", "Drowned_Coat"],
		"primary": Color(0.12, 0.28, 0.32),
		"secondary": Color(0.26, 0.68, 0.56),
	},
	&"tidecaller": {
		"rig": &"tidecaller",
		"meshes": ["Tidecaller_Body"],
		"primary": Color(0.08, 0.36, 0.46),
		"secondary": Color(0.82, 0.62, 0.24),
	},
	&"corsair_raider": {
		"rig": &"pirate",
		"meshes": ["Body", "Hat_Bandana", "Vest_Crew", "Eyepatch", "Belt_Sash"],
		"primary": Color(0.56, 0.12, 0.14),
		"secondary": Color(0.16, 0.16, 0.18),
	},
	&"rival_captain": {
		"rig": &"pirate",
		"meshes": ["Body", "Hat_Tricorne", "Coat_Captain", "Beard_Full", "Belt_Sash"],
		"primary": Color(0.46, 0.10, 0.16),
		"secondary": Color(0.88, 0.68, 0.20),
	},
}

const DEFAULT_CARRY_LOCAL := Vector3(0.0, 1.0, -0.56)

@export var archetype: StringName = &"captain":
	get:
		return _archetype
	set(value):
		if is_node_ready():
			set_archetype(value)
		else:
			_archetype = value

var skeleton: Skeleton3D = null
var hand_right: BoneAttachment3D = null
var hand_left: BoneAttachment3D = null
var head_socket: BoneAttachment3D = null
var back_socket: BoneAttachment3D = null
var carry_anchor: Node3D = null
var first_person_hidden: bool = false

var _archetype: StringName = &"captain"
var _rig_key: StringName = &""
var _rig_root: Node3D = null
var _meshes: Dictionary = {} # String -> MeshInstance3D
var _active_mesh_names: Array[String] = []
var _primary_mat: StandardMaterial3D = null
var _secondary_mat: StandardMaterial3D = null
var _primary_tint: Color = Color(0.14, 0.25, 0.50)
var _secondary_tint: Color = Color(0.78, 0.16, 0.16)
var _built: bool = false


func _ready() -> void:
	_ensure_carry_anchor()
	if not _built:
		set_archetype(_archetype)


## All supported archetype identifiers.
static func get_archetype_names() -> Array[StringName]:
	var names: Array[StringName] = []
	for k: StringName in ARCHETYPES.keys():
		names.append(k)
	return names


## Configure the visual rig and modular clothing pieces for `arch`.
func set_archetype(arch: StringName) -> void:
	var resolved := arch
	if not ARCHETYPES.has(resolved):
		push_warning("CharacterVisual: unknown archetype '%s', falling back to 'captain'." % String(arch))
		resolved = &"captain"
	_archetype = resolved
	_ensure_carry_anchor()

	var spec: Dictionary = ARCHETYPES[resolved]
	var want_rig: StringName = spec["rig"]
	var rig_swapped := false
	if _rig_root == null or _rig_key != want_rig:
		_load_rig(want_rig)
		rig_swapped = true

	_active_mesh_names.clear()
	for mesh_name: String in spec["meshes"]:
		_active_mesh_names.append(mesh_name)
	_apply_mesh_visibility()

	set_tint(spec["primary"] as Color, spec["secondary"] as Color)
	_built = true

	if rig_swapped:
		rig_changed.emit(skeleton)
	archetype_changed.emit(_archetype)


func get_archetype() -> StringName:
	return _archetype


## Hide or reveal character meshes cleanly for first-person view without losing archetype state.
func set_first_person_hidden(hidden: bool) -> void:
	first_person_hidden = hidden
	_apply_mesh_visibility()


## Apply per-instance primary and secondary cloth tints without mutating shared mesh resources.
func set_tint(primary: Color, secondary: Color) -> void:
	_primary_tint = primary
	_secondary_tint = secondary
	if _rig_root == null:
		set_archetype(archetype)
		_primary_tint = primary
		_secondary_tint = secondary
	if _primary_mat != null:
		_primary_mat.albedo_color = _primary_tint
	if _secondary_mat != null:
		_secondary_mat.albedo_color = _secondary_tint


func get_primary_tint() -> Color:
	return _primary_tint


func get_secondary_tint() -> Color:
	return _secondary_tint


## Return currently enabled meshes for this archetype (regardless of first-person hide state).
func get_active_meshes() -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for mesh_name in _active_mesh_names:
		if _meshes.has(mesh_name):
			out.append(_meshes[mesh_name] as MeshInstance3D)
	return out


## Return every MeshInstance3D present in the currently loaded rig.
func get_all_meshes() -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for mi in _meshes.values():
		out.append(mi as MeshInstance3D)
	return out


## Combined rest-space AABB of active meshes in CharacterVisual local space.
func get_bounds() -> AABB:
	var combined := AABB()
	var has_any := false
	for mi in get_active_meshes():
		if mi.mesh == null:
			continue
		var bb := mi.mesh.get_aabb()
		if not has_any:
			combined = bb
			has_any = true
		else:
			combined = combined.merge(bb)
	return combined


# ------------------------------------------------------------------ internals

func _ensure_carry_anchor() -> void:
	if carry_anchor != null and is_instance_valid(carry_anchor):
		return
	carry_anchor = get_node_or_null(^"CarryAnchor") as Node3D
	if carry_anchor == null:
		carry_anchor = Node3D.new()
		carry_anchor.name = "CarryAnchor"
		carry_anchor.position = DEFAULT_CARRY_LOCAL
		add_child(carry_anchor)


func _load_rig(rig_key: StringName) -> void:
	var saved_attachments := _detach_socket_children()
	if _rig_root != null and is_instance_valid(_rig_root):
		remove_child(_rig_root)
		_rig_root.queue_free()
	_rig_root = null
	skeleton = null
	hand_right = null
	hand_left = null
	head_socket = null
	back_socket = null
	_meshes.clear()
	_primary_mat = null
	_secondary_mat = null

	var scene: PackedScene = RIG_SCENES.get(rig_key)
	assert(scene != null, "CharacterVisual: missing rig scene for %s" % String(rig_key))
	_rig_root = scene.instantiate() as Node3D
	_rig_root.name = "Rig"
	add_child(_rig_root)
	_rig_key = rig_key

	var skels := _rig_root.find_children("*", "Skeleton3D", true, false)
	if skels.size() > 0:
		skeleton = skels[0] as Skeleton3D

	for node in _rig_root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi == null:
			continue
		mi.extra_cull_margin = 0.5
		_meshes[String(mi.name)] = mi

	_setup_instance_materials()
	_setup_sockets(saved_attachments)


func _setup_instance_materials() -> void:
	for mi: MeshInstance3D in _meshes.values():
		if mi.mesh == null:
			continue
		for si in mi.mesh.get_surface_count():
			var base_mat := mi.mesh.surface_get_material(si)
			if base_mat == null:
				continue
			var rname := base_mat.resource_name
			if rname == "mat_cloth_primary":
				if _primary_mat == null:
					_primary_mat = base_mat.duplicate() as StandardMaterial3D
					_primary_mat.resource_name = "mat_cloth_primary_instance"
				mi.set_surface_override_material(si, _primary_mat)
			elif rname == "mat_cloth_secondary":
				if _secondary_mat == null:
					_secondary_mat = base_mat.duplicate() as StandardMaterial3D
					_secondary_mat.resource_name = "mat_cloth_secondary_instance"
				mi.set_surface_override_material(si, _secondary_mat)


func _detach_socket_children() -> Dictionary:
	var saved := {
		"hand_right": [],
		"hand_left": [],
		"head_socket": [],
		"back_socket": [],
	}
	var pairs := [
		["hand_right", hand_right],
		["hand_left", hand_left],
		["head_socket", head_socket],
		["back_socket", back_socket],
	]
	for pair in pairs:
		var sock: BoneAttachment3D = pair[1]
		if sock == null or not is_instance_valid(sock):
			continue
		var children: Array = []
		for c in sock.get_children():
			sock.remove_child(c)
			children.append(c)
		saved[pair[0]] = children
	return saved


func _setup_sockets(saved_attachments: Dictionary) -> void:
	if skeleton == null:
		return
	hand_right = _create_socket("HandRight", "Hand_R", saved_attachments.get("hand_right", []))
	hand_left = _create_socket("HandLeft", "Hand_L", saved_attachments.get("hand_left", []))
	head_socket = _create_socket("HeadSocket", "Head", saved_attachments.get("head_socket", []))
	back_socket = _create_socket("BackSocket", "Chest", saved_attachments.get("back_socket", []))


func _create_socket(node_name: String, bone: String, children: Array) -> BoneAttachment3D:
	var sock := BoneAttachment3D.new()
	sock.name = node_name
	sock.bone_name = bone
	skeleton.add_child(sock)
	for child in children:
		sock.add_child(child as Node)
	return sock


func _apply_mesh_visibility() -> void:
	for mesh_name: String in _meshes.keys():
		var mi: MeshInstance3D = _meshes[mesh_name]
		if first_person_hidden:
			mi.visible = false
		else:
			mi.visible = _active_mesh_names.has(mesh_name)
