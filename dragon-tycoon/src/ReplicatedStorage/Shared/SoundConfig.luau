-- ReplicatedStorage/Shared/SoundConfig
-- Every sound in the game. Music is licensed APM Music and effects are Pro Sound
-- Effects, both provided free on the Roblox Creator Store; small UI sounds are
-- Roblox's built-in sounds. Swap an id here to change a sound everywhere.

local SoundConfig = {}

SoundConfig.Music = {
	Sanctuary = {
		{ Id = "rbxassetid://9041719248", Volume = 0.35 }, -- New Existence (calm acoustic)
		{ Id = "rbxassetid://1837597619", Volume = 0.3 }, -- Joy in Fantasyland 2
	},
	Battle = { { Id = "rbxassetid://1836104000", Volume = 0.35 } }, -- Determined Epic Theme
	Raid = { { Id = "rbxassetid://9045929119", Volume = 0.4 } }, -- Ancient Grounds
}

SoundConfig.Effects = {
	Roar = { Id = "rbxassetid://9113980319", Volume = 0.7, Speed = 0.8 },
	Wings = { Id = "rbxassetid://9113444620", Volume = 0.45, Speed = 0.55 },
	EggCrack = { Id = "rbxassetid://9113959343", Volume = 0.8, Speed = 1 },
	Coins = { Id = "rbxassetid://9113849492", Volume = 0.6, Speed = 1.1 },
	Fire = { Id = "rbxassetid://9114446852", Volume = 0.7, Speed = 1 },
	Thunder = { Id = "rbxassetid://9119841134", Volume = 0.5, Speed = 1.3 },
	Whoosh = { Id = "rbxasset://sounds/swordlunge.wav", Volume = 0.6, Speed = 0.8 },
	Slash = { Id = "rbxasset://sounds/swordslash.wav", Volume = 0.7, Speed = 0.7 },
	Hit = { Id = "rbxasset://sounds/collide.wav", Volume = 0.6, Speed = 0.8 },
	Chime = { Id = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.5, Speed = 1 },
	Click = { Id = "rbxasset://sounds/clickfast.wav", Volume = 0.25, Speed = 1 },
}

-- Which effect each element's skills use.
SoundConfig.ElementCast = {
	Fire = "Fire", Light = "Fire", Storm = "Thunder",
	Water = "Whoosh", Nature = "Whoosh", Earth = "Whoosh", Ice = "Whoosh", Shadow = "Whoosh",
}

return SoundConfig
