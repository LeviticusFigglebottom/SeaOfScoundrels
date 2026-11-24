# Progress

Re-read this, ROADMAP.md, DECISIONS.md and ARCHITECTURE.md when resuming.

## Current state (2026-11-24)
- M0 foundations in place: skeleton, autoloads, shared wave function with tests, test runner, capture tool, CI workflow.
- `scenes/main.tscn` is a placeholder ocean plane.
- Tooling on the dev machine: Godot at `/usr/local/bin/godot`, Blender at `/usr/local/bin/blender`, export templates archive at `/opt/tools/tpl.tpz` (not yet installed). These live outside the repo and vanish with the container; `tools/setup_env.sh` reinstalls them.

## In flight
- Ocean rendering, sky and weather, ship physics, pawn and controller, sloop model (parallel agents on worktree branches).

## Next
- Integrate the above into `scenes/main.tscn`; character model and animation; island generator; AI crewmate; Drowned enemy; audio.

## Known issues
- No GPU here: frame times are unmeasured (DECISIONS D9).
