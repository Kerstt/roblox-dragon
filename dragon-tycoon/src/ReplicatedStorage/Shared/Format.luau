-- ReplicatedStorage/Shared/Format
-- Number and time formatting for UI and signs.

local Format = {}

local SUFFIXES = { "", "K", "M", "B", "T", "Qa", "Qi" }

-- 999 -> "999", 1234 -> "1.23K", 2500000 -> "2.5M"
function Format.Short(n: number): string
	if n ~= n then
		return "0"
	end
	local sign = if n < 0 then "-" else ""
	n = math.abs(n)
	if n < 1000 then
		if n == math.floor(n) then
			return sign .. tostring(n)
		end
		return sign .. (string.format("%.1f", n):gsub("%.0$", ""))
	end
	local i = 1
	while n >= 1000 and i < #SUFFIXES do
		n /= 1000
		i += 1
	end
	local text = if n >= 100 then string.format("%.0f", n) elseif n >= 10 then string.format("%.1f", n) else string.format("%.2f", n)
	if text:find("%.") then
		text = text:gsub("0+$", ""):gsub("%.$", "")
	end
	return sign .. text .. SUFFIXES[i]
end

-- 1234567 -> "1,234,567"
function Format.Commas(n: number): string
	local text = tostring(math.floor(math.abs(n)))
	local result = text:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
	return (if n < 0 then "-" else "") .. result
end

-- 3725 -> "1h 2m", 125 -> "2m 5s"
function Format.Duration(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	local h = seconds // 3600
	local m = (seconds % 3600) // 60
	local s = seconds % 60
	if h > 0 then
		return string.format("%dh %dm", h, m)
	elseif m > 0 then
		return string.format("%dm %ds", m, s)
	end
	return string.format("%ds", s)
end

return Format
