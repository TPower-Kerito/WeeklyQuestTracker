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

-- Modern vs Classic Theme Presets
function WQT.GetTheme()
    local themeKey = (WeeklyQuestTrackerDB and WeeklyQuestTrackerDB.settings and WeeklyQuestTrackerDB.settings.theme) or "modern"
    if themeKey == "classic" then
        return {
            name = "classic",
            frameBg = { 0.08, 0.09, 0.12, 0.96 },
            frameBorder = { 0.35, 0.38, 0.45, 1 },
            headerBg = { 0.12, 0.14, 0.18, 1 },
            headerBorder = { 0.22, 0.25, 0.32, 1 },
            cardBg = { 0.12, 0.14, 0.18, 0.9 },
            cardBorder = { 0.25, 0.28, 0.36, 0.8 },
            tabActiveBg = { 0.22, 0.26, 0.35, 1 },
            tabActiveBorder = { 0.9, 0.75, 0.2, 1 },
            tabActiveTextColor = "|cffffd100",
            tabInactiveBg = { 0.12, 0.13, 0.17, 1 },
            tabInactiveBorder = { 0.25, 0.28, 0.35, 0.6 },
            tabInactiveTextColor = "|cffa0a0a0",
        }
    else
        -- Modern Midnight Glow
        return {
            name = "modern",
            frameBg = { 0.05, 0.06, 0.09, 0.97 },
            frameBorder = { 0.14, 0.32, 0.52, 0.95 },
            headerBg = { 0.08, 0.10, 0.15, 0.98 },
            headerBorder = { 0.16, 0.28, 0.44, 0.9 },
            cardBg = { 0.07, 0.09, 0.14, 0.94 },
            cardBorder = { 0.16, 0.24, 0.36, 0.8 },
            cardHoverBorder = { 0.0, 0.85, 1.0, 1.0 },
            tabActiveBg = { 0.10, 0.22, 0.36, 1 },
            tabActiveBorder = { 0.0, 0.85, 1.0, 1 },
            tabActiveTextColor = "|cff00e5ff",
            tabInactiveBg = { 0.08, 0.09, 0.13, 0.95 },
            tabInactiveBorder = { 0.18, 0.22, 0.30, 0.75 },
            tabInactiveTextColor = "|cff8c9bb0",
        }
    end
end

function WQT.ApplyTheme()
    if not mainFrame then return end
    local theme = WQT.GetTheme()
    mainFrame:SetBackdropColor(unpack(theme.frameBg))
    mainFrame:SetBackdropBorderColor(unpack(theme.frameBorder))
    if mainFrame.header then
        mainFrame.header:SetBackdropColor(unpack(theme.headerBg))
        mainFrame.header:SetBackdropBorderColor(unpack(theme.headerBorder))
    end
end

-- Format Class Colored Name with Class Icon (Honors showClassIcons setting)
local function GetFormattedName(charData)
    local r, g, b, hex = WQT.GetClassColor(charData.class)
    local showIcons = (WeeklyQuestTrackerDB and WeeklyQuestTrackerDB.settings and WeeklyQuestTrackerDB.settings.showClassIcons ~= false)
    local icon = showIcons and WQT.GetClassIcon(charData.class) or ""
    local iconPrefix = (icon and icon ~= "") and (icon .. " ") or ""
    return string.format("%s|c%s%s|r", iconPrefix, hex, charData.name or "Unknown")
end

-- Update Minimap and Window Header Icon in Real-Time
function WQT.UpdateAddonIcon(texturePath)
    if not WeeklyQuestTrackerDB.settings then WeeklyQuestTrackerDB.settings = {} end
    WeeklyQuestTrackerDB.settings.iconTexture = texturePath
    local mb = _G["WQT_MinimapButton"]
    if mb and mb.icon then
        mb.icon:SetTexture(texturePath)
    end
    if mainFrame and mainFrame.titleIcon then
        mainFrame.titleIcon:SetTexture(texturePath)
    end
    local hud = _G["WQT_MiniHUD"]
    if hud and hud.iconTex then
        hud.iconTex:SetTexture(texturePath)
    end
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
    local theme = WQT.GetTheme()
    f:SetBackdrop(FRAME_BACKDROP)
    f:SetBackdropColor(unpack(theme.frameBg))
    f:SetBackdropBorderColor(unpack(theme.frameBorder))

    -- Register ESC key to close
    tinsert(UISpecialFrames, "WQT_MainFrame")

    -- Header / Title Bar
    local header = CreateFrame("Frame", nil, f, "BackdropTemplate")
    header:SetPoint("TOPLEFT", 4, -4)
    header:SetPoint("TOPRIGHT", -4, -4)
    header:SetHeight(42)
    header:SetBackdrop(CARD_BACKDROP)
    header:SetBackdropColor(unpack(theme.headerBg))
    header:SetBackdropBorderColor(unpack(theme.headerBorder))
    f.header = header

    -- Modern Title Icon Badge
    local iconTexture = (WeeklyQuestTrackerDB and WeeklyQuestTrackerDB.settings and WeeklyQuestTrackerDB.settings.iconTexture) or "Interface\\Icons\\inv_misc_compass_01"
    local titleIconBadge = CreateFrame("Frame", nil, header, "BackdropTemplate")
    titleIconBadge:SetSize(28, 28)
    titleIconBadge:SetPoint("LEFT", header, "LEFT", 10, 0)
    titleIconBadge:SetBackdrop(CARD_BACKDROP)
    titleIconBadge:SetBackdropColor(0.06, 0.08, 0.12, 1)
    titleIconBadge:SetBackdropBorderColor(0.0, 0.85, 1.0, 0.9)

    local titleIcon = titleIconBadge:CreateTexture(nil, "ARTWORK")
    titleIcon:SetSize(22, 22)
    titleIcon:SetPoint("CENTER", 0, 0)
    titleIcon:SetTexture(iconTexture)
    f.titleIcon = titleIcon
    f.titleIconBadge = titleIconBadge

    -- Title Text
    local title = header:CreateFontString(nil, "OVERLAY", "GameFontHighlightMedium")
    title:SetPoint("LEFT", titleIconBadge, "RIGHT", 10, 0)
    title:SetText(WQT.ADDON_TITLE .. " |cff888888v" .. WQT.VERSION .. "|r")

    -- Reset Timer Badge
    local resetBadge = CreateFrame("Frame", nil, header, "BackdropTemplate")
    resetBadge:SetPoint("LEFT", title, "RIGHT", 14, 0)
    resetBadge:SetSize(145, 24)
    resetBadge:SetBackdrop(CARD_BACKDROP)
    resetBadge:SetBackdropColor(0.16, 0.14, 0.08, 0.9)
    resetBadge:SetBackdropBorderColor(0.65, 0.55, 0.2, 0.85)

    local resetText = resetBadge:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    resetText:SetPoint("CENTER", 0, 0)
    resetText:SetText("|cffffcc00Reset: ...|r")
    f.resetText = resetText

    -- Close Button (Custom Flat Sleek)
    local closeBtn = CreateFrame("Button", nil, header, "UIPanelCloseButton")
    closeBtn:SetPoint("RIGHT", header, "RIGHT", -4, 0)
    closeBtn:SetScript("OnClick", function() f:Hide() end)

    -- "+ Add Quest" Button
    local addBtn = CreateFrame("Button", nil, header, "BackdropTemplate")
    addBtn:SetSize(105, 24)
    addBtn:SetPoint("RIGHT", closeBtn, "LEFT", -8, 0)
    addBtn:SetBackdrop(CARD_BACKDROP)
    addBtn:SetBackdropColor(0.12, 0.20, 0.32, 1)
    addBtn:SetBackdropBorderColor(0.0, 0.85, 1.0, 0.85)

    local addBtnText = addBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    addBtnText:SetPoint("CENTER", 0, 0)
    addBtnText:SetText("|cff00e5ff+ Add Quest|r")
    addBtn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.18, 0.28, 0.44, 1)
        self:SetBackdropBorderColor(0.2, 0.95, 1.0, 1)
    end)
    addBtn:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.12, 0.20, 0.32, 1)
        self:SetBackdropBorderColor(0.0, 0.85, 1.0, 0.85)
    end)
    addBtn:SetScript("OnClick", function()
        WQT.ShowAddQuestDialog()
    end)

    -- Tab Switcher Bar (5 Tabs)
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
        { id = "settings", label = "Settings" },
    }

    local lastBtn = nil
    for _, t in ipairs(tabs) do
        local btn = CreateFrame("Button", nil, tabBar, "BackdropTemplate")
        btn:SetSize(114, 26)
        if not lastBtn then
            btn:SetPoint("LEFT", tabBar, "LEFT", 0, 0)
        else
            btn:SetPoint("LEFT", lastBtn, "RIGHT", 6, 0)
        end

        btn:SetBackdrop(CARD_BACKDROP)
        btn:SetBackdropColor(unpack(theme.tabInactiveBg))
        btn:SetBackdropBorderColor(unpack(theme.tabInactiveBorder))

        local btnText = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        btnText:SetPoint("CENTER", 0, 0)
        btnText:SetText(theme.tabInactiveTextColor .. t.label .. "|r")
        btn.text = btnText

        btn:SetScript("OnEnter", function(self)
            if activeTab ~= t.id then
                self:SetBackdropColor(0.14, 0.20, 0.30, 1)
                self:SetBackdropBorderColor(0.0, 0.85, 1.0, 0.8)
                local plain = self.text:GetText():gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
                self.text:SetText("|cffffffff" .. plain .. "|r")
            end
        end)
        btn:SetScript("OnLeave", function(self)
            if activeTab ~= t.id then
                local curTheme = WQT.GetTheme()
                self:SetBackdropColor(unpack(curTheme.tabInactiveBg))
                self:SetBackdropBorderColor(unpack(curTheme.tabInactiveBorder))
                local plain = self.text:GetText():gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
                self.text:SetText(curTheme.tabInactiveTextColor .. plain .. "|r")
            end
        end)

        btn:SetScript("OnClick", function()
            if WeeklyQuestTrackerDB and WeeklyQuestTrackerDB.settings and WeeklyQuestTrackerDB.settings.soundFeedback ~= false then
                PlaySound(SOUNDKIT.U_CHAT_SCROLL_BUTTON)
            end
            WQT.SetViewMode(t.id)
        end)

        tabButtons[t.id] = btn
        lastBtn = btn
    end
    f.tabButtons = tabButtons

    -- Filter Bar (Right-aligned in tabBar for Grid, Cards, and To-Do)
    local filterBar = CreateFrame("Frame", nil, tabBar)
    filterBar:SetPoint("RIGHT", tabBar, "RIGHT", -2, 0)
    filterBar:SetSize(400, 26)
    f.filterContainer = filterBar

    local fLabel = filterBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fLabel:SetPoint("LEFT", 0, 0)
    fLabel:SetText("|cff888888Filter:|r")

    -- 1. Status Filter Button
    local statusBtn = CreateFrame("Button", nil, filterBar, "BackdropTemplate")
    statusBtn:SetSize(115, 24)
    statusBtn:SetPoint("LEFT", fLabel, "RIGHT", 6, 0)
    statusBtn:SetBackdrop(CARD_BACKDROP)
    statusBtn:SetBackdropColor(0.14, 0.16, 0.22, 1)
    statusBtn:SetBackdropBorderColor(0.3, 0.35, 0.45, 0.8)
    local statusBtnText = statusBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    statusBtnText:SetPoint("CENTER", 0, 0)
    statusBtnText:SetText("|cffffffffAll Alts|r v")
    statusBtn.text = statusBtnText
    statusBtn:SetScript("OnClick", function(self)
        WQT.ToggleStatusDropdown(self)
    end)

    -- 2. Quest Filter Button
    local questBtn = CreateFrame("Button", nil, filterBar, "BackdropTemplate")
    questBtn:SetSize(155, 24)
    questBtn:SetPoint("LEFT", statusBtn, "RIGHT", 6, 0)
    questBtn:SetBackdrop(CARD_BACKDROP)
    questBtn:SetBackdropColor(0.14, 0.16, 0.22, 1)
    questBtn:SetBackdropBorderColor(0.3, 0.35, 0.45, 0.8)
    local questBtnText = questBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    questBtnText:SetPoint("CENTER", 0, 0)
    questBtnText:SetText("|cffffffffAll Quests|r v")
    questBtn.text = questBtnText
    questBtn:SetScript("OnClick", function(self)
        WQT.ToggleQuestDropdown(self)
    end)

    -- 3. Reset Button
    local resetBtn = CreateFrame("Button", nil, filterBar, "BackdropTemplate")
    resetBtn:SetSize(22, 24)
    resetBtn:SetPoint("LEFT", questBtn, "RIGHT", 6, 0)
    resetBtn:SetBackdrop(CARD_BACKDROP)
    resetBtn:SetBackdropColor(0.24, 0.12, 0.14, 1)
    resetBtn:SetBackdropBorderColor(0.65, 0.25, 0.3, 0.9)
    local resetBtnText = resetBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    resetBtnText:SetPoint("CENTER", 0, 0)
    resetBtnText:SetText("|cffff4444X|r")
    resetBtn:SetScript("OnClick", function()
        WQT.currentStatusFilter = "ALL"
        WQT.currentQuestFilter = "ALL"
        WQT.CloseDropdownMenu()
        WQT.UpdateFilterUI()
        WQT.RefreshUI()
    end)
    resetBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Reset Filters", 1, 0.82, 0)
        GameTooltip:AddLine("Show all characters and all quests.", 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    resetBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    resetBtn:Hide()

    f.filterControls = {
        statusBtn = statusBtn,
        statusBtnText = statusBtnText,
        questBtn = questBtn,
        questBtnText = questBtnText,
        resetBtn = resetBtn,
    }

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

    local theme = WQT.GetTheme()

    if mainFrame and mainFrame.tabButtons then
        for tabId, btn in pairs(mainFrame.tabButtons) do
            local plainText = btn.text:GetText():gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
            if tabId == activeTab then
                btn:SetBackdropColor(unpack(theme.tabActiveBg))
                btn:SetBackdropBorderColor(unpack(theme.tabActiveBorder))
                btn.text:SetText(theme.tabActiveTextColor .. plainText .. "|r")
            else
                btn:SetBackdropColor(unpack(theme.tabInactiveBg))
                btn:SetBackdropBorderColor(unpack(theme.tabInactiveBorder))
                btn.text:SetText(theme.tabInactiveTextColor .. plainText .. "|r")
            end
        end
    end

    WQT.RefreshUI()
end

-- =========================================================================
-- FILTER LOGIC & DROPDOWN MENUS
-- =========================================================================
WQT.currentStatusFilter = "ALL" -- "ALL", "INCOMPLETE", "DONE"
WQT.currentQuestFilter = "ALL"  -- "ALL" or specific quest.name

local dropdownMenu = nil

function WQT.CloseDropdownMenu()
    if dropdownMenu then dropdownMenu:Hide() end
end

function WQT.OpenDropdownMenu(anchorBtn, items)
    if not dropdownMenu then
        dropdownMenu = CreateFrame("Frame", "WQT_FilterDropdownMenu", UIParent, "BackdropTemplate")
        dropdownMenu:SetFrameStrata("DIALOG")
        dropdownMenu:SetBackdrop(FRAME_BACKDROP)
        dropdownMenu:SetBackdropColor(0.10, 0.12, 0.16, 0.98)
        dropdownMenu:SetBackdropBorderColor(0.35, 0.45, 0.65, 1)
        dropdownMenu:EnableMouse(true)
    end

    if dropdownMenu:IsShown() and dropdownMenu.currentAnchor == anchorBtn then
        dropdownMenu:Hide()
        return
    end

    dropdownMenu.currentAnchor = anchorBtn
    for _, child in ipairs({ dropdownMenu:GetChildren() }) do
        child:Hide()
        child:SetParent(nil)
    end

    local itemHeight = 24
    local menuWidth = math.max(anchorBtn:GetWidth() + 30, 220)
    local totalHeight = 10 + (#items * itemHeight)

    dropdownMenu:ClearAllPoints()
    dropdownMenu:SetPoint("TOPLEFT", anchorBtn, "BOTTOMLEFT", 0, -3)
    dropdownMenu:SetSize(menuWidth, totalHeight)

    local curY = -6
    for _, it in ipairs(items) do
        local btn = CreateFrame("Button", nil, dropdownMenu)
        btn:SetSize(menuWidth - 12, itemHeight)
        btn:SetPoint("TOPLEFT", dropdownMenu, "TOPLEFT", 6, curY)

        local t = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        t:SetPoint("LEFT", 8, 0)
        t:SetText(it.text)
        btn.text = t

        local highlight = btn:CreateTexture(nil, "BACKGROUND")
        highlight:SetAllPoints()
        highlight:SetColorTexture(0.2, 0.35, 0.55, 0.45)
        highlight:Hide()

        btn:SetScript("OnEnter", function() highlight:Show() end)
        btn:SetScript("OnLeave", function() highlight:Hide() end)
        btn:SetScript("OnClick", function()
            WQT.CloseDropdownMenu()
            if it.onClick then it.onClick() end
        end)

        curY = curY - itemHeight
    end

    dropdownMenu:Show()
end

function WQT.ToggleStatusDropdown(anchor)
    local items = {
        {
            text = "|cffffffffAll Alts (No Filter)|r",
            onClick = function()
                WQT.currentStatusFilter = "ALL"
                WQT.UpdateFilterUI()
                WQT.RefreshUI()
            end
        },
        {
            text = "|cffffa500Incomplete Alts Only|r",
            onClick = function()
                WQT.currentStatusFilter = "INCOMPLETE"
                WQT.UpdateFilterUI()
                WQT.RefreshUI()
            end
        },
        {
            text = "|cff2ecc71Completed Alts Only (6/6 Done)|r",
            onClick = function()
                WQT.currentStatusFilter = "DONE"
                WQT.UpdateFilterUI()
                WQT.RefreshUI()
            end
        },
    }
    WQT.OpenDropdownMenu(anchor, items)
end

function WQT.ToggleQuestDropdown(anchor)
    local items = {
        {
            text = "|cffffffffAll Quests (No Quest Filter)|r",
            onClick = function()
                WQT.currentQuestFilter = "ALL"
                WQT.UpdateFilterUI()
                WQT.RefreshUI()
            end
        }
    }

    local quests = WeeklyQuestTrackerDB.quests or {}
    for _, q in ipairs(quests) do
        local qName = q.name
        table.insert(items, {
            text = string.format("Needs: |cffffd100%s|r", qName),
            onClick = function()
                WQT.currentQuestFilter = qName
                WQT.UpdateFilterUI()
                WQT.RefreshUI()
            end
        })
    end

    WQT.OpenDropdownMenu(anchor, items)
end

function WQT.UpdateFilterUI()
    if not mainFrame or not mainFrame.filterControls then return end
    local c = mainFrame.filterControls

    -- Status Filter Button
    if WQT.currentStatusFilter == "INCOMPLETE" then
        c.statusBtnText:SetText("|cffffa500Incomplete Only|r v")
        c.statusBtn:SetBackdropBorderColor(0.9, 0.6, 0.1, 1)
    elseif WQT.currentStatusFilter == "DONE" then
        c.statusBtnText:SetText("|cff2ecc71All Done|r v")
        c.statusBtn:SetBackdropBorderColor(0.2, 0.8, 0.3, 1)
    else
        c.statusBtnText:SetText("|cffffffffAll Alts|r v")
        c.statusBtn:SetBackdropBorderColor(0.3, 0.35, 0.45, 0.8)
    end

    -- Quest Filter Button
    if WQT.currentQuestFilter ~= "ALL" then
        local qShort = WQT.currentQuestFilter
        if #qShort > 17 then qShort = qShort:sub(1, 15) .. "..." end
        c.questBtnText:SetText(string.format("|cff00e5ffNeeds: %s|r v", qShort))
        c.questBtn:SetBackdropBorderColor(0.0, 0.85, 1.0, 1)
    else
        c.questBtnText:SetText("|cffffffffAll Quests|r v")
        c.questBtn:SetBackdropBorderColor(0.3, 0.35, 0.45, 0.8)
    end

    -- Reset Button
    if WQT.currentStatusFilter ~= "ALL" or WQT.currentQuestFilter ~= "ALL" then
        c.resetBtn:Show()
    else
        c.resetBtn:Hide()
    end
end

-- =========================================================================
-- RENDER VIEWS
-- =========================================================================
function WQT.RefreshUI()
    if not mainFrame or not mainFrame:IsShown() then return end

    WQT.ApplyTheme()

    local secsUntilReset = C_DateAndTime.GetSecondsUntilWeeklyReset() or 0
    mainFrame.resetText:SetText(string.format("|cffffcc00Reset: %s|r", WQT.FormatTimeRemaining(secsUntilReset)))

    local currentKey = WQT.GetPlayerKey()
    mainFrame.currentAltText:SetText(string.format("Current Alt: |cffffd100%s|r", currentKey))

    -- Show Filter Bar on Grid, Cards, and To-Do; hide on Current Alt and Settings
    if mainFrame.filterContainer then
        if activeTab == "current" or activeTab == "settings" then
            mainFrame.filterContainer:Hide()
        else
            mainFrame.filterContainer:Show()
        end
    end
    WQT.UpdateFilterUI()

    for _, child in ipairs({ contentScrollChild:GetChildren() }) do
        child:Hide()
        child:SetParent(nil)
    end

    local quests = WeeklyQuestTrackerDB.quests or {}
    local chars = WeeklyQuestTrackerDB.characters or {}

    local statusFilter = WQT.currentStatusFilter or "ALL"
    local questFilter = WQT.currentQuestFilter or "ALL"

    local sortedChars = {}
    for charKey, data in pairs(chars) do
        local include = true
        local charQuests = data.quests or {}

        -- 1. Status Filter Check
        if statusFilter == "INCOMPLETE" then
            local hasIncomplete = false
            for _, q in ipairs(quests) do
                local qs = charQuests[q.name]
                if not qs or (qs.state ~= "DONE" and not qs.completed) then
                    hasIncomplete = true
                    break
                end
            end
            if not hasIncomplete then include = false end
        elseif statusFilter == "DONE" then
            local allDone = (#quests > 0)
            for _, q in ipairs(quests) do
                local qs = charQuests[q.name]
                if not qs or (qs.state ~= "DONE" and not qs.completed) then
                    allDone = false
                    break
                end
            end
            if not allDone then include = false end
        end

        -- 2. Quest Filter Check: Only includes characters that NEED this quest (not finished)
        if include and questFilter ~= "ALL" then
            local qs = charQuests[questFilter]
            local isDone = qs and (qs.state == "DONE" or qs.completed)
            if isDone then
                include = false
            end
        end

        if include then
            table.insert(sortedChars, { key = charKey, data = data })
        end
    end
    local currentKey = WQT.GetPlayerKey()
    table.sort(sortedChars, function(a, b)
        local aIsCurrent = (a.key == currentKey)
        local bIsCurrent = (b.key == currentKey)
        if aIsCurrent ~= bIsCurrent then
            return aIsCurrent
        end

        local aFav = a.data.favorite and true or false
        local bFav = b.data.favorite and true or false
        if aFav ~= bFav then
            return aFav
        end

        return (a.data.name or "") < (b.data.name or "")
    end)

    if activeTab == "current" then
        WQT.RenderCurrentCharacterView(quests, 0)
    elseif activeTab == "grid" then
        WQT.RenderGridView(sortedChars, quests, 0)
    elseif activeTab == "cards" then
        WQT.RenderCardsView(sortedChars, quests, 0)
    elseif activeTab == "todo" then
        WQT.RenderTodoView(sortedChars, quests, 0)
    elseif activeTab == "settings" then
        WQT.RenderSettingsView(0)
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

    -- Character Name & Details (with Star Button)
    local isFav = charData and charData.favorite
    local favBtn = CreateFrame("Button", nil, heroCard)
    favBtn:SetSize(22, 22)
    favBtn:SetPoint("TOPLEFT", 14, -13)
    local favText = favBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    favText:SetPoint("CENTER", 0, 0)
    favText:SetText(isFav and "|cffffd100★|r" or "|cff555555☆|r")

    favBtn:SetScript("OnClick", function()
        if charData then
            charData.favorite = not charData.favorite
            if WeeklyQuestTrackerDB and WeeklyQuestTrackerDB.settings and WeeklyQuestTrackerDB.settings.soundFeedback ~= false then
                PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
            end
            WQT.RefreshUI()
        end
    end)
    favBtn:SetScript("OnEnter", function(self)
        favText:SetText("|cffffd100★|r")
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(isFav and "Favorite Alt (Pinned)" or "Mark as Favorite / Main", 1, 0.82, 0)
        GameTooltip:AddLine("Click to toggle favorite status.", 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    favBtn:SetScript("OnLeave", function(self)
        favText:SetText(isFav and "|cffffd100★|r" or "|cff555555☆|r")
        GameTooltip:Hide()
    end)

    local heroName = heroCard:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    heroName:SetPoint("LEFT", favBtn, "RIGHT", 4, 0)
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

    -- Center: Feature 4 - Great Vault Summary Badge
    local showVault = not (WeeklyQuestTrackerDB and WeeklyQuestTrackerDB.settings and WeeklyQuestTrackerDB.settings.showGreatVault == false)
    local vData = (charData and charData.vault) or {}
    local vRaid = tonumber(vData.raid) or 0
    local vMythic = tonumber(vData.mythic) or 0
    local vWorld = tonumber(vData.world) or 0
    local vTotal = tonumber(vData.total) or (vRaid + vMythic + vWorld)

    local vaultWidget = CreateFrame("Button", nil, heroCard, "BackdropTemplate")
    vaultWidget:SetPoint("CENTER", heroCard, "CENTER", -10, -2)
    vaultWidget:SetSize(310, 68)
    vaultWidget:SetBackdrop(CARD_BACKDROP)
    vaultWidget:SetBackdropColor(0.08, 0.10, 0.15, 0.95)
    vaultWidget:SetBackdropBorderColor(0.90, 0.75, 0.20, 0.85)

    if not showVault then
        vaultWidget:Hide()
    end

    local vIcon = vaultWidget:CreateTexture(nil, "ARTWORK")
    vIcon:SetSize(22, 22)
    vIcon:SetPoint("TOPLEFT", 10, -8)
    vIcon:SetTexture("Interface\\Icons\\inv_misc_coin_17")
    vIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    local vTitle = vaultWidget:CreateFontString(nil, "OVERLAY", "GameFontHighlightMedium")
    vTitle:SetPoint("LEFT", vIcon, "RIGHT", 6, 0)
    vTitle:SetText(string.format("|cffffd100Great Vault:|r |cffffcc00%d / 9 Unlocked|r", vTotal))

    local vBreakdown = vaultWidget:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    vBreakdown:SetPoint("BOTTOMLEFT", 10, 10)
    vBreakdown:SetText(string.format("|cffffffffRaid:|r |c%s%d/3|r   |cffffffffMythic:|r |c%s%d/3|r   |cffffffffDelves:|r |c%s%d/3|r",
        vRaid > 0 and "ff2ecc71" or "ffaaaaaa", vRaid,
        vMythic > 0 and "ff2ecc71" or "ffaaaaaa", vMythic,
        vWorld > 0 and "ff2ecc71" or "ffaaaaaa", vWorld))

    vaultWidget:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(1.0, 0.9, 0.3, 1)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Great Vault Summary (Weekly)", 1, 0.82, 0)
        GameTooltip:AddLine("Weekly bank reward choices unlocked for this character:", 0.8, 0.8, 0.8, true)
        GameTooltip:AddLine(" ")
        GameTooltip:AddDoubleLine("• Raid Encounters:", string.format("|c%s%d / 3 Slots|r", vRaid > 0 and "ff2ecc71" or "ffaaaaaa", vRaid), 1, 1, 1, 1, 1, 1)
        GameTooltip:AddDoubleLine("• Mythic Dungeons:", string.format("|c%s%d / 3 Slots|r", vMythic > 0 and "ff2ecc71" or "ffaaaaaa", vMythic), 1, 1, 1, 1, 1, 1)
        GameTooltip:AddDoubleLine("• World & Delves:", string.format("|c%s%d / 3 Slots|r", vWorld > 0 and "ff2ecc71" or "ffaaaaaa", vWorld), 1, 1, 1, 1, 1, 1)
        GameTooltip:AddLine(" ")
        GameTooltip:AddDoubleLine("Total Choices Available:", string.format("|c%s%d / 9 Slots|r", vTotal > 0 and "ffffcc00" or "ff888888", vTotal), 1, 0.82, 0, 1, 1, 1)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("|cff00ff00Click to open Great Vault window|r", 0.2, 1, 0.4)
        GameTooltip:Show()
    end)
    vaultWidget:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(0.90, 0.75, 0.20, 0.85)
        GameTooltip:Hide()
    end)
    vaultWidget:SetScript("OnClick", function()
        pcall(function()
            if not WeeklyRewardsFrame then
                if WeeklyRewards_LoadUI then WeeklyRewards_LoadUI() end
            end
            if WeeklyRewards_ShowUI then
                WeeklyRewards_ShowUI()
            end
        end)
    end)

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

    -- 3. The 6 Individual Quest Cards (Height: 46px each)
    local cardHeight = 46
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

        -- Single prominent quest title, perfectly centered vertically (No subtitle text)
        local qTitle = rowCard:CreateFontString(nil, "OVERLAY", "GameFontHighlightMedium")
        qTitle:SetPoint("LEFT", numBadge, "RIGHT", 14, 0)
        qTitle:SetText("|cffffd100" .. qName .. "|r")

        local statusPill = CreateFrame("Frame", nil, rowCard, "BackdropTemplate")
        statusPill:SetSize(185, 30)
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

        -- Star Button for Favorite in Grid
        local isFav = charData and charData.favorite
        local starBtn = CreateFrame("Button", nil, row)
        starBtn:SetSize(18, 18)
        starBtn:SetPoint("LEFT", row, "LEFT", 4, 0)
        local starText = starBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        starText:SetPoint("CENTER", 0, 0)
        starText:SetText(isFav and "|cffffd100★|r" or "|cff555555☆|r")

        starBtn:SetScript("OnClick", function()
            charData.favorite = not charData.favorite
            if WeeklyQuestTrackerDB and WeeklyQuestTrackerDB.settings and WeeklyQuestTrackerDB.settings.soundFeedback ~= false then
                PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
            end
            WQT.RefreshUI()
        end)
        starBtn:SetScript("OnEnter", function(self)
            starText:SetText("|cffffd100★|r")
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine(isFav and "Favorite Alt (Pinned to top)" or "Mark as Favorite / Main", 1, 0.82, 0)
            GameTooltip:AddLine("Click to toggle favorite status.", 0.8, 0.8, 0.8)
            GameTooltip:Show()
        end)
        starBtn:SetScript("OnLeave", function(self)
            starText:SetText(isFav and "|cffffd100★|r" or "|cff555555☆|r")
            GameTooltip:Hide()
        end)

        local charBtn = CreateFrame("Button", nil, row)
        charBtn:SetPoint("LEFT", starBtn, "RIGHT", 2, 0)
        charBtn:SetSize(colCharWidth - 24, rowHeight)

        local v = (charData and charData.vault) or {}
        local vRaid = tonumber(v.raid) or 0
        local vMythic = tonumber(v.mythic) or 0
        local vWorld = tonumber(v.world) or 0
        local vTotal = tonumber(v.total) or (vRaid + vMythic + vWorld)

        local charLabel = charBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        charLabel:SetPoint("LEFT", 2, 0)
        local charPrefix = isCurrentChar and "|cff00e5ff[You] |r" or ""
        local charSuffix = isCurrentChar and " |cff00e5ff(You)|r" or string.format(" |cff888888(%s)|r", charData.realm or "")
        if vTotal > 0 then
            charSuffix = charSuffix .. string.format(" |cffffcc00[%d/9]|r", vTotal)
        end
        charLabel:SetText(charPrefix .. GetFormattedName(charData) .. charSuffix)

        charBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        charBtn:SetScript("OnEnter", function(self)
            if not isCurrentChar then
                row:SetBackdropColor(0.20, 0.24, 0.32, 1)
                row:SetBackdropBorderColor(0.4, 0.5, 0.7, 0.8)
            end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(GetFormattedName(charData) .. string.format(" |cff888888(%s)|r", charData.realm or ""), 1, 0.82, 0)
            GameTooltip:AddLine(string.format("Level %d %s", charData.level or 90, charData.class or ""), 0.8, 0.8, 0.8)
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("|cffffd100Great Vault Weekly Status:|r", 1, 0.82, 0)
            GameTooltip:AddDoubleLine("  • Raid Encounters:", string.format("|c%s%d / 3 Slots|r", vRaid > 0 and "ff2ecc71" or "ffaaaaaa", vRaid), 1, 1, 1, 1, 1, 1)
            GameTooltip:AddDoubleLine("  • Mythic Dungeons:", string.format("|c%s%d / 3 Slots|r", vMythic > 0 and "ff2ecc71" or "ffaaaaaa", vMythic), 1, 1, 1, 1, 1, 1)
            GameTooltip:AddDoubleLine("  • Delves & World:", string.format("|c%s%d / 3 Slots|r", vWorld > 0 and "ff2ecc71" or "ffaaaaaa", vWorld), 1, 1, 1, 1, 1, 1)
            GameTooltip:AddDoubleLine("  Total Choices Unlocked:", string.format("|c%s%d / 9 Slots|r", vTotal > 0 and "ffffcc00" or "ff888888", vTotal), 1, 0.82, 0, 1, 1, 1)
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("|cff00ff00Left-Click: Open Great Vault window|r", 0.2, 1, 0.4)
            GameTooltip:AddLine("|cffff4444Right-Click: Remove alt from tracker|r", 0.9, 0.3, 0.3)
            GameTooltip:Show()
        end)
        charBtn:SetScript("OnLeave", function()
            if not isCurrentChar then
                local baseBgR = isEven and 0.08 or 0.12
                local baseBgG = isEven and 0.09 or 0.13
                local baseBgB = isEven and 0.12 or 0.16
                row:SetBackdropColor(baseBgR, baseBgG, baseBgB, 0.9)
                row:SetBackdropBorderColor(0.22, 0.24, 0.30, 0.5)
            end
            GameTooltip:Hide()
        end)

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
            elseif btn == "LeftButton" then
                pcall(function()
                    if not WeeklyRewardsFrame then
                        if WeeklyRewards_LoadUI then WeeklyRewards_LoadUI() end
                    end
                    if WeeklyRewards_ShowUI then
                        WeeklyRewards_ShowUI()
                    end
                end)
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
    local cardHeight = 65 + (totalQuests * 22) + 26
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

        -- Star Button for Favorite in Card
        local isFav = charData and charData.favorite
        local favBtn = CreateFrame("Button", nil, card)
        favBtn:SetSize(18, 18)
        favBtn:SetPoint("TOPLEFT", 10, -9)
        local favText = favBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightMedium")
        favText:SetPoint("CENTER", 0, 0)
        favText:SetText(isFav and "|cffffd100★|r" or "|cff555555☆|r")

        favBtn:SetScript("OnClick", function()
            charData.favorite = not charData.favorite
            if WeeklyQuestTrackerDB and WeeklyQuestTrackerDB.settings and WeeklyQuestTrackerDB.settings.soundFeedback ~= false then
                PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
            end
            WQT.RefreshUI()
        end)
        favBtn:SetScript("OnEnter", function(self)
            favText:SetText("|cffffd100★|r")
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine(isFav and "Favorite Alt (Pinned to top)" or "Mark as Favorite / Main", 1, 0.82, 0)
            GameTooltip:AddLine("Click to toggle favorite status.", 0.8, 0.8, 0.8)
            GameTooltip:Show()
        end)
        favBtn:SetScript("OnLeave", function(self)
            favText:SetText(isFav and "|cffffd100★|r" or "|cff555555☆|r")
            GameTooltip:Hide()
        end)

        local cardTitle = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightMedium")
        cardTitle:SetPoint("LEFT", favBtn, "RIGHT", 4, 0)
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

        -- Feature 4: Great Vault Footer in Card
        local v = (charData and charData.vault) or {}
        local vRaid = tonumber(v.raid) or 0
        local vMythic = tonumber(v.mythic) or 0
        local vWorld = tonumber(v.world) or 0
        local vTotal = tonumber(v.total) or (vRaid + vMythic + vWorld)

        local vLine = card:CreateTexture(nil, "ARTWORK")
        vLine:SetHeight(1)
        vLine:SetPoint("TOPLEFT", 12, qItemY - 2)
        vLine:SetPoint("TOPRIGHT", -12, qItemY - 2)
        vLine:SetColorTexture(0.25, 0.32, 0.44, 0.5)

        local vFooter = CreateFrame("Button", nil, card)
        vFooter:SetPoint("TOPLEFT", 12, qItemY - 4)
        vFooter:SetSize(cardWidth - 24, 22)

        local vText = vFooter:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        vText:SetPoint("LEFT", 2, 0)
        vText:SetText(string.format("|TInterface\\Icons\\inv_misc_coin_17:13:13:0:0:64:64:4:60:4:60|t |cffffd100Vault:|r |cffffffffR:|r |c%s%d/3|r  |cffffffffM:|r |c%s%d/3|r  |cffffffffD:|r |c%s%d/3|r",
            vRaid > 0 and "ff2ecc71" or "ffaaaaaa", vRaid,
            vMythic > 0 and "ff2ecc71" or "ffaaaaaa", vMythic,
            vWorld > 0 and "ff2ecc71" or "ffaaaaaa", vWorld))

        local vTotalText = vFooter:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        vTotalText:SetPoint("RIGHT", -2, 0)
        vTotalText:SetText(string.format("|c%s%d / 9 Slots|r", vTotal > 0 and "ffffcc00" or "ff888888", vTotal))

        vFooter:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine((charData.name or "Character") .. " - Great Vault", 1, 0.82, 0)
            GameTooltip:AddDoubleLine("• Raid Encounters:", string.format("|c%s%d / 3 Slots|r", vRaid > 0 and "ff2ecc71" or "ffaaaaaa", vRaid), 1, 1, 1, 1, 1, 1)
            GameTooltip:AddDoubleLine("• Mythic Dungeons:", string.format("|c%s%d / 3 Slots|r", vMythic > 0 and "ff2ecc71" or "ffaaaaaa", vMythic), 1, 1, 1, 1, 1, 1)
            GameTooltip:AddDoubleLine("• Delves & World:", string.format("|c%s%d / 3 Slots|r", vWorld > 0 and "ff2ecc71" or "ffaaaaaa", vWorld), 1, 1, 1, 1, 1, 1)
            GameTooltip:AddLine(" ")
            GameTooltip:AddDoubleLine("Total Choices Available:", string.format("|c%s%d / 9 Slots|r", vTotal > 0 and "ffffcc00" or "ff888888", vTotal), 1, 0.82, 0, 1, 1, 1)
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("|cff00ff00Click: Open Great Vault window|r", 0.2, 1, 0.4)
            GameTooltip:Show()
        end)
        vFooter:SetScript("OnLeave", function() GameTooltip:Hide() end)
        vFooter:SetScript("OnClick", function()
            pcall(function()
                if not WeeklyRewardsFrame then
                    if WeeklyRewards_LoadUI then WeeklyRewards_LoadUI() end
                end
                if WeeklyRewards_ShowUI then
                    WeeklyRewards_ShowUI()
                end
            end)
        end)

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
            local favPrefix = charData.favorite and "|cffffd100★ |r" or ""
            local tag = isCurrentChar and " |cff00e5ff(Current Alt)|r" or string.format(" |cff888888(%s)|r", charData.realm or "")
            charName:SetText(favPrefix .. GetFormattedName(charData) .. tag)

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

                qBtn:SetScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:AddLine(item.name, 1, 0.82, 0)
                    GameTooltip:AddLine("|cffffcc00Shift + Left-Click:|r Cycle status manually", 0.9, 0.9, 0.2)
                    GameTooltip:Show()
                end)
                qBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

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
-- VIEW 4: SETTINGS & CUSTOMIZATION
-- =========================================================================
function WQT.RenderSettingsView(startY)
    local parent = contentScrollChild
    local currentY = startY or 0
    local totalWidth = 980
    local settings = WeeklyQuestTrackerDB.settings or {}
    local currentIcon = settings.iconTexture or "Interface\\Icons\\inv_misc_compass_01"
    local currentTheme = settings.theme or "modern"

    -- 1. Hero Header Banner
    local banner = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    banner:SetPoint("TOPLEFT", parent, "TOPLEFT", 4, currentY)
    banner:SetSize(totalWidth, 54)
    banner:SetBackdrop(CARD_BACKDROP)
    banner:SetBackdropColor(0.08, 0.12, 0.18, 0.95)
    banner:SetBackdropBorderColor(0.0, 0.85, 1.0, 0.85)

    local bTitle = banner:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    bTitle:SetPoint("TOPLEFT", 16, -10)
    bTitle:SetText("|cff00e5ffSettings & Customization|r")

    local bSub = banner:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    bSub:SetPoint("TOPLEFT", 16, -32)
    bSub:SetText("|cff8e9aafPersonalize your visual theme, choose your minimap icon, and configure display options.|r")

    currentY = currentY - 64

    -- 2. Section: UI Visual Theme (Modern vs Classic)
    local themeBox = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    themeBox:SetPoint("TOPLEFT", parent, "TOPLEFT", 4, currentY)
    themeBox:SetSize(totalWidth, 105)
    themeBox:SetBackdrop(CARD_BACKDROP)
    themeBox:SetBackdropColor(0.07, 0.08, 0.12, 0.95)
    themeBox:SetBackdropBorderColor(0.20, 0.28, 0.40, 0.85)

    local tTitle = themeBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightMedium")
    tTitle:SetPoint("TOPLEFT", 14, -12)
    tTitle:SetText("|cffffd100Visual Theme Preset|r")

    local tDesc = themeBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    tDesc:SetPoint("TOPLEFT", 14, -32)
    tDesc:SetText("|cff888888Switch between the modern Midnight theme or restore the previous classic look at any time:|r")

    -- Modern Theme Button
    local modernBtn = CreateFrame("Button", nil, themeBox, "BackdropTemplate")
    modernBtn:SetPoint("TOPLEFT", 14, -54)
    modernBtn:SetSize(240, 38)
    modernBtn:SetBackdrop(CARD_BACKDROP)
    local isModern = (currentTheme == "modern")
    if isModern then
        modernBtn:SetBackdropColor(0.09, 0.18, 0.28, 1)
        modernBtn:SetBackdropBorderColor(0.0, 0.85, 1.0, 1)
    else
        modernBtn:SetBackdropColor(0.08, 0.10, 0.14, 0.9)
        modernBtn:SetBackdropBorderColor(0.2, 0.25, 0.35, 0.6)
    end
    local modernText = modernBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    modernText:SetPoint("CENTER", 0, 0)
    modernText:SetText(isModern and "|cff00e5ff[Active] Modern Midnight (Glow)|r" or "|cffffffffModern Midnight (Glow)|r")
    modernBtn:SetScript("OnClick", function()
        settings.theme = "modern"
        WQT.ApplyTheme()
        if settings.soundFeedback ~= false then PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON) end
        WQT.RefreshUI()
    end)

    -- Classic Theme Button
    local classicBtn = CreateFrame("Button", nil, themeBox, "BackdropTemplate")
    classicBtn:SetPoint("LEFT", modernBtn, "RIGHT", 14, 0)
    classicBtn:SetSize(240, 38)
    classicBtn:SetBackdrop(CARD_BACKDROP)
    local isClassic = (currentTheme == "classic")
    if isClassic then
        classicBtn:SetBackdropColor(0.16, 0.18, 0.24, 1)
        classicBtn:SetBackdropBorderColor(0.9, 0.75, 0.2, 1)
    else
        classicBtn:SetBackdropColor(0.08, 0.10, 0.14, 0.9)
        classicBtn:SetBackdropBorderColor(0.2, 0.25, 0.35, 0.6)
    end
    local classicText = classicBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    classicText:SetPoint("CENTER", 0, 0)
    classicText:SetText(isClassic and "|cffffd100[Active] Classic Slate (Previous)|r" or "|cffffffffClassic Slate (Previous Look)|r")
    classicBtn:SetScript("OnClick", function()
        settings.theme = "classic"
        WQT.ApplyTheme()
        if settings.soundFeedback ~= false then PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON) end
        WQT.RefreshUI()
    end)

    currentY = currentY - 115

    -- 3. Section: Minimap & Window Icon Style
    local iconBox = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    iconBox:SetPoint("TOPLEFT", parent, "TOPLEFT", 4, currentY)
    iconBox:SetSize(totalWidth, 140)
    iconBox:SetBackdrop(CARD_BACKDROP)
    iconBox:SetBackdropColor(0.07, 0.08, 0.12, 0.95)
    iconBox:SetBackdropBorderColor(0.20, 0.28, 0.40, 0.85)

    local iTitle = iconBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightMedium")
    iTitle:SetPoint("TOPLEFT", 14, -12)
    iTitle:SetText("|cffffd100Minimap & Tracker Icon Style|r")

    local iDesc = iconBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    iDesc:SetPoint("TOPLEFT", 14, -32)
    iDesc:SetText("|cff888888Click any icon below to instantly change your Minimap button, Compartment, and Tracker header:|r")

    local iconsList = WQT.AVAILABLE_ICONS or {}
    local tileWidth = 152
    local tileHeight = 68
    local startX = 14
    for idx, item in ipairs(iconsList) do
        local isSelected = (currentIcon == item.texture)
        local tile = CreateFrame("Button", nil, iconBox, "BackdropTemplate")
        tile:SetPoint("TOPLEFT", iconBox, "TOPLEFT", startX + (idx - 1) * (tileWidth + 8), -56)
        tile:SetSize(tileWidth, tileHeight)
        tile:SetBackdrop(CARD_BACKDROP)

        if isSelected then
            tile:SetBackdropColor(0.10, 0.20, 0.30, 1)
            tile:SetBackdropBorderColor(0.0, 0.85, 1.0, 1)
        else
            tile:SetBackdropColor(0.09, 0.10, 0.14, 0.9)
            tile:SetBackdropBorderColor(0.22, 0.26, 0.35, 0.6)
        end

        local tex = tile:CreateTexture(nil, "ARTWORK")
        tex:SetSize(28, 28)
        tex:SetPoint("TOP", 0, -8)
        tex:SetTexture(item.texture)

        local nameStr = tile:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        nameStr:SetPoint("TOP", tex, "BOTTOM", 0, -4)
        if isSelected then
            nameStr:SetText("|cff00e5ff" .. item.name .. "|r")
        else
            nameStr:SetText("|cffffffff" .. item.name .. "|r")
        end

        tile:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine(item.name, 1, 0.82, 0)
            GameTooltip:AddLine(item.desc or "Click to set this icon.", 0.8, 0.8, 0.8, true)
            if isSelected then
                GameTooltip:AddLine("|cff2ecc71Currently Selected|r", 0.2, 1, 0.4)
            end
            GameTooltip:Show()
            if not isSelected then
                self:SetBackdropBorderColor(0.4, 0.65, 0.95, 0.9)
            end
        end)
        tile:SetScript("OnLeave", function(self)
            GameTooltip:Hide()
            if not isSelected then
                self:SetBackdropBorderColor(0.22, 0.26, 0.35, 0.6)
            end
        end)
        tile:SetScript("OnClick", function()
            WQT.UpdateAddonIcon(item.texture)
            if settings.soundFeedback ~= false then PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON) end
            WQT.RefreshUI()
        end)
    end

    currentY = currentY - 150

    -- 4. Section: Interface & Display Options (Checkboxes)
    local optBox = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    optBox:SetPoint("TOPLEFT", parent, "TOPLEFT", 4, currentY)
    optBox:SetSize(totalWidth, 160)
    optBox:SetBackdrop(CARD_BACKDROP)
    optBox:SetBackdropColor(0.07, 0.08, 0.12, 0.95)
    optBox:SetBackdropBorderColor(0.20, 0.28, 0.40, 0.85)

    local oTitle = optBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightMedium")
    oTitle:SetPoint("TOPLEFT", 14, -12)
    oTitle:SetText("|cffffd100Display & Automation Options|r")

    local function CreateCheckbox(parentFrame, x, y, label, settingKey, defaultVal, onChange)
        local cb = CreateFrame("CheckButton", nil, parentFrame, "UICheckButtonTemplate")
        cb:SetPoint("TOPLEFT", x, y)
        cb:SetSize(24, 24)
        local currentVal = (settings[settingKey] == nil and defaultVal) or settings[settingKey]
        cb:SetChecked(currentVal)

        local cbLabel = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        cbLabel:SetPoint("LEFT", cb, "RIGHT", 6, 0)
        cbLabel:SetText(label)

        cb:SetScript("OnClick", function(self)
            local isChecked = self:GetChecked()
            settings[settingKey] = isChecked
            if settings.soundFeedback ~= false then PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON) end
            if onChange then onChange(isChecked) end
        end)
        return cb
    end

    -- Checkbox 1: Minimap Button
    CreateCheckbox(optBox, 14, -38, "Show Floating Minimap Icon", "showMinimapButton", true, function(val)
        local mb = _G["WQT_MinimapButton"]
        if mb then
            if val then mb:Show() else mb:Hide() end
        end
    end)

    -- Checkbox 2: Class Icons
    CreateCheckbox(optBox, 330, -38, "Show Class Icons next to Names", "showClassIcons", true, function()
        WQT.RefreshUI()
    end)

    -- Checkbox 3: Highlight Current Character
    CreateCheckbox(optBox, 640, -38, "Highlight Current Alt in Grid View", "highlightCurrentChar", true, function()
        WQT.RefreshUI()
    end)

    -- Checkbox 4: Sound Feedback
    CreateCheckbox(optBox, 14, -76, "Play Sound Feedback on Clicks", "soundFeedback", true)

    -- Checkbox 5: Auto Open on Login
    CreateCheckbox(optBox, 330, -76, "Auto-open Tracker Window on Login", "autoOpenOnLogin", false)

    -- Checkbox 6: On-Screen Mini HUD (Feature 2)
    CreateCheckbox(optBox, 640, -76, "Show On-Screen Mini HUD Bar", "showMiniHUD", true, function(val)
        if val then
            local hud = WQT.CreateMiniHUD()
            if hud then hud:Show(); WQT.UpdateMiniHUD() end
        else
            local hud = _G["WQT_MiniHUD"]
            if hud then hud:Hide() end
        end
    end)

    -- Checkbox 7: Alt Incomplete Reminder on Logout (Feature 3)
    CreateCheckbox(optBox, 14, -114, "Alt Incomplete Reminder on Logout", "logoutReminder", true)

    -- Checkbox 8: Great Vault Summary (Feature 4)
    CreateCheckbox(optBox, 330, -114, "Show Great Vault Badges (R/M/D)", "showGreatVault", true, function()
        WQT.RefreshUI()
    end)

    currentY = currentY - 175

    -- 5. Section: Database & Character Management
    local dbBox = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    dbBox:SetPoint("TOPLEFT", parent, "TOPLEFT", 4, currentY)
    dbBox:SetBackdrop(CARD_BACKDROP)
    dbBox:SetBackdropColor(0.07, 0.08, 0.12, 0.95)
    dbBox:SetBackdropBorderColor(0.20, 0.28, 0.40, 0.85)

    local dTitle = dbBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightMedium")
    dTitle:SetPoint("TOPLEFT", 14, -12)
    dTitle:SetText("|cffffd100Data & Character Management|r")

    -- Button A: Re-scan Current Character
    local scanBtn = CreateFrame("Button", nil, dbBox, "BackdropTemplate")
    scanBtn:SetPoint("TOPLEFT", 14, -36)
    scanBtn:SetSize(210, 26)
    scanBtn:SetBackdrop(CARD_BACKDROP)
    scanBtn:SetBackdropColor(0.12, 0.20, 0.32, 1)
    scanBtn:SetBackdropBorderColor(0.0, 0.85, 1.0, 0.9)
    local scanText = scanBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    scanText:SetPoint("CENTER", 0, 0)
    scanText:SetText("|cff00e5ffRe-Scan Current Alt Now|r")
    scanBtn:SetScript("OnClick", function()
        WQT.ScanCurrentCharacter()
        print(string.format("%s: Current character re-scanned successfully.", WQT.ADDON_TITLE))
        WQT.RefreshUI()
    end)

    -- Button B: Reset Default Quests
    local resetQBtn = CreateFrame("Button", nil, dbBox, "BackdropTemplate")
    resetQBtn:SetPoint("LEFT", scanBtn, "RIGHT", 14, 0)
    resetQBtn:SetSize(220, 26)
    resetQBtn:SetBackdrop(CARD_BACKDROP)
    resetQBtn:SetBackdropColor(0.22, 0.14, 0.14, 1)
    resetQBtn:SetBackdropBorderColor(0.7, 0.3, 0.3, 0.9)
    local resetQText = resetQBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    resetQText:SetPoint("CENTER", 0, 0)
    resetQText:SetText("|cffff6666Restore 6 Default Quests|r")
    resetQBtn:SetScript("OnClick", function()
        StaticPopupDialogs["WQT_CONFIRM_RESTORE_QUESTS"] = {
            text = "Reset all tracked quests back to the 6 default Midnight quests?",
            button1 = "Restore",
            button2 = "Cancel",
            OnAccept = function() WQT.ResetToDefaultQuests() end,
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
        }
        StaticPopup_Show("WQT_CONFIRM_RESTORE_QUESTS")
    end)

    -- Tracked Alts Table
    local charHeader = dbBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    charHeader:SetPoint("TOPLEFT", 14, -72)
    charHeader:SetText("|cffaaaaaaTracked Alts in Database (Click 'Remove' to delete inactive alts):|r")

    local charY = -94
    local allChars = WeeklyQuestTrackerDB.characters or {}
    local charList = {}
    for k, v in pairs(allChars) do table.insert(charList, { key = k, data = v }) end
    local curPlayerKey = WQT.GetPlayerKey()
    table.sort(charList, function(a, b)
        local aIsCurrent = (a.key == curPlayerKey)
        local bIsCurrent = (b.key == curPlayerKey)
        if aIsCurrent ~= bIsCurrent then return aIsCurrent end

        local aFav = a.data.favorite and true or false
        local bFav = b.data.favorite and true or false
        if aFav ~= bFav then return aFav end

        return (a.data.name or "") < (b.data.name or "")
    end)

    local qList = WeeklyQuestTrackerDB.quests or {}
    for _, item in ipairs(charList) do
        local cKey = item.key
        local cData = item.data
        local isCurrent = (cKey == curPlayerKey)
        local isFav = cData.favorite and true or false

        local cRow = CreateFrame("Frame", nil, dbBox, "BackdropTemplate")
        cRow:SetPoint("TOPLEFT", 14, charY)
        cRow:SetSize(totalWidth - 28, 28)
        cRow:SetBackdrop(CARD_BACKDROP)

        if isCurrent then
            cRow:SetBackdropColor(0.12, 0.16, 0.24, 0.9)
            cRow:SetBackdropBorderColor(0.0, 0.85, 1.0, 0.85)
        else
            cRow:SetBackdropColor(0.09, 0.10, 0.14, 0.8)
            cRow:SetBackdropBorderColor(0.18, 0.22, 0.30, 0.6)
        end

        local cName = cRow:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        cName:SetPoint("LEFT", 10, 0)
        local starPrefix = isFav and "|cffffd100★ |r" or ""
        local tag = isCurrent and " |cff00e5ff(Current Alt)|r" or string.format(" |cff888888(%s)|r", cData.realm or "")
        cName:SetText(starPrefix .. GetFormattedName(cData) .. tag)

        local cQuests = cData.quests or {}
        local done = 0
        for _, q in ipairs(qList) do
            local qs = cQuests[q.name]
            if qs and (qs.state == "DONE" or qs.completed) then done = done + 1 end
        end

        local delBtn = CreateFrame("Button", nil, cRow, "BackdropTemplate")
        delBtn:SetSize(64, 20)
        delBtn:SetPoint("RIGHT", -8, 0)
        delBtn:SetBackdrop(CARD_BACKDROP)
        delBtn:SetBackdropColor(0.24, 0.10, 0.12, 1)
        delBtn:SetBackdropBorderColor(0.65, 0.25, 0.25, 0.9)
        local delText = delBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        delText:SetPoint("CENTER", 0, 0)
        delText:SetText("|cffff5555Remove|r")

        -- Favorite Button in Settings
        local favBtn = CreateFrame("Button", nil, cRow, "BackdropTemplate")
        favBtn:SetSize(90, 20)
        favBtn:SetPoint("RIGHT", delBtn, "LEFT", -8, 0)
        favBtn:SetBackdrop(CARD_BACKDROP)
        if isFav then
            favBtn:SetBackdropColor(0.24, 0.20, 0.08, 1)
            favBtn:SetBackdropBorderColor(1.0, 0.85, 0.20, 0.9)
        else
            favBtn:SetBackdropColor(0.11, 0.13, 0.18, 1)
            favBtn:SetBackdropBorderColor(0.30, 0.35, 0.45, 0.7)
        end
        local favBtnText = favBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        favBtnText:SetPoint("CENTER", 0, 0)
        favBtnText:SetText(isFav and "|cffffd100★ Favorited|r" or "|cff888888☆ Favorite|r")
        favBtn:SetScript("OnClick", function()
            cData.favorite = not cData.favorite
            if WeeklyQuestTrackerDB and WeeklyQuestTrackerDB.settings and WeeklyQuestTrackerDB.settings.soundFeedback ~= false then
                PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
            end
            WQT.RefreshUI()
        end)

        local cCount = cRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        cCount:SetPoint("RIGHT", favBtn, "LEFT", -14, 0)
        cCount:SetText(string.format("|cffffcc00%d / %d Done|r", done, #qList))

        delBtn:SetScript("OnClick", function()
            StaticPopupDialogs["WQT_CONFIRM_REMOVE_CHAR_SETTINGS"] = {
                text = "Remove alt |cffffd100" .. (cData.name or cKey) .. "|r from database?",
                button1 = "Remove",
                button2 = "Cancel",
                OnAccept = function()
                    WQT.RemoveCharacter(cKey)
                end,
                timeout = 0,
                whileDead = true,
                hideOnEscape = true,
            }
            StaticPopup_Show("WQT_CONFIRM_REMOVE_CHAR_SETTINGS")
        end)

        charY = charY - 32
    end

    local dbBoxHeight = math.abs(charY) + 14
    dbBox:SetSize(totalWidth, dbBoxHeight)

    currentY = currentY - (dbBoxHeight + 20)
    parent:SetHeight(math.abs(currentY) + 60)
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
    local savedIcon = (WeeklyQuestTrackerDB and WeeklyQuestTrackerDB.settings and WeeklyQuestTrackerDB.settings.iconTexture) or "Interface\\Icons\\inv_misc_compass_01"
    icon:SetTexture(savedIcon)
    icon:SetSize(21, 21)
    icon:SetPoint("CENTER")
    btn.icon = icon

    local border = btn:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetSize(54, 54)
    border:SetPoint("TOPLEFT")

    if WeeklyQuestTrackerDB and WeeklyQuestTrackerDB.settings and WeeklyQuestTrackerDB.settings.showMinimapButton == false then
        btn:Hide()
    end

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
-- FEATURE 2: ON-SCREEN MINI HUD (FLOATING TRACKER BAR)
-- =========================================================================
local miniHUD = nil

function WQT.CreateMiniHUD()
    if miniHUD then return miniHUD end

    local hud = CreateFrame("Frame", "WQT_MiniHUD", UIParent, "BackdropTemplate")
    hud:SetSize(196, 30)
    hud:SetFrameStrata("MEDIUM")
    hud:SetClampedToScreen(true)
    hud:SetMovable(true)
    hud:EnableMouse(true)
    hud:RegisterForDrag("LeftButton")

    hud:SetBackdrop(CARD_BACKDROP)
    hud:SetBackdropColor(0.06, 0.08, 0.12, 0.94)
    hud:SetBackdropBorderColor(0.0, 0.85, 1.0, 0.85)

    -- Restore saved position or default to top center
    local pos = WeeklyQuestTrackerDB and WeeklyQuestTrackerDB.settings and WeeklyQuestTrackerDB.settings.hudPosition
    if pos and pos.point and pos.x and pos.y then
        hud:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x, pos.y)
    else
        hud:SetPoint("TOP", UIParent, "TOP", 0, -35)
    end

    hud:SetScript("OnDragStart", function(self)
        self:StartMoving()
    end)
    hud:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local pt, _, relPt, x, y = self:GetPoint()
        if WeeklyQuestTrackerDB and WeeklyQuestTrackerDB.settings then
            WeeklyQuestTrackerDB.settings.hudPosition = { point = pt, relPoint = relPt, x = x, y = y }
        end
    end)

    -- Left Icon Badge (Tiny Compass or chosen icon)
    local iconTex = hud:CreateTexture(nil, "ARTWORK")
    iconTex:SetSize(16, 16)
    iconTex:SetPoint("LEFT", 7, 0)
    local curIcon = (WeeklyQuestTrackerDB and WeeklyQuestTrackerDB.settings and WeeklyQuestTrackerDB.settings.iconTexture) or "Interface\\Icons\\inv_misc_compass_01"
    iconTex:SetTexture(curIcon)
    hud.iconTex = iconTex

    -- Smart explicit tooltip anchor to guarantee zero overlap across all screen positions
    local function AnchorHUDTooltip(targetFrame)
        local cx, cy = hud:GetCenter()
        local parentH = (UIParent and UIParent:GetHeight()) or 768
        GameTooltip:SetOwner(targetFrame, "ANCHOR_NONE")
        GameTooltip:ClearAllPoints()
        if cy and (cy > parentH / 2) then
            -- Bar is in top half of screen: firmly place tooltip BELOW the bar with clean 8px margin
            GameTooltip:SetPoint("TOP", targetFrame, "BOTTOM", 0, -8)
        else
            -- Bar is in bottom half of screen: firmly place tooltip ABOVE the bar with clean 8px margin
            GameTooltip:SetPoint("BOTTOM", targetFrame, "TOP", 0, 8)
        end
    end

    -- 6 Quest Indicator Slots (Spacing: ~18px apart)
    local slots = {}
    local startX = 28
    for i = 1, 6 do
        local slot = CreateFrame("Button", nil, hud)
        slot:SetSize(18, 18)
        slot:SetPoint("LEFT", hud, "LEFT", startX + (i - 1) * 20, 0)

        local slotIcon = slot:CreateTexture(nil, "ARTWORK")
        slotIcon:SetAllPoints()
        slotIcon:SetTexture("Interface\\RaidFrame\\ReadyCheck-NotReady")
        slot.icon = slotIcon

        slot:RegisterForClicks("LeftButtonUp")
        slot:SetScript("OnClick", function()
            WQT.ToggleUI()
        end)

        slot:SetScript("OnEnter", function(self)
            if self.questName then
                AnchorHUDTooltip(self)
                GameTooltip:AddLine(self.questName, 1, 0.85, 0)
                GameTooltip:AddLine("Status: " .. (self.statusText or "Incomplete"), 1, 1, 1)
                GameTooltip:AddLine("|cff888888Click: Open tracker|r", 0.7, 0.7, 0.7)
                GameTooltip:Show()
            end
        end)
        slot:SetScript("OnLeave", function() GameTooltip:Hide() end)

        slots[i] = slot
    end
    hud.slots = slots

    -- Right Progress Label (e.g. "4/6")
    local ratioText = hud:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    ratioText:SetPoint("RIGHT", hud, "RIGHT", -7, 0)
    ratioText:SetText("|cffffd1000/6|r")
    hud.ratioText = ratioText

    -- Main HUD Click & Hover
    hud:SetScript("OnMouseUp", function(self, button)
        if button == "LeftButton" then
            WQT.ToggleUI()
        end
    end)

    hud:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(1.0, 0.85, 0.2, 1)
        AnchorHUDTooltip(self)
        GameTooltip:AddLine(WQT.ADDON_TITLE .. " |cff888888(Mini HUD)|r", 1, 1, 1)

        local currentKey = WQT.GetPlayerKey()
        local charData = WeeklyQuestTrackerDB and WeeklyQuestTrackerDB.characters and WeeklyQuestTrackerDB.characters[currentKey]
        if charData and charData.quests then
            GameTooltip:AddLine("Current Alt: |cffffd100" .. (charData.name or "You") .. "|r", 1, 0.82, 0)
            local quests = WeeklyQuestTrackerDB.quests or {}
            for _, q in ipairs(quests) do
                local status = charData.quests[q.name]
                GameTooltip:AddDoubleLine(q.name, WQT.GetStatusString(status, true))
            end
        end

        if charData and charData.vault then
            local v = charData.vault
            local vRaid = tonumber(v.raid) or 0
            local vMythic = tonumber(v.mythic) or 0
            local vWorld = tonumber(v.world) or 0
            local vTotal = tonumber(v.total) or (vRaid + vMythic + vWorld)
            GameTooltip:AddLine(" ")
            GameTooltip:AddDoubleLine("|cffffd100Great Vault:|r", string.format("R: |c%s%d/3|r  M: |c%s%d/3|r  D: |c%s%d/3|r (|cffffcc00%d/9|r)",
                vRaid > 0 and "ff2ecc71" or "ffaaaaaa", vRaid,
                vMythic > 0 and "ff2ecc71" or "ffaaaaaa", vMythic,
                vWorld > 0 and "ff2ecc71" or "ffaaaaaa", vWorld,
                vTotal))
        end

        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("|cff00ff00Left-Click:|r Toggle Full Window", 0.7, 0.7, 0.7)
        GameTooltip:AddLine("|cff00ff00Drag:|r Move Bar on Screen", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)

    hud:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(0.0, 0.85, 1.0, 0.85)
        GameTooltip:Hide()
    end)

    miniHUD = hud

    -- Check visibility setting
    if WeeklyQuestTrackerDB and WeeklyQuestTrackerDB.settings and WeeklyQuestTrackerDB.settings.showMiniHUD == false then
        miniHUD:Hide()
    else
        miniHUD:Show()
    end

    WQT.UpdateMiniHUD()
    return miniHUD
end

function WQT.UpdateMiniHUD()
    if not miniHUD then return end

    local currentKey = WQT.GetPlayerKey()
    local charData = WeeklyQuestTrackerDB and WeeklyQuestTrackerDB.characters and WeeklyQuestTrackerDB.characters[currentKey]
    local charQuests = (charData and charData.quests) or {}
    local quests = WeeklyQuestTrackerDB.quests or {}

    local curIcon = (WeeklyQuestTrackerDB and WeeklyQuestTrackerDB.settings and WeeklyQuestTrackerDB.settings.iconTexture) or "Interface\\Icons\\inv_misc_compass_01"
    if miniHUD.iconTex then miniHUD.iconTex:SetTexture(curIcon) end

    local doneCount = 0
    local totalQuests = #quests

    for i = 1, 6 do
        local slot = miniHUD.slots[i]
        if slot then
            local q = quests[i]
            if q then
                slot:Show()
                slot.questName = q.name
                local qs = charQuests[q.name]
                local state = qs and qs.state or (qs and qs.completed and "DONE") or "INCOMPLETE"

                if state == "DONE" then
                    slot.icon:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
                    slot.statusText = "|cff2ecc71Done|r"
                    doneCount = doneCount + 1
                elseif state == "READY" then
                    slot.icon:SetTexture("Interface\\GossipFrame\\ActiveQuestIcon")
                    slot.statusText = "|cff00e5ffReady to Turn In|r"
                elseif state == "PROGRESS" then
                    slot.icon:SetTexture("Interface\\COMMON\\Indicator-Yellow")
                    slot.statusText = "|cfff39c12In Progress|r"
                else
                    slot.icon:SetTexture("Interface\\RaidFrame\\ReadyCheck-NotReady")
                    slot.statusText = "|cffe74c3cIncomplete|r"
                end
            else
                slot:Hide()
            end
        end
    end

    if miniHUD.ratioText then
        if doneCount == totalQuests and totalQuests > 0 then
            miniHUD.ratioText:SetText(string.format("|cff2ecc71%d/%d|r", doneCount, totalQuests))
            miniHUD:SetBackdropBorderColor(0.2, 0.85, 0.35, 0.95)
        else
            miniHUD.ratioText:SetText(string.format("|cffffcc00%d/%d|r", doneCount, totalQuests))
            miniHUD:SetBackdropBorderColor(0.0, 0.85, 1.0, 0.85)
        end
    end
end

function WQT.ToggleMiniHUD()
    local hud = WQT.CreateMiniHUD()
    if hud:IsShown() then
        hud:Hide()
        if WeeklyQuestTrackerDB and WeeklyQuestTrackerDB.settings then
            WeeklyQuestTrackerDB.settings.showMiniHUD = false
        end
        print(string.format("%s: Mini HUD |cffff5555hidden|r. (Type /wqt hud to show)", WQT.ADDON_TITLE))
    else
        hud:Show()
        if WeeklyQuestTrackerDB and WeeklyQuestTrackerDB.settings then
            WeeklyQuestTrackerDB.settings.showMiniHUD = true
        end
        WQT.UpdateMiniHUD()
        print(string.format("%s: Mini HUD |cff00ff00shown|r.", WQT.ADDON_TITLE))
    end
end

-- =========================================================================
-- FEATURE 3: LOGOUT REMINDER TOAST BANNER
-- =========================================================================
local logoutToast = nil
local logoutToastTimer = nil

function WQT.ShowLogoutReminderToast(currentCharInfo, currentCharPending, pendingAlts, totalQuests)
    if not logoutToast then
        logoutToast = CreateFrame("Frame", "WQT_LogoutReminderToast", UIParent, "BackdropTemplate")
        logoutToast:SetSize(460, 150)
        logoutToast:SetFrameStrata("DIALOG")
        logoutToast:SetClampedToScreen(true)
        logoutToast:SetMovable(true)
        logoutToast:EnableMouse(true)
        logoutToast:RegisterForDrag("LeftButton")
        logoutToast:SetScript("OnDragStart", logoutToast.StartMoving)
        logoutToast:SetScript("OnDragStop", function(self)
            self:StopMovingOrSizing()
            local point, _, relPoint, x, y = self:GetPoint()
            if WeeklyQuestTrackerDB and WeeklyQuestTrackerDB.settings then
                WeeklyQuestTrackerDB.settings.logoutToastPosition = {
                    point = point,
                    relPoint = relPoint,
                    x = math.floor(x + 0.5),
                    y = math.floor(y + 0.5),
                }
            end
        end)

        logoutToast:SetBackdrop(CARD_BACKDROP)
        logoutToast:SetBackdropColor(0.06, 0.08, 0.12, 0.98)
        logoutToast:SetBackdropBorderColor(1.0, 0.82, 0.15, 0.95)

        -- Position
        local pos = WeeklyQuestTrackerDB and WeeklyQuestTrackerDB.settings and WeeklyQuestTrackerDB.settings.logoutToastPosition
        if pos and pos.point and pos.x and pos.y then
            logoutToast:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x, pos.y)
        else
            logoutToast:SetPoint("TOP", UIParent, "TOP", 0, -110)
        end

        -- Header Icon (Bell)
        local icon = logoutToast:CreateTexture(nil, "ARTWORK")
        icon:SetSize(22, 22)
        icon:SetPoint("TOPLEFT", 12, -10)
        icon:SetTexture("Interface\\Icons\\inv_misc_bell_01")
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

        -- Title
        local title = logoutToast:CreateFontString(nil, "OVERLAY", "GameFontHighlightMedium")
        title:SetPoint("LEFT", icon, "RIGHT", 8, 0)
        title:SetText("|cffffd100Weekly Quest Alert|r  |cffff5555Pending Quests!|r")

        -- Close Button (X)
        local closeBtn = CreateFrame("Button", nil, logoutToast, "UIPanelCloseButton")
        closeBtn:SetSize(24, 24)
        closeBtn:SetPoint("TOPRIGHT", -4, -4)
        closeBtn:SetScript("OnClick", function()
            logoutToast:Hide()
        end)

        -- Divider line
        local sep = logoutToast:CreateTexture(nil, "ARTWORK")
        sep:SetHeight(1)
        sep:SetPoint("TOPLEFT", 12, -36)
        sep:SetPoint("TOPRIGHT", -12, -36)
        sep:SetColorTexture(0.25, 0.35, 0.48, 0.6)

        -- Content Line 1: Current character
        local currText = logoutToast:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        currText:SetPoint("TOPLEFT", 14, -44)
        currText:SetJustifyH("LEFT")
        logoutToast.currText = currText

        -- Content Line 2: Other alts
        local altsText = logoutToast:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        altsText:SetPoint("TOPLEFT", 14, -68)
        altsText:SetPoint("RIGHT", logoutToast, "RIGHT", -14, 0)
        altsText:SetJustifyH("LEFT")
        altsText:SetWordWrap(true)
        logoutToast.altsText = altsText

        -- Open Tracker Button
        local openBtn = CreateFrame("Button", nil, logoutToast, "BackdropTemplate")
        openBtn:SetSize(160, 24)
        openBtn:SetPoint("BOTTOMLEFT", 14, 12)
        openBtn:SetBackdrop(CARD_BACKDROP)
        openBtn:SetBackdropColor(0.10, 0.22, 0.35, 1)
        openBtn:SetBackdropBorderColor(0.0, 0.85, 1.0, 0.9)
        local openBtnText = openBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        openBtnText:SetPoint("CENTER", 0, 0)
        openBtnText:SetText("|cff00e5ffOpen Quest Tracker|r")
        openBtn:SetScript("OnClick", function()
            logoutToast:Hide()
            if not (mainFrame and mainFrame:IsShown()) then
                WQT.ToggleUI()
            end
        end)
        openBtn:SetScript("OnEnter", function(self)
            self:SetBackdropColor(0.15, 0.30, 0.48, 1)
        end)
        openBtn:SetScript("OnLeave", function(self)
            self:SetBackdropColor(0.10, 0.22, 0.35, 1)
        end)

        -- Dismiss Button
        local dismissBtn = CreateFrame("Button", nil, logoutToast, "BackdropTemplate")
        dismissBtn:SetSize(80, 24)
        dismissBtn:SetPoint("BOTTOMRIGHT", -14, 12)
        dismissBtn:SetBackdrop(CARD_BACKDROP)
        dismissBtn:SetBackdropColor(0.14, 0.16, 0.22, 1)
        dismissBtn:SetBackdropBorderColor(0.35, 0.40, 0.50, 0.8)
        local dismissBtnText = dismissBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        dismissBtnText:SetPoint("CENTER", 0, 0)
        dismissBtnText:SetText("|cffaaaaaaDismiss|r")
        dismissBtn:SetScript("OnClick", function()
            logoutToast:Hide()
        end)
        dismissBtn:SetScript("OnEnter", function(self)
            self:SetBackdropColor(0.20, 0.22, 0.30, 1)
        end)
        dismissBtn:SetScript("OnLeave", function(self)
            self:SetBackdropColor(0.14, 0.16, 0.22, 1)
        end)
    end

    -- Update Dynamic Text
    local cName = currentCharInfo and currentCharInfo.name or "Current Alt"
    local cHex = currentCharInfo and currentCharInfo.classHex or "ffffffff"
    if currentCharPending > 0 then
        logoutToast.currText:SetText(string.format("• |cffffd100Current Alt|r (|c%s%s|r): |cffe74c3c%d of %d quests incomplete!|r",
            cHex, cName, currentCharPending, totalQuests))
    else
        logoutToast.currText:SetText(string.format("• |cffffd100Current Alt|r (|c%s%s|r): |cff2ecc71All %d quests completed!|r",
            cHex, cName, totalQuests))
    end

    if #pendingAlts > 0 then
        local altStrs = {}
        local maxDisplay = 4
        for i = 1, math.min(#pendingAlts, maxDisplay) do
            local a = pendingAlts[i]
            local star = a.favorite and "|cffffd100★|r" or ""
            table.insert(altStrs, string.format("%s|c%s%s|r (|cffe74c3c%d|r)", star, a.classHex, a.name, a.pending))
        end
        local listStr = table.concat(altStrs, ", ")
        if #pendingAlts > maxDisplay then
            listStr = listStr .. string.format(" |cff888888(+%d more)|r", #pendingAlts - maxDisplay)
        end
        logoutToast.altsText:SetText(string.format("• |cffffd100Other Incomplete Alts (%d):|r %s", #pendingAlts, listStr))
        logoutToast:SetHeight(152)
    else
        logoutToast.altsText:SetText("• |cffffd100Other Alts:|r |cff2ecc71All other tracked alts are 100% complete!|r")
        logoutToast:SetHeight(140)
    end

    -- Cancel existing auto-hide timer and set 10-second timer
    if logoutToastTimer then
        pcall(function() logoutToastTimer:Cancel() end)
        logoutToastTimer = nil
    end
    logoutToastTimer = C_Timer.NewTimer(10, function()
        if logoutToast and logoutToast:IsShown() then
            logoutToast:Hide()
        end
    end)

    logoutToast:Show()
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

-- Auto init map buttons and Mini HUD upon loading
local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:RegisterEvent("PLAYER_ENTERING_WORLD")
loader:SetScript("OnEvent", function()
    WQT.CreateMinimapButton()
    WQT.CreateWorldMapButton()
    WQT.CreateMiniHUD()
end)

-- Also hook WorldMapFrame OnShow to ensure map button is always present
if WorldMapFrame then
    WorldMapFrame:HookScript("OnShow", function()
        WQT.CreateWorldMapButton()
    end)
end
