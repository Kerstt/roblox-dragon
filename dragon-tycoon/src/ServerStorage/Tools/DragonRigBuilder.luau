-- ServerStorage/Tools/DragonRigBuilder
-- Edit-time tool (not used by the running game). Turns an AI-generated,
-- segmented, textured dragon model into a ride-ready template:
--   Model (PrimaryPart = Root, invisible, faces the dragon's head)
--     Body, Head, LeftWing, RightWing, Tail  (MeshParts, unanchored, massless)
--     Root/Motor6D per part with the joint at the hip, neck base, tail base and
--       shoulders, so DragonAnimation can flap wings, sway the tail, etc.
--     Root attachments: RootAttachment, SaddleAttachment, MouthAttachment, AuraAttachment
--   Attributes: FootOffset (Root height above the feet), Species, Element, Rig

local DragonRigBuilder = {}

-- Required parts; LeftLeg/RightLeg are optional (newer models have them).
local KEYWORDS = {
	{ Name = "LeftWing" },
	{ Name = "RightWing" },
	{ Name = "Head" },
	{ Name = "Tail" },
	{ Name = "Body" },
}

local function classify(name: string): string?
	local lower = name:lower()
	local left = lower:find("left", 1, true) ~= nil
	local right = lower:find("right", 1, true) ~= nil
	if lower:find("leg", 1, true) then
		return if left then "LeftLeg" elseif right then "RightLeg" else nil
	end
	if lower:find("wing", 1, true) or lower:find("fin", 1, true) or left or right then
		return if left then "LeftWing" elseif right then "RightWing" else nil
	end
	if lower:find("head", 1, true) or lower:find("neck", 1, true) then
		return "Head"
	end
	if lower:find("tail", 1, true) then
		return "Tail"
	end
	if lower:find("body", 1, true) or lower:find("torso", 1, true) then
		return "Body"
	end
	return nil
end

local function along(part: BasePart, dir: Vector3): number
	-- half extent of the part's bounding box along a world direction
	local cf, size = part.CFrame, part.Size / 2
	return math.abs(cf.RightVector:Dot(dir)) * size.X + math.abs(cf.UpVector:Dot(dir)) * size.Y + math.abs(cf.LookVector:Dot(dir)) * size.Z
end

-- source: a Model containing MeshParts whose names mention body/head/left/right/tail.
-- options: { Name, Species, Element, Rig, Length? (nose-to-tail studs; nil = keep size) }
function DragonRigBuilder.Build(source: Model, options: { [string]: any }): Model
	local src = source:Clone()
	src.Parent = workspace
	local found: { [string]: BasePart } = {}
	for _, d in src:GetDescendants() do
		if d:IsA("MeshPart") then
			local role = classify(d.Name)
			if role and not found[role] then
				found[role] = d
			end
		end
	end
	for _, entry in KEYWORDS do
		assert(found[entry.Name], "DragonRigBuilder: no part for " .. entry.Name)
	end
	-- Drop any rig the generator added; we build our own.
	for _, d in src:GetDescendants() do
		if d:IsA("JointInstance") or d:IsA("AnimationController") or d:IsA("Folder") then
			d:Destroy()
		end
	end

	if options.Length then
		local _, size = src:GetBoundingBox()
		local current = math.max(size.X, size.Z)
		src:ScaleTo(src:GetScale() * options.Length / current)
	end

	local body, head, tail = found.Body, found.Head, found.Tail
	local forward = ((head.Position - body.Position) * Vector3.new(1, 0, 1)).Unit
	local cf, size = src:GetBoundingBox()
	local bottomY = cf.Position.Y - size.Y / 2
	local center = body.Position
	local rootCF = CFrame.lookAt(center, center + forward)
	local right = rootCF.RightVector

	local leftWing, rightWing = found.LeftWing, found.RightWing
	if (leftWing.Position - center):Dot(right) > 0 then
		leftWing, rightWing = rightWing, leftWing -- generator's left/right was mirrored
	end

	local model = Instance.new("Model")
	model.Name = options.Name or source.Name
	local root = Instance.new("Part")
	root.Name = "Root"
	root.Size = Vector3.new(4, 4, 6)
	root.CFrame = rootCF
	root.Transparency = 1
	root.CanCollide = false
	root.CanQuery = false
	root.CanTouch = false
	root.Anchored = true
	root.Parent = model
	model.PrimaryPart = root

	local function attach(name: string, worldPos: Vector3)
		local att = Instance.new("Attachment")
		att.Name = name
		att.CFrame = rootCF:ToObjectSpace(CFrame.new(worldPos) * (rootCF - rootCF.Position))
		att.Parent = root
	end

	local function addPart(part: BasePart, name: string, jointWorld: Vector3)
		part.Name = name
		part.Anchored = false
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.Massless = true
		part.Parent = model
		local jointCF = CFrame.new(jointWorld) * (rootCF - rootCF.Position)
		local motor = Instance.new("Motor6D")
		motor.Name = name
		motor.Part0 = root
		motor.Part1 = part
		motor.C0 = rootCF:ToObjectSpace(jointCF)
		motor.C1 = part.CFrame:ToObjectSpace(jointCF)
		motor.Parent = root
	end

	addPart(body, "Body", center)
	addPart(head, "Head", head.Position - forward * along(head, forward) * 0.85 - Vector3.new(0, head.Size.Y * 0.15, 0))
	addPart(tail, "Tail", tail.Position + forward * along(tail, forward) * 0.9)
	local lw = leftWing.Position + right * along(leftWing, right) * 0.9
	addPart(leftWing, "LeftWing", Vector3.new(lw.X, leftWing.Position.Y - along(leftWing, Vector3.yAxis) * 0.6, lw.Z))
	local rw = rightWing.Position - right * along(rightWing, right) * 0.9
	addPart(rightWing, "RightWing", Vector3.new(rw.X, rightWing.Position.Y - along(rightWing, Vector3.yAxis) * 0.6, rw.Z))

	-- Hind legs: the hip joint sits at the top of each leg.
	local leftLeg, rightLeg = found.LeftLeg, found.RightLeg
	if leftLeg and rightLeg and (leftLeg.Position - center):Dot(right) > 0 then
		leftLeg, rightLeg = rightLeg, leftLeg
	end
	for name, leg in { LeftLeg = leftLeg, RightLeg = rightLeg } do
		if leg then
			addPart(leg, name, leg.Position + Vector3.new(0, along(leg, Vector3.yAxis) * 0.8, 0))
		end
	end

	attach("RootAttachment", center)
	attach("SaddleAttachment", center + Vector3.new(0, along(body, Vector3.yAxis) * 0.85, 0) + forward * along(body, forward) * 0.25)
	attach("MouthAttachment", head.Position + forward * along(head, forward) * 0.9)
	attach("AuraAttachment", center)

	-- Stand on the feet, not on a drooping wingtip: use the legs' lowest point when present.
	local feetY = bottomY
	if found.LeftLeg or found.RightLeg then
		feetY = math.huge
		for _, leg in { found.LeftLeg, found.RightLeg } do
			if leg then
				feetY = math.min(feetY, leg.Position.Y - along(leg, Vector3.yAxis))
			end
		end
	end
	model:SetAttribute("FootOffset", center.Y - feetY)
	model:SetAttribute("Species", options.Species or "")
	model:SetAttribute("Element", options.Element or "")
	model:SetAttribute("Rig", options.Rig or "")
	model:SetAttribute("Length", math.max(size.X, size.Z))
	src:Destroy()
	return model
end

-- Western skeleton -----------------------------------------------------------------
-- source: a Model of MeshParts named with either scheme (the spec's names on the
-- right are renamed to the ones on the left):
--   Body               Pelvis                 Chest (optional)     Torso_Upper
--   Neck, Neck2, ..    Neck_01, Neck_02, ..   Head, Jaw (optional)
--   Tail1 .. TailN     Tail_01 .. Tail_04, Tail_Tip
--   LeftWing           Wing_L_Shoulder        LeftWingTip          Wing_L_Elbow
--   LeftWingMembrane   Wing_L_Membrane        (and Right / _R_)
--   FrontLeftLeg       FrontLeg_L_Upper       FrontLeftLegLower    FrontLeg_L_Lower
--   FrontLeftFoot      FrontLeg_L_Foot        HindLeftLeg..        BackLeg_L_Upper..
-- Only Body and Head are required; the skeleton uses whatever is there.
-- options: { Name, Species, Element, Length (nose-to-tail studs), CloseSeams (default true) }
--
-- Joint placement, in order of preference:
--   1. an Attachment in the child part named "JointPin" or "JointRig*" (hand-placed)
--   2. anatomy rules: top of each leg segment, inner edge of each wing, back of the jaw
--   3. chain rule: where the child meets its parent, slightly inside the child
-- Every joint shares the dragon's orientation, so pose axes mean the same thing
-- everywhere (see DragonAnimation).

local function canonicalName(name: string): string?
	if name == "Pelvis" then
		return "Body"
	elseif name == "Torso_Upper" then
		return "Chest"
	elseif name == "Tail_Tip" then
		return "TailTip" -- numbered after the other tail pieces below
	end
	local neck = name:match("^Neck_0*(%d+)$")
	if neck then
		local i = tonumber(neck) :: number
		return if i <= 1 then "Neck" else "Neck" .. i
	end
	local tail = name:match("^Tail_0*(%d+)$")
	if tail then
		return "Tail" .. tonumber(tail)
	end
	local wingSide, wingPart = name:match("^Wing_([LR])_(%a+)$")
	if wingSide then
		local side = if wingSide == "L" then "Left" else "Right"
		local map = { Shoulder = "Wing", Elbow = "WingTip", Membrane = "WingMembrane" }
		return if map[wingPart] then side .. map[wingPart] else nil
	end
	local legEnd, legSide, legPart = name:match("^(%a+)Leg_([LR])_(%a+)$")
	if legEnd == "Front" or legEnd == "Back" then
		local prefix = (if legEnd == "Front" then "Front" else "Hind") .. (if legSide == "L" then "Left" else "Right")
		local map = { Upper = "Leg", Lower = "LegLower", Foot = "Foot" }
		return if map[legPart] then prefix .. map[legPart] else nil
	end
	return nil
end

-- Parent of each canonical part, given which parts exist.
local function parentName(name: string, parts: { [string]: BasePart }): string?
	local front = if parts.Chest then "Chest" else "Body"
	if name == "Body" then
		return nil
	elseif name == "Chest" then
		return "Body"
	elseif name == "Neck" then
		return front
	end
	local neckIndex = name:match("^Neck(%d+)$")
	if neckIndex then
		local i = tonumber(neckIndex) :: number
		return if i == 2 then "Neck" else "Neck" .. (i - 1)
	end
	if name == "Head" then
		local last = nil
		if parts.Neck then
			last = "Neck"
			local i = 2
			while parts["Neck" .. i] do
				last = "Neck" .. i
				i += 1
			end
		end
		return last or front
	elseif name == "Jaw" then
		return "Head"
	end
	local tailIndex = name:match("^Tail(%d+)$")
	if tailIndex then
		local i = tonumber(tailIndex) :: number
		return if i == 1 then "Body" else "Tail" .. (i - 1)
	end
	for _, side in { "Left", "Right" } do
		if name == side .. "Wing" then
			return front
		elseif name == side .. "WingTip" then
			return side .. "Wing"
		elseif name == side .. "WingMembrane" then
			return if parts[side .. "WingTip"] then side .. "WingTip" else side .. "Wing"
		end
		for _, legEnd in { "Front", "Hind" } do
			local leg = legEnd .. side .. "Leg"
			if name == leg then
				return if legEnd == "Front" then front else "Body"
			elseif name == leg .. "Lower" then
				return leg
			elseif name == legEnd .. side .. "Foot" then
				return if parts[leg .. "Lower"] then leg .. "Lower" else leg
			end
		end
	end
	return nil
end

-- Parents first, so moving a parent before its children keeps chains connected.
local function buildOrder(parts: { [string]: BasePart }): { string }
	local order, placed = {}, {}
	local function place(name: string)
		if placed[name] or not parts[name] then
			return
		end
		local parent = parentName(name, parts)
		if parent then
			place(parent)
		end
		placed[name] = true
		table.insert(order, name)
	end
	local names = {}
	for name in parts do
		table.insert(names, name)
	end
	table.sort(names)
	for _, name in names do
		place(name)
	end
	return order
end

local function handPin(part: BasePart): Attachment?
	for _, child in part:GetChildren() do
		if child:IsA("Attachment") and (child.Name == "JointPin" or child.Name:sub(1, 8) == "JointRig") then
			return child
		end
	end
	return nil
end

local function chainName(name: string): boolean
	return name:match("^Neck") ~= nil or name:match("^Tail%d") ~= nil
end

function DragonRigBuilder.BuildWestern(source: Model, options: { [string]: any }): Model
	local src = source:Clone()
	src.Parent = workspace
	for _, d in src:GetDescendants() do
		if d:IsA("JointInstance") or d:IsA("AnimationController") or d:IsA("WeldConstraint") then
			d:Destroy()
		end
	end
	-- Collect parts under their canonical names (a rebuilt rig's Root is skipped).
	local parts: { [string]: BasePart } = {}
	local tailTip: BasePart? = nil
	for _, d in src:GetDescendants() do
		if d:IsA("BasePart") and d.Name ~= "Root" and not d:IsA("Seat") then
			local name = canonicalName(d.Name) or d.Name
			if name == "TailTip" then
				tailTip = d
			elseif parts[name] == nil then
				parts[name] = d
			end
		end
	end
	if tailTip then
		local n = 1
		while parts["Tail" .. n] do
			n += 1
		end
		parts["Tail" .. n] = tailTip
	end
	for name, p in parts do
		p.Name = name
	end
	assert(parts.Body and parts.Head, "BuildWestern: needs at least Body (or Pelvis) and Head")

	-- Nose-to-tail length (wings excluded), then scale to the wanted length.
	local function forwardOf(): Vector3
		return ((parts.Head.Position - parts.Body.Position) * Vector3.new(1, 0, 1)).Unit
	end
	local function spanAlong(dir: Vector3): number
		local lo, hi = math.huge, -math.huge
		for name, p in parts do
			if name == "Body" or name == "Chest" or name == "Head" or name == "Jaw" or chainName(name) then
				local c = p.Position:Dot(dir)
				local h = along(p, dir)
				lo, hi = math.min(lo, c - h), math.max(hi, c + h)
			end
		end
		return hi - lo
	end
	if options.Length then
		src:ScaleTo(src:GetScale() * options.Length / spanAlong(forwardOf()))
	end

	local body = parts.Body
	local forward = forwardOf()
	local center = body.Position
	local rootCF = CFrame.lookAt(center, center + forward)
	local right = rootCF.RightVector
	local up = Vector3.yAxis

	-- Seams: pull each neck/tail piece a little into its parent, so bending the
	-- chain shows the parent's surface instead of a hollow cut. Skipped where a
	-- joint was hand-placed. TUNING: SEAM_OVERLAP (fraction of the child's length).
	local SEAM_OVERLAP, SEAM_MAX_SHIFT = 0.05, 0.08
	if options.CloseSeams ~= false then
		local order = buildOrder(parts)
		for _, name in order do
			local child = parts[name]
			local parentKey = parentName(name, parts)
			local parent = parentKey and parts[parentKey]
			if parent and chainName(name) and not handPin(child) then
				local dir = child.Position - parent.Position
				if dir.Magnitude > 0.01 then
					dir = dir.Unit
					local childLen = along(child, dir) * 2
					local parentFar = parent.Position:Dot(dir) + along(parent, dir)
					local childNear = child.Position:Dot(dir) - along(child, dir)
					local gap = childNear - parentFar
					local shift = math.clamp(gap + SEAM_OVERLAP * childLen, 0, SEAM_MAX_SHIFT * childLen)
					if shift > 0 then
						-- move this piece and everything further down the chain
						for _, other in order do
							local k = other
							while k do
								if k == name then
									parts[other].CFrame -= dir * shift
									break
								end
								k = parentName(k, parts) :: any
							end
						end
					end
				end
			end
		end
	end

	local model = Instance.new("Model")
	model.Name = options.Name or source.Name
	local root = Instance.new("Part")
	root.Name = "Root"
	root.Size = Vector3.new(4, 4, 6)
	root.CFrame = rootCF
	root.Transparency = 1
	root.CanCollide = false
	root.CanQuery = false
	root.CanTouch = false
	root.Anchored = true
	root.Parent = model
	model.PrimaryPart = root

	-- Visual parts never collide and carry no mass: physics runs on Root only.
	for _, p in parts do
		p.Anchored = false
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Massless = true
		p.Parent = model
	end

	local orientation = rootCF - rootCF.Position
	local function joint(name: string, parent: BasePart, child: BasePart, worldPos: Vector3)
		local jointCF = CFrame.new(worldPos) * orientation
		local motor = Instance.new("Motor6D")
		motor.Name = name
		motor.Part0 = parent
		motor.Part1 = child
		motor.C0 = parent.CFrame:ToObjectSpace(jointCF)
		motor.C1 = child.CFrame:ToObjectSpace(jointCF)
		motor.Parent = root -- all joints live on Root, where DragonMotionController looks for them
	end

	joint("Body", root, body, center)
	for _, name in buildOrder(parts) do
		local parentKey = parentName(name, parts)
		local child = parts[name]
		local parent = parentKey and parts[parentKey]
		if parent then
			local at: Vector3
			local pin = handPin(child)
			if pin then
				at = pin.WorldPosition
			elseif name:find("Leg$") or name:find("LegLower$") then
				at = child.Position + up * along(child, up) * 0.8 -- hip / shoulder / knee: top of the segment
			elseif name:find("Foot$") then
				at = child.Position + up * along(child, up) * 0.7 -- ankle
			elseif name == "LeftWing" or name == "RightWing" then
				local side = if name == "LeftWing" then -right else right
				at = child.Position - side * along(child, side) * 0.85 -- inner edge, next to the body
				at = Vector3.new(at.X, child.Position.Y - along(child, up) * 0.35, at.Z)
			elseif name == "Jaw" then
				at = child.Position - forward * along(child, forward) * 0.8 + up * along(child, up) * 0.5 -- hinge
			else
				local dir = child.Position - parent.Position
				dir = if dir.Magnitude > 0.01 then dir.Unit else forward
				at = child.Position - dir * along(child, dir) * 0.85
			end
			joint(name, parent, child, at)
		end
	end

	-- Root-level attachments the movers and effects use.
	for _, n in { "RootAttachment", "AuraAttachment" } do
		local att = Instance.new("Attachment")
		att.Name = n
		att.Parent = root
	end
	-- Stand on the feet.
	local feetY = math.huge
	for name, p in parts do
		if name:find("Leg$") or name:find("LegLower$") or name:find("Foot$") then
			feetY = math.min(feetY, p.Position.Y - along(p, up))
		end
	end
	if feetY == math.huge then
		local cf, size = model:GetBoundingBox()
		feetY = cf.Position.Y - size.Y / 2
	end
	model:SetAttribute("FootOffset", center.Y - feetY)
	model:SetAttribute("Species", options.Species or "")
	model:SetAttribute("Element", options.Element or "")
	model:SetAttribute("DragonElement", options.Element or "")
	model:SetAttribute("Rig", "Western")
	model:SetAttribute("Length", spanAlong(forward))
	DragonRigBuilder.AddAnatomyPoints(model)
	src:Destroy()
	return model
end

-- Anatomy points for saddles and effects ------------------------------------------
-- Adds (or moves) attachments on a built Western rig. Safe to run again on an
-- existing template, e.g. after changing the rules here:
--   Root.SaddleAttachment   on the back, behind the neck base and ahead of the
--                           wing shoulders, sitting on the body's real surface
--   Mouth_VFX               front of the head (on the Jaw when there is one)
--   BreathEnd               a short way ahead of the mouth (breath beam target)
--   Chest_Core              front-lower chest       Dorsal_Spines  top of the back
--   Wing_L_Tip, Wing_R_Tip  outer end of each wing  Tail_Tip       end of the last tail piece
--   Feet_Front_L/R, Feet_Back_L/R  under each foot
-- Older names (MouthAttachment, TipAttachment) are kept for existing code.
local AssetService = game:GetService("AssetService")

-- Highest point of a mesh's real surface near a world XZ position (falls back
-- to the top of its box when the mesh can't be read).
local function surfaceTop(part: BasePart, at: Vector3, radius: number): number
	local ok, top = pcall(function()
		if not part:IsA("MeshPart") then
			error("not a mesh")
		end
		local em = AssetService:CreateEditableMeshAsync(Content.fromUri(part.MeshId))
		local scale = part.Size / part.MeshSize
		local best = -math.huge
		for _, v in em:GetVertices() do
			local w = part.CFrame:PointToWorldSpace(em:GetPosition(v) * scale)
			if (Vector2.new(w.X, w.Z) - Vector2.new(at.X, at.Z)).Magnitude < radius then
				best = math.max(best, w.Y)
			end
		end
		em:Destroy()
		if best == -math.huge then
			error("no vertices near the spot")
		end
		return best
	end)
	return if ok then top else part.Position.Y + along(part, Vector3.yAxis) * 0.9
end

function DragonRigBuilder.AddAnatomyPoints(model: Model)
	local root = model.PrimaryPart :: BasePart
	local rootCF = root.CFrame
	local forward, right, up = rootCF.LookVector, rootCF.RightVector, Vector3.yAxis
	local function part(name: string): BasePart?
		local p = model:FindFirstChild(name)
		return if p and p:IsA("BasePart") then p else nil
	end
	local function jointWorld(name: string): Vector3?
		local m = root:FindFirstChild(name)
		if m and m:IsA("Motor6D") and m.Part0 then
			return (m.Part0.CFrame * m.C0).Position
		end
		return nil
	end
	local function put(holder: BasePart, name: string, world: Vector3): Attachment
		local att = holder:FindFirstChild(name)
		if not (att and att:IsA("Attachment")) then
			att = Instance.new("Attachment")
			att.Name = name
			att.Parent = holder
		end
		att.CFrame = holder.CFrame:ToObjectSpace(CFrame.new(world) * (rootCF - rootCF.Position))
		return att :: Attachment
	end
	local body = part("Body") :: BasePart
	local chest = part("Chest")
	local front = chest or body

	-- Saddle. TUNING: SADDLE_BACK = how far from the neck base toward the
	-- shoulders (0 = at the neck, 1 = at the wing roots); SADDLE_RAISE = studs
	-- the seat sits above the scales.
	local SADDLE_BACK, SADDLE_RAISE = 0.55, 0.35
	local neckBase = jointWorld("Neck")
	local lw, rw = jointWorld("LeftWing"), jointWorld("RightWing")
	local spot: Vector3
	if neckBase and lw and rw then
		local shoulders = (lw + rw) / 2
		spot = neckBase:Lerp(shoulders, SADDLE_BACK)
		-- the seat never goes behind the wing roots, where the rider's legs would hit the wings
		local behind = (spot - shoulders):Dot(forward)
		if behind < 0 then
			spot -= forward * behind
		end
	else
		spot = body.Position + forward * along(body, forward) * 0.4
	end
	spot -= right * (spot - body.Position):Dot(right) -- centred on the spine
	local holder = if chest and (spot - chest.Position):Dot(forward) > -along(chest, forward) then chest else body
	local top = surfaceTop(holder, spot, along(holder, right) * 0.35)
	local seatY = top + SADDLE_RAISE - 0.5 -- the Seat is 1 stud thick; riders sit on its top face
	local saddle = root:FindFirstChild("SaddleAttachment") or Instance.new("Attachment")
	saddle.Name = "SaddleAttachment"
	saddle.Parent = root
	;(saddle :: Attachment).CFrame = rootCF:ToObjectSpace(CFrame.new(Vector3.new(spot.X, seatY, spot.Z)) * (rootCF - rootCF.Position))

	-- Mouth and breath target.
	local head = part("Head") :: BasePart
	local jaw = part("Jaw")
	local mouthHolder = jaw or head
	local mouth = mouthHolder.Position + forward * along(mouthHolder, forward) * 0.85 - up * along(mouthHolder, up) * (if jaw then 0 else 0.2)
	put(mouthHolder, "Mouth_VFX", mouth)
	put(mouthHolder, "MouthAttachment", mouth)
	put(mouthHolder, "BreathEnd", mouth + forward * (model:GetAttribute("Length") or 36) * 0.3)

	-- Chest core and spines.
	put(front, "Chest_Core", front.Position + forward * along(front, forward) * 0.55 - up * along(front, up) * 0.35)
	put(body, "Dorsal_Spines", Vector3.new(body.Position.X, surfaceTop(body, body.Position, along(body, right) * 0.4) + 0.2, body.Position.Z))

	-- Wingtips: the outer end of the last wing piece.
	for _, s in { { "Left", "L", -right }, { "Right", "R", right } } do
		local tip = part(s[1] .. "WingMembrane") or part(s[1] .. "WingTip") or part(s[1] .. "Wing")
		if tip then
			local outer = tip.Position + s[3] * along(tip, s[3]) * 0.85
			put(tip, "Wing_" .. s[2] .. "_Tip", outer)
			put(tip, "TipAttachment", outer)
		end
	end

	-- Tail tip: the far end of the last tail piece.
	local n = 1
	while part("Tail" .. (n + 1)) do
		n += 1
	end
	local last = part("Tail" .. n)
	if last then
		local prev = part("Tail" .. (n - 1)) or body
		local dir = (last.Position - prev.Position)
		dir = if dir.Magnitude > 0.01 then dir.Unit else -forward
		put(last, "Tail_Tip", last.Position + dir * along(last, dir) * 0.85)
	end

	-- Feet: under the lowest piece of each leg.
	for _, legEnd in { { "Front", "Front" }, { "Hind", "Back" } } do
		for _, side in { { "Left", "L" }, { "Right", "R" } } do
			local base = legEnd[1] .. side[1]
			local foot = part(base .. "Foot") or part(base .. "LegLower") or part(base .. "Leg")
			if foot then
				put(foot, "Feet_" .. legEnd[2] .. "_" .. side[2], foot.Position - up * along(foot, up) * 0.9)
			end
		end
	end
end

return DragonRigBuilder
