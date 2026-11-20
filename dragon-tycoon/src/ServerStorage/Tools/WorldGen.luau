-- ServerStorage/Tools/WorldGen
-- Edit-time tool (not used by the running game) that writes the Dragon Tycoon
-- landscape into Terrain:
--   * a flat meadow valley in the middle (hub castle + the 8 plots, r < ~420)
--   * rolling forested hills around it
--   * a ring of rocky, snow-capped mountains at the edge (the world boundary)
--   * lakes in the hills, three fed by waterfalls off cliffs
-- Heights are in studs; ground level in the valley is y = 0.

local WorldGen = {}

WorldGen.HalfSize = 1400 -- world spans -1400..1400 on X and Z
WorldGen.Seed = 7.31

-- Lakes: center, radius, water surface height, depth below surface
WorldGen.Lakes = {
	{ Name = "North", X = 0, Z = -760, R = 175, Water = 6, Depth = 30 },
	{ Name = "East", X = 770, Z = 250, R = 130, Water = 22, Depth = 24 },
	{ Name = "West", X = -720, Z = -380, R = 115, Water = 14, Depth = 22 },
	{ Name = "South", X = -160, Z = 790, R = 160, Water = 8, Depth = 26, Island = true },
}

-- Waterfalls: a plateau with a stream that pours over a cliff into a lake.
-- (X, Z) = where the water leaves the cliff edge; Dir = direction it falls toward.
WorldGen.Falls = {
	{ Name = "GreatFalls", X = 0, Z = -945, DirX = 0, DirZ = 1, Width = 44, Top = 230, Lake = "North" },
	{ Name = "EastFalls", X = 905, Z = 250, DirX = -1, DirZ = 0, Width = 26, Top = 120, Lake = "East" },
	{ Name = "WestFalls", X = -840, Z = -380, DirX = 1, DirZ = 0, Width = 22, Top = 150, Lake = "West" },
}

local function smoothstep(a: number, b: number, x: number): number
	local t = math.clamp((x - a) / (b - a), 0, 1)
	return t * t * (3 - 2 * t)
end

local function fbm(x: number, z: number, octaves: number, freq: number, seed: number): number
	local total, amp, norm = 0, 1, 0
	for _ = 1, octaves do
		total += math.noise(x * freq, z * freq, seed) * amp
		norm += amp
		amp *= 0.5
		freq *= 2.03
	end
	return total / norm -- about -0.5..0.5
end

-- Sharp mountain ridges: 1 - |noise|, squared.
local function ridged(x: number, z: number, octaves: number, freq: number, seed: number): number
	local total, amp, norm = 0, 1, 0
	for _ = 1, octaves do
		local n = 1 - math.abs(math.noise(x * freq, z * freq, seed) * 2)
		total += n * n * amp
		norm += amp
		amp *= 0.5
		freq *= 2.1
	end
	return total / norm -- 0..1
end

local function lakeByName(name: string)
	for _, lake in WorldGen.Lakes do
		if lake.Name == name then
			return lake
		end
	end
	return nil
end

-- Ground height and which lake (if any) covers this point.
function WorldGen.Height(x: number, z: number): (number, any)
	local seed = WorldGen.Seed
	local r = math.sqrt(x * x + z * z)

	-- Valley: flat at the hub, the faintest roll between plots. Sits 2.4 studs
	-- low because smooth terrain draws its surface ~2 studs above the voxel
	-- edge; this keeps grass under the cobblestone plaza and paths (y ~0.35).
	local valley = -2.4 + (if r < 140 then 0 else 1.2 * fbm(x, z, 2, 1 / 90, seed))
	-- Hills: rolling, 15..95 studs.
	local hills = 50 + 90 * fbm(x, z, 4, 1 / 330, seed + 10)
	-- Mountains: ridged peaks.
	local mountains = 140 + 330 * ridged(x, z, 5, 1 / 420, seed + 20)

	local valleyMask = 1 - smoothstep(400, 560, r)
	local mountainMask = smoothstep(840, 1080, r + 60 * fbm(x, z, 2, 1 / 300, seed + 30))
	local h = hills + (valley - hills) * valleyMask
	h = h + (mountains - h) * mountainMask

	-- Lakes: carve basins.
	local inLake = nil
	for _, lake in WorldGen.Lakes do
		local d = math.sqrt((x - lake.X) ^ 2 + (z - lake.Z) ^ 2)
		local wobble = lake.R * (1 + 0.18 * fbm(x, z, 2, 1 / 80, seed + 50))
		if d < wobble * 1.5 then
			local floor = lake.Water - lake.Depth * (1 - smoothstep(0, wobble, d)) - 2
			local shore = lake.Water + 3
			local t = smoothstep(wobble * 0.85, wobble * 1.45, d)
			local target = if d < wobble then floor else shore
			h = target + (h - target) * t
			if d < wobble and h < lake.Water then
				inLake = lake
			end
			if lake.Island and d < wobble * 0.22 then
				h = math.max(h, lake.Water + 10 * (1 - d / (wobble * 0.22)) + 2)
				inLake = nil
			end
		end
	end

	-- Waterfall plateaus: stamped after the lakes so the cliff edge stays sheer.
	for _, f in WorldGen.Falls do
		local dx, dz = x - f.X, z - f.Z
		local along = dx * f.DirX + dz * f.DirZ -- + = toward the lake
		local across = math.abs(dx * -f.DirZ + dz * f.DirX)
		if across < f.Width * 4 and along <= 0 and along > -300 then
			local widthFade = 1 - smoothstep(f.Width * 2, f.Width * 4, across)
			local plateau = f.Top + 25 * fbm(x, z, 2, 1 / 60, seed + 40) * (1 - smoothstep(-40, 0, along))
			local stamped = h + (plateau - h) * widthFade
			if stamped > h then
				h = stamped
				inLake = nil
			end
		end
	end

	-- Stream channels across the plateaus that feed each waterfall.
	for _, f in WorldGen.Falls do
		local dx, dz = x - f.X, z - f.Z
		local along = dx * f.DirX + dz * f.DirZ
		local across = math.abs(dx * -f.DirZ + dz * f.DirX)
		if along <= 0 and along > -240 and across < f.Width * 0.5 then
			h = math.min(h, f.Top - 6)
		end
	end
	return h, inLake
end

-- Surface material for a column, given height and slope (rise per stud).
function WorldGen.Material(x: number, z: number, h: number, slope: number, lake: any): Enum.Material
	local seed = WorldGen.Seed
	if lake then
		return if h > lake.Water - 4 then Enum.Material.Sand else Enum.Material.Mud
	end
	for _, l in WorldGen.Lakes do
		local d = math.sqrt((x - l.X) ^ 2 + (z - l.Z) ^ 2)
		if d < l.R * 1.2 and h < l.Water + 4 then
			return Enum.Material.Sand
		end
	end
	local patch = fbm(x, z, 2, 1 / 40, seed + 60)
	if h > 320 + 30 * patch then
		return if slope > 1.1 then Enum.Material.Rock else Enum.Material.Snow
	end
	if slope > 1.0 then
		return if h > 160 then Enum.Material.Slate else Enum.Material.Rock
	end
	if slope > 0.55 then
		return if patch > 0.1 then Enum.Material.Rock else Enum.Material.Ground
	end
	if h > 230 then
		return Enum.Material.Rock
	end
	if patch > 0.22 then
		return Enum.Material.Ground
	end
	return if patch < -0.15 then Enum.Material.LeafyGrass else Enum.Material.Grass
end

-- Writes one square chunk of terrain. x0, z0 = min corner (multiples of 4).
function WorldGen.BuildChunk(x0: number, z0: number, size: number)
	local terrain = workspace.Terrain
	local res = 4
	local n = size // res
	-- Column heights (one extra ring for slope)
	local heights, lakes = {}, {}
	local minH, maxH = math.huge, -math.huge
	for i = 0, n + 1 do
		heights[i], lakes[i] = {}, {}
		for k = 0, n + 1 do
			local x = x0 + (i - 0.5) * res
			local z = z0 + (k - 0.5) * res
			local h, lake = WorldGen.Height(x, z)
			heights[i][k] = h
			lakes[i][k] = lake
			if i >= 1 and i <= n and k >= 1 and k <= n then
				minH = math.min(minH, h)
				local top = if lake then math.max(h, lake.Water) else h
				maxH = math.max(maxH, top)
			end
		end
	end
	local y0 = math.floor((minH - 16) / res) * res
	local y1 = math.ceil((maxH + 4) / res) * res
	local ny = (y1 - y0) // res

	local materials, occupancy = {}, {}
	for i = 1, n do
		local matX, occX = {}, {}
		materials[i], occupancy[i] = matX, occX
		for j = 1, ny do
			matX[j], occX[j] = {}, {}
		end
		for k = 1, n do
			local h = heights[i][k]
			local lake = lakes[i][k]
			local sx = (heights[i + 1][k] - heights[i - 1][k]) / (2 * res)
			local sz = (heights[i][k + 1] - heights[i][k - 1]) / (2 * res)
			local slope = math.sqrt(sx * sx + sz * sz)
			local x = x0 + (i - 0.5) * res
			local z = z0 + (k - 0.5) * res
			local surface = WorldGen.Material(x, z, h, slope, lake)
			for j = 1, ny do
				local bottom = y0 + (j - 1) * res
				local fill = math.clamp((h - bottom) / res, 0, 1)
				local mat, occ
				if fill > 0 then
					mat = if h - bottom <= 10 then surface elseif h - bottom <= 24 and surface ~= Enum.Material.Snow then Enum.Material.Ground else Enum.Material.Rock
					occ = fill
				elseif lake and bottom < lake.Water then
					mat, occ = Enum.Material.Water, 1
				else
					mat, occ = Enum.Material.Air, 0
				end
				matX[j][k] = mat
				occX[j][k] = occ
			end
		end
	end
	local region = Region3.new(Vector3.new(x0, y0, z0), Vector3.new(x0 + size, y1, z0 + size)):ExpandToGrid(res)
	terrain:WriteVoxels(region, res, materials, occupancy)
end

-- Water sheets for the waterfalls (terrain water, falling down the cliff face).
function WorldGen.BuildFalls()
	local terrain = workspace.Terrain
	for _, f in WorldGen.Falls do
		local lake = lakeByName(f.Lake)
		local dir = Vector3.new(f.DirX, 0, f.DirZ)
		local right = Vector3.new(-f.DirZ, 0, f.DirX)
		-- the stream on the plateau
		local streamStart = Vector3.new(f.X, 0, f.Z) - dir * 230
		for step = 0, 230, 8 do
			local p = streamStart + dir * step
			terrain:FillBlock(CFrame.lookAt(Vector3.new(p.X, f.Top - 4, p.Z), Vector3.new(p.X, f.Top - 4, p.Z) + dir), Vector3.new(f.Width * 0.45, 4, 10), Enum.Material.Water)
		end
		-- the falling sheet, from the lip down to the lake
		local fallTop = f.Top - 2
		local fallBottom = lake.Water - 2
		local height = fallTop - fallBottom
		local center = Vector3.new(f.X, (fallTop + fallBottom) / 2, f.Z) + dir * 6
		terrain:FillBlock(CFrame.lookAt(center, center + dir), Vector3.new(f.Width * 0.45, height, 6), Enum.Material.Water)
		_ = right
	end
end

return WorldGen
