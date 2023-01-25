package.path = package.path .. ";src/?.lua"

local Lexer = require "compiler.lexer"
local Parser = require "compiler.parser"
local Optimizer = require "compiler.optimizer"

local tokens = Lexer.lex([[
	// Test
	if 22 + 55 {
		// Test
		let x = 5 + (6 * 2) * 10 - 2
	}

	while true {}
]])

local ast = Parser.parse(tokens)
local opt_ast = Optimizer.optimize(ast)

for k, v in ipairs(opt_ast) do
	print(k, v.data[1])
end

local Class = require "jvm.class"

local bin = Class.new("SimplJ")
	:withStrings { "java/lang/Object", "main", "<init>", "Code", "()V", "([Ljava/lang/String;)V" }
	:encode()

local out = io.open("SimpleJ.class", "wb")
out:write(bin)
out:close()