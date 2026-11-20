-- ReplicatedStorage/Client/UI
-- Shared look and building blocks for all Dragon Tycoon screens.
-- Style: stylized fantasy. Dark slate panels, warm gold accents, rounded
-- corners, readable on phones (44px+ touch targets).

local TweenService = game:GetService("TweenService")

local UI = {}

UI.Colors = {
	Panel = Color3.fromRGB(26, 28, 36),
	Panel2 = Color3.fromRGB(38, 41, 52),
	Panel3 = Color3.fromRGB(52, 56, 70),
	Stroke = Color3.fromRGB(120, 98, 62),
	Text = Color3.fromRGB(242, 236, 224),
	Muted = Color3.fromRGB(168, 162, 150),
	Gold = Color3.fromRGB(242, 192, 92),
	Good = Color3.fromRGB(96, 200, 124),
	Bad = Color3.fromRGB(232, 96, 84),
	Button = Color3.fromRGB(220, 164, 72),
	ButtonText = Color3.fromRGB(34, 26, 14),
	Secondary = Color3.fromRGB(64, 70, 88),
	Disabled = Color3.fromRGB(70, 72, 80),
}

UI.Font = Enum.Font.GothamMedium
UI.FontBold = Enum.Font.GothamBold

-- Creates an instance: UI.new("Frame", { Size = ..., Parent = ... })
function UI.new(className: string, props: { [string]: any }?): any
	local inst = Instance.new(className)
	local parent = nil
	for key, value in props or {} do
		if key == "Parent" then
			parent = value
		else
			(inst :: any)[key] = value
		end
	end
	if inst:IsA("GuiObject") and (props == nil or props.BorderSizePixel == nil) then
		(inst :: any).BorderSizePixel = 0
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

function UI.corner(inst: Instance, radius: number?)
	UI.new("UICorner", { CornerRadius = UDim.new(0, radius or 12), Parent = inst })
end

function UI.stroke(inst: Instance, color: Color3?, thickness: number?)
	return UI.new("UIStroke", {
		Color = color or UI.Colors.Stroke,
		Thickness = thickness or 1.5,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = inst,
	})
end

function UI.padding(inst: Instance, px: number)
	UI.new("UIPadding", {
		PaddingTop = UDim.new(0, px),
		PaddingBottom = UDim.new(0, px),
		PaddingLeft = UDim.new(0, px),
		PaddingRight = UDim.new(0, px),
		Parent = inst,
	})
end

function UI.list(inst: Instance, gap: number?, horizontal: boolean?)
	return UI.new("UIListLayout", {
		Padding = UDim.new(0, gap or 8),
		FillDirection = if horizontal then Enum.FillDirection.Horizontal else Enum.FillDirection.Vertical,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = inst,
	})
end

function UI.label(parent: Instance, text: string, size: number?, props: { [string]: any }?): TextLabel
	local p = {
		BackgroundTransparency = 1,
		Font = UI.Font,
		Text = text,
		TextSize = size or 16,
		TextColor3 = UI.Colors.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = true,
		RichText = true,
		Size = UDim2.new(1, 0, 0, (size or 16) + 6),
		Parent = parent,
	}
	for k, v in props or {} do
		p[k] = v
	end
	return UI.new("TextLabel", p)
end

-- A rounded button. Returns the button and a setEnabled(bool, text?) function.
function UI.button(parent: Instance, text: string, onClick: () -> (), props: { [string]: any }?): (TextButton, (boolean, string?) -> ())
	local p = {
		BackgroundColor3 = UI.Colors.Button,
		TextColor3 = UI.Colors.ButtonText,
		Font = UI.FontBold,
		Text = text,
		TextSize = 16,
		AutoButtonColor = true,
		Size = UDim2.new(1, 0, 0, 44),
		Parent = parent,
	}
	for k, v in props or {} do
		p[k] = v
	end
	local button: TextButton = UI.new("TextButton", p)
	UI.corner(button, 10)
	local baseColor = button.BackgroundColor3
	local enabled = true
	button.Activated:Connect(function()
		if enabled then
			onClick()
		end
	end)
	local function setEnabled(on: boolean, newText: string?)
		enabled = on
		button.BackgroundColor3 = if on then baseColor else UI.Colors.Disabled
		button.TextColor3 = if on then (p.TextColor3 :: Color3) else UI.Colors.Muted
		button.AutoButtonColor = on
		if newText then
			button.Text = newText
		end
	end
	return button, setEnabled
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

-- Bottom sheets ------------------------------------------------------------------
-- Only one sheet is open at a time.

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

-- footerHeight: fixed area under the scrolling body (0 for none).
function UI.sheet(screen: ScreenGui, title: string, footerHeight: number?): Sheet
	local footerH = footerHeight or 0
	local frame = UI.new("Frame", {
		Name = title .. "Sheet",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -84),
		Size = UDim2.new(0.96, 0, 0.66, 0),
		BackgroundColor3 = UI.Colors.Panel,
		Visible = false,
		ZIndex = 5,
		Parent = screen,
	})
	UI.corner(frame, 16)
	UI.stroke(frame)
	UI.new("UISizeConstraint", { MaxSize = Vector2.new(560, 680), Parent = frame })

	local titleLabel = UI.label(frame, "<b>" .. title .. "</b>", 20, {
		Position = UDim2.fromOffset(16, 10),
		Size = UDim2.new(1, -80, 0, 30),
		TextColor3 = UI.Colors.Gold,
		Font = UI.FontBold,
		ZIndex = 6,
	})

	local sheet: any = { Frame = frame, Title = titleLabel, OnOpen = Instance.new("BindableEvent") }

	UI.button(frame, "X", function()
		sheet.Close()
	end, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -10, 0, 8),
		Size = UDim2.fromOffset(44, 36),
		BackgroundColor3 = UI.Colors.Secondary,
		TextColor3 = UI.Colors.Text,
		ZIndex = 6,
	})

	local body = UI.new("ScrollingFrame", {
		Name = "Body",
		Position = UDim2.fromOffset(12, 52),
		Size = UDim2.new(1, -24, 1, -(60 + footerH + (if footerH > 0 then 10 else 0))),
		BackgroundTransparency = 1,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = UI.Colors.Stroke,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ZIndex = 6,
		Parent = frame,
	})
	UI.list(body, 8)
	UI.new("UIPadding", { PaddingRight = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8), Parent = body })

	local footer = UI.new("Frame", {
		Name = "Footer",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 12, 1, -10),
		Size = UDim2.new(1, -24, 0, footerH),
		BackgroundTransparency = 1,
		Visible = footerH > 0,
		ZIndex = 6,
		Parent = frame,
	})

	sheet.Body = body
	sheet.Footer = footer
	function sheet.IsOpen()
		return frame.Visible
	end
	function sheet.Close()
		frame.Visible = false
		if openSheet == sheet then
			openSheet = nil
		end
	end
	function sheet.Open()
		if openSheet and openSheet ~= sheet then
			openSheet.Close()
		end
		openSheet = sheet
		frame.Visible = true
		frame.Position = UDim2.new(0.5, 0, 1, -60)
		UI.tween(frame, 0.18, { Position = UDim2.new(0.5, 0, 1, -84) })
		sheet.OnOpen:Fire()
	end
	return sheet :: Sheet
end

function UI.CloseAllSheets()
	if openSheet then
		openSheet.Close()
	end
end

-- A colored dot (element or rarity marker).
function UI.dot(parent: Instance, color: Color3, size: number?): Frame
	local s = size or 12
	local dot = UI.new("Frame", { Size = UDim2.fromOffset(s, s), BackgroundColor3 = color, Parent = parent })
	UI.corner(dot, s)
	return dot
end

-- A horizontal row container with a list layout.
function UI.row(parent: Instance, height: number, gap: number?): Frame
	local row = UI.new("Frame", { Size = UDim2.new(1, 0, 0, height), BackgroundTransparency = 1, Parent = parent })
	local layout = UI.list(row, gap or 8, true)
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	return row
end

-- A rounded card container that grows with its content.
function UI.card(parent: Instance, props: { [string]: any }?): Frame
	local p = {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = UI.Colors.Panel2,
		Parent = parent,
	}
	for k, v in props or {} do
		p[k] = v
	end
	local card = UI.new("Frame", p)
	UI.corner(card, 12)
	UI.padding(card, 10)
	return card
end

return UI
