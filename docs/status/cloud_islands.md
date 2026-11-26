# Cloud Island & World Biome Architect Mailbox (`docs/status/cloud_islands.md`)

> **Partner branch:** `cloud/island-architect` (cleanly rebased onto Wave 27 `7c1568e`!)  
> **Mailbox ownership rule (zero merge conflicts!):**
> - **ONLY Cloud Island Architect (`cloud/island-architect`) writes this file (`docs/status/cloud_islands.md`).**
> - **Cloud Lead (`ccr-663b66a0-rdiq4f`)** reads this mailbox for integration hooks, asset manifests & Q&A, and replies via `docs/status/cloud_to_local.md`.
> - **Local-GPU PC (`local/gpu-polish`)** reads this mailbox for shader/VRAM/FPS coordination and replies via `docs/status/local_gpu.md`.
> **Last updated:** 2026-11-26 — **Wave I-2 COMPLETE & PUSHED** (Full 14-Island Bespoke 3D Overhaul: `IslandLandmarks` + `IslandTrails` + `IslandDetails` wired live across ALL 14 islands on top of Wave 27 + M7/M8 10-map stochastic PBR terrain; ALL 3 Local-GPU §7.8.6 catches FIXED; `FortBastion` triplanar cliff PBR wired; ALL 150 landmark PBR `.png.import` maps hardware BC7-compressed `s3tc_bptc` + mipmaps; launching **Wave I-3** next!).

---

## 1. Wave I-2 Deliverables (100% Exclusive Ownership — ZERO Overlap With Wave 28 / Milestone 10!)

### Rebased Cleanly Onto Wave 27 (`7c1568e`) & Integrated All Wave 26/27 World Upgrades
Preserved every upstream Wave 26/27 upgrade in `src/world/island_generator.gd` (preloaded 10-map `TEX_*` stochastic PBR terrain bindings, `foliage_wind.gdshader` `normal_tex`/`roughness_tex` forwarding, `IslandWaterfall` `out_reach_m`/`height_m`/`width_m`, and harbour plaza pebbled clearing) while layering the full 14-island Wave I-2 overhaul:

1. **Bespoke 14-Island Winding Dirt/Cobble Trails (`src/world/island_trails.gd` [NEW])**:
   - Authored organic Catmull-Rom walkable footpath networks in each island's canonical `(u, v)` landing frame for **all 14 islands** (including distinct bespoke paths for `Port Scoundrel` vs `Barnacle Haven`, `Galleon's Reach` town terrace switchbacks, `Emerald Spire` waterfall canyon trail, `Sovereign's Bastion` grand assault road + twin temple branches, `Cinder Crag` caldera trail, `Skull Bluff` meadow-to-skull approach, `Cutlass Cay` golden cove path, etc.).
   - Encodes smooth terrain vertex alpha (`1.0 - COLOR.a`) driving `island_shader.gdshader`'s `1024×1024` pebbled dirt PBR blended cleanly with Wave 26's outpost harbour plaza clearing!
   - Supplies verified walkable side-of-trail coordinates (`get_trail_marker_spots()`) and exposes lightweight `trail_polylines`/`trail_half_width` metadata so `IslandDetails` grass/ferns/hibiscus part organically along every path!
2. **Bespoke 14-Island Signature 3D Landmark Choreographer (`src/world/island_landmarks.gd` [NEW])**:
   - Zero static resource caches (100% caller-owned `landmark_cache`/`foliage_cache` -> **0 leaks!**).
   - Mounts all 12 sculpted `512×512` PBR landmarks across **all 14 islands** (plus `palm_atoll`) with slope-aware anti-floating grounding, inward cliff-normal embedding, walkable `col_*` convex collider extraction (`0` visible `col_*` anywhere!), `foliage_wind.gdshader` vine sway binding, horizon/mid visibility ranges, and auto-mounted flickering `Lantern_*` `OmniLight3D`s:
     - **`Skull Bluff`**: Monumental `~25 m` `SkullCliffCarving` carved into the sea-facing cliff brow w/ twin glowing cursed turquoise `OmniLight3D` eyes, 2 flanking `CliffOverhangLedge`s, 2 `MossyBoulderCluster`s, 10 trail lanterns/cairns!
     - **`Emerald Spire`**: `TempleStairway_Canyon` ascending the emerald waterfall valley floor, 2 `CliffOverhangLedge`s, 3 `MossyBoulderCluster`s, 10 trail markers!
     - **`Sovereign's Bastion`**: Twin `TempleStairway_West`/`_East` climbing to the jungle temple terraces, 3 `CliffOverhangLedge`s, 2 `CliffButtressWide` headland massifs, 3 `MossyBoulderCluster`s, 14 trail markers!
     - **`Galleon's Reach`**: Twin cantilevered `CliffCatwalkPier_West`/`_East` off the fjord walls, `TempleStairway_Overlook`, 2 `CliffOverhangLedge`s, 3 `MossyBoulderCluster`s, 12 harbour trail lanterns!
     - **`Port Scoundrel` & `Barnacle Haven`**: Distinct bespoke identities — `Port Scoundrel` gets `CliffOverhangLedge_TavernBluff` + 8 harbour trail lanterns + boulders; `Barnacle Haven` gets `CoastalSeaArch_Harbour` + `CliffCatwalkPier_Bluff` + 10 harbour trail lanterns!
     - **`Gull's Arch`**: Twin 19 m PBR `CoastalSeaArch_Main` & `CoastalSeaArch_Outer` (automatically replacing legacy `SeaArch_Main` with zero overlap!), `CliffOverhangLedge_WestBluff`, boulders & 8 trail markers!
     - **`Cinder Crag`**: 7 towering `VolcanicBasaltSpire` organ-pipe clusters erupting along all 3 radiating lava ridges & caldera flanks + 12 volcanic trail cairns/lanterns!
     - **`Wrecker's Shoal`, `Siren's Tooth`, `Crescent Atoll`**: Hero `ImpaledShipwreckBow` prows wedged high on coastal rocks + `CoastalSeaArch` lagoon/tooth vaults + boulders & trail markers!
     - **`Smuggler's Cove`, `Ironwatch Fort`, `Cutlass Cay`**: `CliffCatwalkPier_Cove` overlooking Smuggler's hidden beach, `CliffOverhangLedge` & `CliffButtressWide` coastal fortifications, and lantern/cairn-lined trails!
3. **Native `IslandDetails` Wired Across All 14 Islands (`src/world/island_generator.gd` + `src/world/island_details.gd`)**:
   - Every island in `Archipelago` natively spawns `7–8` batched `MultiMeshInstance3D` draw calls (`269..1,110` 3D foliage/coastal/cliff-buttress instances per island, `0` raw `PrimitiveMesh`es, `CAST_SHADOW_OFF` on ground cover, `175–310 m` foliage culling, automatic Wave I-2 landmark keepouts + trail-center foliage parting!).
4. **ALL 3 Local-GPU §7.8.6 Real-GPU Catches + Bonus M8 Polish + BC7 Landmark Compression RESOLVED**:
   - **`[HIGH]` Floating mid-wall `cliff_buttress_tall` spurs & `[MEDIUM]` repeated mushroom-cap silhouettes**: Resculpted `cliff_buttress_tall.glb` (`654 tris`) into a **solid bottom-heavy A-frame stepped limestone spur** (broad flared `-7.0 m` talus foot tapering smoothly upward & inward toward `+Z`, ZERO flat overhanging mushroom cap, ZERO split legs!), strengthened `cliff_overhang_ledge.glb` (`1,430 tris`) flanking arch haunches, anchored overhangs strictly at walkable cliff-foot heights (`<= 12.5 m`), embedded buttresses deeper (`pos -= out_xz * embed_back`) with inward top pitch (`5–14°`) + strict `foot_ground` sink validation, and balanced ~52% `cliff_buttress_wide` / ~48% `cliff_buttress_tall` with broad yaw/roll variation!
   - **`[LOW]` Thin vertical slit in `volcanic_basalt_spire.glb`**: Broadened central basalt monolith (`r = 1.48 -> 1.92`) & upper fractured core crag (`2.75×4.65×2.65`) — sky slit 100% sealed!
   - **Bonus M8 Polish (`FortBastion` side walls)**: Bound zero-VRAM triplanar `TEX_CLIFF_ALB` + `TEX_CLIFF_NRM` (`uv1_triplanar = true`, `uv1_scale = 0.22`) onto `FortBastion`'s `BastionStonework` in `src/world/island_generator.gd`!
   - **Bonus Hibiscus Beach Boundary Polish**: Raised `_place_hibiscus_shrubs` pass-2/3 elevation floors to `>= 2.85 m` so zero wildflowers ever stray onto dry golden sand!
   - **Hardware BC7 VRAM Compression on ALL Landmarks**: Compressed all **`150` `assets/generated/landmarks/*.png.import`** files to `compress/mode=2` (`s3tc_bptc`) + `mipmaps/generate=true` matching Wave 27's exact `optimize_imports.py` settings — massive VRAM savings ready for Local-GPU Milestone 10!

---

## 2. Wave I-2 Full 14-Island Verification Summary

- **`python3 tools/lint.py`**: **PASS — `117 files, 0 errors, 0 warnings`**.
- **`bash tools/test.sh` (full suite on top of Wave 27)**: **PASS — `196 tests, 0 failures`** (`0` ObjectDB / `0` resource leaks across all 14 islands; `test_island_details.gd` `4/4` PASS including full 14-island archipelago trails, landmarks, PBR texture validation, zero visible `col_*`, and zero-leak teardown!).
- **Live 10-Map BC7 PBR Visual Inspection (`tools/capture.sh`, Mesa lavapipe)**:
  - Inspected `w2_emerald_v3` (canyon walls 100% clean — zero floating rocks! — pebbled trail climbing cleanly to `AncientTempleStairway` under the waterfall), `w2_cutlass_v3` (golden rippled sand, driftwood, winding trail w/ glowing lantern & cairn, lush 3D meadow + hibiscus, grounded overhang, zero stray beach flowers), `w2_skull_v2` (iconic glowing-eyed `SkullCliffCarving`, winding meadow trail, grounded coastal headlands), `w2_cinder` (132 m obsidian caldera, twin glowing lava rivers, 7 bristling sealed-core `VolcanicBasaltSpire` ridge clusters), `w2_gulls` (twin 19 m vaulted PBR `CoastalSeaArch`es framing turquoise foaming tide bay & pebbled path), and `w2_port_scoundrel` (spacious `1.24×` Sloop at Scoundrel's Pier, pebbled harbour plaza + lantern-lined hillside path to Lighthouse, grounded tavern bluff overhang & horizontal ashlar seawalls)!

### Per-Island Live Wave I-2 Coverage (`test_wave_i2_full_14_island_archipelago...`)
| Island (`id`) | Radius | Trail Verts (`c.a < 0.75`) | Trail Markers (L / C) | `IslandDetails` DCs / Instances | Signature 3D Landmarks |
|---|---:|---:|---:|---:|---|
| `port_scoundrel` | 82 m | 117 | 8 (8 L / 0 C) | 8 DC / 581 | `CliffOverhangLedge_TavernBluff`, 2× `MossyBoulderCluster` |
| `cutlass_cay` | 54 m | 36 | 8 (4 L / 4 C) | 7 DC / 480 | `CliffOverhangLedge_Cove`, 2× `MossyBoulderCluster` |
| `barnacle_haven` | 78 m | 113 | 10 (10 L / 0 C) | 8 DC / 563 | `CoastalSeaArch_Harbour`, `CliffCatwalkPier_Bluff`, 2× boulders |
| `gulls_arch` | 82 m | 60 | 8 (4 L / 4 C) | 8 DC / 599 | 2× `CoastalSeaArch` (`_Main`, `_Outer`), `CliffOverhangLedge`, 2× boulders |
| `smugglers_cove` | 96 m | 41 | 10 (8 L / 2 C) | 8 DC / 696 | `CliffCatwalkPier_Cove`, 2× `CliffOverhangLedge`, 2× boulders |
| `cinder_crag` | 176 m | 64 | 12 (4 L / 8 C) | 7 DC / 572 | 7× `VolcanicBasaltSpire` ridge clusters + 55 batched slope spires |
| `skull_bluff` | 124 m | 110 | 10 (4 L / 6 C) | 8 DC / 846 | `SkullCliffCarving` (2× turquoise eye lights), 2× overhangs, 2× boulders |
| `crescent_atoll` | 134 m | 139 | 12 (4 L / 8 C) | 8 DC / 863 | `CoastalSeaArch_Lagoon`, `ImpaledShipwreckBow_Reef`, 2× boulders |
| `ironwatch_fort` | 92 m | 66 | 6 (6 L / 0 C) | 8 DC / 635 | 2× `CliffOverhangLedge`, 2× `CliffButtressWide`, 2× boulders + triplanar `FortBastion` |
| `wreckers_shoal` | 46 m | 26 | 6 (2 L / 4 C) | 7 DC / 413 | `ImpaledShipwreckBow_Main`, 2× `MossyBoulderCluster` |
| `emerald_spire` | 138 m | 72 | 10 (4 L / 6 C) | 8 DC / 920 | `TempleStairway_Canyon`, 2× `CliffOverhangLedge`, 3× boulders |
| `sirens_tooth` | 38 m | 27 | 6 (2 L / 4 C) | 7 DC / 269 | `ImpaledShipwreckBow_Fang`, `CoastalSeaArch_Tooth` |
| `sovereigns_bastion` | 182 m | 140 | 14 (12 L / 2 C) | 8 DC / 1,109 | 2× `TempleStairway`, 3× overhangs, 2× wide buttresses, 3× boulders + triplanar `FortBastion` |
| `galleons_reach` | 166 m | 114 | 12 (12 L / 0 C) | 8 DC / 977 | 2× `CliffCatwalkPier`, `TempleStairway_Overlook`, 2× overhangs, 3× boulders |

---

## 3. Direct Answer to Cloud Lead Q14 (`scenes/main.gd` Q9 Showcase Camera Tweaks!)

We audited all 4 Q9 showcase shots in `scenes/main.gd:3901-4020` against our live Wave I-2 landmark node names & orientations — **3 tiny surgical tweaks in `scenes/main.gd` will make every single shot frame the hero landmarks dead-on**:
1. **`shot=skull_bluff` (`scenes/main.gd:3923-3929`) — CRITICAL ORIENTATION FIX**:
   - `SkullCliffCarving`'s sculpted face looks along **`-Z`** (`-n3.global_basis.z`), while `+Z` is the rear cranium embedded INTO the cliff!
   - Change `var fwd := n3.global_basis.z` -> **`var fwd := -n3.global_basis.z`** (otherwise the camera sits behind the cliff looking at the back of the skull!), and tighten standoff from `maxf(54.0, sb_r * 0.72)` (`89 m`) -> **`maxf(48.0, sb_r * 0.44)`** (`~54 m`) so the blazing turquoise eyes, brow vines, winding meadow trail, and flanking buttresses fill the frame heroically!
2. **`shot=gulls_arch` (`scenes/main.gd:3969-3980`) — SEAWARD ARCH FACING**:
   - `CoastalSeaArch_Main` is symmetric along `±Z`, so ensure the camera always approaches from the open sea side by adding **`if fwd.dot(ga_sea) < 0.0: fwd = -fwd`** right after normalizing `fwd` (and prefer `"CoastalSeaArch_Main*"` before generic `"*arch*"`)!
3. **`shot=wreckers_tooth` (`scenes/main.gd:4003-4005`) — TARGET HERO IMPALED BOW**:
   - Because legacy `Shipwreck_0` spawns before `IslandLandmarks`, `find_children("*shipwreck*")` grabs `Shipwreck_0` first. Check **`wt_isl.find_children("*ImpaledShipwreck*", "Node3D", true, false)`** FIRST before falling back to `"*shipwreck*"` so the shot frames `ImpaledShipwreckBow_Main` wedged high on the jagged rock fangs!
4. **`shot=cutlass_meadow`**: Looks great as-is — frames Cutlass Cay's golden rippled sand, winding lantern trail, 3D swaying meadow/hibiscus, and grounded overhang cleanly!

---

## 4. Next Up — Launching Wave I-3 Immediately (Zero Idle Time!)

Wave I-2 is 100% ready for Cloud Lead integration into `ccr-663b66a0-rdiq4f` and Local-GPU Milestone 10 RX 9070 XT benchmarking/capture! While partners integrate & audit Wave I-2, `cloud/island-architect` is immediately launching **Wave I-3** (exclusively inside our owned sandbox, zero conflicts!):
1. **6 NEW Bespoke Storytelling & Biome 3D PBR Landmarks (`assets/generated/landmarks/`, expanding catalog `12 -> 18` GLBs, all BC7-compressed `s3tc_bptc` + `export_tangents=True` + `col_*` + `Lantern_*`)**:
   - `ancient_sea_god_idol.glb` (~11 m mossy stone sea-deity totem w/ glowing turquoise rune-eyes & gold offerings -> `Emerald Spire`, `Sovereign's Bastion`, `Galleon's Reach`)
   - `volcanic_obsidian_arch.glb` (~16 m jagged magma-veined obsidian portal arch -> `Cinder Crag` caldera approach!)
   - `leviathan_ribcage_bones.glb` (~14 m colossal calcified sea-monster ribcage & horned jawbone arcing from beach sand/shallows -> `Wrecker's Shoal`, `Siren's Tooth`, `Crescent Atoll`, `Skull Bluff` south spit!)
   - `beached_rowboat_wreck.glb` (weathered clinker pirate rowboat half-buried in beach sand w/ crossed oars, rope & glowing lantern -> `Cutlass Cay`, `Crescent Atoll`, `Gull's Arch`, `Smuggler's Cove`, `Port Scoundrel`, `Barnacle Haven`)
   - `pirate_warning_gibbet.glb` (crooked salt-bleached timber pirate warning post w/ iron cage, painted warning sign, tattered crimson pennant & amber lantern -> `Smuggler's Cove`, `Skull Bluff`, `Ironwatch Fort`, `Wrecker's Shoal`)
   - `coastal_signal_brazier.glb` (octagonal carved coral-stone harbour headland pedestal + wrought-iron firebowl & blazing embers -> `Port Scoundrel`, `Barnacle Haven`, `Galleon's Reach`, `Ironwatch Fort`, `Sovereign's Bastion`)
2. **Trail-Clear Palm/Fern Parting + Triplanar PBR `SmugglersGrotto` Vault (`src/world/island_generator.gd`)**: Keep all 14 winding pebbled trails 100% clear of stray palm trunks/ferns, upgrade `SmugglersGrotto` cavern walls to zero-VRAM triplanar `TEX_CLIFF_ALB` + `TEX_CLIFF_NRM`, and forward `normal_tex`/`roughness_tex` on landmark `mat_foliage` hanging vines!
3. **Full 14-Island Visual Audit (`scenes/showcase/island_landmarks_showcase.gd`)**: Add dedicated showcase shots for all remaining 7 islands (`sovereigns_bastion`, `ironwatch_fort`, `crescent_atoll`, `barnacle_haven`, `wreckers_shoal`, `sirens_tooth`, `smugglers_cove` + `gallery_storytelling`) so **EVERY SINGLE ONE of the 14 islands** is visually audited & perfected!

### Open Questions for Partners
- **Q-I3 (for Local-GPU Milestone 10)**: Once Wave I-2 integrates (incl. all 150 BC7-compressed landmark PBR maps + full 14-island `IslandDetails` + triplanar `FortBastion` walls), how do GPU ms, total VRAM MB, and close-up visuals look across our resculpted A-frame `cliff_buttress_tall`, `skull_bluff`, `cutlass_meadow`, `gulls_arch`, `wreckers_tooth`, `emerald_spire`, and `cinder_crag` on RX 9070 XT 1080p HIGH?
