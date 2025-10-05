-- Heightmap Terrain System
-- Generates terrain geometry from a 128x128 heightmap stored as userdata

local Heightmap = {}

-- Configuration
Heightmap.MAP_SIZE = 128  -- 128x128 heightmap
Heightmap.TILE_SIZE = 4   -- Size of each terrain quad (matches current ground grid)
Heightmap.HEIGHT_SCALE = 0.5  -- How much each color index raises the terrain (0.5m per index)
Heightmap.SPRITE_INDEX = 64  -- Sprite 64 = spritesheet 1, sprite 0 (64 sprites per sheet)

-- Cache for height values
local height_cache = {}

-- Heightmap data - will be loaded from sprite
local heightmap_data = nil

-- Initialize heightmap by loading from sprite 256 (spritesheet 1, sprite 0)
function Heightmap.init()
	-- Get the sprite data (128x128 sprite at index 256)
	heightmap_data = get_spr(Heightmap.SPRITE_INDEX)

	if not heightmap_data then
		-- Create a flat heightmap as fallback
		heightmap_data = userdata("u8", Heightmap.MAP_SIZE, Heightmap.MAP_SIZE)
		for i = 0, Heightmap.MAP_SIZE * Heightmap.MAP_SIZE - 1 do
			heightmap_data[i] = 0
		end
	end
end

-- Set height value at a specific tile
-- @param tile_x, tile_z: tile coordinates (0-127)
-- @param height_value: height in color indices (0-15)
function Heightmap.set_tile_height(tile_x, tile_z, height_value)
	if tile_x < 0 or tile_x >= Heightmap.MAP_SIZE or tile_z < 0 or tile_z >= Heightmap.MAP_SIZE then
		return
	end

	local pixel_index = tile_z * Heightmap.MAP_SIZE + tile_x
	heightmap_data[pixel_index] = height_value

	-- Clear cache for this tile
	local cache_key = tile_x .. "," .. tile_z
	height_cache[cache_key] = nil
end

-- Get height at a specific world position by sampling the heightmap
-- Uses bilinear interpolation for smooth slope collision
-- @param world_x, world_z: world coordinates
-- @return height value (y coordinate)
function Heightmap.get_height(world_x, world_z)
	-- Initialize on first call if needed
	if not heightmap_data then
		Heightmap.init()
	end

	-- Convert world coordinates to heightmap coordinates
	-- Center the map at (0, 0) in world space
	local half_world = (Heightmap.MAP_SIZE * Heightmap.TILE_SIZE) / 2
	local map_x_f = (world_x + half_world) / Heightmap.TILE_SIZE
	local map_z_f = (world_z + half_world) / Heightmap.TILE_SIZE

	-- Get the four surrounding heightmap pixels
	local x0 = flr(map_x_f)
	local z0 = flr(map_z_f)
	local x1 = x0 + 1
	local z1 = z0 + 1

	-- Clamp to map bounds
	if x0 < 0 or x1 >= Heightmap.MAP_SIZE or z0 < 0 or z1 >= Heightmap.MAP_SIZE then
		return 0  -- Outside map bounds = sea level
	end

	-- Get heights at four corners
	local h00 = heightmap_data[z0 * Heightmap.MAP_SIZE + x0] * Heightmap.HEIGHT_SCALE
	local h10 = heightmap_data[z0 * Heightmap.MAP_SIZE + x1] * Heightmap.HEIGHT_SCALE
	local h01 = heightmap_data[z1 * Heightmap.MAP_SIZE + x0] * Heightmap.HEIGHT_SCALE
	local h11 = heightmap_data[z1 * Heightmap.MAP_SIZE + x1] * Heightmap.HEIGHT_SCALE

	-- Calculate interpolation factors (0-1 within the pixel)
	local fx = map_x_f - x0
	local fz = map_z_f - z0

	-- Bilinear interpolation
	local h0 = h00 * (1 - fx) + h10 * fx  -- Interpolate along x at z0
	local h1 = h01 * (1 - fx) + h11 * fx  -- Interpolate along x at z1
	local height = h0 * (1 - fz) + h1 * fz  -- Interpolate along z

	return height
end

-- Generate terrain mesh for a region around the camera
-- This creates a grid of vertices with heights from the heightmap
-- @param cam_x, cam_z: camera position
-- @param grid_count: number of tiles in each direction (default auto-calculated from render distance)
-- @param render_distance: how far to render terrain (optional, default 20)
-- @return verts, faces: vertex and face arrays
function Heightmap.generate_terrain(cam_x, cam_z, grid_count, render_distance)
	-- Auto-calculate grid_count based on render distance to optimize
	render_distance = render_distance or 20
	if not grid_count then
		-- Calculate grid_count to cover the render distance
		-- We want terrain that extends to the render distance
		grid_count = flr(render_distance / Heightmap.TILE_SIZE) * 2  -- *2 to cover all directions
		grid_count = min(grid_count, 32)  -- Cap at 32x32 for performance
	end

	local verts = {}
	local faces = {}

	local half_size = grid_count * Heightmap.TILE_SIZE / 2

	-- Snap camera position to grid
	local center_x = flr(cam_x / Heightmap.TILE_SIZE) * Heightmap.TILE_SIZE
	local center_z = flr(cam_z / Heightmap.TILE_SIZE) * Heightmap.TILE_SIZE

	-- Create vertices for a (grid_count+1) x (grid_count+1) grid
	-- We need grid_count+1 vertices to make grid_count quads
	for gz = 0, grid_count do
		for gx = 0, grid_count do
			local world_x = center_x + gx * Heightmap.TILE_SIZE - half_size
			local world_z = center_z + gz * Heightmap.TILE_SIZE - half_size

			-- Sample height from heightmap
			local height = Heightmap.get_height(world_x, world_z)

			add(verts, vec(world_x, height, world_z))
		end
	end

	-- Create quads (2 triangles each) with tiled UVs
	-- Simple version without merging for now
	for gz = 0, grid_count - 1 do
		for gx = 0, grid_count - 1 do
			-- Calculate vertex indices (grid_count+1 vertices per row)
			local v1 = gz * (grid_count + 1) + gx + 1
			local v2 = gz * (grid_count + 1) + gx + 2
			local v3 = (gz + 1) * (grid_count + 1) + gx + 2
			local v4 = (gz + 1) * (grid_count + 1) + gx + 1

			-- Determine sprite: use SPRITE_WATER (12) if flat and height is 0, otherwise SPRITE_GROUND (2)
			-- Get heights of all 4 vertices to check if flat
			local h1 = verts[v1].y
			local h2 = verts[v2].y
			local h3 = verts[v3].y
			local h4 = verts[v4].y

			-- Check if quad is flat (all vertices at same height)
			local is_flat = (h1 == h2 and h2 == h3 and h3 == h4)

			-- Get height value from heightmap at quad center
			local world_x = center_x + gx * Heightmap.TILE_SIZE - half_size + Heightmap.TILE_SIZE / 2
			local world_z = center_z + gz * Heightmap.TILE_SIZE - half_size + Heightmap.TILE_SIZE / 2
			local tile_x, tile_z = Heightmap.world_to_tile(world_x, world_z)
			local height_value = 0
			if tile_x >= 0 and tile_x < Heightmap.MAP_SIZE and tile_z >= 0 and tile_z < Heightmap.MAP_SIZE then
				local pixel_index = tile_z * Heightmap.MAP_SIZE + tile_x
				height_value = heightmap_data[pixel_index]
			end

			-- Water only on flat surfaces at height 0, otherwise ground texture
			local sprite_id = (is_flat and height_value == 0) and 12 or 2

			-- UV coordinates with 4x4 tiling (64x64 pixels = 4 tiles of 16x16)
			local uv_tl = vec(0, 0)
			local uv_tr = vec(64, 0)
			local uv_br = vec(64, 64)
			local uv_bl = vec(0, 64)

			-- First triangle (v1, v2, v3)
			add(faces, {v1, v2, v3, sprite_id, uv_tl, uv_tr, uv_br})
			-- Second triangle (v1, v3, v4)
			add(faces, {v1, v3, v4, sprite_id, uv_tl, uv_br, uv_bl})
		end
	end

	return verts, faces
end

-- Clear the height cache (call this if heightmap changes)
function Heightmap.clear_cache()
	height_cache = {}
end

-- Get the height at a specific tile coordinate (for placing objects)
-- @param tile_x, tile_z: tile coordinates (0-127)
-- @return height value
function Heightmap.get_tile_height(tile_x, tile_z)
	-- Initialize on first call if needed
	if not heightmap_data then
		Heightmap.init()
	end

	if tile_x < 0 or tile_x >= Heightmap.MAP_SIZE or tile_z < 0 or tile_z >= Heightmap.MAP_SIZE then
		return 0
	end

	local pixel_index = tile_z * Heightmap.MAP_SIZE + tile_x
	local color_index = heightmap_data[pixel_index]
	return color_index * Heightmap.HEIGHT_SCALE
end

-- Convert world coordinates to tile coordinates
-- @param world_x, world_z: world coordinates
-- @return tile_x, tile_z: tile coordinates
function Heightmap.world_to_tile(world_x, world_z)
	local half_world = (Heightmap.MAP_SIZE * Heightmap.TILE_SIZE) / 2
	local tile_x = flr((world_x + half_world) / Heightmap.TILE_SIZE)
	local tile_z = flr((world_z + half_world) / Heightmap.TILE_SIZE)
	return tile_x, tile_z
end

-- Convert tile coordinates to world coordinates (center of tile)
-- @param tile_x, tile_z: tile coordinates
-- @return world_x, world_z: world coordinates
function Heightmap.tile_to_world(tile_x, tile_z)
	local half_world = (Heightmap.MAP_SIZE * Heightmap.TILE_SIZE) / 2
	local world_x = tile_x * Heightmap.TILE_SIZE - half_world + Heightmap.TILE_SIZE / 2
	local world_z = tile_z * Heightmap.TILE_SIZE - half_world + Heightmap.TILE_SIZE / 2
	return world_x, world_z
end

-- Generate a color-coded minimap visualization
-- Samples height values and averages surrounding pixels for smooth visualization
-- @return userdata: 128x128 u8 array with color indices
function Heightmap.generate_minimap()
	-- Initialize on first call if needed
	if not heightmap_data then
		Heightmap.init()
	end

	-- Create output minimap texture
	local minimap = userdata("u8", Heightmap.MAP_SIZE, Heightmap.MAP_SIZE)

	-- Find min and max height values in the entire map for normalization
	local min_height = 999999
	local max_height = -999999
	for z = 0, Heightmap.MAP_SIZE - 1 do
		for x = 0, Heightmap.MAP_SIZE - 1 do
			local idx = z * Heightmap.MAP_SIZE + x
			local color_idx = heightmap_data[idx]
			local height = color_idx * Heightmap.HEIGHT_SCALE
			min_height = min(min_height, height)
			max_height = max(max_height, height)
		end
	end

	-- Avoid division by zero
	local height_range = max_height - min_height
	if height_range == 0 then
		height_range = 1
	end

	-- Minimap terrain color scheme
	-- IMPORTANT: Colors 21, 5, 22, 6, 7 are RESERVED for terrain only on the minimap
	-- Do not use these colors for buildings, trees, or other minimap elements
	-- Normalized based on tallest feature in the map
	local terrain_colors = {21, 5, 22, 6, 7}  -- Low to high elevation

	-- Process each pixel with 3x3 averaging for smooth visualization
	for z = 0, Heightmap.MAP_SIZE - 1 do
		for x = 0, Heightmap.MAP_SIZE - 1 do
			-- Sample height with 3x3 kernel averaging
			local height_sum = 0
			local sample_count = 0

			for dz = -1, 1 do
				for dx = -1, 1 do
					local sx = x + dx
					local sz = z + dz

					-- Bounds check
					if sx >= 0 and sx < Heightmap.MAP_SIZE and
					   sz >= 0 and sz < Heightmap.MAP_SIZE then
						local idx = sz * Heightmap.MAP_SIZE + sx
						local color_idx = heightmap_data[idx]
						local height = color_idx * Heightmap.HEIGHT_SCALE
						height_sum = height_sum + height
						sample_count = sample_count + 1
					end
				end
			end

			-- Calculate average height
			local avg_height = height_sum / sample_count

			-- Normalize height to 0-1 range based on actual map min/max
			local normalized_height = (avg_height - min_height) / height_range

			-- Map normalized height to color index (0-4 maps to 5 colors)
			local color_idx = flr(normalized_height * (#terrain_colors - 0.001))  -- -0.001 prevents overflow
			color_idx = mid(0, color_idx, #terrain_colors - 1)  -- Clamp to valid range
			local color = terrain_colors[color_idx + 1]  -- +1 because Lua arrays start at 1

			-- Store color in minimap
			minimap[z * Heightmap.MAP_SIZE + x] = color
		end
	end

	return minimap
end

-- Don't auto-initialize - let it load on first use
-- This allows the sprite system to be ready first

return Heightmap
