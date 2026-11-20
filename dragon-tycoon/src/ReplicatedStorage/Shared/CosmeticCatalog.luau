-- ReplicatedStorage/Shared/CosmeticCatalog
-- Dragon styles bought with Robux: wing trails and auras. Looks only, never stats.
-- One trail and one aura can be worn at a time; they show on every dragon you ride.

local CosmeticCatalog = {}

export type Cosmetic = {
	Id: string,
	Name: string,
	Kind: "Trail" | "Aura",
	Colors: { Color3 }, -- start -> end
	Text: string,
}

local list: { Cosmetic } = {
	{ Id = "EmberTrail", Name = "Ember Trail", Kind = "Trail", Colors = { Color3.fromRGB(255, 200, 90), Color3.fromRGB(220, 50, 20) }, Text = "Wingtips that leave streaks of fire." },
	{ Id = "FrostTrail", Name = "Frost Trail", Kind = "Trail", Colors = { Color3.fromRGB(240, 255, 255), Color3.fromRGB(120, 200, 255) }, Text = "An icy mist trails from your wings." },
	{ Id = "StormTrail", Name = "Storm Trail", Kind = "Trail", Colors = { Color3.fromRGB(220, 200, 255), Color3.fromRGB(120, 60, 255) }, Text = "Crackling violet light behind every wingbeat." },
	{ Id = "VerdantTrail", Name = "Verdant Trail", Kind = "Trail", Colors = { Color3.fromRGB(200, 255, 160), Color3.fromRGB(40, 150, 60) }, Text = "A ribbon of living green." },
	{ Id = "GoldenTrail", Name = "Golden Trail", Kind = "Trail", Colors = { Color3.fromRGB(255, 245, 190), Color3.fromRGB(230, 160, 40) }, Text = "Gleaming gold, fit for royalty." },
	{ Id = "ShadowTrail", Name = "Shadow Trail", Kind = "Trail", Colors = { Color3.fromRGB(140, 90, 200), Color3.fromRGB(20, 10, 30) }, Text = "Smoke from the void follows you." },
	{ Id = "RoyalGlow", Name = "Royal Glow", Kind = "Aura", Colors = { Color3.fromRGB(255, 225, 140), Color3.fromRGB(255, 180, 60) }, Text = "Golden sparkles drift around your dragon." },
	{ Id = "SpiritWisps", Name = "Spirit Wisps", Kind = "Aura", Colors = { Color3.fromRGB(180, 230, 255), Color3.fromRGB(80, 160, 255) }, Text = "Little blue spirits circle your dragon." },
	{ Id = "EmberSoul", Name = "Ember Soul", Kind = "Aura", Colors = { Color3.fromRGB(255, 170, 80), Color3.fromRGB(200, 40, 20) }, Text = "Embers rise from your dragon's scales." },
	{ Id = "VoidMist", Name = "Void Mist", Kind = "Aura", Colors = { Color3.fromRGB(170, 120, 255), Color3.fromRGB(40, 10, 70) }, Text = "A dark purple haze clings to your dragon." },
}

local byId: { [string]: Cosmetic } = {}
for _, c in list do
	byId[c.Id] = c
end
CosmeticCatalog.List = list

function CosmeticCatalog.Get(id: any): Cosmetic?
	return if type(id) == "string" then byId[id] else nil
end

return CosmeticCatalog
