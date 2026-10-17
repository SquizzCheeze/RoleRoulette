-- RoleRoulette: UI
--
-- The window is LibSquizzShell-1.0, the one SquizzFrames and Squizzumables
-- use, so RoleRoulette looks like them, follows the shared theme and appears
-- in the combined /squizz window. Two pages:
--
--   Roll      roster | specs for the selected member | result
--   Settings  rotation, auto-announce, theme
--
-- Frames are never created in combat: the window waits for combat to end the
-- first time it is opened, and new roster rows wait the same way (through
-- ns.OutOfCombat). Text, ticks and colours still update in combat.

local _, ns = ...
local R, W = ns.Randomizer, ns.W

local UI = {}
ns.UI = UI

local ADDON_ID = "RoleRoulette"
local ROSTER_W, RESULT_W, GAP = 230, 250, 10
local ROW_H = 24
local SPEC_ROW_H = 22
local RESULT_ROW_H = 46

local function Shell() return LibStub("LibSquizzShell-1.0", true) end
local function Theme() return LibStub("LibSquizzTheme-1.0", true) end

local win
local selected                  -- the member whose specs are shown
local roll = {}                 -- the Roll page's widgets, once built
local rosterRows, resultRows = {}, {}
local specRows = {}             -- [specID] = row
local classHeaders = {}

-----------------------------------------------------------------------
-- Roster column
-----------------------------------------------------------------------

local function SetMessage(text, colorKey)
    if not roll.message then return end
    roll.message:SetText(text or "")
    roll.message:SetTextColor(W.RGBA(colorKey or "critical"))
end

local function PaintRosterRow(row)
    local m = row.member
    local isSel = m and m == selected
    if isSel then
        local r, g, b = W.Accent()
        row:SetBackdropColor(r, g, b, 0.14)
        row.bar:SetColorTexture(r, g, b, 1)
        row.bar:Show()
        row.name:SetTextColor(W.RGBA("textBright"))
    else
        if row.hover then
            row:SetBackdropColor(W.RGBA("controlHi"))
        else
            row:SetBackdropColor(0, 0, 0, 0)
        end
        row.bar:Hide()
        row.name:SetTextColor(W.RGBA("text"))
    end
end

local function CreateRosterRow(parent, i)
    local row = CreateFrame("Button", nil, parent, "BackdropTemplate")
    row:SetHeight(ROW_H)
    row:SetPoint("TOPLEFT", 0, -(i - 1) * (ROW_H + 2))
    row:SetPoint("TOPRIGHT", 0, -(i - 1) * (ROW_H + 2))
    row:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8X8"})

    row.bar = row:CreateTexture(nil, "OVERLAY")
    row.bar:SetPoint("TOPLEFT")
    row.bar:SetPoint("BOTTOMLEFT")
    row.bar:SetWidth(3)

    row.available = W.Toggle(row, nil, function(on)
        if row.member then
            row.member.available = on
            UI.RefreshCount()
        end
    end)
    row.available:SetPoint("LEFT", 8, 0)
    row.available.tip = "Playing tonight"

    -- Remove: a quiet X that turns red on hover.
    row.remove = CreateFrame("Button", nil, row)
    row.remove:SetSize(20, ROW_H)
    row.remove:SetPoint("RIGHT", -2, 0)
    local x = W.Text(row.remove, 12, "textDim")
    x:SetPoint("CENTER")
    x:SetText("x")
    row.remove:SetScript("OnEnter", function(self)
        x:SetTextColor(W.RGBA("danger"))
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Remove from the roster", 1, 1, 1)
        GameTooltip:Show()
    end)
    row.remove:SetScript("OnLeave", function()
        x:SetTextColor(W.RGBA("textDim"))
        GameTooltip:Hide()
    end)
    row.remove:SetScript("OnClick", function()
        local m = row.member
        if not m then return end
        ns.RemoveMember(m)
        if selected == m then selected = nil end
        UI.RefreshRoster()
        UI.RefreshSpecs()
    end)

    -- The roles their pool covers, dimmed when not covered.
    row.roles = {}
    local prev = row.remove
    for k = #R.ORDER, 1, -1 do
        local role = R.ORDER[k]
        local t = row:CreateTexture(nil, "ARTWORK")
        t:SetSize(15, 15)
        t:SetPoint("RIGHT", prev, "LEFT", -2, 0)
        ns.SetRoleIcon(t, role)
        row.roles[role] = t
        prev = t
    end

    row.name = W.Text(row, 12, "text")
    row.name:SetPoint("LEFT", row.available, "RIGHT", 8, 0)
    row.name:SetPoint("RIGHT", prev, "LEFT", -4, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)

    row:SetScript("OnEnter", function(self) self.hover = true PaintRosterRow(self) end)
    row:SetScript("OnLeave", function(self) self.hover = false PaintRosterRow(self) end)
    row:SetScript("OnClick", function(self)
        if not self.member then return end
        selected = (selected == self.member) and nil or self.member
        UI.RefreshRoster()
        UI.RefreshSpecs()
    end)
    return row
end

function UI.RefreshCount()
    if not roll.count then return end
    -- One to five can roll; more than five is the only count that can't.
    local n = #R.Available(ns.db.roster)
    roll.count:SetText(string.format("%d playing", n))
    roll.count:SetTextColor(W.RGBA(n > R.GROUP_SIZE and "critical" or (n > 0 and "good" or "textDim")))
end

function UI.RefreshRoster()
    if not roll.rosterChild then return end
    local roster = ns.db.roster
    -- New rows are new frames, so they wait for combat to end.
    if #roster > #rosterRows and InCombatLockdown() then
        ns.OutOfCombat("roster", UI.RefreshRoster)
        return
    end
    for i = #rosterRows + 1, #roster do
        rosterRows[i] = CreateRosterRow(roll.rosterChild, i)
    end
    for i, row in ipairs(rosterRows) do
        local m = roster[i]
        row.member = m
        if m then
            row.available:SetChecked(m.available)
            row.name:SetText(m.name)
            local roles = R.RolesFor(m, ns.RoleOf)
            for role, t in pairs(row.roles) do
                t:SetDesaturated(not roles[role])
                t:SetAlpha(roles[role] and 1 or 0.2)
            end
            PaintRosterRow(row)
            row:Show()
        else
            row:Hide()
        end
    end
    roll.rosterChild:SetHeight(math.max(1, #roster * (ROW_H + 2)))
    roll.rosterEmpty:SetShown(#roster == 0)
    UI.RefreshCount()
end

local function AddFromBox()
    local m, err = ns.AddMember(roll.nameBox:GetText())
    if not m then
        SetMessage(err)
        return
    end
    roll.nameBox:SetText("")
    roll.nameBox:ClearFocus()
    SetMessage("")
    selected = m
    UI.RefreshRoster()
    UI.RefreshSpecs()
end

local function BuildRoster(panel)
    local head = W.Section(panel, "Roster")
    head:SetPoint("TOPLEFT", 10, -10)
    head:SetPoint("TOPRIGHT", -10, -10)
    roll.count = W.Text(panel, 11, "textDim")
    roll.count:SetPoint("RIGHT", head, "RIGHT", 0, 0)

    local add = W.Button(panel, "Add", 52, 22)
    add:SetPoint("TOPRIGHT", head, "BOTTOMRIGHT", 0, -10)
    add:SetScript("OnClick", AddFromBox)

    local box = W.EditBox(panel, 10, "Name...")
    box:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 0, -10)
    box:SetPoint("RIGHT", add, "LEFT", -6, 0)
    box:SetMaxLetters(48)
    box:SetScript("OnEnterPressed", AddFromBox)
    roll.nameBox = box

    local import = W.Button(panel, "Import Party", 10, 22)
    import:SetPoint("TOPLEFT", box, "BOTTOMLEFT", 0, -6)
    import:SetPoint("TOPRIGHT", add, "BOTTOMRIGHT", 0, -6)
    import:SetScript("OnClick", function()
        local added, skipped, unreadable = ns.ImportParty()
        local parts = {added .. " added"}
        if skipped > 0 then parts[#parts + 1] = skipped .. " already listed" end
        if unreadable > 0 then parts[#parts + 1] = unreadable .. " unreadable right now" end
        SetMessage("Import: " .. table.concat(parts, ", ") .. ".", "textDim")
        UI.RefreshRoster()
    end)

    local sf, child = W.ScrollArea(panel)
    sf:SetPoint("TOPLEFT", import, "BOTTOMLEFT", -4, -10)
    sf:SetPoint("BOTTOMRIGHT", -14, 8)
    roll.rosterChild = child

    roll.rosterEmpty = W.Text(panel, 11, "textDim")
    roll.rosterEmpty:SetPoint("TOPLEFT", sf, "TOPLEFT", 8, -10)
    roll.rosterEmpty:SetPoint("RIGHT", panel, "RIGHT", -12, 0)
    roll.rosterEmpty:SetJustifyH("LEFT")
    roll.rosterEmpty:SetText("Add people by name or import your party, then click a name to choose their specs.")
end

-----------------------------------------------------------------------
-- Specs column
-----------------------------------------------------------------------

local function PaintSpecRow(row)
    local on = selected and ns.HasSpec(selected, row.specID)
    if on then
        local r, g, b = W.Accent()
        row.box:SetBackdropColor(r, g, b, 1)
    else
        row.box:SetBackdropColor(W.RGBA("control"))
    end
    if row.hover then
        row:SetBackdropColor(W.RGBA("controlHi"))
    else
        row:SetBackdropColor(0, 0, 0, 0)
    end
    row.name:SetTextColor(W.RGBA(on and "textBright" or "text"))
end

local function BuildSpecs(panel)
    roll.specHead = W.Section(panel, "Specs")
    roll.specHead:SetPoint("TOPLEFT", 10, -10)
    roll.specHead:SetPoint("TOPRIGHT", -10, -10)

    local clear = W.Button(panel, "Clear", 52, 18)
    clear:SetPoint("RIGHT", roll.specHead, "RIGHT", 0, 1)
    clear:SetScript("OnClick", function()
        if not selected then return end
        wipe(selected.specs)
        UI.RefreshSpecs()
        UI.RefreshRoster()
    end)
    roll.specClear = clear

    local hint = W.Text(panel, 11, "textDim")
    hint:SetPoint("TOPLEFT", roll.specHead, "BOTTOMLEFT", 0, -8)
    hint:SetPoint("RIGHT", panel, "RIGHT", -10, 0)  -- wraps instead of running into the next column
    hint:SetJustifyH("LEFT")
    hint:SetText("Tick every spec they'll play.")
    roll.specHint = hint

    local sf, child = W.ScrollArea(panel)
    sf:SetPoint("TOPLEFT", hint, "BOTTOMLEFT", -4, -8)
    sf:SetPoint("BOTTOMRIGHT", -14, 8)
    roll.specScroll = sf

    roll.specEmpty = W.Text(panel, 12, "textDim")
    roll.specEmpty:SetPoint("CENTER", panel, "CENTER", 0, 20)
    roll.specEmpty:SetWidth(220)
    roll.specEmpty:SetText("Click a name in the roster to choose what they'll play.")

    local y = 0
    for _, class in ipairs(ns.Classes) do
        local header = W.Text(child, 12, "text")
        header:SetPoint("TOPLEFT", 4, -y - 4)
        header:SetText(class.name)
        header:SetTextColor(ns.ClassColor(class.classID))
        classHeaders[#classHeaders + 1] = header
        y = y + 22

        for _, spec in ipairs(class.specs) do
            local row = CreateFrame("Button", nil, child, "BackdropTemplate")
            row:SetHeight(SPEC_ROW_H)
            row:SetPoint("TOPLEFT", 0, -y)
            row:SetPoint("TOPRIGHT", 0, -y)
            row:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8X8"})
            row.specID, row.classID = spec.specID, class.classID

            row.box = CreateFrame("Frame", nil, row, "BackdropTemplate")
            row.box:SetSize(12, 12)
            row.box:SetPoint("LEFT", 10, 0)
            W.Backdrop(row.box, "control", "border")

            local role = row:CreateTexture(nil, "ARTWORK")
            role:SetSize(15, 15)
            role:SetPoint("LEFT", row.box, "RIGHT", 8, 0)
            ns.SetRoleIcon(role, spec.role)

            local icon = row:CreateTexture(nil, "ARTWORK")
            icon:SetSize(18, 18)
            icon:SetPoint("LEFT", role, "RIGHT", 5, 0)
            icon:SetTexture(spec.icon)
            icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

            row.name = W.Text(row, 12, "text")
            row.name:SetPoint("LEFT", icon, "RIGHT", 7, 0)
            row.name:SetText(spec.name)

            row:SetScript("OnEnter", function(self) self.hover = true PaintSpecRow(self) end)
            row:SetScript("OnLeave", function(self) self.hover = false PaintSpecRow(self) end)
            row:SetScript("OnClick", function(self)
                if not selected then return end
                local on = not ns.HasSpec(selected, self.specID)
                ns.SetSpec(selected, self.classID, self.specID, on)
                PlaySound(on and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON
                    or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
                PaintSpecRow(self)
                UI.RefreshRoster()
            end)
            specRows[spec.specID] = row
            y = y + SPEC_ROW_H + 1
        end
        y = y + 10
    end
    child:SetHeight(math.max(1, y))
end

function UI.RefreshSpecs()
    if not roll.specHead then return end
    local has = selected ~= nil
    roll.specHead:SetText(has and ("Specs for " .. selected.name) or "Specs")
    roll.specScroll:SetShown(has)
    roll.specHint:SetShown(has)
    roll.specClear:SetShown(has)
    roll.specEmpty:SetShown(not has)
    for _, row in pairs(specRows) do PaintSpecRow(row) end
end

-----------------------------------------------------------------------
-- Result column
-----------------------------------------------------------------------

local function CreateResultRow(parent, i)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(RESULT_ROW_H)
    row:SetPoint("TOPLEFT", 0, -(i - 1) * RESULT_ROW_H)
    row:SetPoint("TOPRIGHT", 0, -(i - 1) * RESULT_ROW_H)

    row.role = row:CreateTexture(nil, "ARTWORK")
    row.role:SetSize(22, 22)
    row.role:SetPoint("LEFT", 2, 0)

    local frame = CreateFrame("Frame", nil, row, "BackdropTemplate")
    frame:SetSize(34, 34)
    frame:SetPoint("LEFT", row.role, "RIGHT", 8, 0)
    W.Backdrop(frame, "control", "border")
    row.spec = frame:CreateTexture(nil, "ARTWORK")
    row.spec:SetPoint("TOPLEFT", 1, -1)
    row.spec:SetPoint("BOTTOMRIGHT", -1, 1)
    row.spec:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    row.who = W.Text(row, 14, "textBright")
    row.who:SetPoint("TOPLEFT", frame, "TOPRIGHT", 9, -2)
    row.who:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    row.who:SetJustifyH("LEFT")
    row.who:SetWordWrap(false)

    row.detail = W.Text(row, 11, "textDim")
    row.detail:SetPoint("BOTTOMLEFT", frame, "BOTTOMRIGHT", 9, 2)
    row.detail:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    row.detail:SetJustifyH("LEFT")
    row.detail:SetWordWrap(false)
    return row
end

function UI.RefreshResult()
    if not roll.results then return end
    local last = ns.db.history.last
    local has = last and #last > 0
    for i, row in ipairs(resultRows) do
        local e = has and last[i]
        if e then
            local spec = ns.SpecInfo[e.specID]
            local class = ns.ClassByID(e.classID)
            ns.SetRoleIcon(row.role, e.role)
            row.spec:SetTexture(spec and spec.icon or 134400) -- question mark
            row.who:SetText(e.name)
            row.who:SetTextColor(ns.ClassColor(e.classID))
            -- No role word: the icon on the left already says it, and the
            -- room is needed for names like "Marksmanship Hunter".
            row.detail:SetText(string.format("%s %s",
                spec and spec.name or "Unknown spec", class and class.name or ""))
            row:Show()
        else
            row:Hide()
        end
    end
    roll.resultEmpty:SetShown(not has)
    roll.reroll:SetEnabled(has)
    roll.announce:SetEnabled(has)
end

local function DoRoll(isReroll)
    local r = ns.Roll(isReroll)
    if r.ok then SetMessage("") else SetMessage(r.message) end
    UI.RefreshResult()
end

local function BuildResult(panel)
    local head = W.Section(panel, "Result")
    head:SetPoint("TOPLEFT", 10, -10)
    head:SetPoint("TOPRIGHT", -10, -10)

    local go = W.Button(panel, "Randomize!", 10, 34, "accent")
    go:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 0, -10)
    go:SetPoint("TOPRIGHT", head, "BOTTOMRIGHT", 0, -10)
    go:SetScript("OnClick", function()
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        DoRoll(false)
    end)

    local results = CreateFrame("Frame", nil, panel)
    results:SetPoint("TOPLEFT", go, "BOTTOMLEFT", 0, -8)
    results:SetPoint("TOPRIGHT", go, "BOTTOMRIGHT", 0, -8)
    results:SetHeight(R.GROUP_SIZE * RESULT_ROW_H)
    roll.results = results
    for i = 1, R.GROUP_SIZE do resultRows[i] = CreateResultRow(results, i) end

    roll.resultEmpty = W.Text(panel, 12, "textDim")
    roll.resultEmpty:SetPoint("CENTER", results, "CENTER")
    roll.resultEmpty:SetWidth(200)
    roll.resultEmpty:SetText("Switch on who's playing (one to five), then press Randomize.")

    roll.reroll = W.Button(panel, "Re-roll", 10, 24)
    roll.reroll:SetPoint("TOPLEFT", results, "BOTTOMLEFT", 0, -8)
    roll.reroll:SetPoint("RIGHT", results, "CENTER", -3, 0)
    roll.reroll:SetScript("OnClick", function() DoRoll(true) end)

    roll.announce = W.Button(panel, "Announce", 10, 24)
    roll.announce:SetPoint("TOPRIGHT", results, "BOTTOMRIGHT", 0, -8)
    roll.announce:SetPoint("LEFT", results, "CENTER", 3, 0)
    roll.announce:SetScript("OnClick", function() ns.Announce() end)

    roll.message = W.Text(panel, 11, "critical")
    roll.message:SetPoint("TOPLEFT", roll.reroll, "BOTTOMLEFT", 0, -10)
    roll.message:SetPoint("RIGHT", panel, "RIGHT", -10, 0)
    roll.message:SetJustifyH("LEFT")
end

-----------------------------------------------------------------------
-- Pages
-----------------------------------------------------------------------

local function BuildRollPage(host)
    ns.BuildClassData()

    local roster = W.Panel(host)
    roster:SetPoint("TOPLEFT", 8, -4)
    roster:SetPoint("BOTTOMLEFT", 8, 8)
    roster:SetWidth(ROSTER_W)
    BuildRoster(roster)

    local result = W.Panel(host)
    result:SetPoint("TOPRIGHT", -8, -4)
    result:SetPoint("BOTTOMRIGHT", -8, 8)
    result:SetWidth(RESULT_W)
    BuildResult(result)

    local specs = W.Panel(host)
    specs:SetPoint("TOPLEFT", roster, "TOPRIGHT", GAP, 0)
    specs:SetPoint("BOTTOMRIGHT", result, "BOTTOMLEFT", -GAP, 0)
    BuildSpecs(specs)

    UI.Refresh()
end

-- Grey explanation under a control; x defaults to lining up with a toggle's label.
local function Note(parent, text, anchor, x, y)
    local fs = W.Text(parent, 11, "textDim")
    fs:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", x or 37, y or -4)
    fs:SetPoint("RIGHT", parent, "RIGHT", -20, 0)
    fs:SetJustifyH("LEFT")
    fs:SetText(text)
    return fs
end

local function BuildSettingsPage(host)
    local s = ns.db.settings

    local rolling = W.Section(host, "Rolling")
    rolling:SetPoint("TOPLEFT", 12, -10)
    rolling:SetPoint("TOPRIGHT", -12, -10)

    local rotation = W.Toggle(host, "Rotate roles", function(on) s.rotation = on end)
    rotation:SetPoint("TOPLEFT", rolling, "BOTTOMLEFT", 2, -14)
    rotation:SetChecked(s.rotation)
    local n1 = Note(host, "Makes it much less likely that anyone gets the same role as last game. "
        .. "Re-rolling doesn't count as a game.", rotation)

    local auto = W.Toggle(host, "Announce to chat after every roll", function(on) s.autoAnnounce = on end)
    auto:SetPoint("TOPLEFT", n1, "BOTTOMLEFT", -37, -14)
    auto:SetChecked(s.autoAnnounce)
    local n2 = Note(host, "Posts each result to party chat. The Announce button works either way.", auto)

    local LST = Theme()
    if not LST then return end
    local theme = W.Section(host, "Theme")
    theme:SetPoint("TOPLEFT", n2, "BOTTOMLEFT", -39, -22)
    theme:SetPoint("RIGHT", host, "RIGHT", -12, 0)

    local buttons, prev = {}, nil
    local function Mark()
        for key, b in pairs(buttons) do b:SetActive(key == LST:PresetKey()) end
    end
    for _, key in ipairs(LST.ORDER) do
        local preset = LST.PRESETS[key]
        local b = W.Button(host, preset.name, 104, 24)
        if prev then
            b:SetPoint("LEFT", prev, "RIGHT", 6, 0)
        else
            b:SetPoint("TOPLEFT", theme, "BOTTOMLEFT", 2, -12)
        end
        b:HookScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
            GameTooltip:SetText(preset.name, 1, 1, 1)
            GameTooltip:AddLine(preset.tip, nil, nil, nil, true)
            GameTooltip:Show()
        end)
        b:HookScript("OnLeave", function() GameTooltip:Hide() end)
        b:SetScript("OnClick", function()
            local from = LST:PresetKey()
            if from == key then return end
            LST:SetPreset(key)
            Mark()
            if LST:NeedsReload(from, key) then
                ns.Print("theme set to " .. preset.name .. ". /reload to see it fully.")
            end
        end)
        buttons[key] = b
        prev = b
    end
    Mark()
    Note(host, "One theme covers RoleRoulette, SquizzFrames and Squizzumables. "
        .. "The accent changes at once; the rest after a /reload.", buttons[LST.ORDER[1]], 0, -10)
end

-----------------------------------------------------------------------
-- Window
-----------------------------------------------------------------------

local function SaveWindow()
    if not win then return end
    local f = win.frame
    local point, _, relPoint, x, y = f:GetPoint(1)
    if not point then return end
    ns.db.window = {point = point, relPoint = relPoint, x = x, y = y,
                    w = f:GetWidth(), h = f:GetHeight()}
end

local function RestoreWindow()
    local p = ns.db.window
    if type(p) ~= "table" or not p.point then return end
    local f = win.frame
    f:ClearAllPoints()
    f:SetPoint(p.point, UIParent, p.relPoint or p.point, p.x or 0, p.y or 0)
    if p.w and p.h then f:SetSize(p.w, p.h) end
end

-- Pages, sidebar and search entries. Done at PLAYER_LOGIN, after every addon
-- has loaded, so RoleRoulette comes after SquizzFrames and Squizzumables in
-- the combined /squizz window rather than ahead of them.
function UI.Register()
    local S = Shell()
    if not S then return end
    S:RegisterAddon(ADDON_ID, {title = "RoleRoulette", groups = {
        {label = "Group", pages = {
            {key = "roll", label = "Roll", layout = "fill",
             subtitle = "Who tanks, who heals, and what everyone plays",
             build = BuildRollPage, onShow = function() UI.Refresh() end},
        }},
        {label = "General", pages = {
            {key = "settings", label = "Settings", layout = "scroll", height = 320,
             subtitle = "Rotation, announcing and theme",
             build = BuildSettingsPage},
        }},
    }})
    S:RegisterOpener(ADDON_ID, {
        open = function(pageId, show)
            local w = UI.Create()
            if w and show then w:Open(pageId) end
            return w
        end,
    })
    local LST = Theme()
    if LST then
        LST:RegisterCallback(function()
            W.RefreshAccent()
            if win then win:RefreshAccent() end
        end)
    end
end

-- The window, built once and out of combat. nil while it has to wait.
function UI.Create()
    if win then return win end
    local S = Shell()
    if not S then
        ns.Print("LibSquizzShell-1.0 is missing, so the window can't open.")
        return nil
    end
    if InCombatLockdown() then return nil end
    win = S:CreateWindow({
        name = "RoleRouletteFrame",
        addons = {ADDON_ID},
        title = "ROLEROULETTE",
        subtitle = "Random roles and specs",
        width = 960, height = 600,
        minWidth = 900, minHeight = 520,
        combat = "fade",
        onHide = SaveWindow,
    })
    RestoreWindow()
    win.titleBar:HookScript("OnDragStop", SaveWindow)
    win:BuildAllPages()
    return win
end

function UI.Refresh()
    UI.RefreshRoster()
    UI.RefreshSpecs()
    UI.RefreshResult()
end

function UI.Toggle(pageId)
    local w = UI.Create()
    if w then
        w:Toggle(pageId)
    elseif InCombatLockdown() then
        ns.Print("the window opens when combat ends.")
        ns.OutOfCombat("open", function() UI.Toggle(pageId) end)
    end
end
