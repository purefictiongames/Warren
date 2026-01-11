--[[
    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC

    This software, its architecture, and associated documentation are proprietary
    and confidential. All rights reserved.

    Unauthorized copying, modification, distribution, or use of this software,
    in whole or in part, is strictly prohibited without prior written permission.
--]]

-- Orchestrator.Script (Server)
-- Coordinates game flow - receives events via Input, sends commands via Output
-- Applies RunModes configuration to assets based on player mode changes
-- Black box implementation - no direct asset references

-- Guard: Only run if this is the deployed version (has dot in name)
if not script.Name:match("%.") then
	return
end

-- Extract asset name from script name
local assetName = script.Name:match("^(.+)%.")
if not assetName then
	warn("[Orchestrator.Script] Could not extract asset name from script.Name:", script.Name)
	return
end

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Wait for boot system - ORCHESTRATE stage means all assets are initialized
local System = require(ReplicatedStorage:WaitForChild("System.System"))
System:WaitForStage(System.Stages.ORCHESTRATE)

-- Load RunModes API
local RunModes = require(ReplicatedStorage:WaitForChild("RunModes.RunModes"))

-- Load Transition API
local Transition = require(ReplicatedStorage:WaitForChild("GUI.Transition"))
local transitionEvents = Transition:GetEvents()

-- Get standardized events (created by bootstrap)
local inputEvent = ReplicatedStorage:WaitForChild(assetName .. ".Input")
local outputEvent = ReplicatedStorage:WaitForChild(assetName .. ".Output")

-- Input modal functions (for locking prompts during countdown)
local pushModal = ReplicatedStorage:WaitForChild("Input.PushModal")
local popModal = ReplicatedStorage:WaitForChild("Input.PopModal")

-- Track if game loop is running
local gameRunning = false

-- Track pending mode changes (player -> { newMode, oldMode })
local pendingModeChange = {}

-- Track if we're waiting for countdown to complete before starting game
local awaitingCountdown = false
local countdownPlayer = nil -- Player waiting for countdown to complete
local savedMovement = nil -- { walkSpeed, jumpPower } to restore after countdown

-- Freeze player movement (for countdown)
local function freezePlayer(player)
	local character = player.Character
	if not character then return end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end

	-- Save current values
	savedMovement = {
		walkSpeed = humanoid.WalkSpeed,
		jumpPower = humanoid.JumpPower,
	}

	-- Freeze
	humanoid.WalkSpeed = 0
	humanoid.JumpPower = 0
	System.Debug:Message(assetName, "Froze player movement for", player.Name)
end

-- Unfreeze player movement (after countdown)
local function unfreezePlayer(player)
	local character = player.Character
	if not character then return end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end

	-- Restore saved values or use defaults
	if savedMovement then
		humanoid.WalkSpeed = savedMovement.walkSpeed
		humanoid.JumpPower = savedMovement.jumpPower
		savedMovement = nil
	else
		humanoid.WalkSpeed = 16 -- Default
		humanoid.JumpPower = 50 -- Default
	end
	System.Debug:Message(assetName, "Unfroze player movement for", player.Name)
end

-- Apply mode configuration to all assets
-- Sends enable/disable commands via Router to each asset
local function applyModeToAssets(mode)
	local config = RunModes:GetConfig(mode)
	if not config or not config.assets then
		System.Debug:Warn(assetName, "No asset config for mode:", mode)
		return
	end

	System.Debug:Message(assetName, "Applying mode config:", mode)

	for targetAssetName, settings in pairs(config.assets) do
		-- Apply active state
		if settings.active ~= nil then
			local command = settings.active and "enable" or "disable"
			local message = {
				target = targetAssetName,
				command = command
			}

			-- Include behavior if specified in config
			if settings.behavior then
				message.behavior = settings.behavior
			end

			System.Debug:Message(assetName, "Sending", command, "to", targetAssetName, settings.behavior and ("behavior:" .. settings.behavior) or "")
			System.Router:Send(assetName, message)
		end
	end

	System.Debug:Message(assetName, "Finished applying mode config:", mode)
end

-- Start the game loop (or resume after wave transition)
local function startGameLoop()
	if gameRunning then return end
	gameRunning = true

	-- Update Router context
	System.Router:SetContext("gameActive", true)

	System.Debug:Message(assetName, "Starting game loop")

	-- Reset dispenser (targeted command)
	System.Router:Send(assetName, { target = "MarshmallowBag", command = "reset" })

	-- Signal WaveController to start spawning (uses static wiring)
	System.Router:Send(assetName, { action = "gameStarted" })

	-- Start the play timer (targeted command)
	System.Router:Send(assetName, { target = "PlayTimer", command = "start" })
end

-- Pause the game loop (between waves - player can still move)
local function pauseGameLoop()
	if not gameRunning then return end

	-- Stop spawning but don't clear state (uses static wiring)
	System.Router:Send(assetName, { action = "wavePaused" })

	-- Stop PlayTimer (targeted command)
	System.Router:Send(assetName, { target = "PlayTimer", command = "stop" })

	System.Debug:Message(assetName, "Paused game loop for wave transition")
end

-- Resume the game loop after wave transition
local function resumeGameLoop()
	if not gameRunning then return end

	-- Signal WaveController to resume spawning (uses static wiring)
	System.Router:Send(assetName, { action = "waveResumed" })

	-- Restart the play timer (targeted command)
	System.Router:Send(assetName, { target = "PlayTimer", command = "start" })

	System.Debug:Message(assetName, "Resumed game loop")
end

-- Stop the game loop completely
local function stopGameLoop()
	if not gameRunning then return end
	gameRunning = false

	-- Update Router context
	System.Router:SetContext("gameActive", false)

	-- Signal WaveController to stop spawning (uses static wiring)
	System.Router:Send(assetName, { action = "gameStopped" })

	-- Stop PlayTimer (targeted command)
	System.Router:Send(assetName, { target = "PlayTimer", command = "stop" })

	System.Debug:Message(assetName, "Stopped game loop")
end

-- Handle wave transition (PlayTimer expired but game continues)
local function onWaveTransition()
	System.Debug:Message(assetName, "Wave timer expired - transitioning to next wave")

	-- Pause spawning
	pauseGameLoop()

	-- Tell WaveController to advance wave (uses static wiring)
	System.Router:Send(assetName, { action = "advanceWave" })

	-- Brief pause for wave transition (could show UI here)
	task.delay(2, function()
		if gameRunning then
			-- Reset dispenser for new wave (targeted command)
			System.Router:Send(assetName, { target = "MarshmallowBag", command = "reset" })

			-- Resume with new wave
			resumeGameLoop()
		end
	end)
end

-- Per-submission handler (RoundComplete from Scoreboard)
-- Note: Individual TimedEvaluators auto-reset themselves after evaluation
local function onRoundComplete(result)
	if not gameRunning then return end

	-- Log the submission (each TimedEvaluator handles its own reset)
	System.Debug:Message(assetName, "Submission received from", result and result.assetName or "unknown")
end

-- End game and return all active players to standby
local function endGame(reason)
	if not gameRunning then return end

	System.Debug:Message(assetName, "Game ending:", reason)

	-- Stop the game loop first
	stopGameLoop()

	-- Transition all active players back to standby
	-- The transition system handles the visual flow (fade out, apply mode, fade in)
	for _, player in ipairs(game.Players:GetPlayers()) do
		if RunModes:IsGameActive(player) then
			System.Debug:Message(assetName, "Returning", player.Name, "to standby")
			RunModes:SetMode(player, RunModes.Modes.STANDBY)
		end
	end

	System.Debug:Message(assetName, "Game ended - players returned to standby")
end

-- Handle input messages
inputEvent.Event:Connect(function(message)
	if not message or type(message) ~= "table" then
		System.Debug:Warn(assetName, "Invalid input message:", message)
		return
	end

	local action = message.action

	-- Handle RunModes.ModeChanged (doesn't have action field, has player/newMode/oldMode)
	if not action and message.player and message.newMode then
		action = "modeChanged"
	end

	if action == "timerExpired" then
		-- Determine which timer expired based on game state
		if awaitingCountdown then
			-- CountdownTimer finished - unfreeze player, unlock prompts, start game
			awaitingCountdown = false
			if countdownPlayer then
				unfreezePlayer(countdownPlayer)
				popModal:Invoke(countdownPlayer, "countdown")
				System.Debug:Message(assetName, "Countdown complete - unfroze and unlocked", countdownPlayer.Name)
				countdownPlayer = nil
			end
			System.Debug:Message(assetName, "Countdown complete - starting game")
			startGameLoop()
		else
			-- PlayTimer expired - transition to next wave (game continues)
			onWaveTransition()
		end

	elseif action == "dispenserEmpty" then
		-- Dispenser (MarshmallowBag) is empty - end the game
		endGame("Dispenser empty")

	elseif action == "roundComplete" then
		-- Scoreboard round complete - reset evaluator
		onRoundComplete(message.result)

	elseif action == "modeChanged" then
		-- RunModes changed for a player
		local player = message.player
		local newMode = message.newMode
		local oldMode = message.oldMode

		System.Debug:Message(assetName, "Mode changed for", player.Name, ":", oldMode, "->", newMode)

		-- Store pending mode change and start transition
		pendingModeChange[player] = { newMode = newMode, oldMode = oldMode }
		Transition:Start(player, "fade", { class = "transition-fade" })

	else
		System.Debug:Warn(assetName, "Unknown action:", action)
	end
end)

--------------------------------------------------------------------------------
-- TRANSITION HANDLERS
--------------------------------------------------------------------------------

-- When screen is covered (black), apply mode changes while hidden
if transitionEvents.Covered then
	transitionEvents.Covered.Event:Connect(function(data)
		local player = data.player
		local pending = pendingModeChange[player]

		if not pending then
			System.Debug:Warn(assetName, "TransitionCovered but no pending mode change for", player.Name)
			Transition:Reveal(player)
			return
		end

		local newMode = pending.newMode

		System.Debug:Message(assetName, "Screen covered for", player.Name, "- applying mode:", newMode)

		-- Apply mode config to assets while screen is black
		applyModeToAssets(newMode)

		-- Mark that we need to start countdown when transition completes (if entering active mode)
		if RunModes:IsGameActive(player) and not gameRunning then
			awaitingCountdown = true
			System.Debug:Message(assetName, "Will start countdown after transition reveals")
		end

		-- Check if anyone is still in active mode
		if not RunModes:IsGameActive(player) then
			-- Player returning to standby - clear countdown state
			awaitingCountdown = false
			if countdownPlayer then
				popModal:Invoke(countdownPlayer, "countdown")
				countdownPlayer = nil
			end

			local anyActive = false
			for _, p in ipairs(game.Players:GetPlayers()) do
				if RunModes:IsGameActive(p) then
					anyActive = true
					break
				end
			end

			if not anyActive and gameRunning then
				stopGameLoop()
				-- Apply standby config since no one is playing
				applyModeToAssets(RunModes.Modes.STANDBY)
			end
		end

		-- Reveal the new scene
		Transition:Reveal(player)
	end)
end

-- When transition is complete, start countdown if needed
if transitionEvents.Complete then
	transitionEvents.Complete.Event:Connect(function(data)
		local player = data.player
		pendingModeChange[player] = nil

		-- Start countdown timer if we're entering active mode
		if awaitingCountdown then
			System.Debug:Message(assetName, "Transition complete - starting countdown for", player.Name)
			countdownPlayer = player
			-- Freeze player and lock prompts during countdown
			freezePlayer(player)
			pushModal:Invoke(player, "countdown")
			System.Router:Send(assetName, { target = "CountdownTimer", command = "start" })
		else
			System.Debug:Message(assetName, "Transition complete for", player.Name)
		end
	end)
end

-- Apply initial standby mode to all assets (game doesn't auto-start)
applyModeToAssets(RunModes.Modes.STANDBY)

System.Debug:Message(assetName, "Setup complete - listening on", assetName .. ".Input")

System.Debug:Message(assetName, "Script loaded")
