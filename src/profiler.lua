-- Profiler module for performance tracking
-- Tracks CPU time spent in different subsystems

local Profiler = {}

-- Profiler state
local enabled = true
local timers = {}
local timer_stack = {}

-- Reset all profiler timers
function Profiler.reset()
	timers = {}
end

-- Start timing a section
function Profiler.start(name)
	if not enabled then return end

	local timer = {
		name = name,
		start_time = stat(1),  -- CPU time
		parent = timer_stack[#timer_stack]
	}

	add(timer_stack, timer)
end

-- End timing a section
function Profiler.stop(name)
	if not enabled then return end

	if #timer_stack == 0 then
		-- Error: no timer running
		return
	end

	local timer = timer_stack[#timer_stack]
	if timer.name != name then
		-- Error: mismatched timer
		return
	end

	-- Calculate elapsed time
	local end_time = stat(1)
	local elapsed = end_time - timer.start_time

	-- Store in timers table
	if not timers[name] then
		timers[name] = {
			total = 0,
			count = 0,
			avg = 0,
			max = 0,
			min = 999999
		}
	end

	local t = timers[name]
	t.total += elapsed
	t.count += 1
	t.avg = t.total / t.count
	t.max = max(t.max, elapsed)
	t.min = min(t.min, elapsed)

	-- Pop from stack
	del(timer_stack, timer)
end

-- Get timing data for a section
function Profiler.get(name)
	return timers[name]
end

-- Get all timing data
function Profiler.get_all()
	return timers
end

-- Enable/disable profiler
function Profiler.set_enabled(is_enabled)
	enabled = is_enabled
end

-- Check if enabled
function Profiler.is_enabled()
	return enabled
end

-- Draw profiler display
function Profiler.draw(x, y, max_entries)
	if not enabled then return end

	local cy = y
	print_shadow = print_shadow or function(text, x, y, color)
		print(text, x + 1, y + 1, 0)
		print(text, x, y, color)
	end

	print_shadow("PROFILER (ms):", x, cy, 11)
	cy += 10

	-- Sort by total time (descending)
	local sorted = {}
	for name, data in pairs(timers) do
		add(sorted, {name=name, data=data})
	end

	-- Simple bubble sort by total time
	for i = 1, #sorted do
		for j = i + 1, #sorted do
			if sorted[j].data.total > sorted[i].data.total then
				local temp = sorted[i]
				sorted[i] = sorted[j]
				sorted[j] = temp
			end
		end
	end

	-- Display entries
	local count = 0
	for entry in all(sorted) do
		if max_entries and count >= max_entries then break end

		local name = entry.name
		local data = entry.data
		local avg_ms = flr(data.avg * 1000 * 100) / 100
		local max_ms = flr(data.max * 1000 * 100) / 100

		-- Color based on time (red = slow, green = fast)
		local color = 11  -- Default green
		if avg_ms > 5 then
			color = 8  -- Red
		elseif avg_ms > 2 then
			color = 9  -- Orange
		elseif avg_ms > 1 then
			color = 10  -- Yellow
		end

		print_shadow(name..": "..avg_ms, x, cy, color)
		cy += 8
		count += 1
	end

	return cy
end

return Profiler
