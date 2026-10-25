-- The window: where a WMO's sets come from, which of them to spawn, and where they go, read top
-- to bottom, with a run's progress at the foot.
--
-- A surface over Console, as the commands are: it reads Source for the sets, Target for the
-- selected object's pose, Find for a name searched, Busy for whether it may start and Watch for
-- the run going on, and spawns, imports and stops through the same doors, so the window and
-- the commands can never disagree. The layout is Window.xml; this file gives it behaviour and
-- every word.
--
-- Source and Target each follow the gob selection until their box is unticked. The source is
-- the WMO a gob entry is, shown in its ID box as the target's numbers are: the selected gob's,
-- one typed, the lowest of a WMO searched, or the doodad's. The target is the selected gob, or
-- where the player stands while no gob is selected, so every number always holds a value. The doodad `.doodad select`
-- picks is another selection, held at the same time and shown in a panel of its own beside the
-- window: picking it never changes the source or the target, and selecting a gob never clears
-- it. It is a step before the gob pipeline, giving each side something in advance. Use as source
-- keeps its WMO as the source with the sets it drew chosen; Import doodad turns it into a gob,
-- selected like any other, with those sets chosen while the source follows the selection; a
-- block kept as it is stays so. Importing hides the doodad, which stays selected, so the panel
-- keeps it. While a run goes nothing changes, since every spawn moves the selection.

_G.Furnish = _G.Furnish or {}
local Furnish = _G.Furnish
local Window = {}
Furnish.Window = Window

local Console = Furnish.Console
local Client = Furnish.Client
local Pose = Furnish.Pose
local Rows = Furnish.Rows
local Reader = Furnish.Reader
local Chat = Furnish.Chat

--- The border a list wears, ObjectMover's: a tooltip's edge over a dark shade.
local PANEL = {
	bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
	edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
	tile = true,
	tileEdge = true,
	tileSize = 16,
	edgeSize = 16,
	insets = { left = 5, right = 5, top = 5, bottom = 5 },
}

--- The search list's own backdrop: flat and opaque, since it lies over the window.
local OVERLAY = {
	bgFile = "Interface\\Buttons\\WHITE8X8",
	edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
	tile = false,
	edgeSize = 16,
	insets = { left = 4, right = 4, top = 4, bottom = 4 },
}

--- The tooltip's colours: a label, a value, a heading, what a click does, and a refusal.
local GREY, WHITE, GOLD = { 0.62, 0.62, 0.62 }, { 1, 1, 1 }, { 1, 0.82, 0 }
local GREEN, RED = { 0.25, 1, 0.25 }, { 1, 0.13, 0.13 }

--- A warning's colour, Tiler's: a red light enough to read on the dark panel.
local WARN = { 1, 0.5, 0.5 }

local ROW = 22

--- The smallest the window may be drawn, which is the size its layout was made for; it may grow
-- to twice that.
local MIN_WIDTH, MIN_HEIGHT = 400, 628

--- How many letters a name search waits for, as Blizzard's own searches do; how many WMOs it
-- lists at most, and how many rows of them show before the list scrolls.
local SEARCH_FROM, RESULTS, RESULT_ROWS = 3, 60, 8

--- How many models a set's tooltip names before it says how many more there are.
local NAMED = 8

--- How many objects a run places before the bar guesses the time left from its pace.
local PACED = 5

--- The position's numbers, two rows across the window's width: the axes, then the turn about
-- each and the scale. Each is its box, its row, where the pose keeps it, and ObjectMover's colour
-- for its axis, the same for a position and the turn about it.
local RED_AXIS, BLUE_AXIS, GREEN_AXIS =
	{ 1, 0.376, 0.376 }, { 0.22, 0.43, 0.97 }, { 0.13, 0.99, 0.55 }
local NUMBERS = {
	{ box = "X", row = 1, part = "position", key = "x", colour = RED_AXIS },
	{ box = "Y", row = 1, part = "position", key = "y", colour = BLUE_AXIS },
	{ box = "Z", row = 1, part = "position", key = "z", colour = GREEN_AXIS },
	{ box = "Roll", row = 2, part = "rotation", key = "roll", colour = RED_AXIS },
	{ box = "Pitch", row = 2, part = "rotation", key = "pitch", colour = BLUE_AXIS },
	{ box = "Turn", row = 2, part = "rotation", key = "turn", colour = GREEN_AXIS },
	{ box = "Scale", row = 2, colour = GREY },
}

--- Where each row of boxes stands, measured up from the window's foot to its top, and how far
-- apart the boxes are. A box's border art reaches five units left of the box itself.
local NUMBER_ROWS, NUMBER_GAP, NUMBER_ART = { 170, 144 }, 8, 5

--- A button's caps either side of its words.
local CAPS = 24

--- How many of a doodad's sets its panel shows before its list scrolls.
local DOODAD_ROWS = 10

local frame = _G.FurnishFrame
local list = frame.Sets
local panel = frame.Doodad
local provider, found, drawn =
	_G.CreateDataProvider(), _G.CreateDataProvider(), _G.CreateDataProvider()

--- Where the sets come from: the Source request pinned, or nil to follow the gob selection; the
-- doodad `.doodad select` picked, in its own slot, imported or not, with the sets of the WMO it
-- is; the doodad imported last while the source followed the selection, whose sets come chosen
-- when the gob it became is shown; the source shown, or nil, and the gob entry its ID box holds;
-- and the sets chosen, by index.
local pinned, doodad, marks, shown, shownEntry
local chosen = {}

--- Where the sets go: the pose shown, its own copy, with what to call it and say of it; whether
-- it stays when the selection moves; and whether a number of it was typed.
local spot, spotPinned, edited = nil, false, false

--- The run going on, as the window draws it: { total, done, started }.
local run

--- The search match Enter takes, by its place in the list.
local picked = 1

local stops = {}

--- A count with its thousands set apart.
local function thousands(count)
	local text, done = tostring(count), 1
	while done > 0 do
		text, done = text:gsub("^(%-?%d+)(%d%d%d)", "%1,%2")
	end
	return text
end

local function objects(count)
	return count == 1 and "1 object" or thousands(count) .. " objects"
end

--- Seconds as a clock reads them.
local function clock(seconds)
	seconds = math.floor(seconds + 0.5)
	local hours, minutes = math.floor(seconds / 3600), math.floor(seconds % 3600 / 60)
	if hours > 0 then
		return ("%d:%02d:%02d"):format(hours, minutes, seconds % 60)
	end
	return ("%d:%02d"):format(minutes, seconds % 60)
end

--- A number as a box shows it: three places at most, no trailing zeros.
local function shownNumber(value)
	local text = ("%.3f"):format(value):gsub("0+$", ""):gsub("%.$", "")
	return text == "-0" and "0" or text
end

--- A pose of the window's own, so a number changed never reaches the record it was read off.
local function copy(pose, name, detail)
	local own = {}
	for key, value in pairs(pose) do
		own[key] = value
	end
	own.position = { x = pose.position.x, y = pose.position.y, z = pose.position.z }
	own.rotation =
		{ roll = pose.rotation.roll, pitch = pose.rotation.pitch, turn = pose.rotation.turn }
	own.name = name or pose.name
	own.detail = detail
	return own
end

local function valueOf(pose, number)
	if number.part then
		return pose[number.part][number.key]
	end
	return pose.scale
end

--- What a gob target is, in a word or two.
local function gobDetail(pose)
	return (pose.groupLeader or 0) ~= 0 and "Gob, in a group" or "Gob"
end

--- Whether a run spawns a pivot to lead its group: when grouped without the target, and while
-- a pivot display is set at all.
local function pivots(group)
	return group == "pivot" and Furnish.Settings.marker ~= nil
end

--- What Use selected fills the target from: the selected gob, or else a selected group, whose
-- pose says group; nil when neither is selected. The target never follows a group by itself.
local function selectedForTarget()
	return Console.Target() or Console.Group()
end

--- Show a tooltip: a title, label and value pairs, and lines in a colour of their own.
-- @param lines each { label, value } for a pair, or { text, colour } for a line of its own
local function tip(owner, title, lines)
	local tooltip = _G.GameTooltip
	tooltip:SetOwner(owner, "ANCHOR_RIGHT")
	tooltip:SetText(title, GOLD[1], GOLD[2], GOLD[3])
	for _, line in ipairs(lines) do
		if line.value then
			local value = tostring(line.value)
			tooltip:AddDoubleLine(line.label, value, GREY[1], GREY[2], GREY[3], 1, 1, 1)
		elseif line.text then
			local colour = line.colour or WHITE
			tooltip:AddLine(line.text, colour[1], colour[2], colour[3], true)
		end
	end
	tooltip:Show()
end

--- Give a control a tooltip, its lines read when shown: a function's answer, or a fixed list.
-- How a command types the same thing is read then too, since the command's name is only known
-- once every file has loaded.
local function hint(owner, title, lines, words)
	owner:SetScript(
		"OnEnter",
		Client.Guarded(function()
			local shownTitle = type(title) == "function" and title() or title
			local shownLines = type(lines) == "function" and lines() or lines
			local all = {}
			for i, line in ipairs(shownLines) do
				all[i] = line
			end
			if words then
				all[#all + 1] = { text = "Typed: " .. Chat.Typed(words), colour = GREY }
			end
			tip(owner, shownTitle, all)
		end)
	)
	owner:SetScript("OnLeave", _G.GameTooltip_Hide)
end

--- Why the target cannot be included in the group, or nil when it can.
local function cannotInclude()
	if not spot or not spot.guid then
		return "The target is a position, not a gob."
	elseif not Client.CanEdit(spot) then
		return "You can't edit the target in this phase."
	end
	return nil
end

--- The request's group, from the three boxes: loose, a group the target joins, or a group of
-- their own that a pivot leads, or the set's first object where No pivot is ticked.
local function grouped()
	if not frame.Grouped:GetChecked() then
		return "nogroup"
	elseif frame.Include:GetChecked() and not cannotInclude() then
		return "attach"
	elseif frame.NoPivot:GetChecked() then
		return "first"
	end
	return "pivot"
end

--- Whether the selected gob draws a set already, as part of its model: its base set, unless
-- the WMO comes unfurnished. A WMO searched stands nowhere and draws nothing.
local function baked(set)
	if pinned or not shown then
		return false
	end
	return set.index == 0 and not shown.blank
end

--- The chosen sets' indexes in the list's order, and how many objects they hold.
local function chosenSets()
	local indexes, count = {}, 0
	for _, set in ipairs(shown and shown.sets or {}) do
		if chosen[set.index] then
			indexes[#indexes + 1] = set.index
			count = count + set.count
		end
	end
	return indexes, count
end

--- What the main button says, and whether it may be pressed.
local function action()
	if run then
		return "Stop", true
	elseif Console.Busy() then
		return "Waiting for the server", false
	elseif not Client.CanSpawn(true) then
		return "You can't spawn in this phase", false
	elseif not shown then
		return "No sets to spawn", false
	end
	local indexes, count = chosenSets()
	if #indexes == 0 then
		return "Choose a set", false
	elseif not spot then
		return "Choose where to spawn", false
	elseif spot.scale <= 0 then
		return "Scale must be above 0", false
	end
	return "Spawn " .. objects(count) .. (pivots(grouped()) and " and a pivot" or ""), true
end

--- Mark a row chosen or not: a gold wash and an accent along its edge.
local function mark(button, set)
	button.Selected:SetShown(chosen[set.index] == true)
	button.Accent:SetShown(chosen[set.index] == true)
end

--- Say how many chosen sets the list hides above and below what it shows.
local function updateMore()
	local scroll = list.ScrollBox
	local top = scroll:GetDerivedScrollOffset()
	local bottom = top + scroll:GetVisibleExtent()
	local above, below = {}, {}
	for position, set in ipairs(shown and shown.sets or {}) do
		if chosen[set.index] then
			if position * ROW <= top then
				above[#above + 1] = position
			elseif (position - 1) * ROW >= bottom then
				below[#below + 1] = position
			end
		end
	end
	for _, edge in ipairs({ { list.Above, above, above[#above] }, { list.Below, below, below[1] } }) do
		local button, hidden, nearest = edge[1], edge[2], edge[3]
		button:SetShown(#hidden > 0)
		button.nearest = nearest
		button.Label:SetText(("%d more chosen"):format(#hidden))
	end
end

--- What a set holds, by model, the most numerous first: a list of { name, count }, and how many
-- of its objects the client's catalogue does not name.
local function holds(set)
	local counts, unnamed = {}, 0
	for _, row in ipairs(Rows.OfSet(set.id) or {}) do
		local name = Console.ModelName(row.display)
		if name then
			counts[name] = (counts[name] or 0) + 1
		else
			unnamed = unnamed + 1
		end
	end
	local held = {}
	for name, count in pairs(counts) do
		held[#held + 1] = { name = name, count = count }
	end
	table.sort(held, function(a, b)
		return a.count > b.count or (a.count == b.count and a.name < b.name)
	end)
	return held, unnamed
end

--- Whether two roots offer the same sets, as an emptied copy and the WMO it was emptied from do.
local function sameSets(a, b)
	local one, other = Reader.Sets(a), Reader.Sets(b)
	if not (one and other) or #one ~= #other then
		return false
	end
	for i, set in ipairs(one) do
		if set[2] ~= other[i][2] then
			return false
		end
	end
	return true
end

--- What to know before the next spawn, the weightiest first, each { text, colour }.
local function warnings()
	local said = {}
	if run or not shown or not spot then
		return said
	end
	if spot.wmo and spot.file ~= shown.file and not sameSets(spot.file, shown.file) then
		local text = ("These sets are %s's, not %s's, so they may not fit."):format(
			shown.name,
			spot.name
		)
		said[#said + 1] = { text = text, colour = WARN }
	end
	-- A reminder, not a warning: whether highlighting is on is the player's call.
	if #(chosenSets()) > 0 then
		said[#said + 1] =
			{ text = "Highlighting too many objects can crash the game.", colour = GREY }
	end
	return said
end

--- The status row: a run's bar while it goes; otherwise what to know before the next spawn, or
-- how the last run ended.
local function updateStatus()
	local said = warnings()
	frame.Notice.said = said
	frame.Notice:SetShown(#said > 0)
	local first = said[1]
	frame.Notice.Text:SetText(first and first.text or "")
	if first then
		frame.Notice.Text:SetTextColor(first.colour[1], first.colour[2], first.colour[3])
	end
	frame.Progress:SetShown(run ~= nil or (#said == 0 and frame.Progress.ended == true))
end

--- Every control the player may change, which a run holds still.
local function controls()
	local all = {
		frame.Search,
		frame.SourceFollow,
		frame.SourceID,
		frame.TargetFollow,
		frame.Here,
		frame.UseSelected,
		frame.Grouped,
	}
	for _, number in ipairs(NUMBERS) do
		all[#all + 1] = frame[number.box]
	end
	return all
end

--- A checkbox's words, white while it may be ticked and grey while it may not.
local function checkText(box, enabled)
	box.text:SetFontObject(enabled and _G.GameFontHighlightSmall or _G.GameFontDisableSmall)
end

local function updateTarget()
	-- A number typed makes a gob's position the player's own; a position typed is no longer where
	-- anyone stood.
	local name, detail = spot and spot.name or "", spot and spot.detail or ""
	if edited and spot.guid then
		detail = detail .. ", edited"
	elseif edited then
		name, detail = "A position", "Typed in"
	end
	frame.TargetName:SetText(name)
	frame.TargetDetail:SetText(detail)
	frame.TargetFollow:SetChecked(not spotPinned)
	for _, number in ipairs(NUMBERS) do
		local box = frame[number.box]
		if not box:HasFocus() then
			box:SetText(spot and shownNumber(valueOf(spot, number)) or "")
		end
		local colour = run and GREY or number.colour
		box.Axis:SetTextColor(colour[1], colour[2], colour[3])
		box:SetTextColor(run and 0.5 or 1, run and 0.5 or 1, run and 0.5 or 1)
	end
	-- The button names what it reads, a gob or a group, and is as wide as its words.
	local from = selectedForTarget()
	local label = from and from.group and "Use selected group" or "Use selected gob"
	if frame.UseSelected:GetText() ~= label then
		frame.UseSelected:SetText(label)
		frame.UseSelected:SetWidth(
			math.ceil(frame.UseSelected:GetFontString():GetStringWidth()) + CAPS
		)
	end
	frame.UseSelected:SetEnabled(not run and from ~= nil)
	local canInclude = not run and frame.Grouped:GetChecked() and not cannotInclude()
	frame.Include:SetEnabled(canInclude)
	checkText(frame.Include, canInclude)
	-- Who leads a group of the set's own, which a group the target leads has not.
	local canChooseLeader = not run and frame.Grouped:GetChecked() and grouped() ~= "attach"
	frame.NoPivot:SetEnabled(canChooseLeader)
	checkText(frame.NoPivot, canChooseLeader)
	checkText(frame.Grouped, not run)
	frame.Warning:SetShown(grouped() == "attach" and (spot.groupLeader or 0) ~= 0)
end

--- The doodad panel, there while a doodad is selected; a doodad imported once is not again.
local function updateDoodad()
	panel:SetShown(doodad ~= nil)
	if not doodad then
		return
	end
	local count = #doodad.sets .. (#doodad.sets == 1 and " set" or " sets")
	panel.Detail:SetText(count .. (doodad.imported and ", imported" or ""))
	panel.UseSource:SetEnabled(not run)
	panel.Import:SetEnabled(not run and not doodad.imported)
end

local function update()
	for _, control in ipairs(controls()) do
		control:SetEnabled(not run)
	end
	updateDoodad()
	-- The ID box holds the source's entry, unless it is being typed in.
	local id = frame.SourceID
	if not id:HasFocus() then
		id:SetText(shownEntry and tostring(shownEntry) or "")
	end
	id:SetTextColor(run and 0.5 or 1, run and 0.5 or 1, run and 0.5 or 1)
	list.ScrollBox:ForEachFrame(mark)
	updateMore()
	updateTarget()
	updateStatus()
	local text, enabled = action()
	frame.SpawnButton:SetText(text)
	frame.SpawnButton:SetEnabled(enabled)
	-- A run's objects can be taken back only while it goes; once it ends, its group is the
	-- player's, and nothing here knows what has been done to it since.
	frame.DeleteButton:SetShown(run ~= nil)
	frame.SpawnButton:SetPoint("TOPRIGHT", frame, "BOTTOMRIGHT", run and -142 or -18, 38)
end

--- The spawn the window describes, as Console takes it.
local function request()
	return {
		indexes = (chosenSets()),
		file = shown.file,
		label = shown.name,
		at = copy(spot),
		group = grouped(),
		quiet = true,
	}
end

_G.StaticPopupDialogs.FURNISH_JOIN_GROUP = {
	text = "%s is in a group already. The %s join that group, and moving the group moves them too.",
	button1 = "Spawn",
	button2 = _G.CANCEL,
	OnAccept = function(_, data)
		Console.Spawn(data)
	end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
}

--- Spawn the chosen sets, asking first where they would join a group the target is in already,
-- and spawning then what was asked about, whatever has been selected since; or stop the run.
local function spawn()
	if run then
		return Console.Stop(false)
	end
	local text, enabled = action()
	if not enabled then
		return Chat.Say(text)
	end
	if grouped() == "attach" and (spot.groupLeader or 0) ~= 0 then
		local _, count = chosenSets()
		local dialog = _G.StaticPopup_Show("FURNISH_JOIN_GROUP", spot.name, objects(count))
		if dialog then
			dialog.data = request()
		end
		return
	end
	Console.Spawn(request())
end

--- What is chosen when a WMO is first shown: the sets a doodad drew beyond the base set, which the
-- WMO draws itself unless it comes unfurnished; where no doodad adds one, its first set it does not
-- draw already, and the base too where it comes unfurnished.
local function chooseFirst(sets, blank)
	chosen = {}
	for _, set in ipairs(sets) do
		if set.placed and (set.index ~= 0 or blank) then
			chosen[set.index] = true
		end
	end
	if next(chosen) then
		return
	end
	for _, set in ipairs(sets) do
		if not baked(set) and set.index ~= 0 then
			chosen[set.index] = true
			break
		end
	end
	if blank and sets[1] and sets[1].index == 0 then
		chosen[0] = true
	end
end

--- The source's request: what is pinned, the doodad's WMO among them, or the selected gob, marked
-- with the sets the doodad it was imported from drew.
local function sourceRequest()
	if pinned then
		return pinned
	elseif marks then
		return { placement = marks }
	end
	return nil
end

--- The source's detail line: what it is and how many sets it has.
local function sourceDetail()
	local count = #shown.sets .. (#shown.sets == 1 and " set" or " sets")
	return count .. (shown.blank and ", unfurnished" or "")
end

--- The gob entry the source's ID box holds: the one kept, the lowest of a WMO searched, or the
-- selected gob's; nil where there is none.
local function sourceEntry()
	if pinned then
		return pinned.entry
			or (pinned.file and Reader.Load() and Reader.EntryOfFile(pinned.file))
			or nil
	end
	local selected = Console.Target()
	return selected and selected.entry
end

--- Read the window afresh: the source and the target follow the selection unless unticked.
local function refresh()
	if run then
		return
	end
	local before = shown
	shown = not (pinned and pinned.empty) and Console.Source(sourceRequest()) or nil
	if shown then
		for _, set in ipairs(shown.sets) do
			shown.placed = shown.placed or set.placed
		end
	end
	local fresh = shown and not (before and before.file == shown.file)
	if fresh then
		chooseFirst(shown.sets, shown.blank)
	end
	-- The doodad imported last says which sets come chosen on the gob it became, once that gob is
	-- shown, and nothing after.
	if marks and shown and shown.placed then
		marks = nil
	end
	if not spotPinned then
		local selected = Console.Target()
		if selected then
			spot = copy(selected, nil, gobDetail(selected))
		elseif not spot or spot.guid then
			-- With nothing selected the target takes where the player stands, read once so no number
			-- is empty, and never again while it stays so: it does not follow the player, and Here
			-- reads it afresh.
			local here = Pose.Here()
			spot = here and copy(here, "Your position", "")
		end
		-- Without a gob to follow, the target says why: none is selected, or a group is, which the
		-- target never follows by itself.
		if spot and not selected then
			spot.detail = Console.Group() and "A group is selected" or "No gob selected"
		end
		edited = false
	end
	frame.SourceFollow:SetChecked(not pinned)
	shownEntry = sourceEntry()
	provider:Flush()
	if shown then
		frame.SourceName:SetText(shown.name)
		frame.SourceName:SetTextColor(1, 1, 1)
		frame.SourceDetail:SetText(sourceDetail())
		provider:InsertTable(shown.sets)
	else
		local selected = not pinned and Console.Target()
		frame.SourceName:SetTextColor(1, 1, 1)
		if pinned and pinned.empty then
			frame.SourceName:SetText("Nothing kept")
			frame.SourceName:SetTextColor(0.5, 0.5, 0.5)
			frame.SourceDetail:SetText("")
		elseif pinned then
			frame.SourceName:SetText(pinned.name or ("Entry %d"):format(pinned.entry))
			frame.SourceDetail:SetText("No sets")
		elseif selected then
			frame.SourceName:SetText(selected.name)
			frame.SourceDetail:SetText(selected.wmo and "No sets" or "Not a WMO")
		else
			-- A group is no source, whatever leads it, as a model is not.
			local group = not pinned and Console.Group()
			frame.SourceName:SetText(group and "A group" or "No WMO selected")
			frame.SourceName:SetTextColor(0.5, 0.5, 0.5)
			frame.SourceDetail:SetText(group and "Led by " .. group.name or "")
		end
		list.Empty:SetText(
			pinned and pinned.empty and "Search a WMO, or tick Follow selection."
				or pinned and "Search another WMO."
				or "Select one WMO, or search one."
		)
	end
	list.Empty:SetShown(not shown)
	update()
end

--- The bar's words during a run: how far it is, and once its pace is known, how long is left.
local function progressText()
	local line = ("%s of %s"):format(thousands(run.done), thousands(run.total))
	local elapsed = Client.Now() - run.started
	if run.done >= PACED and run.done < run.total then
		local left = elapsed / run.done * (run.total - run.done)
		line = line .. (", about %s left"):format(clock(left))
	end
	frame.Progress.Text:SetText(line)
end

local function started(total)
	run = { total = total, done = 0, started = Client.Now() }
	frame.Results:Hide()
	frame.Progress:SetMinMaxValues(0, math.max(total, 1))
	frame.Progress:SetValue(0)
	frame.Progress.ended = false
	progressText()
	update()
end

local function progressed(done)
	if not run then
		return
	end
	run.done = done
	frame.Progress:SetValue(done)
	progressText()
end

--- Say how a run ended on the bar, which stays until the next one starts.
local function finished(result, seconds)
	local was = run
	run = nil
	if not (result and was) then
		frame.Progress.ended = false
		return refresh()
	end
	local placed = #result.spawned - (result.pivot and 1 or 0)
	local pivot = result.pivot and " and a pivot" or ""
	local line
	if result.deleted then
		line = ("Stopped, %s deleted"):format(objects(result.deleted))
	elseif result.aborted then
		line = ("Stopped: %s of %s%s"):format(thousands(placed), objects(result.total), pivot)
	else
		line = ("Done: %s%s in %s"):format(objects(placed), pivot, clock(seconds))
	end
	local missed = #result.refused + #result.unjoined
	if missed > 0 then
		line = line .. (", %d not placed or grouped; see chat"):format(missed)
	end
	frame.Progress:SetValue(result.deleted and 0 or placed)
	frame.Progress.Text:SetText(line)
	frame.Progress.ended = true
	refresh()
end

--- A click chooses the one set, and a ctrl-click adds or removes it.
local function rowClick(button)
	if run then
		return
	end
	_G.PlaySound(_G.SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
	local index = button:GetElementData().index
	if _G.IsControlKeyDown() then
		chosen[index] = not chosen[index] or nil
	else
		chosen = { [index] = true }
	end
	update()
end

--- A set's tooltip, read off the row as it stands, since rows are reused as the list scrolls:
-- what it is, whether the source draws it already, and the models it holds.
local function rowEnter(button)
	local set = button:GetElementData()
	local lines = {
		{ label = "Set", value = set.index },
		{ label = "Objects", value = thousands(set.count) },
	}
	if set.canonical ~= "" then
		lines[#lines + 1] = { label = "In the file", value = set.canonical }
	end
	if baked(set) then
		lines[#lines + 1] =
			{ text = "The WMO draws this set already, as part of its model.", colour = GREEN }
	elseif set.placed then
		lines[#lines + 1] = { text = "The doodad drew this set.", colour = GREEN }
	end
	if Console.ModelsNamed() then
		local held, unnamed = holds(set)
		if #held > 0 then
			lines[#lines + 1] = { text = "Holds", colour = GOLD }
			for i = 1, math.min(NAMED, #held) do
				lines[#lines + 1] = { label = held[i].name, value = held[i].count }
			end
			if #held > NAMED then
				lines[#lines + 1] =
					{ text = ("and %d more models"):format(#held - NAMED), colour = GREY }
			end
		end
		if unnamed > 0 then
			local text = ("and %s the client does not name"):format(objects(unnamed))
			lines[#lines + 1] = { text = text, colour = GREY }
		end
	else
		-- The names come from one walk of the client's catalogue; the tooltip redraws when it ends,
		-- if the row is still the one under the cursor.
		lines[#lines + 1] = { text = "Naming the models...", colour = GREY }
		Console.NameModels(function()
			if _G.GameTooltip:IsOwned(button) and button:GetElementData() == set then
				rowEnter(button)
			end
		end)
	end
	lines[#lines + 1] = { text = "Click: choose this set alone", colour = GREEN }
	lines[#lines + 1] = { text = "Ctrl-click: add or remove this set", colour = GREEN }
	tip(button, set.name, lines)
end

local function initRow(button, set, new)
	if new then
		button:SetScript("OnClick", Client.Guarded(rowClick))
		button:SetScript("OnEnter", Client.Guarded(rowEnter))
		button:SetScript("OnLeave", _G.GameTooltip_Hide)
	end
	button.Index:SetText(set.index)
	button.Label:SetText(set.name)
	button.Count:SetText(thousands(set.count))
	button.Tag:SetText(baked(set) and "baked" or "")
	button.Label:SetPoint("RIGHT", baked(set) and -100 or -44, 0)
	mark(button, set)
end

--- Show the sets of a WMO a search found, and keep them whatever is selected.
local function pick(wmo)
	_G.PlaySound(_G.SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
	pinned = { file = wmo.file, name = wmo.name }
	frame.Search:ClearFocus()
	frame.Results:Hide()
	refresh()
end

--- Light the search match Enter takes, wrapping past either end, and bring it into view.
local function light(index)
	local size = found:GetSize()
	if size == 0 then
		return
	end
	picked = (index - 1) % size + 1
	frame.Results.ScrollBox:ScrollToElementDataIndex(picked)
	frame.Results.ScrollBox:ForEachFrame(function(button, wmo)
		button.Picked:SetShown(found:FindIndex(wmo) == picked)
	end)
end

--- A found WMO's tooltip, read off the row as it stands.
local function resultEnter(button)
	local wmo = button:GetElementData()
	local lines = {
		{ label = "Sets", value = wmo.sets },
		{ label = "File", value = wmo.file },
	}
	if wmo.blank then
		lines[#lines + 1] =
			{ text = "It comes unfurnished: it draws none of its sets itself.", colour = GREY }
	end
	lines[#lines + 1] = { text = "Click: show its sets", colour = GREEN }
	tip(button, wmo.name, lines)
end

local function initResult(button, wmo, new)
	if new then
		button:SetScript(
			"OnClick",
			Client.Guarded(function(self)
				pick(self:GetElementData())
			end)
		)
		button:SetScript("OnEnter", Client.Guarded(resultEnter))
		button:SetScript("OnLeave", _G.GameTooltip_Hide)
	end
	button.Label:SetText(wmo.name)
	button.Count:SetText(wmo.sets == 1 and "1 set" or wmo.sets .. " sets")
	button.Tag:SetText(wmo.blank and "unfurnished" or "")
	button.Label:SetPoint("RIGHT", wmo.blank and -128 or -60, 0)
	button.Picked:SetShown(found:FindIndex(wmo) == picked)
end

--- A search typed: from three letters, the WMOs a name finds list under the box, the first lit
-- so Enter takes it.
local function searchChanged(box, typed)
	if not typed then
		return
	end
	local text = box:GetText():match("^%s*(.-)%s*$")
	found:Flush()
	picked = 1
	if #text < SEARCH_FROM then
		return frame.Results:Hide()
	end
	local wmos = Console.Find(text)
	for i = 1, math.min(RESULTS, #wmos) do
		found:Insert(wmos[i])
	end
	frame.Results.Empty:SetText(("No WMO with sets is named like %s."):format(text))
	frame.Results.Empty:SetShown(#wmos == 0)
	frame.Results:SetHeight(math.min(#wmos, RESULT_ROWS) * ROW + 16 + (#wmos == 0 and 40 or 0))
	frame.Results:Show()
end

--- A search entered: the match that is lit becomes the source.
local function searched()
	local wmo = found:GetSize() > 0 and found:Find(picked)
	if wmo then
		pick(wmo)
	end
end

--- Follow the selection with the sets, or keep the WMO shown whatever is selected.
local function followSource(box)
	if box:GetChecked() then
		pinned = nil
		frame.Search:SetText("")
	else
		-- Unticked with nothing shown, the source stays empty until a search or an ID fills it.
		pinned = shown and { file = shown.file, name = shown.name, entry = shownEntry }
			or { empty = true }
	end
	refresh()
end

--- An ID typed, once its box is left: the WMO that gob entry is becomes the source, kept whatever
-- gob is selected; anything but a new number puts back the one shown.
local function idChanged(box)
	local entry = tonumber(box:GetText())
	if entry and entry ~= shownEntry then
		pinned = { entry = entry }
		frame.Search:SetText("")
		frame.Results:Hide()
		return refresh()
	end
	update()
end

--- Follow the selection with the target, or keep the position shown whatever is selected.
local function followTarget(box)
	spotPinned = not box:GetChecked()
	refresh()
end

--- Fill the target once from a pose, and keep it there until Follow selection is ticked.
local function fillTarget(pose)
	if pose then
		spot, spotPinned, edited = pose, true, false
	end
	update()
end

--- What the Import doodad tooltip says: what importing does, and whether it has been.
local function importLines()
	local lines = {
		{
			text = "Turn the doodad into a gob, which becomes the selected gob. The gob draws only its base set, so while Source follows the selection, the doodad's other sets come chosen.",
		},
	}
	if doodad and doodad.imported then
		lines[#lines + 1] = {
			text = "Imported already: the doodad is hidden on the map and stays selected.",
			colour = GREY,
		}
	end
	return lines
end

--- A doodad's set's tooltip: what it is, and whether the doodad draws it.
local function drawnEnter(button)
	local set = button:GetElementData()
	local lines = {
		{ label = "Set", value = set.index },
		{ label = "Objects", value = thousands(set.count) },
	}
	if set.canonical ~= "" then
		lines[#lines + 1] = { label = "In the file", value = set.canonical }
	end
	if set.draws then
		local text = set.placed and "The doodad draws this set on the map."
			or "The doodad draws this set as part of its model."
		lines[#lines + 1] = { text = text, colour = GREEN }
	end
	tip(button, set.name, lines)
end

local function initDrawn(button, set, new)
	if new then
		button:SetScript("OnEnter", Client.Guarded(drawnEnter))
		button:SetScript("OnLeave", _G.GameTooltip_Hide)
	end
	button.Index:SetText(set.index)
	button.Label:SetText(set.name)
	button.Count:SetText(thousands(set.count))
	button.Tag:SetText(set.draws and "baked" or "")
	-- The name ends where the tag begins, which is where the count's column begins when there is none.
	button.Label:SetPoint("RIGHT", button.Tag, "LEFT", -6, 0)
end

--- Fill the doodad panel with the doodad's name and the sets of the WMO it is, its list as tall
-- as its sets up to a point, past which it scrolls.
local function fillDoodad()
	drawn:Flush()
	if not doodad then
		return
	end
	panel.Name:SetText(doodad.name)
	drawn:InsertTable(doodad.sets)
	local rows = math.min(#doodad.sets, DOODAD_ROWS)
	panel:SetHeight(72 + rows * ROW + 16 + 82)
end

--- Keep the doodad's WMO as the source whatever is selected, with the sets the doodad drew
-- chosen; the target stays as it is.
local function useDoodad()
	pinned = { entry = doodad.entry, placement = doodad, name = doodad.name }
	frame.Search:SetText("")
	frame.Results:Hide()
	shown = nil
	refresh()
end

--- Import the doodad picked: it becomes a gob, selected like any other, which Source and Target
-- each follow while ticked; the sets the doodad drew come chosen when the source shows that gob.
-- Either kept as it is stays so, the source's chosen sets and all. The doodad is hidden, not
-- gone, and stays selected, so it stays in its slot.
local function importDoodad()
	doodad.imported = true
	if not pinned then
		marks, chosen, shown = doodad, {}, nil
	end
	Console.Import({ uid = doodad.uid, only = true })
	update()
end

--- A number typed: the target is the player's own from here on.
local function numberChanged(box, typed)
	if not typed then
		return
	end
	local value = tonumber(box:GetText())
	if not value then
		return
	end
	spot = spot or copy(Pose.At(0, 0, 0), "A position", "")
	if box.number.part then
		spot[box.number.part][box.number.key] = value
	else
		spot.scale = value
	end
	spotPinned, edited = true, true
	update()
end

--- A doodad `.doodad select` picked: a WMO Furnish has sets for fills the doodad slot and its
-- panel, each set marked where the doodad draws it, as part of its model or as the map chose;
-- the source and the target stay the gob selection's.
local function doodadSelected(line)
	local named = Furnish.Commands.SelectedDoodad(line)
	local of = named and Console.Source({ entry = named.entry, placement = named })
	if run or not of then
		return
	end
	for _, set in ipairs(of.sets) do
		set.draws = set.placed or (set.index == 0 and not of.blank)
	end
	named.name, named.sets = Client.ModelName(named.name), of.sets
	doodad = named
	fillDoodad()
	update()
end

--- The gob selection changed; the doodad slot is a selection of its own and keeps what it holds.
local function selectionChanged()
	refresh()
end

--- Lay the position's boxes across the window's width, each row split into equal boxes with the
-- same gap between each, and set every value in after its axis word.
local function layoutNumbers()
	local width = frame:GetWidth() - 40
	for row, bottom in ipairs(NUMBER_ROWS) do
		local boxes = {}
		for _, number in ipairs(NUMBERS) do
			if number.row == row then
				boxes[#boxes + 1] = frame[number.box]
			end
		end
		local art = (width - (#boxes - 1) * NUMBER_GAP) / #boxes
		for i, box in ipairs(boxes) do
			box:ClearAllPoints()
			box:SetPoint(
				"TOPLEFT",
				frame,
				"BOTTOMLEFT",
				20 + (i - 1) * (art + NUMBER_GAP) + NUMBER_ART,
				bottom
			)
			box:SetWidth(art - NUMBER_ART)
			box:SetTextInsets(box.Axis:GetStringWidth() + 6, 4, 0, 0)
		end
	end
	-- The source's ID box is as wide as one of the three on the target's first row.
	local id = frame.SourceID
	id:SetWidth((width - 2 * NUMBER_GAP) / 3 - NUMBER_ART)
	id:SetTextInsets(id.Axis:GetStringWidth() + 6, 4, 0, 0)
end

--- Size each button to its words and its caps.
local function fitButtons()
	for _, button in ipairs({ frame.Here, frame.UseSelected, frame.Highlight }) do
		button:SetWidth(math.ceil(button:GetFontString():GetStringWidth()) + CAPS)
	end
end

--- Make a list of rows, each made from a template, in a box made from FurnishListTemplate,
-- whose scroll bar shows only while there is somewhere to scroll.
local function listOf(box, data, template, initializer)
	box:SetBackdrop(PANEL)
	box:SetBackdropColor(0, 0, 0, 0.6)
	box:SetBackdropBorderColor(0.75, 0.75, 0.75)
	local view = _G.CreateScrollBoxListLinearView()
	view:SetElementExtent(ROW)
	view:SetElementInitializer("Button", template, Client.Guarded(initializer))
	-- A list sized to its rows can come out a hair short of them once the screen rounds it to
	-- whole pixels, which Blizzard's own test reads as something to scroll; less than a unit
	-- hidden is nothing to scroll.
	box.ScrollBox.HasScrollableExtent = function(scroll)
		return scroll:GetVisibleExtent() > 0 and scroll:GetDerivedScrollRange() >= 1
	end
	_G.ScrollUtil.InitScrollBoxListWithScrollBar(box.ScrollBox, box.ScrollBar, view)
	local anchor = _G.CreateAnchor
	_G.ScrollUtil.AddManagedScrollBarVisibilityBehavior(box.ScrollBox, box.ScrollBar, {
		anchor("TOPLEFT", box, "TOPLEFT", 8, -8),
		anchor("BOTTOMRIGHT", box, "BOTTOMRIGHT", -22, 8),
	}, {
		anchor("TOPLEFT", box, "TOPLEFT", 8, -8),
		anchor("BOTTOMRIGHT", box, "BOTTOMRIGHT", -8, 8),
	})
	box.ScrollBox:SetDataProvider(data)
end

--- An import the player typed marks the doodad in the panel imported where it is the one, since
-- the server refuses a second import. The window sends nothing for it: the server selects the gob
-- it made but sends no record of it, and reading that gob is the player's own `.gob select`.
local function importHeard(line)
	local uid = Furnish.Commands.Imported({ line })
	if uid and doodad and tostring(doodad.uid) == uid and not doodad.imported then
		doodad.imported = true
		update()
	end
end

local function listen()
	stops = {
		Client.OnSelection(selectionChanged),
		Client.OnPhaseChange(update),
		Client.OnSystemLine(doodadSelected),
		Client.OnSystemLine(importHeard),
	}
end

local function stopListening()
	for _, stop in pairs(stops) do
		stop()
	end
	stops = {}
end

local function buildSearch()
	local search = frame.Search
	search.Instructions:SetText("Search a WMO by name")
	search:HookScript("OnTextChanged", Client.Guarded(searchChanged))
	search:HookScript("OnEnterPressed", Client.Guarded(searched))
	search:HookScript("OnEscapePressed", function()
		frame.Results:Hide()
	end)
	search:SetScript(
		"OnArrowPressed",
		Client.Guarded(function(_, key)
			if frame.Results:IsShown() and (key == "UP" or key == "DOWN") then
				light(picked + (key == "UP" and -1 or 1))
			end
		end)
	)
	-- Leaving the box closes the list, unless the click that left it was on the list.
	search:HookScript("OnEditFocusLost", function()
		if not _G.DoesAncestryInclude(frame.Results, _G.GetMouseFocus()) then
			frame.Results:Hide()
		end
	end)
	listOf(frame.Results, found, "FurnishResultRowTemplate", initResult)
	frame.Results:SetBackdrop(OVERLAY)
	frame.Results:SetBackdropColor(0.06, 0.06, 0.06, 1)
	frame.Results:SetBackdropBorderColor(0.75, 0.75, 0.75)
end

local function buildSource()
	frame.SourceLabel:SetText("Source")
	frame.SourceFollow.Label:SetText("Follow selection")
	frame.SourceFollow:SetScript("OnClick", Client.Guarded(followSource))
	hint(frame.SourceFollow, "Follow selection", {
		{ text = "Ticked, the sets are those of the selected WMO." },
		{ text = "Unticked, they stay this WMO's whatever gob is selected." },
	})
	-- Typed in and left, by Enter or a click away, the ID takes; Escape puts back the one shown.
	local id = frame.SourceID
	id.Axis:SetText("ID")
	id.Axis:SetTextColor(GREY[1], GREY[2], GREY[3])
	id:SetScript("OnEnterPressed", id.ClearFocus)
	id:SetScript("OnEscapePressed", function(box)
		box:SetText(shownEntry and tostring(shownEntry) or "")
		box:ClearFocus()
	end)
	id:HookScript("OnEditFocusGained", id.HighlightText)
	id:HookScript("OnEditFocusLost", Client.Guarded(idChanged))
	hint(id, "ID", {
		{ text = "The gob entry whose WMO the sets come from." },
		{ text = "Type one to keep that WMO whatever gob is selected." },
	})
	listOf(list, provider, "FurnishSetRowTemplate", initRow)
	list:SetBackdropColor(0, 0, 0, 0.25)
	list.ScrollBox:RegisterCallback(
		_G.BaseScrollBoxEvents.OnScroll,
		Client.Guarded(updateMore),
		list
	)
	list.Above.Arrow:SetTexture("Interface\\Buttons\\Arrow-Up-Up")
	list.Below.Arrow:SetTexture("Interface\\Buttons\\Arrow-Down-Up")
	list.Above.Edge:SetPoint("BOTTOMLEFT")
	list.Above.Edge:SetPoint("BOTTOMRIGHT")
	list.Below.Edge:SetPoint("TOPLEFT")
	list.Below.Edge:SetPoint("TOPRIGHT")
	for _, edge in ipairs({ list.Above, list.Below }) do
		edge:SetScript(
			"OnClick",
			Client.Guarded(function(button)
				list.ScrollBox:ScrollToElementDataIndex(button.nearest)
			end)
		)
	end
end

local function buildTarget()
	frame.TargetLabel:SetText("Target")
	frame.TargetFollow.Label:SetText("Follow selection")
	frame.TargetFollow:SetScript("OnClick", Client.Guarded(followTarget))
	hint(frame.TargetFollow, "Follow selection", {
		{
			text = "Ticked, the target is the selected gob, or where you stand while no gob is selected.",
		},
		{ text = "Unticked, the target stays as it is whatever gob is selected." },
	})
	for order, number in ipairs(NUMBERS) do
		local box = frame[number.box]
		box.number = number
		number.order = order
		box.Axis:SetText(number.box)
		box:HookScript("OnTextChanged", Client.Guarded(numberChanged))
		box:SetScript("OnEnterPressed", box.ClearFocus)
		-- Leaving a box shows the value the target holds, so text that is no number does not stay.
		box:HookScript("OnEditFocusLost", Client.Guarded(update))
		-- Typing replaces the number, and Tab moves on through the boxes, as in ObjectMover.
		box:HookScript("OnEditFocusGained", box.HighlightText)
		box:SetScript(
			"OnTabPressed",
			Client.Guarded(function(self)
				local step = _G.IsShiftKeyDown() and -1 or 1
				local after = NUMBERS[(self.number.order - 1 + step) % #NUMBERS + 1]
				frame[after.box]:SetFocus()
			end)
		)
	end
	frame.Here:SetText("Here")
	frame.UseSelected:SetText("Use selected gob")
	frame.Here:SetScript(
		"OnClick",
		Client.Guarded(function()
			local here = Pose.Here()
			fillTarget(here and copy(here, "Your position", "Where you stood"))
		end)
	)
	frame.UseSelected:SetScript(
		"OnClick",
		Client.Guarded(function()
			local from = selectedForTarget()
			if from and from.group then
				return fillTarget(copy(from, "A group", "Led by " .. from.name))
			end
			fillTarget(from and copy(from, nil, gobDetail(from)))
		end)
	)
	hint(
		frame.Here,
		"Here",
		{ { text = "Fill the target with where you stand and the way you face, once." } },
		"<set> here"
	)
	hint(frame.UseSelected, function()
		return frame.UseSelected:GetText()
	end, function()
		local from = selectedForTarget()
		if from and from.group then
			return {
				{ text = "Fill the target with the selected group's position and facing, once." },
				{ text = "A group has no roll or pitch of its own, so the target is level." },
				{ text = "With Include the target, the objects join that group." },
			}
		end
		return { { text = "Fill the target with the selected gob's position, once." } }
	end)

	frame.Grouped.text:SetText("Group on spawn")
	frame.Grouped:SetChecked(true)
	frame.Include.text:SetText("Include the target")
	frame.NoPivot.text:SetText("No pivot")
	frame.Warning:SetPoint("LEFT", frame.Include.text, "RIGHT", 4, 0)
	for _, box in ipairs({ frame.Grouped, frame.Include, frame.NoPivot }) do
		box:SetScript("OnClick", Client.Guarded(update))
	end
	hint(frame.Grouped, "Group on spawn", function()
		return {
			{ text = "The spawned objects form one group, so they move as one." },
			{
				text = "Unless the target is included or No pivot is ticked, a pivot leads the group: one extra, invisible object where the WMO stands.",
			},
		}
	end, "<set>")
	hint(frame.NoPivot, "No pivot", {
		{ text = "The set's first object leads the group, so no extra object spawns." },
		{
			text = "A group turns and scales around its leader, so it then turns around that object rather than around the WMO.",
		},
	}, "<set> first")
	hint(frame.Include, "Include the target", function()
		local why = cannotInclude()
		return {
			{
				text = "The target joins the group and leads it, so moving the target moves everything, and no pivot spawns.",
			},
			{
				text = "If the target is in a group already, the objects join that group; Spawn asks first.",
			},
			why and { text = why, colour = RED },
		}
	end, "<set> attach")
	frame.Warning:SetScript(
		"OnEnter",
		Client.Guarded(function(button)
			tip(button, "The target is in a group", {
				{ text = spot.name .. " is in a group already, so the objects join that group." },
				{ text = "Spawn asks before it starts.", colour = GREY },
			})
		end)
	)
	frame.Warning:SetScript("OnLeave", _G.GameTooltip_Hide)
	frame:HookScript("OnSizeChanged", Client.Guarded(layoutNumbers))
	layoutNumbers()
end

local function buildDoodad()
	panel.Label:SetText("Doodad")
	panel.UseSource:SetText("Use as source")
	panel.Import:SetText("Import doodad")
	listOf(panel.Sets, drawn, "FurnishSetRowTemplate", initDrawn)
	panel.Sets:SetBackdropColor(0, 0, 0, 0.25)
	-- Closed, the panel lets the doodad go; selecting one again brings it back.
	panel.CloseButton:SetScript(
		"OnClick",
		Client.Guarded(function()
			doodad = nil
			fillDoodad()
			update()
		end)
	)
	panel.UseSource:SetScript("OnClick", Client.Guarded(useDoodad))
	panel.Import:SetScript("OnClick", Client.Guarded(importDoodad))
	hint(panel.UseSource, "Use as source", {
		{
			text = "Show the sets of the doodad's WMO as the source, kept whatever gob is selected, with the sets the doodad drew beyond its base chosen.",
		},
		{ text = "The target stays as it is." },
	})
	hint(panel.Import, "Import doodad", importLines, "import")
end

local function buildFooter()
	frame.Highlight:SetText("Highlighting")
	frame.Highlight:SetScript("OnClick", Client.Guarded(Console.ToggleHighlight))
	hint(frame.Highlight, "Highlighting", {
		{ text = "The client's outline on selected objects, on or off." },
		{
			text = "Highlighting too many objects can crash the game, so you may want it off before a big spawn.",
		},
	})
	frame.Notice:SetScript(
		"OnEnter",
		Client.Guarded(function(button)
			tip(button, "Before you spawn", button.said or {})
		end)
	)
	frame.Notice:SetScript("OnLeave", _G.GameTooltip_Hide)
	frame.SpawnButton:SetScript("OnClick", Client.Guarded(spawn))
	frame.DeleteButton:SetText("Stop and delete")
	frame.DeleteButton:SetScript(
		"OnClick",
		Client.Guarded(function()
			Console.Stop(true)
		end)
	)
	hint(
		frame.DeleteButton,
		"Stop and delete",
		{ { text = "Stop, then delete everything this run spawned." } }
	)

	-- The clock on the bar moves between replies too.
	local since = 0
	frame.Progress:SetScript("OnUpdate", function(_, elapsed)
		since = since + elapsed
		if run and since >= 0.25 then
			since = 0
			progressText()
		end
	end)
end

local function build()
	frame.Header:Setup("Furnish")
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
	-- Moved or resized by hand, the game's own layout cache keeps the window's place and size.
	frame:SetMinResize(MIN_WIDTH, MIN_HEIGHT)
	frame:SetMaxResize(MIN_WIDTH * 2, MIN_HEIGHT * 2)
	frame.Grip:SetScript("OnMouseDown", function()
		-- Held by its centre, the frame would grow on both sides and the corner leave the cursor;
		-- held by its top left corner, the corner dragged is the one that moves.
		local left, top = frame:GetLeft(), frame:GetTop()
		frame:ClearAllPoints()
		frame:SetPoint("TOPLEFT", _G.UIParent, "BOTTOMLEFT", left, top)
		frame:StartSizing("BOTTOMRIGHT")
	end)
	frame.Grip:SetScript("OnMouseUp", function()
		frame:StopMovingOrSizing()
		update()
	end)
	table.insert(_G.UISpecialFrames, frame:GetName())

	buildSearch()
	buildSource()
	buildTarget()
	buildDoodad()
	buildFooter()

	frame:SetScript(
		"OnShow",
		Client.Guarded(function()
			_G.PlaySound(_G.SOUNDKIT.IG_CHARACTER_INFO_OPEN)
			-- A size the game kept from an older window may be smaller than this layout needs.
			local width, height = frame:GetSize()
			if width < MIN_WIDTH or height < MIN_HEIGHT then
				frame:SetSize(math.max(width, MIN_WIDTH), math.max(height, MIN_HEIGHT))
			end
			-- A position read when nothing was selected is read again when the window opens, so it is
			-- where the player stands now rather than wherever they stood last time.
			if not spotPinned and spot and not spot.guid then
				spot = nil
			end
			-- Fitted here, once every label is set and the client's fonts are certainly loaded.
			fitButtons()
			layoutNumbers()
			listen()
			refresh()
			-- Started now, so the models are usually named by the time a set is rested on; a WMO
			-- shown by its entry takes its name from the same walk, once it ends.
			Console.NameModels(Client.Guarded(function()
				if frame:IsShown() and pinned and pinned.entry and not pinned.placement then
					refresh()
				end
			end))
		end)
	)
	frame:SetScript(
		"OnHide",
		Client.Guarded(function()
			_G.PlaySound(_G.SOUNDKIT.IG_CHARACTER_INFO_CLOSE)
			frame.Results:Hide()
			stopListening()
		end)
	)

	Console.Watch({
		started = Client.Guarded(started),
		progress = Client.Guarded(progressed),
		finished = Client.Guarded(finished),
		-- A wait ends on the record of the object it waited for, which reaches the window's own
		-- listener while the wait still stands, so the button is redrawn when the wait ends too.
		waiting = Client.Guarded(update),
	})
end

--- Show the window, or hide it when it shows.
function Window.Toggle()
	frame:SetShown(not frame:IsShown())
end

build()
