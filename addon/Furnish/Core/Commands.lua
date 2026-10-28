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

--- The command that spawns an object, before what it spawns.
Commands.SPAWN = "gobject spawn"

--- Whether an angle in degrees is zero for the server's purposes, so a spawn need not say it;
-- any angle, a record's as readily as one Transform.Place answers.
function Commands.IsLevel(angle)
	local turned = angle % 360
	return turned < 0.0005 or turned > 359.9995
end

--- Whether a scale is 1 for the server's purposes, so a spawn need not say it.
function Commands.IsUnit(scale)
	return math.abs(scale - 1) < 0.0005
end

--- What `.gob spawn` takes for a display: the display as a negative number, where a positive one
-- is a gameobject entry.
-- @param display the gameobject display id, as the data holds it, positive
function Commands.OfDisplay(display)
	return -display
end

--- The spawn command for a display at a world pose, saying only what differs from a plain
-- spawn: scale 1, a level rotation and a northward turn each cost no word.
-- @param display the gameobject display id, as the data holds it, positive
-- @param pose { x, y, z, roll, pitch, turn, scale }, what Transform.Place answers
function Commands.Spawn(display, pose)
	return Commands.SpawnObject(Commands.OfDisplay(display), pose)
end

--- The spawn command for what `.gob spawn` takes, where the player stands and the way they face,
-- as the server places a spawn that names no position.
-- @param id a gameobject entry, or a display as a negative number
function Commands.SpawnHere(id)
	return ("%s %d"):format(Commands.SPAWN, id)
end

--- The spawn command for what `.gob spawn` takes, at a world pose, as Spawn says it.
-- @param id a gameobject entry, or a display as a negative number
-- @param pose { x, y, z, roll, pitch, turn, scale }, what Transform.Place answers
function Commands.SpawnObject(id, pose)
	local words = { Commands.SpawnHere(id) }
	if not Commands.IsUnit(pose.scale) then
		words[#words + 1] = "scale " .. Commands.Number(pose.scale)
	end
	words[#words + 1] = "posx " .. Commands.Number(pose.x)
	words[#words + 1] = "posy " .. Commands.Number(pose.y)
	words[#words + 1] = "posz " .. Commands.Number(pose.z)
	if not Commands.IsLevel(pose.pitch) then
		words[#words + 1] = "pitch " .. Commands.Number(pose.pitch)
	end
	if not Commands.IsLevel(pose.roll) then
		words[#words + 1] = "roll " .. Commands.Number(pose.roll)
	end
	-- A spawn takes the player's facing, so the turn is always said; north is how zero is said,
	-- since the server reads a bare zero as nothing.
	if Commands.IsLevel(pose.turn) then
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

--- Select an object by its GUID, which also has the server push the object's record; without
-- one, the object nearest the player, as a player selects one by hand.
function Commands.Select(guid)
	if guid then
		return "gobject select " .. guid
	end
	return "gobject select"
end

--- Turn the client's highlighting of the selection on or off as state says, "on" or "off";
-- without one, on if it is off and off if it is on.
function Commands.Highlight(state)
	if state then
		return "toggle highlight " .. state
	end
	return "toggle highlight"
end

--- Select the whole group a GUID leads, for the group commands that follow.
function Commands.SelectGroup(leader)
	return "gobject group select " .. leader
end

--- Save the selected group as a blueprint of the name given.
function Commands.BlueprintNew(name)
	return "gobject blueprint new " .. name
end

--- A command as a player types it into chat, behind its dot.
function Commands.Typed(command)
	return "." .. command
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

--- The links a server line names a doodad by, and whether each is one taken off the map: by a
-- delete, or by an import or a replace, which put an object in its place.
local DOODAD_LINKS = { doodad_uid = false, doodad_deleted_uid = true }

--- What a doodad link in a server line names: the doodad's unique id, the gameobject entry the
-- number after its name is, the map the line says it stands on, nil for a line that names none,
-- as a near line does, and whether it is off the map; or nil for a line with no doodad link. The
-- server colours the map's number, so it is read off the line scrubbed.
function Commands.DoodadLink(line)
	local link, uid, entry = line:match("|H(doodad_%a*_?uid):(%d+):[^|]*|h%[.- %- (%d+)%]|h")
	local removed = DOODAD_LINKS[link]
	if removed == nil then
		return nil
	end
	local map = tonumber(Commands.Plain(line):match(" on map (%d+)"))
	return tonumber(uid), tonumber(entry), map, removed
end

--- The gameobject entry a gob's selection or spawn line names, a spawn selecting what it makes;
-- or nil for any other line.
function Commands.GobLine(line)
	local said = line:find("Selected gameobject", 1, true)
		or line:find("Spawned gameobject", 1, true)
	return said and tonumber(line:match("|Hgameobject_entry:(%d+)|h")) or nil
end

--- What a doodad selection's line names, the line `.doodad select` prints and no addon message
-- carries: { uid, entry, name, map, removed, status }, the doodad's unique id, the entry after its
-- name, its name as the line spells it, the map it stands on, whether it is off the map, and if
-- so the word the line says how in, lower case, as "replaced"; or nil for any other line.
function Commands.SelectedDoodad(line)
	if not line:find("Selected doodad", 1, true) then
		return nil
	end
	local uid, entry, map, removed = Commands.DoodadLink(line)
	if not (uid and map) then
		return nil
	end
	local name = line:match("|Hdoodad_%a*_?uid:[^|]*|h%[(.-) %- %d+%]|h")
	local status = removed and Commands.Plain(line):match("%] %((%a+)%)") or nil
	return {
		uid = uid,
		entry = entry,
		name = name,
		map = map,
		removed = removed,
		status = status and status:lower(),
	}
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
