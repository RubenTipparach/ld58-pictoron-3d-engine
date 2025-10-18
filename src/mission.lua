-- Mission module: Mission scripting and objective tracking
local Cargo = include("src/cargo.lua")
local AudioManager = include("src/audio_manager.lua")

local Mission = {}

-- Reference to LandingPads module (set externally from main.lua)
Mission.LandingPads = nil

-- MISSION PARAMETERS (EASY TO ADJUST!)

-- General mission settings
Mission.LANDING_PAD_RADIUS = 3  -- Landing pad radius in units (3 units = 30 meters)
Mission.CARGO_DELIVERY_DELAY = 1.0  -- Time to wait on pad before cargo delivery (seconds)
Mission.OBJECTIVES_BOX_WIDTH = 290  -- Width of mission objectives box (pixels)
Mission.OBJECTIVES_BOX_X = 5  -- X position of objectives box
Mission.OBJECTIVES_BOX_Y = 5  -- Y position of objectives box

-- Mission 1: Engine Test
Mission.M1_HOVER_DURATION = 5  -- How long to hover in seconds

-- Mission 2: Cargo Delivery
Mission.M2_CARGO_DISTANCE_X = -100  -- Cargo X offset from landing pad (units, negative = west)
Mission.M2_CARGO_DISTANCE_Z = 20     -- Cargo Z offset from landing pad (units)
Mission.M2_CARGO_COUNT = 1          -- Number of cargo boxes

-- Mission 3: Scientific Mission
Mission.M3_BUILDING_ID = 10         -- Building ID for Command Tower
Mission.M3_LANDING_PAD_ID = 4       -- Landing Pad D (ID 4) - Crater expedition staging area
Mission.M3_CARGO_COUNT = 1          -- Number of scientist pods

-- Mission 4: Ocean Rescue
Mission.M4_CARGO_ASEPRITE_X = 105   -- Cargo pickup location
Mission.M4_CARGO_ASEPRITE_Z = 57    -- Cargo pickup location
Mission.M4_LANDING_PAD_ID = 2       -- Landing Pad B (ID 2)
Mission.M4_CARGO_COUNT = 1          -- Number of cargo boxes

-- Mission 5: Secret Weapon
Mission.M5_CARGO_ASEPRITE_X = 54    -- Cargo location
Mission.M5_CARGO_ASEPRITE_Z = 60    -- Cargo location
Mission.M5_LANDING_PAD_ID = 3       -- Landing Pad C (ID 3)
Mission.M5_CARGO_COUNT = 1          -- Number of cargo boxes

-- Mission state
Mission.current_objectives = {}
Mission.cargo_objects = {}
Mission.total_cargo = 0
Mission.collected_cargo = 0
Mission.active = false
Mission.complete_flag = false
Mission.landing_pad_pos = {x = 0, y = 0, z = 0}  -- Landing pad position for navigation
Mission.required_landing_pad_id = nil  -- ID of the target landing pad for this mission
Mission.current_target = {x = 0, z = 0}  -- Current mission objective location (for compass)
Mission.show_pause_menu = false
Mission.cargo_just_delivered = false  -- Flag for snapping ship to landed position
Mission.type = nil  -- Mission type: "hover", "cargo", etc.
Mission.hover_timer = 0  -- Timer for hover mission
Mission.hover_duration = 0  -- Required hover time
Mission.mission_name = ""  -- Name of current mission
Mission.current_mission_num = nil  -- Current mission number (1-5)

-- Initialize a hover mission (take off, hover, land)
-- hover_duration: how long to hover in seconds
-- landing_pad_x, landing_pad_z: landing pad position
-- landing_pad_id: ID of the landing pad (default 1)
function Mission.start_hover_mission(hover_duration, landing_pad_x, landing_pad_z, landing_pad_id)
	Mission.active = true
	Mission.complete_flag = false
	Mission.type = "hover"
	Mission.hover_timer = 0
	Mission.hover_duration = hover_duration
	Mission.show_pause_menu = false

	-- Store landing pad position and ID
	Mission.landing_pad_pos.x = landing_pad_x
	Mission.landing_pad_pos.z = landing_pad_z
	Mission.required_landing_pad_id = landing_pad_id or 1

	-- Set target to landing pad (hover mission always returns to start pad)
	Mission.current_target.x = landing_pad_x
	Mission.current_target.z = landing_pad_z

	-- Set objective text
	Mission.current_objectives = {
		"Take off and hover for " .. hover_duration .. " seconds",
		"Then land back on the pad",
		"",
		"[TAB] Menu  [G] Hide Mission  [C] Show Controls"
	}
end

-- Initialize a mission with cargo pickups
-- cargo_coords: array of {aseprite_x, aseprite_z, world_y (optional)} coordinates
-- landing_pad_x, landing_pad_z: landing pad position for navigation
-- landing_pad_id: ID of the landing pad to deliver to (default 1)
function Mission.start_cargo_mission(cargo_coords, landing_pad_x, landing_pad_z, landing_pad_id)
	Mission.active = true
	Mission.complete_flag = false
	Mission.type = "cargo"
	Mission.cargo_objects = {}
	Mission.total_cargo = #cargo_coords
	Mission.collected_cargo = 0
	Mission.show_pause_menu = false

	-- Store landing pad position and ID
	Mission.landing_pad_pos.x = landing_pad_x or 0
	Mission.landing_pad_pos.z = landing_pad_z or 0
	Mission.required_landing_pad_id = landing_pad_id or 1

	-- Create cargo objects at specified coordinates
	for i, coord in ipairs(cargo_coords) do
		local cargo = Cargo.create({
			aseprite_x = coord.aseprite_x,
			aseprite_z = coord.aseprite_z,
			use_heightmap = coord.world_y == nil,  -- Only use heightmap if world_y not specified
			world_y = coord.world_y,  -- Optional custom Y position
			id = i
		})
		add(Mission.cargo_objects, cargo)
	end

	-- Set initial target to first cargo location (will switch to landing pad when cargo picked up)
	if Mission.cargo_objects[1] then
		Mission.current_target.x = Mission.cargo_objects[1].x
		Mission.current_target.z = Mission.cargo_objects[1].z
	else
		-- No cargo, point to landing pad
		local target_pad = Mission.LandingPads.get_pad(Mission.required_landing_pad_id)
		Mission.current_target.x = target_pad.x
		Mission.current_target.z = target_pad.z
	end

	-- Set objective text with button prompts for mission 1
	Mission.current_objectives = {
		"Collect all cargo and return to Landing Pad A",
		"Cargo: 0/" .. Mission.total_cargo,
		"Land with engines off to deliver",
		"[TAB] Menu  [G] Hide Mission  [C] Show Controls"
	}
end

-- Update mission state (check pickups, update objectives)
function Mission.update(delta_time, ship_x, ship_y, ship_z, right_click_held, ship_landed, ship_pitch, ship_yaw, ship_roll, engines_off, current_landing_pad)
	if not Mission.active then return end
	if Mission.complete_flag then return end

	-- Handle hover mission
	if Mission.type == "hover" then
		-- ship_landed parameter is actually is_on_landing_pad (from main.lua)
		local is_on_pad = ship_landed

		-- Count hover time only when NOT on the landing pad
		if not is_on_pad then
			Mission.hover_timer += delta_time
			-- Update objective with timer
			local remaining = Mission.hover_duration - Mission.hover_timer
			if remaining > 0 then
				Mission.current_objectives[1] = "Hover for " .. flr(remaining + 1) .. " more seconds"
			else
				Mission.current_objectives[1] = "Land back on the pad to complete"
			end
		end

		-- Check if mission complete (hovered long enough and landed on pad)
		if Mission.hover_timer >= Mission.hover_duration and is_on_pad then
			Mission.complete()
		end
		return
	end

	-- Handle cargo mission
	-- Update all cargo with new pickup system
	for cargo in all(Mission.cargo_objects) do
		Cargo.update(cargo, delta_time, ship_x, ship_y, ship_z, right_click_held, ship_landed, ship_pitch, ship_yaw, ship_roll)

		-- Count attached cargo
		if Cargo.is_attached(cargo) and not cargo.was_attached then
			cargo.was_attached = true
			Mission.collected_cargo += 1
			Mission.current_objectives[2] = "Cargo: " .. Mission.collected_cargo .. "/" .. Mission.total_cargo

			-- Switch target to the required landing pad when cargo is picked up
			-- Debug: Check what's nil
			if not Mission.LandingPads then
				stop("ERROR: Mission.LandingPads is nil!")
			end
			if not Mission.required_landing_pad_id then
				stop("ERROR: Mission.required_landing_pad_id is nil!")
			end
			local target_pad = Mission.LandingPads.get_pad(Mission.required_landing_pad_id)
			if not target_pad then
				stop("ERROR: get_pad returned nil for ID " .. Mission.required_landing_pad_id)
			end
			Mission.current_target.x = target_pad.x
			Mission.current_target.z = target_pad.z
		end

		-- Check if cargo delivered when landed on pad with cargo attached and engines off
		-- Also verify we're on the correct landing pad
		local on_correct_pad = current_landing_pad and current_landing_pad.id == Mission.required_landing_pad_id

		if cargo.state == "attached" and not cargo.was_delivered and ship_landed and engines_off and on_correct_pad then
			-- Initialize delivery timer if not started
			if not cargo.delivery_timer then
				cargo.delivery_timer = 0
			end

			-- Increment timer
			cargo.delivery_timer += delta_time

			-- Deliver after delay
			if cargo.delivery_timer >= Mission.CARGO_DELIVERY_DELAY then
				cargo.state = "delivered"
				cargo.was_delivered = true
				Mission.cargo_just_delivered = true  -- Set flag to snap ship
			end
		else
			-- Reset timer if conditions not met
			cargo.delivery_timer = nil
		end
	end

	-- Check if all cargo delivered to landing pad (only for cargo missions)
	if Mission.total_cargo > 0 then
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
end

-- Complete the mission
function Mission.complete()
	Mission.complete_flag = true
	
	-- Start mission complete music
	print("Mission complete - starting music")
	if AudioManager and AudioManager.start_mission_complete_music then
		AudioManager.start_mission_complete_music()
		print("Mission complete music started")
	else
		print("AudioManager not available")
	end

	-- Mission-specific completion text
	local completion_text = "All cargo delivered"
	if Mission.current_mission_num == 6 then
		completion_text = "All alien waves destroyed!"
	end

	Mission.current_objectives = {
		"MISSION COMPLETE!",
		completion_text,
		"",
		"[Q] Return to Menu"
	}

	-- Unlock next mission (if not in testing mode)
	if Mission.current_mission_num then
		local next_mission_key = "mission_" .. (Mission.current_mission_num + 1)
		local progress = fetch("/appdata/mission_progress.pod") or {}
		progress[next_mission_key] = true
		store("/appdata/mission_progress.pod", progress)
	end
end

-- Reset mission
function Mission.reset()
	Mission.active = false
	Mission.cargo_objects = {}
	Mission.total_cargo = 0
	Mission.collected_cargo = 0
	Mission.current_objectives = {}
	Mission.complete_flag = false
	Mission.type = nil
	Mission.hover_timer = 0
	Mission.hover_duration = 0
	Mission.mission_name = ""
	Mission.cargo_just_delivered = false
	Mission.show_pause_menu = false
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
	-- Always draw mission box (even if mission not active, for debugging)
	-- Mission-specific features only draw if active

	-- Draw tether lines and prompts for cargo (only if mission active)
	local show_prompt = false
	if Mission.active and not Mission.complete_flag then
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
	local box_x = Mission.OBJECTIVES_BOX_X
	local box_y = Mission.OBJECTIVES_BOX_Y
	local box_width = Mission.OBJECTIVES_BOX_WIDTH
	local box_height = #Mission.current_objectives * 8 + 10
	-- Add extra height for mission name if present
	if Mission.mission_name and Mission.mission_name ~= "" then
		box_height += 10
	end

	-- Draw dithered background
	fillp(0b0101101001011010, 0b0101101001011010)
	rectfill(box_x, box_y, box_x + box_width, box_y + box_height, 1)
	fillp()

	-- Draw border
	rect(box_x, box_y, box_x + box_width, box_y + box_height, 6)

	-- Draw mission name header if available
	local text_y = box_y + 5
	if Mission.mission_name and Mission.mission_name ~= "" then
		-- Draw mission name in header color
		print(Mission.mission_name, box_x + 5, text_y, 11)
		text_y += 10  -- Add spacing after mission name
	end

	-- Draw objectives
	if #Mission.current_objectives > 0 then
		for i, objective in ipairs(Mission.current_objectives) do
			-- Highlight first objective in hover missions (the timer)
			if Mission.type == "hover" and i == 1 then
				-- Draw background rectangle for timer
				local text_width = #objective * 4
				rectfill(box_x + 3, text_y + (i - 1) * 8 - 1, box_x + 7 + text_width, text_y + (i - 1) * 8 + 6, 1)
				-- Draw timer text in bright yellow
				print(objective, box_x + 5, text_y + (i - 1) * 8, 10)
			else
				print(objective, box_x + 5, text_y + (i - 1) * 8, 7)
			end
		end
	else
		-- Debug message when no objectives
		print("No mission loaded", box_x + 5, text_y, 8)
	end

	-- Draw pickup prompt if hovering near cargo
	if show_prompt then
		local prompt_y = 135 + 50  -- Below center
		print("[Hold Right-Click] Pickup Cargo", 240 - #"[Hold Right-Click] Pickup Cargo" * 2, prompt_y, 11)
	end

	-- Draw mission complete box (centered)
	if Mission.complete_flag then
		local screen_center_x = 240  -- Screen width 480 / 2
		local complete_box_width = 250
		local complete_box_height = 60
		local complete_box_x1 = screen_center_x - complete_box_width / 2
		local complete_box_x2 = screen_center_x + complete_box_width / 2
		local complete_box_y = 135 - complete_box_height / 2

		-- Draw dithered background
		fillp(0b0101101001011010, 0b0101101001011010)
		rectfill(complete_box_x1, complete_box_y, complete_box_x2, complete_box_y + complete_box_height, 1)
		fillp()

		-- Draw border
		rect(complete_box_x1, complete_box_y, complete_box_x2, complete_box_y + complete_box_height, 10)

		-- Draw text centered with shadow
		for i, objective in ipairs(Mission.current_objectives) do
			local text_x = screen_center_x - #objective * 2
			local text_y = complete_box_y + 10 + (i - 1) * 10
			-- Shadow
			print(objective, text_x + 1, text_y + 1, 0)
			-- Main text
			print(objective, text_x, text_y, 7)
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
	print("[Tab] Resume", 240 - #"[Tab] Resume" * 2, box_y + 30, 7)
	print("[Q] Return to Menu", 240 - #"[Q] Return to Menu" * 2, box_y + 45, 7)
end

return Mission
