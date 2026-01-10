--[[
    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC

    This software, its architecture, and associated documentation are proprietary
    and confidential. All rights reserved.

    Unauthorized copying, modification, distribution, or use of this software,
    in whole or in part, is strictly prohibited without prior written permission.
--]]

-- System.Router
-- Central message routing with filtering capabilities
--
-- Like a network router/firewall:
--   - Routes messages to targets based on message.target field
--   - Filters messages based on rules (source, target, command, context)
--   - Falls back to static wiring for non-targeted messages
--
-- Usage:
--   Router:Send(source, message) -- Route a message
--   Router:SetContext(key, value) -- Set context for filtering
--   Router:AddRule(rule) -- Add a filtering rule

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Router = {
	-- Filtering rules
	rules = {},

	-- Current context (e.g., { gameActive = true, currentWave = 1 })
	context = {},

	-- Static wiring fallbacks (populated from GameManifest)
	staticWiring = {},

	-- Debug reference (set during init)
	Debug = nil,
}

--[[
    Initialize the Router
    Called by System bootstrap

    @param config {
        Debug: table - Debug module reference
        wiring: table - Static wiring from GameManifest
    }
]]
function Router:Init(config)
	self.Debug = config.Debug

	-- Build static wiring lookup
	-- Format: staticWiring[source] = { target1, target2, ... }
	if config.wiring then
		for _, wire in ipairs(config.wiring) do
			local source = wire.from
			local target = wire.to

			if not self.staticWiring[source] then
				self.staticWiring[source] = {}
			end
			table.insert(self.staticWiring[source], target)
		end
	end

	if self.Debug then
		self.Debug:Message("Router", "Initialized with", #(config.wiring or {}), "static wires")
	end
end

--[[
    Send a message through the router

    @param source: string - Source asset name (e.g., "Orchestrator")
    @param message: table - Message to route
    @return boolean - Whether message was delivered
]]
function Router:Send(source, message)
	if not message or type(message) ~= "table" then
		if self.Debug then
			self.Debug:Warn("Router", "Invalid message from", source)
		end
		return false
	end

	-- Targeted message - route to specific target
	if message.target then
		return self:_routeTargeted(source, message.target, message)
	end

	-- Non-targeted message - use static wiring
	return self:_routeStatic(source, message)
end

--[[
    Route a targeted message to a specific asset

    @param source: string - Source asset name
    @param target: string - Target asset name
    @param message: table - Message to deliver
    @return boolean - Whether message was delivered
]]
function Router:_routeTargeted(source, target, message)
	-- Check filtering rules
	local allowed, reason = self:_checkRules(source, target, message)
	if not allowed then
		if self.Debug then
			self.Debug:Warn("Router", "Blocked:", source, "->", target,
				"command:", message.command or message.action or "?",
				"reason:", reason)
		end
		return false
	end

	-- Find target's Input event
	local targetInput = ReplicatedStorage:FindFirstChild(target .. ".Input")
	if not targetInput then
		if self.Debug then
			self.Debug:Warn("Router", "Target not found:", target .. ".Input")
		end
		return false
	end

	-- Deliver message
	targetInput:Fire(message)

	if self.Debug then
		self.Debug:Message("Router", source, "->", target,
			"[" .. (message.command or message.action or "msg") .. "]")
	end

	return true
end

--[[
    Route a non-targeted message via static wiring

    @param source: string - Source asset name
    @param message: table - Message to deliver
    @return boolean - Whether any message was delivered
]]
function Router:_routeStatic(source, message)
	local sourceKey = source .. ".Output"
	local targets = self.staticWiring[sourceKey]

	if not targets or #targets == 0 then
		if self.Debug then
			self.Debug:Warn("Router", "No static wiring for:", sourceKey)
		end
		return false
	end

	local delivered = false
	for _, targetKey in ipairs(targets) do
		-- Extract target name from "Target.Input" format
		local targetName = targetKey:match("^(.+)%.Input$")
		if targetName then
			-- Check filtering rules (use source as "target" for action-based rules)
			local allowed, reason = self:_checkRules(source, targetName, message)
			if allowed then
				local targetInput = ReplicatedStorage:FindFirstChild(targetKey)
				if targetInput then
					targetInput:Fire(message)
					delivered = true

					if self.Debug then
						self.Debug:Message("Router", source, "->", targetName,
							"[" .. (message.action or "msg") .. "] (static)")
					end
				end
			else
				if self.Debug then
					self.Debug:Warn("Router", "Static blocked:", source, "->", targetName, "reason:", reason)
				end
			end
		end
	end

	return delivered
end

--[[
    Check if a message passes filtering rules

    @param source: string - Source asset name
    @param target: string - Target asset name
    @param message: table - Message to check
    @return boolean, string - (allowed, reason if denied)
]]
function Router:_checkRules(source, target, message)
	for _, rule in ipairs(self.rules) do
		local matches, reason = self:_ruleMatches(rule, source, target, message)
		if matches then
			if rule.deny then
				return false, reason or rule.name or "rule denied"
			end
			-- If rule matches and allows, continue checking (explicit allow)
		end
	end

	-- Default: allow
	return true, nil
end

--[[
    Check if a rule matches the current message

    @param rule: table - Rule definition
    @param source: string - Source asset name
    @param target: string - Target asset name
    @param message: table - Message to check
    @return boolean, string - (matches, match reason)
]]
function Router:_ruleMatches(rule, source, target, message)
	-- Check source filter
	if rule.sources then
		local sourceMatch = false
		for _, s in ipairs(rule.sources) do
			if s == source or s == "*" then
				sourceMatch = true
				break
			end
		end
		if not sourceMatch then
			return false
		end
	end

	-- Check target filter
	if rule.targets then
		local targetMatch = false
		for _, t in ipairs(rule.targets) do
			if t == target or t == "*" then
				targetMatch = true
				break
			end
		end
		if not targetMatch then
			return false
		end
	end

	-- Check command filter
	if rule.commands then
		local cmd = message.command or message.action
		local cmdMatch = false
		for _, c in ipairs(rule.commands) do
			if c == cmd or c == "*" then
				cmdMatch = true
				break
			end
		end
		if not cmdMatch then
			return false
		end
	end

	-- Check context requirements
	if rule.requireContext then
		for key, value in pairs(rule.requireContext) do
			if self.context[key] ~= value then
				return false, "context:" .. key
			end
		end
	end

	-- All filters matched
	return true, rule.name
end

--[[
    Add a filtering rule

    Rule format:
    {
        name = "rule name" (optional, for debugging),
        sources = { "Orchestrator", "WaveController" } (optional, defaults to all),
        targets = { "CampPlacer" } (optional, defaults to all),
        commands = { "enable", "disable" } (optional, defaults to all),
        requireContext = { gameActive = true } (optional),
        deny = true (if true, matching messages are blocked; if false/nil, allowed)
    }

    @param rule: table - Rule definition
]]
function Router:AddRule(rule)
	table.insert(self.rules, rule)

	if self.Debug then
		self.Debug:Message("Router", "Added rule:", rule.name or "#" .. #self.rules)
	end
end

--[[
    Set a context value for filtering

    @param key: string - Context key
    @param value: any - Context value
]]
function Router:SetContext(key, value)
	self.context[key] = value

	if self.Debug then
		self.Debug:Message("Router", "Context:", key, "=", tostring(value))
	end
end

--[[
    Get current context

    @return table - Current context
]]
function Router:GetContext()
	return self.context
end

--[[
    Clear all rules
]]
function Router:ClearRules()
	self.rules = {}
end

return Router
