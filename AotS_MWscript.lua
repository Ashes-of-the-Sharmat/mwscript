-- Wrapper for the creation and running of temporary dynamically generated MWscript scripts, including handling of feedback via global variable changes
-- Written by Vidi_Aquam

AotS_MWscript = {}

local variablePattern = "var_"
local scriptRecordPrefix = "serverScript_"

local variableTypes = { -- Use a table instead of string.upper to prevent use of "string" variable type since MWscript only uses shorts, longs, and floats
    ["short"] = enumerations.variableType.SHORT,
    ["long"] = enumerations.variableType.LONG,
    ["float"] = enumerations.variableType.FLOAT,

    ["s"] = enumerations.variableType.SHORT, -- Also for shorthand versions
    ["l"] = enumerations.variableType.LONG,
    ["f"] = enumerations.variableType.FLOAT
}

local data = {}
local scriptIndex = 0

local generateScriptRecordId = function()
    scriptIndex = scriptIndex + 1
    return string.lower(scriptRecordPrefix .. scriptIndex)
end

local getGeneratedVariableName = function(id, varIndex)
    return string.lower(id .. variablePattern .. varIndex)
end

local getIdFromVariableName = function(var)
    for id in pairs(data) do
        for _, varEntry in ipairs(data[id].variables) do
            if varEntry[1] == var then return id end
        end
    end
end

AotS_MWscript.createScript = function(text, callbackHandler, variables)
    -- text = script text; use $name for the script name and $global1, $global2, $global3, etc. for variables whose values will be sent to the server when changed
    -- callbackHandler = function to be run when receiving a MWscript global variable change from this particular MWscript; called with the arguments of pid, variable index (the 1 of $global1 or 2 of $global2), and new variable value
    -- variables = table of strings (see variableTypes above) corresponding to the types of each feedback MWscript global variable; the first will be $global1 in script text, the second $global2, and so on

    local id = generateScriptRecordId()
    data[id] = {variables = {}}

    -- Register callback
    data[id].callback = callbackHandler

    -- Deal with variables
    tes3mp.ClearClientGlobals()
    if variables and type(variables) == "table" then
        for index, kind in ipairs(variables) do
            if variableTypes[string.lower(kind)] then
                local varName = getGeneratedVariableName(id, index)
                local varType = variableTypes[string.lower(kind)]

                data[id].variables[#data[id].variables+1] = {varName, varType}
                text = string.gsub(text, "$global" .. index, varName) 
            end
        end
    end

    -- Deal with script record
    text = string.gsub(text, "$name", id) 
    data[id].scriptText = text

    return id
end

AotS_MWscript.sendScriptToPlayer = function (pid, id, sendToAll)
    -- Send a created script to a player
    if data[id] then
        tes3mp.ClearClientGlobals()
        for index, varEntry in ipairs(data[id].variables) do
            if varEntry[2] == enumerations.variableType.FLOAT then
                tes3mp.AddClientGlobalFloat(varEntry[1], 0)
            else
                tes3mp.AddClientGlobalInteger(varEntry[1], 0, varEntry[2])
            end
            tes3mp.AddSynchronizedClientGlobalId(varEntry[1])
        end

        if #data[id].variables > 0 then
            tes3mp.SendClientScriptGlobal(pid, sendToAll, false)
            tes3mp.SendClientScriptSettings(pid, sendToAll)
        end

        tes3mp.ClearRecords()
        tes3mp.SetRecordType(enumerations.recordType.SCRIPT)
        tes3mp.SetRecordId(id)
        tes3mp.SetRecordScriptText(data[id].scriptText)
        tes3mp.AddRecord()
        tes3mp.SendRecordDynamic(pid, sendToAll, false)
    end
end

AotS_MWscript.sendVariableUpdate = function(pid, id, varIndex, value, sendToAll)
    if data[id] and data[id].variables[varIndex] then
        tes3mp.ClearClientGlobals()

        local varEntry = data[id].variables[varIndex]
        if varEntry[2] == enumerations.variableType.FLOAT then
            tes3mp.AddClientGlobalFloat(varEntry[1], value)
        else
            tes3mp.AddClientGlobalInteger(varEntry[1], value, varEntry[2])
        end

        tes3mp.SendClientScriptGlobal(pid, sendToAll, false)
    end
end

AotS_MWscript.runScriptOnPlayer = function(pid, id, forAll)
    logicHandler.RunConsoleCommandOnPlayer(pid, "StartScript " .. id , forAll)
end

AotS_MWscript.callbackHandler = function(pid, variables)
    for name, variable in pairs(variables) do
        local id = getIdFromVariableName(name)
        if id and data[id].callback then
            local varIndex = 0
            for index, varEntry in ipairs(data[id].variables) do
                if varEntry[1] == name then
                    varIndex = index
                    break
                end
            end
            data[id].callback(pid, varIndex, variable.intValue)
        end
        return customEventHooks.makeEventStatus(false, false)
    end
end

customEventHooks.registerValidator("OnClientScriptGlobal", function(eventStatus, pid, variables) AotS_MWscript.callbackHandler(pid, variables) end)

-- Example --

-- customEventHooks.registerHandler("OnPlayerAuthentified", function (eventStatus, pid)
--     local text = [[
--         Begin $name

--         short wasJumping
--         short wasSneaking

--         if ( wasJumping == 0 )
--             if ( GetPCJumping == 1 )
--                 set wasJumping to 1
--                 set $global1 to ( $global1 + 1 )
--                 MessageBox, "Client Jump Counter: %G", $global1 
--             endif
--         else
--             if ( GetPCJumping == 0 )
--                 set wasJumping to 0
--             endif
--         endif

--         if ( wasSneaking == 0 )
--             if ( GetPCSneaking == 1 )
--                 set wasSneaking to 1
--                 set $global2 to ( $global2 + 1 )
--                 MessageBox, "Client Sneak Counter: %G", $global2 
--             endif
--         else
--             if ( GetPCSneaking == 0 )
--                 set wasSneaking to 0
--             endif
--         endif

--         End
--     ]]

--     local id = AotS_MWscript.createScript(text, function (pid, varIndex, value)
--         if varIndex == 1 then
--             tes3mp.MessageBox(pid, 999999, "Server Jump Counter: " .. value)
--         elseif varIndex == 2 then
--             tes3mp.MessageBox(pid, 999999, "Server Sneak Counter: " .. value)
--         end
--     end, {"long", "long"})

--     AotS_MWscript.sendScriptToPlayer(pid, id)

--     AotS_MWscript.runScriptOnPlayer(pid, id)
-- end)
