-- ReplicatedStorage/Shared/CombatConfig
-- Combat stats, damage math, match rules, rewards and matchmaking settings.
-- Shared so the UI can show the same numbers, but only the server decides
-- hits, damage, cooldowns and results.
--
-- Fairness rules from the plan:
--   * Rarity changes combat stats only a little (Rarities.PvpMultiplier, 1.00x-1.25x).
--   * Egg power (income) never affects combat.
--   * Ranked fights set every dragon to level 30 with no rarity bonus.
-- Numbers marked [PLACEHOLDER] are first guesses to tune after playtests.

local Shared = script.Parent
local Rarities = require(Shared.Rarities)
local Elements = require(Shared.Elements)

local CombatConfig = {}

CombatConfig.Modes = { "Casual", "Ranked", "Practice" }

-- Stats ------------------------------------------------------------------------

CombatConfig.Base = { HP = 1400, Attack = 100, Defense = 100 } -- level 1, Common [PLACEHOLDER]
CombatConfig.LevelGrowth = 0.04 -- +4% to every stat per level [PLACEHOLDER]
CombatConfig.RankedLevel = 30
CombatConfig.BaseDamage = 50 -- damage of a Power 1 skill between equal dragons [PLACEHOLDER]

-- Combat roles. Every element has two dragons with different roles.
CombatConfig.Archetypes = {
	Tank = { HP = 1.25, Attack = 0.9, Defense = 1.25, Speed = 0.92 },
	Bruiser = { HP = 1.1, Attack = 1.0, Defense = 1.1, Speed = 0.97 },
	Striker = { HP = 0.9, Attack = 1.15, Defense = 0.9, Speed = 1.08 },
	Caster = { HP = 0.95, Attack = 1.1, Defense = 0.95, Speed = 1.0 },
}

CombatConfig.SpeciesArchetype = {
	Cindermaw = "Bruiser", Pyrelance = "Striker",
	Briarhorn = "Tank", Sylvenreach = "Caster",
	Tidewhelp = "Striker", Deepkeel = "Bruiser",
	Quarrytusk = "Tank", Faultcrown = "Bruiser",
	Squallwing = "Striker", Thunderquill = "Caster",
	Rimeclaw = "Bruiser", Frostveil = "Caster",
	Dawnwarden = "Tank", Solhallow = "Caster",
	Duskrend = "Striker", Gloamveil = "Tank",
}

export type Stats = { MaxHP: number, Attack: number, Defense: number, Speed: number }

-- Combat stats for a dragon. mode = "Ranked" uses level 30 and no rarity bonus.
function CombatConfig.Stats(speciesId: string, level: number, rarity: string, mode: string?): Stats
	local arch = CombatConfig.Archetypes[CombatConfig.SpeciesArchetype[speciesId] or "Bruiser"]
	local ranked = mode == "Ranked"
	local lvl = if ranked then CombatConfig.RankedLevel else math.clamp(level or 1, 1, 50)
	local rarityInfo = Rarities.Info[rarity]
	local rarityMult = if ranked or not rarityInfo then 1 else rarityInfo.PvpMultiplier
	local growth = (1 + CombatConfig.LevelGrowth * (lvl - 1)) * rarityMult
	return {
		MaxHP = math.floor(CombatConfig.Base.HP * arch.HP * growth),
		Attack = CombatConfig.Base.Attack * arch.Attack * growth,
		Defense = CombatConfig.Base.Defense * arch.Defense * growth,
		Speed = arch.Speed,
	}
end

-- One number for matching casual fights: level growth x rarity bonus.
function CombatConfig.Power(level: number, rarity: string): number
	local rarityInfo = Rarities.Info[rarity]
	return (1 + CombatConfig.LevelGrowth * ((level or 1) - 1)) * (if rarityInfo then rarityInfo.PvpMultiplier else 1)
end

-- Damage of one hit. power = the skill's Power. No randomness: fights are fair.
function CombatConfig.Damage(power: number, attack: number, defense: number, attackerElement: string, defenderElement: string): number
	local elementMult = Elements.GetDamageMultiplier(attackerElement, defenderElement)
	return power * CombatConfig.BaseDamage * (attack / math.max(defense, 1)) * elementMult
end

-- Match rules ---------------------------------------------------------------------

CombatConfig.Countdown = 4 -- seconds before skills can be used
CombatConfig.MatchDuration = 150 -- seconds; then the higher health % wins
CombatConfig.ResultsTime = 5 -- seconds on the results screen before going home
CombatConfig.GlobalCooldown = 0.5 -- seconds between any two skills
CombatConfig.DodgeCooldown = 3
CombatConfig.DodgeInvulnerable = 0.55 -- seconds of dodge invulnerability
CombatConfig.StrikeWindup = 0.25
CombatConfig.NovaWindup = 0.35

-- Ultimate charge (0-100). [PLACEHOLDER]
CombatConfig.UltPerSecond = 1.2
CombatConfig.UltPerDamageDealt = 120 -- per 100% of the target's max HP dealt
CombatConfig.UltPerDamageTaken = 80 -- per 100% of your max HP taken

-- Arena. Offsets are relative to the arena's center.
CombatConfig.Arena = {
	Radius = 230,
	Floor = -120,
	Ceiling = 150,
	OutsideDamage = 0.06, -- of max HP per second while outside the walls
}

-- Rewards -------------------------------------------------------------------------

CombatConfig.Scales = { Win = 3, Loss = 1 } -- crafting material from Casual and Ranked
CombatConfig.Trophy = {
	Base = 30,
	Spread = 25, -- trophies difference per point of change
	Min = 10,
	Max = 50,
	SameOpponentPerDay = 3, -- ranked matches vs the same player per day that change trophies
}
CombatConfig.SuspiciousShortMatch = 20 -- seconds; shorter PvP matches get logged
CombatConfig.PracticeBotAttack = 0.8 -- the practice dragon hits a bit softer than a player [PLACEHOLDER]

-- Trophies won (positive) or lost (negative) in a ranked match.
function CombatConfig.TrophyChange(mine: number, theirs: number, won: boolean): number
	local t = CombatConfig.Trophy
	local swing = (theirs - mine) / t.Spread
	if won then
		return math.clamp(math.floor(t.Base + swing + 0.5), t.Min, t.Max)
	end
	return -math.clamp(math.floor(t.Base - swing + 0.5), t.Min, t.Max)
end

-- Matchmaking ---------------------------------------------------------------------

CombatConfig.Queue = {
	CasualWindow = 0.15, -- power difference allowed at first (15%)
	CasualWindowGrowth = 0.05, -- +5% per second waited
	RankedWindow = 100, -- trophy difference allowed at first
	RankedWindowGrowth = 20, -- per second waited
}

return CombatConfig
