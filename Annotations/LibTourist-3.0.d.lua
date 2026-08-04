---@meta

---@class LibTourist-3.0
local Tourist = {}

--- Returns true if the zone is known and contains one or more dungeon or raid instances.
---@param zone string | number unique (localized) zone name or uiMapID
---@return boolean hasInstances
function Tourist:DoesZoneHaveInstances(zone) end

--- Returns the localized name of the complex in which the instance resides, if any.
---@param zone string | number  unique (localized) name or uiMapID of an instance
---@return string? complexName
function Tourist:GetComplex(zone) end

--- Returns the localized name of the continent on which the given zone resides. Returns the localized continent name if the zone is a continent.
---@param zone string | number unique (localized) zone name or uiMapID
---@return string continentName
function Tourist:GetContinent(zone) end

--- Returns localized zone name, x-coordinate and y-coordinate of the entrance portal of the given instance, if the instance and the coordinates are known.
--- The coordinates are values between 0 and 1.
---@param instance string | number unique (localized) name  or uiMapID of an instance
---@return (string zoneName, number x, number y)
function Tourist:GetEntrancePortalLocation(instance) end

--- Returns an r, g and b value representing a color, depending on the given zone and the current character's faction.
---
--- * Blue = sanctuary
--- * Orange = PvP
--- * Green = friendly
--- * Red = hostile
--- * Yellow = neutral, contested or unknown.
---@param zone string | number unique (localized) zone name or uiMapID
---@return (number r, number g, number b)
function Tourist:GetFactionColor(zone) end

--- Returns fishing skill info for the specified zone (localized zone name or mapID):
--- - skillName: Name of the required fishing skill
--- - maxLevel: Maximum skill level that can be reached for that skill
--- - currentSkill: Current player skill level for that fishing skill
--- - skillEnabled: true if the player has learned the required skill
--- Note: no data is available if a skill has not been learned, so if skillEnabled is false, other values will be empty.
---@param zone string | number unique (localized) zone name or uiMapID
---@return FishingSkillInfo
function Tourist:GetFishingSkillInfo(zone) end

--- Returns the primary group size of the given instance. If the primary group size is variable, the maximum group size will be returned (for backward compatibility).
---@param instance string | number unique (localized) name or uiMapID of an instance
---@return number groupSize
function Tourist:GetInstanceGroupSize(instance) end

--- Returns the localized name of the zone in which the instance resides.
---@param instance string | number unique (localized) name or uiMapID of an instance
---@return string zoneName
function Tourist:GetInstanceZone(instance) end

--- Returns the minimum and maximum level for the given zone, instance or battleground.
---
--- If zone is a zone or an instance, a third value is returned: the scaled zone level. This is the level 'presented' to the player when inside the zone. It's calculated by GetScaledZoneLevel.
---
--- This method takes the active Chromie Time expansion into account, if one is selected.
---@param zone string| number unique (localized) zone name or uiMapID
---@return (number minLevel, number maxLevel)
function Tourist:GetLevel(zone) end

--- Returns an r, g and b value representing a color ranging from grey (too low) via green, yellow and orange to red (too high), by calling CalculateLevelColor with the min and max level of the given zone and the current player level.
--- Note: if zone is a zone or an instance, the zone's scaled level (calculated by GetScaledZoneLevel) is used instead of it's minimum and maximum level.
--- GetLevelColor returns r/g/b-values for the following colors:
---
--- * City or level unknown -> White
--- * Exact match, one-level bracket -> Yellow
--- * Player is three or more levels short of Low -> Red
--- * Player is two or less levels short of Low -> sliding scale between Red and Orange
--- * Player is at low, at least two-level bracket -> Orange
--- * Player is between low and the middle of the bracket -> sliding scale between Orange and Yellow
--- * Player is at the middle of the bracket -> Yellow
--- * Player is between the middle of the bracket and High -> sliding scale between Yellow and Green
--- * Player is at High, at least two-level bracket -> Green
--- * Player is up to three levels above High -> sliding scale between Green and Gray
--- * Player is at High + 3 or above -> Gray
---@param zone string | number unique (localized) zone name or uiMapID
---@return (number r, number g, number b)
function Tourist:GetLevelColor(zone) end

---This function replaces the abandoned LibBabble-Zone library and returns a lookup table containing all zone names (including continents, instances etcetera) where the English zone name is the key and the localized zone name is the value.
---@return table<string, string>
function Tourist:GetLookupTable() end

--- Returns true if recommended instances are available for the current player.
---@return boolean
function Tourist:HasRecommendedInstances() end

--- Returns true if the zone is a Battleground.
---@param zone string | number unique (localized) zone name or uiMapID
---@return boolean
function Tourist:IsBattleground(zone) end

--- Iterates through the unique localized names of all Battlegrounds and Instances for which the player level is within the zone's level range.
function Tourist:IterateRecommendedInstances() end

--- Iterates through the unique localized names of all Zones and PvP Zones for which the player level is within the zone's level range. The list is based on the scaled level of the zones, as calculated by GetScaledZoneLevel, and therefore returns all zones that can scale to the player's current level.
function Tourist:IterateRecommendedZones() end

--- Iterates through the unique localized names of all dungeon and raid Instances within the given zone.
---@param zone string | number unique (localized) zone name or uiMapID
function Tourist:IterateZoneInstances(zone) end

--------------------------------------------------------------------------------
---- Auxiliary Types
--------------------------------------------------------------------------------

---@class FishingSkillInfo
---@field skillName string Name of the required fishing skill
---@field maxLevel number Maximum skill level that can be reached for that skill
---@field currentSkill number Current player skill level for that fishing skill
---@field skillEnabled boolean true if the player has learned the required skill
