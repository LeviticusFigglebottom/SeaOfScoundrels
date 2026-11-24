class_name TickProbe
extends Node
## Runs a callable at the END of every physics tick (after pawns and
## controllers), so tests can sample state that is consistent within a tick.

var fn: Callable

func _init(p_fn: Callable = Callable()) -> void:
	fn = p_fn
	process_physics_priority = 1000

func _physics_process(delta: float) -> void:
	if fn.is_valid():
		fn.call(delta)
