-- Sprite Constants (shared across all modules)
local Constants = {}

-- Sprite indices
Constants.SPRITE_CUBE = 0
Constants.SPRITE_SPHERE = 1
Constants.SPRITE_GROUND = 14  -- Terrain texture (32x32)
Constants.SPRITE_FLAME = 3
Constants.SPRITE_SMOKE = 5
Constants.SPRITE_TREES = 6
Constants.SPRITE_LANDING_PAD = 8
Constants.SPRITE_SHIP = 9
Constants.SPRITE_SHIP_DAMAGE = 10
Constants.SPRITE_SKYBOX = 11
Constants.SPRITE_WATER = 12
Constants.SPRITE_WATER2 = 13
Constants.SPRITE_GRASS = 15  -- Grass texture for elevation 3+ (32x32)
Constants.SPRITE_ROCKS = 16  -- Rock texture for elevation 10+ (32x32)
Constants.SPRITE_ROOFTOP = 17  -- Building rooftop texture (32x32)
Constants.SPRITE_BUILDING_SIDE = 18  -- Building side texture - nine-sliced and tiled (32x32)
Constants.SPRITE_BUILDING_SIDE_ALT = 19  -- Alternate building side texture (32x32)
Constants.SPRITE_CARGO = 20  -- Cargo pickup object texture (32x32)
Constants.SPRITE_PLANET = 21  -- Planet texture for menu background (64x32)
Constants.SPRITE_CLOUDS = 22  -- Cloud layer texture for menu planet (64x32)
Constants.SPRITE_HEIGHTMAP = 64  -- Heightmap data source (128x128)

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
