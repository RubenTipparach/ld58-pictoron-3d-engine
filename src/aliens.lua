-- Aliens module: UFO fighters and mother ship
local Aliens = {}

-- Helper to create vectors (same as main.lua)
local function vec(x, y, z)
	return {x=x, y=y, z=z}
end

-- Alien configuration
Aliens.FIGHTER_HEALTH = 100
Aliens.MOTHER_SHIP_HEALTH = 2000
Aliens.FIGHTER_SPEED = 2.0  -- Units per second
Aliens.FIGHTER_FIRE_RATE = 2  -- Bullets per second
Aliens.FIGHTER_FIRE_ARC = 0.125  -- 45 degrees (45/360 = 0.125)
Aliens.FIGHTER_FIRE_RANGE = 15  -- Units

-- Fighter AI behavior
Aliens.FIGHTER_ENGAGE_DIST = 10  -- 100 meters - get close
Aliens.FIGHTER_RETREAT_DIST = 20  -- 200 meters - retreat distance
Aliens.FIGHTER_ENGAGE_TIME = 10  -- Seconds to circle close
Aliens.FIGHTER_RETREAT_TIME = 15  -- Seconds to stay far

Aliens.MOTHER_SHIP_FIRE_RATE = 2  -- Bullets per second (reduced from 10 for performance)
Aliens.MOTHER_SHIP_FIRE_RANGE = 25  -- Units

-- Wave configuration (DEBUG: Single fighter for testing)
Aliens.waves = {
	{count = 1, type = "fighter"},  -- DEBUG: Just one fighter
	{count = 4, type = "fighter"},
	{count = 1, type = "mother"}
}

-- Active aliens
Aliens.fighters = {}
Aliens.mother_ship = nil
Aliens.current_wave = 0
Aliens.wave_complete = false
Aliens.mother_ship_destroyed = false  -- Track if mother ship was killed
Aliens.mother_ship_destroyed_time = nil  -- Time when mother ship was destroyed

-- Mesh storage (set from main.lua)
Aliens.fighter_mesh = nil
Aliens.mother_mesh = nil

-- Create a UFO fighter
function Aliens.spawn_fighter(x, y, z)
	local fighter = {
		x = x,
		y = y,
		z = z,
		vx = 0,
		vy = 0,
		vz = 0,
		yaw = 0,
		roll = 0,  -- Banking while turning
		prev_yaw = 0,  -- For banking calculation
		health = Aliens.FIGHTER_HEALTH,
		max_health = Aliens.FIGHTER_HEALTH,
		fire_timer = 0,
		target = nil,  -- Will be set to player ship
		type = "fighter",
		-- AI state
		ai_state = "engage",  -- "engage" or "retreat"
		ai_timer = 0,  -- Time in current state
		circle_angle = rnd(1)  -- Random starting angle for circling
	}
	add(Aliens.fighters, fighter)
	return fighter
end

-- Create mother ship
function Aliens.spawn_mother_ship(x, y, z)
	Aliens.mother_ship = {
		x = x,
		y = y,
		z = z,
		vx = 0,
		vy = 0,
		vz = 0,
		yaw = 0,
		health = Aliens.MOTHER_SHIP_HEALTH,
		max_health = Aliens.MOTHER_SHIP_HEALTH,
		fire_timer = 0,
		fire_angle = 0,  -- For bullet patterns
		target = nil,  -- Will be set to player ship
		type = "mother"
	}
	return Aliens.mother_ship
end

-- Reset alien state
function Aliens.reset()
	Aliens.fighters = {}
	Aliens.mother_ship = nil
	Aliens.current_wave = 0
	Aliens.wave_complete = false
	Aliens.mother_ship_destroyed = false
end

-- Start next wave
function Aliens.start_next_wave(player)
	Aliens.current_wave += 1
	if Aliens.current_wave > #Aliens.waves then
		return false  -- No more waves
	end

	local wave = Aliens.waves[Aliens.current_wave]
	Aliens.wave_complete = false

	if wave.type == "fighter" then
		-- DEBUG: Spawn fighters close to player (50m = 5 units)
		for i = 1, wave.count do
			local angle = (i / wave.count) * 1  -- Spread around circle
			local distance = 5  -- DEBUG: 50 meters (was 30)
			local x = player.x + cos(angle) * distance
			local z = player.z + sin(angle) * distance
			local y = player.y + 2  -- DEBUG: Same height as player (was +5 to +10)
			local fighter = Aliens.spawn_fighter(x, y, z)
			fighter.target = player
		end
	elseif wave.type == "mother" then
		-- Spawn mother ship above player
		local mother = Aliens.spawn_mother_ship(player.x, player.y + 20, player.z)
		mother.target = player
	end

	return true
end

-- Callbacks for explosions (set from main.lua)
Aliens.on_fighter_destroyed = nil
Aliens.on_mothership_destroyed = nil

-- Update all aliens
function Aliens.update(delta_time, player)
	-- Update fighters
	for i = #Aliens.fighters, 1, -1 do
		local fighter = Aliens.fighters[i]

		if fighter.health <= 0 then
			-- Trigger fighter explosion callback
			if Aliens.on_fighter_destroyed then
				Aliens.on_fighter_destroyed(fighter.x, fighter.y, fighter.z)
			end
			del(Aliens.fighters, fighter)
		else
			Aliens.update_fighter(fighter, delta_time, player)
		end
	end

	-- Update mother ship
	if Aliens.mother_ship then
		if Aliens.mother_ship.health <= 0 then
			-- Trigger mother ship explosion callback
			if Aliens.on_mothership_destroyed then
				Aliens.on_mothership_destroyed(Aliens.mother_ship.x, Aliens.mother_ship.y, Aliens.mother_ship.z)
			end
			Aliens.mother_ship_destroyed = true  -- Mark as destroyed
			Aliens.mother_ship_destroyed_time = time()  -- Record destruction time
			Aliens.mother_ship = nil
		else
			-- DEBUG: Make mother ship stationary
			-- Aliens.update_mother_ship(Aliens.mother_ship, delta_time, player)

			-- Just update fire timer
			Aliens.mother_ship.fire_timer += delta_time
		end
	end

	-- Check if wave is complete (only if a wave has been started)
	if #Aliens.fighters == 0 and not Aliens.mother_ship and Aliens.current_wave > 0 then
		Aliens.wave_complete = true
	end
end

-- Update fighter AI (engage/retreat pattern)
function Aliens.update_fighter(fighter, delta_time, player)
	-- Update AI state timer
	fighter.ai_timer += delta_time

	-- Direction to player
	local dx = player.x - fighter.x
	local dy = player.y - fighter.y
	local dz = player.z - fighter.z
	local dist = sqrt(dx*dx + dy*dy + dz*dz)

	-- State machine: engage (get close and circle) or retreat (fly away)
	if fighter.ai_state == "engage" then
		-- Engage: fly to 80m and circle for 10 seconds
		if fighter.ai_timer >= Aliens.FIGHTER_ENGAGE_TIME then
			fighter.ai_state = "retreat"
			fighter.ai_timer = 0
		end

		local desired_dist = Aliens.FIGHTER_ENGAGE_DIST

		if dist > desired_dist + 2 then
			-- Move toward player
			local dir_x = dx / dist
			local dir_y = dy / dist
			local dir_z = dz / dist
			fighter.vx = dir_x * Aliens.FIGHTER_SPEED
			fighter.vy = dir_y * Aliens.FIGHTER_SPEED
			fighter.vz = dir_z * Aliens.FIGHTER_SPEED
		else
			-- Circle around player with small radius (1-2 units = 10-20m)
			fighter.circle_angle += delta_time * 0.3  -- Rotation speed
			local circle_radius = 1.5  -- 15 meters circle radius
			local circle_x = player.x + cos(fighter.circle_angle) * circle_radius
			local circle_z = player.z + sin(fighter.circle_angle) * circle_radius
			local circle_y = player.y + 2

			local to_circle_x = circle_x - fighter.x
			local to_circle_y = circle_y - fighter.y
			local to_circle_z = circle_z - fighter.z
			local to_circle_dist = sqrt(to_circle_x*to_circle_x + to_circle_y*to_circle_y + to_circle_z*to_circle_z)

			if to_circle_dist > 0.1 then
				fighter.vx = (to_circle_x / to_circle_dist) * Aliens.FIGHTER_SPEED
				fighter.vy = (to_circle_y / to_circle_dist) * Aliens.FIGHTER_SPEED
				fighter.vz = (to_circle_z / to_circle_dist) * Aliens.FIGHTER_SPEED
			end
		end

	elseif fighter.ai_state == "retreat" then
		-- Retreat: fly to 200m and stay for 15 seconds
		if fighter.ai_timer >= Aliens.FIGHTER_RETREAT_TIME then
			fighter.ai_state = "engage"
			fighter.ai_timer = 0
		end

		local desired_dist = Aliens.FIGHTER_RETREAT_DIST

		if dist < desired_dist - 2 then
			-- Move away from player
			local dir_x = -dx / dist
			local dir_y = -dy / dist
			local dir_z = -dz / dist
			fighter.vx = dir_x * Aliens.FIGHTER_SPEED
			fighter.vy = dir_y * Aliens.FIGHTER_SPEED
			fighter.vz = dir_z * Aliens.FIGHTER_SPEED
		else
			-- Hold position at distance
			fighter.vx = 0
			fighter.vy = 0
			fighter.vz = 0
		end
	end

	-- Stay above minimum altitude
	local min_altitude = 10  -- 100 meters
	if fighter.y < min_altitude then
		fighter.vy = 0.5
	elseif fighter.y > 30 then
		fighter.vy = -0.2
	end

	-- Update position
	fighter.x += fighter.vx * delta_time
	fighter.y += fighter.vy * delta_time
	fighter.z += fighter.vz * delta_time

	-- Rotate to face velocity direction (direction of flight)
	local new_yaw = atan2(fighter.vx, fighter.vz)

	-- Calculate yaw change for banking
	local yaw_change = new_yaw - fighter.prev_yaw
	-- Normalize to -0.5 to 0.5
	while yaw_change > 0.5 do yaw_change -= 1 end
	while yaw_change < -0.5 do yaw_change += 1 end

	-- Bank based on turn rate (max 30 degrees = 0.083 turns)
	local max_bank = 0.083
	fighter.roll = -yaw_change * 10  -- Negative for correct banking direction
	if fighter.roll > max_bank then fighter.roll = max_bank end
	if fighter.roll < -max_bank then fighter.roll = -max_bank end

	-- Smooth roll back to level when not turning much
	if abs(yaw_change) < 0.01 then
		fighter.roll = fighter.roll * 0.9  -- Dampen roll
	end

	fighter.prev_yaw = fighter.yaw
	fighter.yaw = new_yaw

	-- Update fire timer
	fighter.fire_timer += delta_time
end

-- Update mother ship
function Aliens.update_mother_ship(mother, delta_time, player)
	-- Hover in place, slowly descending
	if mother.y > player.y + 10 then
		mother.vy = -0.1
		mother.y += mother.vy * delta_time * 60
	else
		mother.vy = 0
	end

	-- Rotate slowly
	mother.yaw += delta_time * 0.2

	-- Update fire timer and pattern angle
	mother.fire_timer += delta_time
	mother.fire_angle += delta_time * 2  -- Rotate bullet pattern
end

-- Check if fighter can fire at player
function Aliens.can_fire_fighter(fighter, player)
	local dx = player.x - fighter.x
	local dy = player.y - fighter.y
	local dz = player.z - fighter.z
	local dist = sqrt(dx*dx + dy*dy + dz*dz)

	if dist > Aliens.FIGHTER_FIRE_RANGE then
		return false
	end

	-- Check if player is in firing arc (45 degrees from front)
	local angle_to_player = atan2(dx, dz)
	local angle_diff = abs(angle_to_player - fighter.yaw)
	if angle_diff > 0.5 then
		angle_diff = 1 - angle_diff
	end

	return angle_diff <= Aliens.FIGHTER_FIRE_ARC
end

-- Get all active aliens for rendering and collision
function Aliens.get_all()
	local result = {}
	for f in all(Aliens.fighters) do
		add(result, f)
	end
	if Aliens.mother_ship then
		add(result, Aliens.mother_ship)
	end
	return result
end

-- Reset aliens system
function Aliens.reset()
	Aliens.fighters = {}
	Aliens.mother_ship = nil
	Aliens.current_wave = 0
	Aliens.wave_complete = false
end

return Aliens
