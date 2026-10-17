-- RoleRoulette: themed controls
--
-- Flat controls in the look SquizzFrames and Squizzumables share: 1px borders,
-- dark fills, one accent colour. Every colour comes from LibSquizzTheme-1.0, so
-- RoleRoulette follows whichever preset is picked in either addon. Only the
-- accent repaints live (W.RefreshAccent, on a preset change); everything else
-- is read when the control is made, as in the other two addons.

local _, ns = ...

local W = {}
ns.W = W

local WHITE = "Interface\\Buttons\\WHITE8X8"
local FONT = "Fonts\\FRIZQT__.TTF"

local function Theme() return LibStub and LibStub("LibSquizzTheme-1.0", true) end

function W.RGBA(key)
    local T = Theme()
    if T then return T:RGBA(key) end
    return 0.5, 0.5, 0.5, 1
end

function W.Accent()
    local T = Theme()
    if T then return T:AccentRGB() end
    return 0.78, 0.65, 0.30
end

-- Everything that draws in the accent registers a repaint here.
local accentPainters = {}
function W.OnAccent(fn)
    accentPainters[#accentPainters + 1] = fn
    fn()
end
function W.RefreshAccent()
    for _, fn in ipairs(accentPainters) do fn() end
end

function W.Backdrop(frame, bgKey, borderKey)
    frame:SetBackdrop({bgFile = WHITE, edgeFile = WHITE, edgeSize = 1})
    frame:SetBackdropColor(W.RGBA(bgKey))
    if borderKey then
        frame:SetBackdropBorderColor(W.RGBA(borderKey))
    else
        frame:SetBackdropBorderColor(0, 0, 0, 0)
    end
end

function W.Text(parent, size, colorKey, layer)
    local fs = parent:CreateFontString(nil, layer or "OVERLAY")
    fs:SetFont(FONT, size or 12, "")
    fs:SetShadowOffset(1, -1)
    fs:SetShadowColor(0, 0, 0, 0.8)
    fs:SetTextColor(W.RGBA(colorKey or "text"))
    return fs
end

-- A section title: accent swatch, capitals, hairline underneath.
function W.Section(parent, text)
    local pane = CreateFrame("Frame", nil, parent)
    pane:SetHeight(18)
    local swatch = pane:CreateTexture(nil, "ARTWORK")
    swatch:SetSize(6, 6)
    swatch:SetPoint("LEFT")
    W.OnAccent(function()
        local r, g, b = W.Accent()
        swatch:SetColorTexture(r, g, b, 1)
    end)
    pane.title = W.Text(pane, 11, "textBright")
    pane.title:SetPoint("LEFT", swatch, "RIGHT", 6, 0)
    function pane:SetText(t) self.title:SetText((t or ""):upper()) end
    pane:SetText(text)
    local line = pane:CreateTexture(nil, "BACKGROUND")
    line:SetPoint("BOTTOMLEFT")
    line:SetPoint("BOTTOMRIGHT")
    line:SetHeight(1)
    line:SetColorTexture(1, 1, 1, 0.08)
    local Shell = LibStub and LibStub("LibSquizzShell-1.0", true)
    if Shell then Shell:IndexSection(parent, text) end
    return pane
end

-- A flat button. style "accent" fills it with the accent (the main action);
-- "danger" turns red on hover. b:SetText routes to its own label.
function W.Button(parent, label, width, height, style)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetSize(width or 90, height or 22)
    W.Backdrop(b, "control", "border")
    b.text = W.Text(b, (height or 22) >= 30 and 14 or 11, "text")
    b.text:SetPoint("CENTER")
    b.text:SetText(label or "")
    function b:SetText(t) self.text:SetText(t or "") end

    local hover = false
    local function Paint()
        if not b:IsEnabled() then
            b:SetBackdropColor(W.RGBA("control"))
            b.text:SetTextColor(W.RGBA("textDim"))
            return
        end
        b.text:SetTextColor(W.RGBA((style == "accent" or b.active) and "textBright" or "text"))
        if b.active then
            local r, g, bb = W.Accent()
            b:SetBackdropColor(r, g, bb, 0.45)
        elseif style == "accent" then
            local r, g, bb = W.Accent()
            b:SetBackdropColor(r, g, bb, hover and 0.6 or 0.3)
        elseif hover and style == "danger" then
            b:SetBackdropColor(W.RGBA("danger"))
        elseif hover then
            b:SetBackdropColor(W.RGBA("controlHi"))
        else
            b:SetBackdropColor(W.RGBA("control"))
        end
    end
    b:SetScript("OnEnter", function() hover = true Paint() end)
    b:SetScript("OnLeave", function() hover = false Paint() end)
    b:SetScript("OnEnable", Paint)
    b:SetScript("OnDisable", Paint)
    -- Lit in the accent: the chosen one of a set (the theme presets).
    function b:SetActive(on)
        self.active = on and true or false
        Paint()
    end
    W.OnAccent(Paint)
    return b
end

-- The toggle switch both addons use for on/off settings: a track and a square
-- knob that slides right and takes the accent when on. onChange(checked).
local TOGGLE_W, TOGGLE_H, PAD = 30, 16, 2
local KNOB = TOGGLE_H - PAD * 2
local OFF = {0.45, 0.45, 0.45}

function W.Toggle(parent, label, onChange)
    local cb = CreateFrame("CheckButton", nil, parent, "BackdropTemplate")
    cb:SetSize(TOGGLE_W, TOGGLE_H)
    W.Backdrop(cb, "control", "border")
    local knob = cb:CreateTexture(nil, "ARTWORK")
    knob:SetSize(KNOB, KNOB)

    if label then
        cb.label = W.Text(cb, 11, "text")
        cb.label:SetPoint("LEFT", cb, "RIGHT", 7, 0)
        cb.label:SetText(label)
        cb:SetHitRectInsets(0, -cb.label:GetStringWidth() - 7, 0, 0)
    end

    local function Paint()
        local on = cb:GetChecked() and true or false
        knob:ClearAllPoints()
        knob:SetPoint("LEFT", on and (TOGGLE_W - KNOB - PAD) or PAD, 0)
        if on then
            local r, g, b = W.Accent()
            knob:SetColorTexture(r, g, b, 1)
            local _, _, _, ca = W.RGBA("control")
            cb:SetBackdropColor(r * 0.28, g * 0.28, b * 0.28, ca)
        else
            knob:SetColorTexture(OFF[1], OFF[2], OFF[3], 1)
            cb:SetBackdropColor(W.RGBA("control"))
        end
    end
    W.OnAccent(Paint)

    local setChecked = cb.SetChecked
    function cb:SetChecked(v)
        setChecked(self, v and true or false)
        Paint()
    end
    cb:SetScript("OnClick", function(self)
        Paint()
        PlaySound(self:GetChecked() and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON
            or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
        if onChange then onChange(self:GetChecked() and true or false) end
    end)
    cb:SetScript("OnEnter", function(self)
        local r, g, b = W.Accent()
        self:SetBackdropBorderColor(r, g, b, 0.6)
        if self.tip then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(self.tip, 1, 1, 1, 1, true)
            GameTooltip:Show()
        end
    end)
    cb:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(W.RGBA("border"))
        GameTooltip:Hide()
    end)

    if label then
        local Shell = LibStub and LibStub("LibSquizzShell-1.0", true)
        if Shell then Shell:IndexControl(cb, label) end
    end
    return cb
end

-- A single-line input in the search box's style, with grey hint text.
function W.EditBox(parent, width, hint)
    local box = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
    box:SetSize(width, 22)
    W.Backdrop(box, "control", "border")
    box:SetFont(FONT, 11, "")
    box:SetTextColor(W.RGBA("text"))
    box:SetTextInsets(6, 6, 0, 0)
    box:SetAutoFocus(false)
    local h = W.Text(box, 11, "textDim")
    h:SetPoint("LEFT", 6, 0)
    h:SetText(hint or "")
    local function Hint() h:SetShown(box:GetText() == "" and not box:HasFocus()) end
    box:SetScript("OnEditFocusGained", function(self)
        Hint()
        local r, g, b = W.Accent()
        self:SetBackdropBorderColor(r, g, b, 0.8)
    end)
    box:SetScript("OnEditFocusLost", function(self)
        Hint()
        self:SetBackdropBorderColor(W.RGBA("border"))
    end)
    box:SetScript("OnTextChanged", Hint)
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    return box
end

-- A panel: the dark box each column sits in.
function W.Panel(parent)
    local p = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    W.Backdrop(p, "tabInactive", "border")
    local r, g, b = W.RGBA("border")
    p:SetBackdropBorderColor(r, g, b, 0.5)
    return p
end

-- A scroll area with the window's thin scroll bar. Returns the scroll frame
-- and its child; size the child's height to the content.
function W.ScrollArea(parent)
    local sf = CreateFrame("ScrollFrame", nil, parent)
    local bar = CreateFrame("Slider", nil, parent, "BackdropTemplate")
    bar:SetPoint("TOPLEFT", sf, "TOPRIGHT", 4, 0)
    bar:SetPoint("BOTTOMLEFT", sf, "BOTTOMRIGHT", 4, 0)
    bar:SetWidth(6)
    bar:SetOrientation("VERTICAL")
    bar:SetMinMaxValues(0, 0)
    bar:SetValueStep(20)
    bar:SetObeyStepOnDrag(true)
    bar:SetBackdrop({bgFile = WHITE})
    bar:SetBackdropColor(W.RGBA("control"))
    local thumb = bar:CreateTexture(nil, "OVERLAY")
    thumb:SetSize(6, 30)
    local tr, tg, tb = W.RGBA("controlHi")
    thumb:SetColorTexture(tr, tg, tb, 1)
    bar:SetThumbTexture(thumb)

    local child = CreateFrame("Frame", nil, sf)
    child:SetSize(1, 1)
    sf:SetScrollChild(child)
    sf:SetScript("OnSizeChanged", function(self, w) child:SetWidth(w) end)
    sf:SetScript("OnScrollRangeChanged", function(_, _, yrange)
        yrange = yrange or 0
        bar:SetMinMaxValues(0, yrange)
        bar:SetShown(yrange > 0)
        if bar:GetValue() > yrange then bar:SetValue(yrange) end
    end)
    bar:SetScript("OnValueChanged", function(_, v) sf:SetVerticalScroll(v) end)
    sf:EnableMouseWheel(true)
    sf:SetScript("OnMouseWheel", function(_, delta)
        local lo, hi = bar:GetMinMaxValues()
        bar:SetValue(math.max(lo, math.min(hi, bar:GetValue() - delta * 40)))
    end)
    bar:Hide()
    sf.bar = bar
    return sf, child
end
