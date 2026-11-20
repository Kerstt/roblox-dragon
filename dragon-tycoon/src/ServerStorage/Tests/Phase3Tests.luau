-- ServerStorage/Tests/Phase3Tests
-- Pure tests for leveling, combat math, skill data and fairness rules.
-- Run from the command bar: print(require(game.ServerStorage.Tests.Phase3Tests).run())

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared

local Leveling = require(Shared.Leveling)
local CombatConfig = require(Shared.CombatConfig)
local SkillCatalog = require(Shared.SkillCatalog)
local DragonCatalog = require(Shared.DragonCatalog)
local Rarities = require(Shared.Rarities)
local RaidConfig = require(Shared.RaidConfig)
local Elements = require(Shared.Elements)

local Phase3Tests = {}

local SPECIES = { "Cindermaw", "Pyrelance", "Briarhorn", "Sylvenreach", "Tidewhelp", "Deepkeel", "Quarrytusk", "Faultcrown",
	"Squallwing", "Thunderquill", "Rimeclaw", "Frostveil", "Dawnwarden", "Solhallow", "Duskrend", "Gloamveil" }

function Phase3Tests.run(): string
	local passed, failed = 0, 0
	local lines = {}
	local function check(name: string, ok: boolean, detail: any?)
		if ok then
			passed += 1
		else
			failed += 1
			table.insert(lines, "FAIL " .. name .. (if detail ~= nil then ": " .. tostring(detail) else ""))
		end
	end

	-- Leveling ----------------------------------------------------------------
	check("xp curve rises", Leveling.XPToNext(1) < Leveling.XPToNext(10) and Leveling.XPToNext(10) < Leveling.XPToNext(49))
	check("no xp past max", Leveling.XPToNext(Leveling.MaxLevel) == nil)
	check("feed cost rises", Leveling.FeedCost(1) < Leveling.FeedCost(30))
	check("no feed at max", Leveling.FeedCost(Leveling.MaxLevel) == nil)
	local d = { Level = 1, XP = 0 }
	check("add xp levels up", Leveling.AddXP(d, Leveling.XPToNext(1)) == 1 and d.Level == 2 and d.XP == 0, d.Level)
	local d2 = { Level = 1, XP = 0 }
	local big = 0
	for l = 1, 9 do
		big += Leveling.XPToNext(l)
	end
	check("add xp multi-level", Leveling.AddXP(d2, big + 5) == 9 and d2.Level == 10 and d2.XP == 5, d2.Level)
	local d3 = { Level = 49, XP = 0 }
	Leveling.AddXP(d3, 10 ^ 9)
	check("xp caps at max level", d3.Level == Leveling.MaxLevel and d3.XP == 0, d3.Level)
	check("bad xp ignored", Leveling.AddXP({ Level = 1, XP = 0 }, -5) == 0 and Leveling.AddXP({ Level = 1, XP = 0 }, 0 / 0) == 0)
	check("skills by level", Leveling.SkillsUnlocked(1) == 1 and Leveling.SkillsUnlocked(9) == 1 and Leveling.SkillsUnlocked(10) == 2
		and Leveling.SkillsUnlocked(29) == 3 and Leveling.SkillsUnlocked(30) == 4)
	check("ranked level opens all skills", Leveling.SkillsUnlocked(CombatConfig.RankedLevel) == 4)
	local infuse = Leveling.InfuseCost({ Level = 5, XP = 0 })
	check("infuse finishes level", infuse ~= nil and infuse * Leveling.EssenceXP >= Leveling.XPToNext(5), infuse)
	check("battle xp win > loss", Leveling.BattleXP(10, "Win") > Leveling.BattleXP(10, "Loss"))
	check("practice xp < pvp xp", Leveling.BattleXP(10, "PracticeWin") < Leveling.BattleXP(10, "Win"))

	-- Skills ------------------------------------------------------------------
	local problems = SkillCatalog.Validate(SPECIES)
	check("skill data valid", #problems == 0, table.concat(problems, "; "))
	for _, id in SPECIES do
		check("species exists " .. id, DragonCatalog.Get(id) ~= nil)
		check("archetype " .. id, CombatConfig.Archetypes[CombatConfig.SpeciesArchetype[id] or ""] ~= nil)
	end
	-- every element's two dragons have different roles
	local byElement = {}
	for _, id in SPECIES do
		local element = (DragonCatalog.Get(id) :: any).Element
		byElement[element] = byElement[element] or {}
		table.insert(byElement[element], CombatConfig.SpeciesArchetype[id])
	end
	for element, roles in byElement do
		check("roles differ in " .. element, #roles == 2 and roles[1] ~= roles[2], table.concat(roles, ","))
	end

	-- Fairness ----------------------------------------------------------------
	local common = CombatConfig.Stats("Cindermaw", 20, "Common")
	local mythic = CombatConfig.Stats("Cindermaw", 20, "Mythic")
	check("rarity bonus is small", mythic.Attack / common.Attack <= 1.25 + 1e-9, mythic.Attack / common.Attack)
	local r1 = CombatConfig.Stats("Cindermaw", 2, "Common", "Ranked")
	local r2 = CombatConfig.Stats("Cindermaw", 50, "Mythic", "Ranked")
	check("ranked normalizes level and rarity", r1.MaxHP == r2.MaxHP and r1.Attack == r2.Attack)
	check("level raises stats", CombatConfig.Stats("Briarhorn", 30, "Common").MaxHP > CombatConfig.Stats("Briarhorn", 1, "Common").MaxHP)
	local even = CombatConfig.Damage(1, 100, 100, "Fire", "Earth")
	check("even damage = base", math.abs(even - CombatConfig.BaseDamage) < 1e-6, even)
	check("element advantage", CombatConfig.Damage(1, 100, 100, "Fire", "Nature") > even and CombatConfig.Damage(1, 100, 100, "Fire", "Water") < even)
	check("damage never negative", CombatConfig.Damage(1, 100, 0, "Fire", "Fire") > 0)
	check("power ignores egg power", CombatConfig.Power(10, "Rare") == CombatConfig.Power(10, "Rare"))
	check("power grows with level", CombatConfig.Power(20, "Common") > CombatConfig.Power(10, "Common"))
	for _, rarity in Rarities.Order do
		check("pvp multiplier capped " .. rarity, Rarities.Info[rarity].PvpMultiplier <= 1.25)
	end

	-- A fight between equal dragons lasts a sensible time (rough DPS model)
	local stats = CombatConfig.Stats("Cindermaw", 30, "Common")
	local dps = 0
	for slot = 1, 3 do
		local skill = SkillCatalog.Get(SkillCatalog.ForSpecies("Cindermaw")[slot]) :: any
		local power = (skill.Power or 0) * (skill.Ticks or 1)
		dps += power * CombatConfig.BaseDamage / skill.Cooldown
	end
	local ttk = stats.MaxHP / dps
	check("time to win 20-120s", ttk > 20 and ttk < 120, ttk)

	-- Trophies ----------------------------------------------------------------
	check("even win", CombatConfig.TrophyChange(1000, 1000, true) == CombatConfig.Trophy.Base)
	check("even loss", CombatConfig.TrophyChange(1000, 1000, false) == -CombatConfig.Trophy.Base)
	check("beating stronger gives more", CombatConfig.TrophyChange(1000, 1300, true) > CombatConfig.TrophyChange(1000, 700, true))
	check("losing to weaker costs more", CombatConfig.TrophyChange(1000, 700, false) < CombatConfig.TrophyChange(1000, 1300, false))
	check("trophy change clamped", CombatConfig.TrophyChange(0, 100000, true) == CombatConfig.Trophy.Max
		and CombatConfig.TrophyChange(100000, 0, true) == CombatConfig.Trophy.Min)

	-- Raids ------------------------------------------------------------------
	check("8 raid bosses", #RaidConfig.Bosses == 8, #RaidConfig.Bosses)
	local bossElements = {}
	for _, boss in RaidConfig.Bosses do
		local species = DragonCatalog.Get(boss.Species)
		check("boss species exists " .. boss.Species, species ~= nil)
		if species then
			bossElements[species.Element] = true
		end
		check("boss has a name " .. boss.Species, type(boss.Name) == "string" and #boss.Name > 0)
	end
	for _, element in Elements.Order do
		check("a boss for " .. element, bossElements[element] == true)
		local effect = RaidConfig.ElementEffect[element]
		check("boss effect for " .. element, effect ~= nil and SkillCatalog.Statuses[effect.Status] ~= nil)
	end
	local seen = {}
	for day = 0, 7 do
		seen[RaidConfig.BossFor(day).Species] = true
	end
	local count = 0
	for _ in seen do
		count += 1
	end
	check("boss rotation covers all 8 in 8 days", count == 8, count)
	check("today's boss exists", RaidConfig.Today() ~= nil)
	for name, attack in RaidConfig.Attacks do
		check("attack sane " .. name, attack.Power > 0 and attack.Cooldown > 0 and attack.Weight > 0)
		if attack.Telegraph then
			check("telegraph long enough " .. name, attack.Telegraph >= 1, attack.Telegraph)
		end
	end
	check("raid win xp > loss xp", Leveling.BattleXP(20, "RaidWin") > Leveling.BattleXP(20, "RaidLoss"))
	check("party size limits", RaidConfig.MaxParty == 4 and RaidConfig.LobbyWait > 0)
	check("win rewards relics", RaidConfig.Rewards.Win.Relics > 0 and RaidConfig.Rewards.Loss.Relics == 0)

	table.insert(lines, 1, string.format("Phase 3 tests: %d passed, %d failed", passed, failed))
	return table.concat(lines, "\n")
end

return Phase3Tests
