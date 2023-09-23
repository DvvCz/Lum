
---@enum TokenVariant
local Variant = {
	Integer = 1,
	Float = 2,
	Boolean = 3,
	String = 4,

	Identifier = 5,
	Keyword = 6,
	Operator = 7,
	Comment = 8
}

local Keywords = {
	["if"] = true, ["else"] = true,
	["while"] = true, ["for"] = true,

	["var"] = true,
	["fn"] = true, ["return"] = true,

	["enum"] = true, ["struct"] = true,

	["const"] = true, -- compile time block
}

local Operators = {
	["{"] = true, ["("] = true, ["["] = true,
	["}"] = true, [")"] = true, ["]"] = true,

	[">"] = true, ["<"] = true,
	[">="] = true, ["<="] = true,
	["=="] = true,

	["+"] = true, ["+="] = true,
	["-"] = true, ["-="] = true,
	["*"] = true, ["*="] = true,
	["/"] = true, ["/="] = true,

	["||"] = true, ["&&"] = true,

	[","] = true, [":"] = true, ["."] = true,
	["="] = true
}

---@class Token
---@field variant TokenVariant
---@field data any

local DebugVariant = {}
for k, v in pairs(Variant) do
	DebugVariant[v] = k
end

local TokenMeta = {}
function TokenMeta:__tostring()
	return "Token { variant: " .. DebugVariant[self.variant] .. ", data: " .. tostring(self.data) .. " }"
end

---@type fun(tbl: Token): Token
local function Token(tbl)
	return setmetatable(tbl, TokenMeta)
end

---@param code string
---@return Token[]
local function lex(code)
	local tokens, ptr, column, line, len = {}, 0, 0, 0, #code

	local function consume(pattern, ws)
		local start, ed, match = code:find(pattern, ptr)
		if start then
			ptr = ed + 1

			if ws then
				local slice = code:sub(start, ed)
				local _, lines = slice:gsub("\n", "")
				if lines ~= 0 then
					line = line + lines
					column = slice:match("\n()[^\n]*$")
				end

				column = column + (start - ed) + 1
			else
				column = column + (start - ed) + 1
			end

			return match or true
		end
	end

	local function next()
		local data = consume("^(%d+%.%d+)")
		if data then
			return Token { variant = Variant.Float, data = tonumber(data) }
		end

		data = consume("^(%d+)")
		if data then
			return Token { variant = Variant.Integer, data = tonumber(data) }
		end

		data = consume("^\"([^\"]+)\"", true)
		if data then
			return Token { variant = Variant.String, data = data }
		end

		data = consume("^([%w_]+)")
		if data then
			if Keywords[data] then
				return Token { variant = Variant.Keyword, data = data }
			elseif data == "true" or data == "false" then
				return Token { variant = Variant.Boolean, data = data == "true" }
			else
				return Token { variant = Variant.Identifier, data = data }
			end
		end

		data = consume("^([-=+/*><&|][=&|])")
		if data and Operators[data] then
			return Token { variant = Variant.Operator, data = data }
		end

		data = consume("^([-{}()[%]:+*/.,<>=])")
		if data and Operators[data] then
			return Token { variant = Variant.Operator, data = data }
		end
	end

	while ptr <= len do
		repeat consume("^%s+", true) until not consume("^(//[^\n]+)", true) -- Skip whitespace & Comments
		tokens[#tokens + 1] = assert( next(), "Failed to lex string: (" .. code:sub(ptr, ptr + 5) .. ")" )
		repeat consume("^%s+", true) until not consume("^(//[^\n]+)", true)
	end

	return tokens
end

return {
	Variant = Variant,
	DebugVariant = DebugVariant,

	Token = TokenMeta,
	lex = lex
}