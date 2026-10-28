-- What the commands do: list a WMO's sets, spawn one, import a doodad, and stop.
--
-- This is the surface, not the API. It holds the one run, reads what a merge joins off the selection,
-- and closes a grouped run by selecting the group in the player's sight, so the next group
-- command acts on it; the API selects nothing. That group then stands for the object the run
-- was anchored on, so the next set needs no reselecting by hand. Every line it prints says
-- what was asked and what was found, and a refusal says the way out. A run that ends whole, at
-- scale 1 with no roll or pitch, led by its pivot or merged into a WMO that stood alone and owns
-- its sets, leaves a blueprint name on offer while its group stays selected; saving it is the
-- player's, and nothing here sends it.
--
-- A request is plain data, as the command line and a list link both give it:
--   index   the set's index, as a list prints it
--   indexes several sets' indexes instead, spawned together in the order given
--   entry   an object's entry naming the root, as a lookup line prints it
--   file    a root's file id, which a list link carries
--   label   what to call that root in a line, which a list link carries
--   here    true to spawn at the player rather than on the selected object
--   at      a pose to spawn at instead, as Pose gives one, its numbers alone: a merge joins the
--           group of whatever is selected when the spawn runs, gob or group
--   group   a word from Console.GROUPS; nil is Console.GROUPED
--   base    true to lay the root's base set under the sets, unless it is one of them
--   quiet   true when a window shows the run's progress, so the chat leaves it out
--   ways    how the door the request came through names a way out, as a line suggests one:
--           { stop(), list(entry), from(), here() }, each a function answering the words, list's
--           entry nil for the selected WMO's; a way the door does not offer goes unsaid
--
-- A window reads Source for the sets to show, Selected for the object they may spawn on, Busy
-- for whether it may start, and Watch for the run it started; it spawns and stops through the
-- same doors as the commands. Each door says its own ways out, so a line never teaches a
-- command to a player using the window.

local _, Furnish = ...
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
local objects = Chat.Objects

--- How a run's objects may be grouped, in the order a window offers them: the word a request
-- says it by, the kernel's group, how a line says the run is led, and what the help says the
-- word does. A merge has no group of its own: it joins the selected gob's or group's.
Console.GROUPS = {
	{
		word = "nogroup",
		group = Group.None,
		lead = "ungrouped",
		hint = "every object stands alone",
	},
	{ word = "pivot", group = Group.Pivot, lead = "led by a pivot, one extra invisible object" },
	{
		word = "first",
		group = Group.First,
		lead = "led by the set's first object",
		hint = "the first object spawned leads, no pivot",
	},
	{ word = "merge", hint = "join the selected gob's group, no pivot" },
}

--- The grouping a request that names none gets, which is why the help gives it no word.
Console.GROUPED = "pivot"

local GROUPING = {}
for _, grouping in ipairs(Console.GROUPS) do
	GROUPING[grouping.word] = grouping
end

--- A grouping by its word, as Console.GROUPS declares it; nil is Console.GROUPED.
function Console.Grouping(word)
	return GROUPING[word or Console.GROUPED]
end

--- The run going on, if any, and whether it was asked to stop. A wait for an object's record:
-- { what it waits for, what a stop leaves standing or nil, stop }. The group the last run
-- selected and the object that run was anchored on: { leader, guid, pose }.
local running, stopping, waiting, anchored

--- The run as a window draws it: { total, done, started } while one goes, and { result, seconds,
-- offer } for the one that ended last, so a window opened in the middle of either can catch up.
-- The offer is { name, leader }, or nil where the run offers no blueprint.
local current, last

--- Who hears a run besides the chat, as a window registers: { started(total, what),
-- progress(done, total), deleting(done, total), finished(result, seconds), waiting(waits),
-- imported(uid, guid) }, each optional.
local watchers = {}

local function tell(name, ...)
	for _, watcher in ipairs(watchers) do
		if watcher[name] then
			watcher[name](...)
		end
	end
end

--- Start or end a wait for the server, and tell every watcher. A window cannot tell otherwise
-- when a wait ends: the record that ends one reaches the window's own listener first, while
-- the wait still stands.
local function wait(what)
	waiting = what
	tell("waiting", what ~= nil)
end

--- A set's name as a line shows it; the base set has none of its own.
local function setName(set)
	return Sets.IsBase(set) and "Base" or Names.Set(set.name)
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

--- A way out as a door words it, or nil where the door offers none.
-- @param ways a request's ways, or nil
-- @param name which way: "stop", "list", "from" or "here"
local function way(ways, name, ...)
	local words = ways and ways[name]
	return words and words(...) or nil
end

--- A line, with a way out after it where the door offers one.
local function offering(text, wayOut)
	return wayOut and text .. "; " .. wayOut or text
end

--- Why nothing new can start, or nil; with the way that ends it, where the door offers one.
local function busy(ways)
	local doing
	if waiting then
		doing = "waiting for " .. waiting.what
	elseif running and not running.Done() then
		doing = current and current.deleting and "still deleting what it spawned"
			or "still spawning"
	else
		return nil
	end
	local stop = way(ways, "stop")
	return offering(Furnish.NAME .. " is " .. doing, stop and stop .. " ends it")
end

--- Whether nothing is under way; says what is, where something is.
local function idle(ways)
	local blocked = busy(ways)
	if blocked then
		say(blocked)
	end
	return not blocked
end

--- The server's door, or nil having said why it is shut.
local function sender()
	local send, reason = Client.Send()
	if not send then
		say(reason)
	end
	return send
end

--- Whether a spawn or an import may begin: nothing else under way, the player allowed to spawn
-- here, the data loaded and the server's door open. Says why not; answers the door when it may.
local function ready(ways)
	if not (idle(ways) and Client.CanSpawn()) then
		return nil
	end
	local loaded, reason = Reader.Load()
	if not loaded then
		return say(reason)
	end
	return sender()
end

--- Whether the group the last run selected is still selected, standing for the object that run
-- was anchored on.
local function anchorHeld()
	return anchored ~= nil and Client.SelectedGroup() == anchored.leader
end

--- Select an object by its GUID and hand onRecord the record the server pushes for it; refused,
-- end the wait and call refused(replies). With waitFor, the wait starts here, before anything is
-- sent; without, the caller's wait stands already.
-- @return a function that stops waiting for the record; or nil and the reason
local function reselect(send, guid, onRecord, refused, waitFor)
	local stopAwaiting, reason = Client.AwaitRecord(guid, function(record)
		wait(nil)
		onRecord(record)
	end)
	if not stopAwaiting then
		return nil, reason
	end
	if waitFor then
		wait({ what = waitFor, stop = stopAwaiting })
	end
	send(Commands.Select(guid), function(selected, replies)
		if not selected and waiting then
			waiting.stop()
			wait(nil)
			refused(replies)
		end
	end)
	return stopAwaiting
end

--- The selected object's pose, or nil and the way out.
-- @param what what the selection is for, as the way out names it: "the WMO"
-- @param otherwise another way out, said after selecting, or nil
local function selection(what, otherwise)
	local pose, reason = Pose.Selected()
	if not pose then
		return nil,
			("%s; select %s first, as with %s%s"):format(
				reason,
				what,
				Commands.Typed(Commands.Select()),
				otherwise or ""
			)
	end
	return pose
end

--- Call fn with the selected object's pose, or say the way out. The group the last run
-- selected stands for the object that run was anchored on: Furnish selects that object again
-- and reads its record fresh, since moving the group may have moved it.
-- @param ways the request's ways out
local function withSelection(ways, what, otherwise, fn)
	local pose, reason = selection(what, otherwise)
	if pose then
		return fn(pose)
	end
	if not anchorHeld() then
		return say(reason)
	end
	local send = idle(ways) and sender()
	if not send then
		return
	end
	local guid = anchored.guid
	local stopAwaiting
	stopAwaiting, reason = reselect(send, guid, function(record)
		fn(Pose.OfRecord(record))
	end, function(replies)
		anchored = nil
		say(
			("the group stands for object %s, but selecting it was refused: %s; select %s first"):format(
				guid,
				quote(replies),
				what
			)
		)
	end, "object " .. guid)
	if not stopAwaiting then
		return say(reason)
	end
end

--- Why an object's own sets cannot be read, or nil when it is a WMO that has them; instead,
-- if given, says what to do.
local function notWmo(pose, instead)
	if pose.wmo then
		return nil
	end
	return pose.name .. " is not a WMO, so it has no sets" .. (instead and "; " .. instead or "")
end

--- The root a request names, what to call it, and the way to list its sets, where the request's
-- door offers one; or nil and the way out. Without an entry or a file it is the selected WMO's
-- own.
local function rootOf(request, pose)
	if request.file then
		return request.file, request.label, way(request.ways, "list")
	end
	if request.entry then
		local file = Sets.OfEntry(request.entry)
		if not file then
			return nil,
				("object %d is not a WMO Furnish has sets for; check the entry on its lookup line"):format(
					request.entry
				)
		end
		return file, "object " .. request.entry, way(request.ways, "list", request.entry)
	end
	return pose.file, pose.name, way(request.ways, "list")
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
	local grouping = Console.Grouping(request.group)
	if grouping.group then
		return grouping.group, grouping.lead
	end
	if not (pose and pose.guid) then
		return nil, "no gob is selected whose group to merge into"
	end
	-- Refused before anything spawns; the run still stops if the server refuses a join.
	if not Client.CanEdit(pose) then
		return nil,
			("you can't edit %s in this phase, so the set can't merge into its group"):format(
				pose.name
			)
	end
	if pose.groupLeader ~= 0 then
		return pose.groupLeader, "joining the group " .. pose.name .. " is in"
	end
	return pose.guid, "led by " .. pose.name
end

--- The blueprint name a run is to offer once it ends whole, or nil: at scale 1 with no roll or
-- pitch, as the server reads them, either led by its pivot, named after the source as a set
-- apart, or merged into a gob that stood alone, owns every set spawned and stands where they
-- were placed, named after that gob. Placed anywhere else, the gob and its sets are not the WMO
-- furnished, and the name would say they were.
-- @param word the request's group word, nil being Console.GROUPED
-- @param destination the pose the rows are placed at
-- @param owner the gob a merge joins, as groupOf reads it
-- @param label the source as a line names it
-- @param chosen the sets spawned, each { index, id, name }
local function offered(word, destination, owner, label, chosen)
	local rotation = destination.rotation or {}
	local plain = Commands.IsUnit(destination.scale or 1)
		and Commands.IsLevel(rotation.roll or 0)
		and Commands.IsLevel(rotation.pitch or 0)
	if not plain then
		return nil
	end
	local sets, ids = {}, {}
	for i, set in ipairs(chosen) do
		sets[i] = set
	end
	table.sort(sets, function(a, b)
		return a.index < b.index
	end)
	for i, set in ipairs(sets) do
		ids[i] = set.id
	end
	if Console.Grouping(word).group == Group.Pivot then
		return Names.Blueprint(label, sets, true)
	end
	if word ~= "merge" or not owner or owner.group or owner.groupLeader ~= 0 or not owner.file then
		return nil
	end
	if not Pose.Same(destination, owner) then
		return nil
	end
	if #Sets.Named(owner.file, ids) < #ids then
		return nil
	end
	return Names.Blueprint(owner.name, sets, false)
end

--- What a blueprint offer says, in the window and in chat alike: the question, why it is worth
-- it, and what a click on it does.
Console.OFFER = {
	title = "Save as a blueprint?",
	why = "Spawn it again instantly with one command.",
	click = "Click: put it in the chat box; Enter sends it",
}

--- What a chat line's blueprint button carries before the name.
local OFFERED = "blueprint:"

--- Whether a run ended whole: nothing stopped, refused, left out of the group or deleted.
local function whole(result)
	return not result.aborted
		and not result.deleted
		and #result.refused == 0
		and #result.unjoined == 0
		and result.leader ~= nil
		and result.joined > 0
end

--- What a line calls the model a display draws: its name, or what it is not.
local function modelOf(display)
	return Console.ModelName(display) or "a model the client's catalogue does not name"
end

--- How a run ended, as one word every surface says it by: "deleted" where a stop deleted all it
-- spawned, "part deleted" where it deleted some, "refused" where the server would not add an
-- object to the group, "stopped", or "done".
-- @param result what Furnish.Spawn's finished hook is handed
function Console.Ending(result)
	if result.deleted then
		return result.deleted == #result.spawned and "deleted" or "part deleted"
	elseif result.joinRefused then
		return "refused"
	elseif result.aborted then
		return "stopped"
	end
	return "done"
end

--- Report a finished run, how long it took, and select its group so the next group
-- command acts on it, the group standing for the object the run was anchored on, if any.
local function finish(result, started, anchor)
	local ending = Console.Ending(result)
	local spawned = ("%d of %d spawned%s in %s"):format(
		result.placed,
		result.total,
		result.pivot and ", and the pivot," or "",
		since(started)
	)
	if ending == "deleted" then
		say(("stopped, and deleted the %s spawned"):format(objects(result.deleted)))
	elseif ending == "part deleted" then
		say(
			("stopped, and deleted %d of the %s spawned"):format(
				result.deleted,
				objects(#result.spawned)
			)
		)
	elseif ending == "refused" then
		say("stopped, as the server would not add an object to the group: " .. spawned)
	elseif ending == "stopped" then
		say("stopped: " .. spawned)
	else
		say("done: " .. spawned)
	end
	for _, refusal in ipairs(result.refused) do
		local what = refusal.pivot and "the pivot" or modelOf(refusal.display)
		say(("%s was refused: %s"):format(what, quote(refusal.messages)))
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

local stride = Chat.Stride

local function hooks(about)
	local told, cleaned, started = 0, 0, Client.Now()
	return {
		progress = function(done, total)
			if current then
				current.done = done
			end
			tell("progress", done, total)
			if not about.quiet and done < total and done - told >= stride(total) then
				told = done
				say(("%d of %d"):format(done, total))
			end
		end,
		deleting = function(done, total)
			if current then
				current.deleting = current.deleting or { stopping = false }
				current.deleting.done, current.deleting.total = done, total
			end
			tell("deleting", done, total)
			if not about.quiet and done < total and done - cleaned >= stride(total) then
				cleaned = done
				say(("deleted %d of %d"):format(done, total))
			end
		end,
		finished = function(result)
			finish(result, started, about.anchor)
			local offer = about.blueprint
					and whole(result)
					and { name = about.blueprint, leader = tostring(result.leader) }
				or nil
			current, last =
				nil, { result = result, seconds = Client.Now() - started, offer = offer }
			-- A window draws its own offer; in chat, the name is a button.
			if offer and not about.quiet then
				say(Console.OFFER.title .. " " .. Chat.Link(OFFERED .. offer.name, offer.name))
			end
			tell("finished", result, last.seconds)
		end,
	}
end

--- Whether this session has reminded the player that highlighting can crash the game.
local reminded = false

--- Send a run, having said what it is.
-- @param destination the pose the rows are placed at
-- @param about { what, the set as a line names it; where, "on <WMO>" or "at your feet";
--   lead, how the group is led as groupOf says it; anchor, the selected object the run is
--   anchored on, or nil; quiet, true when a window shows the progress instead; blueprint, the
--   name to offer if the run ends whole, or nil }
local function start(rows, destination, group, about)
	local send = sender()
	if not send then
		return
	end
	say(("spawning %s %s, %s"):format(about.what, about.where, about.lead))
	-- A run ends by selecting its group, and highlighting too many objects can crash the client.
	-- Whether it is on is the player's to decide, so the first run of a session only reminds them.
	if not reminded then
		reminded = true
		say(
			("%s; %s turns it off"):format(
				Chat.HIGHLIGHT:lower(),
				Commands.Typed(Commands.Highlight("off"))
			)
		)
	end
	-- Started now, so a refusal at the end of the run can name its model.
	Console.NameModels(function() end)
	-- Told before the run, which may answer whole before Spawn returns.
	current, last = { total = #rows, done = 0, started = Client.Now() }, nil
	tell("started", #rows, about.what)
	local handle, refused = Furnish.Spawn(
		rows,
		destination.position,
		destination.rotation,
		destination.scale,
		group,
		send,
		hooks(about)
	)
	if not handle then
		current = nil
		tell("finished", nil, 0)
		return say("nothing was sent: " .. refused)
	end
	running, stopping = handle, false
end

--- The selected object's pose, any object, or nil and why there is none. While the group the
-- last run selected stays selected, it is the object that run was on.
local function selectedPose()
	local pose, reason = Pose.Selected()
	if not pose and anchorHeld() then
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
	local sets, none = setsOf(file, name)
	if not sets then
		return nil, none
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
	local wrong = notWmo(pose)
	if wrong then
		return nil, wrong
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
		-- Read raw, since only the count is wanted and most files the catalogue names have none.
		local sets = not seen[row.file] and Reader.Sets(row.file)
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

--- The selected object's pose, whatever it is, with its name, guid, groupLeader and canEdit
-- beside it; or nil and why nothing is selected. A window reads it for its source, as one source
-- of a destination's numbers, and for the group a merge would join.
function Console.Selected()
	return selectedPose()
end

--- The selected group, which a merge joins and a destination may take its numbers from once,
-- never by following it: its pose as Pose.OfGroup gives it. Nil when no group is selected, when
-- the group is the one Furnish's last run made, which stands for the object that run was on,
-- or when its leader's record has not arrived yet.
function Console.Group()
	if anchorHeld() then
		return nil
	end
	local leader = Client.SelectedGroupLeader()
	return leader and Pose.OfGroup(leader) or nil
end

--- The run going on, { total, done, started }, or nil; and the one that ended last,
-- { result, seconds, offer }, or nil. A window that hears runs only while it shows reads these
-- as it opens.
function Console.Run()
	return current, last
end

--- The blueprint name the last run offers, while that run's group is what is selected, since the
-- command that saves it saves the selection; or nil. It stands until it is dismissed or the next
-- run starts, and shows again whenever the group is selected again: as a run settles, the
-- selection passes through the objects it spawned before the group's own lands.
function Console.Offer()
	local offer = last and last.offer
	if offer and Client.SelectedGroup() == offer.leader then
		return offer.name
	end
	return nil
end

--- The command that saves the selected group as a blueprint under a name, as a player types it.
function Console.OfferCommand(name)
	return Commands.Typed(Commands.BlueprintNew(name))
end

--- The blueprint name a chat line's button carries, or nil for words no such button wrote.
function Console.OfferIn(words)
	return words:match("^" .. OFFERED .. "(.+)$")
end

--- Put the command that saves the last run's group as a blueprint in the chat box, while that
-- group is what is selected, since the command saves the selection; sending it is the player's.
function Console.PasteOffer(name)
	local offer = last and last.offer
	if not (offer and offer.name == name) then
		return say("that blueprint offer has gone with a later run")
	end
	if Client.SelectedGroup() ~= offer.leader then
		return say(
			("%s saves the run's group, so select that group first, as with %s"):format(
				name,
				Commands.Typed(Commands.SelectGroup(offer.leader))
			)
		)
	end
	Chat.Paste(Console.OfferCommand(name))
end

--- Fill a tooltip for a chat line's blueprint button.
-- @param tooltip a tooltip owned and empty
function Console.DescribeOffer(name, tooltip)
	local tip = Chat.TIP
	Chat.Tip(tooltip, Console.OFFER.title, {
		{ text = Console.OFFER.why, colour = tip.label },
		{ text = Console.OfferCommand(name) },
		{ text = Console.OFFER.click, colour = tip.click },
	})
end

--- Let the last run's blueprint offer go.
function Console.DismissOffer()
	if last then
		last.offer = nil
	end
end

--- Why nothing new can start, or nil; with ways, as a request carries them, the way that ends
-- it too.
function Console.Busy(ways)
	return busy(ways)
end

--- Turn the client's highlighting of the selection on or off, as Tiler and ObjectMover do.
function Console.ToggleHighlight()
	local send = sender()
	if send then
		send(Commands.Highlight(), nil, true)
	end
end

--- Hear every run besides the chat.
-- @param watcher { started(total, what), progress(done, total), deleting(done, total),
--   finished(result, seconds), waiting(waits), imported(uid, guid) }, each optional; deleting
--   is told as a stopped run's cleanup deletes, finished has no result for a run refused before
--   anything was sent, waiting is told whenever a wait for the server starts or ends, and
--   imported once the server names the object an import made
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

--- The words a list's button for a set carries, which Console.LinkRequest reads back: the
-- root's file, the set's index, the group and base words the list was asked with, and what to
-- call the root.
local function linkWords(file, set, request, label)
	local base = request.base and "base" or ""
	return table.concat({ file, set.index, request.group or Console.GROUPED, base, label }, ":")
end

--- The request a list's button carries, as a click spawns it, or nil for words no list wrote.
function Console.LinkRequest(words)
	local file, index, group, base, label = words:match("^(%d+):(%d+):(%a+):(%a*):(.*)$")
	if not file then
		return nil
	end
	return {
		file = tonumber(file),
		index = tonumber(index),
		group = group,
		base = base == "base",
		label = label,
	}
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
	-- A menu of buttons, one a set; its index and its objects are in its tooltip.
	local buttons = {}
	for i, set in ipairs(sets) do
		buttons[i] = Chat.Link(linkWords(file, set, request, label), setName(set))
	end
	say(("%s has %s:"):format(label, Chat.Count(#sets, "set")))
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
	local listing = way(request.ways, "list", "<entry>")
	withSelection(request.ways, "the WMO", nil, function(pose)
		local wrong = notWmo(pose, listing and listing .. " lists another object's")
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
	if not Sets.IsBase(set) then
		about = set.name .. ", " .. about
	end
	local said = {}
	if request.group ~= Console.GROUPED then
		said[#said + 1] = request.group
	end
	if request.base then
		said[#said + 1] = "base"
	end
	local tip = Chat.TIP
	Chat.Tip(tooltip, setName(set), {
		{ text = about, colour = tip.label },
		#said > 0 and { text = "with " .. table.concat(said, " and "), colour = tip.label } or {},
		{ text = "Click: spawn on the selected gob", colour = tip.click },
		{ text = "Ctrl-click: spawn at your feet", colour = tip.click },
	})
end

--- What a preview of a set shows: the models it holds, each once with its count, under a name;
-- nil where it holds none the data can name.
-- @param id the set's id
-- @param name what to call it, its WMO's name before its own: "house's Full"
function Console.SetPreview(id, name)
	local models = Rows.Models(id)
	if not (models and models[1]) then
		return nil
	end
	return { kind = "models", name = name, models = models }
end

--- What a preview of a list link's set shows, as Console.SetPreview gives it; nil where the
-- link names no set the data has.
-- @param request a list link's request
function Console.LinkPreview(request)
	local set = Reader.Load() and Sets.Pick(request.file, request.index)
	if not set then
		return nil
	end
	return Console.SetPreview(set.id, ("%s's %s"):format(request.label, setName(set)))
end

--- What a preview of a WMO shows: its picture, found by the WMO file's name.
-- @param name the file's name, as the client's catalogue spells it, whole or as a line shows it
function Console.WmoPreview(name)
	return { kind = "wmo", id = 0, name = name }
end

--- Fill a tooltip for the button on a WMO's doodad line.
-- @param tooltip a tooltip owned and empty
function Console.DescribeImport(tooltip)
	Chat.Tip(tooltip, Furnish.NAME, {
		{ text = "Click: import this WMO and spawn its sets on it", colour = Chat.TIP.click },
	})
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
		for _, row in ipairs(own) do
			rows[#rows + 1] = row
		end
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

--- Spawn sets at a destination, a pose's numbers. Selected is the selected object, or nil: the
-- group a merge joins, the object the run's group stands for once it ends, and, where the
-- request gives no position, the object the sets go onto and whose root they may be.
local function spawnOn(request, destination, selected)
	local onto = not (request.here or request.at) and selected or nil
	local reason
	if request.here then
		destination, reason = Pose.Here()
		if not destination then
			return say(reason)
		end
	end
	local file, label, listing = rootOf(request, selected)
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
			local shows = listing and ("%s shows its %d"):format(listing, #sets)
			return say(offering(("%s has no set %d"):format(label, index), shows))
		end
		chosen[#chosen + 1] = set
		hasBase = hasBase or Sets.IsBase(set)
	end
	-- A WMO Epsilon emptied draws no base set of its own, so one the sets go onto gets it, under
	-- the rest and once.
	local base = request.base or (onto and Sets.IsBlank(onto.file))
	if base and not hasBase and Sets.IsBase(sets[1]) then
		table.insert(chosen, 1, sets[1])
	end
	local rows, what = gather(chosen)
	if not rows then
		return say(what)
	end
	-- The set is named by its WMO wherever it is not going onto that WMO, or a copy of it.
	if not (onto and Sets.Same(onto.file, file)) then
		what = label .. "'s " .. what
	end
	local group, lead = groupOf(request, selected)
	if not group then
		return say(lead)
	end
	local spot = destination.position
	start(rows, destination, group, {
		what = what,
		where = request.here and "at your feet"
			or onto and ("on " .. onto.name)
			or ("at %.1f, %.1f, %.1f"):format(spot.x, spot.y, spot.z),
		lead = lead,
		anchor = selected and selected.guid and selected or nil,
		quiet = request.quiet,
		blueprint = offered(request.group, destination, selected, label, chosen),
	})
end

--- Spawn the one gob an entry names where the player stands, as a typed `.gob spawn` does, its
-- reply shown as if typed; the server selects what it spawns.
-- @param entry a gameobject entry, as a lookup line prints it
-- @param ways the ways out of the door it came through, as a request carries them
function Console.SpawnGob(entry, ways)
	local send = ready(ways)
	if send then
		send(Commands.SpawnHere(entry), nil, true)
	end
end

--- Spawn a set on the selected object, or at the player.
-- @param request as the head of this file describes it
function Console.Spawn(request)
	if not ready(request.ways) then
		return
	end
	-- A pose given is the destination, its numbers alone, and its root must be named, since a pose
	-- names none. The selection is read apart from it: a merge joins whatever is selected, a group
	-- as readily as a gob, and the run's group stands for it once the run ends.
	local named = request.entry or request.file
	if request.at then
		if not named then
			return say("a position names no WMO; name the one whose sets to spawn")
		end
		local group = request.group == "merge" and Console.Group()
		if group or request.group ~= "merge" then
			return spawnOn(request, request.at, group or (selectedPose()))
		end
		return withSelection(request.ways, "the object whose group to join", nil, function(selected)
			spawnOn(request, request.at, selected)
		end)
	end
	-- The selected object is the destination unless the set goes at the player, and any object
	-- will do. It must be a WMO only where the set is its own, read off it because
	-- neither a link nor an entry names one; and it leads the group a set merges into.
	if request.here and named and request.group ~= "merge" then
		return spawnOn(request, nil, nil)
	end
	local what = not named and "the WMO"
		or request.here and "the object whose group to join"
		or "the object to spawn on"
	local here = request.here
		and not named
		and request.group ~= "merge"
		and way(request.ways, "here")
	local from = way(request.ways, "from")
	withSelection(request.ways, what, here and (", or name it, as " .. here) or nil, function(pose)
		local wrong = not named and notWmo(pose, from and "name one, as " .. from)
		if wrong then
			return say(wrong)
		end
		spawnOn(request, pose, pose)
	end)
end

--- The sets an imported WMO showed as a doodad, beyond the base set it shows
-- itself; with base, the base set as well, whether the doodad showed it or not.
local function placed(pose, ids, base)
	local chosen = {}
	local first = base and (Sets.OfFile(pose.file) or {})[1]
	if first and Sets.IsBase(first) then
		chosen[1] = first
	end
	for _, set in ipairs(Sets.Named(pose.file, ids)) do
		if not Sets.IsBase(set) then
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
	local send = ready(request.ways)
	if not send then
		return
	end
	local reason
	local map = Client.Map()

	-- What may still answer: the import's line and the record of the object it made. A stop
	-- silences both.
	local stopped, heard = false, false
	local stopHearing, stopAwaiting
	wait({
		what = "the imported object",
		left = "an import already sent stands",
		stop = function()
			stopped = true
			stopHearing()
			if stopAwaiting then
				stopAwaiting()
			end
		end,
	})

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
			-- The data keeps no placement that draws only its base set, which the gob draws
			-- itself, so this is said alike of one that drew only that and one the data lacks.
			local listing = way(request.ways, "list")
			return say(
				offering(
					("imported %s as object %s; the doodad drew no set beyond its base that %s knows of"):format(
						model,
						guid,
						Furnish.NAME
					),
					listing and listing .. " lists the WMO's own"
				)
			)
		end
		local rows, what = gather(chosen)
		if not rows then
			return say(what)
		end
		local word = request.group or "merge"
		local group, lead = groupOf({ group = word }, pose)
		if not group then
			return say(("imported %s as object %s, but %s"):format(model, guid, lead))
		end
		start(rows, pose, group, {
			what = what,
			where = "on " .. pose.name,
			lead = lead,
			anchor = pose,
			quiet = request.quiet,
			blueprint = offered(word, pose, pose, pose.name, chosen),
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
		-- The server's line naming the object is the import done; the selection that follows
		-- needs the GUID it names.
		tell("imported", uid, guid)
		local ids = Sets.OfPlacement(map, tonumber(uid))
		stopAwaiting, reason = reselect(send, guid, function(record)
			furnish(record, ids, guid, model)
		end, function(replies)
			say(
				("imported %s as object %s, but selecting it was refused: %s"):format(
					model,
					guid,
					quote(replies)
				)
			)
		end)
		if not stopAwaiting then
			wait(nil)
			return say(reason)
		end
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
			wait(nil)
			say("nothing was imported: " .. quote(messages))
		end
	end)
end

--- What a second stop does, said by the first, and said by the second as it does it.
local AGAIN, GIVING_UP =
	" again gives up on a reply that never comes", "giving up on the replies still owed"

--- Stop spawning. With delete, also delete what the run spawned.
-- @param ways the ways out of the door the stop came through, as a request carries them
function Console.Stop(delete, ways)
	if waiting then
		local left = waiting.left
		waiting.stop()
		wait(nil)
		return say("stopped; nothing was spawned" .. (left and ", and " .. left or ""))
	end
	if not (running and not running.Done()) then
		return say("nothing is spawning")
	end
	local stop = way(ways, "stop")
	local again = stop and stop .. AGAIN
	-- Once the run is deleting, a stop ends the deleting the way it ends a run.
	local deleting = current and current.deleting
	if deleting then
		say(deleting.stopping and GIVING_UP or offering("no more deletes", again))
		deleting.stopping = true
		return running.Abort()
	end
	if stopping then
		say(GIVING_UP)
	elseif delete then
		say(offering("stopping, then deleting what was spawned", again))
	else
		say(offering("stopping", again))
	end
	stopping = true
	running.Abort(delete)
end
