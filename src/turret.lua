-- Turret module: Player auto-turret
local Turret = {}

-- Helper to create vectors (same as main.lua)
local function vec(x, y, z)
	return {x=x, y=y, z=z}
end

-- Quaternion math for gimbal-lock-free rotation
local Quat = {}

-- Create quaternion from axis-angle or components
function Quat.new(w, x, y, z)
	return {w=w or 1, x=x or 0, y=y or 0, z=z or 0}
end

-- Create quaternion from euler angles (yaw, pitch, roll)
function Quat.from_euler(yaw, pitch, roll)
	local cy, sy = cos(yaw * 0.5), sin(yaw * 0.5)
	local cp, sp = cos(pitch * 0.5), sin(pitch * 0.5)
	local cr, sr = cos(roll * 0.5), sin(roll * 0.5)

	return {
		w = cy * cp * cr + sy * sp * sr,
		x = cy * cp * sr - sy * sp * cr,
		y = sy * cp * sr + cy * sp * cr,
		z = sy * cp * cr - cy * sp * sr
	}
end

-- Convert quaternion to euler angles (returns yaw, pitch, roll)
function Quat.to_euler(q)
	-- yaw (z-axis rotation)
	local siny_cosp = 2 * (q.w * q.z + q.x * q.y)
	local cosy_cosp = 1 - 2 * (q.y * q.y + q.z * q.z)
	local yaw = atan2(siny_cosp, cosy_cosp)

	-- pitch (y-axis rotation) - use atan2 instead of asin
	local sinp = 2 * (q.w * q.y - q.z * q.x)
	local pitch
	if abs(sinp) >= 1 then
		pitch = sinp > 0 and 0.25 or -0.25  -- Use 90 degrees if out of range
	else
		-- atan2(sin, cos) is equivalent to asin(sin) when cos = sqrt(1 - sin^2)
		local cosp = sqrt(1 - sinp * sinp)
		pitch = atan2(sinp, cosp)
	end

	-- roll (x-axis rotation)
	local sinr_cosp = 2 * (q.w * q.x + q.y * q.z)
	local cosr_cosp = 1 - 2 * (q.x * q.x + q.y * q.y)
	local roll = atan2(sinr_cosp, cosr_cosp)

	return yaw, pitch, roll
end

-- Multiply two quaternions
function Quat.multiply(q1, q2)
	return {
		w = q1.w * q2.w - q1.x * q2.x - q1.y * q2.y - q1.z * q2.z,
		x = q1.w * q2.x + q1.x * q2.w + q1.y * q2.z - q1.z * q2.y,
		y = q1.w * q2.y - q1.x * q2.z + q1.y * q2.w + q1.z * q2.x,
		z = q1.w * q2.z + q1.x * q2.y - q1.y * q2.x + q1.z * q2.w
	}
end

-- Spherical linear interpolation between two quaternions
function Quat.slerp(q1, q2, t)
	-- Compute dot product
	local dot = q1.w * q2.w + q1.x * q2.x + q1.y * q2.y + q1.z * q2.z

	-- If dot product is negative, negate q2 to take shorter path
	local q2_copy = {w=q2.w, x=q2.x, y=q2.y, z=q2.z}
	if dot < 0 then
		q2_copy.w = -q2_copy.w
		q2_copy.x = -q2_copy.x
		q2_copy.y = -q2_copy.y
		q2_copy.z = -q2_copy.z
		dot = -dot
	end

	-- If quaternions are very close, use linear interpolation
	if dot > 0.9995 then
		return {
			w = q1.w + t * (q2_copy.w - q1.w),
			x = q1.x + t * (q2_copy.x - q1.x),
			y = q1.y + t * (q2_copy.y - q1.y),
			z = q1.z + t * (q2_copy.z - q1.z)
		}
	end

	-- Spherical interpolation - use atan2 instead of acos
	-- theta = acos(dot) = atan2(sqrt(1 - dot^2), dot)
	local theta = atan2(sqrt(1 - dot * dot), dot)
	local sin_theta = sin(theta)
	local a = sin((1 - t) * theta) / sin_theta
	local b = sin(t * theta) / sin_theta

	return {
		w = a * q1.w + b * q2_copy.w,
		x = a * q1.x + b * q2_copy.x,
		y = a * q1.y + b * q2_copy.y,
		z = a * q1.z + b * q2_copy.z
	}
end

-- Normalize quaternion
function Quat.normalize(q)
	local mag = sqrt(q.w * q.w + q.x * q.x + q.y * q.y + q.z * q.z)
	if mag < 0.0001 then
		return {w=1, x=0, y=0, z=0}
	end
	return {w=q.w/mag, x=q.x/mag, y=q.y/mag, z=q.z/mag}
end

-- Conjugate/inverse quaternion (for unit quaternions, conjugate = inverse)
function Quat.conjugate(q)
	return {w=q.w, x=-q.x, y=-q.y, z=-q.z}
end

-- Turret mount configuration (EASY TO ADJUST!)
Turret.MOUNT_OFFSET_X = 0    -- X offset from ship center when mounted
Turret.MOUNT_OFFSET_Y = 0.3  -- Y offset (positive = above ship, along up vector)
Turret.MOUNT_OFFSET_Z = 0.0  -- Z offset from ship center when mounted (positive = forward)

-- Turret configuration
Turret.FIRE_ARC = 0.5  -- 180 degrees (half hemisphere)
Turret.FIRE_RANGE = 20  -- 200 meters
Turret.ROTATION_SPEED = 0.1  -- How fast turret rotates to target (0-1, slerp factor)
Turret.MAX_PITCH = 0.125  -- Max pitch up/down (45 degrees = 0.125 turns)
Turret.MAX_YAW = 0.25  -- Max yaw left/right from ship forward (90 degrees = 0.25 turns)
Turret.SPRITE = 24

-- Turret state
Turret.orientation = Quat.new()  -- Current orientation (quaternion)
Turret.target = nil  -- Current target
Turret.verts = nil
Turret.faces = nil

-- Initialize turret geometry (long cube) using proper cube generation
function Turret.init()
	-- Long cube (1.0 units long, 0.15x0.15 cross section) - visible size
	local length = 0.5
	local width = 0.05
	local height = 0.05

	-- Create vertices for a box (INVERTED: back/front swapped so it points forward)
	-- Bottom vertices (y = -height/2), then top vertices (y = +height/2)
	Turret.verts = {
		vec(-width/2, -height/2, -length), -- 1: bottom back left (inverted Z)
		vec(width/2, -height/2, -length),  -- 2: bottom back right (inverted Z)
		vec(width/2, -height/2, 0),        -- 3: bottom front right (inverted Z)
		vec(-width/2, -height/2, 0),       -- 4: bottom front left (inverted Z)
		vec(-width/2, height/2, -length),  -- 5: top back left (inverted Z)
		vec(width/2, height/2, -length),   -- 6: top back right (inverted Z)
		vec(width/2, height/2, 0),         -- 7: top front right (inverted Z)
		vec(-width/2, height/2, 0)         -- 8: top front left (inverted Z)
	}

	-- Faces with sprite 24 (32x32 texture) - same winding as cargo
	Turret.faces = {
		{1, 2, 3, Turret.SPRITE, vec(0,0), vec(32,0), vec(32,32)}, {1, 3, 4, Turret.SPRITE, vec(0,0), vec(32,32), vec(0,32)},  -- Bottom
		{5, 7, 6, Turret.SPRITE, vec(0,0), vec(32,0), vec(32,32)}, {5, 8, 7, Turret.SPRITE, vec(0,0), vec(32,32), vec(0,32)},  -- Top
		{1, 5, 6, Turret.SPRITE, vec(0,0), vec(32,0), vec(32,32)}, {1, 6, 2, Turret.SPRITE, vec(0,0), vec(32,32), vec(0,32)},  -- Back
		{3, 7, 8, Turret.SPRITE, vec(0,0), vec(32,0), vec(32,32)}, {3, 8, 4, Turret.SPRITE, vec(0,0), vec(32,32), vec(0,32)},  -- Front
		{4, 8, 5, Turret.SPRITE, vec(0,0), vec(32,0), vec(32,32)}, {4, 5, 1, Turret.SPRITE, vec(0,0), vec(32,32), vec(0,32)},  -- Left
		{2, 6, 7, Turret.SPRITE, vec(0,0), vec(32,0), vec(32,32)}, {2, 7, 3, Turret.SPRITE, vec(0,0), vec(32,32), vec(0,32)}   -- Right
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

-- Update turret (find target and rotate toward it using quaternions)
function Turret.update(delta_time, ship, enemies)
	-- Find target
	Turret.target = Turret.find_target(ship, enemies)

	-- Get current turret world position
	local turret_x, turret_y, turret_z = Turret.get_position(ship.x, ship.y, ship.z, ship.pitch, ship.yaw, ship.roll)

	local target_quat
	if Turret.target then
		-- Calculate direction to target (in world space)
		local dx = Turret.target.x - turret_x
		local dy = Turret.target.y - turret_y
		local dz = Turret.target.z - turret_z

		-- Target yaw and pitch (in absolute world space - independent of ship)
		local target_yaw = atan2(dx, dz)
		local horizontal_dist = sqrt(dx*dx + dz*dz)
		local target_pitch = -atan2(dy, horizontal_dist)

		-- Check if target is within firing arc (relative to ship's forward direction)
		local yaw_relative = target_yaw - ship.yaw
		-- Normalize to -0.5 to 0.5 range
		while yaw_relative > 0.5 do yaw_relative -= 1 end
		while yaw_relative < -0.5 do yaw_relative += 1 end

		-- Clamp to firing arc if needed
		local clamped_yaw = target_yaw
		if abs(yaw_relative) > Turret.MAX_YAW then
			-- Outside firing arc - clamp to edge of arc
			if yaw_relative > 0 then
				clamped_yaw = ship.yaw + Turret.MAX_YAW
			else
				clamped_yaw = ship.yaw - Turret.MAX_YAW
			end
		end

		-- Clamp pitch to max pitch constraint (relative to horizontal)
		local clamped_pitch = target_pitch
		if clamped_pitch > Turret.MAX_PITCH then
			clamped_pitch = Turret.MAX_PITCH
		elseif clamped_pitch < -Turret.MAX_PITCH then
			clamped_pitch = -Turret.MAX_PITCH
		end

		-- Create target quaternion in world space (no ship rotation influence)
		target_quat = Quat.from_euler(clamped_yaw, clamped_pitch, 0)
	else
		-- Return to forward position (match ship orientation - pitch, yaw, and roll)
		target_quat = Quat.from_euler(ship.yaw, ship.pitch, ship.roll)
	end

	-- Slerp toward target orientation
	Turret.orientation = Quat.slerp(Turret.orientation, target_quat, Turret.ROTATION_SPEED)
	Turret.orientation = Quat.normalize(Turret.orientation)
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

-- Get firing direction (toward target)
function Turret.get_fire_direction(ship)
	if not Turret.target then
		return nil
	end

	-- Get turret world position
	local turret_x, turret_y, turret_z = Turret.get_position(ship.x, ship.y, ship.z, ship.pitch, ship.yaw, ship.roll)

	-- Direction from turret to target: (enemy - turret).normalize
	local dir_x = Turret.target.x - turret_x
	local dir_y = Turret.target.y - turret_y
	local dir_z = Turret.target.z - turret_z

	-- Normalize
	local mag = sqrt(dir_x*dir_x + dir_y*dir_y + dir_z*dir_z)
	if mag < 0.0001 then
		return 0, 0, 1  -- Default forward
	end
	return dir_x/mag, dir_y/mag, dir_z/mag
end

-- Get turret euler angles for rendering
function Turret.get_euler_angles()
	return Quat.to_euler(Turret.orientation)
end

-- Reset turret
function Turret.reset()
	Turret.orientation = Quat.new()
	Turret.target = nil
end

-- Project 3D point to 2D screen space
function Turret.project_3d_to_2d(x, y, z, camera)
	-- Apply camera transform
	x = x - camera.x
	y = y - camera.y
	z = z - camera.z

	-- Rotate by camera rotation
	local cos_ry = cos(camera.ry)
	local sin_ry = sin(camera.ry)
	local x2 = x * cos_ry - z * sin_ry
	local z2 = x * sin_ry + z * cos_ry

	local cos_rx = cos(camera.rx)
	local sin_rx = sin(camera.rx)
	local y2 = y * cos_rx - z2 * sin_rx
	local z3 = y * sin_rx + z2 * cos_rx

	-- Move away from camera (hardcoded cam_dist like in renderer)
	local cam_dist = 5
	z3 = z3 + cam_dist

	-- Perspective projection
	local near = 0.1
	if z3 > near then
		local fov = 70
		local fov_rad = fov / 360
		local tan_half_fov = sin(fov_rad) / cos(fov_rad)
		local px = x2 / z3 * (270 / tan_half_fov)
		local py = y2 / z3 * (270 / tan_half_fov)

		-- Screen space
		px = px + 240
		py = py + 135

		return px, py, z3
	end

	return nil, nil, nil
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
