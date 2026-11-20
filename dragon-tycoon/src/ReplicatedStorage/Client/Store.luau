-- ReplicatedStorage/Client/Store
-- The client's copy of its own sanctuary (sent by the server) and the one
-- function for asking the server to do something. The client never decides
-- outcomes; it only displays what the server sends.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Store = {}

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local requestRemote = remotes:WaitForChild("Request") :: RemoteFunction
local stateRemote = remotes:WaitForChild("State") :: RemoteEvent
local noticeRemote = remotes:WaitForChild("Notice") :: RemoteEvent

local changed = Instance.new("BindableEvent")
local noticed = Instance.new("BindableEvent")

Store.State = nil :: any
-- Fires (state) whenever a new snapshot arrives.
Store.Changed = changed.Event
-- Fires (kind, payload) for server notices.
Store.Notice = noticed.Event

local function setState(state: any)
	if type(state) == "table" then
		Store.State = state
		changed:Fire(state)
	end
end

-- Asks the server to do an action. Always returns a table with `ok`.
function Store.Request(action: string, ...: any): any
	local ok, result = pcall(requestRemote.InvokeServer, requestRemote, action, ...)
	if not ok or type(result) ~= "table" then
		return { ok = false, error = "network" }
	end
	return result
end

function Store.start()
	stateRemote.OnClientEvent:Connect(setState)
	noticeRemote.OnClientEvent:Connect(function(kind, payload)
		noticed:Fire(kind, payload)
	end)
	-- First snapshot (the server also pushes one when the save loads).
	task.spawn(function()
		for _ = 1, 30 do
			if Store.State then
				return
			end
			local result = Store.Request("GetState")
			if result.ok then
				setState(result.state)
				return
			end
			task.wait(1)
		end
	end)
end

-- Friendly text for server error codes.
local MESSAGES = {
	not_enough_coins = "Not enough coins yet.",
	nest_full = "Your nest is full. Release or assign some dragons first.",
	too_fast = "Easy there, the last egg is still settling.",
	no_free_slot = "No free slot at that station.",
	station_full = "This station already has all 3 slots.",
	all_slots_bought = "You've unlocked every slot.",
	max_level = "This station is at max level.",
	station_closed = "Unlock a slot here first.",
	rate_limited = "Slow down a little.",
	choose_starter_first = "Choose your first dragon first.",
	working = "Send that dragon to the nest first.",
	not_loaded = "Your save is still loading.",
	network = "Connection hiccup, try again.",
	in_battle = "Not during a battle.",
	not_enough_essence = "Not enough essence. Release dragons to get more.",
	max_dragon_level = "This dragon is already at max level.",
	arenas_busy = "All arenas are busy. Try again in a moment.",
	not_found = "That dragon isn't here anymore.",
	down = "You're down. Hang on!",
}

function Store.ErrorText(code: string?): string
	return MESSAGES[code or ""] or "Something went wrong, try again."
end

return Store
