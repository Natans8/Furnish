-- The server's grammar, in one place: every command the addon spells and every reply it
-- reads. Nothing else in the addon writes a command word or matches a reply, so a change in
-- what the server accepts or prints is a change here and nowhere else.
--
-- Every function is pure: a value in, a string out, or a reply in, a value out.

local _, Furnish = ...
local Commands = {}
Furnish.Commands = Commands

--- The longest text EpsilonLib's AddonCommands will send; it refuses from 250 up.
Commands.LIMIT = 249

--- A number as the command line carries it: enough digits to give the server every one it
-- keeps, and no trailing zeros, sign or exponent for the common values.
function Commands.Number(value)
	local text = string.format("%.9g", value)
	if text:find("e") then
		text = string.format("%.9f", value):gsub("0+$", ""):gsub("%.$", "")
	end
	if text == "-0" then
		return "0"
	end
	return text
end

--- Whether an angle in degrees is zero for the server's purposes.
local function level(angle)
	return angle < 0.0005 or angle > 359.9995
end

--- The spawn command for a display at a world pose, saying only what differs from a plain
-- spawn: scale 1, a level rotation and a northward turn each cost no word.
-- @param display the gameobject display id, as the data holds it, positive
-- @param pose { x, y, z, roll, pitch, turn, scale }, what Transform.Place answers
function Commands.Spawn(display, pose)
	return Commands.SpawnObject(-display, pose)
end

--- The spawn command for what `.gob spawn` takes, at a world pose, as Spawn says it.
-- @param id a gameobject entry, or a display as a negative number
-- @param pose { x, y, z, roll, pitch, turn, scale }, what Transform.Place answers
function Commands.SpawnObject(id, pose)
	local words = { ("gobject spawn %d"):format(id) }
	if math.abs(pose.scale - 1) >= 0.0005 then
		words[#words + 1] = "scale " .. Commands.Number(pose.scale)
	end
	words[#words + 1] = "posx " .. Commands.Number(pose.x)
	words[#words + 1] = "posy " .. Commands.Number(pose.y)
	words[#words + 1] = "posz " .. Commands.Number(pose.z)
	if not level(pose.pitch) then
		words[#words + 1] = "pitch " .. Commands.Number(pose.pitch)
	end
	if not level(pose.roll) then
		words[#words + 1] = "roll " .. Commands.Number(pose.roll)
	end
	-- A spawn takes the player's facing, so the turn is always said; north is how zero is said,
	-- since the server reads a bare zero as nothing.
	if level(pose.turn) then
		words[#words + 1] = "face north"
	else
		words[#words + 1] = "face north turn " .. Commands.Number(pose.turn)
	end
	return table.concat(words, " ")
end

--- Add the selected object to the group a GUID leads.
function Commands.Join(leader)
	return "gobject group add " .. leader
end

function Commands.Delete(guid)
	return "gobject delete " .. guid
end

--- Select an object by its GUID, which also has the server push the object's record.
function Commands.Select(guid)
	return "gobject select " .. guid
end

--- Turn the client's highlighting of the selection on if it is off, or off if it is on.
function Commands.Highlight()
	return "toggle highlight"
end

--- Select the whole group a GUID leads, for the group commands that follow.
function Commands.SelectGroup(leader)
	return "gobject group select " .. leader
end

--- Turn a doodad into a gameobject: the one a unique id names, or the selected one.
function Commands.Import(uid)
	if uid then
		return "doodad import " .. uid
	end
	return "doodad import"
end

--- What an import reply names: the doodad's unique id on its map and the new object's
-- GUID, both as strings, and the model's name; or nil for any other reply.
function Commands.Imported(messages)
	for _, message in ipairs(messages or {}) do
		-- Every system line comes here, so one that cannot be an import is passed over unscrubbed.
		if message:find("UniqueId", 1, true) then
			local plain = Commands.Plain(message)
			local uid, guid = plain:match("%(UniqueId: (%d+)%) as GUID (%d+)")
			if uid then
				return uid, guid, plain:match("%[(.-) %- %d+%]")
			end
		end
	end
	return nil
end

--- What a doodad link in a server line names: the doodad's unique id, the gameobject entry the
-- number after its name is, and the map the line says it stands on, nil for a line that names
-- none, as a near line does; or nil for a line with no doodad link.
function Commands.DoodadLink(line)
	local uid, entry = line:match("|Hdoodad_uid:(%d+):[^|]*|h%[.- %- (%d+)%]|h")
	if not uid then
		return nil
	end
	return tonumber(uid), tonumber(entry), tonumber(line:match(" on map (%d+)"))
end

--- The gameobject entry a gob's selection or spawn line names, a spawn selecting what it makes;
-- or nil for any other line.
function Commands.GobLine(line)
	local said = line:find("Selected gameobject", 1, true)
		or line:find("Spawned gameobject", 1, true)
	return said and tonumber(line:match("|Hgameobject_entry:(%d+)|h")) or nil
end

--- What a doodad selection's line names, the line `.doodad select` prints and no addon message
-- carries: { uid, entry, name, map }, the doodad's unique id, the entry after its name, its name
-- as the line spells it and the map it stands on; or nil for any other line.
function Commands.SelectedDoodad(line)
	-- Every system line comes here, so one that cannot be a selection is passed over unscrubbed.
	if not line:find("Selected doodad", 1, true) then
		return nil
	end
	local plain = Commands.Plain(line)
	local name, entry, uid = plain:match("Selected doodad %[(.-) %- (%d+)%] %(UID: (%d+)%)")
	local map = plain:match(" on map (%d+)")
	if not (name and map) then
		return nil
	end
	return { uid = tonumber(uid), entry = tonumber(entry), name = name, map = tonumber(map) }
end

--- A reply with its colour codes and link wrappers removed, for quoting in a message.
function Commands.Plain(text)
	return (
		tostring(text or "")
			:gsub("|c%x%x%x%x%x%x%x%x", "")
			:gsub("|r", "")
			:gsub("|H[^|]*|h", "")
			:gsub("|h", "")
	)
end

--- The GUID a spawn reply names, as a string, or nil.
function Commands.GuidIn(messages)
	for _, message in ipairs(messages or {}) do
		local guid = message:match("gameobject_GUID:[0-9]+|h([0-9]+)|h")
			or message:match("GUID: |c%x%x%x%x%x%x%x%x([0-9]+)")
		if guid then
			return guid
		end
	end
	return nil
end
