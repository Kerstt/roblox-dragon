-- ReplicatedStorage/Client/UI
-- Unified Viking UI/UX design system built directly from hud.jpeg and shop.jpeg:
--   * Forged dark wrought-iron frames studded with round copper/brass rivets
--   * Horizontal weathered Nordic oak timber planks with dark plank seams
--   * Hanging forged-iron link chains connecting top plaques and Great-Hall sheets
--   * Sculpted Norse dragon-prow figurehead & circular crossed-bones close shield
--   * Recessed obsidian/slate content wells & molten-gold / smoked-timber plaques

local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local VikingModels = require(script.Parent.VikingModels)

local UI = {}

UI.Colors = {
	-- Forged wrought iron & brass hardware
	IronOuter = Color3.fromRGB(58, 61, 68),
	IronMid = Color3.fromRGB(84, 88, 98),
	IronHighlight = Color3.fromRGB(128, 134, 146),
	Iron = Color3.fromRGB(104, 110, 122),
	Rivet = Color3.fromRGB(204, 144, 74),
	RivetHighlight = Color3.fromRGB(250, 208, 138),

	-- Weathered Nordic oak timber & recessed obsidian slate
	Panel = Color3.fromRGB(88, 56, 33),
	Panel2 = Color3.fromRGB(31, 32, 36), -- Recessed dark obsidian/slate stone well (shop.jpeg)
	Panel3 = Color3.fromRGB(52, 40, 33), -- Warm smoked-oak card surface
	WoodPlankTop = Color3.fromRGB(112, 70, 41),
	WoodPlankMid = Color3.fromRGB(94, 58, 34),
	WoodPlankBot = Color3.fromRGB(76, 46, 26),
	WoodSeam = Color3.fromRGB(34, 19, 10),
	WoodDark = Color3.fromRGB(22, 14, 10),
	WoodLight = Color3.fromRGB(116, 74, 43),

	-- Accents, typography & CTAs
	Stroke = Color3.fromRGB(198, 148, 66), -- Burnished bronze-gold trim
	Crimson = Color3.fromRGB(138, 38, 30),
	Text = Color3.fromRGB(248, 238, 218), -- Warm parchment cream
	Muted = Color3.fromRGB(194, 178, 154),
	Gold = Color3.fromRGB(255, 204, 84), -- Chiseled Viking gold
	GoldSoft = Color3.fromRGB(244, 222, 168), -- Warm cream-gold (+income/s in hud.jpeg)
	Ember = Color3.fromRGB(236, 182, 78), -- Glowing active plaque gold
	Rune = Color3.fromRGB(120, 216, 248),
	Good = Color3.fromRGB(106, 214, 132),
	Bad = Color3.fromRGB(232, 88, 78),
	Button = Color3.fromRGB(232, 176, 72), -- Molten amber-gold CTA plaque
	ButtonText = Color3.fromRGB(34, 20, 8), -- Chiseled dark espresso text
	Secondary = Color3.fromRGB(68, 54, 44), -- Weathered timber-slate plaque
	Disabled = Color3.fromRGB(60, 56, 56),
}

UI.Font = Enum.Font.GothamMedium
UI.FontBold = Enum.Font.GothamBold
UI.FontDisplay = Enum.Font.Merriweather

UI.SheetChanged = Instance.new("BindableEvent")

function UI.new(className: string, props: { [string]: any }?): any
	local inst = Instance.new(className)
	local parent = nil
	if props then
		for key, value in props do
			if key == "Parent" then
				parent = value
			else
				(inst :: any)[key] = value
			end
		end
	end
	if inst:IsA("GuiObject") and (props == nil or props.BorderSizePixel == nil) then
		inst.BorderSizePixel = 0
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

function UI.corner(inst: Instance, radius: number?): UICorner
	return UI.new("UICorner", { CornerRadius = UDim.new(0, radius or 10), Parent = inst })
end

function UI.stroke(inst: Instance, color: Color3?, thickness: number?): UIStroke
	return UI.new("UIStroke", {
		Color = color or UI.Colors.Stroke,
		Thickness = thickness or 1.5,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = inst,
	})
end

function UI.padding(inst: Instance, top: number, right: number?, bottom: number?, left: number?): UIPadding
	local r = right or top
	local b = bottom or top
	local l = left or r
	return UI.new("UIPadding", {
		PaddingTop = UDim.new(0, top),
		PaddingRight = UDim.new(0, r),
		PaddingBottom = UDim.new(0, b),
		PaddingLeft = UDim.new(0, l),
		Parent = inst,
	})
end

function UI.gradient(inst: Instance, topColor: Color3, bottomColor: Color3, rotation: number?): UIGradient
	return UI.new("UIGradient", {
		Color = ColorSequence.new(topColor, bottomColor),
		Rotation = rotation or 90,
		Parent = inst,
	})
end

function UI.list(inst: Instance, gap: number?, horizontal: boolean?): UIListLayout
	return UI.new("UIListLayout", {
		Padding = UDim.new(0, gap or 8),
		FillDirection = if horizontal then Enum.FillDirection.Horizontal else Enum.FillDirection.Vertical,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = inst,
	})
end

-- Responsive UIScale helper so top plaque, sheets, and bottom 6-arch dock fit
-- cleanly on both desktop monitors and compact Studio / mobile viewports.
function UI.attachResponsiveScale(target: Instance, refHeight: number?, minScale: number?): UIScale
	local scale = UI.new("UIScale", { Scale = 1, Parent = target })
	local refH = refHeight or 760
	local floorS = minScale or 0.68
	local camConn: RBXScriptConnection? = nil

	local function update()
		local cam = Workspace.CurrentCamera
		if not cam then
			return
		end
		local vp = cam.ViewportSize
		if vp.Y > 0 then
			local byH = vp.Y / refH
			local byW = vp.X / 820
			scale.Scale = math.clamp(math.min(byH, byW), floorS, 1)
		end
	end

	local function bindCamera()
		if camConn then
			camConn:Disconnect()
			camConn = nil
		end
		local cam = Workspace.CurrentCamera
		if cam then
			camConn = cam:GetPropertyChangedSignal("ViewportSize"):Connect(update)
			update()
		end
	end

	Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(bindCamera)
	bindCamera()
	target.Destroying:Connect(function()
		if camConn then
			camConn:Disconnect()
		end
	end)
	return scale
end

-- Single circular hammered copper/brass rivet with specular highlight dot
function UI.roundRivet(parent: Instance, pos: UDim2, size: number?, zIndex: number?, color: Color3?): Frame
	local s = size or 7
	local z = zIndex or (if parent:IsA("GuiObject") then parent.ZIndex + 4 else 5)
	local stud = UI.new("Frame", {
		Name = "Rivet",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = pos,
		Size = UDim2.fromOffset(s, s),
		BackgroundColor3 = color or UI.Colors.Rivet,
		ZIndex = z,
		Parent = parent,
	})
	UI.corner(stud, s)
	UI.stroke(stud, UI.Colors.WoodDark, 1)
	if s >= 6 then
		local hi = UI.new("Frame", {
			Position = UDim2.fromOffset(1, 1),
			Size = UDim2.fromOffset(math.max(2, math.floor(s * 0.34)), math.max(2, math.floor(s * 0.34))),
			BackgroundColor3 = UI.Colors.RivetHighlight,
			BackgroundTransparency = 0.2,
			ZIndex = z + 1,
			Parent = stud,
		})
		UI.corner(hi, s)
	end
	return stud
end

-- Four corner forged brass rivets (never put directly on a UIListLayout parent)
function UI.rivets(frame: GuiObject, color: Color3?, size: number?, zIndex: number?, inset: number?)
	local s = size or 7
	local pad = inset or 9
	local col = color or UI.Colors.Rivet
	local z = zIndex or (frame.ZIndex + 4)
	local anchors = {
		UDim2.fromOffset(pad, pad),
		UDim2.new(1, -pad, 0, pad),
		UDim2.new(0, pad, 1, -pad),
		UDim2.new(1, -pad, 1, -pad),
	}
	for _, pos in anchors do
		UI.roundRivet(frame, pos, s, z, col)
	end
end

-- Perimeter forged brass rivets along top, bottom, and optional side iron rails
function UI.perimeterRivets(frame: GuiObject, topCount: number, sideCount: number, zIndex: number?, size: number?, inset: number?)
	local s = size or 6
	local pad = inset or 5
	local z = zIndex or (frame.ZIndex + 5)
	for i = 0, topCount - 1 do
		local alpha = if topCount <= 1 then 0.5 else i / (topCount - 1)
		local xOff = math.floor((0.5 - alpha) * -2 * pad)
		local posTop = if i == 0
			then UDim2.fromOffset(pad + 4, pad)
			elseif i == topCount - 1 then UDim2.new(1, -(pad + 4), 0, pad)
			else UDim2.new(alpha, xOff, 0, pad)
		local posBot = if i == 0
			then UDim2.new(0, pad + 4, 1, -pad)
			elseif i == topCount - 1 then UDim2.new(1, -(pad + 4), 1, -pad)
			else UDim2.new(alpha, xOff, 1, -pad)
		UI.roundRivet(frame, posTop, s, z)
		UI.roundRivet(frame, posBot, s, z)
	end
	for j = 1, sideCount do
		local alpha = j / (sideCount + 1)
		UI.roundRivet(frame, UDim2.new(0, pad, alpha, 0), s, z)
		UI.roundRivet(frame, UDim2.new(1, -pad, alpha, 0), s, z)
	end
end

function UI.horns(frame: GuiObject, color: Color3?, zIndex: number?)
	local col = color or UI.Colors.IronMid
	local z = zIndex or (frame.ZIndex + 3)
	for _, x in { 0, 1 } do
		local plate = UI.new("Frame", {
			Name = if x == 0 then "LeftBracket" else "RightBracket",
			AnchorPoint = Vector2.new(x, 0),
			Position = UDim2.new(x, 0, 0, 0),
			Size = UDim2.fromOffset(18, 6),
			BackgroundColor3 = col,
			ZIndex = z,
			Parent = frame,
		})
		UI.corner(plate, 2)
	end
end

-- Carved bronze Norse triquetra/knotwork corner medallion (hud.jpeg & shop.jpeg)
function UI.knotMedallion(parent: Instance, pos: UDim2, anchor: Vector2, size: number?, zIndex: number?): Frame
	local s = size or 22
	local z = zIndex or 4
	local holder = UI.new("Frame", {
		Name = "NorseKnot",
		AnchorPoint = anchor,
		Position = pos,
		Size = UDim2.fromOffset(s, s),
		BackgroundTransparency = 1,
		ZIndex = z,
		Parent = parent,
	})
	for idx, rot in { 0, 60, 120 } do
		local loop = UI.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(0.86, 0, 0.36, 0),
			Rotation = rot,
			BackgroundTransparency = 1,
			ZIndex = z + (idx % 2),
			Parent = holder,
		})
		UI.corner(loop, s)
		UI.stroke(loop, UI.Colors.Stroke, 1.6)
	end
	local hub = UI.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(5, 5),
		Rotation = 45,
		BackgroundColor3 = UI.Colors.Gold,
		ZIndex = z + 2,
		Parent = holder,
	})
	UI.corner(hub, 1)
	return holder
end

-- Renders horizontal weathered oak timber planks with dark wood seams inside `parent`
function UI.woodPlanks(parent: GuiObject, plankCount: number?, zIndex: number?, radius: number?): Frame
	local count = plankCount or 3
	local z = zIndex or (parent.ZIndex + 1)
	local r = radius or 6
	local board = UI.new("Frame", {
		Name = "WoodPlanks",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = UI.Colors.Panel,
		ClipsDescendants = true,
		ZIndex = z,
		Parent = parent,
	})
	UI.corner(board, r)
	UI.gradient(board, Color3.fromRGB(255, 240, 218), Color3.fromRGB(168, 138, 118), 90)

	-- Subtle vertical edge vignette like weathered longhouse planks
	for _, side in { 0, 1 } do
		local shade = UI.new("Frame", {
			AnchorPoint = Vector2.new(side, 0),
			Position = UDim2.fromScale(side, 0),
			Size = UDim2.new(0, 18, 1, 0),
			BackgroundColor3 = UI.Colors.WoodDark,
			BackgroundTransparency = 0.72,
			ZIndex = z + 1,
			Parent = board,
		})
		UI.gradient(
			shade,
			if side == 0 then Color3.new(0, 0, 0) else Color3.new(1, 1, 1),
			if side == 0 then Color3.new(1, 1, 1) else Color3.new(0, 0, 0),
			0
		)
	end

	-- Horizontal plank seam grooves + warm wood bevel edge
	for i = 1, count - 1 do
		local y = i / count
		UI.new("Frame", {
			Position = UDim2.new(0, 0, y, -1),
			Size = UDim2.new(1, 0, 0, 2),
			BackgroundColor3 = UI.Colors.WoodSeam,
			BackgroundTransparency = 0.2,
			ZIndex = z + 1,
			Parent = board,
		})
		UI.new("Frame", {
			Position = UDim2.new(0, 0, y, 1),
			Size = UDim2.new(1, 0, 0, 1),
			BackgroundColor3 = Color3.fromRGB(164, 114, 70),
			BackgroundTransparency = 0.65,
			ZIndex = z + 1,
			Parent = board,
		})
	end
	return board
end

-- Forged dark wrought-iron link chain connecting top currency plaque to Saga signboard & modal sheets
function UI.hangingChain(parent: Instance, xPos: UDim2, topY: number, height: number, zIndex: number?): Frame
	local z = zIndex or 5
	local chain = UI.new("Frame", {
		Name = "IronChain",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(xPos.X.Scale, xPos.X.Offset, 0, topY),
		Size = UDim2.fromOffset(14, height),
		BackgroundTransparency = 1,
		ZIndex = z,
		Parent = parent,
	})

	-- Top & bottom iron mounting shackles
	for _, y in { 0, height - 6 } do
		local ring = UI.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, y),
			Size = UDim2.fromOffset(12, 6),
			BackgroundColor3 = UI.Colors.IronOuter,
			ZIndex = z + 2,
			Parent = chain,
		})
		UI.corner(ring, 3)
		UI.stroke(ring, UI.Colors.IronHighlight, 1)
	end

	local links = math.max(2, math.floor(height / 9))
	for i = 1, links do
		local ly = (i - 1) * (height / links)
		if i % 2 == 1 then
			-- Broad oval iron link
			local oval = UI.new("Frame", {
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.new(0.5, 0, 0, ly),
				Size = UDim2.fromOffset(10, 11),
				BackgroundColor3 = UI.Colors.WoodDark,
				BackgroundTransparency = 0.25,
				ZIndex = z,
				Parent = chain,
			})
			UI.corner(oval, 5)
			UI.stroke(oval, UI.Colors.IronMid, 2.2)
		else
			-- Edge-on vertical connecting link
			local bar = UI.new("Frame", {
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.new(0.5, 0, 0, ly),
				Size = UDim2.fromOffset(5, 11),
				BackgroundColor3 = UI.Colors.IronHighlight,
				ZIndex = z + 1,
				Parent = chain,
			})
			UI.corner(bar, 2)
			UI.stroke(bar, UI.Colors.WoodDark, 1)
		end
	end
	return chain
end

-- Forged iron border + brass rivets + horizontal oak planks (hud.jpeg ResourcePlaque & Saga Signboard)
function UI.ironWoodPlaque(frame: GuiObject, plankCount: number?, radius: number?, topRivets: number?, sideRivets: number?): Frame
	local r = radius or 8
	frame.BackgroundColor3 = UI.Colors.IronOuter
	UI.corner(frame, r)
	UI.gradient(frame, Color3.fromRGB(224, 228, 238), Color3.fromRGB(122, 126, 136), 90)
	UI.stroke(frame, UI.Colors.WoodDark, 1.8)

	local innerRim = UI.new("Frame", {
		Name = "IronInnerRim",
		Position = UDim2.fromOffset(9, 9),
		Size = UDim2.new(1, -18, 1, -18),
		BackgroundColor3 = UI.Colors.Panel,
		ZIndex = frame.ZIndex + 1,
		Parent = frame,
	})
	UI.corner(innerRim, math.max(4, r - 3))
	UI.stroke(innerRim, UI.Colors.WoodDark, 1.6)

	local board = UI.woodPlanks(innerRim, plankCount or 3, frame.ZIndex + 1, math.max(4, r - 3))
	UI.perimeterRivets(frame, topRivets or 6, sideRivets or 1, frame.ZIndex + 4, 6, 5)
	return board
end

-- Forged iron & dark obsidian-well panel (kept compatible with StarterPicker, WelcomeBack, HatchReveal)
-- IMPORTANT: Only call on frames whose children are explicitly positioned (NOT UIListLayout parents).
function UI.vikingPanel(frame: GuiObject, accentColor: Color3?, radius: number?, rivetSize: number?)
	local accent = accentColor or UI.Colors.Stroke
	local r = radius or 12
	frame.BackgroundColor3 = UI.Colors.IronOuter
	UI.corner(frame, r)
	UI.gradient(frame, Color3.fromRGB(226, 230, 240), Color3.fromRGB(118, 122, 132), 90)
	local stroke = UI.stroke(frame, accent, 2.0)

	local well = UI.new("Frame", {
		Name = "InnerWell",
		Position = UDim2.fromOffset(8, 8),
		Size = UDim2.new(1, -16, 1, -16),
		BackgroundColor3 = UI.Colors.Panel2,
		BackgroundTransparency = 0.02,
		ZIndex = frame.ZIndex,
		Parent = frame,
	})
	UI.corner(well, math.max(5, r - 4))
	UI.stroke(well, UI.Colors.WoodDark, 1.8)

	UI.perimeterRivets(frame, 5, 2, frame.ZIndex + 4, rivetSize or 6, 4)
	return stroke
end

function UI.runeDivider(parent: Instance, layoutOrder: number?, color: Color3?, zIndex: number?): Frame
	local col = color or UI.Colors.IronMid
	local z = zIndex or 8
	local wrap = UI.new("Frame", {
		Size = UDim2.new(1, 0, 0, 16),
		BackgroundTransparency = 1,
		LayoutOrder = layoutOrder or 0,
		ZIndex = z,
		Parent = parent,
	})
	UI.new("Frame", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 4, 0.5, 0),
		Size = UDim2.new(0.5, -18, 0, 2),
		BackgroundColor3 = col,
		BackgroundTransparency = 0.15,
		ZIndex = z,
		Parent = wrap,
	})
	UI.new("Frame", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -4, 0.5, 0),
		Size = UDim2.new(0.5, -18, 0, 2),
		BackgroundColor3 = col,
		BackgroundTransparency = 0.15,
		ZIndex = z,
		Parent = wrap,
	})
	local gem = UI.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(9, 9),
		Rotation = 45,
		BackgroundColor3 = UI.Colors.Stroke,
		ZIndex = z + 1,
		Parent = wrap,
	})
	UI.stroke(gem, UI.Colors.WoodDark, 1.4)
	return wrap
end

local ICON_BG: { [string]: Color3 } = {
	Eggs = Color3.fromRGB(58, 42, 28),
	Dragons = Color3.fromRGB(68, 28, 24),
	Stations = Color3.fromRGB(44, 46, 54),
	Ride = Color3.fromRGB(48, 38, 30),
	Battle = Color3.fromRGB(64, 28, 28),
	Shop = Color3.fromRGB(62, 44, 24),
	MerchantStall = Color3.fromRGB(66, 44, 26),
	Coins = Color3.fromRGB(58, 40, 18),
	Essence = Color3.fromRGB(42, 28, 58),
	Horn = Color3.fromRGB(52, 36, 24),
	Raid = Color3.fromRGB(56, 28, 72),
}

local ICON_RINGS: { [string]: Color3 } = {
	Eggs = Color3.fromRGB(218, 168, 78),
	Dragons = Color3.fromRGB(224, 134, 62),
	Stations = Color3.fromRGB(186, 158, 96),
	Ride = Color3.fromRGB(206, 168, 98),
	Battle = Color3.fromRGB(214, 132, 76),
	Shop = Color3.fromRGB(238, 188, 78),
	MerchantStall = Color3.fromRGB(218, 164, 74),
	Coins = Color3.fromRGB(246, 194, 78),
	Essence = Color3.fromRGB(196, 138, 255),
	Horn = Color3.fromRGB(214, 162, 78),
	Raid = Color3.fromRGB(198, 148, 255),
}

-- Carved Viking medallion socket containing a brightly-lit 3D mini-model
function UI.icon(parent: Instance, kind: string, size: number?, color: Color3?, zIndex: number?, spinSpeed: number?, circular: boolean?): Frame
	local s = size or 36
	local ring = color or ICON_RINGS[kind] or UI.Colors.Stroke
	local bg = ICON_BG[kind] or UI.Colors.Panel2
	local z = zIndex or 3
	local badge = UI.new("Frame", {
		Name = kind .. "Icon",
		Size = UDim2.fromOffset(s, s),
		BackgroundColor3 = bg,
		ZIndex = z,
		Parent = parent,
	})
	UI.corner(badge, if circular then s else math.floor(s * 0.28))
	UI.gradient(badge, Color3.fromRGB(255, 246, 230), Color3.fromRGB(132, 116, 108), 110)
	UI.stroke(badge, ring, 1.8)

	VikingModels.ViewportIcon(badge, kind, UDim2.fromScale(1.18, 1.18), spinSpeed or 0, z + 1).Position = UDim2.fromScale(-0.09, -0.09)
	return badge
end

function UI.label(parent: Instance, text: string, size: number?, props: { [string]: any }?): TextLabel
	local parentZ = if parent:IsA("GuiObject") then parent.ZIndex else 1
	local p = {
		BackgroundTransparency = 1,
		Font = UI.Font,
		Text = text,
		TextSize = size or 16,
		TextColor3 = UI.Colors.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = true,
		RichText = true,
		ZIndex = parentZ + 1,
		Size = UDim2.new(1, 0, 0, (size or 16) + 6),
		Parent = parent,
	}
	if props then
		for k, v in props do
			p[k] = v
		end
	end
	return UI.new("TextLabel", p)
end

-- Sculpted Viking Plaque CTA button (burnished molten-gold primary or riveted timber-slate secondary)
function UI.button(parent: Instance, text: string, onClick: () -> (), props: { [string]: any }?): (TextButton, (boolean, string?) -> ())
	local parentZ = if parent:IsA("GuiObject") then parent.ZIndex else 1
	local p = {
		BackgroundColor3 = UI.Colors.Button,
		TextColor3 = UI.Colors.ButtonText,
		Font = UI.FontBold,
		Text = text,
		TextSize = 15,
		AutoButtonColor = false,
		ZIndex = parentZ + 1,
		Size = UDim2.new(1, 0, 0, 42),
		Parent = parent,
	}
	if props then
		for k, v in props do
			p[k] = v
		end
	end
	local button: TextButton = UI.new("TextButton", p)
	local baseColor = button.BackgroundColor3
	local baseTextColor = button.TextColor3
	local isGold = baseColor == UI.Colors.Button or baseColor == UI.Colors.Gold or baseColor == UI.Colors.Ember
	local isPositive = baseColor == UI.Colors.Good

	UI.corner(button, 7)
	if isGold then
		UI.gradient(button, Color3.fromRGB(255, 246, 214), Color3.fromRGB(186, 140, 88), 90)
	elseif isPositive then
		UI.gradient(button, Color3.fromRGB(240, 255, 242), Color3.fromRGB(138, 188, 146), 90)
	else
		UI.gradient(button, Color3.fromRGB(238, 224, 208), Color3.fromRGB(142, 124, 112), 90)
	end
	local btnStroke = UI.stroke(button, if isGold then UI.Colors.Gold elseif isPositive then UI.Colors.Good else UI.Colors.IronMid, if isGold then 1.8 else 1.4)

	-- Top bevel sheen + subtle corner rivets like shop.jpeg plaques
	UI.new("Frame", {
		Position = UDim2.fromOffset(6, 2),
		Size = UDim2.new(1, -12, 0, 2),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = if isGold then 0.56 else 0.78,
		ZIndex = button.ZIndex + 1,
		Parent = button,
	})
	UI.rivets(button, if isGold then Color3.fromRGB(156, 104, 34) else UI.Colors.Rivet, 4, button.ZIndex + 2, 5)

	local scale = UI.new("UIScale", { Scale = 1, Parent = button })
	local enabled = true

	button.MouseEnter:Connect(function()
		if enabled then
			UI.tween(scale, 0.1, { Scale = 1.02 })
			btnStroke.Color = UI.Colors.Gold
		end
	end)
	button.MouseLeave:Connect(function()
		UI.tween(scale, 0.1, { Scale = 1 })
		btnStroke.Color = if not enabled
			then UI.Colors.IronOuter
			elseif isGold then UI.Colors.Gold
			elseif isPositive then UI.Colors.Good
			else UI.Colors.IronMid
	end)
	button.MouseButton1Down:Connect(function()
		if enabled then
			UI.tween(scale, 0.06, { Scale = 0.96 })
		end
	end)
	button.MouseButton1Up:Connect(function()
		if enabled then
			UI.tween(scale, 0.1, { Scale = 1 })
		end
	end)
	button.Activated:Connect(function()
		if enabled then
			onClick()
		end
	end)

	local function setEnabled(on: boolean, newText: string?)
		enabled = on
		button.BackgroundColor3 = if on then baseColor else UI.Colors.Disabled
		button.TextColor3 = if on then baseTextColor else UI.Colors.Muted
		btnStroke.Color = if not on
			then UI.Colors.IronOuter
			elseif isGold then UI.Colors.Gold
			elseif isPositive then UI.Colors.Good
			else UI.Colors.IronMid
		if not on then
			scale.Scale = 1
		end
		if newText then
			button.Text = newText
		end
	end
	return button, setEnabled
end

-- Exact riveted 4-tab bar from shop.jpeg: active = glowing golden plaque + dark text;
-- inactive = weathered dark-oak plaque + forged iron border + warm cream-gold text.
function UI.tabBar(parent: Instance, tabs: { string }, activeTab: string, onSelect: (string) -> (), layoutOrder: number?): Frame
	local parentZ = if parent:IsA("GuiObject") then parent.ZIndex else 12
	local bar = UI.new("Frame", {
		Name = "VikingTabBar",
		Size = UDim2.new(1, 0, 0, 44),
		BackgroundColor3 = Color3.fromRGB(24, 22, 24),
		LayoutOrder = layoutOrder or 1,
		ZIndex = parentZ + 1,
		Parent = parent,
	})
	UI.corner(bar, 7)
	UI.stroke(bar, UI.Colors.IronMid, 1.4)
	UI.padding(bar, 4, 4, 4, 4)

	local layout = UI.list(bar, 6, true)
	layout.VerticalAlignment = Enum.VerticalAlignment.Center

	local n = math.max(1, #tabs)
	for idx, name in tabs do
		local active = name == activeTab
		local btn = UI.new("TextButton", {
			Name = "Tab_" .. name,
			Size = UDim2.new(1 / n, -math.ceil((n - 1) * 6 / n), 1, 0),
			BackgroundColor3 = if active then Color3.fromRGB(242, 194, 96) else Color3.fromRGB(72, 56, 44),
			Text = name,
			Font = UI.FontDisplay,
			TextSize = 15,
			TextColor3 = if active then Color3.fromRGB(32, 18, 8) else Color3.fromRGB(238, 220, 186),
			AutoButtonColor = false,
			LayoutOrder = idx,
			ZIndex = parentZ + 2,
			Parent = bar,
		})
		UI.corner(btn, 6)
		if active then
			UI.gradient(btn, Color3.fromRGB(255, 248, 220), Color3.fromRGB(196, 146, 78), 90)
			UI.stroke(btn, Color3.fromRGB(255, 228, 132), 2.0)
		else
			UI.gradient(btn, Color3.fromRGB(236, 220, 204), Color3.fromRGB(140, 120, 108), 90)
			UI.stroke(btn, UI.Colors.IronMid, 1.3)
		end
		UI.rivets(btn, if active then Color3.fromRGB(148, 96, 28) else UI.Colors.Rivet, 4, parentZ + 3, 5)
		btn.Activated:Connect(function()
			onSelect(name)
		end)
	end
	return bar
end

function UI.clear(container: Instance)
	for _, child in container:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

function UI.tween(inst: Instance, seconds: number, goal: { [string]: any }, style: Enum.EasingStyle?)
	local tween = TweenService:Create(inst, TweenInfo.new(seconds, style or Enum.EasingStyle.Quad, Enum.EasingDirection.Out), goal)
	tween:Play()
	return tween
end

-- Viking Great-Hall Modal Sheets (built directly from shop.jpeg) --------------

local openSheet: any = nil

export type Sheet = {
	Frame: Frame,
	Body: ScrollingFrame,
	Footer: Frame,
	Title: TextLabel,
	Open: () -> (),
	Close: () -> (),
	IsOpen: () -> boolean,
	OnOpen: BindableEvent,
}

function UI.IsAnySheetOpen(): boolean
	return openSheet ~= nil and openSheet.IsOpen()
end

-- Circular riveted iron & dark-wood shield close button with crossed bone bars (shop.jpeg)
local function buildCrossedBonesClose(parent: Instance, onClose: () -> (), zIndex: number): TextButton
	local btn = UI.new("TextButton", {
		Name = "CloseShield",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(1, -6, 0, 8),
		Size = UDim2.fromOffset(46, 46),
		BackgroundColor3 = UI.Colors.IronOuter,
		Text = "",
		AutoButtonColor = false,
		ZIndex = zIndex,
		Parent = parent,
	})
	UI.corner(btn, 23)
	UI.gradient(btn, Color3.fromRGB(230, 234, 244), Color3.fromRGB(118, 122, 132), 90)
	local rimStroke = UI.stroke(btn, UI.Colors.WoodDark, 2)

	local disc = UI.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(34, 34),
		BackgroundColor3 = Color3.fromRGB(64, 42, 28),
		ZIndex = zIndex + 1,
		Parent = btn,
	})
	UI.corner(disc, 17)
	UI.stroke(disc, UI.Colors.IronMid, 1.4)

	-- 6 tiny shield rim rivets
	for i = 1, 6 do
		local a = (math.pi * 2 / 6) * i
		UI.roundRivet(btn, UDim2.new(0.5, math.cos(a) * 19, 0.5, math.sin(a) * 19), 4, zIndex + 2)
	end

	-- Crossed carved ivory bone X in center
	local boneColor = Color3.fromRGB(240, 230, 208)
	for _, angle in { 45, -45 } do
		local bone = UI.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(22, 5),
			Rotation = angle,
			BackgroundColor3 = boneColor,
			ZIndex = zIndex + 3,
			Parent = disc,
		})
		UI.corner(bone, 3)
		UI.stroke(bone, UI.Colors.WoodDark, 1)
		for _, endX in { 0, 1 } do
			for _, endY in { -2, 2 } do
				local knob = UI.new("Frame", {
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.new(endX, 0, 0.5, endY),
					Size = UDim2.fromOffset(5, 5),
					BackgroundColor3 = boneColor,
					ZIndex = zIndex + 3,
					Parent = bone,
				})
				UI.corner(knob, 3)
			end
		end
	end

	local scale = UI.new("UIScale", { Scale = 1, Parent = btn })
	btn.MouseEnter:Connect(function()
		UI.tween(scale, 0.1, { Scale = 1.08 })
		rimStroke.Color = UI.Colors.Gold
	end)
	btn.MouseLeave:Connect(function()
		UI.tween(scale, 0.1, { Scale = 1 })
		rimStroke.Color = UI.Colors.WoodDark
	end)
	btn.MouseButton1Down:Connect(function()
		UI.tween(scale, 0.06, { Scale = 0.92 })
	end)
	btn.MouseButton1Up:Connect(function()
		UI.tween(scale, 0.1, { Scale = 1 })
	end)
	btn.Activated:Connect(onClose)
	return btn
end

function UI.sheet(screen: ScreenGui, title: string, footerHeight: number?, iconKind: string?): Sheet
	local footerH = footerHeight or 0

	-- Positioned cleanly in the Great-Hall window band between the top currency
	-- plaque (connected by two hanging chains!) and the bottom 6-arch dock!
	local frame = UI.new("Frame", {
		Name = title .. "Sheet",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 74),
		Size = UDim2.new(0.92, 0, 1, -208),
		BackgroundColor3 = UI.Colors.IronOuter,
		Visible = false,
		ZIndex = 12,
		Parent = screen,
	})
	UI.new("UISizeConstraint", { MinSize = Vector2.new(320, 270), MaxSize = Vector2.new(660, 660), Parent = frame })
	UI.corner(frame, 10)
	UI.gradient(frame, Color3.fromRGB(224, 228, 238), Color3.fromRGB(118, 122, 132), 90)
	UI.stroke(frame, UI.Colors.WoodDark, 2.2)
	UI.perimeterRivets(frame, 8, 5, 17, 6, 5)

	-- Twin hanging iron chains rising from top of modal frame to top currency plaque (shop.jpeg)
	UI.hangingChain(frame, UDim2.fromScale(0.28, 0), -20, 24, 11)
	UI.hangingChain(frame, UDim2.fromScale(0.72, 0), -20, 24, 11)

	-- Top-left sculpted Norse Dragon-Head Longship Figurehead finial (shop.jpeg)
	local prowHolder = UI.new("Frame", {
		Name = "DragonProwFinial",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(4, 10),
		Size = UDim2.fromOffset(66, 66),
		BackgroundTransparency = 1,
		ZIndex = 19,
		Parent = frame,
	})
	VikingModels.ViewportIcon(prowHolder, "DragonProw", UDim2.fromScale(1, 1), 0, 20, 0)

	-- Recessed dark obsidian/slate stone interior well (shop.jpeg)
	local innerWell = UI.new("Frame", {
		Name = "ObsidianWell",
		Position = UDim2.fromOffset(10, 10),
		Size = UDim2.new(1, -20, 1, -20),
		BackgroundColor3 = UI.Colors.Panel2,
		ClipsDescendants = true,
		ZIndex = 13,
		Parent = frame,
	})
	UI.corner(innerWell, 6)
	UI.stroke(innerWell, UI.Colors.WoodDark, 1.8)

	-- Subtle carved Norse knotwork side trim rails inside the well
	for _, side in { 0, 1 } do
		local pillar = UI.new("Frame", {
			AnchorPoint = Vector2.new(side, 0),
			Position = UDim2.new(side, 0, 0, 62),
			Size = UDim2.new(0, 8, 1, -62),
			BackgroundColor3 = Color3.fromRGB(44, 45, 50),
			BackgroundTransparency = 0.25,
			ZIndex = 13,
			Parent = innerWell,
		})
		UI.stroke(pillar, UI.Colors.WoodDark, 1)
	end

	-- Horizontal weathered oak timber Header Banner (shop.jpeg)
	local header = UI.new("Frame", {
		Name = "Header",
		Size = UDim2.new(1, 0, 0, 60),
		BackgroundColor3 = UI.Colors.Panel,
		ZIndex = 14,
		Parent = innerWell,
	})
	UI.woodPlanks(header, 3, 14, 4)

	-- Forged iron crossbeam divider directly beneath header
	local beam = UI.new("Frame", {
		Name = "HeaderIronBeam",
		Position = UDim2.fromOffset(0, 58),
		Size = UDim2.new(1, 0, 0, 5),
		BackgroundColor3 = UI.Colors.IronOuter,
		ZIndex = 16,
		Parent = innerWell,
	})
	UI.stroke(beam, UI.Colors.WoodDark, 1)

	-- Carved header emblem on the left (MerchantStall for Merchant Hall, matching shop.jpeg!)
	local resolvedIcon = if iconKind == "Shop" then "MerchantStall" else iconKind
	if resolvedIcon then
		local crest = UI.new("Frame", {
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 14, 0.5, 0),
			Size = UDim2.fromOffset(46, 46),
			BackgroundColor3 = ICON_BG[resolvedIcon] or UI.Colors.WoodDark,
			ZIndex = 16,
			Parent = header,
		})
		UI.corner(crest, 9)
		UI.stroke(crest, UI.Colors.Stroke, 1.6)
		VikingModels.ViewportIcon(crest, resolvedIcon, UDim2.fromScale(1.18, 1.18), 0.45, 17).Position = UDim2.fromScale(-0.09, -0.09)
	end

	UI.knotMedallion(header, UDim2.new(1, -46, 0.5, 0), Vector2.new(0.5, 0.5), 22, 15)

	-- Centered chiseled golden serif header title (matching "Merchant Hall" in shop.jpeg)
	local titleLabel = UI.label(header, "<b>" .. title .. "</b>", 25, {
		Font = UI.FontDisplay,
		Position = UDim2.fromOffset(64, 6),
		Size = UDim2.new(1, -128, 1, -12),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = UI.Colors.Gold,
		TextStrokeColor3 = UI.Colors.WoodDark,
		TextStrokeTransparency = 0.18,
		ZIndex = 16,
		Parent = header,
	})
	UI.gradient(titleLabel, Color3.fromRGB(255, 242, 168), Color3.fromRGB(218, 148, 48), 90)

	local sheet: any = { Frame = frame, Title = titleLabel, OnOpen = Instance.new("BindableEvent") }
	buildCrossedBonesClose(frame, function()
		sheet.Close()
	end, 20)

	local footerReserve = if footerH > 0 then (footerH + 14) else 0
	local body = UI.new("ScrollingFrame", {
		Name = "Body",
		Position = UDim2.fromOffset(12, 68),
		Size = UDim2.new(1, -24, 1, -(74 + footerReserve)),
		BackgroundTransparency = 1,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = UI.Colors.Stroke,
		AutomaticCanvasSize = Enum.AutomaticSize.None,
		CanvasSize = UDim2.new(),
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ZIndex = 14,
		Parent = innerWell,
	})
	local bodyLayout = UI.list(body, 8)
	UI.new("UIPadding", { PaddingTop = UDim.new(0, 2), PaddingRight = UDim.new(0, 8), PaddingBottom = UDim.new(0, 12), PaddingLeft = UDim.new(0, 2), Parent = body })

	local function syncCanvas()
		body.CanvasSize = UDim2.fromOffset(0, bodyLayout.AbsoluteContentSize.Y + 18)
	end
	bodyLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(syncCanvas)
	body.ChildAdded:Connect(function()
		task.defer(syncCanvas)
	end)

	local footer = UI.new("Frame", {
		Name = "Footer",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 14, 1, -8),
		Size = UDim2.new(1, -28, 0, footerH),
		BackgroundTransparency = 1,
		Visible = footerH > 0,
		ZIndex = 15,
		Parent = innerWell,
	})
	if footerH > 0 then
		UI.new("Frame", {
			Position = UDim2.new(0, 0, 1, -(footerH + 12)),
			Size = UDim2.new(1, 0, 0, 3),
			BackgroundColor3 = UI.Colors.IronOuter,
			ZIndex = 15,
			Parent = innerWell,
		})
	end

	sheet.Body = body
	sheet.Footer = footer
	function sheet.IsOpen()
		return frame.Visible
	end
	function sheet.Close()
		local wasOpen = frame.Visible
		frame.Visible = false
		if openSheet == sheet then
			openSheet = nil
		end
		if wasOpen then
			UI.SheetChanged:Fire(false)
		end
	end
	function sheet.Open()
		if openSheet and openSheet ~= sheet then
			openSheet.Frame.Visible = false
		end
		openSheet = sheet
		frame.Visible = true
		frame.Position = UDim2.new(0.5, 0, 0, 88)
		UI.tween(frame, 0.2, { Position = UDim2.new(0.5, 0, 0, 74) }, Enum.EasingStyle.Back)
		sheet.OnOpen:Fire()
		UI.SheetChanged:Fire(true)
		task.defer(syncCanvas)
	end
	return sheet :: Sheet
end

function UI.CloseAllSheets()
	if openSheet then
		openSheet.Close()
	end
end

function UI.dot(parent: Instance, color: Color3, size: number?): Frame
	local s = size or 12
	local parentZ = if parent:IsA("GuiObject") then parent.ZIndex else 1
	local dot = UI.new("Frame", { Size = UDim2.fromOffset(s, s), BackgroundColor3 = color, ZIndex = parentZ + 1, Parent = parent })
	UI.corner(dot, s)
	UI.stroke(dot, UI.Colors.WoodDark, 1)
	return dot
end

function UI.row(parent: Instance, height: number, gap: number?): Frame
	local parentZ = if parent:IsA("GuiObject") then parent.ZIndex else 1
	local row = UI.new("Frame", { Size = UDim2.new(1, 0, 0, height), BackgroundTransparency = 1, ZIndex = parentZ + 1, Parent = parent })
	local layout = UI.list(row, gap or 8, true)
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	return row
end

function UI.card(parent: Instance, props: { [string]: any }?): Frame
	local parentZ = if parent:IsA("GuiObject") then parent.ZIndex else 1
	local p = {
		Size = UDim2.new(1, 0, 0, 44),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = UI.Colors.Panel3,
		ZIndex = parentZ + 1,
		Parent = parent,
	}
	if props then
		for k, v in props do
			p[k] = v
		end
	end
	local card = UI.new("Frame", p)
	UI.corner(card, 8)
	UI.gradient(card, Color3.fromRGB(250, 238, 222), Color3.fromRGB(168, 150, 138), 90)
	UI.stroke(card, UI.Colors.IronMid, 1.4)
	UI.padding(card, 10)
	return card
end

return UI
