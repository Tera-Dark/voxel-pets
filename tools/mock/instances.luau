--!nonstrict
-- API-dump-validated fake Instances for the client mock: members are checked against
-- tools/data/roblox_api.json (unknown member -> "X is not a valid member of Y"), writes are
-- type-checked like Roblox, events are lazily created signals running on the shared scheduler.
local DT = require("./datatypes")
local typed, typeofX = DT.typed, DT.typeofX
local v3, v2, cf, c3, udim, udim2 = DT.v3, DT.v2, DT.cf, DT.c3, DT.udim, DT.udim2

-- api: decoded roblox_api.json; scheduler: roblox_mock Scheduler; Enum: DT.buildEnum(api)
return function(api, scheduler, Enum)
	local classes = api.classes

	-- ------------------------------------------------------------ class metadata
	local chainCache = {}
	local function chain(className)
		local c = chainCache[className]
		if not c then
			c = {}
			local n = className
			while n and classes[n] do
				table.insert(c, n)
				n = classes[n].super
			end
			chainCache[className] = c
		end
		return c
	end
	local function isA(className, base)
		for _, n in chain(className) do
			if n == base then
				return true
			end
		end
		return false
	end
	local propCache = {}
	local function propInfo(className, key)
		local ck = className .. "." .. key
		local cached = propCache[ck]
		if cached == nil then
			cached = false
			for _, n in chain(className) do
				local code = classes[n].props[key]
				if code then
					cached = { code = code, ptype = classes[n].ptypes[key] or "" }
					break
				end
			end
			propCache[ck] = cached
		end
		return cached or nil
	end
	local function hasList(className, field, key)
		for _, n in chain(className) do
			if table.find(classes[n][field], key) then
				return true
			end
		end
		return false
	end

	-- ------------------------------------------------------------ signals
	local SignalMT = {}
	SignalMT.__index = SignalMT
	local function newSignal()
		return setmetatable({ handlers = {} }, SignalMT)
	end
	function SignalMT:Connect(fn)
		assert(type(fn) == "function", "Attempt to connect failed: Passed value is not a function")
		local entry = { fn = fn }
		table.insert(self.handlers, entry)
		local conn = { Connected = true }
		function conn.Disconnect()
			conn.Connected = false
			local i = table.find(self.handlers, entry)
			if i then
				table.remove(self.handlers, i)
			end
		end
		return conn
	end
	function SignalMT:Once(fn)
		local conn
		conn = self:Connect(function(...)
			conn.Disconnect()
			fn(...)
		end)
		return conn
	end
	function SignalMT:Wait()
		local co = coroutine.running()
		local fired = nil
		local conn
		conn = self:Connect(function(...)
			conn.Disconnect()
			fired = table.pack(...)
			if coroutine.status(co) == "suspended" then
				scheduler:resume(co)
			end
		end)
		coroutine.yield()
		return table.unpack(fired, 1, fired.n)
	end
	function SignalMT:Fire(...)
		for _, entry in table.clone(self.handlers) do
			scheduler:spawn(entry.fn, ...)
		end
	end

	-- ------------------------------------------------------------ instances
	local state = setmetatable({}, { __mode = "k" })
	local InstanceMT = typed("Instance")
	local Impl = {} -- [className] = { method = fn }

	local function st(obj)
		return state[obj]
	end
	local function isInstance(v)
		return type(v) == "table" and getmetatable(v) == InstanceMT
	end

	local function make(className)
		local obj = setmetatable({}, InstanceMT)
		state[obj] = {
			class = className,
			props = { Name = className },
			children = {},
			parent = nil,
			attrs = {},
			signals = {},
			attrSignals = {},
			propSignals = {},
			destroyed = false,
		}
		return obj
	end

	local function signalOf(obj, name)
		local s = st(obj)
		local sig = s.signals[name]
		if not sig then
			sig = newSignal()
			s.signals[name] = sig
		end
		return sig
	end

	local function fullName(obj)
		local parts = {}
		local o = obj
		while o do
			table.insert(parts, 1, st(o).props.Name)
			o = st(o).parent
		end
		return table.concat(parts, ".")
	end

	local TRUE_DEFAULTS = {
		Visible = true,
		Enabled = true,
		Archivable = true,
		AutoButtonColor = true,
		CanCollide = true,
		CastShadow = true,
		CanQuery = true,
		CanTouch = true,
		AutoLocalize = true,
		ResetOnSpawn = true,
		ClipsDescendants = false,
	}
	local NUM_DEFAULTS = {
		TextSize = 14,
		ZIndex = 1,
		Thickness = 1,
		TextStrokeTransparency = 1,
		FieldOfView = 70,
		MaxActivationDistance = 10,
		ScrollBarThickness = 12,
	}
	local function defaultFor(className, key, ptype)
		if ptype == "bool" then
			if key == "Active" then
				return isA(className, "GuiButton")
			end
			return TRUE_DEFAULTS[key] == true
		elseif ptype == "int" or ptype == "int64" or ptype == "float" or ptype == "double" then
			return NUM_DEFAULTS[key] or 0
		elseif ptype == "string" or ptype == "Content" or ptype == "ContentId" then
			return ""
		elseif ptype == "Color3" then
			return c3(0.64, 0.64, 0.65)
		elseif ptype == "UDim2" then
			return udim2(0, 0, 0, 0)
		elseif ptype == "UDim" then
			return udim(0, 0)
		elseif ptype == "Vector2" then
			return v2(0, 0)
		elseif ptype == "Vector3" then
			return if key == "Size" then v3(4, 1, 2) else v3(0, 0, 0)
		elseif ptype == "CFrame" then
			return cf(0, 0, 0)
		elseif ptype == "Font" then
			return setmetatable(
				{ Family = "rbxasset://fonts/families/SourceSansPro.json" },
				typed("Font")
			)
		elseif string.sub(ptype, 1, 5) == "Enum:" then
			local e = api.enums[string.sub(ptype, 6)]
			return e and Enum[string.sub(ptype, 6)][e[1]] or nil
		end
		return nil
	end

	local DATATYPES = {
		Color3 = true,
		UDim2 = true,
		UDim = true,
		Vector2 = true,
		Vector3 = true,
		CFrame = true,
		Font = true,
		TweenInfo = true,
	}
	-- Mirrors Roblox's property assignment checks. Returns the (possibly coerced) value.
	local function checkValue(className, key, ptype, value)
		local function bad()
			error(
				string.format(
					"Unable to assign property %s. %s expected, got %s (%s)",
					key,
					ptype,
					typeofX(value),
					className
				),
				3
			)
		end
		if ptype == "bool" then
			if type(value) ~= "boolean" then
				bad()
			end
		elseif ptype == "int" or ptype == "int64" or ptype == "float" or ptype == "double" then
			if type(value) ~= "number" then
				bad()
			end
		elseif ptype == "string" then
			if type(value) == "number" then
				return tostring(value)
			elseif type(value) ~= "string" then
				bad()
			end
		elseif DATATYPES[ptype] then
			if typeofX(value) ~= ptype then
				bad()
			end
		elseif string.sub(ptype, 1, 5) == "Enum:" then
			local enumName = string.sub(ptype, 6)
			if typeofX(value) == "EnumItem" then
				if value.EnumType.Name ~= enumName then
					bad()
				end
			elseif type(value) == "string" then
				return Enum[enumName][value]
			else
				bad()
			end
		elseif string.sub(ptype, 1, 6) == "Class:" then
			if
				value ~= nil
				and (not isInstance(value) or not isA(st(value).class, string.sub(ptype, 7)))
			then
				bad()
			end
		elseif ptype == "Callback" then
			if value ~= nil and type(value) ~= "function" then
				bad()
			end
		end
		return value
	end

	local function setParent(obj, parent)
		local s = st(obj)
		if s.destroyed then
			error(
				"The Parent property of " .. s.props.Name .. " is locked, current parent: NULL",
				3
			)
		end
		if parent ~= nil and not isInstance(parent) then
			error("Unable to assign property Parent. Object expected, got " .. typeofX(parent), 3)
		end
		local p = parent
		while p do
			if p == obj then
				error(
					"Attempt to set parent of " .. s.props.Name .. " to itself or a descendant",
					3
				)
			end
			p = st(p).parent
		end
		if s.parent then
			local siblings = st(s.parent).children
			local i = table.find(siblings, obj)
			if i then
				table.remove(siblings, i)
			end
			signalOf(s.parent, "ChildRemoved"):Fire(obj)
		end
		s.parent = parent
		if parent then
			table.insert(st(parent).children, obj)
			signalOf(parent, "ChildAdded"):Fire(obj)
		end
	end

	local function resolveMethod(obj, key)
		local s = st(obj)
		for _, n in chain(s.class) do
			local impl = Impl[n]
			if impl and impl[key] then
				return impl[key]
			end
		end
		if hasList(s.class, "methods", key) then
			return function()
				error(
					"client_mock: " .. s.class .. ":" .. key .. "() is not implemented in the mock",
					2
				)
			end
		end
		return nil
	end

	InstanceMT.__index = function(obj, key)
		local s = st(obj)
		if key == "Parent" then
			return s.parent
		elseif key == "ClassName" then
			return s.class
		end
		local method = resolveMethod(obj, key)
		if method then
			return method
		end
		local info = propInfo(s.class, key)
		if info then
			if key == "Position" and isA(s.class, "BasePart") then
				local c = s.props.CFrame or cf(0, 0, 0)
				return v3(c.X, c.Y, c.Z)
			elseif key == "AbsoluteSize" then
				return v2(1280, 720)
			elseif key == "AbsolutePosition" then
				return v2(0, 0)
			elseif key == "TextBounds" then
				local text = tostring(s.props.Text or "")
				local size = s.props.TextSize or 14
				return v2(#text * size * 0.6, size)
			end
			local v = s.props[key]
			if v == nil then
				v = defaultFor(s.class, key, info.ptype)
			end
			return v
		end
		if hasList(s.class, "events", key) then
			return signalOf(obj, key)
		end
		for _, child in s.children do
			if st(child).props.Name == key then
				return child
			end
		end
		if s.extra and s.extra[key] ~= nil then
			return s.extra[key]
		end
		error(
			tostring(key) .. " is not a valid member of " .. s.class .. ' "' .. fullName(obj) .. '"',
			2
		)
	end

	InstanceMT.__newindex = function(obj, key, value)
		local s = st(obj)
		if key == "Parent" then
			setParent(obj, value)
			return
		end
		local info = propInfo(s.class, key)
		if not info then
			error(
				tostring(key)
					.. " is not a valid member of "
					.. s.class
					.. ' "'
					.. fullName(obj)
					.. '"',
				2
			)
		end
		if string.sub(info.code, 1, 1) == "r" then
			error("Unable to assign property " .. key .. ". Property is read only", 2)
		end
		value = checkValue(s.class, key, info.ptype, value)
		if key == "Position" and isA(s.class, "BasePart") then
			local old = s.props.CFrame or cf(0, 0, 0)
			s.props.CFrame = cf(value.X, value.Y, value.Z, old.r)
		else
			s.props[key] = value
		end
		if s.signals.Changed then
			s.signals.Changed:Fire(key)
		end
		local ps = s.propSignals[key]
		if ps then
			ps:Fire()
		end
	end

	InstanceMT.__tostring = function(obj)
		return st(obj).props.Name
	end

	local function new(className)
		local c = classes[className]
		if not c then
			error('Unable to create an Instance of type "' .. tostring(className) .. '"', 2)
		end
		if table.find(c.tags, "NotCreatable") or table.find(c.tags, "Service") then
			error('Unable to create an Instance of type "' .. className .. '"', 2)
		end
		return make(className)
	end

	local function descendants(obj, out)
		out = out or {}
		for _, child in st(obj).children do
			table.insert(out, child)
			descendants(child, out)
		end
		return out
	end

	local function destroy(obj)
		local s = st(obj)
		if s.destroyed then
			return
		end
		for _, child in table.clone(s.children) do
			destroy(child)
		end
		if s.parent then
			setParent(obj, nil)
		end
		s.destroyed = true
		s.signals = {}
	end

	-- ------------------------------------------------------------ attribute values
	local ATTR_TYPES = {
		string = true,
		boolean = true,
		number = true,
		Color3 = true,
		UDim2 = true,
		UDim = true,
		Vector2 = true,
		Vector3 = true,
		CFrame = true,
		Font = true,
		EnumItem = true,
	}

	Impl.Instance = {
		Destroy = destroy,
		ClearAllChildren = function(obj)
			for _, child in table.clone(st(obj).children) do
				destroy(child)
			end
		end,
		GetChildren = function(obj)
			return table.clone(st(obj).children)
		end,
		GetDescendants = function(obj)
			return descendants(obj)
		end,
		FindFirstChild = function(obj, name, recursive)
			local list = if recursive then descendants(obj) else st(obj).children
			for _, child in list do
				if st(child).props.Name == name then
					return child
				end
			end
			local extra = st(obj).extra
			return extra and extra[name] or nil
		end,
		FindFirstChildOfClass = function(obj, className)
			for _, child in st(obj).children do
				if st(child).class == className then
					return child
				end
			end
			return nil
		end,
		FindFirstChildWhichIsA = function(obj, className)
			for _, child in st(obj).children do
				if isA(st(child).class, className) then
					return child
				end
			end
			return nil
		end,
		FindFirstAncestorOfClass = function(obj, className)
			local p = st(obj).parent
			while p do
				if st(p).class == className then
					return p
				end
				p = st(p).parent
			end
			return nil
		end,
		FindFirstAncestorWhichIsA = function(obj, className)
			local p = st(obj).parent
			while p do
				if isA(st(p).class, className) then
					return p
				end
				p = st(p).parent
			end
			return nil
		end,
		WaitForChild = function(obj, name, timeout)
			local found = obj:FindFirstChild(name)
			local waited = 0
			while not found do
				if timeout and waited >= timeout then
					return nil
				end
				if not timeout and waited >= 30 then
					error(
						"Infinite yield on " .. fullName(obj) .. ':WaitForChild("' .. name .. '")',
						2
					)
				end
				waited += scheduler:wait(0.1)
				found = obj:FindFirstChild(name)
			end
			return found
		end,
		IsA = function(obj, className)
			return isA(st(obj).class, className)
		end,
		IsDescendantOf = function(obj, ancestor)
			local p = st(obj).parent
			while p do
				if p == ancestor then
					return true
				end
				p = st(p).parent
			end
			return false
		end,
		GetFullName = fullName,
		Clone = function(obj)
			local s = st(obj)
			local copy = make(s.class)
			for k, v in s.props do
				st(copy).props[k] = v
			end
			for k, v in s.attrs do
				st(copy).attrs[k] = v
			end
			for _, child in s.children do
				child:Clone().Parent = copy
			end
			return copy
		end,
		GetAttribute = function(obj, name)
			return st(obj).attrs[name]
		end,
		GetAttributes = function(obj)
			return table.clone(st(obj).attrs)
		end,
		SetAttribute = function(obj, name, value)
			if value ~= nil and not ATTR_TYPES[typeofX(value)] then
				error(
					"SetAttribute: type "
						.. typeofX(value)
						.. " is not supported (attribute "
						.. name
						.. ")",
					2
				)
			end
			local s = st(obj)
			s.attrs[name] = value
			local sig = s.attrSignals[name]
			if sig then
				sig:Fire()
			end
			if s.signals.AttributeChanged then
				s.signals.AttributeChanged:Fire(name)
			end
		end,
		GetAttributeChangedSignal = function(obj, name)
			local s = st(obj)
			s.attrSignals[name] = s.attrSignals[name] or newSignal()
			return s.attrSignals[name]
		end,
		GetPropertyChangedSignal = function(obj, prop)
			local s = st(obj)
			if not propInfo(s.class, prop) then
				error(prop .. " is not a valid property name.", 2)
			end
			s.propSignals[prop] = s.propSignals[prop] or newSignal()
			return s.propSignals[prop]
		end,
	}
	Impl.PVInstance = {
		GetPivot = function(obj)
			local s = st(obj)
			if isA(s.class, "BasePart") then
				return s.props.CFrame or cf(0, 0, 0)
			end
			local primary = s.props.PrimaryPart
			if primary then
				return st(primary).props.CFrame or cf(0, 0, 0)
			end
			return s.pivot or cf(0, 0, 0)
		end,
		PivotTo = function(obj, target)
			if typeofX(target) ~= "CFrame" then
				error("Unable to cast value to CFrame", 2)
			end
			local s = st(obj)
			if isA(s.class, "BasePart") then
				s.props.CFrame = target
				return
			end
			s.pivot = target
			if s.props.PrimaryPart then
				st(s.props.PrimaryPart).props.CFrame = target
			end
		end,
	}
	Impl.BindableEvent = {
		Fire = function(obj, ...)
			signalOf(obj, "Event"):Fire(...)
		end,
	}
	Impl.GuiObject = {
		TweenPosition = function()
			return true
		end,
		TweenSize = function()
			return true
		end,
		TweenSizeAndPosition = function()
			return true
		end,
	}

	return {
		chain = chain,
		isA = isA,
		propInfo = propInfo,
		hasList = hasList,
		newSignal = newSignal,
		make = make,
		new = new,
		st = st,
		isInstance = isInstance,
		signalOf = signalOf,
		fullName = fullName,
		checkValue = checkValue,
		descendants = descendants,
		destroy = destroy,
		Impl = Impl,
	}
end
