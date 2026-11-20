-- ReplicatedStorage/Client/Preview
-- 3D previews of dragons and eggs inside UI (ViewportFrames).
--   Preview.Dragon(parent, speciesId, props?) -> ViewportFrame
--   Preview.Egg(parent, eggId, props?) -> ViewportFrame
--   Preview.SetRoll(vp, angle) / Preview.SetPose(vp, pitch, yaw, roll, lift, zoom)
-- Previews slowly turn while visible. Particle effects don't show in
-- viewports, so these are the bare models.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Preview = {}

type ViewState = {
	Camera: Camera,
	Center: Vector3,
	Distance: number,
	Height: number,
	Angle: number,
	Speed: number,
	Zoom: number,
}

local states: { [ViewportFrame]: ViewState } = {}

local function setupViewport(parent: Instance, props: { [string]: any }?): ViewportFrame
	local vp = Instance.new("ViewportFrame")
	vp.Size = UDim2.fromScale(1, 1)
	vp.BackgroundTransparency = 1
	vp.Ambient = Color3.fromRGB(210, 200, 196)
	vp.LightColor = Color3.fromRGB(255, 244, 218)
	vp.LightDirection = Vector3.new(-0.55, -0.8, -0.6)
	for key, value in props or {} do
		(vp :: any)[key] = value
	end
	vp.Parent = parent
	return vp
end

local function updateCamera(state: ViewState)
	local dist = state.Distance * state.Zoom
	local offset = Vector3.new(math.sin(state.Angle), 0, math.cos(state.Angle)) * dist + Vector3.new(0, state.Height * state.Zoom, 0)
	state.Camera.CFrame = CFrame.lookAt(state.Center + offset, state.Center)
end

local function frame(vp: ViewportFrame, model: Model, look: Vector3, spin: number, closeness: number)
	local camera = Instance.new("Camera")
	camera.FieldOfView = 35
	camera.Parent = vp
	vp.CurrentCamera = camera
	model.Parent = vp
	local cf, size = model:GetBoundingBox()
	local radius = size.Magnitude / 2
	local distance = radius / math.tan(math.rad(camera.FieldOfView / 2)) * closeness
	local angle = math.atan2(look.X, look.Z) + math.rad(35)
	local state: ViewState = {
		Camera = camera,
		Center = cf.Position,
		Distance = distance,
		Height = distance * 0.25,
		Angle = angle,
		Speed = spin,
		Zoom = 1,
	}
	updateCamera(state)
	states[vp] = state
	vp.Destroying:Connect(function()
		states[vp] = nil
	end)
end

local function strip(model: Model)
	for _, d in model:GetDescendants() do
		if d:IsA("ParticleEmitter") or d:IsA("Light") or d:IsA("Script") or d:IsA("LocalScript") then
			d:Destroy()
		end
	end
end

-- spin: radians per second (0 = still). closeness < 1 zooms in.
function Preview.Dragon(parent: Instance, speciesId: string, props: { [string]: any }?, spin: number?, closeness: number?): ViewportFrame?
	local folder = ReplicatedStorage:FindFirstChild("DragonModels")
	local template = folder and folder:FindFirstChild(speciesId)
	if not template then
		return nil
	end
	local vp = setupViewport(parent, props)
	local model = template:Clone() :: Model
	strip(model)
	local look = (model.PrimaryPart :: BasePart).CFrame.LookVector
	frame(vp, model, look, spin or 0.35, closeness or 0.85)
	return vp
end

function Preview.Egg(parent: Instance, eggId: string, props: { [string]: any }?, spin: number?, closeness: number?): ViewportFrame?
	local folder = ReplicatedStorage:FindFirstChild("EggModels")
	local template = folder and folder:FindFirstChild(eggId)
	if not template then
		return nil
	end
	local vp = setupViewport(parent, props)
	local model = template:Clone() :: Model
	strip(model)
	frame(vp, model, Vector3.new(0, 0, 1), spin or 0.5, closeness or 0.8)
	return vp
end

-- Drives 3D wobble, hop, and camera zoom pulse during egg hatching.
function Preview.SetPose(vp: ViewportFrame, pitch: number, yaw: number, roll: number, lift: number?, zoom: number?)
	local model = vp:FindFirstChildWhichIsA("Model")
	if model and model.PrimaryPart then
		local base = model:GetAttribute("BasePivot") :: CFrame?
		if not base then
			base = model:GetPivot()
			model:SetAttribute("BasePivot", base)
		end
		model:PivotTo((base :: CFrame) * CFrame.new(0, lift or 0, 0) * CFrame.Angles(pitch, yaw, roll))
	end
	local state = states[vp]
	if state and zoom then
		state.Zoom = zoom
		updateCamera(state)
	end
end

-- Tilts an egg preview (for backwards compatibility). angle in radians.
function Preview.SetRoll(vp: ViewportFrame, angle: number)
	Preview.SetPose(vp, 0, 0, angle, 0)
end

RunService.RenderStepped:Connect(function(dt)
	for vp, state in states do
		if state.Speed ~= 0 and vp.Visible and vp.Parent then
			state.Angle += state.Speed * dt
			updateCamera(state)
		end
	end
end)

return Preview
