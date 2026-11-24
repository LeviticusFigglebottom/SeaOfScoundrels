# Godot 4.8 notes (4.7.2 -> 4.8 beta 5)

Researched 2026-11-24 against `Godot_v4.8-beta5_linux.x86_64` (a661dfdbc).
Evidence tags: **[ran]** = executed here on a scratch copy of this project;
**[api]** = from diffing `--doctool` dumps of 4.7.2 and 4.8b5 (33 new classes, 0 removed);
**[blog]** = official dev 1-7 / beta 1-5 posts; **[log]** = interactive changelog data (1,915 PRs).

Headline: 4.8 is an editor-UX, rendering and physics-API release. It does **not** ship a suite of
headless/agent tools. The CLI gained four small options; everything else we rely on already existed.

## Tooling we should adopt

**CLI differences, complete list [ran: `--help` diff]:** new `-q` (alias of `--quiet`),
`--skip-breakpoints`, `--clear-shader-cache`, `--debug-mute-audio`; `--breakpoints` now documents
`source:line`; `--single-threaded-scene` is now editor-only; debug options are relabelled as
unavailable in release templates. Hidden (not in `--help`): `--run-upgrade-tool`.

- **Our pipeline works unchanged [ran].** `--import`, `tests/test_runner.tscn` (6 tests, 0 failures)
  and a 3-frame `--write-movie` capture of `main.tscn` under Xvfb/llvmpipe all pass on 4.8b5.
  PNG movie frames are written faster (GH-121437) [log].
- **Capture flags.** Add `--debug-mute-audio` and, after shader edits that look stale,
  `--clear-shader-cache` [ran, accepted alongside `--write-movie`]:
  `xvfb-run -a godot --path . --rendering-method forward_plus --audio-driver Dummy --debug-mute-audio --write-movie captures/x/f.png --fixed-fps 10 --quit-after 30 res://scenes/main.tscn`
- **Lint through the built-in language server [ran].** `--check-only` is unchanged: it reports parse
  errors only, never warnings, and fails on scripts that reference autoloads (`Identifier not found: Net`),
  on both versions. The LSP does give warnings headless:
  `godot --headless --path . --editor --lsp-port 6005`
  then send `initialize` + `textDocument/didOpen` over TCP and read `textDocument/publishDiagnostics`.
  New in 4.8: the warning name is in the diagnostic `code` field (GH-122756), e.g. `UNUSED_VARIABLE`,
  `STANDALONE_EXPRESSION`, and the new `ONREADY_WITH_CAST`
  (`debug/gdscript/warnings/onready_with_cast`). `renameProvider` is advertised (also in 4.7).
  A ~50-line Python client is enough; this is the one real tooling gain for agents.
- **DAP.** `--dap-port <port>` still exists; 4.8 only stops advertising unsupported features
  (GH-125024). Not tried beyond start-up.
- **Project upgrade tool [ran].** The editor can run it when a project is opened in a new version
  (GH-119466). Headless it fails (it restarts the editor without `--headless`); under Xvfb it works:
  `xvfb-run -a godot --path . --editor --run-upgrade-tool --quit --audio-driver Dummy`
  On our project it changed only `project.godot`: `config/features` 4.7 -> 4.8, replaced our header
  comment with the stock one, and dropped `common/physics_ticks_per_second=60` (a default value).
  Recommendation: do not run it on the repo; bump `config/features` by hand. Undocumented flag.
- **API reference for agents [ran].** `godot --headless --doctool <dir>` and `--dump-extension-api`
  work headless; diffing two dumps is the most reliable "what changed" source. Note the official
  binary's XML has no descriptions; use docs.godotengine.org/en/latest for prose.
- **Text scenes diff better.** Object values are written one property per line (GH-92102) and
  scenes with metadata or embedded scenes get a new text format version (GH-121920, GH-125351) [blog].

## Engine features to use

- **`Trail3D`** (inherits new abstract `LineBase3D`) [api, ran: instantiates headless]. Wakes,
  cannonball tracers, sail-tip streamers. Properties: `emitting`, `lifetime` (0.2), `limit_mode`
  (`LIMIT_MODE_LIFETIME` / `LIMIT_MODE_MAX_LENGTH`), `max_length`, `min_section_length`, `width`,
  `width_curve`, `color`, `color_gradient`, `mesh_alignment` (`MESH_ALIGNMENT_LOCAL` / `_BILLBOARD`),
  `tiling_mode`, `tiling_multiplier`, `pin_uv`, `material_mode` (`MATERIAL_MODE_MIX` / `_ADD` /
  `_CUSTOM`), `material` (ShaderMaterial; custom shaders need `skip_vertex_transform` and read
  tangent/width from `CUSTOM0`, per the class docs). Methods: `clear()`, `get_current_length()`.
  Beta 4 and 5 still fixed Trail3D bugs (GH-125394, GH-125732), so verify visually.
- **Buoyancy helper:** `RigidBody3D.get_velocity_at_position(global_point)` and
  `get_velocity_at_local_position()` [api, ran] for per-probe drag on hulls.
- **Non-allocating physics queries** [api, ran]: `PhysicsDirectSpaceState3D.intersect_ray_into(params, result)`,
  `cast_motion_into`, `intersect_shape_into`, `collide_shape_into`, `get_rest_info_into`,
  `intersect_point_into` with reusable `PhysicsIntersectRayResult3D` (`position`, `normal`,
  `collider`, `collider_id`, `collider_rid`, `collider_shape`, `collider_face_index`) etc.
  Return `bool`; use for cannonball and AI line-of-sight rays.
- **Jolt 5.6.0** (GH-121260); `Generic6DOFJoint3D` gains `set_angular_target_rotation(Quaternion)`,
  `linear_drive_*/force_limit`, `angular_drive_*/torque_limit` [api] (rudder, capstan, cannon carriages).
- **Lighting** [api]: screen-space contact shadows via
  `rendering/lights_and_shadows/contact_shadow/enabled` (+ `shadow_length`, `surface_thickness`) and
  `Light3D.shadow_contact_shadows_allow` / `shadow_contact_shadows_blur`; multi-bounce AO via
  `rendering/lights_and_shadows/multi_bounce_occlusion/enabled`. Both default off.
- **Shaders:** uniform hints `no_storage` and `no_editor` (GH-122931), `Shader.set_include_path()`,
  implicit `bool` constant conversion (GH-120715) [log/api].
- **Particles:** `ParticleProcessMaterial.particle_flag_preserve_color`;
  `BaseMaterial3D.particles_anim_enabled` now separate from billboard mode [api].
- **Textures:** mip streaming (`rendering/textures/streaming/enabled`, `TextureStreaming` singleton,
  `StreamedTexture2D`); `mipmaps/preserve_alpha_test_coverage` on import (rigging, foliage) [api].
- **GUI:** `Label` / `RichTextLabel` `resize_font_to_fit`, `minimum_font_size`, `maximum_font_size`
  (the blog calls these `auto_font_size`; the binary does not) [api]; theme sounds
  (`Theme.set_sound`, `Control.play_theme_sound`, bus `audio/buses/gui_theme_bus`); `SpinBox.format`;
  `gui/common/auto_focus_strategy`; `ui_toggle_fullscreen` action (Alt+Enter) is now built in.
- **Animation:** `AnimationNodeObserver*` resources emit signals such as `started` / `finished` for
  OneShot nodes; `Animation.INTERPOLATION_MAKIMA`; `AnimationPlayer.clear_cache_on_stop` [api].
- **Misc:** `FuzzySearch.search_all(query, targets)` [ran]; `Vector2.inverse()`;
  `ResourceLoader.get_resource_type()`; glTF import reads `CUSTOM3` (GH-120040).
- Nothing new for multiplayer, navigation or sky beyond bug fixes [log].

## Breaking changes to check

- **ENet:** `ENetMultiplayerPeer.create_server()` previously passed the channel count as incoming
  bandwidth; fixed in GH-124620. `src/net/net.gd:33` calls it with two arguments, so unaffected, but
  re-run `tools/test_net.sh`. mbedTLS moved to 4.1.x / PSA Crypto (GH-120725): matters only if we add DTLS.
- **GDScript:** strings are no longer treated as comments (GH-121833): `"""doc"""` statements still
  compile [ran] but now raise `STANDALONE_EXPRESSION`; use `##`. Scripts cannot inherit their own
  inner classes (GH-121171). `self.free()` is an error (GH-123316). `Array.map/filter/...` parameter
  renamed `method` -> `callable` (positional calls unaffected).
- **Particles:** flipbook animation needs `particles_anim_enabled = true` (GH-120786; default false);
  default particle angle curve range is now [-1, 1] (GH-123959).
- **Sky / look:** sky brightness multiplier applied in the correct colour space (GH-110911) and
  non-volumetric fog now appears in sky reflections (GH-107958). Re-capture reference frames and
  compare. The sky `SCREEN_UV` fix (GH-121676) is Compatibility-only.
- **Physics:** `Generic6DOFJoint3D.FLAG_ENABLE_MOTOR` renamed in favour of
  `FLAG_ENABLE_ANGULAR_MOTOR` (GH-96458); `NOTIFICATION_DEBUG_COLLISIONS_HINT_CHANGED` replaced by a
  signal; undocumented `enter_world` script callbacks removed (GH-111504).
- **API signatures:** `Image.compress(mode, source, profile)` (was `astc_format`),
  `Image.generate_mipmaps` gained arguments, `DisplayServer.get_display_safe_area(screen)`,
  `Skeleton3D.reset_bone_pose(s)` gained an argument, `SpinBox.prefix/suffix` deprecated,
  `MovieWriter._write_frame` audio pointer type changed (extensions only) [api].
- **Debug/export:** the local debugger and profiling now fail in release exports (GH-122213,
  GH-122317); new projects ignore joypads when unfocused (GH-120399); audio playback now starts
  paused when the player node cannot process (GH-114764).
- **Known issue (dev 7 post):** Steam Deck built-in controls do not work in Linux exports in Gaming Mode.
- No "Upgrading to 4.8" docs page exists yet (404 on 2026-11-24).

## Not found

- **No MCP server, AI/agent integration or "tool suite"** in the engine: nothing in `--help`, the
  class dump, the binary's strings, the eleven release posts or the 1,915-PR changelog. The only
  "AI" string in the binary is a sponsor credit. The owner may be thinking of third-party MCP
  add-ons listed in the Asset Library/Store (search-result level only; not evaluated, not recommended
  here), or of the editor-only additions: project upgrade tool, experimental symbol renaming,
  underlined diagnostics, Find-in-Files replace preview.
- **No GDScript formatter or standalone linter CLI.** A code-actions/quick-fix PR (GH-114168) was
  merged and reverted (GH-121337).
- **No built-in GDScript test framework.** `--test` exists only in builds compiled with `tests=yes`
  (engine C++ tests); the official binary refuses it [ran]. Keep `tests/test_runner.gd`.
- **No new screenshot, profiler or tracing CLI.** Tracy/Perfetto changes are compile-time only.
- The interactive changelog page itself is a JS app; its data file
  (`.../godot-interactive-changelog/data/godotengine.godot.4.8.json`) was read instead.
