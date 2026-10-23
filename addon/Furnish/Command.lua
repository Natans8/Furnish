-- The command, its names declared in Chat.lua: what a player types, read into a request for
-- the console, the help that says what can be typed, and the clicks on a list's links. The
-- command alone is the window's.
--
-- The commands and the words are declared once, below, and the help is read off them.

_G.Furnish = _G.Furnish or {}
local Furnish = _G.Furnish
local Command = {}
Furnish.Command = Command

local Client = Furnish.Client
local Console = Furnish.Console
local Chat = Furnish.Chat

--- What can be typed after the command, in the order the help says it.
Command.USAGE = {
	{ "help", "this help" },
	{ "list", "the selected building's sets" },
	{ "list <entry>", "an object's sets, by the entry on its lookup line" },
	{ "<set>", "spawn a set on the selected building" },
	{ "<set> from <entry>", "spawn an object's set on the selected object" },
	{ "<set> here", "spawn the selected building's set at your feet" },
	{ "<set> here <entry>", "spawn an object's set at your feet" },
	{ "import", "import the selected doodad and furnish it, grouped on it" },
	{ "stop", "stop spawning" },
	{ "stop delete", "stop, and delete what was spawned" },
}

--- The words that may follow a set, a list or an import, in the order the help says them.
-- Each sets one field of the request; the three that say who leads the group share one.
Command.WORDS = {
	{ word = "first", field = "group", value = "first", hint = "its first object leads the group" },
	{
		word = "attach",
		field = "group",
		value = "attach",
		hint = "join the selected object's group",
	},
	{ word = "nogroup", field = "group", value = "nogroup", hint = "spawn every object ungrouped" },
	{ word = "base", field = "base", value = true, hint = "lay the base set under it" },
}

local WORD = {}
for _, each in ipairs(Command.WORDS) do
	WORD[each.word] = each
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

--- The help, as lines: what the command takes, then the words.
local function helpLines()
	local lefts = {}
	for _, row in ipairs(Command.USAGE) do
		lefts[#lefts + 1] = Chat.GOLD .. Chat.Typed(row[1]) .. Chat.END
	end
	for _, each in ipairs(Command.WORDS) do
		lefts[#lefts + 1] = Chat.GOLD .. each.word .. Chat.END
	end
	local widest = Chat.Widest(lefts)
	local lines = {
		Chat.GOLD
			.. "Furnish"
			.. Chat.END
			.. Chat.GREY
			.. " spawns a building's doodad sets as objects"
			.. Chat.END,
	}
	for i, row in ipairs(Command.USAGE) do
		lines[#lines + 1] = "  " .. Chat.Cell(lefts[i], widest) .. row[2]
	end
	lines[#lines + 1] = Chat.GREY .. "After a set, list or import:" .. Chat.END
	for i, each in ipairs(Command.WORDS) do
		lines[#lines + 1] = "  " .. Chat.Cell(lefts[#Command.USAGE + i], widest) .. each.hint
	end
	lines[#lines + 1] = Chat.GREY
		.. "A set in a list is a link: click it to spawn it, ctrl-click to spawn it at your feet."
		.. Chat.END
	return lines
end

--- Act on what a player typed after the command.
function Command.Run(text)
	local request, reason = Command.Parse(text)
	if not request then
		return Chat.Say(reason)
	end
	if request.action == "window" then
		-- TODO: open the window, once it is built.
		Chat.Say("the window is not built yet; " .. Chat.Typed("help") .. " lists the commands")
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
		Console.Stop(request.delete)
	end
end

--- A list link's words as the request a click makes, or nil for words it did not write.
local function fromLink(words)
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

--- A click on a list link spawns its set: plainly on the selected object, with ctrl at
-- the player's feet.
function Command.Click(words, modifier)
	-- TODO: a shift-click shares the set, once what a shared set carries is decided.
	if modifier == "share" then
		return
	end
	local request = fromLink(words)
	if request then
		request.here = modifier == "ctrl"
		Console.Spawn(request)
	end
end

--- What resting on a list link shows: the set, then what a click and a ctrl-click do.
function Command.Hover(words, tooltip)
	local request = fromLink(words)
	if request then
		Console.Describe(request, tooltip)
	end
end

for i, name in ipairs(Chat.COMMANDS) do
	_G["SLASH_FURNISH" .. i] = name
end
_G.SlashCmdList.FURNISH = Client.Guarded(Command.Run)
Chat.OnLinks(Command.Click, Command.Hover)
