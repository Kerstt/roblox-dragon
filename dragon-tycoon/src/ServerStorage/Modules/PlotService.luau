-- ServerStorage/Modules/PlotService
-- Gives each player their own plot and keeps the world in sync with their save:
-- owner sign, station built/scaffold, station billboards, the "Manage"
-- prompts, and the dragon models working at each station.
--
-- Expects Workspace.Plots/PlotN built to the level-design naming contract.
-- Dragon models come from DragonVisuals (realistic models, station size).

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared

local Elements = require(Shared.Elements)
local SanctuaryConfig = require(Shared.SanctuaryConfig)
local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local SanctuaryLogic = require(script.Parent.SanctuaryLogic)
local SanctuaryService = require(script.Parent.SanctuaryService)
local DragonVisuals = require(script.Parent.DragonVisuals)

local PlotService = {}

local WHITE = Color3.new(1, 1, 1)

type PlotState = {
	Model: Model,
	Owner: Player?,
	-- dragonId -> model, "station:rarity:species" key, and current slot
	Dragons: { [string]: { Model: Model, Key: string, Slot: number } },
	DragonFolder: Folder,
	StationOpen: { [string]: boolean }, -- last built/scaffold state shown
}

local REFRESH_INTERVAL = 0.25 -- batch plot refreshes (clients can trigger many changes)

local plots: { PlotState } = {}
local plotOf: { [Player]: PlotState } = {}
local characterConnections: { [Player]: RBXScriptConnection } = {}

-- Visual helpers -------------------------------------------------------------------

local function setPartsVisible(container: Instance, visible: boolean)
	for _, part in container:GetDescendants() do
		if part:IsA("BasePart") then
			if visible then
				part.Transparency = part:GetAttribute("BaseTransparency") or 0
				part.CanCollide = part:GetAttribute("BaseCanCollide") ~= false
			else
				part.Transparency = 1
				part.CanCollide = false
			end
		end
	end
end

local function rememberCollision(container: Instance, default: boolean?)
	for _, part in container:GetDescendants() do
		if part:IsA("BasePart") and part:GetAttribute("BaseCanCollide") == nil then
			part:SetAttribute("BaseCanCollide", if default ~= nil then default else part.CanCollide)
		end
	end
end

local function makeBillboard(adornee: BasePart, name: string, size: UDim2, offset: Vector3, maxDistance: number): TextLabel
	local gui = Instance.new("BillboardGui")
	gui.Name = name
	gui.Size = size
	gui.StudsOffset = offset
	gui.MaxDistance = maxDistance
	gui.LightInfluence = 0
	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = WHITE
	label.TextStrokeTransparency = 0.35
	label.RichText = true
	label.Parent = gui
	gui.Adornee = adornee
	gui.Parent = adornee
	return label
end

local function formatNumber(n: number): string
	local suffixes = { "", "K", "M", "B", "T", "Qa" }
	local i = 1
	while math.abs(n) >= 1000 and i < #suffixes do
		n /= 1000
		i += 1
	end
	local text = if i == 1 and n == math.floor(n) then tostring(n) else string.format("%.1f", n)
	return (text:gsub("%.0$", "")) .. suffixes[i]
end

-- Dragon models ------------------------------------------------------------------------

-- The realistic dragon model, scaled down to stand at a station slot.
local function buildDragon(dragonId: string, dragon: any): Model?
	local model = DragonVisuals.Build(dragon, "Station")
	if not model then
		return nil
	end
	model.Name = dragonId
	local root = model.PrimaryPart :: BasePart
	root.Anchored = true
	CollectionService:AddTag(model, "AnimatedDragon")
	return model
end

local function placeOnSlot(model: Model, slot: BasePart)
	local root = model.PrimaryPart :: BasePart
	local rootToPivot = root.CFrame:ToObjectSpace(model:GetPivot())
	local floorY = slot.Position.Y - slot.Size.Y / 2
	local position = Vector3.new(slot.Position.X, floorY + (model:GetAttribute("FootOffset") or root.Size.Y / 2), slot.Position.Z)
	local rootTarget = CFrame.lookAlong(position, slot.CFrame.LookVector)
	model:PivotTo(rootTarget * rootToPivot)
end

-- Plot sync ---------------------------------------------------------------------------

local function stationIncome(data: any, station: string, multiplier: number): number
	local level = data.Sanctuary.Stations[station].Level
	local total = 0
	for _, id in SanctuaryLogic.DragonsAt(data, station) do
		total += SanctuaryConfig.DragonIncome(data.Dragons[id], station, level)
	end
	return total * multiplier
end

local function refreshPlot(state: PlotState)
	local owner = state.Owner
	local data = owner and DataService.GetData(owner)
	local stationsFolder = state.Model:FindFirstChild("Stations")
	local multiplier = if owner then EconomyService.GetIncomeMultiplier(owner) else 1

	-- Stations
	for _, station in SanctuaryConfig.Stations do
		local model = stationsFolder and stationsFolder:FindFirstChild(station)
		if model then
			local info = data and data.Sanctuary.Stations[station]
			local open = data == nil or info.Slots > 0 -- unowned plots look finished
			if state.StationOpen[station] ~= open then
				state.StationOpen[station] = open
				if model:FindFirstChild("Built") then
					setPartsVisible(model.Built, open)
				end
				if model:FindFirstChild("Scaffold") then
					setPartsVisible(model.Scaffold, not open)
				end
			end
			local signAnchor = model:FindFirstChild("SignAnchor")
			local sign = signAnchor and signAnchor:FindFirstChild("StationSign")
			if sign then
				sign.Enabled = data ~= nil
				if data then
					local used = #SanctuaryLogic.DragonsAt(data, station)
					local prefers = table.concat(Elements.StationAffinity[station], " & ")
					local line2 = if info.Slots > 0
						then string.format("%d/%d dragons  •  %s/s", used, info.Slots, formatNumber(stationIncome(data, station, multiplier)))
						else "Unlock a slot to build"
					sign.Text.Text = string.format("<b>%s</b>  Lv %d\n%s\n<font size=\"14\">%s +25%%</font>", station:upper(), info.Level, line2, prefers)
				end
			end
			local prompt = model:FindFirstChild("Prompt")
			prompt = prompt and prompt:FindFirstChild("ManagePrompt")
			if prompt then
				prompt:SetAttribute("OwnerId", if owner then owner.UserId else 0)
			end
		end
	end

	-- Owner sign
	local ownerSign = state.Model:FindFirstChild("OwnerSign")
	local label = ownerSign and ownerSign:FindFirstChild("OwnerGui") and ownerSign.OwnerGui:FindFirstChild("Text")
	if label then
		label.Text = if owner then owner.DisplayName .. "'s Sanctuary" else "Empty Sanctuary"
	end

	-- Dragons at stations
	local wanted: { [string]: { Key: string, Station: string, Slot: number } } = {}
	if data then
		for _, station in SanctuaryConfig.Stations do
			for slot, id in SanctuaryLogic.DragonsAt(data, station) do
				local d = data.Dragons[id]
				wanted[id] = { Key = station .. ":" .. d.Rarity .. ":" .. d.Species, Station = station, Slot = slot }
			end
		end
	end
	for id, entry in state.Dragons do
		if not wanted[id] or wanted[id].Key ~= entry.Key then
			entry.Model:Destroy()
			state.Dragons[id] = nil
		end
	end
	for id, want in wanted do
		local stationModel = stationsFolder and stationsFolder:FindFirstChild(want.Station)
		local slotPart = stationModel and stationModel:FindFirstChild("Slot" .. want.Slot)
		local entry = state.Dragons[id]
		if entry then
			-- Same dragon, same station: just move it if its slot changed.
			if entry.Slot ~= want.Slot and slotPart then
				placeOnSlot(entry.Model, slotPart)
				entry.Slot = want.Slot
			end
		else
			local model = slotPart and buildDragon(id, data.Dragons[id])
			if model then
				placeOnSlot(model, slotPart)
				model.Parent = state.DragonFolder
				state.Dragons[id] = { Model = model, Key = want.Key, Slot = want.Slot }
			end
		end
	end
end

-- Plot ownership ----------------------------------------------------------------------

local function teleportToPlot(player: Player, character: Model)
	local state = plotOf[player]
	local spawnPart = state and state.Model:FindFirstChild("Spawn") :: BasePart?
	if not spawnPart then
		return
	end
	local root = character:WaitForChild("HumanoidRootPart", 10)
	if root and plotOf[player] == state then
		task.wait() -- let the default spawn finish first
		character:PivotTo(spawnPart.CFrame + Vector3.new(0, 3, 0))
	end
end

local function claimPlot(player: Player)
	if plotOf[player] then
		return
	end
	for _, state in plots do
		if not state.Owner then
			state.Owner = player
			plotOf[player] = state
			state.Model:SetAttribute("OwnerId", player.UserId)
			player:SetAttribute("Plot", state.Model.Name)
			refreshPlot(state)
			characterConnections[player] = player.CharacterAdded:Connect(function(character)
				teleportToPlot(player, character)
			end)
			if player.Character then
				task.spawn(teleportToPlot, player, player.Character)
			end
			return
		end
	end
	warn("[PlotService] No free plot for", player.Name, "- set Max Players to 8 in Game Settings")
end

local function releasePlot(player: Player)
	local state = plotOf[player]
	if characterConnections[player] then
		characterConnections[player]:Disconnect()
		characterConnections[player] = nil
	end
	if not state then
		return
	end
	plotOf[player] = nil
	state.Owner = nil
	state.Model:SetAttribute("OwnerId", nil)
	refreshPlot(state)
end

function PlotService.GetPlot(player: Player): Model?
	local state = plotOf[player]
	return state and state.Model
end

-- Setup ----------------------------------------------------------------------------------

local function preparePlot(model: Model): PlotState
	local stationsFolder = model:FindFirstChild("Stations")
	for _, station in SanctuaryConfig.Stations do
		local stationModel = stationsFolder and stationsFolder:FindFirstChild(station)
		if stationModel then
			if stationModel:FindFirstChild("Built") then
				rememberCollision(stationModel.Built)
			end
			if stationModel:FindFirstChild("Scaffold") then
				rememberCollision(stationModel.Scaffold, true)
			end
			local signAnchor = stationModel:FindFirstChild("SignAnchor")
			if signAnchor and not signAnchor:FindFirstChild("StationSign") then
				local label = makeBillboard(signAnchor, "StationSign", UDim2.fromOffset(220, 78), Vector3.zero, 90)
				;(label.Parent :: BillboardGui).Enabled = false
			end
			local promptPart = stationModel:FindFirstChild("Prompt")
			if promptPart and not promptPart:FindFirstChild("ManagePrompt") then
				local prompt = Instance.new("ProximityPrompt")
				prompt.Name = "ManagePrompt"
				prompt.ActionText = "Manage"
				prompt.ObjectText = station
				prompt.HoldDuration = 0
				prompt.MaxActivationDistance = 14
				prompt.RequiresLineOfSight = false
				prompt:SetAttribute("Station", station)
				prompt:SetAttribute("OwnerId", 0)
				prompt.Parent = promptPart
			end
		end
	end

	local ownerSign = model:FindFirstChild("OwnerSign")
	if ownerSign and not ownerSign:FindFirstChild("OwnerGui") then
		local gui = Instance.new("SurfaceGui")
		gui.Name = "OwnerGui"
		gui.Face = Enum.NormalId.Front
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 40
		gui.LightInfluence = 0
		local label = Instance.new("TextLabel")
		label.Name = "Text"
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.GothamBold
		label.TextScaled = true
		label.TextColor3 = Color3.fromRGB(40, 35, 30)
		label.Text = "Empty Sanctuary"
		label.Parent = gui
		gui.Parent = ownerSign
	end

	local folder = model:FindFirstChild("Dragons") or Instance.new("Folder")
	folder.Name = "Dragons"
	folder.Parent = model
	return { Model = model, Owner = nil, Dragons = {}, DragonFolder = folder :: Folder, StationOpen = {} }
end

function PlotService.init()
	local folder = workspace:FindFirstChild("Plots")
	if not folder then
		warn("[PlotService] Workspace.Plots is missing")
		return
	end
	local models = folder:GetChildren()
	table.sort(models, function(a, b)
		return (tonumber(a.Name:match("%d+")) or 0) < (tonumber(b.Name:match("%d+")) or 0)
	end)
	for _, model in models do
		if model:IsA("Model") then
			local state = preparePlot(model)
			table.insert(plots, state)
			refreshPlot(state)
		end
	end

	DataService.ProfileLoaded:Connect(claimPlot)
	Players.PlayerRemoving:Connect(releasePlot)
	-- Batch refreshes: many quick changes cost one refresh per interval.
	local pending: { [Player]: boolean } = {}
	SanctuaryService.Changed:Connect(function(player, reason)
		if reason ~= "settings" then -- settings don't change anything in the world
			pending[player] = true
		end
	end)
	task.spawn(function()
		while true do
			task.wait(REFRESH_INTERVAL)
			for player in pending do
				pending[player] = nil
				local state = plotOf[player]
				if state then
					local ok, err = pcall(refreshPlot, state)
					if not ok then
						warn("[PlotService] Refresh failed:", err)
					end
				end
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		pending[player] = nil
	end)
	-- Station signs show income; refresh them now and then (passes, etc.).
	task.spawn(function()
		while true do
			task.wait(10)
			for _, state in plots do
				if state.Owner then
					pcall(refreshPlot, state)
				end
			end
		end
	end)
end

return PlotService
