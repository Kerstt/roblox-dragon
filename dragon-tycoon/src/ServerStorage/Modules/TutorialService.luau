-- ServerStorage/Modules/TutorialService
-- Moves each new player through Shared/TutorialConfig and pays the rewards.
-- Steps complete from real actions (RemoteService calls OnAction after a
-- successful request) or, for "Ride", from the dragon actually flying.
-- Players who already played before the tutorial existed skip it.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TutorialConfig = require(ReplicatedStorage.Shared.TutorialConfig)
local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local MountService = require(script.Parent.MountService)

local TutorialService = {}

local changed = Instance.new("BindableEvent")
TutorialService.Changed = changed.Event -- (player)
local notice = Instance.new("BindableEvent")
TutorialService.Notice = notice.Event -- (player, "TutorialStep", { Title, Reward, Finished })

local FLY_HEIGHT = 35 -- a ridden dragon above this height counts as flying

local function advance(player: Player, data: any)
	local step = data.Tutorial.Step
	local info = TutorialConfig.Get(step)
	if not info then
		return
	end
	if info.Reward > 0 then
		EconomyService.AddCoins(player, info.Reward, "Tutorial")
	end
	data.Tutorial.Step = step + 1
	local finished = TutorialConfig.Get(data.Tutorial.Step) == nil
	if finished then
		data.Tutorial.Step = TutorialConfig.Done
		EconomyService.AddCoins(player, TutorialConfig.FinishReward, "Tutorial")
	end
	notice:Fire(player, "TutorialStep", { Title = info.Title, Reward = info.Reward, Finished = finished, Bonus = if finished then TutorialConfig.FinishReward else 0 })
	changed:Fire(player)
end

-- Called after any successful request. action = the request name; extra = its first argument.
function TutorialService.OnAction(player: Player, action: string, extra: any)
	local data = DataService.GetData(player)
	if not data or data.Tutorial.Step >= TutorialConfig.Done then
		return
	end
	local info = TutorialConfig.Get(data.Tutorial.Step)
	if not info then
		return
	end
	if info.Id == "Starter" and action == "ChooseStarter" then
		advance(player, data)
	elseif info.Action == "Practice" and action == "QueueJoin" and extra == "Practice" then
		advance(player, data)
	elseif info.Action and info.Action == action then
		advance(player, data)
	end
end

local function rideCheck()
	for _, player in Players:GetPlayers() do
		local data = DataService.GetData(player)
		if data and data.Tutorial.Step < TutorialConfig.Done then
			local info = TutorialConfig.Get(data.Tutorial.Step)
			if info and info.Id == "Ride" then
				local _, root = MountService.GetMount(player)
				if root and root.Position.Y > FLY_HEIGHT then
					advance(player, data)
				end
			end
		end
	end
end

function TutorialService.init()
	DataService.ProfileLoaded:Connect(function(player: Player)
		-- BindableEvents copy tables, so change the live save from GetData.
		local data = DataService.GetData(player)
		if not data then
			return
		end
		-- Players from before the tutorial existed skip it.
		if data.Tutorial.Step == 0 and data.Stats.Hatches > 0 then
			data.Tutorial.Step = TutorialConfig.Done
		elseif data.Tutorial.Step == 0 and data.Tutorial.Starter ~= "" then
			data.Tutorial.Step = 1
		end
	end)
	task.spawn(function()
		while true do
			task.wait(1)
			local ok, err = pcall(rideCheck)
			if not ok then
				warn("[TutorialService] ride check failed:", err)
			end
		end
	end)
end

return TutorialService
