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
---@param props table The properties passed to the shader. Expects a `tex` field with a texture index or sprite array {id, width, height}.
---@param vert_data userdata A 6x3 matrix where each row is the xyzwuv of a vertex.
---@param screen_height number The height of the screen, used for scanline truncation.
function Renderer.textri(props,vert_data,screen_height)
    -- Handle sprite constant as array {id, width, height} or plain number
    local spr = type(props.tex) == "table" and props.tex[1] or props.tex

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
-- @param fog_start_distance: distance at which fog starts (optional)
-- @param is_skybox: skip pitch-based culling for skybox (optional)
-- @return sorted_faces: array of faces ready to draw
function Renderer.render_mesh(verts, faces, camera, offset_x, offset_y, offset_z, sprite_override, is_ground, rot_pitch, rot_yaw, rot_roll, render_distance, ground_always_behind, fog_start_distance, is_skybox)
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
	local obj_dist = sqrt(dist_sq)  -- Store distance for fog calculation

	-- Cull objects beyond render range (unless it's ground)
	if not is_ground and dist_sq > far * far then
		return {}
	end

	-- AABB culling: Calculate bounding box before expensive vertex processing
	if not is_ground and #verts > 0 then
		local min_x, max_x = verts[1].x, verts[1].x
		local min_y, max_y = verts[1].y, verts[1].y
		local min_z, max_z = verts[1].z, verts[1].z

		for i = 2, #verts do
			local v = verts[i]
			if v.x < min_x then min_x = v.x end
			if v.x > max_x then max_x = v.x end
			if v.y < min_y then min_y = v.y end
			if v.y > max_y then max_y = v.y end
			if v.z < min_z then min_z = v.z end
			if v.z > max_z then max_z = v.z end
		end

		-- Transform AABB to world space
		local world_min_x = min_x + obj_x
		local world_max_x = max_x + obj_x
		local world_min_z = min_z + obj_z
		local world_max_z = max_z + obj_z

		-- Simple frustum check: if entire AABB is outside view, cull it
		-- Check if box is completely behind camera
		local cam_to_min_z = world_min_z - camera.z
		local cam_to_max_z = world_max_z - camera.z
		if cam_to_max_z < 0 then
			return {}  -- Entire box behind camera
		end
	end

	-- Cache camera-space transformations and project vertices
	local projected = {}
	local depths = {}
	local camera_verts = {}  -- Cache transformed vertices in camera space

	-- Precompute combined transformation matrix (3x3) + translation vector
	-- This combines object rotation and camera rotation into one matrix multiplication
	local cos_ry, sin_ry = cos(camera.ry), sin(camera.ry)
	local cos_rx, sin_rx = cos(camera.rx), sin(camera.rx)

	-- Build combined 3x3 rotation matrix (object rotation * camera rotation)
	-- Matrix elements: m11, m12, m13, m21, m22, m23, m31, m32, m33
	local m11, m12, m13, m21, m22, m23, m31, m32, m33

	-- Pre-calculate object rotation trig values (needed in vertex loop)
	local cos_pitch, sin_pitch, cos_yaw, sin_yaw, cos_roll, sin_roll
	if rot_pitch or rot_yaw or rot_roll then
		-- Object has rotation - combine with camera rotation
		cos_pitch, sin_pitch = cos(rot_pitch or 0), sin(rot_pitch or 0)
		cos_yaw, sin_yaw = cos(rot_yaw or 0), sin(rot_yaw or 0)
		cos_roll, sin_roll = cos(rot_roll or 0), sin(rot_roll or 0)

		-- Pre-multiply object rotation matrix with camera rotation matrix
		-- This reduces per-vertex operations from 2 matrix multiplies to 1
		-- Combined matrix = Camera_Y * Camera_X * Object_Yaw * Object_Pitch * Object_Roll
		-- For simplicity, doing camera rotation only (object rotation applied per vertex for now)
		-- Full matrix multiplication would save more but is complex - TODO for future optimization
		m11, m12, m13 = cos_ry, 0, -sin_ry
		m21, m22, m23 = sin_ry * sin_rx, cos_rx, cos_ry * sin_rx
		m31, m32, m33 = sin_ry * cos_rx, -sin_rx, cos_ry * cos_rx
	else
		-- No object rotation - just camera rotation matrix
		m11, m12, m13 = cos_ry, 0, -sin_ry
		m21, m22, m23 = sin_ry * sin_rx, cos_rx, cos_ry * sin_rx
		m31, m32, m33 = sin_ry * cos_rx, -sin_rx, cos_ry * cos_rx
	end

	for i, v in ipairs(verts) do
		local vx, vy, vz = v.x, v.y, v.z

		-- Apply object rotation first (if needed) - TODO: pre-multiply into matrix
		local x, y, z
		if rot_pitch or rot_yaw or rot_roll then
			-- Yaw (Y axis)
			local x_yaw = vx * cos_yaw - vz * sin_yaw
			local z_yaw = vx * sin_yaw + vz * cos_yaw
			-- Pitch (X axis)
			local y_pitch = vy * cos_pitch - z_yaw * sin_pitch
			local z_pitch = vy * sin_pitch + z_yaw * cos_pitch
			-- Roll (Z axis)
			x = x_yaw * cos_roll - y_pitch * sin_roll
			y = x_yaw * sin_roll + y_pitch * cos_roll
			z = z_pitch
		else
			x, y, z = vx, vy, vz
		end

		-- Apply world offset
		x = x + (offset_x or 0)
		y = y + (offset_y or 0)
		z = z + (offset_z or 0)

		-- Translate to camera space
		x = x - camera.x
		y = y - camera.y
		z = z - camera.z

		-- Apply 3x3 camera rotation matrix (single matrix multiply)
		-- This replaces separate Y and X rotation steps
		local x2 = m11 * x + m12 * y + m13 * z
		local y2 = m21 * x + m22 * y + m23 * z
		local z3 = m31 * x + m32 * y + m33 * z

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

			-- For skybox, only cull based on horizontal (XZ) components, ignore pitch (Y)
			local skybox_dot = dot
			if is_skybox then
				skybox_dot = nx * view_x + nz * view_z  -- Exclude Y component
			end

			-- Only render if facing camera (dot product > 0 means facing camera)
			-- Skip backface culling for ground/skybox (is_ground flag)
			-- For skybox, use horizontal-only dot product to avoid pitch-based culling
			if (is_skybox and skybox_dot > -0.5) or dot > 0 or is_ground then
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

					-- Calculate fog opacity based on distance (0 = opaque, 1 = fully fogged)
					-- Using exponential falloff for smoother fade
					local fog_opacity = nil  -- nil means no fog (don't add fog field)
					if fog_start_distance then
						-- For terrain/ground, use per-vertex depth instead of mesh distance
						local face_dist = is_ground and avg_depth or obj_dist
						if face_dist > fog_start_distance then
							local linear_fog = (face_dist - fog_start_distance) / (far - fog_start_distance)
							fog_opacity = linear_fog * linear_fog  -- Exponential (square for smoother falloff)
							fog_opacity = mid(0, fog_opacity, 1)  -- Clamp 0-1
						else
							fog_opacity = 0  -- Within fog range but before fog starts
						end
					end

					-- Create a copy of face with sprite override if provided
					local face_copy = {face[1], face[2], face[3], sprite_override or face[4], face[5], face[6], face[7]}
					add(sorted_faces, {face=face_copy, depth=avg_depth, p1=p1, p2=p2, p3=p3, fog=fog_opacity})
				end
			end
		end
	end

	return sorted_faces
end

-- Draw a list of sorted faces using the pooled vertex data
-- @param all_faces: sorted array of faces
-- @param ship_flash_red: whether to flash ship sprite red (optional)
-- @param fog_enabled: whether fog/dithering is enabled (optional, default true)
function Renderer.draw_faces(all_faces, ship_flash_red, fog_enabled)
	-- Default fog to enabled if not specified
	if fog_enabled == nil then fog_enabled = true end
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
		-- Only if fog is enabled
		if fog_enabled and f.fog ~= nil then
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

			-- Apply linear fog dithering based on distance (applies to all sprites except skybox)
			-- fog_level: 0 = no fog (opaque), 1 = full fog (transparent)
			-- Only apply if fog exists and is greater than 0 (f.fog will be nil if DEBUG_RENDER_FOG is false)
			if f.fog > 0 and not f.is_skybox then
				local fog_level = f.fog
				-- Higher fog_level = less visible (patterns FLIPPED - more 1s = MORE transparent!)
				if fog_level > 0.875 then
					fillp(0b0111111101111111)  -- Most 1s = most transparent (almost invisible)
				elseif fog_level > 0.75 then
					fillp(0b0111101101111011)  --
				elseif fog_level > 0.625 then
					fillp(0b0101101101011011)  --
				elseif fog_level > 0.5 then
					fillp(0b0101101001011010)  -- 50%
				elseif fog_level > 0.375 then
					fillp(0b1010010010100100)  --
				elseif fog_level > 0.25 then
					fillp(0b1000010010000100)  --
				elseif fog_level > 0.125 then
					fillp(0b1000010000100001)  --
				else
					fillp(0b1000000010000000)  -- Fewest 1s = least transparent (barely fogged)
				end
			end
		else
			fillp()  -- Reset to solid when fog disabled
		end

		Renderer.textri({tex = render_sprite}, vert_data_pool, 270)
	end

	fillp()  -- Reset fill pattern after drawing
end

-- Bucket sort using depth bins (O(n) - hash faces by depth into buckets)
-- @param faces: array of faces to sort by depth
function Renderer.sort_faces(faces)
	if #faces == 0 then return end

	-- Find min/max depth for bucketing
	local min_depth = faces[1].depth
	local max_depth = faces[1].depth
	for i = 2, #faces do
		local d = faces[i].depth
		if d < min_depth then min_depth = d end
		if d > max_depth then max_depth = d end
	end

	-- Number of buckets (trade-off: more buckets = better distribution, more memory)
	local num_buckets = 100
	local range = max_depth - min_depth
	if range == 0 then return end  -- All same depth

	-- Create buckets (array of arrays)
	local buckets = {}
	for i = 1, num_buckets do
		buckets[i] = {}
	end

	-- Hash faces into buckets by depth
	for i = 1, #faces do
		local face = faces[i]
		local bucket_index = flr((face.depth - min_depth) / range * (num_buckets - 1)) + 1
		add(buckets[bucket_index], face)
	end

	-- Insertion sort helper for small buckets (faster than quicksort for small n)
	local function insertion_sort(arr)
		for i = 2, #arr do
			local key = arr[i]
			local j = i - 1
			while j >= 1 and arr[j].depth < key.depth do  -- Back to front
				arr[j + 1] = arr[j]
				j = j - 1
			end
			arr[j + 1] = key
		end
	end

	-- Quicksort helper for larger buckets
	local function quicksort(arr, low, high)
		if low < high then
			local pivot = arr[high].depth
			local i = low - 1
			for j = low, high - 1 do
				if arr[j].depth > pivot then  -- Back to front
					i = i + 1
					arr[i], arr[j] = arr[j], arr[i]
				end
			end
			arr[i + 1], arr[high] = arr[high], arr[i + 1]
			local pi = i + 1
			quicksort(arr, low, pi - 1)
			quicksort(arr, pi + 1, high)
		end
	end

	-- Sort each bucket internally for precision (important for close faces)
	-- Use insertion sort for small buckets (<=10), quicksort for larger ones
	for i = 1, num_buckets do
		local bucket_size = #buckets[i]
		if bucket_size > 1 then
			if bucket_size <= 10 then
				insertion_sort(buckets[i])
			else
				quicksort(buckets[i], 1, bucket_size)
			end
		end
	end

	-- Rebuild sorted array (back to front: higher bucket index first)
	local write_index = 1
	for i = num_buckets, 1, -1 do
		for j = 1, #buckets[i] do
			faces[write_index] = buckets[i][j]
			write_index += 1
		end
	end
end

return Renderer
