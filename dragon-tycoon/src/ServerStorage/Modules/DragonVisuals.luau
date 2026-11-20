-- ServerStorage/Modules/DragonVisuals
-- Builds the 3D model for one of a player's dragons, ready to animate:
--   * the species' realistic model from ReplicatedStorage/DragonModels
--   * element effects built into the design: each element has its own set of
--     particle effects on the wings, mouth, tail and body (see EFFECTS)
--   * rarity makes the effects denser, and Legendary/Mythic dragons glow
--   * size: "Ride" is full size, "Station" is scaled down to fit station slots

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared

local DragonCatalog = require(Shared.DragonCatalog)
local Rarities = require(Shared.Rarities)
local CosmeticCatalog = require(Shared.CosmeticCatalog)

local DragonVisuals = {}

DragonVisuals.StationScale = 0.4

local SPARK = "rbxasset://textures/particles/sparkles_main.dds"
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"
local FIRE = "rbxasset://textures/particles/fire_main.dds"

-- Where: Aura (body center), Wings (both wing parts), Mouth, Tail, Body (body part surface)
-- Sizes and speeds are for ride size and scale down for stations.
local EFFECTS = {
	Fire = {
		{ Where = "Wings", Texture = FIRE, Colors = { Color3.fromRGB(255, 190, 80), Color3.fromRGB(255, 70, 20) }, Rate = 14, Life = { 0.6, 1.2 }, Speed = { 1, 3 }, Size = { 0.9, 0 }, Light = 1, Accel = Vector3.new(0, 6, 0), Transparency = 0.2 },
		{ Where = "Aura", Texture = SPARK, Colors = { Color3.fromRGB(255, 170, 60), Color3.fromRGB(255, 80, 20) }, Rate = 10, Life = { 1.5, 2.5 }, Speed = { 2, 5 }, Size = { 0.6, 0 }, Light = 1, Accel = Vector3.new(0, 5, 0) },
		{ Where = "Mouth", Texture = SMOKE, Colors = { Color3.fromRGB(70, 60, 55), Color3.fromRGB(30, 28, 26) }, Rate = 4, Life = { 1.5, 2.5 }, Speed = { 2, 4 }, Size = { 2, 7 }, Light = 0, Accel = Vector3.new(0, 3, 0), Transparency = 0.55 },
		Glow = Color3.fromRGB(255, 120, 40),
	},
	Ice = {
		{ Where = "Wings", Texture = SMOKE, Colors = { Color3.fromRGB(230, 248, 255), Color3.fromRGB(170, 215, 245) }, Rate = 8, Life = { 1.5, 2.5 }, Speed = { 0.5, 1.5 }, Size = { 2.5, 5 }, Light = 0.2, Accel = Vector3.new(0, -2, 0), Transparency = 0.75 },
		{ Where = "Aura", Texture = SPARK, Colors = { Color3.fromRGB(255, 255, 255), Color3.fromRGB(190, 235, 255) }, Rate = 6, Life = { 2, 3 }, Speed = { 0.5, 1.5 }, Size = { 0.35, 0 }, Light = 0.8, Accel = Vector3.new(0, -1, 0) },
		{ Where = "Mouth", Texture = SMOKE, Colors = { Color3.fromRGB(235, 250, 255), Color3.fromRGB(200, 230, 250) }, Rate = 5, Life = { 1, 1.8 }, Speed = { 3, 6 }, Size = { 1.5, 5 }, Light = 0.1, Accel = Vector3.new(0, -1, 0), Transparency = 0.6 },
	},
	Storm = {
		{ Where = "Wings", Texture = SPARK, Colors = { Color3.fromRGB(230, 210, 255), Color3.fromRGB(140, 100, 255) }, Rate = 22, Life = { 0.08, 0.25 }, Speed = { 8, 18 }, Size = { 0.7, 0 }, Light = 1, Accel = Vector3.zero },
		{ Where = "Body", Texture = SPARK, Colors = { Color3.fromRGB(200, 190, 255), Color3.fromRGB(100, 80, 255) }, Rate = 10, Life = { 0.1, 0.3 }, Speed = { 4, 10 }, Size = { 0.5, 0 }, Light = 1, Accel = Vector3.zero },
		{ Where = "Aura", Texture = SMOKE, Colors = { Color3.fromRGB(90, 85, 110), Color3.fromRGB(50, 50, 70) }, Rate = 3, Life = { 2, 3 }, Speed = { 0.5, 1 }, Size = { 3, 6 }, Light = 0, Accel = Vector3.new(0, 0.5, 0), Transparency = 0.8 },
		Glow = Color3.fromRGB(150, 120, 255),
	},
	Nature = {
		{ Where = "Wings", Texture = SPARK, Colors = { Color3.fromRGB(150, 210, 90), Color3.fromRGB(80, 150, 50) }, Rate = 6, Life = { 3, 5 }, Speed = { 0.5, 1.5 }, Size = { 0.6, 0.4 }, Light = 0, Accel = Vector3.new(0.5, -1.5, 0), Rotation = true },
		{ Where = "Aura", Texture = SPARK, Colors = { Color3.fromRGB(255, 250, 200), Color3.fromRGB(200, 240, 140) }, Rate = 5, Life = { 2.5, 4 }, Speed = { 0.3, 1 }, Size = { 0.25, 0 }, Light = 0.6, Accel = Vector3.new(0, 0.3, 0) },
	},
	Water = {
		{ Where = "Wings", Texture = SPARK, Colors = { Color3.fromRGB(200, 230, 255), Color3.fromRGB(110, 170, 230) }, Rate = 10, Life = { 0.8, 1.4 }, Speed = { 0.5, 1 }, Size = { 0.35, 0.2 }, Light = 0.3, Accel = Vector3.new(0, -25, 0) },
		{ Where = "Tail", Texture = SPARK, Colors = { Color3.fromRGB(200, 230, 255), Color3.fromRGB(110, 170, 230) }, Rate = 6, Life = { 0.8, 1.4 }, Speed = { 0.5, 1 }, Size = { 0.35, 0.2 }, Light = 0.3, Accel = Vector3.new(0, -25, 0) },
		{ Where = "Aura", Texture = SMOKE, Colors = { Color3.fromRGB(170, 210, 240), Color3.fromRGB(120, 170, 220) }, Rate = 4, Life = { 1.5, 2.5 }, Speed = { 1, 2 }, Size = { 2, 4 }, Light = 0.1, Accel = Vector3.new(0, -2, 0), Transparency = 0.75 },
	},
	Earth = {
		{ Where = "Body", Texture = SMOKE, Colors = { Color3.fromRGB(150, 125, 95), Color3.fromRGB(110, 92, 72) }, Rate = 5, Life = { 1.5, 2.5 }, Speed = { 0.5, 1.5 }, Size = { 2.5, 5 }, Light = 0, Accel = Vector3.new(0, -1, 0), Transparency = 0.7 },
		{ Where = "Wings", Texture = SPARK, Colors = { Color3.fromRGB(120, 100, 80), Color3.fromRGB(80, 65, 50) }, Rate = 6, Life = { 1, 1.6 }, Speed = { 0.5, 1 }, Size = { 0.4, 0.3 }, Light = 0, Accel = Vector3.new(0, -30, 0) },
		Glow = Color3.fromRGB(255, 120, 40), -- magma seams on some Earth dragons
	},
	Light = {
		{ Where = "Aura", Texture = SPARK, Colors = { Color3.fromRGB(255, 245, 210), Color3.fromRGB(255, 210, 120) }, Rate = 12, Life = { 2, 3 }, Speed = { 0.5, 1.5 }, Size = { 0.5, 0 }, Light = 1, Accel = Vector3.new(0, 1.5, 0) },
		{ Where = "Wings", Texture = SPARK, Colors = { Color3.fromRGB(255, 240, 190), Color3.fromRGB(255, 200, 110) }, Rate = 8, Life = { 1, 2 }, Speed = { 0.3, 1 }, Size = { 0.6, 0 }, Light = 1, Accel = Vector3.new(0, 1, 0) },
		Glow = Color3.fromRGB(255, 225, 150),
		AlwaysGlow = true,
	},
	Shadow = {
		{ Where = "Wings", Texture = SMOKE, Colors = { Color3.fromRGB(40, 25, 55), Color3.fromRGB(10, 6, 14) }, Rate = 10, Life = { 1.5, 2.5 }, Speed = { 0.5, 1.5 }, Size = { 3, 7 }, Light = 0, Accel = Vector3.new(0, 1, 0), Transparency = 0.5 },
		{ Where = "Tail", Texture = SMOKE, Colors = { Color3.fromRGB(35, 20, 50), Color3.fromRGB(8, 5, 12) }, Rate = 6, Life = { 1.5, 2.5 }, Speed = { 0.5, 1 }, Size = { 2.5, 6 }, Light = 0, Accel = Vector3.new(0, 1, 0), Transparency = 0.5 },
		{ Where = "Aura", Texture = SPARK, Colors = { Color3.fromRGB(180, 120, 255), Color3.fromRGB(110, 60, 200) }, Rate = 4, Life = { 1.5, 2.5 }, Speed = { 0.5, 1 }, Size = { 0.35, 0 }, Light = 1, Accel = Vector3.zero },
	},
}

local RARITY_RATE = { Common = 0.35, Uncommon = 0.5, Rare = 0.75, Epic = 1, Legendary = 1.4, Mythic = 2 }

local function modelsFolder(): Instance?
	return ReplicatedStorage:FindFirstChild("DragonModels")
end

local function findTemplate(speciesId: string): Model?
	local folder = modelsFolder()
	if not folder then
		return nil
	end
	local exact = folder:FindFirstChild(speciesId)
	if exact then
		return exact :: Model
	end
	-- Fallback while the roster is being made: same element, else anything.
	local species = DragonCatalog.Get(speciesId)
	for _, model in folder:GetChildren() do
		if species and model:GetAttribute("Element") == species.Element then
			return model :: Model
		end
	end
	return folder:FindFirstChildWhichIsA("Model")
end

local function emitterTargets(model: Model, where: string): { Instance }
	local root = model.PrimaryPart :: BasePart
	if where == "Aura" then
		return { root:FindFirstChild("AuraAttachment") }
	elseif where == "Mouth" then
		return { root:FindFirstChild("MouthAttachment") }
	elseif where == "Wings" then
		return { model:FindFirstChild("LeftWing"), model:FindFirstChild("RightWing") }
	elseif where == "Tail" then
		return { model:FindFirstChild("Tail") }
	elseif where == "Body" then
		return { model:FindFirstChild("Body") }
	end
	return {}
end

local function addEffects(model: Model, element: string, rarity: string, scale: number)
	local recipes = EFFECTS[element]
	if not recipes then
		return
	end
	local rateScale = (RARITY_RATE[rarity] or 0.5) * (if scale < 1 then 0.6 else 1)
	for i, spec in ipairs(recipes) do
		for _, target in emitterTargets(model, spec.Where) do
			if target then
				local e = Instance.new("ParticleEmitter")
				e.Name = element .. "Effect" .. i
				e.Texture = spec.Texture
				e.Color = ColorSequence.new(spec.Colors[1], spec.Colors[2])
				e.LightEmission = spec.Light
				e.Rate = spec.Rate * rateScale
				e.Lifetime = NumberRange.new(spec.Life[1], spec.Life[2])
				e.Speed = NumberRange.new(spec.Speed[1] * scale, spec.Speed[2] * scale)
				e.SpreadAngle = Vector2.new(180, 180)
				e.Acceleration = spec.Accel * scale
				e.Size = NumberSequence.new(spec.Size[1] * scale, spec.Size[2] * scale)
				e.Transparency = NumberSequence.new(spec.Transparency or 0.15, 1)
				e.Drag = 1
				if spec.Rotation then
					e.Rotation = NumberRange.new(0, 360)
					e.RotSpeed = NumberRange.new(-90, 90)
				end
				if target:IsA("BasePart") then
					e.Shape = Enum.ParticleEmitterShape.Box
					e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
				end
				e.Parent = target
			end
		end
	end

	local root = model.PrimaryPart :: BasePart
	local info = Rarities.Info[rarity]
	local glowColor = recipes.Glow
	if glowColor and ((info and info.Rank >= 4) or recipes.AlwaysGlow) then
		local light = Instance.new("PointLight")
		light.Name = "ElementGlow"
		light.Color = glowColor
		light.Brightness = if info and info.Rank >= 6 then 2 elseif info and info.Rank >= 5 then 1.4 else 0.8
		light.Range = 22 * scale + 6
		light.Shadows = false
		light.Parent = root
	end
end

-- dragon = { Species, Rarity, ... } from the save. mode = "Ride" | "Station".
function DragonVisuals.Build(dragon: any, mode: string): Model?
	local species = DragonCatalog.Get(dragon.Species)
	local template = species and findTemplate(species.Id)
	if not species or not template then
		return nil
	end
	local model = template:Clone()
	model:SetAttribute("Species", species.Id)
	model:SetAttribute("Element", species.Element)
	model:SetAttribute("Rarity", dragon.Rarity)
	local scale = if mode == "Station" then DragonVisuals.StationScale else 1
	if scale ~= 1 then
		model:ScaleTo(model:GetScale() * scale)
		model:SetAttribute("FootOffset", (model:GetAttribute("FootOffset") or 6) * scale)
		model:SetAttribute("Length", (model:GetAttribute("Length") or 36) * scale)
	end
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.CanCollide = false
			part.CanTouch = false
			part.CanQuery = false
			part.CastShadow = mode == "Ride" and part.Name ~= "Root"
		end
	end
	addEffects(model, species.Element, dragon.Rarity, scale)
	return model
end

DragonVisuals.Effects = EFFECTS
-- Dragon styles (Robux cosmetics): a trail along each wingtip and/or an aura of
-- particles around the body. Looks only.
function DragonVisuals.ApplyCosmetics(model: Model, trailId: string?, auraId: string?)
	local root = model.PrimaryPart
	if not root then
		return
	end
	local scale = (model:GetAttribute("Length") or 36) / 36
	local trail = CosmeticCatalog.Get(trailId)
	if trail and trail.Kind == "Trail" then
		for _, name in { "LeftWing", "RightWing" } do
			local wing = model:FindFirstChild(name)
			if wing and wing:IsA("BasePart") then
				-- The wing's longest axis is its span; the tip is the end away from the body.
				local size = wing.Size
				local axis = if size.X >= size.Y and size.X >= size.Z then Vector3.xAxis
					elseif size.Y >= size.Z then Vector3.yAxis
					else Vector3.zAxis
				local half = (size * axis).Magnitude / 2
				local away = wing.CFrame:VectorToObjectSpace(wing.Position - root.Position)
				local sign = if away:Dot(axis) >= 0 then 1 else -1
				local outer = Instance.new("Attachment")
				outer.Name = "StyleTrailTip"
				outer.Position = axis * half * 0.92 * sign
				outer.Parent = wing
				local inner = Instance.new("Attachment")
				inner.Name = "StyleTrailBase"
				inner.Position = axis * half * 0.62 * sign
				inner.Parent = wing
				local t = Instance.new("Trail")
				t.Name = "StyleTrail"
				t.Attachment0 = outer
				t.Attachment1 = inner
				t.Color = ColorSequence.new(trail.Colors[1], trail.Colors[2])
				t.Transparency = NumberSequence.new(0.15, 1)
				t.LightEmission = 0.7
				t.Lifetime = 0.7
				t.MinLength = 0.2
				t.Parent = wing
			end
		end
	end
	local aura = CosmeticCatalog.Get(auraId)
	if aura and aura.Kind == "Aura" then
		local body = model:FindFirstChild("Body")
		local holder = if body and body:IsA("BasePart") then body else root
		local e = Instance.new("ParticleEmitter")
		e.Name = "StyleAura"
		e.Texture = SPARK
		e.Color = ColorSequence.new(aura.Colors[1], aura.Colors[2])
		e.LightEmission = 1
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.6 * scale), NumberSequenceKeypoint.new(1, 0) })
		e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
		e.Lifetime = NumberRange.new(1.2, 1.8)
		e.Speed = NumberRange.new(1, 4)
		e.SpreadAngle = Vector2.new(180, 180)
		e.Shape = Enum.ParticleEmitterShape.Box
		e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
		e.Rate = 24
		e.Parent = holder
	end
end

return DragonVisuals
