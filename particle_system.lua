-- Particle System Module
-- Handles creation, updating, and rendering of 3D particles

local ParticleSystem = {}
ParticleSystem.__index = ParticleSystem

-- Create a new particle system
function ParticleSystem.new(config)
	local self = setmetatable({}, ParticleSystem)

	-- Configuration
	self.particle_size = config.size or 0.16
	self.max_particles = config.max_particles or 4
	self.particle_lifetime = config.lifetime or 2.0
	self.spawn_rate = config.spawn_rate or 0.3
	self.sprite_id = config.sprite_id or 5
	self.scale_growth = config.scale_growth or 1.5  -- How much to grow over lifetime

	-- State
	self.particles = {}
	self.spawn_timer = 0

	-- Base vertices for a diamond particle (will be scaled/rotated per instance)
	self.base_verts = {
		vec(0, self.particle_size, 0),    -- Top
		vec(0, -self.particle_size, 0),   -- Bottom
		vec(self.particle_size, 0, 0),    -- Right
		vec(-self.particle_size, 0, 0),   -- Left
		vec(0, 0, self.particle_size),    -- Front
		vec(0, 0, -self.particle_size),   -- Back
	}

	-- Initialize particle pool
	for i = 1, self.max_particles do
		add(self.particles, {
			active = false,
			life = 0,
			x = 0, y = 0, z = 0,
			vx = 0, vy = 0, vz = 0,
			rot_x = 0, rot_y = 0, rot_z = 0,
			vrot_x = 0, vrot_y = 0, vrot_z = 0
		})
	end

	return self
end

-- Spawn a new particle at a given position with initial velocity
function ParticleSystem:spawn(x, y, z, vx, vy, vz, config)
	config = config or {}

	-- Find inactive particle slot
	for particle in all(self.particles) do
		if not particle.active then
			particle.active = true
			particle.life = 0
			particle.x = x
			particle.y = y
			particle.z = z

			-- Set velocity (inherit + random offset)
			local random_vx = config.random_vx or ((rnd(2) - 1) * 0.02)
			local random_vy = config.random_vy or (rnd(0.03) + 0.01)
			local random_vz = config.random_vz or ((rnd(2) - 1) * 0.02)

			particle.vx = (vx or 0) + random_vx
			particle.vy = (vy or 0) + random_vy
			particle.vz = (vz or 0) + random_vz

			-- No rotation for smoke
			particle.rot_x = 0
			particle.rot_y = 0
			particle.rot_z = 0
			particle.vrot_x = 0
			particle.vrot_y = 0
			particle.vrot_z = 0

			return true
		end
	end

	return false  -- No available slots
end

-- Update all active particles
function ParticleSystem:update(dt)
	for particle in all(self.particles) do
		if particle.active then
			particle.life += dt

			-- Update position
			particle.x += particle.vx
			particle.y += particle.vy
			particle.z += particle.vz

			-- No rotation update for smoke

			-- Apply drag
			particle.vx *= 0.98
			particle.vy *= 0.98
			particle.vz *= 0.98

			-- Deactivate particle when it expires
			if particle.life >= self.particle_lifetime then
				particle.active = false
			end
		end
	end
end

-- Render all active particles (returns faces to add to render queue)
function ParticleSystem:render(render_mesh_func)
	local all_particle_faces = {}

	for particle in all(self.particles) do
		if particle.active then
			local life_progress = particle.life / self.particle_lifetime

			-- Scale grows over lifetime
			local scale = 1.0 + life_progress * self.scale_growth

			-- Opacity grows from 25% to 100% over lifetime (starts at 75% transparent)
			local opacity = 0.25 + (life_progress * 0.75)

			if opacity > 0 then
				-- Create temporary vertices for this particle with scale only (no rotation)
				local particle_verts = {}

				for _, base_v in ipairs(self.base_verts) do
					local x, y, z = base_v.x * scale, base_v.y * scale, base_v.z * scale
					add(particle_verts, vec(x, y, z))
				end

				-- Create faces for the diamond (8 triangular faces)
				local diamond_faces = {
					{1, 3, 5, self.sprite_id, vec(0,0), vec(16,0), vec(16,16)},  -- Top-Right-Front
					{1, 5, 4, self.sprite_id, vec(0,0), vec(16,0), vec(16,16)},  -- Top-Front-Left
					{1, 4, 6, self.sprite_id, vec(0,0), vec(16,0), vec(16,16)},  -- Top-Left-Back
					{1, 6, 3, self.sprite_id, vec(0,0), vec(16,0), vec(16,16)},  -- Top-Back-Right
					{2, 5, 3, self.sprite_id, vec(0,0), vec(16,0), vec(16,16)},  -- Bottom-Front-Right
					{2, 4, 5, self.sprite_id, vec(0,0), vec(16,0), vec(16,16)},  -- Bottom-Left-Front
					{2, 6, 4, self.sprite_id, vec(0,0), vec(16,0), vec(16,16)},  -- Bottom-Back-Left
					{2, 3, 6, self.sprite_id, vec(0,0), vec(16,0), vec(16,16)},  -- Bottom-Right-Back
				}

				-- Render particle at its world position
				local particle_sorted = render_mesh_func(
					particle_verts,
					diamond_faces,
					particle.x,
					particle.y,
					particle.z
				)

				-- Add opacity information to each face
				for _, f in ipairs(particle_sorted) do
					f.opacity = opacity  -- Store opacity for graduated dithering
					add(all_particle_faces, f)
				end
			end
		end
	end

	return all_particle_faces
end

-- Get count of active particles
function ParticleSystem:get_active_count()
	local count = 0
	for particle in all(self.particles) do
		if particle.active then
			count += 1
		end
	end
	return count
end

return ParticleSystem
