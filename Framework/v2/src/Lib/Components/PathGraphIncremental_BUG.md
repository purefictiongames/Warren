# PathGraphIncremental - Bug Documentation

## Problem Summary
Rooms overlap and segments don't connect properly. The incremental path generation with overlap resolution is not working correctly.

## Expected Behavior
1. PathGraph generates a path with segments (direction + length recipes)
2. RoomBlocker builds rooms one segment at a time
3. When Room B overlaps Room A, RoomBlocker reports overlap amount
4. PathGraph shifts ALL downstream points to clear the overlap
5. Result: No overlapping rooms, all segments connect properly

## Actual Behavior
- Rooms still overlap
- Segments don't connect to their rooms properly
- Path visualization doesn't match room positions

## The Correct Algorithm (per user)

When overlap is detected at segment A→B (going North):

1. Calculate shift amount (overlap + buffer)
2. Get FROM point's position (point A)
3. **Shift EVERY point where Z > A.z by the shift amount in +Z direction**
4. This includes:
   - Point B (the TO point)
   - All points further north
   - Points on OTHER branches that happen to be north of A
5. Re-validate the segment with new positions

### Key Insight
"It then updates EVERY point with a north point greater than itself by this new value"

This is a world-space coordinate shift, not a recipe modification. Like inserting space into the world.

## What Was Tried

### Attempt 1: Extend segment length
- Changed segment recipe length
- Recalculated positions from recipes
- **Problem**: Didn't properly cascade to all branches

### Attempt 2: Spatially-aware room sizing
- Calculated max room size based on available space
- Constrained rooms to fit
- **Problem**: Still got overlaps, rooms too small

### Attempt 3: World-space shift
- Implemented `shiftDownstreamPoints()`
- Shifts all points beyond threshold in direction
- **Problem**: Rooms not connecting, positions still wrong

## Root Cause Analysis Needed

The math should be simple:
1. Point positions are {x, y, z} coordinates
2. Segments go in 6 directions: N(+Z), S(-Z), E(+X), W(-X), U(+Y), D(-Y)
3. When shifting north: add to Z for all points where Z > threshold
4. When shifting east: add to X for all points where X > threshold
5. etc.

Something is wrong with either:
- How positions are being tracked/updated
- How the shift threshold is determined
- How the shift is applied
- The order of operations (build vs check vs shift)

## Files Involved

- `PathGraphIncremental.lua` - Path generation and shift logic
- `RoomBlockerIncremental.lua` - Room building and overlap detection
- `PathGraphIncremental_Demo.lua` - Demo wiring

## Next Steps

Start fresh conversation with clear context:
1. Read the algorithm description above
2. Implement with pencil-and-paper level simplicity
3. Add extensive logging to trace exact positions at each step
4. Test with minimal case (2-3 segments) before scaling up
