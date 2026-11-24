extends Node
## Top-level game/session state. Kept deliberately thin; systems own their data.

## Emitted for crew banner-style notifications (diegetic where possible).
signal notice(text: String)

func post_notice(text: String) -> void:
	notice.emit(text)
