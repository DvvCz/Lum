local ir = require "compiler.assembler"
local IRVariant = ir.Variant

---@class Target
---@field name string
---@field generate (fun(ir: IR): string)?

---@type Target
local Target = {
	name = "Lua",

	generate = function(ir)
		local function expr(ir)
			local variant, data = ir.variant, ir.data
			if variant == IRVariant.Literal then
				---@type "int"|"float"|"string"|"boolean", number|boolean|string
				local ty, val = data[1], data[2]
				if ty == "string" then
					return string.format("%q", val)
				elseif ty == val then
					return val and "true" or "false"
				else
					return tostring(val)
				end
			elseif variant == IRVariant.Identifier then
				return data
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
			elseif variant == IRVariant.Negate then
				return string.format("-%s", expr(data))
			else
				error("Unimplemented expression: " .. variant)
			end
		end

		---@param ir IR
		---@return string
		local function stmt(ir)
			local variant, data = ir.variant, ir.data
			if variant == IRVariant.Module then
				---@type string, IR
				local name, scope = data[1], data[2]
				return string.format("local %s = {}\ndo\n%s\nend\nreturn %s", name, stmt(scope), name)
			elseif variant == IRVariant.Scope then
				local buf = {}
				for i, ir in ipairs(data) do
					buf[i] = stmt(ir):gsub("\n", "\n\t")
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
				for k, param in ipairs(data[2]) do
					param_names[k] = param[1]
				end
				return string.format("local function %s(%s)\n%s\nend", data[1], table.concat(param_names, ", "), stmt(data[3]))
			elseif variant == IRVariant.Declare then
				return string.format("local %s = %s", data[1], expr(data[2]))
			elseif variant == IRVariant.Assign then
				return string.format("%s = %s", data[1], expr(data[2]))
			elseif variant == IRVariant.Call then
				local args = {}
				for k, arg in ipairs(data[2]) do
					args[k] = expr(arg)
				end
				return string.format("%s(%s)", data[1], table.concat(args, ", "))
			else
				error("Unimplemented stmt: " .. variant)
			end
		end

		return stmt(ir)
	end,
}

return Target