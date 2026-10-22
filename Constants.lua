--[[
    WeeklyQuestTracker - Constants & Default Configuration
    Safe, Blizzard-compliant Lua addon for World of Warcraft Retail.
]]

local addonName, WQT = ...

-- Expose addon globally
_G["WeeklyQuestTracker"] = WQT

WQT.VERSION = "1.0.4"
WQT.ADDON_TITLE = "|cff00ccffWeekly Quest Tracker|r"

-- Default Tracked Quests
WQT.DEFAULT_QUESTS = {
    {
        name = "Fortify the Runestones",
        ids = { 90573, 90574, 90575, 90576 },
        isWeekly = true,
    },
    {
        name = "Abundant Offerings",
        ids = { 89507, 81682, 82146 },
        isWeekly = true,
    },
    {
        name = "The Story of the Root of the World",
        ids = {
            -- Haranir Relics & Legends of the Haranir (Root of the World, Relic Scenarios)
            88998, 88993, 88994, 88995, 88996, 88997, 88999,
            89000, 89001, 89002, 89003, 89004, 89005,
            88990, 88991, 88992,
            -- Harandar Storyline & Reliquary Quests
            90733, 90734, 90735, 90740, 90741, 90742, 90743, 90744, 90745,
            90730, 90731, 90732, 90736, 90737, 90738, 90739,
        },
        isWeekly = true,
    },
    {
        name = "Trailing Xal'atath",
        ids = { 82414, 83240, 84300, 83120, 83121, 83122 },
        isWeekly = true,
    },
    {
        name = "Unity Against the Void",
        ids = { 93744, 93767 },
        isWeekly = true,
    },
}

-- Default Addon Configuration
WQT.DEFAULT_CONFIG = {
    viewMode = "grid", -- "grid", "cards", "todo", or "combined"
    showMinimapButton = true,
    minimapAngle = 45,
    autoOpenOnLogin = false,
    soundFeedback = true,
}

-- Blizzard Native Textures for 4 Distinct States:
-- 1. Done (Green Checkmark)
-- 2. Ready to Turn In (Gold Quest Question Mark)
-- 3. In Progress (Yellow Status Indicator Dot)
-- 4. Incomplete (Red Cross)
WQT.ICON_CHECK    = "|TInterface\\RaidFrame\\ReadyCheck-Ready:15:15:0:0|t"
WQT.ICON_READY    = "|TInterface\\GossipFrame\\ActiveQuestIcon:16:16:0:0|t"
WQT.ICON_PROGRESS = "|TInterface\\COMMON\\Indicator-Yellow:14:14:0:0|t"
WQT.ICON_CROSS    = "|TInterface\\RaidFrame\\ReadyCheck-NotReady:15:15:0:0|t"

WQT.STATUS_DONE     = WQT.ICON_CHECK .. " |cff2ecc71Done|r"
WQT.STATUS_READY    = WQT.ICON_READY .. " |cff00ccffReady to Turn In|r"
WQT.STATUS_PROGRESS = WQT.ICON_PROGRESS .. " |cfff39c12In Progress|r"
WQT.STATUS_TODO     = WQT.ICON_CROSS .. " |cffe74c3cIncomplete|r"

-- Safe Class Color lookup
function WQT.GetClassColor(classFileName)
    if not classFileName then return 1, 1, 1, "ffffffff" end
    local color = (CUSTOM_CLASS_COLORS and CUSTOM_CLASS_COLORS[classFileName]) or RAID_CLASS_COLORS[classFileName]
    if color then
        return color.r, color.g, color.b, color.colorStr or "ffffffff"
    end
    return 0.8, 0.8, 0.8, "ffcccccc"
end

-- Get Class Icon Texture String
function WQT.GetClassIcon(classFileName)
    if not classFileName then return "" end
    local coords = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[classFileName]
    if coords then
        return string.format("|TInterface\\TargetingFrame\\UI-Classes-Circles:16:16:0:0:256:256:%d:%d:%d:%d|t",
            coords[1] * 256, coords[2] * 256, coords[3] * 256, coords[4] * 256)
    end
    return ""
end

-- Format seconds into readable format (e.g., "4d 22h")
function WQT.FormatTimeRemaining(seconds)
    if not seconds or seconds <= 0 then
        return "Soon"
    end
    local days = math.floor(seconds / 86400)
    local hours = math.floor((seconds % 86400) / 3600)
    local mins = math.floor((seconds % 3600) / 60)

    if days > 0 then
        return string.format("%dd %dh", days, hours)
    elseif hours > 0 then
        return string.format("%dh %dm", hours, mins)
    else
        return string.format("%dm", mins)
    end
end
