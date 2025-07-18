local versionNum = '1.00'

local widget = widget ---@type Widget


local GetUnitGroup = Spring.GetUnitGroup
local SetUnitGroup = Spring.SetUnitGroup
local GetSelectedUnits = Spring.GetSelectedUnits
local GetUnitDefID = Spring.GetUnitDefID
local GetUnitHealth = Spring.GetUnitHealth
local GetUnitIsBeingBuilt = Spring.GetUnitIsBeingBuilt
local GetMouseState = Spring.GetMouseState
local SelectUnitArray = Spring.SelectUnitArray
local TraceScreenRay = Spring.TraceScreenRay
local GetUnitPosition = Spring.GetUnitPosition
local GetGameFrame = Spring.GetGameFrame
local Echo = Spring.Echo
local GetUnitRulesParam = Spring.GetUnitRulesParam

function widget:GetInfo()
	return {
		name = "add selection to group",
		desc = "v" .. (versionNum) .. " shift+0-9 adds selected units to group.",
		author = "ondrase",
		date = "Mar 23, 2025",
		license = "GNU GPL, v2 or later",
		layer = 100,
		enabled = true
	}
end

include("keysym.h.lua")

-- Game engine hooks
function widget:KeyPress(key, mods, isRepeat)
    if mods.shift and key > 47 and key < 58 and not mods.ctlr and not mods.alt then
      local num = key - 48
      --Echo("keyid: " .. key)
      --Echo("num: " .. num)
      for _, unitid in ipairs(GetSelectedUnits()) do
        SetUnitGroup(unitid, num)


      end
    elseif mods.ctrl and key == 106 and not mods.shift and not mods.alt then
      UnSetUnitAutoReplacement(GetSelectedUnits())
    end
end

