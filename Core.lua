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
    end

    if not WeeklyQuestTrackerDB.settings then
        WeeklyQuestTrackerDB.settings = {}
    end
    for k, v in pairs(WQT.DEFAULT_CONFIG) do
        if WeeklyQuestTrackerDB.settings[k] == nil then
            WeeklyQuestTrackerDB.settings[k] = v
        end
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

    WeeklyQuestTrackerDB.characters[charKey].lastUpdate = time()

    if WQT.RefreshUI then
        WQT.RefreshUI()
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
end

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

-- Remove an unwanted character record
function WQT.RemoveCharacter(charKey)
    if WeeklyQuestTrackerDB.characters[charKey] then
        WeeklyQuestTrackerDB.characters[charKey] = nil
        print(string.format("%s: Character '%s' removed from tracker.", WQT.ADDON_TITLE, charKey))
        if WQT.RefreshUI then WQT.RefreshUI() end
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
end

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
        print("  |cff00ff00/wqt scan|r - Re-scan current character")
        print("  |cff00ff00/wqt check [name]|r - Inspect quests and IDs in your log")
        print("  |cff00ff00/wqt add <QuestID> [Name]|r - Add a new quest")
        print("  |cff00ff00/wqt reset|r - Force weekly reset check")
    end
end

-- Event Listener
f:SetScript("OnEvent", function(self, event, arg1, ...)
    if event == "ADDON_LOADED" and arg1 == addonName then
        WQT.InitDB()
    elseif event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" then
        WQT.InitDB()
        WQT.CheckWeeklyReset()
        C_Timer.After(1.5, function()
            WQT.ScanCurrentCharacter()
        end)
    elseif event == "QUEST_TURNED_IN" or event == "QUEST_REMOVED" or event == "QUEST_ACCEPTED" or event == "QUEST_LOG_UPDATE" or event == "QUEST_WATCH_UPDATE" then
        C_Timer.After(0.5, function()
            WQT.ScanCurrentCharacter()
        end)
    end
end)
