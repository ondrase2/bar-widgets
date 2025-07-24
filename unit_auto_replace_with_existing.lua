---@diagnostic disable: duplicate-set-field

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
--
--  file:    unit_auto_replace.lua
--  brief:   Automatically replaces units and replicates their orders if they are destroyed
--  author:  Simon Gardner
--
--  Copyright (C) 2023.
--  Licensed under the terms of the GNU GPL, v2 or later.
--
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
-- Usage Instructions:
--
-- Causes selected units to be automatically replaced when destroyed.
--
-- For example a spotter plane could be given a patrol route and then
-- and Ctrl-U command given. If the spotter is destoyed then a build order
-- for a new spotter will be added to the appropriate factory.
-- When the replacement unit leaves the factory it will be reinstated with its original
-- orders as at the time Ctrl-U was pressed.
-- Works with multiple units and orders allowing new tactics to be devised.
-- Alternative tacticss incldue automatically replaced spybots or fighter screens.
--
-- Ctrl-U - Tags the selected units for automatic replacement with their current orders
-- Ctrl-J - Cancels any saved auto-replacement orders for the selected units.
--
-- Units will be replaced indefinitely until the Ctrl-J cmd is issued.

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

function widget:GetInfo()
  return {
    name    = 'Unit AutoReplace',
    desc    = 'Automatically replaces units and replicates their orders if they are destroyed',
    author  = 'slgard@gmail.com',
    date    = '2023-10-14',
    license = 'GNU GPL, v2 or later',
    layer   = 10,
    enabled = true,
  }
end

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

-- Alias Spring API calls for performance
local myTeamID = Spring.GetMyTeamID() --todo handle teamchanged
local Echo = Spring.Echo
local GetTeamUnits = Spring.GetTeamUnits
local GetSelectedUnits = Spring.GetSelectedUnits
local GetUnitDefID = Spring.GetUnitDefID
local GiveOrderToUnit = Spring.GiveOrderToUnit
local GetUnitCommands = Spring.GetUnitCommands
local GetUnitPosition = Spring.GetUnitPosition


--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
-- local state
local unitsMarkedForReplacement = {}
local unitFactoryOrdersCache = {}
local unitTransportOrdersCache = {}


--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
-- Utility functions

-- Spring.GetUnitPosition has a strange return type that also
-- includes optional middle points and aim point so lets simplify that
local function GetUnitLocation(unitID)
  local x, y, z, _ = GetUnitPosition(unitID)
  return { x, y, z }
end


local function GiveOrdersToUnit(unitID, cmds)
  for i, cmd in ipairs(cmds) do
    GiveOrderToUnit(unitID, cmd.id, cmd.params, { shift = true })
  end
end

local function CanItBuild(unitDef, unitTypeID)
  for _, buildOptionID in ipairs(unitDef.buildOptions) do
    if buildOptionID == unitTypeID then return true end
  end
end

local function GetFactoriesThatCanBuildUnitType(unitTypeID)
  local allUnits = GetTeamUnits(myTeamID)
  local builderUnits = {}

  for _, unitID in ipairs(allUnits) do
    local unitDef = UnitDefs[GetUnitDefID(unitID)]

    if unitDef and unitDef.isFactory and CanItBuild(unitDef, unitTypeID) then
      table.insert(builderUnits, unitID)
    end
  end

  return builderUnits
end

local function BuildReplacementUnit(unitID, unitDefID)
  local unit = unitsMarkedForReplacement[unitID]
  local factoryID = table.remove(GetFactoriesThatCanBuildUnitType(unitDefID))
  if factoryID == nil then
    return
  end

  -- tell factory to build replacement unit
  GiveOrderToUnit(factoryID, -unitDefID, {}, {})

  -- add entry to dictionary so we can retrieve the original orders when the replacement unit has been built
  table.insert(unitFactoryOrdersCache, {
    unitDefID = unitDefID,
    factoryID = factoryID,
    cmds = unit.cmds,
  })
end

local function ExtractFromUnitFactoryOrdersCache(unitDefID)
  for i, order in ipairs(unitFactoryOrdersCache) do
    if order.unitDefID == unitDefID then
      table.remove(unitFactoryOrdersCache, i)
      return order
    end
  end
  return nil
end

local function isCmdEq(cmd1, cmd2)
  if cmd1.id ~= cmd2.id then return false end
  if #cmd1.params ~= #cmd2.params then return false end
  for i, _ in ipairs(cmd1.params) do
    if cmd1.params[i] ~= cmd2.params[i] then return false end
  end
  return true
end

local function isCmdInCmds(cmd, cmds)
  for _, ele in ipairs(cmds) do
    if isCmdEq(cmd, ele) then return true end
  end
  return false
end

local function FindLast(inputTable, fn)
  for i = #inputTable, 1, -1 do
    if fn(inputTable[i]) then
      return inputTable[i]
    end
  end
end

local function FilterList(inputTable, fn)
  local outputTable = {}
  for _, ele in ipairs(inputTable) do
    if fn(ele) then
      table.insert(outputTable, ele)
    end
  end
  return outputTable
end

local function SetUnitAutoReplacement(selectedUnits)
  for _, unitID in ipairs(GetSelectedUnits()) do
    local unitDefID = GetUnitDefID(unitID)
    if not UnitDefs[unitDefID].isFactory then
      Echo("AutoReplace: " .. UnitDefs[unitDefID].name)-- .. " : " .. unitID)

      -- get current unit commands
      local cmds = GetUnitCommands(unitID, 20)

      -- make unit first move to it's location when it received the AutoReplace command
      local unitLocation = GetUnitLocation(unitID)
      table.insert(cmds, 1, { id = CMD.MOVE, params = unitLocation, options = { shift = true } })
      unitsMarkedForReplacement[unitID] = {
        cmds = cmds,
      }
    end
  end
end

local function UnSetUnitAutoReplacement(selectedUnits)
  for _, unitID in ipairs(selectedUnits) do
    if unitsMarkedForReplacement[unitID] ~= nil then
      local unitDefID = GetUnitDefID(unitID)
      Echo("AutoReplace unset: " .. UnitDefs[unitDefID].name)-- .. " : " .. unitID)
      unitsMarkedForReplacement[unitID] = nil
    end
  end
end

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
-- Game engine hooks
function widget:KeyPress(key, mods, isRepeat)
  if mods.ctrl and key == 117 and not mods.shift and not mods.alt then     -- Ctrl-U
    SetUnitAutoReplacement(GetSelectedUnits())
  elseif mods.ctrl and key == 106 and not mods.shift and not mods.alt then -- Ctrl-J
    UnSetUnitAutoReplacement(GetSelectedUnits())
  end
end

function widget:UnitLoaded(unitID, unitDefID, unitTeam, transportID, transportTeam)
  if unitTeam ~= myTeamID then return end

  local replacementUnitDef = unitsMarkedForReplacement[unitID]
  if replacementUnitDef == nil then return end

  -- if there are no factory commands then we're not picking up a replaceable unit so ignore
  if replacementUnitDef.factoryCmds == nil then return end
  local postDisembarkCmds = FilterList(GetUnitCommands(unitID, 20), function(cmd)
    -- sometimes units will have an additional wait command from being to told to wait for the transport
    -- sometimes units have incompleted orders in their queue from leaving the factor
    -- so remove WAITs and factory commands to avoid weird behaviour from units
    -- (like not moving at all or trying to walk back to the factory)
    return cmd.id ~= CMD.WAIT and not isCmdInCmds(cmd, replacementUnitDef.factoryCmds)
  end)

  local startLocation = GetUnitLocation(transportID)
  local lastMoveCmd = FindLast(replacementUnitDef.factoryCmds, function(cmd)
    return cmd.id == CMD.MOVE
  end)

  -- clear existing transport orders (from Transport AI widget)
  GiveOrderToUnit(transportID, CMD.STOP, {}, {})

  -- copy factory assigned unit orders to the transport
  GiveOrdersToUnit(transportID, replacementUnitDef.factoryCmds)

  -- tell the transport to unload the unit at the destination
  GiveOrderToUnit(transportID, CMD.UNLOAD_UNITS, lastMoveCmd.params, { shift = true })

  -- return the transport to it's starting location
  GiveOrderToUnit(transportID, CMD.MOVE, startLocation, { shift = true })

  -- save unit orders for when the unit is unloaded
  unitTransportOrdersCache[unitID] = {
    cmds = postDisembarkCmds
  }
end

function widget:UnitUnloaded(unitID, unitDefID, unitTeam, transportID, transportTeam)
  if unitTeam ~= myTeamID then return end


  -- restore unit orders from before it was transported
  local cachedUnitCmds = unitTransportOrdersCache[unitID]
  if cachedUnitCmds == nil then return end

  -- not sure why adding a STOP here helps, but it prevents some strange behavior
  -- from the unit where it effectively ignores FIGHT and PATROL orders after transportation
  GiveOrderToUnit(unitID, CMD.STOP, {}, {})
  -- restore the units pre-transport orders
  GiveOrdersToUnit(unitID, cachedUnitCmds.cmds)

  -- clear transport orders cache
  unitTransportOrdersCache[unitID] = nil
end

function widget:UnitFromFactory(unitID, unitDefID, unitTeam, factID, factDefID, userOrders)
  if unitTeam ~= myTeamID then return end

  -- check if we have replacement orders for this unit type
  local replacementOrders = ExtractFromUnitFactoryOrdersCache(unitDefID)
  if replacementOrders == nil then return end

  -- get any unit orders assigned by the factory
  local factoryCmds = GetUnitCommands(unitID, 20)

  -- add the replacement orders to this unit
  GiveOrdersToUnit(unitID, replacementOrders.cmds)

  -- mark this unit for replacement
  -- and save factory assigned commands to interoperate with the Transport AI widget.
  unitsMarkedForReplacement[unitID] = {
    cmds = replacementOrders.cmds,
    factoryCmds = factoryCmds
  }
end

function widget:UnitDestroyed(unitID, unitDefID, unitTeam, attackerID, attackerDefID, attackerTeam)
  if unitTeam ~= myTeamID then return end

  -- clean up references to this unit
  unitTransportOrdersCache[unitID] = nil

  if unitsMarkedForReplacement[unitID] then
   -- BuildReplacementUnit(unitID, unitDefID) --bugged
   for _, otherunitID in ipairs(Spring.GetTeamUnits(myTeamID)) do
		local otherunitDefID = GetUnitDefID(otherunitID)
		if otherunitDefID == unitDefID and unitsMarkedForReplacement[otherunitID] == nil then
      
      unitsMarkedForReplacement[otherunitID] = unitsMarkedForReplacement[unitID]
      Echo("replaced " .. UnitDefs[otherunitDefID].name )--.. " : " .. unitID .. " with " .. otherunitID)
      GiveOrdersToUnit(otherunitID, unitsMarkedForReplacement[unitID].cmds)
      
      break
    end
	 end
  end
  unitsMarkedForReplacement[unitID] = nil
end