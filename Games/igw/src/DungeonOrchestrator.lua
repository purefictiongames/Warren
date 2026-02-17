--[[
    IGW v2 — DungeonOrchestrator
    Top-level game node. Owns dungeon lifecycle.

    On start: applies lighting, sets up style resolver, creates DOM root,
    fires buildPass into the pipeline.

    Receives buildComplete when pipeline finishes.
--]]

return {
    name = "DungeonOrchestrator",
    domain = "server",

    Sys = {
        onInit = function(self)
            self._config = self:getAttribute("config") or {}
        end,

        onStart = function(self)
            local Debug = self._System and self._System.Debug
            local Dom = self._System.Dom
            local StyleBridge = self._System.StyleBridge
            local Styles = self._System.Styles
            local ClassResolver = self._System.ClassResolver
            local config = self._config

            -- Apply lighting
            local lc = config.lighting
            if lc then
                local Lighting = game:GetService("Lighting")
                Lighting.ClockTime = lc.ClockTime or 0
                Lighting.Brightness = lc.Brightness or 0
                Lighting.OutdoorAmbient = Color3.fromRGB(
                    lc.OutdoorAmbient[1] or 0,
                    lc.OutdoorAmbient[2] or 0,
                    lc.OutdoorAmbient[3] or 0
                )
                Lighting.Ambient = Color3.fromRGB(
                    lc.Ambient[1] or 20,
                    lc.Ambient[2] or 20,
                    lc.Ambient[3] or 25
                )
                Lighting.FogEnd = lc.FogEnd or 1000
                Lighting.FogColor = Color3.fromRGB(
                    lc.FogColor[1] or 0,
                    lc.FogColor[2] or 0,
                    lc.FogColor[3] or 0
                )
                Lighting.GlobalShadows = lc.GlobalShadows or false
            end

            -- Set up style resolver
            local resolver = StyleBridge.createResolver(Styles, ClassResolver)
            Dom.setStyleResolver(resolver)

            -- Build dungeon
            local seed = (os.time() + math.random(1, 9999))
            local regionNum = 1
            local paletteClass = StyleBridge.getPaletteClass(regionNum)

            if Debug then
                Debug.info("DungeonOrchestrator", "Seed:", seed, "Palette:", paletteClass)
            end

            -- Create DOM root
            local root = Dom.createElement("Model", {
                Name = "Region_" .. regionNum,
            })

            -- Defer buildPass so IPC.start() finishes setting isStarted = true
            -- before we attempt to route signals through the pipeline
            local selfRef = self
            task.defer(function()
                selfRef.Out:Fire("buildPass", {
                    dom = root,
                    seed = seed,
                    regionNum = regionNum,
                    paletteClass = paletteClass,
                })
            end)
        end,

        onStop = function(self)
            -- Cleanup: destroy container if it exists
            if self._container and self._container.Parent then
                self._container:Destroy()
            end
        end,
    },

    In = {
        onBuildComplete = function(self, payload)
            local Debug = self._System and self._System.Debug
            self._container = payload.container
            if Debug then
                Debug.info("DungeonOrchestrator", "Build complete.",
                    "Rooms:", payload.roomCount or "?",
                    "Doors:", payload.doorCount or "?")
            end
        end,
    },
}
