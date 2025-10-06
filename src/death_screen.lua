-- Death Screen Module
-- Handles death state UI and animations

local DeathScreen = {}

-- Configuration
DeathScreen.FADE_DURATION = 0.5  -- Fade in over 0.5 seconds
DeathScreen.TOTAL_DURATION = 2.0  -- Total time before allowing restart

-- Colors
DeathScreen.BG_COLOR = 12  -- Blue background
DeathScreen.BORDER_COLOR = 8  -- Red border
DeathScreen.TEXT_COLOR = 8  -- Red text
DeathScreen.SHADOW_COLOR = 0  -- Black shadow

-- Layout
DeathScreen.BOX_X1 = 140
DeathScreen.BOX_Y1 = 100
DeathScreen.BOX_X2 = 340
DeathScreen.BOX_Y2 = 170

-- Draw the death screen overlay
-- @param death_timer: time since entering DEAD state
function DeathScreen.draw(death_timer)
	-- Blue rectangle background (semi-transparent feel using dithering)
	fillp(0b0101101001011010)  -- 50% dither pattern
	rectfill(DeathScreen.BOX_X1, DeathScreen.BOX_Y1, DeathScreen.BOX_X2, DeathScreen.BOX_Y2, DeathScreen.BG_COLOR)
	fillp()  -- Reset fill pattern

	-- Red border
	rect(DeathScreen.BOX_X1, DeathScreen.BOX_Y1, DeathScreen.BOX_X2, DeathScreen.BOX_Y2, DeathScreen.BORDER_COLOR)

	-- "YOU DIED" text (fading in)
	local fade_progress = min(death_timer / DeathScreen.FADE_DURATION, 1)

	local death_text = "YOU DIED"
	local text_x = 240 + (#death_text * 4)
	local text_y = 120

	-- Fade using dithering patterns
	if fade_progress > 0.8 then
		-- Fully visible
		fillp()
	elseif fade_progress > 0.6 then
		fillp(0b1000000010000000)  -- Very light dither
	elseif fade_progress > 0.4 then
		fillp(0b1000010010000100)  -- Light dither
	elseif fade_progress > 0.2 then
		fillp(0b1010010010100100)  -- Medium dither
	else
		fillp(0b0101101001011010)  -- Heavy dither (barely visible)
	end

	-- Shadow
	print(death_text, text_x + 2, text_y + 2, DeathScreen.SHADOW_COLOR)
	-- Main text (white)
	print(death_text, text_x, text_y, DeathScreen.TEXT_COLOR)
	fillp()  -- Reset fill pattern

	-- Return to menu prompt (appears after total duration)
	if death_timer >= DeathScreen.TOTAL_DURATION then
		local prompt = "PRESS ANY KEY TO RETURN TO MENU"
		local prompt_x = 240 - (#prompt * 2)
		-- Shadow
		print(prompt, prompt_x + 1, 146, DeathScreen.SHADOW_COLOR)
		-- Main text
		print(prompt, prompt_x, 145, DeathScreen.TEXT_COLOR)
	end
end

-- Check if restart is allowed
-- @param death_timer: time since entering DEAD state
-- @return true if player can restart
function DeathScreen.can_restart(death_timer)
	return death_timer >= DeathScreen.TOTAL_DURATION
end

return DeathScreen
