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

local old = playerGui:FindFirstChild("TURavaHubGUI")
if old then old:Destroy() end
local staleBlackout = playerGui:FindFirstChild("TURavaHubBlackout")
if staleBlackout then staleBlackout:Destroy() end
sweepHighlights()

local connections = {}
local cleanups = {}

local UNLOAD = { gui=nil,handler=nil,active=false,exporter=nil,
	restoreLOS=function() end,restoreRendering=function() end,
	cancelMovement=function() end,render3d={ enabled=false },fullDiagnostics=false }
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
		if not ok then warn("[TU Rava Hub] cleanup error: " .. tostring(err)) end
	end
	table.clear(cleanups)
	pcall(UNLOAD.restoreLOS)
	pcall(sweepHighlights)
	task.spawn(function()
		pcall(function() if UNLOAD.exporter then UNLOAD.exporter() end end)
	end)
end
function UNLOAD.request(source)
	if UNLOAD.active then return end
	if UNLOAD.handler then
		local ok, err = pcall(UNLOAD.handler, source or "requested")
		if ok then return end
		warn("[TU Rava Hub] unload handler failed; forcing shutdown: " .. tostring(err))
	end
	UNLOAD.force(source or "fallback")
end

local OPTIONS = {
	AutoHide=true, AutoElevator=true,
	Fuseboxes=true,
	MovementMode="Teleport",TweenDepth=-15,Disable3DRendering=false,
}

local BUILD = "TU Rava Hub v2.6.48"
local debugStart = os.clock()
local LOG_LIMIT = 4000
local debugLines, debugIndex, debugLast = {}, 0, {}
local debugStats = {
	teleports=0,teleportFailures=0,unsafeDestinations=0,
	renderToggles=0,renderErrors=0,
	pickupTweens=0,underMapTweens=0,underMapAborts=0,underMapHealthStops=0,underMapGuardBlocks=0,
	pickupPreemptions=0,pickupRouteCooldowns=0,
	pickupChasesIgnored=0,
	pickupSafetyScans=0,pickupLoSExposed=0,pickupSafetySkips=0,
	pickupDangerEvades=0,pickupCooldownInterrupts=0,
	pickupRepeatBlocks=0,pickupCircuitTrips=0,pickupCircuitResets=0,
	pickupFailedInteractions=0,pickupContactRetries=0,pickupContactRecovered=0,pickupContactFailed=0,
	promptMovePulses=0,promptMoveVerified=0,promptMoveStationary=0,promptMoveBlocked=0,
	promptWalkKeyInputs=0,promptWalkVerified=0,promptWalkRetries=0,
	machineNearFinishHeld=0,machineChaseDeferred=0,finalSafeMoves=0,finalSafeFailures=0,
	elevatorWatchStarts=0,elevatorFallbacks=0,elevatorFallbackSuccess=0,elevatorFallbackFailures=0,
	elevatorHoldCorrections=0,elevatorDeaths=0,
	pickupBeforeWaits=0,pickupBeforeCompleted=0,pickupBeforeTimeouts=0,masterToggles=0,
	elevatorPlatformDetections=0,elevatorUncertainArrivals=0,elevatorGeometryMisses=0,
	pickupTweenDistance=0,pickupTravelMs=0,
	pickupAttempts=0,pickupConfirmed=0,pickupUnconfirmed=0,
	promptAttempts=0,promptFailures=0,machineTargetChanges=0,
	promptAlternateSelected=0,promptShownEvents=0,promptHiddenEvents=0,
	nestedProgressResolutions=0,machineInitialPromptRetries=0,
	promptSeatAttempts=0,promptSeatVerified=0,promptSeatBlocked=0,
	promptOrbitAttempts=0,promptOrbitMoves=0,promptOrbitConfirmed=0,
	promptOrbitBlocked=0,promptOrbitTimeouts=0,promptOrbitFires=0,
	pickupOrbitRecoveries=0,machineOrbitRecoveries=0,
	pickupPromptReplacements=0,machinePromptFallbacks=0,
	pickupNearestRoutes=0,
	pickupSnakeSkipped=0,pickupSnakeInterrupted=0,pickupSnakeEscapes=0,
	snakeGuardsCreated=0,snakeGuardsRemoved=0,snakeGuardsMoved=0,snakeUnderPickupDetected=0,
	elevatorHoldChecks=0,elevatorHoldUncertain=0,
	elevatorAlternateAttempts=0,elevatorAlternateMoves=0,
	elevatorAlternateUnavailable=0,elevatorStateConfirmed=0,
	elevatorCandidateScans=0,elevatorGenericFloors=0,
	elevatorFallbackVerified=0,elevatorFallbackUnverified=0,
	elevatorMissingStatusRecovered=0,elevatorFastDispatch=0,
	elevatorRoundResets=0,urgentMachineExits=0,
	elevatorWideScans=0,elevatorFarAlternateAttempts=0,
	elevatorAlternateCommitted=0,elevatorServerRelocations=0,
	elevatorTransitionHolds=0,elevatorLastResortRetries=0,
	elevatorBackupRejected=0,elevatorUnverifiedBackupUsed=0,
	elevatorEntryMoves=0,elevatorEntryMoved=0,elevatorEntryUnsafeSkipped=0,
	elevatorContactWalks=0,elevatorContactWalkSteps=0,elevatorContactWalkMoved=0,
	elevatorRecoveryScheduled=0,elevatorRecoveryDispatched=0,elevatorRecoveryExhausted=0,
	fuseLocatedDisabled=0,fuseDynamicFound=0,fuseActivationUnverified=0,
    blackoutFuseFound=0,blackoutFuseCollected=0,blackoutFuseUnsafe=0,
    blackoutBoxDispatches=0,blackoutBoxFallbacks=0,blackoutBoxMissing=0,
	machineExitFlightWaits=0,damageRetreatTriggers=0,
	autoHideExitRequests=0,autoHideExitSent=0,autoHideExitDuringSkillcheck=0,
	autoHideExitQueued=0,autoHideExitEventFailures=0,
	chaseThreatRetreats=0,survivalMilestones=0,
	machineStalls=0,skillcheckInputs=0,skillcheckInputFailures=0,
	skillcheckRebinds=0,skillcheckInputSignal=0,skillcheckInputVIM=0,
	skillcheckRoundSeen=0,skillcheckBarSeen=0,skillcheckMissingParts=0,
	skillcheckLateAttached=0,skillcheckRearms=0,skillcheckUiRecreated=0,
	skillcheckWatchErrors=0,skillcheckFrameConnections=0,
	chases=0,workerErrors=0,machineCompletions=0,
	machinePlacements=0,machineDangers=0,fuseAttempts=0,
	itemUseAttempts=0,itemUseFailures=0,itemUseObserved=0,itemUseUnverified=0,
	abilityCompletionTriggers=0,abilityInputFailures=0,abilityInputDeferred=0,
	abilityAttempts=0,abilityDispatched=0,
	abilityWaffles=0,abilityWaffleFailures=0,
	trashUseAttempts=0,trashUseInputs=0,trashUseFailures=0,
	trashAbilityInputs=0,trashIdleInputs=0,
	skillcheckExitAttempts=0,skillcheckExitFailures=0,
	deathExports=0,deathExportFailures=0,
	skillcheckLeaveDeferred=0,skillcheckMoveBlocked=0,
	hits=0,totalDamage=0,nearestEnemyMissing=0,
	espAdded=0,espRemoved=0,espUpdates=0,
	squidTentaclesRemoved=0,squidTentacleErrors=0,
	targetCacheRefreshes=0,targetCacheHits=0,
	handoffs=0,handoffTotalMs=0,handoffMaxMs=0,
	handoffLastMs=0,firstObjectiveMs=0,machineScans=0,slowMachineScans=0,
	completionWakeups=0,fastHandoffs=0,fastPromptDispatches=0,
	threatPredictions=0,threatProximityAlerts=0,instantHideMoves=0,
	soundComputerDone=0,soundOilDone=0,soundMainReady=0,soundElevatorDoor=0,
	soundMainFlush=0,soundMainFlushDoor=0,soundMainFlushCorroborated=0,
	soundElevatorCountdownStop=0,soundElevatorCountdownAccepted=0,
	soundElevatorCountdownUnverified=0,
	soundElevatorDoorClosing=0,soundFloorTransitions=0,soundFloorTransitionResets=0,
	doorClosingIgnoredDuringWork=0,hideStarts=0,hideRetreats=0,hideWaitTicks=0,
	hideResumes=0,hideSaferTargets=0,hideNoShelter=0,hideDangerStays=0,
	soundElevatorSelections=0,soundElevatorReroutes=0,soundElevatorUnmappedDoor=0,soundElevatorSoundFallbacks=0,
	soundDoneRecovered=0,soundDoneAmbiguous=0,objectiveLateValueBinds=0,
	completedSkillcheckHandoffs=0,pickupOrbitsSuppressed=0,elevatorTeleportSteps=0,
	soundMainCompleted=0,soundMainCompletedDoor=0,soundMainCompletionVerified=0,
	soundBlackout=0,soundBlackoutDispatches=0,soundBlackoutDeferred=0,
	soundWakeups=0,soundHandoffs=0,soundIgnored=0,
	voidLandingsBlocked=0,voidDropsDetected=0,voidRecoveries=0,voidRecoveryFailures=0,
	voidCircuitTrips=0,voidSurfaceSnapshots=0,voidTweenRoutesBlocked=0,
}
-- Tracks the user's actual goal: 1,000 machine completions without reaching 0 HP.
-- Total machine completions remain separate because a cumulative count would
-- not demonstrate a deathless streak.
local GOAL = { Target=1000, Streak=0, Best=0, Deaths=0, Achieved=false }
local debugStatus = { action="Ready",lastWarning="None",currentTarget="None",
	lastHit="None",lastHandoff="None",handoffPending="None" }
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
-- Draw black behind the game's 2D UI while the 3D scene is disabled.
-- A separate low-DisplayOrder ScreenGui keeps the hub and skillchecks visible.
function UNLOAD.render3d.removeBlackout()
	local overlay = UNLOAD.render3d.blackout
	UNLOAD.render3d.blackout = nil
	if overlay then pcall(function() overlay:Destroy() end) end
	local leftover = playerGui:FindFirstChild("TURavaHubBlackout")
	if leftover then pcall(function() leftover:Destroy() end) end
end
function UNLOAD.render3d.createBlackout()
	local overlay = Instance.new("ScreenGui")
	overlay.Name = "TURavaHubBlackout"
	overlay.ResetOnSpawn = false
	overlay.IgnoreGuiInset = true
	overlay.DisplayOrder = -1000
	overlay.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	pcall(function() overlay.ScreenInsets = Enum.ScreenInsets.None end)
	local background = Instance.new("Frame")
	background.Name = "BlackBackground"
	background.Size = UDim2.fromScale(1, 1)
	background.Position = UDim2.fromScale(0, 0)
	background.BackgroundColor3 = Color3.new(0, 0, 0)
	background.BackgroundTransparency = 0
	background.BorderSizePixel = 0
	background.Active = false
	background.Parent = overlay
	overlay.Parent = playerGui
	return overlay
end
function UNLOAD.render3d.enable()
	local ok, err = pcall(function()
		UNLOAD.render3d.removeBlackout()
		UNLOAD.render3d.blackout = UNLOAD.render3d.createBlackout()
		RunService:Set3dRenderingEnabled(false)
	end)
	if not ok then
		UNLOAD.render3d.removeBlackout()
		increment("renderErrors")
		debugEvent("RENDER", "disable_failed", { error=tostring(err) }, "ERROR")
		error(err, 0)
	end
	UNLOAD.render3d.enabled = true
	OPTIONS.Disable3DRendering = true
	increment("renderToggles")
	debugEvent("RENDER", "disabled_3d", { background="black" })
end
function UNLOAD.render3d.disable()
	local ok, err = pcall(function() RunService:Set3dRenderingEnabled(true) end)
	if not ok then
		increment("renderErrors")
		debugEvent("RENDER", "restore_failed", { error=tostring(err) }, "ERROR")
		error(err, 0)
	end
	UNLOAD.render3d.removeBlackout()
	UNLOAD.render3d.enabled = false
	OPTIONS.Disable3DRendering = false
	increment("renderToggles")
	debugEvent("RENDER", "enabled_3d")
end
UNLOAD.restoreRendering = function()
	if UNLOAD.render3d.enabled then
		UNLOAD.render3d.disable()
	else
		UNLOAD.render3d.removeBlackout()
	end
end

local function debugLog(message)
	local msg = tostring(message)
	local category = msg:find("pickup") and "PICKUP"
		or (msg:find("machine") or msg:find("progress") or msg:find("place ")) and "MACHINE"
		or msg:find("skillcheck") and "SKILLCHECK" or "SYSTEM"
	local level = msg:find("^ERROR") and "ERROR" or "INFO"
	debugEvent(category, "legacy", { message=msg }, level)
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
		"TU Rava Hub | Startup / Fallback Diagnostic Report",
		"Build=" .. BUILD,
		"Exported=" .. os.date("%Y-%m-%d %H:%M:%S"),
		"PlaceId=" .. tostring(game.PlaceId) .. " JobId=" .. tostring(game.JobId),
		"FullDiagnostics=" .. tostring(UNLOAD.fullDiagnostics),
		"Stats: " .. fieldString(debugStats),
		"Goal: " .. fieldString(GOAL),
		"Status: " .. fieldString(debugStatus),
		"---- EVENTS ----",
	}
	for _, event in ipairs(allDebugLines()) do table.insert(summary, event) end
	return table.concat(summary, "\n")
end
UNLOAD.fallbackExport = function(reason)
	if typeof(writefile) ~= "function" then
		debugEvent("DEBUG", "fallback_export_unavailable", { reason=reason }, "WARN")
		return false
	end
	local prefix = reason == "death" and "TU_Rava_Hub_DEATH_Debug_"
		or ("TU_Rava_Hub_" .. tostring(reason or "STARTUP") .. "_Debug_")
	local filename = prefix .. os.time() .. "_" .. math.floor((os.clock() % 1) * 100000) .. ".txt"
	local ok, err = pcall(writefile, filename, UNLOAD.fallbackReport())
	debugEvent("DEBUG", ok and "fallback_export_saved" or "fallback_export_error",
		{ filename=filename,reason=reason,error=ok and "none" or tostring(err) }, ok and "INFO" or "ERROR")
	return ok
end
UNLOAD.exporter = function() return UNLOAD.fallbackExport("UNLOAD") end

local activeMotion
local skillcheckProtected -- Initialized after GUI visibility helpers are defined.
local infectedNear -- Assigned after monster-folder helpers are defined.
local motionPauseUntil = 0
UNLOAD.imminentEvacuationUntil = 0
UNLOAD.damageRetreatSerial = 0
local PICKUP_TRAVEL = {
	Speed=360,ElevatorSpeed=900,SafetyRadius=24,ArriveTolerance=4.5,
}
local function cancelMotion(owner)
	if UNLOAD.abortOrbit then UNLOAD.abortOrbit() end
	local motion = activeMotion
	if motion and (not owner or motion.owner == owner) then
		activeMotion = nil
		motion.cancelled = true
		if motion.tween then pcall(function() motion.tween:Cancel() end) end
		local recoverySucceeded = nil
		if motion.returnSurface then
			motion.unloading = true
			local ok, restored = pcall(motion.returnSurface)
			recoverySucceeded = ok and restored == true
			if not recoverySucceeded then
				debugEvent("MOVE", "cancel_surface_recovery_failed", {
					owner=motion.owner,phase=motion.phase or "unknown",
				}, "WARN")
			end
		end
		if motion.restore then pcall(motion.restore) end
		debugEvent("MOVE", "cancel", { owner=motion.owner,
			phase=motion.phase or "unknown",surfaced=recoverySucceeded })
	end
end
UNLOAD.cancelMovement = cancelMotion

-- Avoid sending the character into missing collision geometry (especially
-- the elevator's old unverified -20-stud fallback). An AFK session should
-- prefer a skipped objective to falling below the map and losing a life.
do
    local guard = { blocked=false, recovering=false, safeCFrame=nil,
        safeMap=nil, safePart=nil, safeAt=0, previousRoot=nil,
        sampleAt=0, recentRecoveries={}, lastMovementAt=0 }
    UNLOAD.voidGuard = guard

    local function floorBelow(point, maxDrop, character)
        if typeof(point) ~= "Vector3" then return nil end
        if point.Y <= workspace.FallenPartsDestroyHeight + 25 then return nil end
        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        local ignore = {}
        if character then table.insert(ignore, character) end
        local snakePlates = workspace:FindFirstChild("TU_Rava_SnakeGuards")
        if snakePlates then table.insert(ignore, snakePlates) end
        params.FilterDescendantsInstances = ignore
        pcall(function() params.RespectCanCollide = true end)
        -- Several passes ignore decorative, transparent or non-collidable
        -- surfaces without ignoring legitimate glass or solid platforms.
        for attempt=1,7 do
            local hit = workspace:Raycast(point + Vector3.new(0,2,0),
                Vector3.new(0,-(maxDrop+2),0),params)
            if not hit then return nil end
            local part = hit.Instance
            local vertical = point.Y - hit.Position.Y
            if hit.Normal.Y >= 0.48 and vertical >= -0.15 and vertical <= maxDrop
                and (part == workspace.Terrain or (part and part.CanCollide)) then
                return hit
            end
            if not part then return nil end
            table.insert(ignore,part)
            params.FilterDescendantsInstances=ignore
        end
        return nil
    end

    function guard.landingOK(where, owner)
        if guard.blocked or guard.recovering then return false,"recovery_locked" end
        if typeof(where) ~= "Vector3" then return false,"invalid_position" end
        if where.Y <= workspace.FallenPartsDestroyHeight + 35 then
            return false,"near_destroy_height"
        end
        local character=player.Character
        -- The approach to a prompt may be somewhat higher than the ground;
        -- require a genuinely collidable floor in the landing column.
        if not floorBelow(where,22,character) then
            return false,"no_supported_landing"
        end
        return true,"ground_found"
    end

    function guard.noteMove(owner,where)
        guard.lastMovementAt=os.clock()
    end

    function guard.recover(reason, root)
        if guard.recovering or guard.blocked then return false end
        guard.recovering=true
        local character=player.Character
        local humanoid=character and character:FindFirstChildOfClass("Humanoid")
        local safe=guard.safeCFrame
        local sameMap=guard.safeMap == workspace:FindFirstChild("Map")
        -- A saved platform from the previous floor is not a safe destination.
        local valid=safe and sameMap and guard.safePart and guard.safePart.Parent
            and floorBelow(safe.Position,10,character)
        local ok=false
        motionPauseUntil=math.max(motionPauseUntil,os.clock()+2.0)
        if valid and character and root and root.Parent and humanoid
            and humanoid.Health > 0 then
            pcall(cancelMotion)
            if UNLOAD.abortOrbit then pcall(UNLOAD.abortOrbit) end
            ok=pcall(function()
                root.Anchored=false
                root.AssemblyLinearVelocity=Vector3.zero
                root.AssemblyAngularVelocity=Vector3.zero
                root.CFrame=(safe+Vector3.new(0,1.5,0))
            end)
            ok=ok and root.Parent ~= nil
                and (root.Position-(safe.Position+Vector3.new(0,1.5,0))).Magnitude < 7
        end
        if ok then
            increment("voidRecoveries")
            local now=os.clock()
            table.insert(guard.recentRecoveries,now)
            while #guard.recentRecoveries > 0
                and now-guard.recentRecoveries[1] > 30 do
                table.remove(guard.recentRecoveries,1)
            end
            if #guard.recentRecoveries >= 3 then
                -- Repeated recoveries indicate a bad map/route: lock motion.
                guard.blocked=true
                increment("voidCircuitTrips")
            end
        else
            increment("voidRecoveryFailures")
            -- No proven support => stop all future automated movements.
            guard.blocked=true
        end
        debugEvent("VOID",ok and "safe_position_restored" or "recovery_failed",{
            reason=reason,restored=ok,locked=guard.blocked,
            rootY=root and math.floor(root.Position.Y) or "missing",
            savedY=safe and math.floor(safe.Position.Y) or "none",
            mapMatched=sameMap,
        },ok and "WARN" or "ERROR")
        guard.recovering=false
        return ok
    end

    local elapsed=0
    local conn=RunService.Heartbeat:Connect(function(dt)
        if not alive or guard.recovering or guard.blocked then return end
        elapsed+=dt
        if elapsed < 0.08 then return end
        elapsed=0
        local character=player.Character
        local root=character and character:FindFirstChild("HumanoidRootPart")
        local humanoid=character and character:FindFirstChildOfClass("Humanoid")
        if not root or not root.Parent or not humanoid or humanoid.Health <= 0 then return end
        if root ~= guard.previousRoot then
            guard.previousRoot=root
            guard.safeCFrame=nil
            guard.safePart=nil
            guard.safeMap=nil
            guard.safeAt=0
            guard.recentRecoveries={}
        end
        local pos=root.Position
        local time=os.clock()
        local supported=(not root.Anchored and not activeMotion)
            and floorBelow(pos,8,character)
        if supported then
            -- A stable landing snapshot is trustworthy only with solid support.
            if (not guard.safeCFrame) or time-guard.safeAt > 0.20 then
                guard.safeCFrame=root.CFrame
                guard.safePart=supported.Instance
                guard.safeMap=workspace:FindFirstChild("Map")
                guard.safeAt=time
                increment("voidSurfaceSnapshots")
            end
            return
        end
        local lowerThanSafe=guard.safeCFrame
            and pos.Y < guard.safeCFrame.Position.Y - 17
        local nearKillHeight=pos.Y <= workspace.FallenPartsDestroyHeight + 45
        local falling=root.AssemblyLinearVelocity.Y < -12
        -- Only recover when there's no ground within a generous lower column.
        -- This avoids interrupting normal jumps and server floor transitions.
        local farBelowSafe=guard.safeCFrame
            and pos.Y < guard.safeCFrame.Position.Y - 35
        if (nearKillHeight or (lowerThanSafe and falling) or farBelowSafe)
            and not floorBelow(pos,30,character) then
            increment("voidDropsDetected")
            guard.recover(nearKillHeight and "kill_height" or "falling_below_floor",root)
        end
    end)
    table.insert(connections,conn)
    table.insert(cleanups,function() guard.blocked=true end)
end

local function instantTeleport(destination, keepGoing, owner, mode)
	local emergency = mode == "emergency" or mode == "elevator" or mode == "hide"
	if not alive or not keepGoing() then return false end
	if owner == "pickup" and UNLOAD.pickupSnakeUnsafe
		and UNLOAD.pickupSnakeUnsafe(nil,destination.Position) then
		debugThrottled("pickup_snake_teleport",1,"SNAKES","destination_blocked",{},"WARN")
		return false
	end
	local protected, checkType = false, "not_ready"
	if skillcheckProtected then protected, checkType = skillcheckProtected() end
	-- Only a corroborated completion permits the next machine handoff while
	-- a completed skillcheck GUI is still fading out. Never bypass for pickups.
	local verifiedHandoff = owner == "machine" and (mode == "fast" or mode == "handoff")
		and os.clock() < (UNLOAD.verifiedHandoffUntil or 0)
	if protected and not verifiedHandoff and not (emergency and owner == "machine"
		and os.clock() <= (UNLOAD.imminentEvacuationUntil or 0)) then
		increment("skillcheckMoveBlocked")
		debugThrottled("skillcheck_teleport_block_" .. tostring(owner), 1.5,
			"SKILLCHECK", "teleport_deferred", { owner=owner,mode=mode or "routine",ui=checkType }, "INFO")
		return false
	end
	if verifiedHandoff and protected then
		increment("completedSkillcheckHandoffs")
	end
	if owner == "machine" and activeMotion and activeMotion.owner == "pickup" then
		debugEvent("MOVE", "machine_preempts_pickup_tween", { phase=activeMotion.phase or "unknown" }, "WARN")
		cancelMotion("pickup")
	end
	if activeMotion and not emergency then
		debugThrottled("move_busy_" .. owner, 3, "MOVE", "occupied", { owner=owner }, "WARN")
		return false
	end
	if emergency then
		cancelMotion()
		motionPauseUntil = math.max(motionPauseUntil, os.clock() + 1.5)
	end
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsDescendantOf(workspace) then
		debugThrottled("root_" .. owner, 5, "MOVE", "root_missing", { owner=owner }, "WARN")
		return false
	end
	local landingOK, landingWhy = UNLOAD.voidGuard.landingOK(destination.Position,owner)
	if not landingOK then
		increment("voidLandingsBlocked")
		debugThrottled("unsafe_landing_"..tostring(owner),1.5,"VOID",
			"teleport_rejected",{ owner=owner,reason=landingWhy,
			to=tostring(destination.Position) },"WARN")
		return false
	end
	local from = root.Position
	local distance = (from - destination.Position).Magnitude
	if distance < 0.25 then return true end
	if not emergency and infectedNear and infectedNear(destination.Position, 15) then
		increment("unsafeDestinations")
		debugThrottled("unsafe_" .. owner, 3, "MOVE", "unsafe_destination",
			{ owner=owner,position=tostring(destination.Position) }, "WARN")
		return false
	end
	local ok, err = pcall(function()
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
		root.CFrame = destination
	end)
	if not ok then
		increment("teleportFailures")
		debugEvent("MOVE", "teleport_error", { owner=owner,error=err }, "ERROR")
		return false
	end
	local drift = (root.Position - destination.Position).Magnitude
	if drift > 4 then
		increment("teleportFailures")
		debugThrottled("drift_" .. owner, 1, "MOVE", "arrival_mismatch",
			{ owner=owner,drift=string.format("%.2f",drift),target=tostring(destination.Position) }, "WARN")
		return false
	end
	UNLOAD.voidGuard.noteMove(owner,destination.Position)
	increment("teleports")
	debugEvent("MOVE", "teleport", {
		owner=owner,mode=emergency and "emergency" or "routine",
		distance=string.format("%.1f",distance),to=tostring(destination.Position),
	})
	return true
end

local function tweenUnderMap(destination, keepGoing, owner, mode)
	local emergency = mode == "emergency" or mode == "elevator" or mode == "hide"
	if not alive or not keepGoing() then return false, "inactive" end
	if owner == "pickup" and UNLOAD.pickupSnakeUnsafe
		and UNLOAD.pickupSnakeUnsafe(nil,destination.Position) then
		return false,"snake_destination"
	end
	if skillcheckProtected and skillcheckProtected()
		and not (emergency and owner == "machine"
			and os.clock() <= (UNLOAD.imminentEvacuationUntil or 0)) then
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
	local landingOK,landingWhy=UNLOAD.voidGuard.landingOK(goal,owner)
	if not landingOK then
		increment("voidLandingsBlocked")
		debugThrottled("bad_tween_landing_"..tostring(owner),2,"VOID",
			"tween_rejected",{owner=owner,reason=landingWhy},"WARN")
		return false,landingWhy
	end
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
		debugEvent("MOVE", "depth_blocked", { requestedY=cruiseY,destroyY=destroyY,
			depth=OPTIONS.TweenDepth,owner=owner }, "WARN")
		return false, "near_destroy_height"
	end
	local points = {
		Vector3.new(from.X,cruiseY,from.Z),
		Vector3.new(goal.X,cruiseY,goal.Z),
		goal,
	}
	local motion = { owner=owner,phase="descent",cancelled=false }
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
		if not root.Parent then return false end
		if not root.Anchored then return (root.Position - from).Magnitude <= PICKUP_TRAVEL.ArriveTolerance end
		local ok, tween = pcall(function()
			return TweenService:Create(root, TweenInfo.new(0.12, Enum.EasingStyle.Linear),
				{ CFrame=CFrame.new(from) })
		end)
		if not ok then return false end
		local played = pcall(function() tween:Play() end)
		if not played then return false end
		local deadline = os.clock() + 0.23
		while tween.PlaybackState == Enum.PlaybackState.Playing
			and os.clock() < deadline and root.Parent do
			RunService.Heartbeat:Wait()
		end
		return root.Parent ~= nil and (root.Position - from).Magnitude <= PICKUP_TRAVEL.ArriveTolerance
	end
	local function abort(reason)
		local stillOwns = activeMotion == motion
		motion.cancelled = true
		if motion.tween then pcall(function() motion.tween:Cancel() end) end
		if stillOwns and character == player.Character and root.Parent and health() ~= 0 then
			local surface = CFrame.new(from)
			local recovered, recovery = pcall(function()
				return TweenService:Create(root, TweenInfo.new(0.12, Enum.EasingStyle.Linear),
					{ CFrame=surface })
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
		debugEvent("MOVE", "undermap_abort", { owner=owner,reason=reason,
			elapsedMs=math.floor((os.clock() - startAt) * 1000 + 0.5),
			depth=OPTIONS.TweenDepth }, "WARN")
		return false, reason
	end
	debugEvent("MOVE", "undermap_start", { owner=owner,depth=OPTIONS.TweenDepth,
			cruiseY=string.format("%.1f",cruiseY),
			distance=string.format("%.1f",(from - goal).Magnitude) })
	local length = 0
	for i, point in ipairs(points) do
		if motion.cancelled or activeMotion ~= motion or not keepGoing() then
			return abort("interrupted")
		end
		local distance = (root.Position - point).Magnitude
		if distance > 0.2 then
			motion.phase = ({ "descent","underground","ascent" })[i]
			if i == 3 and not emergency and infectedNear and infectedNear(goal,
				owner == "pickup" and PICKUP_TRAVEL.SafetyRadius or 15) then
				return abort("enemy_at_destination")
			end
			local routeSpeed = mode == "elevator" and PICKUP_TRAVEL.ElevatorSpeed or PICKUP_TRAVEL.Speed
			local duration = math.max(0.04, distance / routeSpeed)
			local ok, tween = pcall(function()
				return TweenService:Create(root, TweenInfo.new(duration, Enum.EasingStyle.Linear),
					{ CFrame=CFrame.new(point) * (destination - destination.Position) })
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
				if skillcheckProtected and skillcheckProtected()
					and not (emergency and owner == "machine"
						and os.clock() <= (UNLOAD.imminentEvacuationUntil or 0)) then
					return abort("skillcheck_visible")
				end
				if os.clock() > deadline then return abort("tween_stalled") end
				if owner == "pickup" and UNLOAD.pickupSnakeUnsafe
					and UNLOAD.pickupSnakeUnsafe(nil,root.Position) then
					return abort("snake_under_route")
				end
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
	debugEvent("MOVE", "undermap_arrived", { owner=owner,depth=OPTIONS.TweenDepth,
			ms=math.floor((os.clock() - startAt) * 1000 + 0.5) })
	return true, "undermap"
end

local function teleportCharacter(destination, keepGoing, owner, mode)
	-- Any new route cancels an in-progress local contact orbit.
	if UNLOAD.abortOrbit then UNLOAD.abortOrbit() end
	-- Objective handoffs and Auto Hide are latency-critical: use one-frame
	-- teleport even when under-map tweening is selected for routine routes.
	if owner == "machine" and (mode == "handoff" or mode == "hide") then
		return instantTeleport(destination, keepGoing, owner,
			mode == "hide" and "emergency" or "fast")
	end
	-- AFK movement is always surface teleport: anchored under-map tweens can
	-- strand the character beneath a removed platform or moving elevator.
	if owner == "machine" or owner == "pickup" or owner == "return" then
		if OPTIONS.MovementMode == "Tween" then
			increment("voidTweenRoutesBlocked")
		end
		return instantTeleport(destination, keepGoing, owner, mode)
	end
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
			warn("[TU Rava Hub] " .. label .. " error: " .. tostring(err))
			increment("workerErrors")
			debugEvent("WORKER", "crashed", { worker=label,error=tostring(err),retry="0.5s" }, "ERROR")
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
		debugEvent("TSQUID", "tentacle_removed", { source=reason,class=className })
	else
		increment("squidTentacleErrors")
		debugThrottled("squid_delete_failed", 2, "TSQUID", "tentacle_remove_failed",
			{ source=reason,error=err }, "ERROR")
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

local function corner(parent, radius) return new("UICorner", { CornerRadius=UDim.new(0,radius) }, parent) end

local function list(parent, padding, align)
	return new("UIListLayout", {
		Padding=UDim.new(0,padding), SortOrder=Enum.SortOrder.LayoutOrder,
		HorizontalAlignment=align or Enum.HorizontalAlignment.Left,
	}, parent)
end

local UI = {
	background=Color3.fromRGB(15,18,27),surface=Color3.fromRGB(23,28,39),
	surface2=Color3.fromRGB(32,38,52),soft=Color3.fromRGB(40,48,65),
	accent=Color3.fromRGB(113,124,255),blue=Color3.fromRGB(80,192,255),
	good=Color3.fromRGB(70,207,148),bad=Color3.fromRGB(230,102,118),
	text=Color3.fromRGB(238,241,252),muted=Color3.fromRGB(147,156,180),
}
local function uiText(parent, value, size, bold, color, props)
	local config = { BackgroundTransparency=1,Text=value,TextColor3=color or UI.text,
		TextSize=size or 14,Font=bold and Enum.Font.GothamBold or Enum.Font.Gotham,
		TextXAlignment=Enum.TextXAlignment.Left,BorderSizePixel=0 }
	for k, v in pairs(props or {}) do config[k] = v end
	return new("TextLabel", config, parent)
end
local function uiStroke(parent, color, thickness)
	return new("UIStroke", { Color=color or UI.soft,Thickness=thickness or 1,Transparency=0.3 }, parent)
end

local screenGui = new("ScreenGui", {
	Name="TURavaHubGUI",ResetOnSpawn=false,DisplayOrder=2147483647,
	ZIndexBehavior=Enum.ZIndexBehavior.Sibling,IgnoreGuiInset=false,
}, playerGui)
UNLOAD.gui = screenGui
_G.TURavaHubUnload = UNLOAD.request
track(screenGui.Destroying:Connect(function()
	if not UNLOAD.active then UNLOAD.request("gui_destroyed") end
end))
local main = new("Frame", {
	Name="HubWindow",Size=UDim2.fromOffset(650,445),AnchorPoint=Vector2.new(0.5,0.5),
	Position=UDim2.fromScale(0.5,0.5),BackgroundColor3=UI.background,
	BorderSizePixel=0,Active=true,ClipsDescendants=true,
}, screenGui)
corner(main, 16)
uiStroke(main, UI.soft, 1)
local mainScale = new("UIScale", { Scale=1 }, main)
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

local top = new("Frame", { Size=UDim2.new(1,0,0,64),BackgroundColor3=UI.surface,
	BorderSizePixel=0,Active=true }, main)
new("Frame", { Size=UDim2.new(1,0,0,2),Position=UDim2.new(0,0,1,-2),
	BackgroundColor3=UI.accent,BorderSizePixel=0 }, top)
uiText(top, "RAVA HUB", 21, true, UI.text, { Position=UDim2.fromOffset(22,10),Size=UDim2.fromOffset(166,27) })
local headerStatus = uiText(top, "SYSTEM READY", 12, true, UI.good,
	{ Position=UDim2.fromOffset(346,20),Size=UDim2.fromOffset(192,24),TextXAlignment=Enum.TextXAlignment.Right })
local minimizeButton = new("TextButton", { Text="—",Size=UDim2.fromOffset(32,32),
	Position=UDim2.new(1,-84,0,15),BackgroundColor3=UI.surface2,
	TextColor3=UI.text,TextSize=18,Font=Enum.Font.GothamBold,BorderSizePixel=0 }, top)
corner(minimizeButton, 8)
local unloadButton = new("TextButton", { Text="×",Size=UDim2.fromOffset(32,32),
	Position=UDim2.new(1,-45,0,15),BackgroundColor3=Color3.fromRGB(92,47,62),
	TextColor3=UI.text,TextSize=24,Font=Enum.Font.GothamBold,BorderSizePixel=0 }, top)
corner(unloadButton, 8)
track(unloadButton.Activated:Connect(function()
	UNLOAD.request("header_button")
end))

local sidebar = new("Frame", { Position=UDim2.fromOffset(0,64),Size=UDim2.new(0,158,1,-94),
	BackgroundColor3=UI.surface,BorderSizePixel=0 }, main)
new("UIListLayout", { SortOrder=Enum.SortOrder.LayoutOrder,Padding=UDim.new(0,7) }, sidebar)
new("UIPadding", { PaddingTop=UDim.new(0,15),PaddingLeft=UDim.new(0,10),
	PaddingRight=UDim.new(0,10) }, sidebar)
local mainArea = new("Frame", { Position=UDim2.fromOffset(158,64),
	Size=UDim2.new(1,-158,1,-94),BackgroundTransparency=1 }, main)
local footer = new("Frame", { Position=UDim2.new(0,0,1,-30),Size=UDim2.new(1,0,0,30),
	BackgroundColor3=UI.surface,BorderSizePixel=0 }, main)
local footerLabel = uiText(footer, "TU Rava Hub", 11, false, UI.muted,
	{ Position=UDim2.fromOffset(17,5),Size=UDim2.new(1,-30,0,21) })
local diagnosticsDock = new("Frame", {
    Name="DiagnosticsDock",Position=UDim2.new(0,0,1,-96),
    Size=UDim2.fromOffset(158,65),BackgroundColor3=UI.surface,
    BorderSizePixel=0,ZIndex=3,
}, main)
new("Frame", { Size=UDim2.new(1,-20,0,1),Position=UDim2.fromOffset(10,2),
    BackgroundColor3=UI.soft,BorderSizePixel=0,ZIndex=3 }, diagnosticsDock)
local pages, menuButtons, activeTab = {}, {}, "AFK"
local toggleRefreshers = {}
local TAB_ORDER = { "AFK","Manual","Diagnostics" }
local TAB_SYMBOL = { AFK="◆",Manual="◉",Diagnostics="≡" }
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
        Name=name .. "Tab",Size=diagnostic and UDim2.new(1,-20,0,45)
            or UDim2.new(1,0,0,45),
        Position=diagnostic and UDim2.fromOffset(10,9) or UDim2.new(),
        LayoutOrder=index,BackgroundColor3=UI.surface,BorderSizePixel=0,
        ZIndex=diagnostic and 4 or 1,
        Text="  " .. TAB_SYMBOL[name] .. "    " .. name,
        Font=Enum.Font.GothamMedium,TextSize=14,
        TextXAlignment=Enum.TextXAlignment.Left,TextColor3=UI.muted,
    }, diagnostic and diagnosticsDock or sidebar)
    corner(button, 9)
    menuButtons[name] = button
    track(button.Activated:Connect(function()
        showTab(name)
        debugEvent("UI", "open_tab", { tab=name,access=diagnostic and "dock" or "sidebar" })
    end))
end
local function createSection(name)
	local page = new("ScrollingFrame", {
		Name=name .. "Page",Position=UDim2.fromOffset(0,0),Size=UDim2.fromScale(1,1),
		BackgroundTransparency=1,BorderSizePixel=0,ScrollBarThickness=4,
		ScrollBarImageColor3=UI.accent,CanvasSize=UDim2.new(),
		AutomaticCanvasSize=Enum.AutomaticSize.None,Visible=name == activeTab,
	}, mainArea)
	local pageLayout = list(page, 9)
	track(pageLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
		page.CanvasSize = UDim2.fromOffset(0, pageLayout.AbsoluteContentSize.Y + 34)
	end))
	new("UIPadding", { PaddingTop=UDim.new(0,15),PaddingLeft=UDim.new(0,14),
		PaddingRight=UDim.new(0,14),PaddingBottom=UDim.new(0,14) }, page)
	pages[name] = page
	uiText(page, name, 20, true, UI.text, {
		Size=UDim2.new(1,-8,0,30),LayoutOrder=-2,
	})
	return page
end
local function createSubcategory(page, heading, order, initiallyOpen)
	local expanded = initiallyOpen ~= false
	local card = new("Frame", {
		Name=heading:gsub("[^%w]","") .. "Group",Size=UDim2.new(1,-9,0,44),
		BackgroundColor3=UI.surface2,BorderSizePixel=0,LayoutOrder=order,
	}, page)
	corner(card, 10)
	uiStroke(card)
	local header = new("TextButton", {
		Name="GroupHeader",Size=UDim2.new(1,0,0,44),
		BackgroundTransparency=1,BorderSizePixel=0,Text="",AutoButtonColor=false,
	}, card)
	uiText(header, heading, 14, true, UI.text, {
		Position=UDim2.fromOffset(12,11),Size=UDim2.new(1,-55,0,22),
	})
	local caret = uiText(header, expanded and "−" or "+", 22, true, UI.accent, {
		Position=UDim2.new(1,-36,0,9),Size=UDim2.fromOffset(26,24),
		TextXAlignment=Enum.TextXAlignment.Center,
	})
	local body = new("Frame", {
		Name="GroupContent",BackgroundTransparency=1,
		Position=UDim2.fromOffset(0,44),Size=UDim2.new(1,0,0,0),
		Visible=expanded,BorderSizePixel=0,
	}, card)
	local contentLayout = list(body, 6, Enum.HorizontalAlignment.Center)
	new("UIPadding", { PaddingTop=UDim.new(0,3),PaddingBottom=UDim.new(0,10),
		PaddingLeft=UDim.new(0,8),PaddingRight=UDim.new(0,8) }, body)
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
		debugEvent("UI", "subcategory", { group=heading,open=expanded })
	end))
	task.defer(reflow)
	return body
end

pages.AFK = createSection("AFK")
pages.Manual = createSection("Manual")
pages.Diagnostics = createSection("Diagnostics")
uiText(pages.AFK, "Runs unattended: objectives, survival, pickups, and floor transitions.",
    12, false, UI.muted, { LayoutOrder=-1,Size=UDim2.new(1,-12,0,34),TextWrapped=true })
uiText(pages.Manual, "Use while playing: ESP, camera, rendering, and movement settings.",
    12, false, UI.muted, { LayoutOrder=-1,Size=UDim2.new(1,-12,0,34),TextWrapped=true })
local goalCard = new("Frame", { Name="DeathlessGoal",LayoutOrder=0,
    Size=UDim2.new(1,-9,0,72),BackgroundColor3=UI.surface2,BorderSizePixel=0 }, pages.AFK)
corner(goalCard, 10)
uiStroke(goalCard)
uiText(goalCard, "DEATHLESS MACHINE CHALLENGE", 12, true, UI.text, {
    Position=UDim2.fromOffset(12,8),Size=UDim2.new(1,-24,0,22) })
local afkGoalLabel = uiText(goalCard, "0 / 1000 machines  |  0 deaths  |  Best 0", 13, true, UI.good, {
    Position=UDim2.fromOffset(12,34),Size=UDim2.new(1,-24,0,26) })
uiText(pages.Diagnostics, "Initializing Diagnostics…",
	12, false, UI.muted, {
		Name="DiagnosticsStartupNotice",LayoutOrder=1,
		Size=UDim2.new(1,-12,0,68),TextWrapped=true,
		TextYAlignment=Enum.TextYAlignment.Top,
	})
UNLOAD.bootstrapExport = new("TextButton", {
	Name="DiagnosticsStartupExport",LayoutOrder=2,
	Size=UDim2.new(1,-12,0,38),BackgroundColor3=UI.accent,
	Text="EXPORT STARTUP LOG",Font=Enum.Font.GothamBold,
	TextColor3=UI.text,TextSize=12,BorderSizePixel=0,
}, pages.Diagnostics)
corner(UNLOAD.bootstrapExport, 8)
track(UNLOAD.bootstrapExport.Activated:Connect(function()
	UNLOAD.fallbackExport("STARTUP")
end))
UNLOAD.bootstrapUnload = new("TextButton", {
	Name="DiagnosticsStartupUnload",LayoutOrder=3,
	Size=UDim2.new(1,-12,0,38),BackgroundColor3=Color3.fromRGB(92,47,62),
	Text="UNLOAD HUB",Font=Enum.Font.GothamBold,
	TextColor3=UI.text,TextSize=12,BorderSizePixel=0,
}, pages.Diagnostics)
corner(UNLOAD.bootstrapUnload, 8)
track(UNLOAD.bootstrapUnload.Activated:Connect(function()
	UNLOAD.request("startup_diagnostics")
end))
task.delay(6, function()
	if alive and not UNLOAD.fullDiagnostics then
		increment("workerErrors")
		debugEvent("SYSTEM", "startup_incomplete", {
			diagnostics="fallback_available",note="check_executor_console",
		}, "ERROR")
	end
end)
local function createToggleRow(parent, name, order, feature, description)
	local row = new("Frame", { Size=UDim2.new(1,-9,0,description and 58 or 43),
		BackgroundColor3=UI.surface,BorderSizePixel=0,LayoutOrder=order }, parent)
	corner(row, 9)
	uiStroke(row)
	uiText(row, name, 14, description ~= nil, UI.text, {
		Position=UDim2.fromOffset(12,description and 6 or 0),
		Size=UDim2.new(1,-97,0,description and 24 or 43),
	})
	if description then
		uiText(row, description, 11, false, UI.muted, {
			Position=UDim2.fromOffset(12,30),Size=UDim2.new(1,-102,0,17),
			TextTruncate=Enum.TextTruncate.AtEnd,
		})
	end
	local button = new("TextButton", {
		Size=UDim2.fromOffset(62,28),Position=UDim2.new(1,-73,0.5,-14),
		BorderSizePixel=0,TextSize=12,Font=Enum.Font.GothamBold,
		TextColor3=UI.text,
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
			debugEvent("UI", "feature_changed", { name=name,enabled=feature.enabled })
		else
			increment("workerErrors")
			debugEvent("UI", "toggle_error", { name=name,error=err }, "ERROR")
		end
		for _, update in ipairs(toggleRefreshers) do update() end
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
local launcher = new("TextButton", { Name="RavaLauncher",Size=UDim2.fromOffset(50,50),
	Position=UDim2.new(0,14,0.5,-25),BackgroundColor3=UI.accent,
	Text="R",TextColor3=Color3.new(1,1,1),Font=Enum.Font.GothamBold,
	TextSize=25,BorderSizePixel=0,ZIndex=10 }, screenGui)
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
	{ Name="Item ESP",Folders={ "Items","Capsules","Candies","Map.InfectedSamples" },Color=Color3.fromRGB(255,220,70),TopLevelOnly=true },
	{ Name="Objective ESP",Folders={ "Computers","OilMachines" },Color=Color3.fromRGB(90,255,120),TopLevelOnly=true,
		Extra={ "Map.SpecialFolder.BigMachine.Computer","Map.SpecialFolder.BigMachine.Machine" } },
	{ Name="Infected ESP",Folders={ "MonsterFolder" },Color=Color3.fromRGB(255,60,60) },
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
	local state = { enabled=false,objects={},roots={},run=0 }
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
		local record = { conns={},name=inst.Name }
		state.objects[inst] = record
		local adornee = getAdorneePart(inst)
		local highlightTarget = inst:IsA("Folder") and adornee or inst
		if highlightTarget then
			record.highlight = new("Highlight", { Name="TU_ESP_Highlight",Adornee=highlightTarget,
				DepthMode=Enum.HighlightDepthMode.AlwaysOnTop,FillTransparency=0.93,
				OutlineTransparency=0,OutlineColor=config.Color }, inst)
		end
		local function createLabel()
			if record.billboard or not state.enabled or not inst.Parent then return end
			local part = getAdorneePart(inst)
			if not part then return end
			if not record.highlight then
				record.highlight = new("Highlight", { Name="TU_ESP_Highlight",Adornee=part,
					DepthMode=Enum.HighlightDepthMode.AlwaysOnTop,
					FillTransparency=0.93,OutlineTransparency=0,OutlineColor=config.Color }, inst)
			end
			local height = part.Size.Y
			if inst:IsA("Model") then
				local ok, size = pcall(function() return inst:GetExtentsSize() end)
				if ok then height = size.Y end
			end
			record.billboard = new("BillboardGui", { Adornee=part,AlwaysOnTop=true,
				Size=UDim2.fromOffset(220,29),StudsOffsetWorldSpace=Vector3.new(0,height / 2 + 1.4,0),
				MaxDistance=700,ResetOnSpawn=false }, screenGui)
			record.label = new("TextLabel", { BackgroundTransparency=1,Size=UDim2.fromScale(1,1),
				Text=inst.Name,TextColor3=config.Color,TextStrokeTransparency=0.12,
				TextScaled=false,TextSize=15,Font=Enum.Font.GothamBold }, record.billboard)
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
	Height=3,Settle=0.08,Dwell=0.55,
	Revisit=5,FailedRetry=0.8,Empty=0.05,
	Poll=0.04,IdleReturn=0.55,HeldLimit=3,
	SpamRate=16,BetweenPickups=0.11,TeleportBetweenPickups=0.14,
	TeleportSettle=0.10,InfectedClear=22,
	PickupHardRadius=26,PickupVisibleDanger=39,PickupSightRange=115,
	PickupThreatLead=0.32,PickupThreatRefresh=0.07,
}

local PROMPT_HOLDERS = { "Prompt","PromptPart" }
local originalPromptSight = setmetatable({}, { __mode="k" })
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
					{ prompt=prompt.Name,error=tostring(err) }, "WARN")
			end
		end
	end
	return prompt
end
local function getPrompt(target)
	if not target then return nil end
	local selected, disabled
	for _, name in ipairs(PROMPT_HOLDERS) do
		local holder = target:FindFirstChild(name)
		if holder then
			local candidate = holder:IsA("ProximityPrompt") and holder
				or holder:FindFirstChildWhichIsA("ProximityPrompt", true)
			if candidate then
				if candidate.Enabled then
					if disabled then increment("promptAlternateSelected") end
					return noPromptSight(candidate)
				end
				disabled = disabled or candidate
			end
		end
	end
	for _, child in ipairs(target:GetDescendants()) do
		if child:IsA("ProximityPrompt") then
			if child.Enabled then
				if disabled then increment("promptAlternateSelected") end
				selected = child
				break
			end
			disabled = disabled or child
		end
	end
	return noPromptSight(selected or disabled)
end
for _, child in ipairs(workspace:GetDescendants()) do
	if child:IsA("ProximityPrompt") then noPromptSight(child) end
end
track(workspace.DescendantAdded:Connect(function(child)
	if child:IsA("ProximityPrompt") then noPromptSight(child) end
end))

do
	local shown = setmetatable({}, { __mode="k" })
	UNLOAD.promptShownAt = shown
	local service = game:GetService("ProximityPromptService")
	track(service.PromptShown:Connect(function(prompt)
		shown[prompt] = os.clock()
		increment("promptShownEvents")
	end))
	track(service.PromptHidden:Connect(function(prompt)
		shown[prompt] = nil
		increment("promptHiddenEvents")
	end))
end

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

-- Autofarm prompt contact uses precise CFrame repositioning only.
-- No Humanoid:Move, Humanoid:MoveTo, WASD, or virtual walking keys.
-- Elevator entry uses separate grounded CFrame steps for possible touch triggers.
do
    local orbitGeneration, orbitActive = 0, false
    UNLOAD.abortOrbit = function() orbitGeneration += 1 end
    table.insert(cleanups, UNLOAD.abortOrbit)

    local function snapContact(prompt,part,keepGoing,purpose,side)
        if not alive or not keepGoing() or not prompt or not part
            or not prompt.Parent or not prompt.Enabled
            or (skillcheckProtected and skillcheckProtected()) then
            return false,"unavailable"
        end
        local character=player.Character
        local root=character and character:FindFirstChild("HumanoidRootPart")
        local humanoid=character and character:FindFirstChildOfClass("Humanoid")
        if not root or not root.Parent or root.Anchored or not humanoid or humanoid.Health <= 0
            or activeMotion then
            return false,"not_repositionable"
        end
        local center=getPromptPosition(prompt,part)
        local maxRange=prompt.MaxActivationDistance
        if maxRange <= 0.5 then return false,"prompt_range_too_small" end
        -- Stay inside the activation sphere rather than using a broad
        -- humanoid walking correction that can attract infected enemies.
        local up=math.min(math.max(0.22,maxRange*0.24),1.55)
        local radius=math.min(0.8,math.max(0.05,maxRange-up-0.7))
        local horizontal=root.Position-center
        horizontal=Vector3.new(horizontal.X,0,horizontal.Z)
        local toward=horizontal.Magnitude > 0.05 and horizontal.Unit
            or Vector3.new(1,0,0)
        if side then toward=Vector3.new(-toward.Z,0,toward.X) end
        local destination=center+Vector3.new(0,up,0)+toward*radius
        if (destination-center).Magnitude >= maxRange-0.08 then
            destination=center+Vector3.new(0,math.max(0.1,maxRange*0.35),0)
        end
        -- Never micro-teleport an item farm into a snake's footprint.
        if purpose and purpose:find("pickup",1,true) and UNLOAD.pickupSnakeUnsafe
            and UNLOAD.pickupSnakeUnsafe(nil,destination) then
            return false,"snake_under_destination"
        end
        local nearThreat=purpose and purpose:find("pickup",1,true) and 20 or 14
        if infectedNear and infectedNear(destination,nearThreat) then
            return false,"enemy_nearby"
        end
        if not keepGoing() or player.Character ~= character then return false,"interrupted" end
        local okay,why=UNLOAD.voidGuard.landingOK(destination,"prompt")
        if not okay then
            increment("voidLandingsBlocked")
            return false,why
        end
        local success,err=pcall(function()
            root.AssemblyLinearVelocity=Vector3.zero
            root.AssemblyAngularVelocity=Vector3.zero
            root.CFrame=CFrame.new(destination)*(root.CFrame-root.Position)
        end)
        local reached=success and root.Parent ~= nil
            and (root.Position-center).Magnitude <= maxRange
            and (root.Position-destination).Magnitude <= 2
        if not success then
            debugThrottled("snap_contact_error_"..tostring(purpose),2,"PROMPT",
                "teleport_contact_failed",{purpose=purpose,error=tostring(err)},"WARN")
        end
        return reached,reached and "teleport_contact" or "teleport_not_verified"
    end

    UNLOAD.refreshPromptContact=function(prompt,part,keepGoing,purpose)
        increment("promptMovePulses")
        local ok,reason=snapContact(prompt,part,keepGoing,purpose,false)
        increment(ok and "promptMoveVerified" or "promptMoveBlocked")
        debugThrottled("contact_snap_"..tostring(purpose),3,"PROMPT",
            ok and "contact_teleported" or "contact_teleport_blocked",
            {purpose=purpose,reason=reason},ok and "INFO" or "WARN")
        return ok,reason
    end
    UNLOAD.seatPrompt=function(prompt,part,keepGoing,purpose)
        increment("promptSeatAttempts")
        local ok,reason=snapContact(prompt,part,keepGoing,purpose,true)
        increment(ok and "promptSeatVerified" or "promptSeatBlocked")
        return ok,reason
    end

    UNLOAD.orbitPromptContact=function(target,prompt,part,keepGoing,confirmed,activate,purpose,maxSeconds)
        if orbitActive then
            increment("promptOrbitBlocked")
            return false,"already_orbiting",0
        end
        local character=player.Character
        local root=character and character:FindFirstChild("HumanoidRootPart")
        local humanoid=character and character:FindFirstChildOfClass("Humanoid")
        if not alive or not target or not prompt or not part or not root or not humanoid
            or humanoid.Health <= 0 or root.Anchored or activeMotion
            or not prompt.Enabled or not target:IsDescendantOf(workspace)
            or not keepGoing() or (skillcheckProtected and skillcheckProtected()) then
            increment("promptOrbitBlocked")
            return false,"unavailable",0
        end
        orbitActive=true
        local myGeneration=orbitGeneration
        local begun=os.clock()
        local duration=math.clamp(tonumber(maxSeconds) or 0.85,0.20,1.0)
        local lastFire=-math.huge
        local fires,positions=0,0
        local result="timeout"
        increment("promptOrbitAttempts")
        local success,err=pcall(function()
            -- Small discrete teleports replace the former Humanoid MoveTo orbit.
            for step=1,12 do
                if os.clock()-begun >= duration then break end
                local got,confirmedNow=pcall(confirmed)
                if got and confirmedNow then result="confirmed" break end
                if orbitGeneration ~= myGeneration or not alive or character ~= player.Character
                    or not root.Parent or root.Anchored or activeMotion
                    or not prompt.Parent or not prompt.Enabled or not target.Parent
                    or humanoid.Health <= 0 or not keepGoing()
                    or (skillcheckProtected and skillcheckProtected()) then
                    result="interrupted" break
                end
                local center=getPromptPosition(prompt,part)
                local height=math.min(1.3, math.max(0.2,prompt.MaxActivationDistance*0.24))
                local radius=math.min(0.85,math.max(0.12,prompt.MaxActivationDistance*0.3))
                local theta=2*math.pi*(step-1)/12
                local goal=center+Vector3.new(math.cos(theta)*radius,height,
                    math.sin(theta)*radius)
                if (goal-center).Magnitude >= prompt.MaxActivationDistance-0.1 then
                    result="outside_range" break
                end
                if purpose and purpose:find("pickup",1,true) and UNLOAD.pickupSnakeUnsafe
                    and (UNLOAD.pickupSnakeUnsafe(target,goal)
                        or UNLOAD.pickupSnakeUnsafe(target,part)) then
                    result="snake_trap" break
                end
                local radiusRisk=purpose and purpose:find("pickup",1,true) and 22 or 16
                if infectedNear and (infectedNear(root.Position,radiusRisk)
                    or infectedNear(goal,radiusRisk)) then
                    result="enemy_nearby" break
                end
                local landingOK=UNLOAD.voidGuard.landingOK(goal,"prompt_orbit")
                if not landingOK then
                    increment("voidLandingsBlocked")
                    result="orbit_landing_unsafe" break
                end
                root.AssemblyLinearVelocity=Vector3.zero
                root.AssemblyAngularVelocity=Vector3.zero
                root.CFrame=CFrame.new(goal)*(root.CFrame-root.Position)
                positions+=1
                if os.clock()-lastFire >= (purpose and purpose:find("pickup",1,true)
                    and 1/FARM.SpamRate or 0.1) then
                    lastFire=os.clock()
                    local firedOK,fired=pcall(activate)
                    if firedOK and fired then fires+=1 end
                end
                task.wait(math.min(0.065,math.max(0.01,duration/12)))
            end
        end)
        orbitActive=false
        if not success then
            result="lua_error"
            debugEvent("PROMPT","teleport_orbit_error",{purpose=purpose,error=tostring(err)},"ERROR")
        end
        local got,done=pcall(confirmed)
        if got and done and result ~= "lua_error" then result="confirmed" end
        if positions>0 then increment("promptOrbitMoves") end
        increment("promptOrbitFires",fires)
        if result=="confirmed" then increment("promptOrbitConfirmed")
        elseif result=="timeout" then increment("promptOrbitTimeouts")
        else increment("promptOrbitBlocked") end
        debugEvent("PROMPT","teleport_orbit_"..result,{
            target=target.Name,purpose=purpose,positions=positions,fires=fires,
            durationMs=math.floor((os.clock()-begun)*1000+0.5) },
            result=="confirmed" and "INFO" or "WARN")
        return result=="confirmed",result,fires
    end
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
			{ prompt=prompt.Name,owner=tostring(prompt.Parent) }, "WARN")
		return false
	end
	task.wait(math.max(0, prompt.HoldDuration) + 0.05)
	pcall(function()
		prompt:InputHoldEnd()
	end)
	return true
end

local machinePromptHolds = setmetatable({}, { __mode="k" })
local modifiedMachinePrompts = setmetatable({}, { __mode="k" })

local function triggerMachinePrompt(prompt)
	increment("promptAttempts")
	noPromptSight(prompt)
	if not prompt or not prompt:IsA("ProximityPrompt") or not prompt:IsDescendantOf(workspace) or not prompt.Enabled then
		increment("promptFailures")
		debugThrottled("machine_prompt_invalid", 3, "PROMPT", "machine_prompt_unavailable", nil, "WARN")
		return false
	end
	if not modifiedMachinePrompts[prompt] then
		modifiedMachinePrompts[prompt] = { hold=prompt.HoldDuration,sight=prompt.RequiresLineOfSight }
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
			{ prompt=prompt.Name }, "WARN")
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
	TPhantasia=true, TSquid=true, TSnakes=true,
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
	if target.Parent ~= initialParent then return true, "target_removed" end
	if not prompt:IsDescendantOf(target) then return false, "prompt_replaced" end
	if confirmPickup and heldCount() > initialHeld then
		return true, "inventory_increased"
	end
	if not prompt.Enabled and not confirmPickup then return true, "prompt_disabled" end
	return false
end

local function spamPrompt(prompt, target, keepGoing, confirmPickup, initialHeld, initialParent, duration)
	local deadline = os.clock() + (duration or FARM.Dwell)
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
		if not prompt:IsDescendantOf(target) then return finish(false, "prompt_replaced", attempts) end
		if not keepGoing() then return interruption() end

		attempts += 1
		if hasFirePrompt and attempts >= 4 and not holding and os.clock() - beganAt >= 0.22 then
			beginFallbackHold()
		end
		local started = os.clock()
		local fired = triggerPrompt(prompt, false)
		if not fired then
			debugThrottled("pickup_activation_" .. tostring(target), 2, "PICKUP",
				"activation_failed", { target=target.Name,attempt=attempts }, "WARN")
		end
		local nextAttempt = math.min(deadline, started + 1 / FARM.SpamRate)
		while os.clock() < nextAttempt do
			local done, why = pickupEvidence(prompt, target, initialParent, confirmPickup, initialHeld)
			if done then return finish(true, why, attempts) end
			if not prompt:IsDescendantOf(target) then return finish(false, "prompt_replaced", attempts) end
			if not keepGoing() then return interruption() end
			task.wait(math.min(FARM.Poll, math.max(0.01, nextAttempt - os.clock())))
		end
	end
	local collected, reason = pickupEvidence(prompt, target, initialParent, confirmPickup, initialHeld)
	if collected then return finish(true, reason, attempts) end
	return finish(false, "confirmation_timeout", attempts)
end

local targetCaches = setmetatable({}, { __mode="k" })
local function getTargets(folder)
	local cache = targetCaches[folder]
	if not cache then
		cache = { dirty=true,conns={},last=0,values={} }
		targetCaches[folder] = cache
		local function invalidate(obj)
			local parent = obj.Parent
			if parent == folder or (parent and parent.Parent == folder) then cache.dirty = true end
		end
		for _, signal in ipairs({ folder.DescendantAdded,folder.DescendantRemoving }) do
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

local chase = { pending=false,holdUntil=0 }
local pickupCircuit = {
	paused=false,finalized=false,
	failed=setmetatable({},{ __mode="k" }),
	blocked=setmetatable({},{ __mode="k" }),
	failedTargets=setmetatable({},{ __mode="k" }),
	distinctFailures=0,
	consecutive=0,
	lastConfirmed=os.clock(),
	MaxTargetFailures=3,
	MaxConsecutiveFailures=6,
	MaxStallSeconds=8,
}
function pickupCircuit.pause(reason)
	if pickupCircuit.paused then return end
	pickupCircuit.paused = true
	increment("pickupCircuitTrips")
	debugEvent("PICKUP", "collection_paused", {
		reason=reason,failures=pickupCircuit.consecutive,
		failedTargets=pickupCircuit.distinctFailures,
	}, "WARN")
end
function pickupCircuit.reset(reason)
	if not pickupCircuit.paused and not pickupCircuit.finalized then return end
	pickupCircuit.paused = false
	pickupCircuit.finalized = false
	pickupCircuit.failed = setmetatable({}, { __mode="k" })
	pickupCircuit.blocked = setmetatable({}, { __mode="k" })
	pickupCircuit.failedTargets = setmetatable({}, { __mode="k" })
	pickupCircuit.distinctFailures = 0
	pickupCircuit.consecutive = 0
	pickupCircuit.lastConfirmed = os.clock()
	increment("pickupCircuitResets")
	debugEvent("PICKUP", "collection_resumed", { reason=reason })
end
function pickupCircuit.record(target, folder, confirmed, reason, attempts)
	if confirmed then
		pickupCircuit.lastConfirmed = os.clock()
		pickupCircuit.consecutive = 0
		pickupCircuit.distinctFailures = 0
		pickupCircuit.failedTargets = setmetatable({}, { __mode="k" })
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
			folder=folder,name=target.Name,
			attempts=pickupCircuit.failed[target],reason=reason,
		}, "WARN")
	end
	if pickupCircuit.consecutive >= pickupCircuit.MaxConsecutiveFailures
		and pickupCircuit.distinctFailures >= 2 then
		pickupCircuit.pause("repeated_failed_collections")
	end
end

track(workspace.ChildAdded:Connect(function(instance)
	if instance.Name == "Map" or ((instance.Name == "Items" or instance.Name == "Capsules")
		and not pickupCircuit.finalized) then
		pickupCircuit.reset("world_reloaded")
	end
end))

UNLOAD.pickupBefore = { completed=false,started=nil,mapRef=workspace:FindFirstChild("Map") }
function UNLOAD.pickupBefore.reset(reason)
	UNLOAD.pickupBefore.completed = false
	UNLOAD.pickupBefore.started = nil
	UNLOAD.pickupBefore.mapRef = workspace:FindFirstChild("Map")
	pickupCircuit.reset(reason)
	debugEvent("PICKUP", "before_phase_reset", { reason=reason })
end
track(workspace.ChildAdded:Connect(function(inst)
	if inst.Name == "Map" and inst ~= UNLOAD.pickupBefore.mapRef then
		UNLOAD.pickupBefore.reset("new_map")
	end
end))

local pickupCoordinator = {
	owner=nil, home=nil, lastActivity=os.clock(),
	enabledCount=0,
}

local function releasePickup(farm)
	if pickupCoordinator.owner == farm then
		pickupCoordinator.owner = nil
		pickupCoordinator.lastActivity = os.clock()
	end
end

local function returnPickupHome(force, isBlocked)
	if pickupCircuit.paused or pickupCircuit.finalized then return end
	if not pickupCoordinator.home or pickupCoordinator.owner then return end
	if UNLOAD.pickupBefore.started and not UNLOAD.pickupBefore.completed then
		pickupCoordinator.home = nil
		return
	end
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

-- Client-only collision shields under every currently observed TSnakes instance.
-- Pickup safety remains a separate, continuously updated decision; it does not
-- rely on the shield preventing server-side attacks.
do
    local SETTINGS = {
        PlatePadding=4, PlateThickness=1.5, PlateOffset=0.35,
        PickupPadding=8, PickupBelow=45, PickupAbove=10,
        Refresh=0.055,
    }
    local oldGuards = workspace:FindFirstChild("TU_Rava_SnakeGuards")
    if oldGuards then pcall(function() oldGuards:Destroy() end) end
    local guardsFolder = Instance.new("Folder")
    guardsFolder.Name = "TU_Rava_SnakeGuards"
    guardsFolder.Parent = workspace
    local snakes = {} -- [TSnakes instance] = { guard=BasePart?, footprint=table? }

    local function fullBounds(inst)
        if inst:IsA("BasePart") then return inst.CFrame, inst.Size end
        if inst:IsA("Model") then
            local ok, cf, size = pcall(function() return inst:GetBoundingBox() end)
            if ok and cf and size and size.Magnitude > 0.01 then return cf,size end
        end
        if inst:IsA("Folder") then
            local lo,hi
            for _, obj in ipairs(inst:GetDescendants()) do
                if obj:IsA("BasePart") then
                    local c,sz = obj.CFrame,obj.Size
                    local r,u,l = c.RightVector,c.UpVector,c.LookVector
                    local hx = (math.abs(r.X)*sz.X+math.abs(u.X)*sz.Y+math.abs(l.X)*sz.Z)*0.5
                    local hy = (math.abs(r.Y)*sz.X+math.abs(u.Y)*sz.Y+math.abs(l.Y)*sz.Z)*0.5
                    local hz = (math.abs(r.Z)*sz.X+math.abs(u.Z)*sz.Y+math.abs(l.Z)*sz.Z)*0.5
                    local offset = Vector3.new(hx,hy,hz)
                    local a,b = c.Position-offset,c.Position+offset
                    lo = lo and Vector3.new(math.min(lo.X,a.X),math.min(lo.Y,a.Y),math.min(lo.Z,a.Z)) or a
                    hi = hi and Vector3.new(math.max(hi.X,b.X),math.max(hi.Y,b.Y),math.max(hi.Z,b.Z)) or b
                end
            end
            if lo and hi then return CFrame.new((lo+hi)*0.5),hi-lo end
        end
        local part = getAdorneePart(inst)
        return part and part.CFrame, part and part.Size
    end

    local function footprint(cf,sz)
        local r,u,l=cf.RightVector,cf.UpVector,cf.LookVector
        local hx = (math.abs(r.X)*sz.X+math.abs(u.X)*sz.Y+math.abs(l.X)*sz.Z)*0.5
        local hy = (math.abs(r.Y)*sz.X+math.abs(u.Y)*sz.Y+math.abs(l.Y)*sz.Z)*0.5
        local hz = (math.abs(r.Z)*sz.X+math.abs(u.Z)*sz.Y+math.abs(l.Z)*sz.Z)*0.5
        return { x=cf.Position.X,z=cf.Position.Z,halfX=hx,halfZ=hz,
            top=cf.Position.Y+hy,bottom=cf.Position.Y-hy }
    end

    local function removeSnake(inst)
        local record = snakes[inst]
        if not record then return end
        snakes[inst]=nil
        if record.guard then
            pcall(function() record.guard:Destroy() end)
            increment("snakeGuardsRemoved")
        end
    end

    local function updateSnake(inst,record)
        local cf,sz=fullBounds(inst)
        if not cf or not sz then
            record.footprint=nil
            if record.guard then record.guard.CanCollide=false end
            return
        end
        local fp=footprint(cf,sz)
        record.footprint=fp
        local plate=record.guard
        if not plate or not plate.Parent then
            plate=Instance.new("Part")
            plate.Name="TU_TSnakesSafetyHitbox"
            plate.Anchored=true
            plate.CanCollide=true
            plate.CanTouch=false
            plate.CanQuery=true -- CanQuery=false does not suppress queries on collidable parts
            plate.CastShadow=false
            plate.Transparency=1
            plate.Locked=true
            plate.Parent=guardsFolder
            record.guard=plate
            increment("snakeGuardsCreated")
            debugEvent("SNAKES","guard_created",{snake=inst:GetFullName()})
        end
        local targetSize=Vector3.new(math.max(2,fp.halfX*2+SETTINGS.PlatePadding*2),
            SETTINGS.PlateThickness,math.max(2,fp.halfZ*2+SETTINGS.PlatePadding*2))
        local targetCF=CFrame.new(fp.x,fp.bottom-SETTINGS.PlateOffset-SETTINGS.PlateThickness*0.5,fp.z)
        if (plate.Position-targetCF.Position).Magnitude > 0.05
            or (plate.Size-targetSize).Magnitude > 0.05 then
            plate.Size=targetSize
            plate.CFrame=targetCF
            increment("snakeGuardsMoved")
        end
        if not plate.CanCollide then plate.CanCollide=true end
    end

    local function register(inst)
        if inst.Name ~= "TSnakes" or snakes[inst] then return end
        if not (inst:IsA("Model") or inst:IsA("BasePart") or inst:IsA("Folder")) then return end
        local record={ guard=nil,footprint=nil }
        snakes[inst]=record
        updateSnake(inst,record)
    end

    for _, inst in ipairs(workspace:GetDescendants()) do register(inst) end
    track(workspace.DescendantAdded:Connect(function(inst)
        if inst.Name == "TSnakes" then register(inst) end
    end))
    track(workspace.DescendantRemoving:Connect(function(inst)
        if snakes[inst] then removeSnake(inst) end
    end))
    table.insert(cleanups,function()
        for snake in pairs(snakes) do removeSnake(snake) end
        if guardsFolder.Parent then guardsFolder:Destroy() end
    end)
    task.spawn(function()
        while alive do
            local hasSnakes = false
            for snake,record in pairs(snakes) do
                if snake:IsDescendantOf(workspace) then
                    hasSnakes = true
                    local ok,err=pcall(updateSnake,snake,record)
                    if not ok then
                        debugThrottled("snake_update_error",3,"SNAKES","guard_update_error",
                            { reason=tostring(err) },"WARN")
                    end
                else
                    removeSnake(snake)
                end
            end
            task.wait(hasSnakes and SETTINGS.Refresh or 0.4)
        end
    end)

    function UNLOAD.pickupSnakeUnsafe(target,partOrPosition)
        -- Attached snake traps always exclude an item even if their geometry
        -- streams in late or their root position is temporarily unavailable.
        if target and target.Parent then
            local current=target
            while current and current ~= workspace do
                if current.Name == "TSnakes" then return true,"nested_trap",0 end
                current=current.Parent
            end
            if target:FindFirstChild("TSnakes",true) then return true,"attached_trap",0 end
        end
        local pos
        if typeof(partOrPosition)=="Vector3" then
            pos=partOrPosition
        elseif typeof(partOrPosition)=="Instance" and partOrPosition:IsA("BasePart") then
            pos=partOrPosition.Position
        elseif target and target.Parent then
            local part=getAdorneePart(target)
            pos=part and part.Position
        end
        if not pos then return false end

        for snake,record in pairs(snakes) do
            if snake.Parent and snake:IsDescendantOf(workspace) then
                if target and (snake:IsDescendantOf(target) or target:IsDescendantOf(snake)) then
                    return true,"attached_trap",0
                end
                local fp=record.footprint
                if fp and math.abs(pos.X-fp.x) <= fp.halfX+SETTINGS.PickupPadding
                    and math.abs(pos.Z-fp.z) <= fp.halfZ+SETTINGS.PickupPadding
                    and pos.Y >= fp.bottom-SETTINGS.PickupBelow
                    and pos.Y <= fp.top+SETTINGS.PickupAbove then
                    local flat=Vector3.new(pos.X-fp.x,0,pos.Z-fp.z).Magnitude
                    return true,"under_"..snake:GetFullName(),flat
                end
            end
        end
        return false
    end
end

-- Pickup-only threat assessment. This does not modify objective movement or
-- the ProximityPrompt.RequiresLineOfSight setting. A wall can hide a pickup
-- from a monster even when the pickup prompt itself ignores sight rules.
local pickupThreatCache = { at=-math.huge, entries={} }
local function pickupThreatSnapshot(force)
    local now = os.clock()
    if not force and now - pickupThreatCache.at < FARM.PickupThreatRefresh then
        return pickupThreatCache.entries
    end
    local entries = {}
    local folder = workspace:FindFirstChild("MonsterFolder")
    if folder then
        for _, enemy in ipairs(getTargets(folder)) do
            -- TSnakes are covered by the dedicated trap check. Treat all
            -- other monster models as potential pickup threats.
            if (enemy:IsA("Model") or enemy:IsA("BasePart"))
                and enemy.Name ~= "TSnakes" then
                local core = enemy:IsA("BasePart") and enemy
                    or (enemy:FindFirstChild("HumanoidRootPart", true)
                        or enemy.PrimaryPart or enemy:FindFirstChild("Head", true)
                        or enemy:FindFirstChildWhichIsA("BasePart", true))
                if core then
                    table.insert(entries, { object=enemy,core=core,
                        position=core.Position,velocity=core.AssemblyLinearVelocity,
                        look=core.CFrame.LookVector })
                end
            end
        end
    end
    pickupThreatCache.at, pickupThreatCache.entries = now, entries
    return entries
end

local function pickupSightClear(enemy, position, target)
    local origin = enemy.position + Vector3.new(0, 1.2, 0)
    local destination = position + Vector3.new(0, 1.1, 0)
    local direction = destination - origin
    if direction.Magnitude < 0.5 then return true end
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    local ignored = { enemy.object }
    local character = player.Character
    if character then table.insert(ignored, character) end
    local folder = workspace:FindFirstChild("MonsterFolder")
    if folder then table.insert(ignored, folder) end
    local guards = workspace:FindFirstChild("TU_Rava_SnakeGuards")
    if guards then table.insert(ignored,guards) end
    params.FilterDescendantsInstances = ignored
    params.IgnoreWater = true
    -- Ignore a few fully transparent, nonblocking decorative pieces so they
    -- don't masquerade as solid cover. Solid walls remain true occluders.
    for _ = 1, 5 do
        local hit = workspace:Raycast(origin,direction,params)
        if not hit then return true end
        if target and (hit.Instance == target or hit.Instance:IsDescendantOf(target)) then
            return true
        end
        local part = hit.Instance
        if part:IsA("BasePart") and (part.Transparency >= 0.95
            or (not part.CanCollide and part.Transparency >= 0.5)) then
            table.insert(ignored,part)
            params.FilterDescendantsInstances = ignored
        else
            return false
        end
    end
    return false
end

-- Lower score is preferable. Hard-danger pickups are never attempted.
-- A visible pickup that is not close enough to be dangerous can still be used
-- if every alternative is worse, rather than starving the pickup phase.
local function pickupRisk(position, target, anchor)
    local score = anchor and (position-anchor).Magnitude * 0.09 or 0
    local result = { unsafe=false,score=score,nearest=math.huge,visible=false,approaching=false }
    increment("pickupSafetyScans")
    for _, enemy in ipairs(pickupThreatSnapshot()) do
        if enemy.core.Parent and math.abs(enemy.position.Y-position.Y) <= 24 then
            local to = Vector3.new(position.X-enemy.position.X,0,position.Z-enemy.position.Z)
            local distance = to.Magnitude
            local speed = Vector3.new(enemy.velocity.X,0,enemy.velocity.Z)
            local predicted = distance
            if distance > 0.01 and speed:Dot(to) > 0 then
                local nextPos = enemy.position + speed * FARM.PickupThreatLead
                predicted = math.min(distance,Vector3.new(position.X-nextPos.X,0,
                    position.Z-nextPos.Z).Magnitude)
            end
            local nearing = predicted < distance - 1
            local effective = math.min(distance,predicted)
            result.nearest = math.min(result.nearest,effective)
            result.approaching = result.approaching or nearing
            result.score += math.max(0, 95-effective) * 1.4
            if effective <= FARM.PickupHardRadius then result.unsafe = true end
            if effective <= FARM.PickupSightRange then
                local sight = pickupSightClear(enemy,position,target)
                if sight then
                    local look = Vector3.new(enemy.look.X,0,enemy.look.Z)
                    local facing = distance < 0.1 or look.Magnitude < 0.01
                        or look.Unit:Dot(to.Unit) >= -0.15
                    result.visible = true
                    if facing then
                        increment("pickupLoSExposed")
                        result.score += math.max(0, FARM.PickupSightRange-effective)*4 + 90
                        if effective <= FARM.PickupVisibleDanger then result.unsafe = true end
                    else
                        -- An unobstructed pickup behind the monster still carries risk.
                        result.score += math.max(0, FARM.PickupSightRange-effective)*1.8 + 30
                    end
                end
            end
            if nearing and effective <= FARM.PickupVisibleDanger + 8 then
                result.score += 110
            end
        end
    end
    return result
end

-- Only pickups wait: the wait is broken into short checks, and an approaching
-- enemy can end it immediately. Machine handoffs never call this function.
local function pickupInterval(active, isBlocked)
    local length = OPTIONS.MovementMode == "Teleport"
        and FARM.TeleportBetweenPickups or FARM.BetweenPickups
    local untilAt = os.clock() + length
    while active() and not (isBlocked and isBlocked()) and os.clock() < untilAt do
        local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
        if not root or pickupRisk(root.Position).unsafe
            or UNLOAD.pickupSnakeUnsafe(nil,root.Position) then
            increment("pickupCooldownInterrupts")
            return false
        end
        task.wait(math.min(0.02, math.max(0.005, untilAt-os.clock())))
    end
    return active() and not (isBlocked and isBlocked())
end

-- Never escape toward the saved return point when the enemy has reached it.
local lastPickupEvadeAt = -math.huge
local function pickupEmergencyEvade(active, home, name)
    if not active() or os.clock() - lastPickupEvadeAt < 0.35 then return false end
    local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
    if not root or (not pickupRisk(root.Position).unsafe
        and not UNLOAD.pickupSnakeUnsafe(nil,root.Position)) then return false end
    local destination
    local strategy = "return_point"
    if home and not pickupRisk(home.Position).unsafe
        and not UNLOAD.pickupSnakeUnsafe(nil,home.Position) then
        destination = home
    else
        -- Return point can become occupied. Find a safer, known item location
        -- instead of blindly escaping into another infected or empty space.
        local best = math.huge
        for _, folderName in ipairs({"Capsules","Map.InfectedSamples","Items","Candies"}) do
            local folder = resolveWorkspacePath(folderName)
            if folder then
                for _, candidate in ipairs(getTargets(folder)) do
                    local part = getAdorneePart(candidate)
                    if part and candidate.Name:lower() ~= "fuse"
                        and not UNLOAD.pickupSnakeUnsafe(candidate,part) then
                        local risk = pickupRisk(part.Position,candidate,root.Position)
                        if not risk.unsafe and risk.nearest >= FARM.PickupVisibleDanger + 10
                            and risk.score < best then
                            best = risk.score
                            destination = CFrame.new(part.Position+Vector3.new(0,FARM.Height,0))
                            strategy = "safe_item_area"
                        end
                    end
                end
            end
        end
    end
    if not destination then
        debugThrottled("pickup_escape_no_safe_point",2,"DANGER",
            "pickup_escape_safety_unavailable",{ pickup=name or "unknown" },"WARN")
        return false
    end
    lastPickupEvadeAt = os.clock()
    increment("pickupDangerEvades")
    debugEvent("DANGER","pickup_immediate_evade",{
        pickup=name or "unknown",destination=strategy },"WARN")
    -- An emergency dodge stays immediate even if normal pickup mode is Tween.
    return instantTeleport(destination,active,"pickup_escape","emergency")
end

local function newAutofarm(folderName, gate, filter, confirmPickup, isBlocked)
	local farm = { enabled=false,working=false,hasWork=false }
	local runId = 0
	local recent = setmetatable({}, { __mode="k" })
	local snakeSkippedAt = setmetatable({}, { __mode="k" })
	local function loop(myId)
		local function active() return alive and farm.enabled and runId == myId end
		local function allowed()
			return active() and not (UNLOAD.voidGuard and UNLOAD.voidGuard.blocked)
				and not pickupCircuit.paused and not pickupCircuit.finalized and (not gate or gate()) and not (isBlocked and isBlocked())
				and (os.clock() >= motionPauseUntil)
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
					local candidates = getTargets(folder)
					-- Rank ALL pickup modes by enemy proximity, physical line of sight,
					-- closing speed, and then travel distance. Never reorder objectives.
					if #candidates > 1 then
						local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
						if root then
							local ranked = {}
							for _, candidate in ipairs(candidates) do
								local part = getAdorneePart(candidate)
								local risk = part and pickupRisk(part.Position,candidate,root.Position)
								local snakeUnsafe = part and UNLOAD.pickupSnakeUnsafe(candidate,part)
								table.insert(ranked,{ item=candidate,score=risk and risk.score or math.huge,
									unsafe=not risk or risk.unsafe or snakeUnsafe })
							end
							table.sort(ranked,function(a,b)
								if a.unsafe ~= b.unsafe then return not a.unsafe end
								return a.score < b.score
							end)
							candidates = {}
							for _, record in ipairs(ranked) do table.insert(candidates,record.item) end
							increment("pickupNearestRoutes")
						end
					end
					for _, target in ipairs(candidates) do
						if not allowed() then break end
						local character = player.Character
						local root = character and character:FindFirstChild("HumanoidRootPart")
						local prompt = target.Parent and getPrompt(target)
						local fresh = not pickupCircuit.blocked[target] and (not filter or filter(target))
							and (not recent[target] or os.clock() - recent[target] >= FARM.Revisit)
						local part = fresh and root and prompt and prompt.Enabled and getPromptPart(prompt, target)
						local snakeUnsafe, snakeSource, snakeDistance
						if part then
							snakeUnsafe, snakeSource, snakeDistance = UNLOAD.pickupSnakeUnsafe(target, part)
						end
						local safety = part and pickupRisk(part.Position,target,root and root.Position)
						local unsafe = part and (snakeUnsafe or (safety and safety.unsafe))
						if snakeUnsafe then
							if not snakeSkippedAt[target] or os.clock() - snakeSkippedAt[target] >= 5 then
								snakeSkippedAt[target] = os.clock()
								increment("pickupSnakeSkipped")
								debugEvent("SNAKES", "pickup_skipped", { folder=folder.Name,name=target.Name,
									source=snakeSource or "unknown",distance=snakeDistance or "attached" }, "WARN")
							end
						elseif unsafe then
							increment("pickupSafetySkips")
							debugThrottled("pickup_unsafe_" .. tostring(target), 5, "PICKUP", "skipped_enemy_or_sight",
								{ folder=folder.Name,name=target.Name,
									nearest=safety and string.format("%.1f",safety.nearest) or "unknown",
									visible=safety and safety.visible or false }, "WARN")
						end
						if part and not unsafe and pickupCoordinator.owner == nil then
							pickupCoordinator.owner = farm
							pickupCoordinator.lastActivity = os.clock()
							pickupCoordinator.home = pickupCoordinator.home or root.CFrame
							didWork = true
							farm.working = true
							increment("pickupAttempts")
							local beganAt = os.clock()
							debugEvent("PICKUP", "attempt", { folder=folder.Name,name=target.Name,
								held=heldCount(),prompt=prompt.Name,distance=string.format("%.1f",(root.Position - part.Position).Magnitude) })
							local initialHeld, initialParent = heldCount(), target.Parent
							local ok, confirmed, reason, attempts = pcall(function()
								if not allowed() then return false, "not_allowed", 0 end
								local promptPosition = getPromptPosition(prompt, part)
								local function stillPicking(traveling)
									if not (allowed() and pickupCoordinator.owner == farm
										and part:IsDescendantOf(workspace) and prompt.Enabled)
										or UNLOAD.pickupSnakeUnsafe(target, part)
										or UNLOAD.pickupSnakeUnsafe(target, promptPosition) then return false end
									-- A moving enemy can interrupt a pickup even during prompt spam.
									if pickupRisk(part.Position,target).unsafe then return false end
									if not traveling and pickupRisk(root.Position).unsafe then return false end
									return true
								end
								local approachHeight = math.clamp(prompt.MaxActivationDistance - 1, 0.25, FARM.Height)
								local destination = CFrame.new(promptPosition + Vector3.new(0, approachHeight, 0))
								local arrived, travelReason = tweenPickup(destination, function()
									return stillPicking(true) and not pickupRisk(promptPosition,target).unsafe
								end, target)
								if not arrived then
									if isBlocked and isBlocked() then return false, "preempted_by_machine", 0 end
									return false, "tween_" .. tostring(travelReason), 0
								end
								task.wait(0.04)
								local contacted = UNLOAD.refreshPromptContact(prompt, part, function()
									return stillPicking(true) and not pickupRisk(promptPosition,target).unsafe
								end, "pickup_arrival")
								if not contacted and stillPicking(true) then
									contacted = UNLOAD.seatPrompt(prompt, part, function()
										return stillPicking(true) and not pickupRisk(promptPosition,target).unsafe
									end, "pickup_arrival")
								end
								task.wait(contacted and 0.05 or (OPTIONS.MovementMode == "Teleport" and FARM.TeleportSettle or FARM.Settle))
								if isBlocked and isBlocked() then return false, "preempted_by_machine", 0 end
								if UNLOAD.pickupSnakeUnsafe(target, part)
									or UNLOAD.pickupSnakeUnsafe(target,promptPosition) then
									return false, "snake_trap_after_arrival", 0
								end
								if pickupRisk(root.Position).unsafe then
									return false, "enemy_after_arrival", 0
								end
								local actualRange = (root.Position - promptPosition).Magnitude
								if actualRange > prompt.MaxActivationDistance then
									debugEvent("PICKUP", "outside_prompt_range", {
										name=target.Name,distance=string.format("%.2f",actualRange),
										maximum=prompt.MaxActivationDistance }, "WARN")
									return false, "outside_prompt_range", 0
								end
								local observed, why = pickupEvidence(prompt, target, initialParent, confirmPickup, initialHeld)
								if observed then return true, why, 0 end
								if not stillPicking() then
									return false, (isBlocked and isBlocked()) and "preempted_by_machine" or "interrupted_after_arrival", 0
								end
								local success, why, fired = spamPrompt(prompt, target, stillPicking, confirmPickup, initialHeld, initialParent)
								if not success and (why == "confirmation_timeout" or why == "prompt_replaced")
									and (fired or 0) > 0 and stillPicking(true) and not pickupCircuit.paused then
									increment("pickupContactRetries")
									local refreshed = getPrompt(target)
									if refreshed and refreshed.Enabled and refreshed:IsDescendantOf(target) then
										if refreshed ~= prompt then
											increment("pickupPromptReplacements")
											prompt = refreshed
											part = getPromptPart(prompt, target) or part
											promptPosition = getPromptPosition(prompt, part)
										end
										local contactOk = UNLOAD.refreshPromptContact(prompt, part, function()
											return stillPicking(true) and not pickupRisk(promptPosition,target).unsafe
										end, "pickup_retry")
										if not contactOk and stillPicking(true) then
											contactOk = UNLOAD.seatPrompt(prompt, part, function()
												return stillPicking(true) and not pickupRisk(promptPosition,target).unsafe
											end, "pickup_retry")
										end
										if contactOk and stillPicking(true)
											and (root.Position - promptPosition).Magnitude <= prompt.MaxActivationDistance then
											local retrySuccess, retryReason, retryFired = spamPrompt(prompt, target, stillPicking,
												confirmPickup, initialHeld, initialParent, 0.43)
											success, why, fired = retrySuccess, retryReason, fired + retryFired
											increment(retrySuccess and "pickupContactRecovered" or "pickupContactFailed")
											debugEvent("PICKUP", retrySuccess and "contact_recovered" or "contact_unconfirmed",
												{ name=target.Name,folder=folder.Name,attempts=fired }, retrySuccess and "INFO" or "WARN")
										else
											increment("pickupContactFailed")
											why = why == "prompt_replaced" and "prompt_replaced" or "confirmation_timeout"
										end
									end
							end
								-- No orbit or walking fallback for pickup routes. A failed
								-- contact retry is retried in the next pickup cycle instead.
								if not success and (why == "confirmation_timeout" or why == "prompt_replaced") then
									increment("pickupOrbitsSuppressed")
								end
								if not success and isBlocked and isBlocked() then return false, "preempted_by_machine", fired end
								return success, why, fired
							end)
							if not confirmed and UNLOAD.pickupSnakeUnsafe(target, part) then
								confirmed, reason = false, "snake_trap_appeared"
								increment("pickupSnakeInterrupted")
								local home = pickupCoordinator.home
								if home and active() and not (isBlocked and isBlocked())
									and not UNLOAD.pickupSnakeUnsafe(nil, home.Position) then
									local escaped = teleportCharacter(home, function() return active() end,
											"pickup_snake_escape", "emergency")
									if escaped then increment("pickupSnakeEscapes") end
								end
							end
							if active() and not (isBlocked and isBlocked()) then
								pickupEmergencyEvade(active,pickupCoordinator.home,target.Name)
							end
							releasePickup(farm)
							-- This small pickup-only pause never delays machine objectives.
							if active() and not (isBlocked and isBlocked()) then
								local waited = pickupInterval(active,isBlocked)
								if not waited and not (isBlocked and isBlocked()) then
									pickupEmergencyEvade(active,pickupCoordinator.home,target.Name)
								end
							end
							if not ok then
								debugLog("ERROR pickup " .. tostring(target.Name) .. ": " .. tostring(confirmed))
								warn("[TU Rava Hub] pickup error: " .. tostring(confirmed))
								confirmed, reason, attempts = false, "lua_error", 0
							end
							if reason == "preempted_by_machine" then
								increment("pickupPreemptions")
								debugEvent("PICKUP", "preempted_by_machine", {
									folder=folder.Name,name=target.Name,
									elapsedMs=math.floor((os.clock() - beganAt) * 1000 + 0.5),
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
							debugEvent("PICKUP", "result", { folder=folder.Name,name=target.Name,
								movement=OPTIONS.MovementMode:lower(),confirmed=confirmed,reason=reason or "unknown",activations=attempts or 0,
								maxDistance=prompt.MaxActivationDistance,holdDuration=prompt.HoldDuration,
								requiresSight=prompt.RequiresLineOfSight,
								promptVisible=UNLOAD.promptShownAt[prompt] ~= nil,
								duration=string.format("%.2f",os.clock() - beganAt),held=heldCount() },
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
local espBody = pages.Manual
local espWorld = createSubcategory(espBody, "ESP - COLLECTIBLES & OBJECTIVES", 1)
local espThreats = createSubcategory(espBody, "ESP - INFECTED TRACKING", 2, true)
UNLOAD.manualThreatSection = espThreats
for i, config in ipairs(ESP_CONFIGS) do
	local parent = (config.Name == "Infected ESP") and espThreats or espWorld
	createToggleRow(parent, config.Name, i, newESP(config))
end

end

local TRASH_ITEMS = { Coffee=true,Socks=true,Waffle=true,["Pristine Boots"]=true }
local HEALTH_ITEMS = { Bandaid=true,Medkit=true,["Pristine Medkit"]=true }
local ITEM_OPTIONS = { Trash=false,Health=false,AutoTrashUse=true }

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
    -- Loose fuses belong EXCLUSIVELY to the blackout worker, never Item Autofarm.
    if item.Name:lower() == "fuse" then return false end
	if TRASH_ITEMS[item.Name] then return ITEM_OPTIONS.Trash end
	if HEALTH_ITEMS[item.Name] then
		if not ITEM_OPTIONS.Health then return false end
		local health = getHealth()
		return health ~= nil and health ~= 3
	end
	return true
end

local USE_ITEMS = {
	Oil={ Wrench=true,["Pristine Wrench"]=true,Gloves=true,["Pristine Gloves"]=true },
	Computer={ USB=true,["Pristine USB"]=true,Mint=true,["Pristine Mint"]=true },
	Health=HEALTH_ITEMS,
}

local AUTO_USE = { Tick=0.25,HealCooldown=3,UseDelay=0.2 }
local SLOT_KEYS = { Enum.KeyCode.One,Enum.KeyCode.Two,Enum.KeyCode.Three }

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
				item=item.Name,index=tostring(item:GetAttribute("Index")),
				indexSource=source,inventory=inventorySummary(),
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
		debugEvent("ITEM", "invalid_slot", { slot=tostring(slot),purpose=purpose }, "WARN")
		return false
	end
	if UserInputService:GetFocusedTextBox() then
		debugThrottled("item_input_focused", 3, "ITEM", "input_deferred_focused_textbox", {
			purpose=purpose,slot=slot,
		}, "WARN")
		return false
	end
	local timeout = os.clock() + 0.35
	while slotInputBusy and os.clock() < timeout do task.wait(0.02) end
	if slotInputBusy then
		debugThrottled("item_input_busy", 2, "ITEM", "input_busy", { purpose=purpose }, "WARN")
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
		purpose=purpose,item=item and item.Name or "unknown",slot=slot,
		indexSource=indexSource or "unknown",method=driver,acceptedByInputAPI=succeeded,
		error=succeeded and "none" or tostring(err),
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
				purpose=purpose,item=item and item.Name or "unknown",
				method=driver,slot=slot,countBefore=initialCount,countAfter=newCount,
				itemRemoved=itemRemoved,healed=healed,-- Reusable items may not produce observable changes.
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
		machine=machine.Name,inventory=inventorySummary(),
	}, "WARN")
	return false
end

local ABILITY = { KeyHold=0.075,InputWait=0.30,TrashDelay=0.02 }
local trashControl = {
    busy=false,nextAttempt=setmetatable({},{ __mode="k" }),
    Tick=0.22,SuccessRetry=3.0,FailureRetry=0.8,
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
		item=item.Name,slot=slot,reason=purpose,
		machine=machineName or "none",dispatched=sent,
	}, sent and "INFO" or "WARN")
	return sent
end
local abilityStatusLabel -- Created in Autofarm > Automatic Actions.
local machineFarm
local machinesDone
local leaveObjective
local machineExitBlockedUntil = 0

local autoAbility = { enabled=false }
function autoAbility.enable()
	if autoAbility.enabled then return end
	autoAbility.enabled = true
	if abilityStatusLabel then
		abilityStatusLabel.Text = "After each completed machine: press F  |  ENABLED"
		abilityStatusLabel.TextColor3 = UI.good
	end
	debugEvent("ABILITY", "enabled", { trigger="machine_completion",input="F",cooldownDetection=false })
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
				machine=machine.Name,ui=tostring(ui),
			}, "WARN")
			return false, "skillcheck"
		end
	end
	if UserInputService:GetFocusedTextBox() then
		increment("abilityInputDeferred")
		debugEvent("ABILITY", "completion_f_deferred_textbox", { machine=machine.Name }, "WARN")
		return false, "textbox"
	end
	local deadline = os.clock() + ABILITY.InputWait
	while slotInputBusy and alive and os.clock() < deadline do task.wait(0.02) end
	if slotInputBusy or not alive then
		increment("abilityInputDeferred")
		debugEvent("ABILITY", "completion_f_deferred_input_busy", { machine=machine.Name }, "WARN")
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
		machine=machine.Name,method=driver,durationMs=durationMs,
		dispatched=ok,acceptedByGame="unknown",error=ok and "none" or tostring(err),
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
					machine=machine.Name,item=item.Name,slot=slot,dispatched=sent,
				})
			else
				debugThrottled("ability_no_trash", 6, "ITEM", "trash_not_found", {
					inventory=inventorySummary(),
				}, "INFO")
			end
		end
	end
	trashControl.busy = false
	return ok, ok and "sent" or "input_failed"
end

local autoUse = { enabled=false }
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

local function collectOpen()
	return not UNLOAD.pickupBefore.completed and not pickupCircuit.finalized
		and not (machinesDone and machinesDone())
end

local function machineBusy()
	return machineFarm ~= nil and machineFarm.enabled == true and
		(machineFarm.target ~= nil or machineFarm.placed == true or machineFarm.moving == true
			or machineFarm.finalizing == true)
end

local capsuleFarm = newAutofarm({ "Capsules","Map.InfectedSamples" }, collectOpen, nil, false, machineBusy)

local itemFarm = newAutofarm("Items", function()
	return heldCount() < FARM.HeldLimit and not capsuleFarm.working and collectOpen()
end, itemAllowed, true, machineBusy)

local candyFarm = newAutofarm("Candies", function()
	return not capsuleFarm.working and not itemFarm.working and collectOpen()
end, nil, false, machineBusy)

PICKUPS = {
	{ farm=capsuleFarm,folder="Capsules" },
	{ farm=capsuleFarm,folder="Map.InfectedSamples" },
	{ farm=itemFarm,folder="Items",held=true,filter=itemAllowed },
	{ farm=candyFarm,folder="Candies" },
}

local function scanFinalPickups()
	local result = { eligible=0,safe=0,unsafe=0,skipped=0,blocked=0,sources={} }
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
								if UNLOAD.pickupSnakeUnsafe(target, part)
									or pickupRisk(part.Position,target).unsafe then
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
	local option = { enabled=options[key] }
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
local farmBody = pages.AFK
local farmActions = createSubcategory(farmBody, "AUTOMATIC ITEM & ABILITY USE", 7, true)
createToggleRow(farmActions, "Auto Use Ability", 1, autoAbility)
createToggleRow(farmActions, "Auto Use Items", 3, autoUse)
UNLOAD.trashUseToggle = newOption(ITEM_OPTIONS, "AutoTrashUse")
createToggleRow(farmActions, "Auto Use Trash Items", 4, UNLOAD.trashUseToggle)

local farmPickups = createSubcategory(farmBody, "PICKUP AUTOFARMS", 5, true)
createToggleRow(farmPickups, "Capsule Autofarm", 1, capsuleFarm)
createToggleRow(farmPickups, "Item Autofarm", 2, itemFarm)
createToggleRow(farmPickups, "Candy Autofarm", 3, candyFarm)
local farmFilters = createSubcategory(farmBody, "PICKUP FILTERS", 6, false)
createToggleRow(farmFilters, "Pick Up Trash Items", 1, newOption(ITEM_OPTIONS, "Trash"))
createToggleRow(farmFilters, "Pick Up Health Items", 2, newOption(ITEM_OPTIONS, "Health"))

autoUse.enable()
autoAbility.enable()
for _, refresh in ipairs(toggleRefreshers) do refresh() end

end

local MACHINE = {
	Folders={ "OilMachines","Computers" }, Range=50, Height=3,
	Elevator="Map.SpecialFolder.ExitElevator", ElevatorFallback="Elevator", ElevatorHeight=-20,
	Tick=0.010,Settle=0,PromptRetry=0.075,
	RescanInterval=0.030,StallTimeout=2.7,UseTimeout=8,NearFinishAt=90,NearFinishHold=20,
	ClearHold=1.0,ItemWaitMax=24,
	SkillcheckPause=3, ChaseHold=2.5, HideMinSeconds=2.5, HideClearSeconds=1.5,
	DoneValue=100, FuseDwell=0.7,
	EmergencyDistance=27,ThreatLead=0.28,ThreatVertical=26,
	Fuseboxes={
		"Map.SpecialFolder.Fusebox.Handle.ProximityPrompt",
		"Map.SpecialFolder.ExitFusebox.Handle.ProximityPrompt",
	},
	Allowed={ TSelena=true,TSquid=true,TPhantasia=true,TFizzle=true,TSnakes=true },
}

local function targetPosition(inst)
	if inst:IsA("BasePart") then return inst.Position end
	if inst:IsA("Model") then return inst:GetPivot().Position end
	local part = getAdorneePart(inst)
	return part and part.Position
end

do
local selenaLook = { enabled=false,active=false,chaseSeen=false,
	target=nil,binding="TU_RavaHub_LookAtSelena" }
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
	debugEvent("SELENA", "look_stopped", { reason=reason or "unknown" })
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
		debugEvent("SELENA", "look_failed", { error=tostring(err) }, "ERROR")
		return
	end
	debugEvent("SELENA", "look_started", { trigger=trigger or "chase",target=unit:GetFullName() })
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

-- Resolve the moving core rather than a model pivot or a decorative part;
-- inactive decoration can be dozens of studs from the actual monster.
local function threatCore(unit)
	if unit:IsA("BasePart") then return unit end
	if unit:IsA("Model") then
		return unit:FindFirstChild("HumanoidRootPart", true)
			or unit.PrimaryPart or unit:FindFirstChild("Head", true)
			or unit:FindFirstChildWhichIsA("BasePart", true)
	end
	return nil
end

infectedNear = function(position, radius)
	local folder = workspace:FindFirstChild("MonsterFolder")
	if not folder then return false end
	for _, twisted in ipairs(getTargets(folder)) do
		if not isInsideMachineExcludedFolder(twisted)
			and (not MACHINE.Allowed[twisted.Name] or twisted.Name == "TSelena") then
			local part = threatCore(twisted)
			if part and (part.Position - position).Magnitude <= radius then return true end
		end
	end
	return false
end

-- Nearest-threat detection: consider 3-D floor separation, actual character
-- cores, and a short forward prediction only when moving toward our position.
-- Ordinarily excluded monsters count during an explicit Chase event when the
-- chased monster is identified (or when the event supplies no monster name).
local function twistedNear(position, radius)
	if not OPTIONS.AutoHide then return false end
	local folder = workspace:FindFirstChild("MonsterFolder")
	if not folder then return false end
	local limit = radius or MACHINE.Range
	local nearest, nearestName, nearestPredicted = nil, nil, false
	for _, twisted in ipairs(getTargets(folder)) do
		local eventThreat = chase.eventActive
			and (chase.threatName == nil or chase.threatName == twisted.Name)
		if not isInsideMachineExcludedFolder(twisted)
			and (not MACHINE.Allowed[twisted.Name] or eventThreat) then
			local core = threatCore(twisted)
			if core then
				local pos = core.Position
				if math.abs(pos.Y - position.Y) <= MACHINE.ThreatVertical then
					local delta = Vector3.new(position.X-pos.X, 0, position.Z-pos.Z)
					local distance = delta.Magnitude
					local velocity = core.AssemblyLinearVelocity
					local flatVelocity = Vector3.new(velocity.X, 0, velocity.Z)
					local prediction = false
					if distance > 0.01 and flatVelocity:Dot(delta) > 0 then
						local nextPosition = pos + flatVelocity * MACHINE.ThreatLead
						local leadDistance = Vector3.new(position.X-nextPosition.X,
							0, position.Z-nextPosition.Z).Magnitude
						if leadDistance < distance then
							distance, prediction = leadDistance, true
						end
					end
					if distance <= limit and (nearest == nil or distance < nearest) then
						nearest, nearestName, nearestPredicted = distance, twisted.Name, prediction
					end
				end
			end
		end
	end
	if nearest then
		if nearestPredicted then increment("threatPredictions") end
		return true, nearestName, nearest, nearestPredicted
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
local deathExport = { handled=false,life=0,character=nil }
local function exportOnDeath(reason, hp)
	if deathExport.handled or not alive then return end
	deathExport.handled = true
	increment("deathExports")
	GOAL.Best = math.max(GOAL.Best, GOAL.Streak)
	GOAL.Deaths += 1
	debugEvent("GOAL", "deathless_streak_broken", {
		completed=GOAL.Streak,best=GOAL.Best,deaths=GOAL.Deaths,target=GOAL.Target,
		trigger=reason,health=hp,
	}, "ERROR")
	GOAL.Streak = 0
	debugEvent("HITS", "health_zero", { trigger=reason,health=hp,life=deathExport.life }, "ERROR")
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
					debugEvent("DEBUG", "death_export_unavailable", { reason="exporter_not_ready" }, "ERROR")
				end
			end)
		end
	end)
end
local healthMonitor = { source=nil,conn=nil,old=nil,diedConn=nil }
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
			if newValue > 0 then
				UNLOAD.damageRetreatSerial = (UNLOAD.damageRetreatSerial or 0) + 1
			end
			if not name then increment("nearestEnemyMissing") end
			debugStatus.lastHit = string.format("%.1f -> %.1f | %s (%.1f studs)",
				previous, newValue, name or "none", distance or -1)
			debugEvent("HITS", "health_decreased", {
				source=mode,from=previous,to=newValue,damage=previous - newValue,
				nearestInfected=name or "none",nearestDistance=distance and string.format("%.1f",distance) or "unknown",
				position=playerPos and tostring(playerPos) or "unknown",
				machineTarget=debugStatus.currentTarget,
				pickupActive=pickupCoordinator.owner ~= nil,
				attribution="proximity_only",
			}, "WARN")
			if previous >= 3 and newValue <= 0 then
				increment("elevatorDeaths")
				debugEvent("HITS", "elevator_death", {
					nearestInfected=name or "none",nearestDistance=distance or "unknown",
					position=playerPos and tostring(playerPos) or "unknown",
					lastElevator=machineFarm and machineFarm.elevatorSource or "none",
					platformFound=machineFarm and machineFarm.elevatorPlatform ~= nil or false,
				}, "ERROR")
			end
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
	debugEvent("HITS", "monitor_bound", { source=mode or "none",initial=healthMonitor.old or "unknown" })
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
			local chasedMonster = nil
			for i = 1, select("#", ...) do
				local value = select(i, ...)
				local name = typeof(value) == "Instance" and value.Name
					or (type(value) == "string" and value or nil)
				if name == "TSelena" then
					hasSelenaMarker = true
					chasedMonster = name
				elseif name and name:match("^T[A-Z][a-z]") then
					hasOtherMonsterMarker = true
					chasedMonster = name
				end
			end
			for _, arg in ipairs({ ... }) do
				if arg == "Stopped" or arg == "Ended" or arg == "Finished" then
					chase.eventActive = false
					chase.threatName = nil
					chase.holdUntil = math.min(chase.holdUntil, os.clock() + MACHINE.ClearHold)
				end
				if arg == "Started" and (hasSelenaMarker or not hasOtherMonsterMarker) then
					UNLOAD.selenaLook.onChase()
				elseif (arg == "Stopped" or arg == "Ended" or arg == "Finished")
					and (hasSelenaMarker or not hasOtherMonsterMarker) then
					UNLOAD.selenaLook.chaseSeen = false
					UNLOAD.selenaLook.stop("chase_ended")
				end
				if arg == "Started" and OPTIONS.AutoHide and machineFarm and machineFarm.enabled then
					increment("chases")
					local pickupTravel = pickupCoordinator.owner ~= nil
						or (activeMotion and activeMotion.owner == "pickup")
						or ((capsuleFarm.enabled or itemFarm.enabled or candyFarm.enabled)
							and not machineBusy())
					if pickupTravel then
						increment("pickupChasesIgnored")
						debugThrottled("pickup_chase_ignored", 2, "DANGER", "pickup_auto_hide_suppressed", nil, "INFO")
						continue
					end
					debugEvent("DANGER", "chase_started", { autoHide=OPTIONS.AutoHide,
						monster=chasedMonster or "unknown" }, "WARN")
					chase.eventActive = true
					chase.threatName = chasedMonster
					chase.pending = true
					-- Allow an urgent escape even when a skillcheck is visibly active.
					UNLOAD.imminentEvacuationUntil = os.clock() + 1.25
					chase.serial = (chase.serial or 0) + 1
					chase.holdUntil = math.max(chase.holdUntil, os.clock() + MACHINE.ChaseHold)
					if machineFarm and machineFarm.target then
						cancelMachinePromptHold(getPrompt(machineFarm.target))
					end
					-- Every accepted chase event gets its OWN exit attempt, even if the
					-- skillcheck UI is open or an earlier InvokeServer is still pending.
					-- Do not wait inside OnClientEvent: travel must be able to preempt.
					if leaveObjective then
						local ok, queued = pcall(leaveObjective, "auto_hide_chase_event", true, 0)
						if ok and queued then
							chase.exitRequestedSerial = chase.serial
						else
							increment("autoHideExitEventFailures")
							debugEvent("MACHINE", "auto_hide_exit_event_failed", {
								serial=chase.serial,error=not ok and tostring(queued) or "not_queued",
							}, "ERROR")
						end
					end
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

UNLOAD.progressValues = setmetatable({}, { __mode="k" })
local function getProgress(machine)
	if not machine then return nil end
	local cache = UNLOAD.progressValues
	local value = cache[machine]
	if value and not value:IsDescendantOf(machine) then value = nil end
	if not value then
		value = machine:FindFirstChild("ComputerPercentage") or machine:FindFirstChild("OilValue")
		if not value then
			value = machine:FindFirstChild("ComputerPercentage", true)
				or machine:FindFirstChild("OilValue", true)
			if value then increment("nestedProgressResolutions") end
		end
		if value and (value:IsA("NumberValue") or value:IsA("IntValue")) then
			cache[machine] = value
		else
			cache[machine] = nil
			return nil
		end
	end
	return value.Value
end

local function isComplete(machine)
	local progress = getProgress(machine)
	return progress ~= nil and progress >= MACHINE.DoneValue
end

local function getBigMachines()
	local list = {}
	for _, name in ipairs({ "Machine","Computer" }) do
		local big = resolveWorkspacePath("Map.SpecialFolder.BigMachine." .. name)
		if big and not isInsideMachineExcludedFolder(big) then table.insert(list, big) end
	end
	return list
end

-- Exclusion is only a short-lived hint from a local-player completion sound.
-- Keep the excluded machine counted as incomplete, so a sound cannot falsely
-- indicate every machine is finished or send the player to the elevator.
local function nearestIncomplete(list, excluded)
	local root = getPlayerRoot()
	local best, bestDistance, anyIncomplete = nil, nil, false
	for _, machine in ipairs(list) do
		if not isComplete(machine) then
			anyIncomplete = true
			if machine ~= excluded then
				local prompt = getPrompt(machine)
				local pos = prompt and prompt.Enabled and targetPosition(machine)
				if pos then
					local distance = root and (root.Position - pos).Magnitude or 0
					if not bestDistance or distance < bestDistance then best, bestDistance = machine, distance end
				end
			end
		end
	end
	return best, anyIncomplete
end

local function pickMachine(excluded)
	local scanStarted = os.clock()
	increment("machineScans")
	local function report(target, status)
		local elapsed = (os.clock() - scanStarted) * 1000
		if elapsed > 30 then
			increment("slowMachineScans")
			debugThrottled("slow_machine_scan", 3, "PERF", "slow_machine_scan",
				{ ms=string.format("%.1f",elapsed),status=status }, "WARN")
		end
		return target, status
	end
	local normals = getMachines()
	local best, anyIncomplete = nearestIncomplete(normals, excluded)
	if best then return report(best, "work") end
	if anyIncomplete then return report(nil, "wait") end
	local bigs = getBigMachines()
	best, anyIncomplete = nearestIncomplete(bigs, excluded)
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

-- A UI can be recreated inside its existing ScreenGui, or nested beneath an
-- extra container. Resolve the live widgets rather than caching a single path.
function UNLOAD.skillcheckNodes()
	local round = playerGui:FindFirstChild("RoundSkillcheck")
		or playerGui:FindFirstChild("RoundSkillcheck", true)
	local normal = round and round:FindFirstChild("Normal", true)
	local lock = playerGui:FindFirstChild("LockUI")
		or playerGui:FindFirstChild("LockUI", true)
	local skill = lock and lock:FindFirstChild("Skillcheck", true)
	local main = skill and skill:FindFirstChild("Main", true)
	local marker = main and main:FindFirstChild("Marker", true)
	return normal,main,marker
end

local lastSkillcheckOnScreenAt = -math.huge
skillcheckProtected = function()
	local normal, _, marker = UNLOAD.skillcheckNodes()
	if skillcheckWidgetOnScreen(normal) then
		lastSkillcheckOnScreenAt = os.clock()
		return true,"round"
	end
	if skillcheckWidgetOnScreen(marker) then
		lastSkillcheckOnScreenAt = os.clock()
		return true,"bar"
	end
	if os.clock() - lastSkillcheckOnScreenAt < 0.05 then return true,"ui_transition" end
	return false,"none"
end

local autoSkillcheck

local skillcheckMovedAt = 0
local lastDial, lastBar

local function skillcheckVisible()
	local normal, _, marker = UNLOAD.skillcheckNodes()
	local now,visible = os.clock(),false
	if normal and skillcheckWidgetOnScreen(normal) then
		visible = true
		local aim = normal:FindFirstChild("AimImage",true)
		local rotation = aim and aim.Rotation
		if rotation ~= lastDial then
			lastDial,skillcheckMovedAt = rotation,now
		end
	end
	if marker and skillcheckWidgetOnScreen(marker) then
		visible = true
		local x = marker.AbsolutePosition.X
		if x ~= lastBar then
			lastBar,skillcheckMovedAt = x,now
		end
	end
	return visible and now-skillcheckMovedAt < 0.5
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

leaveObjective = function(reason, force, waitSeconds)
	reason = reason or "manual"
	local protected, checkType = skillcheckProtected()
	local forced = force == true
	local autoHide = reason:find("auto_hide", 1, true) ~= nil
		or reason == "chase_escape" or reason == "infected_near_machine"
	if protected and not forced then
		increment("skillcheckLeaveDeferred")
		debugThrottled("skillcheck_leave_" .. tostring(reason), 1,
			"MACHINE", "leave_deferred_skillcheck", { reason=reason,
				ui=checkType,forceRequested=false }, "INFO")
		return false
	end
	if protected and forced then
		increment("urgentMachineExits")
		if autoHide then increment("autoHideExitDuringSkillcheck") end
		debugEvent("MACHINE", "forced_leave_during_skillcheck", { reason=reason,ui=checkType }, "WARN")
	end
	if autoHide then increment("autoHideExitRequests") end
	-- Never reuse a previous result for a new Auto Hide activation. Queue the
	-- new request behind an in-flight request instead of silently dropping it.
	local previous = UNLOAD.exitInFlight
	if previous and not previous.finished then
		increment("machineExitFlightWaits")
		if autoHide then increment("autoHideExitQueued") end
	end
	increment("skillcheckExitAttempts")
	machineExitBlockedUntil = math.max(machineExitBlockedUntil, os.clock() + 0.75)
	local flight = { finished=false,successful=false,startedAt=os.clock() }
	UNLOAD.exitInFlight = flight
	local begin = os.clock()
	task.spawn(function()
		if previous and not previous.finished then
			local expiry = os.clock() + 0.45
			while not previous.finished and os.clock() < expiry and alive do task.wait(0.01) end
			if not previous.finished then
				debugEvent("MACHINE", "leave_previous_response_pending", { reason=reason }, "WARN")
			end
		end
		local reprotected, uiType = skillcheckProtected()
		if reprotected and not forced then
			flight.finished = true
			increment("skillcheckLeaveDeferred")
			debugEvent("MACHINE", "leave_cancelled_ui_appeared", { reason=reason,ui=uiType }, "INFO")
			return
		end
		local ok, response = pcall(function()
			local remotes = game:GetService("ReplicatedStorage"):FindFirstChild("Remotes")
			local remote = remotes and remotes:FindFirstChild("SkillCheck")
			if not remote or not remote:IsA("RemoteFunction") then
				error("SkillCheck RemoteFunction unavailable")
			end
			if autoHide then increment("autoHideExitSent") end
			return remote:InvokeServer()
		end)
		flight.successful = ok and response ~= false
		flight.finished = true
		if not ok or response == false then increment("skillcheckExitFailures") end
		debugEvent("MACHINE",
			(not ok and "leave_remote_failed") or (response == false and "leave_remote_rejected" or "leave_remote_complete"),
			{ reason=reason,returned=tostring(response),
				responseVerified=response == true,requestCompleted=ok,
				elapsedMs=math.floor((os.clock() - begin) * 1000 + 0.5) },
			(not ok and "ERROR") or (response == false and "WARN" or "INFO"))
	end)
	local deadline = os.clock() + (waitSeconds or (forced and 0.18 or 0.12))
	while not flight.finished and os.clock() < deadline do task.wait() end
	if not flight.finished and waitSeconds ~= 0 then
		debugThrottled("leave_remote_pending", 2, "MACHINE", "leave_remote_pending",
			{ reason=reason,escapeContinues=forced }, "WARN")
	end
	-- Forced exits have been scheduled even if the RemoteFunction has not
	-- returned. Server acceptance is never inferred from this value.
	return forced or flight.successful
end

UNLOAD.floorState = {
	mapRef=workspace:FindFirstChild("Map"),seen=false,
	completed=0,lastCompletion=-math.huge,noTargetsSince=nil,
	finished=false,completionReason="none",
}
function UNLOAD.floorStatus(target, status)
	local state = UNLOAD.floorState
	local currentMap = workspace:FindFirstChild("Map")
	if currentMap and currentMap ~= state.mapRef then
		state.mapRef = currentMap
		state.seen,state.completed,state.finished = false,0,false
		state.noTargetsSince,state.lastCompletion = nil,-math.huge
		state.completionReason = "none"
		increment("elevatorRoundResets")
	end
	if target then
		if state.finished then
			state.completed,state.finished = 0,false
			state.completionReason = "none"
		end
		state.seen,state.noTargetsSince = true,nil
		return false
	end
	if status == "wait" or status == "work" then
		state.noTargetsSince = nil
		return false
	end
	if status == "done" and state.seen then
		state.finished,state.completionReason = true,"all_completed"
		return true
	end
	-- Many floors remove their completed machine models. A stable 'none'
	-- after a confirmed completion must not erase the elevator deadline.
	if status == "none" and state.seen and state.completed > 0 then
		local now = os.clock()
		state.noTargetsSince = state.noTargetsSince or now
		if not state.finished and now - state.noTargetsSince >= 0.50
			and now - state.lastCompletion >= 0.50 then
			state.finished,state.completionReason = true,"completed_models_removed"
			increment("elevatorMissingStatusRecovered")
			debugEvent("MACHINE", "all_complete_models_removed", {
				completed=state.completed,secondsWithoutTargets=string.format("%.2f",now-state.noTargetsSince),
			})
		end
	else
		state.noTargetsSince = nil
	end
	return state.finished and status ~= "wait" and status ~= "work"
end

local doneAt,doneValue = 0,false
machinesDone = function()
	local now = os.clock()
	if now-doneAt >= 0.10 then
		doneAt = now
		local nextTarget,status = pickMachine()
		doneValue = UNLOAD.floorStatus(nextTarget,status)
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
	local farm = { enabled=false,target=nil,finalizing=false,
		elevatorTransit=false,elevatorTarget=nil,allDoneSince=nil,
		elevatorEmergencyLocked=false,elevatorWatchFired=false,
		elevatorHoldCorrections=0,lastElevatorHoldAt=0,
		elevatorAlternateCommitted=false,elevatorAlternateTried=false,
		elevatorServerRelocated=false,elevatorServerRelocatedAt=nil,
		lastElevatorMoveAt=nil,elevatorProfiled=false,elevatorEntryTouched=false,
		elevatorEntryAttempts=0,elevatorContactRetryAt=0,
		elevatorRecoveryAt=nil,elevatorRecoveryCount=0,
		soundSerial=0,soundLast=nil,soundDoneTarget=nil,soundDoneUntil=0,
		lastPromptTarget=nil,lastPromptAt=-math.huge,
		mainReadyUntil=0,elevatorDoorOpenUntil=0,
		elevatorSoundPath=nil,elevatorSoundAt=-math.huge,elevatorSoundWaitSince=nil,
		pendingDoorPath=nil,pendingDoorAt=-math.huge,
		mainFlushTarget=nil,mainFlushAt=-math.huge,mainFlushUntil=0,
		mainCompletionTarget=nil,mainCompletionAt=-math.huge,
		mainCompletionUntil=0,mainCompletionDoorUntil=0,mainCompletionExitUntil=0,
		blackoutCueAt=-math.huge,blackoutPendingUntil=0,lastFuseAttemptAt=-math.huge,
        blackoutActive=false,blackoutHandled=false,blackoutStartedAt=-math.huge,
        blackoutFuseSeen=false,blackoutBoxPath=nil,blackoutBoxAttempted=false,
		lastBlackoutDeferredCueAt=-math.huge,fuseInFlight=false,
		lastDoorSoundAt=-math.huge,mainFlushDoorUntil=0,mainFlushExitUntil=0,
		elevatorCountdownStopAt=-math.huge,elevatorCountdownPendingUntil=0,
		elevatorCountdownHoldUntil=0,elevatorCountdownAccepted=false,
		floorTransitionConfirmed=false,floorTransitionAt=-math.huge,
		floorTransitionSnapshot=nil,
		soundMapRef=workspace:FindFirstChild("Map") }
	local runId = 0
	local looseFuses -- forward-declared for door and blackout handlers
	-- Countdown StopSound has no Parent or player identifier. It is only a hint
	-- until the watchdog corroborates it with a recent elevator approach.
	local function resetCountdownSignal()
		farm.elevatorCountdownStopAt = -math.huge
		farm.elevatorCountdownPendingUntil = 0
		farm.elevatorCountdownHoldUntil = 0
		farm.elevatorCountdownAccepted = false
	end
	local function resetFlushSignals()
		resetCountdownSignal()
		farm.floorTransitionConfirmed = false
		farm.floorTransitionAt = -math.huge
		farm.floorTransitionSnapshot = nil
		farm.elevatorSoundPath = nil
		UNLOAD.elevatorSoundPath = nil
		farm.elevatorSoundAt = -math.huge
		farm.elevatorSoundWaitSince = nil
		farm.elevatorSoundFallbackLogged = false
		farm.pendingDoorPath = nil
		farm.pendingDoorAt = -math.huge
		farm.mainFlushTarget = nil
		farm.lastPromptTarget = nil
		farm.lastPromptAt = -math.huge
		UNLOAD.verifiedHandoffUntil = 0
		farm.mainFlushAt = -math.huge
		farm.mainFlushUntil = 0
		farm.lastDoorSoundAt = -math.huge
		farm.mainFlushDoorUntil = 0
		farm.mainFlushExitUntil = 0
		farm.mainCompletionTarget = nil
		farm.mainCompletionAt = -math.huge
		farm.mainCompletionUntil = 0
		farm.mainCompletionDoorUntil = 0
		farm.mainCompletionExitUntil = 0
		farm.blackoutCueAt = -math.huge
		farm.blackoutPendingUntil = 0
        farm.blackoutActive = false
        farm.blackoutHandled = false
        farm.blackoutStartedAt = -math.huge
        farm.blackoutFuseSeen = false
        farm.blackoutLastFuseAt = -math.huge
        farm.blackoutBoxPath = nil
        farm.blackoutBoxAttempted = false
		farm.lastFuseAttemptAt = -math.huge
		farm.lastBlackoutDeferredCueAt = -math.huge
		farm.fuseInFlight = false
	end

	-- Door closing is the final floor-complete cue in this game.
	-- If the map model is reused, wait until genuinely fresh objectives appear
	-- instead of re-entering old objectives whose replicated progress is stale.
	local function snapshotFloorObjectives()
		local snapshot = {}
		for _, machine in ipairs(getMachines()) do snapshot[machine] = { progress=getProgress(machine) } end
		for _, machine in ipairs(getBigMachines()) do snapshot[machine] = { progress=getProgress(machine) } end
		return snapshot
	end
	local function freshFloorObjectivesPresent()
		if not farm.floorTransitionConfirmed then return false end
		if os.clock() - farm.floorTransitionAt < 0.5 then return false end
		local snapshot = farm.floorTransitionSnapshot or {}
		for _, group in ipairs({getMachines(),getBigMachines()}) do
			for _, machine in ipairs(group) do
				local prompt = getPrompt(machine)
				if prompt and prompt.Enabled and not isComplete(machine) then
					if snapshot[machine] == nil then
						-- Newly spawned model, not just an old replicated percentage.
						return true
					else
						local before = snapshot[machine].progress
						local after = getProgress(machine)
						if type(before) == "number" and before >= MACHINE.DoneValue
							and type(after) == "number" and after < MACHINE.DoneValue * 0.2 then
							return true
						end
					end
				end
			end
		end
		return false
	end
	-- MainMachineCompleted is the actual completion cue. MainMachineFlush
	-- is only a secondary sound and must never finalize a machine by itself.
	-- A door opening shortly after completion can corroborate the transition,
	-- provided all other machine progress is complete and no blackout is active.
	local function mainDoorVerified()
		local now = os.clock()
		local main = farm.mainCompletionTarget
		if not main or workspace:FindFirstChild("Map") ~= farm.soundMapRef
			or not UNLOAD.floorState.seen then return false end
		-- A recent Fuses cue takes precedence: complete the blackout work
		-- instead of treating door audio as proof that the exit is ready.
		if now - (farm.blackoutCueAt or -math.huge) <= 8 then return false end
		if now < (farm.mainCompletionExitUntil or 0) then return true end
		if now > (farm.mainCompletionDoorUntil or 0)
			or now <= (farm.blackoutPendingUntil or 0) then return false end
		for _, machine in ipairs(getMachines()) do
			if not isComplete(machine) then return false end
		end
		for _, machine in ipairs(getBigMachines()) do
			if machine ~= main and not isComplete(machine) then return false end
		end
		farm.mainCompletionExitUntil = now + 12.0
		increment("soundMainCompletionVerified")
		debugEvent("SOUND", "main_completed_door_handoff", {
			mainTarget=main.Name,transitionHoldSeconds=12,
			evidence="completed_sound_plus_door_other_objectives_complete",
		})
		return true
	end

	-- The Sound remote is client-bound (OnClientEvent), not something we FireServer.
	-- Cobalt's firesignal examples describe payloads, not the way to listen.
	-- A local "Done" cue may lead progress replication by a few frames.
	local function machineKind(machine)
		if not machine then return nil end
		local oil = workspace:FindFirstChild("OilMachines")
		local computers = workspace:FindFirstChild("Computers")
		if oil and machine:IsDescendantOf(oil) then return "Machine" end
		if computers and machine:IsDescendantOf(computers) then return "Computer" end
		local big = resolveWorkspacePath("Map.SpecialFolder.BigMachine")
		if big and machine:IsDescendantOf(big) then
			if machine.Name == "Machine" then return "Machine" end
			if machine.Name == "Computer" then return "Computer" end
		end
		return nil
	end

	-- Both elevator models exist, but only the one that actually plays the
	-- opening sound after the machines are finished is the correct exit.
	-- Match sound Parent by ancestry, not an assumed Elevator/ExitElevator name.
	local function elevatorPathFromDoor(parent)
		if typeof(parent) ~= "Instance" then return nil end
		for _, path in ipairs({ MACHINE.Elevator, MACHINE.ElevatorFallback, "ExitElevator" }) do
			local elevator = resolveWorkspacePath(path)
			if elevator and (parent == elevator or parent:IsDescendantOf(elevator)) then
				return path
			end
		end
		return nil
	end
    -- Door names are stable roles even when the physical exit swaps each floor.
    -- Save the LAST closing door across map resets, then use its opposite side
    -- to decide which fusebox receives blackout fuses.
    local function oppositeElevatorPath(path)
        if path == MACHINE.Elevator or path == "ExitElevator" then
            return MACHINE.ElevatorFallback
        elseif path == MACHINE.ElevatorFallback then
            return MACHINE.Elevator
        end
        return nil
    end
    local function blackoutFuseboxPath()
        local lastClosed = UNLOAD.lastClosedElevatorPath
        local opposite = oppositeElevatorPath(lastClosed)
        if opposite == MACHINE.Elevator then
            return MACHINE.Fuseboxes[2],opposite,"opposite_last_closed"
        elseif opposite == MACHINE.ElevatorFallback then
            return MACHINE.Fuseboxes[1],opposite,"opposite_last_closed"
        end
        -- If we missed the preceding door close, the exit's open sound
        -- identifies the correct side. Never blindly choose both boxes here.
        local opened = farm.elevatorSoundPath
        if opened == MACHINE.Elevator then
            return MACHINE.Fuseboxes[2],opened,"opened_exit_fallback"
        elseif opened == MACHINE.ElevatorFallback then
            return MACHINE.Fuseboxes[1],opened,"opened_exit_fallback"
        end
        local unique,uniqueSide
        for _,entry in ipairs({
            {path=MACHINE.Fuseboxes[1],side=MACHINE.ElevatorFallback},
            {path=MACHINE.Fuseboxes[2],side=MACHINE.Elevator},
        }) do
            local prompt=resolveWorkspacePath(entry.path)
            if prompt and prompt:IsA("ProximityPrompt") and prompt.Enabled then
                if unique then return nil,nil,"ambiguous_active_boxes" end
                unique,uniqueSide=entry.path,entry.side
            end
        end
        if unique then return unique,uniqueSide,"single_enabled_fusebox" end
        return nil,nil,"door_identity_unavailable"
    end

	local function selectElevatorFromDoor(path, why)
		if not path or farm.floorTransitionConfirmed then return end
		local previous = farm.elevatorSoundPath
		farm.elevatorSoundPath = path
		UNLOAD.elevatorSoundPath = path
		farm.elevatorSoundAt = os.clock()
		farm.elevatorSoundWaitSince = nil
		farm.elevatorSoundFallbackLogged = false
		if previous == path then return end
		increment("soundElevatorSelections")
		farm.elevatorAlternateCommitted = false
		farm.elevatorAlternateTried = false
		farm.elevatorRecoveryAt = nil
		farm.elevatorRecoveryCount = 0
		farm.elevatorWatchFired = false
		farm.elevatorHoldCorrections = 0
		farm.elevatorServerRelocated = false
		farm.elevatorServerRelocatedAt = nil
		-- A stale countdown or old fallback must not block a newly identified lift.
		resetCountdownSignal()
		if farm.elevatorEmergencyLocked then
			farm.elevatorEmergencyLocked = false
			farm.finalizing = false
		end
		if farm.elevatorSource and farm.elevatorSource ~= path then
			-- A default route may already have started before sound replication.
			-- Drop that destination so the watchdog routes to the sounding lift.
			-- Avoid cancelling a tween mid-surface-return; once it exits, reroute.
			farm.elevatorTarget = nil
			farm.elevatorPlatform = nil
			farm.elevatorEntryTouched = false
			farm.elevatorEntryAttempts = 0
			farm.elevatorContactRetryAt = 0
			increment("soundElevatorReroutes")
		end
		debugEvent("SOUND", "elevator_exit_identified_by_open_sound", {
			path=path,previous=previous or "none",
			previousDestination=farm.elevatorSource or "none",reason=why,
		})
	end

	local function acceptSoundCue(packet)
		if not alive or typeof(packet) ~= "table" then return end
		local now = os.clock()
		local name = packet.SoundName
		local kind, category
		local doorPath
		if name == "Done" and packet.IsVoiceLine == true
			and packet.Player == player
			and (packet.Category == "Machine" or packet.Category == "Computer") then
			kind, category = "done", packet.Category
		elseif name == "MainMachineFillingUp" and packet.IsVoiceLine == false then
			kind = "main_ready"
		elseif name == "MainMachineFlush" and packet.IsVoiceLine == false then
			kind = "main_flush"
		elseif name == "MainMachineCompleted" and packet.IsVoiceLine == false then
			kind = "main_completed"
		elseif name == "Fuses" and packet.IsVoiceLine == false then
			kind = "blackout"
		elseif name == "ElevatorDoor" and packet.IsVoiceLine == false then
			doorPath = elevatorPathFromDoor(packet.Parent)
			if not doorPath then
				increment("soundElevatorUnmappedDoor")
				debugThrottled("unmapped_elevator_open",2,"SOUND","unmapped_elevator_door", {
					parent=typeof(packet.Parent) == "Instance" and packet.Parent:GetFullName() or "missing" },"WARN")
				return
			end
			kind = "door_open"
		elseif name == "ElevatorDoorClosing" and packet.IsVoiceLine == false then
			doorPath = elevatorPathFromDoor(packet.Parent)
			if not doorPath then
				increment("soundElevatorUnmappedDoor")
				debugThrottled("unmapped_elevator_close",2,"SOUND","unmapped_elevator_closing", {
					parent=typeof(packet.Parent) == "Instance" and packet.Parent:GetFullName() or "missing" },"WARN")
				return
			end
			kind = "door_close"
		elseif name == "ElevatorCountdown" and packet.Action == "StopSound" then
			kind = "countdown_stop"
		else
			return
		end
		if not farm.enabled then
			-- Closing door direction is still useful if machine autofarm was
			-- enabled after the starting door animation.
			if kind == "door_close" then UNLOAD.lastClosedElevatorPath = doorPath end
			return
		end
		if workspace:FindFirstChild("Map") ~= farm.soundMapRef then
			farm.soundMapRef = workspace:FindFirstChild("Map")
			farm.soundDoneTarget,farm.soundDoneUntil = nil,0
			farm.mainReadyUntil,farm.elevatorDoorOpenUntil = 0,0
			resetFlushSignals()
		end
		-- Suppress doubled sound packets before recording a second handoff.
		local fingerprint = kind .. ":" .. tostring(category or "") .. ":" .. tostring(doorPath or "")
		if fingerprint == farm.lastSoundFingerprint
			and now - (farm.lastSoundAt or -math.huge) < 0.16 then return end
		farm.lastSoundFingerprint,farm.lastSoundAt = fingerprint,now
		farm.soundSerial += 1
		farm.soundLast = { kind=kind,category=category,at=now }
		if kind == "done" then
			increment(category == "Machine" and "soundOilDone" or "soundComputerDone")
			local target = farm.target
			-- Completion audio can arrive after the prompt disables or the
			-- old machine has already stopped being considered "placed".
			-- Accept it only for the current matching objective with recent
			-- local interaction evidence, or visible near-complete progress.
			local recentlyUsed = target and farm.lastPromptTarget == target
				and now - (farm.lastPromptAt or -math.huge) <= 3.0
			local nearDone = target and (getProgress(target) or 0) >= 92
			if target and machineKind(target) == category and isComplete(target) then
				-- The progress value got to 100 before this sound packet. This is
				-- confirmed completion, not an ambiguous/unmatched sound.
				farm.soundDoneTarget = target
				farm.soundDoneUntil = now + 1.5
				UNLOAD.verifiedHandoffUntil = now + 1.5
				debugEvent("SOUND", "machine_done_confirmed_by_progress", {
					target=target.Name,category=category,progress=getProgress(target),
				})
			elseif target and machineKind(target) == category and not isComplete(target)
				and (recentlyUsed or nearDone or farm.placed) then
				farm.soundDoneTarget = target
				farm.soundDoneUntil = now + 3.0 -- allow replication to catch up
				UNLOAD.verifiedHandoffUntil = now + 2.5
				if not farm.placed then increment("soundDoneRecovered") end
				debugEvent("SOUND", "local_machine_done_cue", {
					target=target.Name,category=category,
					evidence=recentlyUsed and "recent_prompt" or nearDone and "near_complete" or "placed",
				})
			else
				increment("soundDoneAmbiguous")
				debugThrottled("sound_done_unmatched", 0.7, "SOUND", "done_without_active_match", {
					category=category,target=target and target.Name or "none",
					placed=farm.placed,prior=recentlyUsed == true })
			end
		elseif kind == "main_ready" then
			-- Confirmed game cue: all BASE oil/computer objectives are done.
			-- Prefer the main machine when its prompt is actually enabled, even if
			-- a base objective still appears unfinished during replication.
			increment("soundMainReady")
			farm.mainReadyUntil = now + 15.0
			debugEvent("SOUND", "base_objectives_completed", {
				priority="main_machine_next",verifiedBy="MainMachineFillingUp",
			})
		elseif kind == "main_flush" then
			-- Flush may carry a detached Oil instance, so Parent is intentionally
			-- ignored. It is informational, NOT a completion trigger.
			increment("soundMainFlush")
			farm.mainFlushAt = now
			farm.mainFlushUntil = now + 5.0
			debugEvent("SOUND", "main_machine_flush", {
				parentName=typeof(packet.Parent) == "Instance" and packet.Parent.Name or "detached_or_nil",
				phase="secondary_audio",verified=false,
			})
		elseif kind == "main_completed" then
			increment("soundMainCompleted")
			local main = farm.target and isBigMachine(farm.target) and farm.target or nil
			farm.mainCompletionTarget = main
			farm.mainCompletionAt = now
			farm.mainCompletionUntil = now + 12.0
			farm.mainReadyUntil = 0
			if main and not isComplete(main) then
				farm.soundDoneTarget = main
				farm.soundDoneUntil = now + 1.2
			end
			if main and now - (farm.lastDoorSoundAt or -math.huge) <= 2.0 then
				farm.mainCompletionDoorUntil = now + 2.0
				increment("soundMainCompletedDoor")
			end
			-- In a few frames the opening cue may arrive before completion audio.
			-- Consume that same-floor cue rather than guessing an elevator model.
			if farm.pendingDoorPath and now - farm.pendingDoorAt <= 2.0 then
				selectElevatorFromDoor(farm.pendingDoorPath, "door_immediately_preceded_main_completion")
			end
			debugEvent("SOUND", "main_machine_completed", {
				mainTarget=main and main.Name or "none",
				phase="main_completed",pairedDoor=farm.mainCompletionDoorUntil > now,
			})
		elseif kind == "blackout" then
			increment("soundBlackout")
			farm.blackoutCueAt = now
            farm.blackoutActive = true
            farm.blackoutHandled = false
            farm.blackoutStartedAt = now
            farm.blackoutFuseSeen = false
            farm.blackoutLastFuseAt = -math.huge
            farm.blackoutBoxPath = nil
            farm.blackoutBoxAttempted = false
			farm.blackoutPendingUntil = now + 12.0
			-- A blackout does not prove that an elevator is open or all
			-- machines are done. Fusebox handling takes priority if enabled.
			debugEvent("SOUND", "blackout_started", {
				fuseboxesEnabled=OPTIONS.Fuseboxes,priority="fusebox_check",
			})
		elseif kind == "door_close" then
			-- Doors can close at the START of a floor or when Auto Hide uses an
			-- elevator. Remember the side, but do not conclude an unfinished floor
			-- is complete just because a door closed (observed in v2.6.47 debug).
			UNLOAD.lastClosedElevatorPath = doorPath
			increment("soundElevatorDoorClosing")
			debugEvent("SOUND", "last_closing_elevator_saved", {
				path=doorPath,nextFuseboxSide=oppositeElevatorPath(doorPath) or "unknown",
			})
			local nextUnfinished, objectiveStatus = pickMachine()
			local readyToExit = (farm.allDoneSince ~= nil or objectiveStatus == "done")
				and nextUnfinished == nil
				and not farm.blackoutActive
				and (not looseFuses or #looseFuses() == 0)
			local mainCue = now - farm.mainCompletionAt <= 30
			local bigs = getBigMachines()
			local bigsCompleted = #bigs > 0
			for _, mainMachine in ipairs(bigs) do
				if not isComplete(mainMachine) then bigsCompleted = false break end
			end
			-- Some elevators close during hiding or when the next floor starts.
			-- Require evidence that the MAIN stage finished, not merely an empty
			-- base-machine folder or a shelter's cached elevator target.
			local finishing = readyToExit and (mainCue or bigsCompleted)
				and (farm.finalizing or farm.allDoneSince ~= nil or farm.elevatorTarget ~= nil)
			if not finishing then
				increment("doorClosingIgnoredDuringWork")
				debugEvent("SOUND", "door_closing_not_floor_complete", {
				status=objectiveStatus,unfinished=nextUnfinished and nextUnfinished.Name or "none",
				finalizing=farm.finalizing == true,ready=readyToExit,
				path=doorPath,
			}, "INFO")
			elseif not farm.floorTransitionConfirmed then
				farm.floorTransitionConfirmed = true
				farm.floorTransitionAt = now
				farm.floorTransitionSnapshot = snapshotFloorObjectives()
				farm.blackoutPendingUntil = 0
				farm.elevatorCountdownPendingUntil = 0
				farm.elevatorCountdownHoldUntil = now + 20.0
				farm.allDoneSince = farm.allDoneSince or now
				UNLOAD.floorState.seen = true
				UNLOAD.floorState.finished = true
				UNLOAD.floorState.completionReason = "elevator_door_closing_verified"
				increment("soundFloorTransitions")
				debugEvent("SOUND", "floor_completed_door_closing", {
					phase="transition",stopRetries=true,
					confirmedBy="door_plus_completed_objectives",
				})
			end
		elseif kind == "countdown_stop" then
			-- An earlier transition hint, NOT final floor completion.
			-- It may also be fired when a timer is cancelled or a round resets.
			increment("soundElevatorCountdownStop")
			farm.elevatorCountdownStopAt = now
			farm.elevatorCountdownPendingUntil = now + 3.0
			debugEvent("SOUND", "elevator_countdown_stopped", {
				phase="elevator_arrival_candidate",verified=false,
				floorDone=farm.allDoneSince ~= nil,
				targetSelected=farm.elevatorTarget ~= nil,
			})
		elseif kind == "door_open" then
			increment("soundElevatorDoor")
			farm.lastDoorSoundAt = now
			farm.pendingDoorPath,farm.pendingDoorAt = doorPath,now
			-- Only an opening cue AFTER machine completion selects the exit.
			-- A door opening mid-round (e.g. during Auto Hide) is not enough.
			local endStage = farm.mainCompletionAt > -math.huge
				or farm.allDoneSince ~= nil
				or (UNLOAD.floorState.seen and machinesDone())
			if endStage and not farm.floorTransitionConfirmed then
				selectElevatorFromDoor(doorPath, "opened_after_all_machines")
			end
			if farm.mainCompletionTarget
				and now <= (farm.mainCompletionUntil or 0) then
				farm.mainCompletionDoorUntil = now + 2.0
				increment("soundMainCompletedDoor")
				debugEvent("SOUND", "main_completed_followed_by_door", {
					mainTarget=farm.mainCompletionTarget.Name,phase="elevator_opening",
					path=doorPath,
				})
			end
			local root = getPlayerRoot()
			local soundPosition = targetPosition(packet.Parent)
			local nearDoor = root and soundPosition
				and (root.Position - soundPosition).Magnitude <= 55
			if nearDoor and farm.elevatorSoundPath == doorPath then
				farm.elevatorDoorOpenUntil = now + 2.0
				farm.elevatorContactRetryAt = math.min(farm.elevatorContactRetryAt or 0, now)
			end
			debugEvent("SOUND", "elevator_door_open", {
				nearPlayer=nearDoor == true,selected=farm.elevatorSoundPath == doorPath,
				path=doorPath,confirmsEntry=false })
		end
	end

	task.spawn(function()
		local remotes = game:GetService("ReplicatedStorage"):WaitForChild("Remotes", 10)
		local event = remotes and remotes:WaitForChild("Sound", 10)
		if not alive then return end
		if event and event:IsA("RemoteEvent") then
			track(event.OnClientEvent:Connect(function(packet)
				local ok, err = pcall(acceptSoundCue, packet)
				if not ok then
					increment("workerErrors")
					debugThrottled("sound_cue_failure",2,"SOUND","cue_error",{error=err},"ERROR")
				end
			end))
			debugEvent("SOUND", "listener_attached", { remote="ReplicatedStorage.Remotes.Sound" })
		else
			debugEvent("SOUND", "listener_missing", { remote="ReplicatedStorage.Remotes.Sound" },"WARN")
		end
	end)
	local elevatorPreference = 1
	local function move(position, keepGoing, mode)
		farm.moving = true
		local arrived = teleportCharacter(CFrame.new(position), keepGoing, "machine", mode)
		farm.moving = false
		return arrived
	end
	local function elevatorMove(position, keepGoing, instantHide)
		if farm.elevatorTransit or farm.floorTransitionConfirmed then return false end
		farm.elevatorTransit = true
		farm.elevatorTarget = position
		local ok, arrived = pcall(move, position,
			function() return keepGoing() and not farm.floorTransitionConfirmed end,
			instantHide and "hide" or "elevator")
		if instantHide then increment("instantHideMoves") end
		farm.elevatorTransit = false
		if ok and arrived == true then farm.lastElevatorMoveAt = os.clock() end
		if not ok then
			farm.moving = false
			debugEvent("MACHINE", "elevator_move_error", { error=tostring(arrived) }, "ERROR")
			return false
		end
		return arrived == true
	end
	local function elevatorPlatform(elevator)
		if not elevator then return nil end
		local reference = targetPosition(elevator)
		local fallback = reference and (reference + Vector3.new(0, MACHINE.ElevatorHeight, 0))
		if not fallback then return nil end
		local best, score, bestKind = nil, -math.huge, nil
		local scanned = 0
		local function consider(part, exterior)
			if not part:IsA("BasePart") or part.Size.X < 3 or part.Size.Z < 3
				or part.Size.X > 70 or part.Size.Z > 70
				or part.CFrame.UpVector.Y < 0.8 then return end
			local gap = Vector3.new(part.Position.X - fallback.X, 0,
				part.Position.Z - fallback.Z).Magnitude
			if gap > 23 or math.abs(part.Position.Y - fallback.Y) > 32 then return end
			local name = part.Name:lower()
			if name:find("door") or name:find("wall") or name:find("glass")
				or name:find("ceiling") or name:find("roof") then return end
			local strength, kind = 0, "generic_floor"
			if name:find("floor") or name:find("platform") then strength, kind = 15, "named_floor"
			elseif name:find("inside") or name:find("interior") then strength, kind = 13, "interior"
			elseif name:find("elevator") then strength, kind = 12, "elevator_part"
			elseif name:find("base") then strength, kind = 10, "base"
			elseif name:find("trigger") or name:find("zone") then strength, kind = 9, "trigger"
			elseif part.CanCollide and part.Size.Y <= 5 then strength = 7 end
			if strength == 0 then return end
			if not part.CanCollide and kind == "generic_floor" then return end
			if exterior then
				local ancestor = part.Parent and part.Parent.Name:lower() or ""
				if name:find("elevator") or name:find("exit") or ancestor:find("elevator") then
					strength -= 4
				else
					-- A nearby unnamed floor may help select a position, but it is
					-- NOT proof of elevator entry.
					if not part.Anchored or not part.CanCollide or gap > 9 or part.Size.Y > 8 then return end
					strength -= 7
					kind = "nearby_floor_unverified"
				end
			end
			strength += part.CanCollide and 2 or 0
			strength -= gap * 0.07 + math.abs(part.Position.Y - fallback.Y) * 0.16
			scanned += 1
			if strength > score then best, score, bestKind = part, strength, kind end
		end
		if elevator:IsA("BasePart") then consider(elevator, false) end
		for _, part in ipairs(elevator:GetDescendants()) do consider(part, false) end
		if not best then
			increment("elevatorWideScans")
			local ok, nearby = pcall(function()
				return workspace:GetPartBoundsInBox(
					CFrame.new(reference + Vector3.new(0, -10, 0)),
					Vector3.new(46, 72, 46))
			end)
			if ok then for _, part in ipairs(nearby) do
				if not part:IsDescendantOf(elevator) then consider(part, true) end
			end end
		end
		if not best then
			local ok, nearby = pcall(function() return workspace:GetPartBoundsInRadius(fallback, 23) end)
			if ok then for _, part in ipairs(nearby) do
				if not part:IsDescendantOf(elevator) then consider(part, true) end
			end end
		end
		increment("elevatorCandidateScans")
		if best and score >= 5 then
			if bestKind == "generic_floor" then increment("elevatorGenericFloors") end
			local pos = best.Position + best.CFrame.UpVector * (best.Size.Y * 0.5 + 2.75)
			if bestKind == "nearby_floor_unverified" or not best.CanCollide then
				return pos, nil, bestKind .. "_position_only", scanned
			end
			return pos, best, bestKind, scanned
		end
		-- Never aim at an arbitrary -20 stud offset: it may be below the map.
		if UNLOAD.voidGuard and UNLOAD.voidGuard.landingOK(fallback,"elevator_fallback") then
			return fallback,nil,"unverified_offset_grounded",scanned
		end
		debugThrottled("elevator_void_fallback",2,"VOID",
			"unsupported_elevator_offset_skipped",{position=tostring(fallback)},"WARN")
		return nil
	end
	local function platformContains(part, point)
		if not part or not part.Parent then return false end
		local localPoint = part.CFrame:PointToObjectSpace(point)
		return math.abs(localPoint.X) <= part.Size.X * 0.5 + 0.3
			and math.abs(localPoint.Z) <= part.Size.Z * 0.5 + 0.3
			and localPoint.Y >= part.Size.Y * 0.5 - 1.5
			and localPoint.Y <= part.Size.Y * 0.5 + 6.5
	end
	local function inElevatorSignal()
		local character = player.Character
		for _, holder in ipairs({ player,character }) do
			if holder then
				for _, key in ipairs({ "InElevator","IsInElevator","InsideElevator","InExitElevator","OnElevator" }) do
					if holder:GetAttribute(key) == true then return key end
				end
			end
		end
		return nil
	end
	local function verifyElevatorPosition()
		local root = getPlayerRoot()
		local near = root ~= nil and farm.elevatorTarget ~= nil
			and (root.Position - farm.elevatorTarget).Magnitude <= 7
		local geometry = near and platformContains(farm.elevatorPlatform, root.Position) or false
		local signal = inElevatorSignal()
		return near == true, geometry == true, signal
	end
	local function profileElevators()
		if farm.elevatorProfiled then return end
		farm.elevatorProfiled = true
		for _, path in ipairs({ MACHINE.Elevator, MACHINE.ElevatorFallback }) do
			local instance = resolveWorkspacePath(path)
			local sample, total = {}, 0
			if instance then
				local function samplePart(part)
					if not part:IsA("BasePart") then return end
					total += 1
					if #sample < 14 then
						table.insert(sample, part.Name .. ":" .. tostring(part.Size)
							.. ":collide=" .. tostring(part.CanCollide)
							.. ":touch=" .. tostring(part.CanTouch))
					end
				end
				samplePart(instance)
				for _, part in ipairs(instance:GetDescendants()) do samplePart(part) end
			end
			debugEvent("MACHINE", "elevator_geometry_profile", {
				path=path, class=instance and instance.ClassName or "missing",
				parts=total, sample=table.concat(sample, " | "),
			})
		end
	end
	-- CFrame arrival and standing on a collidable elevator floor are NOT
	-- proof that a Touched/zone entry registered on the server. In previous
	-- builds a generic floor caused this function to return without walking.
	-- Use a few short, raycast-supported Humanoid steps instead.
	local function touchElevatorEntrance(active)
		if not farm.elevatorTarget or farm.elevatorTransit or farm.elevatorServerRelocated
			or farm.elevatorEntryAttempts >= 3
			or os.clock() < (farm.elevatorContactRetryAt or 0) then return end
		local root = getPlayerRoot()
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not root or not humanoid or not active() or (getHealth() or 0) <= 0 then return end
		if (root.Position - farm.elevatorTarget).Magnitude > 7
			or twistedNear(root.Position) or (skillcheckProtected and skillcheckProtected()) then return end
		local _, geometry, signal = verifyElevatorPosition()
		if signal then farm.elevatorEntryTouched = true return end
		farm.elevatorEntryAttempts += 1
		farm.elevatorContactRetryAt = os.clock() + 1.6
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { character }
		local function supported(position)
			local ok, hit = pcall(function()
				return workspace:Raycast(position + Vector3.new(0, 2, 0),
					Vector3.new(0, -7.5, 0), params)
			end)
			return ok and hit and hit.Instance and hit.Instance.CanCollide
				and hit.Normal.Y > 0.70
				and position.Y - hit.Position.Y >= 1.0
				and position.Y - hit.Position.Y <= 5.0
				and (not farm.elevatorPlatform or platformContains(farm.elevatorPlatform,position))
		end
		local start = root.Position
		if not supported(start) then
			increment("elevatorEntryUnsafeSkipped")
			debugEvent("MACHINE", "elevator_contact_unsafe_floor", {
				source=farm.elevatorSource or "none",attempt=farm.elevatorEntryAttempts,
				geometry=geometry,position=tostring(start),
			}, "WARN")
			return
		end
		-- Prefer a named invisible touch zone near the player when present;
		-- otherwise take short guarded teleport steps across supported ground.
		local candidates = {}
		local instance = farm.elevatorSource and resolveWorkspacePath(farm.elevatorSource)
		if instance then
			for _, part in ipairs(instance:GetDescendants()) do
				if part:IsA("BasePart") and part.CanTouch and not part.CanCollide then
					local name = part.Name:lower()
					if name:find("trigger") or name:find("hitbox")
						or name:find("touch") or name:find("zone") then
						local flat = Vector3.new(part.Position.X-start.X, 0, part.Position.Z-start.Z)
						if flat.Magnitude > 0.5 and flat.Magnitude <= 9
							and math.abs(part.Position.Y-start.Y) < 6 then
							table.insert(candidates,{ pos=part.Position,name=part.Name,d=flat.Magnitude })
						end
					end
				end
			end
			table.sort(candidates,function(a,b) return a.d < b.d end)
		end
		local towards = farm.elevatorPlatform and
			Vector3.new(farm.elevatorPlatform.Position.X-start.X,0,
				farm.elevatorPlatform.Position.Z-start.Z) or Vector3.zero
		if #candidates > 0 then
			towards = Vector3.new(candidates[1].pos.X-start.X,0,candidates[1].pos.Z-start.Z)
		end
		if towards.Magnitude < 0.5 then
			towards = Vector3.new(root.CFrame.LookVector.X,0,root.CFrame.LookVector.Z)
		end
		if towards.Magnitude < 0.1 then towards = Vector3.new(1,0,0) end
		local forward = towards.Unit
		local sideways = Vector3.new(-forward.Z,0,forward.X)
		local directions = { forward, sideways, -sideways, -forward }
		local steps = 0
		local moved = 0
		increment("elevatorContactWalks")
		for _, dir in ipairs(directions) do
			if steps >= 3 or not active() or not farm.elevatorTarget
				or (root.Position - farm.elevatorTarget).Magnitude > 9
				or twistedNear(root.Position)
				or (skillcheckProtected and skillcheckProtected()) then break end
			local here = root.Position
			if (here-start).Magnitude > 12 then break end -- possible server transition
			local nextPos = here + dir * 1.65
			if supported(nextPos) and UNLOAD.voidGuard.landingOK(nextPos,"elevator_contact") then
				-- Elevator contact now uses teleport-only steps. Never leave a
				-- Humanoid MoveTo command active when the next pickup phase starts.
				local ok = pcall(function()
					root.AssemblyLinearVelocity = Vector3.zero
					root.AssemblyAngularVelocity = Vector3.zero
					root.CFrame = CFrame.new(nextPos) * (root.CFrame - root.Position)
				end)
				if ok and (root.Position-nextPos).Magnitude <= 2.0 then
					steps += 1
					increment("elevatorTeleportSteps")
					task.wait(0.06)
					moved += (root.Position-here).Magnitude
					if select(3,verifyElevatorPosition()) then break end
				end
			end
		end
		farm.elevatorEntryTouched = steps > 0
		increment("elevatorContactWalkSteps",steps)
		if moved > 0.15 then increment("elevatorContactWalkMoved") end
		increment("elevatorEntryMoves")
		if moved > 0.15 then increment("elevatorEntryMoved") end
		debugEvent("MACHINE", "elevator_entry_teleport_steps", {
			attempt=farm.elevatorEntryAttempts,steps=steps,
			moved=string.format("%.2f",moved),platform=geometry,
			source=farm.elevatorSource or "none",
			triggerCandidate=#candidates>0 and candidates[1].name or "none",
			serverSignal=select(3,verifyElevatorPosition()) or "none",
		}, steps>0 and "INFO" or "WARN")
	end
	local function chooseElevator(paths, avoid)
		local fallback
		for _, path in ipairs(paths) do
			local instance = resolveWorkspacePath(path)
			local spot, platform, detection, scanned = elevatorPlatform(instance)
			if spot then
				local choice = { pos=spot,platform=platform,detection=detection,
					instance=instance,path=path,scanned=scanned }
				-- Avoid repeating exactly the same unverified destination on retries.
				if not avoid or (spot - avoid).Magnitude > 5 then
					if platform then return choice end
					fallback = fallback or choice
				end
			end
		end
		return fallback
	end
	local function applyElevatorChoice(chosen, keepGoing, instantHide)
		-- A new destination must rearm physical contact, even when a previous
		-- position was marked as reached without server-confirmed entry.
		if farm.elevatorSource ~= chosen.path or not farm.elevatorTarget
			or (farm.elevatorTarget - chosen.pos).Magnitude > 5 then
			farm.elevatorEntryTouched = false
			farm.elevatorEntryAttempts = 0
			farm.elevatorContactRetryAt = 0
		end
		farm.elevatorPlatform = chosen.platform
		farm.elevatorSource = chosen.path
		farm.elevatorDetection = chosen.detection
		local arrived = elevatorMove(chosen.pos, keepGoing, instantHide)
		if chosen.platform then increment("elevatorPlatformDetections") end
		return arrived
	end
	local function goElevator(advancePreference, keepGoing)
		keepGoing = keepGoing or function() return alive and farm.enabled end
		local paths = elevatorPreference == 1
			and { MACHINE.Elevator,MACHINE.ElevatorFallback }
			or { MACHINE.ElevatorFallback,MACHINE.Elevator }
		local chosen = chooseElevator(paths)
		if not chosen then return false end
		local arrived = applyElevatorChoice(chosen, keepGoing, true)
		if arrived and advancePreference then elevatorPreference = elevatorPreference == 1 and 2 or 1 end
		return arrived
	end
	-- Auto Hide is NOT floor completion: pick a supported safe refuge. Never
	-- commit the final elevator selection or use an ungrounded offset to hide.
	local function goHideShelter(keepGoing)
		local root = getPlayerRoot()
		if not root then return false end
		local choices = {}
		for _, path in ipairs({ MACHINE.Elevator, MACHINE.ElevatorFallback }) do
			local inst = resolveWorkspacePath(path)
			local pos, platform, detection = elevatorPlatform(inst)
			if pos and not twistedNear(pos, MACHINE.EmergencyDistance + 8)
				and UNLOAD.voidGuard.landingOK(pos, "hide") then
				table.insert(choices, {
					pos=pos,path=path,platform=platform,detection=detection,
					distance=(root.Position-pos).Magnitude,
				})
			end
		end
		table.sort(choices, function(a,b) return a.distance < b.distance end)
		for _, chosen in ipairs(choices) do
			if applyElevatorChoice(chosen,keepGoing,true) then
				debugEvent("HIDE","shelter_reached", {
					path=chosen.path,distance=string.format("%.1f",chosen.distance),
				})
				return true
			end
		end
		-- Last grounded checkpoint is a fallback ONLY when it is on this map,
		-- physically supported, and outside the immediate enemy radius.
		local guard = UNLOAD.voidGuard
		local home = guard and guard.safeCFrame
		if home and guard.safeMap == workspace:FindFirstChild("Map")
			and not twistedNear(home.Position, MACHINE.EmergencyDistance + 8)
			and guard.landingOK(home.Position + Vector3.new(0,1,0),"hide") then
			return move(home.Position + Vector3.new(0,1,0),keepGoing,"hide")
		end
		increment("hideNoShelter")
		debugThrottled("hide_no_shelter",1.5,"HIDE","no_supported_shelter",{},"WARN")
		return false
	end
    -- looseFuses was forward-declared for the sound and elevator guards.
	local function finishAtElevator(active, alternative)
        if OPTIONS.Fuseboxes and (farm.blackoutActive or #looseFuses() > 0) then
            debugThrottled("elevator_wait_fuses",1,"FUSE","elevator_blocked_by_fuses",
                { remaining=#looseFuses() },"INFO")
            return false
        end
		-- Wait briefly for the door-opening cue, rather than racing to whichever
		-- elevator happens to be first in the old list. Geometry is only fallback.
		local now = os.clock()
		local soundPath = farm.elevatorSoundPath
		if soundPath and not resolveWorkspacePath(soundPath) then
			debugEvent("SOUND", "sounding_elevator_removed", { path=soundPath },"WARN")
			farm.elevatorSoundPath = nil
			UNLOAD.elevatorSoundPath = nil
			soundPath = nil
		end
		if not soundPath then
			farm.elevatorSoundWaitSince = farm.elevatorSoundWaitSince or now
			if now - farm.elevatorSoundWaitSince < 2.0 then return false end
			if not farm.elevatorSoundFallbackLogged then
				farm.elevatorSoundFallbackLogged = true
				increment("soundElevatorSoundFallbacks")
				debugEvent("SOUND", "elevator_open_cue_timeout", {
					fallback="geometry",waitSeconds=2.0 },"WARN")
			end
		end
		profileElevators()
		local previous = farm.elevatorTarget
		local primary = { MACHINE.Elevator,MACHINE.ElevatorFallback }
		-- NEVER select the opposite elevator as a backup while a matching
		-- opening sound has identified the real exit for this floor.
		if soundPath then alternative = false end
		local paths = soundPath and { soundPath }
			or (alternative and { MACHINE.ElevatorFallback,MACHINE.Elevator } or primary)
		if not soundPath and farm.elevatorAlternateCommitted and farm.elevatorSource then
			-- Never bounce back to the first unverified elevator after committing
			-- to the backup for the current floor.
			paths = { farm.elevatorSource }
			alternative = false
		end
		local chosen = chooseElevator(paths, alternative and previous or nil)
		if alternative and chosen and previous and chosen.platform == nil
			and (chosen.pos-previous).Magnitude > 180 then
			-- A cross-map alternate is useful ONLY after the first elevator has
			-- failed to verify for a few seconds; do not blindly reject it forever.
			local elapsed = os.clock() - (farm.allDoneSince or os.clock())
			if elapsed < 3.5 then
				debugThrottled("elevator_long_alternate",4,"MACHINE","elevator_alternate_waiting",
					{ from=farm.elevatorSource or "none",to=chosen.path,
					  seconds=string.format("%.1f",elapsed),
					  distance=string.format("%.1f",(chosen.pos-previous).Magnitude) },"WARN")
				chosen = nil
			else
				increment("elevatorFarAlternateAttempts")
				debugEvent("MACHINE", "elevator_far_alternate_attempt", {
					from=farm.elevatorSource or "none",to=chosen.path,
					distance=string.format("%.1f",(chosen.pos-previous).Magnitude),
				},"WARN")
			end
		end
		-- A first-floor death in v2.6.30 proved that refusing this
		-- distinct fallback strands the player on an unverified exit offset.
		-- Try the fallback ONCE when the primary has not produced a server
		-- transition. This is a recovery attempt, not verified elevator entry.
		if alternative and chosen and chosen.path == MACHINE.ElevatorFallback
			and chosen.platform == nil and resolveWorkspacePath(MACHINE.Elevator) then
			increment("elevatorUnverifiedBackupUsed")
			debugEvent("MACHINE", "elevator_backup_recovery_attempt", {
				from=farm.elevatorSource or "none", to=chosen.path,
				detection=chosen.detection, reason="primary_unverified",
			}, "WARN")
		end
		if not chosen and alternative then
			increment("elevatorAlternateUnavailable")
			debugEvent("MACHINE", "elevator_alternate_missing", { previous=tostring(previous) }, "WARN")
			return false
		end
		if not chosen then
			debugEvent("MACHINE", "elevator_location_missing", nil, "WARN")
			return false
		end
		if alternative then
			increment("elevatorAlternateAttempts")
			debugEvent("MACHINE", "elevator_alternate_target", {
				from=farm.elevatorSource or "none",to=chosen.path,
				distance=previous and string.format("%.1f",(chosen.pos - previous).Magnitude) or "none",
				detection=chosen.detection,candidateParts=chosen.scanned,
			})
		end
		local arrived = applyElevatorChoice(chosen, active)
		if arrived and alternative then
			farm.elevatorAlternateCommitted = true
			increment("elevatorAlternateCommitted")
		end
		if arrived then RunService.Heartbeat:Wait() end
		local near, geometry, signal = verifyElevatorPosition()
		if arrived then
			increment("elevatorHoldChecks")
			if not geometry and not signal then increment("elevatorHoldUncertain") end
		end
		if arrived and not geometry and not signal then increment("elevatorUncertainArrivals") end
		if arrived and not near then increment("elevatorGeometryMisses") end
		if arrived and alternative then increment("elevatorAlternateMoves") end
		if arrived and signal then increment("elevatorStateConfirmed") end
		increment(arrived and "finalSafeMoves" or "finalSafeFailures")
		debugEvent("MACHINE", arrived and "elevator_position_reached" or "elevator_move_failed", {
			path=chosen.path,mode=OPTIONS.MovementMode,detection=chosen.detection,
			nearTarget=near,platformVerified=geometry,stateSignal=signal or "none",
			candidateParts=chosen.scanned,positionOnly=chosen.platform == nil,
			alternate=alternative == true,
		}, arrived and (geometry or signal) and "INFO" or "WARN")
		return arrived
	end
    looseFuses = function()
        local items = workspace:FindFirstChild("Items")
        local matches = {}
        if items then
            -- Exact root contents only: never collect inventory/held fuses or
            -- unrelated descendants in other item models.
            for _,item in ipairs(items:GetChildren()) do
                if item.Name:lower() == "fuse" then
                    if item:IsA("Folder") then
                        -- Both common layouts are supported: separate Fuse
                        -- objects, or a Fuse folder containing pickup models.
                        local subitems={}
                        for _,child in ipairs(item:GetChildren()) do
                            if child:IsA("Model") or child:IsA("BasePart") then
                                table.insert(subitems,child)
                            end
                        end
                        if #subitems > 0 then
                            for _,subitem in ipairs(subitems) do
                                table.insert(matches,subitem)
                            end
                        elseif getPrompt(item) then
                            -- A self-contained Fuse folder containing a prompt.
                            table.insert(matches,item)
                        end
                    else
                        table.insert(matches,item)
                    end
                end
            end
        end
        return matches
    end

    local function collectBlackoutFuse(active)
        local itemsFolder=workspace:FindFirstChild("Items")
        if not itemsFolder then return false,"items_not_loaded" end
        local found = looseFuses()
        if #found == 0 then
            -- Sound may arrive before the server replicates the first fuse.
            -- Once at least one fuse has existed, proceed immediately at zero.
            if not farm.blackoutFuseSeen
                and os.clock() - farm.blackoutStartedAt < 0.85 then
                return false,"awaiting_fuse_spawn"
            end
            if farm.blackoutFuseSeen
                and os.clock() - (farm.blackoutLastFuseAt or os.clock()) < 0.18 then
                return false,"confirming_fuse_depletion"
            end
            return true,"no_fuses_remaining"
        end
        farm.blackoutLastFuseAt=os.clock()
        farm.blackoutFuseSeen = true
        increment("blackoutFuseFound",#found)
        local root = getPlayerRoot()
        if root then
            table.sort(found,function(a,b)
                local pa,pb=getAdorneePart(a),getAdorneePart(b)
                local ra=pa and pickupRisk(pa.Position,a,root.Position)
                local rb=pb and pickupRisk(pb.Position,b,root.Position)
                local av=ra and ra.score or math.huge
                local bv=rb and rb.score or math.huge
                return av < bv
            end)
        end
        local didAttempt=false
        for _,fuse in ipairs(found) do
            if not active() then return false,"cancelled" end
            local prompt = getPrompt(fuse)
            local part = prompt and getPromptPart(prompt,fuse)
            if part and prompt.Enabled and part:IsDescendantOf(workspace)
                and not UNLOAD.pickupSnakeUnsafe(fuse,part)
                and not pickupRisk(part.Position,fuse).unsafe then
                didAttempt=true
                local at=getPromptPosition(prompt,part)
                local h=math.clamp(prompt.MaxActivationDistance-1,0.25,MACHINE.Height)
                local dest=at+Vector3.new(0,h,0)
                local originalParent=fuse.Parent
                local function safe()
                    return active() and fuse.Parent == originalParent
                        and prompt.Parent and prompt.Enabled
                        and not UNLOAD.pickupSnakeUnsafe(fuse,part)
                        and not pickupRisk(part.Position,fuse).unsafe
                end
                if move(dest,safe) then
                    if safe() then
                        UNLOAD.refreshPromptContact(prompt,part,safe,"blackout_fuse")
                        local started=os.clock()
                        while safe() and os.clock()-started < 0.85 do
                            triggerPrompt(prompt)
                            if fuse.Parent ~= originalParent then break end
                            task.wait(math.min(0.075,1/FARM.SpamRate))
                        end
                        if fuse.Parent ~= originalParent then
                            increment("blackoutFuseCollected")
                            debugEvent("FUSE","loose_fuse_collected", { name=fuse.Name })
                        else
                            debugThrottled("blackout_fuse_not_confirmed_"..tostring(fuse),2,
                                "FUSE","loose_fuse_still_present",{ name=fuse.Name },"WARN")
                        end
                    end
                end
                -- Small interruptible pickup-only cooldown; machine teleports stay instant.
                local finish=os.clock()+FARM.TeleportBetweenPickups
                while active() and os.clock()<finish do task.wait(0.02) end
                break -- Re-scan after each attempt; replication can replace a fuse.
            end
        end
        if not didAttempt then
            increment("blackoutFuseUnsafe")
            debugThrottled("blackout_fuses_blocked",2,"FUSE","fuses_unsafe_or_not_ready",
                { remaining=#found },"WARN")
        end
        return false,"fuses_remaining"
    end

	local function checkFuseboxes(active, selectedPath)
		local candidates, found = {}, {}
        local didAttempt=false
		local function register(prompt, path)
			if prompt and prompt:IsA("ProximityPrompt") and not found[prompt] then
				found[prompt] = true
				table.insert(candidates, { prompt=prompt, path=path })
			end
		end
		for _, path in ipairs(MACHINE.Fuseboxes) do
            if not selectedPath or path == selectedPath then
                local prompt = resolveWorkspacePath(path)
                if not prompt then
                    debugEvent("FUSE", "known_path_missing", { path=path }, "WARN")
                end
                register(prompt, path)
            end
		end
		-- Some rounds rename breaker objects. Discover their prompts only
		-- under SpecialFolder, never press arbitrary workspace prompts.
		local special = resolveWorkspacePath("Map.SpecialFolder")
		if special then
			for _, descendant in ipairs(special:GetDescendants()) do
                local boxName = selectedPath and selectedPath:match("%.([^%.]+)%.Handle%.")
                local selectedBox = boxName and special:FindFirstChild(boxName)
                local inSelected = not selectedPath or (selectedBox
                    and descendant:IsDescendantOf(selectedBox))
				if inSelected and descendant:IsA("ProximityPrompt") and not found[descendant] then
					local ancestor = descendant.Parent
					for _ = 1, 5 do
						if not ancestor or ancestor == special then break end
						local name = ancestor.Name:lower():gsub("[%s_%-]", "")
						if name:find("fusebox", 1, true)
							or name:find("breaker", 1, true) then
							register(descendant, descendant:GetFullName())
							increment("fuseDynamicFound")
							break
						end
						ancestor = ancestor.Parent
					end
				end
			end
		end
		if #candidates == 0 then
            if selectedPath then increment("blackoutBoxMissing") end
            return false
        end
		for _, entry in ipairs(candidates) do
			if not active() then return false end
			local prompt = entry.prompt
			local part = prompt.Parent and getPromptPart(prompt, prompt.Parent)
			local root = getPlayerRoot()
			debugEvent("FUSE", "located", {
				path=entry.path,found=part ~= nil,enabled=prompt.Enabled,
				parent=prompt.Parent and prompt.Parent.Name or "missing",
				action=prompt.ActionText,object=prompt.ObjectText,
				hold=prompt.HoldDuration,maxDistance=prompt.MaxActivationDistance,
				distance=part and root and string.format("%.1f", (part.Position - root.Position).Magnitude) or "unknown",
			})
			if not prompt.Enabled then
				increment("fuseLocatedDisabled")
			elseif part and not twistedNear(part.Position) then
				if not move(part.Position + Vector3.new(0, MACHINE.Height, 0), active) then
					debugEvent("FUSE", "approach_failed", { path=entry.path }, "WARN")
					return false
				end
				task.wait(MACHINE.Settle)
				if prompt.Parent and prompt.Enabled and active() then
					UNLOAD.refreshPromptContact(prompt, part, function()
						return active() and prompt.Parent and prompt.Enabled and not twistedNear(part.Position)
					end, "fusebox_arrival")
					local deadline = os.clock() + math.max(0.7, math.min(2, prompt.HoldDuration + 0.3))
					local fires = 0
					while active() and prompt.Parent and prompt.Enabled and os.clock() < deadline do
						if twistedNear(part.Position) then break end
						if triggerPrompt(prompt) then fires += 1 end
						task.wait(MACHINE.PromptRetry)
					end
					increment("fuseAttempts")
                    if fires > 0 then didAttempt = true end
					if prompt.Enabled then increment("fuseActivationUnverified") end
					debugEvent("FUSE", "interaction_result", {
						path=entry.path,fires=fires,promptEnabled=prompt.Enabled,
						acceptedByServer="unknown",
					}, prompt.Enabled and "WARN" or "INFO")
				end
			else
				debugEvent("FUSE", "unsafe_or_missing", {
					path=entry.path,partFound=part ~= nil,
				}, "WARN")
			end
		end
        -- A disabled prompt or a sent interaction is enough to release the
        -- blackout route; neither guarantees server acceptance. Keep diagnostics.
        if selectedPath then
            return didAttempt or (#candidates > 0 and not candidates[1].prompt.Enabled)
        end
        return didAttempt
	end

    local function handleBlackout(active)
        local cleared,reason=collectBlackoutFuse(active)
        if not cleared then return false,reason end
        -- Do not select a box until zero world fuses have been observed.
        if #looseFuses() > 0 then return false,"fuse_reappeared" end
        local chosen,exitPath,selection=blackoutFuseboxPath()
        if not chosen then
            -- Unknown opening/closing door: wait for an identity cue rather
            -- than pressing both boxes and potentially undoing the exit route.
            debugThrottled("blackout_unknown_side",2,"FUSE","fusebox_side_unknown",
                { lastClosed=UNLOAD.lastClosedElevatorPath or "none" },"WARN")
            return false,"unknown_elevator_side"
        end
        farm.blackoutBoxPath=chosen
        increment("blackoutBoxDispatches")
        if selection ~= "opposite_last_closed" then increment("blackoutBoxFallbacks") end
        debugEvent("FUSE","zero_fuses_to_exit_box", {
            box=chosen,exit=exitPath,source=selection,
            lastClosed=UNLOAD.lastClosedElevatorPath or "none"
        })
        -- A post-completion opening sound is still authoritative for the
        -- actual exit; the opposite-door rule determines the blackout box.
        local sent=checkFuseboxes(active,chosen)
        if not sent then return false,"box_not_ready" end
        farm.blackoutActive=false
        farm.blackoutHandled=true
        farm.blackoutPendingUntil=0
        debugEvent("FUSE","blackout_box_interaction_dispatched", {
            box=chosen,confirmedByServer="unverified",fusesRemaining=0 })
        return true,"blackout_box_reached"
    end

	local function loop(myId)
		local function active() return alive and farm.enabled and runId == myId end
		-- Hide state is handled explicitly below; no one-frame hidden flag.
		local lastFire = 0
		local fireAfter = 0
		local placedAt = 0
		local logProgress = false
		local logFire = false
		local loggedTarget = nil
		local usedItem = false
		local toolTryAt = setmetatable({}, { __mode="k" })
		local lastPrompt = nil
		local lastProgress = nil
		local lastMachineRescan = 0
		local finished = false
		local activated, lockedOn = false, false
		local lastProgressAt = os.clock()
		local checkingSince
		local lastContactAt = -math.huge
		local clearSince = nil
		local waitStart = nil
		local startupPickupsDone = UNLOAD.pickupBefore.completed
		local lastDamageRetreatSerial = UNLOAD.damageRetreatSerial or 0
		local doneCandidateAt = nil
		local emergencyNextMove = false
		local handoffStartedAt, handoffFrom, handoffReason = nil, nil, nil
		local abilityTriggeredFor = setmetatable({}, { __mode="k" })
		local watchedTarget, targetWatchConnections = nil, {}
		local forceRescan = true
		local handledSoundSerial = farm.soundSerial
		local function scanMachine()
			local now = os.clock()
			-- This is a guarded fast path: the flush alone never completes a floor.
			-- A subsequent ElevatorDoor cue and no other incomplete objectives
			-- allow the hub to switch before the final progress value replicates.
			if mainDoorVerified() then return nil, "done" end
			local excluded = now <= (farm.soundDoneUntil or 0)
				and farm.soundDoneTarget or nil
			-- MainMachineFillingUp indicates the big machine has become relevant.
			-- Prioritize only an enabled, actually present big-machine prompt.
			if now < (farm.mainReadyUntil or 0) then
				local bigs = getBigMachines()
				local candidate, anyIncomplete = nearestIncomplete(bigs, excluded)
				if candidate then return candidate, "work" end
				-- Do not return to a stale base-machine percentage while the
				-- main machine prompt is still spawning or temporarily disabled.
				-- Once all visible main machines are complete, proceed normally.
				if #bigs == 0 or anyIncomplete then return nil, "wait" end
			end
			-- After the actual completion cue, avoid re-entering the same main
			-- machine because its progress value is a few frames behind.
			if farm.mainCompletionTarget and now < farm.mainCompletionUntil
				and not isComplete(farm.mainCompletionTarget) then
				local alternate = nearestIncomplete(getBigMachines(), farm.mainCompletionTarget)
				if alternate then return alternate, "work" end
				return nil, "wait"
			end
			return pickMachine(excluded)
		end
		local function clearTargetWatch()
			for _, conn in ipairs(targetWatchConnections) do pcall(function() conn:Disconnect() end) end
			table.clear(targetWatchConnections)
			watchedTarget = nil
		end
		farm.clearFastWatch = clearTargetWatch
		local function watchTarget(target)
			if watchedTarget == target then return end
			clearTargetWatch()
			watchedTarget = target
			if not target then return end
			getProgress(target) -- Populate the cached progress ValueBase reference.
			local value = UNLOAD.progressValues[target]
			if value then
				table.insert(targetWatchConnections, value.Changed:Connect(function()
					if not alive or not farm.enabled then return end
					if value.Value >= MACHINE.DoneValue then
						forceRescan = true
						UNLOAD.verifiedHandoffUntil = os.clock() + 1.4
						increment("completionWakeups")
					end
				end))
			end
			local prompt = getPrompt(target)
			if prompt then
				table.insert(targetWatchConnections,
					prompt:GetPropertyChangedSignal("Enabled"):Connect(function()
						forceRescan = true
					end))
			end
			table.insert(targetWatchConnections, target.AncestryChanged:Connect(function()
				forceRescan = true
			end))
			table.insert(targetWatchConnections, target.DescendantAdded:Connect(function(child)
				if child:IsA("ProximityPrompt") then
					forceRescan = true
				elseif (child.Name == "OilValue" or child.Name == "ComputerPercentage")
					and (child:IsA("NumberValue") or child:IsA("IntValue")) then
					UNLOAD.progressValues[target] = child
					forceRescan = true
					increment("objectiveLateValueBinds")
					-- Rebuild watcher once, so completion fires on the new Value.
					task.defer(function()
						if active() and watchedTarget == target then
							clearTargetWatch()
							watchTarget(target)
						end
					end)
				end
			end))
		end
		local function noteMachineCompleted(machine)
			if abilityTriggeredFor[machine] then return end
			abilityTriggeredFor[machine] = true
			UNLOAD.verifiedHandoffUntil = os.clock() + 1.5
			increment("machineCompletions")
			-- Keep total completions for diagnostics, but never count a completion
			-- toward the deathless goal while the current life is at 0 HP.
			if not deathExport.handled and (healthMonitor.old == nil or healthMonitor.old > 0) then
				GOAL.Streak += 1
				GOAL.Best = math.max(GOAL.Best, GOAL.Streak)
				if GOAL.Streak >= GOAL.Target and not GOAL.Achieved then
					GOAL.Achieved = true
					debugEvent("GOAL", "target_reached_without_death", {
						streak=GOAL.Streak,target=GOAL.Target,deaths=GOAL.Deaths,
					})
				end
			else
				debugEvent("GOAL", "completion_ignored_at_zero_health", { name=machine.Name }, "WARN")
			end
			local state = UNLOAD.floorState
			state.seen = true
			state.completed += 1
			state.lastCompletion = os.clock()
			if GOAL.Streak > 0 and GOAL.Streak % 100 == 0 then
				increment("survivalMilestones")
				debugEvent("GOAL", "deathless_streak_milestone", {
					streak=GOAL.Streak,best=GOAL.Best,target=GOAL.Target,
				})
			end
			debugEvent("MACHINE", "completed", {
				name=machine.Name,progress=tostring(getProgress(machine)),
			})
			if autoAbility.enabled then
				-- Completion inputs may yield while holding F. Never delay the next
				-- objective's movement or prompt dispatch for an ability animation.
				task.spawn(abilityAfterCompletion, machine)
			end
		end
		local function beginHandoff(reason, from)
			if handoffStartedAt then return end
			handoffStartedAt = os.clock()
			handoffFrom = from and from.Name or "none"
			handoffReason = reason
			debugStatus.handoffPending = reason .. " from " .. handoffFrom
			debugEvent("PERF", "handoff_begin", { from=handoffFrom,reason=reason })
		end
		local hide = {
			active=false,since=0,clearSince=nil,lastMove=-math.huge,
			relocate=false,reason="none",shelterReached=false,
		}
		farm.hideState = hide
		local function beginHide(reason, shouldRelocate, shouldExit)
			local now = os.clock()
			if not hide.active then
				hide.active = true
				hide.since = now
				hide.clearSince = nil
				hide.reason = reason
				hide.relocate = shouldRelocate
				hide.shelterReached = false
				increment("hideStarts")
				debugEvent("HIDE","entered", { reason=reason,
					minimum=MACHINE.HideMinSeconds,clear=MACHINE.HideClearSeconds,
					target=farm.target and farm.target.Name or "none" }, "WARN")
			elseif shouldRelocate then
				hide.relocate = true
				hide.clearSince = nil
			end
			local prompt = farm.target and getPrompt(farm.target)
			if prompt then cancelMachinePromptHold(prompt) end
			if shouldExit and chase.exitRequestedSerial ~= chase.serial then
				leaveObjective("auto_hide_" .. reason,true,0)
				chase.exitRequestedSerial=chase.serial
			end
			farm.placed = false
			lastFire = 0
			lastPrompt = nil
			lastProgress = nil
			usedItem = false
			chase.holdUntil = math.max(chase.holdUntil,hide.since + MACHINE.HideMinSeconds)
		end
		local function handleHide()
			if not hide.active then return false end
			local now = os.clock()
			local root = getPlayerRoot()
			local unsafeAtRoot = not root or twistedNear(root.Position,MACHINE.EmergencyDistance + 8)
			local target = farm.target
			if target and (isComplete(target) or not target:IsDescendantOf(workspace)) then
				if isComplete(target) then
					beginHandoff("completed_during_hide",target)
					noteMachineCompleted(target)
				end
				farm.target = nil
				target = nil
			end
			local targetPrompt = target and getPrompt(target)
			local targetPart = targetPrompt and getPromptPart(targetPrompt,target)
			local targetUnsafe = targetPart and twistedNear(targetPart.Position,MACHINE.Range)
			if targetUnsafe and now - hide.since >= 0.6 then
				local alternative = safeAlternative(target)
				if alternative then
					farm.target = alternative
					target = alternative
					targetUnsafe = false
					increment("hideSaferTargets")
					debugEvent("HIDE","safer_objective_selected",{ name=alternative.Name })
				end
			end
			if hide.relocate or unsafeAtRoot then
				hide.relocate = true
				if not root or unsafeAtRoot or not hide.shelterReached then
					if now - hide.lastMove >= 1.0 then
						hide.lastMove=now
						UNLOAD.imminentEvacuationUntil=now+1.25
						hide.shelterReached=goHideShelter(active)
						if hide.shelterReached then increment("hideRetreats") end
					end
				end
			end
			-- Do NOT move back after a fixed 0.15-second timer. Hold until both
			-- the minimum dwell and a continuous safe window have elapsed.
			if unsafeAtRoot or targetUnsafe or chase.pending then
				hide.clearSince = nil
				increment("hideDangerStays")
			else
				hide.clearSince = hide.clearSince or now
			end
			local cleared = hide.clearSince and now-hide.clearSince >= MACHINE.HideClearSeconds
			if cleared and now-hide.since >= MACHINE.HideMinSeconds
				and now >= chase.holdUntil then
				hide.active=false
				chase.eventActive=false
				chase.threatName=nil
				farm.placed=false
				farm.elevatorTarget=nil -- A shelter is NOT the end-of-floor elevator.
				farm.elevatorSource=nil
				forceRescan=true
				increment("hideResumes")
				debugEvent("HIDE","resuming_objectives",{
					waitMs=math.floor((now-hide.since)*1000+0.5),
					target=farm.target and farm.target.Name or "rescan",
				})
				return false
			end
			increment("hideWaitTicks")
			return true
		end
		farm.placed = false
		beginHandoff("start", nil)
		while active() do
			if UNLOAD.voidGuard and UNLOAD.voidGuard.blocked then
				debugThrottled("void_motion_frozen",5,"VOID","autofarm_paused_for_safety",
					{ reason="repeated_or_failed_void_recovery" },"ERROR")
				task.wait(0.3)
				continue
			end
			if workspace:FindFirstChild("Map") ~= farm.soundMapRef then
				local transitioned = farm.floorTransitionConfirmed
				farm.soundMapRef = workspace:FindFirstChild("Map")
				farm.soundDoneTarget,farm.soundDoneUntil = nil,0
				farm.mainReadyUntil,farm.elevatorDoorOpenUntil = 0,0
				resetFlushSignals()
				farm.elevatorTarget = nil
				farm.allDoneSince = nil
				farm.elevatorEmergencyLocked = false
				farm.finalizing = false
				if transitioned then
					UNLOAD.floorStatus(nil,"wait")
					increment("soundFloorTransitionResets")
					debugEvent("SOUND","new_floor_map_detected")
				end
				forceRescan = true
			end
			if farm.floorTransitionConfirmed then
				-- No objective teleports, breaker interactions or elevator retry
				-- corrections on the floor after the door-close completion event.
				if farm.target then
					local oldPrompt = getPrompt(farm.target)
					if oldPrompt then cancelMachinePromptHold(oldPrompt) end
				end
				farm.target, farm.placed = nil, false
				if freshFloorObjectivesPresent() then
					resetFlushSignals()
					farm.elevatorTarget = nil
					farm.allDoneSince = nil
					farm.elevatorEmergencyLocked = false
					farm.finalizing = false
					UNLOAD.floorState.seen = false
					UNLOAD.floorState.finished = false
					UNLOAD.floorState.completed = 0
					UNLOAD.floorState.completionReason = "new_objectives_same_map"
					UNLOAD.pickupBefore.reset("new_floor_objectives")
					startupPickupsDone,finished,waitStart = false,false,nil
					forceRescan = true
					increment("soundFloorTransitionResets")
					debugEvent("SOUND","new_floor_objectives_same_map")
				else
					task.wait(0.05)
					continue
				end
			end
			if handledSoundSerial ~= farm.soundSerial then
				handledSoundSerial = farm.soundSerial
				forceRescan = true
				increment("soundWakeups")
			end
			if farm.elevatorEmergencyLocked then
				task.wait(0.12)
				continue
			end
            -- Blackout owns its fuses. Ordinary Item Autofarm ignores Fuse;
            -- never enter any elevator fusebox while loose fuses remain.
            local now=os.clock()
            if OPTIONS.Fuseboxes and not farm.blackoutHandled and not farm.blackoutActive
                and (farm.mainCompletionAt > -math.huge or machinesDone())
                and #looseFuses() > 0 then
                farm.blackoutActive=true
                farm.blackoutStartedAt=now-0.85
                farm.blackoutFuseSeen=true
                debugEvent("FUSE","blackout_fuses_found_without_sound")
            end
            if OPTIONS.Fuseboxes and farm.blackoutActive then
                if not (skillcheckProtected and skillcheckProtected()) then
                    if farm.placed then
                        local oldPrompt=farm.target and getPrompt(farm.target)
                        if oldPrompt then cancelMachinePromptHold(oldPrompt) end
                        leaveObjective("blackout_fuse_dispatch",true,0)
                        farm.placed=false
                        lastPrompt=nil
                        lastFire=0
                    end
                    farm.fuseInFlight=true
                    local ok,complete,why=pcall(handleBlackout,function()
                        return active() and not farm.floorTransitionConfirmed
                            and OPTIONS.Fuseboxes
                    end)
                    farm.fuseInFlight=false
                    if not ok then
                        increment("workerErrors")
                        debugEvent("FUSE","blackout_worker_failed",{ error=complete },"ERROR")
                    end
                    if complete then forceRescan=true end
                else
                    if farm.lastBlackoutDeferredCueAt ~= farm.blackoutCueAt then
                        farm.lastBlackoutDeferredCueAt=farm.blackoutCueAt
                        increment("soundBlackoutDeferred")
                        debugEvent("FUSE","blackout_deferred_skillcheck")
                    end
                end
                if farm.blackoutActive then
                    task.wait(0.04)
                    continue
                end
            end
			local root = getPlayerRoot()
			local moved = false
			local dangerAtRoot,dangerName,dangerDistance = false,nil,nil
			if root and farm.placed and farm.target and OPTIONS.AutoHide then
				dangerAtRoot,dangerName,dangerDistance = twistedNear(root.Position)
				if dangerAtRoot and dangerDistance
					and dangerDistance <= MACHINE.EmergencyDistance then
					if not chase.pending then chase.serial = (chase.serial or 0) + 1 end
					chase.pending = true
					UNLOAD.imminentEvacuationUntil = os.clock() + 0.8
					increment("chaseThreatRetreats")
					increment("threatProximityAlerts")
					debugThrottled("urgent_close_enemy",1,"DANGER","urgent_close_enemy",
						{ enemy=dangerName,distance=string.format("%.1f",dangerDistance) },"WARN")
				end
			end
			if (UNLOAD.damageRetreatSerial or 0) > lastDamageRetreatSerial then
				lastDamageRetreatSerial = UNLOAD.damageRetreatSerial
				if farm.placed then
					if not chase.pending then chase.serial = (chase.serial or 0) + 1 end
					chase.pending = true
					UNLOAD.imminentEvacuationUntil = os.clock() + 0.8
					increment("damageRetreatTriggers")
					debugEvent("DANGER","damage_forces_machine_retreat", {
						target=farm.target and farm.target.Name or "none" },"WARN")
				end
			end
			local protected, checkType = skillcheckProtected()
			-- Once completion has been observed, the disappearing skillcheck UI
			-- must not hold the next objective hostage.
			local completedTarget = farm.target and
				(isComplete(farm.target) or
				(farm.soundDoneTarget == farm.target
				and os.clock() <= (farm.soundDoneUntil or 0)))
			if completedTarget then
				UNLOAD.verifiedHandoffUntil = os.clock() + 1.4
			end
			if protected and not hide.active and not completedTarget and not chase.pending
				and not (dangerAtRoot and dangerDistance
					and dangerDistance <= MACHINE.EmergencyDistance)
				and os.clock() > (UNLOAD.imminentEvacuationUntil or 0) then
				if activeMotion and activeMotion.owner == "pickup" then cancelMotion("pickup") end
				debugThrottled("machine_skillcheck_hold", 2, "SKILLCHECK", "holding_objective", {
					ui=checkType,target=farm.target and farm.target.Name or "none",
					chasePending=chase.pending,
				}, "INFO")
				task.wait(MACHINE.Tick)
				continue
			end
			if chase.pending then
				chase.pending = false
				debugEvent("DANGER","chase_shelter_requested", {
					target=farm.target and farm.target.Name or "none",
				},"WARN")
				-- The Chase listener may already have queued the remote exit. Do
				-- not queue it twice, but never wait on InvokeServer before escape.
				beginHide("chase",true,true)
			end
			if hide.active and handleHide() then
				task.wait(0.06)
				continue
			end
			if finished and not farm.elevatorEmergencyLocked then
				local newObjective, newStatus = scanMachine()
				if newObjective and newStatus == "work" then
					UNLOAD.pickupBefore.reset("new_objectives")
					startupPickupsDone = false
					finished = false
					waitStart = nil
					farm.finalizing = false
					debugEvent("MACHINE", "new_round_detected", { target=newObjective.Name })
				end
			end
			local anyPickup = capsuleFarm.enabled or itemFarm.enabled or candyFarm.enabled
			local pending = false
			if not UNLOAD.pickupBefore.completed and not startupPickupsDone and anyPickup then
				local availableObjective, objectiveStatus = scanMachine()
				if availableObjective or objectiveStatus == "wait" then
					local now = os.clock()
					UNLOAD.pickupBefore.started = UNLOAD.pickupBefore.started or now
					if not waitStart then
						waitStart = UNLOAD.pickupBefore.started
						increment("pickupBeforeWaits")
						debugEvent("PICKUP", "before_machines_started", { limitSeconds=MACHINE.ItemWaitMax })
					end
					local elapsed = now - waitStart
					local snapshot = scanFinalPickups()
					local collectorWorking = pickupBusy() or pickupCoordinator.owner ~= nil
					local safePending = snapshot.safe > 0 or collectorWorking
					local spawnGrace = elapsed < 0.7
					local expired = elapsed >= MACHINE.ItemWaitMax
					local stalled = elapsed > pickupCircuit.MaxStallSeconds
						and debugStats.pickupAttempts > 0
						and now - math.max(waitStart, pickupCircuit.lastConfirmed) >= pickupCircuit.MaxStallSeconds
					if (safePending or spawnGrace) and not expired and not stalled and not pickupCircuit.paused then
						pending = true
					else
						UNLOAD.pickupBefore.completed = true
						startupPickupsDone = true
						pickupCoordinator.home = nil
						if activeMotion and activeMotion.owner == "pickup" then cancelMotion("pickup") end
						pickupCoordinator.owner = nil
						increment(expired and "pickupBeforeTimeouts" or "pickupBeforeCompleted")
						debugEvent("PICKUP", "before_machines_complete", {
							reason=pickupCircuit.paused and "flood_blocked" or expired and "time_budget"
								or stalled and "no_progress" or "collected_or_unavailable",
								seconds=math.floor(elapsed * 10 + 0.5) / 10,
							safeRemaining=snapshot.safe,unsafeRemaining=snapshot.unsafe,
						}, expired or stalled and "WARN" or "INFO")
					end
				end
			end
			if not anyPickup and not UNLOAD.pickupBefore.completed then
				UNLOAD.pickupBefore.completed = true
				startupPickupsDone = true
			end
			if pending and not farm.placed then
				local currentPrompt = farm.target and getPrompt(farm.target)
				if currentPrompt then cancelMachinePromptHold(currentPrompt) end
				farm.placed = false
				lastFire = 0
				lastPrompt = nil
				usedItem = false
			elseif root then
				local target = farm.target
				local status = "work"
				local now = os.clock()
				if forceRescan or now - lastMachineRescan >= MACHINE.RescanInterval then
					forceRescan = false
					lastMachineRescan = now
					local scannedTarget, scannedStatus = scanMachine()
					local currentPrompt = target and getPrompt(target)
					if target and not isComplete(target) then abilityTriggeredFor[target] = nil end
					local targetProgress = target and getProgress(target)
					local nearFinish = targetProgress and targetProgress >= MACHINE.NearFinishAt
						and targetProgress < MACHINE.DoneValue
					local finishLocked = nearFinish and farm.placed
						and now - lastProgressAt <= MACHINE.NearFinishHold
					local soundedDone = target and target == farm.soundDoneTarget
						and now <= (farm.soundDoneUntil or 0)
					local mainCueSwitch = target and not isBigMachine(target)
						and now <= (farm.mainReadyUntil or 0)
						and scannedTarget and isBigMachine(scannedTarget)
					local currentUsable = target
						and not (scannedTarget ~= target and (soundedDone or mainCueSwitch))
						and isLiveMachineObjective(target)
						and not isComplete(target)
						and currentPrompt ~= nil
						and (currentPrompt.Enabled
							or (farm.placed and now - lastProgressAt <= MACHINE.UseTimeout)
							or finishLocked)
					if finishLocked and scannedTarget ~= target then
						increment("machineNearFinishHeld")
						debugThrottled("near_finish_" .. tostring(target), 4, "MACHINE", "near_finish_held",
							{ name=target.Name,progress=targetProgress,candidate=scannedTarget and scannedTarget.Name or "none" })
					end
					if not currentUsable then
						if target and scannedTarget ~= target then
							if soundedDone then
								increment("soundHandoffs")
								debugEvent("SOUND", "fast_handoff_on_done", {
									from=target.Name,to=scannedTarget and scannedTarget.Name or "waiting_for_replication",
									evidence="local_player_done_cue",
								})
							end
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
						debugEvent("MACHINE", "target_removed", { name=target.Name }, "WARN")
					end
					target, farm.placed = nil, false
					lastFire = 0
					lastPrompt = nil
					lastProgress = nil
					usedItem = false
				end
				if not target then target, status = scanMachine() end
				farm.target = target
				watchTarget(target)
				if target ~= loggedTarget then
					lastContactAt = -math.huge
					loggedTarget = target
					debugStatus.currentTarget = target and target.Name or "None"
					increment("machineTargetChanges")
					debugEvent("MACHINE", "target_changed", { name=target and target.Name or "none",status=status })
				end
				local prompt = target and getPrompt(target)
				local part = prompt and getPromptPart(prompt, target)
				if part then
					UNLOAD.floorStatus(target, "work")
					doneCandidateAt = nil
					if finished and pickupCircuit.finalized and not UNLOAD.pickupBefore.completed then
						pickupCircuit.reset("new_objective")
					end
					farm.finalizing = false
					finished = false
					local danger, dangerName, dangerDist = twistedNear(part.Position)
					local progressNow = getProgress(target)
					-- A danger at the NEXT objective is not evidence that the player
					-- is being chased. Never spam leave/retreat while already safe.
					if danger then
						farm.placed = false
						cancelMachinePromptHold(prompt)
						local nearPlayer = twistedNear(root.Position,MACHINE.EmergencyDistance)
						local alternative = safeAlternative(target)
						increment("machineDangers")
						debugThrottled("danger_target_" .. tostring(target),1.5,
							"DANGER","unsafe_objective",{
							name=target.Name,enemy=tostring(dangerName),
							distance=string.format("%.1f",dangerDist or 0),
							nearPlayer=nearPlayer == true,
							alternative=alternative and alternative.Name or "none",
							},"WARN")
						if alternative and not nearPlayer then
							beginHandoff("danger_reroute",target)
							farm.target = alternative
							forceRescan=true
						else
							-- If the character is safe, hold position; if being chased,
							-- move to a supported shelter. Neither case teleports back
							-- until the clear window has been continuously satisfied.
							beginHide("unsafe_objective",nearPlayer == true,nearPlayer == true)
						end
					elseif hide.active then
						farm.placed = false
						cancelMachinePromptHold(prompt)
					elseif os.clock() < chase.holdUntil then
						farm.placed = false
						cancelMachinePromptHold(prompt)
					else
						if farm.placed and prompt.Enabled and (root.Position - part.Position).Magnitude > prompt.MaxActivationDistance then
							farm.placed = false
						end
						if not farm.placed then
							local teleportAt = os.clock()
							local arrived = move(part.Position + Vector3.new(0, MACHINE.Height, 0), function()
								return active() and not chase.pending and target:IsDescendantOf(workspace)
									and prompt:IsDescendantOf(workspace) and not isComplete(target)
									and not twistedNear(part.Position)
							end, emergencyNextMove and "hide" or "handoff")
							if arrived then emergencyNextMove = false end
							if not arrived then
								task.wait(MACHINE.Tick)
								continue
							end
							-- First prompt goes out immediately after movement. The old
							-- contact walk could cost hundreds of ms on EVERY handoff.
							local initialFireAt = os.clock()
							local initialFired = triggerMachinePrompt(prompt)
							farm.lastPromptTarget,farm.lastPromptAt = target,os.clock()
							increment("fastPromptDispatches")
							if not initialFired and active() and not isComplete(target) then
								local contacted = UNLOAD.refreshPromptContact(prompt, part, function()
									return active() and farm.target == target and not chase.pending
										and target:IsDescendantOf(workspace) and not isComplete(target)
								end, "machine_arrival_retry")
								if not contacted and prompt.Enabled then
									contacted = UNLOAD.seatPrompt(prompt, part, function()
										return active() and farm.target == target and not chase.pending
											and target:IsDescendantOf(workspace) and not isComplete(target)
									end, "machine_arrival_retry")
									if contacted then increment("machinePromptFallbacks") end
								end
								local fresh = getPrompt(target)
								local freshPart = fresh and getPromptPart(fresh, target)
								if fresh and fresh.Enabled and freshPart
									and (root.Position - getPromptPosition(fresh, freshPart)).Magnitude <= fresh.MaxActivationDistance then
									prompt, part = fresh, freshPart
									increment("machineInitialPromptRetries")
									initialFired = triggerMachinePrompt(prompt)
									farm.lastPromptTarget,farm.lastPromptAt = target,os.clock()
								end
							end
							debugEvent("PERF", "prompt_after_teleport", {
								machine=target.Name,dispatched=initialFired,
								arrivalToPromptMs=math.floor((initialFireAt - teleportAt) * 1000 + 0.5),
							})
							if handoffStartedAt then
								increment("fastHandoffs")
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
									from=handoffFrom,to=target.Name,ms=ms,
									reason=handoffReason,dispatched=initialFired,
								})
								handoffStartedAt, handoffFrom, handoffReason = nil, nil, nil
							end
							lastFire = initialFireAt
							fireAfter = 0
							farm.placed = true
							startupPickupsDone = true
							UNLOAD.pickupBefore.completed = true
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
								debugEvent("MACHINE", "progress_stalled", { name=target.Name,
									progress=tostring(getProgress(target)),seconds=MACHINE.StallTimeout }, "WARN")
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
						if prompt.Enabled and not activated and farm.placed and not checking
							and os.clock() - placedAt >= 0.8
							and os.clock() - lastProgressAt >= 0.8
							and os.clock() - lastContactAt >= 1.2
							and (root.Position - part.Position).Magnitude <= prompt.MaxActivationDistance + 3 then
							lastContactAt = os.clock()
							local currentProgress = getProgress(target)
							local corrected = UNLOAD.refreshPromptContact(prompt, part, function()
								return active() and farm.target == target and prompt.Enabled
									and not chase.pending and not isComplete(target)
							end, "machine_retry")
							if not corrected and active() and prompt.Enabled and not isComplete(target) then
								corrected = UNLOAD.seatPrompt(prompt, part, function()
									return active() and farm.target == target and prompt.Enabled
										and not chase.pending and not isComplete(target)
								end, "machine_retry")
								if corrected then increment("machinePromptFallbacks") end
							end
							-- A stall may mean the prompt was fired without entering its activation region.
							-- Circle the prompt briefly while firing; stop on actual progress or a skillcheck.
							if active() and prompt.Enabled and not isComplete(target) and not chase.pending then
								local orbitOK, orbitReason = UNLOAD.orbitPromptContact(target, prompt, part,
									function() return active() and farm.target == target and not chase.pending
										and not twistedNear(part.Position) and not isComplete(target) end,
									function()
										local current = getProgress(target)
										return isComplete(target) or not prompt.Enabled
											or (current ~= nil and currentProgress ~= nil and current > currentProgress)
									end,
									function() return triggerMachinePrompt(prompt) end,
									"machine_retry", 0.85)
								if orbitOK then
									increment("machineOrbitRecoveries")
									lastProgressAt = os.clock()
									activated = true
									corrected = true
								elseif orbitReason == "enemy_nearby" or orbitReason == "interrupted" then
									corrected = false
								end
							end
							if corrected and active() and prompt.Enabled and not isComplete(target) then
								lastFire = os.clock()
								local dispatched = triggerMachinePrompt(prompt)
								debugEvent("MACHINE", "contact_retry", { name=target.Name,
									progress=tostring(currentProgress),mode=OPTIONS.MovementMode,dispatched=dispatched })
							else
								debugThrottled("machine_contact_failed_" .. tostring(target), 4,
									"MACHINE", "contact_reposition_deferred", { name=target.Name }, "WARN")
							end
						end
						if not activated and not paused and not isComplete(target) and prompt.Enabled
							and os.clock() >= fireAfter and os.clock() - lastFire >= MACHINE.PromptRetry then
							lastFire = os.clock()
							if logFire then
								logFire = false
								debugLog(string.format("first fire %s %.2fs after place", target.Name, os.clock() - placedAt))
							end
							triggerMachinePrompt(prompt)
							farm.lastPromptTarget,farm.lastPromptAt = target,os.clock()
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
				elseif UNLOAD.floorStatus(target, status) then
					local now = os.clock()
					doneCandidateAt = doneCandidateAt or now
					if not finished and now - doneCandidateAt >= 0.11 then
						local verifyTarget, verifyStatus = scanMachine()
						if not verifyTarget and UNLOAD.floorStatus(verifyTarget, verifyStatus) then
							finished = true
							UNLOAD.pickupBefore.completed = true
							pickupCircuit.finalized = true
							pickupCoordinator.home = nil
							pickupCoordinator.owner = nil
							if activeMotion and activeMotion.owner == "pickup" then cancelMotion("pickup") end
							if handoffStartedAt then
								debugEvent("PERF", "handoff_no_next_objective", {
									from=handoffFrom,reason=handoffReason,
									ms=math.floor((now - handoffStartedAt) * 1000 + 0.5),
								})
								handoffStartedAt, handoffFrom, handoffReason = nil, nil, nil
								debugStatus.handoffPending = "None"
							end
							debugEvent("MACHINE", "all_complete", { autoElevator=OPTIONS.AutoElevator,
								fuseboxes=OPTIONS.Fuseboxes,pickupTiming="before" })
							-- Breakers must be handled before committing to the exit.
							-- Otherwise touching a breaker may pull the player out of
							-- the elevator after a valid transfer has begun.
							farm.finalizing = OPTIONS.AutoElevator or OPTIONS.Fuseboxes
                            if OPTIONS.Fuseboxes and active() and not farm.elevatorEmergencyLocked
                                and not farm.blackoutHandled and not farm.blackoutActive then
                                if #looseFuses() > 0 then
                                    farm.blackoutActive=true
                                    farm.blackoutStartedAt=os.clock()-0.85
                                    farm.blackoutFuseSeen=true
                                    debugEvent("FUSE","finalization_waits_for_loose_fuses")
                                elseif os.clock() - (farm.blackoutCueAt or -math.huge) < 12 then
                                    farm.blackoutActive=true
                                    farm.blackoutStartedAt=farm.blackoutCueAt
                                -- No Fuses event and no loose Fuse items means
                                -- no confirmed blackout. Head to the real exit.
                                end
                            end
							if OPTIONS.AutoElevator and active() and not farm.elevatorEmergencyLocked
                                and not farm.blackoutActive then
								finishAtElevator(active)
							end
							if not farm.elevatorEmergencyLocked then farm.finalizing = false end
						else
							doneCandidateAt = nil
							debugThrottled("machine_done_recheck", 2, "MACHINE", "done_recheck_failed", {
								status=verifyStatus,target=verifyTarget and verifyTarget.Name or "none",
							}, "WARN")
						end
					end
					task.wait(0.04)
				elseif not part and (status == "wait" or status == "none") then
					debugThrottled("machine_wait_" .. status, 5, "MACHINE", "waiting_for_objective", {
						status=status,pending=debugStatus.handoffPending,
					}, "WARN")
					task.wait(0.08)
				end
			end
			task.wait(moved and 0 or MACHINE.Tick)
		end
		clearTargetWatch()
	end
	function farm.enable()
		if farm.enabled then return end
		farm.enabled = true
		farm.soundMapRef = workspace:FindFirstChild("Map")
		farm.soundDoneTarget,farm.soundDoneUntil = nil,0
		farm.mainReadyUntil,farm.elevatorDoorOpenUntil = 0,0
		resetFlushSignals()
		farm.lastSoundFingerprint,farm.lastSoundAt = nil,nil
		farm.allDoneSince = nil
		farm.elevatorWatchFired = false
		farm.elevatorEmergencyLocked = false
		farm.elevatorTarget = nil
		farm.elevatorPlatform = nil
		farm.elevatorSource = nil
		farm.elevatorAlternateCommitted = false
		farm.elevatorAlternateTried = false
		farm.elevatorServerRelocated = false
		farm.elevatorServerRelocatedAt = nil
		farm.lastElevatorMoveAt = nil
		farm.elevatorProfiled = false
		farm.elevatorEntryTouched = false
		UNLOAD.imminentEvacuationUntil = 0
		chase.pending = false
		chase.eventActive = false
		chase.threatName = nil
		chase.serial = (chase.serial or 0) + 1
		chase.exitRequestedSerial = nil
		chase.holdExitAt = nil
		runId += 1
		local myId = runId
		supervise("machine autofarm", function()
			return alive and farm.enabled and runId == myId
		end, function()
			loop(myId)
		end)
		supervise("elevator watchdog", function()
			return alive and farm.enabled and runId == myId
		end, function()
			local function active() return alive and farm.enabled and runId == myId end
			while active() do
				if farm.floorTransitionConfirmed then
					task.wait(0.05)
					continue
				end
				-- Let the blackout/fuse worker finish before any elevator correction
				-- or final teleport. Sounds are prompts to check state, not proof
				-- that server-side elevator entry has been registered.
				if OPTIONS.Fuseboxes and
                    (farm.blackoutActive or farm.fuseInFlight
                        or os.clock() < (farm.blackoutPendingUntil or 0)) then
					task.wait(0.025)
					continue
				end
				if OPTIONS.AutoElevator then
					local signalCompleted = mainDoorVerified()
					local completed = signalCompleted or machinesDone()
					if signalCompleted and not UNLOAD.floorState.finished then
						UNLOAD.floorState.finished = true
						UNLOAD.floorState.completionReason = "main_completed_plus_elevator_door"
						debugEvent("SOUND", "main_completed_door_floor_transition", {
							autoElevator=OPTIONS.AutoElevator,
							arrivalVerified=false,
						})
					end
					if completed then
						if not farm.allDoneSince then
							farm.allDoneSince = os.clock()
							farm.elevatorWatchFired = false
							farm.elevatorHoldCorrections = 0
							farm.lastElevatorInside = nil
							farm.elevatorAlternateTried = false
							farm.elevatorAlternateCommitted = false
							farm.elevatorServerRelocated = false
							farm.elevatorServerRelocatedAt = nil
							farm.elevatorProfiled = false
							farm.elevatorEntryTouched = false
							farm.elevatorEntryAttempts = 0
							farm.elevatorContactRetryAt = 0
							farm.elevatorRecoveryAt = nil
							farm.elevatorRecoveryCount = 0
							increment("elevatorWatchStarts")
							debugEvent("MACHINE", "elevator_watch_started", { deadlineSeconds=15 })
						end
						local now = os.clock()
						if not farm.elevatorCountdownAccepted
							and now <= (farm.elevatorCountdownPendingUntil or 0) then
							local near, geometry, serverSignal = verifyElevatorPosition()
							local root = getPlayerRoot()
							local nearExit = root and farm.elevatorTarget
								and (root.Position - farm.elevatorTarget).Magnitude <= 13
							local recentArrival = farm.lastElevatorMoveAt
								and now - farm.lastElevatorMoveAt <= 25
							-- Require completed objectives, an actual elevator destination,
							-- and a recent approach; geometry is only supporting evidence.
							if farm.elevatorTarget and recentArrival
								and (nearExit or serverSignal) then
								farm.elevatorCountdownAccepted = true
								farm.elevatorCountdownPendingUntil = 0
								farm.elevatorCountdownHoldUntil = now + 14.0
								increment("soundElevatorCountdownAccepted")
								debugEvent("SOUND", "elevator_countdown_arrival_correlated", {
									nearTarget=near,nearExit=nearExit == true,
									platformVerified=geometry,
									serverSignal=serverSignal or "none",
									holdSeconds=14,entryServerConfirmed=serverSignal ~= nil,
								})
							end
						end
						if farm.elevatorCountdownPendingUntil > 0
							and now > farm.elevatorCountdownPendingUntil then
							farm.elevatorCountdownPendingUntil = 0
							increment("soundElevatorCountdownUnverified")
							debugEvent("SOUND", "elevator_countdown_stop_unverified", {
								reason="not_close_to_recent_elevator_destination",
							})
						end
						if farm.elevatorSoundPath and farm.elevatorSource
							and farm.elevatorSource ~= farm.elevatorSoundPath and not farm.elevatorTransit then
							farm.elevatorTarget = nil
						end
						if not farm.elevatorTarget and not farm.finalizing
							and os.clock() >= (farm.elevatorCountdownHoldUntil or 0)
							and not farm.elevatorTransit and not farm.elevatorEmergencyLocked
							and os.clock()-farm.allDoneSince >= 0.20
							and not (skillcheckProtected and skillcheckProtected()) then
							increment("elevatorFastDispatch")
							debugEvent("MACHINE","elevator_fast_dispatch", {
								reason=UNLOAD.floorState.completionReason },"WARN")
							finishAtElevator(active)
						end
						if farm.elevatorTarget and farm.elevatorPlatform and not farm.elevatorTransit then
							local near, inside = verifyElevatorPosition()
							if near and inside then
								farm.lastElevatorInside = farm.lastElevatorInside or os.clock()
								if os.clock() - farm.lastElevatorInside >= 5 then farm.elevatorHoldCorrections = 0 end
							else
								farm.lastElevatorInside = nil
							end
						end
						-- When the game moves the character a whole room away shortly
						-- after arrival, suspect a server-controlled floor transition.
						-- Do not yank the player straight back to the completed floor.
						if farm.elevatorTarget and farm.lastElevatorMoveAt
							and not farm.elevatorServerRelocated then
							local root = getPlayerRoot()
							local age = os.clock() - farm.lastElevatorMoveAt
							local dist = root and (root.Position - farm.elevatorTarget).Magnitude or 0
							if age >= 0.35 and age <= 8 and dist > 80 then
								farm.elevatorServerRelocated = true
								farm.elevatorServerRelocatedAt = os.clock()
								increment("elevatorServerRelocations")
								debugEvent("MACHINE", "elevator_server_relocation_suspected", {
									distance=string.format("%.1f", dist),age=string.format("%.1f",age),
								},"WARN")
							end
						end
						local holdForTransition = (farm.elevatorServerRelocated and
							(os.clock() - (farm.elevatorServerRelocatedAt or 0) < 48))
							or os.clock() < (farm.elevatorCountdownHoldUntil or 0)
						-- An audible door opening is a short arrival grace window, not proof
						-- the server accepted elevator entry. Avoid frantic repositioning.
						local doorOpening = os.clock() < (farm.elevatorDoorOpenUntil or 0)
						if farm.elevatorTarget and farm.elevatorEntryAttempts < 3
							and not farm.finalizing and not farm.elevatorTransit
							and not farm.elevatorEmergencyLocked and not holdForTransition
							and os.clock() >= (farm.elevatorContactRetryAt or 0)
							and (doorOpening or os.clock() - farm.allDoneSince >= 1.2) then
							touchElevatorEntrance(active)
						end
						if farm.elevatorTarget and not farm.finalizing and not farm.elevatorTransit
							and not farm.elevatorEmergencyLocked and not holdForTransition
							and farm.elevatorHoldCorrections < 3 and not doorOpening
							and os.clock() - farm.allDoneSince >= 0.65
							and os.clock() - farm.lastElevatorHoldAt >= 1.0
							and not (skillcheckProtected and skillcheckProtected()) then
							local near, within, signal = verifyElevatorPosition()
							if not near or (farm.elevatorPlatform and not within and not signal) then
								farm.elevatorHoldCorrections += 1
								farm.lastElevatorHoldAt = os.clock()
								increment("elevatorHoldCorrections")
								debugEvent("MACHINE", "elevator_position_correction", {
									near=near,platformVerified=within,stateSignal=signal or "none",
									attempt=farm.elevatorHoldCorrections,
								}, "WARN")
								finishAtElevator(active)
							end
						end
						-- If the primary still has no server entry signal after physical
						-- contact attempts, try one distinct backup. Real floor support
						-- gets a longer window so that we do not abandon it prematurely.
						if farm.elevatorTarget and not farm.elevatorTransit
							and not farm.finalizing and not farm.elevatorEmergencyLocked
							and not holdForTransition and not doorOpening
							and not farm.elevatorAlternateCommitted
							and not farm.elevatorAlternateTried
							and os.clock() - farm.allDoneSince >= (farm.elevatorPlatform and 11.0 or 3.5)
							and (not farm.elevatorPlatform or farm.elevatorEntryAttempts >= 2)
							and not (skillcheckProtected and skillcheckProtected()) then
							farm.elevatorAlternateTried = true
							local near, within, signal = verifyElevatorPosition()
							-- An ordinary collidable floor is not proof that the game
							-- accepted elevator entry. Only a replicated entry signal or
							-- a new-round/server-relocation observation can justify staying.
							if not signal then
								increment("elevatorLastResortRetries")
								debugEvent("MACHINE", "elevator_primary_unverified_recover", {
									near=near,platform=within,reason="no_server_entry_signal",
								}, "WARN")
								finishAtElevator(active, true)
							end
						end
						-- The old 15-second fallback permanently locked the character at an
						-- unverified location. Revisit the supported primary exit after a
						-- bounded cooling period, unless a server transition is in progress.
						if farm.elevatorRecoveryAt and os.clock() >= farm.elevatorRecoveryAt
							and not holdForTransition and not doorOpening
							and not farm.elevatorTransit
							and not farm.finalizing and not farm.elevatorEmergencyLocked
							and not (skillcheckProtected and skillcheckProtected()) then
							farm.elevatorRecoveryAt = nil
							farm.elevatorAlternateCommitted = false
							farm.elevatorAlternateTried = true
							farm.elevatorEntryAttempts = 0
							farm.elevatorEntryTouched = false
							farm.elevatorContactRetryAt = 0
							farm.elevatorHoldCorrections = 0
							farm.elevatorServerRelocated = false
							farm.elevatorServerRelocatedAt = nil
							farm.elevatorWatchFired = false
							farm.allDoneSince = os.clock()
							increment("elevatorRecoveryDispatched")
							debugEvent("MACHINE", "elevator_recovery_to_exit", {
								attempt=farm.elevatorRecoveryCount,
								from=farm.elevatorSource or "none",
							}, "WARN")
							finishAtElevator(active)
						end
						if not farm.elevatorWatchFired and os.clock() - farm.allDoneSince >= 15
							and not holdForTransition and not doorOpening
							and not farm.elevatorTransit
							and not (skillcheckProtected and skillcheckProtected()) then
							farm.elevatorWatchFired = true
							farm.elevatorEmergencyLocked = true
							farm.finalizing = true
							pickupCircuit.finalized = true
							pickupCoordinator.home = nil
							pickupCoordinator.owner = nil
							if activeMotion and activeMotion.owner == "pickup" then cancelMotion("pickup") end
							chase.pending = false
							chase.holdUntil = 0
							motionPauseUntil = 0
							increment("elevatorFallbacks")
							debugEvent("MACHINE", "elevator_fallback_triggered", {
								seconds=math.floor(os.clock() - farm.allDoneSince),mode=OPTIONS.MovementMode,
							})
							local reached, geometry, state = false, false, nil
							for attempt = 1, 2 do
								if not active() then break end
								-- Later recovery rounds should finish on the primary exit,
								-- not permanently strand the player at the unverified backup.
								local moved = finishAtElevator(active,
									attempt == 1 and farm.elevatorRecoveryCount == 0
									and not farm.elevatorAlternateCommitted)
								if moved then
									task.wait(0.05)
									reached, geometry, state = verifyElevatorPosition()
									if reached and (geometry or state) then break end
								end
								if attempt < 2 then task.wait(0.08) end
							end
							-- Geometry is useful for supporting the character, but not proof
							-- that the elevator/level transition was accepted.
							local verified = reached and state ~= nil
							increment(verified and "elevatorFallbackSuccess" or "elevatorFallbackFailures")
							increment(verified and "elevatorFallbackVerified" or "elevatorFallbackUnverified")
							local root = getPlayerRoot()
							if not verified then
								debugEvent("MACHINE", "elevator_exit_not_confirmed", {
									primaryPresent=resolveWorkspacePath(MACHINE.Elevator) ~= nil,
									backupRejected=debugStats.elevatorBackupRejected,
								}, "WARN")
							end
							debugEvent("MACHINE", verified and "elevator_fallback_geometry" or "elevator_fallback_unverified", {
								mode=OPTIONS.MovementMode,nearTarget=reached,platformVerified=geometry,
								stateSignal=state or "none",elevator=farm.elevatorSource or "none",
								position=root and tostring(root.Position) or "missing",
								target=farm.elevatorTarget and tostring(farm.elevatorTarget) or "missing",
							}, verified and "INFO" or "WARN")
							if not verified and farm.elevatorRecoveryCount < 3 then
								farm.elevatorRecoveryCount += 1
								farm.elevatorRecoveryAt = os.clock() + 11 + farm.elevatorRecoveryCount * 3
								farm.elevatorEmergencyLocked = false
								farm.finalizing = false
								increment("elevatorRecoveryScheduled")
								debugEvent("MACHINE", "elevator_recovery_scheduled", {
									attempt=farm.elevatorRecoveryCount,delay=11+farm.elevatorRecoveryCount*3,
									last=farm.elevatorSource or "none",
								}, "WARN")
							elseif not verified then
								-- Stop force-teleporting after bounded retries. Keep the best
								-- supported exit as the last holding point, and record uncertainty.
								increment("elevatorRecoveryExhausted")
								debugEvent("MACHINE", "elevator_recovery_exhausted", {
									location=farm.elevatorSource or "none",
								}, "WARN")
							end
						end
					else
						local nextObjective,nextStatus = pickMachine()
						local newWork = nextObjective ~= nil and nextStatus == "work"
						if farm.allDoneSince and newWork then
							farm.allDoneSince = nil
							farm.elevatorWatchFired = false
							farm.elevatorTarget = nil
							farm.elevatorPlatform = nil
							farm.elevatorSource = nil
							farm.elevatorAlternateCommitted = false
							farm.elevatorAlternateTried = false
							farm.elevatorServerRelocated = false
							farm.elevatorServerRelocatedAt = nil
							farm.elevatorProfiled = false
							farm.elevatorEntryTouched = false
							farm.elevatorEntryAttempts = 0
							farm.elevatorContactRetryAt = 0
							farm.elevatorRecoveryAt = nil
							farm.elevatorRecoveryCount = 0
							resetCountdownSignal()
							if farm.elevatorEmergencyLocked then
								farm.elevatorEmergencyLocked = false
								farm.finalizing = false
								pickupCircuit.reset("new_objective")
							end
						end
					end
				else
					farm.allDoneSince = nil
					resetCountdownSignal()
					farm.elevatorWatchFired = false
					if farm.elevatorEmergencyLocked then
						farm.elevatorEmergencyLocked = false
						farm.finalizing = false
						pickupCircuit.reset("auto_elevator_disabled")
					end
				end
				task.wait(0.06)
			end
		end)
	end
	function farm.disable()
		local wasEnabled = farm.enabled
		farm.enabled = false
		if farm.hideState then farm.hideState.active = false end
		farm.soundDoneTarget,farm.soundDoneUntil = nil,0
		farm.mainReadyUntil,farm.elevatorDoorOpenUntil = 0,0
		resetFlushSignals()
		farm.allDoneSince = nil
		farm.elevatorWatchFired = false
		farm.elevatorEmergencyLocked = false
		farm.elevatorTarget = nil
		farm.elevatorPlatform = nil
		farm.elevatorSource = nil
		farm.elevatorAlternateCommitted = false
		farm.elevatorAlternateTried = false
		farm.elevatorServerRelocated = false
		runId += 1
		farm.target, farm.placed, farm.moving, farm.finalizing = nil, false, false, false
		if farm.clearFastWatch then farm.clearFastWatch() end
		cancelMotion("machine")
		restoreMachinePrompts()
		if wasEnabled and alive then
			local protected, checkType = skillcheckProtected()
			if protected then
				debugEvent("MACHINE", "disable_exit_deferred_skillcheck", { ui=checkType }, "INFO")
			else
				leaveObjective("machine_autofarm_disabled", true, 0)
				-- Disabling automation must not teleport the character to a random
				-- elevator, especially when an incomplete objective remains.
			end
		end
	end
	table.insert(cleanups, farm.disable)
	return farm
end

local function createInputRow(parent, name, order, apply)
	local row = new("Frame", { Size=UDim2.new(1,-9,0,43),BackgroundColor3=UI.surface,
		BorderSizePixel=0,LayoutOrder=order }, parent)
	corner(row, 9)
	uiStroke(row)
	uiText(row, name, 14, false, UI.text, {
		Position=UDim2.fromOffset(12,0),Size=UDim2.new(1,-98,1,0),
	})
	local box = new("TextBox", {
		Size=UDim2.fromOffset(69,28),Position=UDim2.new(1,-80,0.5,-14),
		BackgroundColor3=UI.soft,BorderSizePixel=0,Text=tostring(apply(nil)),
		TextColor3=UI.text,TextSize=13,Font=Enum.Font.GothamBold,
		ClearTextOnFocus=false,
	}, row)
	corner(box, 7)
	track(box.FocusLost:Connect(function()
		local input = tonumber(box.Text)
		local previous = tostring(apply(nil))
		local ok, current = pcall(apply, input)
		box.Text = ok and tostring(current) or previous
		debugEvent("UI", "setting_changed", { name=name,requested=tostring(input),result=box.Text },
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

local BUTTON_SIGNALS = { "MouseButton1Down","Activated","MouseButton1Click","TouchTap" }

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
		if ok and signal and fireConnections(signal) then
            increment("skillcheckInputSignal")
            return true, "signal_" .. name
        end
	end
	local sent = tapGuiObject(button)
    if sent then increment("skillcheckInputVIM") end
    return sent, sent and "virtual_mouse" or "input_failed"
end

local function normRot(r) return (r + 180) % 360 - 180 end

local function newAutoSkillcheck()
	local feature = { enabled=false }
	local runId = 0
	local beats = {}
	local function active(id) return alive and feature.enabled and runId == id end
	local function stop()
		for connection in pairs(beats) do pcall(function() connection:Disconnect() end) end
		table.clear(beats)
	end
	-- Heartbeat is reliable even with 3D rendering disabled. PreRender provides a
	-- second chance to see short-lived GUI frames without changing hit timing.
	local function watchFrames(callback)
		local failed, errors = false,0
		local function protectedCheck()
			if failed then return end
			local ok,err = pcall(callback)
			if not ok then
				errors += 1
				increment("skillcheckWatchErrors")
				debugThrottled("skillcheck_frame_error",1,"SKILLCHECK","watch_error",
					{ error=tostring(err),count=errors },"WARN")
				if errors >= 2 then failed = true end
			else
				errors = 0
			end
		end
		local attached = {}
		local heartbeat = RunService.Heartbeat:Connect(protectedCheck)
		beats[heartbeat],attached[heartbeat] = true,true
		local ok,render = pcall(function()
			return RunService.PreRender:Connect(protectedCheck)
		end)
		if ok and render then
			beats[render],attached[render] = true,true
			increment("skillcheckFrameConnections")
		end
		return function()
			for connection in pairs(attached) do
				connection:Disconnect()
				beats[connection] = nil
			end
		end,function() return failed end
	end
	local function bindRound(id)
		local missingEpisode = false
		while active(id) do
			local normal = UNLOAD.skillcheckNodes()
			local aim = normal and normal:FindFirstChild("AimImage",true)
			local target = normal and normal:FindFirstChild("Target",true)
			local hit = normal and normal:FindFirstChild("Hit",true)
			if not (normal and aim and target and hit) then
				if normal and effectivelyVisible(normal) and not missingEpisode then
					missingEpisode = true
					increment("skillcheckMissingParts")
					debugThrottled("round_parts_missing",0.75,"SKILLCHECK","round_waiting_for_parts",
						{ aim=aim ~= nil,target=target ~= nil,hit=hit ~= nil },"WARN")
				end
			task.wait(0.03)
			else
				missingEpisode = false
				local fired, firedAt = false,0
				local lastVisible,lastValue,lastAim,lastTarget = false,nil,nil,nil
				local bindTime = os.clock()
				local function check()
					if not active(id) or not normal:IsDescendantOf(playerGui) then return end
					local visible = effectivelyVisible(normal)
					if visible ~= lastVisible then
						if visible then
							fired,firedAt,lastValue,lastAim,lastTarget = false,0,nil,nil,nil
							increment("skillcheckRoundSeen")
							debugThrottled("round_ui_seen",0.5,"SKILLCHECK","round_detected",
								{ bindDelayMs=math.floor((os.clock()-bindTime)*1000) })
						else
							lastValue,lastAim,lastTarget = nil,nil,nil
						end
						lastVisible = visible
					end
					if not visible then return end
					local now = os.clock()
					local aimRot,targetRot = aim.Rotation,target.Rotation
					local currentAim = normRot(aimRot+180)
					local zoneStart = normRot(targetRot-30)
					local value = math.abs(((currentAim-zoneStart)+180)%360-180)/60
					-- A widget may remain Visible across separate checks. A changed
					-- target, or a discontinuous pointer reset, marks a NEW check.
					if fired and now-firedAt > 0.30 then
						local targetReset = lastTarget and math.abs(normRot(targetRot-lastTarget)) > 5
						local pointerReset = lastAim and math.abs(normRot(aimRot-lastAim)) > 75
						if targetReset or pointerReset then
							fired,lastValue = false,nil
							increment("skillcheckRearms")
							debugThrottled("round_rearm",0.3,"SKILLCHECK","round_new_cycle",
								{ reason=targetReset and "target_changed" or "pointer_reset" })
						end
					end
					if not fired then
						local crossed = lastValue and lastValue < 0.44 and value >= 0.44
						local late = lastValue == nil and value >= 0.44 and value <= 0.52
						if crossed or late then
							-- Lock BEFORE dispatch: both Heartbeat and PreRender observe
							-- the same widget, but must never double-activate it.
							fired,firedAt = true,now
							if late then increment("skillcheckLateAttached") end
							local sent,method = pressGuiButton(hit)
							if sent then increment("skillcheckInputs")
							else increment("skillcheckInputFailures") end
							debugEvent("SKILLCHECK","dial_input",{
								dispatched=sent,method=method,lateAttach=late,
								position=string.format("%.3f",value),
							},sent and "INFO" or "WARN")
						end
					end
					lastValue,lastAim,lastTarget = value,aimRot,targetRot
				end
				local disconnect,broken = watchFrames(check)
				increment("skillcheckRebinds")
				while active(id) and not broken() and normal:IsDescendantOf(playerGui)
					and aim:IsDescendantOf(normal) and target:IsDescendantOf(normal)
					and hit:IsDescendantOf(normal) do
					local latest = UNLOAD.skillcheckNodes()
					if latest ~= normal then
						 increment("skillcheckUiRecreated")
						 break
					end
					if normal:FindFirstChild("AimImage",true) ~= aim
						or normal:FindFirstChild("Target",true) ~= target
						or normal:FindFirstChild("Hit",true) ~= hit then
						increment("skillcheckUiRecreated")
						break
					end
					task.wait(0.04)
				end
			disconnect()
		end
		end
	end
	local function bindBar(id)
		local missingEpisode = false
		while active(id) do
			local _,main,marker = UNLOAD.skillcheckNodes()
			local objective = main and main:FindFirstChild("Objective",true)
			local button = main and main:FindFirstChild("MobileButtonClick",true)
			if not (main and marker and objective and button) then
				if main and effectivelyVisible(main) and not missingEpisode then
					missingEpisode = true
					increment("skillcheckMissingParts")
					debugThrottled("bar_parts_missing",0.75,"SKILLCHECK","bar_waiting_for_parts",
						{ marker=marker ~= nil,objective=objective ~= nil,button=button ~= nil },"WARN")
				end
			task.wait(0.03)
			else
				missingEpisode = false
				local fired,firedAt = false,0
				local lastVisible,lastDist,lastMarkerX,lastObjectiveX = false,nil,nil,nil
				local bindTime = os.clock()
				local function check()
					if not active(id) or not main:IsDescendantOf(playerGui) then return end
					local visible = effectivelyVisible(marker)
					if visible ~= lastVisible then
						if visible then
							fired,firedAt,lastDist,lastMarkerX,lastObjectiveX = false,0,nil,nil,nil
							increment("skillcheckBarSeen")
							debugThrottled("bar_ui_seen",0.5,"SKILLCHECK","bar_detected",
								{ bindDelayMs=math.floor((os.clock()-bindTime)*1000) })
						else
							lastDist,lastMarkerX,lastObjectiveX = nil,nil,nil
						end
						lastVisible = visible
					end
					if not visible then return end
					local now = os.clock()
					local markerX = marker.AbsolutePosition.X+marker.AbsoluteSize.X*0.5
					local objectiveX = objective.AbsolutePosition.X+objective.AbsoluteSize.X*0.5
					local dist = markerX-objectiveX
					if fired and now-firedAt > 0.30 then
						local targetReset = lastObjectiveX and math.abs(objectiveX-lastObjectiveX) > 7
						local pointerReset = lastMarkerX and (lastMarkerX-markerX) > math.max(35,marker.AbsoluteSize.X*3)
							and dist < -math.max(12,objective.AbsoluteSize.X*0.75)
						if targetReset or pointerReset then
							fired,lastDist = false,nil
							increment("skillcheckRearms")
							debugThrottled("bar_rearm",0.3,"SKILLCHECK","bar_new_cycle",
								{ reason=targetReset and "objective_changed" or "marker_reset" })
						end
					end
					if not fired then
						local crossed = lastDist and lastDist < -2 and dist >= -2
						local late = lastDist == nil and dist >= -2
							and dist <= math.max(4,objective.AbsoluteSize.X*0.20)
						if crossed or late then
							fired,firedAt = true,now
							if late then increment("skillcheckLateAttached") end
							local sent,method = pressGuiButton(button)
							if sent then increment("skillcheckInputs")
							else increment("skillcheckInputFailures") end
							debugEvent("SKILLCHECK","bar_input",{
								 dispatched=sent,method=method,lateAttach=late,
								 distance=string.format("%.2f",dist),
							},sent and "INFO" or "WARN")
						end
					end
					lastDist,lastMarkerX,lastObjectiveX = dist,markerX,objectiveX
				end
				local disconnect,broken = watchFrames(check)
				increment("skillcheckRebinds")
				while active(id) and not broken() and main:IsDescendantOf(playerGui)
					and marker:IsDescendantOf(main) and objective:IsDescendantOf(main)
					and button:IsDescendantOf(main) do
					local _,latestMain,latestMarker = UNLOAD.skillcheckNodes()
					if latestMain ~= main or latestMarker ~= marker
						or main:FindFirstChild("Objective",true) ~= objective
						or main:FindFirstChild("MobileButtonClick",true) ~= button then
						increment("skillcheckUiRecreated")
						break
					end
					task.wait(0.04)
				end
			disconnect()
		end
	end
	end
	function feature.enable()
		if feature.enabled then return end
		feature.enabled = true
		runId += 1
		local id = runId
		supervise("skillcheck dial",function() return active(id) end,function() bindRound(id) end)
		supervise("skillcheck bar",function() return active(id) end,function() bindBar(id) end)
	end
	function feature.disable()
		feature.enabled = false
		runId += 1
		stop()
	end
	table.insert(cleanups,feature.disable)
	return feature
end

autoSkillcheck = newAutoSkillcheck()
autoSkillcheck.enable()

machineFarm = newMachineAutofarm()

-- This UI/diagnostics initialization is isolated in its own function frame.
-- Luau limits the number of simultaneously active local registers in one
-- function to 200; adding all GUI controls to the long top-level chunk
-- exceeded that limit at refreshMovementMode in v2.6.44.
-- The new function captures preexisting state through normal Lua upvalues.
UNLOAD.finishInitialization = function()

do
local mainBody = pages.AFK
local mainControl = createSubcategory(mainBody, "AFK START / STOP", 1, true)
local farmFeatures = { capsuleFarm,itemFarm,candyFarm,machineFarm,
	autoSkillcheck,autoUse,autoAbility,UNLOAD.trashUseToggle }
local master = { enabled=false }
local function allEnabled()
	for _, feature in ipairs(farmFeatures) do
		if not feature.enabled then return false end
	end
	return true
end
function master.enable()
	for _, feature in ipairs(farmFeatures) do
		if not feature.enabled then feature.enable() end
	end
	master.enabled = allEnabled()
	increment("masterToggles")
	debugEvent("MAIN", "autofarm_enabled", { allEnabled=master.enabled })
end
function master.disable()
	for _, feature in ipairs(farmFeatures) do
		if feature.enabled then feature.disable() end
	end
	master.enabled = false
	increment("masterToggles")
	debugEvent("MAIN", "autofarm_disabled")
end
local function refreshMaster()
	master.enabled = allEnabled()
end
table.insert(toggleRefreshers, refreshMaster)
createToggleRow(mainControl, "Master Autofarm", 1, master, "One-click control for all core autofarms")
end

do
local machinesBody = pages.AFK
local machineCore = createSubcategory(machinesBody, "MACHINE & SKILLCHECK AUTOFARM", 2, true)
createToggleRow(machineCore, "Machine Autofarm", 1, machineFarm)
createToggleRow(machineCore, "Auto Skillcheck", 2, autoSkillcheck)

local machineMovement = createSubcategory(pages.Manual, "MOVEMENT SETTINGS", 3, true)
local modeRow = new("Frame", { LayoutOrder=1,Size=UDim2.new(1,-9,0,43),
	BackgroundColor3=UI.surface,BorderSizePixel=0 }, machineMovement)
corner(modeRow, 9)
uiStroke(modeRow)
uiText(modeRow, "Movement Mode", 14, true, UI.text, {
	Position=UDim2.fromOffset(12,0),Size=UDim2.new(0.42,0,1,0),
})
local tweenButton = new("TextButton", {
	Text="TWEEN",Font=Enum.Font.GothamBold,TextSize=11,
	TextColor3=UI.text,BorderSizePixel=0,
	Position=UDim2.new(0.46,0,0.5,-14),Size=UDim2.new(0.25,-3,0,28),
}, modeRow)
local teleportButton = new("TextButton", {
	Text="TELEPORT",Font=Enum.Font.GothamBold,TextSize=10,
	TextColor3=UI.text,BorderSizePixel=0,
	Position=UDim2.new(0.72,0,0.5,-14),Size=UDim2.new(0.26,-8,0,28),
}, modeRow)
corner(tweenButton, 7)
corner(teleportButton, 7)
local depthRow = new("Frame", { LayoutOrder=2,Size=UDim2.new(1,-9,0,65),
	BackgroundColor3=UI.surface,BorderSizePixel=0,Visible=false }, machineMovement)
corner(depthRow, 9)
uiStroke(depthRow)
uiText(depthRow, "Under-map Depth", 14, true, UI.text, {
	Position=UDim2.fromOffset(12,2),Size=UDim2.new(1,-110,0,26),
})
local depthValue = uiText(depthRow, "−15 studs", 12, true, UI.accent, {
	Position=UDim2.new(1,-108,0,2),Size=UDim2.fromOffset(96,26),
	TextXAlignment=Enum.TextXAlignment.Right,
})
local depthTrack = new("TextButton", { Text="",AutoButtonColor=false,
	Position=UDim2.new(0,16,0,33),Size=UDim2.new(1,-32,0,24),
	BackgroundTransparency=1,BorderSizePixel=0 }, depthRow)
local depthRail = new("Frame", { BackgroundColor3=UI.soft,BorderSizePixel=0,
	Position=UDim2.fromOffset(0,9),Size=UDim2.new(1,0,0,6) }, depthTrack)
corner(depthRail, 3)
local depthFill = new("Frame", { BackgroundColor3=UI.accent,BorderSizePixel=0,
	Position=UDim2.fromOffset(0,9),Size=UDim2.new(0,0,0,6) }, depthTrack)
corner(depthFill, 3)
local depthKnob = new("Frame", { AnchorPoint=Vector2.new(0.5,0.5),
	Size=UDim2.fromOffset(17,17),BackgroundColor3=UI.text,
	BorderSizePixel=0 }, depthTrack)
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
		debugEvent("MOVE", "mode_change_blocked", { requested=mode,reason="travel_active" }, "WARN")
		return
	end
	OPTIONS.MovementMode = mode
	refreshMovementMode()
	debugEvent("MOVE", "mode_changed", { mode=mode,depth=OPTIONS.TweenDepth })
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
		debugEvent("MOVE", "depth_changed", { depth=OPTIONS.TweenDepth })
	end
end))
table.insert(toggleRefreshers, refreshMovementMode)
refreshMovementMode()

local machineSafety = createSubcategory(machinesBody, "SURVIVAL & AUTO HIDE", 3, true)
createToggleRow(machineSafety, "Auto Hide", 1, newOption(OPTIONS, "AutoHide"))
createToggleRow(UNLOAD.manualThreatSection, "Look At Selena", 3, UNLOAD.selenaLook)
createInputRow(machineSafety, "Danger range (studs)", 2, function(value)
	if value and value > 0 and value < 2000 then MACHINE.Range = value end
	return MACHINE.Range
end)

local machineFlow = createSubcategory(machinesBody, "BLACKOUT & ELEVATOR AUTOMATION", 4, true)
createToggleRow(machineFlow, "Auto Elevator", 1, newOption(OPTIONS, "AutoElevator"))
createToggleRow(machineFlow, "Fusebox Check", 2, newOption(OPTIONS, "Fuseboxes"))

local machinePerformance = createSubcategory(pages.Manual, "VISUAL PERFORMANCE", 4, true)
createToggleRow(machinePerformance, "Disable 3D Rendering", 1, UNLOAD.render3d)
end

local diagnosticsPage = pages.Diagnostics
local diagnosticsOverview = createSubcategory(diagnosticsPage, "SESSION OVERVIEW", 1, true)
local diagnosticsTools = createSubcategory(diagnosticsPage, "EXPORT & FILTER", 2, true)
local diagnosticsEvents = createSubcategory(diagnosticsPage, "RECENT EVENTS", 3, true)
local summaryCard = new("Frame", { Size=UDim2.new(1,-9,0,156),
	BackgroundColor3=UI.surface,BorderSizePixel=0,LayoutOrder=1 }, diagnosticsOverview)
corner(summaryCard, 10)
uiStroke(summaryCard)
local stateLabel = uiText(summaryCard, "RUNNING", 12, true, UI.good, {
	Position=UDim2.fromOffset(13,10),Size=UDim2.new(1,-25,0,21),
})
local statsLabel = uiText(summaryCard, "Collecting diagnostic counters...", 12, false, UI.text, {
	Position=UDim2.fromOffset(13,35),Size=UDim2.new(1,-25,0,114),
	TextYAlignment=Enum.TextYAlignment.Top,TextWrapped=true,
})
local toolsRow = new("Frame", { Size=UDim2.new(1,-9,0,42),
	BackgroundTransparency=1,LayoutOrder=2 }, diagnosticsTools)
local function actionButton(name, width, x, color)
	local button = new("TextButton", { Text=name,Size=UDim2.fromOffset(width,36),
		Position=UDim2.fromOffset(x,3),BackgroundColor3=color,
		TextColor3=UI.text,TextSize=12,Font=Enum.Font.GothamBold,
		BorderSizePixel=0 }, toolsRow)
	corner(button, 8)
	return button
end
local exportButton = actionButton("EXPORT LOG", 110, 0, UI.accent)
local copyButton = actionButton("COPY LOG", 101, 119, UI.surface2)
local warningButton = actionButton("WARNINGS: OFF", 130, 229, UI.surface2)
local outputStatus = uiText(diagnosticsTools, "Logs export manually, on unload, and automatically at 0 HP.", 11, false, UI.muted,
	{ Size=UDim2.new(1,-9,0,22),LayoutOrder=3 })
UNLOAD.secondaryButton = new("TextButton", {
	Name="DiagnosticsUnloadHub",Text="UNLOAD HUB",LayoutOrder=4,
	Size=UDim2.new(1,-9,0,34),BackgroundColor3=Color3.fromRGB(92,47,62),
	TextColor3=UI.text,TextSize=12,Font=Enum.Font.GothamBold,
	BorderSizePixel=0,
}, diagnosticsTools)
corner(UNLOAD.secondaryButton, 8)
track(UNLOAD.secondaryButton.Activated:Connect(function()
	UNLOAD.request("diagnostics_button")
end))
local logDisplay = new("TextBox", { Size=UDim2.new(1,-9,0,190),
	BackgroundColor3=Color3.fromRGB(11,14,21),BorderSizePixel=0,
	Text="No events yet.",TextColor3=Color3.fromRGB(194,207,232),
	TextSize=11,Font=Enum.Font.Code,TextXAlignment=Enum.TextXAlignment.Left,
	TextYAlignment=Enum.TextYAlignment.Top,TextWrapped=true,
	TextEditable=false,MultiLine=true,ClearTextOnFocus=false,
	LayoutOrder=4 }, diagnosticsEvents)
corner(logDisplay, 9)
local warningsOnly = false
track(warningButton.MouseButton1Click:Connect(function()
	warningsOnly = not warningsOnly
	warningButton.Text = "WARNINGS: " .. (warningsOnly and "ON" or "OFF")
	debugEvent("UI", "diagnostic_filter", { warningsOnly=warningsOnly })
end))

local function debugReport()
	local summary = {
		"TU Rava Hub | Diagnostic Report",
		"Build=" .. BUILD,
		"Exported=" .. os.date("%Y-%m-%d %H:%M:%S"),
		string.format("SessionSeconds=%.2f PlaceId=%s JobId=%s",
			os.clock() - debugStart,tostring(game.PlaceId),tostring(game.JobId)),
		"Mode=" .. OPTIONS.MovementMode .. " underMapDepth=" .. tostring(OPTIONS.TweenDepth),
		"Movement policy=AFK machine/pickup/fuse/return routes use surface teleports only; unsupported targets rejected",
		"VoidGuard=grounded checkpoint; auto-recovery; lock after 3 recoveries/30s; deathless safety first",
		"UI layout=Manual (ESP, view, movement), AFK (machine automation, survival, pickups, blackout, automatic item use), Diagnostics",
		"Movement priority=instant objective handoffs/Auto Hide; routine pickups follow movement selection; prompt spam stays at 16/s",
		"LOS=disabled only for prompts; pickup routing uses monster-to-pickup raycasts (client-side estimates)",
		"Hit attribution=nearest infected only (not confirmed attacker)",
		"Selena camera=look after Chase Started when TSelena is loaded; stops when unloaded/toggle off",
		"Machine exit=SkillCheck:InvokeServer() with no arguments on each Auto Hide; never skipped for visible UI or earlier in-flight request",
		"Skillcheck protection=normally defer exits and travel; immediate danger or health loss permits urgent escape",
		"Elevator check=platform, alternative elevator position, and optional replicated state; no server entry guarantee",
		"Pickups=before machines only; 24s phase budget and 8s no-progress cutoff",
				"Elevator fallback=short grounded CFrame steps only; backup after 3.5-11s; 15s watchdog with bounded retry if entry unverified",
		"Ability=press F once per detected machine completion; no cooldown HUD polling or Ability remote",
		"Ability input dispatched is not proof the game accepted it; active skillchecks block completion handling",
		"Prompts=enabled-aware lookup, visibility events, teleport-only contact correction; dispatched is not confirmed",
		"Snake safety=client-only collidable rectangular guard follows every TSnakes; live rectangular below-snake pickup exclusion; checks on route/prompt/retry",
		"Autofarm prompt correction=teleport-only, no Humanoid Move/MoveTo or walking keys; elevator touch-entry recovery remains independent",
		"Item hotkeys=executor keypress preferred, VIM fallback; input success does not prove item effect",
		"AbilityConfig: " .. fieldString(ABILITY),
		"Death export=automatic when observed health <= 0 (once per life)",
		"Handoff timing=objective completion/unavailable to first immediate prompt dispatch; progression wakeup is value event-driven",
		"Sound cues=MainMachineFillingUp means base done; MainMachineCompleted means main done; Flush secondary; Fuses blackout; Countdown StopSound early hint; DoorClosing final only when all objectives complete",
		"Elevator choice=after final machines use ElevatorDoor Parent ancestry; blackout box=opposite of last closed elevator door; 2s geometry fallback for actual elevator",
        "Blackout=fuse objects under workspace.Items collected separately before chosen fusebox; Item Autofarm ignores Fuse",
		"Threat detection=nearest active moving core + short approaching-velocity prediction + vertical separation + explicit chase event",
		"Auto Hide transitions=asynchronous exit request, grounded shelter when needed, >=2.5s dwell plus >=1.5s continuously clear before objective return",
		"Session objective target=1000 machine completions in a single 0-HP-free streak; GOAL.Streak resets to zero on death",
		"FloorState: " .. fieldString({ observed=UNLOAD.floorState.seen,
			completed=UNLOAD.floorState.completed,finished=UNLOAD.floorState.finished,
			reason=UNLOAD.floorState.completionReason }),
		string.format("Client touch=%s promptFire=%s virtualInput=%s clipboard=%s writefile=%s",
			tostring(UserInputService.TouchEnabled),tostring(hasFirePrompt),
			tostring(pcall(function() return game:GetService("VirtualInputManager") end)),
			tostring(typeof(setclipboard) == "function"),tostring(typeof(writefile) == "function")),
		"Stats: " .. fieldString(debugStats),
		"Goal: " .. fieldString(GOAL),
		"Status: " .. fieldString(debugStatus),
		"AutoHideState: " .. fieldString(machineFarm and machineFarm.hideState and {
			active=machineFarm.hideState.active,reason=machineFarm.hideState.reason,
			seconds=machineFarm.hideState.active and
				string.format("%.2f",os.clock()-machineFarm.hideState.since) or "0",
			shelterReached=machineFarm.hideState.shelterReached,
		} or { active=false }),
		string.format("Performance: firstObjectiveMs=%d handoffs=%d averageMs=%.1f maxMs=%d lastMs=%d slowScans=%d cacheRefreshes=%d cacheHits=%d",
			debugStats.firstObjectiveMs,debugStats.handoffs,
			debugStats.handoffs > 0 and debugStats.handoffTotalMs / debugStats.handoffs or 0,
			debugStats.handoffMaxMs,debugStats.handoffLastMs,debugStats.slowMachineScans,
			debugStats.targetCacheRefreshes,debugStats.targetCacheHits),
		"Movement: " .. fieldString({ mode=OPTIONS.MovementMode,depth=OPTIONS.TweenDepth,speed=PICKUP_TRAVEL.Speed }),
		"Rendering3D=" .. (OPTIONS.Disable3DRendering and "disabled" or "enabled"),
		"SelenaCamera: " .. fieldString({ enabled=UNLOAD.selenaLook.enabled,chasing=UNLOAD.selenaLook.chaseSeen,
			tracking=UNLOAD.selenaLook.active }),
		"CapsuleSources=workspace.Capsules; workspace.Map.InfectedSamples",
		"TrashItems=Coffee; Socks; Waffle; Pristine Boots (Waffle preferred after ability)",
		string.format("Tween: arrived=%d aborted=%d hpStops=%d guards=%d pickupDistance=%d",
			debugStats.underMapTweens,debugStats.underMapAborts,debugStats.underMapHealthStops,
			debugStats.underMapGuardBlocks,debugStats.pickupTweenDistance),
		"PickupTiming=Before; 0.14s teleport / 0.11s tween pickup-only interruptible gaps",
		"PickupPhase: " .. fieldString({ completed=UNLOAD.pickupBefore.completed,
			started=UNLOAD.pickupBefore.started ~= nil,mapLoaded=UNLOAD.pickupBefore.mapRef ~= nil }),
		"PickupGuard: " .. fieldString({ paused=pickupCircuit.paused,finalized=pickupCircuit.finalized,
			contactRetries=debugStats.pickupContactRetries,contactRecovered=debugStats.pickupContactRecovered,
			failures=pickupCircuit.consecutive,
			failedTargets=pickupCircuit.distinctFailures,targetLimit=pickupCircuit.MaxTargetFailures,
			noProgressSeconds=pickupCircuit.MaxStallSeconds }),
		"ExitSoundSelection: " .. fieldString({ selectedPath=UNLOAD.elevatorSoundPath or "none",
			selections=debugStats.soundElevatorSelections,reroutes=debugStats.soundElevatorReroutes,
			unmapped=debugStats.soundElevatorUnmappedDoor,fallbacks=debugStats.soundElevatorSoundFallbacks }),
		"Options: " .. fieldString(OPTIONS),
		"FARM: " .. fieldString(FARM),
		"MACHINE: " .. fieldString({ Range=MACHINE.Range,NearFinishAt=MACHINE.NearFinishAt,
			NearFinishHold=MACHINE.NearFinishHold,StallTimeout=MACHINE.StallTimeout,
			UseTimeout=MACHINE.UseTimeout,ChaseHold=MACHINE.ChaseHold,
			ItemWaitMax=MACHINE.ItemWaitMax,RescanInterval=MACHINE.RescanInterval }),
		"ItemInput: " .. fieldString({ executorKeypress=typeof(keypress) == "function",
			executorKeyrelease=typeof(keyrelease) == "function",virtualInput=pcall(function()
				return game:GetService("VirtualInputManager") end) }),
		"Enabled: " .. fieldString({ capsules=capsuleFarm.enabled,items=itemFarm.enabled,
			candy=candyFarm.enabled,machine=machineFarm.enabled,
			skillchecks=autoSkillcheck.enabled,autoUse=autoUse.enabled,
			autoAbility=autoAbility.enabled,autoTrashUse=ITEM_OPTIONS.AutoTrashUse }),
		string.format("LogEvents=%d Retained=%d Dropped=%d",debugIndex,
			math.min(debugIndex,LOG_LIMIT),math.max(0,debugIndex - LOG_LIMIT)),
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
	debugEvent("DEBUG", "export_requested", { reason=reason })
	if typeof(writefile) ~= "function" then
		debugEvent("DEBUG", "export_failed", { reason="writefile unavailable" }, "WARN")
		showExportStatus("Export unavailable. Try Copy Log instead.")
		return false
	end
	local prefix = reason == "death" and "TU_Rava_Hub_DEATH_Debug_" or "TU_Rava_Hub_Debug_"
	local filename = prefix .. os.time() .. "_" .. math.floor((os.clock() % 1) * 100000) .. ".txt"
	local ok, err = pcall(writefile, filename, debugReport())
	if ok then
		showExportStatus("Saved: " .. filename)
		debugEvent("DEBUG", "export_success", { filename=filename,reason=reason })
		return true
	end
	showExportStatus("Export failed: " .. tostring(err):sub(1, 70))
	debugEvent("DEBUG", "export_failed", { error=err,reason=reason }, "ERROR")
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
	debugEvent("DEBUG", ok and "copy_success" or "copy_failed", { error=not ok and err or "none" },
		ok and "INFO" or "ERROR")
end))
supervise("diagnostic UI", function() return alive end, function()
	while alive do
		if main.Visible then for _, refresh in ipairs(toggleRefreshers) do refresh() end end
		if main.Visible then
			local working = (machineFarm.enabled and "MACHINE") or (pickupBusy() and "PICKUPS") or "IDLE"
			headerStatus.Text = working .. "  •  " .. (BUILD:match("v%d+%.%d+%.%d+") or "RAVA")
			headerStatus.TextColor3 = working == "IDLE" and UI.muted or UI.good
			footerLabel.Text = string.format("%s   •   %s   •   %d moves", BUILD, OPTIONS.MovementMode,
				debugStats.teleports + debugStats.underMapTweens)
			afkGoalLabel.Text = string.format("%d / %d machines  |  %d deaths  |  Best %d",
				GOAL.Streak,GOAL.Target,GOAL.Deaths,GOAL.Best)
			afkGoalLabel.TextColor3 = GOAL.Achieved and UI.good or GOAL.Deaths > 0 and UI.bad or UI.text
		end
		if activeTab == "Diagnostics" and main.Visible then
			stateLabel.Text = string.format("DEATHLESS: %d/%d  |  Best %d  |  0 HP: %d",
				GOAL.Streak,GOAL.Target,GOAL.Best,GOAL.Deaths)
			statsLabel.Text = string.format("Hits %d  |  Damage %.1f  |  Handoffs %d (avg %.0fms)\nTeleports %d  |  Pickups %d/%d  |  ESP %d active\nMachines %d total  |  Stalls %d  |  Errors %d\nSounds oil %d  |  computer %d  |  base %d  |  mainDone %d  |  blackout %d\nFlush %d  |  door %d  |  closing %d  |  countdown %d\nAbilities %d  |  Trash inputs %d  |  Death logs %d",
				debugStats.hits, debugStats.totalDamage, debugStats.handoffs,
				debugStats.handoffs > 0 and debugStats.handoffTotalMs / debugStats.handoffs or 0,
				debugStats.teleports, debugStats.pickupConfirmed, debugStats.pickupAttempts,
				math.max(0, debugStats.espAdded - debugStats.espRemoved),
				debugStats.machineCompletions, debugStats.machineStalls, debugStats.workerErrors,
				debugStats.soundOilDone,debugStats.soundComputerDone,
				debugStats.soundMainReady,debugStats.soundMainCompleted,debugStats.soundBlackout,
				debugStats.soundMainFlush,debugStats.soundElevatorDoor,
				debugStats.soundElevatorDoorClosing,debugStats.soundElevatorCountdownAccepted,
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
debugEvent("SYSTEM", "initialized", { build=BUILD,place=game.PlaceId,
	startupChecks="passed",fallbackExport=true,
    diagnosticsTab=menuButtons.Diagnostics ~= nil and pages.Diagnostics ~= nil,
    diagnosticsDock=diagnosticsDock.Parent ~= nil,ui="manual_afk_collapsible",
	mode=OPTIONS.MovementMode,underMapDepth=OPTIONS.TweenDepth,selenaCamera=true,
	lineOfSight="disabled",abilityAuto=true,abilityTrigger="F_after_machine_completion",sampleFarm=true,pickupSpeed=PICKUP_TRAVEL.Speed,
	enemyClearance=PICKUP_TRAVEL.SafetyRadius,pickupSettle=FARM.Settle,
	pickupDwell=FARM.Dwell,pickupRate=FARM.SpamRate,itemWaitMax=MACHINE.ItemWaitMax,promptMoveFix=true })
task.spawn(function()
	local previous = {}
	local watchFolders = { "Items","Capsules","Map.InfectedSamples","Candies","Computers","OilMachines","MonsterFolder" }
	while alive do
		for _, folderName in ipairs(watchFolders) do
			local folder = resolveWorkspacePath(folderName)
			local present = folder ~= nil
			if previous[folderName] ~= present then
				debugEvent("WORLD", present and "folder_found" or "folder_missing",
					{ name=folderName,children=folder and #folder:GetChildren() or 0 },
					present and "INFO" or "WARN")
				previous[folderName] = present
			end
		end
		task.wait(5)
	end
end)

UNLOAD.handler = function(source)
	debugEvent("SYSTEM", "unload", {
		source=source or "requested",
		elapsed=string.format("%.2f",os.clock() - debugStart),
	})
	cancelMotion()
	UNLOAD.force(source)
end

end -- UNLOAD.finishInitialization
UNLOAD.finishInitialization()
UNLOAD.finishInitialization = nil -- release one-time initializer reference
