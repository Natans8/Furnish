-- The client adapter: the one file that names EpsilonLib and C_Epsilon.
--
-- Everything above reaches the game through these few functions, so the rest of the addon
-- runs in a plain Lua with this file's globals stood in. Nothing here decides anything about
-- furnishing; it only sends, reads and reshapes.

_G.Furnish = _G.Furnish or {}
local Furnish = _G.Furnish
local Client = {}
Furnish.Client = Client

local send

--- A function whose fault reaches the client's error handler, traceback and all, instead
-- of dying in silence. Every boundary a command reply or a timer crosses is wrapped, since
-- AddonCommands swallows an error thrown inside its callback. The handler is the client's
-- own, so BugSack and the error frame show it the way they show any addon's.
function Client.Guarded(fn)
	if fn == nil then
		return nil
	end
	return function(...)
		local handler = _G.geterrorhandler and _G.geterrorhandler() or print
		local count, arguments = select("#", ...), { ... }
		return select(
			2,
			xpcall(function()
				return fn(unpack(arguments, 1, count))
			end, handler)
		)
	end
end

--- The door to the server: function(text, callback(success, messages), shown), registered
-- once. The server's reply is kept from chat, refusals too, since every caller reports
-- what it asked for in its own words; shown true lets the player see it as if they had
-- typed the command. The callback is optional and guarded, so a fault in it is reported
-- rather than swallowed.
-- @return the function, or nil and the reason
function Client.Send()
	if send then
		return send
	end
	local lib = _G.EpsilonLib
	if not (lib and lib.AddonCommands) then
		return nil, "EpsilonLib is not loaded, and Furnish sends every command through it"
	end
	local ok, registered = pcall(lib.AddonCommands.Register, "Furnish", false)
	local raw
	if ok and registered then
		raw = registered
	else
		raw = function(text, callback, shown)
			lib.AddonCommands.Send("Furnish", text, callback, shown)
		end
	end
	send = function(text, callback, shown)
		raw(text, Client.Guarded(callback), shown or nil)
	end
	return send
end

--- Whether the player may spawn objects in this phase, its members, officers and owner. A
-- refusal is said in chat in Epsilon's own words, as its other building tools say it. Where
-- EpsilonLib cannot answer, the server is left to decide.
function Client.CanSpawn()
	local lib = _G.EpsilonLib
	local check = lib and lib.GameObject and lib.GameObject.CanSpawn
	if not check then
		return true
	end
	-- Any true answer is permission, as EpsilonLib reads it: Epsilon's calls may answer 1.
	return check(true) and true or false
end

--- The selected object's record, or nil; false for a group selection.
function Client.Selected()
	local lib = _G.EpsilonLib
	if not (lib and lib.GameObject) then
		return nil
	end
	if lib.GameObject:IsGroupSelected() then
		return false
	end
	return lib.GameObject:GetSelected()
end

--- Call fn with an object's record once EpsilonLib holds it, which is once the server has
-- pushed it for the selection. A record already selected is handed over at once.
-- @param guid the object's GUID
-- @param fn function(record), called once
-- @return a function that stops waiting; or nil and the reason
function Client.AwaitRecord(guid, fn)
	local lib = _G.EpsilonLib
	local events = lib and lib.EventManager
	if not events then
		return nil, "EpsilonLib is not loaded, and Furnish reads every object through it"
	end
	local wanted, reference = tostring(guid), nil
	local function stop()
		if reference then
			events:Remove(reference, "EPSILON_OBJ_UPDATE")
			reference = nil
		end
	end
	local function offer(record)
		if reference and record and tostring(record.guid) == wanted then
			stop()
			fn(record)
		end
	end
	-- EpsilonLib calls a listener as listener(nil, event, ...), its own frame withheld.
	local _
	_, reference = events:Register(
		"EPSILON_OBJ_UPDATE",
		Client.Guarded(function(_, _, _, record)
			offer(record)
		end)
	)
	offer(Client.Selected() or nil)
	return stop
end

local systemFrame, systemListener

--- Hear every system line the server prints: fn(line) for each, until the function returned
-- is called. One listener at a time, since one import waits at a time.
function Client.OnSystemLine(fn)
	if not systemFrame then
		systemFrame = _G.CreateFrame("Frame")
		systemFrame:RegisterEvent("CHAT_MSG_SYSTEM")
		systemFrame:SetScript(
			"OnEvent",
			Client.Guarded(function(_, _, line)
				if systemListener then
					systemListener(line)
				end
			end)
		)
	end
	systemListener = fn
	return function()
		if systemListener == fn then
			systemListener = nil
		end
	end
end

--- Restore the saved copy of a settings table over its defaults, then make the live table
-- the saved one, so the client writes whatever a surface changes at logout. A saved value
-- is taken only for a key the defaults declare and only when its type agrees, so a stale
-- or hand-edited file cannot put a string where a number goes.
-- @param settings the defaults, which become the live values
-- @param name the saved variable's global name, as the toc declares it
function Client.Restore(settings, name)
	local saved = _G[name]
	if type(saved) == "table" then
		for key, default in pairs(settings) do
			local value = saved[key]
			if type(value) == type(default) then
				settings[key] = value
			end
		end
	end
	_G[name] = settings
end

--- Call fn once this addon has loaded, which is when its saved variables are readable.
function Client.OnLoaded(fn)
	local frame = _G.CreateFrame("Frame")
	frame:RegisterEvent("ADDON_LOADED")
	frame:SetScript("OnEvent", function(_, _, addon)
		if addon == "Furnish" then
			frame:UnregisterEvent("ADDON_LOADED")
			Client.Guarded(fn)()
		end
	end)
end

Client.OnLoaded(function()
	Client.Restore(Furnish.Settings, "FurnishSettings")
end)

--- The player's position as the server places by, and the map: x, y, z, map. Blizzard's
-- UnitPosition answers nothing useful on a phase, which is an instanced map.
function Client.Position()
	return _G.C_Epsilon.GetPosition()
end

--- The player's facing in degrees, 0 north and growing toward west, as a spawn's turn.
function Client.Facing()
	return math.deg(_G.GetPlayerFacing() or 0)
end

--- The model name a record carries, as the data spells it: the file's base name, lower
-- case, without the folder, the extension or the carriage return the client appends.
function Client.ModelName(name)
	name = tostring(name or ""):gsub("[\r\n]", ""):lower()
	name = name:match("([^/\\]+)$") or name
	return (name:gsub("%.wmo$", ""))
end
