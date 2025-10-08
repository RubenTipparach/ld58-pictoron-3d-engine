-- Heightmap Terrain System
-- Generates terrain geometry from a 128x128 heightmap stored as userdata

local Constants = include("src/constants.lua")
local Heightmap = {}

-- Configuration
Heightmap.MAP_SIZE = 128  -- 128x128 heightmap
Heightmap.TILE_SIZE = 4   -- Size of each terrain quad (matches current ground grid)
Heightmap.HEIGHT_SCALE = 0.5  -- How much each color index raises the terrain (0.5m per index)
Heightmap.MAX_HEIGHT = 32  -- Maximum height value (0-32 range)
Heightmap.SPRITE_INDEX = Constants.SPRITE_HEIGHTMAP  -- Heightmap data source sprite

-- Cache for height values
local height_cache = {}

-- Heightmap data - will be loaded from sprite
local heightmap_data = nil

-- Initialize heightmap by loading from sprite 256 (spritesheet 1, sprite 0)
function Heightmap.init()
	-- Get the sprite data (128x128 sprite at index 256)
	local sprite_id = type(Heightmap.SPRITE_INDEX) == "table" and Heightmap.SPRITE_INDEX[1] or Heightmap.SPRITE_INDEX
	heightmap_data = get_spr(sprite_id)

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
-- @param height_value: height in color indices (0-32, clamped)
function Heightmap.set_tile_height(tile_x, tile_z, height_value)
	if tile_x < 0 or tile_x >= Heightmap.MAP_SIZE or tile_z < 0 or tile_z >= Heightmap.MAP_SIZE then
		return
	end

	-- Clamp height to valid range
	height_value = mid(0, height_value, Heightmap.MAX_HEIGHT)

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

-- Generate terrain tiles with bounding boxes for culling
-- This creates individual tile meshes that can be culled separately
-- @param cam_x, cam_z: camera position
-- @param grid_count: number of tiles in each direction (default auto-calculated from render distance)
-- @param render_distance: how far to render terrain (optional, default 20)
-- @return tiles: array of {verts, faces, bounds={min_x, min_y, min_z, max_x, max_y, max_z}, center_x, center_z}
function Heightmap.generate_terrain_tiles(cam_x, cam_z, grid_count, render_distance)
	-- Auto-calculate grid_count based on render distance to optimize
	render_distance = render_distance or 20
	if not grid_count then
		-- Calculate grid_count to cover the render distance
		-- We want terrain that extends to the render distance
		grid_count = flr(render_distance / Heightmap.TILE_SIZE) * 2  -- *2 to cover all directions
		grid_count = min(grid_count, 32)  -- Cap at 32x32 for performance
	end

	local tiles = {}
	local half_size = grid_count * Heightmap.TILE_SIZE / 2

	-- Snap camera position to grid
	local center_x = flr(cam_x / Heightmap.TILE_SIZE) * Heightmap.TILE_SIZE
	local center_z = flr(cam_z / Heightmap.TILE_SIZE) * Heightmap.TILE_SIZE

	-- Create individual tiles (each tile is one quad = 2 triangles)
	for gz = 0, grid_count - 1 do
		for gx = 0, grid_count - 1 do
			local world_x1 = center_x + gx * Heightmap.TILE_SIZE - half_size
			local world_z1 = center_z + gz * Heightmap.TILE_SIZE - half_size
			local world_x2 = world_x1 + Heightmap.TILE_SIZE
			local world_z2 = world_z1 + Heightmap.TILE_SIZE

			-- Sample heights at 4 corners
			local h1 = Heightmap.get_height(world_x1, world_z1)
			local h2 = Heightmap.get_height(world_x2, world_z1)
			local h3 = Heightmap.get_height(world_x2, world_z2)
			local h4 = Heightmap.get_height(world_x1, world_z2)

			-- Create vertices for this tile (4 corners)
			local verts = {
				vec(world_x1, h1, world_z1),  -- v1: top-left
				vec(world_x2, h2, world_z1),  -- v2: top-right
				vec(world_x2, h3, world_z2),  -- v3: bottom-right
				vec(world_x1, h4, world_z2),  -- v4: bottom-left
			}

			-- Calculate bounding box and tile height
			local min_y = min(h1, h2, h3, h4)
			local max_y = max(h1, h2, h3, h4)
			local tile_height = max_y - min_y  -- Height of the tile (0 for flat tiles)

			local bounds = {
				min_x = world_x1,
				min_y = min_y,
				min_z = world_z1,
				max_x = world_x2,
				max_y = max_y,
				max_z = world_z2
			}

			-- Check if tile is flat
			local is_flat = (h1 == h2 and h2 == h3 and h3 == h4)

			-- Get tile coordinates for sprite selection
			local tile_x1, tile_z1 = Heightmap.world_to_tile(world_x1, world_z1)
			local tile_x2, tile_z2 = Heightmap.world_to_tile(world_x2, world_z2)

			-- Sample heightmap values for sprite selection
			local height_values = {}
			if tile_x1 >= 0 and tile_x1 < Heightmap.MAP_SIZE and tile_z1 >= 0 and tile_z1 < Heightmap.MAP_SIZE then
				add(height_values, heightmap_data[tile_z1 * Heightmap.MAP_SIZE + tile_x1])
			end
			if tile_x2 >= 0 and tile_x2 < Heightmap.MAP_SIZE and tile_z1 >= 0 and tile_z1 < Heightmap.MAP_SIZE then
				add(height_values, heightmap_data[tile_z1 * Heightmap.MAP_SIZE + tile_x2])
			end
			if tile_x2 >= 0 and tile_x2 < Heightmap.MAP_SIZE and tile_z2 >= 0 and tile_z2 < Heightmap.MAP_SIZE then
				add(height_values, heightmap_data[tile_z2 * Heightmap.MAP_SIZE + tile_x2])
			end
			if tile_x1 >= 0 and tile_x1 < Heightmap.MAP_SIZE and tile_z2 >= 0 and tile_z2 < Heightmap.MAP_SIZE then
				add(height_values, heightmap_data[tile_z2 * Heightmap.MAP_SIZE + tile_x1])
			end

			-- Determine height value for sprite selection
			local height_value = 0
			if #height_values > 0 then
				if is_flat then
					height_value = height_values[1]
				else
					height_value = height_values[1]
					for _, h in ipairs(height_values) do
						if h < height_value then
							height_value = h
						end
					end
				end
			end

			-- Determine sprite
			local is_water = (is_flat and height_value == 0)
			local sprite_id
			if is_water then
				sprite_id = Constants.SPRITE_WATER
			elseif height_value >= 10 then
				sprite_id = Constants.SPRITE_ROCKS
			elseif height_value >= 3 then
				sprite_id = Constants.SPRITE_GRASS
			else
				sprite_id = Constants.SPRITE_GROUND
			end

			-- UV coordinates with 2x2 tiling
			local uv_tl = vec(0, 0)
			local uv_tr = vec(32, 0)
			local uv_br = vec(32, 32)
			local uv_bl = vec(0, 32)

			-- Create faces (2 triangles for the quad)
			local faces = {
				{1, 2, 3, sprite_id, uv_tl, uv_tr, uv_br},
				{1, 3, 4, sprite_id, uv_tl, uv_br, uv_bl}
			}

			-- Store tile with bounding box and height
			add(tiles, {
				verts = verts,
				faces = faces,
				bounds = bounds,
				center_x = (world_x1 + world_x2) / 2,
				center_z = (world_z1 + world_z2) / 2,
				height = tile_height,  -- Height of terrain at this tile
				max_y = max_y  -- Maximum Y coordinate
			})
		end
	end

	return tiles
end

-- Legacy function for backwards compatibility - generates single mesh
-- @param cam_x, cam_z: camera position
-- @param grid_count: number of tiles in each direction
-- @param render_distance: how far to render terrain
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

			-- Get height values for all 4 corners of the quad
			local world_x1 = center_x + gx * Heightmap.TILE_SIZE - half_size
			local world_z1 = center_z + gz * Heightmap.TILE_SIZE - half_size
			local world_x2 = world_x1 + Heightmap.TILE_SIZE
			local world_z2 = world_z1 + Heightmap.TILE_SIZE

			-- Sample all 4 corners
			local tile_x1, tile_z1 = Heightmap.world_to_tile(world_x1, world_z1)
			local tile_x2, tile_z2 = Heightmap.world_to_tile(world_x2, world_z2)

			local height_values = {}
			-- Corner 1 (top-left)
			if tile_x1 >= 0 and tile_x1 < Heightmap.MAP_SIZE and tile_z1 >= 0 and tile_z1 < Heightmap.MAP_SIZE then
				add(height_values, heightmap_data[tile_z1 * Heightmap.MAP_SIZE + tile_x1])
			end
			-- Corner 2 (top-right)
			if tile_x2 >= 0 and tile_x2 < Heightmap.MAP_SIZE and tile_z1 >= 0 and tile_z1 < Heightmap.MAP_SIZE then
				add(height_values, heightmap_data[tile_z1 * Heightmap.MAP_SIZE + tile_x2])
			end
			-- Corner 3 (bottom-right)
			if tile_x2 >= 0 and tile_x2 < Heightmap.MAP_SIZE and tile_z2 >= 0 and tile_z2 < Heightmap.MAP_SIZE then
				add(height_values, heightmap_data[tile_z2 * Heightmap.MAP_SIZE + tile_x2])
			end
			-- Corner 4 (bottom-left)
			if tile_x1 >= 0 and tile_x1 < Heightmap.MAP_SIZE and tile_z2 >= 0 and tile_z2 < Heightmap.MAP_SIZE then
				add(height_values, heightmap_data[tile_z2 * Heightmap.MAP_SIZE + tile_x1])
			end

			-- For slopes, use the LOWEST height value; for flat areas, use the height value
			local height_value = 0
			if #height_values > 0 then
				if is_flat then
					-- Flat: use any height (they're all the same)
					height_value = height_values[1]
				else
					-- Slope: use minimum height for consistency
					height_value = height_values[1]
					for _, h in ipairs(height_values) do
						if h < height_value then
							height_value = h
						end
					end
				end
			end

			-- Determine if this is water (flat and height 0)
			local is_water = (is_flat and height_value == 0)

			-- Choose sprite based on height
			local sprite_id
			if is_water then
				sprite_id = Constants.SPRITE_WATER
			elseif height_value >= 10 then
				sprite_id = Constants.SPRITE_ROCKS
			elseif height_value >= 3 then
				sprite_id = Constants.SPRITE_GRASS
			else
				sprite_id = Constants.SPRITE_GROUND
			end

			-- UV coordinates using sprite size from constant (16x16 pixels)
			local sprite_size = sprite_id[2] or 16  -- Get width from sprite array
			local uv_tl = vec(0, 0)
			local uv_tr = vec(sprite_size, 0)
			local uv_br = vec(sprite_size, sprite_size)
			local uv_bl = vec(0, sprite_size)

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

return Heightmap
