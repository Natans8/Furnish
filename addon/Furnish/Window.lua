-- The window: the selected building's sets, how to group them, and a run's progress.
--
-- A surface over Console, as the commands are: it reads Target for what to show, Busy for
-- whether it may start and Watch for the run going on, and spawns and stops through the same
-- doors, so the window and the commands can never disagree. The layout is Window.xml; this
-- file gives it behaviour. While a run goes the window keeps what it showed, since every spawn
-- moves the selection.

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

--- The groupings a run may take, a radio button each, in the order the window lays them out:
-- the request's group value, what the button says, and what its tooltip says it does.
local GROUPS = {
	{
		value = "pivot",
		label = "Pivot",
		hint = "An invisible marker at the building leads the group.",
	},
	{ value = "first", label = "First object", hint = "The first object spawned leads the group." },
	{
		value = "attach",
		label = "The building's group",
		hint = "The objects join the building's own group.",
	},
	{ value = "nogroup", label = "No group", hint = "The objects stand loose." },
}

--- Where the radio buttons sit in their panel: two to a row from the first one's corner, the
-- second column a gap past the widest label of the first, measured in the player's own font.
local RADIO_LEFT, RADIO_TOP, RADIO_ROW, RADIO_GAP = 64, -30, 22, 16

local frame = _G.FurnishFrame
local building, sets = frame.BuildingPanel, frame.SetsPanel
local provider = _G.CreateDataProvider()

--- What the window shows and what is chosen in it.
local target, chosen, grouping, base = nil, nil, "pivot", false

--- The grouping's radio buttons, in GROUPS' order.
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

--- How a command spells a choice, read off the command's own words: "/furn <set> first", or
-- the bare spawn for the default, which takes no word.
local function typed(field, value)
	for _, each in ipairs(Furnish.Command.WORDS) do
		if each.field == field and each.value == value then
			return Chat.Typed("<set> " .. each.word)
		end
	end
	return Chat.Typed("<set>") .. ", with no word"
end

local function setAt(index)
	for _, set in ipairs(target and target.sets or {}) do
		if set.index == index then
			return set
		end
	end
	return nil
end

local function hasBase()
	return target ~= nil and target.sets[1] ~= nil and target.sets[1].index == 0
end

--- The base set may be laid under the chosen one: the building has one, it is not the one
-- chosen, and Epsilon did not empty the building, which lays it always.
local function baseUsable()
	return target ~= nil and not target.blank and hasBase() and chosen ~= 0 and not run
end

local function updateBase()
	local check = frame.Options.Base
	local usable = baseUsable()
	check:SetChecked((target ~= nil and target.blank) or (usable and base))
	check:SetEnabled(usable)
	check.text:SetFontObject(usable and _G.GameFontHighlightSmall or _G.GameFontDisableSmall)
end

local function updateGroup()
	for _, radio in ipairs(radios) do
		radio:SetChecked(radio.group.value == grouping)
		radio:SetEnabled(not run)
		radio.text:SetFontObject(run and _G.GameFontDisableSmall or _G.GameFontHighlightSmall)
	end
end

local function updateButton()
	local button = frame.SpawnButton
	if run then
		button:SetText("Stop")
		button:SetEnabled(true)
	else
		button:SetText("Spawn")
		button:SetEnabled(target ~= nil and chosen ~= nil and Console.Busy() == nil)
	end
end

--- Mark a row chosen or not: a gold wash and an accent along its edge.
local function mark(button, set)
	button.Selected:SetShown(set.index == chosen)
	button.Accent:SetShown(set.index == chosen)
end

local function paintRows()
	sets.ScrollBox:ForEachFrame(mark)
end

local function choose(index)
	chosen = index
	paintRows()
	updateBase()
	updateButton()
end

--- Start the chosen set, or stop the run going on.
local function spawn()
	if run then
		return Console.Stop(false)
	end
	if not (target and chosen) then
		return
	end
	Console.Spawn({
		index = chosen,
		group = grouping ~= "pivot" and grouping or nil,
		base = baseUsable() and base or nil,
		quiet = true,
	})
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

--- Show the selection's building and its sets, or why there are none. Nothing changes while
-- a run goes.
local function refresh()
	if run then
		return
	end
	local found, reason = Console.Target()
	target = found
	provider:Flush()
	if found then
		building.Name:SetText(found.name)
		building.Detail:SetText(
			#found.sets
				.. (#found.sets == 1 and " set" or " sets")
				.. (found.blank and ", emptied by Epsilon, so its base set comes along" or "")
		)
		provider:InsertTable(found.sets)
		if not setAt(chosen) then
			chosen = found.sets[1] and found.sets[1].index
			for _, set in ipairs(found.sets) do
				if set.index ~= 0 then
					chosen = set.index
					break
				end
			end
		end
		frame.Empty:Hide()
		frame.Hint:SetText("Double-click a set to spawn it")
	else
		chosen = nil
		building.Name:SetText("No building selected")
		building.Detail:SetText("")
		frame.Empty:SetText(
			reason:gsub("^%l", string.upper) .. ".\n\nSelect a building to see its sets."
		)
		frame.Empty:Show()
		frame.Hint:SetText("")
	end
	paintRows()
	updateBase()
	updateButton()
end

local function started(total, what)
	run = { total = total, done = 0, started = Client.Now(), what = what }
	building.Detail:SetText("Spawning " .. what)
	frame.Hint:Hide()
	frame.Progress:SetMinMaxValues(0, math.max(total, 1))
	frame.Progress:SetValue(0)
	frame.Progress:Show()
	progressText()
	updateGroup()
	updateBase()
	updateButton()
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
	updateGroup()
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
	choose(button:GetElementData().index)
end

local function rowDoubleClick(button)
	choose(button:GetElementData().index)
	spawn()
end

local function rowEnter(button)
	local set = button:GetElementData()
	local tooltip = _G.GameTooltip
	tooltip:SetOwner(button, "ANCHOR_RIGHT")
	tooltip:SetText(set.name, 1, 1, 1)
	tooltip:AddLine(("Set %d of %s, %s"):format(set.index, target.name, objects(set.count)))
	if set.canonical ~= "" then
		tooltip:AddLine(("Named %s in the building's file"):format(set.canonical), 0.62, 0.62, 0.62)
	end
	tooltip:AddLine("Double-click to spawn it", 0.62, 0.62, 0.62)
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

local function groupClick(radio)
	_G.PlaySound(_G.SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
	grouping = radio.group.value
	updateGroup()
end

local function groupEnter(radio)
	local group = radio.group
	local tooltip = _G.GameTooltip
	tooltip:SetOwner(radio, "ANCHOR_RIGHT")
	tooltip:SetText(group.label, 1, 1, 1)
	tooltip:AddLine(group.hint, nil, nil, nil, true)
	tooltip:AddLine("Typed: " .. typed("group", group.value), 0.62, 0.62, 0.62)
	tooltip:Show()
end

local function baseEnter(check)
	local tooltip = _G.GameTooltip
	tooltip:SetOwner(check, "ANCHOR_RIGHT")
	if target and target.blank then
		tooltip:SetText(
			"Epsilon emptied this building, so its base set always comes along.",
			1,
			1,
			1,
			1,
			true
		)
	elseif target and not hasBase() then
		tooltip:SetText("This building has no base set.", 1, 1, 1, 1, true)
	elseif chosen == 0 then
		tooltip:SetText("The base set is the one chosen.", 1, 1, 1, 1, true)
	else
		tooltip:SetText("Spawn the building's base set under the chosen one.", 1, 1, 1, 1, true)
	end
	tooltip:AddLine("Typed: " .. typed("base", true), 0.62, 0.62, 0.62)
	tooltip:Show()
end

local function build()
	frame.Header:Setup("Furnish")
	for _, panel in ipairs({ building, sets, frame.Options }) do
		panel:SetBackdrop(PANEL)
		panel:SetBackdropColor(0, 0, 0, 0.25)
		panel:SetBackdropBorderColor(0.75, 0.75, 0.75)
	end
	sets.Title:SetText("Doodad sets")
	frame.Options.Title:SetText("Spawning")
	frame.Options.GroupLabel:SetText("Group")
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

	for i, group in ipairs(GROUPS) do
		local radio = _G.CreateFrame(
			"CheckButton",
			"FurnishFrameGroup" .. i,
			frame.Options,
			"UIRadioButtonTemplate"
		)
		radio.group = group
		radio.text:SetText(group.label)
		radio:SetScript("OnClick", Client.Guarded(groupClick))
		radio:SetScript("OnEnter", Client.Guarded(groupEnter))
		radio:SetScript("OnLeave", _G.GameTooltip_Hide)
		radios[i] = radio
	end
	updateGroup()
	local widest = 0
	for i = 1, #radios, 2 do
		widest = math.max(widest, radios[i].text:GetStringWidth())
	end
	local second = RADIO_LEFT + radios[1]:GetWidth() + 5 + widest + RADIO_GAP
	for i, radio in ipairs(radios) do
		radio:SetPoint(
			"TOPLEFT",
			i % 2 == 1 and RADIO_LEFT or second,
			RADIO_TOP - math.floor((i - 1) / 2) * RADIO_ROW
		)
	end

	local check = frame.Options.Base
	check.text:SetText("Lay the base set under it")
	check:SetScript(
		"OnClick",
		Client.Guarded(function(self)
			_G.PlaySound(_G.SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
			base = self:GetChecked() and true or false
		end)
	)
	check:SetScript("OnEnter", Client.Guarded(baseEnter))
	check:SetScript("OnLeave", _G.GameTooltip_Hide)

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
