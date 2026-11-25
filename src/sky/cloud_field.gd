extends RefCounted
## CPU copy of cloud_column() in cloud_field.gdshaderinc: where the clouds are,
## as a function of world position and the `Weather` state. Used for the shadow
## at the camera (which dims the sun for standard materials) and by gameplay
## that wants to know whether a spot is in sun. Keep the maths in step with the
## shader include.

const MAP := preload("res://assets/generated/sky/cloud_map.png")
const MAP_TILE := 12000.0
const BIG_TILE := 48000.0
const BASE_FAIR := 950.0
const BASE_STORM := 380.0
## Light left under the thickest cloud.
const FLOOR_LIGHT := 0.22

var _img: Image
var _w: int
var _h: int


func _init() -> void:
	_img = MAP.get_image()
	if _img.is_compressed():
		_img.decompress()
	_w = _img.get_width()
	_h = _img.get_height()

static func cell_top(radius: float) -> float:
	return BASE_STORM + clampf(radius * 1.5, 1800.0, 5200.0)

func _tex(uv: Vector2) -> Color:
	## Bilinear, repeating: what the GPU sampler returns at mip 0.
	var x := fposmod(uv.x, 1.0) * _w - 0.5
	var y := fposmod(uv.y, 1.0) * _h - 0.5
	var x0 := floori(x)
	var y0 := floori(y)
	var fx := x - x0
	var fy := y - y0
	var a := _img.get_pixel(posmod(x0, _w), posmod(y0, _h))
	var b := _img.get_pixel(posmod(x0 + 1, _w), posmod(y0, _h))
	var c := _img.get_pixel(posmod(x0, _w), posmod(y0 + 1, _h))
	var d := _img.get_pixel(posmod(x0 + 1, _w), posmod(y0 + 1, _h))
	return a.lerp(b, fx).lerp(c.lerp(d, fx), fy)

func weather_at(xz: Vector2) -> Vector3:
	## x = cloudiness, y = storminess, z = storm cell strength at a position,
	## including the weather front of a transition in progress.
	var pos := Vector3(xz.x, 0.0, xz.y)
	var behind: float = Weather.front_weight(pos)
	var cl: float = lerpf(Weather.front_from.x, Weather.cloudiness, behind) if behind < 1.0 else Weather.cloudiness
	var st: float = lerpf(Weather.front_from.y, Weather.base_storminess, behind) if behind < 1.0 else Weather.base_storminess
	var cell: float = Weather.storm_intensity * Weather.storm_cell_strength(pos)
	return Vector3(cl, maxf(st, cell), cell)

func column(xz: Vector2) -> Dictionary:
	## The cloud column over a world position: `m` > 0 inside a cloud footprint,
	## `base` altitude and `height` of the cloud in metres, `k` dome tightness,
	## `storm` local storminess.
	var q: Vector2 = xz - Weather.cloud_offset
	var a := _tex(q / MAP_TILE)
	var big := _tex(Vector2(q.x * 0.8 + q.y * 0.6, q.y * 0.8 - q.x * 0.6) / BIG_TILE + Vector2(0.37, 0.37)).g
	var w := weather_at(xz)
	var st := w.y
	var cover := clampf(lerpf(w.x, 1.0, smoothstep(0.1, 0.7, st)), 0.0, 1.0)
	var f := a.r * 0.7 + big * 0.3
	var thr := lerpf(0.95, 0.3, cover) - smoothstep(0.72, 1.0, cover) * 0.31
	var m := f - thr
	var heavy := smoothstep(0.2, 0.9, st)
	var base := lerpf(BASE_FAIR, BASE_STORM, heavy)
	var tower := clampf(0.2 + 0.9 * smoothstep(0.25, 0.75, w.x) + 2.0 * st, 0.0, 1.0)
	var h := 450.0 + 2500.0 * a.b * tower
	var deck := smoothstep(0.7, 1.0, cover)
	h = lerpf(h, 700.0 + 900.0 * a.b, deck * (1.0 - 0.5 * heavy))
	h = lerpf(h, 900.0 + 900.0 * big, heavy)
	return {"m": m, "base": base, "height": h, "k": lerpf(0.22, 0.07, deck), "storm": st, "cell": w.z}

func light_at(world_pos: Vector3, towards_light: Vector3) -> float:
	## Fraction of the key light reaching a point near the ground: 1 in open
	## sun, FLOOR_LIGHT under the thickest cloud. Matches the baked shadow texture.
	var shift := shadow_shift(towards_light)
	var c := column(Vector2(world_pos.x, world_pos.z) + shift * cast_height())
	var thick: float = c["height"] * sqrt(clampf(c["m"] / c["k"], 0.0, 1.0)) * 0.8
	return lerpf(FLOOR_LIGHT, 1.0, exp(-thick / 220.0))

static func shadow_shift(towards_light: Vector3) -> Vector2:
	## Ground metres per metre of height towards the light. Low suns are treated
	## as 14 degrees up so shadows do not stretch across the whole sea.
	var flat := Vector2(towards_light.x, towards_light.z)
	return flat / maxf(towards_light.y, 0.25)

func cast_height() -> float:
	## Altitude the shadow is cast from: a little above the cloud base.
	var stormy: float = maxf(Weather.base_storminess, Weather.storm_intensity * 0.5)
	return lerpf(BASE_FAIR, BASE_STORM, smoothstep(0.2, 0.9, stormy)) + 250.0
