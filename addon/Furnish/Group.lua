-- Which group: the GUID that leads an existing object's group, for a spawn that joins it.
--
-- `Furnish.Group` is the kernel's table of grouping words; this file adds the one provider
-- that turns an object into the GUID the kernel takes in their place.

_G.Furnish = _G.Furnish or {}
local Furnish = _G.Furnish
local Group = Furnish.Group

local Pose = Furnish.Pose

--- The GUID leading the group an object is in, or the object's own when it is in none.
-- @param callback function(leader) or function(nil, reason)
function Group.Leading(guid, callback)
	Pose.Of(guid, function(pose, reason)
		if not pose then
			return callback(nil, reason)
		end
		if pose.groupLeader and pose.groupLeader ~= 0 then
			return callback(pose.groupLeader)
		end
		callback(pose.guid)
	end)
end
