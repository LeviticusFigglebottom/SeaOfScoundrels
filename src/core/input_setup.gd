extends Node
## Registers all input actions in code so project.godot stays merge-friendly.
## Add new actions to ACTIONS; never edit the [input] section of project.godot.

const ACTIONS := {
	"move_forward": [KEY_W],
	"move_back": [KEY_S],
	"move_left": [KEY_A],
	"move_right": [KEY_D],
	"jump": [KEY_SPACE],
	"sprint": [KEY_SHIFT],
	"interact": [KEY_F],
	"leave_station": [KEY_X],
	"primary": ["mouse_left"],
	"secondary": ["mouse_right"],
	"command_wheel": [KEY_Q],
	"item_next": [KEY_E],
	"item_prev": [KEY_C],
	"item_radial": [KEY_TAB],
	"dodge": [KEY_ALT, KEY_V],
	"heavy_attack": [KEY_R],
	"slot_1": [KEY_1],
	"slot_2": [KEY_2],
	"slot_3": [KEY_3],
	"slot_4": [KEY_4],
	"slot_5": [KEY_5],
	"slot_6": [KEY_6],
	"pause": [KEY_ESCAPE],
}

func _enter_tree() -> void:
	for action in ACTIONS:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action, 0.2)
		for code in ACTIONS[action]:
			var ev: InputEvent
			if code is String:
				var mb := InputEventMouseButton.new()
				mb.button_index = MOUSE_BUTTON_LEFT if code == "mouse_left" else MOUSE_BUTTON_RIGHT
				ev = mb
			else:
				var k := InputEventKey.new()
				k.physical_keycode = code
				ev = k
			InputMap.action_add_event(action, ev)
