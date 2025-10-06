-- Weather module: Rain, wind, and lightning effects
local Weather = {}

-- Helper to create vectors (same as main.lua)
local function vec(x, y, z)
	return {x=x, y=y, z=z}
end

-- Weather configuration
Weather.RAIN_PARTICLE_COUNT = 100  -- Number of rain particles
Weather.RAIN_SPEED = -50  -- Downward velocity (negative = down, faster for better streak)
--Weather.RAIN_SPRITE = 23  -- Sprite ID for rain particles

-- Rain streak visual tuning
Weather.RAIN_STREAK_SCALE = 2.0  -- Base scaling factor for streak length
Weather.RAIN_SHIP_MOTION_FACTOR = 5.0  -- How much ship motion affects streak direction (0-2, 1=normal)
Weather.RAIN_WIND_MOTION_FACTOR = 2.0  -- How much wind affects streak direction (0-2, 1=normal)

-- Wind configuration (altitude-based strength)
Weather.WIND_LIGHT_STRENGTH = 0.03  -- Light wind 0-100m (10 units)
Weather.WIND_MEDIUM_STRENGTH = 0.08  -- Medium wind 100-200m (10-20 units)
Weather.WIND_HEAVY_STRENGTH = 0.15  -- Heavy wind 200m+ (20+ units)
Weather.WIND_CHANGE_MIN = 10  -- Minimum seconds between wind direction changes
Weather.WIND_CHANGE_MAX = 20  -- Maximum seconds between wind direction changes

-- Lightning configuration
Weather.LIGHTNING_MIN_INTERVAL = 10  -- Minimum seconds between lightning
Weather.LIGHTNING_MAX_INTERVAL = 20  -- Maximum seconds between lightning
Weather.LIGHTNING_FLASH_COUNT = 3  -- Number of flashes per lightning event
Weather.LIGHTNING_FLASH_DURATION = 0.1  -- Duration of each flash (seconds)
Weather.LIGHTNING_FLASH_GAP = 0.2  -- Gap between flashes (seconds)

-- Rain depth color mapping (farthest to closest)
Weather.RAIN_COLORS = {1, 16, 12, 28}

-- Weather state
Weather.enabled = false
Weather.rain_particles = {}
Weather.lightning_timer = 0
Weather.next_lightning_time = 0
Weather.lightning_active = false
Weather.lightning_flash_index = 0
Weather.lightning_flash_timer = 0
Weather.original_skybox_sprite = nil
Weather.lightning_skybox_sprite = 23

-- Wind state
Weather.wind_direction_x = 0
Weather.wind_direction_z = 0
Weather.wind_timer = 0
Weather.next_wind_change = 0

-- Initialize weather system
function Weather.init()
	Weather.rain_particles = {}

	-- Create rain particles
	for i = 1, Weather.RAIN_PARTICLE_COUNT do
		add(Weather.rain_particles, {
			x = (rnd() - 0.5) * 400,  -- Spread across map
			y = rnd() * 80 + 20,  -- Height range 20-100
			z = (rnd() - 0.5) * 400,  -- Spread across map
			vx = 0,
			vy = Weather.RAIN_SPEED,
			vz = 0,
			active = true
		})
	end

	-- Initialize lightning timer
	Weather.lightning_timer = 0
	Weather.next_lightning_time = Weather.LIGHTNING_MIN_INTERVAL + rnd() * (Weather.LIGHTNING_MAX_INTERVAL - Weather.LIGHTNING_MIN_INTERVAL)
	Weather.lightning_active = false
	Weather.lightning_flash_index = 0
	Weather.lightning_flash_timer = 0

	-- Initialize wind with random direction
	local angle = rnd() * 1  -- Random angle (0-1 = 0-360 degrees)
	Weather.wind_direction_x = cos(angle)
	Weather.wind_direction_z = sin(angle)
	Weather.wind_timer = 0
	Weather.next_wind_change = Weather.WIND_CHANGE_MIN + rnd() * (Weather.WIND_CHANGE_MAX - Weather.WIND_CHANGE_MIN)
end

-- Update weather system
function Weather.update(delta_time, camera, ship_y)
	if not Weather.enabled then return end

	-- Update rain particles
	for particle in all(Weather.rain_particles) do
		if particle.active then
			-- Rain falls straight down in world space (plus wind)
			particle.y += Weather.RAIN_SPEED * delta_time  -- RAIN_SPEED units per second

			-- Reset particle if it falls well below ground (allow it to fall below visible ground)
			if particle.y < -20 then
				-- Respawn above camera with random offset
				particle.x = camera.x + (rnd() - 0.5) * 80
				particle.y = camera.y + 40 + rnd() * 20
				particle.z = camera.z + (rnd() - 0.5) * 80
			end

			-- If particle is too far from camera, respawn near camera
			local dx_cam = particle.x - camera.x
			local dz_cam = particle.z - camera.z
			if dx_cam*dx_cam + dz_cam*dz_cam > 60*60 then
				particle.x = camera.x + (rnd() - 0.5) * 80
				particle.y = camera.y + 40 + rnd() * 20
				particle.z = camera.z + (rnd() - 0.5) * 80
			end
		end
	end

	-- Update wind direction
	Weather.wind_timer += delta_time
	if Weather.wind_timer >= Weather.next_wind_change then
		-- Change wind to random direction
		local angle = rnd() * 1  -- Random angle (0-1 = 0-360 degrees)
		Weather.wind_direction_x = cos(angle)
		Weather.wind_direction_z = sin(angle)
		Weather.wind_timer = 0
		Weather.next_wind_change = Weather.WIND_CHANGE_MIN + rnd() * (Weather.WIND_CHANGE_MAX - Weather.WIND_CHANGE_MIN)
	end

	-- Update lightning
	Weather.lightning_timer += delta_time

	if Weather.lightning_active then
		Weather.lightning_flash_timer += delta_time

		-- Check if current flash is done
		if Weather.lightning_flash_timer >= Weather.LIGHTNING_FLASH_DURATION then
			Weather.lightning_flash_timer = 0
			Weather.lightning_flash_index += 1

			-- Check if all flashes are done
			if Weather.lightning_flash_index >= Weather.LIGHTNING_FLASH_COUNT * 2 then
				Weather.lightning_active = false
				Weather.lightning_flash_index = 0
				Weather.lightning_timer = 0
				Weather.next_lightning_time = Weather.LIGHTNING_MIN_INTERVAL + rnd() * (Weather.LIGHTNING_MAX_INTERVAL - Weather.LIGHTNING_MIN_INTERVAL)
			end
		end
	else
		-- Check if it's time for lightning
		if Weather.lightning_timer >= Weather.next_lightning_time then
			Weather.lightning_active = true
			Weather.lightning_flash_index = 0
			Weather.lightning_flash_timer = 0
		end
	end
end

-- Get current wind velocity based on altitude
function Weather.get_wind_velocity(altitude)
	if not Weather.enabled then return 0, 0 end

	-- Determine wind strength based on altitude
	local wind_strength = 0
	if altitude >= 20 then  -- 200m+ (20 units)
		wind_strength = Weather.WIND_HEAVY_STRENGTH
	elseif altitude >= 10 then  -- 100-200m (10-20 units)
		wind_strength = Weather.WIND_MEDIUM_STRENGTH
	elseif altitude >= 0 then  -- 0-100m (0-10 units)
		wind_strength = Weather.WIND_LIGHT_STRENGTH
	end

	return Weather.wind_direction_x * wind_strength, Weather.wind_direction_z * wind_strength
end

-- Apply wind force to ship (called from main update)
function Weather.apply_wind(ship, ship_y, is_landed)
	if not Weather.enabled then return end
	if is_landed then return end  -- No wind when landed

	local wind_vx, wind_vz = Weather.get_wind_velocity(ship_y)

	-- Apply wind force
	if wind_vx ~= 0 or wind_vz ~= 0 then
		ship.vx += wind_vx * 0.016  -- Assume ~60fps
		ship.vz += wind_vz * 0.016
	end
end

-- Render rain particles as billboards (like smoke particles)
function Weather.render_rain(render_mesh_func, camera)
	if not Weather.enabled then return {} end

	local all_rain_faces = {}

	for particle in all(Weather.rain_particles) do
		if particle.active then
			-- Calculate distance for depth-based color
			local dx = particle.x - camera.x
			local dy = particle.y - camera.y
			local dz = particle.z - camera.z
			local dist = sqrt(dx*dx + dy*dy + dz*dz)

			-- Map distance to color (farthest to closest: 1, 16, 12, 28)
			local color_index = min(4, max(1, flr(dist / 30) + 1))
			local color = Weather.RAIN_COLORS[color_index]

			-- Create thin vertical line (very narrow billboard)
			local size = 0.01  -- Very thin
			local length = 0.3  -- Line length
			local rain_verts = {
				vec(-size, 0, 0),
				vec(size, 0, 0),
				vec(size, -length, 0),
				vec(-size, -length, 0)
			}

			local rain_faces = {
				{1, 2, 3, color},
				{1, 3, 4, color}
			}

			-- Render rain particle as billboard at particle position
			local faces = render_mesh_func(rain_verts, rain_faces, particle.x, particle.y, particle.z, nil, false)
			for _, f in ipairs(faces) do
				add(all_rain_faces, f)
			end
		end
	end

	return all_rain_faces
end

-- Draw rain as 2D lines (projected from 3D positions)
function Weather.draw_rain_lines(camera, ship)
	if not Weather.enabled then return end

	-- Get current wind velocity at ship altitude
	local wind_vx, wind_vz = Weather.get_wind_velocity(ship.y)

	for particle in all(Weather.rain_particles) do
		if particle.active then
			-- Calculate rain velocity in world space (always falling down)
			local rain_world_vx = wind_vx * Weather.RAIN_WIND_MOTION_FACTOR
			local rain_world_vy = Weather.RAIN_SPEED / 60  -- Convert to per-frame velocity (negative = down)
			local rain_world_vz = wind_vz * Weather.RAIN_WIND_MOTION_FACTOR

			-- Calculate relative velocity (what we see from ship's perspective)
			local rel_vx = rain_world_vx + (ship.vx * Weather.RAIN_SHIP_MOTION_FACTOR)
			local rel_vy = rain_world_vy + (ship.vy * Weather.RAIN_SHIP_MOTION_FACTOR)
			local rel_vz = rain_world_vz + (ship.vz * Weather.RAIN_SHIP_MOTION_FACTOR)

			-- Start point: actual particle position in world space
			local start_x = particle.x
			local start_y = particle.y
			local start_z = particle.z

			-- End point: where particle will be based on relative velocity
			local end_x = start_x + rel_vx * Weather.RAIN_STREAK_SCALE
			local end_y = start_y + rel_vy * Weather.RAIN_STREAK_SCALE
			local end_z = start_z + rel_vz * Weather.RAIN_STREAK_SCALE

			-- Transform start point to camera space
			local dx = start_x - camera.x
			local dy = start_y - camera.y
			local dz = start_z - camera.z

			-- Apply camera rotation
			local cos_ry = cos(camera.ry)
			local sin_ry = sin(camera.ry)
			local cos_rx = cos(camera.rx)
			local sin_rx = sin(camera.rx)

			-- Rotate start point around Y (yaw)
			local x1 = dx * cos_ry - dz * sin_ry
			local z1 = dx * sin_ry + dz * cos_ry

			-- Rotate start point around X (pitch)
			local y2 = dy * cos_rx - z1 * sin_rx
			local z2 = dy * sin_rx + z1 * cos_rx

			-- Only draw if start point is in front of camera
			if z2 > 0.1 then
				-- Project start point to screen
				local fov = 1.5
				local screen_x1 = 240 + (x1 / z2) * 200 * fov
				local screen_y1 = 135 - (y2 / z2) * 200 * fov

				-- Transform end point to camera space
				local dx2 = end_x - camera.x
				local dy2 = end_y - camera.y
				local dz2 = end_z - camera.z

				-- Rotate end point around Y (yaw)
				local x1_end = dx2 * cos_ry - dz2 * sin_ry
				local z1_end = dx2 * sin_ry + dz2 * cos_ry

				-- Rotate end point around X (pitch)
				local y2_end = dy2 * cos_rx - z1_end * sin_rx
				local z2_end = dy2 * sin_rx + z1_end * cos_rx

				-- Project end point to screen
				if z2_end > 0.1 then
					local screen_x2 = 240 + (x1_end / z2_end) * 200 * fov
					local screen_y2 = 135 - (y2_end / z2_end) * 200 * fov

					-- Calculate distance for color
					local dist = sqrt(dx*dx + dy*dy + dz*dz)
					local color_index = min(4, max(1, flr(dist / 30) + 1))
					local color = Weather.RAIN_COLORS[color_index]

					-- Draw rain streak
					line(screen_x1, screen_y1, screen_x2, screen_y2, color)
				end
			end
		end
	end
end

-- Check if lightning is flashing (for skybox toggle)
function Weather.is_lightning_flash()
	if not Weather.enabled then return false end
	if not Weather.lightning_active then return false end

	-- Flash on even indices (0, 2, 4), off on odd (1, 3, 5)
	return Weather.lightning_flash_index % 2 == 0
end

-- Enable/disable weather
function Weather.set_enabled(enabled)
	Weather.enabled = enabled
	if enabled and #Weather.rain_particles == 0 then
		Weather.init()
	end
end

return Weather
