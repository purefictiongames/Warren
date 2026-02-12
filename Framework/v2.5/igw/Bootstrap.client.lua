--[[
    It Gets Worse — Client Bootstrap

    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    OVERVIEW
    ============================================================================

    This is the client entry point. It mirrors the server bootstrap but:
    - Uses Memory backend for Log (DataStore is server-only)
    - Only creates client-domain node instances
    - Runs in StarterPlayerScripts

    Nothing in the framework runs until this script explicitly calls it.

--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- Wait for Warren package and game modules
local Warren = require(ReplicatedStorage:WaitForChild("Warren"))
local Components = require(ReplicatedStorage:WaitForChild("Components"))
local Debug = Warren.System.Debug

--------------------------------------------------------------------------------
-- STUDIO CLI ACCESS
--------------------------------------------------------------------------------
-- Expose globals for command bar testing in Studio
-- These are stripped in production (non-Studio) builds

if RunService:IsStudio() then
    _G.Warren = Warren
    _G.Node = Warren.Node
    _G.Debug = Warren.System.Debug
    _G.Log = Warren.System.Log
    _G.IPC = Warren.System.IPC
    _G.State = Warren.System.State
    _G.View = Warren.System.View
end

--------------------------------------------------------------------------------
-- CONFIGURATION
--------------------------------------------------------------------------------

-- Configure debug output
Debug.configure({
    level = "info",  -- "error", "warn", "info", "trace"
})

-- Configure persistent logging (Memory only on client)
local Log = Warren.System.Log
Log.configure({
    backend = "Memory",  -- Always Memory on client (DataStore is server-only)
})

--------------------------------------------------------------------------------
-- BOOTSTRAP
--------------------------------------------------------------------------------

Debug.info("Bootstrap", "Warren v" .. Warren._VERSION)
Debug.info("Bootstrap", "Client starting...")

-- Initialize Log subsystem (generates session ID, starts auto-flush)
Log.init()

-- Initialize IPC subsystem
local IPC = Warren.System.IPC

--------------------------------------------------------------------------------
-- NODE REGISTRATION
--------------------------------------------------------------------------------
-- Register client-domain nodes and define modes here before IPC.init()

-- Register TitleScreen for initial title display
IPC.registerNode(Components.TitleScreen)

-- Register ExitScreen for pause/exit menu
IPC.registerNode(Components.ExitScreen)

-- Register ScreenTransition for screen fade effects during teleportation
IPC.registerNode(Components.ScreenTransition)

-- Register AreaHUD for area/room display
IPC.registerNode(Components.AreaHUD)

-- Register MiniMap for full-screen map view
IPC.registerNode(Components.MiniMap)

-- Register LobbyCountdown for lobby pad countdown UI
IPC.registerNode(Components.LobbyCountdown)

-- Also register server-side nodes for wiring resolution (they won't create instances)
IPC.registerNode(Components.JumpPad)
IPC.registerNode(Components.RegionManager)
IPC.registerNode(Components.LobbyManager)

--------------------------------------------------------------------------------
-- MODE DEFINITION
--------------------------------------------------------------------------------
-- Define same modes as server for cross-domain wiring to work

IPC.defineMode("Dungeon", {
    nodes = { "JumpPad", "RegionManager", "TitleScreen", "ExitScreen", "ScreenTransition", "AreaHUD", "MiniMap", "LobbyManager", "LobbyCountdown" },
    wiring = {
        JumpPad = { "RegionManager" },
        TitleScreen = { "RegionManager" },
        ExitScreen = { "RegionManager" },
        RegionManager = { "TitleScreen", "ExitScreen", "ScreenTransition", "AreaHUD", "MiniMap", "LobbyManager", "LobbyCountdown" },
        ScreenTransition = { "RegionManager" },
        MiniMap = { "RegionManager" },
        LobbyManager = { "LobbyCountdown" },
    },
})

--------------------------------------------------------------------------------
-- INSTANCE CREATION
--------------------------------------------------------------------------------

-- Resolve current Place context via PlaceGraph
local placeName = Components.PlaceGraph.resolve(game.PlaceId)

-- Only create TitleScreen on the start Place (not needed on gameplay server)
if placeName == "start" then
    IPC.createInstance("TitleScreen", { id = "TitleScreen_Local" })
end

-- Create ExitScreen instance (pause/exit menu)
IPC.createInstance("ExitScreen", { id = "ExitScreen_Local" })

-- Create ScreenTransition instance (one per client)
IPC.createInstance("ScreenTransition", { id = "ScreenTransition_Local" })

-- Create AreaHUD instance (displays current area/room)
IPC.createInstance("AreaHUD", { id = "AreaHUD_Local" })

-- Create MiniMap instance (full-screen map view)
IPC.createInstance("MiniMap", { id = "MiniMap_Local" })

-- Create LobbyCountdown instance (lobby pad countdown UI)
IPC.createInstance("LobbyCountdown", { id = "LobbyCountdown_Local" })

-- Initialize IPC (calls onInit on all registered client instances)
IPC.init()

-- Switch to Dungeon mode (must match server)
IPC.switchMode("Dungeon")

-- Start IPC (enables routing, calls onStart on all instances)
IPC.start()

-- TODO: Initialize other subsystems in order
-- Warren.System.State.init()
-- Warren.System.View.init()

--------------------------------------------------------------------------------
-- CLEANUP ON SHUTDOWN
--------------------------------------------------------------------------------
-- Ensure all nodes are properly stopped when the client disconnects.
-- This disconnects all RunService connections and cleans up state.

local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

-- Cleanup when local player is removed (game closing or leaving)
if LocalPlayer then
    LocalPlayer.AncestryChanged:Connect(function(_, parent)
        if not parent then
            Debug.info("Bootstrap", "Client shutting down...")
            Warren.System.stopAll()
            Debug.info("Bootstrap", "Client shutdown complete")
        end
    end)
end

-- Note: game:BindToClose is server-only. For client cleanup, rely on:
-- 1. LocalPlayer.AncestryChanged (fires when player leaves)
-- 2. Node's auto-cleanup when model is destroyed
-- 3. Manual Tests.stopAll() or System.stopAll() before running tests

Debug.info("Bootstrap", "Client ready")
