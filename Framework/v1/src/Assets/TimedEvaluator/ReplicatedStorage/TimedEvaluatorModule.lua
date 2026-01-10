--[[
    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC

    This software, its architecture, and associated documentation are proprietary
    and confidential. All rights reserved.

    Unauthorized copying, modification, distribution, or use of this software,
    in whole or in part, is strictly prohibited without prior written permission.
--]]

-- TimedEvaluatorModule
-- Shared logic for initializing TimedEvaluator instances
-- Can be used at boot time or runtime for dynamic spawning

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TimedEvaluatorModule = {}

--[[
    Initialize a TimedEvaluator instance

    @param config {
        model: Model - The TimedEvaluator model to initialize
        assetName: string - Unique name for this instance
        inputEvent: BindableEvent - Event to receive commands
        System: table - Reference to System module (for Debug)
    }

    @return table - Controller with enable/disable/reset methods
]]
function TimedEvaluatorModule.initialize(config)
	local model = config.model
	local assetName = config.assetName
	local inputEvent = config.inputEvent
	local System = config.System

	-- Dependencies
	local Visibility = require(ReplicatedStorage:WaitForChild("System.Visibility"))
	local forceItemPickup = ReplicatedStorage:WaitForChild("Backpack.ForceItemPickup")

	-- Config from attributes (with validation)
	local acceptType = model:GetAttribute("AcceptType") or "Marshmallow"
	local evalTarget = model:GetAttribute("EvalTarget") or "ToastLevel"
	local countdown = model:GetAttribute("Countdown") or 30
	local timeoutBehavior = model:GetAttribute("TimeoutBehavior") or "reset" -- "reset" or "despawn"

	-- Validate target range
	local targetMin = model:GetAttribute("TargetMin")
	local targetMax = model:GetAttribute("TargetMax")
	if targetMin == nil or targetMin <= 0 then targetMin = 10 end
	if targetMax == nil or targetMax <= 0 then targetMax = 100 end
	if targetMin > targetMax then targetMin, targetMax = targetMax, targetMin end

	-- Resolve anchor (may be dedicated Anchor part or Humanoid body part like Head)
	local anchor, isBodyPart = Visibility.resolveAnchor(model)
	if not anchor then
		System.Debug:Warn(assetName, "No anchor resolved for", model.Name)
		return nil
	end
	System.Debug:Message(assetName, "Anchor resolved to", anchor.Name, isBodyPart and "(body part)" or "(dedicated)")

	-- Find Humanoid (if present)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		for _, desc in ipairs(model:GetDescendants()) do
			if desc:IsA("Humanoid") then
				humanoid = desc
				break
			end
		end
	end

	-- Ground the model so its bottom sits at ground level (Y=0 or configured)
	-- This ensures unanchored humanoid parts don't fall through the world
	local groundY = model:GetAttribute("GroundY") or 0
	local minY = math.huge
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			local bottomY = part.Position.Y - (part.Size.Y / 2)
			if bottomY < minY then
				minY = bottomY
			end
		end
	end
	if minY ~= math.huge then
		local offset = groundY - minY
		if math.abs(offset) > 0.01 then
			model:PivotTo(model:GetPivot() + Vector3.new(0, offset, 0))
			System.Debug:Message(assetName, "Grounded model by", offset, "studs")
		end
	end

	-- For Humanoids: stabilize on spawn to prevent falling over
	if humanoid then
		local rootPart = humanoid.RootPart
		if not rootPart then
			local humanoidModel = humanoid.Parent
			rootPart = humanoidModel:FindFirstChild("HumanoidRootPart")
				or humanoidModel:FindFirstChild("Torso")
		end

		if rootPart then
			-- Stabilize: anchor briefly, zero velocity, then release with forced standing state
			rootPart.Anchored = true
			rootPart.AssemblyLinearVelocity = Vector3.zero
			rootPart.AssemblyAngularVelocity = Vector3.zero

			task.delay(0.1, function()
				if not rootPart or not rootPart.Parent or not humanoid or not humanoid.Parent then
					return
				end

				rootPart.Anchored = false
				humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)

				task.delay(0.1, function()
					if humanoid and humanoid.Parent then
						humanoid:ChangeState(Enum.HumanoidStateType.Running)
					end
				end)

				System.Debug:Message(assetName, "Humanoid stabilized and standing")
			end)
		end
	end

	-- Bind non-humanoid parts to follow anchor using physics constraints
	-- (For Humanoids/body parts, bindToAnchor returns early - they handle their own physics)
	Visibility.bindToAnchor(model)

	-- Configure anchor based on whether it's a dedicated part or body part
	if isBodyPart then
		-- Body part anchor (e.g., Head): keep visible, ensure prompt works
		-- Don't anchor it - Humanoid controls its position
		anchor.CanTouch = true -- Allow interactions
	else
		-- Dedicated Anchor part: make invisible, non-collideable, anchored
		anchor.Anchored = true
		anchor.Transparency = 1
		anchor:SetAttribute("VisibleTransparency", 1)
		anchor.CanCollide = false
		anchor:SetAttribute("VisibleCanCollide", false)
		anchor.CanTouch = false
		anchor:SetAttribute("VisibleCanTouch", false)
	end

	-- Find or create ProximityPrompt on anchor
	local prompt = anchor:FindFirstChild("ProximityPrompt")
	if not prompt then
		System.Debug:Warn(assetName, "No ProximityPrompt found in Anchor")
		return nil
	end

	-- Find or create EvaluationComplete event
	local evaluationComplete = anchor:FindFirstChild("EvaluationComplete")
	if not evaluationComplete then
		evaluationComplete = Instance.new("BindableEvent")
		evaluationComplete.Name = "EvaluationComplete"
		evaluationComplete.Parent = anchor
	end

	-- Internal state
	local timerThread = nil
	local timerGeneration = 0
	local isRunning = false
	local hasEvaluated = false

	-- Create TimerTick event for satisfaction updates
	local timerTick = model:FindFirstChild("TimerTick")
	if not timerTick then
		timerTick = Instance.new("BindableEvent")
		timerTick.Name = "TimerTick"
		timerTick.Parent = model
	end

	-- Update satisfaction based on current state
	local function updateSatisfaction(state)
		local satisfaction = model:GetAttribute("Satisfaction") or 0
		local decay = state.deltaTime * 3
		satisfaction = math.max(0, satisfaction - decay)
		model:SetAttribute("Satisfaction", satisfaction)
	end

	-- Listen for timer ticks
	timerTick.Event:Connect(updateSatisfaction)

	-- Auto-reset delay (configurable via attribute)
	local autoResetDelay = model:GetAttribute("AutoResetDelay") or 3

	-- Forward declaration for reset (defined later)
	local reset

	-- Evaluate submitted item (or nil if timeout)
	local function evaluate(item, player)
		if hasEvaluated then return end
		hasEvaluated = true
		isRunning = false

		-- Stop timer if running
		if timerThread then
			pcall(function() task.cancel(timerThread) end)
			timerThread = nil
		end

		local targetValue = model:GetAttribute("TargetValue") or 0
		local submittedValue = nil
		local score = nil

		if item then
			submittedValue = item:GetAttribute(evalTarget) or 0
			score = math.abs(targetValue - submittedValue)
			System.Debug:Message(assetName, "Evaluated", item.Name, "- Submitted:", submittedValue, "Target:", targetValue, "Score:", score)
		else
			System.Debug:Message(assetName, "Time ran out! Target was:", targetValue)
		end

		-- Fire event with result
		local timeRemaining = model:GetAttribute("TimeRemaining") or 0
		local wasTimeout = item == nil

		evaluationComplete:Fire({
			submitted = item ~= nil,
			submittedValue = submittedValue,
			targetValue = targetValue,
			score = score,
			player = player,
			timeRemaining = timeRemaining,
			countdown = countdown,
			assetName = assetName,
			timedOut = wasTimeout,
		})

		-- Handle post-evaluation behavior based on timeoutBehavior setting
		if wasTimeout and timeoutBehavior == "despawn" then
			-- Timeout with despawn mode: hide and signal for removal
			System.Debug:Message(assetName, "Timeout - despawning (timeoutBehavior:", timeoutBehavior, ")")
			Visibility.hideModel(model)
			model:SetAttribute("IsEnabled", false)
			model:SetAttribute("HUDVisible", false)

			-- Fire despawn event so Dropper/WaveController know slot is free
			evaluationComplete:Fire({
				action = "camperDespawned",
				assetName = assetName,
				reason = "timeout",
			})
		else
			-- Normal mode or successful submission: auto-reset after delay
			task.delay(autoResetDelay, function()
				if model:GetAttribute("IsEnabled") then
					System.Debug:Message(assetName, "Auto-resetting after", autoResetDelay, "seconds")
					reset()
				end
			end)
		end
	end

	-- Start countdown timer
	local function startTimer()
		timerGeneration = timerGeneration + 1
		local myGeneration = timerGeneration

		timerThread = task.spawn(function()
			local timeRemaining = countdown
			model:SetAttribute("TimeRemaining", timeRemaining)

			while timeRemaining > 0 and isRunning and myGeneration == timerGeneration do
				local dt = task.wait(1)
				timeRemaining = timeRemaining - 1
				model:SetAttribute("TimeRemaining", timeRemaining)

				timerTick:Fire({
					deltaTime = dt,
					timeRemaining = timeRemaining,
					countdown = countdown,
				})
			end

			if isRunning and not hasEvaluated and myGeneration == timerGeneration then
				evaluate(nil, nil)
			end
		end)
	end

	-- Reset/init function (assigned to forward declaration)
	reset = function()
		if timerThread then
			pcall(function() task.cancel(timerThread) end)
			timerThread = nil
		end

		hasEvaluated = false
		isRunning = true

		local newTarget = math.random(targetMin, targetMax)
		model:SetAttribute("TargetValue", newTarget)
		model:SetAttribute("TimeRemaining", countdown)
		model:SetAttribute("Satisfaction", 100)

		System.Debug:Message(assetName, "Reset - TargetValue:", newTarget)

		startTimer()
	end

	-- Find marshmallow mounted on RoastingStick
	local function findMountedItem(player)
		local character = player.Character
		if not character then return nil end

		local stick = character:FindFirstChild("RoastingStick")
		if not stick then return nil end

		local mounted = stick:FindFirstChild(acceptType)
		if mounted and mounted:IsA("Tool") then
			return mounted
		end

		return nil
	end

	-- Unmount item from RoastingStick and move to backpack
	local function unmountToBackpack(player, item)
		local handle = item:FindFirstChild("Handle")
		if handle then
			local weld = handle:FindFirstChild("WeldConstraint")
			if weld then
				weld:Destroy()
			end
		end

		forceItemPickup:Fire({
			player = player,
			item = item,
		})
	end

	-- Find accepted item in player's inventory
	local function findAcceptedItem(player)
		local backpack = player:FindFirstChild("Backpack")
		if backpack then
			for _, child in ipairs(backpack:GetChildren()) do
				if child:IsA("Tool") and child.Name == acceptType then
					return child
				end
			end
		end

		local character = player.Character
		if character then
			for _, child in ipairs(character:GetChildren()) do
				if child:IsA("Tool") and child.Name == acceptType then
					return child
				end
			end
		end

		return nil
	end

	-- Handle player interaction
	prompt.Triggered:Connect(function(player)
		if not isRunning or hasEvaluated then
			System.Debug:Message(assetName, "Not accepting submissions")
			return
		end

		local mounted = findMountedItem(player)
		if mounted then
			System.Debug:Message(assetName, "Unmounting", mounted.Name, "from RoastingStick")
			unmountToBackpack(player, mounted)
			task.wait(0.1)
		end

		local item = findAcceptedItem(player)
		if not item then
			System.Debug:Message(assetName, "Player has no", acceptType)
			return
		end

		local itemToEvaluate = item
		item:Destroy()

		evaluate(itemToEvaluate, player)
	end)

	-- Command handlers
	local function handleReset()
		reset()
		return true
	end

	local function handleEnable()
		Visibility.showModel(model)
		prompt.Enabled = true
		model:SetAttribute("IsEnabled", true)
		model:SetAttribute("HUDVisible", true)
		System.Debug:Message(assetName, "Enabled")
		return true
	end

	local function handleDisable()
		if timerThread then
			pcall(function() task.cancel(timerThread) end)
			timerThread = nil
		end
		isRunning = false
		Visibility.hideModel(model)
		prompt.Enabled = false
		model:SetAttribute("IsEnabled", false)
		model:SetAttribute("HUDVisible", false)
		System.Debug:Message(assetName, "Disabled")
		return true
	end

	-- Listen on Input for commands
	if inputEvent then
		inputEvent.Event:Connect(function(message)
			if not message or type(message) ~= "table" then
				return
			end

			if message.command == "reset" then
				handleReset()
			elseif message.command == "enable" then
				handleEnable()
			elseif message.command == "disable" then
				handleDisable()
			end
		end)
	end

	-- Create BindableFunctions on model for direct access
	local resetFunction = Instance.new("BindableFunction")
	resetFunction.Name = "Reset"
	resetFunction.OnInvoke = handleReset
	resetFunction.Parent = model

	local enableFunction = Instance.new("BindableFunction")
	enableFunction.Name = "Enable"
	enableFunction.OnInvoke = handleEnable
	enableFunction.Parent = model

	local disableFunction = Instance.new("BindableFunction")
	disableFunction.Name = "Disable"
	disableFunction.OnInvoke = handleDisable
	disableFunction.Parent = model

	System.Debug:Message(assetName, "Initialized via module - AcceptType:", acceptType)

	-- Return controller for external access
	return {
		model = model,
		assetName = assetName,
		evaluationComplete = evaluationComplete,
		enable = handleEnable,
		disable = handleDisable,
		reset = handleReset,
	}
end

return TimedEvaluatorModule
