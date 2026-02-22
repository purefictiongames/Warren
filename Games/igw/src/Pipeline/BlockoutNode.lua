--[[
    IGW v2 Pipeline — BlockoutNode (Subtractive Terrain)

    Blockout visualization — creates colored, semi-transparent box Parts
    showing feature volumes along spline paths. Controlled by the
    `showBlockout` attribute (skip Part creation when false).

    Color key:
        Grey (140,140,140)     — ridge crest (main_spine)
        Light grey (180,180,180) — sub_ridge
        Blue (80,120,200)      — glacial valley
        Light blue (120,160,220) — fluvial valley
        Red (200,60,60)        — stratovolcano
        Yellow (220,200,80)    — pass
        Cyan (80,200,200)      — cirque
        Orange (220,140,60)    — cinder cone

    Signal: onBuildBlockout(payload) → fires nodeComplete
--]]

local SPLINE_COLORS = {
    main_spine    = Color3.fromRGB(140, 140, 140),
    sub_ridge     = Color3.fromRGB(180, 180, 180),
    glacial_valley = Color3.fromRGB(80, 120, 200),
    fluvial_valley = Color3.fromRGB(120, 160, 220),
}

local FEATURE_COLORS = {
    stratovolcano = Color3.fromRGB(200, 60, 60),
    pass          = Color3.fromRGB(220, 200, 80),
    cirque        = Color3.fromRGB(80, 200, 200),
    cinder_cone   = Color3.fromRGB(220, 140, 60),
}

return {
    name = "BlockoutNode",
    domain = "server",

    Sys = {
        onInit = function(self) end,
        onStart = function(self) end,
        onStop = function(self) end,
    },

    In = {
        onBuildBlockout = function(self, payload)
            local Dom = self._System.Dom
            local showBlockout = self:getAttribute("showBlockout")
            if showBlockout == nil then showBlockout = true end
            local groundY = self:getAttribute("groundY") or 0

            local splines = payload.splines or {}
            local biomeConfig = payload.biomeConfig or {}
            local featureDefs = biomeConfig.features or {}
            local baseElev = biomeConfig.baseElevation or {}
            local crestHeight = baseElev.crestHeight or 350
            local edgeHeight = baseElev.edgeHeight or 40

            local blockoutFolder = Dom.createElement("Folder", {
                Name = "Blockout",
            })
            Dom.appendChild(payload.dom, blockoutFolder)

            local partCount = 0
            local featurePartCount = 0

            if not showBlockout then
                print("[BlockoutNode] showBlockout = false, skipping Part creation")
                self.Out:Fire("nodeComplete", payload)
                return
            end

            ----------------------------------------------------------------
            -- Create segment boxes along each spline
            ----------------------------------------------------------------

            for si, spline in ipairs(splines) do
                local cps = spline.controlPoints
                local color = SPLINE_COLORS[spline.subclass]
                    or SPLINE_COLORS[spline.class]
                    or Color3.fromRGB(160, 160, 160)

                local isValley = (spline.class == "valley")

                -- Segment boxes between consecutive CPs
                for ci = 1, #cps - 1 do
                    local cpA = cps[ci]
                    local cpB = cps[ci + 1]

                    -- Segment midpoint and length
                    local midX = (cpA.x + cpB.x) / 2
                    local midZ = (cpA.z + cpB.z) / 2
                    local dx = cpB.x - cpA.x
                    local dz = cpB.z - cpA.z
                    local segLen = math.sqrt(dx * dx + dz * dz)
                    if segLen < 1 then continue end

                    -- Rotation to align box along segment direction
                    local angle = math.atan2(dz, dx)

                    -- Average width and elevation/depth at midpoint
                    local avgWidth = ((cpA.width or 100) + (cpB.width or 100)) / 2

                    local boxH, boxY
                    if isValley then
                        local avgDepth = ((cpA.depth or 50) + (cpB.depth or 50)) / 2
                        -- Valley boxes sit below the base elevation
                        local avgElev = (cpA.elevation + cpB.elevation) / 2
                        boxH = avgDepth
                        boxY = groundY + avgElev - avgDepth / 2
                    else
                        local avgElev = (cpA.elevation + cpB.elevation) / 2
                        boxH = avgElev
                        boxY = groundY + avgElev / 2
                    end

                    if boxH < 1 then continue end

                    local part = Dom.createElement("Part", {
                        Name = string.format("Seg_%d_%d", si, ci),
                        Size = Vector3.new(segLen, boxH, avgWidth),
                        CFrame = CFrame.new(midX, boxY, midZ)
                            * CFrame.Angles(0, -angle, 0),
                        Color = color,
                        Anchored = true,
                        Transparency = 0.4,
                        CanCollide = false,
                    })
                    Dom.appendChild(blockoutFolder, part)
                    partCount = partCount + 1
                end

                ----------------------------------------------------------------
                -- Point feature boxes at tagged CPs
                ----------------------------------------------------------------

                for ci, cp in ipairs(cps) do
                    if not cp.featureClass then continue end

                    local featColor = FEATURE_COLORS[cp.featureClass]
                        or Color3.fromRGB(200, 200, 200)

                    local def = featureDefs[cp.featureClass] or {}
                    local featW, featH

                    if cp.featureClass == "stratovolcano" then
                        featW = (def.baseRadius and def.baseRadius[2] or 500) * 2
                        featH = cp.elevation or 300
                    elseif cp.featureClass == "cinder_cone" then
                        featW = (def.baseRadius and def.baseRadius[2] or 100) * 2
                        featH = def.height and def.height[2] or 80
                    elseif cp.featureClass == "cirque" then
                        featW = def.diameter and def.diameter[2] or 350
                        featH = def.depth and def.depth[2] or 120
                    elseif cp.featureClass == "pass" then
                        featW = cp.width or (def.width and def.width[2] or 300)
                        featH = def.depth and def.depth[2] or 120
                    else
                        featW = 100
                        featH = 100
                    end

                    -- Position: additive features rise above ground,
                    -- subtractive (cirque, pass) sit below ridge crest
                    local featY
                    local isSubtractive = (cp.featureClass == "cirque"
                        or cp.featureClass == "pass")
                    if isSubtractive then
                        featY = groundY + (cp.elevation or crestHeight * 0.5) - featH / 2
                    else
                        featY = groundY + featH / 2
                    end

                    local part = Dom.createElement("Part", {
                        Name = string.format("Feat_%s_%d_%d", cp.featureClass, si, ci),
                        Size = Vector3.new(featW, featH, featW),
                        CFrame = CFrame.new(cp.x, featY, cp.z),
                        Color = featColor,
                        Anchored = true,
                        Transparency = 0.3,
                        CanCollide = false,
                        Shape = Enum.PartType.Block,
                    })
                    Dom.appendChild(blockoutFolder, part)
                    featurePartCount = featurePartCount + 1
                end
            end

            print(string.format(
                "[BlockoutNode] %d segment boxes, %d feature boxes (%d splines)",
                partCount, featurePartCount, #splines
            ))

            self.Out:Fire("nodeComplete", payload)
        end,
    },
}
