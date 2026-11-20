-- ServerStorage/Modules/MountService
-- Summon one of your dragons at full size, ride it, fly it.
--
-- The rider's device steers the dragon (it gets network ownership, so flight
-- is smooth), and the server checks every half second that the dragon stays
-- under the speed limit, below the altitude cap and inside the world. A
-- dragon that breaks the rules is pulled back to its last good position.
--
-- Battles summon with SummonAt(..., { Locked = true }): a locked mount can't be
-- dismissed or left, and only Release() removes it. Removed fires whenever a
-- mount goes away, so CombatService can end a fight if a dragon disappears.

local Players = game:GetService("Players")
local PhysicsService = game:GetService("PhysicsService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared

local DragonCatalog = require(Shared.DragonCatalog)
local FlightConfig = require(Shared.FlightConfig)
local DataService = require(script.Parent.DataService)
local DragonVisuals = require(script.Parent.DragonVisuals)

local MountService = {}

type Mount = {
	Model: Model,
	Root: BasePart,
	Seat: Seat,
	DragonId: string,
	LastGood: CFrame,
	Strikes: number,
	EmptySince: number?,
	Locked: boolean,
}

local mounts: { [Player]: Mount } = {}

local removed = Instance.new("BindableEvent")
-- Fires (player, model) after a player's mount is removed for any reason.
MountService.Removed = removed.Event

local RIDER_GROUP = "Riders"

-- While mounted, the rider's body passes through the world (the dragon does the
-- colliding), so walls and roofs never snag or jerk the ride.
local function setRiderCollisions(character: Model?, riding: boolean)
	if not character then
		return
	end
	for _, part in character:GetDescendants() do
		if part:IsA("BasePart") then
			part.CollisionGroup = if riding then RIDER_GROUP else "Default"
		end
	end
end
local mountFolder: Folder

local function fail(code: string)
	return { ok = false, error = code }
end

local function despawn(player: Player)
	local mount = mounts[player]
	mounts[player] = nil
	if mount then
		local humanoid = mount.Seat.Occupant
		if humanoid then
			humanoid.Sit = false
		end
		setRiderCollisions(player.Character, false)
		mount.Model:Destroy()
		removed:Fire(player, mount.Model)
	end
end

-- Finds flat ground in front of the player for the dragon to land on.
local function spawnCFrame(character: Model, footOffset: number, length: number): CFrame
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart
	local look = root.CFrame.LookVector * Vector3.new(1, 0, 1)
	look = if look.Magnitude > 0.01 then look.Unit else Vector3.new(0, 0, -1)
	local spot = root.Position + look * (length * 0.6)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character, mountFolder }
	params.RespectCanCollide = true -- land on solid ground, not invisible markers
	local hit = workspace:Raycast(spot + Vector3.new(0, 60, 0), Vector3.new(0, -200, 0), params)
	local groundY = if hit then hit.Position.Y else root.Position.Y - 3
	local position = Vector3.new(spot.X, groundY + footOffset, spot.Z)
	return CFrame.lookAt(position, position + look)
end

export type SummonOptions = {
	CFrame: CFrame?, -- where to put the dragon (default: in front of the player)
	Locked: boolean?, -- battle mount: can't be dismissed or left
}

local function summon(player: Player, dragonId: string, options: SummonOptions?)
	local current = mounts[player]
	if current and current.Locked then
		return fail("in_battle")
	end
	local data = DataService.GetData(player)
	if not data then
		return fail("not_loaded")
	end
	local dragon = data.Dragons[dragonId]
	if not dragon then
		return fail("not_found")
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 or not character:FindFirstChild("HumanoidRootPart") then
		return fail("no_character")
	end

	despawn(player)
	local model = DragonVisuals.Build(dragon, "Ride")
	if not model then
		return fail("no_model")
	end
	local root = model.PrimaryPart :: BasePart
	local foot = model:GetAttribute("FootOffset") or 6
	if data.Cosmetics then
		DragonVisuals.ApplyCosmetics(model, data.Cosmetics.Trail, data.Cosmetics.Aura)
	end
	local place = options and options.CFrame or spawnCFrame(character, foot, model:GetAttribute("Length") or 36)
	model:PivotTo(place)
	model.Name = player.Name .. "_Mount"
	local locked = options ~= nil and options.Locked == true
	if locked then
		model:SetAttribute("Locked", true)
	end
	model:SetAttribute("OwnerId", player.UserId)
	model:SetAttribute("DragonId", dragonId)

	-- Saddle
	local saddleAttachment = root:FindFirstChild("SaddleAttachment") :: Attachment
	local seat = Instance.new("Seat")
	seat.Name = "Saddle"
	seat.Size = Vector3.new(3, 1, 3)
	seat.Transparency = 1
	seat.CanCollide = false
	seat.CanQuery = false
	seat.Massless = true
	seat.CFrame = saddleAttachment.WorldCFrame
	seat.Parent = model
	-- Welded to the animated Body (not the Root), so the rider rises and falls
	-- with every wingbeat, breath and step.
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = model:FindFirstChild("Body") :: BasePart? or root
	weld.Part1 = seat
	weld.Parent = seat

	-- Movers the rider's device drives
	local rootAttachment = root:FindFirstChild("RootAttachment") :: Attachment
	local velocity = Instance.new("LinearVelocity")
	velocity.Name = "FlightVelocity"
	velocity.Attachment0 = rootAttachment
	velocity.RelativeTo = Enum.ActuatorRelativeTo.World
	velocity.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	velocity.MaxForce = math.huge
	velocity.VectorVelocity = Vector3.zero
	velocity.Parent = root
	local align = Instance.new("AlignOrientation")
	align.Name = "FlightOrientation"
	align.Mode = Enum.OrientationAlignmentMode.OneAttachment
	align.Attachment0 = rootAttachment
	align.MaxTorque = math.huge
	align.Responsiveness = 9 -- smooth, weighty turns
	align.MaxAngularVelocity = 3
	align.CFrame = root.CFrame.Rotation
	align.Parent = root

	-- The dragon, not the rider, must be the assembly root, or sitting down
	-- would drag the dragon to the rider instead of lifting the rider up.
	root.RootPriority = 127
	root.Anchored = false
	CollectionService:AddTag(model, "AnimatedDragon")
	model.Parent = mountFolder
	root:SetNetworkOwner(player)

	local mount: Mount = {
		Model = model,
		Root = root,
		Seat = seat,
		DragonId = dragonId,
		LastGood = root.CFrame,
		Strikes = 0,
		EmptySince = nil,
		Locked = locked,
	}
	mounts[player] = mount

	seat:GetPropertyChangedSignal("Occupant"):Connect(function()
		local occupant = seat.Occupant
		if occupant and occupant.Parent ~= player.Character then
			occupant.Sit = false -- only the owner rides their dragon
			return
		end
		mount.EmptySince = if occupant then nil else os.clock()
		setRiderCollisions(player.Character, occupant ~= nil)
		if not occupant and mount.Locked then
			-- Battle mounts can't be left: put the rider straight back in the saddle.
			task.delay(0.2, function()
				if mounts[player] == mount and mount.Locked and humanoid.Parent and humanoid.Health > 0 then
					seat:Sit(humanoid)
				end
			end)
		end
	end)
	task.delay(0.3, function()
		if mounts[player] == mount and humanoid.Parent then
			seat:Sit(humanoid)
		end
	end)
	local species = DragonCatalog.Get(dragon.Species)
	return { ok = true, name = (species and species.Name or dragon.Species), model = model }
end

-- Called from the client (through RemoteService): summon in front of the player.
function MountService.Summon(player: Player, dragonId: string)
	local result = summon(player, dragonId, nil)
	result.model = nil -- the client finds its mount in Workspace.Mounts
	return result
end

-- Server only: summon at a given spot, optionally locked for a battle.
function MountService.SummonAt(player: Player, dragonId: string, options: SummonOptions)
	return summon(player, dragonId, options)
end

function MountService.Dismiss(player: Player)
	local mount = mounts[player]
	if mount and mount.Locked then
		return fail("in_battle")
	end
	despawn(player)
	return { ok = true }
end

-- Server only: removes the mount even if it is locked (end of a battle).
function MountService.Release(player: Player)
	despawn(player)
end

function MountService.GetMountedDragonId(player: Player): string?
	local mount = mounts[player]
	return mount and mount.DragonId
end

function MountService.GetMount(player: Player): (Model?, BasePart?)
	local mount = mounts[player]
	if mount and mount.Model.Parent then
		return mount.Model, mount.Root
	end
	return nil, nil
end

-- Every half second: enforce limits and clear empty mounts.
local function watch()
	local now = os.clock()
	for player, mount in mounts do
		if not mount.Model.Parent then
			mounts[player] = nil
			continue
		end
		if not mount.Locked and mount.EmptySince and now - mount.EmptySince > FlightConfig.DespawnAfterDismount then
			despawn(player)
			continue
		end
		local root = mount.Root
		local position = root.Position
		local speed = root.AssemblyLinearVelocity.Magnitude
		local moved = (position - mount.LastGood.Position).Magnitude
		local flat = Vector3.new(position.X, 0, position.Z).Magnitude
		local reason = if speed > FlightConfig.ServerMaxSpeed then "speed"
			elseif moved > FlightConfig.ServerMaxSpeed * 0.5 * 1.5 then "teleport" -- further than possible in 0.5s
			elseif position.Y > FlightConfig.MaxAltitude then "altitude"
			elseif flat > FlightConfig.WorldRadius then "bounds"
			elseif position.Y < -50 then "underground"
			else nil
		if reason then
			mount.Strikes += 1
			warn("[MountService] Limit broken by", player.Name, reason, "speed", math.floor(speed), "moved", math.floor(moved), "pos", position)
			-- Take control back, put the dragon at its last good spot, hand it back.
			root:SetNetworkOwner(nil)
			root.AssemblyLinearVelocity = Vector3.zero
			mount.Model:PivotTo(mount.LastGood)
			local velocity = root:FindFirstChild("FlightVelocity") :: LinearVelocity?
			if velocity then
				velocity.VectorVelocity = Vector3.zero
			end
			if mount.Strikes >= 5 then
				despawn(player)
			else
				task.delay(1, function()
					if mounts[player] == mount and root.Parent then
						root:SetNetworkOwner(player)
					end
				end)
			end
		else
			mount.LastGood = root.CFrame
			mount.Strikes = math.max(0, mount.Strikes - 0.1)
		end
	end
end

function MountService.init()
	pcall(function()
		PhysicsService:RegisterCollisionGroup(RIDER_GROUP)
	end)
	PhysicsService:CollisionGroupSetCollidable(RIDER_GROUP, "Default", false)
	PhysicsService:CollisionGroupSetCollidable(RIDER_GROUP, RIDER_GROUP, false)
	mountFolder = workspace:FindFirstChild("Mounts") or Instance.new("Folder")
	mountFolder.Name = "Mounts"
	mountFolder.Parent = workspace
	Players.PlayerRemoving:Connect(despawn)
	Players.PlayerAdded:Connect(function(player)
		player.CharacterRemoving:Connect(function()
			despawn(player)
		end)
	end)
	for _, player in Players:GetPlayers() do
		player.CharacterRemoving:Connect(function()
			despawn(player)
		end)
	end
	task.spawn(function()
		while true do
			task.wait(0.5)
			local ok, err = pcall(watch)
			if not ok then
				warn("[MountService] watch failed:", err)
			end
		end
	end)
end

return MountService
