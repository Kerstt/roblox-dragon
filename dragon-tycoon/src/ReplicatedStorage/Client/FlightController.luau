-- ReplicatedStorage/Client/FlightController
-- Steers your own dragon while you sit in its saddle, with weight and momentum:
--   Move (WASD / thumbstick): go where the camera looks; the dragon turns at a
--     natural rate (tighter when slow, wide arcs at speed) and banks into turns
--   Climb: Space / A        Dive: Q, Ctrl or C / B
--   Boost: Shift / L3       Dismount: X / Y        Phones: on-screen buttons
-- Diving trades height for speed; climbing costs speed. Near the ground the
-- dragon flares and lands; on the ground it walks, turning before it moves.
-- The camera follows a smoothed point and widens its view at speed. In flight it
-- swings back behind the dragon unless the rider turns it by hand (right mouse,
-- touch drag, right stick); its normal downward tilt counts as level flight.
-- The server checks speed and position, so this can't break the rules.
--
-- Battles (CombatClient calls these): Dodge(), Lunge(target), Knockback(push),
-- FaceTarget(target, seconds). In a battle the dragon also obeys the server's
-- SpeedMul attribute (slows, stuns, haste) and soft arena walls, and can't be
-- dismounted. Outside battles, dragons are gently kept out of the arenas.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ContextActionService = game:GetService("ContextActionService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local C = require(ReplicatedStorage.Shared.FlightConfig)
local Store = require(script.Parent.Store)
local Hud = require(script.Parent.Hud)

local FlightController = {}

local player = Players.LocalPlayer
local controls: any = nil
local lastCameraInput = 0 -- when the rider last turned the camera by hand

type Ride = {
	Model: Model,
	Root: BasePart,
	Velocity: LinearVelocity,
	Align: AlignOrientation,
	Humanoid: Humanoid,
	Flying: boolean,
	Speed: number, -- forward speed along Heading
	Vy: number, -- vertical speed
	Heading: Vector3, -- flat unit vector
	YawRate: number,
	Pitch: number,
	Bank: number,
	Foot: number,
	Focus: BasePart,
	TakeoffUntil: number,
	Push: Vector3, -- dodges, lunges and knockbacks (decays quickly)
	FaceTarget: BasePart?,
	FaceUntil: number,
	RollUntil: number,
	RollDir: number,
}

local ride: Ride? = nil
local held = { Up = false, Down = false, Boost = false, Forward = false }
local savedZoom = { Min = 0.5, Max = 128 }
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.RespectCanCollide = true -- ignore invisible markers like spawn pads

local function approach(current: number, target: number, up: number, down: number, dt: number): number
	if target > current then
		return math.min(target, current + up * dt)
	end
	return math.max(target, current - down * dt)
end

local function smooth(current: number, target: number, rate: number, dt: number): number
	return current + (target - current) * (1 - math.exp(-rate * dt))
end

-- Roblox's PlayerModule (if this place has it) gives the touch thumbstick.
local function getControls()
	if controls == nil then
		local scripts = player:FindFirstChild("PlayerScripts")
		local module = scripts and scripts:FindFirstChild("PlayerModule")
		if module then
			local ok, result = pcall(function()
				return require(module):GetControls()
			end)
			controls = if ok then result else false
		end
	end
	return controls or nil
end

local KEYS = {
	{ Enum.KeyCode.W, Vector3.new(0, 0, -1) },
	{ Enum.KeyCode.Up, Vector3.new(0, 0, -1) },
	{ Enum.KeyCode.S, Vector3.new(0, 0, 1) },
	{ Enum.KeyCode.Down, Vector3.new(0, 0, 1) },
	{ Enum.KeyCode.A, Vector3.new(-1, 0, 0) },
	{ Enum.KeyCode.Left, Vector3.new(-1, 0, 0) },
	{ Enum.KeyCode.D, Vector3.new(1, 0, 0) },
	{ Enum.KeyCode.Right, Vector3.new(1, 0, 0) },
}

-- Movement input as (x = right, z = back), from whatever the player uses.
local function readMove(): Vector3
	local c = getControls()
	if c then
		local ok, vector = pcall(c.GetMoveVector, c)
		if ok and vector.Magnitude > 0.05 then
			return vector
		end
	end
	local move = Vector3.zero
	if not UserInputService:GetFocusedTextBox() then
		for _, entry in KEYS do
			if UserInputService:IsKeyDown(entry[1]) then
				move += entry[2]
			end
		end
	end
	for _, input in UserInputService:GetGamepadState(Enum.UserInputType.Gamepad1) do
		if input.KeyCode == Enum.KeyCode.Thumbstick1 and input.Position.Magnitude > 0.2 then
			move += Vector3.new(input.Position.X, 0, -input.Position.Y)
		end
	end
	if held.Forward then -- on-screen "Fly" button: go where the camera looks
		move += Vector3.new(0, 0, -1)
	end
	return if move.Magnitude > 1 then move.Unit else move
end

-- Ground height under a point (ray starts above it so a slight dip still finds the floor).
local function groundBelow(position: Vector3, lift: number): number?
	local hit = workspace:Raycast(position + Vector3.new(0, lift, 0), Vector3.new(0, -(600 + lift), 0), rayParams)
	return hit and hit.Position.Y
end

local function stop()
	local r = ride
	if not r then
		return
	end
	ride = nil
	for _, name in { "DragonUp", "DragonDown", "DragonBoost", "DragonDismount", "DragonForward" } do
		ContextActionService:UnbindAction(name)
	end
	held.Up, held.Down, held.Boost, held.Forward = false, false, false, false
	local camera = workspace.CurrentCamera
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		camera.CameraSubject = humanoid
	end
	camera.FieldOfView = C.BaseFov
	player.CameraMinZoomDistance = savedZoom.Min
	player.CameraMaxZoomDistance = savedZoom.Max
	r.Focus:Destroy()
end

local function bindHold(name: string, key: string, title: string, ...: Enum.KeyCode)
	ContextActionService:BindActionAtPriority(name, function(_, state)
		held[key] = state == Enum.UserInputState.Begin or state == Enum.UserInputState.Change
		return Enum.ContextActionResult.Sink -- stops Space from jumping out of the saddle
	end, true, Enum.ContextActionPriority.High.Value, ...)
	ContextActionService:SetTitle(name, title)
end

local function start(model: Model, humanoid: Humanoid)
	local root = model.PrimaryPart :: BasePart
	local velocity = root:WaitForChild("FlightVelocity", 5) :: LinearVelocity?
	local align = root:WaitForChild("FlightOrientation", 5) :: AlignOrientation?
	if not velocity or not align then
		return
	end
	local look = root.CFrame.LookVector * Vector3.new(1, 0, 1)

	-- The camera follows this point, which trails the dragon smoothly.
	local focus = Instance.new("Part")
	focus.Name = "RideCameraFocus"
	focus.Anchored = true
	focus.CanCollide = false
	focus.CanQuery = false
	focus.CanTouch = false
	focus.Transparency = 1
	focus.Size = Vector3.one
	focus.CFrame = root.CFrame
	focus.Parent = workspace.CurrentCamera

	ride = {
		Model = model,
		Root = root,
		Velocity = velocity,
		Align = align,
		Humanoid = humanoid,
		Flying = false,
		Speed = 0,
		Vy = 0,
		Heading = if look.Magnitude > 0.01 then look.Unit else Vector3.new(0, 0, -1),
		YawRate = 0,
		Pitch = 0,
		Bank = 0,
		Foot = model:GetAttribute("FootOffset") or 6,
		Focus = focus,
		TakeoffUntil = 0,
		Push = Vector3.zero,
		FaceTarget = nil,
		FaceUntil = 0,
		RollUntil = 0,
		RollDir = 1,
	}
	rayParams.FilterDescendantsInstances = { model, player.Character :: Instance, focus }
	-- Summoned in mid-air (battle arenas): start flying instead of dropping.
	local below = groundBelow(root.Position, ride.Foot)
	if not below or root.Position.Y - below - ride.Foot > 15 then
		ride.Flying = true
	end

	bindHold("DragonUp", "Up", "Climb", Enum.KeyCode.Space, Enum.KeyCode.ButtonA)
	bindHold("DragonDown", "Down", "Dive", Enum.KeyCode.Q, Enum.KeyCode.LeftControl, Enum.KeyCode.C, Enum.KeyCode.ButtonB)
	bindHold("DragonBoost", "Boost", "Boost", Enum.KeyCode.LeftShift, Enum.KeyCode.ButtonL3)
	bindHold("DragonForward", "Forward", "Fly", Enum.KeyCode.ButtonR2)
	ContextActionService:BindActionAtPriority("DragonDismount", function(_, state)
		if state == Enum.UserInputState.Begin then
			if model:GetAttribute("Locked") then
				Hud.Toast("You can't leave your dragon in the middle of a battle!", Color3.fromRGB(255, 200, 120))
				return Enum.ContextActionResult.Sink
			end
			humanoid.Sit = false
			Store.Request("Dismiss")
		end
		return Enum.ContextActionResult.Sink
	end, true, Enum.ContextActionPriority.High.Value, Enum.KeyCode.X, Enum.KeyCode.ButtonY)
	ContextActionService:SetTitle("DragonDismount", "Land off")
	pcall(function()
		ContextActionService:SetPosition("DragonUp", UDim2.new(1, -95, 1, -230))
		ContextActionService:SetPosition("DragonDown", UDim2.new(1, -165, 1, -170))
		ContextActionService:SetPosition("DragonBoost", UDim2.new(1, -95, 1, -300))
		ContextActionService:SetPosition("DragonDismount", UDim2.new(1, -165, 1, -300))
		ContextActionService:SetPosition("DragonForward", UDim2.new(1, -235, 1, -230))
	end)

	local camera = workspace.CurrentCamera
	camera.CameraSubject = focus
	savedZoom.Min, savedZoom.Max = player.CameraMinZoomDistance, player.CameraMaxZoomDistance
	-- Start the camera at a good distance behind the dragon, then let the player zoom.
	local length = model:GetAttribute("Length") or 36
	player.CameraMaxZoomDistance = math.max(savedZoom.Max, length * 4)
	player.CameraMinZoomDistance = length * 1.4
	task.delay(0.25, function()
		if ride and ride.Model == model then
			player.CameraMinZoomDistance = length * 0.6
		end
	end)
	Hud.Toast("Space: take off  \u{2022}  WASD: fly  \u{2022}  Shift: boost  \u{2022}  Q: dive/land  \u{2022}  X: dismount", Color3.fromRGB(255, 200, 120))
end

local function step(dt: number)
	local r = ride
	if not r then
		return
	end
	if not r.Model.Parent or r.Humanoid.SeatPart == nil then
		stop()
		return
	end
	dt = math.min(dt, 1 / 20)
	local camera = workspace.CurrentCamera
	local move = readMove() -- x = right, z = back
	local position = r.Root.Position
	local ground = groundBelow(position, r.Foot)
	local height = if ground then position.Y - ground - r.Foot else math.huge
	local now = os.clock()

	-- Take off / land
	if not r.Flying and held.Up then
		r.Flying = true
		r.Vy = C.TakeoffSpeed
		r.TakeoffUntil = now + 0.9
	elseif r.Flying and height < 1.2 and not held.Up and r.Vy <= 1 and now > r.TakeoffUntil then
		r.Flying = false -- touched down
		r.Vy = 0
	end

	-- Where the rider wants to go (camera-relative)
	local look = camera.CFrame.LookVector
	local rightDir = camera.CFrame.RightVector
	local wish = look * -move.Z + rightDir * move.X
	local wishFlat = Vector3.new(wish.X, 0, wish.Z)
	local amount = math.min(1, move.Magnitude)
	local speedMul = r.Model:GetAttribute("SpeedMul") or 1
	-- Breath attacks: turn to keep the target in front.
	local facing = r.FaceTarget ~= nil and now < r.FaceUntil and r.FaceTarget.Parent ~= nil
	if facing then
		local toTarget = (r.FaceTarget :: BasePart).Position - position
		toTarget = Vector3.new(toTarget.X, 0, toTarget.Z)
		if toTarget.Magnitude > 1 then
			wishFlat = toTarget.Unit
		end
	end

	-- Turn toward the wish at a natural rate (eased in and out)
	local turnLimit
	if r.Flying then
		local t = math.clamp(r.Speed / C.BoostSpeed, 0, 1)
		turnLimit = C.TurnRateSlow + (C.TurnRateFast - C.TurnRateSlow) * t
	else
		turnLimit = C.GroundTurnRate
	end
	local wantYawRate = 0
	if wishFlat.Magnitude > 0.05 then
		local target = wishFlat.Unit
		local angle = math.atan2(r.Heading:Cross(target).Y, r.Heading:Dot(target))
		local limit = if facing then turnLimit * 1.8 else turnLimit
		wantYawRate = math.clamp(angle * 2.5, -limit, limit)
	end
	r.YawRate = smooth(r.YawRate, wantYawRate, C.TurnEase, dt)
	r.Heading = (CFrame.Angles(0, r.YawRate * dt, 0) * r.Heading).Unit
	local alignment = if wishFlat.Magnitude > 0.05 then math.max(0, r.Heading:Dot(wishFlat.Unit)) else 0

	if r.Flying then
		-- Speed with momentum; diving adds speed, climbing costs it
		local cruise = (if held.Boost then C.BoostSpeed else C.CruiseSpeed) * speedMul
		local targetSpeed = cruise * amount * (0.35 + 0.65 * alignment) - r.Vy * C.DiveGain
		targetSpeed = math.clamp(targetSpeed, C.HoverSpeed, C.BoostSpeed * 1.15)
		r.Speed = approach(r.Speed, targetSpeed, C.AirAccel, C.AirDecel, dt)

		-- Vertical: follow the camera's pitch when moving, plus Climb/Dive
		-- The chase camera normally looks a little down at the dragon; treat that
		-- tilt as level flight, with a small dead zone, so W alone holds altitude.
		local camPitch = math.asin(math.clamp(look.Y, -1, 1)) - C.CameraNeutralPitch
		local dead = C.CameraPitchDeadzone
		local steerPitch = if math.abs(camPitch) <= dead then 0 else camPitch - math.sign(camPitch) * dead
		local wantVy = math.sin(math.clamp(steerPitch * 1.3, -1.2, 1.2)) * r.Speed * amount * math.max(0, -move.Z)
			+ ((if held.Up then 1 else 0) - (if held.Down then 1 else 0)) * C.ClimbSpeed * speedMul
		if now < r.TakeoffUntil then
			wantVy = math.max(wantVy, C.TakeoffSpeed * 0.7)
		end
		-- Ease the descent near the ground so it flares and lands softly
		if wantVy < 0 and height < 30 then
			local floorSpeed = -(height * (if held.Down then 1.2 else 0.6) + 2)
			wantVy = math.max(wantVy, floorSpeed)
		end
		r.Vy = smooth(r.Vy, wantVy, 2.2, dt)
		if height < 0.3 and r.Vy < 0 then
			r.Vy = 0
		end
		if height < 0 then
			-- skimming into rising ground (hills): lift out smoothly
			r.Vy = math.max(r.Vy, math.min(-height * 6, 40))
		end
	else
		-- Walking: turn first, then move; boost to run
		local walk = (if held.Boost then C.RunSpeed else C.GroundSpeed) * speedMul
		local targetSpeed = walk * amount * alignment ^ 1.5
		r.Speed = approach(r.Speed, targetSpeed, C.GroundAccel, C.GroundDecel, dt)
		local wantY = if ground then ground + r.Foot else position.Y
		r.Vy = math.clamp((wantY - position.Y) * 8, -60, 30)
	end

	r.Push *= math.exp(-3.5 * dt)
	local velocity = r.Heading * r.Speed + Vector3.new(0, r.Vy, 0) + r.Push
	local arenaCenter = r.Model:GetAttribute("ArenaCenter")
	if r.Model:GetAttribute("InBattle") and typeof(arenaCenter) == "Vector3" then
		-- Soft arena walls: slow down any movement that would leave the arena.
		local offset = position - arenaCenter
		local flat = Vector3.new(offset.X, 0, offset.Z)
		local limit = (r.Model:GetAttribute("ArenaRadius") or 230) - 14
		if flat.Magnitude > limit then
			local outward = flat.Unit
			local outSpeed = velocity:Dot(outward)
			if outSpeed > 0 then
				velocity -= outward * outSpeed * math.clamp((flat.Magnitude - limit) / 10, 0, 1)
			end
		end
		local ceiling = (r.Model:GetAttribute("ArenaCeiling") or 150) - 10
		local floor = (r.Model:GetAttribute("ArenaFloor") or -120) + 10
		if offset.Y > ceiling and velocity.Y > 0 then
			velocity = Vector3.new(velocity.X, velocity.Y * math.clamp(1 - (offset.Y - ceiling) / 8, 0, 1), velocity.Z)
			r.Vy = math.min(r.Vy, velocity.Y)
		elseif offset.Y < floor and velocity.Y < 0 then
			velocity = Vector3.new(velocity.X, velocity.Y * math.clamp(1 - (floor - offset.Y) / 8, 0, 1), velocity.Z)
			r.Vy = math.max(r.Vy, velocity.Y)
		end
	else
		-- Not fighting: keep out of the arenas so battles aren't blocked.
		local arenas = workspace:FindFirstChild("Arenas")
		if arenas then
			for _, arena in arenas:GetChildren() do
				local center = arena:GetAttribute("Center")
				if typeof(center) == "Vector3" then
					local offset = position - center
					local flat = Vector3.new(offset.X, 0, offset.Z)
					if flat.Magnitude < 250 and offset.Y > -140 and offset.Y < 170 and flat.Magnitude > 1 then
						velocity += flat.Unit * 45
					end
				end
			end
		end
	end
	-- Stay under the server's speed limit even with boosts and pushes.
	local maxSpeed = C.ServerMaxSpeed * 0.9
	if velocity.Magnitude > maxSpeed then
		velocity = velocity.Unit * maxSpeed
	end
	r.Velocity.VectorVelocity = velocity
	if r.Model:GetAttribute("DebugRide") ~= nil then
		r.Model:SetAttribute("DebugRide", string.format("fly=%s move=(%.2f,%.2f) wishFlat=%.2f align=%.2f yawRate=%.2f speed=%.1f h=%.1f", tostring(r.Flying), move.X, move.Z, wishFlat.Magnitude, alignment, r.YawRate, r.Speed, height))
	end

	-- Body attitude: pitch with climb/dive, bank into turns (both smoothed)
	local pitchTarget = 0
	if r.Flying then
		-- Fast: the nose follows the flight path. Slow: the body hangs upright under
		-- the flapping wings, and it flares nose-up just before touching down.
		local glide = math.clamp(r.Speed / (C.CruiseSpeed * 0.6), 0, 1)
		pitchTarget = math.atan2(r.Vy, math.max(r.Speed, 12)) * 0.8 * glide
		if r.Vy < 0 then
			pitchTarget += (1 - glide) * math.rad(8)
		end
		if height < 14 and r.Vy < -2 then
			pitchTarget += math.rad(14) * (1 - height / 14)
		end
		pitchTarget = math.clamp(pitchTarget, -C.MaxPitch, C.MaxPitch)
	end
	r.Pitch = smooth(r.Pitch, pitchTarget, 3, dt)
	local bankTarget = if r.Flying then math.clamp(r.YawRate * (0.25 + r.Speed / 90), -C.MaxBank, C.MaxBank) else r.YawRate * 0.06
	if now < r.RollUntil then
		bankTarget = -1.25 * r.RollDir -- evasive roll to the side of the dodge
	end
	r.Bank = smooth(r.Bank, bankTarget, if now < r.RollUntil then 9 else 2.5, dt)
	r.Align.CFrame = CFrame.lookAt(Vector3.zero, r.Heading) * CFrame.Angles(r.Pitch, 0, r.Bank)

	-- Camera: trail a smoothed point; widen the view with speed
	local focusTarget = position + Vector3.new(0, r.Foot * 1.6, 0)
	r.Focus.Position = r.Focus.Position:Lerp(focusTarget, 1 - math.exp(-C.CameraLag * dt))
	-- In flight the camera eases around behind the dragon (unless the rider is
	-- turning it by hand), so A/D give a continuous banking turn like a real mount.
	if r.Flying and r.Speed > 15 and now - lastCameraInput > C.CameraReturnDelay then
		local camFlat = Vector3.new(look.X, 0, look.Z)
		if camFlat.Magnitude > 0.1 then
			local off = math.atan2(camFlat.Unit:Cross(r.Heading).Y, camFlat.Unit:Dot(r.Heading))
			local follow = math.clamp(r.Speed / C.CruiseSpeed, 0.4, 1) * C.CameraFollowRate
			local turn = off * (1 - math.exp(-follow * dt))
			local pivot = r.Focus.Position
			camera.CFrame = CFrame.new(pivot) * CFrame.Angles(0, turn, 0) * CFrame.new(-pivot) * camera.CFrame
		end
	end
	local fovTarget = C.BaseFov + C.SpeedFov * math.clamp((r.Speed - C.CruiseSpeed * 0.6) / (C.BoostSpeed - C.CruiseSpeed * 0.6), 0, 1)
	camera.FieldOfView = smooth(camera.FieldOfView, fovTarget, 2, dt)
end

local function watchCharacter(character: Model)
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	humanoid.Seated:Connect(function(active, seat)
		if active and seat and seat.Name == "Saddle" then
			local model = seat.Parent
			if model and model:IsA("Model") and model:GetAttribute("OwnerId") == player.UserId then
				start(model, humanoid)
			end
		elseif not active then
			stop()
		end
	end)
end

function FlightController.start()
	if player.Character then
		task.spawn(watchCharacter, player.Character)
	end
	player.CharacterAdded:Connect(watchCharacter)
	player.CharacterRemoving:Connect(stop)
	RunService.RenderStepped:Connect(step)
	UserInputService.InputChanged:Connect(function(input, processed)
		local t = input.UserInputType
		if t == Enum.UserInputType.MouseMovement then
			if UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2) or UserInputService.MouseBehavior == Enum.MouseBehavior.LockCenter then
				lastCameraInput = os.clock()
			end
		elseif t == Enum.UserInputType.Touch and not processed then
			lastCameraInput = os.clock()
		elseif input.KeyCode == Enum.KeyCode.Thumbstick2 and input.Position.Magnitude > 0.25 then
			lastCameraInput = os.clock()
		end
	end)
end

function FlightController.IsRiding(): boolean
	return ride ~= nil
end

function FlightController.GetModel(): Model?
	return ride and ride.Model
end

-- Quick sideways burst and roll. dir: -1 left, 1 right (default: the way you steer).
function FlightController.Dodge(dir: number?)
	local r = ride
	if not r then
		return
	end
	local side = dir or (if UserInputService:IsKeyDown(Enum.KeyCode.A) then -1 elseif UserInputService:IsKeyDown(Enum.KeyCode.D) then 1 else (if math.random() < 0.5 then -1 else 1))
	local right = r.Heading:Cross(Vector3.yAxis)
	r.Push += right * side * 75 + Vector3.new(0, 6, 0)
	r.RollUntil = os.clock() + 0.45
	r.RollDir = side
end

-- Strike skills: lunge at the target.
function FlightController.Lunge(target: BasePart?)
	local r = ride
	if not r or not target then
		return
	end
	local toward = target.Position - r.Root.Position
	if toward.Magnitude > 1 then
		r.Push += toward.Unit * math.min(95, toward.Magnitude * 2)
	end
end

function FlightController.Knockback(push: Vector3)
	if ride and typeof(push) == "Vector3" and push.Magnitude < 200 then
		ride.Push += push
	end
end

-- Keep turning toward `target` for a few seconds (breath attacks).
function FlightController.FaceTarget(target: BasePart?, seconds: number)
	if ride then
		ride.FaceTarget = target
		ride.FaceUntil = os.clock() + seconds
	end
end

return FlightController
