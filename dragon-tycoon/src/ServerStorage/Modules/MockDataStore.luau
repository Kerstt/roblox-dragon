-- ServerStorage/Modules/MockDataStore
-- In-memory stand-in for a DataStore. Used by the tests, and by DataService in
-- Studio when "Enable Studio Access to API Services" is off (nothing persists then).

local MockDataStore = {}
MockDataStore.__index = MockDataStore

local function deepCopy(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for k, v in value do
		copy[k] = deepCopy(v)
	end
	return copy
end

export type MockDataStore = typeof(setmetatable({} :: {
	data: { [string]: any },
	failNext: number,
	failAll: boolean,
	calls: number,
}, MockDataStore))

function MockDataStore.new(): MockDataStore
	return setmetatable({
		data = {},
		failNext = 0, -- the next N requests throw, like a DataStore outage
		failAll = false, -- every request throws
		calls = 0,
	}, MockDataStore)
end

function MockDataStore._maybeFail(self: MockDataStore)
	self.calls += 1
	if self.failAll then
		error("MockDataStore: simulated outage")
	end
	if self.failNext > 0 then
		self.failNext -= 1
		error("MockDataStore: simulated request failure")
	end
end

function MockDataStore.GetAsync(self: MockDataStore, key: string): any
	self:_maybeFail()
	return deepCopy(self.data[key])
end

function MockDataStore.SetAsync(self: MockDataStore, key: string, value: any)
	self:_maybeFail()
	self.data[key] = deepCopy(value)
end

-- Same contract as DataStore:UpdateAsync: the transform gets a copy of the stored
-- value; returning nil cancels the write.
function MockDataStore.UpdateAsync(self: MockDataStore, key: string, transform: (any) -> any): any
	self:_maybeFail()
	local newValue = transform(deepCopy(self.data[key]))
	if newValue == nil then
		return nil
	end
	self.data[key] = deepCopy(newValue)
	return deepCopy(newValue)
end

return MockDataStore
