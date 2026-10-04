-- Admin editor: opened with /asgarage. The server re-checks permission on every call.

RegisterNetEvent('asg:admin:open', function()
    if Open then return end
    local data = lib.callback.await('asg:admin:data', false)
    if not data then
        return lib.notify({ description = L('not_allowed'), type = 'error' })
    end
    OpenNui('admin', data)
end)

local function call(name, ...)
    return lib.callback.await(name, false, ...)
end

RegisterNUICallback('adminData', function(_, cb) cb(call('asg:admin:data') or {}) end)

RegisterNUICallback('adminSave', function(body, cb)
    local ok, msg = call('asg:admin:save', body)
    cb({ ok = ok, msg = msg })
    if ok then RefreshGarages() end
end)

RegisterNUICallback('adminDelete', function(body, cb)
    local ok, msg = call('asg:admin:delete', body.id)
    cb({ ok = ok, msg = msg })
    if ok then RefreshGarages() end
end)

RegisterNUICallback('adminClearOwner', function(body, cb)
    local ok, msg = call('asg:admin:clearOwner', body.id)
    cb({ ok = ok, msg = msg })
end)

RegisterNUICallback('adminVehicles', function(body, cb) cb(call('asg:admin:vehicles', body.query) or {}) end)

RegisterNUICallback('adminForce', function(body, cb)
    local ok, msg = call('asg:admin:force', body.plate, body.garage)
    cb({ ok = ok, msg = msg })
end)

RegisterNUICallback('adminLogs', function(body, cb) cb(call('asg:admin:logs', body.query) or {}) end)

RegisterNUICallback('adminGoto', function(body, cb)
    local x, y, z = tonumber(body.x), tonumber(body.y), tonumber(body.z)
    if x and y and z then
        local ent = cache.vehicle or cache.ped
        SetEntityCoords(ent, x, y, z + 0.5, false, false, false, false)
    end
    cb({})
end)

-- Placement mode: the editor hides, the admin walks (or drives) to the spot and presses E.
-- Replies with the position (and heading) or { cancel = true }.
RegisterNUICallback('adminPlace', function(body, cb)
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'hide' })
    lib.showTextUI(('[E] Place %s   [BACKSPACE] Cancel'):format(body.label or 'point'))

    local result
    while true do
        Wait(0)
        local ent = cache.vehicle or cache.ped
        local c, h = GetEntityCoords(ent), GetEntityHeading(ent)
        local z = cache.vehicle and c.z or c.z - 0.95
        DrawMarker(1, c.x, c.y, z, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.4, 1.4, 0.6, 165, 148, 255, 160, false, false, 2, false, nil, nil, false)
        if IsControlJustPressed(0, 38) then
            result = { x = c.x, y = c.y, z = z, w = h }
            break
        end
        if IsControlJustPressed(0, 177) or IsControlJustPressed(0, 202) then break end
    end

    lib.hideTextUI()
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'show' })
    cb(result or { cancel = true })
end)

RegisterNUICallback('adminStats', function(_, cb) cb(call('asg:admin:stats') or {}) end)

RegisterNUICallback('adminTool', function(body, cb)
    local ok, msg, list = call('asg:admin:tool', body.kind, body.args)
    cb({ ok = ok, msg = msg, list = list })
    if ok and (body.kind == 'moveGarage' or body.kind == 'releaseOldImpounds') then RefreshGarages() end
end)

RegisterNUICallback('adminExport', function(_, cb) cb({ text = call('asg:admin:export') or '' }) end)

RegisterNUICallback('adminImport', function(body, cb)
    local ok, msg = call('asg:admin:import', body.text)
    cb({ ok = ok, msg = msg })
    if ok then RefreshGarages() end
end)
