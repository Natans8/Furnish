-- The placement maths: where a doodad stands in the world once its house stands somewhere.
--
-- A placement is relative to its WMO: a position in the WMO's own axes and a quaternion. A
-- spawned house has a position, a rotation and a scale of its own, and the server takes a
-- spawn's rotation as three angles, roll about X, pitch about Y, turn about Z, in degrees.
-- So a doodad's world pose is the house's rotation applied to its scaled offset, added to
-- the house's position, and the two rotations multiplied and read back as angles.
--
-- Facing 0 is north, which is +X, and the angle grows toward west, which is +Y; that is the
-- convention the paste tool spawned correctly under, and it is kept here unchanged. Every
-- function is pure, so the whole file runs outside the client.

_G.Furnish = _G.Furnish or {}
local Furnish = _G.Furnish
local Transform = {}
Furnish.Transform = Transform

local IDENTITY = { x = 0, y = 0, z = 0, w = 1 }

--- The quaternion that applies b first and then a, as the product a * b.
function Transform.Multiply(a, b)
	return {
		x = a.w * b.x + a.x * b.w + a.y * b.z - a.z * b.y,
		y = a.w * b.y + a.y * b.w + a.z * b.x - a.x * b.z,
		z = a.w * b.z + a.z * b.w + a.x * b.y - a.y * b.x,
		w = a.w * b.w - a.x * b.x - a.y * b.y - a.z * b.z,
	}
end

--- A vector turned by a quaternion.
function Transform.Rotate(q, v)
	-- q * v * conj(q), with the middle product written out for a pure vector.
	local tx = 2 * (q.y * v.z - q.z * v.y)
	local ty = 2 * (q.z * v.x - q.x * v.z)
	local tz = 2 * (q.x * v.y - q.y * v.x)
	return {
		x = v.x + q.w * tx + (q.y * tz - q.z * ty),
		y = v.y + q.w * ty + (q.z * tx - q.x * tz),
		z = v.z + q.w * tz + (q.x * ty - q.y * tx),
	}
end

--- The quaternion for roll about X, then pitch about Y, then turn about Z, in degrees.
function Transform.FromAngles(roll, pitch, turn)
	local hr, hp, ht = math.rad(roll or 0) / 2, math.rad(pitch or 0) / 2, math.rad(turn or 0) / 2
	local cr, sr = math.cos(hr), math.sin(hr)
	local cp, sp = math.cos(hp), math.sin(hp)
	local ct, st = math.cos(ht), math.sin(ht)
	return {
		x = sr * cp * ct - cr * sp * st,
		y = cr * sp * ct + sr * cp * st,
		z = cr * cp * st - sr * sp * ct,
		w = cr * cp * ct + sr * sp * st,
	}
end

local function clamp(v)
	if v > 1 then
		return 1
	elseif v < -1 then
		return -1
	end
	return v
end

local function degrees(radians)
	local value = math.deg(radians) % 360
	if value < 0 then
		value = value + 360
	end
	return value
end

--- The roll, pitch and turn a quaternion stands for, each in degrees within [0, 360).
function Transform.ToAngles(q)
	local roll = math.atan2(2 * (q.w * q.x + q.y * q.z), 1 - 2 * (q.x * q.x + q.y * q.y))
	local pitch = math.asin(clamp(2 * (q.w * q.y - q.z * q.x)))
	local turn = math.atan2(2 * (q.w * q.z + q.x * q.y), 1 - 2 * (q.y * q.y + q.z * q.z))
	return degrees(roll), degrees(pitch), degrees(turn)
end

--- Whether an angle in degrees is zero for the server's purposes.
local function level(angle)
	return angle < 0.0005 or angle > 359.9995
end

--- Where a placement stands once its house stands at a pose.
-- @param house { x, y, z, roll, pitch, turn, scale }, angles in degrees, scale 1 for none
-- @param row { x, y, z, qx, qy, qz, qw, scale } as the reader gives a placement
-- @return { x, y, z, roll, pitch, turn, scale }, angles in degrees within [0, 360)
function Transform.Place(house, row)
	local scale = house.scale or 1
	local houseTurn = Transform.FromAngles(house.roll, house.pitch, house.turn)
	local offset =
		Transform.Rotate(houseTurn, { x = row.x * scale, y = row.y * scale, z = row.z * scale })
	local rotation = { x = row.qx, y = row.qy, z = row.qz, w = row.qw }
	local roll, pitch, turn = Transform.ToAngles(Transform.Multiply(houseTurn, rotation))
	return {
		x = house.x + offset.x,
		y = house.y + offset.y,
		z = house.z + offset.z,
		roll = roll,
		pitch = pitch,
		turn = turn,
		scale = row.scale * scale,
	}
end

--- A number as the command line carries it: enough digits to give the server every one it
-- keeps, and no trailing zeros, sign or exponent for the common values.
function Transform.Number(value)
	local text = string.format("%.9g", value)
	if text:find("e") then
		text = string.format("%.9f", value):gsub("0+$", ""):gsub("%.$", "")
	end
	if text == "-0" then
		return "0"
	end
	return text
end

--- The spawn command for a doodad at a world pose, saying only what differs from a plain
-- spawn: scale 1, a level rotation and a northward turn each cost no word.
-- @param display the doodad's display id, as the data holds it, positive
-- @param pose what Place answered
function Transform.SpawnCommand(display, pose)
	local words = { "gobject spawn -" .. display }
	if math.abs(pose.scale - 1) >= 0.0005 then
		words[#words + 1] = "scale " .. Transform.Number(pose.scale)
	end
	words[#words + 1] = "posx " .. Transform.Number(pose.x)
	words[#words + 1] = "posy " .. Transform.Number(pose.y)
	words[#words + 1] = "posz " .. Transform.Number(pose.z)
	if not level(pose.pitch) then
		words[#words + 1] = "pitch " .. Transform.Number(pose.pitch)
	end
	if not level(pose.roll) then
		words[#words + 1] = "roll " .. Transform.Number(pose.roll)
	end
	-- A spawn takes the player's facing, so the turn is always said; north is how zero is said,
	-- since the server reads a bare zero as nothing.
	if level(pose.turn) then
		words[#words + 1] = "face north"
	else
		words[#words + 1] = "face north turn " .. Transform.Number(pose.turn)
	end
	return table.concat(words, " ")
end

Transform.IDENTITY = IDENTITY
