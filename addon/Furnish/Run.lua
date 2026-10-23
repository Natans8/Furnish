-- A run: a series of commands sent through one door, in order, with what each answered kept
-- by position.
--
-- The run knows nothing of what the commands do. A command is a string, or a function of
-- the results so far whose text may depend on an earlier reply and may be nil to send
-- nothing. A command may name the positions it needs answered before it goes, and no more
-- than `width` commands are unanswered at once. The run tells its hooks how far it is and
-- hands back every result when it ends or is aborted. A need names an earlier position, and
-- a series that breaks that rule is refused before anything is sent.
--
-- `send(text, callback(success, messages))` is the one door to the server, handed in rather
-- than reached for, so the whole file runs against a stand-in outside the client.

_G.Furnish = _G.Furnish or {}
local Furnish = _G.Furnish
local Run = {}
Furnish.Run = Run

local function tell(hooks, name, ...)
	local hook = hooks and hooks[name]
	if hook then
		hook(...)
	end
end

local function answered(results, needs)
	for _, index in ipairs(needs or {}) do
		if results[index] == nil then
			return false
		end
	end
	return true
end

--- Send a series of commands.
-- @param commands a list of { text = string or function(results), needs = { positions } }
-- @param send function(text, callback(success, messages))
-- @param hooks { progress = function(done, total, index, result), finished = function(outcome) },
--   optional; progress is told each position as it settles
-- @param width how many commands may be unanswered at once; 1 when absent
-- @return a handle with Abort(), which stops sending, and Done(); or nil and the reason
function Run.Start(commands, send, hooks, width)
	width = width or 1
	local total = #commands
	for index, command in ipairs(commands) do
		for _, need in ipairs(command.needs or {}) do
			if need >= index then
				return nil,
					("command %d needs position %d, which is not before it"):format(index, need)
			end
		end
	end
	local results = {}
	local at, inFlight, done = 1, 0, 0
	local aborted, finished = false, false
	local step

	local function finish()
		if finished then
			return
		end
		finished = true
		tell(
			hooks,
			"finished",
			{ results = results, total = total, done = done, aborted = aborted }
		)
	end

	local function settle(index, result)
		if finished then
			return
		end
		results[index] = result
		done = done + 1
		tell(hooks, "progress", done, total, index, result)
	end

	step = function()
		if aborted or at > total then
			if inFlight == 0 then
				finish()
			end
			return
		end
		while inFlight < width and at <= total do
			local command = commands[at]
			if not answered(results, command.needs) then
				return
			end
			local index = at
			at = at + 1
			local text = command.text
			if type(text) == "function" then
				text = text(results)
			end
			if text == nil then
				settle(index, { skipped = true })
			else
				inFlight = inFlight + 1
				send(text, function(success, messages)
					inFlight = inFlight - 1
					settle(index, { text = text, success = success == true, messages = messages })
					step()
				end)
			end
		end
		if at > total and inFlight == 0 then
			finish()
		end
	end

	local handle = {}

	--- Stop sending. What is already in flight still answers, and then the run finishes.
	-- A second abort while replies are still owed gives up on them and finishes at once,
	-- since the server's door has no timeout of its own; a reply that lands afterwards is
	-- ignored.
	function handle.Abort()
		if finished then
			return
		end
		local again = aborted
		aborted = true
		if again or inFlight == 0 then
			finish()
		end
	end

	function handle.Done()
		return finished
	end

	step()
	return handle
end
