--!nonstrict
-- Property defaults + assignment checks for the client mock's fake Instances: Roblox's real
-- defaults where "first enum item" would be wrong, and the same type errors Roblox raises
-- (e.g. `label.Text = nil`, a Color3 into a UDim2 property).
local DT = require("./datatypes")
local typed, typeofX = DT.typed, DT.typeofX
local v3, v2, cf, c3, udim, udim2 = DT.v3, DT.v2, DT.cf, DT.c3, DT.udim, DT.udim2

return function(api, Enum, isA, isInstance, st)
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
	-- Roblox defaults where "first enum item" would be wrong (matters for layout + rendering).
	local ENUM_DEFAULTS = {
		TextXAlignment = "Center",
		TextYAlignment = "Center",
		ScreenInsets = "CoreUISafeInsets",
		VerticalAlignment = "Top",
		HorizontalAlignment = "Left",
		FillDirection = "Vertical",
		SortOrder = "LayoutOrder",
		AutomaticSize = "None",
		TextTruncate = "None",
		ApplyStrokeMode = "Contextual",
		ZIndexBehavior = "Sibling",
		CameraType = "Custom",
		ScrollingDirection = "XY",
		AutomaticCanvasSize = "None",
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
			local enumName = string.sub(ptype, 6)
			local e = api.enums[enumName]
			if not e then
				return nil
			end
			local preferred = ENUM_DEFAULTS[key]
			if preferred and table.find(e, preferred) then
				return Enum[enumName][preferred]
			end
			return Enum[enumName][e[1]]
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

	return { defaultFor = defaultFor, checkValue = checkValue }
end
