-- Walk-in interiors: fade in, stand inside the garage with the player's vehicles parked in a
-- showroom. Browse with the console (the entry point) and take a vehicle out to drive away.
Interior = nil -- { garage, entities = { [plate] = vehicle }, interiorId }

local function fade(out)
    if out then
        DoScreenFadeOut(500)
        while not IsScreenFadedOut() do Wait(0) end
    else
        DoScreenFadeIn(500)
    end
end

local function spawnShowroom(g, list)
    local entities = {}
    for idx, v in ipairs(list) do
        local bay = g.interior.bays[idx]
        if not bay then break end
        local hash = type(v.model) == 'number' and v.model or joaat(v.model or '')
        if IsModelInCdimage(hash) and pcall(lib.requestModel, hash, 5000) then
            local veh = CreateVehicle(hash, bay.x, bay.y, bay.z, bay.w, false, false)
            SetModelAsNoLongerNeeded(hash)
            if veh and veh ~= 0 then
                lib.setVehicleProperties(veh, v.props)
                SetVehicleOnGroundProperly(veh)
                SetEntityInvincible(veh, true)
                FreezeEntityPosition(veh, true)
                SetVehicleDoorsLocked(veh, 2)
                entities[v.plate] = veh
            end
        end
    end
    return entities
end

local function clearShowroom()
    if not Interior then return end
    for _, veh in pairs(Interior.entities) do
        if DoesEntityExist(veh) then DeleteEntity(veh) end
    end
end

function IsInInterior() return Interior ~= nil end
function ShowroomVehicle(plate) return Interior and Interior.entities[plate] end

function ExitInterior()
    if not Interior then return end
    local g = Interior.garage
    Preview.stop()
    fade(true)
    clearShowroom()
    lib.callback.await('asg:interior:exit', false)
    Interior = nil
    local c = g.coords
    SetEntityCoordsNoOffset(cache.ped, c.x, c.y, c.z, false, false, false)
    Wait(300)
    fade(false)
end

local function interiorLoop()
    CreateThread(function()
        while Interior do
            Wait(0)
            local i = Interior.garage.interior
            local me = GetEntityCoords(cache.ped)
            DrawMarker(1, i.exit.x, i.exit.y, i.exit.z - 0.95, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.2, 1.2, 0.5, 255, 122, 112, 150, false, false, 2, false, nil, nil, false)
            DrawMarker(27, i.enter.x, i.enter.y, i.enter.z - 0.95, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.4, 1.4, 0.5, 165, 148, 255, 150, false, false, 2, false, nil, nil, false)
            local text
            if not Open then
                if #(me - i.exit) < 1.5 then text = L('leave_garage')
                elseif #(me - vec3(i.enter.x, i.enter.y, i.enter.z)) < 2.0 then text = L('browse_vehicles') end
            end
            if text ~= Interior.prompt then
                Interior.prompt = text
                if text then lib.showTextUI(text) else lib.hideTextUI() end
            end
            if text and IsControlJustPressed(0, 38) then
                lib.hideTextUI()
                Interior.prompt = nil
                if text == L('leave_garage') then ExitInterior() else OpenGarage(Interior.garage) end
            end
        end
    end)
end

function EnterInterior(g)
    local res = lib.callback.await('asg:interior:enter', false, g.id)
    if not res then return Notify('no_access') end

    local i = g.interior
    fade(true)
    if i.ipl then RequestIpl(i.ipl) end
    RequestCollisionAtCoord(i.enter.x, i.enter.y, i.enter.z)
    SetEntityCoordsNoOffset(cache.ped, i.enter.x, i.enter.y, i.enter.z, false, false, false)
    SetEntityHeading(cache.ped, i.enter.w)

    local id = GetInteriorAtCoords(i.enter.x, i.enter.y, i.enter.z)
    if id ~= 0 then
        PinInteriorInMemory(id)
        for _, set in ipairs(i.entitySets or {}) do ActivateInteriorEntitySet(id, set) end
        RefreshInterior(id)
        local t = GetGameTimer()
        while not IsInteriorReady(id) and GetGameTimer() - t < 5000 do Wait(50) end
    end
    Wait(300)

    Interior = { garage = g, entities = spawnShowroom(g, res.vehicles), interiorId = id }
    fade(false)
    interiorLoop()
end

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() or not Interior then return end
    clearShowroom()
    lib.hideTextUI()
end)
