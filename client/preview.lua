-- Showroom-style 3D preview: a local, frozen copy of the vehicle shown at garage.preview
-- with a scripted camera. The NUI drag rotates it.
Preview = {}

local veh, cam

function Preview.removeVehicle()
    if veh and DoesEntityExist(veh) then DeleteEntity(veh) end
    veh = nil
end

function Preview.show(g, model)
    if not g or not g.preview then return end
    local hash = type(model) == 'number' and model or joaat(model or '')
    if not IsModelInCdimage(hash) then return end
    if not pcall(lib.requestModel, hash, 5000) then return end

    Preview.removeVehicle()
    local p = g.preview
    veh = CreateVehicle(hash, p.x, p.y, p.z, p.w, false, false)
    SetModelAsNoLongerNeeded(hash)
    if not veh or veh == 0 then veh = nil return end

    SetVehicleOnGroundProperly(veh)
    SetEntityCollision(veh, false, false)
    FreezeEntityPosition(veh, true)
    SetEntityInvincible(veh, true)
    SetVehicleDoorsLocked(veh, 2)

    if not cam then
        cam = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
        local o = GetOffsetFromEntityInWorldCoords(veh, 3.6, 5.8, 1.5)
        SetCamCoord(cam, o.x, o.y, o.z)
        PointCamAtCoord(cam, p.x, p.y, p.z + 0.6)
        SetCamActive(cam, true)
        RenderScriptCams(true, true, 600, true, true)
    end
end

function Preview.rotate(dx)
    if veh and DoesEntityExist(veh) then
        SetEntityHeading(veh, GetEntityHeading(veh) + (tonumber(dx) or 0) * 0.4)
    end
end

function Preview.stop()
    Preview.removeVehicle()
    if cam then
        RenderScriptCams(false, true, 500, true, true)
        DestroyCam(cam, false)
        cam = nil
    end
end

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then Preview.stop() end
end)
