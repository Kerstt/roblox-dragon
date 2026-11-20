-- ReplicatedStorage/Shared/TutorialConfig
-- The guided first five minutes. The server (TutorialService) checks each step
-- and pays its reward; the client (TutorialGuide) shows the text and points at
-- the button to press (Highlight = a bottom-menu button).

local TutorialConfig = {}

TutorialConfig.Done = 99

TutorialConfig.Steps = {
	{ Id = "Starter", Title = "Welcome, dragon keeper!", Text = "Choose your first dragon.", Reward = 0 },
	{ Id = "Hatch", Title = "Hatch an egg", Text = "Tap <b>Eggs</b> and buy a <b>Hatchling Egg</b>.", Reward = 150, Highlight = "Eggs", Action = "Hatch" },
	{ Id = "Assign", Title = "Put a dragon to work", Text = "Tap <b>Dragons</b>, then <b>Assign</b> a resting dragon to a station. Working dragons earn coins every second.", Reward = 200, Highlight = "Dragons", Action = "Assign" },
	{ Id = "Ride", Title = "Take to the skies", Text = "Tap <b>Ride</b>, pick a dragon, then hold <b>Space</b> to take off. WASD to fly.", Reward = 250, Highlight = "Ride" },
	{ Id = "Feed", Title = "Train your dragon", Text = "Tap <b>Dragons</b>, then <b>Train</b> and <b>Feed</b> a dragon. Levels unlock new skills.", Reward = 200, Highlight = "Dragons", Action = "Feed" },
	{ Id = "Battle", Title = "Your first battle", Text = "Tap <b>Battle</b>, then <b>Start practice</b>. Use 1, 2, 3 for skills and E to dodge.", Reward = 300, Highlight = "Battle", Action = "Practice" },
}
TutorialConfig.FinishReward = 500

function TutorialConfig.Get(step: number)
	return TutorialConfig.Steps[step + 1] -- step numbers start at 0
end

return TutorialConfig
