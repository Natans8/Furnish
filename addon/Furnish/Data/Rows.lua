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

--- A set's placements with the model file each draws, for a scene of the set: each { display,
-- file, x, y, z, qx, qy, qz, qw, scale }, about the WMO's origin as the rows are. Those drawing a
-- display the data names no file for are left out. Nil and the reason where the set is not in the
-- data.
-- @param id a set id, as Sets.OfFile or Sets.OfPlacement give it
function Rows.Pieces(id)
	local rows, reason = Rows.OfSet(id)
	if not rows then
		return nil, reason
	end
	local pieces = {}
	for _, row in ipairs(rows) do
		local file = Reader.ModelFile(row.display)
		if file then
			local piece = { file = file }
			for key, value in pairs(row) do
				piece[key] = value
			end
			pieces[#pieces + 1] = piece
		end
	end
	return pieces
end
