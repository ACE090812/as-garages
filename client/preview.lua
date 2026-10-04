-- Showroom-style 3D preview. Either a local, frozen copy of the vehicle at garage.preview
-- (Preview.show) or a real showroom car inside a walk-in interior (Preview.focus), with a
-- scripted camera that has several modes, an optional turntable and headlights.
Preview = {}

local MODES = { 'front', 'side', 'rear', 'cabin', 'engine', 'wheel' }
Preview.modes = MODES

local owned        -- vehicle created by the preview (deleted on stop)
local target       -- vehicle the camera looks at (owned or a showroom car)
local cam, mode = nil, 'front'
local spin, lights = Config.Preview.spin, Config.Preview.lights
local lastDrag = 0
local running = false

local function dims(veh)
    local min, max = GetModelDimensions(GetEntityModel(veh))
    return max.x - min.x, max.y - min.y, max.z - min.z
end

-- Camera position and look-at point for a mode, both relative to the vehicle.
local function layout(veh, m)
    local W, L, H = dims(veh)
    if m == 'side' then
        return vec3(W * 0.5 + L * 0.9 + 1.0, 0.0, H * 0.7 + 0.2), vec3(0.0, 0.0, H * 0.45)
    elseif m == 'rear' then
        return vec3(-W * 0.9, -(L * 0.5 + 3.0), H * 0.9 + 0.3), vec3(0.0, -L * 0.2, H * 0.4)
    elseif m == 'cabin' then
        return vec3(-W * 0.18, L * 0.04, H * 0.62), vec3(-W * 0.1, L * 0.5 + 5.0, H * 0.55)
    elseif m == 'engine' then
        return vec3(0.0, L * 0.55 + 2.2, H * 1.5 + 1.0), vec3(0.0, L * 0.3, H * 0.45)
    elseif m == 'wheel' then
        local bone = GetEntityBoneIndexByName(veh, 'wheel_lf')
        if bone ~= -1 then
            local b = GetOffsetFromEntityGivenWorldCoords(veh, GetWorldPositionOfEntityBone(veh, bone))
            return vec3(b.x - 1.8, b.y + 0.6, b.z + 0.4), b
        end
    end
    return vec3(W * 1.6 + 1.5, L * 1.0 + 1.5, H * 0.8 + 0.4), vec3(0.0, 0.0, H * 0.4) -- front three-quarter
end

local function applyCam(instant)
    if not target or not DoesEntityExist(target) then return end
    local pos, look = layout(target, mode)
    local p = GetOffsetFromEntityInWorldCoords(target, pos.x, pos.y, pos.z)
    local l = GetOffsetFromEntityInWorldCoords(target, look.x, look.y, look.z)

    local old = cam
    cam = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
    SetCamCoord(cam, p.x, p.y, p.z)
    PointCamAtCoord(cam, l.x, l.y, l.z)
    SetCamFov(cam, mode == 'cabin' and 70.0 or 50.0)
    SetCamActive(cam, true)
    if old and not instant then
        SetCamActiveWithInterp(cam, old, 700, 1, 1)
        local oldCam = old
        SetTimeout(800, function() if DoesCamExist(oldCam) then DestroyCam(oldCam, false) end end)
    else
        if old then DestroyCam(old, false) end
        RenderScriptCams(true, true, 600, true, true)
    end
end

local function applyLooks()
    if not target or not DoesEntityExist(target) then return end
    SetVehicleLights(target, lights and 2 or 0)
    SetVehicleInteriorlight(target, lights)
    if mode == 'engine' then SetVehicleDoorOpen(target, 4, false, false) else SetVehicleDoorShut(target, 4, false) end
end

-- Slow turntable for the preview-owned vehicle while the player is not dragging it.
local function startLoop()
    if running then return end
    running = true
    CreateThread(function()
        local last = GetGameTimer()
        while running do
            Wait(0)
            local now = GetGameTimer()
            local dt = (now - last) / 1000.0
            last = now
            if spin and owned and DoesEntityExist(owned) and now - lastDrag > 2500 then
                SetEntityHeading(owned, GetEntityHeading(owned) + Config.Preview.spinSpeed * dt)
            end
        end
    end)
end

function Preview.removeVehicle()
    if owned and DoesEntityExist(owned) then DeleteEntity(owned) end
    owned = nil
end

local function setTarget(veh, keepMode)
    target = veh
    if not keepMode then mode = 'front' end
    applyLooks()
    applyCam(cam ~= nil)
    startLoop()
end

function Preview.show(g, model, props)
    if not g or not g.preview then return end
    local hash = type(model) == 'number' and model or joaat(model or '')
    if not IsModelInCdimage(hash) then return end
    if not pcall(lib.requestModel, hash, 5000) then return end

    Preview.removeVehicle()
    local p = g.preview
    local veh = CreateVehicle(hash, p.x, p.y, p.z, p.w, false, false)
    SetModelAsNoLongerNeeded(hash)
    if not veh or veh == 0 then return end

    if props then lib.setVehicleProperties(veh, props) end
    SetVehicleOnGroundProperly(veh)
    SetEntityCollision(veh, false, false)
    FreezeEntityPosition(veh, true)
    SetEntityInvincible(veh, true)
    SetVehicleDoorsLocked(veh, 2)
    owned = veh
    setTarget(veh, true)
end

-- Look at a showroom car that already exists (walk-in interiors).
function Preview.focus(veh)
    if not veh or not DoesEntityExist(veh) then return end
    Preview.removeVehicle()
    setTarget(veh, true)
end

function Preview.setMode(m)
    for _, name in ipairs(MODES) do
        if name == m then
            mode = m
            applyLooks()
            applyCam(false)
            return
        end
    end
end

function Preview.setOption(key, value)
    if key == 'spin' then spin = value == true end
    if key == 'lights' then lights = value == true applyLooks() end
end

function Preview.rotate(dx)
    lastDrag = GetGameTimer()
    local veh = owned or target
    if veh and DoesEntityExist(veh) then
        SetEntityHeading(veh, GetEntityHeading(veh) + (tonumber(dx) or 0) * 0.4)
    end
end

function Preview.stop()
    running = false
    if target and DoesEntityExist(target) then SetVehicleDoorShut(target, 4, false) end
    Preview.removeVehicle()
    target = nil
    if cam then
        RenderScriptCams(false, true, 500, true, true)
        DestroyCam(cam, false)
        cam = nil
    end
    mode = 'front'
    spin, lights = Config.Preview.spin, Config.Preview.lights
end

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then Preview.stop() end
end)
