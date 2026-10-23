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

--- The door to the server: function(text, callback(success, messages)), registered once.
-- The callback is guarded, so a fault in it is reported rather than swallowed.
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
		raw = function(text, callback)
			lib.AddonCommands.Send("Furnish", text, callback, false)
		end
	end
	send = function(text, callback)
		raw(text, Client.Guarded(callback))
	end
	return send
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

--- The rows of the client's display table whose model name matches, through its own search.
-- @param name a model name, with or without folder and extension
-- @return a list of { display, file, name }, the name as ModelName spells it
function Client.SearchModels(name)
	local epsilon = _G.C_Epsilon
	if not (epsilon and epsilon.GODI_Search and epsilon.GODI_RetrieveSearch) then
		return {}
	end
	local wanted = Client.ModelName(name)
	local found = {}
	for i = 0, (epsilon.GODI_Search(wanted) or 0) - 1 do
		local row = epsilon.GODI_RetrieveSearch(i)
		if row and Client.ModelName(row.name) == wanted then
			found[#found + 1] = { display = row.displayid, file = row.fileid, name = wanted }
		end
	end
	return found
end
