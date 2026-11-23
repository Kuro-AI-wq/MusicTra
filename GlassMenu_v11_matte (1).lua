--[[
	Glass Menu v11 (матовый, лёгкий)
	Центр:  окно + нижняя панель вкладок  FPS | Графика | Вид | Остров | Ещё
	Бока:   панельки быстрых функций (плавно "плавают", окно не перекрывают)
	Сверху: остров (FPS, минуты сессии, пинг). Тап по острову открывает/закрывает меню.
	Только производительность и внешний вид. У каждой функции есть откат.
]]

local ICON_IMAGE = "" -- по желанию: "rbxassetid://ТВОЙ_ID" - картинка на круглой кнопке

local env = (getgenv and getgenv()) or _G

-- защита от двойного запуска: прошлый экземпляр выгружается целиком
if env.__MatteMenu and type(env.__MatteMenu.Unload) == "function" then
	pcall(env.__MatteMenu.Unload)
	env.__MatteMenu = nil
end

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UIS = game:GetService("UserInputService")
local Lighting = game:GetService("Lighting")
local StatsService = game:GetService("Stats")
local CoreGui = game:GetService("CoreGui")
local VirtualUser = game:GetService("VirtualUser")
local Workspace = game:GetService("Workspace")
local LP = Players.LocalPlayer or Players.PlayerAdded:Wait()

-- ===== тема: один матовый вариант, непрозрачные плотные цвета =====
local T = {
	bg = Color3.fromRGB(22, 24, 30),
	side = Color3.fromRGB(28, 31, 39),
	card = Color3.fromRGB(37, 41, 51),
	press = Color3.fromRGB(47, 52, 65),
	line = Color3.fromRGB(58, 63, 78),
	text = Color3.fromRGB(242, 245, 250),
	sub = Color3.fromRGB(176, 183, 199),
	accent = Color3.fromRGB(16, 120, 140),
	glow = Color3.fromRGB(54, 200, 222),
	off = Color3.fromRGB(82, 88, 104),
	knob = Color3.fromRGB(248, 249, 252),
	danger = Color3.fromRGB(196, 62, 74),
	good = Color3.fromRGB(72, 214, 120),
	warn = Color3.fromRGB(240, 190, 60),
	bad = Color3.fromRGB(240, 84, 84),
}

-- ===== состояние: всё в одной таблице S, элементы интерфейса в UI =====
local S = {
	alive = true, unloading = false, open = false,
	conns = {}, fconns = {}, active = {}, orig = {}, tok = {},
	log = {}, logDirty = false,
	fps = 60, frames = 0, acc = 0, warm = 0, low = 0,
	boosted = false, boostSet = {},
	limit = "60", prevLimit = "60", limit0 = "60", capChanged = false,
	qKey = "min", ccMode = "bright", scale = 1, page = "FPS",
	crossColor = "mint", crossSize = "m",
	t0 = os.time(),
}
local UI = { pages = {}, tabs = {}, sync = {}, floatTw = {} }
local F = {} -- функции: F[имя] = { on = fn, off = fn }

local SetCap, ApplyLimit, EngageBoost, ReleaseBoost

-- ===== базовые помощники =====
local function Log(msg)
	local L = S.log
	L[#L + 1] = os.date("%H:%M:%S") .. "  " .. tostring(msg)
	if #L > 60 then table.remove(L, 1) end
	S.logDirty = true
end

local function Run(name, fn, ...)
	local ok, err = pcall(fn, ...)
	if not ok then Log("[" .. name .. "] " .. tostring(err)) end
	return ok
end

local function New(class, props, parent)
	local o = Instance.new(class)
	if props then
		for k, v in pairs(props) do o[k] = v end
	end
	if parent then o.Parent = parent end
	return o
end

local function Tween(obj, t, props)
	local tw = TweenService:Create(obj, TweenInfo.new(t, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props)
	tw:Play()
	return tw
end

local function Connect(signal, fn)
	local c = signal:Connect(fn)
	S.conns[#S.conns + 1] = c
	return c
end

local function FConnect(name, signal, fn)
	local list = S.fconns[name]
	if not list then
		list = {}
		S.fconns[name] = list
	end
	local c = signal:Connect(fn)
	list[#list + 1] = c
	return c
end

local function FDisconnect(name)
	local list = S.fconns[name]
	if list then
		for i = 1, #list do
			pcall(function() list[i]:Disconnect() end)
		end
		S.fconns[name] = nil
	end
end

-- включение / выключение функции с откатом при ошибке
local function SetFeature(name, state)
	local f = F[name]
	if not f then
		Log("нет функции: " .. tostring(name))
		return false
	end
	state = state and true or false
	if (S.active[name] or false) == state then return true end
	local ok, err = pcall(state and f.on or f.off)
	if not ok then
		Log("[" .. name .. "] " .. tostring(err))
		if state then pcall(f.off) end
		S.active[name] = false
		return false
	end
	S.active[name] = state
	local sync = UI.sync[name]
	if sync then pcall(sync, state) end
	return true
end

-- пакетный обход Workspace: чанками, чтобы интерфейс не подвисал
local function Batch(name, tok, fn)
	task.spawn(function()
		local ok, err = pcall(function()
			local list = Workspace:GetDescendants()
			for i = 1, #list do
				if S.tok[name] ~= tok or not S.alive then return end
				fn(list[i])
				if i % 250 == 0 then task.wait() end
			end
		end)
		if not ok then Log("[" .. name .. "] " .. tostring(err)) end
	end)
end

local function GuiParent()
	local ok, h = pcall(function() return gethui and gethui() end)
	if ok and h then return h end
	local okc = pcall(function() return CoreGui.Name end)
	if okc then return CoreGui end
	return LP:WaitForChild("PlayerGui", 10)
end

-- ================= ФУНКЦИИ (каждая с откатом) =================

do -- ==== ЛИМИТ FPS / ТУРБО ====
	Run("fps", function()
		local okc, c = pcall(function() return getfpscap and getfpscap() end)
		if okc and type(c) == "number" and c > 0 and c < 1000 then S.orig.cap = c else S.orig.cap = 60 end
		local CAPS = { ["30"] = 30, ["60"] = 60, ["120"] = 120, max = 999 }
		local k = tostring(S.orig.cap)
		if not CAPS[k] then k = (S.orig.cap > 120) and "max" or "60" end
		S.limit = k
		S.limit0 = k
		S.prevLimit = (k == "max") and "60" or k

		SetCap = function(v)
			if not setfpscap then error("setfpscap не поддерживается этим экзекутором") end
			setfpscap(v)
		end
		ApplyLimit = function(key)
			local v = CAPS[key]
			if not v then return end
			if not Run("fps", SetCap, v) then return end
			S.capChanged = true
			S.limit = key
			if key ~= "max" then S.prevLimit = key end
			if UI.setLimit then UI.setLimit(key) end
			if UI.setTurbo then UI.setTurbo(key == "max") end
		end
	end)
end

do -- ==== КАЧЕСТВО ГРАФИКИ ====
	Run("quality", function()
		local LEVELS = {
			min = Enum.QualityLevel.Level01,
			low = Enum.QualityLevel.Level03,
			mid = Enum.QualityLevel.Level05,
		}
		F.quality = {
			apply = function()
				local lv = LEVELS[S.qKey]
				if lv then settings().Rendering.QualityLevel = lv end
			end,
			on = function()
				if S.orig.quality == nil then S.orig.quality = settings().Rendering.QualityLevel end
				F.quality.apply()
			end,
			off = function()
				if S.orig.quality ~= nil then settings().Rendering.QualityLevel = S.orig.quality end
				S.orig.quality = nil
			end,
		}
	end)
end

do -- ==== БЕЗ ТЕНЕЙ ====
	Run("shadows", function()
		F.shadows = {
			on = function()
				S.orig.shadows = Lighting.GlobalShadows
				Lighting.GlobalShadows = false
			end,
			off = function()
				if S.orig.shadows ~= nil then Lighting.GlobalShadows = S.orig.shadows end
				S.orig.shadows = nil
			end,
		}
	end)
end

do -- ==== БЕЗ РАЗМЫТИЯ (blur / DoF / bloom / sunrays) ====
	Run("postfx", function()
		local POSTFX = { BlurEffect = true, DepthOfFieldEffect = true, BloomEffect = true, SunRaysEffect = true }
		F.postfx = {
			on = function()
				local store = {}
				S.orig.postfx = store
				local function kill(o)
					if POSTFX[o.ClassName] and store[o] == nil then
						store[o] = o.Enabled
						o.Enabled = false
					end
				end
				for _, o in ipairs(Lighting:GetChildren()) do kill(o) end
				FConnect("postfx", Lighting.ChildAdded, kill)
			end,
			off = function()
				FDisconnect("postfx")
				local store = S.orig.postfx
				if store then
					for o, v in pairs(store) do
						if o.Parent then o.Enabled = v end
					end
				end
				S.orig.postfx = nil
			end,
		}
	end)
end

do -- ==== БЕЗ ЭФФЕКТОВ (частицы, шлейфы, огонь) ====
	Run("particles", function()
		local FX = { ParticleEmitter = true, Trail = true, Beam = true, Fire = true, Smoke = true, Sparkles = true }
		F.particles = {
			on = function()
				local store = setmetatable({}, { __mode = "k" })
				S.orig.particles = store
				local tok = {}
				S.tok.particles = tok
				local function kill(o)
					if FX[o.ClassName] and store[o] == nil then
						store[o] = o.Enabled
						o.Enabled = false
					end
				end
				FConnect("particles", Workspace.DescendantAdded, kill)
				Batch("particles", tok, kill)
			end,
			off = function()
				S.tok.particles = nil
				FDisconnect("particles")
				local store = S.orig.particles
				if store then
					for o, v in pairs(store) do
						if o.Parent then o.Enabled = v end
					end
				end
				S.orig.particles = nil
			end,
		}
	end)
end

do -- ==== ПРОСТЫЕ МАТЕРИАЛЫ ====
	Run("materials", function()
		F.materials = {
			on = function()
				local store = setmetatable({}, { __mode = "k" })
				S.orig.materials = store
				local tok = {}
				S.tok.materials = tok
				local function conv(o)
					if o:IsA("BasePart") and not o:IsA("Terrain") and store[o] == nil
						and o.Material ~= Enum.Material.SmoothPlastic then
						local m = o:FindFirstAncestorOfClass("Model")
						if m and Players:GetPlayerFromCharacter(m) then return end
						store[o] = o.Material
						o.Material = Enum.Material.SmoothPlastic
					end
				end
				FConnect("materials", Workspace.DescendantAdded, conv)
				Batch("materials", tok, conv)
			end,
			off = function()
				S.tok.materials = nil
				FDisconnect("materials")
				local store = S.orig.materials
				if store then
					for o, v in pairs(store) do
						if o.Parent then o.Material = v end
					end
				end
				S.orig.materials = nil
			end,
		}
	end)
end

do -- ==== БЕЗ АТМОСФЕРЫ (дымка, облака) ====
	Run("atmo", function()
		F.atmo = {
			on = function()
				local st = {}
				S.orig.atmo = st
				for _, o in ipairs(Lighting:GetChildren()) do
					if o:IsA("Atmosphere") then
						st[o] = { o.Density, o.Haze, o.Glare }
						o.Density = 0
						o.Haze = 0
						o.Glare = 0
					end
				end
				local terrain = Workspace:FindFirstChildOfClass("Terrain")
				local clouds = terrain and terrain:FindFirstChildOfClass("Clouds")
				if clouds then
					st[clouds] = clouds.Enabled
					clouds.Enabled = false
				end
			end,
			off = function()
				local st = S.orig.atmo
				if st then
					for o, v in pairs(st) do
						if o.Parent then
							if type(v) == "table" then
								o.Density = v[1]
								o.Haze = v[2]
								o.Glare = v[3]
							else
								o.Enabled = v
							end
						end
					end
				end
				S.orig.atmo = nil
			end,
		}
	end)
end

do -- ==== ЦВЕТ И ЯРКОСТЬ (своя ColorCorrection) ====
	Run("cc", function()
		local CC = {
			bright = { Brightness = 0.07, Contrast = 0.06, Saturation = 0.05 },
			contrast = { Brightness = 0, Contrast = 0.22, Saturation = 0.18 },
		}
		F.cc = {
			apply = function()
				local fx, p = S.ccFx, CC[S.ccMode]
				if fx and p then
					for k, v in pairs(p) do fx[k] = v end
				end
			end,
			on = function()
				local fx = Instance.new("ColorCorrectionEffect")
				fx.Name = "MatteCC"
				S.ccFx = fx
				F.cc.apply()
				fx.Parent = Lighting
			end,
			off = function()
				if S.ccFx then S.ccFx:Destroy() end
				S.ccFx = nil
			end,
		}
	end)
end

do -- ==== ПРИЦЕЛ (статичная точка-кольцо в центре, только внешний вид) ====
	Run("cross", function()
		local COL = {
			white = Color3.fromRGB(255, 255, 255), mint = Color3.fromRGB(80, 230, 170),
			red = Color3.fromRGB(255, 90, 90), yellow = Color3.fromRGB(255, 214, 70),
		}
		local SZ = { s = 16, m = 22, l = 30 }
		F.cross = {
			apply = function()
				local c = S.cross
				if not c then return end
				local n = SZ[S.crossSize] or 22
				c.ring.Size = UDim2.fromOffset(n, n)
				c.stroke.Color = COL[S.crossColor] or COL.mint
				c.dot.BackgroundColor3 = COL[S.crossColor] or COL.mint
			end,
			on = function()
				local ring = New("Frame", {
					Name = "Cross", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
					Size = UDim2.fromOffset(22, 22), BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 1,
				})
				New("UICorner", { CornerRadius = UDim.new(1, 0) }, ring)
				local stroke = New("UIStroke", { Thickness = 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, ring)
				local dot = New("Frame", {
					AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
					Size = UDim2.fromOffset(4, 4), BorderSizePixel = 0,
				}, ring)
				New("UICorner", { CornerRadius = UDim.new(1, 0) }, dot)
				S.cross = { ring = ring, stroke = stroke, dot = dot }
				F.cross.apply()
				ring.Parent = UI.gui
			end,
			off = function()
				if S.cross then S.cross.ring:Destroy() end
				S.cross = nil
			end,
		}
	end)
end

do -- ==== АНТИ-АФК ====
	Run("afk", function()
		F.afk = {
			on = function()
				FConnect("afk", LP.Idled, function()
					pcall(function()
						VirtualUser:CaptureController()
						VirtualUser:ClickButton2(Vector2.new(0, 0))
					end)
				end)
			end,
			off = function() FDisconnect("afk") end,
		}
	end)
end

do -- ==== ОСТРОВ (показать / скрыть) ====
	Run("island", function()
		F.island = {
			on = function() if UI.island then UI.island.Visible = true end end,
			off = function() if UI.island then UI.island.Visible = false end end,
		}
	end)
end

do -- ==== АВТО-БУСТ: при FPS < 28 сам включает лёгкую графику ====
	Run("autoboost", function()
		EngageBoost = function()
			if S.boosted then return end
			S.boosted = true
			S.boostSet = {}
			for _, n in ipairs({ "shadows", "postfx", "particles", "quality" }) do
				if not S.active[n] then
					if n == "quality" then S.qKey = "min" end
					if SetFeature(n, true) then S.boostSet[#S.boostSet + 1] = n end
				end
			end
		end
		ReleaseBoost = function()
			if not S.boosted then return end
			S.boosted = false
			for _, n in ipairs(S.boostSet) do SetFeature(n, false) end
			S.boostSet = {}
		end
		F.autoboost = {
			on = function()
				S.low = 0
				S.warm = 0
			end,
			off = function()
				if ReleaseBoost then ReleaseBoost() end
			end,
		}
	end)
end

-- ================= ВИДЖЕТЫ ИНТЕРФЕЙСА =================

local function Corner(obj, r)
	return New("UICorner", { CornerRadius = UDim.new(0, r) }, obj)
end

local function Stroke(obj, color, th)
	return New("UIStroke", { Color = color, Thickness = th, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, obj)
end

local function Label(parent, props)
	props.BackgroundTransparency = 1
	props.BorderSizePixel = 0
	props.TextColor3 = props.TextColor3 or T.text
	props.Font = props.Font or Enum.Font.GothamMedium
	props.TextXAlignment = props.TextXAlignment or Enum.TextXAlignment.Left
	return New("TextLabel", props, parent)
end

local function MakeRow(parent, order, h, clickable)
	local row = New(clickable and "TextButton" or "Frame", {
		Size = UDim2.new(1, 0, 0, h), BackgroundColor3 = T.card, BorderSizePixel = 0, LayoutOrder = order,
	})
	Corner(row, 10)
	if clickable then
		row.AutoButtonColor = false
		row.Text = ""
		Connect(row.MouseButton1Down, function() Tween(row, 0.08, { BackgroundColor3 = T.press }) end)
		local function rel() Tween(row, 0.12, { BackgroundColor3 = T.card }) end
		Connect(row.MouseButton1Up, rel)
		Connect(row.MouseLeave, rel)
	end
	row.Parent = parent
	return row
end

-- строка-переключатель; возвращает set(on, instant)
local function Toggle(parent, order, title, desc, onTap)
	local row = MakeRow(parent, order, 64, true)
	Label(row, {
		Text = title, Font = Enum.Font.GothamBold, TextSize = 15,
		Position = UDim2.fromOffset(14, 7), Size = UDim2.new(1, -80, 0, 20),
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	Label(row, {
		Text = desc, TextSize = 13, TextColor3 = T.sub,
		Position = UDim2.fromOffset(14, 28), Size = UDim2.new(1, -80, 0, 32),
		TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, TextTruncate = Enum.TextTruncate.AtEnd,
	})
	local track = New("Frame", {
		AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -14, 0.5, 0),
		Size = UDim2.fromOffset(46, 26), BackgroundColor3 = T.off, BorderSizePixel = 0,
	}, row)
	Corner(track, 99)
	local knob = New("Frame", {
		AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 3, 0.5, 0),
		Size = UDim2.fromOffset(20, 20), BackgroundColor3 = T.knob, BorderSizePixel = 0,
	}, track)
	Corner(knob, 99)
	local function set(on, instant)
		local p = on and UDim2.new(0, 23, 0.5, 0) or UDim2.new(0, 3, 0.5, 0)
		local c = on and T.accent or T.off
		if instant then
			knob.Position = p
			track.BackgroundColor3 = c
		else
			Tween(knob, 0.14, { Position = p })
			Tween(track, 0.14, { BackgroundColor3 = c })
		end
	end
	Connect(row.Activated, onTap)
	return set
end

-- боковая панелька функции (название + статус + светящаяся рамка при включении)
local function SideCard(parent, order, title, onTap)
	local card = New("TextButton", {
		Name = title, LayoutOrder = order, Size = UDim2.new(1, 0, 0, 62), BackgroundColor3 = T.card,
		BorderSizePixel = 0, AutoButtonColor = false, Text = "",
	})
	Corner(card, 12)
	local st = Stroke(card, T.line, 1.5)
	Label(card, {
		Text = title, Font = Enum.Font.GothamBold, TextSize = 14,
		Position = UDim2.fromOffset(12, 10), Size = UDim2.new(1, -34, 0, 20),
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	local stat = Label(card, {
		Text = "Выключено", TextSize = 13, TextColor3 = T.sub,
		Position = UDim2.fromOffset(12, 33), Size = UDim2.new(1, -20, 0, 18),
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	local dot = New("Frame", {
		AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 14),
		Size = UDim2.fromOffset(10, 10), BackgroundColor3 = T.off, BorderSizePixel = 0,
	}, card)
	Corner(dot, 99)
	Connect(card.MouseButton1Down, function() Tween(card, 0.08, { BackgroundColor3 = T.press }) end)
	local function rel() Tween(card, 0.12, { BackgroundColor3 = T.card }) end
	Connect(card.MouseButton1Up, rel)
	Connect(card.MouseLeave, rel)
	local function set(on, instant)
		stat.Text = on and "Включено" or "Выключено"
		stat.TextColor3 = on and T.glow or T.sub
		local dc = on and T.glow or T.off
		local sc = on and T.glow or T.line
		if instant then
			dot.BackgroundColor3 = dc
			st.Color = sc
		else
			Tween(dot, 0.14, { BackgroundColor3 = dc })
			Tween(st, 0.14, { Color = sc })
		end
	end
	Connect(card.Activated, onTap)
	card.Parent = parent
	return set
end

-- сегментный выбор (30 / 60 / 120 / MAX); возвращает set(key, instant)
local function Segment(parent, order, title, desc, options, key0, onPick)
	local row = MakeRow(parent, order, 96, false)
	Label(row, {
		Text = title, Font = Enum.Font.GothamBold, TextSize = 15,
		Position = UDim2.fromOffset(14, 7), Size = UDim2.new(1, -28, 0, 20),
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	Label(row, {
		Text = desc, TextSize = 13, TextColor3 = T.sub,
		Position = UDim2.fromOffset(14, 27), Size = UDim2.new(1, -28, 0, 18),
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	local bar = New("Frame", {
		Position = UDim2.new(0, 14, 0, 52), Size = UDim2.new(1, -28, 0, 34),
		BackgroundColor3 = T.bg, BorderSizePixel = 0,
	}, row)
	Corner(bar, 9)
	New("UIPadding", {
		PaddingTop = UDim.new(0, 3), PaddingBottom = UDim.new(0, 3),
		PaddingLeft = UDim.new(0, 3), PaddingRight = UDim.new(0, 3),
	}, bar)
	New("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, SortOrder = Enum.SortOrder.LayoutOrder }, bar)
	local btns = {}
	local n = #options
	for i = 1, n do
		local o = options[i]
		local b = New("TextButton", {
			Name = o.key, LayoutOrder = i, Size = UDim2.new(1 / n, 0, 1, 0),
			BackgroundColor3 = T.accent, BackgroundTransparency = 1, BorderSizePixel = 0,
			AutoButtonColor = false, Text = o.text, TextSize = 14, Font = Enum.Font.GothamBold, TextColor3 = T.sub,
		}, bar)
		Corner(b, 7)
		btns[o.key] = b
		Connect(b.Activated, function() onPick(o.key) end)
	end
	local function set(key, instant)
		for k, b in pairs(btns) do
			local sel = (k == key)
			local tr = sel and 0 or 1
			local col = sel and T.text or T.sub
			if instant then
				b.BackgroundTransparency = tr
				b.TextColor3 = col
			else
				Tween(b, 0.12, { BackgroundTransparency = tr, TextColor3 = col })
			end
		end
	end
	set(key0, true)
	return set
end

local function Button(parent, order, text, color, fn)
	local b = New("TextButton", {
		LayoutOrder = order, Size = UDim2.new(1, 0, 0, 44), BackgroundColor3 = color, BorderSizePixel = 0,
		AutoButtonColor = true, Text = text, TextSize = 15, Font = Enum.Font.GothamBold, TextColor3 = T.text,
	})
	Corner(b, 10)
	Connect(b.Activated, fn)
	b.Parent = parent
	return b
end

-- ================= СБРОС И ВЫГРУЗКА =================

local function ResetAll()
	for name in pairs(F) do SetFeature(name, false) end
	if ApplyLimit and S.capChanged then ApplyLimit(S.limit0) end
	SetFeature("island", true)
	Log("все функции отключены, значения возвращены")
end

local function Unload()
	if S.unloading then return end
	S.unloading = true
	S.alive = false
	UI.sync = {}
	for name in pairs(F) do SetFeature(name, false) end
	if S.capChanged and S.orig.cap and SetCap then pcall(SetCap, S.orig.cap) end
	for name in pairs(S.fconns) do FDisconnect(name) end
	for i = 1, #S.conns do
		pcall(function() S.conns[i]:Disconnect() end)
	end
	S.conns = {}
	for _, tw in ipairs(UI.floatTw) do pcall(function() tw:Cancel() end) end
	if UI.gui then pcall(function() UI.gui:Destroy() end) end
	if env.__MatteMenu and env.__MatteMenu.State == S then env.__MatteMenu = nil end
end

-- ================= ИНТЕРФЕЙС =================

do -- ==== ОКНО, ПАНЕЛЬКИ, ВКЛАДКИ, ОСТРОВ, КРУГЛАЯ КНОПКА ====
	Run("ui", function()
		local parent = GuiParent()
		local old = parent:FindFirstChild("MatteMenu")
		if old then old:Destroy() end

		local gui = New("ScreenGui", {
			Name = "MatteMenu", ResetOnSpawn = false, IgnoreGuiInset = true,
			DisplayOrder = 999, ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		})
		UI.gui = gui

		-- корневой контейнер: [левые панельки] [окно] [правые панельки] - без перекрытий
		local root = New("Frame", {
			Name = "Root", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.88, 0.8), BackgroundTransparency = 1, BorderSizePixel = 0,
			ZIndex = 5, Visible = false,
		}, gui)
		UI.root = root
		UI.sizeC = New("UISizeConstraint", { MinSize = Vector2.new(560, 250), MaxSize = Vector2.new(780, 360) }, root)
		UI.uiscale = New("UIScale", { Scale = 1 }, root)
		New("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 10),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}, root)

		local function MakeSide(order)
			local wrap = New("Frame", {
				Name = "Side" .. order, LayoutOrder = order, Size = UDim2.new(0.215, 0, 1, 0),
				BackgroundTransparency = 1, BorderSizePixel = 0,
			}, root)
			local fl = New("Frame", {
				Name = "Float", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, BorderSizePixel = 0,
			}, wrap)
			New("UIListLayout", {
				Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder,
				VerticalAlignment = Enum.VerticalAlignment.Center,
			}, fl)
			return fl
		end
		UI.floatL = MakeSide(1)
		UI.floatR = MakeSide(3)

		-- окно
		local win = New("Frame", {
			Name = "Window", LayoutOrder = 2, Size = UDim2.new(0.53, 0, 1, 0),
			BackgroundColor3 = T.bg, BorderSizePixel = 0, ClipsDescendants = true,
		}, root)
		UI.win = win
		Corner(win, 14)
		Stroke(win, T.line, 1)

		local head = New("Frame", { Name = "Head", Size = UDim2.new(1, 0, 0, 40), BackgroundTransparency = 1, BorderSizePixel = 0 }, win)
		Label(head, {
			Text = "Glass Menu", Font = Enum.Font.GothamBold, TextSize = 17,
			Position = UDim2.fromOffset(14, 0), Size = UDim2.new(0, 120, 1, 0),
		})
		UI.status = Label(head, {
			Text = "FPS --  |  Пинг -- мс", TextSize = 13, TextColor3 = T.sub,
			TextXAlignment = Enum.TextXAlignment.Right,
			Position = UDim2.new(0, 134, 0, 0), Size = UDim2.new(1, -148, 1, 0),
			TextTruncate = Enum.TextTruncate.AtEnd,
		})
		New("Frame", {
			Position = UDim2.new(0, 0, 1, -1), Size = UDim2.new(1, 0, 0, 1),
			BackgroundColor3 = T.line, BorderSizePixel = 0,
		}, head)

		local pagesHost = New("Frame", {
			Name = "Pages", Position = UDim2.fromOffset(0, 40), Size = UDim2.new(1, 0, 1, -86),
			BackgroundTransparency = 1, BorderSizePixel = 0, ClipsDescendants = true,
		}, win)

		-- нижняя панель вкладок
		local bar = New("Frame", {
			Name = "Tabs", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, 0),
			Size = UDim2.new(1, 0, 0, 46), BackgroundColor3 = T.side, BorderSizePixel = 0,
		}, win)
		New("UIPadding", {
			PaddingTop = UDim.new(0, 5), PaddingBottom = UDim.new(0, 5),
			PaddingLeft = UDim.new(0, 5), PaddingRight = UDim.new(0, 5),
		}, bar)
		New("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, SortOrder = Enum.SortOrder.LayoutOrder }, bar)

		local function SelectPage(id, instant)
			for k, p in pairs(UI.pages) do p.Visible = (k == id) end
			for k, b in pairs(UI.tabs) do
				local sel = (k == id)
				local tr = sel and 0 or 1
				local col = sel and T.text or T.sub
				if instant then
					b.BackgroundTransparency = tr
					b.TextColor3 = col
				else
					Tween(b, 0.12, { BackgroundTransparency = tr, TextColor3 = col })
				end
			end
			S.page = id
		end

		local TABS = { { "FPS", "FPS" }, { "GFX", "Графика" }, { "VIEW", "Вид" }, { "ISL", "Остров" }, { "MORE", "Ещё" } }
		for i = 1, #TABS do
			local id, name = TABS[i][1], TABS[i][2]
			local b = New("TextButton", {
				Name = id, LayoutOrder = i, Size = UDim2.new(1 / #TABS, 0, 1, 0),
				BackgroundColor3 = T.accent, BackgroundTransparency = 1, BorderSizePixel = 0,
				AutoButtonColor = false, Text = name, TextSize = 14, Font = Enum.Font.GothamBold, TextColor3 = T.sub,
			}, bar)
			Corner(b, 9)
			UI.tabs[id] = b
			Connect(b.Activated, function() SelectPage(id) end)

			local p = New("ScrollingFrame", {
				Name = id, Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, BorderSizePixel = 0,
				ScrollBarThickness = 3, ScrollBarImageColor3 = T.line, CanvasSize = UDim2.new(),
				AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollingDirection = Enum.ScrollingDirection.Y,
				Visible = false,
			}, pagesHost)
			New("UIPadding", {
				PaddingTop = UDim.new(0, 10), PaddingBottom = UDim.new(0, 10),
				PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 12),
			}, p)
			New("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, p)
			UI.pages[id] = p
		end
		local P = UI.pages

		-- ---- масштаб меню / острова ----
		local function ApplyScale(sc)
			S.scale = sc
			UI.uiscale.Scale = sc
			UI.root.Size = UDim2.fromScale(0.88 / sc, 0.8 / sc)
			UI.sizeC.MinSize = Vector2.new(560 / sc, 250 / sc)
			UI.sizeC.MaxSize = Vector2.new(780 / sc, 360 / sc)
		end

		-- ---- плавное "парение" боковых панелек (1 твин на сторону, только пока меню открыто) ----
		local function StopFloat()
			for _, tw in ipairs(UI.floatTw) do tw:Cancel() end
			UI.floatTw = {}
		end
		local function StartFloat()
			StopFloat()
			local sides = { UI.floatL, UI.floatR }
			for i = 1, 2 do
				local from = (i == 1) and -4 or 4
				sides[i].Position = UDim2.fromOffset(0, from)
				local tw = TweenService:Create(
					sides[i],
					TweenInfo.new(3.4, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
					{ Position = UDim2.fromOffset(0, -from) }
				)
				tw:Play()
				UI.floatTw[#UI.floatTw + 1] = tw
			end
		end

		local function SetOpen(open)
			S.open = open and true or false
			if S.open then
				UI.root.Position = UDim2.new(0.5, 0, 0.5, 14)
				UI.root.Visible = true
				Tween(UI.root, 0.18, { Position = UDim2.fromScale(0.5, 0.5) })
				StartFloat()
			else
				StopFloat()
				UI.root.Visible = false
			end
		end
		UI.SetOpen = SetOpen

		-- ================= ВКЛАДКА FPS =================
		UI.setLimit = Segment(P.FPS, 1, "Лимит FPS", "Максимум кадров в секунду", {
			{ key = "30", text = "30" }, { key = "60", text = "60" },
			{ key = "120", text = "120" }, { key = "max", text = "MAX" },
		}, S.limit, function(k)
			if ApplyLimit then ApplyLimit(k) end
		end)
		UI.sync.particles = Toggle(P.FPS, 2, "Без эффектов", "Частицы, шлейфы и огонь на карте", function()
			SetFeature("particles", not S.active.particles)
		end)
		UI.sync.materials = Toggle(P.FPS, 3, "Простые материалы", "Гладкие поверхности вместо текстур", function()
			SetFeature("materials", not S.active.materials)
		end)
		local note = New("Frame", { LayoutOrder = 4, Size = UDim2.new(1, 0, 0, 50), BackgroundTransparency = 1, BorderSizePixel = 0 }, P.FPS)
		Label(note, {
			Text = "Турбо снимает лимит FPS. Авто-буст облегчает графику при FPS ниже 28 и возвращает всё при выключении.",
			TextSize = 13, TextColor3 = T.sub, Size = UDim2.fromScale(1, 1),
			TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top,
		})

		-- ================= ВКЛАДКА ГРАФИКА =================
		local setQ
		setQ = Segment(P.GFX, 1, "Качество графики", "Системный уровень рендера", {
			{ key = "auto", text = "Авто" }, { key = "min", text = "Мин" },
			{ key = "low", text = "Низк" }, { key = "mid", text = "Сред" },
		}, "auto", function(k)
			if k == "auto" then
				SetFeature("quality", false)
			else
				S.qKey = k
				if S.active.quality then
					Run("quality", F.quality.apply)
					setQ(k)
				else
					SetFeature("quality", true)
				end
			end
		end)
		UI.sync.quality = function(on) setQ(on and S.qKey or "auto") end

		UI.sync.atmo = Toggle(P.GFX, 2, "Без атмосферы", "Убирает дымку и облака", function()
			SetFeature("atmo", not S.active.atmo)
		end)

		local setCC
		setCC = Segment(P.GFX, 3, "Цвет и яркость", "Лёгкая цветокоррекция", {
			{ key = "off", text = "Обычная" }, { key = "bright", text = "Ярче" }, { key = "contrast", text = "Контраст" },
		}, "off", function(k)
			if k == "off" then
				SetFeature("cc", false)
			else
				S.ccMode = k
				if S.active.cc then
					Run("cc", F.cc.apply)
					setCC(k)
				else
					SetFeature("cc", true)
				end
			end
		end)
		UI.sync.cc = function(on) setCC(on and S.ccMode or "off") end

		-- ================= ВКЛАДКА ВИД =================
		local setSc
		setSc = Segment(P.VIEW, 1, "Размер меню", "Если текст мелкий - увеличьте", {
			{ key = "0.9", text = "90%" }, { key = "1", text = "100%" },
			{ key = "1.15", text = "115%" }, { key = "1.3", text = "130%" },
		}, "1", function(k)
			ApplyScale(tonumber(k) or 1)
			setSc(k)
		end)
		local setCol
		setCol = Segment(P.VIEW, 2, "Цвет прицела", "Кольцо с точкой в центре экрана", {
			{ key = "white", text = "Белый" }, { key = "mint", text = "Мята" },
			{ key = "red", text = "Красный" }, { key = "yellow", text = "Жёлтый" },
		}, S.crossColor, function(k)
			S.crossColor = k
			setCol(k)
			if S.cross then Run("cross", F.cross.apply) end
		end)
		local setCS
		setCS = Segment(P.VIEW, 3, "Размер прицела", "Включается панелькой слева", {
			{ key = "s", text = "Мал" }, { key = "m", text = "Сред" }, { key = "l", text = "Бол" },
		}, S.crossSize, function(k)
			S.crossSize = k
			setCS(k)
			if S.cross then Run("cross", F.cross.apply) end
		end)

		-- ================= ВКЛАДКА ОСТРОВ =================
		UI.sync.island = Toggle(P.ISL, 1, "Остров", "Панель FPS, время сессии и пинг сверху", function()
			SetFeature("island", not S.active.island)
		end)
		local setIs
		setIs = Segment(P.ISL, 2, "Размер острова", "Компактный или покрупнее", {
			{ key = "0.85", text = "Мал" }, { key = "1", text = "Норм" }, { key = "1.15", text = "Бол" },
		}, "1", function(k)
			if UI.islScale then UI.islScale.Scale = tonumber(k) or 1 end
			setIs(k)
		end)

		-- ================= ВКЛАДКА ЕЩЁ =================
		local logCard = New("Frame", {
			Name = "LogCard", LayoutOrder = 1, Size = UDim2.new(1, 0, 0, 140),
			BackgroundColor3 = T.card, BorderSizePixel = 0,
		}, P.MORE)
		Corner(logCard, 10)
		Label(logCard, {
			Text = "Журнал", Font = Enum.Font.GothamBold, TextSize = 15,
			Position = UDim2.fromOffset(14, 7), Size = UDim2.new(1, -28, 0, 20),
		})
		local ls = New("ScrollingFrame", {
			Position = UDim2.new(0, 10, 0, 32), Size = UDim2.new(1, -20, 1, -42),
			BackgroundColor3 = T.bg, BorderSizePixel = 0, ScrollBarThickness = 3,
			ScrollBarImageColor3 = T.line, CanvasSize = UDim2.new(),
			AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollingDirection = Enum.ScrollingDirection.Y,
		}, logCard)
		Corner(ls, 8)
		New("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8), PaddingTop = UDim.new(0, 6), PaddingBottom = UDim.new(0, 6) }, ls)
		UI.logLabel = Label(ls, {
			Text = "Ошибок нет", TextSize = 12, TextColor3 = T.sub,
			Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
			TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top,
		})

		Button(P.MORE, 2, "Скопировать журнал", T.accent, function()
			Run("copy", function()
				if not setclipboard then error("setclipboard недоступен") end
				setclipboard(table.concat(S.log, "\n"))
				Log("журнал скопирован")
			end)
		end)
		Button(P.MORE, 3, "Откатить все функции", T.press, ResetAll)
		Button(P.MORE, 4, "Выгрузить меню", T.danger, Unload)

		-- ================= БОКОВЫЕ ПАНЕЛЬКИ =================
		UI.setTurbo = SideCard(UI.floatL, 1, "Турбо", function()
			if ApplyLimit then ApplyLimit(S.limit == "max" and S.prevLimit or "max") end
		end)
		UI.sync.autoboost = SideCard(UI.floatL, 2, "Авто-буст", function()
			SetFeature("autoboost", not S.active.autoboost)
		end)
		UI.sync.cross = SideCard(UI.floatL, 3, "Прицел", function()
			SetFeature("cross", not S.active.cross)
		end)
		UI.sync.postfx = SideCard(UI.floatR, 1, "Без размытия", function()
			SetFeature("postfx", not S.active.postfx)
		end)
		UI.sync.afk = SideCard(UI.floatR, 2, "Анти-АФК", function()
			SetFeature("afk", not S.active.afk)
		end)
		UI.sync.shadows = SideCard(UI.floatR, 3, "Без теней", function()
			SetFeature("shadows", not S.active.shadows)
		end)

		-- ================= ОСТРОВ (сверху по центру) =================
		local isl = New("Frame", {
			Name = "Island", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 6),
			Size = UDim2.fromOffset(270, 30), BackgroundColor3 = Color3.fromRGB(12, 13, 16),
			BorderSizePixel = 0, ZIndex = 8, Visible = false,
		}, gui)
		UI.island = isl
		Corner(isl, 99)
		Stroke(isl, T.line, 1)
		UI.islScale = New("UIScale", { Scale = 1 }, isl)
		UI.dotL = New("Frame", {
			Position = UDim2.fromOffset(14, 11), Size = UDim2.fromOffset(8, 8), BackgroundColor3 = T.good, BorderSizePixel = 0,
		}, isl)
		Corner(UI.dotL, 99)
		UI.islFps = Label(isl, {
			Text = "60 FPS", Font = Enum.Font.GothamBold, TextSize = 14,
			Position = UDim2.fromOffset(28, 0), Size = UDim2.fromOffset(70, 30),
		})
		UI.islTime = Label(isl, {
			Text = "0 мин", Font = Enum.Font.GothamBold, TextSize = 14, TextXAlignment = Enum.TextXAlignment.Center,
			Position = UDim2.fromOffset(105, 0), Size = UDim2.fromOffset(60, 30),
		})
		UI.islPing = Label(isl, {
			Text = "-- мс", Font = Enum.Font.GothamBold, TextSize = 14, TextXAlignment = Enum.TextXAlignment.Right,
			Position = UDim2.fromOffset(172, 0), Size = UDim2.fromOffset(62, 30),
		})
		UI.dotR = New("Frame", {
			Position = UDim2.fromOffset(244, 11), Size = UDim2.fromOffset(8, 8), BackgroundColor3 = T.good, BorderSizePixel = 0,
		}, isl)
		Corner(UI.dotR, 99)
		local islBtn = New("TextButton", {
			Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, BorderSizePixel = 0, Text = "", ZIndex = 3,
		}, isl)
		Connect(islBtn.Activated, function() SetOpen(not S.open) end)

		-- ================= КРУГЛАЯ ПЕРЕТАСКИВАЕМАЯ КНОПКА =================
		local fb = New("TextButton", {
			Name = "Toggle", Position = UDim2.new(0, 12, 1, -64), Size = UDim2.fromOffset(46, 46),
			BackgroundColor3 = T.card, BorderSizePixel = 0, AutoButtonColor = false,
			Text = (ICON_IMAGE == "") and "FPS" or "", TextSize = 14, Font = Enum.Font.GothamBold,
			TextColor3 = T.text, ZIndex = 10,
		}, gui)
		Corner(fb, 99)
		Stroke(fb, T.glow, 1.5)
		if ICON_IMAGE ~= "" then
			local img = New("ImageLabel", {
				Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, BorderSizePixel = 0, Image = ICON_IMAGE,
			}, fb)
			Corner(img, 99)
		end
		local dragging, moved, dragStart, startPos = false, false, nil, nil
		Connect(fb.InputBegan, function(input)
			local t = input.UserInputType
			if t == Enum.UserInputType.Touch or t == Enum.UserInputType.MouseButton1 then
				dragging = true
				moved = false
				dragStart = input.Position
				startPos = fb.Position
			end
		end)
		Connect(UIS.InputChanged, function(input)
			if not dragging then return end
			local t = input.UserInputType
			if t == Enum.UserInputType.Touch or t == Enum.UserInputType.MouseMovement then
				local d = input.Position - dragStart
				if d.Magnitude > 6 then moved = true end
				if moved then
					fb.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
				end
			end
		end)
		Connect(UIS.InputEnded, function(input)
			if not dragging then return end
			local t = input.UserInputType
			if t == Enum.UserInputType.Touch or t == Enum.UserInputType.MouseButton1 then
				dragging = false
				if not moved then SetOpen(not S.open) end
			end
		end)

		-- ================= ЗАВЕРШЕНИЕ СБОРКИ =================
		UI.setTurbo(S.limit == "max", true)
		SelectPage("FPS", true)
		gui.Parent = parent
		SetFeature("island", true)
		SetOpen(true)
	end)
end

-- ================= МОНИТОР FPS / ПИНГА / ЖУРНАЛА (одно соединение, 2 раза в секунду) =================

do
	Run("monitor", function()
		local pingItem
		pcall(function()
			local net = StatsService:WaitForChild("Network", 5)
			local ssi = net and net:WaitForChild("ServerStatsItem", 5)
			pingItem = ssi and ssi:FindFirstChild("Data Ping")
		end)

		local function Step()
			local fps = math.floor(S.fps + 0.5)
			local ping = 0
			if pingItem then
				local ok, v = pcall(pingItem.GetValue, pingItem)
				if ok and type(v) == "number" then ping = math.floor(v + 0.5) end
			end

			-- авто-буст
			if S.active.autoboost and not S.boosted then
				S.warm = S.warm + 1
				if S.warm > 6 then
					if S.fps < 28 then S.low = S.low + 1 else S.low = 0 end
					if S.low >= 4 then
						S.low = 0
						if EngageBoost then Run("autoboost", EngageBoost) end
						Log("авто-буст: графика облегчена (FPS ниже 28)")
					end
				end
			end

			-- остров (обновляем только изменившееся)
			if UI.island and UI.island.Visible then
				local ft = fps .. " FPS"
				if ft ~= S.lastFps then
					S.lastFps = ft
					UI.islFps.Text = ft
					UI.dotL.BackgroundColor3 = (fps >= 50) and T.good or ((fps >= 28) and T.warn or T.bad)
				end
				local pt = ping .. " мс"
				if pt ~= S.lastPing then
					S.lastPing = pt
					UI.islPing.Text = pt
					UI.dotR.BackgroundColor3 = (ping <= 100) and T.good or ((ping <= 200) and T.warn or T.bad)
				end
				local mt = math.floor((os.time() - S.t0) / 60) .. " мин"
				if mt ~= S.lastTime then
					S.lastTime = mt
					UI.islTime.Text = mt
				end
			end

			-- окно: статус и журнал (только когда меню открыто)
			if UI.root and UI.root.Visible then
				UI.status.Text = fps .. " FPS  |  Пинг " .. ping .. " мс"
				if S.logDirty and UI.logLabel then
					S.logDirty = false
					UI.logLabel.Text = (#S.log > 0) and table.concat(S.log, "\n") or "Ошибок нет"
				end
			end
		end

		Connect(RunService.Heartbeat, function(dt)
			S.frames = S.frames + 1
			S.acc = S.acc + dt
			if S.acc < 0.5 then return end
			S.fps = S.frames / S.acc
			S.frames = 0
			S.acc = 0
			local ok, err = pcall(Step)
			if not ok and not S.monErr then
				S.monErr = true
				Log("[monitor] " .. tostring(err))
			end
		end)
	end)
end

env.__MatteMenu = { Unload = Unload, State = S }
Log("меню запущено")
