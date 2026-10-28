-- What to spawn: placements, as collections the kernel takes whole and spawns in order.
--
-- A set's rows come from the data as a trail, each beside the one before, so a player can
-- follow the furnishing with their eyes; after that they are only rows, to be put together
-- before the kernel sees them.

local _, Furnish = ...
local Rows = {}
Furnish.Rows = Rows

local Reader = Furnish.Reader

--- A set's placements, or nil and the reason.
-- @param id a set id, as Sets.OfFile or Sets.OfPlacement give it
-- @return a list of { display, x, y, z, qx, qy, qz, qw, scale }
function Rows.OfSet(id)
	local loaded, reason = Reader.Load()
	if not loaded then
		return nil, reason
	end
	local rows = Reader.Placements(id)
	if not rows then
		return nil, ("the data has no set %s"):format(tostring(id))
	end
	return rows
end

--- The models a set holds: each model file it draws once, { file, count }, the file being the id
-- a model frame renders, the most numerous first and then by file; and how many of its objects
-- draw a display whose file the data does not know, which are left out. Nil and the reason where
-- the set is not in the data.
-- @param id a set id, as Sets.OfFile or Sets.OfPlacement give it
function Rows.Models(id)
	local rows, reason = Rows.OfSet(id)
	if not rows then
		return nil, reason
	end
	local counts, unknown = {}, 0
	for _, row in ipairs(rows) do
		local file = Reader.ModelFile(row.display)
		if file then
			counts[file] = (counts[file] or 0) + 1
		else
			unknown = unknown + 1
		end
	end
	local models = {}
	for file, count in pairs(counts) do
		models[#models + 1] = { file = file, count = count }
	end
	table.sort(models, function(a, b)
		return a.count > b.count or (a.count == b.count and a.file < b.file)
	end)
	return models, unknown
end

--- Every row of every list given, in the order given.
function Rows.Union(...)
	local out = {}
	for i = 1, select("#", ...) do
		for _, row in ipairs(select(i, ...) or {}) do
			out[#out + 1] = row
		end
	end
	return out
end
