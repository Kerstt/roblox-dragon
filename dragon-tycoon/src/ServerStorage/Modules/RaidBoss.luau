-- ServerStorage/Modules/RaidBoss
-- The Elder dragon in co-op raids: a giant version of one of the 16 dragons,
-- flown by the server. Every attack is announced with a red warning shape
-- (Telegraph) before it lands, so players can fly out of it or dodge:
--   Breath   a cone at one player
--   Orbs     a homing orb at every player (dodge with E)
--   Slam     a shockwave around the boss that throws players back
--   Meteors  a blast where each player is now (keep moving!)
-- At half health it roars and shields itself; near the end it enrages.
-- CombatService passes `api` so damage, shields and effects follow the same
-- rules as everything else in combat.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared

local RaidConfig = require(Shared.RaidConfig)
local DragonVisuals = require(script.Parent.DragonVisuals)

local RaidBoss = {}

local rng = Random.new()

function RaidBoss.Spawn(species: string, level: number, center: Vector3): Model?
	local model = DragonVisuals.Build({ Species = species, Rarity = "Legendary", Level = level, Power = 1 }, "Ride")
	if not model then
		return nil
	end
	local scale = RaidConfig.BossScale
	local length = (model:GetAttribute("Length") or 36) * scale
	local foot = (model:GetAttribute("FootOffset") or 6) * scale
	model:ScaleTo(model:GetScale() * scale)
	model:SetAttribute("Length", length)
	model:SetAttribute("FootOffset", foot)
	model:SetAttribute("Boss", true)
	model.Name = "RaidBoss"
	model:PivotTo(CFrame.new(center + Vector3.new(0, 40, 0)))
	local root = model.PrimaryPart :: BasePart
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
	align.Responsiveness = 6
	align.MaxAngularVelocity = 1.6
	align.CFrame = root.CFrame.Rotation
	align.Parent = root
	root.Anchored = false
	CollectionService:AddTag(model, "AnimatedDragon")
	model.Parent = workspace:FindFirstChild("Mounts") or workspace
	root:SetNetworkOwner(nil)
	return model
end

function RaidBoss.NewState(model: Model)
	local root = model.PrimaryPart :: BasePart
	return {
		Velocity = root:FindFirstChild("FlightVelocity") :: LinearVelocity,
		Align = root:FindFirstChild("FlightOrientation") :: AlignOrientation,
		Vel = Vector3.zero,
		Orbit = rng:NextNumber(0, math.pi * 2),
		NextAttack = os.clock() + 3,
		Cooldowns = {},
		Target = nil :: any,
		NextRetarget = 0,
		LockDir = nil :: Vector3?,
		LockUntil = 0,
		Phase = 1,
	}
end

local function mouthOf(boss: any): Vector3
	local root = boss.Root :: BasePart
	local length = boss.Model:GetAttribute("Length") or 90
	return root.Position + root.CFrame.LookVector * length * 0.4
end

local function pickAttack(s: any, t: number): string?
	local total = 0
	local options = {}
	for name, attack in RaidConfig.Attacks do
		if t >= (s.Cooldowns[name] or 0) then
			total += attack.Weight
			table.insert(options, name)
		end
	end
	if total == 0 then
		return nil
	end
	table.sort(options)
	local roll = rng:NextNumber(0, total)
	for _, name in options do
		roll -= RaidConfig.Attacks[name].Weight
		if roll <= 0 then
			return name
		end
	end
	return options[#options]
end

-- Attacks ----------------------------------------------------------------------------

local function breath(boss: any, s: any, api: any)
	local a = RaidConfig.Attacks.Breath
	local target = s.Target
	if not target then
		return
	end
	local origin = mouthOf(boss)
	local toward = target.Root.Position - origin
	if toward.Magnitude < 1 then
		return
	end
	local dir = toward.Unit
	s.LockDir = dir
	s.LockUntil = os.clock() + a.Telegraph + 1
	api.Telegraph({ Shape = "Cone", Origin = origin, Direction = dir, Range = a.Range, Angle = a.Angle, Time = a.Telegraph })
	task.delay(a.Telegraph, function()
		if not api.Fighting(boss.Match) then
			return
		end
		api.Fx("BossBreath", { Caster = boss.Model, Element = boss.Element, Duration = 1, Range = a.Range })
		local cosAngle = math.cos(math.rad(a.Angle))
		for _, p in api.Alive(boss.Match) do
			local offset = p.Root.Position - origin
			if offset.Magnitude <= a.Range and (offset.Magnitude < 1 or dir:Dot(offset.Unit) >= cosAngle) then
				api.BossHit(boss, p, a.Power, nil, false)
			end
		end
	end)
end

local function orbs(boss: any, api: any)
	local a = RaidConfig.Attacks.Orbs
	for _, p in api.Alive(boss.Match) do
		local travel = (p.Root.Position - boss.Root.Position).Magnitude / a.Speed
		api.Fx("BossOrb", { Caster = boss.Model, Target = p.Model, Travel = travel, Element = boss.Element })
		task.delay(travel, function()
			if api.Fighting(boss.Match) and not p.Down and not p.Gone then
				api.BossHit(boss, p, a.Power, nil, true)
			end
		end)
	end
end

local function slam(boss: any, api: any)
	local a = RaidConfig.Attacks.Slam
	local origin = boss.Root.Position
	api.Telegraph({ Shape = "Sphere", Origin = origin, Radius = a.Radius, Time = a.Telegraph })
	task.delay(a.Telegraph, function()
		if not api.Fighting(boss.Match) then
			return
		end
		api.Fx("BossSlam", { Origin = boss.Root.Position, Radius = a.Radius, Element = boss.Element })
		for _, p in api.Alive(boss.Match) do
			if (p.Root.Position - boss.Root.Position).Magnitude <= a.Radius then
				api.BossHit(boss, p, a.Power, { { Status = "Knockback", Value = a.Knockback } }, false)
			end
		end
	end)
end

local function meteors(boss: any, api: any)
	local a = RaidConfig.Attacks.Meteors
	for _, target in api.Alive(boss.Match) do
		local zone = target.Root.Position
		api.Telegraph({ Shape = "Sphere", Origin = zone, Radius = a.Radius, Time = a.Telegraph })
		task.delay(a.Telegraph, function()
			if not api.Fighting(boss.Match) then
				return
			end
			api.Fx("BossMeteor", { Origin = zone, Radius = a.Radius, Element = boss.Element })
			for _, p in api.Alive(boss.Match) do
				if (p.Root.Position - zone).Magnitude <= a.Radius then
					api.BossHit(boss, p, a.Power, nil, false)
				end
			end
		end)
	end
end

local ATTACKS = {
	Breath = function(boss, s, api)
		breath(boss, s, api)
	end,
	Orbs = function(boss, _, api)
		orbs(boss, api)
	end,
	Slam = function(boss, _, api)
		slam(boss, api)
	end,
	Meteors = function(boss, _, api)
		meteors(boss, api)
	end,
}

-- Runs every combat tick.
function RaidBoss.Think(boss: any, dt: number, fighting: boolean, api: any)
	local s = boss.BossState
	local root = boss.Root :: BasePart
	local t = os.clock()
	local center = boss.Match.Arena.Center
	local alive = api.Alive(boss.Match)

	-- Pick who to look at (and breathe on).
	if fighting and (#alive > 0) and (t > s.NextRetarget or not s.Target or s.Target.Down or s.Target.Gone) then
		s.Target = alive[rng:NextInteger(1, #alive)]
		s.NextRetarget = t + rng:NextNumber(4, 7)
	end

	-- Slow, heavy circling over the middle of the arena.
	s.Orbit += dt * 0.12
	local goal = center + Vector3.new(math.cos(s.Orbit) * 45, 40 + 6 * math.sin(t * 0.7), math.sin(s.Orbit) * 45)
	local toward = goal - root.Position
	local speed = 26 * math.max(boss.SpeedMul, 0.15)
	local want = if toward.Magnitude > 0.5 then toward.Unit * math.min(speed, toward.Magnitude * 1.2) else Vector3.zero
	if s.Impulse then
		s.Impulse = nil -- too heavy to be knocked around
	end
	s.Vel = s.Vel:Lerp(want, 1 - math.exp(-2 * dt))
	s.Velocity.VectorVelocity = s.Vel

	local face = if s.LockDir and t < s.LockUntil then s.LockDir
		elseif s.Target and s.Target.Root then s.Target.Root.Position - root.Position
		else root.CFrame.LookVector
	local flat = Vector3.new(face.X, 0, face.Z)
	if flat.Magnitude > 0.5 then
		local pitch = math.clamp(math.atan2(face.Y, flat.Magnitude) * 0.4, -0.35, 0.35)
		s.Align.CFrame = CFrame.lookAt(Vector3.zero, flat.Unit) * CFrame.Angles(pitch, 0, 0)
	end

	if not fighting then
		return
	end

	-- Phases
	local share = boss.HP / boss.Stats.MaxHP
	if s.Phase == 1 and share <= RaidConfig.PhaseTwoAt then
		s.Phase = 2
		api.Shield(boss, 0.12, 8)
		api.Announce(boss.Match, boss.Name .. " roars and raises a shield! Break it!")
	elseif s.Phase == 2 and share <= RaidConfig.EnrageAt then
		s.Phase = 3
		api.Empower(boss, 0.25, 600)
		api.Announce(boss.Match, boss.Name .. " is enraged! Finish it!")
	end

	-- Attacks
	if #alive == 0 or t < s.NextAttack or api.Stunned(boss) then
		return
	end
	local name = pickAttack(s, t)
	if not name then
		return
	end
	local attack = RaidConfig.Attacks[name]
	local faster = if s.Phase >= 2 then 0.75 else 1
	s.Cooldowns[name] = t + attack.Cooldown * faster
	local gap = rng:NextNumber(RaidConfig.AttackGap[1], RaidConfig.AttackGap[2]) * faster
	s.NextAttack = t + gap + (attack.Telegraph or 0)
	ATTACKS[name](boss, s, api)
end

return RaidBoss
