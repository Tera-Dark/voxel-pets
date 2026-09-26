--!nonstrict
-- Roblox datatypes for the client mock (Vector3 / Vector2 / CFrame / Color3 / UDim / UDim2 /
-- TweenInfo), the API-dump-backed Enum, and a typeof() that understands them.

-- ================================================================ datatypes
local function typed(name)
	return { __type = name }
end

-- ---------------------------------------------------------------- Vector3 / Vector2
local V3mt = typed("Vector3")
local function v3(x, y, z)
	return setmetatable({ X = x or 0, Y = y or 0, Z = z or 0 }, V3mt)
end
local V3methods = {}
V3mt.__index = function(v, k)
	if k == "Magnitude" then
		return math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z)
	elseif k == "Unit" then
		local m = math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z)
		return if m > 0 then v3(v.X / m, v.Y / m, v.Z / m) else v3()
	end
	local m = V3methods[k]
	if m then
		return m
	end
	error(tostring(k) .. " is not a valid member of Vector3", 2)
end
V3mt.__add = function(a, b)
	return v3(a.X + b.X, a.Y + b.Y, a.Z + b.Z)
end
V3mt.__sub = function(a, b)
	return v3(a.X - b.X, a.Y - b.Y, a.Z - b.Z)
end
V3mt.__mul = function(a, b)
	if type(a) == "number" then
		return v3(b.X * a, b.Y * a, b.Z * a)
	elseif type(b) == "number" then
		return v3(a.X * b, a.Y * b, a.Z * b)
	end
	return v3(a.X * b.X, a.Y * b.Y, a.Z * b.Z)
end
V3mt.__div = function(a, b)
	if type(b) == "number" then
		return v3(a.X / b, a.Y / b, a.Z / b)
	end
	return v3(a.X / b.X, a.Y / b.Y, a.Z / b.Z)
end
V3mt.__unm = function(a)
	return v3(-a.X, -a.Y, -a.Z)
end
V3mt.__eq = function(a, b)
	return a.X == b.X and a.Y == b.Y and a.Z == b.Z
end
V3mt.__tostring = function(v)
	return string.format("%g, %g, %g", v.X, v.Y, v.Z)
end
function V3methods.Lerp(a, b, t)
	return a + (b - a) * t
end
function V3methods.Dot(a, b)
	return a.X * b.X + a.Y * b.Y + a.Z * b.Z
end
function V3methods.Cross(a, b)
	return v3(a.Y * b.Z - a.Z * b.Y, a.Z * b.X - a.X * b.Z, a.X * b.Y - a.Y * b.X)
end
local Vector3 = {
	new = v3,
	zero = v3(0, 0, 0),
	one = v3(1, 1, 1),
	xAxis = v3(1, 0, 0),
	yAxis = v3(0, 1, 0),
	zAxis = v3(0, 0, 1),
}

local V2mt = typed("Vector2")
local function v2(x, y)
	return setmetatable({ X = x or 0, Y = y or 0 }, V2mt)
end
V2mt.__index = function(v, k)
	if k == "Magnitude" then
		return math.sqrt(v.X * v.X + v.Y * v.Y)
	end
	error(tostring(k) .. " is not a valid member of Vector2", 2)
end
V2mt.__add = function(a, b)
	return v2(a.X + b.X, a.Y + b.Y)
end
V2mt.__sub = function(a, b)
	return v2(a.X - b.X, a.Y - b.Y)
end
V2mt.__mul = function(a, b)
	if type(a) == "number" then
		return v2(b.X * a, b.Y * a)
	elseif type(b) == "number" then
		return v2(a.X * b, a.Y * b)
	end
	return v2(a.X * b.X, a.Y * b.Y)
end
V2mt.__eq = function(a, b)
	return a.X == b.X and a.Y == b.Y
end
local Vector2 = { new = v2, zero = v2(0, 0), one = v2(1, 1) }

-- ---------------------------------------------------------------- CFrame (position + 3x3 rotation)
local CFmt = typed("CFrame")
local function cf(x, y, z, r)
	return setmetatable({ X = x, Y = y, Z = z, r = r or { 1, 0, 0, 0, 1, 0, 0, 0, 1 } }, CFmt)
end
local function mulR(a, b)
	local o = {}
	for i = 0, 2 do
		for j = 0, 2 do
			o[i * 3 + j + 1] = a[i * 3 + 1] * b[j + 1]
				+ a[i * 3 + 2] * b[3 + j + 1]
				+ a[i * 3 + 3] * b[6 + j + 1]
		end
	end
	return o
end
local function rotV(r, v)
	return v3(
		r[1] * v.X + r[2] * v.Y + r[3] * v.Z,
		r[4] * v.X + r[5] * v.Y + r[6] * v.Z,
		r[7] * v.X + r[8] * v.Y + r[9] * v.Z
	)
end
local function lookRot(eye, target)
	local f = (target - eye)
	if f.Magnitude < 1e-9 then
		return { 1, 0, 0, 0, 1, 0, 0, 0, 1 }
	end
	f = f.Unit
	local up = v3(0, 1, 0)
	local right = f:Cross(up)
	if right.Magnitude < 1e-9 then
		right = v3(1, 0, 0)
	else
		right = right.Unit
	end
	local u = right:Cross(f)
	-- columns: right, up, -forward
	return { right.X, u.X, -f.X, right.Y, u.Y, -f.Y, right.Z, u.Z, -f.Z }
end
local CFmethods = {}
CFmt.__index = function(c, k)
	if k == "Position" or k == "p" then
		return v3(c.X, c.Y, c.Z)
	elseif k == "LookVector" then
		return v3(-c.r[3], -c.r[6], -c.r[9])
	elseif k == "RightVector" then
		return v3(c.r[1], c.r[4], c.r[7])
	elseif k == "UpVector" then
		return v3(c.r[2], c.r[5], c.r[8])
	elseif k == "Rotation" then
		return cf(0, 0, 0, c.r)
	end
	local m = CFmethods[k]
	if m then
		return m
	end
	error(tostring(k) .. " is not a valid member of CFrame", 2)
end
CFmt.__mul = function(a, b)
	if getmetatable(b) == V3mt then
		return rotV(a.r, b) + v3(a.X, a.Y, a.Z)
	end
	local p = rotV(a.r, v3(b.X, b.Y, b.Z))
	return cf(a.X + p.X, a.Y + p.Y, a.Z + p.Z, mulR(a.r, b.r))
end
CFmt.__add = function(a, v)
	return cf(a.X + v.X, a.Y + v.Y, a.Z + v.Z, a.r)
end
CFmt.__sub = function(a, v)
	return cf(a.X - v.X, a.Y - v.Y, a.Z - v.Z, a.r)
end
CFmt.__eq = function(a, b)
	return a.X == b.X and a.Y == b.Y and a.Z == b.Z
end
function CFmethods.Lerp(a, b, t)
	return cf(
		a.X + (b.X - a.X) * t,
		a.Y + (b.Y - a.Y) * t,
		a.Z + (b.Z - a.Z) * t,
		if t < 0.5 then a.r else b.r
	)
end
function CFmethods.Inverse(a)
	local r = a.r
	local rt = { r[1], r[4], r[7], r[2], r[5], r[8], r[3], r[6], r[9] }
	local p = rotV(rt, v3(-a.X, -a.Y, -a.Z))
	return cf(p.X, p.Y, p.Z, rt)
end
function CFmethods.ToWorldSpace(a, b)
	return a * b
end
function CFmethods.ToObjectSpace(a, b)
	return a:Inverse() * b
end
function CFmethods.PointToWorldSpace(a, v)
	return a * v
end
function CFmethods.GetComponents(a)
	local r = a.r
	return a.X, a.Y, a.Z, r[1], r[2], r[3], r[4], r[5], r[6], r[7], r[8], r[9]
end
local function angles(rx, ry, rz)
	local cx, sx, cy, sy, cz, sz =
		math.cos(rx or 0),
		math.sin(rx or 0),
		math.cos(ry or 0),
		math.sin(ry or 0),
		math.cos(rz or 0),
		math.sin(rz or 0)
	local Rx = { 1, 0, 0, 0, cx, -sx, 0, sx, cx }
	local Ry = { cy, 0, sy, 0, 1, 0, -sy, 0, cy }
	local Rz = { cz, -sz, 0, sz, cz, 0, 0, 0, 1 }
	return cf(0, 0, 0, mulR(mulR(Rx, Ry), Rz))
end
local CFrame = {
	new = function(a, b, c, ...)
		if a == nil then
			return cf(0, 0, 0)
		elseif getmetatable(a) == V3mt then
			if getmetatable(b) == V3mt then
				return cf(a.X, a.Y, a.Z, lookRot(a, b))
			end
			return cf(a.X, a.Y, a.Z)
		end
		assert(
			type(a) == "number" and type(b) == "number" and type(c) == "number",
			"CFrame.new: bad arguments"
		)
		local rest = { ... }
		if #rest == 9 then
			return cf(a, b, c, rest)
		end
		return cf(a, b, c)
	end,
	Angles = angles,
	fromEulerAnglesXYZ = angles,
	lookAt = function(eye, target)
		return cf(eye.X, eye.Y, eye.Z, lookRot(eye, target))
	end,
	identity = cf(0, 0, 0),
}

-- ---------------------------------------------------------------- Color3
local C3mt = typed("Color3")
local function c3(r, g, b)
	return setmetatable({ R = r or 0, G = g or 0, B = b or 0 }, C3mt)
end
local C3methods = {}
C3mt.__index = function(_, k)
	local m = C3methods[k]
	if m then
		return m
	end
	error(tostring(k) .. " is not a valid member of Color3", 2)
end
C3mt.__eq = function(a, b)
	return a.R == b.R and a.G == b.G and a.B == b.B
end
function C3methods.Lerp(a, b, t)
	return c3(a.R + (b.R - a.R) * t, a.G + (b.G - a.G) * t, a.B + (b.B - a.B) * t)
end
function C3methods.ToHSV(c)
	local r, g, b = c.R, c.G, c.B
	local mx, mn = math.max(r, g, b), math.min(r, g, b)
	local d = mx - mn
	local h = 0
	if d > 0 then
		if mx == r then
			h = ((g - b) / d) % 6
		elseif mx == g then
			h = (b - r) / d + 2
		else
			h = (r - g) / d + 4
		end
		h /= 6
	end
	return h, if mx > 0 then d / mx else 0, mx
end
function C3methods.ToHex(c)
	return string.format("%02x%02x%02x", c.R * 255, c.G * 255, c.B * 255)
end
local Color3 = {
	new = c3,
	fromRGB = function(r, g, b)
		return c3((r or 0) / 255, (g or 0) / 255, (b or 0) / 255)
	end,
	fromHSV = function(h, s, v)
		h = (h % 1) * 6
		local i = math.floor(h)
		local f = h - i
		local p, q, t = v * (1 - s), v * (1 - s * f), v * (1 - s * (1 - f))
		local rgb = ({
			{ v, t, p },
			{ q, v, p },
			{ p, v, t },
			{ p, q, v },
			{ t, p, v },
			{ v, p, q },
		})[i % 6 + 1]
		return c3(rgb[1], rgb[2], rgb[3])
	end,
}

-- ---------------------------------------------------------------- UDim / UDim2 / misc
local UDmt = typed("UDim")
local function udim(s, o)
	return setmetatable({ Scale = s or 0, Offset = o or 0 }, UDmt)
end
UDmt.__index = function(_, k)
	error(tostring(k) .. " is not a valid member of UDim", 2)
end
UDmt.__add = function(a, b)
	return udim(a.Scale + b.Scale, a.Offset + b.Offset)
end
UDmt.__sub = function(a, b)
	return udim(a.Scale - b.Scale, a.Offset - b.Offset)
end
UDmt.__eq = function(a, b)
	return a.Scale == b.Scale and a.Offset == b.Offset
end
local UDim = { new = udim }

local U2mt = typed("UDim2")
local function udim2(xs, xo, ys, yo)
	return setmetatable({ X = udim(xs, xo), Y = udim(ys, yo) }, U2mt)
end
U2mt.__index = function(u, k)
	if k == "Width" then
		return u.X
	elseif k == "Height" then
		return u.Y
	elseif k == "Lerp" then
		return function(a, b, t)
			return udim2(
				a.X.Scale + (b.X.Scale - a.X.Scale) * t,
				a.X.Offset + (b.X.Offset - a.X.Offset) * t,
				a.Y.Scale + (b.Y.Scale - a.Y.Scale) * t,
				a.Y.Offset + (b.Y.Offset - a.Y.Offset) * t
			)
		end
	end
	error(tostring(k) .. " is not a valid member of UDim2", 2)
end
U2mt.__add = function(a, b)
	return udim2(
		a.X.Scale + b.X.Scale,
		a.X.Offset + b.X.Offset,
		a.Y.Scale + b.Y.Scale,
		a.Y.Offset + b.Y.Offset
	)
end
U2mt.__sub = function(a, b)
	return udim2(
		a.X.Scale - b.X.Scale,
		a.X.Offset - b.X.Offset,
		a.Y.Scale - b.Y.Scale,
		a.Y.Offset - b.Y.Offset
	)
end
U2mt.__eq = function(a, b)
	return a.X == b.X and a.Y == b.Y
end
local UDim2 = {
	new = function(xs, xo, ys, yo)
		if getmetatable(xs) == UDmt then
			return setmetatable({ X = xs, Y = xo }, U2mt)
		end
		return udim2(xs, xo, ys, yo)
	end,
	fromScale = function(x, y)
		return udim2(x, 0, y, 0)
	end,
	fromOffset = function(x, y)
		return udim2(0, x, 0, y)
	end,
}

local TImt = typed("TweenInfo")
local TweenInfo = {
	new = function(t, style, dir, rep, rev, delay)
		return setmetatable({
			Time = t or 1,
			EasingStyle = style,
			EasingDirection = dir,
			RepeatCount = rep or 0,
			Reverses = rev or false,
			DelayTime = delay or 0,
		}, TImt)
	end,
}

-- ================================================================ API-backed Enum
local function buildEnum(api)
	local EnumItemMT = typed("EnumItem")
	EnumItemMT.__tostring = function(item)
		return "Enum." .. item.EnumType.Name .. "." .. item.Name
	end
	local EnumMT = typed("Enum")
	local enums = {}
	for name, items in api.enums do
		local e = setmetatable({ Name = name, items = {} }, EnumMT)
		for i, itemName in items do
			e.items[itemName] =
				setmetatable({ Name = itemName, Value = i - 1, EnumType = e }, EnumItemMT)
		end
		enums[name] = e
	end
	EnumMT.__index = function(e, k)
		if k == "GetEnumItems" then
			return function(self)
				local out = {}
				for _, item in self.items do
					table.insert(out, item)
				end
				return out
			end
		end
		local item = rawget(e, "items")[k]
		if item then
			return item
		end
		error(tostring(k) .. ' is not a valid member of "Enum.' .. rawget(e, "Name") .. '"', 2)
	end
	local Enum = setmetatable({}, {
		__index = function(_, k)
			local e = enums[k]
			if e then
				return e
			end
			error(tostring(k) .. ' is not a valid member of "Enums"', 2)
		end,
	})
	return Enum, EnumItemMT
end

-- ================================================================ helpers
local function typeofX(v)
	if type(v) == "table" then
		local mt = getmetatable(v)
		if type(mt) == "table" and rawget(mt, "__type") then
			return mt.__type
		end
	end
	return typeof(v)
end

return {
	typed = typed,
	typeofX = typeofX,
	buildEnum = buildEnum,
	Vector3 = Vector3,
	Vector2 = Vector2,
	CFrame = CFrame,
	Color3 = Color3,
	UDim = UDim,
	UDim2 = UDim2,
	TweenInfo = TweenInfo,
	v3 = v3,
	v2 = v2,
	cf = cf,
	c3 = c3,
	udim = udim,
	udim2 = udim2,
}
