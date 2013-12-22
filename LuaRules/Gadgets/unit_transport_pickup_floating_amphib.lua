function gadget:GetInfo()
  return {
    name      = "AirTransport_SeaPickup",
    desc      = "Allow air transport to use amphibious' floatation gadget to pickup unit at sea",
    author    = "msafwan (xponen)",
    date      = "22.12.2013",
    license   = "GNU GPL, v2 or later",
    layer     = 0,
    enabled   = true  --  loaded by default?
  }
end

--------------------------------------------------------------------------------
--  «COMMON»  ------------------------------------------------------------------
--------------------------------------------------------------------------------
if (gadgetHandler:IsSyncedCode()) then
--------------------------------------------------------------------------------
--  «SYNCED»  ------------------------------------------------------------------
--------------------------------------------------------------------------------


--Speed-ups
local spGetUnitDefID    = Spring.GetUnitDefID;
local spGiveOrderToUnit = Spring.GiveOrderToUnit
local spSetUnitMoveGoal = Spring.SetUnitMoveGoal
local spGetUnitCommands = Spring.GetUnitCommands
local spGetCommandQueue = Spring.GetCommandQueue
local spGetUnitPosition = Spring.GetUnitPosition
local spGetGroundHeight = Spring.GetGroundHeight
local spGetUnitAllyTeam = Spring.GetUnitAllyTeam
local spGetUnitStates = Spring.GetUnitStates
local spGetUnitIsTransporting = Spring.GetUnitIsTransporting
local spGetUnitsInCylinder = Spring.GetUnitsInCylinder
local spGiveOrderArrayToUnitArray = Spring.GiveOrderArrayToUnitArray

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

-- commands

include("LuaRules/Configs/customcmds.h.lua")
local floatDefs = include("LuaRules/Configs/float_defs.lua")

local extendedloadCmdDesc = {
  id      = CMD_EXTENDED_LOAD, --defined in customcmds.h.lua
  type    =	CMDTYPE.ICON_UNIT_OR_AREA , --have unitID or mapPos + radius
  name    = 'extendloadunit',
  --hidden  = true,
  cursor  = 'Loadunits', 
  action  = 'extendloadunit',
  tooltip = 'Load unit into transport, call amphibious to surface if possible.',
}

local extendedunloadCmdDesc = {
  id      = CMD_EXTENDED_UNLOAD, --defined in customcmds.h.lua
  type    =	CMDTYPE.ICON_MAP , --have mapPos
  name    = 'extendunloadunit',
  --hidden  = true,
  cursor  = 'Unloadunits', 
  action  = 'extendunloadunit',
  tooltip = 'Unload unit from transport, drop amphibious to water if possible.',
}

local sinkCommand = {
	[CMD.MOVE] = true,
	[CMD.GUARD] = true,
	[CMD.FIGHT] = true,
	[CMD.PATROL] = true,
	[CMD_WAIT_AT_BEACON] = true,
}

local transportPhase = {}
local giveLOAD_order = {}
local giveDROP_order = {}
local maintainFloat = {}
local maintainFloatCount = 0

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

local function IsUnitAllied(unitID1,unitID2)
	if spGetUnitAllyTeam(unitID1) == spGetUnitAllyTeam(unitID2) then
		return true
	else
		return false
	end
end

local function IsUnitIdle(unitID)
	local cQueue = spGetCommandQueue(unitID, 1)
	local moving = cQueue and #cQueue > 0 and sinkCommand[cQueue[1].id]
	return not moving
end


--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

function gadget:Initialize()
  gadgetHandler:RegisterCMDID(CMD_EXTENDED_LOAD);
  gadgetHandler:RegisterCMDID(CMD_EXTENDED_UNLOAD);  
end


--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

function gadget:AllowCommand_GetWantedCommand()	
	return {[CMD.UNLOAD_UNITS] = true, [CMD.LOAD_UNITS] = true,}
end

function gadget:AllowCommand_GetWantedUnitDefID()
	return true
end

function gadget:AllowCommand(unitID, unitDefID, teamID, cmdID, cmdParams, cmdOptions)
	if (cmdID == CMD.LOAD_UNITS) and (not transportPhase[unitID] or transportPhase[unitID]:sub(1,19)~= "INTERNAL_LOAD_UNITS") then  --detected LOAD command not originated from this gadget
		if not cmdParams[2] then --not area transport
			local targetDefID = spGetUnitDefID(cmdParams[1])
			if floatDefs[targetDefID] then --targeted unit could utilize float gadget (unit_impulsefloat.lua)
				if not cmdOptions.shift then --the LOAD command was not part of a queue, order a STOP command to clear current queue (this create the normal behaviour when SHIFT modifier is not used)
					spGiveOrderToUnit(unitID, CMD.STOP,{},{})
					transportPhase[unitID] = nil
				end
				local cmd=spGetUnitCommands(unitID)
				local index = (cmd and #cmd) or 0 --get the lenght of current queue
				spGiveOrderToUnit(unitID,CMD.INSERT,{index,CMD_EXTENDED_LOAD,CMD.OPT_SHIFT,cmdParams[1]}, {"alt"}) --insert LOAD-Extension command at current index in queue
				--"PHASE A"--
				--Spring.Echo("A")
				return false --replace LOAD with LOAD-Extension command
			end
		else --is an area-transport
			local haveWater = false
			local halfRadius = cmdParams[4]*0.5
			if spGetGroundHeight(cmdParams[1],cmdParams[3]) < 0
			or spGetGroundHeight(cmdParams[1]+halfRadius,cmdParams[3]) < 0
			or spGetGroundHeight(cmdParams[1],cmdParams[3]+halfRadius) < 0
			or spGetGroundHeight(cmdParams[1]-halfRadius,cmdParams[3]) < 0
			or spGetGroundHeight(cmdParams[1],cmdParams[3]-halfRadius) < 0
			then
				haveWater = true
			end 
			if haveWater then 
				if not cmdOptions.shift then
					spGiveOrderToUnit(unitID, CMD.STOP,{},{})
					transportPhase[unitID] = nil
				end
				local cmd=spGetUnitCommands(unitID)
				local index = (cmd and #cmd) or 0
				spGiveOrderToUnit(unitID,CMD.INSERT,{index,CMD_EXTENDED_LOAD,CMD.OPT_SHIFT,unpack(cmdParams)}, {"alt"})
				return false
			end
		end
	end
	if (cmdID == CMD.UNLOAD_UNITS) then
		if not cmdOptions.shift then
			spGiveOrderToUnit(unitID, CMD.STOP,{},{})
			transportPhase[unitID] = nil
		end
		local cmd=spGetUnitCommands(unitID)
		local index = (cmd and #cmd) or 0
		local orderToSandwich = {
			{CMD.INSERT,{index,CMD.UNLOAD_UNITS,CMD.OPT_SHIFT,unpack(cmdParams)}, {"alt"}},
			{CMD.INSERT,{index+1,CMD_EXTENDED_UNLOAD,CMD.OPT_SHIFT,unpack(cmdParams)}, {"alt"}},
		}
		spGiveOrderArrayToUnitArray ({unitID},orderToSandwich)
		return false
	end 
	return true
end

function gadget:CommandFallback(unitID, unitDefID, unitTeam, cmdID, cmdParams, cmdOptions, cmdTag)
	if cmdID == CMD_EXTENDED_LOAD then
		if not cmdParams[2] then --is not area-ransport
			local cargoID = cmdParams[1]
			if GG.HoldStillForTransport_HoldFloat and IsUnitAllied(cargoID,unitID) then --is not targeting enemy
				local isHolding = GG.HoldStillForTransport_HoldFloat(cargoID) --check & call targeted unit to hold its float
				if not isHolding and transportPhase[unitID]~="ALREADY_CALL_UNIT_ONCE" and IsUnitIdle(cargoID) then --target have not float yet, and this is our first call, and targeted unit is idle enough for a float
					GG.WantToTransport_FloatNow(cargoID)
					local x,y,z = spGetUnitPosition(cargoID)
					spSetUnitMoveGoal(unitID, x,y,z, 500)
					transportPhase[unitID] = "ALREADY_CALL_UNIT_ONCE"
				end
			end
			local _,y = spGetUnitPosition(cargoID)
			if y >= -20 then --unit is above water
				--"PHASE B"--
				--Spring.Echo("B")
				local isRepeat = spGetUnitStates(unitID)["repeat"]
				local options = isRepeat and CMD.OPT_INTERNAL or CMD.OPT_SHIFT 
				transportPhase[unitID] = "INTERNAL_LOAD_UNITS " .. cargoID
				giveLOAD_order[#giveLOAD_order+1] = {unitID,CMD.INSERT,{0,CMD.LOAD_UNITS,options,cargoID}, {"alt"}}
				return true,true --remove this command
			end
			return true,false --hold this command
		else
			local units = spGetUnitsInCylinder(cmdParams[1],cmdParams[3],cmdParams[4])
			local haveFloater = false
			for i=1, #units do
				local potentialCargo = units[i]
				if GG.HoldStillForTransport_HoldFloat and IsUnitAllied(potentialCargo,unitID) then
					local isHolding = GG.HoldStillForTransport_HoldFloat(potentialCargo)
					if not isHolding and IsUnitIdle(potentialCargo) then
						GG.WantToTransport_FloatNow(potentialCargo)
					end
				end
				local _,y = spGetUnitPosition(potentialCargo)
				if y >= -20 then
					haveFloater = true
				end
			end
			if transportPhase[unitID]~="ALREADY_CALL_UNIT_ONCE" then
				spSetUnitMoveGoal(unitID, cmdParams[1],cmdParams[2],cmdParams[3],cmdParams[4]) --get into area-transport circle
				transportPhase[unitID] = "ALREADY_CALL_UNIT_ONCE"
			end
			if haveFloater then
				local isRepeat = spGetUnitStates(unitID)["repeat"]
				local options = isRepeat and CMD.OPT_INTERNAL or CMD.OPT_SHIFT 
				transportPhase[unitID] = "INTERNAL_LOAD_UNITS " .. cmdParams[1]+cmdParams[3]
				giveLOAD_order[#giveLOAD_order+1] = {unitID,CMD.INSERT,{0,CMD.LOAD_UNITS,options,unpack(cmdParams)}, {"alt"}}
				return true,true --remove this command
			end
			return true,false --hold this command
		end
		return true,true --remove this command
	elseif cmdID == CMD_EXTENDED_UNLOAD then
		local cargo = spGetUnitIsTransporting(unitID)
		if cargo and #cargo==1 then
			if transportPhase[unitID] ~= "ALREADY_CALL_UNITDROP_ONCE" then
				spSetUnitMoveGoal(unitID,cmdParams[1],cmdParams[2],cmdParams[3],64)
				transportPhase[unitID] = "ALREADY_CALL_UNITDROP_ONCE"
			end
			local x,_,z = spGetUnitPosition(unitID)
			local distance = math.sqrt((x-cmdParams[1])^2 + (z-cmdParams[3])^2)
			if distance > 64 then --wait until reach destination
				return true, false  --hold this command
			end
			local gy = spGetGroundHeight(x,z)
			local cargoDefID = spGetUnitDefID(cargo[1])
			if gy < 0 and (UnitDefs[cargoDefID].customParams.commtype or floatDefs[cargoDefID]) then
				giveDROP_order[#giveDROP_order+1] = {unitID,CMD.INSERT,{0,CMD_ONECLICK_WEAPON,CMD.OPT_INTERNAL}, {"alt"}}
				-- Spring.Echo("E")
				--"PHASE E"--
			end
		end 
		return true,true --remove this command
	end
	return false --ignore
end

function gadget:GameFrame(f)
	if f%16 == 11 then --the same frequency as command check in "unit_impulsefloat_toggle.lua" (which is at f%16 == 12)
		if maintainFloatCount > 0 then
			local i=1
			while i<=maintainFloatCount do --not yet iterate over whole entry
				local transportID = maintainFloat[i][1]
				local transporteeList = maintainFloat[i][2]
				local haveFloater = false
				for i = 1, #transporteeList do
					local potentialCargo = transporteeList[i]
					if GG.HoldStillForTransport_HoldFloat and IsUnitAllied(potentialCargo,transportID) and GG.HoldStillForTransport_HoldFloat(potentialCargo) then
						haveFloater = true
					end
				end
				local cmd=spGetUnitCommands(transportID,1)
				if cmd and cmd[1] then					
					if cmd[1]['id'] == CMD.LOAD_UNITS and haveFloater then
						i = i + 1 --go to next entry
					else
						-- delete current entry, replace it with final entry, and loop again
						maintainFloat[i] = maintainFloat[maintainFloatCount]
						maintainFloat[maintainFloatCount] = nil
						maintainFloatCount = maintainFloatCount -1
						--Spring.Echo("D")
						--"PHASE D"--
					end
				else
					-- delete current entry, replace it with final entry, and loop again
					maintainFloat[i] = maintainFloat[maintainFloatCount]
					maintainFloat[maintainFloatCount] = nil
					maintainFloatCount = maintainFloatCount -1
				end
			end
		end
	end
	if #giveLOAD_order > 0 then
		for i = 1, #giveLOAD_order do
			local order = giveLOAD_order[i]
			local transportID = order[1]
			if transportPhase[transportID] == "INTERNAL_LOAD_UNITS " .. order[3][4] + (order[3][6] or 0) then
				spGiveOrderToUnit(unpack(order))
				local transporteeList
				if not order[3][5] then
					transporteeList = {order[3][4]} 
				else
					transporteeList = spGetUnitsInCylinder(order[3][4],order[3][6],order[3][7])
				end
				transportPhase[transportID] = nil --clear a blocking tag
				maintainFloatCount = maintainFloatCount + 1
				maintainFloat[maintainFloatCount] = {transportID,transporteeList}
				--Spring.Echo("C")
				--"PHASE C"--
			end
		end
		giveLOAD_order = {}
	end
	if #giveDROP_order >0 then
		for i = 1, #giveDROP_order do
			spGiveOrderToUnit(unpack(giveDROP_order[i]))
			-- Spring.Echo("F")
			--PHASE F--
		end
		giveDROP_order = {}
	end
end

--------------------------------------------------------------------------------
--  «SYNCED»  ------------------------------------------------------------------
--------------------------------------------------------------------------------
else
--------------------------------------------------------------------------------
--  «UNSYNCED»  ----------------------------------------------------------------
--------------------------------------------------------------------------------
include("LuaRules/Configs/customcmds.h.lua")

function gadget:Initialize()
  Spring.SetCustomCommandDrawData(CMD_EXTENDED_LOAD, CMD.LOAD_UNITS, {0,0.6,0.6,1},true)
  Spring.SetCustomCommandDrawData(CMD_EXTENDED_UNLOAD, CMD.UNLOAD_UNITS, {0.6,0.6,0,1})
end

--------------------------------------------------------------------------------
--  «UNSYNCED»  ----------------------------------------------------------------
--------------------------------------------------------------------------------
end
--------------------------------------------------------------------------------
--  «COMMON»  ------------------------------------------------------------------
--------------------------------------------------------------------------------