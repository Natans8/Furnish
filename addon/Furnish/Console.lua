-- What the commands do: list a WMO's sets, spawn one, import a doodad, and stop.
--
-- This is the surface, not the API. It holds the one run, reads `attach` off the selection,
-- and closes a grouped run by selecting the group in the player's sight, so the next group
-- command acts on it; the API selects nothing. That group then stands for the object the run
-- was anchored on, so the next set needs no reselecting by hand. Every line it prints says
-- what was asked and what was found, and a refusal says the way out.
--
-- A request is plain data, as the command line and a list link both give it:
--   index   the set's index, as a list prints it
--   indexes several sets' indexes instead, spawned together in the order given
--   entry   an object's entry naming the root, as a lookup line prints it
--   file    a root's file id, which a list link carries
--   label   what to call that root in a line, which a list link carries
--   here    true to spawn at the player rather than on the selected object
--   at      a pose to spawn at instead, as Pose gives one; with the guid of the object it was
--           read off, that object is the one an attach joins
--   group   "pivot", "first", "attach" or "nogroup"; nil is "pivot"
--   base    true to lay the root's base set under the sets, unless it is one of them
--   quiet   true when a window shows the run's progress, so the chat leaves it out
--
-- A window reads Source for the sets to show, Target for the object they may spawn on, Busy
-- for whether it may start, and Watch for the run it started; it spawns and stops through the
-- same doors as the commands.

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

--- The run going on, if any, and whether it was asked to stop. A wait for an object's record:
-- { what it waits for, what a stop leaves standing or nil, stop }. The group the last run
-- selected and the object that run was anchored on: { leader, guid, pose }.
local running, stopping, waiting, anchored

--- Who hears a run besides the chat, as a window registers: { started(total, what),
-- progress(done, total), finished(result, seconds) }, each optional.
local watchers = {}

local function tell(name, ...)
	for _, watcher in ipairs(watchers) do
		if watcher[name] then
			watcher[name](...)
		end
	end
end

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

--- How long since a moment on the client's clock, as a line says it.
local function since(moment)
	return ("%.1f s"):format(Client.Now() - moment)
end

local function objects(count)
	return count == 1 and "1 object" or count .. " objects"
end

--- Why nothing new can start, or nil.
local function busy()
	if waiting then
		return ("Furnish is waiting for %s; %s ends it"):format(waiting.what, Chat.Typed("stop"))
	elseif running and not running.Done() then
		return "Furnish is still spawning; " .. Chat.Typed("stop") .. " ends it"
	end
	return nil
end

--- The selected object's pose, or nil and the way out.
-- @param what what the selection is for, as the way out names it: "the WMO"
-- @param otherwise another way out, said after selecting, or nil
local function selection(what, otherwise)
	local pose, reason = Pose.Selected()
	if not pose then
		return nil,
			("%s; select %s first, as with .gob select%s"):format(reason, what, otherwise or "")
	end
	return pose
end

--- Call fn with the selected object's pose, or say the way out. The group the last run
-- selected stands for the object that run was anchored on: Furnish selects that object again
-- and reads its record fresh, since moving the group may have moved it.
local function withSelection(what, otherwise, fn)
	local pose, reason = selection(what, otherwise)
	if pose then
		return fn(pose)
	end
	if not (anchored and Client.SelectedGroup() == anchored.leader) then
		return say(reason)
	end
	local blocked = busy()
	if blocked then
		return say(blocked)
	end
	local send
	send, reason = Client.Send()
	if not send then
		return say(reason)
	end
	local guid = anchored.guid
	local stopAwaiting
	stopAwaiting, reason = Client.AwaitRecord(guid, function(record)
		waiting = nil
		fn(Pose.OfRecord(record))
	end)
	if not stopAwaiting then
		return say(reason)
	end
	waiting = { what = "object " .. guid, stop = stopAwaiting }
	send(Commands.Select(guid), function(selected, replies)
		if not selected and waiting then
			waiting.stop()
			waiting, anchored = nil, nil
			say(
				("the group stands for object %s, but selecting it was refused: %s; select %s first"):format(
					guid,
					quote(replies),
					what
				)
			)
		end
	end)
end

--- Why an object's own sets cannot be read, or nil when it is a WMO that has them.
local function notWmo(pose, instead)
	if pose.wmo then
		return nil
	end
	return pose.name .. " is not a WMO, so it has no sets; " .. instead
end

--- The root a request names, what to call it, and the list command that shows its sets;
-- or nil and the way out. Without an entry or a file it is the selected WMO's own.
local function rootOf(request, pose)
	if request.file then
		return request.file, request.label, Chat.Typed("list")
	end
	if request.entry then
		local file = Sets.OfEntry(request.entry)
		if not file then
			return nil,
				("object %d is not a WMO Furnish has sets for; check the entry on its lookup line"):format(
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
		return Group.Pivot, "led by a pivot, one extra invisible object"
	elseif word == "first" then
		return Group.First, "led by the set's first object"
	elseif word == "nogroup" then
		return Group.None, "ungrouped"
	end
	if not pose.guid then
		return nil, "a spawn at your feet has no selected gob to include in the group"
	end
	if pose.groupLeader ~= 0 then
		return pose.groupLeader, "joining the group " .. pose.name .. " is in"
	end
	return pose.guid, "led by " .. pose.name
end

--- What a line calls the model a display draws: its name, the pivot, or what it is not.
local function modelOf(display)
	if display == Furnish.Settings.marker then
		return "the pivot"
	end
	return Console.ModelName(display) or "a model the client's catalogue does not name"
end

--- Report a finished run, how long it took, and select its group so the next group
-- command acts on it, the group standing for the object the run was anchored on, if any.
local function finish(result, started, anchor)
	local doodads = #result.spawned - (result.pivot and 1 or 0)
	local pivot = result.pivot and ", and the pivot," or ""
	if result.deleted == #result.spawned then
		say(("stopped, and deleted the %s spawned"):format(objects(result.deleted)))
	elseif result.deleted then
		say(
			("stopped, and deleted %d of the %s spawned"):format(
				result.deleted,
				objects(#result.spawned)
			)
		)
	elseif result.aborted then
		say(
			("stopped: %d of %d spawned%s in %s"):format(
				doodads,
				result.total,
				pivot,
				since(started)
			)
		)
	else
		say(("done: %d of %d spawned%s in %s"):format(doodads, result.total, pivot, since(started)))
	end
	for _, refusal in ipairs(result.refused) do
		say(("%s was refused: %s"):format(modelOf(refusal.display), quote(refusal.messages)))
	end
	for _, miss in ipairs(result.unjoined) do
		say(
			("%s, object %s, spawned but did not join the group: %s"):format(
				modelOf(miss.display),
				miss.guid,
				quote(miss.messages)
			)
		)
	end
	if result.joined > 0 and not result.deleted then
		Client.Send()(Commands.SelectGroup(result.leader), nil, true)
		anchored = anchor
				and { leader = tostring(result.leader), guid = tostring(anchor.guid), pose = anchor }
			or nil
	end
end

local function hooks(about)
	local told, started = 0, Client.Now()
	return {
		progress = function(done, total)
			tell("progress", done, total)
			if not about.quiet and done < total and done - told >= 10 then
				told = done
				say(("%d of %d"):format(done, total))
			end
		end,
		finished = function(result)
			finish(result, started, about.anchor)
			tell("finished", result, Client.Now() - started)
		end,
	}
end

--- Whether this session has reminded the player that highlighting can crash the game.
local reminded = false

--- Send a run, having said what it is.
-- @param target the pose the rows are placed at
-- @param about { what, the set as a line names it; where, "on <WMO>" or "at your feet";
--   lead, how the group is led as groupOf says it; anchor, the selected object the run is
--   anchored on, or nil; quiet, true when a window shows the progress instead }
local function start(rows, target, group, about)
	local send, reason = Client.Send()
	if not send then
		return say(reason)
	end
	say(("spawning %s %s, %s"):format(about.what, about.where, about.lead))
	-- A run ends by selecting its group, and highlighting too many objects can crash the client.
	-- Whether it is on is the player's to decide, so the first run of a session only reminds them.
	if not reminded then
		reminded = true
		say("highlighting too many objects can crash the game; .toggle highlight off turns it off")
	end
	-- Started now, so a refusal at the end of the run can name its model.
	Console.NameModels(function() end)
	-- Told before the run, which may answer whole before Spawn returns.
	tell("started", #rows, about.what)
	local handle, refused = Furnish.Spawn(
		rows,
		target.position,
		target.rotation,
		target.scale,
		group,
		send,
		hooks(about)
	)
	if not handle then
		tell("finished", nil, 0)
		return say("nothing was sent: " .. refused)
	end
	running, stopping = handle, false
end

--- The selected object's pose, any object, or nil and why there is none. While the group the
-- last run selected stays selected, it is the object that run was on.
local function selectedPose()
	local pose, reason = Pose.Selected()
	if not pose and anchored and Client.SelectedGroup() == anchored.leader then
		return anchored.pose
	end
	return pose, reason
end

--- A WMO's sets as a window lists them, under the name it goes by; or nil and the reason.
local function described(file, name, drawn)
	local loaded, why = Reader.Load()
	if not loaded then
		return nil, why
	end
	local sets = Sets.OfFile(file)
	if not sets then
		return nil, name .. " has no doodad sets in Furnish's data"
	end
	local placed = {}
	for _, id in ipairs(drawn or {}) do
		placed[id] = true
	end
	local shown = {}
	for i, set in ipairs(sets) do
		shown[i] = {
			id = set.id,
			index = set.index,
			name = setName(set),
			count = set.count,
			canonical = set.name,
			placed = placed[set.id] == true,
		}
	end
	return { name = name, file = file, blank = Sets.IsBlank(file), sets = shown }
end

--- Where a window takes its sets from: a root it names, or the selected WMO.
-- @param of nil for the selection; { file, name } for a root by its file id and what to call it;
--   or { entry } for the WMO a gameobject's entry names, the number a lookup line prints. Any
--   of them may carry a placement, a doodad as Commands.SelectedDoodad reads it, whose sets are
--   marked placed; with an entry, the doodad names the source, or else its WMO's file as the
--   client's catalogue names it once Console.NameModels has ended, or else the entry itself
-- @return { name, file, blank, sets }, each set { id, index, name, count, canonical, placed }, the
--   name as a line shows it, canonical as the file spells it, empty for the base set, and placed
--   true for a set the doodad shows now; blank is true for a WMO Epsilon emptied, which always gets its
--   base set; or nil and why there are none
function Console.Source(of)
	of = of or {}
	local placement = of.placement
	local drawn = placement and Sets.OfPlacement(placement.map, placement.uid) or nil
	if of.file then
		return described(of.file, of.name, drawn)
	end
	if of.entry then
		local file, reason = Sets.OfEntry(of.entry)
		if not file then
			return nil, reason
		end
		local name = placement and Client.ModelName(placement.name)
			or Client.FileName(file)
			or ("object %d"):format(of.entry)
		return described(file, name, drawn)
	end
	local pose, reason = selectedPose()
	if not pose then
		return nil, reason
	end
	if not pose.wmo then
		return nil, pose.name .. " is not a WMO, so it has no sets"
	end
	return described(pose.file, pose.name, drawn)
end

--- Every file the catalogue is asked to name, as a set, gathered once: each model the data's sets
-- place and each WMO root it has sets for.
local wantedFiles

--- Learn the name of every model the data places and every WMO it has sets for, by one walk of
-- the client's own catalogue a session, then call done; at once where the walk has ended.
function Console.NameModels(done)
	if not Reader.Load() then
		return done()
	end
	if not wantedFiles then
		wantedFiles = {}
		for _, file in pairs(Reader.ModelFiles()) do
			wantedFiles[file] = true
		end
		for file in pairs(Reader.Roots()) do
			wantedFiles[file] = true
		end
	end
	Client.NameFiles(wantedFiles, done)
end

--- Whether the walk Console.NameModels starts has ended, so a model it did not name has none.
function Console.ModelsNamed()
	return Client.FilesNamed()
end

--- The name of the model a display draws, as the client's catalogue spells it; nil until
-- Console.NameModels has ended, or where the catalogue does not carry the file.
function Console.ModelName(display)
	local file = Reader.Load() and Reader.ModelFile(display)
	return file and Client.FileName(file) or nil
end

--- The WMOs Furnish has sets for whose names hold some words, as the client's own catalogue of
-- gameobject displays names them; each WMO once, however many displays draw it.
-- @return a list of { file, name, sets, blank }, sets being how many it has, those with the most
--   sets first and then by name, since a WMO with one set has only the base set it draws already
function Console.Find(words)
	if not Reader.Load() then
		return {}
	end
	local found, seen = {}, {}
	for _, row in ipairs(Client.SearchDisplays(words)) do
		local sets = not seen[row.file] and Sets.OfFile(row.file)
		seen[row.file] = true
		if sets then
			found[#found + 1] = {
				file = row.file,
				name = Client.ModelName(row.name),
				sets = #sets,
				blank = Sets.IsBlank(row.file),
			}
		end
	end
	table.sort(found, function(a, b)
		if a.sets ~= b.sets then
			return a.sets > b.sets
		end
		return a.name < b.name
	end)
	return found
end

--- What a window's sets may spawn on and whose group they may join: the selected object's
-- pose, whatever it is, with its name, guid, groupLeader and canEdit beside it; or nil and
-- why nothing is selected.
function Console.Target()
	return selectedPose()
end

--- Why nothing new can start, or nil.
function Console.Busy()
	return busy()
end

--- Turn the client's highlighting of the selection on or off, as Tiler and ObjectMover do.
function Console.ToggleHighlight()
	local send, reason = Client.Send()
	if not send then
		return say(reason)
	end
	send(Commands.Highlight(), nil, true)
end

--- Hear every run besides the chat.
-- @param watcher { started(total, what), progress(done, total), finished(result, seconds) },
--   each optional; finished has no result for a run refused before anything was sent
-- @return a function that stops hearing
function Console.Watch(watcher)
	watchers[#watchers + 1] = watcher
	return function()
		for i, known in ipairs(watchers) do
			if known == watcher then
				table.remove(watchers, i)
				return
			end
		end
	end
end

--- Print a root's sets, each a link that spawns it; pose is the selected WMO's, or nil
-- where the request names an entry.
local function list(request, pose)
	local file, label = rootOf(request, pose)
	if not file then
		return say(label)
	end
	local sets, reason = setsOf(file, label)
	if not sets then
		return say(reason)
	end
	local carried = table.concat({ request.group or "pivot", request.base and "base" or "" }, ":")
	-- A menu of buttons, one a set; its index and its objects are in its tooltip.
	local buttons = {}
	for i, set in ipairs(sets) do
		buttons[i] = Chat.Link(table.concat({ file, set.index, carried, label }, ":"), setName(set))
	end
	say(("%s has %d sets:"):format(label, #sets))
	for _, line in ipairs(Chat.Menu(buttons)) do
		Chat.Line(line)
	end
end

--- Print a root's sets, each a link that spawns it.
-- @param request { entry } for an object's sets, or {} for the selected WMO's; group
--   and base ride along on every link
function Console.List(request)
	local loaded, reason = Reader.Load()
	if not loaded then
		return say(reason)
	end
	if request.entry then
		return list(request, nil)
	end
	withSelection("the WMO", nil, function(pose)
		local wrong = notWmo(pose, Chat.Typed("list <entry>") .. " lists another object's")
		if wrong then
			return say(wrong)
		end
		list(request, pose)
	end)
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
	tooltip:AddLine("Click: spawn the set onto the selected gob", 1, 1, 1)
	tooltip:AddLine("Ctrl-click: spawn the set at your feet", 1, 1, 1)
end

--- Fill a tooltip for the button on a WMO's doodad line.
-- @param tooltip a tooltip owned and empty
function Console.DescribeImport(tooltip)
	tooltip:SetText("Furnish", 1, 1, 1)
	tooltip:AddLine(
		"Import this WMO and spawn the sets it shows now, grouped on it",
		0.62,
		0.62,
		0.62,
		true
	)
end

--- The rows of several sets in the order given, and how a line names them, as "Base and Full
-- (sets 0 and 1, 3 objects)"; or nil and the reason.
local function gather(chosen)
	local rows, names, indexes = {}, {}, {}
	for i, set in ipairs(chosen) do
		local own, missing = Rows.OfSet(set.id)
		if not own then
			return nil, missing
		end
		rows = Rows.Union(rows, own)
		names[i], indexes[i] = setName(set), set.index
	end
	return rows,
		("%s (%s %s, %s)"):format(
			table.concat(names, " and "),
			#chosen == 1 and "set" or "sets",
			table.concat(indexes, " and "),
			objects(#rows)
		)
end

--- Spawn sets; pose is the selected object's, or nil where they go at the player from a named
-- root and join no object's group.
local function spawnOn(request, pose)
	local target, reason = pose, nil
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
	local chosen, hasBase = {}, false
	for _, index in ipairs(request.indexes or { request.index }) do
		local set = Sets.Pick(file, index)
		if not set then
			return say(("%s has no set %d; %s shows its %d"):format(label, index, listing, #sets))
		end
		chosen[#chosen + 1] = set
		hasBase = hasBase or set.index == 0
	end
	-- A WMO Epsilon emptied draws no base set of its own, so one standing as the target gets
	-- it, under the rest and once.
	local base = request.base or (not request.here and Sets.IsBlank(pose.file))
	if base and not hasBase and sets[1].index == 0 then
		table.insert(chosen, 1, sets[1])
	end
	local rows, what = gather(chosen)
	if not rows then
		return say(what)
	end
	-- The set is named by its WMO wherever it is not going onto that WMO.
	if request.here or label ~= pose.name then
		what = label .. "'s " .. what
	end
	local group, lead = groupOf(request, pose)
	if not group then
		return say(lead)
	end
	local spot = target.position
	start(rows, target, group, {
		what = what,
		where = request.here and "at your feet"
			or pose.name and ("on " .. pose.name)
			or ("at %.1f, %.1f, %.1f"):format(spot.x, spot.y, spot.z),
		lead = lead,
		anchor = pose and pose.guid and pose or nil,
		quiet = request.quiet,
	})
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
	-- A pose given is the target, and the object it was read off, if any, is the one an attach
	-- joins; its root must be named, since a pose names none.
	local named = request.entry or request.file
	if request.at then
		if not named then
			return say("a position names no WMO; name the one whose sets to spawn")
		end
		return spawnOn(request, request.at)
	end
	-- The selected object is the target unless the set goes at the player, and any object
	-- will do. It must be a WMO only where the set is its own, read off it because
	-- neither a link nor an entry names one; and it leads the group a set attaches to.
	if request.here and named and request.group ~= "attach" then
		return spawnOn(request, nil)
	end
	local what = not named and "the WMO"
		or request.here and "the object whose group to join"
		or "the object to spawn on"
	local otherwise = request.here and not named and request.group ~= "attach"
	withSelection(
		what,
		otherwise and (", or name it, as " .. Chat.Typed("3 here <entry>")) or nil,
		function(pose)
			local wrong = not named
				and notWmo(pose, "name one, as " .. Chat.Typed("3 from <entry>"))
			if wrong then
				return say(wrong)
			end
			spawnOn(request, pose)
		end
	)
end

--- The sets an imported WMO showed as a doodad, beyond the base set it shows
-- itself; with base, the base set as well, whether the doodad showed it or not.
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

--- Import a doodad, then spawn on it the sets it showed, or the ones named,
-- grouped on the WMO it now is unless a word says otherwise.
-- @param request uid, the doodad's unique id, or nil for the selected doodad; only, true to
--   import it and spawn nothing, leaving it selected as the WMO it now is; indexes, the sets to
--   spawn in place of the ones it showed, the base among them only with base; group and base,
--   as for a spawn
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

	-- What may still answer: the import's line and the record of the object it made. A stop
	-- silences both.
	local stopped, heard = false, false
	local stopHearing, stopAwaiting
	waiting = {
		what = "the imported object",
		left = "an import already sent stands",
		stop = function()
			stopped = true
			stopHearing()
			if stopAwaiting then
				stopAwaiting()
			end
		end,
	}

	local function furnish(record, ids, guid, model)
		if request.only then
			return say(("imported %s as object %s"):format(model, guid))
		end
		local pose = Pose.OfRecord(record)
		if not pose.wmo then
			return say(
				("imported %s as object %s, which is not a WMO and has no sets"):format(model, guid)
			)
		end
		if request.indexes then
			ids = {}
			for _, index in ipairs(request.indexes) do
				local set = Sets.Pick(pose.file, index)
				if set then
					ids[#ids + 1] = set.id
				end
			end
		end
		local chosen = ids and placed(pose, ids, request.base) or {}
		if #chosen == 0 then
			return say(
				("imported %s as object %s; %s"):format(
					model,
					guid,
					ids and "the doodad drew only its base set, which the gob draws itself"
						or (
							"the doodad drew no set Furnish knows; "
							.. Chat.Typed("list")
							.. " lists the WMO's own"
						)
				)
			)
		end
		local rows, what = gather(chosen)
		if not rows then
			return say(what)
		end
		local group, lead = groupOf({ group = request.group or "attach" }, pose)
		start(rows, pose, group, {
			what = what,
			where = "on " .. pose.name,
			lead = lead,
			anchor = pose,
			quiet = request.quiet,
		})
	end

	-- The import selects the object but pushes no record of it, and the record carries the
	-- pose; selecting it again has the server push one.
	local function imported(uid, guid, model)
		if stopped or heard then
			return
		end
		heard = true
		stopHearing()
		local ids = Sets.OfPlacement(map, tonumber(uid))
		stopAwaiting, reason = Client.AwaitRecord(guid, function(record)
			waiting = nil
			furnish(record, ids, guid, model)
		end)
		if not stopAwaiting then
			waiting = nil
			return say(reason)
		end
		send(Commands.Select(guid), function(selected, replies)
			if not selected and waiting then
				waiting.stop()
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
	end

	-- The server names the object an import made in one line, sent in the command's reply or
	-- as a plain system line after it, so both are heard and the first is taken. An import by
	-- unique id takes only its own doodad's line.
	stopHearing = Client.OnSystemLine(function(line)
		local uid, guid, model = Commands.Imported({ line })
		if uid and (request.uid == nil or uid == tostring(request.uid)) then
			imported(uid, guid, model)
		end
	end)
	send(Commands.Import(request.uid), function(success, messages)
		if stopped or heard then
			return
		end
		local uid, guid, model = Commands.Imported(messages)
		if uid then
			return imported(uid, guid, model)
		end
		if not success then
			waiting.stop()
			waiting = nil
			say("nothing was imported: " .. quote(messages))
		end
	end)
end

--- Stop spawning. With delete, also delete what the run spawned.
function Console.Stop(delete)
	if waiting then
		local left = waiting.left
		waiting.stop()
		waiting = nil
		return say("stopped; nothing was spawned" .. (left and ", and " .. left or ""))
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
