# Roadmap

Milestones with acceptance criteria. Status lives in PROGRESS.md.

## M0. Foundations
- [x] Godot pinned, project skeleton, autoloads (`Net`, `Weather`, `Sea`, `Game`).
- [x] Shared wave function on CPU and in shader, with tests.
- [x] Headless test runner; off-screen capture tool.
- [ ] CI: tests + Linux export on every push.
- [ ] One-command asset rebuild.

## M1. Vertical slice: "There and back"
Accept when a player can, in one sitting, without debug keys:
- [ ] **Ocean**: rolling swells, foam, translucent crests, refraction, underwater view; calm to storm blend. Screenshots hold up next to the vision at noon, sunset, night, storm.
- [ ] **Sky**: day/night cycle, sun and moon, stars, clouds, fog tied to weather; storm with rain and lightning.
- [ ] **Sloop**: floats on the visible waves (bow rises on the swell you see); wheel with inertia, sail length and angle with wind response, anchor; takes hull holes, floods, can be bailed and patched, sinks. Headless physics tests cover float, turn, sail, flood, sink.
- [ ] **Pawn**: walk and jump on a rolling deck without sliding or jitter; swim; ladders; use stations; carry a chest.
- [ ] **Tools**: compass, spyglass, lantern, held map; map table on the ship.
- [ ] **AI crewmate**: takes helm or sails on order, trims sensibly on its own, bails and repairs, calls out land and ships, banters.
- [ ] **Island**: one generated treasure island with a readable silhouette, beach, palms, rocks, a dig site; one outpost with a dock and a buyer.
- [ ] **Enemies**: Drowned on the island (melee with block, parry, stagger); one Drowned sloop that hunts and trades broadsides.
- [ ] **Loop**: take the map, sail, dig, fight, carry chest aboard, survive the interception, sell at the outpost.
- [ ] **Audio**: ocean, wind, hull, sail, cannon, sword, footsteps; one original shanty; crew barks.
- [ ] **Save**: gold and progress persist.
- [ ] Runs as host with a second client joining and seeing the same ship and sea.

## M2. A living sea
- Voyage composer (hooks, sites, complications, payoffs); 6+ voyage shapes.
- World-event director: storms as places, shark packs, leviathan, ghost ship, fort siege, wrecks, floating barrels and castaways.
- Archipelago of 10+ islands with distinct landmarks; map table shows discoveries.
- Second and third enemy factions; enemy variants with real behaviour.
- Full crew of three AI with command wheel, personalities, shanty sessions.

## M3. Depth
- Companies, renown, sidegrade fittings (hull, sails, cannons, crew traits), cosmetics, shipwright UI.
- Second ship class; rival captains; authored story voyage chain.
- Fishing, cooking, grog; instruments with playable shanties.
- Co-op hardening: late join, reconnection, host migration decision.

## M4. Polish and performance
- Real-GPU profiling against the frame budget; LODs; quality settings.
- Tutorial voyage, accessibility options, key rebinding, generated font.
- Windows, Linux, macOS exports from CI.
