# Warren Framework: DOM Architecture Vision

## Purpose of This Document

This is an architectural vision and implementation guide for Claude Code. It describes the next evolution of the Warren framework (formerly LibPureFiction): a full XML/HTML-style DOM model applied to Roblox game development. Read this document completely before analyzing the codebase or writing any code. This is the north star — every decision should align with the mental model described here.

## Who Built This and Why It Matters

Warren is built by a developer with decades of web development experience (DOM, CSS, JavaScript, Node.js) but no traditional game engine background. This is intentional and fundamental. Warren's entire philosophy is that the web already solved the hard problems of component architecture, separation of concerns, declarative composition, and reactive updates. Warren ports those solutions into Roblox's 3D game environment.

**Do not suggest "the Roblox way" of doing things.** Warren deliberately rejects conventional Roblox patterns. If you find yourself reaching for a pattern from Knit, Nevermore, or typical Roblox scripting tutorials, stop and ask whether the web has a better answer. It almost always does.

---

## Part 1: The Core Mental Model

Warren treats the entire Roblox game as a **living document**, exactly like a web browser treats an HTML page. Every concept maps directly:

| Web Concept | Warren Equivalent |
|---|---|
| HTML DOM Tree | Roblox Instance hierarchy, managed by Warren |
| DOM Nodes / Elements | Roblox Parts/Models wrapped as Warren nodes |
| `document.getElementById()` | `Warren.dom.getElementById()` |
| `document.querySelector()` | `Warren.dom.querySelector()` |
| `appendChild()`, `removeChild()` | `Warren.dom.appendChild(node, child)` |
| CSS Classes & Cascade | Warren Style system (runtime attribute cascade) |
| CSS Stylesheets | Warren Style Packs (declarative attribute definitions) |
| JavaScript Event Listeners | Warren Signal system |
| XSLT Transformations | Warren Build Pipeline (source defs → resolved game tree) |
| XRefs / `href` / `src` | Warren cross-references between declarative definitions |
| Web Components | Warren Components (closure-based, signal-driven) |
| `<script>` behavior modules | Warren Extensions (imperative hooks, declaratively referenced) |

**This is not a metaphor. This is the literal architecture.** When in doubt about how something should work, ask "how does the browser do it?" and adapt that answer.

---

## Part 2: The DOM Layer

### 2.1 Nodes Are Dumb References

A Warren node is a **handle** — an identity token. It has no methods on its surface. It does not know how to manipulate itself.

```lua
-- WRONG: Methods on the node
node:appendChild(child)
node:setAttribute("color", "red")
node:remove()

-- CORRECT: DOM API operates ON nodes
Warren.dom.appendChild(parentNode, childNode)
Warren.dom.setAttribute(node, "color", "red")
Warren.dom.removeChild(parentNode, childNode)
```

This is the W3C DOM model, not the jQuery model. Nodes are arguments to API functions, not objects with fluent interfaces. This is critical because:

1. **No method surface to leak or abuse.** Claude Code cannot call methods that don't exist.
2. **All mutation is centralized.** The DOM system is the single authority over all node manipulation. Validation, signal emission, lifecycle hooks — all in one place.
3. **Capability scoping via factories.** Systems receive only the DOM methods they need. A build pipeline phase gets construction methods. A runtime component gets interaction methods. Principle of least privilege.

### 2.2 DOM API Methods

The DOM system should provide (at minimum) equivalents to:

**Tree Traversal:**
- `Warren.dom.getElementById(id)` — Lookup by unique ID
- `Warren.dom.getElementsByClassName(className)` — Batch lookup by class
- `Warren.dom.querySelector(selector)` — CSS-style selector lookup
- `Warren.dom.querySelectorAll(selector)` — All matching nodes
- `Warren.dom.getParent(node)` — Parent node
- `Warren.dom.getChildren(node)` — Direct children
- `Warren.dom.getDescendants(node)` — All descendants (deep traversal)

**Tree Mutation:**
- `Warren.dom.appendChild(parent, child)` — Add child node
- `Warren.dom.removeChild(parent, child)` — Remove child node
- `Warren.dom.insertBefore(parent, newChild, referenceChild)` — Positional insert
- `Warren.dom.replaceChild(parent, newChild, oldChild)` — Swap nodes
- `Warren.dom.cloneNode(node, deep)` — Deep or shallow clone

**Attribute Manipulation:**
- `Warren.dom.setAttribute(node, key, value)` — Set attribute
- `Warren.dom.getAttribute(node, key)` — Get attribute
- `Warren.dom.removeAttribute(node, key)` — Remove attribute
- `Warren.dom.hasAttribute(node, key)` — Check existence

**Class Management:**
- `Warren.dom.addClass(node, className)` — Add style class
- `Warren.dom.removeClass(node, className)` — Remove style class
- `Warren.dom.toggleClass(node, className)` — Toggle class
- `Warren.dom.hasClass(node, className)` — Check class membership
- `Warren.dom.getClasses(node)` — List all classes

**Lifecycle:**
- `Warren.dom.createElement(type, attributes)` — Create new node
- `Warren.dom.createFragment()` — Create document fragment for batch operations
- `Warren.dom.mount(node)` — Trigger mount lifecycle (onMount callbacks)
- `Warren.dom.unmount(node)` — Trigger unmount lifecycle (onUnmount callbacks)

### 2.3 DOM Events and Signals

DOM mutations emit signals automatically. This is how the rest of the system stays reactive:

- Node added → `childAdded` signal on parent
- Node removed → `childRemoved` signal on parent
- Attribute changed → `attributeChanged` signal on node
- Class added/removed → `classChanged` signal on node
- Node mounted → `mounted` signal on node
- Node unmounted → `unmounted` signal on node

These are Warren signals, not Roblox events. They flow through the existing signal infrastructure. Systems subscribe to these signals to react to DOM changes — they never poll or manually check state.

### 2.4 Relationship to Roblox Instances

Warren nodes wrap Roblox Instances (Parts, Models, Folders, etc.) but **Warren owns the abstraction layer.** Code should never reach through a Warren node to directly manipulate the underlying Roblox Instance. The DOM API handles the translation:

```lua
-- Warren.dom.setAttribute(node, "color", Color3.new(1,0,0))
-- Internally: finds the Roblox Instance, applies the property
-- Externally: consumer code never touches the Instance directly
```

This allows Warren to intercept, validate, batch, or defer mutations. It also means Warren could theoretically wrap non-Instance things (virtual nodes, computed nodes) without breaking consumer code.

---

## Part 3: The Style System (CSS Analog)

### 3.1 Overview

Warren Styles apply visual and behavioral attributes to nodes through a cascade model identical in concept to CSS. Styles are **not** stored on nodes — they are resolved by the style system and applied to nodes based on class membership, ID, and specificity.

### 3.2 Style Definitions

A style definition is a declarative data structure (Lua table) that describes attributes for a selector:

```lua
-- Conceptual example (exact syntax TBD based on what feels right)
local styles = {
    [".biome-inferno"] = {
        granite_color = Color3.fromRGB(80, 20, 20),
        lava_intensity = 1.0,
        fog_density = 0.3,
        ambient_light = Color3.fromRGB(60, 20, 10),
    },
    [".room-boss"] = {
        lava_intensity = 1.5,
        fog_density = 0.5,
    },
    ["#final-altar"] = {
        granite_color = Color3.fromRGB(10, 10, 10),
        particle_effect = "embers",
    },
}
```

### 3.3 The Cascade

Specificity follows the CSS model:

1. **Base/default styles** — lowest priority, applied to all nodes of a type
2. **Class styles** — applied to nodes with matching classes (`.biome-inferno`)
3. **ID styles** — applied to specific nodes (`#final-altar`)
4. **Inline overrides** — set directly via `Warren.dom.setAttribute()`, highest priority

When multiple classes apply to a node, their properties merge with later/more-specific classes winning conflicts. This is the cascade.

### 3.4 Runtime Reactivity

**When a style definition changes, all nodes using that class update automatically.** This is the reactive core of the style system.

```lua
-- Change the biome-inferno lava intensity
Warren.styles.setProperty(".biome-inferno", "lava_intensity", 2.0)
-- Every node with class "biome-inferno" immediately updates
```

This is powered by the signal system. When `addClass` or `removeClass` is called on a node, the style system recalculates and applies the resolved attributes. When a style definition property changes, the style system finds all nodes subscribed to that class and reapplies.

### 3.5 Terrain Styles

Styles can define terrain rendering attributes as well as part attributes:

```lua
[".biome-cavern"] = {
    -- Part attributes
    granite_color = Color3.fromRGB(60, 55, 50),
    
    -- Terrain attributes
    terrain = {
        passes = {
            { material = Enum.Material.Rock, coverage = 1.0, algorithm = "fill" },
            { material = Enum.Material.CrackedLava, coverage = 0.3, algorithm = "perlin",
              frequency = 0.15, amplitude = 0.8 },
        },
        roughness = 0.7,
        voxel_resolution = 4,  -- studs per voxel
    },
}
```

The terrain system reads these style properties and executes a **multi-pass rendering pipeline**:
1. Base pass fills the region with the primary material
2. Detail passes layer additional materials using specified algorithms (perlin noise, voronoi, stripes, etc.)
3. Parameters control the visual output without changing the terrain system code

Different biomes = different terrain style definitions = completely different ground aesthetics from the same system.

### 3.6 Style Packs and Procedural Generation

Style definitions can come from three sources:

1. **Static Style Packs** — hand-crafted, curated definitions. Designer intent baseline.
2. **Generative** — the system creates style definitions within declared constraints (color ranges, parameter bounds, algorithm choices). Every run is visually unique.
3. **Hybrid** — start from a base static pack, add constraints, let the system fill in gaps with controlled randomness.

```lua
-- Hybrid example: base pack + constraints + generative fill
local style = Warren.styles.generate({
    base = StylePacks.Inferno,
    constraints = {
        lava_intensity = { min = 0.5, max = 1.5 },
        palette = "warm",
        pattern_style = "organic",
    },
    -- Properties not constrained are generated freely within base pack ranges
})
```

For IT GETS WORSE: early floors use static packs (familiar, readable). Deeper floors get increasing generative freedom. The game literally becomes more visually unpredictable as difficulty increases. "It gets worse" isn't just gameplay — it's the visual style destabilizing.

---

## Part 4: The Build Pipeline (XSLT Analog)

### 4.1 Overview

The build pipeline is the system that transforms declarative source definitions into a resolved game tree that the DOM layer instantiates. It is analogous to XSLT processing an XML source document.

**Three concerns, strictly separated:**

1. **Authoring** — declarative definitions that are lightweight, composable, and full of cross-references.
2. **Transformation** — the build pipeline resolves references, applies conditional logic, runs procedural generation, and outputs a fully resolved game tree definition.
3. **Instantiation** — the DOM layer takes the resolved tree and creates actual Roblox instances with components and signals wired up.

### 4.2 Source Definitions with XRefs

Source definitions reference each other without hard coupling:

```lua
-- Room definition (conceptual)
local room = {
    type = "room",
    id = "corridor-01",
    layout = ref("layouts/narrow-passage"),   -- xref to layout def
    theme = ref("themes/current-biome"),       -- xref to active theme
    lighting = ref("lighting/dim-corridor"),   -- xref to lighting def
    spawns = {
        ref("spawns/ambient-enemies"),
        ref("spawns/loot-common"),
    },
}
```

The `ref()` calls are cross-references. They don't contain the actual data — they point to other definitions that the transformation step resolves.

### 4.3 The Pipeline as a Document

The build pipeline itself is **declarative, not imperative.** It is a graph of processing nodes wired together through an orchestrator/patch panel. It is NOT a chain of method calls.

```lua
-- Conceptual pipeline definition
local roomBuildPipeline = {
    type = "pipeline",
    phases = {
        { id = "bounds",    processor = ref("processors/define-bounds") },
        { id = "maze",      processor = ref("processors/generate-maze") },
        { id = "mass",      processor = ref("processors/mass-terrain") },
        { id = "base-style", processor = ref("processors/apply-base-style") },
        { id = "detail-style", processor = ref("processors/apply-detail-passes") },
        { id = "lighting",  processor = ref("processors/apply-lighting") },
        { id = "components", processor = ref("processors/attach-components") },
        { id = "signals",   processor = ref("processors/wire-signals") },
    },
}
```

Each phase is a discrete node with input/output signal endpoints:
- **Reorderable** — move a phase by changing its position in the definition
- **Swappable** — plug in a different processor for any phase
- **Forkable** — phases can run in parallel branches and merge
- **Inspectable** — tap any point in the pipeline to see intermediate state (critical for the Forge R&D environment)
- **Manipulable via DOM API** — because pipeline phases are nodes in a document, `Warren.dom.getElementById("maze")` works on the pipeline definition itself. You could swap a pipeline phase at runtime using the same API that manipulates game geometry.

### 4.4 How Build Pipelines Use the DOM

Pipeline phases manipulate geometry **exclusively through DOM API methods.** There is no separate "build API" vs "runtime API." A pipeline phase adding a wall calls `Warren.dom.appendChild()`. A runtime system destroying a wall calls `Warren.dom.removeChild()`. Same code path, same validation, same signal emission.

This means:
- Every geometry mutation is observable and logged, whether it happened during build or at runtime
- The build system is the first consumer of an API that everything else also uses
- There is one way to touch geometry: the DOM API. Period.

### 4.5 Transformation as Procedural Generation

For IT GETS WORSE, the procedural dungeon generation IS the transformation step. The maze algorithm doesn't directly spawn blocks — it produces a resolved document that the DOM layer renders. Mental model: **parse → resolve → render**, exactly like a browser.

Different game modes or generators can be different transformation pipelines operating on the same source definitions and rendering through the same DOM layer.

---

## Part 5: Extensions (JavaScript Analog)

### 5.1 The Declarative/Imperative Boundary

Warren's goal: **build entire games without imperative coding, except for custom behavior bits.** Everything structural — dungeon generation, room construction, terrain styling, lighting, theming, component lifecycle, the entire build pipeline — is declarative.

The only imperative code should be for genuinely novel behaviors: unique enemy movement patterns, special trap mechanics, custom gameplay logic. These are **Extensions.**

### 5.2 Extension Contract

An Extension is:
- A closure (true encapsulation, nothing leaks)
- With signal endpoints (input/output)
- Declaratively referenced in game definitions

```lua
-- Extension definition (imperative code lives here)
local BounceOnHit = Warren.extension(function()
    local function calculateBounce(velocity, normal)
        -- Custom physics logic — this is the genuinely novel bit
        return velocity - 2 * velocity:Dot(normal) * normal
    end

    return {
        name = "BounceOnHit",
        In = {
            onCollision = function(context, data)
                local newVel = calculateBounce(data.velocity, data.normal)
                context.Out:Fire("bounced", { velocity = newVel })
            end,
        },
        Out = { bounced = {} },
    }
end)

-- Declarative reference in a game definition
local bouncyTrap = {
    type = "node",
    id = "trap-bouncy",
    class = { "trap", "physics-interactive" },
    extensions = { ref("extensions/bounce-on-hit") },  -- wired in declaratively
}
```

The Extension author writes the *what* (bounce physics). The framework handles the *how* (when it fires, what it connects to, lifecycle management) and the *when* (mounting, unmounting, signal routing).

---

## Part 6: Resource Loading & Network Layer (fetch/XHR Analog)

### 6.1 Overview

Every browser has a network stack. Warren needs one too — not immediately, but the architecture must be designed so it can be added without rearchitecting the ref system or the pipeline.

The core principle: **a ref is a ref regardless of where it resolves from.** Consumer code should never know or care whether a cross-reference points to a local definition, a Roblox DataStore entry, or an external HTTP endpoint. The resolution strategy is an implementation detail of the ref system.

### 6.2 Ref Resolution Tiers

Cross-references should resolve through a tiered strategy:

```lua
-- All three look identical to consuming code:
ref("layouts/narrow-passage")           -- Tier 1: Local (immediate)
ref("datastore://player-saves/slot-1")  -- Tier 2: Roblox DataStore (async, platform-managed)
ref("https://api.example.com/defs/v2")  -- Tier 3: External HTTP (async, self-hosted)
```

**Tier 1 — Local:** Resolved immediately during transformation. Definitions live in the game's source tree. This is what exists today.

**Tier 2 — Roblox DataStore:** Async resolution via Roblox's built-in persistence. Subject to Roblox's rate limits and the 4MB per-key size cap. Suitable for player saves and game state that fits within platform constraints.

**Tier 3 — External HTTP:** Async resolution via `HttpService:RequestAsync()`. Self-hosted resources on AWS/Azure/GCP. No Roblox size limits, but introduces hosting responsibility, latency, and availability concerns. This tier is **future work** — design for it now, implement later.

### 6.3 Roblox HTTP Constraints

Roblox imposes constraints that map loosely to browser security policies:

- **Server-side only** — `HttpService` calls can only be made from server scripts. This aligns with Warren's server-authoritative model. The server DOM fetches resources; clients receive the resolved result.
- **Domain whitelisting** — each game must explicitly enable HTTP and can only reach domains the developer configures. This is effectively a CORS policy. Warren should abstract this so the ref system handles it, not individual consumers.
- **Rate limits** — Roblox rate-limits HTTP requests. Warren's network layer should queue and throttle requests, not fire them ad-hoc.
- **No WebSockets** — Roblox doesn't support persistent connections. All remote resolution is request/response. Design for polling or on-demand fetching, not push-based updates.

### 6.4 Async Pipeline Integration

Remote refs make the build pipeline partially asynchronous. Implications:

- **Pipeline phases must support async resolution.** A phase that depends on a remote resource yields until the ref resolves, then continues. This is Warren's Promise/async-await layer.
- **Independent phases can proceed in parallel.** If phase A is waiting on an HTTP fetch and phase B has all its refs resolved locally, B should not block on A. This is where pipeline parallelism transitions from nice-to-have to structurally necessary.
- **Timeouts and failure handling are required.** A remote ref that takes too long or fails must not hang the pipeline indefinitely. Each remote ref should have a configurable timeout and a fallback strategy.

### 6.5 Caching

Browsers cache aggressively. Warren should too.

- **Session cache** — once a remote resource is fetched, store it for the duration of the game session. Don't re-fetch unless explicitly invalidated.
- **TTL (Time-to-Live)** — remote refs can specify a cache duration. Short TTL for frequently updated data, long TTL for stable definitions.
- **Stale-while-revalidate** — serve the cached version immediately while fetching an update in the background. Critical for not blocking gameplay on network latency.
- **Cache key strategy** — URL + version/ETag, so updated resources are fetched while unchanged ones are served from cache.

This becomes especially important if hosting costs are per-request. Aggressive caching is both a performance and a cost optimization.

### 6.6 Fallback Strategies

When an external source is unavailable, Warren needs a defined behavior. Options per ref:

- **Cached fallback** — use the last successfully fetched version. Stale data is better than no data for most cases.
- **Default fallback** — use a locally defined default. The ref specifies both a remote source and a local backup.
- **Graceful degradation** — the pipeline phase that needed the resource skips or uses reduced functionality. A biome style that can't load its custom palette falls back to the base theme.
- **Hard failure** — the resource is critical and the pipeline cannot continue without it. Rare, but necessary for things like player save data.

```lua
-- Conceptual ref with fallback
ref("https://api.example.com/styles/seasonal-event", {
    fallback = ref("styles/default-biome"),
    cache_ttl = 3600,  -- 1 hour
    timeout = 5000,    -- 5 seconds
})
```

### 6.7 Schema Validation

Local definitions are trusted — you authored them. Remote definitions are not. Before a remote resource is integrated into the DOM or used by the pipeline:

- **Validate against expected schema.** A style definition must have the right shape. A layout definition must have required fields.
- **Reject malformed data.** Don't silently accept garbage. Log the error, trigger fallback.
- **Sanitize inputs.** Remote data should never be able to inject behavior (no remote code execution, only data). This is Warren's Content Security Policy.

### 6.8 Future Self-Hosting Architecture (Notes)

Not for implementation now, but for design consideration:

- Containerized API on AWS/Azure/GCP serving JSON definitions over HTTPS
- Player save data stored in a managed database (DynamoDB, Cosmos, Firestore), bypassing Roblox's 4MB DataStore limit
- CDN for static assets — style packs, layout libraries, definition bundles. Cached at the edge for low latency.
- Versioned API endpoints — `/v1/styles/...`, `/v2/styles/...` so game updates don't break older clients
- Health checks and monitoring — Warren's network layer should report fetch failures so you can detect hosting issues before players do

The key design principle for now: **build the ref system and pipeline to be transport-agnostic.** Local, DataStore, HTTP — the plumbing changes, the interface doesn't. When self-hosting becomes real, it's a new ref resolver implementation, not a rearchitecture.

---

## Part 7: Existing Architecture Constraints

These are non-negotiable. They predate the DOM vision and the DOM vision must respect them.

### 7.1 Three Domains

- **System Domain** — the kernel. Bootstrap, preload, global game state. Server-authoritative.
- **Player Domain** — per-player user-space. Sessions, inventory, progression.
- **Asset Domain** — self-contained reusable components. Batteries-included.

**Dependency flows bottom-up ONLY:** Assets → Player → System. Never the reverse. No sibling dependencies.

### 7.2 Closure-Based Encapsulation

All node internals live inside closures. Nothing is exposed except signal endpoints and what factories explicitly attach. This is already implemented/in-progress as a refactor. The DOM vision builds on top of this — it does not replace it.

### 7.3 Signal-Driven Communication

Nodes communicate via signals. `Out:Fire()` → wiring → `In.onHandler()`. Never direct method calls between nodes. The DOM API is the ONLY additional surface, and it is centralized in the DOM system, not on nodes.

### 7.4 Server Authority

Server owns ALL authoritative game state. Client is view-layer ONLY. Client never modifies authoritative state. This applies to the DOM — the authoritative DOM tree lives server-side. Client receives a replicated view.

### 7.5 Convention Over Configuration

Folder structure and naming conventions determine behavior. Auto-discovery, not registration. Minimal configuration. The DOM system should follow this — node types, classes, and IDs should be discoverable by convention where possible.

### 7.6 The Forge

The Forge is a separate R&D project for building and testing generic modules before promoting them to production games. The DOM system, style system, and pipeline system should all be testable in the Forge independently.

---

## Part 8: Implementation Strategy

### 8.1 Build Order

The DOM vision has clear dependency layers. Build bottom-up:

1. **DOM Core** — Node registry, tree management, the DOM API methods (getElementById, appendChild, setAttribute, etc.). This is the foundation everything else depends on.
2. **DOM Events** — Signal emission on mutations (childAdded, attributeChanged, etc.). Wires DOM into the existing signal system.
3. **Style System Core** — Class management, style definitions, the cascade resolver. Depends on DOM attributes and class management.
4. **Style Reactivity** — Automatic reapplication when styles or classes change. Depends on DOM events.
5. **Terrain Style Integration** — Multi-pass terrain rendering driven by style definitions. Depends on style system.
6. **Pipeline Framework** — Declarative pipeline definitions, phase orchestrator, the patch panel model. Uses DOM API internally.
7. **Pipeline Phases** — Individual processors (maze gen, terrain massing, lighting, etc.) as swappable pipeline nodes.
8. **Generative Styles** — Procedural style generation within constraints. Depends on style system being stable.
9. **Extension System** — Formalized extension contract for imperative behavior hooks.

### 8.2 Critical Path for IT GETS WORSE

Not everything needs to ship at once. For the game's current needs, prioritize:

1. DOM Core + DOM Events (foundation)
2. Style System Core + Terrain Styles (the nine biomes need this)
3. Pipeline Framework + key phases (room construction already works, formalize it)
4. Generative Styles (visual variety for deeper floors)

Extensions can wait — the current signal/component system handles custom behaviors fine for now.

### 8.3 What Already Exists

Before implementing anything, **analyze the current codebase** to understand:
- How nodes are currently created and managed
- How the maze/room generation currently works (this becomes a pipeline)
- How terrain theming currently works (this becomes style-driven)
- How components are currently attached (this maps to the DOM lifecycle)
- Where the closure refactor stands

Map existing code to the DOM concepts. Identify what can be evolved vs what needs to be rebuilt. Prefer evolution — the current system works and ships games. The DOM layer should wrap and formalize what exists, not throw it away.

### 8.4 Naming Conventions

Use web-standard names wherever possible. If a web developer would recognize the method name, use it. Don't invent Roblox-flavored alternatives:

- `getElementById` not `findNodeById`
- `appendChild` not `addChild`
- `addClass` not `applyClass`
- `setAttribute` not `setProperty`

The whole point is that web developers can read Warren code and immediately understand it.

---

## Part 9: What This Enables

When fully realized, Warren with the DOM architecture means:

- **A game is a document.** It has structure (DOM), presentation (Styles), and behavior (Signals + Extensions). Separation of concerns, all the way through.
- **Building a game is describing it.** Declarative definitions, cross-references, style packs, pipeline configurations. Not scripts.
- **Runtime changes are style swaps.** Change a biome? Swap a stylesheet. Increase difficulty? Add a class. Transition zones? Blend classes per chunk.
- **Build pipelines are data.** Reorderable, swappable, inspectable, composable processing graphs. Not imperative code chains.
- **Content scales through combination.** Two materials × style parameters × algorithmic passes × generative constraints = unlimited visual variety from minimal assets. The Taco Bell philosophy at its logical extreme.
- **One API for everything.** Build systems, runtime systems, components, pipelines — all use the same DOM API. Learn once, use everywhere.
- **The framework enforces itself.** Closures prevent leaking internals. Centralized DOM API prevents bypassing mutation control. Signals prevent hidden coupling. The wrong thing is impossible, not just discouraged.
- **Web developers can build Roblox games.** The entire mental model — DOM, CSS, events, components — is already in their heads. Warren just applies it to 3D space.

---

## Part 10: Blind Spots and Open Questions

These are areas where the vision may have gaps. Flag these during implementation and propose solutions:

1. **Selector performance** — CSS selector resolution in a browser is heavily optimized. How do we keep querySelector fast in a game with thousands of nodes? Do we need indexing beyond ID and class lookups?

2. **Replication strategy** — The authoritative DOM is server-side. How much of the DOM tree and style state replicates to clients? Full tree? Diffs? Only visible/nearby nodes? This intersects with Roblox's existing replication model.

3. **Attribute types** — CSS has a relatively constrained property model. Warren attributes could be anything (Color3, Vector3, Enum values, tables). How does the cascade handle complex types? Deep merge? Replace?

4. **Specificity edge cases** — CSS specificity gets complicated. How much of that complexity do we actually need? Start simple (ID > class > default) and add nuance only when needed.

5. **Pipeline parallelism** — The vision mentions parallel pipeline branches. Is this actually needed for current games, or is sequential sufficient? Don't over-engineer.

6. **Hot reloading** — Can style definitions be swapped at runtime without rebuilding the DOM tree? This would be powerful for the Forge but may introduce state consistency challenges.

7. **Memory management** — Infinite dungeon means constant node creation/destruction. The DOM layer adds overhead per node. What's the memory profile? Do we need object pooling at the DOM level?

8. **Style inheritance vs composition** — CSS uses inheritance (child inherits parent styles). Is that the right model for 3D game nodes, or is explicit composition (node only gets styles from its own classes) cleaner?

9. **Cross-domain DOM access** — System, Player, and Asset domains have strict boundaries. Can a Player domain component query the DOM? Only its own subtree? This needs clear rules.

10. **Undo/history** — If the DOM tracks all mutations, is there value in a command history for debugging or replay? Low priority but architecturally interesting.

11. **Ref resolution ordering** — When multiple remote refs are in-flight simultaneously, does resolution order matter? Can a later-resolved ref invalidate an earlier one? What happens if two refs point to the same resource with different cache policies?

12. **Offline/degraded mode** — If external hosting goes down mid-session, can the game continue with cached/local resources? How does the DOM handle the transition from "online" to "degraded" gracefully without the player noticing?

13. **Save file size growth** — Self-hosted saves bypass DataStore's 4MB limit, but what's the practical upper bound? A player with hundreds of hours might generate massive save data. Compression? Incremental saves? Pruning strategies?

14. **Authentication for remote resources** — If save files are self-hosted, how does Warren verify that player A's request is actually from player A? Roblox provides player identity server-side, but the external API needs to trust that identity. Token-based auth flowing through the ref system.

---

## Summary: The One Rule

**Warren is a web browser for 3D games.**

Source definitions are the HTML. The build pipeline is the parser. The DOM is the document. Styles are the CSS. Signals are the event system. Extensions are the JavaScript. The game is a living document that the framework renders and keeps reactive.

Everything flows from this analogy. When you're unsure how to implement something, ask: "How does the browser do it?" Then adapt that answer to Warren.
