local scanlines = userdata("f64",11,270)

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

-- Generate ground plane (4x4 grid of quads = 16 quads)
local ground_verts = {}
local ground_faces = {}

-- Create vertices for a 5x5 grid (needed for 4x4 quads)
for gz = 0, 4 do
	for gx = 0, 4 do
		add(ground_verts, vec(
			gx * 4 - 8,  -- Center around origin, 4 units per quad
			0,           -- Ground plane at y=0
			gz * 4 - 8
		))
	end
end

-- Create quads (2 triangles each) with tiled UVs
for gz = 0, 3 do
	for gx = 0, 3 do
		-- Calculate vertex indices (5 vertices per row)
		local v1 = gz * 5 + gx + 1
		local v2 = gz * 5 + gx + 2
		local v3 = (gz + 1) * 5 + gx + 2
		local v4 = (gz + 1) * 5 + gx + 1

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

-- Generate city buildings (10 cubes of varying sizes and positions)
local buildings = {}
for i = 1, 10 do
	-- Random position in a grid-like pattern
	local x = ((i - 1) % 5) * 3 - 6  -- Spread along x: -6 to 6
	local z = flr((i - 1) / 5) * 3 - 1.5  -- Two rows

	-- Random height (1 to 4 units)
	local height = 1 + (i % 4)

	-- Random width and depth (0.5 to 1.5 units)
	local width = 0.5 + (i * 0.1) % 1
	local depth = 0.5 + ((i * 7) % 10) * 0.1

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

	-- Sprite alternates between 0 and 1
	local sprite = i % 2

	add(buildings, {
		verts = building_verts,
		faces = cube_faces,
		x = x,
		y = 0,
		z = z,
		sprite_override = sprite
	})
end

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
	y = -1,  -- Start slightly elevated
	z = -8,  -- Start further back to see the city
	rx = 0,  -- rotation around X axis
	ry = 0,  -- rotation around Y axis
}

-- Performance tracking
local fps_counter = 0
local fps_timer = 0
local current_fps = 0

-- Helper function to project and render a mesh
local function render_mesh(verts, faces, offset_x, offset_y, offset_z, sprite_override, is_ground)
	-- Projection parameters
	local fov = 70  -- Narrower FOV reduces edge distortion
	local near = 0.01  -- Very small near plane to minimize pop-in
	local fov_rad = fov * 0.5 * 0.0174533
	local tan_half_fov = sin(fov_rad) / cos(fov_rad)

	-- Camera distance
	local cam_dist = 5

	-- Transform and project vertices, storing depth for each
	local projected = {}
	local depths = {}
	for i, v in ipairs(verts) do
		-- Apply offset for positioning
		local x = v.x + (offset_x or 0)
		local y = v.y + (offset_y or 0)
		local z = v.z + (offset_z or 0)

		-- Apply camera pan
		x = x - camera.x
		y = y - camera.y
		z = z - camera.z

		-- Rotate around Y axis
		local x2 = x * cos(camera.ry) - z * sin(camera.ry)
		local z2 = x * sin(camera.ry) + z * cos(camera.ry)

		-- Rotate around X axis
		local y2 = y * cos(camera.rx) - z2 * sin(camera.rx)
		local z3 = y * sin(camera.rx) + z2 * cos(camera.rx)

		-- Move away from camera
		z3 += cam_dist

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
			-- Get original vertices for view-space backface culling
			local v1 = verts[v1_idx]
			local v2 = verts[v2_idx]
			local v3 = verts[v3_idx]

			-- Transform vertices to camera space for view-space culling
			local function to_camera_space(v)
				local x = v.x + (offset_x or 0) - camera.x
				local y = v.y + (offset_y or 0) - camera.y
				local z = v.z + (offset_z or 0) - camera.z

				-- Rotate around Y axis
				local x2 = x * cos(camera.ry) - z * sin(camera.ry)
				local z2 = x * sin(camera.ry) + z * cos(camera.ry)

				-- Rotate around X axis
				local y2 = y * cos(camera.rx) - z2 * sin(camera.rx)
				local z3 = y * sin(camera.rx) + z2 * cos(camera.rx)

				return vec(x2, y2, z3 + cam_dist)
			end

			local cv1 = to_camera_space(v1)
			local cv2 = to_camera_space(v2)
			local cv3 = to_camera_space(v3)

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
	-- Update FPS counter
	fps_counter += 1
	fps_timer += 1/60
	if fps_timer >= 1.0 then
		current_fps = fps_counter
		fps_counter = 0
		fps_timer = 0
	end

	-- Rotate with Z and X (slower)
	local rot_speed = 0.005
	if btn(4) then  -- Z button
		camera.ry -= rot_speed
	end
	if btn(5) then  -- X button
		camera.ry += rot_speed
	end

	-- Move camera with arrow keys (forward/back/strafe)
	local move_speed = 0.05
	if btn(2) then  -- Up - move forward
		camera.z += move_speed * cos(camera.ry)
		camera.x += move_speed * sin(camera.ry)
	end
	if btn(3) then  -- Down - move backward
		camera.z -= move_speed * cos(camera.ry)
		camera.x -= move_speed * sin(camera.ry)
	end
	if btn(0) then  -- Left - strafe left
		camera.x += move_speed * cos(camera.ry)
		camera.z -= move_speed * sin(camera.ry)
	end
	if btn(1) then  -- Right - strafe right
		camera.x -= move_speed * cos(camera.ry)
		camera.z += move_speed * sin(camera.ry)
	end

	-- Vertical movement with W and S
	if key("w") then  -- W - move up
		camera.y += move_speed
	end
	if key("s") then  -- S - move down
		camera.y -= move_speed
	end
end

function _draw()
	cls(0)

	-- Collect all faces from all meshes
	local all_faces = {}

	-- Render ground plane (with is_ground flag for depth bias)
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

	-- Get sphere faces (floating above the city)
	local sphere_sorted = render_mesh(sphere_verts, sphere_faces, 0, 5, 0)
	for _, f in ipairs(sphere_sorted) do
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

	-- Draw all faces in sorted order
	for _, f in ipairs(all_faces) do
		local face = f.face
		local sprite_id = face[4]
		local uv1 = face[5] or vec(0,0)
		local uv2 = face[6] or vec(16,0)
		local uv3 = face[7] or vec(16,16)

		-- Build vert_data matrix (6x3: xyzwuv for each vertex)
		local vert_data = userdata("f64",6,3)
		-- Vertex 1
		vert_data[0], vert_data[1], vert_data[2], vert_data[3], vert_data[4], vert_data[5] =
			f.p1.x, f.p1.y, 0, f.p1.w, uv1.x, uv1.y
		-- Vertex 2
		vert_data[6], vert_data[7], vert_data[8], vert_data[9], vert_data[10], vert_data[11] =
			f.p2.x, f.p2.y, 0, f.p2.w, uv2.x, uv2.y
		-- Vertex 3
		vert_data[12], vert_data[13], vert_data[14], vert_data[15], vert_data[16], vert_data[17] =
			f.p3.x, f.p3.y, 0, f.p3.w, uv3.x, uv3.y

		textri({tex = sprite_id}, vert_data, 270)
	end

	-- Performance info
	local cpu = stat(1) * 100
	print("FPS: "..current_fps, 2, 2, 11)
	print("CPU: "..flr(cpu).."%", 2, 10, 11)
	print("Tris: "..#all_faces, 2, 18, 11)
	print("Z/X: Rotate  Arrows: Move  W/S: Up/Down", 2, 262, 7)
end
