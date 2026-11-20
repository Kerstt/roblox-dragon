-- ReplicatedStorage/Client/HatchReveal
-- Plays the hatch animation for a result the SERVER already decided.
-- Full reveal ~4s (wobble, crack glow in rarity color, reveal card); tap to skip
-- after 0.5s. Quick mode is a 1.2s card. Legendary and Mythic always get the
-- full reveal (still skippable).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared

local UI = require(script.Parent.UI)
local Preview = require(script.Parent.Preview)
local DragonCatalog = require(Shared.DragonCatalog)
local EggCatalog = require(Shared.EggCatalog)
local Elements = require(Shared.Elements)
local Rarities = require(Shared.Rarities)
local SanctuaryConfig = require(Shared.SanctuaryConfig)

local HatchReveal = {}

local screen: ScreenGui

function HatchReveal.init(screenGui: ScreenGui)
	screen = screenGui
end

local function waitForTapOrTime(button: GuiButton, seconds: number, minSeconds: number)
	local tapped = false
	local start = os.clock()
	local connection = button.Activated:Connect(function()
		if os.clock() - start >= minSeconds then
			tapped = true
		end
	end)
	while not tapped and os.clock() - start < seconds do
		task.wait()
	end
	connection:Disconnect()
	return tapped
end

local function showCard(dim: GuiButton, title: string, speciesId: string, rarityId: string, footer: string)
	local species = DragonCatalog.Get(speciesId)
	local rarity = Rarities.Info[rarityId]
	local element = species and Elements.Info[species.Element]
	local card = UI.new("Frame", {
		Name = "Card",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(0.8, 0, 0, 260),
		BackgroundColor3 = UI.Colors.Panel,
		ZIndex = 52,
		Parent = dim,
	})
	UI.new("UISizeConstraint", { MaxSize = Vector2.new(380, 340), Parent = card })
	UI.corner(card, 18)
	UI.stroke(card, rarity.Color, 3)
	UI.padding(card, 16)
	UI.list(card, 6).HorizontalAlignment = Enum.HorizontalAlignment.Center
	local center = { TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 53 }
	UI.label(card, title, 14, table.clone(center)).TextColor3 = UI.Colors.Muted
	-- The real 3D dragon on a stage tinted by its element
	local emblem = UI.new("Frame", {
		Size = UDim2.new(1, 0, 0, 120),
		BackgroundColor3 = (element and element.Color or UI.Colors.Panel3):Lerp(Color3.new(0, 0, 0), 0.75),
		ZIndex = 53,
		Parent = card,
	})
	UI.corner(emblem, 12)
	UI.stroke(emblem, rarity.Color, 2)
	if not Preview.Dragon(emblem, speciesId, { ZIndex = 54 }, 0.6) then
		UI.label(emblem, element and element.DisplayName or "?", 14, {
			Size = UDim2.fromScale(1, 1),
			TextXAlignment = Enum.TextXAlignment.Center,
			Font = UI.FontBold,
			ZIndex = 54,
		})
	end
	local nameProps = table.clone(center)
	nameProps.Font = UI.FontBold
	UI.label(card, species and species.Name or speciesId, 26, nameProps)
	local rarityProps = table.clone(center)
	rarityProps.TextColor3 = rarity.Color
	rarityProps.Font = UI.FontBold
	UI.label(card, rarityId:upper(), 18, rarityProps)
	local footerProps = table.clone(center)
	footerProps.Size = UDim2.new(1, 0, 0, 40)
	footerProps.TextColor3 = UI.Colors.Muted
	UI.label(card, footer, 14, footerProps)
	card.Size = UDim2.new(0.6, 0, 0, 240)
	UI.tween(card, 0.2, { Size = UDim2.new(0.8, 0, 0, 300) }, Enum.EasingStyle.Back)
	return card
end

local function describe(result: any): string
	if result.Released then
		return "Auto-released for +" .. result.Essence .. " essence"
	end
	local species = DragonCatalog.Get(result.Species)
	local egg = EggCatalog.Get(result.Egg)
	local station = species and Elements.GetPreferredStation(species.Element) or "?"
	local income = SanctuaryConfig.DragonIncome({ Species = result.Species, Rarity = result.Rarity, Level = 1, Power = egg and egg.Power or 1 }, station, 0)
	return string.format("Earns %s/s at the %s (+25%% match)\nTap to continue", tostring(math.floor(income * 100) / 100), station)
end

-- Yields until the reveal is finished.
function HatchReveal.Play(result: any, quick: boolean)
	local rarity = Rarities.Info[result.Rarity]
	local egg = EggCatalog.Get(result.Egg)
	local full = not quick or rarity.Rank >= 5

	local dim = UI.new("TextButton", {
		Name = "HatchReveal",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.35,
		Text = "",
		AutoButtonColor = false,
		ZIndex = 50,
		Parent = screen,
	})

	if full then
		-- Glow behind the egg that grows in the rarity color as it cracks
		local glow = UI.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(150, 150),
			BackgroundColor3 = rarity.Color,
			BackgroundTransparency = 1,
			ZIndex = 51,
			Parent = dim,
		})
		UI.new("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = glow })
		local eggFrame = UI.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(200, 240),
			BackgroundTransparency = 1,
			ZIndex = 52,
			Parent = dim,
		})
		local eggView = Preview.Egg(eggFrame, result.Egg, { ZIndex = 52 }, 0, 0.75)
		if not eggView then
			eggFrame.BackgroundTransparency = 0
			eggFrame.BackgroundColor3 = egg and egg.Color or UI.Colors.Panel3
			eggFrame.Size = UDim2.fromOffset(130, 170)
			UI.new("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = eggFrame })
		end
		local crack = UI.stroke(glow, rarity.Color, 0)
		local skipped = false
		local start = os.clock()
		local connection = dim.Activated:Connect(function()
			if os.clock() - start > 0.5 then
				skipped = true
			end
		end)
		-- Wobble (1s)
		for i = 1, 6 do
			if skipped then
				break
			end
			local tilt = if i % 2 == 0 then -12 else 12
			if eggView then
				Preview.SetRoll(eggView, math.rad(tilt))
			else
				UI.tween(eggFrame, 0.08, { Rotation = tilt })
			end
			task.wait(0.16)
		end
		eggFrame.Rotation = 0
		if eggView then
			Preview.SetRoll(eggView, 0)
		end
		-- Cracks glow in the rarity color (1s)
		if not skipped then
			UI.tween(crack, 0.9, { Thickness = 10 })
			UI.tween(glow, 0.9, { BackgroundTransparency = 0.55, Size = UDim2.fromOffset(230, 230) }, Enum.EasingStyle.Sine)
			local t = os.clock()
			while not skipped and os.clock() - t < 1 do
				task.wait()
			end
		end
		connection:Disconnect()
		-- Burst
		local flash = UI.new("Frame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = rarity.Color,
			BackgroundTransparency = 0.2,
			ZIndex = 55,
			Parent = dim,
		})
		eggFrame:Destroy()
		glow:Destroy()
		UI.tween(flash, 0.35, { BackgroundTransparency = 1 })
		task.delay(0.4, function()
			flash:Destroy()
		end)
	end

	local card = showCard(dim, "You hatched", result.Species, result.Rarity, describe(result))
	if full then
		waitForTapOrTime(dim, 4, 0.5)
	else
		waitForTapOrTime(dim, 1.2, 0.2)
	end
	card:Destroy()

	if result.Bonus then
		showCard(dim, "Tutorial reward! A friend joined your sanctuary", result.Bonus.Species, result.Bonus.Rarity, "This one is a fixed gift, not a roll.\nTap to continue")
		waitForTapOrTime(dim, 6, 0.5)
	end
	dim:Destroy()
end

return HatchReveal
