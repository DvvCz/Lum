local Type = require "compiler.assembler.type"
local Natives, Fn, Struct = Type.Natives, Type.Fn, Type.Struct

---@class IR
---@field variant IRVariant
---@field data any
---@field type Type
local IR = {}
IR.__index = IR

function IR:__tostring()
	return "IR " .. self.variant
end

---@param variant IRVariant
---@param data any
---@param type Type?
function IR.new(variant, data, type)
	return setmetatable({ variant = variant, data = data, type = type or Natives.void }, IR)
end

---@class IRVariable
---@field type Type # Type of the variable (ie "integer")
---@field const boolean?
local IRVariable = {}
IRVariable.__index = IRVariable

---@param type Type
---@param const boolean?
function IRVariable.new(type, const)
	return setmetatable({ type = type, const = const }, IRVariable)
end

IR.Variable = IRVariable

---@enum IRVariant
IR.Variant = {
	Emit = -1, -- Used by the compiler `emit` intrinsic.

	Module = 1,
	Scope = 2,

	If = 3,
	While = 4,
	Fn = 5,
	Return = 6,

	Declare = 7,
	Assign = 8,

	Call = 9,
	Index = 10,

	Negate = 11,

	Add = 12,
	Sub = 13,
	Mul = 14,
	Div = 15,

	And = 16,
	Or = 17,

	Eq = 18,
	NotEq = 19,

	Literal = 20, -- "" 22 22.0

	StructInstance = 21,
	Struct = 22,

	Identifier = 23
}

return IR