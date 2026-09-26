--!nonstrict
-- GUI tree export for scripts/render_ui.py: every ScreenGui under PlayerGui with the properties
-- that matter for layout/rendering, datatypes encoded as plain JSON arrays.
return function(st, propInfo, typeofX)
	local DUMP_PROPS = {
		"Size",
		"Position",
		"AnchorPoint",
		"Visible",
		"Enabled",
		"BackgroundColor3",
		"BackgroundTransparency",
		"Text",
		"TextSize",
		"TextColor3",
		"TextTransparency",
		"TextXAlignment",
		"TextYAlignment",
		"TextWrapped",
		"TextTruncate",
		"TextScaled",
		"TextStrokeTransparency",
		"TextStrokeColor3",
		"ZIndex",
		"LayoutOrder",
		"AutomaticSize",
		"ClipsDescendants",
		"DisplayOrder",
		"IgnoreGuiInset",
		"ScreenInsets",
		"Padding",
		"FillDirection",
		"HorizontalAlignment",
		"VerticalAlignment",
		"SortOrder",
		"CellSize",
		"CellPadding",
		"PaddingTop",
		"PaddingBottom",
		"PaddingLeft",
		"PaddingRight",
		"Color",
		"Thickness",
		"Transparency",
		"ApplyStrokeMode",
		"MaxSize",
		"MinSize",
		"Scale",
		"CanvasSize",
		"FontFace",
		"LineHeight",
	}
	local function encode(v)
		local t = typeofX(v)
		if t == "UDim2" then
			return { v.X.Scale, v.X.Offset, v.Y.Scale, v.Y.Offset }
		elseif t == "UDim" then
			return { v.Scale, v.Offset }
		elseif t == "Vector2" then
			return { v.X, v.Y }
		elseif t == "Color3" then
			return { v.R, v.G, v.B }
		elseif t == "EnumItem" then
			return v.Name
		elseif t == "Font" then
			return tostring(v.Family)
		elseif t == "number" or t == "string" or t == "boolean" then
			return v
		end
		return nil
	end
	local function dumpNode(obj)
		local s = st(obj)
		local node = { class = s.class, name = s.props.Name, props = {}, children = {} }
		for _, key in DUMP_PROPS do
			if propInfo(s.class, key) then
				node.props[key] = encode(obj[key])
			end
		end
		for _, child in s.children do
			table.insert(node.children, dumpNode(child))
		end
		return node
	end
	local M = {}
	function M.dump(playerGui, viewport)
		local guis = {}
		for _, g in st(playerGui).children do
			if st(g).class == "ScreenGui" then
				table.insert(guis, dumpNode(g))
			end
		end
		return { viewport = { viewport[1], viewport[2] }, guis = guis }
	end
	return M
end
