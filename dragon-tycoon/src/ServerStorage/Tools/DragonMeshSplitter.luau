-- ServerStorage/Tools/DragonMeshSplitter
-- Edit-time fallback for when the AI segment_mesh tool is unavailable. Cuts a
-- MeshPart into pieces by position, keeping its UVs (so the texture still fits)
-- and normals. Triangles that cross a cut go into both pieces, so neighbouring
-- pieces overlap a little and bending hides the cut.
--
--   Splitter.Legs(part, bodyCenter, "front")   -> left / right leg
--   Splitter.Tail(part, bodyCenter, pieces)    -> tail pieces, base first
--   Splitter.Wing(part, bodyCenter, cut)       -> shoulder piece + wingtip piece
--
-- The new MeshParts are built from EditableMeshes: they work in Studio straight
-- away, but they are only kept in a saved place once their meshes are uploaded
-- (see Splitter.Adopt). Dragons face -Z after DragonWesternPrep.Normalize.

local AssetService = game:GetService("AssetService")

local Splitter = {}

local function load(part: MeshPart)
	local src = AssetService:CreateEditableMeshAsync(Content.fromUri(part.MeshId))
	local scale = part.Size / part.MeshSize
	local function world(p: Vector3): Vector3
		return part.CFrame:PointToWorldSpace(p * scale)
	end
	return src, scale, world
end

-- groupOf(worldPos) -> group index. Builds one MeshPart per group.
local function cut(part: MeshPart, groupOf: (Vector3) -> number, names: { string }): { MeshPart }
	local src, scale, world = load(part)
	local faces: { { number } } = {}
	for g = 1, #names do
		faces[g] = {}
	end
	local groupCache = {}
	local function vgroup(v): number
		local g = groupCache[v]
		if not g then
			g = groupOf(world(src:GetPosition(v)))
			groupCache[v] = g
		end
		return g
	end
	for _, f in src:GetFaces() do
		local seen = {}
		for _, v in src:GetFaceVertices(f) do
			local g = vgroup(v)
			if not seen[g] then
				seen[g] = true
				table.insert(faces[g], f)
			end
		end
	end
	local out = {}
	for g, list in faces do
		if #list > 0 then
			local mn, mx = Vector3.one * math.huge, -Vector3.one * math.huge
			for _, f in list do
				for _, v in src:GetFaceVertices(f) do
					local p = src:GetPosition(v)
					mn, mx = mn:Min(p), mx:Max(p)
				end
			end
			local center = (mn + mx) / 2
			local em = AssetService:CreateEditableMesh()
			local vmap, uvmap, nmap = {}, {}, {}
			for _, f in list do
				local nv = {}
				for i, v in src:GetFaceVertices(f) do
					if not vmap[v] then
						vmap[v] = em:AddVertex(src:GetPosition(v) - center)
					end
					nv[i] = vmap[v]
				end
				local face = em:AddTriangle(nv[1], nv[2], nv[3])
				local uvs = src:GetFaceUVs(f)
				if uvs and #uvs == 3 then
					local nu = {}
					for i, u in uvs do
						if not uvmap[u] then
							uvmap[u] = em:AddUV(src:GetUV(u))
						end
						nu[i] = uvmap[u]
					end
					em:SetFaceUVs(face, nu)
				end
				local ns = src:GetFaceNormals(f)
				if ns and #ns == 3 then
					local nn = {}
					for i, n in ns do
						if not nmap[n] then
							nmap[n] = em:AddNormal(src:GetNormal(n))
						end
						nn[i] = nmap[n]
					end
					em:SetFaceNormals(face, nn)
				end
			end
			local piece = AssetService:CreateMeshPartAsync(Content.fromObject(em))
			piece.Name = names[g]
			piece.TextureID = part.TextureID
			piece.Material = part.Material
			piece.MaterialVariant = part.MaterialVariant
			piece.Color = part.Color
			piece.Size = piece.MeshSize * scale
			piece.CFrame = part.CFrame * CFrame.new(center * scale)
			piece.Anchored = true
			piece.CanCollide = false
			piece.Parent = part.Parent
			piece:SetAttribute("SplitFrom", part.Name)
			table.insert(out, piece)
		end
	end
	src:Destroy()
	return out
end

local function worldVerts(part: MeshPart): { Vector3 }
	local src, _, world = load(part)
	local list = {}
	for _, v in src:GetVertices() do
		table.insert(list, world(src:GetPosition(v)))
	end
	src:Destroy()
	return list
end

-- A pair of legs: left (-X) and right (+X) of the body's centre line.
function Splitter.Legs(part: MeshPart, bodyCenter: Vector3, which: string): { MeshPart }
	return cut(part, function(p)
		return if p.X < bodyCenter.X then 1 else 2
	end, { "left " .. which .. " leg", "right " .. which .. " leg" })
end

-- A tail: equal lengths along its run away from the body (base first).
function Splitter.Tail(part: MeshPart, bodyCenter: Vector3, pieces: number?): { MeshPart }
	local n = pieces or 3
	local verts = worldVerts(part)
	local lo, hi = math.huge, -math.huge
	-- distance from the body along the ground plane follows a straight or curling tail
	local function run(p: Vector3): number
		return Vector2.new(p.X - bodyCenter.X, p.Z - bodyCenter.Z).Magnitude
	end
	for _, p in verts do
		local d = run(p)
		lo, hi = math.min(lo, d), math.max(hi, d)
	end
	local names = {}
	for i = 1, n do
		names[i] = "tail piece " .. i
	end
	return cut(part, function(p)
		return math.clamp(math.floor((run(p) - lo) / (hi - lo + 1e-6) * n) + 1, 1, n)
	end, names)
end

-- A wing: shoulder piece and wingtip piece, cut at `cutAt` (0..1) of the
-- distance from the wing root (where it meets the body) to its farthest point.
function Splitter.Wing(part: MeshPart, bodyCenter: Vector3, cutAt: number?): { MeshPart }
	local verts = worldVerts(part)
	table.sort(verts, function(a, b)
		return math.abs(a.X - bodyCenter.X) < math.abs(b.X - bodyCenter.X)
	end)
	local root = Vector3.zero
	local k = math.max(1, math.floor(#verts * 0.05))
	for i = 1, k do
		root += verts[i]
	end
	root /= k
	local far = 0
	for _, p in verts do
		far = math.max(far, (p - root).Magnitude)
	end
	local limit = far * (cutAt or 0.45)
	return cut(part, function(p)
		return if (p - root).Magnitude < limit then 1 else 2
	end, { "wing shoulder half", "wingtip half of wing" })
end

-- Swaps split pieces for uploaded copies of the same meshes, so the place keeps
-- them when saved. Upload route (Studio's own importer does the upload):
--   1. File > Export as glTF (Studio exports the whole place)
--   2. extract the pieces into a small GLB (extract_pieces.py in the repo's scripts/)
--   3. File > Import that GLB: Studio uploads each mesh to the creator's account
--   4. Splitter.Adopt(model, importedModel)
-- A glTF round trip through Studio turns meshes half a turn about Y (X and Z
-- flip), which ROUND_TRIP undoes. Pieces are matched by name; a mirrored wing
-- (a clone sharing its pair's mesh) reuses the same upload. When several dragons
-- share one import, their pieces are named "<prefix>__<piece>"; pass the prefix.
local ROUND_TRIP = CFrame.Angles(0, math.pi, 0)

function Splitter.Adopt(model: Model, imported: Instance, prefix: string?): { string }
	local uploads: { [string]: MeshPart } = {}
	local lead = if prefix then prefix .. "__" else ""
	for _, d in imported:GetDescendants() do
		if d:IsA("MeshPart") and d.Name:sub(1, #lead) == lead then
			uploads[d.Name:sub(#lead + 1)] = d
		end
	end
	-- which in-memory mesh each upload stands for
	local byObject = {}
	for name, up in uploads do
		local mine = model:FindFirstChild(name)
		if mine and mine:IsA("MeshPart") and mine.MeshContent.SourceType == Enum.ContentSourceType.Object then
			byObject[mine.MeshContent.Object] = up
		end
	end
	local report = {}
	for _, old in model:GetChildren() do
		if old:IsA("MeshPart") and old.MeshContent.SourceType == Enum.ContentSourceType.Object then
			local up = byObject[old.MeshContent.Object]
			if not up then
				table.insert(report, "no upload for " .. old.Name)
				continue
			end
			local new = up:Clone()
			new.Name = old.Name
			new.Size = old.Size
			new.CFrame = old.CFrame * ROUND_TRIP
			new.TextureID = old.TextureID
			new.Material = old.Material
			new.MaterialVariant = old.MaterialVariant
			new.Color = old.Color
			new.Transparency = old.Transparency
			new.Anchored = old.Anchored
			new.CanCollide = old.CanCollide
			new.CanQuery = old.CanQuery
			new.CanTouch = old.CanTouch
			new.Massless = old.Massless
			for _, child in new:GetChildren() do
				child:Destroy()
			end
			for _, child in old:GetChildren() do
				if child:IsA("Attachment") then
					child.CFrame = ROUND_TRIP:Inverse() * child.CFrame
				end
				child.Parent = new
			end
			for k, v in old:GetAttributes() do
				new:SetAttribute(k, v)
			end
			new:SetAttribute("SplitFrom", nil)
			new.Parent = old.Parent
			old:Destroy()
			table.insert(report, new.Name .. " <- " .. tostring(new.MeshId))
		end
	end
	return report
end

return Splitter
