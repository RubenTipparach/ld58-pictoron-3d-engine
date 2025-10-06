-- Cutscene Module
-- Displays story scenes with sprites and text

local Cutscene = {}

-- Configuration
Cutscene.TEXT_COLOR = 7  -- White
Cutscene.SHADOW_COLOR = 0  -- Black
Cutscene.BG_COLOR = 0  -- Black background
Cutscene.TEXT_Y_START = 160  -- Y position where text starts
Cutscene.LINE_HEIGHT = 10  -- Height between lines
Cutscene.TEXT_SPEED = 0.025  -- Seconds per character (2x faster)
Cutscene.SPRITE_X = (480 - 256) / 2 - 80 -- Center sprite horizontally (256px on 480px screen)
Cutscene.SPRITE_Y = 10
Cutscene.SPRITE_WIDTH = 256  -- Sprite width
Cutscene.SPRITE_HEIGHT = 128  -- Sprite height

-- Story scenes
Cutscene.scenes = {
	{
		sprite = 66,
		text = {
			"Tom Lander, having recently reclaimed his throne,",
			"is now king of the moon."
		}
	},
	{
		sprite = 67,
		text = {
			"Little did he know the Barons placed a sleeper cell",
			"on the Alien planet Gradix. They became mindless",
			"terrorists who blew up cities and government officials",
			"in the name of Tom Lander, framing him for countless",
			"murders."
		}
	},
	{
		sprite = 68,
		text = {
			"The Gradixians got pissed, and invaded the moon.",
			"They showed up with a giant spaceship and blew up",
			"everything. The Moon kingdom evacuated and spread out",
			"across the galaxy. Tom was stripped of his title,",
			"escaped and lived in the outer worlds as an anonymous",
			"blue collar worker. His amazing lander skills landed",
			"him as the Ace Lander Pilot of the Shimigu Mining",
			"industry."
		}
	},
	{
		sprite = 69,
		text = {
			"One day, they received a message from the Gradixians.",
			"They are still pissed at Tom Lander, and demand they",
			"hand him over. The Shimigu board said \"Fuck that!\",",
			"and decided that it was worth defending Tom and his",
			"Lander."
		}
	},
	{
		sprite = 70,
		text = {
			"They have 10 days to prepare before the Gradixians",
			"arrive. Tom must build up his fortress, by doing what",
			"he does best. Pick up valuable resources and land them",
			"in Texius city. The brilliant builders will build up",
			"the fort and fight back the invaders."
		}
	}
}

-- Current state
Cutscene.active = false
Cutscene.current_scene = 1
Cutscene.char_timer = 0
Cutscene.chars_shown = 0
Cutscene.scene_complete = false
Cutscene.skip_used_this_frame = false
Cutscene.default_sfx_addr = nil  -- Store default sfx address to restore later

-- Initialize cutscene
function Cutscene.start(scene_num, intro_addr)
	Cutscene.active = true
	Cutscene.current_scene = scene_num or 1
	Cutscene.char_timer = 0
	Cutscene.chars_shown = 0
	Cutscene.scene_complete = false

	-- Play intro music from custom base address
	if intro_addr then
		music(0, nil, nil, intro_addr)  -- Play pattern 0 from intro_addr
	end
end

-- Stop cutscene
function Cutscene.stop()
	Cutscene.active = false
	-- Stop music when cutscene ends
	music(-1)
end

-- Update cutscene (text reveal animation)
function Cutscene.update(delta_time)
	if not Cutscene.active then return end

	-- Reset skip flag at start of update
	Cutscene.skip_used_this_frame = false

	local scene = Cutscene.scenes[Cutscene.current_scene]
	if not scene then
		Cutscene.stop()
		return
	end

	-- Calculate total characters in all lines
	local total_chars = 0
	for _, line in ipairs(scene.text) do
		total_chars += #line
	end

	-- Check if Z or Space is pressed to skip teletype
	if (keyp("z") or keyp("space")) and Cutscene.chars_shown < total_chars then
		-- Show all text immediately
		Cutscene.chars_shown = total_chars
		Cutscene.scene_complete = true
		Cutscene.skip_used_this_frame = true  -- Mark that we used the key press
	end

	-- Reveal characters over time
	if Cutscene.chars_shown < total_chars then
		Cutscene.char_timer += delta_time
		if Cutscene.char_timer >= Cutscene.TEXT_SPEED then
			Cutscene.chars_shown += 1
			Cutscene.char_timer = 0
		end
	else
		Cutscene.scene_complete = true
	end
end

-- Draw cutscene
function Cutscene.draw()
	if not Cutscene.active then return end

	local scene = Cutscene.scenes[Cutscene.current_scene]
	if not scene then return end

	-- Black background
	rectfill(0, 0, 480, 270, Cutscene.BG_COLOR)

	-- Draw sprite (256x128)
	if scene.sprite then
		spr(scene.sprite, Cutscene.SPRITE_X, Cutscene.SPRITE_Y)
	end

	-- Draw text with character reveal
	local y = Cutscene.TEXT_Y_START
	local chars_remaining = Cutscene.chars_shown

	for _, line in ipairs(scene.text) do
		if chars_remaining <= 0 then break end

		-- Show only the revealed portion of this line
		local line_to_show = sub(line, 1, min(chars_remaining, #line))

		-- Center the text (wider text block)
		local text_x = 240 - (#line_to_show * 2.5)

		-- Shadow
		print(line_to_show, text_x + 1, y + 1, Cutscene.SHADOW_COLOR)
		-- Main text
		print(line_to_show, text_x, y, Cutscene.TEXT_COLOR)

		chars_remaining -= #line
		y += Cutscene.LINE_HEIGHT
	end

	-- Show prompt when scene is complete
	if Cutscene.scene_complete then
		local prompt = "Z/SPACE TO CONTINUE"
		local prompt_x = 240 - (#prompt * 2) - 20
		local prompt_y = 250

		-- Blink the prompt
		if (time() * 2) % 1 > 0.5 then
			-- Shadow
			print(prompt, prompt_x + 1, prompt_y + 1, Cutscene.SHADOW_COLOR)
			-- Main text
			print(prompt, prompt_x, prompt_y, 11)  -- Green
		end
	end
end

-- Check if space/enter pressed to advance
function Cutscene.check_input()
	if not Cutscene.active then return false end
	if not Cutscene.scene_complete then return false end

	-- Don't advance if we just used the key to skip teletype this frame
	if Cutscene.skip_used_this_frame then
		return false
	end

	-- Only advance on fresh key press (keyp detects first press, not held)
	if keyp("space") or keyp("return") or keyp("x") or keyp("z") then
		-- Move to next scene
		Cutscene.current_scene += 1

		if Cutscene.current_scene > #Cutscene.scenes then
			-- All scenes complete
			Cutscene.stop()
			return true  -- Signal that cutscene is done
		else
			-- Start next scene
			Cutscene.char_timer = 0
			Cutscene.chars_shown = 0
			Cutscene.scene_complete = false
			return false
		end
	end

	return false
end

-- Get total number of scenes
function Cutscene.get_scene_count()
	return #Cutscene.scenes
end

return Cutscene
