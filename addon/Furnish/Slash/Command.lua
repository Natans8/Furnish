-- The command: what a player types, read into a request for the console, the help that says
-- what can be typed, and the clicks on a list's links. The command alone is the window's.
--
-- The commands and the words are declared once, below, and the help is read off them.

local _, Furnish = ...
local Command = {}
Furnish.Command = Command

local Client = Furnish.Client
local Console = Furnish.Console
local Chat = Furnish.Chat

--- What can be typed after the command, in the order the help says it.
Command.USAGE = {
	{ "", "the window" },
	{ "list [<entry>]", "a WMO's sets, as buttons" },
	{ "<set> [from <entry>]", "spawn a set on the selected gob" },
	{ "<set> here [<entry>]", "spawn a set at your feet" },
	{ "import", "import the selected doodad with its set" },
	{ "stop [delete]", "stop a run, deleting what it spawned with delete" },
}

--- The words that may follow a set, a list or an import, in the order the help says them.
-- Each sets one field of the request: first the groupings Console declares, which share one,
-- all but the one a request gets by naming none, then the rest.
Command.WORDS = {}
for _, grouping in ipairs(Console.GROUPS) do
	if grouping.word ~= Console.GROUPED then
		Command.WORDS[#Command.WORDS + 1] =
			{ word = grouping.word, field = "group", value = grouping.word, hint = grouping.hint }
	end
end
for _, each in ipairs({
	{ word = "base", field = "base", value = true, hint = "the base set as well" },
	{
		word = "quiet",
		field = "quiet",
		value = true,
		hint = "no progress counts in chat",
	},
}) do
	Command.WORDS[#Command.WORDS + 1] = each
end

local WORD = {}
for _, each in ipairs(Command.WORDS) do
	WORD[each.word] = each
end

--- One of the links this file writes: a doodad line's button, "import", carrying the doodad's
-- unique id; a gob line's, "list", carrying the gob's entry; or a word in the help, "word".
-- A list's buttons for its sets carry words of Console's own.
local function link(kind, value, label)
	return Chat.Link(kind .. ":" .. value, label)
end

--- What kind of link this file wrote words for, and what it carries; nil for words it did not.
local function linked(words)
	return words:match("^(%a+):(.+)$")
end

local function number(token)
	return token and token:match("^%d+$") and tonumber(token)
end

--- What a player typed after the command, as a request; or nil and the way out.
-- @return { action = "window" | "help" | "list" | "spawn" | "import" | "stop", and the fields the
--   console reads: index, entry, here, group, base, delete }
function Command.Parse(text)
	local tokens = {}
	for token in text:lower():gmatch("%S+") do
		tokens[#tokens + 1] = token
	end
	local head = tokens[1]
	if head == nil then
		return { action = "window" }
	elseif head == "help" then
		return { action = "help" }
	end
	if head == "stop" then
		if tokens[2] == nil or (tokens[2] == "delete" and tokens[3] == nil) then
			return { action = "stop", delete = tokens[2] == "delete" }
		end
		return nil, "stop takes delete or nothing: " .. Chat.Typed("stop delete")
	end
	local request, i
	if head == "list" then
		request = { action = "list", entry = number(tokens[2]) }
		i = request.entry and 3 or 2
	elseif head == "import" then
		request, i = { action = "import" }, 2
	elseif number(head) then
		request, i = { action = "spawn", index = number(head) }, 2
	else
		return nil, head .. " is not a Furnish command; " .. Chat.Typed("help") .. " shows them"
	end
	local said = {}
	while tokens[i] do
		local token = tokens[i]
		if token == "from" or token == "here" then
			if request.action ~= "spawn" then
				return nil,
					("%s follows a set's number, as %s"):format(token, Chat.Typed("3 " .. token))
			end
			local entry = number(tokens[i + 1])
			if token == "from" and not entry then
				return nil, "from takes an object's entry, as " .. Chat.Typed("3 from <entry>")
			end
			if entry and request.entry then
				return nil, "name the object once, as " .. Chat.Typed("3 here <entry>")
			end
			if token == "here" then
				request.here = true
			end
			request.entry = request.entry or entry
			i = i + (entry and 2 or 1)
		else
			local word = WORD[token]
			if not word then
				return nil,
					token .. " is not a word Furnish knows; " .. Chat.Typed("help") .. " shows them"
			end
			if said[word.field] then
				return nil,
					("%s and %s cannot go together; choose one"):format(said[word.field], token)
			end
			said[word.field] = token
			request[word.field] = word.value
			i = i + 1
		end
	end
	return request
end

--- The help, as lines: what the command takes, one short line each, then the words on one line,
-- each a link that says what it does when rested on. No columns: a line short enough never
-- wraps, and padding drawn in the chat font cannot be measured to the pixel. A list's buttons
-- and a chat line's [Furnish] say what they do in their own tooltips, so the help leaves them out.
local function helpLines()
	local lines = {
		Chat.GOLD
			.. Furnish.NAME
			.. Chat.END
			.. Chat.GREY
			.. " spawns a WMO's doodad sets as objects"
			.. Chat.END,
	}
	for _, row in ipairs(Command.USAGE) do
		lines[#lines + 1] = "  " .. Chat.GOLD .. Chat.Typed(row[1]) .. Chat.END .. ": " .. row[2]
	end
	local words = {}
	for _, each in ipairs(Command.WORDS) do
		words[#words + 1] = link("word", each.word, each.word)
	end
	lines[#lines + 1] = "  "
		.. Chat.GREY
		.. "After a set or import:"
		.. Chat.END
		.. " "
		.. table.concat(words, " ")
	return lines
end

--- How the console's lines name a way out to a player at the command line or in chat: as the
-- command is typed, read when said, since the command's name is set further down.
Command.WAYS = {
	stop = function()
		return Chat.Typed("stop")
	end,
	list = function(entry)
		return Chat.Typed(entry and "list " .. entry or "list")
	end,
	from = function()
		return Chat.Typed("3 from <entry>")
	end,
	here = function()
		return Chat.Typed("3 here <entry>")
	end,
}

--- Act on what a player typed after the command.
function Command.Run(text)
	local request, reason = Command.Parse(text)
	if not request then
		return Chat.Say(reason)
	end
	request.ways = Command.WAYS
	if request.action == "window" then
		Furnish.Window.Toggle()
	elseif request.action == "help" then
		for _, line in ipairs(helpLines()) do
			Chat.Line(line)
		end
	elseif request.action == "list" then
		Console.List(request)
	elseif request.action == "spawn" then
		Console.Spawn(request)
	elseif request.action == "import" then
		Console.Import(request)
	else
		Console.Stop(request.delete, Command.WAYS)
	end
end

--- A click on a list's button spawns its set: plainly on the selected object, with ctrl at
-- the player's feet. A click on a doodad line's button imports that WMO and furnishes it,
-- and one on a gob line's lists the gob's sets.
function Command.Click(words, modifier)
	-- TODO: a shift-click shares the set, once what a shared set carries is decided.
	if modifier == "share" then
		return
	end
	local kind, value = linked(words)
	if kind == "import" then
		return Console.Import({ uid = value, ways = Command.WAYS })
	elseif kind == "list" then
		return Console.List({ entry = tonumber(value), ways = Command.WAYS })
	end
	local offered = Console.OfferIn(words)
	if offered then
		return Console.PasteOffer(offered)
	end
	local request = Console.LinkRequest(words)
	if request then
		request.here = modifier == "ctrl"
		request.ways = Command.WAYS
		Console.Spawn(request)
	end
end

--- What resting on one of Furnish's links shows: a set and its clicks, what a doodad or gob
-- line's button does, or what a word in the help does.
function Command.Hover(words, tooltip)
	local kind, value = linked(words)
	if kind == "import" then
		return Console.DescribeImport(tooltip)
	elseif kind == "list" then
		return Chat.Tip(
			tooltip,
			Furnish.NAME,
			{ { text = "Click: list this WMO's sets", colour = Chat.TIP.click } }
		)
	elseif kind == "word" and WORD[value] then
		return Chat.Tip(tooltip, value, { { text = WORD[value].hint } })
	end
	local offered = Console.OfferIn(words)
	if offered then
		return Console.DescribeOffer(offered, tooltip)
	end
	local request = Console.LinkRequest(words)
	if request then
		Console.Describe(request, tooltip)
	end
end

-- TODO: both names are placeholders until the command's final name is chosen. Messages
-- read the first through Chat.Typed, so a rename is these two lines.
_G.SLASH_FURNISH1 = "/furn"
_G.SLASH_FURNISH2 = "/furnish"
_G.SlashCmdList.FURNISH = Client.Guarded(Command.Run)
Chat.OnLinks(Command.Click, Command.Hover)

--- The unique id of the doodad a server line names by its link, where it is a WMO
-- Furnish has sets for, still on the map, and the map placed it with a set beyond its base, so
-- that importing it spawns something. The number after the name in the link is the object's gameobject
-- entry, and the data answers for it; the name is never read, since many a WMO's
-- name has no `.wmo` in it. A select line names its map, and a near line's doodads stand on
-- the player's. The first such line loads the data.
function Command.PlacedWmo(line)
	local uid, entry, map, removed = Furnish.Commands.DoodadLink(line)
	-- One taken off the map, by a delete, an import or a replace, cannot be imported.
	local file = uid and not removed and Furnish.Sets.OfEntry(entry)
	if not file then
		return nil
	end
	if Furnish.Sets.DrawsBeyondBase(file, map or Client.Map(), uid) then
		return uid
	end
	return nil
end

--- The entry of the gob a selection or a spawn line names, where it is a WMO Furnish has sets
-- for, a spawn selecting what it makes; the number in the link is the entry, and the name is
-- never read.
function Command.SelectedWmo(line)
	local entry = Furnish.Commands.GobLine(line)
	if entry and Furnish.Sets.OfEntry(entry) then
		return entry
	end
	return nil
end

-- A WMO's doodad line, from a select or a near, gets a button that imports and furnishes
-- it, and a WMO gob's selection or spawn line one that lists its sets, beside the server's own,
-- unless the player has turned the buttons off.
Chat.OnServerLines(function(line)
	if not Furnish.Settings.chatButtons then
		return nil
	end
	local uid = Command.PlacedWmo(line)
	if uid then
		return " - " .. link("import", uid, Furnish.NAME)
	end
	local entry = Command.SelectedWmo(line)
	return entry and " - " .. link("list", entry, Furnish.NAME) or nil
end)
