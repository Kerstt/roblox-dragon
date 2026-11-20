-- ServerStorage/Modules/RateLimiter
-- Token bucket per player: allows short bursts, caps the sustained rate.

local Players = game:GetService("Players")

local RateLimiter = {}
RateLimiter.__index = RateLimiter

function RateLimiter.new(perSecond: number, burst: number)
	local self = setmetatable({
		perSecond = perSecond,
		burst = burst,
		buckets = {} :: { [any]: { tokens: number, at: number } },
	}, RateLimiter)
	Players.PlayerRemoving:Connect(function(player)
		self.buckets[player] = nil
	end)
	return self
end

-- True if this request is allowed (and uses one token).
function RateLimiter:Allow(key: any, now: number?): boolean
	local t = now or os.clock()
	local bucket = self.buckets[key]
	if not bucket then
		bucket = { tokens = self.burst, at = t }
		self.buckets[key] = bucket
	end
	bucket.tokens = math.min(self.burst, bucket.tokens + (t - bucket.at) * self.perSecond)
	bucket.at = t
	if bucket.tokens < 1 then
		return false
	end
	bucket.tokens -= 1
	return true
end

return RateLimiter
