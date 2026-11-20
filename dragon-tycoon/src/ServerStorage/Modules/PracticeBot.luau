-- ServerStorage/Modules/PracticeBot
-- The AI sparring dragon for Practice mode (never used in Casual or Ranked).
-- The server flies it: it circles the player, closes in for melee and breath
-- skills, backs off for bolts, sometimes dodges incoming shots, and uses its
-- ultimate when charged. It uses exactly the same skill rules as players
-- (CombatService.UseSkill), so it can't cheat.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared

local SkillCatalog = require(Shared.SkillCatalog)
local CombatConfig = require(Shared.CombatConfig)
local DragonVisuals = require(script.Parent.DragonVisuals)

local PracticeBot = {}

local BASE_SPEED = 58 -- studs/s before the dragon's speed multiplier [PLACEHOLDER]
local THINK_MIN, THINK_MAX = 0.5, 1.0 -- seconds between skill decisions (slower than a sharp player)
local DODGE_CHANCE = 0.3

local rng = Random.new()

function PracticeBot.Spawn(entry: any, place: CFrame): Model?
	local model = DragonVisuals.Build({ Species = entry.Species, Rarity = "Common", Level = entry.Level, Power = 1 }, "Ride")
	if not model then
		return nil
	end
	local root = model.PrimaryPart :: BasePart
	model:PivotTo(place)
	model.Name = "PracticeDragon"
	model:SetAttribute("Bot", true)
	local attachment = root:FindFirstChild("RootAttachment") :: Attachment
	local velocity = Instance.new("LinearVelocity")
	velocity.Name = "FlightVelocity"
	velocity.Attachment0 = attachment
	velocity.RelativeTo = Enum.ActuatorRelativeTo.World
	velocity.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	velocity.MaxForce = math.huge
	velocity.VectorVelocity = Vector3.zero
	velocity.Parent = root
	local align = Instance.new("AlignOrientation")
	align.Name = "FlightOrientation"
	align.Mode = Enum.OrientationAlignmentMode.OneAttachment
	align.Attachment0 = attachment
	align.MaxTorque = math.huge
	align.Responsiveness = 9
	align.MaxAngularVelocity = 3
	align.CFrame = root.CFrame.Rotation
	align.Parent = root
	root.Anchored = false
	CollectionService:AddTag(model, "AnimatedDragon")
	local folder = workspace:FindFirstChild("Mounts") or workspace
	model.Parent = folder
	root:SetNetworkOwner(nil) -- the server flies it
	return model
end

function PracticeBot.NewState(model: Model)
	local root = model.PrimaryPart :: BasePart
	return {
		Velocity = root:FindFirstChild("FlightVelocity") :: LinearVelocity,
		Align = root:FindFirstChild("FlightOrientation") :: AlignOrientation,
		Vel = Vector3.zero,
		Orbit = rng:NextNumber(0, math.pi * 2),
		OrbitDir = if rng:NextNumber() < 0.5 then -1 else 1,
		NextThink = os.clock() + 1,
		NextFlip = os.clock() + rng:NextNumber(4, 8),
		Impulse = nil :: Vector3?,
		IncomingAt = nil :: number?,
		Bank = 0,
	}
end

-- Close-range skill ready (or nearly)? Then the bot moves in.
local function wantsClose(f: any, t: number): boolean
	for slot = 1, math.min(f.Unlocked, 4) do
		local skill = SkillCatalog.Get(f.Skills[slot])
		if skill and (skill.Kind == "Strike" or skill.Kind == "Breath" or skill.Kind == "Nova") then
			local ready = f.Cooldowns[slot] - t < 0.6
			if slot == 4 then
				ready = f.Ult >= 100
			end
			if ready then
				return true
			end
		end
	end
	return false
end

local function clampToArena(position: Vector3, center: Vector3): Vector3
	local A = CombatConfig.Arena
	local offset = position - center
	local flat = Vector3.new(offset.X, 0, offset.Z)
	if flat.Magnitude > A.Radius - 30 then
		flat = flat.Unit * (A.Radius - 30)
	end
	local y = math.clamp(offset.Y, A.Floor + 30, A.Ceiling - 30)
	return center + flat + Vector3.new(0, y, 0)
end

-- Runs every combat tick. `api` is CombatService (UseSkill, Dodge).
function PracticeBot.Think(f: any, dt: number, fighting: boolean, api: any)
	local s = f.BotState
	local root = f.Root :: BasePart
	local foe = f.Opponent
	if not foe.Root or not foe.Root.Parent then
		return
	end
	local t = os.clock()
	local position = root.Position
	local target = foe.Root.Position
	local center = f.Match.Arena.Center

	-- Where to fly: circle the player, closer when a melee/breath skill is ready.
	local want = Vector3.zero
	if fighting then
		if t > s.NextFlip then
			s.OrbitDir = -s.OrbitDir
			s.NextFlip = t + rng:NextNumber(4, 8)
		end
		s.Orbit += dt * 0.4 * s.OrbitDir
		local distance = if wantsClose(f, t) then 28 else 85
		local goal = target + Vector3.new(math.cos(s.Orbit), 0, math.sin(s.Orbit)) * distance + Vector3.new(0, 10 * math.sin(t * 0.6), 0)
		goal = clampToArena(goal, center)
		local toward = goal - position
		local speed = BASE_SPEED * math.max(f.SpeedMul, 0.15)
		if toward.Magnitude > 0.5 then
			want = toward.Unit * math.min(speed, toward.Magnitude * 1.6)
		end
		if t < f.LungeUntil then
			local at = target - position
			if at.Magnitude > 1 then
				want = at.Unit * 110
			end
		end
	end
	if s.Impulse then
		s.Vel += s.Impulse
		s.Impulse = nil
	end
	s.Vel = s.Vel:Lerp(want, 1 - math.exp(-3 * dt))
	s.Velocity.VectorVelocity = s.Vel

	-- Face the player while fighting (breath needs it), else face where it flies.
	local faceDir = if fighting then target - position else s.Vel
	local flat = Vector3.new(faceDir.X, 0, faceDir.Z)
	if flat.Magnitude > 0.5 then
		local lateral = root.CFrame.RightVector:Dot(s.Vel)
		s.Bank += (math.clamp(-lateral / 60, -0.6, 0.6) - s.Bank) * (1 - math.exp(-3 * dt))
		local pitch = math.clamp(math.atan2(faceDir.Y, flat.Magnitude) * 0.5, -0.4, 0.4)
		s.Align.CFrame = CFrame.lookAt(Vector3.zero, flat.Unit) * CFrame.Angles(pitch, 0, s.Bank)
	end

	if not fighting then
		return
	end

	-- Dodge an incoming bolt now and then.
	if s.IncomingAt and s.IncomingAt - t < 0.3 then
		if s.IncomingAt > t and rng:NextNumber() < DODGE_CHANCE then
			if api.Dodge(f) then
				s.Impulse = root.CFrame.RightVector * (if rng:NextNumber() < 0.5 then -45 else 45)
			end
		end
		s.IncomingAt = nil
	end

	-- Skills: ultimate first, then the others in a shuffled order.
	if t < s.NextThink then
		return
	end
	s.NextThink = t + rng:NextNumber(THINK_MIN, THINK_MAX)
	local order = { 2, 3, 1 }
	if rng:NextNumber() < 0.5 then
		order[1], order[2] = order[2], order[1]
	end
	table.insert(order, 1, 4)
	for _, slot in order do
		if slot <= f.Unlocked then
			local skill = SkillCatalog.Get(f.Skills[slot])
			-- Save self-heals and shields for when they're useful.
			local selfOnly = skill and skill.Kind == "Self" and not skill.SelfEffects
			if not (selfOnly and f.HP > f.Stats.MaxHP * 0.75) then
				if api.UseSkill(f, slot) then
					return
				end
			end
		end
	end
end

return PracticeBot
