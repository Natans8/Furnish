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
--
-- A click chooses the piece under the pointer, a shift-click chooses it too, and a shift-drag
-- chooses every piece whose middle its band holds, as it is drawn; what is chosen stays lit as the
-- pointed piece is, and the scene says when that changes. Chosen lists them as they would spawn,
-- the lowest-standing piece first, so that it leads the group they form, unless a ctrl-click has
-- made another lead.

local _, Furnish = ...
local Scene = {}
Scene.__index = Scene
Furnish.Scene = Scene

local Client = Furnish.Client
local Transform = Furnish.Transform

--- The client's model scene whose orbit camera a scene takes, as Glimpse's stage does.
local CAMERA = 114

--- How a turn of the wheel and a drag move the camera: the share of its distance one step
-- keeps, six steps halving it, and the radians one pixel turns, a full turn in about eight
-- hundred pixels.
local ZOOM_STEP, TURN_PER_PIXEL = 0.88, 0.008

--- The nearest the camera draws, and so the nearest the wheel brings it to what it looks at.
local NEAR = 0.01

--- The farthest the wheel takes the camera, as a share of the distance framed: four times it,
-- where the sphere framed is a quarter of the view, short of the pieces shrinking to a point.
local FARTHEST = 4

--- How far a press may wander, in the interface's own units, and still be a click rather than a
-- drag: the system's own drag threshold.
local CLICK_SLOP = 4

--- What each button drags: the left turns the camera, the right and the middle pan it.
local DRAGS = { LeftButton = "Turn", RightButton = "Pan", MiddleButton = "Pan" }

--- How the band a shift-drag draws looks: a thin edge over a faint fill, both in the interface's
-- own gold.
local BAND = {
	bgFile = "Interface/Buttons/WHITE8x8",
	edgeFile = "Interface/Buttons/WHITE8x8",
	edgeSize = 1,
}
local BAND_FILL, BAND_EDGE = { 1, 0.82, 0, 0.1 }, { 1, 0.82, 0, 0.7 }

--- How many frame levels a frame drawn over the models stands above the scene, which draws its
-- models over anything level with it.
Scene.ABOVE = 10

--- How fast a held rotate button turns the camera, in radians a second: half a turn a second, as
-- the game's own model frames turn while theirs is held.
local SPIN = math.pi

--- The angle a drawing opens at: from a corner, looking down at thirty-five degrees, which shows
-- a room's floor and its walls at once.
local YAW, PITCH = math.rad(225), math.rad(35)

--- How far the camera tilts up or down, in radians: seven degrees short of straight down the
-- vertical, where the orbit would have nothing to turn about.
local STEEPEST = 1.45

--- How far off the view's axis, as a share of the depth, the points stand that the scene's own
-- projection is asked about to measure it.
local LENS_STEP = 0.1

--- The kit that lights the piece under the pointer and the pieces chosen: a steady pale yellow
-- glow along the edges, the nearest a scene draws to the outline `.gob select` puts on a gob,
-- which a scene does not draw.
local GLOW_KIT = 87979

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

--- One axis of a ray against the slab a box takes on it: how far along the ray it is inside,
-- narrowed from the entry and exit so far; nil where the ray misses the slab.
local function slab(from, along, least, most, near, far)
	if along == 0 then
		if from < least or from > most then
			return nil
		end
		return near, far
	end
	local a, b = (least - from) / along, (most - from) / along
	if a > b then
		a, b = b, a
	end
	near, far = math.max(near, a), math.min(far, b)
	if near > far then
		return nil
	end
	return near, far
end

--- Where a ray meets a box square to its axes: how far along it enters and leaves, the entry
-- negative where it starts inside; nil where it misses. Nothing is allocated, since this runs
-- once a box every time the pointer moves.
-- @param ox, oy, oz where the ray starts
-- @param dx, dy, dz its direction, whose share along the view is one, so its distances are depths
-- @param low the box's least corner, { x, y, z }
-- @param high the box's greatest corner
local function meets(ox, oy, oz, dx, dy, dz, low, high)
	local near, far = slab(ox, dx, low[1], high[1], -math.huge, math.huge)
	if near then
		near, far = slab(oy, dy, low[2], high[2], near, far)
	end
	if near then
		near, far = slab(oz, dz, low[3], high[3], near, far)
	end
	return near, far
end

--- How far the pointer has moved from a press, in the interface's own units.
local function wandered(frame, pressed, x, y)
	return math.sqrt((x - pressed.x) ^ 2 + (y - pressed.y) ^ 2) / frame:GetEffectiveScale()
end

--- A scene over a ModelScene frame, made from ModelSceneMixinTemplate.
-- @param onLoad called as the models load, with how many have, how many there are, and the
--   seconds since the drawing began
-- @param onHover called when the piece under the pointer changes, with that piece as Draw was
--   given it, or nil where there is none
-- @param onChoose called when the pieces chosen change, which Chosen then lists
-- @return the scene, which Draw fills
function Scene.New(frame, onLoad, onHover, onChoose)
	local self = setmetatable({
		frame = frame,
		actors = {},
		boxes = {},
		chosen = {},
		onLoad = onLoad,
		onHover = onHover,
		onChoose = onChoose,
		yaw = YAW,
		pitch = PITCH,
		zoom = 1,
		distance = 1,
		centre = { 0, 0, 0 },
	}, Scene)
	-- As far as the client draws, so no far wall of a WMO's worth of pieces is cut off.
	frame:SetCameraNearClip(NEAR)
	frame:SetCameraFarClip(2 ^ 64)
	frame:EnableMouse(true)
	frame:EnableMouseWheel(true)
	-- The band a shift-drag draws, over the models, as the controls stand over them.
	local band = _G.CreateFrame("Frame", nil, frame, "BackdropTemplate")
	band:SetFrameLevel(frame:GetFrameLevel() + Scene.ABOVE)
	band:SetBackdrop(BAND)
	band:SetBackdropColor(unpack(BAND_FILL))
	band:SetBackdropBorderColor(unpack(BAND_EDGE))
	band:Hide()
	self.band = band
	-- The presses and the wheel are taken over from the scene's own script, which turns the camera
	-- its own way; its per-frame script stays, since it is what moves the camera, and a drag is
	-- read beside it.
	frame:SetScript("OnMouseDown", function(_, button)
		if button == "LeftButton" then
			local x, y = _G.GetCursorPosition()
			local more = _G.IsShiftKeyDown()
			self.pressed = { x = x, y = y, more = more, lead = _G.IsControlKeyDown() }
			-- With shift held, the press draws a band rather than turning the camera, and what
			-- is chosen as it is pressed stays chosen under the band.
			if more then
				local kept = {}
				for index, actor in ipairs(self.chosen) do
					kept[index] = actor
				end
				self.pressed.kept = kept
				return
			end
		end
		if DRAGS[button] then
			self:Drag(DRAGS[button], button, true)
		end
	end)
	frame:SetScript(
		"OnMouseUp",
		Client.Guarded(function(_, button)
			self:Release(button)
		end)
	)
	frame:SetScript(
		"OnMouseWheel",
		Client.Guarded(function(_, delta)
			self:Zoom(delta)
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
	frame:HookScript(
		"OnHide",
		Client.Guarded(function()
			self:Rest()
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
	-- How far the view reaches off its axis, up and across, as the scene draws it; a frame not yet
	-- laid out measures nothing, and is taken as square until it does.
	local frame = self.frame
	local scale = frame:GetEffectiveScale()
	local width, height = frame:GetWidth() * scale, frame:GetHeight() * scale
	local tall = math.tan(frame:GetCameraFieldOfView() / 2)
	local wide = tall
	if width > 0 and height > 0 then
		local across, up = self:Lens()
		tall, wide = height / 2 / math.abs(up), width / 2 / math.abs(across)
	end
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

--- A point or a direction in the scene's axes, in a held box's own: the piece's offset taken off a
-- point, then the piece's turn undone and its scale divided out by the matrix the box keeps. A
-- ray keeps its distances so carried.
local function into(box, x, y, z, isPoint)
	if isPoint then
		x, y, z = x - box.offset[1], y - box.offset[2], z - box.offset[3]
	end
	local m = box.undo
	return m[1] * x + m[2] * y + m[3] * z,
		m[4] * x + m[5] * y + m[6] * z,
		m[7] * x + m[8] * y + m[9] * z
end

--- How far along a ray it enters a held box, turned as its piece is: the ray carried into the
-- box's own axes and tested against the model's box there. Nil where it misses the box, starts
-- inside it, or meets it nearer than the camera draws. The box square to the scene holds the
-- turned one, so a ray that leaves it before the camera draws is turned off at that, the cheaper
-- test.
local function entersBox(ox, oy, oz, dx, dy, dz, box)
	local _, far = meets(ox, oy, oz, dx, dy, dz, box.outerLow, box.outerHigh)
	if not far or far <= NEAR then
		return nil
	end
	local px, py, pz = into(box, ox, oy, oz, true)
	local qx, qy, qz = into(box, dx, dy, dz, false)
	local near = meets(px, py, pz, qx, qy, qz, box.low, box.high)
	if near and near > NEAR then
		return near
	end
	return nil
end

--- Whether a point in the scene's axes lies within a held box, turned as its piece is.
local function holds(box, x, y, z)
	local px, py, pz = into(box, x, y, z, true)
	local low, high = box.low, box.high
	return px >= low[1]
		and px <= high[1]
		and py >= low[2]
		and py <= high[2]
		and pz >= low[3]
		and pz <= high[3]
end

--- Take in a loaded actor's box, turned, scaled and placed as its piece stands: kept as the model's
-- own box with the piece's offset and a matrix that undoes its turn and scale, for finding the
-- piece under the pointer, with the box square to the scene around it, which is taken into the
-- bounds framed.
function Scene:Hold(actor)
	local x1, y1, z1, x2, y2, z2 = actor:GetActiveBoundingBox()
	if not (x1 and y1 and z1 and x2 and y2 and z2) then
		return
	end
	local piece = actor.piece
	local turn, offset, scale = piece.turn, piece.offset, piece.scale
	local outerLow = { math.huge, math.huge, math.huge }
	local outerHigh = { -math.huge, -math.huge, -math.huge }
	for _, corner in ipairs(CORNERS) do
		local tx, ty, tz = Transform.Turned(
			turn,
			(corner[1] and x2 or x1) * scale,
			(corner[2] and y2 or y1) * scale,
			(corner[3] and z2 or z1) * scale
		)
		local x, y, z = offset[1] + tx, offset[2] + ty, offset[3] + tz
		outerLow[1], outerHigh[1] = math.min(outerLow[1], x), math.max(outerHigh[1], x)
		outerLow[2], outerHigh[2] = math.min(outerLow[2], y), math.max(outerHigh[2], y)
		outerLow[3], outerHigh[3] = math.min(outerLow[3], z), math.max(outerHigh[3], z)
	end
	-- The matrix's columns are the scene's axes carried into the model's, each the length of one
	-- model unit: the turn undone, then the scale divided out.
	local undo = Transform.Inverse(turn)
	local ax, ay, az = Transform.Turned(undo, 1 / scale, 0, 0)
	local bx, by, bz = Transform.Turned(undo, 0, 1 / scale, 0)
	local cx, cy, cz = Transform.Turned(undo, 0, 0, 1 / scale)
	local mx, my, mz =
		Transform.Turned(turn, (x1 + x2) / 2 * scale, (y1 + y2) / 2 * scale, (z1 + z2) / 2 * scale)
	local box = {
		actor = actor,
		offset = offset,
		undo = { ax, bx, cx, ay, by, cy, az, bz, cz },
		low = { x1, y1, z1 },
		high = { x2, y2, z2 },
		outerLow = outerLow,
		outerHigh = outerHigh,
		volume = (x2 - x1) * (y2 - y1) * (z2 - z1) * scale ^ 3,
		centre = { offset[1] + mx, offset[2] + my, offset[3] + mz },
	}
	self.boxes[#self.boxes + 1] = box
	actor.box = box
	local low = self.low or { math.huge, math.huge, math.huge }
	local high = self.high or { -math.huge, -math.huge, -math.huge }
	for axis = 1, 3 do
		low[axis] = math.min(low[axis], outerLow[axis])
		high[axis] = math.max(high[axis], outerHigh[axis])
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
	local across, up = self:Lens()
	local depth = self.distance * self.zoom
	local sideways, upward = dx * depth / across, dy * depth / up
	local rx, ry, rz, ux, uy, uz = self:Axes()
	local centre = self.centre
	centre[1] = centre[1] - rx * sideways - ux * upward
	centre[2] = centre[2] - ry * sideways - uy * upward
	centre[3] = centre[3] - rz * sideways - uz * upward
	self.moved = true
end

--- How the scene projects: pixels per unit of tangent off the view's axis, across and up, and the
-- pixel, from the scene's bottom left, where what the camera looks at lands. Measured with the
-- scene's own projection, which answers in pixels from its bottom left, so nothing rests on what
-- its field of view means; read from the field of view, as the vertical one, while the scene
-- projects nothing, as before it is first drawn.
function Scene:Lens()
	local frame = self.frame
	local scale = frame:GetEffectiveScale()
	local width, height = frame:GetWidth() * scale, frame:GetHeight() * scale
	if frame.Project3DPointTo2D then
		local c = self.centre
		local step = self.distance * self.zoom * LENS_STEP
		local rx, ry, rz, ux, uy, uz = self:Axes()
		local midX, midY = frame:Project3DPointTo2D(c[1], c[2], c[3])
		local rightX =
			frame:Project3DPointTo2D(c[1] + rx * step, c[2] + ry * step, c[3] + rz * step)
		local _, upY =
			frame:Project3DPointTo2D(c[1] + ux * step, c[2] + uy * step, c[3] + uz * step)
		if midX and midY and rightX and upY and rightX ~= midX and upY ~= midY then
			return (rightX - midX) / LENS_STEP, (upY - midY) / LENS_STEP, midX, midY
		end
	end
	local reach = height / 2 / math.tan(frame:GetCameraFieldOfView() / 2)
	return reach, reach, width / 2, height / 2
end

--- Where the pointer is off the view's axis, in units of tangent, across and up.
function Scene:Pointer()
	local frame = self.frame
	local scale = frame:GetEffectiveScale()
	local across, up, midX, midY = self:Lens()
	local x, y = _G.GetCursorPosition()
	return (x - frame:GetLeft() * scale - midX) / across,
		(y - frame:GetBottom() * scale - midY) / up
end

--- Bring the camera nearer or farther by steps of the wheel, toward the point under the pointer,
-- which stays under it: what the camera looks at moves toward that point by the share of the
-- distance the step takes off. A button zooms straight in, its pointer being on the button. The
-- camera is aimed afresh.
-- @param straight true to zoom toward the middle of the view, whatever is under the pointer
function Scene:Zoom(steps, straight)
	if not straight then
		self:Grab()
	end
	local zoom = clamp(self.zoom * ZOOM_STEP ^ steps, NEAR / self.distance, FARTHEST)
	if not straight then
		local across, upward = self:Pointer()
		local reach = self.distance * self.zoom * (1 - zoom / self.zoom)
		local rx, ry, rz, ux, uy, uz = self:Axes()
		local centre = self.centre
		centre[1] = centre[1] + (rx * across + ux * upward) * reach
		centre[2] = centre[2] + (ry * across + uy * upward) * reach
		centre[3] = centre[3] + (rz * across + uz * upward) * reach
	end
	self.zoom = zoom
	self.moved = true
	self:Aim()
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

--- Where the camera stands, as a point, and the way it looks, as a unit vector's three numbers.
function Scene:Eye()
	local fx, fy, fz = forwardOf(self.yaw, self.pitch)
	local distance, centre = self.distance * self.zoom, self.centre
	return { centre[1] - fx * distance, centre[2] - fy * distance, centre[3] - fz * distance },
		fx,
		fy,
		fz
end

--- The nearest loaded piece under the pointer, by its box: the box, which names its actor, how
-- deep along the view it lies, and where the camera stands. Nil where the pointer is on none.
function Scene:Pick()
	if not self.boxes[1] or self.frame:GetHeight() <= 0 then
		return nil
	end
	local across, upward = self:Pointer()
	local origin, fx, fy, fz = self:Eye()
	local rx, ry, rz, ux, uy, uz = self:Axes()
	local ox, oy, oz = origin[1], origin[2], origin[3]
	local dx = fx + rx * across + ux * upward
	local dy = fy + ry * across + uy * upward
	local dz = fz + rz * across + uz * upward
	local hits = {}
	for _, box in ipairs(self.boxes) do
		local depth = entersBox(ox, oy, oz, dx, dy, dz, box)
		if depth then
			hits[#hits + 1] = { box = box, depth = depth }
		end
	end
	local chosen
	for _, hit in ipairs(hits) do
		if not chosen or hit.depth < chosen.depth then
			chosen = hit
		end
	end
	-- A piece standing in another, as a jar on a shelf stands in the shelf's box, is what the
	-- pointer is on when the ray meets both: the smaller whose middle the larger holds, nearest
	-- first, and so on inward. A piece only behind another has its middle outside it.
	while chosen do
		local inner
		for _, hit in ipairs(hits) do
			local box, middle = hit.box, hit.box.centre
			if
				box.volume < chosen.box.volume
				and holds(chosen.box, middle[1], middle[2], middle[3])
				and (not inner or hit.depth < inner.depth)
			then
				inner = hit
			end
		end
		if not inner then
			break
		end
		chosen = inner
	end
	if chosen then
		return chosen.box, chosen.depth, origin
	end
	return nil
end

--- Move what the camera turns about and zooms toward to the nearest piece under the pointer, at
-- that piece's depth, the camera staying where it stands: zooming and panning then go at the pace
-- of what is pointed at rather than of the middle of the set. Nothing there leaves it be.
function Scene:Grab()
	local picked, depth, origin = self:Pick()
	if picked then
		local fx, fy, fz = forwardOf(self.yaw, self.pitch)
		self.centre = { origin[1] + fx * depth, origin[2] + fy * depth, origin[3] + fz * depth }
		self.zoom = clamp(depth / self.distance, NEAR / self.distance, FARTHEST)
	end
end

--- Load an actor's model afresh, at its piece's place, tilt and scale, with nothing on it. An
-- actor stands in its own scaled space, so its offset is divided by its scale.
function Scene:Load(actor)
	local piece = actor.piece
	local offset, scale = piece.offset, piece.scale
	actor.lit = nil
	actor:ClearModel()
	actor:SetUseCenterForOrigin(false, false, false)
	actor:SetPosition(offset[1] / scale, offset[2] / scale, offset[3] / scale)
	actor:SetScale(scale)
	local roll, pitch, yaw = Transform.ToAngles(piece.turn)
	actor:SetRoll(math.rad(roll))
	actor:SetPitch(math.rad(pitch))
	actor:SetYaw(math.rad(yaw))
	actor:SetModelByFileID(actor.source.file)
end

--- Light an actor's piece, or put its light out, as it is pointed at or chosen: the kit goes on
-- as either begins and comes off once both have ended. The glow stays painted once its kit is
-- taken off, so what the kit painted is cleared too, by the method Epsilon's client gives every
-- scene actor; a client without it has the model loaded afresh instead, which draws it without.
function Scene:Paint(actor)
	local lit = (actor == self.hovered and actor ~= self.dimmed) or actor.chosen == true
	if lit == (actor.lit == true) then
		return
	end
	actor.lit = lit or nil
	if lit then
		actor:SetSpellVisualKit(GLOW_KIT, false)
	elseif actor.ClearAllEffects then
		actor:SetSpellVisualKit(nil)
		actor:ClearAllEffects()
	else
		self:Load(actor)
	end
end

--- Point at a piece, or at none: the piece pointed at is lit and named, and the last is let be.
-- @param actor the piece's actor, or nil for none
function Scene:Hover(actor)
	if actor == self.hovered then
		return
	end
	local left = self.hovered
	self.hovered, self.dimmed = actor, nil
	if left then
		self:Paint(left)
	end
	if actor then
		self:Paint(actor)
	end
	if self.onHover then
		self.onHover(actor and actor.source)
	end
end

--- Make a list of actors what is chosen, in its order: the flag comes off those let go and goes
-- on those taken, each is lit or not as it stands, and the change is told. An unchanged list is
-- nothing.
function Scene:Settle(chosen)
	local was = self.chosen
	local same = #was == #chosen
	if same then
		for index, actor in ipairs(chosen) do
			if was[index] ~= actor then
				same = false
				break
			end
		end
	end
	if same then
		return false
	end
	for _, actor in ipairs(was) do
		actor.chosen = nil
	end
	for _, actor in ipairs(chosen) do
		actor.chosen = true
	end
	self.chosen = chosen
	-- A piece made to lead leads only while it is chosen.
	if self.lead and self.lead.chosen ~= true then
		self.lead = nil
	end
	for _, actor in ipairs(was) do
		self:Paint(actor)
	end
	for _, actor in ipairs(chosen) do
		self:Paint(actor)
	end
	if self.onChoose then
		self.onChoose()
	end
	return true
end

--- Choose the piece an actor draws alone, in place of what was chosen, or too, which toggles it;
-- nil alone chooses none. Made to lead, it is chosen too and leads the group in place of the
-- piece the rule would pick, until it is let go.
-- @param actor the piece's actor, or nil
-- @param more true to keep what was chosen
-- @param lead true to make the piece lead
function Scene:Choose(actor, more, lead)
	local chosen = {}
	local led = self.lead
	if more or (lead and actor) then
		for _, each in ipairs(self.chosen) do
			if each ~= actor then
				chosen[#chosen + 1] = each
			end
		end
	end
	if lead and actor then
		chosen[#chosen + 1] = actor
		self.lead = actor
	elseif actor and not (more and actor.chosen == true) then
		chosen[#chosen + 1] = actor
	elseif actor then
		-- Let go under the pointer, the piece goes dark until the pointer leaves it, or the light
		-- it keeps as the pointed piece would hide that it was let go.
		self.dimmed = actor
	end
	if not self:Settle(chosen) and self.lead ~= led and self.onChoose then
		self.onChoose()
	end
end

--- Choose what a shift press kept and every loaded piece whose middle its band holds now, in
-- that order, the band's pieces in the order they were drawn. Read afresh each frame the band is stretched,
-- so a piece lights as the band reaches it and goes out as the band leaves it. The band's far
-- corner is in screen pixels, as the pointer is read, and the middles are where the scene draws
-- them, those behind the camera left out.
function Scene:Banded(pressed, x1, y1)
	local frame = self.frame
	local scale = frame:GetEffectiveScale()
	local left, bottom = frame:GetLeft() * scale, frame:GetBottom() * scale
	local lowX, highX = math.min(pressed.x, x1) - left, math.max(pressed.x, x1) - left
	local lowY, highY = math.min(pressed.y, y1) - bottom, math.max(pressed.y, y1) - bottom
	local eye, fx, fy, fz = self:Eye()
	local chosen, kept, within = {}, {}, {}
	for index, actor in ipairs(pressed.kept) do
		chosen[index], kept[actor] = actor, true
	end
	for _, box in ipairs(self.boxes) do
		local actor, middle = box.actor, box.centre
		if not kept[actor] then
			local depth = (middle[1] - eye[1]) * fx
				+ (middle[2] - eye[2]) * fy
				+ (middle[3] - eye[3]) * fz
			if depth > NEAR then
				local x, y = frame:Project3DPointTo2D(middle[1], middle[2], middle[3])
				if x and y and x >= lowX and x <= highX and y >= lowY and y <= highY then
					within[#within + 1] = actor
				end
			end
		end
	end
	table.sort(within, function(a, b)
		return a.order < b.order
	end)
	for _, actor in ipairs(within) do
		chosen[#chosen + 1] = actor
	end
	self:Settle(chosen)
end

--- The ground a held box covers: its footprint, square to the scene.
local function footprint(box)
	return (box.outerHigh[1] - box.outerLow[1]) * (box.outerHigh[2] - box.outerLow[2])
end

--- Which chosen piece leads the group they form: the lowest-standing piece's box, bottom to top,
-- is the ground they stand on, and of the pieces whose bottom lies within it the one covering
-- most ground leads, the one drawn first among those alike. Level is read off the boxes rather
-- than as one height, since a chair's lowest vertex and a carpet's are never the same to the
-- last digit. So a table leads what is on it, a carpet leads the chairs on it, a floor piece
-- leads what hangs above it, and a group led from the ground sits on the ground when it is moved
-- there.
local function leader(actors)
	local lowest
	for _, actor in ipairs(actors) do
		if not lowest or actor.box.outerLow[3] < lowest.box.outerLow[3] then
			lowest = actor
		end
	end
	local ground = lowest.box.outerHigh[3]
	local leads
	for _, actor in ipairs(actors) do
		if
			actor.box.outerLow[3] <= ground
			and (
				not leads
				or footprint(actor.box) > footprint(leads.box)
				or footprint(actor.box) == footprint(leads.box) and actor.order < leads.order
			)
		then
			leads = actor
		end
	end
	return leads
end

--- How many pieces are chosen, which a band's every frame asks, and so without the ranking
-- Chosen does.
function Scene:Count()
	return #self.chosen
end

--- The piece that leads, as Draw was given it: the one a ctrl-click made lead, or the one the
-- rule picks; and whether it was made to. Nil where none is chosen.
function Scene:Leader()
	if not self.chosen[1] then
		return nil
	end
	local made = self.lead
	return (made or leader(self.chosen)).source, made ~= nil
end

--- The pieces chosen, as Draw was given them, in the order they would spawn: the one that leads
-- first, as Leader says it, then the rest in the order drawn.
function Scene:Chosen()
	local pieces = {}
	if self.chosen[1] then
		local leads = self.lead or leader(self.chosen)
		local rest = {}
		for _, actor in ipairs(self.chosen) do
			if actor ~= leads then
				rest[#rest + 1] = actor
			end
		end
		table.sort(rest, function(a, b)
			return a.order < b.order
		end)
		pieces[1] = leads.source
		for _, actor in ipairs(rest) do
			pieces[#pieces + 1] = actor.source
		end
	end
	return pieces
end

--- A press let go. The left button's, let go where it was made, is a click, which chooses the
-- piece under the pointer alone or, with shift, too; dragged with shift, its band chose as it
-- went and is read once more where it was let go; dragged without, it turned the camera.
function Scene:Release(button)
	self.dragged = nil
	local pressed = self.pressed
	self.pressed = nil
	if button ~= "LeftButton" or not pressed then
		return
	end
	self.band:Hide()
	local x, y = _G.GetCursorPosition()
	if wandered(self.frame, pressed, x, y) <= CLICK_SLOP then
		self:Choose(self.hovered, pressed.more, pressed.lead)
	elseif pressed.more then
		self:Banded(pressed, x, y)
	end
end

--- Draw the band from a shift press to the pointer, once the press has wandered past a click,
-- and choose what it holds.
function Scene:Stretch(pressed)
	local frame, band = self.frame, self.band
	local scale = frame:GetEffectiveScale()
	local x, y = _G.GetCursorPosition()
	if wandered(frame, pressed, x, y) <= CLICK_SLOP then
		band:Hide()
		return
	end
	band:ClearAllPoints()
	band:SetPoint(
		"BOTTOMLEFT",
		frame,
		"BOTTOMLEFT",
		math.min(pressed.x, x) / scale - frame:GetLeft(),
		math.min(pressed.y, y) / scale - frame:GetBottom()
	)
	band:SetSize(
		math.max(math.abs(x - pressed.x) / scale, 1),
		math.max(math.abs(y - pressed.y) / scale, 1)
	)
	band:Show()
	self:Banded(pressed, x, y)
end

--- Let go of all the pointer held, as the scene hides: the press, the drag, the band and what was
-- pointed at.
function Scene:Rest()
	self.pointed = false
	self.pressed, self.dragged = nil, nil
	self.band:Hide()
	self:Hover(nil)
end

--- Turn the camera on its own while the left mouse button stays down, as a held rotate button
-- does: 1 the way a drag to the left turns it, -1 the other way.
function Scene:Spin(direction)
	self.spin = direction
end

--- What a frame does: a drag turns or pans the camera, a held rotate button turns it, a shift
-- press stretches its band, and what loaded since the last frame is framed and told, once for
-- however many loaded.
-- @param elapsed the seconds since the last frame
function Scene:Tick(elapsed)
	-- A press let go off the scene is not heard by it, so the button is read as it is.
	local pressed = self.pressed
	local banding = pressed and pressed.more
	if banding then
		if _G.IsMouseButtonDown("LeftButton") then
			self:Stretch(pressed)
		else
			self:Release("LeftButton")
			banding = false
		end
	end
	local dragged = self.dragged
	if dragged then
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
	-- and not while a drag holds the view or a band is drawn.
	if self.pointed and not self.dragged and not banding then
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
		-- What lies under a pointer that has not moved may have, a model having loaded there.
		self.looked = nil
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
	local chose = #self.chosen > 0
	for _, actor in ipairs(self.chosen) do
		actor.chosen = nil
	end
	self.chosen, self.lead = {}, nil
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
			local turn = Transform.TurnOf(piece)
			actor.piece = { offset = offset, turn = turn, scale = scale }
			actor.order = placed
			actor.source = piece
			actor:SetOnModelLoadedCallback(Client.Guarded(loaded))
			self:Load(actor)
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
	if chose and self.onChoose then
		self.onChoose()
	end
end
