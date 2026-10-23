-- The door: the core driven by a GUID, for a test from /run.
--
--   /run Furnish.Spawn(guid, 1)                  spawn set 1 on that WMO, pivot-led
--   /run Furnish.Spawn(guid, 1, { attach = true })
--   /run Furnish.Spawn(Furnish.Selected(), 1)    the selected object's GUID
--   /run Furnish.Abort(true)                     stop the run and delete what it spawned
--
-- A GUID becomes a record by selecting the object: EpsilonLib keeps no record by id, only
-- the one the server pushes for the selection. The house is that record reduced to what the
-- plan reads. Nothing here parses text or draws anything; a command and a window come later
-- and call the same functions.

_G.Furnish = _G.Furnish or {}
local Furnish = _G.Furnish

local send
local running

local SELECT_TRIES = 30
local SELECT_INTERVAL = 0.1

local function sender()
	if send then
		return send
	end
	local lib = _G.EpsilonLib
	if not (lib and lib.AddonCommands) then
		return nil, "EpsilonLib is not loaded"
	end
	local ok, registered = pcall(lib.AddonCommands.Register, "Furnish", false)
	if ok and registered then
		send = registered
	else
		send = function(text, callback)
			lib.AddonCommands.Send("Furnish", text, callback, false)
		end
	end
	return send
end

local function say(text)
	print("|cff66ccffFurnish:|r " .. text)
end

--- The selected object's GUID, or nil.
function Furnish.Selected()
	local lib = _G.EpsilonLib
	local object = lib and lib.GameObject and lib.GameObject:GetSelected()
	return object and object.guid
end

--- The plan's house record from EpsilonLib's object record.
-- The rotation is EpsilonLib's own reading of the record, roll on x, pitch on y, turn on z,
-- with the server's orientation standing in for the turn where the record carries none.
function Furnish.HouseOf(object)
	local rotation = object.transform and object.transform.rotation or {}
	local position = object.transform and object.transform.position or {}
	local turn = rotation.z or 0
	if turn == 0 and object.orientation and object.orientation ~= 0 then
		turn = math.deg(object.orientation)
	end
	return {
		guid = object.guid,
		file = object.fileID,
		twinOf = nil,
		x = position.x,
		y = position.y,
		z = position.z,
		roll = rotation.x or 0,
		pitch = rotation.y or 0,
		turn = turn,
		scale = object.scale or 1,
		groupLeader = object.groupLeader or 0,
		canEdit = object.canEdit,
	}
end

--- Select the object and hand its record to the callback once the server has pushed it.
-- @param guid the object's GUID
-- @param callback function(object) or function(nil, reason)
local function resolve(guid, callback)
	local lib = _G.EpsilonLib
	local wanted = tonumber(guid)
	if not wanted then
		return callback(nil, "give the WMO's GUID")
	end
	local selected = lib.GameObject:GetSelected()
	if selected and tonumber(selected.guid) == wanted and not lib.GameObject:IsGroupSelected() then
		return callback(selected)
	end
	local door, why = sender()
	if not door then
		return callback(nil, why)
	end
	door("gobject select " .. wanted, function(success, messages)
		if not success then
			return callback(
				nil,
				"could not select "
					.. wanted
					.. ": "
					.. tostring(messages and messages[1] or "no reply")
			)
		end
		local tries = 0
		local function look()
			local object = lib.GameObject:GetSelected()
			if object and tonumber(object.guid) == wanted then
				return callback(object)
			end
			tries = tries + 1
			if tries >= SELECT_TRIES then
				return callback(nil, "selected " .. wanted .. " but its record never arrived")
			end
			_G.C_Timer.After(SELECT_INTERVAL, look)
		end
		look()
	end)
end

--- Spawn a set on a WMO.
-- @param guid the WMO's GUID; Furnish.Selected() gives the selection's
-- @param index the set's position in the root's MODS, as the listing shows it
-- @param options { attach = bool, nopivot = bool, default = bool }, optional
function Furnish.Spawn(guid, index, options)
	if running and not running.Done() then
		say("a run is still going; Furnish.Abort() stops it")
		return
	end
	local lib = _G.EpsilonLib
	if not (lib and lib.GameObject) then
		say("EpsilonLib is not loaded")
		return
	end
	resolve(guid, function(object, reason)
		if not object then
			say(reason)
			return
		end
		if not object:IsWMO() then
			say("that is not a WMO")
			return
		end
		local plan, refused = Furnish.Plan.Build(Furnish.HouseOf(object), index, options)
		if not plan then
			say(refused)
			return
		end
		local door, why = sender()
		if not door then
			say(why)
			return
		end
		say(
			("spawning set %d%s, %d objects, %s"):format(
				plan.set.index,
				plan.set.name ~= "" and (" " .. plan.set.name) or "",
				plan.doodads,
				plan.leader == "house" and "attached to the house"
					or (plan.leader == "pivot" and "with a pivot" or "first object leading")
			)
		)
		local last = 0
		running = Furnish.Run.Start(plan, door, {
			progress = function(done, total)
				if done == total or done - last >= 10 then
					last = done
					say(("%d of %d"):format(done, total))
				end
			end,
			finished = function(result)
				local text = ("done: %d spawned"):format(#result.spawned)
				if #result.refused > 0 then
					text = text .. (", %d refused"):format(#result.refused)
					for _, refusal in ipairs(result.refused) do
						say(
							("refused display %s: %s"):format(
								tostring(refusal.display),
								refusal.reason
							)
						)
					end
				end
				if result.leader then
					text = text .. ", leader " .. result.leader
				end
				if result.aborted then
					text = text
						.. ", aborted"
						.. (result.deleted and (", %d deleted"):format(result.deleted) or "")
				end
				say(text)
			end,
		})
	end)
end

--- Stop the current run. With cleanup, delete what it spawned.
function Furnish.Abort(cleanup)
	if running and not running.Done() then
		running.Abort(cleanup)
	else
		say("nothing is running")
	end
end
