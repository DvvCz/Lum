package.path = package.path .. ";src/?.lua"

local Lexer = require "compiler.lexer"
local Parser = require "compiler.parser"
local Optimizer = require "compiler.optimizer"
local Assembler = require "compiler.assembler"

local Interpreter = require "compiler.interpreter"

local lua = require "targets.lua"

local tokens = Lexer.lex(io.open("src/main.lum", "rb"):read("*a"))

local handle = assert(io.open("src/targets/lua/std.lum"), "Couldn't get std")
local std = handle:read("*a")
handle:close()

local std_ir = Assembler.assemble(Parser.parse(Lexer.lex(std)))

local ast = Parser.parse(tokens)
local ir = Assembler.assemble(ast, { ["std"] = std_ir })

local out = io.open("foo.lua", "wb")
out:write(lua.generate(ir))
out:close()