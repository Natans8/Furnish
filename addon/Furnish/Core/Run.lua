-- A run: a series of commands sent through one door, in order, with what each answered kept
-- by position.
--
-- The run knows nothing of what the commands do. A command is a string, or a function of
-- the results so far whose text may depend on an earlier reply and may be nil to send
-- nothing. A command may name the positions it needs answered before it goes, and no more
-- than `width` commands are unanswered at once. A command may be glued to the one before
-- it: the two go out in the same breath or not at all, so nothing sent from an event can
-- come between them, and the width never parts them. The run tells its hooks how far it is
-- and hands back every result when it ends or is aborted. A need names an earlier position,
-- never one in its own glued run, and a series that breaks that rule is refused before
-- anything is sent.
--
-- `send(text, callback(success, messages))` is the one door to the server, handed in rather
-- than reached for, so the whole file runs against a stand-in outside the client.

local _, Furnish = ...
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
-- @param commands a list of { text = string or function(results), needs = { positions },
--   glued = true to go out together with the command before it }
-- @param send function(text, callback(success, messages))
-- @param hooks { progress = function(done, total, index, result), finished = function(outcome) },
--   optional; progress is told each position as it settles
-- @param width how many commands may be unanswered at once; 1 when absent
-- @return a handle with Abort(), which stops sending, and Done(); or nil and the reason
function Run.Start(commands, send, hooks, width)
	width = width or 1
	local total = #commands
	local head = 1
	for index, command in ipairs(commands) do
		if command.glued and index == 1 then
			return nil, "command 1 is glued, but nothing is before it"
		elseif not command.glued then
			head = index
		end
		for _, need in ipairs(command.needs or {}) do
			if need >= head then
				return nil,
					("command %d needs position %d, which is not before it and its glued run"):format(
						index,
						need
					)
			end
		end
	end
	local results = {}
	local at, inFlight, done = 1, 0, 0
	local aborted, finished, stepping, another = false, false, false, false
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

	-- Send the command at a position, or settle it as skipped when its text comes out nil.
	local function dispatch(index)
		local text = commands[index].text
		if type(text) == "function" then
			text = text(results)
		end
		if text == nil then
			settle(index, { skipped = true })
			return
		end
		inFlight = inFlight + 1
		send(text, function(success, messages)
			inFlight = inFlight - 1
			settle(index, { text = text, success = success == true, messages = messages })
			step()
		end)
	end

	-- The last position of the glued run that starts at `from`, and whether all of it may go.
	local function gluedRun(from)
		local last = from
		while commands[last + 1] and commands[last + 1].glued do
			last = last + 1
		end
		for index = from, last do
			if not answered(results, commands[index].needs) then
				return last, false
			end
		end
		return last, true
	end

	step = function()
		-- A reply that lands while this is still sending only asks for another pass, so a
		-- glued run is never parted by a send made from inside one of its own callbacks.
		if stepping then
			another = true
			return
		end
		stepping = true
		repeat
			another = false
			while not aborted and inFlight < width and at <= total do
				local last, ready = gluedRun(at)
				if not ready then
					break
				end
				for index = at, last do
					dispatch(index)
				end
				at = last + 1
			end
		until not another
		stepping = false
		if (aborted or at > total) and inFlight == 0 then
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
