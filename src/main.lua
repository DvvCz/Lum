package.path = package.path .. ";src/?.lua"

local Lexer = require "compiler.lexer"
local Parser = require "compiler.parser"
local Optimizer = require "compiler.optimizer"
local Assembler = require "compiler.assembler"

local lua = require "targets.lua"

local tokens = Lexer.lex([[
	// Hello, world!
	let x = 5 + -2 * 2
	let y = "dd" + "xyssz"

	if true {
		foo()
	} else if false {
		let x = 4
	} else {
		foo()
	}

	while true && true {
		let x = 22
		let dd = "fffff"
		x = 55
	}
]])

local ast = Parser.parse(tokens)
local ir = Assembler.assemble(ast)
local oir = Optimizer.optimize(ir)

local out = io.open("foo.lua", "wb")
out:write(lua.generate(oir))
out:close()

--[[local bin = JVM.generate(program)

local out = io.open("SimpleJ.class", "wb")
out:write(bin)
out:close()]]