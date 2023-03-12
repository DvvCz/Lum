---@enum TypeVariant
local Variant = {
	Native = 1,

	--- Constant value of type. const x = integer
	---@alias TypeUnion { type: Type }
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
---@field union FnUnion|TypeUnion|StructUnion|ArrayUnion|integer
local TypeMeta = {}
TypeMeta.__index = TypeMeta

local DebugNatives, ANY

function TypeMeta:__tostring()
	if self.variant == Variant.Function then
		local buf = {}
		for i, param in ipairs(self.union.params) do
			buf[i] = tostring(param)
		end
		return "Fn(" .. table.concat(buf, ", ") ..  "): " .. tostring(self.union.ret)
	elseif self.variant == Variant.Native then
		return DebugNatives[self]
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
	elseif self.variant == Variant.Struct then
		if rhs.variant ~= Variant.Struct then return false end

		local lhs, rhs = self.union, rhs.union
		---@cast lhs StructUnion
		---@cast rhs StructUnion

		if #lhs.fields ~= #rhs.fields then return false end

		for i, field in ipairs(lhs.fields) do
			if field ~= rhs.fields[i] then return false end
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
	return setmetatable({ variant = Variant.Type, union = { type = ty } }, TypeMeta)
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
local IR = Native(6)

local Natives = {
	[0] = ANY, ["any"] = ANY,
	[1] = VOID, ["void"] = VOID,
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