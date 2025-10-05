-- Load modules
local load_obj = include("obj_loader.lua")
local ParticleSystem = include("particle_system.lua")
local MathUtils = include("math_utils.lua")
local Renderer = include("renderer.lua")
local Collision = include("collision.lua")
local Heightmap = include("heightmap.lua")
local Minimap = include("minimap.lua")

-- Sprite Constants (for easy reference)
local SPRITE_CUBE = 0
local SPRITE_SPHERE = 1
local SPRITE_GROUND = 2  -- Terrain texture
local SPRITE_FLAME = 3
local SPRITE_SMOKE = 5
local SPRITE_TREES = 6
local SPRITE_LANDING_PAD = 8
local SPRITE_SHIP = 9
local SPRITE_SHIP_DAMAGE = 10
local SPRITE_SKYBOX = 11
local SPRITE_WATER = 12
local SPRITE_WATER2 = 13
local SPRITE_HEIGHTMAP = 64  -- Heightmap data source (128x128)

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
local DAMAGE_GROUND_MULTIPLIER = 100   -- Damage multiplier for ground impacts

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
	DEAD = 2
}
local current_game_state = GAME_STATE.PLAYING
local death_timer = 0

-- textri function is now in renderer.lua module

-- Cube vertices (8 corners)
local cube_verts = {
	vec(-1, -1, -1),  -- 1
	vec( 1, -1, -1),  -- 2
	vec( 1,  1, -1),  -- 3
	vec(-1,  1, -1),  -- 4
	vec(-1, -1,  1),  -- 5
	vec( 1, -1,  1),  -- 6
	vec( 1,  1,  1),  -- 7
	vec(-1,  1,  1),  -- 8
}

-- Cube faces (as triangles, 2 triangles per face)
-- Each face: {v1, v2, v3, sprite_id, uv1, uv2, uv3}
local cube_faces = {
	-- Front face (sprite 0) - first triangle
	{1, 2, 3, 0, vec(0,0), vec(16,0), vec(16,16)},
	-- Front face - second triangle
	{1, 3, 4, 0, vec(0,0), vec(16,16), vec(0,16)},
	-- Back face (sprite 1)
	{6, 5, 8, 1, vec(0,0), vec(16,0), vec(16,16)},
	{6, 8, 7, 1, vec(0,0), vec(16,16), vec(0,16)},
	-- Left face (sprite 0)
	{5, 1, 4, 0, vec(0,0), vec(16,0), vec(16,16)},
	{5, 4, 8, 0, vec(0,0), vec(16,16), vec(0,16)},
	-- Right face (sprite 1)
	{2, 6, 7, 1, vec(0,0), vec(16,0), vec(16,16)},
	{2, 7, 3, 1, vec(0,0), vec(16,16), vec(0,16)},
	-- Top face (sprite 0)
	{4, 3, 7, 0, vec(0,0), vec(16,0), vec(16,16)},
	{4, 7, 8, 0, vec(0,0), vec(16,16), vec(0,16)},
	-- Bottom face (sprite 1)
	{5, 6, 2, 1, vec(0,0), vec(16,0), vec(16,16)},
	{5, 2, 1, 1, vec(0,0), vec(16,16), vec(0,16)},
}

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
local buildings = {}
local building_configs = {
	{x = -10, z = 5, width = 1.5, depth = 1.5, height = 8, sprite = 0},    -- Tall tower
	{x = -5, z = 4, width = 1.2, depth = 1.2, height = 6, sprite = 1},     -- Medium tower
	{x = 0, z = 5, width = 1.0, depth = 1.0, height = 5, sprite = 0},      -- Shorter building
	{x = 6, z = 4, width = 1.3, depth = 1.3, height = 7, sprite = 1},      -- Tall tower
	{x = -8, z = 12, width = 1.8, depth = 1.0, height = 4, sprite = 0},    -- Wide building
	{x = -2, z = 12, width = 1.0, depth = 1.8, height = 5, sprite = 1},    -- Long building
	{x = 3, z = 14, width = 1.2, depth = 1.2, height = 9, sprite = 0},     -- Tallest skyscraper
	{x = 9, z = 12, width = 1.0, depth = 1.0, height = 3, sprite = 1},     -- Small building
	{x = -6, z = 18, width = 1.5, depth = 1.2, height = 6, sprite = 0},    -- Medium building
	{x = 2, z = 20, width = 1.1, depth = 1.4, height = 7, sprite = 1},     -- Tall building
}

for i, config in ipairs(building_configs) do
	local x = config.x
	local z = config.z
	local width = config.width
	local depth = config.depth
	local height = config.height
	local sprite = config.sprite

	-- Create scaled vertices for this building
	-- Shift vertices up so bottom is at y=0
	local building_verts = {}
	for _, v in ipairs(cube_verts) do
		add(building_verts, vec(
			v.x * width,
			(v.y + 1) * height,  -- +1 to shift from [-1,1] to [0,2], then scale
			v.z * depth
		))
	end

	-- Get height from heightmap if available
	local building_height = 0
	if USE_HEIGHTMAP then
		building_height = Heightmap.get_height(x, z)
	end

	add(buildings, {
		verts = building_verts,
		faces = cube_faces,
		x = x,
		y = building_height,  -- Terrain elevation
		z = z,
		sprite_override = sprite,  -- Use sprite from config (0 or 1)
		-- Store collision dimensions for wireframe rendering
		width = width * 2,  -- Full width (not half-width)
		height = height * 2,  -- Full height
		depth = depth * 2   -- Full depth
	})
end


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

-- Landing pad bounds: w="..pad_width.." h="..pad_height.." d="..pad_depth

-- Landing pad object at spawn position (moved to the right)
-- Scale down by 50% for both visual and collision
local pad_scale = 0.5
local pad_scaled_verts = {}
for _, v in ipairs(landing_pad_mesh.verts) do
	add(pad_scaled_verts, vec(v.x * pad_scale, v.y * pad_scale, v.z * pad_scale))
end

local landing_pad = {
	verts = pad_scaled_verts,
	faces = landing_pad_mesh.faces,
	x = 5,  -- Moved 5 units to the right
	y = 0.5,
	z = -3,
	sprite_override = SPRITE_LANDING_PAD,  -- Landing pad texture
	-- Collision box: width/depth from mesh (scaled 50%), height fixed at 1.5m
	width = pad_width * pad_scale,
	height = 1.5,  -- Fixed at 1.5m for collision
	depth = pad_depth * pad_scale
}

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

local function add_explosion(vtol_obj)
	-- Pick a random engine position for the explosion
	local random_thruster = vtol_obj.thrusters[flr(rnd(#vtol_obj.thrusters)) + 1]

	-- Calculate world position of the engine using ship rotation
	local cos_yaw = cos(vtol_obj.yaw)
	local sin_yaw = sin(vtol_obj.yaw)
	local cos_pitch = cos(vtol_obj.pitch)
	local sin_pitch = sin(vtol_obj.pitch)

	-- Rotate engine position by ship's yaw (simplified - just yaw rotation for now)
	local world_x = vtol_obj.x --+ (random_thruster.x * cos_yaw - random_thruster.z * sin_yaw)
	local world_y = vtol_obj.y --+ (random_thruster.y or -0.3)  -- Use thruster y or default
	local world_z = vtol_obj.z --+ (random_thruster.x * sin_yaw + random_thruster.z * cos_yaw)

	add(explosions, {
		x = world_x,
		y = world_y,
		z = world_z,
		time = 0,
		max_time = 0.6,  -- Duration in seconds
		max_radius = 8   -- Larger radius for visibility
	})
end

-- VTOL Vehicle Physics
local vtol = {
	-- Position & rotation (centered on landing pad, sitting on top)
	x = 5, y = 2, z = -3,  -- Aligned with landing pad center (x=5, z=-3), on pad (y=2)
	pitch = 0, yaw = 0, roll = 0,

	-- Velocity & angular velocity
	vx = 0, vy = 0, vz = 0,
	vpitch = 0, vyaw = 0, vroll = 0,

	-- Thruster positions will be set from engine_positions after loading
	thrusters = {},

	-- Health and damage
	health = 100,
	max_health = 100,
	is_damaged = false,  -- Track if ship is smoking

	-- Physics constants (use globals for easy tweaking)
	mass = VTOL_MASS,
	thrust = VTOL_THRUST,
	gravity = VTOL_GRAVITY,
	damping = VTOL_DAMPING,
	angular_damping = VTOL_ANGULAR_DAMPING,
}

-- Position history for minimap trail (store last 5 seconds)
local position_history = {}
local HISTORY_DURATION = 5  -- seconds
local HISTORY_SAMPLE_RATE = 0.1  -- sample every 0.1 seconds
local last_history_sample = 0

-- Load cross_lander mesh from OBJ
local cross_lander_mesh = load_obj("cross_lander.obj")
local flame_mesh = load_obj("flame.obj")

-- Fallback to red cubes if OBJ loading fails
if not cross_lander_mesh or #cross_lander_mesh.verts == 0 then
	-- ERROR: Could not load cross_lander mesh, using fallback red cube
	cross_lander_mesh = {
		verts = {
			vec(-1.5, 0, -1.5), vec(1.5, 0, -1.5), vec(1.5, 0, 1.5), vec(-1.5, 0, 1.5),
			vec(-1.5, 3, -1.5), vec(1.5, 3, -1.5), vec(1.5, 3, 1.5), vec(-1.5, 3, 1.5)
		},
		faces = {
			{1, 2, 3, 8, vec(0,0), vec(16,0), vec(16,16)}, {1, 3, 4, 8, vec(0,0), vec(16,16), vec(0,16)},
			{5, 7, 6, 8, vec(0,0), vec(16,0), vec(16,16)}, {5, 8, 7, 8, vec(0,0), vec(16,16), vec(0,16)},
			{1, 5, 6, 8, vec(0,0), vec(16,0), vec(16,16)}, {1, 6, 2, 8, vec(0,0), vec(16,16), vec(0,16)},
			{3, 7, 8, 8, vec(0,0), vec(16,0), vec(16,16)}, {3, 8, 4, 8, vec(0,0), vec(16,16), vec(0,16)},
			{4, 8, 5, 8, vec(0,0), vec(16,0), vec(16,16)}, {4, 5, 1, 8, vec(0,0), vec(16,16), vec(0,16)},
			{2, 6, 7, 8, vec(0,0), vec(16,0), vec(16,16)}, {2, 7, 3, 8, vec(0,0), vec(16,16), vec(0,16)}
		}
	}
end
if not flame_mesh or #flame_mesh.verts == 0 then
	-- ERROR: Could not load flame mesh, using fallback red cube
	flame_mesh = {
		verts = {
			vec(-0.5, 0, -0.5), vec(0.5, 0, -0.5), vec(0.5, 0, 0.5), vec(-0.5, 0, 0.5),
			vec(-0.5, 1, -0.5), vec(0.5, 1, -0.5), vec(0.5, 1, 0.5), vec(-0.5, 1, 0.5)
		},
		faces = {
			{1, 2, 3, SPRITE_FLAME, vec(0,0), vec(16,0), vec(16,16)}, {1, 3, 4, SPRITE_FLAME, vec(0,0), vec(16,16), vec(0,16)},
			{5, 7, 6, SPRITE_FLAME, vec(0,0), vec(16,0), vec(16,16)}, {5, 8, 7, SPRITE_FLAME, vec(0,0), vec(16,16), vec(0,16)},
			{1, 5, 6, SPRITE_FLAME, vec(0,0), vec(16,0), vec(16,16)}, {1, 6, 2, SPRITE_FLAME, vec(0,0), vec(16,16), vec(0,16)},
			{3, 7, 8, SPRITE_FLAME, vec(0,0), vec(16,0), vec(16,16)}, {3, 8, 4, SPRITE_FLAME, vec(0,0), vec(16,16), vec(0,16)},
			{4, 8, 5, SPRITE_FLAME, vec(0,0), vec(16,0), vec(16,16)}, {4, 5, 1, SPRITE_FLAME, vec(0,0), vec(16,16), vec(0,16)},
			{2, 6, 7, SPRITE_FLAME, vec(0,0), vec(16,0), vec(16,16)}, {2, 7, 3, SPRITE_FLAME, vec(0,0), vec(16,16), vec(0,16)}
		}
	}
end

-- Scale down to fit the engine - make it much smaller
-- Original engine positions in model: (6,-2,0) (-6,-2,0) (0,-2,6) (0,-2,-6)
local model_scale = 0.15  -- Scale everything down to 15% of original size

local vtol_verts = {}
for _, v in ipairs(cross_lander_mesh.verts) do
	add(vtol_verts, vec(
		v.x * model_scale,
		v.y * model_scale,
		v.z * model_scale
	))
end

-- Assign ship texture (sprite 9) to all lander faces
-- Sprite 9 is 64x64 pixels, so scale UVs accordingly
local vtol_faces = {}
for _, face in ipairs(cross_lander_mesh.faces) do
	-- Replace sprite_id (4th element) with sprite 9
	-- Scale UVs from 16x16 to 64x64 (multiply by 4)
	local uv1 = {x = face[5].x * 4, y = face[5].y * 4}
	local uv2 = {x = face[6].x * 4, y = face[6].y * 4}
	local uv3 = {x = face[7].x * 4, y = face[7].y * 4}
	add(vtol_faces, {face[1], face[2], face[3], 9, uv1, uv2, uv3})
end

-- Engine positions (scaled from original model)
-- Original: (6,-2,0) (-6,-2,0) (0,-2,6) (0,-2,-6)
local engine_positions = {
	{x = 6 * model_scale, y = -2 * model_scale, z = 0, key = "d"},  -- Right (D)
	{x = -6 * model_scale, y = -2 * model_scale, z = 0, key = "a"},  -- Left (A)
	{x = 0, y = -2 * model_scale, z = 6 * model_scale, key = "w"},  -- Front (W)
	{x = 0, y = -2 * model_scale, z = -6 * model_scale, key = "s"},  -- Back (S)
}

-- Add flame models at each engine position (single layer with animation)
local flame_face_indices = {}
local flame_base_verts = {}  -- Store base vertex positions for animation
for i, engine in ipairs(engine_positions) do
	local flame_verts_start = #vtol_verts

	for _, v in ipairs(flame_mesh.verts) do
		add(vtol_verts, vec(
			v.x * model_scale + engine.x,
			v.y * model_scale + engine.y,
			v.z * model_scale + engine.z
		))
		-- Store base position for animation
		add(flame_base_verts, {
			base_x = v.x * model_scale + engine.x,
			base_y = v.y * model_scale + engine.y,
			base_z = v.z * model_scale + engine.z,
			offset_x = (v.x - 2.3394) * model_scale,  -- Offset from flame center
			offset_y = (v.y - 0.3126) * model_scale,
			offset_z = (v.z + 2.7187) * model_scale,
			engine_idx = i
		})
	end

	local faces_start = #vtol_faces + 1
	for _, face in ipairs(flame_mesh.faces) do
		add(vtol_faces, {
			face[1] + flame_verts_start,
			face[2] + flame_verts_start,
			face[3] + flame_verts_start,
			SPRITE_FLAME,  -- Use flame sprite
			face[5], face[6], face[7]
		})
	end
	local faces_end = #vtol_faces

	-- Track flame faces
	add(flame_face_indices, {start_idx = faces_start, end_idx = faces_end, thruster_idx = i})

	-- Add thruster to VTOL (for physics)
	add(vtol.thrusters, {x = engine.x, z = engine.z, key = engine.key, active = false})
end

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

-- Function to reset game to initial state
local function reset_game()
	-- Reset VTOL state (centered on landing pad, sitting on top)
	vtol.x = 5
	vtol.y = 2
	vtol.z = -3
	vtol.pitch = 0
	vtol.yaw = 0
	vtol.roll = 0
	vtol.vx = 0
	vtol.vy = 0
	vtol.vz = 0
	vtol.vpitch = 0
	vtol.vyaw = 0
	vtol.vroll = 0
	vtol.health = vtol.max_health
	vtol.is_damaged = false

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
end

-- Generate minimap terrain cache (called once at startup)
-- Pre-renders the entire heightmap into a small texture for fast drawing
local function generate_minimap_terrain_cache()
	if not USE_HEIGHTMAP then
		return nil
	end

	-- Generating minimap terrain cache...

	-- Create a userdata image for the full heightmap (128x128)
	-- This covers the entire map, not just the minimap view
	local cache_size = Heightmap.MAP_SIZE
	local cache = userdata("u8", cache_size, cache_size)

	-- Terrain elevation colors: 21 (low), 5, 22, 6 (high)
	local terrain_colors = {21, 5, 22, 6}

	-- Pre-calculate world space origin (map center)
	local half_world = (Heightmap.MAP_SIZE * Heightmap.TILE_SIZE) / 2

	-- Generate the full terrain color map
	for z = 0, cache_size - 1 do
		for x = 0, cache_size - 1 do
			-- Convert cache coordinates to world coordinates
			local world_x = x * Heightmap.TILE_SIZE - half_world
			local world_z = z * Heightmap.TILE_SIZE - half_world

			-- Get height at this position
			local height = Heightmap.get_height(world_x, world_z)

			-- Map height to color (0-16m mapped to 4 colors)
			-- Height range: 0 to 32 color indices * 0.5 = 0 to 16m max
			local max_height = 32 * Heightmap.HEIGHT_SCALE  -- 16m max
			local height_normalized = mid(0, height / max_height, 1)  -- 0 to 1
			local color_index = height_normalized * (#terrain_colors - 1)  -- 0 to 3
			local color_base = flr(color_index) + 1  -- 1 to 4
			local color_frac = color_index - flr(color_index)

			-- Clamp to valid range
			color_base = mid(1, color_base, #terrain_colors)

			-- Dither for smooth gradients
			local final_color = terrain_colors[color_base]
			if color_base < #terrain_colors and color_frac > 0 then
				local dither_pattern = (x + z) % 2
				if color_frac > 0.5 and dither_pattern == 1 then
					final_color = terrain_colors[color_base + 1]
				elseif color_frac > 0.75 then
					final_color = terrain_colors[color_base + 1]
				end
			end

			-- Store in cache
			cache[z * cache_size + x] = final_color
		end
	end

	-- Minimap terrain cache generated
	return cache
end

-- Alternative: Generate color-coded minimap using heightmap module
local function generate_minimap_terrain_cache_v2()
	if not USE_HEIGHTMAP then
		return nil
	end
	-- Use heightmap's built-in color-coded visualization with 3x3 averaging
	return Heightmap.generate_minimap()
end

-- draw_collision_wireframe is now in Collision module

-- Wrapper for render_mesh to track culling stats and use Renderer module
local function render_mesh(verts, faces, offset_x, offset_y, offset_z, sprite_override, is_ground, rot_pitch, rot_yaw, rot_roll)
	-- Early culling check
	local obj_x = offset_x or 0
	local obj_z = offset_z or 0
	local dx = obj_x - camera.x
	local dz = obj_z - camera.z
	local dist_sq = dx*dx + dz*dz

	if not is_ground and dist_sq > RENDER_DISTANCE * RENDER_DISTANCE then
		objects_culled += 1
		return {}
	end

	objects_rendered += 1

	return Renderer.render_mesh(
		verts, faces, camera,
		offset_x, offset_y, offset_z,
		sprite_override, is_ground,
		rot_pitch, rot_yaw, rot_roll,
		RENDER_DISTANCE,
		GROUND_ALWAYS_BEHIND,
		FOG_START_DISTANCE
	)
end

function _update()
	-- Calculate delta time (time since last frame)
	local current_time = time()
	delta_time = current_time - last_time
	last_time = current_time

	-- Generate minimap cache on first frame
	if not minimap_terrain_cache and USE_HEIGHTMAP then
		minimap_terrain_cache = generate_minimap_terrain_cache_v2()
		Minimap.set_terrain_cache(minimap_terrain_cache)
	end

	-- Check for death
	if vtol.health <= 0 and current_game_state == GAME_STATE.PLAYING then
		current_game_state = GAME_STATE.DEAD
		death_timer = 0
	end

	-- Handle death state
	if current_game_state == GAME_STATE.DEAD then
		death_timer += delta_time

		-- Check for restart input (any key or mouse click)
		if key("x") or key("z") or key("space") or key("return") then
			reset_game()
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

	-- Animate flame vertices (subtle flickering with noise)
	local flame_time = time() * 6  -- Animation speed
	for i, base_vert in ipairs(flame_base_verts) do
		-- Base flicker (subtle sine wave)
		local base_flicker = sin(flame_time + base_vert.engine_idx * 2.5) * 0.03

		-- Add noise (combine multiple sine waves at different frequencies)
		local noise = sin(flame_time * 3.7 + i * 0.5) * 0.015
		noise += sin(flame_time * 7.2 + i * 1.3) * 0.01

		local scale_mod = 1.0 + base_flicker + noise

		-- Apply animated scale to flame vertices
		local vert_idx = #cross_lander_mesh.verts + i
		vtol_verts[vert_idx].x = base_vert.base_x + base_vert.offset_x * (scale_mod - 1.0)
		vtol_verts[vert_idx].y = base_vert.base_y + base_vert.offset_y * (scale_mod - 1.0) * 1.2  -- Slight Y stretching
		vtol_verts[vert_idx].z = base_vert.base_z + base_vert.offset_z * (scale_mod - 1.0)
	end

	-- VTOL Physics Update
	-- Apply gravity
	vtol.vy += vtol.gravity

	-- Thruster controls (WASD or IJKL - can hold multiple at once)
	-- Check each key separately
	local w_pressed = key("w") or key("i")  -- W or I
	local a_pressed = key("a") or key("j")  -- A or J
	local s_pressed = key("s") or key("k")  -- S or K
	local d_pressed = key("d") or key("l")  -- D or L

	-- Special combination keys
	local space_pressed = key("space")  -- Fire all thrusters
	local n_pressed = key("n")  -- Fire A+D (left/right pair)
	local m_pressed = key("m")  -- Fire W+S (front/back pair)
	local shift_pressed = key("lshift") or key("rshift")  -- Auto-level ship

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

	-- Height limit (400m ceiling) - disable thrusters if too high
	local max_height = 400
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

				if vtol.y < building_height then
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
						vtol.health -= damage

						-- Spawn explosion effect at random engine
						add_explosion(vtol)

						-- Start smoking if health is low
						if vtol.health < 50 then
							vtol.is_damaged = true
						end
					end

					-- Kill velocity when hitting side
					vtol.vx *= 0.5
					vtol.vz *= 0.5
				else
					-- Above building - rooftop is a potential landing surface
					ground_height = max(ground_height, building_height)
				end
			end
		end
	end

	-- Landing pad collision (same logic as buildings)
	local half_width = landing_pad.width / 2
	local half_depth = landing_pad.depth / 2

	if Collision.point_in_box(vtol.x, vtol.z, landing_pad.x, landing_pad.z, half_width, half_depth) then
		-- VTOL is horizontally above/inside landing pad
		if vtol.y < landing_pad.height then
			-- Side collision with landing pad - push out using Collision module
			vtol.x, vtol.z = Collision.push_out_of_box(
				vtol.x, vtol.z,
				landing_pad.x, landing_pad.z,
				half_width, half_depth
			)

			-- Calculate collision velocity for damage
			local collision_speed = sqrt(vtol.vx*vtol.vx + vtol.vy*vtol.vy + vtol.vz*vtol.vz)
			if collision_speed > DAMAGE_BUILDING_THRESHOLD then
				local damage = collision_speed * DAMAGE_BUILDING_MULTIPLIER
				vtol.health -= damage

				-- Spawn explosion effect at random engine
				add_explosion(vtol)

				-- Start smoking if health is low
				if vtol.health < 50 then
					vtol.is_damaged = true
				end
			end

			-- Kill velocity when hitting side
			vtol.vx *= 0.5
			vtol.vz *= 0.5
		else
			-- Above landing pad - it's a landing surface
			ground_height = max(ground_height, landing_pad.height)
		end
	end

	-- Ground/rooftop collision (use 0.5 offset for VTOL center)
	-- If using heightmap, sample terrain height at VTOL position
	local terrain_height = 0
	if USE_HEIGHTMAP then
		terrain_height = Heightmap.get_height(vtol.x, vtol.z)
	end

	local landing_height = max(ground_height, terrain_height) + 0.5
	if vtol.y < landing_height then
		-- Check impact velocity for damage
		if vtol.vy < DAMAGE_GROUND_THRESHOLD then  -- Hard landing
			local damage = abs(vtol.vy) * DAMAGE_GROUND_MULTIPLIER
			vtol.health -= damage

			-- Spawn explosion effect at random engine
			add_explosion(vtol)

			-- Start smoking if health is low
			if vtol.health < 50 then
				vtol.is_damaged = true
			end
		end

		vtol.y = landing_height
		vtol.vy = 0
		-- Dampen rotation when touching any surface
		vtol.vpitch *= VTOL_GROUND_PITCH_DAMPING
		vtol.vroll *= VTOL_GROUND_ROLL_DAMPING
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

end

function _draw()
	cls(5)  -- Background color index 6

	-- Update FPS counter (count rendered frames)
  	current_fps = stat(7)

	-- Show death screen
	if current_game_state == GAME_STATE.DEAD then
		-- Dark overlay
		rectfill(0, 0, 480, 270, 0)

		-- "YOU DIED" text with shadow
		local death_text = "YOU DIED"
		local text_x = 240 - (#death_text * 4)
		local text_y = 100

		-- Shadow
		print(death_text, text_x + 2, text_y + 2, 0)
		-- Main text (red)
		print(death_text, text_x, text_y, 8)

		-- Stats
		local stats_y = 130
		print("FINAL HULL: "..flr(max(0, vtol.health)).."%", 240 - 60, stats_y, 7)

		-- Restart prompt (flashing)
		local flash = (time() * 2) % 1 > 0.5
		if flash then
			local prompt = "PRESS ANY KEY TO RESTART"
			local prompt_x = 240 - (#prompt * 2)
			print(prompt, prompt_x, 160, 11)
		end

		return
	end

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

	-- Animate water: swap between SPRITE_WATER and SPRITE_WATER2 every 1 second
	local water_frame = flr(time()) % 2  -- 0 or 1, changes every second
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


	-- Get sphere faces (floating above the city)
	local sphere_sorted = render_mesh(sphere_verts, sphere_faces, 0, 5, 0)
	for _, f in ipairs(sphere_sorted) do
		add(all_faces, f)
	end

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

	-- Render VTOL with rotation (filter flame faces only - smoke is now independent)
	local vtol_faces_filtered = {}
	for i, face in ipairs(vtol_faces) do
		local should_show = true

		-- Check if this face is a flame
		for _, flame_info in ipairs(flame_face_indices) do
			if i >= flame_info.start_idx and i <= flame_info.end_idx then
				-- Only show flame if thruster is active
				should_show = vtol.thrusters[flame_info.thruster_idx].active
				break
			end
		end

		if should_show then
			-- Create face copy with damage sprite if needed
			local face_copy = {face[1], face[2], face[3], face[4], face[5], face[6], face[7]}
			if use_damage_sprite and face[4] == SPRITE_SHIP then
				face_copy[4] = SPRITE_SHIP_DAMAGE  -- Switch to damage sprite
			end
			add(vtol_faces_filtered, face_copy)
		end
	end

	local vtol_sorted = render_mesh(
		vtol_verts,
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
	local health_bar_height = 8

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
	rect(health_bar_x, health_bar_y, health_bar_x + health_bar_width, health_bar_y + health_bar_height, 7)

	-- Health text
	print("HULL: "..flr(max(0, vtol.health)).."%", health_bar_x + 2, health_bar_y + 1, 7)

	-- Performance info
	local cpu = stat(1) * 100
	--print("FPS: "..current_fps.."  fc:"..fps_counter.." ft:"..flr(fps_timer*100)/100, 2, 2, 11)
	print("CPU: "..flr(cpu).."%", 2, 10, 11)
	print("Tris: "..#all_faces, 2, 18, 11)
	print("Objects: "..objects_rendered.."/"..objects_rendered+objects_culled.." (culled: "..objects_culled..")", 2, 26, 11)
	print("VTOL: x="..flr(vtol.x*10)/10 .." y="..flr(vtol.y*10)/10 .." z="..flr(vtol.z*10)/10, 2, 34, 10)

	-- Velocity debug info
	local vel_total = sqrt(vtol.vx*vtol.vx + vtol.vy*vtol.vy + vtol.vz*vtol.vz)
	print("VEL: "..flr(vel_total*1000)/1000, 2, 42, 10)
	print("  vx="..flr(vtol.vx*1000)/1000 .." vy="..flr(vtol.vy*1000)/1000 .." vz="..flr(vtol.vz*1000)/1000, 2, 50, 6)

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
	Minimap.draw(camera, vtol, buildings, building_configs, landing_pad, Heightmap, position_history)

	-- Draw 3D compass (cross/diamond shape with red and grey arrows)
	-- Side view: <> (diamond), Front view: X (cross)
	-- Two red arrows (north/south axis) and two grey arrows (east/west axis)
	local compass_x = 240  -- Center of screen
	local compass_y = 240  -- Bottom middle
	local compass_size = 12

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
		-- Draw landing pad collision box (green)
		Collision.draw_wireframe(
			camera,
			landing_pad.x,
			landing_pad.y,
			landing_pad.z,
			landing_pad.width,
			landing_pad.height,
			landing_pad.depth,
			11  -- Green
		)

		-- Draw building collision boxes (red)
		for _, building in ipairs(buildings) do
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
end
