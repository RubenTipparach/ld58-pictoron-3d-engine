-- Aliens module: UFO fighters and mother ship
local Aliens = {}

-- Helper to create vectors (same as main.lua)
local function vec(x, y, z)
	return {x=x, y=y, z=z}
end

-- Alien configuration
Aliens.FIGHTER_HEALTH = 100
Aliens.MOTHER_SHIP_HEALTH = 500
Aliens.FIGHTER_SPEED = 2.0  -- Units per second
Aliens.FIGHTER_FIRE_RATE = 2  -- Bullets per second
Aliens.FIGHTER_FIRE_ARC = 0.125  -- 45 degrees (45/360 = 0.125)
Aliens.FIGHTER_FIRE_RANGE = 15  -- Units

-- Fighter AI behavior
Aliens.FIGHTER_ENGAGE_DIST = 10  -- 100 meters - get close
Aliens.FIGHTER_RETREAT_DIST = 20  -- 200 meters - retreat distance
Aliens.FIGHTER_ENGAGE_TIME = 10  -- Seconds to circle close
Aliens.FIGHTER_RETREAT_TIME = 15  -- Seconds to stay far
Aliens.FIGHTER_STATE_TIME_VARIANCE = 5  -- +/- seconds for state duration randomization
Aliens.FIGHTER_CIRCLE_SPEED = 0.3  -- Rotation speed when circling (turns per second)
Aliens.FIGHTER_CIRCLE_RADIUS = 10  -- Circle radius in units (15 meters)
Aliens.FIGHTER_CIRCLE_HEIGHT_OFFSET = 2  -- Height above player when circling
Aliens.FIGHTER_APPROACH_THRESHOLD = 2  -- Distance threshold for reaching target position
Aliens.FIGHTER_MIN_ALTITUDE = 10  -- Minimum altitude in units (100 meters)
Aliens.FIGHTER_MAX_ALTITUDE = 50  -- Maximum altitude in units (500 meters)
Aliens.FIGHTER_ALTITUDE_CLIMB_SPEED = 0.5  -- Climb speed when below min altitude
Aliens.FIGHTER_ALTITUDE_DESCEND_SPEED = -0.2  -- Descend speed when above max altitude
Aliens.FIGHTER_BANK_MULTIPLIER = 10  -- Banking intensity (roll per yaw change)
Aliens.FIGHTER_MAX_BANK = 0.083  -- Max bank angle (30 degrees = 0.083 turns)
Aliens.FIGHTER_BANK_DAMPING = 0.9  -- Roll damping when not turning

-- Mother ship behavior
Aliens.MOTHER_SHIP_FIRE_RATE = 1  -- Bullets per second (reduced from 10 for performance)
Aliens.MOTHER_SHIP_FIRE_RANGE = 25  -- Units
Aliens.MOTHER_SHIP_HOVER_HEIGHT = 10  -- Height above player when following
Aliens.MOTHER_SHIP_MAX_HEIGHT = 30  -- Maximum altitude (200 meters)
Aliens.MOTHER_SHIP_DESCEND_SPEED = -0.1  -- Descent speed

-- Wave configuration (DEBUG: Single fighter for testing)
Aliens.waves = {
	{count = 2, type = "fighter"},  -- DEBUG: Just one fighter
	{count = 4, type = "fighter"},
	{count = 5, type = "fighter"},
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
		ai_duration = Aliens.FIGHTER_ENGAGE_TIME + (rnd(2) - 1) * Aliens.FIGHTER_STATE_TIME_VARIANCE,  -- Randomized duration for current state
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
function Aliens.start_next_wave(player, landing_pads)
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
		-- Spawn mother ship above Landing Pad A, 1000m (100 units) to the north
		local pad_a = landing_pads and landing_pads.get_pad("Landing Pad A")
		local spawn_x = pad_a and pad_a.x or player.x
		local spawn_y = player.y + 20
		local spawn_z = (pad_a and pad_a.z or player.z) + 100

		local mother = Aliens.spawn_mother_ship(spawn_x, spawn_y, spawn_z)
		mother.target = player
	end

	return true
end

-- Callbacks for explosions (set from main.lua)
Aliens.on_fighter_destroyed = nil
Aliens.on_mothership_destroyed = nil

-- Callback for shooting bullets (set from main.lua)
Aliens.spawn_bullet = nil

-- Update all aliens
function Aliens.update(delta_time, player, player_on_pad)
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
			Aliens.update_fighter(fighter, delta_time, player, player_on_pad)
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
			-- Update mother ship behavior (includes bottom turret)
			Aliens.update_mother_ship(Aliens.mother_ship, delta_time, player, player_on_pad)
		end
	end

	-- Check if wave is complete (only if a wave has been started)
	if #Aliens.fighters == 0 and not Aliens.mother_ship and Aliens.current_wave > 0 then
		Aliens.wave_complete = true
	end
end

-- Update fighter AI (engage/retreat pattern)
function Aliens.update_fighter(fighter, delta_time, player, player_on_pad)
	-- Update AI state timer
	fighter.ai_timer += delta_time

	-- Direction to player
	local dx = player.x - fighter.x
	local dy = player.y - fighter.y
	local dz = player.z - fighter.z
	local dist = sqrt(dx*dx + dy*dy + dz*dz)

	-- State machine: engage (get close and circle) or retreat (fly away)
	if fighter.ai_state == "engage" then
		-- Engage: fly close and circle for randomized duration
		if fighter.ai_timer >= fighter.ai_duration then
			fighter.ai_state = "retreat"
			fighter.ai_timer = 0
			fighter.ai_duration = Aliens.FIGHTER_RETREAT_TIME + (rnd(2) - 1) * Aliens.FIGHTER_STATE_TIME_VARIANCE
		end

		local desired_dist = Aliens.FIGHTER_ENGAGE_DIST

		if dist > desired_dist + Aliens.FIGHTER_APPROACH_THRESHOLD then
			-- Move toward player
			local dir_x = dx / dist
			local dir_y = dy / dist
			local dir_z = dz / dist
			fighter.vx = dir_x * Aliens.FIGHTER_SPEED
			fighter.vy = dir_y * Aliens.FIGHTER_SPEED
			fighter.vz = dir_z * Aliens.FIGHTER_SPEED
		else
			-- Circle around player
			fighter.circle_angle += delta_time * Aliens.FIGHTER_CIRCLE_SPEED
			local circle_x = player.x + cos(fighter.circle_angle) * Aliens.FIGHTER_CIRCLE_RADIUS
			local circle_z = player.z + sin(fighter.circle_angle) * Aliens.FIGHTER_CIRCLE_RADIUS
			local circle_y = player.y + Aliens.FIGHTER_CIRCLE_HEIGHT_OFFSET

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
		-- Retreat: fly away and stay for randomized duration
		if fighter.ai_timer >= fighter.ai_duration then
			fighter.ai_state = "engage"
			fighter.ai_timer = 0
			fighter.ai_duration = Aliens.FIGHTER_ENGAGE_TIME + (rnd(2) - 1) * Aliens.FIGHTER_STATE_TIME_VARIANCE
		end

		local desired_dist = Aliens.FIGHTER_RETREAT_DIST

		if dist < desired_dist - Aliens.FIGHTER_APPROACH_THRESHOLD then
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
	if fighter.y < Aliens.FIGHTER_MIN_ALTITUDE then
		fighter.vy = Aliens.FIGHTER_ALTITUDE_CLIMB_SPEED
	elseif fighter.y > Aliens.FIGHTER_MAX_ALTITUDE then
		fighter.vy = Aliens.FIGHTER_ALTITUDE_DESCEND_SPEED
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

	-- Bank based on turn rate
	fighter.roll = -yaw_change * Aliens.FIGHTER_BANK_MULTIPLIER
	if fighter.roll > Aliens.FIGHTER_MAX_BANK then fighter.roll = Aliens.FIGHTER_MAX_BANK end
	if fighter.roll < -Aliens.FIGHTER_MAX_BANK then fighter.roll = -Aliens.FIGHTER_MAX_BANK end

	-- Smooth roll back to level when not turning much
	if abs(yaw_change) < 0.01 then
		fighter.roll = fighter.roll * Aliens.FIGHTER_BANK_DAMPING
	end

	fighter.prev_yaw = fighter.yaw
	fighter.yaw = new_yaw

	-- Update fire timer and shoot at player
	fighter.fire_timer += delta_time

	-- Fire at player when engaged and within range (but not when player is on landing pad)
	if not player_on_pad and fighter.ai_state == "engage" and dist <= Aliens.FIGHTER_FIRE_RANGE then
		if fighter.fire_timer >= (1 / Aliens.FIGHTER_FIRE_RATE) then
			-- Calculate direction to player
			local to_player_x = dx / dist
			local to_player_y = dy / dist
			local to_player_z = dz / dist

			-- Spawn bullet via callback
			if Aliens.spawn_bullet then
				Aliens.spawn_bullet(
					fighter.x, fighter.y, fighter.z,
					to_player_x, to_player_y, to_player_z,
					Aliens.FIGHTER_FIRE_RANGE
				)
			end
			fighter.fire_timer = 0
		end
	end
end

-- Update mother ship
function Aliens.update_mother_ship(mother, delta_time, player, player_on_pad)
	-- Hover above player, but cap at maximum height (200m)
	local target_height = player.y + Aliens.MOTHER_SHIP_HOVER_HEIGHT
	if target_height > Aliens.MOTHER_SHIP_MAX_HEIGHT then
		target_height = Aliens.MOTHER_SHIP_MAX_HEIGHT
	end

	if mother.y > target_height then
		mother.vy = Aliens.MOTHER_SHIP_DESCEND_SPEED
		mother.y += mother.vy * delta_time * 60
	else
		mother.vy = 0
	end

	-- Rotate slowly
	mother.yaw += delta_time * 0.2

	-- Update fire timer
	mother.fire_timer += delta_time

	-- Bottom turret: shoots two bullets at a time at player
	-- Check if player is below mothership (downward firing arc)
	local dx = player.x - mother.x
	local dy = player.y - mother.y
	local dz = player.z - mother.z
	local dist = sqrt(dx*dx + dy*dy + dz*dz)

	if not player_on_pad and dist <= Aliens.MOTHER_SHIP_FIRE_RANGE then
		-- Calculate direction to player
		local to_player_x = dx / dist
		local to_player_y = dy / dist
		local to_player_z = dz / dist

		-- Mothership's down vector (always pointing down in world space)
		local mother_down_x = 0
		local mother_down_y = -1
		local mother_down_z = 0

		-- Check firing constraints (player must be below mothership)
		local dot = to_player_x * mother_down_x + to_player_y * mother_down_y + to_player_z * mother_down_z

		if dot > 0 and mother.fire_timer >= (1 / Aliens.MOTHER_SHIP_FIRE_RATE) then
			-- Shoot two bullets with slight spread
			if Aliens.spawn_bullet then
				-- Bullet 1: slightly left
				local spread = 0.1
				Aliens.spawn_bullet(
					mother.x - spread, mother.y, mother.z,
					to_player_x, to_player_y, to_player_z,
					Aliens.MOTHER_SHIP_FIRE_RANGE
				)
				-- Bullet 2: slightly right
				Aliens.spawn_bullet(
					mother.x + spread, mother.y, mother.z,
					to_player_x, to_player_y, to_player_z,
					Aliens.MOTHER_SHIP_FIRE_RANGE
				)
			end
			mother.fire_timer = 0
		end
	end
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
