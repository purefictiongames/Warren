-- TimedEvaluator.Script (Server)
-- Timed evaluation system - accepts items and compares against target value

-- Guard: Only run if this is the deployed version
if not script.Name:match("^TimedEvaluator%.") then
	return
end

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Wait for boot system
local System = require(ReplicatedStorage:WaitForChild("System.System"))
System:WaitForStage(System.Stages.SCRIPTS)

-- Dependencies (guaranteed to exist after SCRIPTS stage)
local forceItemPickup = ReplicatedStorage:WaitForChild("Backpack.ForceItemPickup")
local runtimeAssets = game.Workspace:WaitForChild("RuntimeAssets")
local model = runtimeAssets:WaitForChild("TimedEvaluator")

-- Config from attributes (with validation)
local acceptType = model:GetAttribute("AcceptType") or "Marshmallow"
local evalTarget = model:GetAttribute("EvalTarget") or "ToastLevel"
local countdown = model:GetAttribute("Countdown") or 30

-- Validate target range
local targetMin = model:GetAttribute("TargetMin")
local targetMax = model:GetAttribute("TargetMax")
if targetMin == nil or targetMin <= 0 then targetMin = 10 end
if targetMax == nil or targetMax <= 0 then targetMax = 100 end
if targetMin > targetMax then targetMin, targetMax = targetMax, targetMin end

-- Find components
local anchor = model:FindFirstChild("Anchor")
if not anchor then
	warn("TimedEvaluator: No Anchor found in", model.Name)
	return
end

local prompt = anchor:FindFirstChild("ProximityPrompt")
if not prompt then
	warn("TimedEvaluator: No ProximityPrompt found in Anchor")
	return
end

local evaluationComplete = anchor:FindFirstChild("EvaluationComplete")
if not evaluationComplete then
	warn("TimedEvaluator: No EvaluationComplete event found in Anchor")
	return
end

-- Internal state
local timerThread = nil
local timerGeneration = 0
local isRunning = false
local hasEvaluated = false

-- Create TimerTick event for satisfaction updates
local timerTick = Instance.new("BindableEvent")
timerTick.Name = "TimerTick"
timerTick.Parent = model

-- Update satisfaction based on current state
local function updateSatisfaction(state)
	local satisfaction = model:GetAttribute("Satisfaction") or 0
	local decay = state.deltaTime * 3
	satisfaction = math.max(0, satisfaction - decay)
	model:SetAttribute("Satisfaction", satisfaction)
	print("TimedEvaluator: Satisfaction updated to", math.floor(satisfaction))
end

-- Listen for timer ticks
timerTick.Event:Connect(updateSatisfaction)

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
		print("TimedEvaluator: Evaluated", item.Name, "- Submitted:", submittedValue, "Target:", targetValue, "Score:", score)
	else
		print("TimedEvaluator: Time ran out! Target was:", targetValue)
	end

	-- Fire event with result
	local timeRemaining = model:GetAttribute("TimeRemaining") or 0
	evaluationComplete:Fire({
		submitted = item ~= nil,
		submittedValue = submittedValue,
		targetValue = targetValue,
		score = score,
		player = player,
		timeRemaining = timeRemaining,
		countdown = countdown,
	})
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

-- Reset/init function
local function reset()
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

	print("TimedEvaluator: Reset - TargetValue:", newTarget, "(range:", targetMin, "-", targetMax, ") Countdown:", countdown)

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
		print("TimedEvaluator: Not accepting submissions")
		return
	end

	local mounted = findMountedItem(player)
	if mounted then
		print("TimedEvaluator: Unmounting", mounted.Name, "from RoastingStick")
		unmountToBackpack(player, mounted)
		task.wait(0.1)
	end

	local item = findAcceptedItem(player)
	if not item then
		print("TimedEvaluator: Player has no", acceptType)
		return
	end

	local itemToEvaluate = item
	item:Destroy()

	evaluate(itemToEvaluate, player)
end)

-- Expose reset via BindableFunction (for orchestrator)
local resetFunction = Instance.new("BindableFunction")
resetFunction.Name = "Reset"
resetFunction.OnInvoke = function()
	reset()
	return true
end
resetFunction.Parent = model

-- Initial reset on load
reset()

print("TimedEvaluator: Setup complete - AcceptType:", acceptType, "EvalTarget:", evalTarget)

print("TimedEvaluator.Script loaded")
