-- The server's grammar, in one place: every command the addon spells and every reply it
-- reads. Nothing else in the addon writes a command word or matches a reply, so a change in
-- what the server accepts or prints is a change here and nowhere else.
--
-- Every function is pure: a value in, a string out, or a reply in, a value out.

_G.Furnish = _G.Furnish or {}
local Furnish = _G.Furnish
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
	local words = { "gobject spawn -" .. display }
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

--- A spawn with the join chained onto its line, so the spawned object joins at once.
function Commands.Chained(spawn, leader)
	return spawn .. " group add " .. leader
end

function Commands.Delete(guid)
	return "gobject delete " .. guid
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
