--!strict
-- ReplicatedStorage/Shared/DragonAnimation
-- Procedural dragon motion: turns a movement state into Motor6D transforms.
-- DragonMotionController (client) applies them every frame on each device.
--
-- Skeletons (joints are Motor6Ds on Root, named after their part):
--   Classic:  Body, Head, Tail, LeftWing, RightWing (+ LeftLeg, RightLeg)
--   Western:  Body [> Chest] > Neck > Neck2.. > Head [> Jaw]
--             Body > Tail1 > Tail2 > .. TailN
--             [Chest|Body] > LeftWing > LeftWingTip [> LeftWingMembrane]   (and Right)
--             [Chest|Body] > FrontLeftLeg [> FrontLeftLegLower > FrontLeftFoot] (and Right)
--             Body > HindLeftLeg [> HindLeftLegLower > HindLeftFoot]          (and Right)
-- Parts in [brackets] are optional; poses use whatever the model has.
--
-- Joint axes are the dragon's own: -Z forward, +Y up, +X right.
--   Pitch (+X) = nose/foot up or forward      Yaw (+Y) = turn left
--   Roll (+Z)  = left side down                Translations scale with `size`.
--
-- Layers, from bottom to top:
--   1. State params (Idle, Walk, Run, Takeoff, Hover, Fly, Glide, Dive, Land),
--      blended over time so changes never pop.
--   2. Secondary motion from the dragon's real movement (Motion): banking into
--      turns, the head leading and the tail dragging behind, pitch with climb.
--   3. Keyframed clips (Clips) such as Roar, Breath, Pet, TailWhip, Launch,
--      with a priority and a joint mask so an upper-body action plays over any
--      movement.

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
	Stride: number, -- 0..1 how much the legs walk
	Gallop: number, -- 0 = trot (diagonal pairs), 1 = gallop (front pair, hind pair)
	LegTuck: number, -- 0 standing, 1 tucked up in flight, negative = reaching down (landing)
	HindDangle: number, -- 0..1 hind legs hang loose (hovering)
	BodyPitch: number, -- radians (+ nose up)
	NeckReach: number, -- 0..1 neck stretched forward (speed)
}

-- Secondary-motion inputs, measured from the dragon by the controller.
export type Motion = {
	Turn: number, -- -1..1, + = turning left (yaw rate)
	TailTurn: { number }, -- the same turn, delayed further for each tail segment
	Climb: number, -- -1..1, + = climbing, - = diving
	Necks: number, -- neck segments in the model (Neck, Neck2, ..)
	Tails: number, -- tail segments (Tail1..TailN)
	Airborne: number, -- 0 on the ground .. 1 flying (blends the banking in)
}

-- TUNING: every state starts from these, then overrides what it needs.
local DEFAULTS: Params = {
	FlapAmp = 0, FlapRate = 0.3, WingLift = 0, WingFold = 0, Flutter = 0,
	TailSway = 0.1, TailRate = 0.3, HeadBob = 0.05, Breath = 0,
	Stride = 0, Gallop = 0, LegTuck = 0, HindDangle = 0, BodyPitch = 0, NeckReach = 0,
}

local function state(overrides: { [string]: number }): Params
	local p = table.clone(DEFAULTS) :: any
	for key, value in overrides do
		p[key] = value
	end
	return p
end

DragonAnimation.States = {
	-- On the ground
	Idle = state({ WingLift = 0.02, WingFold = 1, TailSway = 0.14, TailRate = 0.22, HeadBob = 0.06, Breath = 0.35 }),
	Walk = state({ WingLift = 0.04, WingFold = 0.92, TailSway = 0.2, TailRate = 0.5, Breath = 0.2, Stride = 1, BodyPitch = 0.02 }),
	Run = state({ WingLift = 0.08, WingFold = 0.85, TailSway = 0.16, TailRate = 0.9, HeadBob = 0.04, Breath = 0.1, Stride = 1, Gallop = 1, BodyPitch = 0.03, NeckReach = 0.45 }),
	-- In the air
	Takeoff = state({ FlapAmp = 1.05, FlapRate = 1.45, WingLift = 0.22, TailSway = 0.08, TailRate = 0.6, HeadBob = 0.1, LegTuck = 0.35, BodyPitch = 0.22 }),
	Hover = state({ FlapAmp = 0.95, FlapRate = 1.25, WingLift = 0.18, TailSway = 0.12, TailRate = 0.45, HeadBob = 0.08, LegTuck = 0.35, HindDangle = 1, BodyPitch = 0.18 }),
	Fly = state({ FlapAmp = 0.72, FlapRate = 0.85, WingLift = 0.1, TailSway = 0.07, TailRate = 0.35, LegTuck = 1, NeckReach = 0.5 }),
	Glide = state({ FlapAmp = 0.03, FlapRate = 0.5, WingLift = 0.06, Flutter = 1, TailSway = 0.05, TailRate = 0.3, HeadBob = 0.02, LegTuck = 1, BodyPitch = -0.02, NeckReach = 1 }),
	Dive = state({ FlapAmp = 0.02, FlapRate = 0.5, WingLift = -0.05, WingFold = 0.45, Flutter = 1.4, TailSway = 0.03, TailRate = 0.3, HeadBob = 0.01, LegTuck = 1, BodyPitch = -0.1, NeckReach = 1 }),
	Land = state({ FlapAmp = 0.55, FlapRate = 0.9, WingLift = 0.38, Flutter = 0.4, TailSway = 0.1, TailRate = 0.5, LegTuck = -0.45, BodyPitch = 0.32 }),
	-- Idle actions (short one-offs on top of Idle)
	Stretch = state({ FlapAmp = 0.45, FlapRate = 0.6, WingLift = 0.35, WingFold = 0.05, Flutter = 0.3, TailSway = 0.25, TailRate = 0.4, HeadBob = 0.12, Breath = 0.4, BodyPitch = 0.08 }),
} :: { [string]: Params }

DragonAnimation.GroundStates = { Idle = true, Walk = true, Run = true, Stretch = true }

-- Moves current params toward the target a little each frame (smooth state changes).
function DragonAnimation.Blend(current: Params, target: Params, dt: number, speed: number?): Params
	local alpha = 1 - math.exp(-(speed or 4) * dt)
	local out = {}
	for key, value in target :: any do
		local from = (current :: any)[key] or value
		out[key] = from + (value - from) * alpha
	end
	return out :: any
end

-- Western wing fold targets (joint frame). The rest pose is a spread wing whose
-- membrane trails behind the arm.
local ARM_BACK_RIGHT = CFrame.fromMatrix(Vector3.zero, Vector3.new(0, 0, 1), Vector3.new(-1, 0, 0), Vector3.new(0, -1, 0))
local ARM_BACK_LEFT = CFrame.fromMatrix(Vector3.zero, Vector3.new(0, 0, -1), Vector3.new(1, 0, 0), Vector3.new(0, -1, 0))
-- TUNING: arm back and slightly out, membrane rolled out so it drapes along the flank
local FOLD_RIGHT = CFrame.Angles(0, 0.22, 0) * CFrame.Angles(0.06, 0, 0) * CFrame.Angles(0, 0, 0.85) * ARM_BACK_RIGHT
local FOLD_LEFT = CFrame.Angles(0, -0.22, 0) * CFrame.Angles(0.06, 0, 0) * CFrame.Angles(0, 0, -0.85) * ARM_BACK_LEFT
local TIP_FOLD_RIGHT = CFrame.Angles(0, -2.73, 0) * CFrame.Angles(-0.6, 0, 0) -- hand forward, fingers down
local TIP_FOLD_LEFT = CFrame.Angles(0, 2.73, 0) * CFrame.Angles(-0.6, 0, 0)

-- TUNING: secondary motion strength
local BANK_ROLL = 0.14 -- extra body roll into a turn (the flight physics already banks the whole dragon)
local BANK_WING = 0.12 -- inside wing dips, outside wing lifts
local HEAD_LEAD = 0.18 -- head turns into the turn ahead of the body
local NECK_LEAD = 0.28
local TAIL_DRAG = 0.24 -- tail swings out behind a turn (per segment, delayed)
local CLIMB_NECK = 0.22 -- neck lifts when climbing, lowers in a dive
local CLIMB_TAIL = 0.16 -- tail trails below a climb, above a dive
local DIVE_SWEEP = 0.38 -- wings sweep back in a dive

local function legPose(upper: number, lift: number, tuck: number): (CFrame, CFrame, CFrame)
	-- Knee/elbow bends while the leg swings forward or tucks; the foot stays near level.
	local lower = -0.65 * lift - 0.8 * math.max(tuck, 0)
	local foot = -0.55 * (upper + lower) - 0.3 * math.max(tuck, 0)
	return CFrame.Angles(upper, 0, 0), CFrame.Angles(lower, 0, 0), CFrame.Angles(foot, 0, 0)
end

-- p: blended params. t: seconds. flap: running wingbeat phase. stride: running
-- step phase. motion: secondary-motion inputs. size: model length / 36.
function DragonAnimation.PoseWestern(p: Params, t: number, flap: number, stride: number, motion: Motion, size: number): { [string]: CFrame }
	local pose: { [string]: CFrame } = {}
	local turn, climb = motion.Turn, motion.Climb
	local air = motion.Airborne

	-- Wings. Inner wing: a powerful downstroke and slower recovery (sin + 2nd
	-- harmonic). The tip follows a little later and bends further, like a whip.
	local stroke = math.sin(flap) + 0.28 * math.sin(2 * flap)
	if stroke < 0 then
		stroke *= 0.75 -- the downstroke ends lower than level, but not straight down
	end
	local tipStroke = math.sin(flap - 0.7) + 0.2 * math.sin(2 * flap - 1.4)
	local flutter = p.Flutter * 0.025 * math.sin(t * 19) + p.Flutter * 0.015 * math.sin(t * 31)
	local fold = math.clamp(p.WingFold, 0, 1)
	local spread = 1 - fold
	local spreadLift = p.WingLift + p.FlapAmp * stroke + flutter
	local bankLift = BANK_WING * turn * air
	local sweep = DIVE_SWEEP * math.max(0, -climb) * spread
	local tipBend = 0.55 * p.FlapAmp * tipStroke + flutter * 1.6
	-- Walking: folded wings shift with each step (the wrists help carry weight).
	local stepL = math.sin(stride)
	local stepR = math.sin(stride + math.pi)
	local walkL = p.Stride * 0.12 * stepR
	local walkR = p.Stride * 0.12 * stepL
	pose.LeftWing = CFrame.Angles(0, walkL, 0)
		* (CFrame.Angles(0, sweep, 0) * CFrame.Angles(0, 0, -(spreadLift - bankLift))):Lerp(FOLD_LEFT, fold)
	pose.RightWing = CFrame.Angles(0, -walkR, 0)
		* (CFrame.Angles(0, -sweep, 0) * CFrame.Angles(0, 0, spreadLift + bankLift)):Lerp(FOLD_RIGHT, fold)
	pose.LeftWingTip = CFrame.Angles(0, 0, -tipBend):Lerp(TIP_FOLD_LEFT, fold)
	pose.RightWingTip = CFrame.Angles(0, 0, tipBend):Lerp(TIP_FOLD_RIGHT, fold)
	-- Membrane (optional third wing piece): billows with the stroke, trembles when gliding.
	local billow = (0.3 * tipBend + flutter * 2.5) * spread
	pose.LeftWingMembrane = CFrame.Angles(0, 0, -billow)
	pose.RightWingMembrane = CFrame.Angles(0, 0, billow)

	-- Body: breathing, lifting on each downstroke, rolling with steps and into turns.
	local gallop = p.Gallop
	local breath = p.Breath * math.sin(t * 2 * math.pi * 0.3)
	local beat = -0.55 * p.FlapAmp * math.cos(flap)
	local stepBob = p.Stride * (0.3 + 0.35 * gallop) * (math.abs(math.sin(stride)) - 0.5)
	local roll = p.Stride * 0.03 * (1 - gallop) * math.sin(stride) + BANK_ROLL * turn * air
	local yawSway = p.Stride * 0.04 * (1 - gallop) * math.sin(stride + 0.6)
	local flex = 0.07 * gallop * math.sin(2 * stride) -- spine flexes with each bound
	pose.Body = CFrame.new(0, (breath + beat + stepBob) * size, 0)
		* CFrame.Angles(p.BodyPitch + 0.03 * p.FlapAmp * math.sin(flap) + flex, yawSway, roll)
	-- Chest (optional upper torso): counter-flexes against the pelvis.
	pose.Chest = CFrame.Angles(-flex * 1.4, -yawSway * 0.6, 0)

	-- Neck and head share the looking around (calm only), lead into turns, lift
	-- with a climb, stretch forward at speed, and keep the eyes level.
	local calm = (1 - math.min(1, p.FlapAmp)) * (1 - p.Stride * 0.5)
	local lookYaw = calm * (0.3 * math.sin(t * 0.31) + 0.15 * math.sin(t * 0.83))
	local lookPitch = calm * 0.1 * math.sin(t * 0.47)
	local nod = p.HeadBob * math.sin(t * 2 * math.pi * 0.45)
	local steady = -p.BodyPitch * 0.6 - 0.08 * p.FlapAmp * math.sin(flap)
	local reach = -0.14 * p.NeckReach
	local neckPitch = steady * 0.6 + lookPitch * 0.5 + nod * 0.4 - p.Stride * 0.05 * math.sin(2 * stride)
		- 0.1 * p.LegTuck + reach + CLIMB_NECK * climb - flex * 0.8
	local neckYaw = lookYaw * 0.55 + NECK_LEAD * turn - yawSway * 0.8
	local necks = math.max(1, motion.Necks)
	for i = 1, necks do
		pose[if i == 1 then "Neck" else "Neck" .. i] = CFrame.Angles(neckPitch / necks, neckYaw / necks, 0)
	end
	pose.Head = CFrame.Angles(
		steady * 0.4 + lookPitch * 0.5 + nod * 0.6 + 0.1 * p.LegTuck - reach * 0.7 + 0.1 * climb,
		lookYaw * 0.45 + HEAD_LEAD * turn,
		-roll * 0.8
	)
	pose.Jaw = CFrame.identity

	-- Tail: a travelling wave from base to tip (each segment later and wider),
	-- dragging behind turns with a delay, trailing below a climb.
	local tails = math.max(1, motion.Tails)
	local per = 3 / tails -- spread the same total bend over however many segments there are
	local tailPhase = t * 2 * math.pi * p.TailRate
	local tailPitch = 0.05 * math.sin(t * 1.1) - p.BodyPitch * 0.35 - CLIMB_TAIL * climb
	for i = 1, tails do
		local u = i * per -- position along the tail in "3-segment" units
		local amp = p.TailSway * (0.55 + 0.35 * u) * per
		local lag = 0.9 * u
		local drag = motion.TailTurn[i] or turn
		pose["Tail" .. i] = CFrame.Angles(
			(tailPitch / u) * per + p.Stride * 0.03 * per * math.sin(2 * stride - lag) - flex * 0.5 * per,
			amp * math.sin(tailPhase - lag) + TAIL_DRAG * per * drag + p.Stride * 0.12 * per * math.sin(stride - lag),
			0
		)
	end

	-- Legs. Trot: diagonal pairs (front-left with hind-right). Gallop: front pair
	-- together, hind pair together, half a cycle apart. Positive pitch = foot
	-- forward. In flight the legs tuck; hovering, the hind legs dangle; landing,
	-- they reach forward and down.
	local swing = 0.42 * p.Stride * (1 + 0.45 * gallop)
	local function phase(trot: number, gal: number): number
		return stride + trot + (gal - trot) * gallop
	end
	local tuck = p.LegTuck
	local tuckFront = -0.85 * math.max(tuck, 0) + 0.35 * math.max(-tuck, 0)
	local hindTuck = tuck * (1 - p.HindDangle)
	local tuckHind = -1.05 * math.max(hindTuck, 0) + 0.25 * math.max(-hindTuck, 0)
	local dangle = p.HindDangle * 0.09
	local legs = {
		{ "FrontLeft", phase(0, 0), tuckFront, 0, tuck },
		{ "FrontRight", phase(math.pi, 0.35), tuckFront, 0, tuck },
		{ "HindLeft", phase(math.pi, math.pi), tuckHind, dangle * math.sin(t * 1.7), hindTuck },
		{ "HindRight", phase(0, math.pi + 0.35), tuckHind, dangle * math.sin(t * 1.7 + 1.3), hindTuck },
	}
	for _, leg in legs do
		local ph: number = leg[2]
		local upperAngle = swing * math.sin(ph) + leg[3] + leg[4]
		local lift = p.Stride * math.max(0, math.cos(ph)) -- leg travelling forward = lifted
		local upper, lower, foot = legPose(upperAngle, lift, leg[5])
		pose[leg[1] .. "Leg"] = upper
		pose[leg[1] .. "LegLower"] = lower
		pose[leg[1] .. "Foot"] = foot
	end
	return pose
end

-- Keyframed clips ------------------------------------------------------------------
-- Each key: T (seconds) and Pose = { joint = { pitch, yaw, roll, lift } } where
-- lift is studs (Body only, scaled with size). "Neck" and "Tail" mean the whole
-- chain: the rotation is shared out over every neck / tail segment.
-- Priority: 1 Movement, 2 Action, 3 Action2 (higher is applied last, on top).
-- Mask: joints the clip may touch (others keep the procedural motion), so an
-- upper-body Roar plays over walking, hovering or gliding.
-- Events fire once at their time: the controller passes them to the VFX.

export type Key = { T: number, Pose: { [string]: { number } } }
export type Clip = {
	Name: string,
	Duration: number,
	Priority: number,
	Mask: { [string]: boolean }?,
	FadeIn: number,
	FadeOut: number,
	Keys: { Key },
	Events: { { T: number, Name: string } },
	TailWag: number?, -- radians of fast tail wag (Pet)
	TailWagRate: number?,
}

local UPPER = { Chest = true, Neck = true, Head = true, Jaw = true }
local TAIL = { Tail = true, Body = true }
local TAIL_AND_HEAD = { Neck = true, Head = true, Jaw = true, Tail = true }

DragonAnimation.Priority = { Movement = 1, Action = 2, Action2 = 3 }

local CLIPS: { [string]: (number?) -> Clip } = {
	-- Rear back, then a wide-jawed roar thrust forward.
	Roar = function(duration)
		local d = duration or 1.6
		return {
			Name = "Roar", Duration = d, Priority = 2, Mask = UPPER, FadeIn = 0.12, FadeOut = 0.25,
			Keys = {
				{ T = 0, Pose = {} },
				{ T = 0.35, Pose = { Neck = { 0.45, 0, 0 }, Head = { 0.35, 0, 0 }, Jaw = { -0.15, 0, 0 }, Chest = { -0.06, 0, 0 } } },
				{ T = 0.6, Pose = { Neck = { -0.28, 0, 0 }, Head = { -0.12, 0, 0 }, Jaw = { -0.8, 0, 0 }, Chest = { 0.1, 0, 0 } } },
				{ T = d - 0.35, Pose = { Neck = { -0.22, 0.05, 0 }, Head = { -0.1, -0.05, 0.06 }, Jaw = { -0.75, 0, 0 }, Chest = { 0.08, 0, 0 } } },
				{ T = d, Pose = {} },
			},
			Events = { { T = 0.55, Name = "Roar" } },
		}
	end,
	-- Charge (rear back, glow builds), then thrust forward with the jaw open
	-- for the breath stream. duration = how long the stream lasts.
	Breath = function(duration)
		local stream = duration or 1.2
		local d = 0.6 + stream + 0.3
		return {
			Name = "Breath", Duration = d, Priority = 2, Mask = UPPER, FadeIn = 0.1, FadeOut = 0.25,
			Keys = {
				{ T = 0, Pose = {} },
				{ T = 0.45, Pose = { Neck = { 0.38, 0, 0 }, Head = { 0.25, 0, 0 }, Jaw = { -0.2, 0, 0 }, Chest = { -0.05, 0, 0 } } },
				{ T = 0.62, Pose = { Neck = { -0.3, 0, 0 }, Head = { -0.18, 0, 0 }, Jaw = { -0.65, 0, 0 }, Chest = { 0.1, 0, 0 } } },
				{ T = 0.6 + stream, Pose = { Neck = { -0.24, 0, 0 }, Head = { -0.14, 0, 0 }, Jaw = { -0.6, 0, 0 }, Chest = { 0.08, 0, 0 } } },
				{ T = d, Pose = {} },
			},
			Events = { { T = 0, Name = "ChargeStart" }, { T = 0.58, Name = "BreathStart" }, { T = 0.6 + stream, Name = "BreathStop" } },
		}
	end,
	-- Happy reaction to being petted: lean the head in, tilt it, wag the tail.
	Pet = function(duration)
		local d = duration or 2.2
		return {
			Name = "Pet", Duration = d, Priority = 2, Mask = TAIL_AND_HEAD, FadeIn = 0.2, FadeOut = 0.35,
			Keys = {
				{ T = 0, Pose = {} },
				{ T = 0.4, Pose = { Neck = { -0.18, 0.12, 0 }, Head = { -0.12, 0.1, 0.3 } } },
				{ T = 1.2, Pose = { Neck = { -0.15, -0.08, 0 }, Head = { -0.08, -0.12, -0.25 }, Jaw = { -0.12, 0, 0 } } },
				{ T = d, Pose = {} },
			},
			Events = { { T = 0.3, Name = "Happy" } },
			TailWag = 0.42,
			TailWagRate = 4.5,
		}
	end,
	-- Wind the tail one way, snap it the other (burst at the snap).
	TailWhip = function(duration)
		local d = duration or 0.9
		return {
			Name = "TailWhip", Duration = d, Priority = 3, Mask = TAIL, FadeIn = 0.06, FadeOut = 0.2,
			Keys = {
				{ T = 0, Pose = {} },
				{ T = 0.3, Pose = { Tail = { 0.15, 0.75, 0 }, Body = { 0, -0.12, 0, 0 } } },
				{ T = 0.45, Pose = { Tail = { 0.05, -1.05, 0 }, Body = { 0, 0.16, 0, 0 } } },
				{ T = d, Pose = {} },
			},
			Events = { { T = 0.45, Name = "TailBurst" } },
		}
	end,
	-- Takeoff launch: crouch, then the hind legs push off and the nose lifts.
	Launch = function(duration)
		local d = duration or 0.55
		local legsDown = { 0.2, 0, 0 }
		return {
			Name = "Launch", Duration = d, Priority = 1, FadeIn = 0.05, FadeOut = 0.15,
			Mask = { Body = true, Chest = true, Neck = true, Head = true, FrontLeftLeg = true, FrontRightLeg = true, HindLeftLeg = true, HindRightLeg = true, Tail = true },
			Keys = {
				{ T = 0, Pose = {} },
				{ T = 0.2, Pose = { Body = { -0.06, 0, 0, -1.4 }, Neck = { -0.2, 0, 0 }, FrontLeftLeg = legsDown, FrontRightLeg = legsDown, HindLeftLeg = { 0.35, 0, 0 }, HindRightLeg = { 0.35, 0, 0 }, Tail = { -0.15, 0, 0 } } },
				{ T = 0.34, Pose = { Body = { 0.28, 0, 0, 0.9 }, Neck = { 0.25, 0, 0 }, HindLeftLeg = { -0.7, 0, 0 }, HindRightLeg = { -0.7, 0, 0 }, Tail = { -0.2, 0, 0 } } },
				{ T = d, Pose = {} },
			},
			Events = { { T = 0.3, Name = "Takeoff" } },
		}
	end,
}

DragonAnimation.ClipNames = { "Roar", "Breath", "Pet", "TailWhip", "Launch" }

function DragonAnimation.MakeClip(name: string, duration: number?): Clip?
	local make = CLIPS[name]
	return if make then make(duration) else nil
end

local function smooth(x: number): number
	return x * x * (3 - 2 * x)
end

-- Samples a clip at `elapsed` seconds. Returns joint -> CFrame offset.
function DragonAnimation.SampleClip(clip: Clip, elapsed: number, size: number): { [string]: CFrame }
	local keys = clip.Keys
	local out: { [string]: CFrame } = {}
	local i = 1
	while i < #keys - 1 and elapsed > keys[i + 1].T do
		i += 1
	end
	local a, b = keys[i], keys[math.min(i + 1, #keys)]
	local span = b.T - a.T
	local alpha = if span > 0 then smooth(math.clamp((elapsed - a.T) / span, 0, 1)) else 1
	local joints: { [string]: boolean } = {}
	for joint in a.Pose do
		joints[joint] = true
	end
	for joint in b.Pose do
		joints[joint] = true
	end
	for joint in joints do
		local va = a.Pose[joint] or { 0, 0, 0, 0 }
		local vb = b.Pose[joint] or { 0, 0, 0, 0 }
		local function lerp(k: number): number
			local x, y = va[k] or 0, vb[k] or 0
			return x + (y - x) * alpha
		end
		out[joint] = CFrame.new(0, lerp(4) * size, 0) * CFrame.Angles(lerp(1), lerp(2), lerp(3))
	end
	return out
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
