-- ReplicatedStorage/Client/EggShop
-- Viking Egg Forge / Roost shop sheet. Every odd shown here comes from
-- EggCatalog, the same table the server rolls with. Rarity odds sit directly
-- above the Hatch button; the full outcome list is one tap away.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared

local UI = require(script.Parent.UI)
local Store = require(script.Parent.Store)
local Hud = require(script.Parent.Hud)
local HatchReveal = require(script.Parent.HatchReveal)
local Preview = require(script.Parent.Preview)
local VikingModels = require(script.Parent.VikingModels)
local DragonCatalog = require(Shared.DragonCatalog)
local EggCatalog = require(Shared.EggCatalog)
local Elements = require(Shared.Elements)
local Rarities = require(Shared.Rarities)
local Format = require(Shared.Format)

local EggShop = {}

local player = Players.LocalPlayer
local sheet: UI.Sheet
local selectedEgg = "Hatchling"
local showAllOutcomes = false
local hatching = false
local buyButton: TextButton
local setBuyEnabled: (boolean, string?) -> ()
local buyMultiButton: TextButton
local setBuyMultiEnabled: (boolean, string?) -> ()
local oddsGrid: Frame
local oddsTitle: TextLabel
local quickToggle: TextButton
local luckEndsAt = 0 -- os.clock() when the Luck Boost ends (from the server's snapshot)
local shownLucky = false

local function isLucky(): boolean
	return os.clock() < luckEndsAt
end

local function coins(): number
	return player:GetAttribute("Coins") or (Store.State and Store.State.Coins) or 0
end

local function needsNestRoom(egg: any, state: any): boolean
	if not state or not state.AutoRelease then
		return true
	end
	for rarity, weight in egg.RarityWeights do
		if weight > 0 and state.AutoRelease[rarity] ~= true then
			return true
		end
	end
	return false
end

local function refreshBuy()
	if not buyButton or not buyMultiButton then
		return
	end
	local egg = EggCatalog.Get(selectedEgg) :: any
	local state = Store.State
	local singleText = "Hatch x1 • ◉ " .. Format.Short(egg.Price)
	local multiPrice = egg.Price * 4
	local multiText = "Hatch x4 • ◉ " .. Format.Short(multiPrice)
	local usesRoom = needsNestRoom(egg, state)
	local bonusNeed = if selectedEgg == "Hatchling" and state and not state.BonusGiven then 1 else 0

	if hatching then
		setBuyEnabled(false, "Hatching...")
		setBuyMultiEnabled(false, "Hatching...")
	else
		local singleNeed = (if usesRoom then 1 else 0) + bonusNeed
		local multiNeed = (if usesRoom then 4 else 0) + bonusNeed

		if state and state.IdleCount + singleNeed > state.NestCapacity then
			setBuyEnabled(false, "Nest full")
		elseif coins() < egg.Price then
			setBuyEnabled(false, singleText)
		else
			setBuyEnabled(true, singleText)
		end

		if state and state.IdleCount + multiNeed > state.NestCapacity then
			setBuyMultiEnabled(false, "Need 4 nest")
		elseif coins() < multiPrice then
			setBuyMultiEnabled(false, multiText)
		else
			setBuyMultiEnabled(true, multiText)
		end
	end

	local quick = state and state.QuickHatch
	quickToggle.Text = if quick then "Quick: ON" else "Quick: OFF"
	quickToggle.BackgroundColor3 = if quick then UI.Colors.Good else UI.Colors.Secondary
	quickToggle.TextColor3 = if quick then UI.Colors.ButtonText else UI.Colors.Text
end

local function renderOddsGrid()
	UI.clear(oddsGrid)
	shownLucky = isLucky()
	if oddsTitle then
		local left = math.max(0, math.floor(luckEndsAt - os.clock()))
		oddsTitle.Text = if shownLucky
			then string.format("<b>Rarity Chances</b>  <font color=\"#%s\">Luck Boost (%d:%02d)</font>", UI.Colors.Good:ToHex(), left // 60, left % 60)
			else "<b>Rarity Chances</b>"
	end
	for _, r in EggCatalog.GetRarityOdds(selectedEgg, shownLucky) do
		local info = Rarities.Info[r.Rarity]
		local cell = UI.new("Frame", { BackgroundColor3 = Color3.fromRGB(44, 38, 34), LayoutOrder = info.Rank, ZIndex = 16, Parent = oddsGrid })
		UI.corner(cell, 6)
		UI.stroke(cell, info.Color, 1.3)
		UI.label(cell, string.format("<font color=\"#%s\"><b>%s</b></font>  %s", info.Color:ToHex(), r.Rarity, EggCatalog.FormatChance(r.Chance)), 13, {
			Size = UDim2.fromScale(1, 1),
			TextXAlignment = Enum.TextXAlignment.Center,
			TextWrapped = false,
			ZIndex = 17,
		})
	end
end

local function renderBody()
	local body = sheet.Body
	UI.clear(body)

	-- Viking Pedestal Egg Picker
	local picker = UI.new("ScrollingFrame", {
		Size = UDim2.new(1, 0, 0, 112),
		BackgroundTransparency = 1,
		ScrollingDirection = Enum.ScrollingDirection.X,
		AutomaticCanvasSize = Enum.AutomaticSize.X,
		CanvasSize = UDim2.new(),
		ScrollBarThickness = 4,
		ScrollBarImageColor3 = UI.Colors.Stroke,
		LayoutOrder = 1,
		Parent = body,
	})
	UI.list(picker, 8, true)
	for _, egg in EggCatalog.List do
		local selected = egg.Id == selectedEgg
		local button = UI.new("TextButton", {
			Size = UDim2.fromOffset(110, 102),
			BackgroundColor3 = if selected then Color3.fromRGB(78, 56, 36) else Color3.fromRGB(44, 40, 42),
			AutoButtonColor = false,
			Text = "",
			LayoutOrder = egg.Order,
			Parent = picker,
		})
		UI.corner(button, 8)
		UI.gradient(button, Color3.fromRGB(252, 240, 220), Color3.fromRGB(156, 138, 126), 90)
		UI.stroke(button, if selected then UI.Colors.Gold else UI.Colors.IronMid, if selected then 2.0 else 1.3)
		UI.rivets(button, if selected then UI.Colors.Gold else UI.Colors.Rivet, 4, button.ZIndex + 3, 5)

		local aura = UI.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 6),
			Size = UDim2.fromOffset(52, 52),
			BackgroundColor3 = Color3.fromRGB(24, 18, 16),
			Parent = button,
		})
		UI.corner(aura, 26)
		UI.stroke(aura, if selected then egg.Color else UI.Colors.IronOuter, 1.4)
		if not Preview.Egg(aura, egg.Id, { ZIndex = button.ZIndex + 2 }, if selected then 0.9 else 0) then
			VikingModels.ViewportEgg(aura, egg.Color, UI.Colors.Gold, if selected then 0.9 else 0, button.ZIndex + 2, egg.Id)
		end

		UI.label(button, egg.Name:gsub(" Egg", ""), 13, {
			Font = UI.FontDisplay,
			Position = UDim2.fromOffset(4, 60),
			Size = UDim2.new(1, -8, 0, 18),
			TextXAlignment = Enum.TextXAlignment.Center,
			TextColor3 = if selected then UI.Colors.Gold else UI.Colors.Text,
			TextWrapped = false,
		})
		UI.label(button, "◉ " .. Format.Short(egg.Price), 12, {
			Position = UDim2.fromOffset(4, 79),
			Size = UDim2.new(1, -8, 0, 18),
			TextXAlignment = Enum.TextXAlignment.Center,
			TextColor3 = UI.Colors.GoldSoft,
			Font = UI.FontBold,
			TextWrapped = false,
		})
		button.Activated:Connect(function()
			selectedEgg = egg.Id
			showAllOutcomes = false
			renderBody()
			renderOddsGrid()
			refreshBuy()
		end)
	end

	-- Auto Hatch pass: keep hatching this egg
	local shop = Store.State and Store.State.Shop
	if shop and shop.Passes.AutoHatch then
		local on = shop.AutoHatchEgg == selectedEgg
		UI.button(body, if on then "Auto Hatch: ON (tap to stop)" else "Auto Hatch This Egg", function()
			local result = Store.Request("SetAutoHatch", if on then "" else selectedEgg)
			if not result.ok then
				Hud.Error(result.error)
			end
		end, {
			LayoutOrder = 2, Size = UDim2.new(1, 0, 0, 40), TextSize = 14,
			BackgroundColor3 = if on then UI.Colors.Good else UI.Colors.Secondary,
			TextColor3 = if on then UI.Colors.ButtonText else UI.Colors.Text,
		})
	end

	-- Selected Egg Plaque with prominent 3D Real Egg Model Stage
	local egg = EggCatalog.Get(selectedEgg) :: any
	local infoCard = UI.card(body, { LayoutOrder = 3 })
	UI.stroke(infoCard, egg.Color, 1.6)
	local heroRow = UI.row(infoCard, 90, 12)
	local heroStage = UI.new("Frame", {
		Size = UDim2.fromOffset(86, 86),
		BackgroundColor3 = Color3.fromRGB(24, 18, 16),
		Parent = heroRow,
	})
	UI.corner(heroStage, 10)
	UI.stroke(heroStage, egg.Color, 1.5)
	if not Preview.Egg(heroStage, egg.Id, { ZIndex = heroStage.ZIndex + 1 }, 0.75, 0.76) then
		VikingModels.ViewportEgg(heroStage, egg.Color, UI.Colors.Gold, 0.75, heroStage.ZIndex + 1, egg.Id)
	end

	local heroText = UI.new("Frame", {
		Size = UDim2.new(1, -98, 1, 0),
		BackgroundTransparency = 1,
		Parent = heroRow,
	})
	UI.list(heroText, 4)
	UI.label(heroText, string.format("<b>%s</b>  <font color=\"#%s\">(x%s Egg Power)</font>", egg.Name, UI.Colors.Gold:ToHex(), Format.Short(egg.Power or 1)), 16, {
		Font = UI.FontDisplay,
		TextColor3 = UI.Colors.Gold,
		Size = UDim2.new(1, 0, 0, 22),
	})
	UI.label(heroText, egg.Description, 13, { Size = UDim2.new(1, 0, 0, 20), AutomaticSize = Enum.AutomaticSize.Y })
	UI.label(heroText, "Each hatch rolls rarity and dragon separately using the exact chances below.", 12, {
		Size = UDim2.new(1, 0, 0, 20), AutomaticSize = Enum.AutomaticSize.Y, TextColor3 = UI.Colors.Muted,
	})

	-- Dragon odds
	UI.label(body, "<b>Dragons in This Egg</b>", 15, { Font = UI.FontDisplay, LayoutOrder = 4, TextColor3 = UI.Colors.Gold })
	local order = 5
	for _, d in EggCatalog.GetDragonOdds(selectedEgg) do
		local species = DragonCatalog.Get(d.Species) :: any
		local element = Elements.Info[species.Element]
		local rowCard = UI.card(body, { LayoutOrder = order })
		UI.padding(rowCard, 6)
		order += 1
		local row = UI.row(rowCard, 24)
		UI.dot(row, element.Color, 12)
		UI.label(row, species.Name .. "  <font color=\"#" .. UI.Colors.Muted:ToHex() .. "\">" .. element.DisplayName .. "</font>", 14, {
			Size = UDim2.new(0.7, 0, 1, 0), TextWrapped = false, Font = UI.FontBold,
		})
		UI.label(row, EggCatalog.FormatChance(d.Chance), 14, {
			Size = UDim2.new(0.24, 0, 1, 0), TextXAlignment = Enum.TextXAlignment.Right, TextWrapped = false, TextColor3 = UI.Colors.Gold, Font = UI.FontBold,
		})
	end

	-- Every outcome
	local outcomes = EggCatalog.GetOutcomeTable(selectedEgg, isLucky())
	UI.button(body, (if showAllOutcomes then "Hide" else "Show") .. " Every Outcome (" .. #outcomes .. ")", function()
		showAllOutcomes = not showAllOutcomes
		renderBody()
	end, { BackgroundColor3 = UI.Colors.Secondary, TextColor3 = UI.Colors.Text, LayoutOrder = order })
	order += 1
	if showAllOutcomes then
		table.sort(outcomes, function(a, b)
			return a.Chance > b.Chance
		end)
		local listCard = UI.card(body, { LayoutOrder = order })
		UI.list(listCard, 3)
		for _, o in outcomes do
			local info = Rarities.Info[o.Rarity]
			local row = UI.row(listCard, 20)
			UI.label(row, string.format("<font color=\"#%s\">%s</font> %s", info.Color:ToHex(), o.Rarity, o.Species), 13, {
				Size = UDim2.new(0.7, 0, 1, 0), TextWrapped = false,
			})
			UI.label(row, EggCatalog.FormatChance(o.Chance), 13, {
				Size = UDim2.new(0.26, 0, 1, 0), TextXAlignment = Enum.TextXAlignment.Right, TextWrapped = false, TextColor3 = UI.Colors.Muted,
			})
		end
	end
end

local function hatch(count: number)
	if hatching then
		return
	end
	hatching = true
	refreshBuy()
	if count > 1 then
		local result = Store.Request("HatchMulti", selectedEgg, count)
		if result.ok and type(result.results) == "table" then
			local quick = Store.State and Store.State.QuickHatch
			sheet.Frame.Visible = false
			HatchReveal.PlayBatch(result.results, quick == true)
			sheet.Frame.Visible = true
		else
			Hud.Error(result.error)
		end
	else
		local result = Store.Request("Hatch", selectedEgg)
		if result.ok then
			local quick = Store.State and Store.State.QuickHatch
			sheet.Frame.Visible = false
			HatchReveal.Play(result.result, quick == true)
			sheet.Frame.Visible = true
		else
			Hud.Error(result.error)
		end
	end
	hatching = false
	refreshBuy()
end

function EggShop.init(screen: ScreenGui)
	sheet = UI.sheet(screen, "Egg Forge", 154, "Eggs")

	-- Footer: rarity odds directly above the Hatch x1 / Hatch x4 / Quick buttons
	local footer = sheet.Footer
	oddsTitle = UI.label(footer, "<b>Rarity Chances</b>", 14, { Font = UI.FontDisplay, Size = UDim2.new(1, 0, 0, 18), TextColor3 = UI.Colors.Gold, TextWrapped = false })
	oddsGrid = UI.new("Frame", {
		Position = UDim2.fromOffset(0, 20),
		Size = UDim2.new(1, 0, 0, 62),
		BackgroundTransparency = 1,
		Parent = footer,
	})
	UI.new("UIGridLayout", {
		CellSize = UDim2.new(1 / 3, -6, 0, 28),
		CellPadding = UDim2.fromOffset(6, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = oddsGrid,
	})
	buyButton, setBuyEnabled = UI.button(footer, "Hatch x1", function()
		hatch(1)
	end, {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 1, 0),
		Size = UDim2.new(0.38, -4, 0, 50),
		TextSize = 14,
	})
	buyMultiButton, setBuyMultiEnabled = UI.button(footer, "Hatch x4", function()
		hatch(4)
	end, {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.57, 0, 1, 0),
		Size = UDim2.new(0.38, -4, 0, 50),
		TextSize = 14,
		BackgroundColor3 = UI.Colors.Ember,
	})
	quickToggle = UI.button(footer, "Quick: OFF", function()
		local on = not (Store.State and Store.State.QuickHatch)
		local result = Store.Request("SetQuickHatch", on)
		if not result.ok then
			Hud.Error(result.error)
		end
	end, {
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, 0, 1, 0),
		Size = UDim2.new(0.24, -4, 0, 50),
		TextSize = 13,
		BackgroundColor3 = UI.Colors.Secondary,
		TextColor3 = UI.Colors.Text,
	})

	sheet.OnOpen.Event:Connect(function()
		renderBody()
		renderOddsGrid()
		refreshBuy()
	end)
	Store.Changed:Connect(function(state)
		local seconds = state.Shop and state.Shop.LuckSeconds or 0
		luckEndsAt = if seconds > 0 then os.clock() + seconds else 0
		refreshBuy()
		if sheet.IsOpen() then
			renderOddsGrid()
		end
	end)
	player:GetAttributeChangedSignal("Coins"):Connect(refreshBuy)
	task.spawn(function()
		while true do
			task.wait(1)
			if sheet.IsOpen() and (shownLucky or isLucky()) then
				local wasLucky = shownLucky
				renderOddsGrid()
				if wasLucky ~= shownLucky and showAllOutcomes then
					renderBody()
				end
			end
		end
	end)
end

function EggShop.Open()
	sheet.Open()
end

return EggShop
