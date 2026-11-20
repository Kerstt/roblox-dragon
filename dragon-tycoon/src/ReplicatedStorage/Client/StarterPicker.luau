-- ReplicatedStorage/Client/StarterPicker
-- First-time Viking ceremony: pick 1 of 3 starter dragons (fixed choice, never random).
-- Uses inner Content containers so decorative Viking framing never collides with UIListLayout.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared

local UI = require(script.Parent.UI)
local Store = require(script.Parent.Store)
local Hud = require(script.Parent.Hud)
local Preview = require(script.Parent.Preview)
local DragonCatalog = require(Shared.DragonCatalog)
local EggCatalog = require(Shared.EggCatalog)
local Elements = require(Shared.Elements)

local StarterPicker = {}

local overlay: TextButton? = nil
local choosing = false

local function build(screen: ScreenGui)
	local dim = UI.new("TextButton", {
		Name = "StarterPicker",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.5,
		Text = "",
		AutoButtonColor = false,
		ZIndex = 45,
		Parent = screen,
	})
	local box = UI.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(0.94, 0, 0.82, 0),
		BackgroundColor3 = UI.Colors.Panel,
		ZIndex = 46,
		Parent = dim,
	})
	UI.new("UISizeConstraint", { MaxSize = Vector2.new(660, 520), Parent = box })
	UI.vikingPanel(box, UI.Colors.Gold, 18, 7)

	-- Weathered oak timber banner header inside the forged-iron modal
	local header = UI.new("Frame", {
		Position = UDim2.fromOffset(10, 10),
		Size = UDim2.new(1, -20, 0, 80),
		BackgroundColor3 = UI.Colors.Panel,
		ZIndex = 47,
		Parent = box,
	})
	UI.woodPlanks(header, 3, 47, 6)
	UI.stroke(header, UI.Colors.Stroke, 1.6)

	UI.label(header, "<b>Choose Your First Wyrm</b>", 24, {
		Font = UI.FontDisplay,
		Position = UDim2.fromOffset(12, 8),
		Size = UDim2.new(1, -24, 0, 30),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = UI.Colors.Gold,
		TextStrokeColor3 = UI.Colors.WoodDark,
		TextStrokeTransparency = 0.2,
		ZIndex = 49,
	})
	UI.label(header, "Swear your sanctuary oath to one dragon—a fixed choice, not a random roll. It starts working right away.", 13, {
		Position = UDim2.fromOffset(16, 40),
		Size = UDim2.new(1, -32, 0, 36),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = UI.Colors.Text,
		ZIndex = 49,
	})

	local cards = UI.new("Frame", {
		Position = UDim2.fromOffset(14, 98),
		Size = UDim2.new(1, -28, 1, -112),
		BackgroundTransparency = 1,
		ZIndex = 47,
		Parent = box,
	})
	UI.new("UIGridLayout", {
		CellSize = UDim2.new(1 / 3, -8, 1, 0),
		CellPadding = UDim2.fromOffset(10, 8),
		Parent = cards,
	})

	for _, starter in EggCatalog.Starters do
		local species = DragonCatalog.Get(starter.Species) :: any
		local element = Elements.Info[species.Element]
		local station = Elements.GetPreferredStation(species.Element)

		-- Outer Viking oak/element frame (no UIListLayout directly on card!)
		local card = UI.new("Frame", { BackgroundColor3 = UI.Colors.Panel3, ZIndex = 47, Parent = cards })
		UI.vikingPanel(card, element.Color, 14, 5)

		-- Clean inner Content container for layout
		local content = UI.new("Frame", {
			Position = UDim2.fromOffset(10, 10),
			Size = UDim2.new(1, -20, 1, -20),
			BackgroundTransparency = 1,
			ZIndex = 48,
			Parent = card,
		})
		UI.list(content, 6).HorizontalAlignment = Enum.HorizontalAlignment.Center

		local stage = UI.new("Frame", {
			Size = UDim2.new(1, 0, 0, 128),
			BackgroundColor3 = element.Color:Lerp(UI.Colors.WoodDark, 0.72),
			ZIndex = 49,
			Parent = content,
		})
		UI.corner(stage, 10)
		UI.stroke(stage, element.Color, 1.8)
		if not Preview.Dragon(stage, species.Id, { ZIndex = 50 }, 0.5) then
			stage.BackgroundColor3 = element.Color
		end

		UI.label(content, "<b>" .. species.Name .. "</b>", 19, {
			Font = UI.FontDisplay,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextColor3 = UI.Colors.Gold,
			ZIndex = 49,
		})

		local pill = UI.new("Frame", {
			Size = UDim2.new(0.92, 0, 0, 24),
			BackgroundColor3 = element.Color:Lerp(UI.Colors.WoodDark, 0.75),
			ZIndex = 49,
			Parent = content,
		})
		UI.corner(pill, 6)
		UI.stroke(pill, element.Color, 1)
		UI.label(pill, string.format("<b>%s</b> • %s", element.DisplayName, station or "?"), 12, {
			Size = UDim2.fromScale(1, 1),
			TextXAlignment = Enum.TextXAlignment.Center,
			TextColor3 = element.Color,
			TextWrapped = false,
			ZIndex = 50,
		})

		UI.label(content, species.Hook, 12, {
			Size = UDim2.new(1, 0, 1, -264),
			TextXAlignment = Enum.TextXAlignment.Center,
			TextColor3 = UI.Colors.Muted,
			ZIndex = 49,
		})

		UI.button(content, "Choose " .. species.Name, function()
			if choosing then
				return
			end
			choosing = true
			local result = Store.Request("ChooseStarter", species.Id)
			choosing = false
			if result.ok then
				Hud.Toast(species.Name .. " joined your sanctuary and is working at the " .. (station or "?") .. "!", UI.Colors.Good)
			else
				Hud.Error(result.error)
			end
		end, { Size = UDim2.new(1, 0, 0, 44), TextSize = 14, ZIndex = 50 })
	end
	return dim
end

function StarterPicker.init(screen: ScreenGui)
	Store.Changed:Connect(function(state)
		local needed = state.Starter == ""
		if needed and not overlay then
			UI.CloseAllSheets()
			overlay = build(screen)
		elseif not needed and overlay then
			overlay:Destroy()
			overlay = nil
		end
	end)
end

return StarterPicker
