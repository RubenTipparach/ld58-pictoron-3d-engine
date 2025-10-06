-- Bullets module: Player and enemy projectiles
local Bullets = {}

-- Helper to create vectors (same as main.lua)
local function vec(x, y, z)
	return {x=x, y=y, z=z}
end

-- Bullet configuration (EASY TO ADJUST!)
Bullets.MAX_BULLETS = 100  -- Total bullet budget
Bullets.PLAYER_SPRITE = 25
Bullets.ENEMY_SPRITE = 26
Bullets.PLAYER_BULLET_SPEED = 10  -- Units per second
Bullets.ENEMY_BULLET_SPEED = 4  -- Units per second
Bullets.BULLET_SIZE = 0.2  -- Billboard size
Bullets.BULLET_RANGE = 100  -- 200 meters max range
Bullets.PLAYER_FIRE_RATE = 1  -- Bullets per second (0 = disabled)
Bullets.PLAYER_FIRE_COOLDOWN = Bullets.PLAYER_FIRE_RATE > 0 and (1 / Bullets.PLAYER_FIRE_RATE) or 999999

-- Enemy firing configuration (EASY TO ADJUST!)
Bullets.ENEMY_FIRE_RATE = 0  -- Bullets per second per enemy (0 = disabled)
Bullets.ENEMY_FIRE_COOLDOWN = Bullets.ENEMY_FIRE_RATE > 0 and (1 / Bullets.ENEMY_FIRE_RATE) or 999999

-- Active bullets
Bullets.bullets = {}
Bullets.player_fire_timer = 0

-- Spawn a bullet (internal function)
function Bullets.spawn(x, y, z, dir_x, dir_y, dir_z, sprite, owner, max_range, speed)
	-- Check bullet budget
	if #Bullets.bullets >= Bullets.MAX_BULLETS then
		return nil
	end

	local bullet = {
		x = x,
		y = y,
		z = z,
		vx = dir_x * speed,
		vy = dir_y * speed,
		vz = dir_z * speed,
		sprite = sprite,
		owner = owner,  -- "player" or "enemy"
		start_x = x,
		start_y = y,
		start_z = z,
		max_range = max_range or Bullets.BULLET_RANGE,
		active = true
	}

	add(Bullets.bullets, bullet)
	return bullet
end

-- Spawn player bullet (with rate limiting, faster speed)
function Bullets.spawn_player_bullet(x, y, z, dir_x, dir_y, dir_z, max_range)
	if Bullets.player_fire_timer > 0 then
		return nil  -- Still on cooldown
	end

	Bullets.player_fire_timer = Bullets.PLAYER_FIRE_COOLDOWN
	return Bullets.spawn(x, y, z, dir_x, dir_y, dir_z, Bullets.PLAYER_SPRITE, "player", max_range, Bullets.PLAYER_BULLET_SPEED)
end

-- Spawn enemy bullet (no rate limit, controlled by enemy fire rate, slower speed)
function Bullets.spawn_enemy_bullet(x, y, z, dir_x, dir_y, dir_z, max_range)
	return Bullets.spawn(x, y, z, dir_x, dir_y, dir_z, Bullets.ENEMY_SPRITE, "enemy", max_range, Bullets.ENEMY_BULLET_SPEED)
end

-- Update all bullets
function Bullets.update(delta_time)
	-- Update player fire cooldown
	if Bullets.player_fire_timer > 0 then
		Bullets.player_fire_timer -= delta_time
		if Bullets.player_fire_timer < 0 then
			Bullets.player_fire_timer = 0
		end
	end

	-- Update bullet positions
	for i = #Bullets.bullets, 1, -1 do
		local bullet = Bullets.bullets[i]

		if bullet.active then
			-- Move bullet (with delta_time for consistent speed)
			bullet.x += bullet.vx * delta_time
			bullet.y += bullet.vy * delta_time
			bullet.z += bullet.vz * delta_time

			-- Check range
			local dx = bullet.x - bullet.start_x
			local dy = bullet.y - bullet.start_y
			local dz = bullet.z - bullet.start_z
			local dist = sqrt(dx*dx + dy*dy + dz*dz)

			if dist > bullet.max_range then
				del(Bullets.bullets, bullet)
			end
		else
			del(Bullets.bullets, bullet)
		end
	end
end

-- Render bullets as camera-facing billboards (same logic as smoke particles)
function Bullets.render(render_mesh_func, camera)
	local all_bullet_faces = {}

	for bullet in all(Bullets.bullets) do
		if bullet.active then
			-- BILLBOARD MODE: Create camera-facing quad
			local half_size = Bullets.BULLET_SIZE

			-- Camera forward vector (direction camera is looking)
			local forward_x = sin(camera.ry) * cos(camera.rx)
			local forward_y = sin(camera.rx)
			local forward_z = cos(camera.ry) * cos(camera.rx)

			-- Camera right vector (perpendicular to forward, in XZ plane)
			local right_x = cos(camera.ry)
			local right_y = 0
			local right_z = -sin(camera.ry)

			-- Camera up vector (cross product of forward and right, inverted)
			local up_x = -(forward_y * right_z - forward_z * right_y)
			local up_y = -(forward_z * right_x - forward_x * right_z)
			local up_z = -(forward_x * right_y - forward_y * right_x)

			-- Build quad vertices using right and up vectors
			local billboard_verts = {
				vec(-right_x * half_size + up_x * half_size, -right_y * half_size + up_y * half_size, -right_z * half_size + up_z * half_size),  -- Top-left
				vec(right_x * half_size + up_x * half_size, right_y * half_size + up_y * half_size, right_z * half_size + up_z * half_size),    -- Top-right
				vec(right_x * half_size - up_x * half_size, right_y * half_size - up_y * half_size, right_z * half_size - up_z * half_size),    -- Bottom-right
				vec(-right_x * half_size - up_x * half_size, -right_y * half_size - up_y * half_size, -right_z * half_size - up_z * half_size),  -- Bottom-left
			}

			-- Billboard faces with proper UV coordinates (16x16 textures)
			local billboard_faces = {
				{1, 2, 3, bullet.sprite, vec(0,0), vec(16,0), vec(16,16)},
				{1, 3, 4, bullet.sprite, vec(0,0), vec(16,16), vec(0,16)}
			}

			-- Render billboard at bullet position
			local faces = render_mesh_func(billboard_verts, billboard_faces, bullet.x, bullet.y, bullet.z, nil, false)
			for _, f in ipairs(faces) do
				add(all_bullet_faces, f)
			end
		end
	end

	return all_bullet_faces
end

-- Check bullet collision with a bounding box
function Bullets.check_collision(owner_type, bounds)
	local hits = {}

	for i = #Bullets.bullets, 1, -1 do
		local bullet = Bullets.bullets[i]

		-- Only check bullets from the opposite owner
		if bullet.active and bullet.owner ~= owner_type then
			-- AABB collision check
			if bullet.x >= bounds.left and bullet.x <= bounds.right and
			   bullet.y >= bounds.bottom and bullet.y <= bounds.top and
			   bullet.z >= bounds.back and bullet.z <= bounds.front then
				add(hits, bullet)
				bullet.active = false  -- Mark for removal
				del(Bullets.bullets, bullet)
			end
		end
	end

	return hits
end

-- Reset bullets system
function Bullets.reset()
	Bullets.bullets = {}
	Bullets.player_fire_timer = 0
end

return Bullets
