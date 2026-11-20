-- ReplicatedStorage/Client/Hud
-- Top bar (coins, income, essence), the next-goal hint, toasts, the bottom
-- menu buttons, and the welcome-back popup.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UI = require(script.Parent.UI)
local Store = require(script.Parent.Store)
local Format = require(ReplicatedStorage.Shared.Format)
local EggCatalog = require(ReplicatedStorage.Shared.EggCatalog)

local Hud = {}

local player = Players.LocalPlayer
local screen: ScreenGui
local toastHolder: Frame
local goalLabel: TextLabel
local menuBar: Frame
local battleMode = false

function Hud.Toast(text: string, color: Color3?)
	local toast = UI.new("TextLabel", {
		Size = UDim2.new(1, 0, 0, 40),
		BackgroundColor3 = UI.Colors.Panel,
		BackgroundTransparency = 0.05,
		Font = UI.FontBold,
		TextSize = 16,
		TextColor3 = color or UI.Colors.Text,
		Text = text,
		TextWrapped = true,
		ZIndex = 30,
		Parent = toastHolder,
	})
	UI.corner(toast, 10)
	UI.stroke(toast, color or UI.Colors.Stroke, 1)
	task.delay(2.6, function()
		UI.tween(toast, 0.3, { BackgroundTransparency = 1, TextTransparency = 1 })
		task.wait(0.3)
		toast:Destroy()
	end)
end

function Hud.Error(code: string?)
	Hud.Toast(Store.ErrorText(code), UI.Colors.Bad)
end

-- Hides the bottom menu and goal hint during battles (the skill bar goes there).
function Hud.SetBattleMode(on: boolean)
	battleMode = on
	if menuBar then
		menuBar.Visible = not on
	end
	if goalLabel then
		goalLabel.Visible = not on and goalLabel.Text ~= ""
	end
	if on then
		UI.CloseAllSheets()
	end
end

-- The next thing a new player should do.
local function nextGoal(state: any): string?
	if state.Starter == "" or (state.TutorialStep and state.TutorialStep < 99) then
		return nil -- the tutorial panel is showing instead
	end
	if state.Hatches == 0 then
		return "Next: buy a Hatchling Egg (100 coins). Tap <b>Eggs</b>."
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
		return "Next: put a dragon to work. Tap <b>Dragons</b>, then Assign."
	end
	if state.IdleCount > 0 and state.NextSlotCost and state.SlotsBought < 3 then
		return "Next: unlock another station slot in <b>Stations</b>."
	end
	local grove = EggCatalog.Get("Grove")
	if grove and state.Coins < grove.Price and state.Hatches < 10 then
		return "Goal: save " .. Format.Commas(grove.Price) .. " coins for a Grove Egg (Storm & Ice dragons)."
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
		Size = UDim2.new(0.86, 0, 0, 210),
		BackgroundColor3 = UI.Colors.Panel,
		ZIndex = 41,
		Parent = dim,
	})
	UI.new("UISizeConstraint", { MaxSize = Vector2.new(380, 260), Parent = box })
	UI.corner(box, 16)
	UI.stroke(box, UI.Colors.Gold, 2)
	UI.padding(box, 16)
	UI.list(box, 10).HorizontalAlignment = Enum.HorizontalAlignment.Center
	UI.label(box, "<b>Welcome back!</b>", 22, { TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = UI.Colors.Gold, ZIndex = 42 })
	UI.label(box, "While you were away (" .. Format.Duration(payload.Seconds or 0) .. "), your dragons earned", 16, {
		TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.new(1, 0, 0, 40), ZIndex = 42,
	})
	UI.label(box, "<b>+" .. Format.Commas(payload.Coins or 0) .. " coins</b>", 26, {
		TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = UI.Colors.Gold, ZIndex = 42,
	})
	UI.button(box, "Collect", function()
		dim:Destroy()
	end, { Size = UDim2.new(0.6, 0, 0, 44), ZIndex = 42 })
end

-- menu = { { Text, OnClick } }
function Hud.init(screenGui: ScreenGui, menu: { { Text: string, OnClick: () -> () } })
	screen = screenGui

	-- Top bar (kept clear of Roblox's top-left/top-right buttons)
	local top = UI.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 8),
		Size = UDim2.fromOffset(300, 46),
		BackgroundColor3 = UI.Colors.Panel,
		BackgroundTransparency = 0.1,
		Parent = screen,
	})
	UI.corner(top, 23)
	UI.stroke(top)
	local coins = UI.label(top, "", 20, {
		Font = UI.FontBold,
		Position = UDim2.fromOffset(16, 0),
		Size = UDim2.new(0.5, -16, 1, 0),
		TextColor3 = UI.Colors.Gold,
		TextWrapped = false,
	})
	local income = UI.label(top, "", 14, {
		Position = UDim2.new(0.5, 0, 0, 3),
		Size = UDim2.new(0.5, -14, 0.5, 0),
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = UI.Colors.Good,
		TextWrapped = false,
	})
	local essence = UI.label(top, "", 14, {
		Position = UDim2.new(0.5, 0, 0.5, -2),
		Size = UDim2.new(0.5, -14, 0.5, 0),
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = Color3.fromRGB(190, 160, 255),
		TextWrapped = false,
	})

	goalLabel = UI.label(screen, "", 15, {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 60),
		Size = UDim2.new(0.9, 0, 0, 34),
		TextXAlignment = Enum.TextXAlignment.Center,
		BackgroundTransparency = 0.25,
		BackgroundColor3 = UI.Colors.Panel,
		Visible = false,
	})
	UI.new("UISizeConstraint", { MaxSize = Vector2.new(460, 60), Parent = goalLabel })
	UI.corner(goalLabel, 10)

	toastHolder = UI.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 100),
		Size = UDim2.new(0.9, 0, 0, 200),
		BackgroundTransparency = 1,
		ZIndex = 30,
		Parent = screen,
	})
	UI.new("UISizeConstraint", { MaxSize = Vector2.new(420, 200), Parent = toastHolder })
	UI.list(toastHolder, 6)

	-- Bottom menu (thumb zone)
	local bar = UI.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -12),
		Size = UDim2.new(0.96, 0, 0, 60),
		BackgroundTransparency = 1,
		Parent = screen,
	})
	menuBar = bar
	UI.new("UISizeConstraint", { MaxSize = Vector2.new(if #menu > 5 then 580 else 460, 60), Parent = bar })
	local layout = UI.list(bar, if #menu > 5 then 6 else 10, true)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	for i, item in menu do
		local button = UI.button(bar, item.Text, item.OnClick, {
			Name = "Menu" .. item.Text, -- the tutorial finds buttons by name
			Size = UDim2.new(1 / #menu, if #menu > 5 then -6 else -10, 1, 0),
			TextSize = if #menu > 4 then 15 else 18,
			LayoutOrder = i,
		})
		UI.stroke(button, UI.Colors.Stroke, 2)
	end

	local function refreshCurrency()
		local state = Store.State
		coins.Text = "◉ " .. Format.Short(player:GetAttribute("Coins") or (state and state.Coins) or 0)
		income.Text = "+" .. Format.Short(player:GetAttribute("Income") or 0) .. "/s"
		essence.Text = "◆ " .. Format.Short(state and state.Essence or 0) .. " essence"
	end
	player:GetAttributeChangedSignal("Coins"):Connect(refreshCurrency)
	player:GetAttributeChangedSignal("Income"):Connect(refreshCurrency)
	Store.Changed:Connect(function(state)
		refreshCurrency()
		local goal = nextGoal(state)
		goalLabel.Visible = goal ~= nil and not battleMode
		goalLabel.Text = goal or ""
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
