--[[
    WeeklyQuestTracker - Premium Multi-Mode User Interface
    Clean, modern, font-safe UI with Blizzard native textures and zero missing glyphs.
    Supports 4 View Modes:
      1. Grid (Matrix Table)
      2. Cards (Character Cards with Progress Bars)
      3. To-Do List (Incomplete Quests Focus)
      4. Combined (To-Do Summary + Full Grid together)
    Map Integrations:
      - Native Blizzard Addon Compartment (Minimap Menu)
      - Dedicated World Map Frame Button (On the 'M' Map window)
      - Floating / Draggable Circular Minimap Icon
]]

local addonName, WQT = ...

local mainFrame = nil
local activeTab = "grid" -- "grid", "cards", "todo", "combined"
local contentScrollChild = nil
local addQuestDialog = nil

-- Standard Safe Tooltip Borders & Textures
local FRAME_BACKDROP = {
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = false,
    tileSize = 16,
    edgeSize = 14,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
}

local CARD_BACKDROP = {
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = false,
    tileSize = 16,
    edgeSize = 10,
    insets = { left = 2, right = 2, top = 2, bottom = 2 },
}

-- Format Class Colored Name with Class Icon
local function GetFormattedName(charData)
    local r, g, b, hex = WQT.GetClassColor(charData.class)
    local icon = WQT.GetClassIcon(charData.class)
    local iconPrefix = (icon and icon ~= "") and (icon .. " ") or ""
    return string.format("%s|c%s%s|r", iconPrefix, hex, charData.name or "Unknown")
end

-- Resolve Full or Compact Status Display String
function WQT.GetStatusString(qStatus, isShort)
    if not qStatus then
        return isShort and WQT.STATUS_TODO_SHORT or WQT.STATUS_TODO
    end
    local state = qStatus.state
    if state == "DONE" or (state == nil and qStatus.completed) then
        return isShort and WQT.STATUS_DONE_SHORT or WQT.STATUS_DONE
    elseif state == "READY" or qStatus.readyToTurnIn then
        return isShort and WQT.STATUS_READY_SHORT or WQT.STATUS_READY
    elseif state == "PROGRESS" or qStatus.inProgress then
        return isShort and WQT.STATUS_PROGRESS_SHORT or WQT.STATUS_PROGRESS
    else
        return isShort and WQT.STATUS_TODO_SHORT or WQT.STATUS_TODO
    end
end

-- =========================================================================
-- MAIN WINDOW SETUP
-- =========================================================================
function WQT.CreateMainFrame()
    if mainFrame then return mainFrame end

    local f = CreateFrame("Frame", "WQT_MainFrame", UIParent, "BackdropTemplate")
    f:SetSize(1040, 600)
    f:SetPoint("CENTER")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetClampedToScreen(true)
    f:SetBackdrop(FRAME_BACKDROP)
    f:SetBackdropColor(0.08, 0.09, 0.12, 0.96)
    f:SetBackdropBorderColor(0.35, 0.38, 0.45, 1)

    -- Register ESC key to close
    tinsert(UISpecialFrames, "WQT_MainFrame")

    -- Header / Title Bar
    local header = CreateFrame("Frame", nil, f, "BackdropTemplate")
    header:SetPoint("TOPLEFT", 4, -4)
    header:SetPoint("TOPRIGHT", -4, -4)
    header:SetHeight(42)
    header:SetBackdrop(CARD_BACKDROP)
    header:SetBackdropColor(0.12, 0.14, 0.18, 1)
    header:SetBackdropBorderColor(0.22, 0.25, 0.32, 1)

    -- Title Text
    local title = header:CreateFontString(nil, "OVERLAY", "GameFontHighlightMedium")
    title:SetPoint("LEFT", header, "LEFT", 14, 0)
    title:SetText(WQT.ADDON_TITLE .. " |cff888888v" .. WQT.VERSION .. "|r")

    -- Reset Timer Badge
    local resetBadge = CreateFrame("Frame", nil, header, "BackdropTemplate")
    resetBadge:SetPoint("LEFT", title, "RIGHT", 14, 0)
    resetBadge:SetSize(140, 24)
    resetBadge:SetBackdrop(CARD_BACKDROP)
    resetBadge:SetBackdropColor(0.18, 0.16, 0.10, 0.9)
    resetBadge:SetBackdropBorderColor(0.6, 0.5, 0.2, 0.8)

    local resetText = resetBadge:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    resetText:SetPoint("CENTER", 0, 0)
    resetText:SetText("|cffffcc00Reset in: ...|r")
    f.resetText = resetText

    -- Close Button (Custom Flat Sleek)
    local closeBtn = CreateFrame("Button", nil, header, "UIPanelCloseButton")
    closeBtn:SetPoint("RIGHT", header, "RIGHT", -4, 0)
    closeBtn:SetScript("OnClick", function() f:Hide() end)

    -- "+ Add Quest" Button
    local addBtn = CreateFrame("Button", nil, header, "BackdropTemplate")
    addBtn:SetSize(110, 24)
    addBtn:SetPoint("RIGHT", closeBtn, "LEFT", -8, 0)
    addBtn:SetBackdrop(CARD_BACKDROP)
    addBtn:SetBackdropColor(0.15, 0.22, 0.32, 1)
    addBtn:SetBackdropBorderColor(0.3, 0.5, 0.7, 0.9)

    local addBtnText = addBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    addBtnText:SetPoint("CENTER", 0, 0)
    addBtnText:SetText("|cff66ccff+ Add Quest|r")
    addBtn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.2, 0.3, 0.45, 1)
        self:SetBackdropBorderColor(0.4, 0.7, 1.0, 1)
    end)
    addBtn:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.15, 0.22, 0.32, 1)
        self:SetBackdropBorderColor(0.3, 0.5, 0.7, 0.9)
    end)
    addBtn:SetScript("OnClick", function()
        WQT.ShowAddQuestDialog()
    end)

    -- Tab Switcher Bar (4 Tabs)
    local tabBar = CreateFrame("Frame", nil, f)
    tabBar:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 6, -6)
    tabBar:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", -6, -6)
    tabBar:SetHeight(28)

    local tabButtons = {}
    local tabs = {
        { id = "current", label = "Current Alt" },
        { id = "grid", label = "Grid (All Alts)" },
        { id = "cards", label = "Cards" },
        { id = "todo", label = "To-Do List" },
    }

    local lastBtn = nil
    for _, t in ipairs(tabs) do
        local btn = CreateFrame("Button", nil, tabBar, "BackdropTemplate")
        btn:SetSize(168, 26)
        if not lastBtn then
            btn:SetPoint("LEFT", tabBar, "LEFT", 0, 0)
        else
            btn:SetPoint("LEFT", lastBtn, "RIGHT", 6, 0)
        end

        btn:SetBackdrop(CARD_BACKDROP)
        btn:SetBackdropColor(0.14, 0.15, 0.19, 1)
        btn:SetBackdropBorderColor(0.28, 0.30, 0.38, 0.8)

        local btnText = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        btnText:SetPoint("CENTER", 0, 0)
        btnText:SetText(t.label)
        btn.text = btnText

        btn:SetScript("OnClick", function()
            WQT.SetViewMode(t.id)
        end)

        tabButtons[t.id] = btn
        lastBtn = btn
    end
    f.tabButtons = tabButtons

    -- Main Scrollable Content Container
    local scrollFrame = CreateFrame("ScrollFrame", "WQT_ScrollFrame", f, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", tabBar, "BOTTOMLEFT", 4, -8)
    scrollFrame:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -26, 32)

    contentScrollChild = CreateFrame("Frame", nil, scrollFrame)
    contentScrollChild:SetSize(scrollFrame:GetWidth() or 990, 1)
    scrollFrame:SetScrollChild(contentScrollChild)
    f.scrollChild = contentScrollChild

    -- Bottom Status / Info Bar
    local statusBar = CreateFrame("Frame", nil, f, "BackdropTemplate")
    statusBar:SetPoint("BOTTOMLEFT", 6, 6)
    statusBar:SetPoint("BOTTOMRIGHT", -6, 6)
    statusBar:SetHeight(24)
    statusBar:SetBackdrop(CARD_BACKDROP)
    statusBar:SetBackdropColor(0.10, 0.11, 0.14, 0.9)
    statusBar:SetBackdropBorderColor(0.2, 0.22, 0.28, 0.6)

    local currentAltText = statusBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    currentAltText:SetPoint("LEFT", 10, 0)
    f.currentAltText = currentAltText

    local tipText = statusBar:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    tipText:SetPoint("RIGHT", -10, 0)
    tipText:SetText("|cffffcc00Shift-Click cell: Cycle status|r | |cff888888Right-click quest: Delete|r")

    -- Initialize frame as hidden so first toggle shows it immediately
    f:Hide()
    mainFrame = f
    return mainFrame
end

-- =========================================================================
-- VIEW MODE SWITCHER
-- =========================================================================
function WQT.SetViewMode(mode)
    activeTab = mode or "current"
    if WeeklyQuestTrackerDB and WeeklyQuestTrackerDB.settings then
        WeeklyQuestTrackerDB.settings.viewMode = activeTab
    end

    if mainFrame and mainFrame.tabButtons then
        for tabId, btn in pairs(mainFrame.tabButtons) do
            if tabId == activeTab then
                btn:SetBackdropColor(0.22, 0.26, 0.35, 1)
                btn:SetBackdropBorderColor(0.9, 0.75, 0.2, 1)
                btn.text:SetText("|cffffd100" .. btn.text:GetText():gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "") .. "|r")
            else
                btn:SetBackdropColor(0.12, 0.13, 0.17, 1)
                btn:SetBackdropBorderColor(0.25, 0.28, 0.35, 0.6)
                local plainText = btn.text:GetText():gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
                btn.text:SetText("|cffa0a0a0" .. plainText .. "|r")
            end
        end
    end

    WQT.RefreshUI()
end

-- =========================================================================
-- RENDER VIEWS
-- =========================================================================
function WQT.RefreshUI()
    if not mainFrame or not mainFrame:IsShown() then return end

    local secsUntilReset = C_DateAndTime.GetSecondsUntilWeeklyReset() or 0
    mainFrame.resetText:SetText(string.format("|cffffcc00Reset in: %s|r", WQT.FormatTimeRemaining(secsUntilReset)))

    local currentKey = WQT.GetPlayerKey()
    mainFrame.currentAltText:SetText(string.format("Current Alt: |cffffd100%s|r", currentKey))

    for _, child in ipairs({ contentScrollChild:GetChildren() }) do
        child:Hide()
        child:SetParent(nil)
    end

    local quests = WeeklyQuestTrackerDB.quests or {}
    local chars = WeeklyQuestTrackerDB.characters or {}

    local sortedChars = {}
    for charKey, data in pairs(chars) do
        table.insert(sortedChars, { key = charKey, data = data })
    end
    table.sort(sortedChars, function(a, b) return (a.data.name or "") < (b.data.name or "") end)

    if activeTab == "current" then
        WQT.RenderCurrentCharacterView(quests, 0)
    elseif activeTab == "grid" then
        WQT.RenderGridView(sortedChars, quests, 0)
    elseif activeTab == "cards" then
        WQT.RenderCardsView(sortedChars, quests, 0)
    elseif activeTab == "todo" then
        WQT.RenderTodoView(sortedChars, quests, 0)
    else
        activeTab = "current"
        WQT.RenderCurrentCharacterView(quests, 0)
    end
end

-- =========================================================================
-- VIEW 0: CURRENT CHARACTER FOCUSED VIEW
-- =========================================================================
function WQT.RenderCurrentCharacterView(quests, startY)
    local parent = contentScrollChild
    local currentY = startY or 0
    local totalWidth = 980

    local currentKey = WQT.GetPlayerKey()
    local charData = WeeklyQuestTrackerDB.characters and WeeklyQuestTrackerDB.characters[currentKey]
    if not charData then
        WQT.ScanCurrentCharacter()
        charData = WeeklyQuestTrackerDB.characters and WeeklyQuestTrackerDB.characters[currentKey]
    end

    local name = UnitName("player") or "Unknown"
    local realm = GetNormalizedRealmName() or GetRealmName() or ""
    local localizedClass, classFile = UnitClass("player")
    local level = UnitLevel("player") or 90
    local _, _, _, classColorHex = WQT.GetClassColor(classFile)
    classColorHex = classColorHex or "ffffffff"

    local charQuests = (charData and charData.quests) or {}
    local totalQuests = #quests
    local doneCount = 0
    local readyCount = 0
    local progressCount = 0
    local incompleteCount = 0

    for _, q in ipairs(quests) do
        local qs = charQuests[q.name]
        if qs and (qs.state == "DONE" or qs.completed) then
            doneCount = doneCount + 1
        elseif qs and (qs.state == "READY" or qs.readyToTurnIn) then
            readyCount = readyCount + 1
        elseif qs and (qs.state == "PROGRESS" or qs.inProgress) then
            progressCount = progressCount + 1
        else
            incompleteCount = incompleteCount + 1
        end
    end

    -- 1. Hero Spotlight Header Card (Height: 96px)
    local heroCard = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    heroCard:SetPoint("TOPLEFT", parent, "TOPLEFT", 4, currentY)
    heroCard:SetSize(totalWidth, 96)
    heroCard:SetBackdrop(CARD_BACKDROP)
    heroCard:SetBackdropColor(0.12, 0.14, 0.20, 0.98)
    heroCard:SetBackdropBorderColor(0.0, 0.85, 1.0, 0.95)

    -- Character Name & Details
    local heroName = heroCard:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    heroName:SetPoint("TOPLEFT", 16, -14)
    heroName:SetText(string.format("|c%s%s|r |cff00e5ff(Current Alt)|r", classColorHex, name))

    local heroDetails = heroCard:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    heroDetails:SetPoint("TOPLEFT", 16, -38)
    heroDetails:SetText(string.format("Level %d %s | Realm: |cffffd100%s|r", level, localizedClass or classFile or "", realm))

    -- Quick Scan Button
    local scanBtn = CreateFrame("Button", nil, heroCard, "BackdropTemplate")
    scanBtn:SetSize(150, 24)
    scanBtn:SetPoint("TOPLEFT", 16, -62)
    scanBtn:SetBackdrop(CARD_BACKDROP)
    scanBtn:SetBackdropColor(0.16, 0.24, 0.36, 1)
    scanBtn:SetBackdropBorderColor(0.3, 0.6, 0.9, 0.9)
    local scanBtnText = scanBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    scanBtnText:SetPoint("CENTER", 0, 0)
    scanBtnText:SetText("|cff00e5ffRe-Scan Character|r")
    scanBtn:SetScript("OnClick", function()
        WQT.ScanCurrentCharacter()
        print(string.format("%s: Re-scanned %s successfully.", WQT.ADDON_TITLE, name))
        WQT.RefreshUI()
    end)
    scanBtn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.22, 0.32, 0.48, 1)
        self:SetBackdropBorderColor(0.4, 0.8, 1.0, 1)
    end)
    scanBtn:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.16, 0.24, 0.36, 1)
        self:SetBackdropBorderColor(0.3, 0.6, 0.9, 0.9)
    end)

    -- Right Side: Progress Bar & Status Counters
    local progressPercent = totalQuests > 0 and math.floor((doneCount / totalQuests) * 100) or 0
    local progressLabel = heroCard:CreateFontString(nil, "OVERLAY", "GameFontHighlightMedium")
    progressLabel:SetPoint("TOPRIGHT", -16, -14)
    progressLabel:SetText(string.format("Weekly Completion: |cff2ecc71%d / %d|r (|cffffd100%d%%|r)", doneCount, totalQuests, progressPercent))

    local pBar = CreateFrame("StatusBar", nil, heroCard)
    pBar:SetSize(280, 14)
    pBar:SetPoint("TOPRIGHT", -16, -38)
    pBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    pBar:SetMinMaxValues(0, math.max(totalQuests, 1))
    pBar:SetValue(doneCount)
    if doneCount == totalQuests and totalQuests > 0 then
        pBar:SetStatusBarColor(0.18, 0.80, 0.44)
    else
        pBar:SetStatusBarColor(0.0, 0.75, 1.0)
    end

    local pBarBg = pBar:CreateTexture(nil, "BACKGROUND")
    pBarBg:SetAllPoints()
    pBarBg:SetColorTexture(0.08, 0.09, 0.12, 0.9)

    local badgesLabel = heroCard:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    badgesLabel:SetPoint("TOPRIGHT", -16, -64)
    badgesLabel:SetText(string.format("%s |cff2ecc71%d Done|r   %s |cff00e5ff%d Ready|r   %s |cfff39c12%d Active|r   %s |cffe74c3c%d To-Do|r",
        WQT.ICON_CHECK, doneCount,
        WQT.ICON_READY, readyCount,
        WQT.ICON_PROGRESS, progressCount,
        WQT.ICON_CROSS, incompleteCount))

    currentY = currentY - 108

    -- 2. Section Header: Weekly Tasks List
    local listHeader = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    listHeader:SetPoint("TOPLEFT", parent, "TOPLEFT", 4, currentY)
    listHeader:SetSize(totalWidth, 28)
    listHeader:SetBackdrop(CARD_BACKDROP)
    listHeader:SetBackdropColor(0.15, 0.17, 0.22, 1)
    listHeader:SetBackdropBorderColor(0.35, 0.40, 0.50, 0.9)

    local listTitle = listHeader:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    listTitle:SetPoint("LEFT", 12, 0)
    listTitle:SetText("|cffffd100Weekly Quests for " .. name .. "|r")

    local listHint = listHeader:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    listHint:SetPoint("RIGHT", -12, 0)
    listHint:SetText("|cffaaaaaaShift + Left-Click any card to cycle status manually|r")

    currentY = currentY - 34

    -- 3. The 6 Individual Quest Cards (Height: 52px each)
    local cardHeight = 52
    for index, q in ipairs(quests) do
        local qName = q.name
        local qs = charQuests[qName]
        local state = qs and qs.state or (qs and qs.completed and "DONE") or "INCOMPLETE"

        local rowCard = CreateFrame("Button", nil, parent, "BackdropTemplate")
        rowCard:SetPoint("TOPLEFT", parent, "TOPLEFT", 4, currentY)
        rowCard:SetSize(totalWidth, cardHeight)
        rowCard:SetBackdrop(CARD_BACKDROP)

        if state == "DONE" then
            rowCard:SetBackdropColor(0.09, 0.16, 0.11, 0.95)
            rowCard:SetBackdropBorderColor(0.20, 0.65, 0.35, 0.85)
        elseif state == "READY" then
            rowCard:SetBackdropColor(0.08, 0.17, 0.24, 0.95)
            rowCard:SetBackdropBorderColor(0.0, 0.85, 1.0, 0.95)
        elseif state == "PROGRESS" then
            rowCard:SetBackdropColor(0.18, 0.15, 0.08, 0.95)
            rowCard:SetBackdropBorderColor(0.95, 0.70, 0.15, 0.95)
        else
            rowCard:SetBackdropColor(0.10, 0.11, 0.14, 0.9)
            rowCard:SetBackdropBorderColor(0.25, 0.28, 0.35, 0.7)
        end

        local numBadge = CreateFrame("Frame", nil, rowCard, "BackdropTemplate")
        numBadge:SetSize(28, 28)
        numBadge:SetPoint("LEFT", 12, 0)
        numBadge:SetBackdrop(CARD_BACKDROP)
        numBadge:SetBackdropColor(0.18, 0.20, 0.26, 1)
        numBadge:SetBackdropBorderColor(0.35, 0.40, 0.50, 0.8)
        local numText = numBadge:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        numText:SetPoint("CENTER", 0, 0)
        numText:SetText(tostring(index))

        local qTitle = rowCard:CreateFontString(nil, "OVERLAY", "GameFontHighlightMedium")
        qTitle:SetPoint("TOPLEFT", numBadge, "TOPRIGHT", 12, -4)
        qTitle:SetText("|cffffd100" .. qName .. "|r")

        local qSub = rowCard:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        qSub:SetPoint("BOTTOMLEFT", numBadge, "BOTTOMRIGHT", 12, 4)
        local hint = "Weekly Quest"
        if qName:find("Unity Against the Void") then
            hint = "Midnight Choice: Arcantina - Abundance - Ritual Sites - Delves"
        elseif qName:find("Runestones") then
            hint = "Hallowfall / Midnight Weekly Defense"
        elseif qName:find("Turn Back the Surge") then
            hint = "Coiled Isle - The Cursed Surge Public Event"
        elseif qName:find("Root of the World") then
            hint = "Haranir Relics & Sacred Legends"
        elseif qName:find("Offerings") then
            hint = "Loa of Abundance Weekly Harvest"
        elseif qName:find("Trailing Xal") then
            hint = "Weekly Storyline Investigation"
        end
        qSub:SetText("|cff999999" .. hint .. "|r")

        local statusPill = CreateFrame("Frame", nil, rowCard, "BackdropTemplate")
        statusPill:SetSize(185, 32)
        statusPill:SetPoint("RIGHT", rowCard, "RIGHT", -12, 0)
        statusPill:SetBackdrop(CARD_BACKDROP)

        local pillText = statusPill:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        pillText:SetPoint("CENTER", 0, 0)

        if state == "DONE" then
            statusPill:SetBackdropColor(0.10, 0.25, 0.14, 0.95)
            statusPill:SetBackdropBorderColor(0.25, 0.85, 0.40, 1)
            pillText:SetText(WQT.ICON_CHECK .. "  |cff2ecc71DONE|r")
        elseif state == "READY" then
            statusPill:SetBackdropColor(0.08, 0.22, 0.28, 0.95)
            statusPill:SetBackdropBorderColor(0.0, 0.85, 1.0, 1)
            pillText:SetText(WQT.ICON_READY .. "  |cff00e5ffREADY TO TURN IN|r")
        elseif state == "PROGRESS" then
            statusPill:SetBackdropColor(0.24, 0.18, 0.08, 0.95)
            statusPill:SetBackdropBorderColor(0.95, 0.70, 0.15, 1)
            pillText:SetText(WQT.ICON_PROGRESS .. "  |cfff39c12IN PROGRESS|r")
        else
            statusPill:SetBackdropColor(0.14, 0.12, 0.14, 0.9)
            statusPill:SetBackdropBorderColor(0.60, 0.25, 0.25, 0.8)
            pillText:SetText(WQT.ICON_CROSS .. "  |cffe74c3cINCOMPLETE|r")
        end

        rowCard:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        rowCard:SetScript("OnEnter", function(self)
            self:SetBackdropBorderColor(1.0, 0.85, 0.2, 1)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(qName, 1, 0.82, 0)
            GameTooltip:AddLine("Status: " .. state, 1, 1, 1)
            GameTooltip:AddLine("Tracked IDs: " .. table.concat(q.ids or {}, ", "), 0.7, 0.7, 0.7)
            GameTooltip:AddLine(" ", 1, 1, 1)
            GameTooltip:AddLine("|cffffcc00Shift + Left-Click: Cycle status manually|r", 0.9, 0.9, 0.2)
            GameTooltip:Show()
        end)
        rowCard:SetScript("OnLeave", function(self)
            if state == "DONE" then
                self:SetBackdropBorderColor(0.20, 0.65, 0.35, 0.85)
            elseif state == "READY" then
                self:SetBackdropBorderColor(0.0, 0.85, 1.0, 0.95)
            elseif state == "PROGRESS" then
                self:SetBackdropBorderColor(0.95, 0.70, 0.15, 0.95)
            else
                self:SetBackdropBorderColor(0.25, 0.28, 0.35, 0.7)
            end
            GameTooltip:Hide()
        end)
        rowCard:SetScript("OnClick", function(self, button)
            if IsShiftKeyDown() and button == "LeftButton" then
                WQT.ToggleQuestStatus(currentKey, qName)
            end
        end)

        currentY = currentY - (cardHeight + 6)
    end

    parent:SetHeight(math.abs(currentY) + 50)
    return currentY
end

-- =========================================================================
-- VIEW 1: GRID VIEW (MATRIX TABLE)
-- =========================================================================
function WQT.RenderGridView(sortedChars, quests, startY)
    local parent = contentScrollChild
    local headerHeight = 44
    local rowHeight = 32
    local colCharWidth = 165
    local totalWidth = 980
    local availableWidth = totalWidth - colCharWidth
    local numQuests = math.max(#quests, 1)
    local colQuestWidth = math.floor(availableWidth / numQuests)
    local totalRowWidth = colCharWidth + (#quests * colQuestWidth)
    local currentY = startY or 0
    local currentKey = WQT.GetPlayerKey()

    local headerRow = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    headerRow:SetPoint("TOPLEFT", parent, "TOPLEFT", 4, currentY)
    headerRow:SetSize(totalRowWidth, headerHeight)
    headerRow:SetBackdrop(CARD_BACKDROP)
    headerRow:SetBackdropColor(0.14, 0.16, 0.22, 1)
    headerRow:SetBackdropBorderColor(0.35, 0.40, 0.52, 0.9)

    local charHeaderLabel = headerRow:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    charHeaderLabel:SetPoint("LEFT", 10, 0)
    charHeaderLabel:SetText("|cffffd100Character (Realm)|r")

    for i, q in ipairs(quests) do
        local qHeader = CreateFrame("Button", nil, headerRow)
        qHeader:SetPoint("LEFT", headerRow, "LEFT", colCharWidth + (i - 1) * colQuestWidth, 0)
        qHeader:SetSize(colQuestWidth - 4, headerHeight)

        local qText = qHeader:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        qText:SetPoint("CENTER", 0, 0)
        qText:SetWidth(colQuestWidth - 6)
        qText:SetHeight(38)
        qText:SetWordWrap(true)
        qText:SetJustifyH("CENTER")
        qText:SetText("|cffffd100" .. q.name .. "|r")

        qHeader:RegisterForClicks("RightButtonUp")
        qHeader:SetScript("OnClick", function(self, btn)
            if btn == "RightButton" then
                StaticPopupDialogs["WQT_CONFIRM_REMOVE_QUEST"] = {
                    text = "Do you want to stop tracking quest:\n|cffffd100" .. q.name .. "|r?",
                    button1 = "Yes",
                    button2 = "No",
                    OnAccept = function() WQT.RemoveQuest(i) end,
                    timeout = 0,
                    whileDead = true,
                    hideOnEscape = true,
                }
                StaticPopup_Show("WQT_CONFIRM_REMOVE_QUEST")
            end
        end)
        qHeader:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine(q.name, 1, 0.82, 0)
            GameTooltip:AddLine("Tracked IDs: " .. table.concat(q.ids or {}, ", "), 0.7, 0.7, 0.7)
            GameTooltip:AddLine("|cffff4444Right-Click to remove quest|r", 0.9, 0.3, 0.3)
            GameTooltip:Show()
        end)
        qHeader:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end

    currentY = currentY - (headerHeight + 4)

    for rowIndex, charItem in ipairs(sortedChars) do
        local charKey = charItem.key
        local charData = charItem.data
        local isCurrentChar = (charKey == currentKey)
        local isEven = (rowIndex % 2 == 0)

        local row = CreateFrame("Frame", nil, parent, "BackdropTemplate")
        row:SetPoint("TOPLEFT", parent, "TOPLEFT", 4, currentY)
        row:SetSize(totalRowWidth, rowHeight)
        row:SetBackdrop(CARD_BACKDROP)

        if isCurrentChar then
            row:SetBackdropColor(0.14, 0.18, 0.28, 0.98)
            row:SetBackdropBorderColor(0.0, 0.85, 1.0, 0.95)
        else
            local baseBgR = isEven and 0.08 or 0.12
            local baseBgG = isEven and 0.09 or 0.13
            local baseBgB = isEven and 0.12 or 0.16
            row:SetBackdropColor(baseBgR, baseBgG, baseBgB, 0.9)
            row:SetBackdropBorderColor(0.22, 0.24, 0.30, 0.5)
        end

        local charBtn = CreateFrame("Button", nil, row)
        charBtn:SetPoint("LEFT", row, "LEFT", 4, 0)
        charBtn:SetSize(colCharWidth - 8, rowHeight)

        local charLabel = charBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        charLabel:SetPoint("LEFT", 4, 0)
        local charPrefix = isCurrentChar and "|cff00e5ff[You] |r" or ""
        local charSuffix = isCurrentChar and " |cff00e5ff(You)|r" or string.format(" |cff888888(%s)|r", charData.realm or "")
        charLabel:SetText(charPrefix .. GetFormattedName(charData) .. charSuffix)

        charBtn:SetScript("OnEnter", function()
            if not isCurrentChar then
                row:SetBackdropColor(0.20, 0.24, 0.32, 1)
                row:SetBackdropBorderColor(0.4, 0.5, 0.7, 0.8)
            end
        end)
        charBtn:SetScript("OnLeave", function()
            if not isCurrentChar then
                local baseBgR = isEven and 0.08 or 0.12
                local baseBgG = isEven and 0.09 or 0.13
                local baseBgB = isEven and 0.12 or 0.16
                row:SetBackdropColor(baseBgR, baseBgG, baseBgB, 0.9)
                row:SetBackdropBorderColor(0.22, 0.24, 0.30, 0.5)
            end
        end)

        charBtn:RegisterForClicks("RightButtonUp")
        charBtn:SetScript("OnClick", function(self, btn)
            if btn == "RightButton" then
                StaticPopupDialogs["WQT_CONFIRM_REMOVE_CHAR"] = {
                    text = "Remove alt |cffffd100" .. charData.name .. "|r from tracker?",
                    button1 = "Remove",
                    button2 = "Cancel",
                    OnAccept = function() WQT.RemoveCharacter(charKey) end,
                    timeout = 0,
                    whileDead = true,
                    hideOnEscape = true,
                }
                StaticPopup_Show("WQT_CONFIRM_REMOVE_CHAR")
            end
        end)

        for qIndex, q in ipairs(quests) do
            local cell = CreateFrame("Button", nil, row)
            cell:SetPoint("LEFT", row, "LEFT", colCharWidth + (qIndex - 1) * colQuestWidth, 0)
            cell:SetSize(colQuestWidth - 4, rowHeight)
            cell:RegisterForClicks("LeftButtonUp")

            local statusText = cell:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            statusText:SetPoint("CENTER", 0, 0)

            local qStatus = charData.quests and charData.quests[q.name]
            statusText:SetText(WQT.GetStatusString(qStatus, true)) -- Compact short status!

            cell:SetScript("OnClick", function(self)
                if IsShiftKeyDown() then
                    WQT.ToggleQuestStatus(charKey, q.name)
                end
            end)

            cell:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:AddLine(charData.name .. " - " .. q.name, 1, 0.82, 0)
                GameTooltip:AddLine("Current State: " .. WQT.GetStatusString(qStatus, false))
                GameTooltip:AddLine("|cffffcc00Shift + Click:|r Cycle status manually (Done / Ready / In Progress / Incomplete)", 0.8, 0.8, 0.8)
                GameTooltip:Show()
            end)
            cell:SetScript("OnLeave", function() GameTooltip:Hide() end)
        end

        currentY = currentY - (rowHeight + 2)
    end

    parent:SetHeight(math.abs(currentY) + 50)
    return currentY
end

-- =========================================================================
-- VIEW 2: CARDS VIEW
-- =========================================================================
function WQT.RenderCardsView(sortedChars, quests, startY)
    local parent = contentScrollChild
    local totalWidth = 980
    local cardWidth = 484
    local currentY = startY or 0
    local isLeft = true
    local totalQuests = #quests
    local cardHeight = 65 + (totalQuests * 22)
    local currentKey = WQT.GetPlayerKey()

    for index, charItem in ipairs(sortedChars) do
        local charKey = charItem.key
        local charData = charItem.data
        local charQuests = charData.quests or {}
        local isCurrentChar = (charKey == currentKey)

        local completedCount = 0
        local readyCount = 0
        for _, q in ipairs(quests) do
            local qs = charQuests[q.name]
            if qs and (qs.state == "DONE" or qs.completed) then
                completedCount = completedCount + 1
            elseif qs and (qs.state == "READY" or qs.readyToTurnIn) then
                readyCount = readyCount + 1
            end
        end

        local card = CreateFrame("Frame", nil, parent, "BackdropTemplate")
        card:SetSize(cardWidth, cardHeight)
        card:SetBackdrop(CARD_BACKDROP)

        if isCurrentChar then
            card:SetBackdropColor(0.13, 0.16, 0.25, 0.98)
            card:SetBackdropBorderColor(0.0, 0.85, 1.0, 1.0)
        else
            card:SetBackdropColor(0.10, 0.11, 0.15, 0.95)
            card:SetBackdropBorderColor(0.26, 0.30, 0.38, 0.85)
        end

        if isLeft then
            card:SetPoint("TOPLEFT", parent, "TOPLEFT", 4, currentY)
        else
            card:SetPoint("TOPLEFT", parent, "TOPLEFT", 496, currentY)
        end

        local cardTitle = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightMedium")
        cardTitle:SetPoint("TOPLEFT", 12, -10)
        local tag = isCurrentChar and " |cff00e5ff(Current Alt)|r" or string.format(" |cff888888(%s)|r", charData.realm or "")
        cardTitle:SetText(GetFormattedName(charData) .. tag)

        local badge = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        badge:SetPoint("TOPRIGHT", -12, -10)
        if completedCount == totalQuests and totalQuests > 0 then
            badge:SetText("|cff2ecc71" .. completedCount .. " / " .. totalQuests .. " Done|r")
        elseif readyCount > 0 then
            badge:SetText(string.format("|cff00e5ff%d Ready to Turn In|r", readyCount))
        else
            badge:SetText(string.format("|cffffcc00%d / %d Done|r", completedCount, totalQuests))
        end

        local bar = CreateFrame("StatusBar", nil, card)
        bar:SetPoint("TOPLEFT", 12, -32)
        bar:SetSize(cardWidth - 24, 8)
        bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
        bar:SetMinMaxValues(0, math.max(totalQuests, 1))
        bar:SetValue(completedCount)
        if completedCount == totalQuests and totalQuests > 0 then
            bar:SetStatusBarColor(0.18, 0.8, 0.35)
        else
            bar:SetStatusBarColor(0.9, 0.7, 0.15)
        end

        local qItemY = -48
        for _, q in ipairs(quests) do
            local qBtn = CreateFrame("Button", nil, card)
            qBtn:SetPoint("TOPLEFT", 14, qItemY)
            qBtn:SetSize(cardWidth - 28, 20)
            qBtn:RegisterForClicks("LeftButtonUp")

            local qLine = qBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            qLine:SetPoint("LEFT", 0, 0)
            qLine:SetWidth(cardWidth - 170)
            qLine:SetWordWrap(false)
            qLine:SetJustifyH("LEFT")
            qLine:SetText(q.name)

            local statusIcon = qBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            statusIcon:SetPoint("RIGHT", 0, 0)

            local qs = charQuests[q.name]
            statusIcon:SetText(WQT.GetStatusString(qs))

            qBtn:SetScript("OnClick", function()
                if IsShiftKeyDown() then
                    WQT.ToggleQuestStatus(charKey, q.name)
                end
            end)

            qItemY = qItemY - 22
        end

        if not isLeft then
            currentY = currentY - (cardHeight + 12)
            isLeft = true
        else
            isLeft = false
        end
    end

    if not isLeft then
        currentY = currentY - (cardHeight + 12)
    end

    parent:SetHeight(math.abs(currentY) + 50)
    return currentY
end

-- =========================================================================
-- VIEW 3: TO-DO VIEW (FOCUS ON INCOMPLETE & READY TO TURN IN)
-- =========================================================================
function WQT.RenderTodoView(sortedChars, quests, startY, isSubSection)
    local parent = contentScrollChild
    local currentY = startY or 0
    local totalWidth = 980
    local currentKey = WQT.GetPlayerKey()

    local sectionHeader = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    sectionHeader:SetPoint("TOPLEFT", parent, "TOPLEFT", 4, currentY)
    sectionHeader:SetSize(totalWidth, 28)
    sectionHeader:SetBackdrop(CARD_BACKDROP)
    sectionHeader:SetBackdropColor(0.18, 0.14, 0.08, 0.95)
    sectionHeader:SetBackdropBorderColor(0.5, 0.4, 0.18, 0.9)

    local secTitle = sectionHeader:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    secTitle:SetPoint("LEFT", 12, 0)
    secTitle:SetText("|cffffcc00Remaining Weekly Tasks & Turn-Ins (To-Do Focus)|r")

    currentY = currentY - 34

    local hasAnyIncomplete = false

    for _, charItem in ipairs(sortedChars) do
        local charKey = charItem.key
        local charData = charItem.data
        local charQuests = charData.quests or {}
        local isCurrentChar = (charKey == currentKey)

        local pending = {}
        for _, q in ipairs(quests) do
            local qs = charQuests[q.name]
            if not qs or (qs.state ~= "DONE" and not qs.completed) then
                table.insert(pending, { name = q.name, status = qs })
            end
        end

        if #pending > 0 then
            hasAnyIncomplete = true
            local itemHeight = 34 + (#pending * 22)

            local itemBox = CreateFrame("Frame", nil, parent, "BackdropTemplate")
            itemBox:SetPoint("TOPLEFT", parent, "TOPLEFT", 4, currentY)
            itemBox:SetSize(totalWidth, itemHeight)
            itemBox:SetBackdrop(CARD_BACKDROP)

            if isCurrentChar then
                itemBox:SetBackdropColor(0.14, 0.17, 0.26, 0.95)
                itemBox:SetBackdropBorderColor(0.0, 0.85, 1.0, 0.95)
            else
                itemBox:SetBackdropColor(0.11, 0.12, 0.16, 0.88)
                itemBox:SetBackdropBorderColor(0.3, 0.32, 0.4, 0.6)
            end

            local charName = itemBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightMedium")
            charName:SetPoint("TOPLEFT", 12, -8)
            local tag = isCurrentChar and " |cff00e5ff(Current Alt)|r" or string.format(" |cff888888(%s)|r", charData.realm or "")
            charName:SetText(GetFormattedName(charData) .. tag)

            local countBadge = itemBox:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            countBadge:SetPoint("TOPRIGHT", -14, -8)
            countBadge:SetText(string.format("|cffe74c3c%d Quests Remaining|r", #pending))

            local mY = -32
            for _, item in ipairs(pending) do
                local qBtn = CreateFrame("Button", nil, itemBox)
                qBtn:SetPoint("TOPLEFT", 26, mY)
                qBtn:SetSize(totalWidth - 50, 20)
                qBtn:RegisterForClicks("LeftButtonUp")

                local qLine = qBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                qLine:SetPoint("LEFT", 0, 0)

                local st = item.status and item.status.state
                if st == "READY" or (item.status and item.status.readyToTurnIn) then
                    qLine:SetText(WQT.ICON_READY .. "  |cffffffff" .. item.name .. "|r |cff00e5ff(Ready to Turn In!)|r")
                elseif st == "PROGRESS" or (item.status and item.status.inProgress) then
                    qLine:SetText(WQT.ICON_PROGRESS .. "  |cffffffff" .. item.name .. "|r |cfff39c12(In Progress)|r")
                else
                    qLine:SetText(WQT.ICON_CROSS .. "  |cffffffff" .. item.name .. "|r |cffe74c3c(Not Started)|r")
                end

                qBtn:SetScript("OnClick", function()
                    if IsShiftKeyDown() then
                        WQT.ToggleQuestStatus(charKey, item.name)
                    end
                end)

                mY = mY - 22
            end

            currentY = currentY - (itemHeight + 8)
        end
    end

    if not hasAnyIncomplete then
        local allDoneBox = CreateFrame("Frame", nil, parent, "BackdropTemplate")
        allDoneBox:SetPoint("TOPLEFT", parent, "TOPLEFT", 4, currentY)
        allDoneBox:SetSize(totalWidth, 48)
        allDoneBox:SetBackdrop(CARD_BACKDROP)
        allDoneBox:SetBackdropColor(0.08, 0.20, 0.11, 0.9)
        allDoneBox:SetBackdropBorderColor(0.2, 0.6, 0.3, 0.8)

        local allDoneText = allDoneBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightMedium")
        allDoneText:SetPoint("CENTER", 0, 0)
        allDoneText:SetText(WQT.ICON_CHECK .. "  |cff2ecc71All weekly quests completed across all characters!|r")

        currentY = currentY - 56
    end

    parent:SetHeight(math.abs(currentY) + 50)
    return currentY
end

-- =========================================================================
-- DIALOG: ADD NEW QUEST DYNAMICALLY
-- =========================================================================
function WQT.ShowAddQuestDialog()
    if addQuestDialog then
        addQuestDialog:Show()
        return
    end

    local d = CreateFrame("Frame", "WQT_AddQuestDialog", UIParent, "BackdropTemplate")
    d:SetSize(380, 210)
    d:SetPoint("CENTER")
    d:SetMovable(true)
    d:EnableMouse(true)
    d:RegisterForDrag("LeftButton")
    d:SetScript("OnDragStart", d.StartMoving)
    d:SetScript("OnDragStop", d.StopMovingOrSizing)
    d:SetBackdrop(FRAME_BACKDROP)
    d:SetBackdropColor(0.10, 0.12, 0.16, 0.98)
    d:SetBackdropBorderColor(0.4, 0.5, 0.65, 1)
    d:SetFrameStrata("DIALOG")

    local title = d:CreateFontString(nil, "OVERLAY", "GameFontHighlightMedium")
    title:SetPoint("TOP", 0, -14)
    title:SetText("|cffffd100Track New Quest|r")

    local idLabel = d:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    idLabel:SetPoint("TOPLEFT", 24, -48)
    idLabel:SetText("Quest ID (Number):")

    local idBox = CreateFrame("EditBox", nil, d, "InputBoxTemplate")
    idBox:SetSize(140, 22)
    idBox:SetPoint("TOPLEFT", 24, -66)
    idBox:SetAutoFocus(false)
    idBox:SetNumeric(true)

    local nameLabel = d:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    nameLabel:SetPoint("TOPLEFT", 24, -100)
    nameLabel:SetText("Quest Name (Optional / Auto-fetch):")

    local nameBox = CreateFrame("EditBox", nil, d, "InputBoxTemplate")
    nameBox:SetSize(330, 22)
    nameBox:SetPoint("TOPLEFT", 24, -118)
    nameBox:SetAutoFocus(false)

    local saveBtn = CreateFrame("Button", nil, d, "BackdropTemplate")
    saveBtn:SetSize(110, 26)
    saveBtn:SetPoint("BOTTOMLEFT", 45, 18)
    saveBtn:SetBackdrop(CARD_BACKDROP)
    saveBtn:SetBackdropColor(0.15, 0.28, 0.18, 1)
    saveBtn:SetBackdropBorderColor(0.3, 0.7, 0.35, 1)
    local saveBtnText = saveBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    saveBtnText:SetPoint("CENTER", 0, 0)
    saveBtnText:SetText("|cff2ecc71Add Quest|r")

    saveBtn:SetScript("OnClick", function()
        local qid = tonumber(idBox:GetText())
        local qname = nameBox:GetText()
        if qid and qid > 0 then
            WQT.AddQuest(qname, qid)
            d:Hide()
            idBox:SetText("")
            nameBox:SetText("")
        else
            print(WQT.ADDON_TITLE .. ": Please enter a valid Quest ID number.")
        end
    end)

    local cancelBtn = CreateFrame("Button", nil, d, "BackdropTemplate")
    cancelBtn:SetSize(110, 26)
    cancelBtn:SetPoint("BOTTOMRIGHT", -45, 18)
    cancelBtn:SetBackdrop(CARD_BACKDROP)
    cancelBtn:SetBackdropColor(0.24, 0.12, 0.14, 1)
    cancelBtn:SetBackdropBorderColor(0.6, 0.25, 0.3, 1)
    local cancelBtnText = cancelBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    cancelBtnText:SetPoint("CENTER", 0, 0)
    cancelBtnText:SetText("|cffe74c3cCancel|r")
    cancelBtn:SetScript("OnClick", function() d:Hide() end)

    addQuestDialog = d
    d:Show()
end

-- =========================================================================
-- MAP INTEGRATION 1: WORLD MAP BUTTON ('M' KEY)
-- =========================================================================
function WQT.CreateWorldMapButton()
    if not WorldMapFrame then return end
    if _G["WQT_WorldMapButton"] then return end

    local btn = CreateFrame("Button", "WQT_WorldMapButton", WorldMapFrame, "BackdropTemplate")
    btn:SetSize(28, 28)
    btn:SetFrameStrata("HIGH")
    btn:SetFrameLevel(100)
    btn:SetPoint("TOPRIGHT", WorldMapFrame, "TOPRIGHT", -68, -4)

    btn:SetBackdrop(CARD_BACKDROP)
    btn:SetBackdropColor(0.10, 0.12, 0.16, 0.95)
    btn:SetBackdropBorderColor(0.35, 0.50, 0.75, 1)

    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetTexture("Interface\\Icons\\INV_Misc_Book_09")
    icon:SetPoint("CENTER", 0, 0)
    icon:SetSize(18, 18)

    btn:SetScript("OnClick", function()
        WQT.ToggleUI()
    end)

    btn:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(1, 0.82, 0, 1)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(WQT.ADDON_TITLE, 1, 1, 1)
        GameTooltip:AddLine("Click to toggle Weekly Quest Tracker", 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)

    btn:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(0.35, 0.50, 0.75, 1)
        GameTooltip:Hide()
    end)
end

-- =========================================================================
-- MAP INTEGRATION 2: NATIVE ADDON COMPARTMENT (MINIMAP MENU)
-- =========================================================================
function WQT_OnAddonCompartmentClick(addonName, buttonName)
    WQT.ToggleUI()
end

function WQT_OnAddonCompartmentEnter(addonName, button)
    GameTooltip:SetOwner(button, "ANCHOR_LEFT")
    GameTooltip:AddLine(WQT.ADDON_TITLE, 1, 1, 1)
    GameTooltip:AddLine("Click to open Weekly Quest Tracker", 0.8, 0.8, 0.8)
    GameTooltip:Show()
end

function WQT_OnAddonCompartmentLeave(addonName, button)
    GameTooltip:Hide()
end

-- =========================================================================
-- MAP INTEGRATION 3: FLOATING / DRAGGABLE MINIMAP ICON
-- =========================================================================
function WQT.CreateMinimapButton()
    if _G["WQT_MinimapButton"] then return end

    local btn = CreateFrame("Button", "WQT_MinimapButton", MinimapBackdrop or Minimap or UIParent)
    btn:SetSize(33, 33)
    btn:SetFrameStrata("HIGH")
    btn:SetFrameLevel(500)

    local icon = btn:CreateTexture(nil, "BACKGROUND")
    icon:SetTexture("Interface\\Icons\\INV_Misc_Book_09")
    icon:SetSize(21, 21)
    icon:SetPoint("CENTER")

    local border = btn:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetSize(54, 54)
    border:SetPoint("TOPLEFT")

    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    btn:RegisterForDrag("LeftButton")

    local function UpdatePosition(angle)
        local rad = math.rad(angle)
        local radius = (Minimap and (Minimap:GetWidth() / 2) + 8) or 105
        local cos = math.cos(rad)
        local sin = math.sin(rad)
        local x = cos * radius
        local y = sin * radius
        btn:ClearAllPoints()
        btn:SetPoint("CENTER", Minimap, "CENTER", x, y)
    end

    local currentAngle = (WeeklyQuestTrackerDB and WeeklyQuestTrackerDB.settings and WeeklyQuestTrackerDB.settings.minimapAngle) or 220
    UpdatePosition(currentAngle)

    btn:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local px, py = GetCursorPosition()
            local scale = Minimap:GetEffectiveScale()
            px, py = px / scale, py / scale
            local angle = math.deg(math.atan2(py - my, px - mx))
            if angle < 0 then angle = angle + 360 end
            if WeeklyQuestTrackerDB and WeeklyQuestTrackerDB.settings then
                WeeklyQuestTrackerDB.settings.minimapAngle = angle
            end
            UpdatePosition(angle)
        end)
    end)

    btn:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
    end)

    btn:SetScript("OnClick", function(self, button)
        if button == "LeftButton" then
            WQT.ToggleUI()
        elseif button == "RightButton" then
            local modes = { "current", "grid", "cards", "todo" }
            local nextIdx = 1
            for i, m in ipairs(modes) do
                if m == activeTab then
                    nextIdx = (i % #modes) + 1
                    break
                end
            end
            WQT.SetViewMode(modes[nextIdx])
            print(string.format("%s: Switched view to |cffffd100%s|r", WQT.ADDON_TITLE, modes[nextIdx]:upper()))
        end
    end)

    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine(WQT.ADDON_TITLE, 1, 1, 1)
        GameTooltip:AddLine("Track weekly quests across all characters", 0.8, 0.8, 0.8)

        local currentKey = WQT.GetPlayerKey()
        local charData = WeeklyQuestTrackerDB and WeeklyQuestTrackerDB.characters and WeeklyQuestTrackerDB.characters[currentKey]
        if charData and charData.quests then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Current Alt (" .. (charData.name or "") .. "):", 1, 0.82, 0)
            local quests = WeeklyQuestTrackerDB.quests or {}
            for _, q in ipairs(quests) do
                local status = charData.quests[q.name]
                GameTooltip:AddDoubleLine(q.name, WQT.GetStatusString(status))
            end
        end

        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("|cff00ff00Left-Click:|r Toggle Tracker Window", 0.7, 0.7, 0.7)
        GameTooltip:AddLine("|cff00ff00Right-Click:|r Cycle View Mode", 0.7, 0.7, 0.7)
        GameTooltip:AddLine("|cff00ff00Drag:|r Move Icon around Minimap", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)

    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

-- =========================================================================
-- TOGGLE MAIN FRAME
-- =========================================================================
function WQT.ToggleUI()
    local f = WQT.CreateMainFrame()
    if f:IsShown() then
        f:Hide()
    else
        f:Show()
        if WeeklyQuestTrackerDB and WeeklyQuestTrackerDB.settings then
            activeTab = WeeklyQuestTrackerDB.settings.viewMode or "grid"
        end
        WQT.SetViewMode(activeTab)
    end
end

-- Auto init map buttons upon loading
local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:RegisterEvent("PLAYER_ENTERING_WORLD")
loader:SetScript("OnEvent", function()
    WQT.CreateMinimapButton()
    WQT.CreateWorldMapButton()
end)

-- Also hook WorldMapFrame OnShow to ensure map button is always present
if WorldMapFrame then
    WorldMapFrame:HookScript("OnShow", function()
        WQT.CreateWorldMapButton()
    end)
end
