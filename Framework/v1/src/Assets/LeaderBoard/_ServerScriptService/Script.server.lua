-- LeaderBoard.Script (Server)
-- Tracks top 10 scores with DataStore persistence

-- Guard: Only run if this is the deployed version
if not script.Name:match("^LeaderBoard%.") then
	return
end

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")

-- Wait for boot system
local System = require(ReplicatedStorage:WaitForChild("System.System"))
System:WaitForStage(System.Stages.SCRIPTS)

-- Dependencies (guaranteed to exist after SCRIPTS stage)
local runtimeAssets = game.Workspace:WaitForChild("RuntimeAssets")
local model = runtimeAssets:WaitForChild("LeaderBoard")
local roundComplete = ReplicatedStorage:WaitForChild("Scoreboard.RoundComplete")
local timerExpired = ReplicatedStorage:WaitForChild("GlobalTimer.TimerExpired")
local dispenserEmpty = ReplicatedStorage:WaitForChild("Dispenser.Empty")

local DATASTORE_NAME = "LeaderBoard_v1"
local DATASTORE_KEY = "TopScores"

-- Find Billboard part with SurfaceGui
local billboard = model:FindFirstChild("Billboard")
if not billboard then
	System.Debug:Warn("LeaderBoard", "No Billboard part found")
	return
end

local surfaceGui = billboard:FindFirstChild("SurfaceGui")
if not surfaceGui then
	System.Debug:Warn("LeaderBoard", "No SurfaceGui found on Billboard")
	return
end

local textLabel = surfaceGui:FindFirstChild("TextLabel", true)
if not textLabel then
	System.Debug:Warn("LeaderBoard", "No TextLabel found in SurfaceGui")
	return
end

-- Size TextLabel to fill the SurfaceGui
textLabel.Size = UDim2.new(1, 0, 1, 0)
textLabel.Position = UDim2.new(0, 0, 0, 0)
textLabel.TextXAlignment = Enum.TextXAlignment.Left
textLabel.TextYAlignment = Enum.TextYAlignment.Top
textLabel.TextScaled = true
textLabel.BackgroundTransparency = 1

-- Score tracking
local scores = {}
local maxEntries = 10
local dataStore = nil

-- Try to get DataStore
local success, err = pcall(function()
	dataStore = DataStoreService:GetDataStore(DATASTORE_NAME)
end)

if not success then
	System.Debug:Warn("LeaderBoard", "DataStore unavailable -", err)
end

-- Load scores from DataStore
local function loadScores()
	if not dataStore then return end

	local success, data = pcall(function()
		return dataStore:GetAsync(DATASTORE_KEY)
	end)

	if success and data then
		scores = data
		System.Debug:Message("LeaderBoard", "Loaded", #scores, "scores from DataStore")
	elseif not success then
		System.Debug:Warn("LeaderBoard", "Failed to load scores -", data)
	end
end

-- Save scores to DataStore
local function saveScores()
	if not dataStore then return end

	local success, err = pcall(function()
		dataStore:SetAsync(DATASTORE_KEY, scores)
	end)

	if success then
		System.Debug:Message("LeaderBoard", "Saved scores to DataStore")
	else
		System.Debug:Warn("LeaderBoard", "Failed to save scores -", err)
	end
end

-- Update the display
local function updateDisplay()
	local lines = {}
	for i = 1, maxEntries do
		local rank = string.format("%2d.", i)
		if scores[i] then
			local name = scores[i].name
			if #name > 16 then
				name = string.sub(name, 1, 14) .. ".."
			end
			local score = tostring(scores[i].score)
			local padding = string.rep(" ", 18 - #name)
			table.insert(lines, rank .. " " .. name .. padding .. score)
		else
			table.insert(lines, rank .. " ---              ---")
		end
	end

	textLabel.Text = table.concat(lines, "\n")
end

-- Add score to leaderboard (maintains sorted top 10)
local function addScore(playerName, score)
	score = math.floor(score + 0.5)

	table.insert(scores, { name = playerName, score = score })

	table.sort(scores, function(a, b)
		return a.score > b.score
	end)

	while #scores > maxEntries do
		table.remove(scores)
	end

	updateDisplay()
	saveScores()
	System.Debug:Message("LeaderBoard", "Added score for", playerName, "-", score)
end

-- Track current round scores
local currentRoundScores = {}

-- Listen for per-marshmallow score updates
roundComplete.Event:Connect(function(result)
	local player = result.player
	if not player then return end

	currentRoundScores[player.Name] = result.totalScore or 0
end)

-- Post scores to leaderboard when timed round ends
local function onRoundEnd()
	for playerName, totalScore in pairs(currentRoundScores) do
		if totalScore > 0 then
			if #scores < maxEntries or totalScore > scores[#scores].score then
				addScore(playerName, totalScore)
			end
		end
	end

	currentRoundScores = {}
	System.Debug:Message("LeaderBoard", "Round ended - scores posted")
end

-- Listen for round end triggers
timerExpired.Event:Connect(onRoundEnd)
dispenserEmpty.Event:Connect(onRoundEnd)

-- Load existing scores and display
loadScores()
updateDisplay()

System.Debug:Message("LeaderBoard", "Setup complete")

System.Debug:Message("LeaderBoard", "Script loaded")
