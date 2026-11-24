class_name FoamField
extends SubViewport
## Simulated foam for `Ocean`: a small float texture that remembers where the
## water has been whitened, so foam lingers and disperses instead of blinking
## with the crest that made it.
##
## The texture is one square tile of `tile_size` metres in REST-plane
## coordinates (the wave function's undisplaced plane), addressed with wrap
## around, so it never has to scroll as the camera moves and foam rides the
## waves. Each frame, without clearing: everything decays, breaking crests
## (Jacobian of the shared wave set) are written in, a band on the far side of
## the tile is wiped before it wraps into view, and queued stamps
## (`Ocean.add_foam`: wakes, splashes, impacts) are drawn on top.

const DECAY_SHADER := "
shader_type canvas_item;
render_mode blend_mul, unshaded;
uniform float decay = 0.98;
void fragment() { COLOR = vec4(vec3(decay), 1.0); }
"

const INJECT_SHADER := "
shader_type canvas_item;
render_mode blend_mix, unshaded;
#include \"res://src/ocean/waves.gdshaderinc\"
uniform vec2 center;
uniform float tile = 256.0;
uniform float rate = 0.2;
uniform float crest_start = 0.87;
uniform float crest_full = 0.46;
void fragment() {
	// the copy of this texel nearest the camera
	vec2 rest = center + (fract(UV - center / tile + 0.5) - 0.5) * tile;
	float j = sea_jacobian_lod(rest, sea_time, 0.0);
	float f = smoothstep(crest_start, crest_full, j);
	// wipe the far band so stale foam never wraps back in
	float wipe = smoothstep(0.445, 0.485, distance(rest, center) / tile);
	// blend towards the crest's own strength (never past it), or to zero in the wipe band
	COLOR = vec4(vec3(f * (1.0 - wipe)), max(f * rate, wipe));
}
"

const STAMP_SHADER := "
shader_type canvas_item;
render_mode blend_mix, unshaded;
void fragment() {
	float r = length(UV - 0.5) * 2.0;
	COLOR = vec4(1.0, 1.0, 1.0, COLOR.a * smoothstep(1.0, 0.35, r));
}
"

var tile_size: float = 256.0
## Seconds for foam to fade to about a third.
var lifetime: float = 7.0

var _decay: ShaderMaterial
var _inject: ShaderMaterial
var _stamps: Node2D
var _queue: Array[Vector4] = []  # rest x, rest z, radius, strength
var _white: ImageTexture

func _init(resolution: int = 512, tile: float = 256.0) -> void:
	tile_size = tile
	size = Vector2i(resolution, resolution)
	disable_3d = true
	use_hdr_2d = true
	transparent_bg = true
	render_target_clear_mode = SubViewport.CLEAR_MODE_ONCE
	render_target_update_mode = SubViewport.UPDATE_ALWAYS
	gui_disable_input = true

func _ready() -> void:
	var full := Vector2(size)
	_decay = _material(DECAY_SHADER)
	_add_rect(_decay, full)
	_inject = _material(INJECT_SHADER)
	_inject.set_shader_parameter(&"tile", tile_size)
	Sea.bind_material(_inject)
	_add_rect(_inject, full)
	var img := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	_white = ImageTexture.create_from_image(img)
	_stamps = Node2D.new()
	_stamps.material = _material(STAMP_SHADER)
	_stamps.draw.connect(_draw_stamps)
	add_child(_stamps)

func _material(code: String) -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = code
	var m := ShaderMaterial.new()
	m.shader = sh
	return m

func _add_rect(mat: ShaderMaterial, full: Vector2) -> void:
	var r := ColorRect.new()
	r.size = full
	r.material = mat
	add_child(r)

## Queue a soft disc of foam at a rest-plane point.
func stamp(rest: Vector2, radius: float, strength: float) -> void:
	if _queue.size() < 512:
		_queue.append(Vector4(rest.x, rest.y, radius, clampf(strength, 0.0, 1.0)))

## Advance one frame. `center` is the camera's rest-plane position.
func step(delta: float, center: Vector2, crest_start: float, crest_full: float) -> void:
	var storm := Sea.sea_state()
	_decay.set_shader_parameter(&"decay", exp(-delta / (lifetime * lerpf(0.7, 1.6, storm))))
	_inject.set_shader_parameter(&"center", center)
	_inject.set_shader_parameter(&"rate", clampf(delta * 7.0, 0.0, 1.0))
	_inject.set_shader_parameter(&"crest_start", crest_start)
	_inject.set_shader_parameter(&"crest_full", crest_full)
	_stamps.queue_redraw()

func _draw_stamps() -> void:
	var n := float(size.x)
	var px_per_m := n / tile_size
	for s in _queue:
		var r := maxf(s.z * px_per_m, 1.5)
		var c := Vector2(fposmod(s.x, tile_size), fposmod(s.y, tile_size)) * px_per_m
		var col := Color(1.0, 1.0, 1.0, s.w)
		# draw the wrapped copies too when the disc crosses the tile edge
		for oy: float in [-n, 0.0, n]:
			for ox: float in [-n, 0.0, n]:
				var p := c + Vector2(ox, oy)
				if p.x + r < 0.0 or p.y + r < 0.0 or p.x - r > n or p.y - r > n:
					continue
				_stamps.draw_texture_rect(_white, Rect2(p - Vector2(r, r), Vector2(r, r) * 2.0), false, col)
	_queue.clear()
