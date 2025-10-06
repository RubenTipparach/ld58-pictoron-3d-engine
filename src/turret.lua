-- Turret module: Player auto-turret
local Turret = {}

-- Helper to create vectors (same as main.lua)
local function vec(x, y, z)
	return {x=x, y=y, z=z}
end

-- Turret mount configuration (EASY TO ADJUST!)
Turret.MOUNT_OFFSET_X = 0    -- X offset from ship center when mounted
Turret.MOUNT_OFFSET_Y = 0.2  -- Y offset (positive = above ship, along up vector)
Turret.MOUNT_OFFSET_Z = 0.5  -- Z offset from ship center when mounted (positive = forward)

-- Turret configuration
Turret.FIRE_ARC = 0.5  -- 180 degrees (half hemisphere)
Turret.FIRE_RANGE = 20  -- 200 meters
Turret.ROTATION_SPEED = 0.1  -- How fast turret rotates to target
Turret.SPRITE = 24

-- Turret state
Turret.yaw = 0  -- Current rotation
Turret.pitch = 0  -- Current pitch
Turret.target = nil  -- Current target
Turret.verts = nil
Turret.faces = nil

-- Initialize turret geometry (long cube, rotated 90 degrees)
function Turret.init()
	-- Long cube (0.2 units long, 0.03x0.03 cross section) - 1/10 size
	local length = 0.2
	local width = 0.03
	local height = 0.03

	-- Create vertices for a box
	Turret.verts = {
		vec(-width/2, -height/2, 0),      -- 1: back bottom left
		vec(width/2, -height/2, 0),       -- 2: back bottom right
		vec(width/2, height/2, 0),        -- 3: back top right
		vec(-width/2, height/2, 0),       -- 4: back top left
		vec(-width/2, -height/2, length), -- 5: front bottom left
		vec(width/2, -height/2, length),  -- 6: front bottom right
		vec(width/2, height/2, length),   -- 7: front top right
		vec(-width/2, height/2, length)   -- 8: front top left
	}

	-- Faces with sprite 24
	Turret.faces = {
		{1, 2, 3, Turret.SPRITE, vec(0,0), vec(16,0), vec(8,16)},  -- Back
		{1, 3, 4, Turret.SPRITE, vec(0,0), vec(16,16), vec(0,16)},
		{5, 6, 7, Turret.SPRITE, vec(0,0), vec(16,0), vec(8,16)},  -- Front
		{5, 7, 8, Turret.SPRITE, vec(0,0), vec(16,16), vec(0,16)},
		{1, 2, 6, Turret.SPRITE, vec(0,0), vec(16,0), vec(8,16)},  -- Bottom
		{1, 6, 5, Turret.SPRITE, vec(0,0), vec(16,16), vec(0,16)},
		{4, 3, 7, Turret.SPRITE, vec(0,0), vec(16,0), vec(8,16)},  -- Top
		{4, 7, 8, Turret.SPRITE, vec(0,0), vec(16,16), vec(0,16)},
		{1, 4, 8, Turret.SPRITE, vec(0,0), vec(16,0), vec(8,16)},  -- Left
		{1, 8, 5, Turret.SPRITE, vec(0,0), vec(16,16), vec(0,16)},
		{2, 3, 7, Turret.SPRITE, vec(0,0), vec(16,0), vec(8,16)},  -- Right
		{2, 7, 6, Turret.SPRITE, vec(0,0), vec(16,16), vec(0,16)}
	}
end

-- Find best target from list of enemies
function Turret.find_target(ship, enemies)
	local best_target = nil
	local best_score = -999

	for enemy in all(enemies) do
		local dx = enemy.x - ship.x
		local dy = enemy.y - ship.y
		local dz = enemy.z - ship.z
		local dist = sqrt(dx*dx + dy*dy + dz*dz)

		-- Check if in range
		if dist <= Turret.FIRE_RANGE then
			-- Check if in firing arc (180 degrees from ship's front)
			local angle_to_enemy = atan2(dx, dz)
			local angle_diff = abs(angle_to_enemy - ship.yaw)
			if angle_diff > 0.5 then
				angle_diff = 1 - angle_diff
			end

			if angle_diff <= Turret.FIRE_ARC then
				-- Prioritize closer enemies
				local score = (Turret.FIRE_RANGE - dist) / Turret.FIRE_RANGE
				if score > best_score then
					best_score = score
					best_target = enemy
				end
			end
		end
	end

	return best_target
end

-- Update turret (find target and rotate toward it)
function Turret.update(delta_time, ship, enemies)
	-- Find target
	Turret.target = Turret.find_target(ship, enemies)

	if Turret.target then
		-- Calculate angle to target
		local dx = Turret.target.x - ship.x
		local dy = Turret.target.y - ship.y
		local dz = Turret.target.z - ship.z

		-- Target yaw (horizontal rotation)
		local target_yaw = atan2(dx, dz)

		-- Target pitch (vertical rotation)
		local horizontal_dist = sqrt(dx*dx + dz*dz)
		local target_pitch = -atan2(dy, horizontal_dist)

		-- Smoothly rotate toward target
		local yaw_diff = target_yaw - Turret.yaw
		if yaw_diff > 0.5 then
			yaw_diff -= 1
		elseif yaw_diff < -0.5 then
			yaw_diff += 1
		end
		Turret.yaw += yaw_diff * Turret.ROTATION_SPEED

		local pitch_diff = target_pitch - Turret.pitch
		Turret.pitch += pitch_diff * Turret.ROTATION_SPEED
	else
		-- Return to forward position
		Turret.yaw += (ship.yaw - Turret.yaw) * Turret.ROTATION_SPEED * 0.5
		Turret.pitch += (0 - Turret.pitch) * Turret.ROTATION_SPEED * 0.5
	end

	-- Normalize angles
	if Turret.yaw > 1 then
		Turret.yaw -= 1
	elseif Turret.yaw < 0 then
		Turret.yaw += 1
	end
end

-- Check if turret can fire (aligned with target)
function Turret.can_fire()
	if not Turret.target then
		return false
	end

	-- Check if turret is roughly aligned (within 5 degrees)
	-- This is checked in the main update loop
	return true
end

-- Get firing direction
function Turret.get_fire_direction()
	if not Turret.target then
		return nil
	end

	-- Direction based on turret rotation
	local dir_x = sin(Turret.yaw) * cos(Turret.pitch)
	local dir_y = sin(Turret.pitch)
	local dir_z = cos(Turret.yaw) * cos(Turret.pitch)

	-- Normalize
	local mag = sqrt(dir_x*dir_x + dir_y*dir_y + dir_z*dir_z)
	return dir_x/mag, dir_y/mag, dir_z/mag
end

-- Reset turret
function Turret.reset()
	Turret.yaw = 0
	Turret.pitch = 0
	Turret.target = nil
end

-- Get turret position in world space (mounted on ship)
-- Transforms mount offset by ship rotation to get world position
function Turret.get_position(ship_x, ship_y, ship_z, ship_pitch, ship_yaw, ship_roll)
	ship_pitch = ship_pitch or 0
	ship_yaw = ship_yaw or 0
	ship_roll = ship_roll or 0

	local offset_x = Turret.MOUNT_OFFSET_X
	local offset_y = Turret.MOUNT_OFFSET_Y
	local offset_z = Turret.MOUNT_OFFSET_Z

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

	-- Position turret at ship position + rotated offset
	return ship_x + x_final, ship_y + y_final, ship_z + z_final
end

return Turret
