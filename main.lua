local scanlines = userdata("f64",11,270)

-- VTOL Physics Configuration (easy tweaking)
local VTOL_THRUST = 0.002  -- Thrust force per thruster
local VTOL_TORQUE_YAW = 0.001  -- Torque around Y axis (yaw)
local VTOL_TORQUE_PITCH = 0.0008  -- Torque around X axis (pitch)
local VTOL_TORQUE_ROLL = 0.0008  -- Torque around Z axis (roll)
local VTOL_MASS = 30
local VTOL_GRAVITY = -0.003
local VTOL_DAMPING = 0.95  -- Linear velocity damping (air resistance)
local VTOL_ANGULAR_DAMPING = 0.85 -- Angular velocity damping (rotational drag)
local VTOL_GROUND_PITCH_DAMPING = 0.8  -- Rotation damping when touching ground (pitch)
local VTOL_GROUND_ROLL_DAMPING = 0.8   -- Rotation damping when touching ground (roll)

-- Rendering Configuration
local RENDER_DISTANCE = 20  -- Far plane / fog distance

-- Minimap Configuration
local MINIMAP_X = 420  -- Top-right corner
local MINIMAP_Y = 10
local MINIMAP_SIZE = 50  -- 50x50 pixels
local MINIMAP_SCALE = 2  -- World units per pixel
local MINIMAP_BG_COLOR = 1  -- Dark blue background

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
		sprite_override = sprite  -- Use sprite from config (0 or 1)
	})
end

-- Load random mesh from random.lua
local random_mesh = include("random.lua")

-- Create hovering object from random mesh
local hovering_object = {
	verts = random_mesh.verts,
	faces = random_mesh.faces,
	x = 0,       -- Center over city
	y = 7,       -- Hover above buildings
	z = 12,      -- Position over city
	sprite_override = 0  -- Use sprite 0 for testing
}

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
	-- Position & rotation (in front of camera)
	x = 0, y = 1, z = -3,
	pitch = 0, yaw = 0, roll = 0,

	-- Velocity & angular velocity
	vx = 0, vy = 0, vz = 0,
	vpitch = 0, vyaw = 0, vroll = 0,

	-- Thruster positions (relative to center)
	thrusters = {
		{x = 1, z = 0, key = "a", active = false},   -- Right (A)
		{x = -1, z = 0, key = "d", active = false},  -- Left (D)
		{x = 0, z = 1, key = "w", active = false},   -- Front (W)
		{x = 0, z = -1, key = "s", active = false},  -- Back (S)
	},

	-- Physics constants (use globals for easy tweaking)
	mass = VTOL_MASS,
	thrust = VTOL_THRUST,
	gravity = VTOL_GRAVITY,
	damping = VTOL_DAMPING,
	angular_damping = VTOL_ANGULAR_DAMPING,
}

-- VTOL cube model (simple cross shape)
local vtol_verts = {
	-- Center body
	vec(-0.3, -0.2, -0.3), vec(0.3, -0.2, -0.3), vec(0.3, 0.2, -0.3), vec(-0.3, 0.2, -0.3),
	vec(-0.3, -0.2, 0.3), vec(0.3, -0.2, 0.3), vec(0.3, 0.2, 0.3), vec(-0.3, 0.2, 0.3),
	-- Right thruster arm
	vec(0.3, -0.1, -0.1), vec(1.2, -0.1, -0.1), vec(1.2, 0.1, -0.1), vec(0.3, 0.1, -0.1),
	vec(0.3, -0.1, 0.1), vec(1.2, -0.1, 0.1), vec(1.2, 0.1, 0.1), vec(0.3, 0.1, 0.1),
	-- Left thruster arm
	vec(-1.2, -0.1, -0.1), vec(-0.3, -0.1, -0.1), vec(-0.3, 0.1, -0.1), vec(-1.2, 0.1, -0.1),
	vec(-1.2, -0.1, 0.1), vec(-0.3, -0.1, 0.1), vec(-0.3, 0.1, 0.1), vec(-1.2, 0.1, 0.1),
	-- Front thruster arm
	vec(-0.1, -0.1, 0.3), vec(0.1, -0.1, 0.3), vec(0.1, 0.1, 0.3), vec(-0.1, 0.1, 0.3),
	vec(-0.1, -0.1, 1.2), vec(0.1, -0.1, 1.2), vec(0.1, 0.1, 1.2), vec(-0.1, 0.1, 1.2),
	-- Back thruster arm
	vec(-0.1, -0.1, -1.2), vec(0.1, -0.1, -1.2), vec(0.1, 0.1, -1.2), vec(-0.1, 0.1, -1.2),
	vec(-0.1, -0.1, -0.3), vec(0.1, -0.1, -0.3), vec(0.1, 0.1, -0.3), vec(-0.1, 0.1, -0.3),
}

-- Generate simple cube faces for VTOL
local vtol_faces = {}
local function add_cube_faces(v_offset, sprite)
	add(vtol_faces, {v_offset+1, v_offset+2, v_offset+3, sprite, vec(0,0), vec(16,0), vec(16,16)})
	add(vtol_faces, {v_offset+1, v_offset+3, v_offset+4, sprite, vec(0,0), vec(16,16), vec(0,16)})
	add(vtol_faces, {v_offset+6, v_offset+5, v_offset+8, sprite, vec(0,0), vec(16,0), vec(16,16)})
	add(vtol_faces, {v_offset+6, v_offset+8, v_offset+7, sprite, vec(0,0), vec(16,16), vec(0,16)})
	add(vtol_faces, {v_offset+5, v_offset+1, v_offset+4, sprite, vec(0,0), vec(16,0), vec(16,16)})
	add(vtol_faces, {v_offset+5, v_offset+4, v_offset+8, sprite, vec(0,0), vec(16,16), vec(0,16)})
	add(vtol_faces, {v_offset+2, v_offset+6, v_offset+7, sprite, vec(0,0), vec(16,0), vec(16,16)})
	add(vtol_faces, {v_offset+2, v_offset+7, v_offset+3, sprite, vec(0,0), vec(16,16), vec(0,16)})
	add(vtol_faces, {v_offset+4, v_offset+3, v_offset+7, sprite, vec(0,0), vec(16,0), vec(16,16)})
	add(vtol_faces, {v_offset+4, v_offset+7, v_offset+8, sprite, vec(0,0), vec(16,16), vec(0,16)})
	add(vtol_faces, {v_offset+5, v_offset+6, v_offset+2, sprite, vec(0,0), vec(16,0), vec(16,16)})
	add(vtol_faces, {v_offset+5, v_offset+2, v_offset+1, sprite, vec(0,0), vec(16,16), vec(0,16)})
end

-- Center body (sprite 0)
add_cube_faces(0, 0)
-- Right arm (sprite 1)
add_cube_faces(8, 1)
-- Left arm (sprite 1)
add_cube_faces(16, 1)
-- Front arm (sprite 1)
add_cube_faces(24, 1)
-- Back arm (sprite 1)
add_cube_faces(32, 1)

-- Flame cubes (one for each thruster, sprite 3 for red flames)
-- Right thruster flame
local flame_verts_start = #vtol_verts
for _, v in ipairs(cube_verts) do
	add(vtol_verts, vec(v.x * 0.15 + 1, v.y * 0.15 - 0.3, v.z * 0.15))
end
add_cube_faces(flame_verts_start, 3)

-- Left thruster flame
flame_verts_start = #vtol_verts
for _, v in ipairs(cube_verts) do
	add(vtol_verts, vec(v.x * 0.15 - 1, v.y * 0.15 - 0.3, v.z * 0.15))
end
add_cube_faces(flame_verts_start, 3)

-- Front thruster flame
flame_verts_start = #vtol_verts
for _, v in ipairs(cube_verts) do
	add(vtol_verts, vec(v.x * 0.15, v.y * 0.15 - 0.3, v.z * 0.15 + 1))
end
add_cube_faces(flame_verts_start, 3)

-- Back thruster flame
flame_verts_start = #vtol_verts
for _, v in ipairs(cube_verts) do
	add(vtol_verts, vec(v.x * 0.15, v.y * 0.15 - 0.3, v.z * 0.15 - 1))
end
add_cube_faces(flame_verts_start, 3)

-- Track which faces are flames (last 48 faces, 12 per flame cube)
local flame_face_indices = {
	{start_idx = #vtol_faces - 47, end_idx = #vtol_faces - 36, thruster_idx = 1},  -- Right
	{start_idx = #vtol_faces - 35, end_idx = #vtol_faces - 24, thruster_idx = 2},  -- Left
	{start_idx = #vtol_faces - 23, end_idx = #vtol_faces - 12, thruster_idx = 3},  -- Front
	{start_idx = #vtol_faces - 11, end_idx = #vtol_faces, thruster_idx = 4},       -- Back
}

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

	-- Mouse camera control
	local mouse_x, mouse_y = mouse()
	camera.ry = (mouse_x - 240) / 240 * 0.5  -- Horizontal mouse controls yaw
	camera.rx = (mouse_y - 135) / 135 * 0.3  -- Vertical mouse controls pitch

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

	-- Ground/rooftop collision (use 0.5 offset for VTOL center)
	local landing_height = ground_height + 0.5
	if vtol.y < landing_height then
		vtol.y = landing_height
		vtol.vy = 0
		-- Dampen rotation when touching any surface
		vtol.vpitch *= VTOL_GROUND_PITCH_DAMPING
		vtol.vroll *= VTOL_GROUND_ROLL_DAMPING
	end

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

	-- Render hovering object from random.lua
	local hovering_faces = render_mesh(
		hovering_object.verts,
		hovering_object.faces,
		hovering_object.x,
		hovering_object.y,
		hovering_object.z,
		hovering_object.sprite_override
	)
	for _, f in ipairs(hovering_faces) do
		add(all_faces, f)
	end

	-- Get sphere faces (floating above the city)
	local sphere_sorted = render_mesh(sphere_verts, sphere_faces, 0, 5, 0)
	for _, f in ipairs(sphere_sorted) do
		add(all_faces, f)
	end

	-- Render VTOL with rotation (filter flame faces based on active thrusters)
	local vtol_faces_filtered = {}
	for i, face in ipairs(vtol_faces) do
		local is_flame = false
		local should_show = true

		-- Check if this face is a flame
		for _, flame_info in ipairs(flame_face_indices) do
			if i >= flame_info.start_idx and i <= flame_info.end_idx then
				is_flame = true
				-- Only show flame if thruster is active
				should_show = vtol.thrusters[flame_info.thruster_idx].active
				break
			end
		end

		-- Add face if it's not a flame, or if it's a flame and thruster is active
		if not is_flame or should_show then
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
		add(all_faces, f)
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

	-- Draw all faces in sorted order (reuse pooled userdata)
	for _, f in ipairs(all_faces) do
		local face = f.face
		local sprite_id = face[4]
		local uv1 = face[5] or vec(0,0)
		local uv2 = face[6] or vec(16,0)
		local uv3 = face[7] or vec(16,16)

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

		textri({tex = sprite_id}, vert_data_pool, 270)
	end

	-- Performance info
	local cpu = stat(1) * 100
	print("FPS: "..current_fps, 2, 2, 11)
	print("CPU: "..flr(cpu).."%", 2, 10, 11)
	print("Tris: "..#all_faces, 2, 18, 11)
	print("Objects: "..objects_rendered.."/"..objects_rendered+objects_culled.." (culled: "..objects_culled..")", 2, 26, 11)
	print("VTOL: x="..flr(vtol.x*10)/10 .." y="..flr(vtol.y*10)/10 .." z="..flr(vtol.z*10)/10, 2, 34, 10)

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

	-- Draw hovering object
	local hx = MINIMAP_X + MINIMAP_SIZE / 2 + (hovering_object.x - camera.x) / MINIMAP_SCALE
	local hy = MINIMAP_Y + MINIMAP_SIZE / 2 + (hovering_object.z - camera.z) / MINIMAP_SCALE
	if hx >= MINIMAP_X and hx <= MINIMAP_X + MINIMAP_SIZE and
	   hy >= MINIMAP_Y and hy <= MINIMAP_Y + MINIMAP_SIZE then
		circfill(hx, hy, 2, 14)  -- Pink/magenta circle for hovering object
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
end
