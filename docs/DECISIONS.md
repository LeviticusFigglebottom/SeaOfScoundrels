# Decisions log

Newest last. Each entry: decision, why, and what would change it.

**D1. Godot 4.7.2-stable, pinned in `.godot-version`.** Latest stable on godotengine.org as of 2026-11-24. Renderer Forward+, physics Jolt (built in). GDScript only: no C#, no GDExtension, so CI and export stay one binary.

**D2. Blender 5.3.0 headless for models, pinned in `.blender-version`.** Python generator scripts under `tools/blender/`. Audio and textures from Python (numpy/scipy/Pillow) under `tools/audio/` and `tools/textures/`. `tools/build_assets.sh` rebuilds everything.

**D3. Generated assets are committed** under `assets/generated/`. The pipeline is reproducible, but committing outputs keeps every commit runnable without Blender and keeps CI fast. Revisit if the repo grows past a few hundred MB.

**D4. Gerstner sum, not FFT, for the ocean.** Rare used a Tessendorf FFT. An FFT surface cannot be evaluated cheaply at arbitrary points on the CPU, and the brief requires one function for shader and physics. A small Gerstner set (up to 12 waves) is exact on both sides; the shader adds normal-only detail. Revisit only if the surface looks too regular after tuning.

**D5. Wave directions are fixed world constants.** Rotating a Gerstner direction makes the pattern sweep sideways far from the origin. Weather changes amplitude only. Wind direction still changes freely and affects sailing, spray and clouds.

**D6. Input actions are registered in code** (`src/core/input_setup.gd`), not in `project.godot`, so parallel branches do not conflict.

**D7. Own minimal test runner** (`tests/test_runner.tscn`) instead of a third-party framework. Tools are allowed, but this is 60 lines and has no dependency.

**D8. Development branch.** This environment may only push to `ccr-663b66a0-rdiq4f`; that branch plays the role of "main" (always runnable). Workstreams use local worktree branches merged into it.

**D9. Software rendering for verification.** This environment has no GPU; visuals are checked with Mesa lavapipe (software Vulkan) under Xvfb via `tools/capture.sh`. Frame times measured here are not representative. The frame budget (D10) is tracked by draw calls, primitive counts and shader cost reasoning, and needs a real-GPU check. FLAG for the owner: please run the game on real hardware and report frame time.

**D10. Frame budget target:** 60 fps (16.6 ms) at 1080p on a mid-range 2020 desktop GPU (GTX 1660 class). Sub-budgets: ocean 3 ms, sky and clouds 1.5 ms, world and ships 4 ms, characters 2 ms, post 1.5 ms, CPU sim 4 ms per frame.

**D11. Font (resolved 2026-11-25).** Originally flagged when no font file existed in the repo. Now resolved by `tools/textures/gen_font.py` (auto-run by `tools/build_assets.sh`), which procedurally synthesises an original nautical stroke BMFont atlas (`assets/generated/ui/scoundrel_font.{fnt,png}`, 105 printable ASCII + typographic punctuation glyphs) loaded natively by Godot 4.8 as a `FontFile`. Zero third-party font data remains.

**D12. First-person player, third-person-quality crew.** Like the inspiration, the player is first person (immersion with diegetic tools), but player and AI share one `Pawn` with a full body model so co-op partners and crew look right.

**D13. Stay on 4.7.2 until 4.8 is stable (checked 2026-11-24).** godotengine.org lists 4.8 only as pre-release: beta 5 came out today and the release notes say a release candidate is next. The brief asks for the latest stable, so the pin stays at 4.7.2. When 4.8-stable appears: bump `.godot-version`, run the project upgrade tool, re-run tests and captures, and review the "breaks compat" list (mbedTLS/network changes, sky shader SCREEN_UV, export option serialization). Features worth adopting then: `Trail3D` (wakes, cannonball and sword trails), non-allocating physics queries (buoyancy and AI raycasts), Label auto font size (HUD).

**D14. Moved to Godot 4.8 beta 5 at the owner's request (2026-11-24), superseding D1 and D13.** Pin is `4.8-beta5` in `.godot-version`; tests, net test, capture and Linux export verified on it. Move to each newer 4.8 pre-release and then 4.8-stable as they appear, re-running the same checks. Notes on what 4.8 offers: `docs/GODOT_4_8_NOTES.md`.

**D15. Clouds are flat noise layers in the sky shader, not meshes or raymarching.** Two layers (cumulus, cirrus) sample one generated 512 px noise texture (`tools/textures/gen_sky_noise.py`); the cumulus edge is a tight threshold and its shading is three flat tones from a second sample taken towards the light. Seven texture reads per sky pixel, no extra passes or draw calls, which fits the 1.5 ms sky budget with room to spare. The cost: clouds have no parallax or real volume and cannot be flown through or cast shadows on the sea. Revisit with Rare-style cloud meshes if landmark clouds (skull, ship) or towering storm cells are wanted.

**D16. The sky's colours live in one script, `src/sky/sky_palette.gd`.** A pure function of sun height, cloud cover and storminess, keyed at six sun heights and authored in sRGB. The sky shader, lights, fog and the global uniforms all read the same values, so fog always matches the horizon. The sky's radiance map runs in realtime mode (256 px) because the sky changes every frame.

**D17. `Weather.wind_vector()` includes gusts.** Sails, spray and flags get gusts without extra code; anything that needs the steady wind uses `mean_wind_vector()`. Gusts are a function of the replicated `clock`, so peers agree.


**D18. Quality bar for flagship systems (owner directive, 2026-11-24).** See "Quality bar" in DESIGN.md. Consequences: every flagship workstream (ocean, sky and weather, ship physics and mechanics, ship model, islands) gets an independent review and at least one dedicated polish pass after first merge; the frame budget in D10 is a target for the default quality preset, with higher presets allowed to exceed it; D15 (flat cloud layers) is reopened, since clouds without volume do not meet the bar.

**D19. Ocean wave set: 16 Gerstner waves with separate calm and storm amplitudes** (amends D4's "up to 12"; the cap is now 32). One global amplitude multiplier could only make the calm sea taller; the owner wants storms that are steep and chaotic. Each wave now blends between a calm and a storm amplitude with `Sea.amp_scale`, still one function shared exactly by CPU and shader (`tools/test_gpu.sh` checks it on the GPU). Waves shorter than about 7 m carry centimetres and are normal-only detail. Revisit the count if `Sea.height()` (about 12 microseconds) shows up in the CPU budget.

**D20. The ocean shades itself (unshaded material) and simulates foam in a rest-plane texture.** Full control of the stylized look, one draw call, and foam that lingers and takes stamps from other systems (`Ocean.add_foam`). Costs: no engine shadows on water (a cloud-shadow include can be multiplied in when the sky provides it), and transparent objects are not refracted or fogged. Quality levels (`Ocean.quality`) scale mesh density, foam simulation, detail layers and underwater shafts.

**D21. Clouds are a raymarched signed-distance field in the sky shader, supersedes D15.** Considered: mesh or impostor clouds composited soft (Rare's approach), a classic density raymarch, and a hybrid. Chosen: one analytic field (weather-map footprints, flat-based domes, a generated 64^3 puff volume carved out) that returns a rough signed distance, marched in Godot's half-resolution sky pass. Why: the same function gives parallax, towering and flat-based shapes, storm cells with a world position, weather fronts, and the ground shadow (`cloud_shadow_tex` is the field projected along the light), with nothing to place, sort or wrap; sphere-tracing with a few steps is opaque and crisp, which suits the painterly look better than noisy semi-transparent volumes; and the sky sub-passes give reduced-resolution rendering and soft upscaling for free. Cost: clouds are behind all geometry (nothing can fly through them, a far island cannot hide a nearer storm tower; the cell's rain curtain is real geometry for that reason), and shaped landmark clouds would need an extra SDF term or meshes. `SkyRig.cloud_quality` scales it: low (quarter-res), medium (half-res, the D10 budget), high (full-res, exceeds it). Revisit with meshes if clouds must interact with ships or the camera must enter them.

**D22. Co-op host authority without mid-sea host migration (M3 decision).** Considered: peer-to-peer host handoff on host drop vs. clean host-authoritative sessions with client late-join sync and bounded reconnect (`Net.reconnect()`, `connection_lost`, `connection_failed`). Chosen: host-authoritative sessions with persistent captain/ship profile saves on the host and automatic client reconnect retries (`Net`). Why: mid-sea migration of RigidBody3D ships, AI crew utility state, hull breach arrays and WorldDirector pacing timers adds high desync risk for minimal value in 1–4 player friend sessions; returning peers rejoin the saved world cleanly, and AI crewmates automatically yield and reclaim deck slots as friends join or leave. Revisit only if dedicated headless servers are added.

**D23. Second ship class: two-masted Brigantine (`src/ship/brigantine.tscn`).** Chosen over a three-masted galleon so 2–4 player crews (or solo + 3 AI crewmates) stay nimble without excessive running between three yards. `tools/blender/gen_brigantine.py` follows the exact `docs/SHIP_ART.md` contract (`Station_*`, `col_*`, `HullPanel_NN`/`Hole_NN`/`HolePatch_NN`, `mask_water`, `Sail_Fore`/`Yard_Fore`/`Flag_Fore`, twin aft broadside cannons `Station_CannonPortAft`/`Station_CannonStarboardAft`), allowing `Ship` (`src/ship/ship.gd`) to drive both Sloop and Brigantine from one class-aware script and live-swap classes in harbour via `ShipwrightMenu`.

**D24. Three distinct enemy factions with behavioural differentiation.** Drowned (skeleton crews: melee shamblers, shield-bearers requiring flank/parry, volatile powder-carriers, buffing captains, cursed Drowned sloops), Tidecallers (coral-armoured ranged sea cultists that reposition and summon water surges), and Corsairs (agile human freebooter raiders using dodge-steps, boarding axes, blunderbusses, rival captains, and fast Corsair sloops), plus Ghost Ships, Shark packs, and the multi-tentacle Abyssal Leviathan boss.

**D25. Clean `RenderingServer` SubViewport/global-uniform teardown on `_exit_tree()`.** Binding a `ViewportTexture` RID to a global shader uniform (`cloud_shadow_tex` in `SkyRig`) or material (`FoamField` in `Ocean`) without releasing it before scene shutdown deadlocked Godot 4.8's Forward+ Vulkan render thread on exit (`__futex_wait`). `SkyRig`, `Ocean`, `FoamField`, `Underwater`, and `CrestSpray` now explicitly clear global texture uniforms and material shader parameters in `_exit_tree()`, guaranteeing clean `EXIT=0` shutdown across all scenes and automated captures.


