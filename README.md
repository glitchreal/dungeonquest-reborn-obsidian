# Dungeon Quest Reborn — Obsidian

Fresh hub for Dungeon Quest Reborn (lobby + dungeon). RightShift toggles the menu.

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/glitchreal/dungeonquest-reborn-obsidian/main/main.luau"))()
```

Supports all live dungeons (verified via `getDungeonStats`, Sep 2026):

Desert Temple, Winter Outpost, Pirate Island, King's Castle, The Underworld,
Samurai Palace, The Canals, Ghastly Harbor, Steampunk Sewers, Orbital Outpost,
Volcanic Chambers, Aquatic Temple, Enchanted Forest, Northern Lands,
Gilded Skies (190/195), Oni Dungeon (195/200).

Event maps (Tutorial, Egg Island, Krampus) are excluded from best-dungeon picks.

## Tabs

- Dungeon: automation, farm position, boss distance, ability range, move speed,
  auto abilities/spam, bounded auto dodge, dynamic melee distance, auto replay.
- Carry Finder: `joinDungeon` local joins + `sendJoinRequest` private flow +
  `listGlobalParties`/`joinGlobalParty` fallback, best progression,
  difficulty/hardcore filters, stall recovery, heal carrier, session stats.
- Lobby: auto create/start/ready, auto best, auto join host, dungeon/wave/boss-raid
  modes, private + whitelist, raid tiers via `createBossLobby`/`startBossRaid`.
- Inventory: spell/physical best gear, rarity selling, keep list, duplicate abilities.
- Webhooks: wins/losses, drops, wanted pings, coins/gems, JobId tag.
- Other: skill points, AFK performance, anti-AFK, FPS limit, streaming mode,
  stuck/disconnect recovery, config save/autoload + teleport continuation.

Live-verified remotes: `createLobby`, `joinDungeon`, `sendJoinRequest`,
`listGlobalParties`, `joinGlobalParty`, `startDungeon`, `changeStartValue`,
`readyUp`, `leaveGame`, `teleToLobby`, `replayDungeon`, `reloadInvy`,
`getDungeonStats`, `equipItem`, `sellItemEvent`, `spendSkillPoint`,
`abilityUsed`, `addPlayerToWhitelist`, `createBossLobby`, `startBossRaid`.
