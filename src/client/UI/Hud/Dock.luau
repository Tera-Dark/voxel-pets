--!nonstrict
-- Bottom dock: unlocked features only (the big BATTLE button is the entry to stages), grouped
-- (adventure / pets / base / more) with gaps, pixel icon + label tiles. A tab collapses or
-- expands it; it hides while a screen is open. It sits between the pet chip and the BATTLE
-- button when it fits, otherwise one row higher (narrow phones), so labels never disappear.
-- Tiles show a "!" badge (something to do) or a NEW tag (unlocked this session, until opened).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Features = require(Shared.Config.Features)

local PixelIcons = require(script.Parent.Parent.PixelIcons)

local Dock = {}

local TILE_W, TILE_H = 84, 62
local GAP, GROUP_GAP = 3, 8
local BOTTOM_MARGIN = 8
local LEFT_RESERVED = 250 -- pet chip: 10 + 230 + 10
local RIGHT_RESERVED = 196 -- BATTLE: 176 + 10 + 10
-- In the bottom row the dock centres on the gap between the chip and BATTLE, not the screen.
local ROW_OFFSET = (LEFT_RESERVED - RIGHT_RESERVED) / 2

Dock.KEYS = { "stages", "stats" }
Dock.TILE_W, Dock.TILE_H = TILE_W, TILE_H

local function inDock(f)
	return f.dock ~= false
end

-- opts.onOpen(featureId), opts.onUnlocked(features) (live unlocks only, not the first build),
-- opts.canvasWidth() -> logical canvas width (for the row decision)
function Dock.build(root, ctx, opts)
	local C, Theme, State = ctx.C, ctx.Theme, ctx.State
	local self = {
		expanded = true, -- the player's choice
		screenOpen = false,
		buttons = {},
		badges = {},
		fresh = {}, -- [id] = true while the NEW tag shows
		signature = nil,
		raised = false,
	}

	local frame = C.frame({
		Name = "Dock",
		Size = UDim2.fromOffset(TILE_W, TILE_H),
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -BOTTOM_MARGIN),
		BackgroundTransparency = 1,
		Parent = root,
	})
	local layoutObj =
		C.list(frame, GAP, Enum.FillDirection.Horizontal, Enum.HorizontalAlignment.Center)
	layoutObj.VerticalAlignment = Enum.VerticalAlignment.Bottom

	local toggle = C.button({
		Name = "DockToggle",
		Size = UDim2.fromOffset(72, 18),
		AnchorPoint = Vector2.new(0.5, 1),
		Text = "v",
		TextSize = 8,
		BackgroundColor3 = Theme.Colors.panel,
		Parent = root,
	})
	local toggleDot = C.frame({
		Name = "Dot",
		Size = UDim2.fromOffset(10, 10),
		Position = UDim2.new(1, -6, 0, -4),
		BackgroundColor3 = Theme.Colors.bad,
		Visible = false,
		ZIndex = 3,
		Parent = toggle,
	})

	local function anyBadge()
		for id, on in self.badges do
			if on and self.buttons[id] then
				return true
			end
		end
		return false
	end

	local function paintItem(id)
		local b = self.buttons[id]
		if not b then
			return
		end
		b.Badge.Visible = self.badges[id] == true
		b.New.Visible = self.fresh[id] == true
	end

	function self.relayout()
		local count, groupSet, groups = 0, {}, 0
		for id in self.buttons do
			count += 1
			local g = Features.ById[id].group
			if not groupSet[g] then
				groupSet[g] = true
				groups += 1
			end
		end
		local width = count * TILE_W
			+ math.max(0, count - 1) * GAP
			+ math.max(0, groups - 1) * GROUP_GAP
		local canvasWidth = if opts.canvasWidth then opts.canvasWidth() else 1280
		self.raised = width > canvasWidth - LEFT_RESERVED - RIGHT_RESERVED
		local bottom = if self.raised then BOTTOM_MARGIN + 66 else BOTTOM_MARGIN
		local offsetX = if self.raised then 0 else ROW_OFFSET
		frame.Size = UDim2.fromOffset(math.max(width, TILE_W), TILE_H)
		frame.Position = UDim2.new(0.5, offsetX, 1, -bottom)
		frame.Visible = self.expanded and not self.screenOpen and count > 0
		-- nothing worth collapsing until the dock has a few tiles
		toggle.Visible = not self.screenOpen and (count >= 3 or not self.expanded)
		if self.expanded then
			toggle.Text = "v"
			toggle.Size = UDim2.fromOffset(72, 16)
			toggle.Position = UDim2.new(0.5, offsetX, 1, -(bottom + TILE_H + 4))
		else
			toggle.Text = "^  MENU"
			toggle.Size = UDim2.fromOffset(110, 24)
			toggle.Position = UDim2.new(0.5, ROW_OFFSET, 1, -BOTTOM_MARGIN)
		end
		toggleDot.Visible = not self.expanded and anyBadge()
		for id in self.buttons do
			paintItem(id)
		end
	end

	local function makeItem(f, order)
		local b = C.button({
			Name = "Dock_" .. f.id,
			Size = UDim2.fromOffset(TILE_W, TILE_H),
			Text = "",
			BackgroundColor3 = Theme.Colors.panel,
			LayoutOrder = order,
			Parent = frame,
		}, function()
			self.fresh[f.id] = nil
			paintItem(f.id)
			opts.onOpen(f.id)
		end)
		PixelIcons.new(f.icon, 30, { Position = UDim2.new(0.5, -15, 0, 7), Parent = b })
		C.label({
			Name = "Label",
			Size = UDim2.new(1, -4, 0, 16),
			Position = UDim2.new(0, 2, 1, -20),
			Text = f.label,
			TextSize = 8,
			TextXAlignment = Enum.TextXAlignment.Center,
			Parent = b,
		})
		C.label({
			Name = "Badge",
			Size = UDim2.fromOffset(16, 16),
			Position = UDim2.new(1, -18, 0, 2),
			BackgroundTransparency = 0,
			BackgroundColor3 = Theme.Colors.bad,
			Text = "!",
			TextSize = 9,
			TextXAlignment = Enum.TextXAlignment.Center,
			ZIndex = 3,
			Visible = false,
			Parent = b,
		})
		C.label({
			Name = "New",
			Size = UDim2.fromOffset(30, 13),
			Position = UDim2.fromOffset(2, 2),
			BackgroundTransparency = 0,
			BackgroundColor3 = Theme.Colors.accent,
			Text = "NEW",
			TextSize = 7,
			TextColor3 = Theme.Colors.bg,
			TextXAlignment = Enum.TextXAlignment.Center,
			ZIndex = 3,
			Visible = false,
			Parent = b,
		})
		return b
	end

	function self.rebuild()
		local p = State.profile
		if not p then
			return
		end
		local unlocked = {}
		for _, f in Features.unlocked(p) do
			if inDock(f) then
				table.insert(unlocked, f)
			end
		end
		local ids = {}
		for _, f in unlocked do
			table.insert(ids, f.id)
		end
		local signature = table.concat(ids, ",")
		if signature == self.signature then
			return
		end
		local newly = {}
		if self.signature ~= nil then
			for _, f in unlocked do
				if not self.buttons[f.id] then
					self.fresh[f.id] = true
					table.insert(newly, f)
				end
			end
		end
		self.signature = signature
		for _, b in self.buttons do
			b:Destroy()
		end
		table.clear(self.buttons)
		for _, child in frame:GetChildren() do
			if child.Name == "Gap" then
				child:Destroy()
			end
		end
		local lastGroup = nil
		for _, f in unlocked do
			local groupIndex = table.find(Features.GROUP_ORDER, f.group) or 9
			local order = groupIndex * 100 + f.order
			if lastGroup and f.group ~= lastGroup then
				C.frame({
					Name = "Gap",
					Size = UDim2.fromOffset(GROUP_GAP - GAP, 8),
					BackgroundTransparency = 1,
					LayoutOrder = order - 1,
					Parent = frame,
				})
			end
			lastGroup = f.group
			self.buttons[f.id] = makeItem(f, order)
		end
		self.relayout()
		if #newly > 0 and opts.onUnlocked then
			opts.onUnlocked(newly)
		end
	end

	function self.setExpanded(value: boolean)
		self.expanded = value
		self.relayout()
	end

	-- A screen opened (name) or closed (nil): the dock steps aside while a screen is open.
	function self.onScreen(name)
		self.screenOpen = name ~= nil
		self.relayout()
	end

	function self.setBadge(id: string, on: boolean)
		if self.badges[id] == on then
			return
		end
		self.badges[id] = on
		paintItem(id)
		toggleDot.Visible = not self.expanded and anyBadge()
	end

	function self.button(id: string)
		return self.buttons[id]
	end

	toggle.Activated:Connect(function()
		self.setExpanded(not self.expanded)
	end)
	State.onKeys(Dock.KEYS, self.rebuild)
	self.rebuild()
	self.frame = frame
	self.toggle = toggle
	return self
end

return Dock
