-- Pieces laid out in a model scene: one actor a piece, at its own place, tilt and scale about the
-- pieces' centre, under an orbit camera the player turns by dragging and brings nearer with the
-- wheel. No model frame can draw a WMO, so a set's pieces stand without the WMO around them.
--
-- An actor stands in its own scaled space, so a piece's offset is divided by its scale, and a
-- piece's tilt is read as `.gob spawn` takes it; both were judged against the world in game.
--
-- The camera frames the sphere around every loaded model's box: a sphere looks the same from every
-- side, so no turn takes a piece out of the frame, and each model that loads widens the frame until
-- the player zooms or pans. A right or middle drag pans, as the game's own dressing room moves its
-- model, the pieces following the pointer, and the wheel zooms toward the point under the pointer.
-- The client's own scene script moves the camera every frame; the scene only says where it looks
-- from.

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

--- The nearest the camera draws, and so the nearest the wheel brings it to what it looks at.
local NEAR = 0.01

--- The farthest the wheel takes the camera, as a share of the distance framed, short of the
-- pieces shrinking to a point.
local FARTHEST = 4

--- What each button drags: the left turns the camera, the right and the middle pan it.
local DRAGS = { LeftButton = "Turn", RightButton = "Pan", MiddleButton = "Pan" }

--- How fast a held rotate button turns the camera, in radians a second: half a turn a second, as
-- the game's own model frames turn while theirs is held.
local SPIN = math.pi

--- The angle a drawing opens at: from a corner, looking down.
local YAW, PITCH = math.rad(225), math.rad(35)

--- How far the camera tilts up or down, short of looking straight down the vertical.
local STEEPEST = 1.45

--- The kit that outlines the piece under the pointer: the outline Gilded Claws draws, judged the
-- same as the glow `.gob select` puts on a gob.
local HOVER_KIT = 90111

--- The corners of a box, as which of its two ends each axis takes.
local CORNERS = {}
for i = 0, 7 do
	CORNERS[#CORNERS + 1] = { i % 2 == 1, math.floor(i / 2) % 2 == 1, math.floor(i / 4) % 2 == 1 }
end

local function clamp(value, least, most)
	return math.max(least, math.min(most, value))
end

--- Where the client's orbit camera looks, from its turn and tilt.
local function forwardOf(yaw, pitch)
	return math.cos(pitch) * math.cos(yaw), math.cos(pitch) * math.sin(yaw), -math.sin(pitch)
end

--- How far in front of the camera a ray enters a box it starts outside of, as a depth along the
-- view; nil where it misses the box or starts inside it.
-- @param ray a direction whose share along the view is one, so its distances are depths
-- @param box { low x, low y, low z, high x, high y, high z }
local function enters(origin, ray, box)
	local near, far = -math.huge, math.huge
	for axis = 1, 3 do
		local from, along, low, high = origin[axis], ray[axis], box[axis], box[axis + 3]
		if along == 0 then
			if from < low or from > high then
				return nil
			end
		else
			local a, b = (low - from) / along, (high - from) / along
			if a > b then
				a, b = b, a
			end
			near, far = math.max(near, a), math.min(far, b)
			if near > far then
				return nil
			end
		end
	end
	if near <= NEAR then
		return nil
	end
	return near
end

--- A scene over a ModelScene frame, made from ModelSceneMixinTemplate.
-- @param onLoad called as the models load, with how many have, how many there are, and the
--   seconds since the drawing began
-- @param onHover called when the piece under the pointer changes, with that piece as Draw was
--   given it, or nil where there is none
-- @return the scene, which Draw fills
function Scene.New(frame, onLoad, onHover)
	local self = setmetatable({
		frame = frame,
		actors = {},
		boxes = {},
		onLoad = onLoad,
		onHover = onHover,
		yaw = YAW,
		pitch = PITCH,
		zoom = 1,
		distance = 1,
		centre = { 0, 0, 0 },
	}, Scene)
	frame:SetCameraNearClip(NEAR)
	frame:SetCameraFarClip(2 ^ 64)
	frame:EnableMouse(true)
	frame:EnableMouseWheel(true)
	-- The presses and the wheel are taken over from the scene's own script, which turns the camera
	-- its own way; its per-frame script stays, since it is what moves the camera, and a drag is
	-- read beside it.
	frame:SetScript("OnMouseDown", function(_, button)
		if DRAGS[button] then
			self:Drag(DRAGS[button], button, true)
		end
	end)
	frame:SetScript("OnMouseUp", function()
		self.dragged = nil
	end)
	frame:SetScript(
		"OnMouseWheel",
		Client.Guarded(function(_, delta)
			self:Zoom(delta)
			self:Aim()
		end)
	)
	frame:HookScript(
		"OnUpdate",
		Client.Guarded(function(_, elapsed)
			self:Tick(elapsed)
		end)
	)
	frame:HookScript("OnEnter", function()
		self.pointed = true
	end)
	frame:HookScript(
		"OnLeave",
		Client.Guarded(function()
			self.pointed = false
			self:Hover(nil)
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
	camera:SetMinZoomDistance(NEAR)
	camera:SetMaxZoomDistance(self.distance * FARTHEST)
	camera:SetTarget(self.centre[1], self.centre[2], self.centre[3])
	camera:SetYaw(self.yaw)
	camera:SetPitch(self.pitch)
	camera:SetZoomDistance(self.distance * self.zoom)
	camera:SnapAllInterpolatedValues()
	camera:SynchronizeCamera()
	-- What lies under a pointer that has not moved may have.
	self.looked = nil
end

--- Stand back far enough that the sphere around everything loaded fits the narrower of the
-- frame's two fields of view, aimed at its centre. Nothing loaded leaves the camera as it is.
-- @return true where it framed
function Scene:Fit()
	local low, high = self.low, self.high
	if not low then
		return false
	end
	local dx, dy, dz = high[1] - low[1], high[2] - low[2], high[3] - low[3]
	local radius = math.sqrt(dx * dx + dy * dy + dz * dz) / 2
	if radius <= 0 then
		return false
	end
	-- The field of view is read as the vertical one. A frame not yet laid out measures nothing, and
	-- is taken as square until it does.
	local tall = math.tan(self.frame:GetCameraFieldOfView() / 2)
	local width, height = self.frame:GetWidth(), self.frame:GetHeight()
	local wide = (width > 0 and height > 0) and tall * width / height or tall
	self.centre = { (low[1] + high[1]) / 2, (low[2] + high[2]) / 2, (low[3] + high[3]) / 2 }
	self.distance = radius / math.sin(math.atan(math.min(tall, wide)))
	self:Aim()
	return true
end

--- Put the camera back as a drawing opens it: the opening angle, framing everything loaded.
function Scene:Reset()
	self.yaw, self.pitch, self.zoom, self.moved = YAW, PITCH, 1, false
	if not self:Fit() then
		self:Aim()
	end
end

--- Take in a loaded actor's box, turned, scaled and placed as its piece stands: kept, square to the
-- scene's axes, for finding the piece under the pointer, and taken into the bounds framed.
function Scene:Hold(actor)
	local x1, y1, z1, x2, y2, z2 = actor:GetActiveBoundingBox()
	if not (x1 and y1 and z1 and x2 and y2 and z2) then
		return
	end
	local box = { math.huge, math.huge, math.huge, -math.huge, -math.huge, -math.huge }
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
			box[axis], box[axis + 3] = math.min(box[axis], value), math.max(box[axis + 3], value)
		end
	end
	box.actor = actor
	self.boxes[#self.boxes + 1] = box
	local low = self.low or { math.huge, math.huge, math.huge }
	local high = self.high or { -math.huge, -math.huge, -math.huge }
	for axis = 1, 3 do
		low[axis], high[axis] = math.min(low[axis], box[axis]), math.max(high[axis], box[axis + 3])
	end
	self.low, self.high = low, high
end

--- Turn the camera about what it looks at, by how far the pointer moved, in screen pixels.
function Scene:Turn(dx, dy)
	self.yaw = self.yaw - dx * TURN_PER_PIXEL
	self.pitch = clamp(self.pitch + dy * TURN_PER_PIXEL, -STEEPEST, STEEPEST)
end

--- The view's right and up in the scene's axes, from the camera's turn and tilt: it looks along
-- the client's orbit camera's forward, right is level across that, and up is square to both.
-- Worked out here rather than read from the scene's GetCameraRight, which Blizzard's own panning
-- adds where the model should follow the pointer, so as pointing to the view's left.
function Scene:Axes()
	local yaw = self.yaw
	local fx, fy, fz = forwardOf(yaw, self.pitch)
	local rx, ry = math.sin(yaw), -math.cos(yaw)
	return rx, ry, 0, ry * fz, -rx * fz, rx * fy - ry * fx
end

--- Move what the camera looks at across the view, so the pieces at its depth follow the pointer:
-- a pixel is the share of the view's height it spans, at the camera's distance.
function Scene:Pan(dx, dy)
	local frame = self.frame
	local tall = 2 * self.distance * self.zoom * math.tan(frame:GetCameraFieldOfView() / 2)
	local step = tall / (frame:GetHeight() * frame:GetEffectiveScale())
	local rx, ry, rz, ux, uy, uz = self:Axes()
	local centre = self.centre
	centre[1] = centre[1] - (rx * dx + ux * dy) * step
	centre[2] = centre[2] - (ry * dx + uy * dy) * step
	centre[3] = centre[3] - (rz * dx + uz * dy) * step
	self.moved = true
end

--- Bring the camera nearer or farther by steps of the wheel, toward the point under the pointer,
-- which stays under it: what the camera looks at moves toward that point by the share of the
-- distance the step takes off. A button zooms straight in, its pointer being on the button.
-- @param straight true to zoom toward the middle of the view, whatever is under the pointer
function Scene:Zoom(steps, straight)
	if not straight then
		self:Grab()
	end
	local zoom = clamp(self.zoom * ZOOM_STEP ^ steps, NEAR / self.distance, FARTHEST)
	if not straight then
		local share = 1 - zoom / self.zoom
		local x, y = _G.GetCursorPosition()
		local cx, cy = self.frame:GetCenter()
		local scale = self.frame:GetEffectiveScale()
		self:Pan(-(x - cx * scale) * share, -(y - cy * scale) * share)
	end
	self.zoom = zoom
	self.moved = true
end

--- Start dragging with a mouse button held: turning the camera, or panning it. A pan pressed on
-- the scene grabs the piece under the pointer, which then follows the pointer.
-- @param action "Turn" or "Pan"
-- @param button the mouse button held, whose release ends the drag
-- @param pointed true where the press was on the scene itself, rather than on a button
function Scene:Drag(action, button, pointed)
	if action == "Pan" and pointed then
		self:Grab()
	end
	local x, y = _G.GetCursorPosition()
	self.dragged = { x = x, y = y, button = button, action = action }
end

--- The nearest loaded piece under the pointer, by its box: the box, which names its actor, how
-- deep along the view it lies, and where the camera stands. Nil where the pointer is on none.
function Scene:Pick()
	local frame = self.frame
	local scale = frame:GetEffectiveScale()
	local half = frame:GetHeight() * scale / 2
	if not self.boxes[1] or half <= 0 then
		return nil
	end
	local x, y = _G.GetCursorPosition()
	local cx, cy = frame:GetCenter()
	local spread = math.tan(frame:GetCameraFieldOfView() / 2) / half
	local across, upward = (x - cx * scale) * spread, (y - cy * scale) * spread
	local fx, fy, fz = forwardOf(self.yaw, self.pitch)
	local rx, ry, rz, ux, uy, uz = self:Axes()
	local distance, centre = self.distance * self.zoom, self.centre
	local origin =
		{ centre[1] - fx * distance, centre[2] - fy * distance, centre[3] - fz * distance }
	local ray = {
		fx + rx * across + ux * upward,
		fy + ry * across + uy * upward,
		fz + rz * across + uz * upward,
	}
	local nearest, picked
	for _, box in ipairs(self.boxes) do
		local depth = enters(origin, ray, box)
		if depth and (not nearest or depth < nearest) then
			nearest, picked = depth, box
		end
	end
	return picked, nearest, origin
end

--- Move what the camera turns about and zooms toward to the nearest piece under the pointer, at
-- that piece's depth, the camera staying where it stands: zooming and panning then go at the pace
-- of what is pointed at rather than of the middle of the set. Nothing there leaves it be.
function Scene:Grab()
	local picked, depth, origin = self:Pick()
	if picked then
		local fx, fy, fz = forwardOf(self.yaw, self.pitch)
		self.centre = { origin[1] + fx * depth, origin[2] + fy * depth, origin[3] + fz * depth }
		self.zoom = depth / self.distance
	end
end

--- Outline the piece under the pointer and say which it is, taking the outline off the last.
-- @param actor the piece's actor, or nil for none
function Scene:Hover(actor)
	if actor == self.hovered then
		return
	end
	if self.hovered then
		self.hovered:SetSpellVisualKit(0)
	end
	self.hovered = actor
	if actor then
		actor:SetSpellVisualKit(HOVER_KIT, false)
	end
	if self.onHover then
		self.onHover(actor and actor.piece)
	end
end

--- Turn the camera on its own while the left mouse button stays down, as a held rotate button
-- does: 1 the way a drag to the left turns it, -1 the other way.
function Scene:Spin(direction)
	self.spin = direction
end

--- What a frame does: a drag turns or pans the camera, a held rotate button turns it, and what
-- loaded since the last frame is framed and told, once for however many loaded.
-- @param elapsed the seconds since the last frame
function Scene:Tick(elapsed)
	local dragged = self.dragged
	if dragged then
		-- A press let go off the scene is not heard by it, so the button is read as it is.
		if not _G.IsMouseButtonDown(dragged.button) then
			self.dragged = nil
		else
			local x, y = _G.GetCursorPosition()
			self[dragged.action](self, x - dragged.x, y - dragged.y)
			dragged.x, dragged.y = x, y
			self:Aim()
		end
	end
	if self.spin then
		if not _G.IsMouseButtonDown("LeftButton") then
			self.spin = nil
		else
			self.yaw = self.yaw + self.spin * SPIN * (elapsed or 0)
			self:Aim()
		end
	end
	-- The piece under the pointer is looked for again when the pointer or the camera has moved,
	-- and not while a drag holds the view.
	if self.pointed and not self.dragged then
		local x, y = _G.GetCursorPosition()
		local looked = self.looked
		if not (looked and looked[1] == x and looked[2] == y) then
			self.looked = { x, y }
			local box = self:Pick()
			self:Hover(box and box.actor)
		end
	end
	if self.arrived then
		self.arrived = false
		if not self.moved then
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
	self.drawing, self.low, self.high, self.zoom, self.moved = drawing, nil, nil, 1, false
	self.boxes = {}
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
			actor.piece = { file = piece.file, offset = offset, turn = turn, scale = scale }
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
	self:Hover(nil)
	self.looked = nil
	self.total = placed
	self:Tell()
end
