-- ReplicatedStorage/Client/StationsSheet
-- Viking Sanctuary Guilds: Mine, Farm, Forge, and Watchtower.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared

local UI = require(script.Parent.UI)
local Store = require(script.Parent.Store)
local Hud = require(script.Parent.Hud)
local DragonsSheet = require(script.Parent.DragonsSheet)
local Elements = require(Shared.Elements)
local SanctuaryConfig = require(Shared.SanctuaryConfig)
local Format = require(Shared.Format)

local StationsSheet = {}

local STATION_INFO = {
	Mine = "Cut into the cliff. Earth and Ice dragons dig deepest.",
	Farm = "Terraced fields. Nature and Water dragons grow the most.",
	Forge = "Lava vents and anvils. Fire and Storm dragons work hottest.",
	Watchtower = "The spire. Rare Light and Shadow dragons keep watch.",
}

local player = Players.LocalPlayer
local sheet: UI.Sheet
local focus: string? = nil
local busy = false

local function coins(): number
	return player:GetAttribute("Coins") or (Store.State and Store.State.Coins) or 0
end

local function act(action: string, station: string, successText: string)
	if busy then
		return
	end
	busy = true
	local result = Store.Request(action, station)
	busy = false
	if result.ok then
		Hud.Toast(successText, UI.Colors.Good)
	else
		Hud.Error(result.error)
	end
end

local function render()
	local state = Store.State
	if not sheet or not sheet.IsOpen() or not state then
		return
	end
	UI.clear(sheet.Body)
	local nextCost = state.NextSlotCost
	local summary = UI.card(sheet.Body, { LayoutOrder = 0 })
	UI.label(summary, string.format("<b>Slots Unlocked:</b> %d/%d  •  <b>Next Slot:</b> %s", state.SlotsBought, #SanctuaryConfig.SlotCosts,
		if nextCost then "<font color=\"#" .. UI.Colors.Gold:ToHex() .. "\">◉ " .. Format.Short(nextCost) .. "</font>" else "All unlocked"), 14, {
		Size = UDim2.new(1, 0, 0, 20), TextColor3 = UI.Colors.Text,
	})

	for i, station in SanctuaryConfig.Stations do
		local info = state.Stations[station]
		local used, income = 0, 0
		for _, d in state.Dragons do
			if d.Station == station then
				used += 1
				income += SanctuaryConfig.DragonIncome(d, station, info.Level)
			end
		end

		local order = if station == focus then 1 elseif info.Slots > 0 then 10 + i else 20 + i
		local card = UI.card(sheet.Body, { LayoutOrder = order })
		if station == focus then
			UI.stroke(card, UI.Colors.Gold, 2)
		elseif info.Slots > 0 then
			UI.stroke(card, UI.Colors.Stroke, 1.2)
		end
		UI.list(card, 6)
		local prefers = {}
		for _, el in Elements.StationAffinity[station] do
			table.insert(prefers, string.format("<font color=\"#%s\"><b>%s</b></font>", Elements.Info[el].Color:ToHex(), el))
		end

		local headRow = UI.row(card, 26, 8)
		UI.icon(headRow, "Stations", 24, if info.Slots > 0 then UI.Colors.Gold else UI.Colors.Iron, 7)
		UI.label(headRow, string.format("<b>%s</b>  <font color=\"#%s\">Lv %d/%d</font>", station, UI.Colors.Muted:ToHex(), info.Level, SanctuaryConfig.StationMaxLevel), 18, {
			Font = UI.FontDisplay,
			Size = UDim2.new(1, -34, 1, 0),
			TextColor3 = UI.Colors.Gold,
			TextWrapped = false,
		})

		UI.label(card, STATION_INFO[station], 13, { TextColor3 = UI.Colors.Muted, Size = UDim2.new(1, 0, 0, 32) })
		UI.label(card, string.format("%s +25%%  •  Dragons %d/%d  •  <b>%s/s</b>  •  +%d%% level",
			table.concat(prefers, " & "), used, info.Slots, Format.Short(income), math.floor(info.Level * SanctuaryConfig.StationLevelBonus * 100 + 0.5)), 13, {
			Size = UDim2.new(1, 0, 0, 34),
		})

		local row = UI.row(card, 44, 6)
		local canSlot = info.Slots < SanctuaryConfig.SlotsPerStation and nextCost ~= nil
		local _, setSlot = UI.button(row, "", function()
			act("BuySlot", station, "New slot at the " .. station .. "!")
		end, { Size = UDim2.new(1 / 3, -4, 1, 0), TextSize = 13 })
		if info.Slots >= SanctuaryConfig.SlotsPerStation then
			setSlot(false, "Slots full")
		elseif not nextCost then
			setSlot(false, "All unlocked")
		else
			setSlot(canSlot and coins() >= nextCost, (if info.Slots == 0 then "Build " else "+ Slot ") .. "◉" .. Format.Short(nextCost))
		end

		local upgradeCost = SanctuaryConfig.UpgradeCost(info.Level)
		local _, setUpgrade = UI.button(row, "", function()
			act("Upgrade", station, station .. " upgraded!")
		end, { Size = UDim2.new(1 / 3, -4, 1, 0), TextSize = 13 })
		if info.Slots == 0 then
			setUpgrade(false, "Build first")
		elseif not upgradeCost then
			setUpgrade(false, "Max level")
		else
			setUpgrade(coins() >= upgradeCost, "Upgrade ◉" .. Format.Short(upgradeCost))
		end

		local _, setAssign = UI.button(row, "Assign", function()
			DragonsSheet.Open(station)
		end, { Size = UDim2.new(1 / 3, -4, 1, 0), TextSize = 13, BackgroundColor3 = UI.Colors.Secondary, TextColor3 = UI.Colors.Text })
		setAssign(used < info.Slots, if used < info.Slots then "Assign" elseif info.Slots == 0 then "No slots" else "Full")
	end
end

function StationsSheet.init(screen: ScreenGui)
	sheet = UI.sheet(screen, "Stations", 0, "Stations")
	sheet.OnOpen.Event:Connect(render)
	Store.Changed:Connect(render)
	local lastSignature = ""
	player:GetAttributeChangedSignal("Coins"):Connect(function()
		local state = Store.State
		if not state or not sheet.IsOpen() then
			return
		end
		local parts = { tostring(state.NextSlotCost and coins() >= state.NextSlotCost) }
		for _, station in SanctuaryConfig.Stations do
			local cost = SanctuaryConfig.UpgradeCost(state.Stations[station].Level)
			table.insert(parts, tostring(cost and coins() >= cost))
		end
		local signature = table.concat(parts, ",")
		if signature ~= lastSignature then
			lastSignature = signature
			render()
		end
	end)
end

function StationsSheet.Open(station: string?)
	focus = station
	sheet.Open()
	sheet.Body.CanvasPosition = Vector2.zero
end

return StationsSheet
