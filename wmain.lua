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
local Theme
local isAuthenticated = false
local isSending = true
local licensedTo = "Unknown"

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
    sm = 6,
    md = 10,
    lg = 14,
    xl = 16,
    xxl = 20
}

local FontSize = {
    caption = 10,
    body = 12,
    subtitle = 14,
    title = 16
}

local Radius = {
    small = 6,
    medium = 8,
    large = 12
}

local ElementHeight = {
    input   = 30,
    button  = 30,
    header  = 44,
    section = 26
}

Theme = {
    bg           = Color3.fromRGB(12, 14, 20),
    surface      = Color3.fromRGB(20, 23, 32),
    surface2     = Color3.fromRGB(26, 30, 42),
    stroke       = Color3.fromRGB(44, 50, 68),
    text         = Color3.fromRGB(235, 240, 250),
    textDim      = Color3.fromRGB(155, 165, 185),
    accent       = Color3.fromRGB(86, 170, 255),
    accentStrong = Color3.fromRGB(72, 140, 230),
    good         = Color3.fromRGB(64, 190, 120),
    warn         = Color3.fromRGB(255, 186, 73),
    bad          = Color3.fromRGB(230, 80, 95)
}

----------------------------------------------------------------
-- RARITY & FISH DATA
----------------------------------------------------------------

local RarityByRGB = {
    ["rgb(255, 185, 43)"] = "Legendary",
    ["rgb(255, 25, 25)"]  = "Mythical",
    ["rgb(24, 255, 152)"] = "Secret"
}

local RarityColors = {
    ["Legendary"] = 16766763,
    ["Mythical"]  = 16719129,
    ["Secret"]    = 1622168
}

local Mutations = {
    "Galaxy","Corrupt","Gemstone","Ghost","Lightning","Fairy Dust","Gold","Midnight",
    "Radioactive","Stone","Holographic","Albino","Bloodmoon","Sandy","Acidic",
    "Color Burn","Festive","Frozen","Leviathan Rage","Crystalized","Cupid","Heartbreak"
}

----------------------------------------------------------------
-- FISH DATABASE
----------------------------------------------------------------

local FishDatabase = {}
local FishIndexByNormalizedName = {}

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

local function getModuleSourceText(moduleScript)
    local sourceText = nil
    local okDirect, direct = pcall(function()
        return moduleScript.Source
    end)
    if okDirect and type(direct) == "string" and direct ~= "" then
        sourceText = direct
    end

    if (not sourceText or sourceText == "") and decompile then
        local okDec, dec = pcall(function()
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

    local count = 0
    for _, item in ipairs(ItemsFolder:GetDescendants()) do
        if item:IsA("ModuleScript") then
            local ok, data = pcall(require, item)
            if ok and data and data.Data then
                local fishData = data.Data
                if fishData.Type == "Fish" and fishData.Name then
                    local entry = {
                        Name      = fishData.Name,
                        Icon      = fishData.Icon or "",
                        Tier      = fishData.Tier or "Unknown",
                        SellPrice = data.SellPrice or 0,
                        Id        = fishData.Id or 0
                    }
                    FishDatabase[fishData.Name] = entry
                    FishIndexByNormalizedName[normalizeFishName(fishData.Name)] = entry
                    count += 1
                end
            elseif not ok then
                local fallback = parseFishFromModuleSource(getModuleSourceText(item), item.Name)
                if fallback and fallback.Name then
                    FishDatabase[fallback.Name] = fallback
                    FishIndexByNormalizedName[normalizeFishName(fallback.Name)] = fallback
                    count += 1
                end
            end
        end
    end

    print("[FISH LOGGER] Loaded", count, "fish into database")
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

local function extractAssetId(iconString)
    if not iconString or iconString == "" then
        return nil
    end
    return iconString:match("rbxassetid://(%d+)") or iconString:match("(%d+)")
end

local function getThumbnailURL(fishName)
    local cleanedName = cleanFishName(fishName)
    local fishData    = FishDatabase[cleanedName]
        or FishIndexByNormalizedName[normalizeFishName(cleanedName)]
        or FishIndexByNormalizedName[normalizeFishName(fishName)]
    if not fishData or not fishData.Icon then
        return "https://i.ibb.co.com/q38LKrcJ/image.png"
    end

    local assetId = extractAssetId(fishData.Icon)
    if not assetId then
        return "https://i.ibb.co.com/q38LKrcJ/image.png"
    end

    local requestFunc = (syn and syn.request) or (http and http.request) or http_request or (fluxus and fluxus.request) or request
    if not requestFunc then
        warn("[FISH LOGGER] ⚠️ HTTP request not available for thumbnails")
        return "https://i.ibb.co.com/q38LKrcJ/image.png"
    end

    local url = string.format(
        "https://thumbnails.roblox.com/v1/assets?assetIds=%s&returnPolicy=PlaceHolder&size=420x420&format=Png&isCircular=false",
        assetId
    )

    for attempt = 1, 3 do
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

            if jsonSuccess and jsonData.data and jsonData.data[1] and jsonData.data[1].imageUrl and jsonData.data[1].imageUrl ~= "" then
                return jsonData.data[1].imageUrl
            end
        end

        if attempt < 3 then
            task.wait(0.2)
        end
    end

    return "https://i.ibb.co.com/q38LKrcJ/image.png"
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
    ["Ruby (Gemstone)"] = true
}

local webhookWarningTime = 0

local function sendToDiscord(webhookUrl, embedData, username, avatarUrl)
    local requestFunc = (syn and syn.request) or (http and http.request) or http_request or (fluxus and fluxus.request) or request
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

-- MODIFIKASI: Fungsi untuk menentukan filter yang digunakan
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

    local rarity = RarityByRGB[catchData.rgbString]
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

    local embedColor   = RarityColors[rarity] or 2067276
    local thumbnailUrl = getThumbnailURL(catchData.fish)

    local embed = {
        embeds = {{
            title       = "[🔒] RENNB PRIVATE - [ SERVER MONITORING ]",
            description = string.format("[**%s**] has obtained a [**%s**]\nCONGRATULATIONS [🎊]", catchData.player, catchData.fish),
            color       = embedColor,
            thumbnail   = { url = thumbnailUrl },
            fields = {
                { name = "🐳 FISH",     value = "`" .. cleanedFish      .. "`", inline = true },
                { name = "🧬 MUTATION", value = "`" .. mutation         .. "`", inline = true },
                { name = "✨ RARITY",   value = "`" .. rarity           .. "`", inline = true },
                { name = "👤 PLAYER",   value = "`" .. catchData.player .. "`", inline = true },
                { name = "🎲 CHANCE",   value = "`"  .. catchData.chance .. "`",  inline = true },
                { name = "⚖️ WEIGHT",   value = "`" .. catchData.weight .. "`", inline = true }
            },
            footer = {
                text = string.format("BY RENNARUDHA • %s", catchData.time)
            }
        }}
    }

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
    isAuthenticated = false
    isSending = false
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
dashFrame.Size              = UDim2.new(0, 450, 0, 340)
dashFrame.Position          = UDim2.new(0.5, 0, 0.5, 0)
dashFrame.AnchorPoint       = Vector2.new(0.5, 0.5)
dashFrame.BackgroundColor3  = Theme.bg
dashFrame.BorderSizePixel   = 0
dashFrame.Active            = true
dashFrame.Draggable         = true
dashFrame.Visible           = false
dashFrame.Parent            = screenGui
addCorner(dashFrame, Radius.large)

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

local dashHeaderFix = Instance.new("Frame")
dashHeaderFix.Size              = UDim2.new(1, 0, 0, Radius.large)
dashHeaderFix.Position          = UDim2.new(0, 0, 1, -Radius.large)
dashHeaderFix.BackgroundColor3  = Theme.surface2
dashHeaderFix.BorderSizePixel   = 0
dashHeaderFix.Parent            = dashHeader

local dashTitle = Instance.new("TextLabel")
dashTitle.Size                  = UDim2.new(1, -110, 0, 20)
dashTitle.Position              = UDim2.new(0, Spacing.lg, 0, Spacing.sm)
dashTitle.BackgroundTransparency = 1
dashTitle.Font                  = Enum.Font.GothamBold
dashTitle.TextSize              = FontSize.title
dashTitle.TextXAlignment        = Enum.TextXAlignment.Left
dashTitle.TextColor3            = Theme.text
dashTitle.Text                  = "[🔒] PRIVATE RENN - SERVER MONITORING"
dashTitle.Parent                = dashHeader

local dashSubtitle = Instance.new("TextLabel")
dashSubtitle.Size                  = UDim2.new(1, -110, 0, 16)
dashSubtitle.Position              = UDim2.new(0, Spacing.lg, 0, 26)
dashSubtitle.BackgroundTransparency = 1
dashSubtitle.Font                  = Enum.Font.GothamMedium
dashSubtitle.TextSize              = FontSize.caption
dashSubtitle.TextXAlignment        = Enum.TextXAlignment.Left
dashSubtitle.TextColor3            = Theme.textDim
dashSubtitle.Text                  = "THE MORE I SWIM - THE MORE IM SINKING"
dashSubtitle.Parent                = dashHeader

local hideBtn = Instance.new("TextButton")
hideBtn.Size                  = UDim2.new(0, 68, 0, 28)
hideBtn.Position              = UDim2.new(1, -68 - Spacing.md, 0.5, -14)
hideBtn.BackgroundColor3      = Theme.accentStrong
hideBtn.BorderSizePixel       = 0
hideBtn.Font                  = Enum.Font.GothamBold
hideBtn.TextSize              = FontSize.body
hideBtn.TextColor3            = Theme.text
hideBtn.Text                  = "Hide"
hideBtn.AutoButtonColor       = true
hideBtn.Parent                = dashHeader
addCorner(hideBtn, Radius.medium)
table.insert(interactiveObjects, hideBtn)

local minimizeBtn = Instance.new("TextButton")
minimizeBtn.Name            = "MinimizeBtn"
minimizeBtn.Size            = UDim2.new(0, 180, 0, 36)
minimizeBtn.Position        = UDim2.new(0, Spacing.md, 0.5, -18)
minimizeBtn.AnchorPoint     = Vector2.new(0, 0.5)
minimizeBtn.BackgroundColor3= Theme.good
minimizeBtn.BorderSizePixel = 0
minimizeBtn.Font            = Enum.Font.GothamBold
minimizeBtn.TextSize        = FontSize.body
minimizeBtn.TextColor3      = Theme.text
minimizeBtn.Text            = "🎣 Discord Monitor: ON"
minimizeBtn.AutoButtonColor = true
minimizeBtn.Visible         = false
minimizeBtn.Parent          = screenGui
addCorner(minimizeBtn, Radius.medium)
addStroke(minimizeBtn, Theme.stroke, 2)

minimizeBtn.MouseButton1Click:Connect(function()
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

local dashLayout = Instance.new("UIListLayout")
dashLayout.Padding    = UDim.new(0, Spacing.md)
dashLayout.SortOrder  = Enum.SortOrder.LayoutOrder
dashLayout.Parent     = dashContent

local function makeSection(titleText, order)
    local section            = Instance.new("Frame")
    section.Size             = UDim2.new(1, 0, 0, 0)
    section.BackgroundColor3 = Theme.surface
    section.BorderSizePixel  = 0
    section.LayoutOrder      = order
    section.Parent           = dashContent
    addCorner(section, Radius.medium)

    local label = Instance.new("TextLabel")
    label.Name                  = "SectionLabel"
    label.Size                  = UDim2.new(1, -Spacing.md*2, 0, 14)
    label.Position              = UDim2.new(0, Spacing.md, 0, Spacing.sm)
    label.BackgroundTransparency = 1
    label.Font                  = Enum.Font.GothamBold
    label.TextSize              = FontSize.subtitle
    label.TextXAlignment        = Enum.TextXAlignment.Left
    label.TextColor3            = Theme.text
    label.Text                  = titleText
    label.Parent                = section

    local body = Instance.new("Frame")
    body.Name                   = "SectionBody"
    body.Size                   = UDim2.new(1, -Spacing.md*2, 1, -24)
    body.Position               = UDim2.new(0, Spacing.md, 0, 18)
    body.BackgroundTransparency = 1
    body.Parent                 = section

    return section, body
end

local monitorSection, monitorBody = makeSection("Monitoring", 1)
monitorSection.Size = UDim2.new(1, 0, 0, 108)

local monitorRow = Instance.new("Frame")
monitorRow.Size                  = UDim2.new(1, 0, 0, ElementHeight.input)
monitorRow.BackgroundTransparency = 1
monitorRow.Parent                = monitorBody

local monitorLabel = Instance.new("TextLabel")
monitorLabel.Size                  = UDim2.new(1, -90, 1, 0)
monitorLabel.BackgroundTransparency = 1
monitorLabel.Font                  = Enum.Font.GothamMedium
monitorLabel.TextSize              = FontSize.body
monitorLabel.TextXAlignment        = Enum.TextXAlignment.Left
monitorLabel.TextColor3            = Theme.textDim
monitorLabel.Text                  = "Send to Discord"
monitorLabel.Parent                = monitorRow

local toggleBtn = Instance.new("TextButton")
toggleBtn.Size                  = UDim2.new(0, 64, 0, ElementHeight.input)
toggleBtn.Position              = UDim2.new(1, -64, 0, 0)
toggleBtn.BackgroundColor3      = Theme.good
toggleBtn.BorderSizePixel       = 0
toggleBtn.Font                  = Enum.Font.GothamBold
toggleBtn.TextSize              = FontSize.body
toggleBtn.TextColor3            = Theme.text
toggleBtn.Text                  = "ON"
toggleBtn.AutoButtonColor       = true
toggleBtn.Parent                = monitorRow
addCorner(toggleBtn, Radius.medium)
table.insert(interactiveObjects, toggleBtn)

-- MODIFIKASI: Baris checkbox pertama
local rarityRow = Instance.new("Frame")
rarityRow.Size                  = UDim2.new(1, 0, 0, 24)
rarityRow.Position              = UDim2.new(0, 0, 0, ElementHeight.input + Spacing.xs)
rarityRow.BackgroundTransparency = 1
rarityRow.Parent                = monitorBody

-- MODIFIKASI: Baris checkbox kedua (untuk 2 filter baru)
local rarityRow2 = Instance.new("Frame")
rarityRow2.Size                  = UDim2.new(1, 0, 0, 24)
rarityRow2.Position              = UDim2.new(0, 0, 0, ElementHeight.input + Spacing.xs + 22)
rarityRow2.BackgroundTransparency = 1
rarityRow2.Parent                = monitorBody

local function createRarityCheckbox(rarityName, index, color, parentFrame)
    local item = Instance.new("Frame")
    
    -- MODIFIKASI: Jika ada lebih dari 3 checkbox, gunakan 2 kolom
    if parentFrame == rarityRow2 then
        item.Size = UDim2.new(0.5, -Spacing.xs, 1, 0)
        item.Position = UDim2.new((index - 1) * 0.5, (index > 1) and Spacing.xs or 0, 0, 0)
    else
        item.Size = UDim2.new(1/3, -Spacing.xs, 1, 0)
        item.Position = UDim2.new((index - 1)/3, (index > 1) and Spacing.xs or 0, 0, 0)
    end
    
    item.BackgroundTransparency = 1
    item.Parent                = parentFrame

    local box = Instance.new("TextButton")
    box.Size                  = UDim2.new(0, 20, 0, 20)
    box.Position              = UDim2.new(0, 0, 0.5, -10)
    box.BackgroundColor3      = Theme.surface2
    box.BorderSizePixel       = 0
    box.Font                  = Enum.Font.GothamBold
    box.TextSize              = FontSize.body
    box.TextColor3            = Theme.text
    box.Text                  = ""
    box.AutoButtonColor       = true
    box.Parent                = item
    addCorner(box, Radius.small)

    local check = Instance.new("Frame")
    check.Size              = UDim2.new(0, 12, 0, 12)
    check.Position          = UDim2.new(0.5, -6, 0.5, -6)
    check.BackgroundColor3  = color
    check.BorderSizePixel   = 0
    check.Parent            = box
    addCorner(check, Spacing.xs)

    local label = Instance.new("TextLabel")
    label.Size                  = UDim2.new(1, -30, 1, 0)
    label.Position              = UDim2.new(0, 28, 0, 0)
    label.BackgroundTransparency = 1
    label.Font                  = Enum.Font.GothamMedium
    label.TextSize              = FontSize.caption  -- MODIFIKASI: Font lebih kecil untuk text panjang
    label.TextXAlignment        = Enum.TextXAlignment.Left
    label.TextColor3            = Theme.text
    label.Text                  = rarityName
    label.TextScaled            = false
    label.TextWrapped           = true
    label.Parent                = item

    table.insert(interactiveObjects, box)

    local function sync()
        if rarityFilters[rarityName] then
            check.Visible    = true
            label.TextColor3 = Theme.text
        else
            check.Visible    = false
            label.TextColor3 = Theme.textDim
        end
    end
    sync()

    box.MouseButton1Click:Connect(function()
        if isBusy then return end
        rarityFilters[rarityName] = not rarityFilters[rarityName]
        sync()
    end)
end

-- MODIFIKASI: Checkbox di baris pertama
createRarityCheckbox("Legendary", 1, Color3.fromRGB(255, 200, 80), rarityRow)
createRarityCheckbox("Mythical",  2, Color3.fromRGB(255, 100, 100), rarityRow)
createRarityCheckbox("Secret",    3, Color3.fromRGB(100, 255, 190), rarityRow)

-- MODIFIKASI: Checkbox di baris kedua (2 filter baru)
createRarityCheckbox("Legend (Crystalized)", 1, Color3.fromRGB(255, 100, 100), rarityRow2)
createRarityCheckbox("Ruby (Gemstone)", 2, Color3.fromRGB(255, 200, 80), rarityRow2)

local webhookSection, webhookBody = makeSection("Webhook", 2)
webhookSection.Size = UDim2.new(1, 0, 0, 76)

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
    currentWebhookURL = webhookBox.Text
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
table.insert(interactiveObjects, testBtn)

testBtn.MouseButton1Click:Connect(function()
    if isBusy then return end
    if not currentWebhookURL or currentWebhookURL == "" then
        warn("[FISH LOGGER] Please enter a webhook URL first!")
        return
    end

    local testFishName = "GEMSTONE Ruby"
    local cleanedFish = cleanFishName(testFishName)
    local mutation = detectMutation(testFishName)
    local thumbnailUrl = getThumbnailURL(testFishName)
    local rarity = "Secret"
    local embedColor = RarityColors[rarity] or 16766763

    local testEmbed = {
        embeds = {{
            title       = "[🔒] RENNB PRIVATE - [ SERVER CONNECTED ]",
            description = string.format("[ **%s** ] has obtained a [ **%s** ]\nWEBHOOK CONNECTED [✅]", Player.Name, testFishName),
            color       = embedColor,
            thumbnail   = { url = thumbnailUrl },
            fields = {
                { name = "🐳 FISH",     value = "`" .. cleanedFish .. "`",      inline = true },
                { name = "🧬 MUTATION", value = "`" .. mutation .. "`",         inline = true },
                { name = "✨ RARITY",   value = "`" .. rarity .. "`",           inline = true },
                { name = "👤 PLAYER",   value = "`" .. Player.Name .. "`",      inline = true },
                { name = "🎲 CHANCE",   value = "`1/500K`",                       inline = true },
                { name = "⚖️ WEIGHT",   value = "`165 kg`",                    inline = true }
            },
            footer = {
                text = string.format("By RENNARUDHA • %s", os.date("%d/%m/%Y %H:%M"))
            }
        }}
    }

    sendToDiscord(currentWebhookURL, testEmbed, botName, botAvatar)
    print("[FISH LOGGER] 🧪 Test webhook sent with real data for:", testFishName)
end)

local footerSection = Instance.new("Frame")
footerSection.Size                  = UDim2.new(1, 0, 0, 22)
footerSection.BackgroundTransparency = 1
footerSection.LayoutOrder           = 3
footerSection.Parent                = dashContent

local footerInfoLabel = Instance.new("TextLabel")
footerInfoLabel.Size                  = UDim2.new(0.65, 0, 1, 0)
footerInfoLabel.BackgroundTransparency = 1
footerInfoLabel.Font                  = Enum.Font.GothamMedium
footerInfoLabel.TextSize              = FontSize.caption
footerInfoLabel.TextXAlignment        = Enum.TextXAlignment.Left
footerInfoLabel.TextYAlignment        = Enum.TextYAlignment.Center
footerInfoLabel.TextColor3            = Theme.textDim
footerInfoLabel.Text                  = "Monitoring: ALL PLAYERS"
footerInfoLabel.Parent                = footerSection

local statusPill = Instance.new("TextLabel")
statusPill.Size                  = UDim2.new(0, 86, 0, 20)
statusPill.Position              = UDim2.new(1, -86, 0.5, -10)
statusPill.BackgroundColor3      = Theme.good
statusPill.BorderSizePixel       = 0
statusPill.Font                  = Enum.Font.GothamBold
statusPill.TextSize              = FontSize.caption
statusPill.TextColor3            = Theme.text
statusPill.Text                  = "● LIVE"
statusPill.Parent                = footerSection
addCorner(statusPill, Radius.medium)

local closeBtn = Instance.new("TextButton")
closeBtn.Size                  = UDim2.new(1, 0, 0, 30)
closeBtn.BackgroundColor3      = Theme.bad
closeBtn.BorderSizePixel       = 0
closeBtn.Font                  = Enum.Font.GothamBold
closeBtn.TextSize              = FontSize.body
closeBtn.TextColor3            = Theme.text
closeBtn.Text                  = "CLOSE PANEL - GOOD BYE"
closeBtn.AutoButtonColor       = true
closeBtn.LayoutOrder           = 4
closeBtn.Parent                = dashContent
addCorner(closeBtn, Radius.medium)
table.insert(interactiveObjects, closeBtn)

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
        statusPill.BackgroundColor3 = Theme.good
        statusPill.Text             = "● RUNNING"
        minimizeBtn.Text            = "● R-PRIVATE MONITORING : ON"
        minimizeBtn.BackgroundColor3= Theme.good
    else
        toggleBtn.BackgroundColor3  = Theme.bad
        toggleBtn.Text              = "DEACTIVE"
        statusPill.BackgroundColor3 = Theme.bad
        statusPill.Text             = "● PAUSED"
        minimizeBtn.Text            = "● R-PRIVATE MONITORING : OFF"
        minimizeBtn.BackgroundColor3= Theme.bad
    end
end)

local function openDashboard()
    refreshSlotInfo()
    if not currentWebhookURL or currentWebhookURL == "" then
        isSending = false
        toggleBtn.BackgroundColor3  = Theme.bad
        toggleBtn.Text              = "DEACTIVE"
        statusPill.BackgroundColor3 = Theme.bad
        statusPill.Text             = "● PAUSED"
        minimizeBtn.BackgroundColor3= Theme.bad
        minimizeBtn.Text            = "● R-PRIVATE MONITORING : OFF"
        print("[FISH LOGGER] 💡 Auto-disabled sending: Webhook URL is empty")
    end

    local tweenInfo = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

    local authFade = TweenService:Create(authFrame, tweenInfo, {
        Size                  = UDim2.new(0, 380, 0, 145),
        BackgroundTransparency= 1
    })

    dashFrame.Visible              = true
    dashFrame.Size                 = UDim2.new(0, 340, 0, 210)
    dashFrame.BackgroundTransparency = 1

    local dashFade = TweenService:Create(dashFrame, tweenInfo, {
        Size                  = UDim2.new(0, 450, 0, 340),
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

