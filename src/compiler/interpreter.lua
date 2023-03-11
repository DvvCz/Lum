
local IR = require "compiler.assembler.ir"
local Variant = IR.Variant

local Type = require "compiler.assembler.type"
local Natives, Fn = Type.Natives, Type.Fn

---@class InterpreterScope
---@field vars table<string, any>
---@field parent InterpreterScope?
local InterpreterScope = {}
InterpreterScope.__index = InterpreterScope

---@param var string
---@return any?
function InterpreterScope:find(var)
	return self.vars[var] or (self.parent and self.parent:find(var))
end

---@param name string
---@return any val
function InterpreterScope:attr(name)
	if self[name] ~= nil then
		return self[name]
	elseif self.parent then
		return self.parent:attr(name)
	end
end

---@param parent InterpreterScope?
---@return InterpreterScope
function InterpreterScope.new(parent)
	return setmetatable({ vars = {}, parent = parent }, InterpreterScope)
end

---@class Interpreter
---@field scope InterpreterScope
local Interpreter = {}
Interpreter.__index = Interpreter

---@class InterpreterBuilder: Interpreter
local InterpreterBuilder = {}
InterpreterBuilder.__index = InterpreterBuilder

---@return InterpreterBuilder
function Interpreter.new()
	return setmetatable({
		scope = setmetatable({ vars = {} }, InterpreterScope)
	}, InterpreterBuilder)
end

---@param vars table<string, any>
function InterpreterBuilder:withVariables(vars)
	for k, v in pairs(vars) do
		self.scope.vars[k] = v
	end
	return self
end

---@return Interpreter
function InterpreterBuilder:build()
	return setmetatable(self, Interpreter)
end

--- Interprets an IR node and returns a value (if applicable.)
---@param ir IR
---@return any? # Value if ir is an expression
function Interpreter:eval(ir)
	local variant, data = ir.variant, ir.data

	if variant == Variant.Module then ---@cast data { [1]: string, [2]: IR }
		return self:eval(data[2])
	elseif variant == Variant.Scope then ---@cast data IR[]
		local scope = InterpreterScope.new(self.scope)
		self.scope = scope

		local last = table.remove(data)

		if scope:attr("returning") then
			for _, ir in ipairs(data) do
				if self.__return__ then
					self.__return__ = false
					return self.__returnvalue__
				end
				self:eval(ir)
			end
		else
			for _, ir in ipairs(data) do
				self:eval(ir)
			end
		end

		local out = self:eval(last)
		self.scope = self.scope.parent
		return out
	elseif variant == Variant.If then
		for _, dat in ipairs(data) do
			local cond, block = dat[1], dat[2]
			if cond then
				if self:eval(cond) then
					self:eval(block)
					break
				end
			else
				self:eval(block)
				break
			end
		end
	elseif variant == Variant.While then
		while self:eval(data[1]) do
			self:eval(data[2])
		end
	elseif variant == Variant.Fn then
		local attrs, name, params, body = data[1], data[2], data[3], data[4]
		self.scope.vars[name] = function(args)
			for i, arg in ipairs(args) do
				self.scope[params[i][1]] = arg
			end

			return self:eval(body)
		end
	elseif variant == Variant.Return then
		self.__return__ = true
		self.__returnvalue__ = self:eval(data)
	elseif variant == Variant.Declare then
		self.scope.vars[data[2]] = assert(self:eval(data[3]), "Cannot set to nil")
	elseif variant == Variant.Assign then
		self.scope.vars[data[1]] = self:eval(data[2])
	elseif variant == Variant.Call then
		local fn = assert(self:eval(data[1]), "undefined fn at runtime " .. tostring(data[1]))
		local args = {}
		for i, arg in ipairs(data[2]) do
			args[i] = self:eval(arg)
		end
		return fn(args)
	elseif variant == Variant.Index then
		return self:eval(data[1])[data[2]]
	elseif variant == Variant.Negate then
		return -self:eval(data)
	elseif variant == Variant.Add then
		if data[1].type == Natives.string then
			return self:eval(data[1]) .. self:eval(data[2])
		else
			return self:eval(data[1]) + self:eval(data[2])
		end
	elseif variant == Variant.Sub then
		return self:eval(data[1]) - self:eval(data[2])
	elseif variant == Variant.Mul then
		return self:eval(data[1]) * self:eval(data[2])
	elseif variant == Variant.Div then
		return self:eval(data[1]) / self:eval(data[2])
	elseif variant == Variant.And then
		return self:eval(data[1]) and self:eval(data[2])
	elseif variant == Variant.Or then
		return self:eval(data[1]) or self:eval(data[2])
	elseif variant == Variant.Literal then ---@cast data { [1]: any }
		return data[2]
	elseif variant == Variant.Identifier then
		return assert(self.scope:find(data), "Couldn't find variable " .. data)
	end
end

return Interpreter