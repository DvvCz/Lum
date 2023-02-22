-- Basically a second AST, with more info.
-- Compiles to a bunch of instructions, which can then be tweaked with optimizer.
local Parser = require "compiler.parser"
local NodeVariant = Parser.Variant

--[[
	let x = 5
	{
		let y = 2
	}

	fn test() {}

	mod foo {
		fn bar() {}
	}
]]

---@class IR
---@field variant IRVariant
---@field data table
local IR = {}
IR.__index = IR

function IR:__tostring()
	return "IR " .. self.variant
end

function IR.new(variant, data)
	return setmetatable({ variant = variant, data = data}, IR)
end

---@class IRVariable
---@field val any? # The value of the variable, if it could be deduced at compile time.
---@field type string # Type of the variable (ie "int")
local IRVariable = {}
IRVariable.__index = IRVariable

function IRVariable.new(type, const)
	return setmetatable({ type = type, const = const }, IRVariable)
end

---@enum IRVariant
local Variant = {
	Module = 1,
	Scope = 2,

	If = 3, -- if <exp> {}
	While = 4, -- while <exp> {}

	Assign = 5, -- x = 5
	Declare = 6, -- let x = 5

	Call = 7,

	Negate = 8,

	Add = 9,
	Sub = 10,
	Mul = 11,
	Div = 12,

	And = 13,
	Or = 14,

	Literal = 15, -- "" 22 22.0
	Identifier = 16
}

---@class Scope
---@field data table<string, IRVariable>
---@field parent Scope?
local Scope = {}

---@return Scope
function Scope.new(parent)
	return setmetatable({ data = {}, parent = parent }, Scope)
end

---@param ast Node
---@return IR
local function assemble(ast)
	local current = Scope.new()

	---@generic T
	---@param fn fun(scope: table<string, IRVariable>): T?
	---@return T
	local function scope(fn)
		current = Scope.new(current)
		local ret = fn(current)
		current = current.parent
		return ret
	end

	---@return string type
	local function typeNode(node)
		local variant, nv = node.variant, NodeVariant

		if variant == nv.Add then
			local lhs_ty, rhs_ty = typeNode(node.data[1]), typeNode(node.data[2])
			assert(lhs_ty == rhs_ty, "Cannot add differing types")
			return lhs_ty
		elseif variant == nv.Sub then
			local lhs_ty, rhs_ty = typeNode(node.data[1]), typeNode(node.data[2])
			assert(lhs_ty == rhs_ty, "Cannot sub differing types")
			return lhs_ty
		elseif variant == nv.Mul then
			local lhs_ty, rhs_ty = typeNode(node.data[1]), typeNode(node.data[2])
			assert(lhs_ty == rhs_ty, "Cannot mul differing types")
			return lhs_ty
		elseif variant == nv.Div then
			local lhs_ty, rhs_ty = typeNode(node.data[1]), typeNode(node.data[2])
			assert(lhs_ty == rhs_ty, "Cannot div differing types")
			return lhs_ty
		elseif variant == nv.And then
			local lhs_ty, rhs_ty = typeNode(node.data[1]), typeNode(node.data[2])
			assert(lhs_ty == rhs_ty and lhs_ty == "boolean", "Can only use logical AND operator with booleans")
			return "boolean"
		elseif variant == nv.Or then
			local lhs_ty, rhs_ty = typeNode(node.data[1]), typeNode(node.data[2])
			assert(lhs_ty == rhs_ty and lhs_ty == "boolean", "Can only use logical OR operator with booleans")
			return "boolean"
		elseif variant == nv.Negate then
			local ty = typeNode(node.data)
			assert(ty == "int" or ty == "float", "Can only negate float or integer")
			return ty
		elseif variant == nv.Literal then
			return node.data[1]
		else
			error("Failed to narrow type for " .. tostring(node))
		end
	end

	---@param node Node
	local function assembleNode(node)
		local variant, data, nv = node.variant, node.data, NodeVariant
		if variant == nv.Block then
			return IR.new(Variant.Scope, scope(function(_scope)
				local items = {}
				for i, item in ipairs(data) do
					items[i] = assembleNode(item)
				end
				return items
			end))
		elseif variant == nv.Declare then
			if current.data[data[1]] then
				error("Cannot re-declare existing variable " .. data[1])
			else
				current.data[data[1]] = typeNode(data[2])
				return IR.new(Variant.Declare, { data[1], assembleNode(data[2]) })
			end
		elseif variant == nv.Assign then
			local expected, got = assert(current.data[data[1]], "Variable " .. node.data[1] .. " does not exist"), typeNode(node.data[2])
			assert(expected == got, "Cannot assign type " .. got .. " to variable of " .. expected)
			return IR.new(Variant.Assign, { data[1], assembleNode(data[2]) })
		elseif variant == nv.If then
			local chain = {}
			for i, if_else_if in ipairs(data) do
				local cond, block = if_else_if[1], if_else_if[2]
				chain[i] = { cond and assembleNode(cond), assembleNode(block) }
			end
			return IR.new(Variant.If, chain)
		elseif variant == nv.While then
			return IR.new(Variant.While, { assembleNode(data[1]), assembleNode(data[2]) })
		elseif variant == nv.Call then -- todo arguments
			local fn = assert(current.data[data[1]], "Calling nonexistant function: " .. data[1])
			return IR.new(Variant.Call, { fn, {} })
		elseif variant == nv.Add then
			return IR.new(Variant.Add, { assembleNode(data[1]), assembleNode(data[2]) })
		elseif variant == nv.Sub then
			return IR.new(Variant.Sub, { assembleNode(data[1]), assembleNode(data[2]) })
		elseif variant == nv.Mul then
			return IR.new(Variant.Mul, { assembleNode(data[1]), assembleNode(data[2]) })
		elseif variant == nv.Div then
			return IR.new(Variant.Div, { assembleNode(data[1]), assembleNode(data[2]) })
		elseif variant == nv.And then
			return IR.new(Variant.And, { assembleNode(data[1]), assembleNode(data[2]) })
		elseif variant == nv.Or then
			return IR.new(Variant.Or, { assembleNode(data[1]), assembleNode(data[2]) })
		elseif variant == nv.Negate then
			return IR.new(Variant.Negate, assembleNode(data))
		elseif variant == nv.Literal then
			return IR.new(Variant.Literal, { data[1], data[2] })
		elseif variant == nv.Identifier then
			return IR.new(Variant.Identifier, data)
		else
			error("Unhandled assembler instruction: " .. tostring(node))
		end

		return node
	end

	return IR.new(Variant.Module, {"main", assembleNode(ast)})
end

return {
	assemble = assemble,

	IR = IR,
	Variant = Variant,
}