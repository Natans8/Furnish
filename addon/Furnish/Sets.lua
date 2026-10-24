-- Which sets: the ways a root file is found, and the sets it offers.
--
-- The data keys sets by the root's file id. A selected object's record carries that id, and
-- a gameobject entry, the number a lookup line prints, reaches it through the data, which
-- carries every WMO object the server lists. A root Epsilon emptied, an emptywmo twin or one
-- of its own copies, carries in the data the sets of the WMO it was emptied from. A map
-- placement gives the sets the zone chose.

_G.Furnish = _G.Furnish or {}
local Furnish = _G.Furnish
local Sets = {}
Furnish.Sets = Sets

local Reader = Furnish.Reader
local Names = Furnish.Names

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
		offered[i] = set.name ~= "" and ("%d %s"):format(set.index, Names.Set(set.name))
			or tostring(set.index)
	end
	return nil,
		("root file %s has no set %s; it has %s"):format(
			tostring(file),
			tostring(index),
			table.concat(offered, ", ")
		)
end

--- The root file a gameobject entry's object is, or nil and the reason.
function Sets.OfEntry(entry)
	local loaded, reason = Reader.Load()
	if not loaded then
		return nil, reason
	end
	local file = Reader.FileOfEntry(entry)
	if not file then
		return nil,
			("entry %s is no WMO object the data knows, or its root has no doodad sets"):format(
				tostring(entry)
			)
	end
	return file
end

--- Whether a root draws none of its sets itself, Epsilon having emptied it; its sets are
-- the WMO's it was emptied from, and the base set goes under any other.
function Sets.IsBlank(file)
	return Reader.Load() and Reader.IsBlank(file)
end

--- The set ids a WMO placed on the map draws, by map and ADT unique id, the number a
-- `.doodad import` line prints; or nil and the reason. Several on a tile where the zone
-- chose a run of sets.
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
