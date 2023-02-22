local Class = require "targets.jvm.class"

---@type Target
local Target = {
	name = "JVM",

	generate = function(ir)
		--[[local c = Class.new("SimplJ")
			:withStrings({ "java/lang/Object", "main", "<init>", "Code", "()V", "([Ljava/lang/String;)V" })
			:assemble()]]

		return ""
	end
}

return Target