local IR = require "compiler.assembler.ir"
local Type = require "compiler.assembler.type"

local IRVariant, Natives = IR.Variant, Type.Natives

---@class Target
---@field name string
---@field generate (fun(ir: IR): string)?

---@type Target
local Target = {
	name = "Lua",

	generate = function(ir)
		local stmt
		---@param ir IR
		---@return string
		local function expr(ir)
			local variant, data = ir.variant, ir.data
			if variant == IRVariant.Module then
				local buf = {}
				for i, ir in ipairs(data[2]) do
					local out = stmt(ir)
					if out ~= false then
						buf[i] = out:gsub("\n", "\n")
					end
				end
				return string.format("(function()\n%s\nend)()", table.concat(buf, "\n\t"))
			elseif variant == IRVariant.Call then
				local args = {}
				for k, arg in ipairs(data[2]) do
					args[k] = expr(arg)
				end
				return string.format("(%s)(%s)", expr(data[1]), table.concat(args, ", "))
			elseif variant == IRVariant.Index then
				return string.format("%s.%s", expr(data[1]), data[2])
			elseif variant == IRVariant.Negate then
				return string.format("-%s", expr(data))
			elseif variant == IRVariant.Add then
				return string.format("(%s + %s)", expr(data[1]), expr(data[2]))
			elseif variant == IRVariant.Sub then
				return string.format("(%s - %s)", expr(data[1]), expr(data[2]))
			elseif variant == IRVariant.Mul then
				return string.format("(%s * %s)", expr(data[1]), expr(data[2]))
			elseif variant == IRVariant.Div then
				return string.format("(%s / %s)", expr(data[1]), expr(data[2]))
			elseif variant == IRVariant.And then
				return string.format("(%s and %s)", expr(data[1]), expr(data[2]))
			elseif variant == IRVariant.Or then
				return string.format("(%s or %s)", expr(data[1]), expr(data[2]))
			elseif variant == IRVariant.Eq then
				return string.format("(%s == %s)", expr(data[1]), expr(data[2]))
			elseif variant == IRVariant.NotEq then
				return string.format("(%s ~= %s)", expr(data[1]), expr(data[2]))
			elseif variant == IRVariant.Literal then ---@cast data number|boolean|string
				if ir.type == Natives.string then
					return string.format("%q", data)
				elseif ir.type == Natives.boolean then
					return data and "true" or "false"
				elseif ir.type.variant == Type.Variant.Struct then
					return "struct"
				else
					return tostring(data)
				end
			elseif variant == IRVariant.StructInstance then ---@cast data { [1]: Type, [2]: table<string, IR> }
				local buf = {}

				for key, value in pairs(data[2]) do
					buf[#buf + 1] = key .. " = " .. expr(value)
				end

				return "{" .. table.concat(buf, ",") .. "}"
			elseif variant == IRVariant.Identifier then
				return data
			else
				error("Unimplemented expression: " .. tostring(variant))
			end
		end

		---@param ir IR
		---@return string
		function stmt(ir)
			local variant, data = ir.variant, ir.data
			if variant == IRVariant.Module then
				---@type string, IR
				local name, scope = data[1], data[2]
				return string.format("local %s = {}\ndo\n%s\nend\nreturn %s", name, stmt(scope), name)
			elseif variant == IRVariant.Scope then
				local buf = {}
				for i, ir in ipairs(data) do
					local out = stmt(ir)
					if out ~= false then
						buf[#buf + 1] = out:gsub("\n", "\n\t")
					end
				end
				return "\t" .. table.concat(buf, "\n\t")
			elseif variant == IRVariant.If then
				local first = table.remove(data, 1)

				local buffer = { string.format("if %s then\n%s\n", expr(first[1]), stmt(first[2])) }
				for i, if_else_if in ipairs(data) do
					local condition, block = if_else_if[1], if_else_if[2]
					if condition then
						buffer[1 + i] = string.format("elseif %s then\n%s\n", expr(condition), stmt(block))
					else
						buffer[1 + i] = string.format("else\n%s\n", stmt(block))
					end
				end
				buffer[#buffer + 1] = "end"
				return table.concat(buffer)
			elseif variant == IRVariant.While then
				return string.format("while %s do\n%s\nend", expr(data[1]), stmt(data[2]))
			elseif variant == IRVariant.Fn then
				local param_names = {}
				for k, param in ipairs(data[3]) do
					param_names[k] = param[1]
				end
				return string.format("local function %s(%s)\n%s\nend", data[2], table.concat(param_names, ", "), stmt(data[4]))
			elseif variant == IRVariant.Return then
				return string.format("return %s", expr(data))
			elseif variant == IRVariant.Declare then
				if data[1] then return false end
				return string.format("local %s = %s", data[2], expr(data[3]))
			elseif variant == IRVariant.Assign then
				return string.format("%s = %s", data[1], expr(data[2]))
			elseif variant == IRVariant.Call then
				local args = {}
				for k, arg in ipairs(data[2]) do
					args[k] = expr(arg)
				end
				return string.format("(%s)(%s)", expr(data[1]), table.concat(args, ", "))
			elseif variant == IRVariant.Emit then
				return data
			else
				error("Unimplemented stmt: " .. (variant or "???"))
			end
		end

		return stmt(ir)
	end,
}

return Target