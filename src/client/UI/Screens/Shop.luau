--!nonstrict
-- Shop: gamepasses + gem packs (MarketplaceService prompts) and the gem shop (server-side purchases).
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")

local Screen = {}
local ui = {}
local shop = nil
local PASS_ORDER = { "VIP", "TripleHatch", "LuckyCharm" }
local PRODUCT_ORDER = { "GemsSmall", "GemsMedium", "GemsLarge" }

local function clear(frame)
	for _, child in frame:GetChildren() do
		if
			not child:IsA("UIListLayout")
			and not child:IsA("UIPadding")
			and not child:IsA("UIGridLayout")
		then
			child:Destroy()
		end
	end
end

local function promptPass(ctx, id)
	if id == 0 then
		ctx.toast("Coming soon (pass not configured yet)", "info")
		return
	end
	local ok = pcall(
		MarketplaceService.PromptGamePassPurchase,
		MarketplaceService,
		Players.LocalPlayer,
		id
	)
	if not ok then
		ctx.toast("Purchase prompt failed", "bad")
	end
end

local function promptProduct(ctx, id)
	if id == 0 then
		ctx.toast("Coming soon (product not configured yet)", "info")
		return
	end
	local ok =
		pcall(MarketplaceService.PromptProductPurchase, MarketplaceService, Players.LocalPlayer, id)
	if not ok then
		ctx.toast("Purchase prompt failed", "bad")
	end
end

local function render(ctx)
	local C, Theme, State = ctx.C, ctx.Theme, ctx.State
	if not shop then
		return
	end
	local p = State.profile
	clear(ui.passes)
	for i, key in PASS_ORDER do
		local def = shop.passes[key]
		local owned = p.passes and p.passes[key]
		local card =
			C.panel({ Size = UDim2.fromOffset(200, 120), LayoutOrder = i, Parent = ui.passes })
		C.label({
			Size = UDim2.new(1, -12, 0, 18),
			Position = UDim2.fromOffset(6, 6),
			Text = def.displayName,
			TextSize = 10,
			TextColor3 = Theme.Colors.accent,
			Parent = card,
		})
		C.label({
			Size = UDim2.new(1, -12, 0, 50),
			Position = UDim2.fromOffset(6, 26),
			Text = def.description,
			TextSize = 8,
			Parent = card,
		})
		local b = C.button({
			Size = UDim2.new(1, -12, 0, 26),
			Position = UDim2.new(0, 6, 1, -32),
			Text = owned and "OWNED" or "Buy (Robux)",
			TextSize = 9,
			BackgroundColor3 = owned and Theme.Colors.panel or Theme.Colors.good,
			Parent = card,
		}, function()
			promptPass(ctx, def.id)
		end)
		C.setEnabled(b, not owned)
	end
	clear(ui.products)
	for i, key in PRODUCT_ORDER do
		local def = shop.products[key]
		local card =
			C.panel({ Size = UDim2.fromOffset(200, 90), LayoutOrder = i, Parent = ui.products })
		C.label({
			Size = UDim2.new(1, -12, 0, 18),
			Position = UDim2.fromOffset(6, 6),
			Text = def.displayName,
			TextSize = 10,
			TextColor3 = Theme.Colors.gems,
			Parent = card,
		})
		C.label({
			Size = UDim2.new(1, -12, 0, 16),
			Position = UDim2.fromOffset(6, 26),
			Text = def.gems .. " gems",
			TextSize = 9,
			Parent = card,
		})
		C.button({
			Size = UDim2.new(1, -12, 0, 26),
			Position = UDim2.new(0, 6, 1, -32),
			Text = "Buy (Robux)",
			TextSize = 9,
			BackgroundColor3 = Theme.Colors.good,
			Parent = card,
		}, function()
			promptProduct(ctx, def.id)
		end)
	end
	clear(ui.gemShop)
	for i, item in shop.gemShop do
		local card =
			C.panel({ Size = UDim2.fromOffset(200, 110), LayoutOrder = i, Parent = ui.gemShop })
		C.label({
			Size = UDim2.new(1, -12, 0, 18),
			Position = UDim2.fromOffset(6, 6),
			Text = item.displayName,
			TextSize = 10,
			TextColor3 = Theme.Colors.accent,
			Parent = card,
		})
		C.label({
			Size = UDim2.new(1, -12, 0, 40),
			Position = UDim2.fromOffset(6, 26),
			Text = item.description,
			TextSize = 8,
			Parent = card,
		})
		local b = C.button({
			Size = UDim2.new(1, -12, 0, 26),
			Position = UDim2.new(0, 6, 1, -32),
			Text = item.gems .. " gems",
			TextSize = 9,
			BackgroundColor3 = Theme.Colors.info,
			Parent = card,
		}, function()
			local ok, err, got = ctx.Net.invoke("BuyWithGems", item.id)
			if ok then
				ctx.toast(
					"Purchased "
						.. item.displayName
						.. (got and got.coins and (" (+" .. got.coins .. " coins)") or ""),
					"good"
				)
			else
				ctx.toast(err, "bad")
			end
		end)
		C.setEnabled(b, (p.gems or 0) >= item.gems)
	end
	ui.note.Text = shop.paidRandomItemsRestricted
			and "Paid random items are not available in your region; eggs can only be bought with coins here."
		or "Eggs show full numeric odds before purchase (see the Hatchery). Gems are not refundable."
end

function Screen.build(host, ctx)
	Screen.ctx = ctx
	local C, Theme = ctx.C, ctx.Theme
	local root = C.panel({
		Name = "Shop",
		Size = UDim2.fromOffset(880, 520),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Parent = host,
	}, "Shop")
	local function section(y, text)
		C.label({
			Size = UDim2.new(1, -16, 0, 16),
			Position = UDim2.fromOffset(8, y),
			Text = text,
			TextSize = 9,
			TextColor3 = Theme.Colors.textDim,
			Parent = root,
		})
	end
	section(34, "GAMEPASSES")
	ui.passes = C.frame({
		Size = UDim2.new(1, -16, 0, 120),
		Position = UDim2.fromOffset(8, 52),
		BackgroundTransparency = 1,
		Parent = root,
	})
	C.list(ui.passes, 10, Enum.FillDirection.Horizontal, Enum.HorizontalAlignment.Center)
	section(180, "GEMS")
	ui.products = C.frame({
		Size = UDim2.new(1, -16, 0, 90),
		Position = UDim2.fromOffset(8, 198),
		BackgroundTransparency = 1,
		Parent = root,
	})
	C.list(ui.products, 10, Enum.FillDirection.Horizontal, Enum.HorizontalAlignment.Center)
	section(296, "GEM SHOP")
	ui.gemShop = C.frame({
		Size = UDim2.new(1, -16, 0, 110),
		Position = UDim2.fromOffset(8, 314),
		BackgroundTransparency = 1,
		Parent = root,
	})
	C.list(ui.gemShop, 10, Enum.FillDirection.Horizontal, Enum.HorizontalAlignment.Center)
	ui.note = C.label({
		Size = UDim2.new(1, -16, 0, 40),
		Position = UDim2.new(0, 8, 1, -50),
		TextSize = 8,
		TextColor3 = Theme.Colors.textDim,
		Parent = root,
	})
	C.button({
		Size = UDim2.fromOffset(28, 24),
		Position = UDim2.new(1, -31, 0, 3),
		Text = "X",
		BackgroundColor3 = Theme.Colors.bad,
		Parent = root,
	}, function()
		ctx.Screens.close()
	end)
	ctx.State.onKeys({ "gems", "passes", "purchases" }, function()
		if root.Visible then
			render(ctx)
		end
	end)
	return root
end

function Screen.onOpen()
	local ctx = Screen.ctx
	local ok, err, v = ctx.Net.invoke("GetShop")
	if ok then
		shop = v
	else
		ctx.toast(err, "bad")
	end
	render(ctx)
end

return Screen
