--!strict
-- ReplicatedStorage/Shared/DragonElementalVFX
-- Element effects placed on the dragon's anatomy, with presets per element.
--
--   Server: DragonElementalVFX.Apply(model, element, rarity, scale, mode) builds
--           every emitter, trail, beam and light once, when the model is made
--           (DragonVisuals calls it). Each piece is tagged with a "VFX" role.
--   Client: DragonElementalVFX.Bind(model) returns a handle that plays them:
--           handle:Tick(t, dt, info) every frame, handle:Event(name) for moments
--           (ChargeStart, BreathStart, BreathStop, Roar, TailBurst, Takeoff,
--           Land, Happy), handle:SetActive(on) for distance culling.
--
-- Anatomy points (attachments from DragonRigBuilder.AddAnatomyPoints):
--   Mouth_VFX   charge sparks, breath puffs, the breath stream, beam and light
--   Wing_L_Tip / Wing_R_Tip   ribbon trails and aura above TRAIL_SPEED in flight
--   Tail_Tip    ambient element trail, burst on tail whips
--   Chest_Core / Dorsal_Spines   lights that pulse with charge and roars
--   Feet_Front_L/R, Feet_Back_L/R   dust on takeoff and landing (+ a ground ring)
-- Classic models without these points still get their ambient effects.
--
-- To add an element: copy a preset below, change its colors and recipes.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Rarities = require(Shared:WaitForChild("Rarities")) :: any
local FlightConfig = require(Shared:WaitForChild("FlightConfig")) :: any

local DragonElementalVFX = {}

local SPARK = "rbxasset://textures/particles/sparkles_main.dds"
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"
local FIRE = "rbxasset://textures/particles/fire_main.dds"

-- TUNING
local TRAIL_SPEED = FlightConfig.CruiseSpeed * 0.7 -- wing trails and aura switch on above this flight speed
local RARITY_RATE = { Common = 0.35, Uncommon = 0.5, Rare = 0.75, Epic = 1, Legendary = 1.4, Mythic = 2 }

local hex = Color3.fromHex
local rgb = Color3.fromRGB

-- Emitter recipe. Sizes and speeds are for a 36-stud dragon and scale with it.
--   Where (ambient only): Wings | Aura | Mouth | Tail | Body
--   Rate = continuous particles/second; Burst = particles per one-off burst
--   Colors default to the preset's {hot, core}
export type Recipe = {
	Where: string?,
	Texture: string,
	Colors: { Color3 }?,
	Rate: number?,
	Burst: number?,
	Life: { number },
	Speed: { number },
	Size: { number },
	Light: number,
	Accel: Vector3?,
	Transparency: number?,
	Spread: number?,
	Rotation: boolean?,
	Drag: number?,
	Up: boolean?, -- emit upward (ground rings) instead of forward / all around
}

export type Preset = {
	Colors: { Color3 }, -- { hot, core }: bright centre to deep edge
	Dark: Color3, -- smoke and dust tone
	Glow: Color3,
	GlowBrightness: number,
	AlwaysGlow: boolean?,
	Ambient: { Recipe },
	Puff: { Recipe }, -- breath puffs now and then while calm
	Stream: { Recipe }, -- the breath attack
	BeamWidth: number,
	Charge: Recipe,
	WingAura: Recipe,
	TrailLight: number,
	TailTip: Recipe,
	TailBurst: Recipe,
	Ring: Recipe, -- elemental shockwave on takeoff and landing
	Arcs: boolean?, -- lightning arcs between wingtips, spines, neck and tail
}

local PRESETS: { [string]: Preset } = {
	Fire = {
		Colors = { hex("FFD000"), hex("FF6A00") },
		Dark = rgb(62, 46, 38),
		Glow = hex("FF8A1F"),
		GlowBrightness = 1,
		Ambient = {
			{ Where = "Wings", Texture = FIRE, Rate = 14, Life = { 0.6, 1.2 }, Speed = { 1, 3 }, Size = { 0.9, 0 }, Light = 1, Accel = Vector3.new(0, 6, 0), Transparency = 0.2 },
			{ Where = "Aura", Texture = SPARK, Rate = 10, Life = { 1.5, 2.5 }, Speed = { 2, 5 }, Size = { 0.6, 0 }, Light = 1, Accel = Vector3.new(0, 5, 0) }, -- rising embers
			{ Where = "Mouth", Texture = SMOKE, Colors = { rgb(80, 66, 58), rgb(30, 26, 24) }, Rate = 4, Life = { 1.5, 2.5 }, Speed = { 2, 4 }, Size = { 2, 7 }, Light = 0, Accel = Vector3.new(0, 3, 0), Transparency = 0.55 }, -- heat haze
		},
		Puff = {
			{ Texture = FIRE, Burst = 28, Life = { 0.35, 0.7 }, Speed = { 14, 22 }, Size = { 1.2, 4 }, Light = 1, Accel = Vector3.new(0, 4, 0), Spread = 14 },
			{ Texture = SMOKE, Colors = { rgb(60, 50, 45), rgb(25, 22, 20) }, Burst = 10, Life = { 1, 1.8 }, Speed = { 6, 10 }, Size = { 2, 7 }, Light = 0, Accel = Vector3.new(0, 5, 0), Transparency = 0.5, Spread = 14 },
		},
		Stream = {
			{ Texture = FIRE, Rate = 120, Life = { 0.45, 0.7 }, Speed = { 45, 60 }, Size = { 2, 9 }, Light = 1, Accel = Vector3.new(0, 6, 0), Spread = 12 },
			{ Texture = SMOKE, Colors = { rgb(70, 55, 45), rgb(25, 20, 18) }, Rate = 25, Life = { 0.8, 1.2 }, Speed = { 20, 30 }, Size = { 4, 12 }, Light = 0, Accel = Vector3.new(0, 8, 0), Transparency = 0.55, Spread = 16 },
		},
		BeamWidth = 2.2,
		Charge = { Texture = SPARK, Rate = 40, Life = { 0.3, 0.5 }, Speed = { 1, 3 }, Size = { 0.5, 1.2 }, Light = 1 },
		WingAura = { Texture = FIRE, Rate = 30, Life = { 0.3, 0.6 }, Speed = { 0, 1 }, Size = { 1, 0 }, Light = 1 },
		TrailLight = 0.9,
		TailTip = { Texture = FIRE, Rate = 8, Life = { 0.5, 1 }, Speed = { 0.5, 1.5 }, Size = { 0.8, 0 }, Light = 1, Accel = Vector3.new(0, 4, 0) },
		TailBurst = { Texture = FIRE, Burst = 40, Life = { 0.3, 0.6 }, Speed = { 10, 20 }, Size = { 1.5, 0 }, Light = 1, Spread = 180 },
		Ring = { Texture = FIRE, Burst = 36, Life = { 0.4, 0.7 }, Speed = { 14, 22 }, Size = { 1.4, 0 }, Light = 1, Up = true },
	},
	Shadow = { -- Void / Arcane
		Colors = { hex("E0AAFF"), hex("7B2CBF") },
		Dark = rgb(36, 20, 52),
		Glow = hex("9D4EDD"),
		GlowBrightness = 0.8,
		Ambient = {
			{ Where = "Wings", Texture = SMOKE, Colors = { rgb(60, 32, 90), rgb(12, 6, 20) }, Rate = 10, Life = { 1.5, 2.5 }, Speed = { 0.5, 1.5 }, Size = { 3, 7 }, Light = 0, Accel = Vector3.new(0, 1, 0), Transparency = 0.5 },
			{ Where = "Aura", Texture = SPARK, Rate = 8, Life = { 1.5, 3 }, Speed = { 0.3, 1 }, Size = { 0.3, 0 }, Light = 1, Accel = Vector3.zero }, -- stardust motes
		},
		Puff = {
			{ Texture = SMOKE, Colors = { rgb(90, 50, 130), rgb(12, 6, 18) }, Burst = 20, Life = { 1, 1.8 }, Speed = { 6, 11 }, Size = { 2, 7 }, Light = 0, Accel = Vector3.new(0, 1.5, 0), Transparency = 0.4, Spread = 14 },
			{ Texture = SPARK, Burst = 10, Life = { 0.5, 1 }, Speed = { 8, 12 }, Size = { 0.5, 0 }, Light = 1, Spread = 14 },
		},
		Stream = {
			{ Texture = SMOKE, Colors = { hex("9D4EDD"), rgb(20, 8, 30) }, Rate = 90, Life = { 0.5, 0.8 }, Speed = { 40, 55 }, Size = { 2.5, 10 }, Light = 0.4, Spread = 12, Transparency = 0.3 },
			{ Texture = SPARK, Rate = 80, Life = { 0.4, 0.7 }, Speed = { 45, 60 }, Size = { 0.7, 0 }, Light = 1, Spread = 10 },
		},
		BeamWidth = 2,
		Charge = { Texture = SPARK, Rate = 45, Life = { 0.3, 0.6 }, Speed = { 0.5, 2 }, Size = { 0.4, 1 }, Light = 1 },
		WingAura = { Texture = SPARK, Rate = 26, Life = { 0.4, 0.8 }, Speed = { 0, 1 }, Size = { 0.5, 0 }, Light = 1 },
		TrailLight = 0.5,
		TailTip = { Texture = SMOKE, Colors = { rgb(60, 32, 90), rgb(10, 5, 16) }, Rate = 6, Life = { 1.2, 2 }, Speed = { 0.3, 1 }, Size = { 2, 5 }, Light = 0, Transparency = 0.5 },
		TailBurst = { Texture = SPARK, Burst = 40, Life = { 0.3, 0.6 }, Speed = { 10, 18 }, Size = { 0.9, 0 }, Light = 1, Spread = 180 },
		Ring = { Texture = SMOKE, Colors = { hex("9D4EDD"), rgb(20, 8, 30) }, Burst = 24, Life = { 0.6, 1 }, Speed = { 12, 18 }, Size = { 3, 7 }, Light = 0.3, Transparency = 0.4, Up = true },
	},
	Ice = {
		Colors = { hex("CAF0F8"), hex("00B4D8") },
		Dark = rgb(170, 200, 215),
		Glow = hex("90E0EF"),
		GlowBrightness = 0.7,
		Ambient = {
			{ Where = "Wings", Texture = SMOKE, Colors = { rgb(235, 250, 255), rgb(170, 215, 245) }, Rate = 8, Life = { 1.5, 2.5 }, Speed = { 0.5, 1.5 }, Size = { 2.5, 5 }, Light = 0.2, Accel = Vector3.new(0, -2, 0), Transparency = 0.75 }, -- cold mist
			{ Where = "Aura", Texture = SPARK, Colors = { rgb(255, 255, 255), hex("CAF0F8") }, Rate = 6, Life = { 2, 3 }, Speed = { 0.5, 1.5 }, Size = { 0.35, 0.2 }, Light = 0.8, Accel = Vector3.new(0, -1.5, 0), Rotation = true }, -- falling snow crystals
			{ Where = "Mouth", Texture = SMOKE, Colors = { rgb(235, 250, 255), rgb(200, 230, 250) }, Rate = 5, Life = { 1, 1.8 }, Speed = { 3, 6 }, Size = { 1.5, 5 }, Light = 0.1, Accel = Vector3.new(0, -1, 0), Transparency = 0.6 },
		},
		Puff = {
			{ Texture = SMOKE, Colors = { rgb(240, 252, 255), hex("90E0EF") }, Burst = 22, Life = { 0.8, 1.5 }, Speed = { 8, 14 }, Size = { 1.5, 6 }, Light = 0.25, Accel = Vector3.new(0, -2, 0), Transparency = 0.45, Spread = 14 },
			{ Texture = SPARK, Burst = 18, Life = { 0.6, 1.2 }, Speed = { 10, 16 }, Size = { 0.5, 0 }, Light = 1, Accel = Vector3.new(0, -3, 0), Spread = 14 },
		},
		Stream = {
			{ Texture = SMOKE, Colors = { rgb(240, 252, 255), hex("48CAE4") }, Rate = 90, Life = { 0.5, 0.8 }, Speed = { 40, 55 }, Size = { 2, 9 }, Light = 0.3, Spread = 12, Transparency = 0.35 },
			{ Texture = SPARK, Rate = 70, Life = { 0.4, 0.7 }, Speed = { 45, 60 }, Size = { 0.6, 0.2 }, Light = 1, Spread = 10, Rotation = true },
		},
		BeamWidth = 1.8,
		Charge = { Texture = SPARK, Rate = 40, Life = { 0.3, 0.6 }, Speed = { 0.5, 2 }, Size = { 0.4, 1 }, Light = 1 },
		WingAura = { Texture = SPARK, Rate = 24, Life = { 0.5, 0.9 }, Speed = { 0, 1 }, Size = { 0.45, 0.2 }, Light = 0.9, Accel = Vector3.new(0, -3, 0), Rotation = true },
		TrailLight = 0.8,
		TailTip = { Texture = SMOKE, Colors = { rgb(235, 250, 255), rgb(170, 215, 245) }, Rate = 6, Life = { 1, 1.8 }, Speed = { 0.3, 1 }, Size = { 1.5, 4 }, Light = 0.1, Accel = Vector3.new(0, -1, 0), Transparency = 0.6 }, -- cold mist trail
		TailBurst = { Texture = SPARK, Burst = 36, Life = { 0.4, 0.8 }, Speed = { 10, 18 }, Size = { 0.8, 0.2 }, Light = 1, Spread = 180, Rotation = true },
		Ring = { Texture = SMOKE, Colors = { rgb(240, 252, 255), hex("90E0EF") }, Burst = 22, Life = { 0.7, 1.1 }, Speed = { 12, 18 }, Size = { 3, 7 }, Light = 0.2, Transparency = 0.45, Up = true },
	},
	Storm = { -- Lightning
		Colors = { hex("FFBE0B"), hex("3A86FF") },
		Dark = rgb(70, 76, 96),
		Glow = hex("3A86FF"),
		GlowBrightness = 1,
		Ambient = {
			{ Where = "Wings", Texture = SPARK, Rate = 22, Life = { 0.08, 0.25 }, Speed = { 8, 18 }, Size = { 0.7, 0 }, Light = 1, Accel = Vector3.zero },
			{ Where = "Body", Texture = SPARK, Rate = 10, Life = { 0.1, 0.3 }, Speed = { 4, 10 }, Size = { 0.5, 0 }, Light = 1, Accel = Vector3.zero },
			{ Where = "Aura", Texture = SMOKE, Colors = { rgb(90, 95, 120), rgb(50, 54, 72) }, Rate = 3, Life = { 2, 3 }, Speed = { 0.5, 1 }, Size = { 3, 6 }, Light = 0, Accel = Vector3.new(0, 0.5, 0), Transparency = 0.8 },
		},
		Puff = {
			{ Texture = SPARK, Burst = 34, Life = { 0.12, 0.3 }, Speed = { 18, 30 }, Size = { 0.9, 0 }, Light = 1, Spread = 16 },
		},
		Stream = {
			{ Texture = SPARK, Rate = 160, Life = { 0.2, 0.35 }, Speed = { 60, 80 }, Size = { 1.2, 0 }, Light = 1, Spread = 10 },
			{ Texture = SMOKE, Colors = { hex("8EC5FF"), rgb(40, 60, 120) }, Rate = 30, Life = { 0.3, 0.5 }, Speed = { 35, 45 }, Size = { 2, 6 }, Light = 0.6, Spread = 10, Transparency = 0.6 },
		},
		BeamWidth = 1.4,
		Charge = { Texture = SPARK, Rate = 60, Life = { 0.1, 0.25 }, Speed = { 3, 8 }, Size = { 0.5, 0 }, Light = 1 },
		WingAura = { Texture = SPARK, Rate = 34, Life = { 0.08, 0.2 }, Speed = { 6, 12 }, Size = { 0.6, 0 }, Light = 1 },
		TrailLight = 1,
		TailTip = { Texture = SPARK, Rate = 10, Life = { 0.1, 0.25 }, Speed = { 4, 10 }, Size = { 0.5, 0 }, Light = 1 },
		TailBurst = { Texture = SPARK, Burst = 50, Life = { 0.1, 0.3 }, Speed = { 18, 30 }, Size = { 1, 0 }, Light = 1, Spread = 180 },
		Ring = { Texture = SPARK, Burst = 44, Life = { 0.15, 0.35 }, Speed = { 24, 36 }, Size = { 1, 0 }, Light = 1, Up = true },
		Arcs = true,
	},
	Nature = {
		Colors = { hex("C6F36B"), hex("3FA34D") },
		Dark = rgb(96, 84, 60),
		Glow = hex("9EF01A"),
		GlowBrightness = 0.6,
		Ambient = {
			{ Where = "Wings", Texture = SPARK, Colors = { rgb(150, 210, 90), rgb(80, 150, 50) }, Rate = 6, Life = { 3, 5 }, Speed = { 0.5, 1.5 }, Size = { 0.6, 0.4 }, Light = 0, Accel = Vector3.new(0.5, -1.5, 0), Rotation = true }, -- drifting leaves
			{ Where = "Aura", Texture = SPARK, Colors = { rgb(255, 250, 200), rgb(200, 240, 140) }, Rate = 5, Life = { 2.5, 4 }, Speed = { 0.3, 1 }, Size = { 0.25, 0 }, Light = 0.6, Accel = Vector3.new(0, 0.3, 0) }, -- pollen
		},
		Puff = {
			{ Texture = SPARK, Burst = 22, Life = { 1.2, 2.2 }, Speed = { 5, 9 }, Size = { 0.55, 0.2 }, Light = 0.5, Accel = Vector3.new(0, -0.8, 0), Rotation = true, Spread = 14 },
		},
		Stream = {
			{ Texture = SPARK, Rate = 110, Life = { 0.5, 0.8 }, Speed = { 40, 55 }, Size = { 0.8, 0.4 }, Light = 0.4, Spread = 12, Rotation = true },
			{ Texture = SMOKE, Colors = { rgb(190, 240, 150), rgb(60, 120, 50) }, Rate = 30, Life = { 0.5, 0.8 }, Speed = { 30, 40 }, Size = { 2, 7 }, Light = 0.2, Spread = 12, Transparency = 0.55 },
		},
		BeamWidth = 1.6,
		Charge = { Texture = SPARK, Rate = 30, Life = { 0.4, 0.7 }, Speed = { 0.5, 1.5 }, Size = { 0.4, 0.8 }, Light = 0.7 },
		WingAura = { Texture = SPARK, Rate = 18, Life = { 0.8, 1.4 }, Speed = { 0, 1 }, Size = { 0.5, 0.3 }, Light = 0.3, Rotation = true },
		TrailLight = 0.6,
		TailTip = { Texture = SPARK, Rate = 5, Life = { 1.5, 2.5 }, Speed = { 0.3, 1 }, Size = { 0.45, 0.3 }, Light = 0.2, Accel = Vector3.new(0.3, -1, 0), Rotation = true },
		TailBurst = { Texture = SPARK, Burst = 36, Life = { 0.6, 1.1 }, Speed = { 8, 15 }, Size = { 0.7, 0.3 }, Light = 0.4, Spread = 180, Rotation = true },
		Ring = { Texture = SPARK, Burst = 30, Life = { 0.6, 1 }, Speed = { 10, 16 }, Size = { 0.7, 0.3 }, Light = 0.3, Rotation = true, Up = true },
	},
	Water = {
		Colors = { hex("90E0EF"), hex("0077B6") },
		Dark = rgb(150, 180, 200),
		Glow = hex("48CAE4"),
		GlowBrightness = 0.6,
		Ambient = {
			{ Where = "Wings", Texture = SPARK, Colors = { rgb(200, 230, 255), rgb(110, 170, 230) }, Rate = 10, Life = { 0.8, 1.4 }, Speed = { 0.5, 1 }, Size = { 0.35, 0.2 }, Light = 0.3, Accel = Vector3.new(0, -25, 0) }, -- dripping
			{ Where = "Aura", Texture = SMOKE, Colors = { rgb(170, 210, 240), rgb(120, 170, 220) }, Rate = 4, Life = { 1.5, 2.5 }, Speed = { 1, 2 }, Size = { 2, 4 }, Light = 0.1, Accel = Vector3.new(0, -2, 0), Transparency = 0.75 },
		},
		Puff = {
			{ Texture = SPARK, Burst = 26, Life = { 0.6, 1.1 }, Speed = { 12, 18 }, Size = { 0.5, 0.2 }, Light = 0.4, Accel = Vector3.new(0, -30, 0), Spread = 14 },
			{ Texture = SMOKE, Colors = { rgb(190, 225, 245), rgb(140, 190, 230) }, Burst = 10, Life = { 0.8, 1.4 }, Speed = { 5, 9 }, Size = { 2, 5 }, Light = 0.1, Accel = Vector3.new(0, -2, 0), Transparency = 0.6, Spread = 14 },
		},
		Stream = {
			{ Texture = SPARK, Rate = 120, Life = { 0.4, 0.7 }, Speed = { 50, 65 }, Size = { 0.7, 0.3 }, Light = 0.5, Accel = Vector3.new(0, -30, 0), Spread = 8 },
			{ Texture = SMOKE, Colors = { rgb(210, 240, 255), hex("0096C7") }, Rate = 40, Life = { 0.5, 0.8 }, Speed = { 35, 45 }, Size = { 2, 8 }, Light = 0.2, Spread = 10, Transparency = 0.5 },
		},
		BeamWidth = 1.8,
		Charge = { Texture = SPARK, Rate = 35, Life = { 0.3, 0.6 }, Speed = { 0.5, 2 }, Size = { 0.4, 0.9 }, Light = 0.7 },
		WingAura = { Texture = SPARK, Rate = 26, Life = { 0.4, 0.7 }, Speed = { 0, 1 }, Size = { 0.4, 0.2 }, Light = 0.5, Accel = Vector3.new(0, -20, 0) },
		TrailLight = 0.7,
		TailTip = { Texture = SPARK, Rate = 6, Life = { 0.8, 1.4 }, Speed = { 0.5, 1 }, Size = { 0.35, 0.2 }, Light = 0.3, Accel = Vector3.new(0, -25, 0) },
		TailBurst = { Texture = SPARK, Burst = 40, Life = { 0.5, 0.9 }, Speed = { 12, 20 }, Size = { 0.6, 0.2 }, Light = 0.5, Accel = Vector3.new(0, -30, 0), Spread = 180 },
		Ring = { Texture = SMOKE, Colors = { rgb(210, 240, 255), hex("48CAE4") }, Burst = 22, Life = { 0.6, 1 }, Speed = { 14, 20 }, Size = { 2.5, 6 }, Light = 0.2, Transparency = 0.45, Up = true },
	},
	Earth = {
		Colors = { hex("FF8C42"), hex("7F5539") },
		Dark = rgb(150, 125, 95),
		Glow = rgb(255, 120, 40), -- magma seams
		GlowBrightness = 0.7,
		Ambient = {
			{ Where = "Body", Texture = SMOKE, Colors = { rgb(150, 125, 95), rgb(110, 92, 72) }, Rate = 5, Life = { 1.5, 2.5 }, Speed = { 0.5, 1.5 }, Size = { 2.5, 5 }, Light = 0, Accel = Vector3.new(0, -1, 0), Transparency = 0.7 },
			{ Where = "Wings", Texture = SPARK, Colors = { rgb(120, 100, 80), rgb(80, 65, 50) }, Rate = 6, Life = { 1, 1.6 }, Speed = { 0.5, 1 }, Size = { 0.4, 0.3 }, Light = 0, Accel = Vector3.new(0, -30, 0) }, -- falling grit
		},
		Puff = {
			{ Texture = SMOKE, Colors = { rgb(160, 130, 95), rgb(110, 90, 70) }, Burst = 16, Life = { 1, 1.8 }, Speed = { 6, 10 }, Size = { 2, 6 }, Light = 0, Accel = Vector3.new(0, -1, 0), Transparency = 0.5, Spread = 14 },
			{ Texture = SPARK, Burst = 10, Life = { 0.6, 1.1 }, Speed = { 8, 12 }, Size = { 0.45, 0.3 }, Light = 0.8, Accel = Vector3.new(0, -25, 0), Spread = 14 },
		},
		Stream = {
			{ Texture = SMOKE, Colors = { rgb(170, 140, 100), rgb(90, 70, 52) }, Rate = 70, Life = { 0.6, 0.9 }, Speed = { 35, 50 }, Size = { 3, 10 }, Light = 0, Spread = 12, Transparency = 0.4 },
			{ Texture = SPARK, Rate = 60, Life = { 0.4, 0.7 }, Speed = { 40, 55 }, Size = { 0.7, 0.3 }, Light = 1, Accel = Vector3.new(0, -20, 0), Spread = 10 },
		},
		BeamWidth = 1.6,
		Charge = { Texture = SPARK, Rate = 30, Life = { 0.3, 0.6 }, Speed = { 0.5, 2 }, Size = { 0.4, 0.9 }, Light = 0.9 },
		WingAura = { Texture = SPARK, Rate = 20, Life = { 0.5, 0.9 }, Speed = { 0, 1 }, Size = { 0.45, 0.3 }, Light = 0.6, Accel = Vector3.new(0, -25, 0) },
		TrailLight = 0.3,
		TailTip = { Texture = SMOKE, Colors = { rgb(150, 125, 95), rgb(110, 92, 72) }, Rate = 4, Life = { 1.2, 2 }, Speed = { 0.3, 1 }, Size = { 1.5, 4 }, Light = 0, Accel = Vector3.new(0, -1, 0), Transparency = 0.6 },
		TailBurst = { Texture = SMOKE, Colors = { rgb(170, 140, 100), rgb(90, 70, 52) }, Burst = 24, Life = { 0.6, 1 }, Speed = { 10, 16 }, Size = { 2, 6 }, Light = 0, Spread = 180, Transparency = 0.4 },
		Ring = { Texture = SMOKE, Colors = { rgb(170, 140, 100), rgb(90, 70, 52) }, Burst = 26, Life = { 0.7, 1.2 }, Speed = { 14, 22 }, Size = { 3, 8 }, Light = 0, Transparency = 0.35, Up = true },
	},
	Light = {
		Colors = { hex("FFF8E1"), hex("FFD166") },
		Dark = rgb(230, 215, 180),
		Glow = rgb(255, 225, 150),
		GlowBrightness = 1,
		AlwaysGlow = true,
		Ambient = {
			{ Where = "Aura", Texture = SPARK, Rate = 12, Life = { 2, 3 }, Speed = { 0.5, 1.5 }, Size = { 0.5, 0 }, Light = 1, Accel = Vector3.new(0, 1.5, 0) }, -- rising motes
			{ Where = "Wings", Texture = SPARK, Rate = 8, Life = { 1, 2 }, Speed = { 0.3, 1 }, Size = { 0.6, 0 }, Light = 1, Accel = Vector3.new(0, 1, 0) },
		},
		Puff = {
			{ Texture = SPARK, Burst = 28, Life = { 0.6, 1.2 }, Speed = { 10, 16 }, Size = { 0.8, 0 }, Light = 1, Accel = Vector3.new(0, 1, 0), Spread = 14 },
		},
		Stream = {
			{ Texture = SPARK, Rate = 140, Life = { 0.35, 0.6 }, Speed = { 50, 65 }, Size = { 1, 0 }, Light = 1, Spread = 8 },
			{ Texture = SMOKE, Colors = { rgb(255, 250, 230), hex("FFD166") }, Rate = 30, Life = { 0.3, 0.5 }, Speed = { 35, 45 }, Size = { 2, 6 }, Light = 1, Spread = 8, Transparency = 0.6 },
		},
		BeamWidth = 2.4,
		Charge = { Texture = SPARK, Rate = 50, Life = { 0.3, 0.6 }, Speed = { 0.5, 2 }, Size = { 0.5, 1.2 }, Light = 1 },
		WingAura = { Texture = SPARK, Rate = 28, Life = { 0.4, 0.8 }, Speed = { 0, 1 }, Size = { 0.6, 0 }, Light = 1 },
		TrailLight = 1,
		TailTip = { Texture = SPARK, Rate = 8, Life = { 0.8, 1.4 }, Speed = { 0.3, 1 }, Size = { 0.5, 0 }, Light = 1, Accel = Vector3.new(0, 1, 0) },
		TailBurst = { Texture = SPARK, Burst = 44, Life = { 0.4, 0.8 }, Speed = { 12, 20 }, Size = { 1, 0 }, Light = 1, Spread = 180 },
		Ring = { Texture = SPARK, Burst = 40, Life = { 0.4, 0.7 }, Speed = { 16, 24 }, Size = { 1, 0 }, Light = 1, Up = true },
	},
}

DragonElementalVFX.Presets = PRESETS
DragonElementalVFX.TrailSpeed = TRAIL_SPEED

-- Shared by every element: dust kicked up under the feet, and the happy sparkle.
local DUST: Recipe = { Texture = SMOKE, Burst = 16, Life = { 0.8, 1.3 }, Speed = { 6, 12 }, Size = { 3, 8 }, Light = 0, Transparency = 0.5, Drag = 3, Up = true }
local HAPPY: Recipe = { Texture = SPARK, Colors = { rgb(255, 235, 160), rgb(255, 150, 200) }, Burst = 14, Life = { 0.8, 1.4 }, Speed = { 2, 5 }, Size = { 0.6, 0 }, Light = 1, Accel = Vector3.new(0, 3, 0), Spread = 60 }

-- Building (server) ---------------------------------------------------------------

local function makeEmitter(recipe: Recipe, preset: Preset, scale: number, rateScale: number, role: string, parent: Instance, colors: { Color3 }?): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Name = "VFX_" .. role
	e.Texture = recipe.Texture
	local c = colors or recipe.Colors or preset.Colors
	e.Color = ColorSequence.new(c[1], c[2] or c[1])
	e.LightEmission = recipe.Light
	e.Lifetime = NumberRange.new(recipe.Life[1], recipe.Life[2])
	e.Speed = NumberRange.new(recipe.Speed[1] * scale, recipe.Speed[2] * scale)
	e.Size = NumberSequence.new(recipe.Size[1] * scale, recipe.Size[2] * scale)
	e.Transparency = NumberSequence.new(recipe.Transparency or 0.15, 1)
	e.Acceleration = (recipe.Accel or Vector3.zero) * scale
	e.Drag = recipe.Drag or 1
	if recipe.Up then
		-- Ground rings: out and up from the ground in every direction.
		e.EmissionDirection = Enum.NormalId.Top
		e.SpreadAngle = Vector2.new(80, 80)
	elseif recipe.Spread then
		e.EmissionDirection = Enum.NormalId.Front
		e.SpreadAngle = Vector2.new(recipe.Spread, recipe.Spread)
	else
		e.SpreadAngle = Vector2.new(180, 180)
	end
	if recipe.Rotation then
		e.Rotation = NumberRange.new(0, 360)
		e.RotSpeed = NumberRange.new(-100, 100)
	end
	if parent:IsA("BasePart") then
		e.Shape = Enum.ParticleEmitterShape.Box
		e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
	end
	if recipe.Burst then
		e.Rate = 0
		e:SetAttribute("Burst", math.max(1, math.floor(recipe.Burst * math.sqrt(rateScale) + 0.5)))
	else
		e.Rate = (recipe.Rate or 0) * rateScale
		e:SetAttribute("BaseRate", e.Rate)
	end
	e:SetAttribute("VFX", role)
	e.Parent = parent
	return e
end

local function findAttachment(model: Model, ...: string): Attachment?
	for _, name in { ... } do
		local found = model:FindFirstChild(name, true)
		if found and found:IsA("Attachment") then
			return found
		end
	end
	return nil
end

local function partNamed(model: Model, name: string): BasePart?
	local p = model:FindFirstChild(name)
	return if p and p:IsA("BasePart") then p else nil
end

local function ambientTargets(model: Model, where: string): { Instance }
	local root = model.PrimaryPart :: BasePart
	local list: { Instance } = {}
	local function add(x: Instance?)
		if x then
			table.insert(list, x)
		end
	end
	if where == "Aura" then
		add(root:FindFirstChild("AuraAttachment"))
	elseif where == "Mouth" then
		add(findAttachment(model, "Mouth_VFX", "MouthAttachment"))
	elseif where == "Wings" then
		for _, n in { "LeftWing", "RightWing", "LeftWingTip", "RightWingTip" } do
			add(partNamed(model, n))
		end
	elseif where == "Tail" then
		add(partNamed(model, "Tail") or partNamed(model, "Tail3"))
		add(partNamed(model, "Tail2"))
	elseif where == "Body" then
		add(partNamed(model, "Body"))
		add(partNamed(model, "Neck"))
	end
	return list
end

-- mode: "Ride" (everything) or "Station" (calm effects only: no breath attack,
-- trails, impacts or arcs, so a plot full of dragons stays cheap).
function DragonElementalVFX.Apply(model: Model, element: string, rarity: string, scale: number, mode: string)
	local preset = PRESETS[element]
	local root = model.PrimaryPart
	if not preset or not root then
		return
	end
	model:SetAttribute("DragonElement", element)
	local info = Rarities.Info[rarity]
	local rank = if info then info.Rank else 1
	local station = mode == "Station"
	local rateScale = (RARITY_RATE[rarity] or 0.5) * (if station then 0.6 else 1)
	local western = model:GetAttribute("Rig") == "Western"
	local length = (model:GetAttribute("Length") or 36) :: number

	-- Ambient: always running (switched off at a distance by the client).
	for _, recipe in preset.Ambient do
		for _, target in ambientTargets(model, recipe.Where or "Aura") do
			makeEmitter(recipe, preset, scale, rateScale, "Ambient", target)
		end
	end

	local mouth = findAttachment(model, "Mouth_VFX", "MouthAttachment")
	local tailTip = findAttachment(model, "Tail_Tip")
	local chest = findAttachment(model, "Chest_Core") or root:FindFirstChild("AuraAttachment") :: Attachment?
	local dorsal = findAttachment(model, "Dorsal_Spines")

	-- Calm breath puffs (both modes; western dragons breathe, classic ones don't).
	if mouth and western then
		for _, recipe in preset.Puff do
			makeEmitter(recipe, preset, scale, 1 + 0.15 * rank, "Puff", mouth)
		end
	end
	if tailTip then
		makeEmitter(preset.TailTip, preset, scale, rateScale, "Ambient", tailTip)
	end

	-- Chest core glow (the inner fire); pulses with charge and roars.
	if western or preset.AlwaysGlow or rank >= 4 then
		local light = Instance.new("PointLight")
		light.Name = "VFX_ChestCore"
		light.Color = preset.Glow
		light.Brightness = preset.GlowBrightness * (if rank >= 6 then 2 elseif rank >= 5 then 1.4 else 0.8)
		light.Range = 22 * scale + 6
		light.Shadows = false
		light:SetAttribute("VFX", "ChestCore")
		light:SetAttribute("Base", light.Brightness)
		light.Parent = chest or root
	end

	-- Happy sparkle above the head (petting).
	local head = partNamed(model, "Head")
	if head then
		local happy = Instance.new("Attachment")
		happy.Name = "Happy_VFX"
		happy.Position = Vector3.new(0, head.Size.Y * 0.5, 0)
		happy.Parent = head
		makeEmitter(HAPPY, preset, scale, 1, "Happy", happy)
	end

	if station or not western then
		return
	end

	-- Breath attack: charge sparks, then the stream, a beam and a mouth light.
	if mouth then
		makeEmitter(preset.Charge, preset, scale, 1, "Charge", mouth).Rate = 0
		for _, recipe in preset.Stream do
			makeEmitter(recipe, preset, scale, 1, "Stream", mouth).Enabled = false
		end
		local target = findAttachment(model, "BreathEnd")
		if target then
			local beam = Instance.new("Beam")
			beam.Name = "VFX_StreamBeam"
			beam.Attachment0 = mouth
			beam.Attachment1 = target
			beam.Color = ColorSequence.new(preset.Colors[1], preset.Colors[2])
			beam.Transparency = NumberSequence.new(0.1, 0.9)
			beam.LightEmission = 1
			beam.Width0 = preset.BeamWidth * scale * 0.6
			beam.Width1 = preset.BeamWidth * scale * 1.8
			beam.FaceCamera = true
			beam.Segments = 12
			beam.Enabled = false
			beam:SetAttribute("VFX", "StreamBeam")
			beam:SetAttribute("W1", beam.Width1)
			beam.Parent = mouth
		end
		local light = Instance.new("PointLight")
		light.Name = "VFX_MouthLight"
		light.Color = preset.Colors[1]
		light.Brightness = 0
		light.Range = 26 * scale + 6
		light.Shadows = false
		light.Enabled = false
		light:SetAttribute("VFX", "MouthLight")
		light.Parent = mouth
	end

	-- Spine glow along the back.
	if dorsal then
		local light = Instance.new("PointLight")
		light.Name = "VFX_Dorsal"
		light.Color = preset.Glow
		light.Brightness = preset.GlowBrightness * 0.6
		light.Range = 14 * scale + 4
		light.Shadows = false
		light:SetAttribute("VFX", "Dorsal")
		light:SetAttribute("Base", light.Brightness)
		light.Parent = dorsal
	end

	-- Wingtips: ribbon trails and an aura, both only at speed in flight.
	for _, side in { { "Wing_L_Tip", 1 }, { "Wing_R_Tip", -1 } } do
		local tip = findAttachment(model, side[1] :: string)
		if tip then
			local inner = Instance.new("Attachment")
			inner.Name = "TrailInner"
			-- toward the body along the span: a wide ribbon off the wing's outer edge
			inner.CFrame = tip.CFrame * CFrame.new((side[2] :: number) * length * 0.09, 0, 0)
			inner.Parent = tip.Parent
			local t = Instance.new("Trail")
			t.Name = "VFX_WingTrail"
			t.Attachment0 = tip
			t.Attachment1 = inner
			t.Color = ColorSequence.new(preset.Colors[1], preset.Colors[2])
			t.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(1, 1) })
			t.WidthScale = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0.2) })
			t.LightEmission = preset.TrailLight
			t.Lifetime = 0.55
			t.MinLength = 0.3
			t.Enabled = false
			t:SetAttribute("VFX", "WingTrail")
			t.Parent = tip.Parent
			makeEmitter(preset.WingAura, preset, scale, 1, "WingAura", tip).Enabled = false
		end
	end

	-- Tail whip burst.
	if tailTip then
		makeEmitter(preset.TailBurst, preset, scale, 1, "TailBurst", tailTip)
	end

	-- Takeoff / landing: dust under each foot and an elemental ring on the ground.
	for _, n in { "Feet_Front_L", "Feet_Front_R", "Feet_Back_L", "Feet_Back_R" } do
		local foot = findAttachment(model, n)
		if foot then
			makeEmitter(DUST, preset, scale, 1, "Dust", foot, { preset.Dark, preset.Dark:Lerp(Color3.new(0, 0, 0), 0.3) })
		end
	end
	local ground = Instance.new("Attachment")
	ground.Name = "Ground_VFX"
	ground.Position = Vector3.new(0, -((model:GetAttribute("FootOffset") or 6) :: number), 0)
	ground.Parent = root
	makeEmitter(preset.Ring, preset, scale, 1, "Ring", ground)

	-- Lightning: zig-zag arcs (three segments each, re-shaped on every flash)
	-- between the wingtips, the spines, the neck and the tail.
	if preset.Arcs then
		local points = {
			findAttachment(model, "Wing_L_Tip"), dorsal, findAttachment(model, "Wing_R_Tip"),
		}
		local function arcPoint(partName: string): Attachment?
			local p = partNamed(model, partName)
			if not p then
				return nil
			end
			local a = Instance.new("Attachment")
			a.Name = "ArcPoint"
			a.Position = Vector3.new(0, p.Size.Y * 0.35, 0)
			a.Parent = p
			return a
		end
		local neck, tail = arcPoint("Neck"), arcPoint("Tail2") or arcPoint("Tail1")
		local arcPairs = { { points[1], points[2] }, { points[2], points[3] }, { points[1], points[3] }, { points[2], neck }, { points[2], tail } }
		local group = 0
		for _, pair in arcPairs do
			local a, b = pair[1], pair[2]
			if a and b then
				group += 1
				local mids = {}
				for k = 1, 2 do
					local m = Instance.new("Attachment")
					m.Name = "ArcMid"
					m.Parent = root
					mids[k] = m
				end
				local chain = { a, mids[1], mids[2], b }
				for k = 1, 3 do
					local beam = Instance.new("Beam")
					beam.Name = "VFX_Arc"
					beam.Attachment0 = chain[k]
					beam.Attachment1 = chain[k + 1]
					beam.Color = ColorSequence.new(Color3.new(1, 1, 1), preset.Colors[2])
					beam.LightEmission = 1
					beam.Width0 = 0.4 * scale
					beam.Width1 = 0.25 * scale
					beam.FaceCamera = true
					beam.Enabled = false
					beam:SetAttribute("VFX", "Arc")
					beam:SetAttribute("Group", group)
					beam:SetAttribute("Seg", k)
					beam.Parent = root
				end
			end
		end
	end
end

-- Playing (client) ----------------------------------------------------------------

export type Info = { State: string, Flying: boolean, Speed: number, Calm: boolean }

type ArcGroup = { A: Attachment, B: Attachment, Mids: { Attachment }, Beams: { Beam } }

export type Handle = {
	Model: Model,
	Size: number,
	Roles: { [string]: { Instance } },
	Arcs: { ArcGroup },
	Charge: number,
	ChargeTarget: number,
	Breathing: boolean,
	Pulse: number,
	Active: boolean,
	Trails: boolean,
	NextPuff: number,
	NextArc: number,
	Seed: number,
	Tick: (Handle, number, number, Info) -> (),
	Event: (Handle, string) -> (),
	SetActive: (Handle, boolean) -> (),
}

local Handle = {}
Handle.__index = Handle

function DragonElementalVFX.Bind(model: Model): Handle
	local roles: { [string]: { Instance } } = {}
	local arcBeams: { [number]: { Beam } } = {}
	for _, d in model:GetDescendants() do
		local role = d:GetAttribute("VFX")
		if type(role) == "string" then
			roles[role] = roles[role] or {}
			table.insert(roles[role], d)
			if role == "Arc" and d:IsA("Beam") then
				local g = d:GetAttribute("Group") :: number
				arcBeams[g] = arcBeams[g] or {}
				arcBeams[g][d:GetAttribute("Seg") :: number] = d
			end
		end
	end
	local arcs: { ArcGroup } = {}
	for _, beams in arcBeams do
		if beams[1] and beams[2] and beams[3] then
			table.insert(arcs, {
				A = beams[1].Attachment0 :: Attachment,
				B = beams[3].Attachment1 :: Attachment,
				Mids = { beams[1].Attachment1 :: Attachment, beams[2].Attachment1 :: Attachment },
				Beams = beams,
			})
		end
	end
	local self = setmetatable({
		Model = model,
		Size = ((model:GetAttribute("Length") or 36) :: number) / 36,
		Roles = roles,
		Arcs = arcs,
		Charge = 0,
		ChargeTarget = 0,
		Breathing = false,
		Pulse = 0,
		Active = true,
		Trails = false,
		NextPuff = os.clock() + 2 + math.random() * 6,
		NextArc = os.clock() + math.random(),
		Seed = math.random() * 100,
	}, Handle)
	return self :: any
end

local function each(self: any, role: string): { Instance }
	return self.Roles[role] or {}
end

local function burst(self: any, role: string, factor: number?)
	for _, e in each(self, role) do
		if e:IsA("ParticleEmitter") then
			e:Emit(math.ceil(((e:GetAttribute("Burst") or 10) :: number) * (factor or 1)))
		end
	end
end

function Handle.SetActive(self: any, on: boolean)
	if self.Active == on then
		return
	end
	self.Active = on
	for _, e in each(self, "Ambient") do
		(e :: ParticleEmitter).Enabled = on
	end
	if not on then
		self:SetTrails(false)
	end
end

function Handle.SetTrails(self: any, on: boolean)
	if self.Trails == on then
		return
	end
	self.Trails = on
	for _, t in each(self, "WingTrail") do
		(t :: Trail).Enabled = on
	end
	for _, e in each(self, "WingAura") do
		(e :: ParticleEmitter).Enabled = on
	end
end

local function setStream(self: any, on: boolean)
	for _, e in each(self, "Stream") do
		(e :: ParticleEmitter).Enabled = on
	end
	for _, b in each(self, "StreamBeam") do
		(b :: Beam).Enabled = on
	end
end

-- Moments, sent by the motion controller when a clip or state change hits them.
function Handle.Event(self: any, name: string)
	if name == "ChargeStart" then
		self.ChargeTarget = 1
	elseif name == "BreathStart" then
		self.Breathing = true
		self.ChargeTarget = 0.35
		setStream(self, true)
	elseif name == "BreathStop" or name == "ActionEnd" then
		self.Breathing = false
		self.ChargeTarget = 0
		setStream(self, false)
	elseif name == "Roar" then
		self.Pulse = 1
		burst(self, "Puff", 1.5)
	elseif name == "TailBurst" then
		burst(self, "TailBurst")
	elseif name == "Takeoff" or name == "Land" then
		burst(self, "Dust", if name == "Land" then 1.3 else 1)
		burst(self, "Ring", if name == "Land" then 1.2 else 1)
	elseif name == "Happy" then
		burst(self, "Happy")
		self.Pulse = math.max(self.Pulse, 0.5)
	end
end

function Handle.Tick(self: any, t: number, dt: number, info: Info)
	-- Speed-gated wingtip trails and aura.
	self:SetTrails(self.Active and info.Flying and info.Speed > TRAIL_SPEED)
	if not self.Active then
		return
	end
	-- Calm breath puffs now and then (not while breathing the real thing).
	if not self.Breathing and t > self.NextPuff then
		burst(self, "Puff", if info.Calm then 1 else 0.5)
		self.NextPuff = t + (if info.Calm then 3 + math.random() * 5 else 1.5 + math.random() * 2.5)
	end
	-- Charge builds and fades smoothly; the sparks follow it.
	self.Charge += (self.ChargeTarget - self.Charge) * math.min(1, dt * 4)
	for _, e in each(self, "Charge") do
		local emitter = e :: ParticleEmitter
		emitter.Rate = ((emitter:GetAttribute("BaseRate") or 30) :: number) * self.Charge
	end
	self.Pulse = math.max(0, self.Pulse - dt * 1.4)
	local boost = 1 + 1.6 * self.Charge + 1.8 * self.Pulse + (if self.Breathing then 1 else 0)
	-- TUNING: glow flicker (slow breathing pulse + fast flicker)
	for _, l in each(self, "ChestCore") do
		local light = l :: PointLight
		local base = (light:GetAttribute("Base") or 1) :: number
		light.Brightness = base * (0.8 + 0.2 * math.sin(t * 1.7 + self.Seed) + 0.12 * math.sin(t * 13 + self.Seed)) * boost
	end
	for _, l in each(self, "Dorsal") do
		local light = l :: PointLight
		local base = (light:GetAttribute("Base") or 0.6) :: number
		light.Brightness = base * (0.6 + 0.4 * math.sin(t * 2.1 + self.Seed)) * boost
	end
	local mouthOn = self.Breathing or self.Charge > 0.08
	for _, l in each(self, "MouthLight") do
		local light = l :: PointLight
		light.Enabled = mouthOn
		light.Brightness = if self.Breathing then 4 + math.sin(t * 25) else 3 * self.Charge
	end
	if self.Breathing then
		for _, b in each(self, "StreamBeam") do
			local beam = b :: Beam
			beam.Width1 = ((beam:GetAttribute("W1") or beam.Width1) :: number) * (0.85 + 0.15 * math.sin(t * 30)) -- flicker
		end
	end
	-- Lightning arcs: one or two flash with a fresh zig-zag, more often when charged.
	if #self.Arcs > 0 and t > self.NextArc then
		for _, group in self.Arcs do
			for _, beam in group.Beams do
				beam.Enabled = false
			end
		end
		local excited = self.Breathing or self.Charge > 0.2 or self.Pulse > 0.2
		for _ = 1, if excited then 3 else math.random(1, 2) do
			local group = self.Arcs[math.random(1, #self.Arcs)]
			local a, b = group.A.WorldPosition, group.B.WorldPosition
			local jag = (a - b).Magnitude * 0.12
			for k, mid in group.Mids do
				local p = a:Lerp(b, k / 3)
				mid.WorldPosition = p + Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 2 * jag
			end
			for _, beam in group.Beams do
				beam.Enabled = true
			end
		end
		local beams = self.Arcs
		task.delay(0.06 + math.random() * 0.08, function()
			for _, group in beams do
				for _, beam in group.Beams do
					beam.Enabled = false
				end
			end
		end)
		self.NextArc = t + (if excited then 0.08 + math.random() * 0.25 else 0.25 + math.random() * 1.6)
	end
end

return DragonElementalVFX
