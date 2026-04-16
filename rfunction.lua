-- CONFIG
local DefaultWebhookURL = ""
local LogServerURL = ""

-- Prevent duplicate execution
if _G.FishMonitorLoaded then
    warn("[FISH LOGGER] Script already running! Please close the existing one first.")
    return
end
_G.FishMonitorLoaded = true

----------------------------------------------------------------
-- SERVICES (HARUS DI PALING ATAS)
----------------------------------------------------------------

local Players           = game:GetService("Players")
local TextChatService   = game:GetService("TextChatService")
local HttpService       = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")
local UserInputService  = game:GetService("UserInputService")
local Player            = Players.LocalPlayer
local PlayerGui         = Player:WaitForChild("PlayerGui")

----------------------------------------------------------------
-- SESSION MANAGEMENT
----------------------------------------------------------------

-- Custom UUID Generator
local function generateUUID()
    local template = 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'
    return string.gsub(template, '[xy]', function(c)
        local v = (c == 'x') and math.random(0, 0xf) or math.random(8, 0xb)
        return string.format('%x', v)
    end)
end

local SessionUUID = generateUUID()
local SyncInterval = 5
local LastSyncTime = 0
local CurrentLicenseKey = ""
local CurrentLicenseOwner = "Unknown"
local CurrentLicenseExpires = "-"
local currentWebhookURL = DefaultWebhookURL
local populationWebhookURL = ""
local Theme
local isAuthenticated = false
local isSending = true
local licensedTo = "Unknown"
local populationDcfcConnected = false
local populationMonitorRunning = true
local populationIntervalSeconds = 10
local populationCycleLabel
local populationStatusLabel
local populationToggleButton
local populationAddedConnection
local populationRemovingConnection
local populationSeenPlayers = {}
local pendingPopulationJoined = {}
local pendingPopulationLeft = {}

local CONFIG_FOLDER = "rennb_private"
local CONFIG_FILE = CONFIG_FOLDER .. "/fish_logger_config.json"

local function getExploitFunc(name)
    local value = rawget(_G, name)
    if type(value) == "function" then
        return value
    end

    value = rawget(getgenv and getgenv() or {}, name)
    if type(value) == "function" then
        return value
    end

    return rawget(shared or {}, name)
end

local function ensureConfigFolder()
    local isFolderFunc = getExploitFunc("isfolder")
    local makeFolderFunc = getExploitFunc("makefolder")

    if type(makeFolderFunc) ~= "function" then
        return false
    end

    if type(isFolderFunc) == "function" then
        local ok, exists = pcall(isFolderFunc, CONFIG_FOLDER)
        if ok and exists then
            return true
        end
    end

    pcall(makeFolderFunc, CONFIG_FOLDER)
    return true
end

local function loadLocalConfig()
    local isFileFunc = getExploitFunc("isfile")
    local readFileFunc = getExploitFunc("readfile")
    if type(isFileFunc) ~= "function" or type(readFileFunc) ~= "function" then
        return
    end

    local okExists, exists = pcall(isFileFunc, CONFIG_FILE)
    if not okExists or not exists then
        return
    end

    local okRead, raw = pcall(readFileFunc, CONFIG_FILE)
    if not okRead or type(raw) ~= "string" or raw == "" then
        return
    end

    local okDecode, data = pcall(HttpService.JSONDecode, HttpService, raw)
    if not okDecode or type(data) ~= "table" then
        warn("[FISH LOGGER] Failed to decode local config.")
        return
    end

    currentWebhookURL = tostring(data.webhook_url or currentWebhookURL or "")
    populationWebhookURL = tostring(data.population_webhook_url or populationWebhookURL or "")
end

local function saveLocalConfig()
    local writeFileFunc = getExploitFunc("writefile")
    if type(writeFileFunc) ~= "function" then
        return false
    end

    ensureConfigFolder()

    local payload = {
        webhook_url = currentWebhookURL or "",
        population_webhook_url = populationWebhookURL or ""
    }

    local okEncode, encoded = pcall(HttpService.JSONEncode, HttpService, payload)
    if not okEncode then
        warn("[FISH LOGGER] Failed to encode local config.")
        return false
    end

    local okWrite = pcall(writeFileFunc, CONFIG_FILE, encoded)
    if not okWrite then
        warn("[FISH LOGGER] Failed to save local config.")
        return false
    end

    return true
end

loadLocalConfig()

local function refreshSlotInfo()
    return
end

local function sendLogToServer(action, additionalData)
    return true, nil
end

local function startSyncLoop()
    return
end

----------------------------------------------------------------
-- DESIGN SYSTEM (CONSISTENT SPACING & SIZING)
----------------------------------------------------------------

local Spacing = {
    xs = 4,
    sm = 8,
    md = 12,
    lg = 16,
    xl = 20,
    xxl = 24
}

local FontSize = {
    caption = 10,
    body = 12,
    subtitle = 14,
    title = 16
}

local Radius = {
    small = 8,
    medium = 12,
    large = 16
}

local ElementHeight = {
    input   = 34,
    button  = 34,
    header  = 52,
    section = 28
}

Theme = {
    bg           = Color3.fromRGB(14, 18, 24),
    surface      = Color3.fromRGB(21, 27, 35),
    surface2     = Color3.fromRGB(29, 36, 46),
    stroke       = Color3.fromRGB(57, 67, 80),
    text         = Color3.fromRGB(241, 244, 248),
    textDim      = Color3.fromRGB(154, 163, 174),
    accent       = Color3.fromRGB(100, 124, 167),
    accentStrong = Color3.fromRGB(80, 100, 138),
    brandA       = Color3.fromRGB(255, 196, 64),
    brandB       = Color3.fromRGB(255, 136, 24),
    brandText    = Color3.fromRGB(34, 24, 8),
    good         = Color3.fromRGB(102, 238, 146),
    warn         = Color3.fromRGB(214, 168, 88),
    bad          = Color3.fromRGB(232, 92, 104)
}

----------------------------------------------------------------
-- RARITY & FISH DATA
----------------------------------------------------------------

local RarityByRGB = {
    ["rgb(255, 185, 43)"] = "Legendary",
    ["rgb(255, 25, 25)"]  = "Mythical",
    ["rgb(24, 255, 152)"] = "Secret",
    ["rgb(0, 0, 0)"]      = "Forgotten"
}

local RarityColors = {
    ["Legendary"] = 16766763,
    ["Mythical"]  = 16719129,
    ["Secret"]    = 1622168,
    ["Forgotten"] = 5793266,
    ["Custom"] = 5793266
}

local Mutations = {
    "Galaxy","Corrupt","Gemstone","Ghost","Lightning","Fairy Dust","Gold","Midnight",
    "Radioactive","Stone","Holographic","Albino","Bloodmoon","Sandy","Acidic",
    "Color Burn","Festive","Frozen","Leviathan Rage","Crystalized","Cupid","Heartbreak","Carrot","Pastel","Blood Moon","Moon Fragment","Purple Moon","Cupid"
}

----------------------------------------------------------------
-- FISH DATABASE
----------------------------------------------------------------

local FishDatabase = {}
local FishIndexByNormalizedName = {}
local ItemVisualDatabase = {}
local ItemVisualIndexByNormalizedName = {}
local MODULE_REQUIRE_TIMEOUT = 0.35
local MODULE_DECOMPILE_TIMEOUT = 0.75

local function normalizeFishName(name)
    if not name then
        return ""
    end
    local normalized = tostring(name):lower()
    normalized = normalized:gsub("[%p_]", " ")
    normalized = normalized:gsub("%s+", " ")
    normalized = normalized:match("^%s*(.-)%s*$") or ""
    return normalized
end

local function runWithTimeout(timeoutSeconds, fn)
    local done = false
    local ok = false
    local result = nil

    task.spawn(function()
        ok, result = pcall(fn)
        done = true
    end)

    local deadline = os.clock() + (timeoutSeconds or 0.25)
    while not done and os.clock() < deadline do
        task.wait()
    end

    if not done then
        return false, nil, true
    end
    return ok, result, false
end

local function getModuleSourceText(moduleScript)
    local sourceText = nil
    local okDirect, direct = pcall(function()
        return moduleScript.Source
    end)
    if okDirect and type(direct) == "string" and direct ~= "" then
        sourceText = direct
    end

    if (not sourceText or sourceText == "") and decompile then
        local okDec, dec = runWithTimeout(MODULE_DECOMPILE_TIMEOUT, function()
            return decompile(moduleScript)
        end)
        if okDec and type(dec) == "string" and dec ~= "" then
            sourceText = dec
        end
    end
    return sourceText
end

local function parseFishFromModuleSource(sourceText, moduleName)
    if type(sourceText) ~= "string" or sourceText == "" then
        return nil
    end

    local itemType = sourceText:match('Type%s*=%s*"([^"]+)"') or sourceText:match("Type%s*=%s*'([^']+)'")
    if itemType ~= "Fish" then
        return nil
    end

    local name = sourceText:match('Name%s*=%s*"([^"]+)"') or sourceText:match("Name%s*=%s*'([^']+)'") or moduleName
    local icon = sourceText:match('Icon%s*=%s*"([^"]+)"') or sourceText:match("Icon%s*=%s*'([^']+)'") or ""
    local idStr = sourceText:match("Id%s*=%s*(%d+)")

    return {
        Name = name,
        Icon = icon,
        Tier = "Unknown",
        SellPrice = 0,
        Id = idStr and tonumber(idStr) or 0
    }
end

local function parseItemVisualFromModuleSource(sourceText, moduleName)
    if type(sourceText) ~= "string" or sourceText == "" then
        return nil
    end

    local name = sourceText:match('Name%s*=%s*"([^"]+)"') or sourceText:match("Name%s*=%s*'([^']+)'") or moduleName
    local icon = sourceText:match('Icon%s*=%s*"([^"]+)"') or sourceText:match("Icon%s*=%s*'([^']+)'") or ""
    local idStr = sourceText:match("Id%s*=%s*(%d+)")
    local itemType = sourceText:match('Type%s*=%s*"([^"]+)"') or sourceText:match("Type%s*=%s*'([^']+)'") or "Unknown"

    if name == "" and icon == "" then
        return nil
    end

    return {
        Name = name,
        Icon = icon,
        Id = idStr and tonumber(idStr) or 0,
        Type = itemType
    }
end

local function addItemVisualEntry(entry)
    if not entry or not entry.Name or entry.Name == "" then
        return false
    end

    ItemVisualDatabase[entry.Name] = entry
    ItemVisualIndexByNormalizedName[normalizeFishName(entry.Name)] = entry
    return true
end

local function isEnchantStoneMatch(itemName)
    local normalized = normalizeFishName(itemName)
    return normalized == "eggy enchant stone"
        or normalized:find("enchant stone", 1, true) ~= nil
end

local function isEggyEnchantStoneMatch(itemName)
    return normalizeFishName(itemName) == "eggy enchant stone"
end

local function buildFishDatabase()
    local success, ItemsFolder = pcall(function()
        return ReplicatedStorage:WaitForChild("Items", 5)
    end)

    if not success or not ItemsFolder then
        warn("[FISH LOGGER] Could not find Items folder in ReplicatedStorage")
        return
    end

    FishDatabase = {}
    FishIndexByNormalizedName = {}
    ItemVisualDatabase = {}
    ItemVisualIndexByNormalizedName = {}

    local fishCount = 0
    local itemVisualCount = 0
    for _, item in ipairs(ItemsFolder:GetDescendants()) do
        if item:IsA("ModuleScript") then
            local ok, data = runWithTimeout(MODULE_REQUIRE_TIMEOUT, function()
                return require(item)
            end)
            if ok and data and data.Data then
                local itemData = data.Data
                if itemData.Name then
                    itemVisualCount += addItemVisualEntry({
                        Name = itemData.Name,
                        Icon = itemData.Icon or "",
                        Id = itemData.Id or 0,
                        Type = itemData.Type or "Unknown"
                    }) and 1 or 0
                end

                if itemData.Type == "Fish" and itemData.Name then
                    local entry = {
                        Name      = itemData.Name,
                        Icon      = itemData.Icon or "",
                        Tier      = itemData.Tier or "Unknown",
                        SellPrice = data.SellPrice or 0,
                        Id        = itemData.Id or 0
                    }
                    FishDatabase[itemData.Name] = entry
                    FishIndexByNormalizedName[normalizeFishName(itemData.Name)] = entry
                    fishCount += 1
                end
            else
                local sourceText = getModuleSourceText(item)
                local fallbackVisual = parseItemVisualFromModuleSource(sourceText, item.Name)
                itemVisualCount += addItemVisualEntry(fallbackVisual) and 1 or 0

                local fallback = parseFishFromModuleSource(sourceText, item.Name)
                if fallback and fallback.Name then
                    FishDatabase[fallback.Name] = fallback
                    FishIndexByNormalizedName[normalizeFishName(fallback.Name)] = fallback
                    fishCount += 1
                end
            end
        end
    end

    print("[FISH LOGGER] Loaded", fishCount, "fish into database")
    print("[FISH LOGGER] Loaded", itemVisualCount, "item visuals into database")
end
local function cleanFishName(fishName)
    local cleaned = fishName

    for _, mutation in ipairs(Mutations) do
        local pattern = mutation:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
        cleaned = cleaned:gsub(pattern, "")
        cleaned = cleaned:gsub(pattern:upper(), "")
        cleaned = cleaned:gsub(pattern:lower(), "")
    end

    local prefixes = {"Big","BIG","Shiny","SHINY","Shining","SHINING","Sparkling","SPARKLING"}
    for _, prefix in ipairs(prefixes) do
        cleaned = cleaned:gsub(prefix, "")
    end

    cleaned = cleaned:gsub("%s+", " ")
    cleaned = cleaned:match("^%s*(.-)%s*$")

    return cleaned
end

local ForgottenFishAliases = {
    "sea eater",
    "the sea eater",
    "forgotten sea eater",
    "thunderzilla",
    "the thunderzilla",
    "forgotten thunderzilla"
}

local function isForgottenAliasMatch(candidate, alias)
    if candidate == "" or alias == "" then
        return false
    end

    if candidate == alias then
        return true
    end

    return candidate:find(alias, 1, true) ~= nil
end

local function isForgottenFishMatch(fishName)
    local normalizedRaw = normalizeFishName(fishName)
    local normalizedCleaned = normalizeFishName(cleanFishName(fishName))

    for _, alias in ipairs(ForgottenFishAliases) do
        if isForgottenAliasMatch(normalizedRaw, alias) or isForgottenAliasMatch(normalizedCleaned, alias) then
            return true
        end
    end

    return false
end

local function extractAssetId(iconString)
    if not iconString or iconString == "" then
        return nil
    end
    return iconString:match("rbxassetid://(%d+)")
        or iconString:match("id=(%d+)")
        or iconString:match("(%d+)")
end

local DEFAULT_FISH_IMAGE = "https://i.ibb.co/q38LKrcJ/image.png"
local THUMBNAIL_RETRY_COUNT = 10
local THUMBNAIL_RETRY_DELAY = 0.75

local function getThumbnailURL(fishName)
    local cleanedName = cleanFishName(fishName)
    local fishData    = FishDatabase[cleanedName]
        or FishIndexByNormalizedName[normalizeFishName(cleanedName)]
        or FishIndexByNormalizedName[normalizeFishName(fishName)]
    local itemData = fishData
        or ItemVisualDatabase[cleanedName]
        or ItemVisualIndexByNormalizedName[normalizeFishName(cleanedName)]
        or ItemVisualIndexByNormalizedName[normalizeFishName(fishName)]

    if not itemData or not itemData.Icon then
        return DEFAULT_FISH_IMAGE
    end

    local assetId = extractAssetId(itemData.Icon)
    if not assetId then
        return DEFAULT_FISH_IMAGE
    end

    local requestFunc = (syn and syn.request) or (http and http.request) or http_request or (fluxus and fluxus.request) or request
    if not requestFunc then
        -- Fallback langsung ke endpoint thumbnail Roblox agar tetap dapat gambar.
        return string.format("https://www.roblox.com/asset-thumbnail/image?assetId=%s&width=420&height=420&format=png", assetId)
    end

    local url = string.format(
        "https://thumbnails.roblox.com/v1/assets?assetIds=%s&returnPolicy=PlaceHolder&size=420x420&format=Png&isCircular=false",
        assetId
    )

    for attempt = 1, THUMBNAIL_RETRY_COUNT do
        local success, response = pcall(function()
            return requestFunc({
                Url    = url,
                Method = "GET"
            })
        end)

        if success and response and response.StatusCode == 200 then
            local jsonSuccess, jsonData = pcall(function()
                return HttpService:JSONDecode(response.Body)
            end)

            local assetData = jsonSuccess and jsonData and jsonData.data and jsonData.data[1]
            if assetData and assetData.imageUrl and assetData.imageUrl ~= "" then
                if assetData.state == "Completed" then
                    return assetData.imageUrl
                end

                if attempt == THUMBNAIL_RETRY_COUNT then
                    return assetData.imageUrl
                end
            end
        end

        if attempt < THUMBNAIL_RETRY_COUNT then
            task.wait(THUMBNAIL_RETRY_DELAY)
        end
    end

    return string.format("https://www.roblox.com/asset-thumbnail/image?assetId=%s&width=420&height=420&format=png", assetId)
end

local function detectMutation(fishName)
    for _, mutation in ipairs(Mutations) do
        local pattern = mutation:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
        if fishName:upper():find(pattern:upper()) then
            return mutation
        end
    end
    return "None"
end
----------------------------------------------------------------
-- UTIL
----------------------------------------------------------------

local function stripRichText(text)
    return text:gsub("<.->", "")
end

local function extractColorFromRichText(text)
    local r, g, b = text:match('color="rgb%((%d+),%s*(%d+),%s*(%d+)%)"')
    if r and g and b then
        return Color3.fromRGB(tonumber(r), tonumber(g), tonumber(b)), string.format("rgb(%s, %s, %s)", r, g, b)
    end
    local hex = text:match('color="#(%x+)"')
    if hex and #hex == 6 then
        local rh = tonumber(hex:sub(1,2), 16)
        local gh = tonumber(hex:sub(3,4), 16)
        local bh = tonumber(hex:sub(5,6), 16)
        return Color3.fromRGB(rh, gh, bh), string.format("rgb(%d, %d, %d)", rh, gh, bh)
    end
    return Color3.fromRGB(200, 200, 200), "rgb(200, 200, 200)"
end

local function normalizeRGBKey(rgbString)
    if type(rgbString) ~= "string" then
        return ""
    end

    local r, g, b = rgbString:match("rgb%((%d+),%s*(%d+),%s*(%d+)%)")
    if not r or not g or not b then
        return rgbString:lower():gsub("%s+", "")
    end

    return string.format("rgb(%d,%d,%d)", tonumber(r), tonumber(g), tonumber(b))
end

local function getRarityFromRGB(rgbString)
    local direct = RarityByRGB[rgbString]
    if direct then
        return direct
    end

    local normalizedTarget = normalizeRGBKey(rgbString)
    if normalizedTarget == "" then
        return nil
    end

    for rgbKey, rarity in pairs(RarityByRGB) do
        if normalizeRGBKey(rgbKey) == normalizedTarget then
            return rarity
        end
    end

    return nil
end

local function parseServerMessage(text)
    local cleanText = stripRichText(text)
    if not cleanText:match("^%[Server%]:") then return nil end

    local playerName, fishName, weight, chance =
        cleanText:match("%[Server%]:%s*(.-)%s+obtained%s+an?%s+(.-)%s+%((.-)%)%s+with%s+a%s+(.-)%s+chance!")

    if playerName and fishName and weight and chance then
        local _, rgbStr = extractColorFromRichText(text)
        return {
            player    = playerName,
            fish      = fishName,
            weight    = weight,
            chance    = chance,
            rgbString = rgbStr,
            time      = os.date("%d/%m/%Y %H:%M")
        }
    end

    playerName, fishName, chance =
        cleanText:match("%[Server%]:%s*(.-)%s+obtained%s+an?%s+(.-)%s+with%s+a%s+(.-)%s+chance!")

    if playerName and fishName and chance then
        local _, rgbStr = extractColorFromRichText(text)
        return {
            player    = playerName,
            fish      = fishName,
            weight    = "N/A",
            chance    = chance,
            rgbString = rgbStr,
            time      = os.date("%d/%m/%Y %H:%M")
        }
    end

    return nil
end

----------------------------------------------------------------
-- DISCORD WEBHOOK
----------------------------------------------------------------

isSending         = true
isAuthenticated   = false
licensedTo        = "Unknown"

local botName   = DefaultBotName
local botAvatar = DefaultBotAvatar

-- MODIFIKASI: Tambahkan 2 filter baru
local rarityFilters = {
    ["Legendary"] = false,
    ["Mythical"]  = true,
    ["Secret"]    = true,
    ["Legend (Crystalized)"] = true,
    ["Ruby (Gemstone)"] = true,
    ["Eggy Enchant Stone"] = true,
    ["Forgotten"] = true
}

local webhookWarningTime = 0

local function getRequestFunc()
    return (syn and syn.request) or (http and http.request) or http_request or (fluxus and fluxus.request) or request
end

local function sendToDiscord(webhookUrl, embedData, username, avatarUrl)
    local requestFunc = getRequestFunc()
    if not requestFunc then
        warn("[FISH LOGGER] ⚠️ HTTP request function not available")
        return
    end

    local payload = {
        username   = username or botName,
        avatar_url = avatarUrl or botAvatar
    }

    for k, v in pairs(embedData) do
        payload[k] = v
    end

    local success, result = pcall(function()
        requestFunc({
            Url     = webhookUrl,
            Method  = "POST",
            Headers = {
                ["Content-Type"] = "application/json"
            },
            Body = HttpService:JSONEncode(payload)
        })
    end)

    if not success then
        warn("[FISH LOGGER] ❌ Failed to send to Discord:", result)
    end
end

local function popNow()
    return os.date("%Y-%m-%d %H:%M:%S")
end

local function buildPopulationSnapshot()
    local snapshot = {}
    for _, player in ipairs(Players:GetPlayers()) do
        snapshot[player.UserId] = {
            userId = player.UserId,
            name = player.Name
        }
    end
    return snapshot
end

local function countPopulationMap(map)
    local n = 0
    for _ in pairs(map) do
        n += 1
    end
    return n
end

local function comparePopulationSnapshots(previousSnapshot, currentSnapshot)
    local joined = {}
    local left = {}
    local stayed = {}

    for userId, data in pairs(currentSnapshot) do
        if previousSnapshot[userId] then
            stayed[userId] = data
        else
            joined[userId] = data
        end
    end

    for userId, data in pairs(previousSnapshot) do
        if not currentSnapshot[userId] then
            left[userId] = data
        end
    end

    return joined, left, stayed
end

local function mergePopulationMaps(baseMap, extraMap)
    local merged = {}

    for userId, data in pairs(baseMap or {}) do
        merged[userId] = data
    end

    for userId, data in pairs(extraMap or {}) do
        merged[userId] = data
    end

    return merged
end

local function getPopulationNames(map)
    local names = {}
    for _, data in pairs(map) do
        table.insert(names, string.format("%s (%d)", data.name, data.userId))
    end
    table.sort(names)
    return names
end

local function logPopulationList(label, map)
    local names = getPopulationNames(map)
    if #names == 0 then
        print(string.format("[POP-MONITOR] %s: -", label))
        return
    end
    print(string.format("[POP-MONITOR] %s (%d): %s", label, #names, table.concat(names, ", ")))
end

local function queuePopulationJoin(player)
    if not player or not player.UserId then
        return
    end

    local userId = player.UserId
    local payload = {
        userId = userId,
        name = player.Name
    }

    populationSeenPlayers[userId] = payload
    pendingPopulationJoined[userId] = payload
    pendingPopulationLeft[userId] = nil
end

local function queuePopulationLeft(player)
    if not player or not player.UserId then
        return
    end

    local userId = player.UserId
    local known = populationSeenPlayers[userId]
    local payload = {
        userId = userId,
        name = (known and known.name) or player.Name
    }

    populationSeenPlayers[userId] = nil
    pendingPopulationLeft[userId] = payload
    pendingPopulationJoined[userId] = nil
end

local function initializePopulationTracking()
    populationSeenPlayers = {}
    pendingPopulationJoined = {}
    pendingPopulationLeft = {}

    for _, player in ipairs(Players:GetPlayers()) do
        populationSeenPlayers[player.UserId] = {
            userId = player.UserId,
            name = player.Name
        }
    end

    if populationAddedConnection then
        populationAddedConnection:Disconnect()
    end
    if populationRemovingConnection then
        populationRemovingConnection:Disconnect()
    end

    populationAddedConnection = Players.PlayerAdded:Connect(function(player)
        queuePopulationJoin(player)
    end)

    populationRemovingConnection = Players.PlayerRemoving:Connect(function(player)
        queuePopulationLeft(player)
    end)
end

local function consumePendingPopulationEvents()
    local joined = pendingPopulationJoined
    local left = pendingPopulationLeft

    pendingPopulationJoined = {}
    pendingPopulationLeft = {}

    return joined, left
end

local function getPlayerAvatarThumbnail(userId)
    if not userId or userId <= 0 then
        return ""
    end

    local requestFunc = getRequestFunc()
    if requestFunc then
        local url = string.format(
            "https://thumbnails.roblox.com/v1/users/avatar-headshot?userIds=%d&size=420x420&format=Png&isCircular=false",
            userId
        )

        local success, response = pcall(function()
            return requestFunc({
                Url = url,
                Method = "GET"
            })
        end)

        if success and response and response.StatusCode == 200 and response.Body then
            local jsonOk, jsonData = pcall(function()
                return HttpService:JSONDecode(response.Body)
            end)

            local avatarData = jsonOk and jsonData and jsonData.data and jsonData.data[1]
            if avatarData and avatarData.imageUrl and avatarData.imageUrl ~= "" then
                return avatarData.imageUrl
            end
        end
    end

    return string.format(
        "https://tr.rbxcdn.com/180DAY-%d/420/420/AvatarHeadshot/Png/noFilter",
        userId
    )
end

local function refreshPopulationToggleUI()
    if not populationToggleButton or not populationStatusLabel then
        return
    end
    if not populationToggleButton.Parent or not populationStatusLabel.Parent then
        return
    end
    if populationDcfcConnected then
        populationToggleButton.Text = "ACTIVE"
        populationToggleButton.BackgroundColor3 = Theme.good
        populationStatusLabel.Text = "STATUS: ACTIVE"
        populationStatusLabel.TextColor3 = Theme.good
    else
        populationToggleButton.Text = "UNACTIVE"
        populationToggleButton.BackgroundColor3 = Theme.bad
        populationStatusLabel.Text = "STATUS: UNACTIVE"
        populationStatusLabel.TextColor3 = Theme.bad
    end
end

local function sendPopulationDiscordNotification(title, description, color, thumbnailUrl, fields)
    if not populationDcfcConnected then
        return
    end
    if populationWebhookURL == "" then
        return
    end

    local requestFunc = getRequestFunc()
    if not requestFunc then
        warn("[POP-MONITOR] HTTP request function not available.")
        return
    end

    local payload = {
        username = "DC/FC Monitor",
        embeds = {{
            title = title,
            description = description,
            color = color or 5793266,
            thumbnail = thumbnailUrl ~= "" and { url = thumbnailUrl } or nil,
            fields = fields,
            footer = {
                text = "#ʀᴇɴɴ-ʙ ᴀᴄᴛɪᴠᴇ ᴍᴏɴɪᴛᴏʀɪɴɢ | " .. popNow()
            }
        }}
    }

    local ok, response = pcall(function()
        return requestFunc({
            Url = populationWebhookURL,
            Method = "POST",
            Headers = {
                ["Content-Type"] = "application/json"
            },
            Body = HttpService:JSONEncode(payload)
        })
    end)

    if not ok then
        warn("[POP-MONITOR] Failed send webhook:", response)
        return
    end

    local statusCode = response and (response.StatusCode or response.Status)
    if statusCode and statusCode >= 400 then
        warn(string.format(
            "[POP-MONITOR] Discord webhook rejected request. Status: %s | Body: %s",
            tostring(statusCode),
            tostring(response.Body)
        ))
    end
end

local function sendPopulationEventsToDiscord(joined, left, cycle)
    local joinedNames = getPopulationNames(joined)
    local leftNames = getPopulationNames(left)

    if #joinedNames > 0 then
        for _, data in pairs(joined) do
            sendPopulationDiscordNotification(
                "[ RENN-SERVER ] RECONNECT DETECTED",
                string.format("Player reconnected to server.\n`%s (%d)`", data.name, data.userId),
                5763719,
                getPlayerAvatarThumbnail(data.userId),
                {
                    { name = "STATUS", value = "`RECONNECTED`", inline = true },
                    { name = "PLAYER", value = "`" .. data.name .. "`", inline = true },
                    { name = "USER ID", value = "`" .. data.userId .. "`", inline = true },
                    { name = "CYCLE", value = "`" .. cycle .. "`", inline = true }
                }
            )
        end
    end

    if #leftNames > 0 then
        for _, data in pairs(left) do
            sendPopulationDiscordNotification(
                "[ RENN-SERVER ] DISCONNECT DETECTED",
                string.format("Player disconnected from server.\n`%s (%d)`", data.name, data.userId),
                15548997,
                getPlayerAvatarThumbnail(data.userId),
                {
                    { name = "STATUS", value = "`DISCONNECTED`", inline = true },
                    { name = "PLAYER", value = "`" .. data.name .. "`", inline = true },
                    { name = "USER ID", value = "`" .. data.userId .. "`", inline = true },
                    { name = "CYCLE", value = "`" .. cycle .. "`", inline = true }
                }
            )
        end
    end
end

local function runPopulationLoop()
    initializePopulationTracking()
    local previous = buildPopulationSnapshot()
    local cycle = 0

    print(string.rep("=", 72))
    print(string.format("[POP-MONITOR] %s | Monitor started.", popNow()))
    print(string.format("[POP-MONITOR] Interval compare: %ds", populationIntervalSeconds))

    while populationMonitorRunning do
        task.wait(populationIntervalSeconds)
        cycle += 1

        local current = buildPopulationSnapshot()
        local joinedBySnapshot, leftBySnapshot, stayed = comparePopulationSnapshots(previous, current)
        local joinedByEvent, leftByEvent = consumePendingPopulationEvents()
        local joined = mergePopulationMaps(joinedBySnapshot, joinedByEvent)
        local left = mergePopulationMaps(leftBySnapshot, leftByEvent)

        print(string.rep("-", 72))
        print(string.format("[POP-MONITOR] %s | Cycle #%d selesai", popNow(), cycle))
        print(string.format("[POP-MONITOR] Total Sebelumnya: %d | Total Sekarang: %d", countPopulationMap(previous), countPopulationMap(current)))
        logPopulationList("JOINED", joined)
        logPopulationList("LEFT", left)
        logPopulationList("STAYED", stayed)
        print("[POP-MONITOR] Status: script berjalan normal.")

        if populationCycleLabel and populationCycleLabel.Parent then
            populationCycleLabel.Text = string.format("CYCLE: %d | Last Compare: %s", cycle, popNow())
        end

        if populationDcfcConnected and populationWebhookURL ~= "" then
            sendPopulationEventsToDiscord(joined, left, cycle)
        elseif populationDcfcConnected and populationWebhookURL == "" then
            warn("[POP-MONITOR] DC/FC CONNECT ACTIVE, tapi LINK DC kosong.")
        end

        previous = current
    end
end

-- MODIFIKASI: Fungsi untuk menentukan filter yang digunakan
local function buildCatchEmbed(catchData, rarityLabel, embedColor, options)
    options = options or {}

    local mutation = options.mutationLabel or detectMutation(catchData.fish)
    local cleanedFish = options.fishLabel or cleanFishName(catchData.fish)
    local displayRarity = options.rarityLabel or rarityLabel
    local thumbnailUrl = getThumbnailURL(catchData.fish)

    return {
        embeds = {{
            title       = "🔒 RENNBLLOYD PRIVATE - SERVER HOOK",
            description = string.format("❝ **%s** ❝ Has Obtained a ❝ **%s** ❝\n✨ 𝗖𝗢𝗡𝗚𝗥𝗔𝗧𝗨𝗟𝗔𝗧𝗜𝗢𝗡𝗦 ✨", catchData.player, catchData.fish),
            color       = embedColor,
            thumbnail   = { url = thumbnailUrl },
            fields = {
                { name = "🐳 FISH",     value = "`" .. cleanedFish      .. "`", inline = true },
                { name = "🧬 MUTATION", value = "`" .. mutation         .. "`", inline = true },
                { name = "✨ RARITY",   value = "`" .. displayRarity    .. "`", inline = true },
                { name = "👤 PLAYER",   value = "`" .. catchData.player .. "`", inline = true },
                { name = "🎲 CHANCE",   value = "`" .. catchData.chance .. "`", inline = true },
                { name = "⚖️ WEIGHT",   value = "`" .. catchData.weight .. "`", inline = true }
            },
            footer = {
                text = string.format("BY RENNB CIO KOPERASI MERAH PUTIH• %s", catchData.time)
            }
        }}
    }
end

local function sendToWebhook(catchData)
    if not isAuthenticated then return end
    if not isSending       then return end

    if not currentWebhookURL or currentWebhookURL == "" then
        local currentTime = tick()
        if (currentTime - webhookWarningTime) >= 60 then
            warn("[FISH LOGGER] ⚠️ Webhook URL is empty! Please set it in the dashboard.")
            webhookWarningTime = currentTime
        end
        return
    end

    local rarity = getRarityFromRGB(catchData.rgbString)
    if rarity == "Forgotten" then
        if not rarityFilters["Forgotten"] then
            print("[FISH LOGGER] ⭐️ Skipped: Forgotten - filter disabled")
            return
        end

        local forgottenRarity = "Forgotten"
        local forgottenEmbed = buildCatchEmbed(
            catchData,
            forgottenRarity,
            RarityColors[forgottenRarity] or RarityColors["Custom"] or 5793266
        )

        task.spawn(function()
            pcall(function()
                sendToDiscord(currentWebhookURL, forgottenEmbed, botName, botAvatar)
                print("[FISH LOGGER] ✅ Sent:", catchData.player, "→", catchData.fish, "(Filter: Forgotten)")
            end)
        end)
        return
    end

    if not rarity then return end

    local mutation = detectMutation(catchData.fish)
    local cleanedFish = cleanFishName(catchData.fish)
    
    -- LOGIKA PRIORITAS: Tentukan filter yang sesuai
    local filterToUse = nil
    
    -- Cek apakah Ruby (Gemstone)
    if rarity == "Legendary" and cleanedFish == "Ruby" and mutation == "Gemstone" then
        if rarityFilters["Ruby (Gemstone)"] and not rarityFilters["Legendary"] then
            filterToUse = "Ruby (Gemstone)"
        elseif rarityFilters["Legendary"] then
            filterToUse = "Legendary"
        elseif rarityFilters["Ruby (Gemstone)"] then
            filterToUse = "Ruby (Gemstone)"
        end
    -- Cek apakah Eggy Enchant Stone
    elseif rarity == "Mythical" and isEggyEnchantStoneMatch(catchData.fish) then
        if rarityFilters["Eggy Enchant Stone"] and not rarityFilters["Mythical"] then
            filterToUse = "Eggy Enchant Stone"
        elseif rarityFilters["Mythical"] then
            filterToUse = "Mythical"
        elseif rarityFilters["Eggy Enchant Stone"] then
            filterToUse = "Eggy Enchant Stone"
        end
    -- Cek apakah Legend (Crystalized)
    elseif rarity == "Legendary" and mutation == "Crystalized" then
        if rarityFilters["Legend (Crystalized)"] and not rarityFilters["Legendary"] then
            filterToUse = "Legend (Crystalized)"
        elseif rarityFilters["Legendary"] then
            filterToUse = "Legendary"
        elseif rarityFilters["Legend (Crystalized)"] then
            filterToUse = "Legend (Crystalized)"
        end
    -- Filter rarity biasa
    else
        if rarityFilters[rarity] then
            filterToUse = rarity
        end
    end
    
    -- Jika tidak ada filter yang aktif, skip
    if not filterToUse then
        print("[FISH LOGGER] ⭐️ Skipped:", rarity, mutation, "- filter disabled")
        return
    end

    local embedOptions = nil
    if filterToUse == "Eggy Enchant Stone" then
        embedOptions = {
            mutationLabel = "Enchant Stone"
        }
    end

    local embed = buildCatchEmbed(catchData, filterToUse, RarityColors[rarity] or 2067276, embedOptions)

    task.spawn(function()
        pcall(function()
            sendToDiscord(currentWebhookURL, embed, botName, botAvatar)
            print("[FISH LOGGER] ✅ Sent:", catchData.player, "→", catchData.fish, "(Filter:", filterToUse .. ")")
        end)
    end)
end

----------------------------------------------------------------
-- LICENSE VALIDATION
----------------------------------------------------------------

local function validateKey(inputKey)
    local details = {
        owner = Player.Name,
        expires = "Never",
        webhook_url = currentWebhookURL
    }
    return true, "Offline mode active", details.owner, details
end

----------------------------------------------------------------
-- GUI HELPER FUNCTIONS
----------------------------------------------------------------

local isBusy             = false
local interactiveObjects = {}

local function addCorner(obj, radius)
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, radius)
    corner.Parent       = obj
end

local function addStroke(obj, color, thickness)
    local stroke           = Instance.new("UIStroke")
    stroke.Color           = color
    stroke.Thickness       = thickness
    stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    stroke.Parent          = obj
    return stroke
end

local function addOceanGradient(obj, colorTop, colorBottom, rotation)
    local gradient = Instance.new("UIGradient")
    gradient.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, colorTop),
        ColorSequenceKeypoint.new(1, colorBottom)
    })
    gradient.Rotation = rotation or 90
    gradient.Parent = obj
    return gradient
end

local function applyPanelBadgeStyle(obj, stateColor)
    obj.BackgroundTransparency = 1
    obj.BackgroundColor3 = Theme.bg
    obj.TextColor3 = stateColor
end

local function makeDraggable(target, handle)
    handle = handle or target
    local dragging = false
    local dragInput = nil
    local dragStart = nil
    local startPos = nil

    handle.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = target.Position
            target:SetAttribute("_Dragged", false)
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                end
            end)
        end
    end)

    handle.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
            dragInput = input
        end
    end)

    UserInputService.InputChanged:Connect(function(input)
        if dragging and input == dragInput and dragStart and startPos then
            local delta = input.Position - dragStart
            if math.abs(delta.X) > 3 or math.abs(delta.Y) > 3 then
                target:SetAttribute("_Dragged", true)
            end
            target.Position = UDim2.new(
                startPos.X.Scale,
                startPos.X.Offset + delta.X,
                startPos.Y.Scale,
                startPos.Y.Offset + delta.Y
            )
        end
    end)
end

local function setBusy(state)
    isBusy = state
    for _, obj in ipairs(interactiveObjects) do
        if obj:IsA("TextButton") then
            obj.Active          = not state
            obj.AutoButtonColor = not state
        elseif obj:IsA("TextBox") then
            obj.Active = not state
        end
    end
end

----------------------------------------------------------------
-- GUI CREATION - MAIN CONTAINER
----------------------------------------------------------------

local screenGui       = Instance.new("ScreenGui")
screenGui.Name        = "FishMonitorAuth"
screenGui.ResetOnSpawn = false
screenGui.Parent      = PlayerGui

local function unloadScript()
    _G.FishMonitorLoaded = false
    _G.StopPopulationMonitor = nil
    isAuthenticated = false
    isSending = false
    populationMonitorRunning = false
    populationDcfcConnected = false
    if populationAddedConnection then
        populationAddedConnection:Disconnect()
        populationAddedConnection = nil
    end
    if populationRemovingConnection then
        populationRemovingConnection:Disconnect()
        populationRemovingConnection = nil
    end
    if screenGui and screenGui.Parent then
        screenGui:Destroy()
    end
end

----------------------------------------------------------------
-- AUTH FRAME (COMPACT)
----------------------------------------------------------------

local authFrame = Instance.new("Frame")
authFrame.Name                   = "AuthFrame"
authFrame.Size                   = UDim2.new(0, 380, 0, 170)
authFrame.Position               = UDim2.new(0.5, 0, 0.5, 0)
authFrame.AnchorPoint            = Vector2.new(0.5, 0.5)
authFrame.BackgroundColor3       = Theme.bg
authFrame.BorderSizePixel        = 0
authFrame.Active                 = true
authFrame.Draggable              = true
authFrame.Parent                 = screenGui
addCorner(authFrame, Radius.large)
addOceanGradient(authFrame, Color3.fromRGB(10, 44, 72), Color3.fromRGB(5, 22, 38), 90)

local authShadow = Instance.new("ImageLabel")
authShadow.Name               = "Shadow"
authShadow.BackgroundTransparency = 1
authShadow.Position           = UDim2.new(0.5, 0, 0.5, 0)
authShadow.Size               = UDim2.new(1, 24, 1, 24)
authShadow.AnchorPoint        = Vector2.new(0.5, 0.5)
authShadow.Image              = "rbxasset://textures/ui/Shadow.png"
authShadow.ImageColor3        = Color3.fromRGB(0, 0, 0)
authShadow.ImageTransparency  = 0.45
authShadow.ScaleType          = Enum.ScaleType.Slice
authShadow.SliceCenter        = Rect.new(10, 10, 118, 118)
authShadow.ZIndex             = 0
authShadow.Parent             = authFrame

local authHeader = Instance.new("Frame")
authHeader.Size              = UDim2.new(1, 0, 0, ElementHeight.header)
authHeader.BackgroundColor3  = Theme.surface2
authHeader.BorderSizePixel   = 0
authHeader.Parent            = authFrame
addCorner(authHeader, Radius.large)
addOceanGradient(authHeader, Color3.fromRGB(14, 68, 102), Color3.fromRGB(10, 42, 72), 0)

local authHeaderFix = Instance.new("Frame")
authHeaderFix.Size              = UDim2.new(1, 0, 0, Radius.large)
authHeaderFix.Position          = UDim2.new(0, 0, 1, -Radius.large)
authHeaderFix.BackgroundColor3  = Theme.surface2
authHeaderFix.BorderSizePixel   = 0
authHeaderFix.Parent            = authHeader

local authTitle = Instance.new("TextLabel")
authTitle.Size                  = UDim2.new(1, -Spacing.xl, 0, 18)
authTitle.Position              = UDim2.new(0, Spacing.lg, 0, Spacing.sm)
authTitle.BackgroundTransparency = 1
authTitle.Font                  = Enum.Font.GothamBold
authTitle.TextSize              = FontSize.title
authTitle.TextXAlignment        = Enum.TextXAlignment.Left
authTitle.TextColor3            = Theme.text
authTitle.Text                  = "Server Monitor"
authTitle.Parent                = authHeader

local authSubtitle = Instance.new("TextLabel")
authSubtitle.Size                  = UDim2.new(1, -Spacing.xl, 0, 14)
authSubtitle.Position              = UDim2.new(0, Spacing.lg, 0, 26)
authSubtitle.BackgroundTransparency = 1
authSubtitle.Font                  = Enum.Font.GothamMedium
authSubtitle.TextSize              = FontSize.caption
authSubtitle.TextXAlignment        = Enum.TextXAlignment.Left
authSubtitle.TextColor3            = Theme.textDim
authSubtitle.Text                  = "Offline auto verification"
authSubtitle.Parent                = authHeader

local authContent = Instance.new("Frame")
authContent.Size              = UDim2.new(1, -Spacing.xl*2, 1, -ElementHeight.header - Spacing.xl)
authContent.Position          = UDim2.new(0, Spacing.xl, 0, ElementHeight.header + Spacing.sm)
authContent.BackgroundTransparency = 1
authContent.Parent            = authFrame

local statusCard = Instance.new("Frame")
statusCard.Size             = UDim2.new(1, 0, 0, 82)
statusCard.Position         = UDim2.new(0, 0, 0, 8)
statusCard.BackgroundColor3 = Theme.surface
statusCard.BorderSizePixel  = 0
statusCard.Parent           = authContent
addCorner(statusCard, Radius.medium)
addOceanGradient(statusCard, Color3.fromRGB(11, 56, 86), Color3.fromRGB(8, 36, 58), 90)

local statusLabel = Instance.new("TextLabel")
statusLabel.Size                  = UDim2.new(1, -Spacing.xl, 1, -Spacing.md)
statusLabel.Position              = UDim2.new(0, Spacing.md, 0, Spacing.sm)
statusLabel.BackgroundTransparency = 1
statusLabel.Font                  = Enum.Font.GothamMedium
statusLabel.TextSize              = FontSize.body
statusLabel.TextXAlignment        = Enum.TextXAlignment.Center
statusLabel.TextYAlignment        = Enum.TextYAlignment.Center
statusLabel.TextColor3            = Theme.textDim
statusLabel.Text                  = "Reading Fish Database.."
statusLabel.TextWrapped           = true
statusLabel.Parent                = statusCard

local loadingBar = Instance.new("Frame")
loadingBar.Size                 = UDim2.new(0, 0, 0, 2)
loadingBar.Position             = UDim2.new(0, 0, 1, -2)
loadingBar.BackgroundColor3     = Theme.accent
loadingBar.BorderSizePixel      = 0
loadingBar.Visible              = false
loadingBar.Parent               = statusCard
addCorner(loadingBar, 1)

----------------------------------------------------------------
-- DASHBOARD FRAME (OPTIMIZED & COMPACT)
----------------------------------------------------------------

local dashFrame = Instance.new("Frame")
dashFrame.Name              = "DashboardFrame"
dashFrame.Size              = UDim2.new(0, 540, 0, 450)
dashFrame.Position          = UDim2.new(0.5, 0, 0.5, 0)
dashFrame.AnchorPoint       = Vector2.new(0.5, 0.5)
dashFrame.BackgroundColor3  = Theme.bg
dashFrame.BorderSizePixel   = 0
dashFrame.Active            = true
dashFrame.Draggable         = true
dashFrame.Visible           = false
dashFrame.Parent            = screenGui
addCorner(dashFrame, Radius.large)
addOceanGradient(dashFrame, Color3.fromRGB(27, 33, 42), Color3.fromRGB(12, 16, 22), 90)
addStroke(dashFrame, Theme.stroke, 1)

local dashShadow = Instance.new("ImageLabel")
dashShadow.Name               = "Shadow"
dashShadow.BackgroundTransparency = 1
dashShadow.Position           = UDim2.new(0.5, 0, 0.5, 0)
dashShadow.Size               = UDim2.new(1, 24, 1, 24)
dashShadow.AnchorPoint        = Vector2.new(0.5, 0.5)
dashShadow.Image              = "rbxasset://textures/ui/Shadow.png"
dashShadow.ImageColor3        = Color3.fromRGB(0, 0, 0)
dashShadow.ImageTransparency  = 0.45
dashShadow.ScaleType          = Enum.ScaleType.Slice
dashShadow.SliceCenter        = Rect.new(10, 10, 118, 118)
dashShadow.ZIndex             = 0
dashShadow.Parent             = dashFrame

local dashHeader = Instance.new("Frame")
dashHeader.Size              = UDim2.new(1, 0, 0, ElementHeight.header)
dashHeader.BackgroundColor3  = Theme.surface2
dashHeader.BorderSizePixel   = 0
dashHeader.Parent            = dashFrame
addCorner(dashHeader, Radius.large)
addOceanGradient(dashHeader, Color3.fromRGB(34, 40, 50), Color3.fromRGB(22, 27, 35), 0)

local dashHeaderFix = Instance.new("Frame")
dashHeaderFix.Size              = UDim2.new(1, 0, 0, Radius.large)
dashHeaderFix.Position          = UDim2.new(0, 0, 1, -Radius.large)
dashHeaderFix.BackgroundColor3  = Theme.surface2
dashHeaderFix.BorderSizePixel   = 0
dashHeaderFix.Parent            = dashHeader

local dashTitle = Instance.new("TextLabel")
dashTitle.Size                  = UDim2.new(1, -156, 0, 22)
dashTitle.Position              = UDim2.new(0, Spacing.xl, 0, Spacing.sm)
dashTitle.BackgroundTransparency = 1
dashTitle.Font                  = Enum.Font.GothamBold
dashTitle.TextSize              = FontSize.title
dashTitle.TextXAlignment        = Enum.TextXAlignment.Left
dashTitle.TextColor3            = Theme.text
dashTitle.Text                  = "RENN SERVER MONITOR"
dashTitle.Parent                = dashHeader

local dashSubtitle = Instance.new("TextLabel")
dashSubtitle.Size                  = UDim2.new(1, -156, 0, 16)
dashSubtitle.Position              = UDim2.new(0, Spacing.xl, 0, 30)
dashSubtitle.BackgroundTransparency = 1
dashSubtitle.Font                  = Enum.Font.GothamMedium
dashSubtitle.TextSize              = FontSize.caption
dashSubtitle.TextXAlignment        = Enum.TextXAlignment.Left
dashSubtitle.TextColor3            = Theme.textDim
dashSubtitle.Text                  = "Fish monitoring and separated DC/FC logging"
dashSubtitle.Parent                = dashHeader

local hideBtn = Instance.new("TextButton")
hideBtn.Size                  = UDim2.new(0, 88, 0, 30)
hideBtn.Position              = UDim2.new(1, -88 - Spacing.lg, 0.5, -15)
hideBtn.BackgroundColor3      = Theme.surface
hideBtn.BorderSizePixel       = 0
hideBtn.Font                  = Enum.Font.GothamBold
hideBtn.TextSize              = FontSize.body
hideBtn.TextColor3            = Theme.text
hideBtn.Text                  = "MINIMIZE"
hideBtn.AutoButtonColor       = true
hideBtn.Parent                = dashHeader
addCorner(hideBtn, Radius.medium)
addStroke(hideBtn, Theme.stroke, 1)
table.insert(interactiveObjects, hideBtn)

local minimizeBtn = Instance.new("TextButton")
minimizeBtn.Name            = "MinimizeBtn"
minimizeBtn.Size            = UDim2.new(0, 64, 0, 32)
minimizeBtn.Position        = UDim2.new(0, Spacing.lg, 0.5, -16)
minimizeBtn.AnchorPoint     = Vector2.new(0, 0.5)
minimizeBtn.BackgroundTransparency = 1
minimizeBtn.BackgroundColor3= Theme.bg
minimizeBtn.BorderSizePixel = 0
minimizeBtn.Font            = Enum.Font.GothamBlack
minimizeBtn.TextSize        = 20
minimizeBtn.TextColor3      = Theme.good
minimizeBtn.Text            = "⚡ R"
minimizeBtn.AutoButtonColor = true
minimizeBtn.Active          = true
minimizeBtn.Visible         = false
minimizeBtn.Parent          = screenGui
applyPanelBadgeStyle(minimizeBtn, Theme.good)
makeDraggable(minimizeBtn)

minimizeBtn.MouseButton1Click:Connect(function()
    if minimizeBtn:GetAttribute("_Dragged") then
        minimizeBtn:SetAttribute("_Dragged", false)
        return
    end
    dashFrame.Visible   = true
    minimizeBtn.Visible = false
end)

hideBtn.MouseButton1Click:Connect(function()
    dashFrame.Visible   = false
    minimizeBtn.Visible = true
end)

local dashContent = Instance.new("Frame")
dashContent.Size              = UDim2.new(1, -Spacing.lg*2, 1, -ElementHeight.header - Spacing.lg*2)
dashContent.Position          = UDim2.new(0, Spacing.lg, 0, ElementHeight.header + Spacing.md)
dashContent.BackgroundTransparency = 1
dashContent.Parent            = dashFrame

local tabBar = Instance.new("Frame")
tabBar.Size = UDim2.new(1, 0, 0, 40)
tabBar.BackgroundColor3 = Theme.surface
tabBar.BorderSizePixel = 0
tabBar.Parent = dashContent
addCorner(tabBar, Radius.medium)
addStroke(tabBar, Theme.stroke, 1)

local fishTabBtn = Instance.new("TextButton")
fishTabBtn.Size = UDim2.new(0.5, -Spacing.md, 1, -Spacing.sm)
fishTabBtn.Position = UDim2.new(0, Spacing.xs, 0, Spacing.xs)
fishTabBtn.BackgroundColor3 = Theme.accent
fishTabBtn.BorderSizePixel = 0
fishTabBtn.Font = Enum.Font.GothamBold
fishTabBtn.TextSize = FontSize.body
fishTabBtn.TextColor3 = Theme.text
fishTabBtn.Text = "Fish Monitor"
fishTabBtn.AutoButtonColor = true
fishTabBtn.Parent = tabBar
addCorner(fishTabBtn, Radius.medium)
addStroke(fishTabBtn, Theme.stroke, 1)
table.insert(interactiveObjects, fishTabBtn)

local dcfcTabBtn = Instance.new("TextButton")
dcfcTabBtn.Size = UDim2.new(0.5, -Spacing.md, 1, -Spacing.sm)
dcfcTabBtn.Position = UDim2.new(0.5, Spacing.xs, 0, Spacing.xs)
dcfcTabBtn.BackgroundColor3 = Theme.surface2
dcfcTabBtn.BorderSizePixel = 0
dcfcTabBtn.Font = Enum.Font.GothamBold
dcfcTabBtn.TextSize = FontSize.body
dcfcTabBtn.TextColor3 = Theme.textDim
dcfcTabBtn.Text = "DC/FC"
dcfcTabBtn.AutoButtonColor = true
dcfcTabBtn.Parent = tabBar
addCorner(dcfcTabBtn, Radius.medium)
addStroke(dcfcTabBtn, Theme.stroke, 1)
table.insert(interactiveObjects, dcfcTabBtn)

local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.new(1, 0, 0, ElementHeight.button)
closeBtn.Position = UDim2.new(0, 0, 1, -ElementHeight.button)
closeBtn.BackgroundColor3 = Theme.surface
closeBtn.BorderSizePixel = 0
closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextSize = FontSize.body
closeBtn.TextColor3 = Theme.text
closeBtn.Text = "CLOSE PANEL"
closeBtn.AutoButtonColor = true
closeBtn.Parent = dashContent
addCorner(closeBtn, Radius.medium)
addStroke(closeBtn, Theme.stroke, 1)
table.insert(interactiveObjects, closeBtn)

local tabPages = Instance.new("Frame")
tabPages.Size = UDim2.new(1, 0, 1, -(40 + Spacing.md + ElementHeight.button + Spacing.sm))
tabPages.Position = UDim2.new(0, 0, 0, 40 + Spacing.md)
tabPages.BackgroundTransparency = 1
tabPages.Parent = dashContent

local fishTabPage = Instance.new("Frame")
fishTabPage.Size = UDim2.new(1, 0, 1, 0)
fishTabPage.BackgroundTransparency = 1
fishTabPage.Parent = tabPages

local dcfcTabPage = Instance.new("Frame")
dcfcTabPage.Size = UDim2.new(1, 0, 1, 0)
dcfcTabPage.BackgroundTransparency = 1
dcfcTabPage.Visible = false
dcfcTabPage.Parent = tabPages

local fishTabLayout = Instance.new("UIListLayout")
fishTabLayout.Padding = UDim.new(0, Spacing.md)
fishTabLayout.SortOrder = Enum.SortOrder.LayoutOrder
fishTabLayout.Parent = fishTabPage

local dcfcTabLayout = Instance.new("UIListLayout")
dcfcTabLayout.Padding = UDim.new(0, Spacing.md)
dcfcTabLayout.SortOrder = Enum.SortOrder.LayoutOrder
dcfcTabLayout.Parent = dcfcTabPage

local function setActiveTab(tabName)
    local isFish = tabName == "fish"
    fishTabPage.Visible = isFish
    dcfcTabPage.Visible = not isFish

    fishTabBtn.BackgroundColor3 = isFish and Theme.accent or Theme.surface2
    fishTabBtn.TextColor3 = isFish and Theme.text or Theme.textDim
    dcfcTabBtn.BackgroundColor3 = isFish and Theme.surface2 or Theme.accent
    dcfcTabBtn.TextColor3 = isFish and Theme.textDim or Theme.text
end

fishTabBtn.MouseButton1Click:Connect(function()
    if isBusy then return end
    setActiveTab("fish")
end)

dcfcTabBtn.MouseButton1Click:Connect(function()
    if isBusy then return end
    setActiveTab("dcfc")
end)

local function makeSection(parentFrame, titleText, order)
    local section            = Instance.new("Frame")
    section.Size             = UDim2.new(1, 0, 0, 0)
    section.BackgroundColor3 = Theme.surface
    section.BorderSizePixel  = 0
    section.LayoutOrder      = order
    section.Parent           = parentFrame
    addCorner(section, Radius.medium)
    addOceanGradient(section, Color3.fromRGB(31, 37, 46), Color3.fromRGB(20, 24, 31), 90)
    addStroke(section, Theme.stroke, 1)

    local label = Instance.new("TextLabel")
    label.Name                  = "SectionLabel"
    label.Size                  = UDim2.new(1, -Spacing.lg*2, 0, 16)
    label.Position              = UDim2.new(0, Spacing.lg, 0, Spacing.md)
    label.BackgroundTransparency = 1
    label.Font                  = Enum.Font.GothamBold
    label.TextSize              = FontSize.body
    label.TextXAlignment        = Enum.TextXAlignment.Left
    label.TextColor3            = Theme.text
    label.Text                  = string.upper(titleText)
    label.Parent                = section

    local divider = Instance.new("Frame")
    divider.Size = UDim2.new(1, -Spacing.lg*2, 0, 1)
    divider.Position = UDim2.new(0, Spacing.lg, 0, 34)
    divider.BackgroundColor3 = Theme.stroke
    divider.BorderSizePixel = 0
    divider.Parent = section

    local body = Instance.new("Frame")
    body.Name                   = "SectionBody"
    body.Size                   = UDim2.new(1, -Spacing.lg*2, 1, -46)
    body.Position               = UDim2.new(0, Spacing.lg, 0, 42)
    body.BackgroundTransparency = 1
    body.Parent                 = section

    return section, body
end

local monitorSection, monitorBody = makeSection(fishTabPage, "Monitoring", 1)
monitorSection.Size = UDim2.new(1, 0, 0, 176)

local monitorRow = Instance.new("Frame")
monitorRow.Size                  = UDim2.new(1, 0, 0, ElementHeight.input)
monitorRow.BackgroundTransparency = 1
monitorRow.Parent                = monitorBody

local monitorLabel = Instance.new("TextLabel")
monitorLabel.Size                  = UDim2.new(1, -96, 1, 0)
monitorLabel.BackgroundTransparency = 1
monitorLabel.Font                  = Enum.Font.GothamMedium
monitorLabel.TextSize              = FontSize.body
monitorLabel.TextXAlignment        = Enum.TextXAlignment.Left
monitorLabel.TextColor3            = Theme.textDim
monitorLabel.Text                  = "Send catch activity to Discord"
monitorLabel.Parent                = monitorRow

local toggleBtn = Instance.new("TextButton")
toggleBtn.Size                  = UDim2.new(0, 84, 0, ElementHeight.input)
toggleBtn.Position              = UDim2.new(1, -84, 0, 0)
toggleBtn.BackgroundColor3      = Theme.good
toggleBtn.BorderSizePixel       = 0
toggleBtn.Font                  = Enum.Font.GothamBold
toggleBtn.TextSize              = FontSize.body
toggleBtn.TextColor3            = Theme.text
toggleBtn.Text                  = "ON"
toggleBtn.AutoButtonColor       = true
toggleBtn.Parent                = monitorRow
addCorner(toggleBtn, Radius.medium)
addStroke(toggleBtn, Theme.stroke, 1)
table.insert(interactiveObjects, toggleBtn)

-- MODIFIKASI: Baris switch pertama
local rarityRow = Instance.new("Frame")
rarityRow.Size                  = UDim2.new(1, 0, 0, 28)
rarityRow.Position              = UDim2.new(0, 0, 0, ElementHeight.input + Spacing.sm)
rarityRow.BackgroundTransparency = 1
rarityRow.Parent                = monitorBody

-- MODIFIKASI: Baris switch kedua
local rarityRow2 = Instance.new("Frame")
rarityRow2.Size                  = UDim2.new(1, 0, 0, 34)
rarityRow2.Position              = UDim2.new(0, 0, 0, ElementHeight.input + Spacing.sm + 28)
rarityRow2.BackgroundTransparency = 1
rarityRow2.Parent                = monitorBody

local rarityRow3 = Instance.new("Frame")
rarityRow3.Size                  = UDim2.new(1, 0, 0, 34)
rarityRow3.Position              = UDim2.new(0, 0, 0, ElementHeight.input + Spacing.sm + 62)
rarityRow3.BackgroundTransparency = 1
rarityRow3.Parent                = monitorBody

local function createRarityCheckbox(rarityName, index, color, parentFrame)
    local item = Instance.new("Frame")
    item.Size = UDim2.new(1/3, -Spacing.xs, 1, 0)
    item.Position = UDim2.new((index - 1)/3, (index > 1) and Spacing.xs or 0, 0, 0)
    
    item.BackgroundTransparency = 1
    item.Parent                = parentFrame

    local label = Instance.new("TextLabel")
    label.Size                  = UDim2.new(1, -58, 1, 0)
    label.Position              = UDim2.new(0, 0, 0, 0)
    label.BackgroundTransparency = 1
    label.Font                  = Enum.Font.GothamMedium
    label.TextSize              = 9
    label.TextXAlignment        = Enum.TextXAlignment.Left
    label.TextColor3            = Theme.text
    label.Text                  = rarityName
    label.TextScaled            = false
    label.TextWrapped           = false
    pcall(function()
        label.TextTruncate = Enum.TextTruncate.AtEnd
    end)
    label.Parent                = item

    local switch = Instance.new("TextButton")
    switch.Size                  = UDim2.new(0, 48, 0, 22)
    switch.Position              = UDim2.new(1, -48, 0.5, -11)
    switch.BackgroundColor3      = Theme.surface2
    switch.BorderSizePixel       = 0
    switch.Text                  = ""
    switch.AutoButtonColor       = true
    switch.Parent                = item
    addCorner(switch, 11)
    addStroke(switch, Theme.stroke, 1)
    addOceanGradient(switch, Color3.fromRGB(44, 50, 62), Color3.fromRGB(30, 35, 44), 0)

    local knob = Instance.new("Frame")
    knob.Size                 = UDim2.new(0, 16, 0, 16)
    knob.Position             = UDim2.new(0, 3, 0.5, -8)
    knob.BackgroundColor3     = Color3.fromRGB(230, 234, 238)
    knob.BorderSizePixel      = 0
    knob.Parent               = switch
    addCorner(knob, 8)

    local stateLabel = Instance.new("TextLabel")
    stateLabel.Size                  = UDim2.new(0, 18, 1, 0)
    stateLabel.Position              = UDim2.new(0, 15, 0, 0)
    stateLabel.BackgroundTransparency = 1
    stateLabel.Font                  = Enum.Font.GothamBold
    stateLabel.TextSize              = 8
    stateLabel.TextXAlignment        = Enum.TextXAlignment.Center
    stateLabel.TextColor3            = Theme.text
    stateLabel.Parent                = switch

    table.insert(interactiveObjects, switch)

    local function sync()
        if rarityFilters[rarityName] then
            switch.BackgroundColor3 = color
            stateLabel.Text = "ON"
            stateLabel.Position = UDim2.new(0, 8, 0, 0)
            knob.Position = UDim2.new(1, -19, 0.5, -8)
            label.TextColor3 = Theme.text
        else
            switch.BackgroundColor3 = Theme.surface2
            stateLabel.Text = "OFF"
            stateLabel.Position = UDim2.new(0, 21, 0, 0)
            knob.Position = UDim2.new(0, 3, 0.5, -8)
            label.TextColor3 = Theme.textDim
        end
    end
    sync()

    switch.MouseButton1Click:Connect(function()
        if isBusy then return end
        rarityFilters[rarityName] = not rarityFilters[rarityName]
        sync()
    end)
end

-- MODIFIKASI: Switch di baris pertama
createRarityCheckbox("Legendary", 1, Color3.fromRGB(255, 200, 80), rarityRow)
createRarityCheckbox("Mythical",  2, Color3.fromRGB(255, 100, 100), rarityRow)
createRarityCheckbox("Secret",    3, Color3.fromRGB(100, 255, 190), rarityRow)

-- MODIFIKASI: Switch di baris kedua
createRarityCheckbox("Legend (Crystalized)", 1, Color3.fromRGB(255, 100, 100), rarityRow2)
createRarityCheckbox("Ruby (Gemstone)", 2, Color3.fromRGB(255, 200, 80), rarityRow2)
createRarityCheckbox("Forgotten", 3, Color3.fromRGB(90, 210, 255), rarityRow2)
createRarityCheckbox("Eggy Enchant Stone", 1, Color3.fromRGB(255, 100, 100), rarityRow3)

local webhookSection, webhookBody = makeSection(fishTabPage, "Webhook", 2)
webhookSection.Size = UDim2.new(1, 0, 0, 96)

local webhookLabel = Instance.new("TextLabel")
webhookLabel.Size                  = UDim2.new(1, 0, 0, 12)
webhookLabel.BackgroundTransparency = 1
webhookLabel.Font                  = Enum.Font.GothamMedium
webhookLabel.TextSize              = FontSize.caption
webhookLabel.TextXAlignment        = Enum.TextXAlignment.Left
webhookLabel.TextColor3            = Theme.textDim
webhookLabel.Text                  = "Discord Webhook URL"
webhookLabel.Parent                = webhookBody

local webhookRow = Instance.new("Frame")
webhookRow.Size                  = UDim2.new(1, 0, 0, ElementHeight.input)
webhookRow.Position              = UDim2.new(0, 0, 0, 14)
webhookRow.BackgroundTransparency = 1
webhookRow.Parent                = webhookBody

local webhookBoxContainer = Instance.new("Frame")
webhookBoxContainer.Size             = UDim2.new(1, -88 - Spacing.xs, 1, 0)
webhookBoxContainer.BackgroundColor3 = Theme.surface2
webhookBoxContainer.BorderSizePixel  = 0
webhookBoxContainer.ClipsDescendants = true
webhookBoxContainer.Parent           = webhookRow
addCorner(webhookBoxContainer, Radius.medium)
addStroke(webhookBoxContainer, Theme.stroke, 1)

local webhookBox = Instance.new("TextBox")
webhookBox.Size                  = UDim2.new(1, -Spacing.md*2, 1, 0)
webhookBox.Position              = UDim2.new(0, Spacing.md, 0, 0)
webhookBox.BackgroundTransparency = 1
webhookBox.Font                  = Enum.Font.GothamMedium
webhookBox.TextSize              = FontSize.body
webhookBox.TextColor3            = Theme.text
webhookBox.TextXAlignment        = Enum.TextXAlignment.Left
webhookBox.TextYAlignment        = Enum.TextYAlignment.Center
webhookBox.ClearTextOnFocus      = false
webhookBox.TextWrapped           = false
pcall(function()
    webhookBox.TextTruncate = Enum.TextTruncate.AtEnd
end)
webhookBox.Text                  = currentWebhookURL
webhookBox.PlaceholderText       = "https://discord.com/api/webhooks/..."
webhookBox.PlaceholderColor3     = Theme.textDim
webhookBox.Parent                = webhookBoxContainer
table.insert(interactiveObjects, webhookBox)

webhookBox.FocusLost:Connect(function()
    currentWebhookURL = (webhookBox.Text or ""):gsub("^%s*(.-)%s*$", "%1")
    webhookBox.Text = currentWebhookURL
    saveLocalConfig()
    if isAuthenticated and currentWebhookURL ~= "" then
        sendLogToServer("sync", {
            license_key = CurrentLicenseKey,
            player_name = Player.Name,
            webhook_url = currentWebhookURL
        })
    end
end)

local testBtn = Instance.new("TextButton")
testBtn.Size                  = UDim2.new(0, 88, 1, 0)
testBtn.Position              = UDim2.new(1, -88, 0, 0)
testBtn.BackgroundColor3      = Theme.accent
testBtn.BorderSizePixel       = 0
testBtn.Font                  = Enum.Font.GothamBold
testBtn.TextSize              = FontSize.body
testBtn.TextColor3            = Theme.text
testBtn.Text                  = "Test"
testBtn.AutoButtonColor       = true
testBtn.Parent                = webhookRow
addCorner(testBtn, Radius.medium)
addStroke(testBtn, Theme.stroke, 1)
table.insert(interactiveObjects, testBtn)

testBtn.MouseButton1Click:Connect(function()
    if isBusy then return end
    if not currentWebhookURL or currentWebhookURL == "" then
        warn("[FISH LOGGER] Please enter a webhook URL first!")
        return
    end

    local testFishName = "CARROT Strawberry Orca"
    local cleanedFish = cleanFishName(testFishName)
    local mutation = detectMutation(testFishName)
    local thumbnailUrl = getThumbnailURL(testFishName)
    local rarity = "Secret"
    local embedColor = RarityColors[rarity] or 16766763

    local testEmbed = {
        embeds = {{
            title       = "🔒 RENNBLLOYD PRIVATE - SERVER TEST CONNECTED",
            description = string.format("❝ **%s** ❝ Has Obtained a ❝ **%s** ❝\nWEBHOOK CONNECTED !! ", Player.Name, testFishName),
            color       = embedColor,
            thumbnail   = { url = thumbnailUrl },
            fields = {
                { name = "🐳 FISH",     value = "`" .. cleanedFish .. "`",      inline = true },
                { name = "🧬 MUTATION", value = "`" .. mutation .. "`",         inline = true },
                { name = "✨ RARITY",   value = "`" .. rarity .. "`",           inline = true },
                { name = "👤 PLAYER",   value = "`" .. Player.Name .. "`",      inline = true },
                { name = "🎲 CHANCE",   value = "`1/3M`",                       inline = true },
                { name = "⚖️ WEIGHT",   value = "`310K kg`",                    inline = true }
            },
            footer = {
                text = string.format("BY RENNB CIO KOPERASI MERAH PUTIH• %s", os.date("%d/%m/%Y %H:%M"))
            }
        }}
    }

    sendToDiscord(currentWebhookURL, testEmbed, botName, botAvatar)
    print("[FISH LOGGER] 🧪 Test webhook sent with real data for:", testFishName)
end)

local populationSection, populationBody = makeSection(dcfcTabPage, "R-LOGS", 1)
populationSection.Size = UDim2.new(1, 0, 0, 184)

local populationToggleRow = Instance.new("Frame")
populationToggleRow.Size                  = UDim2.new(1, 0, 0, ElementHeight.input)
populationToggleRow.BackgroundTransparency = 1
populationToggleRow.Parent                = populationBody

local populationToggleLabel = Instance.new("TextLabel")
populationToggleLabel.Size                  = UDim2.new(1, -118, 1, 0)
populationToggleLabel.BackgroundTransparency = 1
populationToggleLabel.Font                  = Enum.Font.GothamMedium
populationToggleLabel.TextSize              = FontSize.body
populationToggleLabel.TextXAlignment        = Enum.TextXAlignment.Left
populationToggleLabel.TextColor3            = Theme.textDim
populationToggleLabel.Text                  = "DC/FC connection logging"
populationToggleLabel.Parent                = populationToggleRow

populationToggleButton = Instance.new("TextButton")
populationToggleButton.Size                  = UDim2.new(0, 108, 0, ElementHeight.input)
populationToggleButton.Position              = UDim2.new(1, -108, 0, 0)
populationToggleButton.BackgroundColor3      = Theme.bad
populationToggleButton.BorderSizePixel       = 0
populationToggleButton.Font                  = Enum.Font.GothamBold
populationToggleButton.TextSize              = FontSize.body
populationToggleButton.TextColor3            = Theme.text
populationToggleButton.Text                  = "UNACTIVE"
populationToggleButton.AutoButtonColor       = true
populationToggleButton.Parent                = populationToggleRow
addCorner(populationToggleButton, Radius.medium)
addStroke(populationToggleButton, Theme.stroke, 1)
table.insert(interactiveObjects, populationToggleButton)

local populationWebhookLabel = Instance.new("TextLabel")
populationWebhookLabel.Size                  = UDim2.new(1, 0, 0, 12)
populationWebhookLabel.Position              = UDim2.new(0, 0, 0, 44)
populationWebhookLabel.BackgroundTransparency = 1
populationWebhookLabel.Font                  = Enum.Font.GothamMedium
populationWebhookLabel.TextSize              = FontSize.caption
populationWebhookLabel.TextXAlignment        = Enum.TextXAlignment.Left
populationWebhookLabel.TextColor3            = Theme.textDim
populationWebhookLabel.Text                  = "DC/FC Webhook URL"
populationWebhookLabel.Parent                = populationBody

local populationWebhookContainer = Instance.new("Frame")
populationWebhookContainer.Size             = UDim2.new(1, 0, 0, ElementHeight.input)
populationWebhookContainer.Position         = UDim2.new(0, 0, 0, 60)
populationWebhookContainer.BackgroundColor3 = Theme.surface2
populationWebhookContainer.BorderSizePixel  = 0
populationWebhookContainer.ClipsDescendants = true
populationWebhookContainer.Parent           = populationBody
addCorner(populationWebhookContainer, Radius.medium)
addStroke(populationWebhookContainer, Theme.stroke, 1)

local populationWebhookBox = Instance.new("TextBox")
populationWebhookBox.Size                  = UDim2.new(1, -Spacing.md * 2, 1, 0)
populationWebhookBox.Position              = UDim2.new(0, Spacing.md, 0, 0)
populationWebhookBox.BackgroundTransparency = 1
populationWebhookBox.Font                  = Enum.Font.GothamMedium
populationWebhookBox.TextSize              = FontSize.body
populationWebhookBox.TextColor3            = Theme.text
populationWebhookBox.TextXAlignment        = Enum.TextXAlignment.Left
populationWebhookBox.TextYAlignment        = Enum.TextYAlignment.Center
populationWebhookBox.ClearTextOnFocus      = false
populationWebhookBox.PlaceholderText       = "https://discord.com/api/webhooks/..."
populationWebhookBox.PlaceholderColor3     = Theme.textDim
populationWebhookBox.Text                  = populationWebhookURL
populationWebhookBox.Parent                = populationWebhookContainer
table.insert(interactiveObjects, populationWebhookBox)

populationStatusLabel = Instance.new("TextLabel")
populationStatusLabel.Size                  = UDim2.new(1, 0, 0, 14)
populationStatusLabel.Position              = UDim2.new(0, 0, 0, 104)
populationStatusLabel.BackgroundTransparency = 1
populationStatusLabel.Font                  = Enum.Font.GothamBold
populationStatusLabel.TextSize              = FontSize.caption
populationStatusLabel.TextXAlignment        = Enum.TextXAlignment.Left
populationStatusLabel.TextColor3            = Theme.bad
populationStatusLabel.Text                  = "STATUS: UNACTIVE"
populationStatusLabel.Parent                = populationBody

populationCycleLabel = Instance.new("TextLabel")
populationCycleLabel.Size                  = UDim2.new(1, 0, 0, 16)
populationCycleLabel.Position              = UDim2.new(0, 0, 0, 126)
populationCycleLabel.BackgroundTransparency = 1
populationCycleLabel.Font                  = Enum.Font.GothamMedium
populationCycleLabel.TextSize              = FontSize.caption
populationCycleLabel.TextXAlignment        = Enum.TextXAlignment.Left
populationCycleLabel.TextColor3            = Theme.textDim
populationCycleLabel.Text                  = "CYCLE: 0 | Last Compare: -"
populationCycleLabel.Parent                = populationBody

populationWebhookBox.FocusLost:Connect(function()
    populationWebhookURL = (populationWebhookBox.Text or ""):gsub("^%s*(.-)%s*$", "%1")
    populationWebhookBox.Text = populationWebhookURL
    saveLocalConfig()
    print("[POP-MONITOR] LINK DC updated.")
end)

populationToggleButton.MouseButton1Click:Connect(function()
    if isBusy then return end
    populationDcfcConnected = not populationDcfcConnected
    refreshPopulationToggleUI()
    print(string.format("[POP-MONITOR] DC/FC CONNECT -> %s", populationDcfcConnected and "ACTIVE" or "UNACTIVE"))
end)

refreshPopulationToggleUI()
setActiveTab("fish")

local footerSection = Instance.new("Frame")
footerSection.Size                  = UDim2.new(1, 0, 0, 24)
footerSection.BackgroundTransparency = 1
footerSection.LayoutOrder           = 3
footerSection.Parent                = fishTabPage

local footerInfoLabel = Instance.new("TextLabel")
footerInfoLabel.Size                  = UDim2.new(1, -42, 1, 0)
footerInfoLabel.BackgroundTransparency = 1
footerInfoLabel.Font                  = Enum.Font.GothamMedium
footerInfoLabel.TextSize              = FontSize.caption
footerInfoLabel.TextXAlignment        = Enum.TextXAlignment.Left
footerInfoLabel.TextYAlignment        = Enum.TextYAlignment.Center
footerInfoLabel.TextColor3            = Theme.textDim
footerInfoLabel.Text                  = "Monitoring scope: all players"
footerInfoLabel.Parent                = footerSection

local statusPill = Instance.new("TextLabel")
statusPill.Size                  = UDim2.new(0, 44, 0, 28)
statusPill.Position              = UDim2.new(1, -44, 0.5, -14)
statusPill.BackgroundTransparency = 1
statusPill.BackgroundColor3      = Theme.bg
statusPill.BorderSizePixel       = 0
statusPill.Font                  = Enum.Font.GothamBlack
statusPill.TextSize              = 12
statusPill.TextColor3            = Theme.good
statusPill.Text                  = "⚡ R"
statusPill.Parent                = footerSection
applyPanelBadgeStyle(statusPill, Theme.good)

closeBtn.MouseButton1Click:Connect(function()
    print("[FISH LOGGER] Script unloaded by user")
    unloadScript()
end)

----------------------------------------------------------------
-- STATUS & ANIMATION FUNCTIONS
----------------------------------------------------------------

local function setStatus(text, color, loading)
    statusLabel.Text       = text
    statusLabel.TextColor3 = color or Theme.textDim
    if loading then
        loadingBar.Visible = true
        loadingBar.Size    = UDim2.new(0, 0, 0, 2)
        task.spawn(function()
            while isBusy do
                loadingBar.Size = UDim2.new(0, 0, 0, 2)
                local tween = TweenService:Create(
                    loadingBar,
                    TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
                    { Size = UDim2.new(1, 0, 0, 2) }
                )
                tween:Play()
                tween.Completed:Wait()
                task.wait(0.05)
            end
            loadingBar.Visible = false
        end)
    else
        loadingBar.Visible = false
    end
end

toggleBtn.MouseButton1Click:Connect(function()
    if isBusy then return end
    isSending = not isSending
    if isSending then
        toggleBtn.BackgroundColor3  = Theme.good
        toggleBtn.Text              = "ACTIVE"
        statusPill.Text             = "⚡ R"
        applyPanelBadgeStyle(statusPill, Theme.good)
        minimizeBtn.Text            = "⚡ R"
        applyPanelBadgeStyle(minimizeBtn, Theme.good)
    else
        toggleBtn.BackgroundColor3  = Theme.bad
        toggleBtn.Text              = "DEACTIVE"
        statusPill.Text             = "⚡ R"
        applyPanelBadgeStyle(statusPill, Theme.bad)
        minimizeBtn.Text            = "⚡ R"
        applyPanelBadgeStyle(minimizeBtn, Theme.bad)
    end
end)

local function openDashboard()
    refreshSlotInfo()
    if not currentWebhookURL or currentWebhookURL == "" then
        isSending = false
        toggleBtn.BackgroundColor3  = Theme.bad
        toggleBtn.Text              = "DEACTIVE"
        statusPill.Text             = "⚡ R"
        applyPanelBadgeStyle(statusPill, Theme.bad)
        minimizeBtn.Text            = "⚡ R"
        applyPanelBadgeStyle(minimizeBtn, Theme.bad)
        print("[FISH LOGGER] 💡 Auto-disabled sending: Webhook URL is empty")
    end

    local tweenInfo = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

    local authFade = TweenService:Create(authFrame, tweenInfo, {
        Size                  = UDim2.new(0, 380, 0, 145),
        BackgroundTransparency= 1
    })

    dashFrame.Visible              = true
    dashFrame.Size                 = UDim2.new(0, 340, 0, 220)
    dashFrame.BackgroundTransparency = 1

    local dashFade = TweenService:Create(dashFrame, tweenInfo, {
        Size                  = UDim2.new(0, 450, 0, 380),
        BackgroundTransparency= 0
    })

    authFade:Play()
    task.wait(0.15)
    dashFade:Play()

    authFade.Completed:Connect(function()
        authFrame.Visible               = false
        authFrame.BackgroundTransparency = 0
        authFrame.Size                  = UDim2.new(0, 380, 0, 170)
    end)
end

local function startOfflineMonitor()
    if isBusy then return end

    setBusy(true)
    setStatus("Reading Fish Database..", Theme.warn, true)

    task.spawn(function()
        local success, _, owner, details = validateKey("offline")
        if not success then
            setStatus("Failed to start offline mode", Theme.bad, false)
            setBusy(false)
            return
        end

        isAuthenticated = true
        licensedTo = owner
        CurrentLicenseOwner = owner
        CurrentLicenseKey = ""
        CurrentLicenseExpires = (details and details.expires) or "Never"
        currentWebhookURL = webhookBox.Text ~= "" and webhookBox.Text or ((details and details.webhook_url) or "")
        webhookBox.Text = currentWebhookURL
        saveLocalConfig()

        setStatus("Loading Fish Database...", Theme.good, true)
        LastSyncTime = 0
        startSyncLoop()
        buildFishDatabase()

        task.wait(0.35)
        openDashboard()
        setBusy(false)
    end)
end

task.defer(startOfflineMonitor)
task.spawn(runPopulationLoop)

_G.StopPopulationMonitor = function()
    populationMonitorRunning = false
    populationDcfcConnected = false
    if populationAddedConnection then
        populationAddedConnection:Disconnect()
        populationAddedConnection = nil
    end
    if populationRemovingConnection then
        populationRemovingConnection:Disconnect()
        populationRemovingConnection = nil
    end
    refreshPopulationToggleUI()
    print("[POP-MONITOR] Monitor stopped.")
end

----------------------------------------------------------------
-- CHAT LISTENER
----------------------------------------------------------------

local debounce = {}

local function processMessage(text, source)
    if not isAuthenticated then return end

    local key = text .. "_" .. source
    if debounce[key] and (tick() - debounce[key]) < 1 then return end
    debounce[key] = tick()

    local data = parseServerMessage(text)
    if data then
        sendToWebhook(data)
    end
end

if TextChatService.ChatVersion == Enum.ChatVersion.TextChatService then
    TextChatService.OnIncomingMessage = function(msg)
        local text = msg.Text
        if text:match("%[Server%]:") and not text:match("%[Global Alerts%]") then
            processMessage(text, "incoming")
        end
        return nil
    end
end

print("[FISH LOGGER] ✅ Script loaded successfully!")
print("[FISH LOGGER] 🆔 Session UUID:", SessionUUID)
