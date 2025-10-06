-- Mission Scripts
-- Defines all mission scenarios

local LandingPads = include("src/landing_pads.lua")

local Missions = {}

-- Mission 1: Engine Test
-- Simple tutorial - take off, hover for duration, and land back on the pad
function Missions.start_mission_1(Mission)
	local pad_x, pad_y, pad_z, pad_yaw = LandingPads.get_spawn(1)
	pad_x = pad_x or 0
	pad_z = pad_z or 0
	Mission.start_hover_mission(Mission.M1_HOVER_DURATION, pad_x, pad_z)
	-- Update mission name
	Mission.mission_name = "Engine Test"
end

-- Mission 2: Cargo Delivery
-- Pick up cargo at specified distance and deliver to landing pad
function Missions.start_mission_2(Mission)
	local pad_x, pad_y, pad_z, pad_yaw = LandingPads.get_spawn(1)
	pad_x = pad_x or 0
	pad_z = pad_z or 0

	-- Create cargo boxes using parameters from Mission
	local cargo_list = {}
	for i = 1, Mission.M2_CARGO_COUNT do
		-- Convert world coords to Aseprite coords: aseprite = (world / 4) + 64
		local cargo_world_x = pad_x + Mission.M2_CARGO_DISTANCE_X
		local cargo_world_z = pad_z + Mission.M2_CARGO_DISTANCE_Z
		local cargo_aseprite_x = (cargo_world_x / 4) + 64
		local cargo_aseprite_z = (cargo_world_z / 4) + 64
		add(cargo_list, {aseprite_x = cargo_aseprite_x, aseprite_z = cargo_aseprite_z})
	end

	Mission.start_cargo_mission(cargo_list, pad_x, pad_z)
	-- Update mission name
	Mission.mission_name = "Cargo Delivery"
end

-- Start a mission by number
function Missions.start(mission_num, Mission)
	if mission_num == 1 then
		Missions.start_mission_1(Mission)
	elseif mission_num == 2 then
		Missions.start_mission_2(Mission)
	end
	-- Add more missions here as they're created
end

return Missions
