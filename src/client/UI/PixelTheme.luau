--!nonstrict
-- Pixel-art UI theme: warm "sunny voxel" style (D-26). Cozy wooden windows with gold trim and
-- cream text (Stardew-inspired direction, our own palette), chunky pixel borders, Press Start 2P
-- (fallback Arcade). Colour keys are semantic and shared by every screen, so the whole game
-- re-skins from here.
local Theme = {}

Theme.Colors = {
	-- windows / wood
	bg = Color3.fromRGB(42, 31, 20), -- backdrop, loading screen
	panel = Color3.fromRGB(122, 78, 42), -- window wood
	panelLight = Color3.fromRGB(150, 99, 58), -- raised wood (cards, neutral buttons)
	panelDark = Color3.fromRGB(94, 59, 30), -- insets, title bars
	parchment = Color3.fromRGB(240, 220, 174), -- light content insets
	-- lines
	border = Color3.fromRGB(58, 36, 18), -- dark outline
	borderLight = Color3.fromRGB(232, 185, 90), -- gold trim
	-- text
	text = Color3.fromRGB(255, 241, 208), -- cream (on wood)
	textDark = Color3.fromRGB(74, 44, 21), -- brown (on parchment)
	textDim = Color3.fromRGB(227, 199, 155), -- warm tan
	-- accents
	accent = Color3.fromRGB(242, 181, 68), -- gold
	good = Color3.fromRGB(103, 176, 78), -- grass green
	bad = Color3.fromRGB(217, 88, 60), -- terracotta
	info = Color3.fromRGB(88, 167, 216), -- sky
	-- bars
	hp = Color3.fromRGB(111, 191, 87),
	hpBack = Color3.fromRGB(74, 43, 34),
	shield = Color3.fromRGB(124, 195, 232),
	-- currencies
	coins = Color3.fromRGB(255, 200, 60),
	gems = Color3.fromRGB(127, 220, 208),
	essence = Color3.fromRGB(198, 139, 238),
	shards = Color3.fromRGB(207, 196, 174),
	marks = Color3.fromRGB(240, 154, 98),
	tickets = Color3.fromRGB(239, 143, 194),
	medals = Color3.fromRGB(240, 168, 74),
}

Theme.Rarity = {
	Common = Color3.fromRGB(207, 198, 184),
	Uncommon = Color3.fromRGB(122, 204, 106),
	Rare = Color3.fromRGB(96, 158, 240),
	Epic = Color3.fromRGB(186, 116, 240),
	Legendary = Color3.fromRGB(255, 172, 44),
	Mythic = Color3.fromRGB(255, 92, 128),
	Secret = Color3.fromRGB(70, 60, 88),
	Cursed = Color3.fromRGB(164, 74, 196),
}

Theme.Variant = {
	Normal = Color3.fromRGB(139, 116, 92),
	Golden = Color3.fromRGB(226, 178, 52),
	Rainbow = Color3.fromRGB(196, 92, 204),
	DarkMatter = Color3.fromRGB(88, 54, 142),
}

Theme.Element = {
	Fire = Color3.fromRGB(240, 110, 50),
	Water = Color3.fromRGB(70, 140, 220),
	Grass = Color3.fromRGB(96, 180, 78),
	Light = Color3.fromRGB(250, 230, 120),
	Dark = Color3.fromRGB(120, 80, 170),
	Neutral = Color3.fromRGB(180, 180, 180),
}

Theme.Border = 3
Theme.Pad = 8

-- Bevel edges for the pixel 3D look: lighten toward the light (top/left), darken away (bottom/right).
function Theme.hilite(base: Color3): Color3
	return base:Lerp(Color3.new(1, 1, 1), 0.22)
end

function Theme.shadow(base: Color3): Color3
	return base:Lerp(Color3.new(0, 0, 0), 0.3)
end

local pixelFont = nil
local triedFont = false
-- Returns a Font object for TextLabel.FontFace (Press Start 2P if available, else Arcade).
function Theme.font(): Font
	if not triedFont then
		triedFont = true
		local ok, f = pcall(function()
			return Font.new(
				"rbxasset://fonts/families/PressStart2P.json",
				Enum.FontWeight.Regular,
				Enum.FontStyle.Normal
			)
		end)
		if ok and f then
			pixelFont = f
		end
	end
	return pixelFont or Font.fromEnum(Enum.Font.Arcade)
end

-- Readable monospace font for logs / diagnostics (pixel fonts are hard to read at length).
function Theme.monoFont(): Font
	return Font.fromEnum(Enum.Font.Code)
end

function Theme.currencyColor(currency: string): Color3
	return Theme.Colors[currency] or Theme.Colors.text
end

return Theme
