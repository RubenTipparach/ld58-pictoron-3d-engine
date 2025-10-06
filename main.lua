-- UI toggles (EASY TO ADJUST!)
local show_debug = false
local show_mission_ui = true

-- Load modules
local load_obj = include("src/obj_loader.lua")
local ParticleSystem = include("src/particle_system.lua")
local MathUtils = include("src/math_utils.lua")
local Renderer = include("src/renderer.lua")
local Collision = include("src/collision.lua")
local Heightmap = include("src/heightmap.lua")
local Minimap = include("src/minimap.lua")
local Constants = include("src/constants.lua")
local DeathScreen = include("src/death_screen.lua")
local LandingPads = include("src/landing_pads.lua")
local Ship = include("src/ship.lua")
local Building = include("src/building.lua")
local Cargo = include("src/cargo.lua")
local Mission = include("src/mission.lua")
local Menu = include("src/menu.lua")

-- Import sprite constants for easy reference
local SPRITE_CUBE = Constants.SPRITE_CUBE
local SPRITE_SPHERE = Constants.SPRITE_SPHERE
local SPRITE_GROUND = Constants.SPRITE_GROUND
local SPRITE_FLAME = Constants.SPRITE_FLAME
local SPRITE_SMOKE = Constants.SPRITE_SMOKE
local SPRITE_TREES = Constants.SPRITE_TREES
local SPRITE_LANDING_PAD = Constants.SPRITE_LANDING_PAD
local SPRITE_SHIP = Constants.SPRITE_SHIP
local SPRITE_SHIP_DAMAGE = Constants.SPRITE_SHIP_DAMAGE
local SPRITE_SKYBOX = Constants.SPRITE_SKYBOX
local SPRITE_WATER = Constants.SPRITE_WATER
local SPRITE_WATER2 = Constants.SPRITE_WATER2
local SPRITE_GRASS = Constants.SPRITE_GRASS
local SPRITE_ROCKS = Constants.SPRITE_ROCKS
local SPRITE_ROOFTOP = Constants.SPRITE_ROOFTOP
local SPRITE_BUILDING_SIDE = Constants.SPRITE_BUILDING_SIDE
local SPRITE_BUILDING_SIDE_ALT = Constants.SPRITE_BUILDING_SIDE_ALT
local SPRITE_CARGO = Constants.SPRITE_CARGO
local SPRITE_PLANET = Constants.SPRITE_PLANET
local SPRITE_HEIGHTMAP = Constants.SPRITE_HEIGHTMAP

-- Input state tracking
local last_escape_state = false
local last_q_state = false
local last_tab_state = false
local last_g_state = false

-- Ship Spawn Configuration (EASY TO ADJUST!)
local SHIP_SPAWN_HEIGHT_OFFSET = -1 -- Height above landing pad surface (in world units, 1 unit = 10 meters)

-- Landing Pad Repair Configuration
local REPAIR_RATE = 10  -- Health points repaired per second when landed on pad
local REPAIR_DELAY = 1.0  -- Seconds of being stationary before repair starts

-- VTOL Physics Configuration (easy tweaking)
local VTOL_THRUST = 0.002  -- Thrust force per thruster
local VTOL_TORQUE_YAW = 0.001  -- Torque around Y axis (yaw)
local VTOL_TORQUE_PITCH = 0.0008  -- Torque around X axis (pitch)
local VTOL_TORQUE_ROLL = 0.0008  -- Torque around Z axis (roll)
local VTOL_MASS = 30
local VTOL_GRAVITY = -0.005
local VTOL_DAMPING = 0.95  -- Linear velocity damping (air resistance)
local VTOL_ANGULAR_DAMPING = 0.85 -- Angular velocity damping (rotational drag)
local VTOL_GROUND_PITCH_DAMPING = 0.8  -- Rotation damping when touching ground (pitch)
local VTOL_GROUND_ROLL_DAMPING = 0.8   -- Rotation damping when touching ground (roll)

-- Damage Configuration
local DAMAGE_BUILDING_THRESHOLD = 0.1  -- Minimum speed for building collision damage
local DAMAGE_GROUND_THRESHOLD = -0.05  -- Minimum vertical velocity for ground impact damage
local DAMAGE_BUILDING_MULTIPLIER = 50  -- Damage multiplier for building collisions
local DAMAGE_GROUND_MULTIPLIER = 400   -- Damage multiplier for ground impacts

-- Rendering Configuration
local RENDER_DISTANCE = 20  -- Far plane / fog distance
local FOG_START_DISTANCE = 15  -- Distance where fog/fade begins (3m before render distance)
local DEBUG_SHOW_PHYSICS_WIREFRAME = false  -- Toggle physics collision wireframes
local GROUND_ALWAYS_BEHIND = false  -- Force ground to render behind everything (depth bias)

-- Heightmap Configuration
local USE_HEIGHTMAP = true  -- Enable heightmap terrain system (128x128 map from sprite 64)
local DEBUG_SHOW_HEIGHTMAP_SPRITE = false  -- Draw sprite 64 (heightmap data) on screen to verify it's correct

-- Cached minimap terrain texture (generated once at startup)
local minimap_terrain_cache = nil

-- Game State Management
local GAME_STATE = {
	PLAYING = 1,
	DYING = 2,  -- Exploding phase
	DEAD = 3    -- Show death screen
}
local current_game_state = GAME_STATE.PLAYING
local death_timer = 0
local DEATH_EXPLOSION_DURATION = 2.0  -- 2 seconds of explosions before death screen
local death_explosion_timer = 0

-- textri function is now in renderer.lua module

-- Low poly sphere (icosphere approximation)
local function generate_sphere(subdivisions)
	-- Start with icosahedron
	local t = (1 + sqrt(5)) / 2
	local vertices = {
		vec(-1, t, 0), vec(1, t, 0), vec(-1, -t, 0), vec(1, -t, 0),
		vec(0, -1, t), vec(0, 1, t), vec(0, -1, -t), vec(0, 1, -t),
		vec(t, 0, -1), vec(t, 0, 1), vec(-t, 0, -1), vec(-t, 0, 1)
	}

	-- Normalize to unit sphere using MathUtils
	for i, v in ipairs(vertices) do
		vertices[i] = MathUtils.normalize(v)
	end

	-- Icosahedron faces (reversed winding order for correct facing)
	local ico_faces = {
		{1, 6, 12}, {1, 2, 6}, {1, 8, 2}, {1, 11, 8}, {1, 12, 11},
		{2, 10, 6}, {6, 5, 12}, {12, 3, 11}, {11, 7, 8}, {8, 9, 2},
		{4, 5, 10}, {4, 3, 5}, {4, 7, 3}, {4, 9, 7}, {4, 10, 9},
		{5, 6, 10}, {3, 12, 5}, {7, 11, 3}, {9, 8, 7}, {10, 2, 9}
	}

	return vertices, ico_faces
end

local sphere_verts, sphere_faces_raw = generate_sphere(1)
-- Convert sphere faces to include sprite_id and UVs
local sphere_faces = {}
for _, face in ipairs(sphere_faces_raw) do
	add(sphere_faces, {face[1], face[2], face[3], SPRITE_SPHERE, vec(0,0), vec(16,0), vec(16,16)})  -- sphere sprite
end

-- Skybox: 6-sided dome with 1 vertical segment using sprite 11
local skybox_radius = 50
local skybox_height = 30
local skybox_verts = {}

-- Bottom ring (6 vertices at y=0)
for i = 0, 5 do
	local angle = i / 6
	add(skybox_verts, vec(
		cos(angle) * skybox_radius,
		0,
		sin(angle) * skybox_radius
	))
end

-- Top vertex
add(skybox_verts, vec(0, skybox_height, 0))  -- Vertex 7

-- Skybox faces (6 triangular sides) - 32x32 sprite
local skybox_faces = {}
for i = 0, 5 do
	local b1 = i + 1                  -- Bottom ring vertex
	local b2 = (i + 1) % 6 + 1        -- Next bottom vertex
	local top = 7                      -- Top vertex

	-- Triangle from bottom edge to top (UVs tile horizontally across 32px)
	local u_start = i * 32 / 6
	local u_end = (i + 1) * 32 / 6
	add(skybox_faces, {b1, b2, top, SPRITE_SKYBOX, vec(u_start, 32), vec(u_end, 32), vec((u_start+u_end)/2, 0)})
end

-- Ground plane generation now uses heightmap system
-- Wrapper for backward compatibility - auto-sizes based on render distance
function generate_ground_around_camera(cam_x, cam_z)
	-- Pass nil for grid_count to auto-calculate, and RENDER_DISTANCE for optimization
	return Heightmap.generate_terrain(cam_x, cam_z, nil, RENDER_DISTANCE)
end

-- Generate city buildings (10 skyscraper-style buildings)
-- Using Building module with rooftop (sprite 17) and nine-sliced sides (sprite 18 or 19)
local building_configs = {
	{x = -10, z = 5, width = 1.5, depth = 1.5, height = 8, side_sprite = SPRITE_BUILDING_SIDE},      -- Tall tower
	{x = -5, z = 4, width = 1.2, depth = 1.2, height = 6, side_sprite = SPRITE_BUILDING_SIDE_ALT},   -- Medium tower
	{x = 0, z = 5, width = 1.0, depth = 1.0, height = 5, side_sprite = SPRITE_BUILDING_SIDE},        -- Shorter building
	{x = 6, z = 4, width = 1.3, depth = 1.3, height = 7, side_sprite = SPRITE_BUILDING_SIDE_ALT},    -- Tall tower
	{x = -8, z = 12, width = 1.8, depth = 1.0, height = 4, side_sprite = SPRITE_BUILDING_SIDE},      -- Wide building
	{x = -2, z = 12, width = 1.0, depth = 1.8, height = 5, side_sprite = SPRITE_BUILDING_SIDE_ALT},  -- Long building
	{x = 3, z = 14, width = 1.2, depth = 1.2, height = 9, side_sprite = SPRITE_BUILDING_SIDE},       -- Tallest skyscraper
	{x = 9, z = 12, width = 1.0, depth = 1.0, height = 3, side_sprite = SPRITE_BUILDING_SIDE_ALT},   -- Small building
	{x = -6, z = 18, width = 1.5, depth = 1.2, height = 6, side_sprite = SPRITE_BUILDING_SIDE},      -- Medium building
	{x = 2, z = 20, width = 1.1, depth = 1.4, height = 7, side_sprite = SPRITE_BUILDING_SIDE_ALT},   -- Tall building
}

local buildings = Building.create_city(building_configs, USE_HEIGHTMAP)


-- Load landing pad mesh from landing_pad.obj
local landing_pad_mesh = load_obj("landing_pad.obj")
if not landing_pad_mesh or #landing_pad_mesh.verts == 0 then
	-- ERROR: Could not load landing pad mesh, using fallback red cube
	-- Create a 3x3 red cube as fallback
	landing_pad_mesh = {
		verts = {
			vec(-1.5, 0, -1.5), vec(1.5, 0, -1.5), vec(1.5, 0, 1.5), vec(-1.5, 0, 1.5),  -- Bottom
			vec(-1.5, 3, -1.5), vec(1.5, 3, -1.5), vec(1.5, 3, 1.5), vec(-1.5, 3, 1.5)   -- Top
		},
		faces = {
			-- Bottom face
			{1, 2, 3, SPRITE_LANDING_PAD, vec(0,0), vec(16,0), vec(16,16)}, {1, 3, 4, SPRITE_LANDING_PAD, vec(0,0), vec(16,16), vec(0,16)},
			-- Top face
			{5, 7, 6, SPRITE_LANDING_PAD, vec(0,0), vec(16,0), vec(16,16)}, {5, 8, 7, SPRITE_LANDING_PAD, vec(0,0), vec(16,16), vec(0,16)},
			-- Front face
			{1, 5, 6, SPRITE_LANDING_PAD, vec(0,0), vec(16,0), vec(16,16)}, {1, 6, 2, SPRITE_LANDING_PAD, vec(0,0), vec(16,16), vec(0,16)},
			-- Back face
			{3, 7, 8, SPRITE_LANDING_PAD, vec(0,0), vec(16,0), vec(16,16)}, {3, 8, 4, SPRITE_LANDING_PAD, vec(0,0), vec(16,16), vec(0,16)},
			-- Left face
			{4, 8, 5, SPRITE_LANDING_PAD, vec(0,0), vec(16,0), vec(16,16)}, {4, 5, 1, SPRITE_LANDING_PAD, vec(0,0), vec(16,16), vec(0,16)},
			-- Right face
			{2, 6, 7, SPRITE_LANDING_PAD, vec(0,0), vec(16,0), vec(16,16)}, {2, 7, 3, SPRITE_LANDING_PAD, vec(0,0), vec(16,16), vec(0,16)}
		}
	}
end

-- Override sprite to SPRITE_LANDING_PAD for landing pad (32x32 pixels) and scale UVs to 32x32
for _, face in ipairs(landing_pad_mesh.faces) do
	face[4] = SPRITE_LANDING_PAD  -- Set sprite index to landing pad texture
	-- Scale UVs from 16x16 to 32x32 (multiply by 2)
	if face[5] then face[5] = vec(face[5].x * 2, face[5].y * 2) end
	if face[6] then face[6] = vec(face[6].x * 2, face[6].y * 2) end
	if face[7] then face[7] = vec(face[7].x * 2, face[7].y * 2) end
end

-- Calculate bounding box from landing pad mesh using Collision module
local pad_min_x, pad_max_x, pad_min_y, pad_max_y, pad_min_z, pad_max_z =
	Collision.calculate_bounds(landing_pad_mesh.verts)

local pad_width = pad_max_x - pad_min_x
local pad_height = pad_max_y - pad_min_y
local pad_depth = pad_max_z - pad_min_z

-- Create landing pads using the LandingPads system
-- Landing pads automatically adjust to terrain height
-- To spawn ship on a specific pad: LandingPads.get_spawn(id) returns x, y, z, yaw
-- Pad 1: Main spawn pad
local landing_pad_1 = LandingPads.create_pad({
	id = 1,
	x = 5,
	z = -3,
	mesh = landing_pad_mesh,
	scale = 0.5,
	sprite = SPRITE_LANDING_PAD,
	collision_dims = {
		width = pad_width,
		height = 2,
		depth = pad_depth
	},
	collision_y_offset = -1.0  -- Adjust collision box down
})

-- Example: Pad 2 at a different location (commented out)
-- local landing_pad_2 = LandingPads.create_pad({
-- 	id = 2,
-- 	x = -10,
-- 	z = 15,
-- 	mesh = landing_pad_mesh,
-- 	scale = 0.5,
-- 	sprite = SPRITE_LANDING_PAD,
-- 	collision_dims = {
-- 		width = pad_width,
-- 		height = 1.5,
-- 		depth = pad_depth
-- 	}
-- })

-- Keep reference to primary pad for backward compatibility
local landing_pad = landing_pad_1

-- Load tree mesh from tree.obj
local tree_mesh = load_obj("tree.obj")
if not tree_mesh or #tree_mesh.verts == 0 then
	-- ERROR: Could not load tree mesh, using fallback red cube
	-- Create a 3x3 red cube as fallback
	tree_mesh = {
		verts = {
			vec(-1.5, 0, -1.5), vec(1.5, 0, -1.5), vec(1.5, 0, 1.5), vec(-1.5, 0, 1.5),  -- Bottom
			vec(-1.5, 3, -1.5), vec(1.5, 3, -1.5), vec(1.5, 3, 1.5), vec(-1.5, 3, 1.5)   -- Top
		},
		faces = {
			{1, 2, 3, SPRITE_TREES, vec(0,0), vec(16,0), vec(16,16)}, {1, 3, 4, SPRITE_TREES, vec(0,0), vec(16,16), vec(0,16)},
			{5, 7, 6, SPRITE_TREES, vec(0,0), vec(16,0), vec(16,16)}, {5, 8, 7, SPRITE_TREES, vec(0,0), vec(16,16), vec(0,16)},
			{1, 5, 6, SPRITE_TREES, vec(0,0), vec(16,0), vec(16,16)}, {1, 6, 2, SPRITE_TREES, vec(0,0), vec(16,16), vec(0,16)},
			{3, 7, 8, SPRITE_TREES, vec(0,0), vec(16,0), vec(16,16)}, {3, 8, 4, SPRITE_TREES, vec(0,0), vec(16,16), vec(0,16)},
			{4, 8, 5, SPRITE_TREES, vec(0,0), vec(16,0), vec(16,16)}, {4, 5, 1, SPRITE_TREES, vec(0,0), vec(16,16), vec(0,16)},
			{2, 6, 7, SPRITE_TREES, vec(0,0), vec(16,0), vec(16,16)}, {2, 7, 3, SPRITE_TREES, vec(0,0), vec(16,16), vec(0,16)}
		}
	}
end

-- Override sprite to SPRITE_TREES for all tree faces
for _, face in ipairs(tree_mesh.faces) do
	face[4] = SPRITE_TREES  -- Set sprite index to trees
end

-- Generate random tree positions (max 3 per 20m x 20m cell)
local trees = {}
local cell_size = 20  -- 20m x 20m cells
local max_trees_per_cell = 3
local map_range = 100  -- Place trees in 200x200m area (-100 to 100)

-- Create grid cells and track tree count per cell
local tree_grid = {}

-- Seeded random is now in MathUtils module

-- Generate trees with grid-based distribution
for tree_idx = 1, 150 do  -- Try to place up to 150 trees
	local x = (MathUtils.seeded_random(tree_idx, 0, 1234) - 0.5) * map_range * 2
	local z = (MathUtils.seeded_random(tree_idx, 1, 1234) - 0.5) * map_range * 2

	-- Determine which cell this tree falls into
	local cell_x = flr(x / cell_size)
	local cell_z = flr(z / cell_size)
	local cell_key = cell_x .. "," .. cell_z

	-- Initialize cell counter if needed
	if not tree_grid[cell_key] then
		tree_grid[cell_key] = 0
	end

	-- Only place tree if cell has less than max trees
	if tree_grid[cell_key] < max_trees_per_cell then
		-- Get height from heightmap if available
		local tree_height = 0
		if USE_HEIGHTMAP then
			tree_height = Heightmap.get_height(x, z)
		end

		-- Don't place trees on water (height = 0)
		if tree_height > 0 then
			add(trees, {
				verts = tree_mesh.verts,
				faces = tree_mesh.faces,
				x = x,
				y = tree_height,  -- Terrain elevation
				z = z,
				sprite_override = 6
			})
			tree_grid[cell_key] += 1
		end
	end
end

-- Generated " .. #trees .. " trees across the map

-- UV coordinates for a full sprite
local uvs = {
	vec(0, 0),
	vec(16, 0),
	vec(16, 16),
	vec(0, 16),
}

-- Camera state
local camera = {
	x = 0,
	y = 3,  -- 3 units above the ground
	z = -8,  -- Start further back to see the city
	rx = 0,  -- rotation around X axis
	ry = 0,  -- rotation around Y axis
}

-- Mouse drag state for camera control
local mouse_drag = {
	active = false,
	start_x = 0,
	start_y = 0,
	base_rx = 0,
	base_ry = 0
}

-- Performance tracking
local fps_counter = 0
local fps_timer = 0
local current_fps = 0
local objects_rendered = 0
local objects_culled = 0
local last_time = time()
local delta_time = 0

-- Pre-allocate userdata pool to avoid allocations per triangle
local vert_data_pool = userdata("f64", 6, 3)

-- Explosion effects (visual only)
local explosions = {}

local function add_explosion(ship)
	-- Pick a random engine position for the explosion
	local random_thruster = ship.thrusters[flr(rnd(#ship.thrusters)) + 1]

	-- Calculate world position of the engine using ship rotation
	local cos_yaw = cos(ship.yaw)
	local sin_yaw = sin(ship.yaw)
	local cos_pitch = cos(ship.pitch)
	local sin_pitch = sin(ship.pitch)

	-- Rotate engine position by ship's yaw (simplified - just yaw rotation for now)
	local world_x = ship.x + (random_thruster.x * cos_yaw - random_thruster.z * sin_yaw)
	local world_y = ship.y + (random_thruster.y or -0.3)  -- Use thruster y or default
	local world_z = ship.z + (random_thruster.x * sin_yaw + random_thruster.z * cos_yaw)

	add(explosions, {
		x = world_x,
		y = world_y,
		z = world_z,
		time = 0,
		max_time = 0.6,  -- Duration in seconds
		max_radius = 16   -- Bigger explosions (doubled from 8)
	})
end

-- VTOL Vehicle Physics
-- Get spawn position from landing pad 1
local spawn_x, spawn_y, spawn_z, spawn_yaw = LandingPads.get_spawn(1)
spawn_y += SHIP_SPAWN_HEIGHT_OFFSET  -- Apply spawn height offset

-- Create ship using Ship module
local vtol = Ship.new({
	spawn_x = spawn_x,
	spawn_y = spawn_y,
	spawn_z = spawn_z,
	spawn_yaw = spawn_yaw,
	mass = VTOL_MASS,
	thrust = VTOL_THRUST,
	gravity = VTOL_GRAVITY,
	damping = VTOL_DAMPING,
	angular_damping = VTOL_ANGULAR_DAMPING,
	max_health = 100
})

-- Position history for minimap trail (store last 5 seconds)
local position_history = {}
local HISTORY_DURATION = 5  -- seconds
local HISTORY_SAMPLE_RATE = 0.1  -- sample every 0.1 seconds
local last_history_sample = 0

-- Smoke particle system (using ParticleSystem module)
local smoke_system = ParticleSystem.new({
	size = 0.16,
	max_particles = 10,  -- Increased from 4 to 10 for damage severity
	lifetime = 2.0,
	spawn_rate = 0.3,
	sprite_id = SPRITE_SMOKE,  -- Grey smoke sprite
	scale_growth = 1.5
})
local smoke_spawn_timer = 0
local smoke_spawn_rate = 0.3  -- Base spawn rate (can be modified based on damage)

-- Speed lines particle system (dust/motion lines)
local speed_lines = {}
local MAX_SPEED_LINES = 40  -- Maximum number of speed lines
local SPEED_LINE_SPAWN_RATE = 0.05  -- Spawn interval
local speed_line_timer = 0

-- Repair system
local repair_timer = 0  -- Time ship has been stationary on landing pad
local is_on_landing_pad = false  -- Track if ship is on a landing pad

local function spawn_speed_line(ship)
	-- Calculate ship speed
	local speed = sqrt(ship.vx * ship.vx + ship.vy * ship.vy + ship.vz * ship.vz)

	if speed < 0.02 then return end  -- Don't spawn at very low speeds

	-- Spawn line randomly around the ship in a sphere (40m radius = 4 world units)
	local spawn_radius = 4  -- 40 meters radius (4x larger)

	-- Random position in a sphere around ship (using spherical coordinates for even distribution)
	local theta = rnd(1)  -- Angle around Y axis (0-1)
	local phi = rnd(1)  -- Angle from Y axis (0-1)
	local radius = rnd(spawn_radius)

	-- Convert to Cartesian coordinates for even sphere distribution
	local offset_x = radius * sin(phi) * cos(theta)
	local offset_y = radius * sin(phi) * sin(theta)
	local offset_z = radius * cos(phi)

	-- All lines point in the same direction: ship's velocity
	-- Normalize ship velocity to get direction
	local vel_mag = sqrt(ship.vx * ship.vx + ship.vy * ship.vy + ship.vz * ship.vz)
	local dir_x = ship.vx / vel_mag
	local dir_y = ship.vy / vel_mag
	local dir_z = ship.vz / vel_mag

	-- Calculate line length at spawn (based on current velocity, minimum 1 pixel equivalent)
	local line_length = max(0.1, vel_mag * 2)

	add(speed_lines, {
		x = ship.x + offset_x,
		y = ship.y + offset_y,
		z = ship.z + offset_z,
		-- Store direction and length at spawn time (won't change)
		dir_x = dir_x,
		dir_y = dir_y,
		dir_z = dir_z,
		length = line_length,  -- Fixed length
		life = 1.0,  -- Lifetime in seconds
		max_life = 1.0
	})
end

-- Function to start a mission
local function start_mission(mission_num)
	-- Reset VTOL state (spawn on landing pad 1)
	local spawn_x, spawn_y, spawn_z, spawn_yaw = LandingPads.get_spawn(1)
	spawn_y += SHIP_SPAWN_HEIGHT_OFFSET  -- Apply spawn height offset
	vtol:reset(spawn_x, spawn_y, spawn_z, spawn_yaw)

	-- Reset camera
	camera.x = 0
	camera.y = 3
	camera.z = -8
	camera.rx = 0
	camera.ry = 0

	-- Deactivate all smoke particles
	for particle in all(smoke_system.particles) do
		particle.active = false
		particle.life = 0
	end

	-- Clear speed lines
	speed_lines = {}
	speed_line_timer = 0

	-- Clear position history
	position_history = {}
	last_history_sample = 0

	-- Reset game state
	current_game_state = GAME_STATE.PLAYING
	death_timer = 0
	smoke_spawn_timer = 0

	-- Start mission based on number
	Mission.reset()
	if mission_num == 1 then
		-- Get landing pad position for mission 1
		local pad_x, pad_y, pad_z = LandingPads.get_spawn(1)
		-- Mission 1: Simple tutorial - pick up cargo 100 meters west of landing pad
		-- Convert world coords to Aseprite coords: aseprite = (world / 4) + 64
		local cargo_world_x = pad_x - 10  -- 10 units west = 100 meters
		local cargo_world_z = pad_z
		local cargo_aseprite_x = (cargo_world_x / 4) + 64
		local cargo_aseprite_z = (cargo_world_z / 4) + 64
		Mission.start_cargo_mission({
			{aseprite_x = cargo_aseprite_x, aseprite_z = cargo_aseprite_z}
		}, pad_x or 0, pad_z or 0)
	end
	-- Add more missions here as they're created

	Menu.active = false
end

-- Function to reset game to initial state
local function reset_game()
	start_mission(1)  -- Restart current mission
end


-- draw_collision_wireframe is now in Collision module

-- Wrapper for render_mesh to track culling stats and use Renderer module
local function render_mesh(verts, faces, offset_x, offset_y, offset_z, sprite_override, is_ground, rot_pitch, rot_yaw, rot_roll, render_distance)
	-- Use provided render distance or default
	local effective_render_distance = render_distance or RENDER_DISTANCE
	-- If custom render distance provided, disable fog by setting fog start to same value
	local effective_fog_distance = render_distance and render_distance or FOG_START_DISTANCE

	-- Early culling check
	local obj_x = offset_x or 0
	local obj_z = offset_z or 0
	local dx = obj_x - camera.x
	local dz = obj_z - camera.z
	local dist_sq = dx*dx + dz*dz

	if not is_ground and dist_sq > effective_render_distance * effective_render_distance then
		objects_culled += 1
		return {}
	end

	objects_rendered += 1

	return Renderer.render_mesh(
		verts, faces, camera,
		offset_x, offset_y, offset_z,
		sprite_override, is_ground,
		rot_pitch, rot_yaw, rot_roll,
		effective_render_distance,
		GROUND_ALWAYS_BEHIND,
		effective_fog_distance
	)
end

-- Initialize menu at startup
Menu.init()

function _update()
	-- Calculate delta time (time since last frame)
	local current_time = time()
	delta_time = current_time - last_time
	last_time = current_time

	-- Handle menu updates
	if Menu.active then
		local action, mission_num = Menu.update(delta_time)
		if action == "start_mission" and mission_num then
			start_mission(mission_num)
		end
		return  -- Don't update game while in menu
	end

	-- Handle pause menu (TAB key)
	if key("tab") and not (last_tab_state) then
		Mission.show_pause_menu = not Mission.show_pause_menu
	end
	last_tab_state = key("tab")

	-- Toggle mission UI (G key)
	if key("g") and not (last_g_state) then
		show_mission_ui = not show_mission_ui
	end
	last_g_state = key("g")

	-- Handle pause menu actions
	if Mission.show_pause_menu then
		if key("q") and not (last_q_state) then
			-- Return to main menu
			Mission.reset()
			Mission.show_pause_menu = false
			Menu.active = true
			Menu.init()
		end
		last_q_state = key("q")
		return  -- Don't update game while paused
	end
	last_q_state = false

	-- Handle mission complete screen
	if Mission.complete_flag then
		-- Any key press returns to menu
		if stat(28) > 0 then  -- Check if any key was pressed
			Mission.reset()
			Menu.active = true
			Menu.init()
		end
		return  -- Don't update game while showing complete screen
	end

	-- Generate minimap cache on first frame
	if not minimap_terrain_cache and USE_HEIGHTMAP then
		minimap_terrain_cache = Minimap.generate_terrain_cache(Heightmap)
		Minimap.set_terrain_cache(minimap_terrain_cache)
	end

	-- Check for death
	if vtol.health <= 0 and current_game_state == GAME_STATE.PLAYING then
		current_game_state = GAME_STATE.DYING
		death_explosion_timer = 0
	end

	-- Handle dying state (continuous explosions)
	if current_game_state == GAME_STATE.DYING then
		death_explosion_timer += delta_time

		-- Spawn explosions rapidly
		if rnd(1) < 0.3 then  -- 30% chance each frame
			add_explosion(vtol)
		end

		-- Transition to dead state after explosion duration
		if death_explosion_timer >= DEATH_EXPLOSION_DURATION then
			current_game_state = GAME_STATE.DEAD
			death_timer = 0
		end

		-- Continue updating so we can see smoke and explosions (don't return)
	end

	-- Handle dead state (show death screen)
	if current_game_state == GAME_STATE.DEAD then
		death_timer += delta_time

		-- Check for restart input (any key or mouse click) after delay
		if DeathScreen.can_restart(death_timer) then
			if key("x") or key("z") or key("space") or key("return") then
				reset_game()
			end
		end

		-- Don't update game logic when dead
		return
	end

	-- Mouse camera control (drag-based rotation)
	local mouse_x, mouse_y, mouse_buttons = mouse()
	local left_button_down = mouse_buttons & 0x1 == 0x1

	if left_button_down then
		if not mouse_drag.active then
			-- Start dragging - record initial position and current rotation
			mouse_drag.active = true
			mouse_drag.start_x = mouse_x
			mouse_drag.start_y = mouse_y
			mouse_drag.base_rx = camera.rx
			mouse_drag.base_ry = camera.ry
		else
			-- Dragging - update rotation based on distance from start
			local delta_x = mouse_x - mouse_drag.start_x
			local delta_y = mouse_y - mouse_drag.start_y

			camera.ry = mouse_drag.base_ry + (delta_x / 240) * 0.5
			camera.rx = mouse_drag.base_rx + (delta_y / 135) * 0.3
		end
	else
		-- Button released - stop dragging
		mouse_drag.active = false
	end

	-- -- Rotate with Z and X (slower)
	-- local rot_speed = 0.005
	-- if btn(4) then  -- Z button
	-- 	camera.ry -= rot_speed
	-- end
	-- if btn(5) then  -- X button
	-- 	camera.ry += rot_speed
	-- end

	-- -- Move camera with arrow keys (forward/back/strafe)
	-- local move_speed = 0.05
	-- if btn(2) then  -- Up - move forward
	-- 	camera.z += move_speed * cos(camera.ry)
	-- 	camera.x += move_speed * sin(camera.ry)
	-- end
	-- if btn(3) then  -- Down - move backward
	-- 	camera.z -= move_speed * cos(camera.ry)
	-- 	camera.x -= move_speed * sin(camera.ry)
	-- end
	-- if btn(0) then  -- Left - strafe left
	-- 	camera.x += move_speed * cos(camera.ry)
	-- 	camera.z -= move_speed * sin(camera.ry)
	-- end
	-- if btn(1) then  -- Right - strafe right
	-- 	camera.x -= move_speed * cos(camera.ry)
	-- 	camera.z += move_speed * sin(camera.ry)
	-- end

	-- -- Vertical movement with W and S
	-- if key("w") then  -- W - move up
	-- 	camera.y += move_speed
	-- end
	-- if key("s") then  -- S - move down
	-- 	camera.y -= move_speed
	-- end

	-- Animate flame vertices using Ship module
	vtol:animate_flames()

	-- VTOL Physics Update
	-- Apply gravity
	vtol.vy += vtol.gravity

	-- Thruster controls (WASD or IJKL - can hold multiple at once)
	local shift_pressed = false  -- Declare outside for auto-level feature

	-- Disable controls when dying or dead
	if current_game_state == GAME_STATE.DYING or current_game_state == GAME_STATE.DEAD then
		-- Disable all thrusters
		vtol.thrusters[1].active = false
		vtol.thrusters[2].active = false
		vtol.thrusters[3].active = false
		vtol.thrusters[4].active = false
	else
		-- Check each key separately
		local w_pressed = key("w") or key("i")  -- W or I
		local a_pressed = key("a") or key("j")  -- A or J
		local s_pressed = key("s") or key("k")  -- S or K
		local d_pressed = key("d") or key("l")  -- D or L

		-- Special combination keys
		local space_pressed = key("space")  -- Fire all thrusters
		local n_pressed = key("n")  -- Fire A+D (left/right pair)
		local m_pressed = key("m")  -- Fire W+S (front/back pair)
		shift_pressed = key("lshift") or key("rshift")  -- Auto-level ship

		-- Update thruster active states
		if space_pressed then
			-- Space: fire all thrusters
			vtol.thrusters[1].active = true  -- Right (A)
			vtol.thrusters[2].active = true  -- Left (D)
			vtol.thrusters[3].active = true  -- Front (W)
			vtol.thrusters[4].active = true  -- Back (S)
		elseif n_pressed then
			-- N: fire left/right pair (A+D)
			vtol.thrusters[1].active = true  -- Right (A)
			vtol.thrusters[2].active = true  -- Left (D)
			vtol.thrusters[3].active = false
			vtol.thrusters[4].active = false
		elseif m_pressed then
			-- M: fire front/back pair (W+S)
			vtol.thrusters[1].active = false
			vtol.thrusters[2].active = false
			vtol.thrusters[3].active = true  -- Front (W)
			vtol.thrusters[4].active = true  -- Back (S)
		else
			-- Normal WASD/IJKL controls
			vtol.thrusters[1].active = a_pressed  -- Right thruster (A or J)
			vtol.thrusters[2].active = d_pressed  -- Left thruster (D or L)
			vtol.thrusters[3].active = w_pressed  -- Front thruster (W or I)
			vtol.thrusters[4].active = s_pressed  -- Back thruster (S or K)
		end
	end

	-- Height limit (400m ceiling) - disable thrusters if too high
	local max_height = 40  -- 400 meters (1 unit = 10 meters)
	if vtol.y >= max_height then
		-- Shut off all thrusters above ceiling
		vtol.thrusters[1].active = false
		vtol.thrusters[2].active = false
		vtol.thrusters[3].active = false
		vtol.thrusters[4].active = false
	end

	-- Precompute trig values (shared across all thrusters)
	local cos_pitch, sin_pitch = cos(vtol.pitch), sin(vtol.pitch)
	local cos_yaw, sin_yaw = cos(vtol.yaw), sin(vtol.yaw)
	local cos_roll, sin_roll = cos(vtol.roll), sin(vtol.roll)

	-- Apply thrust and torque for each active thruster
	for i, thruster in ipairs(vtol.thrusters) do
		if thruster.active then
			-- Thrust direction is always upward in local space (0, 1, 0)
			-- Transform this vector by the VTOL's rotation to get world space thrust

			-- Start with local up vector (0, 1, 0)
			local tx, ty, tz = 0, 1, 0

			-- Apply rotations: Yaw -> Pitch -> Roll
			-- Yaw (rotation around Y)
			local tx_yaw = tx * cos_yaw - tz * sin_yaw
			local tz_yaw = tx * sin_yaw + tz * cos_yaw

			-- Pitch (rotation around X)
			local ty_pitch = ty * cos_pitch - tz_yaw * sin_pitch
			local tz_pitch = ty * sin_pitch + tz_yaw * cos_pitch

			-- Roll (rotation around Z)
			local tx_roll = tx_yaw * cos_roll - ty_pitch * sin_roll
			local ty_roll = tx_yaw * sin_roll + ty_pitch * cos_roll

			-- Apply thrust in world space
			vtol.vx += tx_roll * vtol.thrust
			vtol.vy += ty_roll * vtol.thrust
			vtol.vz += tz_pitch * vtol.thrust

			-- Calculate torque: thrusters push from below, creating pitch and roll
			-- Thruster on left/right (x != 0) creates roll around Z axis
			-- Thruster on front/back (z != 0) creates pitch around X axis
			-- No direct yaw torque since thrusters push straight up
			vtol.vpitch += thruster.z * VTOL_TORQUE_PITCH  -- Front/back creates pitch
			vtol.vroll += -thruster.x * VTOL_TORQUE_ROLL   -- Left/right creates roll
		end
	end

	-- Update VTOL position
	vtol.x += vtol.vx
	vtol.y += vtol.vy
	vtol.z += vtol.vz

	-- Hard ceiling at 400m (40 world units)
	local max_height = 40  -- 400 meters
	if vtol.y > max_height then
		vtol.y = max_height  -- Clamp to ceiling
		if vtol.vy > 0 then
			vtol.vy = 0  -- Stop upward velocity
		end
	end

	-- Track position history for minimap trail
	if current_time - last_history_sample >= HISTORY_SAMPLE_RATE then
		add(position_history, {x = vtol.x, z = vtol.z, t = current_time})
		last_history_sample = current_time

		-- Remove old entries (older than 5 seconds)
		while #position_history > 0 and current_time - position_history[1].t > HISTORY_DURATION do
			deli(position_history, 1)
		end
	end

	-- Auto-level with shift key
	if shift_pressed then
		-- Smoothly reset rotation to level (zero pitch and roll)
		local level_speed = 0.05  -- How fast to level out
		vtol.pitch = vtol.pitch * (1 - level_speed)
		vtol.roll = vtol.roll * (1 - level_speed)
		-- Also dampen angular velocities heavily
		vtol.vpitch *= 0.8
		vtol.vroll *= 0.8
	end

	-- Update VTOL rotation
	vtol.pitch += vtol.vpitch
	vtol.yaw += vtol.vyaw
	vtol.roll += vtol.vroll

	-- Apply damping
	vtol.vx *= vtol.damping
	vtol.vy *= vtol.damping
	vtol.vz *= vtol.damping
	vtol.vpitch *= vtol.angular_damping
	vtol.vyaw *= vtol.angular_damping
	vtol.vroll *= vtol.angular_damping

	-- Map boundary collision (bounce back if out of bounds)
	if USE_HEIGHTMAP then
		local map_half_size = (Heightmap.MAP_SIZE * Heightmap.TILE_SIZE) / 2
		local bounce_damping = 0.5  -- Velocity reduction on bounce

		-- Check X bounds
		if vtol.x < -map_half_size then
			vtol.x = -map_half_size
			vtol.vx = abs(vtol.vx) * bounce_damping  -- Bounce back (reverse and dampen)
		elseif vtol.x > map_half_size then
			vtol.x = map_half_size
			vtol.vx = -abs(vtol.vx) * bounce_damping  -- Bounce back (reverse and dampen)
		end

		-- Check Z bounds
		if vtol.z < -map_half_size then
			vtol.z = -map_half_size
			vtol.vz = abs(vtol.vz) * bounce_damping  -- Bounce back (reverse and dampen)
		elseif vtol.z > map_half_size then
			vtol.z = map_half_size
			vtol.vz = -abs(vtol.vz) * bounce_damping  -- Bounce back (reverse and dampen)
		end
	end


	-- Building collision (check for rooftop landings and side collisions)
	local ground_height = 0  -- Track the highest surface beneath the VTOL

	for i, building in ipairs(buildings) do
		-- Get building bounds (using config for accurate dimensions)
		local config = building_configs[i]
		if config then
			local half_width = config.width
			local half_depth = config.depth
			local building_height = config.height * 2  -- Height is scaled by 2 in vertex generation

			-- Check if VTOL is within building's horizontal bounds using Collision module
			if Collision.point_in_box(vtol.x, vtol.z, building.x, building.z, half_width, half_depth) then
				-- VTOL is horizontally above/inside this building
				local building_top = building.y + building_height
				local building_bottom = building.y

				-- Check if VTOL is within the vertical bounds of the building
				if vtol.y > building_bottom and vtol.y < building_top then
					-- Side collision: VTOL is inside the building volume
					-- Teleport out to nearest edge using Collision module
					vtol.x, vtol.z = Collision.push_out_of_box(
						vtol.x, vtol.z,
						building.x, building.z,
						half_width, half_depth
					)

					-- Calculate collision velocity for damage
					local collision_speed = sqrt(vtol.vx*vtol.vx + vtol.vy*vtol.vy + vtol.vz*vtol.vz)
					if collision_speed > DAMAGE_BUILDING_THRESHOLD then
						local damage = collision_speed * DAMAGE_BUILDING_MULTIPLIER
						vtol:take_damage(damage)

						-- Spawn explosion effect at random engine
						add_explosion(vtol)
					end

					-- Kill velocity when hitting side
					vtol.vx *= 0.5
					vtol.vz *= 0.5
				elseif vtol.y >= building_top then
					-- Above building - rooftop is a potential landing surface
					ground_height = max(ground_height, building_top)
				end
			end
		end
	end

	-- Landing pad collision using collision object
	if landing_pad.collision then
		local bounds = landing_pad.collision:get_bounds()

		if Collision.point_in_box(vtol.x, vtol.z, landing_pad.x, landing_pad.z, bounds.half_width, bounds.half_depth) then
			-- VTOL is horizontally above/inside landing pad
			-- Check if VTOL is within the vertical bounds of the pad
			if vtol.y > bounds.bottom and vtol.y < bounds.top then
				-- Side collision with landing pad - push out using Collision module
				vtol.x, vtol.z = Collision.push_out_of_box(
					vtol.x, vtol.z,
					landing_pad.x, landing_pad.z,
					bounds.half_width, bounds.half_depth
				)

				-- Calculate collision velocity for damage
				local collision_speed = sqrt(vtol.vx*vtol.vx + vtol.vy*vtol.vy + vtol.vz*vtol.vz)
				if collision_speed > DAMAGE_BUILDING_THRESHOLD then
					local damage = collision_speed * DAMAGE_BUILDING_MULTIPLIER
					vtol:take_damage(damage)

					-- Spawn explosion effect at random engine
					add_explosion(vtol)
				end

				-- Kill velocity when hitting side
				vtol.vx *= 0.5
				vtol.vz *= 0.5
			elseif vtol.y >= bounds.top then
				-- Above landing pad - it's a landing surface
				ground_height = max(ground_height, bounds.top)
			end
		end
	end

	-- Ground/rooftop collision (use 0.5 offset for VTOL center)
	-- If using heightmap, sample terrain height at VTOL position
	local terrain_height = 0
	if USE_HEIGHTMAP then
		terrain_height = Heightmap.get_height(vtol.x, vtol.z)
	end

	local landing_height = max(ground_height, terrain_height) + 0.5
	local is_grounded = false
	if vtol.y < landing_height then
		-- Check impact velocity for damage
		if vtol.vy < DAMAGE_GROUND_THRESHOLD then  -- Hard landing
			local damage = abs(vtol.vy) * DAMAGE_GROUND_MULTIPLIER
			vtol:take_damage(damage)

			-- Spawn explosion effect at random engine
			add_explosion(vtol)
		end

		vtol.y = landing_height
		vtol.vy = 0
		is_grounded = true
		-- Dampen rotation when touching any surface
		vtol.vpitch *= VTOL_GROUND_PITCH_DAMPING
		vtol.vroll *= VTOL_GROUND_ROLL_DAMPING
	end

	-- Check if ship is on landing pad and repair if stationary
	is_on_landing_pad = false
	if landing_pad.collision and is_grounded then
		local bounds = landing_pad.collision:get_bounds()
		-- Check if ship is within landing pad horizontal bounds
		if Collision.point_in_box(vtol.x, vtol.z, landing_pad.x, landing_pad.z, bounds.half_width, bounds.half_depth) then
			-- Ship is on the landing pad
			is_on_landing_pad = true

			-- Calculate if ship is stationary (very low velocity)
			local total_velocity = sqrt(vtol.vx*vtol.vx + vtol.vy*vtol.vy + vtol.vz*vtol.vz)
			local total_angular_velocity = abs(vtol.vpitch) + abs(vtol.vyaw) + abs(vtol.vroll)

			if total_velocity < 0.01 and total_angular_velocity < 0.01 then
				-- Ship is stationary, increment repair timer
				repair_timer += delta_time

				-- Start repairing after delay
				if repair_timer >= REPAIR_DELAY and vtol.health < vtol.max_health then
					local repair_amount = REPAIR_RATE * delta_time
					vtol.health = min(vtol.health + repair_amount, vtol.max_health)

					-- Stop smoking if health is above 50%
					if vtol.health >= 50 then
						vtol.is_damaged = false
					end
				end
			else
				-- Ship is moving, reset repair timer
				repair_timer = 0
			end
		else
			repair_timer = 0
		end
	else
		repair_timer = 0
	end

	-- Smoke particle spawning (only when damaged)
	local health_percent = vtol.health / vtol.max_health * 100
	if health_percent <= 70 then
		smoke_spawn_timer += delta_time

		-- Adjust spawn rate based on damage severity
		-- Start with 3 particles at 70% health, scale up to 10 at 0% health
		local spawn_rate = smoke_spawn_rate
		local particles_to_spawn = 1
		if health_percent <= 50 then
			spawn_rate = 0.2
			particles_to_spawn = 2
		end
		if health_percent <= 30 then
			spawn_rate = 0.15
			particles_to_spawn = 3
		end

		-- Spawn new particles if timer expired
		if smoke_spawn_timer >= spawn_rate then
			smoke_spawn_timer = 0
			-- Spawn multiple particles based on damage severity
			for i = 1, particles_to_spawn do
				smoke_system:spawn(vtol.x, vtol.y, vtol.z, vtol.vx, vtol.vy, vtol.vz)
			end
		end
	end

	-- Update explosion effects
	for i = #explosions, 1, -1 do
		local exp = explosions[i]
		exp.time += delta_time
		if exp.time >= exp.max_time then
			deli(explosions, i)
		end
	end

	-- Update smoke particle system
	smoke_system:update(delta_time)

	-- Update and spawn speed lines
	local ship_speed = sqrt(vtol.vx * vtol.vx + vtol.vy * vtol.vy + vtol.vz * vtol.vz)

	-- Spawn rate based on speed (more lines at higher speeds)
	local spawn_rate = SPEED_LINE_SPAWN_RATE
	if ship_speed > 0.1 then
		spawn_rate = SPEED_LINE_SPAWN_RATE / (1 + ship_speed * 5)  -- Faster spawning at high speed
	end

	speed_line_timer += delta_time
	if speed_line_timer >= spawn_rate and #speed_lines < MAX_SPEED_LINES then
		-- Spawn multiple lines at high speeds
		local num_to_spawn = flr(ship_speed * 10) + 1
		num_to_spawn = min(num_to_spawn, 3)  -- Cap at 3 per frame
		for i = 1, num_to_spawn do
			spawn_speed_line(vtol)
		end
		speed_line_timer = 0
	end

	-- Update speed lines (they don't move, just fade out)
	for i = #speed_lines, 1, -1 do
		local speed_line = speed_lines[i]
		speed_line.life -= delta_time

		if speed_line.life <= 0 then
			deli(speed_lines, i)
		end
	end

	-- Camera follows VTOL with smooth lerp (doesn't drift too far)
	-- local camera_offset = 5  -- Distance behind VTOL
	local camera_lerp_speed = 0.1  -- How fast camera catches up

	-- Target camera position (centered on VTOL)
	local target_x = vtol.x
	local target_y = vtol.y
	local target_z = vtol.z

	-- Smoothly move camera toward target
	camera.x += (target_x - camera.x) * camera_lerp_speed
	camera.y += (target_y - camera.y) * camera_lerp_speed
	camera.z += (target_z - camera.z) * camera_lerp_speed

	-- Update mission (check cargo pickups, update objectives)
	-- Check if right mouse button is held
	local mouse_x, mouse_y, mouse_buttons = mouse()
	local right_click_held = (mouse_buttons & 0x2) == 0x2

	-- Check if ship is landed (low velocity and touching ground)
	local is_landed = vtol.vy < 0.01 and vtol.vy > -0.01 and vtol.y < 2

	Mission.update(delta_time, vtol.x, vtol.y, vtol.z, right_click_held, is_landed, vtol.pitch, vtol.yaw, vtol.roll)

end

function _draw()
	-- Handle menu rendering
	if Menu.active then
		Menu.draw(camera, render_mesh)
		return
	end

	cls(5)  -- Background color index 6

	-- Update FPS counter (count rendered frames)
  	current_fps = stat(7)


	-- Reset culling counters
	objects_rendered = 0
	objects_culled = 0

	-- Collect all faces from all meshes
	local all_faces = {}

	-- Render skybox (always at camera position, draws behind everything)
	local skybox_sorted = render_mesh(skybox_verts, skybox_faces, camera.x, camera.y, camera.z, nil, true)  -- true = no distance culling
	for _, f in ipairs(skybox_sorted) do
		f.depth = 999999  -- Push skybox to back (always draws behind)
		f.is_skybox = true  -- Mark as skybox to exclude from fog
		add(all_faces, f)
	end

	-- Generate and render ground plane dynamically around camera
	local ground_verts, ground_faces = generate_ground_around_camera(camera.x, camera.z)

	-- Animate water: swap between SPRITE_WATER and SPRITE_WATER2 every 0.5 seconds
	local water_frame = flr(time() * 2) % 2  -- 0 or 1, changes every 0.5 seconds
	local water_sprite = water_frame == 0 and SPRITE_WATER or SPRITE_WATER2

	-- Update water sprite on all water faces
	for _, face in ipairs(ground_faces) do
		if face[4] == SPRITE_WATER or face[4] == SPRITE_WATER2 then
			face[4] = water_sprite
		end
	end

	local ground_sorted = render_mesh(ground_verts, ground_faces, 0, 0, 0, nil, true)
	for _, f in ipairs(ground_sorted) do
		add(all_faces, f)
	end

	-- Render all buildings
	for _, building in ipairs(buildings) do
		local building_faces = render_mesh(
			building.verts,
			building.faces,
			building.x,
			building.y,
			building.z,
			building.sprite_override
		)
		for _, f in ipairs(building_faces) do
			add(all_faces, f)
		end
	end

	-- Render landing pad
	local pad_faces = render_mesh(
		landing_pad.verts,
		landing_pad.faces,
		landing_pad.x,
		landing_pad.y,
		landing_pad.z,
		landing_pad.sprite_override
	)
	for _, f in ipairs(pad_faces) do
		add(all_faces, f)
	end

	-- Render all trees
	for _, tree in ipairs(trees) do
		local tree_faces = render_mesh(
			tree.verts,
			tree.faces,
			tree.x,
			tree.y,
			tree.z,
			tree.sprite_override
		)
		for _, f in ipairs(tree_faces) do
			add(all_faces, f)
		end
	end

	-- Render all cargo objects (with animation and scaling)
	for cargo in all(Mission.cargo_objects) do
		-- Skip only if delivered (show when attached)
		if cargo.state ~= "delivered" then
			-- Scale vertices to 50% for consistent size
			local scaled_verts = {}
			for _, v in ipairs(cargo.verts) do
				add(scaled_verts, vec(v.x * cargo.scale, v.y * cargo.scale, v.z * cargo.scale))
			end

			local cargo_faces = render_mesh(
				scaled_verts,
				cargo.faces,
				cargo.x,
				cargo.y + cargo.bob_offset,
				cargo.z,
				nil,  -- no sprite override
				false,  -- not ground
				cargo.pitch, cargo.yaw, cargo.roll  -- Use cargo rotation (matches ship when attached)
			)
			for _, f in ipairs(cargo_faces) do
				add(all_faces, f)
			end
		end
	end

	-- Get sphere faces (floating above the city)
	-- local sphere_sorted = render_mesh(sphere_verts, sphere_faces, 0, 5, 0)
	-- for _, f in ipairs(sphere_sorted) do
	-- 	add(all_faces, f)
	-- end

	-- Render smoke particles using particle system (camera-facing billboards)
	local smoke_faces = smoke_system:render(render_mesh, camera)
	for _, f in ipairs(smoke_faces) do
		f.is_vtol = true  -- Mark smoke as VTOL-related
		add(all_faces, f)
	end

	-- Calculate if ship should flash (critically damaged)
	local health_percent = vtol.health / vtol.max_health
	local use_damage_sprite = false
	if health_percent < 0.2 then  -- Below 20%
		use_damage_sprite = (time() * 2) % 1 > 0.5  -- Flash on/off (slower)
	end

	-- Get filtered faces from Ship module
	local vtol_faces_filtered = vtol:get_render_faces(use_damage_sprite)

	local vtol_sorted = render_mesh(
		vtol.verts,
		vtol_faces_filtered,
		vtol.x,
		vtol.y,
		vtol.z,
		nil,  -- no sprite override
		false,  -- not ground
		vtol.pitch,
		vtol.yaw,
		vtol.roll
	)
	for _, f in ipairs(vtol_sorted) do
		f.is_vtol = true  -- Mark VTOL faces
		add(all_faces, f)
	end

	-- Special case: VTOL always renders in front when landed on a surface
	-- Check if VTOL is within horizontal bounds of landing pad or any building
	local vtol_on_surface = false

	-- Check landing pad bounds
	local pad_hw, pad_hd = landing_pad.width / 2, landing_pad.depth / 2
	if abs(vtol.x - landing_pad.x) < pad_hw and abs(vtol.z - landing_pad.z) < pad_hd then
		-- VTOL is above/on landing pad
		if vtol.y <= landing_pad.height + 1 then  -- Within 1m of landing pad top
			vtol_on_surface = true
		end
	end

	-- Check building bounds
	if not vtol_on_surface then
		for i, building in ipairs(buildings) do
			local config = building_configs[i]
			if config then
				local hw, hd = config.width, config.depth
				local building_height = config.height * 2
				if abs(vtol.x - building.x) < hw and abs(vtol.z - building.z) < hd then
					-- VTOL is above/on building
					if vtol.y <= building_height + 1 then  -- Within 1m of building top
						vtol_on_surface = true
						break
					end
				end
			end
		end
	end

	-- If VTOL is on a surface, bias ONLY VTOL faces to render in front
	-- Landing pad and buildings still sort normally with each other
	if vtol_on_surface then
		for _, f in ipairs(all_faces) do
			-- Only bias faces marked as VTOL (ship, flames, smoke)
			if f.is_vtol then
				f.depth = f.depth - 100  -- Move VTOL/smoke faces much closer for sorting
			end
		end
	end

	-- Sort all faces using Renderer module
	Renderer.sort_faces(all_faces)

	-- Draw all faces using Renderer module
	Renderer.draw_faces(all_faces, false)

	-- Health bar
	local health_bar_x = 2
	local health_bar_y = 250
	local health_bar_width = 100
	local health_bar_height = 10

	-- Background (dark)
	rectfill(health_bar_x, health_bar_y, health_bar_x + health_bar_width, health_bar_y + health_bar_height, 1)

	-- Health fill (color based on health level)
	local health_percent = vtol.health / vtol.max_health
	local health_width = health_bar_width * max(0, health_percent)
	local health_color = 11  -- Green
	if health_percent < 0.3 then
		health_color = 8  -- Red
	elseif health_percent < 0.6 then
		health_color = 9  -- Orange
	end

	rectfill(health_bar_x, health_bar_y, health_bar_x + health_width, health_bar_y + health_bar_height, health_color)

	-- Border
	rect(health_bar_x, health_bar_y, health_bar_x + health_bar_width, health_bar_y + health_bar_height, 1)

	-- Health text
	print("HULL: "..flr(max(0, vtol.health)).."%", health_bar_x + 2, health_bar_y + 2, 1)

	-- Repair indicator (show when on landing pad and repairing)
	if is_on_landing_pad and repair_timer >= REPAIR_DELAY and vtol.health < vtol.max_health then
		-- Flash "REPAIRING" text
		if (time() * 2) % 1 > 0.5 then
			print("REPAIRING", health_bar_x + health_bar_width + 5, health_bar_y + 1, 11)
		end
	end

	-- Control hints (left side)
	local hint_x, hint_y = 2, 132
	print("CONTROLS:", hint_x, hint_y, 7)
	hint_y += 10
	print("Space: All thrusters", hint_x, hint_y, 6)
	hint_y += 8
	print("N:     Left+Right", hint_x, hint_y, 6)
	hint_y += 8
	print("M:     Front+Back", hint_x, hint_y, 6)
	hint_y += 8
	print("Shift: Auto-level", hint_x, hint_y, 6)

	-- -- Debug: show button states
	-- local w_state = key("w") and "W" or "-"
	-- local a_state = key("a") and "A" or "-"
	-- local s_state = key("s") and "S" or "-"
	-- local d_state = key("d") and "D" or "-"
	-- print("Keys: "..w_state.." "..a_state.." "..s_state.." "..d_state, 2, 42, 11)

	-- -- Debug: show active thrusters
	-- local active_str = "Thrusters: "
	-- if vtol.thrusters[1].active then active_str = active_str.."R " end
	-- if vtol.thrusters[2].active then active_str = active_str.."L " end
	-- if vtol.thrusters[3].active then active_str = active_str.."F " end
	-- if vtol.thrusters[4].active then active_str = active_str.."B " end
	-- print(active_str, 2, 50, 10)

	-- Draw thruster key indicators at thruster screen positions
	-- Show which thrusters are firing based on actual active state (includes special keys)
	-- Engine positions are at indices 1-4 in vtol.thrusters
	-- 1=Right(A), 2=Left(D), 3=Front(W), 4=Back(S)
	local thruster_keys = {
		{idx = 1, key = "A", active = vtol.thrusters[1].active},
		{idx = 2, key = "D", active = vtol.thrusters[2].active},
		{idx = 3, key = "W", active = vtol.thrusters[3].active},
		{idx = 4, key = "S", active = vtol.thrusters[4].active},
	}

	-- Precompute ship rotation matrices
	local cos_pitch, sin_pitch = cos(vtol.pitch), sin(vtol.pitch)
	local cos_yaw, sin_yaw = cos(vtol.yaw), sin(vtol.yaw)
	local cos_roll, sin_roll = cos(vtol.roll), sin(vtol.roll)

	for _, tk in ipairs(thruster_keys) do
		local thruster = vtol.thrusters[tk.idx]
		if thruster then
			-- Start with thruster local position
			local tx, ty, tz = thruster.x, 0, thruster.z

			-- Apply ship rotation (yaw -> pitch -> roll)
			-- Yaw (Y axis)
			local tx_yaw = tx * cos_yaw - tz * sin_yaw
			local tz_yaw = tx * sin_yaw + tz * cos_yaw

			-- Pitch (X axis)
			local ty_pitch = ty * cos_pitch - tz_yaw * sin_pitch
			local tz_pitch = ty * sin_pitch + tz_yaw * cos_pitch

			-- Roll (Z axis)
			local tx_roll = tx_yaw * cos_roll - ty_pitch * sin_roll
			local ty_roll = tx_yaw * sin_roll + ty_pitch * cos_roll

			-- Transform to world space
			tx = tx_roll + vtol.x - camera.x
			ty = ty_roll + vtol.y - camera.y
			tz = tz_pitch + vtol.z - camera.z

			-- Apply camera rotation (Y axis then X axis)
			local cos_ry, sin_ry = cos(camera.ry), sin(camera.ry)
			local cos_rx, sin_rx = cos(camera.rx), sin(camera.rx)

			local tx2 = tx * cos_ry - tz * sin_ry
			local tz2 = tx * sin_ry + tz * cos_ry

			local ty2 = ty * cos_rx - tz2 * sin_rx
			local tz3 = ty * sin_rx + tz2 * cos_rx

			-- Move away from camera
			local cam_dist = 5
			tz3 += cam_dist

			-- Project to screen
			if tz3 > 0.01 then
				local fov = 70
				local fov_rad = fov * 0.5 * 0.0174533
				local tan_half_fov = sin(fov_rad) / cos(fov_rad)

				local px = tx2 / tz3 * (270 / tan_half_fov) + 240
				local py = ty2 / tz3 * (270 / tan_half_fov) + 135

				-- Draw key letter with 20px offset above thruster
				-- Red if firing (active), grey if not
				local color = tk.active and 8 or 6
				print(tk.key, px - 2, py - 24, color)
			end
		end
	end

	-- Draw minimap using Minimap module
	Minimap.draw(camera, vtol, buildings, building_configs, landing_pad, Heightmap, position_history, Mission.cargo_objects)

	-- Draw 3D compass (cross/diamond shape with red and grey arrows)
	-- Side view: <> (diamond), Front view: X (cross)
	-- Two red arrows (north/south axis) and two grey arrows (east/west axis)
	local compass_x = 240  -- Center of screen
	local compass_y = 240  -- Bottom middle
	local compass_size = 12

	-- Black box background for compass and altitude (4 pixels wider, 8 pixels less tall)
	local box_x1 = compass_x - compass_size - 3
	local box_y1 = compass_y - compass_size + 1
	local box_x2 = compass_x + 64
	local box_y2 = compass_y + compass_size - 1
	rectfill(box_x1, box_y1, box_x2, box_y2, 0)
	rect(box_x1, box_y1, box_x2, box_y2, 7)  -- White border

	-- Create 4 arrow tips in world space (forming a 3D cross)
	-- Red arrows: North (+Z) and South (-Z)
	-- Grey arrows: East (+X) and West (-X)
	local points_3d = {
		{x = 0, y = 0, z = compass_size},    -- 1: North tip (red)
		{x = 0, y = 0, z = -compass_size},   -- 2: South tip (grey)
		{x = compass_size, y = 0, z = 0},    -- 3: East tip (grey)
		{x = -compass_size, y = 0, z = 0},   -- 4: West tip (grey)
		{x = 0, y = 0, z = 0},               -- 5: Center
	}

	-- Transform points by camera rotation and project to screen
	local cos_pitch, sin_pitch = cos(camera.rx), sin(camera.rx)
	local cos_yaw, sin_yaw = cos(camera.ry), sin(camera.ry)

	local projected_points = {}
	for i, p in ipairs(points_3d) do
		-- Rotate by camera yaw (Y axis)
		local x_yaw = p.x * cos_yaw - p.z * sin_yaw
		local z_yaw = p.x * sin_yaw + p.z * cos_yaw

		-- Rotate by camera pitch (X axis)
		local y_pitch = p.y * cos_pitch - z_yaw * sin_pitch
		local z_pitch = p.y * sin_pitch + z_yaw * cos_pitch

		-- Project to screen (orthographic)
		projected_points[i] = {
			x = compass_x + x_yaw,
			y = compass_y + y_pitch,
			z = z_pitch  -- Store depth for sorting
		}
	end

	-- Create arrows (lines from center to tips)
	local arrows = {
		{from = 5, to = 1, color = 8, z = projected_points[1].z},  -- North (red)
		{from = 5, to = 2, color = 5, z = projected_points[2].z},  -- South (grey)
		{from = 5, to = 3, color = 5, z = projected_points[3].z},  -- East (grey)
		{from = 5, to = 4, color = 5, z = projected_points[4].z},  -- West (grey)
	}

	-- Sort arrows by depth (back to front)
	for i = 1, #arrows do
		for j = i + 1, #arrows do
			if arrows[i].z > arrows[j].z then
				arrows[i], arrows[j] = arrows[j], arrows[i]
			end
		end
	end

	-- Draw arrows in sorted order
	for _, arrow in ipairs(arrows) do
		local p1 = projected_points[arrow.from]
		local p2 = projected_points[arrow.to]
		line(p1.x, p1.y, p2.x, p2.y, arrow.color)
		-- Draw arrowhead (small circle at tip)
		circfill(p2.x, p2.y, 1, arrow.color)
	end

	-- Center dot
	circfill(compass_x, compass_y, 2, 0)  -- Black center
	circ(compass_x, compass_y, 2, 7)  -- White outline

	-- Draw cargo direction indicator (orange arrow)
	if Mission.active and Mission.cargo_objects and #Mission.cargo_objects > 0 then
		-- Find nearest cargo that's not attached or delivered
		local nearest_cargo = nil
		local nearest_dist = 999999
		for cargo in all(Mission.cargo_objects) do
			if cargo.state ~= "attached" and cargo.state ~= "delivered" then
				local dx = cargo.x - vtol.x
				local dz = cargo.z - vtol.z
				local dist = sqrt(dx*dx + dz*dz)
				if dist < nearest_dist then
					nearest_dist = dist
					nearest_cargo = cargo
				end
			end
		end

		-- Draw arrow pointing to nearest cargo
		if nearest_cargo then
			local dx = nearest_cargo.x - vtol.x
			local dz = nearest_cargo.z - vtol.z

			-- Create 3D point in direction of cargo (invert for correct direction)
			local cargo_point = {x = -dx, y = 0, z = -dz}
			-- Normalize to compass size
			local mag = sqrt(dx*dx + dz*dz)
			if mag > 0.01 then
				cargo_point.x = (-dx / mag) * compass_size
				cargo_point.z = (-dz / mag) * compass_size

				-- Transform by camera rotation
				local x_yaw = cargo_point.x * cos_yaw - cargo_point.z * sin_yaw
				local z_yaw = cargo_point.x * sin_yaw + cargo_point.z * cos_yaw
				local y_pitch = 0 * cos_pitch - z_yaw * sin_pitch

				-- Project to screen
				local cargo_screen_x = compass_x + x_yaw
				local cargo_screen_y = compass_y + y_pitch

				-- Draw orange arrow to cargo
				line(compass_x, compass_y, cargo_screen_x, cargo_screen_y, 9)  -- Orange
				circfill(cargo_screen_x, cargo_screen_y, 2, 9)  -- Orange arrowhead
			end
		end
	end

	-- Altitude counter (1 world unit = 10 meters)
	local altitude_meters = vtol.y * 10
	print("ALT: "..flr(altitude_meters).."m", compass_x + 20, compass_y - 3, 11)

	-- Draw explosion effects (dithered colored circles)
	for exp in all(explosions) do
		-- Calculate animation progress (0 to 1)
		local progress = exp.time / exp.max_time

		-- Radius grows then shrinks
		local radius = exp.max_radius * (1 - progress)

		-- Transform explosion position to screen space
		local ex = exp.x - camera.x
		local ey = exp.y - camera.y
		local ez = exp.z - camera.z

		-- Apply camera rotation
		local cos_ry, sin_ry = cos(camera.ry), sin(camera.ry)
		local cos_rx, sin_rx = cos(camera.rx), sin(camera.rx)

		local ex2 = ex * cos_ry - ez * sin_ry
		local ez2 = ex * sin_ry + ez * cos_ry

		local ey2 = ey * cos_rx - ez2 * sin_rx
		local ez3 = ey * sin_rx + ez2 * cos_rx

		-- Move away from camera
		ez3 += 5

		-- Project to screen
		if ez3 > 0.01 then
			local fov = 70
			local fov_rad = fov * 0.5 * 0.0174533
			local tan_half_fov = sin(fov_rad) / cos(fov_rad)

			local sx = ex2 / ez3 * (270 / tan_half_fov) + 240
			local sy = ey2 / ez3 * (270 / tan_half_fov) + 135

			-- Draw dithered explosion circles
			if radius >= 1 then
				-- Outer layer (yellow/orange dither)
				for i = 0, radius do
					local dither = (flr(sx + i) + flr(sy)) % 2
					local color = dither == 0 and 10 or 9  -- Yellow/Orange dither
					circ(sx, sy, i, color)
				end

				-- Inner core (red/orange)
				if radius > 2 then
					for i = 0, radius / 2 do
						local dither = (flr(sx + i) + flr(sy + 1)) % 2
						local color = dither == 0 and 8 or 9  -- Red/Orange dither
						circ(sx, sy, i, color)
					end
				end
			end
		end
	end

	-- Draw speed lines (3D line particles)
	for speed_line in all(speed_lines) do
		-- Transform line position to camera space
		local lx = speed_line.x - camera.x
		local ly = speed_line.y - camera.y
		local lz = speed_line.z - camera.z

		-- Apply camera rotation
		local cos_ry, sin_ry = cos(camera.ry), sin(camera.ry)
		local cos_rx, sin_rx = cos(camera.rx), sin(camera.rx)

		local lx2 = lx * cos_ry - lz * sin_ry
		local lz2 = lx * sin_ry + lz * cos_ry

		local ly2 = ly * cos_rx - lz2 * sin_rx
		local lz3 = ly * sin_rx + lz2 * cos_rx

		-- Move away from camera
		lz3 += 5

		-- Color based on starting point depth: 5 (darkest/far), 22 (mid), 6 (lightest/near)
		local color = 5  -- Default dark
		if lz3 < 8 then
			color = 6  -- Lightest (closest)
		elseif lz3 < 15 then
			color = 22  -- Mid-tone
		end

		-- Project to screen
		if lz3 > 0.01 then
			local fov = 70
			local fov_rad = fov * 0.5 * 0.0174533
			local tan_half_fov = sin(fov_rad) / cos(fov_rad)

			local sx1 = lx2 / lz3 * (270 / tan_half_fov) + 240
			local sy1 = ly2 / lz3 * (270 / tan_half_fov) + 135

			-- Calculate line end point using stored fixed length and direction
			local end_x = speed_line.x + speed_line.dir_x * speed_line.length
			local end_y = speed_line.y + speed_line.dir_y * speed_line.length
			local end_z = speed_line.z + speed_line.dir_z * speed_line.length

			-- Transform end point
			local ex = end_x - camera.x
			local ey = end_y - camera.y
			local ez = end_z - camera.z

			local ex2 = ex * cos_ry - ez * sin_ry
			local ez2 = ex * sin_ry + ez * cos_ry

			local ey2 = ey * cos_rx - ez2 * sin_rx
			local ez3 = ey * sin_rx + ez2 * cos_rx
			ez3 += 5

			if ez3 > 0.01 then
				local sx2 = ex2 / ez3 * (270 / tan_half_fov) + 240
				local sy2 = ey2 / ez3 * (270 / tan_half_fov) + 135

				-- Draw line with fade based on lifetime
				local alpha = speed_line.life / speed_line.max_life
				if alpha > 0.3 then  -- Only draw if visible enough
					line(sx1, sy1, sx2, sy2, color)
				end
			end
		end
	end

	-- Draw physics wireframes (if enabled) using Collision module
	if DEBUG_SHOW_PHYSICS_WIREFRAME then
		-- Draw landing pad collision box (white) if within render distance
		local dx = landing_pad.x - camera.x
		local dz = landing_pad.z - camera.z
		if dx*dx + dz*dz <= RENDER_DISTANCE * RENDER_DISTANCE then
			if landing_pad.collision then
				Collision.draw_collision_wireframe(landing_pad.collision, camera, 7)
			end
		end

		-- Draw building collision boxes (red) if within render distance
		for _, building in ipairs(buildings) do
			local dx = building.x - camera.x
			local dz = building.z - camera.z
			if dx*dx + dz*dz <= RENDER_DISTANCE * RENDER_DISTANCE then
				Collision.draw_wireframe(
					camera,
					building.x,
					building.y,
					building.z,
					building.width,
					building.height,
					building.depth,
					8  -- Red
				)
			end
		end
	end

	-- Debug: Draw heightmap sprite to verify it's the correct one
	if DEBUG_SHOW_HEIGHTMAP_SPRITE then
		-- Draw sprite 256 in top-left corner (scaled down)
		-- Draw a small version (64x64) to see the heightmap
		local scale = 0.5  -- 50% size = 64x64 pixels
		local debug_x = 10
		local debug_y = 70

		-- Draw background box
		rectfill(debug_x - 2, debug_y - 2, debug_x + 64 + 2, debug_y + 64 + 2, 0)

		-- Draw the sprite scaled down
		sspr(64, 0, 0, 128, 128, debug_x, debug_y, 64, 64)

		-- Label
		print("HEIGHTMAP (64)", debug_x, debug_y - 10, 11)
	end

	-- Show death overlay (rendered on top of everything)
	if current_game_state == GAME_STATE.DEAD then
		DeathScreen.draw(death_timer)
	end

	-- Draw mission UI (objectives, navigation, pause menu, tether lines)
	-- Draw mission UI (toggle with G)
	if show_mission_ui then
		Mission.draw_ui(camera, vtol.x, vtol.y, vtol.z, 5)
	else
		-- Draw compact controls hint when mission UI is hidden
		local hint_box_x = 5
		local hint_box_y = 5
		local hint_text = "[TAB] Menu  [G] Mission"
		local hint_width = #hint_text * 4 + 36
		local hint_height = 12

		-- Draw dithered background
		fillp(0b0101101001011010, 0b0101101001011010)
		rectfill(hint_box_x, hint_box_y, hint_box_x + hint_width, hint_box_y + hint_height, 1)
		fillp()

		-- Draw border
		rect(hint_box_x, hint_box_y, hint_box_x + hint_width, hint_box_y + hint_height, 6)

		-- Draw text
		print(hint_text, hint_box_x + 3, hint_box_y + 3, 7)
	end
	
	-- Performance info (on top of mission box)
	if show_debug then
		local cpu = stat(1) * 100
		local debug_y = 5  -- Same as mission box top
		print("FPS: "..current_fps, 2, debug_y, 11)
		print("CPU: "..flr(cpu).."%", 2, debug_y + 8, 11)
		print("Tris: "..#all_faces, 2, debug_y + 16, 11)
		print("Objects: "..objects_rendered.."/"..objects_rendered+objects_culled.." (culled: "..objects_culled..")", 2, debug_y + 24, 11)
		print("VTOL: x="..flr(vtol.x*10)/10 .." y="..flr(vtol.y*10)/10 .." z="..flr(vtol.z*10)/10, 2, debug_y + 32, 10)
	end

	-- Velocity debug info
	if show_debug then
		local vel_total = sqrt(vtol.vx*vtol.vx + vtol.vy*vtol.vy + vtol.vz*vtol.vz)
		print("VEL: "..flr(vel_total*1000)/1000, 2, 47, 10)
		print("  vx="..flr(vtol.vx*1000)/1000 .." vy="..flr(vtol.vy*1000)/1000 .." vz="..flr(vtol.vz*1000)/1000, 2, 55, 6)
	end


	Mission.draw_pause_menu()
end
