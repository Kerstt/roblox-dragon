-- ReplicatedStorage/Client/BattleSheet
-- The Battle menu: your record, pick a dragon, then Casual, Ranked, Practice
-- or the co-op Raid against today's Elder dragon.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared

local UI = require(script.Parent.UI)
local Store = require(script.Parent.Store)
local Hud = require(script.Parent.Hud)
local DragonCatalog = require(Shared.DragonCatalog)
local Elements = require(Shared.Elements)
local Rarities = require(Shared.Rarities)
local SkillCatalog = require(Shared.SkillCatalog)
local Leveling = require(Shared.Leveling)
local CombatConfig = require(Shared.CombatConfig)
local RaidConfig = require(Shared.RaidConfig)

local BattleSheet = {}

local sheet: UI.Sheet
local selected: string? = nil
local busy = false

local MODES = {
	{ Id = "Casual", Title = "Casual", Button = "Find a match",
		Text = "Fight real players whose dragons are about as strong as yours. Win XP and dragon scales." },
	{ Id = "Ranked", Title = "Ranked", Button = "Find a ranked match",
		Text = "Every dragon fights at level 30 with all 4 skills and no rarity bonus, so skill decides. Win trophies." },
	{ Id = "Practice", Title = "Practice", Button = "Start practice",
		Text = "Spar with an AI dragon at your dragon's level. A little XP, up to " .. Leveling.PracticeRewardsPerDay .. " times a day." },
}

local function sortedIds(state: any): { string }
	local ids = {}
	for id in state.Dragons do
		table.insert(ids, id)
	end
	table.sort(ids, function(a, b)
		local da, db = state.Dragons[a], state.Dragons[b]
		if (da.Level or 1) ~= (db.Level or 1) then
			return (da.Level or 1) > (db.Level or 1)
		end
		local ra, rb = Rarities.Info[da.Rarity].Rank, Rarities.Info[db.Rarity].Rank
		if ra ~= rb then
			return ra > rb
		end
		return (tonumber(a:sub(2)) or 0) < (tonumber(b:sub(2)) or 0)
	end)
	return ids
end

local render: () -> ()

local function join(mode: string)
	if busy or not selected then
		return
	end
	busy = true
	local result = Store.Request("QueueJoin", mode, selected)
	busy = false
	if not result.ok then
		Hud.Error(result.error)
		return
	end
	sheet.Close()
	if not result.started then
		Hud.Toast(if mode == "Raid" then "Gathering a raid party. It starts soon!" else "Looking for an opponent. Keep playing, we'll fly you to the arena!", UI.Colors.Gold)
	end
end

local function dragonRow(state: any, id: string, order: number)
	local d = state.Dragons[id]
	local species = DragonCatalog.Get(d.Species) :: any
	local rarity = Rarities.Info[d.Rarity]
	local element = Elements.Info[species.Element]
	local isSelected = selected == id
	local card = UI.card(sheet.Body, { LayoutOrder = order, BackgroundColor3 = if isSelected then UI.Colors.Panel3 else UI.Colors.Panel2 })
	if isSelected then
		UI.stroke(card, UI.Colors.Gold, 2)
	end
	UI.list(card, 4)
	local top = UI.row(card, 40)
	local info = UI.new("Frame", { Size = UDim2.new(1, -96, 1, 0), BackgroundTransparency = 1, Parent = top })
	local unlocked = Leveling.SkillsUnlocked(d.Level or 1)
	UI.label(info, string.format("<b>%s</b>  Lv %d  <font color=\"#%s\">%s</font>", species.Name, d.Level or 1, rarity.Color:ToHex(), d.Rarity), 15, {
		Size = UDim2.new(1, 0, 0, 20), TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd,
	})
	UI.label(info, string.format("<font color=\"#%s\">%s</font> • %s • %d/4 skills", element.Color:ToHex(), element.DisplayName,
		CombatConfig.SpeciesArchetype[d.Species] or "", unlocked), 12, {
		Position = UDim2.fromOffset(0, 20), Size = UDim2.new(1, 0, 0, 16), TextColor3 = UI.Colors.Muted, TextWrapped = false,
	})
	UI.button(top, if isSelected then "Chosen" else "Choose", function()
		selected = id
		render()
	end, {
		Size = UDim2.fromOffset(88, 36), TextSize = 14,
		BackgroundColor3 = if isSelected then UI.Colors.Gold else UI.Colors.Secondary,
		TextColor3 = if isSelected then UI.Colors.ButtonText else UI.Colors.Text,
	})
	if isSelected then
		local skills = SkillCatalog.ForSpecies(d.Species) or {}
		for slot, skillId in skills do
			local skill = SkillCatalog.Get(skillId) :: any
			local open = slot <= unlocked
			UI.label(card, string.format("%s<b>%s</b>%s  <font color=\"#%s\">%s</font>",
				if slot == 4 then "Ultimate: " else slot .. ". ", skill.Name,
				if open then "" else string.format(" (Lv %d)", Leveling.SkillUnlockLevels[slot]),
				UI.Colors.Muted:ToHex(), skill.Text), 12, {
				Size = UDim2.new(1, 0, 0, 30), TextColor3 = if open then UI.Colors.Text else UI.Colors.Muted,
			})
		end
	end
end

render = function()
	local state = Store.State
	if not sheet or not sheet.IsOpen() or not state or not state.Combat then
		return
	end
	local body = sheet.Body
	local scroll = body.CanvasPosition
	UI.clear(body)
	local c = state.Combat

	local stats = UI.card(body, { LayoutOrder = 1 })
	UI.list(stats, 2)
	UI.label(stats, string.format("<b>%d trophies</b>  <font color=\"#%s\">(best %d)</font>", c.Trophies, UI.Colors.Muted:ToHex(), c.BestTrophies), 18, { TextColor3 = UI.Colors.Gold })
	UI.label(stats, string.format("Wins %d • Losses %d • Ranked %d-%d • %d dragon scales", c.Wins, c.Losses, c.RankedWins, c.RankedLosses, c.Scales), 13, { TextColor3 = UI.Colors.Muted })
	UI.label(stats, string.format("Practice XP left today: %d/%d • Raid rewards left: %d/%d • %d relic shards",
		c.PracticeLeft, Leveling.PracticeRewardsPerDay, c.RaidLeft or 0, Leveling.RaidRewardsPerDay, c.Relics or 0), 13, { TextColor3 = UI.Colors.Muted })

	-- Modes
	if state.Queue then
		local waiting = UI.card(body, { LayoutOrder = 2, BackgroundColor3 = UI.Colors.Panel3 })
		UI.list(waiting, 6)
		UI.label(waiting, "Looking for a <b>" .. state.Queue .. "</b> opponent...", 15)
		UI.button(waiting, "Cancel", function()
			Store.Request("QueueLeave")
		end, { Size = UDim2.new(1, 0, 0, 38), BackgroundColor3 = UI.Colors.Secondary, TextColor3 = UI.Colors.Text })
	else
		for i, mode in MODES do
			local card = UI.card(body, { LayoutOrder = 1 + i })
			UI.list(card, 4)
			UI.label(card, "<b>" .. mode.Title .. "</b>", 16, { TextColor3 = UI.Colors.Gold })
			UI.label(card, mode.Text, 13, { Size = UDim2.new(1, 0, 0, 34), TextColor3 = UI.Colors.Muted })
			local _, setEnabled = UI.button(card, mode.Button, function()
				join(mode.Id)
			end, { Size = UDim2.new(1, 0, 0, 40) })
			setEnabled(selected ~= nil and not state.InBattle)
		end
		-- Co-op raid against today's Elder
		local boss = RaidConfig.Today()
		local bossSpecies = DragonCatalog.Get(boss.Species) :: any
		local bossElement = Elements.Info[bossSpecies.Element]
		local raidCard = UI.card(body, { LayoutOrder = 5, BackgroundColor3 = Color3.fromRGB(48, 36, 44) })
		UI.stroke(raidCard, Color3.fromRGB(190, 160, 255), 1.5)
		UI.list(raidCard, 4)
		UI.label(raidCard, string.format("<b>Co-op Raid: %s</b>  <font color=\"#%s\">%s</font>", boss.Name, bossElement.Color:ToHex(), bossElement.DisplayName), 16, {
			TextColor3 = Color3.fromRGB(210, 190, 255),
		})
		UI.label(raidCard, string.format("Team up with up to %d players against a giant Elder dragon. Fly out of the red zones and dodge its orbs! Bring a dragon strong against %s. Wins give XP, scales and relic shards. A new Elder every day.",
			RaidConfig.MaxParty, bossElement.DisplayName), 13, { Size = UDim2.new(1, 0, 0, 50), TextColor3 = UI.Colors.Muted })
		local _, setRaid = UI.button(raidCard, "Join the raid", function()
			join("Raid")
		end, { Size = UDim2.new(1, 0, 0, 40), BackgroundColor3 = Color3.fromRGB(170, 140, 240) })
		setRaid(selected ~= nil and not state.InBattle)
	end

	UI.label(body, "<b>Your fighter</b>", 16, { LayoutOrder = 10, TextColor3 = UI.Colors.Gold })
	local ids = sortedIds(state)
	if selected and not state.Dragons[selected] then
		selected = nil
	end
	selected = selected or ids[1]
	for i, id in ids do
		dragonRow(state, id, 10 + i)
	end
	if #ids == 0 then
		UI.label(body, "Hatch a dragon first!", 15, { LayoutOrder = 11, TextColor3 = UI.Colors.Muted })
	end
	task.defer(function()
		body.CanvasPosition = scroll
	end)
end

function BattleSheet.init(screen: ScreenGui)
	sheet = UI.sheet(screen, "Battle")
	sheet.OnOpen.Event:Connect(render)
	Store.Changed:Connect(render)
end

function BattleSheet.Open()
	sheet.Open()
end

return BattleSheet
