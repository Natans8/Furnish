-- What to spawn: placements, as unordered collections the kernel takes whole.
--
-- A set's rows come from the data; after that they are only rows, to be put together,
-- thinned or picked from before the kernel sees them.

_G.Furnish = _G.Furnish or {}
local Furnish = _G.Furnish
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

--- The rows whose display is not the one given.
function Rows.Without(rows, display)
	local out = {}
	for _, row in ipairs(rows) do
		if row.display ~= display then
			out[#out + 1] = row
		end
	end
	return out
end
