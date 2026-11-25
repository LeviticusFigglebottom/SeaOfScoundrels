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

**D11. Font: FLAG.** No font file is in the repo. Text uses Godot's built-in fallback font, which ships inside the engine binary (Open Sans, OFL). If that counts as third-party content, the fix is a generated stroke font from `tools/`; planned as a polish item.

**D12. First-person player, third-person-quality crew.** Like the inspiration, the player is first person (immersion with diegetic tools), but player and AI share one `Pawn` with a full body model so co-op partners and crew look right.

**D13. Stay on 4.7.2 until 4.8 is stable (checked 2026-11-24).** godotengine.org lists 4.8 only as pre-release: beta 5 came out today and the release notes say a release candidate is next. The brief asks for the latest stable, so the pin stays at 4.7.2. When 4.8-stable appears: bump `.godot-version`, run the project upgrade tool, re-run tests and captures, and review the "breaks compat" list (mbedTLS/network changes, sky shader SCREEN_UV, export option serialization). Features worth adopting then: `Trail3D` (wakes, cannonball and sword trails), non-allocating physics queries (buoyancy and AI raycasts), Label auto font size (HUD).

**D14. Moved to Godot 4.8 beta 5 at the owner's request (2026-11-24), superseding D1 and D13.** Pin is `4.8-beta5` in `.godot-version`; tests, net test, capture and Linux export verified on it. Move to each newer 4.8 pre-release and then 4.8-stable as they appear, re-running the same checks. Notes on what 4.8 offers: `docs/GODOT_4_8_NOTES.md`.

**D15. Clouds are flat noise layers in the sky shader, not meshes or raymarching.** Two layers (cumulus, cirrus) sample one generated 512 px noise texture (`tools/textures/gen_sky_noise.py`); the cumulus edge is a tight threshold and its shading is three flat tones from a second sample taken towards the light. Seven texture reads per sky pixel, no extra passes or draw calls, which fits the 1.5 ms sky budget with room to spare. The cost: clouds have no parallax or real volume and cannot be flown through or cast shadows on the sea. Revisit with Rare-style cloud meshes if landmark clouds (skull, ship) or towering storm cells are wanted.

**D16. The sky's colours live in one script, `src/sky/sky_palette.gd`.** A pure function of sun height, cloud cover and storminess, keyed at six sun heights and authored in sRGB. The sky shader, lights, fog and the global uniforms all read the same values, so fog always matches the horizon. The sky's radiance map runs in realtime mode (256 px) because the sky changes every frame.

**D17. `Weather.wind_vector()` includes gusts.** Sails, spray and flags get gusts without extra code; anything that needs the steady wind uses `mean_wind_vector()`. Gusts are a function of the replicated `clock`, so peers agree.


**D18. Quality bar for flagship systems (owner directive, 2026-11-24).** See "Quality bar" in DESIGN.md. Consequences: every flagship workstream (ocean, sky and weather, ship physics and mechanics, ship model, islands) gets an independent review and at least one dedicated polish pass after first merge; the frame budget in D10 is a target for the default quality preset, with higher presets allowed to exceed it; D15 (flat cloud layers) is reopened, since clouds without volume do not meet the bar.

**D19. Clouds are a raymarched signed-distance field in the sky shader, supersedes D15.** Considered: mesh or impostor clouds composited soft (Rare's approach), a classic density raymarch, and a hybrid. Chosen: one analytic field (weather-map footprints, flat-based domes, a generated 64^3 puff volume carved out) that returns a rough signed distance, marched in Godot's half-resolution sky pass. Why: the same function gives parallax, towering and flat-based shapes, storm cells with a world position, weather fronts, and the ground shadow (`cloud_shadow_tex` is the field projected along the light), with nothing to place, sort or wrap; sphere-tracing with a few steps is opaque and crisp, which suits the painterly look better than noisy semi-transparent volumes; and the sky sub-passes give reduced-resolution rendering and soft upscaling for free. Cost: clouds are behind all geometry (nothing can fly through them, a far island cannot hide a nearer storm tower; the cell's rain curtain is real geometry for that reason), and shaped landmark clouds would need an extra SDF term or meshes. `SkyRig.cloud_quality` scales it: low (quarter-res), medium (half-res, the D10 budget), high (full-res, exceeds it). Revisit with meshes if clouds must interact with ships or the camera must enter them.

