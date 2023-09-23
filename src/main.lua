package.path = package.path .. ";src/?.lua"

local Lexer = require "compiler.lexer"
local Parser = require "compiler.parser"
local Optimizer = require "compiler.optimizer"
local Assembler = require "compiler.assembler"

local lua = require "targets.lua"

local ast = Parser.parse(Lexer.lex(io.open("src/main.lum", "rb"):read("*a")))

local function sort_values(a, b)
	if type(a) == "number" and type(b) == "number" then
		return a < b
	else
		return tostring(a) < tostring(b)
	end
end

local function dump(object, depth, dumped)
	depth = depth or 0

	if dumped then
		local ref_depth = dumped[object]
		if ref_depth then
			return "<self " .. ref_depth .. ">"
		end
	else
		dumped = {}
	end

	local obj_type = type(object)

	if obj_type == "table" then
		local keys = {}

		do
			local idx = 1
			for key, v in pairs(object) do
				keys[idx] = key
				idx = idx + 1
			end
		end

		table.sort(keys, sort_values)

		depth = depth + 1

		local output = {'{'}
		local indent = string.rep(' ', depth * 4)

		dumped[object] = depth
		for k, key in pairs(keys) do
			local ty, value = type(key), object[key]
			if ty == "number" then
				key = '[' .. key .. ']'
			elseif ty ~= "string" then
				key = '[' .. tostring(key) .. ']'
			end
			output[k + 1] = indent .. key .. " = " .. dump(value, depth, dumped) .. ','
		end
		dumped[object] = nil

		depth = depth - 1

		-- string.sub is faster than doing string.rep again. Remove the last 4 chars (indent)
		output[#output + 1] = string.sub(indent, 1, -4) .. '}'

		return table.concat(output, '\n')
	elseif obj_type == "string" then
		return '"' .. object .. '"'
	else
		return tostring(object)
	end
end

print( dump(ast) )

local math_ir = Assembler.assemble(Parser.parse(Lexer.lex(io.open("src/targets/lua/math.lum"):read("*a"))))
local std_ir = Assembler.assemble(Parser.parse(Lexer.lex(io.open("src/targets/lua/std.lum"):read("*a"))), { ["math"] = math_ir })

local ir = Assembler.assemble(ast, { ["std"] = std_ir })


local code = lua.generate(ir)
print(code)
loadstring(code)()

--[[local out = io.open("foo.lua", "wb")
out:write(lua.generate(ir))
out:close()]]