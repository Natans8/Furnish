-- The window: where a WMO's sets come from, which of them to spawn, and where they go, read top
-- to bottom, with a run's progress at the foot.
--
-- A surface over Console, as the commands are: it reads Source for the sets, Target for the
-- selected object's pose, Find for a name searched, Busy for whether it may start and Watch for
-- the run going on, and spawns, imports and stops through the same doors, so the window and
-- the commands can never disagree. The layout is Window.xml; this file gives it behaviour and
-- every word.
--
-- The window works on gobs. Its sets are the selected WMO's until a WMO is searched or the pin is
-- clicked, and the spot they go to is the selected object's until a number of it is changed, Me
-- or Selected fills it, or its pin is clicked. A doodad `.doodad select` picks is a step before
-- that: its button imports it, the gob it becomes is selected and followed like any other, and
-- the sets the doodad showed come chosen. A selection the sets cannot come from is said, never
-- passed over, and while a run goes nothing changes, since every spawn moves the selection.

_G.Furnish = _G.Furnish or {}
local Furnish = _G.Furnish
local Window = {}
Furnish.Window = Window

local Console = Furnish.Console
local Client = Furnish.Client
local Pose = Furnish.Pose
local Rows = Furnish.Rows
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

--- The tooltip's colours: a label, a value beside it, and what a click does.
local GREY, WHITE, GREEN = { 0.62, 0.62, 0.62 }, { 1, 1, 1 }, { 0.25, 1, 0.25 }

local ROW = 22

--- The smallest the window may be drawn, which is the size its layout was made for; it may grow
-- to twice that.
local MIN_WIDTH, MIN_HEIGHT = 400, 600

--- How many letters a name search waits for, and how many WMOs it lists at most.
local SEARCH_FROM, RESULTS = 3, 60

--- How many models the contents line names before it says how many more there are.
local NAMED = 4

--- The position's numbers on a grid of three columns, one an axis: X, Y and Z, then the turn
-- about each, then the scale. Each is the box that shows it, its row and column, and where the
-- pose keeps it.
local NUMBERS = {
	{ box = "X", label = "X", row = 1, column = 1, part = "position", key = "x" },
	{ box = "Y", label = "Y", row = 1, column = 2, part = "position", key = "y" },
	{ box = "Z", label = "Z", row = 1, column = 3, part = "position", key = "z" },
	{ box = "Roll", label = "Roll", row = 2, column = 1, part = "rotation", key = "roll" },
	{ box = "Pitch", label = "Pitch", row = 2, column = 2, part = "rotation", key = "pitch" },
	{ box = "Turn", label = "Turn", row = 2, column = 3, part = "rotation", key = "turn" },
	{ box = "Scale", label = "Scale", row = 3, column = 1 },
}

--- Where the grid's first row stands under Onto's top, how far apart its rows are, and how many
-- columns it has.
local NUMBERS_TOP, NUMBERS_ROW, NUMBERS_COLUMNS = -26, 24, 3

--- The search list's own backdrop: flat and nearly opaque, since it lies over the window.
local OVERLAY = {
	bgFile = "Interface\\Buttons\\WHITE8X8",
	edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
	tile = false,
	edgeSize = 16,
	insets = { left = 4, right = 4, top = 4, bottom = 4 },
}

local frame = _G.FurnishFrame
local source, list, onto = frame.Source, frame.Sets, frame.Onto
local provider, found = _G.CreateDataProvider(), _G.CreateDataProvider()

--- Where the sets come from: the Source request pinned, or nil to follow the selection; the
-- doodad imported last, whose sets come chosen while its WMO is shown; the source shown, or nil
-- and why there is none; the sets chosen, by index, and the one a shift-click runs from.
local pinned, marks, shown
local chosen, anchor = {}, nil

--- Where the sets go: the pose shown, its own copy; what to call it where it is no object's;
-- whether it stays when the selection moves; and the doodad picked and not yet imported.
local spot, spotName, spotPinned, doodad = nil, nil, false, nil

--- The run going on, as the window draws it: { total, done, started }.
local run

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
local function copy(pose)
	local own = {}
	for key, value in pairs(pose) do
		own[key] = value
	end
	own.position = { x = pose.position.x, y = pose.position.y, z = pose.position.z }
	own.rotation =
		{ roll = pose.rotation.roll, pitch = pose.rotation.pitch, turn = pose.rotation.turn }
	return own
end

local function valueOf(pose, number)
	if number.part then
		return pose[number.part][number.key]
	end
	return pose.scale
end

--- Show a tooltip: a title, label and value pairs, and lines in a colour of their own.
-- @param lines each { label, value } for a pair, or { text, colour } for a line of its own
local function tip(owner, title, lines)
	local tooltip = _G.GameTooltip
	tooltip:SetOwner(owner, "ANCHOR_RIGHT")
	tooltip:SetText(title, 1, 0.82, 0)
	for _, line in ipairs(lines) do
		if line.value then
			local value = tostring(line.value)
			tooltip:AddDoubleLine(line.label, value, GREY[1], GREY[2], GREY[3], 1, 1, 1)
		else
			local colour = line.colour or WHITE
			tooltip:AddLine(line.text, colour[1], colour[2], colour[3], true)
		end
	end
	tooltip:Show()
end

--- Give a control a tooltip: what it does, and how a command types it, read when shown, since
-- the command's name is only known once every file has loaded.
local function hint(owner, title, text, words)
	owner:SetScript(
		"OnEnter",
		Client.Guarded(function()
			local typed = words and { text = "Typed: " .. Chat.Typed(words), colour = GREY }
			tip(owner, title, { { text = text }, typed })
		end)
	)
	owner:SetScript("OnLeave", _G.GameTooltip_Hide)
end

--- The object the sets may join the group of, or nil.
local function joinable()
	return spot and spot.guid and Client.CanEdit(spot) and spot.name or nil
end

--- The request's group, from the two boxes: loose, joining the target's group where it may be
-- joined, or a group of their own, which the pivot leads.
local function grouped()
	if not onto.Grouped:GetChecked() then
		return "nogroup"
	elseif onto.Join:GetChecked() and joinable() then
		return "attach"
	end
	return "pivot"
end

--- Whether the selected WMO shows a set already: its base set, unless Epsilon emptied it. A WMO
-- searched or pinned stands nowhere.
local function current(set)
	return not pinned and set.index == 0 and not shown.blank
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
		return "Select where to spawn", false
	end
	return "Spawn " .. objects(count), true
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
		button:SetText(("%d more chosen"):format(#hidden))
	end
end

--- What the chosen sets hold, by model, the most numerous first: a list of { name, count }, and
-- the displays the client's catalogue has not yet named.
local function contents()
	local counts, unknown, seen = {}, {}, {}
	for _, set in ipairs(shown.sets) do
		for _, row in ipairs(chosen[set.index] and Rows.OfSet(set.id) or {}) do
			local model = Client.DisplayModel(row.display)
			local name = model and Client.ModelName(model) or ("display " .. row.display)
			if not model and not seen[row.display] then
				unknown[#unknown + 1], seen[row.display] = row.display, true
			end
			counts[name] = (counts[name] or 0) + 1
		end
	end
	local held = {}
	for name, count in pairs(counts) do
		held[#held + 1] = { name = name, count = count }
	end
	table.sort(held, function(a, b)
		return a.count > b.count or (a.count == b.count and a.name < b.name)
	end)
	return held, unknown
end

local updateContents

--- Say on one line what the chosen sets hold, asking the client's catalogue for any model it
-- has not named yet, which names it a moment later.
function updateContents()
	if not shown or #(chosenSets()) == 0 then
		frame.Contents.held = nil
		return frame.Contents.Text:SetText("")
	end
	local held, unknown = contents()
	frame.Contents.held = held
	local named = {}
	for i = 1, math.min(NAMED, #held) do
		named[i] = ("%s x%d"):format(held[i].name, held[i].count)
	end
	local more = #held > NAMED and (", and %d more"):format(#held - NAMED) or ""
	frame.Contents.Text:SetText("Holds " .. table.concat(named, ", ") .. more)
	if #unknown > 0 then
		Client.WalkDisplays(unknown, updateContents)
	end
end

local function updateOnto()
	if spot then
		onto.Name:SetText(spot.name or spotName or "A position")
	else
		onto.Name:SetText("|cff808080Select where to spawn|r")
	end
	onto.Follow:SetChecked(not spotPinned)
	for _, number in ipairs(NUMBERS) do
		local box = onto[number.box]
		if not box:HasFocus() then
			box:SetText(spot and shownNumber(valueOf(spot, number)) or "")
		end
		box:SetEnabled(not run)
	end
	onto.FromDoodad:SetShown(doodad ~= nil)
	if doodad then
		onto.FromDoodad:SetText("Import " .. doodad.name)
		onto.FromDoodad:SetEnabled(not run)
	end
	local canJoin = onto.Grouped:GetChecked() and joinable() ~= nil
	onto.Join:SetEnabled(canJoin)
	onto.Join.text:SetFontObject(canJoin and _G.GameFontHighlightSmall or _G.GameFontDisableSmall)
	onto.Warning:SetShown(grouped() == "attach" and (spot.groupLeader or 0) ~= 0)
end

local function update()
	list.ScrollBox:ForEachFrame(mark)
	updateMore()
	updateContents()
	updateOnto()
	local text, enabled = action()
	frame.SpawnButton:SetText(text)
	frame.SpawnButton:SetEnabled(enabled)
	local last = not run and Console.Last()
	frame.DeleteButton:SetShown(run ~= nil or last ~= nil)
	frame.DeleteButton:SetText(run and "Stop and delete" or "Delete them")
	frame.DeleteButton.last = last
	frame.SpawnButton:SetPoint("BOTTOMRIGHT", (run or last) and -142 or -18, 14)
end

--- Spawn the chosen sets where the window says, or stop the run.
local function spawn()
	if run then
		return Console.Stop(false)
	end
	local text, enabled = action()
	if not enabled then
		return Chat.Say(text)
	end
	Console.Spawn({
		indexes = (chosenSets()),
		file = shown.file,
		label = shown.name,
		at = spot,
		group = grouped(),
		quiet = true,
	})
end

--- What is chosen when a WMO is first shown: the sets a doodad imported from it showed;
-- else its first set past the base, and the base too where Epsilon emptied the WMO, since it
-- draws none of its own.
local function chooseFirst(sets, blank)
	chosen, anchor = {}, nil
	for _, set in ipairs(sets) do
		if set.placed then
			chosen[set.index], anchor = true, anchor or set.index
		end
	end
	if anchor then
		return
	end
	for _, set in ipairs(sets) do
		if set.index ~= 0 then
			chosen[set.index], anchor = true, set.index
			break
		end
	end
	if blank and sets[1] and sets[1].index == 0 then
		chosen[0] = true
	end
end

--- Read the window afresh: the source and the spot follow the selection unless pinned.
local function refresh()
	if run then
		return
	end
	local before = shown
	shown = Console.Source(pinned or (marks and { placement = marks }) or nil)
	local fresh = shown and not (before and before.file == shown.file)
	if fresh then
		chooseFirst(shown.sets, shown.blank)
	end
	if not spotPinned then
		local selected = Console.Target()
		spot, spotName = selected and copy(selected), nil
	end
	source.Follow:SetChecked(not pinned)
	provider:Flush()
	if shown then
		local count = #shown.sets .. (#shown.sets == 1 and " set" or " sets")
		source.Name:SetText(shown.name)
		source.Detail:SetText(count .. (shown.blank and ", emptied" or ""))
		provider:InsertTable(shown.sets)
	else
		local selected = not pinned and Console.Target()
		if pinned then
			source.Name:SetText(pinned.name or ("Entry %d"):format(pinned.entry))
			source.Detail:SetText("No sets")
		elseif selected then
			source.Name:SetText(selected.name)
			source.Detail:SetText(selected.wmo and "No sets" or "Not a WMO")
		else
			source.Name:SetText("|cff808080Nothing selected|r")
			source.Detail:SetText("")
		end
		list.Empty:SetText(pinned and "Search another WMO." or "Select a WMO, or search one.")
	end
	list.Empty:SetShown(not shown)
	update()
end

local function progressText()
	frame.Progress.Text:SetText(
		("%s of %s   %s"):format(
			thousands(run.done),
			thousands(run.total),
			clock(Client.Now() - run.started)
		)
	)
end

local function started(total)
	run = { total = total, done = 0, started = Client.Now() }
	frame.Progress:SetMinMaxValues(0, math.max(total, 1))
	frame.Progress:SetValue(0)
	frame.Progress:Show()
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
		frame.Progress:Hide()
		return refresh()
	end
	local placed = #result.spawned - (result.pivot and 1 or 0)
	local line
	if result.undone then
		line = ("Deleted %s"):format(objects(result.deleted))
	elseif result.deleted then
		line = ("Stopped, %s deleted"):format(objects(result.deleted))
	elseif result.aborted then
		line = ("Stopped: %s of %s"):format(thousands(placed), thousands(result.total))
	else
		line = ("Done: %s in %s"):format(objects(placed), clock(seconds))
	end
	local missed = #result.refused + #result.unjoined
	if missed > 0 then
		line = line .. (", %d not placed or grouped; see chat"):format(missed)
	end
	frame.Progress:SetValue(result.deleted and 0 or placed)
	frame.Progress.Text:SetText(line)
	refresh()
end

--- Where a set stands in the list, or nil.
local function positionOf(index)
	for position, set in ipairs(shown.sets) do
		if set.index == index then
			return position
		end
	end
	return nil
end

--- Select as a file list does: a click selects the one set, a ctrl-click adds or removes one,
-- and a shift-click selects the run from the last set clicked.
local function rowClick(button)
	_G.PlaySound(_G.SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
	local index = button:GetElementData().index
	local from = anchor and positionOf(anchor)
	if _G.IsShiftKeyDown() and from then
		local to = positionOf(index)
		chosen = {}
		for position = math.min(from, to), math.max(from, to) do
			chosen[shown.sets[position].index] = true
		end
	elseif _G.IsControlKeyDown() then
		chosen[index], anchor = not chosen[index] or nil, index
	else
		chosen, anchor = { [index] = true }, index
	end
	update()
end

local function rowEnter(button)
	local set = button:GetElementData()
	local lines = {
		{ label = "Set", value = set.index },
		{ label = "Objects", value = thousands(set.count) },
	}
	if set.canonical ~= "" then
		lines[#lines + 1] = { label = "In the file", value = set.canonical }
	end
	if current(set) then
		lines[#lines + 1] = { text = "The selected WMO shows it now", colour = GREEN }
	elseif set.placed then
		lines[#lines + 1] = { text = "The doodad showed it", colour = GREEN }
	end
	lines[#lines + 1] =
		{ text = "Click: choose it. Ctrl: add it. Shift: choose the run", colour = GREEN }
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
	button.Tag:SetText(current(set) and "current" or "")
	mark(button, set)
end

--- Show the sets of a WMO a search found, and keep them whatever is selected.
local function pick(button)
	_G.PlaySound(_G.SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
	local wmo = button:GetElementData()
	pinned = { file = wmo.file, name = wmo.name }
	frame.Search:ClearFocus()
	frame.Results:Hide()
	refresh()
end

--- A found WMO's tooltip, read off the row as it stands, since rows are reused as the list
-- scrolls.
local function resultEnter(button)
	local wmo = button:GetElementData()
	tip(button, wmo.name, {
		{ label = "Sets", value = wmo.sets },
		{ label = "File", value = wmo.file },
		{ text = "Click: show its sets", colour = GREEN },
	})
end

local function initResult(button, wmo, new)
	if new then
		button:SetScript("OnClick", Client.Guarded(pick))
		button:SetScript("OnEnter", Client.Guarded(resultEnter))
		button:SetScript("OnLeave", _G.GameTooltip_Hide)
	end
	button.Label:SetText(wmo.name)
	button.Count:SetText(wmo.sets == 1 and "1 set" or wmo.sets .. " sets")
	button.Tag:SetText(wmo.blank and "emptied" or "")
end

--- A search typed: a name lists the WMOs it finds under the box; a number waits for Enter.
local function searchChanged(box, typed)
	if not typed then
		return
	end
	local text = box:GetText():match("^%s*(.-)%s*$")
	found:Flush()
	if tonumber(text) or #text < SEARCH_FROM then
		return frame.Results:Hide()
	end
	local wmos = Console.Find(text)
	for i = 1, math.min(RESULTS, #wmos) do
		found:Insert(wmos[i])
	end
	frame.Results.Empty:SetText(("No WMO with sets is named like %s."):format(text))
	frame.Results.Empty:SetShown(#wmos == 0)
	frame.Results:SetHeight(math.min(#wmos, 8) * ROW + 16 + (#wmos == 0 and 40 or 0))
	frame.Results:Show()
end

--- A search entered: an entry, the number after a name on a lookup line, shows its WMO's sets;
-- a name shows the first WMO it found.
local function searched(box)
	box:ClearFocus()
	local text = box:GetText():match("^%s*(.-)%s*$")
	local entry = tonumber(text)
	if entry then
		pinned = { entry = entry }
	elseif found:GetSize() > 0 then
		local first = found:Find(1)
		pinned = { file = first.file, name = first.name }
	else
		return
	end
	frame.Results:Hide()
	refresh()
end

--- Follow the selection with the sets, or keep the WMO shown whatever is selected.
local function followSource(box)
	if box:GetChecked() then
		pinned = nil
		frame.Search:SetText("")
	elseif shown then
		pinned = { file = shown.file, name = shown.name }
	end
	refresh()
end

--- Follow the selection with the spot, or keep the position shown whatever is selected.
local function followSpot(box)
	spotPinned = not box:GetChecked() and spot ~= nil
	refresh()
end

--- Fill the spot from the player or the selection, and keep it there.
local function fillSpot(pose, name)
	if pose then
		spot, spotName, spotPinned = copy(pose), name, true
	end
	update()
end

--- Import the doodad picked: it becomes a gob, selected, which the spot follows, and the sets it
-- showed come chosen when its WMO is shown.
local function importDoodad()
	marks, spotPinned = doodad, false
	doodad = nil
	chosen = {}
	shown = nil
	Console.Import({ uid = marks.uid, only = true })
	update()
end

--- A number typed: the spot is the player's own from here on.
local function numberChanged(box, typed)
	if not typed then
		return
	end
	local value = tonumber(box:GetText())
	if not value then
		return
	end
	spot = spot or copy(Pose.At(0, 0, 0))
	if box.number.part then
		spot[box.number.part][box.number.key] = value
	else
		spot.scale = value
	end
	spotPinned = true
	update()
end

--- A doodad `.doodad select` picked: a WMO Furnish has sets for gets its import button.
local function doodadSelected(line)
	local named = Furnish.Commands.SelectedDoodad(line)
	if run or not named or not Console.Source({ entry = named.entry }) then
		return
	end
	named.name = Client.ModelName(named.name)
	doodad = named
	update()
end

--- Lay the position's boxes out on their grid across Onto's width: every column as wide as the
-- next, every name in one column as wide as the widest, so the boxes of a column line up and no
-- width of the window leaves one outside it.
local function layoutNumbers()
	local width = onto:GetWidth()
	if width == 0 then
		return
	end
	local label = 0
	for _, number in ipairs(NUMBERS) do
		label = math.max(label, onto[number.box].Name:GetStringWidth())
	end
	local column = width / NUMBERS_COLUMNS
	for _, number in ipairs(NUMBERS) do
		local box = onto[number.box]
		box:ClearAllPoints()
		box:SetPoint(
			"TOPLEFT",
			onto,
			"TOPLEFT",
			(number.column - 1) * column + label + 14,
			NUMBERS_TOP - (number.row - 1) * NUMBERS_ROW
		)
		box:SetWidth(column - label - 24)
	end
end

--- Make a list of rows, each made from a template, in a box made from FurnishListTemplate.
local function listOf(box, data, template, initializer)
	box:SetBackdrop(PANEL)
	box:SetBackdropColor(0, 0, 0, 0.6)
	box:SetBackdropBorderColor(0.75, 0.75, 0.75)
	local view = _G.CreateScrollBoxListLinearView()
	view:SetElementExtent(ROW)
	view:SetElementInitializer("Button", template, Client.Guarded(initializer))
	_G.ScrollUtil.InitScrollBoxListWithScrollBar(box.ScrollBox, box.ScrollBar, view)
	box.ScrollBox:SetDataProvider(data)
end

local function listen()
	stops = {
		Client.OnSelection(refresh),
		Client.OnPhaseChange(update),
		Client.OnSystemLine(doodadSelected),
	}
end

local function stopListening()
	for _, stop in pairs(stops) do
		stop()
	end
	stops = {}
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

	local search = frame.Search
	search.Instructions:SetText("Search a WMO by name or entry")
	search:HookScript("OnTextChanged", Client.Guarded(searchChanged))
	search:HookScript("OnEnterPressed", Client.Guarded(searched))
	search:HookScript("OnEscapePressed", function()
		frame.Results:Hide()
	end)
	listOf(frame.Results, found, "FurnishResultRowTemplate", initResult)
	frame.Results:SetBackdrop(OVERLAY)
	frame.Results:SetBackdropColor(0.06, 0.06, 0.06, 0.98)
	frame.Results:SetBackdropBorderColor(0.75, 0.75, 0.75)

	source.Follow.Label:SetText("Follow selection")
	source.Follow:SetScript("OnClick", Client.Guarded(followSource))
	hint(
		source.Follow,
		"Follow selection",
		"Ticked, the sets are the selected WMO's. Unticked, they stay this WMO's whatever you select."
	)
	source:EnableMouse(true)
	source:SetScript(
		"OnEnter",
		Client.Guarded(function()
			if shown then
				tip(source, shown.name, { { label = "File", value = shown.file } })
			end
		end)
	)
	source:SetScript("OnLeave", _G.GameTooltip_Hide)

	listOf(list, provider, "FurnishSetRowTemplate", initRow)
	list:SetBackdropColor(0, 0, 0, 0.25)
	list.ScrollBox:RegisterCallback(
		_G.BaseScrollBoxEvents.OnScroll,
		Client.Guarded(updateMore),
		list
	)
	list.Above.Arrow:SetTexture("Interface\\Buttons\\Arrow-Up-Up")
	list.Below.Arrow:SetTexture("Interface\\Buttons\\Arrow-Down-Up")
	for _, edge in ipairs({ list.Above, list.Below }) do
		edge:SetScript(
			"OnClick",
			Client.Guarded(function(button)
				list.ScrollBox:ScrollToElementDataIndex(button.nearest)
			end)
		)
	end

	frame.Contents:SetScript(
		"OnEnter",
		Client.Guarded(function(button)
			if not button.held then
				return
			end
			local lines = {}
			for i, each in ipairs(button.held) do
				lines[i] = { label = each.name, value = each.count }
			end
			tip(button, "What the chosen sets hold", lines)
		end)
	)
	frame.Contents:SetScript("OnLeave", _G.GameTooltip_Hide)

	onto.Label:SetText("Onto")
	onto.FillLabel:SetText("Fill from")
	onto.GroupLabel:SetText("Group")
	onto.FromPlayer:SetText("Me")
	onto.FromSelection:SetText("Selected")
	onto.FromPlayer:SetScript(
		"OnClick",
		Client.Guarded(function()
			fillSpot(Pose.Here(), "Your position")
		end)
	)
	onto.FromSelection:SetScript(
		"OnClick",
		Client.Guarded(function()
			fillSpot(Console.Target())
		end)
	)
	onto.FromDoodad:SetScript("OnClick", Client.Guarded(importDoodad))
	onto.Follow.Label:SetText("Follow selection")
	onto.Follow:SetScript("OnClick", Client.Guarded(followSpot))
	hint(
		onto.FromPlayer,
		"Me",
		"Fill the position with yours, facing the way you face.",
		"<set> here"
	)
	hint(onto.FromSelection, "Selected", "Fill the position with the selected object's.")
	hint(
		onto.FromDoodad,
		"Import the doodad",
		"Turn the doodad you picked into a gob and spawn onto it; the sets it showed come chosen.",
		"import"
	)
	hint(
		onto.Follow,
		"Follow selection",
		"Ticked, the position is the selected object's. Unticked, it stays whatever you select."
	)
	onto.Grouped.text:SetText("Group them")
	onto.Grouped:SetChecked(true)
	onto.Join.text:SetText("Join its group")
	onto.Warning:SetPoint("LEFT", onto.Join.text, "RIGHT", 4, 0)
	for _, box in ipairs({ onto.Grouped, onto.Join }) do
		box:SetScript("OnClick", Client.Guarded(update))
	end
	hint(
		onto.Grouped,
		"Group them",
		"The spawned objects form one group, led by an invisible pivot where the WMO stands.",
		"<set>"
	)
	hint(
		onto.Join,
		"Join its group",
		"The objects join the group of the object they spawn on, or form one it leads.",
		"<set> attach"
	)
	onto.Warning:SetScript(
		"OnEnter",
		Client.Guarded(function(button)
			tip(button, "Already in a group", {
				{ text = spot.name .. " is in a group already; the sets join that group." },
			})
		end)
	)
	onto.Warning:SetScript("OnLeave", _G.GameTooltip_Hide)
	for _, number in ipairs(NUMBERS) do
		local box = onto[number.box]
		box.number = number
		box.Name:SetText(number.label)
		box:HookScript("OnTextChanged", Client.Guarded(numberChanged))
		box:SetScript("OnEnterPressed", box.ClearFocus)
	end
	onto:SetScript("OnSizeChanged", Client.Guarded(layoutNumbers))
	layoutNumbers()

	frame.SpawnButton:SetScript("OnClick", Client.Guarded(spawn))
	frame.DeleteButton:SetScript(
		"OnClick",
		Client.Guarded(function()
			if run then
				return Console.Stop(true)
			end
			Console.DeleteLast()
		end)
	)
	frame.DeleteButton:SetScript(
		"OnEnter",
		Client.Guarded(function(button)
			if run then
				return tip(
					button,
					"Stop and delete",
					{ { text = "Stop, then delete what was spawned." } }
				)
			end
			tip(button, "Delete them", {
				{
					text = ("Delete the %s the last run spawned."):format(
						objects(button.last or 0)
					),
				},
			})
		end)
	)
	frame.DeleteButton:SetScript("OnLeave", _G.GameTooltip_Hide)

	-- The clock on the bar moves between replies too.
	local since = 0
	frame.Progress:SetScript("OnUpdate", function(_, elapsed)
		since = since + elapsed
		if run and since >= 0.25 then
			since = 0
			progressText()
		end
	end)

	frame:SetScript(
		"OnShow",
		Client.Guarded(function()
			_G.PlaySound(_G.SOUNDKIT.IG_CHARACTER_INFO_OPEN)
			-- A size the game kept from an older window may be smaller than this layout needs.
			local width, height = frame:GetSize()
			if width < MIN_WIDTH or height < MIN_HEIGHT then
				frame:SetSize(math.max(width, MIN_WIDTH), math.max(height, MIN_HEIGHT))
			end
			listen()
			refresh()
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
	})
end

--- Show the window, or hide it when it shows.
function Window.Toggle()
	frame:SetShown(not frame:IsShown())
end

build()
