-- ReplicatedStorage/Shared/DragonAnimation
-- Procedural dragon motion. A dragon model has Motor6Ds on its Root named
-- Body, Head, Tail, LeftWing, RightWing and (when the model has them)
-- LeftLeg, RightLeg. This module turns a movement state into joint transforms;
-- DragonAnimator applies them every frame on each player's device.
--
-- Joint axes are the dragon's own: -Z forward, +Y up, +X right.
--   Wing flap  = roll around the forward axis (left wing negative = up)
--   Wing fold  = sweep back around Y, plus a droop
--   Leg swing  = pitch around X (negative = foot forward)
-- Translations are in studs for a 36-stud dragon and scale with model size.

local DragonAnimation = {}

export type Params = {
	FlapAmp: number, -- radians, half the wing stroke
	FlapRate: number, -- strokes per second
	WingLift: number, -- radians, resting wing height (+ up)
	WingFold: number, -- 0 = spread, 1 = folded against the body
	Flutter: number, -- small fast membrane tremble (gliding)
	TailSway: number, -- radians
	TailRate: number,
	HeadBob: number, -- radians
	Breath: number, -- studs of chest rise
	Stride: number, -- 0..1 how much the legs and wing-wrists walk
	LegTuck: number, -- 0 standing, 1 tucked up in flight, negative = reaching down (landing)
	BodyPitch: number, -- radians (+ nose up)
}

DragonAnimation.States = {
	-- On the ground
	Idle = { FlapAmp = 0, FlapRate = 0.3, WingLift = 0.02, WingFold = 1, Flutter = 0, TailSway = 0.14, TailRate = 0.22, HeadBob = 0.06, Breath = 0.35, Stride = 0, LegTuck = 0, BodyPitch = 0 },
	Walk = { FlapAmp = 0, FlapRate = 0.3, WingLift = 0.04, WingFold = 0.92, Flutter = 0, TailSway = 0.2, TailRate = 0.5, HeadBob = 0.05, Breath = 0.2, Stride = 1, LegTuck = 0, BodyPitch = 0.02 },
	-- In the air
	Takeoff = { FlapAmp = 1.05, FlapRate = 1.45, WingLift = 0.22, WingFold = 0, Flutter = 0, TailSway = 0.08, TailRate = 0.6, HeadBob = 0.1, Breath = 0, Stride = 0, LegTuck = 0.35, BodyPitch = 0.22 },
	Hover = { FlapAmp = 0.95, FlapRate = 1.25, WingLift = 0.18, WingFold = 0, Flutter = 0, TailSway = 0.12, TailRate = 0.45, HeadBob = 0.08, Breath = 0, Stride = 0, LegTuck = 0.2, BodyPitch = 0.18 },
	Fly = { FlapAmp = 0.72, FlapRate = 0.85, WingLift = 0.1, WingFold = 0, Flutter = 0, TailSway = 0.07, TailRate = 0.35, HeadBob = 0.05, Breath = 0, Stride = 0, LegTuck = 1, BodyPitch = 0 },
	Glide = { FlapAmp = 0.03, FlapRate = 0.5, WingLift = 0.06, WingFold = 0, Flutter = 1, TailSway = 0.05, TailRate = 0.3, HeadBob = 0.02, Breath = 0, Stride = 0, LegTuck = 1, BodyPitch = -0.02 },
	Dive = { FlapAmp = 0.02, FlapRate = 0.5, WingLift = -0.05, WingFold = 0.45, Flutter = 1.4, TailSway = 0.03, TailRate = 0.3, HeadBob = 0.01, Breath = 0, Stride = 0, LegTuck = 1, BodyPitch = -0.1 },
	Land = { FlapAmp = 0.55, FlapRate = 0.9, WingLift = 0.38, WingFold = 0, Flutter = 0.4, TailSway = 0.1, TailRate = 0.5, HeadBob = 0.05, Breath = 0, Stride = 0, LegTuck = -0.45, BodyPitch = 0.32 },
	-- Idle actions (short one-offs on top of Idle)
	Stretch = { FlapAmp = 0.45, FlapRate = 0.6, WingLift = 0.35, WingFold = 0.05, Flutter = 0.3, TailSway = 0.25, TailRate = 0.4, HeadBob = 0.12, Breath = 0.4, Stride = 0, LegTuck = 0, BodyPitch = 0.08 },
} :: { [string]: Params }

-- Moves current params toward the target a little each frame (smooth state changes).
function DragonAnimation.Blend(current: Params, target: Params, dt: number, speed: number?): Params
	local alpha = 1 - math.exp(-(speed or 4) * dt)
	local out = {}
	for key, value in target do
		local from = (current :: any)[key] or value
		out[key] = from + (value - from) * alpha
	end
	return out :: any
end

-- t: seconds. flap: running wingbeat phase. stride: running step phase.
-- turn: -1..1 (left/right turning). size: model length / 36 (scales offsets).
function DragonAnimation.Pose(p: Params, t: number, flap: number, stride: number, turn: number, size: number)
	-- Wingbeat: powerful downstroke, slower recovery (sin + 2nd harmonic).
	local stroke = math.sin(flap) + 0.28 * math.sin(2 * flap)
	local flutter = p.Flutter * 0.025 * math.sin(t * 19) + p.Flutter * 0.015 * math.sin(t * 31)
	local lift = p.WingLift + p.FlapAmp * stroke + flutter
	local fold = p.WingFold
	local sweep = 1.1 * fold
	local droop = 0.5 * fold

	-- Walking: wings fold into front "legs" that step opposite the hind legs.
	local stepL = math.sin(stride)
	local stepR = math.sin(stride + math.pi)
	local wingStepL = p.Stride * 0.22 * stepR
	local wingStepR = p.Stride * 0.22 * stepL
	local wingLiftL = p.Stride * 0.12 * math.max(0, math.cos(stride + math.pi))
	local wingLiftR = p.Stride * 0.12 * math.max(0, math.cos(stride))

	local left = CFrame.Angles(0, sweep + wingStepL, 0) * CFrame.Angles(0, 0, -(lift - droop + wingLiftL))
	local right = CFrame.Angles(0, -sweep - wingStepR, 0) * CFrame.Angles(0, 0, lift - droop + wingLiftR)

	-- Body: breathing, rising on each wing downstroke, dipping between steps.
	local breath = p.Breath * math.sin(t * 2 * math.pi * 0.3)
	local beat = -0.55 * p.FlapAmp * math.cos(flap)
	local stepBob = p.Stride * 0.35 * (math.abs(math.sin(stride)) - 0.5)
	local sway = p.Stride * 0.035 * math.sin(stride)
	local body = CFrame.new(0, (breath + beat + stepBob) * size, 0)
		* CFrame.Angles(p.BodyPitch + 0.03 * p.FlapAmp * math.sin(flap), 0, sway)

	-- Head: steadied against the body's motion, looks around when calm, leans into turns.
	local calm = (1 - math.min(1, p.FlapAmp)) * (1 - p.Stride * 0.5)
	local lookYaw = calm * (0.22 * math.sin(t * 0.31) + 0.12 * math.sin(t * 0.83))
	local lookPitch = calm * 0.08 * math.sin(t * 0.47)
	local head = CFrame.Angles(
		-p.BodyPitch * 0.6 + p.HeadBob * math.sin(t * 2 * math.pi * 0.45) - 0.08 * p.FlapAmp * math.sin(flap) + lookPitch - p.Stride * 0.04 * math.sin(2 * stride),
		lookYaw + 0.4 * turn + p.Stride * 0.05 * math.sin(stride),
		0
	)

	-- Tail: travelling S-wave (phase lag), trails behind turns, lifts in a dive.
	local tail = CFrame.Angles(
		0.06 * math.sin(t * 1.1) - p.BodyPitch * 0.5 + p.Stride * 0.04 * math.sin(2 * stride - 1),
		p.TailSway * math.sin(t * 2 * math.pi * p.TailRate - 1.2) + 0.45 * turn + p.Stride * 0.16 * math.sin(stride - 1.4),
		0
	)

	-- Legs: stride (negative = forward), tucked back in flight, reaching down to land.
	local legSwing = 0.5 * p.Stride
	local tuck = 1.05 * p.LegTuck
	local leftLeg = CFrame.Angles(-legSwing * stepL + tuck, 0, 0)
	local rightLeg = CFrame.Angles(-legSwing * stepR + tuck, 0, 0)

	return {
		Body = body,
		Head = head,
		Tail = tail,
		LeftWing = left,
		RightWing = right,
		LeftLeg = leftLeg,
		RightLeg = rightLeg,
	}
end

-- Occasional idle actions so resting dragons never look frozen.
DragonAnimation.IdleActions = {
	{ Name = "Stretch", Duration = 2.6 },
}

return DragonAnimation
