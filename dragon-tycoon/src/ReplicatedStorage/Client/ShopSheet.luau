-- ReplicatedStorage/Client/ShopSheet
-- Viking Merchant Hall: Game Passes, Robux eggs & Luck Boost (hidden when policy
-- restricts paid random items, with every outcome's odds shown before buying),
-- choose-a-dragon, and dragon styles.

local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared

local UI = require(script.Parent.UI)
local Store = require(script.Parent.Store)
local Hud = require(script.Parent.Hud)
local Preview = require(script.Parent.Preview)
local VikingModels = require(script.Parent.VikingModels)
local HatchReveal = require(script.Parent.HatchReveal)
local GameConfig = require(Shared.GameConfig)
local ProductCatalog = require(Shared.ProductCatalog)
local CosmeticCatalog = require(Shared.CosmeticCatalog)
local EggCatalog = require(Shared.EggCatalog)
local DragonCatalog = require(Shared.DragonCatalog)
local Elements = require(Shared.Elements)
local Rarities = require(Shared.Rarities)

local ShopSheet = {}

local player = Players.LocalPlayer
local sheet: UI.Sheet
local tab = "Passes"
local pickedDragon = "Cindermaw"
local openOdds: { [string]: boolean } = {}
local prices: { [string]: number } = {}
local busy = false

local SPECIES = { "Cindermaw", "Pyrelance", "Briarhorn", "Sylvenreach", "Tidewhelp", "Deepkeel", "Quarrytusk", "Faultcrown",
	"Squallwing", "Thunderquill", "Rimeclaw", "Frostveil", "Dawnwarden", "Solhallow", "Duskrend", "Gloamveil" }

-- Fail closed: until Roblox confirms, treat the player as restricted.
local function restricted(): boolean
	return player:GetAttribute("PolicyLoaded") ~= true or player:GetAttribute("PaidRandomItemsRestricted") ~= false
end

local function priceText(key: string, fallback: number): string
	return "R$ " .. tostring(prices[key] or fallback)
end

local function loadPrices()
	for key, id in GameConfig.DevProducts do
		if id > 0 then
			task.spawn(function()
				local ok, info = pcall(MarketplaceService.GetProductInfo, MarketplaceService, id, Enum.InfoType.Product)
				if ok and info and info.PriceInRobux then
					prices[key] = info.PriceInRobux
				end
			end)
		end
	end
	for key, id in GameConfig.GamePasses do
		if id > 0 then
			task.spawn(function()
				local ok, info = pcall(MarketplaceService.GetProductInfo, MarketplaceService, id, Enum.InfoType.GamePass)
				if ok and info and info.PriceInRobux then
					prices[key] = info.PriceInRobux
				end
			end)
		end
	end
end

local render: () -> ()

local function buy(key: string, choice: string?)
	if busy then
		return
	end
	busy = true
	local result = Store.Request("Buy", key, choice)
	busy = false
	if not result.ok then
		Hud.Error(result.error)
	elseif result.test then
		Hud.Toast("Studio test purchase (no Robux spent).", UI.Colors.Muted)
	end
end

local function card(order: number, title: string, text: string?)
	local c = UI.card(sheet.Body, { LayoutOrder = order })
	UI.list(c, 6)
	UI.label(c, "<b>" .. title .. "</b>", 16, { Font = UI.FontDisplay, TextColor3 = UI.Colors.Gold })
	if text then
		UI.label(c, text, 13, { Size = UDim2.new(1, 0, 0, 20), AutomaticSize = Enum.AutomaticSize.Y, TextColor3 = UI.Colors.Muted })
	end
	return c
end

local function passesTab(state: any)
	for i, pass in ProductCatalog.Passes do
		local owned = state.Shop.Passes[pass.Key] == true
		local c = card(10 + i, pass.Name, pass.Text)
		local _, setEnabled = UI.button(c, if owned then "Owned" else priceText(pass.Key, pass.Price), function()
			local result = Store.Request("BuyPass", pass.Key)
			if not result.ok then
				Hud.Error(result.error)
			end
		end, { Size = UDim2.new(1, 0, 0, 42) })
		setEnabled(not owned)
	end
end

local function oddsList(parent: Instance, eggId: string)
	for _, r in EggCatalog.GetRarityOdds(eggId) do
		local info = Rarities.Info[r.Rarity]
		UI.label(parent, string.format("<font color=\"#%s\"><b>%s</b></font>  %s", info.Color:ToHex(), r.Rarity, EggCatalog.FormatChance(r.Chance)), 14, { Size = UDim2.new(1, 0, 0, 18) })
	end
	local key = eggId
	UI.button(parent, if openOdds[key] then "Hide Every Outcome" else "Show Every Outcome & Odds", function()
		openOdds[key] = not openOdds[key]
		render()
	end, { Size = UDim2.new(1, 0, 0, 34), TextSize = 13, BackgroundColor3 = UI.Colors.Secondary, TextColor3 = UI.Colors.Text })
	if openOdds[key] then
		local outcomes = EggCatalog.GetOutcomeTable(eggId)
		table.sort(outcomes, function(a, b)
			return a.Chance > b.Chance
		end)
		for _, o in outcomes do
			local info = Rarities.Info[o.Rarity]
			local species = DragonCatalog.Get(o.Species) :: any
			UI.label(parent, string.format("<font color=\"#%s\">%s</font> %s  <font color=\"#%s\">%s</font>", info.Color:ToHex(), o.Rarity, species.Name,
				UI.Colors.Muted:ToHex(), EggCatalog.FormatChance(o.Chance)), 12, { Size = UDim2.new(1, 0, 0, 16) })
		end
	end
end

local function eggsTab(state: any)
	if restricted() then
		card(10, "Not Available", "Robux eggs and the Luck Boost aren't available for your account. You can still choose an exact dragon or a dragon style!")
		return
	end
	local order = 10
	for _, egg in EggCatalog.RobuxEggs do
		local product = ProductCatalog.Products[egg.Id]
		local c = card(order, egg.Name, egg.Description)
		UI.stroke(c, egg.Color, 1.5)
		order += 1
		local holder = UI.new("Frame", { Size = UDim2.new(1, 0, 0, 74), BackgroundTransparency = 1, ZIndex = c.ZIndex + 1, Parent = c })
		if not Preview.Egg(holder, egg.Id, { Size = UDim2.fromOffset(74, 74), ZIndex = c.ZIndex + 2 }, 0.6) then
			local box = UI.new("Frame", { Size = UDim2.fromOffset(74, 74), BackgroundTransparency = 1, ZIndex = c.ZIndex + 2, Parent = holder })
			VikingModels.ViewportEgg(box, egg.Color, UI.Colors.Gold, 0.6, c.ZIndex + 2, egg.Id)
		end
		UI.label(c, "<b>Odds (shown before you buy):</b>", 13)
		oddsList(c, egg.Id)
		UI.button(c, "Buy " .. egg.Name .. "  " .. priceText(egg.Id, product.Price), function()
			buy(egg.Id)
		end, { Size = UDim2.new(1, 0, 0, 42) })
	end
	local luck = ProductCatalog.Products.LuckBoost
	local seconds = state.Shop.LuckSeconds or 0
	local c = card(order, luck.Name .. (if seconds > 0 then string.format("  (active: %d:%02d left)", seconds // 60, seconds % 60) else ""), luck.Text)
	UI.button(c, (if seconds > 0 then "Add 15 Minutes  " else "Buy Luck Boost  ") .. priceText("LuckBoost", luck.Price), function()
		buy("LuckBoost")
	end, { Size = UDim2.new(1, 0, 0, 42) })
end

local function dragonsTab(state: any)
	local product = ProductCatalog.Products.FixedDragon
	local c = card(10, product.Name, product.Text)
	local grid = UI.new("Frame", { Size = UDim2.new(1, 0, 0, 4 * 44), BackgroundTransparency = 1, Parent = c })
	UI.new("UIGridLayout", { CellSize = UDim2.new(0.25, -6, 0, 38), CellPadding = UDim2.fromOffset(6, 6), SortOrder = Enum.SortOrder.LayoutOrder, Parent = grid })
	for i, id in SPECIES do
		local species = DragonCatalog.Get(id) :: any
		local element = Elements.Info[species.Element]
		local chosen = pickedDragon == id
		local b = UI.button(grid, species.Name, function()
			pickedDragon = id
			render()
		end, {
			LayoutOrder = i, TextSize = 12,
			BackgroundColor3 = if chosen then element.Color else UI.Colors.Secondary,
			TextColor3 = if chosen then UI.Colors.ButtonText else UI.Colors.Text,
		})
		b.Name = id
	end
	local picked = DragonCatalog.Get(pickedDragon) :: any
	local preview = UI.new("Frame", { Size = UDim2.new(1, 0, 0, 132), BackgroundColor3 = UI.Colors.Panel2, Parent = c })
	UI.corner(preview, 8)
	UI.stroke(preview, Rarities.Info.Epic.Color, 1.6)
	Preview.Dragon(preview, pickedDragon, { Size = UDim2.fromScale(1, 1) }, 0.45)
	UI.label(c, string.format("You get exactly: <font color=\"#%s\"><b>Epic %s</b></font> (%s). No randomness.", Rarities.Info.Epic.Color:ToHex(), picked.Name, picked.Element), 14)
	UI.button(c, "Buy Epic " .. picked.Name .. "  " .. priceText("FixedDragon", product.Price), function()
		buy("FixedDragon", pickedDragon)
	end, { Size = UDim2.new(1, 0, 0, 42) })
	if state.Shop then
		return
	end
end

local function stylesTab(state: any)
	local product = ProductCatalog.Products.Cosmetic
	card(10, "Dragon Styles", product.Text .. " One trail and one aura can be worn at a time.")
	local owned = {}
	for _, id in state.Shop.Cosmetics do
		owned[id] = true
	end
	for i, cosmetic in CosmeticCatalog.List do
		local c = UI.card(sheet.Body, { LayoutOrder = 20 + i })
		local row = UI.row(c, 44)
		local swatch = UI.new("Frame", { Size = UDim2.fromOffset(40, 40), BackgroundColor3 = Color3.new(1, 1, 1), Parent = row })
		UI.corner(swatch, 8)
		UI.stroke(swatch, UI.Colors.Stroke, 1.4)
		UI.new("UIGradient", { Color = ColorSequence.new(cosmetic.Colors[1], cosmetic.Colors[2]), Rotation = 45, Parent = swatch })
		local info = UI.new("Frame", { Size = UDim2.new(1, -170, 1, 0), BackgroundTransparency = 1, Parent = row })
		UI.label(info, string.format("<b>%s</b>  <font color=\"#%s\">%s</font>", cosmetic.Name, UI.Colors.Muted:ToHex(), cosmetic.Kind), 14, { Size = UDim2.new(1, 0, 0, 20), TextWrapped = false })
		UI.label(info, cosmetic.Text, 12, { Position = UDim2.fromOffset(0, 20), Size = UDim2.new(1, 0, 0, 22), TextColor3 = UI.Colors.Muted })
		local wearing = state.Shop[cosmetic.Kind] == cosmetic.Id
		if owned[cosmetic.Id] then
			UI.button(row, if wearing then "Take off" else "Wear", function()
				local r = Store.Request("Equip", cosmetic.Kind, if wearing then "" else cosmetic.Id)
				if not r.ok then
					Hud.Error(r.error)
				else
					Hud.Toast("Summon your dragon again to see it.", UI.Colors.Muted)
				end
			end, {
				Size = UDim2.fromOffset(110, 38), TextSize = 14,
				BackgroundColor3 = if wearing then UI.Colors.Good else UI.Colors.Secondary,
				TextColor3 = if wearing then UI.Colors.ButtonText else UI.Colors.Text,
			})
		else
			UI.button(row, priceText("Cosmetic", product.Price), function()
				buy("Cosmetic", cosmetic.Id)
			end, { Size = UDim2.fromOffset(110, 38), TextSize = 14 })
		end
	end
end

local TABS = { "Passes", "Eggs", "Dragons", "Styles" }

render = function()
	local state = Store.State
	if not sheet or not sheet.IsOpen() or not state or not state.Shop then
		return
	end
	local body = sheet.Body
	local scroll = body.CanvasPosition
	UI.clear(body)

	-- Exact riveted 4-plaque Viking tab bar from shop.jpeg
	UI.tabBar(body, TABS, tab, function(selectedTab)
		tab = selectedTab
		render()
	end, 1)

	if RunService:IsStudio() then
		local notice = UI.new("Frame", {
			Size = UDim2.new(1, 0, 0, 32),
			BackgroundColor3 = Color3.fromRGB(48, 40, 34),
			LayoutOrder = 2,
			ZIndex = 15,
			Parent = body,
		})
		UI.corner(notice, 6)
		UI.stroke(notice, UI.Colors.IronMid, 1.2)
		UI.rivets(notice, UI.Colors.Rivet, 4, 16, 5)
		UI.label(notice, "Studio products without an ID are test purchases (free)", 13, {
			Position = UDim2.fromOffset(14, 0),
			Size = UDim2.new(1, -28, 1, 0),
			TextColor3 = UI.Colors.Text,
			TextWrapped = false,
			TextTruncate = Enum.TextTruncate.AtEnd,
			ZIndex = 16,
		})
	end
	if tab == "Passes" then
		passesTab(state)
	elseif tab == "Eggs" then
		eggsTab(state)
	elseif tab == "Dragons" then
		dragonsTab(state)
	else
		stylesTab(state)
	end
	task.defer(function()
		body.CanvasPosition = scroll
	end)
end

function ShopSheet.init(screen: ScreenGui)
	sheet = UI.sheet(screen, "Merchant Hall", 0, "Shop")
	sheet.OnOpen.Event:Connect(render)
	Store.Changed:Connect(render)
	player:GetAttributeChangedSignal("PaidRandomItemsRestricted"):Connect(render)
	task.spawn(loadPrices)

	Store.Notice:Connect(function(kind, payload)
		if type(payload) ~= "table" then
			return
		end
		if kind == "RobuxHatch" then
			local shown = table.clone(payload)
			if not EggCatalog.Get(shown.Egg) then
				shown.Egg = "RoyalEgg"
			end
			UI.CloseAllSheets()
			task.spawn(HatchReveal.Play, shown, false)
		elseif kind == "LuckBoost" then
			Hud.Toast("Luck Boost active! Rare and better chances are doubled on coin eggs.", UI.Colors.Good)
		elseif kind == "Cosmetic" then
			local cosmetic = CosmeticCatalog.Get(payload.Id)
			Hud.Toast("New style: " .. (if cosmetic then cosmetic.Name else "?") .. ". You're wearing it now!", UI.Colors.Gold)
		elseif kind == "AutoHatched" then
			local info = Rarities.Info[payload.Rarity]
			if info and info.Rank >= 3 then
				local species = DragonCatalog.Get(payload.Species)
				Hud.Toast(string.format("Auto hatch: %s %s!", payload.Rarity, if species then species.Name else "?"), info.Color)
			end
		elseif kind == "AutoHatchStopped" then
			Hud.Toast("Auto hatch stopped: " .. Store.ErrorText(payload.Reason), UI.Colors.Bad)
		end
	end)
end

function ShopSheet.Open(startTab: string?)
	if startTab then
		tab = startTab
	end
	sheet.Open()
end

return ShopSheet
