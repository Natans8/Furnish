-- Which sets: the ways a root file is found, and the sets it offers.
--
-- The data keys sets by the root's file id, and a selected object's record carries that id:
-- the record is the key, and another root is another object selected. The one root never
-- standing in the world is an emptywmo's original, which its name gives by construction,
-- the prefix trimmed and the rest looked up in the client's own display table. A map
-- placement gives the sets the zone chose.

_G.Furnish = _G.Furnish or {}
local Furnish = _G.Furnish
local Sets = {}
Furnish.Sets = Sets

local Reader = Furnish.Reader
local Client = Furnish.Client
local Commands = Furnish.Commands

--- The sets a root file offers, in index order, or nil and the reason.
-- @return a list of { index, id, name, count }; the default set's name is ""
function Sets.OfFile(file)
	local loaded, reason = Reader.Load()
	if not loaded then
		return nil, reason
	end
	local raw = Reader.Sets(file)
	if not raw then
		return nil, ("the data has no doodad sets for root file %s"):format(tostring(file))
	end
	local sets = {}
	for i, entry in ipairs(raw) do
		sets[i] = { index = entry[1], id = entry[2], name = entry[3], count = entry[4] }
	end
	return sets
end

--- One set of a root by its index, or nil and a reason that lists the indexes there are.
function Sets.Pick(file, index)
	local sets, reason = Sets.OfFile(file)
	if not sets then
		return nil, reason
	end
	local offered = {}
	for i, set in ipairs(sets) do
		if set.index == index then
			return set
		end
		offered[i] = set.name ~= "" and ("%d %s"):format(set.index, set.name) or tostring(set.index)
	end
	return nil,
		("root file %s has no set %s; it has %s"):format(
			tostring(file),
			tostring(index),
			table.concat(offered, ", ")
		)
end

--- The root file a model name spawns, through the client's own display table. Only an
-- emptywmo's original is reached this way, since a name is a convention and not a key.
local function fileOfName(name)
	local wanted = Client.ModelName(name)
	local found = Client.SearchModels(wanted)
	for _, row in ipairs(found) do
		if Sets.OfFile(row.file) then
			return row.file
		end
	end
	if #found > 0 then
		return nil,
			("%s is in the client's model list but the data has no doodad sets for it"):format(
				wanted
			)
	end
	return nil, ("no model is named %s"):format(wanted)
end

--- The root file an emptywmo was hollowed from, by its name with the prefix trimmed.
function Sets.Original(name)
	local original = name:gsub("^eps_emptywmo_", "eps_"):gsub("^emptywmo_", "")
	local file, reason = fileOfName(original)
	if not file then
		return nil, ("%s has no original to borrow from: %s"):format(name, reason)
	end
	return file
end

--- The set ids a WMO placed on the map draws, by map and ADT unique id; or nil and the
-- reason. Several on a tile where the zone chose a run of sets.
function Sets.OfPlacement(map, uid)
	local loaded, reason = Reader.Load()
	if not loaded then
		return nil, reason
	end
	local ids = Reader.MapSets(map, uid)
	if not ids then
		return nil,
			("the data has no map placement %s on map %s; only WMOs placed by the map are known"):format(
				tostring(uid),
				tostring(map)
			)
	end
	return ids
end
