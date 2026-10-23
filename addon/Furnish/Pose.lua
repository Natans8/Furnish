-- Where to spawn: the anchor's position, rotation and scale, from whatever gives them.
--
-- Every function answers the same shape, { position = { x, y, z }, rotation = { roll, pitch,
-- turn }, scale }, plus whatever else the source knew, so a surface may take the pose from
-- one source and anything else from another. A rotation the source did not know is nil,
-- which the kernel reads as level.

_G.Furnish = _G.Furnish or {}
local Furnish = _G.Furnish
local Pose = {}
Furnish.Pose = Pose

local Client = Furnish.Client
local Commands = Furnish.Commands

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
-- the record carries none. Beside the pose: guid, file, name, wmo, empty, groupLeader,
-- canEdit.
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
		file = object.fileID,
		name = name,
		wmo = object.IsWMO and object:IsWMO() or false,
		empty = name:find("emptywmo_", 1, true) ~= nil,
		groupLeader = object.groupLeader or 0,
		canEdit = object.canEdit,
	}
end

--- An object's pose by GUID. EpsilonLib keeps a record only for the selection, so the
-- object is selected first unless it already is.
-- @param callback function(pose) or function(nil, reason)
function Pose.Of(guid, callback)
	local wanted = tonumber(guid)
	if not wanted then
		return callback(nil, ("a gameobject GUID is a number, not %s"):format(tostring(guid)))
	end
	local function deliver(object, reason)
		if not object then
			return callback(nil, reason)
		end
		callback(Pose.OfRecord(object))
	end
	local selected = Client.Selected()
	if selected and tonumber(selected.guid) == wanted then
		return deliver(selected)
	end
	local send, why = Client.Send()
	if not send then
		return callback(nil, why)
	end
	send(Commands.Select(wanted), function(success, messages)
		if not success then
			return callback(
				nil,
				("gobject select %d was refused: %s"):format(wanted, Commands.Quote(messages))
			)
		end
		Client.AwaitSelection(wanted, deliver)
	end)
end

--- A map doodad's pose from its `.doodad select` line, which the client prints and keeps
-- nowhere. Beside the pose: uid, map, entry, name. The line carries no rotation, so the
-- rotation is nil; the data's own placement, by map and uid, is where one would come from.
function Pose.OfDoodad(line)
	local doodad = Commands.DoodadIn(line)
	if not doodad then
		return nil, "that is not a `.doodad select` line"
	end
	return {
		position = { x = doodad.x, y = doodad.y, z = doodad.z },
		rotation = nil,
		scale = doodad.scale,
		uid = doodad.uid,
		map = doodad.map,
		entry = doodad.entry,
		name = doodad.name,
	}
end
