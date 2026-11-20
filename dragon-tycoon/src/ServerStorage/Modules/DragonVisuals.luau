-- ServerStorage/Modules/DragonVisuals
-- Builds the 3D model for one of a player's dragons, ready to animate:
--   * the species' realistic model from ReplicatedStorage/DragonModels
--   * element effects on the dragon's anatomy (Shared/DragonElementalVFX): ambient
--     particles, breath, wing trails, tail tip, chest glow, landing dust
--   * rarity makes the effects denser, and Legendary/Mythic dragons glow brighter
--   * station dragons can be petted (a prompt; the reaction plays on every client)
--   * size: "Ride" is full size, "Station" is scaled down to fit station slots

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared

local DragonCatalog = require(Shared.DragonCatalog)
local Rarities = require(Shared.Rarities)
local CosmeticCatalog = require(Shared.CosmeticCatalog)
local DragonElementalVFX = require(Shared.DragonElementalVFX)

local DragonVisuals = {}

DragonVisuals.StationScale = 0.4 -- (classic 36-stud models) station dragons are 40% size
DragonVisuals.StationLength = 14.4 -- station dragons are this long, whatever the ride size

local SPARK = "rbxasset://textures/particles/sparkles_main.dds"

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

-- Petting (station dragons): a prompt anyone can use; every client sees the
-- happy reaction because it travels as a model attribute (Action = "Pet@<time>").
-- TUNING: PET_COOLDOWN seconds between pets of the same dragon.
local PET_COOLDOWN = 2.5
local function addPetPrompt(model: Model, speciesName: string)
	local root = model.PrimaryPart
	if not root then
		return
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "PetPrompt"
	prompt.ActionText = "Pet"
	prompt.ObjectText = speciesName
	prompt.KeyboardKeyCode = Enum.KeyCode.F
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Style = Enum.ProximityPromptStyle.Default
	prompt.Parent = root
	local last = 0
	prompt.Triggered:Connect(function()
		local now = os.clock()
		if now - last < PET_COOLDOWN then
			return
		end
		last = now
		model:SetAttribute("Action", string.format("Pet@%.3f", workspace:GetServerTimeNow()))
	end)
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
	-- Station dragons are a fixed length, so bigger ride models don't crowd the plots.
	local scale = if mode == "Station"
		then DragonVisuals.StationLength / ((template:GetAttribute("Length") :: number?) or 36)
		else 1
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
	DragonElementalVFX.Apply(model, species.Element, dragon.Rarity, scale, mode)
	if mode == "Station" then
		addPetPrompt(model, species.Name)
	end
	return model
end

DragonVisuals.Effects = DragonElementalVFX.Presets
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
