local U8_MAX = 256
local U16_MAX = 65536
local U32_MAX = 4294967296

---@class ByteVec
---@field read_ptr integer
---@field write_ptr integer
---@field input string
---@field output string[]
local ByteVec = {}
ByteVec.__index = ByteVec

---@param str string?
function ByteVec.new(str)
	return setmetatable({ input = str, read_ptr = 0, write_ptr = 0, output = {}}, ByteVec)
end

function ByteVec:__tostring()
	return "ByteVec"
end

---@return number u8
function ByteVec:readU1()
	self.read_ptr = self.read_ptr + 1
	return string.byte(self.input, self.read_ptr)
end

--- Reads an unsigned integer from the stream
---@param n integer # 1, 2, 3, 4 ...
---@return number
function ByteVec:readU(n)
	local out = 0
	for i = 0, n - 1 do
		local b = self:readU1()
		out = out + bit.lshift(b, 8 * i)
	end
	return out
end

---@param len integer
function ByteVec:read(len)
	local start = self.read_ptr + 1
	self.read_ptr = self.read_ptr + len
	return string.sub(self.input, start, self.read_ptr)
end

--- Writes vararg bytes to the stream, connecting them with table.concat and string.char
---@vararg integer
function ByteVec:write(...)
	self.write_ptr = self.write_ptr + 1
	self.output[self.write_ptr] = table.concat {string.char(...)}
end

--- Writes a string directly into the buffer (No \0 appended.)
---@param str string
function ByteVec:writeString(str)
	self.write_ptr = self.write_ptr + 1
	self.output[self.write_ptr] = str
end

---@param byte integer
function ByteVec:writeU1(byte)
	self.write_ptr = self.write_ptr + 1
	self.output[self.write_ptr] = string.char(byte)
end

---@param n integer
function ByteVec:writeU2(n)
	self:writeU1( math.floor(n / U8_MAX) )
	self:writeU1( n % U8_MAX )
end

---@param n integer
function ByteVec:writeU4(n)
	self:writeU2( math.floor(n / U16_MAX) )
	self:writeU2( n % U16_MAX )
end

---@param n integer
function ByteVec:writeU8(n)
	self:writeU4( math.floor(n / U32_MAX) )
	self:writeU4( n % U32_MAX )
end

---@return string
function ByteVec:getOutput()
	return table.concat(self.output)
end

return ByteVec