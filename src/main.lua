package.path = package.path .. ";src/?.lua"

local Lexer = require "compiler.lexer"
local Parser = require "compiler.parser"
local Optimizer = require "compiler.optimizer"
local Assembler = require "compiler.assembler"

local lua = require "targets.lua"

local tokens = Lexer.lex([[
	let std = const { import("std") }

	fn foo() {}

	foo()

	// let x = std.print
]])

local handle = assert(io.open("src/targets/lua/std.simpl"), "Couldn't get std")
local std = handle:read("*a")
handle:close()

local std_ir = Assembler.assemble(Parser.parse(Lexer.lex(std)))

local ast = Parser.parse(tokens)
local ir = Assembler.assemble(ast, { ["std"] = std_ir })

local oir = Optimizer.optimize(ir)

local out = io.open("foo.lua", "wb")
out:write(lua.generate(oir))
out:close()

--[[local bin = JVM.generate(program)

local out = io.open("SimpleJ.class", "wb")
out:write(bin)
out:close()]]