> **Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC**
>
> This software, its architecture, and associated documentation are proprietary
> and confidential. All rights reserved.
>
> Unauthorized copying, modification, distribution, or use of this software,
> in whole or in part, is strictly prohibited without prior written permission.

---

# Unified Styling System - Comprehensive Guide

**Version:** 2.0
**Last Updated:** January 8, 2026
**Audience:** Developers working with Warren Framework

---

# Table of Contents

1. [Overview](#1-overview)
2. [Philosophy & Design](#2-philosophy--design)
3. [Architecture](#3-architecture)
4. [GUI Styling](#4-gui-styling)
5. [Asset Styling](#5-asset-styling)
6. [Practical Recipes](#6-practical-recipes)
7. [Troubleshooting](#7-troubleshooting)
8. [Advanced Techniques](#8-advanced-techniques)
9. [Migration Guide](#9-migration-guide)
10. [Quick Reference](#10-quick-reference)

---

# 1. Overview

## 1.1 What is the Unified Styling System?

The styling system provides a **single declarative language** for styling both GUI elements and 3D assets in your Roblox game. Instead of writing imperative code to position, style, and transform objects, you define their appearance and placement in a central configuration file (`Styles.lua`), then apply those styles via simple API calls.

**Key Benefits:**
- **Consistency**: One language for all visual styling
- **Maintainability**: Change styles in one place, affects everything
- **Discoverability**: Visual behavior visible without reading code
- **Iteration Speed**: Tweak positioning without redeploying scripts
- **Separation of Concerns**: Logic separate from presentation

## 1.2 What Can Be Styled?

### GUI Elements
- Text labels, buttons, frames, images
- Positions, sizes, colors, fonts
- Layout modifiers (corners, strokes, padding)
- Responsive breakpoints

### 3D Assets
- Models, BaseParts, Attachments
- Position, rotation, scale
- Transform composition
- Declarative placement

## 1.3 Quick Example

```lua
-- In Styles.lua
classes = {
    ["hud-text"] = {
        textSize = 24,
        textColor = {255, 170, 0},
        font = "GothamBold",
    },

    ["Camper"] = {
        position = {0, 0.5, 0},
        rotation = {0, 90, 0},
    },
}

-- In client GUI script
local label = GUI:Create({
    type = "TextLabel",
    class = "hud-text",
    text = "Score: 0",
})

-- In asset server script
model:SetAttribute("StyleClass", "Camper")
GUI:StyleAsset(model)
```

---

# 2. Philosophy & Design

## 2.1 Core Principles

### Declarative Over Imperative

**Don't:** Write positioning code
```lua
-- BAD: Imperative
model:PivotTo(CFrame.new(10, 2, 5) * CFrame.Angles(0, math.rad(90), 0))
```

**Do:** Declare desired state
```lua
-- GOOD: Declarative
classes = {
    ["Dispenser"] = {
        position = {10, 2, 5},
        rotation = {0, 90, 0},
    },
}
```

### Configuration Over Code

Visual behavior lives in configuration files, not scattered through scripts.

### Single Source of Truth

`Styles.lua` is the authoritative source for all visual styling. Never bypass it.

### Separation of Concerns

- **Scripts**: Handle logic, events, state
- **Styles**: Handle appearance, positioning, transforms
- **Layouts**: Handle screen regions and responsive breakpoints

## 2.2 Design Goals

1. **Unified Language**: Same syntax for GUI and assets
2. **CSS-Like Familiarity**: Cascade, selectors, specificity
3. **Type Safety**: Array syntax converts to proper Roblox types
4. **Idempotency**: Repeated application doesn't drift
5. **Determinism**: Predictable results every time
6. **Extensibility**: Easy to add new properties

---

# 3. Architecture

## 3.1 Component Overview

```
┌─────────────────────────────────────────────────────────────┐
│                        Styles.lua                            │
│   (Configuration: base, classes, ids for GUI + Assets)       │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ▼
         ┌───────────────────────┐
         │    StyleEngine         │
         │ (Unified Resolution)   │
         └───────┬───────────────┘
                 │
         ┌───────┴───────┐
         │               │
         ▼               ▼
   ┌──────────┐    ┌──────────┐
   │GuiAdapter│    │AssetAdapter│
   └────┬─────┘    └─────┬────┘
        │                │
        ▼                ▼
   ┌─────────┐     ┌──────────┐
   │  GUI    │     │  Assets  │
   │Elements │     │ (Models, │
   │         │     │  Parts)  │
   └─────────┘     └──────────┘
```

### Style Resolution Flow

1. **Input**: Node + Styles.lua + Breakpoint (optional)
2. **Resolution**: StyleEngine applies cascade (base → class → id → inline)
3. **Filtering**: Domain adapter checks which properties are supported
4. **Conversion**: ValueConverter transforms arrays to Roblox types
5. **Application**: Domain adapter applies to instance

## 3.2 Domain Adapters

**Purpose**: Isolate domain-specific property handling while sharing resolution logic.

### GuiAdapter
- Handles: GuiObject instances
- Properties: size, position, textColor, font, etc.
- Special handling: UI modifiers (UICorner, UIStroke, etc.)

### AssetAdapter
- Handles: Model, BasePart, Attachment instances
- Properties: position, rotation, pivot, offset, scale
- Special handling: Transform composition, idempotent scaling

## 3.3 Key Modules

| Module | Purpose |
|--------|---------|
| `Styles.lua` | Central configuration (ReplicatedFirst) |
| `Layouts.lua` | Screen layout definitions (ReplicatedFirst) |
| `GUI.lua` | Public API for styling |
| `StyleEngine.lua` | Domain-agnostic resolution |
| `StyleResolver.lua` | Cascade algorithm (legacy, used by StyleEngine) |
| `ValueConverter.lua` | Type conversion (arrays → Roblox types) |
| `GuiAdapter.lua` | GUI domain handler |
| `AssetAdapter.lua` | Asset domain handler |
| `DomainAdapter.lua` | Adapter interface |

---

# 4. GUI Styling

## 4.1 Element Creation

### Basic Creation

```lua
local GUI = require(ReplicatedStorage:WaitForChild("GUI.GUI"))

local label = GUI:Create({
    type = "TextLabel",
    class = "hud-text",
    id = "score-display",
    text = "Score: 0",
})
label.Parent = screenGui
```

### With Children

```lua
local frame = GUI:Create({
    type = "Frame",
    class = "panel",
    size = {0.5, 0, 0.4, 0},
    children = {
        {
            type = "TextLabel",
            class = "panel-title",
            text = "Settings",
        },
        {
            type = "TextButton",
            class = "btn",
            text = "Close",
        },
    },
})
```

## 4.2 Style Definition

### Base Styles (Type-Level)

```lua
-- In Styles.lua
base = {
    TextLabel = {
        backgroundTransparency = 1,
        font = "SourceSans",
        textColor = {255, 255, 255},
    },
    Frame = {
        backgroundColor = {30, 30, 30},
        backgroundTransparency = 0.1,
    },
}
```

### Class Styles

```lua
classes = {
    ["hud-text"] = {
        textSize = 24,
        font = "GothamBold",
    },

    ["hud-large"] = {
        textSize = 36,
    },

    ["gold"] = {
        textColor = {255, 170, 0},
    },

    -- Multiple classes: "hud-text hud-large gold"
}
```

### ID Styles (Highest Specificity)

```lua
ids = {
    ["score-display"] = {
        textSize = 42,
        textColor = {255, 200, 100},
    },
}
```

## 4.3 Value Types

### UDim2 (Position, Size)

```lua
-- Format: {scaleX, offsetX, scaleY, offsetY}
size = {0.5, 0, 0.4, 0},        -- 50% width, 40% height
position = {0.5, -50, 0.5, -50}, -- Centered with offset
```

### Color3 (RGB)

```lua
-- Format: {r, g, b} where 0-255 (auto-converts) or 0-1
textColor = {255, 170, 0},   -- Orange (0-255 range)
textColor = {1, 0.67, 0},    -- Orange (0-1 range)
```

### Vector2 (Anchor Points)

```lua
-- Format: {x, y}
anchorPoint = {0.5, 0.5},  -- Center anchor
```

### Fonts

```lua
-- String name maps to Enum.Font
font = "GothamBold",
font = "Bangers",
font = "SourceSans",
```

## 4.4 UI Modifiers

### Corner Radius (UICorner)

```lua
["panel"] = {
    cornerRadius = 12,  -- UDim(0, 12)
}
```

### Stroke (UIStroke)

```lua
["bordered"] = {
    stroke = {
        color = {255, 255, 255},
        thickness = 2,
        transparency = 0,
    },
}
```

### Padding (UIPadding)

```lua
["padded"] = {
    padding = 8,  -- Uniform padding
}

["custom-padding"] = {
    padding = {
        top = 10,
        right = 5,
        bottom = 10,
        left = 5,
    },
}
```

### List Layout (UIListLayout)

```lua
["vertical-list"] = {
    listLayout = {
        direction = "Vertical",
        hAlign = "Center",
        vAlign = "Top",
        padding = 5,
        sortOrder = "LayoutOrder",
    },
}
```

## 4.5 Responsive Breakpoints

### Define Breakpoints

```lua
-- In Layouts.lua
breakpoints = {
    desktop = { minWidth = 1200 },
    tablet = { minWidth = 768, maxWidth = 1199 },
    phone = { maxWidth = 767 },
}
```

### Responsive Styles

```lua
-- In Styles.lua
classes = {
    ["responsive-text"] = {
        textSize = 24,  -- Desktop default
    },
    ["responsive-text@tablet"] = {
        textSize = 20,
    },
    ["responsive-text@phone"] = {
        textSize = 16,
    },
}
```

## 4.6 Runtime Style Manipulation

```lua
-- Replace all classes
GUI:SetClass(element, "new-class")

-- Add a class
GUI:AddClass(element, "highlighted")

-- Remove a class
GUI:RemoveClass(element, "highlighted")

-- Toggle a class
GUI:ToggleClass(element, "active")

-- Check if has class
if GUI:HasClass(element, "active") then
    -- ...
end
```

---

# 5. Asset Styling

## 5.1 Asset Creation Pattern

### 1. Define Styles

```lua
-- In Styles.lua
classes = {
    ["Camper"] = {
        position = {0, 0.5, 0},  -- Y=0.5 studs above ground
    },
    ["Camper1"] = {
        rotation = {0, 0, 0},    -- North
    },
    ["Camper2"] = {
        rotation = {0, 90, 0},   -- East
    },
}
```

### 2. Apply in Asset Script

```lua
-- In Camper server script
local GUI = require(ReplicatedStorage:WaitForChild("GUI.GUI"))

-- Set style class via attribute
model:SetAttribute("StyleClass", "Camper Camper1")

-- Apply styles
GUI:StyleAsset(model)
```

## 5.2 Transform Properties

### Position

**Type**: `{x, y, z}` (Vector3)
**Purpose**: World position offset in studs
**Space**: World-space translation

```lua
["Dispenser"] = {
    position = {10, 2, 5},  -- X=10, Y=2, Z=5 studs
}
```

### Rotation

**Type**: `{x, y, z}` (Vector3)
**Purpose**: Rotation in **degrees** (NOT radians)
**Order**: Applied as CFrame.Angles(rx, ry, rz)

```lua
["FacingEast"] = {
    rotation = {0, 90, 0},   -- Rotate 90° around Y axis
}

["Tilted"] = {
    rotation = {15, 45, 0},  -- Combo rotation
}
```

**IMPORTANT**: Always use degrees, never `math.rad()`.

### Offset

**Type**: `{x, y, z}` (Vector3)
**Purpose**: Local-space translation after rotation
**Space**: Relative to rotated axes

```lua
["WeaponRack"] = {
    rotation = {0, 45, 0},
    offset = {0, 0, -2},     -- 2 studs "forward" in rotated space
}
```

### Pivot

**Type**: `CFrame`
**Purpose**: Explicit pivot override (advanced)
**Use Case**: When you need full CFrame control

```lua
["CustomPivot"] = {
    pivot = CFrame.new(5, 0, 5) * CFrame.Angles(0, math.rad(45), 0),
}
```

### Scale

**Type**: `number` (uniform) or `{x, y, z}` (non-uniform)
**Purpose**: Multiply BasePart.Size
**Requirement**: `AllowScale = true` attribute on part
**Idempotency**: Stores baseline, always computed from baseline

```lua
-- Uniform scaling
["LargeCrate"] = {
    scale = 1.5,  -- 150% size
}

-- Non-uniform scaling
["FlatPlatform"] = {
    scale = {2, 0.5, 2},  -- Wide and flat
}
```

## 5.3 Transform Composition

When multiple transform properties are defined, they're applied in this order:

1. **Base CFrame**: Start from `pivot` (if provided) or current transform
2. **Position**: Apply world position offset (`base + position`)
3. **Rotation**: Apply rotation (`base * CFrame.Angles(...)`)
4. **Offset**: Apply local translation (`base * CFrame.new(offset)`)
5. **Scale**: Apply to Size (separate, not part of CFrame)

### Example

```lua
["ComplexTransform"] = {
    position = {10, 0, 5},    -- Move to (10, 0, 5)
    rotation = {0, 45, 0},    -- Rotate 45° around Y
    offset = {0, 0, -2},      -- Move 2 studs "forward" in rotated space
    scale = 1.2,              -- 120% size (requires AllowScale)
}
```

**Result**: Model positioned at (10, 0, 5), rotated 45°, offset forward in local space, 120% size.

## 5.4 Supported Node Types

### Model

- **Positioning**: `Model:PivotTo(CFrame)`
- **Supports**: position, rotation, pivot, offset
- **Scale**: Not supported (scale individual parts instead)

```lua
model:SetAttribute("StyleClass", "MyModel")
GUI:StyleAsset(model)
```

### BasePart (Part, MeshPart, etc.)

- **Positioning**: `part.CFrame = CFrame`
- **Supports**: position, rotation, offset, scale
- **Scale**: Requires `AllowScale = true` attribute

```lua
part:SetAttribute("AllowScale", true)  -- In Studio or script
part:SetAttribute("StyleClass", "ScaledPart")
GUI:StyleAsset(part)
```

### Attachment

- **Positioning**: `attachment.CFrame = CFrame` (relative to parent)
- **Supports**: position, rotation, offset (relative space)

```lua
attachment:SetAttribute("StyleClass", "OffsetAttachment")
GUI:StyleAsset(attachment)
```

## 5.5 Scaling Deep Dive

### Why Opt-In?

Scaling can break welded assemblies, collision geometry, and physics. To prevent accidental destruction, scaling requires explicit consent via the `AllowScale` attribute.

### Setup

```lua
-- In Studio: Select the BasePart, add attribute
-- Name: AllowScale
-- Type: Boolean
-- Value: true

-- Or via script (before styling):
part:SetAttribute("AllowScale", true)
```

### Idempotency

The system stores the **baseline size** in `__StyleBaseSize` attribute on first application. Every subsequent application computes from this baseline, preventing drift.

```lua
-- First application
GUI:StyleAsset(part)  -- Stores baseline, applies scale

-- Repeated applications (safe)
GUI:StyleAsset(part)  -- Uses stored baseline, recomputes
GUI:StyleAsset(part)  -- Always 1.5x baseline, never drifts
```

### Debugging

If scale doesn't apply:
1. Check Output for warning: `"Scale blocked on ... (AllowScale attribute not set)"`
2. Verify `AllowScale = true` attribute exists on the part
3. Confirm you're targeting a BasePart, not a Model

## 5.6 Node Identity

Assets use attributes for selector matching:

### StyleClass Attribute

Space-separated class names (like CSS).

```lua
model:SetAttribute("StyleClass", "Camper Camper1")
-- Applies: base.Model → classes.Camper → classes.Camper1
```

### StyleId Attribute

Unique identifier. Defaults to `instance.Name` if not set.

```lua
model:SetAttribute("StyleId", "main-dispenser")
-- Matches: ids["main-dispenser"]
```

## 5.7 Complete Example

```lua
-- In Styles.lua
classes = {
    ["CircleFormation"] = {
        position = {0, 0, 0},  -- Base position
    },

    ["Camper1"] = {
        rotation = {0, 0, 0},
        offset = {0, 0, -10},  -- 10 studs north
    },

    ["Camper2"] = {
        rotation = {0, 90, 0},
        offset = {0, 0, -10},  -- 10 studs east (after rotation)
    },

    ["Camper3"] = {
        rotation = {0, 180, 0},
        offset = {0, 0, -10},  -- 10 studs south
    },

    ["Camper4"] = {
        rotation = {0, 270, 0},
        offset = {0, 0, -10},  -- 10 studs west
    },
}

-- In asset server script
local GUI = require(ReplicatedStorage:WaitForChild("GUI.GUI"))
local runtimeAssets = workspace:WaitForChild("RuntimeAssets")

-- Position campers in circle around fire
for i = 1, 4 do
    local camper = runtimeAssets:WaitForChild("Camper" .. i)
    camper:SetAttribute("StyleClass", "CircleFormation Camper" .. i)
    GUI:StyleAsset(camper)
end
```

---

# 6. Practical Recipes

## 6.1 HUD Element Creation

```lua
-- Define styles
classes = {
    ["hud-panel"] = {
        backgroundColor = {0, 0, 80},
        backgroundTransparency = 0.8,
        cornerRadius = 12,
        stroke = {
            color = {255, 255, 255},
            thickness = 1,
        },
    },

    ["hud-header"] = {
        font = "Bangers",
        textSize = 36,
        textColor = {255, 170, 0},
        backgroundTransparency = 1,
    },

    ["hud-value"] = {
        font = "GothamBold",
        textSize = 44,
        textColor = {255, 255, 255},
        backgroundTransparency = 1,
    },
}

-- Create HUD
local GUI = require(ReplicatedStorage:WaitForChild("GUI.GUI"))

local panel = GUI:Create({
    type = "Frame",
    class = "hud-panel",
    size = {0.15, 0, 0.3, 0},
    position = {0.85, 0, 0, 0},
    children = {
        {
            type = "TextLabel",
            class = "hud-header",
            size = {1, 0, 0.3, 0},
            text = "Score",
        },
        {
            type = "TextLabel",
            class = "hud-value",
            id = "score-value",
            size = {1, 0, 0.7, 0},
            position = {0, 0, 0.3, 0},
            text = "0",
        },
    },
})
panel.Parent = screenGui
```

## 6.2 Circular Asset Formation

```lua
-- Styles.lua
classes = {
    ["CircleCenter"] = {
        position = {0, 0, 0},
    },
}

-- Asset script
local GUI = require(ReplicatedStorage:WaitForChild("GUI.GUI"))
local radius = 15  -- studs
local count = 8

for i = 1, count do
    local angle = (i - 1) * (360 / count)
    local rad = math.rad(angle)
    local x = math.cos(rad) * radius
    local z = math.sin(rad) * radius

    local asset = runtimeAssets:WaitForChild("Item" .. i)
    asset:SetAttribute("StyleClass", "CircleCenter")
    GUI:StyleAsset(asset, {
        position = {x, 0, z},
        rotation = {0, -angle, 0},  -- Face outward
    })
end
```

## 6.3 Responsive Button

```lua
-- Styles.lua
classes = {
    ["btn"] = {
        backgroundColor = {80, 80, 100},
        textColor = {255, 255, 255},
        textSize = 16,
        backgroundTransparency = 0,
        cornerRadius = 8,
    },
    ["btn:hover"] = {
        backgroundColor = {100, 100, 140},
    },
    ["btn:active"] = {
        backgroundColor = {60, 60, 80},
    },
}

-- Client script
local button = GUI:Create({
    type = "TextButton",
    class = "btn",
    text = "Click Me",
    size = {0, 150, 0, 40},
    onClick = function()
        print("Clicked!")
    end,
})
button.Parent = screenGui
```

## 6.4 Grid of Items

```lua
-- Styles.lua
classes = {
    ["grid-item"] = {
        size = {0, 80, 0, 80},
        backgroundColor = {40, 40, 60},
        cornerRadius = 8,
    },
}

-- Client script
local GUI = require(ReplicatedStorage:WaitForChild("GUI.GUI"))

local container = GUI:Create({
    type = "Frame",
    size = {0, 300, 0, 300},
    listLayout = {
        direction = "Horizontal",
        padding = 10,
        wraps = true,
    },
})

for i = 1, 12 do
    local item = GUI:Create({
        type = "Frame",
        class = "grid-item",
    })
    item.Parent = container
end

container.Parent = screenGui
```

## 6.5 Asset Height Above Baseplate

```lua
-- Styles.lua
classes = {
    ["BaseOffset"] = {
        position = {0, 0.5, 0},  -- 0.5 studs above ground
    },

    ["Camper"] = {
        -- Inherits BaseOffset position
    },
}

-- Asset script (applying to all campers)
local baseplateTop = workspace.Baseplate.Position.Y + (workspace.Baseplate.Size.Y / 2)

for _, camper in ipairs(runtimeAssets:GetChildren()) do
    if camper.Name:match("^Camper") then
        camper:SetAttribute("StyleClass", "BaseOffset Camper")
        GUI:StyleAsset(camper, {
            position = {camper.PrimaryPart.Position.X, baseplateTop, camper.PrimaryPart.Position.Z},
        })
    end
end
```

---

# 7. Troubleshooting

## 7.1 GUI Issues

### Styles Not Applying

**Symptom**: Element created but uses default appearance

**Causes**:
1. Typo in class name
2. Style not defined in Styles.lua
3. Rojo not synced
4. Style cached (restart Rojo)

**Solution**:
```lua
-- Verify class name matches exactly
class = "hud-text"  -- CORRECT
class = "hudtext"   -- WRONG (no match)

-- Check Styles.lua has the style
classes = {
    ["hud-text"] = { ... },  -- Must exist
}

-- Force Rojo resync
-- Disconnect and reconnect Rojo plugin
```

### Wrong Color

**Symptom**: Color appears black or white instead of expected color

**Cause**: Using wrong range (0-1 vs 0-255)

**Solution**:
```lua
-- System auto-detects range
textColor = {255, 170, 0},   -- CORRECT (0-255)
textColor = {1, 0.67, 0},    -- CORRECT (0-1)

-- If color looks wrong, verify values
```

### Element Not Visible

**Symptom**: Element created but not appearing

**Causes**:
1. `visible = false` in styles
2. Parent not set
3. Z-index/DisplayOrder behind other elements
4. Size is {0, 0, 0, 0}

**Solution**:
```lua
-- Check visibility
visible = true,  -- Or remove (defaults to true)

-- Verify parent
element.Parent = screenGui  -- Must have parent to render

-- Check z-index
zIndex = 10,  -- Higher values render on top
```

## 7.2 Asset Issues

### Asset Not Moving

**Symptom**: `GUI:StyleAsset()` called but asset stays at (0, 0, 0)

**Causes**:
1. Style class not defined
2. Typo in `StyleClass` attribute
3. Property name misspelled

**Solution**:
```lua
-- Verify attribute
print(model:GetAttribute("StyleClass"))  -- Should print "Camper"

-- Verify style exists
classes = {
    ["Camper"] = {  -- Must match attribute
        position = {0, 0.5, 0},
    },
}

-- Check for typos
position = {0, 0.5, 0},  -- CORRECT
Position = {0, 0.5, 0},  -- WRONG (capital P)
```

### Scale Not Working

**Symptom**: `scale` defined but part stays original size

**Causes**:
1. `AllowScale` attribute not set
2. Trying to scale a Model
3. Scale applied to wrong instance

**Solution**:
```lua
-- Check Output for warning
-- "Scale blocked on ... (AllowScale attribute not set)"

-- Set attribute in Studio or script
part:SetAttribute("AllowScale", true)

-- Verify targeting BasePart, not Model
if node:IsA("BasePart") then
    GUI:StyleAsset(part)  -- Will work
end
```

### Rotation Wrong Direction

**Symptom**: Asset rotates but facing wrong way

**Cause**: Using radians instead of degrees

**Solution**:
```lua
-- WRONG: Using radians
rotation = {0, math.rad(90), 0},

-- CORRECT: Using degrees
rotation = {0, 90, 0},
```

### Transform Not Composing

**Symptom**: Only last transform property applies

**Cause**: Properties applying in wrong order or overwriting

**Solution**: Trust the composition order. All properties apply together:
```lua
["Complex"] = {
    position = {10, 0, 5},  -- All three apply
    rotation = {0, 45, 0},  -- in documented order
    offset = {0, 0, -2},    -- (position → rotation → offset)
}
```

## 7.3 Common Mistakes

### Using `math.rad()` in Styles

```lua
-- WRONG
["Rotated"] = {
    rotation = {0, math.rad(90), 0},  -- System expects degrees!
}

-- CORRECT
["Rotated"] = {
    rotation = {0, 90, 0},
}
```

### Forgetting to Set StyleClass

```lua
-- WRONG: Styles defined but never applied
-- (missing SetAttribute call)
GUI:StyleAsset(model)  -- Uses Name as fallback

-- CORRECT
model:SetAttribute("StyleClass", "Camper")
GUI:StyleAsset(model)
```

### Trying to Scale Models

```lua
-- WRONG: Models don't support scale
model:SetAttribute("StyleClass", "BigModel")
classes = {
    ["BigModel"] = { scale = 2 },  -- Won't work
}

-- CORRECT: Scale individual parts
for _, part in ipairs(model:GetDescendants()) do
    if part:IsA("BasePart") then
        part:SetAttribute("AllowScale", true)
        part:SetAttribute("StyleClass", "BigPart")
        GUI:StyleAsset(part)
    end
end
```

---

# 8. Advanced Techniques

## 8.1 Programmatic Style Generation

```lua
-- Generate styles for numbered assets
local camperCount = 8
local angleStep = 360 / camperCount

for i = 1, camperCount do
    local angle = (i - 1) * angleStep
    classes["Camper" .. i] = {
        rotation = {0, angle, 0},
    }
end
```

**Note**: This requires modifying Styles.lua via script before it loads (complex). Prefer inline overrides:

```lua
-- Better approach: Use inline styles
for i = 1, camperCount do
    local angle = (i - 1) * angleStep
    local camper = runtimeAssets["Camper" .. i]
    camper:SetAttribute("StyleClass", "Camper")
    GUI:StyleAsset(camper, {
        rotation = {0, angle, 0},  -- Inline override
    })
end
```

## 8.2 Conditional Styling

```lua
local function getAssetClass(asset)
    if asset:GetAttribute("IsActive") then
        return "ActiveAsset"
    else
        return "InactiveAsset"
    end
end

asset:SetAttribute("StyleClass", getAssetClass(asset))
GUI:StyleAsset(asset)
```

## 8.3 Style Interpolation (Animation)

```lua
-- Animate position change
local TweenService = game:GetService("TweenService")

local function animateToStyle(model, targetStyle)
    local targetPos = Vector3.new(table.unpack(targetStyle.position))
    local targetRot = Vector3.new(table.unpack(targetStyle.rotation))
    local targetCF = CFrame.new(targetPos) * CFrame.Angles(
        math.rad(targetRot.X),
        math.rad(targetRot.Y),
        math.rad(targetRot.Z)
    )

    local tween = TweenService:Create(model.PrimaryPart, TweenInfo.new(1), {
        CFrame = targetCF,
    })
    tween:Play()
end

-- Usage
animateToStyle(model, {
    position = {10, 2, 5},
    rotation = {0, 90, 0},
})
```

## 8.4 Cascading Class Inheritance

```lua
-- Base class
classes = {
    ["Entity"] = {
        position = {0, 0.5, 0},  -- Hover above ground
    },

    ["Friendly"] = {
        -- Inherits Entity position
    },

    ["Enemy"] = {
        -- Inherits Entity position
    },

    ["FriendlyNPC"] = {
        -- Composes: Entity + Friendly
    },
}

-- Usage
npc:SetAttribute("StyleClass", "Entity Friendly FriendlyNPC")
GUI:StyleAsset(npc)
```

## 8.5 Debug Visualization

```lua
-- Visualize style application
local function debugStyleApplied(node)
    local styleClass = node:GetAttribute("StyleClass") or "none"
    local styleId = node:GetAttribute("StyleId") or node.Name

    print(string.format("Applied styles to %s (class: %s, id: %s)",
        node:GetFullName(),
        styleClass,
        styleId
    ))

    -- Create debug label (optional)
    local attachment = Instance.new("Attachment")
    attachment.Parent = node:IsA("Model") and node.PrimaryPart or node

    local billboard = Instance.new("BillboardGui")
    billboard.Size = UDim2.new(0, 200, 0, 50)
    billboard.Adornee = attachment
    billboard.Parent = attachment

    local label = GUI:Create({
        type = "TextLabel",
        class = "debug-label",
        text = styleClass,
        size = {1, 0, 1, 0},
    })
    label.Parent = billboard
end

-- Use after styling
GUI:StyleAsset(model)
debugStyleApplied(model)
```

---

# 9. Migration Guide

## 9.1 From Manual GUI to Styled GUI

### Before

```lua
-- OLD: Manual GUI creation
local label = Instance.new("TextLabel")
label.Size = UDim2.new(0, 200, 0, 50)
label.Position = UDim2.new(0.5, -100, 0.5, -25)
label.BackgroundColor3 = Color3.new(0, 0, 0)
label.BackgroundTransparency = 0.5
label.TextColor3 = Color3.fromRGB(255, 170, 0)
label.TextSize = 24
label.Font = Enum.Font.GothamBold
label.Text = "Score: 0"
label.Parent = screenGui
```

### After

```lua
-- NEW: Declarative styling
-- In Styles.lua:
classes = {
    ["hud-text"] = {
        backgroundColor = {0, 0, 0},
        backgroundTransparency = 0.5,
        textColor = {255, 170, 0},
        textSize = 24,
        font = "GothamBold",
    },
}

-- In script:
local GUI = require(ReplicatedStorage:WaitForChild("GUI.GUI"))
local label = GUI:Create({
    type = "TextLabel",
    class = "hud-text",
    size = {0, 200, 0, 50},
    position = {0.5, -100, 0.5, -25},
    text = "Score: 0",
})
label.Parent = screenGui
```

## 9.2 From Manual Asset Positioning to Styled Assets

### Before

```lua
-- OLD: Hardcoded positioning
local model = runtimeAssets:WaitForChild("Dispenser")
model:PivotTo(CFrame.new(10, 2, 5) * CFrame.Angles(0, math.rad(90), 0))
```

### After

```lua
-- NEW: Declarative positioning
-- In Styles.lua:
classes = {
    ["Dispenser"] = {
        position = {10, 2, 5},
        rotation = {0, 90, 0},
    },
}

-- In script:
local GUI = require(ReplicatedStorage:WaitForChild("GUI.GUI"))
local model = runtimeAssets:WaitForChild("Dispenser")
model:SetAttribute("StyleClass", "Dispenser")
GUI:StyleAsset(model)
```

## 9.3 Incremental Migration Strategy

1. **Phase 1**: New assets only
   - All new code uses styling system
   - Existing code remains unchanged

2. **Phase 2**: Refactor on touch
   - When modifying existing asset, migrate to styling system
   - Document the change

3. **Phase 3**: Full migration (optional)
   - Systematically convert all assets
   - Test thoroughly between migrations

---

# 10. Quick Reference

## 10.1 GUI API

```lua
-- Element creation
local element = GUI:Create(definition)
local elements = GUI:CreateMany(definitions)

-- Layout management
local screenGui, regions = GUI:CreateLayout(layoutName, content)
local region = GUI:GetRegion(layoutName, regionId)
GUI:PlaceInRegion(layoutName, regionId, content)

-- Class manipulation
GUI:SetClass(element, className)
GUI:AddClass(element, className)
GUI:RemoveClass(element, className)
GUI:HasClass(element, className) -> boolean
GUI:ToggleClass(element, className)

-- Asset styling
GUI:StyleAsset(asset, inlineStyles)
GUI:StyleAssetTree(rootAsset, inlineStyles)
```

## 10.2 Value Type Cheat Sheet

| Context | Input | Output |
|---------|-------|--------|
| GUI Size/Position | `{0.5, 0, 0.5, 0}` | `UDim2.new(0.5, 0, 0.5, 0)` |
| GUI Color | `{255, 170, 0}` | `Color3.fromRGB(255, 170, 0)` |
| GUI Anchor | `{0.5, 0.5}` | `Vector2.new(0.5, 0.5)` |
| Asset Position | `{10, 2, 5}` | `Vector3.new(10, 2, 5)` |
| Asset Rotation | `{0, 90, 0}` | `Vector3` (degrees → radians) |
| Asset Scale | `1.5` or `{2, 1, 2}` | `Vector3` (uniform or non-uniform) |

## 10.3 Property Reference

### GUI Properties

`size`, `position`, `anchorPoint`, `backgroundColor`, `backgroundTransparency`, `textColor`, `textSize`, `font`, `text`, `visible`, `cornerRadius`, `stroke`, `padding`, `listLayout`, `aspectRatio`, `zIndex`

### Asset Properties

`position`, `rotation`, `pivot`, `offset`, `scale`

## 10.4 Cascade Order

1. Base (by type)
2. Classes (in order from StyleClass string)
3. ID
4. Inline (passed to StyleAsset/Create)

## 10.5 Troubleshooting Checklist

- [ ] Rojo connected and synced
- [ ] Style defined in Styles.lua
- [ ] Class name matches exactly (case-sensitive)
- [ ] `StyleClass` attribute set on asset
- [ ] `AllowScale` attribute set for scaling
- [ ] Rotation in degrees (not radians)
- [ ] Check Output for warnings
- [ ] Verify node type supports property

---

**End of Styling System Guide**
