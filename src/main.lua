package.path = package.path .. ";src/?.lua"

local Lexer = require "compiler.lexer"
local Parser = require "compiler.parser"
local Optimizer = require "compiler.optimizer"
local Assembler = require "compiler.assembler"

local Interpreter = require "compiler.interpreter"

local lua = require "targets.lua"

local tokens = Lexer.lex([[
	const intrinsics = import("intrinsics")

	intrinsics.emit("foo")

	// let x = 5
	// return test(5)

	// let x = intrinsics.emit
	// let y = x("f")

	// const foo = struct {
	// 	y: i32
	// }

	// let x = foo {
	// 	y: 1
	// }

	// let x = 5 + 26 * 63

	// let x = std.print
]])

local handle = assert(io.open("src/targets/lua/std.simpl"), "Couldn't get std")
local std = handle:read("*a")
handle:close()

local std_ir = Assembler.assemble(Parser.parse(Lexer.lex(std)))

local ast = Parser.parse(tokens)
local ir = Assembler.assemble(ast, { ["std"] = std_ir })

local oir = Optimizer.optimize(ir)

local x = Interpreter.new():build()
x:eval(oir)

for k, v in pairs(x.scope.vars) do
	print("out", k, v.emit)
end

local out = io.open("foo.lua", "wb")
out:write(lua.generate(oir))
out:close()

--[[local bin = JVM.generate(program)

local out = io.open("SimpleJ.class", "wb")
out:write(bin)
out:close()]]