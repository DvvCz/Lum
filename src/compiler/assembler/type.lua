---@enum TypeVariant
local TypeVariant = {
	Native = 1,
	Function = 2
}

---@class Type
---@field variant TypeVariant
---@field union FnUnion|integer
local TypeMeta = {}
TypeMeta.__index = TypeMeta

local DebugNatives, ANY

function TypeMeta:__tostring()
	if self.variant == TypeVariant.Function then
		local buf = {}
		for i, param in ipairs(self.union.params) do
			buf[i] = tostring(param)
		end
		return "Fn(" .. table.concat(buf, ", ") ..  "): " .. tostring(self.union.ret)
	elseif self.variant == TypeVariant.Native then
		return DebugNatives[self]
	else
		return "Type { variant = " .. self.variant .. ", union = " .. tostring(self.union) .. " }"
	end
end

---@alias FnUnion { params: Type[], ret: Type }

---@param rhs Type
function TypeMeta:__eq(rhs)
	if getmetatable(rhs) ~= TypeMeta then
		return false
	end

	if
		(self.variant == TypeVariant.Native and self.union == ANY.union) or
		(rhs.variant == TypeVariant.Native and rhs.union == ANY.union)
	then
		return true
	end

	if self.variant == TypeVariant.Function then
		if rhs.variant ~= TypeVariant.Function then return false end

		---@type FnUnion, FnUnion
		local lhs, rhs = self.union, rhs.union
		if #lhs.params ~= #rhs.params then return false end

		for i, param in ipairs(lhs.params) do
			if param ~= rhs.params[i] then return false end
		end

		return lhs.ret == rhs.ret
	elseif self.variant == TypeVariant.Native then
		return rhs.variant == TypeVariant.Native and
			self.union == rhs.union
	end
end

---@param params Type[]
---@param ret Type
local function Fn(params, ret)
	return setmetatable({ variant = TypeVariant.Function, union = { params = params, ret = ret } }, TypeMeta)
end

---@param id integer
local function Native(id)
	return setmetatable({ variant = TypeVariant.Native, union = id }, TypeMeta)
end

ANY = Native(0)
local VOID = Native(1)
local INTEGER, FLOAT = Native(2), Native(3)
local STRING, BOOLEAN = Native(4), Native(5)
local IR = Native(6)

local Natives = {
	[0] = VOID, ["void"] = VOID,
	[1] = ANY, ["any"] = ANY,
	[2] = INTEGER, ["integer"] = INTEGER,
	[3] = FLOAT, ["float"] = FLOAT,
	[4] = STRING, ["string"] = STRING,
	[5] = BOOLEAN, ["boolean"] = BOOLEAN,
	[6] = IR, ["ir"] = IR
}

DebugNatives = {}
for k, v in pairs(Natives) do
	if type(k) == "string" then
		DebugNatives[v] = k
	end
end

return {
	Fn = Fn,
	Natives = Natives
}