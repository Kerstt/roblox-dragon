-- ServerStorage/Tools/WorldDress
-- Edit-time tool: dresses the grey-box world as a medieval realm using the
-- AI-made models in ServerStorage/WorldAssets.
--   DressPlots()   stone courtyards + real station buildings on all 8 plots
--   DressHub()     cobblestone plaza and paths, stone and timber details
--   PlaceLandmarks() castle on the north hill, villages, windmill, watchtowers
--   PlantForests() oaks and pines on the hills and mountain slopes, boulders

local ServerStorage = game:GetService("ServerStorage")

local WorldDress = {}

local ASSETS = ServerStorage:WaitForChild("WorldAssets")
local STATION_ASSET = { Forge = "Forge", Mine = "MineEntrance", Farm = "FarmBarn", Watchtower = "Watchtower" }

local STONE = Color3.fromRGB(118, 112, 102)
local DARK_STONE = Color3.fromRGB(92, 88, 82)
local WOOD = Color3.fromRGB(92, 66, 44)

local function sceneryFolder(name: string): Folder
	local root = workspace:FindFirstChild("Scenery") or Instance.new("Folder")
	root.Name = "Scenery"
	root.Parent = workspace
	local folder = root:FindFirstChild(name) or Instance.new("Folder")
	folder.Name = name
	folder.Parent = root
	return folder :: Folder
end

local function setLook(part: BasePart, material: Enum.Material, color: Color3)
	part.Material = material
	part.Color = color
end

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Include
rayParams.FilterDescendantsInstances = { workspace.Terrain }

-- Terrain surface under (x, z): position, material, normal.
local function ground(x: number, z: number)
	local hit = workspace:Raycast(Vector3.new(x, 900, z), Vector3.new(0, -1100, 0), rayParams)
	if hit then
		return hit.Position, hit.Material, hit.Normal
	end
	return nil
end

-- Clones an asset, scales it, faces it along `facing`, and sets its base on `baseY`.
local function place(assetName: string, position: Vector3, facing: Vector3, scale: number, parent: Instance, baseY: number?): Model
	local model = ASSETS[assetName]:Clone() :: Model
	model:ScaleTo(model:GetScale() * scale)
	local flat = Vector3.new(facing.X, 0, facing.Z)
	flat = if flat.Magnitude > 0.01 then flat.Unit else Vector3.new(0, 0, -1)
	model:PivotTo(CFrame.lookAt(position, position + flat))
	local cf, size = model:GetBoundingBox()
	local bottom = cf.Position.Y - size.Y / 2
	local y = baseY or position.Y
	model:PivotTo(model:GetPivot() + Vector3.new(position.X - cf.Position.X, y - bottom, position.Z - cf.Position.Z))
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CastShadow = true
		end
	end
	model.Parent = parent
	return model
end

-- Plots ---------------------------------------------------------------------------

function WorldDress.DressPlots()
	local report = {}
	for _, plot in workspace.Plots:GetChildren() do
		local base = plot:FindFirstChild("Base") :: BasePart?
		if base then
			setLook(base, Enum.Material.Cobblestone, Color3.fromRGB(128, 122, 112))
		end
		local terrain = plot:FindFirstChild("Terrain")
		if terrain then
			for _, part in terrain:GetDescendants() do
				if part:IsA("BasePart") then
					local n = part.Name
					if n:find("Cliff") or n:find("Outcrop") then
						setLook(part, Enum.Material.Rock, Color3.fromRGB(104, 98, 90))
					elseif n:find("Path") or n:find("Ramp") then
						setLook(part, Enum.Material.Cobblestone, DARK_STONE)
					elseif n:find("Lintel") then
						setLook(part, Enum.Material.Wood, WOOD)
					else
						setLook(part, Enum.Material.Cobblestone, STONE)
					end
				end
			end
		end
		local sign = plot:FindFirstChild("OwnerSign")
		if sign and sign:IsA("BasePart") then
			setLook(sign, Enum.Material.Wood, Color3.fromRGB(150, 118, 82))
		end
		local nest = plot:FindFirstChild("Nest")
		if nest then
			for _, part in nest:GetDescendants() do
				if part:IsA("BasePart") and part.Transparency < 1 then
					setLook(part, Enum.Material.Rock, Color3.fromRGB(110, 100, 88))
				end
			end
		end

		for _, station in plot.Stations:GetChildren() do
			local built = station:FindFirstChild("Built") :: Model?
			local assetName = STATION_ASSET[station.Name]
			if built and assetName and not built:GetAttribute("Dressed") then
				local cf, size = built:GetBoundingBox()
				local slots = Vector3.zero
				for i = 1, 3 do
					slots += (station :: any)["Slot" .. i].Position
				end
				slots /= 3
				local toward = ((slots - cf.Position) * Vector3.new(1, 0, 1)).Unit
				local halfDepth = math.abs(toward.X) * size.X / 2 + math.abs(toward.Z) * size.Z / 2
				local frontEdge = cf.Position + toward * halfDepth
				local groundY = cf.Position.Y - size.Y / 2
				local _, assetSize = ASSETS[assetName]:GetBoundingBox()
				local scale
				if station.Name == "Watchtower" then
					scale = 72 / assetSize.Y
				else
					local width = math.max(size.X, size.Z) * 1.1
					scale = math.min(width / math.max(assetSize.X, assetSize.Z), 30 / math.min(assetSize.X, assetSize.Z))
				end
				-- grey-box parts go; the real building takes their place
				built:ClearAllChildren()
				local depth = math.min(assetSize.X, assetSize.Z) * scale
				local center = frontEdge - toward * (depth / 2 + 1)
				local building = place(assetName, Vector3.new(center.X, groundY, center.Z), toward, scale, built, groundY)
				for _, d in building:GetDescendants() do
					if d:IsA("BasePart") then
						d:SetAttribute("BaseTransparency", d.Transparency)
						d:SetAttribute("BaseCanCollide", true)
						d.CanCollide = true
					end
				end
				built:SetAttribute("Dressed", true)
			end
			local scaffold = station:FindFirstChild("Scaffold")
			if scaffold then
				for _, part in scaffold:GetDescendants() do
					if part:IsA("BasePart") then
						part.Material = Enum.Material.Wood
						part.Color = Color3.fromRGB(120, 92, 62)
					end
				end
			end
			local markings = station:FindFirstChild("Markings")
			if markings then
				for _, part in markings:GetDescendants() do
					if part:IsA("BasePart") then
						part.Material = Enum.Material.Slate
						part.Color = Color3.fromRGB(80, 78, 74)
					end
				end
			end
		end
		table.insert(report, plot.Name)
		task.wait()
	end
	return "dressed " .. table.concat(report, ", ")
end

-- Hub -----------------------------------------------------------------------------

function WorldDress.DressHub()
	local count = 0
	for _, part in workspace.Hub:GetDescendants() do
		if part:IsA("BasePart") and part.Transparency < 1 and not part:IsDescendantOf(workspace.Hub:FindFirstChild("EggShowcase") or part) and not part:IsA("SpawnLocation") then
			local n = part.Name:lower()
			if n:find("lamp") or n:find("light") or n:find("bulb") then
				if part.Material ~= Enum.Material.Neon then
					setLook(part, Enum.Material.Metal, Color3.fromRGB(45, 42, 40))
				end
			elseif n:find("post") or n:find("board") or n:find("leader") or n:find("sign") then
				setLook(part, Enum.Material.Wood, WOOD)
			elseif n:find("path") or n:find("plaza") or n:find("road") then
				setLook(part, Enum.Material.Cobblestone, if n:find("ring") then DARK_STONE else Color3.fromRGB(132, 126, 116))
			elseif n:find("portal") then
				setLook(part, Enum.Material.Slate, Color3.fromRGB(70, 66, 74))
			elseif part.Material ~= Enum.Material.Neon then
				setLook(part, Enum.Material.Cobblestone, STONE)
			end
			count += 1
		end
	end
	local spawn = workspace.Hub:FindFirstChild("HubSpawn")
	if spawn and spawn:IsA("BasePart") then
		setLook(spawn, Enum.Material.Slate, DARK_STONE)
	end
	return "hub parts restyled: " .. count
end

-- Landmarks -------------------------------------------------------------------------

function WorldDress.PlaceLandmarks()
	local folder = sceneryFolder("Landmarks")
	folder:ClearAllChildren()
	local report = {}

	-- The castle on the north hill, overlooking the valley, facing the hub
	local castleSpot = Vector3.new(0, 0, -480)
	local g = ground(castleSpot.X, castleSpot.Z)
	if g then
		local baseY = g.Y
		-- a rock mound so no corner floats over the slope
		workspace.Terrain:FillBlock(CFrame.new(castleSpot.X, baseY - 20, castleSpot.Z), Vector3.new(150, 40, 140), Enum.Material.Rock)
		local castle = place("CastleKeep", Vector3.new(castleSpot.X, baseY, castleSpot.Z), -castleSpot, 2.2, folder, baseY - 1)
		castle.Name = "Castle"
		table.insert(report, string.format("castle at y %.0f", baseY))
	end

	-- Villages: little clusters between the plots, just outside the plot ring
	local rng = Random.new(1066)
	local houses = 0
	for k = 0, 7 do
		local angle = math.rad(22.5 + 45 * k)
		for h = 1, 3 do
			local radius = 365 + (h - 1) * 30 + rng:NextNumber(-6, 6)
			local a = angle + rng:NextNumber(-0.11, 0.11) + (h - 2) * 0.07
			local x, z = math.sin(a) * radius, math.cos(a) * radius
			local pos = ground(x, z)
			if pos then
				local kind = if (k + h) % 2 == 0 then "TimberHouse" else "StoneCottage"
				local scale = if kind == "TimberHouse" then 1.5 else 1.3
				local facing = (Vector3.new(-x, 0, -z)).Unit + Vector3.new(rng:NextNumber(-0.3, 0.3), 0, rng:NextNumber(-0.3, 0.3))
				local house = place(kind, pos, facing, scale, folder, pos.Y - 0.5)
				house.Name = kind .. houses
				houses += 1
			end
		end
		task.wait()
	end
	table.insert(report, houses .. " village houses")

	-- Windmill on the east hill
	local wm = ground(560, -240)
	if wm then
		place("Windmill", wm, Vector3.new(-1, 0, 0.3), 1.7, folder, wm.Y - 1).Name = "Windmill"
		table.insert(report, "windmill")
	end

	-- Watchtowers on three hills
	for i, spot in { Vector3.new(-560, 0, 220), Vector3.new(520, 0, 540), Vector3.new(330, 0, -580) } do
		local p = ground(spot.X, spot.Z)
		if p then
			place("Watchtower", p, -spot, 1.25, folder, p.Y - 1).Name = "HillTower" .. i
		end
	end
	table.insert(report, "3 hill watchtowers")
	return table.concat(report, ", ")
end

-- Forests -----------------------------------------------------------------------------

-- seed, grid step (studs), append (keep existing trees), minDensity (-1..1: higher = only the thickest woods)
function WorldDress.PlantForests(seed: number?, step: number?, append: boolean?, minDensity: number?)
	local folder = sceneryFolder("Trees")
	if not append then
		folder:ClearAllChildren()
	end
	local rng = Random.new(seed or 4242)
	local half = 1360
	local oaks, pines, rocks = 0, 0, 0
	step = step or 70
	local threshold = minDensity or -0.15
	local okMaterials = { [Enum.Material.Grass] = true, [Enum.Material.LeafyGrass] = true, [Enum.Material.Ground] = true }
	for gx = -half, half, step do
		for gz = -half, half, step do
			local x = gx + rng:NextNumber(-step * 0.45, step * 0.45)
			local z = gz + rng:NextNumber(-step * 0.45, step * 0.45)
			local r = math.sqrt(x * x + z * z)
			-- keep the valley, plots, castle and village open
			local nearCastle = math.abs(x) < 110 and math.abs(z + 480) < 110
			if r > 455 and not nearCastle then
				local pos, material, normal = ground(x, z)
				if pos and okMaterials[material] and normal.Y > 0.86 then
					-- forests clump: skip some spots with low-frequency noise
					local density = math.noise(x / 260, z / 260, 3.3)
					if density > threshold then
						local pine = pos.Y > 110 or (pos.Y > 50 and rng:NextNumber() < 0.5)
						local kind = if pine then "PineTree" else "OakTree"
						local scale = if pine then rng:NextNumber(1.1, 1.9) else rng:NextNumber(0.9, 1.5)
						local facing = Vector3.new(rng:NextNumber(-1, 1), 0, rng:NextNumber(-1, 1))
						local tree = place(kind, pos, facing, scale, folder, pos.Y - 1.5)
						for _, d in tree:GetDescendants() do
							if d:IsA("BasePart") then
								d.CanCollide = false
								d.CanQuery = false
								d.CanTouch = false
							end
						end
						if pine then pines += 1 else oaks += 1 end
					end
				elseif pos and (material == Enum.Material.Rock or material == Enum.Material.Ground) and rng:NextNumber() < 0.25 then
					workspace.Terrain:FillBall(pos, rng:NextNumber(3, 9), Enum.Material.Rock)
					rocks += 1
				end
			end
		end
		task.wait()
	end
	return string.format("%d oaks, %d pines, %d boulders", oaks, pines, rocks)
end

return WorldDress
