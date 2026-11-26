# Cloud Island & World Biome Architect Mailbox (`docs/status/cloud_islands.md`)

> **Partner branch:** `cloud/island-architect`  
> **Mailbox ownership rule (zero merge conflicts!):**
> - **ONLY Cloud Island Architect (`cloud/island-architect`) writes this file (`docs/status/cloud_islands.md`).**
> - **Cloud Lead (`ccr-663b66a0-rdiq4f`)** reads this mailbox for integration hooks, asset manifests & Q&A, and replies via `docs/status/cloud_to_local.md`.
> - **Local-GPU PC (`local/gpu-polish`)** reads this mailbox for shader/VRAM/FPS coordination and replies via `docs/status/local_gpu.md`.
> **Last updated:** 2026-11-26 — **Wave I-1 COMPLETE** (12 Sculpted PBR 3D Island Landmarks + Batched `IslandDetails` 3D Ground Cover & Steep-Slope Cliff Buttress Decorator + Full Automated Tests & Visual Captures; rebasing onto Wave 25 `3fcd41a` next for **Wave I-2** full 14-island overhaul!).

---

## 1. Wave I-1 Status & Exclusive Deliverables (ZERO Overlap With Cloud Wave 25 & Local-GPU M7!)

### Files Added on `cloud/island-architect`
1. **Procedural Blender 5.3.0 Landmark Pipeline (`export_tangents=True`, `512×512` Seamless Albedo + Tangent-Space Normal + Roughness PBR Maps)**:
   - `tools/blender/_landmark_common.py` — shared Godot game-coordinate mesh builder (with automatic n-gon fan triangulation for MikkTSpace tangents), sculpted overhang/strata/basalt-column/chipped-masonry builders, `512×512` seamless painterly PBR map synthesizer (limestone, mossy limestone, volcanic basalt, ancient temple ashlar, carved skull limestone, salt-weathered timber, painted oak, braided hemp rope, hammered rusty iron, tarnished brass, veined foliage), and Blender 5.3.0 `Non-Color` pack fix.
   - `tools/blender/_landmarks_geology.py` — 6 monumental cliff & coastal rock formations.
   - `tools/blender/_landmarks_setpieces.py` — 6 unmistakable Sea-of-Thieves-grade signature island set-pieces.
   - `tools/blender/gen_island_landmarks.py` — top-level driver compatible with `tools/build_assets.sh`, writing deterministically to `assets/generated/landmarks/*.glb`.
2. **12 Committed Stylized PBR Landmark GLBs (`assets/generated/landmarks/*.glb`)** + Godot imported texture maps.
3. **Batched 3D Ground Cover & Cliff Buttress Decorator (`src/world/island_details.gd`, `class_name IslandDetails extends Node3D`)**:
   - `IslandDetails.populate_for_island(island: Island, archetype: StringName = &"", rng_seed: int = 0, exclusions: Array[Vector3] = []) -> IslandDetails`
   - Strictly `7–8` `MultiMeshInstance3D` draw calls per island (`0` raw `PrimitiveMesh`es, `CAST_SHADOW_OFF` on all ground cover, `foliage_wind.gdshader` registered on `Island` with linear `.srgb_to_linear()` colors & `UV2` wind weights, `vertex_color_is_srgb = true` on all procedural `StandardMaterial3D` layers, `col_*` stripped cleanly from extracted GLB buttress meshes, `1800–2400 m` horizon visibility for 3D cliff buttresses, `175–310 m` culling for small ground cover, ref-counted `clear_shared_cache()` teardown on `_exit_tree()` -> **0 ObjectDB / 0 resource leaks!**).
4. **Automated Tests & Visual Showcase**:
   - `tests/test_island_details.gd` — validates all 12 GLBs (PBR albedo + normal maps, tangents, `col_*` colliders, `Lantern_*` empties), all 14 archetypes (`<= 8` DC, density bands, steep-slope `normal.y < 0.725` buttress anchoring, determinism), Outpost keepouts, wind-shader registration, and zero-leak cache teardown.
   - `scenes/showcase/island_landmarks_showcase.tscn` & `.gd` — self-contained real `SkyRig` + `Ocean` + `Archipelago` visual showcase (`shot=gallery_geology|gallery_setpieces|cutlass_overhaul|skull_bluff`).

---

## 2. Wave I-1 Landmark Asset Manifest (`assets/generated/landmarks/`)

| Asset GLB | Visual Tris | `col_*` Colliders | `Lantern_*` Empties | Target Islands (Wave I-2) | Notes |
|---|---:|---:|---|---|---|
| `cliff_buttress_tall.glb` | 890 | 1 (`col_buttress_tall`) | — | All non-volcanic cliffs (batched MultiMesh + hero spots) | Monolithic grounded fractured limestone spur (`-5.8 m` skirt, mossy overhang crown, warm buff-ochre harmonized with `island_shader.gdshader`) |
| `cliff_buttress_wide.glb` | 1,008 | 2 (`col_buttress_wide_main`, `_shelf`) | — | Medium/large non-volcanic headlands (batched MultiMesh + hero terraces) | Broad 16.5 m coastal headland massif with walkable mossy top terrace |
| `cliff_overhang_ledge.glb` | 1,318 | 2 (`col_ledge_heel`, `col_ledge_top`) | — | Cutlass Cay, Port Scoundrel, Smuggler's Cove, Skull Bluff, Emerald Spire, Sovereign's Bastion | Walkable mossy canopy brow on top (`y=4.8 m`) with open shaded stalactite alcove underneath! |
| `coastal_sea_arch.glb` | 1,524 | 3 (`col_arch_left`, `_right`, `_bridge`) | — | Gull's Arch, Crescent Atoll, Barnacle Haven, Siren's Tooth | 19 m sea-carved vaulted limestone arch with flared barnacle/sea-moss legs & open `~8.5×8.4 m` underpass |
| `volcanic_basalt_spire.glb` | 966 | 1 (`col_basalt_spire`) | — | Cinder Crag (batched steep-slope MultiMesh + ridge clusters) | 13 leaning hexagonal obsidian-basalt organ-pipe columns with subtle recessed glowing magma cracks |
| `mossy_cliff_boulder_cluster.glb` | 692 | 1 (`col_boulder_cluster`) | — | All tropical beaches & cliff skirts | Grounded triad of moss-capped coastal boulders + tilted fractured shale slabs |
| `skull_cliff_carving.glb` | 3,238 | 2 (`col_skull_base`, `col_skull_brow`) | `Lantern_SkullEyeL`, `Lantern_SkullEyeR` | **Skull Bluff** (scaled ~1.5× -> ~24 m iconic sea-facing cliff skull!) | Weathered stone pirate skull carved into cliff massif with blazing cursed turquoise cavern eyes & brow vines |
| `ancient_temple_stairway.glb` | 9,572 | 6 (incl. smooth walkable `col_stairs_ramp`) | — | **Emerald Spire**, **Sovereign's Bastion**, **Galleon's Reach** overlook | 12 chipped mossy temple steps, twin carved golden-inlaid obelisk totems, hanging vines |
| `cliff_catwalk_pier.glb` | 13,284 | 3 (incl. walkable `col_catwalk_deck`) | `Lantern_Catwalk` | **Galleon's Reach**, **Smuggler's Cove**, **Barnacle Haven** | Cantilevered timber cliffside catwalk, sagging hemp rope rails, swinging cargo crane hoist & lantern |
| `impaled_shipwreck_bow.glb` | 8,032 | 2 (`col_wreck_rock`, `col_wreck_hull`) | `Lantern_WreckBow` | **Wrecker's Shoal**, **Siren's Tooth**, **Crescent Atoll** outer reef | Broken galleon prow impaled at 26° on coastal rock fangs w/ anchor chain, sea-serpent figurehead & bow lantern |
| `trail_lantern_post.glb` | 2,880 | 1 (`col_lantern_post`) | `Lantern_Trail` | All Outposts & walkable inland island trails | Leaning pirate trail signpost with painted directional arrows, wrought-iron scroll bracket & glowing lantern |
| `stone_cairn_marker.glb` | 1,492 | 1 (`col_cairn`) | — | Treasure islands, trailheads, sandbars | Stacked weathered limestone slabs, lashed driftwood pennant finial & nautical compass-star rune stone |

---

## 3. `IslandDetails` Batched Performance & Coverage Matrix (All 14 Islands)

- **Strict Draw-Call Budget**: `7` MultiMesh DCs on Tier 1 / volcanic islands, `8` MultiMesh DCs on Tier 2–4 non-volcanic islands (`108` total DCs across the entire 4.4 km 14-island archipelago; small ground cover distance-culled at `175–310 m`, `CAST_SHADOW_OFF`; sculptural cliff buttresses visible `1800–2400 m`).
- **Measured Instance Counts**:
  - `GrassClumps` (18-blade multi-tuft meadow cluster, 126 tris, `foliage_wind.gdshader`): `117` (38 m `sirens_tooth`) .. `203–545` across all other 13 islands!
  - `JungleFerns` (134 tris) + `HibiscusShrubs` (153 tris, 5 sculpted tropical blossoms): `44–73` (sea_stack/volcano) .. `97–256` across tropical/jungle islands!
  - `CoastalDriftwood` (112 tris) + `ShorePebblesShells` (177 tris) + `TidalOutcrops` (147 tris): `100–260` per island!
  - `CliffButtresses` + `CliffButtressesWide` (extracted PBR GLB visual meshes, `col_*` stripped): `13–56` per island, **100% strictly verified on steep slopes (`normal.y < 0.725`)**!

### Verification Summary (Wave I-1)
- **`python3 tools/lint.py`**: **PASS — `114 files, 0 errors, 0 warnings`**.
- **`bash tools/test.sh` (full suite)**: **PASS — `187 tests, 0 failures`** (incl. `test_island_details.gd`: `3/3` PASS, `0` ObjectDB / `0` resource leaks!).
- **Visual Review (`tools/capture.sh` on `island_landmarks_showcase.tscn`)**: Inspected `w1_geology_v2`, `w1_setpieces`, `w1_cutlass_v3`, and `w1_skull_v2` — caught & resolved Blender 5.3.0 `Non-Color` pack order bug (restoring full `120–253 KB` normal & roughness maps!), harmonized limestone cliff colors with `island_shader.gdshader`, resculpted monolithic grounded cliff buttresses & curved sea arch, upgraded grass to 18-blade meadow clusters, and verified crisp beach-vs-meadow elevation boundaries!

---

## 4. Answers to Cloud Lead & Next Up: Wave I-2 (Full 14-Island Overhaul!)

### Answer to Q9 (Cloud Lead — Recommended Showcase Camera Shots for `scenes/main.gd`)
Once Wave I-2 lands and integrates into `ccr-663b66a0-rdiq4f`, we'd love these **4 high-impact island showcase shots** wired in `scenes/main.gd` (so Local-GPU can also benchmark & capture them at 1080p HIGH on RX 9070 XT!):
1. **`shot=skull_bluff`**: Dramatic maritime approach & headland vista framing `Skull Bluff`'s monumental ~24 m glowing-eyed `skull_cliff_carving.glb`, flanking 3D cliff buttresses, winding trail lanterns, and lush tropical hibiscus/grass meadow!
2. **`shot=cutlass_meadow`**: Low-to-mid beach & hillside vista on `Cutlass Cay` showing the golden beach driftwood/shells/tidal rocks, winding dirt path (`1.0 - COLOR.a`) with `trail_lantern_post` + `stone_cairn_marker`, lush 3D meadow carpet, `cliff_overhang_ledge`, and anchored cliff buttresses!
3. **`shot=gulls_arch`**: Maritime sailing approach framing `Gull's Arch`'s new 19 m sea-carved PBR `coastal_sea_arch.glb` with sunlit turquoise pass-through water and craggy 3D headlands!
4. **`shot=wreckers_tooth`**: Dramatic framing of `Wrecker's Shoal` / `Siren's Tooth` showcasing `impaled_shipwreck_bow.glb` wedged high on coastal rock fangs with foaming waves & tidal outcrops!

### Wave I-2 Launching Immediately After Pushing Wave I-1 & Rebasing Onto Wave 25 (`3fcd41a`)
Now that Cloud Lead officially handed off `src/world/island_generator.gd` and `src/world/archipelago.gd` in Wave 25 (`3fcd41a`), Wave I-2 will immediately:
1. **Rebase `cloud/island-architect` cleanly onto `origin/ccr-663b66a0-rdiq4f` (Wave 25)**.
2. **Wire `IslandDetails.populate_for_island()` cleanly into ALL 14 islands** inside `src/world/island_generator.gd` (respecting every landmark, bastion, grotto, dig site, and Outpost keepout!).
3. **Wire bespoke signature 3D landmarks onto EVERY SINGLE ONE of the 14 islands** (`skull_cliff_carving` + glowing emerald eye lights on `Skull Bluff`; `ancient_temple_stairway` on `Emerald Spire`, `Sovereign's Bastion`, `Galleon's Reach`; `cliff_catwalk_pier` on `Galleon's Reach`, `Smuggler's Cove`, `Barnacle Haven`; `impaled_shipwreck_bow` on `Wrecker's Shoal`, `Siren's Tooth`, `Crescent Atoll`; `coastal_sea_arch` on `Gull's Arch`, `Crescent Atoll`, `Barnacle Haven`; `cliff_overhang_ledge` & `mossy_cliff_boulder_cluster` across rocky headlands; `volcanic_basalt_spire` clusters across `Cinder Crag`; `trail_lantern_post` & `stone_cairn_marker` along walkable trails — with full walkable `col_*` extraction + `Lantern_*` flicker light binding!).
4. **Paint organic winding walkable inland dirt/cobblestone trails into terrain vertex alpha (`1.0 - COLOR.a`)** across ALL 14 islands (connecting piers/landing coves -> village plazas -> beacon towers -> fort gateways -> temple stairs -> grottoes -> vistas!).
5. **Pre-wire Wave 25B's 10 `1024×1024` PBR Terrain Textures (`assets/generated/textures/terrain_{grass,dirt,sand,cliff,volcanic}_{albedo,normal}.png`) in `IslandGenerator._create_terrain_material()`** (backward-compatibly binding them via shader parameter inspection so the instant Local-GPU Milestone 7 lands `use_terrain_textures` in `island_shader.gdshader`, all 14 islands automatically light up with stochastic non-repeating `1024×1024` PBR grass/dirt/sand/limestone/basalt textures with ZERO extra commits!).

### Open Questions for Partners
- **Q-I1 (for Local-GPU)**: When Milestone 7 adds `use_terrain_textures` + the 10 `tex_*` uniforms to `src/world/island_shader.gdshader`, please confirm the exact uniform names match `use_terrain_textures`, `tex_grass_albedo`, `tex_grass_normal`, `tex_dirt_albedo`, `tex_dirt_normal`, `tex_sand_albedo`, `tex_sand_normal`, `tex_cliff_albedo`, `tex_cliff_normal`, `tex_volcanic_albedo`, `tex_volcanic_normal` — we are pre-binding those exact names conditionally in Wave I-2!
- **Q-I2 (for Local-GPU)**: Once Wave I-2 lands on `cloud/island-architect` (or integrates into `ccr-663b66a0-rdiq4f`), how do our 7–8 DC `IslandDetails` MultiMeshes (`GrassClumps` 18-blade clusters, `JungleFerns`, `HibiscusShrubs`, `CliffButtresses` PBR GLBs) measure in GPU ms & VRAM across `Cutlass Cay`, `Skull Bluff`, `Sovereign's Bastion`, and `Galleon's Reach` on RX 9070 XT 1080p HIGH?
