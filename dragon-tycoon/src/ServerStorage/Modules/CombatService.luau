-- ServerStorage/Modules/CombatService
-- Server-authoritative 1v1 dragon duels in the sky arenas.
--
-- The server decides everything: whether a skill can be used (unlocked, off
-- cooldown, in range, line of sight, not stunned), hits, damage, shields, status
-- effects, ultimate charge, the winner and the rewards. Clients only send
-- "use skill N" / "dodge" and play the effects the server tells them about.
-- Players fly their own dragon (smooth flight needs client physics), and the
-- server checks positions: MountService caps speed, and leaving the arena walls
-- hurts.
--
-- ReplicatedStorage/Remotes/Combat (RemoteEvent):
--   client -> server: ("Skill", slot 1-4), ("Dodge")
--   server -> client: MatchStart, Fight, Update, Fx, Denied, Knockback, Warn, MatchEnd, Queue

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared

local CombatConfig = require(Shared.CombatConfig)
local SkillCatalog = require(Shared.SkillCatalog)
local Leveling = require(Shared.Leveling)
local DragonCatalog = require(Shared.DragonCatalog)
local Elements = require(Shared.Elements)
local DataService = require(script.Parent.DataService)
local MountService = require(script.Parent.MountService)
local PlotService = require(script.Parent.PlotService)
local RateLimiter = require(script.Parent.RateLimiter)
local PracticeBot = require(script.Parent.PracticeBot)
local RaidBoss = require(script.Parent.RaidBoss)
local RaidConfig = require(Shared.RaidConfig)

local CombatService = {}

local changed = Instance.new("BindableEvent")
-- Fires (player) when the player's saved combat data changed (rewards).
CombatService.Changed = changed.Event

local TICK = 0.1
local UPDATE_EVERY = 0.2
local BUFFS = { "Haste", "Empower", "Evade", "Regen" }

local combatRemote: RemoteEvent
local inputLimiter = RateLimiter.new(12, 20)
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.RespectCanCollide = true

type Arena = { Model: Model, Center: Vector3, SpawnA: CFrame, SpawnB: CFrame, Busy: boolean }
local arenas: { Arena } = {}
local matches: { [number]: any } = {}
local fighterByPlayer: { [Player]: any } = {}
local nextMatchId = 0

local function now(): number
	return os.clock()
end

local function today(): number
	return math.floor(os.time() / 86400)
end

-- Messaging ------------------------------------------------------------------------

local function sendTo(f: any, ...: any)
	if f.Player and f.Player.Parent == Players then
		combatRemote:FireClient(f.Player, ...)
	end
end

local function sendBoth(match: any, ...: any)
	for _, f in match.Fighters do
		sendTo(f, ...)
	end
end

-- Effects are sent to everyone so spectators see the fight too.
local function fx(kind: string, payload: any)
	combatRemote:FireAllClients("Fx", kind, payload)
end

-- Status effects -------------------------------------------------------------------

local function statusValue(f: any, name: string): number
	local s = f.Statuses[name]
	if s and s.Until > now() then
		return s.Value or 0
	end
	return 0
end

local function hasStatus(f: any, name: string): boolean
	local s = f.Statuses[name]
	return s ~= nil and s.Until > now()
end

local function attackOf(f: any): number
	return f.Stats.Attack * (1 + statusValue(f, "Empower"))
end

local function defenseOf(f: any): number
	return f.Stats.Defense * (1 - statusValue(f, "Weaken"))
end

-- Flight speed multiplier from slows, stuns and haste (the client reads it).
local function updateSpeed(f: any)
	local mul = f.Stats.Speed
	mul *= 1 - statusValue(f, "Chill")
	mul *= 1 - statusValue(f, "Snare")
	if hasStatus(f, "Stun") then
		mul *= 0.25
	end
	mul *= 1 + statusValue(f, "Haste")
	mul = math.clamp(mul, 0.15, 2)
	if math.abs(mul - f.SpeedMul) > 0.01 then
		f.SpeedMul = mul
		if f.Model and f.Model.Parent then
			f.Model:SetAttribute("SpeedMul", mul)
		end
	end
end

local function statusList(f: any): { string }
	local list = {}
	local t = now()
	for name, s in f.Statuses do
		if s.Until > t then
			table.insert(list, name)
		end
	end
	table.sort(list)
	return list
end

local function cleanse(f: any)
	for name in f.Statuses do
		local info = SkillCatalog.Statuses[name]
		if info and info.Harmful then
			f.Statuses[name] = nil
		end
	end
	updateSpeed(f)
end

local function applyEffects(source: any, target: any, effects: { any }?)
	if not effects then
		return
	end
	local t = now()
	for _, e in effects do
		if e.Status == "Knockback" then
			local away = target.Root.Position - source.Root.Position
			if away.Magnitude < 0.1 then
				away = source.Root.CFrame.LookVector
			end
			local push = away.Unit * (e.Value or 50)
			if target.Player then
				sendTo(target, "Knockback", push)
			elseif target.BotState then
				target.BotState.Impulse = push
			end
		elseif e.Status == "Burn" then
			local dps = CombatConfig.Damage(e.Value or 0.1, attackOf(source), defenseOf(target), source.Element, target.Element)
			local current = target.Statuses.Burn
			if not current or current.Until <= t or dps >= (current.Dps or 0) then
				target.Statuses.Burn = { Until = t + (e.Duration or 3), Value = e.Value, Dps = dps, Source = source }
			else
				current.Until = math.max(current.Until, t + (e.Duration or 3))
			end
		else
			local current = target.Statuses[e.Status]
			local value = e.Value or 0
			if not current or current.Until <= t or value >= (current.Value or 0) then
				target.Statuses[e.Status] = { Until = t + (e.Duration or 2), Value = value }
			else
				current.Until = math.max(current.Until, t + (e.Duration or 2))
			end
			if e.Status == "Stun" then
				target.ChannelUntil = 0 -- a stun interrupts breath attacks
			end
		end
	end
	updateSpeed(target)
end

-- Damage and healing -------------------------------------------------------------

local endMatch: (match: any, winner: any, reason: string) -> ()
local onZeroHealth: (f: any) -> ()

local function addUlt(f: any, amount: number)
	if f.Unlocked >= 4 then
		f.Ult = math.min(100, f.Ult + amount)
	end
end

local function heal(f: any, amount: number)
	if amount <= 0 or f.HP <= 0 then
		return
	end
	local before = f.HP
	f.HP = math.min(f.Stats.MaxHP, f.HP + amount)
	local healed = f.HP - before
	if healed >= 1 then
		fx("Heal", { Model = f.Model, Amount = math.floor(healed) })
	end
end

-- Takes damage through the shield. Returns the damage done.
local function hurt(target: any, amount: number, source: any?, showKind: string?): number
	local match = target.Match
	if match.State ~= "Fight" or target.HP <= 0 or amount <= 0 then
		return 0
	end
	local t = now()
	local absorbed = 0
	if target.Shield > 0 and t < target.ShieldUntil then
		absorbed = math.min(target.Shield, amount)
		target.Shield -= absorbed
	end
	target.HP = math.max(0, target.HP - (amount - absorbed))
	if source then
		source.Dealt += amount
		addUlt(source, amount / target.Stats.MaxHP * CombatConfig.UltPerDamageDealt)
	end
	addUlt(target, amount / target.Stats.MaxHP * CombatConfig.UltPerDamageTaken)
	if showKind then
		fx("Hit", { Model = target.Model, Amount = math.floor(amount + 0.5), Shielded = absorbed > 0, Kind = showKind })
	end
	if target.HP <= 0 then
		onZeroHealth(target)
	end
	return amount
end

-- One skill hit: dodge check, element math, shield break, lifesteal, effects.
local function resolveHit(source: any, target: any, skill: any, power: number)
	if source.Match.State ~= "Fight" or target.HP <= 0 or source.HP <= 0 then
		return
	end
	if now() < target.InvulnUntil then
		fx("Miss", { Model = target.Model, Text = "Dodged!" })
		return
	end
	local amount = CombatConfig.Damage(power, attackOf(source), defenseOf(target), source.Element, target.Element)
	if skill.ShieldBreak and target.Shield > 0 and now() < target.ShieldUntil then
		target.Shield = 0
		amount *= 1.25
		fx("ShieldBreak", { Model = target.Model })
	end
	local mult = Elements.GetDamageMultiplier(source.Element, target.Element)
	local kind = if mult > 1 then "Strong" elseif mult < 1 then "Weak" else "Normal"
	local dealt = hurt(target, amount, source, kind)
	if dealt > 0 and skill.Lifesteal then
		heal(source, dealt * skill.Lifesteal)
	end
	if dealt > 0 and target.HP > 0 then
		applyEffects(source, target, skill.Effects)
	end
end

local function lineOfSight(a: any, b: any): boolean
	local ignore = { a.Model, b.Model }
	for _, f in { a, b } do
		if f.Player and f.Player.Character then
			table.insert(ignore, f.Player.Character)
		end
	end
	rayParams.FilterDescendantsInstances = ignore
	local from = a.Root.Position
	local hit = workspace:Raycast(from, b.Root.Position - from, rayParams)
	return hit == nil
end

-- Skills ---------------------------------------------------------------------------

local function selfPart(f: any, skill: any)
	local t = now()
	if skill.Cleanse then
		cleanse(f)
	end
	if skill.Shield then
		f.Shield = math.max(f.Shield, f.Stats.MaxHP * skill.Shield)
		f.ShieldUntil = math.max(f.ShieldUntil, t + (skill.ShieldTime or 5))
		fx("Shield", { Model = f.Model, Until = skill.ShieldTime or 5 })
	end
	if skill.Heal then
		heal(f, f.Stats.MaxHP * skill.Heal)
	end
	if skill.SelfEffects then
		applyEffects(f, f, skill.SelfEffects)
	end
end

-- Eclipse Hex: take the target's shield and buffs.
local function steal(f: any, target: any)
	local t = now()
	if target.Shield > 0 and t < target.ShieldUntil then
		f.Shield = math.max(f.Shield, target.Shield)
		f.ShieldUntil = math.max(f.ShieldUntil, t + 5)
		target.Shield = 0
		fx("Shield", { Model = f.Model, Until = 5 })
	end
	for _, name in BUFFS do
		local s = target.Statuses[name]
		if s and s.Until > t then
			f.Statuses[name] = { Until = s.Until, Value = s.Value }
			target.Statuses[name] = nil
		end
	end
	updateSpeed(f)
	updateSpeed(target)
end

-- Uses skill `slot` (1-4). Returns true, or false and a reason code.
function CombatService.UseSkill(f: any, slot: any): (boolean, string?)
	local match = f.Match
	if match.State ~= "Fight" then
		return false, "not_started"
	end
	if type(slot) ~= "number" or slot ~= slot or slot % 1 ~= 0 or slot < 1 or slot > 4 then
		return false, "invalid"
	end
	if f.HP <= 0 or f.Down then
		return false, "down"
	end
	if slot > f.Unlocked then
		return false, "skill_locked"
	end
	local skill = SkillCatalog.Get(f.Skills[slot])
	if not skill then
		return false, "invalid"
	end
	local t = now()
	if hasStatus(f, "Stun") then
		return false, "stunned"
	end
	if t < f.ChannelUntil then
		return false, "busy"
	end
	if t < f.GcdUntil then
		return false, "busy"
	end
	if t < f.Cooldowns[slot] then
		return false, "cooldown"
	end
	if slot == 4 and f.Ult < 100 then
		return false, "ult_not_ready"
	end
	local target = f.Opponent
	-- Distance to the target's body (a raid boss is huge, so measure to its edge).
	local distance = math.max(0, (target.Root.Position - f.Root.Position).Magnitude - (target.Reach or 0))
	if skill.Kind == "Bolt" or skill.Kind == "Breath" or skill.Kind == "Strike" then
		if distance > skill.Range then
			return false, "out_of_range"
		end
		if not lineOfSight(f, target) then
			return false, "blocked"
		end
	end

	-- Committed: start cooldowns, spend the ultimate.
	f.Cooldowns[slot] = t + skill.Cooldown
	f.GcdUntil = t + CombatConfig.GlobalCooldown
	if slot == 4 then
		f.Ult = 0
	end
	local travel = if skill.Kind == "Bolt" then distance / skill.Speed else 0
	fx("Cast", {
		Caster = f.Model,
		Target = target.Model,
		Skill = skill.Id,
		Kind = skill.Kind,
		Element = f.Element,
		Travel = travel,
		Ultimate = skill.Ultimate == true,
	})
	selfPart(f, skill)

	if skill.Kind == "Bolt" then
		if f.BotState == nil and target.BotState then
			target.BotState.IncomingAt = t + travel -- lets the practice dragon try to dodge
		end
		task.delay(travel, function()
			if match.State ~= "Fight" then
				return
			end
			if hasStatus(target, "Evade") then
				fx("Miss", { Model = target.Model, Text = "Evaded!" })
				return
			end
			if (target.Root.Position - f.Root.Position).Magnitude - (target.Reach or 0) > skill.Range * 1.5 then
				fx("Miss", { Model = target.Model, Text = "Out of reach" })
				return
			end
			if skill.Steal and now() >= target.InvulnUntil then
				steal(f, target)
			end
			resolveHit(f, target, skill, skill.Power or 0)
		end)
	elseif skill.Kind == "Breath" then
		f.ChannelUntil = t + skill.Duration
		local cosCone = math.cos(math.rad(skill.Cone))
		for i = 1, skill.Ticks do
			task.delay(skill.Duration * (i - 0.5) / skill.Ticks, function()
				if match.State ~= "Fight" or f.HP <= 0 or now() > f.ChannelUntil + 0.05 then
					return -- interrupted
				end
				local offset = target.Root.Position - f.Root.Position
				if offset.Magnitude - (target.Reach or 0) > skill.Range * 1.15 then
					return
				end
				if offset.Magnitude > 1 and f.Root.CFrame.LookVector:Dot(offset.Unit) < cosCone then
					return -- not in front
				end
				resolveHit(f, target, skill, skill.Power or 0)
			end)
		end
	elseif skill.Kind == "Strike" then
		f.LungeUntil = t + CombatConfig.StrikeWindup + 0.15
		task.delay(CombatConfig.StrikeWindup, function()
			if match.State ~= "Fight" then
				return
			end
			if (target.Root.Position - f.Root.Position).Magnitude - (target.Reach or 0) > skill.Range + 20 then
				fx("Miss", { Model = target.Model, Text = "Missed" })
				return
			end
			resolveHit(f, target, skill, skill.Power or 0)
		end)
	elseif skill.Kind == "Nova" then
		task.delay(CombatConfig.NovaWindup, function()
			if match.State ~= "Fight" then
				return
			end
			if (target.Root.Position - f.Root.Position).Magnitude - (target.Reach or 0) > skill.Radius then
				fx("Miss", { Model = target.Model, Text = "Missed" })
				return
			end
			resolveHit(f, target, skill, skill.Power or 0)
		end)
	end
	return true
end

function CombatService.Dodge(f: any): boolean
	local t = now()
	if f.Match.State ~= "Fight" or f.HP <= 0 or hasStatus(f, "Stun") or t < f.DodgeReadyAt then
		return false
	end
	f.InvulnUntil = t + CombatConfig.DodgeInvulnerable
	f.DodgeReadyAt = t + CombatConfig.DodgeCooldown
	fx("Dodge", { Model = f.Model })
	return true
end

-- Arenas ---------------------------------------------------------------------------

local function loadArenas()
	local folder = workspace:FindFirstChild("Arenas")
	if not folder then
		warn("[CombatService] Workspace.Arenas is missing: battles are off")
		return
	end
	for _, model in folder:GetChildren() do
		local center = model:GetAttribute("Center")
		local a = model:GetAttribute("SpawnA")
		local b = model:GetAttribute("SpawnB")
		if model:IsA("Model") and typeof(center) == "Vector3" and typeof(a) == "CFrame" and typeof(b) == "CFrame" then
			table.insert(arenas, { Model = model, Center = center, SpawnA = a, SpawnB = b, Busy = false })
		end
	end
	table.sort(arenas, function(x, y)
		return x.Model.Name < y.Model.Name
	end)
end

function CombatService.FreeArenas(): number
	local count = 0
	for _, arena in arenas do
		if not arena.Busy then
			count += 1
		end
	end
	return count
end

function CombatService.IsInMatch(player: Player): boolean
	return fighterByPlayer[player] ~= nil
end

-- Matches --------------------------------------------------------------------------

local function publicFighter(f: any, match: any)
	return {
		Name = f.Name,
		Species = f.Species,
		Element = f.Element,
		Level = f.Level,
		Rarity = if match.Mode == "Ranked" then nil else f.Rarity,
		MaxHP = f.Stats.MaxHP,
		Skills = f.Skills,
		Unlocked = f.Unlocked,
		Model = f.Model,
		Trophies = f.TrophiesAtStart,
	}
end

local function newFighter(match: any, side: string, entry: any)
	local level = if match.Mode == "Ranked" then CombatConfig.RankedLevel else entry.Level
	local species = DragonCatalog.Get(entry.Species) :: any
	local stats = CombatConfig.Stats(entry.Species, entry.Level, entry.Rarity, match.Mode)
	if entry.Bot then
		stats.Attack *= CombatConfig.PracticeBotAttack
	end
	return {
		Side = side,
		Player = entry.Player,
		Name = entry.Name,
		DragonId = entry.DragonId,
		Species = entry.Species,
		Element = species.Element,
		Level = level,
		RealLevel = entry.Level,
		Rarity = entry.Rarity,
		Stats = stats,
		HP = stats.MaxHP,
		Shield = 0,
		ShieldUntil = 0,
		Skills = SkillCatalog.ForSpecies(entry.Species),
		Unlocked = Leveling.SkillsUnlocked(level),
		Cooldowns = { 0, 0, 0, 0 },
		GcdUntil = 0,
		Ult = 0,
		Statuses = {},
		DodgeReadyAt = 0,
		InvulnUntil = 0,
		ChannelUntil = 0,
		LungeUntil = 0,
		SpeedMul = -1,
		Dealt = 0,
		Outside = false,
		TrophiesAtStart = entry.Trophies or 0,
		Match = match,
		Model = nil :: Model?,
		Root = nil :: BasePart?,
		BotState = nil :: any,
	}
end

local function setArenaAttributes(model: Model, arena: Arena)
	model:SetAttribute("ArenaCenter", arena.Center)
	model:SetAttribute("ArenaRadius", CombatConfig.Arena.Radius)
	model:SetAttribute("ArenaFloor", CombatConfig.Arena.Floor)
	model:SetAttribute("ArenaCeiling", CombatConfig.Arena.Ceiling)
	model:SetAttribute("InBattle", true)
end

local function sendHome(player: Player)
	local character = player.Character
	local plot = PlotService.GetPlot(player)
	local spawnPart = plot and plot:FindFirstChild("Spawn") :: BasePart?
	if character and spawnPart then
		character:PivotTo(spawnPart.CFrame + Vector3.new(0, 4, 0))
	end
end

local function cleanup(match: any)
	for _, f in match.Fighters do
		if f.Player then
			if fighterByPlayer[f.Player] == f then
				fighterByPlayer[f.Player] = nil
			end
			if f.Model and f.Player.Parent == Players then
				MountService.Release(f.Player)
				task.delay(0.1, sendHome, f.Player)
			end
		elseif f.Model then
			f.Model:Destroy()
		end
	end
	match.Arena.Busy = false
	matches[match.Id] = nil
end

local function abort(match: any, reason: string)
	match.State = "Ended"
	for _, f in match.Fighters do
		if f and f.Player then
			sendTo(f, "Queue", { Status = "Failed", Reason = reason })
		end
	end
	cleanup(match)
end

-- Rewards for one fighter. `data` may be passed while the player is leaving.
local function grant(f: any, won: boolean, match: any, data: any?)
	local player = f.Player
	if not player then
		return nil
	end
	-- Prefer the live save: data passed through a BindableEvent is only a copy.
	data = DataService.GetData(player) or data
	if not data then
		return nil
	end
	local c = data.Combat
	local rewards = { XP = 0, Levels = 0, Trophies = 0, Scales = 0, Note = nil :: string? }
	local xp = 0
	if match.Mode == "Practice" then
		if c.PracticeDay ~= today() then
			c.PracticeDay = today()
			c.PracticeRewards = 0
		end
		if c.PracticeRewards < Leveling.PracticeRewardsPerDay then
			c.PracticeRewards += 1
			xp = Leveling.BattleXP(f.RealLevel, if won then "PracticeWin" else "PracticeLoss")
		else
			rewards.Note = "Today's practice XP is used up. Come back tomorrow!"
		end
	else
		xp = Leveling.BattleXP(f.RealLevel, if won then "Win" else "Loss")
		rewards.Scales = if won then CombatConfig.Scales.Win else CombatConfig.Scales.Loss
		c.Scales += rewards.Scales
		if won then
			c.Wins += 1
		else
			c.Losses += 1
		end
	end
	if match.Mode == "Ranked" then
		if won then
			c.RankedWins += 1
		else
			c.RankedLosses += 1
		end
		local opponent = f.Opponent
		local key = if opponent.Player then tostring(opponent.Player.UserId) else "bot"
		-- Forget old days so the table stays small.
		for k, pair in c.RankedPairs do
			if pair.Day ~= today() then
				c.RankedPairs[k] = nil
			end
		end
		local pair = c.RankedPairs[key] or { Day = today(), Count = 0 }
		c.RankedPairs[key] = pair
		if pair.Count < CombatConfig.Trophy.SameOpponentPerDay then
			pair.Count += 1
			local change = CombatConfig.TrophyChange(f.TrophiesAtStart, opponent.TrophiesAtStart, won)
			local before = c.Trophies
			c.Trophies = math.max(0, c.Trophies + change)
			c.BestTrophies = math.max(c.BestTrophies, c.Trophies)
			rewards.Trophies = c.Trophies - before
		else
			rewards.Note = "No trophies: you've already fought this player 3 times today."
		end
	end
	if xp > 0 and f.DragonId and data.Dragons[f.DragonId] then
		local dragon = data.Dragons[f.DragonId]
		local before = dragon.Level
		Leveling.AddXP(dragon, xp)
		rewards.XP = xp
		rewards.Levels = dragon.Level - before
		rewards.Level = dragon.Level
	end
	rewards.TrophyTotal = c.Trophies
	changed:Fire(player)
	return rewards
end

endMatch = function(match: any, winner: any, reason: string, leavingData: any?)
	if match.State == "Ended" then
		return
	end
	match.State = "Ended"
	local duration = now() - (match.FightAt or now())
	for _, f in match.Fighters do
		local won = f == winner
		local rewards = grant(f, won, match, if f.Player and leavingData and leavingData.Player == f.Player then leavingData.Data else nil)
		sendTo(f, "MatchEnd", {
			Won = won,
			Reason = reason,
			Mode = match.Mode,
			Rewards = rewards,
			Duration = math.floor(duration),
			FoeName = f.Opponent.Name,
		})
		if f.Model and f.Model.Parent then
			f.Model:SetAttribute("InBattle", nil)
			f.Model:SetAttribute("SpeedMul", nil)
		end
	end
	fx("MatchEnd", { Winner = winner and winner.Model })
	local loser = if winner == match.A then match.B else match.A
	local line = string.format("[Combat] %s match %d: %s (%s L%d) beat %s (%s L%d) by %s in %ds",
		match.Mode, match.Id, winner.Name, winner.Species, winner.Level, loser.Name, loser.Species, loser.Level, reason, math.floor(duration))
	print(line)
	if match.Mode ~= "Practice" and duration < CombatConfig.SuspiciousShortMatch then
		warn("[Combat] SUSPICIOUS short match:", line)
	end
	task.delay(CombatConfig.ResultsTime, cleanup, match)
end

-- Co-op raids -----------------------------------------------------------------------

local function alivePlayers(match: any): { any }
	local list = {}
	for _, f in match.Fighters do
		if f.Player and not f.Down and not f.Gone and f.Root and f.Root.Parent then
			table.insert(list, f)
		end
	end
	return list
end

local endRaid: (match: any, won: boolean, reason: string) -> ()

-- A raider who left the game or lost their dragon: out of this raid, no rewards.
local function markGone(f: any)
	if f.Gone then
		return
	end
	f.Gone = true
	f.Down = false
	f.HP = 0
	local player = f.Player
	if player and fighterByPlayer[player] == f then
		fighterByPlayer[player] = nil
		if player.Parent == Players then
			MountService.Release(player)
			task.delay(0.1, sendHome, player)
		end
	end
	local match = f.Match
	if match.State ~= "Ended" then
		local anyone = false
		for _, other in match.Fighters do
			if other.Player and not other.Gone then
				anyone = true
			end
		end
		if not anyone then
			endRaid(match, false, "Abandoned")
		end
	end
end

onZeroHealth = function(target: any)
	local match = target.Match
	if match.Kind ~= "Raid" then
		endMatch(match, target.Opponent, "KO")
		return
	end
	if target.IsBoss then
		endRaid(match, true, "Cleared")
		return
	end
	if target.Down or target.Gone then
		return
	end
	-- Downed: sit out for a few seconds, then come back with some health.
	target.Down = true
	target.DownUntil = now() + RaidConfig.ReviveTime
	target.Statuses = {}
	target.Shield = 0
	target.ChannelUntil = 0
	target.SpeedMul = 0.35
	if target.Model and target.Model.Parent then
		target.Model:SetAttribute("SpeedMul", 0.35)
	end
	fx("Down", { Model = target.Model })
	sendTo(target, "Down", RaidConfig.ReviveTime)
	if #alivePlayers(match) == 0 then
		if (match.SoloRevives or 0) > 0 then
			match.SoloRevives -= 1
			sendBoth(match, "Announce", string.format("Revives left: %d", match.SoloRevives))
		else
			endRaid(match, false, "Wiped")
		end
	end
end

local function revive(f: any)
	f.Down = false
	f.HP = f.Stats.MaxHP * RaidConfig.ReviveHealth
	f.SpeedMul = -1
	updateSpeed(f)
	f.InvulnUntil = now() + 1.5
	fx("Revive", { Model = f.Model })
	sendTo(f, "Revive")
end

-- A boss attack landing on a raider. Dodging (and Evade, for orbs) avoids it.
local function bossHit(boss: any, target: any, power: number, extraEffects: { any }?, evadable: boolean)
	if boss.Match.State ~= "Fight" or target.Down or target.Gone or target.HP <= 0 then
		return
	end
	if now() < target.InvulnUntil or (evadable and hasStatus(target, "Evade")) then
		fx("Miss", { Model = target.Model, Text = "Dodged!" })
		return
	end
	local amount = CombatConfig.Damage(power, attackOf(boss), defenseOf(target), boss.Element, target.Element)
	local mult = Elements.GetDamageMultiplier(boss.Element, target.Element)
	local kind = if mult > 1 then "Strong" elseif mult < 1 then "Weak" else "Normal"
	local dealt = hurt(target, amount, boss, kind)
	if dealt > 0 and target.HP > 0 and not target.Down then
		local effects = {}
		local elementEffect = RaidConfig.ElementEffect[boss.Element]
		if elementEffect then
			table.insert(effects, elementEffect)
		end
		for _, e in extraEffects or {} do
			table.insert(effects, e)
		end
		applyEffects(boss, target, effects)
	end
end

-- What RaidBoss is allowed to do.
local raidApi = {
	Alive = alivePlayers,
	Fighting = function(match: any): boolean
		return match.State == "Fight"
	end,
	BossHit = bossHit,
	Telegraph = function(payload: any)
		fx("Telegraph", payload)
	end,
	Fx = fx,
	Shield = function(f: any, share: number, seconds: number)
		f.Shield = math.max(f.Shield, f.Stats.MaxHP * share)
		f.ShieldUntil = math.max(f.ShieldUntil, now() + seconds)
		fx("Shield", { Model = f.Model, Until = seconds })
	end,
	Empower = function(f: any, value: number, seconds: number)
		applyEffects(f, f, { { Status = "Empower", Duration = seconds, Value = value } })
	end,
	Announce = function(match: any, text: string)
		sendBoth(match, "Announce", text)
	end,
	Stunned = function(f: any): boolean
		return hasStatus(f, "Stun")
	end,
}

-- Raid rewards, shared by the whole party (limited per day).
local function grantRaid(f: any, won: boolean, partySize: number)
	local player = f.Player
	local data = player and DataService.GetData(player)
	if not data then
		return nil
	end
	local c = data.Combat
	local rewards = { XP = 0, Levels = 0, Scales = 0, Relics = 0, Trophies = 0, Note = nil :: string? }
	if c.RaidDay ~= today() then
		c.RaidDay = today()
		c.RaidRewards = 0
	end
	if won then
		c.RaidClears += 1
	end
	if c.RaidRewards >= Leveling.RaidRewardsPerDay then
		rewards.Note = "Today's raid rewards are used up. Come back tomorrow!"
		changed:Fire(player)
		return rewards
	end
	c.RaidRewards += 1
	local r = if won then RaidConfig.Rewards.Win else RaidConfig.Rewards.Loss
	rewards.Scales = r.Scales
	rewards.Relics = r.Relics + r.RelicsPerExtraPlayer * math.max(0, partySize - 1)
	c.Scales += rewards.Scales
	c.Relics += rewards.Relics
	local xp = Leveling.BattleXP(f.RealLevel, if won then "RaidWin" else "RaidLoss")
	local dragon = f.DragonId and data.Dragons[f.DragonId]
	if xp > 0 and dragon then
		local before = dragon.Level
		Leveling.AddXP(dragon, xp)
		rewards.XP = xp
		rewards.Levels = dragon.Level - before
		rewards.Level = dragon.Level
	end
	changed:Fire(player)
	return rewards
end

endRaid = function(match: any, won: boolean, reason: string)
	if match.State == "Ended" then
		return
	end
	match.State = "Ended"
	local duration = now() - (match.FightAt or now())
	local party = 0
	for _, f in match.Fighters do
		if f.Player and not f.Gone then
			party += 1
		end
	end
	for _, f in match.Fighters do
		if f.Player and not f.Gone then
			sendTo(f, "MatchEnd", {
				Won = won,
				Reason = reason,
				Mode = "Raid",
				Rewards = grantRaid(f, won, party),
				Duration = math.floor(duration),
				FoeName = match.Boss.Name,
			})
		end
		if f.Model and f.Model.Parent then
			f.Model:SetAttribute("InBattle", nil)
			f.Model:SetAttribute("SpeedMul", nil)
		end
	end
	fx("MatchEnd", { Winner = if won then nil else match.Boss.Model })
	print(string.format("[Combat] Raid %d vs %s: %s (%s) with %d players in %ds", match.Id, match.Boss.Name,
		if won then "cleared" else "failed", reason, party, math.floor(duration)))
	task.delay(CombatConfig.ResultsTime, cleanup, match)
end

-- Starts a raid for 1-4 entries { Player, DragonId }. Returns true if it started.
function CombatService.StartRaid(entries: { any }): boolean
	local arena: Arena? = nil
	for _, a in arenas do
		if not a.Busy then
			arena = a
			break
		end
	end
	if not arena or #entries == 0 or #entries > RaidConfig.MaxParty then
		return false
	end
	for _, entry in entries do
		local data = DataService.GetData(entry.Player)
		local dragon = data and data.Dragons[entry.DragonId]
		if not dragon or fighterByPlayer[entry.Player] then
			return false
		end
		entry.Species = dragon.Species
		entry.Level = dragon.Level or 1
		entry.Rarity = dragon.Rarity
		entry.Name = entry.Player.DisplayName
	end

	local bossInfo = RaidConfig.Today()
	arena.Busy = true
	nextMatchId += 1
	local match: any = { Id = nextMatchId, Mode = "Raid", Kind = "Raid", Arena = arena, State = "Starting", Fighters = {} }
	local players = {}
	for i, entry in entries do
		local f = newFighter(match, "P" .. i, entry)
		table.insert(players, f)
		table.insert(match.Fighters, f)
	end

	-- The boss is built from the party's average dragon.
	local hp, attack, defense, level = 0, 0, 0, 0
	for _, f in players do
		hp += f.Stats.MaxHP
		attack += f.Stats.Attack
		defense += f.Stats.Defense
		level += f.RealLevel
	end
	local n = #players
	match.SoloRevives = if n == 1 then RaidConfig.SoloRevives else 0
	local boss = newFighter(match, "Boss", { Species = bossInfo.Species, Level = math.floor(level / n), Rarity = "Common", Name = bossInfo.Name })
	boss.IsBoss = true
	boss.Rarity = nil
	boss.Stats = {
		MaxHP = math.floor(hp / n * RaidConfig.BossHPPerPlayer * n),
		Attack = attack / n * RaidConfig.BossAttack,
		Defense = defense / n,
		Speed = 1,
	}
	boss.HP = boss.Stats.MaxHP
	boss.Unlocked = 0
	boss.Opponent = players[1]
	for _, f in players do
		f.Opponent = boss
	end
	match.Boss = boss
	table.insert(match.Fighters, boss)
	matches[match.Id] = match

	local c = arena.Center
	for i, f in players do
		local angle = (i - 1) * math.pi / 2 + math.pi
		local position = c + Vector3.new(math.cos(angle) * 130, 15, math.sin(angle) * 130)
		fighterByPlayer[f.Player] = f
		local result = MountService.SummonAt(f.Player, f.DragonId, { CFrame = CFrame.lookAt(position, Vector3.new(c.X, position.Y, c.Z)), Locked = true })
		if not result.ok then
			abort(match, result.error or "summon_failed")
			return false
		end
		f.Model = result.model
		f.Root = (f.Model :: Model).PrimaryPart
		setArenaAttributes(f.Model :: Model, arena)
		updateSpeed(f)
	end
	boss.Model = RaidBoss.Spawn(bossInfo.Species, boss.Level, c)
	if not boss.Model then
		abort(match, "summon_failed")
		return false
	end
	boss.Root = (boss.Model :: Model).PrimaryPart
	boss.Reach = (boss.Model:GetAttribute("Length") or 90) * 0.35
	boss.BossState = RaidBoss.NewState(boss.Model)
	setArenaAttributes(boss.Model, arena)
	updateSpeed(boss)

	match.State = "Countdown"
	match.FightAt = now() + CombatConfig.Countdown
	match.EndsAt = match.FightAt + RaidConfig.Duration
	local names = {}
	for _, f in players do
		table.insert(names, f.Name)
	end
	for _, f in players do
		sendTo(f, "MatchStart", {
			Id = match.Id,
			Mode = "Raid",
			You = publicFighter(f, match),
			Foe = publicFighter(boss, match),
			Party = names,
			Countdown = CombatConfig.Countdown,
			Duration = RaidConfig.Duration,
		})
	end
	task.delay(CombatConfig.Countdown, function()
		if match.State == "Countdown" then
			match.State = "Fight"
			sendBoth(match, "Fight")
		end
	end)
	return true
end

-- Starts a match. Each entry: { Player, DragonId } or { Bot = true, Species, Level }.
-- Returns true if it started.
function CombatService.StartMatch(mode: string, entryA: any, entryB: any): boolean
	local arena: Arena? = nil
	for _, a in arenas do
		if not a.Busy then
			arena = a
			break
		end
	end
	if not arena then
		return false
	end

	-- Read both dragons from the saves.
	for _, entry in { entryA, entryB } do
		if entry.Player then
			local data = DataService.GetData(entry.Player)
			local dragon = data and data.Dragons[entry.DragonId]
			if not dragon or fighterByPlayer[entry.Player] then
				return false
			end
			entry.Species = dragon.Species
			entry.Level = dragon.Level or 1
			entry.Rarity = dragon.Rarity
			entry.Trophies = data.Combat.Trophies
			entry.Name = entry.Player.DisplayName
		else
			entry.Rarity = "Common"
			entry.Name = "Sparring " .. ((DragonCatalog.Get(entry.Species) :: any).Name)
		end
	end

	arena.Busy = true
	nextMatchId += 1
	local match: any = { Id = nextMatchId, Mode = mode, Kind = "Duel", Arena = arena, State = "Starting" }
	match.A = newFighter(match, "A", entryA)
	match.B = newFighter(match, "B", entryB)
	match.A.Opponent = match.B
	match.B.Opponent = match.A
	match.Fighters = { match.A, match.B }
	matches[match.Id] = match

	for _, pair in { { match.A, entryA, arena.SpawnA }, { match.B, entryB, arena.SpawnB } } do
		local f, entry, place = pair[1], pair[2], pair[3]
		if entry.Player then
			fighterByPlayer[entry.Player] = f
			local result = MountService.SummonAt(entry.Player, entry.DragonId, { CFrame = place, Locked = true })
			if not result.ok then
				abort(match, result.error or "summon_failed")
				return false
			end
			f.Model = result.model
		else
			f.Model = PracticeBot.Spawn(entry, place)
			if not f.Model then
				abort(match, "summon_failed")
				return false
			end
			f.BotState = PracticeBot.NewState(f.Model)
		end
		f.Root = (f.Model :: Model).PrimaryPart
		setArenaAttributes(f.Model :: Model, arena)
		updateSpeed(f)
	end

	match.State = "Countdown"
	match.FightAt = now() + CombatConfig.Countdown
	match.EndsAt = match.FightAt + CombatConfig.MatchDuration
	for _, f in { match.A, match.B } do
		sendTo(f, "MatchStart", {
			Id = match.Id,
			Mode = mode,
			You = publicFighter(f, match),
			Foe = publicFighter(f.Opponent, match),
			Countdown = CombatConfig.Countdown,
			Duration = CombatConfig.MatchDuration,
		})
	end
	task.delay(CombatConfig.Countdown, function()
		if match.State == "Countdown" then
			match.State = "Fight"
			sendBoth(match, "Fight")
		end
	end)
	return true
end

-- The 10-per-second match loop -----------------------------------------------------

local function fighterUpdate(f: any)
	local t = now()
	return {
		HP = math.floor(f.HP + 0.5),
		Shield = if t < f.ShieldUntil then math.floor(f.Shield + 0.5) else 0,
		Ult = math.floor(f.Ult),
		Statuses = statusList(f),
	}
end

local function tickFighter(f: any, dt: number)
	local match = f.Match
	local t = now()
	if f.Gone then
		return
	end
	if not f.Model or not f.Model.Parent or not f.Root then
		if match.Kind == "Raid" then
			if f.IsBoss then
				endRaid(match, false, "Error")
			else
				markGone(f)
			end
		else
			endMatch(match, f.Opponent, "Forfeit")
		end
		return
	end
	if f.Down then
		if t >= f.DownUntil then
			revive(f)
		end
		return
	end
	-- Damage and healing over time
	local burn = f.Statuses.Burn
	if burn and burn.Until > t then
		hurt(f, burn.Dps * dt, burn.Source, nil)
	end
	local regen = f.Statuses.Regen
	if regen and regen.Until > t then
		f.HP = math.min(f.Stats.MaxHP, f.HP + f.Stats.MaxHP * (regen.Value or 0) * dt)
	end
	-- Expire effects and shields
	local expired = false
	for name, s in f.Statuses do
		if s.Until <= t then
			f.Statuses[name] = nil
			expired = true
		end
	end
	if expired then
		updateSpeed(f)
	end
	if f.Shield > 0 and t >= f.ShieldUntil then
		f.Shield = 0
	end
	addUlt(f, CombatConfig.UltPerSecond * dt)
	-- Arena walls: outside hurts.
	local offset = f.Root.Position - match.Arena.Center
	local flat = Vector3.new(offset.X, 0, offset.Z).Magnitude
	local A = CombatConfig.Arena
	local outside = not f.IsBoss and (flat > A.Radius or offset.Y < A.Floor or offset.Y > A.Ceiling)
	if outside then
		if not f.Outside then
			sendTo(f, "Warn", "Get back inside the arena!")
		end
		hurt(f, f.Stats.MaxHP * A.OutsideDamage * dt, nil, nil)
	end
	f.Outside = outside
end

local updateClock = 0
local function tick(dt: number)
	updateClock += dt
	local sendUpdates = updateClock >= UPDATE_EVERY
	if sendUpdates then
		updateClock = 0
	end
	local t = now()
	for _, match in matches do
		if match.State == "Fight" then
			for _, f in match.Fighters do
				if match.State == "Fight" then
					tickFighter(f, dt)
				end
			end
			if match.State == "Fight" and t >= match.EndsAt and match.Kind == "Raid" then
				endRaid(match, false, "Time")
			elseif match.State == "Fight" and t >= match.EndsAt then
				-- Time's up: the higher health share wins (ties go to more damage dealt).
				local a, b = match.A, match.B
				local ra, rb = a.HP / a.Stats.MaxHP, b.HP / b.Stats.MaxHP
				local winner = if ra > rb then a elseif rb > ra then b elseif a.Dealt >= b.Dealt then a else b
				endMatch(match, winner, "Time")
			end
		end
		if match.State == "Fight" or match.State == "Countdown" then
			local fighting = match.State == "Fight"
			for _, f in match.Fighters do
				if f.Model and f.Model.Parent then
					if f.BotState then
						PracticeBot.Think(f, dt, fighting, CombatService)
					elseif f.BossState then
						RaidBoss.Think(f, dt, fighting, raidApi)
					end
				end
			end
		end
		if sendUpdates and match.State ~= "Ended" then
			local duration = if match.Kind == "Raid" then RaidConfig.Duration else CombatConfig.MatchDuration
			local timeLeft = if match.State == "Countdown" then duration else math.max(0, match.EndsAt - t)
			local party = nil
			if match.Kind == "Raid" then
				party = {}
				for _, p in match.Fighters do
					if p.Player then
						table.insert(party, { Name = p.Name, HP = math.floor(p.HP + 0.5), MaxHP = p.Stats.MaxHP, Down = p.Down == true, Gone = p.Gone == true })
					end
				end
			end
			for _, f in match.Fighters do
				if f.Player and not f.Gone then
					local cooldowns = {}
					for slot = 1, 4 do
						cooldowns[slot] = math.max(0, f.Cooldowns[slot] - t)
					end
					sendTo(f, "Update", {
						Time = timeLeft,
						You = fighterUpdate(f),
						Foe = fighterUpdate(f.Opponent),
						Cooldowns = cooldowns,
						Dodge = math.max(0, f.DodgeReadyAt - t),
						Busy = math.max(0, f.ChannelUntil - t, f.GcdUntil - t),
						Party = party,
						Down = if f.Down then math.max(0, f.DownUntil - t) else nil,
					})
				end
			end
		end
	end
end

-- Player input ---------------------------------------------------------------------

local function onInput(player: Player, kind: any, slot: any)
	if not inputLimiter:Allow(player) then
		return
	end
	local f = fighterByPlayer[player]
	if not f then
		return
	end
	if kind == "Skill" then
		local ok, reason = CombatService.UseSkill(f, slot)
		if not ok and type(slot) == "number" then
			sendTo(f, "Denied", math.clamp(math.floor(slot), 1, 4), reason)
		end
	elseif kind == "Dodge" then
		CombatService.Dodge(f)
	end
end

-- A player who leaves (or loses their dragon) mid-fight forfeits.
function CombatService.Forfeit(player: Player, data: any?)
	local f = fighterByPlayer[player]
	if f and f.Match.State ~= "Ended" then
		if f.Match.Kind == "Raid" then
			markGone(f)
		else
			endMatch(f.Match, f.Opponent, "Forfeit", if data then { Player = player, Data = data } else nil)
		end
	end
end

function CombatService.SendQueueStatus(player: Player, status: any)
	if player.Parent == Players then
		combatRemote:FireClient(player, "Queue", status)
	end
end

function CombatService.init()
	loadArenas()
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	combatRemote = Instance.new("RemoteEvent")
	combatRemote.Name = "Combat"
	combatRemote.Parent = remotes
	combatRemote.OnServerEvent:Connect(onInput)

	DataService.ProfileReleasing:Connect(function(player: Player, data: any)
		CombatService.Forfeit(player, data)
	end)
	Players.PlayerRemoving:Connect(function(player)
		CombatService.Forfeit(player)
		fighterByPlayer[player] = nil
	end)
	MountService.Removed:Connect(function(player: Player, model: Model)
		local f = fighterByPlayer[player]
		if f and f.Model == model and f.Match.State ~= "Ended" then
			if f.Match.Kind == "Raid" then
				markGone(f)
			else
				endMatch(f.Match, f.Opponent, "Forfeit")
			end
		end
	end)

	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc < TICK then
			return
		end
		local step = acc
		acc = 0
		local ok, err = pcall(tick, step)
		if not ok then
			warn("[CombatService] tick failed:", err)
		end
	end)
end

return CombatService
