--!strict
-- ReplicatedStorage/Client/HatchReveal
-- Public client adapter preserving HatchReveal.init / HatchReveal.Play(result, quick)
-- for EggShop & ShopSheet, plus HatchReveal.PlayBatch(results, quick) for 4-egg
-- cluster hatching, delegating to HatchSequenceController.

local HatchSequenceController = require(script.Parent.HatchSequenceController)
local HatchCelebrationFX = require(script.Parent.HatchCelebrationFX)

local HatchReveal = {}

local screen: ScreenGui? = nil

function HatchReveal.init(screenGui: ScreenGui)
	screen = screenGui
end

-- Yields until the single-egg 3D hatch & celebration sequence finishes.
function HatchReveal.Play(result: HatchCelebrationFX.HatchItem, quick: boolean)
	assert(screen ~= nil, "HatchReveal.init(screenGui) must be called before Play")
	HatchSequenceController.PlaySingle(screen :: ScreenGui, result, quick)
end

-- Yields until the multi-egg (up to 4 eggs) 3D cluster hatch & celebration finishes.
function HatchReveal.PlayBatch(results: { HatchCelebrationFX.HatchItem }, quick: boolean)
	assert(screen ~= nil, "HatchReveal.init(screenGui) must be called before PlayBatch")
	HatchSequenceController.PlayCluster(screen :: ScreenGui, results, quick)
end

return HatchReveal
