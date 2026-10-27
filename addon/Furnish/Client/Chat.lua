-- How Furnish writes to chat: its prefix, its colours, a menu of buttons, and its links.
--
-- Chat has no columns, and spaces cannot make one, since the chat font is proportional. A
-- menu's buttons are laid as many to a line as the chat frame holds, measured in the player's
-- own font, a texture the client ships that draws nothing standing between them. The help
-- keeps to short lines instead, since padding to a column drifted in game.
--
-- A link is the client's garrison-mission link carrying Furnish's own words. The client
-- ignores one it cannot read as a mission, and Furnish acts on the ones it wrote.

local _, Furnish = ...
local Chat = {}
Furnish.Chat = Chat

--- The colours lines are drawn in: gold for a command and a number, white for a name, the
-- client's link blue for what a click acts on, grey for what is said in passing, red for a
-- fault, and the blue of the prefix.
Chat.GOLD, Chat.WHITE, Chat.BLUE, Chat.GREY, Chat.RED, Chat.PREFIX =
	"|cffffd100", "|cffffffff", "|cff71d5ff", "|cff9d9d9d", "|cffff2020", "|cff66ccff"
Chat.END = "|r"

--- A count with its thousands set apart.
function Chat.Thousands(count)
	local text, done = tostring(count), 1
	while done > 0 do
		text, done = text:gsub("^(%-?%d+)(%d%d%d)", "%1,%2")
	end
	return text
end

--- A count and what it counts, singular for one: "1 set", "1,204 objects".
function Chat.Count(count, noun)
	if count == 1 then
		return "1 " .. noun
	end
	return Chat.Thousands(count) .. " " .. noun .. "s"
end

--- A count of objects: "1 object", "1,204 objects".
function Chat.Objects(count)
	return Chat.Count(count, "object")
end

--- A run past this many objects is counted by tenths rather than quarters, since a quarter of it
-- would leave over 125 objects between lines.
local LONG_RUN = 500

--- How far a run goes between the lines chat counts it by: a quarter of it, a tenth past
-- LONG_RUN, and never under ten objects, so a run says at most three such lines, nine once it
-- is long, and none at ten objects or fewer.
function Chat.Stride(total)
	if total > LONG_RUN then
		return math.ceil(total / 10)
	end
	return math.max(10, math.ceil(total / 4))
end

--- The risk a player is reminded of before a big spawn. Whether highlighting is on stays the
-- player's to decide, so Furnish only says this and never turns it off.
Chat.HIGHLIGHT = "Highlighting too many objects can crash the game"

--- A tooltip's colours: the title, a label beside its value, a plain line, what a click does,
-- a warning and a refusal.
Chat.TIP = {
	title = { 1, 0.82, 0 },
	label = { 0.62, 0.62, 0.62 },
	text = { 1, 1, 1 },
	click = { 0.25, 1, 0.25 },
	warning = { 1, 0.5, 0.5 },
	refusal = { 1, 0.13, 0.13 },
}

--- Fill a tooltip that is owned already: a gold title, then each line, a { label, value } pair
-- drawn as two columns, or a { text, colour } line of its own, wrapped. Every tooltip Furnish
-- draws goes through here, so the same kind of line looks the same wherever it is.
function Chat.Tip(tooltip, title, lines)
	local tip = Chat.TIP
	tooltip:SetText(title, tip.title[1], tip.title[2], tip.title[3])
	for _, line in ipairs(lines) do
		if line.value then
			local label, value = tip.label, tip.text
			tooltip:AddDoubleLine(
				line.label,
				tostring(line.value),
				label[1],
				label[2],
				label[3],
				value[1],
				value[2],
				value[3]
			)
		elseif line.text then
			local colour = line.colour or tip.text
			tooltip:AddLine(line.text, colour[1], colour[2], colour[3], true)
		end
	end
end

--- What a player types for an action, as a message spells it: the command's first name, as
-- Command.lua registers it, and the words, if any.
function Chat.Typed(words)
	if words == "" then
		return _G.SLASH_FURNISH1
	end
	return _G.SLASH_FURNISH1 .. " " .. words
end

--- Print one line, with the prefix that says who wrote it.
function Chat.Say(text)
	print(Chat.PREFIX .. Furnish.NAME .. ":" .. Chat.END .. " " .. text)
end

--- Print one line without the prefix, for the lines under a heading.
function Chat.Line(text)
	print(text)
end

local SPACER = "Interface/Common/Spacer"

local function frame()
	local chat = _G.DEFAULT_CHAT_FRAME
	if chat and chat.GetFont and chat.CreateFontString then
		return chat
	end
	return nil
end

local ruler

--- How wide text draws in the chat frame's own font, in pixels; nil where nothing can
-- measure it, as outside the client.
local function width(text)
	local chat = frame()
	if not chat then
		return nil
	end
	local file, height, flags = chat:GetFont()
	if not ruler then
		ruler = chat:CreateFontString(nil, "ARTWORK")
		ruler:Hide()
	end
	ruler:SetFont(file, height, flags)
	ruler:SetText(text)
	return ruler:GetStringWidth()
end

local function gap(pixels)
	pixels = math.floor(pixels)
	if pixels < 1 then
		return ""
	end
	return "|T" .. SPACER .. ":1:" .. pixels .. "|t"
end

--- The space kept after a column: half the font's height, so it grows with the font. Only
-- asked once a width was measured, so the frame is there.
local function gutter()
	local _, height = frame():GetFont()
	return math.floor(height / 2)
end

--- Buttons laid out as a menu under a heading: indented, a gutter between each, and as many to
-- a line as the chat frame holds, so no button breaks across two lines. Outside the client,
-- where nothing measures, every button goes on one line.
-- @param buttons links, each drawn as its label in brackets
-- @return the lines to print
function Chat.Menu(buttons)
	local chat, indent = frame(), "  "
	local first = buttons[1] and width(buttons[1])
	if not (chat and first) then
		return { indent .. table.concat(buttons, " ") }
	end
	local space = gutter()
	local room = chat:GetWidth() - width(indent) - space
	local lines, line, used = {}, {}, 0
	for _, button in ipairs(buttons) do
		local drawn = width(button)
		if #line > 0 and used + space + drawn > room then
			lines[#lines + 1] = indent .. table.concat(line, gap(space))
			line, used = {}, 0
		end
		used = used + (#line > 0 and space or 0) + drawn
		line[#line + 1] = button
	end
	if #line > 0 then
		lines[#lines + 1] = indent .. table.concat(line, gap(space))
	end
	return lines
end

local LINK = "garrmission:furnish"

--- A link drawn as its label in brackets, carrying Furnish's words.
-- @param words the words a click reads back, joined by colons
-- @param label what the link shows
function Chat.Link(words, label)
	return Chat.BLUE .. "|H" .. LINK .. ":" .. words .. "|h[" .. label .. "]|h" .. Chat.END
end

--- The words of one of Furnish's links, or nil for any other link.
local function wordsOf(link)
	return link:match("^" .. LINK .. ":(.*)$")
end

--- Add text to the end of the server's lines: append(line) answers what to add, or nil to
-- leave the line as it came. The client runs a filter once for each chat frame showing a
-- line, so the answer for the last line is kept. Filters run in the order they were added,
-- each adding to what the one before it left: this one is added as Furnish loads, after
-- GLink's, which the toc loads first, and before Glimpse's, which is added at login, so the
-- server's own buttons come first, then Furnish's, then the preview.
function Chat.OnServerLines(append)
	local last, shown
	local filter = Furnish.Client.Guarded(function(_, _, message, ...)
		if type(message) ~= "string" then
			return false
		end
		if message ~= last then
			last = message
			local extra = append(message)
			shown = extra and message .. extra or nil
		end
		if not shown then
			return false
		end
		return false, shown, ...
	end)
	_G.ChatFrame_AddMessageEventFilter("CHAT_MSG_SYSTEM", filter)
end

--- Act on Furnish's links: onClick(words, modifier) when one is clicked, where modifier is
-- "share" for the client's chat-link click, "ctrl" for a control-click and nil for a plain
-- one; onEnter(words, tooltip) when the pointer rests on one, with the tooltip owned and
-- empty. Called once, at load.
function Chat.OnLinks(onClick, onEnter)
	_G.hooksecurefunc(
		"SetItemRef",
		Furnish.Client.Guarded(function(link)
			local words = wordsOf(link)
			if not words then
				return
			end
			local modifier
			if _G.IsModifiedClick("CHATLINK") then
				modifier = "share"
			elseif _G.IsControlKeyDown() then
				modifier = "ctrl"
			end
			onClick(words, modifier)
		end)
	)
	-- Whether the tooltip showing is one of Furnish's, so leaving another addon's link
	-- does not hide what that addon drew.
	local holding = false
	local enter = Furnish.Client.Guarded(function(chat, link)
		local words = wordsOf(link)
		if words then
			_G.GameTooltip:SetOwner(chat, "ANCHOR_CURSOR")
			onEnter(words, _G.GameTooltip)
			_G.GameTooltip:Show()
			holding = true
		end
	end)
	local leave = Furnish.Client.Guarded(function()
		if holding then
			holding = false
			_G.GameTooltip:Hide()
		end
	end)
	for i = 1, _G.NUM_CHAT_WINDOWS do
		local chat = _G["ChatFrame" .. i]
		if chat then
			chat:HookScript("OnHyperlinkEnter", enter)
			chat:HookScript("OnHyperlinkLeave", leave)
		end
	end
end
