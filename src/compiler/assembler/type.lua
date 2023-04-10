---@enum TypeVariant
local Variant = {
	---@alias NativeUnion integer
	Native = 1,

	--- Constant value of type. const x = integer
	---@alias TypeUnion Type
	Type = 2,

	---@alias FnUnion { const: boolean, params: Type[], ret: Type }
	Function = 3,

	---@alias StructUnion { fields: table<string, Type> }
	Struct = 4,

	---@alias ArrayUnion Type
	Array = 5,
}

---@class Type
---@field variant TypeVariant
---@field union NativeUnion|TypeUnion|StructUnion|FnUnion|ArrayUnion
local TypeMeta = {}
TypeMeta.__index = TypeMeta

local DebugNatives, ANY

function TypeMeta:__tostring()
	local variant, union = self.variant, self.union
	if variant == Variant.Native then ---@cast union NativeUnion
		return DebugNatives[self]
	elseif variant == Variant.Type then ---@cast union TypeUnion
		return "Type(" .. tostring(union) .. ")"
	elseif variant == Variant.Function then ---@cast union FnUnion
		local buf = {}
		for i, param in ipairs(union.params) do
			buf[i] = tostring(param)
		end
		return "Fn(" .. table.concat(buf, ", ") ..  "): " .. tostring(union.ret)
	elseif variant == Variant.Struct then ---@cast union StructUnion
		local buf = {}
		for name, ty in pairs(union.fields) do
			buf[#buf + 1] = name .. ": " .. tostring(ty)
		end
		return "Struct { " .. table.concat(buf, ", ") .. " }"
	elseif variant == Variant.Array then ---@cast union ArrayUnion
		return "Array(" .. tostring(union) .. ")"
	else
		return "Type { variant = " .. self.variant .. ", union = " .. tostring(self.union) .. " }"
	end
end

---@param rhs Type
function TypeMeta:__eq(rhs)
	if getmetatable(rhs) ~= TypeMeta then
		return false
	end

	if
		(self.variant == Variant.Native and self.union == ANY.union) or
		(rhs.variant == Variant.Native and rhs.union == ANY.union)
	then
		return true
	end

	if self.variant == Variant.Function then
		if rhs.variant ~= Variant.Function then return false end

		local lhs, rhs = self.union, rhs.union
		---@cast lhs FnUnion
		---@cast rhs FnUnion

		if #lhs.params ~= #rhs.params then return false end

		for i, param in ipairs(lhs.params) do
			if param ~= rhs.params[i] then return false end
		end

		return lhs.ret == rhs.ret
	elseif self.variant == Variant.Type then
		if rhs.variant ~= Variant.Type then return false end

		return self.union == rhs.union
	elseif self.variant == Variant.Struct then
		if rhs.variant ~= Variant.Struct then return false end

		local lhs, rhs = self.union, rhs.union
		---@cast lhs StructUnion
		---@cast rhs StructUnion

		for k, v in pairs(lhs.fields) do
			local rhs = rhs.fields[k]
			if not rhs or rhs ~= v then
				return false
			end
		end

		for k, v in pairs(rhs.fields) do
			local lhs = lhs.fields[k]
			if not lhs or lhs ~= v then
				return false
			end
		end

		return true
	elseif self.variant == Variant.Array then
		return rhs.variant == Variant.Array and self.union == rhs.union
	elseif self.variant == Variant.Native then
		return rhs.variant == Variant.Native and
			self.union == rhs.union
	end
end

---@param params Type[]
---@param ret Type
---@param const boolean?
local function Fn(params, ret, const)
	return setmetatable({ variant = Variant.Function, union = { params = params, ret = ret, const = const } }, TypeMeta)
end

---@param ty Type
local function Ty(ty)
	return setmetatable({ variant = Variant.Type, union = ty }, TypeMeta)
end

---@param fields table<string, Type>
local function Struct(fields)
	return setmetatable({ variant = Variant.Struct, union = { fields = fields } }, TypeMeta)
end

---@param type Type
local function Array(type)
	return setmetatable({ variant = Variant.Array, union = type }, TypeMeta)
end

---@param id integer
local function Native(id)
	return setmetatable({ variant = Variant.Native, union = id }, TypeMeta)
end

ANY = Native(0)
local VOID = Native(1)
local INTEGER, FLOAT = Native(2), Native(3)
local STRING, BOOLEAN = Native(4), Native(5)
local IR, TYPE = Native(6), Native(7)

local Natives = {
	[0] = ANY, ["any"] = ANY,
	[1] = VOID, ["void"] = VOID,
	[2] = INTEGER, ["integer"] = INTEGER,
	[3] = FLOAT, ["float"] = FLOAT,
	[4] = STRING, ["string"] = STRING,
	[5] = BOOLEAN, ["boolean"] = BOOLEAN,
	[6] = IR, ["ir"] = IR,
	[7] = TYPE, ["type"] = TYPE
}

DebugNatives = {}
for k, v in pairs(Natives) do
	if type(k) == "string" then
		DebugNatives[v] = k
	end
end

---@param type string
---@return Type
local function from(type)
	return assert(Natives[type], "Invalid type: " .. tostring(type))
end

return {
	Fn = Fn,
	Ty = Ty,
	Struct = Struct,
	Array = Array,

	from = from,

	Variant = Variant,
	Natives = Natives
}