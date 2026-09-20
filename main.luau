-- Dungeon Quest Reborn Obsidian loader
-- Usage:
--   loadstring(game:HttpGet("https://raw.githubusercontent.com/glitchreal/dungeonquest-reborn-obsidian/main/main.luau"))()
local ROOT = "https://raw.githubusercontent.com/glitchreal/dungeonquest-reborn-obsidian/main/"
if not game:IsLoaded() then game.Loaded:Wait() end
local ok, err = pcall(function()
    local src = game:HttpGet(ROOT .. "dist/DungeonQuestRebornObsidian.luau")
    assert(type(src) == "string" and #src > 1000, "bad download")
    getgenv().DQRBSource = src
    assert(loadstring(src, "DQRB"))()
end)
if not ok then warn("[DQRB] load failed: " .. tostring(err)) end
