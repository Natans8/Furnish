-- The /run door: the providers composed for the common cases, reporting to chat.
--
-- This is a surface, not the API: it holds the one running run, picks defaults, and prints.
-- Every line it prints says what was asked, what was found and, on a refusal, the way out.
--
-- A root is the selected object's, off the record the server pushed for it, or any WMO
-- object's by its entry, the number a lookup line prints. Nothing here moves the selection.
--
--   /run Furnish.Console.Sets()                 the selected object's sets
--   /run Furnish.Console.Sets(817579)           an object's sets, by entry
--   /run Furnish.Console.Spawn(1)               set 1 of the selected object's root, on it
--   /run Furnish.Console.Spawn(1, { from = 817579 })     entry 817579's set 1, on the selection
--   /run Furnish.Console.Spawn(1, { group = Furnish.Group.First })
--   /run Furnish.Console.Here(817579, 1)        entry 817579's set 1, at the player
--   /run Furnish.Console.Abort(true)            stop, and delete what was spawned

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

--- The server's reply lines as one quotable string, colour codes and links stripped.
local function quote(messages)
	if #messages == 0 then
		return "an empty reply"
	end
	local plain = {}
	for i, line in ipairs(messages) do
		plain[i] = Commands.Plain(line)
	end
	return '"' .. table.concat(plain, " / ") .. '"'
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
			local doodads = #result.spawned - (result.pivot and 1 or 0)
			local text = ("done: %d of %d spawned"):format(doodads, result.total)
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
				say(("display %d was refused: %s"):format(refusal.display, quote(refusal.messages)))
			end
			for _, miss in ipairs(result.unjoined) do
				say(
					("%s (display %d) spawned but did not join: %s"):format(
						miss.guid,
						miss.display,
						quote(miss.messages)
					)
				)
			end
		end,
	}
end

--- The selected object's pose, or nil and a reason that names the way out.
local function selection()
	local pose, reason = Pose.Selected()
	if not pose then
		return nil, reason .. "; select one object with gobject select <guid>"
	end
	return pose
end

--- The rows for a set of a root: the set's own, with set 0's before them on an emptywmo or
-- when asked for. Asking for set 0 itself is just set 0.
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

--- List the sets of the selected object's root, or of an object by entry.
function Console.Sets(entry)
	local function list(root, label)
		local sets, reason = Sets.OfFile(root)
		if not sets then
			return say(reason)
		end
		say(("%s offers %d sets:"):format(label, #sets))
		for _, set in ipairs(sets) do
			say("  " .. describe(set))
		end
	end
	if entry then
		local file, reason = Sets.OfEntry(entry)
		if not file then
			return say(reason)
		end
		return list(file, "entry " .. tostring(entry))
	end
	local pose, reason = selection()
	if not pose then
		return say(reason)
	end
	list(pose.file, ("%s (root file %s)"):format(pose.name, tostring(pose.file)))
end

--- Spawn a set on the selected object.
-- @param index the set's index
-- @param options { from = another object's entry, group = a Furnish.Group value or GUID,
--   withDefault = true to lay set 0 under the set asked for, as an emptywmo always does }
function Console.Spawn(index, options)
	options = options or {}
	local pose, reason = selection()
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
	local empty = Sets.IsEmptyShell(pose.name)
	local file, missing
	if options.from then
		file, missing = Sets.OfEntry(options.from)
	elseif empty then
		file, missing = Sets.Original(pose.name)
	else
		file = pose.file
	end
	if not file then
		return say(missing)
	end
	local rows, note = rowsFor(file, index, options.withDefault or empty)
	if not rows then
		return say(note)
	end
	start(rows, pose, options.group or Group.Pivot, note .. " of root file " .. file)
end

--- Spawn a set of an object's root where the player stands, facing as the player faces.
-- @param entry the object's entry, as a lookup line prints it
-- @param index the set's index
-- @param options { group = a Furnish.Group value or GUID, withDefault = true, scale = number }
function Console.Here(entry, index, options)
	options = options or {}
	local pose, reason = Pose.Here()
	if not pose then
		return say(reason)
	end
	pose.scale = options.scale or 1
	local file, missing = Sets.OfEntry(entry)
	if not file then
		return say(missing)
	end
	local rows, note = rowsFor(file, index, options.withDefault)
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
