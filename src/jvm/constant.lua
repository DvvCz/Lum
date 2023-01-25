---@enum ConstantTag
local ConstantTag = {
	Utf8 = 1,
	Integer = 3,
	Float = 4,
	Long = 5,
	Double = 6,
	Class = 7,
	String = 8,

	FieldRef = 9,
	MethodRef = 10,
	InterfaceMethodRef = 11,

	NameAndType = 12,

	MethodHandle = 15,
	MethodType = 16,

	Dynamic = 17,
	InvokeDynamic = 18,

	Module = 19,
	Package = 20
}

local DebugConstantTag = {}
for k, v in pairs(ConstantTag) do
	DebugConstantTag[v] = k
end

---@class Constant
---@field tag ConstantTag
---@field data any
local Constant = {}
Constant.__index = Constant

function Constant:__tostring()
	return "Constant { tag: " .. DebugConstantTag[self.tag] .. " (" .. self.tag .. "), data: " .. tostring(self.data) .. " }"
end

---@param tag "Utf8"|"Integer"|"Float"|"Long"|"Double"|"Class"|"String"|"FieldRef"|"MethodRef"|"InterfaceMethodRef"|"NameAndType"|"MethodHandle"|"MethodType"|"Dynamic"|"InvokeDynamic"|"Module"|"Package"
function Constant.new(tag, data)
	local tag = assert(ConstantTag[tag], "Invalid tag: " .. tag)
	return setmetatable({ tag = tag, data = data }, Constant)
end

---@param vec ByteVec
function Constant:writeTo(vec)
	vec:writeU1(self.tag)
	if self.tag == ConstantTag.Class then
		vec:writeU2(self.data)
	elseif self.tag == ConstantTag.Integer then
		vec:writeU4(self.data)
	elseif self.tag == ConstantTag.String then
		vec:writeU2(self.data) -- Index to a Constant (Utf8)
	elseif self.tag == ConstantTag.Utf8 then
		vec:writeU2(#self.data)
		vec:writeString(self.data)
	elseif self.tag == ConstantTag.MethodRef then
		vec:writeU2(self.data[1]) -- class_index
		vec:writeU2(self.data[2]) -- name_and_type_index
	elseif self.tag == ConstantTag.NameAndType then
		vec:writeU2(self.data[1]) -- name_index (name)
		vec:writeU2(self.data[2]) -- descriptor_index (type)
	else
		error("Unimplemented tag: " +  self.tag)
	end
end

return Constant, ConstantTag