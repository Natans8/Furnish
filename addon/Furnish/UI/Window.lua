-- The window: where a WMO's sets come from, which of them to spawn, and where they go, read top
-- to bottom, with a run's progress at the foot.
--
-- A surface over Console, as the commands are: it reads Source for the sets, Selected for the
-- selected object's pose, Find for a name searched, Busy for whether it may start and Watch for
-- the run going on, and spawns, imports and stops through the same doors, so the window and
-- the commands can never disagree. The layout is Window.xml; this file gives it behaviour and
-- every word.
--
-- Source and Destination each follow the gob selection until their box is unticked. The source is
-- the WMO a gob entry is, shown in its ID box as the destination's numbers are: the selected gob's,
-- one typed, the lowest of a WMO searched, or the doodad's. The destination is numbers and nothing
-- else: following the selected gob is one way to fill them, Here, Use selected and typing the
-- others, and while no gob is followed they hold where the player stood, so every number always
-- holds a value. The selection matters to the destination only as a source of numbers; what it
-- decides is the group, which the Selected gob leader joins. The doodad `.doodad select`
-- picks is another selection, held at the same time and shown in a panel of its own beside the
-- window: picking it never changes the source or the destination, and selecting a gob never clears
-- it. Use as source keeps its WMO as the source with the sets it drew chosen; Import doodad is
-- the import a command makes, turning it into a gob and spawning those sets merged into it, the
-- run on the window's bar. Importing hides the doodad, which stays selected, so the panel keeps
-- it. While a run goes nothing changes, since every spawn moves the selection.

local _, Furnish = ...
local Window = {}
Furnish.Window = Window

local Console = Furnish.Console
local Client = Furnish.Client
local Pose = Furnish.Pose
local Rows = Furnish.Rows
local Reader = Furnish.Reader
local Sets = Furnish.Sets
local Chat = Furnish.Chat
local Names = Furnish.Names
local Commands = Furnish.Commands
local Previews = Furnish.Previews
local Scene = Furnish.Scene

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

--- The leader's bar: the list's edge, drawn finer for a control one row high.
local SEGMENTS = {
	bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
	edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
	tile = true,
	tileEdge = true,
	tileSize = 16,
	edgeSize = 12,
	insets = { left = 3, right = 3, top = 3, bottom = 3 },
}

--- What each grouping's segment says, by its word, the segments standing in the order
-- Console.GROUPS declares them. A merge's says what is selected, a gob or a group, so it is
-- read when drawn.
local LABELS = { nogroup = "No group", pivot = "Pivot", first = "First spawned" }

--- The room either side of a segment's words, and what the alert mark takes beside them.
local SEGMENT_PAD, ALERT_ROOM = 6, 17

--- The tooltip's colours, Chat's: a label, a heading, what a click does, a warning and a refusal.
local GREY, GOLD, GREEN = Chat.TIP.label, Chat.TIP.title, Chat.TIP.click
local WARN, RED = Chat.TIP.warning, Chat.TIP.refusal

--- How bright what a run holds still is drawn: text, numbers and the accent alike.
local DIM = 0.5

--- How a list's box is shaded and edged, the leader's bar alike.
local SHADE, EDGE = { 0, 0, 0, 0.25 }, { 0.75, 0.75, 0.75 }

--- The sound a choice makes, as Blizzard's own check boxes make it.
local CHOOSE = _G.SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON

--- The pop-up that asks before a set joins a group the selected gob is in already.
local JOIN = "FURNISH_JOIN_GROUP"

--- How the console's lines name a way out to a player at the window: its Stop is the one a line
-- the window starts can need, since the window offers nothing a command alone can do.
local WAYS = {
	stop = function()
		return "the window's Stop"
	end,
}

local ROW = 22

--- How far a list's rows stand in from its box, as FurnishListTemplate sets them, and the room
-- its scroll bar takes on the right while it shows.
local LIST_INSET, BAR_ROOM = 8, 22

--- The room an empty list's line saying why takes, its margins in FurnishListTemplate.
local EMPTY_ROOM = 40

--- The smallest the window may be drawn, which is the size its layout was made for; it may grow
-- to twice that.
local MIN_WIDTH, MIN_HEIGHT = 400, 668

--- How many letters a name search waits for, as Blizzard's own searches do; how many WMOs it
-- lists at most, and how many rows of them show before the list scrolls.
local SEARCH_FROM, RESULTS, RESULT_ROWS = 3, 60, 8

--- How many objects a run places before the bar guesses the time left from its pace.
local PACED = 5

--- The position's numbers, two rows across the window's width: the axes, then the turn about
-- each and the scale. Each is its box, its row, where the pose keeps it, and ObjectMover's colour
-- for its axis, the same for a position and the turn about it.
local RED_AXIS, BLUE_AXIS, GREEN_AXIS =
	{ 1, 0.376, 0.376 }, { 0.22, 0.43, 0.97 }, { 0.13, 0.99, 0.55 }
local NUMBERS = {
	{ box = "X", row = 1, part = "position", key = "x", colour = RED_AXIS, unit = "In yards." },
	{ box = "Y", row = 1, part = "position", key = "y", colour = BLUE_AXIS, unit = "In yards." },
	{ box = "Z", row = 1, part = "position", key = "z", colour = GREEN_AXIS, unit = "In yards." },
	{
		box = "Roll",
		row = 2,
		part = "rotation",
		key = "roll",
		colour = RED_AXIS,
		unit = "In degrees.",
	},
	{
		box = "Pitch",
		row = 2,
		part = "rotation",
		key = "pitch",
		colour = BLUE_AXIS,
		unit = "In degrees.",
	},
	{
		box = "Turn",
		row = 2,
		part = "rotation",
		key = "turn",
		colour = GREEN_AXIS,
		unit = "In degrees, from north.",
	},
	{ box = "Scale", row = 2, key = "scale", colour = GREY, unit = "1 is the model's own size." },
}

--- Where each row of boxes stands, measured up from the window's foot to its top, and how far
-- apart the boxes are. A box's border art reaches five units left of the box itself.
local NUMBER_ROWS, NUMBER_GAP, NUMBER_ART = { 170, 144 }, 8, 5

--- A button's caps either side of its words.
local CAPS = 24

--- How far the source's words stand from its picture.
local PICTURE_GAP = 8

--- How many of a doodad's sets its panel shows before its list scrolls.
local DOODAD_ROWS = 10

local frame = _G.FurnishFrame
local list = frame.Sets
local panel = frame.Doodad
local offer = frame.Blueprint
local preview = frame.Preview
local provider, found, drawn =
	_G.CreateDataProvider(), _G.CreateDataProvider(), _G.CreateDataProvider()

--- Every control the player may change, which a run holds still.
local CONTROLS = {
	frame.Search,
	frame.SourceFollow,
	frame.SourceID,
	frame.DestinationFollow,
	frame.Here,
	frame.UseSelected,
}
for _, number in ipairs(NUMBERS) do
	CONTROLS[#CONTROLS + 1] = frame[number.box]
end

--- Where the sets come from: the Source request pinned, or nil to follow the gob selection; the
-- doodad `.doodad select` picked, in its own slot, imported or not, with the sets of the WMO it
-- is; the source shown, or nil, and the gob entry its ID box holds; and the sets chosen, by index.
local pinned, doodad, shown, shownEntry
local chosen = {}

--- Whether the next source shown has its sets chosen afresh, even where it is the WMO shown
-- already: a doodad used as the source brings its own; and what the list shows, as listKey says
-- it, so the list is rebuilt only when that changes.
local rechoose, listed = false, nil

--- Where the sets go: the position, rotation and scale shown, and nothing of what they were read
-- from; whether they stay when the selection moves; and whether they were last read off the
-- selection, so that losing it reads where the player stands once.
local spot, spotPinned, spotFollowed = nil, false, false

--- What the player chose to lead the objects' group, as a request's group says it.
local lead = Console.GROUPED

--- The run going on, as Console holds it: { total, done, started, deleting }, read as it is
-- told; and the last run's result the bar has said.
local run, told

--- The scene the Preview pane draws in, made as the window is built; and what it last drew, as
-- its source and chosen sets, so it is drawn again only when they change.
local stage, previewed

--- The search match Enter takes, by its place in the list.
local picked = 1

local stops = {}

local thousands = Chat.Thousands
local objects = Chat.Objects

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

--- Where a pose keeps the value a number box shows: its position or rotation, or the pose
-- itself for the scale.
local function holder(pose, number)
	return number.part and pose[number.part] or pose
end

--- Whether a run grouped as a word says spawns a pivot to lead its group.
local function pivots(word)
	return Console.Grouping(word).group == Furnish.Group.Pivot
end

--- Draw a box's backdrop, shaded and edged as every one in the window is.
local function dress(box, backdrop, shade)
	box:SetBackdrop(backdrop)
	box:SetBackdropColor(unpack(shade or SHADE))
	box:SetBackdropBorderColor(unpack(EDGE))
end

--- Light a number box while the pointer rests on it, unless a run holds it still.
local function lightOnHover(box)
	box:HookScript("OnEnter", function(self)
		self.Hover:SetShown(self:IsEnabled())
	end)
	box:HookScript("OnLeave", function(self)
		self.Hover:Hide()
	end)
end

--- Set a box's words in after its axis word, as every number box has them.
local function insetAfterAxis(box)
	box:SetTextInsets(box.Axis:GetStringWidth() + 6, 4, 0, 0)
end

--- Draw text in white, or dimmed while a run holds it still.
local function brighten(text)
	local shade = run and DIM or 1
	text:SetTextColor(shade, shade, shade)
end

--- What is selected: the selected gob, or else a selected group, whose pose says group; nil when
-- neither is. Use selected takes its numbers once, the destination never following a group by
-- itself, and the Selected gob leader merges into its group.
local function selection()
	return Console.Selected() or Console.Group()
end

--- What is selected as a word: "group" for a group, else "gob".
local function kindOf(selected)
	return selected and selected.group and "group" or "gob"
end

--- Take down what resting on a found WMO showed: its tooltip, and the preview beside it.
local function leaveResult()
	_G.GameTooltip:Hide()
	Previews.Unpeek()
end

--- Show a tooltip beside a control, its lines as Chat.Tip takes them.
local function tip(owner, title, lines)
	_G.GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
	Chat.Tip(_G.GameTooltip, title, lines)
	_G.GameTooltip:Show()
end

--- Size a button to its words and its caps.
local function fit(button)
	button:SetWidth(math.ceil(button:GetFontString():GetStringWidth()) + CAPS)
end

--- Give a control a tooltip, its lines read when shown: a function's answer, or a fixed list.
-- The title is read then too, nil being the control's own words, which a check box keeps in its
-- label; and so is how a command types the same thing, since the command's name is only known
-- once every file has loaded.
local function hint(owner, title, lines, words)
	owner:SetScript(
		"OnEnter",
		Client.Guarded(function()
			local shownTitle = type(title) == "function" and title()
				or title
				or (owner.Label or owner):GetText()
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

--- Why the selected gob or group cannot take the objects into its group, or nil when it can.
local function cannotLead()
	local selected = selection()
	if not selected then
		return "No gob or group is selected."
	elseif not Client.CanEdit(selected) then
		return ("You can't edit the selected %s in this phase."):format(kindOf(selected))
	end
	return nil
end

--- The request's group: the leader chosen, the selected gob standing down to the pivot while it
-- cannot lead, and coming back as chosen once it can.
local function grouped()
	if lead == "merge" and cannotLead() then
		return Console.GROUPED
	end
	return lead
end

--- The selected gob, where the objects would join a group it is in already, which Spawn asks
-- about first; a selected group is chosen as one, so it is not asked about.
local function joinsGroup()
	local selected = grouped() == "merge" and Console.Selected()
	return selected and (selected.groupLeader or 0) ~= 0 and selected or nil
end

--- Whether the selected gob draws a set already, as part of its model: its base set, unless
-- the WMO comes unfurnished. A source kept, by a search, an ID typed, Use as source or Follow
-- selection unticked, stands nowhere and draws nothing.
local function baked(set)
	return not pinned and shown ~= nil and Sets.DrawnByRoot(shown.file, set)
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

--- What to know before the next spawn, the weightiest first, each { text, colour }.
local function warnings()
	local said = {}
	if run or not shown then
		return said
	end
	-- Only a destination following the selected WMO stands on it; numbers taken once stand
	-- wherever they were taken.
	local onto = not spotPinned and Console.Selected()
	if onto and onto.wmo and onto.file ~= shown.file and not Sets.Same(onto.file, shown.file) then
		local text = ("%s's sets may not fit %s."):format(shown.name, onto.name)
		said[#said + 1] = { text = text, colour = WARN }
	end
	-- A reminder, not a warning: whether highlighting is on is the player's call.
	if #(chosenSets()) > 0 then
		said[#said + 1] = { text = Chat.HIGHLIGHT .. ".", colour = GREY }
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

--- The selected gob's segment's words: what is selected, a group or a gob.
local function selectedLabel()
	return "Selected " .. kindOf(selection())
end

--- The leader's segments, in Console.GROUPS's order, made once by buildLeader; and the words and mark they
-- were last laid out for, since laying them out measures text.
local segments = {}
local laidOut

--- Lay the segments across the bar: each as wide as its words, with the alert mark's room where it
-- shows, and what the bar has left shared out evenly, so a long name never crowds.
local function layoutLeader()
	local bar = frame.Leader
	local inset = SEGMENTS.insets.left
	local natural, total = {}, 0
	for i, segment in ipairs(segments) do
		natural[i] = segment.Label:GetStringWidth()
			+ 2 * SEGMENT_PAD
			+ (segment.Alert:IsShown() and ALERT_ROOM or 0)
		total = total + natural[i]
	end
	local spare, left = (bar:GetWidth() - 2 * inset - total) / #segments, inset
	for i, segment in ipairs(segments) do
		local width = natural[i] + spare
		segment:ClearAllPoints()
		segment:SetPoint("TOPLEFT", bar, "TOPLEFT", left, -inset)
		segment:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", left, inset)
		segment:SetWidth(width)
		segment.Divider:SetShown(i > 1)
		segment.Label:ClearAllPoints()
		segment.Label:SetPoint("CENTER", segment.Alert:IsShown() and ALERT_ROOM / 2 or 0, 0)
		left = left + width
	end
end

--- The leader's segments: the one in force lit as a chosen set row is, the selected gob's named
-- for what is selected and greyed while it cannot lead, its mark shown while the objects would
-- join a group that stands already. A run holds them still.
local function updateLeader()
	local current = grouped()
	local marked = false
	frame.LeaderLabel:SetFontObject(run and _G.GameFontDisableSmall or _G.GameFontNormalSmall)
	local accent = run and { DIM, DIM, DIM } or GOLD
	for _, segment in ipairs(segments) do
		local choice = segment.choice
		local enabled = not run and (choice.word ~= "merge" or not cannotLead())
		segment.Label:SetText(LABELS[choice.word] or selectedLabel())
		segment.Label:SetFontObject(
			enabled and _G.GameFontHighlightSmall or _G.GameFontDisableSmall
		)
		segment:SetEnabled(enabled)
		local inForce = choice.word == current
		segment.Chosen:SetShown(inForce)
		segment.Accent:SetShown(inForce)
		segment.Accent:SetColorTexture(accent[1], accent[2], accent[3], 0.9)
		segment.Alert:SetShown(inForce and joinsGroup() ~= nil)
		marked = marked or segment.Alert:IsShown()
	end
	local shape = selectedLabel() .. tostring(marked)
	if shape ~= laidOut then
		laidOut = shape
		layoutLeader()
	end
end

local function updateDestination()
	frame.DestinationFollow:SetChecked(not spotPinned)
	for _, number in ipairs(NUMBERS) do
		local box = frame[number.box]
		if not box:HasFocus() then
			box:SetText(spot and shownNumber(holder(spot, number)[number.key]) or "")
		end
		local colour = run and GREY or number.colour
		box.Axis:SetTextColor(colour[1], colour[2], colour[3])
		brighten(box)
	end
	-- The button names what it reads, a gob or a group, and is as wide as its words.
	local from = selection()
	local label = "Use selected " .. kindOf(from)
	if frame.UseSelected:GetText() ~= label then
		frame.UseSelected:SetText(label)
		fit(frame.UseSelected)
	end
	frame.UseSelected:SetEnabled(not run and from ~= nil)
	updateLeader()
end

--- The doodad panel, there while a doodad is selected; a doodad imported once is not again. A
-- doodad picked while the window was shut has not been read yet, since reading it loads the data,
-- and is read when the window opens.
local function updateDoodad()
	panel:SetShown(doodad ~= nil and doodad.sets ~= nil)
	if not (doodad and doodad.sets) then
		return
	end
	local count = #doodad.sets > 0 and Chat.Count(#doodad.sets, "set") or "No sets"
	local state = doodad.status or doodad.imported and "imported"
	panel.Detail:SetText(count .. (state and ", " .. state or ""))
	panel.UseSource:SetEnabled(not run and #doodad.sets > 0)
	-- Held while an import waits for its gob, so a second click sends nothing twice, and for one
	-- the server has off the map, whose import it refuses.
	local importable = not (doodad.imported or doodad.removed)
	panel.Import:SetEnabled(not run and importable and not Console.Busy())
end

--- Draw the chosen sets in the Preview pane, while it shows and only when what is chosen changed.
local function updatePreview()
	if not preview:IsShown() then
		return
	end
	local indexes = chosenSets()
	local key = shown and (shown.file .. ":" .. table.concat(indexes, ",")) or ""
	if key == previewed then
		return
	end
	previewed = key
	local pieces, names = {}, {}
	for _, set in ipairs(shown and shown.sets or {}) do
		if chosen[set.index] then
			names[#names + 1] = set.name
			for _, piece in ipairs(Rows.Pieces(set.id) or {}) do
				pieces[#pieces + 1] = piece
			end
		end
	end
	stage:Draw(pieces)
	preview.Name:SetText(shown and shown.name or "No sets")
	local detail = "Choose a set to see it laid out."
	if #names > 0 then
		detail = ("%s, %s"):format(table.concat(names, ", "), objects(#pieces))
	end
	preview.Detail:SetText(detail)
end

local function update()
	for _, control in ipairs(CONTROLS) do
		control:SetEnabled(not run)
	end
	updateDoodad()
	-- The ID box holds the source's entry, unless it is being typed in.
	local id = frame.SourceID
	if not id:HasFocus() then
		id:SetText(shownEntry and tostring(shownEntry) or "")
	end
	brighten(id)
	list.ScrollBox:ForEachFrame(mark)
	updateMore()
	updateDestination()
	updateStatus()
	local text, enabled = action()
	frame.SpawnButton:SetText(text)
	frame.SpawnButton:SetEnabled(enabled)
	-- A run's objects can be taken back only while it goes; once it ends, its group is the
	-- player's, and nothing here knows what has been done to it since. Shown, it stands where
	-- the spawn button ends, which shortens to meet it.
	frame.SpawnSource:SetEnabled(
		not run and shownEntry ~= nil and Client.CanSpawn(true) and not Console.Busy()
	)
	updatePreview()
	local delete = frame.DeleteButton
	delete:SetShown(run ~= nil)
	if run then
		frame.SpawnButton:SetPoint("TOPRIGHT", delete, "TOPLEFT", -4, 0)
	else
		frame.SpawnButton:SetPoint("TOPRIGHT", delete, "TOPRIGHT")
	end
end

--- The spawn the window describes, as Console takes it.
local function request()
	return {
		indexes = (chosenSets()),
		file = shown.file,
		label = shown.name,
		at = Pose.Copy(spot),
		group = grouped(),
		quiet = true,
		ways = WAYS,
	}
end

_G.StaticPopupDialogs[JOIN] = {
	text = "%s is in a group already, so the %s join it.",
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

--- Spawn the chosen sets, asking first where they would join a group the selected gob is in
-- already, the merge reading the selection when the answer comes; or stop the run.
local function spawn()
	if run then
		return Console.Stop(false, WAYS)
	end
	local text, enabled = action()
	if not enabled then
		return Chat.Say(text)
	end
	local member = joinsGroup()
	if member then
		local _, count = chosenSets()
		local dialog = _G.StaticPopup_Show(JOIN, member.name, objects(count))
		if dialog then
			dialog.data = request()
		end
		return
	end
	Console.Spawn(request())
end

--- What is chosen when a WMO is first shown: the sets a doodad drew beyond the base set, which the
-- WMO draws itself unless it comes unfurnished; where no doodad adds one, its first set beyond the
-- base, and the base too where it comes unfurnished.
local function chooseFirst(file, sets)
	chosen = {}
	for _, set in ipairs(sets) do
		if set.placed and not Sets.DrawnByRoot(file, set) then
			chosen[set.index] = true
		end
	end
	if next(chosen) then
		return
	end
	for _, set in ipairs(sets) do
		if not Sets.IsBase(set) then
			chosen[set.index] = true
			break
		end
	end
	local base = sets[1]
	if base and Sets.IsBase(base) and not Sets.DrawnByRoot(file, base) then
		chosen[base.index] = true
	end
end

--- The source's detail line: what it is and how many sets it has.
local function sourceDetail()
	return Chat.Count(#shown.sets, "set") .. (shown.blank and ", unfurnished" or "")
end

--- What the set list shows for a source, as a string to compare: its WMO, whether it is kept,
-- which sets the doodad marks; nil for none. Its rows are rebuilt only when this changes.
local function listKey(source)
	if not source then
		return nil
	end
	local placed = {}
	for _, set in ipairs(source.sets) do
		if set.placed then
			placed[#placed + 1] = set.index
		end
	end
	return table.concat({ source.file, tostring(pinned ~= nil), table.concat(placed, ",") }, ":")
end

--- The gob entry the source's ID box holds: the one kept, the lowest of a WMO searched, or the
-- selected gob's; nil where there is none.
local function sourceEntry()
	if pinned then
		return pinned.entry
			or (pinned.file and Reader.Load() and Reader.EntryOfFile(pinned.file))
			or nil
	end
	local selected = Console.Selected()
	return selected and selected.entry
end

--- Read the window afresh: the source and the destination follow the selection unless unticked.
local function refresh()
	if run then
		return
	end
	local before = shown
	-- What is pinned, the doodad's WMO among them, or nil for the selected gob.
	shown = not (pinned and pinned.empty) and Console.Source(pinned) or nil
	if shown then
		for _, set in ipairs(shown.sets) do
			shown.placed = shown.placed or set.placed
		end
	end
	if shown and (rechoose or not (before and before.file == shown.file)) then
		rechoose = false
		chooseFirst(shown.file, shown.sets)
	end
	if not spotPinned then
		local selected = Console.Selected()
		if selected then
			spot, spotFollowed = Pose.Copy(selected), true
		elseif not spot or spotFollowed then
			-- With nothing selected the destination takes where the player stands, read once so no number
			-- is empty, and never again while it stays so: it does not follow the player, and Here
			-- reads it afresh.
			local here = Pose.Here()
			spot, spotFollowed = here and Pose.Copy(here), false
		end
	end
	frame.SourceFollow:SetChecked(not pinned)
	shownEntry = sourceEntry()
	-- Filling the list again redraws every row, so it is done only when what it shows changed.
	local key = listKey(shown)
	if key ~= listed then
		listed = key
		provider:Flush()
		if shown then
			provider:InsertTable(shown.sets)
		end
	end
	-- What the source says: its name, greyed where there is none, its detail, and what the
	-- empty list suggests, or why there can be no sets at all.
	local name, detail, dim, empty
	local loaded, missing = Reader.Load()
	if shown then
		name, detail = shown.name, sourceDetail()
	elseif not loaded then
		name, detail, dim, empty = "No data", "", true, missing
	elseif pinned and pinned.empty then
		name, detail, dim = "Nothing kept", "", true
		empty = "Search a WMO, or tick Follow selection."
	elseif pinned then
		name, detail = pinned.name or ("Entry %d"):format(pinned.entry), "No sets"
		empty = "Search another WMO."
	else
		local selected = Console.Selected()
		-- A group is no source, whatever leads it, as a model is not.
		local group = not selected and Console.Group()
		empty = "Select one WMO, or search one."
		if selected then
			name, detail = selected.name, selected.wmo and "No sets" or "Not a WMO"
		else
			name, dim = group and "A group" or "No WMO selected", true
			detail = group and "Led by " .. group.name or ""
		end
	end
	local shade = dim and DIM or 1
	frame.SourceName:SetText(name)
	frame.SourceName:SetTextColor(shade, shade, shade)
	frame.SourceDetail:SetText(detail)
	-- The source's WMO as Glimpse pictures it, its box left empty where there is none.
	frame.PictureBox.Picture:SetTexture(shown and Previews.Picture(shownEntry, shown.name) or nil)
	list.Empty:SetText(empty or "")
	list.Empty:SetShown(not shown)
	update()
end

--- The bar's words during a run: how far it is, and once its pace is known, how long is left;
-- once a stopped run deletes what it spawned, how far the deleting is.
local function progressText()
	local cleanup = run.deleting
	if cleanup then
		return frame.Progress.Text:SetText(
			("Deleting %s of %s"):format(thousands(cleanup.done), thousands(cleanup.total))
		)
	end
	local line = ("%s of %s"):format(thousands(run.done), thousands(run.total))
	local elapsed = Client.Now() - run.started
	if run.done >= PACED and run.done < run.total then
		local left = elapsed / run.done * (run.total - run.done)
		line = line .. (", about %s left"):format(clock(left))
	end
	frame.Progress.Text:SetText(line)
end

--- The clock on the bar moves between replies too, a few times a second while a run goes.
local since = 0
local function tick(_, elapsed)
	since = since + elapsed
	if since >= 0.25 then
		since = 0
		progressText()
	end
end

--- The blueprint the last run offers, shown while Console says it stands. A new offer starts
-- from its suggested name; the one already up keeps whatever has been typed into it.
local function showOffer()
	local name = Console.Offer()
	if not name then
		offer:Hide()
		offer.made = nil
		return
	end
	if offer.made ~= name then
		offer.made = name
		offer.Name:SetText(name)
		offer.Name:SetCursorPosition(0)
	end
	offer:Show()
end

--- Put the blueprint command in the chat box, the name as the box holds it. Sending it is the
-- player's, and so is whatever the server answers.
local function pasteOffer()
	local name = offer.Name:GetText()
	if name == "" then
		return
	end
	offer.Name:ClearFocus()
	Chat.Paste(Console.OfferCommand(name))
end

--- Draw the run Console holds on the bar: how far it has got, or, once a stopped run deletes
-- what it spawned, how far the deleting is, the bar emptying as the objects go.
local function drawRun()
	local cleanup = run.deleting
	local total, value
	if cleanup then
		total, value = cleanup.total, cleanup.total - cleanup.done
	else
		total, value = run.total, run.done
	end
	frame.Progress:SetMinMaxValues(0, math.max(total, 1))
	frame.Progress:SetValue(value)
	progressText()
end

--- A run begun, or one going on that the window catches up with.
local function started()
	run = Console.Run()
	frame.Results:Hide()
	frame.Progress.ended = false
	frame.Progress:SetScript("OnUpdate", tick)
	drawRun()
	-- The next run takes the last one's offer with it.
	showOffer()
	update()
end

--- A run's progress, or its cleanup's, which Console has counted already.
local function progressed()
	if run then
		drawRun()
	end
end

--- Say how a run ended on the bar, which stays until the next one starts.
local function finished(result, seconds)
	run = nil
	frame.Progress:SetScript("OnUpdate", nil)
	if not result then
		frame.Progress.ended = false
		return refresh()
	end
	told = result
	local placed = result.placed
	local pivot = result.pivot and " and a pivot" or ""
	local ending = Console.Ending(result)
	local line
	if ending == "deleted" then
		line = ("Stopped, %s deleted"):format(objects(result.deleted))
	elseif ending == "part deleted" then
		line = ("Stopped, %s of %s deleted"):format(
			thousands(result.deleted),
			objects(#result.spawned)
		)
	elseif ending == "done" then
		line = ("Done: %s%s in %s"):format(objects(placed), pivot, clock(seconds))
	else
		line = ("Stopped: %s of %s%s"):format(thousands(placed), objects(result.total), pivot)
	end
	local missed = #result.refused + #result.unjoined
	if missed > 0 then
		line = line .. (", %d not placed or grouped; see chat"):format(missed)
	end
	frame.Progress:SetValue(result.deleted and 0 or placed)
	frame.Progress.Text:SetText(line)
	frame.Progress.ended = true
	refresh()
	-- Most often up only once the run's group is selected, a selection event later.
	showOffer()
end

--- A click chooses the one set, and a ctrl- or shift-click adds or removes it; either opens the
-- Preview pane on what is chosen then.
local function rowClick(button)
	if run then
		return
	end
	_G.PlaySound(CHOOSE)
	local index = button:GetElementData().index
	if _G.IsControlKeyDown() or _G.IsShiftKeyDown() then
		chosen[index] = not chosen[index] or nil
	else
		chosen = { [index] = true }
	end
	-- A scene applies nothing while hidden, so a pane opened now is drawn afresh.
	if not preview:IsShown() then
		preview:Show()
		previewed = nil
	end
	update()
end

--- The lines every set's tooltip opens with: its index, its objects and its name in the file.
local function setLines(set)
	local lines = {
		{ label = "Set", value = set.index },
		{ label = "Objects", value = thousands(set.count) },
	}
	if set.canonical ~= "" then
		lines[#lines + 1] = { label = "In the file", value = set.canonical }
	end
	return lines
end

--- Fill a set's row: its index, its name, its objects, and the word beside the name, if any.
local function fillSetRow(button, set, tag)
	button.Index:SetText(set.index)
	button.Label:SetText(set.name)
	button.Count:SetText(thousands(set.count))
	button.Tag:SetText(tag or "")
end

--- A set's tooltip, read off the row as it stands, since rows are reused as the list scrolls:
-- what it is, and whether the source draws it already.
local function rowEnter(button)
	local set = button:GetElementData()
	local lines = setLines(set)
	if baked(set) then
		lines[#lines + 1] = { text = "The WMO draws it already.", colour = GREEN }
	elseif set.placed then
		lines[#lines + 1] = { text = "The doodad drew it.", colour = GREEN }
	end
	lines[#lines + 1] = { text = "Click: choose only this set", colour = GREEN }
	lines[#lines + 1] = { text = "Ctrl- or shift-click: add or remove this set", colour = GREEN }
	tip(button, set.name, lines)
end

local function initRow(button, set, new)
	if new then
		button:SetScript("OnClick", Client.Guarded(rowClick))
		button:SetScript("OnEnter", Client.Guarded(rowEnter))
		button:SetScript("OnLeave", _G.GameTooltip_Hide)
	end
	fillSetRow(button, set, baked(set) and "baked")
	mark(button, set)
end

--- Show the sets of a WMO a search found, and keep them whatever is selected.
local function pick(wmo)
	_G.PlaySound(CHOOSE)
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
		lines[#lines + 1] = { text = "Unfurnished: it draws none of its sets.", colour = GREY }
	end
	lines[#lines + 1] = { text = "Click: show its sets", colour = GREEN }
	tip(button, wmo.name, lines)
	Previews.Peek(Console.WmoPreview(wmo.name))
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
		button:SetScript("OnLeave", Client.Guarded(leaveResult))
	end
	button.Label:SetText(wmo.name)
	button.Count:SetText(Chat.Count(wmo.sets, "set"))
	button.Tag:SetText(wmo.blank and "unfurnished" or "")
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
	-- Inserted at once, since every insert redraws the whole list.
	local wmos, shownFound = Console.Find(text), {}
	for i = 1, math.min(RESULTS, #wmos) do
		shownFound[i] = wmos[i]
	end
	found:InsertTable(shownFound)
	frame.Results.Empty:SetText(("No WMO with sets is named like %s."):format(text))
	frame.Results.Empty:SetShown(#wmos == 0)
	local rows = math.min(#wmos, RESULT_ROWS) * ROW + 2 * LIST_INSET
	frame.Results:SetHeight(rows + (#wmos == 0 and EMPTY_ROOM or 0))
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

--- Follow the selection with the destination, or keep the position shown whatever is selected.
local function followDestination(box)
	spotPinned = not box:GetChecked()
	refresh()
end

--- Fill the destination once from a pose, and keep it there until Follow selection is ticked.
local function fillDestination(pose)
	if pose then
		spot, spotPinned, spotFollowed = pose, true, false
	end
	update()
end

--- What the Import doodad tooltip says: what importing does, and whether it has been.
local function importLines()
	local lines = {
		{ text = "Turn the doodad into a gob and spawn the sets it drew on it." },
	}
	if doodad and doodad.removed then
		lines[#lines + 1] = {
			text = ("Listed as %s, so it can't be imported."):format(doodad.status or "removed"),
			colour = GREY,
		}
	elseif doodad and doodad.imported then
		lines[#lines + 1] = {
			text = "Imported already.",
			colour = GREY,
		}
	end
	return lines
end

--- A doodad's set's tooltip: what it is, and whether the doodad draws it.
local function drawnEnter(button)
	local set = button:GetElementData()
	local lines = setLines(set)
	if set.draws then
		local text = set.placed and "The doodad draws it on the map." or "Its model draws it."
		lines[#lines + 1] = { text = text, colour = GREEN }
	end
	tip(button, set.name, lines)
end

local function initDrawn(button, set, new)
	if new then
		button:SetScript("OnEnter", Client.Guarded(drawnEnter))
		button:SetScript("OnLeave", _G.GameTooltip_Hide)
	end
	fillSetRow(button, set, set.draws and "baked")
end

--- Fill the doodad panel with the doodad's name and the sets of the WMO it is, its list as tall
-- as its sets up to a point, past which it scrolls. A doodad not yet read is read here, each set
-- marked where the doodad draws it, as part of its model or as the map chose. One that is no WMO
-- Furnish has sets for keeps the slot, its list saying so, since it is still what
-- `.doodad select` picked and a panel that stayed shut would say nothing at all.
local function fillDoodad()
	drawn:Flush()
	if doodad and not doodad.sets then
		local of = Console.Source({ entry = doodad.entry, placement = doodad })
		doodad.name = Client.ModelName(doodad.name)
		if of then
			for _, set in ipairs(of.sets) do
				set.draws = set.placed or Sets.DrawnByRoot(of.file, set)
			end
			doodad.sets = of.sets
		else
			local loaded, missing = Reader.Load()
			doodad.sets = {}
			doodad.missing = loaded and "Not a WMO Furnish has sets for." or missing
		end
	end
	if not doodad then
		return
	end
	panel.Name:SetText(doodad.name)
	drawn:InsertTable(doodad.sets)
	local empty = #doodad.sets == 0
	panel.Sets.Empty:SetText(doodad.missing or "")
	panel.Sets.Empty:SetShown(empty)
	local rows = math.min(#doodad.sets, DOODAD_ROWS)
	panel:SetHeight(72 + rows * ROW + 2 * LIST_INSET + (empty and EMPTY_ROOM or 0) + 82)
end

--- Keep the doodad's WMO as the source whatever is selected, with the sets the doodad drew
-- chosen; the destination stays as it is.
local function useDoodad()
	pinned = { entry = doodad.entry, placement = doodad, name = doodad.name }
	frame.Search:SetText("")
	frame.Results:Hide()
	rechoose = true
	refresh()
end

--- Import the doodad picked as the command does: it becomes a gob, and the sets it drew spawn
-- merged into it, the run on the window's bar. The doodad is hidden, not gone, and stays
-- selected, so it stays in its slot. It counts as imported once the server names the gob it
-- made, since the gob is selected by the GUID that names it.
local function importDoodad()
	Console.Import({ uid = doodad.uid, quiet = true, ways = WAYS })
	update()
end

--- A number typed: the destination is the player's own from here on.
local function numberChanged(box, typed)
	if not typed then
		return
	end
	local value = tonumber(box:GetText())
	if not value then
		return
	end
	spot = spot or Pose.At(0, 0, 0)
	holder(spot, box.number)[box.number.key] = value
	spotPinned, spotFollowed = true, false
	update()
end

--- A doodad `.doodad select` picked takes the doodad slot, whatever it is and whether the window
-- is open or not, so the panel never shows one the server no longer holds; it is read once the
-- window shows it. The source and the destination stay the gob selection's.
local function doodadSelected(line)
	local named = Commands.SelectedDoodad(line)
	if not named then
		return
	end
	-- Picked again, a doodad imported stays imported, since the server refuses a second import.
	if doodad and doodad.uid == named.uid then
		named.imported = doodad.imported
	end
	doodad = named
	if frame:IsShown() then
		fillDoodad()
		update()
	end
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
			insetAfterAxis(box)
		end
	end
	-- The source's ID box is as wide as one of the three on the destination's first row.
	local id = frame.SourceID
	id:SetWidth((width - 2 * NUMBER_GAP) / 3 - NUMBER_ART)
	insetAfterAxis(id)
end

--- Size each button to its words and its caps.
local function fitButtons()
	local buttons = {
		frame.Here,
		frame.UseSelected,
		frame.SpawnSource,
		frame.Highlight,
		offer.Paste,
	}
	for _, button in ipairs(buttons) do
		fit(button)
	end
end

--- Make a list of rows, each made from a template, in a box made from FurnishListTemplate,
-- whose scroll bar shows only while there is somewhere to scroll.
local function listOf(box, data, template, initializer)
	dress(box, PANEL)
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
	local inset = LIST_INSET
	_G.ScrollUtil.AddManagedScrollBarVisibilityBehavior(box.ScrollBox, box.ScrollBar, {
		anchor("TOPLEFT", box, "TOPLEFT", inset, -inset),
		anchor("BOTTOMRIGHT", box, "BOTTOMRIGHT", -BAR_ROOM, inset),
	}, {
		anchor("TOPLEFT", box, "TOPLEFT", inset, -inset),
		anchor("BOTTOMRIGHT", box, "BOTTOMRIGHT", -inset, inset),
	})
	box.ScrollBox:SetDataProvider(data)
end

--- The server named the gob an import made, so the doodad in the panel, where it is the one, is
-- imported, and the server refuses a second import.
local function importConfirmed(uid)
	-- A unique id is a number where the window read it off a line, and a string where an import
	-- line names it.
	if not (uid and doodad and tostring(doodad.uid) == tostring(uid)) then
		return
	end
	if not doodad.imported then
		doodad.imported = true
		if frame:IsShown() then
			update()
		end
	end
end

--- An import typed as the server's own command is heard by its line. The window sends nothing for
-- it: the server selects the gob it made but sends no record of it, and reading that gob is the
-- player's own `.gob select`.
local function importHeard(line)
	importConfirmed(Commands.Imported({ line }))
end

--- What the window hears only while it is open: the gob selection, the phase, and runs, since
-- a shut window draws nothing and catches up as it opens. The doodad slot is heard always, in
-- build, since a doodad picked while the window is shut is still the one picked.
local function listen()
	stops = {
		Client.OnSelection(refresh),
		-- The blueprint offer shows while the run's group is selected.
		Client.OnSelection(Client.Guarded(showOffer)),
		Client.OnPhaseChange(update),
		Console.Watch({
			started = Client.Guarded(started),
			progress = Client.Guarded(progressed),
			deleting = Client.Guarded(progressed),
			finished = Client.Guarded(finished),
			-- A wait ends on the record of the object it waited for, which reaches the window's own
			-- listener while the wait still stands, so the button is redrawn when the wait ends too.
			waiting = Client.Guarded(update),
		}),
	}
end

--- Catch up with runs the window did not hear while it was shut: one going on is drawn where it
-- has got to, and one that ended is said on the bar, unless it was said already.
local function catchUp()
	local going, ended = Console.Run()
	if going then
		started()
	elseif run then
		run = nil
		frame.Progress:SetScript("OnUpdate", nil)
	end
	if not going and ended and ended.result ~= told then
		finished(ended.result, ended.seconds)
	end
	showOffer()
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
	dress(frame.Results, OVERLAY, { 0.06, 0.06, 0.06, 1 })
end

local function buildSource()
	frame.SourceLabel:SetText("Source")
	frame.SourceFollow.Label:SetText("Follow selection")
	frame.SourceFollow:SetScript("OnClick", Client.Guarded(followSource))
	hint(frame.SourceFollow, nil, {
		{ text = "Ticked: follows the selected WMO." },
		{ text = "Unticked: stays as it is." },
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
		{ text = "The gob entry of the source's WMO." },
		{ text = "Type one to keep that WMO." },
	})
	lightOnHover(id)
	frame.SpawnSource:SetText("Spawn WMO")
	frame.SpawnSource:SetMotionScriptsWhileDisabled(true)
	frame.SpawnSource:SetScript(
		"OnClick",
		Client.Guarded(function()
			Console.SpawnGob(shownEntry, WAYS)
		end)
	)
	hint(frame.SpawnSource, nil, function()
		return {
			{ text = "Spawn the source's WMO where you stand." },
			-- Read when shown: the entry the source has then, or none while there is none.
			shownEntry and {
				text = "Typed: " .. Commands.Typed(Commands.SpawnHere(shownEntry)),
				colour = GREY,
			} or {},
		}
	end)
	listOf(list, provider, "FurnishSetRowTemplate", initRow)
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

--- What a leader's tooltip says: what choosing it makes of the objects, and why it cannot lead
-- where it cannot.
local function leadLines(choice)
	local turns = { text = "A group moves, turns and scales about its leader.", colour = GREY }
	if choice.word == "nogroup" then
		return { { text = "Each object stands alone." } }
	elseif choice.word == "pivot" then
		return {
			{ text = "An invisible object at the destination leads." },
			{ text = "One extra object spawns.", colour = GREY },
			turns,
		}
	elseif choice.word == "first" then
		return {
			{ text = "The first object spawned leads." },
			turns,
		}
	end
	local lines
	local selected = selection()
	if selected and selected.group then
		lines = { { text = "The objects join the selected group." } }
	else
		lines = { { text = "The selected gob leads." } }
		if selected and (selected.groupLeader or 0) ~= 0 then
			lines[#lines + 1] = {
				text = selected.name .. " is in a group already; the objects join it.",
				colour = WARN,
			}
		end
	end
	local why = cannotLead()
	if why then
		lines[#lines + 1] = { text = why, colour = RED }
	end
	return lines
end

--- The leader's bar and its segments, one a choice, a click making it the one in force.
local function buildLeader()
	frame.LeaderLabel:SetText("Group leader")
	dress(frame.Leader, SEGMENTS)
	for i, choice in ipairs(Console.GROUPS) do
		local segment = _G.CreateFrame("Button", nil, frame.Leader, "FurnishSegmentTemplate")
		segment.choice = choice
		-- Greyed, a segment still says why when rested on.
		segment:SetMotionScriptsWhileDisabled(true)
		segment:SetScript(
			"OnClick",
			Client.Guarded(function()
				_G.PlaySound(CHOOSE)
				lead = choice.word
				update()
			end)
		)
		-- How a command types the same: a set's number, then the word, which the grouping a
		-- request gets by naming none goes without.
		local typed = choice.word == Console.GROUPED and "<set>" or "<set> " .. choice.word
		hint(segment, function()
			return LABELS[choice.word] or selectedLabel()
		end, function()
			return leadLines(choice)
		end, typed)
		segments[i] = segment
	end
	frame.Leader:HookScript("OnSizeChanged", Client.Guarded(layoutLeader))
end

local function buildDestination()
	frame.DestinationLabel:SetText("Destination")
	frame.DestinationFollow.Label:SetText("Follow selection")
	frame.DestinationFollow:SetScript("OnClick", Client.Guarded(followDestination))
	hint(frame.DestinationFollow, nil, {
		{
			text = "Ticked: follows the selected gob.",
		},
		{ text = "Unticked: stays as it is." },
	})
	for order, number in ipairs(NUMBERS) do
		local box = frame[number.box]
		box.number = number
		box.Axis:SetText(number.box)
		hint(box, number.box, { { text = number.unit } })
		lightOnHover(box)
		box:HookScript("OnTextChanged", Client.Guarded(numberChanged))
		box:SetScript("OnEnterPressed", box.ClearFocus)
		-- Leaving a box shows the value the destination holds, so text that is no number does not stay.
		box:HookScript("OnEditFocusLost", Client.Guarded(update))
		-- Typing replaces the number, and Tab moves on through the boxes, as in ObjectMover.
		box:HookScript("OnEditFocusGained", box.HighlightText)
		box:SetScript(
			"OnTabPressed",
			Client.Guarded(function()
				local step = _G.IsShiftKeyDown() and -1 or 1
				local after = NUMBERS[(order - 1 + step) % #NUMBERS + 1]
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
			fillDestination(here and Pose.Copy(here))
		end)
	)
	frame.UseSelected:SetScript(
		"OnClick",
		Client.Guarded(function()
			local from = selection()
			fillDestination(from and Pose.Copy(from))
		end)
	)
	hint(frame.Here, nil, { { text = "Fill in where you stand and face, once." } }, "<set> here")
	hint(frame.UseSelected, nil, function()
		local from = selection()
		if from and from.group then
			return {
				{
					text = "Fill in the selected group's position, once.",
				},
				{ text = "Level, since a group has no roll or pitch.", colour = GREY },
			}
		end
		return { { text = "Fill in the selected gob's position, once." } }
	end)

	buildLeader()
	frame:HookScript("OnSizeChanged", Client.Guarded(layoutNumbers))
	layoutNumbers()
end

local function buildDoodad()
	panel.Label:SetText("Doodad")
	panel.UseSource:SetText("Use as source")
	panel.Import:SetText("Import doodad")
	listOf(panel.Sets, drawn, "FurnishSetRowTemplate", initDrawn)
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
	hint(panel.UseSource, nil, {
		{
			text = "Keep the doodad's WMO as the source, the sets it drew chosen.",
		},
	})
	hint(panel.Import, nil, importLines, "import")
end

--- Stand the Preview pane against the window's right edge, as tall as the room the side panels
-- leave it: below the doodad panel and above the blueprint offer while they show.
local function placePreview()
	preview:ClearAllPoints()
	if panel:IsShown() then
		preview:SetPoint("TOPLEFT", panel, "BOTTOMLEFT")
	else
		preview:SetPoint("TOPLEFT", frame, "TOPRIGHT")
	end
	if offer:IsShown() then
		preview:SetPoint("BOTTOMLEFT", offer, "TOPLEFT")
	else
		preview:SetPoint("BOTTOMLEFT", frame, "BOTTOMRIGHT")
	end
end

--- Say under the scene how far its models have loaded, and once they have, how long they took.
local function showLoading(loaded, total, seconds)
	local text = ""
	if loaded < total then
		text = ("Loading %s of %s"):format(thousands(loaded), objects(total))
	elseif total > 0 then
		text = ("%s loaded in %.2f s"):format(objects(total), seconds)
	end
	preview.Loading:SetText(text)
end

local function buildPreview()
	preview.Label:SetText("Preview")
	preview.Hint:SetText("Drag to turn, right-drag to pan, wheel to zoom.")
	stage = Scene.New(preview.Scene, showLoading)
	preview.CloseButton:SetScript(
		"OnClick",
		Client.Guarded(function()
			preview:Hide()
		end)
	)
	for _, side in ipairs({ panel, offer }) do
		side:HookScript("OnShow", Client.Guarded(placePreview))
		side:HookScript("OnHide", Client.Guarded(placePreview))
	end
end

--- Make room for the source's picture where Glimpse's WMO pictures are installed: its box shown,
-- and the rows beside it narrowed to leave it its width. Done once, since an addon is installed or
-- not for the whole session.
local function buildPicture()
	if not Previews.Pictured() then
		return
	end
	local box = frame.PictureBox
	dress(box, PANEL)
	box:Show()
	frame.PictureRoom:SetWidth(box:GetWidth() + PICTURE_GAP)
end

local function buildOffer()
	offer.Title:SetText(Console.OFFER.title)
	offer.Why:SetText(Console.OFFER.why)
	offer.Paste:SetText("Paste to chat")
	offer.Name:SetMaxLetters(Names.BLUEPRINT)
	offer.Name:SetMaxBytes(Names.BLUEPRINT)
	-- Closed, the offer goes for good; the next whole run makes the next one.
	offer.CloseButton:SetScript(
		"OnClick",
		Client.Guarded(function()
			Console.DismissOffer()
			showOffer()
		end)
	)
	offer.Paste:SetScript("OnClick", Client.Guarded(pasteOffer))
	offer.Name:SetScript("OnEnterPressed", Client.Guarded(pasteOffer))
	offer.Name:HookScript(
		"OnTextChanged",
		Client.Guarded(function(box, typed)
			-- A blueprint name with a space can only be used by its id, so a space typed is an
			-- underscore.
			local text = box:GetText()
			if typed and text:find(" ") then
				local at = box:GetCursorPosition()
				box:SetText((text:gsub(" ", "_")))
				box:SetCursorPosition(at)
			end
			offer.Paste:SetEnabled(box:GetText() ~= "")
		end)
	)
	hint(offer.Paste, nil, function()
		return {
			{ text = Console.OfferCommand(offer.Name:GetText()) },
			{ text = Console.OFFER.click, colour = GREEN },
		}
	end)
end

local function buildFooter()
	frame.Highlight:SetText("Highlighting")
	frame.Highlight:SetScript("OnClick", Client.Guarded(Console.ToggleHighlight))
	hint(frame.Highlight, nil, {
		{ text = "Outline selected objects, on or off." },
		{ text = Chat.HIGHLIGHT .. ".", colour = GREY },
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
			Console.Stop(true, WAYS)
		end)
	)
	hint(frame.DeleteButton, nil, { { text = "Stop, then delete what this run spawned." } })
end

local function build()
	frame.Header:Setup(Furnish.NAME)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
	-- Moved or resized by hand, the game's own layout cache keeps the window's place and size.
	buildPicture()
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
	buildDestination()
	buildDoodad()
	buildFooter()
	buildOffer()
	buildPreview()
	Client.OnSystemLine(doodadSelected)
	Client.OnSystemLine(importHeard)
	-- Heard always, as the doodad slot is: an import is done when the server names its gob.
	Console.Watch({ imported = Client.Guarded(importConfirmed) })

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
			if not spotPinned and not spotFollowed then
				spot = nil
			end
			-- Fitted here, once every label is set and the client's fonts are certainly loaded.
			fitButtons()
			layoutNumbers()
			listen()
			fillDoodad()
			catchUp()
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
end

--- Show the window, or hide it when it shows.
function Window.Toggle()
	frame:SetShown(not frame:IsShown())
end

build()
