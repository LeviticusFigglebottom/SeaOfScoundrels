# Architecture and interfaces

Read this before touching code. These contracts let workstreams land independently.

## Conventions
- Godot 4.7.2, GDScript, typed where practical. Forward+ renderer, Jolt physics, 60 Hz physics tick.
- Units are metres, seconds, kilograms. **-Z is forward**, +Y up, +X starboard (right).
- Sea level is world Y = 0 at rest.
- Layout: `src/<system>/` code, scenes and shaders; `scenes/` top-level and showcase scenes; `assets/generated/` generator outputs (committed); `tools/` generators and scripts; `tests/` headless tests.
- Scenes are written as text `.tscn` or built in code. Nobody uses the editor GUI, so keep scenes small and build structure in `_ready()` where simpler.
- Do not edit `project.godot` unless you must. Input actions go in `src/core/input_setup.gd`. New autoloads need the lead's sign-off (say so in your report).
- No third-party content: no downloaded models, textures, audio, fonts, shaders or code snippets. Write everything.
- Host authority: code that changes world state runs only where `Net.is_host()`. Player intent reaches the host through methods that can later be RPCs (keep them small, with plain arguments).

## Verification
- `tools/test.sh [test_name]` runs headless tests (`tests/test_*.gd`, extend `TestCase`).
- `tools/capture.sh res://scene.tscn name [seconds] [fps] [-- args]` renders PNG frames (1600x900) and an mp4 into `captures/` (git-ignored) with software Vulkan. It is slow (0.2 to 2 s per frame): use 5 to 10 fps and short clips. Look at the frames with the Read tool and judge them against DESIGN.md.
- Showcase scenes live in `scenes/showcase/<system>_showcase.tscn`, are self-contained, and script their own camera so captures are repeatable.
- The machine has 4 cores and other agents are rendering too. Do not run more than one capture at a time.

## Autoloads
| Name | File | Owns |
|---|---|---|
| `InputSetup` | `src/core/input_setup.gd` | input actions |
| `Net` | `src/net/net.gd` | session, `is_host()` |
| `Weather` | `src/sky/weather.gd` | `time_of_day`, `wind_vector()`, `wind_speed`, `storminess`, `sun_direction()` |
| `Sea` | `src/ocean/sea.gd` | wave function: `height(x,z)`, `height_at(p)`, `depth(p)`, `normal(x,z)`, `displacement(x,z)`, `rest_point(x,z)`, `time`, `amp_scale`, `sea_state()`, `significant_height()`, `wave_amplitude(i)`, `bind_material(mat)` |
| `Game` | `src/core/game.gd` | session state, `post_notice()` |

`Sea` is the only source of water height. Shaders that need waves include `res://src/ocean/waves.gdshaderinc` and register their material with `Sea.bind_material()`.

## Ocean (`src/ocean/`)
`ocean.tscn` (`class_name Ocean`) is dropped into any scene and follows the active camera; it needs the `Sea`, `Weather` and `Net` autoloads and reads the sky globals (`sun_dir`, `sun_color`, `sky_horizon_color`, `sky_zenith_color`, `ambient_color`; at night the sky rig puts the moon in `sun_dir`/`sun_color`, which is what lights the water).

- **Wave model.** `Sea.WAVE_TABLE` rows are `[wavelength, calm amplitude, storm amplitude, heading, steepness]` (16 waves, `MAX_WAVES` 32). `amp_scale` runs `AMP_CALM..AMP_STORM` and blends each wave between its two amplitudes, so a storm adds a steep cross sea instead of scaling the calm one; values outside the range scale the nearest column (0 = flat). `Sea.height()` costs about 12 microseconds. Waves under about 7 m exist only as normal detail in the shader.
- **Surface.** One mesh, one draw call: concentric square rings with doubling cell size, stitched rims, a skirt to the horizon, moved in 8 m steps (a multiple of every ring cell that still carries waves). `ocean.gdshader` is unshaded and composites everything itself: it reads the screen and depth textures (so it draws in the transparent pass, writes depth, and does **not** receive shadows or engine lights). Vertices beyond the far plane are depth-clamped.
- **Public API.** `Ocean.current` (static) or group `ocean`; `quality` (`Ocean.Quality.LOW/MEDIUM/HIGH`); `add_foam(world_pos, radius, strength)` to whiten the water (wakes, splashes, impacts: call every frame for a trail; it rides the waves and fades in about 7 to 11 s; works within about 100 m of the camera, not at LOW); `rain_intensity` (negative follows `Weather.rain_intensity()` when present); `camera_depth`, `camera_submerged`, signal `camera_submerged_changed(bool)`; `material` for tuning colours.
- **Foam field.** `foam_field.gd`: a 512 px float texture covering a wrapping 256 m tile in rest-plane coordinates (`Sea.rest_point`), never cleared: decay, crest injection from the wave Jacobian, stamps from `add_foam`.
- **Underwater.** `underwater.gd` draws a full-screen pass before the surface while the camera is within 0.6 m of the water or below it (fog, absorption, caustics, sun shafts, per-pixel waterline from `sea_height`). The surface shader draws its own underside (Snell's window). Other transparent materials are not fogged by it.
- **Tests.** `tools/test.sh` covers the CPU maths and the mesh; `tools/test_gpu.sh` renders `waves.gdshaderinc` and compares it with `Sea` (needs a renderer; software Vulkan under Xvfb works).
- **Showcase.** `tools/capture.sh res://scenes/showcase/ocean_showcase.tscn <name> 3 5 -- shot=calm|storm|sunset|night|shore|underwater|waterline|wake|swell|aerial [quality=low|medium|high] [amp=] [t=] [rain=] [scale=] [wire=1]`.

## Ship (`src/ship/`)
`Ship extends RigidBody3D` (`class_name Ship`). Origin at the waterline, midship, on the centreline.

Control state (host-owned, replicated later):
- `helm: float` in -1..1, the wheel position (positive turns to starboard). Set through `set_helm_target(v)`; the wheel has inertia.
- `sail_set: float` in 0..1 (0 furled, 1 full). `set_sail_target(v)`.
- `sail_trim: float` radians, yard angle relative to the hull, about -1.2..1.2. `set_trim_target(v)`.
- `anchor_down: bool`. `set_anchor(down)`.
Read-only: `speed_knots()`, `forward_speed()`, `water_level` (0..1 hold flooding), `holes: Array`, `is_sinking`, `apparent_wind()`.
Damage: `apply_hull_damage(world_pos: Vector3, radius: float)` creates a hole; `patch_hole(index)`; `bail(amount)`.

### Sloop dimensions (shared by physics and art)
- Length on deck 13 m (bow at z = -6.5, stern at z = +6.5), beam 4.4 m, draught 1.2 m, main deck at y = +1.1, quarterdeck (aft of z = +3) at y = +2.0, hold floor at y = -0.6.
- One mast at z = -1.0, 14 m tall above deck, one square mainsail (yard 6.5 m wide at y = +9), bowsprit.
- Mass about 9000 kg.
- Station markers (Node3D or glTF empties, names exact): `Station_Helm` (0, 2.0, 5.2), `Station_SailLength` (-1.9, 1.1, 0.5), `Station_SailAngle` (1.9, 1.1, 0.5), `Station_Anchor` (0, 1.1, -4.6), `Station_CannonPort` (-2.0, 1.1, -1.5) facing -X, `Station_CannonStarboard` (2.0, 1.1, -1.5) facing +X, `Station_MapTable` (0, -0.6, 2.5), `Station_Ladder_Port` (-2.3, 0, 2.0), `Station_Ladder_Starboard` (2.3, 0, 2.0).
- Model file: `assets/generated/ship/sloop.glb`. Meshes named `col_*` are collision-only convex pieces (hidden at runtime). The sail, yard, wheel, rudder, capstan and anchor are separate objects named `Sail`, `Yard`, `Wheel`, `Rudder`, `Capstan`, `Anchor` with origins at their pivots.

## Stations (`src/ship/station.gd`)
`Station extends Node3D` (`class_name Station`): `kind: StringName` (`&"helm"`, `&"sail_length"`, `&"sail_angle"`, `&"anchor"`, `&"cannon"`, `&"map_table"`, `&"bilge"`, ...), `occupant: Node`, `can_occupy(pawn)`, `occupy(pawn)`, `release()`, and `drive(axis: Vector2, primary: bool, secondary: bool, delta: float)`, which the occupant's controller calls every physics tick. The player controller and the AI call the same `drive()`. Stations expose `stand_point: Transform3D` (where the occupant stands) and `prompt: String`.

## Characters (`src/characters/`)
`Pawn extends CharacterBody3D` (`class_name Pawn`): a body with no brain. A controller child sets intent each tick:
- `wish_dir: Vector3` (world-space horizontal move direction, length 0..1), `wish_sprint`, `wish_jump`, `look_yaw`, `look_pitch`.
- `interact()` uses the focused `Interactable`; `station: Station` when crewing one; `carried: Node3D` when hauling.
- `health`, `apply_damage(amount, from)`, `died` signal.
Pawns ride moving ships: while standing on a `Ship`, motion is solved in the ship's local frame so a rolling deck never throws or jitters the pawn.
Controllers: `PlayerController` (local input, first-person camera), `CrewBrain` (AI crew), `EnemyBrain`.

`Interactable extends Area3D` (`class_name Interactable`, `src/core/interactable.gd`): `prompt: String`, `signal interacted(pawn)`, `can_interact(pawn) -> bool`.

## Collision layers
1 world static (terrain, docks) · 2 ships (hull and deck) · 3 pawns · 4 interactables (areas) · 5 projectiles · 6 carryables and debris · 7 water volumes and triggers.

## Sky (`src/sky/`)
`sky_rig.tscn` is dropped into any scene: owns `WorldEnvironment`, sun and moon `DirectionalLight3D`, sky shader, clouds, stars, fog and precipitation, all driven by `Weather`. It sets these global shader uniforms for other shaders (declared in `project.godot` by the lead): `sun_dir: vec3`, `sun_color: vec3`, `sky_horizon_color: vec3`, `sky_zenith_color: vec3`, `ambient_color: vec3`.
