--[[
    WeeklyQuestTracker - Constants & Default Configuration
    Safe, Blizzard-compliant Lua addon for World of Warcraft Retail.
]]

local addonName, WQT = ...

-- Expose addon globally
_G["WeeklyQuestTracker"] = WQT

WQT.VERSION = "1.1.8"
WQT.ADDON_TITLE = "|cff00e5ffWeekly Quest|r |cffffd100Tracker|r"

-- Available Minimap / Header Icons for User Selection
WQT.AVAILABLE_ICONS = {
    { id = "compass", name = "Golden Compass", texture = "Interface\\Icons\\inv_misc_compass_01", desc = "Radiant golden navigational compass (New Modern Default)" },
    { id = "hourglass", name = "Hourglass of Time", texture = "Interface\\Icons\\inv_relics_hourglass", desc = "Mystic hourglass marking the weekly reset countdown" },
    { id = "void", name = "Twilight Void", texture = "Interface\\Icons\\spell_shadow_twilight", desc = "Cosmic void twilight crest fitting the Midnight theme" },
    { id = "keystone", name = "Mythic Star", texture = "Interface\\Icons\\achievement_dungeon_mythicplus", desc = "Radiant mythic keystone star emblem" },
    { id = "pocketwatch", name = "Timekeeper Watch", texture = "Interface\\Icons\\inv_misc_pocketwatch_01", desc = "Antique golden pocketwatch tracking weekly timers" },
    { id = "book", name = "Classic Tome", texture = "Interface\\Icons\\INV_Misc_Book_09", desc = "Original leatherbound quest log tome (Classic Look)" },
}

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
        -- 93744: Meta quest, 93767: Arcantina, 93890: Abundance, 95843: Ritual Sites, 93909: Delves
        ids = { 93744, 93767, 93890, 95843, 93909 },
        isWeekly = true,
    },
    {
        name = "Turn Back the Surge",
        ids = { 96995 },
        isWeekly = true,
    },
}

-- Default Addon Configuration
WQT.DEFAULT_CONFIG = {
    viewMode = "current", -- "current", "grid", "cards", "todo", or "settings"
    theme = "modern",    -- "modern" (Midnight Dark Glow) or "classic" (Slate)
    iconTexture = "Interface\\Icons\\inv_misc_compass_01", -- Modern Golden Compass
    showMinimapButton = true,
    minimapAngle = 45,
    showMiniHUD = true, -- Feature 2: Compact On-Screen Floating Tracker Bar
    logoutReminder = true, -- Feature 3: Alt Incomplete Reminder on Logout
    showGreatVault = true, -- Feature 4: Great Vault Summary (Raid/Mythic/Delves)
    showClassIcons = true,
    highlightCurrentChar = true,
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

-- Short Compact Statuses for Grid Matrix Table
WQT.STATUS_DONE_SHORT     = WQT.ICON_CHECK .. " |cff2ecc71Done|r"
WQT.STATUS_READY_SHORT    = WQT.ICON_READY .. " |cff00e5ffReady|r"
WQT.STATUS_PROGRESS_SHORT = WQT.ICON_PROGRESS .. " |cfff39c12Active|r"
WQT.STATUS_TODO_SHORT     = WQT.ICON_CROSS .. " |cffe74c3cTo-Do|r"

-- Class Colors Lookup Map
WQT.CLASS_COLORS = {
    ["WARRIOR"] = "ffc79c6e",
    ["PALADIN"] = "fff58cba",
    ["HUNTER"] = "ffabd473",
    ["ROGUE"] = "fffff569",
    ["PRIEST"] = "ffffffff",
    ["DEATHKNIGHT"] = "ffc41f3b",
    ["SHAMAN"] = "ff0070de",
    ["MAGE"] = "ff69ccf0",
    ["WARLOCK"] = "ff9482c9",
    ["MONK"] = "ff00ff96",
    ["DRUID"] = "ffff7d0a",
    ["DEMONHUNTER"] = "ffa330c9",
    ["EVOKER"] = "ff33937f",
}

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
