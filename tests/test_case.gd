class_name TestCase
extends Node
## Minimal test base. Subclass in tests/test_*.gd; methods named test_* run.
## Tests may `await` (e.g. physics frames). Use the check_* helpers.

var failures: Array[String] = []
var _current: String = ""

func check(cond: bool, msg: String = "") -> void:
	if not cond:
		failures.append("%s: %s" % [_current, msg if msg != "" else "check failed"])

func check_eq(a: Variant, b: Variant, msg: String = "") -> void:
	if a != b:
		failures.append("%s: expected %s == %s %s" % [_current, a, b, msg])

func check_near(a: float, b: float, tol: float = 0.001, msg: String = "") -> void:
	if absf(a - b) > tol:
		failures.append("%s: expected %f ~= %f (tol %f) %s" % [_current, a, b, tol, msg])

## Wait n physics frames.
func physics_frames(n: int) -> void:
	for _i in n:
		await get_tree().physics_frame
