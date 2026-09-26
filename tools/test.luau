--!nonstrict
-- Test runner for shared config + simulator + progression + expedition + data contracts.
-- Domain suites live in tools/tests/ and return function(check, near). Exit code 1 on failure (used by CI).
local process = require("@lune/process")

local failures, passes = 0, 0
local function check(cond, msg)
	if cond then
		passes += 1
	else
		failures += 1
		print("  FAIL: " .. msg)
	end
end
local function near(a, b, eps)
	return math.abs(a - b) <= (eps or 1e-6)
end

local suites = {
	require("./tests/config"),
	require("./tests/combat"),
	require("./tests/progression"),
	require("./tests/expedition"),
	require("./tests/data"),
}

for _, suite in suites do
	suite(check, near)
end

print(string.format("\n%d passed, %d failed", passes, failures))
if failures > 0 then
	process.exit(1)
end
