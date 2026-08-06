--------------------------------------------------------------------------------
---- AddOn Namespace
--------------------------------------------------------------------------------

local AddOnFolderName = ...
local private = select(2, ...) ---@type PrivateNamespace

local TravelAgent = LibStub("AceAddon-3.0"):GetAddon(AddOnFolderName, "AceEvent-3.0")

local DataBroker = LibStub("LibDataBroker-1.1")
local DBIcon = LibStub("LibDBIcon-1.0")
local L = LibStub("AceLocale-3.0"):GetLocale(AddOnFolderName)

--------------------------------------------------------------------------------
---- Configuration
--------------------------------------------------------------------------------

local options

local function GetOptions()
    ---@type TravelAgentDatabase
    local db = private.db

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

                            ---@param value boolean
                            set = function(_, value)
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

                            ---@param value boolean
                            set = function(_, value)
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

                            ---@param value boolean
                            set = function(_, value)
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

                            ---@param value boolean
                            set = function(_, value)
                                db.datafeed.show_coords = value

                                if db.datafeed.show_coords then
                                    if not private.CoordFeed then
                                        private.CoordFeed = DataBroker:NewDataObject(
                                            AddOnFolderName .. "Coordinates",
                                            private.CoordFeedData
                                        )
                                    end

                                    private.CoordFeed.text = private.GetCoords()
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

                            ---@param value boolean
                            set = function(_, value)
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

                            ---@param value boolean
                            set = function(_, value)
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

                            ---@param value boolean
                            set = function(_, value)
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

                            ---@param value number
                            set = function(_, value)
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

                            ---@param value number
                            set = function(_, value)
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
