--!strict
-- ReplicatedStorage/Client/HatchCelebrationFX
-- Rarity-scaled 3D celebration VFX (Common -> Mythic), zero-leak Trove cleanup,
-- and forged Viking Reveal Banners (bottom-center single crest + 4-egg overhead
-- BillboardGuis with "NEW!" discovery badges).

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local UI = require(script.Parent.UI)
local HatchFXConfig = require(script.Parent.HatchFXConfig)
local DragonCatalog = require(Shared:WaitForChild("DragonCatalog"))
local EggCatalog = require(Shared:WaitForChild("EggCatalog"))
local Elements = require(Shared:WaitForChild("Elements"))
local Rarities = require(Shared:WaitForChild("Rarities"))
local SanctuaryConfig = require(Shared:WaitForChild("SanctuaryConfig"))

local HatchCelebrationFX = {}

-- ============================================================================
-- Strictly Typed Zero-Leak Trove Cleanup Container
-- ============================================================================

export type Trove = {
	AddInstance: <T>(self: Trove, inst: T) -> T,
	AddConnection: (self: Trove, conn: RBXScriptConnection) -> RBXScriptConnection,
	AddTween: (self: Trove, tween: Tween) -> Tween,
	AddCallback: (self: Trove, fn: () -> ()) -> (),
	Clean: (self: Trove) -> (),
}

type TroveInternal = Trove & {
	_cleaned: boolean,
	_instances: { Instance },
	_connections: { RBXScriptConnection },
	_tweens: { Tween },
	_callbacks: { () -> () },
}

function HatchCelebrationFX.NewTrove(): Trove
	local self: TroveInternal = {
		_cleaned = false,
		_instances = {},
		_connections = {},
		_tweens = {},
		_callbacks = {},
		AddInstance = function<T>(t: Trove, inst: T): T
			local ti = t :: TroveInternal
			if ti._cleaned then
				if typeof(inst) == "Instance" then
					(inst :: Instance):Destroy()
				end
			else
				table.insert(ti._instances, (inst :: any) :: Instance)
			end
			return inst
		end,
		AddConnection = function(t: Trove, conn: RBXScriptConnection): RBXScriptConnection
			local ti = t :: TroveInternal
			if ti._cleaned then
				conn:Disconnect()
			else
				table.insert(ti._connections, conn)
			end
			return conn
		end,
		AddTween = function(t: Trove, tween: Tween): Tween
			local ti = t :: TroveInternal
			if ti._cleaned then
				tween:Cancel()
			else
				table.insert(ti._tweens, tween)
			end
			return tween
		end,
		AddCallback = function(t: Trove, fn: () -> ())
			local ti = t :: TroveInternal
			if ti._cleaned then
				fn()
			else
				table.insert(ti._callbacks, fn)
			end
		end,
		Clean = function(t: Trove)
			local ti = t :: TroveInternal
			if ti._cleaned then
				return
			end
			ti._cleaned = true
			for _, tween in ti._tweens do
				pcall(function()
					tween:Cancel()
				end)
			end
			for _, conn in ti._connections do
				if conn.Connected then
					conn:Disconnect()
				end
			end
			for i = #ti._callbacks, 1, -1 do
				pcall(ti._callbacks[i])
			end
			for i = #ti._instances, 1, -1 do
				local inst = ti._instances[i]
				if inst and inst.Parent then
					inst:Destroy()
				end
			end
			table.clear(ti._tweens)
			table.clear(ti._connections)
			table.clear(ti._callbacks)
			table.clear(ti._instances)
		end,
	}
	return self
end

export type HatchItem = {
	Egg: string,
	Id: string?,
	Species: string,
	Rarity: string,
	Released: boolean?,
	Essence: number?,
	IsNew: boolean?,
	Bonus: { Id: string, Species: string, Rarity: string, IsNew: boolean? }?,
}

-- ============================================================================
-- Audio Helper
-- ============================================================================

function HatchCelebrationFX.PlaySound(
	trove: Trove,
	spec: HatchFXConfig.SoundSpec,
	parent: Instance?,
	pitchOverride: number?,
	volumeScale: number?
)
	local s = Instance.new("Sound")
	s.SoundId = spec.Id
	s.Volume = spec.Volume * (volumeScale or 1)
	s.PlaybackSpeed = (pitchOverride or spec.Speed) * (0.97 + math.random() * 0.06)
	s.RollOffMaxDistance = 260
	s.RollOffMinDistance = 24
	s.Parent = parent or SoundService
	trove:AddInstance(s)
	s:Play()
	Debris:AddItem(s, 8)
end

-- ============================================================================
-- Elemental Aura Emitter on Revealed 3D Dragon
-- ============================================================================

function HatchCelebrationFX.AttachElementAura(trove: Trove, rootPart: BasePart, elementId: string, rarityRank: number)
	local profile = HatchFXConfig.ElementProfiles[elementId] or HatchFXConfig.ElementProfiles.Fire
	local att = trove:AddInstance(Instance.new("Attachment"))
	att.Position = Vector3.new(0, 0.8, 0)
	att.Parent = rootPart

	local emitter = trove:AddInstance(Instance.new("ParticleEmitter"))
	emitter.Texture = profile.Texture
	emitter.Color = ColorSequence.new(profile.Secondary, profile.Primary)
	emitter.LightEmission = 0.85
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.55),
		NumberSequenceKeypoint.new(0.5, 0.95),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.15),
		NumberSequenceKeypoint.new(0.75, 0.45),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Lifetime = NumberRange.new(0.65, 1.25)
	emitter.Speed = NumberRange.new(2.5, 6.0)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Acceleration = Vector3.new(0, 4.5, 0)
	emitter.Rate = 12 + rarityRank * 5
	emitter.Parent = att
	emitter:Emit(14 + rarityRank * 4)
end

-- ============================================================================
-- Rarity-Escalated 3D World Celebration (Common -> Mythic)
-- ============================================================================

local function spawnRarityPillar(trove: Trove, worldContainer: Instance, pos: Vector3, color: Color3, width: number, height: number, isMythicTier: boolean)
	local anchor = trove:AddInstance(Instance.new("Part"))
	anchor.Name = "RarityPillarAnchor"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(1, 1, 1)
	anchor.CFrame = CFrame.new(pos)
	anchor.Parent = worldContainer

	local att0 = Instance.new("Attachment")
	att0.Position = Vector3.new(0, 0, 0)
	att0.Parent = anchor

	local att1 = Instance.new("Attachment")
	att1.Position = Vector3.new(0, height, 0)
	att1.Parent = anchor

	local beam = Instance.new("Beam")
	beam.Attachment0 = att0
	beam.Attachment1 = att1
	beam.FaceCamera = true
	beam.LightEmission = 1
	beam.LightInfluence = 0
	beam.Texture = HatchFXConfig.Textures.PillarBeam
	beam.TextureSpeed = 1.6
	beam.TextureLength = 8
	beam.Color = ColorSequence.new(Color3.new(1, 1, 1), color)
	beam.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.12),
		NumberSequenceKeypoint.new(0.65, 0.35),
		NumberSequenceKeypoint.new(1, 1),
	})
	beam.Width0 = width
	beam.Width1 = width * 0.38
	beam.Parent = anchor

	-- Swirling runic embers climbing the pillar
	local embers = Instance.new("ParticleEmitter")
	embers.Texture = HatchFXConfig.Textures.Sparkle
	embers.Color = ColorSequence.new(Color3.fromRGB(255, 244, 196), color)
	embers.LightEmission = 1
	embers.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.7),
		NumberSequenceKeypoint.new(1, 0),
	})
	embers.Lifetime = NumberRange.new(0.8, 1.5)
	embers.Speed = NumberRange.new(8, 18)
	embers.SpreadAngle = Vector2.new(28, 28)
	embers.Acceleration = Vector3.new(0, 10, 0)
	embers.Rate = if isMythicTier then 48 else 26
	embers.Parent = att0
	embers:Emit(if isMythicTier then 45 else 24)

	if isMythicTier then
		-- Secondary firework/lightning volley burst for Legendary & Mythic!
		local volley = Instance.new("ParticleEmitter")
		volley.Texture = HatchFXConfig.Textures.Sparkle
		volley.Color = ColorSequence.new(Color3.fromRGB(255, 232, 132), color)
		volley.LightEmission = 1
		volley.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1.15),
			NumberSequenceKeypoint.new(0.6, 0.65),
			NumberSequenceKeypoint.new(1, 0),
		})
		volley.Lifetime = NumberRange.new(0.7, 1.35)
		volley.Speed = NumberRange.new(16, 32)
		volley.SpreadAngle = Vector2.new(65, 65)
		volley.Acceleration = Vector3.new(0, -18, 0)
		volley.Rate = 0
		volley.Parent = att0
		volley:Emit(52)
	end

	-- Smoothly taper pillar width down after initial flare
	task.delay(0.85, function()
		if beam.Parent then
			local tw = TweenService:Create(beam, TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Width0 = width * 0.45,
				Width1 = 0.1,
			})
			trove:AddTween(tw)
			tw:Play()
		end
	end)
end

function HatchCelebrationFX.TriggerRarityCelebration(
	trove: Trove,
	worldContainer: Instance,
	slotWorldPositions: { Vector3 },
	results: { HatchItem },
	camera: Camera,
	baseFOV: number,
	screenGui: ScreenGui,
	quick: boolean
)
	local highestRank = 1
	local highestRarity = "Common"
	for _, r in results do
		local info = Rarities.Info[r.Rarity]
		if info and info.Rank > highestRank then
			highestRank = info.Rank
			highestRarity = r.Rarity
		end
	end

	local topProfile = HatchFXConfig.RarityProfiles[highestRarity] or HatchFXConfig.RarityProfiles.Common

	-- Per-slot sparkles or vertical light pillars
	for i, r in results do
		local pos = slotWorldPositions[i] or slotWorldPositions[1]
		local rInfo = Rarities.Info[r.Rarity] or Rarities.Info.Common
		local rProfile = HatchFXConfig.RarityProfiles[r.Rarity] or HatchFXConfig.RarityProfiles.Common

		-- Torchlight / Emerald / Rarity sparkle burst on every slot
		local burstPart = trove:AddInstance(Instance.new("Part"))
		burstPart.Anchored = true
		burstPart.CanCollide = false
		burstPart.CanQuery = false
		burstPart.CanTouch = false
		burstPart.Transparency = 1
		burstPart.Size = Vector3.new(1, 1, 1)
		burstPart.CFrame = CFrame.new(pos + Vector3.new(0, 1.2, 0))
		burstPart.Parent = worldContainer

		local sp = Instance.new("ParticleEmitter")
		sp.Texture = HatchFXConfig.Textures.Sparkle
		sp.Color = ColorSequence.new(Color3.new(1, 1, 1), rProfile.CrestColor)
		sp.LightEmission = 1
		sp.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.75),
			NumberSequenceKeypoint.new(1, 0),
		})
		sp.Lifetime = NumberRange.new(0.55, 1.1)
		sp.Speed = NumberRange.new(6, 15)
		sp.SpreadAngle = Vector2.new(180, 180)
		sp.Acceleration = Vector3.new(0, -10, 0)
		sp.Rate = 0
		sp.Parent = burstPart
		sp:Emit(rProfile.SparkleCount)

		if rProfile.Tier >= 2 then
			spawnRarityPillar(trove, worldContainer, pos, rInfo.Color, rProfile.PillarWidth, rProfile.PillarHeight, rProfile.Tier >= 3)
		end
	end

	-- Tier-escalated Audio, Camera FOV Punch-In, and Legendary/Mythic Hitstop Flash
	HatchCelebrationFX.PlaySound(trove, HatchFXConfig.Sounds.RevealChime, nil, 0.96 + highestRank * 0.05, 1)
	if topProfile.Tier >= 2 then
		HatchCelebrationFX.PlaySound(trove, HatchFXConfig.Sounds.EpicPillar, nil, nil, 0.9)
		local targetFOV = if topProfile.Tier >= 3 then HatchFXConfig.Camera.PunchFOVMythic else HatchFXConfig.Camera.PunchFOVRare
		local punchIn = TweenService:Create(camera, TweenInfo.new(0.14, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { FieldOfView = targetFOV })
		trove:AddTween(punchIn)
		punchIn:Play()
		task.delay(0.18, function()
			if camera.Parent then
				local punchOut = TweenService:Create(camera, TweenInfo.new(0.42, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), { FieldOfView = baseFOV })
				trove:AddTween(punchOut)
				punchOut:Play()
			end
		end)
	end

	if topProfile.Tier >= 3 then
		HatchCelebrationFX.PlaySound(trove, HatchFXConfig.Sounds.DragonRoar, nil, nil, 1.0)
		HatchCelebrationFX.PlaySound(trove, HatchFXConfig.Sounds.MythicThunder, nil, nil, 0.95)

		-- 0.08s Legendary/Mythic Hitstop Freeze-Frame Flash!
		local flash = trove:AddInstance(UI.new("Frame", {
			Name = "HitstopFlash",
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = topProfile.CrestColor:Lerp(Color3.new(1, 1, 1), 0.35),
			BackgroundTransparency = 0.14,
			ZIndex = 62,
			Parent = screenGui,
		}))
		if not quick and topProfile.HitstopSeconds > 0 then
			task.wait(topProfile.HitstopSeconds)
		end
		local fade = TweenService:Create(flash, TweenInfo.new(0.36, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			BackgroundTransparency = 1,
		})
		trove:AddTween(fade)
		fade:Play()
	elseif highestRank >= 3 then
		HatchCelebrationFX.PlaySound(trove, HatchFXConfig.Sounds.DragonRoar, nil, 1.04, 0.7)
	end
end

-- ============================================================================
-- Forged Viking Reveal Banner (Single Bottom Crest + 4-Egg Overhead Billboards)
-- ============================================================================

local function buildElementBadge(parent: Instance, elementId: string, sizePx: number, zIndex: number): Frame
	local elInfo = Elements.Info[elementId]
	local elFX = HatchFXConfig.ElementProfiles[elementId] or HatchFXConfig.ElementProfiles.Fire
	local color = if elInfo then elInfo.Color else elFX.Primary

	local badge = UI.new("Frame", {
		Size = UDim2.fromOffset(sizePx, sizePx),
		BackgroundColor3 = color:Lerp(UI.Colors.WoodDark, 0.65),
		ZIndex = zIndex,
		Parent = parent,
	})
	UI.corner(badge, math.floor(sizePx * 0.5))
	UI.stroke(badge, color, 1.6)
	UI.label(badge, "<b>" .. elFX.RuneGlyph .. "</b>", math.floor(sizePx * 0.58), {
		Font = UI.FontBold,
		Size = UDim2.fromScale(1, 1),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = color:Lerp(Color3.new(1, 1, 1), 0.25),
		ZIndex = zIndex + 1,
	})
	return badge
end

local function buildNewBadge(parent: Instance, pos: UDim2, anchor: Vector2, zIndex: number): Frame
	local tag = UI.new("Frame", {
		Name = "NewDiscoveryBadge",
		AnchorPoint = anchor,
		Position = pos,
		Size = UDim2.fromOffset(58, 22),
		BackgroundColor3 = Color3.fromRGB(238, 178, 48),
		ZIndex = zIndex,
		Parent = parent,
	})
	UI.corner(tag, 5)
	UI.gradient(tag, Color3.fromRGB(255, 244, 178), Color3.fromRGB(204, 132, 34), 90)
	UI.stroke(tag, UI.Colors.WoodDark, 1.5)
	UI.label(tag, "<b>NEW!</b>", 12, {
		Font = UI.FontBold,
		Size = UDim2.fromScale(1, 1),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = UI.Colors.ButtonText,
		ZIndex = zIndex + 1,
	})
	return tag
end

local function formatDragonSubtext(item: HatchItem): string
	if item.Released then
		return string.format("Auto-released • +%d Essence", item.Essence or 0)
	end
	local species = DragonCatalog.Get(item.Species)
	local egg = EggCatalog.Get(item.Egg)
	local station = if species then Elements.GetPreferredStation(species.Element) else "?"
	local income = SanctuaryConfig.DragonIncome({
		Species = item.Species,
		Rarity = item.Rarity,
		Level = 1,
		Power = if egg then egg.Power else 1,
	}, station or "Forge", 0)
	return string.format("Earns %s/s at %s (+25%% match)", tostring(math.floor(income * 100) / 100), station or "?")
end

function HatchCelebrationFX.ShowVikingBanner(
	trove: Trove,
	screenGui: ScreenGui,
	results: { HatchItem },
	dragonRoots: { BasePart? },
	headingOverride: string?
): TextButton
	-- Invisible full-screen click catcher so tapping anywhere dismisses/advances cleanly
	local clickCatcher: TextButton = trove:AddInstance(UI.new("TextButton", {
		Name = "HatchBannerCatcher",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text = "",
		AutoButtonColor = false,
		ZIndex = 55,
		Parent = screenGui,
	}))

	if #results == 1 then
		local r = results[1]
		local species = DragonCatalog.Get(r.Species)
		local rarity = Rarities.Info[r.Rarity] or Rarities.Info.Common
		local rProfile = HatchFXConfig.RarityProfiles[r.Rarity] or HatchFXConfig.RarityProfiles.Common
		local elementId = if species then species.Element else "Fire"
		local elInfo = Elements.Info[elementId]

		local banner = trove:AddInstance(UI.new("Frame", {
			Name = "VikingRevealBanner",
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, 90),
			Size = UDim2.new(0.92, 0, 0, 126),
			BackgroundColor3 = UI.Colors.IronOuter,
			ZIndex = 56,
			Parent = screenGui,
		}))
		UI.new("UISizeConstraint", { MaxSize = Vector2.new(490, 130), Parent = banner })
		UI.ironWoodPlaque(banner, 3, 10, 8, 2)

		-- Rarity-escalated metallic rim pulse for Rare+ and crimson/gold crest for Legendary/Mythic
		local rimGlow = UI.new("Frame", {
			Position = UDim2.fromOffset(7, 7),
			Size = UDim2.new(1, -14, 1, -14),
			BackgroundTransparency = 1,
			ZIndex = 58,
			Parent = banner,
		})
		UI.corner(rimGlow, 7)
		local rimStroke = UI.stroke(rimGlow, if rProfile.Tier >= 2 then rarity.Color else UI.Colors.Stroke, if rProfile.Tier >= 3 then 2.8 else 1.8)
		if rProfile.Tier >= 2 then
			local pulseTw = TweenService:Create(
				rimStroke,
				TweenInfo.new(0.55, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
				{ Thickness = if rProfile.Tier >= 3 then 4.5 else 3.2 }
			)
			trove:AddTween(pulseTw)
			pulseTw:Play()
		end

		if rProfile.Tier >= 3 then
			local crown = UI.new("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(0.5, 0, 0, 0),
				Size = UDim2.fromOffset(196, 24),
				BackgroundColor3 = UI.Colors.Crimson,
				ZIndex = 60,
				Parent = banner,
			})
			UI.corner(crown, 6)
			UI.stroke(crown, UI.Colors.Gold, 1.8)
			UI.label(crown, "<b>★ " .. (headingOverride or (r.Rarity:upper() .. " HATCH!")) .. " ★</b>", 12, {
				Font = UI.FontDisplay,
				Size = UDim2.fromScale(1, 1),
				TextXAlignment = Enum.TextXAlignment.Center,
				TextColor3 = UI.Colors.Gold,
				ZIndex = 61,
			})
		elseif headingOverride then
			UI.label(banner, "<b>" .. headingOverride .. "</b>", 12, {
				Font = UI.FontBold,
				Position = UDim2.fromOffset(20, 10),
				Size = UDim2.new(1, -40, 0, 16),
				TextXAlignment = Enum.TextXAlignment.Center,
				TextColor3 = UI.Colors.GoldSoft,
				ZIndex = 59,
			})
		end

		if r.IsNew then
			buildNewBadge(banner, UDim2.new(1, -16, 0, -4), Vector2.new(1, 0.5), 61)
		end

		-- Element Rune Medallion on Left
		local elemBadge = buildElementBadge(banner, elementId, 52, 59)
		elemBadge.AnchorPoint = Vector2.new(0, 0.5)
		elemBadge.Position = UDim2.new(0, 22, 0.5, 0)

		-- Rarity Pill + Dragon Name + Element/Income Line
		local rarityTag = UI.new("Frame", {
			Position = UDim2.fromOffset(86, 18),
			Size = UDim2.fromOffset(104, 22),
			BackgroundColor3 = rarity.Color:Lerp(UI.Colors.WoodDark, 0.72),
			ZIndex = 59,
			Parent = banner,
		})
		UI.corner(rarityTag, 5)
		UI.stroke(rarityTag, rarity.Color, 1.4)
		UI.label(rarityTag, "<b>" .. r.Rarity:upper() .. "</b>", 12, {
			Font = UI.FontBold,
			Size = UDim2.fromScale(1, 1),
			TextXAlignment = Enum.TextXAlignment.Center,
			TextColor3 = rarity.Color,
			ZIndex = 60,
		})

		UI.label(banner, string.format("<font color=\"#%s\"><b>%s</b></font>", (if elInfo then elInfo.Color else UI.Colors.Text):ToHex(), if elInfo then elInfo.DisplayName else elementId), 13, {
			Position = UDim2.fromOffset(198, 19),
			Size = UDim2.new(1, -218, 0, 20),
			TextWrapped = false,
			ZIndex = 59,
		})

		UI.label(banner, "<b>" .. (if species then species.Name else r.Species) .. "</b>", 25, {
			Font = UI.FontDisplay,
			Position = UDim2.fromOffset(86, 42),
			Size = UDim2.new(1, -106, 0, 30),
			TextColor3 = UI.Colors.Gold,
			TextStrokeColor3 = UI.Colors.WoodDark,
			TextStrokeTransparency = 0.16,
			TextWrapped = false,
			ZIndex = 59,
		})

		UI.label(banner, formatDragonSubtext(r) .. "  •  Tap to continue", 13, {
			Position = UDim2.fromOffset(86, 76),
			Size = UDim2.new(1, -104, 0, 32),
			TextColor3 = UI.Colors.Text,
			TextStrokeColor3 = UI.Colors.WoodDark,
			TextStrokeTransparency = 0.42,
			ZIndex = 59,
		})

		local slideIn = TweenService:Create(banner, TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Position = UDim2.new(0.5, 0, 1, -20),
		})
		trove:AddTween(slideIn)
		slideIn:Play()
	else
		-- 4-Egg Cluster: Overhead forged Viking BillboardGui above each hatched 3D dragon
		for i, r in results do
			local root = dragonRoots[i]
			if root then
				local species = DragonCatalog.Get(r.Species)
				local rarity = Rarities.Info[r.Rarity] or Rarities.Info.Common
				local elementId = if species then species.Element else "Fire"

				local bb = trove:AddInstance(Instance.new("BillboardGui"))
				bb.Name = "ClusterRevealTag_" .. tostring(i)
				bb.Adornee = root
				bb.Size = UDim2.fromOffset(172, 68)
				bb.StudsOffset = Vector3.new(0, 3.6, 0)
				bb.AlwaysOnTop = true
				bb.MaxDistance = 120
				bb.Parent = screenGui

				local plate = UI.new("Frame", {
					Size = UDim2.fromScale(1, 1),
					BackgroundColor3 = UI.Colors.IronOuter,
					Parent = bb,
				})
				UI.corner(plate, 8)
				UI.stroke(plate, rarity.Color, 2.0)

				local wood = UI.new("Frame", {
					Position = UDim2.fromOffset(4, 4),
					Size = UDim2.new(1, -8, 1, -8),
					BackgroundColor3 = UI.Colors.Panel,
					Parent = plate,
				})
				UI.woodPlanks(wood, 2, 2, 5)

				local badge = buildElementBadge(plate, elementId, 32, 4)
				badge.AnchorPoint = Vector2.new(0, 0.5)
				badge.Position = UDim2.new(0, 8, 0.5, 0)

				UI.label(plate, string.format("<font color=\"#%s\"><b>%s</b></font>%s", rarity.Color:ToHex(), r.Rarity:upper(), if r.Released then " • +Essence" else ""), 11, {
					Position = UDim2.fromOffset(46, 8),
					Size = UDim2.new(1, -52, 0, 16),
					TextWrapped = false,
					ZIndex = 5,
				})
				UI.label(plate, "<b>" .. (if species then species.Name else r.Species) .. "</b>", 15, {
					Font = UI.FontDisplay,
					Position = UDim2.fromOffset(46, 25),
					Size = UDim2.new(1, -52, 0, 22),
					TextColor3 = UI.Colors.Gold,
					TextStrokeColor3 = UI.Colors.WoodDark,
					TextStrokeTransparency = 0.18,
					TextWrapped = false,
					TextTruncate = Enum.TextTruncate.AtEnd,
					ZIndex = 5,
				})

				if r.IsNew then
					buildNewBadge(plate, UDim2.new(1, -4, 0, 2), Vector2.new(1, 0), 7)
				end
			end
		end

		-- Bottom summary Viking bar for the 4-egg multi-hatch
		local summary = trove:AddInstance(UI.new("Frame", {
			Name = "VikingClusterBanner",
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, 70),
			Size = UDim2.new(0.88, 0, 0, 58),
			BackgroundColor3 = UI.Colors.IronOuter,
			ZIndex = 56,
			Parent = screenGui,
		}))
		UI.new("UISizeConstraint", { MaxSize = Vector2.new(430, 58), Parent = summary })
		UI.ironWoodPlaque(summary, 2, 8, 7, 1)
		UI.label(summary, string.format("<b>Hatched %d Dragons!</b>  •  Tap anywhere to continue", #results), 16, {
			Font = UI.FontDisplay,
			Size = UDim2.fromScale(1, 1),
			TextXAlignment = Enum.TextXAlignment.Center,
			TextColor3 = UI.Colors.Gold,
			TextStrokeColor3 = UI.Colors.WoodDark,
			TextStrokeTransparency = 0.2,
			ZIndex = 60,
		})
		local slideIn = TweenService:Create(summary, TweenInfo.new(0.26, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Position = UDim2.new(0.5, 0, 1, -20),
		})
		trove:AddTween(slideIn)
		slideIn:Play()
	end

	return clickCatcher
end

return HatchCelebrationFX
