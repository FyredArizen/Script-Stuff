local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
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

local UNLOAD = { gui = nil, handler = nil, active = false, exporter = nil,
	restoreLOS = function() end, restoreRendering = function() end,
	cancelMovement = function() end, render3d = { enabled = false }, fullDiagnostics = false }
function UNLOAD.force(source)
	if UNLOAD.active then return end
	UNLOAD.active = true
	alive = false -- Every supervised worker sees cancellation immediately.
	_G.TURavaHubUnload = nil
	pcall(UNLOAD.cancelMovement)
	pcall(UNLOAD.restoreRendering)
	if UNLOAD.gui then
		pcall(function() UNLOAD.gui.Enabled = false end)
		pcall(function() UNLOAD.gui:Destroy() end)
	end
	for _, connection in ipairs(connections) do
		pcall(function() connection:Disconnect() end)
	end
	table.clear(connections)
	for _, cleanup in ipairs(cleanups) do
		local ok, err = pcall(cleanup)
		if not ok then warn("[TU - Rava Hub] cleanup error: " .. tostring(err)) end
	end
	table.clear(cleanups)
	pcall(UNLOAD.restoreLOS)
	task.spawn(function()
		pcall(function() if UNLOAD.exporter then UNLOAD.exporter() end end)
		pcall(sweepHighlights)
	end)
end
function UNLOAD.request(source)
	if UNLOAD.active then return end
	if UNLOAD.handler then
		local ok, err = pcall(UNLOAD.handler, source or "requested")
		if ok then return end
		warn("[TU - Rava Hub] unload handler failed; forcing shutdown: " .. tostring(err))
	end
	UNLOAD.force(source or "fallback")
end

local OPTIONS = {
	AutoHide = true,  AutoElevator = true,
	Fuseboxes = true,  ItemsFirst = true,
	CollectLast = true,
	MovementMode = "Teleport", TweenDepth = -15, Disable3DRendering = false,
}

local BUILD = "2.6.7 Flood Loop Guard"
local debugStart = os.clock()
local LOG_LIMIT = 4000
local debugLines, debugIndex, debugLast = {}, 0, {}
local debugStats = {
	teleports = 0, teleportFailures = 0, unsafeDestinations = 0,
	renderToggles = 0, renderErrors = 0,
	pickupTweens = 0, pickupTweenAborts = 0, pickupTweenDetours = 0,
	underMapTweens = 0, underMapAborts = 0, underMapHealthStops = 0, underMapGuardBlocks = 0,
	pickupPreemptions = 0, pickupRouteCooldowns = 0,
	pickupPathfindAttempts = 0, pickupPathfindRoutes = 0, pickupPathfindFailures = 0,
	finalSweeps = 0, finalSweepChecks = 0, finalSweepCompleted = 0,
	finalSweepTimeouts = 0, finalSweepResets = 0, finalSweepLastSecond = 0,
	finalSweepCollectionAttempts = 0, pickupChasesIgnored = 0,
	pickupRepeatBlocks = 0, pickupCircuitTrips = 0, pickupCircuitResets = 0,
	pickupFailedInteractions = 0, finalSweepStallExits = 0,
	pickupTweenUnsafe = 0, pickupTweenDistance = 0, pickupTravelMs = 0,
	pickupAttempts = 0, pickupConfirmed = 0, pickupUnconfirmed = 0,
	promptAttempts = 0, promptFailures = 0, machineTargetChanges = 0,
	machineStalls = 0, skillcheckInputs = 0, skillcheckInputFailures = 0,
	chases = 0, workerErrors = 0, machineCompletions = 0,
	machinePlacements = 0, machineDangers = 0, fuseAttempts = 0,
	itemUseAttempts = 0, itemUseFailures = 0, itemUseObserved = 0, itemUseUnverified = 0,
	abilityCompletionTriggers = 0, abilityInputFailures = 0, abilityInputDeferred = 0,
	abilityAttempts = 0, abilityDispatched = 0,
	abilityWaffles = 0, abilityWaffleFailures = 0,
	trashUseAttempts = 0, trashUseInputs = 0, trashUseFailures = 0,
	trashAbilityInputs = 0, trashIdleInputs = 0,
	skillcheckExitAttempts = 0, skillcheckExitFailures = 0,
	deathExports = 0, deathExportFailures = 0,
	skillcheckLeaveDeferred = 0, skillcheckMoveBlocked = 0,
	hits = 0, totalDamage = 0, nearestEnemyMissing = 0,
	espAdded = 0, espRemoved = 0, espUpdates = 0,
	squidTentaclesRemoved = 0, squidTentacleErrors = 0,
	targetCacheRefreshes = 0, targetCacheHits = 0,
	handoffs = 0, handoffTotalMs = 0, handoffMaxMs = 0,
	handoffLastMs = 0, firstObjectiveMs = 0, machineScans = 0, slowMachineScans = 0,
}
local debugStatus = { action = "Ready", lastWarning = "None", currentTarget = "None",
	lastHit = "None", lastHandoff = "None", handoffPending = "None" }
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
function UNLOAD.render3d.enable()
	local ok, err = pcall(function() RunService:Set3dRenderingEnabled(false) end)
	if not ok then
		increment("renderErrors")
		debugEvent("RENDER", "disable_failed", { error = tostring(err) }, "ERROR")
		error(err, 0)
	end
	UNLOAD.render3d.enabled = true
	OPTIONS.Disable3DRendering = true
	increment("renderToggles")
	debugEvent("RENDER", "disabled_3d")
end
function UNLOAD.render3d.disable()
	local ok, err = pcall(function() RunService:Set3dRenderingEnabled(true) end)
	if not ok then
		increment("renderErrors")
		debugEvent("RENDER", "restore_failed", { error = tostring(err) }, "ERROR")
		error(err, 0)
	end
	UNLOAD.render3d.enabled = false
	OPTIONS.Disable3DRendering = false
	increment("renderToggles")
	debugEvent("RENDER", "enabled_3d")
end
UNLOAD.restoreRendering = function()
	if UNLOAD.render3d.enabled then UNLOAD.render3d.disable() end
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

UNLOAD.fallbackReport = function()
	local summary = {
		"TU - Rava Hub | Startup / Fallback Diagnostic Report",
		"Build=" .. BUILD,
		"Exported=" .. os.date("%Y-%m-%d %H:%M:%S"),
		"PlaceId=" .. tostring(game.PlaceId) .. " JobId=" .. tostring(game.JobId),
		"FullDiagnostics=" .. tostring(UNLOAD.fullDiagnostics),
		"Stats: " .. fieldString(debugStats),
		"Status: " .. fieldString(debugStatus),
		"---- EVENTS ----",
	}
	for _, event in ipairs(allDebugLines()) do table.insert(summary, event) end
	return table.concat(summary, "\n")
end
UNLOAD.fallbackExport = function(reason)
	if typeof(writefile) ~= "function" then
		debugEvent("DEBUG", "fallback_export_unavailable", { reason = reason }, "WARN")
		return false
	end
	local prefix = reason == "death" and "TU_Rava_Hub_DEATH_Debug_"
		or ("TU_Rava_Hub_" .. tostring(reason or "STARTUP") .. "_Debug_")
	local filename = prefix .. os.time() .. "_" .. math.floor((os.clock() % 1) * 100000) .. ".txt"
	local ok, err = pcall(writefile, filename, UNLOAD.fallbackReport())
	debugEvent("DEBUG", ok and "fallback_export_saved" or "fallback_export_error",
		{ filename = filename, reason = reason, error = ok and "none" or tostring(err) }, ok and "INFO" or "ERROR")
	return ok
end
UNLOAD.exporter = function() return UNLOAD.fallbackExport("UNLOAD") end

local activeMotion
local skillcheckProtected -- Initialized after GUI visibility helpers are defined.
local infectedNear -- Assigned after monster-folder helpers are defined.
local motionPauseUntil = 0
local PICKUP_TRAVEL = {
	Speed = 300, SafetyRadius = 24, CheckInterval = 0.035,
	ArriveTolerance = 4.5,
}
local function cancelMotion(owner)
	local motion = activeMotion
	if motion and (not owner or motion.owner == owner) then
		activeMotion = nil
		motion.cancelled = true
		if motion.tween then pcall(function() motion.tween:Cancel() end) end
		if not alive and motion.returnSurface then
			motion.unloading = true
			pcall(motion.returnSurface)
		end
		if motion.restore then pcall(motion.restore) end
		debugEvent("MOVE", "cancel", { owner = motion.owner, phase = motion.phase or "unknown" })
	end
end
UNLOAD.cancelMovement = cancelMotion
local function instantTeleport(destination, keepGoing, owner, mode)
	local emergency = mode == "emergency"
	if not alive or not keepGoing() then return false end
	local protected, checkType = false, "not_ready"
	if skillcheckProtected then protected, checkType = skillcheckProtected() end
	if protected then
		increment("skillcheckMoveBlocked")
		debugThrottled("skillcheck_teleport_block_" .. tostring(owner), 1.5,
			"SKILLCHECK", "teleport_deferred", { owner = owner, mode = mode or "routine", ui = checkType }, "INFO")
		return false
	end
	if owner == "machine" and activeMotion and activeMotion.owner == "pickup" then
		debugEvent("MOVE", "machine_preempts_pickup_tween", { phase = activeMotion.phase or "unknown" }, "WARN")
		cancelMotion("pickup")
	end
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
	if not emergency and infectedNear and infectedNear(destination.Position, 15) then
		increment("unsafeDestinations")
		debugThrottled("unsafe_" .. owner, 3, "MOVE", "unsafe_destination",
			{ owner = owner, position = tostring(destination.Position) }, "WARN")
		return false
	end
	local ok, err = pcall(function()
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
		root.CFrame = destination
	end)
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

local function tweenUnderMap(destination, keepGoing, owner, mode)
	local emergency = mode == "emergency"
	if not alive or not keepGoing() then return false, "inactive" end
	if skillcheckProtected and skillcheckProtected() then
		increment("skillcheckMoveBlocked")
		return false, "skillcheck_visible"
	end
	if owner == "machine" and activeMotion and activeMotion.owner ~= "machine" then
		cancelMotion()
	end
	if activeMotion then
		if emergency then cancelMotion() else return false, "movement_busy" end
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsDescendantOf(workspace) then return false, "missing_root" end
	local from = root.Position
	local goal = destination.Position
	if (from - goal).Magnitude < 0.25 then return true, "already_there" end
	if not emergency and infectedNear and infectedNear(goal, owner == "pickup" and PICKUP_TRAVEL.SafetyRadius or 15) then
		increment("underMapGuardBlocks")
		return false, "unsafe_destination"
	end
	local cruiseY = math.min(from.Y, goal.Y) + OPTIONS.TweenDepth
	if from.Y < goal.Y + OPTIONS.TweenDepth + 2 then
		cruiseY = math.min(cruiseY + math.abs(OPTIONS.TweenDepth), from.Y)
	end
	local destroyY = workspace.FallenPartsDestroyHeight
	if cruiseY <= destroyY + 20 then
		increment("underMapGuardBlocks")
		debugEvent("MOVE", "depth_blocked", { requestedY = cruiseY, destroyY = destroyY,
			depth = OPTIONS.TweenDepth, owner = owner }, "WARN")
		return false, "near_destroy_height"
	end
	local points = {
		Vector3.new(from.X, cruiseY, from.Z),
		Vector3.new(goal.X, cruiseY, goal.Z),
		goal,
	}
	local motion = { owner = owner, phase = "descent", cancelled = false }
	local originalAnchored = root.Anchored
	local collision = {}
	for _, part in ipairs(character:GetDescendants()) do
		if part:IsA("BasePart") then
			collision[part] = part.CanCollide
			part.CanCollide = false
		end
	end
	root.Anchored = true
	function motion.restore()
		if motion.restored then return end
		motion.restored = true
		for part, value in pairs(collision) do
			if part.Parent then pcall(function() part.CanCollide = value end) end
		end
		if root.Parent then pcall(function() root.Anchored = originalAnchored end) end
	end
	activeMotion = motion
	local startAt = os.clock()
	local tracked = workspace:FindFirstChild("Alive")
	tracked = tracked and tracked:FindFirstChild(player.Name)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local function health()
		local hp = tracked and tracked:GetAttribute("Health")
		if type(hp) == "number" then return hp end
		return humanoid and humanoid.Health or nil
	end
	local healthAtStart = health()
	function motion.returnSurface()
		if root.Parent and root.Anchored then
			local ok, tween = pcall(function()
				return TweenService:Create(root, TweenInfo.new(0.12, Enum.EasingStyle.Linear),
					{ CFrame = CFrame.new(from) })
			end)
			if ok then
				pcall(function() tween:Play() end)
				local deadline = os.clock() + 0.22
				while tween.PlaybackState == Enum.PlaybackState.Playing
					and os.clock() < deadline do RunService.Heartbeat:Wait() end
			end
		end
	end
	local function abort(reason)
		local stillOwns = activeMotion == motion
		motion.cancelled = true
		if motion.tween then pcall(function() motion.tween:Cancel() end) end
		if stillOwns and character == player.Character and root.Parent and health() ~= 0 then
			local surface = CFrame.new(from)
			local recovered, recovery = pcall(function()
				return TweenService:Create(root, TweenInfo.new(0.12, Enum.EasingStyle.Linear),
					{ CFrame = surface })
			end)
			if recovered then
				motion.tween = recovery
				pcall(function() recovery:Play() end)
				local untilTime = os.clock() + 0.25
				while recovery.PlaybackState == Enum.PlaybackState.Playing and alive
					and os.clock() < untilTime do RunService.Heartbeat:Wait() end
			end
		end
		if stillOwns and activeMotion == motion then activeMotion = nil end
		if not motion.unloading then motion.restore() end
		increment("underMapAborts")
		if reason == "health_dropped" then increment("underMapHealthStops") end
		debugEvent("MOVE", "undermap_abort", { owner = owner, reason = reason,
			elapsedMs = math.floor((os.clock() - startAt) * 1000 + 0.5),
			depth = OPTIONS.TweenDepth }, "WARN")
		return false, reason
	end
	debugEvent("MOVE", "undermap_start", { owner = owner, depth = OPTIONS.TweenDepth,
			cruiseY = string.format("%.1f", cruiseY),
			distance = string.format("%.1f", (from - goal).Magnitude) })
	local length = 0
	for i, point in ipairs(points) do
		if motion.cancelled or activeMotion ~= motion or not keepGoing() then
			return abort("interrupted")
		end
		local distance = (root.Position - point).Magnitude
		if distance > 0.2 then
			motion.phase = ({ "descent", "underground", "ascent" })[i]
			if i == 3 and not emergency and infectedNear and infectedNear(goal,
				owner == "pickup" and PICKUP_TRAVEL.SafetyRadius or 15) then
				return abort("enemy_at_destination")
			end
			local duration = math.max(0.04, distance / PICKUP_TRAVEL.Speed)
			local ok, tween = pcall(function()
				return TweenService:Create(root, TweenInfo.new(duration, Enum.EasingStyle.Linear),
					{ CFrame = CFrame.new(point) * (destination - destination.Position) })
			end)
			if not ok then return abort("tween_create_failed") end
			motion.tween = tween
			local played = pcall(function() tween:Play() end)
			if not played then return abort("tween_play_failed") end
			local deadline = os.clock() + duration + 0.5
			while tween.PlaybackState == Enum.PlaybackState.Playing do
				RunService.Heartbeat:Wait()
				if motion.cancelled or activeMotion ~= motion or player.Character ~= character
					or not alive or not keepGoing() then return abort("interrupted") end
				if skillcheckProtected and skillcheckProtected() then return abort("skillcheck_visible") end
				if os.clock() > deadline then return abort("tween_stalled") end
				local currentHealth = health()
				if healthAtStart and currentHealth and currentHealth < healthAtStart then
					return abort("health_dropped")
				end
			end
			if (root.Position - point).Magnitude > PICKUP_TRAVEL.ArriveTolerance then
				return abort("arrival_drift")
			end
			length += distance
		end
	end
	if activeMotion == motion then activeMotion = nil end
	motion.restore()
	increment("underMapTweens")
	if owner == "pickup" then
		increment("pickupTweens")
		increment("pickupTweenDistance", math.floor(length))
		increment("pickupTravelMs", math.floor((os.clock() - startAt) * 1000))
	end
	debugEvent("MOVE", "undermap_arrived", { owner = owner, depth = OPTIONS.TweenDepth,
			ms = math.floor((os.clock() - startAt) * 1000 + 0.5) })
	return true, "undermap"
end

local function teleportCharacter(destination, keepGoing, owner, mode)
	if OPTIONS.MovementMode == "Teleport" then
		return instantTeleport(destination, keepGoing, owner, mode)
	end
	return tweenUnderMap(destination, keepGoing, owner, mode)
end

local function tweenPickup(destination, keepGoing, target)
	local arrived, reason = teleportCharacter(destination, keepGoing, "pickup", "routine")
	return arrived, reason or OPTIONS.MovementMode:lower()
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

local function findTSquid()
	local monsterFolder = workspace:FindFirstChild("MonsterFolder")
	return monsterFolder and monsterFolder:FindFirstChild("TSquid")
end

local function deleteSquidTentacle(inst, reason)
	if not alive or not inst or inst.Name ~= "Tentacle" or not inst.Parent then return end
	local squid = findTSquid()
	if not squid or not inst:IsDescendantOf(squid) then return end
	local className = inst.ClassName
	local ok, err = pcall(function() inst:Destroy() end)
	if ok then
		increment("squidTentaclesRemoved")
		debugEvent("TSQUID", "tentacle_removed", { source = reason, class = className })
	else
		increment("squidTentacleErrors")
		debugThrottled("squid_delete_failed", 2, "TSQUID", "tentacle_remove_failed",
			{ source = reason, error = err }, "ERROR")
	end
end

local function sweepSquidTentacles(reason)
	local squid = findTSquid()
	if not squid then return end
	for _, inst in ipairs(squid:GetDescendants()) do
		if inst.Name == "Tentacle" then deleteSquidTentacle(inst, reason) end
	end
end

track(workspace.DescendantAdded:Connect(function(inst)
	if not alive then return end
	if inst.Name == "Tentacle" then
		task.defer(deleteSquidTentacle, inst, "spawn")
	elseif (inst.Name == "MonsterFolder" and inst.Parent == workspace)
		or (inst.Name == "TSquid" and inst.Parent and inst.Parent.Name == "MonsterFolder"
			and inst.Parent.Parent == workspace) then
		task.defer(function()
			if alive then sweepSquidTentacles("folder_recreated") end
		end)
	end
end))

sweepSquidTentacles("startup")
supervise("TSquid Tentacle watcher", function() return alive end, function()
	while alive do
		sweepSquidTentacles("watchdog")
		task.wait(0.6)
	end
end)

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
UNLOAD.gui = screenGui
_G.TURavaHubUnload = UNLOAD.request
track(screenGui.Destroying:Connect(function()
	if not UNLOAD.active then UNLOAD.request("gui_destroyed") end
end))
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
uiText(top, "RAVA HUB", 21, true, UI.text, { Position = UDim2.fromOffset(22, 10), Size = UDim2.fromOffset(166, 27) })
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
track(unloadButton.Activated:Connect(function()
	UNLOAD.request("header_button")
end))

local sidebar = new("Frame", { Position = UDim2.fromOffset(0, 64), Size = UDim2.new(0, 158, 1, -94),
	BackgroundColor3 = UI.surface, BorderSizePixel = 0 }, main)
new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 7) }, sidebar)
new("UIPadding", { PaddingTop = UDim.new(0, 15), PaddingLeft = UDim.new(0, 10),
	PaddingRight = UDim.new(0, 10) }, sidebar)
local mainArea = new("Frame", { Position = UDim2.fromOffset(158, 64),
	Size = UDim2.new(1, -158, 1, -94), BackgroundTransparency = 1 }, main)
local footer = new("Frame", { Position = UDim2.new(0, 0, 1, -30), Size = UDim2.new(1, 0, 0, 30),
	BackgroundColor3 = UI.surface, BorderSizePixel = 0 }, main)
local footerLabel = uiText(footer, "TU - Rava Hub", 11, false, UI.muted,
	{ Position = UDim2.fromOffset(17, 5), Size = UDim2.new(1, -30, 0, 21) })
local diagnosticsDock = new("Frame", {
    Name = "DiagnosticsDock", Position = UDim2.new(0, 0, 1, -96),
    Size = UDim2.fromOffset(158, 65), BackgroundColor3 = UI.surface,
    BorderSizePixel = 0, ZIndex = 3,
}, main)
new("Frame", { Size = UDim2.new(1, -20, 0, 1), Position = UDim2.fromOffset(10, 2),
    BackgroundColor3 = UI.soft, BorderSizePixel = 0, ZIndex = 3 }, diagnosticsDock)
local pages, menuButtons, activeTab = {}, {}, "Autofarm"
local toggleRefreshers = {}
local TAB_ORDER = { "ESP", "Autofarm", "Machines", "Diagnostics" }
local TAB_SYMBOL = { ESP = "◉", Autofarm = "◆", Machines = "▣", Diagnostics = "≡" }
local function showTab(name)
	activeTab = name
	for _, refresh in ipairs(toggleRefreshers) do refresh() end
	for key, page in pairs(pages) do page.Visible = key == name end
	for key, button in pairs(menuButtons) do
		button.BackgroundColor3 = key == name and UI.soft or UI.surface
		button.TextColor3 = key == name and UI.text or UI.muted
	end
end
for index, name in ipairs(TAB_ORDER) do
    local diagnostic = name == "Diagnostics"
    local button = new("TextButton", {
        Name = name .. "Tab", Size = diagnostic and UDim2.new(1, -20, 0, 45)
            or UDim2.new(1, 0, 0, 45),
        Position = diagnostic and UDim2.fromOffset(10, 9) or UDim2.new(),
        LayoutOrder = index, BackgroundColor3 = UI.surface, BorderSizePixel = 0,
        ZIndex = diagnostic and 4 or 1,
        Text = "  " .. TAB_SYMBOL[name] .. "    " .. name,
        Font = Enum.Font.GothamMedium, TextSize = 14,
        TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = UI.muted,
    }, diagnostic and diagnosticsDock or sidebar)
    corner(button, 9)
    menuButtons[name] = button
    track(button.Activated:Connect(function()
        showTab(name)
        debugEvent("UI", "open_tab", { tab = name, access = diagnostic and "dock" or "sidebar" })
    end))
end
local diagnosticsQuick = new("TextButton", {
    Name = "DiagnosticsQuickAccess", Text = "LOGS",
    Position = UDim2.fromOffset(259, 16), Size = UDim2.fromOffset(72, 31),
    Font = Enum.Font.GothamBold, TextSize = 12, TextColor3 = UI.text,
    BackgroundColor3 = UI.surface2, BorderSizePixel = 0,
}, top)
corner(diagnosticsQuick, 8)
track(diagnosticsQuick.Activated:Connect(function()
    showTab("Diagnostics")
    debugEvent("UI", "open_tab", { tab = "Diagnostics", access = "header" })
end))
local function createSection(name)
	local page = new("ScrollingFrame", {
		Name = name .. "Page", Position = UDim2.fromOffset(0, 0), Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 4,
		ScrollBarImageColor3 = UI.accent, CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.None, Visible = name == activeTab,
	}, mainArea)
	local pageLayout = list(page, 9)
	track(pageLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
		page.CanvasSize = UDim2.fromOffset(0, pageLayout.AbsoluteContentSize.Y + 34)
	end))
	new("UIPadding", { PaddingTop = UDim.new(0, 15), PaddingLeft = UDim.new(0, 14),
		PaddingRight = UDim.new(0, 14), PaddingBottom = UDim.new(0, 14) }, page)
	pages[name] = page
	uiText(page, name, 20, true, UI.text, {
		Size = UDim2.new(1, -8, 0, 30), LayoutOrder = -2,
	})
	return page
end
local function createSubcategory(page, heading, order, initiallyOpen)
	local expanded = initiallyOpen ~= false
	local card = new("Frame", {
		Name = heading:gsub("[^%w]", "") .. "Group", Size = UDim2.new(1, -9, 0, 44),
		BackgroundColor3 = UI.surface2, BorderSizePixel = 0, LayoutOrder = order,
	}, page)
	corner(card, 10)
	uiStroke(card)
	local header = new("TextButton", {
		Name = "GroupHeader", Size = UDim2.new(1, 0, 0, 44),
		BackgroundTransparency = 1, BorderSizePixel = 0, Text = "", AutoButtonColor = false,
	}, card)
	uiText(header, heading, 14, true, UI.text, {
		Position = UDim2.fromOffset(12, 11), Size = UDim2.new(1, -55, 0, 22),
	})
	local caret = uiText(header, expanded and "−" or "+", 22, true, UI.accent, {
		Position = UDim2.new(1, -36, 0, 9), Size = UDim2.fromOffset(26, 24),
		TextXAlignment = Enum.TextXAlignment.Center,
	})
	local body = new("Frame", {
		Name = "GroupContent", BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 44), Size = UDim2.new(1, 0, 0, 0),
		Visible = expanded, BorderSizePixel = 0,
	}, card)
	local contentLayout = list(body, 6, Enum.HorizontalAlignment.Center)
	new("UIPadding", { PaddingTop = UDim.new(0, 3), PaddingBottom = UDim.new(0, 10),
		PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }, body)
	local function reflow()
		local height = expanded and (contentLayout.AbsoluteContentSize.Y + 15) or 0
		body.Visible = expanded
		body.Size = UDim2.new(1, 0, 0, height)
		card.Size = UDim2.new(1, -9, 0, 44 + height)
		caret.Text = expanded and "−" or "+"
	end
	track(contentLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(reflow))
	track(header.MouseButton1Click:Connect(function()
		expanded = not expanded
		reflow()
		debugEvent("UI", "subcategory", { group = heading, open = expanded })
	end))
	task.defer(reflow)
	return body
end

pages.Diagnostics = createSection("Diagnostics")
uiText(pages.Diagnostics, "Initializing Diagnostics…",
	12, false, UI.muted, {
		Name = "DiagnosticsStartupNotice", LayoutOrder = 1,
		Size = UDim2.new(1, -12, 0, 68), TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
	})
UNLOAD.bootstrapExport = new("TextButton", {
	Name = "DiagnosticsStartupExport", LayoutOrder = 2,
	Size = UDim2.new(1, -12, 0, 38), BackgroundColor3 = UI.accent,
	Text = "EXPORT STARTUP LOG", Font = Enum.Font.GothamBold,
	TextColor3 = UI.text, TextSize = 12, BorderSizePixel = 0,
}, pages.Diagnostics)
corner(UNLOAD.bootstrapExport, 8)
track(UNLOAD.bootstrapExport.Activated:Connect(function()
	UNLOAD.fallbackExport("STARTUP")
end))
UNLOAD.bootstrapUnload = new("TextButton", {
	Name = "DiagnosticsStartupUnload", LayoutOrder = 3,
	Size = UDim2.new(1, -12, 0, 38), BackgroundColor3 = Color3.fromRGB(92, 47, 62),
	Text = "UNLOAD HUB", Font = Enum.Font.GothamBold,
	TextColor3 = UI.text, TextSize = 12, BorderSizePixel = 0,
}, pages.Diagnostics)
corner(UNLOAD.bootstrapUnload, 8)
track(UNLOAD.bootstrapUnload.Activated:Connect(function()
	UNLOAD.request("startup_diagnostics")
end))
task.delay(6, function()
	if alive and not UNLOAD.fullDiagnostics then
		increment("workerErrors")
		debugEvent("SYSTEM", "startup_incomplete", {
			diagnostics = "fallback_available", note = "check_executor_console",
		}, "ERROR")
	end
end)
local function createToggleRow(parent, name, order, feature, description)
	local row = new("Frame", { Size = UDim2.new(1, -9, 0, description and 58 or 43),
		BackgroundColor3 = UI.surface, BorderSizePixel = 0, LayoutOrder = order }, parent)
	corner(row, 9)
	uiStroke(row)
	uiText(row, name, 14, description ~= nil, UI.text, {
		Position = UDim2.fromOffset(12, description and 6 or 0),
		Size = UDim2.new(1, -97, 0, description and 24 or 43),
	})
	if description then
		uiText(row, description, 11, false, UI.muted, {
			Position = UDim2.fromOffset(12, 30), Size = UDim2.new(1, -102, 0, 17),
			TextTruncate = Enum.TextTruncate.AtEnd,
		})
	end
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
	table.insert(toggleRefreshers, refresh)
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

do
	local dragging, origin, start
	local function isPress(input)
		return input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
	end
	track(top.InputBegan:Connect(function(input)
		local function onControl(control)
			local pos, size = control.AbsolutePosition, control.AbsoluteSize
			local p = input.Position
			return p.X >= pos.X and p.X <= pos.X + size.X
				and p.Y >= pos.Y and p.Y <= pos.Y + size.Y
		end
		if isPress(input) and not onControl(unloadButton) and not onControl(minimizeButton) then
			dragging, origin, start = true, input.Position, main.Position
		end
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

local function resolveWorkspacePath(path)
	local current = workspace
	for name in path:gmatch("[^%.]+") do current = current and current:FindFirstChild(name) end
	return current
end

local ESP_CONFIGS = {
	{ Name = "Item ESP", Folders = { "Items", "Capsules", "Candies", "Map.InfectedSamples" }, Color = Color3.fromRGB(255, 220, 70), TopLevelOnly = true },
	{ Name = "Objective ESP", Folders = { "Computers", "OilMachines" }, Color = Color3.fromRGB(90, 255, 120), TopLevelOnly = true,
		Extra = { "Map.SpecialFolder.BigMachine.Computer", "Map.SpecialFolder.BigMachine.Machine" } },
	{ Name = "Infected ESP", Folders = { "MonsterFolder" }, Color = Color3.fromRGB(255, 60, 60) },
}
local function isTarget(config, root, inst)
	if config.TopLevelOnly then
		return inst.Parent == root and (inst:IsA("Model") or inst:IsA("BasePart") or inst:IsA("Folder"))
	end
	if not (inst:IsA("Model") or inst:IsA("BasePart")) then return false end
	local parent = inst.Parent
	return parent == root or (parent and parent:IsA("Folder") and parent:IsDescendantOf(root))
end
local function getAdorneePart(inst)
	if inst:IsA("BasePart") then return inst end
	if inst:IsA("Model") and inst.PrimaryPart then return inst.PrimaryPart end
	return inst:FindFirstChildWhichIsA("BasePart", true)
end
local function newESP(config)
	local state = { enabled = false, objects = {}, roots = {}, run = 0 }
	local function remove(inst)
		local record = state.objects[inst]
		if not record then return end
		state.objects[inst] = nil
		for _, conn in ipairs(record.conns) do conn:Disconnect() end
		if record.highlight then record.highlight:Destroy() end
		if record.billboard then record.billboard:Destroy() end
		increment("espRemoved")
	end
	local function add(inst)
		if state.objects[inst] or not inst:IsDescendantOf(workspace) then return end
		local record = { conns = {}, name = inst.Name }
		state.objects[inst] = record
		local adornee = getAdorneePart(inst)
		local highlightTarget = inst:IsA("Folder") and adornee or inst
		if highlightTarget then
			record.highlight = new("Highlight", { Name = "TU_ESP_Highlight", Adornee = highlightTarget,
				DepthMode = Enum.HighlightDepthMode.AlwaysOnTop, FillTransparency = 0.93,
				OutlineTransparency = 0, OutlineColor = config.Color }, inst)
		end
		local function createLabel()
			if record.billboard or not state.enabled or not inst.Parent then return end
			local part = getAdorneePart(inst)
			if not part then return end
			if not record.highlight then
				record.highlight = new("Highlight", { Name = "TU_ESP_Highlight", Adornee = part,
					DepthMode = Enum.HighlightDepthMode.AlwaysOnTop,
					FillTransparency = 0.93, OutlineTransparency = 0, OutlineColor = config.Color }, inst)
			end
			local height = part.Size.Y
			if inst:IsA("Model") then
				local ok, size = pcall(function() return inst:GetExtentsSize() end)
				if ok then height = size.Y end
			end
			record.billboard = new("BillboardGui", { Adornee = part, AlwaysOnTop = true,
				Size = UDim2.fromOffset(220, 29), StudsOffsetWorldSpace = Vector3.new(0, height / 2 + 1.4, 0),
				MaxDistance = 700, ResetOnSpawn = false }, screenGui)
			record.label = new("TextLabel", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1),
				Text = inst.Name, TextColor3 = config.Color, TextStrokeTransparency = 0.12,
				TextScaled = false, TextSize = 15, Font = Enum.Font.GothamBold }, record.billboard)
		end
		createLabel()
		if not record.billboard then
			local c
			c = inst.DescendantAdded:Connect(function()
				if not state.enabled then return end
				createLabel()
				if record.billboard and c then c:Disconnect() end
			end)
			table.insert(record.conns, c)
		end
		table.insert(record.conns, inst:GetPropertyChangedSignal("Name"):Connect(function() record.name = inst.Name end))
		increment("espAdded")
	end
	local function clearRoots()
		for root, conns in pairs(state.roots) do
			for _, conn in ipairs(conns) do conn:Disconnect() end
			state.roots[root] = nil
		end
	end
	local function watchRoot(root)
		if not root or state.roots[root] then return end
		local conns = {}
		state.roots[root] = conns
		local function consider(obj)
			if isTarget(config, root, obj) then add(obj) end
		end
		if config.TopLevelOnly then
			for _, obj in ipairs(root:GetChildren()) do consider(obj) end
			table.insert(conns, root.ChildAdded:Connect(consider))
			table.insert(conns, root.ChildRemoved:Connect(remove))
		else
			for _, obj in ipairs(root:GetDescendants()) do consider(obj) end
			table.insert(conns, root.DescendantAdded:Connect(consider))
			table.insert(conns, root.DescendantRemoving:Connect(remove))
		end
	end
	local function sync()
		local wanted = {}
		for _, folderName in ipairs(config.Folders) do
			local root = resolveWorkspacePath(folderName)
			if root then
				watchRoot(root)
				for _, obj in ipairs(config.TopLevelOnly and root:GetChildren() or root:GetDescendants()) do
					if isTarget(config, root, obj) then wanted[obj] = true end
				end
			end
		end
		for _, path in ipairs(config.Extra or {}) do
			local obj = resolveWorkspacePath(path)
			if obj then wanted[obj] = true end
		end
		for obj in pairs(state.objects) do
			if not wanted[obj] then remove(obj) end
		end
		for obj in pairs(wanted) do add(obj) end
		for root in pairs(state.roots) do
			if not root:IsDescendantOf(workspace) then
				for _, conn in ipairs(state.roots[root]) do conn:Disconnect() end
				state.roots[root] = nil
			end
		end
	end
	local function refreshLabels()
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		local playerPos = root and root.Position
		for inst, record in pairs(state.objects) do
			if not inst:IsDescendantOf(workspace) then
				remove(inst)
			else
				if record.label then
					local part = getAdorneePart(inst)
					local distance = playerPos and part and math.floor((part.Position - playerPos).Magnitude + 0.5)
					local caption = record.name
					if distance then caption ..= "  •  " .. distance .. " studs" end
					if config.Name == "Objective ESP" then
						local value = inst:FindFirstChild("ComputerPercentage") or inst:FindFirstChild("OilValue")
						if value and (value:IsA("IntValue") or value:IsA("NumberValue")) then
							caption ..= "  [" .. math.floor(value.Value) .. "%]"
						end
					end
					if caption ~= record.label.Text then record.label.Text = caption end
					increment("espUpdates")
				end
			end
		end
	end
	function state.enable()
		if state.enabled then return end
		state.enabled = true
		state.run += 1
		local myRun = state.run
		state.rootAdded = workspace.DescendantAdded:Connect(function(child)
			for _, folderName in ipairs(config.Folders) do
				if child.Name == (folderName:match("([^%.]+)$"))
					and child == resolveWorkspacePath(folderName) then
					watchRoot(child)
					break
				end
			end
		end)
		supervise("esp " .. config.Name, function() return alive and state.enabled and state.run == myRun end, function()
			while alive and state.enabled and state.run == myRun do
				if not state.lastSweep or os.clock() - state.lastSweep > 4 then
					state.lastSweep = os.clock()
					sync()
				end
				refreshLabels()
				task.wait(0.38)
			end
		end)
	end
	function state.disable()
		state.enabled = false
		state.run += 1
		if state.rootAdded then state.rootAdded:Disconnect(); state.rootAdded = nil end
		clearRoots()
		for obj in pairs(state.objects) do remove(obj) end
		state.lastSweep = nil
	end
	table.insert(cleanups, state.disable)
	return state
end


local FARM = {
	Height = 3, Settle = 0.08, Dwell = 1.25,
	Revisit = 5, FailedRetry = 0.65, Empty = 0.12,
	Poll = 0.04, IdleReturn = 0.55, HeldLimit = 3,
	SpamRate = 16, BetweenPickups = 0.025, TeleportBetweenPickups = 0.10,
	TeleportSettle = 0.16, InfectedClear = 22,
}

local PROMPT_HOLDERS = { "Prompt", "PromptPart" }
local originalPromptSight = setmetatable({}, { __mode = "k" })
UNLOAD.restoreLOS = function()
	for prompt, wasRequired in pairs(originalPromptSight) do
		if prompt.Parent then
			pcall(function() prompt.RequiresLineOfSight = wasRequired end)
		end
	end
end
local function noPromptSight(prompt)
	if prompt and prompt:IsA("ProximityPrompt") then
		if originalPromptSight[prompt] == nil then
			originalPromptSight[prompt] = prompt.RequiresLineOfSight and true or false
		end
		if prompt.RequiresLineOfSight then
			local ok, err = pcall(function() prompt.RequiresLineOfSight = false end)
			if not ok then
				debugThrottled("sight_set_failed_" .. tostring(prompt), 10, "PROMPT", "disable_los_failed",
					{ prompt = prompt.Name, error = tostring(err) }, "WARN")
			end
		end
	end
	return prompt
end
local function getPrompt(target)
	for _, name in ipairs(PROMPT_HOLDERS) do
		local holder = target:FindFirstChild(name)
		if holder then
			if holder:IsA("ProximityPrompt") then return noPromptSight(holder) end
			local direct = holder:FindFirstChildWhichIsA("ProximityPrompt", true)
			if direct then return noPromptSight(direct) end
		end
	end
	return noPromptSight(target:FindFirstChildWhichIsA("ProximityPrompt", true))
end
for _, child in ipairs(workspace:GetDescendants()) do
	if child:IsA("ProximityPrompt") then noPromptSight(child) end
end
track(workspace.DescendantAdded:Connect(function(child)
	if child:IsA("ProximityPrompt") then noPromptSight(child) end
end))

local function getPromptPart(prompt, target)
	local parent = prompt.Parent
	if parent and parent:IsA("BasePart") then return parent end
	if parent and parent:IsA("Attachment") and parent.Parent:IsA("BasePart") then return parent.Parent end
	return getAdorneePart(target)
end

local function getPromptPosition(prompt, fallbackPart)
	local parent = prompt.Parent
	if parent and parent:IsA("Attachment") then return parent.WorldPosition end
	if parent and parent:IsA("BasePart") then return parent.Position end
	return fallbackPart.Position
end

local hasFirePrompt = typeof(fireproximityprompt) == "function"

local function triggerPrompt(prompt, forceHold)
	increment("promptAttempts")
	noPromptSight(prompt)
	if not prompt or not prompt:IsA("ProximityPrompt") or not prompt:IsDescendantOf(workspace) or not prompt.Enabled then
		increment("promptFailures")
		debugThrottled("invalid_pickup_prompt", 3, "PROMPT", "invalid_target", nil, "WARN")
		return false
	end
	if hasFirePrompt and not forceHold then
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
	noPromptSight(prompt)
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
				prompt.RequiresLineOfSight = false
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

local function pickupEvidence(prompt, target, initialParent, confirmPickup, initialHeld)
	if target.Parent ~= initialParent or not prompt:IsDescendantOf(target) then
		return true, "target_removed"
	end
	if confirmPickup and heldCount() > initialHeld then
		return true, "inventory_increased"
	end
	if not prompt.Enabled and not confirmPickup then return true, "prompt_disabled" end
	return false
end

local function spamPrompt(prompt, target, keepGoing, confirmPickup, initialHeld, initialParent)
	local deadline = os.clock() + FARM.Dwell
	local attempts = 0
	local holding, fallbackStarted, spamActive = false, false, true
	local beganAt = os.clock()
	local function finish(success, reason, count)
		spamActive = false
		return success, reason, count
	end
	local function beginFallbackHold()
		if holding or fallbackStarted or not hasFirePrompt or not prompt.Enabled then return end
		holding, fallbackStarted = true, true
		task.spawn(function()
			local began = pcall(function() prompt:InputHoldBegin() end)
			if began then
				local untilTime = os.clock() + math.max(0, prompt.HoldDuration) + 0.03
				while os.clock() < untilTime and spamActive and keepGoing() do task.wait(0.04) end
				pcall(function() prompt:InputHoldEnd() end)
			end
			holding = false
		end)
	end
	local function interruption()
		if confirmPickup and not prompt.Enabled then
			task.wait(0.14) -- brief replication grace period; do not linger near an enemy
			local collected, reason = pickupEvidence(prompt, target, initialParent, confirmPickup, initialHeld)
			if collected then return finish(true, reason, attempts) end
			return finish(false, "prompt_disabled_without_inventory", attempts)
		end
		return finish(false, "interrupted", attempts)
	end

	while os.clock() < deadline do
		local confirmed, reason = pickupEvidence(prompt, target, initialParent, confirmPickup, initialHeld)
		if confirmed then return finish(true, reason, attempts) end
		if not keepGoing() then return interruption() end

		attempts += 1
		if hasFirePrompt and attempts >= 8 and not holding and os.clock() - beganAt >= 0.5 then
			beginFallbackHold()
		end
		local started = os.clock()
		local fired = triggerPrompt(prompt, false)
		if not fired then
			debugThrottled("pickup_activation_" .. tostring(target), 2, "PICKUP",
				"activation_failed", { target = target.Name, attempt = attempts }, "WARN")
		end
		local nextAttempt = math.min(deadline, started + 1 / FARM.SpamRate)
		while os.clock() < nextAttempt do
			local done, why = pickupEvidence(prompt, target, initialParent, confirmPickup, initialHeld)
			if done then return finish(true, why, attempts) end
			if not keepGoing() then return interruption() end
			task.wait(math.min(FARM.Poll, math.max(0.01, nextAttempt - os.clock())))
		end
	end
	local collected, reason = pickupEvidence(prompt, target, initialParent, confirmPickup, initialHeld)
	if collected then return finish(true, reason, attempts) end
	return finish(false, "confirmation_timeout", attempts)
end

local targetCaches = setmetatable({}, { __mode = "k" })
local function getTargets(folder)
	local cache = targetCaches[folder]
	if not cache then
		cache = { dirty = true, conns = {}, last = 0, values = {} }
		targetCaches[folder] = cache
		local function invalidate(obj)
			local parent = obj.Parent
			if parent == folder or (parent and parent.Parent == folder) then cache.dirty = true end
		end
		for _, signal in ipairs({ folder.DescendantAdded, folder.DescendantRemoving }) do
			table.insert(cache.conns, signal:Connect(invalidate))
		end
		table.insert(cache.conns, folder.AncestryChanged:Connect(function(_, parent)
			if parent then return end
			for _, conn in ipairs(cache.conns) do conn:Disconnect() end
			targetCaches[folder] = nil
		end))
	end
	if cache.dirty or os.clock() - cache.last >= 1.2 then
		local values = {}
		for _, child in ipairs(folder:GetChildren()) do
			if child:IsA("Folder") then
				for _, inner in ipairs(child:GetChildren()) do table.insert(values, inner) end
			else
				table.insert(values, child)
			end
		end
		cache.values, cache.dirty, cache.last = values, false, os.clock()
		increment("targetCacheRefreshes")
	else
		increment("targetCacheHits")
	end
	return cache.values
end
table.insert(cleanups, function()
	for folder, cache in pairs(targetCaches) do
		for _, conn in ipairs(cache.conns) do conn:Disconnect() end
		targetCaches[folder] = nil
	end
end)


heldCount = function()
	local folder = player:FindFirstChild("ItemsFolder")
	return folder and #folder:GetChildren() or 0
end

local chase = { pending = false, holdUntil = 0 }
local finalSweepActive = false
local pickupCircuit = {
	paused = false,
	failed = setmetatable({}, { __mode = "k" }),
	blocked = setmetatable({}, { __mode = "k" }),
	failedTargets = setmetatable({}, { __mode = "k" }),
	distinctFailures = 0,
	consecutive = 0,
	lastConfirmed = os.clock(),
	MaxTargetFailures = 3,
	MaxConsecutiveFailures = 6,
	MaxStallSeconds = 12,
}
function pickupCircuit.pause(reason)
	if pickupCircuit.paused then return end
	pickupCircuit.paused = true
	increment("pickupCircuitTrips")
	debugEvent("PICKUP", "collection_paused", {
		reason = reason, failures = pickupCircuit.consecutive,
		failedTargets = pickupCircuit.distinctFailures,
	}, "WARN")
end
function pickupCircuit.reset(reason)
	if not pickupCircuit.paused then return end
	pickupCircuit.paused = false
	pickupCircuit.failed = setmetatable({}, { __mode = "k" })
	pickupCircuit.blocked = setmetatable({}, { __mode = "k" })
	pickupCircuit.failedTargets = setmetatable({}, { __mode = "k" })
	pickupCircuit.distinctFailures = 0
	pickupCircuit.consecutive = 0
	pickupCircuit.lastConfirmed = os.clock()
	increment("pickupCircuitResets")
	debugEvent("PICKUP", "collection_resumed", { reason = reason })
end
function pickupCircuit.record(target, folder, confirmed, reason, attempts)
	if confirmed then
		pickupCircuit.lastConfirmed = os.clock()
		pickupCircuit.consecutive = 0
		pickupCircuit.distinctFailures = 0
		pickupCircuit.failedTargets = setmetatable({}, { __mode = "k" })
		pickupCircuit.failed[target] = nil
		return
	end
	if (attempts or 0) < 1 or (reason ~= "confirmation_timeout"
		and reason ~= "prompt_disabled_without_inventory") then return end
	increment("pickupFailedInteractions")
	pickupCircuit.consecutive += 1
	pickupCircuit.failed[target] = (pickupCircuit.failed[target] or 0) + 1
	if not pickupCircuit.failedTargets[target] then
		pickupCircuit.failedTargets[target] = true
		pickupCircuit.distinctFailures += 1
	end
	if pickupCircuit.failed[target] >= pickupCircuit.MaxTargetFailures
		and not pickupCircuit.blocked[target] then
		pickupCircuit.blocked[target] = true
		increment("pickupRepeatBlocks")
		debugEvent("PICKUP", "item_retry_limit", {
			folder = folder, name = target.Name,
			attempts = pickupCircuit.failed[target], reason = reason,
		}, "WARN")
	end
	if pickupCircuit.consecutive >= pickupCircuit.MaxConsecutiveFailures
		and pickupCircuit.distinctFailures >= 2 then
		pickupCircuit.pause("repeated_failed_collections")
	end
end

track(workspace.ChildAdded:Connect(function(instance)
	if instance.Name == "Map" or instance.Name == "Items" or instance.Name == "Capsules" then
		pickupCircuit.reset("world_reloaded")
	end
end))

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
	if finalSweepActive or pickupCircuit.paused then return end
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
			return active() and not pickupCircuit.paused and (not gate or gate()) and not (isBlocked and isBlocked())
				and (finalSweepActive or os.clock() >= motionPauseUntil)
				and (finalSweepActive or not (OPTIONS.AutoHide and os.clock() < chase.holdUntil))
		end
		while active() do
			local folders = {}
			if type(folderName) == "table" then
				for _, name in ipairs(folderName) do
					local folder = resolveWorkspacePath(name)
					if folder then table.insert(folders, folder) end
				end
			else
				local folder = resolveWorkspacePath(folderName)
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
						local fresh = not pickupCircuit.blocked[target] and (not filter or filter(target))
							and (not recent[target] or os.clock() - recent[target] >= FARM.Revisit)
						local part = fresh and root and prompt and prompt.Enabled and getPromptPart(prompt, target)
						local unsafe = part and infectedNear(part.Position, FARM.InfectedClear)
						if unsafe then
							debugThrottled("pickup_unsafe_" .. tostring(target), 5, "PICKUP", "skipped_enemy_nearby",
								{ folder = folder.Name, name = target.Name }, "WARN")
						end
						if part and not unsafe and pickupCoordinator.owner == nil then
							pickupCoordinator.owner = farm
							pickupCoordinator.lastActivity = os.clock()
							pickupCoordinator.home = pickupCoordinator.home or root.CFrame
							didWork = true
							farm.working = true
							increment("pickupAttempts")
							if finalSweepActive then increment("finalSweepCollectionAttempts") end
							local beganAt = os.clock()
							debugEvent("PICKUP", "attempt", { folder = folder.Name, name = target.Name,
								held = heldCount(), prompt = prompt.Name, distance = string.format("%.1f", (root.Position - part.Position).Magnitude) })
							local initialHeld, initialParent = heldCount(), target.Parent
							local ok, confirmed, reason, attempts = pcall(function()
								if not allowed() then return false, "not_allowed", 0 end
								local function stillPicking(traveling)
									return allowed() and pickupCoordinator.owner == farm
										and part:IsDescendantOf(workspace) and prompt.Enabled
										and (traveling or not infectedNear(root.Position, FARM.InfectedClear))
								end
								local promptPosition = getPromptPosition(prompt, part)
								local approachHeight = math.clamp(prompt.MaxActivationDistance - 1, 0.25, FARM.Height)
								local destination = CFrame.new(promptPosition + Vector3.new(0, approachHeight, 0))
								local arrived, travelReason = tweenPickup(destination, function()
									return stillPicking(true) and not infectedNear(promptPosition, FARM.InfectedClear)
								end, target)
								if not arrived then
									if isBlocked and isBlocked() then return false, "preempted_by_machine", 0 end
									return false, "tween_" .. tostring(travelReason), 0
								end
								task.wait(OPTIONS.MovementMode == "Teleport" and FARM.TeleportSettle or FARM.Settle)
								if isBlocked and isBlocked() then return false, "preempted_by_machine", 0 end
								if infectedNear(root.Position, FARM.InfectedClear) then
									return false, "enemy_after_arrival", 0
								end
								local actualRange = (root.Position - promptPosition).Magnitude
								if actualRange > prompt.MaxActivationDistance then
									debugEvent("PICKUP", "outside_prompt_range", {
										name = target.Name, distance = string.format("%.2f", actualRange),
										maximum = prompt.MaxActivationDistance }, "WARN")
									return false, "outside_prompt_range", 0
								end
								local observed, why = pickupEvidence(prompt, target, initialParent, confirmPickup, initialHeld)
								if observed then return true, why, 0 end
								if not stillPicking() then
									return false, (isBlocked and isBlocked()) and "preempted_by_machine" or "interrupted_after_arrival", 0
								end
								local success, why, fired = spamPrompt(prompt, target, stillPicking, confirmPickup, initialHeld, initialParent)
								if not success and isBlocked and isBlocked() then return false, "preempted_by_machine", fired end
								return success, why, fired
							end)
							if active() and not (isBlocked and isBlocked()) and root.Parent
								and infectedNear(root.Position, FARM.InfectedClear) then
								local home = pickupCoordinator.home
								if home and not infectedNear(home.Position, PICKUP_TRAVEL.SafetyRadius) then
									debugEvent("DANGER", "pickup_escape", { pickup = target.Name, position = tostring(root.Position) }, "WARN")
									teleportCharacter(home, function() return active() end, "pickup_escape", "emergency")
								end
							end
							releasePickup(farm)
							if active() then
								task.wait(OPTIONS.MovementMode == "Teleport" and FARM.TeleportBetweenPickups or FARM.BetweenPickups)
							end
							if not ok then
								debugLog("ERROR pickup " .. tostring(target.Name) .. ": " .. tostring(confirmed))
								warn("[TU - Rava Hub] pickup error: " .. tostring(confirmed))
								confirmed, reason, attempts = false, "lua_error", 0
							end
							if reason == "preempted_by_machine" then
								increment("pickupPreemptions")
								debugEvent("PICKUP", "preempted_by_machine", {
									folder = folder.Name, name = target.Name,
									elapsedMs = math.floor((os.clock() - beganAt) * 1000 + 0.5),
								}, "INFO")
							end
							if confirmed then
								increment("pickupConfirmed")
								recent[target] = os.clock()
								elseif reason == "preempted_by_machine" then
								recent[target] = os.clock() - FARM.Revisit + 0.15
							else
								increment("pickupUnconfirmed")
								local blockedRoute = reason == "tween_unsafe_destination"
									or reason == "tween_enemy_at_destination"
									or reason == "tween_near_destroy_height"
								if blockedRoute then increment("pickupRouteCooldowns") end
								recent[target] = os.clock() - FARM.Revisit
									+ (blockedRoute and 4 or FARM.FailedRetry)
							end
							pickupCircuit.record(target, folder.Name, confirmed, reason, attempts)
							debugEvent("PICKUP", "result", { folder = folder.Name, name = target.Name,
								movement = OPTIONS.MovementMode:lower(), confirmed = confirmed, reason = reason or "unknown", activations = attempts or 0,
								maxDistance = prompt.MaxActivationDistance, holdDuration = prompt.HoldDuration,
								requiresSight = prompt.RequiresLineOfSight,
								duration = string.format("%.2f", os.clock() - beganAt), held = heldCount() },
								(confirmed or reason == "preempted_by_machine") and "INFO" or "WARN")
						end
					end
					if not allowed() then break end
				end
			end
			farm.hasWork = didWork
			farm.working = false
			if not didWork then
				local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
				local unsafeHere = root and infectedNear(root.Position, FARM.InfectedClear)
				returnPickupHome(unsafeHere == true, isBlocked)
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
				pickupCoordinator.home = nil
			else
				returnPickupHome(true, isBlocked)
			end
		end
	end
	table.insert(cleanups, farm.disable)
	return farm
end

do
local espBody = createSection("ESP", 1)
local espWorld = createSubcategory(espBody, "COLLECTIBLES & OBJECTIVES", 1)
local espThreats = createSubcategory(espBody, "INFECTED TRACKING", 2, true)
for i, config in ipairs(ESP_CONFIGS) do
	local parent = (config.Name == "Infected ESP") and espThreats or espWorld
	createToggleRow(parent, config.Name, i, newESP(config))
end

end

local TRASH_ITEMS = { Coffee = true, Socks = true, Waffle = true, ["Pristine Boots"] = true }
local HEALTH_ITEMS = { Bandaid = true, Medkit = true, ["Pristine Medkit"] = true }
local ITEM_OPTIONS = { Trash = false, Health = false, AutoTrashUse = true }

local function getHealth()
	local aliveFolder = workspace:FindFirstChild("Alive")
	local character = aliveFolder and aliveFolder:FindFirstChild(player.Name)
	local health = character and character:GetAttribute("Health")
	if type(health) == "number" then return health end
	local humanoid = player.Character and player.Character:FindFirstChildWhichIsA("Humanoid")
	if humanoid and humanoid.MaxHealth > 0 then
		return 3 * humanoid.Health / humanoid.MaxHealth
	end
	return nil
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
	local source = "attribute:Index"
	if index == nil then
		local value = item:FindFirstChild("Index")
		if value and value:IsA("ValueBase") then index, source = value.Value, "child:Index" end
	end
	if index == nil then
		local other = item:GetAttribute("Slot")
		if other ~= nil then index, source = other, "attribute:Slot" end
	end
	if type(index) == "string" then index = tonumber(index) end
	if type(index) == "number" and index % 1 == 0 and SLOT_KEYS[index] then
		return index, source
	end
	return nil, source
end

local function inventorySummary()
	local folder = player:FindFirstChild("ItemsFolder")
	if not folder then return "ItemsFolder_missing" end
	local out = {}
	for _, item in ipairs(folder:GetChildren()) do
		local slot = readItemIndex(item)
		table.insert(out, item.Name .. ":" .. tostring(slot or item:GetAttribute("Index") or "?"))
	end
	return table.concat(out, ",")
end

local function findSlot(names)
	local folder = player:FindFirstChild("ItemsFolder")
	if not folder then
		debugThrottled("inventory_missing", 5, "ITEM", "inventory_missing", nil, "WARN")
		return nil
	end
	for _, item in ipairs(folder:GetChildren()) do
		if names[item.Name] then
			local slot, source = readItemIndex(item)
			if slot then return slot, item, source end
			debugThrottled("invalid_slot_" .. item.Name, 5, "ITEM", "slot_unrecognized", {
				item = item.Name, index = tostring(item:GetAttribute("Index")),
				indexSource = source, inventory = inventorySummary(),
			}, "WARN")
		end
	end
	return nil
end

local slotInputBusy = false
local function pressSlot(slot, purpose, item, indexSource)
	purpose = purpose or "unknown"
	if not SLOT_KEYS[slot] then
		increment("itemUseFailures")
		debugEvent("ITEM", "invalid_slot", { slot = tostring(slot), purpose = purpose }, "WARN")
		return false
	end
	if UserInputService:GetFocusedTextBox() then
		debugThrottled("item_input_focused", 3, "ITEM", "input_deferred_focused_textbox", {
			purpose = purpose, slot = slot,
		}, "WARN")
		return false
	end
	local timeout = os.clock() + 0.35
	while slotInputBusy and os.clock() < timeout do task.wait(0.02) end
	if slotInputBusy then
		debugThrottled("item_input_busy", 2, "ITEM", "input_busy", { purpose = purpose }, "WARN")
		return false
	end
	slotInputBusy = true
	increment("itemUseAttempts")
	local initialHealth = getHealth()
	local folder = player:FindFirstChild("ItemsFolder")
	local initialCount = folder and #folder:GetChildren() or -1
	local driver, succeeded, err = "none", false, "unavailable"
	if typeof(keypress) == "function" and typeof(keyrelease) == "function" then
		driver = "executor_keypress"
		succeeded, err = pcall(function()
			keypress(0x30 + slot)
			task.wait(0.08)
			keyrelease(0x30 + slot)
		end)
		if not succeeded then pcall(keyrelease, 0x30 + slot) end
	end
	if not succeeded then
		driver = "VirtualInputManager"
		succeeded, err = pcall(function()
			local vim = game:GetService("VirtualInputManager")
			vim:SendKeyEvent(true, SLOT_KEYS[slot], false, game)
			task.wait(0.09)
			vim:SendKeyEvent(false, SLOT_KEYS[slot], false, game)
		end)
		if not succeeded then
			pcall(function()
				game:GetService("VirtualInputManager"):SendKeyEvent(false, SLOT_KEYS[slot], false, game)
			end)
		end
	end
	slotInputBusy = false
	if not succeeded then increment("itemUseFailures") end
	debugEvent("ITEM", "hotkey_sent", {
		purpose = purpose, item = item and item.Name or "unknown", slot = slot,
		indexSource = indexSource or "unknown", method = driver, acceptedByInputAPI = succeeded,
		error = succeeded and "none" or tostring(err),
	}, succeeded and "INFO" or "ERROR")
	if succeeded then
		task.delay(0.6, function()
			if not alive then return end
			local current = player:FindFirstChild("ItemsFolder")
			local newCount = current and #current:GetChildren() or -1
			local itemRemoved = item ~= nil and (current == nil or not item:IsDescendantOf(current))
			local healthNow = getHealth()
			local healed = purpose == "heal" and initialHealth ~= nil
				and healthNow ~= nil and healthNow > initialHealth
			local countChanged = initialCount >= 0 and newCount >= 0 and newCount < initialCount
			local observed = itemRemoved or healed or countChanged
			increment(observed and "itemUseObserved" or "itemUseUnverified")
			debugEvent("ITEM", observed and "effect_observed" or "effect_unverified", {
				purpose = purpose, item = item and item.Name or "unknown",
				method = driver, slot = slot, countBefore = initialCount, countAfter = newCount,
				itemRemoved = itemRemoved, healed = healed, -- Reusable items may not produce observable changes.
			}, observed and "INFO" or "WARN")
		end)
	end
	return succeeded
end

local function useForMachine(machine)
	local names = (machine:FindFirstChild("OilValue") and USE_ITEMS.Oil)
		or (machine:FindFirstChild("ComputerPercentage") and USE_ITEMS.Computer)
	if not names then return false end
	local slot, item, source = findSlot(names)
	if slot then return pressSlot(slot, "machine:" .. machine.Name, item, source) end
	debugThrottled("tool_missing_" .. machine.Name, 5, "ITEM", "tool_missing", {
		machine = machine.Name, inventory = inventorySummary(),
	}, "WARN")
	return false
end

local ABILITY = { KeyHold = 0.075, InputWait = 0.30, TrashDelay = 0.02 }
local trashControl = {
    busy = false, nextAttempt = setmetatable({}, { __mode = "k" }),
    Tick = 0.22, SuccessRetry = 3.0, FailureRetry = 0.8,
}

function trashControl.findSlot(preferWaffle, includeWaffle)
	local folder = player:FindFirstChild("ItemsFolder")
	if not folder then return nil end
	local now = os.clock()
	local fallbackSlot, fallbackItem, fallbackSource
	for _, item in ipairs(folder:GetChildren()) do
		if TRASH_ITEMS[item.Name] and (includeWaffle or item.Name ~= "Waffle")
			and now >= (trashControl.nextAttempt[item] or 0) then
			local slot, source = readItemIndex(item)
			if slot then
				if preferWaffle and item.Name == "Waffle" then
					return slot, item, source
				end
				if not fallbackSlot then
					fallbackSlot, fallbackItem, fallbackSource = slot, item, source
				end
			end
		end
	end
	return fallbackSlot, fallbackItem, fallbackSource
end

function trashControl.useSlot(slot, item, source, purpose, machineName)
	increment("trashUseAttempts")
	local sent = pressSlot(slot, purpose, item, source)
	trashControl.nextAttempt[item] = os.clock() + (sent and trashControl.SuccessRetry or trashControl.FailureRetry)
	increment(sent and "trashUseInputs" or "trashUseFailures")
	if sent then
		increment(purpose == "trash_after_ability" and "trashAbilityInputs" or "trashIdleInputs")
	end
	debugEvent("ITEM", sent and "trash_input_sent" or "trash_input_failed", {
		item = item.Name, slot = slot, reason = purpose,
		machine = machineName or "none", dispatched = sent,
	}, sent and "INFO" or "WARN")
	return sent
end
local abilityStatusLabel -- Created in Autofarm > Automatic Actions.
local machineFarm
local machinesDone
local leaveObjective
local machineExitBlockedUntil = 0

local autoAbility = { enabled = false }
function autoAbility.enable()
	if autoAbility.enabled then return end
	autoAbility.enabled = true
	if abilityStatusLabel then
		abilityStatusLabel.Text = "After each completed machine: press F  |  ENABLED"
		abilityStatusLabel.TextColor3 = UI.good
	end
	debugEvent("ABILITY", "enabled", { trigger = "machine_completion", input = "F", cooldownDetection = false })
end
function autoAbility.disable()
	if not autoAbility.enabled then return end
	autoAbility.enabled = false
	if abilityStatusLabel then
		abilityStatusLabel.Text = "After each completed machine: press F  |  DISABLED"
		abilityStatusLabel.TextColor3 = UI.muted
	end
	debugEvent("ABILITY", "disabled")
end
table.insert(cleanups, autoAbility.disable)

local function abilityAfterCompletion(machine)
	if not alive or not autoAbility.enabled then return false, "disabled" end
	local health = getHealth()
	local humanoid = player.Character and player.Character:FindFirstChildWhichIsA("Humanoid")
	if (health and health <= 0) or (humanoid and humanoid.Health <= 0) then
		return false, "dead"
	end
	if skillcheckProtected then
		local protected, ui = skillcheckProtected()
		if protected then
			increment("abilityInputDeferred")
			debugEvent("ABILITY", "completion_f_deferred_skillcheck", {
				machine = machine.Name, ui = tostring(ui),
			}, "WARN")
			return false, "skillcheck"
		end
	end
	if UserInputService:GetFocusedTextBox() then
		increment("abilityInputDeferred")
		debugEvent("ABILITY", "completion_f_deferred_textbox", { machine = machine.Name }, "WARN")
		return false, "textbox"
	end
	local deadline = os.clock() + ABILITY.InputWait
	while slotInputBusy and alive and os.clock() < deadline do task.wait(0.02) end
	if slotInputBusy or not alive then
		increment("abilityInputDeferred")
		debugEvent("ABILITY", "completion_f_deferred_input_busy", { machine = machine.Name }, "WARN")
		return false, "input_busy"
	end

	increment("abilityCompletionTriggers")
	increment("abilityAttempts")
	local driver, ok, err = "none", false, "unavailable"
	local started = os.clock()
	trashControl.busy = true
	if typeof(keypress) == "function" and typeof(keyrelease) == "function" then
		driver = "executor_keypress"
		ok, err = pcall(function()
			keypress(0x46) -- F
			task.wait(ABILITY.KeyHold)
			keyrelease(0x46)
		end)
		if not ok then pcall(keyrelease, 0x46) end
	end
	if not ok then
		driver = "VirtualInputManager"
		ok, err = pcall(function()
			local vim = game:GetService("VirtualInputManager")
			vim:SendKeyEvent(true, Enum.KeyCode.F, false, game)
			task.wait(ABILITY.KeyHold)
			vim:SendKeyEvent(false, Enum.KeyCode.F, false, game)
		end)
		if not ok then
			pcall(function()
				game:GetService("VirtualInputManager"):SendKeyEvent(false, Enum.KeyCode.F, false, game)
			end)
		end
	end
	local durationMs = math.floor((os.clock() - started) * 1000 + 0.5)
	if not ok then increment("abilityInputFailures") end
	if ok then increment("abilityDispatched") end
	debugEvent("ABILITY", ok and "completion_f_sent" or "completion_f_failed", {
		machine = machine.Name, method = driver, durationMs = durationMs,
		dispatched = ok, acceptedByGame = "unknown", error = ok and "none" or tostring(err),
	}, ok and "INFO" or "ERROR")
	if abilityStatusLabel then
		abilityStatusLabel.Text = ok and ("Last F: " .. machine.Name .. " (input sent)")
			or ("F input failed: " .. machine.Name)
		abilityStatusLabel.TextColor3 = ok and UI.good or UI.bad
	end
	if ok and ITEM_OPTIONS.AutoTrashUse and alive then
		task.wait(ABILITY.TrashDelay)
		if alive then
			local slot, item, source = trashControl.findSlot(true, true)
			if slot then
				local sent = trashControl.useSlot(slot, item, source, "trash_after_ability", machine.Name)
				if item.Name == "Waffle" then
					increment(sent and "abilityWaffles" or "abilityWaffleFailures")
				end
				debugEvent("ABILITY", "trash_after_f", {
					machine = machine.Name, item = item.Name, slot = slot, dispatched = sent,
				})
			else
				debugThrottled("ability_no_trash", 6, "ITEM", "trash_not_found", {
					inventory = inventorySummary(),
				}, "INFO")
			end
		end
	end
	trashControl.busy = false
	return ok, ok and "sent" or "input_failed"
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
			if health and health < 3 and os.clock() - lastHeal >= AUTO_USE.HealCooldown
				and not (skillcheckProtected and skillcheckProtected()) then
				local slot, item, source = findSlot(HEALTH_ITEMS)
				if slot and pressSlot(slot, "heal", item, source) then
					lastHeal = os.clock()
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

supervise("trash auto use", function()
	return alive
end, function()
	while alive do
		if ITEM_OPTIONS.AutoTrashUse and not slotInputBusy and not trashControl.busy
			and not UserInputService:GetFocusedTextBox()
			and not (skillcheckProtected and skillcheckProtected())
			and pickupCoordinator.owner == nil
			and not (machineFarm and machineFarm.enabled
				and (machineFarm.target ~= nil or machineFarm.placed == true
					or machineFarm.moving == true or machineFarm.finalizing == true)) then
			local slot, item, source = trashControl.findSlot(false, not autoAbility.enabled)
			if slot then
				trashControl.useSlot(slot, item, source, "trash_idle", nil)
			end
		end
		task.wait(trashControl.Tick)
	end
end)

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
			local folder = resolveWorkspacePath(entry.folder)
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

local function collectOpen()
	if finalSweepActive then return true end
	if OPTIONS.CollectLast then return machinesDone ~= nil and machinesDone() end
	return true
end

local function machineBusy()
	if finalSweepActive then return false end
	return machineFarm ~= nil and machineFarm.enabled == true and
		(machineFarm.target ~= nil or machineFarm.placed == true or machineFarm.moving == true
			or machineFarm.finalizing == true)
end

local capsuleFarm = newAutofarm({ "Capsules", "Map.InfectedSamples" }, collectOpen, nil, false, machineBusy)

local itemFarm = newAutofarm("Items", function()
	return heldCount() < FARM.HeldLimit and not capsuleFarm.working and collectOpen()
end, itemAllowed, true, machineBusy)

local candyFarm = newAutofarm("Candies", function()
	return not capsuleFarm.working and not itemFarm.working and collectOpen()
end, nil, false, machineBusy)

PICKUPS = {
	{ farm = capsuleFarm, folder = "Capsules" },
	{ farm = capsuleFarm, folder = "Map.InfectedSamples" },
	{ farm = itemFarm, folder = "Items", held = true, filter = itemAllowed },
	{ farm = candyFarm, folder = "Candies" },
}

local function scanFinalPickups()
	local result = { eligible = 0, safe = 0, unsafe = 0, skipped = 0, blocked = 0, sources = {} }
	local inventoryFull = heldCount() >= FARM.HeldLimit
	for _, entry in ipairs(PICKUPS) do
		local found = 0
		local folder = resolveWorkspacePath(entry.folder)
		if folder then
			local cache = targetCaches[folder]
			if cache then cache.dirty = true end
			for _, target in ipairs(getTargets(folder)) do
				if target and target.Parent then
					local prompt = getPrompt(target)
					if prompt and prompt.Enabled then
						local part = getPromptPart(prompt, target)
						if part then
							found += 1
							if pickupCircuit.blocked[target] then result.blocked = result.blocked + 1 end
							local accepted = not pickupCircuit.blocked[target] and not pickupCircuit.paused
								and entry.farm.enabled and (not entry.held or not inventoryFull)
								and (not entry.filter or entry.filter(target))
							if accepted then
								result.eligible += 1
								if infectedNear and infectedNear(part.Position, FARM.InfectedClear) then
									result.unsafe += 1
								else
									result.safe += 1
								end
							else
								result.skipped += 1
							end
						end
					end
				end
			end
		end
		table.insert(result.sources, entry.folder .. ":" .. found)
	end
	result.sourceSummary = table.concat(result.sources, ",")
	return result
end

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

do
local farmBody = createSection("Autofarm", 2)
local farmActions = createSubcategory(farmBody, "AUTOMATIC ACTIONS", 1, true)
createToggleRow(farmActions, "Auto Use Ability", 1, autoAbility)
createToggleRow(farmActions, "Auto Use Items", 3, autoUse)
createToggleRow(farmActions, "Auto Use Trash Items", 4,
	newOption(ITEM_OPTIONS, "AutoTrashUse"))

local farmPickups = createSubcategory(farmBody, "PICKUP ROUTES", 2, true)
createToggleRow(farmPickups, "Capsule Autofarm", 1, capsuleFarm)
createToggleRow(farmPickups, "Item Autofarm", 2, itemFarm)
createToggleRow(farmPickups, "Candy Autofarm", 3, candyFarm)
local timingRow = new("Frame", {
	LayoutOrder = 4, Size = UDim2.new(1, -9, 0, 43),
	BackgroundColor3 = UI.surface, BorderSizePixel = 0,
}, farmPickups)
corner(timingRow, 9)
uiStroke(timingRow)
uiText(timingRow, "Pickup Timing", 14, true, UI.text, {
	Position = UDim2.fromOffset(12, 0), Size = UDim2.new(0.42, 0, 1, 0),
})
local beforeButton = new("TextButton", {
	Text = "BEFORE", Font = Enum.Font.GothamBold, TextSize = 11,
	TextColor3 = UI.text, BorderSizePixel = 0,
	Position = UDim2.new(0.46, 0, 0.5, -14), Size = UDim2.new(0.25, -3, 0, 28),
}, timingRow)
local afterButton = new("TextButton", {
	Text = "AFTER", Font = Enum.Font.GothamBold, TextSize = 11,
	TextColor3 = UI.text, BorderSizePixel = 0,
	Position = UDim2.new(0.72, 0, 0.5, -14), Size = UDim2.new(0.26, -8, 0, 28),
}, timingRow)
corner(beforeButton, 7)
corner(afterButton, 7)
local function refreshTiming()
	beforeButton.BackgroundColor3 = OPTIONS.CollectLast and UI.soft or UI.accent
	afterButton.BackgroundColor3 = OPTIONS.CollectLast and UI.accent or UI.soft
end
local function setTiming(after)
	if OPTIONS.CollectLast == after then return end
	OPTIONS.CollectLast = after
	refreshTiming()
	debugEvent("PICKUP", "timing_changed", { mode = after and "after" or "before" })
end
track(beforeButton.Activated:Connect(function() setTiming(false) end))
track(afterButton.Activated:Connect(function() setTiming(true) end))
table.insert(toggleRefreshers, refreshTiming)
refreshTiming()

local farmFilters = createSubcategory(farmBody, "COLLECTION FILTERS", 3, true)
createToggleRow(farmFilters, "Pick Up Trash Items", 1, newOption(ITEM_OPTIONS, "Trash"))
createToggleRow(farmFilters, "Pick Up Health Items", 2, newOption(ITEM_OPTIONS, "Health"))

autoUse.enable()
autoAbility.enable()
for _, refresh in ipairs(toggleRefreshers) do refresh() end

end

local MACHINE = {
	Folders = { "OilMachines", "Computers" },  Range = 50,  Height = 3,
	Elevator = "Map.SpecialFolder.ExitElevator",  ElevatorFallback = "Elevator",  ElevatorHeight = -20,
	Tick = 0.03, Settle = 0.025, PromptRetry = 0.08,
	RescanInterval = 0.12, StallTimeout = 3, UseTimeout = 8,
	ClearHold = 1.0, ItemWaitMax = 35, CollectWaitMax = 90, ItemIdle = 0.2,
	FinalSweepPoll = 0.18, FinalSweepClearTime = 1.0,
	EyeHeight = 3,  SkillcheckPause = 3,  SkillcheckStale = 6,
	ChaseHold = 3,  DoneValue = 100,  FuseDwell = 1,
	Fuseboxes = {
		"Map.SpecialFolder.Fusebox.Handle.ProximityPrompt",
		"Map.SpecialFolder.ExitFusebox.Handle.ProximityPrompt",
	},
	Allowed = { TSelena = true, TSquid = true, TPhantasia = true, TFizzle = true, TSnakes = true },
}

local function targetPosition(inst)
	if inst:IsA("BasePart") then return inst.Position end
	if inst:IsA("Model") then return inst:GetPivot().Position end
	local part = getAdorneePart(inst)
	return part and part.Position
end

do
local selenaLook = { enabled = false, active = false, chaseSeen = false,
	target = nil, binding = "TU_RavaHub_LookAtSelena" }
local function selenaTarget()
	local folder = workspace:FindFirstChild("MonsterFolder")
	local unit = folder and folder:FindFirstChild("TSelena", true)
	if not unit or not unit:IsDescendantOf(folder) then return nil end
	if unit:IsA("Model") or unit:IsA("BasePart") then return unit end
	return nil
end

local function selenaPosition(unit)
	if not unit or not unit.Parent then return nil end
	if unit:IsA("BasePart") then return unit.Position end
	local part = unit.PrimaryPart or unit:FindFirstChild("Head", true)
		or unit:FindFirstChild("HumanoidRootPart", true)
		or unit:FindFirstChildWhichIsA("BasePart", true)
	return part and part.Position or nil
end

local function stopSelenaLook(reason)
	if not selenaLook.active then return end
	selenaLook.active = false
	selenaLook.target = nil
	pcall(function() RunService:UnbindFromRenderStep(selenaLook.binding) end)
	debugEvent("SELENA", "look_stopped", { reason = reason or "unknown" })
end

local function startSelenaLook(trigger)
	if not alive or not selenaLook.enabled or not selenaLook.chaseSeen or selenaLook.active then return end
	local unit = selenaTarget()
	if not unit or not selenaPosition(unit) then return end
	selenaLook.target = unit
	selenaLook.active = true
	local ok, err = pcall(function()
		RunService:BindToRenderStep(selenaLook.binding, Enum.RenderPriority.Camera.Value + 1, function()
			if not alive or not selenaLook.enabled or not selenaLook.chaseSeen then
				stopSelenaLook("disabled")
				return
			end
			local current = selenaLook.target
			local monsterFolder = workspace:FindFirstChild("MonsterFolder")
			if not monsterFolder or not current or not current:IsDescendantOf(monsterFolder) then
				selenaLook.chaseSeen = false
				stopSelenaLook("selena_unloaded")
				return
			end
			local destination = selenaPosition(current)
			if not destination then
				selenaLook.chaseSeen = false
				stopSelenaLook("selena_unloaded")
				return
			end
			local camera = workspace.CurrentCamera
			if camera and (destination - camera.CFrame.Position).Magnitude > 0.1 then
				camera.CFrame = CFrame.lookAt(camera.CFrame.Position, destination)
			end
		end)
	end)
	if not ok then
		selenaLook.active = false
		selenaLook.target = nil
		debugEvent("SELENA", "look_failed", { error = tostring(err) }, "ERROR")
		return
	end
	debugEvent("SELENA", "look_started", { trigger = trigger or "chase", target = unit:GetFullName() })
end

local function selenaChaseStarted()
	if not selenaLook.enabled then return end
	selenaLook.chaseSeen = true
	startSelenaLook("chase_started")
	if not selenaLook.active then
		task.spawn(function()
			for i = 1, 35 do
				if not alive or not selenaLook.enabled or not selenaLook.chaseSeen or selenaLook.active then return end
				task.wait(0.15)
				startSelenaLook("chase_delayed_spawn")
			end
		end)
	end
end

function selenaLook.enable()
	selenaLook.enabled = true
	if selenaLook.chaseSeen then startSelenaLook("toggle_enabled") end
end
function selenaLook.disable()
	selenaLook.enabled = false
	selenaLook.chaseSeen = false
	stopSelenaLook("toggle_or_unload")
end
selenaLook.onChase = selenaChaseStarted
selenaLook.stop = stopSelenaLook
UNLOAD.selenaLook = selenaLook
table.insert(cleanups, selenaLook.disable)
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

infectedNear = function(position, radius)
	local folder = workspace:FindFirstChild("MonsterFolder")
	if not folder then return false end
	for _, twisted in ipairs(getTargets(folder)) do
		if not isInsideMachineExcludedFolder(twisted)
			and (not MACHINE.Allowed[twisted.Name] or twisted.Name == "TSelena") then
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
	for _, twisted in ipairs(getTargets(folder)) do
		if not isInsideMachineExcludedFolder(twisted) and not MACHINE.Allowed[twisted.Name] then
			local pos = targetPosition(twisted)
			if pos then
				local delta = pos - position
				local flat = Vector3.new(delta.X, 0, delta.Z).Magnitude
				if flat <= MACHINE.Range then return true, twisted.Name, flat end
			end
		end
	end
	return false
end

local function nearestInfected(position)
	local folder = workspace:FindFirstChild("MonsterFolder")
	if not folder then return nil end
	local nearestName, nearestDistance, nearestPosition
	for _, enemy in ipairs(getTargets(folder)) do
		if enemy:IsA("Model") or enemy:IsA("BasePart") then
			local pos = targetPosition(enemy)
			if pos then
				local dist = (position - pos).Magnitude
				if not nearestDistance or dist < nearestDistance then
					nearestName, nearestDistance, nearestPosition = enemy.Name, dist, pos
				end
			end
		end
	end
	return nearestName, nearestDistance, nearestPosition
end
local writeDebugFile = UNLOAD.fallbackExport -- overwritten by full Diagnostics when ready
local deathExport = { handled = false, life = 0, character = nil }
local function exportOnDeath(reason, hp)
	if deathExport.handled or not alive then return end
	deathExport.handled = true
	increment("deathExports")
	debugEvent("HITS", "health_zero", { trigger = reason, health = hp, life = deathExport.life }, "ERROR")
	task.defer(function()
		if not alive then return end
		if writeDebugFile then
			if not writeDebugFile("death") then increment("deathExportFailures") end
		else
			task.delay(0.3, function()
				if writeDebugFile and alive then
					if not writeDebugFile("death") then increment("deathExportFailures") end
				else
					increment("deathExportFailures")
					debugEvent("DEBUG", "death_export_unavailable", { reason = "exporter_not_ready" }, "ERROR")
				end
			end)
		end
	end)
end
local healthMonitor = { source = nil, conn = nil, old = nil, diedConn = nil }
local function bindHealthSource()
	local aliveFolder = workspace:FindFirstChild("Alive")
	local actor = aliveFolder and aliveFolder:FindFirstChild(player.Name)
	local attributeValue = actor and actor:GetAttribute("Health")
	local source, mode
	if type(attributeValue) == "number" then
		source, mode = actor, "Alive.Health"
	else
		local character = player.Character
		local humanoid = character and character:FindFirstChildWhichIsA("Humanoid")
		if humanoid then source, mode = humanoid, "Humanoid.Health" end
	end
	if deathExport.character ~= player.Character then
		deathExport.character = player.Character
		deathExport.handled = false
		deathExport.life += 1
	end
	if source == healthMonitor.source and mode == healthMonitor.mode then return end
	if healthMonitor.conn then healthMonitor.conn:Disconnect(); healthMonitor.conn = nil end
	if healthMonitor.diedConn then healthMonitor.diedConn:Disconnect(); healthMonitor.diedConn = nil end
	healthMonitor.source, healthMonitor.mode = source, mode
	local currentHumanoid = player.Character and player.Character:FindFirstChildWhichIsA("Humanoid")
	if currentHumanoid then
		healthMonitor.diedConn = currentHumanoid.Died:Connect(function()
			if currentHumanoid.Health <= 0 then exportOnDeath("Humanoid.Died", currentHumanoid.Health) end
		end)
	end
	local function observe(newValue)
		if type(newValue) ~= "number" or not alive then return end
		local previous = healthMonitor.old
		healthMonitor.old = newValue
		if newValue > 0 and previous ~= nil and previous <= 0 then
			deathExport.handled = false
			deathExport.life += 1
		end
		if previous ~= nil and newValue < previous then
			local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			local playerPos = root and root.Position
			local name, distance
			if playerPos then name, distance = nearestInfected(playerPos) end
			increment("hits")
			increment("totalDamage", previous - newValue)
			if not name then increment("nearestEnemyMissing") end
			debugStatus.lastHit = string.format("%.1f -> %.1f | %s (%.1f studs)",
				previous, newValue, name or "none", distance or -1)
			debugEvent("HITS", "health_decreased", {
				source = mode, from = previous, to = newValue, damage = previous - newValue,
				nearestInfected = name or "none", nearestDistance = distance and string.format("%.1f", distance) or "unknown",
				position = playerPos and tostring(playerPos) or "unknown",
				machineTarget = debugStatus.currentTarget,
				pickupActive = pickupCoordinator.owner ~= nil,
				finalSweep = finalSweepActive,
				attribution = "proximity_only",
			}, "WARN")
		end
		if newValue <= 0 then exportOnDeath(mode or "unknown", newValue) end
	end
	healthMonitor.old = mode == "Alive.Health" and source:GetAttribute("Health") or (source and source.Health)
	if healthMonitor.old and healthMonitor.old <= 0 then exportOnDeath("initial_zero", healthMonitor.old) end
	if source and mode == "Alive.Health" then
		healthMonitor.conn = source:GetAttributeChangedSignal("Health"):Connect(function()
			observe(source:GetAttribute("Health"))
		end)
	elseif source then
		healthMonitor.conn = source.HealthChanged:Connect(observe)
	end
	debugEvent("HITS", "monitor_bound", { source = mode or "none", initial = healthMonitor.old or "unknown" })
end
table.insert(cleanups, function()
	if healthMonitor.conn then healthMonitor.conn:Disconnect() end
	if healthMonitor.diedConn then healthMonitor.diedConn:Disconnect() end
end)
supervise("health monitor", function() return alive end, function()
	while alive do
		bindHealthSource()
		task.wait(0.2)
	end
end)


task.spawn(function()
	local remotes = game:GetService("ReplicatedStorage"):WaitForChild("Remotes", 10)
	local event = remotes and remotes:WaitForChild("Chase", 10)
	if alive and event and event:IsA("RemoteEvent") then
		track(event.OnClientEvent:Connect(function(...)
			local hasSelenaMarker, hasOtherMonsterMarker = false, false
			for i = 1, select("#", ...) do
				local value = select(i, ...)
				local name = typeof(value) == "Instance" and value.Name
					or (type(value) == "string" and value or nil)
				if name == "TSelena" then
					hasSelenaMarker = true
				elseif name and name:match("^T[A-Z][a-z]") then
					hasOtherMonsterMarker = true
				end
			end
			for _, arg in ipairs({ ... }) do
				if arg == "Started" and (hasSelenaMarker or not hasOtherMonsterMarker) then
					UNLOAD.selenaLook.onChase()
				elseif (arg == "Stopped" or arg == "Ended" or arg == "Finished")
					and (hasSelenaMarker or not hasOtherMonsterMarker) then
					UNLOAD.selenaLook.chaseSeen = false
					UNLOAD.selenaLook.stop("chase_ended")
				end
				if arg == "Started" and OPTIONS.AutoHide then
					increment("chases")
					local pickupTravel = finalSweepActive or pickupCoordinator.owner ~= nil
						or (activeMotion and activeMotion.owner == "pickup")
						or ((capsuleFarm.enabled or itemFarm.enabled or candyFarm.enabled)
							and not machineBusy())
					if pickupTravel then
						increment("pickupChasesIgnored")
						debugThrottled("pickup_chase_ignored", 2, "DANGER", "pickup_auto_hide_suppressed", nil, "INFO")
						continue
					end
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
	local scanStarted = os.clock()
	increment("machineScans")
	local function report(target, status)
		local elapsed = (os.clock() - scanStarted) * 1000
		if elapsed > 30 then
			increment("slowMachineScans")
			debugThrottled("slow_machine_scan", 3, "PERF", "slow_machine_scan",
				{ ms = string.format("%.1f", elapsed), status = status }, "WARN")
		end
		return target, status
	end
	local normals = getMachines()
	local best, anyIncomplete = nearestIncomplete(normals)
	if best then return report(best, "work") end
	if anyIncomplete then return report(nil, "wait") end
	local bigs = getBigMachines()
	best, anyIncomplete = nearestIncomplete(bigs)
	if best then return report(best, "work") end
	if anyIncomplete then return report(nil, "wait") end
	return report(nil, (#normals + #bigs > 0) and "done" or "none")
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

local function skillcheckWidgetOnScreen(gui)
	if not gui or not gui:IsA("GuiObject") or not effectivelyVisible(gui) then return false end
	local size = gui.AbsoluteSize
	if size.X <= 0 or size.Y <= 0 then return false end
	local camera = workspace.CurrentCamera
	if camera then
		local view = camera.ViewportSize
		local pos = gui.AbsolutePosition
		if pos.X >= view.X or pos.Y >= view.Y or pos.X + size.X <= 0 or pos.Y + size.Y <= 0 then
			return false
		end
	end
	return true
end

local lastSkillcheckOnScreenAt = -math.huge
skillcheckProtected = function()
	local round = playerGui:FindFirstChild("RoundSkillcheck")
	local container = round and round:FindFirstChild("Container")
	local normal = container and container:FindFirstChild("Normal")
	if skillcheckWidgetOnScreen(normal) then
		lastSkillcheckOnScreenAt = os.clock()
		return true, "round"
	end
	local lock = playerGui:FindFirstChild("LockUI")
	local hud = lock and lock:FindFirstChild("HUD")
	local skill = hud and hud:FindFirstChild("Skillcheck")
	local main = skill and skill:FindFirstChild("Main")
	local marker = main and main:FindFirstChild("Marker")
	if skillcheckWidgetOnScreen(marker) then
		lastSkillcheckOnScreenAt = os.clock()
		return true, "bar"
	end
	if os.clock() - lastSkillcheckOnScreenAt < 0.18 then return true, "ui_transition" end
	return false, "none"
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
	return skillcheckProtected()
end

leaveObjective = function(reason, force, waitSeconds)
	reason = reason or "manual"
	local protected, checkType = skillcheckProtected()
	if protected then
		increment("skillcheckLeaveDeferred")
		debugThrottled("skillcheck_leave_" .. tostring(reason), 1,
			"MACHINE", "leave_deferred_skillcheck", { reason = reason,
				ui = checkType, forceRequested = force == true }, "INFO")
		return false
	end
	increment("skillcheckExitAttempts")
	machineExitBlockedUntil = math.max(machineExitBlockedUntil, os.clock() + 0.75)
	local finished, successful = false, false
	local begin = os.clock()
	task.spawn(function()
		local reprotected, uiType = skillcheckProtected()
		if reprotected then
			finished, successful = true, false
			increment("skillcheckLeaveDeferred")
			debugEvent("MACHINE", "leave_cancelled_ui_appeared", { reason = reason, ui = uiType }, "INFO")
			return
		end
		local ok, response = pcall(function()
			local remotes = game:GetService("ReplicatedStorage"):FindFirstChild("Remotes")
			local remote = remotes and remotes:FindFirstChild("SkillCheck")
			if not remote or not remote:IsA("RemoteFunction") then error("SkillCheck RemoteFunction unavailable") end
			return remote:InvokeServer()
		end)
		finished, successful = true, ok and response ~= false
		if not ok or response == false then increment("skillcheckExitFailures") end
		debugEvent("MACHINE",
			(not ok and "leave_remote_failed") or (response == false and "leave_remote_rejected" or "leave_remote_complete"),
			{ reason = reason, returned = tostring(response),
				responseVerified = response == true, requestCompleted = ok,
				elapsedMs = math.floor((os.clock() - begin) * 1000 + 0.5) },
			(not ok and "ERROR") or (response == false and "WARN" or "INFO"))
	end)
	local deadline = os.clock() + (waitSeconds or (force and 0.08 or 0.12))
	while not finished and os.clock() < deadline do task.wait() end
	if not finished then
		debugThrottled("leave_remote_pending", 2, "MACHINE", "leave_remote_pending",
			{ reason = reason, escapeContinues = force }, "WARN")
	end
	return successful or (force and not finished)
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

local function newMachineAutofarm()
	local farm = { enabled = false, target = nil, finalizing = false }
	local runId = 0
	local elevatorPreference = 1
	local pickupsAt, pickupsValue = 0, false
	local function cachedPickups()
		local now = os.clock()
		if now - pickupsAt >= 0.25 then
			pickupsAt = now
			pickupsValue = scanFinalPickups().safe > 0
		end
		return pickupsValue
	end
	local function move(position, keepGoing, mode)
		farm.moving = true
		local arrived = teleportCharacter(CFrame.new(position), keepGoing, "machine", mode)
		farm.moving = false
		return arrived
	end
	-- TODO (later): detect elevator activation / ready state from actual events,
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
	-- TODO (later): detect fusebox enable/completion events directly so the
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
		local toolTryAt = setmetatable({}, { __mode = "k" })
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
		local finalSweep = nil
		local startupPickupsDone = false
		local emergencyNextMove = false
		local handoffStartedAt, handoffFrom, handoffReason = nil, nil, nil
		local abilityTriggeredFor = setmetatable({}, { __mode = "k" })
		local function noteMachineCompleted(machine)
			if abilityTriggeredFor[machine] then return end
			abilityTriggeredFor[machine] = true
			increment("machineCompletions")
			debugEvent("MACHINE", "completed", {
				name = machine.Name, progress = tostring(getProgress(machine)),
			})
			if autoAbility.enabled then
				abilityAfterCompletion(machine)
			end
		end
		local function beginHandoff(reason, from)
			if handoffStartedAt then return end
			handoffStartedAt = os.clock()
			handoffFrom = from and from.Name or "none"
			handoffReason = reason
			debugStatus.handoffPending = reason .. " from " .. handoffFrom
			debugEvent("PERF", "handoff_begin", { from = handoffFrom, reason = reason })
		end
		farm.placed = false
		beginHandoff("start", nil)
		while active() do
			local root = getPlayerRoot()
			local moved = false
			local protected, checkType = skillcheckProtected()
			if protected then
				if activeMotion and activeMotion.owner == "pickup" then cancelMotion("pickup") end
				debugThrottled("machine_skillcheck_hold", 2, "SKILLCHECK", "holding_objective", {
					ui = checkType, target = farm.target and farm.target.Name or "none",
					chasePending = chase.pending,
				}, "INFO")
				task.wait(MACHINE.Tick)
				continue
			end
			if chase.pending and finalSweepActive then chase.pending = false end
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
					leaveObjective("chase_escape", true)
					hidden = goElevator(false, active)
				else
					hidden = false
				end
			end
			local busy = pickupBusy()
			if busy then lastBusyAt = os.clock() end
			local waitingPickups = busy or (cachedPickups() and os.clock() - lastBusyAt < MACHINE.ItemIdle)
			local pending = not pickupCircuit.paused and not startupPickupsDone
				and not OPTIONS.CollectLast and waitingPickups
			if pending and not farm.placed then
				if not waitStart then
					waitStart = os.clock()
					debugEvent("PICKUP", "before_machines_started", { limitSeconds = MACHINE.ItemWaitMax })
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
					if target and not isComplete(target) then abilityTriggeredFor[target] = nil end
					local currentUsable = target
						and isLiveMachineObjective(target)
						and not isComplete(target)
						and currentPrompt ~= nil
						and (currentPrompt.Enabled
							or (farm.placed and now - lastProgressAt <= MACHINE.UseTimeout))
					if not currentUsable then
						if target and scannedTarget ~= target then
							local completed = isComplete(target)
							beginHandoff(completed and "completed" or "unavailable", target)
							if completed then noteMachineCompleted(target) end
						end
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
					beginHandoff("completed_or_removed", target)
					if isComplete(target) then
						noteMachineCompleted(target)
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
					if (finished or finalSweep) and pickupCircuit.paused then
						pickupCircuit.reset("new_objective")
					end
					if finalSweep then
						finalSweepActive = false
						increment("finalSweepResets")
						debugEvent("SWEEP", "cancelled_new_objective", {
							newTarget = target.Name,
							previousMs = math.floor((os.clock() - finalSweep.started) * 1000 + 0.5),
						})
						finalSweep = nil
					end
					farm.finalizing = false
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
							leaveObjective("infected_near_machine", true)
							local alternative = safeAlternative(target)
							if alternative then
								beginHandoff("danger_reroute", target)
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
							local teleportAt = os.clock()
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
							task.wait(MACHINE.Settle)
							local initialFireAt = os.clock()
							local initialFired = triggerMachinePrompt(prompt)
							debugEvent("PERF", "prompt_after_teleport", {
								machine = target.Name, dispatched = initialFired,
								arrivalToPromptMs = math.floor((initialFireAt - teleportAt) * 1000 + 0.5),
							})
							if handoffStartedAt then
								local ms = math.floor((os.clock() - handoffStartedAt) * 1000 + 0.5)
								if handoffReason == "start" then
									debugStats.firstObjectiveMs = ms
								else
									increment("handoffs")
									increment("handoffTotalMs", ms)
									debugStats.handoffMaxMs = math.max(debugStats.handoffMaxMs, ms)
									debugStats.handoffLastMs = ms
									debugStatus.lastHandoff = tostring(ms) .. "ms " .. handoffFrom .. " -> " .. target.Name
								end
								debugStatus.handoffPending = "None"
								debugEvent("PERF", handoffReason == "start" and "first_objective" or "handoff_complete", {
									from = handoffFrom, to = target.Name, ms = ms,
									reason = handoffReason, dispatched = initialFired,
								})
								handoffStartedAt, handoffFrom, handoffReason = nil, nil, nil
							end
							lastFire = initialFireAt
							fireAfter = 0
							farm.placed = true
							startupPickupsDone = true
							moved = true
							placedAt = os.clock()
							increment("machinePlacements")
							logProgress = true
							logFire = not initialFired
							debugLog(string.format("place %s dist=%.1f max=%.1f hold=%.2f enabled=%s progress=%s", target.Name,
								(root.Position - part.Position).Magnitude, prompt.MaxActivationDistance, prompt.HoldDuration, tostring(prompt.Enabled), tostring(getProgress(target))))
							usedItem = false
							lastPrompt = prompt
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
						if autoUse.enabled and activated and not usedItem and farm.placed
							and not checking and not (skillcheckProtected and skillcheckProtected())
							and not isComplete(target)
							and os.clock() >= chase.holdUntil
							and os.clock() - (toolTryAt[target] or -math.huge) >= 0.8 then
							toolTryAt[target] = os.clock()
							usedItem = useForMachine(target)
						end
					end
				elseif status == "done" then
					if handoffStartedAt then
						debugEvent("PERF", "handoff_no_next_objective", {
								from = handoffFrom, reason = handoffReason,
								ms = math.floor((os.clock() - handoffStartedAt) * 1000 + 0.5),
							})
						handoffStartedAt, handoffFrom, handoffReason = nil, nil, nil
						debugStatus.handoffPending = "None"
					end
					if not finished then
						local now = os.clock()
						if not finalSweep then
							finalSweepActive = true
							chase.pending = false
							chase.holdUntil = 0
							motionPauseUntil = 0
							pickupCoordinator.home = nil
							finalSweep = { started = now, lastCheck = -math.huge, emptySince = nil,
								emptyChecks = 0, checks = 0, confirmedStart = debugStats.pickupConfirmed,
								attemptsStart = debugStats.finalSweepCollectionAttempts }
							increment("finalSweeps")
							debugEvent("SWEEP", "start", {
								maxWaitSeconds = MACHINE.CollectWaitMax,
								collectAfterMachines = OPTIONS.CollectLast,
								items = itemFarm.enabled, capsules = capsuleFarm.enabled, candies = candyFarm.enabled,
							})
						end
						if now - finalSweep.lastCheck >= MACHINE.FinalSweepPoll then
							finalSweep.lastCheck = now
							finalSweep.checks += 1
							increment("finalSweepChecks")
							local snapshot = scanFinalPickups()
							local busyNow = pickupBusy() or pickupCoordinator.owner ~= nil
							local pending = snapshot.safe > 0 or busyNow
							if pending then
								finalSweep.emptySince, finalSweep.emptyChecks = nil, 0
							else
								finalSweep.emptySince = finalSweep.emptySince or now
								finalSweep.emptyChecks += 1
							end
							debugThrottled("final_sweep_check", 0.9, "SWEEP", "check", {
								check = finalSweep.checks, safe = snapshot.safe, unsafe = snapshot.unsafe,
								ignored = snapshot.skipped, blocked = snapshot.blocked, pickupBusy = busyNow,
								attempted = debugStats.finalSweepCollectionAttempts - finalSweep.attemptsStart,
								confirmedSoFar = debugStats.pickupConfirmed - finalSweep.confirmedStart,
								sources = snapshot.sourceSummary,
							})
							local timedOut = now - finalSweep.started >= MACHINE.CollectWaitMax
							local noProgressSeconds = now - math.max(finalSweep.started, pickupCircuit.lastConfirmed)
							local stalled = not pickupCircuit.paused and snapshot.safe > 0
								and noProgressSeconds >= pickupCircuit.MaxStallSeconds
								and (debugStats.finalSweepCollectionAttempts > finalSweep.attemptsStart)
							local circuitBroken = pickupCircuit.paused or stalled
							local emptyVerified = finalSweep.emptySince
								and finalSweep.emptyChecks >= 2
								and now - finalSweep.emptySince >= MACHINE.FinalSweepClearTime
							if timedOut or emptyVerified or circuitBroken then
								local verify = scanFinalPickups()
								if not timedOut and not circuitBroken
									and (verify.safe > 0 or pickupBusy() or pickupCoordinator.owner ~= nil) then
									finalSweep.emptySince, finalSweep.emptyChecks = nil, 0
									increment("finalSweepLastSecond")
									debugEvent("SWEEP", "last_second_pickup_detected", {
										safe = verify.safe, sources = verify.sourceSummary,
									})
								else
									if stalled then pickupCircuit.pause("final_sweep_no_progress") end
									local sweepStatus = circuitBroken and "collection_blocked"
										or timedOut and "timeout" or "verified_clear"
									if circuitBroken then increment("finalSweepStallExits") end
									farm.finalizing = OPTIONS.AutoElevator or OPTIONS.Fuseboxes
									finalSweepActive = false
									if farm.finalizing then
										if activeMotion and activeMotion.owner == "pickup" then cancelMotion("pickup") end
										pickupCoordinator.home = nil
									end
									finished = true
									if timedOut then
										increment("finalSweepTimeouts")
									elseif not circuitBroken then
										increment("finalSweepCompleted")
									end
									debugEvent("SWEEP", sweepStatus == "verified_clear" and "complete" or sweepStatus, {
										checks = finalSweep.checks, elapsedMs = math.floor((now - finalSweep.started) * 1000 + 0.5),
										attempted = debugStats.finalSweepCollectionAttempts - finalSweep.attemptsStart,
										collected = debugStats.pickupConfirmed - finalSweep.confirmedStart,
										safeRemaining = verify.safe, unsafeRemaining = verify.unsafe,
										blocked = verify.blocked, ignored = verify.skipped, sources = verify.sourceSummary,
									}, sweepStatus == "verified_clear" and "INFO" or "WARN")
									debugEvent("MACHINE", "all_complete", {
										autoElevator = OPTIONS.AutoElevator, fuseboxes = OPTIONS.Fuseboxes,
										finalSweep = sweepStatus,
									})
									if OPTIONS.Fuseboxes and not circuitBroken then checkFuseboxes(active) end
									if OPTIONS.AutoElevator and active() then
										finishAtElevator(active)
									else
										farm.finalizing = false
									end
								end
							end
						end
					end
					task.wait(0.08)
				elseif not part and (status == "wait" or status == "none") then
					debugThrottled("machine_wait_" .. status, 5, "MACHINE", "waiting_for_objective", {
						status = status, pending = debugStatus.handoffPending,
					}, "WARN")
					task.wait(0.15)
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
		finalSweepActive = false
		runId += 1
		farm.target, farm.placed, farm.moving, farm.finalizing = nil, false, false, false
		cancelMotion("machine")
		restoreMachinePrompts()
		if wasEnabled and alive then
			local protected, checkType = skillcheckProtected()
			if protected then
				debugEvent("MACHINE", "disable_exit_deferred_skillcheck", { ui = checkType }, "INFO")
			else
				leaveObjective("machine_autofarm_disabled", true)
				if OPTIONS.AutoElevator then
					goElevator(true, function() return alive and not farm.enabled end)
				end
			end
		end
	end
	table.insert(cleanups, farm.disable)
	return farm
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

do
local machinesBody = createSection("Machines", 3)
local machineCore = createSubcategory(machinesBody, "OBJECTIVE AUTOMATION", 1, true)
createToggleRow(machineCore, "Machine Autofarm", 1, machineFarm)
createToggleRow(machineCore, "Auto Skillcheck", 2, autoSkillcheck)

local machineMovement = createSubcategory(machinesBody, "MOVEMENT", 2, true)
local modeRow = new("Frame", { LayoutOrder = 1, Size = UDim2.new(1, -9, 0, 43),
	BackgroundColor3 = UI.surface, BorderSizePixel = 0 }, machineMovement)
corner(modeRow, 9)
uiStroke(modeRow)
uiText(modeRow, "Movement Mode", 14, true, UI.text, {
	Position = UDim2.fromOffset(12, 0), Size = UDim2.new(0.42, 0, 1, 0),
})
local tweenButton = new("TextButton", {
	Text = "TWEEN", Font = Enum.Font.GothamBold, TextSize = 11,
	TextColor3 = UI.text, BorderSizePixel = 0,
	Position = UDim2.new(0.46, 0, 0.5, -14), Size = UDim2.new(0.25, -3, 0, 28),
}, modeRow)
local teleportButton = new("TextButton", {
	Text = "TELEPORT", Font = Enum.Font.GothamBold, TextSize = 10,
	TextColor3 = UI.text, BorderSizePixel = 0,
	Position = UDim2.new(0.72, 0, 0.5, -14), Size = UDim2.new(0.26, -8, 0, 28),
}, modeRow)
corner(tweenButton, 7)
corner(teleportButton, 7)
local depthRow = new("Frame", { LayoutOrder = 2, Size = UDim2.new(1, -9, 0, 65),
	BackgroundColor3 = UI.surface, BorderSizePixel = 0, Visible = false }, machineMovement)
corner(depthRow, 9)
uiStroke(depthRow)
uiText(depthRow, "Under-map Depth", 14, true, UI.text, {
	Position = UDim2.fromOffset(12, 2), Size = UDim2.new(1, -110, 0, 26),
})
local depthValue = uiText(depthRow, "−15 studs", 12, true, UI.accent, {
	Position = UDim2.new(1, -108, 0, 2), Size = UDim2.fromOffset(96, 26),
	TextXAlignment = Enum.TextXAlignment.Right,
})
local depthTrack = new("TextButton", { Text = "", AutoButtonColor = false,
	Position = UDim2.new(0, 16, 0, 33), Size = UDim2.new(1, -32, 0, 24),
	BackgroundTransparency = 1, BorderSizePixel = 0 }, depthRow)
local depthRail = new("Frame", { BackgroundColor3 = UI.soft, BorderSizePixel = 0,
	Position = UDim2.fromOffset(0, 9), Size = UDim2.new(1, 0, 0, 6) }, depthTrack)
corner(depthRail, 3)
local depthFill = new("Frame", { BackgroundColor3 = UI.accent, BorderSizePixel = 0,
	Position = UDim2.fromOffset(0, 9), Size = UDim2.new(0, 0, 0, 6) }, depthTrack)
corner(depthFill, 3)
local depthKnob = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5),
	Size = UDim2.fromOffset(17, 17), BackgroundColor3 = UI.text,
	BorderSizePixel = 0 }, depthTrack)
corner(depthKnob, 9)
local draggingDepth = false
local function refreshMovementMode()
	local tween = OPTIONS.MovementMode == "Tween"
	tweenButton.BackgroundColor3 = tween and UI.accent or UI.soft
	teleportButton.BackgroundColor3 = tween and UI.soft or UI.accent
	depthRow.Visible = tween
	local ratio = (OPTIONS.TweenDepth + 50) / 40
	depthFill.Size = UDim2.new(ratio, 0, 0, 6)
	depthKnob.Position = UDim2.fromScale(ratio, 0.5)
	depthValue.Text = string.format("%d studs", OPTIONS.TweenDepth)
end
local function selectMovementMode(mode)
	if OPTIONS.MovementMode == mode then return end
	if activeMotion then
		debugEvent("MOVE", "mode_change_blocked", { requested = mode, reason = "travel_active" }, "WARN")
		return
	end
	OPTIONS.MovementMode = mode
	refreshMovementMode()
	debugEvent("MOVE", "mode_changed", { mode = mode, depth = OPTIONS.TweenDepth })
end
track(tweenButton.Activated:Connect(function() selectMovementMode("Tween") end))
track(teleportButton.Activated:Connect(function() selectMovementMode("Teleport") end))
local function setDepthFromX(x)
	local width = math.max(1, depthTrack.AbsoluteSize.X)
	local fraction = math.clamp((x - depthTrack.AbsolutePosition.X) / width, 0, 1)
	local depth = math.clamp(math.floor(-50 + fraction * 40 + 0.5), -50, -10)
	if OPTIONS.TweenDepth ~= depth then
		OPTIONS.TweenDepth = depth
		refreshMovementMode()
	end
end
track(depthTrack.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch then
		draggingDepth = true
		setDepthFromX(input.Position.X)
	end
end))
track(UserInputService.InputChanged:Connect(function(input)
	if draggingDepth and (input.UserInputType == Enum.UserInputType.MouseMovement
		or input.UserInputType == Enum.UserInputType.Touch) then
		setDepthFromX(input.Position.X)
	end
end))
track(UserInputService.InputEnded:Connect(function(input)
	if draggingDepth and (input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch) then
		draggingDepth = false
		debugEvent("MOVE", "depth_changed", { depth = OPTIONS.TweenDepth })
	end
end))
table.insert(toggleRefreshers, refreshMovementMode)
refreshMovementMode()

local machineSafety = createSubcategory(machinesBody, "SAFETY & THREATS", 3, true)
createToggleRow(machineSafety, "Auto Hide", 1, newOption(OPTIONS, "AutoHide"))
createToggleRow(machineSafety, "Look At Selena", 2, UNLOAD.selenaLook)
createInputRow(machineSafety, "Danger range (studs)", 3, function(value)
	if value and value > 0 and value < 2000 then MACHINE.Range = value end
	return MACHINE.Range
end)

local machineFlow = createSubcategory(machinesBody, "EXIT & PRIORITIES", 4, true)
createToggleRow(machineFlow, "Auto Elevator", 1, newOption(OPTIONS, "AutoElevator"))
createToggleRow(machineFlow, "Fusebox Check", 2, newOption(OPTIONS, "Fuseboxes"))
createToggleRow(machineFlow, "Items First", 3, newOption(OPTIONS, "ItemsFirst"))

local machinePerformance = createSubcategory(machinesBody, "PERFORMANCE", 5, true)
createToggleRow(machinePerformance, "Disable 3D Rendering", 1, UNLOAD.render3d)
end

local diagnosticsPage = pages.Diagnostics
local diagnosticsOverview = createSubcategory(diagnosticsPage, "SESSION OVERVIEW", 1, true)
local diagnosticsTools = createSubcategory(diagnosticsPage, "EXPORT & FILTER", 2, true)
local diagnosticsEvents = createSubcategory(diagnosticsPage, "RECENT EVENTS", 3, true)
local summaryCard = new("Frame", { Size = UDim2.new(1, -9, 0, 130),
	BackgroundColor3 = UI.surface, BorderSizePixel = 0, LayoutOrder = 1 }, diagnosticsOverview)
corner(summaryCard, 10)
uiStroke(summaryCard)
local stateLabel = uiText(summaryCard, "RUNNING", 12, true, UI.good, {
	Position = UDim2.fromOffset(13, 10), Size = UDim2.new(1, -25, 0, 21),
})
local statsLabel = uiText(summaryCard, "Collecting diagnostic counters...", 12, false, UI.text, {
	Position = UDim2.fromOffset(13, 35), Size = UDim2.new(1, -25, 0, 82),
	TextYAlignment = Enum.TextYAlignment.Top, TextWrapped = true,
})
local toolsRow = new("Frame", { Size = UDim2.new(1, -9, 0, 42),
	BackgroundTransparency = 1, LayoutOrder = 2 }, diagnosticsTools)
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
local outputStatus = uiText(diagnosticsTools, "Logs export manually, on unload, and automatically at 0 HP.", 11, false, UI.muted,
	{ Size = UDim2.new(1, -9, 0, 22), LayoutOrder = 3 })
UNLOAD.secondaryButton = new("TextButton", {
	Name = "DiagnosticsUnloadHub", Text = "UNLOAD HUB", LayoutOrder = 4,
	Size = UDim2.new(1, -9, 0, 34), BackgroundColor3 = Color3.fromRGB(92, 47, 62),
	TextColor3 = UI.text, TextSize = 12, Font = Enum.Font.GothamBold,
	BorderSizePixel = 0,
}, diagnosticsTools)
corner(UNLOAD.secondaryButton, 8)
track(UNLOAD.secondaryButton.Activated:Connect(function()
	UNLOAD.request("diagnostics_button")
end))
local logDisplay = new("TextBox", { Size = UDim2.new(1, -9, 0, 190),
	BackgroundColor3 = Color3.fromRGB(11, 14, 21), BorderSizePixel = 0,
	Text = "No events yet.", TextColor3 = Color3.fromRGB(194, 207, 232),
	TextSize = 11, Font = Enum.Font.Code, TextXAlignment = Enum.TextXAlignment.Left,
	TextYAlignment = Enum.TextYAlignment.Top, TextWrapped = true,
	TextEditable = false, MultiLine = true, ClearTextOnFocus = false,
	LayoutOrder = 4 }, diagnosticsEvents)
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
		"Mode=" .. OPTIONS.MovementMode .. " underMapDepth=" .. tostring(OPTIONS.TweenDepth),
		"Movement policy=one selected mode for all pickups and objectives",
		"Movement priority=active machine objectives preempt pickup travel; prompt spam stays at 16/s",
		"LOS=disabled for prompts and infected detection (client-side; server checks may differ)",
		"Hit attribution=nearest infected only (not confirmed attacker)",
		"Selena camera=look after Chase Started when TSelena is loaded; stops when unloaded/toggle off",
		"Machine exit=SkillCheck:InvokeServer() with no arguments; ALL exits deferred while skillcheck UI is visible",
		"Skillcheck protection=defer exits and travel until UI disappears",
		"TODO (later)=improve elevator and fusebox event / completion detection",
		"Final sweep=exits on flood-like repeated pickup failures or no progress; 90s hard cap",
		"Ability=press F once per detected machine completion; no cooldown HUD polling or Ability remote",
		"Ability input dispatched is not proof the game accepted it; active skillchecks block completion handling",
		"Item hotkeys=executor keypress preferred, VIM fallback; input success does not prove item effect",
		"AbilityConfig: " .. fieldString(ABILITY),
		"Death export=automatic when observed health <= 0 (once per life)",
		"Handoff timing=objective completion/unavailable to first prompt dispatch at next target",
		string.format("Client touch=%s promptFire=%s virtualInput=%s clipboard=%s writefile=%s",
			tostring(UserInputService.TouchEnabled), tostring(hasFirePrompt),
			tostring(pcall(function() return game:GetService("VirtualInputManager") end)),
			tostring(typeof(setclipboard) == "function"), tostring(typeof(writefile) == "function")),
		"Stats: " .. fieldString(debugStats),
		"Status: " .. fieldString(debugStatus),
		string.format("Performance: firstObjectiveMs=%d handoffs=%d averageMs=%.1f maxMs=%d lastMs=%d slowScans=%d cacheRefreshes=%d cacheHits=%d",
			debugStats.firstObjectiveMs, debugStats.handoffs,
			debugStats.handoffs > 0 and debugStats.handoffTotalMs / debugStats.handoffs or 0,
			debugStats.handoffMaxMs, debugStats.handoffLastMs, debugStats.slowMachineScans,
			debugStats.targetCacheRefreshes, debugStats.targetCacheHits),
		"Movement: " .. fieldString({ mode = OPTIONS.MovementMode, depth = OPTIONS.TweenDepth, speed = PICKUP_TRAVEL.Speed }),
		"Rendering3D=" .. (OPTIONS.Disable3DRendering and "disabled" or "enabled"),
		"SelenaCamera: " .. fieldString({ enabled = UNLOAD.selenaLook.enabled, chasing = UNLOAD.selenaLook.chaseSeen,
			tracking = UNLOAD.selenaLook.active }),
		"CapsuleSources=workspace.Capsules; workspace.Map.InfectedSamples",
		"TrashItems=Coffee; Socks; Waffle; Pristine Boots (Waffle preferred after ability)",
		string.format("Tween: arrived=%d aborted=%d hpStops=%d guards=%d pickupDistance=%d",
			debugStats.underMapTweens, debugStats.underMapAborts, debugStats.underMapHealthStops,
			debugStats.underMapGuardBlocks, debugStats.pickupTweenDistance),
		"PickupTiming=" .. (OPTIONS.CollectLast and "After" or "Before"),
		"PickupGuard: " .. fieldString({ paused = pickupCircuit.paused, failures = pickupCircuit.consecutive,
			failedTargets = pickupCircuit.distinctFailures, targetLimit = pickupCircuit.MaxTargetFailures,
			noProgressSeconds = pickupCircuit.MaxStallSeconds }),
		"Options: " .. fieldString(OPTIONS),
		"FARM: " .. fieldString(FARM),
		"MACHINE: " .. fieldString({ Range = MACHINE.Range, StallTimeout = MACHINE.StallTimeout,
			UseTimeout = MACHINE.UseTimeout, ChaseHold = MACHINE.ChaseHold,
			ItemWaitMax = MACHINE.ItemWaitMax, CollectWaitMax = MACHINE.CollectWaitMax, RescanInterval = MACHINE.RescanInterval,
			FinalSweepPoll = MACHINE.FinalSweepPoll, FinalSweepClearTime = MACHINE.FinalSweepClearTime }),
		"ItemInput: " .. fieldString({ executorKeypress = typeof(keypress) == "function",
			executorKeyrelease = typeof(keyrelease) == "function", virtualInput = pcall(function()
				return game:GetService("VirtualInputManager") end) }),
		"Enabled: " .. fieldString({ capsules = capsuleFarm.enabled, items = itemFarm.enabled,
			candy = candyFarm.enabled, machine = machineFarm.enabled,
			skillchecks = autoSkillcheck.enabled, autoUse = autoUse.enabled,
			autoAbility = autoAbility.enabled, autoTrashUse = ITEM_OPTIONS.AutoTrashUse }),
		string.format("LogEvents=%d Retained=%d Dropped=%d", debugIndex,
			math.min(debugIndex, LOG_LIMIT), math.max(0, debugIndex - LOG_LIMIT)),
		"---- EVENTS (chronological) ----",
	}
	for _, line in ipairs(allDebugLines()) do table.insert(summary, line) end
	return table.concat(summary, "\n")
end
writeDebugFile = function(reason)
	reason = reason or "manual"
	local function showExportStatus(message)
		pcall(function()
			if outputStatus and outputStatus.Parent then outputStatus.Text = message end
		end)
	end
	debugEvent("DEBUG", "export_requested", { reason = reason })
	if typeof(writefile) ~= "function" then
		debugEvent("DEBUG", "export_failed", { reason = "writefile unavailable" }, "WARN")
		showExportStatus("Export unavailable. Try Copy Log instead.")
		return false
	end
	local prefix = reason == "death" and "TU_Rava_Hub_DEATH_Debug_" or "TU_Rava_Hub_Debug_"
	local filename = prefix .. os.time() .. "_" .. math.floor((os.clock() % 1) * 100000) .. ".txt"
	local ok, err = pcall(writefile, filename, debugReport())
	if ok then
		showExportStatus("Saved: " .. filename)
		debugEvent("DEBUG", "export_success", { filename = filename, reason = reason })
		return true
	end
	showExportStatus("Export failed: " .. tostring(err):sub(1, 70))
	debugEvent("DEBUG", "export_failed", { error = err, reason = reason }, "ERROR")
	return false
end
UNLOAD.exporter = function()
	return writeDebugFile("unload")
end
track(exportButton.MouseButton1Click:Connect(function() writeDebugFile("manual") end))
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
		if main.Visible then for _, refresh in ipairs(toggleRefreshers) do refresh() end end
		local working = (machineFarm.enabled and "MACHINE") or (pickupBusy() and "PICKUPS") or "IDLE"
		headerStatus.Text = working .. "  •  v2.6.5"
		headerStatus.TextColor3 = working == "IDLE" and UI.muted or UI.good
		footerLabel.Text = string.format("%s   •   %s   •   %d moves", BUILD, OPTIONS.MovementMode,
			debugStats.teleports + debugStats.underMapTweens)
		if activeTab == "Diagnostics" and main.Visible then
			stateLabel.Text = "Target: " .. debugStatus.currentTarget .. "  |  Last handoff: " .. tostring(debugStats.handoffLastMs) .. "ms"
			statsLabel.Text = string.format("Hits %d  |  Damage %.1f  |  Handoffs %d (avg %.0fms)\nTeleports %d  |  Pickups %d/%d  |  ESP %d active\nMachines %d done  |  Stalls %d  |  Errors %d\nAbilities %d  |  Trash inputs %d  |  Death logs %d",
				debugStats.hits, debugStats.totalDamage, debugStats.handoffs,
				debugStats.handoffs > 0 and debugStats.handoffTotalMs / debugStats.handoffs or 0,
				debugStats.teleports, debugStats.pickupConfirmed, debugStats.pickupAttempts,
				math.max(0, debugStats.espAdded - debugStats.espRemoved),
				debugStats.machineCompletions, debugStats.machineStalls, debugStats.workerErrors,
				debugStats.abilityDispatched, debugStats.trashUseInputs, debugStats.deathExports)
			local logs = recentDebugLines(11, warningsOnly)
			logDisplay.Text = #logs > 0 and table.concat(logs, "\n") or "No matching events yet."
		end
		task.wait(0.7)
	end
end)
UNLOAD.fullDiagnostics = true
pcall(function()
	for _, item in ipairs(diagnosticsPage:GetChildren()) do
		if item.Name == "DiagnosticsStartupNotice" or item.Name == "DiagnosticsStartupExport"
			or item.Name == "DiagnosticsStartupUnload" then item:Destroy() end
	end
end)
debugEvent("SYSTEM", "initialized", { build = BUILD, place = game.PlaceId,
	startupChecks = "passed", fallbackExport = true,
    diagnosticsTab = menuButtons.Diagnostics ~= nil and pages.Diagnostics ~= nil,
    diagnosticsDock = diagnosticsDock.Parent ~= nil, ui = "collapsible_subcategories",
	mode = OPTIONS.MovementMode, underMapDepth = OPTIONS.TweenDepth, selenaCamera = true,
	lineOfSight = "disabled", abilityAuto = true, abilityTrigger = "F_after_machine_completion", sampleFarm = true, pickupSpeed = PICKUP_TRAVEL.Speed,
	enemyClearance = PICKUP_TRAVEL.SafetyRadius, pickupSettle = FARM.Settle,
	pickupDwell = FARM.Dwell, pickupRate = FARM.SpamRate, itemWaitMax = MACHINE.ItemWaitMax })
task.spawn(function()
	local previous = {}
	while alive do
		for _, folderName in ipairs({ "Items", "Capsules", "Map.InfectedSamples", "Candies", "Computers", "OilMachines", "MonsterFolder" }) do
			local folder = resolveWorkspacePath(folderName)
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

UNLOAD.handler = function(source)
	debugEvent("SYSTEM", "unload", {
		source = source or "requested",
		elapsed = string.format("%.2f", os.clock() - debugStart),
	})
	cancelMotion()
	UNLOAD.force(source)
end
