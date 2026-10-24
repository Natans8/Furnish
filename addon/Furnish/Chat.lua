-- How Furnish writes to chat: its prefix, its colours, columns of exact width, and its links.
--
-- Chat has no columns, and spaces cannot make one, since the chat font is proportional. A
-- gap of an exact number of pixels is a texture the client ships that draws nothing, that
-- many pixels wide, measured on the chat frame in the player's own font.
--
-- A link is the client's garrison-mission link carrying Furnish's own words. The client
-- ignores one it cannot read as a mission, and Furnish acts on the ones it wrote.

_G.Furnish = _G.Furnish or {}
local Furnish = _G.Furnish
local Chat = {}
Furnish.Chat = Chat

--- The colours lines are drawn in: gold for a command and a number, white for a name, the
-- client's link blue for what a click acts on, grey for what is said in passing, and the
-- blue of the prefix.
Chat.GOLD, Chat.WHITE, Chat.BLUE, Chat.GREY, Chat.PREFIX =
	"|cffffd100", "|cffffffff", "|cff71d5ff", "|cff9d9d9d", "|cff66ccff"
Chat.END = "|r"

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
	print(Chat.PREFIX .. "Furnish:" .. Chat.END .. " " .. text)
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

--- Text padded to a column as wide as the widest text it holds, plus the gutter. Outside the
-- client, where nothing measures, one space stands in for the gap.
-- @param text the cell, markup and all
-- @param widest the widest text of the column
function Chat.Cell(text, widest)
	local column, drawn = width(widest), width(text)
	if not column or not drawn then
		return text .. " "
	end
	return text .. gap(column - drawn + gutter())
end

--- The text of a column that draws widest, to size the column by; the longest where
-- nothing can measure.
function Chat.Widest(texts)
	local widest, most = "", -1
	for _, text in ipairs(texts) do
		local drawn = width(text) or #text
		if drawn > most then
			widest, most = text, drawn
		end
	end
	return widest
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
