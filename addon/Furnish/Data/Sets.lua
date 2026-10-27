-- Which sets: the ways a root file is found, and the sets it offers.
--
-- The data keys sets by the root's file id. A selected object's record carries that id, and
-- a gameobject entry, the number a lookup line prints, reaches it through the data, which
-- carries every WMO object the server lists. A root Epsilon emptied, an emptywmo twin or one
-- of its own copies, carries in the data the sets of the WMO it was emptied from. A map
-- placement gives the sets the zone chose.

local _, Furnish = ...
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
	for _, set in ipairs(sets) do
		if set.index == index then
			return set
		end
	end
	local offered = {}
	for i, set in ipairs(sets) do
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

--- The set ids beyond its base a WMO placed on the map draws, by map and ADT unique id, the
-- number a `.doodad import` line prints; or nil and the reason. Several on a tile where the
-- zone chose a run of sets. The data keeps no placement that draws only its base set.
function Sets.OfPlacement(map, uid)
	local loaded, reason = Reader.Load()
	if not loaded then
		return nil, reason
	end
	local ids = Reader.MapSets(map, uid)
	if not ids then
		return nil,
			("the data has no map placement %s on map %s that draws a set beyond its base"):format(
				tostring(uid),
				tostring(map)
			)
	end
	return ids
end

--- The sets of a root that a list of set ids names, in index order.
function Sets.Named(file, ids)
	local wanted = {}
	for _, id in ipairs(ids or {}) do
		wanted[id] = true
	end
	local named = {}
	for _, set in ipairs(Sets.OfFile(file) or {}) do
		if wanted[set.id] then
			named[#named + 1] = set
		end
	end
	return named
end

--- Whether a WMO placed on the map draws a set beyond its base, the one set the gob it is
-- imported as draws itself; false where the data has no such placement.
-- @param file the root's file id
function Sets.DrawsBeyondBase(file, map, uid)
	for _, set in ipairs(Sets.Named(file, Sets.OfPlacement(map, uid))) do
		if set.index ~= 0 then
			return true
		end
	end
	return false
end

--- Whether two roots offer the same sets, as an emptied copy and the WMO it was emptied from do.
function Sets.Same(a, b)
	local one, other = Sets.OfFile(a), Sets.OfFile(b)
	if not (one and other) or #one ~= #other then
		return false
	end
	for i, set in ipairs(one) do
		if set.id ~= other[i].id then
			return false
		end
	end
	return true
end
