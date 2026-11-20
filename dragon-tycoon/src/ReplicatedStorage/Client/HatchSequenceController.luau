--!strict
-- ReplicatedStorage/Client/HatchSequenceController
-- Modular 3D World Dragon Egg Cracking, Hatching & Celebration Controller:
--   * Supports both 1-egg single hatch and 4-egg cluster multi-hatch on Plot.Nest
--   * Stage 1 (0.0s - 0.5s): Elastic pedestal drop & rarity-colored Norse rune ignition
--   * Stage 2 (0.5s - 1.8s): 3 escalating damped-harmonic shakes, progressive 3D cracks,
--     shell-chip ParticleEmitter bursts, internal Beam light rays & camera micro-shake
--   * Stage 3 (1.8s - 2.2s): Anticipation swell -> physical shell-shard radial burst,
--     shockwave ring, PointLight flash, and animated 3D Dragon hop/roar + elemental aura
--   * Quick Mode (Quick: ON): Compresses the sequence to ~0.8s with zero memory leaks.

local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local UI = require(script.Parent.UI)
local VikingModels = require(script.Parent.VikingModels)
local HatchFXConfig = require(script.Parent.HatchFXConfig)
local HatchCelebrationFX = require(script.Parent.HatchCelebrationFX)
local DragonCatalog = require(Shared:WaitForChild("DragonCatalog"))
local EggCatalog = require(Shared:WaitForChild("EggCatalog"))
local Rarities = require(Shared:WaitForChild("Rarities"))

local HatchSequenceController = {}

type Trove = HatchCelebrationFX.Trove
type HatchItem = HatchCelebrationFX.HatchItem

type CrackRig = {
	StageParts: { [number]: { BasePart } },
	Highlight: Highlight,
	CoreLight: PointLight,
	RayBeams: { Beam },
	ChipEmitter: ParticleEmitter,
}

type EggSlotState = {
	Item: HatchItem,
	SlotWorldCF: CFrame,
	EggModel: Model,
	EggSize: Vector3,
	ShellColor: Color3,
	RarityColor: Color3,
	RarityRank: number,
	BaseScale: number,
	Rig: CrackRig,
}

local SHELL_IVORY = Color3.fromRGB(246, 238, 222)
local activeLock = false

-- ============================================================================
-- Pedestal Discovery (Finds Player's Sanctuary Plot.Nest or Fallback Anchor)
-- ============================================================================

local function resolveStageOrigin(): CFrame
	local player = Players.LocalPlayer
	local plotsFolder = Workspace:FindFirstChild("Plots")
	if plotsFolder and player then
		local plotName = player:GetAttribute("Plot")
		local myPlot: Instance? = if type(plotName) == "string" and plotName ~= ""
			then plotsFolder:FindFirstChild(plotName)
			else nil
		if not myPlot then
			for _, p in plotsFolder:GetChildren() do
				if p:GetAttribute("OwnerId") == player.UserId then
					myPlot = p
					break
				end
			end
		end
		if myPlot then
			local nest = myPlot:FindFirstChild("Nest")
			local bowl = nest and nest:FindFirstChild("Bowl")
			if bowl and bowl:IsA("BasePart") then
				local topY = bowl.Position.Y + bowl.Size.Y * 0.5
				local spawnPart = myPlot:FindFirstChild("Spawn")
				local lookPos = if spawnPart and spawnPart:IsA("BasePart")
					then Vector3.new(spawnPart.Position.X, topY, spawnPart.Position.Z)
					else Vector3.new(0, topY, 0)
				local flatDir = lookPos - Vector3.new(bowl.Position.X, topY, bowl.Position.Z)
				if flatDir.Magnitude < 0.5 then
					flatDir = Vector3.new(0, 0, -1)
				end
				return CFrame.lookAt(Vector3.new(bowl.Position.X, topY, bowl.Position.Z), Vector3.new(bowl.Position.X, topY, bowl.Position.Z) + flatDir.Unit)
			end
		end
	end

	-- Fallback showcase pedestal high in clear air if Plots/Nest is unavailable
	local char = player and player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if hrp and hrp:IsA("BasePart") then
		local pos = hrp.Position + Vector3.new(0, 28, 0)
		return CFrame.new(pos)
	end
	return CFrame.new(0, 36, 0)
end

-- ============================================================================
-- Stage 1 Helpers: Glowing Norse Rune Circle & Conformal Egg Crack Rig
-- ============================================================================

local function buildNorseRuneCircle(trove: Trove, parent: Instance, originCF: CFrame, radius: number, color: Color3)
	local ringFolder = trove:AddInstance(Instance.new("Model"))
	ringFolder.Name = "NorseRuneCircle"
	ringFolder.Parent = parent

	-- Outer & inner glowing rune rings
	local segs = 24
	for ringIdx, rScale in { 1.0, 0.76 } do
		local r = radius * rScale
		local chord = 2 * r * math.sin(math.pi / segs) + 0.08
		for i = 1, segs do
			local a = (math.pi * 2 / segs) * i
			local mid = originCF * CFrame.new(math.cos(a) * r, 0.05, math.sin(a) * r)
			local seg = Instance.new("Part")
			seg.Anchored = true
			seg.CanCollide = false
			seg.CanQuery = false
			seg.CanTouch = false
			seg.CastShadow = false
			seg.Material = Enum.Material.Neon
			seg.Color = if ringIdx == 1 then color else color:Lerp(Color3.fromRGB(255, 224, 140), 0.45)
			seg.Transparency = 1
			seg.Size = Vector3.new(if ringIdx == 1 then 0.22 else 0.14, 0.06, chord)
			seg.CFrame = CFrame.lookAt(mid.Position, (originCF * CFrame.new(math.cos(a + 0.1) * r, 0.05, math.sin(a + 0.1) * r)).Position)
			seg.Parent = ringFolder

			local tw = TweenService:Create(seg, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Transparency = 0.08,
			})
			trove:AddTween(tw)
			tw:Play()
		end
	end

	-- 12 radial Viking rune spokes around the perimeter
	for i = 1, 12 do
		local a = (math.pi * 2 / 12) * i
		local rMid = radius * 0.88
		local spoke = Instance.new("Part")
		spoke.Anchored = true
		spoke.CanCollide = false
		spoke.CanQuery = false
		spoke.CanTouch = false
		spoke.CastShadow = false
		spoke.Material = Enum.Material.Neon
		spoke.Color = Color3.fromRGB(255, 236, 178):Lerp(color, 0.5)
		spoke.Transparency = 1
		spoke.Size = Vector3.new(0.14, 0.06, radius * 0.22)
		local p = (originCF * CFrame.new(math.cos(a) * rMid, 0.06, math.sin(a) * rMid)).Position
		spoke.CFrame = CFrame.lookAt(p, originCF.Position + Vector3.new(0, 0.06, 0))
		spoke.Parent = ringFolder

		local tw = TweenService:Create(spoke, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Transparency = 0.12,
		})
		trove:AddTween(tw)
		tw:Play()
	end

	-- Ground rune light
	local lightHost = Instance.new("Part")
	lightHost.Anchored = true
	lightHost.CanCollide = false
	lightHost.CanQuery = false
	lightHost.CanTouch = false
	lightHost.Transparency = 1
	lightHost.Size = Vector3.new(1, 1, 1)
	lightHost.CFrame = originCF * CFrame.new(0, 0.6, 0)
	lightHost.Parent = ringFolder

	local pt = Instance.new("PointLight")
	pt.Color = color
	pt.Range = radius * 3.2
	pt.Brightness = 0
	pt.Shadows = false
	pt.Parent = lightHost

	local ltw = TweenService:Create(pt, TweenInfo.new(0.42, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Brightness = 2.4,
	})
	trove:AddTween(ltw)
	ltw:Play()
end

-- Welds conformal 3D Neon crack seams, internal light Beams, PointLight, and a
-- shell-chip ParticleEmitter onto the real EggModels[eggId] MeshPart!
local function attachCrackRigToEgg(eggModel: Model, eggSize: Vector3, shellColor: Color3, rarityColor: Color3): CrackRig
	local primary = eggModel.PrimaryPart or eggModel:FindFirstChildWhichIsA("BasePart", true)
	assert(primary ~= nil, "EggModel must contain at least one BasePart")

	local stageParts: { [number]: { BasePart } } = { [1] = {}, [2] = {}, [3] = {} }

	-- Support pre-authored CrackStage_1..3 child parts if ever added in Studio
	for _, d in eggModel:GetDescendants() do
		if d:IsA("BasePart") then
			if d.Name == "CrackStage_1" then
				d.Transparency = 1
				table.insert(stageParts[1], d)
			elseif d.Name == "CrackStage_2" then
				d.Transparency = 1
				table.insert(stageParts[2], d)
			elseif d.Name == "CrackStage_3" then
				d.Transparency = 1
				table.insert(stageParts[3], d)
			end
		end
	end

	-- Build conformal 3D glowing fissure segments welded to `primary` so every
	-- single-MeshPart egg visibly fractures across Stages 1, 2, and 3!
	local rx = eggSize.X * 0.49
	local ry = eggSize.Y * 0.48
	local rz = eggSize.Z * 0.49
	local centerPos = eggModel:GetPivot().Position

	local function surfacePoint(theta: number, phi: number): (Vector3, Vector3)
		local sx = rx * math.sin(phi) * math.sin(theta)
		local sy = ry * math.cos(phi)
		local sz = rz * math.sin(phi) * math.cos(theta)
		local n = Vector3.new(sx / (rx * rx), sy / (ry * ry), sz / (rz * rz)).Unit
		return centerPos + Vector3.new(sx, sy, sz) + n * 0.04, n
	end

	local seamDefs = {
		-- Stage 1: Front equatorial zig-zag crack
		{ 1, -0.36, 1.55, -0.12, 1.44 },
		{ 1, -0.12, 1.44, 0.14, 1.60 },
		{ 1, 0.14, 1.60, 0.38, 1.48 },
		-- Stage 2: Crown & lower forks + wider waist wrap
		{ 2, 0.14, 1.60, 0.22, 1.18 },
		{ 2, 0.22, 1.18, 0.05, 0.86 },
		{ 2, -0.12, 1.44, -0.22, 1.88 },
		{ 2, -0.36, 1.55, -0.78, 1.62 },
		{ 2, 0.38, 1.48, 0.82, 1.58 },
		-- Stage 3: Full spiderweb stress fractures
		{ 3, -0.12, 1.44, -0.24, 1.08 },
		{ 3, 0.38, 1.48, 0.48, 1.92 },
		{ 3, -0.78, 1.62, -1.35, 1.52 },
		{ 3, 0.82, 1.58, 1.38, 1.50 },
	}

	local glowTone = rarityColor:Lerp(Color3.fromRGB(255, 240, 176), 0.38)
	for idx, def in seamDefs do
		local stg = def[1]
		if #stageParts[stg] < 12 then
			local p1, n1 = surfacePoint(def[2], def[3])
			local p2, n2 = surfacePoint(def[4], def[5])
			local mid = (p1 + p2) * 0.5
			local dir = p2 - p1
			local nAvg = (n1 + n2).Unit
			local seam = Instance.new("Part")
			seam.Name = "StressCrack_" .. tostring(idx)
			seam.Anchored = false
			seam.CanCollide = false
			seam.CanQuery = false
			seam.CanTouch = false
			seam.Massless = true
			seam.CastShadow = false
			seam.Material = Enum.Material.Neon
			seam.Color = glowTone
			seam.Transparency = 1
			seam.Size = Vector3.new(0.08, 0.08, dir.Magnitude + 0.05)
			seam.CFrame = CFrame.lookAt(mid, mid + dir.Unit, nAvg)
			seam.Parent = eggModel

			local weld = Instance.new("WeldConstraint")
			weld.Part0 = primary
			weld.Part1 = seam
			weld.Parent = seam

			table.insert(stageParts[stg], seam)
		end
	end

	-- Rarity rim Highlight that intensifies as internal dragon energy builds
	local hl = Instance.new("Highlight")
	hl.DepthMode = Enum.HighlightDepthMode.Occluded
	hl.FillColor = glowTone
	hl.OutlineColor = rarityColor
	hl.FillTransparency = 1
	hl.OutlineTransparency = 1
	hl.Parent = eggModel

	-- Internal PointLight + shell-chip ParticleEmitter + leaking light-ray Beams
	local coreAtt = Instance.new("Attachment")
	coreAtt.Name = "HatchCoreAttachment"
	coreAtt.Parent = primary

	local coreLight = Instance.new("PointLight")
	coreLight.Color = rarityColor
	coreLight.Brightness = 0
	coreLight.Range = 12
	coreLight.Shadows = false
	coreLight.Parent = coreAtt

	local chipEmitter = Instance.new("ParticleEmitter")
	chipEmitter.Texture = HatchFXConfig.Textures.ShellChip
	chipEmitter.Color = ColorSequence.new(SHELL_IVORY, shellColor)
	chipEmitter.LightEmission = 0.25
	chipEmitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.28),
		NumberSequenceKeypoint.new(0.7, 0.18),
		NumberSequenceKeypoint.new(1, 0),
	})
	chipEmitter.Lifetime = NumberRange.new(0.35, 0.65)
	chipEmitter.Speed = NumberRange.new(7, 14)
	chipEmitter.SpreadAngle = Vector2.new(120, 120)
	chipEmitter.Acceleration = Vector3.new(0, -28, 0)
	chipEmitter.RotSpeed = NumberRange.new(-260, 260)
	chipEmitter.Rate = 0
	chipEmitter.Parent = coreAtt

	local rayDirections = {
		Vector3.new(0.55, 0.45, 0.72),
		Vector3.new(-0.58, 0.36, 0.68),
		Vector3.new(0.08, 0.78, 0.56),
	}
	local rayBeams: { Beam } = {}
	for i, dir in rayDirections do
		local outAtt = Instance.new("Attachment")
		outAtt.Name = "LeakRayTip_" .. tostring(i)
		outAtt.Position = dir.Unit * (math.max(eggSize.X, eggSize.Y) * 1.15)
		outAtt.Parent = primary

		local beam = Instance.new("Beam")
		beam.Attachment0 = coreAtt
		beam.Attachment1 = outAtt
		beam.FaceCamera = true
		beam.Enabled = false
		beam.LightEmission = 1
		beam.LightInfluence = 0
		beam.Color = ColorSequence.new(Color3.new(1, 1, 1), glowTone)
		beam.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.15),
			NumberSequenceKeypoint.new(1, 1),
		})
		beam.Width0 = 0.45
		beam.Width1 = 1.35
		beam.Parent = primary
		table.insert(rayBeams, beam)
	end

	return {
		StageParts = stageParts,
		Highlight = hl,
		CoreLight = coreLight,
		RayBeams = rayBeams,
		ChipEmitter = chipEmitter,
	}
end

local function activateCrackBeat(slot: EggSlotState, beatStage: number)
	for stg = 1, beatStage do
		for _, p in slot.Rig.StageParts[stg] do
			p.Transparency = 0.04
		end
	end
	slot.Rig.CoreLight.Brightness = beatStage * 1.8
	slot.Rig.Highlight.OutlineTransparency = math.clamp(1.0 - beatStage * 0.28, 0.1, 1)
	slot.Rig.Highlight.FillTransparency = math.clamp(1.0 - beatStage * 0.14, 0.5, 1)
	slot.Rig.ChipEmitter:Emit(10 + beatStage * 6)
	for i, beam in slot.Rig.RayBeams do
		if i <= beatStage then
			beam.Enabled = true
		end
	end
end

-- ============================================================================
-- Stage 3 Helpers: Physical Shell Shard Burst, Shockwave & Animated 3D Dragon
-- ============================================================================

local function spawnPhysicalShellShards(
	trove: Trove,
	worldContainer: Instance,
	originPos: Vector3,
	eggSize: Vector3,
	shellColor: Color3,
	shardCount: number
)
	local lifetime = HatchFXConfig.Timing.ShardLifetime
	for i = 1, shardCount do
		local a = (math.pi * 2 / shardCount) * i + (math.random() - 0.5) * 0.35
		local outDir = Vector3.new(math.cos(a), 0.45 + math.random() * 0.55, math.sin(a)).Unit
		local spawnPos = originPos + Vector3.new(math.cos(a) * eggSize.X * 0.32, (i % 3 - 1) * eggSize.Y * 0.18, math.sin(a) * eggSize.Z * 0.32)

		local shard = trove:AddInstance(Instance.new("WedgePart"))
		shard.Name = "EggShellShard"
		shard.Anchored = false
		shard.CanCollide = false
		shard.CanTouch = false
		shard.CanQuery = false
		shard.CastShadow = false
		shard.Material = Enum.Material.SmoothPlastic
		shard.Color = if i % 3 == 0 then SHELL_IVORY else shellColor
		shard.Size = Vector3.new(0.46 + math.random() * 0.24, 0.58 + math.random() * 0.28, 0.11)
		shard.CFrame = CFrame.lookAt(spawnPos, spawnPos + outDir) * CFrame.Angles(0, 0, math.rad(i * 37))
		shard.Parent = worldContainer

		-- Physical impulse velocity & angular spin under native Workspace gravity
		shard.AssemblyLinearVelocity = outDir * (14 + math.random() * 8) + Vector3.new(0, 12 + math.random() * 6, 0)
		shard.AssemblyAngularVelocity = Vector3.new(
			math.random(-14, 14),
			math.random(-14, 14),
			math.random(-14, 14)
		)

		task.delay(lifetime * 0.55, function()
			if shard.Parent then
				local tw = TweenService:Create(shard, TweenInfo.new(lifetime * 0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
					Transparency = 1,
				})
				trove:AddTween(tw)
				tw:Play()
			end
		end)
		Debris:AddItem(shard, lifetime)
	end
end

local function spawnRadialShockwaveAndFlash(trove: Trove, worldContainer: Instance, centerPos: Vector3, color: Color3)
	local ring = trove:AddInstance(Instance.new("Part"))
	ring.Name = "ShatterShockwave"
	ring.Shape = Enum.PartType.Cylinder
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.CastShadow = false
	ring.Material = Enum.Material.Neon
	ring.Color = color
	ring.Transparency = 0.15
	ring.Size = Vector3.new(0.18, 1.4, 1.4)
	ring.CFrame = CFrame.new(centerPos) * CFrame.Angles(0, 0, math.rad(90))
	ring.Parent = worldContainer

	local flashLight = Instance.new("PointLight")
	flashLight.Color = Color3.new(1, 1, 1):Lerp(color, 0.45)
	flashLight.Brightness = 6
	flashLight.Range = 22
	flashLight.Shadows = false
	flashLight.Parent = ring

	local expand = TweenService:Create(ring, TweenInfo.new(0.42, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.06, 11.5, 11.5),
		Transparency = 1,
	})
	local dimLight = TweenService:Create(flashLight, TweenInfo.new(0.38, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Brightness = 0,
	})
	trove:AddTween(expand)
	trove:AddTween(dimLight)
	expand:Play()
	dimLight:Play()
	Debris:AddItem(ring, 0.5)
end

local function spawnRevealedDragon(
	trove: Trove,
	worldContainer: Instance,
	slotCF: CFrame,
	item: HatchItem,
	isCluster: boolean
): BasePart?
	local species = DragonCatalog.Get(item.Species)
	local rarityInfo = Rarities.Info[item.Rarity] or Rarities.Info.Common
	local elementId = if species then species.Element else "Fire"
	local scale = if isCluster then 0.21 else 0.30

	local folder = ReplicatedStorage:FindFirstChild("DragonModels")
	local template = folder and folder:FindFirstChild(item.Species)
	local dragonModel: Model

	if template and template:IsA("Model") then
		dragonModel = trove:AddInstance(template:Clone())
		dragonModel:SetAttribute("Species", item.Species)
		dragonModel:SetAttribute("Element", elementId)
		dragonModel:SetAttribute("Rarity", item.Rarity)
		dragonModel:ScaleTo(dragonModel:GetScale() * scale)
		local foot = ((dragonModel:GetAttribute("FootOffset") :: number?) or 6) * scale
		dragonModel:SetAttribute("FootOffset", foot)

		for _, d in dragonModel:GetDescendants() do
			if d:IsA("BasePart") then
				d.CanCollide = false
				d.CanQuery = false
				d.CanTouch = false
				d.Anchored = (d == dragonModel.PrimaryPart or d.Name == "Root")
			end
		end
	else
		-- Clean fallback dragon statue if DragonModels is absent in headless tests
		dragonModel = trove:AddInstance(Instance.new("Model"))
		local p = Instance.new("Part")
		p.Name = "Root"
		p.Anchored = true
		p.CanCollide = false
		p.Color = rarityInfo.Color
		p.Size = Vector3.new(1.6, 1.8, 2.2)
		p.Parent = dragonModel
		dragonModel.PrimaryPart = p
		dragonModel:SetAttribute("FootOffset", 1.1)
	end

	local footOffset = (dragonModel:GetAttribute("FootOffset") :: number?) or (6 * scale)
	local baseCF = slotCF * CFrame.new(0, footOffset, 0)
	dragonModel:PivotTo(baseCF * CFrame.new(0, -0.6, 0))
	dragonModel.Parent = worldContainer

	-- Tag so DragonAnimator drives real idle wingbeats & breathing!
	CollectionService:AddTag(dragonModel, "AnimatedDragon")
	trove:AddCallback(function()
		if dragonModel.Parent then
			CollectionService:RemoveTag(dragonModel, "AnimatedDragon")
		end
	end)

	local rootPart = dragonModel.PrimaryPart or dragonModel:FindFirstChildWhichIsA("BasePart", true)
	if rootPart then
		HatchCelebrationFX.AttachElementAura(trove, rootPart, elementId, rarityInfo.Rank)
	end

	-- Celebratory Action Hop + Roar pitch arc!
	local hopStart = os.clock()
	local hopDur = 0.52
	local hopConn: RBXScriptConnection? = nil
	hopConn = RunService.RenderStepped:Connect(function()
		if not dragonModel.Parent then
			if hopConn then
				hopConn:Disconnect()
			end
			return
		end
		local t = os.clock() - hopStart
		if t >= hopDur then
			dragonModel:PivotTo(baseCF)
			if hopConn then
				hopConn:Disconnect()
			end
			return
		end
		local u = t / hopDur
		local hopHeight = math.sin(u * math.pi) * (if isCluster then 1.45 else 2.05)
		local roarPitch = math.sin(u * math.pi) * math.rad(16)
		dragonModel:PivotTo(baseCF * CFrame.new(0, hopHeight, 0) * CFrame.Angles(roarPitch, 0, 0))
	end)
	if hopConn then
		trove:AddConnection(hopConn)
	end

	return rootPart
end

-- ============================================================================
-- Core Sequence Runner (1-Egg or 4-Egg Cluster)
-- ============================================================================

local function runSequence(
	screenGui: ScreenGui,
	results: { HatchItem },
	quick: boolean,
	headingOverride: string?
)
	if #results == 0 then
		return
	end
	while activeLock do
		task.wait()
	end
	activeLock = true

	local trove = HatchCelebrationFX.NewTrove()
	local okRun, errRun = pcall(function(): boolean
		local camera = Workspace.CurrentCamera
		if not camera then
			return false
		end

		-- Hide non-hatch UI cleanly during the 3D showcase and restore guaranteed in Trove
		local restoredVis: { { Gui: GuiObject, WasVisible: boolean } } = {}
		for _, child in screenGui:GetChildren() do
			if child:IsA("GuiObject") and child.Visible then
				table.insert(restoredVis, { Gui = child, WasVisible = true })
				child.Visible = false
			end
		end
		trove:AddCallback(function()
			for _, entry in restoredVis do
				if entry.Gui and entry.Gui.Parent then
					entry.Gui.Visible = entry.WasVisible
				end
			end
		end)

		-- Save & stage Camera safely
		local savedCamType = camera.CameraType
		local savedCamCF = camera.CFrame
		local savedFOV = camera.FieldOfView
		trove:AddCallback(function()
			if camera and camera.Parent then
				camera.CameraType = savedCamType
				camera.FieldOfView = savedFOV
				if savedCamType == Enum.CameraType.Scriptable then
					camera.CFrame = savedCamCF
				end
			end
		end)

		local stageOriginCF = resolveStageOrigin()
		local isCluster = #results > 1
		local camDist = if isCluster then HatchFXConfig.Camera.ClusterDistance else HatchFXConfig.Camera.SingleDistance
		local camHeight = if isCluster then HatchFXConfig.Camera.ClusterHeight else HatchFXConfig.Camera.SingleHeight
		local baseFOV = HatchFXConfig.Camera.BaseFOV

		local camLookTarget = (stageOriginCF * CFrame.new(0, 1.85, 0)).Position
		local camPos = (stageOriginCF * CFrame.new(0, camHeight, -camDist)).Position
		local baseStageCamCF = CFrame.lookAt(camPos, camLookTarget)

		camera.CameraType = Enum.CameraType.Scriptable
		camera.FieldOfView = baseFOV
		camera.CFrame = baseStageCamCF

		-- World container cleaned automatically by Trove
		local stageFolder = trove:AddInstance(Instance.new("Folder"))
		stageFolder.Name = "DragonHatchShowcase"
		stageFolder.Parent = Workspace

		-- Fallback carved Viking platform if staging in open air
		local plotsFolder = Workspace:FindFirstChild("Plots")
		if not plotsFolder then
			local pad = Instance.new("Part")
			pad.Shape = Enum.PartType.Cylinder
			pad.Anchored = true
			pad.CanCollide = false
			pad.Material = Enum.Material.Slate
			pad.Color = Color3.fromRGB(62, 64, 72)
			pad.Size = Vector3.new(1.2, 16, 16)
			pad.CFrame = stageOriginCF * CFrame.new(0, -0.6, 0) * CFrame.Angles(0, 0, math.rad(90))
			pad.Parent = stageFolder
		end

		-- Determine highest rarity across the batch for the Norse rune ring & camera shake
		local highestRank = 1
		local highestRarity = "Common"
		for _, item in results do
			local rInfo = Rarities.Info[item.Rarity]
			if rInfo and rInfo.Rank > highestRank then
				highestRank = rInfo.Rank
				highestRarity = item.Rarity
			end
		end
		local highestColor = (Rarities.Info[highestRarity] or Rarities.Info.Common).Color
		local highestProfile = HatchFXConfig.RarityProfiles[highestRarity] or HatchFXConfig.RarityProfiles.Common

		-- Tap-to-skip catcher + subtle skip hint
		local skipped = false
		local seqStart = os.clock()
		local minSkip = if quick then HatchFXConfig.Timing.QuickMinSkipDelay else HatchFXConfig.Timing.MinSkipDelay

		local skipCatcher: TextButton = trove:AddInstance(UI.new("TextButton", {
			Name = "HatchSkipCatcher",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Text = "",
			AutoButtonColor = false,
			ZIndex = 50,
			Parent = screenGui,
		}))
		local skipHint = trove:AddInstance(UI.label(skipCatcher, "Tap anywhere to skip", 13, {
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -14),
			Size = UDim2.fromOffset(240, 20),
			TextXAlignment = Enum.TextXAlignment.Center,
			TextColor3 = UI.Colors.Muted,
			TextStrokeColor3 = UI.Colors.WoodDark,
			TextStrokeTransparency = 0.4,
			ZIndex = 51,
		}))
		trove:AddConnection(skipCatcher.Activated:Connect(function()
			if os.clock() - seqStart >= minSkip then
				skipped = true
			end
		end))

		local function waitInterruptible(duration: number)
			local t0 = os.clock()
			while not skipped and os.clock() - t0 < duration do
				RunService.RenderStepped:Wait()
			end
		end

		-- ====================================================================
		-- STAGE 1: Pedestal Drop & Norse Rune Ignition (0.0s - 0.5s)
		-- ====================================================================
		local runeRadius = if isCluster then 5.8 else 3.2
		buildNorseRuneCircle(trove, stageFolder, stageOriginCF, runeRadius, highestColor)
		HatchCelebrationFX.PlaySound(trove, HatchFXConfig.Sounds.RuneIgnite, nil, nil, 0.9)

		local slotDefs = if isCluster then HatchFXConfig.ClusterSlots else HatchFXConfig.SingleSlot
		local slots: { EggSlotState } = {}
		local slotPositions: { Vector3 } = {}

		for i, item in results do
			local pose = slotDefs[((i - 1) % #slotDefs) + 1]
			local worldSlotPos = (stageOriginCF * CFrame.new(pose.Offset)).Position
			-- Face each slot cleanly toward the staged camera!
			local flatLook = Vector3.new(camPos.X, worldSlotPos.Y, camPos.Z)
			local slotCF = CFrame.lookAt(worldSlotPos, flatLook) * CFrame.Angles(0, math.rad(pose.YawDeg * 0.25), 0)
			table.insert(slotPositions, worldSlotPos)

			-- Woven Viking nest pad on the stone bowl
			local nestModel = Instance.new("Model")
			nestModel.Name = "NestPad_" .. tostring(i)
			VikingModels.BuildNestInto(nestModel, 0.14, if isCluster then 1.15 else 1.35)
			nestModel:PivotTo(slotCF)
			nestModel.Parent = stageFolder

			local eggCatalogEntry = EggCatalog.Get(item.Egg)
			local eggModel, rawSize, shellColor = VikingModels.CloneEggModel(item.Egg, if eggCatalogEntry then eggCatalogEntry.Color else nil)
			local targetHeight = if isCluster then 2.85 else 3.45
			local scaleFactor = targetHeight / math.max(rawSize.Y, 0.1)
			eggModel:ScaleTo(eggModel:GetScale() * scaleFactor)
			local _, scaledSize = eggModel:GetBoundingBox()

			local rInfo = Rarities.Info[item.Rarity] or Rarities.Info.Common
			local rig = attachCrackRigToEgg(eggModel, scaledSize, shellColor, rInfo.Color)

			local landedEggCF = slotCF * CFrame.new(0, scaledSize.Y * 0.5 + 0.10, 0)
			local startDropCF = landedEggCF * CFrame.new(0, 5.4, 0)
			eggModel:PivotTo(startDropCF)
			eggModel.Parent = stageFolder

			local slotState: EggSlotState = {
				Item = item,
				SlotWorldCF = slotCF,
				EggModel = eggModel,
				EggSize = scaledSize,
				ShellColor = shellColor,
				RarityColor = rInfo.Color,
				RarityRank = rInfo.Rank,
				BaseScale = eggModel:GetScale(),
				Rig = rig,
			}
			table.insert(slots, slotState)

			-- Elastic bounce drop via NumberValue -> PivotTo so multi-part egg rigs stay welded
			local dropDur = if quick then HatchFXConfig.Timing.QuickDropDuration else (HatchFXConfig.Timing.DropDuration - 0.06)
			local alphaVal = trove:AddInstance(Instance.new("NumberValue"))
			alphaVal.Value = 0
			trove:AddConnection(alphaVal.Changed:Connect(function(v: number)
				if eggModel.Parent then
					eggModel:PivotTo(startDropCF:Lerp(landedEggCF, v))
				end
			end))
			task.delay(if quick then 0 else (i - 1) * 0.035, function()
				if alphaVal.Parent then
					local tw = TweenService:Create(alphaVal, TweenInfo.new(dropDur, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
						Value = 1,
					})
					trove:AddTween(tw)
					tw:Play()
					task.delay(dropDur * 0.72, function()
						if stageFolder.Parent then
							HatchCelebrationFX.PlaySound(trove, HatchFXConfig.Sounds.PedestalDrop, nil, 0.95 + i * 0.04, 0.75)
						end
					end)
				end
			end)
		end

		waitInterruptible(if quick then HatchFXConfig.Timing.QuickDropDuration else HatchFXConfig.Timing.DropDuration)

		-- Snap eggs cleanly to landed pose if skipped mid-drop
		for _, s in slots do
			if s.EggModel.Parent then
				s.EggModel:PivotTo(s.SlotWorldCF * CFrame.new(0, s.EggSize.Y * 0.5 + 0.10, 0))
			end
		end

		-- ====================================================================
		-- STAGE 2: Escalating Wobble & Stress Cracks (0.5s - 1.8s)
		-- ====================================================================
		if not quick and not skipped then
			local wobbleTotal = HatchFXConfig.Timing.WobbleDuration
			local beatLen = wobbleTotal / 3
			local wobbleStart = os.clock()
			local triggeredBeat = 0
			local camShakeMag = 0

			while not skipped do
				local elapsed = os.clock() - wobbleStart
				if elapsed >= wobbleTotal then
					break
				end

				local beatIdx = math.clamp(math.floor(elapsed / beatLen) + 1, 1, 3)
				local localT = (elapsed - (beatIdx - 1) * beatLen) / beatLen

				-- Trigger crack peak right as each wobble beat crests (localT >= 0.48)
				if localT >= 0.48 and triggeredBeat < beatIdx then
					triggeredBeat = beatIdx
					local pitch = HatchFXConfig.CrackPitchSteps[beatIdx] or 1.0
					HatchCelebrationFX.PlaySound(trove, HatchFXConfig.Sounds.EggCrack, nil, pitch, 0.82 + beatIdx * 0.12)
					for _, s in slots do
						activateCrackBeat(s, beatIdx)
					end
					camShakeMag = highestProfile.ShakeScale * (0.55 + beatIdx * 0.35)
				end

				-- Damped harmonic rotational wobble around each egg's bottom contact point
				local freq = 22 + beatIdx * 9
				local maxDeg = 9 + beatIdx * 6.5
				local damping = math.exp(-2.4 * localT) * math.sin(localT * math.pi)
				for idx, s in slots do
					if s.EggModel.Parent then
						local phase = idx * 0.85
						local roll = math.sin(elapsed * freq + phase) * math.rad(maxDeg) * damping
						local pitchAngle = math.cos(elapsed * freq * 0.75 + phase) * math.rad(maxDeg * 0.35) * damping
						local bottomContactCF = s.SlotWorldCF * CFrame.new(0, 0.10, 0)
						local localCenterOffset = CFrame.new(0, s.EggSize.Y * 0.5, 0)
						s.EggModel:PivotTo(bottomContactCF * CFrame.Angles(pitchAngle, 0, roll) * localCenterOffset)
					end
				end

				-- Subtle rarity-scaled camera micro-shake
				if camShakeMag > 0.001 then
					local jx = (math.random() - 0.5) * 2 * camShakeMag
					local jy = (math.random() - 0.5) * 2 * camShakeMag
					camera.CFrame = baseStageCamCF * CFrame.new(jx, jy, 0)
					camShakeMag = math.max(0, camShakeMag - 0.018)
				else
					camera.CFrame = baseStageCamCF
				end

				RunService.RenderStepped:Wait()
			end
			camera.CFrame = baseStageCamCF
		elseif quick then
			-- Instant stress-crack flash in Quick Mode
			HatchCelebrationFX.PlaySound(trove, HatchFXConfig.Sounds.EggCrack, nil, 1.15, 0.8)
			for _, s in slots do
				activateCrackBeat(s, 3)
			end
		end

		-- ====================================================================
		-- STAGE 3: Anticipation Swell, Shell Shatter & Dragon Reveal (1.8s - 2.2s)
		-- ====================================================================
		local swellDur = if quick then HatchFXConfig.Timing.QuickAnticipation else HatchFXConfig.Timing.AnticipationDuration
		if not skipped and swellDur > 0 then
			local swellStart = os.clock()
			while not skipped and os.clock() - swellStart < swellDur do
				local a = math.clamp((os.clock() - swellStart) / swellDur, 0, 1)
				for _, s in slots do
					if s.EggModel.Parent then
						s.EggModel:ScaleTo(s.BaseScale * (1 + 0.11 * a))
						s.Rig.Highlight.FillTransparency = 0.2 * (1 - a)
						s.Rig.Highlight.OutlineTransparency = 0
					end
				end
				RunService.RenderStepped:Wait()
			end
		end

		-- Explosive Shell Shatter + Shockwave + Animated 3D Dragon Reveal!
		skipCatcher.Visible = false
		skipHint.Visible = false
		HatchCelebrationFX.PlaySound(trove, HatchFXConfig.Sounds.ShellShatter, nil, nil, 1.0)

		local dragonRoots: { BasePart? } = table.create(#slots)
		for i, s in slots do
			local burstOrigin = (s.SlotWorldCF * CFrame.new(0, s.EggSize.Y * 0.5, 0)).Position
			if s.EggModel.Parent then
				s.EggModel:Destroy()
			end
			local rProfile = HatchFXConfig.RarityProfiles[s.Item.Rarity] or HatchFXConfig.RarityProfiles.Common
			spawnPhysicalShellShards(trove, stageFolder, burstOrigin, s.EggSize, s.ShellColor, rProfile.ShardCount)
			spawnRadialShockwaveAndFlash(trove, stageFolder, s.SlotWorldCF.Position + Vector3.new(0, 0.25, 0), s.RarityColor)
			dragonRoots[i] = spawnRevealedDragon(trove, stageFolder, s.SlotWorldCF, s.Item, isCluster)
		end

		-- Rarity-escalated Celebration FX + Forged Viking Reveal Banner
		HatchCelebrationFX.TriggerRarityCelebration(
			trove,
			stageFolder,
			slotPositions,
			results,
			camera,
			baseFOV,
			screenGui,
			quick
		)

		local dismissCatcher = HatchCelebrationFX.ShowVikingBanner(
			trove,
			screenGui,
			results,
			dragonRoots,
			headingOverride
		)

		-- Hold for celebration + interactive dismiss
		local holdTime = if quick
			then HatchFXConfig.Timing.QuickRevealHold
			else (HatchFXConfig.Timing.ShatterRevealDuration + HatchFXConfig.Timing.CelebrationHold + HatchFXConfig.Timing.BannerMaxReadSeconds)
		local minDismiss = if quick then 0.16 else 0.35
		local holdStart = os.clock()
		local dismissed = false
		trove:AddConnection(dismissCatcher.Activated:Connect(function()
			if os.clock() - holdStart >= minDismiss then
				dismissed = true
			end
		end))
		while not dismissed and os.clock() - holdStart < holdTime do
			RunService.RenderStepped:Wait()
		end
		return true
	end)

	-- Zero-leak guaranteed cleanup regardless of normal exit, skip, or error!
	trove:Clean()
	activeLock = false
	if not okRun then
		warn("[HatchSequenceController] Sequence error:", errRun)
	end

	-- If any hatched item included the fixed first-hatch Tutorial Bonus dragon, showcase it next!
	for _, r in results do
		if r.Bonus then
			local bonusItem: HatchItem = {
				Egg = "Hatchling",
				Id = r.Bonus.Id,
				Species = r.Bonus.Species,
				Rarity = r.Bonus.Rarity,
				Released = false,
				Essence = 0,
				IsNew = r.Bonus.IsNew,
			}
			runSequence(screenGui, { bonusItem }, quick, "SAGA GIFT • JOINED YOUR SANCTUARY")
			break
		end
	end
end

function HatchSequenceController.PlaySingle(screenGui: ScreenGui, result: HatchItem, quick: boolean)
	runSequence(screenGui, { result }, quick, nil)
end

function HatchSequenceController.PlayCluster(screenGui: ScreenGui, results: { HatchItem }, quick: boolean)
	runSequence(screenGui, results, quick, nil)
end

return HatchSequenceController
