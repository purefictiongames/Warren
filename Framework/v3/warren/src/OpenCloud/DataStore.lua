--[[
    Warren Framework v3.0
    OpenCloud/DataStore.lua - Open Cloud DataStore Client (Cross-Runtime)

    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    OVERVIEW
    ============================================================================

    HTTP client wrapping the Roblox Open Cloud DataStore v1 API.
    Runs on both Roblox and Lune via the Platform abstraction layer.

    On Roblox: Uses HttpService:RequestAsync() — requires the
               "Open Cloud via HttpService Without Proxies" beta.
    On Lune:   Uses net.request() as before.

    API keys: On Lune, plain strings from env. On Roblox, opaque Secret
    objects from game settings — they work as HTTP header values directly.

    ============================================================================
    API REFERENCE
    ============================================================================

    Base URL: https://apis.roblox.com/datastores/v1/universes/{universeId}

    Endpoints used:
        GET    /standard-datastores/datastore/entries/entry   (Get entry)
        POST   /standard-datastores/datastore/entries/entry   (Set entry)
        DELETE /standard-datastores/datastore/entries/entry   (Delete entry)
        GET    /standard-datastores/datastore/entries          (List entries)
        GET    /standard-datastores                            (List datastores)

    Auth: x-api-key header

    ============================================================================
    USAGE
    ============================================================================

    ```lua
    local DataStore = require(Warren.OpenCloud.DataStore)

    local ds = DataStore.new({
        universeId = "123456789",
        apiKey = "your-open-cloud-api-key",  -- or Roblox Secret object
    })

    -- Get a value
    local data = ds:getEntry("PlayerData", "Player_001")

    -- Set a value
    ds:setEntry("PlayerData", "Player_001", { gold = 500, level = 3 })

    -- Delete
    ds:deleteEntry("PlayerData", "Player_001")

    -- List keys
    local entries = ds:listEntries("PlayerData", { prefix = "Player_", limit = 10 })
    ```

--]]

local _L = script == nil
local Platform = _L and require("@warren/OpenCloud/Platform") or require(script.Parent.Platform)

local DataStore = {}
DataStore.__index = DataStore

--------------------------------------------------------------------------------
-- CONSTANTS
--------------------------------------------------------------------------------

local BASE_URL = "https://apis.roblox.com/datastores/v1/universes"

--------------------------------------------------------------------------------
-- CONSTRUCTOR
--------------------------------------------------------------------------------

--[[
    Create a new DataStore client.

    @param config table:
        - universeId: string (required)
        - apiKey: string|Secret (required) — plain string on Lune, Secret on Roblox
        - scope: string? (default "global")
    @return DataStore
]]
function DataStore.new(config)
    assert(config.universeId, "DataStore requires universeId")
    assert(config.apiKey, "DataStore requires apiKey")

    local self = setmetatable({}, DataStore)
    self._universeId = tostring(config.universeId)
    self._apiKey = config.apiKey
    self._scope = config.scope or "global"
    self._baseUrl = BASE_URL .. "/" .. self._universeId
    return self
end

--------------------------------------------------------------------------------
-- ENTRIES
--------------------------------------------------------------------------------

--[[
    Get an entry from a DataStore.

    @param datastoreName string - Name of the DataStore
    @param key string - Entry key
    @return any? - Deserialized value, or nil if not found
    @return table? - Metadata (userIds, attributes, version info)
]]
function DataStore:getEntry(datastoreName, key)
    local url = self._baseUrl
        .. "/standard-datastores/datastore/entries/entry"
        .. "?datastoreName=" .. Platform.urlEncode(datastoreName)
        .. "&entryKey=" .. Platform.urlEncode(key)
        .. "&scope=" .. Platform.urlEncode(self._scope)

    local response = Platform.request({
        url = url,
        method = "GET",
        headers = {
            ["x-api-key"] = self._apiKey,
        },
    })

    if response.statusCode == 204 or response.statusCode == 404 then
        return nil, nil
    end

    if response.statusCode ~= 200 then
        error("[Warren.OpenCloud.DataStore] getEntry failed ("
            .. response.statusCode .. "): " .. response.body)
    end

    local data = Platform.jsonDecode(response.body)

    -- Extract metadata from headers
    local metadata = {
        version = response.headers["roblox-entry-version"],
        createdTime = response.headers["roblox-entry-created-time"],
        updatedTime = response.headers["roblox-entry-version-created-time"],
    }

    return data, metadata
end

--[[
    Set an entry in a DataStore.

    @param datastoreName string - Name of the DataStore
    @param key string - Entry key
    @param value any - Value to store (will be JSON-serialized)
    @param options table? - { userIds = {number}, attributes = table, matchVersion = string? }
    @return boolean - true on success
]]
function DataStore:setEntry(datastoreName, key, value, options)
    options = options or {}

    local body = Platform.jsonEncode(value)

    -- Compute MD5 hash for content-md5 header (required by Open Cloud)
    local md5Hash = Platform.md5Base64(body)

    local url = self._baseUrl
        .. "/standard-datastores/datastore/entries/entry"
        .. "?datastoreName=" .. Platform.urlEncode(datastoreName)
        .. "&entryKey=" .. Platform.urlEncode(key)
        .. "&scope=" .. Platform.urlEncode(self._scope)

    if options.matchVersion then
        url = url .. "&matchVersion=" .. Platform.urlEncode(options.matchVersion)
    end

    local headers = {
        ["x-api-key"] = self._apiKey,
        ["content-type"] = "application/json",
        ["content-md5"] = md5Hash,
    }

    if options.userIds then
        headers["roblox-entry-userids"] = Platform.jsonEncode(options.userIds)
    end

    if options.attributes then
        headers["roblox-entry-attributes"] = Platform.jsonEncode(options.attributes)
    end

    local response = Platform.request({
        url = url,
        method = "POST",
        headers = headers,
        body = body,
    })

    if response.statusCode ~= 200 then
        error("[Warren.OpenCloud.DataStore] setEntry failed ("
            .. response.statusCode .. "): " .. response.body)
    end

    return true
end

--[[
    Delete an entry from a DataStore.

    @param datastoreName string - Name of the DataStore
    @param key string - Entry key
    @return boolean - true on success
]]
function DataStore:deleteEntry(datastoreName, key)
    local url = self._baseUrl
        .. "/standard-datastores/datastore/entries/entry"
        .. "?datastoreName=" .. Platform.urlEncode(datastoreName)
        .. "&entryKey=" .. Platform.urlEncode(key)
        .. "&scope=" .. Platform.urlEncode(self._scope)

    local response = Platform.request({
        url = url,
        method = "DELETE",
        headers = {
            ["x-api-key"] = self._apiKey,
        },
    })

    if response.statusCode ~= 204 and response.statusCode ~= 200 then
        error("[Warren.OpenCloud.DataStore] deleteEntry failed ("
            .. response.statusCode .. "): " .. response.body)
    end

    return true
end

--[[
    List entries in a DataStore.

    @param datastoreName string - Name of the DataStore
    @param options table? - { prefix = string?, limit = number?, cursor = string? }
    @return table - { keys = {string}, nextCursor = string? }
]]
function DataStore:listEntries(datastoreName, options)
    options = options or {}

    local url = self._baseUrl
        .. "/standard-datastores/datastore/entries"
        .. "?datastoreName=" .. Platform.urlEncode(datastoreName)
        .. "&scope=" .. Platform.urlEncode(self._scope)

    if options.prefix then
        url = url .. "&prefix=" .. Platform.urlEncode(options.prefix)
    end
    if options.limit then
        url = url .. "&limit=" .. tostring(options.limit)
    end
    if options.cursor then
        url = url .. "&cursor=" .. Platform.urlEncode(options.cursor)
    end

    local response = Platform.request({
        url = url,
        method = "GET",
        headers = {
            ["x-api-key"] = self._apiKey,
        },
    })

    if response.statusCode ~= 200 then
        error("[Warren.OpenCloud.DataStore] listEntries failed ("
            .. response.statusCode .. "): " .. response.body)
    end

    local data = Platform.jsonDecode(response.body)
    return {
        keys = data.keys or {},
        nextCursor = data.nextPageCursor,
    }
end

--[[
    List all DataStores in the universe.

    @param options table? - { prefix = string?, limit = number?, cursor = string? }
    @return table - { datastores = {table}, nextCursor = string? }
]]
function DataStore:listDataStores(options)
    options = options or {}

    local url = self._baseUrl .. "/standard-datastores"

    local params = {}
    if options.prefix then
        table.insert(params, "prefix=" .. Platform.urlEncode(options.prefix))
    end
    if options.limit then
        table.insert(params, "limit=" .. tostring(options.limit))
    end
    if options.cursor then
        table.insert(params, "cursor=" .. Platform.urlEncode(options.cursor))
    end
    if #params > 0 then
        url = url .. "?" .. table.concat(params, "&")
    end

    local response = Platform.request({
        url = url,
        method = "GET",
        headers = {
            ["x-api-key"] = self._apiKey,
        },
    })

    if response.statusCode ~= 200 then
        error("[Warren.OpenCloud.DataStore] listDataStores failed ("
            .. response.statusCode .. "): " .. response.body)
    end

    local data = Platform.jsonDecode(response.body)
    return {
        datastores = data.datastores or {},
        nextCursor = data.nextPageCursor,
    }
end

return DataStore
