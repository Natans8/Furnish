-- The placement maths: where a doodad stands in the world once its anchor stands somewhere.
--
-- A placement is relative to its WMO root: a position in the root's own axes, a quaternion
-- and a scale. An anchor is a position, a rotation and a scale in the world, and the server
-- takes a rotation as three angles, roll about X, pitch about Y, turn about Z, in degrees.
-- So a doodad's world pose is the anchor's rotation applied to its scaled offset, added to
-- the anchor's position, and the two rotations multiplied and read back as angles.
--
-- Facing 0 is north, which is +X, and the angle grows toward west, which is +Y; that is the
-- convention the paste tool spawned correctly under, and it is kept here unchanged. Every
-- function is pure, so the whole file runs outside the client.

local _, Furnish = ...
local Transform = {}
Furnish.Transform = Transform

--- The quaternion that applies b first and then a, as the product a * b.
function Transform.Multiply(a, b)
	return {
		x = a.w * b.x + a.x * b.w + a.y * b.z - a.z * b.y,
		y = a.w * b.y + a.y * b.w + a.z * b.x - a.x * b.z,
		z = a.w * b.z + a.z * b.w + a.x * b.y - a.y * b.x,
		w = a.w * b.w - a.x * b.x - a.y * b.y - a.z * b.z,
	}
end

--- The three numbers of a vector turned by a quaternion, for a caller that keeps vectors as
-- numbers rather than tables, as one testing many boxes a frame does.
function Transform.Turned(q, x, y, z)
	-- q * v * conj(q), with the middle product written out for a pure vector.
	local tx = 2 * (q.y * z - q.z * y)
	local ty = 2 * (q.z * x - q.x * z)
	local tz = 2 * (q.x * y - q.y * x)
	return x + q.w * tx + (q.y * tz - q.z * ty),
		y + q.w * ty + (q.z * tx - q.x * tz),
		z + q.w * tz + (q.x * ty - q.y * tx)
end

--- A vector turned by a quaternion.
function Transform.Rotate(q, v)
	local x, y, z = Transform.Turned(q, v.x, v.y, v.z)
	return { x = x, y = y, z = z }
end

--- The quaternion that undoes another: a placement's turn is a unit quaternion, whose inverse is
-- its conjugate.
function Transform.Inverse(q)
	return { x = -q.x, y = -q.y, z = -q.z, w = q.w }
end

--- A placement's own turn as a quaternion, from the four numbers a row carries.
-- @param row { qx, qy, qz, qw, ... } as the reader gives a placement
function Transform.TurnOf(row)
	return { x = row.qx, y = row.qy, z = row.qz, w = row.qw }
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

--- Where a placement stands once its root stands at an anchor.
-- @param position { x, y, z } of the anchor, in yards
-- @param rotation { roll, pitch, turn } of the anchor, in degrees; nil for level
-- @param scale the anchor's scale, 1 for none
-- @param row { x, y, z, qx, qy, qz, qw, scale } as the reader gives a placement
-- @return { x, y, z, roll, pitch, turn, scale }, angles in degrees within [0, 360)
function Transform.Place(position, rotation, scale, row)
	return Transform.Placer(position, rotation, scale)(row)
end

--- Transform.Place for many placements at one anchor: the anchor's rotation is worked out once.
-- @return function(row) answering what Transform.Place answers
function Transform.Placer(position, rotation, scale)
	rotation = rotation or {}
	scale = scale or 1
	local anchor = Transform.FromAngles(rotation.roll, rotation.pitch, rotation.turn)
	return function(row)
		local offset =
			Transform.Rotate(anchor, { x = row.x * scale, y = row.y * scale, z = row.z * scale })
		local roll, pitch, turn =
			Transform.ToAngles(Transform.Multiply(anchor, Transform.TurnOf(row)))
		return {
			x = position.x + offset.x,
			y = position.y + offset.y,
			z = position.z + offset.z,
			roll = roll,
			pitch = pitch,
			turn = turn,
			scale = row.scale * scale,
		}
	end
end
