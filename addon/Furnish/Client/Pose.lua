-- Where to spawn: the anchor's position, rotation and scale, from whatever gives them.
--
-- Every function answers the same shape, { position = { x, y, z }, rotation = { roll, pitch,
-- turn }, scale }, plus whatever else the source knew, so a surface may take the pose from
-- one source and anything else from another. Nothing here sends a command: an object's
-- record is read off the selection the player made, never one the addon makes for them. A
-- doodad is reached the same way, since `.doodad import` selects what it imports.

local _, Furnish = ...
local Pose = {}
Furnish.Pose = Pose

local Client = Furnish.Client
local Commands = Furnish.Commands
local Transform = Furnish.Transform

--- How far apart two positions may be, in yards, and still be one place: far below what the eye
-- can tell, and above the rounding a position read back from the server carries.
local NEAR = 0.01

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

--- A pose's numbers, a copy of its own: the position, the rotation and the scale, and nothing of
-- what they were read off, so a number changed never reaches the record.
function Pose.Copy(pose)
	local at, turned = pose.position, pose.rotation
	return {
		position = { x = at.x, y = at.y, z = at.z },
		rotation = { roll = turned.roll, pitch = turned.pitch, turn = turned.turn },
		scale = pose.scale,
	}
end

--- The pose that sets a placement down where this pose stands, the rest of its set about it as
-- the set places them: the pose moved back by the placement's own offset, turned and scaled as the
-- pose turns and scales.
-- @param row a placement, { x, y, z, ... } in its set's own axes
function Pose.Leading(pose, row)
	local turn, scale = pose.rotation, pose.scale or 1
	local anchor = Transform.FromAngles(turn.roll, turn.pitch, turn.turn)
	local x, y, z = Transform.Turned(anchor, row.x * scale, row.y * scale, row.z * scale)
	local moved = Pose.Copy(pose)
	local at = moved.position
	at.x, at.y, at.z = at.x - x, at.y - y, at.z - z
	return moved
end

--- Whether two poses stand in one place, turned and scaled alike, as the server reads them.
function Pose.Same(a, b)
	for _, axis in ipairs({ "x", "y", "z" }) do
		if math.abs(a.position[axis] - b.position[axis]) >= NEAR then
			return false
		end
	end
	for _, angle in ipairs({ "roll", "pitch", "turn" }) do
		if not Commands.IsLevel((a.rotation[angle] or 0) - (b.rotation[angle] or 0)) then
			return false
		end
	end
	return Commands.IsUnit(a.scale / b.scale)
end

--- The player's own spot and facing, level, at scale 1.
function Pose.Here()
	local x, y, z = Client.Position()
	if not x then
		return nil, "the client did not answer the player's position"
	end
	return Pose.At(x, y, z, Client.Facing())
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

--- A group's pose, from its leader's record: where the leader stands, the way it faces and its
-- scale, which a group scales relative to, but level, since a group has no roll or pitch of its
-- own and the leader's are only the leader's. Beside it: guid and groupLeader, both the
-- leader's GUID, so a run that includes it joins the group; the leader's name; and group, true.
-- It is no WMO, whatever leads it.
function Pose.OfGroup(leader)
	local pose = Pose.OfRecord(leader)
	pose.rotation.roll, pose.rotation.pitch = 0, 0
	pose.groupLeader = pose.guid
	pose.file, pose.wmo, pose.group = nil, false, true
	return pose
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
