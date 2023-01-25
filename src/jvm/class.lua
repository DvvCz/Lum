local ByteVec = require "jvm.bytevec"
local Constant = require "jvm.constant"

local ACCESS = {
	PUBLIC = 0x0001,
	FINAL = 0x0010,
	SUPER = 0x0020,
	INTERFACE = 0x0200,
	ABSTRACT = 0x0400,
	SYNTHETIC = 0x1000,
	ANNOTATION = 0x2000,
	ENUM = 0x4000,
	MODULE = 0x8000
}

---@class Class
---@field name string
---@field string_table table<string, integer>
---@field string_count integer
local Class = {}
Class.__index = Class

---@param name string
function Class.new(name)
	assert(name, "Expected name for argument #1")
	return setmetatable({ name = name, string_table = { [name] = 1 }, string_count = 1 }, Class)
end

function Class:withStrings(strs)
	local count, len = self.string_count, #strs
	for k = 1, len do
		self.string_table[ strs[k] ] = count + k
	end
	self.string_count = count + len
	return self
end

function Class:encode()
	local vec = ByteVec.new()
	vec:writeU4(0xCAFEBABE) -- magic
	vec:writeU2(0) -- minor_version
	vec:writeU2(61) -- major_version (61 for Java SE 17)

	local constants = {}

	---@param str string
	local function Str(str)
		return self.string_table[str]
	end

	for str, i in pairs(self.string_table) do
		constants[i] = Constant.new("Utf8", str)
	end

	local i = #constants
	local function Const(ty, data)
		i = i + 1
		constants[i] = Constant.new(ty, data)
		return i
	end

	local main = Const("Class", self.string_table[self.name])

	vec:writeU2(#constants + 1) -- constant_pool_count
	for _, const in ipairs(constants) do
		const:writeTo(vec)
	end

	vec:writeU2(ACCESS.SUPER) -- access_flags
	vec:writeU2(main) -- this_class (index to constant table)
	vec:writeU2(0) -- super_class

	vec:writeU2(0) -- interfaces_count
	vec:writeU2(0) -- fields_count

	vec:writeU2(1) -- methods_count

	vec:writeU2(ACCESS.PUBLIC)
	vec:writeU2(self.string_table["<init>"])
	vec:writeU2(self.string_table["([Ljava/lang/String;)V"])
	vec:writeU2(0)

	vec:writeU2(0) -- attributes_count

	return vec:getOutput()
end

return Class