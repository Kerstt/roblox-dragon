--!strict
-- ReplicatedStorage/Client/HatchFXConfig
-- Centralized audio IDs, particle/beam textures, timings, cluster layout, and
-- rarity/element profiles for the 3D Dragon Egg Hatching & Celebration System.
-- Swap any SoundId or Texture string at the top of this file to customize FX.

local HatchFXConfig = {}

-- ============================================================================
-- 1.Placeholder / Configurable Sound & Texture Asset IDs
-- ============================================================================

export type SoundSpec = {
	Id: string,
	Volume: number,
	Speed: number,
}

HatchFXConfig.Sounds = {
	PedestalDrop = { Id = "rbxasset://sounds/collide.wav", Volume = 0.48, Speed = 0.86 } :: SoundSpec,
	RuneIgnite = { Id = "rbxassetid://9114446852", Volume = 0.34, Speed = 1.28 } :: SoundSpec,
	EggCrack = { Id = "rbxassetid://9113959343", Volume = 0.85, Speed = 1.00 } :: SoundSpec,
	ShellShatter = { Id = "rbxassetid://9113959343", Volume = 1.00, Speed = 1.30 } :: SoundSpec,
	RevealChime = { Id = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.58, Speed = 1.04 } :: SoundSpec,
	DragonRoar = { Id = "rbxassetid://9113980319", Volume = 0.72, Speed = 0.88 } :: SoundSpec,
	EpicPillar = { Id = "rbxasset://sounds/swordlunge.wav", Volume = 0.62, Speed = 0.72 } :: SoundSpec,
	MythicThunder = { Id = "rbxassetid://9119841134", Volume = 0.68, Speed = 1.16 } :: SoundSpec,
}

-- Pitch multiplier for each of the 3 escalating stress-crack peaks
HatchFXConfig.CrackPitchSteps = { 0.92, 1.06, 1.22 }

HatchFXConfig.Textures = {
	Sparkle = "rbxasset://textures/particles/sparkles_main.dds",
	Smoke = "rbxasset://textures/particles/smoke_main.dds",
	Fire = "rbxasset://textures/particles/fire_main.dds",
	ShellChip = "rbxasset://textures/particles/sparkles_main.dds",
	LightRayBeam = "rbxasset://textures/particles/sparkles_main.dds",
	PillarBeam = "rbxasset://textures/particles/smoke_main.dds",
}

-- ============================================================================
-- 2. Sequence Stage Timings (Full ~3.2s vs Quick ~0.8s)
-- ============================================================================

HatchFXConfig.Timing = {
	-- Full Cinematic Sequence (~3.2s total)
	DropDuration = 0.50, -- 0.0s - 0.5s: Pedestal drop & Norse rune ignition
	WobbleDuration = 1.30, -- 0.5s - 1.8s: 3 escalating shakes & progressive cracks
	AnticipationDuration = 0.10, -- 1.8s - 1.9s: Pre-burst egg swell
	ShatterRevealDuration = 0.30, -- 1.9s - 2.2s: Radial shard burst + dragon hop/roar
	CelebrationHold = 1.00, -- 2.2s - 3.2s: Rarity celebration & Viking banner showcase
	BannerMaxReadSeconds = 2.60, -- Extra optional reading window (tap anytime to dismiss)
	MinSkipDelay = 0.45, -- Prevent accidental double-tap skipping instantly
	ShardLifetime = 1.50, -- Physical shell debris fade & cleanup lifetime

	-- Quick Hatch Sequence (~0.8s total)
	QuickDropDuration = 0.14,
	QuickAnticipation = 0.06,
	QuickRevealHold = 0.60,
	QuickMinSkipDelay = 0.18,
}

-- ============================================================================
-- 3. Pedestal Staging & 1-Egg / 4-Egg Cluster Coordinates
-- ============================================================================

export type SlotPose = {
	Offset: Vector3,
	YawDeg: number,
}

HatchFXConfig.SingleSlot = {
	{ Offset = Vector3.new(0, 0, 0), YawDeg = 0 },
} :: { SlotPose }

-- Curved Norse ritual arc across the 14x14 Plot.Nest.Bowl so all 4 eggs & dragons frame cleanly
HatchFXConfig.ClusterSlots = {
	{ Offset = Vector3.new(-4.05, 0, 0.85), YawDeg = 18 },
	{ Offset = Vector3.new(-1.38, 0, -0.45), YawDeg = 6 },
	{ Offset = Vector3.new(1.38, 0, -0.45), YawDeg = -6 },
	{ Offset = Vector3.new(4.05, 0, 0.85), YawDeg = -18 },
} :: { SlotPose }

HatchFXConfig.Camera = {
	BaseFOV = 70,
	PunchFOVRare = 62,
	PunchFOVMythic = 58,
	SingleDistance = 11.2,
	SingleHeight = 3.6,
	ClusterDistance = 15.6,
	ClusterHeight = 4.8,
}

-- ============================================================================
-- 4. Rarity & Element Visual Profiles
-- ============================================================================

export type RarityFXProfile = {
	Tier: number, -- 1 = Common/Uncommon, 2 = Rare/Epic, 3 = Legendary/Mythic
	ShakeScale: number,
	SparkleCount: number,
	ShardCount: number,
	PillarWidth: number,
	PillarHeight: number,
	HitstopSeconds: number,
	CrestColor: Color3,
}

HatchFXConfig.RarityProfiles = {
	Common = {
		Tier = 1,
		ShakeScale = 0.05,
		SparkleCount = 18,
		ShardCount = 7,
		PillarWidth = 0,
		PillarHeight = 0,
		HitstopSeconds = 0,
		CrestColor = Color3.fromRGB(214, 184, 132), -- Warm torchlight
	},
	Uncommon = {
		Tier = 1,
		ShakeScale = 0.07,
		SparkleCount = 24,
		ShardCount = 8,
		PillarWidth = 0,
		PillarHeight = 0,
		HitstopSeconds = 0,
		CrestColor = Color3.fromRGB(96, 214, 122), -- Emerald spark
	},
	Rare = {
		Tier = 2,
		ShakeScale = 0.11,
		SparkleCount = 34,
		ShardCount = 8,
		PillarWidth = 3.2,
		PillarHeight = 24,
		HitstopSeconds = 0,
		CrestColor = Color3.fromRGB(78, 162, 255),
	},
	Epic = {
		Tier = 2,
		ShakeScale = 0.15,
		SparkleCount = 44,
		ShardCount = 9,
		PillarWidth = 4.2,
		PillarHeight = 28,
		HitstopSeconds = 0,
		CrestColor = Color3.fromRGB(182, 102, 255),
	},
	Legendary = {
		Tier = 3,
		ShakeScale = 0.22,
		SparkleCount = 60,
		ShardCount = 10,
		PillarWidth = 5.4,
		PillarHeight = 42,
		HitstopSeconds = 0.08,
		CrestColor = Color3.fromRGB(255, 188, 52),
	},
	Mythic = {
		Tier = 3,
		ShakeScale = 0.28,
		SparkleCount = 76,
		ShardCount = 10,
		PillarWidth = 6.6,
		PillarHeight = 48,
		HitstopSeconds = 0.08,
		CrestColor = Color3.fromRGB(255, 76, 128),
	},
} :: { [string]: RarityFXProfile }

export type ElementFXProfile = {
	Primary: Color3,
	Secondary: Color3,
	RuneGlyph: string,
	Texture: string,
}

HatchFXConfig.ElementProfiles = {
	Fire = {
		Primary = Color3.fromRGB(255, 132, 46),
		Secondary = Color3.fromRGB(255, 214, 92),
		RuneGlyph = "ᚠ",
		Texture = HatchFXConfig.Textures.Fire,
	},
	Nature = {
		Primary = Color3.fromRGB(98, 204, 84),
		Secondary = Color3.fromRGB(198, 246, 142),
		RuneGlyph = "ᛒ",
		Texture = HatchFXConfig.Textures.Sparkle,
	},
	Water = {
		Primary = Color3.fromRGB(58, 164, 242),
		Secondary = Color3.fromRGB(178, 234, 255),
		RuneGlyph = "ᛚ",
		Texture = HatchFXConfig.Textures.Sparkle,
	},
	Earth = {
		Primary = Color3.fromRGB(184, 132, 74),
		Secondary = Color3.fromRGB(236, 196, 128),
		RuneGlyph = "ᛟ",
		Texture = HatchFXConfig.Textures.Smoke,
	},
	Storm = {
		Primary = Color3.fromRGB(158, 104, 255),
		Secondary = Color3.fromRGB(224, 202, 255),
		RuneGlyph = "ᚦ",
		Texture = HatchFXConfig.Textures.Sparkle,
	},
	Ice = {
		Primary = Color3.fromRGB(168, 232, 255),
		Secondary = Color3.fromRGB(240, 252, 255),
		RuneGlyph = "ᛁ",
		Texture = HatchFXConfig.Textures.Sparkle,
	},
	Light = {
		Primary = Color3.fromRGB(255, 232, 136),
		Secondary = Color3.fromRGB(255, 252, 224),
		RuneGlyph = "ᛋ",
		Texture = HatchFXConfig.Textures.Sparkle,
	},
	Shadow = {
		Primary = Color3.fromRGB(128, 72, 186),
		Secondary = Color3.fromRGB(204, 146, 255),
		RuneGlyph = "ᛉ",
		Texture = HatchFXConfig.Textures.Smoke,
	},
} :: { [string]: ElementFXProfile }

return HatchFXConfig
