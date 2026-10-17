-- RoleRoulette: UI
--
-- The main window (roster on the left, result on the right) and the spec
-- picker that opens beside it for the selected member. Built on first open,
-- never in combat: creating or resizing frames waits for PLAYER_REGEN_ENABLED
-- through ns.OutOfCombat. Plain values (text, checks, colours) still update
-- in combat.

local _, ns = ...
local R = ns.Randomizer

local UI = {}
ns.UI = UI

local ROW_HEIGHT = 24
local MAIN_W, MAIN_H = 620, 470
local PICKER_W = 460

local BACKDROP = {
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = {left = 11, right = 12, top = 12, bottom = 11},
}

local main, picker
local selected        -- the member whose specs the picker shows
local rosterRows = {}
local resultRows = {}
local message         -- red text under the result: errors, import counts

-----------------------------------------------------------------------
-- Helpers
-----------------------------------------------------------------------

local function MakeWindow(name, w, h, title)
    local f = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
    f:SetSize(w, h)
    f:SetBackdrop(BACKDROP)
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f.title = f:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    f.title:SetPoint("TOP", 0, -18)
    f.title:SetText(title)
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -6, -6)
    return f
end

local function Button(parent, text, w, h)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(w, h or 24)
    b:SetText(text)
    return b
end

local function Check(parent, size)
    local c = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    c:SetSize(size or 24, size or 24)
    return c
end

local function Label(parent, template, text)
    local fs = parent:CreateFontString(nil, "ARTWORK", template or "GameFontHighlight")
    if text then fs:SetText(text) end
    return fs
end

local function ScrollArea(parent, w, h)
    local sf = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
    sf:SetSize(w, h)
    local child = CreateFrame("Frame", nil, sf)
    child:SetSize(w, 1)
    sf:SetScrollChild(child)
    return sf, child
end

local function SetMessage(text, r, g, b)
    if not message then return end
    message:SetText(text or "")
    message:SetTextColor(r or 1, g or 0.3, b or 0.3)
end

-----------------------------------------------------------------------
-- Roster panel
-----------------------------------------------------------------------

local function CreateRosterRow(parent, i)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(236, ROW_HEIGHT)
    row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_HEIGHT)

    row.available = Check(row, 22)
    row.available:SetPoint("LEFT", 0, 0)
    row.available:SetScript("OnClick", function(self)
        if row.member then
            row.member.available = self:GetChecked() and true or false
            UI.RefreshCount()
        end
    end)

    -- The name is a button: clicking it opens the spec picker.
    row.name = CreateFrame("Button", nil, row)
    row.name:SetSize(122, ROW_HEIGHT)
    row.name:SetPoint("LEFT", row.available, "RIGHT", 2, 0)
    row.name.text = Label(row.name, "GameFontHighlight")
    row.name.text:SetPoint("LEFT", 2, 0)
    row.name.text:SetPoint("RIGHT", -2, 0)
    row.name.text:SetJustifyH("LEFT")
    row.name.text:SetWordWrap(false)
    row.name:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    row.selectedTex = row.name:CreateTexture(nil, "BACKGROUND")
    row.selectedTex:SetAllPoints()
    row.selectedTex:SetColorTexture(1, 0.82, 0, 0.18)
    row.name:SetScript("OnClick", function()
        if row.member then UI.Select(row.member) end
    end)

    -- Which roles their pool covers; dimmed when not covered.
    row.roles = {}
    local prev = row.name
    for _, role in ipairs(R.ORDER) do
        local t = row:CreateTexture(nil, "ARTWORK")
        t:SetSize(16, 16)
        t:SetPoint("LEFT", prev, "RIGHT", 2, 0)
        ns.SetRoleIcon(t, role)
        row.roles[role] = t
        prev = t
    end

    row.remove = CreateFrame("Button", nil, row, "UIPanelCloseButton")
    row.remove:SetSize(22, 22)
    row.remove:SetPoint("LEFT", prev, "RIGHT", 2, 0)
    row.remove:SetScript("OnClick", function()
        local m = row.member
        if not m then return end
        ns.RemoveMember(m)
        if selected == m then UI.Select(nil) end
        UI.RefreshRoster()
    end)
    return row
end

local function PaintRosterRow(row, m)
    row.member = m
    row.available:SetChecked(m.available)
    row.name.text:SetText(m.name)
    local roles = R.RolesFor(m, ns.RoleOf)
    for role, t in pairs(row.roles) do
        t:SetDesaturated(not roles[role])
        t:SetAlpha(roles[role] and 1 or 0.25)
    end
    row.selectedTex:SetShown(selected == m)
    row:Show()
end

function UI.RefreshCount()
    if not main then return end
    local n = #R.Available(ns.db.roster)
    local color = (n == R.GROUP_SIZE) and "|cff40ff40" or "|cffff6060"
    main.count:SetText(string.format("Available: %s%d|r / %d", color, n, R.GROUP_SIZE))
end

function UI.RefreshRoster()
    if not main then return end
    local roster = ns.db.roster
    -- New rows are new frames, so they wait for combat to end.
    if #roster > #rosterRows and InCombatLockdown() then
        ns.OutOfCombat("roster", UI.RefreshRoster)
        return
    end
    for i = #rosterRows + 1, #roster do
        rosterRows[i] = CreateRosterRow(main.rosterChild, i)
    end
    for i, row in ipairs(rosterRows) do
        if roster[i] then PaintRosterRow(row, roster[i]) else row.member = nil row:Hide() end
    end
    main.rosterChild:SetHeight(math.max(1, #roster * ROW_HEIGHT))
    main.empty:SetShown(#roster == 0)
    UI.RefreshCount()
end

local function AddFromBox()
    local box = main.nameBox
    local m, err = ns.AddMember(box:GetText())
    if not m then
        SetMessage(err)
        return
    end
    box:SetText("")
    SetMessage("")
    UI.RefreshRoster()
    UI.Select(m)
end

-----------------------------------------------------------------------
-- Result panel
-----------------------------------------------------------------------

local function CreateResultRow(parent, i)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(300, 40)
    row:SetPoint("TOPLEFT", 0, -(i - 1) * 44)

    row.role = row:CreateTexture(nil, "ARTWORK")
    row.role:SetSize(28, 28)
    row.role:SetPoint("LEFT", 0, 0)

    row.spec = row:CreateTexture(nil, "ARTWORK")
    row.spec:SetSize(32, 32)
    row.spec:SetPoint("LEFT", row.role, "RIGHT", 6, 0)
    row.spec:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    row.who = Label(row, "GameFontNormalLarge")
    row.who:SetPoint("TOPLEFT", row.spec, "TOPRIGHT", 8, -1)
    row.who:SetJustifyH("LEFT")

    row.detail = Label(row, "GameFontHighlightSmall")
    row.detail:SetPoint("BOTTOMLEFT", row.spec, "BOTTOMRIGHT", 8, 1)
    row.detail:SetTextColor(0.8, 0.8, 0.8)
    return row
end

function UI.RefreshResult()
    if not main then return end
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
            row.detail:SetText(string.format("%s %s", spec and spec.name or "Unknown spec",
                class and class.name or ""))
            row:Show()
        else
            row:Hide()
        end
    end
    main.placeholder:SetShown(not has)
    main.reroll:SetEnabled(has)
    main.announce:SetEnabled(has)
end

local function DoRoll(isReroll)
    local r = ns.Roll(isReroll)
    if r.ok then SetMessage("") else SetMessage(r.message) end
    UI.RefreshResult()
end

-----------------------------------------------------------------------
-- Main window
-----------------------------------------------------------------------

local function SavePosition(f)
    local point, _, relPoint, x, y = f:GetPoint(1)
    ns.db.position = {point, relPoint, x, y}
end

local function RestorePosition(f)
    f:ClearAllPoints()
    local p = ns.db.position
    if type(p) == "table" and p[1] then
        f:SetPoint(p[1], UIParent, p[2], p[3], p[4])
    else
        f:SetPoint("CENTER", -PICKER_W / 2, 40)
    end
end

local function CreateMain()
    main = MakeWindow("RoleRouletteFrame", MAIN_W, MAIN_H, "Role Roulette")
    main:SetMovable(true)
    main:RegisterForDrag("LeftButton")
    main:SetScript("OnDragStart", function(self) self:StartMoving() end)
    main:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SavePosition(self)
    end)
    main:SetScript("OnHide", function() if picker then picker:Hide() end end)
    RestorePosition(main)
    tinsert(UISpecialFrames, "RoleRouletteFrame") -- Escape closes it

    -- Left: roster
    local rosterTitle = Label(main, "GameFontNormal", "Roster")
    rosterTitle:SetPoint("TOPLEFT", 24, -48)

    main.count = Label(main, "GameFontHighlightSmall")
    main.count:SetPoint("LEFT", rosterTitle, "RIGHT", 10, 0)

    local box = CreateFrame("EditBox", nil, main, "InputBoxTemplate")
    box:SetSize(150, 22)
    box:SetPoint("TOPLEFT", rosterTitle, "BOTTOMLEFT", 6, -8)
    box:SetAutoFocus(false)
    box:SetMaxLetters(48)
    box:SetScript("OnEnterPressed", AddFromBox)
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    main.nameBox = box

    local add = Button(main, "Add", 76, 22)
    add:SetPoint("LEFT", box, "RIGHT", 6, 0)
    add:SetScript("OnClick", AddFromBox)

    local import = Button(main, "Import Party", 238, 22)
    import:SetPoint("TOPLEFT", box, "BOTTOMLEFT", -6, -6)
    import:SetScript("OnClick", function()
        local added, skipped, unreadable = ns.ImportParty()
        local parts = {added .. " added"}
        if skipped > 0 then parts[#parts + 1] = skipped .. " already on the roster" end
        if unreadable > 0 then parts[#parts + 1] = unreadable .. " name(s) unreadable right now" end
        SetMessage("Import: " .. table.concat(parts, ", ") .. ".", 0.6, 0.9, 1)
        UI.RefreshRoster()
    end)

    local sf, child = ScrollArea(main, 236, 262)
    sf:SetPoint("TOPLEFT", import, "BOTTOMLEFT", 0, -8)
    main.rosterChild = child

    main.empty = Label(main, "GameFontDisableSmall",
        "Add people by name or import\nyour party, then click a name\nto pick their specs.")
    main.empty:SetPoint("TOP", sf, "TOP", 0, -20)

    -- Divider
    local line = main:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(1, 1, 1, 0.12)
    line:SetSize(1, MAIN_H - 80)
    line:SetPoint("TOPLEFT", 290, -44)

    -- Right: randomize and the result
    local randomize = Button(main, "Randomize!", 300, 40)
    randomize:SetPoint("TOPLEFT", 304, -48)
    randomize:SetNormalFontObject("GameFontNormalLarge")
    randomize:SetHighlightFontObject("GameFontHighlightLarge")
    randomize:SetScript("OnClick", function() DoRoll(false) end)

    local results = CreateFrame("Frame", nil, main)
    results:SetSize(300, 5 * 44)
    results:SetPoint("TOPLEFT", randomize, "BOTTOMLEFT", 0, -12)
    for i = 1, R.GROUP_SIZE do resultRows[i] = CreateResultRow(results, i) end

    main.placeholder = Label(main, "GameFontDisable",
        "Tick five available people,\nthen press Randomize.")
    main.placeholder:SetPoint("CENTER", results, "CENTER")

    main.reroll = Button(main, "Re-roll", 146, 24)
    main.reroll:SetPoint("TOPLEFT", results, "BOTTOMLEFT", 0, -6)
    main.reroll:SetScript("OnClick", function() DoRoll(true) end)

    main.announce = Button(main, "Announce", 146, 24)
    main.announce:SetPoint("LEFT", main.reroll, "RIGHT", 8, 0)
    main.announce:SetScript("OnClick", function() ns.Announce() end)

    message = Label(main, "GameFontNormalSmall")
    message:SetPoint("TOPLEFT", main.reroll, "BOTTOMLEFT", 0, -8)
    message:SetWidth(300)
    message:SetJustifyH("LEFT")

    -- Settings, along the bottom of the right column
    local rotation = Check(main, 22)
    rotation:SetPoint("BOTTOMLEFT", 300, 40)
    local rotationLabel = Label(main, "GameFontHighlightSmall", "Rotate roles (avoid repeats from last game)")
    rotationLabel:SetPoint("LEFT", rotation, "RIGHT", 2, 0)
    rotation:SetScript("OnClick", function(self) ns.db.settings.rotation = self:GetChecked() and true or false end)
    main.rotation = rotation

    local auto = Check(main, 22)
    auto:SetPoint("BOTTOMLEFT", 300, 18)
    local autoLabel = Label(main, "GameFontHighlightSmall", "Announce to chat after every roll")
    autoLabel:SetPoint("LEFT", auto, "RIGHT", 2, 0)
    auto:SetScript("OnClick", function(self) ns.db.settings.autoAnnounce = self:GetChecked() and true or false end)
    main.auto = auto
end

-----------------------------------------------------------------------
-- Spec picker
-----------------------------------------------------------------------

local specChecks = {}  -- [specID] = checkbutton

local function CreatePicker()
    picker = MakeWindow("RoleRoulettePicker", PICKER_W, MAIN_H, "Specs")
    picker:SetPoint("TOPLEFT", main, "TOPRIGHT", -4, 0)
    picker:SetScript("OnHide", function()
        selected = nil
        UI.RefreshRoster()
    end)

    local hint = Label(picker, "GameFontHighlightSmall", "Tick everything this person is willing to play.")
    hint:SetPoint("TOPLEFT", 26, -50)

    local clear = Button(picker, "Clear", 70, 20)
    clear:SetPoint("TOPRIGHT", -34, -44)
    clear:SetScript("OnClick", function()
        if not selected then return end
        wipe(selected.specs)
        UI.RefreshPicker()
        UI.RefreshRoster()
    end)

    local sf, child = ScrollArea(picker, PICKER_W - 64, MAIN_H - 100)
    sf:SetPoint("TOPLEFT", 22, -70)

    -- Two columns of class blocks; each block is a coloured class name over
    -- one checkbox per spec.
    local colW = (PICKER_W - 64) / 2
    local colY = {0, 0}
    for i, class in ipairs(ns.Classes) do
        local col = (i - 1) % 2 + 1
        local x, y = (col - 1) * colW, colY[col]

        local header = Label(child, "GameFontNormal", class.name)
        header:SetPoint("TOPLEFT", x + 4, -y)
        header:SetTextColor(ns.ClassColor(class.classID))
        y = y + 18

        for _, spec in ipairs(class.specs) do
            local cb = Check(child, 22)
            cb:SetPoint("TOPLEFT", x, -y)
            local role = child:CreateTexture(nil, "ARTWORK")
            role:SetSize(14, 14)
            role:SetPoint("LEFT", cb, "RIGHT", 0, 0)
            ns.SetRoleIcon(role, spec.role)
            local icon = child:CreateTexture(nil, "ARTWORK")
            icon:SetSize(18, 18)
            icon:SetPoint("LEFT", role, "RIGHT", 3, 0)
            icon:SetTexture(spec.icon)
            icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
            local name = Label(child, "GameFontHighlightSmall", spec.name)
            name:SetPoint("LEFT", icon, "RIGHT", 4, 0)

            local classID, specID = class.classID, spec.specID
            cb:SetScript("OnClick", function(self)
                if not selected then return end
                ns.SetSpec(selected, classID, specID, self:GetChecked() and true or false)
                UI.RefreshRoster()
            end)
            specChecks[specID] = cb
            y = y + 22
        end
        colY[col] = y + 10
    end
    child:SetHeight(math.max(colY[1], colY[2]))
end

function UI.RefreshPicker()
    if not (picker and selected) then return end
    picker.title:SetText("Specs for " .. selected.name)
    for specID, cb in pairs(specChecks) do
        cb:SetChecked(ns.HasSpec(selected, specID))
    end
end

function UI.Select(member)
    if not member then
        if picker then picker:Hide() end
        return
    end
    -- The picker is built the first time it is needed, out of combat.
    if not picker and InCombatLockdown() then
        ns.Print("the spec picker opens after combat.")
        ns.OutOfCombat("picker", function() UI.Select(member) end)
        return
    end
    if not picker then CreatePicker() end
    selected = member
    picker:Show()
    UI.RefreshPicker()
    UI.RefreshRoster()
end

-----------------------------------------------------------------------
-- Open / close
-----------------------------------------------------------------------

function UI.Refresh()
    if not main then return end
    main.rotation:SetChecked(ns.db.settings.rotation)
    main.auto:SetChecked(ns.db.settings.autoAnnounce)
    UI.RefreshRoster()
    UI.RefreshResult()
    UI.RefreshPicker()
end

function UI.Toggle()
    if main and main:IsShown() then
        main:Hide()
        return
    end
    if not main then
        if InCombatLockdown() then
            ns.Print("the window opens when combat ends.")
            ns.OutOfCombat("open", UI.Toggle)
            return
        end
        ns.BuildClassData()
        CreateMain()
    end
    main:Show()
    UI.Refresh()
end
