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

local debugLines = {}
local debugStart = os.clock()

local function debugLog(message)
	if #debugLines >= 3000 then table.remove(debugLines, 1) end
	table.insert(debugLines, string.format("[%8.2f] %s", os.clock() - debugStart, message))
end

-- Shared, teleport-only travel controller. Emergency escapes override routine moves.
local TRAVEL = { DangerRadius = 15, ArrivalTolerance = 4 }
local activeMotion
local infectedNear
local motionPauseUntil = 0
local function cancelMotion(owner)
	if activeMotion and (not owner or owner == activeMotion) then activeMotion = nil end
end
local function teleportCharacter(destination, keepGoing, owner, mode)
	local emergency = mode == "emergency"
	if not alive or not keepGoing() then return false end
	if activeMotion and not emergency then return false end
	if emergency then
		cancelMotion()
		motionPauseUntil = math.max(motionPauseUntil, os.clock() + 1.5)
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsDescendantOf(workspace) then return false end
	local from = root.Position
	local distance = (from - destination.Position).Magnitude
	if distance <= 0.25 then return true end
	if not emergency and infectedNear and infectedNear(destination.Position, TRAVEL.DangerRadius) then
		debugLog("MOVE unsafe destination owner=" .. tostring(owner))
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
		debugLog("ERROR MOVE teleport owner=" .. tostring(owner) .. " reason=" .. tostring(err))
		return false
	end
	local drift = (root.Position - destination.Position).Magnitude
	if drift > TRAVEL.ArrivalTolerance then
		debugLog(string.format("MOVE failed owner=%s drift=%.1f", owner, drift))
		return false
	end
	debugLog(string.format("MOVE teleport owner=%s mode=%s dist=%.1f from=(%.1f,%.1f,%.1f) to=(%.1f,%.1f,%.1f)",
		tostring(owner), emergency and "emergency" or "routine", distance,
		from.X, from.Y, from.Z, destination.Position.X, destination.Position.Y, destination.Position.Z))
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
			debugLog("ERROR " .. label .. ": " .. tostring(err))
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

local screenGui = new("ScreenGui", {
	Name = "TURavaHubGUI",  ResetOnSpawn = false,  DisplayOrder = 2147483647,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, playerGui)

local main = new("Frame", {
	Size = UDim2.fromOffset(420, 320),  Position = UDim2.new(0.5, -210, 0.5, -160),
	BackgroundColor3 = Color3.fromRGB(28, 28, 34),  BorderSizePixel = 0,  Active = true,
}, screenGui)
corner(main, 10)

local title = new("TextLabel", {
	Size = UDim2.new(1, 0, 0, 40),  BackgroundColor3 = Color3.fromRGB(40, 40, 50),  BorderSizePixel = 0,
	Text = "TU - Rava Hub",  TextColor3 = Color3.new(1, 1, 1),  TextSize = 20,
	Font = Enum.Font.GothamBold,
}, main)
corner(title, 10)

local content = new("ScrollingFrame", {
	Size = UDim2.new(1, -20, 1, -110),  Position = UDim2.fromOffset(10, 50),  BackgroundTransparency = 1,
	BorderSizePixel = 0,  ScrollBarThickness = 4,  CanvasSize = UDim2.new(),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
}, main)
list(content, 6)

local unloadButton = new("TextButton", {
	Size = UDim2.new(1, -20, 0, 36),  Position = UDim2.new(0, 10, 1, -46),
	BackgroundColor3 = Color3.fromRGB(190, 55, 55),  BorderSizePixel = 0,  Text = "UNLOAD",
	TextColor3 = Color3.new(1, 1, 1),  TextSize = 18,  Font = Enum.Font.GothamBold,
}, main)
corner(unloadButton, 8)

do
	local dragging, dragStart, startPos
	local function isPress(input)
		return input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
	end
	track(title.InputBegan:Connect(function(input)
		if isPress(input) then dragging, dragStart, startPos = true, input.Position, main.Position end
	end))
	track(UserInputService.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch) then
			local d = input.Position - dragStart
			main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
		end
	end))
	track(UserInputService.InputEnded:Connect(function(input)
		if isPress(input) then dragging = false end
	end))
end

do
	local function isPressInput(input)
		return input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
	end
	local iconColor = Color3.fromRGB(217, 119, 87)
	local toggleButton = new("TextButton", {
		Name = "TUToggleIcon",  Size = UDim2.fromOffset(44, 44),  Position = UDim2.new(0, 14, 0.5, -22),
		BackgroundColor3 = Color3.new(0, 0, 0),  BorderSizePixel = 0,  AutoButtonColor = false,
		Text = "",  ZIndex = 10,
	}, screenGui)
	corner(toggleButton, 22)
	new("UIStroke", { Color = Color3.new(1, 1, 1), Thickness = 2 }, toggleButton)
	for i = 0, 5 do
		local bar = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),  Position = UDim2.fromScale(0.5, 0.5),  Size = UDim2.fromOffset(4, 26),
			BackgroundColor3 = iconColor,  BorderSizePixel = 0,  Rotation = i * 30,
			ZIndex = 11,
		}, toggleButton)
		corner(bar, 2)
	end
	local dragging, moved, dragStart, startPos
	track(toggleButton.InputBegan:Connect(function(input)
		if isPressInput(input) then
			dragging, moved, dragStart, startPos = true, false, input.Position, toggleButton.Position
		end
	end))
	track(UserInputService.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch) then
			local d = input.Position - dragStart
			if d.Magnitude > 6 then moved = true end
			if moved then
				toggleButton.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
			end
		end
	end))
	track(UserInputService.InputEnded:Connect(function(input)
		if dragging and isPressInput(input) then
			dragging = false
			if not moved then main.Visible = not main.Visible end
		end
	end))
end

local function createSection(name, order)
	local section = new("Frame", {
		Size = UDim2.new(1, -8, 0, 0),  AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = Color3.fromRGB(34, 34, 42),  BorderSizePixel = 0,  LayoutOrder = order,
	}, content)
	corner(section, 8)
	list(section, 6)
	local header = new("TextButton", {
		Size = UDim2.new(1, 0, 0, 32),  BackgroundColor3 = Color3.fromRGB(55, 55, 70),  BorderSizePixel = 0,
		TextColor3 = Color3.new(1, 1, 1),  TextSize = 16,  Font = Enum.Font.GothamBold,
		TextXAlignment = Enum.TextXAlignment.Left,  LayoutOrder = 0,
	}, section)
	corner(header, 8)
	new("UIPadding", { PaddingLeft = UDim.new(0, 12) }, header)
	local body = new("Frame", {
		Size = UDim2.new(1, 0, 0, 0),  AutomaticSize = Enum.AutomaticSize.Y,  BackgroundTransparency = 1,
		LayoutOrder = 1,
	}, section)
	list(body, 6, Enum.HorizontalAlignment.Center)
	new("UIPadding", {
		PaddingBottom = UDim.new(0, 6),  PaddingLeft = UDim.new(0, 6),  PaddingRight = UDim.new(0, 6),
	}, body)
	local open = true
	local function refresh()
		body.Visible = open
		header.Text = (open and "[-]  " or "[+]  ") .. name
	end
	refresh()
	track(header.MouseButton1Click:Connect(function()
		open = not open
		refresh()
	end))
	return body
end

local function createToggleRow(parent, name, order, feature)
	local row = new("Frame", {
		Size = UDim2.new(1, 0, 0, 34),  BackgroundColor3 = Color3.fromRGB(44, 44, 56),  BorderSizePixel = 0,
		LayoutOrder = order,
	}, parent)
	corner(row, 8)
	new("TextLabel", {
		BackgroundTransparency = 1,  Size = UDim2.new(1, -90, 1, 0),  Position = UDim2.fromOffset(12, 0),
		Text = name,  TextColor3 = Color3.fromRGB(235, 235, 240),  TextSize = 16,
		Font = Enum.Font.GothamMedium,  TextXAlignment = Enum.TextXAlignment.Left,
	}, row)
	local button = new("TextButton", {
		Size = UDim2.fromOffset(64, 24),  Position = UDim2.new(1, -74, 0.5, -12),  BorderSizePixel = 0,
		TextSize = 14,  Font = Enum.Font.GothamBold,  TextColor3 = Color3.new(1, 1, 1),
	}, row)
	corner(button, 6)
	local function refresh()
		button.Text = feature.enabled and "ON" or "OFF"
		button.BackgroundColor3 = feature.enabled and Color3.fromRGB(50, 160, 80) or Color3.fromRGB(90, 90, 100)
	end
	refresh()
	track(button.MouseButton1Click:Connect(function()
		if feature.enabled then
			feature.disable()
		else
			feature.enable()
		end
		refresh()
	end))
end

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
	if not prompt or not prompt:IsA("ProximityPrompt") or not prompt:IsDescendantOf(workspace) then return false end
	if hasFirePrompt then
		local ok = pcall(fireproximityprompt, prompt)
		if ok then return true end
	end
	local began = pcall(function()
		prompt:InputHoldBegin()
	end)
	if not began then return false end
	task.wait(math.max(0, prompt.HoldDuration) + 0.05)
	pcall(function()
		prompt:InputHoldEnd()
	end)
	return true
end

local machinePromptHolds = setmetatable({}, { __mode = "k" })
local modifiedMachinePrompts = setmetatable({}, { __mode = "k" })

local function triggerMachinePrompt(prompt)
	if not prompt or not prompt:IsA("ProximityPrompt") or not prompt:IsDescendantOf(workspace) or not prompt.Enabled then
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
	if not ok then return false end
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
						if part and not unsafe and pickupCoordinator.owner == nil then
							-- This claim has no yield, so other workers cannot claim this action.
							pickupCoordinator.owner = farm
							pickupCoordinator.lastActivity = os.clock()
							pickupCoordinator.home = pickupCoordinator.home or root.CFrame
							didWork = true
							farm.working = true
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
								recent[target] = os.clock()
							else
								recent[target] = os.clock() - FARM.Revisit + FARM.FailedRetry
							end
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

local function pressSlot(slot)
	local ok = pcall(function()
		local vim = game:GetService("VirtualInputManager")
		vim:SendKeyEvent(true, SLOT_KEYS[slot], false, game)
		task.wait(0.05)
		vim:SendKeyEvent(false, SLOT_KEYS[slot], false, game)
	end)
	if not ok and typeof(keypress) == "function" and typeof(keyrelease) == "function" then
		pcall(function()
			keypress(0x30 + slot)
			task.wait(0.05)
			keyrelease(0x30 + slot)
		end)
	end
end

local function useForMachine(machine)
	local names = (machine:FindFirstChild("OilValue") and USE_ITEMS.Oil)
		or (machine:FindFirstChild("ComputerPercentage") and USE_ITEMS.Computer)
	local slot = names and findSlot(names)
	if slot then pressSlot(slot) end
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
					pressSlot(slot)
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
			debugLog("fusebox " .. path .. " found=" .. tostring(part ~= nil) .. " enabled=" .. tostring(part and prompt.Enabled))
			if part and prompt.Enabled then
				if not move(part.Position + Vector3.new(0, MACHINE.Height, 0), active) then return end
				task.wait(MACHINE.Settle)
				if OPTIONS.PromptDelay then task.wait(PROMPT_DELAY) end
				local deadline = os.clock() + MACHINE.FuseDwell
				while active() and os.clock() < deadline and prompt.Parent and prompt.Enabled do
					triggerPrompt(prompt)
					task.wait(MACHINE.PromptRetry)
				end
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
					debugLog("target " .. (target and target.Name or "none") .. " status=" .. status)
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
							debugLog(string.format("danger: %s at %.1f studs near %s", tostring(dangerName), dangerDist or 0, target.Name))
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
						debugLog("all machines done")
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
	local row = new("Frame", {
		Size = UDim2.new(1, 0, 0, 34),  BackgroundColor3 = Color3.fromRGB(44, 44, 56),  BorderSizePixel = 0,
		LayoutOrder = order,
	}, parent)
	corner(row, 8)
	new("TextLabel", {
		BackgroundTransparency = 1,  Size = UDim2.new(1, -90, 1, 0),  Position = UDim2.fromOffset(12, 0),
		Text = name,  TextColor3 = Color3.fromRGB(235, 235, 240),  TextSize = 16,
		Font = Enum.Font.GothamMedium,  TextXAlignment = Enum.TextXAlignment.Left,
	}, row)
	local box = new("TextBox", {
		Size = UDim2.fromOffset(64, 24),  Position = UDim2.new(1, -74, 0.5, -12),
		BackgroundColor3 = Color3.fromRGB(70, 70, 85),  BorderSizePixel = 0,  Text = tostring(apply(nil)),
		TextColor3 = Color3.new(1, 1, 1),  TextSize = 14,  Font = Enum.Font.GothamBold,
		ClearTextOnFocus = false,
	}, row)
	corner(box, 6)
	track(box.FocusLost:Connect(function()
		box.Text = tostring(apply(tonumber(box.Text)))
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
					pressGuiButton(hit)
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
					pressGuiButton(button)
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

-- Debugging and teardown
local function writeDebugFile()
	if typeof(writefile) ~= "function" then
		warn("[TU - Rava Hub] writefile is not available, no debug file written")
		return
	end
	local out = {
		"TU - Rava Hub debug log",
		os.date("%Y-%m-%d %H:%M:%S"),
		string.format("PlaceId %s JobId %s", tostring(game.PlaceId), tostring(game.JobId)),
		string.format("touch=%s fireproximityprompt=%s range=%s movement=teleport",
			tostring(UserInputService.TouchEnabled), tostring(hasFirePrompt), tostring(MACHINE.Range)),
	}
	local keys = {}
	for key in pairs(OPTIONS) do table.insert(keys, key) end
	table.sort(keys)
	local parts = {}
	for _, key in ipairs(keys) do table.insert(parts, key .. "=" .. tostring(OPTIONS[key])) end
	table.insert(out, "options: " .. table.concat(parts, " "))
	keys, parts = {}, {}
	for key in pairs(FARM) do table.insert(keys, key) end
	table.sort(keys)
	for _, key in ipairs(keys) do table.insert(parts, key .. "=" .. tostring(FARM[key])) end
	table.insert(out, "farm: " .. table.concat(parts, " "))
	table.insert(out, "lines: " .. #debugLines)
	table.insert(out, "")
	for _, line in ipairs(debugLines) do table.insert(out, line) end
	local name = "TU_Rava_Hub_Debug_" .. os.time() .. ".txt"
	local ok, err = pcall(writefile, name, table.concat(out, "\n"))
	if ok then
		warn("[TU - Rava Hub] debug file written: " .. name)
	else
		warn("[TU - Rava Hub] debug file failed: " .. tostring(err))
	end
end

local unloaded = false
local function unload()
	if unloaded then return end
	unloaded = true
	alive = false
	cancelMotion()
	_G.TURavaHubUnload = nil
	for _, cleanup in ipairs(cleanups) do pcall(cleanup) end
	table.clear(cleanups)
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