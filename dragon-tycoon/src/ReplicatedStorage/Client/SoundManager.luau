-- ReplicatedStorage/Client/SoundManager
-- Music and sound effects, all on the client (sounds don't change gameplay).
--   Music: calm sanctuary playlist; battle music in duels, a heavier track in
--          raids; crossfades between them. A small button turns music on/off.
--   Effects: skills (by element), hits, roars, wingbeats while you fly, egg
--            cracks, level ups, rewards and button clicks.

local Players = game:GetService("Players")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SoundConfig = require(ReplicatedStorage.Shared.SoundConfig)
local SkillCatalog = require(ReplicatedStorage.Shared.SkillCatalog)
local Store = require(script.Parent.Store)
local UI = require(script.Parent.UI)

local SoundManager = {}

local player = Players.LocalPlayer
local musicOn = true
local currentMood = ""
local currentTrack: Sound? = nil
local playlistIndex = 0
local lastHatches: number? = nil
local wingSound: Sound? = nil
local wingModel: Model? = nil

local function makeSound(spec: any, parent: Instance): Sound
	local s = Instance.new("Sound")
	s.SoundId = spec.Id
	s.Volume = spec.Volume or 0.5
	s.PlaybackSpeed = spec.Speed or 1
	s.RollOffMaxDistance = 400
	s.RollOffMinDistance = 30
	s.Parent = parent
	return s
end

-- Plays a one-shot effect, in 3D at `at` (a part) or flat (UI) when nil.
function SoundManager.Play(name: string, at: BasePart?, volumeScale: number?)
	local spec = SoundConfig.Effects[name]
	if not spec then
		return
	end
	local s = makeSound(spec, at or SoundService)
	s.Volume *= volumeScale or 1
	s.PlaybackSpeed *= 0.95 + math.random() * 0.1 -- small variation so repeats don't sound robotic
	s:Play()
	s.Ended:Once(function()
		s:Destroy()
	end)
	task.delay(10, function()
		if s.Parent then
			s:Destroy()
		end
	end)
end

-- Music -------------------------------------------------------------------------------

local function fadeOut(sound: Sound)
	local tween = TweenService:Create(sound, TweenInfo.new(1.5), { Volume = 0 })
	tween:Play()
	tween.Completed:Once(function()
		sound:Destroy()
	end)
end

local playNext: () -> ()

local function setMood(mood: string)
	if mood == currentMood then
		return
	end
	currentMood = mood
	playlistIndex = 0
	playNext()
end

playNext = function()
	if currentTrack then
		fadeOut(currentTrack)
		currentTrack = nil
	end
	local list = SoundConfig.Music[currentMood]
	if not musicOn or not list or #list == 0 then
		return
	end
	playlistIndex = playlistIndex % #list + 1
	local spec = list[playlistIndex]
	local track = makeSound(spec, SoundService)
	track.Looped = #list == 1
	local target = track.Volume
	track.Volume = 0
	track:Play()
	TweenService:Create(track, TweenInfo.new(2), { Volume = target }):Play()
	currentTrack = track
	local mood = currentMood
	track.Ended:Connect(function()
		if currentTrack == track and currentMood == mood then
			playNext()
		end
	end)
end

local function toggleMusic(button: TextButton)
	musicOn = not musicOn
	button.Text = if musicOn then "Music: on" else "Music: off"
	if musicOn then
		local mood = currentMood
		currentMood = ""
		setMood(if mood ~= "" then mood else "Sanctuary")
	elseif currentTrack then
		fadeOut(currentTrack)
		currentTrack = nil
	end
end

-- Wingbeats on your own dragon --------------------------------------------------------

local function myMount(): Model?
	local mounts = workspace:FindFirstChild("Mounts")
	return mounts and mounts:FindFirstChild(player.Name .. "_Mount") :: Model?
end

local function updateWings()
	local mount = myMount()
	if mount ~= wingModel then
		if wingSound then
			wingSound:Destroy()
			wingSound = nil
		end
		wingModel = mount
		if mount and mount.PrimaryPart then
			SoundManager.Play("Roar", mount.PrimaryPart, 0.8) -- your dragon arrives
			wingSound = makeSound(SoundConfig.Effects.Wings, mount.PrimaryPart)
			;(wingSound :: Sound).Looped = true
			;(wingSound :: Sound).Volume = 0
			;(wingSound :: Sound):Play()
		end
	end
	if wingSound and mount and mount.PrimaryPart then
		local speed = mount.PrimaryPart.AssemblyLinearVelocity.Magnitude
		local target = if speed > 8 then math.clamp(speed / 120, 0.15, 1) * SoundConfig.Effects.Wings.Volume else 0
		wingSound.Volume += (target - wingSound.Volume) * 0.1
	end
end

-- Combat --------------------------------------------------------------------------------

local function rootOf(model: any): BasePart?
	return if typeof(model) == "Instance" and model:IsA("Model") then model.PrimaryPart else nil
end

local function onCombat(kind: string, a: any, b: any)
	if kind == "MatchStart" and type(a) == "table" then
		setMood(if a.Mode == "Raid" then "Raid" else "Battle")
		local foe = rootOf(a.Foe and a.Foe.Model)
		if foe then
			SoundManager.Play("Roar", foe, 1)
		end
	elseif kind == "MatchEnd" and type(a) == "table" then
		SoundManager.Play(if a.Won then "Chime" else "Hit", nil, 1)
		task.delay(5, setMood, "Sanctuary")
	elseif kind == "Fx" and type(b) == "table" then
		if a == "Cast" then
			local skill = SkillCatalog.Get(b.Skill)
			local at = rootOf(b.Caster)
			if skill and at then
				local effect = if skill.Kind == "Strike" then "Slash" else (SoundConfig.ElementCast[b.Element] or "Whoosh")
				SoundManager.Play(effect, at, if b.Ultimate then 1.4 else 1)
				if b.Ultimate then
					SoundManager.Play("Roar", at, 1)
				end
			end
		elseif a == "Hit" and b.Kind then
			local at = rootOf(b.Model)
			if at then
				SoundManager.Play("Hit", at, if b.Kind == "Strong" then 1.2 else 0.8)
			end
		elseif a == "BossBreath" or a == "BossSlam" then
			local at = rootOf(b.Caster) or nil
			SoundManager.Play(if a == "BossBreath" then "Roar" else "Thunder", at, 1.3)
		elseif a == "BossMeteor" then
			SoundManager.Play("Fire", nil, 0.6)
		end
	end
end

function SoundManager.start()
	-- Music on/off button, top-left under Roblox's menu buttons
	local gui = player:WaitForChild("PlayerGui"):WaitForChild("DragonTycoonUI", 10)
	if gui then
		local button = UI.new("TextButton", {
			Name = "MusicToggle",
			Position = UDim2.fromOffset(12, 60),
			Size = UDim2.fromOffset(96, 30),
			BackgroundColor3 = UI.Colors.Panel,
			BackgroundTransparency = 0.2,
			TextColor3 = UI.Colors.Text,
			Font = UI.Font,
			TextSize = 13,
			Text = "Music: on",
			Parent = gui,
		})
		UI.corner(button, 8)
		button.Activated:Connect(function()
			toggleMusic(button)
		end)
		-- A soft click on every button in our UI
		local function hook(d: Instance)
			if d:IsA("TextButton") or d:IsA("ImageButton") then
				(d :: any).Activated:Connect(function()
					SoundManager.Play("Click")
				end)
			end
		end
		for _, d in gui:GetDescendants() do
			hook(d)
		end
		gui.DescendantAdded:Connect(hook)
	end

	setMood("Sanctuary")

	local combat = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Combat", 30)
	if combat then
		(combat :: RemoteEvent).OnClientEvent:Connect(function(kind, a, b)
			local ok = pcall(onCombat, kind, a, b)
			_ = ok
		end)
	end
	Store.Notice:Connect(function(kind)
		if kind == "LevelUp" then
			SoundManager.Play("Chime")
		elseif kind == "TutorialStep" or kind == "WelcomeBack" then
			SoundManager.Play("Coins")
		elseif kind == "RobuxHatch" then
			SoundManager.Play("EggCrack")
		end
	end)
	Store.Changed:Connect(function(state)
		if lastHatches and state.Hatches and state.Hatches > lastHatches then
			SoundManager.Play("EggCrack")
		end
		lastHatches = state.Hatches
	end)
	RunService.Heartbeat:Connect(updateWings)
end

return SoundManager
