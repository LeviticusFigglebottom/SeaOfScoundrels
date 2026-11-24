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
