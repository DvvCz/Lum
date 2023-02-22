local lexer = require "compiler.lexer"
local TokenDebugVariant, TokenVariant = lexer.DebugVariant, lexer.Variant

---@enum NodeVariant
local Variant = {
	Block = 1, -- {} (or top level)
	If = 2, -- if <exp> {}
	While = 3, -- while <exp> {}
	Fn = 4, -- fn <name>((<NAME>:<TYPE>),*) {}

	Declare = 5, -- let x = 5
	Assign = 6, -- x = 5

	Call = 7,

	Negate = 8,

	Add = 9,
	Sub = 10,
	Mul = 11,
	Div = 12,

	And = 13,
	Or = 14,

	Literal = 15, -- "" 22 22.0
	Identifier = 16
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
---@return Node
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

	local stmt, arguments, block

	local function prim()
		local data = optConsume(TokenVariant.Integer)
		if data then
			return Node { variant = Variant.Literal, data = { "integer", data.data } }
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

		data = optConsume(TokenVariant.Identifier)
		if data then
			return Node { variant = Variant.Identifier, data = data.data }
		end
	end

	---@return Node?
	local function expr()
		if optConsume(TokenVariant.Operator, "-") then
			return Node { variant = Variant.Negate, data = expr() }
		end

		if optConsume(TokenVariant.Keyword, "const") then
			local b = block()
			b.data[1] = true -- mark block as constant
			return b
		end

		local lhs
		if optConsume(TokenVariant.Operator, "(") then
			lhs = expr()
			consume(TokenVariant.Operator, ")")
		else
			lhs = prim()
		end

		if not lhs then return end

		local args = arguments()
		if args then
			return Node { variant = Variant.Call, data = { lhs.data, args } }
		end

		--[[if optConsume(TokenVariant.Operator, ".") then
				local rest = 
			end
		end]]

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

	---@return Node
	function block(no_bracket)
		if not no_bracket then consume(TokenVariant.Operator, "{") end

		local stmts = {}
		while index < len do
			if not no_bracket and optConsume(TokenVariant.Operator, "}") then break end
			local item = stmt()
			if not item then
				item = expr()
				if item then
					stmts[#stmts + 1] = item
					consume(TokenVariant.Operator, "}")
					break -- Only last in block can be an expression
				else
					error("Failed to parse token " .. tostring(tokens[index]))
				end
			end
			stmts[#stmts + 1] = item
		end

		return Node { variant = Variant.Block, data = { false, stmts } }
	end

	---@return Node[]?
	function arguments()
		if optConsume(TokenVariant.Operator, "(") then
			local args = {}
			if optConsume(TokenVariant.Operator, ")") then
				return args
			end

			repeat
				args[#args + 1] = assert(expr(), "Expected argument for function call")
			until not optConsume(TokenVariant.Operator, ",")

			consume(TokenVariant.Operator, ")")
			return args
		end
	end

	function stmt()
		if optConsume(TokenVariant.Keyword, "const") then
			local b = block()
			b.data[1] = true
			return b
		elseif optConsume(TokenVariant.Keyword, "if") then
			---@type { [1]: Node?, [2]: Node }
			local chain = { { assert(expr(), "Expected expression after if statement"), block() } }

			while optConsume(TokenVariant.Keyword, "else") do
				if optConsume(TokenVariant.Keyword, "if") then
					chain[#chain + 1] = { assert(expr(), "Expected expression after elseif keyword"), block() }
				else
					chain[#chain + 1] = { nil, block() }
					break
				end
			end

			return Node { variant = Variant.If, data = chain }
		elseif optConsume(TokenVariant.Keyword, "while") then
			return Node { variant = Variant.While, data = { assert(expr(), "Expected expression for while loop"), block() } }
		elseif (optConsume(TokenVariant.Keyword, "pub") and consume(TokenVariant.Keyword, "fn")) or optConsume(TokenVariant.Keyword, "fn") then
			local pub = tokens[index - 2].data == "pub" -- Don't break elseif chain (kind of nasty)
			local name = consume(TokenVariant.Identifier)
			consume(TokenVariant.Operator, "(")

			local params = {}
			if optConsume(TokenVariant.Operator, ")") then
				return Node { variant = Variant.Fn, data = { name.data, params, block() } }
			end

			repeat
				local name = consume(TokenVariant.Identifier)
				consume(TokenVariant.Operator, ":")
				local ty = consume(TokenVariant.Identifier)
				params[#params + 1] = { name.data, ty.data }
			until not optConsume(TokenVariant.Operator, ",")

			consume(TokenVariant.Operator, ")")
			return Node { variant = Variant.Fn, data = { name.data, params, block() } }
		elseif optConsume(TokenVariant.Keyword, "let") then
			local name = consume(TokenVariant.Identifier)
			consume(TokenVariant.Operator, "=")
			return Node { variant = Variant.Declare, data = { name.data, assert(expr(), "Expected expression for declaration of " .. name.data), false } }
		elseif optConsume(TokenVariant.Keyword, "const") then
			local name = consume(TokenVariant.Identifier)
			consume(TokenVariant.Operator, "=")
			return Node { variant = Variant.Declare, data = { name.data, assert(expr(), "Expected expression for const declaration of " .. name.data), true } }
		else
			local name = optConsume(TokenVariant.Identifier)
			if name then
				if optConsume(TokenVariant.Operator, "=") then
					return Node { variant = Variant.Assign, data = { name.data, assert(expr(), "Expected expression for assignment of " .. name.data) } }
				else
					local args = arguments()
					if args then
						return Node { variant = Variant.Call, data = { name.data, args } }
					else
						index = index - 1 -- Expression
					end
				end
			end
		end
	end

	return block(true)
end

return {
	Variant = Variant,
	DebugVariant = DebugVariant,
	parse = parse
}