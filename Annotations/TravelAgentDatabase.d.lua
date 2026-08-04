---@meta _

--------------------------------------------------------------------------------
---- Types
--------------------------------------------------------------------------------

---@class TravelAgentDatabase.Global.DataFeed
---@field minimap_icon { hide: boolean }
---@field show_zone boolean
---@field show_subzone boolean
---@field show_coords boolean

---@class TravelAgentDatabase.Global.Tooltip
---@field hide_hint boolean
---@field show_zone boolean
---@field show_subzone boolean
---@field scale number
---@field timer number

---@class TravelAgentDatabase.Global.TooltipSections
---@field cur_instances boolean
---@field rec_zones boolean
---@field rec_instances boolean
---@field battlegrounds boolean
---@field miscellaneous boolean

---@class TravelAgentDatabase.Global
---@field datafeed TravelAgentDatabase.Global.DataFeed
---@field tooltip TravelAgentDatabase.Global.Tooltip
---@field tooltip_sections TravelAgentDatabase.Global.TooltipSections

---@class TravelAgentDatabase: AceDBObject-3.0, TravelAgentDatabase.Global
---@field global TravelAgentDatabase.Global
