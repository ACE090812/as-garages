Open = false
local Cur       -- { garage, data }
local OfficerVeh

local function strings()
    local t = {}
    for k, v in pairs(Locales.en) do t[k] = v end
    for k, v in pairs(Locales[Config.Locale] or {}) do t[k] = v end
    return t
end

local function openNui(view, data)
    Open = true
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'open', view = view, data = data, t = strings() })
end

function CloseNui()
    if not Open then return end
    Open = false
    Cur, OfficerVeh = nil, nil
    Preview.stop()
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
end

local function enrich(list)
    for _, v in ipairs(list) do
        local hash = type(v.model) == 'number' and v.model or joaat(v.model or '')
        v.name = VehLabel(v.model)
        v.cls = Config.Classes[GetVehicleClassFromName(hash)] or ''
    end
end

function OpenGarage(g)
    local data = lib.callback.await('asg:getGarage', false, g.id)
    if not data then return Notify('no_access') end
    enrich(data.vehicles)
    Cur = { garage = g, data = data }
    openNui(g.type == 'impound' and 'impound' or 'garage', data)
end

function OpenOfficer(veh)
    local plate = (GetVehicleNumberPlateText(veh) or ''):gsub('^%s+', ''):gsub('%s+$', '')
    local lot, best = Config.DefaultImpound, nil
    local me = GetEntityCoords(cache.ped)
    for id, g in pairs(Garages) do
        if g.type == 'impound' then
            local d = #(me - g.coords)
            if not best or d < best then lot, best = id, d end
        end
    end
    OfficerVeh = { entity = veh, lot = lot }
    openNui('officer', { plate = plate, name = VehLabel(GetEntityModel(veh)), lot = lot })
end

local function findVehicle(plate)
    if not Cur then return end
    for _, v in ipairs(Cur.data.vehicles) do
        if v.plate == plate then return v end
    end
end

local function reply(cb, ok, key, extra)
    if not ok and key then Notify(key, extra) end
    cb({ ok = ok })
end

RegisterNUICallback('close', function(_, cb)
    CloseNui()
    cb({})
end)

RegisterNUICallback('takeOut', function(body, cb)
    local g = Cur and Cur.garage
    if not g then return cb({}) end
    local bay = FindBay(g)
    if not bay then Notify('blocked') return cb({ ok = false }) end
    local ok, res = lib.callback.await('asg:takeOut', false, g.id, body.plate, bay)
    if not ok then return reply(cb, false, res) end
    local label = VehLabel(res.model)
    CloseNui()
    cb({ ok = true })
    if SpawnVehicle(res) then Notify('taken_out', label) end
end)

RegisterNUICallback('retrieve', function(body, cb)
    local g = Cur and Cur.garage
    if not g then return cb({}) end
    local bay = FindBay(g)
    if not bay then Notify('blocked') return cb({ ok = false }) end
    local ok, res, fee = lib.callback.await('asg:retrieve', false, g.id, body.plate, bay)
    if not ok then return reply(cb, false, res, fee) end
    local label = VehLabel(res.model)
    CloseNui()
    cb({ ok = true })
    if SpawnVehicle(res) then Notify('retrieved', label) end
end)

RegisterNUICallback('fav', function(body, cb)
    cb({ ok = lib.callback.await('asg:fav', false, body.plate) })
end)

RegisterNUICallback('locate', function(body, cb)
    local pos = lib.callback.await('asg:locate', false, body.plate)
    local v = findVehicle(body.plate)
    if not pos then Notify('vehicle_not_found') return cb({ ok = false }) end
    SetNewWaypoint(pos.x, pos.y)
    Notify('waypoint_set', v and v.name or body.plate)
    cb({ ok = true })
end)

RegisterNUICallback('preview', function(body, cb)
    local v = findVehicle(body.plate)
    if v and Cur then Preview.show(Cur.garage, v.model) end
    cb({})
end)

RegisterNUICallback('rotate', function(body, cb)
    Preview.rotate(body.dx)
    cb({})
end)

RegisterNUICallback('impound', function(body, cb)
    if not OfficerVeh or not DoesEntityExist(OfficerVeh.entity) then CloseNui() return cb({}) end
    local veh, lot = OfficerVeh.entity, OfficerVeh.lot
    local props = lib.getVehicleProperties(veh)
    local ok, key, plate = lib.callback.await('asg:impound', false, NetworkGetNetworkIdFromEntity(veh), {
        reason = body.reason, fee = body.fee, hold = body.hold, ownerRelease = body.ownerRelease, lot = lot,
    }, props)
    CloseNui()
    cb({ ok = ok })
    Notify(key or 'unavailable', plate or VehLabel(props.model))
end)
