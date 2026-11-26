# Roadmap

Milestones with acceptance criteria. Status lives in PROGRESS.md.

## M0. Foundations
- [x] Godot pinned, project skeleton, autoloads (`Net`, `Weather`, `Sea`, `Game`).
- [x] Shared wave function on CPU and in shader, with tests.
- [x] Headless test runner; off-screen capture tool.
- [x] CI: tests + Linux/Windows/macOS export on every push (`.github/workflows/ci.yml`).
- [x] One-command asset rebuild (`tools/build_assets.sh`, all 11 Blender/texture/audio generators).

## M1. Vertical slice: "There and back"
Accept when a player can, in one sitting, without debug keys:
- [x] **Ocean**: rolling swells, foam, translucent crests, refraction, underwater view; calm to storm blend. Verified in Round 1 & 2 visual reviews + real-GPU 1080p Vulkan captures.
- [x] **Sky**: day/night cycle, sun and moon, stars, volumetric SDF clouds, cloud shadows, fog tied to weather; storm with rain and lightning.
- [x] **Sloop**: floats on the visible waves (bow rises on the swell you see); wheel with inertia, sail length and angle with wind response, anchor; takes hull holes, floods, can be bailed and patched, sinks. Headless physics tests cover float, turn, sail, flood, sink (`test_ship.gd`: 8/8).
- [x] **Pawn**: walk and jump on a rolling deck without sliding or jitter; swim; ladders; use stations; carry a chest (`test_pawn.gd`).
- [x] **Tools**: compass, spyglass, lantern, held map, shovel, bucket, planks, tankard, instrument, cutlass, pistol; live SubViewport map table on the ship (`test_items.gd`).
- [x] **AI crewmate**: takes helm or sails on order, trims sensibly on its own, bails and repairs, calls out land and ships, banters (`test_crew.gd`).
- [x] **Island**: 11 generated islands including Cutlass Cay treasure island with readable limestone spires, monotonic beach, palms, rocks, dig sites; Port Scoundrel & outlying outposts with docks, voyage boards and merchant stalls (`test_island.gd`).
- [x] **Enemies**: Drowned on islands (melee with block, parry, stagger, shield-bearers, powder-carriers, captains); cursed Drowned sloop that hunts and trades broadsides (`test_combat.gd`).
- [x] **Loop**: take the map, sail, dig, fight, carry chest aboard, survive the interception, sell at the outpost (`test_vertical_slice.gd`).
- [x] **Audio**: ocean, wind, hull, sail, cannon, sword, footsteps; original shanties; crew barks (`test_audio.gd`, `analyze.py` 0 flagged).
- [x] **Save**: gold, renown, unlocks, discoveries and ship class persist (`test_profile.gd`).
- [x] Runs as host with a second client joining and seeing the same ship and sea (`tools/test_net.sh` PASS).

## M2. A living sea
- [x] Voyage composer (hooks, sites, complications, payoffs); 8+ voyage shapes with anti-repetition scoring (`test_voyage.gd`).
- [x] World-event director: storms as places, shark packs, Abyssal Leviathan boss (`test_leviathan.gd`), ghost ship, fort siege, wrecks (~60% salvage recovery), floating barrels and castaways.
- [x] Archipelago of 11 islands with distinct landmarks; live MapTableView shows discoveries.
- [x] Second and third enemy factions (Tidecallers & Corsairs + rival captains); enemy variants with distinct behaviour (`test_combat.gd`).
- [x] Full crew of three AI (Barnaby, Maren, Pip) with 9-wedge command wheel, personalities, shanty sessions and co-op peer slot yielding.

## M3. Depth
- [x] Companies (3 trading companies), renown ranks, sidegrade fittings (hull, sails, cannons, crew traits), cosmetics/liveries, 3-tab Outpost Shipwright UI (`src/ui/shipwright_menu.gd`).
- [x] Second ship class (two-masted Brigantine, `src/ship/brigantine.tscn`, live harbour class-swapping); rival captains; 3-chapter authored story voyage chain.
- [x] Fishing, cooking, grog; instruments with playable shanties (`test_downtime.gd`).
- [x] Co-op hardening: late join, bounded automatic reconnection (`Net.reconnect()`), host-authority decision recorded in `DECISIONS.md` D22.

## M4. Polish and performance
- [x] Real-GPU 1080p Vulkan profiling against D10 frame budget (RX 9070 XT: `1.32 ms` GPU MED / `1.57 ms` HIGH sailing, ~`6.6 ms` est. GTX 1660 class — well under 16.6 ms / 60 fps); ship LODs; Ocean/Cloud quality presets.
- [x] Starter story voyage (*The Salt-King's Ledger*), accessibility options (subtitles, camera shake, colourblind palette), live key rebinding (`UserSettings`), original procedural BMFont (`scoundrel_font.fnt`, D11 resolved).
- [x] Windows, Linux and macOS release exports from CI (`.github/workflows/ci.yml`, `export_presets.cfg`).
