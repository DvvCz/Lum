-- Basically a second AST, with more info.
-- Compiles to a bunch of instructions, which can then be tweaked with optimizer.
local Parser = require "compiler.parser"
local NodeVariant = Parser.Variant

local Type = require "compiler.assembler.type"
local Natives, Fn = Type.Natives, Type.Fn

---@class IR
---@field variant IRVariant
---@field data table
---@field type Type
---@field is_const boolean
---@field const any
local IR = {}
IR.__index = IR

function IR:__tostring()
	return "IR " .. self.variant
end

---@param variant IRVariant
---@param data any
---@param type Type?
---@param const any
function IR.new(variant, data, type, const)
	return setmetatable({ variant = variant, data = data, type = type or Natives.void, const = const }, IR)
end

---@class IRVariable
---@field val any? # The value of the variable, if it could be deduced at compile time.
---@field type Type # Type of the variable (ie "integer")
---@field const boolean?
local IRVariable = {}
IRVariable.__index = IRVariable

---@param type Type
---@param const boolean?
---@param val any
function IRVariable.new(type, const, val)
	return setmetatable({ type = type, const = const, val = val }, IRVariable)
end

---@enum IRVariant
local Variant = {
	Module = 1,
	Scope = 2,

	If = 3,
	While = 4,
	Fn = 5,

	Declare = 6,
	Assign = 7,

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
---@field const boolean? # Whether inside a constant (compile time) context
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
---@param imports table<string, IR>?
---@return IR
local function assemble(ast, imports)
	imports = imports or {}

	local core = Scope.new() -- compiler -> core -> std

	---@type IR[] # Injected ir into header for import reuse
	local header = {}

	---@type table<string, IR>
	local import_cache = {}

	core.vars.import = IRVariable.new(Fn({Natives.string}, Natives.ir), true, function(args)
		local path = args[1]

		if import_cache[path] then
			return import_cache[path]
		end

		if imports[path] then
			local module = imports[path]
			header[#header + 1] = IR.new(Variant.Declare, {"__import" .. path, module})

			local ref = IR.new(Variant.Identifier, "__import" .. path, module.type, module.const)
			import_cache[path] = ref

			return ref
		end

		error("Couldn't find module '" .. path .. "'")
	end)

	core.vars.__raw__emit = IRVariable.new(Fn({Natives.string}, Natives.ir), true, function(args)
		local code = args[1]
	end)

	local current = Scope.new(core)

	---@generic T
	---@param fn fun(scope: Scope): T?
	---@return T
	local function scope(fn)
		current = Scope.new(current)
		local ret = fn(current)
		current = current.parent
		return ret
	end

	---@param node Node
	local function assembleNode(node)
		local variant, data = node.variant, node.data
		if variant == NodeVariant.Block then
			local const, nodes = data[1], data[2]
			local items = scope(function(scope)
				scope.const = const
				local items = {} ---@type IR[]
				for i, item in ipairs(nodes) do
					items[i] = assembleNode(item)
				end
				return items
			end)

			local ret = items[#items] and items[#items].type or Natives.void
			return IR.new(Variant.Scope, items, ret)
		elseif variant == NodeVariant.If then
			local chain = {}
			for i, if_else_if in ipairs(data) do
				local cond, block = if_else_if[1], if_else_if[2]
				chain[i] = { cond and assembleNode(cond), assembleNode(block) }
			end
			return IR.new(Variant.If, chain)
		elseif variant == NodeVariant.While then
			return IR.new(Variant.While, { assembleNode(data[1]), assembleNode(data[2]) })
		elseif variant == NodeVariant.Fn then -- todo verify types are valid
			local name, param_types = data[1], {}
			for k, param in ipairs(data[2]) do
				param_types[k] = param[2]
			end
			current.vars[name] = IRVariable.new(Fn(param_types, Natives.void))
			return IR.new(Variant.Fn, { data[1], data[2], assembleNode(data[3]) })
		elseif variant == NodeVariant.Declare then
			local name, expr = data[1], assembleNode(data[2])
			if current.vars[name] then
				error("Cannot re-declare existing variable " .. data[1])
			else
				current.vars[name] = IRVariable.new(expr.type, expr.is_const, expr.const)
				return IR.new(Variant.Declare, { name, expr })
			end
		elseif variant == NodeVariant.Assign then
			local name, expr = data[1], assembleNode(data[2])

			local expected = assert(current:find(name), "Variable " .. name .. " does not exist")
			assert(expected.type == expr.type, "Cannot assign type " .. tostring(expr.type) .. " to variable of " .. tostring(expected.type))

			return IR.new(Variant.Assign, { data[1], assembleNode(data[2]) })
		elseif variant == NodeVariant.Call then
			local fn = assert(current:find(data[1]), "Calling nonexistant function: " .. data[1])

			if fn.const then
				assert(current.const, "Cannot call constant fn (" .. data[1] .. ") outside of constant context")

				---@type any[], Type[]
				local args, argtypes = {}, {}
				for k, arg in ipairs(data[2]) do
					local ir = assembleNode(arg)
					assert(ir.const, "Cannot call constant function (" .. data[1] .. ") with runtime argument (" .. tostring(arg) .. ")")
					args[k], argtypes[k] = ir.const, ir.type
				end

				local got = Fn(argtypes, Natives.any)
				assert(fn.type == got, "Calling constant function with incorrect parameters: Expected " .. tostring(fn.type) .. ", got " .. tostring(got))

				if fn.type.union.ret == Natives.ir then
					return fn.val(args)
				else
					return IR.new(Variant.Literal, { fn.type.union.ret, fn.val(args) }, fn.type.union.ret)
				end
			else
				local args, argtypes = {}, {}
				for k, arg in ipairs(data[2]) do
					local ir = assembleNode(arg)
					args[k], argtypes[k] = ir, ir.type
				end

				local got = Fn(argtypes, Natives.any)
				assert(fn.type == got, "Calling function with incorrect parameters: Expected " .. tostring(fn.type) .. ", got " .. tostring(got))

				return IR.new(Variant.Call, { data[1], args })
			end
		elseif variant == NodeVariant.Add then
			local lhs, rhs = assembleNode(data[1]), assembleNode(data[2])
			assert(lhs.type == rhs.type, "Cannot add differing types (" .. tostring(lhs.type) .. " and " .. tostring(rhs.type) .. ")")
			assert(lhs.type == Natives.string or lhs.type == Natives.integer or lhs.type == Natives.float, "Cannot add type: " .. tostring(lhs.type))
			return IR.new(Variant.Add, { lhs, rhs }, lhs.type, current.const and (lhs.const + rhs.const))
		elseif variant == NodeVariant.Sub then
			local lhs, rhs = assembleNode(data[1]), assembleNode(data[2])
			assert(lhs.type == rhs.type, "Cannot subtract differing types (" .. tostring(lhs.type) .. " and " .. tostring(rhs.type) .. ")")
			assert(lhs.type == Natives.integer or lhs.type == Natives.float, "Cannot subtract type: " .. tostring(lhs.type))
			return IR.new(Variant.Sub, { lhs, rhs }, lhs.type, current.const and (lhs.const - rhs.const))
		elseif variant == NodeVariant.Mul then
			local lhs, rhs = assembleNode(data[1]), assembleNode(data[2])
			assert(lhs.type == rhs.type, "Cannot multiply differing types (" .. tostring(lhs.type) .. " and " .. tostring(rhs.type) .. ")")
			assert(lhs.type == Natives.integer or lhs.type == Natives.float, "Cannot multiply type: " .. tostring(lhs.type))
			return IR.new(Variant.Mul, { lhs, rhs }, lhs.type, current.const and (lhs.const * rhs.const))
		elseif variant == NodeVariant.Div then
			local lhs, rhs = assembleNode(data[1]), assembleNode(data[2])
			assert(lhs.type == rhs.type, "Cannot divide differing types (" .. tostring(lhs.type) .. " and " .. tostring(rhs.type) .. ")")
			assert(lhs.type == Natives.integer or lhs.type == Natives.float, "Cannot divide type: " .. tostring(lhs.type))
			return IR.new(Variant.Div, { lhs, rhs }, lhs.type, current.const and (lhs.const / rhs.const))
		elseif variant == NodeVariant.And then
			local lhs, rhs = assembleNode(data[1]), assembleNode(data[2])
			assert(lhs.type == Natives.boolean and rhs.type == Natives.boolean, "Can only perform logical AND operation on booleans")
			return IR.new(Variant.And, { lhs, rhs }, lhs.type, current.const and (lhs.const and rhs.const))
		elseif variant == NodeVariant.Or then
			local lhs, rhs = assembleNode(data[1]), assembleNode(data[2])
			assert(lhs.type == Natives.boolean and rhs.type == Natives.boolean, "Can only perform logical OR operation on booleans")
			return IR.new(Variant.Or, { lhs, rhs }, lhs.type, current.const and (lhs.const or rhs.const))
		elseif variant == NodeVariant.Negate then
			local exp = assembleNode(data)
			assert(exp.type == Natives.integer or exp.type == Natives.float, "Cannot negate type " .. tostring(exp.type))
			return IR.new(Variant.Negate, exp, exp.type, current.const and -exp.const)
		elseif variant == NodeVariant.Literal then
			local ty = Natives[data[1]]
			return IR.new(Variant.Literal, { ty, data[2] }, ty, data[2])
		elseif variant == NodeVariant.Identifier then
			---@type IRVariable
			local var = assert(current.vars[data], "Variable " .. data .. " does not exist")
			return IR.new(Variant.Identifier, data, var.type, var.val)
		else
			error("Unhandled assembler instruction: " .. tostring(node))
		end
	end

	local ir = assembleNode(ast)
	for i, imp in ipairs(header) do
		table.insert(ir.data, 1, imp)
	end

	return IR.new(Variant.Module, {"main", ir})
end

return {
	assemble = assemble,

	IR = IR,
	Variant = Variant,
}