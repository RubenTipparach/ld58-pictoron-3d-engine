-- Landing Pad System
-- Manages landing pad placement and spawn points

local LandingPads = {}

-- Import heightmap for automatic height adjustment
local Heightmap = include("src/heightmap.lua")
local Collision = include("src/engine/collision.lua")
local Constants = include("src/constants.lua")

-- List of all landing pads in the world
LandingPads.pads = {}

-- Create a new landing pad
-- @param config: {id, name, x, z, mesh, scale, sprite, collision_dims, collision_y_offset}
-- @return landing pad object
function LandingPads.create_pad(config)
	local id = config.id or (#LandingPads.pads + 1)
	local name = config.name or "Landing Pad " .. id
	local x = config.x or 0
	local z = config.z or 0
	local mesh = config.mesh
	local scale = config.scale or 1.0
	local sprite = config.sprite
	local collision_dims = config.collision_dims or {width = 2, height = 1.5, depth = 3}
	local collision_y_offset = config.collision_y_offset or 0

	-- Scale mesh vertices
	local scaled_verts = {}
	for _, v in ipairs(mesh.verts) do
		add(scaled_verts, vec(v.x * scale, v.y * scale, v.z * scale))
	end

	-- Get terrain height at this position
	local terrain_height = 0
	if Heightmap then
		terrain_height = Heightmap.get_height(x, z)
	end

	-- Calculate spawn position (centered on pad, above it)
	-- Mesh bottom is at y=0, so spawn slightly above scaled mesh height
	local spawn_y = terrain_height + (collision_dims.height or 1.5) + 0.5  -- 0.5 units above pad

	-- Create collision object
	local collision = Collision.create_box(
		x,
		terrain_height,
		z,
		collision_dims.width * scale,
		collision_dims.height,
		collision_dims.depth * scale,
		collision_y_offset
	)

	local pad = {
		id = id,
		name = name,
		x = x,
		y = terrain_height,  -- Place on terrain
		z = z,
		verts = scaled_verts,
		faces = mesh.faces,
		sprite_override = sprite,
		width = collision_dims.width * scale,
		height = collision_dims.height,
		depth = collision_dims.depth * scale,
		collision = collision,  -- Collision object

		-- Spawn point for ship
		spawn = {
			x = x,
			y = spawn_y,
			z = z,
			yaw = 0  -- Default facing direction
		}
	}

	add(LandingPads.pads, pad)
	return pad
end

-- Get a landing pad by ID
-- @param id: landing pad ID
-- @return landing pad object or nil
function LandingPads.get_pad(id)
	for _, pad in ipairs(LandingPads.pads) do
		if pad.id == id then
			return pad
		end
	end
	return nil
end

-- Get spawn position for a landing pad
-- @param id: landing pad ID
-- @return x, y, z, yaw or nil if not found
function LandingPads.get_spawn(id)
	local pad = LandingPads.get_pad(id)
	if pad and pad.spawn then
		return pad.spawn.x, pad.spawn.y, pad.spawn.z, pad.spawn.yaw
	end
	return nil
end

-- Clear all landing pads
function LandingPads.clear()
	LandingPads.pads = {}
end

-- Get all landing pads (for rendering)
-- @return array of landing pad objects
function LandingPads.get_all()
	return LandingPads.pads
end

-- Create a landing pad using Aseprite tilemap coordinates
-- @param config: {id, name, aseprite_x, aseprite_z, mesh, scale, sprite, collision_dims, collision_y_offset}
-- @return landing pad object
function LandingPads.create_pad_aseprite(config)
	-- Convert Aseprite coordinates to world coordinates
	local world_x, world_z = Constants.aseprite_to_world(config.aseprite_x, config.aseprite_z)

	-- Create new config with world coordinates
	local world_config = {
		id = config.id,
		name = config.name,
		x = world_x,
		z = world_z,
		mesh = config.mesh,
		scale = config.scale,
		sprite = config.sprite,
		collision_dims = config.collision_dims,
		collision_y_offset = config.collision_y_offset
	}

	return LandingPads.create_pad(world_config)
end

return LandingPads
