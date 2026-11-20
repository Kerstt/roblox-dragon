-- ReplicatedStorage/Client/DragonAnimator
-- Animates every dragon tagged "AnimatedDragon" near the camera.
-- The movement state comes from what every client can see (speed, climb rate,
-- height above ground), so riders and onlookers see the same motion with no
-- extra network traffic. Leg strides are matched to ground speed so feet
-- don't skate, and resting dragons do occasional idle actions.

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DragonAnimation = require(ReplicatedStorage.Shared.DragonAnimation)

local DragonAnimator = {}

local MAX_DISTANCE = 400 -- don't animate dragons farther than this
local EFFECTS_DISTANCE = 220 -- element particle effects switch off beyond this (phones)
local JOINTS = { "Body", "Head", "Tail", "LeftWing", "RightWing", "LeftLeg", "RightLeg" }

type Entry = {
	Model: Model,
	Root: BasePart,
	Motors: { [string]: Motor6D },
	Params: any,
	Flap: number,
	Stride: number,
	Seed: number,
	LastYaw: number,
	Turn: number,
	State: string,
	Size: number,
	Foot: number,
	Action: string?,
	ActionUntil: number,
	NextAction: number,
	Emitters: { ParticleEmitter },
	EffectsOn: boolean,
}

local entries: { [Model]: Entry } = {}
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.RespectCanCollide = true

local function add(model: Instance)
	if not model:IsA("Model") or entries[model] then
		return
	end
	local root = model:WaitForChild("Root", 5) :: BasePart?
	if not root or not model.Parent then
		return
	end
	local motors = {}
	for _, name in JOINTS do
		local motor = root:FindFirstChild(name) or (name ~= "LeftLeg" and name ~= "RightLeg" and root:WaitForChild(name, 3))
		if motor and motor:IsA("Motor6D") then
			motors[name] = motor
		end
	end
	local emitters = {}
	for _, d in model:GetDescendants() do
		if d:IsA("ParticleEmitter") then
			table.insert(emitters, d)
		end
	end
	entries[model] = {
		Model = model,
		Root = root,
		Motors = motors,
		Params = DragonAnimation.States.Idle,
		Flap = math.random() * 6.28,
		Stride = math.random() * 6.28,
		Seed = math.random() * 100,
		LastYaw = 0,
		Turn = 0,
		State = "Idle",
		Size = (model:GetAttribute("Length") or 36) / 36,
		Foot = model:GetAttribute("FootOffset") or 6,
		Action = nil,
		ActionUntil = 0,
		NextAction = os.clock() + 6 + math.random() * 20,
		Emitters = emitters,
		EffectsOn = true,
	}
end

local function remove(model: Instance)
	entries[model :: Model] = nil
end

-- Decide the state from how the dragon is moving.
local function stateOf(entry: Entry): (string, number)
	local root = entry.Root
	if root.Anchored then
		return "Idle", 0
	end
	local velocity = root.AssemblyLinearVelocity
	local horizontal = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
	local foot = entry.Foot
	rayParams.FilterDescendantsInstances = { entry.Model }
	local hit = workspace:Raycast(root.Position + Vector3.new(0, foot, 0), Vector3.new(0, -(foot * 6 + 40), 0), rayParams)
	local height = if hit then root.Position.Y - hit.Position.Y - foot else math.huge
	if height < 1.5 then
		if velocity.Y > 6 then
			return "Takeoff", horizontal
		end
		return if horizontal > 2 then "Walk" else "Idle", horizontal
	end
	if velocity.Y < -4 and height < foot * 3 then
		return "Land", horizontal -- flare before touchdown
	end
	if velocity.Y > 8 then
		return (if horizontal < 20 then "Takeoff" else "Hover"), horizontal
	end
	if horizontal < 14 then
		return "Hover", horizontal
	end
	if velocity.Y < -25 then
		return "Dive", horizontal
	end
	if velocity.Y < -6 then
		return "Glide", horizontal
	end
	return "Fly", horizontal
end

local function step(dt: number)
	local camera = workspace.CurrentCamera
	local camPos = camera and camera.CFrame.Position or Vector3.zero
	local t = os.clock()
	for model, entry in entries do
		if not model.Parent then
			entries[model] = nil
			continue
		end
		local distance = (entry.Root.Position - camPos).Magnitude
		local wantEffects = distance < EFFECTS_DISTANCE
		if wantEffects ~= entry.EffectsOn then
			entry.EffectsOn = wantEffects
			for _, emitter in entry.Emitters do
				emitter.Enabled = wantEffects
			end
		end
		if distance > MAX_DISTANCE then
			continue
		end

		local state, groundSpeed = stateOf(entry)
		-- Idle actions: now and then, stretch the wings.
		if state == "Idle" then
			if not entry.Action and t > entry.NextAction then
				local action = DragonAnimation.IdleActions[math.random(1, #DragonAnimation.IdleActions)]
				entry.Action = action.Name
				entry.ActionUntil = t + action.Duration
			end
			if entry.Action and t < entry.ActionUntil then
				state = entry.Action
			elseif entry.Action then
				entry.Action = nil
				entry.NextAction = t + 12 + math.random() * 25
			end
		else
			entry.Action = nil
		end
		entry.State = state

		-- Wing beats and strides are smoothed so changes never pop.
		entry.Params = DragonAnimation.Blend(entry.Params, DragonAnimation.States[state], dt, if state == "Land" or state == "Takeoff" then 5 else 3)
		entry.Flap += dt * entry.Params.FlapRate * 2 * math.pi
		-- One full stride cycle per ~2.4 foot-lengths travelled (no foot skating)
		local strideLength = math.max(4, entry.Foot * 2.4)
		local strideSpeed = if groundSpeed > 0.5 then groundSpeed / strideLength else 0.15
		entry.Stride += dt * strideSpeed * 2 * math.pi * entry.Params.Stride

		-- Turning rate from the change in heading.
		local look = entry.Root.CFrame.LookVector
		local yaw = math.atan2(-look.X, -look.Z)
		local dYaw = (yaw - entry.LastYaw + math.pi) % (2 * math.pi) - math.pi
		entry.LastYaw = yaw
		local turnTarget = math.clamp(dYaw / math.max(dt, 1e-3) / 1.2, -1, 1)
		entry.Turn += (turnTarget - entry.Turn) * math.min(1, dt * 3)

		local pose = DragonAnimation.Pose(entry.Params, t + entry.Seed, entry.Flap, entry.Stride, entry.Turn, entry.Size)
		for name, motor in entry.Motors do
			local transform = pose[name]
			if transform then
				motor.Transform = transform
			end
		end
	end
end

function DragonAnimator.start()
	for _, model in CollectionService:GetTagged("AnimatedDragon") do
		task.spawn(add, model)
	end
	CollectionService:GetInstanceAddedSignal("AnimatedDragon"):Connect(function(model)
		task.spawn(add, model)
	end)
	CollectionService:GetInstanceRemovedSignal("AnimatedDragon"):Connect(remove)
	-- Stepped runs before physics, so Transforms land this frame.
	RunService.Stepped:Connect(function(_, dt)
		step(dt)
	end)
end

return DragonAnimator
