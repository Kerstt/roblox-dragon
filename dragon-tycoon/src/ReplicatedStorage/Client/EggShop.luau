-- ReplicatedStorage/Client/EggShop
-- Egg shop sheet. Every odd shown here comes from EggCatalog, the same table the
-- server rolls with. The rarity odds sit right above the Buy button; the full
-- list of every outcome is one tap away.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared

local UI = require(script.Parent.UI)
local Store = require(script.Parent.Store)
local Hud = require(script.Parent.Hud)
local HatchReveal = require(script.Parent.HatchReveal)
local Preview = require(script.Parent.Preview)
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
local oddsGrid: Frame
local oddsTitle: TextLabel
local quickToggle: TextButton
local luckEndsAt = 0 -- os.clock() when the Luck Boost ends (from the server's snapshot)
local shownLucky = false

-- The Luck Boost changes the odds; every odds view uses this so it always
-- shows exactly what the server will roll.
local function isLucky(): boolean
	return os.clock() < luckEndsAt
end

local function coins(): number
	return player:GetAttribute("Coins") or (Store.State and Store.State.Coins) or 0
end

local function refreshBuy()
	if not buyButton then
		return
	end
	local egg = EggCatalog.Get(selectedEgg) :: any
	local state = Store.State
	local priceText = "Hatch • ◉ " .. Format.Short(egg.Price)
	if hatching then
		setBuyEnabled(false, "Hatching...")
	elseif state and state.IdleCount >= state.NestCapacity then
		setBuyEnabled(false, "Nest full (" .. state.IdleCount .. "/" .. state.NestCapacity .. ")")
	elseif coins() < egg.Price then
		setBuyEnabled(false, priceText)
	else
		setBuyEnabled(true, priceText)
	end
	local quick = state and state.QuickHatch
	quickToggle.Text = if quick then "Quick hatch: ON" else "Quick hatch: OFF"
	quickToggle.BackgroundColor3 = if quick then UI.Colors.Good else UI.Colors.Secondary
end

local function renderOddsGrid()
	UI.clear(oddsGrid)
	shownLucky = isLucky()
	if oddsTitle then
		local left = math.max(0, math.floor(luckEndsAt - os.clock()))
		oddsTitle.Text = if shownLucky
			then string.format("<b>Rarity chances</b>  <font color=\"#%s\">Luck Boost on (%d:%02d left)</font>", UI.Colors.Good:ToHex(), left // 60, left % 60)
			else "<b>Rarity chances</b>"
	end
	for _, r in EggCatalog.GetRarityOdds(selectedEgg, shownLucky) do
		local info = Rarities.Info[r.Rarity]
		local cell = UI.new("Frame", { BackgroundColor3 = UI.Colors.Panel2, LayoutOrder = info.Rank, Parent = oddsGrid })
		UI.corner(cell, 8)
		UI.label(cell, string.format("<font color=\"#%s\"><b>%s</b></font>  %s", info.Color:ToHex(), r.Rarity, EggCatalog.FormatChance(r.Chance)), 14, {
			Size = UDim2.fromScale(1, 1),
			TextXAlignment = Enum.TextXAlignment.Center,
			TextWrapped = false,
			ZIndex = 7,
		})
	end
end

local function renderBody()
	local body = sheet.Body
	UI.clear(body)

	-- Egg picker
	local picker = UI.new("ScrollingFrame", {
		Size = UDim2.new(1, 0, 0, 96),
		BackgroundTransparency = 1,
		ScrollingDirection = Enum.ScrollingDirection.X,
		AutomaticCanvasSize = Enum.AutomaticSize.X,
		CanvasSize = UDim2.new(),
		ScrollBarThickness = 4,
		LayoutOrder = 1,
		Parent = body,
	})
	UI.list(picker, 8, true)
	for _, egg in EggCatalog.List do
		local selected = egg.Id == selectedEgg
		local button = UI.new("TextButton", {
			Size = UDim2.fromOffset(96, 88),
			BackgroundColor3 = if selected then UI.Colors.Panel3 else UI.Colors.Panel2,
			Text = "",
			LayoutOrder = egg.Order,
			Parent = picker,
		})
		UI.corner(button, 12)
		if selected then
			UI.stroke(button, UI.Colors.Gold, 2)
		end
		-- The real 3D egg (turns when selected); colored oval if the model is missing.
		local holder = UI.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 2),
			Size = UDim2.fromOffset(46, 46),
			BackgroundTransparency = 1,
			Parent = button,
		})
		if not Preview.Egg(holder, egg.Id, nil, if selected then 0.8 else 0) then
			local shape = UI.new("Frame", {
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.new(0.5, 0, 0, 4),
				Size = UDim2.fromOffset(30, 38),
				BackgroundColor3 = egg.Color,
				Parent = holder,
			})
			UI.new("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = shape })
		end
		UI.label(button, egg.Name:gsub(" Egg", ""), 13, {
			Position = UDim2.fromOffset(0, 46),
			Size = UDim2.new(1, 0, 0, 18),
			TextXAlignment = Enum.TextXAlignment.Center,
			Font = UI.FontBold,
		})
		UI.label(button, "◉ " .. Format.Short(egg.Price), 13, {
			Position = UDim2.fromOffset(0, 64),
			Size = UDim2.new(1, 0, 0, 18),
			TextXAlignment = Enum.TextXAlignment.Center,
			TextColor3 = UI.Colors.Gold,
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
		UI.button(body, if on then "Auto hatch: ON (tap to stop)" else "Auto hatch this egg", function()
			local result = Store.Request("SetAutoHatch", if on then "" else selectedEgg)
			if not result.ok then
				Hud.Error(result.error)
			end
		end, {
			LayoutOrder = 2, Size = UDim2.new(1, 0, 0, 38), TextSize = 14,
			BackgroundColor3 = if on then UI.Colors.Good else UI.Colors.Secondary,
			TextColor3 = if on then UI.Colors.ButtonText else UI.Colors.Text,
		})
	end

	local egg = EggCatalog.Get(selectedEgg) :: any
	UI.label(body, "<b>" .. egg.Name .. "</b>  •  " .. egg.Description, 15, { LayoutOrder = 2, Size = UDim2.new(1, 0, 0, 40) })
	UI.label(body, "Each hatch rolls a rarity and a dragon separately. These are the exact chances the game uses.", 13, {
		LayoutOrder = 3, Size = UDim2.new(1, 0, 0, 34), TextColor3 = UI.Colors.Muted,
	})

	-- Dragon odds
	UI.label(body, "<b>Dragons in this egg</b>", 15, { LayoutOrder = 4, TextColor3 = UI.Colors.Gold })
	local order = 5
	for _, d in EggCatalog.GetDragonOdds(selectedEgg) do
		local species = DragonCatalog.Get(d.Species) :: any
		local element = Elements.Info[species.Element]
		local row = UI.row(body, 26)
		row.LayoutOrder = order
		order += 1
		UI.dot(row, element.Color, 12)
		UI.label(row, species.Name .. "  <font color=\"#" .. UI.Colors.Muted:ToHex() .. "\">" .. element.DisplayName .. "</font>", 15, {
			Size = UDim2.new(0.7, 0, 1, 0), TextWrapped = false,
		})
		UI.label(row, EggCatalog.FormatChance(d.Chance), 15, {
			Size = UDim2.new(0.25, 0, 1, 0), TextXAlignment = Enum.TextXAlignment.Right, TextWrapped = false,
		})
	end

	-- Every outcome
	local outcomes = EggCatalog.GetOutcomeTable(selectedEgg, isLucky())
	local toggle = UI.button(body, (if showAllOutcomes then "Hide" else "Show") .. " every outcome (" .. #outcomes .. ")", function()
		showAllOutcomes = not showAllOutcomes
		renderBody()
	end, { BackgroundColor3 = UI.Colors.Secondary, TextColor3 = UI.Colors.Text, LayoutOrder = order })
	order += 1
	if showAllOutcomes then
		table.sort(outcomes, function(a, b)
			return a.Chance > b.Chance
		end)
		for _, o in outcomes do
			local info = Rarities.Info[o.Rarity]
			local row = UI.row(body, 22)
			row.LayoutOrder = order
			order += 1
			UI.label(row, string.format("<font color=\"#%s\">%s</font> %s", info.Color:ToHex(), o.Rarity, o.Species), 14, {
				Size = UDim2.new(0.7, 0, 1, 0), TextWrapped = false,
			})
			UI.label(row, EggCatalog.FormatChance(o.Chance), 14, {
				Size = UDim2.new(0.25, 0, 1, 0), TextXAlignment = Enum.TextXAlignment.Right, TextWrapped = false,
			})
		end
	end
	_ = toggle
end

local function hatch()
	if hatching then
		return
	end
	hatching = true
	refreshBuy()
	local result = Store.Request("Hatch", selectedEgg)
	if result.ok then
		local quick = Store.State and Store.State.QuickHatch
		sheet.Frame.Visible = false
		HatchReveal.Play(result.result, quick == true)
		sheet.Frame.Visible = true
	else
		Hud.Error(result.error)
	end
	hatching = false
	refreshBuy()
end

function EggShop.init(screen: ScreenGui)
	sheet = UI.sheet(screen, "Egg Shop", 154)

	-- Footer: rarity odds directly above the Buy button
	local footer = sheet.Footer
	oddsTitle = UI.label(footer, "<b>Rarity chances</b>", 14, { Size = UDim2.new(1, 0, 0, 18), TextColor3 = UI.Colors.Gold, TextWrapped = false })
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
	buyButton, setBuyEnabled = UI.button(footer, "Hatch", hatch, {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 1, 0),
		Size = UDim2.new(0.62, 0, 0, 52),
		TextSize = 18,
	})
	quickToggle = UI.button(footer, "Quick hatch: OFF", function()
		local on = not (Store.State and Store.State.QuickHatch)
		local result = Store.Request("SetQuickHatch", on)
		if not result.ok then
			Hud.Error(result.error)
		end
	end, {
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, 0, 1, 0),
		Size = UDim2.new(0.36, 0, 0, 52),
		TextSize = 14,
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
	-- Keep the boost timer ticking and redraw the odds the moment it starts or ends.
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
