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
Bullets.BULLET_SPEED = 0.5  -- Units per frame (slower for dodging)
Bullets.BULLET_SIZE = 0.2  -- Billboard size
Bullets.PLAYER_FIRE_RATE = 1  -- Bullets per second
Bullets.PLAYER_FIRE_COOLDOWN = 1 / Bullets.PLAYER_FIRE_RATE

-- Enemy firing configuration (EASY TO ADJUST!)
Bullets.ENEMY_FIRE_RATE = 0.5  -- Bullets per second per enemy
Bullets.ENEMY_FIRE_COOLDOWN = 1 / Bullets.ENEMY_FIRE_RATE

-- Active bullets
Bullets.bullets = {}
Bullets.player_fire_timer = 0

-- Spawn a bullet
function Bullets.spawn(x, y, z, dir_x, dir_y, dir_z, sprite, owner, max_range)
	-- Check bullet budget
	if #Bullets.bullets >= Bullets.MAX_BULLETS then
		return nil
	end

	local bullet = {
		x = x,
		y = y,
		z = z,
		vx = dir_x * Bullets.BULLET_SPEED,
		vy = dir_y * Bullets.BULLET_SPEED,
		vz = dir_z * Bullets.BULLET_SPEED,
		sprite = sprite,
		owner = owner,  -- "player" or "enemy"
		start_x = x,
		start_y = y,
		start_z = z,
		max_range = max_range or 20,
		active = true
	}

	add(Bullets.bullets, bullet)
	return bullet
end

-- Spawn player bullet (with rate limiting)
function Bullets.spawn_player_bullet(x, y, z, dir_x, dir_y, dir_z, max_range)
	if Bullets.player_fire_timer > 0 then
		return nil  -- Still on cooldown
	end

	Bullets.player_fire_timer = Bullets.PLAYER_FIRE_COOLDOWN
	return Bullets.spawn(x, y, z, dir_x, dir_y, dir_z, Bullets.PLAYER_SPRITE, "player", max_range)
end

-- Spawn enemy bullet (no rate limit, controlled by enemy fire rate)
function Bullets.spawn_enemy_bullet(x, y, z, dir_x, dir_y, dir_z, max_range)
	return Bullets.spawn(x, y, z, dir_x, dir_y, dir_z, Bullets.ENEMY_SPRITE, "enemy", max_range)
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
			-- Move bullet
			bullet.x += bullet.vx
			bullet.y += bullet.vy
			bullet.z += bullet.vz

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

-- Render bullets as billboards (like smoke particles)
function Bullets.render(render_mesh_func, camera)
	local all_bullet_faces = {}

	for bullet in all(Bullets.bullets) do
		if bullet.active then
			-- Create billboard quad
			local size = Bullets.BULLET_SIZE
			local bullet_verts = {
				vec(-size, -size, 0),
				vec(size, -size, 0),
				vec(size, size, 0),
				vec(-size, size, 0)
			}

			local bullet_faces = {
				{1, 2, 3, bullet.sprite},
				{1, 3, 4, bullet.sprite}
			}

			-- Render billboard at bullet position
			local faces = render_mesh_func(bullet_verts, bullet_faces, bullet.x, bullet.y, bullet.z, nil, false)
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
