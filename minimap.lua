-- Minimap Module
-- Handles minimap rendering with terrain, buildings, and player position

local Minimap = {}

-- Configuration
Minimap.X = 406  -- Top-right corner
Minimap.Y = 10
Minimap.SIZE = 64  -- 64x64 pixels
Minimap.SCALE = 2  -- World units per pixel
Minimap.BG_COLOR = 1  -- Dark blue background

-- Cached terrain texture (set externally)
local terrain_cache = nil

-- Set the terrain cache (called from main)
function Minimap.set_terrain_cache(cache)
	terrain_cache = cache
end

-- Draw the minimap
-- @param camera: camera object with x, y, z, ry
-- @param vtol: player ship with x, y, z
-- @param buildings: array of building objects
-- @param building_configs: array of building configs
-- @param landing_pad: landing pad object
-- @param heightmap: heightmap module reference
function Minimap.draw(camera, vtol, buildings, building_configs, landing_pad, heightmap)
	-- Border (black, 2 pixels thick)
	rectfill(Minimap.X - 2, Minimap.Y - 2, Minimap.X + Minimap.SIZE + 2, Minimap.Y + Minimap.SIZE + 2, 0)

	-- Draw color-coded minimap from cached terrain visualization
	if terrain_cache then
		-- Draw from cached color-coded minimap (128x128)
		for py = 0, Minimap.SIZE - 1 do
			for px = 0, Minimap.SIZE - 1 do
				-- Sample from cache (scale 64px minimap from 128x128 cache)
				local cache_x = flr(px * 2)
				local cache_z = flr(py * 2)
				local cache_idx = cache_z * heightmap.MAP_SIZE + cache_x
				local color = terrain_cache[cache_idx]
				pset(Minimap.X + px, Minimap.Y + py, color)
			end
		end
	else
		-- Fallback: solid background
		rectfill(Minimap.X, Minimap.Y, Minimap.X + Minimap.SIZE, Minimap.Y + Minimap.SIZE, Minimap.BG_COLOR)
	end

	-- Map world offset to minimap pixels helper
	-- Map world units are 4 units per sprite pixel (TILE_SIZE = 4)
	-- Sprite is 128x128, minimap is 64x64 (scale 0.5)
	-- So: 1 sprite pixel = 4 world units = 0.5 minimap pixels
	local pixels_per_world_unit = (Minimap.SIZE / 128.0) / heightmap.TILE_SIZE

	-- Draw buildings on minimap
	for i, building in ipairs(buildings) do
		local config = building_configs[i]
		if config then
			-- Convert world position to minimap position
			local bx = Minimap.X + Minimap.SIZE / 2 + building.x * pixels_per_world_unit
			local by = Minimap.Y + Minimap.SIZE / 2 + building.z * pixels_per_world_unit

			-- Draw building as 1 pixel (not using reserved terrain colors)
			pset(bx, by, 12)  -- Light blue
		end
	end

	-- Draw landing pad on minimap (1 pixel like buildings)
	local pad_x = Minimap.X + Minimap.SIZE / 2 + landing_pad.x * pixels_per_world_unit
	local pad_y = Minimap.Y + Minimap.SIZE / 2 + landing_pad.z * pixels_per_world_unit
	pset(pad_x, pad_y, 11)  -- Green 1 pixel

	-- Draw player position indicator (centered on landing pad, not camera)
	-- Calculate player offset from landing pad (world origin)
	local player_offset_x = vtol.x  -- vtol.x relative to origin
	local player_offset_z = vtol.z  -- vtol.z relative to origin

	local player_minimap_x = Minimap.X + Minimap.SIZE / 2 + player_offset_x * pixels_per_world_unit
	local player_minimap_y = Minimap.Y + Minimap.SIZE / 2 + player_offset_z * pixels_per_world_unit

	-- Draw player dot (always visible, 1 pixel radius)
	circfill(player_minimap_x, player_minimap_y, 1, 10)  -- Yellow dot

	-- Draw direction arrow showing camera facing
	local arrow_length = 6
	local arrow_angle = camera.ry  -- Camera yaw rotation

	-- Calculate arrow endpoint from ship position in opposite camera direction
	local arrow_dx = sin(arrow_angle) * arrow_length
	local arrow_dz = -cos(arrow_angle) * arrow_length

	-- Draw arrow line from ship dot pointing in camera direction
	line(player_minimap_x, player_minimap_y,
	     player_minimap_x + arrow_dx, player_minimap_y + arrow_dz, 10)
end

return Minimap
