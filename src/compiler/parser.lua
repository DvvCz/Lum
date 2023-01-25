local lexer = require "compiler.lexer"
local TokenDebugVariant, TokenVariant = lexer.DebugVariant, lexer.Variant

---@enum NodeVariant
local Variant = {
	Block = 0,
	If = 1, -- if <exp> {}
	While = 2, -- while <exp> {}

	Assign = 2, -- x = 5
	Declare = 3, -- let x = 5

	Negate = 4,

	Add = 5,
	Sub = 6,
	Mul = 7,
	Div = 8,

	And = 9,
	Or = 10,

	Literal = 11, -- "" 22 22.0
}

local DebugVariant = {}
for k, v in pairs(Variant) do
	DebugVariant[v] = k
end

local NodeMeta = {}
function NodeMeta:__tostring()
	return "Node { variant: " .. (DebugVariant[self.variant] or "??") .. ", data: " .. tostring(self.data) .. " }"
end

---@class Node
---@field variant NodeVariant
---@field data table

local function Node(data)
	return setmetatable(data, NodeMeta)
end

---@param tokens Token[]
local function parse(tokens)
	local index, len = 1, #tokens

	---@param variant TokenVariant
	---@return Token
	local function consume(variant, data)
		local token = tokens[index]
		assert(token, "Expected " .. TokenDebugVariant[variant] .. ", got EOI")
		assert(token.variant == variant, "Expected " .. TokenDebugVariant[variant] .. " (" .. tostring(data) .. "), got " .. TokenDebugVariant[token.variant] .. " (" .. tostring(token.data) .. ")")
		if data ~= nil then assert(token.data == data, "Expected " .. data .. ", got " .. tostring(token.data)) end
		index = index + 1
		return token
	end

	---@param variant TokenVariant
	---@return Token?
	local function optConsume(variant, data)
		local token = tokens[index]
		if token and token.variant == variant then
			if data ~= nil and data ~= token.data then return end
			index = index + 1
			return token
		end
	end

	local function prim()
		local data = optConsume(TokenVariant.Integer)
		if data then
			return Node { variant = Variant.Literal, data = { "int", data.data } }
		end

		data = optConsume(TokenVariant.Float)
		if data then
			return Node { variant = Variant.Literal, data = { "float", data.data } }
		end

		data = optConsume(TokenVariant.String)
		if data then
			return Node { variant = Variant.Literal, data = { "string", data.data } }
		end

		data = optConsume(TokenVariant.Boolean)
		if data then
			return Node { variant = Variant.Literal, data = { "boolean", data.data } }
		end
	end

	local function expr()
		if optConsume(TokenVariant.Operator, "-") then
			return Node { variant = Variant.Negate, data = expr() }
		end

		local lhs
		if optConsume(TokenVariant.Operator, "(") then
			lhs = expr()
			consume(TokenVariant.Operator, ")")
		else
			lhs = prim()
		end

		if optConsume(TokenVariant.Operator, "+") then
			return Node { variant = Variant.Add, data = { lhs, assert(expr(), "Expected rhs expression for addition") } }
		elseif optConsume(TokenVariant.Operator, "-") then
			return Node { variant = Variant.Sub, data = { lhs, assert(expr(), "Expected rhs expression for subtraction") } }
		elseif optConsume(TokenVariant.Operator, "*") then
			return Node { variant = Variant.Mul, data = { lhs, assert(expr(), "Expected rhs expression for multiplication") } }
		elseif optConsume(TokenVariant.Operator, "/") then
			return Node { variant = Variant.Div, data = { lhs, assert(expr(), "Expected rhs expression for division") } }
		elseif optConsume(TokenVariant.Operator, "&&") then
			return Node { variant = Variant.And, data = { lhs, assert(expr(), "Expected rhs expression for AND") } }
		elseif optConsume(TokenVariant.Operator, "||") then
			return Node { variant = Variant.Or, data = { lhs, assert(expr(), "Expected rhs expression for OR") } }
		end

		return lhs
	end

	local stmt
	local function block(no_bracket)
		if not no_bracket then consume(TokenVariant.Operator, "{") end

		local stmts = {}
		while index < len do
			if not no_bracket and optConsume(TokenVariant.Operator, "}") then break end
			stmts[#stmts + 1] = assert(stmt(), "Failed to parse token " .. tostring(tokens[index]))
		end

		return Node { variant = Variant.Block, data = stmts }
	end

	function stmt()
		if optConsume(TokenVariant.Keyword, "if") then
			return Node { variant = Variant.If, data = { assert(expr(), "Expected expression after if statement"), block() } }
		elseif optConsume(TokenVariant.Keyword, "while") then
			return Node { variant = Variant.While, data = { assert(expr(), "Expected expression for while loop"), block() } }
		elseif optConsume(TokenVariant.Keyword, "let") then
			local name = consume(TokenVariant.Identifier)
			consume(TokenVariant.Operator, "=")
			return Node { variant = Variant.Declare, data = { name, assert(expr(), "Expected expression for declaration of " .. name.data) } }
		end
	end

	return block(true)
end

return {
	Variant = Variant,
	DebugVariant = DebugVariant,
	parse = parse
}