--!nonstrict
-- Deterministic xorshift32 PRNG. Pure bit32 so it produces identical sequences on Roblox
-- servers, Roblox clients (for replay) and in Lune (offline balance runs).
local Rng = {}
Rng.__index = Rng

local function scramble(seed: number): number
	local s = bit32.band(math.floor(seed), 0xFFFFFFFF)
	s = bit32.bxor(s, 0x9E3779B9)
	if s == 0 then
		s = 0x1234567
	end
	return s
end

function Rng.new(seed: number?)
	local self = setmetatable({ state = scramble(seed or 1) }, Rng)
	for _ = 1, 4 do -- warm-up: shakes out poorly mixed small seeds
		self:nextUint32()
	end
	return self
end

function Rng:nextUint32(): number
	local x = self.state
	x = bit32.bxor(x, bit32.lshift(x, 13))
	x = bit32.bxor(x, bit32.rshift(x, 17))
	x = bit32.bxor(x, bit32.lshift(x, 5))
	self.state = x
	return x
end

-- Uniform float in [0, 1)
function Rng:next(): number
	return self:nextUint32() / 4294967296
end

function Rng:range(lo: number, hi: number): number
	return lo + (hi - lo) * self:next()
end

function Rng:int(lo: number, hi: number): number
	return lo + math.floor(self:next() * (hi - lo + 1))
end

function Rng:chance(p: number): boolean
	return self:next() < p
end

-- Derive an independent seed (e.g. one per battle inside an expedition run).
function Rng:deriveSeed(): number
	return self:nextUint32()
end

return Rng
