-- ReplicatedStorage/Client/VikingModels
-- Procedural 3D miniature Viking models for ViewportFrame UI icons, modal
-- crests, currency badges, figureheads, and the articulated hollow Dragon Egg.
-- Crafted to match hud.jpeg & shop.jpeg and deliver realistic eggshell cracking.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local VikingModels = {}

type SpinEntry = {
	Camera: Camera,
	Center: Vector3,
	Distance: number,
	Height: number,
	Angle: number,
	BaseAngle: number,
	Speed: number,
	HoverSpeed: number,
	Hovered: boolean,
}

local spinning: { [ViewportFrame]: SpinEntry } = {}

local function part(parent: Instance, props: { [string]: any }): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CastShadow = false
	for k, v in props do
		(p :: any)[k] = v
	end
	p.Parent = parent
	return p
end

local function wedge(parent: Instance, props: { [string]: any }): WedgePart
	local w = Instance.new("WedgePart")
	w.Anchored = true
	w.CanCollide = false
	w.TopSurface = Enum.SurfaceType.Smooth
	w.BottomSurface = Enum.SurfaceType.Smooth
	w.CastShadow = false
	for k, v in props do
		(w :: any)[k] = v
	end
	w.Parent = parent
	return w
end

local function mesh(parent: Instance, meshType: Enum.MeshType, scale: Vector3?): SpecialMesh
	local m = Instance.new("SpecialMesh")
	m.MeshType = meshType
	if scale then
		m.Scale = scale
	end
	m.Parent = parent
	return m
end

-- Viking material palette tuned for crisp readability inside small viewports
local OAK = Color3.fromRGB(146, 94, 52)
local DARK_OAK = Color3.fromRGB(84, 52, 30)
local LEATHER = Color3.fromRGB(132, 74, 38)
local DARK_LEATHER = Color3.fromRGB(78, 42, 22)
local STRAW = Color3.fromRGB(178, 134, 72)
local TWIG = Color3.fromRGB(108, 72, 42)
local IRON = Color3.fromRGB(168, 176, 190)
local DARK_IRON = Color3.fromRGB(82, 88, 98)
local CHARCOAL_IRON = Color3.fromRGB(54, 58, 66)
local STEEL = Color3.fromRGB(232, 238, 248)
local GOLD = Color3.fromRGB(255, 206, 82)
local BRONZE = Color3.fromRGB(208, 148, 64)
local CRIMSON = Color3.fromRGB(198, 48, 38)
local DEEP_CRIMSON = Color3.fromRGB(128, 28, 24)
local RUNE_MAGENTA = Color3.fromRGB(224, 120, 255)
local CRYSTAL_WHITE = Color3.fromRGB(244, 236, 255)
local IVORY = Color3.fromRGB(246, 236, 214)

-- Helper: builds a woven twig & straw nest ring around (0, centerY, 0)
local function buildNestInto(parent: Instance, centerY: number, radius: number)
	local count = 14
	for i = 1, count do
		local a = (math.pi * 2 / count) * i
		local r = radius * (0.94 + (i % 3) * 0.04)
		local nx, nz = math.cos(a) * r, math.sin(a) * r
		part(parent, {
			Size = Vector3.new(0.24, 0.22, 0.82),
			Material = Enum.Material.Wood,
			Color = if i % 2 == 0 then TWIG else STRAW,
			CFrame = CFrame.lookAt(Vector3.new(nx, centerY + (i % 2) * 0.06, nz), Vector3.new(nx - math.sin(a), centerY + 0.08, nz + math.cos(a)))
				* CFrame.Angles(math.rad((i % 3 - 1) * 9), 0, math.rad(14)),
		})
	end
	for i = 1, 10 do
		local a = (math.pi * 2 / 10) * i + 0.25
		local r = radius * 0.78
		local nx, nz = math.cos(a) * r, math.sin(a) * r
		part(parent, {
			Size = Vector3.new(0.18, 0.16, 0.68),
			Material = Enum.Material.Grass,
			Color = STRAW,
			CFrame = CFrame.lookAt(Vector3.new(nx, centerY + 0.12, nz), Vector3.new(nx - math.sin(a), centerY + 0.16, nz + math.cos(a))),
		})
	end
	local bed = part(parent, {
		Size = Vector3.new(radius * 1.65, 0.26, radius * 1.65),
		Material = Enum.Material.Grass,
		Color = Color3.fromRGB(150, 110, 56),
		CFrame = CFrame.new(0, centerY - 0.06, 0),
	})
	mesh(bed, Enum.MeshType.Sphere)
end

VikingModels.BuildNestInto = buildNestInto

-- Clones the real 3D egg model from ReplicatedStorage.EggModels[eggId], strips
-- particles/scripts, and centers its bounding box cleanly at (0, 0, 0).
function VikingModels.CloneEggModel(eggId: string?, fallbackColor: Color3?): (Model, Vector3, Color3)
	local folder = ReplicatedStorage:FindFirstChild("EggModels")
	local template = folder and folder:FindFirstChild(eggId or "Hatchling")
	if not template and folder then
		template = folder:FindFirstChild("Hatchling")
	end

	local shellColor = fallbackColor or Color3.fromRGB(228, 210, 178)
	if template and template:IsA("Model") then
		local clone = template:Clone()
		for _, d in clone:GetDescendants() do
			if d:IsA("ParticleEmitter") or d:IsA("Light") or d:IsA("Script") or d:IsA("LocalScript") then
				d:Destroy()
			elseif d:IsA("BasePart") then
				d.Anchored = true
				d.CanCollide = false
				d.CastShadow = false
				if fallbackColor == nil then
					shellColor = d.Color
				end
			end
		end
		local cf, size = clone:GetBoundingBox()
		clone:PivotTo(clone:GetPivot() - cf.Position)
		return clone, size, shellColor
	end

	-- Fallback ovoid only when EggModels is absent
	local fallback = Instance.new("Model")
	fallback.Name = eggId or "FallbackEgg"
	local body = part(fallback, {
		Size = Vector3.new(2.95, 4.0, 2.95),
		Material = Enum.Material.SmoothPlastic,
		Color = shellColor,
		CFrame = CFrame.identity,
	})
	mesh(body, Enum.MeshType.Sphere)
	fallback.PrimaryPart = body
	return fallback, body.Size, shellColor
end

-- 1. EGGS: Real Hatchling Dragon Egg nestled in a woven twig nest (hud.jpeg)
local function buildEggsDockModel(): Model
	local model = Instance.new("Model")
	model.Name = "VikingEggsDock"

	local folder = ReplicatedStorage:FindFirstChild("EggModels")
	local realTemplate = folder and folder:FindFirstChild("Hatchling")
	if realTemplate and realTemplate:IsA("Model") then
		local realEgg, sz = VikingModels.CloneEggModel("Hatchling")
		local scale = 2.04 / math.max(sz.Y, 0.1)
		realEgg:ScaleTo(realEgg:GetScale() * scale)
		local cf2, _ = realEgg:GetBoundingBox()
		realEgg:PivotTo((realEgg:GetPivot() - cf2.Position) * CFrame.new(0, 0.22, 0) * CFrame.Angles(0, 0, math.rad(-4)))
		realEgg.Parent = model
		local primary = realEgg.PrimaryPart or realEgg:FindFirstChildWhichIsA("BasePart", true)
		if primary then
			model.PrimaryPart = primary
		end
		buildNestInto(model, -0.52, 0.98)
		return model
	end

	local eggBaseColor = Color3.fromRGB(238, 224, 196)
	local speckleColor = Color3.fromRGB(134, 88, 54)
	local egg = part(model, {
		Size = Vector3.new(1.56, 2.04, 1.56),
		Material = Enum.Material.SmoothPlastic,
		Color = eggBaseColor,
		CFrame = CFrame.new(0, 0.22, 0) * CFrame.Angles(0, 0, math.rad(-4)),
	})
	mesh(egg, Enum.MeshType.Sphere)
	model.PrimaryPart = egg

	-- Crown cap slightly warmer ivory
	local crown = part(model, {
		Size = Vector3.new(1.24, 1.32, 1.24),
		Material = Enum.Material.SmoothPlastic,
		Color = Color3.fromRGB(248, 238, 214),
		CFrame = egg.CFrame * CFrame.new(0, 0.34, 0),
	})
	mesh(crown, Enum.MeshType.Sphere)

	-- Natural shell speckles hugging the ovoid surface
	local speckles = {
		{ th = 0.2, ph = 0.72, s = 0.22 },
		{ th = -0.45, ph = 0.95, s = 0.28 },
		{ th = 0.65, ph = 1.05, s = 0.24 },
		{ th = -0.15, ph = 1.25, s = 0.19 },
		{ th = 0.95, ph = 0.82, s = 0.25 },
		{ th = -0.95, ph = 0.88, s = 0.22 },
		{ th = 0.35, ph = 0.48, s = 0.17 },
		{ th = -0.58, ph = 0.56, s = 0.20 },
		{ th = 1.55, ph = 0.92, s = 0.26 },
		{ th = -1.65, ph = 0.96, s = 0.24 },
		{ th = 2.6, ph = 0.85, s = 0.27 },
	}
	for _, sp in speckles do
		local sx = 0.76 * math.sin(sp.ph) * math.sin(sp.th)
		local sy = 0.99 * math.cos(sp.ph)
		local sz = 0.76 * math.sin(sp.ph) * math.cos(sp.th)
		local p = egg.CFrame:PointToWorldSpace(Vector3.new(sx, sy, sz))
		local n = (p - egg.Position).Unit
		local dot = part(model, {
			Size = Vector3.new(sp.s, sp.s * 1.18, 0.08),
			Material = Enum.Material.SmoothPlastic,
			Color = speckleColor,
			CFrame = CFrame.lookAt(p, p + n),
		})
		mesh(dot, Enum.MeshType.Sphere)
	end

	buildNestInto(model, -0.46, 0.96)
	return model
end

-- 2. DRAGONS: Fierce Crimson & Gold Horned Dragon Bust on Shield Crest (hud.jpeg)
local function buildDragonModel(): Model
	local model = Instance.new("Model")
	model.Name = "VikingDragon"

	-- Shield backing crest
	local crest = part(model, {
		Size = Vector3.new(1.85, 2.05, 0.24),
		Material = Enum.Material.WoodPlanks,
		Color = DARK_OAK,
		CFrame = CFrame.new(0, 0.02, 0.48),
	})
	mesh(crest, Enum.MeshType.Sphere, Vector3.new(1, 1.05, 0.5))
	local rim = part(model, {
		Size = Vector3.new(2.02, 2.22, 0.18),
		Material = Enum.Material.Metal,
		Color = BRONZE,
		CFrame = CFrame.new(0, 0.02, 0.52),
	})
	mesh(rim, Enum.MeshType.Sphere, Vector3.new(1, 1.05, 0.45))

	-- Muscular arched neck
	local neck = part(model, {
		Size = Vector3.new(0.82, 1.25, 0.86),
		Material = Enum.Material.SmoothPlastic,
		Color = DEEP_CRIMSON,
		CFrame = CFrame.new(0, -0.42, 0.12) * CFrame.Angles(math.rad(22), 0, 0),
	})
	model.PrimaryPart = neck

	-- Golden chest plates
	for i = 1, 3 do
		part(model, {
			Size = Vector3.new(0.58 - i * 0.05, 0.22, 0.24),
			Material = Enum.Material.Metal,
			Color = GOLD,
			CFrame = CFrame.new(0, -0.12 - i * 0.24, -0.26 + i * 0.04) * CFrame.Angles(math.rad(18), 0, 0),
		})
	end

	-- Sculpted Dragon Head + Snout + Jaw
	local headCF = CFrame.new(0, 0.34, -0.08) * CFrame.Angles(math.rad(8), math.rad(-10), 0)
	part(model, {
		Size = Vector3.new(0.96, 0.78, 1.12),
		Material = Enum.Material.SmoothPlastic,
		Color = CRIMSON,
		CFrame = headCF,
	})
	wedge(model, {
		Size = Vector3.new(0.72, 0.48, 0.96),
		Material = Enum.Material.SmoothPlastic,
		Color = CRIMSON,
		CFrame = headCF * CFrame.new(0, 0.02, -0.88),
	})
	part(model, {
		Size = Vector3.new(0.62, 0.24, 0.88),
		Material = Enum.Material.SmoothPlastic,
		Color = DEEP_CRIMSON,
		CFrame = headCF * CFrame.new(0, -0.34, -0.72) * CFrame.Angles(math.rad(-16), 0, 0),
	})

	-- Swept golden horns, blazing eyes, and flared crimson wing-crests
	for _, side in { -1, 1 } do
		part(model, {
			Size = Vector3.new(0.22, 1.18, 0.24),
			Material = Enum.Material.Metal,
			Color = GOLD,
			CFrame = headCF * CFrame.new(side * 0.42, 0.56, 0.38) * CFrame.Angles(math.rad(-46), 0, math.rad(side * -24)),
		})
		wedge(model, {
			Size = Vector3.new(0.16, 0.62, 0.22),
			Material = Enum.Material.Metal,
			Color = IVORY,
			CFrame = headCF * CFrame.new(side * 0.62, 0.98, 0.78) * CFrame.Angles(math.rad(-54), 0, math.rad(side * -28)),
		})
		part(model, {
			Size = Vector3.new(0.18, 0.16, 0.26),
			Material = Enum.Material.Neon,
			Color = Color3.fromRGB(255, 204, 64),
			CFrame = headCF * CFrame.new(side * 0.44, 0.12, -0.34),
		})
		wedge(model, {
			Size = Vector3.new(0.14, 1.32, 0.92),
			Material = Enum.Material.SmoothPlastic,
			Color = CRIMSON,
			CFrame = CFrame.new(side * 0.86, 0.12, 0.28) * CFrame.Angles(math.rad(12), math.rad(side * 52), math.rad(side * -28)),
		})
	end
	return model
end

-- 3. STATIONS: Heavy Forged Steel Blacksmith Anvil on Iron-Banded Oak Stump (hud.jpeg)
local function buildStationsModel(): Model
	local model = Instance.new("Model")
	model.Name = "VikingStations"

	-- Heavy oak timber block + iron band
	local stump = part(model, {
		Size = Vector3.new(0.92, 1.72, 1.72),
		Shape = Enum.PartType.Cylinder,
		Material = Enum.Material.Wood,
		Color = OAK,
		CFrame = CFrame.new(0, -0.68, 0) * CFrame.Angles(0, 0, math.rad(90)),
	})
	model.PrimaryPart = stump
	part(model, {
		Size = Vector3.new(0.18, 1.78, 1.78),
		Shape = Enum.PartType.Cylinder,
		Material = Enum.Material.Metal,
		Color = DARK_IRON,
		CFrame = CFrame.new(0, -0.46, 0) * CFrame.Angles(0, 0, math.rad(90)),
	})

	-- Anvil base feet + waist + bright steel face + tapered horn
	part(model, {
		Size = Vector3.new(1.52, 0.32, 1.02),
		Material = Enum.Material.Metal,
		Color = DARK_IRON,
		CFrame = CFrame.new(0.05, -0.08, 0),
	})
	part(model, {
		Size = Vector3.new(0.96, 0.46, 0.72),
		Material = Enum.Material.Metal,
		Color = DARK_IRON,
		CFrame = CFrame.new(0.06, 0.26, 0),
	})
	part(model, {
		Size = Vector3.new(1.78, 0.44, 0.88),
		Material = Enum.Material.Metal,
		Color = IRON,
		CFrame = CFrame.new(0.18, 0.62, 0),
	})
	part(model, {
		Size = Vector3.new(1.74, 0.10, 0.84),
		Material = Enum.Material.Metal,
		Color = STEEL,
		CFrame = CFrame.new(0.18, 0.84, 0),
	})
	-- Classic conical/wedge blacksmith horn pointing left
	wedge(model, {
		Size = Vector3.new(0.76, 0.40, 0.96),
		Material = Enum.Material.Metal,
		Color = IRON,
		CFrame = CFrame.new(-1.12, 0.64, 0) * CFrame.Angles(0, math.rad(90), math.rad(180)),
	})
	return model
end

-- 4. RIDE: Tooled Leather Dragon Saddle + Stirrups + Sweeping Silver Wings (hud.jpeg)
local function buildRideModel(): Model
	local model = Instance.new("Model")
	model.Name = "VikingRide"

	-- Saddle seat, raised pommel, high cantle & bronze trim
	local seat = part(model, {
		Size = Vector3.new(1.08, 0.38, 1.32),
		Material = Enum.Material.SmoothPlastic,
		Color = LEATHER,
		CFrame = CFrame.new(0, -0.02, 0),
	})
	model.PrimaryPart = seat

	part(model, {
		Size = Vector3.new(0.92, 0.56, 0.34),
		Material = Enum.Material.SmoothPlastic,
		Color = DARK_LEATHER,
		CFrame = CFrame.new(0, 0.32, -0.52) * CFrame.Angles(math.rad(-22), 0, 0),
	})
	part(model, {
		Size = Vector3.new(1.04, 0.64, 0.36),
		Material = Enum.Material.SmoothPlastic,
		Color = DARK_LEATHER,
		CFrame = CFrame.new(0, 0.36, 0.54) * CFrame.Angles(math.rad(26), 0, 0),
	})
	part(model, {
		Size = Vector3.new(0.98, 0.12, 0.38),
		Material = Enum.Material.Metal,
		Color = GOLD,
		CFrame = CFrame.new(0, 0.62, -0.56) * CFrame.Angles(math.rad(-22), 0, 0),
	})

	-- Saddle flaps, leather straps, iron stirrups, and sweeping silver-white wings
	for _, side in { -1, 1 } do
		part(model, {
			Size = Vector3.new(0.18, 0.88, 0.94),
			Material = Enum.Material.SmoothPlastic,
			Color = LEATHER,
			CFrame = CFrame.new(side * 0.56, -0.38, 0.02) * CFrame.Angles(0, 0, math.rad(side * -14)),
		})
		part(model, {
			Size = Vector3.new(0.08, 0.72, 0.14),
			Material = Enum.Material.SmoothPlastic,
			Color = DARK_LEATHER,
			CFrame = CFrame.new(side * 0.66, -0.62, -0.04),
		})
		part(model, {
			Size = Vector3.new(0.12, 0.28, 0.34),
			Material = Enum.Material.Metal,
			Color = IRON,
			CFrame = CFrame.new(side * 0.68, -1.02, -0.04),
		})

		-- Sweeping layered silver-ivory wings rising from each side
		for feather = 1, 4 do
			local lift = 0.24 + (4 - feather) * 0.24
			local span = 1.48 - feather * 0.18
			wedge(model, {
				Size = Vector3.new(0.16, 0.32, span),
				Material = Enum.Material.SmoothPlastic,
				Color = if feather <= 2 then STEEL else Color3.fromRGB(204, 212, 226),
				CFrame = CFrame.new(side * (0.64 + (5 - feather) * 0.20), lift, 0.12 + feather * 0.06)
					* CFrame.Angles(math.rad(12), math.rad(side * 76), math.rad(side * (36 - feather * 9))),
			})
		end
	end
	return model
end

-- 5. BATTLE: Round Oak & Iron Viking Shield + Crossed Bearded Battle-Axes (hud.jpeg)
local function buildBattleModel(): Model
	local model = Instance.new("Model")
	model.Name = "VikingBattle"

	local shieldCF = CFrame.new(0, -0.08, -0.14) * CFrame.Angles(math.rad(-5), 0, 0)
	local body = part(model, {
		Size = Vector3.new(0.24, 2.04, 2.04),
		Shape = Enum.PartType.Cylinder,
		Material = Enum.Material.WoodPlanks,
		Color = OAK,
		CFrame = shieldCF * CFrame.Angles(0, math.rad(90), 0),
	})
	model.PrimaryPart = body

	-- Iron shield rim + central steel boss + rivets
	part(model, {
		Size = Vector3.new(0.20, 2.26, 2.26),
		Shape = Enum.PartType.Cylinder,
		Material = Enum.Material.Metal,
		Color = IRON,
		CFrame = shieldCF * CFrame.Angles(0, math.rad(90), 0),
	})
	part(model, {
		Size = Vector3.new(0.27, 1.92, 0.34),
		Material = Enum.Material.Metal,
		Color = BRONZE,
		CFrame = shieldCF,
	})
	local boss = part(model, {
		Size = Vector3.new(0.74, 0.74, 0.56),
		Material = Enum.Material.Metal,
		Color = STEEL,
		CFrame = shieldCF * CFrame.new(0, 0, -0.16),
	})
	mesh(boss, Enum.MeshType.Sphere)

	-- Twin crossed bearded Viking battle-axes behind the shield
	for _, side in { -1, 1 } do
		local axeCF = CFrame.new(side * 0.06, 0.06, 0.28) * CFrame.Angles(0, 0, math.rad(side * -38))
		-- Ash wood haft
		part(model, {
			Size = Vector3.new(0.20, 3.05, 0.20),
			Material = Enum.Material.Wood,
			Color = DARK_OAK,
			CFrame = axeCF,
		})
		-- Forged bearded axe head flaring outward at top
		part(model, {
			Size = Vector3.new(0.68, 0.46, 0.16),
			Material = Enum.Material.Metal,
			Color = DARK_IRON,
			CFrame = axeCF * CFrame.new(side * 0.28, 1.12, 0),
		})
		wedge(model, {
			Size = Vector3.new(0.18, 0.96, 0.58),
			Material = Enum.Material.Metal,
			Color = STEEL,
			CFrame = axeCF * CFrame.new(side * 0.68, 1.02, 0) * CFrame.Angles(0, math.rad(side * 90), 0),
		})
	end
	return model
end

-- 6. SHOP: Iron-Bound Wooden Treasure Chest + Spilling Gold Coins (hud.jpeg)
local function buildShopModel(): Model
	local model = Instance.new("Model")
	model.Name = "VikingShop"

	local chestCF = CFrame.new(-0.08, -0.18, 0.06) * CFrame.Angles(0, math.rad(-18), 0)
	local base = part(model, {
		Size = Vector3.new(1.94, 1.02, 1.32),
		Material = Enum.Material.WoodPlanks,
		Color = OAK,
		CFrame = chestCF,
	})
	model.PrimaryPart = base

	-- Slightly cracked-open arched lid with warm golden treasure glow inside
	part(model, {
		Size = Vector3.new(1.74, 0.36, 1.12),
		Material = Enum.Material.Neon,
		Color = Color3.fromRGB(255, 208, 76),
		CFrame = chestCF * CFrame.new(0, 0.48, -0.04),
	})
	local lidCF = chestCF * CFrame.new(0, 0.62, 0.12) * CFrame.Angles(math.rad(-18), 0, 0)
	part(model, {
		Size = Vector3.new(1.98, 0.56, 1.36),
		Material = Enum.Material.WoodPlanks,
		Color = OAK,
		CFrame = lidCF,
	})
	-- Forged iron straps + brass lockplate
	for _, x in { -0.68, 0.68 } do
		part(model, {
			Size = Vector3.new(0.22, 1.08, 1.38),
			Material = Enum.Material.Metal,
			Color = DARK_IRON,
			CFrame = chestCF * CFrame.new(x, 0, 0),
		})
		part(model, {
			Size = Vector3.new(0.24, 0.62, 1.42),
			Material = Enum.Material.Metal,
			Color = DARK_IRON,
			CFrame = lidCF * CFrame.new(x, 0, 0),
		})
	end
	part(model, {
		Size = Vector3.new(0.38, 0.46, 0.22),
		Material = Enum.Material.Metal,
		Color = GOLD,
		CFrame = chestCF * CFrame.new(0, 0.22, -0.68),
	})

	-- Scattered stack of gold coins beside chest front-right
	local coinOffsets = {
		Vector3.new(0.88, -0.58, -0.58),
		Vector3.new(0.92, -0.44, -0.54),
		Vector3.new(0.56, -0.62, -0.78),
		Vector3.new(1.12, -0.62, -0.28),
	}
	for _, off in coinOffsets do
		part(model, {
			Size = Vector3.new(0.14, 0.52, 0.52),
			Shape = Enum.PartType.Cylinder,
			Material = Enum.Material.Metal,
			Color = GOLD,
			CFrame = CFrame.new(off) * CFrame.Angles(0, 0, math.rad(90)),
		})
	end
	return model
end

-- 7. MERCHANT STALL: Carved Viking Market Booth for Merchant Hall Header (shop.jpeg)
local function buildMerchantStallModel(): Model
	local model = Instance.new("Model")
	model.Name = "VikingMerchantStall"

	local counter = part(model, {
		Size = Vector3.new(2.1, 0.86, 1.15),
		Material = Enum.Material.WoodPlanks,
		Color = OAK,
		CFrame = CFrame.new(0, -0.56, 0),
	})
	model.PrimaryPart = counter
	part(model, {
		Size = Vector3.new(2.26, 0.18, 1.3),
		Material = Enum.Material.Wood,
		Color = DARK_OAK,
		CFrame = CFrame.new(0, -0.08, 0),
	})
	for _, x in { -0.88, 0.88 } do
		part(model, {
			Size = Vector3.new(0.18, 1.65, 0.18),
			Material = Enum.Material.Wood,
			Color = DARK_OAK,
			CFrame = CFrame.new(x, 0.42, -0.38),
		})
		part(model, {
			Size = Vector3.new(0.18, 1.65, 0.18),
			Material = Enum.Material.Wood,
			Color = DARK_OAK,
			CFrame = CFrame.new(x, 0.56, 0.38),
		})
	end
	-- Pitched timber awning planks
	for i = -2, 2 do
		part(model, {
			Size = Vector3.new(0.44, 0.16, 1.48),
			Material = Enum.Material.WoodPlanks,
			Color = if i % 2 == 0 then BRONZE else OAK,
			CFrame = CFrame.new(i * 0.44, 1.18, 0) * CFrame.Angles(math.rad(16), 0, 0),
		})
	end
	return model
end

-- 8. COINS: Embossed Golden Viking Coin with Stamped Bearded Axe (hud.jpeg)
local function buildCoinsModel(): Model
	local model = Instance.new("Model")
	model.Name = "VikingCoins"

	local coinCF = CFrame.Angles(0, math.rad(90), 0)
	local rim = part(model, {
		Size = Vector3.new(0.32, 2.28, 2.28),
		Shape = Enum.PartType.Cylinder,
		Material = Enum.Material.Metal,
		Color = BRONZE,
		CFrame = coinCF,
	})
	model.PrimaryPart = rim
	part(model, {
		Size = Vector3.new(0.38, 1.88, 1.88),
		Shape = Enum.PartType.Cylinder,
		Material = Enum.Material.Metal,
		Color = GOLD,
		CFrame = coinCF,
	})
	-- Embossed Viking axe relief on the front face
	part(model, {
		Size = Vector3.new(0.16, 1.26, 0.14),
		Material = Enum.Material.Metal,
		Color = BRONZE,
		CFrame = CFrame.new(0, -0.04, -0.18) * CFrame.Angles(0, 0, math.rad(-22)),
	})
	wedge(model, {
		Size = Vector3.new(0.16, 0.68, 0.52),
		Material = Enum.Material.Metal,
		Color = Color3.fromRGB(255, 236, 142),
		CFrame = CFrame.new(0.24, 0.24, -0.20) * CFrame.Angles(0, math.rad(90), math.rad(-22)),
	})
	return model
end

-- 9. ESSENCE: Glowing Pale-Violet Rune Crystal Shard with Fehu Rune (hud.jpeg)
local function buildEssenceModel(): Model
	local model = Instance.new("Model")
	model.Name = "VikingEssence"

	-- Dark stone socket ring behind crystal
	part(model, {
		Size = Vector3.new(0.22, 2.1, 2.1),
		Shape = Enum.PartType.Cylinder,
		Material = Enum.Material.Metal,
		Color = CHARCOAL_IRON,
		CFrame = CFrame.new(0, 0, 0.28) * CFrame.Angles(0, math.rad(90), 0),
	})

	local core = part(model, {
		Size = Vector3.new(1.06, 1.72, 0.72),
		Material = Enum.Material.Neon,
		Color = CRYSTAL_WHITE,
		CFrame = CFrame.Angles(0, 0, math.rad(-6)),
	})
	mesh(core, Enum.MeshType.Sphere, Vector3.new(0.92, 1.16, 0.75))
	model.PrimaryPart = core

	-- Faceted violet aura rim
	local aura = part(model, {
		Size = Vector3.new(1.28, 1.98, 0.56),
		Material = Enum.Material.Neon,
		Color = RUNE_MAGENTA,
		Transparency = 0.35,
		CFrame = CFrame.new(0, 0, 0.06) * CFrame.Angles(0, 0, math.rad(-6)),
	})
	mesh(aura, Enum.MeshType.Sphere, Vector3.new(0.95, 1.18, 0.65))

	-- Etched Norse Fehu (ᚠ) rune strokes on front face
	local runeColor = Color3.fromRGB(168, 56, 224)
	part(model, {
		Size = Vector3.new(0.11, 1.02, 0.12),
		Material = Enum.Material.SmoothPlastic,
		Color = runeColor,
		CFrame = CFrame.new(-0.08, -0.02, -0.34),
	})
	part(model, {
		Size = Vector3.new(0.10, 0.48, 0.12),
		Material = Enum.Material.SmoothPlastic,
		Color = runeColor,
		CFrame = CFrame.new(0.08, 0.26, -0.34) * CFrame.Angles(0, 0, math.rad(-42)),
	})
	part(model, {
		Size = Vector3.new(0.10, 0.42, 0.12),
		Material = Enum.Material.SmoothPlastic,
		Color = runeColor,
		CFrame = CFrame.new(0.06, 0.02, -0.34) * CFrame.Angles(0, 0, math.rad(-42)),
	})
	return model
end

-- 10. HORN: Curved Viking Drinking/Blowing Horn for Music Toggle (hud.jpeg)
local function buildHornModel(): Model
	local model = Instance.new("Model")
	model.Name = "VikingHorn"

	local center = part(model, { Size = Vector3.new(0.2, 0.2, 0.2), Transparency = 1 })
	model.PrimaryPart = center

	local segs = 7
	for i = 1, segs do
		local t = (i - 1) / (segs - 1)
		local angle = math.rad(-55 + t * 115)
		local r = 0.82
		local px = math.sin(angle) * r
		local py = -math.cos(angle) * r + 0.36
		local thickness = 0.22 + t * 0.56
		local isBand = (i == 2 or i == segs)
		local seg = part(model, {
			Size = Vector3.new(0.42, thickness, thickness),
			Shape = Enum.PartType.Cylinder,
			Material = if isBand then Enum.Material.Metal else Enum.Material.SmoothPlastic,
			Color = if isBand then GOLD else Color3.fromRGB(224, 198, 156),
			CFrame = CFrame.new(px, py, 0) * CFrame.Angles(0, 0, angle),
		})
		if i == segs then
			part(model, {
				Size = Vector3.new(0.16, thickness * 0.78, thickness * 0.78),
				Shape = Enum.PartType.Cylinder,
				Material = Enum.Material.SmoothPlastic,
				Color = DARK_OAK,
				CFrame = seg.CFrame * CFrame.new(0.16, 0, 0),
			})
		end
	end
	return model
end

-- 11. DRAGON PROW: Dark Forged-Iron Norse Longship Figurehead for Sheet Corner (shop.jpeg)
local function buildDragonProwModel(): Model
	local model = Instance.new("Model")
	model.Name = "VikingDragonProw"

	local neck = part(model, {
		Size = Vector3.new(0.86, 1.56, 0.54),
		Material = Enum.Material.Metal,
		Color = CHARCOAL_IRON,
		CFrame = CFrame.new(0.28, -0.22, 0) * CFrame.Angles(0, 0, math.rad(28)),
	})
	model.PrimaryPart = neck

	local headCF = CFrame.new(-0.22, 0.48, 0) * CFrame.Angles(0, 0, math.rad(12))
	part(model, {
		Size = Vector3.new(1.18, 0.72, 0.58),
		Material = Enum.Material.Metal,
		Color = DARK_IRON,
		CFrame = headCF,
	})
	wedge(model, {
		Size = Vector3.new(0.54, 0.44, 0.92),
		Material = Enum.Material.Metal,
		Color = IRON,
		CFrame = headCF * CFrame.new(-0.82, 0.08, 0) * CFrame.Angles(0, math.rad(90), 0),
	})
	wedge(model, {
		Size = Vector3.new(0.46, 0.28, 0.78),
		Material = Enum.Material.Metal,
		Color = CHARCOAL_IRON,
		CFrame = headCF * CFrame.new(-0.74, -0.28, 0) * CFrame.Angles(0, math.rad(90), math.rad(-22)),
	})
	wedge(model, {
		Size = Vector3.new(0.32, 0.88, 0.42),
		Material = Enum.Material.Metal,
		Color = IRON,
		CFrame = headCF * CFrame.new(0.38, 0.56, 0) * CFrame.Angles(0, math.rad(-90), math.rad(-36)),
	})
	part(model, {
		Size = Vector3.new(0.18, 0.14, 0.62),
		Material = Enum.Material.Neon,
		Color = BRONZE,
		CFrame = headCF * CFrame.new(-0.24, 0.14, 0),
	})
	return model
end

-- 12. RAID: Horned Elder Skull Emblem
local function buildRaidModel(): Model
	local model = Instance.new("Model")
	model.Name = "VikingRaid"
	local skull = part(model, {
		Size = Vector3.new(1.35, 1.25, 1.35),
		Material = Enum.Material.SmoothPlastic,
		Color = IVORY,
		CFrame = CFrame.new(0, 0, 0),
	})
	mesh(skull, Enum.MeshType.Sphere)
	model.PrimaryPart = skull
	for _, side in { -1, 1 } do
		part(model, {
			Size = Vector3.new(0.32, 1.4, 0.36),
			Material = Enum.Material.Metal,
			Color = GOLD,
			CFrame = CFrame.new(side * 0.68, 0.58, 0.1) * CFrame.Angles(math.rad(18), 0, math.rad(side * -34)),
		})
		part(model, {
			Size = Vector3.new(0.28, 0.26, 0.26),
			Material = Enum.Material.Neon,
			Color = RUNE_MAGENTA,
			CFrame = CFrame.new(side * 0.34, 0.08, -0.58),
		})
	end
	return model
end

local BUILDERS: { [string]: () -> Model } = {
	Eggs = buildEggsDockModel,
	Dragons = buildDragonModel,
	Stations = buildStationsModel,
	Ride = buildRideModel,
	Battle = buildBattleModel,
	Shop = buildShopModel,
	MerchantStall = buildMerchantStallModel,
	Coins = buildCoinsModel,
	Essence = buildEssenceModel,
	Horn = buildHornModel,
	DragonProw = buildDragonProwModel,
	Raid = buildRaidModel,
}

local CLOSENESS: { [string]: number } = {
	Eggs = 0.66,
	Dragons = 0.64,
	Stations = 0.66,
	Ride = 0.62,
	Battle = 0.62,
	Shop = 0.66,
	MerchantStall = 0.66,
	Coins = 0.62,
	Essence = 0.62,
	Horn = 0.64,
	DragonProw = 0.64,
	Raid = 0.68,
}

function VikingModels.ViewportIcon(parent: Instance, kind: string, size: UDim2?, spinSpeed: number?, zIndex: number?, initialYawDeg: number?): ViewportFrame
	local vp = Instance.new("ViewportFrame")
	vp.Name = kind .. "3DIcon"
	vp.Size = size or UDim2.fromScale(1, 1)
	vp.BackgroundTransparency = 1
	vp.Ambient = Color3.fromRGB(224, 212, 198)
	vp.LightColor = Color3.fromRGB(255, 246, 224)
	vp.LightDirection = Vector3.new(-0.45, -0.75, -0.68)
	vp.Active = false
	vp.ZIndex = zIndex or (if parent:IsA("GuiObject") then parent.ZIndex + 1 else 2)
	vp.Parent = parent

	local builder = BUILDERS[kind] or buildBattleModel
	local model = builder()
	model.Parent = vp

	local cam = Instance.new("Camera")
	cam.FieldOfView = 32
	cam.Parent = vp
	vp.CurrentCamera = cam

	local cf, bsize = model:GetBoundingBox()
	local radius = bsize.Magnitude / 2
	local closeness = CLOSENESS[kind] or 0.66
	local dist = radius / math.tan(math.rad(cam.FieldOfView / 2)) * closeness
	local baseAngle = math.rad(initialYawDeg or (if kind == "DragonProw" or kind == "Coins" or kind == "Essence" or kind == "Horn" then 0 else 12))

	local entry: SpinEntry = {
		Camera = cam,
		Center = cf.Position,
		Distance = dist,
		Height = dist * (if kind == "Coins" or kind == "Essence" or kind == "DragonProw" then 0.06 else 0.18),
		Angle = baseAngle,
		BaseAngle = baseAngle,
		Speed = spinSpeed or 0,
		HoverSpeed = 1.6,
		Hovered = false,
	}
	local off = Vector3.new(math.sin(entry.Angle), 0, math.cos(entry.Angle)) * entry.Distance + Vector3.new(0, entry.Height, 0)
	cam.CFrame = CFrame.lookAt(entry.Center + off, entry.Center)

	spinning[vp] = entry
	vp.Destroying:Connect(function()
		spinning[vp] = nil
	end)
	return vp
end

function VikingModels.ViewportEgg(parent: Instance, eggColor: Color3, _accentColor: Color3?, spinSpeed: number?, zIndex: number?, eggId: string?): ViewportFrame
	local vp = Instance.new("ViewportFrame")
	vp.Name = "Egg3DPreview"
	vp.Size = UDim2.fromScale(1, 1)
	vp.BackgroundTransparency = 1
	vp.Ambient = Color3.fromRGB(224, 214, 202)
	vp.LightColor = Color3.fromRGB(255, 248, 228)
	vp.LightDirection = Vector3.new(-0.48, -0.78, -0.65)
	vp.Active = false
	vp.ZIndex = zIndex or (if parent:IsA("GuiObject") then parent.ZIndex + 1 else 2)
	vp.Parent = parent

	local model = VikingModels.CloneEggModel(eggId, eggColor)
	model.Parent = vp

	local cam = Instance.new("Camera")
	cam.FieldOfView = 33
	cam.Parent = vp
	vp.CurrentCamera = cam

	local cf, bsize = model:GetBoundingBox()
	local radius = bsize.Magnitude / 2
	local dist = radius / math.tan(math.rad(cam.FieldOfView / 2)) * 0.78
	local entry: SpinEntry = {
		Camera = cam,
		Center = cf.Position,
		Distance = dist,
		Height = dist * 0.18,
		Angle = math.rad(25),
		BaseAngle = math.rad(25),
		Speed = spinSpeed or 0,
		HoverSpeed = 1.6,
		Hovered = false,
	}
	local off = Vector3.new(math.sin(entry.Angle), 0, math.cos(entry.Angle)) * entry.Distance + Vector3.new(0, entry.Height, 0)
	cam.CFrame = CFrame.lookAt(entry.Center + off, entry.Center)
	spinning[vp] = entry
	vp.Destroying:Connect(function()
		spinning[vp] = nil
	end)
	return vp
end

function VikingModels.SetHovered(vp: ViewportFrame, hovered: boolean)
	local entry = spinning[vp]
	if entry then
		entry.Hovered = hovered
	end
end

RunService.RenderStepped:Connect(function(dt)
	for vp, entry in spinning do
		if vp.Visible and vp.Parent then
			local rate = if entry.Hovered then entry.HoverSpeed else entry.Speed
			if rate ~= 0 then
				entry.Angle += rate * dt
				local off = Vector3.new(math.sin(entry.Angle), 0, math.cos(entry.Angle)) * entry.Distance + Vector3.new(0, entry.Height, 0)
				entry.Camera.CFrame = CFrame.lookAt(entry.Center + off, entry.Center)
			end
		end
	end
end)

return VikingModels
