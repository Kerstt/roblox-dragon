-- ServerStorage/Modules/DevBridge
-- Studio-only test hook. In Studio (never in a live server) it adds a
-- BindableFunction, ServerStorage/DevBridge, so test scripts and plugins can
-- drive the running game: give a dragon, summon it, remove it again.
-- ServerStorage is never visible to clients, and live servers skip this entirely.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local DataService = require(script.Parent.DataService)
local DragonService = require(script.Parent.DragonService)
local MountService = require(script.Parent.MountService)

local DevBridge = {}

local COMMANDS = {}

function COMMANDS.GiveDragon(player: Player, species: string, rarity: string?)
	local data = DataService.GetData(player)
	if not data then
		return false, "no_data"
	end
	local id = DragonService.Create(data, species, rarity or "Common", 10, "DevBridge")
	return true, id
end

function COMMANDS.RemoveDragon(player: Player, dragonId: string)
	local data = DataService.GetData(player)
	if not data or not data.Dragons[dragonId] then
		return false, "not_found"
	end
	pcall(MountService.Dismiss, player)
	data.Dragons[dragonId] = nil
	return true
end

function COMMANDS.Summon(player: Player, dragonId: string)
	return MountService.Summon(player, dragonId)
end

function COMMANDS.Dismiss(player: Player)
	return MountService.Dismiss(player)
end

function DevBridge.init()
	if not RunService:IsStudio() then
		return
	end
	local fn = Instance.new("BindableFunction")
	fn.Name = "DevBridge"
	fn.OnInvoke = function(command: string, userId: number, ...)
		local handler = COMMANDS[command]
		local player = Players:GetPlayerByUserId(userId)
		if not handler or not player then
			return false, "bad_command_or_player"
		end
		return handler(player, ...)
	end
	fn.Parent = ServerStorage
end

return DevBridge
