--!nonstrict
-- Suite: DataStore-safety of the profile schema, remote contract uniqueness and arg validators.
local DataTemplate = require("../../src/shared/DataTemplate")
local Network = require("../../src/shared/Network")
local Validate = require("../../src/shared/Validate")

return function(check)
	print("data + network")
	do
		check(DataTemplate.schemaVersion == 1, "schema v1")
		for _, key in DataTemplate.PUBLIC_KEYS do
			check(DataTemplate[key] ~= nil, "public key exists in template: " .. key)
		end
		local seen = {}
		for _, name in Network.Functions do
			check(not seen[name], "unique remote " .. name)
			seen[name] = true
		end
		for _, name in Network.Events do
			check(not seen[name], "unique remote " .. name)
			seen[name] = true
		end
		check(#Network.Functions >= 30, "function list complete")
	end

	print("validate")
	do
		check(Validate.int(5, 1, 10) == 5, "int in range")
		check(Validate.int(1, 1, 10) == 1 and Validate.int(10, 1, 10) == 10, "int bounds inclusive")
		check(Validate.int(0, 1, 10) == nil, "int below range")
		check(Validate.int(11, 1, 10) == nil, "int above range")
		check(Validate.int(1.5, 1, 10) == nil, "float rejected")
		check(Validate.int(0 / 0, 1, 10) == nil, "NaN rejected")
		check(Validate.int(math.huge, 1, 10) == nil, "inf rejected")
		check(Validate.int("3", 1, 10) == nil, "string rejected")
		check(Validate.int(7) == 7, "unbounded int ok")
		check(Validate.str("abc", 16) == "abc", "str ok")
		check(Validate.str("", 16) == nil, "empty str rejected")
		check(Validate.str("a\nb", 16) == nil, "newline rejected")
		check(Validate.str("a\0b", 16) == nil, "NUL rejected")
		check(Validate.str(string.rep("a", 17), 16) == nil, "overlong str rejected")
		local list = Validate.strList({ "u1", "u2" }, 2)
		check(list ~= nil and list[2] == "u2", "strList ok")
		check(Validate.strList({ "u1", "u2" }, 1) == nil, "strList count cap")
		check(Validate.strList({ "u1", 5 }, 2) == nil, "strList non-string rejected")
		check(Validate.strList({ "u1", "" }, 2) == nil, "strList empty element rejected")
		check(Validate.strList({}, 2) == nil, "strList empty list rejected")
	end
end
