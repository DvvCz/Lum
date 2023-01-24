local parser = require "compiler.parser"
local ParserDebugVariant, NodeVariant = parser.DebugVariant, parser.Variant

---@param node Node
---@return string? ty, any? val
local function eval(node)
	local variant = node.variant

	if variant == NodeVariant.Literal then
		return node.data[1], node.data[2]
	elseif variant == NodeVariant.Add then
		local lhs_ty, lhs = eval(node.data[1])
		local rhs_ty, rhs = eval(node.data[2])
		if lhs and rhs and lhs_ty == rhs_ty and lhs_ty == "int" or lhs_ty == "float" then
			return lhs_ty, lhs + rhs
		end
	elseif variant == NodeVariant.Sub then
		local lhs_ty, lhs = eval(node.data[1])
		local rhs_ty, rhs = eval(node.data[2])
		if lhs and rhs and lhs_ty == rhs_ty and lhs_ty == "int" or lhs_ty == "float" then
			return lhs_ty, lhs - rhs
		end
	elseif variant == NodeVariant.Mul then
		local lhs_ty, lhs = eval(node.data[1])
		local rhs_ty, rhs = eval(node.data[2])
		if lhs and rhs and lhs_ty == rhs_ty and lhs_ty == "int" or lhs_ty == "float" then
			return lhs_ty, lhs * rhs
		end
	elseif variant == NodeVariant.Div then
		local lhs_ty, lhs = eval(node.data[1])
		local rhs_ty, rhs = eval(node.data[2])
		if lhs and rhs and lhs_ty == rhs_ty and lhs_ty == "int" or lhs_ty == "float" then
			return lhs_ty, lhs / rhs
		end
	end
end

---@param ast Node
local function optimize(ast)
	if ast.variant == NodeVariant.Block then
		for k, v in ipairs(ast.data) do
			ast.data[k] = optimize(v) or v
		end
	elseif ast.variant == NodeVariant.If then
		local ty, value = eval(ast.data[1])
		optimize(ast.data[2])
	elseif ast.variant == NodeVariant.Declare then
		local ty, value = eval(ast.data[2])
		if value then
			ast.data[1] = ty
			ast.data[2] = value
		end
	end

	return ast
end

return {
	optimize = optimize
}
