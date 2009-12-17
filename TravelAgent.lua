-------------------------------------------------------------------------------
-- Localized Lua globals.
-------------------------------------------------------------------------------
local _G = getfenv(0)

-------------------------------------------------------------------------------
-- Addon namespace.
-------------------------------------------------------------------------------
local ADDON_NAME	= ...
local LibStub		= _G.LibStub
local TravelAgent	= LibStub("AceAddon-3.0"):NewAddon(ADDON_NAME, "AceEvent-3.0")

local LQT		= LibStub("LibQTip-1.0")
local LDB		= LibStub("LibDataBroker-1.1")
local LT		= LibStub("LibTourist-3.0")
local BZ		= LibStub("LibBabble-Zone-3.0"):GetLookupTable()
local L			= LibStub("AceLocale-3.0"):GetLocale(ADDON_NAME)

local DataObj = LDB:NewDataObject(ADDON_NAME,	{
	type	= "data source",
	label	= ADDON_NAME,
	text	= " ",
	icon	= "Interface\\Icons\\INV_Misc_Map_0" .. math.random(9),
})

local tooltip

-------------------------------------------------------------------------------
-- Constants
-------------------------------------------------------------------------------
local CONTINENT_DATA = {
	[BZ["Kalimdor"]] = {
		id = 1,
		zone_names = {},
		zone_ids = {}
	},
	[BZ["Eastern Kingdoms"]] = {
		id = 2,
		zone_names = {},
		zone_ids = {}
	},
	[BZ["Outland"]] = {
		id = 3,
		zone_names = {},
		zone_ids = {}
	},
	[BZ["Northrend"]] = {
		id = 4,
		zone_names = {},
		zone_ids = {}
	},
}

-------------------------------------------------------------------------------
-- Variables.
-------------------------------------------------------------------------------
local current_zone
local current_subzone
local db

-------------------------------------------------------------------------------
-- Helper functions
-------------------------------------------------------------------------------
local function GetZoneString()
	current_zone = GetRealZoneText()
	current_subzone = GetSubZoneText()

	local r, g, b = LT:GetFactionColor(current_zone)

	if current_subzone == "" or current_subzone == current_zone then
		current_subzone = nil
	end

	return string.format("|cff%02x%02x%02x%s%s%s|r", r * 255, g * 255, b * 255, current_zone, (current_subzone and ": " or ""), current_subzone or "")
end


-----------------------------------------------------------------------
-- Tooltip scripts.
-----------------------------------------------------------------------
do
	local DrawTooltip		-- Upvalue needed for chicken-or-egg-syndrome.
	local coord_line		-- Assigned in DrawTooltip for use elsewhere.

	local function SetCoordLine()
		local x, y = GetPlayerMapPosition("player")
		x = x * 100
		y = y * 100

		tooltip:SetCell(coord_line, 5, string.format("%.2f, %.2f", x, y))
	end

	-----------------------------------------------------------------------
	-- Update scripts.
	-----------------------------------------------------------------------
	local LDB_anchor
	local last_update = 0
	local HIDE_DELAY = 0.5

	local updater = CreateFrame("Frame", nil, UIParent)

	updater:Hide()

	-- Handles tooltip hiding and the dynamic refresh of coordinates if moving while the tooltip is open.
	local function CheckTooltipState(self, elapsed)
		last_update = last_update + elapsed

		if last_update > 0.1 then
			if tooltip:IsMouseOver() or (LDB_anchor and LDB_anchor:IsMouseOver()) then
				if coord_line then
					SetCoordLine()
				end
				self.elapsed = 0
			else
				self.elapsed = self.elapsed + last_update

				if self.elapsed >= HIDE_DELAY then
					tooltip = LQT:Release(tooltip)
					self:Hide()
					LDB_anchor = nil
					coord_line = nil
				end
			end
			last_update = 0
		end
	end

	-----------------------------------------------------------------------
	-- DataObj and Tooltip methods.
	-----------------------------------------------------------------------
	local tooltip_sections = {
		["CurInstances"]	= true,
		["RecZones"]		= true,
		["RecInstances"]	= true,
		["Battlegrounds"]	= true
	}

	local function SectionOnMouseUp(cell, section)
		tooltip_sections[section] = not tooltip_sections[section]

		DrawTooltip(LDB_anchor)
	end

	local function InstanceOnMouseUp(cell, instance)
		if not instance then
			return
		end
		local zone, x, y = LT:GetEntrancePortalLocation(instance)
		local continent = CONTINENT_DATA[LT:GetContinent(zone)]

		TomTom:AddZWaypoint(continent.id, continent.zone_ids[zone], x, y, string.format("%s (%s)", instance, zone), false, true, true, nil, true, true)
	end

	-- Gathers all data relevant to the given instance and adds it to the tooltip.
	local function Tooltip_AddInstance(instance)
		local r, g, b = LT:GetLevelColor(instance)
		local hex = string.format("|cff%02x%02x%02x", r * 255, g * 255, b * 255)

		local location = LT:GetInstanceZone(instance)
		local r2, g2, b2 = LT:GetFactionColor(location)
		local hex2 = string.format("|cff%02x%02x%02x", r2 * 255, g2 * 255, b2 * 255)

		local min, max = LT:GetLevel(instance)
		local _, x, y = LT:GetEntrancePortalLocation(instance)
		local group = LT:GetInstanceGroupSize(instance)

		local level_str

		if min == max then
			level_str = string.format("%s%d|r", hex, min)
		else
			level_str = string.format("%s%d - %d|r", hex, min, max)
		end
		local coord_str = ((not x or not y) and "" or string.format("%.2f, %.2f", x, y))

		line = tooltip:AddLine()
		tooltip:SetCell(line, 1, string.format("%s%s|r", hex, instance))
		tooltip:SetCell(line, 2, level_str)
		tooltip:SetCell(line, 3, group > 0 and string.format("%d", group) or "")
		tooltip:SetCell(line, 4, string.format("%s%s|r", hex2, location or _G.UNKNOWN))
		tooltip:SetCell(line, 5, coord_str)

		if _G.TomTom and x and y then
			tooltip:SetCellScript(line, 1, "OnMouseUp", InstanceOnMouseUp, instance)
		end
	end

	-- List of battlegrounds found during the iteration over the recommended instances, so they can be split into their own section.
	local battlegrounds = {}

	function DrawTooltip(anchor)
		-- Save the value of the anchor so it can be used elsewhere.
		LDB_anchor = anchor

		if not tooltip then
			tooltip = LQT:Acquire(ADDON_NAME.."Tooltip", 5, "LEFT", "CENTER", "RIGHT", "RIGHT", "RIGHT")

			if _G.TipTac and _G.TipTac.AddModifiedTip then
				-- Pass true as second parameter because hooking OnHide causes C stack overflows
				TipTac:AddModifiedTip(tooltip, true)
			end
		end
		tooltip:Clear()
		tooltip:SmartAnchorTo(anchor)

		tooltip:AddHeader()
		tooltip:SetCell(1, 1, GetZoneString(), "CENTER", 5)
		tooltip:AddSeparator()

		local line, column = tooltip:AddLine()
		coord_line = line

		tooltip:SetCell(line, column, _G.LOCATION_COLON)
		SetCoordLine()

		if LT:DoesZoneHaveInstances(current_zone) then
			tooltip:AddLine(" ")

			local header_line = tooltip:AddHeader()
			tooltip:AddSeparator()

			local count = 0

			if tooltip_sections["CurInstances"] then
				for instance in LT:IterateZoneInstances(current_zone) do
					local r, g, b = LT:GetLevelColor(instance)
					local hex = string.format("|cff%02x%02x%02x", r * 255, g * 255, b * 255)
					local min, max = LT:GetLevel(instance)
					local _, x, y = LT:GetEntrancePortalLocation(instance)
					local group = LT:GetInstanceGroupSize(instance)
					local level_str

					if min == max then
						level_str = string.format("%s%d|r", hex, min)
					else
						level_str = string.format("%s%d - %d|r", hex, min, max)
					end
					count = count + 1

					line = tooltip:AddLine()
					tooltip:SetCell(line, 1, string.format("%s%s|r", hex, instance))
					tooltip:SetCell(line, 2, level_str)
					tooltip:SetCell(line, 3, group > 0 and string.format("%d", group) or "")
					tooltip:SetCell(line, 5, string.format("%.2f, %.2f", x or 0, y or 0))

					if _G.TomTom and x and y then
						tooltip:SetCellScript(line, 1, "OnMouseUp", InstanceOnMouseUp, instance)
					end
				end
			end
			tooltip:SetCell(header_line, 1, (count > 1 and _G.MULTIPLE_DUNGEONS or _G.LFG_TYPE_DUNGEON), "CENTER", 5)
			tooltip:SetCellScript(header_line, 1, "OnMouseUp", SectionOnMouseUp, "CurInstances")
		end

		local found_battleground = false

		if LT:HasRecommendedInstances() then
			tooltip:AddLine(" ")

			line = tooltip:AddHeader()
			tooltip:SetCell(line, 1, L["Recommended Instances"], "CENTER", 5)
			tooltip:SetCellScript(line, 1, "OnMouseUp", SectionOnMouseUp, "RecInstances")
			tooltip:AddSeparator()

			for instance in LT:IterateRecommendedInstances() do
				if LT:IsBattleground(instance) then
					if not found_battleground  then
						_G.wipe(battlegrounds)
						found_battleground = true
					end
					battlegrounds[instance] = true
				elseif tooltip_sections["RecInstances"] then
					Tooltip_AddInstance(instance)
				end
			end
		end
		tooltip:AddLine(" ")

		line = tooltip:AddLine()
		tooltip:SetCell(line, 1, L["Recommended Zones"], "CENTER", 5)
		tooltip:SetCellScript(line, 1, "OnMouseUp", SectionOnMouseUp, "RecZones")
		tooltip:AddSeparator()

		if tooltip_sections["RecZones"] then
			for zone in LT:IterateRecommendedZones() do
				local r1, g1, b1 = LT:GetLevelColor(zone)
				local hex1 = string.format("|cff%02x%02x%02x", r1 * 255, g1 * 255, b1 * 255)

				local r2, g2, b2 = LT:GetFactionColor(zone)
				local hex2 = string.format("|cff%02x%02x%02x", r2 * 255, g2 * 255, b2 * 255)

				local min, max = LT:GetLevel(zone)
				local continent = LT:GetContinent(zone)
				local level_str

				if min == max then
					level_str = string.format("%s%d|r", hex1, min)
				else
					level_str = string.format("%s%d - %d|r", hex1, min, max)
				end
				line = tooltip:AddLine()
				tooltip:SetCell(line, 1, string.format("%s%s|r", hex2, zone))
				tooltip:SetCell(line, 2, level_str)
				tooltip:SetCell(line, 4, continent)
			end
		end

		if found_battleground then
			tooltip:AddLine(" ")

			line = tooltip:AddLine()
			tooltip:SetCell(line, 1, _G.BATTLEGROUNDS, "CENTER", 5)
			tooltip:SetCellScript(line, 1, "OnMouseUp", SectionOnMouseUp, "Battlegrounds")
			tooltip:AddSeparator()

			if tooltip_sections["Battlegrounds"] then
				for instance in pairs(battlegrounds) do
					Tooltip_AddInstance(instance)
				end
			end
		end
		updater.elapsed = 0
		updater:SetScript("OnUpdate", CheckTooltipState)
		updater:Show()
		tooltip:Show()
	end

	function DataObj.OnEnter(display, motion)
		DrawTooltip(display)
	end

	function DataObj.OnLeave()
		updater:SetScript("OnUpdate", CheckTooltipState)
		updater.elapsed = 0
	end

	function DataObj.OnClick(display, button)
	end

	function TravelAgent:Update()
		local num = math.random(9)

		DataObj.text = GetZoneString()
		DataObj.icon = "Interface\\Icons\\INV_Misc_Map_0" .. num

		if tooltip and tooltip:IsVisible() then
			DrawTooltip(LDB_anchor)
		end
	end
end	-- do

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
			InitializeZoneData(data.zone_names, data.zone_ids, GetMapZones(data.id))
		end

		-- Database voodoo.
		local temp_db = LibStub("AceDB-3.0"):New(ADDON_NAME.."DB", defaults)
		db = temp_db.profile

		self:SetupOptions()
	end
end	-- do

function TravelAgent:OnEnable()
	self:RegisterEvent("ZONE_CHANGED", self.Update)
	self:RegisterEvent("ZONE_CHANGED_INDOORS", self.Update)
	self:RegisterEvent("ZONE_CHANGED_NEW_AREA", self.Update)

	self:Update()
end

-----------------------------------------------------------------------
-- Configuration.
-----------------------------------------------------------------------
local options

local function GetOptions()
	if not options then
		options = {
			name = ADDON_NAME,
			childGroups = "tab",
			type = "group",
			args = {
				datafeed = {
					name	= L["Datafeed"],
					order	= 2,
					type	= "group",
					args = {
						show_zone = {
							order	= 1,
							type	= "toggle",
							width	= "full",
							name	= L["Show Zone Name"],
							desc	= L["Displays the name of the current zone."],
							get	= function()
									  return db.datafeed.show_zone
								  end,
							set	= function(info, value)
									  db.datafeed.show_zone = value

									  if not db.datafeed.show_zone and not db.datafeed.show_subzone then
										  db.datafeed.show_subzone = true
									  end
									  TravelAgent:Update()
								  end,
						},
						show_subzone = {
							order	= 2,
							type	= "toggle",
							width	= "full",
							name	= L["Show Subzone Name"],
							desc	= L["Displays the name of the current subzone."],
							get	= function()
									  return db.datafeed.show_subzone
								  end,
							set	= function(info, value)
									  db.datafeed.show_subzone = value

									  if not db.datafeed.show_zone and not db.datafeed.show_subzone then
										  db.datafeed.show_zone = true
									  end
									  TravelAgent:Update()
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
							order	= 1,
							type	= "toggle",
							width	= "full",
							name	= L["Hide Hint Text"],
							desc	= L["Hides the hint text at the bottom of the tooltip."],
							get	= function()
									  return db.tooltip.hide_hint
								  end,
							set	= function(info, value)
									  db.tooltip.hide_hint = value
								  end,
						},
						show_zone = {
							order	= 2,
							type	= "toggle",
							width	= "full",
							name	= L["Show Zone Name"],
							desc	= L["Displays the name of the current zone."],
							get	= function()
									  return db.tooltip.show_zone
								  end,
							set	= function(info, value)
									  db.tooltip.show_zone = value

									  if not db.tooltip.show_zone and not db.tooltip.show_subzone then
										  db.tooltip.show_subzone = true
									  end
								  end,
						},
						show_subzone = {
							order	= 3,
							type	= "toggle",
							width	= "full",
							name	= L["Show Subzone Name"],
							desc	= L["Displays the name of the current subzone."],
							get	= function()
									  return db.tooltip.show_subzone
								  end,
							set	= function(info, value)
									  db.tooltip.show_subzone = value

									  if not db.tooltip.show_zone and not db.tooltip.show_subzone then
										  db.tooltip.show_zone = true
									  end
								  end,
						},
						scale = {
							order	= 4,
							type	= "range",
							width	= "full",
							name	= L["Tooltip Scale"],
							desc	= L["Move the slider to adjust the scale of the tooltip."],
							min	= 0.5,
							max	= 1.5,
							step	= 0.01,
							get	= function()
									  return db.tooltip.scale
								  end,
							set	= function(info, value)
									  db.tooltip.scale = math.max(0.5, math.min(1.5, value))
								  end,
						},
					}
				}
			}
		}
	end
	return options
end

function TravelAgent:SetupOptions()
	LibStub("AceConfig-3.0"):RegisterOptionsTable(ADDON_NAME, GetOptions())
	self.options_frame = LibStub("AceConfigDialog-3.0"):AddToBlizOptions(ADDON_NAME)
end
