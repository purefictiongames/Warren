--[[
    IGW v2 Pipeline — Materializer
    Mounts the DOM tree into workspace, creating live Roblox Instances.
    Cleans up existing SpawnLocations before mounting.
--]]

return {
    name = "Materializer",
    domain = "server",

    Sys = {
        onInit = function(self) end,
        onStart = function(self) end,
        onStop = function(self) end,
    },

    In = {
        onMount = function(self, payload)
            local t0 = os.clock()
            local Dom = self._System.Dom

            -- Remove existing dungeon SpawnLocations from workspace
            for _, child in ipairs(workspace:GetChildren()) do
                if child:IsA("SpawnLocation") and child.Name:match("^Spawn_Region") then
                    child:Destroy()
                end
            end

            -- Mount the entire DOM tree into workspace
            Dom.mount(payload.dom, workspace)

            -- Store the container Instance for downstream nodes
            payload.container = payload.dom._instance

            print(string.format("[Materializer] DOM mounted (%.2fs)", os.clock() - t0))

            self.Out:Fire("nodeComplete", payload)
        end,
    },
}
