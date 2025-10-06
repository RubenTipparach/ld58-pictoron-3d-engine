-- Building module: Procedural building generation with textured sides and rooftops
local Constants = include("src/constants.lua")
local Heightmap = include("src/heightmap.lua")

local Building = {}

-- Base cube vertices (8 corners) - will be scaled per building
local function make_cube_verts()
	return {
		vec(-1, -1, -1),  -- 1: bottom front-left
		vec( 1, -1, -1),  -- 2: bottom front-right
		vec( 1,  1, -1),  -- 3: top front-right
		vec(-1,  1, -1),  -- 4: top front-left
		vec(-1, -1,  1),  -- 5: bottom back-left
		vec( 1, -1,  1),  -- 6: bottom back-right
		vec( 1,  1,  1),  -- 7: top back-right
		vec(-1,  1,  1),  -- 8: top back-left
	}
end

-- Generate nine-sliced UVs for a building side
-- Nine-slicing: 1-pixel edges on left/right (columns 0 and 31) stretch horizontally
-- Middle section (columns 1-30) also stretches horizontally
-- Tiles vertically with aspect ratio matching horizontal stretch
-- Aligns to TOP of texture (clips at bottom if needed)
-- width, height: world-space dimensions of the face
-- sprite_size: size of the sprite in pixels (32x32)
-- Returns UV coordinates for the quad
local function generate_nineslice_uvs(width, height, sprite_size)
	-- Horizontal: always stretch to full sprite width (0 to sprite_size)
	-- 1-pixel edges at x=0 and x=31 stretch to building edges
	local u_min = 0
	local u_max = sprite_size

	-- Vertical: tile to match horizontal aspect ratio
	-- The texture should tile such that each segment is square in world space
	-- If width = 3 units, then each vertical tile should also be 3 units tall
	-- Number of tiles = height / width
	local tiles_v = height / width
	local v_range = sprite_size * tiles_v

	-- Align to TOP: V coordinates go from negative (bottom) to 0 (top)
	-- This ensures the top of the texture (v=0) aligns with the top of the building
	-- Any clipping happens at the bottom where v becomes negative
	local v_min = -v_range  -- Bottom of building (may be negative, clips here)
	local v_max = 0         -- Top of building (always at v=0)

	return {
		vec(u_min, v_min),  -- bottom-left
		vec(u_max, v_min),  -- bottom-right
		vec(u_max, v_max),  -- top-right
		vec(u_min, v_max)   -- top-left
	}
end

-- Create a building object
-- config: {x, z, width, depth, height, use_heightmap, side_sprite}
-- Returns: {verts, faces, x, y, z, width, height, depth}
function Building.create(config)
	local x = config.x
	local z = config.z
	local width = config.width
	local depth = config.depth
	local height = config.height
	local use_heightmap = config.use_heightmap or false
	local side_sprite = config.side_sprite or Constants.SPRITE_BUILDING_SIDE

	-- Get terrain height if heightmap is enabled
	local terrain_y = 0
	if use_heightmap then
		terrain_y = Heightmap.get_height(x, z)
	end

	-- Create scaled vertices for this building
	-- Shift vertices up so bottom is at y=0
	local base_verts = make_cube_verts()
	local verts = {}
	for _, v in ipairs(base_verts) do
		add(verts, vec(
			v.x * width,
			(v.y + 1) * height,  -- +1 to shift from [-1,1] to [0,2], then scale
			v.z * depth
		))
	end

	-- Generate faces with proper texturing
	-- Rooftop: sprite 17 (32x32)
	-- Sides: sprite 18 or 19 (32x32) - nine-sliced and tiled
	local faces = {}
	local sprite_size = 32

	-- TOP FACE (rooftop) - sprite 17
	-- Two triangles forming the top quad
	local roof_uvs = {
		vec(0, 0), vec(sprite_size, 0), vec(sprite_size, sprite_size), vec(0, sprite_size)
	}
	add(faces, {4, 3, 7, Constants.SPRITE_ROOFTOP, roof_uvs[1], roof_uvs[2], roof_uvs[3]})
	add(faces, {4, 7, 8, Constants.SPRITE_ROOFTOP, roof_uvs[1], roof_uvs[3], roof_uvs[4]})

	-- FRONT FACE (facing -Z direction) - nine-sliced
	local front_uvs = generate_nineslice_uvs(width * 2, height * 2, sprite_size)
	add(faces, {1, 2, 3, side_sprite, front_uvs[1], front_uvs[2], front_uvs[3]})
	add(faces, {1, 3, 4, side_sprite, front_uvs[1], front_uvs[3], front_uvs[4]})

	-- BACK FACE (facing +Z direction) - nine-sliced
	local back_uvs = generate_nineslice_uvs(width * 2, height * 2, sprite_size)
	add(faces, {6, 5, 8, side_sprite, back_uvs[1], back_uvs[2], back_uvs[3]})
	add(faces, {6, 8, 7, side_sprite, back_uvs[1], back_uvs[3], back_uvs[4]})

	-- LEFT FACE (facing -X direction) - nine-sliced
	local left_uvs = generate_nineslice_uvs(depth * 2, height * 2, sprite_size)
	add(faces, {5, 1, 4, side_sprite, left_uvs[1], left_uvs[2], left_uvs[3]})
	add(faces, {5, 4, 8, side_sprite, left_uvs[1], left_uvs[3], left_uvs[4]})

	-- RIGHT FACE (facing +X direction) - nine-sliced
	local right_uvs = generate_nineslice_uvs(depth * 2, height * 2, sprite_size)
	add(faces, {2, 6, 7, side_sprite, right_uvs[1], right_uvs[2], right_uvs[3]})
	add(faces, {2, 7, 3, side_sprite, right_uvs[1], right_uvs[3], right_uvs[4]})

	-- NO BOTTOM FACE (buildings don't need bottoms)

	return {
		verts = verts,
		faces = faces,
		x = x,
		y = terrain_y,
		z = z,
		width = width * 2,   -- Full width for collision
		height = height * 2, -- Full height for collision
		depth = depth * 2    -- Full depth for collision
	}
end

-- Create multiple buildings from a config array
-- configs: array of {x, z, width, depth, height}
-- use_heightmap: whether to adjust buildings to terrain height
-- Returns: array of building objects
function Building.create_city(configs, use_heightmap)
	local buildings = {}
	for _, config in ipairs(configs) do
		config.use_heightmap = use_heightmap
		add(buildings, Building.create(config))
	end
	return buildings
end

return Building
