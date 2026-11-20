-- ServerScriptService/Main
-- Server bootstrap: starts each system in order. All logic lives in the
-- ModuleScripts in ServerStorage/Modules.

local ServerStorage = game:GetService("ServerStorage")
local Modules = ServerStorage:WaitForChild("Modules")

local DataService = require(Modules.DataService)
local PlayerPolicyService = require(Modules.PlayerPolicyService)
local PurchaseService = require(Modules.PurchaseService)
local EconomyService = require(Modules.EconomyService)
local EggRollLog = require(Modules.EggRollLog)
local SanctuaryService = require(Modules.SanctuaryService)
local RemoteService = require(Modules.RemoteService)
local PlotService = require(Modules.PlotService)
local MountService = require(Modules.MountService)
local LevelService = require(Modules.LevelService)
local CombatService = require(Modules.CombatService)
local QueueService = require(Modules.QueueService)
local ShopService = require(Modules.ShopService)
local TutorialService = require(Modules.TutorialService)

-- 1. Saving must exist before anything touches player data.
DataService.init()
-- 2. Systems that react to players and their data.
PlayerPolicyService.init()
PurchaseService.init()
EconomyService.init()
EggRollLog.init()
SanctuaryService.init() -- before RemoteService, so offline income is in the first state push
RemoteService.init()
PlotService.init()
MountService.init()
LevelService.init()
CombatService.init() -- after RemoteService (adds Remotes/Combat) and MountService
QueueService.init()
ShopService.init() -- registers Developer Products with PurchaseService
TutorialService.init()
-- 3. Start loading players last, so every listener is connected first.
DataService.start()

print("[Main] Dragon Tycoon server started")
