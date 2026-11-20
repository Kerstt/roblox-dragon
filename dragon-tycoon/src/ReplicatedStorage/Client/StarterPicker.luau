-- ReplicatedStorage/Client/StarterPicker
-- First-time screen: pick 1 of 3 starter dragons. It's a fixed choice, not a
-- random roll. Shown while the save has no starter.

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
		BackgroundTransparency = 0.35,
		Text = "",
		AutoButtonColor = false,
		ZIndex = 45,
		Parent = screen,
	})
	local box = UI.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(0.94, 0, 0.8, 0),
		BackgroundColor3 = UI.Colors.Panel,
		ZIndex = 46,
		Parent = dim,
	})
	UI.new("UISizeConstraint", { MaxSize = Vector2.new(620, 520), Parent = box })
	UI.corner(box, 18)
	UI.stroke(box, UI.Colors.Gold, 2)
	UI.padding(box, 16)
	UI.list(box, 10)
	UI.label(box, "<b>Choose your first dragon</b>", 24, { TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = UI.Colors.Gold, ZIndex = 47 })
	UI.label(box, "Pick one to start your sanctuary. This is your choice, not a random roll. It gets its own station right away.", 14, {
		TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = UI.Colors.Muted, Size = UDim2.new(1, 0, 0, 40), ZIndex = 47,
	})

	local cards = UI.new("Frame", { Size = UDim2.new(1, 0, 1, -110), BackgroundTransparency = 1, ZIndex = 47, Parent = box })
	UI.new("UIGridLayout", {
		CellSize = UDim2.new(1 / 3, -8, 1, 0),
		CellPadding = UDim2.fromOffset(8, 8),
		Parent = cards,
	})
	for _, starter in EggCatalog.Starters do
		local species = DragonCatalog.Get(starter.Species) :: any
		local element = Elements.Info[species.Element]
		local station = Elements.GetPreferredStation(species.Element)
		local card = UI.new("Frame", { BackgroundColor3 = UI.Colors.Panel2, ZIndex = 47, Parent = cards })
		UI.corner(card, 14)
		UI.stroke(card, element.Color, 2)
		UI.padding(card, 8)
		UI.list(card, 6).HorizontalAlignment = Enum.HorizontalAlignment.Center
		-- The real 3D dragon, slowly turning
		local stage = UI.new("Frame", { Size = UDim2.new(1, 0, 0, 110), BackgroundColor3 = UI.Colors.Panel, ZIndex = 48, Parent = card })
		UI.corner(stage, 10)
		UI.stroke(stage, element.Color, 1)
		if not Preview.Dragon(stage, species.Id, { ZIndex = 49 }, 0.4) then
			stage.BackgroundColor3 = element.Color
		end
		local center = { TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 48 }
		local nameProps = table.clone(center)
		nameProps.Font = UI.FontBold
		UI.label(card, species.Name, 18, nameProps)
		local elementProps = table.clone(center)
		elementProps.TextColor3 = element.Color
		UI.label(card, element.DisplayName .. " • works best at the " .. (station or "?"), 13, elementProps).Size = UDim2.new(1, 0, 0, 34)
		local hookProps = table.clone(center)
		hookProps.TextColor3 = UI.Colors.Muted
		hookProps.Size = UDim2.new(1, 0, 0, 52)
		UI.label(card, species.Hook, 12, hookProps)
		UI.button(card, "Choose", function()
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
		end, { Size = UDim2.new(1, 0, 0, 44), ZIndex = 48 })
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
