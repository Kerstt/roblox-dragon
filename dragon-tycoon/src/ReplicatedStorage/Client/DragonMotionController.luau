--!strict
-- ReplicatedStorage/Client/DragonMotionController
-- Animates every dragon tagged "AnimatedDragon" near the camera, on each
-- player's device (no animation traffic over the network).
--
-- Each frame, for each dragon:
--   1. State machine from what every client can see (speed, climb rate, height
--      above ground): Idle, Walk, Run (gallop), Takeoff, Hover, Fly, Glide, Dive,
--      Land. Params blend smoothly between states.
--   2. Secondary motion from the real movement: yaw rate (AssemblyAngularVelocity.Y)
--      banks the body and wings into turns, the head leads, and the tail drags
--      behind through a chain of delays; vertical speed tilts neck, tail and wings.
--   3. Keyframed clips layered by priority with joint masks (Roar, Breath, Pet,
--      TailWhip, Launch). Their events drive the element effects.
--   4. Element effects (DragonElementalVFX): breath puffs, charge glow, trails
--      above cruise speed, dust on takeoff and landing, lightning arcs.
--
-- Actions:  DragonMotionController.PlayAction(model, "Roar" | "Breath" | "Pet" |
--           "TailWhip", { Duration = n? })   (CombatFx calls this)
-- The server can trigger an action for everyone by setting the model attribute
-- Action = "<name>@<time>" (one attribute, so the name and the moment arrive
-- together; the petting prompt does this).

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local DragonAnimation = require(Shared:WaitForChild("DragonAnimation")) :: any
local DragonElementalVFX = require(Shared:WaitForChild("DragonElementalVFX")) :: any
local FlightConfig = require(Shared:WaitForChild("FlightConfig")) :: any

local DragonMotionController = {}

-- TUNING ---------------------------------------------------------------------------
local MAX_DISTANCE = 400 -- don't animate dragons farther than this
local EFFECTS_DISTANCE = 220 -- element effects switch off beyond this (phones)
local RUN_SPEED = (FlightConfig.GroundSpeed + FlightConfig.RunSpeed) / 2 -- ground speed where the trot becomes a gallop
local TURN_FULL = 1.2 -- yaw rate (rad/s) that counts as a full turn (Turn = 1)
local TURN_FOLLOW = 3 -- how quickly the body follows turn changes (per second)
local TAIL_FOLLOW = 2.4 -- each tail segment follows the one before at this rate: lower = lazier, longer drag
local CLIMB_FULL = 40 -- vertical speed (studs/s) that counts as a full climb or dive
local CLIMB_FOLLOW = 2.5
local AIR_FOLLOW = 3 -- how fast banking fades in after takeoff
------------------------------------------------------------------------------------

type Playing = { Clip: any, Start: number, Fired: { [number]: boolean } }

type Entry = {
	Model: Model,
	Root: BasePart,
	Motors: { [string]: Motor6D },
	Western: boolean,
	NeckMotors: { string },
	TailMotors: { string },
	Params: any,
	Flap: number,
	Stride: number,
	Seed: number,
	LastYaw: number,
	Turn: number,
	TailTurn: { number },
	Climb: number,
	Airborne: number,
	State: string,
	Grounded: boolean,
	Size: number,
	Foot: number,
	IdleAction: string?,
	IdleUntil: number,
	NextIdle: number,
	Playing: { Playing },
	Vfx: any,
	EffectsOn: boolean,
	Conn: RBXScriptConnection?,
}

local entries: { [Model]: Entry } = {}
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.RespectCanCollide = true

local function chain(motors: { [string]: Motor6D }, first: string, prefix: string): { string }
	local list = {}
	if motors[first] then
		table.insert(list, first)
	end
	local i = 2
	while motors[prefix .. i] do
		table.insert(list, prefix .. i)
		i += 1
	end
	return list
end

function DragonMotionController.PlayAction(model: Model, name: string, options: { [string]: any }?)
	local entry = entries[model]
	if not entry then
		return
	end
	local clip = DragonAnimation.MakeClip(name, options and options.Duration)
	if not clip then
		return
	end
	-- One clip per priority: a new action replaces the one it would fight with.
	for i = #entry.Playing, 1, -1 do
		local p = entry.Playing[i]
		if p.Clip.Priority == clip.Priority then
			entry.Vfx:Event("ActionEnd")
			table.remove(entry.Playing, i)
		end
	end
	table.insert(entry.Playing, { Clip = clip, Start = os.clock(), Fired = {} })
	table.sort(entry.Playing, function(a, b)
		return a.Clip.Priority < b.Clip.Priority
	end)
end

local function add(model: Instance)
	if not model:IsA("Model") or entries[model] then
		return
	end
	local root = model:WaitForChild("Root", 5) :: BasePart?
	if not root or not model.Parent then
		return
	end
	root:WaitForChild("Body", 3) -- joints arrive with the model; give replication a moment
	local motors: { [string]: Motor6D } = {}
	for _, d in root:GetChildren() do
		if d:IsA("Motor6D") then
			motors[d.Name] = d
		end
	end
	local western = motors.Neck ~= nil
	local tails = if western then chain(motors, "Tail1", "Tail") else (if motors.Tail then { "Tail" } else {})
	-- Tail1, Tail2.. : chain() looks for Tail2, Tail3 after Tail1
	local tailTurn = {}
	for i = 1, math.max(1, #tails) do
		tailTurn[i] = 0
	end
	local entry: Entry = {
		Model = model,
		Root = root,
		Motors = motors,
		Western = western,
		NeckMotors = chain(motors, "Neck", "Neck"),
		TailMotors = tails,
		Params = DragonAnimation.States.Idle,
		Flap = math.random() * 6.28,
		Stride = math.random() * 6.28,
		Seed = math.random() * 100,
		LastYaw = 0,
		Turn = 0,
		TailTurn = tailTurn,
		Climb = 0,
		Airborne = 0,
		State = "Idle",
		Grounded = true,
		Size = ((model:GetAttribute("Length") or 36) :: number) / 36,
		Foot = (model:GetAttribute("FootOffset") or 6) :: number,
		IdleAction = nil,
		IdleUntil = 0,
		NextIdle = os.clock() + 6 + math.random() * 20,
		Playing = {},
		Vfx = DragonElementalVFX.Bind(model),
		EffectsOn = true,
		Conn = nil,
	}
	entries[model] = entry
	-- Server-triggered actions (e.g. petting), seen by every client.
	entry.Conn = model:GetAttributeChangedSignal("Action"):Connect(function()
		local value = model:GetAttribute("Action")
		local name = if type(value) == "string" then value:match("^(%a+)") else nil
		if name then
			DragonMotionController.PlayAction(model, name)
		end
	end)
end

local function remove(model: Instance)
	local entry = entries[model :: Model]
	if entry and entry.Conn then
		entry.Conn:Disconnect()
	end
	entries[model :: Model] = nil
end

-- Movement state from what everyone can see.
local function stateOf(entry: Entry): (string, number, number)
	local root = entry.Root
	if root.Anchored then
		return "Idle", 0, 0
	end
	local velocity = root.AssemblyLinearVelocity
	local horizontal = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
	local foot = entry.Foot
	rayParams.FilterDescendantsInstances = { entry.Model }
	local hit = workspace:Raycast(root.Position + Vector3.new(0, foot, 0), Vector3.new(0, -(foot * 6 + 40), 0), rayParams)
	local height = if hit then root.Position.Y - hit.Position.Y - foot else math.huge
	if height < 1.5 then
		if velocity.Y > 6 then
			return "Takeoff", horizontal, velocity.Y
		end
		if horizontal > RUN_SPEED then
			return "Run", horizontal, velocity.Y
		end
		return (if horizontal > 2 then "Walk" else "Idle"), horizontal, velocity.Y
	end
	if velocity.Y < -4 and height < foot * 3 then
		return "Land", horizontal, velocity.Y -- flare before touchdown
	end
	if velocity.Y > 8 then
		return (if horizontal < 20 then "Takeoff" else "Hover"), horizontal, velocity.Y
	end
	if horizontal < 14 then
		return "Hover", horizontal, velocity.Y
	end
	if velocity.Y < -25 then
		return "Dive", horizontal, velocity.Y
	end
	if velocity.Y < -6 then
		return "Glide", horizontal, velocity.Y
	end
	return "Fly", horizontal, velocity.Y
end

local function targetsFor(entry: Entry, joint: string): { string }
	if joint == "Neck" and #entry.NeckMotors > 0 then
		return entry.NeckMotors
	elseif joint == "Tail" then
		return entry.TailMotors
	end
	return { joint }
end

local function step(dt: number)
	local camera = workspace.CurrentCamera
	local camPos = if camera then camera.CFrame.Position else Vector3.zero
	local t = os.clock()
	for model, entry in entries do
		if not model.Parent then
			remove(model)
			continue
		end
		local root = entry.Root
		local distance = (root.Position - camPos).Magnitude
		local wantEffects = distance < EFFECTS_DISTANCE
		if wantEffects ~= entry.EffectsOn then
			entry.EffectsOn = wantEffects
			entry.Vfx:SetActive(wantEffects)
		end
		if distance > MAX_DISTANCE then
			continue
		end

		-- 1. State
		local state, groundSpeed, vy = stateOf(entry)
		local grounded = DragonAnimation.GroundStates[state] == true
		if grounded and state == "Idle" then
			if not entry.IdleAction and t > entry.NextIdle and #entry.Playing == 0 then
				local action = DragonAnimation.IdleActions[math.random(1, #DragonAnimation.IdleActions)]
				entry.IdleAction = action.Name
				entry.IdleUntil = t + action.Duration
			end
			if entry.IdleAction and t < entry.IdleUntil then
				state = entry.IdleAction :: string
			elseif entry.IdleAction then
				entry.IdleAction = nil
				entry.NextIdle = t + 12 + math.random() * 25
			end
		else
			entry.IdleAction = nil
		end
		-- Takeoff and landing moments.
		if entry.Grounded and not grounded and state == "Takeoff" then
			DragonMotionController.PlayAction(model, "Launch") -- its event kicks up the dust
		elseif not entry.Grounded and grounded and not root.Anchored then
			entry.Vfx:Event("Land")
		end
		entry.Grounded = grounded
		entry.State = state

		entry.Params = DragonAnimation.Blend(entry.Params, DragonAnimation.States[state], dt, if state == "Land" or state == "Takeoff" then 5 else 3)
		entry.Flap += dt * entry.Params.FlapRate * 2 * math.pi
		-- One full stride cycle per ~2.4 foot-lengths travelled (no foot skating)
		local strideLength = math.max(4, entry.Foot * 2.4) * (1 + 0.5 * entry.Params.Gallop)
		local strideSpeed = if groundSpeed > 0.5 then groundSpeed / strideLength else 0.15
		entry.Stride += dt * strideSpeed * 2 * math.pi * entry.Params.Stride

		-- 2. Secondary motion
		local yawRate: number
		if root.Anchored then
			local look = root.CFrame.LookVector
			local yaw = math.atan2(-look.X, -look.Z)
			local dYaw = (yaw - entry.LastYaw + math.pi) % (2 * math.pi) - math.pi
			entry.LastYaw = yaw
			yawRate = dYaw / math.max(dt, 1e-3)
		else
			yawRate = root.AssemblyAngularVelocity.Y
		end
		local turnTarget = math.clamp(yawRate / TURN_FULL, -1, 1)
		entry.Turn += (turnTarget - entry.Turn) * math.min(1, dt * TURN_FOLLOW)
		-- each tail segment chases the one in front of it: a travelling delay
		local lead = entry.Turn
		for i = 1, #entry.TailTurn do
			entry.TailTurn[i] += (lead - entry.TailTurn[i]) * math.min(1, dt * TAIL_FOLLOW)
			lead = entry.TailTurn[i]
		end
		local climbTarget = if grounded then 0 else math.clamp(vy / CLIMB_FULL, -1, 1)
		entry.Climb += (climbTarget - entry.Climb) * math.min(1, dt * CLIMB_FOLLOW)
		entry.Airborne += ((if grounded then 0 else 1) - entry.Airborne) * math.min(1, dt * AIR_FOLLOW)

		-- Base pose
		local pose: { [string]: CFrame }
		if entry.Western then
			pose = DragonAnimation.PoseWestern(entry.Params, t + entry.Seed, entry.Flap, entry.Stride, {
				Turn = entry.Turn,
				TailTurn = entry.TailTurn,
				Climb = entry.Climb,
				Necks = #entry.NeckMotors,
				Tails = #entry.TailMotors,
				Airborne = entry.Airborne,
			}, entry.Size)
		else
			pose = DragonAnimation.Pose(entry.Params, t + entry.Seed, entry.Flap, entry.Stride, entry.Turn, entry.Size)
		end

		-- 3. Clips, lowest priority first; each fades in and out and only moves its masked joints.
		for i = #entry.Playing, 1, -1 do
			local playing = entry.Playing[i]
			local clip = playing.Clip
			local elapsed = t - playing.Start
			for k, event in clip.Events do
				if not playing.Fired[k] and elapsed >= event.T then
					playing.Fired[k] = true
					entry.Vfx:Event(event.Name)
				end
			end
			if elapsed >= clip.Duration then
				entry.Vfx:Event("ActionEnd")
				table.remove(entry.Playing, i)
			end
		end
		for _, playing in entry.Playing do
			local clip = playing.Clip
			local elapsed = t - playing.Start
			local weight = math.min(1, elapsed / clip.FadeIn, (clip.Duration - elapsed) / clip.FadeOut)
			weight = math.clamp(weight, 0, 1)
			local offsets = DragonAnimation.SampleClip(clip, elapsed, entry.Size)
			for joint, offset in offsets do
				if clip.Mask == nil or clip.Mask[joint] then
					local targets = targetsFor(entry, joint)
					local share = 1 / math.max(1, #targets)
					for _, target in targets do
						if entry.Motors[target] then
							pose[target] = (pose[target] or CFrame.identity) * CFrame.identity:Lerp(offset, weight * share)
						end
					end
				end
			end
			if clip.TailWag then
				for k, target in entry.TailMotors do
					local wag = clip.TailWag * weight / math.max(1, #entry.TailMotors) * 3
					pose[target] = (pose[target] or CFrame.identity)
						* CFrame.Angles(0, wag * math.sin(elapsed * clip.TailWagRate * 2 * math.pi - k * 0.7), 0)
				end
			end
		end

		-- 4. Effects
		if entry.EffectsOn then
			entry.Vfx:Tick(t, dt, {
				State = state,
				Flying = not grounded and not root.Anchored,
				Speed = groundSpeed,
				Calm = state == "Idle" or state == "Walk" or state == "Hover" or state == "Stretch",
			})
		end

		for name, motor in entry.Motors do
			local transform = pose[name]
			if transform then
				motor.Transform = transform
			end
		end
	end
end

function DragonMotionController.start()
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

return DragonMotionController
