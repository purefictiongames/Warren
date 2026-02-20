--[[
    IGW v2 Pipeline — FeaturePlacer

    Computes AABB bounds for each feature DOM node and updates attributes.
    v1 is a pass-through for positions — future: adjacency constraints
    (lakes in valleys, rivers downhill, cliffs border something).

    Reads .feature DOM nodes from FeatureMap, computes feather distances,
    writes boundMinX/MaxX/MinZ/MaxZ + feather attributes.
--]]

return {
    name = "FeaturePlacer",
    domain = "server",

    Sys = {
        onInit = function(self) end,
        onStart = function(self) end,
        onStop = function(self) end,
    },

    In = {
        onPlaceFeatures = function(self, payload)
            local Dom = self._System.Dom

            local featherDefault = self:getAttribute("featherDefault") or 50
            local featherScale = self:getAttribute("featherScale") or 0.3

            -- Walk FeatureMap children
            local featureMap = nil
            if payload.dom and payload.dom.children then
                for _, child in ipairs(payload.dom.children) do
                    if child.props and child.props.Name == "FeatureMap" then
                        featureMap = child
                        break
                    end
                end
            end

            if not featureMap then
                warn("[FeaturePlacer] No FeatureMap in DOM")
                self.Out:Fire("nodeComplete", payload)
                return
            end

            local count = 0
            for _, node in ipairs(featureMap.children or {}) do
                local props = node.props
                if not props then continue end

                local cx = props.cx or 0
                local cz = props.cz or 0
                local baseWidth = props.baseWidth or 0
                local baseDepth = props.baseDepth or 0

                local maxExtent = math.max(baseWidth, baseDepth)
                local feather = math.max(featherDefault, maxExtent * featherScale)

                -- Compute AABB (estimate from base dimensions + feather)
                props.boundMinX = cx - baseWidth / 2 - feather
                props.boundMaxX = cx + baseWidth / 2 + feather
                props.boundMinZ = cz - baseDepth / 2 - feather
                props.boundMaxZ = cz + baseDepth / 2 + feather
                props.feather = feather

                count = count + 1
            end

            print(string.format(
                "[FeaturePlacer] Computed bounds for %d features",
                count
            ))

            self.Out:Fire("nodeComplete", payload)
        end,
    },
}
