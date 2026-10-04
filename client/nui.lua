Open = false
local Cur       -- { garage, data }
local OfficerVeh
local PropsCache = {}
local previewToken = 0

-- Game UI sounds. Set Config.Sounds = false to silence them.
local SOUNDS = {
    select = { 'NAV_UP_DOWN', 'HUD_FRONTEND_DEFAULT_SOUNDSET' },
    confirm = { 'SELECT', 'HUD_FRONTEND_DEFAULT_SOUNDSET' },
    back = { 'BACK', 'HUD_FRONTEND_DEFAULT_SOUNDSET' },
    error = { 'ERROR', 'HUD_FRONTEND_DEFAULT_SOUNDSET' },
}
function Sfx(kind)
    local s = Config.Sounds and SOUNDS[kind]
    if s then PlaySoundFrontend(-1, s[1], s[2], true) end
end

function Strings()
    local t = {}
    for k, v in pairs(Locales.en) do t[k] = v end
    for k, v in pairs(Locales[Config.Locale] or {}) do t[k] = v end
    return t
end

function OpenNui(view, data)
    Open = true
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'open', view = view, data = data, t = Strings(), theme = Config.Theme, sounds = Config.Sounds })
    Sfx('confirm')
end

function CloseNui()
    if not Open then return end
    Open = false
    Cur, OfficerVeh = nil, nil
    PropsCache = {}
    previewToken = previewToken + 1
    Preview.stop()
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
end

local function enrich(list)
    for _, v in ipairs(list) do
        local hash = type(v.model) == 'number' and v.model or joaat(v.model or '')
        local label = VehLabel(v.model)
        local class = Config.Classes[GetVehicleClassFromName(hash)] or ''
        v.name = (v.nick and v.nick ~= '') and v.nick or label
        v.cls = (v.nick and v.nick ~= '') and (label .. (class ~= '' and ' · ' .. class or '')) or class
        v.label = label
    end
end

function OpenGarage(g)
    local data = lib.callback.await('asg:getGarage', false, g.id)
    if not data then return Notify('no_access') end
    if data.forSale then return BuyGarage(g) end
    enrich(data.vehicles)
    Cur = { garage = g, data = data }
    OpenNui(g.type == 'impound' and 'impound' or 'garage', data)
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
    OpenNui('officer', { plate = plate, name = VehLabel(GetEntityModel(veh)), lot = lot })
end

local function findVehicle(plate)
    if not Cur then return end
    for i, v in ipairs(Cur.data.vehicles) do
        if v.plate == plate then return v, i end
    end
end

local function reply(cb, ok, key, extra)
    if not ok then
        Sfx('error')
        if key then Notify(key, extra) end
    end
    cb({ ok = ok })
end

local function nearbyPlayers()
    local out = {}
    for _, p in ipairs(lib.getNearbyPlayers(GetEntityCoords(cache.ped), 10.0, false)) do
        local id = GetPlayerServerId(p.id)
        out[#out + 1] = { id = id, label = 'ID ' .. id }
    end
    return out
end

RegisterNUICallback('close', function(_, cb)
    Sfx('back')
    CloseNui()
    cb({})
end)

RegisterNUICallback('sfx', function(body, cb)
    Sfx(body.kind)
    cb({})
end)

RegisterNUICallback('takeOut', function(body, cb)
    local g = Cur and Cur.garage
    if not g then return cb({}) end
    local bay = FindBay(g)
    if not bay then Notify('blocked') return reply(cb, false) end
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
    if not bay then Notify('blocked') return reply(cb, false) end
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
    if not pos then Notify('vehicle_not_found') return reply(cb, false) end
    SetNewWaypoint(pos.x, pos.y)
    Notify('waypoint_set', v and v.name or body.plate)
    cb({ ok = true })
end)

-- 3D preview, with the vehicle's real mods once the server has handed them over.
RegisterNUICallback('preview', function(body, cb)
    cb({})
    local v = findVehicle(body.plate)
    if not v or not Cur then return end
    previewToken = previewToken + 1
    local token, g = previewToken, Cur.garage

    local props = PropsCache[body.plate]
    if props == nil then
        Preview.show(g, v.model) -- instant stock model while the mods load
        props = lib.callback.await('asg:props', false, g.id, body.plate) or false
        PropsCache[body.plate] = props
    end
    if token == previewToken and Cur and Cur.garage.id == g.id and props then
        Preview.show(g, v.model, props)
    elseif token == previewToken and Cur and not props then
        Preview.show(g, v.model)
    end
end)

RegisterNUICallback('rotate', function(body, cb)
    Preview.rotate(body.dx)
    cb({})
end)

RegisterNUICallback('rename', function(body, cb)
    local ok, nick = lib.callback.await('asg:rename', false, body.plate, body.name)
    if not ok then return reply(cb, false, nick) end
    local v = findVehicle(body.plate)
    if v then
        v.nick = nick ~= '' and nick or nil
        v.name = v.nick or v.label
        local hash = type(v.model) == 'number' and v.model or joaat(v.model or '')
        local class = Config.Classes[GetVehicleClassFromName(hash)] or ''
        v.cls = v.nick and (v.label .. (class ~= '' and ' · ' .. class or '')) or class
    end
    Notify('renamed', nick ~= '' and nick or (v and v.label or body.plate))
    cb({ ok = true, name = v and v.name, cls = v and v.cls })
end)

RegisterNUICallback('targets', function(_, cb)
    local out = {}
    for id, g in pairs(Garages) do
        if Cur and id ~= Cur.garage.id and g.type ~= 'impound' and not g.forSale then
            out[#out + 1] = { id = id, label = g.label, fee = Config.TransferFee }
        end
    end
    table.sort(out, function(a, b) return a.label < b.label end)
    cb(out)
end)

RegisterNUICallback('transfer', function(body, cb)
    local g = Cur and Cur.garage
    if not g then return cb({}) end
    local ok, label, fee = lib.callback.await('asg:transfer', false, body.plate, g.id, body.to)
    if not ok then return reply(cb, false, label, fee) end
    local v = findVehicle(body.plate)
    if v then v.status, v.at = 'away', label end
    Notify('transfer_ok', v and v.name or body.plate, label)
    cb({ ok = true, at = label })
end)

RegisterNUICallback('nearby', function(_, cb)
    cb(nearbyPlayers())
end)

RegisterNUICallback('sell', function(body, cb)
    local g = Cur and Cur.garage
    if not g then return cb({}) end
    local ok, plate, price = lib.callback.await('asg:sell', false, g.id, body.plate, body.buyer, body.price)
    if not ok then return reply(cb, false, plate) end
    local v, i = findVehicle(body.plate)
    local name = v and v.name or body.plate
    if i then table.remove(Cur.data.vehicles, i) end
    Sfx('confirm')
    Notify('sold_to', name, price)
    cb({ ok = true })
end)

-- Private garage owner: manage who can use it, with ox_lib menus.
local function accessMenu(gid)
    local members = lib.callback.await('asg:members', false, gid) or {}
    local options = {{
        title = L('add_member'), icon = 'user-plus',
        onSelect = function()
            local near = nearbyPlayers()
            if #near == 0 then Notify('nobody_near') return accessMenu(gid) end
            local opts = {}
            for i, p in ipairs(near) do opts[i] = { value = p.id, label = p.label } end
            local input = lib.inputDialog(L('add_member'), { { type = 'select', label = L('add_member_input'), options = opts, required = true } })
            if input then
                local ok, res = lib.callback.await('asg:addMember', false, gid, input[1])
                if ok then Notify('member_added', res) else Notify(res) end
            end
            accessMenu(gid)
        end,
    }}
    for _, m in ipairs(members) do
        options[#options + 1] = {
            title = L('remove_member', m.name or m.identifier), icon = 'user-minus',
            onSelect = function()
                lib.callback.await('asg:removeMember', false, gid, m.identifier)
                Notify('member_removed')
                accessMenu(gid)
            end,
        }
    end
    if #members == 0 then options[#options + 1] = { title = L('no_members'), disabled = true } end
    lib.registerContext({ id = 'asg_access', title = L('access_title'), options = options })
    lib.showContext('asg_access')
end

RegisterNUICallback('access', function(_, cb)
    local g = Cur and Cur.garage
    cb({})
    if not g then return end
    CloseNui()
    accessMenu(g.id)
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
