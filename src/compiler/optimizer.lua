local Assembler = require "compiler.assembler"
local IR = Assembler.IR
local IRDebugVariant, IRVariant = Assembler.DebugVariant, Assembler.Variant

---@param node Node
---@return string? ty, any? val
local function eval(node)
	local variant = node.variant

	if variant == IRVariant.Literal then
		return node.data[1], node.data[2]
	elseif variant == IRVariant.Add then
		local lhs_ty, lhs = eval(node.data[1])
		local rhs_ty, rhs = eval(node.data[2])
		if lhs and rhs and lhs_ty == rhs_ty then
			if lhs_ty == "int" or lhs_ty == "float" then
				return lhs_ty, lhs + rhs
			elseif lhs_ty == "string" then
				return lhs_ty, lhs .. rhs
			end
		end
	elseif variant == IRVariant.Sub then
		local lhs_ty, lhs = eval(node.data[1])
		local rhs_ty, rhs = eval(node.data[2])
		if lhs and rhs and lhs_ty == rhs_ty and lhs_ty == "int" or lhs_ty == "float" then
			return lhs_ty, lhs - rhs
		end
	elseif variant == IRVariant.Mul then
		local lhs_ty, lhs = eval(node.data[1])
		local rhs_ty, rhs = eval(node.data[2])
		if lhs and rhs and lhs_ty == rhs_ty and lhs_ty == "int" or lhs_ty == "float" then
			return lhs_ty, lhs * rhs
		end
	elseif variant == IRVariant.Div then
		local lhs_ty, lhs = eval(node.data[1])
		local rhs_ty, rhs = eval(node.data[2])
		if lhs and rhs and lhs_ty == rhs_ty and lhs_ty == "int" or lhs_ty == "float" then
			return lhs_ty, lhs / rhs
		end
	elseif variant == IRVariant.And then
		local lhs_ty, lhs = eval(node.data[1])
		local rhs_ty, rhs = eval(node.data[2])
		if lhs ~= nil and rhs ~= nil and lhs_ty == rhs_ty and lhs_ty == "boolean" then
			return lhs_ty, lhs and rhs
		end
	elseif variant == IRVariant.Or then
		local lhs_ty, lhs = eval(node.data[1])
		local rhs_ty, rhs = eval(node.data[2])
		if lhs ~= nil and rhs ~= nil and lhs_ty == rhs_ty and lhs_ty == "boolean" then
			return lhs_ty, lhs or rhs
		end
	elseif variant == IRVariant.Negate then
		local ty, val = eval(node.data)
		if ty == "int" or ty == "float" then
			return ty, -val
		end
	end
end

---@param module IR
local function optimize(module)
	---@param ir IR
	local function stmt(ir)
		local variant, data = ir.variant, ir.data
		if variant == IRVariant.Module then
			stmt(ir.data[2])
		elseif variant == IRVariant.Scope then
			local d = {}
			for k, ir in ipairs(data) do
				if stmt(ir) ~= false then
					d[#d + 1] = ir
				end
			end
			ir.data = d
		elseif variant == IRVariant.If then
			local chain = {}
			for i, val in ipairs(data) do
				local cond, block = val[1], val[2]
				stmt(block)
				if cond then
					local ty, val = eval(cond)
					if ty then
						if val ~= false then
							chain[#chain + 1] = { IR.new(IRVariant.Literal, { ty, val }), block }
						end
					else
						chain[#chain + 1] = val
					end
				else
					chain[#chain + 1] = val
				end
			end
			ir.data = chain
		elseif variant == IRVariant.While then
			local ty, val = eval(data[1])
			if ty then
				if val ~= false then
					-- Always true, todo: optimize condition out
					data[1] = IR.new(IRVariant.Literal, {ty, val})
				else
					return false -- Block does nothing.
				end
			end
		elseif variant == IRVariant.Declare then
			local ty, val = eval(data[2])
			if ty then
				data[2] = IR.new(IRVariant.Literal, { ty, val })
			end
		elseif variant == IRVariant.Assign then
			local ty, val = eval(data[2])
			if ty then
				data[2] = IR.new(IRVariant.Literal, { ty, val })
			end
		end
	end

	stmt(module)

	return module
end

return {
	optimize = optimize
}
