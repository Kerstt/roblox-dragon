-- ReplicatedStorage/Client/TutorialGuide
-- Chained weathered-oak & forged-iron Saga signboard suspended beneath the top
-- currency plaque (matching hud.jpeg) + arched golden pulse on target dock button.

local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UI = require(script.Parent.UI)
local Store = require(script.Parent.Store)
local Hud = require(script.Parent.Hud)
local TutorialConfig = require(ReplicatedStorage.Shared.TutorialConfig)

local TutorialGuide = {}

local screen: ScreenGui
local panel: Frame
local titleLabel: TextLabel
local textLabel: TextLabel
local highlightFrame: Frame?
local highlightTween: Tween?
local shownStep = -1

local function clearHighlight()
	if highlightTween then
		highlightTween:Cancel()
		highlightTween = nil
	end
	if highlightFrame then
		highlightFrame:Destroy()
		highlightFrame = nil
	end
end

local function pulse(buttonName: string)
	clearHighlight()
	local button = screen:FindFirstChild("Menu" .. buttonName, true)
	if not button or not button:IsA("GuiObject") then
		return
	end
	local ring = UI.new("Frame", {
		Name = "TutorialHighlight",
		Position = UDim2.fromOffset(-2, -2),
		Size = UDim2.new(1, 4, 1, 4),
		BackgroundTransparency = 1,
		ZIndex = button.ZIndex + 8,
		Parent = button,
	})
	UI.new("UICorner", { CornerRadius = UDim.new(0.45, 0), Parent = ring })
	local stroke = UI.stroke(ring, Color3.fromRGB(255, 228, 108), 2.2)
	highlightFrame = ring
	highlightTween = TweenService:Create(stroke, TweenInfo.new(0.65, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Thickness = 5.2 })
	;(highlightTween :: Tween):Play()
end

local function refresh()
	local state = Store.State
	if not state or state.TutorialStep == nil then
		return
	end
	local step = state.TutorialStep
	local info = TutorialConfig.Get(step)
	local active = state.Starter ~= "" and step < TutorialConfig.Done and info ~= nil and not state.InBattle
	if not active then
		panel.Visible = false
		clearHighlight()
		shownStep = -1
		return
	end

	-- Yield space cleanly when a Great-Hall sheet is open (matching shop.jpeg!)
	panel.Visible = not UI.IsAnySheetOpen()

	if shownStep ~= step then
		shownStep = step
		titleLabel.Text = string.format(
			"<b>%s</b>  Saga %d/%d%s",
			info.Title,
			step + 1,
			#TutorialConfig.Steps,
			if info.Reward > 0 then string.format(" • +%d coins", info.Reward) else ""
		)
		textLabel.Text = info.Text
		if info.Highlight then
			pulse(info.Highlight)
		else
			clearHighlight()
		end
		if panel.Visible then
			panel.Position = UDim2.new(0.5, 0, 0, 64)
			UI.tween(panel, 0.25, { Position = UDim2.new(0.5, 0, 0, 78) }, Enum.EasingStyle.Back)
		end
	end
end

function TutorialGuide.init(screenGui: ScreenGui)
	screen = screenGui
	panel = UI.new("Frame", {
		Name = "TutorialPanel",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 78),
		Size = UDim2.new(0.92, 0, 0, 76),
		BackgroundColor3 = UI.Colors.IronOuter,
		Visible = false,
		ZIndex = 7,
		Parent = screen,
	})
	UI.new("UISizeConstraint", { MaxSize = Vector2.new(504, 78), Parent = panel })

	-- Twin hanging forged-iron chains connecting up into ResourcePlaque (hud.jpeg)
	UI.hangingChain(panel, UDim2.fromScale(0.22, 0), -18, 22, 6)
	UI.hangingChain(panel, UDim2.fromScale(0.78, 0), -18, 22, 6)
	UI.ironWoodPlaque(panel, 3, 8, 8, 2)

	titleLabel = UI.label(panel, "", 17, {
		Font = UI.FontDisplay,
		Position = UDim2.fromOffset(18, 9),
		Size = UDim2.new(1, -36, 0, 22),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = UI.Colors.Gold,
		TextStrokeColor3 = UI.Colors.WoodDark,
		TextStrokeTransparency = 0.18,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = 10,
	})
	textLabel = UI.label(panel, "", 13, {
		Position = UDim2.fromOffset(20, 32),
		Size = UDim2.new(1, -40, 0, 34),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = UI.Colors.Text,
		TextStrokeColor3 = UI.Colors.WoodDark,
		TextStrokeTransparency = 0.4,
		ZIndex = 10,
	})

	UI.SheetChanged.Event:Connect(refresh)
	Store.Changed:Connect(refresh)
	Store.Notice:Connect(function(kind, payload)
		if kind == "TutorialStep" and type(payload) == "table" then
			if payload.Finished then
				Hud.Toast(string.format("Saga complete! +%d coins. The sanctuary is yours, Jarl!", (payload.Reward or 0) + (payload.Bonus or 0)), UI.Colors.Gold)
			elseif (payload.Reward or 0) > 0 then
				Hud.Toast(string.format("Done: %s  +%d coins", tostring(payload.Title), payload.Reward), UI.Colors.Good)
			end
		end
	end)
	refresh()
end

return TutorialGuide
