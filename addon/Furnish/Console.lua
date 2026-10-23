-- What the commands do: list a building's sets, spawn one, import a map doodad, and stop.
--
-- This is the surface, not the API. It holds the one run, reads `attach` off the selection,
-- and closes a grouped run by selecting the group in the player's sight, so the next group
-- command acts on it; the API selects nothing. Every line it prints says what was asked and
-- what was found, and a refusal says the way out.
--
-- A request is plain data, as the command line and a list link both give it:
--   index   the set's index, as a list prints it
--   entry   an object's entry naming the root, as a lookup line prints it
--   file    a root's file id, which a list link carries
--   label   what to call that root in a line, which a list link carries
--   here    true to spawn at the player rather than on the selected object
--   group   "pivot", "first", "attach" or "nogroup"; nil is "pivot"
--   base    true to lay the root's base set under the set

_G.Furnish = _G.Furnish or {}
local Furnish = _G.Furnish
local Console = {}
Furnish.Console = Console

local Reader = Furnish.Reader
local Client = Furnish.Client
local Pose = Furnish.Pose
local Sets = Furnish.Sets
local Names = Furnish.Names
local Rows = Furnish.Rows
local Group = Furnish.Group
local Commands = Furnish.Commands
local Chat = Furnish.Chat

local say = Chat.Say

--- The run going on, if any, whether it was asked to stop, and the way to stop an import
-- still waiting for its object.
local running, stopping, waiting

--- A set's name as a line shows it; the base set has none of its own.
local function setName(set)
	return set.name == "" and "Base" or Names.Set(set.name)
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

local function objects(count)
	return count == 1 and "1 object" or count .. " objects"
end

--- Why nothing new can start, or nil.
local function busy()
	if waiting then
		return "Furnish is waiting for the imported object; " .. Chat.Typed("stop") .. " ends it"
	elseif running and not running.Done() then
		return "Furnish is still spawning; " .. Chat.Typed("stop") .. " ends it"
	end
	return nil
end

--- The selected object's pose, or nil and the way out.
-- @param what what the selection is for, as the way out names it: "the building"
-- @param otherwise another way out, said after selecting, or nil
local function selection(what, otherwise)
	local pose, reason = Pose.Selected()
	if not pose then
		return nil,
			("%s; select %s first, as with .gob select%s"):format(reason, what, otherwise or "")
	end
	return pose
end

--- Why an object's own sets cannot be read, or nil when it is a building that has them.
local function notBuilding(pose, instead)
	if pose.wmo then
		return nil
	end
	return pose.name .. " is not a building, so it has no sets; " .. instead
end

--- The root a request names, what to call it, and the list command that shows its sets;
-- or nil and the way out. Without an entry or a file it is the selected building's own.
local function rootOf(request, pose)
	if request.file then
		return request.file, request.label, Chat.Typed("list")
	end
	if request.entry then
		local file = Sets.OfEntry(request.entry)
		if not file then
			return nil,
				("object %d is not a building Furnish has sets for; check the entry on its lookup line"):format(
					request.entry
				)
		end
		return file, "object " .. request.entry, Chat.Typed("list " .. request.entry)
	end
	return pose.file, pose.name, Chat.Typed("list")
end

--- A root's sets, or nil and the way out.
local function setsOf(file, label)
	local sets = Sets.OfFile(file)
	if not sets then
		return nil, label .. " has no doodad sets in Furnish's data"
	end
	return sets
end

--- The kernel's group for a request, and how a line says it; or nil and the way out.
local function groupOf(request, pose)
	local word = request.group or "pivot"
	if word == "pivot" then
		return Group.Pivot, "led by an invisible pivot"
	elseif word == "first" then
		return Group.First, "led by its first object"
	elseif word == "nogroup" then
		return Group.None, "ungrouped"
	end
	local leader = pose.groupLeader ~= 0 and pose.groupLeader or pose.guid
	return leader, "joining " .. pose.name .. "'s group"
end

--- Report a finished run, and select its group so the next group command acts on it.
local function finish(result)
	local doodads = #result.spawned - (result.pivot and 1 or 0)
	if result.deleted == #result.spawned then
		say(("stopped, and deleted the %s it spawned"):format(objects(result.deleted)))
	elseif result.deleted then
		say(
			("stopped, and deleted %d of the %s it spawned"):format(
				result.deleted,
				objects(#result.spawned)
			)
		)
	elseif result.aborted then
		say(("stopped: %d of %d spawned"):format(doodads, result.total))
	else
		say(("done: %d of %d spawned"):format(doodads, result.total))
	end
	for _, refusal in ipairs(result.refused) do
		say(("display %d was refused: %s"):format(refusal.display, quote(refusal.messages)))
	end
	for _, miss in ipairs(result.unjoined) do
		say(
			("object %s (display %d) spawned but did not join the group: %s"):format(
				miss.guid,
				miss.display,
				quote(miss.messages)
			)
		)
	end
	if result.joined > 0 and not result.deleted then
		Client.Send()(Commands.SelectGroup(result.leader), nil, true)
	end
end

local function hooks()
	local last = 0
	return {
		progress = function(done, total)
			if done < total and done - last >= 10 then
				last = done
				say(("%d of %d"):format(done, total))
			end
		end,
		finished = finish,
	}
end

--- Send a run, having said what it is.
-- @param what the set as a line names it
-- @param where "on <building>" or "at your feet"
-- @param lead how the group is led, as groupOf says it
local function start(rows, pose, group, what, where, lead)
	local send, reason = Client.Send()
	if not send then
		return say(reason)
	end
	say(("spawning %s %s, %s"):format(what, where, lead))
	local handle, refused =
		Furnish.Spawn(rows, pose.position, pose.rotation, pose.scale, group, send, hooks())
	if not handle then
		return say("nothing was sent: " .. refused)
	end
	running, stopping = handle, false
end

--- Print a root's sets, each a link that spawns it.
-- @param request { entry } for an object's sets, or {} for the selected building's; group
--   and base ride along on every link
function Console.List(request)
	local loaded, reason = Reader.Load()
	if not loaded then
		return say(reason)
	end
	local pose
	if not request.entry then
		pose, reason = selection("the building")
		if not pose then
			return say(reason)
		end
		reason = notBuilding(pose, Chat.Typed("list <entry>") .. " lists another object's")
		if reason then
			return say(reason)
		end
	end
	local file, label = rootOf(request, pose)
	if not file then
		return say(label)
	end
	local sets
	sets, reason = setsOf(file, label)
	if not sets then
		return say(reason)
	end
	local carried = table.concat({ request.group or "pivot", request.base and "base" or "" }, ":")
	local indexes, links = {}, {}
	for i, set in ipairs(sets) do
		indexes[i] = Chat.GOLD .. set.index .. Chat.END
		links[i] = Chat.Link(table.concat({ file, set.index, carried, label }, ":"), setName(set))
	end
	local widestIndex, widestLink = Chat.Widest(indexes), Chat.Widest(links)
	say(("%s has %d sets:"):format(label, #sets))
	for i, set in ipairs(sets) do
		Chat.Line(
			"  "
				.. Chat.RightCell(indexes[i], widestIndex)
				.. Chat.Cell(links[i], widestLink)
				.. Chat.GREY
				.. objects(set.count)
				.. Chat.END
		)
	end
end

--- Fill a tooltip for a list link's set: its name, what it is, and what a click does.
-- @param request a list link's request
-- @param tooltip a tooltip owned and empty
function Console.Describe(request, tooltip)
	local set = Reader.Load() and Sets.Pick(request.file, request.index)
	if not set then
		return
	end
	local about = ("set %d of %s, %s"):format(set.index, request.label, objects(set.count))
	if set.name ~= "" then
		about = set.name .. ", " .. about
	end
	local said = {}
	if request.group ~= "pivot" then
		said[#said + 1] = request.group
	end
	if request.base then
		said[#said + 1] = "base"
	end
	tooltip:SetText(setName(set), 1, 1, 1)
	tooltip:AddLine(about, 0.62, 0.62, 0.62, true)
	if #said > 0 then
		tooltip:AddLine("with " .. table.concat(said, " and "), 0.62, 0.62, 0.62)
	end
	tooltip:AddLine("Click: spawn it on the selected object", 1, 1, 1)
	tooltip:AddLine("Ctrl-click: spawn it at your feet", 1, 1, 1)
end

--- Fill a tooltip for the button on a building's doodad line.
-- @param tooltip a tooltip owned and empty
function Console.DescribeImport(tooltip)
	tooltip:SetText("Furnish", 1, 1, 1)
	tooltip:AddLine(
		"Import this building and spawn the sets the map placed it with, grouped on it",
		0.62,
		0.62,
		0.62,
		true
	)
end

--- Spawn a set on the selected object, or at the player.
-- @param request as the head of this file describes it
function Console.Spawn(request)
	local blocked = busy()
	if blocked then
		return say(blocked)
	end
	if not Client.CanSpawn() then
		return
	end
	local loaded, reason = Reader.Load()
	if not loaded then
		return say(reason)
	end
	-- The selected object is the target unless the set goes at the player, and any object
	-- will do. It must be a building only where the set is its own, read off it because
	-- neither a link nor an entry names one; and it leads the group a set attaches to.
	local named = request.entry or request.file
	local pose, target
	if not request.here or not named or request.group == "attach" then
		local what = not named and "the building"
			or request.here and "the object whose group to join"
			or "the object to spawn on"
		local otherwise = request.here and not named and request.group ~= "attach"
		pose, reason = selection(
			what,
			otherwise and (", or name it, as " .. Chat.Typed("3 here <entry>")) or nil
		)
		if not pose then
			return say(reason)
		end
		reason = not named and notBuilding(pose, "name one, as " .. Chat.Typed("3 from <entry>"))
		if reason then
			return say(reason)
		end
		target = pose
	end
	if request.here then
		target, reason = Pose.Here()
		if not target then
			return say(reason)
		end
	end
	local file, label, listing = rootOf(request, pose)
	if not file then
		return say(label)
	end
	local sets
	sets, reason = setsOf(file, label)
	if not sets then
		return say(reason)
	end
	local set = Sets.Pick(file, request.index)
	if not set then
		return say(
			("%s has no set %d; %s shows its %d"):format(label, request.index, listing, #sets)
		)
	end
	local rows, missing = Rows.OfSet(set.id)
	if not rows then
		return say(missing)
	end
	local what = ("%s (set %d, %s"):format(setName(set), set.index, objects(#rows))
	-- A building Epsilon emptied draws no base set of its own, so one standing as the target
	-- gets it.
	local base = request.base or (not request.here and Sets.IsBlank(pose.file))
	if base and set.index ~= 0 and sets[1].index == 0 then
		local under = Rows.OfSet(sets[1].id)
		rows = Rows.Union(under, rows)
		what = what .. " and the base set's " .. #under
	end
	what = what .. ")"
	-- The set is named by its building wherever it is not going onto that building.
	if request.here or label ~= pose.name then
		what = label .. "'s " .. what
	end
	local group, lead = groupOf(request, pose)
	start(rows, target, group, what, request.here and "at your feet" or ("on " .. pose.name), lead)
end

--- The sets of an imported building the map placed it with, beyond the base set it shows
-- itself; with base, the base set as well, whether the map named it or not.
local function placed(pose, ids, base)
	local chosen = {}
	for _, set in ipairs(Sets.OfFile(pose.file) or {}) do
		local named = false
		for _, id in ipairs(ids) do
			named = named or id == set.id
		end
		if set.index == 0 and base or set.index ~= 0 and named then
			chosen[#chosen + 1] = set
		end
	end
	return chosen
end

--- Import a map doodad, then spawn on it the sets the map placed it with, grouped on the
-- building it now is unless a word says otherwise.
-- @param request uid, the doodad's unique id, or nil for the selected doodad; group and
--   base, as for a spawn
function Console.Import(request)
	local blocked = busy()
	if blocked then
		return say(blocked)
	end
	if not Client.CanSpawn() then
		return
	end
	local loaded, reason = Reader.Load()
	if not loaded then
		return say(reason)
	end
	local send
	send, reason = Client.Send()
	if not send then
		return say(reason)
	end
	local _, _, _, map = Client.Position()
	local stopped, stopWaiting = false, nil
	waiting = function()
		stopped = true
		if stopWaiting then
			stopWaiting()
		end
	end
	send(Commands.Import(request.uid), function(_, messages)
		if stopped then
			return
		end
		local uid, guid, model = Commands.Imported(messages)
		if not uid then
			waiting = nil
			return say("nothing was imported: " .. quote(messages))
		end
		local ids = Sets.OfPlacement(map, tonumber(uid))
		-- The import selects the object but pushes no record of it, and the record carries
		-- the pose; selecting it again has the server push one.
		stopWaiting, reason = Client.AwaitRecord(guid, function(record)
			waiting = nil
			local pose = Pose.OfRecord(record)
			if not pose.wmo then
				return say(
					("imported %s as object %s; it is not a building, so it has no sets"):format(
						model,
						guid
					)
				)
			end
			local chosen = ids and placed(pose, ids, request.base) or {}
			if #chosen == 0 then
				return say(
					("imported %s as object %s; %s"):format(
						model,
						guid,
						ids and "the map draws only its base set, which the building shows itself"
							or (
								"the map placed it with no set Furnish knows; "
								.. Chat.Typed("list")
								.. " shows its own"
							)
					)
				)
			end
			local rows, names, indexes = {}, {}, {}
			for i, set in ipairs(chosen) do
				rows = Rows.Union(rows, Rows.OfSet(set.id))
				names[i], indexes[i] = setName(set), set.index
			end
			local what = ("%s (%s %s, %s)"):format(
				table.concat(names, " and "),
				#chosen == 1 and "set" or "sets",
				table.concat(indexes, " and "),
				objects(#rows)
			)
			local group, lead = groupOf({ group = request.group or "attach" }, pose)
			start(rows, pose, group, what, "on " .. pose.name, lead)
		end)
		if not stopWaiting then
			waiting = nil
			return say(reason)
		end
		send(Commands.Select(guid), function(selected, replies)
			if not selected and waiting then
				waiting()
				waiting = nil
				say(
					("imported %s as object %s, but selecting it was refused: %s"):format(
						model,
						guid,
						quote(replies)
					)
				)
			end
		end)
	end)
end

--- Stop spawning. With delete, also delete what the run spawned.
function Console.Stop(delete)
	if waiting then
		waiting()
		waiting = nil
		return say("stopped; nothing was spawned, and an import already sent stands")
	end
	if not (running and not running.Done()) then
		return say("nothing is spawning")
	end
	if stopping then
		say("giving up on the replies still owed")
	elseif delete then
		say(
			"stopping, then deleting what was spawned; "
				.. Chat.Typed("stop")
				.. " again gives up on a reply that never comes"
		)
	else
		say("stopping; " .. Chat.Typed("stop") .. " again gives up on a reply that never comes")
	end
	stopping = true
	running.Abort(delete)
end
