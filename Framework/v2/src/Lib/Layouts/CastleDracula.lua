--[[
    Castle Dracula - Master Layout

    Composes all floors of the dungeon escape map.
    10 floors total (L0-L9), built incrementally.

    Floor Heights:
        L0: Y=0 (Grotto/Crypt)
        L1: Y=70 (Lower Castle/Guard Quarters)
        L2: Y=160 (Inner Castle/Galleries/Library/Grand Hall)
        L3: Y=280 (Inner Keep/Clockwork/Defenses)
        L4: Y=400 (Outer Walls/Battlements/Sentry Loop)

    Coordinate System:
        Origin (0,0,0) at southwest corner, L0 ground level
        +X = East, +Z = North, +Y = Up
--]]

--------------------------------------------------------------------------------
-- FLOOR LAYOUTS
--------------------------------------------------------------------------------

local L0_BaseShell = require(script.Parent.CastleDracula_L0_BaseShell)
local L0_Openings = require(script.Parent.CastleDracula_L0_Openings)
local L1_BaseShell = require(script.Parent.CastleDracula_L1_BaseShell)
local L1_Openings = require(script.Parent.CastleDracula_L1_Openings)
local L2_BaseShell = require(script.Parent.CastleDracula_L2_BaseShell)
local L2_Openings = require(script.Parent.CastleDracula_L2_Openings)
local L3_BaseShell = require(script.Parent.CastleDracula_L3_BaseShell)
local L3_Openings = require(script.Parent.CastleDracula_L3_Openings)
local L4_BaseShell = require(script.Parent.CastleDracula_L4_BaseShell)
local L4_Openings = require(script.Parent.CastleDracula_L4_Openings)
-- ... (future floors)

--------------------------------------------------------------------------------
-- LAYOUT
--------------------------------------------------------------------------------

return {
    name = "CastleDracula",
    spec = {
        origin = "corner",

        parts = {
            -- Level 0: Grotto / Crypt (Y=0)
            { id = "L0",
              xref = L0_BaseShell,
              position = {0, 0, 0} },

            { id = "L0_Openings",
              xref = L0_Openings,
              position = {0, 0, 0} },

            -- Level 1: Lower Castle / Guard Quarters (Y=70)
            { id = "L1",
              xref = L1_BaseShell,
              position = {0, 0, 0} },

            { id = "L1_Openings",
              xref = L1_Openings,
              position = {0, 0, 0} },

            -- Level 2: Inner Castle / Galleries / Library / Grand Hall (Y=160)
            { id = "L2",
              xref = L2_BaseShell,
              position = {0, 0, 0} },

            { id = "L2_Openings",
              xref = L2_Openings,
              position = {0, 0, 0} },

            -- Level 3: Inner Keep / Clockwork / Defenses (Y=280)
            { id = "L3",
              xref = L3_BaseShell,
              position = {0, 0, 0} },

            { id = "L3_Openings",
              xref = L3_Openings,
              position = {0, 0, 0} },

            -- Level 4: Outer Walls / Battlements / Sentry Loop (Y=400)
            { id = "L4",
              xref = L4_BaseShell,
              position = {0, 0, 0} },

            { id = "L4_Openings",
              xref = L4_Openings,
              position = {0, 0, 0} },

            -- Future floors will be added here
        },
    },
}
