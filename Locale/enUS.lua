local debug = false
--@debug@
debug = true
--@end-debug@

local L = LibStub("AceLocale-3.0"):NewLocale("TravelAgent", "enUS", true, debug)

if not L then return end

--@localization(locale="enUS", format="lua_additive_table", handle-unlocalized="english", escape-non-ascii=false, same-key-is-true=true)@