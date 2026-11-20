-- ServerStorage/Modules/EggRollLog
-- Audit log of every egg hatch (who, which egg, what came out, paid with what),
-- as the paid random items checklist requires. Rolls are buffered in memory and
-- written in one batch per minute per server, to stay inside DataStore limits.
-- Each batch is one key: "<UTC date>/<server>/<batch number>".

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")

local EggRollLog = {}

local STORE_NAME = "DragonTycoon_EggRolls_v1"
local FLUSH_SECONDS = 60
local MAX_BUFFER = 5000 -- if writes keep failing, keep at most this many

local buffer = {}
local batchNumber = 0
-- DataStore keys are limited to 50 characters, so use a short server id:
-- "2026-11-20/" (11) + 16 characters + "/" + batch number stays well under it.
local serverId = ((if game.JobId ~= "" then game.JobId else HttpService:GenerateGUID(false)):gsub("[^%w]", "")):sub(1, 16)
local store: any = nil

function EggRollLog.Record(player: Player, eggId: string, result: any, paidWith: string)
	table.insert(buffer, {
		T = os.time(),
		U = player.UserId,
		E = eggId,
		R = result.Rarity,
		S = result.Species,
		P = paidWith, -- "Coins" or "Robux"
		X = if result.Released then 1 else 0,
		L = if result.Lucky then 1 else 0, -- rolled with the Luck Boost odds
	})
	if #buffer > MAX_BUFFER then
		table.remove(buffer, 1)
	end
end

function EggRollLog.Flush()
	if #buffer == 0 or not store then
		return
	end
	local batch = buffer
	buffer = {}
	batchNumber += 1
	local key = os.date("!%Y-%m-%d") .. "/" .. serverId .. "/" .. batchNumber
	local ok, err = pcall(function()
		store:SetAsync(key, batch)
	end)
	if not ok then
		warn("[EggRollLog] Write failed, will retry:", err)
		-- put the batch back in front of anything logged meanwhile
		for i = #batch, 1, -1 do
			table.insert(buffer, 1, batch[i])
		end
		while #buffer > MAX_BUFFER do
			table.remove(buffer, 1)
		end
	end
end

function EggRollLog.init()
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(STORE_NAME)
	end)
	if ok then
		store = result
	else
		warn("[EggRollLog] Log store unavailable:", result)
	end
	task.spawn(function()
		while true do
			task.wait(FLUSH_SECONDS)
			EggRollLog.Flush()
		end
	end)
	game:BindToClose(EggRollLog.Flush)
end

return EggRollLog
