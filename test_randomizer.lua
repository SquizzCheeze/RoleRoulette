-- Standalone tests for RoleRoulette's randomizer. Plain Lua 5.1, no WoW:
--
--     lua test_randomizer.lua
--
-- Run from the addon folder (it dofile()s Core.lua next to it). Exits non-zero
-- if anything fails.

local ns = dofile("Core.lua")
local R = ns.Randomizer

-- Made-up spec IDs; the randomizer only ever sees them through roleOf.
local roleOf = {
    [1] = "TANK", [2] = "TANK",
    [3] = "HEALER", [4] = "HEALER",
    [5] = "DAMAGER", [6] = "DAMAGER", [7] = "DAMAGER",
}

local function M(name, ...)
    local specs = {}
    for i, id in ipairs({...}) do specs[i] = {classID = 1, specID = id} end
    return {name = name, available = true, specs = specs}
end

-- Seedable Park-Miller generator, so a failure reproduces exactly. Its
-- products stay below 2^53, so it is exact in Lua 5.1's doubles too.
local function Rng(seed)
    local s = seed
    return function()
        s = (s * 16807) % 2147483647
        return s / 2147483647
    end
end

local failures, checks = 0, 0
local function Check(cond, what)
    checks = checks + 1
    if not cond then
        failures = failures + 1
        print("FAIL: " .. what)
    end
end

-- Composition is 1/1/3, specs match roles, ordering is T, H, D.
local function CheckValid(result, label)
    Check(result.ok, label .. ": roll succeeded (" .. tostring(result.message) .. ")")
    if not result.ok then return end
    local a = result.assignment
    Check(#a == 5, label .. ": five people assigned")
    local count = {TANK = 0, HEALER = 0, DAMAGER = 0}
    local seen = {}
    for _, e in ipairs(a) do
        count[e.role] = count[e.role] + 1
        Check(roleOf[e.specID] == e.role, label .. ": " .. e.name .. "'s spec matches their role")
        Check(not seen[e.name], label .. ": " .. e.name .. " assigned once")
        seen[e.name] = true
    end
    Check(count.TANK == 1 and count.HEALER == 1 and count.DAMAGER == 3, label .. ": 1/1/3")
    Check(a[1].role == "TANK" and a[2].role == "HEALER", label .. ": ordered tank, healer, DPS")
end

-----------------------------------------------------------------------
-- 1. Valid rosters always produce 1/1/3 with matching specs
-----------------------------------------------------------------------

local flexible = {
    M("Ann", 1, 3, 5), M("Bob", 2, 4, 6), M("Cid", 1, 5, 7),
    M("Dee", 3, 6), M("Eve", 2, 4, 5, 7),
}
local rng = Rng(42)
for i = 1, 500 do
    CheckValid(R.Roll(flexible, roleOf, {random = rng}), "flexible #" .. i)
    if failures > 0 then break end
end

-- Only one arrangement is possible; it must be found every time.
local forced = {M("Tank", 1), M("Heals", 3), M("D1", 5), M("D2", 6), M("D3", 7)}
for i = 1, 50 do
    local r = R.Roll(forced, roleOf, {random = rng})
    CheckValid(r, "forced #" .. i)
    Check(r.ok and r.assignment[1].name == "Tank" and r.assignment[2].name == "Heals",
        "forced #" .. i .. ": the only arrangement")
end

-- A person with two tank specs gets either over many rolls.
local twoTanks = {M("Wall", 1, 2), M("Heals", 3), M("D1", 5), M("D2", 6), M("D3", 7)}
local tankSpecs = {}
for _ = 1, 200 do
    local r = R.Roll(twoTanks, roleOf, {random = rng})
    if r.ok then tankSpecs[r.assignment[1].specID] = true end
end
Check(tankSpecs[1] and tankSpecs[2], "two tank specs: both come up")

-- Unavailable members are ignored.
local withBench = {M("Tank", 1), M("Heals", 3), M("D1", 5), M("D2", 6), M("D3", 7), M("Bench", 1, 3, 5)}
withBench[6].available = false
CheckValid(R.Roll(withBench, roleOf, {random = rng}), "bench ignored")

-----------------------------------------------------------------------
-- 2. Impossible rosters give the right error
-----------------------------------------------------------------------

local function ExpectError(roster, code, label)
    local r = R.Roll(roster, roleOf, {random = rng})
    Check(not r.ok and r.code == code,
        label .. ": expected " .. code .. ", got " .. tostring(r.code) .. " (" .. tostring(r.message) .. ")")
    Check(type(r.message) == "string" and #r.message > 0, label .. ": has a message")
    return r
end

ExpectError({M("A", 1), M("B", 3), M("C", 5), M("D", 6)}, "WRONG_COUNT", "four available")
local six = {M("A", 1), M("B", 3), M("C", 5), M("D", 6), M("E", 7), M("F", 5)}
local r6 = ExpectError(six, "WRONG_COUNT", "six available")
Check(r6.message:find("6", 1, true) ~= nil, "six available: message says how many are ticked")

ExpectError({M("A", 5), M("B", 3), M("C", 5), M("D", 6), M("E", 7)}, "NO_TANK", "no tank")
local noHeal = ExpectError({M("A", 1), M("B", 5), M("C", 5), M("D", 6), M("E", 7)}, "NO_HEALER", "no healer")
Check(noHeal.message == "Nobody has a healer spec in their pool.", "no healer: wording")
ExpectError({M("A", 1), M("B"), M("C", 5), M("D", 6), M("E", 7)}, "EMPTY_POOL", "empty pool")
ExpectError({M("Solo", 1, 3), M("B", 5), M("C", 5), M("D", 6), M("E", 7)}, "SAME_TANK_HEALER", "one tank-healer")
ExpectError({M("A", 1), M("B", 3), M("C", 4), M("D", 6), M("E", 7)}, "TOO_FEW_DPS", "three can't DPS")
-- Both healers can't DPS; one of them has to tank, and neither can.
ExpectError({M("T", 1, 5), M("H1", 3), M("H2", 4), M("D1", 6), M("D2", 7)}, "NON_DPS_STUCK", "two pure healers")

-----------------------------------------------------------------------
-- 3. Rotation weighting reduces repeats
-----------------------------------------------------------------------

-- Everyone can play everything, so any arrangement is possible.
local anyone = {}
for i, n in ipairs({"P1", "P2", "P3", "P4", "P5"}) do anyone[i] = M(n, 1, 3, 5) end
local last = {P1 = "TANK", P2 = "HEALER", P3 = "DAMAGER", P4 = "DAMAGER", P5 = "DAMAGER"}

local function Repeats(weighting)
    local rngW = Rng(7)
    local total = 0
    for _ = 1, 3000 do
        local r = R.Roll(anyone, roleOf, {random = rngW, weighting = weighting, last = last})
        for _, e in ipairs(r.assignment) do
            if last[e.name] == e.role then total = total + 1 end
        end
    end
    return total / 3000
end

local plain, weighted = Repeats(false), Repeats(true)
print(string.format("average repeated roles per roll: unweighted %.2f, weighted %.2f", plain, weighted))
Check(weighted < plain * 0.75, "weighting cuts repeats by at least a quarter")

-- Weighting can't make a forced roster fail.
local rw = R.Roll(forced, roleOf, {random = rng, weighting = true,
    last = {Tank = "TANK", Heals = "HEALER", D1 = "DAMAGER", D2 = "DAMAGER", D3 = "DAMAGER"}})
CheckValid(rw, "weighted forced roster")

-----------------------------------------------------------------------

print(string.format("%d checks, %d failed", checks, failures))
if failures > 0 then os.exit(1) end
