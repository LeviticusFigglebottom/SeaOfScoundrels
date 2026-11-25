# Progress

Re-read this, ROADMAP.md, DECISIONS.md, ARCHITECTURE.md and the "Quality bar" in DESIGN.md when resuming.

## Current state (2026-11-25)
- Engine: Godot 4.8 beta 5 (owner request). Tooling: `tools/setup_env.sh`, `tools/test.sh`, `tools/test_net.sh`, `tools/test_gpu.sh`, `tools/lint.py`, `tools/capture.sh`, `tools/build_assets.sh`.
- Merged on the main line: foundations, net clock/weather replication, profile saves, sky and weather (pass 1), pawn and player controller, sloop model (pass 1), audio, ocean (pass 1).
- `scenes/main.tscn` shows the real ocean under the real sky (no ship yet).
- CI (GitHub Actions) runs lint, tests, net test and Linux export.

## In flight (worktree branches)
- `ws/sky2`: sky pass 2 (volumetric-feeling clouds, storm cells as places, lightning, cloud shadows, moon).
- `ws/ship`: ship physics pass 2 (retune for the 16-wave sea, real sloop model, pawn walkability, replication). Pass 1 is NOT merged: two tests fail against the new sea.
- `ws/shipart`: sloop pass 2 (hold headroom, real hull breaches, glass, running rigging, sail weights).
- `ws/ocean2`: ocean pass 2 (fair-weather drama, shoaling, hull mask, shadows on water).
- `ws/island`: island generator, props, treasure island and outpost.
- `ws/charart`: characters, rig, animation set, animation driver.
- `ws/items`: held tools, HUD, command wheel.

## Next
- Integrate ship + pawn + ocean + sky + island into the main scene; AI crewmate; combat and the Drowned; voyage loop; independent reviews of each flagship system.

## Operational notes
- The container restarted once (2026-11-25) and stopped every agent. Worktrees under `/home/user/ws-*` and `/opt/tools` survived that time, but only this branch is on the remote: agents must commit often, and anything not merged here is at risk if the container is reclaimed.
- Stopped agents can be resumed by messaging their ids; their briefs live in the session, so if the session itself is lost, re-brief from ROADMAP.md, the Quality bar and the "In flight" list above.

## Known issues
- No GPU here: frame times are unmeasured (DECISIONS D9). The ocean agent estimates 1.5-2.5 ms at 1080p on a GTX 1660 for high quality.
- Nobody has listened to the audio except through analysis; the owner has a preview.
