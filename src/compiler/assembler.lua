-- Basically a second AST, with more info.
-- Compiles to a bunch of instructions, which can then be tweaked with optimizer.
local Parser = require "compiler.parser"
local NodeVariant = Parser.Variant

local IR = require "compiler.assembler.ir"
local Variant = IR.Variant

local Type = require "compiler.assembler.type"
local Natives, Fn, Struct = Type.Natives, Type.Fn, Type.Struct

local Interpreter = require "compiler.interpreter"

---@class Scope
---@field vars table<string, IRVariable>
---@field parent Scope?
---@field const boolean
---@field dead boolean
---@field can_return boolean
---@field returned IR
local Scope = {}
Scope.__index = Scope

---@param var string
---@return IRVariable?
function Scope:find(var)
	return self.vars[var] or (self.parent and self.parent:find(var))
end

---@param name string
---@return Scope? scope, any val
function Scope:attr(name)
	if self[name] ~= nil then
		return self, self[name]
	elseif self.parent then
		return self.parent:attr(name)
	end
end

---@param parent Scope?
---@return Scope
function Scope.new(parent)
	return setmetatable({ vars = {}, const = false, parent = parent }, Scope)
end

local INTRINSICS = {
	Type = Struct {
		emit = Fn({Natives.string}, Natives.void, true)
	},

	Value = {
		emit = function(args) -- do nothing, interpreter.
			local code = args[1]
		end
	}
}

---@param ast Node
---@param imports table<string, IR>?
---@return IR
local function assemble(ast, imports)
	imports = imports or {}

	imports.intrinsics = IR.new(Variant.Literal, { [2] = INTRINSICS.Value }, INTRINSICS.Type)

	---@type IR[] # Injected ir into header for import reuse
	local header = {}

	---@type table<string, IR>
	local import_cache = {}

	local const_rt = Interpreter.new()
		:withVariables({
			__importintrinsics = INTRINSICS.Value,
			import = function(args)
				local path = args[1]

				if import_cache[path] then
					return import_cache[path]
				end

				if imports[path] then
					local module = imports[path]
					header[#header + 1] = IR.new(Variant.Declare, {true, "__import" .. path, module})

					local ref = IR.new(Variant.Identifier, "__import" .. path, module.type, module.const)
					import_cache[path] = ref

					return ref
				end

				error("Couldn't find module '" .. tostring(path) .. "'")
			end
		})
		:build()

	local core = Scope.new() -- compiler -> core -> std

	core.vars.import = IR.Variable.new(Fn({Natives.string}, Natives.ir, true))
	core.vars.__raw__emit = IR.Variable.new(Fn({Natives.string}, Natives.ir), true)

	local current = Scope.new(core)

	---@generic T, T2
	---@param fn fun(scope: Scope): T?, T2?
	---@return T?, T2?
	local function scope(fn)
		current = Scope.new(current)
		local ret = fn(current)
		current = current.parent
		return ret
	end

	---@param node Node
	local function assembleNode(node)
		local variant, data = node.variant, node.data
		if variant == NodeVariant.Module then
			current.can_return = true
			return assembleNode(data)
		elseif variant == NodeVariant.Block then
			local const, nodes = data[1], data[2]
			local items = scope(function(scope)
				scope.const = const
				local items = {} ---@type IR[]
				for i, item in ipairs(nodes) do
					if scope.dead then
						print("Warning: Dead code on ", item)
						break
					else
						items[i] = assembleNode(item)
						-- print("dead?", scope.dead, items[i])
					end
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
		elseif variant == NodeVariant.Fn then ---@cast data { [1]: table, [2]: string, [3]: { [1]: string, [2]: string }[] }
			local attrs, name, param_types = data[1], data[2], {}
			for k, param in ipairs(data[3]) do
				param_types[k] = Type.from(param[2])
			end

			local block, returned = scope(function(scope)
				scope.can_return = true
				scope.const = attrs.const ~= nil

				for _, param in ipairs(data[3]) do
					scope.vars[param[1]] = IR.Variable.new(Type.from(param[2]))
				end

				return assembleNode(data[4]), scope.returned
			end)

			local ty = Fn(param_types, returned and returned.type or Natives.void, attrs.const ~= nil)
			current.vars[name] = IR.Variable.new(ty, attrs.const ~= nil)

			local ir = IR.new(Variant.Fn, { attrs, name, data[3], block })
			if attrs.const ~= nil then -- Register function in const runtime.
				const_rt:eval(ir)
			end

			return ir
		elseif variant == NodeVariant.Return then
			local scope = assert(current:attr("can_return"), "Cannot return from current scope")

			local ret = assembleNode(data)
			scope.returned = ret

			local s = current
			while s ~= scope do -- Recurse upward scopes marking dead, until reaching initial function scope
				assert(s, "Unreachable")
				s.dead = true
				s = s.parent
			end

			return IR.new(Variant.Return, ret)
		elseif variant == NodeVariant.Declare then
			local const, name, expr = data[1], data[2], assembleNode(data[3])
			assert(not current.vars[name], "Cannot re-declare existing variable " .. name)

			current.vars[name] = IR.Variable.new(expr.type, const)

			local decl = IR.new(Variant.Declare, { const, name, expr })
			if const then
				const_rt:eval(decl)
			end

			return decl
		elseif variant == NodeVariant.Assign then
			local name, expr = data[1], assembleNode(data[2])

			local expected = assert(current:find(name), "Variable " .. name .. " does not exist")
			assert(expected.type == expr.type, "Cannot assign type " .. tostring(expr.type) .. " to variable of " .. tostring(expected.type))

			return IR.new(Variant.Assign, { data[1], assembleNode(data[2]) })
		elseif variant == NodeVariant.Call then
			local fn = assembleNode(data[1])
			assert(fn.type.variant == Type.Variant.Function, "Cannot call variable of type " .. tostring(fn.type))

			if fn.type.union.const then
				-- assert(current:attr("const"), "Cannot call constant fn (" .. data[1] .. ") outside of constant context")

				---@type any[], Type[]
				local args, argtypes = {}, {}
				for k, arg in ipairs(data[2]) do
					local ir = assembleNode(arg)
					assert(ir.const, "Cannot call constant function (" .. tostring(fn.type) .. ") with runtime argument (" .. tostring(arg) .. ")")
					args[k], argtypes[k] = ir.const, ir.type
				end

				local got = Fn(argtypes, Natives.any)
				assert(fn.type == got, "Calling constant function with incorrect parameters: Expected " .. tostring(fn.type) .. ", got " .. tostring(got))

				local args = {}
				for k, arg in ipairs(data[2]) do
					args[k] = assembleNode(arg)
				end

				local ir = IR.new(Variant.Call, { fn, args })
				local val = const_rt:eval(ir)

				if fn.type.union.ret == Natives.ir then
					return assert(val, "??")
				else
					return IR.new(Variant.Literal, { fn.type.union.ret, val }, fn.type.union.ret)
				end
			else
				assert(not current:attr("const"), "Cannot call non-constant fn (" .. tostring(fn.type) .. ") in constant context")

				local args, argtypes = {}, {}
				for k, arg in ipairs(data[2]) do
					local ir = assembleNode(arg)
					args[k], argtypes[k] = ir, ir.type
				end

				local got = Fn(argtypes, Natives.any)
				assert(fn.type == got, "Calling function with incorrect parameters: Expected " .. tostring(fn.type) .. ", got " .. tostring(got))

				return IR.new(Variant.Call, { fn, args })
			end
		elseif variant == NodeVariant.Index then
			local struct = assembleNode(data[1])
			assert(struct.type.variant == Type.Variant.Struct, "Cannot index type " .. tostring(struct.type))

			local field = data[2]
			local ty = assert(struct.type.union.fields[field], "Struct " .. tostring(struct.type) .. " does not have field " .. field )

			return IR.new(Variant.Index, { assembleNode(data[1]), field }, ty)
		elseif variant == NodeVariant.Add then
			local lhs, rhs = assembleNode(data[1]), assembleNode(data[2])
			assert(lhs.type == rhs.type, "Cannot add differing types (" .. tostring(lhs.type) .. " and " .. tostring(rhs.type) .. ")")
			assert(lhs.type == Natives.string or lhs.type == Natives.integer or lhs.type == Natives.float, "Cannot add type: " .. tostring(lhs.type))
			return IR.new(Variant.Add, { lhs, rhs }, lhs.type, current:attr("const") and (lhs.const + rhs.const))
		elseif variant == NodeVariant.Sub then
			local lhs, rhs = assembleNode(data[1]), assembleNode(data[2])
			assert(lhs.type == rhs.type, "Cannot subtract differing types (" .. tostring(lhs.type) .. " and " .. tostring(rhs.type) .. ")")
			assert(lhs.type == Natives.integer or lhs.type == Natives.float, "Cannot subtract type: " .. tostring(lhs.type))
			return IR.new(Variant.Sub, { lhs, rhs }, lhs.type)
		elseif variant == NodeVariant.Mul then
			local lhs, rhs = assembleNode(data[1]), assembleNode(data[2])
			assert(lhs.type == rhs.type, "Cannot multiply differing types (" .. tostring(lhs.type) .. " and " .. tostring(rhs.type) .. ")")
			assert(lhs.type == Natives.integer or lhs.type == Natives.float, "Cannot multiply type: " .. tostring(lhs.type))
			return IR.new(Variant.Mul, { lhs, rhs }, lhs.type)
		elseif variant == NodeVariant.Div then
			local lhs, rhs = assembleNode(data[1]), assembleNode(data[2])
			assert(lhs.type == rhs.type, "Cannot divide differing types (" .. tostring(lhs.type) .. " and " .. tostring(rhs.type) .. ")")
			assert(lhs.type == Natives.integer or lhs.type == Natives.float, "Cannot divide type: " .. tostring(lhs.type))
			return IR.new(Variant.Div, { lhs, rhs }, lhs.type)
		elseif variant == NodeVariant.And then
			local lhs, rhs = assembleNode(data[1]), assembleNode(data[2])
			assert(lhs.type == Natives.boolean and rhs.type == Natives.boolean, "Can only perform logical AND operation on booleans")
			return IR.new(Variant.And, { lhs, rhs }, lhs.type)
		elseif variant == NodeVariant.Or then
			local lhs, rhs = assembleNode(data[1]), assembleNode(data[2])
			assert(lhs.type == Natives.boolean and rhs.type == Natives.boolean, "Can only perform logical OR operation on booleans")
			return IR.new(Variant.Or, { lhs, rhs }, lhs.type)
		elseif variant == NodeVariant.Negate then
			local exp = assembleNode(data)
			assert(exp.type == Natives.integer or exp.type == Natives.float, "Cannot negate type " .. tostring(exp.type))
			return IR.new(Variant.Negate, exp, exp.type)
		elseif variant == NodeVariant.Literal then
			local ty = Type.from(data[1])
			return IR.new(Variant.Literal, { ty, data[2] }, ty, data[2])
		elseif variant == NodeVariant.Identifier then ---@cast data string
			local var = assert(current:find(data), "Variable " .. data .. " does not exist")
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