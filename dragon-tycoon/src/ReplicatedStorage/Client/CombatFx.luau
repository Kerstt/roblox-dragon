-- ReplicatedStorage/Client/CombatFx
-- Skill visuals and floating combat text. Purely cosmetic: everything here is
-- driven by "Fx" messages from the server (CombatService), which already decided
-- the outcome. Spectators get the same effects, so fights look alive from the ground.

local Debris = game:GetService("Debris")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared

local Elements = require(Shared.Elements)
local SkillCatalog = require(Shared.SkillCatalog)
local DragonMotionController = require(script.Parent.DragonMotionController)

local CombatFx = {}

local MAX_DISTANCE = 800 -- skip effects further than this from the camera
local FIRE = "rbxasset://textures/particles/fire_main.dds"
local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"

local folder: Folder

local function fxFolder(): Folder
	if not folder or not folder.Parent then
		folder = Instance.new("Folder")
		folder.Name = "CombatFx"
		folder.Parent = workspace
	end
	return folder
end

local function rootOf(model: any): BasePart?
	if typeof(model) == "Instance" and model:IsA("Model") and model.Parent then
		return model.PrimaryPart
	end
	return nil
end

local function near(position: Vector3): boolean
	return (workspace.CurrentCamera.CFrame.Position - position).Magnitude < MAX_DISTANCE
end

local function colorOf(element: any): Color3
	local info = Elements.Info[element]
	return if info then info.Color else Color3.fromRGB(255, 220, 150)
end

-- Where breath and bolts come from: in front of and above the body center.
local function mouthOf(model: Model, root: BasePart): Vector3
	local length = model:GetAttribute("Length") or 36
	local foot = model:GetAttribute("FootOffset") or 6
	return root.Position + root.CFrame.LookVector * length * 0.42 + root.CFrame.UpVector * foot * 0.5
end

local function part(props: { [string]: any }): BasePart
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	for k, v in props do
		(p :: any)[k] = v
	end
	p.Parent = fxFolder()
	return p
end

local function tween(inst: Instance, seconds: number, goal: { [string]: any })
	TweenService:Create(inst, TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), goal):Play()
end

-- An expanding, fading sphere.
local function burst(position: Vector3, color: Color3, size: number, seconds: number)
	local ball = part({ Shape = Enum.PartType.Ball, Size = Vector3.one * 2, Color = color, Transparency = 0.25, CFrame = CFrame.new(position) })
	tween(ball, seconds, { Size = Vector3.one * size, Transparency = 1 })
	Debris:AddItem(ball, seconds + 0.1)
end

local function sparks(position: Vector3, color: Color3, count: number, texture: string?)
	local holder = part({ Size = Vector3.one, Transparency = 1, CFrame = CFrame.new(position) })
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = texture or SPARKLE
	emitter.Color = ColorSequence.new(color)
	emitter.LightEmission = 1
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 3), NumberSequenceKeypoint.new(1, 0) })
	emitter.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
	emitter.Lifetime = NumberRange.new(0.4, 0.8)
	emitter.Speed = NumberRange.new(20, 45)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Rate = 0
	emitter.Parent = holder
	emitter:Emit(count)
	Debris:AddItem(holder, 1.2)
end

-- Floating text over a dragon (damage numbers, "Dodged!", ...).
local function floatText(model: any, text: string, color: Color3, scale: number?)
	local root = rootOf(model)
	if not root or not near(root.Position) then
		return
	end
	local foot = (model :: Model):GetAttribute("FootOffset") or 6
	local gui = Instance.new("BillboardGui")
	gui.Adornee = root
	gui.AlwaysOnTop = true
	gui.Size = UDim2.fromOffset(220, 60)
	gui.StudsOffset = Vector3.new(math.random(-6, 6), foot * 2.2, 0)
	gui.LightInfluence = 0
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.Text = text
	label.TextColor3 = color
	label.TextStrokeTransparency = 0.2
	label.Parent = gui
	gui.Size = UDim2.fromOffset(220 * (scale or 1), 46 * (scale or 1))
	gui.Parent = fxFolder()
	tween(gui, 1, { StudsOffset = gui.StudsOffset + Vector3.new(0, 10, 0) })
	task.delay(0.55, function()
		tween(label, 0.45, { TextTransparency = 1, TextStrokeTransparency = 1 })
	end)
	Debris:AddItem(gui, 1.1)
end

-- Skill kinds ------------------------------------------------------------------------

local function bolt(caster: Model, casterRoot: BasePart, target: Model, color: Color3, travel: number, big: boolean)
	local targetRoot = rootOf(target)
	if not targetRoot then
		return
	end
	local start = mouthOf(caster, casterRoot)
	local size = if big then 7 else 3.5
	local ball = part({ Shape = Enum.PartType.Ball, Size = Vector3.one * size, Color = color, CFrame = CFrame.new(start) })
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = if big then 30 else 16
	light.Brightness = 3
	light.Parent = ball
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, size * 0.35, 0)
	a0.Parent = ball
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, -size * 0.35, 0)
	a1.Parent = ball
	local trail = Instance.new("Trail")
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Color = ColorSequence.new(color)
	trail.LightEmission = 1
	trail.Lifetime = 0.35
	trail.Transparency = NumberSequence.new(0.2, 1)
	trail.FaceCamera = true
	trail.Parent = ball
	local started = os.clock()
	local duration = math.max(travel, 0.08)
	local connection
	connection = RunService.RenderStepped:Connect(function()
		local alpha = math.min(1, (os.clock() - started) / duration)
		local goal = if targetRoot.Parent then targetRoot.Position else ball.Position
		local arc = Vector3.new(0, math.sin(alpha * math.pi) * 6, 0)
		ball.CFrame = CFrame.new(start:Lerp(goal, alpha) + arc)
		if alpha >= 1 then
			connection:Disconnect()
			burst(ball.Position, color, if big then 30 else 14, 0.35)
			sparks(ball.Position, color, if big then 40 else 15)
			ball:Destroy()
		end
	end)
end

local function breath(caster: Model, casterRoot: BasePart, color: Color3, skill: any)
	local length = caster:GetAttribute("Length") or 36
	local foot = caster:GetAttribute("FootOffset") or 6
	local duration = skill.Duration or 1.2
	local attachment = Instance.new("Attachment")
	attachment.Name = "BreathFx"
	attachment.Position = Vector3.new(0, foot * 0.5, -length * 0.42)
	attachment.Parent = casterRoot
	-- Western dragons: breathe from the mouth itself (it moves with the head),
	-- after the charge-up of the Breath action.
	local delayStart = 0
	local mouth = caster:FindFirstChild("Mouth_VFX", true) or caster:FindFirstChild("MouthAttachment", true)
	if mouth and mouth:IsA("Attachment") and mouth.Parent and mouth.Parent:IsA("BasePart") then
		attachment.Parent = mouth.Parent
		attachment.CFrame = mouth.CFrame
		DragonMotionController.PlayAction(caster, "Breath", { Duration = duration })
		delayStart = 0.58
	end
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = if skill.Id:find("Frost") or skill.Id:find("Sun") or skill.Id:find("Solar") then SPARKLE else FIRE
	emitter.EmissionDirection = Enum.NormalId.Front
	emitter.Color = ColorSequence.new(Color3.new(1, 1, 1):Lerp(color, 0.35), color)
	emitter.LightEmission = 0.9
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2.5), NumberSequenceKeypoint.new(1, 11) })
	emitter.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
	emitter.Lifetime = NumberRange.new(0.5, 0.75)
	emitter.Speed = NumberRange.new((skill.Range or 55) * 1.2, (skill.Range or 55) * 1.5)
	emitter.SpreadAngle = Vector2.new(skill.Cone * 0.45, skill.Cone * 0.45)
	emitter.Rate = if skill.Ultimate then 220 else 140
	emitter.Enabled = delayStart == 0
	emitter.Parent = attachment
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = 30
	light.Brightness = 3
	light.Enabled = delayStart == 0
	light.Parent = attachment
	if delayStart > 0 then
		task.delay(delayStart, function()
			emitter.Enabled = true
			light.Enabled = true
		end)
	end
	task.delay(delayStart + duration, function()
		emitter.Enabled = false
		light.Enabled = false
	end)
	Debris:AddItem(attachment, delayStart + duration + 1)
end

local function slash(target: Model, color: Color3, big: boolean)
	local root = rootOf(target)
	if not root then
		return
	end
	local length = (if big then 1.4 else 1) * (target:GetAttribute("Length") or 36) * 0.7
	for i, angle in { 35, -35, 0 } do
		if i == 3 and not big then
			break
		end
		local streak = part({ Size = Vector3.new(0.8, 0.8, length), Color = color, Transparency = 0.1,
			CFrame = CFrame.lookAt(root.Position, workspace.CurrentCamera.CFrame.Position) * CFrame.Angles(0, 0, math.rad(angle)) * CFrame.Angles(math.rad(90), 0, 0) })
		tween(streak, 0.35, { Transparency = 1, Size = Vector3.new(0.2, 0.2, length * 1.3) })
		Debris:AddItem(streak, 0.4)
	end
	sparks(root.Position, color, if big then 50 else 20)
end

local function nova(caster: Model, casterRoot: BasePart, color: Color3, radius: number, big: boolean)
	local position = casterRoot.Position
	burst(position, color, radius * 2, 0.5)
	local ring = part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(1, 4, 4), Color = color, Transparency = 0.1,
		CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90)) })
	tween(ring, 0.5, { Size = Vector3.new(0.6, radius * 2.2, radius * 2.2), Transparency = 1 })
	Debris:AddItem(ring, 0.6)
	sparks(position, color, if big then 80 else 35, SMOKE)
end

-- Shield bubbles, one per dragon.
local bubbles: { [Model]: BasePart } = {}
local function shield(model: any, seconds: number)
	local root = rootOf(model)
	if not root then
		return
	end
	local old = bubbles[model]
	if old then
		old:Destroy()
	end
	local size = ((model :: Model):GetAttribute("Length") or 36) * 1.05
	local bubble = part({ Shape = Enum.PartType.Ball, Size = Vector3.one * size, Material = Enum.Material.ForceField,
		Color = Color3.fromRGB(150, 210, 255), Transparency = 0.1, CFrame = root.CFrame })
	bubbles[model] = bubble
	local weld = Instance.new("WeldConstraint")
	bubble.Anchored = false
	bubble.Massless = true
	weld.Part0 = root
	weld.Part1 = bubble
	weld.Parent = bubble
	bubble.Parent = model -- moves with the dragon
	task.delay(seconds, function()
		if bubbles[model] == bubble then
			bubbles[model] = nil
		end
		bubble:Destroy()
	end)
end

local function breakShield(model: any)
	local bubble = bubbles[model]
	if bubble then
		bubbles[model] = nil
		sparks(bubble.Position, Color3.fromRGB(170, 220, 255), 40)
		bubble:Destroy()
	end
	floatText(model, "Shield broken!", Color3.fromRGB(170, 220, 255), 0.8)
end

-- Raid boss ----------------------------------------------------------------------------

local WARNING = Color3.fromRGB(255, 60, 50)

-- A red warning shape that fills up until the attack lands.
local function telegraph(p: any)
	local time = tonumber(p.Time) or 1.5
	if typeof(p.Origin) ~= "Vector3" or not near(p.Origin) then
		return
	end
	local shapes = {}
	if p.Shape == "Cone" and typeof(p.Direction) == "Vector3" then
		-- A cone drawn as a row of growing spheres along the breath direction.
		local range = tonumber(p.Range) or 120
		local spread = math.tan(math.rad(tonumber(p.Angle) or 30))
		for _, along in { 0.22, 0.45, 0.68, 0.9 } do
			local distance = range * along
			local radius = math.max(6, distance * spread)
			table.insert(shapes, { p.Origin + p.Direction * distance, radius })
		end
	else
		table.insert(shapes, { p.Origin, tonumber(p.Radius) or 30 })
	end
	for _, s in shapes do
		local outer = part({ Shape = Enum.PartType.Ball, Size = Vector3.one * s[2] * 2, Color = WARNING, Material = Enum.Material.ForceField,
			Transparency = 0.15, CFrame = CFrame.new(s[1]) })
		local inner = part({ Shape = Enum.PartType.Ball, Size = Vector3.one * 2, Color = WARNING, Transparency = 0.75, CFrame = CFrame.new(s[1]) })
		TweenService:Create(inner, TweenInfo.new(time, Enum.EasingStyle.Linear), { Size = Vector3.one * s[2] * 2 }):Play()
		Debris:AddItem(outer, time + 0.05)
		Debris:AddItem(inner, time + 0.05)
	end
end

local function bossOrb(p: any)
	local caster = p.Caster
	local casterRoot = rootOf(caster)
	if not casterRoot or not near(casterRoot.Position) then
		return
	end
	bolt(caster, casterRoot, p.Target, colorOf(p.Element), tonumber(p.Travel) or 1, true)
end

local function bossBreath(p: any)
	local caster = p.Caster
	local casterRoot = rootOf(caster)
	if not casterRoot or not near(casterRoot.Position) then
		return
	end
	breath(caster, casterRoot, colorOf(p.Element), { Id = "BossBreath", Range = tonumber(p.Range) or 120, Cone = 32, Duration = tonumber(p.Duration) or 1, Ultimate = true })
end

-- Entry point --------------------------------------------------------------------

function CombatFx.Play(kind: string, payload: any)
	if type(payload) ~= "table" then
		return
	end
	if kind == "Cast" then
		local caster = payload.Caster
		local casterRoot = rootOf(caster)
		local skill = SkillCatalog.Get(payload.Skill)
		if not casterRoot or not skill or not near(casterRoot.Position) then
			return
		end
		local color = colorOf(payload.Element)
		local big = payload.Ultimate == true
		-- The caster acts it out (breath plays its own action inside breath()).
		if skill.Kind == "Strike" then
			DragonMotionController.PlayAction(caster, "TailWhip")
		elseif skill.Kind == "Nova" or (big and skill.Kind ~= "Breath") then
			DragonMotionController.PlayAction(caster, "Roar")
		end
		if big then
			floatText(caster, skill.Name .. "!", Color3.fromRGB(255, 215, 120), 1.2)
			burst(casterRoot.Position, color, 40, 0.5)
		end
		if skill.Kind == "Bolt" then
			bolt(caster, casterRoot, payload.Target, color, payload.Travel or 0.3, big)
		elseif skill.Kind == "Breath" then
			breath(caster, casterRoot, color, skill)
		elseif skill.Kind == "Strike" then
			task.delay(0.25, slash, payload.Target, color, big)
		elseif skill.Kind == "Nova" then
			task.delay(0.3, nova, caster, casterRoot, color, skill.Radius or 40, big)
		else
			sparks(casterRoot.Position, color, 30)
		end
	elseif kind == "Hit" then
		local color = if payload.Kind == "Strong" then Color3.fromRGB(255, 150, 60)
			elseif payload.Kind == "Weak" then Color3.fromRGB(180, 180, 180)
			else Color3.fromRGB(255, 255, 255)
		local text = tostring(payload.Amount or 0) .. (if payload.Kind == "Strong" then "!" else "")
		if payload.Shielded then
			text ..= " (shield)"
		end
		floatText(payload.Model, text, color, if payload.Kind == "Strong" then 1.15 else 0.9)
	elseif kind == "Miss" then
		floatText(payload.Model, tostring(payload.Text or "Miss"), Color3.fromRGB(200, 230, 255), 0.8)
	elseif kind == "Heal" then
		floatText(payload.Model, "+" .. tostring(payload.Amount or 0), Color3.fromRGB(110, 230, 130), 0.85)
		local root = rootOf(payload.Model)
		if root then
			sparks(root.Position, Color3.fromRGB(110, 230, 130), 15)
		end
	elseif kind == "Shield" then
		shield(payload.Model, tonumber(payload.Until) or 5)
	elseif kind == "ShieldBreak" then
		breakShield(payload.Model)
	elseif kind == "Dodge" then
		local root = rootOf(payload.Model)
		if root then
			sparks(root.Position, Color3.fromRGB(220, 230, 255), 12, SMOKE)
		end
	elseif kind == "Telegraph" then
		telegraph(payload)
	elseif kind == "BossOrb" then
		bossOrb(payload)
	elseif kind == "BossBreath" then
		bossBreath(payload)
	elseif kind == "BossSlam" or kind == "BossMeteor" then
		if typeof(payload.Origin) == "Vector3" and near(payload.Origin) then
			local color = colorOf(payload.Element)
			burst(payload.Origin, color, (tonumber(payload.Radius) or 30) * 2, 0.5)
			sparks(payload.Origin, color, 60, if kind == "BossMeteor" then FIRE else SMOKE)
		end
	elseif kind == "Down" then
		floatText(payload.Model, "Down!", Color3.fromRGB(255, 110, 100), 1.1)
	elseif kind == "Revive" then
		floatText(payload.Model, "Back in the fight!", Color3.fromRGB(120, 240, 140), 0.9)
		local root = rootOf(payload.Model)
		if root then
			sparks(root.Position, Color3.fromRGB(120, 240, 140), 30)
		end
	end
end

return CombatFx
