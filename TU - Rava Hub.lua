
    
  
		"Options: " .. fieldString(OPTIONS),
		"FARM: " .. fieldString(FARM),
		"MACHINE: " .. fieldString({ Range = MACHINE.Range, NearFinishAt = MACHINE.NearFinishAt,
			NearFinishHold = MACHINE.NearFinishHold, StallTimeout = MACHINE.StallTimeout,
			UseTimeout = MACHINE.UseTimeout, ChaseHold = MACHINE.ChaseHold,
			ItemWaitMax = MACHINE.ItemWaitMax, RescanInterval = MACHINE.RescanInterval }),
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
		headerStatus.Text = working .. "  •  v2.6.19"
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
	pickupDwell = FARM.Dwell, pickupRate = FARM.SpamRate, itemWaitMax = MACHINE.ItemWaitMax, promptMoveFix = true })
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

