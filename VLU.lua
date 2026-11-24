--[[
	Volleyball Legends Utility (VLU) v1.0
	Dynamic Island UI + оптимизация + утилиты | Luau / Delta (mobile)
	Без читов: только интерфейс, статистика и оптимизация клиента.
]]

local ENV = (getgenv and getgenv()) or _G
if ENV.VLU_Unload then pcall(ENV.VLU_Unload) end

---------------------------------------------------------------- services
local S = setmetatable({}, {__index = function(t, k)
	local ok, v = pcall(game.GetService, game, k)
	if ok then rawset(t, k, v) end
	return v
end})
local LP = S.Players.LocalPlayer
local E = Enum
local OUT, IN = E.EasingDirection.Out, E.EasingDirection.In
local QUINT, BACK, QUAD = E.EasingStyle.Quint, E.EasingStyle.Back, E.EasingStyle.Quad

---------------------------------------------------------------- config
local FILE = "VLU_config.json"
local ACCENTS = {
	Color3.fromRGB(10, 132, 255), Color3.fromRGB(175, 82, 222),
	Color3.fromRGB(48, 209, 88), Color3.fromRGB(255, 159, 10),
}
local T = {
	bg = Color3.fromRGB(16, 16, 20), side = Color3.fromRGB(22, 22, 27),
	row = Color3.fromRGB(28, 28, 34), btn = Color3.fromRGB(42, 42, 50),
	off = Color3.fromRGB(70, 70, 78), text = Color3.fromRGB(240, 240, 245),
	sub = Color3.fromRGB(150, 150, 160),
	green = Color3.fromRGB(48, 209, 88), yellow = Color3.fromRGB(255, 204, 0),
	red = Color3.fromRGB(255, 69, 58),
}
local CFG = {
	saver = false, noShadows = false, noFx = false, noPost = false,
	afk3d = false, antiAfk = true,
	quality = 0, fpsCap = 0, memWarn = 0,
	accent = 1, scale = 1, px = 0.5, py = 0.02, notes = "",
}
pcall(function()
	if isfile and readfile and isfile(FILE) then
		local d = S.HttpService:JSONDecode(readfile(FILE))
		for k, v in pairs(d) do
			if CFG[k] ~= nil and type(v) == type(CFG[k]) then CFG[k] = v end
		end
	end
end)
local function save()
	pcall(function()
		if writefile then writefile(FILE, S.HttpService:JSONEncode(CFG)) end
	end)
end
local function accent() return ACCENTS[CFG.accent] or ACCENTS[1] end
local function safe(f, ...)
	local ok, e = pcall(f, ...)
	if not ok then warn("[VLU]", e) end
end

---------------------------------------------------------------- helpers
local conns = {}
local function track(c) conns[#conns + 1] = c return c end

local function new(class, props, parent)
	local o = Instance.new(class)
	for k, v in pairs(props or {}) do o[k] = v end
	if parent then o.Parent = parent end
	return o
end
local function corner(o, r) return new("UICorner", {CornerRadius = UDim.new(0, r)}, o) end
local function TI(t, style, dir) return TweenInfo.new(t, style or QUAD, dir or OUT) end
local function tw(o, props, info)
	local t = S.TweenService:Create(o, info, props)
	t:Play()
	return t
end
local function lbl(parent, p)
	p.BackgroundTransparency = 1
	p.Font = p.Font or E.Font.GothamBold
	p.TextColor3 = p.TextColor3 or T.text
	p.TextSize = p.TextSize or 13
	return new("TextLabel", p, parent)
end
local LEFT = E.TextXAlignment.Left
local ORDER = 0
local function ord() ORDER += 1 return ORDER end

local accFns = {}
local function onAccent(f) accFns[#accFns + 1] = f f() end
local function applyAccent() for _, f in ipairs(accFns) do safe(f) end end

local function fmt(sec)
	sec = math.floor(sec)
	local h, m, s = math.floor(sec / 3600), math.floor(sec % 3600 / 60), sec % 60
	if h > 0 then return ("%d:%02d:%02d"):format(h, m, s) end
	return ("%02d:%02d"):format(m, s)
end

---------------------------------------------------------------- gui root
local gui = new("ScreenGui", {
	Name = "VLU_" .. math.random(100000, 999999), ResetOnSpawn = false,
	IgnoreGuiInset = true, DisplayOrder = 100, ZIndexBehavior = E.ZIndexBehavior.Sibling,
})
local okp = pcall(function() gui.Parent = (gethui and gethui()) or S.CoreGui end)
if not okp or not gui.Parent then gui.Parent = LP:WaitForChild("PlayerGui") end

local function screen()
	local s = gui.AbsoluteSize
	if s.X < 10 then s = workspace.CurrentCamera.ViewportSize end
	return s
end

local function notify(text)
	local l = new("TextLabel", {
		AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -20),
		Size = UDim2.fromOffset(0, 34), AutomaticSize = E.AutomaticSize.X,
		BackgroundColor3 = Color3.fromRGB(10, 10, 12), BackgroundTransparency = 1,
		TextColor3 = T.text, TextTransparency = 1, Font = E.Font.GothamMedium,
		TextSize = 13, Text = "   " .. text .. "   ", ZIndex = 50,
	}, gui)
	corner(l, 17)
	tw(l, {BackgroundTransparency = 0.1, TextTransparency = 0, Position = UDim2.new(0.5, 0, 1, -34)}, TI(0.35, QUINT))
	task.delay(2.4, function()
		tw(l, {BackgroundTransparency = 1, TextTransparency = 1}, TI(0.3))
		task.wait(0.35)
		l:Destroy()
	end)
end

---------------------------------------------------------------- state
local st = {
	expanded = false, menuOpen = false, tok = 0, glow = false,
	drag = false, input = nil, start = Vector2.zero, off = Vector2.zero, moved = false,
	fps = 60, frames = 0, fpsAcc = 0, t0 = tick(),
	pos = {x = 0, y = -60, vx = 0, vy = 0}, tx = 0, ty = 0,
	sw = {run = false, acc = 0, t0 = 0},
}
local U = {tg = {}}

---------------------------------------------------------------- optimization
local Opt = {fx = setmetatable({}, {__mode = "k"}), post = setmetatable({}, {__mode = "k"}), base = {}}
pcall(function()
	Opt.base.shadows = S.Lighting.GlobalShadows
	Opt.base.quality = settings().Rendering.QualityLevel
end)
local FX = {ParticleEmitter = true, Trail = true, Beam = true, Fire = true, Smoke = true, Sparkles = true}
local function isFx(d) return FX[d.ClassName] == true end
local function isPost(d) return d:IsA("PostEffect") end

local function sweep(root, pred, store)
	local n = 0
	for _, d in ipairs(root:GetDescendants()) do
		if pred(d) then
			if store[d] == nil then store[d] = d.Enabled end
			d.Enabled = false
		end
		n += 1
		if n % 800 == 0 then task.wait() end
	end
end
local function restore(store)
	for inst, old in pairs(store) do
		pcall(function() if inst.Parent then inst.Enabled = old end end)
		store[inst] = nil
	end
end

function Opt.setFx(on)
	if Opt.fxConn then Opt.fxConn:Disconnect() Opt.fxConn = nil end
	if on then
		task.spawn(sweep, workspace, isFx, Opt.fx)
		Opt.fxConn = workspace.DescendantAdded:Connect(function(d)
			if isFx(d) then
				pcall(function() Opt.fx[d] = d.Enabled d.Enabled = false end)
			end
		end)
	else
		restore(Opt.fx)
	end
end
function Opt.setPost(on)
	if Opt.postConn then Opt.postConn:Disconnect() Opt.postConn = nil end
	if on then
		task.spawn(function()
			sweep(S.Lighting, isPost, Opt.post)
			if workspace.CurrentCamera then sweep(workspace.CurrentCamera, isPost, Opt.post) end
		end)
		Opt.postConn = S.Lighting.DescendantAdded:Connect(function(d)
			if isPost(d) then
				pcall(function() Opt.post[d] = d.Enabled d.Enabled = false end)
			end
		end)
	else
		restore(Opt.post)
	end
end
function Opt.setShadows(on)
	pcall(function()
		S.Lighting.GlobalShadows = on and false or (Opt.base.shadows ~= false)
	end)
end
function Opt.setQuality(n)
	pcall(function()
		local r = settings().Rendering
		if n == 0 then
			r.QualityLevel = Opt.base.quality or E.QualityLevel.Automatic
		else
			r.QualityLevel = E.QualityLevel[("Level%02d"):format(n)]
		end
	end)
end
function Opt.setCap(n)
	if setfpscap then
		pcall(setfpscap, n == 0 and 60 or n)
	else
		notify("setfpscap не поддерживается")
	end
end
function Opt.clean()
	local before = S.Stats:GetTotalMemoryUsageMb()
	collectgarbage("collect")
	task.wait(0.3)
	local after = S.Stats:GetTotalMemoryUsageMb()
	notify(("Память: %d → %d МБ"):format(before, after))
end

local afkConn
local function setAntiAfk(on)
	if afkConn then afkConn:Disconnect() afkConn = nil end
	if on then
		afkConn = LP.Idled:Connect(function()
			pcall(function()
				S.VirtualUser:CaptureController()
				S.VirtualUser:ClickButton2(Vector2.new())
			end)
		end)
	end
end

local function rejoin()
	notify("Перезаход…")
	pcall(function()
		if #S.Players:GetPlayers() <= 1 then
			LP:Kick("\nПерезаход…")
			task.wait()
			S.TeleportService:Teleport(game.PlaceId, LP)
		else
			S.TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, LP)
		end
	end)
end

local function serverHop()
	notify("Ищу другой сервер…")
	local ok, res = pcall(function()
		local url = ("https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Asc&limit=100"):format(game.PlaceId)
		return S.HttpService:JSONDecode(game:HttpGet(url))
	end)
	if not ok or type(res) ~= "table" or not res.data then
		return notify("Не удалось получить список серверов")
	end
	local list = {}
	for _, s in ipairs(res.data) do
		if s.id ~= game.JobId and s.playing < s.maxPlayers then list[#list + 1] = s.id end
	end
	if #list == 0 then return notify("Нет подходящих серверов") end
	pcall(function()
		S.TeleportService:TeleportToPlaceInstance(game.PlaceId, list[math.random(#list)], LP)
	end)
end

---------------------------------------------------------------- DYNAMIC ISLAND
local isl = new("Frame", {
	Name = "Island", AnchorPoint = Vector2.new(0.5, 0), Size = UDim2.fromOffset(24, 24),
	BackgroundColor3 = Color3.new(0, 0, 0), BorderSizePixel = 0, ClipsDescendants = true, ZIndex = 10,
}, gui)
U.islCorner = new("UICorner", {CornerRadius = UDim.new(0, 17)}, isl)
U.islScale = new("UIScale", {Scale = CFG.scale}, isl)
U.stroke = new("UIStroke", {
	Color = Color3.new(1, 1, 1), Thickness = 1, Transparency = 0.4,
	ApplyStrokeMode = E.ApplyStrokeMode.Border,
}, isl)
local IDLE_SEQ = ColorSequence.new(Color3.fromRGB(62, 62, 70))
U.grad = new("UIGradient", {Color = IDLE_SEQ}, U.stroke)

-- компактный вид
U.compact = new("CanvasGroup", {Size = UDim2.new(1, 0, 0, 34), BackgroundTransparency = 1, GroupTransparency = 1}, isl)
U.cFps = lbl(U.compact, {Size = UDim2.fromScale(0.37, 1), Text = "-- FPS", TextSize = 12})
U.cTime = lbl(U.compact, {Position = UDim2.fromScale(0.37, 0), Size = UDim2.fromScale(0.33, 1), Text = "00:00", TextSize = 12, TextColor3 = T.sub})
U.cPing = lbl(U.compact, {Position = UDim2.fromScale(0.70, 0), Size = UDim2.fromScale(0.30, 1), Text = "-- ms", TextSize = 12})

-- карточка
U.card = new("CanvasGroup", {Size = UDim2.fromOffset(300, 232), BackgroundTransparency = 1, GroupTransparency = 1, Visible = false}, isl)
lbl(U.card, {Position = UDim2.fromOffset(16, 10), Size = UDim2.new(1, -32, 0, 18), Text = "Volleyball Legends • Utility", TextSize = 12, TextColor3 = T.sub, TextXAlignment = LEFT})
local function tile(x, y, title)
	local f = new("Frame", {Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(134, 44), BackgroundColor3 = Color3.fromRGB(28, 28, 32), BorderSizePixel = 0}, U.card)
	corner(f, 12)
	lbl(f, {Position = UDim2.fromOffset(10, 4), Size = UDim2.new(1, -20, 0, 14), Text = title, TextSize = 10, TextColor3 = T.sub, Font = E.Font.GothamMedium, TextXAlignment = LEFT})
	return lbl(f, {Position = UDim2.fromOffset(10, 19), Size = UDim2.new(1, -20, 0, 20), Text = "--", TextSize = 15, TextXAlignment = LEFT})
end
U.tFps = tile(10, 36, "FPS")
U.tPing = tile(156, 36, "ПИНГ")
U.tMem = tile(10, 86, "ПАМЯТЬ ROBLOX")
U.tClock = tile(156, 86, "ВРЕМЯ")
U.tPlay = tile(10, 136, "В ИГРЕ")
U.tPlayers = tile(156, 136, "ИГРОКОВ")
U.openBtn = new("TextButton", {
	Position = UDim2.fromOffset(10, 188), Size = UDim2.fromOffset(280, 36), BackgroundColor3 = accent(),
	Text = "Интерфейс", TextColor3 = Color3.new(1, 1, 1), Font = E.Font.GothamBold, TextSize = 14,
	AutoButtonColor = false, BorderSizePixel = 0,
}, U.card)
corner(U.openBtn, 12)
onAccent(function() U.openBtn.BackgroundColor3 = accent() end)

local function setExpanded(v)
	if st.expanded == v then return end
	st.expanded = v
	st.tok += 1
	local tok = st.tok
	if v then
		U.card.Visible = true
		tw(isl, {Size = UDim2.fromOffset(300, 232)}, TI(0.65, BACK))
		tw(U.islCorner, {CornerRadius = UDim.new(0, 28)}, TI(0.45, QUINT))
		tw(U.compact, {GroupTransparency = 1}, TI(0.12))
		task.delay(0.14, function()
			if st.tok ~= tok then return end
			U.compact.Visible = false
			tw(U.card, {GroupTransparency = 0}, TI(0.3))
		end)
	else
		U.compact.Visible = true
		tw(U.card, {GroupTransparency = 1}, TI(0.12))
		tw(isl, {Size = UDim2.fromOffset(170, 34)}, TI(0.42, QUINT))
		tw(U.islCorner, {CornerRadius = UDim.new(0, 17)}, TI(0.42, QUINT))
		task.delay(0.14, function()
			if st.tok ~= tok then return end
			U.card.Visible = false
			tw(U.compact, {GroupTransparency = 0}, TI(0.25))
		end)
	end
end

---------------------------------------------------------------- drag (spring + glow)
local function pointer(i)
	if i.UserInputType == E.UserInputType.Touch then
		local inset = S.GuiService:GetGuiInset()
		return Vector2.new(i.Position.X + inset.X, i.Position.Y + inset.Y)
	end
	return S.UserInputService:GetMouseLocation()
end

local function clampTarget()
	local scr, sz = screen(), isl.AbsoluteSize
	local hw = sz.X / 2 + 6
	local tx = math.clamp(st.tx, hw, math.max(hw, scr.X - hw))
	local ty = math.clamp(st.ty, 6, math.max(6, scr.Y - sz.Y - 6))
	return tx, ty
end

local function setGlow(on)
	st.glow = on
	if on then
		U.grad.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, accent()),
			ColorSequenceKeypoint.new(0.5, Color3.new(1, 1, 1)),
			ColorSequenceKeypoint.new(1, accent()),
		})
		tw(U.stroke, {Thickness = 3, Transparency = 0}, TI(0.2, QUINT))
		tw(U.islScale, {Scale = CFG.scale * 1.07}, TI(0.4, BACK))
	else
		tw(U.stroke, {Thickness = 1, Transparency = 0.4}, TI(0.3, QUINT))
		tw(U.islScale, {Scale = CFG.scale}, TI(0.4, BACK))
		task.delay(0.3, function() if not st.glow then U.grad.Color = IDLE_SEQ end end)
	end
end

local function beginDrag()
	if st.drag or not st.input then return end
	st.drag = true
	setGlow(true)
	st.off = Vector2.new(st.pos.x, st.pos.y) - pointer(st.input)
	st.tx, st.ty = st.pos.x, st.pos.y
end

local function snap()
	local scr = screen()
	st.tx, st.ty = clampTarget()
	if math.abs(st.tx - scr.X / 2) < 80 then st.tx = scr.X / 2 end
	CFG.px, CFG.py = st.tx / scr.X, st.ty / scr.Y
	save()
end

track(isl.InputBegan:Connect(function(i)
	if st.input then return end
	if i.UserInputType ~= E.UserInputType.Touch and i.UserInputType ~= E.UserInputType.MouseButton1 then return end
	st.input, st.start, st.moved, st.drag = i, pointer(i), false, false
	task.delay(0.28, function()
		if st.input == i and not st.drag then beginDrag() end
	end)
end))
track(S.UserInputService.InputChanged:Connect(function(i)
	if not st.input then return end
	if i == st.input or i.UserInputType == E.UserInputType.MouseMovement then
		local p = pointer(st.input)
		if not st.drag and (p - st.start).Magnitude > 10 then
			st.moved = true
			beginDrag()
		end
		if st.drag then st.tx, st.ty = p.X + st.off.X, p.Y + st.off.Y end
	end
end))
track(S.UserInputService.InputEnded:Connect(function(i)
	local cur = st.input
	if not cur then return end
	local same = (i == cur) or (i.UserInputType == E.UserInputType.MouseButton1 and cur.UserInputType == E.UserInputType.MouseButton1)
	if not same then return end
	local was = st.drag
	st.input, st.drag = nil, false
	if was then
		setGlow(false)
		snap()
	else
		setExpanded(not st.expanded)
	end
end))

---------------------------------------------------------------- MAIN MENU
local MW, MH = 480, 300
U.mHold = new("Frame", {
	Name = "Menu", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(MW, MH), BackgroundTransparency = 1, Visible = false, ZIndex = 5,
}, gui)
U.mFit = new("UIScale", {}, U.mHold)
U.menu = new("CanvasGroup", {
	AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = T.bg, BorderSizePixel = 0, GroupTransparency = 1,
}, U.mHold)
corner(U.menu, 22)
new("UIStroke", {Color = Color3.fromRGB(50, 50, 58), Thickness = 1}, U.menu)
U.mScale = new("UIScale", {Scale = 0.85}, U.menu)

lbl(U.menu, {Position = UDim2.fromOffset(18, 0), Size = UDim2.fromOffset(300, 44), Text = "VL Utility  v1.0", TextSize = 15, TextXAlignment = LEFT})
U.closeBtn = new("TextButton", {
	AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 9), Size = UDim2.fromOffset(34, 26),
	BackgroundColor3 = T.btn, Text = "✕", TextColor3 = T.text, Font = E.Font.GothamBold, TextSize = 13,
	AutoButtonColor = false, BorderSizePixel = 0,
}, U.menu)
corner(U.closeBtn, 8)

local side = new("Frame", {Position = UDim2.fromOffset(8, 44), Size = UDim2.fromOffset(112, MH - 52), BackgroundColor3 = T.side, BorderSizePixel = 0}, U.menu)
corner(side, 14)
new("UIListLayout", {Padding = UDim.new(0, 6), SortOrder = E.SortOrder.LayoutOrder}, side)
new("UIPadding", {PaddingTop = UDim.new(0, 8), PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8)}, side)
U.pages = new("Frame", {Position = UDim2.fromOffset(128, 44), Size = UDim2.fromOffset(MW - 136, MH - 52), BackgroundTransparency = 1}, U.menu)

local pages, tabs = {}, {}
local function selectTab(name)
	for n, p in pairs(pages) do p.Visible = (n == name) end
	st.tab = name
	for n, b in pairs(tabs) do
		local sel = n == name
		tw(b, {BackgroundColor3 = sel and accent() or T.side}, TI(0.2))
		b.TextColor3 = sel and Color3.new(1, 1, 1) or T.sub
	end
end
local function Page(name)
	local p = new("ScrollingFrame", {
		Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 3,
		CanvasSize = UDim2.new(), AutomaticCanvasSize = E.AutomaticSize.Y, Visible = false,
		ScrollingDirection = E.ScrollingDirection.Y,
	}, U.pages)
	new("UIListLayout", {Padding = UDim.new(0, 8), SortOrder = E.SortOrder.LayoutOrder}, p)
	new("UIPadding", {PaddingRight = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8)}, p)
	pages[name] = p
	local b = new("TextButton", {
		LayoutOrder = ord(), Size = UDim2.new(1, 0, 0, 36), BackgroundColor3 = T.side, Text = name,
		TextColor3 = T.sub, Font = E.Font.GothamMedium, TextSize = 12, AutoButtonColor = false, BorderSizePixel = 0,
	}, side)
	corner(b, 10)
	tabs[name] = b
	b.Activated:Connect(function() selectTab(name) end)
	return p
end

-- компоненты
local function Header(page, text)
	lbl(page, {LayoutOrder = ord(), Size = UDim2.new(1, 0, 0, 20), Text = text, TextSize = 11, TextColor3 = T.sub, TextXAlignment = LEFT})
end
local function Toggle(page, label, key, cb, sub)
	local h = sub and 50 or 42
	local row = new("Frame", {LayoutOrder = ord(), Size = UDim2.new(1, 0, 0, h), BackgroundColor3 = T.row, BorderSizePixel = 0}, page)
	corner(row, 10)
	lbl(row, {Position = UDim2.fromOffset(12, sub and 6 or 0), Size = UDim2.new(1, -78, 0, sub and 20 or h), Text = label, TextSize = 13, Font = E.Font.GothamMedium, TextXAlignment = LEFT})
	if sub then
		lbl(row, {Position = UDim2.fromOffset(12, 26), Size = UDim2.new(1, -78, 0, 16), Text = sub, TextSize = 10, TextColor3 = T.sub, Font = E.Font.Gotham, TextXAlignment = LEFT})
	end
	local sw = new("Frame", {AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.5, 0), Size = UDim2.fromOffset(44, 24), BackgroundColor3 = T.off}, row)
	corner(sw, 12)
	local knob = new("Frame", {Size = UDim2.fromOffset(18, 18), Position = UDim2.fromOffset(3, 3), BackgroundColor3 = Color3.new(1, 1, 1)}, sw)
	corner(knob, 9)
	local btn = new("TextButton", {Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = ""}, row)
	local obj = {}
	local function paint(anim)
		local on = CFG[key]
		local info = anim and TI(0.28, BACK) or TweenInfo.new(0)
		tw(knob, {Position = on and UDim2.fromOffset(23, 3) or UDim2.fromOffset(3, 3)}, info)
		tw(sw, {BackgroundColor3 = on and accent() or T.off}, info)
	end
	function obj.Set(v, silent)
		CFG[key] = v
		paint(true)
		if not silent then safe(cb, v) end
		save()
	end
	btn.Activated:Connect(function() obj.Set(not CFG[key]) end)
	onAccent(function() paint(false) end)
	U.tg[key] = obj
	if CFG[key] then task.defer(safe, cb, true) end
	return obj
end
local function Choice(page, label, opts, key, cb)
	local row = new("Frame", {LayoutOrder = ord(), Size = UDim2.new(1, 0, 0, 62), BackgroundColor3 = T.row, BorderSizePixel = 0}, page)
	corner(row, 10)
	lbl(row, {Position = UDim2.fromOffset(12, 6), Size = UDim2.new(1, -24, 0, 18), Text = label, TextSize = 13, Font = E.Font.GothamMedium, TextXAlignment = LEFT})
	local holder = new("Frame", {Position = UDim2.fromOffset(8, 30), Size = UDim2.new(1, -16, 0, 26), BackgroundTransparency = 1}, row)
	new("UIListLayout", {FillDirection = E.FillDirection.Horizontal, Padding = UDim.new(0, 4), SortOrder = E.SortOrder.LayoutOrder}, holder)
	local btns = {}
	local function paint()
		for i, b in ipairs(btns) do
			local sel = CFG[key] == opts[i][2]
			tw(b, {BackgroundColor3 = sel and accent() or T.btn}, TI(0.2))
			b.TextColor3 = sel and Color3.new(1, 1, 1) or T.sub
		end
	end
	for i, o in ipairs(opts) do
		local b = new("TextButton", {
			LayoutOrder = i, Size = UDim2.new(1 / #opts, -4, 1, 0), BackgroundColor3 = T.btn, Text = o[1],
			TextSize = 11, Font = E.Font.GothamMedium, AutoButtonColor = false, BorderSizePixel = 0,
		}, holder)
		corner(b, 8)
		btns[i] = b
		b.Activated:Connect(function()
			CFG[key] = o[2]
			paint()
			save()
			safe(cb, o[2])
		end)
	end
	onAccent(paint)
	if CFG[key] ~= opts[1][2] then task.defer(safe, cb, CFG[key]) end
end
local function Button(page, text, cb)
	local b = new("TextButton", {
		LayoutOrder = ord(), Size = UDim2.new(1, 0, 0, 40), BackgroundColor3 = T.row, Text = text,
		TextColor3 = accent(), Font = E.Font.GothamBold, TextSize = 13, AutoButtonColor = false, BorderSizePixel = 0,
	}, page)
	corner(b, 10)
	onAccent(function() b.TextColor3 = accent() end)
	b.Activated:Connect(function()
		tw(b, {BackgroundColor3 = T.btn}, TI(0.08))
		task.delay(0.1, function() tw(b, {BackgroundColor3 = T.row}, TI(0.25)) end)
		safe(cb)
	end)
	return b
end
local function Graph(page, title, maxV, colorFn)
	local N = 40
	local row = new("Frame", {LayoutOrder = ord(), Size = UDim2.new(1, 0, 0, 96), BackgroundColor3 = T.row, BorderSizePixel = 0}, page)
	corner(row, 10)
	lbl(row, {Position = UDim2.fromOffset(12, 5), Size = UDim2.fromOffset(100, 18), Text = title, TextSize = 12, TextXAlignment = LEFT})
	local info = lbl(row, {Position = UDim2.fromOffset(90, 5), Size = UDim2.new(1, -102, 0, 18), Text = "", TextSize = 10, TextColor3 = T.sub, Font = E.Font.GothamMedium, TextXAlignment = E.TextXAlignment.Right})
	local area = new("Frame", {Position = UDim2.fromOffset(10, 26), Size = UDim2.new(1, -20, 0, 62), BackgroundTransparency = 1, ClipsDescendants = true}, row)
	local bars, data = {}, {}
	for i = 1, N do
		local b = new("Frame", {AnchorPoint = Vector2.new(0, 1), Position = UDim2.new((i - 1) / N, 0, 1, 0), Size = UDim2.new(1 / N, -1, 0, 2), BorderSizePixel = 0, Visible = false}, area)
		corner(b, 2)
		bars[i] = b
	end
	return function(v)
		data[#data + 1] = v
		if #data > N then table.remove(data, 1) end
		local mn, mx, sum = math.huge, 0, 0
		for _, d in ipairs(data) do mn = math.min(mn, d) mx = math.max(mx, d) sum += d end
		for i = 1, N do
			local d = data[#data - (N - i)]
			local b = bars[i]
			if d then
				b.Visible = true
				b.Size = UDim2.new(1 / N, -1, math.clamp(d / maxV, 0.03, 1), 0)
				b.BackgroundColor3 = colorFn(d)
			else
				b.Visible = false
			end
		end
		info.Text = ("мин %d  •  сред %d  •  макс %d"):format(mn, sum / #data, mx)
	end
end

-- страница: ОПТИМИЗАЦИЯ
local P1 = Page("Оптимизация")
Header(P1, "ГРАФИКА И НАГРУЗКА")
Toggle(P1, "Режим экономии", "saver", function(v)
	for _, k in ipairs({"noShadows", "noFx", "noPost"}) do
		if U.tg[k] then U.tg[k].Set(v) end
	end
	Opt.setQuality(v and 1 or CFG.quality)
end, "Всё сразу: тени, эффекты, пост-обработка, качество 1")
Toggle(P1, "Отключить тени", "noShadows", function(v) Opt.setShadows(v) end)
Toggle(P1, "Отключить частицы и следы", "noFx", function(v) Opt.setFx(v) end, "Частицы, Trail, Beam, огонь, дым")
Toggle(P1, "Отключить пост-эффекты", "noPost", function(v) Opt.setPost(v) end, "Bloom, Blur, SunRays, DoF, цветокоррекция")
Choice(P1, "Уровень графики Roblox", {{"Авто", 0}, {"1", 1}, {"3", 3}, {"5", 5}, {"8", 8}}, "quality", function(v) Opt.setQuality(v) end)
Choice(P1, "Лимит FPS", {{"Станд.", 0}, {"30", 30}, {"60", 60}, {"120", 120}, {"∞", 1000}}, "fpsCap", function(v) Opt.setCap(v) end)
Header(P1, "ПАМЯТЬ")
Choice(P1, "Авто-очистка памяти при (МБ)", {{"Выкл", 0}, {"1000", 1000}, {"1500", 1500}, {"2000", 2000}}, "memWarn", function() end)
Button(P1, "Очистить память сейчас", function() task.spawn(Opt.clean) end)

-- страница: СТАТИСТИКА
local P2 = Page("Статистика")
local pushFps = Graph(P2, "FPS", 120, function(v) return v >= 50 and T.green or v >= 30 and T.yellow or T.red end)
local pushPing = Graph(P2, "Пинг, мс", 300, function(v) return v <= 80 and T.green or v <= 160 and T.yellow or T.red end)
U.memRow = lbl(P2, {LayoutOrder = ord(), Size = UDim2.new(1, 0, 0, 22), Text = "", TextSize = 11, TextColor3 = T.sub, Font = E.Font.GothamMedium, TextXAlignment = LEFT})

-- страница: УТИЛИТЫ
local P3 = Page("Утилиты")
Toggle(P3, "Анти-АФК", "antiAfk", setAntiAfk, "Не даёт кикнуть за бездействие")
Toggle(P3, "Режим AFK (без 3D)", "afk3d", function(v)
	pcall(function() S.RunService:Set3dRenderingEnabled(not v) end)
end, "Экономит батарею; экран чёрный, меню работает")
Button(P3, "Перезайти на этот сервер", rejoin)
Button(P3, "Другой сервер", serverHop)
Header(P3, "ТАЙМЕР МАТЧА")
do
	local row = new("Frame", {LayoutOrder = ord(), Size = UDim2.new(1, 0, 0, 56), BackgroundColor3 = T.row, BorderSizePixel = 0}, P3)
	corner(row, 10)
	U.swLbl = lbl(row, {Position = UDim2.fromOffset(12, 0), Size = UDim2.fromOffset(110, 56), Text = "00:00.0", TextSize = 18, TextXAlignment = LEFT})
	local function mini(txt, x, cb)
		local b = new("TextButton", {AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, x, 0.5, 0), Size = UDim2.fromOffset(70, 30), BackgroundColor3 = T.btn, Text = txt, TextColor3 = T.text, Font = E.Font.GothamBold, TextSize = 12, AutoButtonColor = false, BorderSizePixel = 0}, row)
		corner(b, 8)
		b.Activated:Connect(cb)
		return b
	end
	local startBtn
	startBtn = mini("Старт", -88, function()
		local s = st.sw
		if s.run then s.acc += tick() - s.t0 s.run = false startBtn.Text = "Старт"
		else s.t0 = tick() s.run = true startBtn.Text = "Пауза" end
	end)
	mini("Сброс", -10, function()
		st.sw.acc, st.sw.run = 0, false
		startBtn.Text = "Старт"
	end)
end
Header(P3, "ЗАМЕТКИ")
do
	local box = new("TextBox", {
		LayoutOrder = ord(), Size = UDim2.new(1, 0, 0, 110), BackgroundColor3 = T.row, Text = CFG.notes,
		PlaceholderText = "Заметки…", TextColor3 = T.text, PlaceholderColor3 = T.sub, Font = E.Font.Gotham,
		TextSize = 12, TextXAlignment = LEFT, TextYAlignment = E.TextYAlignment.Top, MultiLine = true,
		ClearTextOnFocus = false, TextWrapped = true, BorderSizePixel = 0,
	}, P3)
	corner(box, 10)
	new("UIPadding", {PaddingTop = UDim.new(0, 8), PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10)}, box)
	box.FocusLost:Connect(function() CFG.notes = box.Text save() end)
end

-- страница: ИНТЕРФЕЙС
local P4 = Page("Интерфейс")
do
	local row = new("Frame", {LayoutOrder = ord(), Size = UDim2.new(1, 0, 0, 62), BackgroundColor3 = T.row, BorderSizePixel = 0}, P4)
	corner(row, 10)
	lbl(row, {Position = UDim2.fromOffset(12, 6), Size = UDim2.new(1, -24, 0, 18), Text = "Цвет акцента", TextSize = 13, Font = E.Font.GothamMedium, TextXAlignment = LEFT})
	for i, c in ipairs(ACCENTS) do
		local b = new("TextButton", {Position = UDim2.fromOffset(12 + (i - 1) * 40, 28), Size = UDim2.fromOffset(28, 28), BackgroundColor3 = c, Text = "", AutoButtonColor = false, BorderSizePixel = 0}, row)
		corner(b, 14)
		local sk = new("UIStroke", {Color = Color3.new(1, 1, 1), Thickness = 0}, b)
		b.Activated:Connect(function() CFG.accent = i applyAccent() save() end)
		onAccent(function() tw(sk, {Thickness = CFG.accent == i and 2.5 or 0}, TI(0.2)) end)
	end
end
Choice(P4, "Размер острова", {{"S", 0.85}, {"M", 1}, {"L", 1.2}}, "scale", function(v) U.islScale.Scale = v end)
Button(P4, "Сбросить позицию острова", function()
	local scr = screen()
	CFG.px, CFG.py = 0.5, 0.02
	st.tx, st.ty = scr.X * CFG.px, scr.Y * CFG.py
	save()
end)
Button(P4, "Выгрузить скрипт", function() if ENV.VLU_Unload then ENV.VLU_Unload() end end)

local function fitMenu()
	local s = screen()
	U.mFit.Scale = math.min(1, (s.X - 20) / MW, (s.Y - 20) / MH)
end
local function openMenu()
	if st.menuOpen then return end
	st.menuOpen = true
	fitMenu()
	U.mHold.Visible = true
	U.mScale.Scale, U.menu.GroupTransparency = 0.85, 1
	tw(U.mScale, {Scale = 1}, TI(0.6, BACK))
	tw(U.menu, {GroupTransparency = 0}, TI(0.25))
end
local function closeMenu()
	if not st.menuOpen then return end
	st.menuOpen = false
	tw(U.mScale, {Scale = 0.9}, TI(0.28, QUINT, IN))
	tw(U.menu, {GroupTransparency = 1}, TI(0.25, QUAD, IN))
	task.delay(0.3, function() if not st.menuOpen then U.mHold.Visible = false end end)
end
U.closeBtn.Activated:Connect(closeMenu)
U.openBtn.Activated:Connect(function()
	setExpanded(false)
	task.delay(0.15, openMenu)
end)
onAccent(function() if st.tab then selectTab(st.tab) end end)
selectTab("Оптимизация")

---------------------------------------------------------------- main loop
local function getPing()
	local ok, v = pcall(function() return S.Stats.Network.ServerStatsItem["Data Ping"]:GetValue() end)
	return ok and math.floor(v) or 0
end
local function getMem()
	local ok, v = pcall(function() return S.Stats:GetTotalMemoryUsageMb() end)
	return ok and math.floor(v) or 0
end

local acc2, acc3, lastClean = 0, 0, 0
local function refresh()
	local fps, ping, mem = math.floor(st.fps + 0.5), getPing(), getMem()
	local col = fps >= 50 and T.green or fps >= 30 and T.yellow or T.red
	local sess = fmt(tick() - st.t0)
	U.cFps.Text, U.cFps.TextColor3 = fps .. " FPS", col
	U.cTime.Text = sess
	U.cPing.Text = ping .. " ms"
	U.cPing.TextColor3 = ping <= 80 and T.green or ping <= 160 and T.yellow or T.red
	if st.expanded then
		U.tFps.Text, U.tFps.TextColor3 = tostring(fps), col
		U.tPing.Text = ping .. " ms"
		U.tMem.Text = mem .. " МБ"
		U.tClock.Text = os.date("%H:%M:%S")
		U.tPlay.Text = sess
		U.tPlayers.Text = #S.Players:GetPlayers() .. "/" .. S.Players.MaxPlayers
	end
	if st.menuOpen then U.memRow.Text = "Память: " .. mem .. " МБ  •  Сессия: " .. sess end
	if CFG.memWarn > 0 and mem > CFG.memWarn and tick() - lastClean > 30 then
		lastClean = tick()
		task.spawn(Opt.clean)
	end
	return fps, ping
end

local scr0 = screen()
st.pos.x, st.pos.y = scr0.X * CFG.px, -60
st.tx, st.ty = scr0.X * CFG.px, scr0.Y * CFG.py

track(S.RunService.RenderStepped:Connect(function(raw)
	-- fps
	st.frames += 1
	st.fpsAcc += raw
	acc2 += raw
	acc3 += raw
	if st.fpsAcc >= 0.5 then
		st.fps = st.frames / st.fpsAcc
		st.frames, st.fpsAcc = 0, 0
	end
	-- пружина острова
	local dt = math.min(raw, 1 / 30)
	local tx, ty = clampTarget()
	local p = st.pos
	p.vx += (220 * (tx - p.x) - 24 * p.vx) * dt
	p.vy += (220 * (ty - p.y) - 24 * p.vy) * dt
	p.x += p.vx * dt
	p.y += p.vy * dt
	isl.Position = UDim2.fromOffset(p.x, p.y)
	if st.glow then U.grad.Rotation = (U.grad.Rotation + 220 * dt) % 360 end
	-- секундомер
	if st.menuOpen and st.tab == "Утилиты" then
		local s = st.sw
		local t = s.acc + (s.run and (tick() - s.t0) or 0)
		U.swLbl.Text = ("%02d:%04.1f"):format(math.floor(t / 60), t % 60)
	end
	-- обновление текста
	if acc2 >= 0.5 then
		acc2 = 0
		refresh()
	end
	if acc3 >= 1 then
		acc3 = 0
		if st.menuOpen then
			pushFps(math.floor(st.fps + 0.5))
			pushPing(getPing())
		end
	end
end))

---------------------------------------------------------------- unload / start
local function unload()
	for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
	pcall(function() if afkConn then afkConn:Disconnect() end end)
	Opt.setFx(false) Opt.setPost(false) Opt.setShadows(false) Opt.setQuality(0)
	pcall(function() S.RunService:Set3dRenderingEnabled(true) end)
	pcall(function() gui:Destroy() end)
	ENV.VLU_Unload = nil
end
ENV.VLU_Unload = unload

-- появление острова: падает сверху с пружиной и «раскрывается»
tw(isl, {Size = UDim2.fromOffset(170, 34)}, TI(0.8, BACK))
tw(U.compact, {GroupTransparency = 0}, TI(0.4))
refresh()
notify("VL Utility загружен • нажми на остров")
