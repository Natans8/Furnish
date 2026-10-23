-- How a set's name reads to a player. The data keeps every name as the WMO spells it, since
-- that spelling is the key a tooltip shows and a lookup goes back to, and this file turns it
-- into words wherever it is drawn: a leading "Set_" dropped, underscores, hyphens and case
-- humps split, every word title-cased, and a word already in capitals kept as it is.
--
-- Every function is pure, so the whole file runs outside the client.

_G.Furnish = _G.Furnish or {}
local Furnish = _G.Furnish
local Names = {}
Furnish.Names = Names

local function isUpper(c)
	return c:match("%u") ~= nil
end

local function isLower(c)
	return c:match("%l") ~= nil
end

local function isDigit(c)
	return c:match("%d") ~= nil
end

--- Whether a word boundary falls between two neighbouring characters, the one after being
-- the start of a word: a hump, a letter meeting a digit, or the last capital of a run that
-- a lower-case letter follows, so that "HTTPServer" splits before "Server".
local function boundary(before, here, after)
	if isUpper(here) then
		return isLower(before) or isDigit(before) or (isUpper(before) and isLower(after))
	end
	if isDigit(here) then
		return not isDigit(before)
	end
	return isDigit(before)
end

--- A word as it is drawn: capitals stay capitals, anything else is title-cased.
local function cased(word)
	if word:match("^%u+$") then
		return word
	end
	return word:sub(1, 1):upper() .. word:sub(2):lower()
end

--- A set name as a player reads it. The default set's empty name stays empty, and a name
-- that is nothing but its prefix is drawn as spelled.
function Names.Set(name)
	local rest = name:gsub("^%s+", ""):gsub("%s+$", ""):gsub("^[Ss][Ee][Tt]_", "")
	local words = {}
	local word = ""
	local before = ""
	for i = 1, #rest do
		local here = rest:sub(i, i)
		if here:match("[_%-%s]") then
			if word ~= "" then
				words[#words + 1] = cased(word)
			end
			word = ""
		else
			if word ~= "" and boundary(before, here, rest:sub(i + 1, i + 1)) then
				words[#words + 1] = cased(word)
				word = ""
			end
			word = word .. here
		end
		before = here
	end
	if word ~= "" then
		words[#words + 1] = cased(word)
	end
	if #words == 0 then
		return name
	end
	return table.concat(words, " ")
end
