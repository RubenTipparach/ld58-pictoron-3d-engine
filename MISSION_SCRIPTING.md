# Mission Scripting Guide

## Coordinate System

This game uses **Aseprite coordinates** for mission scripting to make it easy to place objects visually in the heightmap editor.

### Aseprite Coordinate System
- **Origin:** Top-left corner at `(0, 0)`
- **Bounds:** Bottom-right corner at `(128, 128)`
- **Center:** `(64, 64)`

### World Coordinate System
- **Origin:** Center of the map at `(0, 0)`
- **Bounds:** `-256` to `+256` world units in both X and Z axes
- **Scale:** 1 Aseprite pixel = 4 world units (since `TILE_SIZE = 4`)
- **Units:** 1 world unit = 10 meters

### Coordinate Conversion

**Aseprite → World:**
```lua
world_x = (aseprite_x - 64) * 4
world_z = (aseprite_z - 64) * 4
```

**Examples:**
- Aseprite `(0, 0)` → World `(-256, -256)` (top-left corner)
- Aseprite `(64, 64)` → World `(0, 0)` (center)
- Aseprite `(128, 128)` → World `(256, 256)` (bottom-right corner)
- Aseprite `(43, 95)` → World `(-84, 124)`

## Existing Missions

### Mission 1: Tutorial - First Pickup
**Objective:** Pick up a single cargo package close to the landing pad and return it.

**Description:** This is a simple introductory mission designed to teach the basic mechanics. A cargo package is placed just 10 world units west of the landing pad, making it easy to find and complete.

**Features:**
- Single cargo pickup
- Dotted navigation line guides you to the cargo
- Objective box shows progress and controls
- Pause menu available (ESC key)
- Mission complete when cargo is returned to landing pad

**Implementation:** Cargo is dynamically placed 10 units west of Landing Pad 1 using coordinate conversion.

## Creating Missions

### Cargo Collection Mission

To create a cargo collection mission, use the Mission module:

```lua
local Mission = include("src/mission.lua")

-- Start a mission with cargo at specific Aseprite coordinates
Mission.start_cargo_mission({
	{aseprite_x = 43, aseprite_z = 95},
	{aseprite_x = 80, aseprite_z = 20},
	{aseprite_x = 100, aseprite_z = 110}
}, landing_pad_x, landing_pad_z)
```

### Mission Workflow

1. **Design:** Use Aseprite to view the heightmap (sprite 64, 128x128)
2. **Plan:** Note pixel coordinates where you want to place objects
3. **Script:** Add objects using Aseprite coordinates in mission code
4. **Test:** Objects will automatically convert to world coordinates and adjust to terrain height

## Mission Features

### Cargo Objects
- **Pickup Radius:** 1.5 world units (15 meters)
- **Animation:** Automatic bobbing and spinning
- **Mesh:** Loaded from `cargo.obj` (fallback cube if missing)
- **Texture:** Sprite 20 (32x32 pixels)

### Objectives
- Displayed in top-right corner
- Auto-updates as cargo is collected
- Shows "MISSION COMPLETE!" when finished

## Integration in main.lua

```lua
-- In _init() or at startup
Mission.start_cargo_mission({
	{aseprite_x = 43, aseprite_z = 95}
})

-- In _update()
Mission.update(delta_time, vtol.x, vtol.y, vtol.z)

-- In _draw() - render cargo
for cargo in all(Mission.cargo_objects) do
	if not cargo.collected then
		local cargo_faces = render_mesh(
			cargo.verts,
			cargo.faces,
			cargo.x,
			cargo.y + cargo.bob_offset,
			cargo.z,
			nil, false,
			0, cargo.rotation, 0  -- Rotation animation
		)
		-- Add to all_faces for rendering
	end
end

-- In _draw() - draw UI
Mission.draw_ui()
```

## Future Mission Types

The mission system is designed to be extensible. Future mission types could include:
- Delivery missions (pick up and deliver to specific location)
- Timed challenges
- Race checkpoints
- Escort missions
- Search and rescue

## Tips

- Use the heightmap sprite (64) in Aseprite to visualize terrain when planning
- Water is at elevation 0 (black pixels)
- Place cargo on land (non-black pixels) for better visibility
- Test coordinates in small batches before creating large missions
