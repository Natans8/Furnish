-- The door: the core driven from the selection, for a test from /run.
--
--   /run Furnish.Spawn(1)                 spawn set 1 on the selected WMO, pivot-led
--   /run Furnish.Spawn(1, { attach = true })
--   /run Furnish.Abort(true)              stop the run and delete what it spawned
--
-- The house is EpsilonLib's record of the selected object, reduced to what the plan reads.
-- Nothing here parses text or draws anything; a command and a window come later and call
-- the same two functions.

_G.Furnish = _G.Furnish or {}
local Furnish = _G.Furnish

local send
local running

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

--- Spawn a set on the selected WMO.
-- @param index the set's position in the root's MODS, as the listing shows it
-- @param options { attach = bool, nopivot = bool, default = bool }, optional
function Furnish.Spawn(index, options)
	if running and not running.Done() then
		say("a run is still going; Furnish.Abort() stops it")
		return
	end
	local lib = _G.EpsilonLib
	local object = lib and lib.GameObject and lib.GameObject:GetSelected()
	if not object then
		say("select a WMO first")
		return
	end
	if lib.GameObject:IsGroupSelected() then
		say("select the WMO itself, not its group")
		return
	end
	if not object:IsWMO() then
		say("that is not a WMO")
		return
	end
	local house = Furnish.HouseOf(object)
	local plan, reason = Furnish.Plan.Build(house, index, options)
	if not plan then
		say(reason)
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
						("refused display %s: %s"):format(tostring(refusal.display), refusal.reason)
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
end

--- Stop the current run. With cleanup, delete what it spawned.
function Furnish.Abort(cleanup)
	if running and not running.Done() then
		running.Abort(cleanup)
	else
		say("nothing is running")
	end
end
