-- Basically a second AST, with more info.
-- Compiles to a bunch of instructions, which can then be tweaked with optimizer.
local Parser = require "compiler.parser"
local NodeVariant = Parser.Variant

local IR = require "compiler.assembler.ir"
local Variant = IR.Variant

local Type = require "compiler.assembler.type"
local Natives, Fn, Struct, Ty = Type.Natives, Type.Fn, Type.Struct, Type.Ty

local Interpreter = require "compiler.interpreter"

---@class Scope
---@field vars table<string, IRVariable>
---@field parent Scope?
---@field const boolean
---@field dead boolean
---@field fn boolean
---@field module boolean
---@field returned IR? # ir for if scope.fn or scope.module are defined and there was a return value.
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
		emit = Fn({Natives.string}, Natives.ir, true)
	},

	Value = {
		emit = function(args) -- do nothing, interpreter.
			local code = args[1]
			return IR.new(Variant.Emit, code)
		end
	}
}

---@param ast Node
---@param imports table<string, IR>?
---@return IR
local function assemble(ast, imports)
	imports = imports or {}

	imports.intrinsics = IR.new(Variant.Literal, { [1] = INTRINSICS.Type, [2] = INTRINSICS.Value }, INTRINSICS.Type)

	---@type IR[] # Injected ir into header for import reuse
	local header = {}

	---@type table<string, IR>
	local import_cache = {}

	local const_rt
	const_rt = Interpreter.new()
		:withVariables({
			__importintrinsics = INTRINSICS.Value,
			import = function(args)
				local path = args[1]

				if import_cache[path] then
					return import_cache[path]
				end

				if imports[path] then
					local module = imports[path]

					local ir = IR.new(Variant.Declare, {false, "__import" .. path, module})
					header[#header + 1] = ir
					--[[const_rt:eval(ir)]]

					--[[local ref = IR.new(Variant.Identifier, "__import" .. path, module.type, module.const)
					import_cache[path] = ref

					print(path, ref)]]

					return module
				end

				error("Couldn't find module '" .. tostring(path) .. "'")
			end,

			integer = Natives.integer,
			boolean = Natives.boolean,
			float = Natives.float,
			string = Natives.string,
			void = Natives.void
		})
		:build()

	local core = Scope.new() -- compiler -> core -> std

	core.vars.import = IR.Variable.new(Fn({Natives.string}, Natives.ir, true))

	core.vars.integer = IR.Variable.new(Ty(Natives.integer), true)
	core.vars.float = IR.Variable.new(Ty(Natives.float), true)
	core.vars.string = IR.Variable.new(Ty(Natives.string), true)
	core.vars.boolean = IR.Variable.new(Ty(Natives.boolean), true)
	core.vars.void = IR.Variable.new(Ty(Natives.void), true)

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
			current.module = true
			return IR.new(Variant.Module, { "main", assembleNode(data) }, current.returned and current.returned.type)
		elseif variant == NodeVariant.Block then
			local items = scope(function(scope)
				local items = {} ---@type IR[]
				for i, item in ipairs(data) do
					if scope.dead then
						print("Warning: Dead code on ", item)
						break
					else
						local r = assembleNode(item)
						if r ~= false then
							items[#items + 1] = r
						end
						-- print("dead?", scope.dead, items[i])
					end
				end
				return items
			end)

			return IR.new(Variant.Scope, items)
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
				scope.fn = true
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
			local ret = assembleNode(data)

			local scope = assert(current:attr("function") or current:attr("module"))
			if scope.returned then
				assert(scope.returned.type == ret.type, "Cannot return type " .. tostring(ret.type) .. " in scope that returns " .. tostring(scope.returned.type))
			else
				scope.returned = ret
			end

			-- local scope = assert(current:attr("can_return"), "Cannot return from current scope")

			local s = current
			while s ~= scope do -- Recurse upward scopes marking dead, until reaching initial function scope
				assert(s, "Unreachable")
				s.dead = true
				s = s.parent
			end

			local ir = IR.new(Variant.Return, ret)
			if current:attr("module") then
				const_rt:eval(ir)
			end
			return ir
		elseif variant == NodeVariant.Declare then
			local const, name, expr = data[1], data[2], assembleNode(data[3])
			assert(not current.vars[name], "Cannot re-declare existing variable " .. name)

			assert(expr.type ~= Natives.void, "Cannot assign value of void to variable " .. name)
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
				---@type any[], Type[]
				local args, argtypes = {}, {}
				for k, arg in ipairs(data[2]) do
					local ir = assembleNode(arg)
					-- assert(ir.const, "Cannot call constant function (" .. tostring(fn.type) .. ") with runtime argument (" .. tostring(arg) .. ")")
					args[k], argtypes[k] = ir, ir.type
				end

				local got = Fn(argtypes, Natives.any)
				assert(fn.type == got, "Calling constant function with incorrect parameters: Expected " .. tostring(fn.type) .. ", got " .. tostring(got))

				local ir = IR.new(Variant.Call, { fn, args })
				local val = const_rt:eval(ir)

				if fn.type.union.ret == Natives.ir then
					return assert(val, "Constant function (" .. tostring(fn.type) .. ") expecting return of ir returned nothing")
				else
					return IR.new(Variant.Literal, { fn.type.union.ret, val }, fn.type.union.ret)
				end
			else
				assert(not select(2, current:attr("const")), "Cannot call non-constant fn (" .. tostring(fn.type) .. ") in constant context")

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

			local ir = IR.new(Variant.Add, { lhs, rhs }, lhs.type)
			if select(2, current:attr("const")) then
				return IR.new(Variant.Literal, { lhs.type, const_rt:eval(ir) })
			end

			return ir
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
		elseif variant == NodeVariant.StructInstance then
			local name, fields = data[1], {}

			if name then
				local struct = assert(current:find(name), "Invalid type to instantiate (" .. tostring(data[1]) .. ")")
				assert(struct.const, "Type must be constant")
				assert(struct.type.variant == Type.Variant.Struct, "Cannot instantiate non-struct type (" .. tostring(struct.type) .. ")")

				for _, field in ipairs(data[2]) do
					local key, expr = field[1], assembleNode(field[2])
					assert(expr.type == struct.type.union.fields[key], "Cannot set field " .. key .. " to value of type " .. tostring(expr.type))
					fields[key] = expr
				end

				return IR.new(Variant.StructInstance, { struct.type, fields }, struct.type)
			else -- Anonymous struct
				local field_types = {}
				for _, field in ipairs(data[2]) do
					local key, expr = field[1], assembleNode(field[2])
					fields[key], field_types[key] = expr, expr.type
				end

				return IR.new(Variant.StructInstance, { nil, fields }, Struct(field_types))
			end
		elseif variant == NodeVariant.Struct then
			local fields = {}

			for _, field in ipairs(data) do
				local ty = assert(current:find(field[2]), "Variable " .. field[2] .. " does not exist")
				assert(ty.const, "Type must be constant")
				assert(ty.type.variant == Type.Variant.Type, "Cannot use non-type as struct type")
				fields[field[1]] = ty.type.union.type
			end

			return IR.new(Variant.Struct, fields, Struct(fields))
		elseif variant == NodeVariant.Identifier then ---@cast data string
			local var = assert(current:find(data), "Variable " .. data .. " does not exist")
			return IR.new(Variant.Identifier, data, var.type, var.val)
		else
			error("Unhandled assembler instruction: " .. tostring(node))
		end
	end

	local module = assembleNode(ast)
	for i = #header, 1, -1 do
		table.insert(module.data[2].data, 1, header[i])
	end

	return module
end

return {
	assemble = assemble,

	IR = IR,
	Variant = Variant,
}