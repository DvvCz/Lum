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

	If = 3,
	While = 4,
	Fn = 5,

	Assign = 6,
	Declare = 7,

	Call = 8,

	Negate = 9,

	Add = 10,
	Sub = 11,
	Mul = 12,
	Div = 13,

	And = 14,
	Or = 15,

	Literal = 16, -- "" 22 22.0
	Identifier = 17
}

---@class Scope
---@field vars table<string, IRVariable>
---@field parent Scope?
local Scope = {}
Scope.__index = Scope

---@param var string
---@return IRVariable?
function Scope:find(var)
	return self.vars[var] or (self.parent and self.parent:find(var))
end

---@return Scope
function Scope.new(parent)
	return setmetatable({ vars = {}, parent = parent }, Scope)
end

---@param ast Node
---@return IR
local function assemble(ast)
	local current = Scope.new()

	---@generic T
	---@param fn fun(scope: table<string, IRVariable>): T?
	---@return T
	local function scope(fn)
		current = setmetatable({ vars = {}, parent = current }, Scope)
		local ret = fn(current)
		current = current.parent
		return ret
	end

	---@return string type
	local function typeNode(node)
		local variant, nv = node.variant, NodeVariant

		if variant == nv.Add then
			local lhs_ty, rhs_ty = typeNode(node.data[1]), typeNode(node.data[2])
			assert(lhs_ty == rhs_ty, "Cannot add differing types (" .. lhs_ty .. " and " .. rhs_ty .. ")")
			assert(lhs_ty == "int" or lhs_ty == "float" or lhs_ty == "string", "Cannot add type: " .. lhs_ty)
			return lhs_ty
		elseif variant == nv.Sub then
			local lhs_ty, rhs_ty = typeNode(node.data[1]), typeNode(node.data[2])
			assert(lhs_ty == rhs_ty, "Cannot subtract differing types (" .. lhs_ty .. " and " .. rhs_ty .. ")")
			assert(lhs_ty == "int" or lhs_ty == "float" or lhs_ty == "string", "Cannot subtract type: " .. lhs_ty)
			return lhs_ty
		elseif variant == nv.Mul then
			local lhs_ty, rhs_ty = typeNode(node.data[1]), typeNode(node.data[2])
			assert(lhs_ty == rhs_ty, "Cannot multiply differing types (" .. lhs_ty .. " and " .. rhs_ty .. ")")
			assert(lhs_ty == "int" or lhs_ty == "float" or lhs_ty == "string", "Cannot multiply type: " .. lhs_ty)
			return lhs_ty
		elseif variant == nv.Div then
			local lhs_ty, rhs_ty = typeNode(node.data[1]), typeNode(node.data[2])
			assert(lhs_ty == rhs_ty, "Cannot divide differing types (" .. lhs_ty .. " and " .. rhs_ty .. ")")
			assert(lhs_ty == "int" or lhs_ty == "float" or lhs_ty == "string", "Cannot divide type: " .. lhs_ty)
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
			if current.vars[data[1]] then
				error("Cannot re-declare existing variable " .. data[1])
			else
				current.vars[data[1]] = IRVariable.new(typeNode(data[2]))
				return IR.new(Variant.Declare, { data[1], assembleNode(data[2]) })
			end
		elseif variant == nv.Assign then
			local expected, got = assert(current:find(data[1]), "Variable " .. node.data[1] .. " does not exist"), typeNode(node.data[2])
			assert(expected.type == got, "Cannot assign type " .. got .. " to variable of " .. expected.type)
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
		elseif variant == nv.Fn then -- todo verify types are valid
			local name, param_types = data[1], {}
			for k, param in ipairs(data[2]) do
				param_types[k] = param[2]
			end
			current.vars[name] = IRVariable.new("fn(" .. table.concat(param_types) .. ")")
			return IR.new(Variant.Fn, { data[1], data[2], assembleNode(data[3]) })
		elseif variant == nv.Call then -- todo arguments
			local fn = assert(current:find(data[1]), "Calling nonexistant function: " .. data[1])

			local args, argtypes = {}, {}
			for k, arg in ipairs(data[2]) do
				args[k], argtypes[k] = assembleNode(arg), typeNode(arg)
			end

			local sig = "fn(" .. table.concat(argtypes, ",") .. ")"
			assert(fn.type == sig, "Calling function with incorrect parameters: Expected " .. fn.type .. ", got " .. sig)

			return IR.new(Variant.Call, { data[1], args })
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