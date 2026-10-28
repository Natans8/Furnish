-- Pieces laid out in a model scene: one actor a piece, at its own place, tilt and scale about the
-- pieces' centre, under an orbit camera the player turns by dragging and brings nearer with the
-- wheel. No model frame can draw a WMO, so a set's pieces stand without the WMO around them.
--
-- An actor stands in its own scaled space, so a piece's offset is divided by its scale, and a
-- piece's tilt is read as `.gob spawn` takes it; both were judged against the world in game.
--
-- The camera frames the sphere around every loaded model's box: a sphere looks the same from every
-- side, so no turn takes a piece out of the frame, and each model that loads widens the frame until
-- the player zooms. The client's own scene script moves the camera every frame; the scene only says
-- where it looks from.

local _, Furnish = ...
local Scene = {}
Scene.__index = Scene
Furnish.Scene = Scene

local Client = Furnish.Client
local Transform = Furnish.Transform

--- The client's model scene whose orbit camera a scene takes, as Glimpse's stage does.
local CAMERA = 114

--- How a turn of the wheel and a drag move the camera: the share of its distance one step
-- keeps, and the radians one pixel turns.
local ZOOM_STEP, TURN_PER_PIXEL = 0.88, 0.008

--- The nearest and farthest the wheel brings the camera, as shares of the distance framed.
local NEAREST, FARTHEST = 0.15, 4

--- How far the camera tilts up or down, short of looking straight down the vertical.
local STEEPEST = 1.45

--- The corners of a box, as which of its two ends each axis takes.
local CORNERS = {}
for i = 0, 7 do
	CORNERS[#CORNERS + 1] = { i % 2 == 1, math.floor(i / 2) % 2 == 1, math.floor(i / 4) % 2 == 1 }
end

local function clamp(value, least, most)
	return math.max(least, math.min(most, value))
end

--- A scene over a ModelScene frame, made from ModelSceneMixinTemplate.
-- @param onLoad called as the models load, with how many have, how many there are, and the
--   seconds since the drawing began
-- @return the scene, which Draw fills
function Scene.New(frame, onLoad)
	local self = setmetatable({
		frame = frame,
		actors = {},
		onLoad = onLoad,
		yaw = math.rad(225),
		pitch = math.rad(35),
		zoom = 1,
		distance = 1,
		centre = { 0, 0, 0 },
	}, Scene)
	frame:SetCameraNearClip(0.01)
	frame:SetCameraFarClip(2 ^ 64)
	frame:EnableMouse(true)
	frame:EnableMouseWheel(true)
	-- The presses and the wheel are taken over from the scene's own script, which turns the camera
	-- its own way; its per-frame script stays, since it is what moves the camera, and a drag is
	-- read beside it.
	frame:SetScript("OnMouseDown", function(_, button)
		if button == "LeftButton" then
			self.dragged = { _G.GetCursorPosition() }
		end
	end)
	frame:SetScript("OnMouseUp", function()
		self.dragged = nil
	end)
	frame:SetScript(
		"OnMouseWheel",
		Client.Guarded(function(_, delta)
			self.zoom = clamp(self.zoom * ZOOM_STEP ^ delta, NEAREST, FARTHEST)
			self.zoomed = true
			self:Aim()
		end)
	)
	frame:HookScript(
		"OnUpdate",
		Client.Guarded(function()
			self:Tick()
		end)
	)
	return self
end

--- The camera the scene looks through, made from the client's scene the first time, without the
-- drift that scene carries: it moves its aim and turns as it zooms. Nil where the client has none.
function Scene:Camera()
	local camera = self.frame:GetActiveCamera()
	if not camera then
		self.frame:CreateCameraFromScene(CAMERA)
		camera = self.frame:GetActiveCamera()
	end
	if camera and camera ~= self.camera then
		self.camera = camera
		camera:SetTargetSpline(nil)
		camera:SetOrientationSpline(nil)
		camera:SetZoomSpline(nil)
	end
	return camera
end

--- Point the camera at the framed centre, from the angle and distance the player has left it at.
function Scene:Aim()
	local camera = self:Camera()
	if not camera then
		return
	end
	camera:SetMinZoomDistance(self.distance * NEAREST)
	camera:SetMaxZoomDistance(self.distance * FARTHEST)
	camera:SetTarget(self.centre[1], self.centre[2], self.centre[3])
	camera:SetYaw(self.yaw)
	camera:SetPitch(self.pitch)
	camera:SetZoomDistance(self.distance * self.zoom)
	camera:SnapAllInterpolatedValues()
	camera:SynchronizeCamera()
end

--- Stand back far enough that the sphere around everything loaded fits the narrower of the
-- frame's two fields of view, aimed at its centre. Nothing loaded leaves the camera as it is.
function Scene:Fit()
	local low, high = self.low, self.high
	if not low then
		return
	end
	local dx, dy, dz = high[1] - low[1], high[2] - low[2], high[3] - low[3]
	local radius = math.sqrt(dx * dx + dy * dy + dz * dz) / 2
	if radius <= 0 then
		return
	end
	-- The field of view is read as the vertical one. A frame not yet laid out measures nothing, and
	-- is taken as square until it does.
	local tall = math.tan(self.frame:GetCameraFieldOfView() / 2)
	local width, height = self.frame:GetWidth(), self.frame:GetHeight()
	local wide = (width > 0 and height > 0) and tall * width / height or tall
	self.centre = { (low[1] + high[1]) / 2, (low[2] + high[2]) / 2, (low[3] + high[3]) / 2 }
	self.distance = radius / math.sin(math.atan(math.min(tall, wide)))
	self:Aim()
end

--- Take in a loaded actor's box, turned, scaled and placed as its piece stands.
function Scene:Hold(actor)
	local x1, y1, z1, x2, y2, z2 = actor:GetActiveBoundingBox()
	if not (x1 and y1 and z1 and x2 and y2 and z2) then
		return
	end
	local low = self.low or { math.huge, math.huge, math.huge }
	local high = self.high or { -math.huge, -math.huge, -math.huge }
	local piece, scale = actor.piece, actor.piece.scale
	for _, corner in ipairs(CORNERS) do
		local turned = Transform.Rotate(piece.turn, {
			x = (corner[1] and x2 or x1) * scale,
			y = (corner[2] and y2 or y1) * scale,
			z = (corner[3] and z2 or z1) * scale,
		})
		for axis, value in ipairs({
			piece.offset[1] + turned.x,
			piece.offset[2] + turned.y,
			piece.offset[3] + turned.z,
		}) do
			low[axis], high[axis] = math.min(low[axis], value), math.max(high[axis], value)
		end
	end
	self.low, self.high = low, high
end

--- What a frame does: a drag turns the camera, and what loaded since the last frame is framed and
-- told, once for however many loaded.
function Scene:Tick()
	if self.dragged then
		-- A press let go off the scene is not heard by it, so the button is read as it is.
		if not _G.IsMouseButtonDown("LeftButton") then
			self.dragged = nil
		else
			local x, y = _G.GetCursorPosition()
			local from = self.dragged
			self.yaw = self.yaw - (x - from[1]) * TURN_PER_PIXEL
			self.pitch = clamp(self.pitch + (y - from[2]) * TURN_PER_PIXEL, -STEEPEST, STEEPEST)
			from[1], from[2] = x, y
			self:Aim()
		end
	end
	if self.arrived then
		self.arrived = false
		if not self.zoomed then
			self:Fit()
		end
		self:Tell()
	end
end

--- Say how far the drawing has loaded, and once it has, how long it took.
function Scene:Tell()
	if self.loaded == self.total and not self.took then
		self.took = Client.Now() - self.started
	end
	if self.onLoad then
		self.onLoad(self.loaded, self.total, self.took or Client.Now() - self.started)
	end
end

--- Lay the pieces out, in place of whatever the scene showed, and frame them as their models load;
-- none empties it. An actor is made only the first time one is needed and kept for the next
-- drawing, and a load from an earlier drawing counts for nothing.
-- @param pieces a list of { file, x, y, z, qx, qy, qz, qw, scale }, as Rows.Pieces gives them
function Scene:Draw(pieces)
	local low, high = { math.huge, math.huge, math.huge }, { -math.huge, -math.huge, -math.huge }
	for _, piece in ipairs(pieces) do
		for axis, value in ipairs({ piece.x, piece.y, piece.z }) do
			low[axis], high[axis] = math.min(low[axis], value), math.max(high[axis], value)
		end
	end
	local cx, cy, cz = (low[1] + high[1]) / 2, (low[2] + high[2]) / 2, (low[3] + high[3]) / 2
	local drawing = (self.drawing or 0) + 1
	self.drawing, self.low, self.high, self.zoom, self.zoomed = drawing, nil, nil, 1, false
	self.loaded, self.took, self.started = 0, nil, Client.Now()
	local function loaded(actor)
		if self.drawing == drawing and actor.drawing ~= drawing then
			actor.drawing = drawing
			self.loaded = self.loaded + 1
			self:Hold(actor)
			self.arrived = true
		end
	end
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
			local offset = { piece.x - cx, piece.y - cy, piece.z - cz }
			local turn = { x = piece.qx, y = piece.qy, z = piece.qz, w = piece.qw }
			actor.piece = { offset = offset, turn = turn, scale = scale }
			actor:ClearModel()
			actor:SetUseCenterForOrigin(false, false, false)
			actor:SetPosition(offset[1] / scale, offset[2] / scale, offset[3] / scale)
			actor:SetScale(scale)
			local roll, pitch, yaw = Transform.ToAngles(turn)
			actor:SetRoll(math.rad(roll))
			actor:SetPitch(math.rad(pitch))
			actor:SetYaw(math.rad(yaw))
			actor:SetOnModelLoadedCallback(Client.Guarded(loaded))
			actor:SetModelByFileID(piece.file)
			actor:Show()
		end
	end
	for index = placed + 1, #self.actors do
		self.actors[index]:ClearModel()
		self.actors[index]:Hide()
	end
	self.total = placed
	self:Tell()
end
