-------------------------------------------------------------------------------
-- Localized Lua globals.
-------------------------------------------------------------------------------
local math = math
local pairs = pairs
local select = select

-------------------------------------------------------------------------------
-- Addon namespace.
-------------------------------------------------------------------------------
local AddOnFolderName = ...

local TravelAgent = LibStub("AceAddon-3.0"):NewAddon(AddOnFolderName, "AceEvent-3.0")

local QTip = LibStub("LibQTip-2.0")
local DataBroker = LibStub("LibDataBroker-1.1")
local DBIcon = LibStub("LibDBIcon-1.0")
local Tourist = LibStub("LibTourist-3.0")
local HereBeDragons = LibStub("HereBeDragons-2.0")

local L = LibStub("AceLocale-3.0"):GetLocale(AddOnFolderName)
local Z = Tourist:GetLookupTable()

local DataObj
local CoordFeed

---@type LibQTip-2.0.Tooltip|nil
local tooltip

-------------------------------------------------------------------------------
-- Constants
-------------------------------------------------------------------------------
local LocalizedContinentNames = {
    Z["Kalimdor"],
    Z["Eastern Kingdoms"],
    Z["Outland"],
    Z["Northrend"],
    Z["The Maelstrom"],
    Z["Pandaria"],
    Z["Draenor"],
    Z["Broken Isles"],
    Z["Zandalar"],
    Z["Kul Tiras"],
    Z["The Shadowlands"],
    Z["Dragon Isles"],
}

local CONTINENT_DATA = {}

for index = 1, #LocalizedContinentNames do
    CONTINENT_DATA[LocalizedContinentNames[index]] = {
        id = index,
        zone_names = {},
        zone_ids = {},
    }
end

local defaults = {
    global = {
        datafeed = {
            minimap_icon = {
                hide = false,
            },
            show_zone = true,
            show_subzone = true,
            show_coords = true,
        },
        tooltip = {
            hide_hint = false,
            show_zone = true,
            show_subzone = true,
            scale = 1,
            timer = 0.25,
        },
        tooltip_sections = {
            cur_instances = true,
            rec_zones = true,
            rec_instances = true,
            battlegrounds = true,
            miscellaneous = true,
        },
    },
}

-------------------------------------------------------------------------------
-- Variables.
-------------------------------------------------------------------------------
local db
local CHAT_TEXT -- Cache for inserting into the ChatFrame's EditBox

-------------------------------------------------------------------------------
-- Helper functions
-------------------------------------------------------------------------------

local function GetZoneData(datafeed)
    local zoneClassification, isSubZonePvP, factionName = GetZonePVPInfo()
    local zoneText = GetRealZoneText()

    ---@type string|nil
    local subZoneText = GetSubZoneText()

    if subZoneText == "" or subZoneText == zoneText then
        subZoneText = nil
    end

    local label
    local r, g, b = 1.0, 1.0, 1.0

    if zoneClassification == "sanctuary" then
        label = SANCTUARY_TERRITORY
        r, g, b = 0.41, 0.8, 0.94
    elseif zoneClassification == "arena" then
        label = FREE_FOR_ALL_TERRITORY
        r, g, b = 1.0, 0.1, 0.1
    elseif zoneClassification == "friendly" then
        label = FACTION_CONTROLLED_TERRITORY:format(factionName)
        r, g, b = 0.1, 1.0, 0.1
    elseif zoneClassification == "hostile" then
        label = FACTION_CONTROLLED_TERRITORY:format(factionName)
        r, g, b = 1.0, 0.1, 0.1
    elseif zoneClassification == "contested" then
        label = CONTESTED_TERRITORY
        r, g, b = 1.0, 0.7, 0
    elseif zoneClassification == "combat" then
        label = COMBAT_ZONE
        r, g, b = 1.0, 0.1, 0.1
    else
        label = CONTESTED_TERRITORY
        r, g, b = 1.0, 0.9294, 0.7607
    end

    local zoneName, subZoneName

    if datafeed then
        subZoneName = db.datafeed.show_subzone and subZoneText or nil
        zoneName = db.datafeed.show_zone and zoneText or nil
    else
        subZoneName = db.tooltip.show_subzone and subZoneText or nil
        zoneName = db.tooltip.show_zone and zoneText or nil
    end

    if not zoneName and not subZoneName then
        zoneName = zoneText
    end

    local colon = (zoneName and subZoneName) and ": " or ""
    local hex = ("|cff%02x%02x%02x"):format(r * 255, g * 255, b * 255)
    local text = ("%s%s%s"):format(zoneName or "", colon, subZoneName or "")
    local color_text = ("%s%s%s%s|r"):format(hex, zoneName or "", colon, subZoneName or "")

    label = ("%s%s|r"):format(hex, label)

    return zoneText, subZoneText, label, text, color_text
end

local function GetCoords(to_chat)
    local x, y = HereBeDragons:GetPlayerZonePosition()
    x = x or 0
    y = y or 0

    local coords = PARENS_TEMPLATE:format(("%.2f, %.2f"):format(x * 100, y * 100))

    return to_chat and ("%s %s"):format(CHAT_TEXT, coords) or coords
end

-----------------------------------------------------------------------
-- Tooltip and DataBroker methods.
-----------------------------------------------------------------------
local DrawTooltip -- Upvalue needed for chicken-or-egg-syndrome.
local updater = CreateFrame("Frame", nil, UIParent)

local function LDB_OnClick(display, button)
    if button == "RightButton" then
        local settingsPanel = SettingsPanel

        if settingsPanel:IsVisible() then
            settingsPanel:Hide()
        else
            Settings.OpenToCategory(TravelAgent.options_frame)
        end
    elseif button == "LeftButton" then
        if IsShiftKeyDown() then
            local edit_box = ChatEdit_ChooseBoxForSend()

            ChatEdit_ActivateChat(edit_box)
            edit_box:Insert(GetCoords(true))
        elseif IsControlKeyDown() and Atlas_Toggle then
            Atlas_Toggle()
        else
            ToggleFrame(WorldMapFrame)
        end
    end
end

local function LDB_OnEnter(display, motion)
    DrawTooltip(display)
end

local function LDB_OnLeave()
    updater.elapsed = 0
end

do
    -- Assigned in DrawTooltip for use elsewhere.
    local displayAnchor

    ---@type LibQTip-2.0.Row|nil
    local coordinateRow

    local function SetCoordRow()
        if not coordinateRow or not tooltip or tooltip:GetRowCount() < 1 then
            return
        end

        coordinateRow:GetCell(1):SetText(GetCoords()):SetJustifyH("CENTER"):SetColSpan(6)
    end

    local lastUpdate = 0
    local previousX, previousY = 0, 0

    -- Handles tooltip hiding and the dynamic refresh of coordinates (both for the datafeed and if moving while the tooltip is open).
    updater:SetScript("OnUpdate", function(self, elapsed)
        lastUpdate = lastUpdate + elapsed

        if lastUpdate < 0.1 then
            return
        end

        local updateCoords = false
        local x, y = HereBeDragons:GetPlayerZonePosition()
        x = x or 0
        y = y or 0

        if previousX ~= x or previousY ~= y then
            previousX, previousY = x, y
            updateCoords = true
        end

        if tooltip then
            if tooltip:IsMouseOver() or (displayAnchor and displayAnchor:IsMouseOver()) then
                if coordinateRow and updateCoords then
                    SetCoordRow()
                end
                self.elapsed = 0
            else
                self.elapsed = self.elapsed + lastUpdate

                if self.elapsed >= db.tooltip.timer then
                    tooltip = QTip:ReleaseTooltip(tooltip)
                    displayAnchor = nil
                    coordinateRow = nil
                end
            end
        end

        if CoordFeed and updateCoords then
            CoordFeed.text = GetCoords()
        end

        lastUpdate = 0
    end)

    -----------------------------------------------------------------------
    -- DataObj and Tooltip methods.
    -----------------------------------------------------------------------
    local function SectionOnMouseUp(cell, section)
        db.tooltip_sections[section] = not db.tooltip_sections[section]

        DrawTooltip(displayAnchor)
    end

    local function InstanceOnMouseUp(cell, instanceName)
        if not instanceName then
            return
        end

        local zoneName, x, y = Tourist:GetEntrancePortalLocation(instanceName) or UNKNOWN, 0, 0
        local continentData = CONTINENT_DATA[Tourist:GetContinent()]

        _G.CONTINENT_DATA = CONTINENT_DATA
        _G.continentData = continentData

        print(zoneName)
        print(("%s - %s, %s"):format(continentData.zone_ids[zoneName], x, y))

        TomTom:AddWaypoint(continentData.zone_ids[zoneName], x, y, {
            title = ("%s (%s)"):format(instanceName, zoneName),
            source = "TravelAgent",
        })
    end

    -- Gathers all data relevant to the given instance and adds it to the tooltip.
    local function Tooltip_AddInstance(instance)
        if not tooltip then
            return
        end

        local r, g, b = Tourist:GetLevelColor(instance)
        local hex = ("|cff%02x%02x%02x"):format(r * 255, g * 255, b * 255)

        local location = Tourist:GetInstanceZone(instance)
        local r2, g2, b2 = Tourist:GetFactionColor(location)
        local hex2 = ("|cff%02x%02x%02x"):format(r2 * 255, g2 * 255, b2 * 255)

        local min, max = Tourist:GetLevel(instance)
        local _, x, y = Tourist:GetEntrancePortalLocation(instance)
        local group = Tourist:GetInstanceGroupSize(instance)

        local levelText

        if min == max then
            levelText = ("%s%d|r"):format(hex, min)
        else
            levelText = ("%s%d - %d|r"):format(hex, min, max)
        end

        local coordText = ((not x or not y) and "--" or ("%.2f, %.2f"):format(x, y))
        local complex = Tourist:GetComplex(instance)
        local colon = complex and ": " or ""

        local row = tooltip:AddRow()
        row:GetCell(1):SetFormattedText("%s%s%s", complex and complex or "", colon, instance)
        row:GetCell(2):SetText(levelText)
        row:GetCell(3):SetText(group > 0 and ("%d"):format(group) or "")

        if location ~= complex then
            row:GetCell(5):SetFormattedText("%s%s|r", hex2, location or UNKNOWN)
        end

        row:GetCell(6):SetText(coordText)

        if TomTom and x and y then
            row:SetScript("OnMouseUp", InstanceOnMouseUp, instance)
        end
    end

    local TitleFont = CreateFont("TravelAgentTitleFont")
    TitleFont:SetTextColor(0.510, 0.773, 1.0)
    TitleFont:SetFontObject("QuestTitleFont")

    local ICON_PLUS = [[|TInterface\BUTTONS\UI-PlusButton-Up:20:20|t]]
    local ICON_MINUS = [[|TInterface\BUTTONS\UI-MinusButton-Up:20:20|t]]

    -- List of battlegrounds found during the iteration over the recommended instances, so they can be split into their own section.
    local battlegrounds = {}

    function DrawTooltip(anchor)
        -- Save the value of the anchor so it can be used elsewhere.
        displayAnchor = anchor

        if not tooltip then
            tooltip = QTip:AcquireTooltip(
                AddOnFolderName .. "Tooltip",
                6,
                "LEFT",
                "LEFT",
                "CENTER",
                "RIGHT",
                "RIGHT",
                "RIGHT"
            )
            tooltip:EnableMouse(true)
        end

        local currentZoneName, _, pvpLabel, _, zoneText = GetZoneData(false)

        tooltip:Clear():SmartAnchorTo(anchor):SetScale(db.tooltip.scale)

        tooltip
            :AddRow()
            :GetCell(1)
            :SetColSpan(0)
            :SetJustifyH("CENTER")
            :SetFontObject(TitleFont)
            :SetText(AddOnFolderName)

        tooltip:AddSeparator()

        tooltip:AddHeadingRow():GetCell(1):SetText(zoneText):SetJustifyH("CENTER"):SetColSpan(0)
        tooltip:AddHeadingRow():GetCell(1):SetText(pvpLabel):SetJustifyH("CENTER"):SetColSpan(0)

        tooltip:AddSeparator()

        coordinateRow = tooltip:AddHeadingRow()

        SetCoordRow()

        tooltip:AddSeparator()
        tooltip:AddRow(" ")

        if Tourist:DoesZoneHaveInstances(currentZoneName) then
            local currentInstances = db.tooltip_sections.cur_instances
            local headingRow = tooltip:AddHeadingRow()
            local count = 0

            if currentInstances then
                for instance in Tourist:IterateZoneInstances(currentZoneName) do
                    Tooltip_AddInstance(instance)
                    count = count + 1
                end

                tooltip:AddRow(" ")
            end

            headingRow
                :SetScript("OnMouseUp", SectionOnMouseUp, "cur_instances")
                :GetCell(1, QTip:GetCellProvider("TravelAgent Section Header"))
                :SetJustifyH("CENTER")
                :SetColSpan(0)
                :SetFormattedText(
                    "%s %s",
                    currentInstances and ICON_MINUS or ICON_PLUS,
                    count > 1 and MULTIPLE_DUNGEONS or LFG_TYPE_DUNGEON
                )
        end

        local foundBattleground = false

        if Tourist:HasRecommendedInstances() then
            local recommendedInstances = db.tooltip_sections.rec_instances

            tooltip
                :AddHeadingRow()
                :SetScript("OnMouseUp", SectionOnMouseUp, "rec_instances")
                :GetCell(1, QTip:GetCellProvider("TravelAgent Section Header"))
                :SetJustifyH("CENTER")
                :SetColSpan(0)
                :SetFormattedText("%s %s", recommendedInstances and ICON_MINUS or ICON_PLUS, L["Recommended Instances"])

            for instance in Tourist:IterateRecommendedInstances() do
                if Tourist:IsBattleground(instance) then
                    if not foundBattleground then
                        wipe(battlegrounds)
                        foundBattleground = true
                    end

                    battlegrounds[instance] = true
                elseif recommendedInstances then
                    Tooltip_AddInstance(instance)
                end
            end

            if recommendedInstances then
                tooltip:AddRow(" ")
            end
        end

        local recommendedZones = db.tooltip_sections.rec_zones

        tooltip
            :AddHeadingRow()
            :SetScript("OnMouseUp", SectionOnMouseUp, "rec_zones")
            :GetCell(1, QTip:GetCellProvider("TravelAgent Section Header"))
            :SetJustifyH("CENTER")
            :SetColSpan(0)
            :SetFormattedText("%s %s", recommendedZones and ICON_MINUS or ICON_PLUS, L["Recommended Zones"])

        if recommendedZones then
            for zone in Tourist:IterateRecommendedZones() do
                local r1, g1, b1 = Tourist:GetLevelColor(zone)
                local hex1 = ("|cff%02x%02x%02x"):format(r1 * 255, g1 * 255, b1 * 255)

                local r2, g2, b2 = Tourist:GetFactionColor(zone)
                local hex2 = ("|cff%02x%02x%02x"):format(r2 * 255, g2 * 255, b2 * 255)

                local min, max = Tourist:GetLevel(zone)
                local levelText = min == max and ("%s%d|r"):format(hex1, min) or ("%s%d - %d|r"):format(hex1, min, max)

                local row = tooltip:AddRow()
                row:GetCell(1):SetFormattedText("%s%s|r", hex2, zone)
                row:GetCell(2):SetText(levelText)
                row:GetCell(5):SetText(Tourist:GetContinent(zone))
                row:GetCell(6):SetText("--")
            end

            tooltip:AddRow(" ")
        end

        if foundBattleground then
            local isBGToggled = db.tooltip_sections.battlegrounds

            tooltip
                :AddHeadingRow()
                :SetScript("OnMouseUp", SectionOnMouseUp, "battlegrounds")
                :GetCell(1, QTip:GetCellProvider("TravelAgent Section Header"))
                :SetJustifyH("CENTER")
                :SetColSpan(0)
                :SetFormattedText("%s %s", isBGToggled and ICON_MINUS or ICON_PLUS, BATTLEGROUNDS)

            if isBGToggled then
                for instance in pairs(battlegrounds) do
                    Tooltip_AddInstance(instance)
                end

                tooltip:AddRow(" ")
            end
        end

        local isMiscToggled = db.tooltip_sections.miscellaneous

        tooltip
            :AddHeadingRow()
            :SetScript("OnMouseUp", SectionOnMouseUp, "miscellaneous")
            :GetCell(1, QTip:GetCellProvider("TravelAgent Section Header"))
            :SetJustifyH("CENTER")
            :SetColSpan(0)
            :SetFormattedText("%s %s", isMiscToggled and ICON_MINUS or ICON_PLUS, MISCELLANEOUS)

        if isMiscToggled then
            local row = tooltip:AddRow()
            row:GetCell(1):SetText(CONTINENT)
            row:GetCell(5):SetText(Tourist:GetContinent(currentZoneName))

            local min, max = Tourist:GetLevel(currentZoneName)

            if min > 0 and max > 0 then
                local r, g, b = Tourist:GetLevelColor(currentZoneName)
                local hex = ("|cff%02x%02x%02x"):format(r * 255, g * 255, b * 255)

                row = tooltip:AddRow()
                row:GetCell(1):SetText(LEVEL_RANGE)
                row:GetCell(3):SetFormattedText("%s%d - %d|r", hex, min, max)
            end

            local fishingLevel = Tourist:GetFishingSkillInfo(currentZoneName).maxLevel

            if fishingLevel then
                tooltip
                    :AddRow()
                    :GetCell(1)
                    :SetFormattedText(SPELL_FAILED_FISHING_TOO_LOW, fishingLevel)
                    :SetJustifyH("CENTER")
                    :SetColSpan(0)
            end

            tooltip:AddRow(" ")
        end

        if not db.tooltip.hide_hint then
            tooltip:AddSeparator()

            tooltip:AddRow():GetCell(1):SetText(L["Left-click to open the World Map."]):SetColSpan(0)
            tooltip:AddRow():GetCell(1):SetText(L["Shift+Left-click to announce your location."]):SetColSpan(0)

            if Atlas_Toggle then
                tooltip:AddRow():GetCell(1):SetText(L["Control+Left-click to toggle Atlas."]):SetColSpan(0)
            end

            tooltip:AddRow():GetCell(1):SetText(L["Right-click to open configuration menu."]):SetColSpan(0)
        end

        updater.elapsed = 0
        tooltip:Show()
    end

    function TravelAgent:Update()
        local _, _, _, text, color_text = GetZoneData(true)
        local num = math.random(9)

        CHAT_TEXT = text

        DataObj.text = color_text
        DataObj.icon = ([[Interface\Icons\INV_Misc_Map%s0%d]]):format((num == 1 and "_" or ""), num)

        if tooltip and tooltip:IsVisible() then
            DrawTooltip(displayAnchor)
        end
    end
end -- do

-------------------------------------------------------------------------------
-- Event functions
-------------------------------------------------------------------------------
do
    local function InitializeZoneData(name_table, id_table, ...)
        for id = 1, select("#", ...), 1 do
            name_table[id] = select(id, ...)
        end

        for id in pairs(name_table) do
            id_table[name_table[id]] = id
        end
    end

    function TravelAgent:OnInitialize()
        -- Initialize continent/zone data
        for continent, data in pairs(CONTINENT_DATA) do
            InitializeZoneData(data.zone_names, data.zone_ids, C_Map.GetMapChildrenInfo(data.id))
        end

        -- Database voodoo.
        local temp_db = LibStub("AceDB-3.0"):New(AddOnFolderName .. "DB", defaults)
        db = temp_db.global

        self:SetupOptions()
    end
end -- do

local CoordFeedData = {
    type = "data source",
    icon = [[Interface\Icons\INV_Torch_Lit]],
    text = "",
    OnEnter = LDB_OnEnter,
    OnLeave = LDB_OnLeave,
    OnClick = LDB_OnClick,
}

function TravelAgent:OnEnable()
    self:RegisterEvent("ZONE_CHANGED", self.Update)
    self:RegisterEvent("ZONE_CHANGED_INDOORS", self.Update)
    self:RegisterEvent("ZONE_CHANGED_NEW_AREA", self.Update)

    DataObj = DataBroker:NewDataObject(AddOnFolderName, {
        type = "data source",
        label = AddOnFolderName,
        text = " ",
        icon = [[Interface\Icons\INV_Misc_Map_0]] .. math.random(9),
        OnEnter = LDB_OnEnter,
        OnLeave = LDB_OnLeave,
        OnClick = LDB_OnClick,
    })

    if db.datafeed.show_coords then
        CoordFeed = DataBroker:NewDataObject(AddOnFolderName .. "Coordinates", CoordFeedData)
    end

    if DBIcon then
        DBIcon:Register(AddOnFolderName, DataObj, db.datafeed.minimap_icon)
    end
    self:Update()
end

-----------------------------------------------------------------------
-- Configuration.
-----------------------------------------------------------------------
local options

local function GetOptions()
    if not options then
        options = {
            name = AddOnFolderName,
            childGroups = "tab",
            type = "group",
            args = {
                datafeed = {
                    name = L["Datafeed"],
                    order = 2,
                    type = "group",
                    args = {
                        minimap_icon = {
                            order = 1,
                            type = "toggle",
                            width = "full",
                            name = L["Minimap Icon"],
                            desc = L["Draws the icon on the minimap."],
                            get = function()
                                return not db.datafeed.minimap_icon.hide
                            end,
                            set = function(info, value)
                                db.datafeed.minimap_icon.hide = not value

                                DBIcon[value and "Show" or "Hide"](DBIcon, AddOnFolderName)
                            end,
                        },
                        show_zone = {
                            order = 2,
                            type = "toggle",
                            width = "full",
                            name = L["Show Zone Name"],
                            desc = L["Displays the name of the current zone."],
                            get = function()
                                return db.datafeed.show_zone
                            end,
                            set = function(info, value)
                                db.datafeed.show_zone = value

                                if not db.datafeed.show_zone and not db.datafeed.show_subzone then
                                    db.datafeed.show_subzone = true
                                end
                                TravelAgent:Update()
                            end,
                        },
                        show_subzone = {
                            order = 3,
                            type = "toggle",
                            width = "full",
                            name = L["Show Subzone Name"],
                            desc = L["Displays the name of the current subzone."],
                            get = function()
                                return db.datafeed.show_subzone
                            end,
                            set = function(info, value)
                                db.datafeed.show_subzone = value

                                if not db.datafeed.show_zone and not db.datafeed.show_subzone then
                                    db.datafeed.show_zone = true
                                end
                                TravelAgent:Update()
                            end,
                        },
                        show_coords = {
                            order = 4,
                            type = "toggle",
                            width = "full",
                            name = L["Show Coordinates"],
                            desc = L["Displays the coordinates of the current location."],
                            get = function()
                                return db.datafeed.show_coords
                            end,
                            set = function(info, value)
                                db.datafeed.show_coords = value

                                if db.datafeed.show_coords then
                                    if not CoordFeed then
                                        CoordFeed =
                                            DataBroker:NewDataObject(AddOnFolderName .. "Coordinates", CoordFeedData)
                                    end
                                    CoordFeed.text = GetCoords()
                                end
                            end,
                        },
                    },
                },
                tooltip = {
                    name = L["Tooltip"],
                    order = 3,
                    type = "group",
                    args = {
                        hide_hint = {
                            order = 1,
                            type = "toggle",
                            width = "full",
                            name = L["Hide Hint Text"],
                            desc = L["Hides the hint text at the bottom of the tooltip."],
                            get = function()
                                return db.tooltip.hide_hint
                            end,
                            set = function(info, value)
                                db.tooltip.hide_hint = value
                            end,
                        },
                        show_zone = {
                            order = 2,
                            type = "toggle",
                            width = "full",
                            name = L["Show Zone Name"],
                            desc = L["Displays the name of the current zone."],
                            get = function()
                                return db.tooltip.show_zone
                            end,
                            set = function(info, value)
                                db.tooltip.show_zone = value

                                if not db.tooltip.show_zone and not db.tooltip.show_subzone then
                                    db.tooltip.show_subzone = true
                                end
                            end,
                        },
                        show_subzone = {
                            order = 3,
                            type = "toggle",
                            width = "full",
                            name = L["Show Subzone Name"],
                            desc = L["Displays the name of the current subzone."],
                            get = function()
                                return db.tooltip.show_subzone
                            end,
                            set = function(info, value)
                                db.tooltip.show_subzone = value

                                if not db.tooltip.show_zone and not db.tooltip.show_subzone then
                                    db.tooltip.show_zone = true
                                end
                            end,
                        },
                        scale = {
                            order = 4,
                            type = "range",
                            width = "full",
                            name = L["Tooltip Scale"],
                            desc = L["Move the slider to adjust the scale of the tooltip."],
                            min = 0.5,
                            max = 1.5,
                            step = 0.01,
                            get = function()
                                return db.tooltip.scale
                            end,
                            set = function(info, value)
                                db.tooltip.scale = math.max(0.5, math.min(1.5, value))
                            end,
                        },
                        timer = {
                            order = 5,
                            type = "range",
                            width = "full",
                            name = L["Tooltip Timer"],
                            desc = L["Move the slider to adjust the tooltip fade time."],
                            min = 0.1,
                            max = 2,
                            step = 0.01,
                            get = function()
                                return db.tooltip.timer
                            end,
                            set = function(info, value)
                                db.tooltip.timer = math.max(0.1, math.min(2, value))
                            end,
                        },
                    },
                },
            },
        }
    end
    return options
end

function TravelAgent:SetupOptions()
    LibStub("AceConfig-3.0"):RegisterOptionsTable(AddOnFolderName, GetOptions())
    self.options_frame = LibStub("AceConfigDialog-3.0"):AddToBlizOptions(AddOnFolderName)
end
