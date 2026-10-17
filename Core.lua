-- RoleRoulette: Core
--
-- Two halves, in this order:
--
--   1. The randomizer (ns.Randomizer). Pure Lua 5.1 -- no WoW API at all -- so
--      test_randomizer.lua can dofile() this file outside the game.
--   2. Everything that needs the game: class/spec data, SavedVariables, the
--      roster, announcing and the slash command. Guarded by a CreateFrame
--      check, so plain Lua stops before reaching it.

local addonName, ns = ...
addonName = addonName or "RoleRoulette"
ns = ns or {}

-----------------------------------------------------------------------
-- 1. Randomizer (pure Lua)
-----------------------------------------------------------------------

local R = {}
ns.Randomizer = R

R.ORDER = {"TANK", "HEALER", "DAMAGER"}
R.ROLE_LABEL = {TANK = "Tank", HEALER = "Healer", DAMAGER = "DPS"}
R.GROUP_SIZE = 5

-- A dungeon group's slots. Fewer than five people get a slice of it -- two
-- friends picking specs before queueing can be tank + DPS, or two DPS, but
-- never two tanks -- and the group finder fills the rest. Five fill it exactly:
-- 1 tank, 1 healer, 3 DPS.
R.CAPS = {TANK = 1, HEALER = 1, DAMAGER = 3}

-- With rotation weighting on, an assignment's weight is multiplied by this
-- once for every member who would get the same role as last time. 0.2 makes a
-- full repeat 1/3125 as likely as a full rotation, while never ruling one out
-- -- some rosters (one healer) cannot rotate at all.
R.REPEAT_FACTOR = 0.2

-- "A", "A and B", "A, B and C"
local function JoinNames(list)
    local n = #list
    if n == 0 then return "" end
    if n == 1 then return list[1] end
    return table.concat(list, ", ", 1, n - 1) .. " and " .. list[n]
end
R.JoinNames = JoinNames

local function Fail(code, message)
    return {ok = false, code = code, message = message}
end

-- 1..n from a [0,1) source. Injectable so the tests can seed or script it.
local function Pick(random, n)
    local i = math.floor(random() * n) + 1
    if i > n then i = n end
    return i
end

-- Which roles a member's pool covers, as a set. Specs whose role is unknown
-- (removed in a patch, say) are ignored rather than trusted.
function R.RolesFor(member, roleOf)
    local roles = {}
    for _, entry in ipairs(member.specs or {}) do
        local role = roleOf[entry.specID]
        if role then roles[role] = true end
    end
    return roles
end

-- The members flagged available, in roster order.
function R.Available(roster)
    local out = {}
    for _, m in ipairs(roster or {}) do
        if m.available then out[#out + 1] = m end
    end
    return out
end

-- Every valid assignment, as a list of role arrays ({[i] = role}): each
-- person in a role their pool covers and no role over its R.CAPS. The caps
-- add up to five, so five people always come out exactly 1/1/3. At most
-- 3^5 = 243 candidates, so brute force.
function R.Enumerate(roles)
    local n = #roles
    local valid, current, used = {}, {}, {TANK = 0, HEALER = 0, DAMAGER = 0}
    local function Walk(i)
        if i > n then
            local copy = {}
            for k = 1, n do copy[k] = current[k] end
            valid[#valid + 1] = copy
            return
        end
        for _, role in ipairs(R.ORDER) do
            if roles[i][role] and used[role] < R.CAPS[role] then
                used[role] = used[role] + 1
                current[i] = role
                Walk(i + 1)
                used[role] = used[role] - 1
            end
        end
    end
    Walk(1)
    return valid
end

-- Why no valid assignment exists, most specific reason first.
function R.Diagnose(members, roles)
    local empty, tanks, healers, nonDps = {}, {}, {}, {}
    local only = {TANK = {}, HEALER = {}, DAMAGER = {}}  -- pools of one role
    for i, m in ipairs(members) do
        local r = roles[i]
        if not (r.TANK or r.HEALER or r.DAMAGER) then empty[#empty + 1] = m.name end
        if r.TANK then tanks[#tanks + 1] = m.name end
        if r.HEALER then healers[#healers + 1] = m.name end
        if not r.DAMAGER then nonDps[#nonDps + 1] = m.name end
        local count, which = 0, nil
        for role in pairs(r) do count, which = count + 1, role end
        if count == 1 then table.insert(only[which], m.name) end
    end

    if #empty > 0 then
        return Fail("EMPTY_POOL", JoinNames(empty)
            .. (#empty == 1 and " has" or " have") .. " no specs ticked.")
    end
    if #only.TANK > 1 then
        return Fail("TOO_MANY_TANKS", JoinNames(only.TANK)
            .. " can only tank, and a group has room for one tank.")
    end
    if #only.HEALER > 1 then
        return Fail("TOO_MANY_HEALERS", JoinNames(only.HEALER)
            .. " can only heal, and a group has room for one healer.")
    end
    if #nonDps > 2 then
        return Fail("TOO_FEW_DPS", JoinNames(nonDps)
            .. " have no DPS spec, but a group has room for just one tank and one healer.")
    end
    -- A full group needs both a tank and a healer; a smaller one does not.
    if #members == R.GROUP_SIZE then
        if #tanks == 0 then
            return Fail("NO_TANK", "Nobody has a tank spec in their pool.")
        end
        if #healers == 0 then
            return Fail("NO_HEALER", "Nobody has a healer spec in their pool.")
        end
        if #tanks == 1 and #healers == 1 and tanks[1] == healers[1] then
            return Fail("SAME_TANK_HEALER", tanks[1]
                .. " is the only possible tank and also the only possible healer.")
        end
    end
    if #only.DAMAGER > R.CAPS.DAMAGER then
        return Fail("TOO_MANY_DPS", JoinNames(only.DAMAGER)
            .. " can only DPS, and a group has room for three.")
    end
    return Fail("NO_COMBINATION",
        "No combination fits 1 tank, 1 healer and 3 DPS with these pools.")
end

-- Roll a group.
--
--   roster   the full roster; only members with .available are used
--   roleOf   [specID] = "TANK" | "HEALER" | "DAMAGER"
--   opts     .random     () -> [0,1), default math.random
--            .weighting  true to weight against repeating .last
--            .last       [name] = role from the previous game
--            .factor     override for R.REPEAT_FACTOR
--
-- Returns {ok = true, assignment = {{name, role, classID, specID}, ...}}
-- ordered tank, healer, then DPS in roster order -- or {ok = false, code,
-- message}.
function R.Roll(roster, roleOf, opts)
    opts = opts or {}
    local random = opts.random or math.random
    local members = R.Available(roster)

    if #members == 0 then
        return Fail("WRONG_COUNT", "Switch on at least one person who's playing.")
    end
    if #members > R.GROUP_SIZE then
        return Fail("WRONG_COUNT", string.format(
            "A group has room for %d, and %d are switched on.", R.GROUP_SIZE, #members))
    end

    local roles = {}
    for i, m in ipairs(members) do roles[i] = R.RolesFor(m, roleOf) end

    local valid = R.Enumerate(roles)
    if #valid == 0 then return R.Diagnose(members, roles) end

    local function RoleAt(a, i) return a[i] end

    -- Weighted pick. Unweighted is the same code with every weight 1.
    local factor = opts.factor or R.REPEAT_FACTOR
    local last = opts.weighting and opts.last or nil
    local weights, total = {}, 0
    for k, a in ipairs(valid) do
        local w = 1
        if last then
            for i, m in ipairs(members) do
                if last[m.name] == RoleAt(a, i) then w = w * factor end
            end
        end
        weights[k] = w
        total = total + w
    end
    local x = random() * total
    local chosen = valid[#valid]
    for k, a in ipairs(valid) do
        x = x - weights[k]
        if x < 0 then chosen = a break end
    end

    -- A spec for each person from the part of their pool matching the role.
    local byRole = {TANK = {}, HEALER = {}, DAMAGER = {}}
    for i, m in ipairs(members) do
        local role = RoleAt(chosen, i)
        local options = {}
        for _, entry in ipairs(m.specs) do
            if roleOf[entry.specID] == role then options[#options + 1] = entry end
        end
        local spec = options[Pick(random, #options)]
        local list = byRole[role]
        list[#list + 1] = {name = m.name, role = role,
                           classID = spec.classID, specID = spec.specID}
    end

    local assignment = {}
    for _, role in ipairs(R.ORDER) do
        for _, e in ipairs(byRole[role]) do assignment[#assignment + 1] = e end
    end
    return {ok = true, assignment = assignment}
end

-- [name] = role, for feeding a result back in as opts.last.
function R.RolesByName(assignment)
    local map = {}
    for _, e in ipairs(assignment or {}) do map[e.name] = e.role end
    return map
end

-- Outside the game: stop here and hand the randomizer to the test script.
if not CreateFrame then return ns end

-----------------------------------------------------------------------
-- 2. In game
-----------------------------------------------------------------------

_G.RoleRoulette = ns  -- for /dump and other addons; nothing here relies on it

local PREFIX = "|cffffd100RoleRoulette:|r "
function ns.Print(msg) print(PREFIX .. msg) end

local DEFAULTS = {
    roster = {},
    history = {},
    settings = {rotation = true, autoAnnounce = false},
    -- window = {point, relPoint, x, y, w, h}: written by UI.lua when the
    -- window is moved or closed.
}

local function FillDefaults(dst, src)
    for k, v in pairs(src) do
        if dst[k] == nil then
            if type(v) == "table" then
                dst[k] = {}
                FillDefaults(dst[k], v)
            else
                dst[k] = v
            end
        elseif type(v) == "table" and type(dst[k]) == "table" then
            FillDefaults(dst[k], v)
        end
    end
end

-----------------------------------------------------------------------
-- Class and spec data, read from the game rather than hardcoded
-----------------------------------------------------------------------

ns.Classes = {}   -- { {classID, name, file, specs = { {specID, name, icon, role} }} }
ns.SpecInfo = {}  -- [specID] = {classID, name, icon, role}
ns.RoleOf = {}    -- [specID] = role, the randomizer's input

-- 12.1 moved this into C_SpecializationInfo; the bare global is the fallback.
local GetNumSpecsForClass = (C_SpecializationInfo and C_SpecializationInfo.GetNumSpecializationsForClassID)
    or GetNumSpecializationsForClassID

function ns.BuildClassData()
    if #ns.Classes > 0 then return end
    if not (GetNumClasses and GetClassInfo and GetNumSpecsForClass
            and GetSpecializationInfoForClassID) then
        ns.Print("the class/spec API is missing on this client, so the spec list is empty.")
        return
    end
    for classID = 1, GetNumClasses() do
        -- Class IDs have had gaps in the past, so a nil here is skipped.
        local className, classFile, id = GetClassInfo(classID)
        if className and classFile then
            local class = {classID = id or classID, name = className, file = classFile, specs = {}}
            for i = 1, GetNumSpecsForClass(class.classID) or 0 do
                local specID, specName, _, icon, role = GetSpecializationInfoForClassID(class.classID, i)
                if specID and specID ~= 0 and role then
                    class.specs[#class.specs + 1] = {specID = specID, name = specName, icon = icon, role = role}
                    ns.SpecInfo[specID] = {classID = class.classID, name = specName, icon = icon, role = role}
                    ns.RoleOf[specID] = role
                end
            end
            if #class.specs > 0 then ns.Classes[#ns.Classes + 1] = class end
        end
    end
    table.sort(ns.Classes, function(a, b) return a.name < b.name end)
end

function ns.ClassByID(classID)
    for _, c in ipairs(ns.Classes) do
        if c.classID == classID then return c end
    end
end

-- Class colour as r, g, b.
function ns.ClassColor(classID)
    local c = classID and ns.ClassByID(classID)
    if not c then return 1, 1, 1 end
    local col = C_ClassColor and C_ClassColor.GetClassColor(c.file)
        or (RAID_CLASS_COLORS and RAID_CLASS_COLORS[c.file])
    if col then return col.r, col.g, col.b end
    return 1, 1, 1
end

-- Role icon on a texture: Blizzard's own micro role atlas, or the old LFG
-- role sheet if that helper is ever missing.
local ROLE_COORDS = {
    TANK    = {0, 19 / 64, 22 / 64, 41 / 64},
    HEALER  = {20 / 64, 39 / 64, 1 / 64, 20 / 64},
    DAMAGER = {20 / 64, 39 / 64, 22 / 64, 41 / 64},
}
function ns.SetRoleIcon(tex, role)
    local atlas = GetMicroIconForRole and GetMicroIconForRole(role)
    if atlas and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas) then
        tex:SetAtlas(atlas)
        tex:SetTexCoord(0, 1, 0, 1)
    else
        tex:SetTexture("Interface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES")
        local c = ROLE_COORDS[role] or ROLE_COORDS.DAMAGER
        tex:SetTexCoord(c[1], c[2], c[3], c[4])
    end
end

-----------------------------------------------------------------------
-- Combat: frames are created and reshaped only out of combat
-----------------------------------------------------------------------

local pending = {}  -- [key] = fn, newest wins
function ns.OutOfCombat(key, fn)
    if InCombatLockdown() then
        pending[key] = fn
        return false
    end
    fn()
    return true
end

-----------------------------------------------------------------------
-- Roster
-----------------------------------------------------------------------

local function Trim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end

function ns.FindMember(name)
    local lower = name:lower()
    for i, m in ipairs(ns.db.roster) do
        if m.name:lower() == lower then return m, i end
    end
end

-- Returns the member, or nil and a reason.
function ns.AddMember(name)
    if type(name) ~= "string" then return nil, "No name given." end
    name = Trim(name)
    if name == "" then return nil, "Type a name first." end
    if #name > 48 then return nil, "That name is too long." end
    if ns.FindMember(name) then return nil, name .. " is already on the roster." end
    local m = {name = name, available = true, specs = {}}
    ns.db.roster[#ns.db.roster + 1] = m
    return m
end

function ns.RemoveMember(member)
    for i, m in ipairs(ns.db.roster) do
        if m == member then table.remove(ns.db.roster, i) return end
    end
end

function ns.HasSpec(member, specID)
    for _, e in ipairs(member.specs) do
        if e.specID == specID then return true end
    end
    return false
end

function ns.SetSpec(member, classID, specID, on)
    for i, e in ipairs(member.specs) do
        if e.specID == specID then
            if not on then table.remove(member.specs, i) end
            return
        end
    end
    if on then member.specs[#member.specs + 1] = {classID = classID, specID = specID} end
end

-- Adds everyone in the current party. Returns added, skipped (already on the
-- roster), unreadable counts.
function ns.ImportParty()
    local added, skipped, unreadable = 0, 0, 0
    local units = {"player"}
    if IsInGroup() and not IsInRaid() then
        for i = 1, GetNumSubgroupMembers() do units[#units + 1] = "party" .. i end
    end
    for _, unit in ipairs(units) do
        local name = UnitName(unit)
        -- Names can be secret on 12.1 when a unit's identity is restricted;
        -- those are skipped rather than compared or stored.
        if not name or not canaccessvalue(name) then
            unreadable = unreadable + 1
        elseif name == UNKNOWNOBJECT then
            unreadable = unreadable + 1
        elseif ns.FindMember(name) then
            skipped = skipped + 1
        else
            ns.AddMember(name)
            added = added + 1
        end
    end
    return added, skipped, unreadable
end

-----------------------------------------------------------------------
-- Rolling and history
-----------------------------------------------------------------------
--
-- history.last      the result on screen, saved across sessions
-- history.baseline  [name] = role, what rotation weighting steers away from
--
-- Randomize takes the result on screen as the game just played and makes it
-- the baseline. Re-roll keeps the baseline, so throwing a result away does
-- not count as having played it.

function ns.Roll(isReroll)
    ns.BuildClassData()
    local h = ns.db.history
    if not isReroll or not h.baseline then
        h.baseline = R.RolesByName(h.last)
    end
    local result = R.Roll(ns.db.roster, ns.RoleOf, {
        weighting = ns.db.settings.rotation,
        last = h.baseline,
    })
    if result.ok then
        h.last = result.assignment
        if ns.db.settings.autoAnnounce then ns.Announce() end
    end
    return result
end

local function ResultLines(assignment)
    local lines = {}
    for _, e in ipairs(assignment) do
        local spec = ns.SpecInfo[e.specID]
        local class = ns.ClassByID(e.classID)
        lines[#lines + 1] = string.format("%s: %s - %s %s", R.ROLE_LABEL[e.role] or e.role,
            e.name, spec and spec.name or "?", class and class.name or "")
    end
    return lines
end

local SendChat = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage

function ns.Announce()
    local last = ns.db.history.last
    if not last or #last == 0 then
        ns.Print("nothing to announce yet - press Randomize first.")
        return
    end
    local lines = ResultLines(last)

    local channel
    if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then
        channel = "INSTANCE_CHAT"
    elseif IsInGroup() then
        channel = "PARTY"
    end
    if channel and SendChat then
        -- Chat from addons can be refused in restricted content; fall back to
        -- printing rather than losing the result.
        local ok = pcall(SendChat, "RoleRoulette:", channel)
        if ok then
            for _, line in ipairs(lines) do pcall(SendChat, line, channel) end
            return
        end
        ns.Print("couldn't post to group chat here, so here it is:")
    else
        ns.Print("you're not in a party, so here it is:")
    end
    for _, line in ipairs(lines) do print("  " .. line) end
end

-----------------------------------------------------------------------
-- Events and slash command
-----------------------------------------------------------------------

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 == addonName then
        RoleRouletteDB = RoleRouletteDB or {}
        FillDefaults(RoleRouletteDB, DEFAULTS)
        ns.db = RoleRouletteDB
        RoleRouletteDB.position = nil  -- the 1.0 window's, before the shared window
        -- Join the theme shared with SquizzFrames and Squizzumables. No seed:
        -- RoleRoulette never had a look of its own to keep, so whatever the
        -- other two have chosen wins, and alone it gets the default.
        local LST = LibStub and LibStub("LibSquizzTheme-1.0", true)
        if LST then LST:Attach(RoleRouletteDB, nil, 0) end
    elseif event == "PLAYER_LOGIN" then
        ns.BuildClassData()
        if ns.UI then ns.UI.Register() end
    elseif event == "PLAYER_REGEN_ENABLED" then
        local queued = pending
        pending = {}
        for _, fn in pairs(queued) do fn() end
    end
end)

SLASH_ROLEROULETTE1 = "/rr"
SLASH_ROLEROULETTE2 = "/roleroulette"
SlashCmdList.ROLEROULETTE = function(msg)
    msg = Trim(msg or ""):lower()
    if msg == "roll" then
        local r = ns.Roll(false)
        if not r.ok then ns.Print(r.message) end
        if ns.UI then ns.UI.Refresh() end
    elseif msg == "announce" then
        ns.Announce()
    elseif msg == "help" then
        ns.Print("/rr opens the window. /rr roll randomizes, /rr announce posts the last result.")
    elseif ns.UI then
        ns.UI.Toggle()
    end
end
