-- ReplicatedStorage/Client/CombatClient
-- The battle screen and controls. Shows health, shields, effects, the timer, the
-- 4 skill buttons (3 skills + ultimate) and dodge, then the results.
-- Keys: 1 2 3 = skills, 4 = ultimate, E = dodge (gamepad: X, R1, L1, L2, R3).
-- It only sends "use skill N" / "dodge"; the server decides what happens.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared

local UI = require(script.Parent.UI)
local Hud = require(script.Parent.Hud)
local CombatFx = require(script.Parent.CombatFx)
local FlightController = require(script.Parent.FlightController)
local SkillCatalog = require(Shared.SkillCatalog)
local Leveling = require(Shared.Leveling)
local Elements = require(Shared.Elements)
local Rarities = require(Shared.Rarities)

local CombatClient = {}

local player = Players.LocalPlayer
local remote: RemoteEvent
local screen: ScreenGui

local hud: Frame
local timerLabel: TextLabel
local centerLabel: TextLabel
local panels: { [string]: any } = {}
local skillButtons: { any } = {}
local dodgeButton: any
local queuePill: Frame
local queueLabel: TextLabel
local queueSince = 0
local queueMode: string? = nil
local resultsBox: Frame?
local foeMarker: BillboardGui?
local partyLabel: TextLabel
local queueParty = 0
local queueStartsIn = 0

local match: any = nil -- { Id, Mode, You, Foe, Fighting }
local readyAt = { 0, 0, 0, 0 }
local dodgeReadyAt = 0
local lastDenied = 0

local DENIED_TEXT = {
	out_of_range = "Too far away. Fly closer!",
	blocked = "Something's in the way.",
	stunned = "You're stunned!",
	ult_not_ready = "Your ultimate isn't charged yet.",
	skill_locked = "That skill unlocks at a higher level.",
}

local STATUS_COLORS = {
	Burn = Color3.fromRGB(255, 120, 60), Chill = Color3.fromRGB(150, 220, 255), Snare = Color3.fromRGB(120, 200, 100),
	Stun = Color3.fromRGB(255, 230, 90), Weaken = Color3.fromRGB(180, 120, 255), Haste = Color3.fromRGB(120, 255, 200),
	Empower = Color3.fromRGB(255, 170, 90), Evade = Color3.fromRGB(210, 210, 255), Regen = Color3.fromRGB(110, 230, 130),
}

local function shortName(name: string): string
	return if #name > 13 then name:sub(1, 12) .. "." else name
end

-- Health panels ------------------------------------------------------------------

local function makePanel(side: string)
	local left = side == "You"
	local frame = UI.new("Frame", {
		AnchorPoint = Vector2.new(if left then 1 else 0, 0),
		Position = UDim2.new(0.5, if left then -34 else 34, 0, 60),
		Size = UDim2.new(0.44, -34, 0, 62),
		BackgroundColor3 = UI.Colors.Panel,
		BackgroundTransparency = 0.12,
		Parent = hud,
	})
	UI.new("UISizeConstraint", { MaxSize = Vector2.new(280, 62), Parent = frame })
	UI.corner(frame, 10)
	UI.stroke(frame, if left then UI.Colors.Good else UI.Colors.Bad, 1.5)
	local name = UI.label(frame, "", 14, {
		Position = UDim2.fromOffset(10, 4), Size = UDim2.new(1, -20, 0, 18), TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd, TextXAlignment = if left then Enum.TextXAlignment.Left else Enum.TextXAlignment.Right,
	})
	local back = UI.new("Frame", { Position = UDim2.fromOffset(10, 25), Size = UDim2.new(1, -20, 0, 14), BackgroundColor3 = Color3.fromRGB(50, 30, 30), Parent = frame })
	UI.corner(back, 7)
	local fill = UI.new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = if left then UI.Colors.Good else UI.Colors.Bad, Parent = back })
	UI.corner(fill, 7)
	local shieldBar = UI.new("Frame", { Size = UDim2.fromScale(0, 0.45), Position = UDim2.fromScale(0, 0), BackgroundColor3 = Color3.fromRGB(170, 220, 255), Parent = back })
	UI.corner(shieldBar, 4)
	local hpText = UI.label(back, "", 11, { Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, Font = UI.FontBold, ZIndex = 2 })
	local status = UI.label(frame, "", 11, {
		Position = UDim2.fromOffset(10, 42), Size = UDim2.new(1, -20, 0, 16), TextWrapped = false,
		TextXAlignment = if left then Enum.TextXAlignment.Left else Enum.TextXAlignment.Right, TextColor3 = UI.Colors.Muted,
	})
	return { Frame = frame, Name = name, Fill = fill, Shield = shieldBar, HPText = hpText, Status = status, MaxHP = 1 }
end

local function setPanelInfo(panel: any, info: any)
	local element = Elements.Info[info.Element]
	local rarity = info.Rarity and Rarities.Info[info.Rarity]
	panel.MaxHP = info.MaxHP
	panel.Name.Text = string.format("<b>%s</b>  <font color=\"#%s\">%s</font> Lv %d%s",
		info.Name, element and element.Color:ToHex() or "ffffff", info.Element, info.Level,
		if rarity then string.format("  <font color=\"#%s\">%s</font>", rarity.Color:ToHex(), info.Rarity) else "")
end

local function setPanelState(panel: any, state: any)
	local share = math.clamp(state.HP / panel.MaxHP, 0, 1)
	UI.tween(panel.Fill, 0.15, { Size = UDim2.fromScale(share, 1) })
	panel.Shield.Size = UDim2.fromScale(math.clamp(state.Shield / panel.MaxHP, 0, 1), 0.45)
	panel.HPText.Text = string.format("%d / %d%s", state.HP, panel.MaxHP, if state.Shield > 0 then "  +" .. state.Shield else "")
	local parts = {}
	for _, name in state.Statuses do
		local info = SkillCatalog.Statuses[name]
		local color = STATUS_COLORS[name] or UI.Colors.Muted
		table.insert(parts, string.format("<font color=\"#%s\">%s</font>", color:ToHex(), info and info.Label or name))
	end
	panel.Status.Text = table.concat(parts, "  ")
end

-- Skill bar -------------------------------------------------------------------------

local function send(kind: string, slot: number?)
	remote:FireServer(kind, slot)
end

local function useSkill(slot: number)
	if not match or not match.Fighting then
		return
	end
	local button = skillButtons[slot]
	if button and button.Locked then
		if os.clock() - lastDenied > 1 then
			lastDenied = os.clock()
			Hud.Toast(string.format("Unlocks at level %d.", Leveling.SkillUnlockLevels[slot]), UI.Colors.Bad)
		end
		return
	end
	if os.clock() < readyAt[slot] then
		return
	end
	send("Skill", slot)
end

local function dodge()
	if not match or not match.Fighting or os.clock() < dodgeReadyAt then
		return
	end
	dodgeReadyAt = os.clock() + 3
	FlightController.Dodge()
	send("Dodge")
end

local function makeSkillButton(parent: Instance, slot: number, skillId: string, unlocked: boolean)
	local skill = SkillCatalog.Get(skillId) :: any
	local ult = slot == 4
	local button = UI.new("TextButton", {
		Size = UDim2.fromOffset(74, 74),
		BackgroundColor3 = if ult then Color3.fromRGB(70, 52, 24) else UI.Colors.Panel2,
		Text = "",
		AutoButtonColor = true,
		LayoutOrder = slot,
		Parent = parent,
	})
	UI.corner(button, 14)
	UI.stroke(button, if ult then UI.Colors.Gold else UI.Colors.Stroke, if ult then 2.5 else 1.5)
	UI.label(button, shortName(skill.Name), 12, {
		Position = UDim2.fromOffset(4, 22), Size = UDim2.new(1, -8, 0, 32), TextXAlignment = Enum.TextXAlignment.Center,
		Font = UI.FontBold, TextColor3 = if ult then UI.Colors.Gold else UI.Colors.Text,
	})
	UI.label(button, tostring(slot), 12, { Position = UDim2.fromOffset(7, 3), Size = UDim2.fromOffset(16, 16), TextColor3 = UI.Colors.Muted })
	UI.label(button, skill.Kind, 10, {
		Position = UDim2.new(0, 4, 1, -17), Size = UDim2.new(1, -8, 0, 14), TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = UI.Colors.Muted,
	})
	local cover = UI.new("Frame", {
		AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.fromScale(1, 0),
		BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.35, ZIndex = 3, Parent = button,
	})
	UI.corner(cover, 14)
	local coverText = UI.label(button, "", 20, { Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, Font = UI.FontBold, ZIndex = 4 })
	local charge: Frame? = nil
	if ult then
		local back = UI.new("Frame", { Position = UDim2.new(0, 8, 1, -6), Size = UDim2.new(1, -16, 0, 4), BackgroundColor3 = Color3.fromRGB(40, 32, 20), ZIndex = 5, Parent = button })
		charge = UI.new("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = UI.Colors.Gold, ZIndex = 6, Parent = back })
	end
	if not unlocked then
		cover.Size = UDim2.fromScale(1, 1)
		coverText.Text = "Lv " .. Leveling.SkillUnlockLevels[slot]
		coverText.TextSize = 16
	end
	button.Activated:Connect(function()
		useSkill(slot)
	end)
	return { Button = button, Cover = cover, CoverText = coverText, Charge = charge, Locked = not unlocked, Cooldown = skill.Cooldown, Ult = 0 }
end

local function buildSkillBar(you: any)
	local bar = UI.new("Frame", {
		Name = "SkillBar",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -14),
		Size = UDim2.fromOffset(4 * 74 + 64 + 4 * 8, 74),
		BackgroundTransparency = 1,
		Parent = hud,
	})
	local layout = UI.list(bar, 8, true)
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	skillButtons = {}
	for slot = 1, 4 do
		skillButtons[slot] = makeSkillButton(bar, slot, you.Skills[slot], slot <= you.Unlocked)
	end
	local d = UI.new("TextButton", {
		Size = UDim2.fromOffset(64, 64), BackgroundColor3 = UI.Colors.Secondary, Text = "", LayoutOrder = 5, Parent = bar,
	})
	UI.corner(d, 32)
	UI.stroke(d, Color3.fromRGB(200, 220, 255), 1.5)
	UI.label(d, "<b>Dodge</b>", 13, { Size = UDim2.new(1, 0, 0, 20), Position = UDim2.fromOffset(0, 14), TextXAlignment = Enum.TextXAlignment.Center })
	UI.label(d, "E", 11, { Size = UDim2.new(1, 0, 0, 14), Position = UDim2.fromOffset(0, 36), TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = UI.Colors.Muted })
	local cover = UI.new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 1, ZIndex = 3, Parent = d })
	UI.corner(cover, 32)
	d.Activated:Connect(dodge)
	dodgeButton = { Button = d, Cover = cover }
end

-- Foe marker -------------------------------------------------------------------------

local function markFoe(model: any)
	if foeMarker then
		foeMarker:Destroy()
		foeMarker = nil
	end
	if typeof(model) ~= "Instance" or not model:IsA("Model") or not model.PrimaryPart then
		return
	end
	local gui = Instance.new("BillboardGui")
	gui.Name = "FoeMarker"
	gui.Adornee = model.PrimaryPart
	gui.AlwaysOnTop = true
	gui.Size = UDim2.fromOffset(34, 34)
	gui.StudsOffset = Vector3.new(0, (model:GetAttribute("FootOffset") or 6) * 2.4, 0)
	UI.new("TextLabel", {
		Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "◆", TextScaled = true,
		TextColor3 = UI.Colors.Bad, Font = UI.FontBold, TextStrokeTransparency = 0.3, Parent = gui,
	})
	gui.Parent = player:WaitForChild("PlayerGui")
	foeMarker = gui
end

-- Match flow -----------------------------------------------------------------------

local function clearResults()
	if resultsBox then
		resultsBox:Destroy()
		resultsBox = nil
	end
end

local function endBattleScreen()
	match = nil
	hud.Visible = false
	centerLabel.Visible = false
	clearResults()
	markFoe(nil)
	Hud.SetBattleMode(false)
	for slot = 1, 4 do
		ContextActionService:UnbindAction("CombatSkill" .. slot)
	end
	ContextActionService:UnbindAction("CombatDodge")
end

local function flashCenter(text: string, color: Color3, seconds: number)
	centerLabel.Text = text
	centerLabel.TextColor3 = color
	centerLabel.Visible = true
	centerLabel.TextTransparency = 0
	task.delay(seconds, function()
		if centerLabel.Text == text then
			UI.tween(centerLabel, 0.3, { TextTransparency = 1 })
		end
	end)
end

local SKILL_KEYS = {
	{ Enum.KeyCode.One, Enum.KeyCode.KeypadOne, Enum.KeyCode.ButtonX },
	{ Enum.KeyCode.Two, Enum.KeyCode.KeypadTwo, Enum.KeyCode.ButtonR1 },
	{ Enum.KeyCode.Three, Enum.KeyCode.KeypadThree, Enum.KeyCode.ButtonL1 },
	{ Enum.KeyCode.Four, Enum.KeyCode.KeypadFour, Enum.KeyCode.ButtonL2 },
}

local function bindKeys()
	for slot = 1, 4 do
		ContextActionService:BindActionAtPriority("CombatSkill" .. slot, function(_, state)
			if state == Enum.UserInputState.Begin then
				useSkill(slot)
			end
			return Enum.ContextActionResult.Sink
		end, false, Enum.ContextActionPriority.High.Value + 1, table.unpack(SKILL_KEYS[slot]))
	end
	ContextActionService:BindActionAtPriority("CombatDodge", function(_, state)
		if state == Enum.UserInputState.Begin then
			dodge()
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.ContextActionPriority.High.Value + 1, Enum.KeyCode.E, Enum.KeyCode.ButtonR3)
end

local function onMatchStart(payload: any)
	clearResults()
	queueMode = nil
	queuePill.Visible = false
	match = { Id = payload.Id, Mode = payload.Mode, You = payload.You, Foe = payload.Foe, Fighting = false }
	readyAt = { 0, 0, 0, 0 }
	dodgeReadyAt = 0
	Hud.SetBattleMode(true)
	for _, child in hud:GetChildren() do
		if child.Name == "SkillBar" then
			child:Destroy()
		end
	end
	setPanelInfo(panels.You, payload.You)
	setPanelInfo(panels.Foe, payload.Foe)
	setPanelState(panels.You, { HP = payload.You.MaxHP, Shield = 0, Statuses = {} })
	setPanelState(panels.Foe, { HP = payload.Foe.MaxHP, Shield = 0, Statuses = {} })
	partyLabel.Text = ""
	partyLabel.Visible = payload.Mode == "Raid" and payload.Party ~= nil and #payload.Party > 1
	buildSkillBar(payload.You)
	timerLabel.Text = string.format("%d:%02d", payload.Duration // 60, payload.Duration % 60)
	hud.Visible = true
	markFoe(payload.Foe.Model)
	bindKeys()
	local modeText = if payload.Mode == "Ranked" then "Ranked: every dragon fights at level 30"
		elseif payload.Mode == "Practice" then "Practice"
		elseif payload.Mode == "Raid" then "Raid vs " .. payload.Foe.Name .. ". Fly out of the red zones!"
		else "Casual"
	Hud.Toast(modeText .. "  •  1 2 3: skills  •  4: ultimate  •  E: dodge", UI.Colors.Gold)
	task.spawn(function()
		local id = payload.Id
		for n = payload.Countdown, 1, -1 do
			if not match or match.Id ~= id or match.Fighting then
				return
			end
			flashCenter(tostring(n), UI.Colors.Text, 0.8)
			task.wait(1)
		end
	end)
end

local function onUpdate(payload: any)
	if not match then
		return
	end
	local t = math.ceil(payload.Time)
	timerLabel.Text = string.format("%d:%02d", t // 60, t % 60)
	timerLabel.TextColor3 = if t <= 15 and match.Fighting then UI.Colors.Bad else UI.Colors.Text
	setPanelState(panels.You, payload.You)
	setPanelState(panels.Foe, payload.Foe)
	local clock = os.clock()
	for slot = 1, 4 do
		readyAt[slot] = clock + math.max(payload.Cooldowns[slot] or 0, if slot ~= 4 then payload.Busy or 0 else 0)
	end
	dodgeReadyAt = clock + (payload.Dodge or 0)
	if payload.Down then
		centerLabel.Text = string.format("DOWN  %d", math.ceil(payload.Down))
		centerLabel.TextColor3 = UI.Colors.Bad
		centerLabel.TextTransparency = 0
		centerLabel.Visible = true
	end
	if payload.Party and partyLabel.Visible then
		local parts = {}
		for _, p in payload.Party do
			local color = if p.Gone then UI.Colors.Muted elseif p.Down then UI.Colors.Bad else UI.Colors.Good
			local state = if p.Gone then "left" elseif p.Down then "down" else string.format("%d%%", math.floor(p.HP / math.max(p.MaxHP, 1) * 100))
			table.insert(parts, string.format("<font color=\"#%s\">%s %s</font>", color:ToHex(), p.Name, state))
		end
		partyLabel.Text = table.concat(parts, "   ")
	end
	local ult = skillButtons[4]
	if ult then
		ult.Ult = payload.You.Ult
	end
end

local function onMatchEnd(payload: any)
	if not match then
		return
	end
	match.Fighting = false
	for slot = 1, 4 do
		ContextActionService:UnbindAction("CombatSkill" .. slot)
	end
	ContextActionService:UnbindAction("CombatDodge")
	clearResults()
	local won = payload.Won
	local raid = payload.Mode == "Raid"
	local dim = UI.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.45), Size = UDim2.new(0.86, 0, 0, 250),
		BackgroundColor3 = UI.Colors.Panel, ZIndex = 20, Parent = hud,
	})
	UI.new("UISizeConstraint", { MaxSize = Vector2.new(360, 280), Parent = dim })
	UI.corner(dim, 16)
	UI.stroke(dim, if won then UI.Colors.Gold else UI.Colors.Bad, 2)
	UI.padding(dim, 14)
	UI.list(dim, 6).HorizontalAlignment = Enum.HorizontalAlignment.Center
	local reason = if raid then (if payload.Reason == "Cleared" then "The Elder has fallen!"
			elseif payload.Reason == "Wiped" then "Everyone was down at the same time"
			elseif payload.Reason == "Time" then "Time ran out"
			else "The raid ended")
		elseif payload.Reason == "KO" then (if won then "Knockout!" else "Knocked out")
		elseif payload.Reason == "Time" then "Time's up: more health left wins"
		else (if won then "Your opponent left the fight" else "You left the fight")
	local title = if raid then (if won then "RAID CLEARED" else "RAID FAILED") else (if won then "VICTORY" else "DEFEAT")
	UI.label(dim, "<b>" .. title .. "</b>", 30, { TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = if won then UI.Colors.Gold else UI.Colors.Bad, ZIndex = 21 })
	UI.label(dim, reason .. "  •  vs " .. tostring(payload.FoeName), 14, { TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = UI.Colors.Muted, ZIndex = 21 })
	local r = payload.Rewards
	if r then
		local lines = {}
		if r.XP and r.XP > 0 then
			table.insert(lines, string.format("+%d XP%s", r.XP, if r.Levels and r.Levels > 0 then string.format("  <font color=\"#%s\">Level up! Lv %d</font>", UI.Colors.Gold:ToHex(), r.Level or 0) else ""))
		end
		if payload.Mode == "Ranked" then
			table.insert(lines, string.format("%s%d trophies  (%d total)", if r.Trophies >= 0 then "+" else "", r.Trophies, r.TrophyTotal or 0))
		end
		if r.Scales and r.Scales > 0 then
			table.insert(lines, string.format("+%d dragon scales", r.Scales))
		end
		if r.Relics and r.Relics > 0 then
			table.insert(lines, string.format("<font color=\"#%s\">+%d relic shards</font>", Color3.fromRGB(190, 160, 255):ToHex(), r.Relics))
		end
		for _, line in lines do
			UI.label(dim, line, 18, { TextXAlignment = Enum.TextXAlignment.Center, Font = UI.FontBold, ZIndex = 21 })
		end
		if r.Note then
			UI.label(dim, r.Note, 13, { TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = UI.Colors.Muted, Size = UDim2.new(1, 0, 0, 34), ZIndex = 21 })
		end
	end
	UI.label(dim, "Flying home in a moment...", 13, { TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = UI.Colors.Muted, ZIndex = 21 })
	resultsBox = dim
	local id = match.Id
	task.delay(5.5, function()
		if match and match.Id == id then
			endBattleScreen()
		end
	end)
end

local function onQueue(status: any)
	if type(status) ~= "table" then
		return
	end
	if status.Status == "Searching" then
		if queueMode ~= status.Mode then
			queueSince = os.clock()
		end
		queueMode = status.Mode
		queueParty = tonumber(status.Party) or 0
		queueStartsIn = tonumber(status.StartsIn) or 0
		queuePill.Visible = true
	elseif status.Status == "Failed" then
		queueMode = nil
		queuePill.Visible = false
		Hud.Toast("The battle couldn't start. Try again.", UI.Colors.Bad)
	else
		queueMode = nil
		queuePill.Visible = false
	end
end

local function onEvent(kind: string, a: any, b: any, c: any)
	if kind == "Fx" then
		CombatFx.Play(a, b)
		-- My own strikes lunge and my breath keeps facing the target.
		if a == "Cast" and type(b) == "table" and match and b.Caster == FlightController.GetModel() then
			local foeRoot = typeof(b.Target) == "Instance" and b.Target.PrimaryPart
			local skill = SkillCatalog.Get(b.Skill)
			if skill and skill.Kind == "Strike" then
				FlightController.Lunge(foeRoot)
			elseif skill and skill.Kind == "Breath" then
				FlightController.FaceTarget(foeRoot, skill.Duration or 1.2)
			end
		end
	elseif kind == "MatchStart" then
		onMatchStart(a)
	elseif kind == "Fight" then
		if match then
			match.Fighting = true
			flashCenter("FIGHT!", UI.Colors.Gold, 0.9)
		end
	elseif kind == "Update" then
		onUpdate(a)
	elseif kind == "Denied" then
		local text = DENIED_TEXT[b]
		if text and os.clock() - lastDenied > 0.8 then
			lastDenied = os.clock()
			Hud.Toast(text, UI.Colors.Bad)
		end
	elseif kind == "Knockback" then
		FlightController.Knockback(a)
	elseif kind == "Announce" then
		Hud.Toast(tostring(a), UI.Colors.Gold)
	elseif kind == "Down" then
		Hud.Toast("You're down! Hang on, you'll be back in a few seconds.", UI.Colors.Bad)
	elseif kind == "Revive" then
		flashCenter("BACK IN!", UI.Colors.Good, 0.8)
	elseif kind == "Warn" then
		Hud.Toast(tostring(a), UI.Colors.Bad)
	elseif kind == "MatchEnd" then
		onMatchEnd(a)
	elseif kind == "Queue" then
		onQueue(a)
	end
end

-- Every frame: cooldown sweeps, ultimate charge, queue timer.
local function render()
	local clock = os.clock()
	if match and hud.Visible then
		for slot, b in skillButtons do
			if not b.Locked then
				local left = readyAt[slot] - clock
				if slot == 4 then
					local ready = b.Ult >= 100
					if b.Charge then
						b.Charge.Size = UDim2.fromScale(b.Ult / 100, 1)
					end
					b.Cover.Size = UDim2.fromScale(1, if ready then 0 else 1 - b.Ult / 100)
					b.CoverText.Text = if ready then "" else tostring(b.Ult) .. "%"
					b.CoverText.TextSize = 14
				elseif left > 0 then
					b.Cover.Size = UDim2.fromScale(1, math.clamp(left / b.Cooldown, 0, 1))
					b.CoverText.Text = if left >= 1 then tostring(math.ceil(left)) else ""
				else
					b.Cover.Size = UDim2.fromScale(1, 0)
					b.CoverText.Text = ""
				end
			end
		end
		if dodgeButton then
			dodgeButton.Cover.BackgroundTransparency = if clock < dodgeReadyAt then 0.4 else 1
		end
	end
	if queueMode == "Raid" then
		queueLabel.Text = string.format("Gathering a <b>raid</b> party (%d/4)...  starts in %d", math.max(queueParty, 1), queueStartsIn)
	elseif queueMode then
		local waited = math.floor(clock - queueSince)
		queueLabel.Text = string.format("Looking for a <b>%s</b> opponent...  %d:%02d", queueMode, waited // 60, waited % 60)
	end
end

function CombatClient.init(screenGui: ScreenGui)
	screen = screenGui
	hud = UI.new("Frame", { Name = "BattleHud", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false, ZIndex = 10, Parent = screen })
	panels.You = makePanel("You")
	panels.Foe = makePanel("Foe")
	partyLabel = UI.label(hud, "", 12, {
		AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 128), Size = UDim2.new(0.9, 0, 0, 20),
		TextXAlignment = Enum.TextXAlignment.Center, TextWrapped = false, BackgroundTransparency = 0.3, BackgroundColor3 = UI.Colors.Panel,
		Visible = false,
	})
	UI.new("UISizeConstraint", { MaxSize = Vector2.new(560, 20), Parent = partyLabel })
	timerLabel = UI.label(hud, "2:30", 20, {
		AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 70), Size = UDim2.fromOffset(64, 30),
		TextXAlignment = Enum.TextXAlignment.Center, Font = UI.FontBold, BackgroundTransparency = 0.2, BackgroundColor3 = UI.Colors.Panel,
	})
	UI.corner(timerLabel, 8)
	centerLabel = UI.label(hud, "", 64, {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.38), Size = UDim2.fromOffset(400, 90),
		TextXAlignment = Enum.TextXAlignment.Center, Font = Enum.Font.GothamBlack, TextStrokeTransparency = 0.4, Visible = false,
	})

	queuePill = UI.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -82), Size = UDim2.new(0.9, 0, 0, 44),
		BackgroundColor3 = UI.Colors.Panel, BackgroundTransparency = 0.05, Visible = false, Parent = screen,
	})
	UI.new("UISizeConstraint", { MaxSize = Vector2.new(420, 44), Parent = queuePill })
	UI.corner(queuePill, 22)
	UI.stroke(queuePill, UI.Colors.Gold, 1.5)
	queueLabel = UI.label(queuePill, "", 14, { Position = UDim2.fromOffset(16, 0), Size = UDim2.new(1, -110, 1, 0), TextWrapped = false })
	UI.button(queuePill, "Cancel", function()
		remote.Parent:WaitForChild("Request"):InvokeServer("QueueLeave")
	end, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -6, 0.5, 0), Size = UDim2.fromOffset(84, 34), BackgroundColor3 = UI.Colors.Secondary, TextColor3 = UI.Colors.Text, TextSize = 14 })

	remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Combat") :: RemoteEvent
	remote.OnClientEvent:Connect(onEvent)
	RunService.RenderStepped:Connect(render)
end

function CombatClient.InBattle(): boolean
	return match ~= nil
end

return CombatClient
