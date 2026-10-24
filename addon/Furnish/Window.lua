-- The window: a WMO's sets, which of them to spawn, how to group them and where, and a run's
-- progress.
--
-- A surface over Console, as the commands are: it reads Target for what to show, Busy for
-- whether it may start and Watch for the run going on, and spawns and stops through the same
-- doors, so the window and the commands can never disagree. The layout is Window.xml; this
-- file gives it behaviour. The last WMO shown stays when the selection moves off it, so its
-- sets can still go at the player; while a run goes nothing changes, since every spawn moves
-- the selection.

_G.Furnish = _G.Furnish or {}
local Furnish = _G.Furnish
local Window = {}
Furnish.Window = Window

local Console = Furnish.Console
local Client = Furnish.Client
local Chat = Furnish.Chat

--- The border every panel wears, ObjectMover's: a tooltip's edge over a faint shade.
local PANEL = {
	bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
	edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
	tile = true,
	tileEdge = true,
	tileSize = 16,
	edgeSize = 16,
	insets = { left = 5, right = 5, top = 5, bottom = 5 },
}

--- The choices the spawning panel offers, a row of radio buttons each. An option is the
-- request's value, what its button says, what its tooltip says it does, and either the words
-- a command types for it or the command word it takes; one that needs a WMO selected is
-- greyed, and stands down for the first option that needs none, while none is.
local CHOICES = {
	{
		label = "Group",
		field = "group",
		options = {
			{
				value = "pivot",
				label = "Pivot",
				hint = "An invisible marker at the WMO leads the group.",
			},
			{
				value = "first",
				label = "First object",
				hint = "The first object spawned leads the group.",
			},
			{
				value = "attach",
				label = "The WMO's group",
				hint = "The objects join the selected WMO's own group.",
				needsWmo = true,
			},
			{ value = "nogroup", label = "No group", hint = "The objects stand loose." },
		},
	},
	{
		label = "Where",
		field = "place",
		options = {
			{
				value = "target",
				label = "On target gob",
				hint = "The sets spawn on the selected WMO, where its file places them.",
				usage = "<set>",
				needsWmo = true,
			},
			{
				value = "player",
				label = "On player",
				hint = "The sets spawn at your feet, turned the way you face.",
				usage = "<set> here",
			},
		},
	},
}

--- Where the radio buttons sit in their panel: a choice's label at the left, its options two to
-- a row from RADIO_LEFT, the second column a gap past the widest first-column label, measured
-- in the player's own font; each choice starts a row below the last.
local RADIO_LEFT, RADIO_TOP, RADIO_ROW, RADIO_GAP = 64, -30, 22, 16

local frame = _G.FurnishFrame
local wmo, sets = frame.WmoPanel, frame.SetsPanel
local provider = _G.CreateDataProvider()

--- The WMO shown, kept when the selection moves off it; whether it is still selected; the sets
-- chosen in it, by index; and the option taken in each choice, by field.
local target, selected, chosen = nil, false, {}
local taken = { group = "pivot", place = "target" }

--- Every radio button, each knowing its choice and its option.
local radios = {}

--- The run going on, as the window draws it: { total, done, started, what }.
local run

local stopSelection

--- A count with its thousands set apart.
local function thousands(count)
	local text, done = tostring(count), 1
	while done > 0 do
		text, done = text:gsub("^(%d+)(%d%d%d)", "%1,%2")
	end
	return text
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

local function objects(count)
	return count == 1 and "1 object" or thousands(count) .. " objects"
end

--- How a command types an option: its usage, or the command word for its field and value read
-- off the command's own words, or the bare spawn for a default, which takes no word.
local function typed(choice, option)
	if option.usage then
		return Chat.Typed(option.usage)
	end
	for _, each in ipairs(Furnish.Command.WORDS) do
		if each.field == choice.field and each.value == option.value then
			return Chat.Typed("<set> " .. each.word)
		end
	end
	return Chat.Typed("<set>") .. ", with no word"
end

local function available(option)
	return not run and (selected or not option.needsWmo)
end

--- The option in force for a choice: the one taken, or the first that needs no WMO while the
-- one taken needs one and none is selected.
local function inForce(choice)
	local fallback
	for _, option in ipairs(choice.options) do
		if option.value == taken[choice.field] and (selected or not option.needsWmo) then
			return option.value
		end
		fallback = fallback or (not option.needsWmo and option.value) or nil
	end
	return fallback
end

local function choiceOf(field)
	for _, choice in ipairs(CHOICES) do
		if choice.field == field then
			return choice
		end
	end
	return nil
end

--- The chosen sets' indexes in the list's order, and how many objects they hold.
local function chosenSets()
	local indexes, count = {}, 0
	for _, set in ipairs(target and target.sets or {}) do
		if chosen[set.index] then
			indexes[#indexes + 1] = set.index
			count = count + set.count
		end
	end
	return indexes, count
end

local function updateRadios()
	for _, radio in ipairs(radios) do
		local usable = available(radio.option)
		radio:SetChecked(radio.option.value == inForce(radio.choice))
		radio:SetEnabled(usable)
		radio.text:SetFontObject(usable and _G.GameFontHighlightSmall or _G.GameFontDisableSmall)
	end
end

local function updateButton()
	local button = frame.SpawnButton
	if run then
		button:SetText("Stop")
		button:SetEnabled(true)
		return
	end
	button:SetText("Spawn")
	local indexes = chosenSets()
	button:SetEnabled(
		target ~= nil
			and #indexes > 0
			and Console.Busy() == nil
			and (selected or inForce(choiceOf("place")) == "player")
	)
end

local function updateHint()
	if not target then
		return frame.Hint:SetText("")
	end
	local indexes, count = chosenSets()
	if #indexes == 0 then
		return frame.Hint:SetText("Click sets to choose them")
	end
	frame.Hint:SetText(
		("%d %s chosen, %s"):format(#indexes, #indexes == 1 and "set" or "sets", objects(count))
	)
end

--- Mark a row chosen or not: a gold wash and an accent along its edge.
local function mark(button, set)
	button.Selected:SetShown(chosen[set.index] == true)
	button.Accent:SetShown(chosen[set.index] == true)
end

local function update()
	sets.ScrollBox:ForEachFrame(mark)
	updateRadios()
	updateButton()
	updateHint()
end

--- Spawn the chosen sets, or stop the run going on.
local function spawn()
	if run then
		return Console.Stop(false)
	end
	local indexes = chosenSets()
	if not target or #indexes == 0 then
		return
	end
	local group = inForce(choiceOf("group"))
	local request = { indexes = indexes, group = group ~= "pivot" and group or nil, quiet = true }
	if inForce(choiceOf("place")) == "player" then
		-- At the player the WMO is named, since the selection may have moved off it.
		request.here, request.file, request.label = true, target.file, target.name
	end
	Console.Spawn(request)
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

--- What is chosen when a WMO is first shown: its first set past the base, and the base too
-- where Epsilon emptied the WMO, since it draws none of its own.
local function chooseFirst(found)
	chosen = {}
	for _, set in ipairs(found.sets) do
		if set.index ~= 0 then
			chosen[set.index] = true
			break
		end
	end
	if found.blank and found.sets[1] and found.sets[1].index == 0 then
		chosen[0] = true
	end
end

--- Follow the selection: a WMO selected is shown with its sets, and one shown before stays
-- when the selection moves off it. Nothing changes while a run goes.
local function refresh()
	if run then
		return
	end
	local found, reason = Console.Target()
	selected = found ~= nil
	if found and not (target and target.file == found.file) then
		chooseFirst(found)
	end
	target = found or target
	provider:Flush()
	if target then
		wmo.Name:SetText(target.name)
		wmo.Detail:SetText(
			#target.sets
				.. (#target.sets == 1 and " set" or " sets")
				.. (target.blank and ", emptied by Epsilon" or "")
				.. (selected and "" or "; not selected, so at your feet")
		)
		provider:InsertTable(target.sets)
		frame.Empty:Hide()
	else
		wmo.Name:SetText("No WMO selected")
		wmo.Detail:SetText("")
		frame.Empty:SetText(
			reason:gsub("^%l", string.upper) .. ".\n\nSelect a WMO to see its sets."
		)
		frame.Empty:Show()
	end
	update()
end

local function started(total, what)
	run = { total = total, done = 0, started = Client.Now(), what = what }
	wmo.Detail:SetText("Spawning " .. what)
	frame.Hint:Hide()
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
		frame.Hint:Show()
		return refresh()
	end
	local doodads = #result.spawned - (result.pivot and 1 or 0)
	local line
	if result.deleted then
		line = ("Stopped, %s deleted"):format(objects(result.deleted))
	elseif result.aborted then
		line = ("Stopped: %s of %s"):format(thousands(doodads), thousands(result.total))
	else
		line = ("Done: %s in %s"):format(objects(doodads), clock(seconds))
	end
	local missed = #result.refused + #result.unjoined
	if missed > 0 then
		line = line .. (", %d not placed or grouped; see chat"):format(missed)
	end
	frame.Progress:SetValue(result.deleted and 0 or doodads)
	frame.Progress.Text:SetText(line)
	refresh()
end

local function rowClick(button)
	_G.PlaySound(_G.SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
	local index = button:GetElementData().index
	chosen[index] = not chosen[index] or nil
	update()
end

local function rowDoubleClick(button)
	chosen = { [button:GetElementData().index] = true }
	update()
	spawn()
end

local function rowEnter(button)
	local set = button:GetElementData()
	local tooltip = _G.GameTooltip
	tooltip:SetOwner(button, "ANCHOR_RIGHT")
	tooltip:SetText(set.name, 1, 1, 1)
	tooltip:AddLine(("Set %d of %s, %s"):format(set.index, target.name, objects(set.count)))
	if set.canonical ~= "" then
		tooltip:AddLine(("Named %s in the WMO's file"):format(set.canonical), 0.62, 0.62, 0.62)
	end
	tooltip:AddLine("Click to choose it; double-click to spawn it alone", 0.62, 0.62, 0.62)
	tooltip:Show()
end

local function initRow(button, set, new)
	if new then
		button:SetScript("OnClick", Client.Guarded(rowClick))
		button:SetScript("OnDoubleClick", Client.Guarded(rowDoubleClick))
		button:SetScript("OnEnter", Client.Guarded(rowEnter))
		button:SetScript("OnLeave", _G.GameTooltip_Hide)
	end
	button.Index:SetText(set.index)
	button.Label:SetText(set.name)
	button.Count:SetText(objects(set.count))
	mark(button, set)
end

local function radioClick(radio)
	_G.PlaySound(_G.SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
	taken[radio.choice.field] = radio.option.value
	update()
end

local function radioEnter(radio)
	local option = radio.option
	local tooltip = _G.GameTooltip
	tooltip:SetOwner(radio, "ANCHOR_RIGHT")
	tooltip:SetText(option.label, 1, 1, 1)
	tooltip:AddLine(option.hint, nil, nil, nil, true)
	if option.needsWmo and not selected then
		tooltip:AddLine("Select a WMO to choose it.", 1, 0.5, 0.25, true)
	end
	tooltip:AddLine("Typed: " .. typed(radio.choice, option), 0.62, 0.62, 0.62)
	tooltip:Show()
end

--- Lay out every choice: its label, then its options two to a row, the second column past the
-- widest first-column label of all of them.
local function buildChoices()
	local panel = frame.Options
	local rows = {}
	for _, choice in ipairs(CHOICES) do
		local label = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
		label:SetText(choice.label)
		rows[#rows + 1] = { label = label, radios = {} }
		for _, option in ipairs(choice.options) do
			local radio = _G.CreateFrame(
				"CheckButton",
				"FurnishFrameRadio" .. (#radios + 1),
				panel,
				"UIRadioButtonTemplate"
			)
			radio.choice, radio.option = choice, option
			radio.text:SetText(option.label)
			radio:SetScript("OnClick", Client.Guarded(radioClick))
			radio:SetScript("OnEnter", Client.Guarded(radioEnter))
			radio:SetScript("OnLeave", _G.GameTooltip_Hide)
			radios[#radios + 1] = radio
			table.insert(rows[#rows].radios, radio)
		end
	end
	updateRadios()
	local widest = 0
	for _, row in ipairs(rows) do
		for i = 1, #row.radios, 2 do
			widest = math.max(widest, row.radios[i].text:GetStringWidth())
		end
	end
	local second = RADIO_LEFT + radios[1]:GetWidth() + 5 + widest + RADIO_GAP
	local top = RADIO_TOP
	for _, row in ipairs(rows) do
		row.label:SetPoint("TOPLEFT", 14, top - 3)
		for i, radio in ipairs(row.radios) do
			radio:SetPoint(
				"TOPLEFT",
				i % 2 == 1 and RADIO_LEFT or second,
				top - math.floor((i - 1) / 2) * RADIO_ROW
			)
		end
		top = top - math.ceil(#row.radios / 2) * RADIO_ROW - 4
	end
end

local function build()
	frame.Header:Setup("Furnish")
	for _, panel in ipairs({ wmo, sets, frame.Options }) do
		panel:SetBackdrop(PANEL)
		panel:SetBackdropColor(0, 0, 0, 0.25)
		panel:SetBackdropBorderColor(0.75, 0.75, 0.75)
	end
	sets.Title:SetText("Doodad sets")
	frame.Options.Title:SetText("Spawning")
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
	table.insert(_G.UISpecialFrames, frame:GetName())

	local view = _G.CreateScrollBoxListLinearView()
	view:SetElementExtent(22)
	view:SetElementInitializer("Button", "FurnishSetRowTemplate", Client.Guarded(initRow))
	_G.ScrollUtil.InitScrollBoxListWithScrollBar(sets.ScrollBox, sets.ScrollBar, view)
	sets.ScrollBox:SetDataProvider(provider)

	local empty = sets.ScrollBox:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	empty:SetPoint("TOPLEFT", 16, -16)
	empty:SetPoint("BOTTOMRIGHT", -16, 16)
	empty:SetJustifyH("CENTER")
	empty:SetJustifyV("MIDDLE")
	frame.Empty = empty

	buildChoices()

	frame.SpawnButton:SetScript("OnClick", Client.Guarded(spawn))

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
			stopSelection = Client.OnSelection(refresh)
			refresh()
		end)
	)
	frame:SetScript(
		"OnHide",
		Client.Guarded(function()
			_G.PlaySound(_G.SOUNDKIT.IG_CHARACTER_INFO_CLOSE)
			if stopSelection then
				stopSelection()
				stopSelection = nil
			end
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
