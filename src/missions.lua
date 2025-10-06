-- Mission Scripts
-- Defines all mission scenarios

local LandingPads = include("src/landing_pads.lua")
local Constants = include("src/constants.lua")

local Missions = {}

-- Reference to buildings array (set externally from main.lua)
Missions.buildings = nil
Missions.building_configs = nil
Missions.Weather = nil  -- Reference to Weather module (set externally from main.lua)

-- Mission 1: Engine Test
-- Simple tutorial - take off, hover for duration, and land back on the pad
function Missions.start_mission_1(Mission)
	-- Get Landing Pad A actual position (not spawn position)
	local target_pad = LandingPads.get_pad(1)
	local pad_x = target_pad and target_pad.x or 0
	local pad_z = target_pad and target_pad.z or 0
	Mission.start_hover_mission(Mission.M1_HOVER_DURATION, pad_x, pad_z, 1)  -- Landing Pad A (ID 1)
	-- Update mission name
	Mission.mission_name = "Engine Test"
end

-- Mission 2: Cargo Delivery
-- Pick up cargo at specified distance and deliver to landing pad
function Missions.start_mission_2(Mission)
	-- Get Landing Pad A actual position (not spawn position)
	local target_pad = LandingPads.get_pad(1)
	local pad_x = target_pad and target_pad.x or 0
	local pad_z = target_pad and target_pad.z or 0

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

	Mission.start_cargo_mission(cargo_list, pad_x, pad_z, 1)  -- Landing Pad A (ID 1)
	-- Update mission name
	Mission.mission_name = "Cargo Delivery"
end

-- Mission 3: Scientific Mission
-- Pick up scientists from Command Tower rooftop and deliver to Landing Pad D for crater expedition
function Missions.start_mission_3(Mission)
	-- Get Landing Pad D actual position (not spawn position)
	local target_pad = LandingPads.get_pad(Mission.M3_LANDING_PAD_ID)
	local pad_x = target_pad and target_pad.x or 0
	local pad_z = target_pad and target_pad.z or 0

	-- Get Command Tower building position (building ID 10)
	local building_config = Missions.building_configs and Missions.building_configs[Mission.M3_BUILDING_ID]
	local building = Missions.buildings and Missions.buildings[Mission.M3_BUILDING_ID]

	if not building_config or not building then
		-- Fallback: use default position if buildings not available
		building_config = {x = 2, z = 20, height = 7}
		building = {x = 2, y = 0, z = 20}
	end

	-- Create cargo on rooftop of Command Tower
	-- Cargo should be at building center, on top of the roof
	local rooftop_height = building.y + (building_config.height * 2)  -- Height is scaled by 2
	local cargo_world_x = building_config.x
	local cargo_world_z = building_config.z

	-- Convert world coords to Aseprite coords
	local cargo_list = {}
	for i = 1, Mission.M3_CARGO_COUNT do
		local cargo_aseprite_x, cargo_aseprite_z = Constants.world_to_aseprite(cargo_world_x, cargo_world_z)
		add(cargo_list, {
			aseprite_x = cargo_aseprite_x,
			aseprite_z = cargo_aseprite_z,
			world_y = rooftop_height  -- Place on rooftop
		})
	end

	Mission.start_cargo_mission(cargo_list, pad_x, pad_z, Mission.M3_LANDING_PAD_ID)
	-- Update mission name and objectives
	Mission.mission_name = "Scientific Mission"
	Mission.current_objectives[1] = "Pick up scientists from Command Tower rooftop"
	Mission.current_objectives[3] = "Deliver to Landing Pad D (Crater Mission)"
end

-- Mission 4: Ocean Rescue
-- Pick up cargo from the ocean and deliver to Landing Pad B
function Missions.start_mission_4(Mission)
	-- Get Landing Pad B actual position (not spawn position)
	local target_pad = Mission.LandingPads.get_pad(Mission.M4_LANDING_PAD_ID)
	local pad_x = target_pad.x
	local pad_z = target_pad.z

	-- Create cargo at ocean location (Aseprite coords)
	local cargo_list = {}
	for i = 1, Mission.M4_CARGO_COUNT do
		add(cargo_list, {
			aseprite_x = Mission.M4_CARGO_ASEPRITE_X,
			aseprite_z = Mission.M4_CARGO_ASEPRITE_Z,
			world_y = 0  -- Float at sea level
		})
	end

	Mission.start_cargo_mission(cargo_list, pad_x, pad_z, Mission.M4_LANDING_PAD_ID)
	-- Update mission name and objectives
	Mission.mission_name = "Ocean Rescue"
	Mission.current_objectives[1] = "Rescue cargo from the ocean"
	Mission.current_objectives[3] = "Deliver to Landing Pad B"
end

-- Mission 5: Secret Weapon
-- Pick up secret cargo and deliver to Landing Pad C
function Missions.start_mission_5(Mission)
	-- Get Landing Pad C actual position (not spawn position)
	local target_pad = Mission.LandingPads.get_pad(Mission.M5_LANDING_PAD_ID)
	local pad_x = target_pad.x
	local pad_z = target_pad.z

	-- Create cargo at secret location (Aseprite coords)
	local cargo_list = {}
	for i = 1, Mission.M5_CARGO_COUNT do
		add(cargo_list, {
			aseprite_x = Mission.M5_CARGO_ASEPRITE_X,
			aseprite_z = Mission.M5_CARGO_ASEPRITE_Z
		})
	end

	Mission.start_cargo_mission(cargo_list, pad_x, pad_z, Mission.M5_LANDING_PAD_ID)
	-- Update mission name and objectives
	Mission.mission_name = "Secret Weapon"
	Mission.current_objectives[1] = "Retrieve classified cargo"
	Mission.current_objectives[3] = "Deliver to Landing Pad C"

	-- Enable weather for Mission 5
	if Missions.Weather then
		Missions.Weather.set_enabled(true)
		Missions.Weather.init()
	end
end

-- Mission 6: Alien Invasion
-- Combat mission - defend against alien waves
function Missions.start_mission_6(Mission)
	Mission.mission_name = "Alien Invasion"
	Mission.active = true
	Mission.complete_flag = false  -- Not complete yet
	Mission.current_objectives = {
		"Destroy all alien waves"
	}

	-- Set landing pad for reference (Landing Pad A)
	local target_pad = Mission.LandingPads.get_pad(1)
	if target_pad then
		Mission.landing_pad_pos = {x = target_pad.x, y = 0, z = target_pad.z}
	end
end

function Missions.start(mission_num, Mission)
	if mission_num == 1 then
		Missions.start_mission_1(Mission)
	elseif mission_num == 2 then
		Missions.start_mission_2(Mission)
	elseif mission_num == 3 then
		Missions.start_mission_3(Mission)
	elseif mission_num == 4 then
		Missions.start_mission_4(Mission)
	elseif mission_num == 5 then
		Missions.start_mission_5(Mission)
	elseif mission_num == 6 then
		Missions.start_mission_6(Mission)
	end
end

return Missions
