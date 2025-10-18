-- Audio Manager Module
-- Centralized system for managing music and sound effects

local AudioManager = {}

-- Audio file definitions and memory addresses
AudioManager.music_files = {
    intro = {
        file = "sfx/introsong.sfx",
        addr = 0x80000,
        data = nil
    },
    level1 = {
        file = "sfx/firstlevelsong.sfx",
        addr = 0xC0000,
        data = nil
    },
    level2 = {
        file = "sfx/secondlevelsong.sfx", 
        addr = 0x100000,
        data = nil
    },
    hyperlevel = {
        file = "sfx/hyperlevel.sfx",
        addr = 0x140000,
        data = nil
    },
    lastday = {
        file = "sfx/lastday.sfx",
        addr = 0x180000,
        data = nil
    },
    tom_lander = {
        file = "sfx/tom_lander.sfx",
        addr = 0x1C0000,
        data = nil
    }
    -- Add more music files here as needed
}

-- Audio state tracking
AudioManager.current_music = nil
AudioManager.current_volume = 1.0
AudioManager.fade_timer = 0
AudioManager.fade_duration = 0
AudioManager.fade_target_volume = 1.0
AudioManager.fade_callback = nil

-- Volume settings
AudioManager.volumes = {
    menu_music = 1.0,
    level_music = 0.5,
    cutscene_music = 1.0,
    sfx = 1.0
}

-- Initialize audio system - load all music files into memory
function AudioManager.init()
    print("Loading audio files...")
    
    for name, music in pairs(AudioManager.music_files) do
        local data = fetch(music.file)
        if data then
            data:poke(music.addr)
            music.data = data
            print("Loaded: " .. music.file .. " -> 0x" .. tostr(music.addr, true))
        else
            print("Failed to load: " .. music.file)
        end
    end
    
    print("Audio system initialized")
end

-- Play music with optional fade in
function AudioManager.play_music(music_name, pattern, volume, fade_in_time)
    local music_info = AudioManager.music_files[music_name]
    if not music_info or not music_info.data then
        print("Music not found: " .. tostr(music_name))
        return
    end
    
    volume = volume or 1.0
    fade_in_time = fade_in_time or 0
    
    -- Stop current music if different
    if AudioManager.current_music ~= music_name then
        AudioManager.stop_music()
    end
    
    -- Start new music
    if fade_in_time > 0 then
        -- Start at 0 volume and fade in
        music(pattern, nil, nil, music_info.addr, 0)
        AudioManager.fade_to_volume(volume, fade_in_time)
    else
        -- Start at target volume immediately
        music(pattern, nil, nil, music_info.addr, volume)
    end
    
    AudioManager.current_music = music_name
    AudioManager.current_volume = volume
    
    print("Playing: " .. music_name .. " pattern " .. tostr(pattern) .. " vol " .. tostr(volume))
end

-- Stop music with optional fade out
function AudioManager.stop_music(fade_out_time, callback)
    if not AudioManager.current_music then return end
    
    fade_out_time = fade_out_time or 0
    
    if fade_out_time > 0 then
        AudioManager.fade_to_volume(0, fade_out_time, function()
            music(-1)  -- Stop all music
            AudioManager.current_music = nil
            AudioManager.current_volume = 0
            if callback then callback() end
        end)
    else
        music(-1)  -- Stop all music immediately
        AudioManager.current_music = nil
        AudioManager.current_volume = 0
        if callback then callback() end
    end
end

-- Transition between music tracks with crossfade
function AudioManager.transition_music(new_music, pattern, volume, transition_time)
    transition_time = transition_time or 0.5
    volume = volume or 1.0
    
    if AudioManager.current_music then
        -- Fade out current, then fade in new
        AudioManager.stop_music(transition_time / 2, function()
            AudioManager.play_music(new_music, pattern, volume, transition_time / 2)
        end)
    else
        -- No current music, just start new one
        AudioManager.play_music(new_music, pattern, volume, transition_time)
    end
end

-- Fade to a specific volume over time
function AudioManager.fade_to_volume(target_volume, duration, callback)
    AudioManager.fade_target_volume = target_volume
    AudioManager.fade_duration = duration
    AudioManager.fade_timer = 0
    AudioManager.fade_callback = callback
end

-- Update function - handle fades (call this in _update)
function AudioManager.update(delta_time)
    -- Handle volume fading
    if AudioManager.fade_duration > 0 then
        AudioManager.fade_timer += delta_time
        
        local progress = AudioManager.fade_timer / AudioManager.fade_duration
        if progress >= 1.0 then
            -- Fade complete
            AudioManager.current_volume = AudioManager.fade_target_volume
            AudioManager.fade_duration = 0
            
            -- Execute callback if provided
            if AudioManager.fade_callback then
                local callback = AudioManager.fade_callback
                AudioManager.fade_callback = nil
                callback()
            end
        else
            -- Interpolate volume
            local start_volume = AudioManager.current_volume
            AudioManager.current_volume = start_volume + (AudioManager.fade_target_volume - start_volume) * progress
        end
        
        -- Update actual music volume if music is playing
        if AudioManager.current_music then
            local music_info = AudioManager.music_files[AudioManager.current_music]
            if music_info then
                -- Note: Picotron doesn't have direct volume control during playback
                -- This would need to be implemented differently if real-time volume control is needed
            end
        end
    end
end

-- High-level music control functions for different game states
function AudioManager.start_menu_music()
    AudioManager.play_music("level1", 1, AudioManager.volumes.menu_music, 0.3)
end

function AudioManager.start_cutscene_music()
    AudioManager.transition_music("intro", 0, AudioManager.volumes.cutscene_music, 0.5)
end

function AudioManager.start_level_music(mission_num)
    local music_name = "level1"  -- Default
    local pattern = 0
    
    -- Map missions to music
    if mission_num == 3 then
        music_name = "tom_lander"
        pattern = 0
    elseif mission_num == 4 then
        music_name = "level2"
        pattern = 0
    elseif mission_num == 5 then
        music_name = "hyperlevel"
        pattern = 2
    elseif mission_num >= 6 then
        -- Mission 6+ uses lastday for final battle music
        music_name = "lastday"
        pattern = 0
    end
    -- Add more mission->music mappings here
    
    AudioManager.transition_music(music_name, pattern, AudioManager.volumes.level_music, 0.4)
end

function AudioManager.stop_all_audio()
    AudioManager.stop_music()
    -- Stop all SFX channels (except reserved ones)
    for i = 0, 7 do
        if i ~= 4 then  -- Don't stop thruster channel
            sfx(-1, i)
        end
    end
end

-- Enhanced SFX functions
function AudioManager.play_sfx(sfx_id, channel, volume)
    volume = volume or AudioManager.volumes.sfx
    if channel then
        sfx(sfx_id, channel, 0, -1, volume)
    else
        sfx(sfx_id, -1, 0, -1, volume)  -- Auto-assign channel
    end
end

function AudioManager.stop_sfx(channel)
    sfx(-1, channel)
end

-- Get music address for backwards compatibility
function AudioManager.get_music_addr(music_name)
    local music_info = AudioManager.music_files[music_name]
    return music_info and music_info.addr or nil
end

return AudioManager