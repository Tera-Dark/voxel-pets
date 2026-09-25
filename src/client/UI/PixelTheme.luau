--!nonstrict
-- Pixel-art UI theme: chunky borders, flat saturated colors, Press Start 2P (fallback Arcade).
local Theme = {}

Theme.Colors = {
	bg = Color3.fromRGB(24, 26, 40),
	panel = Color3.fromRGB(38, 42, 64),
	panelLight = Color3.fromRGB(54, 60, 90),
	border = Color3.fromRGB(12, 12, 20),
	borderLight = Color3.fromRGB(120, 130, 170),
	text = Color3.fromRGB(240, 240, 248),
	textDim = Color3.fromRGB(160, 168, 196),
	accent = Color3.fromRGB(255, 200, 60),
	good = Color3.fromRGB(90, 210, 110),
	bad = Color3.fromRGB(235, 80, 80),
	info = Color3.fromRGB(90, 170, 250),
	hp = Color3.fromRGB(90, 210, 110),
	hpBack = Color3.fromRGB(70, 30, 30),
	shield = Color3.fromRGB(120, 200, 255),
	coins = Color3.fromRGB(255, 200, 60),
	gems = Color3.fromRGB(120, 230, 230),
	essence = Color3.fromRGB(200, 120, 255),
	shards = Color3.fromRGB(180, 180, 200),
	marks = Color3.fromRGB(255, 140, 80),
	tickets = Color3.fromRGB(255, 120, 200),
	medals = Color3.fromRGB(255, 170, 60),
}

Theme.Rarity = {
	Common = Color3.fromRGB(190, 190, 200),
	Uncommon = Color3.fromRGB(110, 210, 110),
	Rare = Color3.fromRGB(90, 160, 255),
	Epic = Color3.fromRGB(190, 100, 255),
	Legendary = Color3.fromRGB(255, 170, 40),
	Mythic = Color3.fromRGB(255, 80, 120),
	Secret = Color3.fromRGB(40, 40, 60),
	Cursed = Color3.fromRGB(160, 60, 200),
}

Theme.Variant = {
	Normal = Color3.fromRGB(96, 110, 130),
	Golden = Color3.fromRGB(214, 168, 40),
	Rainbow = Color3.fromRGB(190, 80, 200),
	DarkMatter = Color3.fromRGB(70, 40, 120),
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

function Theme.currencyColor(currency: string): Color3
	return Theme.Colors[currency] or Theme.Colors.text
end

return Theme
