local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local alive = true

local function sweepHighlights()
	for _, d in ipairs(workspace:GetDescendants()) do
		if (d:IsA("Highlight") and d.Name == "TU_ESP_Highlight") or d.Name == "TU_RangeCircle" then d:Destroy() end
	end
end

if _G.TURavaHubUnload then pcall(_G.TURavaHubUnload) end
if _G.TUClaudeUnload then pcall(_G.TUClaudeUnload) end

local old = playerGui:FindFirstChild("TURavaHubGUI") or playerGui:FindFirstChild("TUClaudeGUI")
if old then old:Destroy() end
sweepHighlights()

local connections = {}
local cleanups = {}

local OPTIONS = {
	AutoHide = true,  LineOfSight = true,  AutoElevator = true,
	Fuseboxes = true,  ItemsFirst = true,  PromptDelay = true,
	FastPickups = true,  CollectLast = false,
}

-- Diagnostic log: capped circular buffer, timestamps, categories, and counters.
local BUILD = "2.1 Teleport UI / Diagnostics"
local debugStart = os.clock()
local LOG_LIMIT = 4000
local debugLines, debugIndex, debugLast = {}, 0, {}
local debugStats = {
	teleports = 0, teleportFailures = 0, unsafeDestinations = 0,
	pickupAttempts = 0, pickupConfirmed = 0, pickupUnconfirmed = 0,
	promptAttempts = 0, promptFailures = 0, machineTargetChanges = 0,
	machineStalls = 0, skillcheckInputs = 0, skillcheckInputFailures = 0,
	chases = 0, workerErrors = 0, machineCompletions = 0,
	machinePlacements = 0, machineDangers = 0, fuseAttempts = 0,
	itemUseAttempts = 0, itemUseFailures = 0,
}
local debugStatus = { action = "Ready", lastWarning = "None", currentTarget = "None" }
local function increment(metric, amount)
	debugStats[metric] = (debugStats[metric] or 0) + (amount or 1)
end
local function fieldString(fields)
	if not fields then return "" end
	local keys, out = {}, {}
	for key in pairs(fields) do table.insert(keys, key) end
	table.sort(keys)
	for _, key in ipairs(keys) do
		local value = tostring(fields[key]):gsub("[\r\n|]", " "):sub(1, 240)
		table.insert(out, key .. "=" .. value)
	end
	return table.concat(out, " ")
end
local function debugEvent(category, event, fields, level)
	level = level or "INFO"
	debugIndex += 1
	local detail = fieldString(fields)
	local message = string.format("[%s][+%.2fs][%s][%s] %s%s",
		os.date("%H:%M:%S"), os.clock() - debugStart, level, category,
		event, detail ~= "" and " | " .. detail or "")
	debugLines[(debugIndex - 1) % LOG_LIMIT + 1] = message
	if level == "ERROR" or level == "WARN" then
		debugStatus.lastWarning = string.format("%s: %s", category, event)
	elseif category == "MACHINE" or category == "PICKUP" or category == "MOVE" then
		debugStatus.action = category .. ": " .. event
	end
end
local function debugThrottled(key, interval, category, event, fields, level)
	local now = os.clock()
	if now - (debugLast[key] or -math.huge) < interval then return end
	debugLast[key] = now
	debugEvent(category, event, fields, level)
end
local function debugLog(message)
	local msg = tostring(message)
	local category = msg:find("pickup") and "PICKUP"
		or (msg:find("machine") or msg:find("progress") or msg:find("place ")) and "MACHINE"
		or msg:find("skillcheck") and "SKILLCHECK" or "SYSTEM"
	local level = msg:find("^ERROR") and "ERROR" or "INFO"
	debugEvent(category, "legacy", { message = msg }, level)
end
local function recentDebugLines(limit, warningsOnly)
	local lines = {}
	for i = debugIndex, math.max(1, debugIndex - LOG_LIMIT + 1), -1 do
		local text = debugLines[(i - 1) % LOG_LIMIT + 1]
		if text and (not warningsOnly or text:find("%[WARN%]") or text:find("%[ERROR%]")) then
			table.insert(lines, text)
			if limit and #lines >= limit then break end
		end
	end
	return lines
end
local function allDebugLines()
	local lines = {}
	for i = math.max(1, debugIndex - LOG_LIMIT + 1), debugIndex do
		local text = debugLines[(i - 1) % LOG_LIMIT + 1]
		if text then table.insert(lines, text) end
	end
	return lines
end

-- All travel is instantaneous; no interpolation or route sampling.
local activeMotion
local infectedNear -- Assigned after monster-folder helpers are defined.
local motionPauseUntil = 0
local function cancelMotion(owner)
	if activeMotion and (not owner or activeMotion == owner) then
		debugEvent("MOVE", "cancel", { owner = activeMotion })
		activeMotion = nil
	end
end
local function teleportCharacter(destination, keepGoing, owner, mode)
	local emergency = mode == "emergency"
	if not alive or not keepGoing() then return false end
	if activeMotion and not emergency then
		debugThrottled("move_busy_" .. owner, 3, "MOVE", "occupied", { owner = owner }, "WARN")
		return false
	end
	if emergency then
		cancelMotion()
		motionPauseUntil = math.max(motionPauseUntil, os.clock() + 1.5)
	end
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsDescendantOf(workspace) then
		debugThrottled("root_" .. owner, 5, "MOVE", "root_missing", { owner = owner }, "WARN")
		return false
	end
	local from = root.Position
	local distance = (from - destination.Position).Magnitude
	if distance < 0.25 then return true end
	-- Routine movement refuses unsafe destinations. Emergency escapes remain immediate.
	if not emergency and infectedNear and infectedNear(destination.Position, 15) then
		increment("unsafeDestinations")
		debugThrottled("unsafe_" .. owner, 3, "MOVE", "unsafe_destination",
			{ owner = owner, position = tostring(destination.Position) }, "WARN")
		return false
	end
	activeMotion = owner
	local ok, err = pcall(function()
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
		root.CFrame = destination
	end)
	if activeMotion == owner then activeMotion = nil end
	if not ok then
		increment("teleportFailures")
		debugEvent("MOVE", "teleport_error", { owner = owner, error = err }, "ERROR")
		return false
	end
	local drift = (root.Position - destination.Position).Magnitude
	if drift > 4 then
		increment("teleportFailures")
		debugThrottled("drift_" .. owner, 1, "MOVE", "arrival_mismatch",
			{ owner = owner, drift = string.format("%.2f", drift), target = tostring(destination.Position) }, "WARN")
		return false
	end
	increment("teleports")
	debugEvent("MOVE", "teleport", {
		owner = owner, mode = emergency and "emergency" or "routine",
		distance = string.format("%.1f", distance), to = tostring(destination.Position),
	})
	return true
end

local function track(connection)
	table.insert(connections, connection)
	return connection
end

local function supervise(label, isActive, fn)
	task.spawn(function()
		while isActive() do
			local ok, err = pcall(fn)
			if ok then return end
			warn("[TU - Rava Hub] " .. label .. " error: " .. tostring(err))
			increment("workerErrors")
			debugEvent("WORKER", "crashed", { worker = label, error = tostring(err), retry = "0.5s" }, "ERROR")
			task.wait(0.5)
		end
	end)
end

local function new(class, props, parent)
	local inst = Instance.new(class)
	for k, v in pairs(props) do inst[k] = v end
	inst.Parent = parent
	return inst
end

local function corner(parent, radius) return new("UICorner", { CornerRadius = UDim.new(0, radius) }, parent) end

local function list(parent, padding, align)
	return new("UIListLayout", {
		Padding = UDim.new(0, padding),  SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = align or Enum.HorizontalAlignment.Left,
	}, parent)
end

-- UI / design tokens
local UI = {
	background = Color3.fromRGB(15, 18, 27), surface = Color3.fromRGB(23, 28, 39),
	surface2 = Color3.fromRGB(32, 38, 52), soft = Color3.fromRGB(40, 48, 65),
	accent = Color3.fromRGB(113, 124, 255), blue = Color3.fromRGB(80, 192, 255),
	good = Color3.fromRGB(70, 207, 148), bad = Color3.fromRGB(230, 102, 118),
	text = Color3.fromRGB(238, 241, 252), muted = Color3.fromRGB(147, 156, 180),
}
local function uiText(parent, value, size, bold, color, props)
	local config = { BackgroundTransparency = 1, Text = value, TextColor3 = color or UI.text,
		TextSize = size or 14, Font = bold and Enum.Font.GothamBold or Enum.Font.Gotham,
		TextXAlignment = Enum.TextXAlignment.Left, BorderSizePixel = 0 }
	for k, v in pairs(props or {}) do config[k] = v end
	return new("TextLabel", config, parent)
end
local function uiStroke(parent, color, thickness)
	return new("UIStroke", { Color = color or UI.soft, Thickness = thickness or 1, Transparency = 0.3 }, parent)
end

local screenGui = new("ScreenGui", {
	Name = "TURavaHubGUI", ResetOnSpawn = false, DisplayOrder = 2147483647,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling, IgnoreGuiInset = false,
}, playerGui)
local main = new("Frame", {
	Name = "HubWindow", Size = UDim2.fromOffset(650, 445), AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5), BackgroundColor3 = UI.background,
	BorderSizePixel = 0, Active = true, ClipsDescendants = true,
}, screenGui)
corner(main, 16)
uiStroke(main, UI.soft, 1)
local mainScale = new("UIScale", { Scale = 1 }, main)
local function fitToViewport()
	local camera = workspace.CurrentCamera
	local view = camera and camera.ViewportSize or Vector2.new(950, 700)
	mainScale.Scale = math.clamp(math.min((view.X - 22) / 650, (view.Y - 36) / 445), 0.36, 1)
end
fitToViewport()
-- Once-a-second fit check handles screen rotation without a per-frame UI listener.
task.spawn(function()
	while alive do
		fitToViewport()
		task.wait(1)
	end
end)

local top = new("Frame", { Size = UDim2.new(1, 0, 0, 64), BackgroundColor3 = UI.surface,
	BorderSizePixel = 0, Active = true }, main)
new("Frame", { Size = UDim2.new(1, 0, 0, 2), Position = UDim2.new(0, 0, 1, -2),
	BackgroundColor3 = UI.accent, BorderSizePixel = 0 }, top)
uiText(top, "RAVA", 22, true, UI.text, { Position = UDim2.fromOffset(22, 10), Size = UDim2.fromOffset(130, 27) })
uiText(top, "TU   /   CONTROL HUB", 10, true, UI.muted,
	{ Position = UDim2.fromOffset(23, 37), Size = UDim2.fromOffset(190, 15) })
local headerStatus = uiText(top, "SYSTEM READY", 12, true, UI.good,
	{ Position = UDim2.fromOffset(346, 20), Size = UDim2.fromOffset(192, 24), TextXAlignment = Enum.TextXAlignment.Right })
local minimizeButton = new("TextButton", { Text = "—", Size = UDim2.fromOffset(32, 32),
	Position = UDim2.new(1, -84, 0, 15), BackgroundColor3 = UI.surface2,
	TextColor3 = UI.text, TextSize = 18, Font = Enum.Font.GothamBold, BorderSizePixel = 0 }, top)
corner(minimizeButton, 8)
local unloadButton = new("TextButton", { Text = "×", Size = UDim2.fromOffset(32, 32),
	Position = UDim2.new(1, -45, 0, 15), BackgroundColor3 = Color3.fromRGB(92, 47, 62),
	TextColor3 = UI.text, TextSize = 24, Font = Enum.Font.GothamBold, BorderSizePixel = 0 }, top)
corner(unloadButton, 8)

local sidebar = new("Frame", { Position = UDim2.fromOffset(0, 64), Size = UDim2.new(0, 158, 1, -94),
	BackgroundColor3 = UI.surface, BorderSizePixel = 0 }, main)
new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 7) }, sidebar)
new("UIPadding", { PaddingTop = UDim.new(0, 15), PaddingLeft = UDim.new(0, 10),
	PaddingRight = UDim.new(0, 10) }, sidebar)
local mainArea = new("Frame", { Position = UDim2.fromOffset(158, 64),
	Size = UDim2.new(1, -158, 1, -94), BackgroundTransparency = 1 }, main)
local footer = new("Frame", { Position = UDim2.new(0, 0, 1, -30), Size = UDim2.new(1, 0, 0, 30),
	BackgroundColor3 = UI.surface, BorderSizePixel = 0 }, main)
local footerLabel = uiText(footer, "v2.1   •   TELEPORT MODE   •   LOGGING ACTIVE", 11, false, UI.muted,
	{ Position = UDim2.fromOffset(17, 5), Size = UDim2.new(1, -30, 0, 21) })
local pages, menuButtons, activeTab = {}, {}, "Autofarm"
local TAB_ORDER = { "ESP", "Autofarm", "Machines", "Diagnostics" }
local TAB_SYMBOL = { ESP = "◉", Autofarm = "◆", Machines = "▣", Diagnostics = "≡" }
local function showTab(name)
	activeTab = name
	for key, page in pairs(pages) do page.Visible = key == name end
	for key, button in pairs(menuButtons) do
		button.BackgroundColor3 = key == name and UI.soft or UI.surface
		button.TextColor3 = key == name and UI.text or UI.muted
	end
end
for index, name in ipairs(TAB_ORDER) do
	local button = new("TextButton", { Name = name .. "Tab", Size = UDim2.new(1, 0, 0, 45),
		LayoutOrder = index, BackgroundColor3 = UI.surface, BorderSizePixel = 0,
		Text = "  " .. TAB_SYMBOL[name] .. "    " .. name, Font = Enum.Font.GothamMedium,
		TextSize = 14, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = UI.muted }, sidebar)
	corner(button, 9)
	menuButtons[name] = button
	track(button.MouseButton1Click:Connect(function()
		showTab(name)
		debugEvent("UI", "open_tab", { tab = name })
	end))
end
local function createSection(name)
	local page = new("ScrollingFrame", {
		Name = name .. "Page", Position = UDim2.fromOffset(0, 0), Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 4,
		ScrollBarImageColor3 = UI.accent, CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y, Visible = name == activeTab,
	}, mainArea)
	list(page, 9)
	new("UIPadding", { PaddingTop = UDim.new(0, 15), PaddingLeft = UDim.new(0, 14),
		PaddingRight = UDim.new(0, 14), PaddingBottom = UDim.new(0, 14) }, page)
	pages[name] = page
	uiText(page, name, 20, true, UI.text, {
		Size = UDim2.new(1, -8, 0, 30), LayoutOrder = -2,
	})
	uiText(page, (name == "ESP" and "Visual overlays and objective markers")
		or (name == "Autofarm" and "Pickup automation and inventory filters")
		or (name == "Machines" and "Objective logic and protection")
		or "Runtime telemetry and test reports", 12, false, UI.muted, {
		Size = UDim2.new(1, -8, 0, 18), LayoutOrder = -1,
	})
	return page
end
local function createToggleRow(parent, name, order, feature)
	local row = new("Frame", { Size = UDim2.new(1, -9, 0, 43),
		BackgroundColor3 = UI.surface, BorderSizePixel = 0, LayoutOrder = order }, parent)
	corner(row, 9)
	uiStroke(row)
	uiText(row, name, 14, false, UI.text, {
		Position = UDim2.fromOffset(12, 0), Size = UDim2.new(1, -97, 1, 0),
	})
	local button = new("TextButton", {
		Size = UDim2.fromOffset(62, 28), Position = UDim2.new(1, -73, 0.5, -14),
		BorderSizePixel = 0, TextSize = 12, Font = Enum.Font.GothamBold,
		TextColor3 = UI.text,
	}, row)
	corner(button, 15)
	local function refresh()
		button.Text = feature.enabled and "ON" or "OFF"
		button.BackgroundColor3 = feature.enabled and Color3.fromRGB(45, 133, 109) or UI.soft
	end
	refresh()
	track(button.MouseButton1Click:Connect(function()
		local enabled = not feature.enabled
		local ok, err = pcall(function()
			if enabled then feature.enable() else feature.disable() end
		end)
		if ok then
			debugEvent("UI", "feature_changed", { name = name, enabled = feature.enabled })
		else
			increment("workerErrors")
			debugEvent("UI", "toggle_error", { name = name, error = err }, "ERROR")
		end
		refresh()
	end))
end

-- Window drag supports mouse and touch; buttons remain independently clickable.
do
	local dragging, origin, start
	local function isPress(input)
		return input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
	end
	track(top.InputBegan:Connect(function(input)
		if isPress(input) then dragging, origin, start = true, input.Position, main.Position end
	end))
	track(UserInputService.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			local delta = input.Position - origin
			main.Position = UDim2.new(start.X.Scale, start.X.Offset + delta.X, start.Y.Scale, start.Y.Offset + delta.Y)
		end
	end))
	track(UserInputService.InputEnded:Connect(function(input)
		if isPress(input) then dragging = false end
	end))
end
-- Small draggable launcher stays visible when the main window is hidden.
local launcher = new("TextButton", { Name = "RavaLauncher", Size = UDim2.fromOffset(50, 50),
	Position = UDim2.new(0, 14, 0.5, -25), BackgroundColor3 = UI.accent,
	Text = "R", TextColor3 = Color3.new(1, 1, 1), Font = Enum.Font.GothamBold,
	TextSize = 25, BorderSizePixel = 0, ZIndex = 10 }, screenGui)
corner(launcher, 16)
uiStroke(launcher, UI.text, 1)
do
	local dragging, moved, origin, start
	track(launcher.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging, moved, origin, start = true, false, input.Position, launcher.Position
		end
	end))
	track(UserInputService.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			local delta = input.Position - origin
			if delta.Magnitude > 6 then moved = true end
			if moved then launcher.Position = UDim2.new(start.X.Scale, start.X.Offset + delta.X,
				start.Y.Scale, start.Y.Offset + delta.Y) end
		end
	end))
	track(UserInputService.InputEnded:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) then
			dragging = false
			if not moved then main.Visible = not main.Visible end
		end
	end))
end
track(minimizeButton.MouseButton1Click:Connect(function()
	main.Visible = false
end))
showTab(activeTab)

local ESP_REFRESH = 1

local function resolveWorkspacePath(path)
	local current = workspace
	for name in path:gmatch("[^%.]+") do current = current and current:FindFirstChild(name) end
	return current
end

-- ESP overlays
local ESP_CONFIGS = {
	{ Name = "Item ESP", Folders = { "Items", "Capsules", "Candies" }, Color = Color3.fromRGB(255, 220, 70), TopLevelOnly = true },
	{ Name = "Objective ESP", Folders = { "Computers", "OilMachines" }, Color = Color3.fromRGB(90, 255, 120), TopLevelOnly = true, Extra = { "Map.SpecialFolder.BigMachine.Computer", "Map.SpecialFolder.BigMachine.Machine" } },
	{ Name = "Infected ESP", Folders = { "MonsterFolder" }, Color = Color3.fromRGB(255, 60, 60) },
}

local function isTarget(config, root, inst)
	if config.TopLevelOnly then
		return inst.Parent == root and (inst:IsA("Model") or inst:IsA("BasePart") or inst:IsA("Folder"))
	end
	if not (inst:IsA("Model") or inst:IsA("BasePart")) then return false end
	local parent = inst.Parent
	return parent == root or (parent ~= nil and parent:IsA("Folder") and parent:IsDescendantOf(root))
end

local function getAdorneePart(inst)
	if inst:IsA("BasePart") then return inst end
	if inst:IsA("Model") and inst.PrimaryPart then return inst.PrimaryPart end
	return inst:FindFirstChildWhichIsA("BasePart", true)
end

local function createESPObject(config, inst)
	local record = { conns = {} }
	record.highlight = new("Highlight", {
		Name = "TU_ESP_Highlight",  Adornee = inst,  DepthMode = Enum.HighlightDepthMode.AlwaysOnTop,
		FillTransparency = 1,  OutlineTransparency = 0,  OutlineColor = config.Color,
	}, inst)
	local function buildLabel()
		if record.billboard then return true end
		local adornee = getAdorneePart(inst)
		if not adornee then return false end
		local height = inst:IsA("Model") and inst:GetExtentsSize().Y or adornee.Size.Y
		record.billboard = new("BillboardGui", {
			Adornee = adornee,  AlwaysOnTop = true,  Size = UDim2.fromOffset(180, 24),
			StudsOffsetWorldSpace = Vector3.new(0, height / 2 + 1.5, 0),  MaxDistance = math.huge,  ResetOnSpawn = false,
		}, screenGui)
		local label = new("TextLabel", {
			BackgroundTransparency = 1,  Size = UDim2.fromScale(1, 1),  Text = inst.Name,
			TextColor3 = config.Color,  TextStrokeTransparency = 0,  TextSize = 16,
			Font = Enum.Font.GothamBold,
		}, record.billboard)
		table.insert(record.conns, inst:GetPropertyChangedSignal("Name"):Connect(function()
			label.Text = inst.Name
		end))
		return true
	end
	if not buildLabel() then
		local conn
		conn = inst.DescendantAdded:Connect(function()
			if buildLabel() then conn:Disconnect() end
		end)
		table.insert(record.conns, conn)
	end
	return record
end

local function destroyESPObject(record)
	for _, c in ipairs(record.conns) do c:Disconnect() end
	record.highlight:Destroy()
	if record.billboard then record.billboard:Destroy() end
end

local function newESP(config)
	local state = { enabled = false, objects = {}, run = 0 }
	local function sync()
		local wanted = {}
		for _, name in ipairs(config.Folders) do
			local root = resolveWorkspacePath(name)
			if root then
				for _, d in ipairs(config.TopLevelOnly and root:GetChildren() or root:GetDescendants()) do
					if isTarget(config, root, d) then wanted[d] = true end
				end
			end
		end
		for _, path in ipairs(config.Extra or {}) do
			local inst = resolveWorkspacePath(path)
			if inst then wanted[inst] = true end
		end
		for inst, record in pairs(state.objects) do
			if not wanted[inst] or not record.highlight.Parent then
				destroyESPObject(record)
				state.objects[inst] = nil
			end
		end
		for inst in pairs(wanted) do if not state.objects[inst] then state.objects[inst] = createESPObject(config, inst) end end
	end
	function state.enable()
		if state.enabled then return end
		state.enabled = true
		state.run += 1
		local myRun = state.run
		supervise("esp", function()
			return alive and state.enabled and state.run == myRun
		end, function()
			while alive and state.enabled and state.run == myRun do
				sync()
				task.wait(ESP_REFRESH)
			end
		end)
	end
	function state.disable()
		state.enabled = false
		state.run += 1
		for inst, record in pairs(state.objects) do
			destroyESPObject(record)
			state.objects[inst] = nil
		end
	end
	table.insert(cleanups, state.disable)
	return state
end

-- Pickup configuration and proximity prompts
local FARM = {
	Height = 3,  Settle = 0.12,  Dwell = 0.8,
	Revisit = 5,  FailedRetry = 0.6,  Empty = 0.25,
	Poll = 0.04,  IdleReturn = 2,  HeldLimit = 3,
	SpamRate = 8,  InfectedClear = 15,
}

local FARM_BASE = { Settle = 0.12, Dwell = 0.8, FailedRetry = 0.6, Empty = 0.25, Poll = 0.04, SpamRate = 8 }
local FARM_FAST = { Settle = 0.03, Dwell = 0.5, FailedRetry = 0.3, Empty = 0.1, Poll = 0.02, SpamRate = 15 }

for key, value in pairs(OPTIONS.FastPickups and FARM_FAST or FARM_BASE) do FARM[key] = value end

local PROMPT_DELAY = 0.5

local PROMPT_HOLDERS = { "Prompt", "PromptPart" }

local function getPrompt(target)
	for _, name in ipairs(PROMPT_HOLDERS) do
		local holder = target:FindFirstChild(name)
		if holder then
			if holder:IsA("ProximityPrompt") then return holder end
			local direct = holder:FindFirstChildWhichIsA("ProximityPrompt", true)
			if direct then return direct end
		end
	end
	return target:FindFirstChildWhichIsA("ProximityPrompt", true)
end

local function getPromptPart(prompt, target)
	local parent = prompt.Parent
	if parent and parent:IsA("BasePart") then return parent end
	if parent and parent:IsA("Attachment") and parent.Parent:IsA("BasePart") then return parent.Parent end
	return getAdorneePart(target)
end

local hasFirePrompt = typeof(fireproximityprompt) == "function"

local function triggerPrompt(prompt)
	increment("promptAttempts")
	if not prompt or not prompt:IsA("ProximityPrompt") or not prompt:IsDescendantOf(workspace) then
		increment("promptFailures")
		debugThrottled("invalid_pickup_prompt", 3, "PROMPT", "invalid_target", nil, "WARN")
		return false
	end
	if hasFirePrompt then
		local ok = pcall(fireproximityprompt, prompt)
		if ok then return true end
	end
	local began = pcall(function()
		prompt:InputHoldBegin()
	end)
	if not began then
		increment("promptFailures")
		debugThrottled("pickup_prompt_failed_" .. prompt.Name, 3, "PROMPT", "hold_begin_failed",
			{ prompt = prompt.Name, owner = tostring(prompt.Parent) }, "WARN")
		return false
	end
	task.wait(math.max(0, prompt.HoldDuration) + 0.05)
	pcall(function()
		prompt:InputHoldEnd()
	end)
	return true
end

local machinePromptHolds = setmetatable({}, { __mode = "k" })
local modifiedMachinePrompts = setmetatable({}, { __mode = "k" })

local function triggerMachinePrompt(prompt)
	increment("promptAttempts")
	if not prompt or not prompt:IsA("ProximityPrompt") or not prompt:IsDescendantOf(workspace) or not prompt.Enabled then
		increment("promptFailures")
		debugThrottled("machine_prompt_invalid", 3, "PROMPT", "machine_prompt_unavailable", nil, "WARN")
		return false
	end
	if not modifiedMachinePrompts[prompt] then
		modifiedMachinePrompts[prompt] = { hold = prompt.HoldDuration, sight = prompt.RequiresLineOfSight }
	end
	if prompt.HoldDuration ~= 0 then pcall(function() prompt.HoldDuration = 0 end) end
	if prompt.RequiresLineOfSight then pcall(function() prompt.RequiresLineOfSight = false end) end
	if hasFirePrompt then
		local ok = pcall(fireproximityprompt, prompt)
		if ok then return true end
	end
	if machinePromptHolds[prompt] then return false end
	local ok = pcall(function()
		prompt:InputHoldBegin()
	end)
	if not ok then
		increment("promptFailures")
		debugThrottled("machine_prompt_failed_" .. prompt.Name, 3, "PROMPT", "machine_hold_failed",
			{ prompt = prompt.Name }, "WARN")
		return false
	end
	machinePromptHolds[prompt] = true
	local holdTime = math.max(0.12, prompt.HoldDuration)
	task.delay(holdTime + 0.03, function()
		pcall(function()
			prompt:InputHoldEnd()
		end)
		machinePromptHolds[prompt] = nil
	end)
	return true
end

local function cancelMachinePromptHold(prompt)
	if not prompt then return end
	if machinePromptHolds[prompt] then
		pcall(function()
			prompt:InputHoldEnd()
		end)
		machinePromptHolds[prompt] = nil
	end
end

local function restoreMachinePrompts()
	for prompt in pairs(machinePromptHolds) do
		if prompt.Parent then cancelMachinePromptHold(prompt) end
	end
	for prompt, old in pairs(modifiedMachinePrompts) do
		if prompt.Parent then
			pcall(function()
				prompt.HoldDuration = old.hold
				prompt.RequiresLineOfSight = old.sight
			end)
		end
		modifiedMachinePrompts[prompt] = nil
	end
end

table.insert(cleanups, restoreMachinePrompts)

local MACHINE_PROMPT_EXCLUDED_FOLDERS = {
	TPhantasia = true,  TSquid = true,  TSnakes = true,
}

local function isInsideMachineExcludedFolder(inst)
	local current = inst
	while current and current ~= workspace do
		if MACHINE_PROMPT_EXCLUDED_FOLDERS[current.Name] then return true end
		current = current.Parent
	end
	return false
end

local heldCount

local function spamPrompt(prompt, target, keepGoing, confirmPickup)
	local home = target.Parent
	local startingHeld = heldCount()
	local deadline = os.clock() + FARM.Dwell
	local confirmed = false
	while keepGoing() and os.clock() < deadline and target.Parent == home and prompt:IsDescendantOf(target) do
		if not prompt.Enabled then
			confirmed = true
			break
		end
		if confirmPickup and heldCount() > startingHeld then
			confirmed = true
			break
		end
		local started = os.clock()
		-- Only activate the intended target, not unrelated prompts nearby.
		triggerPrompt(prompt)
		task.wait(FARM.Poll)
		if target.Parent ~= home or not prompt:IsDescendantOf(target) or not prompt.Enabled then
			confirmed = true
			break
		end
		if confirmPickup and heldCount() > startingHeld then
			confirmed = true
			break
		end
		local rest = 1 / FARM.SpamRate - (os.clock() - started)
		if rest > 0 then task.wait(rest) end
	end
	if target.Parent ~= home or not prompt:IsDescendantOf(target) or not prompt.Enabled then confirmed = true end
	return confirmed
end

local function getTargets(folder)
	local targets = {}
	for _, child in ipairs(folder:GetChildren()) do
		if child:IsA("Folder") then
			for _, inner in ipairs(child:GetChildren()) do table.insert(targets, inner) end
		else
			table.insert(targets, child)
		end
	end
	return targets
end

heldCount = function()
	local folder = player:FindFirstChild("ItemsFolder")
	return folder and #folder:GetChildren() or 0
end

local chase = { pending = false, holdUntil = 0 }

-- Only one pickup worker may move / activate prompts at a time.
-- Keep a shared home so switching workers cannot overwrite the return location.
-- Coordinated pickup farming
local pickupCoordinator = {
	owner = nil,  home = nil,  lastActivity = os.clock(),
	enabledCount = 0,
}

local function releasePickup(farm)
	if pickupCoordinator.owner == farm then
		pickupCoordinator.owner = nil
		pickupCoordinator.lastActivity = os.clock()
	end
end

local function returnPickupHome(force, isBlocked)
	if not pickupCoordinator.home or pickupCoordinator.owner then return end
	if isBlocked and isBlocked() then
		pickupCoordinator.home = nil -- Machine work supersedes the previous pickup origin.
		return
	end
	if not force and os.clock() - pickupCoordinator.lastActivity < FARM.IdleReturn then return end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root then
		local home = pickupCoordinator.home
		pickupCoordinator.owner = "return"
		local arrived = teleportCharacter(home, function()
			return alive and pickupCoordinator.owner == "return" and not (isBlocked and isBlocked())
		end, "return")
		pickupCoordinator.owner = nil
		if arrived then
			pickupCoordinator.home = nil
			debugLog("pickups returned home")
		else
			pickupCoordinator.lastActivity = os.clock()
			if force then pickupCoordinator.home = nil end -- No active worker to retry.
		end
	end
end

track(player.CharacterAdded:Connect(function()
	cancelMotion()
	pickupCoordinator.owner, pickupCoordinator.home = nil, nil
end))

local function newAutofarm(folderName, gate, filter, confirmPickup, isBlocked)
	local farm = { enabled = false, working = false, hasWork = false }
	local runId = 0
	local recent = setmetatable({}, { __mode = "k" })
	local function loop(myId)
		local function active() return alive and farm.enabled and runId == myId end
		local function allowed()
			return active() and (not gate or gate()) and not (isBlocked and isBlocked())
				and os.clock() >= motionPauseUntil
				and not (OPTIONS.AutoHide and os.clock() < chase.holdUntil)
		end
		while active() do
			local folders = {}
			if type(folderName) == "table" then
				for _, name in ipairs(folderName) do
					local folder = workspace:FindFirstChild(name)
					if folder then table.insert(folders, folder) end
				end
			else
				local folder = workspace:FindFirstChild(folderName)
				if folder then table.insert(folders, folder) end
			end
			local didWork = false
			if allowed() then
				for _, folder in ipairs(folders) do
					for _, target in ipairs(getTargets(folder)) do
						if not allowed() then break end
						local character = player.Character
						local root = character and character:FindFirstChild("HumanoidRootPart")
						local prompt = target.Parent and getPrompt(target)
						local fresh = (not filter or filter(target)) and (not recent[target] or os.clock() - recent[target] >= FARM.Revisit)
						local part = fresh and root and prompt and prompt.Enabled and getPromptPart(prompt, target)
						local unsafe = part and infectedNear(part.Position, FARM.InfectedClear)
						if unsafe then
							debugThrottled("pickup_unsafe_" .. tostring(target), 5, "PICKUP", "skipped_enemy_nearby",
								{ folder = folder.Name, name = target.Name }, "WARN")
						end
						if part and not unsafe and pickupCoordinator.owner == nil then
							-- This claim has no yield, so other workers cannot claim this action.
							pickupCoordinator.owner = farm
							pickupCoordinator.lastActivity = os.clock()
							pickupCoordinator.home = pickupCoordinator.home or root.CFrame
							didWork = true
							farm.working = true
							increment("pickupAttempts")
							local beganAt = os.clock()
							debugEvent("PICKUP", "attempt", { folder = folder.Name, name = target.Name,
								held = heldCount(), prompt = prompt.Name, distance = string.format("%.1f", (root.Position - part.Position).Magnitude) })
							-- Always release the claim, even if a Roblox instance is removed mid-pickup.
							local ok, confirmed = pcall(function()
								if not allowed() then return false end
								local function stillPicking()
									return allowed() and pickupCoordinator.owner == farm
										and part:IsDescendantOf(workspace) and prompt.Enabled
								end
								if not teleportCharacter(CFrame.new(part.Position + Vector3.new(0, FARM.Height, 0)),
									function() return stillPicking() and not infectedNear(part.Position, FARM.InfectedClear) end, "pickup") then
									return false
								end
								task.wait(FARM.Settle)
								if OPTIONS.PromptDelay then task.wait(PROMPT_DELAY) end
								if not stillPicking() then return false end
								return spamPrompt(prompt, target, stillPicking, confirmPickup)
							end)
							releasePickup(farm)
							if not ok then
								debugLog("ERROR pickup " .. tostring(target.Name) .. ": " .. tostring(confirmed))
								warn("[TU - Rava Hub] pickup error: " .. tostring(confirmed))
								confirmed = false
							else
								debugLog(string.format("pickup %s dist=%.1f max=%.1f hold=%.2f confirmed=%s", target.Name,
									(root.Position - part.Position).Magnitude, prompt.MaxActivationDistance, prompt.HoldDuration, tostring(confirmed)))
							end
							if confirmed then
								increment("pickupConfirmed")
								recent[target] = os.clock()
							else
								increment("pickupUnconfirmed")
								recent[target] = os.clock() - FARM.Revisit + FARM.FailedRetry
							end
							debugEvent("PICKUP", "result", { folder = folder.Name, name = target.Name,
								confirmed = confirmed, duration = string.format("%.2f", os.clock() - beganAt), held = heldCount() },
								confirmed and "INFO" or "WARN")
						end
					end
					if not allowed() then break end
				end
			end
			farm.hasWork = didWork
			farm.working = false
			if not didWork then
				returnPickupHome(false, isBlocked)
				task.wait(FARM.Empty)
			end
		end
	end
	function farm.enable()
		if farm.enabled then return end
		farm.enabled = true
		pickupCoordinator.enabledCount += 1
		runId += 1
		local myId = runId
		supervise("item autofarm", function()
			return alive and farm.enabled and runId == myId
		end, function()
			loop(myId)
		end)
	end
	function farm.disable()
		if not farm.enabled then return end
		farm.enabled = false
		farm.working = false
		farm.hasWork = false
		runId += 1
		pickupCoordinator.enabledCount = math.max(0, pickupCoordinator.enabledCount - 1)
		if pickupCoordinator.owner == farm then cancelMotion("pickup") end
		releasePickup(farm)
		if pickupCoordinator.enabledCount == 0 then
			if isBlocked and isBlocked() then
				-- Do not later restore a stale pickup position after machine work.
				pickupCoordinator.home = nil
			else
				returnPickupHome(true, isBlocked)
			end
		end
	end
	table.insert(cleanups, farm.disable)
	return farm
end

local espBody = createSection("ESP", 1)
for i, config in ipairs(ESP_CONFIGS) do createToggleRow(espBody, config.Name, i, newESP(config)) end

-- Inventory and automatic item usage
local TRASH_ITEMS = { Coffee = true, Socks = true, Waffle = true, ["Pristine Boots"] = true }
local HEALTH_ITEMS = { Bandaid = true, Medkit = true, ["Pristine Medkit"] = true }
local ITEM_OPTIONS = { Trash = false, Health = false }

local function getHealth()
	local aliveFolder = workspace:FindFirstChild("Alive")
	local character = aliveFolder and aliveFolder:FindFirstChild(player.Name)
	local health = character and character:GetAttribute("Health")
	return type(health) == "number" and health or nil
end

local function itemAllowed(item)
	if TRASH_ITEMS[item.Name] then return ITEM_OPTIONS.Trash end
	if HEALTH_ITEMS[item.Name] then
		if not ITEM_OPTIONS.Health then return false end
		local health = getHealth()
		return health ~= nil and health ~= 3
	end
	return true
end

local USE_ITEMS = {
	Oil = { Wrench = true, ["Pristine Wrench"] = true, Gloves = true, ["Pristine Gloves"] = true },
	Computer = { USB = true, ["Pristine USB"] = true, Mint = true, ["Pristine Mint"] = true },
	Health = HEALTH_ITEMS,
}

local AUTO_USE = { Tick = 0.25, HealCooldown = 3, UseDelay = 0.2 }
local SLOT_KEYS = { Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.Three }

local function readItemIndex(item)
	local index = item:GetAttribute("Index")
	if index == nil then
		local indexValue = item:FindFirstChild("Index")
		if indexValue and indexValue:IsA("ValueBase") then index = indexValue.Value end
	end
	if type(index) == "string" then index = tonumber(index) end
	if type(index) == "number" and index % 1 == 0 and SLOT_KEYS[index] then return index end
	return nil
end

local function findSlot(names)
	local folder = player:FindFirstChild("ItemsFolder")
	if not folder then return nil end
	for _, item in ipairs(folder:GetChildren()) do
		if names[item.Name] then
			local index = readItemIndex(item)
			if index then return index end
		end
	end
	return nil
end

local function pressSlot(slot, purpose)
	increment("itemUseAttempts")
	local ok = pcall(function()
		local vim = game:GetService("VirtualInputManager")
		vim:SendKeyEvent(true, SLOT_KEYS[slot], false, game)
		task.wait(0.05)
		vim:SendKeyEvent(false, SLOT_KEYS[slot], false, game)
	end)
	if not ok and typeof(keypress) == "function" and typeof(keyrelease) == "function" then
		ok = pcall(function()
			keypress(0x30 + slot)
			task.wait(0.05)
			keyrelease(0x30 + slot)
		end)
	end
	if not ok then increment("itemUseFailures") end
	debugEvent("ITEM", "slot_input", { slot = slot, purpose = purpose or "unknown", dispatched = ok },
		ok and "INFO" or "WARN")
	return ok
end

local function useForMachine(machine)
	local names = (machine:FindFirstChild("OilValue") and USE_ITEMS.Oil)
		or (machine:FindFirstChild("ComputerPercentage") and USE_ITEMS.Computer)
	local slot = names and findSlot(names)
	if slot then
		pressSlot(slot, "machine:" .. machine.Name)
	else
		debugThrottled("tool_missing_" .. machine.Name, 5, "ITEM", "tool_missing", { machine = machine.Name }, "WARN")
	end
end

local autoUse = { enabled = false }
local autoUseRun = 0

function autoUse.enable()
	if autoUse.enabled then return end
	autoUse.enabled = true
	autoUseRun += 1
	local myRun = autoUseRun
	supervise("auto use", function()
		return alive and autoUse.enabled and autoUseRun == myRun
	end, function()
		local lastHeal = 0
		while alive and autoUse.enabled and autoUseRun == myRun do
			local health = getHealth()
			if health and health < 3 and os.clock() - lastHeal >= AUTO_USE.HealCooldown then
				local slot = findSlot(HEALTH_ITEMS)
				if slot then
					lastHeal = os.clock()
					pressSlot(slot, "heal")
				end
			end
			task.wait(AUTO_USE.Tick)
		end
	end)
end

function autoUse.disable()
	autoUse.enabled = false
	autoUseRun += 1
end

table.insert(cleanups, autoUse.disable)

local PICKUPS = {}

local function pickupBusy()
	for _, entry in ipairs(PICKUPS) do
		if entry.farm.enabled and (entry.farm.working or entry.farm.hasWork) then return true end
	end
	return false
end

local function pickupsRemaining()
	for _, entry in ipairs(PICKUPS) do
		if entry.farm.enabled and (not entry.held or heldCount() < FARM.HeldLimit) then
			local folder = workspace:FindFirstChild(entry.folder)
			if folder then
				for _, target in ipairs(getTargets(folder)) do
					local prompt = getPrompt(target)
					if prompt and prompt.Enabled and (not entry.filter or entry.filter(target)) then return true end
				end
			end
		end
	end
	return false
end

local machineFarm
local machinesDone

local function collectOpen() return not OPTIONS.CollectLast or (machinesDone ~= nil and machinesDone()) end

local function machineBusy()
	return machineFarm ~= nil and (machineFarm.placed == true or machineFarm.moving == true)
end

local capsuleFarm = newAutofarm("Capsules", collectOpen, nil, false, machineBusy)

local itemFarm = newAutofarm("Items", function()
	return heldCount() < FARM.HeldLimit and not capsuleFarm.working and collectOpen()
end, itemAllowed, true, machineBusy)

local candyFarm = newAutofarm("Candies", function()
	return not capsuleFarm.working and not itemFarm.working and collectOpen()
end, nil, false, machineBusy)

PICKUPS = {
	{ farm = capsuleFarm, folder = "Capsules" },
	{ farm = itemFarm, folder = "Items", held = true, filter = itemAllowed },
	{ farm = candyFarm, folder = "Candies" },
}

local function newOption(options, key, onChange)
	local option = { enabled = options[key] }
	function option.enable()
		option.enabled = true
		options[key] = true
		if onChange then onChange(true) end
	end
	function option.disable()
		option.enabled = false
		options[key] = false
		if onChange then onChange(false) end
	end
	return option
end

local farmBody = createSection("Autofarm", 2)
createToggleRow(farmBody, "Capsule Autofarm", 1, capsuleFarm)
createToggleRow(farmBody, "Item Autofarm", 2, itemFarm)
createToggleRow(farmBody, "Candy Autofarm", 3, candyFarm)
createToggleRow(farmBody, "Pick Up Trash Items", 4, newOption(ITEM_OPTIONS, "Trash"))
createToggleRow(farmBody, "Pick Up Health Items", 5, newOption(ITEM_OPTIONS, "Health"))
createToggleRow(farmBody, "Auto Use Items", 6, autoUse)
createToggleRow(farmBody, "Fast Pickups", 7, newOption(OPTIONS, "FastPickups", function(on)
	for key, value in pairs(on and FARM_FAST or FARM_BASE) do FARM[key] = value end
end))
createToggleRow(farmBody, "Collect After Machines", 8, newOption(OPTIONS, "CollectLast"))

-- Machine objectives and danger detection
local MACHINE = {
	Folders = { "OilMachines", "Computers" },  Range = 50,  Height = 3,
	Elevator = "Map.SpecialFolder.ExitElevator",  ElevatorFallback = "Elevator",  ElevatorHeight = -20,
	Tick = 0.02,  Settle = 0.04,  PromptRetry = 0.05,
	RescanInterval = 0.5,  StallTimeout = 4,  UseTimeout = 12,
	ClearHold = 1.5,  ItemWaitMax = 30,  ItemIdle = 3,
	EyeHeight = 3,  SkillcheckPause = 3,  SkillcheckStale = 6,
	ChaseHold = 3,  DoneValue = 100,  FuseDwell = 1,
	Fuseboxes = {
		"Map.SpecialFolder.Fusebox.Handle.ProximityPrompt",
		"Map.SpecialFolder.ExitFusebox.Handle.ProximityPrompt",
	},
	Allowed = { TSelena = true, TSquid = true, TPhantasia = true, TFizzle = true, TSnakes = true },
	CircleSink = 1,
}

local function targetPosition(inst)
	if inst:IsA("BasePart") then return inst.Position end
	if inst:IsA("Model") then return inst:GetPivot().Position end
	local part = getAdorneePart(inst)
	return part and part.Position
end

local function targetFloor(inst)
	if inst:IsA("Model") then
		local cf, size = inst:GetBoundingBox()
		return cf.Position.Y - size.Y / 2
	end
	local pos = targetPosition(inst)
	return pos and pos.Y - (inst:IsA("BasePart") and inst.Size.Y / 2 or 0)
end

local function getMachines()
	local list = {}
	for _, name in ipairs(MACHINE.Folders) do
		local folder = workspace:FindFirstChild(name)
		if folder then
			for _, target in ipairs(getTargets(folder)) do
				if not isInsideMachineExcludedFolder(target) then table.insert(list, target) end
			end
		end
	end
	return list
end

local sightParams = RaycastParams.new()
sightParams.FilterType = Enum.RaycastFilterType.Exclude
sightParams.RespectCanCollide = true

infectedNear = function(position, radius)
	local folder = workspace:FindFirstChild("MonsterFolder")
	if not folder then return false end
	for _, twisted in ipairs(getTargets(folder)) do
		if not isInsideMachineExcludedFolder(twisted) and not MACHINE.Allowed[twisted.Name] then
			local pos = targetPosition(twisted)
			if pos and (pos - position).Magnitude <= radius then return true end
		end
	end
	return false
end

local function twistedNear(position)
	if not OPTIONS.AutoHide then return false end
	local folder = workspace:FindFirstChild("MonsterFolder")
	if not folder then return false end
	local ignore = { folder }
	if player.Character then table.insert(ignore, player.Character) end
	sightParams.FilterDescendantsInstances = ignore
	local eye = position + Vector3.new(0, MACHINE.EyeHeight, 0)
	for _, twisted in ipairs(getTargets(folder)) do
		local excludedFolderEntity = isInsideMachineExcludedFolder(twisted)
		local pos = (not excludedFolderEntity and not MACHINE.Allowed[twisted.Name]) and targetPosition(twisted)
		local flat = pos and Vector3.new(pos.X - position.X, 0, pos.Z - position.Z).Magnitude
		if flat and flat <= MACHINE.Range then
			if not OPTIONS.LineOfSight or not workspace:Raycast(eye, pos - eye, sightParams) then
				return true, twisted.Name, flat
			end
		end
	end
	return false
end

-- Chase state shared with pickup workers.

task.spawn(function()
	local remotes = game:GetService("ReplicatedStorage"):WaitForChild("Remotes", 10)
	local event = remotes and remotes:WaitForChild("Chase", 10)
	if alive and event and event:IsA("RemoteEvent") then
		track(event.OnClientEvent:Connect(function(...)
			for _, arg in ipairs({ ... }) do
				if arg == "Started" and OPTIONS.AutoHide then
					increment("chases")
					debugEvent("DANGER", "chase_started", { autoHide = OPTIONS.AutoHide }, "WARN")
					chase.pending = true
					chase.holdUntil = math.max(chase.holdUntil, os.clock() + MACHINE.ChaseHold)
					motionPauseUntil = math.max(motionPauseUntil, chase.holdUntil)
					cancelMotion()
				end
			end
		end))
	end
end)

local function getPlayerRoot()
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart")
end

local function getProgress(machine)
	local value = machine:FindFirstChild("ComputerPercentage") or machine:FindFirstChild("OilValue")
	if value and (value:IsA("NumberValue") or value:IsA("IntValue")) then return value.Value end
	return nil
end

local function isComplete(machine)
	local progress = getProgress(machine)
	return progress ~= nil and progress >= MACHINE.DoneValue
end

local function getBigMachines()
	local list = {}
	for _, name in ipairs({ "Machine", "Computer" }) do
		local big = resolveWorkspacePath("Map.SpecialFolder.BigMachine." .. name)
		if big and not isInsideMachineExcludedFolder(big) then table.insert(list, big) end
	end
	return list
end

local function nearestIncomplete(list)
	local root = getPlayerRoot()
	local best, bestDistance, anyIncomplete = nil, nil, false
	for _, machine in ipairs(list) do
		if not isComplete(machine) then
			anyIncomplete = true
			local prompt = getPrompt(machine)
			local pos = prompt and prompt.Enabled and targetPosition(machine)
			if pos then
				local distance = root and (root.Position - pos).Magnitude or 0
				if not bestDistance or distance < bestDistance then best, bestDistance = machine, distance end
			end
		end
	end
	return best, anyIncomplete
end

local function pickMachine()
	local normals = getMachines()
	local best, anyIncomplete = nearestIncomplete(normals)
	if best then return best, "work" end
	if anyIncomplete then return nil, "wait" end
	local bigs = getBigMachines()
	best, anyIncomplete = nearestIncomplete(bigs)
	if best then return best, "work" end
	if anyIncomplete then return nil, "wait" end
	return nil, (#normals + #bigs > 0) and "done" or "none"
end

local function isLiveMachineObjective(target)
	if not target or not target:IsDescendantOf(workspace) then return false end
	for _, machine in ipairs(getMachines()) do if machine == target then return true end end
	for _, machine in ipairs(getBigMachines()) do if machine == target then return true end end
	return false
end

local function effectivelyVisible(obj)
	local current = obj
	while current and current ~= playerGui do
		if current:IsA("GuiObject") then
			if not current.Visible then return false end
		elseif current:IsA("ScreenGui") then
			if not current.Enabled then return false end
		end
		current = current.Parent
	end
	return current == playerGui
end

local autoSkillcheck

local skillcheckMovedAt = 0
local lastDial, lastBar

local function skillcheckVisible()
	local round = playerGui:FindFirstChild("RoundSkillcheck")
	local container = round and round:FindFirstChild("Container")
	local normal = container and container:FindFirstChild("Normal")
	local lockUI = playerGui:FindFirstChild("LockUI")
	local hud = lockUI and lockUI:FindFirstChild("HUD")
	local skillcheck = hud and hud:FindFirstChild("Skillcheck")
	local main = skillcheck and skillcheck:FindFirstChild("Main")
	local marker = main and main:FindFirstChild("Marker")
	local now = os.clock()
	local visible = false
	if normal and effectivelyVisible(normal) then
		visible = true
		local aim = normal:FindFirstChild("AimImage")
		local rotation = aim and aim.Rotation
		if rotation ~= lastDial then
			lastDial = rotation
			skillcheckMovedAt = now
		end
	end
	if marker and effectivelyVisible(marker) then
		visible = true
		local x = marker.AbsolutePosition.X
		if x ~= lastBar then
			lastBar = x
			skillcheckMovedAt = now
		end
	end
	return visible and now - skillcheckMovedAt < 0.5
end

local skillcheckSince = nil

supervise("skillcheck watch", function()
	return alive
end, function()
	while alive do
		if skillcheckVisible() then
			skillcheckSince = skillcheckSince or os.clock()
		else
			skillcheckSince = nil
		end
		task.wait(0.1)
	end
end)

local function skillcheckActive()
	return skillcheckSince ~= nil and os.clock() - skillcheckSince < MACHINE.SkillcheckStale
end

local function leaveObjective()
	if skillcheckActive() then
		warn("[TU - Rava Hub] leave skipped: skillcheck active")
		debugLog("leave skipped: skillcheck active")
		return
	end
	debugLog("leave invoked")
	local done = false
	task.spawn(function()
		local ok, err = pcall(function()
			local remotes = game:GetService("ReplicatedStorage"):FindFirstChild("Remotes")
			local event = remotes and remotes:FindFirstChild("SkillCheck")
			if not event then error("SkillCheck remote not found") end
			event:InvokeServer("Leave")
		end)
		if not ok then
			warn("[TU - Rava Hub] leave failed: " .. tostring(err))
			debugLog("leave failed: " .. tostring(err))
		end
		done = true
	end)
	local deadline = os.clock() + 0.12
	while not done and os.clock() < deadline do task.wait() end
end

local doneAt, doneValue = 0, false
machinesDone = function()
	local now = os.clock()
	if now - doneAt >= 0.5 then
		doneAt = now
		local _, status = pickMachine()
		doneValue = status == "done"
	end
	return doneValue
end

local function isBigMachine(machine)
	for _, big in ipairs(getBigMachines()) do if big == machine then return true end end
	return false
end

local function safeAlternative(current)
	if current and isBigMachine(current) then return nil end
	local root = getPlayerRoot()
	local best, bestDistance
	for _, machine in ipairs(getMachines()) do
		if machine ~= current and not isComplete(machine) then
			local prompt = getPrompt(machine)
			local part = prompt and prompt.Enabled and getPromptPart(prompt, machine)
			if part and not twistedNear(part.Position) then
				local distance = root and (root.Position - part.Position).Magnitude or 0
				if not bestDistance or distance < bestDistance then best, bestDistance = machine, distance end
			end
		end
	end
	return best
end

-- Machine automation
local function newMachineAutofarm()
	local farm = { enabled = false, target = nil }
	local runId = 0
	local elevatorPreference = 1
	local pickupsAt, pickupsValue = 0, false
	local function cachedPickups()
		local now = os.clock()
		if now - pickupsAt >= 0.25 then
			pickupsAt = now
			pickupsValue = pickupsRemaining()
		end
		return pickupsValue
	end
	local function move(position, keepGoing, mode)
		farm.moving = true
		local arrived = teleportCharacter(CFrame.new(position), keepGoing, "machine", mode)
		farm.moving = false
		return arrived
	end
	local function goElevator(advancePreference, keepGoing)
		keepGoing = keepGoing or function() return alive and farm.enabled end
		local paths = elevatorPreference == 1
			and { MACHINE.Elevator, MACHINE.ElevatorFallback }
			or { MACHINE.ElevatorFallback, MACHINE.Elevator }
		for _, path in ipairs(paths) do
			local elevator = resolveWorkspacePath(path)
			local spot = elevator and targetPosition(elevator)
			if spot then
				local arrived = move(spot + Vector3.new(0, MACHINE.ElevatorHeight, 0), keepGoing, "emergency")
				if arrived and advancePreference then
					elevatorPreference = elevatorPreference == 1 and 2 or 1
				end
				return arrived
			end
		end
		return false
	end
	local function finishAtElevator(active)
		local elevator = resolveWorkspacePath(MACHINE.ElevatorFallback)
		local spot = elevator and targetPosition(elevator)
		if spot and not move(spot + Vector3.new(0, MACHINE.ElevatorHeight, 0), active, "emergency") then return end
		local deadline = os.clock() + 5
		while active() and os.clock() < deadline do
			if not resolveWorkspacePath(MACHINE.Elevator) then return end
			task.wait(0.1)
		end
		if active() then
			local exitElevator = resolveWorkspacePath(MACHINE.Elevator)
			local exitSpot = exitElevator and targetPosition(exitElevator)
			if exitSpot then move(exitSpot + Vector3.new(0, MACHINE.ElevatorHeight, 0), active, "emergency") end
		end
	end
	local function checkFuseboxes(active)
		for _, path in ipairs(MACHINE.Fuseboxes) do
			if not active() then return end
			local prompt = resolveWorkspacePath(path)
			local part = prompt and prompt:IsA("ProximityPrompt") and getPromptPart(prompt, prompt.Parent)
			debugEvent("FUSE", "located", { path = path, found = part ~= nil, enabled = part and prompt.Enabled or false })
			if part and prompt.Enabled then
				increment("fuseAttempts")
				if not move(part.Position + Vector3.new(0, MACHINE.Height, 0), active) then return end
				task.wait(MACHINE.Settle)
				if OPTIONS.PromptDelay then task.wait(PROMPT_DELAY) end
				local deadline = os.clock() + MACHINE.FuseDwell
				while active() and os.clock() < deadline and prompt.Parent and prompt.Enabled do
					triggerPrompt(prompt)
					task.wait(MACHINE.PromptRetry)
				end
				debugEvent("FUSE", "result", { path = path, promptEnabled = prompt.Enabled,
					elapsed = string.format("%.2f", MACHINE.FuseDwell) })
			end
		end
	end
	local function loop(myId)
		local function active() return alive and farm.enabled and runId == myId end
		local hidden = false
		local lastFire = 0
		local fireAfter = 0
		local placedAt = 0
		local logProgress = false
		local logFire = false
		local loggedTarget = nil
		local usedItem = false
		local lastPrompt = nil
		local lastProgress = nil
		local lastMachineRescan = 0
		local finished = false
		local activated, lockedOn = false, false
		local lastProgressAt = os.clock()
		local checkingSince
		local clearSince = nil
		local waitStart = nil
		local lastBusyAt = os.clock()
		local collectStart = nil
		local emergencyNextMove = false
		farm.placed = false
		while active() do
			local root = getPlayerRoot()
			local moved = false
			if chase.pending then
				chase.pending = false
				chase.holdUntil = os.clock() + MACHINE.ChaseHold
				debugLog("chase started: hiding")
				local currentPrompt = farm.target and getPrompt(farm.target)
				if currentPrompt then cancelMachinePromptHold(currentPrompt) end
				farm.placed = false
				lastFire = 0
				lastPrompt = nil
				lastProgress = nil
				usedItem = false
				if root then
					leaveObjective()
					hidden = goElevator(false, active)
				else
					hidden = false
				end
			end
			local busy = pickupBusy()
			if busy then lastBusyAt = os.clock() end
			local waitingPickups = busy or (cachedPickups() and os.clock() - lastBusyAt < MACHINE.ItemIdle)
			local pending = OPTIONS.ItemsFirst and not OPTIONS.CollectLast and waitingPickups
			if pending and not farm.placed then
				if not waitStart then
					waitStart = os.clock()
					debugLog("waiting for pickups before machines")
				end
			else
				waitStart = nil
			end
			if not farm.placed and pending and os.clock() - waitStart < MACHINE.ItemWaitMax then
				local currentPrompt = farm.target and getPrompt(farm.target)
				if currentPrompt then cancelMachinePromptHold(currentPrompt) end
				hidden, farm.placed = false, false
				lastFire = 0
				lastPrompt = nil
				usedItem = false
			elseif root then
				local target = farm.target
				local status = "work"
				local now = os.clock()
				if now - lastMachineRescan >= MACHINE.RescanInterval then
					lastMachineRescan = now
					local scannedTarget, scannedStatus = pickMachine()
					local currentPrompt = target and getPrompt(target)
					local currentUsable = target
						and isLiveMachineObjective(target)
						and not isComplete(target)
						and currentPrompt ~= nil
						and (currentPrompt.Enabled
							or (farm.placed and now - lastProgressAt <= MACHINE.UseTimeout))
					if not currentUsable then
						target = scannedTarget
						farm.placed = false
						lastFire = 0
						lastPrompt = nil
						lastProgress = target and getProgress(target) or nil
						usedItem = false
						status = scannedStatus
					elseif not target then
						target = scannedTarget
						status = scannedStatus
					end
				end
				if target and (not target:IsDescendantOf(workspace) or isComplete(target)) then
					if isComplete(target) then
						increment("machineCompletions")
						debugEvent("MACHINE", "completed", { name = target.Name, progress = tostring(getProgress(target)) })
					else
						debugEvent("MACHINE", "target_removed", { name = target.Name }, "WARN")
					end
					target, farm.placed = nil, false
					lastFire = 0
					lastPrompt = nil
					lastProgress = nil
					usedItem = false
				end
				if not target then target, status = pickMachine() end
				farm.target = target
				if target ~= loggedTarget then
					loggedTarget = target
					debugStatus.currentTarget = target and target.Name or "None"
					increment("machineTargetChanges")
					debugEvent("MACHINE", "target_changed", { name = target and target.Name or "none", status = status })
				end
				local prompt = target and getPrompt(target)
				local part = prompt and getPromptPart(prompt, target)
				if part then
					finished = false
					local danger, dangerName, dangerDist = twistedNear(part.Position)
					if danger then
						clearSince = nil
					elseif not clearSince then
						clearSince = os.clock()
					end
					if danger then
						farm.placed = false
						cancelMachinePromptHold(prompt)
						lastFire = 0
						lastPrompt = nil
						lastProgress = getProgress(target)
						usedItem = false
						if not hidden then
							increment("machineDangers")
							debugEvent("DANGER", "machine_threat", { enemy = tostring(dangerName),
								distance = string.format("%.1f", dangerDist or 0), machine = target.Name }, "WARN")
							leaveObjective()
							local alternative = safeAlternative(target)
							if alternative then
								debugLog("switching to " .. alternative.Name)
								farm.target = alternative
								emergencyNextMove = true
							else
								debugLog("hiding at elevator")
								hidden = goElevator(false, active)
							end
						end
					elseif hidden and os.clock() - clearSince < MACHINE.ClearHold then
						farm.placed = false
						cancelMachinePromptHold(prompt)
					elseif os.clock() < chase.holdUntil then
						farm.placed = false
						cancelMachinePromptHold(prompt)
						lastFire = 0
						lastPrompt = nil
						usedItem = false
						if not hidden then hidden = goElevator(false, active) end
					else
						hidden = false
						if farm.placed and prompt.Enabled and (root.Position - part.Position).Magnitude > prompt.MaxActivationDistance then
							farm.placed = false
						end
						if not farm.placed then
							local arrived = move(part.Position + Vector3.new(0, MACHINE.Height, 0), function()
								return active() and not chase.pending and target:IsDescendantOf(workspace)
									and prompt:IsDescendantOf(workspace) and not isComplete(target)
									and not twistedNear(part.Position)
							end, emergencyNextMove and "emergency" or nil)
							if arrived then emergencyNextMove = false end
							if not arrived then
								task.wait(MACHINE.Tick)
								continue
							end
							if not OPTIONS.PromptDelay then triggerMachinePrompt(prompt) end
							task.wait(MACHINE.Settle)
							fireAfter = OPTIONS.PromptDelay and os.clock() + PROMPT_DELAY or 0
							farm.placed = true
							moved = true
							placedAt = os.clock()
							increment("machinePlacements")
							logProgress = true
							logFire = true
							debugLog(string.format("place %s dist=%.1f max=%.1f hold=%.2f enabled=%s progress=%s", target.Name,
								(root.Position - part.Position).Magnitude, prompt.MaxActivationDistance, prompt.HoldDuration, tostring(prompt.Enabled), tostring(getProgress(target))))
							lastFire = 0
							usedItem = false
							lastPrompt = nil
							lastProgress = getProgress(target)
							activated, lockedOn = false, false
							lastProgressAt = os.clock()
							checkingSince = nil
						end
						local progress = getProgress(target)
						local progressAdvanced = progress ~= nil and lastProgress ~= nil
							and progress > lastProgress
						if progress ~= nil then lastProgress = progress end
						if progressAdvanced then
							lastProgressAt = os.clock()
							activated = true
							if logProgress then
								logProgress = false
								debugLog(string.format("progress started %s now=%s after %.2fs", target.Name, tostring(progress), os.clock() - placedAt))
							end
						end
						if prompt ~= lastPrompt then
							lastPrompt = prompt
							lastFire = 0
						end
						if prompt.Enabled then
							if lockedOn then
								activated, lockedOn = false, false
							elseif activated and os.clock() - lastProgressAt > MACHINE.StallTimeout then
								increment("machineStalls")
								debugEvent("MACHINE", "progress_stalled", { name = target.Name,
									progress = tostring(getProgress(target)), seconds = MACHINE.StallTimeout }, "WARN")
								activated = false
								lastProgressAt = os.clock()
							end
						elseif lastFire > 0 then
							activated, lockedOn = true, true
						end
						local checking = autoSkillcheck ~= nil and autoSkillcheck.enabled and skillcheckVisible()
						if checking then
							checkingSince = checkingSince or os.clock()
						else
							checkingSince = nil
						end
						local paused = checking and os.clock() - checkingSince < MACHINE.SkillcheckPause
						if not activated and not paused and not isComplete(target) and prompt.Enabled
							and os.clock() >= fireAfter and os.clock() - lastFire >= MACHINE.PromptRetry then
							lastFire = os.clock()
							if logFire then
								logFire = false
								debugLog(string.format("first fire %s %.2fs after place", target.Name, os.clock() - placedAt))
							end
							triggerMachinePrompt(prompt)
						end
						if progressAdvanced and not usedItem then
							usedItem = true
							if autoUse.enabled then
								task.delay(AUTO_USE.UseDelay, function()
									if active() and autoUse.enabled and farm.target == target
										and farm.placed and not isComplete(target)
										and os.clock() >= chase.holdUntil then
										useForMachine(target)
									end
								end)
							end
						end
					end
				elseif status == "done" then
					local collecting = OPTIONS.CollectLast and waitingPickups
					if collecting then
						if not collectStart then
							collectStart = os.clock()
							debugLog("machines done, waiting for pickups")
						end
					else
						collectStart = nil
					end
					if not finished and not (collecting and os.clock() - collectStart < MACHINE.ItemWaitMax) then
						finished = true
						debugEvent("MACHINE", "all_complete", { autoElevator = OPTIONS.AutoElevator, fuseboxes = OPTIONS.Fuseboxes })
						if OPTIONS.Fuseboxes then checkFuseboxes(active) end
						if OPTIONS.AutoElevator then
							debugLog("emergency teleport to elevator")
							finishAtElevator(active)
						end
					end
					task.wait(0.5)
				end
			end
			task.wait(moved and 0 or MACHINE.Tick)
		end
	end
	function farm.enable()
		if farm.enabled then return end
		farm.enabled = true
		chase.pending = false
		runId += 1
		local myId = runId
		supervise("machine autofarm", function()
			return alive and farm.enabled and runId == myId
		end, function()
			loop(myId)
		end)
	end
	function farm.disable()
		local wasEnabled = farm.enabled
		farm.enabled = false
		runId += 1
		farm.target, farm.placed, farm.moving = nil, false, false
		cancelMotion("machine")
		restoreMachinePrompts()
		if wasEnabled and alive then
			leaveObjective()
			if OPTIONS.AutoElevator then
				goElevator(true, function() return alive and not farm.enabled end)
			end
		end
	end
	table.insert(cleanups, farm.disable)
	return farm
end

local function newRangeView(machineFarm)
	local view = {}
	local circle
	local function clear()
		if circle then
			circle:Destroy()
			circle = nil
		end
	end
	supervise("range view", function()
		return alive
	end, function()
		while alive do
			local target = machineFarm.enabled and machineFarm.target
			local prompt = target and target:IsDescendantOf(workspace) and getPrompt(target)
			local part = prompt and getPromptPart(prompt, target)
			if part then
				if not circle then
					circle = new("Part", {
						Name = "TU_RangeCircle",  Shape = Enum.PartType.Cylinder,  Anchored = true,
						CanCollide = false,  CanQuery = false,  CanTouch = false,
						Material = Enum.Material.Neon,  Color = Color3.fromRGB(255, 60, 60),  Transparency = 0.75,
					}, workspace)
					new("Highlight", {
						Name = "TU_ESP_Highlight",  Adornee = circle,  DepthMode = Enum.HighlightDepthMode.AlwaysOnTop,
						FillColor = Color3.fromRGB(255, 60, 60),  FillTransparency = 0.88,  OutlineTransparency = 0.05,
						OutlineColor = Color3.fromRGB(255, 60, 60),
					}, circle)
				end
				local diameter = MACHINE.Range * 2
				circle.Size = Vector3.new(0.2, diameter, diameter)
				local floorY = (targetFloor(target) or part.Position.Y) - MACHINE.CircleSink
				circle.CFrame = CFrame.new(part.Position.X, floorY, part.Position.Z)
					* CFrame.Angles(0, 0, math.rad(90))
			else
				clear()
			end
			task.wait(0.2)
		end
	end)
	table.insert(cleanups, clear)
	return view
end

local function createInputRow(parent, name, order, apply)
	local row = new("Frame", { Size = UDim2.new(1, -9, 0, 43), BackgroundColor3 = UI.surface,
		BorderSizePixel = 0, LayoutOrder = order }, parent)
	corner(row, 9)
	uiStroke(row)
	uiText(row, name, 14, false, UI.text, {
		Position = UDim2.fromOffset(12, 0), Size = UDim2.new(1, -98, 1, 0),
	})
	local box = new("TextBox", {
		Size = UDim2.fromOffset(69, 28), Position = UDim2.new(1, -80, 0.5, -14),
		BackgroundColor3 = UI.soft, BorderSizePixel = 0, Text = tostring(apply(nil)),
		TextColor3 = UI.text, TextSize = 13, Font = Enum.Font.GothamBold,
		ClearTextOnFocus = false,
	}, row)
	corner(box, 7)
	track(box.FocusLost:Connect(function()
		local input = tonumber(box.Text)
		local previous = tostring(apply(nil))
		local ok, current = pcall(apply, input)
		box.Text = ok and tostring(current) or previous
		debugEvent("UI", "setting_changed", { name = name, requested = tostring(input), result = box.Text },
			ok and "INFO" or "WARN")
	end))
end

local function fireConnections(signal)
	if typeof(getconnections) ~= "function" then return false end
	local ok, conns = pcall(getconnections, signal)
	if not ok or type(conns) ~= "table" or #conns == 0 then return false end
	local fired = false
	for _, c in ipairs(conns) do
		local fine = pcall(function()
			c:Fire()
		end)
		fired = fired or fine
	end
	return fired
end

local BUTTON_SIGNALS = { "MouseButton1Down", "Activated", "MouseButton1Click", "TouchTap" }

local function tapGuiObject(obj)
	return (pcall(function()
		local vim = game:GetService("VirtualInputManager")
		local inset = game:GetService("GuiService"):GetGuiInset()
		local pos = obj.AbsolutePosition + obj.AbsoluteSize / 2 + inset
		vim:SendMouseButtonEvent(pos.X, pos.Y, 0, true, game, 0)
		vim:SendMouseButtonEvent(pos.X, pos.Y, 0, false, game, 0)
	end))
end

local function pressGuiButton(button)
	for _, name in ipairs(BUTTON_SIGNALS) do
		local ok, signal = pcall(function()
			return button[name]
		end)
		if ok and signal and fireConnections(signal) then return true end
	end
	return tapGuiObject(button)
end

local function normRot(r) return (r + 180) % 360 - 180 end

-- Automated skillchecks
local function newAutoSkillcheck()
	local feature = { enabled = false }
	local runId = 0
	local beats = {} -- Dictionary of currently connected Heartbeats only.
	local function canAutoClick() return alive and feature.enabled end
	local function active(myId) return alive and feature.enabled and runId == myId end
	local function stop()
		for c in pairs(beats) do c:Disconnect() end
		table.clear(beats)
	end
	local function waitPath(root, names, myId)
		local current = root
		for _, name in ipairs(names) do
			local found = current:FindFirstChild(name)
			while not found do
				if not active(myId) then return nil end
				task.wait(0.25)
				found = current:FindFirstChild(name)
			end
			current = found
		end
		return current
	end
	local function watchRound(myId)
		while active(myId) do
			local normal = waitPath(playerGui, { "RoundSkillcheck", "Container", "Normal" }, myId)
			local aimImage = normal and waitPath(normal, { "AimImage" }, myId)
			local target = normal and waitPath(normal, { "Target" }, myId)
			local hit = normal and waitPath(normal, { "Hit" }, myId)
			if not (aimImage and target and hit) then return end
			local fired, lastV7, lastVisible = false, nil, effectivelyVisible(normal)
			local beat = RunService.Heartbeat:Connect(function()
				local visible = effectivelyVisible(normal)
				if visible ~= lastVisible then
					if visible then fired, lastV7 = false, nil end
					lastVisible = visible
				end
				if not visible or fired then return end
				local aim = normRot(aimImage.Rotation + 180)
				local zoneStart = normRot(target.Rotation - 30)
				local v7 = math.abs(((aim - zoneStart) + 180) % 360 - 180) / 60
				if lastV7 and lastV7 < 0.44 and v7 >= 0.44 and canAutoClick() then
					fired = true
					increment("skillcheckInputs")
					local sent = pressGuiButton(hit)
					if not sent then increment("skillcheckInputFailures") end
					debugEvent("SKILLCHECK", "dial_input", { dispatched = sent,
						position = string.format("%.3f", v7) }, sent and "INFO" or "WARN")
				end
				lastV7 = v7
			end)
			beats[beat] = true
			while active(myId) and hit:IsDescendantOf(playerGui) do task.wait(0.5) end
			beat:Disconnect()
			beats[beat] = nil
		end
	end
	local function watchLock(myId)
		while active(myId) do
			local main = waitPath(playerGui, { "LockUI", "HUD", "Skillcheck", "Main" }, myId)
			local marker = main and waitPath(main, { "Marker" }, myId)
			local objective = main and waitPath(main, { "Objective" }, myId)
			local button = main and waitPath(main, { "MobileButtonClick" }, myId)
			if not (marker and objective and button) then return end
			local fired, lastDist, lastVisible = false, nil, effectivelyVisible(marker)
			local beat = RunService.Heartbeat:Connect(function()
				local visible = effectivelyVisible(marker)
				if visible ~= lastVisible then
					if visible then fired, lastDist = false, nil end
					lastVisible = visible
				end
				if not visible or fired then return end
				local markerCenter = marker.AbsolutePosition.X + marker.AbsoluteSize.X * 0.5
				local objectiveCenter = objective.AbsolutePosition.X + objective.AbsoluteSize.X * 0.5
				local dist = markerCenter - objectiveCenter
				if lastDist and lastDist < -2 and dist >= -2 and canAutoClick() then
					fired = true
					increment("skillcheckInputs")
					local sent = pressGuiButton(button)
					if not sent then increment("skillcheckInputFailures") end
					debugEvent("SKILLCHECK", "bar_input", { dispatched = sent,
						distance = string.format("%.2f", dist) }, sent and "INFO" or "WARN")
				end
				lastDist = dist
			end)
			beats[beat] = true
			while active(myId) and button:IsDescendantOf(playerGui) do task.wait(0.5) end
			beat:Disconnect()
			beats[beat] = nil
		end
	end
	function feature.enable()
		if feature.enabled then return end
		feature.enabled = true
		runId += 1
		local myId = runId
		supervise("skillcheck dial", function()
			return active(myId)
		end, function()
			watchRound(myId)
		end)
		supervise("skillcheck bar", function()
			return active(myId)
		end, function()
			watchLock(myId)
		end)
	end
	function feature.disable()
		feature.enabled = false
		runId += 1
		stop()
	end
	table.insert(cleanups, feature.disable)
	return feature
end

autoSkillcheck = newAutoSkillcheck()
autoSkillcheck.enable()

machineFarm = newMachineAutofarm()
newRangeView(machineFarm)

local machinesBody = createSection("Machines", 3)
createToggleRow(machinesBody, "Machine Autofarm", 1, machineFarm)
createToggleRow(machinesBody, "Auto Skillcheck", 2, autoSkillcheck)
createToggleRow(machinesBody, "Auto Hide", 3, newOption(OPTIONS, "AutoHide"))
createToggleRow(machinesBody, "Line Of Sight", 4, newOption(OPTIONS, "LineOfSight"))
createToggleRow(machinesBody, "Auto Elevator (Teleport)", 5, newOption(OPTIONS, "AutoElevator"))
createToggleRow(machinesBody, "Fusebox Check", 6, newOption(OPTIONS, "Fuseboxes"))
createToggleRow(machinesBody, "Items First", 7, newOption(OPTIONS, "ItemsFirst"))
createToggleRow(machinesBody, "Prompt Delay (0.5s)", 8, newOption(OPTIONS, "PromptDelay"))
createInputRow(machinesBody, "Range (studs)", 9, function(value)
	if value and value > 0 and value < 2000 then MACHINE.Range = value end
	return MACHINE.Range
end)


-- Diagnostics page: live counters, warning filter, and export on demand.
local diagnosticsPage = createSection("Diagnostics")
local summaryCard = new("Frame", { Size = UDim2.new(1, -9, 0, 106),
	BackgroundColor3 = UI.surface, BorderSizePixel = 0, LayoutOrder = 1 }, diagnosticsPage)
corner(summaryCard, 10)
uiStroke(summaryCard)
local stateLabel = uiText(summaryCard, "RUNNING", 12, true, UI.good, {
	Position = UDim2.fromOffset(13, 10), Size = UDim2.new(1, -25, 0, 21),
})
local statsLabel = uiText(summaryCard, "Collecting diagnostic counters...", 12, false, UI.text, {
	Position = UDim2.fromOffset(13, 35), Size = UDim2.new(1, -25, 0, 55),
	TextYAlignment = Enum.TextYAlignment.Top, TextWrapped = true,
})
local toolsRow = new("Frame", { Size = UDim2.new(1, -9, 0, 42),
	BackgroundTransparency = 1, LayoutOrder = 2 }, diagnosticsPage)
local function actionButton(name, width, x, color)
	local button = new("TextButton", { Text = name, Size = UDim2.fromOffset(width, 36),
		Position = UDim2.fromOffset(x, 3), BackgroundColor3 = color,
		TextColor3 = UI.text, TextSize = 12, Font = Enum.Font.GothamBold,
		BorderSizePixel = 0 }, toolsRow)
	corner(button, 8)
	return button
end
local exportButton = actionButton("EXPORT LOG", 110, 0, UI.accent)
local copyButton = actionButton("COPY LOG", 101, 119, UI.surface2)
local warningButton = actionButton("WARNINGS: OFF", 130, 229, UI.surface2)
local outputStatus = uiText(diagnosticsPage, "Logs are saved when you press Export or Unload.", 11, false, UI.muted,
	{ Size = UDim2.new(1, -9, 0, 22), LayoutOrder = 3 })
local logDisplay = new("TextBox", { Size = UDim2.new(1, -9, 0, 190),
	BackgroundColor3 = Color3.fromRGB(11, 14, 21), BorderSizePixel = 0,
	Text = "No events yet.", TextColor3 = Color3.fromRGB(194, 207, 232),
	TextSize = 11, Font = Enum.Font.Code, TextXAlignment = Enum.TextXAlignment.Left,
	TextYAlignment = Enum.TextYAlignment.Top, TextWrapped = true,
	TextEditable = false, MultiLine = true, ClearTextOnFocus = false,
	LayoutOrder = 4 }, diagnosticsPage)
corner(logDisplay, 9)
local warningsOnly = false
track(warningButton.MouseButton1Click:Connect(function()
	warningsOnly = not warningsOnly
	warningButton.Text = "WARNINGS: " .. (warningsOnly and "ON" or "OFF")
	debugEvent("UI", "diagnostic_filter", { warningsOnly = warningsOnly })
end))

local function debugReport()
	local summary = {
		"TU - Rava Hub | Diagnostic Report",
		"Build=" .. BUILD,
		"Exported=" .. os.date("%Y-%m-%d %H:%M:%S"),
		string.format("SessionSeconds=%.2f PlaceId=%s JobId=%s",
			os.clock() - debugStart, tostring(game.PlaceId), tostring(game.JobId)),
		"Mode=teleport-only",
		string.format("Client touch=%s promptFire=%s virtualInput=%s clipboard=%s writefile=%s",
			tostring(UserInputService.TouchEnabled), tostring(hasFirePrompt),
			tostring(pcall(function() return game:GetService("VirtualInputManager") end)),
			tostring(typeof(setclipboard) == "function"), tostring(typeof(writefile) == "function")),
		"Stats: " .. fieldString(debugStats),
		"Status: " .. fieldString(debugStatus),
		"Options: " .. fieldString(OPTIONS),
		"FARM: " .. fieldString(FARM),
		"MACHINE: " .. fieldString({ Range = MACHINE.Range, StallTimeout = MACHINE.StallTimeout,
			UseTimeout = MACHINE.UseTimeout, ChaseHold = MACHINE.ChaseHold }),
		"Enabled: " .. fieldString({ capsules = capsuleFarm.enabled, items = itemFarm.enabled,
			candy = candyFarm.enabled, machine = machineFarm.enabled,
			skillchecks = autoSkillcheck.enabled, autoUse = autoUse.enabled }),
		string.format("LogEvents=%d Retained=%d Dropped=%d", debugIndex,
			math.min(debugIndex, LOG_LIMIT), math.max(0, debugIndex - LOG_LIMIT)),
		"---- EVENTS (chronological) ----",
	}
	for _, line in ipairs(allDebugLines()) do table.insert(summary, line) end
	return table.concat(summary, "\n")
end
local function writeDebugFile()
	if typeof(writefile) ~= "function" then
		debugEvent("DEBUG", "export_failed", { reason = "writefile unavailable" }, "WARN")
		outputStatus.Text = "Export unavailable. Try Copy Log instead."
		return false
	end
	local filename = "TU_Rava_Hub_Debug_" .. os.time() .. ".txt"
	local ok, err = pcall(writefile, filename, debugReport())
	if ok then
		outputStatus.Text = "Saved: " .. filename
		debugEvent("DEBUG", "export_success", { filename = filename })
		return true
	end
	outputStatus.Text = "Export failed: " .. tostring(err):sub(1, 70)
	debugEvent("DEBUG", "export_failed", { error = err }, "ERROR")
	return false
end
track(exportButton.MouseButton1Click:Connect(writeDebugFile))
track(copyButton.MouseButton1Click:Connect(function()
	if typeof(setclipboard) ~= "function" then
		outputStatus.Text = "Clipboard unavailable in this executor."
		debugEvent("DEBUG", "copy_unavailable", nil, "WARN")
		return
	end
	local ok, err = pcall(setclipboard, debugReport())
	outputStatus.Text = ok and "Diagnostic report copied." or "Copy failed: " .. tostring(err):sub(1, 60)
	debugEvent("DEBUG", ok and "copy_success" or "copy_failed", { error = not ok and err or "none" },
		ok and "INFO" or "ERROR")
end))
supervise("diagnostic UI", function() return alive end, function()
	while alive do
		local working = (machineFarm.enabled and "MACHINE") or (pickupBusy() and "PICKUPS") or "IDLE"
		headerStatus.Text = working .. "  •  TP MODE"
		headerStatus.TextColor3 = working == "IDLE" and UI.muted or UI.good
		footerLabel.Text = string.format("%s   •   %d teleports   •   %d events", BUILD, debugStats.teleports, debugIndex)
		if activeTab == "Diagnostics" and main.Visible then
			stateLabel.Text = "Current target: " .. debugStatus.currentTarget
			statsLabel.Text = string.format("Teleports %d  |  TP failures %d  |  Unsafe destinations %d\nPickups %d/%d confirmed  |  Prompts failed %d\nMachines %d completed / %d placed  |  Stalls %d  |  Errors %d",
				debugStats.teleports, debugStats.teleportFailures, debugStats.unsafeDestinations,
				debugStats.pickupConfirmed, debugStats.pickupAttempts, debugStats.promptFailures,
				debugStats.machineCompletions, debugStats.machinePlacements,
				debugStats.machineStalls, debugStats.workerErrors)
			local logs = recentDebugLines(11, warningsOnly)
			logDisplay.Text = #logs > 0 and table.concat(logs, "\n") or "No matching events yet."
		end
		task.wait(0.7)
	end
end)
debugEvent("SYSTEM", "initialized", { build = BUILD, place = game.PlaceId, mode = "teleport" })
-- World structure watcher reports renamed/missing objective folders without log spam.
task.spawn(function()
	local previous = {}
	while alive do
		for _, folderName in ipairs({ "Items", "Capsules", "Candies", "Computers", "OilMachines", "MonsterFolder" }) do
			local folder = workspace:FindFirstChild(folderName)
			local present = folder ~= nil
			if previous[folderName] ~= present then
				debugEvent("WORLD", present and "folder_found" or "folder_missing",
					{ name = folderName, children = folder and #folder:GetChildren() or 0 },
					present and "INFO" or "WARN")
				previous[folderName] = present
			end
		end
		task.wait(5)
	end
end)

local unloaded = false
local function unload()
	if unloaded then return end
	unloaded = true
	alive = false
	cancelMotion()
	_G.TURavaHubUnload = nil
	for _, cleanup in ipairs(cleanups) do pcall(cleanup) end
	table.clear(cleanups)
	debugEvent("SYSTEM", "unload", { elapsed = string.format("%.2f", os.clock() - debugStart) })
	writeDebugFile()
	for _, connection in ipairs(connections) do connection:Disconnect() end
	table.clear(connections)
	screenGui:Destroy()
	sweepHighlights()
	pcall(function()
		script.Enabled = false
	end)
end

_G.TURavaHubUnload = unload
track(unloadButton.MouseButton1Click:Connect(unload))
