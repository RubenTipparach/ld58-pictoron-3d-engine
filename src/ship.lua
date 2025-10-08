-- Ship module: VTOL vehicle with physics
local load_obj = include("engine/obj_loader.lua")
local Constants = include("src/constants.lua")

local Ship = {}
Ship.__index = Ship

-- Create a new ship instance
-- config: {
--   spawn_x, spawn_y, spawn_z, spawn_yaw: Initial position and rotation
--   mass, thrust, gravity, damping, angular_damping: Physics constants
--   max_health: Maximum health (default 100)
-- }
function Ship.new(config)
	local self = setmetatable({}, Ship)

	-- Position & rotation
	self.x = config.spawn_x
	self.y = config.spawn_y
	self.z = config.spawn_z
	self.pitch = 0
	self.yaw = config.spawn_yaw or 0
	self.roll = 0

	-- Velocity & angular velocity
	self.vx = 0
	self.vy = 0
	self.vz = 0
	self.vpitch = 0
	self.vyaw = 0
	self.vroll = 0

	-- Physics constants
	self.mass = config.mass or 30
	self.thrust = config.thrust or 0.002
	self.gravity = config.gravity or -0.005
	self.damping = config.damping or 0.95
	self.angular_damping = config.angular_damping or 0.85

	-- Health and damage
	self.max_health = config.max_health or 100
	self.health = self.max_health
	self.is_damaged = false

	-- Thrusters (will be populated after loading mesh)
	self.thrusters = {}

	-- Load mesh and create geometry
	self:load_mesh()

	return self
end

-- Load ship mesh from OBJ file
function Ship:load_mesh()
	local cross_lander_mesh = load_obj("ship_low_poly.obj")
	local flame_mesh = load_obj("flame.obj")

	-- Fallback to red cubes if OBJ loading fails
	if not cross_lander_mesh or #cross_lander_mesh.verts == 0 then
		cross_lander_mesh = {
			verts = {
				vec(-1.5, 0, -1.5), vec(1.5, 0, -1.5), vec(1.5, 0, 1.5), vec(-1.5, 0, 1.5),
				vec(-1.5, 3, -1.5), vec(1.5, 3, -1.5), vec(1.5, 3, 1.5), vec(-1.5, 3, 1.5)
			},
			faces = {
				{1, 2, 3, Constants.SPRITE_SHIP, vec(0,0), vec(16,0), vec(16,16)}, {1, 3, 4, Constants.SPRITE_SHIP, vec(0,0), vec(16,16), vec(0,16)},
				{5, 7, 6, Constants.SPRITE_SHIP, vec(0,0), vec(16,0), vec(16,16)}, {5, 8, 7, Constants.SPRITE_SHIP, vec(0,0), vec(16,16), vec(0,16)},
				{1, 5, 6, Constants.SPRITE_SHIP, vec(0,0), vec(16,0), vec(16,16)}, {1, 6, 2, Constants.SPRITE_SHIP, vec(0,0), vec(16,16), vec(0,16)},
				{3, 7, 8, Constants.SPRITE_SHIP, vec(0,0), vec(16,0), vec(16,16)}, {3, 8, 4, Constants.SPRITE_SHIP, vec(0,0), vec(16,16), vec(0,16)},
				{4, 8, 5, Constants.SPRITE_SHIP, vec(0,0), vec(16,0), vec(16,16)}, {4, 5, 1, Constants.SPRITE_SHIP, vec(0,0), vec(16,16), vec(0,16)},
				{2, 6, 7, Constants.SPRITE_SHIP, vec(0,0), vec(16,0), vec(16,16)}, {2, 7, 3, Constants.SPRITE_SHIP, vec(0,0), vec(16,16), vec(0,16)}
			}
		}
	end
	if not flame_mesh or #flame_mesh.verts == 0 then
		flame_mesh = {
			verts = {
				vec(-0.5, 0, -0.5), vec(0.5, 0, -0.5), vec(0.5, 0, 0.5), vec(-0.5, 0, 0.5),
				vec(-0.5, 1, -0.5), vec(0.5, 1, -0.5), vec(0.5, 1, 0.5), vec(-0.5, 1, 0.5)
			},
			faces = {
				{1, 2, 3, Constants.SPRITE_FLAME, vec(0,0), vec(16,0), vec(16,16)}, {1, 3, 4, Constants.SPRITE_FLAME, vec(0,0), vec(16,16), vec(0,16)},
				{5, 7, 6, Constants.SPRITE_FLAME, vec(0,0), vec(16,0), vec(16,16)}, {5, 8, 7, Constants.SPRITE_FLAME, vec(0,0), vec(16,16), vec(0,16)},
				{1, 5, 6, Constants.SPRITE_FLAME, vec(0,0), vec(16,0), vec(16,16)}, {1, 6, 2, Constants.SPRITE_FLAME, vec(0,0), vec(16,16), vec(0,16)},
				{3, 7, 8, Constants.SPRITE_FLAME, vec(0,0), vec(16,0), vec(16,16)}, {3, 8, 4, Constants.SPRITE_FLAME, vec(0,0), vec(16,16), vec(0,16)},
				{4, 8, 5, Constants.SPRITE_FLAME, vec(0,0), vec(16,0), vec(16,16)}, {4, 5, 1, Constants.SPRITE_FLAME, vec(0,0), vec(16,16), vec(0,16)},
				{2, 6, 7, Constants.SPRITE_FLAME, vec(0,0), vec(16,0), vec(16,16)}, {2, 7, 3, Constants.SPRITE_FLAME, vec(0,0), vec(16,16), vec(0,16)}
			}
		}
	end

	-- Scale down to fit the ship
	local model_scale = 0.15

	-- Create scaled vertices
	local verts = {}
	for _, v in ipairs(cross_lander_mesh.verts) do
		add(verts, vec(
			v.x * model_scale,
			v.y * model_scale,
			v.z * model_scale
		))
	end

	-- Assign ship texture (sprite 9) - 64x64 pixels, scale UVs accordingly
	local faces = {}
	for _, face in ipairs(cross_lander_mesh.faces) do
		local uv1 = {x = face[5].x * 4, y = face[5].y * 4}
		local uv2 = {x = face[6].x * 4, y = face[6].y * 4}
		local uv3 = {x = face[7].x * 4, y = face[7].y * 4}
		add(faces, {face[1], face[2], face[3], Constants.SPRITE_SHIP, uv1, uv2, uv3})
	end

	-- Engine positions (scaled from original model)
	local engine_positions = {
		{x = 6 * model_scale, y = -2 * model_scale, z = 0, key = "d"},  -- Right (D)
		{x = -6 * model_scale, y = -2 * model_scale, z = 0, key = "a"},  -- Left (A)
		{x = 0, y = -2 * model_scale, z = 6 * model_scale, key = "w"},  -- Front (W)
		{x = 0, y = -2 * model_scale, z = -6 * model_scale, key = "s"},  -- Back (S)
	}

	-- Add flame models at each engine position
	local flame_face_indices = {}
	local flame_base_verts = {}
	for i, engine in ipairs(engine_positions) do
		local flame_verts_start = #verts

		for _, v in ipairs(flame_mesh.verts) do
			add(verts, vec(
				v.x * model_scale + engine.x,
				v.y * model_scale + engine.y,
				v.z * model_scale + engine.z
			))
			-- Store base position for animation
			add(flame_base_verts, {
				base_x = v.x * model_scale + engine.x,
				base_y = v.y * model_scale + engine.y,
				base_z = v.z * model_scale + engine.z,
				offset_x = (v.x - 2.3394) * model_scale,
				offset_y = (v.y - 0.3126) * model_scale,
				offset_z = (v.z + 2.7187) * model_scale,
				engine_idx = i
			})
		end

		local faces_start = #faces + 1
		for _, face in ipairs(flame_mesh.faces) do
			add(faces, {
				face[1] + flame_verts_start,
				face[2] + flame_verts_start,
				face[3] + flame_verts_start,
				Constants.SPRITE_FLAME,
				face[5], face[6], face[7]
			})
		end
		local faces_end = #faces

		-- Track flame faces
		add(flame_face_indices, {start_idx = faces_start, end_idx = faces_end, thruster_idx = i})

		-- Add thruster to ship (for physics)
		add(self.thrusters, {x = engine.x, z = engine.z, key = engine.key, active = false})
	end

	-- Store mesh data
	self.verts = verts
	self.faces = faces
	self.flame_face_indices = flame_face_indices
	self.flame_base_verts = flame_base_verts
	self.num_ship_verts = #cross_lander_mesh.verts  -- For animation offset
end

-- Reset ship to spawn position
function Ship:reset(spawn_x, spawn_y, spawn_z, spawn_yaw)
	self.x = spawn_x
	self.y = spawn_y
	self.z = spawn_z
	self.pitch = 0
	self.yaw = spawn_yaw
	self.roll = 0
	self.vx = 0
	self.vy = 0
	self.vz = 0
	self.vpitch = 0
	self.vyaw = 0
	self.vroll = 0
	self.health = self.max_health
	self.is_damaged = false
end

-- Animate flame vertices (called each frame)
function Ship:animate_flames()
	local flame_time = time() * 6
	for i, base_vert in ipairs(self.flame_base_verts) do
		local base_flicker = sin(flame_time + base_vert.engine_idx * 2.5) * 0.03
		local noise = sin(flame_time * 3.7 + i * 0.5) * 0.015
		noise += sin(flame_time * 7.2 + i * 1.3) * 0.01
		local scale_mod = 1.0 + base_flicker + noise

		local vert_idx = self.num_ship_verts + i
		self.verts[vert_idx].x = base_vert.base_x + base_vert.offset_x * (scale_mod - 1.0)
		self.verts[vert_idx].y = base_vert.base_y + base_vert.offset_y * (scale_mod - 1.0) * 1.2
		self.verts[vert_idx].z = base_vert.base_z + base_vert.offset_z * (scale_mod - 1.0)
	end
end

-- Get faces to render (with flame filtering)
function Ship:get_render_faces(use_damage_sprite)
	local filtered_faces = {}
	for i, face in ipairs(self.faces) do
		local should_show = true

		-- Check if this face is a flame
		for _, flame_info in ipairs(self.flame_face_indices) do
			if i >= flame_info.start_idx and i <= flame_info.end_idx then
				should_show = self.thrusters[flame_info.thruster_idx].active
				break
			end
		end

		if should_show then
			local face_copy = {face[1], face[2], face[3], face[4], face[5], face[6], face[7]}
			if use_damage_sprite and face[4] == Constants.SPRITE_SHIP then
				face_copy[4] = Constants.SPRITE_SHIP_DAMAGE
			end
			add(filtered_faces, face_copy)
		end
	end
	return filtered_faces
end

-- Take damage
function Ship:take_damage(amount)
	self.health -= amount
	if self.health < 50 then
		self.is_damaged = true
	end
	sfx(8)  -- Play damage sound
end

return Ship
