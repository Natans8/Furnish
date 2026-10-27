-- How a set's name reads to a player. The data keeps every name as the WMO spells it, since
-- that spelling is the key a tooltip shows and a lookup goes back to, and this file turns it
-- into words wherever it is drawn: a leading "Set_" dropped, underscores, hyphens and case
-- humps split, and every word title-cased. A word in capitals is an acronym and kept as it is,
-- but only in a name that also holds lower case: a name written wholly in capitals says
-- nothing through its case, so every word of it is title-cased. It also names a blueprint after
-- the WMO and the sets a run spawned.
--
-- Every function is pure, so the whole file runs outside the client.

local _, Furnish = ...
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

--- A word as it is drawn: an acronym stays in capitals, anything else is title-cased.
local function cased(word, shouted)
	if not shouted and word:match("^%u+$") then
		return word
	end
	return word:sub(1, 1):upper() .. word:sub(2):lower()
end

--- Every name worked out so far, by its spelling; the names a session meets are few.
local spelled = {}

--- A set name as a player reads it. The default set's empty name stays empty, and a name
-- that is nothing but its prefix is drawn as spelled.
function Names.Set(name)
	local known = spelled[name]
	if known then
		return known
	end
	local rest = name:gsub("^%s+", ""):gsub("%s+$", ""):gsub("^[Ss][Ee][Tt]_", "")
	local shouted = not rest:find("%l")
	local words = {}
	local word = ""
	local before = ""
	for i = 1, #rest do
		local here = rest:sub(i, i)
		if here:match("[_%-%s]") then
			if word ~= "" then
				words[#words + 1] = cased(word, shouted)
			end
			word = ""
		else
			if word ~= "" and boundary(before, here, rest:sub(i + 1, i + 1)) then
				words[#words + 1] = cased(word, shouted)
				word = ""
			end
			word = word .. here
		end
		before = here
	end
	if word ~= "" then
		words[#words + 1] = cased(word, shouted)
	end
	local drawn = #words == 0 and name or table.concat(words, " ")
	spelled[name] = drawn
	return drawn
end

--- The most bytes a blueprint name may take. The chat box sends 255 at most, a longer line goes
-- out in pieces, and this keeps the command and some room back; a longer name is the player's.
Names.BLUEPRINT = 225

--- A piece of a blueprint name: lower case, a run of spaces an underscore, since a name with a
-- space can only be used by its id.
local function piece(text)
	return (text:lower():gsub("%s+", "_"))
end

--- The name a blueprint of a run is offered under: the WMO's name, "set" or "sets" where the sets
-- went without their WMO, then each set's name as a player reads it, the base set's as "base". A
-- name longer than Names.BLUEPRINT gives the sets by index instead, which always fits.
-- @param wmo the WMO's name as Furnish shows it
-- @param sets a list of { index, name }, each name as the WMO spells it, in index order
-- @param apart true where the sets went without their WMO, so the name says set
function Names.Blueprint(wmo, sets, apart)
	local head = piece(wmo)
	if apart then
		head = head .. (#sets == 1 and "_set" or "_sets")
	end
	local named, numbered = { head }, { head }
	for _, set in ipairs(sets) do
		local words = Names.Set(set.name)
		named[#named + 1] = piece(words == "" and "base" or words)
		numbered[#numbered + 1] = tostring(set.index)
	end
	local name = table.concat(named, "_")
	if #name <= Names.BLUEPRINT then
		return name
	end
	return table.concat(numbered, "_")
end
