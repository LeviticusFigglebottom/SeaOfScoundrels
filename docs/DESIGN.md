# Sea of Scoundrels: Design

A stylized pirate sandbox for one captain and an AI crew, or up to four friends in co-op, against a sea full of AI threats. Inspired by Sea of Thieves; everything here (names, characters, music, designs) is original.

Research behind this document: [RESEARCH.md](RESEARCH.md).

## 1. What the research says

**Loved (keep and nail)**
- The ocean and the look. Even lukewarm launch reviews singled out the sea.
- Sailing as hands-on crew work: wheel, sails, anchor and map are separate physical jobs.
- Ship-to-ship combat, praised even by reviewers who disliked the melee.
- "Tools not rules": every item is a freely usable physical tool, which produces unscripted stories.
- Diegetic, near-HUD-less play, and physical treasure that has to be carried home.
- Authored story voyages (the 2019 Tall Tales were the turning point), and low-stakes downtime such as fishing and cooking.

**Criticized (fix)**
- Thin content and repetitive voyages (kill, dig, deliver).
- Cosmetic-only progression that gave no hook.
- Shallow melee, weightless weapons, skeleton variants that all behave alike.
- Solo play: one person cannot steer, trim, navigate, fight and repair at once, and has no lookout.
- Losing hours of loot to ambush; unreliable hit registration and broken world events.
- Supply-gathering busywork before the fun starts.
- A PvE mode treated as second-class (capped rewards).

One finding shapes the whole design: Rare deliberately blocked the helm's view and put the map below deck so that a crew must talk. That friction is the charm in a group and the tedium alone. We keep the friction and give the solo captain a crew to talk to.

## 2. Pillars

1. **The sea is the star.** Big rolling swells, foam, translucent crests, storms, underwater. One wave function drives both the shader and the physics, so what you see is what the ship floats on.
2. **The ship is a machine you crew.** Real buoyancy and weight, wind and trim, wheel inertia, anchor, holes, flooding, bailing, repair, sinking. "Believable, not realistic."
3. **You are the captain; the crew is competent.** AI crewmates take stations, call out what they see, follow quick orders, act sensibly without them, and have personalities. The same slots take human friends.
4. **Tools, not rules.** Map table, compass, spyglass, lantern, held treasure maps, carried cannonballs and chests. Minimal HUD, no minimap.
5. **A painterly world readable from the horizon.** Chunky silhouettes, bold colour, dynamic sky, landmark islands.
6. **A perilous, living sea.** Storms, sea monsters, ghost and skeleton ships, forts. Sailing downtime is never empty.
7. **Charm.** Shanties, instruments, grog, humour, expressive animation.

## Quality bar (owner directive, 2026-11-24)

No graphical or mechanical quality is to be compromised. The flagship features are, together: the water and seas (massive, dynamic, beautiful, at times turbulent), the sky and weather, the physics, the ships with all their mechanics fully fleshed out, and the islands. In practice:

- A flagship system is not "done" at first merge. It is done when captures hold up against the vision in every condition (calm, storm, noon, sunset, night, close, far, in motion), a fresh reviewer has gone through it, and its listed weak spots are fixed, not just logged.
- When quality and the frame budget conflict, build the high-quality version and add a scalable quality setting below it; do not ship the cheap version as the only one.
- When quality and schedule conflict, quality wins: go deeper on the flagship systems before going wider on content.
- Placeholders (flat water planes, primitive ships, capsule characters) never appear in the main game scene once the real system exists.

## 3. Core loop

Port (stock up, pick voyages, refit) → set sail (crew the ship, navigate with diegetic tools) → the sea happens (weather, events, rivals) → objective (island, fort, wreck, hunt) → haul treasure home under threat → sell, earn gold and renown → sidegrade the ship and crew.

A session should produce a story within 20 minutes and never erase itself on failure.

## 4. Systems

### Ocean
Sum-of-Gerstner swell set shared by shader and CPU (`Sea` autoload); the shader adds normal-only micro detail. Colour from a deep/subsurface blend driven by crest mask, view and sun; foam from the wave Jacobian and from depth intersections; refraction, depth fog, underwater view with caustic light and a surface seen from below. Storms raise amplitude smoothly. Wave directions are fixed constants (see DECISIONS).

**Surface target (owner reference, 2026-11-25).** The owner supplied a deck-height fair-weather screenshot of the inspiration as the bar for our water (a quality target only; nothing is copied). The surface must be fully textured and dynamic: fine ripples and lacy foam webbing covering all near water, draped over and stretched along the wave faces; texture and foam that flow with the water's motion (up faces, over crests, streaming down the backs) instead of scrolling uniformly; chunky steep crests with smaller waves riding the big ones even in fair weather; breaking crests that throw spray; dense twinkling sun glints; strong colour separation (deep blue distance and backs, translucent teal crests, milky green under foam); and a bright hazy horizon with islands as pale silhouettes. Acceptance: our deck-height noon capture holds up beside the reference for richness, flow and liveliness, and a motion clip shows the texture flowing over the waves.

### Ship
Rigid body with per-point buoyancy sampled from `Sea`, drag split into forward/lateral/vertical, keel resistance, rudder torque that scales with speed, sail force from wind angle and trim, heel in gusts. Anchor with a swinging stop. Hull damage creates holes below or above the waterline; holes below it flood the hold; water adds mass and lowers the ship; bail with buckets, patch with planks; past a threshold the ship founders. Ship classes later (sloop first).

### Stations and tools
Every crewable thing is a `Station` (helm, sail length, sail angle, anchor capstan, cannons, map table, bilge, repair points). Players and AI use the same station API. Held tools are `Item`s in a small radial: compass, spyglass, lantern, cutlass, pistol, bucket, planks, map, tankard, instrument.

### AI crew
Each crewmate has a role preference, a utility-based brain that picks stations by need (flooding beats trimming), callouts (land, sail, rocks, leak, wind shift), and a personality that colours banter. The captain's command wheel gives orders: man a station, trim for speed, drop or raise anchor, fire at target, repair, bail, follow me, fetch that chest, hold fire. Orders override utility until done or cancelled.

### Combat
Melee with weight: light chain, heavy, block, timed parry that staggers, dodge step, stamina. Distinct weapons (cutlass, boarding axe, pistol, blunderbuss). Enemy factions with readable behaviour rather than reskins:
- **Drowned** (skeleton crews): shamble in numbers, weak to parry; variants add real behaviour (shield-bearers who must be flanked, powder carriers who must be shot first, captains who buff).
- **Tidecallers** (coral-grown sea cultists): ranged, reposition, summon water hazards.
- **Beasts**: crabs that guard, eels that ambush swimmers, gulls that mark loot.
- **At sea**: Drowned sloops, ghost ships that phase and broadside, a leviathan, a shark pack.
Hits are resolved by the host with generous, clearly telegraphed windows.

### Voyages and events
Voyages are composed from parts: a **hook** (map, riddle, bounty, rumour, cargo contract, rescue), a **site** (island type, fort, wreck, sea cave, open-sea hunt), **complications** (storm, rival ship, curse, time limit, fragile cargo) and a **payoff** (treasure class, renown, unique fitting). Authored story voyages use the same parts with scripted beats. World events spawn on a pacing director that tracks how long since the last surprise and how much cargo is aboard: rivals hunt in proportion to cargo, with a warning (a sail on the horizon, a crew callout) and a way out.

### Progression and saves
Gold and renown with three trading companies. Unlocks are **sidegrades**: hull (fast and fragile vs. stout and slow), sails (speed vs. close-hauled handling), cannon types, crew traits, tool variants. Plus cosmetics for ship and crew. Persistent save of captain, ship loadout, crew roster, discoveries. On sinking, part of the cargo is salvageable from a marked wreck and the ship is restored at the last port: a setback and a new errand, not a wipe.

### Tedium cuts
Ports stock the ship automatically (a quartermaster crewmate handles it; barrels on islands are a bonus). One-press take-all from containers. Crew fetch and carry. Fast, readable repair and bail loops. Sailing downtime is filled with crew banter, shanties, fishing, small sightings and events.

### Co-op
Host-authoritative. Clients send intent; the host simulates ships, AI, damage and loot and replicates state. Wave time is replicated so every peer sees the same sea. Single-player is a host with AI in the empty slots; a friend joining takes over a slot.

## 5. Art and audio direction

- **Shape**: chunky, slightly exaggerated proportions; thick planks, fat masts, big hands. Low-to-mid poly with bevels, flat-ish shading, vertex colour and procedural textures.
- **Colour**: saturated turquoise shallows to deep teal, warm wood, sun-bleached canvas, strong complementary accents (flag red, lantern orange). Night is blue and readable, never black.
- **Light**: warm key, cool fill, coloured fog for depth; strong sunsets; storm green-grey.
- **Audio**: all synthesized. Layered ocean and wind beds that follow sea state and speed, hull creaks tied to roll, sail flap tied to trim, original shanties (concertina, hurdy-gurdy, drum, whistle) the crew can play, adaptive music stings for sightings and combat.
- **UI**: parchment and ink, hand-drawn icon shapes generated procedurally; HUD limited to a faint health pip and contextual prompts.

## 6. Vertical slice

One sloop on the ocean under the dynamic sky; sail from a small outpost to one treasure island and back with one AI crewmate; dig up a chest guarded by Drowned; a Drowned sloop intercepts on the way home; sell the chest. It must feel great before going wide: water and ship feel first.

## 7. Non-goals

PvP; live-service grind; realistic sailing simulation; licensed or third-party content of any kind.
