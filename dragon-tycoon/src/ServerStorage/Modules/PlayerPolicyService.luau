-- ServerStorage/Modules/PlayerPolicyService
-- Reads Roblox's per-player policy flags and tells the rest of the game.
--
-- Fail closed: every player starts as "paid random items restricted" and
-- "no paid-item trading" until Roblox confirms otherwise. If the check never
-- succeeds, they stay restricted, so nobody sees Robux eggs or luck boosts by
-- mistake.
--
-- The flags are also copied to player attributes so client UI can read them:
--   PaidRandomItemsRestricted (bool), PaidItemTradingAllowed (bool), PolicyLoaded (bool)
-- Client UI is only for display. Purchases must always re-check on the server.

local Players = game:GetService("Players")
local PolicyService = game:GetService("PolicyService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)

local PlayerPolicyService = {}

export type Policy = {
	ArePaidRandomItemsRestricted: boolean,
	IsPaidItemTradingAllowed: boolean,
	Loaded: boolean, -- false until Roblox has answered
}

local RETRY_DELAYS = { 0, 2, 5, 10, 20, 40 } -- seconds before each attempt

local policies: { [Player]: Policy } = {}
local changed = Instance.new("BindableEvent")
-- Fires (player, policy) whenever a player's policy is set or updated.
PlayerPolicyService.PolicyChanged = changed.Event

-- Turns Roblox's answer into our policy. Anything missing or odd is restrictive.
function PlayerPolicyService.fromPolicyInfo(info: any, loaded: boolean): Policy
	info = if type(info) == "table" then info else {}
	return {
		ArePaidRandomItemsRestricted = info.ArePaidRandomItemsRestricted ~= false,
		IsPaidItemTradingAllowed = info.IsPaidItemTradingAllowed == true,
		Loaded = loaded,
	}
end

local function setPolicy(player: Player, policy: Policy)
	if RunService:IsStudio() and type(GameConfig.StudioPolicyOverride) == "table" then
		for key, value in GameConfig.StudioPolicyOverride do
			if policy[key] ~= nil and type(value) == "boolean" then
				policy[key] = value
			end
		end
	end
	policies[player] = policy
	player:SetAttribute("PaidRandomItemsRestricted", policy.ArePaidRandomItemsRestricted)
	player:SetAttribute("PaidItemTradingAllowed", policy.IsPaidItemTradingAllowed)
	player:SetAttribute("PolicyLoaded", policy.Loaded)
	changed:Fire(player, table.clone(policy))
end

local function fetchPolicy(player: Player)
	setPolicy(player, PlayerPolicyService.fromPolicyInfo(nil, false))
	for attempt, delay in RETRY_DELAYS do
		if delay > 0 then
			task.wait(delay)
		end
		if player.Parent ~= Players then
			return
		end
		local ok, info = pcall(PolicyService.GetPolicyInfoForPlayerAsync, PolicyService, player)
		if player.Parent ~= Players then
			return -- left while we waited; don't recreate their entry
		end
		if ok and type(info) == "table" then
			setPolicy(player, PlayerPolicyService.fromPolicyInfo(info, true))
			return
		end
		warn("[PlayerPolicyService] Policy check failed for", player.Name, "attempt", attempt, info)
	end
	warn("[PlayerPolicyService] Giving up on", player.Name, "- keeping them restricted")
end

-- A copy of the player's policy (restrictive if unknown).
function PlayerPolicyService.GetPolicy(player: Player): Policy
	local policy = policies[player]
	return if policy then table.clone(policy) else PlayerPolicyService.fromPolicyInfo(nil, false)
end

-- True only when Roblox confirmed this player may buy paid random items
-- (Robux eggs, luck boosts).
function PlayerPolicyService.CanBuyPaidRandomItems(player: Player): boolean
	local policy = policies[player]
	return policy ~= nil and policy.Loaded and not policy.ArePaidRandomItemsRestricted
end

-- True only when Roblox confirmed this player may trade paid items.
-- Trading is not in v1; check this before building it.
function PlayerPolicyService.CanTradePaidItems(player: Player): boolean
	local policy = policies[player]
	return policy ~= nil and policy.Loaded and policy.IsPaidItemTradingAllowed
end

function PlayerPolicyService.init()
	Players.PlayerAdded:Connect(fetchPolicy)
	Players.PlayerRemoving:Connect(function(player)
		policies[player] = nil
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(fetchPolicy, player)
	end
end

return PlayerPolicyService
