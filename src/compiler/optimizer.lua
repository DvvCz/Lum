local Assembler = require "compiler.assembler"
local IR, Variant = Assembler.IR, Assembler.Variant

local Type = require "compiler.assembler.type"
local Natives, Fn = Type.Natives, Type.Fn

---@param ir IR
---@return Type? ty, any? val
local function eval(ir)
	local variant, data = ir.variant, ir.data

	if variant == Variant.Literal then
		return ir.type, ir.const
	elseif variant == Variant.Add then
		local lhs_ty, lhs = eval(data[1])
		local rhs_ty, rhs = eval(data[2])
		if lhs and rhs and lhs_ty == rhs_ty then
			if lhs_ty == Natives.integer or lhs_ty == Natives.float then
				return lhs_ty, lhs + rhs
			elseif lhs_ty == Natives.string then
				return lhs_ty, lhs .. rhs
			end
		end
	elseif variant == Variant.Sub then
		local lhs_ty, lhs = eval(data[1])
		local rhs_ty, rhs = eval(data[2])
		if lhs and rhs and lhs_ty == rhs_ty and lhs_ty == Natives.integer or lhs_ty == Natives.float then
			return lhs_ty, lhs - rhs
		end
	elseif variant == Variant.Mul then
		local lhs_ty, lhs = eval(data[1])
		local rhs_ty, rhs = eval(data[2])
		if lhs and rhs and lhs_ty == rhs_ty and lhs_ty == Natives.integer or lhs_ty == Natives.float then
			return lhs_ty, lhs * rhs
		end
	elseif variant == Variant.Div then
		local lhs_ty, lhs = eval(data[1])
		local rhs_ty, rhs = eval(data[2])
		if lhs and rhs and lhs_ty == rhs_ty and lhs_ty == Natives.integer or lhs_ty == Natives.float then
			return lhs_ty, lhs / rhs
		end
	elseif variant == Variant.And then
		local lhs_ty, lhs = eval(data[1])
		local rhs_ty, rhs = eval(data[2])
		if lhs ~= nil and rhs ~= nil and lhs_ty == rhs_ty and lhs_ty == Natives.boolean then
			return lhs_ty, lhs and rhs
		end
	elseif variant == Variant.Or then
		local lhs_ty, lhs = eval(data[1])
		local rhs_ty, rhs = eval(data[2])
		if lhs ~= nil and rhs ~= nil and lhs_ty == rhs_ty and lhs_ty == Natives.boolean then
			return lhs_ty, lhs or rhs
		end
	elseif variant == Variant.Negate then
		local ty, val = eval(data)
		if ty == Natives.integer or ty == Natives.float then
			return ty, -val
		end
	elseif variant == Variant.Scope then
		if #data == 1 then -- Optimize to just the inner expression if block contains only one expression
			ir.variant, ir.data = data[1].variant, data[1].data
		end
	end
end

---@param module IR
local function optimize(module)
	---@param ir IR
	local function expr(ir)
		local variant, data = ir.variant, ir.data
		if variant == Variant.Literal then
			return ir
		elseif variant == Variant then
		end
	end

	---@param ir IR
	local function stmt(ir)
		local variant, data = ir.variant, ir.data
		if variant == Variant.Module then
			stmt(ir.data[2])
		elseif variant == Variant.Scope then
			local d = {}
			for k, ir in ipairs(data) do
				if stmt(ir) ~= false then
					d[#d + 1] = ir
				end
			end
			ir.data = d
		elseif variant == Variant.If then
			local chain = {}
			for i, val in ipairs(data) do
				local cond, block = val[1], val[2]
				stmt(block)
				if cond then
					local ty, val = eval(cond)
					if ty then
						if val ~= false then
							chain[#chain + 1] = { IR.new(Variant.Literal, { ty, val }), block }
						end
					else
						chain[#chain + 1] = val
					end
				else
					chain[#chain + 1] = val
				end
			end
			ir.data = chain
		elseif variant == Variant.While then
			local ty, val = eval(data[1])
			if ty then
				if val ~= false then
					-- Always true, todo: optimize condition out
					data[1] = IR.new(Variant.Literal, {ty, val})
				else
					return false -- Block does nothing.
				end
			end
		elseif variant == Variant.Declare then
			local ty, val = eval(data[2])
			if ty then
				data[2] = IR.new(Variant.Literal, { ty, val })
			end
		elseif variant == Variant.Assign then
			local ty, val = eval(data[2])
			if ty then
				data[2] = IR.new(Variant.Literal, { ty, val })
			end
		end
	end

	stmt(module)

	return module
end

return {
	optimize = optimize
}
