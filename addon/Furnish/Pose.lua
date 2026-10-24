-- Where to spawn: the anchor's position, rotation and scale, from whatever gives them.
--
-- Every function answers the same shape, { position = { x, y, z }, rotation = { roll, pitch,
-- turn }, scale }, plus whatever else the source knew, so a surface may take the pose from
-- one source and anything else from another. Nothing here sends a command: an object's
-- record is read off the selection the player made, never one the addon makes for them. A
-- doodad is reached the same way, since `.doodad import` selects what it imports.

_G.Furnish = _G.Furnish or {}
local Furnish = _G.Furnish
local Pose = {}
Furnish.Pose = Pose

local Client = Furnish.Client

--- A pose from plain values.
-- @param turn degrees, 0 north, or nil for north
-- @param scale or nil for 1
function Pose.At(x, y, z, turn, scale)
	return {
		position = { x = x, y = y, z = z },
		rotation = { roll = 0, pitch = 0, turn = turn or 0 },
		scale = scale or 1,
	}
end

--- The player's own spot and facing, level, at scale 1; `map` beside it.
function Pose.Here()
	local x, y, z, map = Client.Position()
	if not x then
		return nil, "the client did not answer the player's position"
	end
	local pose = Pose.At(x, y, z, Client.Facing())
	pose.map = map
	return pose
end

--- An object's pose from EpsilonLib's record of it. The rotation is the record's own, roll
-- on x, pitch on y, turn on z, with the server's orientation standing in for the turn where
-- the record carries none. Beside the pose: guid, entry, file, name, wmo, groupLeader, canEdit.
function Pose.OfRecord(object)
	local rotation = object.transform and object.transform.rotation or {}
	local position = object.transform and object.transform.position or {}
	local turn = rotation.z or 0
	if turn == 0 and object.orientation and object.orientation ~= 0 then
		turn = math.deg(object.orientation)
	end
	local name = Client.ModelName(object.name)
	return {
		position = { x = position.x, y = position.y, z = position.z },
		rotation = { roll = rotation.x or 0, pitch = rotation.y or 0, turn = turn },
		scale = object.scale or 1,
		guid = tonumber(object.guid),
		entry = tonumber(object.entry),
		file = object.fileID,
		name = name,
		wmo = object.IsWMO and object:IsWMO() or false,
		groupLeader = object.groupLeader or 0,
		canEdit = object.canEdit,
	}
end

--- The selected object's pose, from the record the server pushed for it. The core never
-- selects anything itself, since that would move the player's own selection.
-- @return the pose; or nil and the reason, false standing for a group selection
function Pose.Selected()
	local object = Client.Selected()
	if object == false then
		return nil, "a group is selected, not one object"
	end
	if not object then
		return nil, "no object is selected"
	end
	return Pose.OfRecord(object)
end
