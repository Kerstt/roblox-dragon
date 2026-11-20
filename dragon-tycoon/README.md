# Dragon Tycoon

A Roblox dragon-sanctuary tycoon. Hatch eggs, put dragons to work at sanctuary
stations, expand, level your dragons up, ride and fly them over a medieval world,
and battle in sky arenas or team up against a daily Elder dragon.

This repository holds the game's **code** (every Script, LocalScript and
ModuleScript). The 3D world, dragon and egg models, terrain and UI layout live in
the Roblox place itself (place `102026554890017`, edited with Team Create).

## What's in the game

| Area | Highlights |
|---|---|
| Sanctuary (core loop) | 16 dragons, 8 elements, 6 rarities, 5 coin eggs with shown odds, 4 stations (Mine, Forge, Farm, Watchtower), slots, upgrades, offline income |
| Dragons | Realistic AI-generated models, procedural animation, riding and smooth flight, element effects |
| Leveling | Up to level 50; XP from station work, battles, Feed (coins) and Infuse (essence); skills unlock at 1 / 10 / 20 / 30 |
| Combat | Server-authoritative mounted air duels: Casual, Ranked (everyone at level 30, no rarity bonus) and Practice vs an AI dragon; 56 skills (3 + 1 ultimate per dragon), status effects, dodge, trophies |
| Co-op raid | 1-4 players vs a daily Elder dragon (rotates through the 8 elements); every attack is telegraphed |
| Monetization | Game passes, Robux eggs and Luck Boost (odds shown; hidden for policy-restricted players), choose-a-dragon (Epic max), cosmetics. No coin packs |
| Onboarding & feel | Guided 6-step tutorial, music and sound effects |

## Code layout

```
src/
  ServerScriptService/Main.server.luau      server bootstrap (starts every system in order)
  ServerStorage/Modules/                    server systems (data, economy, purchases, sanctuary,
                                            combat, raids, shop, tutorial, ...)
  ServerStorage/Tests/                      test suites (run from the Studio command bar)
  ServerStorage/Tools/                      editor tools (world generation, dragon rig builder)
  ReplicatedStorage/Shared/                 config and data tables shared by server and client
                                            (odds, skills, elements, products, ...)
  ReplicatedStorage/Client/                 client screens and controllers
  StarterPlayer/StarterPlayerScripts/       client bootstrap
```

`default.project.json` maps these folders back into the place with
[Rojo](https://rojo.space), if you want to edit the code in VS Code.
**Careful:** while Rojo is syncing, the files here overwrite the scripts in Studio.

## Rules the code keeps

* **The server decides everything that matters:** coins, rolls, purchases, damage,
  cooldowns, results. Clients only ask and display.
* **Saves are safe:** session-locked `UpdateAsync`, retries, autosave, no saving
  defaults over a failed load. Robux receipts are granted exactly once.
* **Roblox paid random items policy:** every egg shows all outcomes and their exact
  odds from the same table the server rolls; Robux eggs and Luck Boost are hidden
  and refused for restricted players (fail closed); every roll is logged.
* **Fair PvP:** rarity changes combat stats by at most 25%, Ranked normalizes level
  and rarity, egg power never affects combat, Robux never buys wins.

## Running the tests

In Studio's command bar (edit mode):

```lua
for _, n in {"Phase1Tests", "Phase2Tests", "ElementsTests", "Phase3Tests", "Phase4Tests"} do
	print(require(game.ServerStorage.Tests[n]).run())
end
```

## Before launch

* Create the 4 game passes and 5 developer products in Creator Hub and paste their
  IDs into `ReplicatedStorage/Shared/GameConfig` (`GamePasses`, `DevProducts`).
  Until then, Studio treats products with ID 0 as free test purchases.
* Set Max Players to 8 and Lighting > Technology to Future.
* Re-check Roblox's paid random items policy page.
