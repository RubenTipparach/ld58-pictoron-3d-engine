-- Sprite Constants (shared across all modules)
local Constants = {}

-- Sprite configuration: {id, width, height}
Constants.SPRITE_CUBE = {0, 32, 32}
Constants.SPRITE_SPHERE = {1, 32, 32}
Constants.SPRITE_GROUND = {14, 32, 32}  -- Terrain texture
Constants.SPRITE_FLAME = {3, 32, 32}
Constants.SPRITE_SMOKE = {5, 32, 32}
Constants.SPRITE_TREES = {6, 32, 32}
Constants.SPRITE_LANDING_PAD = {8, 32, 32}
Constants.SPRITE_SHIP = {9, 64, 64}
Constants.SPRITE_SHIP_DAMAGE = {10, 64, 64}
Constants.SPRITE_SKYBOX = {11, 32, 32}
Constants.SPRITE_WATER = {12, 32, 32}
Constants.SPRITE_WATER2 = {13, 32, 32}
Constants.SPRITE_GRASS = {15, 32, 32}  -- Grass texture for elevation 3+
Constants.SPRITE_ROCKS = {16, 32, 32}  -- Rock texture for elevation 10+
Constants.SPRITE_ROOFTOP = {17, 32, 32}  -- Building rooftop texture
Constants.SPRITE_BUILDING_SIDE = {18, 32, 32}  -- Building side texture - nine-sliced and tiled
Constants.SPRITE_BUILDING_SIDE_ALT = {19, 32, 32}  -- Alternate building side texture
Constants.SPRITE_CARGO = {20, 32, 32}  -- Cargo pickup object texture
Constants.SPRITE_PLANET = {21, 64, 32}  -- Planet texture for menu background
Constants.SPRITE_CLOUDS = {22, 64, 32}  -- Cloud layer texture for menu planet
Constants.SPRITE_HEIGHTMAP = {64, 128, 128}  -- Heightmap data source

-- Landing pad names
Constants.LANDING_PAD_NAMES = {
	[1] = "Landing Pad A",
	[2] = "Landing Pad B",
	[3] = "Landing Pad C",
	[4] = "Landing Pad D",
	[5] = "Landing Pad E (Debug)"
}

-- Coordinate conversion utilities
-- Convert Aseprite tilemap coordinates to world coordinates
-- Aseprite: (0,0) = top-left, (128,128) = bottom-right, (64,64) = center
-- World: Center at (0,0), 1 tile = 4 world units
function Constants.aseprite_to_world(aseprite_x, aseprite_z)
	return (aseprite_x - 64) * 4, (aseprite_z - 64) * 4
end

-- Convert world coordinates to Aseprite tilemap coordinates
function Constants.world_to_aseprite(world_x, world_z)
	return (world_x / 4) + 64, (world_z / 4) + 64
end

-- Building names
Constants.BUILDING_NAMES = {
	"Warehouse Alpha",
	"Cargo Depot",
	"Storage Facility",
	"Industrial Complex",
	"Distribution Center",
	"Logistics Hub",
	"Supply Station",
	"Freight Terminal",
	"Operations Center",
	"Command Tower"
}

return Constants
