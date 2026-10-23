-- The /run door: the providers composed for the common cases, reporting to chat.
--
-- This is a surface, not the API: it holds the one running run, picks defaults, and prints.
-- Every line it prints says what was asked, what was found and, on a refusal, the way out.
--
-- A root is named by its model name, the word `.lookup gobject` prints beside the entry,
-- resolved by the client's own display table; never by a file id, which no player has.
--
--   /run Furnish.Console.Sets()                      the selected object's sets
--   /run Furnish.Console.Sets("6dr_draenei_house2")  that root's sets
--   /run Furnish.Console.Spawn(1)                    set 1 of the selected object's root, on it
--   /run Furnish.Console.Spawn(1, { from = "6dr_draenei_house2" })   that root's set 1, on it
--   /run Furnish.Console.Spawn(1, { group = Furnish.Group.First })
--   /run Furnish.Console.Here("6dr_draenei_house2", 1)   that root's set 1, at the player
--   /run Furnish.Console.Abort(true)                 stop, and delete what was spawned

_G.Furnish = _G.Furnish or {}
local Furnish = _G.Furnish
local Console = {}
Furnish.Console = Console

local Client = Furnish.Client
local Pose = Furnish.Pose
local Sets = Furnish.Sets
local Rows = Furnish.Rows
local Group = Furnish.Group
local Commands = Furnish.Commands

local running

local function say(text)
	print("|cff66ccffFurnish:|r " .. text)
end

local function describe(set)
	if set.name == "" then
		return ("set %d (default, %d objects)"):format(set.index, set.count)
	end
	return ("set %d %s (%d objects)"):format(set.index, set.name, set.count)
end

local function hooks()
	local last = 0
	return {
		progress = function(done, total)
			if done == total or done - last >= 10 then
				last = done
				say(("%d of %d"):format(done, total))
			end
		end,
		finished = function(result)
			local text = ("done: %d of %d spawned"):format(#result.spawned, result.total)
			if result.leader then
				text = text .. ", group led by " .. result.leader
			end
			if result.aborted then
				text = text .. ", aborted"
			end
			if result.deleted then
				text = text .. (", %d deleted"):format(result.deleted)
			end
			say(text)
			for _, refusal in ipairs(result.refused) do
				say(("display %d was refused: %s"):format(refusal.display, refusal.reason))
			end
		end,
	}
end

--- The selected object's pose, or nil and the reason, with the selection's shape named.
local function selection(callback)
	local object = Client.Selected()
	if object == false then
		return callback(nil, "a group is selected; select one object with gobject select")
	end
	if not object then
		return callback(nil, "no object is selected; select one with gobject select <guid>")
	end
	Pose.Of(object.guid, callback)
end

--- The rows for a set of a root: the set's own, with the default set's before them on an
-- emptywmo or when asked for.
local function rowsFor(file, index, withDefault)
	local set, reason = Sets.Pick(file, index)
	if not set then
		return nil, reason
	end
	local rows, missing = Rows.OfSet(set.id)
	if not rows then
		return nil, missing
	end
	local note = describe(set)
	if withDefault and set.index ~= 0 then
		local default = Sets.Pick(file, 0)
		if default then
			rows = Rows.Union(Rows.OfSet(default.id), rows)
			note = note .. " with the default set's " .. default.count
		end
	end
	return rows, note
end

local function start(rows, pose, group, note)
	if running and not running.Done() then
		return say("a run is still going; /run Furnish.Console.Abort() to stop it")
	end
	local send, why = Client.Send()
	if not send then
		return say(why)
	end
	local lead = group == Group.Pivot and "an invisible pivot leading"
		or group == Group.First and "the first object leading"
		or group == Group.None and "ungrouped"
		or ("joining the group of " .. tostring(group))
	say(
		("spawning %d objects, %s, at %s %s %s, %s"):format(
			#rows,
			note,
			Commands.Number(pose.position.x),
			Commands.Number(pose.position.y),
			Commands.Number(pose.position.z),
			lead
		)
	)
	local handle, reason =
		Furnish.Spawn(rows, pose.position, pose.rotation, pose.scale, group, send, hooks())
	if not handle then
		return say("nothing was sent: " .. reason)
	end
	running = handle
end

--- List the sets of the selected object's root, or of the root a model name spawns.
function Console.Sets(name)
	local function list(file, label)
		local sets, reason = Sets.OfFile(file)
		if not sets then
			return say(reason)
		end
		say(("%s offers %d sets:"):format(label, #sets))
		for _, set in ipairs(sets) do
			say("  " .. describe(set))
		end
	end
	if name then
		local file, reason = Sets.OfName(name)
		if not file then
			return say(reason)
		end
		return list(file, ("%s (root file %s)"):format(tostring(name), tostring(file)))
	end
	selection(function(pose, reason)
		if not pose then
			return say(reason)
		end
		list(pose.file, ("%s (root file %s)"):format(pose.name, tostring(pose.file)))
	end)
end

--- Spawn a set on the selected object.
-- @param index the set's index
-- @param options { from = a model name, group = a Furnish.Group value or GUID, default = true }
function Console.Spawn(index, options)
	options = options or {}
	selection(function(pose, reason)
		if not pose then
			return say(reason)
		end
		if not pose.wmo then
			return say(
				("%s (%d) is not a WMO; a set is laid out against a building"):format(
					pose.name,
					pose.guid
				)
			)
		end
		local function go(file, missing)
			if not file then
				return say(missing)
			end
			local rows, note = rowsFor(file, index, options.default or pose.empty)
			if not rows then
				return say(note)
			end
			start(rows, pose, options.group or Group.Pivot, note .. " of root file " .. file)
		end
		if options.from then
			return go(Sets.OfName(options.from))
		end
		if pose.empty then
			return go(Sets.Original(pose.name))
		end
		go(pose.file)
	end)
end

--- Spawn a set of the root a model name spawns, where the player stands, facing as the
-- player faces.
-- @param name the model name, as .lookup gobject prints it
-- @param index the set's index
-- @param options { group = a Furnish.Group value or GUID, default = true, scale = number }
function Console.Here(name, index, options)
	options = options or {}
	local pose, reason = Pose.Here()
	if not pose then
		return say(reason)
	end
	pose.scale = options.scale or 1
	local file, missing = Sets.OfName(name)
	if not file then
		return say(missing)
	end
	local rows, note = rowsFor(file, index, options.default)
	if not rows then
		return say(note)
	end
	start(rows, pose, options.group or Group.Pivot, note .. " of root file " .. file)
end

--- Stop the current run. With cleanup, delete what it spawned.
function Console.Abort(cleanup)
	if running and not running.Done() then
		running.Abort(cleanup)
		say(cleanup and "aborting, and deleting what was spawned" or "aborting")
	else
		say("nothing is running")
	end
end
