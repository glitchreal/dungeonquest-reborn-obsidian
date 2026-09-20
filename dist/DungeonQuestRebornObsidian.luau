-- Dungeon Quest Reborn | fresh Obsidian hub
-- Runs in lobby + dungeon. RightShift toggles menu.
-- Executor needs: loadstring, game:HttpGet, queue_on_teleport (for continuation), file APIs (for config, optional).
if not game:IsLoaded() then game.Loaded:Wait() end

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local HttpService = game:GetService("HttpService")
local UIS = game:GetService("UserInputService")
local PFS = game:GetService("PathfindingService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local env = getgenv()
local resume = env.DQRBResume
env.DQRBResume = nil
if env.DQRB and env.DQRB.Unload then
    pcall(function() env.DQRB.Unload() end)
end

-- ============================================================
-- Config
-- ============================================================
local C = {
    -- Dungeon
    AutoDungeon = false, FarmPosition = "Nearest", BossDistance = 20, AbilityRange = 26,
    MoveSpeed = 16, MoveSpeedEnabled = false, StartDelay = 0,
    AutoAbilities = true, SpamAbilities = false, AutoDodge = true, AutoReplay = false,
    DodgeSafety = 3, DynamicDistance = false, MeleeDistance = 8,
    -- Carry finder
    CarryFinder = false, CarryHost = "", BestProgression = true,
    CarryDungeons = {}, CarryDifficulties = { "Insane", "Nightmare" },
    CarryHardcore = "Any", -- Any / Yes / No
    CarryJoinDelay = 5, HealCarrier = false, CarryStallTimeout = 60,
    -- Lobby
    AutoCreate = false, AutoStart = false, AutoBest = false,
    AutoJoinHost = false, JoinHostName = "", AutoReady = false,
    LobbyDungeon = "Desert Temple", LobbyDifficulty = "Insane",
    Mode = "Dungeon", -- Dungeon / Wave Defense / Boss Raid
    Hardcore = false, PrivateLobby = true, Whitelist = "",
    AllowFriends = true, RaidTier = "1", AutoRaid = false,
    -- Inventory
    Build = "Spell", AutoEquip = false, AutoSell = false,
    SellCommon = false, SellUncommon = false, SellRare = false, SellEpic = false, SellLegendary = false,
    KeepItems = "", SellDuplicateAbilities = false,
    -- Webhooks / tracking
    WebhookEnabled = false, WebhookURL = "", WantedDrops = "",
    LogWins = true, LogLosses = true, SendDrops = true, CombinedTag = true,
    -- Misc
    AutoSkill = false, SkillStat = "Spell Power",
    AFKMode = false, AntiAFK = true, FPSLimit = 60, FPSEnabled = false,
    StreamingMode = false, StuckRecovery = true, DisconnectRecovery = true,
    TargetBeam = false, ShowWaypoints = true,
}
local DiffOrder = { "Easy", "Medium", "Hard", "Insane", "Nightmare" }

-- Built-in requirements verified live Sep 2026 via getDungeonStats.
-- Live getDungeonStats overrides when available.
local BaseReq = {
    ["Desert Temple"] = { Easy = 1, Medium = 6, Hard = 12, Insane = 20, Nightmare = 27 },
    ["Winter Outpost"] = { Easy = 33, Medium = 40, Hard = 45, Insane = 50, Nightmare = 55 },
    ["Pirate Island"] = { Insane = 60, Nightmare = 65 },
    ["King's Castle"] = { Insane = 70, Nightmare = 75 },
    ["The Underworld"] = { Insane = 80, Nightmare = 85 },
    ["Samurai Palace"] = { Insane = 90, Nightmare = 95 },
    ["The Canals"] = { Insane = 100, Nightmare = 105 },
    ["Ghastly Harbor"] = { Insane = 110, Nightmare = 115 },
    ["Steampunk Sewers"] = { Insane = 120, Nightmare = 125 },
    ["Orbital Outpost"] = { Insane = 140, Nightmare = 145 },
    ["Volcanic Chambers"] = { Insane = 150, Nightmare = 155 },
    ["Aquatic Temple"] = { Insane = 160, Nightmare = 165 },
    ["Enchanted Forest"] = { Insane = 170, Nightmare = 175 },
    ["Northern Lands"] = { Insane = 180, Nightmare = 185 },
    ["Gilded Skies"] = { Insane = 190, Nightmare = 195 },
    ["Oni Dungeon"] = { Insane = 195, Nightmare = 200 },
}
local SkipDungeons = { ["Tutorial Dungeon"] = true, ["Egg Island"] = true, Krampus = true }

-- ============================================================
-- State
-- ============================================================
local alive = true
local hooks, busy, controls, labels, errors = {}, {}, {}, {}, {}
local totals = { Wins = 0, Losses = 0, Coins = 0, Gems = 0, Levels = 0, Kills = 0, Deaths = 0, Runs = 0, RunTime = 0 }
local sessionStart = os.clock()
local placeStart = os.clock()
local runStart, runCounted, runEnded, wasStarted = nil, false, false, false
local runBalances, runKills, runInventory, lastRun, lastDrops = nil, 0, nil, nil, {}
local catalog = {}
local inventoryCache = nil
local lastQueue, lastEquip, lastSell, lastSkill, lastWebhook = 0, 0, 0, 0, -math.huge
local lobbyStatus, carryStatus, raidStatus = "Waiting", "Idle", "Waiting"
local balances = { Coins = 0, Gems = 0, Levels = 0 }
local carryTarget, carryJoinAt, carryStallAt = nil, 0, nil
local stuckPos, stuckAt, lastRecover = nil, os.clock(), 0
local pendingSale = nil
local soldVerified = 0

if type(resume) == "table" then
    if type(resume.Config) == "table" then
        for k, v in pairs(resume.Config) do
            if C[k] ~= nil and type(C[k]) == type(v) then C[k] = v end
        end
    end
    if type(resume.Totals) == "table" then
        for k, v in pairs(resume.Totals) do
            if totals[k] ~= nil and type(v) == "number" then totals[k] = v end
        end
    end
    if tonumber(resume.Elapsed) then sessionStart = os.clock() - math.max(0, tonumber(resume.Elapsed)) end
end

-- ============================================================
-- Helpers
-- ============================================================
local function useIdentity()
    if type(setthreadidentity) == "function" then pcall(setthreadidentity, 8) end
end
local function connect(signal, fn)
    local c = signal:Connect(function(...) useIdentity(); fn(...) end)
    table.insert(hooks, c)
    return c
end
local Library
local function notify(msg)
    if not alive then return end
    useIdentity()
    pcall(function()
        Library:Notify({ Title = "DQ Reborn", Description = tostring(msg):sub(1, 200), Time = 5 })
    end)
end
local function job(key, fn)
    if not alive or busy[key] then return end
    busy[key] = true
    task.spawn(function()
        useIdentity()
        local ok, err = xpcall(fn, debug.traceback)
        busy[key] = nil
        if not ok then
            errors[key] = tostring(err):match("[^\n]+") or "error"
            notify(errors[key])
        end
    end)
end
local function fmtTime(s)
    s = math.max(0, math.floor(s or 0))
    return string.format("%02d:%02d:%02d", math.floor(s / 3600), math.floor(s / 60) % 60, s % 60)
end
local function normName(s)
    return tostring(s or ""):lower():gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s+", " ")
end
local function splitList(text)
    local out, seen = {}, {}
    for token in (text or ""):gmatch("[^,;\r\n]+") do
        token = normName(token)
        if token ~= "" and not seen[token] then seen[token] = true; table.insert(out, token) end
    end
    return out
end
local function validWebhook(url)
    return type(url) == "string" and url:match("^https://discord%.com/api/webhooks/%d+/[%w_-]+$") ~= nil
end

-- ============================================================
-- Game layer (fresh implementation; field names verified Sep 2026)
-- ============================================================
local PM, remotes
pcall(function()
    PM = require(RS:WaitForChild("Utility"):WaitForChild("PlaceManager"))
    remotes = RS:WaitForChild("remotes")
end)

local G = {}

function G.val(root, name, fb)
    local ch = root and root:FindFirstChild(name)
    if ch and ch:IsA("ValueBase") then return ch.Value end
    return fb
end
function G.level(who)
    who = who or player
    if G.val(who, "dataLoaded", true) == false then return nil end
    return tonumber(G.val(who:FindFirstChild("leaderstats"), "Level", nil))
end
function G.readBalances()
    local st = player:FindFirstChild("leaderstats")
    return {
        Coins = tonumber(G.val(st, "Gold", 0)) or 0,
        Gems = tonumber(G.val(st, "Gems", 0)) or 0,
        Levels = G.level() or 0,
    }
end
function G.call(name, ...)
    local r = remotes and remotes:FindFirstChild(name)
    assert(r, "Missing game remote: " .. tostring(name))
    if r:IsA("RemoteFunction") then return r:InvokeServer(...) end
    r:FireServer(...)
    return true
end
function G.tryCall(name, ...)
    local ok, res = pcall(G.call, name, ...)
    if ok then return res end
    return nil
end
function G.inventory()
    local inv = G.call("reloadInvy")
    assert(type(inv) == "table", "Inventory not loaded")
    inventoryCache = inv
    return inv
end
function G.dungeonRows()
    local names = {}
    local gui = player.PlayerGui:FindFirstChild("queueGui")
    local choose = gui and gui:FindFirstChild("chooseDungeon")
    local left = choose and choose:FindFirstChild("backgroundFillLeft")
    local list = left and left:FindFirstChild("ScrollingFrame")
    if list then
        for _, row in ipairs(list:GetChildren()) do
            if row:IsA("ImageLabel") and row:FindFirstChild("TextButton") and not SkipDungeons[row.Name] then
                table.insert(names, row.Name)
            end
        end
    end
    table.sort(names)
    return names
end
function G.refreshCatalog()
    local merged = {}
    for d, diffs in pairs(BaseReq) do
        merged[d] = {}
        for diff, req in pairs(diffs) do merged[d][diff] = { levelReq = req } end
    end
    for _, name in ipairs(G.dungeonRows()) do
        local ok, stats = pcall(G.call, "getDungeonStats", name)
        if ok and type(stats) == "table" then
            merged[name] = merged[name] or {}
            for _, diff in ipairs(DiffOrder) do
                local e = stats[diff]
                if type(e) == "table" and tonumber(e.levelReq) then
                    if not e.isEventPlace and not e.isBossKey then
                        merged[name][diff] = { levelReq = tonumber(e.levelReq) }
                    elseif merged[name][diff] == nil and BaseReq[name] and BaseReq[name][diff] then
                        -- keep built-in fallback
                    else
                        merged[name][diff] = nil
                    end
                end
            end
        end
    end
    catalog = merged
    return merged
end
function G.eligible(name)
    local out = {}
    local lvl = G.level()
    if not lvl or not catalog[name] then return out end
    for _, d in ipairs(DiffOrder) do
        local e = catalog[name][d]
        if e and e.levelReq and lvl >= e.levelReq then table.insert(out, d) end
    end
    return out
end
function G.bestFor(level)
    local best
    for name, diffs in pairs(catalog) do
        if not SkipDungeons[name] then
            for rank, diff in ipairs(DiffOrder) do
                local e = diffs[diff]
                local req = e and tonumber(e.levelReq)
                if req and level and req <= level then
                    if not best or req > best.levelReq or (req == best.levelReq and rank > best.rank) then
                        best = { Dungeon = name, Difficulty = diff, levelReq = req, rank = rank }
                    end
                end
            end
        end
    end
    return best
end
function G.inDungeonPlace()
    if PM and type(PM.GetPlaceName) == "function" then
        local ok, name = pcall(PM.GetPlaceName)
        if ok then return name == "Level" end
    end
    return Workspace:FindFirstChild("dungeon") ~= nil
end
function G.started()
    if PM and type(PM.HasDungeonStarted) == "function" then
        local ok, v = pcall(PM.HasDungeonStarted)
        if ok then return v == true end
    end
    return G.val(Workspace, "dungeonStarted", false) == true
end
function G.isOwner()
    -- PlaceManager has no IsDungeonOwner; ownership = my lobby folder exists.
    local mine = G.findMyLobby()
    return mine ~= nil and mine.Name == player.Name
end
function G.isBossRaid()
    if PM and type(PM.IsBossKey) == "function" then
        local ok, v = pcall(PM.IsBossKey)
        if ok then return v == true end
    end
    return false
end
function G.findMyLobby()
    local games = Workspace:FindFirstChild("games")
    local list = games and games:FindFirstChild("inLobby")
    if list then return list:FindFirstChild(player.Name) end
    return nil
end
function G.scanLobbies()
    local out = {}
    local games = Workspace:FindFirstChild("games")
    local list = games and games:FindFirstChild("inLobby")
    if not list then return out end
    for _, lobby in ipairs(list:GetChildren()) do
        local map = lobby:FindFirstChild("mapName")
        local dungeon = G.val(lobby, "mapName", nil) or (map and map.Value)
        local diff = map and G.val(map, "difficulty", nil)
        local hc = map and G.val(map, "hardcore", nil)
        local priv = map and G.val(map, "private", nil)
        local wave = map and G.val(map, "waveDefence", false)
        if type(dungeon) == "string" and type(diff) == "string" then
            local count = 0
            for _, ch in ipairs(lobby:GetChildren()) do
                if ch:IsA("StringValue") or ch:IsA("ObjectValue") then count = count + 1 end
            end
            table.insert(out, { lobby = lobby, host = lobby.Name, Dungeon = dungeon,
                Difficulty = diff, Hardcore = hc == true, Private = priv == true, Wave = wave == true, Members = count })
        end
    end
    return out
end
function G.makeLobby(dungeon, diff, hardcore, priv, wave)
    local statsOk, stats = pcall(G.call, "getDungeonStats", dungeon)
    local req = statsOk and type(stats) == "table" and stats[diff] and tonumber(stats[diff].levelReq)
    if not req then
        local fb = catalog[dungeon] and catalog[dungeon][diff]
        req = fb and fb.levelReq
    end
    assert(req, "No level requirement for " .. tostring(dungeon) .. " " .. tostring(diff))
    local lvl = assert(G.level(), "Level not loaded")
    assert(lvl >= req, "Requires level " .. req)
    return G.call("createLobby", dungeon, diff, req, hardcore and not wave, priv, wave and true or false)
end
function G.runData()
    local data = {}
    if PM and type(PM.GetPlaceTeleportData) == "function" then
        local ok, tp = pcall(PM.GetPlaceTeleportData)
        if ok and type(tp) == "table" and type(tp.dungeonStats) == "table" then
            for k, v in pairs(tp.dungeonStats) do data[k] = v end
        end
    end
    for _, n in ipairs({ "dungeonName", "dungeonProgress", "dungeonStarted", "hardcore" }) do
        local v = G.val(Workspace, n, nil)
        if v ~= nil then data[n] = v end
    end
    assert(type(data.dungeonName) == "string", "Run data unavailable")
    return data
end
function G.done()
    if G.val(Workspace, "dungeonProgress", "") == "bossKilled" then return true end
    local d = Workspace:FindFirstChild("dungeon")
    local boss = d and d:FindFirstChild("bossRoom")
    return G.val(boss, "dungeonFinished", false) == true
end
function G.failed()
    return player.PlayerGui:FindFirstChild("failedGui") ~= nil
end
function G.replay()
    -- Server validates owner; just attempt it.
    return G.call("replayDungeon", G.runData())
end

balances = G.readBalances()

-- ============================================================
-- Combat engine (original movement/ability/dodge implementation)
-- ============================================================
local Combat = {
    running = false, status = "Idle", kills = 0,
    target = nil, targets = {}, lastScan = 0, lastSkill = 0,
    useQ = true, qCasts = 0, eCasts = 0,
    waypoints = {}, wpIndex = 1, pathObj = nil, pathAt = 0, pathBusy = false,
    lastPos = Vector3.zero, stuckSince = 0, recoveries = 0,
    dodgeAt = 0, dodgeLog = {}, dodgeSide = 1, threats = {},
    folder = nil, nodes = {},
}
local trackedHumanoids = {}
connect(Workspace.DescendantAdded, function(inst)
    if inst:IsA("Humanoid") and inst.Parent and inst.Parent:IsA("Model") then
        trackedHumanoids[inst] = inst.Parent
    end
    if inst:IsA("BasePart") and not inst.CanCollide then
        Combat.threats[inst] = { born = os.clock(), pos = inst.Position, at = os.clock() }
    end
end)
connect(Workspace.DescendantRemoving, function(inst)
    Combat.threats[inst] = nil
    trackedHumanoids[inst] = nil
end)
for _, inst in ipairs(Workspace:GetDescendants()) do
    if inst:IsA("Humanoid") and inst.Parent and inst.Parent:IsA("Model") then trackedHumanoids[inst] = inst.Parent end
    if inst:IsA("BasePart") and not inst.CanCollide then Combat.threats[inst] = { born = os.clock(), pos = inst.Position, at = os.clock() } end
end

local function charParts()
    local ch = player.Character
    if not ch then return nil, nil, nil end
    return ch, ch:FindFirstChildOfClass("Humanoid"), ch:FindFirstChild("HumanoidRootPart")
end
local function modelRoot(m)
    local r = m:FindFirstChild("HumanoidRootPart")
    if r and r:IsA("BasePart") then return r end
    local h = m:FindFirstChild("Head")
    if h and h:IsA("BasePart") then return h end
    return m.PrimaryPart
end
local function validFoe(m)
    if not m or not m.Parent or not m:IsA("Model") then return false end
    if Players:GetPlayerFromCharacter(m) then return false end
    local fn = m:GetFullName():lower()
    if fn:find(".lobby") or fn:find(".aesthetic") then return false end
    if m.Name == player.Name or m.Name == "Seller" or m.Name == "Blacksmith" then return false end
    local h = m:FindFirstChildOfClass("Humanoid")
    local r = modelRoot(m)
    return h ~= nil and h.Health > 0 and r ~= nil
end
local function rayBlocked(a, b, ch, foe)
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = { ch, foe }
    params.IgnoreWater = true
    params.RespectCanCollide = true
    local dir = b - a
    for _ = 1, 4 do
        local hit = Workspace:Raycast(a, dir, params)
        if not hit then return false end
        local mdl = hit.Instance:FindFirstAncestorOfClass("Model")
        local body = mdl and mdl:FindFirstChildOfClass("Humanoid") ~= nil
        if (hit.Instance:IsA("BasePart") and not hit.Instance.CanCollide) or body then
            local ig = params.FilterDescendantsInstances
            table.insert(ig, body and mdl or hit.Instance)
            params.FilterDescendantsInstances = ig
        else
            return true
        end
    end
    return true
end
local function scanFoes(root, now)
    if now - Combat.lastScan < 0.25 then return end
    Combat.lastScan = now
    local list = {}
    for h, m in pairs(trackedHumanoids) do
        if h.Parent ~= m then trackedHumanoids[h] = nil
        elseif m:IsDescendantOf(Workspace) and validFoe(m) then
            local r = modelRoot(m)
            if r and (r.Position - root.Position).Magnitude <= 1000 then table.insert(list, m) end
        end
    end
    Combat.targets = list
end
local function pickFoe(root, now)
    scanFoes(root, now)
    if validFoe(Combat.target) then
        local r = modelRoot(Combat.target)
        if r and Combat.target:IsDescendantOf(Workspace) and (r.Position - root.Position).Magnitude <= 1000 then
            return Combat.target, (r.Position - root.Position).Magnitude
        end
    end
    Combat.target = nil
    local best, bestD
    for _, m in ipairs(Combat.targets) do
        if validFoe(m) then
            local r = modelRoot(m)
            local d = (r.Position - root.Position).Magnitude
            if not bestD or d < bestD then best, bestD = m, d end
        end
    end
    Combat.target = best
    return best, bestD or 1000
end
local function farmGoal(root, foeRoot)
    local mode = C.FarmPosition
    local dist = math.clamp(C.BossDistance, 1, 60)
    local toFoe = (foeRoot.Position - root.Position)
    toFoe = Vector3.new(toFoe.X, 0, toFoe.Z)
    if toFoe.Magnitude < 0.01 then toFoe = Vector3.new(1, 0, 0) end
    toFoe = toFoe.Unit
    local side = Vector3.new(-toFoe.Z, 0, toFoe.X)
    local dir = toFoe
    if mode == "Behind" then dir = -toFoe
    elseif mode == "Front" then dir = toFoe
    elseif mode == "Left" then dir = -side
    elseif mode == "Right" then dir = side
    elseif mode == "Nearest" then
        local want = foeRoot.Position - toFoe * dist
        return Vector3.new(want.X, foeRoot.Position.Y, want.Z)
    end
    local want = foeRoot.Position + dir * dist
    return Vector3.new(want.X, foeRoot.Position.Y, want.Z)
end
local function ensureFolder()
    if Combat.folder and Combat.folder.Parent then return Combat.folder end
    local f = Instance.new("Folder")
    f.Name = "DQRB_WP_" .. player.Name
    f.Parent = Workspace
    Combat.folder = f
    return f
end
local function clearWP()
    if Combat.folder then pcall(function() Combat.folder:ClearAllChildren() end) end
    Combat.nodes = {}
    Combat.waypoints = {}
    Combat.wpIndex = 1
    if Combat.pathObj then pcall(function() Combat.pathObj:Destroy() end) end
    Combat.pathObj = nil
end
local function drawWP()
    clearWP()
    if not C.ShowWaypoints or #Combat.waypoints == 0 then return end
    local f = ensureFolder()
    for i, wp in ipairs(Combat.waypoints) do
        local p = Instance.new("Part")
        p.Shape = Enum.PartType.Ball
        p.Size = Vector3.new(0.6, 0.6, 0.6)
        p.Position = wp.Position
        p.Anchored = true p.CanCollide = false p.CanTouch = false p.CanQuery = false
        p.Material = Enum.Material.Neon
        p.Color = (i == Combat.wpIndex) and Color3.fromRGB(255, 255, 0) or Color3.fromRGB(0, 255, 255)
        p.Parent = f
        table.insert(Combat.nodes, p)
    end
end
local function gotoPos(hum, root, goal, mode, now)
    if (goal - root.Position).Magnitude <= 42 and not rayBlocked(root.Position, goal, hum.Parent, Combat.target) then
        if Combat.pathObj then clearWP() end
        hum:MoveTo(goal)
        return
    end
    if not Combat.pathBusy and #Combat.waypoints == 0 and now - Combat.pathAt >= 0.8 then
        Combat.pathAt = now
        Combat.pathBusy = true
        local from = root.Position
        task.spawn(function()
            local path = PFS:CreatePath({ AgentRadius = 2, AgentHeight = 5.5, AgentCanJump = true, AgentJumpHeight = 12, AgentMaxSlope = 70, WaypointSpacing = 4 })
            local ok = pcall(function() path:ComputeAsync(from, goal) end)
            Combat.pathBusy = false
            if ok and path.Status == Enum.PathStatus.Success then
                local wps = path:GetWaypoints()
                if #wps >= 2 then
                    Combat.pathObj = path
                    Combat.waypoints = wps
                    Combat.wpIndex = 1
                    drawWP()
                    return
                end
            end
            path:Destroy()
            hum:MoveTo(goal)
        end)
        return
    end
    local wp = Combat.waypoints[Combat.wpIndex]
    while wp and (Vector3.new(root.Position.X - wp.Position.X, 0, root.Position.Z - wp.Position.Z)).Magnitude <= 3 do
        Combat.wpIndex += 1
        wp = Combat.waypoints[Combat.wpIndex]
    end
    if not wp then clearWP(); hum:MoveTo(goal); return end
    if wp.Action == Enum.PathWaypointAction.Jump and hum.FloorMaterial ~= Enum.Material.Air then hum.Jump = true end
    hum:MoveTo(wp.Position)
end
local function updateStuck(hum, root, goal, now)
    if now - Combat.stuckSince < 0.4 then return end
    Combat.stuckSince = now
    local moved = (root.Position - Combat.lastPos).Magnitude
    Combat.lastPos = root.Position
    if moved > 0.5 or (goal - root.Position).Magnitude < 3 then return end
    -- small lateral recovery, no random jumps
    Combat.recoveries += 1
    local flat = goal - root.Position
    flat = Vector3.new(flat.X, 0, flat.Z)
    if flat.Magnitude < 0.1 then flat = Vector3.new(1, 0, 0) end
    flat = flat.Unit
    local side = Vector3.new(-flat.Z, 0, flat.X) * Combat.dodgeSide
    Combat.dodgeSide = -Combat.dodgeSide
    local cand = root.Position + side * 6
    if not rayBlocked(root.Position, cand, hum.Parent, Combat.target) then hum:MoveTo(cand) end
end
local function senseThreat(root, foe, now)
    if not C.AutoDodge then return nil end
    for part, s in pairs(Combat.threats) do
        if not part.Parent or now - s.born > 2 then Combat.threats[part] = nil
        elseif part.Transparency < 0.9 then
            local nm = (part.Name .. " " .. part.Parent.Name):lower()
            local risky = nm:find("attack") or nm:find("hitbox") or nm:find("precast") or nm:find("projectile") or nm:find("telegraph") or nm:find("danger")
            local d = (part.Position - root.Position).Magnitude
            if risky and d < 30 then
                local lp = part.CFrame:PointToObjectSpace(root.Position)
                if math.abs(lp.X) < part.Size.X / 2 + C.DodgeSafety and math.abs(lp.Z) < part.Size.Z / 2 + C.DodgeSafety and math.abs(lp.Y) < part.Size.Y / 2 + 4 then
                    return part
                end
            end
        end
        s.pos, s.at = part.Position, now
    end
    return nil
end
local function dodgeOk(now, dist)
    while Combat.dodgeLog[1] and now - Combat.dodgeLog[1].at >= 3 do table.remove(Combat.dodgeLog, 1) end
    if dist < 0.1 or dist > 3.01 then return false end
    if #Combat.dodgeLog >= 2 then return false end
    if Combat.dodgeLog[#Combat.dodgeLog] and now - Combat.dodgeLog[#Combat.dodgeLog].at < 1 then return false end
    local spent = 0
    for _, e in ipairs(Combat.dodgeLog) do spent += e.d end
    return spent + dist <= 6.01
end
local function tryDodge(hum, root, foeRoot, threat, now)
    if not threat or hum.FloorMaterial == Enum.Material.Air then return false end
    local away = root.Position - threat.Position
    away = Vector3.new(away.X, 0, away.Z)
    if away.Magnitude < 0.1 then away = Vector3.new(1, 0, 0) end
    away = away.Unit
    local right = Vector3.new(-away.Z, 0, away.X)
    local cands = { root.Position + right * 3, root.Position - right * 3, root.Position + away * 3 }
    for _, cand in ipairs(cands) do
        cand = Vector3.new(cand.X, root.Position.Y, cand.Z)
        local d = (cand - root.Position).Magnitude
        if dodgeOk(now, d) and not rayBlocked(root.Position + Vector3.new(0, 2, 0), cand + Vector3.new(0, 2, 0), hum.Parent, Combat.target) then
            root.CFrame += (cand - root.Position)
            table.insert(Combat.dodgeLog, { at = now, d = d })
            Combat.dodgeAt = now
            clearWP()
            hum:MoveTo(cand)
            return true
        end
    end
    return false
end
local function abilityTools()
    local out = {}
    for _, cont in ipairs({ player:FindFirstChild("Backpack"), player.Character }) do
        if cont then
            for _, t in ipairs(cont:GetChildren()) do
                local slot = t:FindFirstChild("abilitySlot")
                local cd = t:FindFirstChild("cooldown")
                if slot and cd and (slot.Value == "q" or slot.Value == "e") then
                    out[slot.Value] = { tool = t, left = math.max(0, tonumber(cd.Value) or 0) }
                end
            end
        end
    end
    return out
end
local function castAbilities(now)
    if not C.AutoAbilities then return end
    local gap = C.SpamAbilities and 0.3 or 1.5
    if now - Combat.lastSkill < gap then return end
    local ch, hum = player.Character, player.Character and player.Character:FindFirstChildOfClass("Humanoid")
    if not hum or hum.Health <= 0 then return end
    if player.Character:FindFirstChild("busyCasting") then return end
    local slots = abilityTools()
    local order = Combat.useQ and { "q", "e" } or { "e", "q" }
    for _, s in ipairs(order) do
        local e = slots[s]
        if e and e.left <= 0 then
            local ev = e.tool:FindFirstChild("localEvent")
            local ok = false
            if ev and ev:IsA("BindableEvent") then ok = pcall(function() ev:Fire() end) end
            pcall(function() G.call("abilityUsed", s, e.tool) end)
            Combat.lastSkill = now
            Combat.useQ = not Combat.useQ
            if s == "q" then Combat.qCasts += 1 else Combat.eCasts += 1 end
            return
        end
    end
end
-- Heal-cast helper used by carry healer (casts Universal Heal only when someone is hurt)
local function castHealIfNeeded(members, now)
    if now - Combat.lastSkill < 4 then return false end
    local need = false
    local carrierCh = nil
    for _, m in ipairs(members or {}) do
        local ch = m.player and m.player.Character
        local h = ch and ch:FindFirstChildOfClass("Humanoid")
        if h and h.Health > 0 and h.Health < h.MaxHealth * 0.9 then need = true end
        if m.isCarrier then carrierCh = ch end
    end
    if not need then return false end
    local slots = abilityTools()
    for _, s in ipairs({ "q", "e" }) do
        local e = slots[s]
        if e and e.tool.Name == "Universal Heal" and e.left <= 0 then
            local ev = e.tool:FindFirstChild("localEvent")
            if ev and ev:IsA("BindableEvent") then pcall(function() ev:Fire() end) end
            pcall(function() G.call("abilityUsed", s, e.tool) end)
            Combat.lastSkill = now
            return true
        end
    end
    return false
end

-- ============================================================
-- Inventory helpers (fresh logic)
-- ============================================================
local Rarities = { "Common", "Uncommon", "Rare", "Epic", "Legendary" }
local function isEquipped(item)
    if type(item.equipped) == "table" then
        for _, v in pairs(item.equipped) do if v then return true end end
        return false
    end
    return item.equipped ~= false
end
local function scoreItem(item, kind, build)
    if build == "Spell" then return tonumber(item.spellPower) or 0 end
    if kind == "weapon" then return tonumber(item.physicalDamage) or tonumber(item.physicalPower) or 0 end
    return tonumber(item.physicalPower) or 0
end
local function bestGear(inv, level, build)
    local out = {}
    for _, kind in ipairs({ "weapon", "helmet", "chest" }) do
        local best, bs, bh
        for id, item in pairs(inv[kind .. "s"] or {}) do
            local num = tostring(id):match("^" .. kind .. "_(%d+)$")
            local req = tonumber(item.levelReq)
            if num and req and req <= level then
                local s = scoreItem(item, kind, build)
                local h = tonumber(item.health) or 0
                if not best or s > bs or (s == bs and h > bh) then best, bs, bh = { kind = kind, id = tonumber(num) }, s, h end
            end
        end
        if best then table.insert(out, best) end
    end
    return out
end
local function keepSet()
    local set = {}
    for _, n in ipairs(splitList(C.KeepItems)) do set[n] = true end
    return set
end
local function rarityEnabled(r)
    r = normName(r)
    if r == "common" then return C.SellCommon end
    if r == "uncommon" then return C.SellUncommon end
    if r == "rare" then return C.SellRare end
    if r == "epic" then return C.SellEpic end
    if r == "legendary" then return C.SellLegendary end
    return false
end
local function sellPlan(inv)
    local plan = { weapon = {}, helmet = {}, chest = {}, ability = {} }
    local keep = keepSet()
    local seenAbility = {}
    local total = 0
    for kind, ids in pairs(plan) do
        local cat = kind == "ability" and "abilities" or kind .. "s"
        for id, item in pairs(inv[cat] or {}) do
            local num = tonumber(tostring(id):match("^" .. kind .. "_(%d+)$"))
            if num and not isEquipped(item) and not item.locked and not item.favorite and not item.favourited then
                if keep[normName(item.name)] then continue end
                if kind == "ability" then
                    local nm = normName(item.name)
                    if C.SellDuplicateAbilities then
                        if seenAbility[nm] then
                            if rarityEnabled(item.rarity) then table.insert(ids, num); total += 1 end
                        else seenAbility[nm] = true end
                        continue
                    end
                end
                if rarityEnabled(item.rarity) then table.insert(ids, num); total += 1 end
            elseif kind == "ability" and num and C.SellDuplicateAbilities and not seenAbility[normName(item.name)] then
                seenAbility[normName(item.name)] = true
            end
        end
        table.sort(ids)
    end
    return plan, total
end

-- ============================================================
-- Webhooks / tracking
-- ============================================================
local function wantedSet()
    local s = {}
    for _, n in ipairs(splitList(C.WantedDrops)) do s[n] = true end
    return s
end
local function diffDrops(before, after)
    local got = {}
    if type(before) ~= "table" or type(after) ~= "table" then return got end
    for _, cat in ipairs({ "weapons", "helmets", "chests", "abilities" }) do
        for id, item in pairs(after[cat] or {}) do
            if type(item) == "table" and not (before[cat] or {})[id] then
                table.insert(got, { name = tostring(item.name or id), rarity = tostring(item.rarity or "?"), id = tostring(id),
                    asset = tostring(item.imageId or ""):match("rbxassetid://(%d+)") })
            end
        end
    end
    return got
end
local function sendWebhook(record)
    if not C.WebhookEnabled or not validWebhook(C.WebhookURL) then return end
    if os.clock() - lastWebhook < 5 then return end
    local fn = request or http_request or (syn and syn.request)
    if type(fn) ~= "function" then notify("HTTP unavailable"); return end
    lastWebhook = os.clock()
    job("webhook", function()
        local fields = {}
        local function add(n, v, inline)
            table.insert(fields, { name = n, value = tostring(v):sub(1, 1024), inline = inline ~= false })
        end
        add("Dungeon", record.Dungeon or "?", true)
        add("Difficulty", record.Difficulty or "?", true)
        add("Result", record.Result or "?", true)
        add("Duration", fmtTime(record.Duration or 0), true)
        add("Coins +", record.Coins or 0, true)
        add("Gems +", record.Gems or 0, true)
        add("Wins/Losses", totals.Wins .. "/" .. totals.Losses, true)
        add("Kills", record.Kills or 0, true)
        add("Account", record.Account or (player.Name .. " (" .. player.UserId .. ")"), false)
        local drops = record.Drops or {}
        local names = {}
        for _, d in ipairs(drops) do table.insert(names, d.name .. " [" .. d.rarity .. "]") end
        if C.SendDrops then add("Drops", #names > 0 and table.concat(names, "\n"):sub(1, 1000) or "None", false) end
        local wanted = wantedSet()
        local hit = {}
        for _, d in ipairs(drops) do if wanted[normName(d.name)] then table.insert(hit, d.name) end end
        local body = { username = "DQ Reborn", allowed_mentions = { parse = {} },
            content = #hit > 0 and ("WANTED DROP: " .. table.concat(hit, ", ")) or nil,
            embeds = { { title = "Dungeon Quest Reborn", color = record.Result == "Win" and 5763719 or 15548997, fields = fields,
                footer = C.CombinedTag and { text = "JobId " .. game.JobId .. " | " .. fmtTime(os.clock() - sessionStart) } or nil } } }
        local res = fn({ Url = C.WebhookURL, Method = "POST", Headers = { ["Content-Type"] = "application/json" }, Body = HttpService:JSONEncode(body) })
        local code = tonumber(res and res.StatusCode) or 0
        if not (code >= 200 and code < 300) then notify("Webhook HTTP " .. code) end
    end)
end
local function finishRun(won)
    if runCounted then return end
    runCounted, runEnded = true, true
    Combat.running = false
    totals.Runs += 1
    if won then totals.Wins += 1 else totals.Losses += 1 end
    local dur = runStart and (os.clock() - runStart) or 0
    if won then totals.RunTime += dur end
    job("finish", function()
        task.wait(1.2)
        if not alive then return end
        local after = G.readBalances()
        local d = {}
        pcall(function() d = G.runData() end)
        local ok, cur = pcall(G.inventory)
        local drops = {}
        if ok and runInventory then drops = diffDrops(runInventory, cur) end
        lastDrops = drops
        local rec = { Dungeon = d.dungeonName, Difficulty = d.difficulty, Result = won and "Win" or "Loss",
            Duration = dur, Coins = math.max(0, after.Coins - (runBalances and runBalances.Coins or after.Coins)),
            Gems = math.max(0, after.Gems - (runBalances and runBalances.Gems or after.Gems)),
            Kills = Combat.kills - runKills, Drops = drops, Account = player.Name .. " (" .. player.UserId .. ")" }
        lastRun = rec
        if (won and C.LogWins or not won and C.LogLosses) then sendWebhook(rec) end
        if C.AutoReplay or (C.AutoRaid and G.isBossRaid()) then
            task.wait(2)
            if alive then pcall(G.replay) end
        end
    end)
end

-- ============================================================
-- Obsidian UI
-- ============================================================
local repo = "https://raw.githubusercontent.com/deividcomsono/Obsidian/3df0deae2c50a06cf29cf3b6a047db62466d40b9/"
Library = loadstring(game:HttpGet(repo .. "Library.lua"))()
Library.ScreenGui.Parent = player:WaitForChild("PlayerGui")
Library.ScreenGui.ResetOnSpawn = false
pcall(function() Library.Scheme.AccentColor = Color3.fromRGB(120, 170, 255) end)
Library.ForceCheckbox = false

local Window = Library:CreateWindow({ Title = "Dungeon Quest Reborn", Footer = "Obsidian | fresh build",
    Center = true, AutoShow = true, Resizable = true, ShowCustomCursor = false, Size = UDim2.fromOffset(880, 660) })
local T = {
    Dungeon = Window:AddTab("Dungeon", "swords"),
    Carry = Window:AddTab("Carry Finder", "users"),
    Lobby = Window:AddTab("Lobby", "door-open"),
    Inv = Window:AddTab("Inventory", "backpack"),
    Web = Window:AddTab("Webhooks", "send"),
    Misc = Window:AddTab("Other", "settings"),
    Settings = Window:AddTab("Settings", "save"),
}
local function tg(group, key, text, cb, tip)
    local c = group:AddToggle(key, { Text = text, Default = C[key], Tooltip = tip })
    c:OnChanged(function(v) C[key] = v; if cb then cb(v) end end)
    controls[key] = c
    return c
end
local function sl(group, key, text, mn, mx, cb, round)
    local c = group:AddSlider(key, { Text = text, Default = C[key], Min = mn, Max = mx, Rounding = round or 0 })
    c:OnChanged(function(v) C[key] = v; if cb then cb(v) end end)
    controls[key] = c
    return c
end
local function inp(group, key, text, num, cb)
    local c = group:AddInput(key, { Text = text, Default = tostring(C[key]), Numeric = num or false, Finished = true, ClearTextOnFocus = false })
    c:OnChanged(function(v) C[key] = v; if cb then cb(v) end end)
    controls[key] = c
    return c
end
local function dd(group, key, text, values, cb, multi)
    local c = group:AddDropdown(key, { Text = text, Values = values, Default = C[key], Multi = multi or false, Searchable = #values > 8 })
    c:OnChanged(function(v) C[key] = v; if cb then cb(v) end end)
    controls[key] = c
    return c
end
local function lab(group, key, text)
    labels[key] = group:AddLabel(text, true)
end
local function setLab(key, text)
    if labels[key] then pcall(function() labels[key]:SetText(text) end) end
end

-- Dungeon tab
local dg = T.Dungeon:AddLeftGroupbox("Automation")
tg(dg, "AutoDungeon", "Dungeon Automation")
dd(dg, "FarmPosition", "Farm Position", { "Nearest", "Behind", "Front", "Left", "Right" })
sl(dg, "BossDistance", "Boss Distance", 5, 55)
sl(dg, "AbilityRange", "Ability Range", 8, 100)
tg(dg, "MoveSpeedEnabled", "Movement Speed Override")
sl(dg, "MoveSpeed", "Movement Speed", 8, 60)
sl(dg, "StartDelay", "Start Delay (s)", 0, 120)
tg(dg, "AutoReplay", "Auto Replay")
local da = T.Dungeon:AddRightGroupbox("Combat")
tg(da, "AutoAbilities", "Auto Abilities")
tg(da, "SpamAbilities", "Spam Abilities (faster checks)")
tg(da, "AutoDodge", "Auto Dodge (bounded 3-stud)")
sl(da, "DodgeSafety", "Dodge Safety Padding", 0, 10, nil, 1)
tg(da, "DynamicDistance", "Dynamic Melee Distance")
sl(da, "MeleeDistance", "Melee Distance", 5, 14)
tg(da, "TargetBeam", "Target Beam")
tg(da, "ShowWaypoints", "Show Waypoints")
local ds = T.Dungeon:AddLeftGroupbox("Live")
lab(ds, "DStatus", "Status: idle")
lab(ds, "DTarget", "Target: -")
lab(ds, "DCasts", "Q/E: 0/0")
lab(ds, "DStats", "Wins: 0 Losses: 0")

-- Carry tab
local cg = T.Carry:AddLeftGroupbox("Finder")
tg(cg, "CarryFinder", "Enable Carry Finder")
inp(cg, "CarryHost", "Carrier Username (blank = auto)", false)
tg(cg, "BestProgression", "Best Available Progression")
sl(cg, "CarryJoinDelay", "Join Retry (s)", 3, 30)
sl(cg, "CarryStallTimeout", "Stall Timeout (s)", 20, 300)
tg(cg, "HealCarrier", "Heal Carrier On Damage")
local cf = T.Carry:AddRightGroupbox("Filters")
dd(cf, "CarryHardcore", "Hardcore Preference", { "Any", "Yes", "No" })
lab(cf, "CarryHint", "Dungeon/difficulty filters follow your Lobby selection. Leave carrier blank to auto-pick best run.")
local cs = T.Carry:AddRightGroupbox("Session")
lab(cs, "CarryStatus", "Carry: idle")
lab(cs, "CarryStats", "Runs 0 | Wins 0 | Losses 0")
lab(cs, "CarryGains", "Coins 0 | Gems 0")

-- Lobby tab
local lg = T.Lobby:AddLeftGroupbox("Create / Join")
tg(lg, "AutoCreate", "Auto Create Dungeon")
tg(lg, "AutoStart", "Auto Start Dungeon")
tg(lg, "AutoBest", "Auto Select Best Dungeon")
tg(lg, "AutoJoinHost", "Auto Join Host")
inp(lg, "JoinHostName", "Host To Join", false)
tg(lg, "AutoReady", "Auto Ready")
dd(lg, "Mode", "Mode", { "Dungeon", "Wave Defense", "Boss Raid" })
dd(lg, "LobbyDungeon", "Dungeon", { "Desert Temple", "Winter Outpost", "Pirate Island", "King's Castle", "The Underworld", "Samurai Palace", "The Canals", "Ghastly Harbor", "Steampunk Sewers", "Orbital Outpost", "Volcanic Chambers", "Aquatic Temple", "Enchanted Forest", "Northern Lands", "Gilded Skies", "Oni Dungeon" })
dd(lg, "LobbyDifficulty", "Difficulty", DiffOrder)
lab(lg, "LobbyStatus", "Lobby: waiting")
local lo = T.Lobby:AddRightGroupbox("Options")
tg(lo, "Hardcore", "Hardcore")
tg(lo, "PrivateLobby", "Private Lobby")
inp(lo, "Whitelist", "Party Whitelist (comma names)", false)
tg(lo, "AllowFriends", "Allow Friends Through Kick")
tg(lo, "AutoRaid", "Auto Boss Raid")
dd(lo, "RaidTier", "Boss Raid Tier", { "1", "2", "3", "4", "5", "6", "7", "8" })
lab(lo, "RaidStatus", "Raid: waiting")

-- Inventory tab
local ig = T.Inv:AddLeftGroupbox("Gear")
dd(ig, "Build", "Build", { "Spell", "Physical" })
tg(ig, "AutoEquip", "Auto Equip Best Gear")
ig:AddButton({ Text = "Equip Best Now", Func = function()
    job("equipOnce", function()
        local inv = G.inventory()
        local lvl = assert(G.level(), "Level not loaded")
        for _, e in ipairs(bestGear(inv, lvl, C.Build)) do
            pcall(G.call, "equipItem", e.kind, e.id)
            task.wait(0.25)
        end
        notify("Equipped best " .. C.Build)
    end)
end })
local isell = T.Inv:AddRightGroupbox("Auto Sell")
tg(isell, "AutoSell", "Auto Sell")
tg(isell, "SellCommon", "Sell Common")
tg(isell, "SellUncommon", "Sell Uncommon")
tg(isell, "SellRare", "Sell Rare")
tg(isell, "SellEpic", "Sell Epic")
tg(isell, "SellLegendary", "Sell Legendary")
tg(isell, "SellDuplicateAbilities", "Sell Duplicate Abilities")
lab(isell, "SellStatus", "Sell: off")
local ikeep = T.Inv:AddLeftGroupbox("Keep List (searchable)")
ikeep:AddLabel("Full item names, comma/newline separated. Search filters the lobby dropdowns, not game data.", true)
inp(ikeep, "KeepItems", "Keep Items", false)
ikeep:AddButton({ Text = "Clear Keep List", Func = function() controls.KeepItems:SetValue("") end })

-- Webhooks tab
local wg = T.Web:AddLeftGroupbox("Discord")
tg(wg, "WebhookEnabled", "Dungeon Completion Webhooks")
inp(wg, "WebhookURL", "Webhook URL", false)
inp(wg, "WantedDrops", "Wanted Drops (notify)", false)
tg(wg, "SendDrops", "Drop Tracking")
tg(wg, "CombinedTag", "Combined Session Tag (JobId)")
wg:AddButton({ Text = "Send Test", Func = function()
    sendWebhook({ Dungeon = C.LobbyDungeon, Difficulty = C.LobbyDifficulty, Result = "Win", Duration = 60, Coins = 0, Gems = 0, Kills = 0, Drops = {}, Account = player.Name })
end })
local ws = T.Web:AddRightGroupbox("Tracking")
tg(ws, "LogWins", "Win Tracking")
tg(ws, "LogLosses", "Loss Tracking")
lab(ws, "WStats", "Runs 0 | 00:00:00")
lab(ws, "WGains", "Coins 0 | Gems 0 | Lv 0")
lab(ws, "WDrops", "Last drops: none")

-- Misc tab
local mg = T.Misc:AddLeftGroupbox("Character")
tg(mg, "AutoSkill", "Auto Spend Skill Points")
dd(mg, "SkillStat", "Skill Stat", { "Spell Power", "Physical Power", "Stamina" })
tg(mg, "AntiAFK", "Anti-AFK")
tg(mg, "StreamingMode", "Streaming Mode (hide names)")
local mp = T.Misc:AddRightGroupbox("Performance / Recovery")
tg(mp, "AFKMode", "AFK Performance Mode", function(v)
    if not v then
        RunService:Set3dRenderingEnabled(true)
        if type(setfpscap) == "function" and not C.FPSEnabled then setfpscap(60) end
        pcall(function() Lighting.GlobalShadows = true end)
    end
end)
tg(mp, "FPSEnabled", "FPS Limit Enabled")
sl(mp, "FPSLimit", "FPS Limit", 15, 360)
tg(mp, "StuckRecovery", "Stuck-Session Recovery")
tg(mp, "DisconnectRecovery", "Disconnect Recovery")
lab(mp, "MStatus", "Uptime 00:00:00")

-- Settings tab
local sg = T.Settings:AddLeftGroupbox("Config")
sg:AddLabel("Configs save per-account. Webhook URL is never saved.", true)
sg:AddButton({ Text = "Save Config Now", Func = function() saveNow() end })
local queueFn = queue_on_teleport or queueonteleport or (syn and syn.queue_on_teleport)
sg:AddLabel("Teleport queue: " .. (type(queueFn) == "function" and "available" or "unavailable"), true)
sg:AddLabel("Menu key"):AddKeyPicker("MenuKey", { Default = "RightShift", NoUI = true, Text = "Menu" })
Library.ToggleKeybind = Library.Options.MenuKey
sg:AddButton({ Text = "Unload", Func = function() unload() end })

-- Carry dungeon/difficulty multi-select lives on Lobby tab data but is shown here via defaults:
-- (Obsidian multi-dropdown not assumed; filters reuse LobbyDungeon + CarryDifficulties defaults.)

-- ============================================================
-- Persistence + teleport continuation (webhook excluded)
-- ============================================================
local cfgFile = "DQRB-" .. player.UserId .. ".json"
function saveNow()
    if type(writefile) ~= "function" then return end
    local copy = table.clone(C)
    copy.WebhookURL = nil
    pcall(function()
        writefile(cfgFile, HttpService:JSONEncode({ Version = 1, Config = copy, Totals = totals, Elapsed = os.clock() - sessionStart }))
    end)
end
local function loadNow()
    if type(readfile) ~= "function" or type(resume) == "table" then return end
    local ok, data = pcall(function() return HttpService:JSONDecode(readfile(cfgFile)) end)
    if ok and type(data) == "table" and type(data.Config) == "table" then
        for k, v in pairs(data.Config) do if C[k] ~= nil and type(C[k]) == type(v) then C[k] = v end end
        if type(data.Totals) == "table" then for k, v in pairs(data.Totals) do if totals[k] ~= nil and type(v) == "number" then totals[k] = v end end end
        for k, ctrl in pairs(controls) do if C[k] ~= nil then pcall(function() ctrl:SetValue(C[k]) end) end end
    end
end
local SaveOK, SaveManager = pcall(function() return loadstring(game:HttpGet(repo .. "addons/SaveManager.lua"))() end)
if SaveOK and SaveManager and type(writefile) == "function" then
    SaveManager:SetLibrary(Library)
    SaveManager:IgnoreThemeSettings()
    SaveManager:SetIgnoreIndexes({ "MenuKey", "WebhookURL" })
    SaveManager:SetFolder("DQRB")
    SaveManager:BuildConfigSection(T.Settings)
end

local function unload()
    if not alive then return end
    alive = false
    saveNow()
    Combat.running = false
    clearWP()
    for _, c in ipairs(hooks) do pcall(function() c:Disconnect() end) end
    pcall(function() RunService:Set3dRenderingEnabled(true) end)
    if env.DQRB and env.DQRB.Config == C then env.DQRB = nil end
    if not Library.Unloaded then Library:Unload() end
end
Library:OnUnload(unload)
env.DQRB = { Config = C, Totals = totals, Combat = Combat, Unload = unload }

local teleportArmed = false
connect(player.OnTeleport, function(st)
    if st == Enum.TeleportState.Failed then teleportArmed = false; return end
    if st ~= Enum.TeleportState.Started or teleportArmed or type(queueFn) ~= "function" then return end
    saveNow()
    local snap = HttpService:JSONEncode({ Config = (function() local c = table.clone(C); c.WebhookURL = C.WebhookURL; return c end)(), Totals = totals, Elapsed = os.clock() - sessionStart })
    local src = env.DQRBSource
    if type(src) ~= "string" or #src < 100 then return end
    queueFn(string.format("getgenv().DQRBResume=game:GetService('HttpService'):JSONDecode(%q)\ngetgenv().DQRBSource=%q\nassert(loadstring(getgenv().DQRBSource))()", snap, src))
    teleportArmed = true
end)

-- Anti-AFK + fail/finish listeners
if C.AntiAFK then
    pcall(function()
        local VU = game:GetService("VirtualUser")
        connect(player.Idled, function() pcall(function() VU:CaptureController(); VU:ClickButton2(Vector2.new()) end) end)
    end)
end
for name, won in pairs({ loadCompleteGui = true, loadFailedGui = false }) do
    local r = remotes and remotes:FindFirstChild(name)
    if r then connect(r.OnClientEvent, function() finishRun(won) end) end
end
connect(player.CharacterAdded, function() clearWP(); Combat.lastPos = Vector3.zero end)

-- Streaming mode: mask local name labels
local streamPatches = {}
local function applyStream()
    for inst in pairs(streamPatches) do pcall(function() inst.Text = streamPatches[inst] end) end
    table.clear(streamPatches)
    if not C.StreamingMode then return end
    local roots = { player.PlayerGui }
    if player.Character then table.insert(roots, player.Character) end
    for _, root in ipairs(roots) do
        for _, l in ipairs(root:QueryDescendants("TextLabel")) do
            if l.Text == player.Name or l.Text == player.DisplayName then
                streamPatches[l] = l.Text
                l.Text = "Player"
            end
        end
    end
end

-- Target beam
local beam, beamA, beamB
local function clearBeam()
    if beam then beam:Destroy(); beam = nil end
    if beamA then beamA:Destroy(); beamA = nil end
    if beamB then beamB:Destroy(); beamB = nil end
end

-- ============================================================
-- Slow tick: lobby / carry / inventory / webhooks / recovery
-- ============================================================
local function allowedByWhitelist(name, id)
    local list = splitList(C.Whitelist)
    if #list == 0 then return true end
    for _, t in ipairs(list) do if t == normName(name) or t == tostring(id) then return true end end
    if C.AllowFriends then
        local ok, fr = pcall(player.IsFriendsWith, player, id)
        if ok and fr then return true end
    end
    return false
end

local function lobbyTick(now, inDungeon, started)
    if now - lastQueue < 5 then return end
    lastQueue = now
    job("lobby", function()
        if inDungeon then
            -- Inside dungeon: ready/start. Server enforces owner-only, so just attempt.
            if not started and (C.AutoStart or C.AutoReady) and now - placeStart >= C.StartDelay then
                G.tryCall("changeStartValue")
                G.tryCall("readyUp")
                lobbyStatus = "Starting run"
            end
            return
        end
        -- In lobby place:
        pcall(G.refreshCatalog)
        if C.AutoBest then
            local lvl = G.level()
            local best = lvl and G.bestFor(lvl)
            if best then
                C.LobbyDungeon, C.LobbyDifficulty = best.Dungeon, best.Difficulty
                pcall(function()
                    controls.LobbyDungeon:SetValue(best.Dungeon)
                    controls.LobbyDifficulty:SetValue(best.Difficulty)
                end)
            end
        end
        local wave = C.Mode == "Wave Defense"
        local raid = C.Mode == "Boss Raid"
        if raid then
            if not C.AutoRaid then raidStatus = "Raid paused"; return end
            local lobbies = Workspace:FindFirstChild("bossLobbies")
            if lobbies and lobbies:FindFirstChild(player.Name) then
                raidStatus = "Starting raid"
                G.tryCall("startBossRaid")
            else
                local inv = G.tryCall("reloadInvy") or inventoryCache
                local tier = tonumber(C.RaidTier) or 1
                raidStatus = "Creating tier " .. tier
                if G.tryCall("createBossLobby", tier, C.PrivateLobby, 0) == nil then raidStatus = "Raid request sent" end
            end
            return
        end
        -- Auto join host takes priority over creating
        if C.AutoJoinHost and C.JoinHostName ~= "" then
            lobbyStatus = "Joining " .. C.JoinHostName
            pcall(G.call, "joinDungeon", C.JoinHostName)
            pcall(G.call, "sendJoinRequest", C.JoinHostName, false)
            local mine = G.findMyLobby()
            if mine then lobbyStatus = "In lobby, waiting for start" end
            return
        end
        if C.AutoCreate then
            local mine = G.findMyLobby()
            if mine then
                if C.Whitelist ~= "" then
                    for _, t in ipairs(splitList(C.Whitelist)) do pcall(G.call, "addPlayerToWhitelist", t) end
                end
                lobbyStatus = "Lobby ready"
                if C.AutoStart and now - placeStart >= C.StartDelay then
                    if G.tryCall("startDungeon") ~= nil then lobbyStatus = "Entering dungeon" end
                end
            else
                lobbyStatus = "Creating " .. C.LobbyDungeon .. " " .. C.LobbyDifficulty
                local ok, err = pcall(G.makeLobby, C.LobbyDungeon, C.LobbyDifficulty, C.Hardcore, C.PrivateLobby, wave)
                lobbyStatus = ok and "Lobby created" or ("Create failed: " .. tostring(err):match("[^\n:]+$"):sub(1, 80))
            end
        end
    end)
end

local function carryTick(now, inDungeon, started)
    if not C.CarryFinder then carryStatus = "Idle"; return end
    job("carry", function()
        if inDungeon then
            if G.failed() then
                carryStatus = "Run failed, recovering"
                if C.StuckRecovery then G.tryCall("teleToLobby") end
                return
            end
            if not started then carryStatus = "Waiting for carrier to start"; return end
            -- heal carrier
            if C.HealCarrier then
                local members = {}
                for _, p in ipairs(Players:GetPlayers()) do
                    table.insert(members, { player = p, isCarrier = carryTarget and p.Name == carryTarget })
                end
                castHealIfNeeded(members, now)
            end
            carryStatus = started and ("Farming" .. (carryTarget and (" with " .. carryTarget) or "")) or carryStatus
            -- stall detection: no target + no progress
            if C.StuckRecovery then
                local _, _, root = charParts()
                if root then
                    if not stuckPos or (root.Position - stuckPos).Magnitude > 4 then stuckPos, stuckAt = root.Position, now
                    elseif now - stuckAt > C.CarryStallTimeout and now - lastRecover > 30 then
                        lastRecover = now
                        carryStatus = "Stalled, recovering"
                        G.tryCall("teleToLobby")
                    end
                end
            end
            return
        end
        -- Lobby: find best carry lobby
        local lobbies = G.scanLobbies()
        local lvl = G.level()
        local allowDiff = {}
        for _, d in ipairs(C.CarryDifficulties or {}) do allowDiff[d] = true end
        local scored = {}
        for _, l in ipairs(lobbies) do
            if l.host ~= player.Name and allowedByWhitelist(l.host, 0) ~= false then
                local req = catalog[l.Dungeon] and catalog[l.Dungeon][l.Difficulty] and catalog[l.Dungeon][l.Difficulty].levelReq
                local diffOk = allowDiff[l.Difficulty] ~= false or next(allowDiff) == nil
                local hcOk = C.CarryHardcore == "Any" or (C.CarryHardcore == "Yes") == l.Hardcore
                local nameOk = (C.CarryHost == "") or normName(l.host) == normName(C.CarryHost)
                if diffOk and hcOk and nameOk and req then
                    local score = req
                    if C.BestProgression and lvl then score = (req <= lvl + 40) and req or (req - 1000) end
                    table.insert(scored, { l = l, score = score })
                end
            end
        end
        table.sort(scored, function(a, b) return a.score > b.score end)
        local pick = scored[1] and scored[1].l
        if C.CarryHost ~= "" then
            for _, s in ipairs(scored) do if normName(s.l.host) == normName(C.CarryHost) then pick = s.l break end end
        end
        if not pick then carryStatus = "Searching (" .. #lobbies .. " lobbies)"; return end
        carryTarget = pick.host
        carryStatus = "Joining " .. pick.host .. " | " .. pick.Dungeon .. " " .. pick.Difficulty
        if now - carryJoinAt >= math.max(3, C.CarryJoinDelay) then
            carryJoinAt = now
            -- Verified live: public/whitelisted joins use joinDungeon(host).
            -- Private request flow uses sendJoinRequest(name, force) with 12s force arm.
            local ok = pcall(G.call, "joinDungeon", pick.host)
            if ok then carryStatus = "Join sent to " .. pick.host else carryStatus = "Join failed, requesting " .. pick.host end
            pcall(G.call, "sendJoinRequest", pick.host, false)
        end
        -- Global cross-server fallback: listGlobalParties / joinGlobalParty.
        if now - (carryStallAt or 0) > C.CarryStallTimeout then
            carryStallAt = now
            job("globalCarry", function()
                local list = G.tryCall("listGlobalParties", C.LobbyDungeon ~= "" and C.LobbyDungeon or nil)
                if type(list) == "table" then
                    for _, g in ipairs(list) do
                        if type(g) == "table" and g.jobId and g.ownerName and (C.CarryHost == "" or normName(g.ownerName) == normName(C.CarryHost)) then
                            pcall(G.call, "joinGlobalParty", g.jobId, g.ownerName)
                            carryStatus = "Global join " .. tostring(g.ownerName)
                            break
                        end
                    end
                end
            end)
        end
    end)
end

local function upkeepTick(now)
    -- balances / totals / labels
    local cur = G.readBalances()
    for k, v in pairs(cur) do totals[k] = totals[k] + math.max(0, v - balances[k]) end
    balances = cur
    local inDungeon = G.inDungeonPlace()
    local started = inDungeon and G.started()
    if started and not wasStarted then
        runStart, runCounted, runEnded = now, false, false
        runBalances, runKills = cur, Combat.kills
        job("snap", function() local ok, inv = pcall(G.inventory); if ok then runInventory = inv end end)
    end
    wasStarted = started
    if not runCounted and started and G.done() then finishRun(true) end
    if not runCounted and G.failed() then finishRun(false) end
    local wantFarm = C.AutoDungeon and started and not runEnded and now - placeStart >= C.StartDelay
    if C.CarryFinder and inDungeon and started then wantFarm = true end
    Combat.running = wantFarm == true
    Combat.status = not started and (inDungeon and "Waiting for start" or "In lobby") or (Combat.running and "Farming" or "Idle")

    if C.AutoSkill and now - lastSkill >= 3 then
        local pts = G.val(player, "skillPoints", 0)
        if pts and pts > 0 then
            lastSkill = now
            job("skill", function()
                local map = { ["Spell Power"] = "spellPower", ["Physical Power"] = "physicalPower", Stamina = "stamina" }
                pcall(G.call, "spendSkillPoint", map[C.SkillStat] or "spellPower", pts)
            end)
        end
    end
    if C.AutoEquip and now - lastEquip >= 10 then
        lastEquip = now
        job("equip", function()
            local inv = G.inventory()
            for _, e in ipairs(bestGear(inv, assert(G.level(), "lvl"), C.Build)) do
                pcall(G.call, "equipItem", e.kind, e.id)
                task.wait(0.25)
            end
        end)
    end
    if C.AutoSell and now - lastSell >= 8 then
        lastSell = now
        job("sell", function()
            if G.val(player, "busyTrading", false) then return end
            local inv = G.inventory()
            local plan, n = sellPlan(inv)
            if n == 0 then return end
            local pending = {}
            for kind, ids in pairs(plan) do
                local cat = kind == "ability" and "abilities" or kind .. "s"
                for _, id in ipairs(ids) do
                    local key = kind .. "_" .. id
                    table.insert(pending, cat .. ":" .. tostring(inv[cat][key].UniqueItemID or key))
                end
            end
            G.call("sellItemEvent", plan)
            pendingSale = pending
            task.wait(3)
            local ok2, inv2 = pcall(G.inventory)
            if ok2 then
                local seen = {}
                for cat, items in pairs(inv2) do if type(items) == "table" then for id, it in pairs(items) do if type(it) == "table" then seen[cat .. ":" .. tostring(it.UniqueItemID or id)] = true end end end end
                local gone = 0
                for _, k in ipairs(pending) do if not seen[k] then gone += 1 end end
                soldVerified += gone
            end
            pendingSale = nil
        end)
    end
    if C.FPSEnabled and type(setfpscap) == "function" then pcall(setfpscap, math.clamp(tonumber(C.FPSLimit) or 60, 15, 360)) end
    if C.AFKMode then
        RunService:Set3dRenderingEnabled(false)
        pcall(function() Lighting.GlobalShadows = false end)
        if type(setfpscap) == "function" then pcall(setfpscap, 30) end
    end
    applyStream()

    lobbyTick(now, inDungeon, started)
    carryTick(now, inDungeon, started)

    setLab("DStatus", "Status: " .. Combat.status)
    setLab("DStats", "Wins: " .. totals.Wins .. " Losses: " .. totals.Losses .. " | " .. fmtTime(os.clock() - sessionStart))
    setLab("DCasts", "Q/E: " .. Combat.qCasts .. "/" .. Combat.eCasts .. " | Kills: " .. Combat.kills)
    setLab("LobbyStatus", "Lobby: " .. lobbyStatus)
    setLab("RaidStatus", "Raid: " .. raidStatus)
    setLab("CarryStatus", "Carry: " .. carryStatus)
    setLab("CarryStats", "Runs " .. totals.Runs .. " | Wins " .. totals.Wins .. " | Losses " .. totals.Losses)
    setLab("CarryGains", "Coins " .. totals.Coins .. " | Gems " .. totals.Gems)
    setLab("SellStatus", C.AutoSell and ("Sell: armed | verified " .. soldVerified) or "Sell: off")
    setLab("WStats", "Runs " .. totals.Runs .. " | " .. fmtTime(os.clock() - sessionStart))
    setLab("WGains", "Coins " .. totals.Coins .. " | Gems " .. totals.Gems .. " | Lv " .. totals.Levels)
    local dn = {}
    for _, d in ipairs(lastDrops or {}) do table.insert(dn, d.name) end
    setLab("WDrops", "Last drops: " .. (#dn > 0 and table.concat(dn, ", "):sub(1, 120) or "none"))
    setLab("MStatus", "Uptime " .. fmtTime(os.clock() - sessionStart) .. " | Recoveries " .. Combat.recoveries)
end

-- ============================================================
-- Per-frame combat driver
-- ============================================================
local beamN = 0
connect(RunService.Heartbeat, function()
    if not alive then return end
    local now = os.clock()
    local ch, hum, root = charParts()
    if hum and root and hum.Health > 0 then
        if C.MoveSpeedEnabled then
            pcall(function() hum.WalkSpeed = math.clamp(C.MoveSpeed, 8, 60) end)
        elseif Combat.running then
            pcall(function() hum.WalkSpeed = 16 end)
        end
        if Combat.running then
            local foe, dist = pickFoe(root, now)
            local foeRoot = foe and modelRoot(foe)
            setLab("DTarget", "Target: " .. (foe and foe.Name or "scanning") .. " (" .. math.floor(dist or 0) .. ")")
            if foe and foeRoot then
                -- face target (yaw only)
                local p = root.Position
                local look = Vector3.new(foeRoot.Position.X, p.Y, foeRoot.Position.Z)
                if (look - p).Magnitude > 0.05 then pcall(function() root.CFrame = CFrame.new(p, look) end) end
                local threat = senseThreat(root, foe, now)
                local dodged = threat and tryDodge(hum, root, foeRoot, threat, now) or false
                if not dodged then
                    local goal = farmGoal(root, foeRoot)
                    gotoPos(hum, root, goal, "combat", now)
                    updateStuck(hum, root, goal, now)
                end
                local range = math.max(8, C.AbilityRange)
                if (foeRoot.Position - root.Position).Magnitude <= math.max(range, C.BossDistance + 4) then
                    castAbilities(now)
                    -- basic attack: activate equipped tool
                    for _, t in ipairs(ch:GetChildren()) do
                        if t:IsA("Tool") then pcall(function() t:Activate() end); break end
                    end
                end
                -- kill counting
                local fh = foe:FindFirstChildOfClass("Humanoid")
                if fh then
                    local prev = Combat["hp_" .. foe:GetDebugId()]
                    if prev and prev > 0 and fh.Health <= 0 then Combat.kills += 1; totals.Kills += 1 end
                    Combat["hp_" .. foe:GetDebugId()] = fh.Health
                end
                if C.TargetBeam then
                    beamN += 1
                    if beamN % 30 == 1 then
                        clearBeam()
                        beamA, beamB = Instance.new("Attachment"), Instance.new("Attachment")
                        beamA.Parent, beamB.Parent = root, foeRoot
                        beam = Instance.new("Beam")
                        beam.Attachment0, beam.Attachment1 = beamA, beamB
                        beam.Width0, beam.Width1 = 0.1, 0.1
                        beam.Parent = root
                    end
                else clearBeam() end
            else
                Combat.status = "Scanning"
                hum:MoveTo(root.Position)
            end
        else
            clearBeam()
        end
        -- death counting
        local key = "me_" .. hum:GetDebugId()
        local prev = Combat[key]
        if prev and prev > 0 and hum.Health <= 0 then totals.Deaths += 1 end
        Combat[key] = hum.Health
    end
    if now - (Combat.slowAt or 0) >= 0.5 and not busy.slow then
        Combat.slowAt = now
        job("slow", function() upkeepTick(now) end)
    end
end)

-- Disconnect / stuck-session recovery hooks
connect(game:GetService("ScriptContext").Error, function() end)
task.spawn(function()
    while alive do
        task.wait(15)
        if alive and C.DisconnectRecovery then saveNow() end
    end
end)

loadNow()
pcall(G.refreshCatalog)
job("inv0", function() pcall(G.inventory) end)
notify("DQ Reborn loaded. Enable automation per tab.")
