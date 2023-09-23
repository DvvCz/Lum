local Type = require "compiler.assembler.type"
local Natives, Fn, Struct = Type.Natives, Type.Fn, Type.Struct

---@class IR
---@field variant IRVariant
---@field data any
---@field type Type
---@field const true?
local IR = {}
IR.__index = IR

function IR:__tostring()
	return "IR " .. self.variant
end

---@param variant IRVariant
---@param data any
---@param type Type?
---@param const boolean?
function IR.new(variant, data, type, const)
	return setmetatable({ variant = variant, data = data, type = type or Natives.void, const = const }, IR)
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

	Group = 9,
	Call = 10,
	Index = 11,

	Negate = 12,

	Add = 13,
	Sub = 14,
	Mul = 15,
	Div = 16,

	And = 17,
	Or = 18,

	Eq = 19,
	NotEq = 20,

	Literal = 21, -- "" 22 22.0

	StructInstance = 22,
	Struct = 23,

	Identifier = 24
}

return IR
