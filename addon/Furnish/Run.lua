-- Processing and post-processing: a plan goes out as commands, and what comes back is
-- grouped.
--
-- The run is dumb on purpose. It sends the plan's spawns, reads each reply for the GUID it
-- made, counts a refusal and moves on, and tells its hooks how far it is. Grouping is the
-- one thing it decides after the fact, since a group needs the leader's GUID, which only a
-- reply gives. A run keeps its own GUIDs for as long as it lasts and no longer: an abort can
-- take down what it spawned, and nothing survives the run.
--
-- `send(text, callback)` is the one door to the server, handed in rather than reached for,
-- so the whole file runs against a stand-in outside the client.

_G.Furnish = _G.Furnish or {}
local Furnish = _G.Furnish
local Run = {}
Furnish.Run = Run

--- How many spawns are in flight at once when the join is chained onto them. When it is
-- not, the join acts on the selection the spawn left, so one object goes at a time.
Run.IN_FLIGHT = 4

local function guidOf(messages)
	for _, message in ipairs(messages or {}) do
		local guid = message:match("gameobject_GUID:[0-9]+|h([0-9]+)|h")
			or message:match("GUID: |c[0-9a-fA-F]+([0-9]+)")
		if guid then
			return guid
		end
	end
	return nil
end

local function tell(hooks, name, ...)
	local hook = hooks and hooks[name]
	if hook then
		hook(...)
	end
end

--- Carry out a plan.
-- @param plan what Plan.Build answered
-- @param send function(text, callback(success, messages)) that sends one command
-- @param hooks { progress = function(done, total), finished = function(result) }, optional
-- @return a handle with Abort(cleanup), which stops the run and, with cleanup, deletes what
--   it spawned so far
function Run.Start(plan, send, hooks)
	local state = {
		plan = plan,
		send = send,
		hooks = hooks,
		at = 1,
		inFlight = 0,
		done = 0,
		spawned = {},
		refused = {},
		leader = nil,
		aborted = false,
		finished = false,
	}
	local total = #plan.commands

	local function finish()
		if state.finished then
			return
		end
		state.finished = true
		tell(hooks, "finished", {
			total = total,
			done = state.done,
			spawned = state.spawned,
			refused = state.refused,
			leader = state.leader,
			aborted = state.aborted,
		})
	end

	local function leaderGuid()
		if plan.leader == "house" then
			local house = plan.house
			return tostring(
				house.groupLeader and house.groupLeader ~= 0 and house.groupLeader or house.guid
			)
		end
		return state.leader
	end

	local step

	local function joined(guid)
		state.spawned[#state.spawned + 1] = guid
		state.done = state.done + 1
		tell(hooks, "progress", state.done, total)
		state.inFlight = state.inFlight - 1
		step()
	end

	local function spawned(command, success, messages)
		if not success then
			state.refused[#state.refused + 1] = {
				display = command.display,
				reason = tostring(messages and messages[1] or "refused"),
			}
			state.done = state.done + 1
			tell(hooks, "progress", state.done, total)
			state.inFlight = state.inFlight - 1
			step()
			return
		end
		local guid = guidOf(messages)
		local first = state.leader == nil and plan.leader ~= "house"
		if first then
			state.leader = guid
		end
		if first or plan.chainedJoin then
			joined(guid)
			return
		end
		send("gobject group add " .. leaderGuid(), function()
			joined(guid)
		end)
	end

	local function text(command)
		if plan.chainedJoin and command.role == "doodad" and leaderGuid() then
			return command.text .. " group add " .. leaderGuid()
		end
		return command.text
	end

	step = function()
		if state.aborted then
			if state.inFlight == 0 then
				finish()
			end
			return
		end
		if state.at > total then
			if state.inFlight == 0 then
				finish()
			end
			return
		end
		-- The leader goes alone, since every later join names its GUID; after it, as many as
		-- the join style allows.
		local width = (state.leader or plan.leader == "house")
				and (plan.chainedJoin and Run.IN_FLIGHT or 1)
			or 1
		if state.leader == nil and plan.leader ~= "house" and state.inFlight > 0 then
			return
		end
		while state.inFlight < width and state.at <= total do
			local command = plan.commands[state.at]
			state.at = state.at + 1
			state.inFlight = state.inFlight + 1
			send(text(command), function(success, messages)
				spawned(command, success, messages)
			end)
		end
	end

	local handle = {}

	--- Stop issuing commands. With cleanup, delete what this run spawned once the commands
	-- in flight have answered.
	function handle.Abort(cleanup)
		if state.finished or state.aborted then
			return
		end
		state.aborted = true
		if cleanup then
			local previous = hooks and hooks.finished
			hooks = { progress = hooks and hooks.progress }
			hooks.finished = function(result)
				local pending = #result.spawned
				if pending == 0 then
					if previous then
						previous(result)
					end
					return
				end
				for _, guid in ipairs(result.spawned) do
					send("gobject delete " .. guid, function()
						pending = pending - 1
						if pending == 0 and previous then
							result.deleted = #result.spawned
							previous(result)
						end
					end)
				end
			end
			state.hooks = hooks
		end
		if state.inFlight == 0 then
			finish()
		end
	end

	function handle.Done()
		return state.finished
	end

	step()
	return handle
end
