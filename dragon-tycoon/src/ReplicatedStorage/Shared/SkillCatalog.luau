-- ReplicatedStorage/Shared/SkillCatalog
-- Every combat skill and each dragon's 4-skill loadout (3 skills + 1 ultimate).
-- The server reads this to resolve skills; the UI reads it to show them.
--
-- Kinds (how the server resolves them):
--   Bolt    a homing shot that travels to the target. A dodge or Evade makes it miss.
--   Breath  a channel that hits several times while the target is in front of you.
--   Strike  a melee lunge; the target must be within Range.
--   Nova    a burst around you; hits if the target is within Radius.
--   Self    shields, heals and buffs on yourself (always succeeds).
--
-- Status effects (Effects on the target, SelfEffects on the caster):
--   Burn    damage over time (Value = Power per second)
--   Chill   slowed by Value (0.3 = 30% slower)
--   Snare   slowed by Value
--   Stun    can't use skills or dodge, and flies at 25% speed
--   Weaken  Defense lowered by Value
--   Knockback pushed away (Value = push speed)
--   Haste   faster by Value
--   Empower Attack raised by Value
--   Evade   Bolts miss you
--   Regen   heals Value of max HP per second
-- Numbers are [PLACEHOLDER] first guesses to tune after playtests.

local SkillCatalog = {}

export type Effect = { Status: string, Duration: number?, Value: number? }
export type Skill = {
	Id: string,
	Name: string,
	Kind: "Bolt" | "Breath" | "Strike" | "Nova" | "Self",
	Text: string,
	Cooldown: number,
	Power: number?, -- damage (per tick for Breath)
	Range: number?, -- Bolt, Breath, Strike
	Speed: number?, -- Bolt travel speed
	Ticks: number?, -- Breath hits
	Duration: number?, -- Breath channel time
	Cone: number?, -- Breath half-angle in degrees
	Radius: number?, -- Nova
	Shield: number?, -- shield as a share of max HP
	ShieldTime: number?,
	Heal: number?, -- instant heal as a share of max HP
	Lifesteal: number?, -- share of damage healed
	ShieldBreak: boolean?, -- shatters shields and deals +25% to them
	Cleanse: boolean?, -- removes your harmful effects
	Steal: boolean?, -- removes the target's shield and buffs; you gain a shield
	Effects: { Effect }?,
	SelfEffects: { Effect }?,
	Ultimate: boolean?,
}

local list: { Skill } = {
	-- Element basics (skill 1) -------------------------------------------------
	{ Id = "EmberBolt", Name = "Ember Bolt", Kind = "Bolt", Power = 1.0, Cooldown = 2.2, Range = 140, Speed = 170,
		Effects = { { Status = "Burn", Duration = 3, Value = 0.15 } }, Text = "Hurls a fireball that sets the target burning." },
	{ Id = "ThornVolley", Name = "Thorn Volley", Kind = "Bolt", Power = 1.0, Cooldown = 2.2, Range = 130, Speed = 170,
		Effects = { { Status = "Snare", Duration = 1.5, Value = 0.2 } }, Text = "A spray of thorns that slows the target a little." },
	{ Id = "TideBolt", Name = "Tide Bolt", Kind = "Bolt", Power = 1.0, Cooldown = 2.2, Range = 140, Speed = 170,
		Effects = { { Status = "Knockback", Value = 40 } }, Text = "A crashing water orb that shoves the target back." },
	{ Id = "StoneShard", Name = "Stone Shard", Kind = "Bolt", Power = 1.15, Cooldown = 2.6, Range = 120, Speed = 150,
		Text = "A heavy stone spike. Slower, but hits harder." },
	{ Id = "SparkBolt", Name = "Spark Bolt", Kind = "Bolt", Power = 0.85, Cooldown = 1.8, Range = 150, Speed = 240,
		Text = "A fast crackling spark. Quick to recharge." },
	{ Id = "FrostShard", Name = "Frost Shard", Kind = "Bolt", Power = 0.95, Cooldown = 2.2, Range = 140, Speed = 170,
		Effects = { { Status = "Chill", Duration = 2.5, Value = 0.25 } }, Text = "An ice lance that chills and slows the target." },
	{ Id = "RadiantBolt", Name = "Radiant Bolt", Kind = "Bolt", Power = 1.0, Cooldown = 2.2, Range = 140, Speed = 190,
		Lifesteal = 0.2, Text = "A beam of light that heals you for part of the damage." },
	{ Id = "ShadowBolt", Name = "Shadow Bolt", Kind = "Bolt", Power = 1.0, Cooldown = 2.2, Range = 140, Speed = 170,
		Effects = { { Status = "Weaken", Duration = 3, Value = 0.15 } }, Text = "A bolt of darkness that weakens the target's armor." },

	-- Cindermaw (Fire bruiser) ----------------------------------------------------
	{ Id = "CinderBreath", Name = "Cinder Breath", Kind = "Breath", Power = 0.55, Ticks = 4, Duration = 1.2, Cone = 50, Range = 55, Cooldown = 7,
		Effects = { { Status = "Burn", Duration = 4, Value = 0.2 } }, Text = "Breathes a cone of fire at close range." },
	{ Id = "SmolderHide", Name = "Smolder Hide", Kind = "Self", Cooldown = 14, Shield = 0.18, ShieldTime = 5,
		SelfEffects = { { Status = "Empower", Duration = 5, Value = 0.15 } }, Text = "Hardens your hide into a shield and stokes your attack." },
	{ Id = "InfernoMaw", Name = "Inferno Maw", Kind = "Breath", Power = 1.2, Ticks = 5, Duration = 1.6, Cone = 55, Range = 70, Cooldown = 1, Ultimate = true,
		Effects = { { Status = "Burn", Duration = 6, Value = 0.3 } }, Text = "ULTIMATE. A torrent of fire that leaves the target burning." },

	-- Pyrelance (Fire striker) -----------------------------------------------------
	{ Id = "MoltenDive", Name = "Molten Dive", Kind = "Strike", Power = 2.4, Range = 45, Cooldown = 8,
		Effects = { { Status = "Burn", Duration = 3, Value = 0.15 } }, Text = "Dives into the target with burning talons." },
	{ Id = "FlareBurst", Name = "Flare Burst", Kind = "Nova", Power = 1.6, Radius = 40, Cooldown = 10,
		Effects = { { Status = "Knockback", Value = 60 } }, Text = "Explodes in flame, blasting nearby enemies away." },
	{ Id = "MeteorLance", Name = "Meteor Lance", Kind = "Strike", Power = 6.5, Range = 60, Cooldown = 1, Ultimate = true,
		Effects = { { Status = "Stun", Duration = 1.0 }, { Status = "Burn", Duration = 4, Value = 0.2 } }, Text = "ULTIMATE. Strikes like a falling meteor, stunning the target." },

	-- Briarhorn (Nature tank) ------------------------------------------------------
	{ Id = "BrambleSlam", Name = "Bramble Slam", Kind = "Nova", Power = 1.5, Radius = 40, Cooldown = 9,
		Effects = { { Status = "Snare", Duration = 3, Value = 0.45 } }, Text = "Slams the air, tangling nearby enemies in brambles." },
	{ Id = "Regrowth", Name = "Regrowth", Kind = "Self", Cooldown = 14,
		SelfEffects = { { Status = "Regen", Duration = 4, Value = 0.05 } }, Text = "Heals 20% of your health over 4 seconds." },
	{ Id = "AncientGrove", Name = "Ancient Grove", Kind = "Self", Cooldown = 1, Ultimate = true, Shield = 0.35, ShieldTime = 6, Cleanse = true,
		SelfEffects = { { Status = "Regen", Duration = 6, Value = 0.04 } }, Text = "ULTIMATE. Cleanses you, then shields and heals you." },

	-- Sylvenreach (Nature caster) --------------------------------------------------
	{ Id = "StranglingVines", Name = "Strangling Vines", Kind = "Bolt", Power = 1.2, Range = 120, Speed = 150, Cooldown = 9,
		Effects = { { Status = "Snare", Duration = 3, Value = 0.6 } }, Text = "Vines lash the target and hold it nearly still." },
	{ Id = "SapDrain", Name = "Sap Drain", Kind = "Bolt", Power = 1.6, Range = 110, Speed = 160, Cooldown = 8, Lifesteal = 0.6,
		Text = "Drains the target's life to heal you." },
	{ Id = "Overgrowth", Name = "Overgrowth", Kind = "Nova", Power = 4.5, Radius = 70, Cooldown = 1, Ultimate = true, Lifesteal = 0.4,
		Effects = { { Status = "Snare", Duration = 4, Value = 0.6 } }, Text = "ULTIMATE. A wild burst of growth that roots and drains." },

	-- Tidewhelp (Water striker) ----------------------------------------------------
	{ Id = "RiptideWave", Name = "Riptide Wave", Kind = "Nova", Power = 1.4, Radius = 45, Cooldown = 8,
		Effects = { { Status = "Knockback", Value = 90 } }, Text = "A ring of water that hurls nearby enemies away." },
	{ Id = "Slipstream", Name = "Slipstream", Kind = "Self", Cooldown = 12,
		SelfEffects = { { Status = "Haste", Duration = 4, Value = 0.4 }, { Status = "Evade", Duration = 1.5 } }, Text = "Surges forward, faster and slipping past shots." },
	{ Id = "Maelstrom", Name = "Maelstrom", Kind = "Nova", Power = 5.0, Radius = 75, Cooldown = 1, Ultimate = true,
		Effects = { { Status = "Knockback", Value = 120 }, { Status = "Snare", Duration = 2, Value = 0.5 } }, Text = "ULTIMATE. A whirlpool that crushes and flings enemies." },

	-- Deepkeel (Water bruiser) -----------------------------------------------------
	{ Id = "PressureBlast", Name = "Pressure Blast", Kind = "Bolt", Power = 2.0, Range = 120, Speed = 150, Cooldown = 8, ShieldBreak = true,
		Text = "A crushing blast that shatters shields." },
	{ Id = "KeelRam", Name = "Keel Ram", Kind = "Strike", Power = 2.2, Range = 40, Cooldown = 9,
		Effects = { { Status = "Weaken", Duration = 4, Value = 0.25 }, { Status = "Knockback", Value = 70 } }, Text = "Rams the target, cracking its armor." },
	{ Id = "AbyssalCrush", Name = "Abyssal Crush", Kind = "Bolt", Power = 6.0, Range = 150, Speed = 160, Cooldown = 1, Ultimate = true, ShieldBreak = true,
		Effects = { { Status = "Weaken", Duration = 5, Value = 0.3 } }, Text = "ULTIMATE. The weight of the deep sea. Breaks shields." },

	-- Quarrytusk (Earth tank) ------------------------------------------------------
	{ Id = "TuskCharge", Name = "Tusk Charge", Kind = "Strike", Power = 2.0, Range = 45, Cooldown = 9,
		Effects = { { Status = "Stun", Duration = 0.8 } }, Text = "Charges tusks-first, stunning the target." },
	{ Id = "RockHide", Name = "Rock Hide", Kind = "Self", Cooldown = 15, Shield = 0.25, ShieldTime = 5,
		Text = "Covers you in stone, absorbing damage." },
	{ Id = "Landslide", Name = "Landslide", Kind = "Nova", Power = 5.0, Radius = 65, Cooldown = 1, Ultimate = true,
		Effects = { { Status = "Stun", Duration = 1.6 } }, Text = "ULTIMATE. An avalanche of rock that stuns everything nearby." },

	-- Faultcrown (Earth bruiser) ---------------------------------------------------
	{ Id = "Quake", Name = "Quake", Kind = "Nova", Power = 1.7, Radius = 50, Cooldown = 9,
		Effects = { { Status = "Snare", Duration = 2.5, Value = 0.4 } }, Text = "A shockwave that staggers nearby enemies." },
	{ Id = "MagmaSpit", Name = "Magma Spit", Kind = "Bolt", Power = 1.4, Range = 120, Speed = 150, Cooldown = 7,
		Effects = { { Status = "Burn", Duration = 4, Value = 0.2 } }, Text = "Spits molten rock that keeps burning." },
	{ Id = "SunderingQuake", Name = "Sundering Quake", Kind = "Nova", Power = 5.5, Radius = 80, Cooldown = 1, Ultimate = true,
		Effects = { { Status = "Snare", Duration = 3, Value = 0.5 }, { Status = "Weaken", Duration = 4, Value = 0.2 } }, Text = "ULTIMATE. Splits the sky open around you." },

	-- Squallwing (Storm striker) ---------------------------------------------------
	{ Id = "GaleStrike", Name = "Gale Strike", Kind = "Strike", Power = 2.0, Range = 45, Cooldown = 7,
		Effects = { { Status = "Knockback", Value = 80 } }, Text = "A wing-blow wrapped in wind that sends the target flying." },
	{ Id = "Tailwind", Name = "Tailwind", Kind = "Self", Cooldown = 13,
		SelfEffects = { { Status = "Haste", Duration = 5, Value = 0.5 }, { Status = "Empower", Duration = 5, Value = 0.15 } }, Text = "Rides the storm: faster and stronger for 5 seconds." },
	{ Id = "ThunderclapDive", Name = "Thunderclap Dive", Kind = "Strike", Power = 6.0, Range = 60, Cooldown = 1, Ultimate = true,
		Effects = { { Status = "Stun", Duration = 1.2 } }, Text = "ULTIMATE. Dives with a thunderclap that stuns the target." },

	-- Thunderquill (Storm caster) --------------------------------------------------
	{ Id = "ChainLightning", Name = "Chain Lightning", Kind = "Bolt", Power = 2.2, Range = 170, Speed = 400, Cooldown = 8,
		Text = "Lightning from the quills. Very long range and fast." },
	{ Id = "StaticField", Name = "Static Field", Kind = "Nova", Power = 1.4, Radius = 55, Cooldown = 10,
		Effects = { { Status = "Stun", Duration = 0.5 }, { Status = "Snare", Duration = 2, Value = 0.3 } }, Text = "Charges the air, jolting and slowing nearby enemies." },
	{ Id = "StormSpear", Name = "Storm Spear", Kind = "Bolt", Power = 6.5, Range = 200, Speed = 350, Cooldown = 1, Ultimate = true,
		Effects = { { Status = "Stun", Duration = 1.2 } }, Text = "ULTIMATE. A spear of lightning from across the arena." },

	-- Rimeclaw (Ice bruiser) -------------------------------------------------------
	{ Id = "RimeSlash", Name = "Rime Slash", Kind = "Strike", Power = 2.0, Range = 45, Cooldown = 7,
		Effects = { { Status = "Chill", Duration = 3, Value = 0.35 } }, Text = "Frozen claws that chill the target to the bone." },
	{ Id = "FrostBreath", Name = "Frost Breath", Kind = "Breath", Power = 0.5, Ticks = 4, Duration = 1.2, Cone = 50, Range = 55, Cooldown = 8,
		Effects = { { Status = "Chill", Duration = 3, Value = 0.4 } }, Text = "Breathes freezing mist that slows the target." },
	{ Id = "GlacialPrison", Name = "Glacial Prison", Kind = "Bolt", Power = 5.0, Range = 150, Speed = 170, Cooldown = 1, Ultimate = true,
		Effects = { { Status = "Stun", Duration = 2.0 } }, Text = "ULTIMATE. Freezes the target solid for 2 seconds." },

	-- Frostveil (Ice caster) -------------------------------------------------------
	{ Id = "BlizzardVeil", Name = "Blizzard Veil", Kind = "Nova", Power = 1.3, Radius = 55, Cooldown = 9,
		Effects = { { Status = "Chill", Duration = 3, Value = 0.4 } }, SelfEffects = { { Status = "Evade", Duration = 1.5 } },
		Text = "Wraps you in snow: chills enemies nearby and hides you from shots." },
	{ Id = "MirrorIce", Name = "Mirror Ice", Kind = "Self", Cooldown = 13, Shield = 0.22, ShieldTime = 5,
		Text = "A shield of mirrored ice." },
	{ Id = "Whiteout", Name = "Whiteout", Kind = "Nova", Power = 5.0, Radius = 85, Cooldown = 1, Ultimate = true,
		Effects = { { Status = "Chill", Duration = 5, Value = 0.55 } }, Text = "ULTIMATE. A blizzard that buries everything nearby." },

	-- Dawnwarden (Light tank) ------------------------------------------------------
	{ Id = "SunAegis", Name = "Sun Aegis", Kind = "Self", Cooldown = 14, Shield = 0.25, ShieldTime = 5, Cleanse = true,
		Text = "A golden shield that also clears harmful effects." },
	{ Id = "JudgementSlam", Name = "Judgement Slam", Kind = "Nova", Power = 1.8, Radius = 45, Cooldown = 9,
		Effects = { { Status = "Stun", Duration = 0.6 } }, Text = "Slams down with radiant force, stunning nearby enemies." },
	{ Id = "Daybreak", Name = "Daybreak", Kind = "Self", Cooldown = 1, Ultimate = true, Heal = 0.3, Shield = 0.25, ShieldTime = 6, Cleanse = true,
		Text = "ULTIMATE. Dawn breaks: heals 30%, shields and cleanses you." },

	-- Solhallow (Light caster) -----------------------------------------------------
	{ Id = "Sunbeam", Name = "Sunbeam", Kind = "Breath", Power = 0.55, Ticks = 4, Duration = 1.2, Cone = 25, Range = 100, Cooldown = 7, Lifesteal = 0.2,
		Text = "A long, focused beam of sunlight that heals you a little." },
	{ Id = "SolarMend", Name = "Solar Mend", Kind = "Self", Cooldown = 13, Cleanse = true,
		SelfEffects = { { Status = "Regen", Duration = 4, Value = 0.05 } }, Text = "Clears harmful effects and heals 20% over 4 seconds." },
	{ Id = "SolarFlare", Name = "Solar Flare", Kind = "Breath", Power = 1.3, Ticks = 5, Duration = 1.6, Cone = 30, Range = 120, Cooldown = 1, Ultimate = true,
		Effects = { { Status = "Weaken", Duration = 4, Value = 0.25 } }, Text = "ULTIMATE. A blinding beam of the sun's full fury." },

	-- Duskrend (Shadow striker) ----------------------------------------------------
	{ Id = "ShadowStep", Name = "Shadow Step", Kind = "Strike", Power = 2.4, Range = 75, Cooldown = 8,
		Text = "Blinks through the shadows to strike from further away." },
	{ Id = "SmokeVeil", Name = "Smoke Veil", Kind = "Self", Cooldown = 12,
		SelfEffects = { { Status = "Evade", Duration = 2.5 }, { Status = "Haste", Duration = 3, Value = 0.3 } }, Text = "Vanishes in smoke: shots miss and you move faster." },
	{ Id = "Nightfall", Name = "Nightfall", Kind = "Strike", Power = 6.5, Range = 80, Cooldown = 1, Ultimate = true,
		Effects = { { Status = "Weaken", Duration = 5, Value = 0.3 } }, Text = "ULTIMATE. Night falls on the target in one silent strike." },

	-- Gloamveil (Shadow tank) ------------------------------------------------------
	{ Id = "SoulDrain", Name = "Soul Drain", Kind = "Breath", Power = 0.45, Ticks = 4, Duration = 1.2, Cone = 50, Range = 60, Cooldown = 8, Lifesteal = 0.7,
		Text = "Breathes out shadow that drains the target's life into you." },
	{ Id = "EclipseHex", Name = "Eclipse Hex", Kind = "Bolt", Power = 1.2, Range = 130, Speed = 170, Cooldown = 12, Steal = true,
		Text = "Steals the target's shield and buffs for yourself." },
	{ Id = "Eclipse", Name = "Eclipse", Kind = "Nova", Power = 4.5, Radius = 75, Cooldown = 1, Ultimate = true, Lifesteal = 0.5,
		Effects = { { Status = "Weaken", Duration = 5, Value = 0.3 } }, Text = "ULTIMATE. Blots out the light, draining all nearby." },
}

-- Each species: { skill 1, skill 2, skill 3, ultimate }
SkillCatalog.Loadouts = {
	Cindermaw = { "EmberBolt", "CinderBreath", "SmolderHide", "InfernoMaw" },
	Pyrelance = { "EmberBolt", "MoltenDive", "FlareBurst", "MeteorLance" },
	Briarhorn = { "ThornVolley", "BrambleSlam", "Regrowth", "AncientGrove" },
	Sylvenreach = { "ThornVolley", "StranglingVines", "SapDrain", "Overgrowth" },
	Tidewhelp = { "TideBolt", "RiptideWave", "Slipstream", "Maelstrom" },
	Deepkeel = { "TideBolt", "PressureBlast", "KeelRam", "AbyssalCrush" },
	Quarrytusk = { "StoneShard", "TuskCharge", "RockHide", "Landslide" },
	Faultcrown = { "StoneShard", "Quake", "MagmaSpit", "SunderingQuake" },
	Squallwing = { "SparkBolt", "GaleStrike", "Tailwind", "ThunderclapDive" },
	Thunderquill = { "SparkBolt", "ChainLightning", "StaticField", "StormSpear" },
	Rimeclaw = { "FrostShard", "RimeSlash", "FrostBreath", "GlacialPrison" },
	Frostveil = { "FrostShard", "BlizzardVeil", "MirrorIce", "Whiteout" },
	Dawnwarden = { "RadiantBolt", "SunAegis", "JudgementSlam", "Daybreak" },
	Solhallow = { "RadiantBolt", "Sunbeam", "SolarMend", "SolarFlare" },
	Duskrend = { "ShadowBolt", "ShadowStep", "SmokeVeil", "Nightfall" },
	Gloamveil = { "ShadowBolt", "SoulDrain", "EclipseHex", "Eclipse" },
}

SkillCatalog.Statuses = {
	Burn = { Harmful = true, Label = "Burning" },
	Chill = { Harmful = true, Label = "Chilled" },
	Snare = { Harmful = true, Label = "Snared" },
	Stun = { Harmful = true, Label = "Stunned" },
	Weaken = { Harmful = true, Label = "Weakened" },
	Knockback = { Harmful = true, Label = "Knocked back" },
	Haste = { Harmful = false, Label = "Haste" },
	Empower = { Harmful = false, Label = "Empowered" },
	Evade = { Harmful = false, Label = "Evading" },
	Regen = { Harmful = false, Label = "Regenerating" },
}

local byId: { [string]: Skill } = {}
for _, skill in list do
	byId[skill.Id] = skill
end
SkillCatalog.List = list

function SkillCatalog.Get(id: any): Skill?
	return if type(id) == "string" then byId[id] else nil
end

-- The 4 skill ids of a species (skill 1, 2, 3, ultimate).
function SkillCatalog.ForSpecies(speciesId: string): { string }?
	return SkillCatalog.Loadouts[speciesId]
end

-- Problems in the data (empty list = all good). Used by tests.
function SkillCatalog.Validate(speciesIds: { string }): { string }
	local problems = {}
	for _, speciesId in speciesIds do
		local loadout = SkillCatalog.Loadouts[speciesId]
		if not loadout or #loadout ~= 4 then
			table.insert(problems, speciesId .. ": needs exactly 4 skills")
			continue
		end
		for slot, id in loadout do
			local skill = byId[id]
			if not skill then
				table.insert(problems, speciesId .. ": unknown skill " .. id)
			elseif (slot == 4) ~= (skill.Ultimate == true) then
				table.insert(problems, speciesId .. ": slot " .. slot .. " ultimate mismatch (" .. id .. ")")
			end
		end
	end
	for _, skill in list do
		local needsRange = skill.Kind == "Bolt" or skill.Kind == "Breath" or skill.Kind == "Strike"
		if needsRange and not skill.Range then
			table.insert(problems, skill.Id .. ": missing Range")
		end
		if skill.Kind == "Bolt" and not skill.Speed then
			table.insert(problems, skill.Id .. ": missing Speed")
		end
		if skill.Kind == "Breath" and not (skill.Ticks and skill.Duration and skill.Cone) then
			table.insert(problems, skill.Id .. ": Breath needs Ticks, Duration and Cone")
		end
		if skill.Kind == "Nova" and not skill.Radius then
			table.insert(problems, skill.Id .. ": missing Radius")
		end
		for _, effects in { skill.Effects or {}, skill.SelfEffects or {} } do
			for _, e in effects do
				if not SkillCatalog.Statuses[e.Status] then
					table.insert(problems, skill.Id .. ": unknown status " .. tostring(e.Status))
				end
			end
		end
	end
	return problems
end

return SkillCatalog
