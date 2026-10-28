-- Pieces laid out in a model scene: one actor a piece, at its own place, tilt and scale about the
-- pieces' centre, under an orbit camera the player turns by dragging and brings nearer with the
-- wheel. No model frame can draw a WMO, so a set's pieces stand without the WMO around them.
--
-- An actor stands in its own scaled space, so a piece's offset is divided by its scale, and a
-- piece's tilt is read as `.gob spawn` takes it; both were judged against the world in game.

local _, Furnish = ...
local Scene = {}
Scene.__index = Scene
Furnish.Scene = Scene

local Client = Furnish.Client
local Transform = Furnish.Transform

--- The client's model scene whose orbit camera a scene takes, as Glimpse's stage does.
local CAMERA = 114

--- How far the camera stands, as a share of the pieces' widest extent, and the least extent it
-- frames, so a lone piece is not drawn filling the scene.
local DISTANCE, NARROWEST = 1.3, 4

--- How a turn of the wheel and a drag move the camera: the share of its distance one step
-- keeps, and the radians one pixel turns.
local ZOOM_STEP, TURN_PER_PIXEL = 0.88, 0.008

--- The nearest and farthest the wheel brings the camera, as shares of the distance framed.
local NEAREST, FARTHEST = 0.15, 4

--- How far the camera tilts up or down, short of looking straight down the vertical.
local STEEPEST = 1.45

local function clamp(value, least, most)
	return math.max(least, math.min(most, value))
end

--- A scene over a ModelScene frame, made from ModelSceneMixinTemplate.
-- @return the scene, which Draw fills
function Scene.New(frame)
	local self = setmetatable({
		frame = frame,
		actors = {},
		yaw = math.rad(225),
		pitch = math.rad(35),
		zoom = 1,
		distance = NARROWEST * DISTANCE,
	}, Scene)
	frame:SetCameraNearClip(0.01)
	frame:SetCameraFarClip(2 ^ 64)
	frame:CreateCameraFromScene(CAMERA)
	frame:EnableMouse(true)
	frame:EnableMouseWheel(true)
	local function turn()
		local x, y = _G.GetCursorPosition()
		local from = self.dragged
		self.yaw = self.yaw - (x - from[1]) * TURN_PER_PIXEL
		self.pitch = clamp(self.pitch + (y - from[2]) * TURN_PER_PIXEL, -STEEPEST, STEEPEST)
		from[1], from[2] = x, y
		self:Aim()
	end
	frame:SetScript("OnMouseDown", function()
		self.dragged = { _G.GetCursorPosition() }
		frame:SetScript("OnUpdate", Client.Guarded(turn))
	end)
	frame:SetScript("OnMouseUp", function()
		self.dragged = nil
		frame:SetScript("OnUpdate", nil)
	end)
	frame:SetScript(
		"OnMouseWheel",
		Client.Guarded(function(_, delta)
			self.zoom = clamp(self.zoom * ZOOM_STEP ^ delta, NEAREST, FARTHEST)
			self:Aim()
		end)
	)
	return self
end

--- Point the camera at the pieces' centre, from the angle and distance the player has left it at.
-- The camera comes from the client's own table of scenes, made again here where it was not, and
-- where the client has none to give the pieces stand unaimed rather than the drawing failing.
function Scene:Aim()
	local camera = self.frame:GetActiveCamera()
	if not camera then
		self.frame:CreateCameraFromScene(CAMERA)
		camera = self.frame:GetActiveCamera()
		if not camera then
			return
		end
	end
	camera:SetMinZoomDistance(0.1)
	camera:SetMaxZoomDistance(self.distance * FARTHEST)
	camera:SetTarget(0, 0, 0)
	camera:SetYaw(self.yaw)
	camera:SetPitch(self.pitch)
	camera:SetZoomDistance(self.distance * self.zoom)
	camera:SnapAllInterpolatedValues()
end

--- Lay the pieces out, in place of whatever the scene showed, and frame them; none empties it.
-- An actor is made only the first time one is needed and kept for the next drawing.
-- @param pieces a list of { file, x, y, z, qx, qy, qz, qw, scale }, as Rows.Pieces gives them
function Scene:Draw(pieces)
	local low, high = { math.huge, math.huge, math.huge }, { -math.huge, -math.huge, -math.huge }
	for _, piece in ipairs(pieces) do
		for axis, value in ipairs({ piece.x, piece.y, piece.z }) do
			low[axis], high[axis] = math.min(low[axis], value), math.max(high[axis], value)
		end
	end
	local cx, cy, cz = (low[1] + high[1]) / 2, (low[2] + high[2]) / 2, (low[3] + high[3]) / 2
	local placed = 0
	for _, piece in ipairs(pieces) do
		local scale = piece.scale
		if scale > 0 then
			placed = placed + 1
			local actor = self.actors[placed]
			if not actor then
				actor = self.frame:CreateActor(nil, "ModelSceneActorTemplate")
				self.actors[placed] = actor
			end
			actor:ClearModel()
			actor:SetUseCenterForOrigin(false, false, false)
			actor:SetPosition(
				(piece.x - cx) / scale,
				(piece.y - cy) / scale,
				(piece.z - cz) / scale
			)
			actor:SetScale(scale)
			local roll, pitch, turn =
				Transform.ToAngles({ x = piece.qx, y = piece.qy, z = piece.qz, w = piece.qw })
			actor:SetRoll(math.rad(roll))
			actor:SetPitch(math.rad(pitch))
			actor:SetYaw(math.rad(turn))
			actor:SetModelByFileID(piece.file)
			actor:Show()
		end
	end
	for index = placed + 1, #self.actors do
		self.actors[index]:ClearModel()
		self.actors[index]:Hide()
	end
	local widest = placed > 0 and math.max(high[1] - low[1], high[2] - low[2], high[3] - low[3])
		or 0
	self.distance = math.max(widest, NARROWEST) * DISTANCE
	self:Aim()
end
