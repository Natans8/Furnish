-- The settings panel, in the game's own Options under AddOns: every value in Settings.lua a
-- player may change, written straight into Furnish.Settings, which the game keeps between
-- sessions. A change takes effect at once; Cancel puts back what the panel showed when it
-- opened, and Defaults what the addon ships with.

local _, Furnish = ...
local Client = Furnish.Client
local Chat = Furnish.Chat
local Commands = Furnish.Commands
local Settings = Furnish.Settings

--- The values the addon ships with: every setting, copied as this file loads, before the saved
-- ones are restored over them.
local DEFAULTS = {}
for key, value in pairs(Settings) do
	DEFAULTS[key] = value
end

--- How many commands a run may have unanswered, at least and at most.
local FEWEST, MOST = Furnish.Bounds.inFlight.least, Furnish.Bounds.inFlight.most

-- Made hidden, so the Options window's Show fires OnShow, which reads the settings in.
local panel = _G.CreateFrame("Frame")
panel.name = Furnish.NAME
panel:Hide()

local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
title:SetPoint("TOPLEFT", 16, -16)
title:SetText(Furnish.NAME)

local about = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
about:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
about:SetPoint("RIGHT", panel, "RIGHT", -16, 0)
about:SetJustifyH("LEFT")
about:SetText("Changes take effect at once and are kept between sessions.")

-- The chat buttons. The plain check button the window uses: Blizzard's options template expects
-- a console variable behind it and errors on a click without one.
local buttons = _G.CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
buttons:SetPoint("TOPLEFT", about, "BOTTOMLEFT", -2, -20)
buttons.text:SetText(Furnish.NAME .. " buttons in chat")
buttons:SetScript(
	"OnClick",
	Client.Guarded(function(box)
		_G.PlaySound(_G.SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
		Settings.chatButtons = box:GetChecked() and true or false
	end)
)
buttons:SetScript(
	"OnEnter",
	Client.Guarded(function(self)
		_G.GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		Chat.Tip(_G.GameTooltip, self.text:GetText(), {
			{
				text = ("A [%s] button after a WMO's doodad, selection and spawn lines."):format(
					Furnish.NAME
				),
			},
		})
		_G.GameTooltip:Show()
	end)
)
buttons:SetScript("OnLeave", _G.GameTooltip_Hide)

-- How far ahead of the server's replies a run sends.
local pace = _G.CreateFrame("Slider", nil, panel, "OptionsSliderTemplate")
pace:SetPoint("TOPLEFT", buttons, "BOTTOMLEFT", 4, -40)
pace:SetWidth(240)
pace:SetMinMaxValues(FEWEST, MOST)
pace:SetValueStep(1)
pace:SetObeyStepOnDrag(true)
pace.Low:SetText(FEWEST)
pace.High:SetText(MOST)
pace.tooltipText = "Commands sent ahead of the server's replies. More is faster; Stop can't take back"
	.. " what is sent."
local function paceText(value)
	pace.Text:SetText(("Commands in flight: %d"):format(value))
end
pace:SetScript(
	"OnValueChanged",
	Client.Guarded(function(_, value)
		local whole = math.floor(value + 0.5)
		Settings.inFlight = whole
		paceText(whole)
	end)
)

-- What a pivot spawns as, in the words a spawn command takes.
local pivotLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
pivotLabel:SetPoint("TOPLEFT", pace, "BOTTOMLEFT", -4, -36)
pivotLabel:SetText("Pivot")

local pivot = _G.CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
pivot:SetPoint("LEFT", pivotLabel, "RIGHT", 14, 0)
pivot:SetSize(90, 20)
pivot:SetAutoFocus(false)
pivot:SetMaxLetters(10)

local pivotNote = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
pivotNote:SetPoint("TOPLEFT", pivotLabel, "BOTTOMLEFT", 0, -8)
pivotNote:SetPoint("RIGHT", panel, "RIGHT", -16, 0)
pivotNote:SetJustifyH("LEFT")
pivotNote:SetText(
	(
		"The object that leads a set's group where no other does, as %s takes it: a gob entry,"
		.. " or a display as a negative number. %s's own, %d, is invisible and silent."
	):format(Commands.Typed(Commands.SPAWN), Furnish.NAME, DEFAULTS.pivot)
)

--- Take the id typed, or put back the one kept where Settings does not allow what was typed.
local function pivotEntered(box)
	local value = tonumber(box:GetText())
	if Furnish.Allowed("pivot", value) then
		Settings.pivot = value
	end
	box:SetText(tostring(Settings.pivot))
end
pivot:SetScript("OnEnterPressed", pivot.ClearFocus)
pivot:SetScript("OnEscapePressed", function(box)
	box:SetText(tostring(Settings.pivot))
	box:ClearFocus()
end)
pivot:HookScript("OnEditFocusLost", Client.Guarded(pivotEntered))

--- Show what the settings hold now.
local function show()
	buttons:SetChecked(Settings.chatButtons)
	pace:SetValue(Settings.inFlight)
	paceText(Settings.inFlight)
	pivot:SetText(tostring(Settings.pivot))
end

--- What the panel showed when it opened, which Cancel puts back.
local opened = {}

panel:SetScript(
	"OnShow",
	Client.Guarded(function()
		for key in pairs(DEFAULTS) do
			opened[key] = Settings[key]
		end
		show()
	end)
)

panel.okay = function() end

panel.cancel = function()
	for key, value in pairs(opened) do
		Settings[key] = value
	end
end

panel.default = function()
	for key, value in pairs(DEFAULTS) do
		Settings[key] = value
	end
	show()
end

panel.refresh = show

_G.InterfaceOptions_AddCategory(panel)
