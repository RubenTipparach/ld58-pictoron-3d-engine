local scanlines = userdata("f64",11,270)

-- Load modules
local load_obj = include("obj_loader.lua")
local ParticleSystem = include("particle_system.lua")

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
local DEBUG_SHOW_PHYSICS_WIREFRAME = false  -- Toggle physics collision wireframes

-- Minimap Configuration
local MINIMAP_X = 420  -- Top-right corner
local MINIMAP_Y = 10
local MINIMAP_SIZE = 50  -- 50x50 pixels
local MINIMAP_SCALE = 2  -- World units per pixel
local MINIMAP_BG_COLOR = 1  -- Dark blue background

-- Game State Management
local GAME_STATE = {
	PLAYING = 1,
	DEAD = 2
}
local current_game_state = GAME_STATE.PLAYING
local death_timer = 0

---Draws a 3D textured triangle to the screen. Note that the vertices need W components,
---and that they need to be the reciprocal of the W which is produced by the projection matrix.
---This step is typically done in the perspective division step.
---@param props table The properties passed to the shader. Expects a `tex` field with a texture index.
---@param vert_data userdata A 6x3 matrix where each row is the xyzwuv of a vertex.
---@param screen_height number The height of the screen, used for scanline truncation.
local function textri(props,vert_data,screen_height)
    local spr = props.tex

    -- To make it so that rasterizing top to bottom is always correct,
    -- and so that we know at which point to switch the minor side's slope,
    -- we need the vertices to be sorted by y.
    vert_data:sort(1)

    -- These values are used extensively in the setup, so we'll store them in
    -- local variables.
    local x1,y1,w1, y2,w2, x3,y3,w3 =
        vert_data[0],vert_data[1],vert_data[3],
        vert_data[7],vert_data[9],
        vert_data[12],vert_data[13],vert_data[15]

    -- To get perspective correct interpolation, we need to multiply
    -- the UVs by the w component of their vertices.
    local uv1,uv3 =
        vec(vert_data[4],vert_data[5])*w1,
        vec(vert_data[16],vert_data[17])*w3

    local t = (y2-y1)/(y3-y1)
    local uvd = (uv3-uv1)*t+uv1
    local v1,v2 =
        vec(spr,x1,y1,x1,y1,uv1.x,uv1.y,uv1.x,uv1.y,w1,w1),
        vec(
            spr,
            vert_data[6],y2,
            (x3-x1)*t+x1, y2,
            vert_data[10]*w2,vert_data[11]*w2, -- uv2
            uvd.x,uvd.y,
            w2,(w3-w1)*t+w1
        )

    local start_y = y1 < -1 and -1 or y1\1
    local mid_y = y2 < -1 and -1 or y2 > screen_height-1 and screen_height-1 or y2\1
    local stop_y = (y3 <= screen_height-1 and y3\1 or screen_height-1)

    -- Top half
    local dy = mid_y-start_y
    if dy > 0 then
        local slope = (v2-v1):div((y2-y1))

        scanlines:copy(slope*(start_y+1-y1)+v1,true,0,0,11)
            :copy(slope,true,0,11,11,0,11,dy-1)

        tline3d(scanlines:add(scanlines,true,0,11,11,11,11,dy-1),0,dy)
    end

    -- Bottom half
    dy = stop_y-mid_y
    if dy > 0 then
        -- This is, otherwise, the only place where v3 would be used,
        -- so we just inline it.
        local slope = (vec(spr,x3,y3,x3,y3,uv3.x,uv3.y,uv3.x,uv3.y,w3,w3)-v2)/(y3-y2)

        scanlines:copy(slope*(mid_y+1-y2)+v2,true,0,0,11)
            :copy(slope,true,0,11,11,0,11,dy-1)

        tline3d(scanlines:add(scanlines,true,0,11,11,11,11,dy-1),0,dy)
    end
end

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
	local verts = {}
	local faces = {}

	-- Start with icosahedron
	local t = (1 + sqrt(5)) / 2
	local vertices = {
		vec(-1, t, 0), vec(1, t, 0), vec(-1, -t, 0), vec(1, -t, 0),
		vec(0, -1, t), vec(0, 1, t), vec(0, -1, -t), vec(0, 1, -t),
		vec(t, 0, -1), vec(t, 0, 1), vec(-t, 0, -1), vec(-t, 0, 1)
	}

	-- Normalize to unit sphere
	for i, v in ipairs(vertices) do
		local len = sqrt(v.x*v.x + v.y*v.y + v.z*v.z)
		vertices[i] = vec(v.x/len, v.y/len, v.z/len)
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
	add(sphere_faces, {face[1], face[2], face[3], 1, vec(0,0), vec(16,0), vec(16,16)})  -- sprite 1
end

-- Ground plane generation (dynamic, based on camera position)
function generate_ground_around_camera(cam_x, cam_z)
	local ground_verts = {}
	local ground_faces = {}

	-- Center ground on camera position (snapped to grid)
	local grid_size = 4  -- Size of each quad
	local grid_count = 8  -- 8x8 grid
	local half_size = grid_count * grid_size / 2

	-- Snap camera position to grid
	local center_x = flr(cam_x / grid_size) * grid_size
	local center_z = flr(cam_z / grid_size) * grid_size

	-- Create vertices for a 9x9 grid (needed for 8x8 quads)
	for gz = 0, grid_count do
		for gx = 0, grid_count do
			add(ground_verts, vec(
				center_x + gx * grid_size - half_size,  -- Center around camera
				0,                                        -- Ground plane at y=0
				center_z + gz * grid_size - half_size
			))
		end
	end

	-- Create quads (2 triangles each) with tiled UVs
	for gz = 0, grid_count - 1 do
		for gx = 0, grid_count - 1 do
			-- Calculate vertex indices (9 vertices per row)
			local v1 = gz * (grid_count + 1) + gx + 1
			local v2 = gz * (grid_count + 1) + gx + 2
			local v3 = (gz + 1) * (grid_count + 1) + gx + 2
			local v4 = (gz + 1) * (grid_count + 1) + gx + 1

			-- UV coordinates with 4x4 tiling (64x64 pixels = 4 tiles of 16x16)
			local uv_tl = vec(0, 0)
			local uv_tr = vec(64, 0)
			local uv_br = vec(64, 64)
			local uv_bl = vec(0, 64)

			-- First triangle (v1, v2, v3)
			add(ground_faces, {v1, v2, v3, 2, uv_tl, uv_tr, uv_br})
			-- Second triangle (v1, v3, v4)
			add(ground_faces, {v1, v3, v4, 2, uv_tl, uv_br, uv_bl})
		end
	end

	return ground_verts, ground_faces
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

	add(buildings, {
		verts = building_verts,
		faces = cube_faces,
		x = x,
		y = 0,
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
	printh("ERROR: Could not load landing pad mesh, using fallback red cube")
	-- Create a 3x3 red cube as fallback
	landing_pad_mesh = {
		verts = {
			vec(-1.5, 0, -1.5), vec(1.5, 0, -1.5), vec(1.5, 0, 1.5), vec(-1.5, 0, 1.5),  -- Bottom
			vec(-1.5, 3, -1.5), vec(1.5, 3, -1.5), vec(1.5, 3, 1.5), vec(-1.5, 3, 1.5)   -- Top
		},
		faces = {
			-- Bottom face
			{1, 2, 3, 8, vec(0,0), vec(16,0), vec(16,16)}, {1, 3, 4, 8, vec(0,0), vec(16,16), vec(0,16)},
			-- Top face
			{5, 7, 6, 8, vec(0,0), vec(16,0), vec(16,16)}, {5, 8, 7, 8, vec(0,0), vec(16,16), vec(0,16)},
			-- Front face
			{1, 5, 6, 8, vec(0,0), vec(16,0), vec(16,16)}, {1, 6, 2, 8, vec(0,0), vec(16,16), vec(0,16)},
			-- Back face
			{3, 7, 8, 8, vec(0,0), vec(16,0), vec(16,16)}, {3, 8, 4, 8, vec(0,0), vec(16,16), vec(0,16)},
			-- Left face
			{4, 8, 5, 8, vec(0,0), vec(16,0), vec(16,16)}, {4, 5, 1, 8, vec(0,0), vec(16,16), vec(0,16)},
			-- Right face
			{2, 6, 7, 8, vec(0,0), vec(16,0), vec(16,16)}, {2, 7, 3, 8, vec(0,0), vec(16,16), vec(0,16)}
		}
	}
end

-- Override sprite to 8 for landing pad (32x32 pixels) and scale UVs to 32x32
for _, face in ipairs(landing_pad_mesh.faces) do
	face[4] = 8  -- Set sprite index to 8
	-- Scale UVs from 16x16 to 32x32 (multiply by 2)
	if face[5] then face[5] = vec(face[5].x * 2, face[5].y * 2) end
	if face[6] then face[6] = vec(face[6].x * 2, face[6].y * 2) end
	if face[7] then face[7] = vec(face[7].x * 2, face[7].y * 2) end
end

-- Calculate bounding box from landing pad mesh
local pad_min_x, pad_max_x = 999, -999
local pad_min_y, pad_max_y = 999, -999
local pad_min_z, pad_max_z = 999, -999

for _, v in ipairs(landing_pad_mesh.verts) do
	pad_min_x = min(pad_min_x, v.x)
	pad_max_x = max(pad_max_x, v.x)
	pad_min_y = min(pad_min_y, v.y)
	pad_max_y = max(pad_max_y, v.y)
	pad_min_z = min(pad_min_z, v.z)
	pad_max_z = max(pad_max_z, v.z)
end

local pad_width = pad_max_x - pad_min_x
local pad_height = pad_max_y - pad_min_y
local pad_depth = pad_max_z - pad_min_z

printh("Landing pad bounds: w="..pad_width.." h="..pad_height.." d="..pad_depth)

-- Landing pad object at spawn position (moved to the right)
local landing_pad = {
	verts = landing_pad_mesh.verts,
	faces = landing_pad_mesh.faces,
	x = 5,  -- Moved 5 units to the right
	y = 0,
	z = -3,
	sprite_override = 8,
	-- Collision box: width/depth from mesh, height fixed at 2m
	width = pad_width,
	height = 2,  -- Fixed at 2m for collision (not mesh height)
	depth = pad_depth
}

-- Load tree mesh from tree.obj
local tree_mesh = load_obj("tree.obj")
if not tree_mesh or #tree_mesh.verts == 0 then
	printh("ERROR: Could not load tree mesh, using fallback red cube")
	-- Create a 3x3 red cube as fallback
	tree_mesh = {
		verts = {
			vec(-1.5, 0, -1.5), vec(1.5, 0, -1.5), vec(1.5, 0, 1.5), vec(-1.5, 0, 1.5),  -- Bottom
			vec(-1.5, 3, -1.5), vec(1.5, 3, -1.5), vec(1.5, 3, 1.5), vec(-1.5, 3, 1.5)   -- Top
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

-- Override sprite to 6 for all tree faces
for _, face in ipairs(tree_mesh.faces) do
	face[4] = 6  -- Set sprite index to 6
end

-- Generate random tree positions (max 3 per 20m x 20m cell)
local trees = {}
local cell_size = 20  -- 20m x 20m cells
local max_trees_per_cell = 3
local map_range = 100  -- Place trees in 200x200m area (-100 to 100)

-- Create grid cells and track tree count per cell
local tree_grid = {}

-- Simple seeded random for consistent tree placement
local function seeded_random(x, z, seed)
	local hash = (x * 73856093) ~ (z * 19349663) ~ (seed * 83492791)
	hash = ((hash ~ (hash >> 13)) * 0x5bd1e995) & 0xffffffff
	hash = hash ~ (hash >> 15)
	return (hash & 0x7fffffff) / 0x7fffffff
end

-- Generate trees with grid-based distribution
for tree_idx = 1, 150 do  -- Try to place up to 150 trees
	local x = (seeded_random(tree_idx, 0, 1234) - 0.5) * map_range * 2
	local z = (seeded_random(tree_idx, 1, 1234) - 0.5) * map_range * 2

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
		add(trees, {
			verts = tree_mesh.verts,
			faces = tree_mesh.faces,
			x = x,
			y = 0,  -- Ground level
			z = z,
			sprite_override = 6
		})
		tree_grid[cell_key] += 1
	end
end

printh("Generated " .. #trees .. " trees across the map")

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

-- VTOL Vehicle Physics
local vtol = {
	-- Position & rotation (centered on landing pad, 2m up)
	x = 5, y = 3, z = -3,  -- Aligned with landing pad center (x=5, z=-3), raised 2m (y=3)
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

-- Load cross_lander mesh from OBJ
local cross_lander_mesh = load_obj("cross_lander.obj")
local flame_mesh = load_obj("flame.obj")

-- Fallback to red cubes if OBJ loading fails
if not cross_lander_mesh or #cross_lander_mesh.verts == 0 then
	printh("ERROR: Could not load cross_lander mesh, using fallback red cube")
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
	printh("ERROR: Could not load flame mesh, using fallback red cube")
	flame_mesh = {
		verts = {
			vec(-0.5, 0, -0.5), vec(0.5, 0, -0.5), vec(0.5, 0, 0.5), vec(-0.5, 0, 0.5),
			vec(-0.5, 1, -0.5), vec(0.5, 1, -0.5), vec(0.5, 1, 0.5), vec(-0.5, 1, 0.5)
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

local vtol_faces = cross_lander_mesh.faces

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
			3,  -- Use sprite 3 for flames
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
	max_particles = 4,
	lifetime = 2.0,
	spawn_rate = 0.3,
	sprite_id = 5,  -- Grey smoke sprite
	scale_growth = 1.5
})
local smoke_spawn_timer = 0
local smoke_spawn_rate = 0.3  -- Base spawn rate (can be modified based on damage)

-- Function to reset game to initial state
local function reset_game()
	-- Reset VTOL state (centered on landing pad, 2m up)
	vtol.x = 5
	vtol.y = 3
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

	-- Reset game state
	current_game_state = GAME_STATE.PLAYING
	death_timer = 0
	smoke_spawn_timer = 0
end

-- Helper function to draw wireframe collision box
local function draw_collision_wireframe(x, y, z, width, height, depth, color)
	-- Calculate 8 corners of the box
	local hw, hh, hd = width/2, height/2, depth/2
	local corners = {
		vec(x - hw, y, z - hd),      -- bottom front left
		vec(x + hw, y, z - hd),      -- bottom front right
		vec(x + hw, y, z + hd),      -- bottom back right
		vec(x - hw, y, z + hd),      -- bottom back left
		vec(x - hw, y + height, z - hd),  -- top front left
		vec(x + hw, y + height, z - hd),  -- top front right
		vec(x + hw, y + height, z + hd),  -- top back right
		vec(x - hw, y + height, z + hd),  -- top back left
	}

	-- Project corners to screen space
	local projected = {}
	local fov = 70
	local fov_rad = fov * 0.5 * 0.0174533
	local tan_half_fov = sin(fov_rad) / cos(fov_rad)
	local cam_dist = 3

	for i, corner in ipairs(corners) do
		local cx, cy, cz = corner.x - camera.x, corner.y - camera.y, corner.z - camera.z

		-- Apply camera rotation
		local cos_ry, sin_ry = cos(camera.ry), sin(camera.ry)
		local cos_rx, sin_rx = cos(camera.rx), sin(camera.rx)

		local x2 = cx * cos_ry - cz * sin_ry
		local z2 = cx * sin_ry + cz * cos_ry

		local y2 = cy * cos_rx - z2 * sin_rx
		local z3 = cy * sin_rx + z2 * cos_rx

		z3 += cam_dist

		if z3 > 0.01 then
			local px = x2 / z3 * (270 / tan_half_fov) + 240
			local py = y2 / z3 * (270 / tan_half_fov) + 135
			projected[i] = {x = px, y = py}
		end
	end

	-- Draw lines between corners if both endpoints are visible
	local edges = {
		{1, 2}, {2, 3}, {3, 4}, {4, 1},  -- bottom
		{5, 6}, {6, 7}, {7, 8}, {8, 5},  -- top
		{1, 5}, {2, 6}, {3, 7}, {4, 8}   -- vertical
	}

	for _, edge in ipairs(edges) do
		local p1, p2 = projected[edge[1]], projected[edge[2]]
		if p1 and p2 then
			line(p1.x, p1.y, p2.x, p2.y, color)
		end
	end
end

-- Helper function to project and render a mesh
local function render_mesh(verts, faces, offset_x, offset_y, offset_z, sprite_override, is_ground, rot_pitch, rot_yaw, rot_roll)
	-- Projection parameters
	local fov = 70  -- Narrower FOV reduces edge distortion
	local near = 0.01  -- Very small near plane to minimize pop-in
	local far = RENDER_DISTANCE  -- Fog/culling distance
	local fov_rad = fov * 0.5 * 0.0174533
	local tan_half_fov = sin(fov_rad) / cos(fov_rad)

	-- Camera distance
	local cam_dist = 5

	-- Early culling: check if object is within render distance (horizontal only)
	local obj_x = offset_x or 0
	local obj_z = offset_z or 0
	local dx = obj_x - camera.x
	local dz = obj_z - camera.z
	local dist_sq = dx*dx + dz*dz  -- Only X and Z distance, ignore Y

	-- Cull objects beyond render range (unless it's ground)
	if not is_ground and dist_sq > far * far then
		objects_culled += 1
		return {}
	end

	objects_rendered += 1

	-- Cache camera-space transformations and project vertices
	local projected = {}
	local depths = {}
	local camera_verts = {}  -- Cache transformed vertices in camera space

	-- Precompute rotation values
	local cos_ry, sin_ry = cos(camera.ry), sin(camera.ry)
	local cos_rx, sin_rx = cos(camera.rx), sin(camera.rx)

	-- Precompute object rotation values (if provided)
	local cos_pitch, sin_pitch, cos_yaw, sin_yaw, cos_roll, sin_roll
	if rot_pitch or rot_yaw or rot_roll then
		cos_pitch, sin_pitch = cos(rot_pitch or 0), sin(rot_pitch or 0)
		cos_yaw, sin_yaw = cos(rot_yaw or 0), sin(rot_yaw or 0)
		cos_roll, sin_roll = cos(rot_roll or 0), sin(rot_roll or 0)
	end

	for i, v in ipairs(verts) do
		local x, y, z = v.x, v.y, v.z

		-- Apply object rotation (pitch, yaw, roll) if provided
		if rot_pitch or rot_yaw or rot_roll then
			-- Yaw (Y axis)
			local x_yaw = x * cos_yaw - z * sin_yaw
			local z_yaw = x * sin_yaw + z * cos_yaw

			-- Pitch (X axis)
			local y_pitch = y * cos_pitch - z_yaw * sin_pitch
			local z_pitch = y * sin_pitch + z_yaw * cos_pitch

			-- Roll (Z axis)
			local x_roll = x_yaw * cos_roll - y_pitch * sin_roll
			local y_roll = x_yaw * sin_roll + y_pitch * cos_roll

			x, y, z = x_roll, y_roll, z_pitch
		end

		-- Apply offset for positioning
		x = x + (offset_x or 0)
		y = y + (offset_y or 0)
		z = z + (offset_z or 0)

		-- Apply camera pan
		x = x - camera.x
		y = y - camera.y
		z = z - camera.z

		-- Rotate around Y axis (using cached values)
		local x2 = x * cos_ry - z * sin_ry
		local z2 = x * sin_ry + z * cos_ry

		-- Rotate around X axis (using cached values)
		local y2 = y * cos_rx - z2 * sin_rx
		local z3 = y * sin_rx + z2 * cos_rx

		-- Move away from camera
		z3 += cam_dist

		-- Store camera-space vertex for later use (backface culling)
		camera_verts[i] = vec(x2, y2, z3)

		-- Perspective projection (allow vertices closer to camera)
		if z3 > near then
			local w = z3
			local px = x2 / z3 * (270 / tan_half_fov)
			local py = y2 / z3 * (270 / tan_half_fov)  -- Keep Y positive (world space up = screen up)

			-- Screen space
			px = px + 240
			py = py + 135

			-- Store projected vertex and its depth
			projected[i] = {x=px, y=py, z=0, w=1/w}
			depths[i] = z3
		else
			projected[i] = nil
			depths[i] = nil
		end
	end

	-- Build list of faces with depth for sorting
	local sorted_faces = {}
	for i, face in ipairs(faces) do
		local v1_idx, v2_idx, v3_idx = face[1], face[2], face[3]
		local p1, p2, p3 = projected[v1_idx], projected[v2_idx], projected[v3_idx]
		local d1, d2, d3 = depths[v1_idx], depths[v2_idx], depths[v3_idx]

		if p1 and p2 and p3 and d1 and d2 and d3 then
			-- Use cached camera-space vertices
			local cv1 = camera_verts[v1_idx]
			local cv2 = camera_verts[v2_idx]
			local cv3 = camera_verts[v3_idx]

			-- Calculate face normal in camera space
			local edge1 = vec(cv2.x - cv1.x, cv2.y - cv1.y, cv2.z - cv1.z)
			local edge2 = vec(cv3.x - cv1.x, cv3.y - cv1.y, cv3.z - cv1.z)

			-- Cross product to get normal
			local nx = edge1.y * edge2.z - edge1.z * edge2.y
			local ny = edge1.z * edge2.x - edge1.x * edge2.z
			local nz = edge1.x * edge2.y - edge1.y * edge2.x

			-- View vector is just the average position (since camera is at origin in camera space)
			local view_x = (cv1.x + cv2.x + cv3.x) / 3
			local view_y = (cv1.y + cv2.y + cv3.y) / 3
			local view_z = (cv1.z + cv2.z + cv3.z) / 3

			-- Dot product of normal and view vector
			local dot = nx * view_x + ny * view_y + nz * view_z

			-- Only render if facing camera (dot product > 0 means facing camera)
			if dot > 0 then
				-- Screen space backface culling as backup
				local edge1_x, edge1_y = p2.x - p1.x, p2.y - p1.y
				local edge2_x, edge2_y = p3.x - p1.x, p3.y - p1.y
				local cross = edge1_x * edge2_y - edge1_y * edge2_x

				-- Only include if facing towards camera (clockwise winding in screen space)
				if cross > 0 then
					-- Calculate average depth for sorting
					local avg_depth = (d1 + d2 + d3) / 3
					-- Add depth bias for ground to ensure it renders behind everything
					if is_ground then
						avg_depth += 1000  -- Push ground far back in sort order
					end
					-- Create a copy of face with sprite override if provided
					local face_copy = {face[1], face[2], face[3], sprite_override or face[4], face[5], face[6], face[7]}
					add(sorted_faces, {face=face_copy, depth=avg_depth, p1=p1, p2=p2, p3=p3})
				end
			end
		end
	end

	return sorted_faces
end

function _update()
	-- Calculate delta time (time since last frame)
	local current_time = time()
	delta_time = current_time - last_time
	last_time = current_time

	-- Update FPS counter
	fps_counter += 1
	fps_timer += delta_time
	if fps_timer >= 1.0 then
		current_fps = fps_counter
		fps_counter = 0
		fps_timer = 0
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

	-- Update thruster active states
	vtol.thrusters[1].active = a_pressed  -- Right thruster (A or J)
	vtol.thrusters[2].active = d_pressed  -- Left thruster (D or L)
	vtol.thrusters[3].active = w_pressed  -- Front thruster (W or I)
	vtol.thrusters[4].active = s_pressed  -- Back thruster (S or K)

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

	-- Building collision (check for rooftop landings and side collisions)
	local ground_height = 0  -- Track the highest surface beneath the VTOL

	for i, building in ipairs(buildings) do
		-- Get building bounds (using config for accurate dimensions)
		local config = building_configs[i]
		if config then
			local half_width = config.width
			local half_depth = config.depth
			local building_height = config.height * 2  -- Height is scaled by 2 in vertex generation

			-- Check if VTOL is within building's horizontal bounds
			local dx = vtol.x - building.x
			local dz = vtol.z - building.z

			if abs(dx) < half_width and abs(dz) < half_depth then
				-- VTOL is horizontally above/inside this building

				if vtol.y < building_height then
					-- Side collision: VTOL is inside the building volume
					-- Teleport out to nearest edge
					local push_x = 0
					local push_z = 0

					-- Find closest edge
					local dist_left = abs(dx + half_width)
					local dist_right = abs(dx - half_width)
					local dist_front = abs(dz + half_depth)
					local dist_back = abs(dz - half_depth)

					local min_dist = min(dist_left, dist_right, dist_front, dist_back)

					if min_dist == dist_left then
						vtol.x = building.x - half_width - 0.1
					elseif min_dist == dist_right then
						vtol.x = building.x + half_width + 0.1
					elseif min_dist == dist_front then
						vtol.z = building.z - half_depth - 0.1
					else
						vtol.z = building.z + half_depth + 0.1
					end

					-- Calculate collision velocity for damage
					local collision_speed = sqrt(vtol.vx*vtol.vx + vtol.vy*vtol.vy + vtol.vz*vtol.vz)
					if collision_speed > DAMAGE_BUILDING_THRESHOLD then
						local damage = collision_speed * DAMAGE_BUILDING_MULTIPLIER
						vtol.health -= damage

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
	local dx = vtol.x - landing_pad.x
	local dz = vtol.z - landing_pad.z

	if abs(dx) < half_width and abs(dz) < half_depth then
		-- VTOL is horizontally above/inside landing pad
		if vtol.y < landing_pad.height then
			-- Side collision with landing pad
			local push_x = 0
			local push_z = 0

			-- Find closest edge
			local dist_left = abs(dx + half_width)
			local dist_right = abs(dx - half_width)
			local dist_front = abs(dz + half_depth)
			local dist_back = abs(dz - half_depth)

			local min_dist = min(dist_left, dist_right, dist_front, dist_back)

			if min_dist == dist_left then
				vtol.x = landing_pad.x - half_width - 0.1
			elseif min_dist == dist_right then
				vtol.x = landing_pad.x + half_width + 0.1
			elseif min_dist == dist_front then
				vtol.z = landing_pad.z - half_depth - 0.1
			else
				vtol.z = landing_pad.z + half_depth + 0.1
			end

			-- Calculate collision velocity for damage
			local collision_speed = sqrt(vtol.vx*vtol.vx + vtol.vy*vtol.vy + vtol.vz*vtol.vz)
			if collision_speed > DAMAGE_BUILDING_THRESHOLD then
				local damage = collision_speed * DAMAGE_BUILDING_MULTIPLIER
				vtol.health -= damage

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
	local landing_height = ground_height + 0.5
	if vtol.y < landing_height then
		-- Check impact velocity for damage
		if vtol.vy < DAMAGE_GROUND_THRESHOLD then  -- Hard landing
			local damage = abs(vtol.vy) * DAMAGE_GROUND_MULTIPLIER
			vtol.health -= damage

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
		local spawn_rate = smoke_spawn_rate
		if health_percent <= 50 then spawn_rate = 0.2 end
		if health_percent <= 30 then spawn_rate = 0.15 end

		-- Spawn new particle if timer expired
		if smoke_spawn_timer >= spawn_rate then
			smoke_spawn_timer = 0
			-- Spawn particle at ship center with inherited velocity
			smoke_system:spawn(vtol.x, vtol.y, vtol.z, vtol.vx, vtol.vy, vtol.vz)
		end
	end

	-- Update smoke particle system
	smoke_system:update(delta_time)

	-- Camera follows VTOL with smooth lerp (doesn't drift too far)
	local camera_offset = 5  -- Distance behind VTOL
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
	cls(0)

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

	-- Generate and render ground plane dynamically around camera
	local ground_verts, ground_faces = generate_ground_around_camera(camera.x, camera.z)
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

	-- Render smoke particles using particle system
	local smoke_faces = smoke_system:render(render_mesh)
	for _, f in ipairs(smoke_faces) do
		f.is_vtol = true  -- Mark smoke as VTOL-related
		add(all_faces, f)
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
			add(vtol_faces_filtered, face)
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

	-- Sort all faces by depth (back to front - painter's algorithm)
	-- Using insertion sort - more efficient for mostly sorted data
	for i = 2, #all_faces do
		local key = all_faces[i]
		local j = i - 1
		-- Move elements that are closer than key to one position ahead
		while j >= 1 and all_faces[j].depth < key.depth do
			all_faces[j + 1] = all_faces[j]
			j = j - 1
		end
		all_faces[j + 1] = key
	end

	-- Calculate if ship should flash red (critically damaged)
	local health_percent = vtol.health / vtol.max_health
	local ship_flash_red = false
	if health_percent < 0.2 then  -- Below 20%
		ship_flash_red = (time() * 4) % 1 > 0.5  -- Flash on/off
	end

	-- Draw all faces in sorted order (reuse pooled userdata)
	for _, f in ipairs(all_faces) do
		local face = f.face
		local sprite_id = face[4]
		local uv1 = face[5] or vec(0,0)
		local uv2 = face[6] or vec(16,0)
		local uv3 = face[7] or vec(16,16)

		-- Apply red flash to ship sprite (sprite 0) when critically damaged
		local render_sprite = sprite_id
		if sprite_id == 0 and ship_flash_red then
			render_sprite = 8  -- Red sprite for flash effect
		end

		-- Reuse pooled vert_data (no allocation!)
		-- Vertex 1
		vert_data_pool[0], vert_data_pool[1], vert_data_pool[2], vert_data_pool[3], vert_data_pool[4], vert_data_pool[5] =
			f.p1.x, f.p1.y, 0, f.p1.w, uv1.x, uv1.y
		-- Vertex 2
		vert_data_pool[6], vert_data_pool[7], vert_data_pool[8], vert_data_pool[9], vert_data_pool[10], vert_data_pool[11] =
			f.p2.x, f.p2.y, 0, f.p2.w, uv2.x, uv2.y
		-- Vertex 3
		vert_data_pool[12], vert_data_pool[13], vert_data_pool[14], vert_data_pool[15], vert_data_pool[16], vert_data_pool[17] =
			f.p3.x, f.p3.y, 0, f.p3.w, uv3.x, uv3.y

		-- Apply dithering for flame sprites (sprite 3) and smoke sprites (sprite 5)
		if sprite_id == 3 then
			fillp(0b0101101001011010)  -- 50% dither pattern for flames
		elseif sprite_id == 5 then
			-- Smoke sprite with graduated opacity
			local opacity = f.opacity or 1.0

			-- Use different dither patterns for different opacity levels
			if opacity < 0.25 then
				fillp(0b1000000010000000)  -- ~12.5% opacity (very sparse)
			elseif opacity < 0.5 then
				fillp(0b1000010010000100)  -- ~25% opacity
			elseif opacity < 0.75 then
				fillp(0b0101101001011010)  -- 50% opacity
			else
				fillp(0b0111111101111111)  -- ~87.5% opacity (mostly solid)
			end
		else
			fillp()  -- Reset to solid
		end

		textri({tex = render_sprite}, vert_data_pool, 270)
	end

	fillp()  -- Reset fill pattern after drawing

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
	print("FPS: "..current_fps, 2, 2, 11)
	print("CPU: "..flr(cpu).."%", 2, 10, 11)
	print("Tris: "..#all_faces, 2, 18, 11)
	print("Objects: "..objects_rendered.."/"..objects_rendered+objects_culled.." (culled: "..objects_culled..")", 2, 26, 11)
	print("VTOL: x="..flr(vtol.x*10)/10 .." y="..flr(vtol.y*10)/10 .." z="..flr(vtol.z*10)/10, 2, 34, 10)

	-- Velocity debug info
	local vel_total = sqrt(vtol.vx*vtol.vx + vtol.vy*vtol.vy + vtol.vz*vtol.vz)
	print("VEL: "..flr(vel_total*1000)/1000, 2, 42, 10)
	print("  vx="..flr(vtol.vx*1000)/1000 .." vy="..flr(vtol.vy*1000)/1000 .." vz="..flr(vtol.vz*1000)/1000, 2, 50, 6)

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

	-- print("Mouse: Look around", 2, 254, 7)
	print("WASD: Thrusters (hold multiple)", 2, 262, 7)

	-- Draw minimap
	-- Background
	rectfill(MINIMAP_X, MINIMAP_Y, MINIMAP_X + MINIMAP_SIZE, MINIMAP_Y + MINIMAP_SIZE, MINIMAP_BG_COLOR)
	rect(MINIMAP_X, MINIMAP_Y, MINIMAP_X + MINIMAP_SIZE, MINIMAP_Y + MINIMAP_SIZE, 7)  -- Border

	-- Draw buildings
	for _, building in ipairs(buildings) do
		-- Convert world position to minimap position
		local mx = MINIMAP_X + MINIMAP_SIZE / 2 + (building.x - camera.x) / MINIMAP_SCALE
		local my = MINIMAP_Y + MINIMAP_SIZE / 2 + (building.z - camera.z) / MINIMAP_SCALE

		-- Only draw if within minimap bounds
		if mx >= MINIMAP_X and mx <= MINIMAP_X + MINIMAP_SIZE and
		   my >= MINIMAP_Y and my <= MINIMAP_Y + MINIMAP_SIZE then
			pset(mx, my, 12)  -- Light blue for buildings
		end
	end


	-- Draw VTOL (blinking yellow dot)
	local blink = (time() * 4) % 1 > 0.5  -- Blink 4 times per second
	if blink then
		local vtol_mx = MINIMAP_X + MINIMAP_SIZE / 2
		local vtol_my = MINIMAP_Y + MINIMAP_SIZE / 2
		circfill(vtol_mx, vtol_my, 1, 10)  -- Yellow dot
	end

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

	-- Draw physics wireframes (if enabled)
	if DEBUG_SHOW_PHYSICS_WIREFRAME then
		-- Draw landing pad collision box (green)
		draw_collision_wireframe(
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
			draw_collision_wireframe(
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
