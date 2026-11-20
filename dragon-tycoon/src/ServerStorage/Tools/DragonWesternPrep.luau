-- ServerStorage/Tools/DragonWesternPrep
-- Edit-time helper that turns an AI-generated, segmented western dragon into the
-- 14 named pieces DragonRigBuilder.BuildWestern expects. Used once per species.
--
--   1. generate_mesh with parts torso, neck, head, tail, left wing, right wing,
--      front legs, hind legs (a level, four-legged pose)
--   2. Prep.Normalize(model, slot)      flatten, face -Z, check the stance
--   3. segment_mesh: front legs -> 2, hind legs -> 2, tail -> 3, a wing -> 2
--   4. Prep.Assemble(model, options)    name pieces, wing rest pose from the real
--                                       mesh, mirror the good wing, neck, joint pins
--   5. DragonRigBuilder.BuildWestern, then Prep.Install
-- Joint frame: -Z forward, +Y up, +X is the dragon's right.

local AssetService = game:GetService("AssetService")

local Prep = {}

local function cleanName(name: string): string
	return (name:gsub("_geom$", ""):gsub("[^%a ]", ""))
end

local function along(part: BasePart, dir: Vector3): number
	local cf, size = part.CFrame, part.Size / 2
	return math.abs(cf.RightVector:Dot(dir)) * size.X + math.abs(cf.UpVector:Dot(dir)) * size.Y + math.abs(cf.LookVector:Dot(dir)) * size.Z
end

local function rotateAbout(part: BasePart, pivot: Vector3, rot: CFrame)
	part.CFrame = CFrame.new(pivot) * rot * CFrame.new(pivot):ToObjectSpace(part.CFrame)
end

local function meshParts(model: Instance): { MeshPart }
	local list = {}
	for _, d in model:GetDescendants() do
		if d:IsA("MeshPart") then
			table.insert(list, d)
		end
	end
	return list
end

-- World-space vertices of a MeshPart (every `step`-th vertex).
local function worldVertices(part: MeshPart, step: number?): { Vector3 }
	local em = AssetService:CreateEditableMeshAsync(Content.fromUri(part.MeshId))
	local scale = part.Size / part.MeshSize
	local out = {}
	local i = 0
	for _, v in em:GetVertices() do
		i += 1
		if i % (step or 1) == 0 then
			table.insert(out, part.CFrame:PointToWorldSpace(em:GetPosition(v) * scale))
		end
	end
	em:Destroy()
	return out
end

-- Eigen-decomposition of a symmetric 3x3 matrix (Jacobi). Returns values and
-- the matching unit vectors.
local function eigen3(a: { { number } }): ({ number }, { Vector3 })
	local v = { { 1, 0, 0 }, { 0, 1, 0 }, { 0, 0, 1 } }
	for _ = 1, 40 do
		if a[1][2] ^ 2 + a[1][3] ^ 2 + a[2][3] ^ 2 < 1e-14 then
			break
		end
		for p = 1, 2 do
			for q = p + 1, 3 do
				if math.abs(a[p][q]) > 1e-14 then
					local theta = (a[q][q] - a[p][p]) / (2 * a[p][q])
					local t = (if theta >= 0 then 1 else -1) / (math.abs(theta) + math.sqrt(theta * theta + 1))
					local c = 1 / math.sqrt(t * t + 1)
					local s = t * c
					for k = 1, 3 do
						local akp, akq = a[k][p], a[k][q]
						a[k][p], a[k][q] = c * akp - s * akq, s * akp + c * akq
					end
					for k = 1, 3 do
						local apk, aqk = a[p][k], a[q][k]
						a[p][k], a[q][k] = c * apk - s * aqk, s * apk + c * aqk
					end
					for k = 1, 3 do
						local vkp, vkq = v[k][p], v[k][q]
						v[k][p], v[k][q] = c * vkp - s * vkq, s * vkp + c * vkq
					end
				end
			end
		end
	end
	local vecs = {}
	for i = 1, 3 do
		vecs[i] = Vector3.new(v[1][i], v[2][i], v[3][i]).Unit
	end
	return { a[1][1], a[2][2], a[3][3] }, vecs
end

-- Flattens the generated model, turns it to face -Z and moves it to `slot`.
-- Returns ok plus a one-line stance report.
function Prep.Normalize(model: Model, slot: Vector3): (boolean, string)
	local parts = {}
	for _, p in meshParts(model) do
		p.Name = cleanName(p.Name)
		parts[p.Name] = p
		p.Parent = model
		p.Anchored = true
	end
	for _, d in model:GetChildren() do
		if d:IsA("Model") and #d:GetDescendants() == 0 then
			d:Destroy()
		end
	end
	local head, torso = parts.head, parts.torso
	if not (head and torso) then
		return false, "missing head or torso"
	end
	local fwd = (head.Position - torso.Position) * Vector3.new(1, 0, 1)
	if fwd.Magnitude < 1e-3 then
		return false, "head straight above the torso (rearing)"
	end
	local center = model:GetBoundingBox().Position
	local rot = CFrame.fromRotationBetweenVectors(fwd.Unit, Vector3.new(0, 0, -1))
	for _, p in parts do
		p.CFrame = CFrame.new(slot) * rot * CFrame.new(center):ToObjectSpace(p.CFrame)
	end
	return Prep.CheckStance(model)
end

-- A rideable pose: level body, front legs ahead of the hind legs, tail behind.
function Prep.CheckStance(model: Model): (boolean, string)
	local function get(n)
		return model:FindFirstChild(n)
	end
	local torso, head, tail = get("torso"), get("head"), get("tail")
	local fl, hl = get("front legs"), get("hind legs")
	if not (torso and head and fl and hl) then
		return false, "missing parts"
	end
	local len = along(torso, Vector3.zAxis) * 2
	local hgt = along(torso, Vector3.yAxis) * 2
	local legGap = hl.Position.Z - fl.Position.Z
	local headUp = head.Position.Y - torso.Position.Y
	local tailBack = if tail then tail.Position.Z - torso.Position.Z else 0
	local ok = legGap > 0.22 * len and len > 1.3 * hgt and headUp < 1.0 * hgt and tailBack > 0
	return ok, string.format("torso %.1fx%.1f, leg gap %.2f of body, head up %.1f, tail back %.1f",
		len, hgt, legGap / len, headUp, tailBack)
end

-- Picks the wing side whose split runs across the span (shoulder piece near the
-- body, tip piece far out). Returns side (+1 right / -1 left), inner, tip.
local function pickWing(wings: { MeshPart }, center: Vector3, prefer: number?)
	local bySide = { [1] = {}, [-1] = {} }
	for _, w in wings do
		local side = if w.Position.X - center.X >= 0 then 1 else -1
		table.insert(bySide[side], w)
	end
	local best, bestScore
	for _, side in { prefer or 1, -(prefer or 1) } do
		local list = bySide[side]
		if #list == 2 then
			table.sort(list, function(a, b)
				return math.abs(a.Position.X - center.X) < math.abs(b.Position.X - center.X)
			end)
			local inner, tip = list[1], list[2]
			-- how far out each piece reaches, relative to the whole wing
			local ri = math.abs(inner.Position.X - center.X)
			local rt = math.abs(tip.Position.X - center.X)
			local score = (rt - ri) / math.max(rt, 1e-3)
			if score > 0.2 and (not bestScore or score > bestScore + 0.15) then
				best, bestScore = { side, inner, tip }, score
			end
		end
	end
	if best then
		return best[1], best[2], best[3], bestScore
	end
	return nil
end

-- options: { WingSide = 1|-1 (prefer), FlipLeading = bool, WingScale = number?,
--            NeckRaise = degrees?, MaxNeckStretch = number? }
function Prep.Assemble(model: Model, options: { [string]: any }?): string
	options = options or {}
	local report = {}
	local all = meshParts(model)
	local named: { [string]: MeshPart } = {}
	local legs, tails, wings = {}, {}, {}
	for _, p in all do
		local n = cleanName(p.Name)
		p.Anchored = true
		if n == "torso" then
			named.Body = p
		elseif n == "neck" then
			named.Neck = p
		elseif n == "head" then
			named.Head = p
		elseif n:find("leg") then
			table.insert(legs, p)
		elseif n:find("tail") then
			table.insert(tails, p)
		elseif n:find("wing") then
			table.insert(wings, p)
		end
	end
	local body = assert(named.Body, "no torso")
	local c = body.Position
	local bodyLen = along(body, Vector3.zAxis) * 2
	local halfW, halfH = along(body, Vector3.xAxis), along(body, Vector3.yAxis)

	-- Legs: the two nearest the head are the front pair; left is -X.
	assert(#legs == 4, "need 4 leg pieces, got " .. #legs)
	table.sort(legs, function(a, b)
		return a.Position.Z < b.Position.Z
	end)
	for i, leg in legs do
		local front = i <= 2
		local left = leg.Position.X < c.X
		named[(if front then "Front" else "Hind") .. (if left then "Left" else "Right") .. "Leg"] = leg
	end
	for _, n in { "FrontLeftLeg", "FrontRightLeg", "HindLeftLeg", "HindRightLeg" } do
		assert(named[n], "legs did not split left/right: missing " .. n)
	end

	-- Tail: nearest the body first.
	table.sort(tails, function(a, b)
		return a.Position.Z < b.Position.Z
	end)
	for i, t in tails do
		if i <= 3 then
			named["Tail" .. i] = t
		end
	end
	table.insert(report, #tails .. " tail pieces")

	-- Wings: use one well-split wing and mirror it.
	local side, inner, tip, score = pickWing(wings, c, options.WingSide)
	assert(side, "no wing split across its span; segment a wing into shoulder half + wingtip half")
	table.insert(report, string.format("wing side %d (split score %.2f)", side, score))
	for _, w in wings do
		if w ~= inner and w ~= tip then
			w:Destroy()
		end
	end

	-- Shoulder root: where the wing meets the back.
	local verts = {}
	for _, p in { inner, tip } do
		for _, v in worldVertices(p, 2) do
			table.insert(verts, v)
		end
	end
	table.sort(verts, function(a, b)
		return math.abs(a.X - c.X) < math.abs(b.X - c.X)
	end)
	local root = Vector3.zero
	local nRoot = math.max(1, math.floor(#verts * 0.05))
	for i = 1, nRoot do
		root += verts[i]
	end
	root /= nRoot
	root = Vector3.new(c.X + side * halfW * 0.35, math.clamp(root.Y, c.Y + 0.2 * halfH, c.Y + 0.95 * halfH), root.Z)

	-- Wing plane from the vertices: the normal is the direction of least spread.
	local centroid = Vector3.zero
	for _, v in verts do
		centroid += v
	end
	centroid /= #verts
	local cov = { { 0, 0, 0 }, { 0, 0, 0 }, { 0, 0, 0 } }
	for _, v in verts do
		local d = v - centroid
		local comps = { d.X, d.Y, d.Z }
		for i = 1, 3 do
			for j = 1, 3 do
				cov[i][j] += comps[i] * comps[j]
			end
		end
	end
	local vals, vecs = eigen3(cov)
	local minI = 1
	for i = 2, 3 do
		if vals[i] < vals[minI] then
			minI = i
		end
	end
	local normal = vecs[minI]
	local span = centroid - root
	span = (span - normal * span:Dot(normal)).Unit
	local chord = normal:Cross(span).Unit
	-- Leading edge: the thicker half of the wing (the arm bone), across the chord.
	local thick = { [1] = { 0, 0, 0 }, [-1] = { 0, 0, 0 } } -- n, sum, sumsq of normal offsets
	for _, v in verts do
		local d = v - centroid
		local half = if d:Dot(chord) >= 0 then 1 else -1
		local w = d:Dot(normal)
		local t = thick[half]
		t[1] += 1
		t[2] += w
		t[3] += w * w
	end
	local function spread(t)
		if t[1] < 2 then
			return 0
		end
		local mean = t[2] / t[1]
		return math.sqrt(math.max(0, t[3] / t[1] - mean * mean))
	end
	local lead = if spread(thick[1]) >= spread(thick[-1]) then chord else -chord
	if options.FlipLeading then
		lead = -lead
	end
	table.insert(report, string.format("wing thickness lead %.2f vs %.2f", spread(thick[1]), spread(thick[-1])))
	-- Rest pose: span straight out to the side, leading edge forward, membrane behind.
	local src = CFrame.fromMatrix(Vector3.zero, span, lead, span:Cross(lead))
	local tSpan, tLead = Vector3.new(side, 0, 0), Vector3.new(0, 0, -1)
	local dst = CFrame.fromMatrix(Vector3.zero, tSpan, tLead, tSpan:Cross(tLead))
	local q = dst * src:Inverse()
	rotateAbout(inner, root, q)
	rotateAbout(tip, root, q)

	-- Wingspan: each wing about 0.7 of the nose-to-tail length.
	local nose = (named.Head and named.Head.Position.Z - along(named.Head, Vector3.zAxis)) or (c.Z - bodyLen / 2)
	local tailEnd = c.Z + bodyLen / 2
	for _, t in tails do
		tailEnd = math.max(tailEnd, t.Position.Z + along(t, Vector3.zAxis))
	end
	local length = tailEnd - nose
	local reach = math.abs(tip.Position.X - root.X) + along(tip, Vector3.xAxis)
	local k = options.WingScale or math.clamp(0.7 * length / reach, 1, 1.8)
	for _, p in { inner, tip } do
		local off = p.Position - root
		p.Size *= k
		p.CFrame = (p.CFrame - p.Position) + root + off * k
	end
	table.insert(report, string.format("wing scale %.2f", k))

	-- Joint pins: shoulder, and the elbow where the shoulder piece ends.
	local function pin(part: BasePart, world: Vector3)
		local old = part:FindFirstChild("JointPin")
		if old then
			old:Destroy()
		end
		local a = Instance.new("Attachment")
		a.Name = "JointPin"
		a.Parent = part
		a.WorldPosition = world
	end
	local dir = (tip.Position - root).Unit
	local elbow = root + dir * ((inner.Position - root):Dot(dir) + along(inner, dir) * 0.6)
	pin(inner, root)
	pin(tip, elbow)

	-- Mirror to the other side: half a turn about the forward axis through the root height.
	local sideName = if side == 1 then "Right" else "Left"
	local otherName = if side == 1 then "Left" else "Right"
	inner.Name = sideName .. "Wing"
	tip.Name = sideName .. "WingTip"
	named[sideName .. "Wing"], named[sideName .. "WingTip"] = inner, tip
	local flip = CFrame.fromAxisAngle(Vector3.zAxis, math.pi)
	local mirrorPivot = Vector3.new(c.X, root.Y, root.Z)
	for _, pair in { { inner, "Wing" }, { tip, "WingTip" } } do
		local cl = pair[1]:Clone()
		cl.Name = otherName .. pair[2]
		cl.Parent = model
		rotateAbout(cl, mirrorPivot, flip)
		named[cl.Name] = cl
	end

	-- Neck: lengthen a short neck and lift it so the head rides high.
	local neck, head = named.Neck, named.Head
	if neck and head then
		local neckLen = along(neck, Vector3.zAxis) * 2
		local stretch = math.clamp(0.6 * bodyLen / neckLen, 1, options.MaxNeckStretch or 1.9)
		local aligned = math.abs(neck.CFrame.LookVector:Dot(Vector3.zAxis)) > 0.95
		if stretch > 1.05 and aligned then
			local added = neckLen * (stretch - 1)
			neck.Size = Vector3.new(neck.Size.X, neck.Size.Y, neck.Size.Z * stretch)
			neck.CFrame -= Vector3.new(0, 0, added / 2)
			head.CFrame -= Vector3.new(0, 0, added)
			table.insert(report, string.format("neck x%.2f", stretch))
		end
		local base = Vector3.new(c.X, neck.Position.Y - along(neck, Vector3.yAxis) * 0.2, neck.Position.Z + along(neck, Vector3.zAxis) * 0.7)
		local junction = Vector3.new(c.X, head.Position.Y - along(head, Vector3.yAxis) * 0.25, head.Position.Z + along(head, Vector3.zAxis) * 0.6)
		pin(neck, base)
		pin(head, junction)
		local raise = math.rad(options.NeckRaise or (if head.Position.Y < c.Y + halfH then 20 else 8))
		local lift = CFrame.fromAxisAngle(Vector3.xAxis, raise)
		rotateAbout(neck, base, lift)
		rotateAbout(head, base, lift * CFrame.fromAxisAngle(Vector3.xAxis, -raise * 0.6))
		table.insert(report, string.format("neck raised %.0f deg", math.deg(raise)))
	end

	-- Final names; anything unused goes.
	for name, p in named do
		p.Name = name
		p.Parent = model
	end
	for _, p in meshParts(model) do
		if not named[p.Name] or named[p.Name] ~= p then
			p:Destroy()
		end
	end
	for _, d in model:GetChildren() do
		if d:IsA("Model") then
			d:Destroy()
		end
	end
	model.PrimaryPart = body
	return table.concat(report, "; ")
end

-- Materials, then swap the template in ReplicatedStorage/DragonModels; the old
-- one is kept in ServerStorage/DragonModelArchive.
function Prep.Install(rig: Model, speciesId: string, element: string): Model
	for _, p in rig:GetChildren() do
		if p:IsA("MeshPart") then
			if p.Name:find("Wing") then
				p.Material = Enum.Material.Leather
				p.MaterialVariant = "DragonWingLeather"
			else
				p.Material = Enum.Material.Slate
				p.MaterialVariant = "DragonScales"
			end
		end
	end
	for _, d in rig:GetDescendants() do
		if d:IsA("Attachment") and d.Name == "JointPin" then
			d:Destroy()
		end
	end
	local models = game:GetService("ReplicatedStorage").DragonModels
	local ServerStorage = game:GetService("ServerStorage")
	local archive = ServerStorage:FindFirstChild("DragonModelArchive")
	if not archive then
		archive = Instance.new("Folder")
		archive.Name = "DragonModelArchive"
		archive.Parent = ServerStorage
	end
	local old = models:FindFirstChild(speciesId)
	if old then
		if old:GetAttribute("Rig") ~= "Western" and not archive:FindFirstChild(speciesId .. "_Classic") then
			old.Name = speciesId .. "_Classic"
			old.Parent = archive
		else
			old:Destroy()
		end
	end
	local t = rig:Clone()
	t.Name = speciesId
	t:SetAttribute("Species", speciesId)
	t:SetAttribute("Element", element)
	t.Parent = models
	return t
end

return Prep
