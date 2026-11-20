-- ReplicatedStorage/Client/DragonsSheet
-- Your dragons: who's working where, assign/rest/release, auto-release settings.
-- Open(station) starts in "assign to this station" mode.
-- Each dragon shows its level and XP; Train opens Feed (coins) and Infuse (essence).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared

local UI = require(script.Parent.UI)
local Store = require(script.Parent.Store)
local Hud = require(script.Parent.Hud)
local DragonCatalog = require(Shared.DragonCatalog)
local Elements = require(Shared.Elements)
local Rarities = require(Shared.Rarities)
local SanctuaryConfig = require(Shared.SanctuaryConfig)
local Format = require(Shared.Format)
local Leveling = require(Shared.Leveling)
local SkillCatalog = require(Shared.SkillCatalog)

local DragonsSheet = {}

local sheet: UI.Sheet
local assignTo: string? = nil -- station chosen from the Stations sheet
local rideMode = false -- "pick a dragon to ride"
local expanded: string? = nil -- dragon id whose station picker is open
local confirmRelease: string? = nil
local trainOpen: string? = nil -- dragon id whose Train panel is open
local busy = false

local function act(action: string, ...: any)
	if busy then
		return nil
	end
	busy = true
	local result = Store.Request(action, ...)
	busy = false
	if not result.ok then
		Hud.Error(result.error)
	end
	return result
end

local function freeSlots(state: any, station: string): number
	local used = 0
	for _, d in state.Dragons do
		if d.Station == station then
			used += 1
		end
	end
	return state.Stations[station].Slots - used
end

local function incomeAt(state: any, dragon: any, station: string): number
	return SanctuaryConfig.DragonIncome(dragon, station, state.Stations[station].Level)
end

local function sortedIds(state: any): { string }
	local ids = {}
	for id in state.Dragons do
		table.insert(ids, id)
	end
	table.sort(ids, function(a, b)
		local da, db = state.Dragons[a], state.Dragons[b]
		if assignTo then -- idle dragons that match the station first
			local ma = if not da.Station then incomeAt(state, da, assignTo) else -1
			local mb = if not db.Station then incomeAt(state, db, assignTo) else -1
			if ma ~= mb then
				return ma > mb
			end
		end
		if (da.Station ~= nil) ~= (db.Station ~= nil) then
			return da.Station ~= nil
		end
		local ra, rb = Rarities.Info[da.Rarity].Rank, Rarities.Info[db.Rarity].Rank
		if ra ~= rb then
			return ra > rb
		end
		if (da.Power or 1) ~= (db.Power or 1) then
			return (da.Power or 1) > (db.Power or 1)
		end
		return (tonumber(a:sub(2)) or 0) < (tonumber(b:sub(2)) or 0)
	end)
	return ids
end

local render: () -> ()

local function dragonRow(state: any, id: string, order: number)
	local d = state.Dragons[id]
	local species = DragonCatalog.Get(d.Species) :: any
	local rarity = Rarities.Info[d.Rarity]
	local element = Elements.Info[species.Element]

	local card = UI.card(sheet.Body, { LayoutOrder = order })
	UI.list(card, 6)
	local top = UI.row(card, 44)
	local bar = UI.new("Frame", { Size = UDim2.fromOffset(6, 40), BackgroundColor3 = rarity.Color, Parent = top })
	UI.corner(bar, 3)
	local info = UI.new("Frame", { Size = UDim2.new(1, -170, 1, 0), BackgroundTransparency = 1, Parent = top })
	UI.label(info, string.format("<font color=\"#%s\"><b>%s</b></font> <b>%s</b>  <font color=\"#%s\">Lv %d</font>", rarity.Color:ToHex(), d.Rarity, species.Name, UI.Colors.Gold:ToHex(), d.Level or 1), 16, {
		Size = UDim2.new(1, 0, 0, 20), TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd,
	})
	local where = if d.Station
		then string.format("Working at %s • %s/s", d.Station, Format.Short(incomeAt(state, d, d.Station)))
		else "Resting in the nest"
	UI.label(info, string.format("<font color=\"#%s\">%s</font> • x%s egg power • %s", element.Color:ToHex(), element.DisplayName, Format.Short(d.Power or 1), where), 13, {
		Position = UDim2.fromOffset(0, 22), Size = UDim2.new(1, 0, 0, 18), TextColor3 = UI.Colors.Muted, TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})

	local buttons = UI.new("Frame", { Size = UDim2.fromOffset(156, 40), BackgroundTransparency = 1, Parent = top })
	UI.list(buttons, 6, true).HorizontalAlignment = Enum.HorizontalAlignment.Right
	if rideMode then
		UI.button(buttons, "Ride", function()
			local r = act("Summon", id)
			if r and r.ok then
				sheet.Close()
				Hud.Toast("Climb on! " .. species.Name .. " is ready to fly.", UI.Colors.Good)
			end
		end, { Size = UDim2.fromOffset(150, 40) })
	elseif assignTo and not d.Station then
		local free = freeSlots(state, assignTo) > 0
		local _, setEnabled = UI.button(buttons, "Assign", function()
			local r = act("Assign", id, assignTo)
			if r and r.ok then
				Hud.Toast(species.Name .. " is working at the " .. assignTo .. "!", UI.Colors.Good)
				if freeSlots(Store.State, assignTo) <= 1 then
					assignTo = nil
				end
			end
		end, { Size = UDim2.fromOffset(150, 40) })
		setEnabled(free, if free then "Assign" else "No free slot")
	elseif d.Station then
		UI.button(buttons, "Rest", function()
			act("Assign", id, false)
		end, { Size = UDim2.fromOffset(72, 40), BackgroundColor3 = UI.Colors.Secondary, TextColor3 = UI.Colors.Text })
		UI.button(buttons, "Move", function()
			expanded = if expanded == id then nil else id
			render()
		end, { Size = UDim2.fromOffset(72, 40) })
	else
		local confirming = confirmRelease == id
		UI.button(buttons, if confirming then "+" .. rarity.Essence .. " ◆?" else "Release", function()
			if confirming then
				confirmRelease = nil
				local r = act("Release", { id })
				if r and r.ok then
					Hud.Toast("Released for +" .. r.essence .. " essence", Color3.fromRGB(190, 160, 255))
				end
			else
				confirmRelease = id
				render()
				task.delay(3, function()
					if confirmRelease == id then
						confirmRelease = nil
						render()
					end
				end)
			end
		end, {
			Size = UDim2.fromOffset(72, 40),
			BackgroundColor3 = if confirming then UI.Colors.Bad else UI.Colors.Secondary,
			TextColor3 = UI.Colors.Text,
			TextSize = 14,
		})
		UI.button(buttons, "Assign", function()
			expanded = if expanded == id then nil else id
			render()
		end, { Size = UDim2.fromOffset(72, 40) })
	end

	-- Level and XP, with the Train toggle
	local level = d.Level or 1
	local need = Leveling.XPToNext(level)
	local xpRow = UI.new("Frame", { Size = UDim2.new(1, 0, 0, 24), BackgroundTransparency = 1, Parent = card })
	local back = UI.new("Frame", { Position = UDim2.new(0, 12, 0.5, -4), Size = UDim2.new(1, -200, 0, 8), BackgroundColor3 = UI.Colors.Panel, Parent = xpRow })
	UI.corner(back, 4)
	local fill = UI.new("Frame", { Size = UDim2.fromScale(if need then math.clamp((d.XP or 0) / need, 0, 1) else 1, 1), BackgroundColor3 = UI.Colors.Gold, Parent = back })
	UI.corner(fill, 4)
	UI.label(xpRow, if need then string.format("%s/%s XP", Format.Short(d.XP or 0), Format.Short(need)) else "Max level", 12, {
		AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -78, 0, 2), Size = UDim2.fromOffset(110, 20), TextWrapped = false,
		TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = UI.Colors.Muted,
	})
	if not rideMode and not assignTo then
		UI.button(xpRow, if trainOpen == id then "Close" else "Train", function()
			trainOpen = if trainOpen == id then nil else id
			render()
		end, {
			AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0), Size = UDim2.fromOffset(70, 24), TextSize = 13,
			BackgroundColor3 = UI.Colors.Secondary, TextColor3 = UI.Colors.Text,
		})
	end

	if trainOpen == id then
		local panel = UI.new("Frame", { Size = UDim2.new(1, 0, 0, 44), BackgroundTransparency = 1, Parent = card })
		UI.new("UIGridLayout", { CellSize = UDim2.new(0.5, -4, 0, 44), CellPadding = UDim2.fromOffset(8, 0), Parent = panel })
		local feedCost = Leveling.FeedCost(level)
		local _, setFeed = UI.button(panel, if feedCost then string.format("Feed  ◉ %s\n+%s XP", Format.Short(feedCost), Format.Short(Leveling.FeedXP(level))) else "Max level", function()
			local r = act("Feed", id)
			if r and r.ok and r.levels == 0 then
				Hud.Toast(string.format("%s gobbled it up! +%s XP", species.Name, Format.Short(r.xp)), UI.Colors.Good)
			end
		end, { TextSize = 13 })
		setFeed(feedCost ~= nil and state.Coins >= feedCost)
		local infuseCost = Leveling.InfuseCost(d)
		local _, setInfuse = UI.button(panel, if infuseCost then string.format("Infuse  ◆ %s\nfinish this level", Format.Short(infuseCost)) else "Max level", function()
			act("Infuse", id)
		end, { TextSize = 13, BackgroundColor3 = Color3.fromRGB(150, 120, 220) })
		setInfuse(infuseCost ~= nil and state.Essence >= infuseCost)
		local unlocked = Leveling.SkillsUnlocked(level)
		local skills = SkillCatalog.ForSpecies(d.Species) or {}
		local nextText = if unlocked < 4 and skills[unlocked + 1]
			then string.format("Next skill at level %d: <b>%s</b>", Leveling.SkillUnlockLevels[unlocked + 1], (SkillCatalog.Get(skills[unlocked + 1]) :: any).Name)
			else "All 4 skills unlocked."
		UI.label(card, nextText .. "  Working dragons also gain XP over time.", 12, { Size = UDim2.new(1, 0, 0, 30), TextColor3 = UI.Colors.Muted })
	end

	-- Station picker with the income each choice would give
	if expanded == id then
		local picker = UI.new("Frame", { Size = UDim2.new(1, 0, 0, 52), BackgroundTransparency = 1, Parent = card })
		UI.new("UIGridLayout", { CellSize = UDim2.new(0.25, -6, 0, 52), CellPadding = UDim2.fromOffset(6, 0), Parent = picker })
		for _, station in SanctuaryConfig.Stations do
			local open = state.Stations[station].Slots > 0
			local free = freeSlots(state, station) > 0 or d.Station == station
			local match = Elements.GetStationMultiplier(station, species.Element) > 1
			local label = station .. "\n" .. (if not open then "Locked" elseif not free then "Full" else Format.Short(incomeAt(state, d, station)) .. "/s" .. (if match then " +25%" else ""))
			local _, setEnabled = UI.button(picker, label, function()
				expanded = nil
				local r = act("Assign", id, station)
				if r and r.ok then
					Hud.Toast(species.Name .. " is working at the " .. station .. "!", UI.Colors.Good)
				end
			end, { TextSize = 13, BackgroundColor3 = if match then UI.Colors.Button else UI.Colors.Secondary, TextColor3 = if match then UI.Colors.ButtonText else UI.Colors.Text })
			setEnabled(open and free and d.Station ~= station)
		end
	end
end

render = function()
	local state = Store.State
	if not sheet or not sheet.IsOpen() or not state then
		return
	end
	local body = sheet.Body
	local scroll = body.CanvasPosition
	UI.clear(body)

	local total = 0
	for _ in state.Dragons do
		total += 1
	end
	sheet.Title.Text = if rideMode then "<b>Choose a dragon to ride</b>" elseif assignTo then "<b>Assign to the " .. assignTo .. "</b>" else "<b>Dragons</b>"
	UI.label(body, string.format("%d dragons • Nest %d/%d • ◆ %s essence", total, state.IdleCount, state.NestCapacity, Format.Short(state.Essence)), 14, {
		LayoutOrder = 1, TextColor3 = UI.Colors.Muted,
	})
	if rideMode then
		UI.label(body, "Riding doesn't stop a dragon's station work.", 13, { LayoutOrder = 2, TextColor3 = UI.Colors.Muted })
	elseif assignTo then
		UI.button(body, "Show all dragons", function()
			assignTo = nil
			render()
		end, { LayoutOrder = 2, Size = UDim2.new(1, 0, 0, 36), BackgroundColor3 = UI.Colors.Secondary, TextColor3 = UI.Colors.Text })
	else
		-- Auto-release and bulk release
		local settings = UI.row(body, 36, 6)
		settings.LayoutOrder = 2
		UI.label(settings, "Auto-release:", 13, { Size = UDim2.fromOffset(92, 36), TextWrapped = false, TextColor3 = UI.Colors.Muted })
		for _, rarityId in { "Common", "Uncommon", "Rare" } do
			local on = state.AutoRelease[rarityId] == true
			local button = UI.button(settings, rarityId .. (if on then " ON" else ""), function()
				act("SetAutoRelease", rarityId, not on)
			end, {
				Size = UDim2.new(0.33, -40, 0, 34),
				TextSize = 13,
				BackgroundColor3 = if on then Rarities.Info[rarityId].Color else UI.Colors.Secondary,
				TextColor3 = if on then UI.Colors.ButtonText else UI.Colors.Text,
			})
			_ = button
		end
		local idleCommons = {}
		for id, d in state.Dragons do
			if not d.Station and d.Rarity == "Common" and #idleCommons < 100 then
				table.insert(idleCommons, id)
			end
		end
		if #idleCommons > 0 then
			UI.button(body, string.format("Release %d resting Common%s (+%d ◆)", #idleCommons, if #idleCommons == 1 then "" else "s", #idleCommons * Rarities.Info.Common.Essence), function()
				local r = act("Release", idleCommons)
				if r and r.ok then
					Hud.Toast("Released " .. r.released .. " for +" .. r.essence .. " essence", Color3.fromRGB(190, 160, 255))
				end
			end, { LayoutOrder = 3, Size = UDim2.new(1, 0, 0, 36), BackgroundColor3 = UI.Colors.Secondary, TextColor3 = UI.Colors.Text, TextSize = 14 })
		end
	end

	for i, id in sortedIds(state) do
		dragonRow(state, id, 10 + i)
	end
	if total == 0 then
		UI.label(body, "No dragons yet. Hatch an egg!", 16, { LayoutOrder = 10, TextColor3 = UI.Colors.Muted })
	end
	task.defer(function()
		body.CanvasPosition = scroll
	end)
end

function DragonsSheet.init(screen: ScreenGui)
	sheet = UI.sheet(screen, "Dragons")
	sheet.OnOpen.Event:Connect(render)
	Store.Changed:Connect(render)
end

-- station: open in "assign to this station" mode (optional).
function DragonsSheet.Open(station: string?, mode: string?)
	assignTo = station
	rideMode = mode == "ride"
	expanded = nil
	confirmRelease = nil
	trainOpen = nil
	sheet.Open()
end

return DragonsSheet
