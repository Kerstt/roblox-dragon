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

return DragonRigBuilder
