# Contour-Loop Terrain — Polygon Layers Replace Box Volumes

**Date:** 2026-02-17
**Status:** Implemented

## Problem

The topology terrain system used box volumes + wedge slopes rasterized via `VoxelBuffer.fillWedge`. Each wedge does per-voxel `CFrame:Inverse() * Vector3` — with 3633 slopes per chunk, the first paint handler timed out. The terrain also looked boxy and artificial.

## Solution: Polygon Contour Layers + Radial Height Field

Replaced the entire volume/slope pipeline with polygon contour layers rasterized as continuous height-fields.

### Data Format

**Before:**
```
payload.mountain = [{id, position, dims, parentId, childIds}, ...]  -- box volumes
payload.slopes   = [{cframe, size}, ...]                            -- wedge slopes
```

**After:**
```
payload.features = [{
    cx, cz,                    -- feature center
    boundMinX/MaxX/MinZ/MaxZ,  -- precomputed AABB
    peakY,                     -- top of tallest layer
    layers = [{
        y, height,             -- layer base Y + height in studs
        vertices = {{x,z},...} -- closed polygon (8 vertices)
    }, ...]
}, ...]
```

### Pipeline Changes

| Node | Before | After |
|------|--------|-------|
| TopologyManager | `addVolume()` + `addSlope()` → volumes/slopes | `makeBasePolygon()` + `shrinkPolygon()` → features with polygon layers |
| ChunkManager | Volume/slope AABB filtering | Feature AABB filtering (precomputed bounds) |
| TopologyTerrainPainter | `fillBlock` × N faces + `fillWedge` × N slopes | `fillFeature` per feature (one height-field pass) |

### VoxelBuffer.fillFeature Algorithm

Three-phase approach for smooth organic terrain:

1. **Height field computation**: For each (x,z) column, compute surface height using radial distance from feature centroid, modulated by polygon shape via angular bin lookup (72 bins). Layer transitions use smoothstep interpolation. Feather zone beyond base polygon fades to ground.

2. **Height field smoothing**: 3×3 weighted average (center=4, cardinal neighbors=1). Eliminates columnar artifacts on cliff faces.

3. **Column filling**: Solid voxels below surface (occupancy=1.0), top voxel gets fractional occupancy for sub-voxel marching cubes smoothing.

### Smoothing Iterations

| Iteration | Approach | Problem |
|-----------|----------|---------|
| 1 | Per-layer polygon containment + dithered fills | Horizontal contour rings |
| 2 | Radial distance field + angular bins | Vertical ribbing at polygon vertices |
| 3 | Vertex radius interpolation | Columnar cliff faces |
| 4 | 3×3 height field smoothing | **None — smooth organic terrain** |

## Dead Code Cleanup

Removed ~140 lines of dead code from the old box/wedge system:
- `VoxelBuffer.fillWedge()`, `fillPolygonTop()`, `fillPolygonPerimeter()`, `fillPolygonShell()`
- `Canvas.fillWedge()`, `Canvas.fillCornerWedge()`
- Orphaned `WaterLabTest.lua` (failed experiment)

## Key Discoveries

- **ReadVoxels timing**: Returns stale data when called in same frame as WriteVoxels
- **Vertex ray intersection edge case**: Ray aligning with polygon vertex → both adjacent edges have near-zero cross products → fallback value. Vertex-radius interpolation avoids this.
- **Feather scaling**: `max(50, baseExtent * 0.3)` — larger features get gentler foothills

## Files Changed

- `VoxelBuffer.lua` — fillFeature rewrite, dead code removal
- `Canvas.lua` — dead wrapper removal
- `TopologyManager.lua` — polygon layer generation
- `ChunkManager.lua` — feature filtering
- `TopologyTerrainPainter.lua` — fillFeature integration
- `metadata.lua`, `init.lua` — cleanup
