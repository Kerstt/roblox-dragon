-- StarterPlayerScripts/ClientMain
-- Client bootstrap: builds the screens and wires the station prompts.
-- All screen code lives in ReplicatedStorage/Client.

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Client = ReplicatedStorage:WaitForChild("Client")
local UI = require(Client.UI)
local Store = require(Client.Store)
local Hud = require(Client.Hud)
local HatchReveal = require(Client.HatchReveal)
local EggShop = require(Client.EggShop)
local DragonsSheet = require(Client.DragonsSheet)
local StationsSheet = require(Client.StationsSheet)
local StarterPicker = require(Client.StarterPicker)
local DragonAnimator = require(Client.DragonAnimator)
local FlightController = require(Client.FlightController)
local BattleSheet = require(Client.BattleSheet)
local CombatClient = require(Client.CombatClient)
local ShopSheet = require(Client.ShopSheet)
local TutorialGuide = require(Client.TutorialGuide)
local SoundManager = require(Client.SoundManager)

local player = Players.LocalPlayer

local screen = UI.new("ScreenGui", {
	Name = "DragonTycoonUI",
	ResetOnSpawn = false,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling, -- children always draw above their parent
	ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets,
	Parent = player:WaitForChild("PlayerGui"),
})
UI.attachResponsiveScale(screen, 740, 0.70)

Hud.init(screen, {
	{ Text = "Eggs", OnClick = function() EggShop.Open() end },
	{ Text = "Dragons", OnClick = function() DragonsSheet.Open() end },
	{ Text = "Stations", OnClick = function() StationsSheet.Open() end },
	{ Text = "Ride", OnClick = function() DragonsSheet.Open(nil, "ride") end },
	{ Text = "Battle", OnClick = function() BattleSheet.Open() end },
	{ Text = "Shop", OnClick = function() ShopSheet.Open() end },
})
HatchReveal.init(screen)
EggShop.init(screen)
DragonsSheet.init(screen)
StationsSheet.init(screen)
StarterPicker.init(screen)
BattleSheet.init(screen)
CombatClient.init(screen)
ShopSheet.init(screen)
TutorialGuide.init(screen)
SoundManager.start()

-- Station "Manage" prompts: only usable on your own plot.
local function syncPrompt(prompt: Instance)
	if prompt:IsA("ProximityPrompt") and prompt.Name == "ManagePrompt" then
		local function update()
			prompt.Enabled = prompt:GetAttribute("OwnerId") == player.UserId
		end
		update()
		prompt:GetAttributeChangedSignal("OwnerId"):Connect(update)
	end
end
local plots = workspace:WaitForChild("Plots", 30)
if plots then
	for _, d in plots:GetDescendants() do
		syncPrompt(d)
	end
	plots.DescendantAdded:Connect(syncPrompt)
end
ProximityPromptService.PromptTriggered:Connect(function(prompt)
	if prompt.Name == "ManagePrompt" and prompt:GetAttribute("OwnerId") == player.UserId then
		StationsSheet.Open(prompt:GetAttribute("Station"))
	end
end)

DragonAnimator.start()
FlightController.start()
Store.start()
