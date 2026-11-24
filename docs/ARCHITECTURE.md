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
`sky_rig.tscn` is dropped into any scene: owns `WorldEnvironment`, sun and moon `DirectionalLight3D`, sky shader, clouds, stars, fog and precipitation, all driven by `Weather`. It holds no state, so it is safe on every peer. Do not add another `WorldEnvironment` or directional light to a scene that has the rig. It sets these global shader uniforms every frame (declared in `project.godot` by the lead), all in **linear RGB**:
- `sun_dir: vec3` unit vector towards the dominant light (sun by day, moon by night), never lower than about 6 degrees above the horizon, identical to the shadow-casting `DirectionalLight3D`.
- `sun_color: vec3` that light's colour times energy (includes lightning flashes).
- `sky_horizon_color: vec3` horizon colour; the fog colour is the same value, so fade distant things to it.
- `sky_zenith_color: vec3`, `ambient_color: vec3` (ambient colour times energy).

Rig members other systems may read: `sun`, `moon`, `environment`, `palette` (this frame's colours). Colours come from `sky_palette.gd`, a pure function of sun height, cloud cover and storminess; tune the look there.

`Weather` (host-authoritative; setters are no-ops on clients):
- State: `time_of_day`, `day`, `day_length_seconds`, `wind_heading`, `wind_speed` (mean), `storminess`, `cloudiness`, `cloud_offset`, `clock`. `get_state()` / `apply_state(dict)` are the replication hooks.
- Change it: `set_weather(storminess, wind_speed, wind_heading, seconds = 0, cloudiness = -1)` eases to the target; `set_preset(&"clear" | &"fair" | &"breezy" | &"overcast" | &"squall" | &"storm", seconds)`; `is_transitioning()`, `target_storminess()`.
- Wind: `wind_vector()` **includes gusts** (speed and a small veer); `mean_wind_vector()` is the steady wind; `gust_factor()`, `gustiness()`.
- Sky: `sun_direction()`, `moon_direction()`, `dominant_light_direction()`, `sun_height()`, `daylight()` (0..1), `is_night()`, `moon_phase()`, `cloud_cover()`, `rain_intensity()`.
- Lightning: starts above storminess 0.55. `signal lightning_struck(direction: Vector3, distance: float, intensity: float)` (direction is horizontal, from the listener; delay thunder by distance / 340). `lightning_flash` is the 0..1 flash brightness; `strike_lightning(direction, distance, intensity)` forces one; `lightning_enabled` turns automatic strikes off.

Showcase: `tools/capture.sh res://scenes/showcase/sky_showcase.tscn <name> 2 5 -- time=18.1 storm=0 cloud=0.4`; see the header of `scenes/showcase/sky_showcase.gd` for all arguments (`timelapse=1`, `to_storm=1`, `strike=`, `look=`).
