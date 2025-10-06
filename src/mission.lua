-- Mission module: Mission scripting and objective tracking
local Cargo = include("src/cargo.lua")

local Mission = {}

-- Mission state
Mission.current_objectives = {}
Mission.cargo_objects = {}
Mission.total_cargo = 0
Mission.collected_cargo = 0
Mission.active = false
Mission.complete_flag = false
Mission.landing_pad_pos = {x = 0, y = 0, z = 0}  -- Landing pad position for navigation
Mission.show_pause_menu = false

-- Initialize a mission with cargo pickups
-- cargo_coords: array of {aseprite_x, aseprite_z} coordinates
-- landing_pad_x, landing_pad_z: landing pad position for navigation
function Mission.start_cargo_mission(cargo_coords, landing_pad_x, landing_pad_z)
	Mission.active = true
	Mission.complete_flag = false
	Mission.cargo_objects = {}
	Mission.total_cargo = #cargo_coords
	Mission.collected_cargo = 0
	Mission.show_pause_menu = false

	-- Store landing pad position
	Mission.landing_pad_pos.x = landing_pad_x or 0
	Mission.landing_pad_pos.z = landing_pad_z or 0

	-- Create cargo objects at specified coordinates
	for i, coord in ipairs(cargo_coords) do
		local cargo = Cargo.create({
			aseprite_x = coord.aseprite_x,
			aseprite_z = coord.aseprite_z,
			use_heightmap = true,
			id = i
		})
		add(Mission.cargo_objects, cargo)
	end

	-- Set objective text with button prompts for mission 1
	Mission.current_objectives = {
		"Collect all cargo and return to landing pad",
		"Cargo: 0/" .. Mission.total_cargo,
		"",
		"[TAB] Menu  [G] Hide Mission"
	}
end

-- Update mission state (check pickups, update objectives)
function Mission.update(delta_time, ship_x, ship_y, ship_z, right_click_held, ship_landed, ship_pitch, ship_yaw, ship_roll)
	if not Mission.active then return end
	if Mission.complete_flag then return end

	-- Update all cargo with new pickup system
	for cargo in all(Mission.cargo_objects) do
		Cargo.update(cargo, delta_time, ship_x, ship_y, ship_z, right_click_held, ship_landed, ship_pitch, ship_yaw, ship_roll)

		-- Count attached cargo
		if Cargo.is_attached(cargo) and not cargo.was_attached then
			cargo.was_attached = true
			Mission.collected_cargo += 1
			Mission.current_objectives[2] = "Cargo: " .. Mission.collected_cargo .. "/" .. Mission.total_cargo
		end

		-- Check if cargo touches landing pad (deliver cargo)
		if cargo.state == "attached" and not cargo.was_delivered then
			-- Check distance to landing pad
			local dx = cargo.x - Mission.landing_pad_pos.x
			local dz = cargo.z - Mission.landing_pad_pos.z
			local dist = sqrt(dx*dx + dz*dz)
			local pad_radius = 3  -- Landing pad radius (3 units = 30 meters)

			if dist < pad_radius and cargo.y < 5 then  -- Close to pad and low altitude
				cargo.state = "delivered"
				cargo.was_delivered = true
			end
		end
	end

	-- Check if all cargo delivered to landing pad
	local all_delivered = true
	for cargo in all(Mission.cargo_objects) do
		if cargo.state != "delivered" then
			all_delivered = false
			break
		end
	end

	if all_delivered and Mission.collected_cargo >= Mission.total_cargo then
		Mission.complete()
	end
end

-- Complete the mission
function Mission.complete()
	Mission.complete_flag = true
	Mission.current_objectives = {
		"MISSION COMPLETE!",
		"All cargo delivered",
		"",
		"[Any Key] Return to Menu"
	}
end

-- Reset mission
function Mission.reset()
	Mission.active = false
	Mission.cargo_objects = {}
	Mission.total_cargo = 0
	Mission.collected_cargo = 0
	Mission.current_objectives = {}
end

-- Draw dotted navigation line to target
function Mission.draw_nav_line(camera, from_x, from_z, to_x, to_z, color)
	-- Project start and end points to screen space
	local fov = 70
	local fov_rad = fov * 0.5 * 0.0174533
	local tan_half_fov = sin(fov_rad) / cos(fov_rad)

	-- Transform to camera space
	local cos_ry, sin_ry = cos(camera.ry), sin(camera.ry)
	local cos_rx, sin_rx = cos(camera.rx), sin(camera.rx)

	local function project_point(wx, wy, wz)
		local x, y, z = wx - camera.x, wy - camera.y, wz - camera.z
		local x2 = x * cos_ry - z * sin_ry
		local z2 = x * sin_ry + z * cos_ry
		local y2 = y * cos_rx - z2 * sin_rx
		local z3 = y * sin_rx + z2 * cos_rx + 5

		if z3 > 0.1 then
			local sx = x2 / z3 * (270 / tan_half_fov) + 240
			local sy = y2 / z3 * (270 / tan_half_fov) + 135
			return sx, sy, true
		end
		return 0, 0, false
	end

	-- Draw dotted line
	local sx1, sy1, vis1 = project_point(from_x, 0, from_z)
	local sx2, sy2, vis2 = project_point(to_x, 0, to_z)

	if vis1 and vis2 then
		-- Draw dashed line
		local dx = sx2 - sx1
		local dy = sy2 - sy1
		local dist = sqrt(dx*dx + dy*dy)
		local segments = dist / 4
		for i = 0, segments do
			if i % 2 == 0 then
				local t1 = i / segments
				local t2 = min((i + 1) / segments, 1)
				line(sx1 + dx * t1, sy1 + dy * t1, sx1 + dx * t2, sy1 + dy * t2, color)
			end
		end
	end
end

-- Draw tether line from ship to cargo
function Mission.draw_tether_line(camera, ship_x, ship_y, ship_z, cargo_x, cargo_y, cargo_z)
	-- Project both points to screen space
	local fov = 70
	local fov_rad = fov * 0.5 * 0.0174533
	local tan_half_fov = sin(fov_rad) / cos(fov_rad)

	local cos_ry, sin_ry = cos(camera.ry), sin(camera.ry)
	local cos_rx, sin_rx = cos(camera.rx), sin(camera.rx)

	local function project_point(wx, wy, wz)
		local x, y, z = wx - camera.x, wy - camera.y, wz - camera.z
		local x2 = x * cos_ry - z * sin_ry
		local z2 = x * sin_ry + z * cos_ry
		local y2 = y * cos_rx - z2 * sin_rx
		local z3 = y * sin_rx + z2 * cos_rx + 5

		if z3 > 0.1 then
			local sx = x2 / z3 * (270 / tan_half_fov) + 240
			local sy = y2 / z3 * (270 / tan_half_fov) + 135
			return sx, sy, true
		end
		return 0, 0, false
	end

	local sx1, sy1, vis1 = project_point(ship_x, ship_y, ship_z)
	local sx2, sy2, vis2 = project_point(cargo_x, cargo_y, cargo_z)

	if vis1 and vis2 then
		line(sx1, sy1, sx2, sy2, 11)  -- Cyan tether line
	end
end

-- Draw mission UI (objectives and navigation)
function Mission.draw_ui(camera, ship_x, ship_y, ship_z, minimap_y)
	if not Mission.active then return end

	-- Draw tether lines and prompts for cargo
	local show_prompt = false
	if not Mission.complete_flag then
		for cargo in all(Mission.cargo_objects) do
			-- Draw tether line when tethering
			if Cargo.is_tethering(cargo) then
				Mission.draw_tether_line(camera, ship_x, ship_y, ship_z, cargo.x, cargo.y, cargo.z)
			end

			-- Check if we should show pickup prompt
			if Cargo.show_pickup_prompt(cargo) then
				show_prompt = true
			end
		end
	end

	-- Draw objectives box at top of screen
	local box_x = 5
	local box_y = 5  -- Top of screen
	local box_width = 240
	local box_height = #Mission.current_objectives * 8 + 10

	-- Draw dithered background
	fillp(0b0101101001011010, 0b0101101001011010)
	rectfill(box_x, box_y, box_x + box_width, box_y + box_height, 1)
	fillp()

	-- Draw border
	rect(box_x, box_y, box_x + box_width, box_y + box_height, 6)

	-- Draw objectives
	for i, objective in ipairs(Mission.current_objectives) do
		print(objective, box_x + 5, box_y + 5 + (i - 1) * 8, 7)
	end

	-- Draw pickup prompt if hovering near cargo
	if show_prompt then
		local prompt_y = 135 + 50  -- Below center
		print("[Hold Right-Click] Pickup Cargo", 240 - #"[Hold Right-Click] Pickup Cargo" * 2, prompt_y, 11)
	end

	-- Draw mission complete box (centered)
	if Mission.complete_flag then
		local complete_box_width = 250
		local complete_box_height = 60
		local complete_box_x = 240 - complete_box_width / 2
		local complete_box_y = 135 - complete_box_height / 2

		-- Draw dithered background
		fillp(0b0101101001011010, 0b0101101001011010)
		rectfill(complete_box_x, complete_box_y, complete_box_x + complete_box_width, complete_box_y + complete_box_height, 1)
		fillp()

		-- Draw border
		rect(complete_box_x, complete_box_y, complete_box_x + complete_box_width, complete_box_y + complete_box_height, 10)

		-- Draw text centered
		for i, objective in ipairs(Mission.current_objectives) do
			print(objective, 240 - #objective * 2, complete_box_y + 10 + (i - 1) * 10, 7)
		end
	end
end

-- Draw pause menu
function Mission.draw_pause_menu()
	if not Mission.show_pause_menu then return end

	local box_width = 200
	local box_height = 80
	local box_x = 240 - box_width / 2
	local box_y = 135 - box_height / 2

	-- Draw dithered background
	fillp(0b0101101001011010, 0b0101101001011010)
	rectfill(box_x, box_y, box_x + box_width, box_y + box_height, 1)
	fillp()

	-- Draw border
	rect(box_x, box_y, box_x + box_width, box_y + box_height, 6)

	-- Draw text
	print("PAUSED", 240 - #"PAUSED" * 2, box_y + 10, 7)
	print("[ESC] Resume", 240 - #"[ESC] Resume" * 2, box_y + 30, 7)
	print("[Q] Return to Menu", 240 - #"[Q] Return to Menu" * 2, box_y + 45, 7)
end

return Mission
