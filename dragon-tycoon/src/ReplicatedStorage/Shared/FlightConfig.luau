-- ReplicatedStorage/Shared/FlightConfig
-- Riding and flying numbers. The client steers with these; the server checks
-- riders stay inside them.

return {
	-- Ground
	GroundSpeed = 20, -- studs/s walking
	RunSpeed = 38, -- studs/s with boost held on the ground
	GroundAccel = 16, -- studs/s^2
	GroundDecel = 24,
	GroundTurnRate = 2.2, -- radians/s

	-- Air
	CruiseSpeed = 70, -- studs/s flying
	BoostSpeed = 115, -- studs/s flying with boost
	HoverSpeed = 0, -- no input = slow to a hover
	ClimbSpeed = 34, -- studs/s up/down with Climb/Dive held
	TakeoffSpeed = 30, -- upward leap when leaving the ground
	AirAccel = 20, -- studs/s^2 speeding up
	AirDecel = 26, -- slowing down
	DiveGain = 0.35, -- diving turns height into speed (and climbing costs speed)
	TurnRateSlow = 1.9, -- radians/s turning when slow
	TurnRateFast = 0.95, -- radians/s turning at full speed (wide, natural arcs)
	TurnEase = 3, -- how quickly turning starts/stops
	MaxPitch = math.rad(35),
	MaxBank = math.rad(50),

	-- Camera
	CameraLag = 7, -- higher = tighter follow
	BaseFov = 70,
	SpeedFov = 14, -- extra field of view at top speed
	CameraFollowRate = 1.6, -- how quickly the camera swings back behind the dragon in flight
	CameraReturnDelay = 1.2, -- seconds after the rider turns the camera by hand before it follows again
	CameraNeutralPitch = math.rad(-12), -- the chase camera's normal downward tilt counts as level flight
	CameraPitchDeadzone = math.rad(7), -- tilt within this range of neutral doesn't climb or dive

	-- Server limits (a little above the real maximums for lag tolerance)
	ServerMaxSpeed = 155,
	MaxAltitude = 900,
	WorldRadius = 1950,

	DespawnAfterDismount = 4, -- seconds an empty mount stays before vanishing
}
