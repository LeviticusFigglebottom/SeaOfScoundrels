# Architecture and interfaces

Read this before touching code. These contracts let workstreams land independently.

## Conventions
- Godot 4.8 beta 5, GDScript, typed where practical. Forward+ renderer, Jolt physics, 60 Hz physics tick.
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
- `tools/lint.py [paths]` lints GDScript through the engine's language server (errors and warnings with codes). Run it before committing.
- Engine notes for 4.8 (new APIs worth using, breaking changes): `docs/GODOT_4_8_NOTES.md`.
- Showcase scenes live in `scenes/showcase/<system>_showcase.tscn`, are self-contained, and script their own camera so captures are repeatable.
- The machine has 4 cores and other agents are rendering too. Do not run more than one capture at a time.

## Autoloads
| Name | File | Owns |
|---|---|---|
| `InputSetup` | `src/core/input_setup.gd` | input actions |
| `Net` | `src/net/net.gd` | session, `is_host()` |
| `Weather` | `src/sky/weather.gd` | `time_of_day`, `wind_vector()`, `wind_speed`, `storminess`, `sun_direction()`, `set_weather()`, `lightning_struck` (see Sky) |
| `Sea` | `src/ocean/sea.gd` | wave function: `height(x,z)`, `height_at(p)`, `depth(p)`, `normal(x,z)`, `displacement(x,z)`, `time`, `amp_scale`, `bind_material(mat)` |
| `Game` | `src/core/game.gd` | session state, `post_notice()` |

`Sea` is the only source of water height. Shaders that need waves include `res://src/ocean/waves.gdshaderinc` and register their material with `Sea.bind_material()`.

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
`sky_rig.tscn` is dropped into any scene: owns `WorldEnvironment`, sun and moon `DirectionalLight3D`, the sky shader with volumetric clouds, cloud shadows, fog, rain, mist, the storm cell's rain curtain and lightning, all driven by `Weather`. It holds no replicated state, so it is safe on every peer. Do not add another `WorldEnvironment` or directional light to a scene that has the rig. It sets these global shader uniforms every frame (declared in `project.godot` `[shader_globals]`), colours in **linear RGB**:
- `sun_dir: vec3` unit vector towards the dominant light (sun by day, moon by night), never lower than about 6 degrees above the horizon, identical to the shadow-casting `DirectionalLight3D`.
- `sun_color: vec3` that light's colour times energy (includes lightning flashes and the cloud shadow at the camera).
- `sky_horizon_color: vec3` horizon colour; the fog colour is the same value, so fade distant things to it.
- `sky_zenith_color: vec3`, `ambient_color: vec3` (ambient colour times energy).
- `cloud_shadow_tex: sampler2D`, `cloud_shadow_params: vec4` the clouds' shadow on the ground; use them only through `cloud_shadow.gdshaderinc` (below).

Rig members other systems may read: `sun`, `moon`, `environment`, `palette` (this frame's colours), `camera_sheltered`, `light_at_camera`, `cloud_light_at(world_pos)`, `cloud_field` (`column(xz)`: cloud base, height, storminess over a point). Exports: `cloud_quality` (`LOW` / `MEDIUM` default / `HIGH`), `track_camera_focus`, `splashes_follow_sea`, `rain_particles`, `show_bolts`, `shadow_distance`. Colours come from `sky_palette.gd`, a pure function of sun height, morning or evening, cloud cover and storminess; tune the look there.

### Clouds
One function of world position, `cloud_field.gdshaderinc` (CPU copy: `cloud_field.gd`): a tiled weather map (`cloud_map.png`) gives cloud footprints; over a footprint the cloud is a flat-based dome; a 64^3 puff volume (`cloud_volume.png`) is subtracted so tops and sides are cauliflower lumps. It returns a rough signed distance, so the sky shader strides through empty air, lands on surfaces (bisecting after a forced long stride) and goes opaque within a few steps. Light is a short march towards the sun banded into three tones. The camera's world position feeds the march, so clouds have true parallax; a small-planet curve sinks them behind the horizon by 27 km. Storm cells add a tower and anvil in true metres. Textures come from `tools/textures/gen_cloud_volume.py`.

Quality and cost (texture reads; a march step is 2 reads in clear air, 3 in or near cloud):

| `cloud_quality` | Where the march runs | Steps / light samples | Worst case per marched pixel | Expected at 1080p, GTX 1660 class |
|---|---|---|---|---|
| `LOW` | quarter-res sky pass (130k px) | 16 / 2, no light shafts | about 75 reads | about 0.3 ms |
| `MEDIUM` | half-res sky pass (518k px) | 32 / 3, 6 shaft samples | about 135 reads | 1 to 2 ms (most rays end in under 12 steps; pixels below the horizon exit at once) |
| `HIGH` | full resolution (2.07M px) | 56 / 5, 12 shaft samples, second noise octave | about 280 reads | 6 to 10 ms: for strong GPUs |

Also every frame: the full-res pass (gradient, 3 cirrus reads, at night 3 more for Milky Way and moon), the 512 px shadow bake (4 reads per texel) and the radiance cubemap (10-step march). These are reasoned, not measured: there is no GPU here (D9). Needs a real-hardware check.

### Cloud shadows: how terrain, ocean and ship shaders use them
The rig bakes the clouds' ground shadow for a 16 km square around the camera into `cloud_shadow_tex` every frame, and multiplies the sun (the light node and `sun_color`) by the shadow **at the camera**, so standard materials near the player darken when a cloud passes over. Custom shaders with a large footprint (ocean, islands) should shadow per pixel:
```glsl
#include "res://src/sky/cloud_shadow.gdshaderinc"
// in light():   float sun = LIGHT_IS_DIRECTIONAL ? cloud_light(world_pos.xz) : 1.0;  then multiply the light by `sun`
// with sun_color: vec3 key = sun_color * cloud_light(world_pos.xz);
```
`cloud_light(xz)` is relative to the dimming already in the light (do not use it twice); `cloud_shadow(xz)` is the absolute sunlit fraction (1 open sun, about 0.2 under thick cloud) for things that bypass the light. Example: `scenes/showcase/sky_showcase_ground.gdshader`. Standard materials cannot be shadowed per pixel (Godot has no directional-light projector), so ships get the camera value, which is right at ship scale.

### Shelter from rain
Put an `Area3D` in group `shelter` with a `BoxShape3D` child around any covered space (the hold, a cabin, a hut). Rain, splashes and mist are not drawn inside the four boxes nearest the camera (the boxes may move with a ship), and `rig.camera_sheltered` says whether the listener is under cover.

### `Weather` (host-authoritative; setters are no-ops on clients)
- State: `time_of_day`, `day`, `day_length_seconds`, `wind_heading`, `wind_speed` (mean, outside any cell), `base_storminess`, `cloudiness`, `cloud_offset`, `cloud_evolution`, `clock`, the storm cell (`storm_center`, `storm_radius`, `storm_intensity`, `storm_velocity`, `storm_wind_speed`), the front of a transition and the latest bolt. `get_state()` / `apply_state(dict)` replicate all of it (a snapshot with a new `lightning_serial` starts the flash on clients).
- `storminess` is the weather **at `focus_position`** (this peer's camera; the rig sets it): `max(base_storminess, storm cell there)`. Assigning it sets the background. Anything with a position of its own should ask `local_storminess(world_pos)`; also `local_rain_intensity(pos)`, `wind_speed_at(pos)`, `storm_cell_strength(pos)`. Suggested: `Sea` should take its amplitude from the host's `local_storminess(ship position)`.
- Change it: `set_weather(storminess, wind_speed, wind_heading, seconds = 0, cloudiness = -1)` eases the background to the target; `set_preset(&"clear" | &"fair" | &"breezy" | &"overcast" | &"squall" | &"storm", seconds)`; `is_transitioning()`, `target_storminess()`. `set_storm_cell(center, radius, intensity = 1, seconds = 0, velocity = ZERO)` and `clear_storm_cell(seconds)` place and remove a local storm.
- Fronts: during a timed `set_weather`, the values at the focus ease smoothly, while the sky shows the new weather arriving from upwind as a band (`front_weight(pos)`, 0 ahead of it, 1 behind).
- Wind: `wind_vector()` **includes gusts** (speed and a small veer) and the cell's wind when the focus is inside it; `mean_wind_vector()` is the steady wind; `gust_factor()`, `gustiness()`. Clouds drift and churn with the gusty wind.
- Sky: `sun_direction()`, `moon_direction()` (own path: trails the sun by `moon_elongation()`, always gibbous), `moon_illumination()` (lit fraction from the real geometry; the disc is lit from the sun's direction), `moon_phase()`, `dominant_light_direction()`, `sun_height()`, `daylight()`, `is_night()`, `cloud_cover()`, `rain_intensity()`.
- Lightning: automatic above storminess 0.55, inside the storm cell when there is one (so a distant cell flickers), about a third of it sheet lightning. `signal lightning_struck(direction, distance, intensity)` fires at the flash (direction horizontal from the focus); `signal thunder_heard(direction, distance, intensity)` fires `thunder_delay(distance)` = distance / 343 s later: play thunder on that. `lightning_flash` is the 0..1 flash envelope, `lightning_illumination(pos)` the flash with distance falloff, `lightning_position`, `lightning_is_sheet`; `strike_lightning(direction, distance, intensity)` and `strike_lightning_at(world_pos, intensity, sheet)` force one; `lightning_enabled` turns automatic strikes off.

Showcase: `tools/capture.sh res://scenes/showcase/sky_showcase.tscn <name> 2 5 -- time=18.1 storm=0 cloud=0.4`; see the header of `scenes/showcase/sky_showcase.gd` for all arguments (`timelapse=1`, `from= to=`, `to_storm=1`, `front=`, `cell=x,z,radius,intensity`, `cam=`, `truck=`, `quality=`, `shelter=1`, `strike=`, `look=`). `tools/contact_sheet.py out.png captures/a captures/b:all` tiles frames for comparison.
