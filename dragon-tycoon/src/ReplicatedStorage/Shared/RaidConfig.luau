-- ReplicatedStorage/Shared/RaidConfig
-- Co-op raid: 1 to 4 players, each on one dragon, against today's Elder dragon.
-- The boss changes every day (one per element), so picking a dragon with the
-- element advantage matters. Every boss attack is telegraphed (a red warning
-- shape) before it lands, so good flying and dodging beats it.
-- Numbers marked [PLACEHOLDER] are first guesses to tune after playtests.

local RaidConfig = {}

RaidConfig.MaxParty = 4
RaidConfig.LobbyWait = 20 -- seconds the lobby waits for more players before starting
RaidConfig.Duration = 240 -- seconds to win
RaidConfig.ReviveTime = 8 -- seconds a downed player sits out
RaidConfig.ReviveHealth = 0.4 -- share of max HP when they come back
-- A party fails when everyone is down at once. Alone, that would be every
-- knockout, so solo raiders get this many revives first.
RaidConfig.SoloRevives = 2

-- Boss strength, from the party's average dragon. [PLACEHOLDER]
RaidConfig.BossHPPerPlayer = 2.4 -- x the average player max HP, per player
RaidConfig.BossAttack = 0.9 -- x the average player Attack
RaidConfig.BossScale = 2.6 -- model size vs a normal dragon
RaidConfig.PhaseTwoAt = 0.5 -- health share: the boss roars and gets a shield
RaidConfig.EnrageAt = 0.2 -- health share: the boss hits harder

-- One Elder per element, in rotation (day number mod 8).
RaidConfig.Bosses = {
	{ Species = "Cindermaw", Name = "Elder Cindermaw" },
	{ Species = "Briarhorn", Name = "Elder Briarhorn" },
	{ Species = "Deepkeel", Name = "Elder Deepkeel" },
	{ Species = "Faultcrown", Name = "Elder Faultcrown" },
	{ Species = "Thunderquill", Name = "Elder Thunderquill" },
	{ Species = "Rimeclaw", Name = "Elder Rimeclaw" },
	{ Species = "Dawnwarden", Name = "Elder Dawnwarden" },
	{ Species = "Gloamveil", Name = "Elder Gloamveil" },
}

-- The boss's attacks. Telegraph = warning time before it lands. [PLACEHOLDER]
RaidConfig.Attacks = {
	Breath = { Power = 3.0, Range = 130, Angle = 32, Telegraph = 1.4, Cooldown = 7, Weight = 3 },
	Orbs = { Power = 1.4, Speed = 95, Cooldown = 5, Weight = 3 },
	Slam = { Power = 3.2, Radius = 80, Telegraph = 1.5, Cooldown = 9, Weight = 2, Knockback = 120 },
	Meteors = { Power = 2.8, Radius = 26, Telegraph = 1.8, Cooldown = 8, Weight = 2 },
}
RaidConfig.AttackGap = { 1.6, 2.6 } -- seconds between attacks (shorter after phase two)

-- Extra effect each boss attack carries, by the boss's element.
RaidConfig.ElementEffect = {
	Fire = { Status = "Burn", Duration = 4, Value = 0.25 },
	Nature = { Status = "Snare", Duration = 2.5, Value = 0.45 },
	Water = { Status = "Knockback", Value = 60 },
	Earth = { Status = "Stun", Duration = 0.6 },
	Storm = { Status = "Stun", Duration = 0.4 },
	Ice = { Status = "Chill", Duration = 3, Value = 0.4 },
	Light = { Status = "Weaken", Duration = 4, Value = 0.2 },
	Shadow = { Status = "Weaken", Duration = 4, Value = 0.25 },
}

-- Rewards (shared by the whole party). Relic shards are a rare crafting material.
RaidConfig.Rewards = {
	Win = { Scales = 5, Relics = 2, RelicsPerExtraPlayer = 1 },
	Loss = { Scales = 1, Relics = 0, RelicsPerExtraPlayer = 0 },
}

function RaidConfig.BossFor(day: number)
	return RaidConfig.Bosses[(day % #RaidConfig.Bosses) + 1]
end

-- Today's boss (UTC day).
function RaidConfig.Today()
	return RaidConfig.BossFor(math.floor(os.time() / 86400))
end

return RaidConfig
