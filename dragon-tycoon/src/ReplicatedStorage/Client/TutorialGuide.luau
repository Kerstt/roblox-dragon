-- ReplicatedStorage/Client/TutorialGuide
-- Shows the current tutorial step at the top of the screen and makes the
-- bottom-menu button to press pulse gold. The server decides when a step is
-- done (TutorialService) and pays the reward.

local Players = game:GetService("Players")
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
local highlight: UIStroke?
local highlightTween: Tween?
local shownStep = -1

local function clearHighlight()
	if highlightTween then
		highlightTween:Cancel()
		highlightTween = nil
	end
	if highlight then
		highlight:Destroy()
		highlight = nil
	end
end

local function pulse(buttonName: string)
	clearHighlight()
	local button = screen:FindFirstChild("Menu" .. buttonName, true)
	if not button then
		return
	end
	local stroke = Instance.new("UIStroke")
	stroke.Name = "TutorialHighlight"
	stroke.Color = Color3.fromRGB(255, 230, 120)
	stroke.Thickness = 2
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = button
	highlight = stroke
	highlightTween = TweenService:Create(stroke, TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Thickness = 6 })
	;(highlightTween :: Tween):Play()
end

local function refresh()
	local state = Store.State
	if not state or state.TutorialStep == nil then
		return
	end
	local step = state.TutorialStep
	local info = TutorialConfig.Get(step)
	local active = step < TutorialConfig.Done and info ~= nil and not state.InBattle
	panel.Visible = active
	if not active then
		clearHighlight()
		shownStep = -1
		return
	end
	if shownStep ~= step then
		shownStep = step
		titleLabel.Text = string.format("<b>%s</b>  <font color=\"#%s\">Step %d of %d%s</font>", info.Title, UI.Colors.Muted:ToHex(), step + 1,
			#TutorialConfig.Steps, if info.Reward > 0 then string.format("  •  reward: %d coins", info.Reward) else "")
		textLabel.Text = info.Text
		if info.Highlight then
			pulse(info.Highlight)
		else
			clearHighlight()
		end
		panel.Position = UDim2.new(0.5, 0, 0, 40)
		UI.tween(panel, 0.25, { Position = UDim2.new(0.5, 0, 0, 60) })
	end
end

function TutorialGuide.init(screenGui: ScreenGui)
	screen = screenGui
	panel = UI.new("Frame", {
		Name = "TutorialPanel",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 60),
		Size = UDim2.new(0.92, 0, 0, 66),
		BackgroundColor3 = UI.Colors.Panel,
		BackgroundTransparency = 0.05,
		Visible = false,
		ZIndex = 8,
		Parent = screen,
	})
	UI.new("UISizeConstraint", { MaxSize = Vector2.new(480, 66), Parent = panel })
	UI.corner(panel, 12)
	UI.stroke(panel, UI.Colors.Gold, 1.5)
	titleLabel = UI.label(panel, "", 15, { Position = UDim2.fromOffset(12, 6), Size = UDim2.new(1, -24, 0, 20), TextColor3 = UI.Colors.Gold, TextWrapped = false, ZIndex = 9 })
	textLabel = UI.label(panel, "", 13, { Position = UDim2.fromOffset(12, 27), Size = UDim2.new(1, -24, 0, 36), ZIndex = 9 })

	Store.Changed:Connect(refresh)
	Store.Notice:Connect(function(kind, payload)
		if kind == "TutorialStep" and type(payload) == "table" then
			if payload.Finished then
				Hud.Toast(string.format("Tutorial complete! +%d coins. The sanctuary is yours, keeper!", (payload.Reward or 0) + (payload.Bonus or 0)), UI.Colors.Gold)
			elseif (payload.Reward or 0) > 0 then
				Hud.Toast(string.format("Done: %s  +%d coins", tostring(payload.Title), payload.Reward), UI.Colors.Good)
			end
		end
	end)
	refresh()
end

return TutorialGuide
