-------------------------------------------------------------------------------
-- Localized Lua globals.
-------------------------------------------------------------------------------
local _G = getfenv(0)

local string = _G.string
local math = _G.math
local pairs = _G.pairs
local select = _G.select

-------------------------------------------------------------------------------
-- Addon namespace.
-------------------------------------------------------------------------------
local ADDON_NAME	= ...
local LibStub		= _G.LibStub
local TravelAgent	= LibStub("AceAddon-3.0"):NewAddon(ADDON_NAME, "AceEvent-3.0")

local LQT		= LibStub("LibQTip-1.0")
local LDB		= LibStub("LibDataBroker-1.1")
local LDBIcon		= LibStub("LibDBIcon-1.0")
local LT		= LibStub("LibTourist-3.0")
local BZ		= LibStub("LibBabble-Zone-3.0"):GetLookupTable()
local L			= LibStub("AceLocale-3.0"):GetLocale(ADDON_NAME)

local DataObj
local CoordFeed
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

local defaults = {
	global = {
		datafeed = {
			minimap_icon	= {
				hide	= false,
			},
			show_zone	= true,
			show_subzone	= true,
			show_coords	= true,
		},
		tooltip = {
			hide_hint	= false,
			show_zone	= true,
			show_subzone	= true,
			scale		= 1,
			timer		= 0.25,
		},
		tooltip_sections = {
			cur_instances	= true,
			rec_zones	= true,
			rec_instances	= true,
			battlegrounds	= true,
			miscellaneous	= true,
		}
	}
}

-------------------------------------------------------------------------------
-- Variables.
-------------------------------------------------------------------------------
local db
local CHAT_TEXT		-- Cache for inserting into ChatFrameEditBox

-------------------------------------------------------------------------------
-- Helper functions
-------------------------------------------------------------------------------
local function GetZoneData(datafeed)
	local zone_status, subzone_ispvp, controlling_faction = GetZonePVPInfo()
	local current_zone = GetRealZoneText()
	local current_subzone = GetSubZoneText()

	if current_subzone == "" or current_subzone == current_zone then
		current_subzone = nil
	end
	local zone_str, subzone_str
	local label
	local r, g, b = 1.0, 1.0, 1.0

	if zone_status == "sanctuary" then
		label = _G.SANCTUARY_TERRITORY
		r, g, b = 0.41, 0.8, 0.94
	elseif  zone_status == "arena" then
		label = _G.FREE_FOR_ALL_TERRITORY
		r, g, b = 1.0, 0.1, 0.1
	elseif zone_status == "friendly" then
		label = string.format(_G.FACTION_CONTROLLED_TERRITORY, controlling_faction)
		r, g, b = 0.1, 1.0, 0.1
	elseif zone_status == "hostile" then
		label = string.format(_G.FACTION_CONTROLLED_TERRITORY, controlling_faction)
		r, g, b = 1.0, 0.1, 0.1
	elseif zone_status == "contested" then
		label = _G.CONTESTED_TERRITORY
		r, g, b = 1.0, 0.7, 0
	elseif zone_status == "combat" then
		label = _G.COMBAT_ZONE
		r, g, b = 1.0, 0.1, 0.1
	else
		label = _G.CONTESTED_TERRITORY
		r, g, b = 1.0, 0.9294, 0.7607
	end

	if datafeed then
		subzone_str = db.datafeed.show_subzone and current_subzone or nil
		zone_str = db.datafeed.show_zone and current_zone or nil
	else
		subzone_str = db.tooltip.show_subzone and current_subzone or nil
		zone_str = db.tooltip.show_zone and current_zone or nil
	end

	if not zone_str and not subzone_str then
		zone_str = current_zone
	end
	local colon = (zone_str and subzone_str) and ": " or ""
	local hex = string.format("|cff%02x%02x%02x", r * 255, g * 255, b * 255)
	local text = string.format("%s%s%s", zone_str or "", colon, subzone_str or "")
	local color_text = string.format("%s%s%s%s|r", hex, zone_str or "", colon, subzone_str or "")
	label = string.format("%s%s|r", hex, label)

	return current_zone, current_subzone, label, text, color_text
end

local function GetCoords(to_chat)
	local x, y = GetPlayerMapPosition("player")
	local retstr = string.format(_G.PARENS_TEMPLATE, string.format("%.2f, %.2f", x * 100, y * 100))

	return to_chat and (CHAT_TEXT.." "..retstr) or retstr
end

-----------------------------------------------------------------------
-- Tooltip and DataBroker methods.
-----------------------------------------------------------------------
local DrawTooltip		-- Upvalue needed for chicken-or-egg-syndrome.
local updater

local function LDB_OnClick(display, button)
	if button == "RightButton" then
		local options_frame = InterfaceOptionsFrame

		if options_frame:IsVisible() then
			options_frame:Hide()
		else
			InterfaceOptionsFrame_OpenToCategory(TravelAgent.options_frame)
		end
	elseif button == "LeftButton" then
		if IsShiftKeyDown() then
			ChatFrameEditBox:Show()
			ChatFrameEditBox:Insert(GetCoords(true))
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
	local LDB_anchor
	local coord_line

	local function SetCoordLine()
		local x, y = GetPlayerMapPosition("player")

		tooltip:SetCell(coord_line, 6, string.format("%.2f, %.2f", x * 100, y * 100))
	end

	local last_update = 0
	local prev_x, prev_y = 0, 0

	updater = CreateFrame("Frame", nil, UIParent)

	-- Handles tooltip hiding and the dynamic refresh of coordinates (both for the datafeed and if moving while the tooltip is open).
	updater:SetScript("OnUpdate",
			  function(self, elapsed)
				  last_update = last_update + elapsed

				  if last_update < 0.1 then
					  return
				  end

				  local update_coords = false
				  local x, y = GetPlayerMapPosition("player")

				  if prev_x ~= x or prev_y ~= y then
					  prev_x, prev_y = x, y
					  update_coords = true
				  end

				  if tooltip then
					  if tooltip:IsMouseOver() or (LDB_anchor and LDB_anchor:IsMouseOver()) then
						  if coord_line and update_coords then
							  SetCoordLine()
						  end
						  self.elapsed = 0
					  else
						  self.elapsed = self.elapsed + last_update

						  if self.elapsed >= db.tooltip.timer then
							  tooltip = LQT:Release(tooltip)
							  LDB_anchor = nil
							  coord_line = nil
						  end
					  end
				  end

				  if CoordFeed and update_coords then
					  CoordFeed.text = GetCoords()
				  end
				  last_update = 0
			  end)

	-----------------------------------------------------------------------
	-- DataObj and Tooltip methods.
	-----------------------------------------------------------------------
	local function SectionOnMouseUp(cell, section)
		db.tooltip_sections[section] = not db.tooltip_sections[section]

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

		local complex = LT:GetComplex(instance)
		local colon = complex and ": " or ""
		local line = tooltip:AddLine()

		tooltip:SetCell(line, 1, string.format("%s%s%s", complex and complex or "", colon, instance), "LEFT", 2)
		tooltip:SetCell(line, 3, level_str)
		tooltip:SetCell(line, 4, group > 0 and string.format("%d", group) or "")
		tooltip:SetCell(line, 5, string.format("%s%s|r", hex2, location or _G.UNKNOWN))
		tooltip:SetCell(line, 6, coord_str)

		if _G.TomTom and x and y then
			tooltip:SetLineScript(line, "OnMouseUp", InstanceOnMouseUp, instance)
		end
	end
	local ICON_PLUS = [[|TInterface\BUTTONS\UI-PlusButton-Up:20:20|t]]
	local ICON_MINUS = [[|TInterface\BUTTONS\UI-MinusButton-Up:20:20|t]]

	-- List of battlegrounds found during the iteration over the recommended instances, so they can be split into their own section.
	local battlegrounds = {}

	function DrawTooltip(anchor)
		-- Save the value of the anchor so it can be used elsewhere.
		LDB_anchor = anchor

		if not tooltip then
			tooltip = LQT:Acquire(ADDON_NAME.."Tooltip", 6, "LEFT", "LEFT", "CENTER", "RIGHT", "RIGHT", "RIGHT")

			if _G.TipTac and _G.TipTac.AddModifiedTip then
				-- Pass true as second parameter because hooking OnHide causes C stack overflows
				TipTac:AddModifiedTip(tooltip, true)
			end
		end

		local current_zone, current_subzone, pvp_label, _, zone_text = GetZoneData(false)

		tooltip:Clear()
		tooltip:SmartAnchorTo(anchor)
		tooltip:SetScale(db.tooltip.scale)

		local line, column = tooltip:AddHeader()
		tooltip:SetCell(line, 1, zone_text, "CENTER", 6)

		line, column = tooltip:AddHeader()
		tooltip:SetCell(line, 1, pvp_label, "CENTER", 6)
		tooltip:AddSeparator()

		line, column = tooltip:AddLine()
		coord_line = line

		tooltip:SetCell(line, column, _G.LOCATION_COLON, "LEFT", 2)
		SetCoordLine()

		tooltip:AddLine(" ")

		if LT:DoesZoneHaveInstances(current_zone) then
			local cur_instances = db.tooltip_sections.cur_instances
			local header_line = tooltip:AddHeader()
			local count = 0

			if cur_instances then
				tooltip:AddSeparator()

				for instance in LT:IterateZoneInstances(current_zone) do
					Tooltip_AddInstance(instance)
					count = count + 1
				end
				tooltip:AddLine(" ")
			end
			tooltip:SetCell(header_line, 1, cur_instances and ICON_MINUS or ICON_PLUS)
			tooltip:SetCell(header_line, 2, (count > 1 and _G.MULTIPLE_DUNGEONS or _G.LFG_TYPE_DUNGEON), "LEFT", 5)

			tooltip:SetCellScript(header_line, 1, "OnMouseUp", SectionOnMouseUp, "cur_instances")
		end

		local found_battleground = false

		if LT:HasRecommendedInstances() then
			local rec_instances = db.tooltip_sections.rec_instances

			line = tooltip:AddHeader()
			tooltip:SetCell(line, 1, rec_instances and ICON_MINUS or ICON_PLUS)
			tooltip:SetCell(line, 2, L["Recommended Instances"], "LEFT", 5)

			tooltip:SetCellScript(line, 1, "OnMouseUp", SectionOnMouseUp, "rec_instances")

			-- Unfortunately, two separate checks for rec_instances are needed for the separator and
			-- the empty line below since rec_instances may be false but we need to gather battleground
			-- information in the instance loop.
			if rec_instances then
				tooltip:AddSeparator()
			end

			for instance in LT:IterateRecommendedInstances() do
				if LT:IsBattleground(instance) then
					if not found_battleground then
						_G.wipe(battlegrounds)
						found_battleground = true
					end
					battlegrounds[instance] = true
				elseif rec_instances then
					Tooltip_AddInstance(instance)
				end
			end

			if rec_instances then
				tooltip:AddLine(" ")
			end
		end

		local rec_zones = db.tooltip_sections.rec_zones

		line = tooltip:AddHeader()
		tooltip:SetCell(line, 1, rec_zones and ICON_MINUS or ICON_PLUS)
		tooltip:SetCell(line, 2, L["Recommended Zones"], "LEFT", 5)

		tooltip:SetCellScript(line, 1, "OnMouseUp", SectionOnMouseUp, "rec_zones")

		if rec_zones then
			tooltip:AddSeparator()

			for zone in LT:IterateRecommendedZones() do
				local r1, g1, b1 = LT:GetLevelColor(zone)
				local hex1 = string.format("|cff%02x%02x%02x", r1 * 255, g1 * 255, b1 * 255)

				local r2, g2, b2 = LT:GetFactionColor(zone)
				local hex2 = string.format("|cff%02x%02x%02x", r2 * 255, g2 * 255, b2 * 255)

				local min, max = LT:GetLevel(zone)
				local level_str

				if min == max then
					level_str = string.format("%s%d|r", hex1, min)
				else
					level_str = string.format("%s%d - %d|r", hex1, min, max)
				end
				line = tooltip:AddLine()
				tooltip:SetCell(line, 1, string.format("%s%s|r", hex2, zone), "LEFT", 2)
				tooltip:SetCell(line, 3, level_str)
				tooltip:SetCell(line, 5, LT:GetContinent(zone))
			end
			tooltip:AddLine(" ")
		end

		if found_battleground then
			local bg_toggled = db.tooltip_sections.battlegrounds

			line = tooltip:AddHeader()
			tooltip:SetCell(line, 1, bg_toggled and ICON_MINUS or ICON_PLUS)
			tooltip:SetCell(line, 2, _G.BATTLEGROUNDS, "LEFT", 5)

			tooltip:SetCellScript(line, 1, "OnMouseUp", SectionOnMouseUp, "battlegrounds")

			if bg_toggled then
				tooltip:AddSeparator()

				for instance in pairs(battlegrounds) do
					Tooltip_AddInstance(instance)
				end
				tooltip:AddLine(" ")
			end
		end

		local misc_toggled = db.tooltip_sections.miscellaneous

		line = tooltip:AddLine()

		tooltip:SetCell(line, 1, misc_toggled and ICON_MINUS or ICON_PLUS)
		tooltip:SetCell(line, 2, _G.MISCELLANEOUS, "LEFT", 5)

		tooltip:SetCellScript(line, 1, "OnMouseUp", SectionOnMouseUp, "miscellaneous")

		if misc_toggled then
			tooltip:AddSeparator()

			line, column = tooltip:AddLine()
			tooltip:SetCell(line, column, _G.CONTINENT, "LEFT", 2)
			tooltip:SetCell(line, 5, LT:GetContinent(current_zone))

			local min, max = LT:GetLevel(current_zone)

			if min > 0 and max > 0 then
				local r, g, b = LT:GetLevelColor(current_zone)
				local hex = string.format("|cff%02x%02x%02x", r * 255, g * 255, b * 255)

				line = tooltip:AddLine()
				tooltip:SetCell(line, 1, _G.LEVEL_RANGE, "LEFT", 2)
				tooltip:SetCell(line, 3, string.format("%s%d - %d|r", hex, min, max))
			end

			local fish_lev = LT:GetFishingLevel(current_zone)

			if fish_lev then
				line = tooltip:AddLine()
				tooltip:SetCell(line, 1, string.format(_G.SPELL_FAILED_FISHING_TOO_LOW, fish_lev), "CENTER", 6)
			end
			tooltip:AddLine(" ")
		end

		if not db.tooltip.hide_hint then
			line = tooltip:AddLine()
			tooltip:SetCell(line, 1, L["Left-click to open the World Map."], "LEFT", 6)

			line = tooltip:AddLine()
			tooltip:SetCell(line, 1, L["Shift+Left-click to announce your location."], "LEFT", 6)

			if Atlas_Toggle then
				line = tooltip:AddLine()
				tooltip:SetCell(line, 1, L["Control+Left-click to toggle Atlas."], "LEFT", 6)
			end

			line = tooltip:AddLine()
			tooltip:SetCell(line, 1, L["Right-click to open configuration menu."], "LEFT", 6)
		end
		updater.elapsed = 0
		tooltip:Show()
	end

	function TravelAgent:Update()
		local _, _, _, text, color_text = GetZoneData(true)
		local num = math.random(9)

		CHAT_TEXT = text

		DataObj.text = color_text
		DataObj.icon = string.format("Interface\\Icons\\INV_Misc_Map%s0%d", (num == 1 and "_" or ""), num)

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
		db = temp_db.global

		self:SetupOptions()
	end
end	-- do

local CoordFeedData = {
	type	= "data source",
	icon	= "Interface\\Icons\\INV_Torch_Lit",
	text	= "",
	OnEnter	= LDB_OnEnter,
	OnLeave	= LDB_OnLeave,
	OnClick = LDB_OnClick,
}

function TravelAgent:OnEnable()
	self:RegisterEvent("ZONE_CHANGED", self.Update)
	self:RegisterEvent("ZONE_CHANGED_INDOORS", self.Update)
	self:RegisterEvent("ZONE_CHANGED_NEW_AREA", self.Update)

	DataObj = LDB:NewDataObject(ADDON_NAME, {
		type	= "data source",
		label	= ADDON_NAME,
		text	= " ",
		icon	= "Interface\\Icons\\INV_Misc_Map_0" .. math.random(9),
		OnEnter	= LDB_OnEnter,
		OnLeave	= LDB_OnLeave,
		OnClick	= LDB_OnClick,
	})

	if db.datafeed.show_coords then
		CoordFeed = LDB:NewDataObject(ADDON_NAME.."Coordinates", CoordFeedData)
	end

	if LDBIcon then
		LDBIcon:Register(ADDON_NAME, DataObj, db.datafeed.minimap_icon)
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
			name = ADDON_NAME,
			childGroups = "tab",
			type = "group",
			args = {
				datafeed = {
					name	= L["Datafeed"],
					order	= 2,
					type	= "group",
					args = {
						minimap_icon = {
							order	= 1,
							type	= "toggle",
							width	= "full",
							name	= L["Minimap Icon"],
							desc	= L["Draws the icon on the minimap."],
							get	= function()
									  return not db.datafeed.minimap_icon.hide
								  end,
							set	= function(info, value)
									  db.datafeed.minimap_icon.hide = not value

									  LDBIcon[value and "Show" or "Hide"](LDBIcon, ADDON_NAME)
								  end,
						},
						show_zone = {
							order	= 2,
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
							order	= 3,
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
						show_coords = {
							order	= 4,
							type	= "toggle",
							width	= "full",
							name	= L["Show Coordinates"],
							desc	= L["Displays the coordinates of the current location."],
							get	= function()
									  return db.datafeed.show_coords
								  end,
							set	= function(info, value)
									  db.datafeed.show_coords = value

									  if db.datafeed.show_coords then
										  if not CoordFeed then
											  CoordFeed = LDB:NewDataObject(ADDON_NAME.."Coordinates", CoordFeedData)
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
						timer = {
							order	= 5,
							type	= "range",
							width	= "full",
							name	= L["Tooltip Timer"],
							desc	= L["Move the slider to adjust the tooltip fade time."],
							min	= 0.1,
							max	= 2,
							step	= 0.01,
							get	= function()
									  return db.tooltip.timer
								  end,
							set	= function(info, value)
									  db.tooltip.timer = math.max(0.1, math.min(2, value))
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
