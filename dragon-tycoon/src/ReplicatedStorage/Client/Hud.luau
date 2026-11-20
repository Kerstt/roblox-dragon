-- ReplicatedStorage/Client/Hud
-- Unified Viking HUD built directly from hud.jpeg & shop.jpeg:
--   * Top-center ironbound weathered-oak Currency Plaque (3D Bearded-Axe Coin & Fehu Rune Crystal)
--   * Hanging forged-iron chains + 3-plank timber Goal signboard
--   * Riveted timber & iron Toast banners and Hearth Spoils modal
--   * Bottom 6-Arch Viking Longhouse Dock (EGGS, DRAGONS, STATIONS, RIDE, BATTLE, SHOP)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UI = require(script.Parent.UI)
local VikingModels = require(script.Parent.VikingModels)
local Store = require(script.Parent.Store)
local Format = require(ReplicatedStorage.Shared.Format)
local EggCatalog = require(ReplicatedStorage.Shared.EggCatalog)

local Hud = {}

local player = Players.LocalPlayer
local screen: ScreenGui
local toastHolder: Frame
local goalFrame: Frame
local goalLabel: TextLabel
local menuBar: Frame
local battleMode = false
local currentGoalText: string? = nil

local ARCH_RUNES = { "ᚠ", "ᚱ", "ᛉ", "ᚦ", "ᛟ" }

local function updateGoalVisibility()
	if goalFrame then
		goalFrame.Visible = (currentGoalText ~= nil) and not battleMode and not UI.IsAnySheetOpen()
	end
end

function Hud.Toast(text: string, color: Color3?)
	local accent = color or UI.Colors.Gold
	local toast = UI.new("Frame", {
		Size = UDim2.new(1, 0, 0, 44),
		BackgroundColor3 = UI.Colors.IronOuter,
		ZIndex = 30,
		Parent = toastHolder,
	})
	UI.ironWoodPlaque(toast, 2, 8, 5, 0)

	local gem = UI.new("Frame", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 16, 0.5, 0),
		Size = UDim2.fromOffset(9, 9),
		Rotation = 45,
		BackgroundColor3 = accent,
		ZIndex = 34,
		Parent = toast,
	})
	UI.stroke(gem, UI.Colors.WoodDark, 1.2)

	local label = UI.label(toast, text, 14, {
		Font = UI.FontBold,
		Position = UDim2.fromOffset(32, 6),
		Size = UDim2.new(1, -46, 1, -12),
		TextColor3 = if color == UI.Colors.Bad then UI.Colors.Bad else UI.Colors.Text,
		TextStrokeColor3 = UI.Colors.WoodDark,
		TextStrokeTransparency = 0.35,
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 34,
		Parent = toast,
	})

	toast.Position = UDim2.fromOffset(0, -10)
	UI.tween(toast, 0.2, { Position = UDim2.fromOffset(0, 0) }, Enum.EasingStyle.Back)

	task.delay(2.6, function()
		UI.tween(label, 0.28, { TextTransparency = 1, TextStrokeTransparency = 1 })
		task.wait(0.3)
		if toast.Parent then
			toast:Destroy()
		end
	end)
end

function Hud.Error(code: string?)
	Hud.Toast(Store.ErrorText(code), UI.Colors.Bad)
end

function Hud.SetBattleMode(on: boolean)
	battleMode = on
	if menuBar then
		menuBar.Visible = not on
	end
	updateGoalVisibility()
	if on then
		UI.CloseAllSheets()
	end
end

local function nextGoal(state: any): string?
	if state.Starter == "" or (state.TutorialStep and state.TutorialStep < 99) then
		return nil
	end
	if state.Hatches == 0 then
		return "<b>Next Saga Goal</b>\nBuy a Hatchling Egg (100 coins) — tap <b>EGGS</b> below."
	end
	local freeSlots = 0
	for _, s in state.Stations do
		freeSlots += s.Slots
	end
	local working = 0
	for _, d in state.Dragons do
		if d.Station then
			working += 1
		end
	end
	freeSlots -= working
	if state.IdleCount > 0 and freeSlots > 0 then
		return "<b>Next Saga Goal</b>\nPut a resting dragon to work — tap <b>DRAGONS</b>, then Assign."
	end
	if state.IdleCount > 0 and state.NextSlotCost and state.SlotsBought < 3 then
		return "<b>Next Saga Goal</b>\nUnlock another station slot inside <b>STATIONS</b>."
	end
	local grove = EggCatalog.Get("Grove")
	if grove and state.Coins < grove.Price and state.Hatches < 10 then
		return "<b>Sanctuary Goal</b>\nSave " .. Format.Commas(grove.Price) .. " coins for a Grove Egg (Storm & Ice dragons)."
	end
	return nil
end

local function welcomeBack(payload: any)
	local dim = UI.new("TextButton", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.45,
		Text = "",
		AutoButtonColor = false,
		ZIndex = 40,
		Parent = screen,
	})
	local box = UI.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(0.88, 0, 0, 304),
		BackgroundColor3 = UI.Colors.Panel,
		ZIndex = 41,
		Parent = dim,
	})
	UI.new("UISizeConstraint", { MaxSize = Vector2.new(420, 320), Parent = box })
	UI.vikingPanel(box, UI.Colors.Stroke, 12, 6)

	local crest = UI.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0, -2),
		Size = UDim2.fromOffset(70, 70),
		BackgroundColor3 = Color3.fromRGB(64, 44, 24),
		ZIndex = 43,
		Parent = box,
	})
	UI.corner(crest, 14)
	UI.stroke(crest, UI.Colors.Gold, 2.2)
	VikingModels.ViewportIcon(crest, "Shop", UDim2.fromScale(1.18, 1.18), 0.7, 44).Position = UDim2.fromScale(-0.09, -0.09)

	local content = UI.new("Frame", {
		Position = UDim2.fromOffset(20, 42),
		Size = UDim2.new(1, -40, 1, -56),
		BackgroundTransparency = 1,
		ZIndex = 42,
		Parent = box,
	})
	UI.list(content, 8).HorizontalAlignment = Enum.HorizontalAlignment.Center

	UI.label(content, "<b>Hearth Spoils Returned!</b>", 22, {
		Font = UI.FontDisplay,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = UI.Colors.Gold,
		ZIndex = 42,
	})
	UI.runeDivider(content, 2, UI.Colors.Stroke, 42)
	UI.label(content, "While you were away (" .. Format.Duration(payload.Seconds or 0) .. "), your dragons gathered:", 14, {
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, 0, 0, 38),
		TextColor3 = UI.Colors.Muted,
		ZIndex = 42,
	})
	local spoils = UI.new("Frame", {
		Size = UDim2.new(0.92, 0, 0, 50),
		BackgroundColor3 = UI.Colors.Panel3,
		ZIndex = 42,
		Parent = content,
	})
	UI.corner(spoils, 8)
	UI.stroke(spoils, UI.Colors.Gold, 1.8)
	UI.label(spoils, "<b>+" .. Format.Commas(payload.Coins or 0) .. " Coins</b>", 24, {
		Font = UI.FontDisplay,
		Size = UDim2.fromScale(1, 1),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = UI.Colors.Gold,
		ZIndex = 43,
	})
	UI.button(content, "Claim Spoils", function()
		dim:Destroy()
	end, { Size = UDim2.new(0.72, 0, 0, 44), ZIndex = 42 })
end

-- Builds one tall arched Viking portal button for the 6-button bottom dock (hud.jpeg)
local function buildArchDockButton(parent: Instance, index: number, total: number, item: { Text: string, OnClick: () -> () })
	local button = UI.new("TextButton", {
		Name = "Menu" .. item.Text, -- Preserved contract: TutorialGuide finds buttons by "Menu" .. name
		Size = UDim2.new(1 / total, -8, 1, 0),
		BackgroundTransparency = 1,
		Text = "",
		AutoButtonColor = false,
		LayoutOrder = index,
		ZIndex = 6,
		Parent = parent,
	})
	local scale = UI.new("UIScale", { Scale = 1, Parent = button })

	-- 1. Outer forged dark wrought-iron Arch Dome + Pillar Base
	local ironDome = UI.new("Frame", {
		Name = "IronArchDome",
		Size = UDim2.new(1, 0, 0, 88),
		BackgroundColor3 = UI.Colors.IronOuter,
		ZIndex = 6,
		Parent = button,
	})
	UI.new("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = ironDome })
	UI.gradient(ironDome, Color3.fromRGB(232, 236, 246), Color3.fromRGB(122, 126, 136), 90)
	UI.stroke(ironDome, UI.Colors.WoodDark, 1.8)

	local ironBase = UI.new("Frame", {
		Name = "IronArchBase",
		Position = UDim2.fromOffset(0, 42),
		Size = UDim2.new(1, 0, 1, -42),
		BackgroundColor3 = UI.Colors.IronOuter,
		ZIndex = 6,
		Parent = button,
	})
	UI.corner(ironBase, 6)
	UI.gradient(ironBase, Color3.fromRGB(190, 194, 204), Color3.fromRGB(108, 112, 122), 90)
	UI.stroke(ironBase, UI.Colors.WoodDark, 1.8)

	-- Seamless iron fill hiding the internal overlap line between dome and base
	UI.new("Frame", {
		Position = UDim2.fromOffset(2, 38),
		Size = UDim2.new(1, -4, 0, 14),
		BackgroundColor3 = UI.Colors.IronOuter,
		ZIndex = 6,
		Parent = button,
	})

	-- 7 round copper/brass rivets curving along the upper iron arch!
	for r = 1, 7 do
		local ang = math.rad(-76 + (r - 1) * (152 / 6))
		local rx = 0.5 + math.sin(ang) * 0.44
		local ry = 44 - math.cos(ang) * 39
		UI.roundRivet(button, UDim2.new(rx, 0, 0, ry), 5, 10)
	end

	-- 2. Burnished bronze-gold inner arch trim ring
	local goldDome = UI.new("Frame", {
		Position = UDim2.fromOffset(7, 7),
		Size = UDim2.new(1, -14, 0, 76),
		BackgroundColor3 = UI.Colors.Stroke,
		ZIndex = 7,
		Parent = button,
	})
	UI.new("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = goldDome })

	local goldBase = UI.new("Frame", {
		Position = UDim2.fromOffset(7, 44),
		Size = UDim2.new(1, -14, 1, -72),
		BackgroundColor3 = UI.Colors.Stroke,
		ZIndex = 7,
		Parent = button,
	})
	UI.corner(goldBase, 4)

	-- 3. Deep recessed dark hearth-alcove inside the golden arch
	local alcoveColor = Color3.fromRGB(24, 18, 15)
	local wellDome = UI.new("Frame", {
		Position = UDim2.fromOffset(9, 9),
		Size = UDim2.new(1, -18, 0, 72),
		BackgroundColor3 = alcoveColor,
		ZIndex = 8,
		Parent = button,
	})
	UI.new("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = wellDome })

	local wellBase = UI.new("Frame", {
		Position = UDim2.fromOffset(9, 44),
		Size = UDim2.new(1, -18, 1, -74),
		BackgroundColor3 = alcoveColor,
		ZIndex = 8,
		Parent = button,
	})
	UI.corner(wellBase, 3)

	-- Subtle warm hearth backlight glow behind the 3D miniature
	local glow = UI.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.40, 0),
		Size = UDim2.fromOffset(58, 58),
		BackgroundColor3 = Color3.fromRGB(168, 108, 48),
		BackgroundTransparency = 0.78,
		ZIndex = 8,
		Parent = button,
	})
	UI.corner(glow, 29)

	-- 4. Bright 3D miniature Viking diorama inside the arch alcove
	local vp = VikingModels.ViewportIcon(button, item.Text, UDim2.new(0.88, 0, 0, 76), 0, 9)
	vp.AnchorPoint = Vector2.new(0.5, 0)
	vp.Position = UDim2.new(0.5, 0, 0, 10)

	-- 5. Riveted dark-oak & iron bottom Nameplate Plaque ("EGGS", "DRAGONS", ...)
	local plate = UI.new("Frame", {
		Name = "Nameplate",
		Position = UDim2.new(0, 3, 1, -29),
		Size = UDim2.new(1, -6, 0, 27),
		BackgroundColor3 = UI.Colors.Panel,
		ZIndex = 10,
		Parent = button,
	})
	UI.corner(plate, 5)
	UI.stroke(plate, UI.Colors.IronMid, 1.5)
	UI.woodPlanks(plate, 2, 10, 4)
	UI.roundRivet(plate, UDim2.new(0, 6, 0.5, 0), 4, 12)
	UI.roundRivet(plate, UDim2.new(1, -6, 0.5, 0), 4, 12)

	local textLabel = UI.label(plate, "<b>" .. item.Text:upper() .. "</b>", if total > 5 then 12 else 13, {
		Font = UI.FontDisplay,
		Position = UDim2.fromOffset(8, 1),
		Size = UDim2.new(1, -16, 1, -2),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = UI.Colors.Gold,
		TextStrokeColor3 = UI.Colors.WoodDark,
		TextStrokeTransparency = 0.14,
		TextWrapped = false,
		ZIndex = 12,
		Parent = plate,
	})

	button.MouseEnter:Connect(function()
		UI.tween(scale, 0.12, { Scale = 1.05 })
		goldDome.BackgroundColor3 = UI.Colors.Gold
		goldBase.BackgroundColor3 = UI.Colors.Gold
		glow.BackgroundTransparency = 0.55
		textLabel.TextColor3 = Color3.fromRGB(255, 238, 148)
		VikingModels.SetHovered(vp, true)
	end)
	button.MouseLeave:Connect(function()
		UI.tween(scale, 0.12, { Scale = 1 })
		goldDome.BackgroundColor3 = UI.Colors.Stroke
		goldBase.BackgroundColor3 = UI.Colors.Stroke
		glow.BackgroundTransparency = 0.78
		textLabel.TextColor3 = UI.Colors.Gold
		VikingModels.SetHovered(vp, false)
	end)
	button.MouseButton1Down:Connect(function()
		UI.tween(scale, 0.06, { Scale = 0.95 })
	end)
	button.MouseButton1Up:Connect(function()
		UI.tween(scale, 0.1, { Scale = 1.03 })
	end)
	button.Activated:Connect(item.OnClick)
end

-- menu = { { Text, OnClick } }
function Hud.init(screenGui: ScreenGui, menu: { { Text: string, OnClick: () -> () } })
	screen = screenGui

	-- 1. Top-Center Ironbound Weathered-Oak Currency Plaque (hud.jpeg & shop.jpeg)
	local top = UI.new("Frame", {
		Name = "ResourcePlaque",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 2),
		Size = UDim2.fromOffset(426, 62),
		BackgroundColor3 = UI.Colors.IronOuter,
		ZIndex = 8,
		Parent = screen,
	})
	UI.ironWoodPlaque(top, 3, 9, 8, 1)
	UI.knotMedallion(top, UDim2.new(0, 22, 0.5, 0), Vector2.new(0.5, 0.5), 20, 10)
	UI.knotMedallion(top, UDim2.new(1, -22, 0.5, 0), Vector2.new(0.5, 0.5), 20, 10)

	-- Left Half: Stamped Bearded-Axe Viking Gold Coin + Coins & +Income/s
	local coinBadge = UI.icon(top, "Coins", 44, UI.Colors.Gold, 10, 0.35, true)
	coinBadge.AnchorPoint = Vector2.new(0, 0.5)
	coinBadge.Position = UDim2.new(0, 38, 0.5, 0)

	local coins = UI.label(top, "", 22, {
		Font = UI.FontDisplay,
		Position = UDim2.fromOffset(90, 9),
		Size = UDim2.fromOffset(122, 24),
		TextColor3 = UI.Colors.Gold,
		TextStrokeColor3 = UI.Colors.WoodDark,
		TextStrokeTransparency = 0.16,
		TextWrapped = false,
		ZIndex = 11,
	})
	local income = UI.label(top, "", 13, {
		Font = UI.FontBold,
		Position = UDim2.fromOffset(90, 33),
		Size = UDim2.fromOffset(122, 18),
		TextColor3 = UI.Colors.GoldSoft,
		TextStrokeColor3 = UI.Colors.WoodDark,
		TextStrokeTransparency = 0.35,
		TextWrapped = false,
		ZIndex = 11,
	})

	-- Forged iron center strap with twin rivets
	local sep = UI.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.52, 0.5),
		Size = UDim2.new(0, 4, 0, 40),
		BackgroundColor3 = UI.Colors.IronOuter,
		ZIndex = 10,
		Parent = top,
	})
	UI.corner(sep, 2)
	UI.roundRivet(sep, UDim2.new(0.5, 0, 0, 5), 4, 11)
	UI.roundRivet(sep, UDim2.new(0.5, 0, 1, -5), 4, 11)

	-- Right Half: Glowing Fehu Rune Crystal + Essence Count & Label
	local essenceBadge = UI.icon(top, "Essence", 44, Color3.fromRGB(196, 138, 255), 10, 0.45, true)
	essenceBadge.AnchorPoint = Vector2.new(0, 0.5)
	essenceBadge.Position = UDim2.new(0.52, 16, 0.5, 0)

	local essence = UI.label(top, "", 22, {
		Font = UI.FontDisplay,
		Position = UDim2.new(0.52, 68, 0, 9),
		Size = UDim2.new(0.48, -98, 0, 24),
		TextColor3 = UI.Colors.Gold,
		TextStrokeColor3 = UI.Colors.WoodDark,
		TextStrokeTransparency = 0.16,
		TextWrapped = false,
		ZIndex = 11,
	})
	UI.label(top, "Essence", 13, {
		Font = UI.FontBold,
		Position = UDim2.new(0.52, 68, 0, 33),
		Size = UDim2.new(0.48, -98, 0, 18),
		TextColor3 = UI.Colors.Text,
		TextStrokeColor3 = UI.Colors.WoodDark,
		TextStrokeTransparency = 0.38,
		TextWrapped = false,
		ZIndex = 11,
	})

	-- 2. Chained Weathered-Timber Goal Signboard (shown post-tutorial when no sheet is open)
	goalFrame = UI.new("Frame", {
		Name = "GoalBanner",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 78),
		Size = UDim2.new(0.92, 0, 0, 62),
		BackgroundColor3 = UI.Colors.IronOuter,
		Visible = false,
		ZIndex = 7,
		Parent = screen,
	})
	UI.new("UISizeConstraint", { MaxSize = Vector2.new(490, 64), Parent = goalFrame })
	UI.hangingChain(goalFrame, UDim2.fromScale(0.22, 0), -18, 22, 6)
	UI.hangingChain(goalFrame, UDim2.fromScale(0.78, 0), -18, 22, 6)
	UI.ironWoodPlaque(goalFrame, 3, 8, 8, 1)

	goalLabel = UI.label(goalFrame, "", 14, {
		Size = UDim2.new(1, -28, 1, -14),
		Position = UDim2.fromOffset(14, 7),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextStrokeColor3 = UI.Colors.WoodDark,
		TextStrokeTransparency = 0.35,
		ZIndex = 10,
		Parent = goalFrame,
	})

	toastHolder = UI.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 160),
		Size = UDim2.new(0.9, 0, 0, 200),
		BackgroundTransparency = 1,
		ZIndex = 30,
		Parent = screen,
	})
	UI.new("UISizeConstraint", { MaxSize = Vector2.new(440, 200), Parent = toastHolder })
	UI.list(toastHolder, 6)

	-- 3. Bottom 6-Arch Viking Longhouse Dock (hud.jpeg & shop.jpeg)
	local bar = UI.new("Frame", {
		Name = "VikingHubDock",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -2),
		Size = UDim2.new(0.96, 0, 0, 126),
		BackgroundTransparency = 1,
		ZIndex = 5,
		Parent = screen,
	})
	menuBar = bar
	UI.new("UISizeConstraint", { MaxSize = Vector2.new(if #menu > 5 then 756 else 630, 126), Parent = bar })

	-- Heavy carved longhouse timber & forged-iron backing beam along the lower 88px
	-- so the 6 iron arches crown proudly above the horizontal beam!
	local dockBeam = UI.new("Frame", {
		Name = "LonghouseBeam",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, 86),
		BackgroundColor3 = UI.Colors.IronOuter,
		ZIndex = 4,
		Parent = bar,
	})
	UI.ironWoodPlaque(dockBeam, 3, 9, 10, 2)

	-- Carved vertical rune divider posts between each of the 6 arches
	for i = 1, #menu - 1 do
		local post = UI.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(i / #menu, 0, 1, -8),
			Size = UDim2.fromOffset(10, 74),
			BackgroundTransparency = 1,
			ZIndex = 7,
			Parent = bar,
		})
		UI.label(post, ARCH_RUNES[((i - 1) % #ARCH_RUNES) + 1], 14, {
			Font = UI.FontBold,
			Size = UDim2.fromScale(1, 1),
			TextXAlignment = Enum.TextXAlignment.Center,
			TextColor3 = UI.Colors.Stroke,
			TextTransparency = 0.25,
			ZIndex = 8,
		})
	end

	local holder = UI.new("Frame", {
		Position = UDim2.fromOffset(10, 0),
		Size = UDim2.new(1, -20, 1, -6),
		BackgroundTransparency = 1,
		ZIndex = 6,
		Parent = bar,
	})
	local layout = UI.list(holder, 8, true)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Bottom

	for i, item in menu do
		buildArchDockButton(holder, i, #menu, item)
	end

	local function refreshCurrency()
		local state = Store.State
		coins.Text = "<b>" .. Format.Short(player:GetAttribute("Coins") or (state and state.Coins) or 0) .. "</b>"
		income.Text = "+" .. Format.Short(player:GetAttribute("Income") or 0) .. "/s"
		essence.Text = "<b>" .. Format.Short(state and state.Essence or 0) .. "</b>"
	end
	player:GetAttributeChangedSignal("Coins"):Connect(refreshCurrency)
	player:GetAttributeChangedSignal("Income"):Connect(refreshCurrency)
	UI.SheetChanged.Event:Connect(updateGoalVisibility)
	Store.Changed:Connect(function(state)
		refreshCurrency()
		currentGoalText = nextGoal(state)
		goalLabel.Text = currentGoalText or ""
		updateGoalVisibility()
	end)
	refreshCurrency()

	Store.Notice:Connect(function(kind, payload)
		if kind == "WelcomeBack" and type(payload) == "table" then
			welcomeBack(payload)
		elseif kind == "LevelUp" and type(payload) == "table" then
			Hud.Toast(string.format("%s reached level %d!%s", tostring(payload.Name), payload.Level or 0,
				if payload.SkillUnlocked then " New skill unlocked!" else ""), UI.Colors.Gold)
		end
	end)
end

return Hud
