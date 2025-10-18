-- PARAMETERS (EASY TO ADJUST!)

-- Mission testing
local mission_testing = false  -- If true, all missions are unlocked

-- Game mode
local game_mode = "arcade"  -- "arcade" or "simulation"

-- UI toggles
local show_debug = false
local show_mission_ui = true
local show_ship_collision_box = false  -- Toggle ship collision wireframe
local show_cargo_debug = false  -- Toggle cargo debug info (temporary for Mission 3 debug)

-- Debug menu toggles (toggle with number keys 1-9)
local debug_toggles = {
	player_ship = true,    -- 1: Toggle player ship rendering
	skybox = true,         -- 2: Toggle skybox rendering
	fog = true,            -- 3: Toggle fog effect
	debug_stats = true,    -- 4: Toggle debug stats/performance info
	buildings = true,      -- 5: Toggle building rendering
	terrain = true,        -- 6: Toggle terrain rendering
	fx = true,             -- 7: Toggle FX (particles, smoke, rain lines)
	ui = true,             -- 8: Toggle UI (HUD, compass, health bar, etc)
	bbox = false           -- 9: Toggle bounding box visualization
}

-- Ship collision box dimensions
local SHIP_COLLISION_WIDTH = 1.5   -- Default width
local SHIP_COLLISION_HEIGHT = 2.0  -- Default height
local SHIP_COLLISION_DEPTH = 1.5   -- Default depth

-- Ship collision box with cargo attached
local SHIP_CARGO_COLLISION_WIDTH = 2.0   -- Width with cargo
local SHIP_CARGO_COLLISION_HEIGHT = 2.0  -- Height with cargo
local SHIP_CARGO_COLLISION_DEPTH = 2.0   -- Depth with cargo

-- Function to get current ship collision dimensions
local function get_ship_collision_dimensions(cargo_objects)
	local has_attached_cargo = false
	if cargo_objects then
		for cargo in all(cargo_objects) do
			if cargo.state == "attached" then
				has_attached_cargo = true
				break
			end
		end
	end

	if has_attached_cargo then
		return SHIP_CARGO_COLLISION_WIDTH, SHIP_CARGO_COLLISION_HEIGHT, SHIP_CARGO_COLLISION_DEPTH
	else
		return SHIP_COLLISION_WIDTH, SHIP_COLLISION_HEIGHT, SHIP_COLLISION_DEPTH
	end
end

-- Load modules
include("src/engine/profiler.lua")
profile.enabled(true, true)
local Frustum = include("src/engine/frustum.lua")
local load_obj = include("src/engine/obj_loader.lua")
local ParticleSystem = include("src/engine/particle_system.lua")
local MathUtils = include("src/engine/math_utils.lua")
local Renderer = include("src/engine/renderer.lua")
local Collision = include("src/engine/collision.lua")
local Heightmap = include("src/heightmap.lua")
local Minimap = include("src/minimap.lua")
local Constants = include("src/constants.lua")
local DeathScreen = include("src/death_screen.lua")
local LandingPads = include("src/landing_pads.lua")
local Ship = include("src/ship.lua")
local Building = include("src/building.lua")
local Cargo = include("src/cargo.lua")
local Mission = include("src/mission.lua")
local Missions = include("src/missions.lua")
local Weather = include("src/weather.lua")
local Menu = include("src/menu.lua")
local Aliens = include("src/aliens.lua")
local Bullets = include("src/bullets.lua")
local Turret = include("src/turret.lua")
local Cutscene = include("src/cutscene.lua")
local AudioManager = include("src/audio_manager.lua")

-- Initialize audio system (loads all music files)
AudioManager.init()

-- Set shared module references
Mission.LandingPads = LandingPads
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
local last_c_state = false

-- UI toggles
local show_controls = false

-- Ship Spawn Configuration (EASY TO ADJUST!)
local SHIP_SPAWN_HEIGHT_OFFSET = -1 -- Height above landing pad surface (in world units, 1 unit = 10 meters)

-- Landing Pad Repair Configuration
local REPAIR_RATE = 10  -- Health points repaired per second when landed on pad
local REPAIR_DELAY = 1.0  -- Seconds of being stationary before repair starts

-- VTOL Physics Configuration - ARCADE MODE (assisted flight)
local VTOL_THRUST = 0.0025  -- Thrust force per thruster
local VTOL_TORQUE_YAW = 0.001  -- Torque around Y axis (yaw)
local VTOL_TORQUE_PITCH = 0.0008  -- Torque around X axis (pitch)
local VTOL_TORQUE_ROLL = 0.0008  -- Torque around Z axis (roll)
local VTOL_MASS = 30
local VTOL_GRAVITY = -0.005
local VTOL_DAMPING = 0.95  -- Linear velocity damping (air resistance)
local VTOL_ANGULAR_DAMPING = 0.85 -- Angular velocity damping (rotational drag)
local VTOL_GROUND_PITCH_DAMPING = 0.8  -- Rotation damping when touching ground (pitch)
local VTOL_GROUND_ROLL_DAMPING = 0.8   -- Rotation damping when touching ground (roll)

-- VTOL Physics Configuration - SIMULATION MODE (manual flight, no assists)
local SIM_VTOL_THRUST = 0.0025  -- Slightly weaker thrust (90%)
local SIM_VTOL_TORQUE_YAW = 0.0012  -- Stronger yaw torque (harder to control)
local SIM_VTOL_TORQUE_PITCH = 0.001  -- Stronger pitch torque
local SIM_VTOL_TORQUE_ROLL = 0.001  -- Stronger roll torque
local SIM_VTOL_MASS = 30
local SIM_VTOL_GRAVITY = -0.005
local SIM_VTOL_DAMPING = 0.95  -- Less air resistance (drifts more)
local SIM_VTOL_ANGULAR_DAMPING = 0.85 -- Less rotational drag (spins more)
local SIM_VTOL_GROUND_PITCH_DAMPING = 0.8  -- Less ground damping
local SIM_VTOL_GROUND_ROLL_DAMPING = 0.8   -- Less ground damping

-- Cargo weight penalties (when hauling cargo)
local CARGO_THRUST_PENALTY = 0.9 -- Thrust multiplier when cargo attached (75% = 25% reduction)
local CARGO_DAMPING_PENALTY = 1 -- Damping multiplier when cargo attached (low damping)
local CARGO_ANGULAR_DAMPING_PENALTY = 1.1  -- Angular damping multiplier when cargo attached

-- Damage Configuration
local DAMAGE_BUILDING_THRESHOLD = 0.05  -- Minimum speed for building collision damage
local DAMAGE_GROUND_THRESHOLD = -0.05  -- Minimum vertical velocity for ground impact damage
local DAMAGE_BUILDING_MULTIPLIER = 100  -- Damage multiplier for building collisions
local DAMAGE_GROUND_MULTIPLIER = 300   -- Damage multiplier for ground impacts

-- Rendering Configuration
local RENDER_DISTANCE = 20  -- Far plane / fog distance
local FOG_START_DISTANCE = 15  -- Distance where fog/fade begins (3m before render distance)
local WEATHER_RENDER_DISTANCE = 12  -- Reduced render distance in weather
local WEATHER_FOG_START_DISTANCE = 8  -- Fog starts closer in weather
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

	-- Normalize to unit sphere
	for i, v in ipairs(vertices) do
		local len = v:magnitude()
		if len > 0 then
			vertices[i] = vec(v.x/len, v.y/len, v.z/len)
		end
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

-- Mission 6 Skybox: Similar structure to standard skybox but larger
local m6_skybox_radius = 80
local m6_skybox_height = 50
local m6_skybox_verts = {}
local m6_skybox_faces = {}

-- Bottom ring (16 vertices at y=0 for smoother circle)
for i = 0, 15 do
	local angle = i / 16
	add(m6_skybox_verts, vec(
		cos(angle) * m6_skybox_radius,
		0,
		sin(angle) * m6_skybox_radius
	))
end

-- Top vertex
add(m6_skybox_verts, vec(0, m6_skybox_height, 0))  -- Vertex 17

-- Create triangular faces from bottom ring to top (sprite 29 is 64x32)
for i = 0, 15 do
	local b1 = i + 1                  -- Bottom ring vertex
	local b2 = (i + 1) % 16 + 1       -- Next bottom vertex (wrap around)
	local top = 17                     -- Top vertex

	-- UV coordinates wrap the 64px width around the 16 segments
	local u_start = (i / 16) * 64
	local u_end = ((i + 1) / 16) * 64

	-- Triangle from bottom edge to top
	add(m6_skybox_faces, {b1, b2, top, 29, vec(u_start, 32), vec(u_end, 32), vec((u_start+u_end)/2, 0)})
end

-- Ground plane generation now uses heightmap system
-- Wrapper for backward compatibility - auto-sizes based on render distance
function generate_ground_around_camera(cam_x, cam_z, render_distance)
	-- Pass nil for grid_count to auto-calculate, and render_distance for optimization
	local effective_render_dist = render_distance or RENDER_DISTANCE
	return Heightmap.generate_terrain(cam_x, cam_z, nil, effective_render_dist)
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
-- Using Aseprite tilemap coordinates (x, z) where (64, 64) = world center (0, 0)

-- Pad 1: Main spawn pad (Landing Pad A)
local landing_pad_1 = LandingPads.create_pad({
	id = 1,
	name = Constants.LANDING_PAD_NAMES[1],
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

-- Pad 2: Landing Pad B at aseprite coords (25, 36)
local landing_pad_2 = LandingPads.create_pad_aseprite({
	id = 2,
	name = Constants.LANDING_PAD_NAMES[2],
	aseprite_x = 25,
	aseprite_z = 36,
	mesh = landing_pad_mesh,
	scale = 0.5,
	sprite = SPRITE_LANDING_PAD,
	collision_dims = {
		width = pad_width,
		height = 2,
		depth = pad_depth
	},
	collision_y_offset = -1.0
})

-- Pad 3: Landing Pad C at aseprite coords (115, 112)
local landing_pad_3 = LandingPads.create_pad_aseprite({
	id = 3,
	name = Constants.LANDING_PAD_NAMES[3],
	aseprite_x = 115,
	aseprite_z = 112,
	mesh = landing_pad_mesh,
	scale = 0.5,
	sprite = SPRITE_LANDING_PAD,
	collision_dims = {
		width = pad_width,
		height = 2,
		depth = pad_depth
	},
	collision_y_offset = -1.0
})

-- Pad 4: Landing Pad D at aseprite coords (44, 95)
local landing_pad_4 = LandingPads.create_pad_aseprite({
	id = 4,
	name = Constants.LANDING_PAD_NAMES[4],
	aseprite_x = 44,
	aseprite_z = 95,
	mesh = landing_pad_mesh,
	scale = 0.5,
	sprite = SPRITE_LANDING_PAD,
	collision_dims = {
		width = pad_width,
		height = 2,
		depth = pad_depth
	},
	collision_y_offset = -1.0
})

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

-- Load UFO meshes
local ufo_fighter_mesh = load_obj("ufo_fighter.obj")
local ufo_mother_mesh = load_obj("ufo_mother.obj")

-- Set sprite for UFO meshes and scale UVs from 16x16 baseline
if ufo_fighter_mesh then
	for _, face in ipairs(ufo_fighter_mesh.faces) do
		face[4] = 28  -- Fighter sprite (32x32)
		-- OBJ loader outputs 16x16 UVs, scale by 2 for 32x32 sprite
		if face[5] then face[5] = vec(face[5].x * 2, face[5].y * 2) end
		if face[6] then face[6] = vec(face[6].x * 2, face[6].y * 2) end
		if face[7] then face[7] = vec(face[7].x * 2, face[7].y * 2) end
	end
end
if ufo_mother_mesh then
	for _, face in ipairs(ufo_mother_mesh.faces) do
		face[4] = 27  -- Mother ship sprite (128x128)
		-- OBJ loader outputs 16x16 UVs, scale by 8 for 128x128 sprite
		if face[5] then face[5] = vec(face[5].x * 8, face[5].y * 8) end
		if face[6] then face[6] = vec(face[6].x * 8, face[6].y * 8) end
		if face[7] then face[7] = vec(face[7].x * 8, face[7].y * 8) end
	end
end

-- Initialize turret
Turret.init()

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

-- Store initial camera state for menu
local initial_camera_state = {
	x = camera.x,
	y = camera.y,
	z = camera.z,
	rx = camera.rx,
	ry = camera.ry
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
local last_terrain_gen_time = 0
local cached_terrain_tiles = {}
local TERRAIN_GEN_RATE = 0.5  -- Generate terrain twice per second
local delta_time = 0

-- Pre-allocate userdata pool to avoid allocations per triangle
local vert_data_pool = userdata("f64", 6, 3)

-- Explosion effects (visual only)
local explosions = {}

-- Line particles for mother ship explosion
local line_particles = {}

-- Set alien explosion callbacks (must be after arrays are initialized)
Aliens.on_fighter_destroyed = function(x, y, z)
	-- Big explosion for fighter
	add(explosions, {
		x = x, y = y, z = z,
		time = 0,
		max_time = 1.0,  -- Long explosion
		max_radius = 20  -- Large radius
	})
	sfx(3)  -- Play destruction sound
end

Aliens.on_mothership_destroyed = function(x, y, z)
	-- Huge blue explosion for mother ship
	add(explosions, {
		x = x, y = y, z = z,
		time = 0,
		max_time = 2.0,  -- Very long explosion
		max_radius = 40,  -- Huge radius
		color = 12  -- Blue color
	})

	-- Spawn 30 line particles flying outward
	for i = 1, 30 do
		local angle_h = rnd(1)  -- Random horizontal angle
		local angle_v = rnd(0.5) - 0.25  -- Random vertical angle
		local speed = 5 + rnd(10)  -- Random speed 5-15 units/sec

		add(line_particles, {
			x = x, y = y, z = z,
			vx = cos(angle_h) * cos(angle_v) * speed,
			vy = sin(angle_v) * speed,
			vz = sin(angle_h) * cos(angle_v) * speed,
			time = 0,
			max_time = 2.0,  -- Live for 2 seconds
			color = 12  -- Blue
		})
	end
	sfx(3)  -- Play destruction sound
end

-- Set alien bullet spawn callback
Aliens.spawn_bullet = function(x, y, z, dir_x, dir_y, dir_z, max_range)
	Bullets.spawn_enemy_bullet(x, y, z, dir_x, dir_y, dir_z, max_range)
end

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
local current_landing_pad = nil  -- Currently occupied landing pad (nil if none)
local current_building = nil  -- Currently landed building (nil if none)

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
local function start_mission(mission_num, mode)
	-- Set game mode
	game_mode = mode or "arcade"

	-- Set controls visibility - show for mission 1, hide for others
	if mission_num == 1 then
		show_controls = true
	else
		show_controls = false
	end

	-- Reset VTOL state (spawn on landing pad 1)
	local spawn_x, spawn_y, spawn_z, spawn_yaw = LandingPads.get_spawn(1)
	spawn_y += SHIP_SPAWN_HEIGHT_OFFSET  -- Apply spawn height offset
	vtol:reset(spawn_x, spawn_y, spawn_z, spawn_yaw)

	-- Apply physics based on game mode
	if game_mode == "simulation" then
		vtol.thrust = SIM_VTOL_THRUST
		vtol.damping = SIM_VTOL_DAMPING
		vtol.angular_damping = SIM_VTOL_ANGULAR_DAMPING
	else
		vtol.thrust = VTOL_THRUST
		vtol.damping = VTOL_DAMPING
		vtol.angular_damping = VTOL_ANGULAR_DAMPING
	end

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

	-- Start level music
	AudioManager.start_level_music(mission_num)

	-- Start mission using missions module
	Mission.reset()
	Mission.current_mission_num = mission_num  -- Track current mission for unlocking
	-- Provide building references to Missions module
	Missions.buildings = buildings
	Missions.building_configs = building_configs
	Missions.Weather = Weather
	Missions.start(mission_num, Mission)

	-- Reset combat systems
	Aliens.reset()
	Bullets.reset()
	Turret.reset()

	-- Start first wave only for Mission 6
	if mission_num == 6 then
		Aliens.start_next_wave(vtol, LandingPads)
	end

	Menu.active = false
end

-- Function to reset game to initial state
local function reset_game()
	start_mission(1)  -- Restart current mission
end


-- draw_collision_wireframe is now in Collision module

-- Wrapper for render_mesh to track culling stats and use Renderer module
local function render_mesh(verts, faces, offset_x, offset_y, offset_z, sprite_override, is_ground, rot_pitch, rot_yaw, rot_roll, render_distance, fog_start_distance, is_skybox, no_cull)
	-- Use provided render distance or default
	local effective_render_distance = render_distance or RENDER_DISTANCE
	-- Use provided fog start distance or default
	local effective_fog_distance = fog_start_distance or FOG_START_DISTANCE

	-- Early culling checks for non-terrain objects
	local obj_x = offset_x or 0
	local obj_y = offset_y or 0
	local obj_z = offset_z or 0

	-- Skip culling for special objects (ship, skybox, etc.)
	if not is_ground and not is_skybox and not no_cull then
		-- Distance culling
		local dx = obj_x - camera.x
		local dz = obj_z - camera.z
		local dist_sq = dx*dx + dz*dz

		if dist_sq > effective_render_distance * effective_render_distance then
			objects_culled += 1
			return {}
		end
	end

	-- Only count non-terrain objects (terrain has its own counters)
	if not is_ground then
		objects_rendered += 1
	end

	return Renderer.render_mesh(
		verts, faces, camera,
		offset_x, offset_y, offset_z,
		sprite_override, is_ground,
		rot_pitch, rot_yaw, rot_roll,
		effective_render_distance,
		GROUND_ALWAYS_BEHIND,
		effective_fog_distance,
		is_skybox,
		debug_toggles.fog  -- Pass fog toggle state
	)
end

-- Helper function for printing text with drop shadow
local function print_shadow(text, x, y, color, shadow_color)
	shadow_color = shadow_color or 0  -- Default shadow color is black
	print(text, x + 1, y + 1, shadow_color)  -- Shadow
	print(text, x, y, color)  -- Main text
end

-- Initialize menu at startup
Menu.mission_testing = mission_testing
Menu.init()
AudioManager.start_menu_music()

function _update()
	-- Calculate delta time (time since last frame)
	local current_time = time()
	delta_time = current_time - last_time
	last_time = current_time
	
	-- Update audio manager (handles fades)
	AudioManager.update(delta_time)

	-- Handle cutscene
	if Cutscene.active then
		Cutscene.update(delta_time)
		if Cutscene.check_input() then
			-- Cutscene finished, mark story as played and unlock Mission 1
			Menu.mission_progress.story_played = true
			Menu.mission_progress.mission_1 = true
			store("/appdata/mission_progress.pod", Menu.mission_progress)

			-- Return to menu (fully reset to title screen)
			Menu.init()
			AudioManager.start_menu_music()
		end
		return  -- Don't update game while in cutscene
	end

	-- Handle menu updates
	if Menu.active then
		local action, mission_num, mode = Menu.update(delta_time)
		if action == "start_mission" and mission_num then
			start_mission(mission_num, mode)
		elseif action == "story" then
			-- Start story cutscene
			Menu.active = false
			Cutscene.start(1)
			AudioManager.start_cutscene_music()
		end
		return  -- Don't update game while in menu
	end

	-- Handle pause menu (TAB key)
	if key("tab") and not (last_tab_state) then
		Mission.show_pause_menu = not Mission.show_pause_menu
	end
	last_tab_state = key("tab")

	-- Toggle mission UI (G key) - but force show if mission complete
	if Mission.complete_flag then
		show_mission_ui = true  -- Force show when mission complete
	elseif key("g") and not (last_g_state) then
		show_mission_ui = not show_mission_ui
	end
	last_g_state = key("g")

	-- Toggle controls display (C key)
	if key("c") and not (last_c_state) then
		show_controls = not show_controls
	end
	last_c_state = key("c")

	-- Debug menu toggles (number keys 1-9) - only work if show_debug is enabled
	if show_debug then
		if key("1") and not (last_1_state) then
			debug_toggles.player_ship = not debug_toggles.player_ship
		end
		last_1_state = key("1")

		if key("2") and not (last_2_state) then
			debug_toggles.skybox = not debug_toggles.skybox
		end
		last_2_state = key("2")

		if key("3") and not (last_3_state) then
			debug_toggles.fog = not debug_toggles.fog
		end
		last_3_state = key("3")

		if key("4") and not (last_4_state) then
			debug_toggles.debug_stats = not debug_toggles.debug_stats
		end
		last_4_state = key("4")

		if key("5") and not (last_5_state) then
			debug_toggles.buildings = not debug_toggles.buildings
		end
		last_5_state = key("5")

		if key("6") and not (last_6_state) then
			debug_toggles.terrain = not debug_toggles.terrain
		end
		last_6_state = key("6")

		if key("7") and not (last_7_state) then
			debug_toggles.fx = not debug_toggles.fx
		end
		last_7_state = key("7")

		if key("8") and not (last_8_state) then
			debug_toggles.ui = not debug_toggles.ui
		end
		last_8_state = key("8")

		if key("9") and not (last_9_state) then
			debug_toggles.bbox = not debug_toggles.bbox
		end
		last_9_state = key("9")
	else
		-- Reset last states when debug is off so keys work again when re-enabled
		last_1_state = key("1")
		last_2_state = key("2")
		last_3_state = key("3")
		last_4_state = key("4")
		last_5_state = key("5")
		last_6_state = key("6")
		last_7_state = key("7")
		last_8_state = key("8")
		last_9_state = key("9")
	end

	-- Handle pause menu actions
	if Mission.show_pause_menu then
		if key("q") and not (last_q_state) then
			-- Return to main menu
			Mission.reset()
			Weather.set_enabled(false)  -- Disable weather when returning to menu
			Mission.show_pause_menu = false
			Menu.active = true
			Menu.mission_testing = mission_testing
			Menu.init()
			AudioManager.start_menu_music()
			-- Reset camera to initial menu state
			camera.x = initial_camera_state.x
			camera.y = initial_camera_state.y
			camera.z = initial_camera_state.z
			camera.rx = initial_camera_state.rx
			camera.ry = initial_camera_state.ry
		end
		last_q_state = key("q")
		return  -- Don't update game while paused
	end
	last_q_state = false

	-- Handle mission complete screen
	if Mission.complete_flag then
		-- Q key returns to menu
		if key("q") then
			Mission.reset()
			Weather.set_enabled(false)  -- Disable weather when mission complete
			Menu.active = true
			Menu.mission_testing = mission_testing
			Menu.init()
			AudioManager.start_menu_music()
			-- Reset camera to initial menu state
			camera.x = initial_camera_state.x
			camera.y = initial_camera_state.y
			camera.z = initial_camera_state.z
			camera.rx = initial_camera_state.rx
			camera.ry = initial_camera_state.ry
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
		sfx(3)  -- Play destruction sound
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
			AudioManager.start_death_music()
			death_timer = 0
		end

		-- Continue updating so we can see smoke and explosions (don't return)
	end

	-- Handle dead state (show death screen)
	if current_game_state == GAME_STATE.DEAD then
		death_timer += delta_time

		-- Check for any key input to return to menu after delay
		if DeathScreen.can_restart(death_timer) then
			-- Check for any key press (space, enter, x, z, escape, or any letter/number)
			if key("space") or key("return") or key("x") or key("z") or key("escape") or
			   key("a") or key("b") or key("c") or key("d") or key("e") or key("f") or
			   key("w") or key("s") then
				Menu.active = true
				Menu.init()
				AudioManager.start_menu_music()
				current_game_state = GAME_STATE.PLAYING
				death_timer = 0
			end
		end

		-- Don't update game logic when dead
		return
	end

	-- Mouse camera control (drag-based rotation)
	local mouse_x, mouse_y, mouse_buttons = mouse()
	local left_button_down = mouse_buttons & 0x1 == 0x1
	local right_button_down = mouse_buttons & 0x2 == 0x2

	-- Left or right mouse button rotates camera
	if left_button_down or right_button_down then
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

	-- Rotate camera with arrow keys
	local rot_speed = 0.01
	-- if key("z") or key("left") then
	if key("left") then
		camera.ry -= rot_speed
	end
	-- if key("x") or key("right") then
	if key("right") then
		camera.ry += rot_speed
	end
	if key("up") then
		camera.rx -= rot_speed * 0.6  -- Pitch up
	end
	if key("down") then
		camera.rx += rot_speed * 0.6  -- Pitch down
	end

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

		-- Arcade mode: Special combination keys
		local space_pressed = false
		local n_pressed = false
		local m_pressed = false

		if game_mode == "arcade" then
			space_pressed = key("space")  -- Fire all thrusters
			n_pressed = key("n")  -- Fire A+D (left/right pair)
			m_pressed = key("m")  -- Fire W+S (front/back pair)
			shift_pressed = key("lshift") or key("rshift")  -- Auto-level ship
		end

		-- Update thruster active states
		if space_pressed then
			-- Space: fire all thrusters (arcade only)
			vtol.thrusters[1].active = true  -- Right (A)
			vtol.thrusters[2].active = true  -- Left (D)
			vtol.thrusters[3].active = true  -- Front (W)
			vtol.thrusters[4].active = true  -- Back (S)
		elseif n_pressed then
			-- N: fire left/right pair (A+D) (arcade only)
			vtol.thrusters[1].active = true  -- Right (A)
			vtol.thrusters[2].active = true  -- Left (D)
			vtol.thrusters[3].active = false
			vtol.thrusters[4].active = false
		elseif m_pressed then
			-- M: fire front/back pair (W+S) (arcade only)
			vtol.thrusters[1].active = false
			vtol.thrusters[2].active = false
			vtol.thrusters[3].active = true  -- Front (W)
			vtol.thrusters[4].active = true  -- Back (S)
		else
			-- Normal WASD/IJKL controls (both modes)
			vtol.thrusters[1].active = a_pressed  -- Right thruster (A or J)
			vtol.thrusters[2].active = d_pressed  -- Left thruster (D or L)
			vtol.thrusters[3].active = w_pressed  -- Front thruster (W or I)
			vtol.thrusters[4].active = s_pressed  -- Back thruster (S or K)
		end
	end

	-- Height limit (500m ceiling) - disable thrusters if too high
	local max_height = 50  -- 500 meters (1 unit = 10 meters)
	if vtol.y >= max_height then
		-- Shut off all thrusters above ceiling
		vtol.thrusters[1].active = false
		vtol.thrusters[2].active = false
		vtol.thrusters[3].active = false
		vtol.thrusters[4].active = false
	end

	-- Count active thrusters for sound volume
	local active_thruster_count = 0
	for i, thruster in ipairs(vtol.thrusters) do
		if thruster.active then
			active_thruster_count += 1
		end
	end

	-- Play thruster sound if any thrusters are firing
	local thruster_channel = 4  -- Use channel 4 to avoid music channel conflicts (music uses 0-3)
	if active_thruster_count > 0 then
		-- Volume scales with number of active thrusters (0.6 to 1.0) - increased for testing
		local volume = 0.6 + (active_thruster_count / 4) * 0.4

		-- Check if sound is already playing on this channel
		local is_playing = (stat(464) & (1 << thruster_channel)) != 0

		if not is_playing then
			-- Start looping thruster sound
			sfx(1, thruster_channel, 0, -1, volume)  -- -1 length for infinite loop
		end
	else
		-- Stop thruster sound when no thrusters active
		sfx(-1, thruster_channel)
	end

	-- Precompute trig values (shared across all thrusters)
	local cos_pitch, sin_pitch = cos(vtol.pitch), sin(vtol.pitch)
	local cos_yaw, sin_yaw = cos(vtol.yaw), sin(vtol.yaw)
	local cos_roll, sin_roll = cos(vtol.roll), sin(vtol.roll)

	-- Check if cargo is attached (affects thrust and handling)
	local has_cargo = false
	if Mission.cargo_objects then
		for cargo in all(Mission.cargo_objects) do
			if cargo.state == "attached" then
				has_cargo = true
				break
			end
		end
	end

	-- Calculate effective thrust (reduced when hauling cargo)
	local effective_thrust = vtol.thrust
	if has_cargo then
		effective_thrust *= CARGO_THRUST_PENALTY
	end

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

			-- Apply thrust in world space (using effective thrust)
			vtol.vx += tx_roll * effective_thrust
			vtol.vy += ty_roll * effective_thrust
			vtol.vz += tz_pitch * effective_thrust

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

	-- Hard ceiling at 500m (50 world units)
	local max_height = 50  -- 500 meters
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

	-- Apply damping (reduced when hauling cargo)
	local effective_damping = vtol.damping
	local effective_angular_damping = vtol.angular_damping
	if has_cargo then
		effective_damping *= CARGO_DAMPING_PENALTY
		effective_angular_damping *= CARGO_ANGULAR_DAMPING_PENALTY
	end

	vtol.vx *= effective_damping
	vtol.vy *= effective_damping
	vtol.vz *= effective_damping
	vtol.vpitch *= effective_angular_damping
	vtol.vyaw *= effective_angular_damping
	vtol.vroll *= effective_angular_damping

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
	profile("physics:bbox_bldg")
	local ground_height = 0  -- Track the highest surface beneath the VTOL
	current_building = nil  -- Reset current building

	-- Get ship collision dimensions based on cargo state
	local ship_width, ship_height, ship_depth = get_ship_collision_dimensions(Mission.cargo_objects)
	local ship_half_width = ship_width / 2
	local ship_half_depth = ship_depth / 2

	for i, building in ipairs(buildings) do
		-- Get building bounds (using config for accurate dimensions)
		local config = building_configs[i]
		if config then
			local half_width = config.width
			local half_depth = config.depth
			local building_height = config.height * 2  -- Height is scaled by 2 in vertex generation

			-- Check if ship's bounding box overlaps with building's bounding box
			if Collision.box_overlap(vtol.x, vtol.z, ship_half_width, ship_half_depth, building.x, building.z, half_width, half_depth) then
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
					if building_top > ground_height then
						ground_height = building_top
						current_building = building  -- Track this building (will be checked later for landing)
					end
				end
			end
		end
	end
	profile("physics:bbox_bldg")

	-- Landing pad collision for all pads using collision objects
	profile("physics:bbox_pads")
	for _, pad in ipairs(LandingPads.get_all()) do
		if pad.collision then
			local bounds = pad.collision:get_bounds()

			if Collision.point_in_box(vtol.x, vtol.z, pad.x, pad.z, bounds.half_width, bounds.half_depth) then
				-- VTOL is horizontally above/inside landing pad
				-- Check if VTOL is within the vertical bounds of the pad
				if vtol.y > bounds.bottom and vtol.y < bounds.top then
					-- Side collision with landing pad - push out using Collision module
					vtol.x, vtol.z = Collision.push_out_of_box(
						vtol.x, vtol.z,
						pad.x, pad.z,
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
	end
	profile("physics:bbox_pads")

	-- Ground/rooftop collision (use 0.5 offset for VTOL center)
	profile("physics:terrain")
	-- If using heightmap, sample terrain height at VTOL position
	local terrain_height = 0
	if USE_HEIGHTMAP then
		terrain_height = Heightmap.get_height(vtol.x, vtol.z)
	end

	-- Instant death if ship touches water (terrain_height == 0)
	if terrain_height == 0 and vtol.y <= 0.5 then
		vtol:take_damage(9999)  -- Instant death
		add_explosion(vtol)
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
			sfx(8)  -- Play damage sound for ground collision
		end

		vtol.y = landing_height
		vtol.vy = 0
		is_grounded = true
		-- Dampen rotation when touching any surface
		vtol.vpitch *= VTOL_GROUND_PITCH_DAMPING
		vtol.vroll *= VTOL_GROUND_ROLL_DAMPING
	else
		-- Not grounded, clear building
		current_building = nil
	end

	-- Check if ship is on landing pad and repair if stationary
	is_on_landing_pad = false
	current_landing_pad = nil
	if is_grounded then
		-- Check all landing pads to see which one (if any) the ship is on
		for _, pad in ipairs(LandingPads.get_all()) do
			if pad.collision then
				local bounds = pad.collision:get_bounds()
				-- Check if ship is within landing pad horizontal bounds
				if Collision.point_in_box(vtol.x, vtol.z, pad.x, pad.z, bounds.half_width, bounds.half_depth) then
					-- Ship is on this landing pad
					is_on_landing_pad = true
					current_landing_pad = pad
					break  -- Only on one pad at a time
				end
			end
		end

		-- If on a landing pad, handle repair
		if is_on_landing_pad and current_landing_pad then
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
	profile("physics:terrain")

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

	-- Update line particles (ONLY FOR MISSION 6)
	if Mission.current_mission_num == 6 then
		for i = #line_particles, 1, -1 do
			local p = line_particles[i]
			p.time += delta_time
			p.x += p.vx * delta_time
			p.y += p.vy * delta_time
			p.z += p.vz * delta_time
			if p.time >= p.max_time then
				deli(line_particles, i)
			end
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

	-- Check if all engines are off
	local engines_off = not vtol.thrusters[1].active and
	                    not vtol.thrusters[2].active and
	                    not vtol.thrusters[3].active and
	                    not vtol.thrusters[4].active

	-- Pass is_on_landing_pad status to mission for cargo delivery
	Mission.update(delta_time, vtol.x, vtol.y, vtol.z, right_click_held, is_on_landing_pad, vtol.pitch, vtol.yaw, vtol.roll, engines_off, current_landing_pad)

	-- Update weather system
	Weather.update(delta_time, camera, vtol.y)
	Weather.apply_wind(vtol, vtol.y, is_on_landing_pad)

	-- Update combat systems (ONLY FOR MISSION 6)
	if Mission.current_mission_num == 6 then
		Aliens.update(delta_time, vtol, is_on_landing_pad)
		Bullets.update(delta_time)
	end

	-- Check bullet-terrain/building collisions (ONLY FOR MISSION 6)
	if Mission.current_mission_num == 6 then
		for i = #Bullets.bullets, 1, -1 do
		local bullet = Bullets.bullets[i]
		if bullet.active then
			-- Check terrain collision
			if USE_HEIGHTMAP then
				local terrain_height = Heightmap.get_height(bullet.x, bullet.z)
				if bullet.y <= terrain_height then
					bullet.active = false
					del(Bullets.bullets, bullet)
				end
			end

			-- Check building collisions (simple proximity check)
			for i, building in ipairs(buildings) do
				local config = building_configs[i]
				if config then
					local dx = abs(bullet.x - building.x)
					local dy = abs(bullet.y - (building.y + config.height))
					local dz = abs(bullet.z - building.z)
					if dx < config.width and dy < config.height and dz < config.depth then
						bullet.active = false
						del(Bullets.bullets, bullet)
						break
					end
				end
			end
		end
		end
	end

	if Mission.current_mission_num == 6 then
		Turret.update(delta_time, vtol, Aliens.get_all())
	end

	-- Turret auto-fire (only if can fire and not on landing pad) (ONLY FOR MISSION 6)
	if Mission.current_mission_num == 6 and not is_on_landing_pad and Turret.target and Turret.can_fire() then
		local dir_x, dir_y, dir_z = Turret.get_fire_direction(vtol)
		if dir_x then
			-- Fire from turret position
			local turret_x, turret_y, turret_z = Turret.get_position(vtol.x, vtol.y, vtol.z, vtol.pitch, vtol.yaw, vtol.roll)
			local bullet = Bullets.spawn_player_bullet(
				turret_x, turret_y, turret_z,
				dir_x, dir_y, dir_z,
				Turret.FIRE_RANGE
			)
			-- Only play sound if bullet was actually spawned (not on cooldown)
			if bullet then
				sfx(0)  -- Play shooting sound
			end
		end
	end

	-- Enemy firing (using Bullets.ENEMY_FIRE_RATE) (ONLY FOR MISSION 6)
	if Mission.current_mission_num == 6 then
		for fighter in all(Aliens.fighters) do
		if Aliens.can_fire_fighter(fighter, vtol) and fighter.fire_timer >= Bullets.ENEMY_FIRE_COOLDOWN then
			fighter.fire_timer = 0
			local dx = vtol.x - fighter.x
			local dy = vtol.y - fighter.y
			local dz = vtol.z - fighter.z
			local dist = sqrt(dx*dx + dy*dy + dz*dz)
			Bullets.spawn_enemy_bullet(
				fighter.x, fighter.y, fighter.z,
				dx/dist, dy/dist, dz/dist,
				Aliens.FIGHTER_FIRE_RANGE
			)
		end
		end

		-- Mother ship bullet hell (uses its own fire rate for bullet hell pattern)
	if Aliens.mother_ship and Aliens.mother_ship.fire_timer >= 1 / Aliens.MOTHER_SHIP_FIRE_RATE then
		Aliens.mother_ship.fire_timer = 0
		-- Spiral pattern: 8 bullets in a circle
		for i = 0, 7 do
			local angle = (i / 8 + Aliens.mother_ship.fire_angle) * 1
			local dir_x = cos(angle) * 0.7
			local dir_y = -0.3  -- Slight downward
			local dir_z = sin(angle) * 0.7
			Bullets.spawn_enemy_bullet(
				Aliens.mother_ship.x, Aliens.mother_ship.y, Aliens.mother_ship.z,
				dir_x, dir_y, dir_z,
				Aliens.MOTHER_SHIP_FIRE_RANGE
			)
		end
		end

		-- Check bullet collisions with player
	local ship_width, ship_height, ship_depth = get_ship_collision_dimensions(Mission.cargo_objects)
	local player_bounds = {
		left = vtol.x - ship_width/2,
		right = vtol.x + ship_width/2,
		bottom = vtol.y - ship_height/2,
		top = vtol.y + ship_height/2,
		back = vtol.z - ship_depth/2,
		front = vtol.z + ship_depth/2
	}
	local player_hits = Bullets.check_collision("player", player_bounds)
	for hit in all(player_hits) do
		vtol:take_damage(2)  -- 2 damage per bullet (reduced from 10)
		add_explosion(vtol)
	end

	-- Check bullet collisions with aliens
	for alien in all(Aliens.get_all()) do
		-- Simple bounds for aliens (1x1x1 cube for now)
		local alien_bounds = {
			left = alien.x - 0.5,
			right = alien.x + 0.5,
			bottom = alien.y - 0.5,
			top = alien.y + 0.5,
			back = alien.z - 0.5,
			front = alien.z + 0.5
		}
		local alien_hits = Bullets.check_collision("enemy", alien_bounds)
		for hit in all(alien_hits) do
			alien.health -= 20  -- 20 damage per bullet (unchanged)

			-- Add bullet hit explosion effect at bullet position
			add(explosions, {
				x = hit.x,
				y = hit.y,
				z = hit.z,
				time = 0,
				max_time = 0.3,  -- Short burst
				max_radius = 8   -- Small hit effect
			})
		end
		end

			-- Wave progression
		if Aliens.wave_complete then
			if not Aliens.start_next_wave(vtol, LandingPads) then
				-- All waves complete - mission 6 complete!
				-- Only complete if mother ship was actually destroyed AND 5 seconds have passed
				if Aliens.mother_ship_destroyed and Aliens.mother_ship_destroyed_time then
					if time() - Aliens.mother_ship_destroyed_time >= 5 then
						Mission.complete()
					end
				end
			end
		end
	end

	-- Handle cargo delivery - snap ship to landed position without damage
	if Mission.cargo_just_delivered then
		Mission.cargo_just_delivered = false  -- Reset flag

		-- Snap ship to proper landed position (level and on pad)
		vtol.y = landing_height
		vtol.pitch = 0
		vtol.roll = 0

		-- Zero all velocities
		vtol.vx = 0
		vtol.vy = 0
		vtol.vz = 0
		vtol.vpitch = 0
		vtol.vyaw = 0
		vtol.vroll = 0
	end

end

-- Draw all UI elements (health bar, compass, debug info, etc)
local function draw_ui(all_faces, terrain_tiles_rendered, terrain_tiles_culled, effective_render_distance)
	profile("ui:draw")

	-- Performance info (right side, below minimap) - ALWAYS SHOW (not affected by UI toggle)
	if show_debug and debug_toggles.debug_stats then
		local cpu = stat(1) * 100
		local debug_x = 320  -- Right side of screen
		local debug_y = 20   -- Below minimap (minimap is at y=10, size=64, so 10+64+6=80)

		print_shadow("FPS: "..current_fps, debug_x, debug_y, 11)
		print_shadow("CPU: "..flr(cpu).."%", debug_x, debug_y + 8, 11)
		print_shadow("Tris: "..#all_faces, debug_x, debug_y + 16, 11)
		print_shadow("Objects: "..objects_rendered.."/"..objects_rendered+objects_culled, debug_x, debug_y + 24, 11)
		print_shadow("  culled: "..objects_culled, debug_x, debug_y + 32, 10)
		print_shadow("Terrain: "..terrain_tiles_rendered.."/"..terrain_tiles_rendered+terrain_tiles_culled, debug_x, debug_y + 40, 11)
		print_shadow("  culled: "..terrain_tiles_culled, debug_x, debug_y + 48, 10)
		print_shadow("VTOL: x="..flr(vtol.x*10)/10, debug_x, debug_y + 56, 10)
		print_shadow("      y="..flr(vtol.y*10)/10, debug_x, debug_y + 64, 10)
		print_shadow("      z="..flr(vtol.z*10)/10, debug_x, debug_y + 72, 10)

		local vel_total = sqrt(vtol.vx*vtol.vx + vtol.vy*vtol.vy + vtol.vz*vtol.vz)
		print_shadow("VEL: "..flr(vel_total*1000)/1000, debug_x, debug_y + 80, 10)
		print_shadow("  vx="..flr(vtol.vx*1000)/1000, debug_x, debug_y + 88, 6)
		print_shadow("  vy="..flr(vtol.vy*1000)/1000, debug_x, debug_y + 96, 6)
		print_shadow("  vz="..flr(vtol.vz*1000)/1000, debug_x, debug_y + 104, 6)

		-- Debug toggle menu
		local toggle_y = debug_y + 120
		print_shadow("DEBUG TOGGLES:", debug_x, toggle_y, 11)
		toggle_y += 10
		print_shadow("1:Ship    "..(debug_toggles.player_ship and "ON" or "OFF"), debug_x, toggle_y, debug_toggles.player_ship and 11 or 6)
		toggle_y += 8
		print_shadow("2:Skybox  "..(debug_toggles.skybox and "ON" or "OFF"), debug_x, toggle_y, debug_toggles.skybox and 11 or 6)
		toggle_y += 8
		print_shadow("3:Fog     "..(debug_toggles.fog and "ON" or "OFF"), debug_x, toggle_y, debug_toggles.fog and 11 or 6)
		toggle_y += 8
		print_shadow("4:Stats   "..(debug_toggles.debug_stats and "ON" or "OFF"), debug_x, toggle_y, debug_toggles.debug_stats and 11 or 6)
		toggle_y += 8
		print_shadow("5:Bldgs   "..(debug_toggles.buildings and "ON" or "OFF"), debug_x, toggle_y, debug_toggles.buildings and 11 or 6)
		toggle_y += 8
		print_shadow("6:Terrain "..(debug_toggles.terrain and "ON" or "OFF"), debug_x, toggle_y, debug_toggles.terrain and 11 or 6)
		toggle_y += 8
		print_shadow("7:FX      "..(debug_toggles.fx and "ON" or "OFF"), debug_x, toggle_y, debug_toggles.fx and 11 or 6)
		toggle_y += 8
		print_shadow("8:UI      "..(debug_toggles.ui and "ON" or "OFF"), debug_x, toggle_y, debug_toggles.ui and 11 or 6)
		toggle_y += 8
		print_shadow("9:BBox    "..(debug_toggles.bbox and "ON" or "OFF"), debug_x, toggle_y, debug_toggles.bbox and 11 or 6)
	end

	-- Draw profiler display on left side (below controls) - ALWAYS SHOW (not affected by UI toggle)
	if show_debug and debug_toggles.debug_stats then
		profile.draw()
	end

	-- Health bar
	if debug_toggles.ui then
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

	-- Landing pad/building name indicator (show when on landing pad or building rooftop)
	-- Position above compass (compass is at y=240)
	if current_landing_pad then
		local pad_text = "At " .. current_landing_pad.name
		local text_width = #pad_text * 4  -- Approximate text width
		local text_x = 240 - text_width / 2  -- Center horizontally
		local text_y = 218  -- Above compass
		-- Shadow
		print(pad_text, text_x + 1, text_y + 1, 0)
		-- Main text
		print(pad_text, text_x, text_y, 7)
	elseif current_building and current_building.name then
		local building_text = "Rooftop: " .. current_building.name
		local text_width = #building_text * 4  -- Approximate text width
		local text_x = 240 - text_width / 2  -- Center horizontally
		local text_y = 218  -- Above compass
		-- Shadow
		print(building_text, text_x + 1, text_y + 1, 0)
		-- Main text
		print(building_text, text_x, text_y, 7)
	end

	-- Control hints (left side) with outlines - toggle with C or always show in mission 1
	if show_controls or Mission.current_mission_num == 1 then
		local hint_x, hint_y = 2, 132
		-- Outline
		print("CONTROLS:", hint_x + 1, hint_y + 1, 0)
		print("CONTROLS:", hint_x, hint_y, 7)
		hint_y += 10

		-- Show arcade controls only in arcade mode
		if game_mode == "arcade" then
			-- Outline
			print("Space: All thrusters", hint_x + 1, hint_y + 1, 0)
			print("Space: All thrusters", hint_x, hint_y, 6)
			hint_y += 8
			-- Outline
			print("N:     Left+Right", hint_x + 1, hint_y + 1, 0)
			print("N:     Left+Right", hint_x, hint_y, 6)
			hint_y += 8
			-- Outline
			print("M:     Front+Back", hint_x + 1, hint_y + 1, 0)
			print("M:     Front+Back", hint_x, hint_y, 6)
			hint_y += 8
			-- Outline
			print("Shift: Auto-level", hint_x + 1, hint_y + 1, 0)
			print("Shift: Auto-level", hint_x, hint_y, 6)
		else
			-- Simulation mode - show only basic controls
			print("W/A/S/D: Individual thrusters", hint_x + 1, hint_y + 1, 0)
			print("W/A/S/D: Individual thrusters", hint_x, hint_y, 6)
			hint_y += 8
			print("No assists - manual flight!", hint_x + 1, hint_y + 1, 0)
			print("No assists - manual flight!", hint_x, hint_y, 6)
		end

		hint_y += 10
		-- Camera controls (shown in all modes)
		print("CAMERA:", hint_x + 1, hint_y + 1, 0)
		print("CAMERA:", hint_x, hint_y, 7)
		hint_y += 10
		print("Mouse/RMB: Drag to rotate", hint_x + 1, hint_y + 1, 0)
		print("Mouse/RMB: Drag to rotate", hint_x, hint_y, 6)
		hint_y += 8
		print("Arrow Keys: Rotate camera", hint_x + 1, hint_y + 1, 0)
		print("Arrow Keys: Rotate camera", hint_x, hint_y, 6)
	end

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

	-- Draw minimap using Minimap module (pass all landing pads and target pad ID)
	Minimap.draw(camera, vtol, buildings, building_configs, LandingPads.get_all(), Heightmap, position_history, Mission.cargo_objects, Mission.required_landing_pad_id)

	-- Draw enemies on minimap (flashing red dots)
	local flash = (time() * 4) % 1 > 0.5  -- Flash at 4Hz
	local enemy_color = flash and 8 or 24  -- Flash between colors 8 and 24
	for alien in all(Aliens.get_all()) do
		local minimap_x, minimap_y = Minimap.world_to_minimap(alien.x, alien.z, camera)
		if minimap_x and minimap_y then
			if alien.type == "mother" then
				-- Mother ship: larger red disk
				circfill(minimap_x, minimap_y, 3, enemy_color)
			else
				-- Fighter: small red dot
				circfill(minimap_x, minimap_y, 1, enemy_color)
			end
		end
	end

	-- Draw target health bar and ship type (ONLY FOR MISSION 6) - above compass
	if Mission.current_mission_num == 6 and Turret.target then
		local target = Turret.target
		local target_name = ""
		local target_health = 0
		local target_max_health = 1

		-- Determine target type and health
		if target == Aliens.mother_ship then
			target_name = "MOTHER SHIP"
			target_health = target.health
			target_max_health = target.max_health
		else
			-- It's a fighter
			target_name = "FIGHTER"
			target_health = target.health
			target_max_health = target.max_health
		end

		-- Position above compass (compass is at y=240)
		local target_bar_x = 180
		local target_bar_y = 205
		local target_bar_width = 120
		local target_bar_height = 8

		-- Ship type label (red)
		print(target_name, target_bar_x, target_bar_y - 10, 8)

		-- Health bar background (dark)
		rectfill(target_bar_x, target_bar_y, target_bar_x + target_bar_width, target_bar_y + target_bar_height, 1)

		-- Health fill (always red for enemies)
		local health_percent = target_health / target_max_health
		local health_width = target_bar_width * max(0, health_percent)

		rectfill(target_bar_x, target_bar_y, target_bar_x + health_width, target_bar_y + target_bar_height, 8)

		-- Border (red)
		rect(target_bar_x, target_bar_y, target_bar_x + target_bar_width, target_bar_y + target_bar_height, 8)
	end

	-- Draw 3D compass (cross/diamond shape with red and grey arrows)
	-- Side view: <> (diamond), Front view: X (cross)
	-- Two red arrows (north/south axis) and two grey arrows (east/west axis)
	local compass_x = 230-- Left of center by 30 pixels
	local compass_y = 240  -- Bottom middle
	local compass_size = 12

	-- Black box background for compass and altitude (centered)
	local box_width = 100  -- Total width to fit compass + altitude text
	local box_height = 22  -- Height to fit compass
	local box_x1 = compass_x - box_width / 2 + 20
	local box_x2 = compass_x + box_width / 2 + 20
	local box_y1 = compass_y - box_height / 2
	local box_y2 = compass_y + box_height / 2
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

	-- Add mission target arrow to the list (orange)
	if Mission.active and Mission.current_target then
		local dx = Mission.current_target.x - vtol.x
		local dz = Mission.current_target.z - vtol.z

		-- Normalize to compass size (invert direction)
		local mag = sqrt(dx*dx + dz*dz)
		if mag > 0.01 then
			local target_point = {x = (-dx / mag) * compass_size, y = 0, z = (-dz / mag) * compass_size}

			-- Transform by camera rotation (same as north arrow)
			local x_yaw = target_point.x * cos_yaw - target_point.z * sin_yaw
			local z_yaw = target_point.x * sin_yaw + target_point.z * cos_yaw
			local y_pitch = target_point.y * cos_pitch - z_yaw * sin_pitch
			local z_pitch = target_point.y * sin_pitch + z_yaw * cos_pitch

			-- Add target arrow to the list with depth
			add(arrows, {
				screen_x = compass_x + x_yaw,
				screen_y = compass_y + y_pitch,
				color = 9,  -- Orange
				z = z_pitch,
				is_target = true
			})
		end
	end

	-- Sort arrows by depth (back to front, furthest first)
	for i = 1, #arrows do
		for j = i + 1, #arrows do
			if arrows[i].z > arrows[j].z then
				arrows[i], arrows[j] = arrows[j], arrows[i]
			end
		end
	end

	-- Draw arrows in sorted order (back to front)
	for _, arrow in ipairs(arrows) do
		if arrow.is_target then
			-- Draw target arrow (orange)
			line(compass_x, compass_y, arrow.screen_x, arrow.screen_y, arrow.color)
			circfill(arrow.screen_x, arrow.screen_y, 2, arrow.color)  -- Larger arrowhead
		else
			-- Draw compass direction arrows
			local p1 = projected_points[arrow.from]
			local p2 = projected_points[arrow.to]
			line(p1.x, p1.y, p2.x, p2.y, arrow.color)
			circfill(p2.x, p2.y, 1, arrow.color)  -- Smaller arrowhead
		end
	end

	-- Center dot (drawn last, always on top)
	circfill(compass_x, compass_y, 2, 0)  -- Black center
	circ(compass_x, compass_y, 2, 7)  -- White outline

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

	-- Draw speed lines (3D line particles) - disabled when weather is active
	if not Weather.enabled then
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
	end

	-- Draw physics wireframes (if enabled) using Collision module
	if debug_toggles.bbox then
		-- Draw ship collision box (cyan) to test AABB
		local ship_width, ship_height, ship_depth = get_ship_collision_dimensions(Mission.cargo_objects)
		Collision.draw_wireframe(
			camera,
			vtol.x,
			vtol.y,
			vtol.z,
			ship_width,
			ship_height,
			ship_depth,
			11  -- Cyan for ship
		)

		-- Draw landing pad collision box (white) if within render distance
		local dx = landing_pad.x - camera.x
		local dz = landing_pad.z - camera.z
		if dx*dx + dz*dz <= effective_render_distance * effective_render_distance then
			if landing_pad.collision then
				Collision.draw_collision_wireframe(landing_pad.collision, camera, 7)
			end
		end

		-- Draw building collision boxes (red) if within render distance
		for i, building in ipairs(buildings) do
			local dx = building.x - camera.x
			local dz = building.z - camera.z
			if dx*dx + dz*dz <= effective_render_distance * effective_render_distance then
				-- Get building config for accurate dimensions
				local config = building_configs[i]
				if config then
					local full_width = config.width * 2   -- config stores half-width
					local full_height = config.height * 2 -- config stores half-height
					local full_depth = config.depth * 2   -- config stores half-depth

					Collision.draw_wireframe(
						camera,
						building.x,
						building.y + config.height,  -- Center Y at middle of building
						building.z,
						full_width,
						full_height,
						full_depth,
						8  -- Red
					)
				end
			end
		end

		-- Draw terrain tile bounding boxes (green) - only render nearby tiles to avoid overhead
		local terrain_tiles = Heightmap.generate_terrain_tiles(camera.x, camera.z, nil, effective_render_distance)
		for _, tile in ipairs(terrain_tiles) do
			-- Only draw bbox for tiles within a smaller radius to reduce clutter
			local dx = tile.center_x - camera.x
			local dz = tile.center_z - camera.z
			if dx*dx + dz*dz <= 100 then  -- Only draw nearby tiles (10 unit radius)
				-- Calculate AABB center and extents from bounds
				local center_x = (tile.bounds.min_x + tile.bounds.max_x) / 2
				local center_y = (tile.bounds.min_y + tile.bounds.max_y) / 2
				local center_z = (tile.bounds.min_z + tile.bounds.max_z) / 2
				local full_width = tile.bounds.max_x - tile.bounds.min_x
				local full_height = tile.bounds.max_y - tile.bounds.min_y
				local full_depth = tile.bounds.max_z - tile.bounds.min_z

				Collision.draw_wireframe(
					camera,
					center_x,
					center_y,
					center_z,
					full_width,
					full_height,
					full_depth,
					11  -- Green
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

	-- Debug: Show cargo state if cargo exists
	if show_cargo_debug and Mission.cargo_objects and #Mission.cargo_objects > 0 then
		local debug_x = 10
		local debug_y = 100
		local y_offset = 0

		print("=== CARGO DEBUG ===", debug_x, debug_y + y_offset, 11)
		y_offset += 8

		for i, cargo in ipairs(Mission.cargo_objects) do
			print("Cargo " .. i .. ": " .. (cargo.state or "nil"), debug_x, debug_y + y_offset, 7)
			y_offset += 8

			-- Show distance from ship
			if cargo.x and vtol.x then
				local dx = cargo.x - vtol.x
				local dz = cargo.z - vtol.z
				local dist = sqrt(dx*dx + dz*dz) * 10  -- Convert to meters
				print("  Dist: " .. flr(dist) .. "m", debug_x, debug_y + y_offset, 6)
				y_offset += 8
			end

			-- Show delivery timer
			if cargo.delivery_timer then
				print("  Timer: " .. flr(cargo.delivery_timer * 10) / 10 .. "s", debug_x, debug_y + y_offset, 6)
				y_offset += 8
			end
		end

		-- Show engines off and on pad status
		local engines_off = not vtol.thrusters[1].active and
		                    not vtol.thrusters[2].active and
		                    not vtol.thrusters[3].active and
		                    not vtol.thrusters[4].active
		print("Engines off: " .. (engines_off and "YES" or "NO"), debug_x, debug_y + y_offset, 6)
		y_offset += 8
		print("On pad: " .. (is_on_landing_pad and "YES" or "NO"), debug_x, debug_y + y_offset, 6)
		y_offset += 8

		-- Show distance to target landing pad (using required_landing_pad_id)
		if Mission.required_landing_pad_id then
			local target_pad = LandingPads.get_pad(Mission.required_landing_pad_id)
			if target_pad then
				print("Target Pad: ID " .. Mission.required_landing_pad_id, debug_x, debug_y + y_offset, 6)
				y_offset += 8
				print("  Pos: (" .. flr(target_pad.x) .. ", " .. flr(target_pad.z) .. ")", debug_x, debug_y + y_offset, 6)
				y_offset += 8

				local dx = vtol.x - target_pad.x
				local dz = vtol.z - target_pad.z
				local dist = sqrt(dx*dx + dz*dz)
				print("Pad dist: " .. flr(dist * 100) / 100, debug_x, debug_y + y_offset, 6)
				y_offset += 8
			end
		end

		-- Show compass target
		if Mission.current_target then
			print("Compass: (" .. flr(Mission.current_target.x) .. ", " .. flr(Mission.current_target.z) .. ")", debug_x, debug_y + y_offset, 11)
			y_offset += 8

			-- Show distance to compass target in red
			local dx = vtol.x - Mission.current_target.x
			local dz = vtol.z - Mission.current_target.z
			local dist = sqrt(dx*dx + dz*dz)
			print("Target dist: " .. flr(dist * 100) / 100, debug_x, debug_y + y_offset, 8)
			y_offset += 8
		end
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

	end -- End of UI toggle

	Mission.draw_pause_menu()

	-- Draw rain as lines (if weather enabled)
	if Weather.enabled and debug_toggles.fx then
		Weather.draw_rain_lines(camera, vtol)
	end

	profile("ui:draw")
end

function _draw()
	-- Handle cutscene rendering
	if Cutscene.active then
		Cutscene.draw()
		return
	end

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

	-- Apply weather overrides for fog and render distance
	local effective_render_distance = RENDER_DISTANCE
	local effective_fog_start = FOG_START_DISTANCE
	if Weather.enabled then
		effective_render_distance = WEATHER_RENDER_DISTANCE
		effective_fog_start = WEATHER_FOG_START_DISTANCE
	end

	-- Frustum culling uses simple clip space test (no plane extraction needed)

	-- Collect all faces from all meshes
	local all_faces = {}

	-- Render skybox (always at camera position, draws behind everything)
	profile("render:skybox")
	if debug_toggles.skybox then
		local skybox_sorted
		if Mission.current_mission_num == 6 then
			-- Mission 6: use special dome skybox with sprite 29 (64x32)
			-- is_ground=true, is_skybox=true for special pitch-independent culling
			skybox_sorted = render_mesh(m6_skybox_verts, m6_skybox_faces, camera.x, camera.y, camera.z, nil, true, nil, nil, nil, nil, nil, true)
		else
			-- Other missions: use regular skybox
			local skybox_sprite = nil
			if Weather.enabled then
				-- Mission 5: use cloudy sky (sprite 23)
				skybox_sprite = 23
			end
			skybox_sorted = render_mesh(skybox_verts, skybox_faces, camera.x, camera.y, camera.z, skybox_sprite, true, nil, nil, nil, nil, nil, true)
		end

		for _, f in ipairs(skybox_sorted) do
			f.depth = 999999  -- Push skybox to back (always draws behind)
			f.is_skybox = true  -- Mark as skybox to exclude from fog
			add(all_faces, f)
		end
	end
	profile("render:skybox")

	-- Generate terrain tiles with bounding boxes for culling (only twice per second)
	local terrain_tiles_rendered = 0
	local terrain_tiles_culled = 0
	if debug_toggles.terrain then
		-- Only regenerate terrain twice per second
		local current_time = time()
		if current_time - last_terrain_gen_time >= TERRAIN_GEN_RATE then
			profile("terrain:gen")
			cached_terrain_tiles = Heightmap.generate_terrain_tiles(camera.x, camera.z, nil, effective_render_distance)
			last_terrain_gen_time = current_time
			profile("terrain:gen")
		end
		local terrain_tiles = cached_terrain_tiles

		profile("render:terrain")
		-- Animate water: swap between SPRITE_WATER and SPRITE_WATER2 every 0.5 seconds
		local water_frame = flr(time() * 2) % 2  -- 0 or 1, changes every 0.5 seconds
		local water_sprite = water_frame == 0 and SPRITE_WATER or SPRITE_WATER2

		profile("render:frustum_cull")
		for _, tile in ipairs(terrain_tiles) do
			-- Calculate distance to tile for nearby check
			local dx = tile.center_x - camera.x
			local dz = tile.center_z - camera.z
			local dist_sq = dx*dx + dz*dz
			local is_nearby = dist_sq < 100  -- Within 10 units, skip frustum culling

			-- Frustum cull using simple AABB clip space test (skip for nearby tiles)
			local in_frustum = is_nearby or Frustum.test_aabb_simple(
				camera, 70, 480/270, 0.01, effective_render_distance,
				tile.bounds.min_x, tile.bounds.min_y, tile.bounds.min_z,
				tile.bounds.max_x, tile.bounds.max_y, tile.bounds.max_z
			)

			-- Distance cull terrain tiles based on center point and height
			local distance_culled = Renderer.tile_distance_cull(tile.center_x, tile.center_z, tile.height, camera, effective_render_distance)

			if in_frustum and not distance_culled then
				-- Update water sprite on water faces
				for _, face in ipairs(tile.faces) do
					if face[4] == SPRITE_WATER or face[4] == SPRITE_WATER2 then
						face[4] = water_sprite
					end
				end

				-- Render tile (each tile has its own verts/faces)
				local tile_sorted = render_mesh(tile.verts, tile.faces, 0, 0, 0, nil, true, nil, nil, nil, effective_render_distance, effective_fog_start)
				for _, f in ipairs(tile_sorted) do
					add(all_faces, f)
				end
				terrain_tiles_rendered += 1
			else
				terrain_tiles_culled += 1
			end
		end
		profile("render:frustum_cull")
		profile("render:terrain")
	end

	-- Render all buildings
	profile("render:buildings")
	if debug_toggles.buildings then
		profile("render:frustum_cull")
		for i, building in ipairs(buildings) do
			-- Get building dimensions from config
			local config = building_configs[i]
			if config then
				-- Calculate distance for nearby check
				local dx = building.x - camera.x
				local dz = building.z - camera.z
				local dist_sq = dx*dx + dz*dz
				local is_nearby = dist_sq < 100  -- Within 10 units, skip frustum culling

				-- Calculate AABB bounds for building
				local min_x = building.x - config.width
				local max_x = building.x + config.width
				local min_y = building.y
				local max_y = building.y + config.height * 2
				local min_z = building.z - config.depth
				local max_z = building.z + config.depth

				-- Frustum cull using simple AABB clip space test (skip for nearby buildings)
				local in_frustum = is_nearby or Frustum.test_aabb_simple(
					camera, 70, 480/270, 0.01, effective_render_distance,
					min_x, min_y, min_z, max_x, max_y, max_z
				)

				if in_frustum then
					local building_faces = render_mesh(
						building.verts,
						building.faces,
						building.x,
						building.y,
						building.z,
						building.sprite_override,
						false,
						nil, nil, nil,
						effective_render_distance,
						effective_fog_start
					)
					for _, f in ipairs(building_faces) do
						add(all_faces, f)
					end
				end
			end
		end
		profile("render:frustum_cull")
	end
	profile("render:buildings")

	-- Render all landing pads
	profile("render:pads")
	for _, pad in ipairs(LandingPads.get_all()) do
		local pad_faces = render_mesh(
			pad.verts,
			pad.faces,
			pad.x,
			pad.y,
			pad.z,
			pad.sprite_override,
			false,
			nil, nil, nil,
			effective_render_distance,
			effective_fog_start
		)
		for _, f in ipairs(pad_faces) do
			add(all_faces, f)
		end
	end
	profile("render:pads")

	-- Render all trees
	for _, tree in ipairs(trees) do
		local tree_faces = render_mesh(
			tree.verts,
			tree.faces,
			tree.x,
			tree.y,
			tree.z,
			tree.sprite_override,
			false,
			nil, nil, nil,
			effective_render_distance,
			effective_fog_start
		)
		for _, f in ipairs(tree_faces) do
			add(all_faces, f)
		end
	end

	-- Render all cargo objects (with animation and scaling)
	profile("render:cargo")
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
				cargo.pitch, cargo.yaw, cargo.roll,  -- Use cargo rotation (matches ship when attached)
				effective_render_distance,
				effective_fog_start
			)
			for _, f in ipairs(cargo_faces) do
				add(all_faces, f)
			end
		end
	end
	profile("render:cargo")

	-- Get sphere faces (floating above the city)
	-- local sphere_sorted = render_mesh(sphere_verts, sphere_faces, 0, 5, 0)
	-- for _, f in ipairs(sphere_sorted) do
	-- 	add(all_faces, f)
	-- end

	-- Render smoke particles using particle system (camera-facing billboards)
	profile("render:particles")
	if debug_toggles.fx then
		local smoke_faces = smoke_system:render(render_mesh, camera)
		for _, f in ipairs(smoke_faces) do
			f.is_vtol = true  -- Mark smoke as VTOL-related
			add(all_faces, f)
		end
	end
	profile("render:particles")

	-- Render bullets (ONLY FOR MISSION 6)
	if Mission.current_mission_num == 6 then
		local bullet_faces = Bullets.render(render_mesh, camera)
		for _, f in ipairs(bullet_faces) do
			add(all_faces, f)
		end

		-- Render aliens
		profile("render:aliens")
		for alien in all(Aliens.get_all()) do
			local alien_mesh = alien.type == "fighter" and ufo_fighter_mesh or ufo_mother_mesh
			if alien_mesh and alien_mesh.verts then
				-- Extended render distance for aliens (fighters: 50 units = 500m, mother ship: 100 units = 1000m)
				local alien_render_distance = alien.type == "mother" and 100 or 50
				local alien_faces = render_mesh(
					alien_mesh.verts,
					alien_mesh.faces,
					alien.x,
					alien.y,
					alien.z,
					nil,
					false,
					0, alien.yaw, alien.roll or 0,  -- Add roll for banking
					alien_render_distance,
					effective_fog_start
				)
				for _, f in ipairs(alien_faces) do
					add(all_faces, f)
				end
			end
		end
		profile("render:aliens")
	end

	-- Render turret (attached to ship, using proper mount position and quaternion rotation) (ONLY FOR MISSION 6)
	local turret_x, turret_y, turret_z
	if Mission.current_mission_num == 6 then
		turret_x, turret_y, turret_z = Turret.get_position(vtol.x, vtol.y, vtol.z, vtol.pitch, vtol.yaw, vtol.roll)
		local turret_pitch, turret_yaw, turret_roll = Turret.get_euler_angles()
		local turret_faces = render_mesh(
			Turret.verts,
			Turret.faces,
			turret_x,
			turret_y,
			turret_z,
			nil,
			false,
			turret_pitch, turret_yaw, turret_roll,
			effective_render_distance,
			effective_fog_start
		)
		for _, f in ipairs(turret_faces) do
			f.is_vtol = true  -- Mark turret as VTOL-related
			add(all_faces, f)
		end
	end

	-- DEBUG: Turret wireframe (disabled)
	-- Uncomment to enable turret debug visualization

	-- Calculate if ship should flash (critically damaged)
	profile("render:ship")
	if debug_toggles.player_ship then
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
			vtol.roll,
			effective_render_distance,
			effective_fog_start,
			false,  -- is_skybox
			true    -- no_cull - ship should never be culled
		)
		for _, f in ipairs(vtol_sorted) do
			f.is_vtol = true  -- Mark VTOL faces
			add(all_faces, f)
		end
	end
	profile("render:ship")

	-- Draw ship collision box wireframe (if enabled)
	if debug_toggles.bbox then
		local ship_width, ship_height, ship_depth = get_ship_collision_dimensions(Mission.cargo_objects)

		Collision.draw_wireframe(
			camera,
			vtol.x,
			vtol.y,
			vtol.z,
			ship_width,
			ship_height,
			ship_depth,
			11  -- Cyan for ship collision box
		)
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
	profile("render:sort")
	Renderer.sort_faces(all_faces)
	profile("render:sort")

	-- Draw all faces using Renderer module
	profile("render:draw")
	Renderer.draw_faces(all_faces, false)
	profile("render:draw")

	-- Draw laser beam from turret (100m = 10 units) - simple red line - ALWAYS IN FRONT (ONLY FOR MISSION 6)
	if Mission.current_mission_num == 6 and Turret.target then
		-- Check if target is within firing range
		local dx = Turret.target.x - turret_x
		local dy = Turret.target.y - turret_y
		local dz = Turret.target.z - turret_z
		local dist = sqrt(dx*dx + dy*dy + dz*dz)

		if dist <= Turret.FIRE_RANGE then
			local dir_x, dir_y, dir_z = Turret.get_fire_direction(vtol)
			if dir_x then
				local laser_length = 10  -- 100 meters

				-- Calculate laser end point in world space
				local laser_end_x = turret_x + dir_x * laser_length
				local laser_end_y = turret_y + dir_y * laser_length
				local laser_end_z = turret_z + dir_z * laser_length

				-- Project both points to screen space
				local start_sx, start_sy, start_depth = Turret.project_3d_to_2d(turret_x, turret_y, turret_z, camera)
				local end_sx, end_sy, end_depth = Turret.project_3d_to_2d(laser_end_x, laser_end_y, laser_end_z, camera)

				-- Draw line if both points are visible
				if start_sx and end_sx and start_depth > 0 and end_depth > 0 then
					line(start_sx, start_sy, end_sx, end_sy, 8)  -- Red laser (color 8)
				end
			end
		end
	end

	-- Draw line particles (mother ship debris) - ALWAYS IN FRONT (ONLY FOR MISSION 6)
	if Mission.current_mission_num == 6 and debug_toggles.fx then
		for p in all(line_particles) do
			-- Line particles are small debris lines flying outward
			-- Draw as short lines from current position in direction of velocity
			local line_length = 0.5  -- Length of debris line
			local end_x = p.x + (p.vx / sqrt(p.vx*p.vx + p.vy*p.vy + p.vz*p.vz)) * line_length
			local end_y = p.y + (p.vy / sqrt(p.vx*p.vx + p.vy*p.vy + p.vz*p.vz)) * line_length
			local end_z = p.z + (p.vz / sqrt(p.vx*p.vx + p.vy*p.vy + p.vz*p.vz)) * line_length

			-- Project both points to screen space
			local start_sx, start_sy, start_depth = Turret.project_3d_to_2d(p.x, p.y, p.z, camera)
			local end_sx, end_sy, end_depth = Turret.project_3d_to_2d(end_x, end_y, end_z, camera)

			-- Draw line if both points are visible
			if start_sx and end_sx and start_depth > 0 and end_depth > 0 then
				line(start_sx, start_sy, end_sx, end_sy, p.color or 12)  -- Blue debris
			end
		end
	end

	-- Draw all UI elements (health, compass, minimap, mission UI, etc.)
	draw_ui(all_faces, terrain_tiles_rendered, terrain_tiles_culled, effective_render_distance)
end
