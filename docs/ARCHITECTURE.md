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
| `Sea` | `src/ocean/sea.gd` | wave function: `height(x,z)`, `height_at(p)`, `depth(p)`, `normal(x,z)`, `displacement(x,z)`, `rest_point(x,z)`, `time`, `amp_scale`, `sea_state()`, `significant_height()`, `wave_amplitude(i)`, `bind_material(mat)` |
| `Game` | `src/core/game.gd` | session state, `post_notice()`, `profile` |
| `Audio` | `src/audio/audio_manager.gd` | buses, `play_sfx(name, pos)`, `play_music`, `play_stinger`, shanty stems, ambience mixer setters (`set_sea_state`, `set_wind`, `set_rain`, `set_underwater`, `set_below_deck`, `set_shore`, `set_ship_speed`); catalogue in `assets/generated/audio/manifest.json` |

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
- Length on deck 13 m (bow at z = -6.5, stern at z = +6.5), beam 4.4 m, draught 1.2 m, main deck at y = +1.1, quarterdeck (aft of z = +3) at y = +2.0, hold floor at y = -0.85 (1.85 m headroom).
- One mast at z = -1.0, 14 m tall above deck, one square mainsail (yard 6.5 m wide at y = +9), bowsprit.
- Mass about 9000 kg.
- Station markers (Node3D or glTF empties, names exact): `Station_Helm` (0, 2.0, 5.2), `Station_SailLength` (-1.9, 1.1, 0.5), `Station_SailAngle` (1.9, 1.1, 0.5), `Station_Anchor` (0, 1.1, -4.6), `Station_CannonPort` (-2.0, 1.1, -1.5) facing -X, `Station_CannonStarboard` (2.0, 1.1, -1.5) facing +X, `Station_MapTable` (0, -0.85, 2.5), `Station_Bilge` (0, -0.85, -2.1), `Station_Ladder_Port` (-2.3, 0, 2.0), `Station_Ladder_Starboard` (2.3, 0, 2.0).
- Code must read station positions, pivots and collision from the model's markers and `col_*` meshes, never from these numbers. Full node, material, damage (`HullPanel_NN`/`Hole_NN`/`HolePatch_NN`) and rope conventions: `docs/SHIP_ART.md`.
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

As built (see `src/characters/pawn.gd` header for the full list): signals `died()`, `damaged(amount, from)`, `landed`, `jumped`, `mode_changed`, `station_changed`, `carried_changed`; methods `board(ship_body, local_feet)`, `teleport`, `enter_station`, `leave_station`, `drive_station`, `pick_up`, `drop_carried`, `heal`, `revive`, `get_world_velocity`. `Ladder` (`src/characters/ladder.gd`) is a climb area: local +Y up, +Z out of the hull. `Carryable` (`src/core/carryable.gd`) is the haulable base; containers implement `accept_carryable(item) -> bool`.

Integration rules for anything a pawn rides:
- The body is in group `ship`, on layer 2, and its `collision_mask` must NOT include layer 3 (pawns), or a pawn can shove the hull.
- Stations have an `Interactable` child (or one whose `target` is the station). `stand_point` is local to the station node.
- Spawn with `pawn.board(ship, local_pos)`; AI brains set intent fields with `process_physics_priority < 0`.
- The sloop's hold has 1.85 m of headroom; the pawn's auto-crouch remains as a fallback for low spaces.

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
- Lightning: automatic above storminess 0.55, inside the storm cell when there is one (so a distant cell flickers), about a third of it sheet lightning. `signal lightning_struck(direction, distance, intensity)` fires at the flash (direction horizontal from the focus); `signal thunder_heard(direction, distance, intensity)` fires `thunder_delay(distance)` = distance / 343 s later: play thunder on that. `lightning_flash` is the 0..1 flash envelope, `lightning_illumination(pos)` the flash with distance falloff, `lightning_position`, `lightning_is_sheet`; `strike_lightning(direction, distance, intensity)` and `strike_lightning_at(world_pos, intensity, sheet)` force one; `lightning_enabled` turns automatic strikes off. Non-sheet bolts trigger `SkyRig`'s 1-draw-call Gerstner-conformal `LightningImpact` ocean surge (`src/sky/lightning_impact.gdshader`: expanding electric shockwave ring, fluted ionized spray crown, inner plasma plumes) and stamp a live boiling `Ocean.add_foam()` impact scar.

Showcase: `tools/capture.sh res://scenes/showcase/sky_showcase.tscn <name> 2 5 -- time=18.1 storm=0 cloud=0.4`; see the header of `scenes/showcase/sky_showcase.gd` for all arguments (`timelapse=1`, `from= to=`, `to_storm=1`, `front=`, `cell=x,z,radius,intensity`, `cam=`, `truck=`, `quality=`, `shelter=1`, `strike=`, `look=`). `tools/contact_sheet.py out.png captures/a captures/b:all` tiles frames for comparison.

## Brigantine & Ship Systems (`src/ship/`)
Second playable ship class sharing `Ship` (`src/ship/ship.gd`, `ship_class = &"brigantine"`):
- Model: `assets/generated/ship/brigantine.glb` (+ `brigantine_lod.glb`), generated by `tools/blender/gen_brigantine.py`. Length on deck 17.4 m, beam 5.4 m, main deck y = +1.25, quarterdeck y = +2.25, hold floor y = -0.95 (2.10 m headroom), two masts (`Sail`/`Yard`/`Flag` + `Sail_Fore`/`Yard_Fore`/`Flag_Fore`), 4 broadside cannons (`port`, `starboard`, `port_aft`, `starboard_aft`), 10 breach slots, flared `y = +0.50 m` `mask_water`. Both `gen_sloop.py` and `gen_brigantine.py` merge 21 static un-animated hull/deck/rail/rigging/prop sub-meshes into `Hull` by material while retaining exact `Node3D` anchors (real-GPU measured **-50.5% DC Sloop / -44.4% DC Brigantine**).
- `Ship.apply_livery(sail_tint, flag_tint, glow_accent = Color.BLACK, hull_tint = Color.WHITE)` tints per-ship sails, flags, hull timber/paint, figurehead, and lantern glow via surface overrides without mutating shared `.glb` materials. `faction == &"ghost"` applies the translucent Fresnel ectoplasm shader (`src/ship/ghost_hull.gdshader`) with `set_spectral_phase(alpha, flare)` dissolve; `sail_wind.gdshader` renders procedural faction emblems & tatters (`emblem_mode` 1 = Corsair crimson war-band & skull medallion, 2 = Drowned tattered hem & verdigris rune, 3 = Ghost spectral tattered sails).
- `Cannonball` (`src/ship/cannonball.gd`) & `Ship` tactile VFX: host-authoritative swept raycasts (`intersect_ray_into`) on layer 5 with Godot 4.8 `Trail3D` tracer ribbon, feathered billboard gunpowder smoke puffs + additive golden muzzle flashes, tall feathered foam water-geyser plumes (`Ocean.add_foam()`), blazing ember + oak splinter hull-impact bursts, breach-patch sawdust & hammer-spark bursts (`patch_hole`), bilge-bail splash puffs & overboard foam (`bail`), and hysteresis-gated `wind_caught` peak-trim cue.

## Character art and animation (`src/characters/`)
- `assets/generated/characters/{pirate,drowned,tidecaller}.glb` from `tools/blender/gen_characters.py` (shared 19-bone humanoid rig; 11 distinct archetypes: `captain`, `helmsman`, `lookout`, `carpenter`, `drowned_shambler`, `drowned_shield`, `drowned_powder`, `drowned_captain`, `tidecaller`, `corsair_raider`, `rival_captain`).
- `CharacterVisual` (`src/characters/character_visual.gd`): switches archetypes, per-character waistcoat/accent tints, held-tool/carried-chest sockets (`RightHand`, `LeftHand`), and `set_first_person_hidden(bool)` for the local player.
- `AnimationDriver` (`src/characters/animation_driver.gd`): procedural locomotion (walk, sprint, swim, ladder, air, station poses for helm/sail/capstan/cannon/map) layered with combat/tool actions (`slash_1..3`, `heavy`, `block`, `parry`, `stagger`, `aim_pistol`, `fire_pistol`, `dig`, `bail`, `patch`, `drink`, `play_shanty`, `shout`) and analytical two-bone grounded leg flexion so crouched stances keep boots planted at `y = 0`.
- Showcase: `scenes/showcase/charart_showcase.tscn`.

## AI crew (`src/crew/`)
- `CrewBrain` (`src/crew/crew_brain.gd`, `process_physics_priority = -10`): utility-scored brain controlling a `Pawn` aboard a `Ship` using the exact same `Station.drive()` API as players. Priority hierarchy: survival (bail/patch) > captain command-wheel orders > active station tasks (helm, sail trim/set, cannons) > lookout callouts (hostile vessels prioritized ahead of forward/abeam landmarks) & downtime banter/shanties. During `&"follow"` ashore or against deck boarders, crewmates resolve their `CombatComponent`, scan hostile combatants & beasts within `15 m`, bark persona battle-cries, fight with 3-hit cutlass chains, guard-breaking heavy strikes, and reactive parry/blocks, then seamlessly resume escorting the captain. During shanty sessions, crewmates visibly equip their persona's 3D instrument (`hurdy_gurdy`, `whistle`, `instrument` concertina) on `hand_right`, animate rhythmically with monotonic `Audio.shanty_beat()` tracking, and emit subtle golden musical motes. Supports 3 personas (`&"helmsman"` Barnaby, `&"lookout"` Maren, `&"carpenter"` Pip) and `yield_to_human_player()` when co-op peers join.
- `CrewDialogue` (`src/crew/crew_dialogue.gd`): persona-voiced callouts, banter, and relative ship-bearing formatting.
- Showcase: `scenes/showcase/crew_showcase.tscn`.

## Combat, beasts and bosses (`src/combat/`, `src/world/seabirds.gd`)
- `CombatComponent` (`src/combat/combat_component.gd`): host-authoritative melee & ranged combat attached to any `Pawn` (`cutlass`, `boarding_axe`, `pistol`, `blunderbuss`); 3-hit light chains, heavy lunge, block, timed parry with stagger window, dodge-step, stamina regen, weapon `Trail3D` swing arcs, additive golden parry/heavy sparks, camera recoil impulse, and duck-typed hit resolution across combatants, beasts, fort batteries, and Leviathan tentacles.
- `EnemyBrain` (`src/combat/enemy_brain.gd`): distinct faction/variant AI across 3 factions — Drowned (`drowned_shambler`, `drowned_shield`, `drowned_powder` with 3-layer fiery Powder-Keg explosion + camera trauma, `drowned_captain` with expanding verdigris rally shockwave), Tidecallers (`tidecaller` ranged repositioning + swirling bioluminescent coral-rune vortex shader & erupting water-geyser spout), and Corsairs (`corsair_raider`, `rival_captain` dodge-steps, blunderbuss/pistol + boarding axe + crimson-gold rally shockwave).
- `AIShipBrain` (`src/combat/ai_ship_brain.gd`): drives hostile `Ship` hulls (`&"drowned"`, `&"ghost"` with full spectral dissolve phase-shift teleports to the player's opposite beam & `phase_shifted` signal, `&"corsair"` agile flanking) using the same `Ship` controls as players.
- Beasts: `Shark` (`shark.gd`: 1,522-tri sculpted flat-faceted countershaded shark with 5 gill slits per flank, hinged 9-tooth snapping jaw, 2-segment traveling S-wave heterocercal tail, static mesh caching, circling dorsal-fin wake & Pawn-layer hitbox), `IslandCrab` (`island_crab.gd`: coral-armored beach/dig-site guardian with 0.55 s pincer telegraph & cookable crab-claw drop), `ReefEel` (`reef_eel.gd`: 7-segment undulating coastal swimmer ambusher), and `SeabirdFlock` (`src/world/seabirds.gd`: circling articulated gulls marking harbours, treasure islands, flotsam, castaways, and salvage wrecks).
- `Leviathan` (`src/combat/leviathan.gd`): flagship open-sea boss with 4 sculpted 7-segment bioluminescent sucker-lined tentacles, rising `AbyssalCrown` with glowing amber-aqua eyes, wave-conformal `InkPool` shader with hull cutout, boiling `Ocean.add_foam()` vortex ring, feathered spray eruptions, `is_defeated()` / `get_health_ratio()` HUD hooks, and Sunken Archive salvage reward.

## Islands, sea forts, sea caves, volcano & coral reefs (`src/world/`)
- `Archipelago` (`src/world/archipelago.gd`): 11 deterministic islands spanning ~2 km around Port Scoundrel (`port_scoundrel` home Outpost + 2 outlying Outposts + `cutlass_cay` starter treasure island + `ironwatch_fort` sea fort, `smugglers_cove` sea cave, `cinder_crag` volcano, `crescent_atoll` coral lagoon, `wreckers_shoal` shipwreck reef, arches, and spires). Exposes `get_map_data()`, `nearest_island()`, `get_outposts()`, `get_island_by_id()`.
- `Island` & `IslandGenerator` (`src/world/island.gd`, `island_generator.gd`): seeded heightfield/mesh sculpting with `island_shader.gdshader` + `foliage_wind.gdshader` (including `cloud_shadow.gdshaderinc`), distance-gated flicker lights & wind uniforms, monotonic landing beaches, slope-filtered palms/ferns/boulders, 17 procedural Blender props (`tools/blender/gen_props.py`), warm flat-faceted `FortBastion` octagonal coral-limestone battlements, watchtower gantry & blazing Signal Brazier on `&"fort_rock"`, walkable rain-sheltered `SmugglersGrotto` sea cave (`group &"shelter"`, stalactites, hanging lanterns, contraband stash) on `&"smuggler_cove"`, glowing cracked-obsidian `VolcanoCaldera` magma pool & towering rising ash/ember plume on `&"volcano_crag"`, washed-up glinting emerald sea-glass `MessageBottle` beach discoveries (`src/world/message_bottle.gd`, spawning emergent bonus treasure `DigSite`s), and interactive `CampfireCookingStove` forged-iron tripod skillets over island & outpost campfires.
- `CoralReef` (`src/world/coral_reef.gd`) & `coral_kelp.gdshader`: batched underwater reef gardens strictly bounded to **3 `MultiMeshInstance3D` draw calls** per island (`StaghornCorals`, `BrainTableCorals`, `KelpFronds`, shadow-off, distance-culled `> 155 m`) with seabed slope alignment, mooring keepout clearance, and current-driven underwater kelp sway.
- `FortBattery` (`src/world/fort_battery.gd`) & `FortVault` (`src/world/fort_vault.gd`): 4 sculpted cast-iron coastal sea-battery cannons on beveled oak wheeled carriages mounted in Ironwatch Fort's embrasures (1.35 s priming-fuse telegraph, destructible & manually fireable), paired with a 5,388-tri sculpted wrought-iron barred `FortVault` treasury gate keyed flush into `FortBastion`'s stone gateway that blocks the Sovereign Hoard until Fort defenses are silenced and then swings smoothly open (`±108°`) with warm interior treasury glow.
- `Outpost` (`src/world/outpost.gd`, `bunting_wind.gdshader`), `MerchantStall` (`merchant_stall.gd`), `DigSite` (`dig_site.gd`), `CastawayRaft` (`castaway_raft.gd`): pier mooring transform, 1-DC wind-blown overhead `HarbourBunting` pennant garlands, interactive sculpted `TavernGrogKeg` (`+35 HP` & rotating pirate toasts), campfire `CampfireCookingStove` tripod, animated Merchant Factor, Pier Quartermaster & campfire Concertina Bard (`TavernBardNPC`), faceted crystal `BeaconGlowCore`, automatic harbour restock, voyage notice board, gold/renown treasure turn-in with celebratory doubloon fountain, multi-strike shovel excavation sites with golden unearth shimmer, sculpted 7-log lashed-driftwood Castaway Raft, and sculpted Nautical Iron Salvage Bell-Buoy (`scenes/main.gd`).
- Showcase: `scenes/showcase/island_showcase.tscn`.

## Held tools, armory, map table and diegetic UI (`src/items/`, `src/ui/`)
- `ToolMeshes` (`src/items/tool_meshes.gd`): procedural PBR 3D meshes for all 11 core radial tools (`cutlass`, `pistol`, `compass`, `spyglass`, `lantern`, `shovel`, `bucket`, `planks`, `map`, `tankard`, `instrument`), Armory alternate weapons (`boarding_axe`, `blunderbuss`), and crew shanty instruments (`hurdy_gurdy`, `whistle`).
- `Inventory` (`src/items/inventory.gd`): first-person viewmodel rig, Armory melee/ranged loadout switching (`set_weapon_loadout`), sway/bob/raise poses (compass heading needle, spyglass zoom & sighting readout, lantern toggle, dynamic `MapPainter` parchment treasure chart, shovel dig, bucket bail, plank patch, grog sip, shanty instrument).
- `MapTableView` (`src/items/map_table_view.gd`): off-screen-throttled live SubViewport parchment archipelago chart mounted on `Station_MapTable` (Sloop & Brigantine), showing discovered island contours, active voyage circle, dashed 16-point sepia course-bearing line & distance readout (`format_course_bearing`), live wind-direction feather medallion, Spacebar interactive pin toggle with plotting reticle, storm cells, salvage wrecks, live Leviathan tentacle-star & Fort Siege crossed-cannon threat ink stamps, and ship heading/trail.
- `GameHUD` (`src/ui/hud.gd`), `RadialWheel` (`radial_wheel.gd`), `HudIcons` (`hud_icons.gd`), `ShipwrightMenu` (`shipwright_menu.gd`): parchment-and-ink UI rendered with 106-glyph ink-kerned `assets/generated/ui/scoundrel_font.fnt`; 11-wedge Item Radial (`Tab`, dynamically reflecting Boarding Axe/Blunderbuss labels, hints & hand-drawn ink icons), 9-wedge Crew Command Wheel (`Q`), diegetic crosshair hit-confirm ink ticks & timed-parry brass guard-arcs, peripheral ink-wash damage vignette & low-HP heartbeat pulse (colorblind-aware), hull leak/flood urgency alerts on the supplies chip, auto-wrapped top-center crew callout banners, diegetic Boss Encounter Bar, non-blocking first-launch Voyage Title Card (`show_voyage_title`), pause/settings with built-in Captain's Controls strip, and 3-tab Outpost Shipwright (Voyage Board, Companies/Sidegrades/Ship Class live-swap/Armory Loadout/4-param `hull_livery` & sail/flag liveries with ink-framed color swatch previews, Settings/Keybinds). Accessibility-gated `PlayerController.add_camera_trauma()` delivers cannon recoil, hull impact (`Ship.hull_impacted`), and close-thunder rumble.
- Showcase: `scenes/showcase/items_showcase.tscn` (`shot=tools|armory|map_table|hud`).

## Voyages, economy and world director (`src/voyage/`)
- `Treasure` (`treasure.gd`): `Carryable` loot items with company tags, gold/renown values, optional cargo hazards (weeping bilge, volatile powder, fragile porcelain), and 100% sculpted painterly flat-faceted `ArrayMesh` visuals (`WeakRef`-cached sRGB vertex-colored skulls with glowing iris cores & gold tooth, Spanish-gold fluted jeweled chalices, warm honey-oak slatted crates with wax seals, GLB/sculpted banded chests + luminous `CursedAuraTrim` & tier crowns/medallions).
- `Economy` (`economy.gd`): 3 trading companies (Cartographers' Guild, Iron Tide Company, Freebooters' Exchange), renown ranks, balanced ship/crew sidegrades, and sail/flag/hull paint liveries (`hull_livery`) persisted in `Profile`.
- `VoyageComposer` (`voyage_composer.gd`) & `VoyageManager` (`voyage_manager.gd`): 3-chapter authored Story Voyage chain (starting with *The Salt-King's Ledger* to Cutlass Cay) plus 8+ procedural voyage shapes composed from hooks, sites, complications, and payoffs with anti-repetition scoring.
- `WorldDirector` (`world_director.gd`): cargo-proportional living-sea pacing director spawning rival ships, ghost ships, storm cells, shark packs, Abyssal Leviathan, fort sieges, flotsam barrels, and castaways — plus ~60% salvage wreck recovery & outpost restoration on ship sinking (zero-wipe guarantee).

## Downtime, settings and networking (`src/downtime/`, `src/core/`, `src/net/`)
- `FishingLine` (`src/downtime/fishing.gd`) & `CookingStove` (`src/downtime/cooking.gd`): stern-rail casting/tension-reeling mini-game with a sculpted stowed bamboo rod & oak/brass rail cleat, 3-section flexing bamboo-and-brass rod, 14-segment camera-aligned catenary line (taut & amber under high tension), painted two-tone cork bobber, fight splashes & sculpted 5-species leaping catch fish; plus self-contained sculpted soot-black **Cast-Iron Naval Galley Hearth** (`build_hearth = true`) and forged-iron **3-Leg Campfire Cooking Tripod** (`build_campfire_tripod = true` on island & outpost campfires), sculpted fish & crab sizzling meshes (raw -> golden seared -> burnt), feathered billboard `GPUParticles3D` steam/smoke, and health restoration.
- `UserSettings` (`src/core/settings.gd`): persistent `user://settings.json` for ocean/cloud quality presets, audio bus volumes, mouse sensitivity, FOV, subtitles, colourblind/camera-shake accessibility, and live input key rebinding.
- `Net` (`src/net/net.gd`): host-authoritative ENet sessions (`host()`, `join()`, `reconnect()`, `start_single_player()`), replicated sea clock & weather, ship & pawn state sync, client intent RPCs, late-join sync, and bounded reconnect retries.

