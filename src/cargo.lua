-- Cargo module: Pickup objects for missions
local Constants = include("src/constants.lua")
local Heightmap = include("src/heightmap.lua")

local Cargo = {}

-- Cargo attachment configuration (EASY TO ADJUST!)
Cargo.MOUNT_OFFSET_X = 0    -- X offset from ship center when attached
Cargo.MOUNT_OFFSET_Y = -0.8 -- Y offset (negative = below ship, along down vector)
Cargo.MOUNT_OFFSET_Z = 0    -- Z offset from ship center when attached

-- Convert Aseprite coordinates (0,0 at top-left, 128,128 at bottom-right)
-- to world coordinates (centered at origin)
-- Aseprite coords: (0,0) = top-left, (128,128) = bottom-right
-- World coords: (-256, -256) to (256, 256) in world units (1 unit = 10 meters)
function Cargo.aseprite_to_world(aseprite_x, aseprite_z)
	-- Aseprite heightmap is 128x128 pixels
	-- World map is 512x512 world units (128 * 4, since TILE_SIZE = 4)
	-- Center is at (64, 64) in Aseprite coords

	local world_x = (aseprite_x - 64) * 4  -- Offset from center, scaled by tile size
	local world_z = (aseprite_z - 64) * 4  -- Offset from center, scaled by tile size

	return world_x, world_z
end

-- Create a cargo pickup object
-- config: {aseprite_x, aseprite_z, use_heightmap, id, world_y}
-- Returns: cargo object with mesh, position, and state
function Cargo.create(config)
	local aseprite_x = config.aseprite_x
	local aseprite_z = config.aseprite_z
	local use_heightmap = config.use_heightmap ~= false  -- Default to true
	local id = config.id or 1

	-- Convert Aseprite coordinates to world coordinates
	local world_x, world_z = Cargo.aseprite_to_world(aseprite_x, aseprite_z)

	-- Get terrain height (or use custom Y if provided)
	local world_y = config.world_y or 0
	if not config.world_y and use_heightmap then
		world_y = Heightmap.get_height(world_x, world_z)
	end

	-- Load cargo mesh from OBJ file
	local load_obj = include("src/obj_loader.lua")
	local cargo_mesh = load_obj("cargo.obj")

	-- Fallback cube if OBJ doesn't load
	if not cargo_mesh or #cargo_mesh.verts == 0 then
		cargo_mesh = {
			verts = {
				vec(-0.5, 0, -0.5), vec(0.5, 0, -0.5), vec(0.5, 0, 0.5), vec(-0.5, 0, 0.5),
				vec(-0.5, 1, -0.5), vec(0.5, 1, -0.5), vec(0.5, 1, 0.5), vec(-0.5, 1, 0.5)
			},
			faces = {
				{1, 2, 3, Constants.SPRITE_CARGO, vec(0,0), vec(32,0), vec(32,32)}, {1, 3, 4, Constants.SPRITE_CARGO, vec(0,0), vec(32,32), vec(0,32)},
				{5, 7, 6, Constants.SPRITE_CARGO, vec(0,0), vec(32,0), vec(32,32)}, {5, 8, 7, Constants.SPRITE_CARGO, vec(0,0), vec(32,32), vec(0,32)},
				{1, 5, 6, Constants.SPRITE_CARGO, vec(0,0), vec(32,0), vec(32,32)}, {1, 6, 2, Constants.SPRITE_CARGO, vec(0,0), vec(32,32), vec(0,32)},
				{3, 7, 8, Constants.SPRITE_CARGO, vec(0,0), vec(32,0), vec(32,32)}, {3, 8, 4, Constants.SPRITE_CARGO, vec(0,0), vec(32,32), vec(0,32)},
				{4, 8, 5, Constants.SPRITE_CARGO, vec(0,0), vec(32,0), vec(32,32)}, {4, 5, 1, Constants.SPRITE_CARGO, vec(0,0), vec(32,32), vec(0,32)},
				{2, 6, 7, Constants.SPRITE_CARGO, vec(0,0), vec(32,0), vec(32,32)}, {2, 7, 3, Constants.SPRITE_CARGO, vec(0,0), vec(32,32), vec(0,32)}
			}
		}
	end

	-- Override sprite to SPRITE_CARGO (16x16)
	for _, face in ipairs(cargo_mesh.faces) do
		face[4] = Constants.SPRITE_CARGO
		-- UVs already set to 16x16 in mesh definition
	end

	return {
		id = id,
		verts = cargo_mesh.verts,
		faces = cargo_mesh.faces,
		x = world_x,
		y = world_y + 0.5,  -- Float slightly above ground
		z = world_z,
		base_y = world_y + 0.5,  -- Store base Y position
		aseprite_x = aseprite_x,
		aseprite_z = aseprite_z,
		collected = false,
		state = "idle",  -- States: "idle", "tethering", "attached", "delivered"
		hover_distance = 2,  -- Distance to show prompt (2 world units = 20 meters)
		attach_distance = 0.3,  -- Distance to attach (0.3 world units = 3 meters)
		tether_speed = 5.0,  -- Movement speed when tethering (5.0 world units = 50 m/s)
		bob_offset = 0,  -- For floating animation
		attached_to_ship = false,
		-- Mount offset - position relative to ship when attached (configured at top of file)
		mount_offset = {x = Cargo.MOUNT_OFFSET_X, y = Cargo.MOUNT_OFFSET_Y, z = Cargo.MOUNT_OFFSET_Z},
		scale = 0.5,  -- 50% smaller
		vy = 0,  -- Vertical velocity for falling physics
		gravity = -9.8,  -- Gravity acceleration (m/s^2 = units/s^2)
		-- Rotation when attached (matches ship rotation)
		pitch = 0,
		yaw = 0,
		roll = 0
	}
end

-- Update cargo state and animation
function Cargo.update(cargo, delta_time, ship_x, ship_y, ship_z, right_click_held, ship_landed, ship_pitch, ship_yaw, ship_roll)
	if cargo.state == "delivered" then return end

	-- Calculate distance to ship
	local dx = ship_x - cargo.x
	local dy = ship_y - cargo.y
	local dz = ship_z - cargo.z
	local dist_3d = sqrt(dx*dx + dy*dy + dz*dz)
	local dist_2d = sqrt(dx*dx + dz*dz)

	-- State machine
	if cargo.state == "idle" then
		-- No bobbing or spinning
		cargo.bob_offset = 0

		-- Auto-pickup when within range (no right-click needed)
		if dist_3d < cargo.hover_distance then
			cargo.state = "tethering"
			cargo.vy = 0
		end

	elseif cargo.state == "tethering" then
		-- Move towards ship at 50 m/s
		if dist_3d > cargo.attach_distance then
			-- Normalize direction and move at 50 m/s
			local dir_x = dx / dist_3d
			local dir_y = dy / dist_3d
			local dir_z = dz / dist_3d

			cargo.x += dir_x * cargo.tether_speed * delta_time
			cargo.y += dir_y * cargo.tether_speed * delta_time
			cargo.z += dir_z * cargo.tether_speed * delta_time

			-- Stop bobbing when tethering
			cargo.bob_offset = 0
		else
			-- Close enough - attach to ship
			cargo.state = "attached"
			cargo.attached_to_ship = true
			cargo.collected = true  -- Mark as collected
		end

	elseif cargo.state == "attached" then
		-- Transform mount offset by ship rotation
		ship_pitch = ship_pitch or 0
		ship_yaw = ship_yaw or 0
		ship_roll = ship_roll or 0

		local offset_x = cargo.mount_offset.x
		local offset_y = cargo.mount_offset.y
		local offset_z = cargo.mount_offset.z

		-- Apply yaw rotation (Y axis) to offset
		local cos_yaw, sin_yaw = cos(ship_yaw), sin(ship_yaw)
		local x_yaw = offset_x * cos_yaw - offset_z * sin_yaw
		local z_yaw = offset_x * sin_yaw + offset_z * cos_yaw
		local y_yaw = offset_y

		-- Apply pitch rotation (X axis) to offset
		local cos_pitch, sin_pitch = cos(ship_pitch), sin(ship_pitch)
		local x_pitch = x_yaw
		local y_pitch = y_yaw * cos_pitch - z_yaw * sin_pitch
		local z_pitch = y_yaw * sin_pitch + z_yaw * cos_pitch

		-- Apply roll rotation (Z axis) to offset
		local cos_roll, sin_roll = cos(ship_roll), sin(ship_roll)
		local x_final = x_pitch * cos_roll - y_pitch * sin_roll
		local y_final = x_pitch * sin_roll + y_pitch * cos_roll
		local z_final = z_pitch

		-- Position cargo at ship position + rotated offset
		cargo.x = ship_x + x_final
		cargo.y = ship_y + y_final
		cargo.z = ship_z + z_final

		-- Match ship rotation
		cargo.pitch = ship_pitch
		cargo.yaw = ship_yaw
		cargo.roll = ship_roll
		cargo.bob_offset = 0

		-- Cargo stays attached (delivery happens when touching landing pad)
	end
end

-- Check if cargo needs pickup prompt
function Cargo.show_pickup_prompt(cargo)
	return cargo.state == "hovering"
end

-- Check if cargo is being tethered
function Cargo.is_tethering(cargo)
	return cargo.state == "tethering"
end

-- Check if cargo is attached
function Cargo.is_attached(cargo)
	return cargo.state == "attached"
end

return Cargo
