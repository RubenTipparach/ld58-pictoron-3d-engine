-- Aliens module: UFO fighters and mother ship
local Aliens = {}

-- Helper to create vectors (same as main.lua)
local function vec(x, y, z)
	return {x=x, y=y, z=z}
end

-- Alien configuration
Aliens.FIGHTER_HEALTH = 100
Aliens.MOTHER_SHIP_HEALTH = 1000
Aliens.FIGHTER_SPEED = 0.3
Aliens.FIGHTER_FIRE_RATE = 2  -- Bullets per second
Aliens.FIGHTER_FIRE_ARC = 0.125  -- 45 degrees (45/360 = 0.125)
Aliens.FIGHTER_FIRE_RANGE = 15  -- Units
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
		health = Aliens.FIGHTER_HEALTH,
		max_health = Aliens.FIGHTER_HEALTH,
		fire_timer = 0,
		target = nil,  -- Will be set to player ship
		type = "fighter"
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

-- Update all aliens
function Aliens.update(delta_time, player)
	-- Update fighters
	for i = #Aliens.fighters, 1, -1 do
		local fighter = Aliens.fighters[i]

		if fighter.health <= 0 then
			del(Aliens.fighters, fighter)
		else
			-- DEBUG: Make enemies stationary
			-- Aliens.update_fighter(fighter, delta_time, player)

			-- Just update fire timer
			fighter.fire_timer += delta_time
		end
	end

	-- Update mother ship
	if Aliens.mother_ship then
		if Aliens.mother_ship.health <= 0 then
			Aliens.mother_ship = nil
		else
			-- DEBUG: Make mother ship stationary
			-- Aliens.update_mother_ship(Aliens.mother_ship, delta_time, player)

			-- Just update fire timer
			Aliens.mother_ship.fire_timer += delta_time
		end
	end

	-- Check if wave is complete
	if #Aliens.fighters == 0 and not Aliens.mother_ship then
		Aliens.wave_complete = true
	end
end

-- Update fighter AI
function Aliens.update_fighter(fighter, delta_time, player)
	-- Simple AI: circle around player and strafe
	local dx = player.x - fighter.x
	local dy = player.y - fighter.y
	local dz = player.z - fighter.z
	local dist = sqrt(dx*dx + dy*dy + dz*dz)

	-- Desired distance from player
	local desired_dist = 12

	-- Calculate direction to player
	local dir_x = dx / dist
	local dir_y = dy / dist
	local dir_z = dz / dist

	-- Move toward or away to maintain distance
	if dist > desired_dist + 2 then
		fighter.vx = dir_x * Aliens.FIGHTER_SPEED
		fighter.vy = dir_y * Aliens.FIGHTER_SPEED
		fighter.vz = dir_z * Aliens.FIGHTER_SPEED
	elseif dist < desired_dist - 2 then
		fighter.vx = -dir_x * Aliens.FIGHTER_SPEED
		fighter.vy = -dir_y * Aliens.FIGHTER_SPEED
		fighter.vz = -dir_z * Aliens.FIGHTER_SPEED
	else
		-- Strafe around player
		local strafe_angle = atan2(dz, dx) + 0.25  -- Perpendicular
		fighter.vx = cos(strafe_angle) * Aliens.FIGHTER_SPEED
		fighter.vz = sin(strafe_angle) * Aliens.FIGHTER_SPEED
		fighter.vy = 0
	end

	-- Stay above minimum altitude (avoid terrain/buildings)
	local min_altitude = 10  -- 100 meters
	if fighter.y < min_altitude then
		fighter.vy = 0.5  -- Push upward
	elseif fighter.y > 30 then
		fighter.vy = -0.2  -- Don't go too high
	end

	-- Update position
	fighter.x += fighter.vx * delta_time * 60
	fighter.y += fighter.vy * delta_time * 60
	fighter.z += fighter.vz * delta_time * 60

	-- Rotate to face player
	fighter.yaw = atan2(dx, dz)

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
