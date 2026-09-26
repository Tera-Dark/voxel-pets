--!nonstrict
-- UI snapshots: plays through the new-player flow in the client mock and exports the GUI tree at
-- key moments as JSON; scripts/render_ui.py turns them into PNGs (layout review without Studio).
--   lune run tools/ui_snapshot -- [outDir]        (default /tmp/ui_snapshots)
--   python3 scripts/render_ui.py [outDir]
local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")
local Mock = require("./roblox_mock")
local ClientMock = require("./client_mock")

local root = process.cwd:gsub("/$", "")
local outDir = "/tmp/ui_snapshots"
for _, a in process.args do
	if a ~= "--" then
		outDir = a
	end
end
if fs.isDir(outDir) then
	fs.removeDir(outDir)
end
fs.writeDir(outDir)

math.randomseed(20260926)
local M = Mock.new(root, { scheduler = true, placeId = 0 })
local Boot = M.load("src/server/Boot.luau")
M.spawn(function()
	Boot.run({ world = false })
end)
M.advance(0.1)
local CM = ClientMock.new(M, root, { userId = 4001, name = "Previewer" })
local Data = M.load("src/server/Registry.luau").get("DataService")

local count = 0
local function snap(name)
	count += 1
	local file = string.format("%s/%02d_%s.json", outDir, count, name)
	local dump = CM.dumpGui()
	-- the mock has no real AbsolutePosition: tell the renderer what the pointer targets
	local Highlight = CM.require("src/client/UI/Highlight.luau")
	local target, text = Highlight.current()
	if target then
		dump.highlight = { target = target.Name, text = text }
	end
	fs.writeFile(file, serde.encode("json", dump))
	print("  " .. file)
end
local function named(name)
	return CM.find(function(d)
		return d.Name == name and CM.visible(d)
	end)
end
local function give(fields)
	local d = Data.Get(CM.serverPlayer)
	local keys = {}
	for k, v in fields do
		d[k] = v
		table.insert(keys, k)
	end
	Data.ReplicateKeys(CM.serverPlayer, keys)
	M.advance(0.3)
end

CM.start()
M.advance(0.05)
snap("loading")
M.advance(6)
local Screens = CM.require("src/client/UI/ScreenManager.luau")
local C = CM.require("src/client/UI/Components.luau")
snap("first_join_partner_picker")

CM.click(
	CM.find(function(d)
		return d.Name == "Choose" and d.Parent and d.Parent.Name == "Starter_Emberfox"
	end),
	0.8
)
snap("tutorial_pointer_battle")
CM.click(named("BattleButton"), 0.8)
snap("stages_pointer_fight")
CM.click(named("FightButton"), 3)
snap("battle_playback")
CM.click(CM.byText("SKIP", "TextButton"), 2)
snap("battle_result")
CM.click(CM.byText("Close", "TextButton"), 0.8)
snap("hatch_unlocked_pointer")
CM.click(named("Dock_Hatch"), 0.8)
snap("hatch_free_egg")
CM.click(named("HatchFree"), 1)
snap("hatch_result")
CM.run(function()
	C.closeTopModal()
	Screens.close()
end, 0.6)
CM.click(named("BattleButton"), 0.8)
CM.click(named("FightButton"), 1)
CM.click(CM.byText("SKIP", "TextButton"), 2)
CM.click(CM.byText("Close", "TextButton"), 0.8)
snap("tutorial_complete")
CM.click(CM.byText("LET'S GO", "TextButton"), 0.4)
snap("hud_after_tutorial")

local stages = {}
for s = 1, 3 do
	stages["1-" .. s] = 3
end
M.advance(6)
give({ stages = stages, coins = 1250 })
M.advance(0.8)
snap("camp_unlocked_banner")

local all = {}
for z = 1, 2 do
	for s = 1, 10 do
		all[z .. "-" .. s] = 3
	end
end
give({
	stages = all,
	coins = 48210,
	gems = 355,
	essence = 42,
	shards = 120,
	tickets = 4,
	marks = 70,
	medals = 30,
})
M.advance(9) -- let unlock banners expire
CM.click(named("MoreCurrencies"), 0.3)
snap("late_game_hud_currencies")
CM.click(named("MoreCurrencies"), 0.3)
CM.click(named("Dock_Pets"), 0.8)
snap("pets_screen_dock_collapsed")
CM.run(function()
	Screens.close()
end, 0.3)
CM.click(named("SettingsButton"), 0.4)
snap("settings")
CM.run(function()
	C.closeTopModal()
end, 0.3)

CM.setViewport(844, 390)
CM.run(function() end, 0.5)
snap("mobile_844x390_hud")
CM.click(named("BattleButton"), 0.8)
snap("mobile_844x390_stages")

print(string.format("%d snapshots, %d client errors", count, #CM.errors))
for _, e in CM.errors do
	print("  ERROR " .. string.sub(e, 1, 300))
end
