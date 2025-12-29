-- System.ModuleScript (Shared)
-- Central module providing boot stage constants and wait helpers
-- Scripts can optionally use this to wait for stages, or continue using WaitForChild

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local System = {
	-- Boot stages (in order)
	Stages = {
		SYNC    = 1,  -- Assets cloned to RuntimeAssets, folders extracted
		EVENTS  = 2,  -- All BindableEvents/RemoteEvents created and registered
		MODULES = 3,  -- ModuleScripts deployed and requireable
		SCRIPTS = 4,  -- Server scripts can run
		READY   = 5,  -- Full boot complete, clients can interact
	},

	-- Internal state
	_currentStage = 0,
	_stageEvent = nil,  -- BindableEvent for stage transitions
	_isClient = RunService:IsClient(),
}

-- Initialize event reference (called lazily on first use)
function System:_ensureEvent()
	if self._stageEvent then
		return
	end

	-- Wait for the boot stage event to be deployed
	self._stageEvent = ReplicatedStorage:WaitForChild("System.BootStage", 30)

	if not self._stageEvent then
		warn("System: BootStage event not found, boot system may not be initialized")
	end
end

-- Wait for a specific boot stage to be reached
-- Yields the calling thread until the stage is reached
function System:WaitForStage(stage)
	self:_ensureEvent()

	-- If already at or past the requested stage, return immediately
	if self._currentStage >= stage then
		return
	end

	-- Wait for stage transitions until we reach the requested stage
	while self._currentStage < stage do
		if self._stageEvent then
			self._stageEvent.Event:Wait()
		else
			-- Fallback: poll if event not available
			task.wait(0.1)
		end
	end
end

-- Get the current boot stage
function System:GetCurrentStage()
	return self._currentStage
end

-- Get the name of a stage for debugging
function System:GetStageName(stage)
	for name, value in pairs(self.Stages) do
		if value == stage then
			return name
		end
	end
	return "UNKNOWN"
end

-- Check if a stage has been reached (non-blocking)
function System:IsStageReached(stage)
	return self._currentStage >= stage
end

-- Internal: Set the current stage (called by System.Script on server)
function System:_setStage(stage)
	self._currentStage = stage
	print("System: Stage", self:GetStageName(stage), "(" .. stage .. ")")

	if self._stageEvent then
		self._stageEvent:Fire(stage)
	end
end

-- Internal: Update stage from client ping-pong response
function System:_updateFromServer(stage)
	if stage > self._currentStage then
		self._currentStage = stage

		-- Fire event to wake up any waiting client scripts
		if self._stageEvent then
			self._stageEvent:Fire(stage)
		end
	end
end

return System
