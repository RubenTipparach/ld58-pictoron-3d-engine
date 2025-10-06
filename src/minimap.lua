-- Minimap Module
-- Handles minimap rendering with terrain, buildings, and player position

local Minimap = {}

-- Configuration
Minimap.X = 406  -- Top-right corner
Minimap.Y = 10
Minimap.SIZE = 64  -- 64x64 pixels
Minimap.SCALE = 2  -- World units per pixel
Minimap.BG_COLOR = 1  -- Dark blue background

-- Minimap terrain color scheme
Minimap.TERRAIN_COLORS = {21, 5, 22, 6, 2, 24, 8, 10}  -- Heights 1-32+
Minimap.WATER_COLOR = 1  -- Height 0

-- Cached terrain texture (set externally)
local terrain_cache = nil

-- Set the terrain cache (called from main)
function Minimap.set_terrain_cache(cache)
	terrain_cache = cache
end

-- Generate a color-coded minimap visualization from heightmap
-- Samples height values and averages surrounding pixels for smooth visualization
-- @param heightmap: heightmap module reference
-- @return userdata: 128x128 u8 array with color indices
function Minimap.generate_terrain_cache(heightmap)
	-- Initialize heightmap on first call if needed
	if not heightmap then
		return nil
	end

	-- Get heightmap data
	local heightmap_data = get_spr(heightmap.SPRITE_INDEX)
	if not heightmap_data then
		return nil
	end

	-- Create output minimap texture
	local minimap = userdata("u8", heightmap.MAP_SIZE, heightmap.MAP_SIZE)

	-- Process each pixel by sampling heightmap directly
	for z = 0, heightmap.MAP_SIZE - 1 do
		for x = 0, heightmap.MAP_SIZE - 1 do
			-- Sample height value directly from heightmap (0-32)
			local idx = z * heightmap.MAP_SIZE + x
			local height_value = heightmap_data[idx]

			-- Direct height-to-color mapping
			local color
			if height_value == 0 then
				-- Height 0: water
				color = Minimap.WATER_COLOR
			else
				-- Heights 1-32: map to terrain colors array
				-- 9 colors for 32 height values = ~3.5 height units per color
				local color_idx = flr((height_value - 1) / (32 / #Minimap.TERRAIN_COLORS))
				color_idx = mid(0, color_idx, #Minimap.TERRAIN_COLORS - 1)
				color = Minimap.TERRAIN_COLORS[color_idx + 1]
			end

			-- Store color in minimap
			minimap[idx] = color
		end
	end

	return minimap
end

-- Draw the minimap
-- @param camera: camera object with x, y, z, ry
-- @param vtol: player ship with x, y, z
-- @param buildings: array of building objects
-- @param building_configs: array of building configs
-- @param landing_pad: landing pad object or array of landing pads
-- @param heightmap: heightmap module reference
-- @param position_history: array of {x, z, t} position records
-- @param cargo_objects: cargo objects to display
-- @param target_landing_pad_id: ID of landing pad to flash (optional)
function Minimap.draw(camera, vtol, buildings, building_configs, landing_pad, heightmap, position_history, cargo_objects, target_landing_pad_id)
	-- Border (black, 2 pixels thick) - moved 1 pixel left
	rectfill(Minimap.X - 2, Minimap.Y - 2, Minimap.X + Minimap.SIZE + 1, Minimap.Y + Minimap.SIZE + 1, 0)

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

	-- Check if any cargo is attached (flash target landing pad when cargo collected)
	local cargo_attached = false
	if cargo_objects then
		for cargo in all(cargo_objects) do
			if cargo.state == "attached" then
				cargo_attached = true
				break
			end
		end
	end

	-- Draw all landing pads on minimap (2x2 pixels for visibility)
	-- Support both single landing_pad (backward compat) and landing_pads array
	local pads_to_draw = {}
	if type(landing_pad) == "table" then
		if landing_pad.x then
			-- Single landing pad object
			add(pads_to_draw, landing_pad)
		else
			-- Array of landing pads
			for pad in all(landing_pad) do
				add(pads_to_draw, pad)
			end
		end
	end

	for _, pad in ipairs(pads_to_draw) do
		local pad_x = Minimap.X + Minimap.SIZE / 2 + pad.x * pixels_per_world_unit
		local pad_y = Minimap.Y + Minimap.SIZE / 2 + pad.z * pixels_per_world_unit

		-- Flash only the target landing pad when cargo is attached
		local is_target_pad = target_landing_pad_id and pad.id == target_landing_pad_id
		if cargo_attached and is_target_pad then
			-- Flash at 4Hz (faster than cargo)
			if (time() * 4) % 1 < 0.5 then
				rectfill(pad_x - 1, pad_y - 1, pad_x, pad_y, 11)  -- Cyan flash
			else
				rectfill(pad_x - 1, pad_y - 1, pad_x, pad_y, 7)   -- White
			end
		else
			-- Solid white for all other pads
			rectfill(pad_x - 1, pad_y - 1, pad_x, pad_y, 7)  -- White 2x2 pixels
		end
	end

	-- Draw cargo objects on minimap (blinking)
	if cargo_objects then
		-- Blink at 2Hz (on for 0.25s, off for 0.25s)
		if (time() * 2) % 1 < 0.5 then
			for cargo in all(cargo_objects) do
				-- Only draw if not attached to ship
				if cargo.state ~= "attached" and cargo.state ~= "delivered" then
					local cargo_minimap_x = Minimap.X + Minimap.SIZE / 2 + cargo.x * pixels_per_world_unit
					local cargo_minimap_y = Minimap.Y + Minimap.SIZE / 2 + cargo.z * pixels_per_world_unit
					-- Draw as 2x2 orange square for visibility
					rectfill(cargo_minimap_x - 1, cargo_minimap_y - 1, cargo_minimap_x, cargo_minimap_y, 9)  -- Orange
				end
			end
		end
	end

	-- Draw player position indicator (centered on landing pad, not camera)
	-- Calculate player offset from landing pad (world origin)
	local player_offset_x = vtol.x  -- vtol.x relative to origin
	local player_offset_z = vtol.z  -- vtol.z relative to origin

	local player_minimap_x = Minimap.X + Minimap.SIZE / 2 + player_offset_x * pixels_per_world_unit
	local player_minimap_y = Minimap.Y + Minimap.SIZE / 2 + player_offset_z * pixels_per_world_unit

	-- Draw player dot (always visible, 1 pixel radius)
	circfill(player_minimap_x, player_minimap_y, 1, 10)  -- Yellow dot

	-- Draw position trail (path traveled over last 5 seconds)
	if position_history and #position_history > 1 then
		-- Draw lines between consecutive positions
		for i = 1, #position_history - 1 do
			local pos1 = position_history[i]
			local pos2 = position_history[i + 1]

			-- Convert world positions to minimap coordinates
			local x1 = Minimap.X + Minimap.SIZE / 2 + pos1.x * pixels_per_world_unit
			local y1 = Minimap.Y + Minimap.SIZE / 2 + pos1.z * pixels_per_world_unit
			local x2 = Minimap.X + Minimap.SIZE / 2 + pos2.x * pixels_per_world_unit
			local y2 = Minimap.Y + Minimap.SIZE / 2 + pos2.z * pixels_per_world_unit

			-- Alternate between colors 9 (orange) and 25 (yellow-green) for faded trail effect
			local color = (i % 2 == 0) and 9 or 25
			line(x1, y1, x2, y2, color)
		end

		-- Draw line from last history position to current position
		if #position_history > 0 then
			local last_pos = position_history[#position_history]
			local last_x = Minimap.X + Minimap.SIZE / 2 + last_pos.x * pixels_per_world_unit
			local last_y = Minimap.Y + Minimap.SIZE / 2 + last_pos.z * pixels_per_world_unit
			local color = (#position_history % 2 == 0) and 9 or 25
			line(last_x, last_y, player_minimap_x, player_minimap_y, color)
		end
	end
end

return Minimap
