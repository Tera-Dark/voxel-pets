--!nonstrict
-- Pure argument validators for the remote layer (and anything else taking untrusted input).
-- Engine-agnostic on purpose: Lune unit-tests this module directly.
--
-- Conventions:
--   * int   -> rejects NaN, +/-inf, non-integers, out-of-range values
--   * str   -> rejects empty strings, over-long strings and control characters
--   * strList -> array of valid strings within a count cap (no sparse/mixed tables)

local Validate = {}

local MAX_ITEM_LEN = 32 -- longest accepted id/name inside a list (uids are <= 16)

local function hasControlChars(s: string): boolean
	return string.find(s, "[%c]") ~= nil
end

-- Integer in [lo, hi] (bounds optional). Returns the value or nil.
function Validate.int(v, lo: number?, hi: number?): number?
	if type(v) ~= "number" or v ~= v or v == math.huge or v == -math.huge then
		return nil
	end
	if v % 1 ~= 0 then
		return nil
	end
	if lo ~= nil and v < lo then
		return nil
	end
	if hi ~= nil and v > hi then
		return nil
	end
	return v
end

-- Non-empty string of at most maxLen bytes without control characters. Returns the value or nil.
function Validate.str(v, maxLen: number?): string?
	if type(v) ~= "string" or #v == 0 then
		return nil
	end
	if maxLen ~= nil and #v > maxLen then
		return nil
	end
	if hasControlChars(v) then
		return nil
	end
	return v
end

-- Dense array of 1..maxCount valid strings (each at most MAX_ITEM_LEN bytes). Returns a copy or nil.
function Validate.strList(v, maxCount: number): { string }?
	if type(v) ~= "table" then
		return nil
	end
	local n = #v
	if n == 0 or n > maxCount then
		return nil
	end
	local out = {}
	for i = 1, n do
		local s = Validate.str(v[i], MAX_ITEM_LEN)
		if s == nil then
			return nil
		end
		out[i] = s
	end
	return out
end

return Validate
