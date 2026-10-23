--[[
    WeeklyQuestTracker - Core Logic
    Handles character tracking, Blizzard QuestLog querying, and weekly resets.
]]

local addonName, WQT = ...

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("QUEST_TURNED_IN")
f:RegisterEvent("QUEST_REMOVED")
f:RegisterEvent("QUEST_ACCEPTED")
f:RegisterEvent("QUEST_LOG_UPDATE")
f:RegisterEvent("QUEST_WATCH_UPDATE")
f:RegisterEvent("PLAYER_CAMPING")
pcall(function() f:RegisterEvent("WEEKLY_REWARDS_UPDATE") end)

-- Helper: Get current character key (e.g. "Thrall-TwistingNether")
function WQT.GetPlayerKey()
    local name = UnitName("player")
    local realm = GetNormalizedRealmName() or GetRealmName() or "UnknownRealm"
    return string.format("%s-%s", name, realm)
end

-- Initialize or migrate Database
function WQT.InitDB()
    if not WeeklyQuestTrackerDB then
        WeeklyQuestTrackerDB = {}
    end

    if not WeeklyQuestTrackerDB.characters then
        WeeklyQuestTrackerDB.characters = {}
    end

    if not WeeklyQuestTrackerDB.quests or #WeeklyQuestTrackerDB.quests == 0 then
        WeeklyQuestTrackerDB.quests = {}
        for _, q in ipairs(WQT.DEFAULT_QUESTS) do
            table.insert(WeeklyQuestTrackerDB.quests, {
                name = q.name,
                ids = q.ids,
                isWeekly = q.isWeekly,
            })
        end
    else
        -- Purge any overlapping foreign IDs (e.g. 89507 from Abundant Offerings)
        local forbiddenForRoot = {
            [89505] = true, [89506] = true, [89507] = true, [89508] = true, [89509] = true, [89510] = true,
            [81682] = true, [82146] = true, [90573] = true, [90574] = true, [90575] = true, [90576] = true,
        }

        for _, q in ipairs(WeeklyQuestTrackerDB.quests) do
            if q.name == "The Story of the Root of the World" or q.name == "Lost Legends" then
                q.name = "The Story of the Root of the World"

                local cleanIDs = {}
                for _, id in ipairs(q.ids or {}) do
                    if not forbiddenForRoot[id] then
                        table.insert(cleanIDs, id)
                    end
                end

                -- Add standard Haranir candidate IDs
                local defaultCandidateIDs = nil
                for _, defQ in ipairs(WQT.DEFAULT_QUESTS) do
                    if defQ.name == "The Story of the Root of the World" then
                        defaultCandidateIDs = defQ.ids
                        break
                    end
                end

                if defaultCandidateIDs then
                    local existingMap = {}
                    for _, id in ipairs(cleanIDs) do existingMap[id] = true end
                    for _, newId in ipairs(defaultCandidateIDs) do
                        if not existingMap[newId] and not forbiddenForRoot[newId] then
                            table.insert(cleanIDs, newId)
                        end
                    end
                end

                q.ids = cleanIDs
            end
        end

        -- Migrate characters saved data for the renamed quest
        for _, charData in pairs(WeeklyQuestTrackerDB.characters) do
            if charData.quests and charData.quests["Lost Legends"] then
                if not charData.quests["The Story of the Root of the World"] then
                    charData.quests["The Story of the Root of the World"] = charData.quests["Lost Legends"]
                end
                charData.quests["Lost Legends"] = nil
            end
        end

        -- Ensure all default quests (e.g. Unity Against the Void) exist in user DB
        for _, defQ in ipairs(WQT.DEFAULT_QUESTS) do
            local found = false
            for _, q in ipairs(WeeklyQuestTrackerDB.quests) do
                if q.name == defQ.name then
                    found = true
                    local idMap = {}
                    for _, id in ipairs(q.ids or {}) do idMap[id] = true end
                    for _, newId in ipairs(defQ.ids or {}) do
                        if not idMap[newId] then
                            table.insert(q.ids, newId)
                        end
                    end
                    break
                end
            end
            if not found then
                table.insert(WeeklyQuestTrackerDB.quests, {
                    name = defQ.name,
                    ids = { unpack(defQ.ids or {}) },
                    isWeekly = defQ.isWeekly,
                })
            end
        end
    end

    if not WeeklyQuestTrackerDB.settings then
        WeeklyQuestTrackerDB.settings = {}
    end
    for k, v in pairs(WQT.DEFAULT_CONFIG) do
        if WeeklyQuestTrackerDB.settings[k] == nil then
            WeeklyQuestTrackerDB.settings[k] = v
        end
    end

    -- Upgrade old book icon to modern Golden Compass by default
    if WeeklyQuestTrackerDB.settings.iconTexture == "Interface\\Icons\\INV_Misc_Book_09" or not WeeklyQuestTrackerDB.settings.iconTexture then
        WeeklyQuestTrackerDB.settings.iconTexture = "Interface\\Icons\\inv_misc_compass_01"
    end
    if not WeeklyQuestTrackerDB.settings.theme then
        WeeklyQuestTrackerDB.settings.theme = "modern"
    end
end

-- Check and handle weekly reset across all characters
function WQT.CheckWeeklyReset()
    local now = time()
    local secondsUntilReset = C_DateAndTime.GetSecondsUntilWeeklyReset() or 0
    local estimatedNextReset = now + secondsUntilReset

    if not WeeklyQuestTrackerDB.nextWeeklyReset then
        WeeklyQuestTrackerDB.nextWeeklyReset = estimatedNextReset
        return
    end

    if now >= WeeklyQuestTrackerDB.nextWeeklyReset then
        for charKey, charData in pairs(WeeklyQuestTrackerDB.characters) do
            if charData.quests then
                for qName, qStatus in pairs(charData.quests) do
                    charData.quests[qName] = {
                        state = "INCOMPLETE",
                        completed = false,
                        readyToTurnIn = false,
                        inProgress = false,
                        lastCheck = now
                    }
                end
            end
            if charData.vault then
                charData.vault = {
                    raid = 0,
                    mythic = 0,
                    world = 0,
                    total = 0,
                    lastUpdate = now,
                }
            end
        end

        WeeklyQuestTrackerDB.nextWeeklyReset = estimatedNextReset
        print(string.format("%s: Weekly reset detected! All character weekly quests have been refreshed.", WQT.ADDON_TITLE))

        if WQT.RefreshUI then
            WQT.RefreshUI()
        end
    end
end

-- Determine precise quest status:
-- Returns: "DONE", "READY", "PROGRESS", or "INCOMPLETE"
function WQT.GetQuestStatus(questEntry)
    if not questEntry or not questEntry.ids then return "INCOMPLETE" end

    -- 1. Check if actively in player's QuestLog
    local hasActiveQuest = false
    local isAnyComplete = false
    for _, qid in ipairs(questEntry.ids) do
        if C_QuestLog.IsOnQuest(qid) then
            hasActiveQuest = true
            if C_QuestLog.IsComplete(qid) then
                isAnyComplete = true
                break
            end
        end
    end

    if hasActiveQuest then
        if isAnyComplete then
            return "READY" -- Active and objectives done: needs to be turned in to NPC!
        else
            return "PROGRESS" -- Active in log, still doing objectives
        end
    end

    -- 2. If NOT active in QuestLog, check if flagged completed (Done & turned in)
    for _, qid in ipairs(questEntry.ids) do
        if C_QuestLog.IsQuestFlaggedCompleted(qid) then
            return "DONE"
        end
    end

    return "INCOMPLETE"
end

-- =========================================================================
-- FEATURE 4: GREAT VAULT SUMMARY (RAID / MYTHIC+ / DELVES)
-- =========================================================================
function WQT.ScanGreatVault()
    local result = {
        raid = 0,
        mythic = 0,
        world = 0,
        total = 0,
        lastUpdate = time(),
    }

    pcall(function()
        if not (C_WeeklyRewards and C_WeeklyRewards.GetActivities) then return end

        local raidType = Enum and Enum.WeeklyRewardChestThresholdType and Enum.WeeklyRewardChestThresholdType.Raid
        local mythicType = Enum and Enum.WeeklyRewardChestThresholdType and (Enum.WeeklyRewardChestThresholdType.MythicPlus or Enum.WeeklyRewardChestThresholdType.Activities)
        local worldType = Enum and Enum.WeeklyRewardChestThresholdType and Enum.WeeklyRewardChestThresholdType.World

        local function checkActivitiesList(acts, targetType, fallbackNum)
            local count = 0
            for _, act in ipairs(acts or {}) do
                local matches = false
                if targetType and act.type == targetType then
                    matches = true
                elseif fallbackNum and act.type == fallbackNum then
                    matches = true
                elseif not targetType and not fallbackNum then
                    matches = true
                end

                if matches then
                    local prog = act.progress or 0
                    local thresh = act.threshold or 0
                    if thresh > 0 and prog >= thresh then
                        count = count + 1
                    end
                end
            end
            return count
        end

        local allActs = C_WeeklyRewards.GetActivities() or {}
        local r, m, w = 0, 0, 0
        if #allActs > 0 then
            r = checkActivitiesList(allActs, raidType, 3)
            m = checkActivitiesList(allActs, mythicType, 1)
            w = checkActivitiesList(allActs, worldType, 4)
            if w == 0 and worldType then
                w = checkActivitiesList(allActs, worldType, nil)
            end
        else
            if raidType then r = checkActivitiesList(C_WeeklyRewards.GetActivities(raidType)) end
            if mythicType then m = checkActivitiesList(C_WeeklyRewards.GetActivities(mythicType)) end
            if worldType then w = checkActivitiesList(C_WeeklyRewards.GetActivities(worldType)) end
        end

        result.raid = math.min(math.max(r, 0), 3)
        result.mythic = math.min(math.max(m, 0), 3)
        result.world = math.min(math.max(w, 0), 3)
        result.total = result.raid + result.mythic + result.world
    end)

    return result
end

function WQT.PrintVaultSummary()
    local allChars = WeeklyQuestTrackerDB and WeeklyQuestTrackerDB.characters or {}
    local currentKey = WQT.GetPlayerKey()
    print(string.format("%s: |cffffcc00=== Great Vault Weekly Summary ===|r", WQT.ADDON_TITLE))

    local sorted = {}
    for k, v in pairs(allChars) do
        table.insert(sorted, { key = k, data = v })
    end
    table.sort(sorted, function(a, b)
        local aIsCurrent = (a.key == currentKey)
        local bIsCurrent = (b.key == currentKey)
        if aIsCurrent ~= bIsCurrent then return aIsCurrent end

        local aFav = a.data.favorite and true or false
        local bFav = b.data.favorite and true or false
        if aFav ~= bFav then return aFav end

        return (a.data.name or "") < (b.data.name or "")
    end)

    if #sorted == 0 then
        print("  (No characters tracked yet)")
        return
    end

    for _, item in ipairs(sorted) do
        local cData = item.data
        local v = (cData and cData.vault) or {}
        local vRaid = tonumber(v.raid) or 0
        local vMythic = tonumber(v.mythic) or 0
        local vWorld = tonumber(v.world) or 0
        local vTotal = tonumber(v.total) or (vRaid + vMythic + vWorld)
        local _, _, _, hex = WQT.GetClassColor(cData.class)
        local tag = (item.key == currentKey) and " |cff00e5ff(Current Alt)|r" or ""
        local favStar = cData.favorite and "|cffffd100★ |r" or ""
        print(string.format("  • %s|c%s%s|r%s: |cffffffffRaid:|r |c%s%d/3|r | |cffffffffMythic:|r |c%s%d/3|r | |cffffffffDelves:|r |c%s%d/3|r (|cffffcc00Total: %d/9|r)",
            favStar, hex or "ffffffff", cData.name or item.key, tag,
            vRaid > 0 and "ff2ecc71" or "ffaaaaaa", vRaid,
            vMythic > 0 and "ff2ecc71" or "ffaaaaaa", vMythic,
            vWorld > 0 and "ff2ecc71" or "ffaaaaaa", vWorld,
            vTotal))
    end
end

-- Scan the currently logged-in character's quest status
function WQT.ScanCurrentCharacter()
    if not WeeklyQuestTrackerDB or not WeeklyQuestTrackerDB.characters then return end

    local charKey = WQT.GetPlayerKey()
    local name = UnitName("player")
    local realm = GetNormalizedRealmName() or GetRealmName() or ""
    local _, classFile = UnitClass("player")
    local level = UnitLevel("player")

    if not WeeklyQuestTrackerDB.characters[charKey] then
        WeeklyQuestTrackerDB.characters[charKey] = {
            name = name,
            realm = realm,
            class = classFile,
            level = level,
            favorite = false,
            quests = {},
        }
    else
        WeeklyQuestTrackerDB.characters[charKey].class = classFile
        WeeklyQuestTrackerDB.characters[charKey].level = level
    end

    local charQuests = WeeklyQuestTrackerDB.characters[charKey].quests

    -- Evaluate each tracked quest into 4 states
    for _, questEntry in ipairs(WeeklyQuestTrackerDB.quests) do
        local state = WQT.GetQuestStatus(questEntry)
        charQuests[questEntry.name] = {
            state = state,
            completed = (state == "DONE"),
            readyToTurnIn = (state == "READY"),
            inProgress = (state == "PROGRESS"),
            lastCheck = time(),
        }
    end

    -- Feature 4: Scan and update Great Vault slot counts
    WeeklyQuestTrackerDB.characters[charKey].vault = WQT.ScanGreatVault()

    WeeklyQuestTrackerDB.characters[charKey].lastUpdate = time()

    if WQT.RefreshUI then
        WQT.RefreshUI()
    end
    if WQT.UpdateMiniHUD then
        WQT.UpdateMiniHUD()
    end
end

-- Toggle status manually (Shift+Click on cell cycles states)
function WQT.ToggleQuestStatus(charKey, questName)
    if not WeeklyQuestTrackerDB.characters[charKey] then return end
    local charQuests = WeeklyQuestTrackerDB.characters[charKey].quests
    if not charQuests[questName] then
        charQuests[questName] = { state = "DONE", completed = true, readyToTurnIn = false, inProgress = false, lastCheck = time() }
    else
        local cur = charQuests[questName].state or (charQuests[questName].completed and "DONE") or "INCOMPLETE"
        local nextState = "INCOMPLETE"
        if cur == "INCOMPLETE" then
            nextState = "PROGRESS"
        elseif cur == "PROGRESS" then
            nextState = "READY"
        elseif cur == "READY" then
            nextState = "DONE"
        else
            nextState = "INCOMPLETE"
        end

        charQuests[questName].state = nextState
        charQuests[questName].completed = (nextState == "DONE")
        charQuests[questName].readyToTurnIn = (nextState == "READY")
        charQuests[questName].inProgress = (nextState == "PROGRESS")
        charQuests[questName].lastCheck = time()
    end

    local stateStr = WQT.GetStatusString(charQuests[questName])
    print(string.format("%s: Manually set |cffffd100%s|r on %s to %s.", WQT.ADDON_TITLE, questName, charKey, stateStr))

    if WQT.RefreshUI then WQT.RefreshUI() end
    if WQT.UpdateMiniHUD then WQT.UpdateMiniHUD() end
end
WQT.CycleQuestStatus = WQT.ToggleQuestStatus

-- Add a new quest to the tracker dynamically
function WQT.AddQuest(name, questID)
    if not questID or questID <= 0 then
        print(string.format("%s: Invalid Quest ID.", WQT.ADDON_TITLE))
        return false
    end

    if not name or name:match("^%s*$") then
        local questTitle = C_QuestLog.GetTitleForQuestID(questID)
        if questTitle and questTitle ~= "" then
            name = questTitle
        else
            name = "Quest #" .. questID
        end
    end

    for _, q in ipairs(WeeklyQuestTrackerDB.quests) do
        if q.name:lower() == name:lower() then
            for _, id in ipairs(q.ids) do
                if id == questID then
                    print(string.format("%s: Quest ID %d already tracked under '%s'.", WQT.ADDON_TITLE, questID, q.name))
                    return false
                end
            end
            table.insert(q.ids, questID)
            print(string.format("%s: Added ID %d to existing quest '%s'.", WQT.ADDON_TITLE, questID, q.name))
            WQT.ScanCurrentCharacter()
            return true
        end
    end

    table.insert(WeeklyQuestTrackerDB.quests, {
        name = name,
        ids = { questID },
        isWeekly = true,
    })

    print(string.format("%s: Successfully added quest '%s' (ID: %d).", WQT.ADDON_TITLE, name, questID))
    WQT.ScanCurrentCharacter()
    return true
end

-- Remove a quest from tracking
function WQT.RemoveQuest(index)
    if not WeeklyQuestTrackerDB.quests[index] then return end
    local removedName = WeeklyQuestTrackerDB.quests[index].name
    table.remove(WeeklyQuestTrackerDB.quests, index)

    for _, c in pairs(WeeklyQuestTrackerDB.characters) do
        if c.quests then
            c.quests[removedName] = nil
        end
    end

    print(string.format("%s: Removed quest '%s' from tracker.", WQT.ADDON_TITLE, removedName))
    if WQT.RefreshUI then WQT.RefreshUI() end
end

-- Restore default 6 Midnight quests
function WQT.ResetToDefaultQuests()
    WeeklyQuestTrackerDB.quests = {}
    for _, q in ipairs(WQT.DEFAULT_QUESTS) do
        table.insert(WeeklyQuestTrackerDB.quests, {
            name = q.name,
            ids = { unpack(q.ids or {}) },
            isWeekly = q.isWeekly,
        })
    end
    print(string.format("%s: Restored default 6 Midnight quests.", WQT.ADDON_TITLE))
    WQT.ScanCurrentCharacter()
    if WQT.RefreshUI then WQT.RefreshUI() end
end

-- Remove an unwanted character record
function WQT.RemoveCharacter(charKey)
    if WeeklyQuestTrackerDB.characters[charKey] then
        WeeklyQuestTrackerDB.characters[charKey] = nil
        print(string.format("%s: Character '%s' removed from tracker.", WQT.ADDON_TITLE, charKey))
        if WQT.RefreshUI then WQT.RefreshUI() end
        if WQT.UpdateMiniHUD then WQT.UpdateMiniHUD() end
    end
end

-- Diagnostic: Inspect Active and Completed Quests
function WQT.CheckQuests(searchFilter)
    searchFilter = (searchFilter or ""):lower():match("^%s*(.-)%s*$")
    print(string.format("%s: --- Active Quests in Log ---", WQT.ADDON_TITLE))

    local numEntries = C_QuestLog.GetNumQuestLogEntries() or 0
    local foundActive = 0
    for i = 1, numEntries do
        local info = C_QuestLog.GetInfo(i)
        if info and not info.isHeader then
            local t = info.title or "Unknown"
            if searchFilter == "" or t:lower():find(searchFilter, 1, true) then
                print(string.format("  • [ID: |cff00ff00%d|r] |cffffd100%s|r (Ready to Turn In: %s)",
                    info.questID, t, tostring(info.isComplete or false)))
                foundActive = foundActive + 1
            end
        end
    end
    if foundActive == 0 then
        print("  (No active quests matching filter)")
    end

    -- If a Quest Choice window is open, inspect choice options
    pcall(function()
        if C_QuestChoice and C_QuestChoice.GetNumChoices then
            local num = C_QuestChoice.GetNumChoices()
            if num and num > 0 then
                print(string.format("%s: --- Quest Choice Options (%d available) ---", WQT.ADDON_TITLE, num))
                for idx = 1, num do
                    local opt = C_QuestChoice.GetQuestChoiceOptionInfo(idx)
                    if opt then
                        print(string.format("  Choice %d: |cff00ccff%s|r [OptionID: %s, QuestID: |cff00ff00%s|r]",
                            idx, tostring(opt.title or opt.header or opt.buttonText or "Choice"),
                            tostring(opt.choiceID or opt.responseID or "N/A"),
                            tostring(opt.questID or "N/A")))
                    end
                end
            end
        end
    end)
end

-- =========================================================================
-- FEATURE 3: ALT INCOMPLETE REMINDER ON LOGOUT
-- =========================================================================
local lastReminderTime = 0

function WQT.CheckAndShowLogoutReminder(isManualTest)
    if not isManualTest then
        local enabled = (WeeklyQuestTrackerDB and WeeklyQuestTrackerDB.settings and WeeklyQuestTrackerDB.settings.logoutReminder ~= false)
        if not enabled then return end

        local now = time()
        if (now - lastReminderTime) < 20 then return end
        lastReminderTime = now
    end

    local quests = WeeklyQuestTrackerDB and WeeklyQuestTrackerDB.quests or {}
    local totalQuests = #quests
    if totalQuests == 0 then return end

    local currentKey = WQT.GetPlayerKey()
    local allChars = WeeklyQuestTrackerDB and WeeklyQuestTrackerDB.characters or {}

    -- 1. Check Current Character
    local currentCharData = allChars[currentKey]
    local currentCharPending = 0
    if currentCharData and currentCharData.quests then
        for _, q in ipairs(quests) do
            local qs = currentCharData.quests[q.name]
            if not qs or (qs.state ~= "DONE" and not qs.completed) then
                currentCharPending = currentCharPending + 1
            end
        end
    end

    -- 2. Check Other Alts
    local pendingAlts = {}
    for cKey, cData in pairs(allChars) do
        if cKey ~= currentKey then
            local pCount = 0
            local cQuests = cData.quests or {}
            for _, q in ipairs(quests) do
                local qs = cQuests[q.name]
                if not qs or (qs.state ~= "DONE" and not qs.completed) then
                    pCount = pCount + 1
                end
            end
            if pCount > 0 then
                local _, _, _, hex = WQT.GetClassColor(cData.class)
                table.insert(pendingAlts, {
                    name = cData.name or cKey,
                    classHex = hex or "ffffffff",
                    pending = pCount,
                    favorite = cData.favorite and true or false,
                })
            end
        end
    end

    table.sort(pendingAlts, function(a, b)
        if a.favorite ~= b.favorite then return a.favorite end
        return a.pending > b.pending
    end)

    -- If no characters have pending quests
    if currentCharPending == 0 and #pendingAlts == 0 then
        if isManualTest then
            print(string.format("%s: |cff2ecc71All weekly quests are 100%% complete across all characters!|r", WQT.ADDON_TITLE))
        end
        return
    end

    -- Show On-Screen Reminder Toast Banner
    local charName = (currentCharData and currentCharData.name) or UnitName("player") or "You"
    local _, classFile = UnitClass("player")
    local _, _, _, charHex = WQT.GetClassColor(currentCharData and currentCharData.class or classFile)
    local currentCharInfo = {
        name = charName,
        classHex = charHex or "ffffffff",
    }

    if WQT.ShowLogoutReminderToast then
        WQT.ShowLogoutReminderToast(currentCharInfo, currentCharPending, pendingAlts, totalQuests)
    end

    -- Print Clean Summary to Chat
    print(string.format("%s: |cffffcc00=== Logout Reminder: Pending Weekly Tasks ===|r", WQT.ADDON_TITLE))
    if currentCharPending > 0 then
        print(string.format("  • |cffffd100Current Alt|r (|c%s%s|r): |cffe74c3c%d / %d quests incomplete!|r",
            charHex or "ffffffff", charName, currentCharPending, totalQuests))
    else
        print(string.format("  • |cffffd100Current Alt|r (|c%s%s|r): |cff2ecc71All %d quests completed!|r",
            charHex or "ffffffff", charName, totalQuests))
    end

    if #pendingAlts > 0 then
        local altStrs = {}
        for _, a in ipairs(pendingAlts) do
            local star = a.favorite and "|cffffd100★|r" or ""
            table.insert(altStrs, string.format("%s|c%s%s|r (|cffe74c3c%d|r)", star, a.classHex, a.name, a.pending))
        end
        print(string.format("  • |cffffd100Other Incomplete Alts (%d):|r %s", #pendingAlts, table.concat(altStrs, ", ")))
    end

    -- Play warning alert sound
    pcall(function()
        PlaySound(SOUNDKIT.READY_CHECK or SOUNDKIT.RAID_WARNING)
    end)
end

-- Secure hook for Logout and Quit
pcall(function()
    hooksecurefunc("Logout", function()
        WQT.CheckAndShowLogoutReminder(false)
    end)
    hooksecurefunc("Quit", function()
        WQT.CheckAndShowLogoutReminder(false)
    end)
end)

-- Slash Commands Handler
SLASH_WEEKLYQUESTTRACKER1 = "/wqt"
SLASH_WEEKLYQUESTTRACKER2 = "/weeklyquesttracker"
SlashCmdList["WEEKLYQUESTTRACKER"] = function(msg)
    local cmd, arg1, arg2 = strsplit(" ", msg or "")
    cmd = (cmd or ""):lower()

    if cmd == "" or cmd == "show" or cmd == "toggle" then
        if WQT.ToggleUI then WQT.ToggleUI() end
    elseif cmd == "scan" then
        WQT.ScanCurrentCharacter()
        print(string.format("%s: Current character scanned successfully.", WQT.ADDON_TITLE))
    elseif cmd == "check" or cmd == "find" then
        WQT.CheckQuests(arg1)
    elseif cmd == "reset" then
        WeeklyQuestTrackerDB.nextWeeklyReset = 0
        WQT.CheckWeeklyReset()
    elseif cmd == "hud" or cmd == "bar" then
        if WQT.ToggleMiniHUD then WQT.ToggleMiniHUD() end
    elseif cmd == "reminder" or cmd == "testlogout" then
        WQT.CheckAndShowLogoutReminder(true)
    elseif cmd == "vault" or cmd == "gv" or cmd == "bank" then
        WQT.PrintVaultSummary()
    elseif cmd == "fav" or cmd == "favorite" or cmd == "star" then
        local targetKey = arg1 and arg1:lower()
        local allChars = WeeklyQuestTrackerDB and WeeklyQuestTrackerDB.characters or {}
        local foundKey = nil
        if not targetKey or targetKey == "" then
            foundKey = WQT.GetPlayerKey()
        else
            for k, c in pairs(allChars) do
                if (c.name and c.name:lower() == targetKey) or k:lower():find(targetKey, 1, true) then
                    foundKey = k
                    break
                end
            end
        end

        if foundKey and allChars[foundKey] then
            allChars[foundKey].favorite = not allChars[foundKey].favorite
            local status = allChars[foundKey].favorite and "|cffffd100★ Favorited (Pinned to top)|r" or "|cffaaaaaaUnfavorited|r"
            print(string.format("%s: %s is now %s.", WQT.ADDON_TITLE, allChars[foundKey].name or foundKey, status))
            if WQT.RefreshUI then WQT.RefreshUI() end
        else
            print(string.format("%s: Character '%s' not found.", WQT.ADDON_TITLE, tostring(arg1 or "")))
        end
    elseif cmd == "add" and arg1 then
        local qid = tonumber(arg1)
        local qname = arg2 and msg:match("add%s+%d+%s+(.+)")
        if qid then
            WQT.AddQuest(qname, qid)
        else
            print(string.format("%s: Usage: /wqt add <QuestID> [Quest Name]", WQT.ADDON_TITLE))
        end
    else
        print(string.format("%s Commands:", WQT.ADDON_TITLE))
        print("  |cff00ff00/wqt|r - Toggle tracker window")
        print("  |cff00ff00/wqt hud|r - Toggle Mini HUD floating bar on screen")
        print("  |cff00ff00/wqt vault|r - Show Great Vault summary across all alts")
        print("  |cff00ff00/wqt fav [name]|r - Star/pin character as favorite")
        print("  |cff00ff00/wqt reminder|r - Test logout reminder alert")
        print("  |cff00ff00/wqt scan|r - Re-scan current character")
        print("  |cff00ff00/wqt check [name]|r - Inspect quests and IDs in your log")
        print("  |cff00ff00/wqt add <QuestID> [Name]|r - Add a new quest")
        print("  |cff00ff00/wqt reset|r - Force weekly reset check")
    end
end

-- Event Listener
f:SetScript("OnEvent", function(self, event, arg1, ...)
    if event == "ADDON_LOADED" then
        if arg1 == addonName then
            WQT.InitDB()
        elseif arg1 == "Blizzard_WeeklyRewards" and WeeklyRewardsFrame then
            WeeklyRewardsFrame:HookScript("OnShow", function()
                WQT.ScanCurrentCharacter()
            end)
        end
    elseif event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" then
        WQT.InitDB()
        WQT.CheckWeeklyReset()
        if WeeklyQuestTrackerDB and WeeklyQuestTrackerDB.settings and WeeklyQuestTrackerDB.settings.autoOpenOnLogin then
            C_Timer.After(1.2, function()
                if WQT.ToggleUI and not (mainFrame and mainFrame:IsShown()) then
                    WQT.ToggleUI()
                end
            end)
        end
        C_Timer.After(1.5, function()
            WQT.ScanCurrentCharacter()
        end)
    elseif event == "PLAYER_CAMPING" then
        WQT.CheckAndShowLogoutReminder(false)
    elseif event == "WEEKLY_REWARDS_UPDATE" then
        C_Timer.After(0.5, function()
            WQT.ScanCurrentCharacter()
        end)
    elseif event == "QUEST_TURNED_IN" or event == "QUEST_REMOVED" or event == "QUEST_ACCEPTED" or event == "QUEST_LOG_UPDATE" or event == "QUEST_WATCH_UPDATE" then
        C_Timer.After(0.5, function()
            WQT.ScanCurrentCharacter()
        end)
    end
end)
