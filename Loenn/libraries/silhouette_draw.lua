local supportedUntilLoennVersion = require("utils.version_parser")("0.9")
local currentLoennVersion = require("meta").version

if supportedUntilLoennVersion <= currentLoennVersion then
    return nil
end

local mods = require("mods")
local settings = mods.getModSettings()

-- profiler thingy
-- local profiler = mods.requireFromPlugin("libraries.profiler", "LoennProfiler")
-- local appleCake = profiler.getAppleCake()

local loadedState = require("loaded_state")
local fileLocations = require("file_locations")

local drawableSprite = require("structs.drawable_sprite")
local smartDrawingBatch = require("structs.smart_drawing_batch")
local utils = require("utils")
local threadHandler = require("utils.threads")
local viewportHandler = require("viewport_handler")


local sceneHandler = require("scene_handler")
local inputDevice = require("input_device")

if settings.playerSilhouetteEnabled == nil then
    settings.playerSilhouetteEnabled = false
end
if settings.holdableSilhouetteEnabled == nil then
    settings.holdableSilhouetteEnabled = false
end

local device = {
    _type = "device",
    name = "AuroraSilhouetteDrawDevice",
    _enabled = true,
    PLAYER_DATA_PATH = "ModFiles/aurora_aquir_AurorasLoennPlugin/PlayerStatePath.txt",
    HOLDABLE_DATA_PATH = "ModFiles/aurora_aquir_AurorasLoennPlugin/HoldableStatePath.txt",
    PLAYER_TEXTURE = "characters/aurora_aquir_loenn_plugin_silhouette/madeline",
    OPACITY = 0.33,
    UPDATE_RATE = 1,
    playerSilhouettes = {},
    holdableSilhouettes = {}
}

device.batch = smartDrawingBatch.createOrderedBatch()

local LOENN_IS_OPEN_PATH = "ModFiles/aurora_aquir_AurorasLoennPlugin/loennOpen"
local DEBUGRC_FAILED = false
local GET_FULL_DATA = true 

local SilhouetteDraw = {}
--[[local silhouette_canvas
local canvasWidth = 320
local canvasHeight = 180
]]

local function createLoennIsOpenFile()
    local path = utils.joinpath(fileLocations.getCelesteDir(), LOENN_IS_OPEN_PATH);
    local f, err = io.open(path, "w")
    if not f then return end
    f:write("")
    f:close()
end

local already_checking_loenn_open = false
local function notifyLoennIsOpen()
    if already_checking_loenn_open then return end

    already_checking_loenn_open = true
    -- try debugrc
    local code = [[
        require("selene").load()
        require("selene/selene/wrappers/searcher/love2d/searcher").load()
        require("love.system")

        local args = {...}
        local channelName = unpack(args)
        local channel = love.thread.getChannel(channelName)
        local utils = require("utils")
        local hasRequest, request = utils.tryrequire("lib.luajit-request.luajit-request")
        
        local debugrcWorked = false
        if hasRequest then 
            local response = request.send("http://localhost:32270/aurora_aquir/LoennIsOpen", {timeout = 1}) 
            if response then
                local code = response.code

                if code == 200 then
                    debugrcWorked = true
                end
            end
        end
        
        channel:push({debugrcWorked})
    ]]
    
    return threadHandler.createStartWithCallback(code, function(event)
        already_checking_loenn_open = false
        if not event[1] then
            -- create file instead and remember debugrc failed :D
            DEBUGRC_FAILED = true
            pcall(createLoennIsOpenFile)
        else 
            DEBUGRC_FAILED = false
        end
    end)
end

--[[
    Shoutout to Another Loenn Plugin and Cruor
    Most of the draw code was directly based on their code, since I have absolutely no idea what I am doing
    and after about 3h I have given up on any hope to figure it out.
    (Cruor helped me fix stuff, now uses device and smart draw batch)

    woo debugrc now?
]]

local get_data_debug_rc_blocker = 0
local function getDataDebugRC(full, callbackPlayer, callbackHoldables)
    if get_data_debug_rc_blocker > 0 then return end
    get_data_debug_rc_blocker = 2
    local code = [[
        require("selene").load()
        require("selene/selene/wrappers/searcher/love2d/searcher").load()
        require("love.system")

        local args = {...}
        local channelName, path  = unpack(args)
        local channel = love.thread.getChannel(channelName)
        local utils = require("utils")
        local hasRequest, request = utils.tryrequire("lib.luajit-request.luajit-request")
        
        local data = nil
        if hasRequest then 
            local response = request.send(path)
            if response then
                local code = response.code

                if code == 200 then
                    data = response.body
                end
            end
        end

        channel:push({data})
    ]]

    local reduceBlocker = function(callback)
        
        return function(...)
            get_data_debug_rc_blocker -= 1
            callback(...)
        end

    end

    if full then 
        threadHandler.createStartWithCallback(code, reduceBlocker(callbackPlayer), "http://localhost:32270/aurora_aquir/PlayerStatePath?partial=false")
        threadHandler.createStartWithCallback(code, reduceBlocker(callbackHoldables), "http://localhost:32270/aurora_aquir/HoldableStatePath?partial=false")
    else
        threadHandler.createStartWithCallback(code, reduceBlocker(callbackPlayer), "http://localhost:32270/aurora_aquir/PlayerStatePath?partial=true")
        threadHandler.createStartWithCallback(code, reduceBlocker(callbackHoldables), "http://localhost:32270/aurora_aquir/HoldableStatePath?partial=true")
    end
end

-- Data format:
-- 1st line is amount of lines
-- player: {id},{roomName},{x},{y},{colorHex},{flipX},{flipY}
-- holdable: {id},{roomName},{x},{y},{sprite},{flipX},{flipY}
local function getData(path)
    local f = io.open(utils.joinpath(fileLocations.getCelesteDir(), path), "r")
    if not f then return nil end
    local data = f:read("*all")
    f:close()
    if not data then return nil end
    return data:split("\n")()
end

local function getSprite(x, y, flipX, flipY, colorHex, texture)
    local color = {1, 1, 1, device.OPACITY}
    local success, r, g, b = utils.parseHexColor(colorHex or "ffffff")
    if success then
        color[1] = r
        color[2] = g
        color[3] = b
    end

    local sprite = drawableSprite.fromTexture(texture, {
        scaleX = (flipX and -1 or 1),
        scaleY = (flipY and -1 or 1),
        x = x,
        y = y,
        color = color,
        depth = 0,
        justificationX = 0.5, justificationY = 0.5, -- needed for flipping to work correctly
    })
    if not sprite then return nil end

    -- center bottom -> center center
    sprite.y = sprite.y - ((flipY and -1 or 1) * (sprite.meta.height/2))

    return sprite
end


local playerSilhouetteID = -1
local holdableSilhouetteID = -1
local function getSilhouettes(allSillhouettes, selectedRoom)

    -- sort by room 
    local selectedRoomName = selectedRoom.name
    local selectedRoomSilhouettes = {}

    if allSillhouettes then
         playerSilhouetteID = -1
         holdableSilhouetteID = -1
    end

    if settings.playerSilhouetteEnabled then
        for _, silhouette in ipairs(device.playerSilhouettes) do
            if silhouette.id > playerSilhouetteID and (silhouette.roomName and (silhouette.roomName == selectedRoomName or "lvl_" .. silhouette.roomName == selectedRoomName)) then 
                table.insert(selectedRoomSilhouettes, silhouette.sprite)
                playerSilhouetteID = silhouette.id 
            end
        end
    end
    
    if settings.holdableSilhouetteEnabled then
        for _, silhouette in ipairs(device.holdableSilhouettes) do
            if silhouette.id > holdableSilhouetteID and (silhouette.roomName and (silhouette.roomName == selectedRoomName or "lvl_" .. silhouette.roomName == selectedRoomName)) then 
                table.insert(selectedRoomSilhouettes, silhouette.sprite)
                holdableSilhouetteID = silhouette.id
            end
        end
    end

    return selectedRoomSilhouettes
end

function updateBatch(redrawBatch)
    local selectedRoom = loadedState.getSelectedRoom()
    if not selectedRoom then 
        return 
    end 
    
    local silhouettes = getSilhouettes(redrawBatch, selectedRoom)
    if not silhouettes then    
        return
    end



    if redrawBatch then device.batch:clear() end
    for _, silhouette in ipairs(silhouettes) do
        device.batch:addFromDrawable(silhouette)
    end
end

local playerHighestID = -1
local holdableHighestID = -1
local function updateSilhouettes(redrawBatch, data, player)
    if not data or not data[1] then return end 
    

    if player and settings.playerSilhouetteEnabled then

        local line_one = data[1]:split(",")
        local line_amount = tonumber(line_one[1])
        if not line_amount or line_amount == 0 then 
            return 
        end 
        line_amount += 1
        local partial = line_one[2] == "True"
            
        if not partial then 
            device.playerSilhouettes = {}
            playerHighestID = -1 
            redrawBatch = true
        end

        for i=2, line_amount do
            if data[i] then
                local line = data[i]:split(",")

                local id = tonumber(line[1])

                if id > playerHighestID then 
                    local roomName = line[2]
                    local x = tonumber(line[3])
                    local y = tonumber(line[4])
                    local colorHex = line[5]
                    local flipX = line[6]=="True"
                    local flipY = line[7]=="True"
                    local texture = device.PLAYER_TEXTURE

                    playerHighestID = id

                    local sprite = getSprite(x, y, flipX, flipY, colorHex, texture)

                    if sprite then
                        table.insert(device.playerSilhouettes, {id = id, roomName = roomName, sprite = sprite})
                    end
                end
            end
        end

    elseif not player and settings.holdableSilhouetteEnabled then

        local line_one = data[1]:split(",")
        local line_amount = tonumber(line_one[1])
        if not line_amount or line_amount == 0 then 
            return 
        end 
        line_amount += 1
        local partial = line_one[2] == "True"

        if not partial then 
            device.holdableSilhouettes = {} 
            holdableHighestID = -1
            --redrawBatch = true
        end

        for i=2, line_amount do
            if data[i] then
                local line = data[i]:split(",")

                local id = tonumber(line[1])
                if id > holdableHighestID then 
                    local roomName = line[2]
                    local x = tonumber(line[3])
                    local y = tonumber(line[4])
                    local colorHex = "ffffff"
                    local flipX = line[6]=="True"
                    local flipY = line[7]=="True"
                    local texture = line[5]
                    
                    holdableHighestID = id
                    
                    local sprite = getSprite(x, y, flipX, flipY, colorHex, texture)

                    if sprite then
                        table.insert(device.holdableSilhouettes, {id = id, roomName = roomName, sprite = sprite})
                    end
                end
            end
        end
    end
    updateBatch(redrawBatch)
end

local function updateData(roomSwitched)

    if playerData and holdableData then return end

    local function putData(data, isPlayer) 
        if playerData and isPlayer then return end
        if holdableData and not isPlayer then return end
        if data then
            updateSilhouettes(roomSwitched and isPlayer, data:split("\n")(), isPlayer)
        end
    end

    if not DEBUGRC_FAILED then 
        getDataDebugRC(GET_FULL_DATA, function(event) putData(event[1], true) end, function(event) putData(event[1], false) end)
    else
        local playerData = getData(device.PLAYER_DATA_PATH)
        local holdableData = getData(device.HOLDABLE_DATA_PATH)
        updateSilhouettes(roomSwitched, playerData, true)
        updateSilhouettes(false, holdableData, false)
    end

    GET_FULL_DATA = false
end

function device.draw()
    if not loadedState.map or not device.batch then
        return
    end

    local selectedRoom = loadedState.getSelectedRoom()
    if not selectedRoom then
        return
    end
    --[[
    local canvas
    if not silhouette_canvas then
        silhouette_canvas = love.graphics.newCanvas(canvasWidth, canvasHeight)
    end

    canvas = silhouette_canvas
    canvas:renderTo(function()
        love.graphics.clear(0, 0, 0, 0)
        device.batch:draw()
    end)]]

    local x, y = selectedRoom.x, selectedRoom.y
    viewportHandler.drawRelativeTo(x, y, function()
        --love.graphics.draw(canvas)
        device.batch:draw()
    end)
end

local lastRoomName = nil
local loennIsOpenCounter = 0 -- checks for debugrc every 3 seconds
local timeCount = 0
function device.update(dt)
    --This is to tell the code in c# that we exist :D
    loennIsOpenCounter += dt
    if loennIsOpenCounter > 3 then
       notifyLoennIsOpen()
       loennIsOpenCounter -= 3
    end

    local selectedRoom = loadedState.getSelectedRoom()
    if not selectedRoom then 
        return 
    end
    -- Update very second, or once room is switched
    local roomSwitched = selectedRoom.name ~= lastRoomName
    if not roomSwitched then
        timeCount = timeCount + dt
        if timeCount < device.UPDATE_RATE then
            return
        end
        timeCount = timeCount - device.UPDATE_RATE
    else
        timeCount = 0
        updateBatch(true)
    end

    lastRoomName = selectedRoom.name
    
    if not pcall(updateData, roomSwitched) then
        print("[Aurora's Loenn Plugin/SilhouetteDraw] Updating Silhouette data failed.")
    end
end

function device.quit()
     device.batch:clear() 
     lastRoomName = nil
end
--[[
local function addDevice()
    require("input_device").newInputDevice(
        require("scene_handler").getCurrentScene().inputDevices,
        device
    )
end]]

-- copied from AnotherLoenTool lol thanks!!!
local function checkbox(menu, lang, toggle, active)
  local item = $(menu):find(item -> item[1] == lang)
  if not item then
    item = {}
    table.insert(menu, item)
  end
  item[1] = lang
  item[2] = toggle
  item[3] = "checkbox"
  item[4] = active
end

function device.editorDebugReloadEverything()
    print("[Aurora's Loenn Plugin] Reload Everything was called, this plugin is now broken. Please restart instead.")
    --device.batch:clear()
    --lastRoomName = nil
    --viewportHandler = require("viewport_handler")
    --GET_FULL_DATA = true
end

function device.editorSceneChanged(name, ...)
    if name == "Editor" then
        local scene = sceneHandler.scenes[name]
        --local item = $(scene.inputDevices):find(dev -> dev == device)

        if not scene._firstEnter then
            --inputDevice.newInputDevice(scene.inputDevices, device)
            
            -- delete it or smth idk whats happening
            local key = -1
                for k,v in pairs(scene.inputDevices) do
                    if v == device then
                        key = k
                    end
                end
            if key > 0 then
                scene.inputDevices[key] = device
            else
                -- This is from newInputDevice, I need my device to be at around place 3 so I am just using it directly
                -- This will probably break at some point.
                -- starting from 0.8 should be 4 not 3 apparently
                table.insert(scene.inputDevices, (#scene.inputDevices < 3 and #scene.inputDevices) or 3, device) 
            end
        end
    end
end

local function injectCheckboxes()
    local menubar = require("ui.menubar").menubar
    local viewMenu = $(menubar):find(menu -> menu[1] == "view")[2]
    checkbox(viewMenu, "aurora_aquir_AurorasLoennPlugin_show_playerSilhouette",
                function()
                    settings.playerSilhouetteEnabled = not settings.playerSilhouetteEnabled
                    updateBatch(true)
                end,
                function() return settings.playerSilhouetteEnabled end)
    checkbox(viewMenu, "aurora_aquir_AurorasLoennPlugin_show_holdableSilhouette",
                function()
                    settings.holdableSilhouetteEnabled = not settings.holdableSilhouetteEnabled
                    updateBatch(true)
                end,
                function() return settings.holdableSilhouetteEnabled end)
end

injectCheckboxes()


-- Curtesy of Cruor of how to add a device (so I get draw/update functions)
if sceneHandler._aurorasloennplugin_unloadSeq then sceneHandler._aurorasloennplugin_unloadSeq() end

local _sceneHandlerChangeScene = sceneHandler.changeScene
function sceneHandler.changeScene(name, ...)
    if name == "Editor" then
        local scene = sceneHandler.scenes[name]
        local item = $(scene.inputDevices):find(dev -> dev == device)

        if not scene._firstEnter and not item then
            --inputDevice.newInputDevice(scene.inputDevices, device)

            -- This is from newInputDevice, I need my device to be at around place 3 so I am just using it directly
            -- This will probably break at some point.

            -- starting from 0.8 should be 4 not 3 apparently
            table.insert(scene.inputDevices, (#scene.inputDevices < 4 and #scene.inputDevices) or 4, device) 
        end
    end

    _sceneHandlerChangeScene(name, ...)
end

function _aurorasloennplugin_unloadSeq()
    sceneHandler.changeScene = _sceneHandlerChangeScene
end

return SilhouetteDraw