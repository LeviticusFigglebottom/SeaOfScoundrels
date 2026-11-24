extends Node
## Top-level game/session state. Kept deliberately thin; systems own their data.

## Emitted for crew banner-style notifications (diegetic where possible).
signal notice(text: String)

var profile := Profile.new()

func _ready() -> void:
	profile.load_from()

func post_notice(text: String) -> void:
	notice.emit(text)

func save() -> void:
	var err := profile.save()
	if err != OK:
		push_warning("Could not save profile: %s" % error_string(err))
