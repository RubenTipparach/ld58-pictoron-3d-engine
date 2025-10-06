-- Menu module: Main menu with space background and mission selection
local Constants = include("src/constants.lua")
local Renderer = include("src/renderer.lua")

-- Ship display settings (easy tweaking)
-- Position
local SHIP_X = -2
local SHIP_Y = 3
local SHIP_Z = 0.5  -- Distance from camera
-- Rotation (modified by Q,W,E,A,S,D keys in debug mode)
local SHIP_PITCH = -1.13  -- 45 degrees forward tilt (W/S to adjust)
local SHIP_YAW = 0.16  -- 180 degrees rotation (A/D to adjust)
local SHIP_ROLL = 0.08  -- Q/E to adjust
-- Bobbing animation
local SHIP_BOB_SPEED_Y = 0.5
local SHIP_BOB_AMOUNT_Y = 0.02
local SHIP_BOB_SPEED_X = 0.2
local SHIP_BOB_AMOUNT_X = 0.01
-- Scale
local SHIP_SCALE = 1

-- Planet settings
local PLANET_X = -50
local PLANET_Y = 20
local PLANET_Z = 100
local PLANET_SCALE = 40
local PLANET_PITCH = -0.06
local PLANET_YAW = -0.54
local PLANET_ROLL = 0
local PLANET_ROTATION_SPEED = 0.01  -- Rotation speed per delta_time

-- Cloud layer settings
local CLOUD_SCALE_OFFSET = 2  -- How much larger than planet
local CLOUD_ROTATION_SPEED = 0.02  -- Slightly faster than planet

-- Menu render distance (much larger than game)
local MENU_RENDER_DISTANCE = 200

local Menu = {}

-- Menu state
Menu.active = true
Menu.show_options = false  -- Start with only title screen
Menu.show_mode_select = false  -- Mode selection screen (Arcade/Simulation)
Menu.selected_option = 1
Menu.selected_mode = 1  -- 1 = Arcade, 2 = Simulation
Menu.pending_mission = nil  -- Mission selected, waiting for mode choice
Menu.options = {}
Menu.mission_progress = {}  -- Which missions are unlocked
Menu.mission_testing = false  -- If true, all missions are unlocked (set from main.lua)
Menu.splash_fade = 0  -- Fade timer for splash screen (0 = not fading, >0 = fading out)

-- Space background elements
Menu.planet = {}
Menu.clouds = {}
Menu.space_lines = {}
Menu.ship_mesh = {}
Menu.flame_mesh = {}  -- Cached flame mesh for thrusters
Menu.flame_base_verts = {}  -- Base positions for flame animation

-- Helper function for text with drop shadow
local function print_shadow(text, x, y, color, shadow_color)
	shadow_color = shadow_color or 0  -- Default shadow color is black
	print(text, x + 1, y + 1, shadow_color)  -- Shadow
	print(text, x, y, color)  -- Main text
end

-- Generate 8-sided sphere with 6 height segments (latitude rings)
-- Returns vertices and faces for UV-wrapped sphere
-- sprite_id: which sprite to use for texturing
local function generate_sphere(sprite_id)
	local verts = {}
	local faces = {}

	local rings = 6  -- 6 height segments (latitude)
	local segments = 8  -- 8 sides (longitude)

	-- Generate vertices in rings from top to bottom
	-- Top vertex (north pole)
	add(verts, vec(0, 1, 0))

	-- Middle rings (latitude)
	for ring = 1, rings - 1 do
		local v = ring / rings  -- Vertical position (0 to 1)
		local angle_v = v * 0.5  -- Angle from top (0 to 0.5 turns)
		local y = cos(angle_v)
		local radius = sin(angle_v)

		-- Vertices around the ring (longitude)
		for seg = 0, segments - 1 do
			local angle_h = seg / segments  -- Horizontal angle (0 to 1 turn)
			local x = cos(angle_h) * radius
			local z = sin(angle_h) * radius
			add(verts, vec(x, y, z))
		end
	end

	-- Bottom vertex (south pole)
	add(verts, vec(0, -1, 0))

	-- UV scale for 64x32 sprite
	local uv_scale_u = 64  -- Horizontal (U) scale
	local uv_scale_v = 32  -- Vertical (V) scale
	local uv_offset = -uv_scale_v  -- Slide UVs down by half

	-- Generate faces
	-- Top cap (connect first ring to top vertex)
	for seg = 0, segments - 1 do
		local next_seg = (seg + 1) % segments
		local v1 = 1  -- Top vertex
		local v2 = 2 + seg
		local v3 = 2 + next_seg

		-- UV coordinates (shifted down by half, inverted Y axis)
		local u1 = (seg + 0.5) / segments * uv_scale_u
		local u2 = seg / segments * uv_scale_u
		local u3 = (seg + 1) / segments * uv_scale_u
		local v_top = uv_scale_v - (0 + uv_offset)
		local v_ring1 = uv_scale_v - ((1 / rings) * uv_scale_v + uv_offset)

		-- Reverse winding order: v1, v3, v2 instead of v1, v2, v3
		add(faces, {v1, v3, v2, sprite_id,
			vec(u1, v_top), vec(u3, v_ring1), vec(u2, v_ring1)})
	end

	-- Middle rings
	for ring = 0, rings - 3 do
		local ring_start = 2 + ring * segments
		local next_ring_start = 2 + (ring + 1) * segments

		for seg = 0, segments - 1 do
			local next_seg = (seg + 1) % segments

			-- Two triangles per quad
			local v1 = ring_start + seg
			local v2 = ring_start + next_seg
			local v3 = next_ring_start + next_seg
			local v4 = next_ring_start + seg

			-- UV coordinates (shifted down by half, inverted Y axis)
			local u1 = seg / segments * uv_scale_u
			local u2 = (seg + 1) / segments * uv_scale_u
			local v1_uv = uv_scale_v - ((ring + 1) / rings * uv_scale_v + uv_offset)
			local v2_uv = uv_scale_v - ((ring + 2) / rings * uv_scale_v + uv_offset)

			-- First triangle
			add(faces, {v1, v2, v3, sprite_id,
				vec(u1, v1_uv), vec(u2, v1_uv), vec(u2, v2_uv)})
			-- Second triangle
			add(faces, {v1, v3, v4, sprite_id,
				vec(u1, v1_uv), vec(u2, v2_uv), vec(u1, v2_uv)})
		end
	end

	-- Bottom cap (connect last ring to bottom vertex)
	local last_ring_start = 2 + (rings - 2) * segments
	local bottom_vertex = #verts
	for seg = 0, segments - 1 do
		local next_seg = (seg + 1) % segments
		local v1 = last_ring_start + seg
		local v2 = last_ring_start + next_seg
		local v3 = bottom_vertex

		-- UV coordinates (shifted down by half, inverted Y axis)
		local u1 = seg / segments * uv_scale_u
		local u2 = (seg + 1) / segments * uv_scale_u
		local u_center = (seg + 0.5) / segments * uv_scale_u

		add(faces, {v1, v2, v3, sprite_id,
			vec(u1, uv_scale_v - (uv_scale_v * (rings - 1) / rings + uv_offset)),
			vec(u2, uv_scale_v - (uv_scale_v * (rings - 1) / rings + uv_offset)),
			vec(u_center, uv_scale_v - (uv_scale_v + uv_offset))})
	end

	return verts, faces
end

-- Initialize menu
function Menu.init()
	Menu.active = true
	Menu.show_options = false  -- Reset to title screen
	Menu.show_mode_select = false  -- Reset mode selection
	Menu.selected_option = 1
	Menu.selected_mode = 1  -- Default to Arcade
	Menu.pending_mission = nil  -- Clear pending mission

	-- Load mission progress from storage (or create default)
	if Menu.mission_testing then
		-- Testing mode: unlock all missions
		Menu.mission_progress = {
			mission_1 = true,
			mission_2 = true,
			mission_3 = true,
			mission_4 = true,
			mission_5 = true,
			mission_6 = true
		}
	else
		Menu.mission_progress = {
			mission_1 = true,  -- Mission 1 always unlocked
			mission_2 = false,  -- Unlocks after Mission 1
			mission_3 = false,  -- Unlocks after Mission 2
			mission_4 = false,  -- Unlocks after Mission 3
			mission_5 = false,  -- Unlocks after Mission 4
			mission_6 = false   -- Unlocks after Mission 5
		}

		-- Try to load from Picotron storage using fetch()
		local loaded_progress = fetch("/appdata/mission_progress.pod")
		if loaded_progress then
			Menu.mission_progress.mission_1 = loaded_progress.mission_1 or true  -- Mission 1 always unlocked
			Menu.mission_progress.mission_2 = loaded_progress.mission_2 or false
			Menu.mission_progress.mission_3 = loaded_progress.mission_3 or false
			Menu.mission_progress.mission_4 = loaded_progress.mission_4 or false
			Menu.mission_progress.mission_5 = loaded_progress.mission_5 or false
			Menu.mission_progress.mission_6 = loaded_progress.mission_6 or false
		end
	end

	-- Build menu options based on unlocked missions
	Menu.update_options()

	-- Generate planet
	local planet_verts, planet_faces = generate_sphere(Constants.SPRITE_PLANET)
	Menu.planet = {
		verts = planet_verts,
		faces = planet_faces,
		x = PLANET_X,
		y = PLANET_Y,
		z = PLANET_Z,
		rotation = 0,
		scale = PLANET_SCALE
	}

	-- Scale planet vertices
	for i, v in ipairs(Menu.planet.verts) do
		Menu.planet.verts[i] = vec(v.x * PLANET_SCALE, v.y * PLANET_SCALE, v.z * PLANET_SCALE)
	end

	-- Generate cloud sphere (slightly larger than planet)
	local cloud_verts, cloud_faces = generate_sphere(Constants.SPRITE_CLOUDS)
	local cloud_scale = PLANET_SCALE + CLOUD_SCALE_OFFSET
	Menu.clouds = {
		verts = cloud_verts,
		faces = cloud_faces,
		x = PLANET_X,
		y = PLANET_Y,
		z = PLANET_Z,
		rotation = 0,
		scale = cloud_scale
	}

	-- Scale cloud vertices
	for i, v in ipairs(Menu.clouds.verts) do
		Menu.clouds.verts[i] = vec(v.x * cloud_scale, v.y * cloud_scale, v.z * cloud_scale)
	end

	-- Initialize space lines (depth movement effect)
	Menu.space_lines = {}
	for i = 1, 80 do
		Menu.add_space_line()
	end

	-- Load ship mesh (reuse from game)
	local load_obj = include("src/obj_loader.lua")
	local ship_mesh = load_obj("cross_lander.obj")
	if ship_mesh and #ship_mesh.verts > 0 then
		Menu.ship_mesh = ship_mesh
	end

	-- Load flame mesh for thrusters (cache it)
	local flame_mesh = load_obj("flame.obj")
	if flame_mesh and #flame_mesh.verts > 0 then
		Menu.flame_mesh = flame_mesh
	end
end

-- Calculate ship's up vector based on its rotation
local function get_ship_up_vector()
	-- Apply rotations in same order as renderer: yaw, pitch, roll
	local cos_pitch, sin_pitch = cos(SHIP_PITCH), sin(SHIP_PITCH)
	local cos_yaw, sin_yaw = cos(SHIP_YAW), sin(SHIP_YAW)
	local cos_roll, sin_roll = cos(SHIP_ROLL), sin(SHIP_ROLL)

	-- Start with up vector (0, 1, 0)
	local x, y, z = 0, 1, 0

	-- Apply yaw (Y axis rotation)
	local x_yaw = x * cos_yaw - z * sin_yaw
	local z_yaw = x * sin_yaw + z * cos_yaw

	-- Apply pitch (X axis rotation)
	local y_pitch = y * cos_pitch - z_yaw * sin_pitch
	local z_pitch = y * sin_pitch + z_yaw * cos_pitch

	-- Apply roll (Z axis rotation)
	local x_roll = x_yaw * cos_roll - y_pitch * sin_roll
	local y_roll = x_yaw * sin_roll + y_pitch * cos_roll

	return x_roll, y_roll, z_pitch
end

-- Add a space line for background motion (spawned above ship, moving down)
function Menu.add_space_line()
	local depth_colors = {21, 5, 22}  -- Depth colors

	-- Get ship's up vector to spawn stars above
	local up_x, up_y, up_z = get_ship_up_vector()

	-- Spawn stars in a spread above the ship
	local spread = rnd(20) + 10
	local spawn_dist = 30  -- Distance above ship

	add(Menu.space_lines, {
		x = SHIP_X + up_x * spawn_dist + (rnd(1) - 0.5) * spread,
		y = SHIP_Y + up_y * spawn_dist + (rnd(1) - 0.5) * spread,
		z = SHIP_Z + up_z * spawn_dist,
		speed = rnd(0.3) + 0.1,
		color = depth_colors[flr(rnd(3)) + 1],
		length = rnd(2) + 0.5
	})
end

-- Update menu options based on unlocked missions
function Menu.update_options()
	Menu.options = {}

	-- Mission 1
	if Menu.mission_progress.mission_1 then
		add(Menu.options, {text = "MISSION 1: ENGINE TEST", mission = 1, locked = false})
	else
		add(Menu.options, {text = "MISSION 1: [LOCKED]", mission = 1, locked = true})
	end

	-- Mission 2
	if Menu.mission_progress.mission_2 then
		add(Menu.options, {text = "MISSION 2: CARGO DELIVERY", mission = 2, locked = false})
	else
		add(Menu.options, {text = "MISSION 2: [LOCKED]", mission = 2, locked = true})
	end

	-- Mission 3
	if Menu.mission_progress.mission_3 then
		add(Menu.options, {text = "MISSION 3: SCIENTIFIC MISSION", mission = 3, locked = false})
	else
		add(Menu.options, {text = "MISSION 3: [LOCKED]", mission = 3, locked = true})
	end

	-- Mission 4
	if Menu.mission_progress.mission_4 then
		add(Menu.options, {text = "MISSION 4: OCEAN RESCUE", mission = 4, locked = false})
	else
		add(Menu.options, {text = "MISSION 4: [LOCKED]", mission = 4, locked = true})
	end

	-- Mission 5
	if Menu.mission_progress.mission_5 then
		add(Menu.options, {text = "MISSION 5: SECRET WEAPON", mission = 5, locked = false})
	else
		add(Menu.options, {text = "MISSION 5: [LOCKED]", mission = 5, locked = true})
	end

	-- Mission 6
	if Menu.mission_progress.mission_6 then
		add(Menu.options, {text = "MISSION 6: ALIEN INVASION", mission = 6, locked = false})
	else
		add(Menu.options, {text = "MISSION 6: [LOCKED]", mission = 6, locked = true})
	end

	add(Menu.options, {text = "RESET PROGRESS", action = "reset", locked = false})
	add(Menu.options, {text = "QUIT", action = "quit", locked = false})

	-- Clamp selected option and skip locked options
	if Menu.selected_option > #Menu.options then
		Menu.selected_option = #Menu.options
	end

	-- Make sure we start on an unlocked option
	while Menu.options[Menu.selected_option] and Menu.options[Menu.selected_option].locked do
		Menu.selected_option += 1
		if Menu.selected_option > #Menu.options then
			Menu.selected_option = 1
		end
	end
end

-- Update menu animations
function Menu.update(delta_time)
	if not Menu.active then return end

	-- Rotate planet and clouds
	Menu.planet.rotation += delta_time * PLANET_ROTATION_SPEED
	Menu.clouds.rotation += delta_time * CLOUD_ROTATION_SPEED

	-- Update space lines (move down ship's down vector)
	local up_x, up_y, up_z = get_ship_up_vector()
	local down_x, down_y, down_z = -up_x, -up_y, -up_z

	for i = #Menu.space_lines, 1, -1 do
		local line = Menu.space_lines[i]
		line.x += down_x * line.speed
		line.y += down_y * line.speed
		line.z += down_z * line.speed

		-- Reset line when it goes too far below ship
		local dx = line.x - SHIP_X
		local dy = line.y - SHIP_Y
		local dz = line.z - SHIP_Z
		local dist_sq = dx*dx + dy*dy + dz*dz

		if dist_sq > 60*60 then
			deli(Menu.space_lines, i)
			Menu.add_space_line()
		end
	end

	-- If options not shown yet, wait for Z press to show them
	if not Menu.show_options and not Menu.show_mode_select then
		if btnp(4) or btnp(5) or key("return") or key("space") then  -- Z, X, Enter, Space
			Menu.show_options = true
		end
		return
	end

	-- Mode selection screen
	if Menu.show_mode_select then
		if btnp(2) or btnp(3) then  -- Up or Down
			Menu.selected_mode = (Menu.selected_mode == 1) and 2 or 1
		end

		if btnp(4) or btnp(5) or key("return") or key("space") then  -- Z, X, Enter, Space
			return Menu.select_mode()
		end

		if key("tab") then  -- TAB to go back
			Menu.show_mode_select = false
			Menu.show_options = true
			Menu.pending_mission = nil
		end
		return
	end

	-- Menu navigation (only when options are visible)
	if btnp(2) then  -- Up
		Menu.selected_option -= 1
		if Menu.selected_option < 1 then
			Menu.selected_option = #Menu.options
		end
		-- Skip locked options
		while Menu.options[Menu.selected_option].locked do
			Menu.selected_option -= 1
			if Menu.selected_option < 1 then
				Menu.selected_option = #Menu.options
			end
		end
	end
	if btnp(3) then  -- Down
		Menu.selected_option += 1
		if Menu.selected_option > #Menu.options then
			Menu.selected_option = 1
		end
		-- Skip locked options
		while Menu.options[Menu.selected_option].locked do
			Menu.selected_option += 1
			if Menu.selected_option > #Menu.options then
				Menu.selected_option = 1
			end
		end
	end

	-- Select option
	if btnp(4) or btnp(5) or key("return") or key("space") then  -- Z, X, Enter, Space
		return Menu.select_option()
	end
end

-- Select current menu option
function Menu.select_option()
	local option = Menu.options[Menu.selected_option]

	-- Don't allow selecting locked options
	if option.locked then
		return nil
	end

	if option.mission then
		-- Show mode selection screen
		Menu.pending_mission = option.mission
		Menu.show_mode_select = true
		Menu.show_options = false
		Menu.selected_mode = 1  -- Default to Arcade
	elseif option.action == "reset" then
		-- Reset progress
		Menu.reset_progress()
		Menu.update_options()
	elseif option.action == "quit" then
		-- Quit game
		exit()
	end

	return nil
end

-- Select game mode (Arcade or Simulation)
function Menu.select_mode()
	Menu.active = false
	Menu.selected_mission = Menu.pending_mission
	local mode = (Menu.selected_mode == 1) and "arcade" or "simulation"
	return "start_mission", Menu.pending_mission, mode
end

-- Reset mission progress
function Menu.reset_progress()
	Menu.mission_progress = {
		mission_1 = true,
		mission_2 = false,
		mission_3 = false,
		mission_4 = false,
		mission_5 = false
	}
	Menu.save_progress()
end

-- Save progress to storage
function Menu.save_progress()
	-- Use Picotron's store() function to save to /appdata
	store("/appdata/mission_progress.pod", Menu.mission_progress)
end

-- Unlock a mission
function Menu.unlock_mission(mission_num)
	if mission_num == 2 then
		Menu.mission_progress.mission_2 = true
	elseif mission_num == 3 then
		Menu.mission_progress.mission_3 = true
	elseif mission_num == 4 then
		Menu.mission_progress.mission_4 = true
	elseif mission_num == 5 then
		Menu.mission_progress.mission_5 = true
	end
	Menu.save_progress()
	Menu.update_options()
end

-- Draw menu
function Menu.draw(camera, render_mesh_func)
	if not Menu.active then return end

	cls(0)  -- Black background

	-- Draw space lines (stretch along ship's down vector)
	local up_x, up_y, up_z = get_ship_up_vector()
	local down_x, down_y, down_z = -up_x, -up_y, -up_z

	for space_line in all(Menu.space_lines) do
		-- Project to screen
		local cam_x, cam_y, cam_z = camera.x, camera.y, camera.z
		local lx = space_line.x - cam_x
		local ly = space_line.y - cam_y
		local lz = space_line.z - cam_z + 5

		if lz > 0.01 then
			local fov = 70
			local fov_rad = fov * 0.5 * 0.0174533
			local tan_half_fov = sin(fov_rad) / cos(fov_rad)

			local sx1 = lx / lz * (270 / tan_half_fov) + 240
			local sy1 = ly / lz * (270 / tan_half_fov) + 135

			-- End point (line extending along ship's down vector)
			local ex = space_line.x + down_x * space_line.length - cam_x
			local ey = space_line.y + down_y * space_line.length - cam_y
			local ez = space_line.z + down_z * space_line.length - cam_z + 5

			if ez > 0.01 then
				local sx2 = ex / ez * (270 / tan_half_fov) + 240
				local sy2 = ey / ez * (270 / tan_half_fov) + 135

				line(sx1, sy1, sx2, sy2, space_line.color)
			end
		end
	end

	-- Render planet in background (draw first, always behind everything)
	local planet_sorted = render_mesh_func(
		Menu.planet.verts,
		Menu.planet.faces,
		Menu.planet.x,
		Menu.planet.y,
		Menu.planet.z,
		nil, false,
		PLANET_PITCH, PLANET_YAW + Menu.planet.rotation, PLANET_ROLL,
		MENU_RENDER_DISTANCE  -- Extended render distance for space scene
	)
	Renderer.sort_faces(planet_sorted)
	Renderer.draw_faces(planet_sorted, false)

	-- Render cloud sphere with dithering (drawn after planet, always in front)
	fillp(0b0101101001011010)  -- 50% dither pattern
	local cloud_sorted = render_mesh_func(
		Menu.clouds.verts,
		Menu.clouds.faces,
		Menu.clouds.x,
		Menu.clouds.y,
		Menu.clouds.z,
		nil, false,
		PLANET_PITCH, PLANET_YAW + Menu.clouds.rotation, PLANET_ROLL,
		MENU_RENDER_DISTANCE  -- Extended render distance for space scene
	)
	Renderer.sort_faces(cloud_sorted)
	Renderer.draw_faces(cloud_sorted, false)
	fillp()  -- Reset fill pattern

	-- Collect other faces (space lines, ship, flames)
	local all_faces = {}

	-- Render ship in foreground with thrusters firing
	if Menu.ship_mesh and #Menu.ship_mesh.verts > 0 then
		-- Build ship verts and faces with proper texturing
		local ship_verts = {}
		for _, v in ipairs(Menu.ship_mesh.verts) do
			add(ship_verts, vec(v.x * SHIP_SCALE, v.y * SHIP_SCALE, v.z * SHIP_SCALE))
		end

		-- Apply ship texture (sprite 9) to all faces
		local ship_faces = {}
		for _, face in ipairs(Menu.ship_mesh.faces) do
			local uv1 = {x = face[5].x * 4, y = face[5].y * 4}
			local uv2 = {x = face[6].x * 4, y = face[6].y * 4}
			local uv3 = {x = face[7].x * 4, y = face[7].y * 4}
			add(ship_faces, {face[1], face[2], face[3], Constants.SPRITE_SHIP, uv1, uv2, uv3})
		end

		-- Add flame meshes at engine positions (all 4 engines firing)
		local engine_positions = {
			{x = 6 * SHIP_SCALE, y = -2 * SHIP_SCALE, z = 0},  -- Right
			{x = -6 * SHIP_SCALE, y = -2 * SHIP_SCALE, z = 0},  -- Left
			{x = 0, y = -2 * SHIP_SCALE, z = 6 * SHIP_SCALE},  -- Front
			{x = 0, y = -2 * SHIP_SCALE, z = -6 * SHIP_SCALE},  -- Back
		}

		if Menu.flame_mesh and #Menu.flame_mesh.verts > 0 then
			-- Animate flames with flickering effect
			local flame_time = time() * 6

			for engine_idx, engine in ipairs(engine_positions) do
				local flame_verts_start = #ship_verts

				for vert_idx, v in ipairs(Menu.flame_mesh.verts) do
					-- Calculate flickering scale
					local base_flicker = sin(flame_time + engine_idx * 2.5) * 0.03
					local noise = sin(flame_time * 3.7 + vert_idx * 0.5) * 0.015
					noise += sin(flame_time * 7.2 + vert_idx * 1.3) * 0.01
					local scale_mod = 1.0 + base_flicker + noise

					-- Calculate offset from engine center
					local offset_x = (v.x - 2.3394) * SHIP_SCALE
					local offset_y = (v.y - 0.3126) * SHIP_SCALE
					local offset_z = (v.z + 2.7187) * SHIP_SCALE

					-- Apply animated position
					add(ship_verts, vec(
						v.x * SHIP_SCALE + engine.x + offset_x * (scale_mod - 1.0),
						v.y * SHIP_SCALE + engine.y + offset_y * (scale_mod - 1.0) * 1.2,
						v.z * SHIP_SCALE + engine.z + offset_z * (scale_mod - 1.0)
					))
				end

				for _, face in ipairs(Menu.flame_mesh.faces) do
					add(ship_faces, {
						face[1] + flame_verts_start,
						face[2] + flame_verts_start,
						face[3] + flame_verts_start,
						Constants.SPRITE_FLAME,
						face[5], face[6], face[7]
					})
				end
			end
		end

		-- Position and rotation (configured at top of file)
		local bob_y = sin(time() * SHIP_BOB_SPEED_Y) * SHIP_BOB_AMOUNT_Y
		local bob_x = sin(time() * SHIP_BOB_SPEED_X) * SHIP_BOB_AMOUNT_X

		local ship_sorted = render_mesh_func(
			ship_verts,
			ship_faces,
			SHIP_X + bob_x, SHIP_Y + bob_y, SHIP_Z,
			nil, false,
			SHIP_PITCH, SHIP_YAW, SHIP_ROLL,
			MENU_RENDER_DISTANCE  -- Extended render distance for space scene
		)
		for _, f in ipairs(ship_sorted) do
			add(all_faces, f)
		end
	end

	-- Sort and draw all faces
	Renderer.sort_faces(all_faces)
	Renderer.draw_faces(all_faces, false)

	-- Mode selection screen
	if Menu.show_mode_select then
		local menu_y = 60
		local menu_x = 240

		-- Mode options
		local modes = {
			{name = "ARCADE", desc = "Assisted flight with auto-balance\nand multi-thruster controls"},
			{name = "SIMULATION", desc = "Manual flight with one button\nper thruster - no assists"}
		}

		-- Draw title with drop shadow
		local title = "SELECT MODE"
		local title_width = #title * 4
		print_shadow(title, menu_x - title_width / 2, menu_y, 7)
		menu_y += 20

		-- Draw mode options
		for i, mode in ipairs(modes) do
			local color = (i == Menu.selected_mode) and 11 or 6
			local prefix = (i == Menu.selected_mode) and "> " or "  "

			-- Mode name with drop shadow
			print_shadow(prefix .. mode.name, 80, menu_y, color)
			menu_y += 12

			-- Mode description (only for selected) with drop shadow
			if i == Menu.selected_mode then
				local desc_lines = {}
				for line in mode.desc:gmatch("[^\n]+") do
					add(desc_lines, line)
				end
				for _, line in ipairs(desc_lines) do
					print_shadow("  " .. line, 80, menu_y, 6)
					menu_y += 8
				end
				menu_y += 8
			end
		end

		-- Controls hint with drop shadow - just show tab for going back!
		print_shadow("[TAB] Back", 60, 220, 6)


	elseif Menu.show_options then
		-- Draw menu UI with background box
		local menu_y = 50
		local menu_x = 160

		-- Calculate box dimensions
		local box_padding = 10

		local title_width = #"The Return of Tom Lander" * 4
		local max_option_width = 0
		for i, option in ipairs(Menu.options) do
			local option_width = #(">  " .. option.text) * 4
			if option_width > max_option_width then
				max_option_width = option_width
			end
		end
		local box_width = (title_width > max_option_width and title_width or max_option_width) + box_padding * 2 + 40
		local box_height = 20 + #Menu.options * 12 + box_padding * 2
		local box_x = menu_x - box_width / 2
		local box_y = menu_y - box_padding

		-- Draw dithered background with transparency (color index 1 with dither pattern)
		-- fillp(pattern, transparency_pattern) - where 0 bits in transparency are transparent
		fillp(0b0101101001011010, 0b0101101001011010)
		rectfill(box_x, box_y, box_x + box_width, box_y + box_height, 1)
		fillp()

		-- Draw border (color 6)
		rect(box_x, box_y, box_x + box_width, box_y + box_height, 6)

		-- Draw title
		print("The Return of Tom Lander", 80, menu_y, 7)
		menu_y += 20

		-- Draw options
		for i, option in ipairs(Menu.options) do
			local color
			if option.locked then
				color = 5  -- Grey for locked options
			elseif i == Menu.selected_option then
				color = 11  -- Cyan for selected
			else
				color = 6  -- Dark grey for unselected
			end
			local prefix = (i == Menu.selected_option) and "> " or "  "
			print(prefix .. option.text, 80, menu_y + (i - 1) * 12, color)
		end

	else
		-- Draw sprite 66 (title logo) in center of screen (256x128 scaled 1.5x = 384x192)
		local sprite_w = 256 * 1.5
		local sprite_h = 128 * 1.5
		local sprite_x = 240 - sprite_w / 2
		local sprite_y = 135 - sprite_h / 2

		-- Draw sprite with transparency
		poke(0x550F, 0)  -- Set color 0 (black) as transparent
		-- sspr(sprite_id, src_x, src_y, src_w, src_h, dest_x, dest_y, dest_w, dest_h)
		sspr(65, 0, 0, 256, 128, sprite_x, sprite_y, sprite_w, sprite_h)
		poke(0x550F, 0xFF)  -- Reset transparency

		-- Draw "press Z to start" hint below sprite with drop shadow
		local hint = "[Z] to start"
		local hint_width = #hint * 4
		local hint_x = 240 - hint_width / 2
		local hint_y = sprite_y + sprite_h + 10
		-- Drop shadow
		print(hint, hint_x + 1, hint_y + 1, 0)
		-- Main text (color 1)
		print(hint, hint_x, hint_y, 1)
	end

end

return Menu
