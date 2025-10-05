-- 3D Rendering Module
-- Handles projection, mesh rendering, and textured triangle drawing

local Renderer = {}

-- Scanline buffer for textured triangle rendering
local scanlines = userdata("f64",11,270)

-- Pre-allocate userdata pool to avoid allocations per triangle
local vert_data_pool = userdata("f64", 6, 3)

---Draws a 3D textured triangle to the screen. Note that the vertices need W components,
---and that they need to be the reciprocal of the W which is produced by the projection matrix.
---This step is typically done in the perspective division step.
---@param props table The properties passed to the shader. Expects a `tex` field with a texture index.
---@param vert_data userdata A 6x3 matrix where each row is the xyzwuv of a vertex.
---@param screen_height number The height of the screen, used for scanline truncation.
function Renderer.textri(props,vert_data,screen_height)
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

-- Project and render a mesh with proper culling and sorting
-- @param verts: array of vertices
-- @param faces: array of faces
-- @param camera: camera object with x,y,z,rx,ry
-- @param offset_x, offset_y, offset_z: world position offset
-- @param sprite_override: override sprite ID for all faces (optional)
-- @param is_ground: mark as ground for special depth sorting (optional)
-- @param rot_pitch, rot_yaw, rot_roll: object rotation (optional)
-- @param render_distance: far clipping plane distance
-- @param ground_always_behind: apply depth bias to ground (optional, default true)
-- @return sorted_faces: array of faces ready to draw
function Renderer.render_mesh(verts, faces, camera, offset_x, offset_y, offset_z, sprite_override, is_ground, rot_pitch, rot_yaw, rot_roll, render_distance, ground_always_behind)
	-- Projection parameters
	local fov = 70  -- Field of view
	local near = 0.01  -- Near clipping plane
	local far = render_distance or 20  -- Far clipping plane
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
		return {}
	end

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
			local py = y2 / z3 * (270 / tan_half_fov)

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
					-- Add depth bias for ground to ensure it renders behind everything (if enabled)
					if is_ground and (ground_always_behind == nil or ground_always_behind) then
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

-- Draw a list of sorted faces using the pooled vertex data
-- @param all_faces: sorted array of faces
-- @param ship_flash_red: whether to flash ship sprite red (optional)
function Renderer.draw_faces(all_faces, ship_flash_red)
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

		Renderer.textri({tex = render_sprite}, vert_data_pool, 270)
	end

	fillp()  -- Reset fill pattern after drawing
end

-- Sort faces using insertion sort (efficient for mostly sorted data)
-- @param faces: array of faces to sort by depth
function Renderer.sort_faces(faces)
	-- Sort all faces by depth (back to front - painter's algorithm)
	for i = 2, #faces do
		local key = faces[i]
		local j = i - 1
		-- Move elements that are closer than key to one position ahead
		while j >= 1 and faces[j].depth < key.depth do
			faces[j + 1] = faces[j]
			j = j - 1
		end
		faces[j + 1] = key
	end
end

return Renderer
