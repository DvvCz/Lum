local lexer = require "compiler.lexer"
local TokenDebugVariant, TokenVariant = lexer.DebugVariant, lexer.Variant

---@enum NodeVariant
local Variant = {
	Module = 1, -- Top level

	Block = 2, -- {}
	If = 3, -- if <exp> {}
	While = 4, -- while <exp> {}
	Fn = 5, -- fn <name>((<NAME>:<TYPE>),*) {}
	Return = 6, -- return <exp>?

	Declare = 7, -- let x = 5
	Assign = 8, -- x = 5

	Group = 9,
	Call = 10,
	Index = 11,

	Negate = 12,

	Add = 13,
	Sub = 14,
	Mul = 15,
	Div = 16,

	And = 17,
	Or = 18,

	Eq = 19,
	NotEq = 20,

	Literal = 21, -- "" 22 22.0

	StructInstance = 22,
	Struct = 23,

	Identifier = 24
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

---@generic T?
---@return T
local function assert(value --[[@param value T?]], msg --[[@param msg string]])
	if not value then error(msg) end
	return value
end

---@param tokens Token[]
---@return Node
local function parse(tokens)
	local index, len = 1, #tokens

	---@param variant TokenVariant
	---@return Token
	local function consume(variant, data)
		local token = assert(tokens[index], "Expected " .. TokenDebugVariant[variant] .. ", got EOI")
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

		if optConsume(TokenVariant.Keyword, "struct") then
			consume(TokenVariant.Operator, "{")

			local fields = {}
			if optConsume(TokenVariant.Operator, "}") then
				return Node { variant = Variant.Struct, data = fields }
			end

			repeat
				local key = consume(TokenVariant.Identifier)
				consume(TokenVariant.Operator, ":")
				fields[#fields + 1] = {key.data, consume(TokenVariant.Identifier).data}
			until not optConsume(TokenVariant.Operator, ",")

			consume(TokenVariant.Operator, "}")

			return Node { variant = Variant.Struct, data = fields }
		end

		local struct_type = optConsume(TokenVariant.Identifier)

		if optConsume(TokenVariant.Operator, "{") then
			local fields = {}
			if optConsume(TokenVariant.Operator, "}") then
				return Node { variant = Variant.StructInstance, data = { struct_type and struct_type.data, fields } }
			end

			repeat
				local key = consume(TokenVariant.Identifier)
				consume(TokenVariant.Operator, "=")
				fields[#fields + 1] = {key.data, assert(expr(), "Expected expression for struct field")}
			until not optConsume(TokenVariant.Operator, ",")

			consume(TokenVariant.Operator, "}")

			return Node { variant = Variant.StructInstance, data = { struct_type and struct_type.data, fields } }
		elseif struct_type then
			index = index - 1
		end

		local lhs
		if optConsume(TokenVariant.Operator, "(") then
			lhs = Node { variant = Variant.Group, data = expr() }
			consume(TokenVariant.Operator, ")")
		else
			lhs = prim()
		end

		if optConsume(TokenVariant.Operator, "[") then
			local values = {}
			if optConsume(TokenVariant.Operator, "]") then
				return Node { variant = Variant.Array, data = values }
			end

			repeat
				values[#values + 1] = assert(expr(), "Expected expression for array value")
			until not optConsume(TokenVariant.Operator, ",")

			consume(TokenVariant.Operator, "]")
			return Node { variant = Variant.Array, data = values }
		end

		if not lhs then return end

		while optConsume(TokenVariant.Operator, ".") do
			local rest = consume(TokenVariant.Identifier)
			lhs = Node { variant = Variant.Index, data = { lhs, rest.data } }
		end

		local args = arguments()
		if args then
			lhs = Node { variant = Variant.Call, data = { lhs, args } }
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
			return Node { variant = Variant.And, data = { lhs, assert(expr(), "Expected expression after &&") } }
		elseif optConsume(TokenVariant.Operator, "||") then
			return Node { variant = Variant.Or, data = { lhs, assert(expr(), "Expected expression after ||") } }
		elseif optConsume(TokenVariant.Operator, "==") then
			return Node { variant = Variant.Eq, data = { lhs, assert(expr(), "Expected expression after ==") } }
		elseif optConsume(TokenVariant.Operator, "!=") then
			return Node { variant = Variant.NotEq, data = { lhs, assert(expr(), "Expected expression after !=") } }
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
				item = assert(expr(), "Failed to parse token " .. tostring(tokens[index]))
				assert(item.variant == Variant.Call, "Cannot use expression in statement position")
			end
			stmts[#stmts + 1] = item
		end

		return Node { variant = Variant.Block, data = stmts }
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
		if optConsume(TokenVariant.Keyword, "if") then
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
		elseif optConsume(TokenVariant.Keyword, "var") then
			local name = consume(TokenVariant.Identifier)
			consume(TokenVariant.Operator, "=")
			return Node { variant = Variant.Declare, data = { false, name.data, assert(expr(), "Expected expression for declaration of " .. name.data) } }
		elseif optConsume(TokenVariant.Keyword, "return") then
			return Node { variant = Variant.Return, data = expr() or consume(TokenVariant.Operator, "}") }
		else
			local before = index
			local const = optConsume(TokenVariant.Keyword, "const")

			if (const and optConsume(TokenVariant.Keyword, "fn")) or optConsume(TokenVariant.Keyword, "fn") then
				local name = consume(TokenVariant.Identifier)
				consume(TokenVariant.Operator, "(")

				local params = {}
				if optConsume(TokenVariant.Operator, ")") then
					return Node { variant = Variant.Fn, data = { { const = const }, name.data, params, block() } }
				end

				repeat
					local name = consume(TokenVariant.Identifier)
					consume(TokenVariant.Operator, ":")
					local ty = consume(TokenVariant.Identifier)
					params[#params + 1] = { name.data, ty.data }
				until not optConsume(TokenVariant.Operator, ",")

				consume(TokenVariant.Operator, ")")
				return Node { variant = Variant.Fn, data = { { const = const }, name.data, params, block() } }
			elseif const then -- const x = 5 (variable in const interpreter)
				local name = optConsume(TokenVariant.Identifier)
				if name then
					consume(TokenVariant.Operator, "=")
					return Node { variant = Variant.Declare, data = { true, name.data, assert(expr(), "Expected expression for const declaration") } }
				else
					index = before
				end
			else
				index = before
			end

			local name = optConsume(TokenVariant.Identifier)
			if name then
				if optConsume(TokenVariant.Operator, "=") then
					return Node { variant = Variant.Assign, data = { name.data, assert(expr(), "Expected expression for assignment of " .. name.data) } }
				else
					local args = arguments()
					if args then
						return Node { variant = Variant.Call, data = { Node { variant = Variant.Identifier, data = name.data }, args } }
					else
						index = index - 1 -- Expression
					end
				end
			end
		end
	end

	return Node { variant = Variant.Module, data = block(true) }
end

return {
	Variant = Variant,
	DebugVariant = DebugVariant,
	parse = parse
}