class_name LocationBanner
extends CanvasLayer
## Cinematic Sea-of-Thieves arrival & encounter nameplate banner (non-blocking).
##
## Renders a handcrafted painterly brass-and-parchment top-center banner with
## tapered horizontal divider rules, a central 8-point miniature compass star,
## mirrored nautical scroll brackets, bold uppercase title, and centered
## maritime subtitle across 3 visual styles (&"island", &"outpost", &"threat").
## All controls use MOUSE_FILTER_IGNORE so the banner never blocks UI or clicks.

signal banner_shown(title: String, subtitle: String, style: StringName)

const FADE_IN_SECONDS := 0.45
const FADE_OUT_SECONDS := 0.65
const DEFAULT_HOLD_SECONDS := 3.2
const SHIMMER_DURATION := 1.15
const MAX_QUEUE_SIZE := 2
const VALID_STYLES: Array[StringName] = [&"island", &"outpost", &"threat"]

const SFX_OUTPOST := &"ship_bell"
const SFX_ISLAND := &"ui_open"
const SFX_THREAT := &"thunder_far"
const SFX_OUTPOST_DB := -7.0
const SFX_ISLAND_DB := -5.0
const SFX_THREAT_DB := -6.5

const BANNER_TOP_Y := 86.0
const BANNER_BOTTOM_Y := 178.0

## Set to false in quiet/headless tests to suppress 2D arrival audio cues.
var play_audio: bool = true
## Most recent manifest-verified arrival SFX played (persists until reset_audio_stats()).
var last_arrival_sfx: StringName = &""
## Cumulative arrival SFX cues played across activated banners (reset only via reset_audio_stats()).
var arrival_sfx_count: int = 0

var _root: Control = null
var _art: _BannerArt = null

var _active: bool = false
var _current_title: String = ""
var _current_subtitle: String = ""
var _current_style: StringName = &"island"
var _hold_seconds: float = DEFAULT_HOLD_SECONDS
var _elapsed: float = 0.0
var _alpha: float = 0.0
var _slide_progress: float = 0.0
var _rule_reveal: float = 0.0
var _shimmer_progress: float = 0.0
var _queue: Array[Dictionary] = []


func _ready() -> void:
	layer = 14
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_ui()


func _exit_tree() -> void:
	clear_banner()
	if _art != null and is_instance_valid(_art):
		_art._font = null


func _process(delta: float) -> void:
	step_banner(delta)


func _ensure_ui() -> void:
	if _root != null and is_instance_valid(_root):
		return
	layer = 14
	_root = Control.new()
	_root.name = "LocationBannerRoot"
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_art = _BannerArt.new()
	_art.name = "BannerArt"
	_art.anchor_left = 0.0
	_art.anchor_right = 1.0
	_art.anchor_top = 0.0
	_art.anchor_bottom = 0.0
	_art.offset_left = 0.0
	_art.offset_right = 0.0
	_art.offset_top = BANNER_TOP_Y
	_art.offset_bottom = BANNER_BOTTOM_Y
	_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_art.visible = false
	_root.add_child(_art)


## Display a location or encounter nameplate banner, queuing up to 2 pending banners
## and deduplicating consecutive identical titles. Returns true if displayed or queued.
func show_location(
	title: String,
	subtitle: String = "",
	style: StringName = &"island",
	hold_seconds: float = DEFAULT_HOLD_SECONDS
) -> bool:
	_ensure_ui()
	var clean_title := sanitize_ascii(title).strip_edges().to_upper()
	if clean_title == "":
		return false
	var clean_sub := sanitize_ascii(subtitle).strip_edges()
	var clean_style := style if VALID_STYLES.has(style) else &"island"
	var clean_hold := maxf(hold_seconds, 0.1)

	if _active:
		var last_title := _current_title if _queue.is_empty() else String(_queue[_queue.size() - 1]["title"])
		if clean_title == last_title:
			return false
		if _queue.size() >= MAX_QUEUE_SIZE:
			return false
		_queue.append({
			"title": clean_title,
			"subtitle": clean_sub,
			"style": clean_style,
			"hold": clean_hold,
		})
		return true

	_activate_entry(clean_title, clean_sub, clean_style, clean_hold)
	return true


## Return the manifest-verified 2D arrival SFX id for a banner visual style.
static func arrival_sfx_for_style(style: StringName) -> StringName:
	match style:
		&"outpost":
			return SFX_OUTPOST
		&"threat":
			return SFX_THREAT
		_:
			return SFX_ISLAND


static func _arrival_sfx_volume_db(style: StringName) -> float:
	match style:
		&"outpost":
			return SFX_OUTPOST_DB
		&"threat":
			return SFX_THREAT_DB
		_:
			return SFX_ISLAND_DB


## Explicitly reset arrival SFX telemetry counters back to initial idle values.
func reset_audio_stats() -> void:
	last_arrival_sfx = &""
	arrival_sfx_count = 0


func _play_arrival_sfx(style: StringName) -> void:
	if not play_audio:
		return
	var sfx_id := arrival_sfx_for_style(style)
	if sfx_id == &"" or Audio == null or not Audio.has_sound(sfx_id):
		return
	Audio.play_sfx(sfx_id, Vector3.INF, _arrival_sfx_volume_db(style))
	last_arrival_sfx = sfx_id
	arrival_sfx_count += 1


func _activate_entry(title: String, subtitle: String, style: StringName, hold_seconds: float) -> void:
	_active = true
	_current_title = title
	_current_subtitle = subtitle
	_current_style = style
	_hold_seconds = maxf(hold_seconds, 0.1)
	_elapsed = 0.0
	_alpha = 0.0
	_slide_progress = 0.0
	_rule_reveal = 0.0
	_shimmer_progress = 0.0
	_play_arrival_sfx(_current_style)
	_sync_art()
	banner_shown.emit(_current_title, _current_subtitle, _current_style)


## Advance banner animation timers smoothly (called from `_process` and directly in tests).
func step_banner(delta: float) -> void:
	if _art == null or not is_instance_valid(_art):
		if _active:
			_ensure_ui()
		else:
			return
	if not _active:
		if _art.visible:
			_art.visible = false
		return

	var dt := maxf(delta, 0.0)
	_elapsed += dt
	var hold_end := FADE_IN_SECONDS + _hold_seconds
	var total_dur := hold_end + FADE_OUT_SECONDS

	var shimmer_next := 1.0 if _elapsed >= SHIMMER_DURATION - 0.0001 else clampf(_elapsed / SHIMMER_DURATION, 0.0, 1.0)
	if _elapsed < FADE_IN_SECONDS:
		var t := clampf(_elapsed / FADE_IN_SECONDS, 0.0, 1.0)
		_alpha = t * t * (3.0 - 2.0 * t)
		_slide_progress = 1.0 - pow(1.0 - t, 3.0)
		_rule_reveal = _slide_progress
		_shimmer_progress = shimmer_next
	elif _elapsed < hold_end:
		_alpha = 1.0
		_slide_progress = 1.0
		_rule_reveal = 1.0
		_shimmer_progress = shimmer_next
	elif _elapsed < total_dur:
		var t := clampf((_elapsed - hold_end) / FADE_OUT_SECONDS, 0.0, 1.0)
		_alpha = 1.0 - (t * t * (3.0 - 2.0 * t))
		_slide_progress = 1.0 + t * 0.25
		_rule_reveal = 1.0
		_shimmer_progress = shimmer_next
	else:
		if not _queue.is_empty():
			var next_entry: Dictionary = _queue.pop_front()
			_activate_entry(
				String(next_entry["title"]),
				String(next_entry["subtitle"]),
				StringName(next_entry["style"]),
				float(next_entry["hold"])
			)
			return
		_active = false
		_current_title = ""
		_current_subtitle = ""
		_elapsed = 0.0
		_alpha = 0.0
		_slide_progress = 0.0
		_rule_reveal = 0.0
		_shimmer_progress = 0.0
		_art.shimmer_progress = 0.0
		_art.visible = false
		return

	_sync_art()


func _sync_art() -> void:
	if _art == null or not is_instance_valid(_art):
		return
	_art.title_text = _current_title
	_art.subtitle_text = _current_subtitle
	_art.style_id = _current_style
	_art.alpha = _alpha
	_art.slide_progress = _slide_progress
	_art.rule_reveal = _rule_reveal
	_art.shimmer_progress = _shimmer_progress
	_art.visible = _active
	_art.queue_redraw()


## True while a banner nameplate is currently active on screen.
func is_banner_active() -> bool:
	return _active


## Return the active banner's sanitized uppercase title (or "" when idle).
func get_current_title() -> String:
	return _current_title if _active else ""


## Return the active banner's sanitized subtitle (or "" when idle).
func get_current_subtitle() -> String:
	return _current_subtitle if _active else ""


## Return the active banner's visual style (&"island", &"outpost", or &"threat").
func get_current_style() -> StringName:
	return _current_style


## Return the active banner's current fade opacity in 0..1.
func get_current_alpha() -> float:
	return _alpha if _active else 0.0


## Return the arrival gilded shimmer sweep progress in 0..1 across SHIMMER_DURATION.
func get_shimmer_progress() -> float:
	return _shimmer_progress if _active else 0.0


## Return the number of queued pending banners waiting behind the active card.
func get_queued_count() -> int:
	return _queue.size()


## Return the current animation phase (&"idle", &"fade_in", &"hold", or &"fade_out").
func get_banner_phase() -> StringName:
	if not _active:
		return &"idle"
	if _elapsed < FADE_IN_SECONDS:
		return &"fade_in"
	if _elapsed < FADE_IN_SECONDS + _hold_seconds:
		return &"hold"
	return &"fade_out"


## Immediately dismiss the active banner and clear all pending queued entries.
func clear_banner() -> void:
	_active = false
	_queue.clear()
	_current_title = ""
	_current_subtitle = ""
	_current_style = &"island"
	_elapsed = 0.0
	_alpha = 0.0
	_slide_progress = 0.0
	_rule_reveal = 0.0
	_shimmer_progress = 0.0
	if _art != null and is_instance_valid(_art):
		_art.visible = false
		_art.alpha = 0.0
		_art.shimmer_progress = 0.0
		_art.title_text = ""
		_art.subtitle_text = ""
		_art.queue_redraw()


## Sanitize any string to strict printable ASCII (< 128), mapping common typography gracefully.
static func sanitize_ascii(text: String) -> String:
	if text == "":
		return ""
	var mapped := text.replace(char(0x2014), "--").replace(char(0x2013), "-")
	mapped = mapped.replace(char(0x2018), "'").replace(char(0x2019), "'")
	mapped = mapped.replace(char(0x201C), "\"").replace(char(0x201D), "\"")
	mapped = mapped.replace(char(0x2026), "...")
	mapped = mapped.replace(char(0x00B7), "|").replace(char(0x2022), "*")
	var out := ""
	for i in mapped.length():
		var code := mapped.unicode_at(i)
		if code >= 32 and code < 128:
			out += char(code)
	return out


## Build a rich strict-ASCII maritime subtitle for any Archipelago island archetype.
static func format_island_subtitle(island: Node) -> String:
	if island == null:
		return "Uncharted Sea Isle"
	var arch_v: Variant = island.get(&"archetype")
	var arch := StringName(String(arch_v)) if arch_v != null else &""
	var outpost_v: Variant = island.get(&"is_outpost")
	var is_out := bool(outpost_v) if outpost_v is bool else false
	var rad_v: Variant = island.get(&"radius")
	var radius := float(rad_v) if (rad_v is float or rad_v is int) else 0.0
	if radius <= 0.0:
		var irad_v: Variant = island.get(&"island_radius")
		if irad_v is float or irad_v is int:
			radius = float(irad_v)

	match arch:
		&"grand_outpost":
			return "Capital Outpost -- Grand Harbour"
		&"outpost", &"outpost_harbour":
			return "Outpost Harbour -- Safe Anchorage"
		&"grand_citadel":
			return "Grand Citadel -- Tier IV Sea Fortress"
		&"fort_rock":
			return "Fortified Sea Bastion"
		&"volcano_crag":
			return "Active Volcanic Caldera"
		&"smuggler_cove":
			return "Smuggler's Hidden Cove"
		&"twin_spires":
			return "Twin-Spire Jungle Isle"
		&"crescent_lagoon":
			return "Turquoise Coral Lagoon"
		&"palm_atoll":
			return "Coral Reef Atoll"
		&"wreck_shoal":
			return "Shipwreck Reef Shoal"
		&"skull_bluff":
			return "Cursed Skull Bluff"
		&"sea_arch":
			return "Coastal Sea Arch"
		&"sea_stack":
			return "Towering Sea-Stack Monolith"
		&"treasure_peak", &"treasure_cove":
			return "Uncharted Treasure Cay"

	if is_out:
		return "Outpost Harbour -- Safe Anchorage"
	if radius >= 150.0:
		return "Grand Frontier Island"
	if radius >= 105.0:
		return "Charted Frontier Isle"
	if radius > 0.0 and radius < 55.0:
		return "Small Uncharted Cay"
	return "Uncharted Treasure Cay"


## Select the cinematic visual style (&"outpost", &"threat", or &"island") for an island node.
static func style_for_island(island: Node) -> StringName:
	if island == null:
		return &"island"
	var arch_v: Variant = island.get(&"archetype")
	var arch := StringName(String(arch_v)) if arch_v != null else &""
	var outpost_v: Variant = island.get(&"is_outpost")
	var is_out := bool(outpost_v) if outpost_v is bool else false
	if is_out or arch == &"outpost" or arch == &"grand_outpost" or arch == &"outpost_harbour":
		return &"outpost"
	if arch == &"fort_rock" or arch == &"grand_citadel" or arch == &"volcano_crag":
		return &"threat"
	return &"island"


# ==============================================================================
# Handcrafted Vector-Drawn Maritime Banner Control
# ==============================================================================

class _BannerArt:
	extends Control

	var title_text: String = ""
	var subtitle_text: String = ""
	var style_id: StringName = &"island"
	var alpha: float = 0.0
	var slide_progress: float = 1.0
	var rule_reveal: float = 1.0
	var shimmer_progress: float = 0.0
	var _font: Font = null


	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE


	func _get_palette(style: StringName) -> Dictionary:
		match style:
			&"outpost":
				return {
					"scrim_outer": Color(0.11, 0.08, 0.04, 0.72),
					"scrim_inner": Color(0.28, 0.21, 0.11, 0.42),
					"filigree": Color(1.0, 0.90, 0.62, 0.96),
					"trim": Color(0.88, 0.72, 0.34, 0.92),
					"title": Color(1.0, 0.97, 0.88, 1.0),
					"subtitle": Color(1.0, 0.90, 0.62, 0.96),
					"gem": Color(1.0, 0.94, 0.68, 1.0),
					"shadow": Color(0.05, 0.03, 0.01, 0.86),
					"shimmer_hi": Color(1.0, 0.96, 0.74, 0.96),
					"shimmer_halo": Color(1.0, 0.86, 0.42, 0.48),
					"shimmer_core": Color(1.0, 0.99, 0.92, 1.0),
				}
			&"threat":
				return {
					"scrim_outer": Color(0.07, 0.04, 0.06, 0.80),
					"scrim_inner": Color(0.24, 0.07, 0.09, 0.44),
					"filigree": Color(0.96, 0.36, 0.28, 0.96),
					"trim": Color(0.24, 0.94, 0.86, 0.90),
					"title": Color(1.0, 0.88, 0.84, 1.0),
					"subtitle": Color(0.24, 0.94, 0.86, 0.96),
					"gem": Color(0.96, 0.36, 0.28, 1.0),
					"shadow": Color(0.03, 0.01, 0.02, 0.92),
					"shimmer_hi": Color(0.38, 0.98, 0.90, 0.96),
					"shimmer_halo": Color(0.98, 0.34, 0.26, 0.52),
					"shimmer_core": Color(0.86, 1.0, 0.97, 1.0),
				}
			_:
				return {
					"scrim_outer": Color(0.11, 0.08, 0.05, 0.74),
					"scrim_inner": Color(0.24, 0.17, 0.10, 0.38),
					"filigree": Color(0.95, 0.84, 0.56, 0.96),
					"trim": Color(0.76, 0.58, 0.28, 0.90),
					"title": Color(0.98, 0.93, 0.78, 1.0),
					"subtitle": Color(0.95, 0.84, 0.56, 0.95),
					"gem": Color(0.96, 0.82, 0.42, 1.0),
					"shadow": Color(0.05, 0.03, 0.01, 0.88),
					"shimmer_hi": Color(1.0, 0.94, 0.68, 0.95),
					"shimmer_halo": Color(0.96, 0.80, 0.38, 0.46),
					"shimmer_core": Color(1.0, 0.98, 0.88, 1.0),
				}


	func _col_a(c: Color, mult: float = 1.0) -> Color:
		return Color(c.r, c.g, c.b, c.a * clampf(alpha * mult, 0.0, 1.0))


	func _draw() -> void:
		if alpha <= 0.004 or title_text == "":
			return
		if _font == null:
			_font = HudIcons.get_ui_font()
		var font: Font = _font if _font != null else ThemeDB.fallback_font
		if font == null:
			return

		var w := size.x if size.x > 40.0 else 1280.0
		var h := size.y if size.y > 20.0 else (BANNER_BOTTOM_Y - BANNER_TOP_Y)
		var cx := w * 0.5
		var slide_y := (1.0 - slide_progress) * -14.0
		var cy := h * 0.5 + slide_y

		var pal := _get_palette(style_id)
		var col_scrim_out: Color = pal["scrim_outer"]
		var col_scrim_in: Color = pal["scrim_inner"]
		var col_fil: Color = pal["filigree"]
		var col_trim: Color = pal["trim"]
		var col_title: Color = pal["title"]
		var col_sub: Color = pal["subtitle"]
		var col_gem: Color = pal["gem"]
		var col_shad: Color = pal["shadow"]

		var title_fs := 26
		var sub_fs := 15
		var max_title_w := minf(w - 140.0, 560.0)
		var title_sz := font.get_string_size(title_text, HORIZONTAL_ALIGNMENT_LEFT, -1, title_fs)
		while title_fs > 17 and title_sz.x > max_title_w:
			title_fs -= 1
			title_sz = font.get_string_size(title_text, HORIZONTAL_ALIGNMENT_LEFT, -1, title_fs)

		var sub_sz := Vector2.ZERO
		if subtitle_text != "":
			sub_sz = font.get_string_size(subtitle_text, HORIZONTAL_ALIGNMENT_LEFT, -1, sub_fs)
			while sub_fs > 11 and sub_sz.x > max_title_w:
				sub_fs -= 1
				sub_sz = font.get_string_size(subtitle_text, HORIZONTAL_ALIGNMENT_LEFT, -1, sub_fs)

		var core_half_w := clampf(maxf(title_sz.x, sub_sz.x) * 0.5 + 78.0, 210.0, minf(w * 0.44, 345.0))
		var reveal := clampf(rule_reveal, 0.15, 1.0)
		var half_w := core_half_w * lerpf(0.76, 1.0, reveal)
		var half_h := 39.0 if subtitle_text != "" else 28.0

		# 1. Weathered curved tapered maritime scrim backdrop (layered feathered ribbon).
		_draw_tapered_ribbon(cx, cy, half_w + 56.0, half_h + 6.0, 0.42, _col_a(col_scrim_out, 0.52))
		_draw_tapered_ribbon(cx, cy, half_w + 18.0, half_h, 0.72, _col_a(col_scrim_out, 0.92))
		_draw_tapered_ribbon(cx, cy, half_w - 22.0, half_h - 6.0, 0.84, _col_a(col_scrim_in, 0.88))

		# 2. Subtle top & bottom arched brass framing hairlines.
		var top_arc_y := cy - half_h + 3.0
		var bot_arc_y := cy + half_h - 3.0
		_draw_arched_rule(cx, top_arc_y, half_w * 0.88, -5.0, _col_a(col_trim, 0.55), 1.4)
		_draw_arched_rule(cx, bot_arc_y, half_w * 0.84, 5.0, _col_a(col_trim, 0.48), 1.3)

		# 3. Left & right mirrored nautical baroque scroll brackets framing the nameplate.
		_draw_scroll_bracket(cx, cy, half_w - 14.0, half_h - 8.0, -1.0, _col_a(col_fil, 0.90), _col_a(col_trim, 0.82))
		_draw_scroll_bracket(cx, cy, half_w - 14.0, half_h - 8.0, 1.0, _col_a(col_fil, 0.90), _col_a(col_trim, 0.82))

		# 4. Central tapered horizontal divider rule + 8-point miniature compass star ornament.
		var rule_y := cy + 7.0 if subtitle_text != "" else cy + 16.0
		var rule_span := half_w * 0.86 * reveal
		var star_gap := 16.0
		if rule_span > star_gap + 12.0:
			_draw_tapered_rule_wing(cx - star_gap, cx - rule_span, rule_y, 2.2, _col_a(col_fil, 0.92))
			_draw_tapered_rule_wing(cx + star_gap, cx + rule_span, rule_y, 2.2, _col_a(col_fil, 0.92))
			# Accent diamond dots flanking the star.
			_draw_diamond(Vector2(cx - star_gap - 12.0, rule_y), 3.0, _col_a(col_trim, 0.92))
			_draw_diamond(Vector2(cx + star_gap + 12.0, rule_y), 3.0, _col_a(col_trim, 0.92))
		var star_radius := 11.5 * lerpf(0.65, 1.0, reveal)
		_draw_compass_star(Vector2(cx, rule_y), star_radius,
			_col_a(col_fil, 0.98), _col_a(col_trim, 0.92), _col_a(col_gem, 0.98))

		# 4b. Arrival sweeping gilded shimmer across divider wings & compass star sunburst flare.
		if shimmer_progress > 0.0 and shimmer_progress < 1.0:
			var col_shim_hi: Color = pal["shimmer_hi"]
			var col_shim_halo: Color = pal["shimmer_halo"]
			var col_shim_core: Color = pal["shimmer_core"]
			var wing_bell := sin(shimmer_progress * PI)
			if rule_span > star_gap + 12.0 and wing_bell > 0.004:
				var gleam_dist := lerpf(star_gap, rule_span, shimmer_progress)
				var tip_taper := lerpf(1.0, 0.46, shimmer_progress)
				var gleam_half_len := clampf((rule_span - star_gap) * 0.16, 12.0, 32.0) * tip_taper
				var gleam_half_h := 3.2 * tip_taper
				var wing_min_x := star_gap + 2.0
				var wing_max_x := rule_span - 2.0
				for side: float in [-1.0, 1.0]:
					var gx := cx + side * gleam_dist
					var lo := (cx - wing_max_x) if side < 0.0 else (cx + wing_min_x)
					var hi := (cx - wing_min_x) if side < 0.0 else (cx + wing_max_x)
					var left_x := clampf(gx - gleam_half_len, lo, hi)
					var right_x := clampf(gx + gleam_half_len, lo, hi)
					if right_x - left_x > 2.0:
						var mid_x := (left_x + right_x) * 0.5
						var half_span := (right_x - left_x) * 0.5
						_draw_gleam_diamond(
							Vector2(mid_x, rule_y),
							half_span * 1.28,
							gleam_half_h * 1.65,
							_col_a(col_shim_halo, wing_bell)
						)
						_draw_gleam_diamond(
							Vector2(mid_x, rule_y),
							half_span,
							gleam_half_h,
							_col_a(col_shim_hi, 0.90 * wing_bell)
						)
						_draw_diamond(
							Vector2(mid_x, rule_y),
							(2.2 + 0.9 * wing_bell) * tip_taper,
							_col_a(col_shim_core, 0.95 * wing_bell)
						)

			var star_flare := exp(-pow((shimmer_progress - 0.18) / 0.16, 2.0))
			if star_flare > 0.008:
				_draw_star_sunburst_gleam(
					Vector2(cx, rule_y),
					star_radius,
					star_flare,
					_col_a(col_shim_hi, 0.94 * star_flare),
					_col_a(col_shim_halo, 0.80 * star_flare),
					_col_a(col_shim_core, 0.98 * star_flare)
				)

		# 5. Bold uppercase Location Title with crisp warm dark drop shadow.
		var title_y := (cy - 4.0) if subtitle_text != "" else (cy + 5.0)
		var title_x := cx - title_sz.x * 0.5
		draw_string(font, Vector2(title_x + 2.0, title_y + 2.0), title_text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, title_fs, _col_a(col_shad, 0.95))
		draw_string(font, Vector2(title_x - 1.0, title_y + 1.0), title_text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, title_fs, _col_a(col_shad, 0.50))
		draw_string(font, Vector2(title_x, title_y), title_text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, title_fs, _col_a(col_title, 1.0))

		# 6. Centered maritime Subtitle below the compass divider rule.
		if subtitle_text != "":
			var sub_y := cy + 28.0
			var sub_x := cx - sub_sz.x * 0.5
			draw_string(font, Vector2(sub_x + 1.5, sub_y + 1.5), subtitle_text,
				HORIZONTAL_ALIGNMENT_LEFT, -1, sub_fs, _col_a(col_shad, 0.92))
			draw_string(font, Vector2(sub_x, sub_y), subtitle_text,
				HORIZONTAL_ALIGNMENT_LEFT, -1, sub_fs, _col_a(col_sub, 0.98))


	func _draw_tapered_ribbon(cx: float, cy: float, half_w: float, half_h: float, shoulder_ratio: float, col: Color) -> void:
		if col.a <= 0.002:
			return
		var sx := half_w * shoulder_ratio
		var mid_x := half_w * lerpf(shoulder_ratio, 1.0, 0.52)
		var pts := PackedVector2Array([
			Vector2(cx - half_w, cy),
			Vector2(cx - mid_x, cy - half_h * 0.68),
			Vector2(cx - sx, cy - half_h),
			Vector2(cx, cy - half_h - 3.5),
			Vector2(cx + sx, cy - half_h),
			Vector2(cx + mid_x, cy - half_h * 0.68),
			Vector2(cx + half_w, cy),
			Vector2(cx + mid_x, cy + half_h * 0.68),
			Vector2(cx + sx, cy + half_h),
			Vector2(cx, cy + half_h + 3.5),
			Vector2(cx - sx, cy + half_h),
			Vector2(cx - mid_x, cy + half_h * 0.68),
		])
		draw_colored_polygon(pts, col)


	func _draw_arched_rule(cx: float, base_y: float, half_w: float, arch_h: float, col: Color, width: float) -> void:
		if col.a <= 0.002:
			return
		var pts := PackedVector2Array()
		var steps := 14
		for i in range(steps + 1):
			var u := float(i) / float(steps)
			var nx := lerpf(-1.0, 1.0, u)
			var px := cx + nx * half_w
			var py := base_y + (1.0 - nx * nx) * arch_h
			pts.append(Vector2(px, py))
		draw_polyline(pts, col, width, true)


	func _draw_tapered_rule_wing(x_near: float, x_far: float, y: float, half_thick: float, col: Color) -> void:
		if col.a <= 0.002:
			return
		var x_mid := lerpf(x_near, x_far, 0.45)
		var pts := PackedVector2Array([
			Vector2(x_near, y - half_thick),
			Vector2(x_mid, y - half_thick * 0.62),
			Vector2(x_far, y),
			Vector2(x_mid, y + half_thick * 0.62),
			Vector2(x_near, y + half_thick),
		])
		draw_colored_polygon(pts, col)


	func _draw_scroll_bracket(cx: float, cy: float, offset_x: float, half_h: float, side: float,
			col_main: Color, col_accent: Color) -> void:
		if col_main.a <= 0.002:
			return
		var bx := cx + side * offset_x
		# Curved C-scroll spine with upper & lower nautical wave volutes.
		var spine := PackedVector2Array([
			Vector2(bx - side * 12.0, cy - half_h + 2.0),
			Vector2(bx - side * 2.0, cy - half_h + 4.0),
			Vector2(bx + side * 6.0, cy - half_h * 0.46),
			Vector2(bx + side * 10.0, cy),
			Vector2(bx + side * 6.0, cy + half_h * 0.46),
			Vector2(bx - side * 2.0, cy + half_h - 4.0),
			Vector2(bx - side * 12.0, cy + half_h - 2.0),
		])
		draw_polyline(spine, col_main, 2.0, true)

		# Inner delicate nautical curl echoes at top and bottom tips.
		var upper_curl := PackedVector2Array([
			Vector2(bx - side * 12.0, cy - half_h + 2.0),
			Vector2(bx - side * 18.0, cy - half_h + 7.0),
			Vector2(bx - side * 13.0, cy - half_h + 12.0),
		])
		var lower_curl := PackedVector2Array([
			Vector2(bx - side * 12.0, cy + half_h - 2.0),
			Vector2(bx - side * 18.0, cy + half_h - 7.0),
			Vector2(bx - side * 13.0, cy + half_h - 12.0),
		])
		draw_polyline(upper_curl, col_accent, 1.5, true)
		draw_polyline(lower_curl, col_accent, 1.5, true)

		# Outer brass spearhead finial at bracket apex.
		_draw_diamond(Vector2(bx + side * 14.0, cy), 4.0, col_main)


	func _draw_compass_star(center: Vector2, radius: float, col_major: Color, col_minor: Color, col_core: Color) -> void:
		if col_major.a <= 0.002:
			return
		# 4 diagonal intercardinal points (NE, SE, SW, NW).
		var r_minor := radius * 0.66
		var r_inner_m := radius * 0.22
		for k in 4:
			var ang := PI * 0.25 + float(k) * PI * 0.5
			var tip := center + Vector2(cos(ang), sin(ang)) * r_minor
			var left := center + Vector2(cos(ang - 0.55), sin(ang - 0.55)) * r_inner_m
			var right := center + Vector2(cos(ang + 0.55), sin(ang + 0.55)) * r_inner_m
			draw_colored_polygon(PackedVector2Array([center, left, tip, right]), col_minor)

		# 4 cardinal points (N, E, S, W) forming a crisp 8-point nautical rose.
		var r_inner := radius * 0.27
		for k in 4:
			var ang := float(k) * PI * 0.5
			var tip := center + Vector2(cos(ang), sin(ang)) * radius
			var left := center + Vector2(cos(ang - 0.48), sin(ang - 0.48)) * r_inner
			var right := center + Vector2(cos(ang + 0.48), sin(ang + 0.48)) * r_inner
			draw_colored_polygon(PackedVector2Array([center, left, tip, right]), col_major)

		# Center miniature brass bezel ring and jewel dot.
		draw_circle(center, radius * 0.24, col_core)
		draw_arc(center, radius * 0.34, 0.0, TAU, 16, col_major, 1.2, true)


	func _draw_diamond(center: Vector2, radius: float, col: Color) -> void:
		if col.a <= 0.002:
			return
		var pts := PackedVector2Array([
			center + Vector2(0.0, -radius),
			center + Vector2(radius * 1.15, 0.0),
			center + Vector2(0.0, radius),
			center + Vector2(-radius * 1.15, 0.0),
		])
		draw_colored_polygon(pts, col)


	func _draw_gleam_diamond(center: Vector2, half_len: float, half_h: float, col: Color) -> void:
		if col.a <= 0.002 or half_len <= 0.5 or half_h <= 0.2:
			return
		var pts := PackedVector2Array([
			center + Vector2(-half_len, 0.0),
			center + Vector2(0.0, -half_h),
			center + Vector2(half_len, 0.0),
			center + Vector2(0.0, half_h),
		])
		draw_colored_polygon(pts, col)


	func _draw_star_sunburst_gleam(
		center: Vector2,
		radius: float,
		flare: float,
		col_hi: Color,
		col_halo: Color,
		col_core: Color
	) -> void:
		if col_hi.a <= 0.002:
			return
		# Soft radial warm halo + glowing inner jewel aura.
		draw_circle(center, radius * (0.72 + 0.36 * flare), Color(col_halo.r, col_halo.g, col_halo.b, col_halo.a * 0.55))
		draw_circle(center, radius * (0.42 + 0.22 * flare), col_halo)

		# Crisp 4-ray cardinal sunburst cross.
		var ray_len := radius * (1.28 + 0.52 * flare)
		var ray_half_w := radius * (0.14 + 0.08 * flare)
		_draw_gleam_diamond(center, ray_len, ray_half_w, col_hi)
		_draw_gleam_diamond(center, ray_half_w, ray_len, col_hi)

		# Shorter diagonal glint cross for an 8-point painterly star flare.
		var diag_len := radius * (0.78 + 0.28 * flare) * 0.7071
		var diag_w := 1.45 + 0.65 * flare
		draw_line(center + Vector2(-diag_len, -diag_len), center + Vector2(diag_len, diag_len), col_hi, diag_w, true)
		draw_line(center + Vector2(-diag_len, diag_len), center + Vector2(diag_len, -diag_len), col_hi, diag_w, true)

		# Bright center gleam jewel.
		draw_circle(center, radius * (0.24 + 0.14 * flare), col_core)
