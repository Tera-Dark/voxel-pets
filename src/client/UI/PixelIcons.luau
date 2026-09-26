--!nonstrict
-- 10x10 pixel-art icons drawn with Frames (no image assets needed; matches the pixel UI).
-- Each row is a string; '.' is transparent, other characters index the icon's palette.
-- Horizontal runs of one colour become a single Frame (~15-30 Frames per icon).
local PixelIcons = {}

local K = Color3.fromRGB(24, 24, 36) -- outline

local ICONS = {
	sword = {
		palette = {
			k = K,
			w = Color3.fromRGB(236, 240, 250),
			a = Color3.fromRGB(165, 178, 205),
			g = Color3.fromRGB(245, 190, 60),
			b = Color3.fromRGB(150, 98, 52),
		},
		rows = {
			"......kkk.",
			".....kwwk.",
			"....kwwak.",
			"...kwwak..",
			".kkwwak...",
			".kgaak....",
			"..kgk.....",
			".kbkgk....",
			"kbk.kk....",
			"kk........",
		},
	},
	portal = {
		palette = {
			k = K,
			a = Color3.fromRGB(150, 92, 232),
			b = Color3.fromRGB(88, 52, 168),
			w = Color3.fromRGB(226, 196, 255),
		},
		rows = {
			"...kkkk...",
			"..kaaaak..",
			".kabbbbak.",
			".kabwwbak.",
			".kabwwbak.",
			".kabwwbak.",
			".kabbbbak.",
			".kabbbbak.",
			".kaaaaaak.",
			"kkkkkkkkkk",
		},
	},
	trophy = {
		palette = {
			k = K,
			a = Color3.fromRGB(252, 204, 64),
			b = Color3.fromRGB(206, 142, 32),
			w = Color3.fromRGB(255, 240, 170),
		},
		rows = {
			"kkkkkkkkkk",
			"kawaaaaabk",
			"kkwaaaabkk",
			"..kaaaabk.",
			"...kaabk..",
			"....kbk...",
			"....kbk...",
			"...kaabk..",
			"..kbbbbbk.",
			"..kkkkkkk.",
		},
	},
	paw = {
		palette = {
			k = K,
			a = Color3.fromRGB(255, 196, 168),
			b = Color3.fromRGB(226, 142, 118),
		},
		rows = {
			".kk....kk.",
			"kaak..kaak",
			"kaak..kaak",
			".kk.kk.kk.",
			"...kaak...",
			"..kaaaak..",
			".kaaaaaak.",
			".kaabbaak.",
			"..kaaaak..",
			"...kkkk...",
		},
	},
	egg = {
		palette = {
			k = K,
			a = Color3.fromRGB(252, 244, 214),
			g = Color3.fromRGB(122, 204, 122),
			w = Color3.fromRGB(255, 255, 255),
		},
		rows = {
			"...kkkk...",
			"..kawaak..",
			".kawaaaak.",
			".kaggaaak.",
			"kaaggaagak",
			"kaaaaaggak",
			"kaggaaaaak",
			"kaggaaaaak",
			".kaaaagak.",
			"..kkkkkk..",
		},
	},
	book = {
		palette = {
			k = K,
			a = Color3.fromRGB(204, 72, 72),
			b = Color3.fromRGB(150, 44, 44),
			w = Color3.fromRGB(244, 238, 222),
			g = Color3.fromRGB(245, 190, 60),
		},
		rows = {
			".kkkkkkkk.",
			"kbaaaaaaak",
			"kbaaggaaak",
			"kbagaagaak",
			"kbaaggaaak",
			"kbaaaaaaak",
			"kbaaaaaaak",
			"kbwwwwwwwk",
			"kbkkkkkkkk",
			".kk.......",
		},
	},
	tent = {
		palette = {
			k = K,
			a = Color3.fromRGB(242, 152, 60),
			b = Color3.fromRGB(196, 104, 38),
			d = Color3.fromRGB(70, 44, 30),
			g = Color3.fromRGB(96, 168, 78),
		},
		rows = {
			"....kk....",
			"...kabk...",
			"...kabk...",
			"..kaabbk..",
			"..kaadbk..",
			".kaaddbbk.",
			".kaaddbbk.",
			"kaaaddbbbk",
			"kkkkkkkkkk",
			"gggggggggg",
		},
	},
	star = {
		palette = {
			k = K,
			a = Color3.fromRGB(255, 222, 72),
			b = Color3.fromRGB(230, 168, 40),
			w = Color3.fromRGB(255, 248, 200),
		},
		rows = {
			"....kk....",
			"....kak...",
			"...kawak..",
			"kkkkaaakkk",
			"kaaaaaaaak",
			".kbaaaabk.",
			"..kbaabk..",
			".kbbkkbbk.",
			".kbk..kbk.",
			".kk....kk.",
		},
	},
	scroll = {
		palette = {
			k = K,
			a = Color3.fromRGB(242, 224, 172),
			b = Color3.fromRGB(202, 170, 110),
			d = Color3.fromRGB(120, 96, 70),
		},
		rows = {
			".kkkkkkkk.",
			"kbbbbbbbbk",
			".kaaaaaak.",
			".kaddddak.",
			".kaaaaaak.",
			".kaddddak.",
			".kaaaaaak.",
			".kaddaaak.",
			"kbbbbbbbbk",
			".kkkkkkkk.",
		},
	},
	bag = {
		palette = {
			k = K,
			a = Color3.fromRGB(176, 124, 72),
			b = Color3.fromRGB(128, 86, 48),
			g = Color3.fromRGB(252, 204, 64),
		},
		rows = {
			"...kkkk...",
			"....kk....",
			"...kaak...",
			"..kaaaak..",
			".kaaggaak.",
			"kaagaaaabk",
			"kaaaggaabk",
			"kaaaaagabk",
			"kbaaggaabk",
			".kkkkkkkk.",
		},
	},
	gear = {
		palette = {
			k = K,
			a = Color3.fromRGB(184, 190, 206),
			b = Color3.fromRGB(122, 128, 146),
		},
		rows = {
			"...kaak...",
			".k.kaak.k.",
			"kakaaaakak",
			".kaabbaak.",
			"kaabkkbaak",
			"kaabkkbaak",
			".kaabbaak.",
			"kakaaaakak",
			".k.kaak.k.",
			"...kaak...",
		},
	},
	coin = {
		palette = {
			k = K,
			a = Color3.fromRGB(255, 206, 60),
			b = Color3.fromRGB(222, 160, 30),
			w = Color3.fromRGB(255, 242, 170),
		},
		rows = {
			"..kkkkkk..",
			".kwwaaaak.",
			"kwaaaaaabk",
			"kwaabbaabk",
			"kaabaabbbk",
			"kaabaabbbk",
			"kaaabbaabk",
			"kaaaaaabbk",
			".kbbbbbbk.",
			"..kkkkkk..",
		},
	},
	gem = {
		palette = {
			k = K,
			a = Color3.fromRGB(110, 232, 232),
			b = Color3.fromRGB(58, 168, 190),
			w = Color3.fromRGB(224, 255, 255),
		},
		rows = {
			"..kkkkkk..",
			".kwwaaabk.",
			"kwwaaaabbk",
			"kkkkkkkkkk",
			".kaawaabk.",
			"..kaaabk..",
			"...kaabk..",
			"....kbk...",
			"....kk....",
			"..........",
		},
	},
	arrowDown = {
		palette = { k = K, a = Color3.fromRGB(255, 200, 60) },
		rows = {
			"...kkkk...",
			"...kaak...",
			"...kaak...",
			"...kaak...",
			"kkkkaakkkk",
			".kaaaaaak.",
			"..kaaaak..",
			"...kaak...",
			"....kk....",
			"..........",
		},
	},
	arrowUp = {
		palette = { k = K, a = Color3.fromRGB(255, 200, 60) },
		rows = {
			"..........",
			"....kk....",
			"...kaak...",
			"..kaaaak..",
			".kaaaaaak.",
			"kkkkaakkkk",
			"...kaak...",
			"...kaak...",
			"...kaak...",
			"...kkkk...",
		},
	},
	arrowLeft = {
		palette = { k = K, a = Color3.fromRGB(255, 200, 60) },
		rows = {
			"....k.....",
			"...kk.....",
			"..kak.....",
			".kaakkkkkk",
			"kaaaaaaaak",
			"kaaaaaaaak",
			".kaakkkkkk",
			"..kak.....",
			"...kk.....",
			"....k.....",
		},
	},
	lock = {
		palette = {
			k = K,
			a = Color3.fromRGB(206, 206, 216),
			b = Color3.fromRGB(140, 140, 152),
			d = Color3.fromRGB(60, 60, 72),
		},
		rows = {
			"...kkkk...",
			"..kbbbbk..",
			"..kb..bk..",
			"..kb..bk..",
			".kkkkkkkk.",
			".kaaaaaak.",
			".kaaddaak.",
			".kaaddaak.",
			".kaaaaaak.",
			".kkkkkkkk.",
		},
	},
}

PixelIcons.NAMES = {}
for name in ICONS do
	table.insert(PixelIcons.NAMES, name)
end
table.sort(PixelIcons.NAMES)

-- Builds icon `name` as a transparent Frame of size x size pixels (use multiples of 10).
function PixelIcons.new(name: string, size: number, props)
	local icon = ICONS[name] or ICONS.lock
	local cell = size / 10
	local root = Instance.new("Frame")
	root.Name = "Icon_" .. name
	root.BackgroundTransparency = 1
	root.BorderSizePixel = 0
	root.Size = UDim2.fromOffset(size, size)
	for y, row in icon.rows do
		local x = 1
		while x <= #row do
			local ch = string.sub(row, x, x)
			local runEnd = x
			while runEnd < #row and string.sub(row, runEnd + 1, runEnd + 1) == ch do
				runEnd += 1
			end
			local color = icon.palette[ch]
			if color then
				local px = Instance.new("Frame")
				px.BorderSizePixel = 0
				px.BackgroundColor3 = color
				px.Position = UDim2.fromOffset((x - 1) * cell, (y - 1) * cell)
				px.Size = UDim2.fromOffset((runEnd - x + 1) * cell, cell)
				px.Parent = root
			end
			x = runEnd + 1
		end
	end
	for k, v in props or {} do
		if k ~= "Parent" then
			root[k] = v
		end
	end
	if props and props.Parent then
		root.Parent = props.Parent
	end
	return root
end

-- ZIndex applied to the icon and every pixel (icons inside modals need a raised ZIndex).
function PixelIcons.setZIndex(icon, z: number)
	icon.ZIndex = z
	for _, px in icon:GetChildren() do
		if px:IsA("GuiObject") then
			px.ZIndex = z
		end
	end
end

return PixelIcons
