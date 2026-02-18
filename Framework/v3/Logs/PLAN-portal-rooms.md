# Plan: Portal Rooms + Biome Blending

**Status:** Planned — not yet implemented
**Branch:** v3.0
**Depends on:** Biome system (committed 4916d73), world map (not yet built)

---

## Concept

Replace portal pads with portal rooms. Dead-end rooms on the map perimeter become teleport triggers. When a player enters a portal room, they teleport to the connected map. The room itself is the visual cue — themed with a blend of the current map's biome and the destination biome.

No separate portal geometry. No glowing pads. The room IS the portal.

---

## Key Design Decisions

### 1. Portal rooms = dead-end spur rooms only

The massing system (RoomMasser) already distinguishes main-path rooms from spur terminals. Portal rooms must be dead ends so players never need to cross through a portal to reach other areas of the current map.

**Filter:** After massing, tag spur terminal rooms as portal candidates. The orchestrator assigns each one a destination based on the world map.

### 2. Room-as-teleport-trigger

Each portal room gets a zone trigger (`cave-zone` class) sized to the room volume. Player enters → teleport fires. Same touch detection pattern as lobby pads, but room-scale.

**Consideration:** Need a brief delay or confirmation so players don't accidentally teleport. Options:
- Countdown timer (like lobby pad 10s countdown)
- Stand-on-pad-in-room confirmation (hybrid — room is themed, but activation is explicit)
- Just walk in and go (fastest, most immersive, risk of accidental)

### 3. Biome blending via orchestrator lookup

The portal room reads:
- **Base biome** — from its parent DungeonOrchestrator (the current map's biome)
- **Target biome** — from the world map connection (what map this portal leads to)

The orchestrator passes the target biome to the portal room. The room's terrain painter uses `Canvas.mixBlock` to scatter the target biome's terrain materials into the base. Example: meadow map, portal to ice — snow patches on grass floor, glacier veins in rock walls.

**No per-room config.** The orchestrator already knows its own biome. The world map tells it which biome each portal connects to. Two lookups.

### 4. Larger maps

Current: `mainPathLength = 8`, `spurCount = 4` (~12 rooms).
Portal rooms need more room to breathe. Increase map size so portal rooms feel like destinations, not immediate exits.

Suggested: `mainPathLength = 12-16`, `spurCount = 6-8`, with vertical variation. Makes dungeons feel like real places.

### 5. Vertical portal rooms

Portal rooms that go UP (to mountain/ice) or DOWN (to lava/dungeon) reinforce the world map's elevation model. The massing system already supports vertical rooms (`verticalChance`). Prioritize vertical spurs for portals where the elevation change matches the biome transition.

---

## World Map (prerequisite)

The world map is a higher-level structure that drives dungeon generation:

- Broken into **biome regions** — elevation and distance driving selection
- Desert plains at the surface, meadow as you climb, ice at peaks, dungeon/lava as you descend
- Each node in the world map = one dungeon generation
- Edges between nodes = portal connections
- When generating a dungeon, the world map provides:
  - Which biome to use
  - Which dead-end rooms connect to which neighbor nodes (and their biomes)

### Elevation model (rough)

```
Ice/Glacier ──── peaks, far reaches
Meadow/Village ─ highlands, mid-altitude
Desert ───────── plains, surface level
Dungeon/Sewer ── underground, shallow
Crystal ──────── underground, mid-depth
Lava ─────────── underground, deep
```

Walking through 100 desert maps → meadow transition → mountains → ice at the peaks.
Going down → mines → dungeon → lava the deeper you go.

---

## Biome Blend Spec

### Terrain mixing

Use `Canvas.mixBlock` (already built) on portal room volumes:

```lua
-- In portal room's terrain pass:
-- Paint base biome terrain as normal
Canvas.fillBlock(cf, sz, baseBiome.terrainWall)

-- Mix in target biome terrain (~30% coverage)
local targetWall = Enum.Material[targetBiome.terrainWall]
Canvas.mixBlock(cf, sz, targetWall, 6, 0.3)

-- Floor: scatter target floor material
local targetFloor = Enum.Material[targetBiome.terrainFloor]
Canvas.mixBlock(floorCf, floorSz, targetFloor, 8, 0.35)
```

### Part material blending

Portal room wall/floor parts could use the target biome's `partWall`/`partFloor` on a few surfaces. Or use a transitional palette that blends colors from both biomes.

### Lighting

Portal rooms could shift lighting slightly toward the target biome's values. Partial lerp between base and target lighting configs. Subtle — just enough to hint at what's ahead.

---

## Pipeline Changes Needed

1. **RoomMasser** — Tag dead-end spur rooms as `isPortal = true`
2. **DungeonOrchestrator** — Accept portal target biomes from world map, assign to portal rooms
3. **New node or orchestrator logic** — Biome blend pass for portal rooms (after normal terrain, before door cutting)
4. **Portal trigger** — Zone trigger in portal rooms, teleport on touch (with countdown or confirmation)
5. **World map system** — Graph of biome regions with edges = portal connections

---

## Room-Level Biome (Future Extension)

The style cascade is per-element. A single map could have per-room biome overrides for any room, not just portals. Border zones between biome regions. Transitional hallways. Each room is eventually its own sub-orchestrator with its own style rendering chain.

The portal room biome blend is the first step toward this. The architecture supports it — just scope the biome override to the room's terrain/part pass instead of the whole map.

---

## Open Questions

- Teleport trigger: countdown vs immediate vs pad-in-room?
- Portal room visual indicators beyond biome blend? (Archway? Particle effects? Sound?)
- Can players see into the next map through the portal room? (Expensive — would need to pre-render a slice)
- How does multiplayer work? All players in room teleport together? Individual?
- World map persistence: does the player's position in the world map save to DataStore?
